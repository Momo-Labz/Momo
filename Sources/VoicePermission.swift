import AVFoundation
import Speech

/// Centralized microphone + speech authorization. Never re-prompts after the first system dialog.
///
/// Permission APIs often invoke their completion handlers on the main thread. Resuming a
/// MainActor-awaited continuation directly from that callback deadlocks the UI (callback
/// holds the main thread while MainActor work cannot proceed). Always resume off-main.
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

    static func microphoneAuthorized() -> Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func microphoneBlockReason() -> BlockReason? {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return nil
            case .denied: return .microphoneDenied
            case .undetermined:
                if UserDefaults.standard.bool(forKey: micPromptedKey) { return .microphoneDenied }
                return nil
            @unknown default: return .microphoneDenied
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return nil
        case .denied: return .microphoneDenied
        case .restricted: return .microphoneRestricted
        case .notDetermined:
            if UserDefaults.standard.bool(forKey: micPromptedKey) { return .microphoneDenied }
            return nil
        @unknown default: return .microphoneDenied
        }
    }

    static func speechBlockReason() -> BlockReason? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return nil
        case .denied: return .speechDenied
        case .restricted: return .speechRestricted
        case .notDetermined:
            if UserDefaults.standard.bool(forKey: speechPromptedKey) { return .speechDenied }
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

    /// Returns `true` only when mic access is granted. Requests at most once per install.
    static func requestMicrophoneIfNeeded() async -> Bool {
        if microphoneAuthorized() { return true }
        if microphoneBlockReason() != nil { return false }

        micInFlightLock.lock()
        if micRequestInFlight {
            micInFlightLock.unlock()
            return false
        }
        micRequestInFlight = true
        micInFlightLock.unlock()
        defer {
            micInFlightLock.lock()
            micRequestInFlight = false
            micInFlightLock.unlock()
        }

        UserDefaults.standard.set(true, forKey: micPromptedKey)
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    // Off-main resume prevents MainActor deadlock when the OS calls back on main.
                    Self.resumeOffMain(continuation, returning: granted)
                }
            }
        }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Self.resumeOffMain(continuation, returning: granted)
            }
        }
    }

    /// Returns `.authorized` only when speech access is granted. Requests at most once per install.
    static func requestSpeechIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return .authorized }
        if speechBlockReason() != nil { return current == .notDetermined ? .denied : current }

        speechInFlightLock.lock()
        if speechRequestInFlight {
            speechInFlightLock.unlock()
            return .denied
        }
        speechRequestInFlight = true
        speechInFlightLock.unlock()
        defer {
            speechInFlightLock.lock()
            speechRequestInFlight = false
            speechInFlightLock.unlock()
        }

        UserDefaults.standard.set(true, forKey: speechPromptedKey)
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Self.resumeOffMain(continuation, returning: status)
            }
        }
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
