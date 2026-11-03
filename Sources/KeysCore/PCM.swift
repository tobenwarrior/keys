import Foundation

public struct PCMFile: Equatable {
    public var sampleRate: Double
    public var channels: Int
    public var samples: [Int16]

    public var frames: Int {
        guard channels > 0 else { return 0 }
        return samples.count / channels
    }
}

public enum PCMError: Error, Equatable {
    case unsupported
    case truncated
}

public func readPCM(_ data: Data) throws -> PCMFile {
    if data.count < 12 { throw PCMError.truncated }
    if String(bytes: data[0..<4], encoding: .ascii) != "RIFF" { throw PCMError.unsupported }
    if String(bytes: data[8..<12], encoding: .ascii) != "WAVE" { throw PCMError.unsupported }

    var format: UInt16 = 0
    var channels = 0
    var rate = 0
    var bits = 0
    var pcm: [Int16] = []
    var offset = 12
    while offset + 8 <= data.count {
        let chunkID = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
        let chunkSize = Int(readU32(data, offset + 4))
        let body = offset + 8
        if chunkSize < 0 || body + chunkSize > data.count { throw PCMError.truncated }
        if chunkID == "fmt " {
            if chunkSize < 16 { throw PCMError.unsupported }
            format = readU16(data, body)
            channels = Int(readU16(data, body + 2))
            rate = Int(readU32(data, body + 4))
            bits = Int(readU16(data, body + 14))
        } else if chunkID == "data" {
            if bits != 16 || format != 1 || channels < 1 || rate <= 0 {
                throw PCMError.unsupported
            }
            let count = chunkSize / 2
            pcm.reserveCapacity(count)
            var index = body
            for _ in 0..<count {
                pcm.append(Int16(bitPattern: readU16(data, index)))
                index += 2
            }
        }
        offset = body + chunkSize + (chunkSize % 2)
    }
    if pcm.isEmpty || channels == 0 || rate <= 0 { throw PCMError.unsupported }
    return PCMFile(sampleRate: Double(rate), channels: channels, samples: pcm)
}

public func readPCM(url: URL) throws -> PCMFile {
    try readPCM(Data(contentsOf: url))
}

public struct FrameSpan: Equatable {
    public var start: Int
    public var count: Int
}

public func frameSpan(slice: Slice, sampleRate: Double, frameCount: Int) -> FrameSpan? {
    guard sampleRate > 0, frameCount > 0 else { return nil }
    let start = Int((slice.startMs / 1000.0 * sampleRate).rounded(.down))
    let endMs = slice.endMs ?? (Double(frameCount) / sampleRate * 1000.0)
    var end = Int((endMs / 1000.0 * sampleRate).rounded(.up))
    if start < 0 || start >= frameCount { return nil }
    if end > frameCount { end = frameCount }
    if end <= start { return nil }
    return FrameSpan(start: start, count: end - start)
}

/// Mix the slice into `outputChannels` at `outputRate`.
/// `playbackRate` below 1 plays slower, which drops the pitch.
public func render(
    pcm: PCMFile,
    span: FrameSpan,
    playbackRate: Double,
    outputRate: Double,
    outputChannels: Int
) -> [Float] {
    guard span.count > 0, playbackRate > 0, outputRate > 0, pcm.channels > 0, outputChannels > 0 else {
        return []
    }
    let lastInput = span.start + span.count
    if lastInput > pcm.frames || span.start < 0 { return [] }
    let step = playbackRate * pcm.sampleRate / outputRate
    if step <= 0 { return [] }
    let outFrames = max(1, Int((Double(span.count) / step).rounded(.down)))
    var output = [Float](repeating: 0, count: outFrames * outputChannels)
    let scale: Float = 1.0 / 32768.0
    for frame in 0..<outFrames {
        let position = Double(frame) * step
        let left = min(Int(position), span.count - 1)
        let right = min(left + 1, span.count - 1)
        let fraction = Float(position - Double(left))
        for channel in 0..<outputChannels {
            let sourceChannel = min(channel, pcm.channels - 1)
            let s0 = Float(pcm.samples[(span.start + left) * pcm.channels + sourceChannel]) * scale
            let s1 = Float(pcm.samples[(span.start + right) * pcm.channels + sourceChannel]) * scale
            output[frame * outputChannels + channel] = s0 + (s1 - s0) * fraction
        }
    }
    return output
}

private func readU16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readU32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}
