import AppKit
import Foundation

/// Honest local usage detail for the Usage tab (Claude Code `/usage`-shaped when present).
/// Every optional field stays nil unless parsed from a real local artifact — never invented.
struct LocalUsageDetail: Equatable {
    var windows: [RecordedQuotaWindow] = []
    var totalCostUSD: Double?
    var durationAPISeconds: Double?
    var durationWallSeconds: Double?
    var linesAdded: Int?
    var linesRemoved: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?
    var sourceDescription: String?
    var observedAt: Date = .now

    var hasSessionStats: Bool {
        totalCostUSD != nil
            || durationAPISeconds != nil
            || durationWallSeconds != nil
            || linesAdded != nil
            || linesRemoved != nil
            || inputTokens != nil
            || outputTokens != nil
            || cacheReadTokens != nil
            || cacheWriteTokens != nil
    }

    var hasQuotaMeters: Bool { !windows.isEmpty }

    var isEmpty: Bool { !hasSessionStats && !hasQuotaMeters }

    var fiveHour: RecordedQuotaWindow? {
        windows.filter { $0.minutes < 10_080 }.sorted { $0.minutes < $1.minutes }.first
    }

    var weekly: RecordedQuotaWindow? {
        windows.filter { $0.minutes >= 10_080 }.sorted { $0.minutes > $1.minutes }.first
    }
}

/// Discovers honest local usage % artifacts for providers that do not embed Codex-style
/// `rate_limits` in every transcript. Never invents percentages; never calls provider APIs.
enum LocalUsageArtifactReader {
    /// Artifact windows remain valid longer than live transcript events (rate-limit caches
    /// are useful until reset, not only for 15 minutes).
    static let artifactFreshness: TimeInterval = 24 * 60 * 60

    static func quotaWindows(
        for provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now,
        fileManager: FileManager = .default
    ) -> [RecordedQuotaWindow] {
        detail(for: provider, home: home, now: now, fileManager: fileManager).windows
    }

    /// Full Claude Code–style detail when local JSON exists; empty detail otherwise.
    static func detail(
        for provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now,
        fileManager: FileManager = .default
    ) -> LocalUsageDetail {
        switch provider {
        case .claude:
            return claudeDetail(home: home, now: now, fileManager: fileManager)
        case .cursor:
            return cursorDetail(home: home, now: now, fileManager: fileManager)
        case .codex:
            return codexDetail(home: home, now: now, fileManager: fileManager)
        case .gemini, .grok:
            return LocalUsageDetail()
        }
    }

    /// Probe caches first, then optional read-only CLI helpers. Always returns a concrete empty reason when empty.
    static func probeDetail(
        for provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now,
        fileManager: FileManager = .default,
        timeout: TimeInterval = ProviderCLIUsageProbe.defaultTimeout
    ) -> ProviderUsageProbeResult {
        ProviderCLIUsageProbe.probe(
            provider: provider,
            home: home,
            fileManager: fileManager,
            now: now,
            timeout: timeout
        )
    }

    static func isFresh(_ window: RecordedQuotaWindow, now: Date = .now) -> Bool {
        guard now >= window.observedAt else { return false }
        if let resetsAt = window.resetsAt, resetsAt > now { return true }
        return now.timeIntervalSince(window.observedAt) <= artifactFreshness
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

    /// Claude Code–style reset line, e.g. “Resets Sep 19 at 1:59pm”.
    static func resetCaption(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let date, date > now else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "Resets MMM d 'at' h:mma"
        return formatter.string(from: date)
            .replacingOccurrences(of: "AM", with: "am")
            .replacingOccurrences(of: "PM", with: "pm")
    }

    // MARK: - Claude

    private static func claudeDetail(home: URL, now: Date, fileManager: FileManager) -> LocalUsageDetail {
        for url in claudeCandidateURLs(home: home, fileManager: fileManager) {
            guard let data = try? Data(contentsOf: url), data.count <= 512 * 1024,
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            let observed = modificationDate(url, fileManager: fileManager) ?? now
            var detail = LocalUsageDetail.parse(json, observedAt: observed)
            detail.windows = detail.windows.filter { isFresh($0, now: now) }
            guard !detail.isEmpty else { continue }
            detail.sourceDescription = url.path
            return detail
        }
        return LocalUsageDetail()
    }

    private static func claudeCandidateURLs(home: URL, fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        let names = [
            "usage-limits.json",
            "usage-cache.json",
            "usage_cache.json",
            "rate-limits.json",
            "rate_limits.json",
            "stats-cache.json",
            "oauth-usage-cache.json"
        ]
        let roots = [
            home.appendingPathComponent(".claude", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Claude-3p", isDirectory: true),
            home.appendingPathComponent(".cache/ccstatusline", isDirectory: true)
        ]
        for root in roots {
            for name in names {
                urls.append(root.appendingPathComponent(name))
            }
            // ccstatusline stores usage.json
            urls.append(root.appendingPathComponent("usage.json"))
        }
        let tmpRoots = [
            URL(fileURLWithPath: "/tmp/claude", isDirectory: true),
            home.appendingPathComponent("Library/Caches/claude", isDirectory: true)
        ]
        for tmp in tmpRoots {
            guard let kids = try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]) else {
                continue
            }
            let caches = kids.filter {
                let name = $0.lastPathComponent.lowercased()
                return $0.pathExtension == "json"
                    && (name.hasPrefix("statusline-usage-cache")
                        || name.contains("usage")
                        || name.contains("rate"))
            }.sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            urls.append(contentsOf: caches)
        }
        return urls
    }

