import AppKit
import Foundation

/// Honest desktop-app connection check — never treats “process running” alone as verified.
enum DesktopConnectionVerifier {
    enum Status: Equatable {
        case notInstalled
        case notRunning
        /// App is open but MOMO cannot yet read local session/usage data (often mid sign-in).
        case awaitingSignIn
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
                return "Finish signing in in the app, then Retry. MOMO only marks connected when local session data is readable."
            case .verified:
                return "Connected — local session data is readable."
            case .failed(let reason):
                return reason
            }
        }
    }

    /// Session file suffixes adapters already parse.
    static let sessionSuffixes = ["jsonl", "json"]

    /// Pure check for tests — inject filesystem / running state.
    static func evaluate(
        provider: AIProvider,
        isInstalled: Bool,
        isRunning: Bool,
        hasReadableSessionSource: Bool
    ) -> Status {
        guard isInstalled else { return .notInstalled }
        guard isRunning else { return .notRunning }
        guard hasReadableSessionSource else { return .awaitingSignIn }
        return .verified
    }

    static func verify(_ provider: AIProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Status {
        let installed = DesktopAppCatalog.locate(provider) != nil
        let running = isApplicationRunning(provider)
        let readable = hasReadableSessionSource(provider, home: home)
        return evaluate(
            provider: provider,
            isInstalled: installed,
            isRunning: running,
            hasReadableSessionSource: readable
        )
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
