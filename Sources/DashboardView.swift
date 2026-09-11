import AppKit
import SwiftUI

struct DashboardView: View {
    var refreshOnAppear = true
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var deskDisplay: DeskDisplayServer
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: DashboardTab = .home
    @State private var providerFilter: AIProvider?
    @State private var inspectedSession: AgentSession?
    @State private var inventoryScope: CapabilityInventoryScope?

    init(refreshOnAppear: Bool = true, initialTab: DashboardTab = .home) {
        self.refreshOnAppear = refreshOnAppear
        _tab = State(initialValue: initialTab)
    }

    private var enabledSnapshots: [ProviderSnapshot] {
        monitor.snapshots.filter {
            preferences.isEnabled($0.provider)
                && (!preferences.hideIdleProviders || $0.activeCount > 0 || !$0.sessions.isEmpty)
        }
    }

    private var allSessions: [AgentSession] {
        enabledSnapshots.flatMap(\.sessions).sorted {
            if $0.attention.isUrgent != $1.attention.isUrgent { return $0.attention.isUrgent }
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private var visibleSessions: [AgentSession] {
        allSessions.filter { providerFilter == nil || $0.provider == providerFilter }
    }

    private var urgentSessions: [AgentSession] { allSessions.filter { $0.attention.isUrgent } }
    private var urgentCount: Int { urgentSessions.count }
    private var liveCount: Int { allSessions.filter(\.isRunning).count }
    private var skillTiles: [CapabilityTile] { capabilityTiles(kind: .skill) }
    private var integrationTiles: [CapabilityTile] {
        capabilityTiles(kind: .mcpServer) + capabilityTiles(kind: .plugin)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            page
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            footer
        }
        .frame(minWidth: 760, minHeight: 500)
        .background(BarBoyStyle.panel)
        .task { if refreshOnAppear { monitor.refresh() } }
        .sheet(item: $inspectedSession) { SessionInspectorView(session: $0) }
        .sheet(item: $inventoryScope) { CapabilityInventoryView(initialScope: $0) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PixelBarBoyMark(size: 32, tile: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("MOMO LABZ").font(BarBoyStyle.microLabel).tracking(1.35).foregroundStyle(.secondary)
                Text("BAR BOY").font(BarBoyStyle.display).tracking(0.9)
            }
            HStack(spacing: 4) {
                ForEach(DashboardTab.allCases) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : BarBoyStyle.pageAnimation) { tab = item }
                    } label: {
                        Label(item.label, systemImage: item.symbol)
                            .font(BarBoyStyle.navLabel)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .foregroundStyle(tab == item ? BarBoyStyle.inverseInk : Color.primary)
                            .background(tab == item ? Color.primary : Color.clear, in: Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(3)
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            .padding(.leading, 12)
            Spacer()
            if urgentCount > 0 {
                HStack(spacing: 5) {
                    Rectangle().fill(BarBoyStyle.coral).frame(width: 5, height: 13)
                    Text("\(urgentCount) NEED\(urgentCount == 1 ? "S" : "") YOU")
                }
                .font(BarBoyStyle.alertLabel).foregroundStyle(BarBoyStyle.coral)
                .accessibilityLabel("\(urgentCount) sessions need you")
            } else {
                Text("\(liveCount) LIVE").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }
            Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .barBoyIconButton().help("Refresh local activity")
            Button { openSettings() } label: { Image(systemName: "gearshape.fill") }
                .barBoyIconButton().help("Settings")
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
    }

    @ViewBuilder private var page: some View {
        Group {
            switch tab {
            case .home: homePage
            case .agents: agentsPage
            case .tools: toolsPage
            }
        }
        .id(tab)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: reduceMotion ? 0 : 5)),
            removal: .opacity
        ))
    }

    private var homePage: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 15) {
                returnQueue
                skillSection
                integrationsSection
                if preferences.deskDisplayEnabled { deskDisplayStrip }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Rectangle().fill(BarBoyStyle.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 14) {
                shortcutsPanel
                primaryAction
                liveSummary
            }
            .frame(width: 222, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var returnQueue: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "YOUR TURN", note: urgentCount == 0 ? "FLOW CLEAR" : "\(urgentCount) BLOCKING")
            VStack(spacing: 0) {
                if urgentSessions.isEmpty {
                    HStack(spacing: 11) {
                        Rectangle().fill(Color.primary).frame(width: 6, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MOMO CHECKED. NO ONE IS WAITING.").font(BarBoyStyle.rowTitle)
                            Text("The queue interrupts only when an agent needs you.")
                                .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(11)
                } else {
                    ForEach(Array(urgentSessions.prefix(2).enumerated()), id: \.element.id) { index, session in
                        Button { inspectedSession = session } label: { SessionRow(session: session) }
                            .buttonStyle(.plain)
                        if index < min(urgentSessions.count, 2) - 1 {
                            Rectangle().fill(BarBoyStyle.coral.opacity(0.36)).frame(height: 1).padding(.leading, 45)
                        }
                    }
                }
            }
            .background(urgentSessions.isEmpty ? BarBoyStyle.surface : BarBoyStyle.coral.opacity(0.08))
            .overlay(Rectangle().stroke(urgentSessions.isEmpty ? BarBoyStyle.hairline : BarBoyStyle.coral, lineWidth: urgentSessions.isEmpty ? 1 : 1.5))
        }
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "SKILLS",
                note: skillTiles.isEmpty ? "NONE INSTALLED" : "\(skillTiles.filter(\.isUsed).count) USED / \(skillTiles.count) INSTALLED"
            )
            HStack(spacing: 8) {
                if skillTiles.isEmpty {
                    EmptyCapabilityRow(text: "No installed skills found in enabled providers.")
                } else {
                    ForEach(skillTiles.prefix(3)) { CapabilitySquare(tile: $0) }
                    if skillTiles.count > 3 { MoreCapabilitySquare(count: skillTiles.count - 3) }
                }
                InventoryButtonSquare(label: "SKILLS") { inventoryScope = .skills }
                Spacer(minLength: 0)
            }
        }
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "ACTIVE INTEGRATIONS", note: "MCP + PLUGINS")
            HStack(spacing: 7) {
                if integrationTiles.isEmpty {
                    Text("NONE INSTALLED FOR ENABLED PROVIDERS").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                } else {
                    ForEach(integrationTiles.prefix(5)) { IntegrationMark(tile: $0) }
                    if integrationTiles.count > 5 {
                        Text("+\(integrationTiles.count - 5)")
                            .font(BarBoyStyle.microLabel).frame(width: 30, height: 30)
                            .background(BarBoyStyle.raised)
                            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                    }
                }
                Button { inventoryScope = .integrations } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(BarBoyStyle.raised)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .help("Open installed integrations")
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        }
    }

    private var shortcutsPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("SHORTCUTS", systemImage: "command").font(BarBoyStyle.sectionLabel).foregroundStyle(.secondary)
            ShortcutRow(label: "Quick Ask", keys: ["⌃", "⌥", "SPACE"])
            ShortcutRow(label: "Talk", keys: ["NEXT"], disabled: true)
            ShortcutRow(label: "Dictate", keys: ["NEXT"], disabled: true)
            ShortcutRow(label: "Hands-free", keys: ["NEXT"], disabled: true)
        }
        .padding(12)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private var primaryAction: some View {
        Button(action: openNext) {
            HStack {
                Text(urgentSessions.isEmpty ? "ASK AI" : "OPEN RETURN")
                Spacer()
                Image(systemName: urgentSessions.isEmpty ? "arrow.up.right" : "arrow.right")
            }
            .font(BarBoyStyle.actionLabel)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .foregroundStyle(BarBoyStyle.inverseInk)
            .background(Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(BarBoyPressButtonStyle(reduceMotion: reduceMotion))
        .help(urgentSessions.isEmpty ? "Open Quick Ask" : "Inspect the next blocked session")
    }

    private var liveSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            SummaryRow(label: "LIVE NOW", value: liveCount)
            SummaryRow(label: "MODELS SEEN", value: enabledSnapshots.count)
            SummaryRow(label: "CAPABILITIES", value: skillTiles.count + integrationTiles.count)
        }
        .padding(12)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private var agentsPage: some View {
        HStack(alignment: .top, spacing: 16) {
            usageTable.frame(width: 328)
            Rectangle().fill(BarBoyStyle.hairline).frame(width: 1)
            activitySection.frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var toolsPage: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "SKILL CATALOG", note: "INSTALLED / USED MARKED")
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], alignment: .leading, spacing: 8) {
                        if skillTiles.isEmpty { EmptyCapabilityRow(text: "No installed skills found.") }
                        else { ForEach(skillTiles) { CapabilitySquare(tile: $0) } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Rectangle().fill(BarBoyStyle.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "INTEGRATIONS", note: "MCP + PLUGINS")
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(integrationTiles) { tile in
                            HStack(spacing: 10) {
                                IntegrationMark(tile: tile)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tile.name.uppercased()).font(BarBoyStyle.rowTitle)
                                    Text(tile.provenanceLabel)
                                        .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if tile.isUsed { Text("USED").font(BarBoyStyle.microLabel).padding(4).overlay(Rectangle().stroke(BarBoyStyle.hairline)) }
                            }
                        }
                        if integrationTiles.isEmpty { EmptyCapabilityRow(text: "No installed integrations found.") }
                    }
                }
                Button("MANAGE PROVIDER ACCESS") { openSettings() }
                    .barBoyButton()
            }
            .frame(width: 310, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var usageTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "MODELS", note: "LOCAL + LINKED")
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("PROVIDER").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SHORT").frame(width: 40, alignment: .trailing)
                    Text("WEEK").frame(width: 40, alignment: .trailing)
                    Text("SESS").frame(width: 34, alignment: .trailing)
                }
                .font(BarBoyStyle.tableHeader).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 7)
                Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
                ForEach(Array(enabledSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    ProviderUsageRow(snapshot: snapshot, selected: providerFilter == snapshot.provider) {
                        providerFilter = providerFilter == snapshot.provider ? nil : snapshot.provider
                    }
                    if index < enabledSnapshots.count - 1 {
                        Rectangle().fill(BarBoyStyle.hairline.opacity(0.7)).frame(height: 1).padding(.leading, 41)
                    }
                }
            }
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "AGENTS", note: providerFilter?.name.uppercased() ?? "\(liveCount) LIVE")
            ScrollView {
                VStack(spacing: 0) {
                    if visibleSessions.isEmpty {
                        HStack(spacing: 12) {
                            PixelBarBoyMark(size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MOMO CHECKED. QUIET RIGHT NOW.").font(BarBoyStyle.rowTitle)
                                Text("New local sessions appear here.").font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(13)
                    } else {
                        ForEach(Array(visibleSessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                            Button { inspectedSession = session } label: { SessionRow(session: session) }
                                .buttonStyle(.plain)
                            if index < min(visibleSessions.count, 6) - 1 {
                                Rectangle().fill(session.attention.isUrgent ? BarBoyStyle.coral.opacity(0.35) : BarBoyStyle.hairline.opacity(0.7))
                                    .frame(height: 1).padding(.leading, 45)
                            }
                        }
                    }
                }
            }
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        }
    }

    private var deskDisplayStrip: some View {
        HStack(spacing: 8) {
            Text("DESK DISPLAY").font(BarBoyStyle.microLabel)
            Rectangle().fill(deskDisplay.state == .ready ? Color.primary : Color.secondary).frame(width: 6, height: 6)
            Text("\(deskDisplay.state.label.uppercased()) / \(deskDisplay.pairingCode)")
                .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            Spacer()
            Button("OPEN") { if let url = deskDisplay.displayURL { NSWorkspace.shared.open(url) } }.barBoyButton()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("SUPPORT US") { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/Momo-Labz")!) }
                .barBoyButton()
            Text("PRIVATE / LOCAL-FIRST").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            Spacer()
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                Text(lastUpdateLabel.uppercased()).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.plain).help("Quit BAR BOY")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private func openNext() {
        if let session = urgentSessions.first { inspectedSession = session }
        else { NotificationCenter.default.post(name: .showCommandPalette, object: nil) }
    }

    private func capabilityTiles(kind: InstalledCapabilityKind) -> [CapabilityTile] {
        monitor.capabilityInventory.items(of: kind)
            .map(CapabilityTile.init)
            .sorted {
                if $0.isUsed != $1.isUsed { return $0.isUsed }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var lastUpdateLabel: String {
        guard let date = monitor.lastUpdated else { return "Reading local activity" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        return seconds < 5 ? "Updated now" : "Updated \(seconds)s ago"
    }
}

struct CompactDashboardView: View {
    var refreshOnAppear = true
    var animateMomo = true
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.openWindow) private var openWindow

    private var snapshots: [ProviderSnapshot] {
        monitor.snapshots.filter { preferences.isEnabled($0.provider) }
    }

    private var urgentCount: Int { snapshots.reduce(0) { $0 + $1.needsAttentionCount } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AnimatedMomoMark(size: 28, animated: animateMomo)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MOMO LABZ").font(BarBoyStyle.microLabel).tracking(1.2).foregroundStyle(.secondary)
                    Text("MODELS").font(BarBoyStyle.display)
                }
                Spacer()
                if urgentCount > 0 {
                    Text("!\(urgentCount)").font(BarBoyStyle.alertLabel).foregroundStyle(BarBoyStyle.coral)
                        .accessibilityLabel("\(urgentCount) sessions need you")
                }
                Button(action: expand) {
                    Label("EXPAND", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(BarBoyStyle.microLabel)
                }
                .barBoyButton()
                .help("Open the full BAR BOY hub")
            }
            .padding(.horizontal, 12)
            .frame(height: 52)

            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)

            HStack(spacing: 7) {
                ForEach(snapshots) { snapshot in
                    CompactProviderCell(snapshot: snapshot)
                }
            }
            .padding(12)
        }
        .frame(width: 430, height: 154)
        .background(BarBoyStyle.panel)
        .task { if refreshOnAppear { monitor.refresh() } }
    }

    private func expand() {
        let compactWindow = NSApplication.shared.keyWindow
        openWindow(id: "dashboard")
        DispatchQueue.main.async { compactWindow?.orderOut(nil) }
    }
}

private struct CompactProviderCell: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ProviderMark(provider: snapshot.provider, size: 30, active: snapshot.activeCount > 0)
                if snapshot.needsAttentionCount > 0 {
                    Rectangle().fill(BarBoyStyle.coral).frame(width: 5, height: 12).offset(x: 4, y: -3)
                }
            }
            Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.microLabel).lineLimit(1)
            Text(snapshot.usageText.uppercased()).font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(snapshot.needsAttentionCount > 0 ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.provider.name), \(snapshot.usageText), \(snapshot.activeCount) active")
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case home, agents, tools
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .agents: return "sparkles"
        case .tools: return "square.stack.3d.up.fill"
        }
    }
}

