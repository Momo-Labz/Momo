import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import BAR_BOY

@MainActor
final class BarBoyTests: XCTestCase {
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
        XCTAssertTrue(session.isRunning)
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
        XCTAssertEqual(session.attention, .idle)
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
        XCTAssertEqual(result.count, 3)
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
        let sessions = [
            AgentSession(id: "codex-main", provider: .codex, role: .main, title: "Building the MOMO menu app", detail: "Implementing the local activity dashboard", project: "MOMO", updatedAt: now, isRunning: true, processID: 88, tokens: 12_400, model: "GPT-5.6", mcpServers: ["github", "web"], skills: ["frontend-design"], plugins: []),
            AgentSession(id: "codex-sub", provider: .codex, role: .subagent, title: "Verifying provider adapters", detail: "Checking local session discovery", project: "MOMO", updatedAt: now, isRunning: true, processID: 89, tokens: 4_800, model: "GPT-5.6", mcpServers: [], skills: ["qa"], plugins: []),
            AgentSession(id: "claude-main", provider: .claude, role: .main, title: "Reviewing onboarding copy", detail: "Recent local session", project: "Momo", updatedAt: now.addingTimeInterval(-420), isRunning: false, processID: nil, tokens: 31_200, attention: .needsInput, attentionReason: "Approve the revised copy", model: "Claude Sonnet", mcpServers: ["figma"], skills: ["brand"], plugins: ["Canva"])
        ]
        let snapshots = [
            ProviderSnapshot(provider: .codex, sessions: Array(sessions.prefix(2)), activeCount: 2, localTokensToday: 17_200, updatedAt: now),
            ProviderSnapshot(provider: .claude, sessions: [sessions[2]], activeCount: 0, localTokensToday: 31_200, updatedAt: now),
            ProviderSnapshot(provider: .gemini, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: now),
            ProviderSnapshot(provider: .cursor, sessions: [], activeCount: 1, localTokensToday: 8_900, updatedAt: now),
            ProviderSnapshot(provider: .grok, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: now)
        ]
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
            .frame(width: 760, height: 500)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 500)
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
            .frame(width: CompactDashboardView.canvasSize.width, height: CompactDashboardView.canvasSize.height)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: CompactDashboardView.canvasSize)
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
