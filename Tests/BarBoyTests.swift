import AppKit
import SwiftUI
import XCTest
@testable import BAR_BOY

@MainActor
final class BarBoyTests: XCTestCase {
    func testDesktopTaskLinksRequireRecordedIdentity() {
        let id = "12345678-1234-1234-1234-123456789abc"
        let valid = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"}}\n".utf8)
        XCTAssertEqual(CodexDesktopConnection.taskURL(metadata: valid)?.absoluteString, "codex://threads/\(id)")
        for text in ["{}", "{\"type\":\"user_message\",\"payload\":{\"id\":\"\(id)\"}}", "{\"type\":\"session_meta\",\"payload\":{\"id\":\"../../settings\"}}"] {
            XCTAssertNil(CodexDesktopConnection.taskURL(metadata: Data(text.utf8)))
        }
    }

    func testProviderConsentDefaultsOffAndPersists() {
        let name = "MomoConsentTests"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.removePersistentDomain(forName: name)
        defaults.set(["gemini", "grok"], forKey: "enabledProviders")
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertTrue(preferences.enabledProviders.isEmpty, "Legacy display toggles are not authorization")
        preferences.setEnabled(true, for: .gemini)
        XCTAssertEqual(PreferencesStore(defaults: defaults).enabledProviders, [.gemini])
        preferences.setEnabled(false, for: .gemini)
        XCTAssertTrue(PreferencesStore(defaults: defaults).enabledProviders.isEmpty)
    }

    func testUnauthorizedScannerReturnsNoSessions() async {
        let snapshots = await LocalActivityScanner().scan(providers: [])
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testRevocationClearsPublishedSessionsImmediately() {
        let monitor = ActivityMonitor(autoRefresh: false, scanner: LocalActivityScanner(home: URL(fileURLWithPath: "/tmp/momo-no-account-fixtures")))
        monitor.setAuthorizedProviders([.gemini])
        monitor.setAuthorizedProviders([])
        XCTAssertTrue(monitor.snapshots.isEmpty)
    }

    func testQuickAskDraftsStayWithTheirChat() {
        let context = QuickAskContext()
        let first = AgentSession(id: "a", provider: .gemini, role: .main, title: "First", detail: "", project: "", updatedAt: .now, isRunning: false, processID: nil, tokens: nil)
        let second = AgentSession(id: "b", provider: .gemini, role: .main, title: "Second", detail: "", project: "", updatedAt: .now, isRunning: false, processID: nil, tokens: nil)
        context.select(first)
        context.draft = "Only for first"
        context.select(second)
        XCTAssertEqual(context.draft, "")
        context.draft = "Only for second"
        context.select(first)
        XCTAssertEqual(context.draft, "Only for first")
        XCTAssertEqual(context.provider, .gemini)
        context.newChat()
        XCTAssertEqual(context.draft, "")
    }

    func testCapabilityTextAndCatalogsAreNotEvidence() {
        let fake: [String: Any] = ["prompt": "mcp__fake__run /skills/fake/SKILL.md", "available_tools": [["model": "fake", "plugins": ["Fake"]]]]
        XCTAssertEqual(SessionCapabilities.infer(from: fake), SessionCapabilities())
        for provider in AIProvider.allCases {
            let event: [String: Any] = ["type": "user", "message": fake, "payload": fake]
            XCTAssertEqual(SessionCapabilities.recorded(in: event, provider: provider), SessionCapabilities())
        }
        let call: [String: Any] = ["type": "response_item", "payload": ["type": "function_call", "name": "mcp__github__search", "arguments": ["plugins": ["Fake"]]]]
        let recorded = SessionCapabilities.recorded(in: call, provider: .codex)
        XCTAssertEqual(recorded.mcpServers, ["github"])
        XCTAssertTrue(recorded.plugins.isEmpty)
    }

    func testRenderCodexOnboarding() throws {
        let view = CodexOnboardingView()
            .environmentObject(PreferencesStore(defaults: UserDefaults(suiteName: "MomoOnboardingPreview")!))
            .environmentObject(ActivityMonitor(autoRefresh: false))
            .environmentObject(AttentionNotifier())
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 548, height: 620)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/momo-onboarding.png"))
    }

    func testRenderChatReply() throws {
        let context = QuickAskContext()
        context.select(AgentSession(id: "reply-fixture", provider: .gemini, role: .main, title: "Repair dashboard session tracking", detail: "", project: "MOMO", updatedAt: .now, isRunning: false, processID: nil, tokens: nil, attention: .needsInput, attentionReason: "Choose which failed session to resume"))
        context.draft = "Resume this chat and verify the last recorded error."
        let view = CommandPaletteView(context: context).environmentObject(PreferencesStore()).preferredColorScheme(.dark).frame(width: 552, height: 350)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 552, height: 350)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/momo-chat-reply.png"))
    }

    func testMomoFramesMatchBrandingIndex() throws {
        struct Frame: Decodable { let rows: [String]; let milliseconds: Int }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/momo-index-frames.json")
        let reference = try JSONDecoder().decode([String: [Frame]].self, from: Data(contentsOf: url))
        for (name, motion) in [("loop", MomoMotion.loop), ("wave", .wave), ("blink", .blink)] {
            let expected = try XCTUnwrap(reference[name])
            XCTAssertEqual(motion.frames.count, expected.count)
            for (actual, reference) in zip(motion.frames, expected) {
                XCTAssertEqual(actual.rows.map { $0.map { $0 ? "#" : "." }.joined() }, reference.rows)
                XCTAssertEqual(actual.milliseconds, reference.milliseconds)
            }
        }
    }

    func testRenderMomoPoseSheet() throws {
        let frames = MomoMotion.loop.frames + MomoMotion.wave.frames + MomoMotion.blink.frames
        let view = LazyVGrid(columns: Array(repeating: GridItem(.fixed(72)), count: 6)) {
            ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                VStack {
                    PixelBarBoyMark(size: 56, frame: frame)
                    Text("\(index + 1)").font(.caption)
                }
            }
        }.padding(16).background(BarBoyStyle.panel).preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 300)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/momo-index-poses.png"))
    }

    func testQuotaRequiresBothRecordedPercentageAndWindow() {
        var snapshot = ProviderSnapshot(provider: .gemini, sessions: [], activeCount: 0, localTokensToday: 999_999, updatedAt: .now)
        XCTAssertEqual(snapshot.quotaLabel, "QUOTA —")
        snapshot.shortWindowPercent = 0
        XCTAssertEqual(snapshot.quotaLabel, "QUOTA —")
        snapshot.shortWindowMinutes = 300
        XCTAssertEqual(snapshot.quotaLabel, "0% / 5HR")
        snapshot.shortWindowPercent = 75
        snapshot.shortWindowMinutes = 90
        XCTAssertEqual(snapshot.quotaLabel, "75% / 90MIN")
        snapshot.shortWindowPercent = 101
        XCTAssertEqual(snapshot.quotaLabel, "QUOTA —")
    }

    func testSessionStateIgnoresNestedToolErrors() {
        let tool: [String: Any] = ["type": "response_item", "payload": ["type": "function_call_output", "output": ["status": "failed"]]]
        XCTAssertNil(SessionSignal.recorded(in: tool, provider: .codex))
        XCTAssertNil(SessionSignal.recorded(in: ["type": "user", "message": ["type": "error"]], provider: .claude))
        let completed: [String: Any] = ["type": "event_msg", "payload": ["type": "task_complete"]]
        XCTAssertEqual(SessionSignal.recorded(in: completed, provider: .codex)?.state, .completed)
        XCTAssertNil(SessionSignal.recorded(in: completed, provider: .grok))
        XCTAssertEqual(SessionSignal.recorded(in: ["type": "result", "is_error": true], provider: .claude)?.state, .failed)
    }

    func testGeminiPublicSchemaFixtures() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        for name in ["gemini-public-conversation.json", "gemini-public-revisions.jsonl"] {
            let source = folder.appendingPathComponent(name)
            let session = try XCTUnwrap(GeminiSessionAdapter.parse(Data(contentsOf: source), source: source))
            XCTAssertEqual(session.id, "gemini-fixture-gemini-01")
            XCTAssertEqual(session.tokens, 30, "Message updates replace totals; rewound messages are excluded")
            XCTAssertEqual(session.model, "gemini-fixture")
            XCTAssertEqual(session.attention, .unknown)
            XCTAssertFalse(session.isRunning)
            XCTAssertEqual(session.capabilityCount, 0, "Tool arguments and prompt strings are not capability evidence")
        }
    }

    func testGeminiIncompleteRecordsStayUnknown() throws {
        let source = URL(fileURLWithPath: "/tmp/synthetic-gemini.json")
        let record: [String: Any] = ["sessionId": "fixture", "projectHash": "fixture", "lastUpdated": "2026-09-12T00:00:00Z", "messages": [["id": "a", "type": "gemini", "tokens": ["total": true]], ["id": "b", "type": "gemini", "tokens": ["total": 10]]]]
        let session = try XCTUnwrap(GeminiSessionAdapter.parse(JSONSerialization.data(withJSONObject: record), source: source))
        XCTAssertNil(session.tokens, "Partial or boolean token totals cannot become a complete total")
        XCTAssertNil(session.model)
        XCTAssertNil(GeminiSessionAdapter.parse(Data("{broken".utf8), source: source))
        XCTAssertNil(GeminiSessionAdapter.parse(Data("{\"messages\": []}".utf8), source: source))
    }

    func testStoppedAfterUsageRequiresObservedWorkingTransition() {
        var tracker = SessionProgressTracker()
        func snapshot(_ tokens: Int, _ state: AgentAttention) -> [ProviderSnapshot] {
            [ProviderSnapshot(provider: .codex, sessions: [AgentSession(id: "s", provider: .codex, role: .main, title: "Fixture", detail: "", project: "", updatedAt: .now, isRunning: false, processID: nil, tokens: tokens, attention: state)], activeCount: 0, localTokensToday: tokens, updatedAt: .now)]
        }
        XCTAssertFalse(tracker.update(snapshot(10, .working))[0].sessions[0].stoppedAfterUsageGrowth)
        XCTAssertFalse(tracker.update(snapshot(20, .working))[0].sessions[0].stoppedAfterUsageGrowth)
        XCTAssertTrue(tracker.update(snapshot(20, .failed))[0].sessions[0].stoppedAfterUsageGrowth)
        XCTAssertFalse(tracker.update(snapshot(20, .working))[0].sessions[0].stoppedAfterUsageGrowth)
        XCTAssertFalse(tracker.update(snapshot(20, .failed))[0].sessions[0].stoppedAfterUsageGrowth)
        XCTAssertFalse(tracker.update(snapshot(50, .unknown))[0].sessions[0].stoppedAfterUsageGrowth)
    }

    func testAutoResumeRequiresTerminalUsageStopAndLatestReset() throws {
        let id = "11111111-2222-4333-8444-555555555555"
        let records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": id, "cwd": "/tmp", "source": "cli"]],
            ["type": "event_msg", "payload": ["type": "token_count", "rate_limits": ["primary": ["used_percent": 100, "resets_at": 2_000_000_000], "secondary": ["used_percent": 100, "resets_at": 2_000_000_600]]]],
            ["type": "event_msg", "payload": ["type": "error", "codex_error_info": "usage_limit_exceeded"]],
            ["type": "event_msg", "payload": ["type": "task_complete", "last_agent_message": NSNull()]]
        ]
        func encode(_ value: [[String: Any]]) throws -> Data {
            try value.reduce(into: Data()) { result, record in
                result.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
                result.append(10)
            }
        }
        let candidate = try XCTUnwrap(CodexResumeCandidate.parse(encode(records)))
        XCTAssertEqual(candidate.sessionID, id)
        XCTAssertEqual(candidate.resetAt.timeIntervalSince1970, 2_000_000_600)
        XCTAssertEqual(Array(candidate.arguments.prefix(3)), ["exec", "resume", id])
        XCTAssertFalse(candidate.arguments.contains("--last"))
        XCTAssertFalse(candidate.arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
        XCTAssertNil(CodexResumeCandidate.parse(try encode(Array(records.dropLast()))), "An error alone does not prove the turn is stopped")
        for type in ["turn_aborted", "task_started", "user_message", "request_user_input"] {
            XCTAssertNil(CodexResumeCandidate.parse(try encode(records + [["type": "event_msg", "payload": ["type": type]]])))
        }
        var desktop = records
        desktop[0] = ["type": "session_meta", "payload": ["id": id, "cwd": "/tmp", "source": "vscode"]]
        XCTAssertNil(CodexResumeCandidate.parse(try encode(desktop)))
        var unrelated = records
        unrelated[2] = ["type": "event_msg", "payload": ["type": "error", "codex_error_info": "other", "message": "usage limit"]]
        XCTAssertNil(CodexResumeCandidate.parse(try encode(unrelated)))
    }

    func testAutoResumeSettingPersistsAndDefaultsOff() {
        let name = "MomoAutoResumeTests"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.removePersistentDomain(forName: name)
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertFalse(preferences.autoResumeAfterReset)
        preferences.autoResumeAfterReset = true
        XCTAssertTrue(PreferencesStore(defaults: defaults).autoResumeAfterReset)
        let service = AutoResumeService(defaults: defaults)
        service.update(snapshots: [], enabled: true, authorized: [])
        XCTAssertTrue(service.status.contains("authorization"))
        service.update(snapshots: [], enabled: false, authorized: [.codex])
        XCTAssertTrue(service.status.hasPrefix("Off"))
    }

    func testAutoResumeWaitsThenDispatchesOnceAcrossRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("fixture.jsonl")
        let records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "11111111-2222-4333-8444-555555555555", "cwd": folder.path, "source": "cli"]],
            ["type": "event_msg", "payload": ["type": "token_count", "rate_limits": ["primary": ["used_percent": 100, "resets_at": 2_000_000_000]]]],
            ["type": "event_msg", "payload": ["type": "task_complete", "error": ["codex_error_info": "usage_limit_exceeded"]]]
        ]
        var data = Data()
        for record in records { data.append(try JSONSerialization.data(withJSONObject: record)); data.append(10) }
        try data.write(to: source)
        let name = "MomoResumeDispatch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        // A harmless executable verifies real dispatch without starting an agent,
        // reading credentials, or sending anything to a provider.
        let service = AutoResumeService(defaults: defaults, executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        let session = AgentSession(id: "fixture", provider: .codex, role: .main, title: "Fixture", detail: "", project: "", updatedAt: .now, isRunning: false, processID: nil, tokens: nil, attention: .failed, sourceURL: source)
        let snapshots = [ProviderSnapshot(provider: .codex, sessions: [session], activeCount: 0, localTokensToday: 0, updatedAt: .now)]
        service.update(snapshots: snapshots, enabled: true, authorized: [.codex], now: Date(timeIntervalSince1970: 1_999_999_999))
        XCTAssertTrue(service.status.hasPrefix("Waiting for reset"))
        XCTAssertNil(defaults.stringArray(forKey: "autoResume.attempted.v1"))
        service.update(snapshots: snapshots, enabled: true, authorized: [.codex], now: Date(timeIntervalSince1970: 2_000_000_006))
        XCTAssertEqual(defaults.stringArray(forKey: "autoResume.attempted.v1")?.count, 1)
        for _ in 0..<30 {
            if service.status == "Automatic continuation finished" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(service.status, "Automatic continuation finished")
        let restarted = AutoResumeService(defaults: defaults, executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        restarted.update(snapshots: snapshots, enabled: true, authorized: [.codex], now: Date(timeIntervalSince1970: 2_000_000_100))
        XCTAssertEqual(restarted.status, "Watching for recorded Codex CLI usage stops")
        XCTAssertEqual(defaults.stringArray(forKey: "autoResume.attempted.v1")?.count, 1)
    }

    func testRecordedQuotaExpiresWithoutInventingZero() throws {
        let event: [String: Any] = ["type": "event_msg", "timestamp": "2026-09-12T00:00:00Z", "payload": ["type": "token_count", "rate_limits": ["primary": ["used_percent": 76, "window_minutes": 300, "resets_at": 2_000_000_000]]]]
        let quota = try XCTUnwrap(RecordedQuotaWindow.codex(in: event)?.first)
        XCTAssertEqual(quota.label(now: Date(timeIntervalSince1970: 1_999_999_999)), "76% / 5HR")
        XCTAssertEqual(quota.label(now: Date(timeIntervalSince1970: 2_000_000_000)), "QUOTA —")
        let injected: [String: Any] = ["type": "user", "payload": event]
        XCTAssertNil(RecordedQuotaWindow.codex(in: injected))
        var invalid = event
        invalid["payload"] = ["type": "token_count", "rate_limits": ["primary": ["used_percent": true, "window_minutes": 300]]]
        XCTAssertEqual(RecordedQuotaWindow.codex(in: invalid), [])
    }

    func testScannerPublishesRecordedQuotaFromIsolatedFixture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record: [String: Any] = ["type": "event_msg", "timestamp": "2026-09-12T00:00:00Z", "payload": ["type": "token_count", "rate_limits": ["primary": ["used_percent": 76, "window_minutes": 300, "resets_at": 2_000_000_000]]]]
        try JSONSerialization.data(withJSONObject: record).write(to: sessions.appendingPathComponent("quota-fixture.jsonl"))
        let scanner = LocalActivityScanner(home: root, detectProcesses: false)
        let snapshots = await scanner.scan(providers: [.codex])
        let result = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions.first?.recordedQuotaWindows.first?.percent, 76)
        XCTAssertEqual(result.recordedQuota?.minutes, 300)
        XCTAssertEqual(result.quotaLabel, "76% / 5HR")
        XCTAssertEqual(result.activeCount, 0)
    }

    func testProviderCoverage() {
        XCTAssertEqual(AIProvider.allCases.map(\.name), ["Codex", "Claude", "Gemini", "Cursor", "Grok"])
        XCTAssertTrue(AIProvider.allCases.allSatisfy { !$0.sessionRoots.isEmpty })
    }

    func testSnapshotUsageFormatting() {
        let snapshot = ProviderSnapshot(provider: .codex, sessions: [], activeCount: 0, localTokensToday: 12_400, updatedAt: .now)
        XCTAssertEqual(snapshot.usageText, "12.4K")
    }

    func testProcessMatchingAvoidsProjectPathFalsePositives() {
        XCTAssertTrue(AIProvider.codex.matchesProcessCommand("/opt/homebrew/bin/codex --resume"))
        XCTAssertTrue(AIProvider.claude.matchesProcessCommand("/usr/local/bin/claude --continue"))
        XCTAssertTrue(AIProvider.cursor.matchesProcessCommand("/Applications/Cursor.app/Contents/MacOS/Cursor"))
        XCTAssertTrue(AIProvider.grok.matchesProcessCommand("/opt/homebrew/bin/grok-bot run"))
        XCTAssertFalse(AIProvider.codex.matchesProcessCommand("/usr/bin/xcodebuild -project /Users/me/Documents/Codex/App.xcodeproj"))
        XCTAssertFalse(AIProvider.codex.matchesProcessCommand("/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper"))
    }

    func testDeskDisplayPayloadCanHideSensitiveTitles() throws {
        let session = AgentSession(id: "secret", provider: .codex, role: .main, title: "Confidential acquisition", detail: "", project: "Stealth", updatedAt: .now, isRunning: true, processID: 7, tokens: 900)
        let snapshot = ProviderSnapshot(provider: .codex, sessions: [session], activeCount: 1, localTokensToday: 900, updatedAt: .now)
        let redacted = DeskDisplayServer.makeStatusJSON(snapshots: [snapshot], includeTitles: false)
        let visible = DeskDisplayServer.makeStatusJSON(snapshots: [snapshot], includeTitles: true)
        let redactedText = String(decoding: redacted, as: UTF8.self)
        let visibleText = String(decoding: visible, as: UTF8.self)
        XCTAssertFalse(redactedText.contains("Confidential acquisition"))
        XCTAssertFalse(redactedText.contains("Stealth"))
        XCTAssertTrue(visibleText.contains("Confidential acquisition"))
        XCTAssertTrue(visibleText.contains("Stealth"))
    }

    func testDeskDisplayHTMLIsSmallScreenFirst() {
        let html = DeskDisplayServer.dashboardHTML(token: "abc123")
        XCTAssertTrue(html.contains("width=device-width"))
        XCTAssertTrue(html.contains("YOUR RETURN QUEUE"))
        XCTAssertTrue(html.contains("abc123"))
        XCTAssertTrue(html.contains("overflow:hidden"))
        XCTAssertTrue(html.contains("NEED"))
    }

    func testCapabilityProvenanceInference() {
        let event: [String: Any] = [
            "model_name": "gpt-5.6",
            "tool_name": "mcp__github__search_code",
            "skill_path": "/Users/me/.agents/skills/frontend-design/SKILL.md",
            "plugins": ["Codex Security"]
        ]
        let result = SessionCapabilities.infer(from: event)
        XCTAssertEqual(result.model, "gpt-5.6")
        XCTAssertTrue(result.mcpServers.contains("github"))
        XCTAssertTrue(result.skills.contains("frontend-design"))
        XCTAssertTrue(result.plugins.contains("Codex Security"))
    }

    func testDeskDisplayIncludesCapabilityProvenance() throws {
        let session = AgentSession(id: "cap", provider: .codex, role: .main, title: "Build", detail: "", project: "Hub", updatedAt: .now, isRunning: true, processID: nil, tokens: nil, model: "gpt-5.6", mcpServers: ["github"], skills: ["ship"], plugins: ["security"])
        let snapshot = ProviderSnapshot(provider: .codex, sessions: [session], activeCount: 1, localTokensToday: 0, updatedAt: .now)
        let text = String(decoding: DeskDisplayServer.makeStatusJSON(snapshots: [snapshot], includeTitles: true), as: UTF8.self)
        XCTAssertTrue(text.contains("gpt-5.6"))
        XCTAssertTrue(text.contains("github"))
        XCTAssertTrue(text.contains("ship"))
        XCTAssertTrue(text.contains("security"))
        XCTAssertTrue(text.contains("capabilityCount"))
    }

    func testRunningSessionWinsAgeLabel() {
        let session = AgentSession(id: "1", provider: .claude, role: .subagent, title: "Test", detail: "", project: "BAR BOY", updatedAt: .distantPast, isRunning: true, processID: 123, tokens: nil)
        XCTAssertEqual(session.ageLabel, "LIVE")
    }

    func testRenderDashboardSnapshotsWhenRequested() throws {
        let now = Date()
        var sessions = [
            AgentSession(id: "codex-main", provider: .codex, role: .main, title: "Building the BAR BOY menu app", detail: "Implementing the local activity dashboard", project: "Bar-Boy", updatedAt: now, isRunning: true, processID: 88, tokens: 12_400, model: "GPT-5.6", mcpServers: ["github", "web"], skills: ["frontend-design"], plugins: []),
            AgentSession(id: "codex-sub", provider: .codex, role: .subagent, title: "Verifying provider adapters", detail: "Checking local session discovery", project: "Bar-Boy", updatedAt: now, isRunning: true, processID: 89, tokens: 4_800, attention: .failed, model: "GPT-5.6", mcpServers: [], skills: ["qa"], plugins: []),
            AgentSession(id: "claude-main", provider: .claude, role: .main, title: "Reviewing onboarding copy", detail: "Recent local session", project: "Momo", updatedAt: now.addingTimeInterval(-420), isRunning: false, processID: nil, tokens: 31_200, attention: .needsInput, attentionReason: "Approve the revised copy", model: "Claude Sonnet", mcpServers: ["figma"], skills: ["brand"], plugins: ["Canva"])
        ]
        sessions[1].stoppedAfterUsageGrowth = true
        var snapshots = [
            ProviderSnapshot(provider: .codex, sessions: Array(sessions.prefix(2)), activeCount: 2, localTokensToday: 17_200, updatedAt: now),
            ProviderSnapshot(provider: .claude, sessions: [sessions[2]], activeCount: 0, localTokensToday: 31_200, updatedAt: now),
            ProviderSnapshot(provider: .gemini, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: now),
            ProviderSnapshot(provider: .cursor, sessions: [], activeCount: 1, localTokensToday: 8_900, updatedAt: now),
            ProviderSnapshot(provider: .grok, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: now)
        ]
        snapshots[0].shortWindowPercent = 76
        snapshots[0].shortWindowMinutes = 300
        let monitor = ActivityMonitor(autoRefresh: false, snapshots: snapshots)
        let suite = UserDefaults(suiteName: "BarBoySnapshotTests")!
        suite.removePersistentDomain(forName: "BarBoySnapshotTests")
        let preferences = PreferencesStore(defaults: suite)
        AIProvider.allCases.forEach { preferences.setEnabled(true, for: $0) }
        let deskDisplay = DeskDisplayServer(defaults: suite)
        try render(preferredScheme: .dark, name: "barboy-dark", monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try render(preferredScheme: .light, name: "barboy-light", monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try render(preferredScheme: .dark, name: "barboy-agents-dark", initialTab: .agents, monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try render(preferredScheme: .dark, name: "barboy-tools-dark", initialTab: .tools, monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try renderCompact(preferredScheme: .dark, name: "barboy-compact-dark", monitor: monitor, preferences: preferences)
        try renderCompact(preferredScheme: .light, name: "barboy-compact-light", monitor: monitor, preferences: preferences)
    }

    private func render(preferredScheme: ColorScheme, name: String, initialTab: DashboardTab = .home, monitor: ActivityMonitor, preferences: PreferencesStore, deskDisplay: DeskDisplayServer) throws {
        let view = DashboardView(refreshOnAppear: false, initialTab: initialTab)
            .environmentObject(monitor)
            .environmentObject(preferences)
            .environmentObject(deskDisplay)
            .preferredColorScheme(preferredScheme)
            .frame(width: 430, height: 640)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 640)
        hostingView.appearance = NSAppearance(named: preferredScheme == .dark ? .darkAqua : .aqua)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not render dashboard")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode dashboard")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"), options: .atomic)
    }

    private func renderCompact(preferredScheme: ColorScheme, name: String, monitor: ActivityMonitor, preferences: PreferencesStore) throws {
        let view = CompactDashboardView(refreshOnAppear: false, animateMomo: false)
            .environmentObject(monitor)
            .environmentObject(preferences)
            .preferredColorScheme(preferredScheme)
            .frame(width: 430, height: 174)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 174)
        hostingView.appearance = NSAppearance(named: preferredScheme == .dark ? .darkAqua : .aqua)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not render compact dashboard")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode compact dashboard")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"), options: .atomic)
    }
}
