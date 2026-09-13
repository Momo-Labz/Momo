import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import BAR_BOY

@MainActor
final class BarBoyTests: XCTestCase {
    final class CountingSessionAdapter: ProviderSessionAdapter, @unchecked Sendable {
        let provider: AIProvider
        private let lock = NSLock()
        private var value = 0

        init(provider: AIProvider) {
            self.provider = provider
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func session(from file: ProviderSessionFile, context: ProviderSessionContext) -> AgentSession? {
            lock.lock()
            value += 1
            lock.unlock()
            return AgentSession(
                id: "\(provider.rawValue)-fixture",
                provider: provider,
                role: .main,
                title: "\(provider.name) fixture",
                detail: "Fixture",
                project: "Fixture",
                updatedAt: file.modifiedAt,
                isRunning: false,
                processID: nil,
                tokens: nil,
                attention: .unknown
            )
        }
    }

    func testShortcutRebindingRejectsDuplicatesAndPersists() throws {
        let suite = "MomoShortcutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = GlobalShortcutService(defaults: defaults, register: false)
        let original = shortcuts.bindings[.quickAsk]
        XCTAssertNotNil(shortcuts.update(ShortcutAction.talk.defaultBinding, for: .quickAsk))
        XCTAssertEqual(shortcuts.bindings[.quickAsk], original)
        XCTAssertNotNil(shortcuts.update(ShortcutBinding(key: 40, modifiers: 0, character: "K"), for: .quickAsk))
        let replacement = ShortcutBinding(key: 40, modifiers: original!.modifiers, character: "K")
        XCTAssertNil(shortcuts.update(replacement, for: .quickAsk))
        XCTAssertEqual(GlobalShortcutService(defaults: defaults, register: false).bindings[.quickAsk], replacement)
    }

    func testShortcutCanBeTurnedOffAndPersistsSeparately() {
        let suite = "MomoShortcutToggleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = GlobalShortcutService(defaults: defaults, register: false)
        XCTAssertNil(shortcuts.setEnabled(false, for: .handsFree))
        XCTAssertFalse(shortcuts.isEnabled(.handsFree))
        XCTAssertFalse(GlobalShortcutService(defaults: defaults, register: false).isEnabled(.handsFree))
        XCTAssertNil(shortcuts.setEnabled(true, for: .handsFree))
        XCTAssertTrue(shortcuts.isEnabled(.handsFree))
    }

    func testHandsFreeCommandsRequireAnExplicitEnding() {
        XCTAssertTrue(VoiceInput.hasStopCommand("Please inspect this. MOMO stop."))
        XCTAssertFalse(VoiceInput.hasStopCommand("Stop the worker and continue"))
        XCTAssertFalse(VoiceInput.hasStopCommand("MOMO stop is the command I use"))
        XCTAssertEqual(VoiceInput.removingStopCommand("Hello MOMO stop!"), "Hello")
        XCTAssertTrue(VoiceInput.hasDraftCommand("Hello MOMO use draft"))
        XCTAssertEqual(VoiceInput.removingDraftCommand("Hello MOMO use draft."), "Hello")
    }

    func testBothQuotaWindowsRemainVisibleAndExpireHonestly() {
        var snapshot = ProviderSnapshot(provider: .codex, sessions: [], activeCount: 0, localTokensToday: 10, updatedAt: .now)
        snapshot.recordedQuotas = [
            RecordedQuotaWindow(percent: 32, minutes: 10080, resetsAt: .now.addingTimeInterval(600), observedAt: .now),
            RecordedQuotaWindow(percent: 76, minutes: 300, resetsAt: .now.addingTimeInterval(600), observedAt: .now)
        ]
        XCTAssertTrue(snapshot.quotaLabels[0].hasPrefix("5HR 76%"), snapshot.quotaLabels[0])
        XCTAssertTrue(snapshot.quotaLabels[1].hasPrefix("WEEK 32%"), snapshot.quotaLabels[1])
        snapshot.recordedQuotas = [RecordedQuotaWindow(percent: 100, minutes: 300, resetsAt: .distantPast, observedAt: .distantPast)]
        XCTAssertEqual(snapshot.quotaLabels, ["QUOTA —", "LONG —"])
    }

    func testVoicePopupRendersWithoutMicrophoneAccess() throws {
        let voice = VoiceInput()
        voice.prepare(.handsFree)
        let view = VoicePopup(voice: voice).preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 464, height: 340)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/momo-voice.png"))
        XCTAssertEqual(voice.state, .ready)
        XCTAssertFalse(voice.isActive)
    }

    func testRecordedChatNamesUseLatestRenameNotPromptText() throws {
        let id = "12345678-1234-1234-1234-123456789abc"
        let records: [[String: Any]] = [
            ["id": id, "thread_name": "Old name", "updated_at": "2026-09-01"],
            ["id": id, "thread_name": "Extend Gemini dashboard", "updated_at": "2026-09-12"],
            ["id": "bad", "thread_name": "Invalid identity"]
        ]
        let data = try records.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n").data(using: .utf8)!
        XCTAssertEqual(CodexChatNames.parse(data), [id: "Extend Gemini dashboard"])
    }

    func testConversationLabelsPersistWithoutChangingIdentity() {
        let suite = "MomoLabels-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        let session = AgentSession(id: "stable-id", provider: .codex, role: .main, title: "Original", detail: "", project: "Original folder", updatedAt: .now, isRunning: false, processID: nil, tokens: nil)
        preferences.setLabel(name: "Dashboard work", folder: "Momo Labz", for: session)
        let shown = PreferencesStore(defaults: defaults).presented(session)
        XCTAssertEqual(shown.title, "Dashboard work")
        XCTAssertEqual(shown.project, "Momo Labz")
        XCTAssertEqual(shown.id, session.id)
        XCTAssertEqual(session.title, "Original")
    }

