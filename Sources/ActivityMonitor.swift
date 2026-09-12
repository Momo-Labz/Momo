import AppKit
import Combine
import Foundation
import CryptoKit

@MainActor
final class ActivityMonitor: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot] = .placeholder
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private let scanner: LocalActivityScanner
    private var authorizedProviders: Set<AIProvider> = []
    private var authorizationRevision = 0
    private var progress = SessionProgressTracker()

    init(autoRefresh: Bool = true, snapshots: [ProviderSnapshot] = .placeholder, scanner: LocalActivityScanner = LocalActivityScanner()) {
        self.scanner = scanner
        self.snapshots = snapshots
        if autoRefresh {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func setAuthorizedProviders(_ providers: Set<AIProvider>) {
        guard providers != authorizedProviders else { return }
        authorizedProviders = providers
        authorizationRevision += 1
        progress = SessionProgressTracker()
        snapshots = snapshots.filter { providers.contains($0.provider) }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let providers = authorizedProviders
        let revision = authorizationRevision
        Task {
            guard revision == authorizationRevision else {
                isRefreshing = false
                refresh()
                return
            }
            let latest = await scanner.scan(providers: providers)
            guard revision == authorizationRevision else {
                isRefreshing = false
                refresh()
                return
            }
            snapshots = progress.update(latest)
            lastUpdated = .now
            isRefreshing = false
        }
    }

    func snapshot(for provider: AIProvider) -> ProviderSnapshot {
        snapshots.first(where: { $0.provider == provider })
            ?? ProviderSnapshot(provider: provider, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: .now)
    }
}

actor LocalActivityScanner {
    private let fileManager = FileManager.default
    private let home: URL
    private let detectProcesses: Bool

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, detectProcesses: Bool = true) {
        self.home = home
        self.detectProcesses = detectProcesses
    }

    func scan(providers: Set<AIProvider>) -> [ProviderSnapshot] {
        guard !providers.isEmpty else { return [] }
        let processes = detectProcesses ? runningAIProcesses() : []
        return AIProvider.allCases.filter { providers.contains($0) }.map { provider in
            let providerProcesses = processes.filter { process in
                provider.matchesProcessCommand(process.command)
            }
            let diskSessions = recentSessions(for: provider, running: !providerProcesses.isEmpty)
            let processSessions = providerProcesses.enumerated().map { index, process in
                AgentSession(
                    id: "process-\(process.pid)",
                    provider: provider,
                    role: index == 0 ? .main : .subagent,
                    title: inferredTitle(from: process.command, fallback: "Active \(provider.name) session"),
                    detail: "Local process · PID \(process.pid)",
                    project: inferredProject(from: process.command),
                    updatedAt: .now,
                    isRunning: true,
                    processID: process.pid,
                    tokens: nil,
                    attention: .unknown,
                    attentionReason: "Process detected; chat state is not recorded",
                    model: nil,
                    mcpServers: [],
                    skills: [],
                    plugins: []
                )
            }

            let merged = deduplicated(processSessions + diskSessions)
                .sorted { lhs, rhs in
                    if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
                    return lhs.updatedAt > rhs.updatedAt
                }
            var snapshot = ProviderSnapshot(
                provider: provider,
                sessions: merged,
                activeCount: providerProcesses.count,
                localTokensToday: diskSessions.filter { Calendar.current.isDateInToday($0.updatedAt) }.compactMap(\.tokens).reduce(0, +),
                updatedAt: .now
            )
            snapshot.recordedQuota = diskSessions.flatMap(\.recordedQuotaWindows).sorted {
                if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
                return $0.minutes < $1.minutes
            }.first
            return snapshot
        }
    }

    private func runningAIProcesses() -> [(pid: Int, command: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return output.split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let split = text.firstIndex(of: " "), let pid = Int(text[..<split]), pid != ownPID else { return nil }
            let command = String(text[text.index(after: split)...]).trimmingCharacters(in: .whitespaces)
            guard AIProvider.allCases.contains(where: { $0.matchesProcessCommand(command) }) else { return nil }
            return (pid, command)
        }
    }

    private func recentSessions(for provider: AIProvider, running: Bool) -> [AgentSession] {
        guard provider != .grok else { return [] } // Await an authorized, identified Grok schema.
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86_400)
        var files: [URL] = []
        for relativeRoot in provider.sessionRoots {
            let root = home.appendingPathComponent(relativeRoot, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let file as URL in enumerator {
                guard file.pathExtension == "jsonl" || (provider == .gemini && file.pathExtension == "json") else { continue }
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified >= sevenDaysAgo else { continue }
                files.append(file)
            }
        }

        return files.sorted { modifiedDate($0) > modifiedDate($1) }.prefix(20).compactMap { file in
            if provider == .gemini {
                // Whole-file parsing preserves JSONL revisions and rewinds. Never
                // publish a partial tail as if it represented the full conversation.
                guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= 16 * 1024 * 1024,
                      let data = try? Data(contentsOf: file) else { return nil }
                return GeminiSessionAdapter.parse(data, source: file)
            }
            let metadata = sessionMetadata(from: file, provider: provider)
            return AgentSession(
                id: "\(provider.rawValue)-\(file.path)",
                provider: provider,
                role: metadata.isSubagent ? .subagent : .main,
                title: metadata.title ?? humanized(file.deletingPathExtension().lastPathComponent),
                detail: metadata.detail ?? "Recent local session",
                project: metadata.project ?? humanized(file.deletingLastPathComponent().lastPathComponent),
                updatedAt: modifiedDate(file),
                isRunning: false,
                processID: nil,
                tokens: metadata.tokens,
                attention: metadata.attention,
                attentionReason: metadata.attentionReason,
                model: metadata.capabilities.model,
                mcpServers: metadata.capabilities.mcpServers.sorted(),
                skills: metadata.capabilities.skills.sorted(),
                plugins: metadata.capabilities.plugins.sorted(),
                sourceURL: file,
                recordedQuotaWindows: metadata.quotaWindows
            )
        }
    }

    private func sessionMetadata(from url: URL, provider: AIProvider) -> (title: String?, detail: String?, project: String?, tokens: Int?, isSubagent: Bool, attention: AgentAttention, attentionReason: String?, capabilities: SessionCapabilities, quotaWindows: [RecordedQuotaWindow]) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil, nil, nil, false, .unknown, nil, SessionCapabilities(), []) }
        defer { try? handle.close() }
        let maxBytes = 320 * 1024
        let head = (try? handle.read(upToCount: maxBytes / 2)) ?? Data()
        let size = (try? handle.seekToEnd()) ?? 0
        if size > UInt64(maxBytes / 2) {
            try? handle.seek(toOffset: size - UInt64(maxBytes / 2))
        }
        let tail = (try? handle.read(upToCount: maxBytes / 2)) ?? Data()
        var data = head
        data.append(Data("\n".utf8))
        data.append(tail)
        guard let text = String(data: data, encoding: .utf8) else { return (nil, nil, nil, nil, false, .unknown, nil, SessionCapabilities(), []) }

        var title: String?
        var detail: String?
        var project: String?
        var tokens = 0
        var isSubagent = false
        var attention: AgentAttention = .unknown
        var attentionReason: String?
        var capabilities = SessionCapabilities()
        var quotaWindows: [RecordedQuotaWindow] = []

        for line in text.split(separator: "\n").suffix(500) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if project == nil { project = findString(in: object, keys: ["cwd", "project_path"]).map { URL(fileURLWithPath: $0).lastPathComponent } }
            if title == nil, let candidate = findString(in: object, keys: ["objective", "prompt", "task", "user_message"]) {
                title = clean(candidate, max: 68)
            }
            if detail == nil, let candidate = findString(in: object, keys: ["message", "summary", "last_message"]) {
                detail = clean(candidate, max: 88)
            }
            tokens = max(tokens, findInt(in: object, keys: ["total_tokens", "tokens_used", "input_tokens", "output_tokens"]) ?? 0)
            if let role = findString(in: object, keys: ["role", "agent_role", "agent_type"])?.lowercased(), role.contains("sub") {
                isSubagent = true
            }
            if let signal = SessionSignal.recorded(in: object, provider: provider) {
                attention = signal.state
                attentionReason = signal.reason
            }
            capabilities.merge(SessionCapabilities.recorded(in: object, provider: provider))
            if provider == .codex, let windows = RecordedQuotaWindow.codex(in: object) { quotaWindows = windows }
        }
        return (title, detail, project, tokens == 0 ? nil : tokens, isSubagent, attention, attentionReason, capabilities, quotaWindows)
    }

    private func findString(in value: Any, keys: Set<String>) -> String? {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if keys.contains(key), let text = child as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                if let found = findString(in: child, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array { if let found = findString(in: child, keys: keys) { return found } }
        }
        return nil
    }

    private func findInt(in value: Any, keys: Set<String>) -> Int? {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if keys.contains(key), let number = child as? NSNumber { return number.intValue }
                if let found = findInt(in: child, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array { if let found = findInt(in: child, keys: keys) { return found } }
        }
        return nil
    }

    private func deduplicated(_ sessions: [AgentSession]) -> [AgentSession] {
        var seen = Set<String>()
        return sessions.filter { session in
            let key = session.id
            return seen.insert(key).inserted
        }
    }

    private func modifiedDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func inferredTitle(from command: String, fallback: String) -> String {
        let components = command.split(separator: " ").map(String.init)
        if let index = components.firstIndex(where: { AIProvider.allCases.flatMap(\.processTerms).contains(URL(fileURLWithPath: $0).lastPathComponent.lowercased()) }), index + 1 < components.count {
            let candidate = components[(index + 1)...].filter { !$0.hasPrefix("-") }.joined(separator: " ")
            if !candidate.isEmpty { return clean(candidate, max: 62) }
        }
        return fallback
    }

    private func inferredProject(from command: String) -> String {
        let paths = command.split(separator: " ").map(String.init).filter { $0.hasPrefix("/") }
        return paths.last.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Local"
    }

    private func humanized(_ value: String) -> String {
        let replaced = value.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return replaced.isEmpty ? "Untitled" : replaced.capitalized
    }

    private func clean(_ value: String, max length: Int) -> String {
        let oneLine = value.replacingOccurrences(of: "\n", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.count > length ? String(oneLine.prefix(length - 1)) + "…" : oneLine
    }
}


