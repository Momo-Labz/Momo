import AppKit
import Foundation

/// Maps MOMO providers to installed desktop apps under `/Applications` (and Launch Services).
/// Usage and LIVE state come from local process/session monitoring — never from WebKit scrape.
enum DesktopAppCatalog {
    struct AppMatch: Equatable {
        let provider: AIProvider
        let displayName: String
        let bundleURL: URL?
        var isInstalled: Bool { bundleURL != nil }
    }

    /// Free plan may allow-list at most this many desktop providers; MOMO+ unlocks the rest.
    static let freeProviderLimit = 2

    static func displayName(for provider: AIProvider) -> String {
        switch provider {
        case .codex: return "ChatGPT / Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .grok: return "Grok"
        }
    }

    /// App bundle names to look for under `/Applications` and `~/Applications`.
    static func applicationFileNames(for provider: AIProvider) -> [String] {
        switch provider {
        case .codex: return ["ChatGPT.app", "Codex.app"]
        case .claude: return ["Claude.app"]
        case .gemini: return ["Gemini.app", "Google Gemini.app"]
        case .cursor: return ["Cursor.app"]
        case .grok: return ["Grok.app"]
        }
    }

    static func match(for provider: AIProvider) -> AppMatch {
        AppMatch(provider: provider, displayName: displayName(for: provider), bundleURL: locate(provider))
    }

    static func installedMatches() -> [AppMatch] {
        AIProvider.allCases.map(match(for:))
    }

    static func locate(_ provider: AIProvider) -> URL? {
        for identifier in provider.applicationBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return onDiskURL(provider)
    }

    /// File-system check safe to call from background scanners (no Launch Services).
    static func isPresentOnDisk(_ provider: AIProvider) -> Bool {
        onDiskURL(provider) != nil
    }

    private static func onDiskURL(_ provider: AIProvider) -> URL? {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            for name in applicationFileNames(for: provider) {
                let candidate = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Opens the desktop app when installed. Returns false if the app is missing.
    @discardableResult
    static func open(_ provider: AIProvider) -> Bool {
        guard let url = locate(provider) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

/// Soft-lock helpers for Free vs MOMO+ provider count (no StoreKit).
enum MomoPlusGate {
    static var isPlus: Bool {
        UserDefaults.standard.bool(forKey: "momoPlusEntitled.v1")
    }

    static func canAllowAdditionalProvider(currentAllowedCount: Int, alreadyAllowed: Bool) -> Bool {
        if alreadyAllowed { return true }
        if isPlus { return true }
        return currentAllowedCount < DesktopAppCatalog.freeProviderLimit
    }
}
