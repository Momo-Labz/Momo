import Foundation

/// Result of a read-only local CLI / cache probe. Never invents percentages.
struct ProviderUsageProbeResult: Equatable {
    var detail: LocalUsageDetail = LocalUsageDetail()
    /// Machine-readable blocker when meters are empty.
    var emptyReason: UsageEmptyReason?
    var lastError: String?
}

/// Specific empty-state copy + next action. Every empty provider must surface one of these.
enum UsageEmptyReason: Equatable {
    case privacyBlocked(provider: AIProvider)
    case claudeNoCacheInstallCLI
    case claudeCLIPresentRunOnce
    case claudeAppOnlyNoLocalFile
    case codexNoSessionRateLimits
    case codexCLIMissing
    case chatgptAppOnlyNoLocalFile
    case cursorNoLocalUsageCache
    case cursorCLIMissing
    case grokNoLocalUsage
    case grokCLIMissing
    case geminiNoLocalUsage
    case cliTimedOut(command: String)
    case cliFailed(command: String, message: String)
    case refreshFailed(message: String)

    var message: String {
        switch self {
        case .privacyBlocked(let provider):
            return LocalUsageArtifactReader.privacyGuidance(for: provider)
        case .claudeNoCacheInstallCLI:
            return "No readable Claude usage cache. Install Claude Code CLI (`claude`), sign in, and run once — or run `ccusage` to write ~/.claude/usage-limits.json. Claude.app menu % is live from Anthropic and is not stored as a plaintext file MOMO can read."
        case .claudeCLIPresentRunOnce:
            return "Claude Code CLI is installed, but no usage cache yet. Open Claude / run `claude` once (or `ccusage`) so ~/.claude/usage-limits.json or a /tmp/claude statusline cache exists."
        case .claudeAppOnlyNoLocalFile:
            return "Claude.app is installed and shows live menu usage, but MOMO only reads local Claude Code caches (~/.claude, /tmp/claude) or `ccusage json`. Install/sign in to Claude Code CLI, or run `ccusage` once."
        case .codexNoSessionRateLimits:
            return "No Codex rate_limits in ~/.codex/sessions yet. ChatGPT.app “usage remaining” is not a local file MOMO can read. Run Codex (or ChatGPT desktop Codex) once so a rollout-*.jsonl records primary/secondary used_percent."
        case .codexCLIMissing:
            return "Codex/ChatGPT usage needs a local Codex session log. Install Codex CLI (`codex`) or open ChatGPT/Codex desktop and send one message so ~/.codex/sessions gets rate_limits."
        case .chatgptAppOnlyNoLocalFile:
            return "ChatGPT.app shows 5h/weekly remaining in its own UI; those numbers are not written as plaintext for other apps. MOMO reads Codex CLI session rate_limits under ~/.codex/sessions (used %, until reset)."
        case .cursorNoLocalUsageCache:
            return "Cursor transcripts do not expose account %. Bars appear only if a local usage-cache.json is present under Cursor Support or ~/.cursor."
        case .cursorCLIMissing:
            return "Cursor CLI/binary not found and no local usage-cache.json. Install Cursor, or place a usage-cache.json MOMO can read — otherwise account % is unavailable."
        case .grokNoLocalUsage:
            return "No readable local Grok usage cache or CLI usage output on this Mac. Grok account % is not exposed in session files MOMO supports."
        case .grokCLIMissing:
            return "Grok CLI not found and no local usage cache. Install/sign in to Grok if a CLI exists, or MOMO cannot show account %."
        case .geminiNoLocalUsage:
            return "No readable local Gemini usage cache on this Mac."
        case .cliTimedOut(let command):
            return "Timed out running `\(command)`. Retry refresh, or run that command in Terminal to create a local usage cache."
        case .cliFailed(let command, let message):
            return "`\(command)` failed: \(message)"
        case .refreshFailed(let message):
            return "Usage refresh failed: \(message)"
        }
    }

    var nextActionTitle: String? {
        switch self {
        case .privacyBlocked: return "Open Privacy Settings"
        case .claudeNoCacheInstallCLI, .claudeCLIPresentRunOnce, .claudeAppOnlyNoLocalFile:
            return nil
        case .codexNoSessionRateLimits, .codexCLIMissing, .chatgptAppOnlyNoLocalFile:
            return nil
        default: return nil
        }
    }
}

/// Detects provider CLIs and runs safe read-only usage commands off the caller's thread.
/// Never prompts for Keychain; never scrapes cookies; never invents %.
enum ProviderCLIUsageProbe {
    static let defaultTimeout: TimeInterval = 8