/// Only structured provider errors and reset windows can authorize a retry.
/// Free text, process presence, and "stopped after usage" are never inputs.
struct CodexResumeCandidate: Equatable {
    let sessionID: String
    let directory: String
    let resetAt: Date
    let fingerprint: String
    var key: String { "\(sessionID)|\(Int(resetAt.timeIntervalSince1970))" }

    static func parse(_ data: Data) -> CodexResumeCandidate? {
        guard data.count <= 16 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8) else { return nil }
        var metadata: [String: Any] = [:]
        var windows: [[String: Any]] = []
        var usageStopped = false
        var terminal = false
        for line in text.split(separator: "\n") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = event["payload"] as? [String: Any] else { return nil }
            let type = event["type"] as? String
            if type == "session_meta" { metadata = payload }
            if type == "response_item", payload["role"] as? String == "user" { usageStopped = false; terminal = false }
            guard type == "event_msg" else { continue }
            switch payload["type"] as? String {
            case "token_count":
                if let limits = payload["rate_limits"] as? [String: Any] {
                    windows = [limits["primary"], limits["secondary"]].compactMap { $0 as? [String: Any] }
                }
            case "error", "turn_error": usageStopped = isUsageError(payload); terminal = false
            case "task_complete":
                terminal = true
                if let error = payload["error"] as? [String: Any] { usageStopped = isUsageError(error) }
                else if let answer = payload["last_agent_message"] as? String, !answer.isEmpty { usageStopped = false }
            case "task_started", "turn_aborted", "user_message", "request_user_input", "exec_approval_request", "apply_patch_approval_request":
                usageStopped = false; terminal = false
            default: break
            }
        }
        guard usageStopped, terminal, metadata["source"] as? String == "cli",
              let id = metadata["id"] as? String, UUID(uuidString: id) != nil,
              let cwd = metadata["cwd"] as? String, cwd.hasPrefix("/"), !cwd.contains("\0") else { return nil }
        let exhausted = windows.filter { ($0["used_percent"] as? NSNumber)?.doubleValue ?? -1 >= 100 }
        guard !exhausted.isEmpty else { return nil }
        var resets: [Double] = []
        for window in exhausted {
            guard let reset = window["resets_at"] as? NSNumber,
                  String(cString: reset.objCType) != "c", reset.doubleValue.isFinite,
                  reset.doubleValue > 0, reset.doubleValue < 32_503_680_000 else { return nil }
            resets.append(reset.doubleValue)
        }
        return CodexResumeCandidate(sessionID: id, directory: cwd,
                                    resetAt: Date(timeIntervalSince1970: resets.max()!),
                                    fingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    private static func isUsageError(_ error: [String: Any]) -> Bool {
        let kind = error["codex_error_info"] as? String ?? error["codexErrorInfo"] as? String
        return kind == "usage_limit_exceeded" || kind == "usageLimitExceeded"
    }

    var arguments: [String] {
        ["exec", "resume", sessionID, "Continue the existing task from where the recorded usage limit interrupted it. Keep the original scope and permissions. If the task is complete or requires new user input, stop and report that."]
    }
}

