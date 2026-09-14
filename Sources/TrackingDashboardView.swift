import AppKit
import SwiftUI

private extension TrackerTab {
    var symbol: String {
        switch self { case .activity: "waveform.path.ecg"; case .usage: "chart.bar.xaxis"; case .brain: "circle.hexagongrid.fill" }
    }
}

/// Tracking-first surface for the menu bar, dashboard window, and overview window.
/// It intentionally exposes only observed state and read-only session inspection.
struct TrackingDashboardView: View {
    let refreshOnAppear: Bool
    let showsOverview: Bool
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var deskDisplay: DeskDisplayServer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var surface = MomoSurface.shared
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var pageSize = 10
    @State private var loading = true

    private var snapshots: [ProviderSnapshot] {
        AIProvider.allCases.map { provider in
            var snapshot = monitor.snapshot(for: provider)
            snapshot.sessions = snapshot.sessions.map(preferences.presented)
            return snapshot
        }
    }

    private var sessions: [AgentSession] {
        let all = snapshots.flatMap(\.sessions).sorted { $0.updatedAt > $1.updatedAt }
        guard !debouncedSearch.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(debouncedSearch) ||
            $0.project.localizedCaseInsensitiveContains(debouncedSearch) ||
            $0.provider.name.localizedCaseInsensitiveContains(debouncedSearch)
        }
    }

    var body: some View {
        Group {
            if surface.screen == .settings && !showsOverview {
                embeddedSettings
            } else {
                VStack(spacing: 0) {
                    header
                    providerRail
                    Divider().opacity(0.55)
                    tabBar
                    Divider().opacity(0.55)
                    Group {
                        if loading { LoadingSkeleton() }
                        else {
                            switch surface.trackerTab {
                            case .activity: activity
                            case .usage: usage
                            case .brain: brain
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .id(surface.screen)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: reduceMotion || surface.lastChangeWasKeyboard ? 0 : 4)),
            removal: .opacity
        ))
        .animation(reduceMotion || surface.lastChangeWasKeyboard ? nil : BarBoyStyle.pageAnimation, value: surface.screen)
        .frame(
            width: showsOverview ? MomoSurface.expandedWidth : (surface.expanded ? MomoSurface.expandedWidth : MomoSurface.compactWidth),
            height: showsOverview ? 790 : (surface.expanded ? MomoSurface.expandedHeight : MomoSurface.compactHeight)
        )
        .background(BarBoyStyle.panel)
        .sheet(item: Binding(get: {
            sessions.first(where: { $0.id == surface.selectedSessionID })
        }, set: { session in
            surface.selectSession(session)
        })) { session in SessionDetailView(session: session) }
        .task {
            if refreshOnAppear { monitor.refresh() }
            try? await Task.sleep(for: .milliseconds(150))
            loading = false
        }
        .onChange(of: search) { _, value in
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                debouncedSearch = value
                pageSize = 10
            }
        }
    }

    private var embeddedSettings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { surface.leaveSettings() } label: {
                    Label("BACK", systemImage: "chevron.left")
                        .font(BarBoyStyle.navLabel)
                }
                .barBoyButton()
                VStack(alignment: .leading, spacing: 1) {
                    Text("MOMO LABZ").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                    Text("SETTINGS").font(BarBoyStyle.display).tracking(0.8)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 55)
            Divider().opacity(0.55)
            SettingsView(embedded: true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AnimatedMomoMark(size: 27, animated: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("MOMO LABZ").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                Text("TRACKING").font(BarBoyStyle.display).tracking(0.8)
            }
            Spacer()
            Text(statusText).font(BarBoyStyle.microLabel).foregroundStyle(statusColor)
            Button { surface.expanded.toggle() } label: { Image(systemName: surface.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                .barBoyIconButton().help(surface.expanded ? "Contract" : "Expand")
            Button { surface.showSettings() } label: { Image(systemName: "gearshape.fill") }.barBoyIconButton().help("Settings")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }.barBoyIconButton().help("Quit MOMO")
            Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .barBoyIconButton().help("Refresh observed activity")
        }
        .padding(.horizontal, 14).frame(height: 55)
    }

    private var statusText: String {
        let waiting = snapshots.reduce(0) { $0 + $1.waitingCount }
        return waiting > 0 ? "\(waiting) NEED YOU" : "\(snapshots.reduce(0) { $0 + $1.activeCount }) LIVE"
    }

    private var statusColor: Color { snapshots.contains(where: { $0.hasErrorOrApproval }) ? BarBoyStyle.coral : .secondary }

    private var providerRail: some View {
        HStack(spacing: 7) {
            ForEach(snapshots) { snapshot in
                ProviderCard(snapshot: snapshot, expanded: surface.expanded || showsOverview, selected: surface.selectedProvider == snapshot.provider) {
                    surface.selectProvider(surface.selectedProvider == snapshot.provider ? nil : snapshot.provider)
                    surface.trackerTab = .activity
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: surface.expanded || showsOverview ? 91 : 68)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(TrackerTab.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { surface.trackerTab = item }
                } label: {
                    Label(item.title.uppercased(), systemImage: item.symbol)
                        .font(BarBoyStyle.navLabel).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(surface.trackerTab == item ? BarBoyStyle.inverseInk : Color.primary)
                        .background(surface.trackerTab == item ? Color.primary : .clear)
                }.buttonStyle(.plain)
            }
        }.padding(4)
    }

    private var activity: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITY").font(BarBoyStyle.sectionLabel)
                Spacer()
                Text("READ ONLY").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sessions", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(9).background(BarBoyStyle.surface).overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            LazyVStack(spacing: 6) {
                ForEach(Array(sessions.filter { surface.selectedProvider == nil || $0.provider == surface.selectedProvider }.prefix(surface.expanded || showsOverview ? pageSize : 3))) { session in
                    Button { surface.selectSession(session) } label: { TrackingSessionRow(session: session) }
                        .buttonStyle(.plain)
                }
                if sessions.isEmpty { Text("No recorded activity yet.").font(BarBoyStyle.bodySmall).foregroundStyle(.secondary).padding(.vertical, 20) }
                if (surface.expanded || showsOverview) && sessions.count > pageSize {
                    Button("LOAD 10 MORE") { pageSize += 10 }.barBoyButton()
                }
            }
        }.padding(12)
        }
    }

    private var usage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("USAGE").font(BarBoyStyle.sectionLabel)
                Text("Only provider-recorded windows are shown. A dash means MOMO has no verified value.").font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                ForEach(snapshots) { snapshot in UsageCard(snapshot: snapshot) }
            }.padding(12)
        }
    }

    private var brain: some View {
        BrainWorkspaceView(refreshOnAppear: false)
    }
}

