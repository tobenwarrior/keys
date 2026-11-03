#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct HardwareEvent {
    enum Kind {
        case key(Int)
        case mouse(String)
    }

    var kind: Kind
    var down: Bool
    var autorepeat: Bool
}

/// Hears key and mouse presses. The code is used only to pick a sound.
/// It is not written to disk or the console.
final class InputMonitor {
    var onEvent: ((HardwareEvent) -> Void)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private var thread: Thread?
    private var local: Any?

    func start() {
        stop()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }
            self.installTap()
            self.loop = CFRunLoopGetCurrent()
            ready.signal()
            if self.port != nil {
                CFRunLoopRun()
            }
        }
        thread.qualityOfService = .userInteractive
        thread.name = "keys.input"
        self.thread = thread
        thread.start()
        ready.wait()
        if port == nil {
            installLocal()
        }
    }

    func stop() {
        if let loop {
            CFRunLoopStop(loop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        port = nil
        source = nil
        loop = nil
        thread = nil
        if let local {
            NSEvent.removeMonitor(local)
            self.local = nil
        }
    }

    func inputMonitoringGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestInputMonitoring() {
        CGRequestListenEventAccess()
        openPrivacy("ListenEvent")
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
    }

    private func openPrivacy(_ pane: String) {
        let links = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_\(pane)",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)"
        ]
        for link in links {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private func installTap() {
        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .keyDown, .keyUp,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]
        for type in types {
            mask |= 1 << type.rawValue
        }
        let user = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, user in
                guard let user else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<InputMonitor>.fromOpaque(user).takeUnretainedValue()
                monitor.receive(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: user
        ) else { return }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func installLocal() {
        local = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        ) { [weak self] event in
            self?.receive(nsEvent: event)
            return event
        }
    }

    private func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }
        switch type {
        case .keyDown, .keyUp:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            onEvent?(HardwareEvent(kind: .key(code), down: type == .keyDown, autorepeat: repeated))
        case .leftMouseDown, .leftMouseUp:
            emitMouse(button: 0, down: type == .leftMouseDown)
        case .rightMouseDown, .rightMouseUp:
            emitMouse(button: 1, down: type == .rightMouseDown)
        case .otherMouseDown, .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            emitMouse(button: button, down: type == .otherMouseDown)
        default:
            break
        }
    }

    private func receive(nsEvent: NSEvent) {
        switch nsEvent.type {
        case .keyDown, .keyUp:
            onEvent?(HardwareEvent(
                kind: .key(Int(nsEvent.keyCode)),
                down: nsEvent.type == .keyDown,
                autorepeat: nsEvent.isARepeat
            ))
        case .leftMouseDown, .leftMouseUp:
            emitMouse(button: 0, down: nsEvent.type == .leftMouseDown)
        case .rightMouseDown, .rightMouseUp:
            emitMouse(button: 1, down: nsEvent.type == .rightMouseDown)
        case .otherMouseDown, .otherMouseUp:
            emitMouse(button: Int(nsEvent.buttonNumber), down: nsEvent.type == .otherMouseDown)
        default:
            break
        }
    }

    private func emitMouse(button: Int, down: Bool) {
        guard let name = mouseControl(button: button) else { return }
        onEvent?(HardwareEvent(kind: .mouse(name), down: down, autorepeat: false))
    }
}
#endif
