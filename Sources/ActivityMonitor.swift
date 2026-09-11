import AppKit
import Combine
import Foundation

@MainActor
final class ActivityMonitor: ObservableObject {
    static let refreshInterval: TimeInterval = 15

    @Published private(set) var snapshots: [ProviderSnapshot] = .placeholder
    @Published private(set) var capabilityInventory: CapabilityInventory
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private let scanner: LocalActivityScanner
    private let inventoryScanner: CapabilityInventoryScanner
    private let enabledProviders: @MainActor () -> Set<AIProvider>

    init(
        autoRefresh: Bool = true,
        snapshots: [ProviderSnapshot] = .placeholder,
        capabilityInventory: CapabilityInventory = .empty,
        enabledProviders: @escaping @MainActor () -> Set<AIProvider> = ActivityMonitor.persistedEnabledProviders,
        sessionAdapters: [any ProviderSessionAdapter]? = nil,
        capabilityReader: CapabilityInventoryReader = CapabilityInventoryReader()
    ) {
        self.snapshots = snapshots
        self.capabilityInventory = capabilityInventory
        self.enabledProviders = enabledProviders
        scanner = LocalActivityScanner(adapters: sessionAdapters ?? Self.productionSessionAdapters)
        inventoryScanner = CapabilityInventoryScanner(reader: capabilityReader)
        if autoRefresh {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let enabledProviders = enabledProviders()
        Task {
            async let scanResult = scanner.scan(enabledProviders: enabledProviders)
            async let inventoryResult = inventoryScanner.read(enabledProviders: enabledProviders)
            let (latest, installed) = await (scanResult, inventoryResult)
            snapshots = latest
            capabilityInventory = installed.markingUsed(by: latest.flatMap(\.sessions))
            lastUpdated = .now
            isRefreshing = false
        }
    }

    func snapshot(for provider: AIProvider) -> ProviderSnapshot {
        snapshots.first(where: { $0.provider == provider })
            ?? ProviderSnapshot(
                provider: provider,
                sessions: [],
                activeCount: 0,
                localTokensToday: 0,
                updatedAt: .now,
                isInstalled: false
            )
    }

    static func persistedEnabledProviders() -> Set<AIProvider> {
        guard let saved = UserDefaults.standard.stringArray(forKey: "enabledProviders") else {
            return Set(AIProvider.allCases)
        }
        return Set(saved.compactMap(AIProvider.init(rawValue:)))
    }

    private static var productionSessionAdapters: [any ProviderSessionAdapter] {
        [ClaudeSessionAdapter(), CodexSessionAdapter(), CursorSessionAdapter()]
    }
}

private actor CapabilityInventoryScanner {
    private let reader: CapabilityInventoryReader

    init(reader: CapabilityInventoryReader) {
        self.reader = reader
    }

    func read(enabledProviders: Set<AIProvider>) -> CapabilityInventory {
        reader.read(enabledProviders: enabledProviders)
    }
}

actor LocalActivityScanner {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let adapters: ProviderSessionAdapterRegistry

    init(adapters: [any ProviderSessionAdapter] = []) {
        self.adapters = ProviderSessionAdapterRegistry(overrides: adapters)
    }

    func scan(enabledProviders: Set<AIProvider> = Set(AIProvider.allCases)) async -> [ProviderSnapshot] {
        let providers = AIProvider.allCases.filter(enabledProviders.contains)
        guard !providers.isEmpty else { return [] }

        let now = Date()
        let processes = runningAIProcesses(for: enabledProviders)
        var snapshots: [ProviderSnapshot] = []
        for provider in providers {
            let providerProcesses = processes.filter { process in
                provider.matchesProcessCommand(process.command)
            }
            let diskSessions = await recentSessions(
                for: provider,
                running: !providerProcesses.isEmpty,
                now: now
            )
            let processSessions = providerProcesses.enumerated().map { index, process in
                AgentSession(
                    id: "process-\(process.pid)",
                    provider: provider,
                    role: index == 0 ? .main : .subagent,
                    title: inferredTitle(
                        from: process.command,
                        provider: provider,
                        fallback: "Active \(provider.name) session"
                    ),
                    detail: "Local process · PID \(process.pid)",
                    project: inferredProject(from: process.command),
                    updatedAt: now,
                    isRunning: true,
                    processID: process.pid,
                    tokens: nil,
                    attention: .working,
                    attentionReason: nil,
                    model: nil,
                    mcpServers: [],
                    skills: [],
                    plugins: []
                )
            }

            let merged = Self.deduplicatedSessions(processSessions + diskSessions)
                .sorted { lhs, rhs in
                    if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
                    return lhs.updatedAt > rhs.updatedAt
                }
            let visibleSessions = Self.prioritizedSessions(merged)
            snapshots.append(ProviderSnapshot(
                provider: provider,
                sessions: visibleSessions,
                activeCount: providerProcesses.count,
                localTokensToday: diskSessions
                    .filter { Calendar.current.isDateInToday($0.updatedAt) }
                    .compactMap(\.tokens)
                    .reduce(0, +),
                updatedAt: now,
                isInstalled: !providerProcesses.isEmpty || hasSessionRoot(for: provider)
            ))
        }
        return snapshots
    }

    /// Preserve every detected live process while bounding only inactive history.
    /// This keeps the product's "all running at once" promise without re-parsing
    /// an unbounded archive on every 15-second refresh.
    static func prioritizedSessions(_ sessions: [AgentSession], recentHistoryLimit: Int = 12) -> [AgentSession] {
        let running = sessions.filter(\.isRunning)
        let history = sessions.filter { !$0.isRunning }.prefix(recentHistoryLimit)
        return running + history
    }

    private func runningAIProcesses(for enabledProviders: Set<AIProvider>) -> [(pid: Int, command: String)] {
        guard !enabledProviders.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        // Drain before waiting: a large process table can fill the pipe and deadlock both sides.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return output.split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let split = text.firstIndex(of: " "),
                  let pid = Int(text[..<split]),
                  pid != ownPID else { return nil }
            let command = String(text[text.index(after: split)...]).trimmingCharacters(in: .whitespaces)
            guard enabledProviders.contains(where: { $0.matchesProcessCommand(command) }) else { return nil }
            return (pid, command)
        }
    }

