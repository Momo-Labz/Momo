import AppKit
import SwiftUI

private extension TrackerTab {
    var symbol: String {
        switch self {
        case .activity: "waveform.path.ecg"
        case .usage: "chart.bar.fill"
        case .brain: "circle.hexagongrid.fill"
        case .upgrade: "sparkles"
        }
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
    @ObservedObject private var voiceInput = VoiceInput.shared
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

    private var sessions: [AgentSession] {
        let all = snapshots.flatMap(\.sessions).sorted { $0.updatedAt > $1.updatedAt }
        let limited = SessionPresentation.topChatsPerProvider(all, limit: SessionPresentation.maxChatsPerProvider)
        guard !debouncedSearch.isEmpty else { return limited }
        return limited.filter {
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
                    tabBar
                    Divider().opacity(0.55)
                    Group {
                        if loading { LoadingSkeleton() }
                        else {
                            switch surface.trackerTab {
                            case .activity: activity
                            case .usage: usage
                            case .brain: brain
                            case .upgrade: upgrade
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
            .disabled(needsOnboarding)

            if needsOnboarding {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { /* block chrome until Welcome finishes */ }
                ScrollView {
                    TrackingOnboardingView(
                        initialStep: preferences.needsTrackingOnboarding ? .welcome : onboardingStartStep,
                        initialIntents: preferences.onboardingIntents,
                        initialAllowed: [],
                        onFinish: finishOnboarding,
                        onDismiss: preferences.needsTrackingOnboarding ? nil : { showOnboarding = false },
                        onTalkTrial: { showTalkTrial = true },
                        onProviderConnected: { allowed in
                            for provider in allowed {
                                _ = preferences.connectDesktopProvider(
                                    provider,
                                    trackUsage: true,
                                    trackRecentPrompts: true,
                                    momoPlus: TalkService.shared.quota.momoPlusEntitled
                                )
                            }
                            monitor.setAuthorizedProviders(preferences.enabledProviders)
                            monitor.refresh()
                        }
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
            MomoFeedback.shortcutPressed()
            toggleTalk(fromKeyboard: true)
        }
    }

    private func toggleTalk(fromKeyboard: Bool = false) {
        if preferences.needsTrackingOnboarding {
            showOnboarding = true
            onboardingStartStep = .welcome
            surface.expanded = true
            return
        }
        if voiceInput.isActive {
            voiceInput.stop()
        } else {
            surface.openTalk(fromKeyboard: fromKeyboard)
            voiceInput.prepare(.talk)
            Task { await voiceInput.start() }
        }
    }

    private func finishOnboarding(intents: Set<OnboardingIntent>, allowed: Set<AIProvider>) {
        // Never complete onboarding without ≥1 verified provider.
        guard !allowed.isEmpty else {
            showOnboarding = true
            onboardingStartStep = .connectProviders
            return
        }
        preferences.setOnboardingIntents(intents)
        preferences.syncRefreshIntervalFromDefaults()
        for provider in allowed {
            _ = preferences.connectDesktopProvider(
                provider,
                trackUsage: true,
                trackRecentPrompts: true,
                momoPlus: TalkService.shared.quota.momoPlusEntitled
            )
        }
        preferences.setAllowedTrackingProviders(allowed, markOnboardingSeen: true)
        guard !preferences.needsTrackingOnboarding else {
            showOnboarding = true
            onboardingStartStep = .connectProviders
            return
        }
        monitor.setAuthorizedProviders(preferences.enabledProviders)
        monitor.refresh()
        showOnboarding = false
        showTalkTrial = false
        onboardingStartStep = .welcome
        if preferences.prefersBrainTips() {
            surface.trackerTab = .brain
        } else {
            surface.trackerTab = .activity
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AnimatedMomoMark(size: 27, animated: momoAlerts.isFlashing, motion: .alert, flashAlert: momoAlerts.isFlashing)
            VStack(alignment: .leading, spacing: 1) {
                Text("MOMO LABZ").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                Text("TRACKR").font(BarBoyStyle.display).tracking(0.8)
            }
            Spacer(minLength: 8)
            talkShortcutAffordance
            Text(statusText).font(BarBoyStyle.microLabel).foregroundStyle(statusColor)
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
            Button(action: { toggleTalk() }) {
                Image(systemName: voiceInput.isActive ? "mic.fill" : "mic")
            }
            .barBoyIconButton()
            .foregroundStyle(voiceInput.isActive ? BarBoyStyle.coral : Color.primary)
            .help("Talk (\(GlobalShortcutService.shared.bindings[.talk]?.label ?? "⌃⌥ T"))")
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
            legendChip(color: BarBoyStyle.errorOrange, title: "ERROR")
            legendChip(color: BarBoyStyle.amber, title: "NEEDS YOU")
            legendChip(color: BarBoyStyle.coral.opacity(0.85), title: "USAGE")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alert legend: error, needs you, usage low")
    }

    private var talkShortcutAffordance: some View {
        Button(action: { toggleTalk() }) {
            HStack(spacing: 5) {
                Image(systemName: voiceInput.isActive ? "mic.fill" : "waveform")
                Text("TALK \(GlobalShortcutService.shared.bindings[.talk]?.label ?? "⌃⌥ T")")
            }
            .font(BarBoyStyle.microLabel)
            .foregroundStyle(voiceInput.isActive ? BarBoyStyle.coral : .secondary)
        }
        .buttonStyle(.plain)
        .help("Talk shortcut")
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
                    Text(preferences.allowedTrackingProviders.isEmpty
                          ? "No desktop apps connected yet."
                          : "Finish onboarding to keep these apps on the strip.")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(preferences.trackingOnboardingSeen ? "CONNECT APPS" : "START ONBOARDING") {
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
                                observations: monitor.usageObservations.filter { $0.provider == snapshot.provider },
                                expanded: surface.usesExpandedSize || showsOverview,
                                selected: surface.selectedProvider == snapshot.provider,
                                width: widths
                            ) {
                                surface.selectProvider(surface.selectedProvider == snapshot.provider ? nil : snapshot.provider)
                                if surface.route == .dashboard { surface.trackerTab = .activity }
                            }
                            .frame(width: widths)
                            .clipped()
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: surface.usesExpandedSize || showsOverview ? 118 : 96)
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
        case .dashboard: "TRACKR"
        case .settings: "SETTINGS"
        case .session: "SESSION DETAILS"
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
                let visible = sessions.filter { surface.selectedProvider == nil || $0.provider == surface.selectedProvider }
                ForEach(visible) { session in
                    Button { surface.openSession(session) } label: { TrackingSessionRow(session: session) }
                        .buttonStyle(.plain)
                }
                if visible.isEmpty {
                    Text(surface.selectedProvider == nil
                         ? "No recorded activity yet."
                         : "No recent chats for \(surface.selectedProvider!.name) (showing up to \(SessionPresentation.maxChatsPerProvider)).")
                        .font(BarBoyStyle.bodySmall)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                }
            }
        }.padding(12)
        }
    }

    /// Local-only usage tab: Claude Code `/usage`-shaped meters. No chat list (Activity owns chats).
    private var usage: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("USAGE").font(BarBoyStyle.sectionLabel)
                    Spacer()
                    Text("LOCAL ONLY").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                }
                Text("Approximate, based on local sessions and quota caches on this Mac — never invented. Empty bars mean no readable local usage.")
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if railSnapshots.isEmpty {
                    Text("Connect a desktop app to see local usage.")
                        .font(BarBoyStyle.bodySmall)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(railSnapshots) { snapshot in
                        ClaudeStyleUsageBlock(
                            snapshot: snapshot,
                            observations: monitor.usageObservations.filter { $0.provider == snapshot.provider }
                        )
                    }
                }
            }
            .padding(12)
        }
    }

