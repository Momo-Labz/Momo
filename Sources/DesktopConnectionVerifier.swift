import AppKit
import Foundation

/// Live connect/verification progress for onboarding — never leave a blank static panel.
enum DesktopConnectProgress: Equatable {
    case openingApp
    case waitingForSignIn
    case readingLocalUsage
    case connected(ConnectUsageHonesty)
    case needsPermission
    case failed(String)
    case timedOut

    var title: String {
        switch self {
        case .openingApp: return "Opening app…"
        case .waitingForSignIn: return "Waiting for sign-in…"
        case .readingLocalUsage: return "Reading local usage…"
        case .connected: return "Connected"
        case .needsPermission: return "Needs permission"
        case .failed: return "Failed"
        case .timedOut: return "Timed out"
        }
    }

    var showsSpinner: Bool {
        switch self {
        case .openingApp, .waitingForSignIn, .readingLocalUsage: return true
        case .connected, .needsPermission, .failed, .timedOut: return false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .connected, .needsPermission, .failed, .timedOut: return true
        case .openingApp, .waitingForSignIn, .readingLocalUsage: return false
        }
    }

    var isVerified: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Honest local-usage outcome after a successful desktop connect check.
struct ConnectUsageHonesty: Equatable {
    enum Outcome: Equatable {
        /// Parsed session/week % from a real local cache — values are optional when only one window exists.
        case usageFound(sessionPercent: Int?, weekPercent: Int?)
        /// App/session readable but no usage-cache / statusline artifact yet.
        case noReadableCache
        /// Session root exists but listing/reading is blocked (FDA / App Management).
        case privacyBlocked
    }

    let outcome: Outcome
    /// Absolute path of the cache file when usage was found.
    let sourcePath: String?

    var summary: String {
        switch outcome {
        case .usageFound(let session, let week):
            var parts: [String] = ["Connected — local usage found."]
            if let session { parts.append("Session \(session)%.") }
            if let week { parts.append("Week \(week)%.") }
            if session == nil, week == nil {
                parts.append("Usage meters recorded without percent fields.")
            }
            return parts.joined(separator: " ")
        case .noReadableCache:
            return "Connected — no readable usage % yet. Claude/Codex need a local CLI cache or session rate_limits file; see the Usage tab for the exact next step."
        case .privacyBlocked:
            return "macOS blocked reading local provider files. Open System Settings → Privacy & Security → Full Disk Access, allow MOMO, then Retry."
        }
    }
}

/// Honest desktop-app connection check — never treats “process running” alone as verified.
enum DesktopConnectionVerifier {
    /// Overall wall-clock budget for one connect attempt (open + scan).
    static let connectTimeout: Duration = .seconds(20)
    /// Soft pause after requesting app open so Launch Services can activate.
    static let postOpenSettle: Duration = .milliseconds(600)

    enum Status: Equatable {
        case notInstalled
        case notRunning
        /// App is open but MOMO cannot yet read local session/usage data (often mid sign-in).
        case awaitingSignIn
        /// Session root exists but listing/reading is blocked by macOS TCC / Full Disk Access.
        case privacyBlocked
        case verified
        case failed(String)

        var isVerified: Bool {
            if case .verified = self { return true }
            return false
        }

        var guidance: String {
            switch self {
            case .notInstalled:
                return "Install this app in Applications, then Retry."
            case .notRunning:
                return "Open the app, finish any login prompts, then Retry."
            case .awaitingSignIn:
                return "Finish signing in in the app, then Retry. MOMO only marks connected when local session or usage data is readable."
            case .privacyBlocked:
                return "macOS blocked reading this app’s local files. Open System Settings → Privacy & Security → Full Disk Access, allow MOMO, then Retry. MOMO never writes into other apps."
            case .verified:
                return "Connected — local session or usage data is readable."
            case .failed(let reason):
                return reason
            }
        }
    }

    struct ConnectResult: Equatable {
        let status: Status
        let honesty: ConnectUsageHonesty?
        let progress: DesktopConnectProgress

        var isVerified: Bool { status.isVerified }
    }

    /// Session file suffixes adapters already parse.
    static let sessionSuffixes = ["jsonl", "json"]

    /// Pure check for tests — inject filesystem / running state.
    static func evaluate(
        provider: AIProvider,
        isInstalled: Bool,
        isRunning: Bool,
        hasReadableSessionSource: Bool,
        privacyBlocked: Bool = false
    ) -> Status {
        guard isInstalled else { return .notInstalled }
        guard isRunning else { return .notRunning }
        if hasReadableSessionSource { return .verified }
        if privacyBlocked { return .privacyBlocked }
        return .awaitingSignIn
    }

