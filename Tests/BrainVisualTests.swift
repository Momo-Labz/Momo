import XCTest
import SwiftUI
import AppKit
@testable import BAR_BOY

final class BrainVisualTests: XCTestCase {
    func testBoundedLayoutIsDeterministicAndContainsEveryNode() async {
        let engine = VaultLayoutEngine()
        let nodes = (0..<200).map { VaultVisualNode(id: "note-\($0)", title: "Project \($0)") }
        let edges = (1..<200).map { VaultVisualEdge(from: "note-\($0 - 1)", to: "note-\($0)") }
        let start = Date()
        let first = await engine.layout(nodes: nodes, edges: edges)
        let seconds = Date().timeIntervalSince(start)
        let second = await engine.layout(nodes: nodes, edges: edges)
        XCTAssertEqual(first.positions, second.positions)
        XCTAssertEqual(first.positions.count, 200)
        XCTAssertTrue(first.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.x >= 35 && $0.x <= 485 && $0.y >= 35 && $0.y <= 340 })
        print("MOMO_GRAPH_PROFILE nodes=200 seconds=\(seconds)")
    }

    func testEmptyGraphAndDanglingLinksDoNotCrash() async {
        let result = await VaultLayoutEngine().layout(nodes: [], edges: [VaultVisualEdge(from: "missing", to: "deleted")])
        XCTAssertTrue(result.positions.isEmpty)
    }

    @MainActor
    func testAttachedStatePreservesDraftAcrossContract() {
        let surface = MomoSurface.shared
        let context = QuickAskContext.shared
        context.newChat()
        context.provider = .claude
        let original = context.draft
        defer { context.draft = original; surface.expanded = false; surface.attentionOnly = false; surface.page = .home }
        context.draft = "Review the note links"
        surface.selectedProvider = .claude
        surface.expanded = true
        surface.expanded = false
        surface.expanded = true
        XCTAssertEqual(context.draft, "Review the note links")
        XCTAssertEqual(surface.selectedProvider, .claude)
    }

    @MainActor
    func testRenderNewBrainAndAttachedStates() async throws {
        guard ProcessInfo.processInfo.environment["BAR_BOY_RENDER_SNAPSHOTS"] == "1" else { throw XCTSkip("Enable snapshot rendering") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("momo-visual-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = [
            "MOMO.md": "# MOMO\n[[Local inference]] [[Interface review]] [[Release checklist]]\n#project\n",
            "Local inference.md": "# Local inference\n[[MOMO]] [[Memory budget]]\nKeep inference on demand.\n",
            "Interface review.md": "# Interface review\n[[MOMO]] [[Accessibility]]\nReview attached expansion.\n",
            "Release checklist.md": "# Release checklist\n[[MOMO]] [[Accessibility]] [[Memory budget]]\n",
            "Memory budget.md": "# Memory budget\n[[Local inference]]\n",
            "Accessibility.md": "# Accessibility\n[[Interface review]]\n"
        ]
        for (name, body) in contents { try body.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        let vault = VaultStore(autoRestore: false, persistBookmarks: false)
        try await vault.connect(root)
        let nodes = vault.notes.map { VaultVisualNode(id: $0.id, title: $0.title) }
        let edges = vault.notes.flatMap { note in note.links.map { VaultVisualEdge(from: note.id, to: $0) } }
        let graph = await VaultLayoutEngine().layout(nodes: nodes, edges: edges)
        let brain = BrainWorkspaceView(vault: vault, refreshOnAppear: false, initialGraph: graph, initialSelection: "MOMO.md")
        try capture(brain, size: CGSize(width: 760, height: 600), name: "momo-brain-current")

        let now = Date()
        let sessions = [AgentSession(id: "visual-chat", provider: .codex, role: .main, title: "Review MOMO navigation", detail: "Approval needed before updating the release", project: "MOMO", updatedAt: now, isRunning: false, processID: nil, tokens: 24000, attention: .needsInput, attentionReason: "Review the attached menu screenshots", model: "Codex", mcpServers: [], skills: [], plugins: [])]
        var snapshot = ProviderSnapshot(provider: .codex, sessions: sessions, activeCount: 0, localTokensToday: 24000, updatedAt: now)
        snapshot.recordedQuota = RecordedQuotaWindow(percent: 40, minutes: 300, resetsAt: now.addingTimeInterval(3900), observedAt: now)
        let monitor = ActivityMonitor(autoRefresh: false, snapshots: [snapshot])
        let defaults = UserDefaults(suiteName: "momo.visual." + UUID().uuidString)!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.setEnabled(true, for: .codex)
        let desk = DeskDisplayServer(defaults: defaults)
        let surface = MomoSurface.shared
        surface.selectedProvider = .codex; surface.page = .home; surface.attentionOnly = false; surface.expanded = false
        try capture(CompactDashboardView(refreshOnAppear: false, animateMomo: false).environmentObject(monitor).environmentObject(preferences), size: CompactDashboardView.canvasSize, name: "momo-compact-current")
        surface.expanded = true
        QuickAskContext.shared.select(sessions[0])
        try capture(DashboardView(refreshOnAppear: false).environmentObject(monitor).environmentObject(preferences).environmentObject(desk), size: CGSize(width: 760, height: 760), name: "momo-expanded-current")
        surface.attentionOnly = true
        try capture(DashboardView(refreshOnAppear: false).environmentObject(monitor).environmentObject(preferences).environmentObject(desk), size: CGSize(width: 760, height: 760), name: "momo-attention-current")
        surface.attentionOnly = false
        for page in [DashboardTab.agents, .tools, .network] {
            surface.page = page
            surface.expanded = false
            try capture(CompactDashboardView(refreshOnAppear: false, animateMomo: false).environmentObject(monitor).environmentObject(preferences), size: CompactDashboardView.canvasSize, name: "momo-compact-\(page.rawValue)")
            surface.expanded = true
            try capture(DashboardView(refreshOnAppear: false).environmentObject(monitor).environmentObject(preferences).environmentObject(desk), size: CGSize(width: 760, height: 760), name: "momo-expanded-\(page.rawValue)")
        }
        surface.page = .home
        surface.expanded = false; surface.attentionOnly = false
    }

    @MainActor
    private func capture<V: View>(_ view: V, size: CGSize, name: String) throws {
        let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }
}