    private var upgrade: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(TalkQuotaStore.UpsellCopy.upgradeHeadline)
                    .font(BarBoyStyle.display)
                Text(TalkQuotaStore.UpsellCopy.upgradePitch)
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    upgradeRow(TalkQuotaStore.UpsellCopy.benefitTalk, unlocked: TalkService.shared.quota.momoPlusEntitled)
                    upgradeRow(TalkQuotaStore.UpsellCopy.benefitProviders, unlocked: TalkService.shared.quota.momoPlusEntitled)
                    upgradeRow(TalkQuotaStore.UpsellCopy.benefitAnalytics, unlocked: TalkService.shared.quota.momoPlusEntitled)
                }
                .padding(12)
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))

                if TalkService.shared.quota.momoPlusEntitled {
                    Text("MOMO+ is on for this Mac (soft unlock).")
                        .font(BarBoyStyle.bodySmall)
                        .foregroundStyle(.secondary)
                    Button("Turn off MOMO+ (testing)") {
                        TalkService.shared.quota.setMomoPlusEntitled(false)
                    }
                    .barBoyButton()
                } else {
                    Text(TalkQuotaStore.UpsellCopy.optionalOneLiner)
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                    Button(TalkQuotaStore.UpsellCopy.primaryButton) {
                        TalkService.shared.quota.setMomoPlusEntitled(true)
                    }
                    .barBoyButton()
                }

                Text("Connected apps: \(preferences.allowedTrackingProviders.count)"
                     + (TalkService.shared.quota.momoPlusEntitled
                        ? " · unlimited"
                        : " / \(DesktopAppCatalog.freeProviderLimit) free"))
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private func upgradeRow(_ title: String, unlocked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(unlocked ? Color.primary : .secondary)
            Text(title)
                .font(BarBoyStyle.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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
    let observations: [ProviderUsageObservation]
    let expanded: Bool
    let selected: Bool
    let width: CGFloat?
    let action: () -> Void

    private var windows: (fiveHour: UsagePeekMetric, weekly: UsagePeekMetric) {
        UsagePeekMapping.map(observations: observations, snapshot: snapshot)
    }

    private var statusLine: String {
        if let urgent = snapshot.sessions.first(where: { $0.attention.isUrgent }) {
            return "ISSUE · \(urgent.title)"
        }
        if snapshot.activeCount > 0 { return "LIVE · \(snapshot.activeCount)" }
        if snapshot.isInstalled { return snapshot.sessions.isEmpty ? "IDLE" : snapshot.statusLabel }
        return "NOT INSTALLED"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: expanded ? 5 : 3) {
                HStack(spacing: 4) {
                    ProviderMark(provider: snapshot.provider, size: expanded ? 22 : 17, active: snapshot.activeCount > 0)
                    Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.microLabel).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(snapshot.activeCount > 0 ? "LIVE" : (snapshot.isInstalled ? "IDLE" : "—"))
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                }
                Text(statusLine)
                    .font(BarBoyStyle.bodySmall)
                    .lineLimit(1)
                DualUsageMeters(
                    fiveHour: windows.fiveHour,
                    weekly: windows.weekly,
                    compact: !expanded
                )
            }
            .padding(ProviderStripLayout.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(selected ? BarBoyStyle.surface.opacity(1.8) : BarBoyStyle.surface)
            .overlay(Rectangle().stroke(snapshot.hasErrorOrApproval ? BarBoyStyle.coral : selected ? Color.primary : BarBoyStyle.hairline, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .accessibilityLabel("\(snapshot.provider.name), \(statusLine)")
    }
}

/// Claude Code `/usage`-inspired layout for one connected provider. No activity chat list.
/// Cache / FDA checks load off the main thread so the Usage tab cannot freeze the panel.
private struct ClaudeStyleUsageBlock: View {
    let snapshot: ProviderSnapshot
    let observations: [ProviderUsageObservation]
    var now: Date = .now

    @State private var artifact = LocalUsageDetail()
    @State private var privacyBlocked = false
    @State private var isLoadingArtifact = true

    private var mapped: (fiveHour: UsagePeekMetric, weekly: UsagePeekMetric) {
        let base = UsagePeekMapping.map(observations: observations, snapshot: snapshot, now: now)
        let five: UsagePeekMetric
        if let window = artifact.fiveHour {
            five = UsagePeekMetric(percentage: Int(window.percent.rounded()), resetsAt: window.resetsAt)
        } else {
            five = base.fiveHour
        }
        let weekly: UsagePeekMetric
        if let window = artifact.weekly {
            weekly = UsagePeekMetric(percentage: Int(window.percent.rounded()), resetsAt: window.resetsAt)
        } else {
            weekly = base.weekly
        }
        return (five, weekly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderMark(provider: snapshot.provider, size: 22, active: snapshot.activeCount > 0)
                Text(snapshot.provider.name.uppercased()).font(BarBoyStyle.microLabel)
                Spacer(minLength: 0)
                if isLoadingArtifact {
                    ProgressView().controlSize(.mini)
                }
                Text(snapshot.activeCount > 0 ? "LIVE" : (snapshot.isInstalled ? "IDLE" : "—"))
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            }

            if isLoadingArtifact && artifact.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading local usage…")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                }
            }

            if artifact.hasSessionStats {
                sessionStatsSection
            }

            limitSection(
                title: "Current session",
                subtitle: "5-hour window when recorded",
                metric: mapped.fiveHour
            )
            limitSection(
                title: "Current week",
                subtitle: "All models when recorded",
                metric: mapped.weekly
            )

            if !isLoadingArtifact,
               mapped.fiveHour.percentage == nil,
               mapped.weekly.percentage == nil,
               !artifact.hasSessionStats {
                if privacyBlocked {
                    Text(LocalUsageArtifactReader.privacyGuidance(for: snapshot.provider))
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(BarBoyStyle.coral)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Privacy Settings") {
                        LocalUsageArtifactReader.openPrivacySettings()
                    }
                    .barBoyButton()
                } else {
                    Text(emptyGuidance)
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("What’s contributing to your limits usage?")
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
            Text("Approximate, based on local sessions on this machine — does not include usage from other devices.")
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .task(id: "\(snapshot.provider.rawValue)-\(snapshot.updatedAt.timeIntervalSince1970)") {
            await reloadArtifact()
        }
    }

    @MainActor
    private func reloadArtifact() async {
        isLoadingArtifact = true
        let provider = snapshot.provider
        let capturedNow = now
        let loaded = await Task.detached(priority: .userInitiated) {
            let detail = LocalUsageArtifactReader.detail(for: provider, now: capturedNow)
            let blocked = LocalUsageArtifactReader.isSessionRootPrivacyBlocked(provider)
            return (detail, blocked)
        }.value
        artifact = loaded.0
        privacyBlocked = loaded.1
        isLoadingArtifact = false
    }

    private var emptyGuidance: String {
        switch snapshot.provider {
        case .claude:
            return "No readable Claude usage cache yet (~/.claude or /tmp/claude statusline cache). Bars and resets appear when that file exists."
        case .cursor:
            return "Cursor transcripts do not expose account %. Bars appear only if a local usage-cache.json is present."
        case .codex:
            return "No recorded Codex rate_limits in recent local sessions yet."
        default:
            return "No readable local usage for \(snapshot.provider.name)."
        }
    }

    @ViewBuilder
    private var sessionStatsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session").font(BarBoyStyle.sectionLabel)
            if let cost = artifact.totalCostUSD {
                statRow("Total cost", String(format: "$%.4f", cost))
            }
            if let api = artifact.durationAPISeconds {
                statRow("Total duration (API)", formatDuration(api))
            }
            if let wall = artifact.durationWallSeconds {
                statRow("Total duration (wall)", formatDuration(wall))
            }
            if artifact.linesAdded != nil || artifact.linesRemoved != nil {
                let added = artifact.linesAdded.map(String.init) ?? "—"
                let removed = artifact.linesRemoved.map(String.init) ?? "—"
                statRow("Total code changes", "\(added) lines added, \(removed) lines removed")
            }
            if artifact.inputTokens != nil || artifact.outputTokens != nil
                || artifact.cacheReadTokens != nil || artifact.cacheWriteTokens != nil {
                Text("Usage").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                if let v = artifact.inputTokens { statRow("input", "\(v) tokens") }
                if let v = artifact.outputTokens { statRow("output", "\(v) tokens") }
                if let v = artifact.cacheReadTokens { statRow("cache read", "\(v) tokens") }
                if let v = artifact.cacheWriteTokens { statRow("cache write", "\(v) tokens") }
            }
        }
    }

    private func limitSection(title: String, subtitle: String, metric: UsagePeekMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(BarBoyStyle.sectionLabel)
                Spacer(minLength: 8)
                Text(metric.percentage.map { "\($0)% used" } ?? "— used")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(subtitle)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
            UsageMeter(percent: metric.percentage, alert: (metric.percentage ?? 0) >= 100, height: 10)
            if let reset = LocalUsageArtifactReader.resetCaption(metric.resetsAt, now: now) {
                Text(reset)
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(BarBoyStyle.bodySmall)
                .monospacedDigit()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded()))s" }
        if seconds < 3600 {
            let m = Int(seconds / 60)
            let s = Int(seconds.truncatingRemainder(dividingBy: 60))
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        let h = Int(seconds / 3600)
        let m = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
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
            HStack {
                ProviderMark(provider: session.provider, size: 34, active: session.isRunning)
                VStack(alignment: .leading) {
                    Text(session.provider.name.uppercased()).font(BarBoyStyle.microLabel)
                    Text(SessionPresentation.title(for: session)).font(BarBoyStyle.display)
                }
                Spacer()
            }
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
