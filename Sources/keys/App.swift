#if os(macOS)
import AppKit
import Foundation
import KeysCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var keyboardPacks: [SoundPack] = []
    @Published var mousePacks: [SoundPack] = []
    @Published var problem: String?
    @Published var inputOn = false
    @Published var accessOn = false
    var onSettingsChange: (() -> Void)?

    let session = Session()
    let input = InputMonitor()
    private var bundled: [SoundPack] = []
    private var userPacks: [SoundPack] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? decodeSettings(data) {
            settings = decoded
        } else {
            settings = .standard
        }
    }

    func start() {
        session.updateSettings(settings)
        reload()
        input.onEvent = { [weak self] event in
            self?.session.handle(event)
        }
        input.start()
        refreshPermissions()
    }

    func toggleMute() {
        settings.muted.toggle()
        persist()
    }

    func setVolume(_ volume: Double) {
        settings.volume = volume
        settings = settings.normalized()
        persist()
    }

    func selectKeyboard(_ id: String) {
        settings.keyboardPackId = id
        persist()
        applySelection()
    }

    func selectMouse(_ id: String) {
        settings.mousePackId = id
        persist()
        applySelection()
    }

    func reload() {
        let bundledScan = scanPacks(at: bundledPacksURL())
        let userScan = scanPacks(at: userPacksURL())
        bundled = bundledScan.packs
        userPacks = userScan.packs
        var merged: [String: SoundPack] = [:]
        for pack in bundled + userPacks {
            merged[pack.id] = pack
        }
        let packs = merged.values.sorted { $0.name < $1.name }
        keyboardPacks = packs.filter { $0.kind == .keyboard }
        mousePacks = packs.filter { $0.kind == .mouse }
        let errors = bundledScan.errors + userScan.errors
        problem = errors.first
        if !keyboardPacks.contains(where: { $0.id == settings.keyboardPackId }) {
            settings.keyboardPackId = keyboardPacks.first?.id ?? settings.keyboardPackId
        }
        if !mousePacks.contains(where: { $0.id == settings.mousePackId }) {
            settings.mousePackId = mousePacks.first?.id ?? settings.mousePackId
        }
        persist()
        applySelection()
    }

    func refreshPermissions() {
        inputOn = input.inputMonitoringGranted()
        accessOn = input.accessibilityGranted()
    }

    func allowInput() {
        input.requestInputMonitoring()
        refreshPermissions()
    }

    func allowAccess() {
        input.requestAccessibility()
        refreshPermissions()
    }

    func openPacksFolder() {
        let url = userPacksURL()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func stopInput() {
        input.stop()
    }

    func quit() {
        stopInput()
        NSApp.terminate(nil)
    }

    private func applySelection() {
        let keyboard = keyboardPacks.first { $0.id == settings.keyboardPackId }
        let mouse = mousePacks.first { $0.id == settings.mousePackId }
        let keyboardProblem = session.use(keyboard: keyboard)
        let mouseProblem = session.use(mouse: mouse)
        if problem == nil {
            problem = keyboardProblem ?? mouseProblem
        }
        if !session.player.running {
            problem = problem ?? "Audio did not start"
        }
    }

    private func persist() {
        settings = settings.normalized()
        session.updateSettings(settings)
        if let data = try? encodeSettings(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        onSettingsChange?()
    }

    private func bundledPacksURL() -> URL {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("packs"),
           FileManager.default.fileExists(atPath: resource.path) {
            return resource
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("packs")
        return cwd
    }

    private func userPacksURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("keys/packs", isDirectory: true)
    }

    private static let defaultsKey = "settings"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private var popover: NSPopover!
    private let model = AppModel()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = menuImage()
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "keys"
        }
        let host = NSHostingController(rootView: PopoverView(model: model))
        popover = NSPopover()
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 280, height: 460)
        popover.behavior = .transient
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor(
            srgbRed: 28.0 / 255,
            green: 28.0 / 255,
            blue: 28.0 / 255,
            alpha: 1
        ).cgColor
        model.onSettingsChange = { [weak self] in
            self?.updateIcon()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let shown = self.popover.isShown
            Task { @MainActor in
                if shown { self.model.refreshPermissions() }
                self.status.button?.appearsDisabled = self.model.settings.muted
            }
        }
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            model.stopInput()
        }
    }

    @objc private func togglePopover() {
        guard let button = status.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            Task { @MainActor in
                self.model.refreshPermissions()
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        updateIcon()
    }

    private func updateIcon() {
        status.button?.appearsDisabled = model.settings.muted
    }

    private func menuImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let cap = rect.insetBy(dx: 3, dy: 4)
            let path = NSBezierPath(roundedRect: cap, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.4
            NSColor.black.setStroke()
            path.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 7, width: 2, height: 2)).fill()
            return true
        }
    }
}
#endif
