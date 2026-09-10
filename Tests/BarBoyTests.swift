import AppKit
import SwiftUI
import XCTest
@testable import BAR_BOY

@MainActor
final class BarBoyTests: XCTestCase {
    func testProviderCoverage() {
        XCTAssertEqual(AIProvider.allCases.map(\.name), ["Codex", "Claude", "Gemini"])
        XCTAssertTrue(AIProvider.allCases.allSatisfy { !$0.sessionRoots.isEmpty })
    }

    func testSnapshotUsageFormatting() {
        let snapshot = ProviderSnapshot(provider: .codex, sessions: [], activeCount: 0, localTokensToday: 12_400, updatedAt: .now)
        XCTAssertEqual(snapshot.usageText, "12.4K")
    }

    func testProcessMatchingAvoidsProjectPathFalsePositives() {
        XCTAssertTrue(AIProvider.codex.matchesProcessCommand("/opt/homebrew/bin/codex --resume"))
        XCTAssertTrue(AIProvider.claude.matchesProcessCommand("/usr/local/bin/claude --continue"))
        XCTAssertFalse(AIProvider.codex.matchesProcessCommand("/usr/bin/xcodebuild -project /Users/me/Documents/Codex/App.xcodeproj"))
        XCTAssertFalse(AIProvider.codex.matchesProcessCommand("/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper"))
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
            AgentSession(id: "claude-main", provider: .claude, role: .main, title: "Reviewing onboarding copy", detail: "Recent local session", project: "Momo", updatedAt: now.addingTimeInterval(-420), isRunning: false, processID: nil, tokens: 31_200)
        ]
        let snapshots = [
            ProviderSnapshot(provider: .codex, sessions: Array(sessions.prefix(2)), activeCount: 2, localTokensToday: 17_200, updatedAt: now),
            ProviderSnapshot(provider: .claude, sessions: [sessions[2]], activeCount: 0, localTokensToday: 31_200, updatedAt: now),
            ProviderSnapshot(provider: .gemini, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: now)
        ]
        let monitor = ActivityMonitor(autoRefresh: false, snapshots: snapshots)
        let suite = UserDefaults(suiteName: "BarBoySnapshotTests")!
        suite.removePersistentDomain(forName: "BarBoySnapshotTests")
        let preferences = PreferencesStore(defaults: suite)
        try render(preferredScheme: .dark, name: "barboy-dark", monitor: monitor, preferences: preferences)
        try render(preferredScheme: .light, name: "barboy-light", monitor: monitor, preferences: preferences)
    }

    private func render(preferredScheme: ColorScheme, name: String, monitor: ActivityMonitor, preferences: PreferencesStore) throws {
        let view = DashboardView(refreshOnAppear: false)
            .environmentObject(monitor)
            .environmentObject(preferences)
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