    /// Synchronous verify — call only from a background queue / Task.detached, never MainActor.
    static func verify(_ provider: AIProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Status {
        let installed = DesktopAppCatalog.locate(provider) != nil
        let running = isApplicationRunning(provider)
        let readable = hasReadableLocalData(provider, home: home)
        let blocked = LocalUsageArtifactReader.isSessionRootPrivacyBlocked(provider, home: home)
        return evaluate(
            provider: provider,
            isInstalled: installed,
            isRunning: running,
            hasReadableSessionSource: readable,
            privacyBlocked: blocked
        )
    }

    /// Background verify + honest usage report. Safe to await from MainActor UI.
    static func verifyOffMain(
        _ provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> ConnectResult {
        await Task.detached(priority: .userInitiated) {
            let status = verify(provider, home: home)
            let honesty = usageHonesty(for: provider, status: status, home: home)
            let progress = progress(from: status, honesty: honesty)
            return ConnectResult(status: status, honesty: honesty, progress: progress)
        }.value
    }

    /// Full connect attempt with live progress callbacks (MainActor) and a hard timeout.
    static func runConnectAttempt(
        for provider: AIProvider,
        openApp: Bool,
        onProgress: @MainActor @escaping (DesktopConnectProgress) -> Void
    ) async -> ConnectResult {
        await onProgress(.openingApp)
        if openApp {
            _ = await DesktopAppConnect.openDesktopAppAsync(for: provider)
        }
        await onProgress(.waitingForSignIn)
        try? await Task.sleep(for: postOpenSettle)
        guard !Task.isCancelled else {
            return ConnectResult(status: .failed("Cancelled"), honesty: nil, progress: .failed("Cancelled"))
        }
        await onProgress(.readingLocalUsage)

        let verifyTask = Task { await verifyOffMain(provider) }
        let result: ConnectResult = await withTaskGroup(of: ConnectResult.self) { group in
            group.addTask {
                await verifyTask.value
            }
            group.addTask {
                try? await Task.sleep(for: connectTimeout)
                return ConnectResult(
                    status: .failed("Timed out while checking local files."),
                    honesty: nil,
                    progress: .timedOut
                )
            }
            // First finished child wins; cancel the rest so a late verify cannot overwrite UI.
            let first = await group.next() ?? ConnectResult(
                status: .failed("Cancelled"),
                honesty: nil,
                progress: .failed("Cancelled")
            )
            group.cancelAll()
            verifyTask.cancel()
            return first
        }
        await onProgress(result.progress)
        return result
    }

    static func usageHonesty(
        for provider: AIProvider,
        status: Status,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now,
        fileManager: FileManager = .default
    ) -> ConnectUsageHonesty? {
        switch status {
        case .privacyBlocked:
            return ConnectUsageHonesty(outcome: .privacyBlocked, sourcePath: nil)
        case .verified:
            let probed = LocalUsageArtifactReader.probeDetail(
                for: provider,
                home: home,
                now: now,
                fileManager: fileManager,
                timeout: 5
            )
            let detail = probed.detail
            if detail.hasQuotaMeters {
                let session = detail.fiveHour.map { Int($0.percent.rounded()) }
                let week = detail.weekly.map { Int($0.percent.rounded()) }
                return ConnectUsageHonesty(
                    outcome: .usageFound(sessionPercent: session, weekPercent: week),
                    sourcePath: detail.sourceDescription
                )
            }
            // Verified via sessions (or non-% artifacts) but no quota meters.
            return ConnectUsageHonesty(outcome: .noReadableCache, sourcePath: nil)
        case .notInstalled, .notRunning, .awaitingSignIn, .failed:
            return nil
        }
    }

    static func progress(from status: Status, honesty: ConnectUsageHonesty?) -> DesktopConnectProgress {
        switch status {
        case .verified:
            return .connected(honesty ?? ConnectUsageHonesty(outcome: .noReadableCache, sourcePath: nil))
        case .privacyBlocked:
            return .needsPermission
        case .notInstalled:
            return .failed(Status.notInstalled.guidance)
        case .notRunning:
            return .failed(Status.notRunning.guidance)
        case .awaitingSignIn:
            return .failed(Status.awaitingSignIn.guidance)
        case .failed(let reason):
            return .failed(reason)
        }
    }

    static func isApplicationRunning(_ provider: AIProvider) -> Bool {
        let ids = Set(provider.applicationBundleIdentifiers)
        if !ids.isEmpty {
            let runningIDs = Set(
                NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            )
            if !ids.isDisjoint(with: runningIDs) { return true }
        }
        return isProcessRunning(provider)
    }

    static func isProcessRunning(_ provider: AIProvider) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.split(whereSeparator: \.isNewline).contains { line in
            let command = line.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { return false }
            let parts = command.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { return false }
            return provider.matchesProcessCommand(String(parts[1]))
        }
    }

    /// Readable session file **or** honest local usage artifact (Claude statusline cache, etc.).
    static func hasReadableLocalData(
        _ provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: Date = .now
    ) -> Bool {
        if hasReadableSessionSource(provider, home: home, fileManager: fileManager) {
            return true
        }
        return !LocalUsageArtifactReader.quotaWindows(
            for: provider,
            home: home,
            now: now,
            fileManager: fileManager
        ).isEmpty
    }

    /// True when a default session root exists and at least one session file can be opened for reading.
    static func hasReadableSessionSource(
        _ provider: AIProvider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        let roots = provider.sessionRoots.map { home.appendingPathComponent($0, isDirectory: true) }
        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if firstReadableSessionFile(under: root, fileManager: fileManager) != nil {
                return true
            }
        }
        return false
    }

    static func firstReadableSessionFile(
        under root: URL,
        fileManager: FileManager = .default,
        maxDepth: Int = 4
    ) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var checked = 0
        while let item = enumerator.nextObject() as? URL {
            checked += 1
            if checked > 2_000 { break }
            let depth = item.pathComponents.count - root.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let ext = item.pathExtension.lowercased()
            guard sessionSuffixes.contains(ext) else { continue }
            guard fileManager.isReadableFile(atPath: item.path) else { continue }
            guard let handle = try? FileHandle(forReadingFrom: item) else { continue }
            defer { try? handle.close() }
            let preview = (try? handle.read(upToCount: 64)) ?? Data()
            if !preview.isEmpty { return item }
        }
        return nil
    }
}
