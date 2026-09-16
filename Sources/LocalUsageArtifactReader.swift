import AppKit
import Foundation

/// Discovers honest local usage % artifacts for providers that do not embed Codex-style
/// `rate_limits` in every transcript. Never invents percentages; never calls provider APIs.
enum LocalUsageArtifactReader {
    /// Claude statusline / OAuth-cache JSON and optional Cursor local caches.
    static func quotaWindows(
        for provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now,
        fileManager: FileManager = .default
    ) -> [RecordedQuotaWindow] {
        switch provider {
        case .claude:
            return claudeWindows(home: home, now: now, fileManager: fileManager)
        case .cursor:
            return cursorWindows(home: home, now: now, fileManager: fileManager)
        case .codex, .gemini, .grok:
            return []
        }
    }

    /// True when MOMO can list the provider’s default session root (FDA may block otherwise).
    static func canReadSessionRoot(
        _ provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        for relative in provider.sessionRoots {
            let root = home.appendingPathComponent(relative, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if (try? fileManager.contentsOfDirectory(atPath: root.path)) != nil {
                return true
            }
        }
        return false
    }

    /// Session root exists on disk but listing fails — typical Full Disk Access / TCC denial.
    static func isSessionRootPrivacyBlocked(
        _ provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        for relative in provider.sessionRoots {
            let root = home.appendingPathComponent(relative, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if (try? fileManager.contentsOfDirectory(atPath: root.path)) == nil {
                return true
            }
        }
        return false
    }

    static func privacyGuidance(for provider: AIProvider) -> String {
        let name = DesktopAppCatalog.displayName(for: provider)
        return "macOS blocked reading \(name)’s local files. Open System Settings → Privacy & Security → Full Disk Access and allow MOMO, then Retry. (App Management is only needed if macOS asks — MOMO never writes into \(name).)"
    }

    static func openPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Claude

    private static func claudeWindows(home: URL, now: Date, fileManager: FileManager) -> [RecordedQuotaWindow] {
        for url in claudeCandidateURLs(home: home, fileManager: fileManager) {
            guard let data = try? Data(contentsOf: url), data.count <= 256 * 1024,
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let windows = RecordedQuotaWindow.parseFlexible(
                    json,
                    observedAt: modificationDate(url, fileManager: fileManager) ?? now
                  ),
                  !windows.isEmpty else { continue }
            return windows
        }
        return []
    }

    private static func claudeCandidateURLs(home: URL, fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        let names = [
            "usage-cache.json",
            "usage_cache.json",
            "rate-limits.json",
            "rate_limits.json",
            "stats-cache.json",
            "oauth-usage-cache.json"
        ]
        for name in names {
            urls.append(claude.appendingPathComponent(name))
        }
        // Claude Desktop Application Support (read-only; may be FDA-gated).
        let support = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        for name in names {
            urls.append(support.appendingPathComponent(name))
        }
        // Community / Claude Code statusline caches (written by local scripts, not MOMO).
        let tmp = URL(fileURLWithPath: "/tmp/claude", isDirectory: true)
        if let kids = try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            urls.append(contentsOf: kids.filter {
                $0.lastPathComponent.hasPrefix("statusline-usage-cache") && $0.pathExtension == "json"
            }.sorted { $0.lastPathComponent > $1.lastPathComponent })
        }
        return urls
    }

    // MARK: - Cursor

    private static func cursorWindows(home: URL, now: Date, fileManager: FileManager) -> [RecordedQuotaWindow] {
        // Cursor transcripts do not expose account %. Only accept an explicit local cache if present.
        let support = home.appendingPathComponent("Library/Application Support/Cursor", isDirectory: true)
        let candidates = [
            support.appendingPathComponent("usage-cache.json"),
            support.appendingPathComponent("User/globalStorage/momo-usage-cache.json"),
            home.appendingPathComponent(".cursor/usage-cache.json")
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url), data.count <= 256 * 1024,
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let windows = RecordedQuotaWindow.parseFlexible(
                    json,
                    observedAt: modificationDate(url, fileManager: fileManager) ?? now
                  ),
                  !windows.isEmpty else { continue }
            return windows
        }
        return []
    }

    private static func modificationDate(_ url: URL, fileManager: FileManager) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}

extension RecordedQuotaWindow {
    /// Parses Claude statusline / OAuth-cache shaped JSON and generic rate_limits blobs.
    /// Returns nil when the document is unrelated; [] when keys exist but values are unusable.
    static func parseFlexible(_ json: Any, observedAt: Date) -> [RecordedQuotaWindow]? {
        if let dict = json as? [String: Any] {
            if let nested = dict["rate_limits"] {
                return parseFlexible(nested, observedAt: observedAt)
            }
            // Claude Code statusline: rate_limits.five_hour / seven_day
            // OAuth usage cache: top-level five_hour / seven_day with utilization
            if dict["five_hour"] != nil || dict["seven_day"] != nil || dict["fiveHour"] != nil {
                var windows: [RecordedQuotaWindow] = []
                if let five = window(from: dict["five_hour"] ?? dict["fiveHour"], minutes: 300, observedAt: observedAt) {
                    windows.append(five)
                }
                if let week = window(
                    from: dict["seven_day"] ?? dict["sevenDay"] ?? dict["week"],
                    minutes: 10_080,
                    observedAt: observedAt
                ) {
                    windows.append(week)
                }
                return windows
            }
            // Codex-like primary/secondary
            if dict["primary"] != nil || dict["secondary"] != nil {
                return ["primary", "secondary"].compactMap { key in
                    guard let block = dict[key] as? [String: Any] else { return nil }
                    return window(from: block, minutesHint: key == "secondary" ? 10_080 : 300, observedAt: observedAt)
                }
            }
        }
        return nil
    }

    private static func window(from value: Any?, minutes: Int, observedAt: Date) -> RecordedQuotaWindow? {
        guard let block = value as? [String: Any] else { return nil }
        return window(from: block, minutesHint: minutes, observedAt: observedAt)
    }

    private static func window(from block: [String: Any], minutesHint: Int, observedAt: Date) -> RecordedQuotaWindow? {
        let percent = flexibleNumber(block["used_percentage"])
            ?? flexibleNumber(block["used_percent"])
            ?? flexibleNumber(block["utilization"])
            ?? flexibleNumber(block["percent"])
        guard let percent, (0...100).contains(percent) else { return nil }
        let minutes = Int(flexibleNumber(block["window_minutes"]) ?? Double(minutesHint))
        guard minutes > 0 else { return nil }
        var reset: Date?
        if let value = block["resets_at"] ?? block["resetsAt"], !(value is NSNull) {
            if let seconds = flexibleNumber(value), seconds > 1_000_000_000, seconds < 32_503_680_000 {
                reset = Date(timeIntervalSince1970: seconds)
            } else if let text = value as? String, let parsed = flexibleParseDate(text) {
                reset = parsed
            }
        }
        return RecordedQuotaWindow(percent: percent, minutes: minutes, resetsAt: reset, observedAt: observedAt)
    }

    private static func flexibleNumber(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, String(cString: value.objCType) != "c", value.doubleValue.isFinite else {
            return nil
        }
        return value.doubleValue
    }

    private static func flexibleParseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
