import AppKit
import SwiftUI

private extension TrackerTab {
    var symbol: String {
        switch self { case .activity: "waveform.path.ecg"; case .usage: "chart.bar.xaxis"; case .brain: "circle.hexagongrid.fill" }
    }
}

/// Tracking-first surface for the single attached menu-bar panel.
/// It intentionally exposes only observed state and read-only session inspection.
struct TrackingDashboardView: View {
    let refreshOnAppear: Bool
    let showsOverview: Bool
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var surface = MomoSurface.shared
    @ObservedObject private var momoAlerts = MomoAlertPresenter.shared
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var pageSize = 10
    @State private var loading = true
    @State private var showOnboarding = false
    @State private var onboardingStartStep: TrackingOnboardingStep = .welcome
    @State private var showTalkTrial = false

    private var needsOnboarding: Bool { preferences.needsTrackingOnboarding || showOnboarding }
    private var snapshots: [ProviderSnapshot] {
        AIProvider.allCases.map { provider in
            var snapshot = monitor.snapshot(for: provider)
            snapshot.sessions = snapshot.sessions.map(preferences.presented)
            return snapshot
        }
    }

    private var railSnapshots: [ProviderSnapshot] {
        let allowed = Set(preferences.trackingStripProviders())
        return snapshots.filter { allowed.contains($0.provider) }
    }

