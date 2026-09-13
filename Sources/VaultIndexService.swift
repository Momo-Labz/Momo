import Combine
import Foundation

struct VaultNote: Identifiable, Sendable, Equatable {
    /// Stable path relative to the selected vault, including the `.md` extension.
    let id: String
    let title: String
    /// Explicit Markdown or wiki links resolved to other note IDs.
    let links: [String]
    /// Link text that could not be resolved unambiguously inside the vault.
    let unresolvedLinks: [String]
    let tags: [String]
}

struct VaultGraphSnapshot: Sendable, Equatable {
    let notes: [VaultNote]
    let revision: String

    static let empty = VaultGraphSnapshot(notes: [], revision: "")
}

struct VaultIndexMetrics: Sendable, Equatable {
    let indexedNoteCount: Int
    let reparsedNoteCount: Int
    let duration: TimeInterval
}

enum VaultIndexError: LocalizedError, Equatable {
    case noVault
    case invalidVault
    case noteNotFound
    case pathEscapesVault
    case unreadableNote
    case invalidTitle

    var errorDescription: String? {
        switch self {
        case .noVault: return "Connect an Obsidian vault first."
        case .invalidVault: return "The selected folder is not available."
        case .noteNotFound: return "That note is no longer in the connected vault."
        case .pathEscapesVault: return "MOMO blocked a path outside the connected vault."
        case .unreadableNote: return "MOMO could not read this note."
        case .invalidTitle: return "Enter a note title."
        }
    }
}

