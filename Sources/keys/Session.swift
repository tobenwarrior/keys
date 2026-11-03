#if os(macOS)
import Foundation
import KeysCore

/// Playback state shared by the menu and the input thread.
/// Settings here are volume, mute, and the selected packs. Keystrokes are not stored.
final class Session {
    let player = SoundPlayer()
    private let lock = NSLock()
    private var settings = AppSettings.standard
    private var keyboard: SoundPack?
    private var mouse: SoundPack?
    private var rates: [String: Double] = [:]
    private var frames: [String: Int] = [:]

    func updateSettings(_ settings: AppSettings) {
        let settings = settings.normalized()
        lock.lock()
        self.settings = settings
        lock.unlock()
        player.setVolume(settings.volume)
    }

    func use(keyboard: SoundPack?) -> String? {
        let problem = install(keyboard, clear: .keyboard)
        lock.lock()
        self.keyboard = keyboard
        lock.unlock()
        return problem
    }

    func use(mouse: SoundPack?) -> String? {
        let problem = install(mouse, clear: .mouse)
        lock.lock()
        self.mouse = mouse
        lock.unlock()
        return problem
    }

    func handle(_ event: HardwareEvent) {
        lock.lock()
        let settings = self.settings
        let keyboard = self.keyboard
        let mouse = self.mouse
        lock.unlock()
        guard playbackAllowed(settings), acceptPress(autorepeat: event.autorepeat) else { return }
        switch event.kind {
        case .key(let code):
            guard let name = controlName(macKeyCode: code), let pack = keyboard else { return }
            guard let clip = resolve(pack: pack, control: name, down: event.down) else { return }
            play(clip)
        case .mouse(let name):
            guard let pack = mouse else { return }
            guard let clip = resolve(pack: pack, control: name, down: event.down) else { return }
            play(clip)
        }
    }

    private func play(_ clip: ResolvedClip) {
        let path = clip.file.path
        guard let rate = rates[path], let count = frames[path] else { return }
        player.play(clip, sampleRate: rate, frameCount: count)
    }

    private func install(_ pack: SoundPack?, clear kind: PackKind) -> String? {
        guard let pack else {
            player.clear(kind)
            return nil
        }
        remember(pack)
        return player.replace(pack: pack)
    }

    private func remember(_ pack: SoundPack) {
        var seen = Set<String>()
        for clip in pack.clips.values where seen.insert(clip.file.path).inserted {
            if let pcm = try? readPCM(url: clip.file) {
                rates[clip.file.path] = pcm.sampleRate
                frames[clip.file.path] = pcm.frames
            }
        }
    }
}
#endif