private struct CapabilityTile: Identifiable {
    let name: String
    let kind: InstalledCapabilityKind
    let provider: AIProvider?
    let isUsed: Bool
    let isShared: Bool
    var id: String { "\(kind.rawValue):\(name.lowercased())" }
    var monogram: String { String(name.prefix(2)).uppercased() }
    var provenanceLabel: String {
        let owner = provider?.name.uppercased() ?? (isShared ? "SHARED" : "LOCAL")
        return "\(kind.label) / \(owner)"
    }

    init(_ capability: InstalledCapability) {
        name = capability.name
        kind = capability.kind
        isUsed = capability.isUsed
        isShared = capability.isShared
        let owner = capability.usedBy.sorted { $0.rawValue < $1.rawValue }.first
            ?? capability.providerOwners.sorted { $0.rawValue < $1.rawValue }.first
        provider = owner.flatMap { AIProvider(rawValue: $0.rawValue) }
    }
}

private struct SectionHeader: View {
    let title: String
    let note: String
    var body: some View {
        HStack {
            Text(title).font(BarBoyStyle.sectionLabel).tracking(0.8).foregroundStyle(.secondary)
            Spacer()
            Text(note).font(BarBoyStyle.microLabel).foregroundStyle(.tertiary)
        }
    }
}