/// Incrementally builds immutable note snapshots without retaining note bodies.
actor VaultIndexService {
    private struct Signature: Equatable {
        let modified: TimeInterval
        let size: Int
    }

    private struct CachedMetadata {
        let signature: Signature
        let title: String
        let rawLinks: [String]
        let tags: [String]
    }

    private let fileManager: FileManager
    private let metadataReadLimit = 256 * 1_024
    private let noteReadLimit = 1_024 * 1_024
    private let maximumIndexedNotes = 20_000
    private var rootURL: URL?
    private var accessURL: URL?
    private var cache: [String: CachedMetadata] = [:]
    private var lastMetrics = VaultIndexMetrics(indexedNoteCount: 0, reparsedNoteCount: 0, duration: 0)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func connect(_ url: URL) throws -> VaultGraphSnapshot {
        let scopedURL = url.standardizedFileURL
        let standardized = scopedURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VaultIndexError.invalidVault
        }
        if rootURL != standardized {
            cache.removeAll(keepingCapacity: false)
        }
        rootURL = standardized
        accessURL = scopedURL
        return try withVaultAccess(scopedURL) { try buildSnapshot(in: standardized) }
    }

    func refresh() throws -> VaultGraphSnapshot {
        guard let rootURL else { throw VaultIndexError.noVault }
        return try withVaultAccess(accessURL ?? rootURL) { try buildSnapshot(in: rootURL) }
    }

    func readNote(id: String) throws -> String {
        guard let rootURL else { throw VaultIndexError.noVault }
        return try withVaultAccess(accessURL ?? rootURL) {
            let noteURL = try safeURL(for: id, root: rootURL)
            guard cache[id] != nil else { throw VaultIndexError.noteNotFound }
            guard noteURL.pathExtension.lowercased() == "md" else { throw VaultIndexError.noteNotFound }
            return try boundedText(at: noteURL, limit: noteReadLimit, appendTruncationNotice: true)
        }
    }

    func save(title: String, body: String) throws -> (URL, VaultGraphSnapshot) {
        guard let rootURL else { throw VaultIndexError.noVault }
        let cleanTitle = sanitizedTitle(title)
        guard !cleanTitle.isEmpty else { throw VaultIndexError.invalidTitle }

        return try withVaultAccess(accessURL ?? rootURL) {
            let folder = rootURL.appendingPathComponent("MOMO", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            var suffix = 1
            var destination = folder.appendingPathComponent("\(cleanTitle).md")
            while fileManager.fileExists(atPath: destination.path) {
                suffix += 1
                destination = folder.appendingPathComponent("\(cleanTitle) \(suffix).md")
            }
            guard isInsideVault(destination, root: rootURL) else { throw VaultIndexError.pathEscapesVault }

            let text = "# \(title.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(body)\n"
            try Data(text.utf8).write(to: destination, options: .withoutOverwriting)
            return (destination, try buildSnapshot(in: rootURL))
        }
    }

    func metrics() -> VaultIndexMetrics {
        lastMetrics
    }

    private func buildSnapshot(in root: URL) throws -> VaultGraphSnapshot {
        let startedAt = Date()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { throw VaultIndexError.invalidVault }

        var discovered: [String: Signature] = [:]
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isHidden == true || url.lastPathComponent.hasPrefix(".") {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            guard isInsideVault(url, root: root), let id = relativePath(of: url, root: root) else { continue }
            guard discovered.count < maximumIndexedNotes else { break }
            discovered[id] = Signature(
                modified: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: values?.fileSize ?? 0
            )
        }

        cache = cache.filter { discovered[$0.key] != nil }
        var reparsedNoteCount = 0
        for (id, signature) in discovered where cache[id]?.signature != signature {
            let url = try safeURL(for: id, root: root)
            let text = try boundedText(at: url, limit: metadataReadLimit, appendTruncationNotice: false)
            cache[id] = CachedMetadata(
                signature: signature,
                title: Self.extractTitle(from: text, fallback: url.deletingPathExtension().lastPathComponent),
                rawLinks: Array(Self.extractLinks(from: text).prefix(256)),
                tags: Array(Self.extractTags(from: text).prefix(128))
            )
            reparsedNoteCount += 1
        }

        let notes = cache.keys.sorted().map { id -> VaultNote in
            let metadata = cache[id]!
            var resolved = Set<String>()
            var unresolved = Set<String>()
            for rawLink in metadata.rawLinks {
                if let target = resolve(rawLink, from: id) {
                    resolved.insert(target)
                } else {
                    unresolved.insert(rawLink)
                }
            }
            return VaultNote(
                id: id,
                title: metadata.title,
                links: resolved.sorted(),
                unresolvedLinks: unresolved.sorted(),
                tags: metadata.tags
            )
        }
        lastMetrics = VaultIndexMetrics(
            indexedNoteCount: notes.count,
            reparsedNoteCount: reparsedNoteCount,
            duration: Date().timeIntervalSince(startedAt)
        )
        return VaultGraphSnapshot(notes: notes, revision: revision(for: notes, signatures: discovered))
    }

    private func resolve(_ rawTarget: String, from sourceID: String) -> String? {
        var target = rawTarget.removingPercentEncoding ?? rawTarget
        target = target.components(separatedBy: "#").first ?? target
        target = target.components(separatedBy: "?").first ?? target
        target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !target.hasPrefix("/"), URL(string: target)?.scheme == nil else { return nil }

        let sourceDirectory = (sourceID as NSString).deletingLastPathComponent
        var candidates: [String] = []
        let targets = target.lowercased().hasSuffix(".md") ? [target] : [target, "\(target).md"]
        for value in targets {
            let relative = sourceDirectory.isEmpty ? value : (sourceDirectory as NSString).appendingPathComponent(value)
            candidates.append((relative as NSString).standardizingPath)
            candidates.append((value as NSString).standardizingPath)
        }
        let exact = candidates.first { !$0.hasPrefix("../") && cache[$0] != nil }
        if let exact { return exact }

        let loweredCandidates = Set(candidates.map { $0.lowercased() })
        let caseInsensitive = cache.keys.filter { loweredCandidates.contains($0.lowercased()) }
        if caseInsensitive.count == 1 { return caseInsensitive[0] }

        let stem = ((target as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        let byName = cache.filter {
            (($0.key as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased() == stem ||
                $0.value.title.lowercased() == stem
        }.map(\.key)
        return byName.count == 1 ? byName[0] : nil
    }

    private func boundedText(at url: URL, limit: Int, appendTruncationNotice: Bool) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw VaultIndexError.unreadableNote }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1) else { throw VaultIndexError.unreadableNote }
        let truncated = data.count > limit
        var text = String(decoding: data.prefix(limit), as: UTF8.self)
        if truncated, appendTruncationNotice {
            text += "\n\n[Content truncated by MOMO]"
        }
        return text
    }

    private func safeURL(for id: String, root: URL) throws -> URL {
        guard !id.hasPrefix("/"), !id.split(separator: "/").contains("..") else {
            throw VaultIndexError.pathEscapesVault
        }
        let url = root.appendingPathComponent(id).standardizedFileURL.resolvingSymlinksInPath()
        guard isInsideVault(url, root: root) else { throw VaultIndexError.pathEscapesVault }
        return url
    }

    private func isInsideVault(_ url: URL, root: URL) -> Bool {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
        return resolved == resolvedRoot || resolved.hasPrefix(resolvedRoot + "/")
    }

    private func relativePath(of url: URL, root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func sanitizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\")
        let pieces = trimmed.components(separatedBy: invalid).filter { !$0.isEmpty }
        return pieces.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func withVaultAccess<T>(_ root: URL, operation: () throws -> T) rethrows -> T {
        let granted = root.startAccessingSecurityScopedResource()
        defer { if granted { root.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    private func revision(for notes: [VaultNote], signatures: [String: Signature]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        for note in notes {
            let signature = signatures[note.id]
            let value = "\(note.id)|\(signature?.modified ?? 0)|\(signature?.size ?? 0)|\(note.links.joined(separator: ","))|\(note.tags.joined(separator: ","))"
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }
        return String(hash, radix: 16)
    }

    private static func extractTitle(from text: String, fallback: String) -> String {
        if text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: min(3, text.count))..<text.endIndex) {
            let frontmatter = String(text[..<end.lowerBound])
            if let titleLine = frontmatter.split(separator: "\n").first(where: { $0.lowercased().hasPrefix("title:") }) {
                let title = titleLine.dropFirst(titleLine.firstIndex(of: ":")!.utf16Offset(in: titleLine) + 1)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
                if !title.isEmpty { return title }
            }
        }
        if let match = firstCapture(pattern: "(?m)^#\\s+(.+?)\\s*$", in: text) {
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallback
    }

    private static func extractLinks(from text: String) -> [String] {
        var links: [String] = []
        links += captures(pattern: "\\[\\[([^\\]|]+)(?:\\|[^\\]]+)?\\]\\]", in: text)
        links += captures(pattern: "(?<!!)\\[[^\\]]+\\]\\(([^)]+\\.md(?:#[^)]+)?)\\)", in: text)
        return Array(Set(links.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).sorted()
    }

    private static func extractTags(from text: String) -> [String] {
        var tags = Set(captures(pattern: "(?<![A-Za-z0-9_])#([A-Za-z0-9_/-]+)", in: text))
        if text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: min(3, text.count))..<text.endIndex) {
            let frontmatter = String(text[..<end.lowerBound])
            for line in frontmatter.split(separator: "\n") where line.lowercased().hasPrefix("tags:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'#")) }
                    .filter { !$0.isEmpty }
                    .forEach { tags.insert($0) }
            }
        }
        return tags.sorted()
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        captures(pattern: pattern, in: text).first
    }

    private static func captures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

@MainActor
final class VaultStore: ObservableObject {
    static let shared = VaultStore()

    @Published private(set) var notes: [VaultNote] = []
    @Published private(set) var revision = ""
    @Published private(set) var status = "NO VAULT CONNECTED"
    @Published private(set) var vaultURL: URL?

    private let index: VaultIndexService
    private let defaults: UserDefaults
    private let persistBookmarks: Bool
    private let bookmarkKey = "momo.obsidian.vaultBookmark"
    private var operationID = UUID()

    init(
        index: VaultIndexService = VaultIndexService(),
        defaults: UserDefaults = .standard,
        autoRestore: Bool = true,
        persistBookmarks: Bool = true
    ) {
        self.index = index
        self.defaults = defaults
        self.persistBookmarks = persistBookmarks

        if autoRestore, let data = defaults.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                vaultURL = url
                status = "RESTORING VAULT"
                let requestID = operationID
                Task { [weak self] in await self?.restore(url, replaceBookmark: stale, requestID: requestID) }
            }
        }
    }

    func connect(_ url: URL) async throws {
        let requestID = UUID()
        operationID = requestID
        status = "INDEXING VAULT"
        do {
            let snapshot = try await index.connect(url)
            guard operationID == requestID else { return }
            if persistBookmarks {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(bookmark, forKey: bookmarkKey)
            }
            vaultURL = url
            publish(snapshot)
        } catch {
            status = error.localizedDescription.uppercased()
            throw error
        }
    }

    func refresh() async {
        guard vaultURL != nil else {
            status = "NO VAULT CONNECTED"
            return
        }
        let requestID = UUID()
        operationID = requestID
        status = "REFRESHING VAULT"
        do {
            let snapshot = try await index.refresh()
            guard operationID == requestID else { return }
            publish(snapshot)
        } catch {
            status = error.localizedDescription.uppercased()
        }
    }

    func readNote(id: String) async throws -> String {
        try await index.readNote(id: id)
    }

    func save(title: String, body: String) async throws -> URL {
        let requestID = UUID()
        operationID = requestID
        status = "SAVING NOTE"
        do {
            let (url, snapshot) = try await index.save(title: title, body: body)
            guard operationID == requestID else { return url }
            publish(snapshot)
            return url
        } catch {
            status = error.localizedDescription.uppercased()
            throw error
        }
    }

    private func restore(_ url: URL, replaceBookmark: Bool, requestID: UUID) async {
        do {
            let snapshot = try await index.connect(url)
            guard operationID == requestID else { return }
            vaultURL = url
            publish(snapshot)
            if replaceBookmark, persistBookmarks {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(bookmark, forKey: bookmarkKey)
            }
        } catch {
            vaultURL = nil
            notes = []
            revision = ""
            status = "VAULT ACCESS NEEDED"
        }
    }

    private func publish(_ snapshot: VaultGraphSnapshot) {
        if revision != snapshot.revision {
            notes = snapshot.notes
            revision = snapshot.revision
        }
        status = "\(snapshot.notes.count) NOTE\(snapshot.notes.count == 1 ? "" : "S") · READY"
    }
}
