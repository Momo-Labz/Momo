import XCTest
@testable import BAR_BOY

@MainActor
final class VoiceInputLifecycleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoicePermission.resetPromptLatchForTesting()
        VoiceInput.shared.stop()
    }

    func testPendingStartDebouncesRepeatedPrepareAndStart() async {
        let voice = VoiceInput.shared
        voice.stop()
        XCTAssertEqual(voice.state, .ready)

        // Undetermined + prompted latch must NOT fake “mic off” (System Settings can show ON).
        UserDefaults.standard.set(true, forKey: "voiceMicrophonePrompted.v1")
        XCTAssertNil(VoicePermission.microphoneBlockReason())

        VoicePermission.resetPromptLatchForTesting()
        voice.stop()
        voice.prepare(.talk)
        XCTAssertEqual(voice.state, .ready)
        XCTAssertFalse(voice.isActive)
    }

    func testMicrophoneGuidanceOnlyForHardDeny() {
        // Guidance strings stay useful when the OS reports a real denial.
        XCTAssertFalse(VoicePermission.settingsGuidance(for: .microphoneDenied).isEmpty)
        XCTAssertTrue(VoicePermission.settingsGuidance(for: .microphoneDenied).contains("Microphone"))
    }

    func testStopFromPermissionLikeStatesReturnsReadyWithoutHang() {
        let voice = VoiceInput.shared
        voice.prepare(.talk)
        voice.stop()
        XCTAssertEqual(voice.state, .ready)
        XCTAssertFalse(voice.isPendingStart)
        XCTAssertFalse(voice.isActive)
    }

    func testStartTimeoutConstantIsFinite() {
        XCTAssertGreaterThan(VoiceInput.startTimeoutSeconds, 0)
        XCTAssertLessThanOrEqual(VoiceInput.startTimeoutSeconds, 60)
    }

    func testPermissionGuidanceNeverEmpty() {
        for reason in [
            VoicePermission.BlockReason.microphoneDenied,
            .microphoneRestricted,
            .speechDenied,
            .speechRestricted
        ] {
            XCTAssertFalse(VoicePermission.settingsGuidance(for: reason).isEmpty)
        }
    }
}
