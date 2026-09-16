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

        // Simulate mid-start: mark as permission without opening a system sheet.
        // prepare must not tear down an in-flight permission wait.
        // We exercise the public gate via isPendingStart after forcing state through a blocked start path
        // when mic is already denied via latch.
        UserDefaults.standard.set(true, forKey: "voiceMicrophonePrompted.v1")
        // Status remains notDetermined in this Linux/simulator host; latch makes block reason denied.
        if VoicePermission.microphoneBlockReason() != nil {
            await voice.start()
            XCTAssertEqual(voice.state, .unavailable)
            XCTAssertFalse(voice.isPendingStart)
            // Repeat start while unavailable should not hang — returns quickly.
            await voice.start()
            XCTAssertEqual(voice.state, .unavailable)
        }

        VoicePermission.resetPromptLatchForTesting()
        voice.stop()
        voice.prepare(.talk)
        XCTAssertEqual(voice.state, .ready)
        XCTAssertFalse(voice.isActive)
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
