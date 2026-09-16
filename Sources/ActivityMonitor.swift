import AppKit
import Combine
import Foundation
import CryptoKit
import SQLite3

@MainActor
final class ActivityMonitor: ObservableObject {
    // Keep the menu responsive without polling provider folders every few
    // seconds. File mtimes and the session cache make each refresh cheap.
    static let refreshInterval: TimeInterval = 60
    static func configuredRefreshInterval() -> TimeInterval {
        TimeInterval(PreferencesStore.normalizedRefreshInterval(UserDefaults.standard.integer(forKey: "refreshIntervalSeconds.v1")))
    }

    @Published private(set) var snapshots: [ProviderSnapshot] = .placeholder
    @Published private(set) var capabilityInventory: CapabilityInventory
    @Published private(set) var sessionEvidence: [SessionEvidence] = []
    @Published private(set) var usageObservations: [ProviderUsageObservation] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private var menuIsVisible = false
    private let scanner: LocalActivityScanner
    private let trackingCache: TrackingCache
    private let inventoryScanner: CapabilityInventoryScanner
    private var authorizedProviders: Set<AIProvider>?
    private var authorizationRevision = 0
    private var refreshRequested = false
    private var progress = SessionProgressTracker()
    private let enabledProviders: @MainActor () -> Set<AIProvider>