private struct CapabilitySquare: View {
    let tile: CapabilityTile
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(tile.monogram).font(BarBoyStyle.capabilityMark)
                Spacer()
                if let provider = tile.provider {
                    ProviderMark(provider: provider, size: 18, active: tile.isUsed)
                } else {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 11, weight: .bold))
                }
            }
            Spacer()
            Text(tile.name.uppercased()).font(BarBoyStyle.microLabel).lineLimit(2)
            Text(tile.isUsed ? "USED / \(tile.kind.label)" : "INSTALLED / \(tile.kind.label)")
                .font(.system(size: 7, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(width: 82, height: 78, alignment: .leading)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name), \(tile.kind.label), \(tile.isUsed ? "used in a session" : "installed")")
    }
}

private struct InventoryButtonSquare: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                Text(label).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }
            .frame(width: 62, height: 78)
            .background(BarBoyStyle.raised)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Open installed \(label.lowercased())")
    }
}

private struct MoreCapabilitySquare: View {
    let count: Int
    var body: some View {
        VStack(spacing: 4) {
            Text("+\(count)").font(BarBoyStyle.metric)
            Text("MORE").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
        }
        .frame(width: 62, height: 78)
        .background(BarBoyStyle.raised)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }
}

private struct EmptyCapabilityRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.dashed")
            Text(text).font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(11)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }
}

