import AVFoundation
import Speech

/// Centralized microphone + speech authorization. Never re-prompts after denial.
enum VoicePermission {
    enum BlockReason: Equatable {
        case microphoneDenied
        case microphoneRestricted
        case speechDenied
        case speechRestricted
    }

    static func microphoneAuthorized() -> Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func microphoneBlockReason() -> BlockReason? {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted, .undetermined: return nil
            case .denied: return .microphoneDenied
            @unknown default: return .microphoneDenied
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized, .notDetermined: return nil
        case .denied: return .microphoneDenied
        case .restricted: return .microphoneRestricted
        @unknown default: return .microphoneDenied
        }
    }

    static func speechBlockReason() -> BlockReason? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized, .notDetermined: return nil
        case .denied: return .speechDenied
        case .restricted: return .speechRestricted
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

    /// Returns `true` only when mic access is granted. Requests at most once while status is undetermined.
    static func requestMicrophoneIfNeeded() async -> Bool {
        if microphoneAuthorized() { return true }
        if microphoneBlockReason() != nil { return false }
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Returns `.authorized` only when speech access is granted. Requests at most once while status is notDetermined.
    static func requestSpeechIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return .authorized }
        if speechBlockReason() != nil { return SFSpeechRecognizer.authorizationStatus() }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