    private var usageSnapshots: [ProviderSnapshot] {
        preferences.trackingOnboardingSeen
            ? snapshots.filter { preferences.isTrackingAllowed($0.provider) }
            : []
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
        ZStack {
            // Sticky chrome: header + provider strip + tabs stay put; only the tab body scrolls.
            VStack(spacing: 0) {
                header
                    .zIndex(2)
                providerRail
                    .zIndex(2)
                Divider().opacity(0.55)
                if surface.route == .dashboard {
                    if !surface.pendingUsageReturn.isEmpty {
                        usageReturnBanner
                        Divider().opacity(0.55)
                    }
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
                    .clipped()
                } else if case .settings = surface.route {
                    // Settings owns its Back + tabs below sticky Tracking chrome (no overlapping route strip).
                    SettingsView(embedded: true, onBack: { surface.goBack() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                } else {
                    routeHeader
                    Divider().opacity(0.55)
                    routedContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                }
            }

            if needsOnboarding {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { /* block chrome until Welcome finishes */ }
                ScrollView {
                    TrackingOnboardingView(
                        initialStep: preferences.needsTrackingOnboarding ? .welcome : onboardingStartStep,
                        initialIntents: preferences.onboardingIntents,
                        initialAllowed: preferences.allowedTrackingProviders,
                        onFinish: finishOnboarding,
                        onDismiss: preferences.needsTrackingOnboarding ? nil : { showOnboarding = false },
                        onTalkTrial: { showTalkTrial = true }
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98)))
            }

            if showTalkTrial {
                Color.black.opacity(0.55).ignoresSafeArea()
                TalkPanelView(
                    isOnboardingTrial: true,
                    onFinishedOnboardingTrial: { showTalkTrial = false },
                    onDismiss: { showTalkTrial = false }
                )
                .padding(16)
            }
        }
        .frame(
            width: showsOverview ? MomoSurface.expandedWidth : (surface.usesExpandedSize ? MomoSurface.expandedWidth : MomoSurface.compactWidth),
            height: showsOverview ? 790 : (surface.usesExpandedSize ? MomoSurface.expandedHeight : MomoSurface.compactHeight)
        )
        .background(BarBoyStyle.panel)
        .task {
            if refreshOnAppear { monitor.refresh() }
            try? await Task.sleep(for: .milliseconds(150))
            loading = false
            if preferences.needsTrackingOnboarding {
                surface.expanded = true
                showOnboarding = true
            }
        }
        .onChange(of: preferences.trackingOnboardingSeen) { _, seen in
            if !seen {
                showOnboarding = true
                onboardingStartStep = .welcome
                surface.expanded = true
            }
        }
        .onChange(of: search) { _, value in
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                debouncedSearch = value
                pageSize = 10
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .momoShowProviderChooser)) { note in
            surface.expanded = true
            if surface.route != .dashboard { surface.goBack() }
            if let raw = note.userInfo?["step"] as? Int,
               let step = TrackingOnboardingStep(rawValue: raw) {
                onboardingStartStep = step
            } else {
                onboardingStartStep = .welcome
            }
            showOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .momoShortcut)) { note in
            guard let action = note.object as? ShortcutAction, action == .talk else { return }
            surface.openTalk()
        }
    }

    private func finishOnboarding(intents: Set<OnboardingIntent>, allowed: Set<AIProvider>) {
        preferences.setOnboardingIntents(intents)
        preferences.setAllowedTrackingProviders(allowed, markOnboardingSeen: true)
        showOnboarding = false
        showTalkTrial = false
        onboardingStartStep = .welcome
        let connectable = AIProvider.allCases.filter { allowed.contains($0) && $0.supportsUsageCapture }
        // Soft return only — do not auto-open isolated WebKit after browser connect.
        surface.offerUsageReturn(connectable)
        if intents.contains(.usageTracking), !connectable.isEmpty {
            surface.trackerTab = .usage
        } else if preferences.prefersBrainTips() {
            surface.trackerTab = .brain
        }
    }

    private var usageReturnBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Button("Confirm usage snapshot") { surface.beginPendingUsageReturn() }
                    .barBoyButton()
                Text("Verified % unlock after you preview and accept. Timed refresh is MOMO+.")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                surface.dismissUsageReturn()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BarBoyStyle.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AnimatedMomoMark(size: 27, animated: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("MOMO LABZ").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                Text("TRACKING").font(BarBoyStyle.display).tracking(0.8)
            }
            Spacer(minLength: 8)
            Text(statusText).font(BarBoyStyle.microLabel).foregroundStyle(statusColor)
            // Layout: status → animated MOMO → alert legend → chrome icons
            AnimatedMomoMark(
                size: 28,
                animated: !reduceMotion,
                motion: momoAlerts.isFlashing ? .alert : .loop,
                flashAlert: momoAlerts.isFlashing
            )
            .help(momoAlerts.lastKind.map { "Alert: \($0.legendTitle)" } ?? "MOMO")
            alertLegend
            if surface.route == .dashboard {
                Button {
                    surface.expanded.toggle()
                } label: {
                    Image(systemName: surface.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .barBoyIconButton()
                .help(surface.expanded ? "Contract" : "Expand")
            }
            Button {
                surface.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .barBoyIconButton()
            .help("Settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .barBoyIconButton()
            .help("Quit MOMO")
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .barBoyIconButton()
            .help("Refresh observed activity")
        }
        .padding(.horizontal, 14).frame(height: 55)
    }

    private var alertLegend: some View {
        HStack(spacing: 6) {
            legendChip(color: BarBoyStyle.coral, title: "FAILED")
            legendChip(color: BarBoyStyle.amber, title: "NEEDS YOU")
            legendChip(color: BarBoyStyle.coral.opacity(0.85), title: "USAGE")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alert legend: failed, needs you, usage low")
    }

    private func legendChip(color: Color, title: String) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(color).frame(width: 6, height: 6)
            Text(title).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        let waiting = snapshots.reduce(0) { $0 + $1.waitingCount }
        return waiting > 0 ? "\(waiting) NEED YOU" : "\(snapshots.reduce(0) { $0 + $1.activeCount }) LIVE"
    }

    private var statusColor: Color { snapshots.contains(where: { $0.hasErrorOrApproval }) ? BarBoyStyle.coral : .secondary }

    private var providerRail: some View {
        Group {
            if railSnapshots.isEmpty {
                HStack(spacing: 10) {
                    Text(preferences.trackingOnboardingSeen
                          ? "No providers allowed yet."
                          : "Finish onboarding to populate this strip.")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(preferences.trackingOnboardingSeen ? "CONNECT PROVIDERS" : "START ONBOARDING") {
                        onboardingStartStep = preferences.trackingOnboardingSeen ? .connectProviders : .welcome
                        showOnboarding = true
                        surface.expanded = true
                    }
                    .barBoyButton()
                }
                .padding(.horizontal, 12)
            } else {
                GeometryReader { geo in
                    let widths = ProviderStripLayout.equalCardWidth(
                        availableWidth: geo.size.width - 24,
                        count: railSnapshots.count
                    )
                    HStack(spacing: ProviderStripLayout.spacing) {
                        ForEach(railSnapshots) { snapshot in
                            ProviderCard(
                                snapshot: snapshot,
                                expanded: surface.usesExpandedSize || showsOverview,
                                selected: surface.selectedProvider == snapshot.provider,
                                width: widths
                            ) {
                                surface.selectProvider(surface.selectedProvider == snapshot.provider ? nil : snapshot.provider)
                                if surface.route == .dashboard { surface.trackerTab = .activity }
                            }
                            .frame(width: widths)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: surface.usesExpandedSize || showsOverview ? 91 : 68)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(TrackerTab.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { surface.trackerTab = item }
                } label: {
                    Label(item.title.uppercased(), systemImage: item.symbol)
                        .font(BarBoyStyle.navLabel)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(Rectangle())
                        .foregroundStyle(surface.trackerTab == item ? BarBoyStyle.inverseInk : Color.primary)
                        .background(surface.trackerTab == item ? Color.primary : .clear)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }.padding(4)
    }

    private var routeHeader: some View {
        HStack(spacing: 9) {
            Button { surface.goBack() } label: {
                Label("BACK", systemImage: "chevron.left")
                    .font(BarBoyStyle.navLabel)
                    .frame(width: 100, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            Text(routeTitle).font(BarBoyStyle.sectionLabel)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private var routeTitle: String {
        switch surface.route {
        case .dashboard: "TRACKING"
        case .settings: "SETTINGS"
        case .session: "SESSION DETAILS"
        case let .usage(provider): "\(provider.name.uppercased()) USAGE"
        case .talk: "TALK"
        }
    }

    @ViewBuilder private var routedContent: some View {
        switch surface.route {
        case .dashboard, .settings:
            EmptyView()
        case let .session(id):
            if let session = sessions.first(where: { $0.id == id }) {
                SessionDetailView(session: session)
            } else {
                Text("This session is no longer available.")
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(.secondary)
                    .padding(18)
            }
		case let .usage(provider):
            UsageCaptureView(provider: provider)
        case .talk:
            ScrollView {
                TalkPanelView(onDismiss: { surface.goBack() })
                    .frame(maxWidth: .infinity)
                    .padding(12)
            }
        }
    }

    private var activity: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITY").font(BarBoyStyle.sectionLabel)
                Spacer()
                Text("READ ONLY").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }
            if preferences.prefersBrainTips() {
                Text("Tip: Brain keeps prompts and project folders on-device — open the Brain tab when you want vault links.")
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sessions", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(9).background(BarBoyStyle.surface).overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            LazyVStack(spacing: 6) {
                ForEach(Array(sessions.filter { surface.selectedProvider == nil || $0.provider == surface.selectedProvider }.prefix(surface.usesExpandedSize || showsOverview ? pageSize : 3))) { session in
                    Button { surface.openSession(session) } label: { TrackingSessionRow(session: session) }
                        .buttonStyle(.plain)
                }
                if sessions.isEmpty { Text("No recorded activity yet.").font(BarBoyStyle.bodySmall).foregroundStyle(.secondary).padding(.vertical, 20) }
                if (surface.usesExpandedSize || showsOverview) && sessions.count > pageSize {
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
                Text(preferences.prefersUsageTips()
                     ? "Connect allowed providers, then Confirm usage from the official page when ready. A dash means MOMO has no verified value."
                     : "Connect any allowed provider with an official usage page. Preview before save. A dash means MOMO has no verified value.")
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(.secondary)
                if usageSnapshots.isEmpty {
                    Text("No providers allowed yet. Connect providers in Settings or finish onboarding.")
                        .font(BarBoyStyle.bodySmall)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Button("CONNECT PROVIDERS") {
                        onboardingStartStep = .connectProviders
                        showOnboarding = true
                    }
                    .barBoyButton()
                }
                ForEach(usageSnapshots) { snapshot in
                    UsageCard(
                        snapshot: snapshot,
                        observations: monitor.usageObservations.filter { $0.provider == snapshot.provider }
                    ) {
                        surface.openUsage(snapshot.provider)
                    }
                }
            }.padding(12)
        }
    }

    private var brain: some View {
        // Brain content can exceed the panel; keep chrome sticky by scrolling only this body.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                if preferences.prefersBrainTips() {
                    Text(preferences.onboardingIntents.contains(.projectFolders)
                         ? "Project folders and prompts stay local — connect a vault and link folders you already use."
                         : "Organizing prompts stays on-device in Brain. Ask only when you choose; nothing runs idle.")
                        .font(BarBoyStyle.bodySmall)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }
                BrainWorkspaceView(refreshOnAppear: false)
            }
        }
    }
}

private struct ProviderCard: View {
    let snapshot: ProviderSnapshot
    let expanded: Bool
    let selected: Bool
    let width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: expanded ? 5 : 3) {
                HStack { ProviderMark(provider: snapshot.provider, size: expanded ? 22 : 17, active: snapshot.activeCount > 0); Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.microLabel); Spacer(minLength: 0); Text(snapshot.isInstalled ? (snapshot.activeCount > 0 ? "LIVE" : "IDLE") : "UNAVAILABLE").font(BarBoyStyle.microLabel).foregroundStyle(.secondary) }
                Text(snapshot.statusLabel).font(BarBoyStyle.bodySmall).lineLimit(1)
                if expanded { Text("\(snapshot.tokenLabel) · \(snapshot.resetLabel(now: .now))").font(BarBoyStyle.microLabel).foregroundStyle(.secondary).lineLimit(1) }
                if let percent = snapshot.recordedQuota?.percent ?? snapshot.recordedQuotas.first?.percent {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { index in
                            Rectangle().fill(index < Int(ceil(Double(percent) / 25.0)) ? (percent >= 90 ? BarBoyStyle.coral : BarBoyStyle.amber) : BarBoyStyle.hairline.opacity(0.45)).frame(height: 3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
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
    let observations: [ProviderUsageObservation]
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.rowTitle)
                Spacer()
                Text(snapshot.usageText.uppercased()).font(BarBoyStyle.microLabel)
            }
            HStack {
                Text(snapshot.quotaLabels.joined(separator: "  ·  "))
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.resetLabel(now: .now))
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            }
            if !observations.isEmpty {
                ForEach(observations) { observation in
                    HStack(spacing: 8) {
                        Text(observation.metric.uppercased())
                            .font(BarBoyStyle.microLabel)
                            .lineLimit(1)
                        Spacer()
                        Text(observation.percentage.map { "\($0)%" } ?? "—")
                            .font(BarBoyStyle.microLabel)
                        Text(observation.provenance.label)
                            .font(BarBoyStyle.microLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if snapshot.provider.supportsUsageCapture {
                Button("CONNECT USAGE", action: onConnect).barBoyButton()
            } else {
                Text("No official usage page connected yet.")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
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
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(BarBoyStyle.panel)
    }

    private var verifiedOriginalURL: URL? {
        guard session.provider == .codex else { return nil }
        return CodexDesktopConnection.taskURL(source: session.sourceURL)
    }
}