private struct IntegrationMark: View {
    let tile: CapabilityTile
    var body: some View {
        VStack(spacing: 1) {
            Text(tile.monogram).font(BarBoyStyle.rowTitle)
            Text(tile.kind == .mcpServer ? "M" : "P")
                .font(.system(size: 6, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
        .background(BarBoyStyle.raised)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .help("\(tile.name) / \(tile.provenanceLabel) / \(tile.isUsed ? "used" : "installed")")
        .accessibilityLabel("\(tile.name), \(tile.kind.label)")
    }
}

private struct ShortcutRow: View {
    let label: String
    let keys: [String]
    var disabled = false
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(BarBoyStyle.bodySmall)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.5) : Color.secondary).lineLimit(1)
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key).font(BarBoyStyle.keycap)
                        .foregroundStyle(disabled ? Color.secondary.opacity(0.5) : Color.primary)
                        .padding(.horizontal, key.count > 1 ? 7 : 6).frame(height: 24)
                        .background(BarBoyStyle.raised)
                        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                }
            }
        }
    }
}

private struct SummaryRow: View {
    let label: String
    let value: Int
    var body: some View {
        HStack {
            Text(label).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)").font(BarBoyStyle.metric)
        }
    }
}

private struct ProviderUsageRow: View {
    let snapshot: ProviderSnapshot
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ProviderMark(provider: snapshot.provider, size: 24, active: snapshot.activeCount > 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.rowTitle)
                    Text(snapshot.usageText.uppercased()).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(percent(snapshot.shortWindowPercent)).frame(width: 40, alignment: .trailing)
                Text(percent(snapshot.weekWindowPercent)).frame(width: 40, alignment: .trailing)
                ZStack(alignment: .topTrailing) {
                    Text("\(snapshot.sessions.count)").frame(width: 34, alignment: .trailing)
                    if snapshot.needsAttentionCount > 0 {
                        Rectangle().fill(BarBoyStyle.coral).frame(width: 5, height: 11).offset(x: 4, y: -5)
                    }
                }
            }
            .font(BarBoyStyle.metricSmall)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(selected ? Color.primary.opacity(0.09) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(snapshot.provider.name), \(snapshot.sessions.count) sessions, \(snapshot.usageText) local usage")
    }

    private func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "—" }
}

