import AVFoundation
import Speech

/// Centralized microphone + speech authorization. Never re-prompts after the first system dialog
/// unless status is still undetermined (user can tap Speak again).
///
/// Permission APIs often invoke their completion handlers on the main thread. Resuming a
/// MainActor-awaited continuation directly from that callback deadlocks the UI (callback
/// holds the main thread while MainActor work cannot proceed). Always resume off-main.
///
/// macOS quirk: System Settings → Microphone can show MOMO ON while
/// `AVAudioApplication.recordPermission` still reports `.undetermined` (unsigned builds /
/// identity churn). Always consult `AVCaptureDevice` too, and never treat
/// prompted+undetermined as a hard “access is off”.
enum VoicePermission {
    enum BlockReason: Equatable {
        case microphoneDenied
        case microphoneRestricted
        case speechDenied
        case speechRestricted
    }

    private static let micPromptedKey = "voiceMicrophonePrompted.v1"
    private static let speechPromptedKey = "voiceSpeechPrompted.v1"
    private static let micInFlightLock = NSLock()
    private static var micRequestInFlight = false
    private static let speechInFlightLock = NSLock()
    private static var speechRequestInFlight = false

    /// True when this process is authorized for microphone recording.
    /// Prefers `AVCaptureDevice` (matches System Settings) and also accepts `AVAudioApplication`.
    static func microphoneAuthorized() -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return false
    }

    /// Non-nil only for explicit denied/restricted. Undetermined never shows a false “off” banner.
    static func microphoneBlockReason() -> BlockReason? {
        if microphoneAuthorized() { return nil }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return nil
        case .denied:
            return .microphoneDenied
        case .restricted:
            return .microphoneRestricted
        case .notDetermined:
            break
        @unknown default:
            break
        }

        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return nil
            case .denied:
                return .microphoneDenied
            case .undetermined:
                // Do not latch prompted+undetermined as denied — Settings may already show ON.
                return nil
            @unknown default:
                return .microphoneDenied
            }
        }
        return nil
    }

    static func speechBlockReason() -> BlockReason? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return nil
        case .denied: return .speechDenied
        case .restricted: return .speechRestricted
        case .notDetermined:
            // Same honesty as mic: undetermined is not a hard “off”.
            return nil
        @unknown default: return .speechDenied
        }
    }

    static func settingsGuidance(for reason: BlockReason) -> String {
        switch reason {
        case .microphoneDenied, .microphoneRestricted:
            return "Microphone access is off. Open System Settings → Privacy & Security → Microphone and enable MOMO, then try Talk again."
        case .speechDenied, .speechRestricted:
            return "Speech Recognition is off. Open System Settings → Privacy & Security → Speech Recognition and enable MOMO, then try Talk again."
        }
    }

    /// Returns `true` only when mic access is granted. Requests at most once while undetermined.
    static func requestMicrophoneIfNeeded() async -> Bool {
        if microphoneAuthorized() { return true }
        // Hard deny from System Settings — do not re-prompt; caller shows Open Settings.
        if case .denied = AVCaptureDevice.authorizationStatus(for: .audio) { return false }
        if case .restricted = AVCaptureDevice.authorizationStatus(for: .audio) { return false }
        if #available(macOS 14.0, *), AVAudioApplication.shared.recordPermission == .denied {
            return false
        }

        micInFlightLock.lock()
        if micRequestInFlight {
            micInFlightLock.unlock()
            return microphoneAuthorized()
        }
        micRequestInFlight = true
        micInFlightLock.unlock()
        defer {
            micInFlightLock.lock()
            micRequestInFlight = false
            micInFlightLock.unlock()
        }

        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { ok in
                    Self.resumeOffMain(continuation, returning: ok)
                }
            }
        } else {
            granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    Self.resumeOffMain(continuation, returning: ok)
                }
            }
        }
        // Latch only after a real prompt attempt — never used to fake “denied” while undetermined.
        UserDefaults.standard.set(true, forKey: micPromptedKey)
        return granted || microphoneAuthorized()
    }

    /// Returns `.authorized` only when speech access is granted.
    static func requestSpeechIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return .authorized }
        if current == .denied || current == .restricted { return current }

        speechInFlightLock.lock()
        if speechRequestInFlight {
            speechInFlightLock.unlock()
            return SFSpeechRecognizer.authorizationStatus()
        }
        speechRequestInFlight = true
        speechInFlightLock.unlock()
        defer {
            speechInFlightLock.lock()
            speechRequestInFlight = false
            speechInFlightLock.unlock()
        }

        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Self.resumeOffMain(continuation, returning: status)
            }
        }
        UserDefaults.standard.set(true, forKey: speechPromptedKey)
        return status
    }

    private static func resumeOffMain<T>(_ continuation: CheckedContinuation<T, Never>, returning value: T) {
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: value)
        }
    }

    /// Test seam: clear prompt-latched keys.
    static func resetPromptLatchForTesting(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: micPromptedKey)
        defaults.removeObject(forKey: speechPromptedKey)
        micInFlightLock.lock(); micRequestInFlight = false; micInFlightLock.unlock()
        speechInFlightLock.lock(); speechRequestInFlight = false; speechInFlightLock.unlock()
    }
}