@MainActor
final class AutoResumeService: ObservableObject {
    static let shared = AutoResumeService()
    @Published private(set) var status = "Off"
    private let defaults: UserDefaults
    private var attempted: Set<String>
    private var process: Process?
    private let executableOverride: URL?

    init(defaults: UserDefaults = .standard, executableURL: URL? = nil) {
        executableOverride = executableURL
        self.defaults = defaults
        attempted = Set(defaults.stringArray(forKey: "autoResume.attempted.v1") ?? [])
    }

    func update(snapshots: [ProviderSnapshot], enabled: Bool, authorized: Set<AIProvider>, now: Date = .now) {
        guard enabled else { status = "Off · no new automatic continuations"; return }
        guard authorized.contains(.codex) else { status = "Waiting for Codex local-provider authorization"; return }
        guard process == nil else { return }
        guard let executable = executable else { status = "Codex CLI is not installed at a supported location"; return }
        status = "Watching for recorded Codex CLI usage stops"
        for session in snapshots.filter({ $0.provider == .codex }).flatMap(\.sessions) {
            guard let source = session.sourceURL,
                  let data = boundedRead(source), let candidate = CodexResumeCandidate.parse(data),
                  !attempted.contains(candidate.key) else { continue }
            guard now >= candidate.resetAt.addingTimeInterval(5) else {
                status = "Waiting for reset: \(candidate.resetAt.formatted(date: .omitted, time: .shortened))"
                continue
            }
            // Re-read immediately before dispatch. A new user turn, manual stop,
            // or any other rollout change cancels this stale candidate.
            guard let fresh = boundedRead(source), CodexResumeCandidate.parse(fresh) == candidate else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                status = "Cannot resume: the recorded project folder is unavailable"; continue
            }
            // Persist before launching: app restart or uncertain exit cannot
            // send a second continuation for this same session/reset pair.
            attempted.insert(candidate.key)
            defaults.set(attempted.sorted(), forKey: "autoResume.attempted.v1")
            let child = Process()
            child.executableURL = executable
            child.arguments = candidate.arguments
            child.currentDirectoryURL = URL(fileURLWithPath: candidate.directory)
            child.standardInput = FileHandle.nullDevice
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                let succeeded = child.terminationStatus == 0
                Task { @MainActor in
                    self?.status = succeeded ? "Automatic continuation finished" : "Automatic continuation stopped with an error; no repeated retry"
                    self?.process = nil
                }
            }
            process = child
            do { try child.run(); status = "Automatically continuing a Codex CLI chat" }
            catch { process = nil; status = "Could not start Codex; no repeated retry" }
            return
        }
    }

    private var executable: URL? {
        if let executableOverride { return executableOverride }
        return ["/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    private func boundedRead(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16 * 1024 * 1024 + 1), data.count <= 16 * 1024 * 1024 else { return nil }
        return data
    }
}