private struct SessionRow: View {
    let session: AgentSession
    var body: some View {
        HStack(spacing: 9) {
            ProviderMark(provider: session.provider, size: 28, active: session.isRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(BarBoyStyle.rowTitle).lineLimit(1)
                Text("\(session.role.rawValue.uppercased()) / \(session.project.uppercased())")
                    .font(BarBoyStyle.microLabel).foregroundStyle(.secondary).lineLimit(1)
                if !session.capabilitySummary.isEmpty {
                    Text(session.capabilitySummary).font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(session.attention.isUrgent ? session.attention.label : session.ageLabel)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(session.attention.isUrgent ? BarBoyStyle.coral : Color.secondary)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(session.attention.isUrgent ? BarBoyStyle.coral.opacity(0.10) : BarBoyStyle.raised)
                .overlay(Rectangle().stroke(session.attention.isUrgent ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
        .help(session.attentionReason ?? session.detail)
    }
}

private struct SessionInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    let session: AgentSession
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProviderMark(provider: session.provider, size: 36, active: session.isRunning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.headline).lineLimit(2)
                    Text("\(session.provider.name.uppercased()) / \(session.role.rawValue.uppercased()) / \(session.project.uppercased())")
                        .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                }
                Spacer()
                Button("DONE") { dismiss() }.barBoyButton()
            }
            .padding(16)
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if session.attention.isUrgent {
                        InspectorBlock(title: "RETURN", values: [session.attentionReason ?? "This agent needs your response"], alert: true)
                    }
                    InspectorBlock(title: "MODEL", values: [session.model ?? "Not exposed by this session"])
                    InspectorBlock(title: "MCP SERVERS", values: session.mcpServers.isEmpty ? ["None recorded"] : session.mcpServers)
                    InspectorBlock(title: "SKILLS", values: session.skills.isEmpty ? ["None recorded"] : session.skills)
                    InspectorBlock(title: "PLUGINS", values: session.plugins.isEmpty ? ["None recorded"] : session.plugins)
                    InspectorBlock(title: "LATEST", values: [session.detail])
                }
                .padding(16)
            }
        }
        .frame(width: 430, height: 470)
        .background(BarBoyStyle.panel)
    }
}

private struct InspectorBlock: View {
    let title: String
    let values: [String]
    var alert = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(BarBoyStyle.microLabel).foregroundStyle(alert ? BarBoyStyle.coral : Color.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Text(value.isEmpty ? "No detail recorded" : value)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    if index < values.count - 1 { Rectangle().fill(BarBoyStyle.hairline).frame(height: 1) }
                }
            }
            .background(alert ? BarBoyStyle.coral.opacity(0.08) : BarBoyStyle.surface)
            .overlay(Rectangle().stroke(alert ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
        }
    }
}

extension Notification.Name {
    static let showCommandPalette = Notification.Name("BarBoyShowCommandPalette")
}