    private func recentSessions(for provider: AIProvider, running: Bool, now: Date) async -> [AgentSession] {
        let files = recentSessionFiles(for: provider, now: now)
        let context = ProviderSessionContext(now: now, isProviderRunning: running)
        let adapter = adapters.adapter(for: provider)
        let selectedFiles = files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(12)
        return await withTaskGroup(of: (Int, AgentSession?).self) { group in
            for (index, file) in selectedFiles.enumerated() {
                group.addTask {
                    (
                        index,
                        adapter.session(
                            from: ProviderSessionFile(url: file.url, modifiedAt: file.modifiedAt, index: index),
                            context: context
                        )
                    )
                }
            }
            var parsed: [(Int, AgentSession)] = []
            for await (index, session) in group {
                if let session { parsed.append((index, session)) }
            }
            return parsed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func recentSessionFiles(for provider: AIProvider, now: Date) -> [(url: URL, modifiedAt: Date)] {
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86_400)
        var files: [(url: URL, modifiedAt: Date)] = []
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
                guard values?.isRegularFile == true,
                      let modified = values?.contentModificationDate,
                      modified >= sevenDaysAgo else { continue }
                files.append((file, modified))
            }
        }
        return files
    }

    private func hasSessionRoot(for provider: AIProvider) -> Bool {
        provider.sessionRoots.contains { relativeRoot in
            var isDirectory: ObjCBool = false
            let root = home.appendingPathComponent(relativeRoot, isDirectory: true)
            return fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    static func deduplicatedSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        var seen = Set<String>()
        return sessions.filter { session in
            let key: String
            if session.isRunning {
                key = session.processID.map { "live|\(session.provider.rawValue)|pid|\($0)" }
                    ?? "live|\(session.provider.rawValue)|session|\(session.id)"
            } else {
                key = "history|\(session.provider.rawValue)|\(session.title.lowercased())|\(session.project.lowercased())"
            }
            return seen.insert(key).inserted
        }
    }

    private func inferredTitle(from command: String, provider: AIProvider, fallback: String) -> String {
        let components = command.split(separator: " ").map(String.init)
        if let index = components.firstIndex(where: {
            provider.processTerms.contains(URL(fileURLWithPath: $0).lastPathComponent.lowercased())
        }), index + 1 < components.count {
            let candidate = components[(index + 1)...].filter { !$0.hasPrefix("-") }.joined(separator: " ")
            if !candidate.isEmpty { return clean(candidate, max: 62) }
        }
        return fallback
    }

    private func inferredProject(from command: String) -> String {
        let paths = command.split(separator: " ").map(String.init).filter { $0.hasPrefix("/") }
        return paths.last.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Local"
    }

    private func clean(_ value: String, max length: Int) -> String {
        let oneLine = value.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return oneLine.count > length ? String(oneLine.prefix(length - 1)) + "…" : oneLine
    }
}
