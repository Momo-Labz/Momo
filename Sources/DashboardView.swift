import AppKit
import SwiftUI

struct DashboardView: View {
    var refreshOnAppear = true
    var showsOverview = false
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var deskDisplay: DeskDisplayServer
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var surface = MomoSurface.shared
    @State private var tab: DashboardTab = .home
    @State private var providerFilter: AIProvider?
    @State private var inspectedSession: AgentSession?

    init(refreshOnAppear: Bool = true, initialTab: DashboardTab = .home, showsOverview: Bool = false) {
        self.refreshOnAppear = refreshOnAppear
        self.showsOverview = showsOverview
        _tab = State(initialValue: initialTab)
    }

    private var enabledSnapshots: [ProviderSnapshot] {
        monitor.snapshots.map { snapshot in
            var result = snapshot
            result.sessions = snapshot.sessions.map(preferences.presented)
            return result
        }.filter {
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
    private var skillTiles: [CapabilityTile] { capabilityTiles(kind: .skill) { $0.skills } }
    private var integrationTiles: [CapabilityTile] {
        capabilityTiles(kind: .mcp) { $0.mcpServers } + capabilityTiles(kind: .plugin) { $0.plugins }
    }

    var body: some View {
        if showsOverview {
            VStack(spacing: 0) {
                header
                Divider()
                page
                footer
            }.frame(width: 860, height: 570).background(BarBoyStyle.panel)
                .task { if refreshOnAppear { monitor.refresh() } }
        } else { compactExpansion }
    }

    private var compactExpansion: some View {
        VStack(spacing: 0) {
            CompactDashboardView(refreshOnAppear: false, expanded: true)
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            paneBar
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            switch surface.pane {
            case .quickAsk: CommandPaletteView(embedded: true).environmentObject(preferences)
            case .voice: VoicePopup(embedded: true)
            case .sessions: sessionsPane
            }
            HStack {
                Text(lastUpdateLabel).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                Spacer()
                Button("QUICK ASK") { surface.show(.quickAsk) }.barBoyButton()
            }.padding(12)
        }
        .frame(width: 430)
        .frame(minHeight: 500)
        .background(BarBoyStyle.panel)
        .animation(paneAnimation, value: surface.pane)
        .task { if refreshOnAppear { monitor.refresh() } }
    }

    /// Emil's frequency gate: a pane reached by keyboard shortcut must not animate.
    private var paneAnimation: Animation? {
        reduceMotion || surface.lastChangeWasKeyboard ? nil : BarBoyStyle.pageAnimation
    }

    private var paneBar: some View {
        HStack(spacing: 0) {
            ForEach(MomoPane.allCases) { item in
                Button { surface.show(item) } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(BarBoyStyle.microLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(surface.pane == item ? Color.primary : Color.clear)
                        .foregroundStyle(surface.pane == item ? BarBoyStyle.inverseInk : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(surface.pane == item ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var sessionsPane: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("SESSIONS").font(BarBoyStyle.sectionLabel)
                        Button("OVERVIEW") { openWindow(id: "overview") }.barBoyButton()
                        Spacer()
                        Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .barBoyIconButton().help("Refresh sessions")
                        Button { openSettings() } label: { Image(systemName: "gearshape.fill") }
                            .barBoyIconButton().help("Provider authorization and settings")
                    }
                    ForEach(enabledSnapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(title: snapshot.provider.name.uppercased(), note: "\(snapshot.sessions.count) RECORDED")
                            if snapshot.sessions.isEmpty {
                                Text("No sessions recorded. Process activity alone cannot identify a chat.")
                                    .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                            }
                            ForEach(Array(Set(snapshot.sessions.map(\.project))).sorted(), id: \.self) { folder in
                                Label(folder, systemImage: "folder").font(.headline).padding(.top, 6)
                                ForEach(snapshot.sessions.filter { $0.project == folder }.sorted { $0.updatedAt > $1.updatedAt }) { session in
                                    Button { openReply(session) } label: { SessionRow(session: session, showsFolder: false) }
                                        .buttonStyle(MomoActionButtonStyle())
                                        .background(BarBoyStyle.surface)
                                        .overlay(Rectangle().stroke(session.attention.isUrgent ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
                                }
                            }
                        }
                    }
                    if enabledSnapshots.isEmpty {
                        Text("Authorize a local provider above to see its sessions.")
                            .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                    }
                }.padding(12)
            }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AnimatedMomoMark(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("MOMO LABZ").font(BarBoyStyle.microLabel).tracking(1.35).foregroundStyle(.secondary)
                Text("MOMO").font(BarBoyStyle.display).tracking(0.9)
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
                            Text("NO ONE IS WAITING").font(BarBoyStyle.rowTitle)
                            Text("The queue interrupts only when an agent needs you.")
                                .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(11)
                } else {
                    ForEach(Array(urgentSessions.prefix(2).enumerated()), id: \.element.id) { index, session in
                        Button { openReply(session) } label: { SessionRow(session: session) }
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
            SectionHeader(title: "RECORDED SKILLS", note: skillTiles.isEmpty ? "NOT RECORDED" : "\(skillTiles.count) DETECTED")
            if skillTiles.isEmpty {
                EmptyCapabilityRow(text: "Skills appear when a local session records them.")
            } else {
                HStack(spacing: 8) {
                    ForEach(skillTiles.prefix(4)) { CapabilitySquare(tile: $0) }
                    if skillTiles.count > 4 { MoreCapabilitySquare(count: skillTiles.count - 4) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "RECORDED INTEGRATIONS", note: "MCP + PLUGINS")
            HStack(spacing: 7) {
                if integrationTiles.isEmpty {
                    Text("NONE RECORDED IN SESSIONS").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                } else {
                    ForEach(integrationTiles.prefix(6)) { IntegrationMark(tile: $0) }
                    if integrationTiles.count > 6 {
                        Text("+\(integrationTiles.count - 6)")
                            .font(BarBoyStyle.microLabel).frame(width: 30, height: 30)
                            .background(BarBoyStyle.raised)
                            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                    }
                }
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
            ForEach(ShortcutAction.allCases) { action in
                Button { NotificationCenter.default.post(name: .momoShortcut, object: action) } label: {
                    ShortcutRow(label: action.title, keys: [GlobalShortcutService.shared.bindings[action]?.label ?? "—"])
                }.buttonStyle(MomoActionButtonStyle())
            }
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
            SummaryRow(label: "MODELS RECORDED", value: Set(allSessions.compactMap(\.model)).count)
            SummaryRow(label: "CAPABILITIES", value: skillTiles.count + integrationTiles.count)
        }
        .padding(12)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private var agentsPage: some View {
        HStack(alignment: .top, spacing: 16) {
            usageTable.frame(width: 390)
            Rectangle().fill(BarBoyStyle.hairline).frame(width: 1)
            activitySection.frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var toolsPage: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "SKILL CATALOG", note: "RECORDED BY SESSIONS")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], alignment: .leading, spacing: 8) {
                    if skillTiles.isEmpty { EmptyCapabilityRow(text: "No skills recorded yet.") }
                    else { ForEach(skillTiles) { CapabilitySquare(tile: $0) } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Rectangle().fill(BarBoyStyle.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "INTEGRATIONS", note: "MCP + PLUGINS")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(integrationTiles) { tile in
                        HStack(spacing: 10) {
                            IntegrationMark(tile: tile)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tile.name.uppercased()).font(BarBoyStyle.rowTitle)
                                Text("\(tile.kind.label) / \(tile.provider.name.uppercased())")
                                    .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    if integrationTiles.isEmpty { EmptyCapabilityRow(text: "No integrations recorded yet.") }
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
                    Text("SHORT").frame(width: 70, alignment: .trailing)
                    Text("LONG").frame(width: 70, alignment: .trailing)
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
                                Text("QUIET RIGHT NOW").font(BarBoyStyle.rowTitle)
                                Text("New local sessions appear here.").font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(13)
                    } else {
                        ForEach(Array(visibleSessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                            Button { openReply(session) } label: { SessionRow(session: session) }
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

    private func openReply(_ session: AgentSession) {
        NotificationCenter.default.post(name: .showCommandPalette, object: session)
    }

    private func openNext() {
        if let session = urgentSessions.first { openReply(session) }
        else { NotificationCenter.default.post(name: .showCommandPalette, object: nil) }
    }

    private func capabilityTiles(kind: CapabilityKind, values: (AgentSession) -> [String]) -> [CapabilityTile] {
        var seen = Set<String>()
        return allSessions.flatMap { session in
            values(session).compactMap { name in
                let key = "\(session.provider.rawValue):\(kind.rawValue):\(name.lowercased())"
                guard seen.insert(key).inserted else { return nil }
                return CapabilityTile(name: name, kind: kind, provider: session.provider)
            }
        }
    }

    private var lastUpdateLabel: String {
        guard let date = monitor.lastUpdated else { return "Reading local activity" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        return seconds < 5 ? "Updated now" : "Updated \(seconds)s ago"
    }
}

struct CompactDashboardView: View {
    static let canvasSize = CGSize(width: 430, height: 220)
    var refreshOnAppear = true
    var animateMomo = true
    var expanded = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var snapshots: [ProviderSnapshot] {
        monitor.snapshots.map { snapshot in
            var result = snapshot
            result.sessions = snapshot.sessions.map(preferences.presented)
            return result
        }.filter { preferences.isEnabled($0.provider) }
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
                Button { if expanded { dismiss() } else { expand() } } label: {
                    Label(expanded ? "COLLAPSE" : "EXPAND", systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(BarBoyStyle.microLabel)
                }
                .barBoyButton()
                .help("Open the full MOMO hub")
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            HStack {
                Button("+ PROVIDER") { openSettings() }.barBoyButton()
                Button("REFRESH") { monitor.refresh(); MomoFeedback.perform() }.barBoyButton()
                Spacer()
                Button("OVERVIEW") { openWindow(id: "overview") }.barBoyButton()
            }.font(BarBoyStyle.microLabel).padding(.horizontal, 12).padding(.bottom, 8)

            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)

            HStack(spacing: 7) {
                if snapshots.isEmpty {
                    Button("AUTHORIZE LOCAL PROVIDERS") { openSettings() }
                        .barBoyButton()
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                ForEach(snapshots) { snapshot in
                    Button { openProvider(snapshot) } label: {
                        CompactProviderCell(snapshot: snapshot)
                    }
                    .buttonStyle(.plain)
                    .help(snapshot.needsAttentionCount > 0
                        ? "Open the issue in \(snapshot.provider.name) and inspect the exact chat"
                        : "Open \(snapshot.provider.name) sessions")
                }
            }
            .padding(12)
        }
        .frame(width: 430, height: 220)
        .background(BarBoyStyle.panel)
        .task { if refreshOnAppear { monitor.refresh() } }
    }

    private func expand() {
        let compactWindow = NSApplication.shared.keyWindow
        openWindow(id: "dashboard")
        DispatchQueue.main.async { compactWindow?.orderOut(nil) }
    }

    private func openProvider(_ snapshot: ProviderSnapshot) {
        let session = snapshot.sessions.first(where: { $0.attention.isUrgent })
            ?? snapshot.sessions.first
        guard let session else {
            openWindow(id: "dashboard")
            return
        }
        NotificationCenter.default.post(name: .showCommandPalette, object: session)
        MomoFeedback.perform()
    }
}

private struct CompactProviderCell: View {
    let snapshot: ProviderSnapshot

    /// The conversation actually running for this provider, if any.
    private var running: AgentSession? {
        snapshot.sessions.first { $0.isRunning && $0.processID == nil }
            ?? snapshot.sessions.first { $0.isRunning }
    }

    /// Name the running chat rather than a generic activity count.
    private var runningLine: String {
        guard let running else { return snapshot.usageText.uppercased() }
        return running.title.uppercased()
    }

    private var runningHelp: String {
        guard let running else { return "No running conversation recorded for \(snapshot.provider.name)." }
        return "\(running.title)\nFolder: \(running.project)"
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ProviderMark(provider: snapshot.provider, size: 30, active: snapshot.activeCount > 0)
                if snapshot.needsAttentionCount > 0 {
                    Rectangle().fill(BarBoyStyle.coral).frame(width: 5, height: 12).offset(x: 4, y: -3)
                }
            }
            Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.microLabel).lineLimit(1)
            Text(runningLine).font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                .help(runningHelp)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ForEach(Array(snapshot.quotaLabels(now: context.date).enumerated()), id: \.offset) { _, label in
                    Text(label).font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                        .help(snapshot.recordedQuota?.explanation ?? "No recorded usage window. A dash means unavailable.")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(snapshot.needsAttentionCount > 0 ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.provider.name), \(snapshot.usageText), \(snapshot.quotaLabels.joined(separator: ", ")), \(snapshot.activeCount) active")
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

private enum CapabilityKind: String {
    case skill, mcp, plugin
    var label: String { self == .skill ? "SKILL" : (self == .mcp ? "MCP" : "PLUGIN") }
}

private struct CapabilityTile: Identifiable {
    let name: String
    let kind: CapabilityKind
    let provider: AIProvider
    var id: String { "\(provider.rawValue):\(kind.rawValue):\(name.lowercased())" }
    var monogram: String { String(name.prefix(2)).uppercased() }
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
                ProviderMark(provider: tile.provider, size: 18, active: true)
            }
            Spacer()
            Text(tile.name.uppercased()).font(BarBoyStyle.microLabel).lineLimit(2)
            Text(tile.kind.label).font(.system(size: 7, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(width: 82, height: 78, alignment: .leading)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name), \(tile.kind.label), used by \(tile.provider.name)")
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
            Text(tile.kind == .mcp ? "M" : "P")
                .font(.system(size: 6, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
        .background(BarBoyStyle.raised)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .help("\(tile.name) / \(tile.kind.label) / \(tile.provider.name)")
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
                Text(snapshot.quotaLabels[0]).font(.system(size: 8)).frame(width: 70, alignment: .trailing)
                Text(snapshot.quotaLabels[1]).font(.system(size: 8)).frame(width: 70, alignment: .trailing)
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
    @ObservedObject private var autoResume = AutoResumeService.shared
    let session: AgentSession
    /// Off when the surrounding list already groups rows under a folder header.
    var showsFolder = true
    var body: some View {
        HStack(spacing: 9) {
            ProviderMark(provider: session.provider, size: 28, active: session.isRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(BarBoyStyle.rowTitle).lineLimit(2).help(session.title)
                if session.processID == nil {
                    HStack(spacing: 4) {
                        if showsFolder {
                            Image(systemName: "folder").font(.system(size: 8))
                            Text(session.project).lineLimit(1).truncationMode(.middle)
                            Text("/").foregroundStyle(.tertiary)
                        }
                        Text(session.role.rawValue.uppercased())
                    }
                    .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                    .help("Folder: \(session.project)")
                } else {
                    Text("PROCESS / UNLINKED TO A CHAT")
                        .font(BarBoyStyle.microLabel).foregroundStyle(.secondary).lineLimit(1)
                }
                // The state already says whether it is automatic; no "AUTO" prefix
                // in front of a state that reads "Manual".
                Text(autoResume.state(for: session)).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
                if !session.capabilitySummary.isEmpty {
                    Text(session.capabilitySummary).font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(session.stoppedAfterUsageGrowth ? "STOPPED AFTER USAGE" : (session.attention == .working && !session.isRunning ? "LAST: WORKING" : session.attention.label))
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(session.attention.isUrgent ? BarBoyStyle.coral : Color.secondary)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(session.attention.isUrgent ? BarBoyStyle.coral.opacity(0.10) : BarBoyStyle.raised)
                .overlay(Rectangle().stroke(session.attention.isUrgent ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
        .help(session.stoppedAfterUsageGrowth ? "Stopped after recorded tokens increased. This does not establish a quota or rate-limit cause." : session.attentionReason ?? session.detail)
    }
}

struct SessionInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var autoResume = AutoResumeService.shared
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
                    InspectorBlock(title: "CHAT / AUTO-RESUME", values: [
                        "Chat: \(session.title)",
                        "Folder: \(session.project)",
                        "Auto-resume: \(autoResume.state(for: session))"
                    ], alert: session.attention.isUrgent)
                    if let source = session.sourceURL {
                        InspectorBlock(title: "SOURCE", values: [source.path])
                    }
                    if !session.recordedQuotaWindows.isEmpty {
                        InspectorBlock(title: "RECORDED USAGE", values: session.recordedQuotaWindows.map {
                            "\($0.label(now: .now))\($0.resetsAt.map { " · resets \($0.formatted(date: .omitted, time: .shortened))" } ?? "") · observed \($0.observedAt.formatted())"
                        })
                    }
                    if session.stoppedAfterUsageGrowth {
                        InspectorBlock(title: "STOPPED AFTER USAGE", values: [
                            "This chat was working, then stopped after token usage increased.",
                            "Open the source chat to inspect the provider’s exact error."
                        ], alert: true)
                    }
                    InspectorBlock(title: "MODEL", values: [session.model ?? "Not exposed by this session"])
                    InspectorBlock(title: "MCP SERVERS", values: session.mcpServers.isEmpty ? ["None recorded"] : session.mcpServers)
                    InspectorBlock(title: "SKILLS", values: session.skills.isEmpty ? ["None recorded"] : session.skills)
                    InspectorBlock(title: "PLUGINS", values: session.plugins.isEmpty ? ["None recorded"] : session.plugins)
                    InspectorBlock(title: "LATEST", values: [session.detail])
                    Button("CONTINUE THIS CHAT") {
                        dismiss()
                        NotificationCenter.default.post(name: .showCommandPalette, object: session)
                    }.barBoyButton()
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