    // MARK: - Codex / ChatGPT

    /// Newest Codex session rate_limits stay valid until reset (not a 15-minute activity TTL).
    private static func codexDetail(home: URL, now: Date, fileManager: FileManager) -> LocalUsageDetail {
        let sessionsRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsRoot.path) else { return LocalUsageDetail() }

        // Prefer newest rollout JSONL files (Codex Gauge / OpenUsage path).
        let files = newestCodexSessionFiles(under: sessionsRoot, fileManager: fileManager, limit: 12)
        for file in files {
            guard let windows = latestCodexRateLimits(in: file, fileManager: fileManager), !windows.isEmpty else {
                continue
            }
            let fresh = windows.filter { isFresh($0, now: now) }
            guard !fresh.isEmpty else { continue }
            var detail = LocalUsageDetail(windows: fresh, observedAt: fresh.map(\.observedAt).max() ?? now)
            detail.sourceDescription = file.path
            return detail
        }
        return LocalUsageDetail()
    }

    private static func newestCodexSessionFiles(under root: URL, fileManager: FileManager, limit: Int) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var scored: [(URL, Date)] = []
        var visited = 0
        while let item = enumerator.nextObject() as? URL {
            visited += 1
            if visited > 4_000 { break }
            guard item.pathExtension == "jsonl" else { continue }
            let name = item.lastPathComponent
            guard name.hasPrefix("rollout-") || name.contains("session") || name.hasSuffix(".jsonl") else { continue }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            scored.append((item, values?.contentModificationDate ?? .distantPast))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Walks a Codex JSONL from the end for the latest token_count rate_limits block.
    private static func latestCodexRateLimits(in url: URL, fileManager: FileManager) -> [RecordedQuotaWindow]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let maxBytes = min(max(size, 0), 512 * 1024)
        if size > maxBytes {
            do { try handle.seek(toOffset: UInt64(size - maxBytes)) } catch { return nil }
        }
        let data = (try? handle.readToEnd()) ?? Data()
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }

        var latest: [RecordedQuotaWindow]?
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let windows = RecordedQuotaWindow.codex(in: object) else { continue }
            if !windows.isEmpty {
                latest = windows
                break
            }
        }
        return latest
    }

    // MARK: - Cursor

    private static func cursorDetail(home: URL, now: Date, fileManager: FileManager) -> LocalUsageDetail {
        let support = home.appendingPathComponent("Library/Application Support/Cursor", isDirectory: true)
        let candidates = [
            support.appendingPathComponent("usage-cache.json"),
            support.appendingPathComponent("User/globalStorage/momo-usage-cache.json"),
            home.appendingPathComponent(".cursor/usage-cache.json")
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url), data.count <= 512 * 1024,
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            let observed = modificationDate(url, fileManager: fileManager) ?? now
            var detail = LocalUsageDetail.parse(json, observedAt: observed)
            detail.windows = detail.windows.filter { isFresh($0, now: now) }
            guard detail.hasQuotaMeters else { continue }
            detail.sourceDescription = url.path
            return detail
        }
        return LocalUsageDetail()
    }

    private static func modificationDate(_ url: URL, fileManager: FileManager) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}

