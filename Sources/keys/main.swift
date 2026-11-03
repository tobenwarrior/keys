import Foundation

#if os(macOS)
import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
#else
fputs("keys is a macOS menu bar app. Build it on a Mac with make.\n", stderr)
exit(1)
#endif
