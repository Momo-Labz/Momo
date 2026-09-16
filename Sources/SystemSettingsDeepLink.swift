import AppKit
import Foundation

/// Opens the correct macOS System Settings pane for TCC-related onboarding.
/// Prefer modern `x-apple.systempreferences:` URLs; fall back to `open` scheme variants.
enum SystemSettingsDeepLink {
    static func openMicrophone() {
        open(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?path=Microphone",
            "x-apple.systempreferences:com.apple.preference.security"
        ])
    }

    static func openSpeechRecognition() {
        open(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?path=SpeechRecognition",
            "x-apple.systempreferences:com.apple.preference.security"
        ])
    }

    /// Notifications pane focused on MOMO when possible.
    static func openNotifications() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.momolabz.barboy"
        open(candidates: [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ])
    }

    static func openFullDiskAccess() {
        LocalUsageArtifactReader.openPrivacySettings()
    }

    private static func open(candidates: [String]) {
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}