extension LocalUsageDetail {
    /// Parses Claude Code statusline stdin, OAuth usage cache, or generic rate_limits blobs.
    static func parse(_ json: Any, observedAt: Date) -> LocalUsageDetail {
        var detail = LocalUsageDetail(observedAt: observedAt)
        guard let dict = json as? [String: Any] else { return detail }

        if let windows = RecordedQuotaWindow.parseFlexible(dict, observedAt: observedAt) {
            detail.windows = windows
        }

        // Claude Code statusline `cost` block
        if let cost = dict["cost"] as? [String: Any] {
            detail.totalCostUSD = flexibleNumber(cost["total_cost_usd"])
            if let ms = flexibleNumber(cost["total_api_duration_ms"]) {
                detail.durationAPISeconds = ms / 1000
            } else {
                detail.durationAPISeconds = flexibleNumber(cost["total_api_duration_seconds"])
            }
            if let ms = flexibleNumber(cost["total_duration_ms"]) {
                detail.durationWallSeconds = ms / 1000
            } else {
                detail.durationWallSeconds = flexibleNumber(cost["total_duration_seconds"])
            }
            detail.linesAdded = flexibleInt(cost["total_lines_added"])
            detail.linesRemoved = flexibleInt(cost["total_lines_removed"])
        }

        // Token breakdown from context_window / usage blocks when present
        let usageBlock = (dict["context_window"] as? [String: Any])
            ?? (dict["usage"] as? [String: Any])
            ?? (dict["current_usage"] as? [String: Any])
        if let usage = usageBlock {
            let nested = (usage["current_usage"] as? [String: Any]) ?? usage
            detail.inputTokens = flexibleInt(nested["input_tokens"])
                ?? flexibleInt(nested["total_input_tokens"])
            detail.outputTokens = flexibleInt(nested["output_tokens"])
                ?? flexibleInt(nested["total_output_tokens"])
            detail.cacheReadTokens = flexibleInt(nested["cache_read_input_tokens"])
                ?? flexibleInt(nested["cache_read_tokens"])
            detail.cacheWriteTokens = flexibleInt(nested["cache_creation_input_tokens"])
                ?? flexibleInt(nested["cache_write_tokens"])
                ?? flexibleInt(nested["cache_write_input_tokens"])
        }

        // Top-level token keys (some cache scripts flatten)
        if detail.inputTokens == nil { detail.inputTokens = flexibleInt(dict["input_tokens"]) }
        if detail.outputTokens == nil { detail.outputTokens = flexibleInt(dict["output_tokens"]) }
        if detail.cacheReadTokens == nil {
            detail.cacheReadTokens = flexibleInt(dict["cache_read_input_tokens"])
        }
        if detail.cacheWriteTokens == nil {
            detail.cacheWriteTokens = flexibleInt(dict["cache_creation_input_tokens"])
        }

        return detail
    }

    private static func flexibleNumber(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, String(cString: value.objCType) != "c", value.doubleValue.isFinite else {
            return nil
        }
        return value.doubleValue
    }

    private static func flexibleInt(_ value: Any?) -> Int? {
        guard let number = flexibleNumber(value), number >= 0, number < Double(Int.max) else { return nil }
        return Int(number.rounded(.down))
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
            // ccusage / newer OAuth: structured `limits` array
            if let limits = dict["limits"] as? [[String: Any]] {
                let mapped = windows(fromLimitsArray: limits, observedAt: observedAt)
                if !mapped.isEmpty { return mapped }
            }
            // Claude Code statusline: rate_limits.five_hour / seven_day
            // OAuth usage cache: top-level five_hour / seven_day with utilization
            if dict["five_hour"] != nil || dict["seven_day"] != nil || dict["fiveHour"] != nil
                || dict["session"] != nil || dict["5h"] != nil {
                var windows: [RecordedQuotaWindow] = []
                if let five = window(
                    from: dict["five_hour"] ?? dict["fiveHour"] ?? dict["session"] ?? dict["5h"],
                    minutes: 300,
                    observedAt: observedAt
                ) {
                    windows.append(five)
                }
                if let week = window(
                    from: dict["seven_day"] ?? dict["sevenDay"] ?? dict["week"] ?? dict["weekly"] ?? dict["7d"],
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

    private static func windows(fromLimitsArray limits: [[String: Any]], observedAt: Date) -> [RecordedQuotaWindow] {
        var result: [RecordedQuotaWindow] = []
        for entry in limits {
            let kind = ((entry["kind"] as? String) ?? (entry["type"] as? String) ?? "").lowercased()
            let minutes: Int
            if kind.contains("session") || kind.contains("five") || kind == "5h" {
                minutes = 300
            } else if kind.contains("week") || kind.contains("seven") || kind == "7d" {
                // Prefer all-models weekly; skip model-scoped duplicates for dual meters.
                if kind.contains("scoped") || entry["scope"] != nil { continue }
                minutes = 10_080
            } else {
                continue
            }
            if let window = window(from: entry, minutesHint: minutes, observedAt: observedAt) {
                if !result.contains(where: { $0.minutes == minutes }) {
                    result.append(window)
                }
            }
        }
        return result
    }

    private static func window(from value: Any?, minutes: Int, observedAt: Date) -> RecordedQuotaWindow? {
        guard let block = value as? [String: Any] else { return nil }
        return window(from: block, minutesHint: minutes, observedAt: observedAt)
    }

    private static func window(from block: [String: Any], minutesHint: Int, observedAt: Date) -> RecordedQuotaWindow? {
        let used = flexibleNumber(block["used_percentage"])
            ?? flexibleNumber(block["used_percent"])
            ?? flexibleNumber(block["utilization"])
            ?? flexibleNumber(block["percent"])
            ?? flexibleNumber(block["percent_used"])
        let remaining = flexibleNumber(block["remaining_percentage"])
            ?? flexibleNumber(block["remaining_percent"])
            ?? flexibleNumber(block["remaining"])
        let percent: Double?
        if let used, (0...100).contains(used) {
            percent = used
        } else if let remaining, (0...100).contains(remaining) {
            // ChatGPT-style “usage remaining” → MOMO displays used %.
            percent = 100 - remaining
        } else {
            percent = nil
        }
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