    /// Synchronous probe suitable for `Task.detached`. Prefer caches first via `LocalUsageArtifactReader`.
    static func probe(
        provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: Date = .now,
        timeout: TimeInterval = defaultTimeout,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> ProviderUsageProbeResult {
        // 1) Local artifacts / session rate_limits (no network).
        var detail = LocalUsageArtifactReader.detail(for: provider, home: home, now: now, fileManager: fileManager)
        if !detail.windows.isEmpty || detail.hasSessionStats {
            return ProviderUsageProbeResult(detail: detail, emptyReason: nil)
        }

        if LocalUsageArtifactReader.isSessionRootPrivacyBlocked(provider, home: home, fileManager: fileManager) {
            return ProviderUsageProbeResult(emptyReason: .privacyBlocked(provider: provider))
        }

        // 2) Optional read-only CLI helpers that write/print the same windows.
        switch provider {
        case .claude:
            if let cli = runCCUsageJSON(timeout: timeout, pathEnvironment: pathEnvironment) {
                if !cli.detail.isEmpty {
                    return ProviderUsageProbeResult(detail: cli.detail, emptyReason: nil)
                }
                if let reason = cli.emptyReason {
                    return ProviderUsageProbeResult(emptyReason: reason, lastError: cli.lastError)
                }
            }
            return ProviderUsageProbeResult(emptyReason: diagnoseClaude(home: home, fileManager: fileManager, pathEnvironment: pathEnvironment))
        case .codex:
            return ProviderUsageProbeResult(emptyReason: diagnoseCodex(home: home, fileManager: fileManager, pathEnvironment: pathEnvironment))
        case .cursor:
            return ProviderUsageProbeResult(emptyReason: diagnoseCursor(home: home, fileManager: fileManager, pathEnvironment: pathEnvironment))
        case .grok:
            return ProviderUsageProbeResult(emptyReason: which("grok", pathEnvironment: pathEnvironment) == nil ? .grokCLIMissing : .grokNoLocalUsage)
        case .gemini:
            return ProviderUsageProbeResult(emptyReason: .geminiNoLocalUsage)
        }
    }

    static func which(_ name: String, pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
        let path = pathEnvironment ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
        for dir in path.split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir), isDirectory: true).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        // Common npm / bun global locations when PATH is stripped in GUI apps.
        let extras = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(name)"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/current/bin/\(name)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)")
        ]
        return extras.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Per-provider diagnosis

    private static func diagnoseClaude(home: URL, fileManager: FileManager, pathEnvironment: String?) -> UsageEmptyReason {
        let hasClaudeCLI = which("claude", pathEnvironment: pathEnvironment) != nil
        let hasCCUsage = which("ccusage", pathEnvironment: pathEnvironment) != nil
        let appInstalled = DesktopAppCatalog.isPresentOnDisk(.claude)
        if hasClaudeCLI || hasCCUsage {
            return .claudeCLIPresentRunOnce
        }
        if appInstalled {
            return .claudeAppOnlyNoLocalFile
        }
        return .claudeNoCacheInstallCLI
    }

    private static func diagnoseCodex(home: URL, fileManager: FileManager, pathEnvironment: String?) -> UsageEmptyReason {
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let hasSessionsDir = fileManager.fileExists(atPath: sessions.path)
        let hasCodexCLI = which("codex", pathEnvironment: pathEnvironment) != nil
        let chatGPTInstalled = DesktopAppCatalog.isPresentOnDisk(.codex)
        if hasSessionsDir {
            return chatGPTInstalled ? .chatgptAppOnlyNoLocalFile : .codexNoSessionRateLimits
        }
        if !hasCodexCLI && chatGPTInstalled {
            return .chatgptAppOnlyNoLocalFile
        }
        if !hasCodexCLI {
            return .codexCLIMissing
        }
        return .codexNoSessionRateLimits
    }

    private static func diagnoseCursor(home: URL, fileManager: FileManager, pathEnvironment: String?) -> UsageEmptyReason {
        if which("cursor", pathEnvironment: pathEnvironment) == nil,
           !DesktopAppCatalog.isPresentOnDisk(.cursor) {
            return .cursorCLIMissing
        }
        return .cursorNoLocalUsageCache
    }

    // MARK: - CLI runners

    /// `ccusage json` prints Anthropic OAuth usage windows (same family as Claude menu / Claude Code).
    private static func runCCUsageJSON(timeout: TimeInterval, pathEnvironment: String?) -> ProviderUsageProbeResult? {
        guard let binary = which("ccusage", pathEnvironment: pathEnvironment) else { return nil }
        let outcome = runProcess(
            executable: binary,
            arguments: ["json"],
            timeout: timeout
        )
        switch outcome {
        case .timedOut:
            return ProviderUsageProbeResult(emptyReason: .cliTimedOut(command: "ccusage json"))
        case .failed(let message):
            return ProviderUsageProbeResult(emptyReason: .cliFailed(command: "ccusage json", message: message), lastError: message)
        case .ok(let stdout):
            guard let data = stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                return ProviderUsageProbeResult(
                    emptyReason: .cliFailed(command: "ccusage json", message: "unreadable JSON"),
                    lastError: "unreadable JSON"
                )
            }
            var detail = LocalUsageDetail.parse(json, observedAt: .now)
            // ccusage sometimes nests under `limits` / named keys — parseFlexible already covers five_hour/seven_day.
            if detail.windows.isEmpty, let dict = json as? [String: Any] {
                if let windows = RecordedQuotaWindow.parseFlexible(dict, observedAt: .now) {
                    detail.windows = windows
                }
            }
            detail.windows = detail.windows.filter { LocalUsageArtifactReader.isFresh($0) }
            detail.sourceDescription = "ccusage json"
            if detail.isEmpty {
                return ProviderUsageProbeResult(
                    emptyReason: .cliFailed(command: "ccusage json", message: "no five_hour/seven_day windows"),
                    lastError: "no windows"
                )
            }
            return ProviderUsageProbeResult(detail: detail)
        }
    }

    private enum ProcessOutcome {
        case ok(String)
        case timedOut
        case failed(String)
    }

    private static func runProcess(executable: URL, arguments: [String], timeout: TimeInterval) -> ProcessOutcome {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .failed(error.localizedDescription)
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        let waited = group.wait(timeout: .now() + timeout)
        if waited == .timedOut {
            process.terminate()
            return .timedOut
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        let errText = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            return .failed(errText.isEmpty ? "exit \(process.terminationStatus)" : String(errText.prefix(200)))
        }
        return .ok(outText)
    }
}
