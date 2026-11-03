#if os(macOS)
import AVFoundation
import Foundation
import XCTest
@testable import keys

final class AudioRecoveryTests: XCTestCase {
    func testAudioEngineRestartsAfterConfigurationChange() throws {
        let player = SoundPlayer()
        let engine = try XCTUnwrap(Mirror(reflecting: player).children.first { $0.label == "engine" }?.value as? AVAudioEngine)
        XCTAssertTrue(engine.isRunning, "The test needs a working audio output")
        engine.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)

        let restarted = expectation(description: "Audio engine restarts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if engine.isRunning { restarted.fulfill() }
        }
        wait(for: [restarted], timeout: 3)
        withExtendedLifetime(player) {}
    }
}
#endif
