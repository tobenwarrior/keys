import Foundation
import XCTest
@testable import KeysCore

final class CoreTests: XCTestCase {
    func testFrameSpanUsesSampleRate() {
        let slice = Slice(startMs: 0, endMs: 1000)
        let span = frameSpan(slice: slice, sampleRate: 44100, frameCount: 88200)
        XCTAssertEqual(span, FrameSpan(start: 0, count: 44100))
        let short = frameSpan(slice: Slice(startMs: 0, endMs: 0.1), sampleRate: 44100, frameCount: 100)
        XCTAssertEqual(short, FrameSpan(start: 0, count: 5))
    }

    func testRenderKeepsPitchAndLength() {
        let pcm = PCMFile(sampleRate: 44100, channels: 1, samples: [0, 16384, -16384])
        let identity = render(
            pcm: pcm,
            span: FrameSpan(start: 0, count: 3),
            playbackRate: 1,
            outputRate: 44100,
            outputChannels: 1
        )
        XCTAssertEqual(identity.count, 3)
        XCTAssertEqual(identity[0], 0, accuracy: 0.0001)
        XCTAssertEqual(identity[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(identity[2], -0.5, accuracy: 0.0001)

        let deeper = render(
            pcm: pcm,
            span: FrameSpan(start: 0, count: 3),
            playbackRate: 0.5,
            outputRate: 44100,
            outputChannels: 1
        )
        XCTAssertEqual(deeper.count, 6)
        XCTAssertEqual(deeper[0], 0, accuracy: 0.0001)
        XCTAssertEqual(deeper[1], 0.25, accuracy: 0.0001)
        XCTAssertEqual(deeper[2], 0.5, accuracy: 0.0001)
        XCTAssertEqual(deeper[3], 0, accuracy: 0.0001)
        XCTAssertEqual(deeper[4], -0.5, accuracy: 0.0001)
        XCTAssertEqual(deeper[5], -0.5, accuracy: 0.0001)
    }

    func testWavRoundTrip() throws {
        let bytes = wavData(samples: [1, -2, 3, -4], rate: 44100, channels: 2)
        let pcm = try readPCM(bytes)
        XCTAssertEqual(pcm.sampleRate, 44100)
        XCTAssertEqual(pcm.channels, 2)
        XCTAssertEqual(pcm.samples, [1, -2, 3, -4])
    }

    func testSpaceAndEnterAreLowerThanLetters() {
        XCTAssertEqual(depthRate(for: "Space"), 0.86)
        XCTAssertEqual(depthRate(for: "Enter"), 0.93)
        XCTAssertEqual(depthRate(for: "NumpadEnter"), 0.93)
        XCTAssertEqual(depthRate(for: "KeyA"), 1)
        XCTAssertLessThan(depthRate(for: "Space"), depthRate(for: "Enter"))
        XCTAssertLessThan(depthRate(for: "Enter"), depthRate(for: "KeyA"))
    }

    func testBundledPacks() throws {
        let scan = scanPacks(at: repoRoot().appendingPathComponent("packs"))
        XCTAssertEqual(scan.errors, [])
        XCTAssertEqual(scan.packs.count, 14)
        let keyboards = scan.packs.filter { $0.kind == .keyboard }
        let mice = scan.packs.filter { $0.kind == .mouse }
        XCTAssertEqual(keyboards.count, 10)
        XCTAssertEqual(mice.count, 4)

        let board = try XCTUnwrap(keyboards.first { $0.id == "keyboard-cherrymx-black-pbt" })
        let space = try XCTUnwrap(resolve(pack: board, control: "Space", down: true))
        let enter = try XCTUnwrap(resolve(pack: board, control: "Enter", down: true))
        let keyA = try XCTUnwrap(resolve(pack: board, control: "KeyA", down: true))
        XCTAssertEqual(space.slice.startMs, 34906)
        XCTAssertEqual(enter.slice.startMs, 27154)
        XCTAssertEqual(keyA.slice.startMs, 22850)
        XCTAssertNotEqual(space.slice.startMs, keyA.slice.startMs)
        XCTAssertEqual(space.rate, 0.86)
        XCTAssertEqual(enter.rate, 0.93)
        XCTAssertEqual(keyA.rate, 1)
        XCTAssertNil(resolve(pack: board, control: "MouseLeft", down: true))

        for pack in keyboards {
            let down = try XCTUnwrap(resolve(pack: pack, control: "Space", down: true))
            XCTAssertEqual(down.rate, 0.86)
            XCTAssertNotNil(resolve(pack: pack, control: "Enter", down: true))
            XCTAssertNotNil(resolve(pack: pack, control: "KeyA", down: false))
        }

        let wooden = try XCTUnwrap(mice.first { $0.id == "mouse-wooden" })
        let click = try XCTUnwrap(resolve(pack: wooden, control: "MouseLeft", down: true))
        XCTAssertEqual(click.slice.startMs, 528)
        XCTAssertEqual(click.rate, 1)
        XCTAssertNil(resolve(pack: wooden, control: "KeyA", down: true))
        let pcm = try readPCM(url: click.file)
        XCTAssertEqual(pcm.sampleRate, 44100)
        XCTAssertEqual(pcm.channels, 2)
        XCTAssertGreaterThan(pcm.frames, 1000)
    }

    func testMissingSpaceUsesLetterAtLowerRate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let wav = directory.appendingPathComponent("a.wav")
        try wavData(samples: [0, 0], rate: 8000, channels: 1).write(to: wav)
        let json = """
        {"name":"Tiny","audio_file":"a.wav","definitions":{"KeyA":{"timing":[[0,10]]}}}
        """
        try json.write(to: directory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let pack = try loadPack(at: directory)
        let space = try XCTUnwrap(resolve(pack: pack, control: "Space", down: true))
        XCTAssertEqual(space.slice.startMs, 0)
        XCTAssertEqual(space.rate, 0.86)
        XCTAssertNil(resolve(pack: pack, control: "KeyA", down: false))
    }

    func testRejectsPathEscapeAndBadJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"name":"Bad","audio_file":"../secret.wav","definitions":{"KeyA":{"timing":[[0,10]]}}}
        """
        try json.write(to: directory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let scan = scanPacks(at: directory)
        XCTAssertTrue(scan.packs.isEmpty)
        XCTAssertEqual(scan.errors.count, 1)
    }

    func testSettingsDoNotKeepExtraFields() throws {
        let raw = """
        {"volume":4,"muted":true,"keyboardPackId":"board","mousePackId":"click","typed":["a","b"]}
        """.data(using: .utf8)!
        let settings = try decodeSettings(raw)
        XCTAssertEqual(settings.volume, 1)
        XCTAssertTrue(settings.muted)
        XCTAssertFalse(playbackAllowed(settings))
        let encoded = try JSONSerialization.jsonObject(with: encodeSettings(settings)) as! [String: Any]
        XCTAssertEqual(
            Set(encoded.keys),
            ["volume", "muted", "keyboardPackId", "mousePackId"]
        )
        XCTAssertTrue(playbackAllowed(AppSettings.standard))
        XCTAssertFalse(acceptPress(autorepeat: true))
        XCTAssertTrue(acceptPress(autorepeat: false))
    }

    func testMacKeyNames() {
        XCTAssertEqual(controlName(macKeyCode: 0), "KeyA")
        XCTAssertEqual(controlName(macKeyCode: 49), "Space")
        XCTAssertEqual(controlName(macKeyCode: 36), "Enter")
        XCTAssertEqual(controlName(macKeyCode: 76), "NumpadEnter")
        XCTAssertNil(controlName(macKeyCode: 10))
        XCTAssertEqual(mouseControl(button: 0), "MouseLeft")
        XCTAssertEqual(mouseControl(button: 1), "MouseRight")
        XCTAssertEqual(mouseControl(button: 2), "MouseMiddle")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func wavData(samples: [Int16], rate: Int, channels: Int) -> Data {
        var data = Data()
        func appendASCII(_ text: String) { data.append(contentsOf: text.utf8) }
        func append16(_ value: UInt16) {
            data.append(UInt8(value & 0xff))
            data.append(UInt8(value >> 8))
        }
        func append32(_ value: UInt32) {
            append16(UInt16(value & 0xffff))
            append16(UInt16(value >> 16))
        }
        let pcm = samples.flatMap { sample -> [UInt8] in
            let bits = UInt16(bitPattern: sample)
            return [UInt8(bits & 0xff), UInt8(bits >> 8)]
        }
        appendASCII("RIFF")
        append32(UInt32(36 + pcm.count))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(UInt16(channels))
        append32(UInt32(rate))
        append32(UInt32(rate * channels * 2))
        append16(UInt16(channels * 2))
        append16(16)
        appendASCII("data")
        append32(UInt32(pcm.count))
        data.append(contentsOf: pcm)
        return data
    }
}