    init(
        autoRefresh: Bool = true,
        snapshots: [ProviderSnapshot] = .placeholder,
        capabilityInventory: CapabilityInventory = .empty,
        enabledProviders: @escaping @MainActor () -> Set<AIProvider> = ActivityMonitor.persistedEnabledProviders,
        sessionAdapters: [any ProviderSessionAdapter]? = nil,
        capabilityReader: CapabilityInventoryReader = CapabilityInventoryReader(),
        scanner: LocalActivityScanner? = nil,
        trackingCache: TrackingCache = TrackingCache()
    ) {
        self.snapshots = snapshots
        self.capabilityInventory = capabilityInventory
        self.enabledProviders = enabledProviders
        self.scanner = scanner ?? LocalActivityScanner(adapters: sessionAdapters ?? Self.productionSessionAdapters)
        self.trackingCache = trackingCache
        inventoryScanner = CapabilityInventoryScanner(reader: capabilityReader)
        if autoRefresh {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let baseInterval = Self.configuredRefreshInterval()
                    let interval: TimeInterval = self.menuIsVisible ? baseInterval : max(300, baseInterval)
                    if self.lastUpdated.map({ Date().timeIntervalSince($0) >= interval }) ?? true { self.refresh() }
                }
            }
            timer?.tolerance = 5
        }
    }

    func setMenuVisible(_ visible: Bool) { menuIsVisible = visible }

    func setAuthorizedProviders(_ providers: Set<AIProvider>) {
        guard providers != authorizedProviders else { return }
        authorizedProviders = providers
        authorizationRevision += 1
        progress = SessionProgressTracker()
        snapshots = snapshots.filter { providers.contains($0.provider) }
        sessionEvidence.removeAll()
        usageObservations.removeAll()
        capabilityInventory = .empty
        refresh()
    }

    func setAuthorizedRoots(_ roots: [AIProvider: [URL]]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await scanner.setAuthorizedRoots(roots)
            refresh()
        }
    }

    func refresh() {
        refreshRequested = true
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            while refreshRequested {
                refreshRequested = false
                let providers = authorizedProviders ?? enabledProviders()
                let revision = authorizationRevision
                async let scanResult = scanner.scan(enabledProviders: providers)
                async let inventoryResult = inventoryScanner.read(enabledProviders: providers)
                let (latest, installed) = await (scanResult, inventoryResult)
                guard revision == authorizationRevision else {
                    refreshRequested = true
                    continue
                }
                let updatedSnapshots = progress.update(latest)
                snapshots = updatedSnapshots
                sessionEvidence = Self.evidence(from: updatedSnapshots)
                _ = await trackingCache.accept(Self.usage(from: updatedSnapshots), now: .now)
                usageObservations = await trackingCache.observations(now: .now)
                capabilityInventory = installed.markingUsed(by: latest.flatMap(\.sessions))
                lastUpdated = .now
            }
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
        guard let saved = UserDefaults.standard.stringArray(forKey: "authorizedLocalProviders.v1") else {
            return []
        }
        return Set(saved.compactMap(AIProvider.init(rawValue:)))
    }

    private static var productionSessionAdapters: [any ProviderSessionAdapter] {
        [ClaudeSessionAdapter(), CodexSessionAdapter(), CursorSessionAdapter(), GrokSessionAdapter()]
    }

    private static func evidence(from snapshots: [ProviderSnapshot]) -> [SessionEvidence] {
        snapshots.flatMap { snapshot in
            snapshot.sessions.map { session in
                SessionEvidence(
                    provider: session.provider,
                    sessionID: session.id,
                    conversationID: session.conversationID,
                    event: session.attentionReason ?? session.attention.rawValue,
                    state: session.attention,
                    observedAt: session.updatedAt,
                    source: session.recordedSource ?? session.sourceURL?.lastPathComponent ?? "local session"
                )
            }
        }
    }

    private static func usage(from snapshots: [ProviderSnapshot]) -> [ProviderUsageObservation] {
        snapshots.flatMap { snapshot in
            let windows = snapshot.recordedQuotas.isEmpty
                ? snapshot.recordedQuota.map { [$0] } ?? []
                : snapshot.recordedQuotas
            return windows.map { window in
                ProviderUsageObservation(
                    provider: snapshot.provider,
                    metric: window.durationLabel,
                    percentage: Int(window.percent.rounded()),
                    resetsAt: window.resetsAt,
                    capturedAt: window.observedAt,
                    freshness: TrackingCache.acceptedObservationFreshness,
                    provenance: .providerEvent
                )
            }
        }
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
    static let recentFileLimit = 20
    static let directoryEntryLimit = 10_000
    private let fileManager = FileManager.default
    private let home: URL
    private let detectProcesses: Bool
    private let adapters: ProviderSessionAdapterRegistry
    private var authorizedRoots: [AIProvider: [URL]]
    private struct CachedSession {
        let modifiedAt: Date
        let fileSize: Int
        let session: AgentSession?
    }
    private var sessionCache: [String: CachedSession] = [:]
    private var codexNameCache = CodexNameCache()

    init(adapters: [any ProviderSessionAdapter] = [ClaudeSessionAdapter(), CodexSessionAdapter(), CursorSessionAdapter(), GrokSessionAdapter()], home: URL = FileManager.default.homeDirectoryForCurrentUser, detectProcesses: Bool = true, authorizedRoots: [AIProvider: [URL]] = [:]) {
        self.home = home
        self.detectProcesses = detectProcesses
        self.adapters = ProviderSessionAdapterRegistry(overrides: adapters)
        self.authorizedRoots = authorizedRoots
    }

    func setAuthorizedRoots(_ roots: [AIProvider: [URL]]) {
        authorizedRoots = roots
        sessionCache.removeAll()
        codexNameCache = CodexNameCache()
    }

    func scan(providers: Set<AIProvider>) async -> [ProviderSnapshot] { await scan(enabledProviders: providers) }

    func scan(enabledProviders: Set<AIProvider> = []) async -> [ProviderSnapshot] {
        let providers = AIProvider.allCases.filter(enabledProviders.contains)
        guard !providers.isEmpty else { return [] }

        let now = Date()
        let enabledPrefixes = Set(providers.map { "\($0.rawValue)|" })
        sessionCache = sessionCache.filter { key, _ in enabledPrefixes.contains(where: { key.hasPrefix($0) }) }
        let processes = detectProcesses ? runningAIProcesses(for: enabledProviders) : []
        var snapshots: [ProviderSnapshot] = []
        for provider in providers {
            let providerProcesses = processes.filter { process in
                provider.matchesProcessCommand(process.command)
            }
            var diskSessions = await recentSessions(
                for: provider,
                running: !providerProcesses.isEmpty,
                now: now
            )
            if provider == .codex {
                let ids = Set(diskSessions.map { SessionPresentation.fullIdentity(for: $0) })
                let codexNames = codexNameCache.names(for: ids, home: home, fileManager: fileManager)
                for index in diskSessions.indices {
                    if let name = codexNames[SessionPresentation.fullIdentity(for: diskSessions[index])] {
                        diskSessions[index].title = name
                    }
                }
            }
            let merged = Self.deduplicatedSessions(diskSessions)
                .sorted { lhs, rhs in
                    if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
                    return lhs.updatedAt > rhs.updatedAt
                }
            var snapshot = ProviderSnapshot(
                provider: provider,
                sessions: merged,
                activeCount: merged.filter(\.isRunning).count,
                localTokensToday: diskSessions
                    .filter { Calendar.current.isDateInToday($0.updatedAt) }
                    .compactMap(\.tokens)
                    .reduce(0, +),
                updatedAt: now,
                isInstalled: !providerProcesses.isEmpty || hasSessionRoot(for: provider)
            )
            let freshWindows = diskSessions.flatMap(\.recordedQuotaWindows).filter {
                now >= $0.observedAt
                    && now.timeIntervalSince($0.observedAt) <= TrackingCache.acceptedObservationFreshness
            }
            snapshot.recordedQuota = freshWindows.sorted {
                if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
                return $0.minutes < $1.minutes
            }.first
            if let latest = snapshot.recordedQuota?.observedAt {
                var durations = Set<Int>()
                snapshot.recordedQuotas = freshWindows
                    .filter { $0.observedAt == latest && durations.insert($0.minutes).inserted }
            }
            snapshots.append(snapshot)
        }
        return snapshots
    }

    /// Preserve every session with recorded live evidence while bounding history.
    static func prioritizedSessions(_ sessions: [AgentSession], recentHistoryLimit: Int = 12) -> [AgentSession] {
        let unique = SessionPresentation.relevant(sessions, limit: sessions.count)
        let running = unique.filter(\.isRunning)
        let history = unique.filter { !$0.isRunning }.prefix(max(0, recentHistoryLimit))
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
            .prefix(Self.recentFileLimit)
        let selectedPaths = Set(selectedFiles.map { "\(provider.rawValue)|\($0.url.path)" })
        return await withTaskGroup(of: (Int, AgentSession?).self) { group in
            for (index, file) in selectedFiles.enumerated() {
                group.addTask {
                    (index, await self.cachedSession(provider: provider, file: file, index: index, context: context, adapter: adapter))
                }
            }
            var parsed: [(Int, AgentSession)] = []
            for await (index, session) in group {
                if let session { parsed.append((index, session)) }
            }
            let prefix = "\(provider.rawValue)|"
            sessionCache = sessionCache.filter { key, _ in
                !key.hasPrefix(prefix) || selectedPaths.contains(key)
            }
            return parsed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func cachedSession(
        provider: AIProvider,
        file: (url: URL, modifiedAt: Date),
        index: Int,
        context: ProviderSessionContext,
        adapter: any ProviderSessionAdapter
    ) -> AgentSession? {
        let key = "\(provider.rawValue)|\(file.url.path)"
        let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let cached = sessionCache[key], cached.modifiedAt == file.modifiedAt, cached.fileSize == size {
            return cached.session
        }

        let session: AgentSession?
        if provider == .gemini {
            guard size <= 16 * 1024 * 1024, let data = try? Data(contentsOf: file.url) else {
                sessionCache[key] = CachedSession(modifiedAt: file.modifiedAt, fileSize: size, session: nil)
                return nil
            }
            session = GeminiSessionAdapter.parse(data, source: file.url)
        } else {
            session = adapter.session(
                from: ProviderSessionFile(url: file.url, modifiedAt: file.modifiedAt, index: index),
                context: context
            )
        }
        sessionCache[key] = CachedSession(modifiedAt: file.modifiedAt, fileSize: size, session: session)
        return session
    }

    private func recentSessionFiles(for provider: AIProvider, now: Date) -> [(url: URL, modifiedAt: Date)] {
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86_400)
        var files: [(url: URL, modifiedAt: Date)] = []
        let roots = authorizedRoots[provider] ?? provider.sessionRoots.map { home.appendingPathComponent($0, isDirectory: true) }
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var visitedEntries = 0
            for case let file as URL in enumerator {
                if Task.isCancelled { return files }
                visitedEntries += 1
                if visitedEntries > Self.directoryEntryLimit { break }
                guard file.pathExtension == "jsonl" || (provider == .gemini && file.pathExtension == "json") else { continue }
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      let modified = values?.contentModificationDate,
                      modified >= sevenDaysAgo else { continue }
                files.append((file, modified))
                if files.count > Self.recentFileLimit {
                    files.sort { $0.modifiedAt > $1.modifiedAt }
                    files.removeSubrange(Self.recentFileLimit...)
                }
            }
        }
        return files
    }

    private func hasSessionRoot(for provider: AIProvider) -> Bool {
        let roots = authorizedRoots[provider] ?? provider.sessionRoots.map { home.appendingPathComponent($0, isDirectory: true) }
        return roots.contains { root in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    static func deduplicatedSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        SessionPresentation.relevant(sessions, limit: sessions.count)
    }
}

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
    @Published private(set) var sessionStatuses: [String: String] = [:]
    private var monitoringEnabled = false
    private var resumeAuthorized: Set<AIProvider> = []
    private var runningSessionID: String?
    private let defaults: UserDefaults
    private var attempted: Set<String>
    private var process: Process?
    private let executableOverride: URL?

    init(defaults: UserDefaults = .standard, executableURL: URL? = nil) {
        executableOverride = executableURL
        self.defaults = defaults
        attempted = Set(defaults.stringArray(forKey: "autoResume.attempted.v1") ?? [])
    }

    /// The soonest recorded window that has not reset yet, if any.
    static func pendingWindow(for session: AgentSession, now: Date = .now) -> RecordedQuotaWindow? {
        session.recordedQuotaWindows
            .filter { ($0.resetsAt ?? .distantPast) > now }
            .min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }

    /// Whether MOMO can actually resume this session without the person.
    /// Only recorded Codex CLI rollouts have a supported unattended path.
    static func supportsUnattendedResume(_ session: AgentSession) -> Bool {
        session.provider == .codex && session.recordedSource == "cli"
    }

    func state(for session: AgentSession, now: Date = .now) -> String {
        if runningSessionID == session.id { return "Continuing now" }
        if let state = sessionStatuses[session.id] { return state }
        guard monitoringEnabled else { return "Off" }
        guard resumeAuthorized.contains(session.provider) else { return "Authorize to continue" }

        let remaining = Self.pendingWindow(for: session, now: now)?.remainingLabel(now: now)

        guard Self.supportsUnattendedResume(session) else {
            // No supported unattended path. Say exactly when the window opens
            // and that the person finishes it, rather than implying automation.
            if let remaining { return "Manual · resets in \(remaining)" }
            let reason = session.provider == .codex
                ? "desktop control not connected"
                : "\(session.provider.name) control not connected"
            return "Manual · \(reason)"
        }
        guard executable != nil else { return "Codex CLI unavailable" }
        if let remaining { return "Resumes in \(remaining)" }
        return "Watching for a recorded usage-limit stop"
    }

    func update(snapshots: [ProviderSnapshot], enabled: Bool, authorized: Set<AIProvider>, now: Date = .now) {
        monitoringEnabled = enabled
        resumeAuthorized = authorized
        if process == nil { sessionStatuses = [:] }
        let ids = Set(snapshots.flatMap(\.sessions).map(\.id))
        sessionStatuses = sessionStatuses.filter { ids.contains($0.key) }
        if !enabled { sessionStatuses = Dictionary(uniqueKeysWithValues: ids.map { ($0, "Off") }) }
        else { sessionStatuses = sessionStatuses.filter { $0.value != "Off" } }
        guard enabled else { status = "Off · no new automatic continuations"; return }
        guard authorized.contains(.codex) else { status = "Waiting for Codex local-provider authorization"; return }
        guard process == nil else { return }
        guard let executable = executable else { status = "Codex CLI is not installed at a supported location"; return }
        status = "Watching for recorded Codex CLI usage stops"
        for session in snapshots.filter({ $0.provider == .codex }).flatMap(\.sessions) {
            guard let source = session.sourceURL,
                  let data = boundedRead(source), let candidate = CodexResumeCandidate.parse(data) else { continue }
            if attempted.contains(candidate.key) {
                sessionStatuses[session.id] = "Attempted this reset · no duplicate retry"
                continue
            }
            guard now >= candidate.resetAt.addingTimeInterval(5) else {
                status = "Waiting for reset: \(candidate.resetAt.formatted(date: .omitted, time: .shortened))"
                sessionStatuses[session.id] = status
                continue
            }
            // Re-read immediately before dispatch. A new user turn, manual stop,
            // or any other rollout change cancels this stale candidate.
            guard let fresh = boundedRead(source), CodexResumeCandidate.parse(fresh) == candidate else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                status = "Cannot resume: the recorded project folder is unavailable"; sessionStatuses[session.id] = status; continue
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
                    self?.sessionStatuses[session.id] = succeeded ? "Continuation finished" : "Attempt failed · no duplicate retry"
                    self?.runningSessionID = nil
                    self?.process = nil
                }
            }
            process = child
            runningSessionID = session.id
            do { try child.run(); status = "Automatically continuing a Codex CLI chat"; sessionStatuses[session.id] = "Continuing now" }
            catch { process = nil; runningSessionID = nil; status = "Could not start Codex; no repeated retry"; sessionStatuses[session.id] = status }
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


private struct CodexNameCache {
    private struct Signature: Equatable {
        let modifiedAt: Date?
        let size: Int?
    }

    private var signatures: [String: Signature] = [:]
    private var resolvedIDs = Set<String>()
    private var values: [String: String] = [:]

    mutating func names(for ids: Set<String>, home: URL, fileManager: FileManager) -> [String: String] {
        let metadataURLs = CodexChatNames.metadataURLs(home: home)
        let current = Dictionary(uniqueKeysWithValues: metadataURLs.map { url in
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return (url.path, Signature(
                modifiedAt: attributes?[.modificationDate] as? Date,
                size: attributes?[.size] as? Int
            ))
        })
        if current != signatures {
            signatures = current
            resolvedIDs.removeAll()
            values.removeAll()
        }

        let missing = ids.subtracting(resolvedIDs)
        if !missing.isEmpty {
            values.merge(CodexChatNames.read(home: home, sessionIDs: missing)) { _, latest in latest }
            resolvedIDs.formUnion(missing)
        }

        // The scanner presents at most recentFileLimit Codex chats. Retain only
        // those identities so names from old scans cannot grow without bound.
        resolvedIDs.formIntersection(ids)
        values = values.filter { ids.contains($0.key) }
        return values
    }
}


/// Reads Codex task names from its bounded rename index and current task metadata.
enum CodexChatNames {
    static func metadataURLs(home: URL) -> [URL] {
        let root = home.appendingPathComponent(".codex", isDirectory: true)
        return [
            root.appendingPathComponent("session_index.jsonl"),
            root.appendingPathComponent("state_5.sqlite"),
            root.appendingPathComponent("state_5.sqlite-wal")
        ]
    }

    static func read(home: URL) -> [String: String] {
        read(home: home, sessionIDs: nil)
    }

    static func read(home: URL, sessionIDs: Set<String>?) -> [String: String] {
        let requested = sessionIDs
        let url = home.appendingPathComponent(".codex/session_index.jsonl")
        var names: [String: String] = [:]
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 2_000_000 ? size - 2_000_000 : 0)
            names = parse((try? handle.read(upToCount: 2_000_000)) ?? Data())
            if let requested { names = names.filter { requested.contains($0.key) } }
        }

        // state_5.sqlite is the Codex app's current task metadata. Query only
        // already-selected local session IDs; never sweep every task or preview.
        let database = home.appendingPathComponent(".codex/state_5.sqlite")
        names.merge(readDatabase(database, sessionIDs: requested ?? Set(names.keys))) { _, databaseTitle in
            databaseTitle
        }
        return names
    }
    static func parse(_ data: Data) -> [String: String] {
        var names: [String: String] = [:]
        for line in data.split(separator: 10) {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = record["id"] as? String, UUID(uuidString: id) != nil,
                  let name = record["thread_name"] as? String else { continue }
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Reject prompt blobs rather than disguising them as chat names.
            names[id] = !title.isEmpty && title.count <= 200 && !title.hasPrefix("<") && !title.hasPrefix("#") ? title : nil
        }
        return names
    }

    private static func readDatabase(_ url: URL, sessionIDs: Set<String>) -> [String: String] {
        guard !sessionIDs.isEmpty, FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else { return [:] }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "SELECT name, title FROM threads WHERE id = ?1 LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [:] }
        defer { sqlite3_finalize(statement) }

        var result: [String: String] = [:]
        for id in sessionIDs.prefix(LocalActivityScanner.recentFileLimit) {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            id.withCString { pointer in
                guard sqlite3_bind_text(statement, 1, pointer, -1, nil) == SQLITE_OK,
                      sqlite3_step(statement) == SQLITE_ROW else { return }
                let custom = sqliteString(statement, column: 0)
                let generated = sqliteString(statement, column: 1)
                if let title = validated(custom) ?? validated(generated) {
                    result[id] = title
                }
            }
        }
        return result
    }

    private static func sqliteString(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func validated(_ value: String?) -> String? {
        guard let value else { return nil }
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200, !title.hasPrefix("<"), !title.hasPrefix("#") else { return nil }
        return title
    }
}
