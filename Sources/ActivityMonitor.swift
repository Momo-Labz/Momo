import AppKit
import Combine
import Foundation

@MainActor
final class ActivityMonitor: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot] = .placeholder
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private let scanner = LocalActivityScanner()

    init(autoRefresh: Bool = true, snapshots: [ProviderSnapshot] = .placeholder) {
        self.snapshots = snapshots
        if autoRefresh {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let latest = await scanner.scan()
            snapshots = latest
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
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func scan() -> [ProviderSnapshot] {
        let processes = runningAIProcesses()
        return AIProvider.allCases.map { provider in
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
                    attention: .working,
                    attentionReason: nil
                )
            }

            let merged = deduplicated(processSessions + diskSessions)
                .sorted { lhs, rhs in
                    if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
                    return lhs.updatedAt > rhs.updatedAt
                }
            return ProviderSnapshot(
                provider: provider,
                sessions: Array(merged.prefix(12)),
                activeCount: providerProcesses.count,
                localTokensToday: diskSessions.filter { Calendar.current.isDateInToday($0.updatedAt) }.compactMap(\.tokens).reduce(0, +),
                updatedAt: .now
            )
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
                guard file.pathExtension == "jsonl" else { continue }
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified >= sevenDaysAgo else { continue }
                files.append(file)
            }
        }

        return files.sorted { modifiedDate($0) > modifiedDate($1) }.prefix(20).enumerated().map { index, file in
            let metadata = sessionMetadata(from: file)
            return AgentSession(
                id: "\(provider.rawValue)-\(file.path)",
                provider: provider,
                role: metadata.isSubagent ? .subagent : .main,
                title: metadata.title ?? humanized(file.deletingPathExtension().lastPathComponent),
                detail: metadata.detail ?? "Recent local session",
                project: metadata.project ?? humanized(file.deletingLastPathComponent().lastPathComponent),
                updatedAt: modifiedDate(file),
                isRunning: running && index == 0,
                processID: nil,
                tokens: metadata.tokens,
                attention: metadata.attention,
                attentionReason: metadata.attentionReason
            )
        }
    }

    private func sessionMetadata(from url: URL) -> (title: String?, detail: String?, project: String?, tokens: Int?, isSubagent: Bool, attention: AgentAttention, attentionReason: String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil, nil, nil, false, .working, nil) }
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
        guard let text = String(data: data, encoding: .utf8) else { return (nil, nil, nil, nil, false, .working, nil) }

        var title: String?
        var detail: String?
        var project: String?
        var tokens = 0
        var isSubagent = false
        var attention: AgentAttention = .working
        var attentionReason: String?

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
            if let signal = attentionSignal(in: object) {
                attention = signal.state
                attentionReason = signal.reason
            }
        }
        return (title, detail, project, tokens == 0 ? nil : tokens, isSubagent, attention, attentionReason)
    }

    private func attentionSignal(in object: [String: Any]) -> (state: AgentAttention, reason: String)? {
        let type = findString(in: object, keys: ["type", "event", "event_type", "status", "state"])?.lowercased() ?? ""
        let explicitNeedsInput = ["approval_request", "request_user_input", "requires_action", "waiting_for_user", "needs_input"]
        if explicitNeedsInput.contains(where: { type.contains($0) }) {
            return (.needsInput, "The agent is waiting for your response")
        }
        if ["failed", "error", "cancelled"].contains(where: { type == $0 || type.hasSuffix("_\($0)") }) {
            return (.failed, "The latest agent event failed")
        }
        if ["completed", "complete", "finished", "done"].contains(type) {
            return (.completed, "The latest task finished")
        }
        return nil
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
            let key = "\(session.provider.rawValue)|\(session.title.lowercased())|\(session.project.lowercased())"
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