private struct ProviderCard: View {
    let snapshot: ProviderSnapshot
    let expanded: Bool
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: expanded ? 5 : 3) {
                HStack { ProviderMark(provider: snapshot.provider, size: expanded ? 22 : 17, active: snapshot.activeCount > 0); Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.microLabel); Spacer(); Text(snapshot.isInstalled ? (snapshot.activeCount > 0 ? "LIVE" : "IDLE") : "UNAVAILABLE").font(BarBoyStyle.microLabel).foregroundStyle(.secondary) }
                Text(snapshot.statusLabel).font(BarBoyStyle.bodySmall).lineLimit(1)
                if expanded { Text("\(snapshot.tokenLabel) · \(snapshot.resetLabel(now: .now))").font(BarBoyStyle.microLabel).foregroundStyle(.secondary).lineLimit(1) }
                if let percent = snapshot.recordedQuota?.percent ?? snapshot.recordedQuotas.first?.percent {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { index in
                            Rectangle().fill(index < Int(ceil(Double(percent) / 25.0)) ? (percent >= 90 ? BarBoyStyle.coral : BarBoyStyle.amber) : BarBoyStyle.hairline.opacity(0.45)).frame(height: 3)
                        }
                    }
                }
            }.frame(width: expanded ? 162 : 118, alignment: .leading).padding(8)
                .background(selected ? BarBoyStyle.surface.opacity(1.8) : BarBoyStyle.surface)
                .overlay(Rectangle().stroke(snapshot.hasErrorOrApproval ? BarBoyStyle.coral : selected ? Color.primary : BarBoyStyle.hairline, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityLabel("\(snapshot.provider.name), \(snapshot.statusLabel)")
    }
}

private struct TrackingSessionRow: View {
    let session: AgentSession
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(session.attention == .failed ? BarBoyStyle.coral : session.attention == .needsInput ? BarBoyStyle.amber : Color.primary).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(SessionPresentation.title(for: session)).font(BarBoyStyle.rowTitle).lineLimit(1)
                Text("\(session.provider.name.uppercased()) · \(session.project) · \(session.attention.label)").font(BarBoyStyle.microLabel).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(); Text(session.ageLabel).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
        }.padding(9).background(BarBoyStyle.surface).overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }
}

private struct UsageCard: View {
    let snapshot: ProviderSnapshot
    @State private var capturePresented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.rowTitle); Spacer(); Text(snapshot.usageText.uppercased()).font(BarBoyStyle.microLabel) }
            HStack { Text(snapshot.quotaLabels.joined(separator: "  ·  ")).font(BarBoyStyle.microLabel).foregroundStyle(.secondary); Spacer(); Text(snapshot.resetLabel(now: .now)).font(BarBoyStyle.microLabel).foregroundStyle(.secondary) }
            if snapshot.provider == .claude || snapshot.provider == .cursor {
                Button("CONNECT USAGE") { capturePresented = true }.barBoyButton()
            }
        }.padding(11).background(BarBoyStyle.surface).overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            .sheet(isPresented: $capturePresented) { UsageCaptureView(provider: snapshot.provider) }
    }
}

private struct LoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(0..<5, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(BarBoyStyle.surface).frame(height: 46).redacted(reason: .placeholder) }
        }.padding(12)
    }
}

private struct SessionDetailView: View {
    let session: AgentSession
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { ProviderMark(provider: session.provider, size: 34, active: session.isRunning); VStack(alignment: .leading) { Text(session.provider.name.uppercased()).font(BarBoyStyle.microLabel); Text(SessionPresentation.title(for: session)).font(BarBoyStyle.display) }; Spacer() }
            Divider()
            Text(session.attentionReason ?? session.attention.label).font(BarBoyStyle.bodySmall)
            Text("PROJECT  \(session.project)\nMODEL  \(session.model ?? "Unavailable")\nUPDATED  \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            Spacer()
            if let originalURL = verifiedOriginalURL {
                Button("OPEN ORIGINAL") { NSWorkspace.shared.open(originalURL) }.barBoyButton()
            } else {
                Text("Original destination unavailable").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }
        }.padding(18).frame(minWidth: 360, minHeight: 250).background(BarBoyStyle.panel)
    }

    private var verifiedOriginalURL: URL? {
        guard session.provider == .codex else { return nil }
        return CodexDesktopConnection.taskURL(source: session.sourceURL)
    }
}