    func testAutoResumeNeverClaimsOtherProvidersAreConnected() {
        let service = AutoResumeService(defaults: UserDefaults(suiteName: "MomoResumeVisibility")!)
        service.update(snapshots: [], enabled: true, authorized: Set(AIProvider.allCases))
        for provider in AIProvider.allCases {
            let session = AgentSession(id: provider.rawValue, provider: provider, role: .main, title: "Fixture", detail: "", project: "", updatedAt: .now, isRunning: false, processID: nil, tokens: nil)
            let state = service.state(for: session)
            // Without a recorded CLI rollout nothing here can continue unattended,
            // so the state must read as manual and never imply automation.
            XCTAssertTrue(state.hasPrefix("Manual"), "\(provider.name): \(state)")
            for claim in ["Resumes", "Continuing", "automatic"] {
                XCTAssertFalse(state.contains(claim), "\(provider.name) claimed \(claim): \(state)")
            }
        }
    }

    func testQuotaLabelShowsResetCountdownAndDashesWhenExpired() {
        let now = Date()
        let live = RecordedQuotaWindow(percent: 31, minutes: 300, resetsAt: now.addingTimeInterval(4 * 3600), observedAt: now)
        XCTAssertEqual(live.label(now: now), "5HR 31% · 4H")
        let week = RecordedQuotaWindow(percent: 91, minutes: 10080, resetsAt: now.addingTimeInterval(2 * 86_400), observedAt: now)
        XCTAssertEqual(week.label(now: now), "WEEK 91% · 2D")
        // No recorded reset: report the window without inventing a countdown.
        let noReset = RecordedQuotaWindow(percent: 50, minutes: 300, resetsAt: nil, observedAt: now)
        XCTAssertEqual(noReset.label(now: now), "5HR 50%")
        // Expired data is a dash, never a zero.
        let expired = RecordedQuotaWindow(percent: 99, minutes: 300, resetsAt: now.addingTimeInterval(-60), observedAt: now)
        XCTAssertEqual(expired.label(now: now), "QUOTA —")
    }

