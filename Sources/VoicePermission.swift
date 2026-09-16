import AVFoundation
import Speech

/// Centralized microphone + speech authorization. Never re-prompts after the first system dialog.
enum VoicePermission {
    enum BlockReason: Equatable {
        case microphoneDenied
        case microphoneRestricted
        case speechDenied
        case speechRestricted
    }

    private static let micPromptedKey = "voiceMicrophonePrompted.v1"
    private static let speechPromptedKey = "voiceSpeechPrompted.v1"
    private static var micRequestInFlight = false
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
                // Already asked this install — never show the system dialog again.
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
        guard !micRequestInFlight else { return false }
        micRequestInFlight = true
        defer { micRequestInFlight = false }
        UserDefaults.standard.set(true, forKey: micPromptedKey)
        if #available(macOS 14.0, *) {
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            return granted
        }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Returns `.authorized` only when speech access is granted. Requests at most once per install.
    static func requestSpeechIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return .authorized }
        if speechBlockReason() != nil { return current == .notDetermined ? .denied : current }
        guard !speechRequestInFlight else { return .denied }
        speechRequestInFlight = true
        defer { speechRequestInFlight = false }
        UserDefaults.standard.set(true, forKey: speechPromptedKey)
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    /// Test seam: clear prompt-latched keys.
    static func resetPromptLatchForTesting(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: micPromptedKey)
        defaults.removeObject(forKey: speechPromptedKey)
    }
}
