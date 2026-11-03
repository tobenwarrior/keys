#if os(macOS)
import AVFoundation
import Foundation
import KeysCore

struct ClipKey: Hashable {
    var kind: PackKind
    var file: String
    var start: Int
    var count: Int
    var rateMillis: Int
}

final class SoundPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let nodes: [AVAudioPlayerNode]
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var inflight: [ObjectIdentifier: Int] = [:]
    private var clips: [ClipKey: AVAudioPCMBuffer] = [:]
    private var configurationObserver: NSObjectProtocol?
    var running: Bool { engine.isRunning }

    init(voices: Int = 12) {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        var made: [AVAudioPlayerNode] = []
        for _ in 0..<voices {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            made.append(node)
        }
        nodes = made
        for node in nodes {
            inflight[ObjectIdentifier(node)] = 0
        }
        engine.prepare()
        do {
            try engine.start()
            for node in nodes { node.play() }
        } catch {
            // A later configuration change can retry starting the engine.
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            // The notification arrives on an audio engine thread.
            DispatchQueue.main.async { [weak self] in self?.restartAfterConfigurationChange() }
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    private func restartAfterConfigurationChange(attempt: Int = 0) {
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            for node in nodes where !node.isPlaying { node.play() }
        } catch {
            // Devices may briefly be unavailable while macOS switches outputs.
            guard attempt < 3 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restartAfterConfigurationChange(attempt: attempt + 1)
            }
        }
    }

    func clear(_ kind: PackKind) {
        lock.lock()
        clips = clips.filter { $0.key.kind != kind }
        lock.unlock()
    }

    func setVolume(_ volume: Double) {
        let clamped = min(1, max(0, volume))
        engine.mainMixerNode.outputVolume = Float(clamped)
    }

    func replace(pack: SoundPack) -> String? {
        var decoded: [URL: PCMFile] = [:]
        var built: [ClipKey: AVAudioPCMBuffer] = [:]
        var failure: String?
        let names = Set(pack.clips.keys).union(extraNames(for: pack))
        for name in names {
            for down in [true, false] {
                guard let resolved = resolve(pack: pack, control: name, down: down) else { continue }
                let pcm: PCMFile
                if let cached = decoded[resolved.file] {
                    pcm = cached
                } else {
                    do {
                        pcm = try readPCM(url: resolved.file)
                        decoded[resolved.file] = pcm
                    } catch {
                        failure = "Could not read \(resolved.file.lastPathComponent)"
                        continue
                    }
                }
                guard let span = frameSpan(slice: resolved.slice, sampleRate: pcm.sampleRate, frameCount: pcm.frames) else {
                    continue
                }
                let key = ClipKey(
                    kind: pack.kind,
                    file: resolved.file.path,
                    start: span.start,
                    count: span.count,
                    rateMillis: Int((resolved.rate * 1000).rounded())
                )
                if built[key] != nil { continue }
                let samples = render(
                    pcm: pcm,
                    span: span,
                    playbackRate: resolved.rate,
                    outputRate: format.sampleRate,
                    outputChannels: Int(format.channelCount)
                )
                if let buffer = buffer(from: samples) {
                    built[key] = buffer
                }
            }
        }
        lock.lock()
        clips = clips.filter { $0.key.kind != pack.kind }
        for (key, buffer) in built {
            clips[key] = buffer
        }
        lock.unlock()
        return built.isEmpty ? (failure ?? "No sounds in \(pack.name)") : nil
    }

    func play(_ clip: ResolvedClip, sampleRate: Double, frameCount: Int) {
        guard let span = frameSpan(slice: clip.slice, sampleRate: sampleRate, frameCount: frameCount) else { return }
        let key = ClipKey(
            kind: clip.kind,
            file: clip.file.path,
            start: span.start,
            count: span.count,
            rateMillis: Int((clip.rate * 1000).rounded())
        )
        lock.lock()
        let buffer = clips[key]
        lock.unlock()
        guard let buffer else { return }
        schedule(buffer)
    }

    private func extraNames(for pack: SoundPack) -> Set<String> {
        guard pack.kind == .keyboard else { return [] }
        return ["Space", "Enter", "NumpadEnter"]
    }

    private func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        let channels = Int(format.channelCount)
        guard channels > 0, samples.count >= channels else { return nil }
        let frames = samples.count / channels
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let dest = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            for channel in 0..<channels {
                dest[channel][frame] = samples[frame * channels + channel]
            }
        }
        return buffer
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let node = nodes.min { inflight[ObjectIdentifier($0), default: 0] < inflight[ObjectIdentifier($1), default: 0] }!
        inflight[ObjectIdentifier(node), default: 0] += 1
        lock.unlock()
        node.scheduleBuffer(buffer, completionHandler: { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.inflight[ObjectIdentifier(node), default: 1] -= 1
            self.lock.unlock()
        })
    }
}
#endif