    func testAutoResumeStateCountsDownPerConversation() {
        let now = Date()
        let window = RecordedQuotaWindow(percent: 100, minutes: 300, resetsAt: now.addingTimeInterval(4 * 3600), observedAt: now)
        let service = AutoResumeService(defaults: UserDefaults(suiteName: "MomoResumeCountdown")!,
                                        executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        service.update(snapshots: [], enabled: true, authorized: Set(AIProvider.allCases))

        let cli = AgentSession(id: "cli", provider: .codex, role: .main, title: "A", detail: "", project: "F", updatedAt: now, isRunning: false, processID: nil, tokens: nil, recordedQuotaWindows: [window], recordedSource: "cli")
        XCTAssertEqual(service.state(for: cli, now: now), "Resumes in 4H")

        // A provider with no supported unattended path still gets the exact countdown.
        let claude = AgentSession(id: "cl", provider: .claude, role: .main, title: "B", detail: "", project: "F", updatedAt: now, isRunning: false, processID: nil, tokens: nil, recordedQuotaWindows: [window], recordedSource: nil)
        XCTAssertEqual(service.state(for: claude, now: now), "Manual · resets in 4H")
    }

    func testMenuBarSeparatesAWaitingQuestionFromAFailure() {
        func snapshot(_ attention: AgentAttention) -> ProviderSnapshot {
            let session = AgentSession(id: "s", provider: .claude, role: .main, title: "T", detail: "", project: "P", updatedAt: .now, isRunning: false, processID: nil, tokens: nil, attention: attention)
            return ProviderSnapshot(provider: .claude, sessions: [session], activeCount: 0, localTokensToday: 0, updatedAt: .now)
        }
        let waiting = snapshot(.needsInput)
        XCTAssertEqual(waiting.waitingCount, 1)
        XCTAssertEqual(waiting.failedCount, 0)
        let failed = snapshot(.failed)
        XCTAssertEqual(failed.waitingCount, 0)
        XCTAssertEqual(failed.failedCount, 1)
        // Both still count as urgent for the existing return queue.
        XCTAssertEqual(waiting.needsAttentionCount, 1)
        XCTAssertEqual(failed.needsAttentionCount, 1)
    }

    func testClaudeAdapterHedgesAnIdleOpenToolCall() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("momo-open-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func session(answered: Bool, quietFor seconds: TimeInterval) throws -> AgentSession? {
            var lines = [#"{"type":"user","cwd":"/Users/me/Demo","message":{"content":[{"type":"text","text":"go"}]}}"#,
                         #"{"type":"assistant","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"t1","name":"Bash"}]}}"#]
            if answered {
                lines.append(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}"#)
            }
            let url = directory.appendingPathComponent("\(answered)-\(seconds).jsonl")
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            let modified = Date(timeIntervalSince1970: 1_789_056_000)
            let file = ProviderSessionFile(url: url, modifiedAt: modified, index: 0)
            let context = ProviderSessionContext(now: modified.addingTimeInterval(seconds), isProviderRunning: false)
            return ClaudeSessionAdapter().session(from: file, context: context)
        }

        // An open call that has gone quiet reads as a prompt that may be on screen.
        let idle = try XCTUnwrap(session(answered: false, quietFor: 120))
        XCTAssertEqual(idle.attention, .needsInput)
        XCTAssertTrue(try XCTUnwrap(idle.attentionReason).contains("may be waiting"), idle.attentionReason ?? "")

        // Still within the grace period: the tool is probably just running.
        let fresh = try XCTUnwrap(session(answered: false, quietFor: 2))
        XCTAssertNotEqual(fresh.attention, .needsInput)

        // Answered: nothing is waiting, however long ago it happened.
        let answered = try XCTUnwrap(session(answered: true, quietFor: 600))
        XCTAssertNotEqual(answered.attention, .needsInput)
    }

    func testNotifierDetectsARecentlyReopenedWindowOnce() {
        let now = Date()
        func session(reset: TimeInterval) -> AgentSession {
            AgentSession(id: "s", provider: .claude, role: .main, title: "A", detail: "", project: "F", updatedAt: now, isRunning: false, processID: nil, tokens: nil,
                         recordedQuotaWindows: [RecordedQuotaWindow(percent: 10, minutes: 300, resetsAt: now.addingTimeInterval(reset), observedAt: now)])
        }
        XCTAssertNotNil(AttentionNotifier.justReset(session(reset: -60), now: now))
        XCTAssertNil(AttentionNotifier.justReset(session(reset: -7200), now: now), "a window that reset hours ago is stale")
        XCTAssertNil(AttentionNotifier.justReset(session(reset: 3600), now: now), "a window that has not reset yet")
    }

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
        let view = CommandPaletteView(embedded: true, context: context)
            .environmentObject(ActivityMonitor(autoRefresh: false))
            .environmentObject(PreferencesStore())
            .preferredColorScheme(.dark)
            .frame(width: 430, height: 520)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 520)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/momo-chat-reply.png"))
    }

    func testRenderCompactModelsWithTopOffButton() throws {
        let now = Date()
        var codex = ProviderSnapshot(provider: .codex, sessions: [
            AgentSession(id: "compact-codex", provider: .codex, role: .main, title: "Fix MOMO flow", detail: "", project: "MOMO", updatedAt: now, isRunning: false, processID: nil, tokens: 58_600, attention: .needsInput, attentionReason: "Needs a reply", model: "gpt-fixture")
        ], activeCount: 0, localTokensToday: 58_600, updatedAt: now)
        codex.recordedQuotas = [
            RecordedQuotaWindow(percent: 40, minutes: 10080, resetsAt: now.addingTimeInterval(6 * 86_400), observedAt: now)
        ]
        let snapshots = [
            codex,
            ProviderSnapshot(provider: .claude, sessions: [
                AgentSession(id: "compact-claude", provider: .claude, role: .main, title: "Review copy", detail: "", project: "MOMO", updatedAt: now, isRunning: false, processID: nil, tokens: 105_400, attention: .working)
            ], activeCount: 0, localTokensToday: 105_400, updatedAt: now),
            ProviderSnapshot(provider: .cursor, sessions: [], activeCount: 1, localTokensToday: 0, updatedAt: now)
        ]
        let defaults = UserDefaults(suiteName: "MomoCompactPreview")!
        defer { defaults.removePersistentDomain(forName: "MomoCompactPreview") }
        defaults.removePersistentDomain(forName: "MomoCompactPreview")
        defaults.set(["codex", "claude", "cursor"], forKey: "authorizedLocalProviders.v1")
        let view = CompactDashboardView(refreshOnAppear: false)
            .environmentObject(ActivityMonitor(autoRefresh: false, snapshots: snapshots))
            .environmentObject(PreferencesStore(defaults: defaults))
            .preferredColorScheme(.dark)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 220)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/momo-compact-models.png"))
    }

    func testRenderExpandedFolderAskPath() throws {
        MomoSurface.shared.expanded = true
        MomoSurface.shared.show(.sessions)
        let now = Date()
        let snapshots = [
            ProviderSnapshot(provider: .codex, sessions: [
                AgentSession(id: "expanded-a", provider: .codex, role: .main, title: "MOMO network brain", detail: "Waiting for your reply", project: "MOMO", updatedAt: now, isRunning: false, processID: nil, tokens: nil, attention: .needsInput, attentionReason: "Prompt needs a decision"),
                AgentSession(id: "expanded-b", provider: .codex, role: .main, title: "ClearEC model package", detail: "Completed", project: "CLEAR-EC", updatedAt: now.addingTimeInterval(-600), isRunning: false, processID: nil, tokens: nil, attention: .completed)
            ], activeCount: 0, localTokensToday: 0, updatedAt: now)
        ]
        let defaults = UserDefaults(suiteName: "MomoExpandedPreview")!
        defer { defaults.removePersistentDomain(forName: "MomoExpandedPreview") }
        defaults.removePersistentDomain(forName: "MomoExpandedPreview")
        defaults.set(["codex"], forKey: "authorizedLocalProviders.v1")
        let view = DashboardView(refreshOnAppear: false)
            .environmentObject(ActivityMonitor(autoRefresh: false, snapshots: snapshots))
            .environmentObject(PreferencesStore(defaults: defaults))
            .environmentObject(DeskDisplayServer(defaults: defaults))
            .environmentObject(AttentionNotifier())
            .preferredColorScheme(.dark)
            .frame(width: 430, height: 680)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 680)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/momo-expanded-folders.png"))
    }

    func testRenderNewPromptComposerWithRecentFolders() throws {
        let context = QuickAskContext()
        context.provider = .codex
        context.draft = "Summarize what is blocked"
        context.attach([URL(fileURLWithPath: "/tmp/HANDOFF.md")])
        let now = Date()
        let snapshots = [
            ProviderSnapshot(provider: .codex, sessions: [
                AgentSession(id: "a", provider: .codex, role: .main, title: "A", detail: "", project: "MOMO", updatedAt: now, isRunning: false, processID: nil, tokens: nil),
                AgentSession(id: "b", provider: .codex, role: .main, title: "B", detail: "", project: "CLEAR-EC", updatedAt: now.addingTimeInterval(-10), isRunning: false, processID: nil, tokens: nil),
                AgentSession(id: "c", provider: .codex, role: .main, title: "C", detail: "", project: "Webpage", updatedAt: now.addingTimeInterval(-20), isRunning: false, processID: nil, tokens: nil)
            ], activeCount: 0, localTokensToday: 0, updatedAt: now)
        ]
        let view = CommandPaletteView(embedded: true, context: context)
            .environmentObject(ActivityMonitor(autoRefresh: false, snapshots: snapshots))
            .environmentObject(PreferencesStore())
            .preferredColorScheme(.dark)
            .frame(width: 430, height: 520)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 520)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/momo-new-prompt.png"))
    }

    func testRenderNetworkBrainMap() throws {
        let now = Date()
        let sessions = [
            AgentSession(
                id: "brain-codex",
                provider: .codex,
                role: .main,
                title: "Fix provider usage cards",
                detail: "Codex is waiting for a reply",
                project: "MOMO",
                updatedAt: now,
                isRunning: false,
                processID: nil,
                tokens: 1200,
                attention: .needsInput,
                attentionReason: "The latest task needs your reply",
                model: "gpt-fixture",
                mcpServers: ["github"],
                skills: ["investigate"]
            ),
            AgentSession(
                id: "brain-claude",
                provider: .claude,
                role: .main,
                title: "Review dashboard copy",
                detail: "Claude completed",
                project: "MOMO",
                updatedAt: now,
                isRunning: false,
                processID: nil,
                tokens: 900,
                attention: .completed,
                model: "claude-fixture",
                skills: ["ui-styling"]
            )
        ]
        let snapshots = [
            ProviderSnapshot(provider: .codex, sessions: [sessions[0]], activeCount: 0, localTokensToday: 1200, updatedAt: now),
            ProviderSnapshot(provider: .claude, sessions: [sessions[1]], activeCount: 0, localTokensToday: 900, updatedAt: now)
        ]
        let defaults = UserDefaults(suiteName: "MomoNetworkPreview")!
        defer { defaults.removePersistentDomain(forName: "MomoNetworkPreview") }
        defaults.removePersistentDomain(forName: "MomoNetworkPreview")
        defaults.set(["codex", "claude"], forKey: "authorizedLocalProviders.v1")
        let view = DashboardView(refreshOnAppear: false, initialTab: .network, showsOverview: true)
            .environmentObject(ActivityMonitor(autoRefresh: false, snapshots: snapshots))
            .environmentObject(PreferencesStore(defaults: defaults))
            .preferredColorScheme(.dark)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 860, height: 790)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/momo-network-brain.png"))
    }

    func testQuickAskComposesImprovedPromptWithFolderAndAttachments() {
        let context = QuickAskContext()
        context.provider = .claude
        context.draft = "Fix the provider cards"
        context.selectFolder("MOMO")
        context.attach([URL(fileURLWithPath: "/tmp/spec.md")])
        let prompt = context.composedPrompt
        XCTAssertTrue(prompt.contains("Task:\nFix the provider cards"))
        XCTAssertTrue(prompt.contains("- Folder: MOMO"))
        XCTAssertTrue(prompt.contains("- /tmp/spec.md"))
        XCTAssertTrue(prompt.contains("do not invent capabilities or usage data"))
        context.promptEnhancementEnabled = false
        XCTAssertEqual(context.composedPrompt, "Fix the provider cards")
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

    func testGrokDocumentedSessionFixtureIsSchemaDirected() throws {
        let source = fixtureURL(named: "grok-session/updates.jsonl")
        let session = try XCTUnwrap(GrokSessionAdapter().session(
            from: ProviderSessionFile(url: source, modifiedAt: .now, index: 0),
            context: ProviderSessionContext(now: .now, isProviderRunning: false)
        ))
        XCTAssertEqual(session.id, "grok-fixture-grok-01")
        XCTAssertEqual(session.title, "Review the provider dashboard")
        XCTAssertEqual(session.model, "grok-fixture")
        XCTAssertEqual(session.tokens, 30)
        XCTAssertEqual(session.attention, .completed)
        XCTAssertEqual(session.mcpServers, ["fixture-files"])
        XCTAssertEqual(session.skills, ["fixture-review"])
        XCTAssertTrue(session.plugins.isEmpty, "Grok omits plugins from this documented stream")
        XCTAssertFalse(session.isRunning)
    }

    func testGrokMalformedOrNonUpdateFilesFailClosed() throws {
        let source = URL(fileURLWithPath: "/tmp/grok-summary.json")
        XCTAssertNil(GrokSessionAdapter().session(
            from: ProviderSessionFile(url: source, modifiedAt: .now, index: 0),
            context: ProviderSessionContext(now: .now, isProviderRunning: false)
        ))
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
        let service = AutoResumeService(defaults: defaults, executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        // Codex local-provider authorization is what gates automatic continuation.
        service.update(snapshots: [], enabled: true, authorized: [.claude, .cursor, .gemini, .grok])
        XCTAssertTrue(service.status.contains("authorization"))
        service.update(snapshots: [], enabled: true, authorized: [.codex])
        XCTAssertFalse(service.status.contains("authorization"))
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
        XCTAssertEqual(quota.label(now: Date(timeIntervalSince1970: 1_999_999_999)), "5HR 76% · 1M")
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
        XCTAssertTrue(result.quotaLabel.hasPrefix("5HR 76%"), result.quotaLabel)
        XCTAssertEqual(result.activeCount, 0)
    }

    func testScannerCacheKeepsOtherProvidersBetweenRefreshes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codexRoot = root.appendingPathComponent(".codex/sessions")
        let claudeRoot = root.appendingPathComponent(".claude/projects")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"fixture":true}"#.utf8).write(to: codexRoot.appendingPathComponent("codex.jsonl"))
        try Data(#"{"fixture":true}"#.utf8).write(to: claudeRoot.appendingPathComponent("claude.jsonl"))

        let codex = CountingSessionAdapter(provider: .codex)
        let claude = CountingSessionAdapter(provider: .claude)
        let scanner = LocalActivityScanner(adapters: [codex, claude], home: root, detectProcesses: false)
        _ = await scanner.scan(providers: [.codex, .claude])
        XCTAssertEqual(codex.count, 1)
        XCTAssertEqual(claude.count, 1)

        _ = await scanner.scan(providers: [.codex, .claude])
        XCTAssertEqual(codex.count, 1)
        XCTAssertEqual(claude.count, 1)
    }

    func testScannerParsesOnlyNewestBoundedSessionFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codexRoot = root.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let reference = Date(timeIntervalSince1970: 2_000_000_000)
        for index in 0..<35 {
            let file = codexRoot.appendingPathComponent("session-\(index).jsonl")
            try Data(#"{"fixture":true}"#.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: reference.addingTimeInterval(TimeInterval(index))], ofItemAtPath: file.path)
        }

        let adapter = CountingSessionAdapter(provider: .codex)
        let scanner = LocalActivityScanner(adapters: [adapter], home: root, detectProcesses: false)
        let snapshots = await scanner.scan(providers: [.codex])
        XCTAssertEqual(adapter.count, LocalActivityScanner.recentFileLimit)
        XCTAssertEqual(snapshots.first?.sessions.count, 1, "fixture adapter returns a stable ID that scanner deduplicates")
    }

    func testScannerUsesGrokAdapterForAuthorizedSessionRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessionFolder = root.appendingPathComponent(".grok/sessions/project/fixture-grok-01")
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = fixtureURL(named: "grok-session")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("summary.json"), to: sessionFolder.appendingPathComponent("summary.json"))
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("updates.jsonl"), to: sessionFolder.appendingPathComponent("updates.jsonl"))
        let scanner = LocalActivityScanner(home: root, detectProcesses: false)
        let snapshots = await scanner.scan(providers: [.grok])
        let session = try XCTUnwrap(snapshots.first?.sessions.first)
        XCTAssertEqual(session.provider, .grok)
        XCTAssertEqual(session.title, "Review the provider dashboard")
        XCTAssertEqual(session.mcpServers, ["fixture-files"])
        XCTAssertEqual(session.skills, ["fixture-review"])
    }

    func testMenuBarStatusIconIsVisibleTemplateArtwork() {
        let icon = MenuBarLabelView.statusIcon

        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(icon.tiffRepresentation?.isEmpty ?? true)
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

    func testClaudeAdapterParsesUsageSidechainCapabilitiesAndBlockedState() throws {
        let session = try XCTUnwrap(
            ClaudeSessionAdapter().session(
                from: fixtureFile(named: "claude-session.jsonl"),
                context: .init(now: .now, isProviderRunning: true)
            )
        )

        XCTAssertEqual(session.provider, .claude)
        XCTAssertEqual(session.role, .subagent)
        XCTAssertEqual(session.tokens, 160)
        XCTAssertEqual(session.model, "claude-sonnet-4-5")
        XCTAssertEqual(session.mcpServers, ["figma"])
        XCTAssertEqual(session.skills, ["brand"])
        XCTAssertEqual(session.attention, .needsInput)
        XCTAssertEqual(session.attentionReason, "Claude is waiting for your response")
        XCTAssertEqual(session.project, "Widget")
        XCTAssertFalse(session.isRunning, "Provider process does not establish chat liveness")
    }

    func testCodexAdapterParsesTokenCountMCPAndAttention() throws {
        let session = try XCTUnwrap(
            CodexSessionAdapter().session(
                from: fixtureFile(named: "codex-session.jsonl"),
                context: .init(now: .now, isProviderRunning: false)
            )
        )

        XCTAssertEqual(session.id, "sanitized-codex-session")
        XCTAssertEqual(session.provider, .codex)
        XCTAssertEqual(session.role, .main)
        XCTAssertEqual(session.tokens, 4_321)
        XCTAssertEqual(session.model, "gpt-5.6-codex")
        XCTAssertEqual(session.mcpServers, ["github"])
        XCTAssertEqual(session.attention, .needsInput)
        XCTAssertEqual(session.attentionReason, "Codex is waiting for your response")
        XCTAssertEqual(session.project, "Widget")
        XCTAssertFalse(session.isRunning)
    }

    func testCursorAdapterReportsUnavailableMetadataAsNils() throws {
        let session = try XCTUnwrap(
            CursorSessionAdapter().session(
                from: fixtureFile(named: "Cursor/projects/sanitized-project/agent-transcripts/sanitized-session/sanitized-session.jsonl"),
                context: .init(now: .now, isProviderRunning: false)
            )
        )

        XCTAssertEqual(session.provider, .cursor)
        XCTAssertEqual(session.role, .main)
        XCTAssertEqual(session.title, "Polish the sanitized dashboard")
        XCTAssertEqual(session.detail, "I will refine the layout without exposing private data.")
        XCTAssertEqual(session.project, "Sanitized Project")
        XCTAssertNil(session.tokens)
        XCTAssertNil(session.model)
        XCTAssertTrue(session.mcpServers.isEmpty)
        XCTAssertTrue(session.skills.isEmpty)
        XCTAssertTrue(session.plugins.isEmpty)
        XCTAssertEqual(session.attention, .unknown)
    }

    func testCapabilityInventoryReadsInstalledSourcesAndMarksSessionUsage() throws {
        let fileManager = FileManager.default
        let temporaryHome = fileManager.temporaryDirectory
            .appendingPathComponent("BarBoyInventoryTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.copyItem(at: fixtureURL(named: "inventory-home"), to: temporaryHome)
        defer { try? fileManager.removeItem(at: temporaryHome) }

        let inventory = CapabilityInventoryReader(homeURL: temporaryHome).read()
        let itemIDs = Set(inventory.items.map(\.id))
        XCTAssertTrue(itemIDs.isSuperset(of: [
            "mcpServer:figma", "mcpServer:notion", "mcpServer:legacy",
            "mcpServer:browser", "mcpServer:github", "mcpServer:local-docs",
            "plugin:frontend-design", "plugin:security", "skill:brand", "skill:qa"
        ]))
        XCTAssertEqual(Set(inventory.marketplaces.map(\.name)), ["community", "official"])

        let usedSession = AgentSession(
            id: "inventory-use",
            provider: .claude,
            role: .main,
            title: "Fixture",
            detail: "",
            project: "Widget",
            updatedAt: .now,
            isRunning: false,
            processID: nil,
            tokens: nil,
            mcpServers: ["figma"],
            skills: ["brand", "frontend-design:component"],
            plugins: []
        )
        let marked = inventory.markingUsed(by: [usedSession])
        XCTAssertTrue(try XCTUnwrap(marked.items.first { $0.id == "mcpServer:figma" }).wasUsed(by: .claude))
        XCTAssertTrue(try XCTUnwrap(marked.items.first { $0.id == "skill:brand" }).wasUsed(by: .claude))
        XCTAssertTrue(try XCTUnwrap(marked.items.first { $0.id == "plugin:frontend-design" }).wasUsed(by: .claude))
        XCTAssertFalse(try XCTUnwrap(marked.items.first { $0.id == "mcpServer:local-docs" }).isUsed)
    }

    func testCapabilityInventoryExcludesDisabledProviderInventory() throws {
        let fileManager = FileManager.default
        let temporaryHome = fileManager.temporaryDirectory
            .appendingPathComponent("BarBoyInventoryFilterTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.copyItem(at: fixtureURL(named: "inventory-home"), to: temporaryHome)
        defer { try? fileManager.removeItem(at: temporaryHome) }

        let inventory = CapabilityInventoryReader(homeURL: temporaryHome)
            .read(enabledProviders: [.cursor])
        let itemIDs = Set(inventory.items.map(\.id))
        XCTAssertTrue(itemIDs.contains("mcpServer:local-docs"))
        XCTAssertTrue(itemIDs.contains("skill:qa"), "Shared skills remain available to enabled providers")
        XCTAssertFalse(itemIDs.contains("mcpServer:figma"))
        XCTAssertFalse(itemIDs.contains("mcpServer:github"))
        XCTAssertFalse(itemIDs.contains("plugin:frontend-design"))
        XCTAssertFalse(itemIDs.contains("skill:brand"))
    }

    func testDeskDisplayPayloadCanHideSensitiveTitles() throws {
        let session = AgentSession(
            id: "secret",
            provider: .codex,
            role: .main,
            title: "Confidential acquisition",
            detail: "",
            project: "Stealth",
            updatedAt: .now,
            isRunning: true,
            processID: 7,
            tokens: 900,
            attention: .needsInput,
            attentionReason: "Approve secret launch date",
            model: "private-model",
            mcpServers: ["private-mcp"],
            skills: ["private-skill"],
            plugins: ["private-plugin"]
        )
        let snapshot = ProviderSnapshot(provider: .codex, sessions: [session], activeCount: 1, localTokensToday: 900, updatedAt: .now)
        let redacted = DeskDisplayServer.makeStatusJSON(snapshots: [snapshot], includeTitles: false)
        let visible = DeskDisplayServer.makeStatusJSON(snapshots: [snapshot], includeTitles: true)
        let redactedText = String(decoding: redacted, as: UTF8.self)
        let visibleText = String(decoding: visible, as: UTF8.self)
        XCTAssertFalse(redactedText.contains("Confidential acquisition"))
        XCTAssertFalse(redactedText.contains("Stealth"))
        XCTAssertFalse(redactedText.contains("Approve secret launch date"))
        XCTAssertFalse(redactedText.contains("private-model"))
        XCTAssertFalse(redactedText.contains("private-mcp"))
        XCTAssertFalse(redactedText.contains("private-skill"))
        XCTAssertFalse(redactedText.contains("private-plugin"))
        XCTAssertTrue(visibleText.contains("Confidential acquisition"))
        XCTAssertTrue(visibleText.contains("Stealth"))
        XCTAssertTrue(visibleText.contains("Approve secret launch date"))
        XCTAssertTrue(visibleText.contains("private-model"))
        XCTAssertTrue(visibleText.contains("private-mcp"))
        XCTAssertTrue(visibleText.contains("private-skill"))
        XCTAssertTrue(visibleText.contains("private-plugin"))
    }

    func testDeskDisplayRejectsUnauthorizedAndForeignHostRequests() async throws {
        let suiteName = "BarBoyDeskDisplaySecurityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let server = DeskDisplayServer(defaults: defaults)
        defer {
            server.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }

        server.start()
        for _ in 0..<100 where server.state != .ready {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard server.state == .ready else {
            throw XCTSkip("Desk Display listener could not start: \(server.errorMessage ?? server.state.label)")
        }

        let unauthorized = try rawHTTPResponse(
            port: server.port,
            request: "GET /health HTTP/1.1\r\nHost: 127.0.0.1:\(server.port)\r\nConnection: close\r\n\r\n"
        )
        XCTAssertTrue(unauthorized.hasPrefix("HTTP/1.1 401 Unauthorized"))

        let foreignHost = try rawHTTPResponse(
            port: server.port,
            request: "GET /health HTTP/1.1\r\nHost: attacker.example:\(server.port)\r\nAuthorization: Bearer \(server.token)\r\nConnection: close\r\n\r\n"
        )
        XCTAssertTrue(foreignHost.hasPrefix("HTTP/1.1 421 Misdirected Request"))

        let icon = try rawHTTPResponse(
            port: server.port,
            request: "GET /provider-icon/codex HTTP/1.1\r\nHost: 127.0.0.1:\(server.port)\r\nAuthorization: Bearer \(server.token)\r\nConnection: close\r\n\r\n"
        )
        XCTAssertTrue(icon.hasPrefix("HTTP/1.1 200 OK"))
        XCTAssertTrue(icon.contains("Content-Type: image/png"))
    }

    func testRelayPayloadKeepsEveryRunningSession() throws {
        let sessions = (0..<17).map { index in
            AgentSession(
                id: "session-\(index)",
                provider: .codex,
                role: .main,
                title: "Session \(index)",
                detail: "",
                project: "Fixture",
                updatedAt: .now,
                isRunning: index < 14,
                processID: index,
                tokens: nil
            )
        }
        let prioritized = LocalActivityScanner.prioritizedSessions(sessions, recentHistoryLimit: 2)
        XCTAssertEqual(prioritized.filter(\.isRunning).count, 14)
        XCTAssertEqual(prioritized.count, 16)

        let snapshot = ProviderSnapshot(
            provider: .codex,
            sessions: prioritized,
            activeCount: 14,
            localTokensToday: 0,
            updatedAt: .now
        )
        let data = DeskDisplayServer.makeStatusJSON(snapshots: [snapshot], includeTitles: true)
        let decoded = try JSONDecoder().decode(RelayStatus.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 16)
    }

    func testLiveProcessesWithMatchingTitlesDoNotCollapse() {
        let shared = (title: "Same command", project: "Fixture")
        let sessions = [
            AgentSession(id: "live-1", provider: .codex, role: .main, title: shared.title, detail: "", project: shared.project, updatedAt: .now, isRunning: true, processID: 101, tokens: nil),
            AgentSession(id: "live-2", provider: .codex, role: .main, title: shared.title, detail: "", project: shared.project, updatedAt: .now, isRunning: true, processID: 102, tokens: nil),
            AgentSession(id: "old-1", provider: .codex, role: .main, title: shared.title, detail: "", project: shared.project, updatedAt: .now, isRunning: false, processID: nil, tokens: nil),
            AgentSession(id: "old-2", provider: .codex, role: .main, title: shared.title, detail: "", project: shared.project, updatedAt: .now, isRunning: false, processID: nil, tokens: nil)
        ]

        let result = LocalActivityScanner.deduplicatedSessions(sessions)
        XCTAssertEqual(result.filter(\.isRunning).count, 2)
        XCTAssertEqual(result.count, 4)
    }

    func testDeskDisplayFallsBackWhenPreferredPortIsOccupied() async throws {
        let firstSuiteName = "BarBoyDeskDisplayPortOne-\(UUID().uuidString)"
        let secondSuiteName = "BarBoyDeskDisplayPortTwo-\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: firstSuiteName))
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: secondSuiteName))
        let first = DeskDisplayServer(defaults: firstDefaults)
        let second = DeskDisplayServer(defaults: secondDefaults)
        defer {
            first.stop()
            second.stop()
            firstDefaults.removePersistentDomain(forName: firstSuiteName)
            secondDefaults.removePersistentDomain(forName: secondSuiteName)
        }

        first.start()
        try await waitUntilReady(first)
        guard first.state == .ready else {
            throw XCTSkip("First Desk Display listener could not start: \(first.errorMessage ?? first.state.label)")
        }

        second.start()
        try await waitUntilReady(second)
        guard second.state == .ready else {
            throw XCTSkip("Second Desk Display listener could not start: \(second.errorMessage ?? second.state.label)")
        }

        XCTAssertNotEqual(second.port, 7_377)
        XCTAssertNotEqual(second.port, first.port)
    }

    func testDeskDisplayHTMLIsSmallScreenFirst() {
        let html = DeskDisplayServer.dashboardHTML(token: "abc123")
        XCTAssertTrue(html.contains("width=device-width"))
        XCTAssertTrue(html.contains("YOUR RETURN QUEUE"))
        XCTAssertFalse(html.contains("abc123"), "Pairing credentials must not be embedded in display HTML")
        XCTAssertTrue(html.contains("overflow:hidden"))
        XCTAssertTrue(html.contains("NEED"))
        XCTAssertTrue(html.contains("/provider-icon/"))
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
        let session = AgentSession(id: "1", provider: .claude, role: .subagent, title: "Test", detail: "", project: "MOMO", updatedAt: .distantPast, isRunning: true, processID: 123, tokens: nil)
        XCTAssertEqual(session.ageLabel, "LIVE")
    }

    func testRealCapabilityInventoryWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["BAR_BOY_REAL_DATA_CHECK"] == "1" else {
            throw XCTSkip("Set BAR_BOY_REAL_DATA_CHECK=1 as an xcodebuild setting to smoke-test local metadata.")
        }

        let inventory = CapabilityInventoryReader().read()
        let mcpCount = inventory.items(of: .mcpServer).count
        let pluginCount = inventory.items(of: .plugin).count
        let skillCount = inventory.items(of: .skill).count
        print("BAR_BOY_REAL_DATA_COUNTS mcp=\(mcpCount) plugins=\(pluginCount) skills=\(skillCount) marketplaces=\(inventory.marketplaces.count)")
        XCTAssertGreaterThan(mcpCount + pluginCount + skillCount, 0)

        let scanner = LocalActivityScanner(
            adapters: [ClaudeSessionAdapter(), CodexSessionAdapter(), CursorSessionAdapter()]
        )
        var snapshots: [ProviderSnapshot] = []
        for provider in [AIProvider.codex, .claude, .cursor] {
            let startedAt = Date()
            print("BAR_BOY_REAL_SESSION_SCAN provider=\(provider.rawValue) state=started")
            let providerSnapshots = await scanner.scan(enabledProviders: [provider])
            let duration = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            print("BAR_BOY_REAL_SESSION_SCAN provider=\(provider.rawValue) state=finished seconds=\(duration)")
            snapshots.append(contentsOf: providerSnapshots)
        }
        let sessionCount = snapshots.reduce(0) { $0 + $1.sessions.count }
        let tokenBearingSessionCount = snapshots.flatMap(\.sessions).compactMap(\.tokens).count
        let capabilityBearingSessionCount = snapshots.flatMap(\.sessions).filter {
            !$0.mcpServers.isEmpty || !$0.skills.isEmpty || !$0.plugins.isEmpty
        }.count
        print("BAR_BOY_REAL_SESSION_COUNTS providers=\(snapshots.count) sessions=\(sessionCount) tokenBearing=\(tokenBearingSessionCount) capabilityBearing=\(capabilityBearingSessionCount)")
        XCTAssertEqual(Set(snapshots.map(\.provider)), [.codex, .claude, .cursor])
        XCTAssertGreaterThan(sessionCount, 0)
    }

    func testRenderDashboardSnapshotsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["BAR_BOY_RENDER_SNAPSHOTS"] == "1" else {
            throw XCTSkip("Set BAR_BOY_RENDER_SNAPSHOTS=1 as an xcodebuild setting to write snapshots to /tmp.")
        }

        let now = Date()
        var sessions = [
            AgentSession(id: "codex-main", provider: .codex, role: .main, title: "Building the BAR BOY menu app", detail: "Implementing the local activity dashboard", project: "Bar-Boy", updatedAt: now, isRunning: true, processID: nil, tokens: 12_400, model: "GPT-5.6", mcpServers: ["github", "web"], skills: ["frontend-design"], plugins: []),
            AgentSession(id: "codex-sub", provider: .codex, role: .subagent, title: "Verifying provider adapters", detail: "Checking local session discovery", project: "Bar-Boy", updatedAt: now, isRunning: true, processID: nil, tokens: 4_800, attention: .failed, model: "GPT-5.6", mcpServers: [], skills: ["qa"], plugins: []),
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
        snapshots[0].recordedQuota = RecordedQuotaWindow(percent: 76, minutes: 300, resetsAt: now.addingTimeInterval(3600), observedAt: now)
        snapshots[0].recordedQuotas = [snapshots[0].recordedQuota!, RecordedQuotaWindow(percent: 32, minutes: 10080, resetsAt: now.addingTimeInterval(86400), observedAt: now)]
        let capabilityInventory = CapabilityInventory(
            items: [
                InstalledCapability(name: "frontend-design", kind: .skill, owners: [.shared], marketplaces: [], usedBy: [.codex]),
                InstalledCapability(name: "brand", kind: .skill, owners: [.provider(.claude)], marketplaces: [], usedBy: [.claude]),
                InstalledCapability(name: "qa", kind: .skill, owners: [.shared], marketplaces: [], usedBy: []),
                InstalledCapability(name: "github", kind: .mcpServer, owners: [.provider(.codex)], marketplaces: [], usedBy: [.codex]),
                InstalledCapability(name: "figma", kind: .mcpServer, owners: [.provider(.claude)], marketplaces: [], usedBy: [.claude]),
                InstalledCapability(name: "Canva", kind: .plugin, owners: [.provider(.claude)], marketplaces: ["official"], usedBy: [.claude])
            ],
            marketplaces: [CapabilityMarketplace(name: "official", owners: [.provider(.claude)])]
        )
        let monitor = ActivityMonitor(
            autoRefresh: false,
            snapshots: snapshots,
            capabilityInventory: capabilityInventory
        )
        let suite = UserDefaults(suiteName: "BarBoySnapshotTests")!
        suite.removePersistentDomain(forName: "BarBoySnapshotTests")
        let preferences = PreferencesStore(defaults: suite)
        AIProvider.allCases.forEach { preferences.setEnabled(true, for: $0) }
        let deskDisplay = DeskDisplayServer(defaults: suite)
        try render(preferredScheme: .dark, name: "barboy-dark", monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try render(preferredScheme: .light, name: "barboy-light", monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try render(preferredScheme: .dark, name: "barboy-agents-dark", initialTab: .agents, monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try render(preferredScheme: .dark, name: "barboy-tools-dark", initialTab: .tools, monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        let overview = DashboardView(refreshOnAppear: false, showsOverview: true)
            .environmentObject(monitor).environmentObject(preferences).environmentObject(deskDisplay)
            .preferredColorScheme(.dark)
        let overviewHost = NSHostingView(rootView: overview)
        overviewHost.frame = NSRect(x: 0, y: 0, width: 860, height: 570)
        overviewHost.appearance = NSAppearance(named: .darkAqua)
        overviewHost.layoutSubtreeIfNeeded()
        let overviewBitmap = try XCTUnwrap(overviewHost.bitmapImageRepForCachingDisplay(in: overviewHost.bounds))
        overviewHost.cacheDisplay(in: overviewHost.bounds, to: overviewBitmap)
        try XCTUnwrap(overviewBitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/momo-overview.png"))
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
            .frame(width: 430, height: 220)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 220)
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

    private func fixtureFile(named name: String) throws -> ProviderSessionFile {
        let url = fixtureURL(named: name)
        let existingURL = try XCTUnwrap(
            FileManager.default.fileExists(atPath: url.path) ? url : nil,
            "Missing adapter fixture: \(name)"
        )
        return ProviderSessionFile(url: existingURL, modifiedAt: Date(timeIntervalSince1970: 1_789_056_000), index: 0)
    }

    private func fixtureURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func rawHTTPResponse(port: UInt16, request: String) throws -> String {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connectionResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectionResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED) }

        let sent = request.withCString { bytes in
            Darwin.send(descriptor, bytes, strlen(bytes), 0)
        }
        guard sent == request.utf8.count else { throw POSIXError(.EIO) }
        Darwin.shutdown(descriptor, SHUT_WR)

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            response.append(buffer, count: count)
        }
        return String(decoding: response, as: UTF8.self)
    }

    private func waitUntilReady(_ server: DeskDisplayServer) async throws {
        for _ in 0..<100 where server.state != .ready {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
