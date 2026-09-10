import AppKit
import SwiftUI
import XCTest
@testable import BAR_BOY

@MainActor
final class BarBoyTests: XCTestCase {
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
        XCTAssertTrue(html.contains("WHAT THEY ARE WORKING ON"))
        XCTAssertTrue(html.contains("abc123"))
        XCTAssertTrue(html.contains("overflow:hidden"))
        XCTAssertTrue(html.contains("NEED"))
    }

    func testRunningSessionWinsAgeLabel() {
        let session = AgentSession(id: "1", provider: .claude, role: .subagent, title: "Test", detail: "", project: "BAR BOY", updatedAt: .distantPast, isRunning: true, processID: 123, tokens: nil)
        XCTAssertEqual(session.ageLabel, "LIVE")
    }

    func testRenderDashboardSnapshotsWhenRequested() throws {
        let now = Date()
        let sessions = [
            AgentSession(id: "codex-main", provider: .codex, role: .main, title: "Building the BAR BOY menu app", detail: "Implementing the local activity dashboard", project: "Bar-Boy", updatedAt: now, isRunning: true, processID: 88, tokens: 12_400),
            AgentSession(id: "codex-sub", provider: .codex, role: .subagent, title: "Verifying provider adapters", detail: "Checking local session discovery", project: "Bar-Boy", updatedAt: now, isRunning: true, processID: 89, tokens: 4_800),
            AgentSession(id: "claude-main", provider: .claude, role: .main, title: "Reviewing onboarding copy", detail: "Recent local session", project: "Momo", updatedAt: now.addingTimeInterval(-420), isRunning: false, processID: nil, tokens: 31_200, attention: .needsInput, attentionReason: "Approve the revised copy")
        ]
        let snapshots = [
            ProviderSnapshot(provider: .codex, sessions: Array(sessions.prefix(2)), activeCount: 2, localTokensToday: 17_200, updatedAt: now),
            ProviderSnapshot(provider: .claude, sessions: [sessions[2]], activeCount: 0, localTokensToday: 31_200, updatedAt: now),
            ProviderSnapshot(provider: .gemini, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: now),
            ProviderSnapshot(provider: .cursor, sessions: [], activeCount: 1, localTokensToday: 8_900, updatedAt: now),
            ProviderSnapshot(provider: .grok, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: now)
        ]
        let monitor = ActivityMonitor(autoRefresh: false, snapshots: snapshots)
        let suite = UserDefaults(suiteName: "BarBoySnapshotTests")!
        suite.removePersistentDomain(forName: "BarBoySnapshotTests")
        let preferences = PreferencesStore(defaults: suite)
        let deskDisplay = DeskDisplayServer(defaults: suite)
        try render(preferredScheme: .dark, name: "barboy-dark", monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
        try render(preferredScheme: .light, name: "barboy-light", monitor: monitor, preferences: preferences, deskDisplay: deskDisplay)
    }

    private func render(preferredScheme: ColorScheme, name: String, monitor: ActivityMonitor, preferences: PreferencesStore, deskDisplay: DeskDisplayServer) throws {
        let view = DashboardView(refreshOnAppear: false)
            .environmentObject(monitor)
            .environmentObject(preferences)
            .environmentObject(deskDisplay)
            .preferredColorScheme(preferredScheme)
            .frame(width: 420, height: 650)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 650)
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
}
