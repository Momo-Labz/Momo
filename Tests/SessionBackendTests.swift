import Foundation
import SQLite3
import XCTest
@testable import BAR_BOY

final class SessionBackendTests: XCTestCase {
    private final class CountingAdapter: ProviderSessionAdapter, @unchecked Sendable {
        let provider: AIProvider = .codex
        private let lock = NSLock()
        private var storedCount = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedCount
        }

        func session(from file: ProviderSessionFile, context: ProviderSessionContext) -> AgentSession? {
            lock.lock()
            storedCount += 1
            lock.unlock()
            return AgentSession(
                id: file.url.lastPathComponent, provider: .codex, role: .main,
                title: "Fixture", detail: "", project: "Demo", updatedAt: file.modifiedAt,
                isRunning: false, processID: nil, tokens: nil, attention: .unknown
            )
        }
    }

    func testRelevantSessionsDeduplicateProviderAndFullConversationIdentity() {
        let now = Date()
        let fullID = String(repeating: "session-component-", count: 12)
        let older = session(
            id: "path-a", provider: .claude, title: "Older",
            updatedAt: now.addingTimeInterval(-60), attention: .completed,
            conversationID: fullID
        )
        let newer = session(
            id: "path-b", provider: .claude, title: "Newer",
            updatedAt: now, attention: .needsInput,
            conversationID: fullID
        )
        let otherProvider = session(
            id: "path-c", provider: .codex, title: "Codex",
            updatedAt: now.addingTimeInterval(-120), attention: .completed,
            conversationID: fullID
        )

        let result = SessionPresentation.relevant([older, otherProvider, newer], limit: 10)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.title, "Newer")
        XCTAssertEqual(SessionPresentation.fullIdentity(for: newer), fullID)
    }

    func testRelevantSessionsPrioritizeLiveThenUnresolvedThenRecent() {
        let now = Date()
        let recent = session(id: "recent", provider: .codex, title: "Recent", updatedAt: now, attention: .completed)
        let unresolved = session(id: "waiting", provider: .claude, title: "Waiting", updatedAt: now.addingTimeInterval(-60), attention: .needsInput)
        let live = AgentSession(
            id: "live", provider: .cursor, role: .main, title: "Live", detail: "",
            project: "Demo", updatedAt: now.addingTimeInterval(-120), isRunning: true,
            processID: nil, tokens: nil, attention: .working
        )

        XCTAssertEqual(
            SessionPresentation.relevant([recent, unresolved, live], limit: 3).map(\.id),
            ["live", "waiting", "recent"]
        )
    }

    func testPresentationNeverUsesAnIdentifierAsTheTitle() {
        let id = "12345678-1234-1234-1234-123456789abc"
        let excerpt = session(id: id, provider: .codex, title: "Codex task · 12345678", detail: "Review the cache behavior", updatedAt: .now, attention: .unknown)
        XCTAssertEqual(SessionPresentation.title(for: excerpt), "Review the cache behavior")

        let untitled = session(id: id, provider: .codex, title: id, detail: "Recent local Codex session", updatedAt: .now, attention: .unknown)
        XCTAssertEqual(SessionPresentation.title(for: untitled), "Untitled chat")
    }

    func testUsageAvailabilityDoesNotTurnMissingClaudeOrCursorQuotaIntoZero() {
        XCTAssertEqual(ProviderUsageAvailability.current(for: .claude).sessionTokens, .recordedSessionEvents)
        guard case .unavailable = ProviderUsageAvailability.current(for: .claude).accountQuota else {
            return XCTFail("Claude consumer quota should be unavailable")
        }
        guard case .unavailable = ProviderUsageAvailability.current(for: .cursor).sessionTokens,
              case .unavailable = ProviderUsageAvailability.current(for: .cursor).accountQuota else {
            return XCTFail("Cursor transcript usage and quota should be unavailable")
        }
    }

    func testCodexNamesPreferCurrentAppMetadataForOnlyRequestedChats() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("momo-codex-names-\(UUID().uuidString)")
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let requested = "12345678-1234-1234-1234-123456789abc"
        let unrelated = "87654321-4321-4321-4321-cba987654321"
        try Data("{\"id\":\"\(requested)\",\"thread_name\":\"Index title\"}\n".utf8)
            .write(to: codex.appendingPathComponent("session_index.jsonl"))

        var database: OpaquePointer?
        let databaseURL = codex.appendingPathComponent("state_5.sqlite")
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { if let database { sqlite3_close(database) } }
        let schema = "CREATE TABLE threads (id TEXT PRIMARY KEY, name TEXT, title TEXT);"
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)
        let insert = "INSERT INTO threads VALUES ('\(requested)', 'App rename', 'Generated title'), ('\(unrelated)', 'Private unrelated', 'Other');"
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)

        XCTAssertEqual(CodexChatNames.read(home: home, sessionIDs: [requested]), [requested: "App rename"])
    }

    func testScannerReparsesOnlyTheChangedFile() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("momo-session-cache-\(UUID().uuidString)")
        let root = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let first = root.appendingPathComponent("first.jsonl")
        let second = root.appendingPathComponent("second.jsonl")
        try Data("{\"value\":1}".utf8).write(to: first)
        try Data("{\"value\":2}".utf8).write(to: second)

        let adapter = CountingAdapter()
        let scanner = LocalActivityScanner(adapters: [adapter], home: home, detectProcesses: false)
        _ = await scanner.scan(providers: [.codex])
        XCTAssertEqual(adapter.count, 2)
        _ = await scanner.scan(providers: [.codex])
        XCTAssertEqual(adapter.count, 2)

        try Data("{\"value\":3,\"changed\":true}".utf8).write(to: first)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: first.path)
        _ = await scanner.scan(providers: [.codex])
        XCTAssertEqual(adapter.count, 3)
    }

    private func session(
        id: String,
        provider: AIProvider,
        title: String,
        detail: String = "",
        updatedAt: Date,
        attention: AgentAttention,
        conversationID: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: id, provider: provider, role: .main, title: title, detail: detail,
            project: "Demo", updatedAt: updatedAt, isRunning: false,
            processID: nil, tokens: nil, attention: attention,
            conversationID: conversationID
        )
    }
}
