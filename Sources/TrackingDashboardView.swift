import AppKit
import SwiftUI

private extension TrackerTab {
    var symbol: String {
        switch self {
        case .activity: "waveform.path.ecg"
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

    private var switcherProviders: [AIProvider] {
        preferences.trackingStripProviders()
    }

    var body: some View {
        ZStack {
            // Sticky chrome: header + provider strip + tabs stay put; only the tab body scrolls.
            VStack(spacing: 0) {
                header
                    .zIndex(2)
                providerRail
                    .zIndex(2)
                if !switcherProviders.isEmpty, switcherProviders.count <= DesktopAppCatalog.freeProviderLimit || !TalkService.shared.quota.momoPlusEntitled {
                    freeProviderSwitcher
                        .zIndex(2)
                }
                Divider().opacity(0.55)
                if surface.route == .dashboard {
                    tabBar
                    Divider().opacity(0.55)
                    Group {
                        if loading { LoadingSkeleton() }
                        else {
                            switch surface.trackerTab {
                            case .activity: activity
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

    /// One-click switch between Free (≤2) connected providers — icons + names.
    private var freeProviderSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(switcherProviders, id: \.self) { provider in
                let selected = surface.selectedProvider == provider
                Button {
                    surface.selectProvider(provider)
                    if surface.route == .dashboard { surface.trackerTab = .activity }
                } label: {
                    HStack(spacing: 6) {
                        ProviderMark(provider: provider, size: 16, active: selected || (monitor.snapshot(for: provider).activeCount > 0))
                        Text(provider.name.uppercased())
                            .font(BarBoyStyle.microLabel)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
                    .foregroundStyle(selected ? BarBoyStyle.inverseInk : Color.primary)
                    .background(selected ? Color.primary : BarBoyStyle.surface)
                    .overlay(Rectangle().stroke(selected ? Color.primary : BarBoyStyle.hairline, lineWidth: selected ? 1.5 : 1))
                }
                .buttonStyle(.plain)
                .help("Show \(provider.name) activity")
            }
            if switcherProviders.count == 1 {
                Text("Free · \(DesktopAppCatalog.freeProviderLimit - 1) slot left")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear {
            if surface.selectedProvider == nil, let first = switcherProviders.first {
                surface.selectProvider(first)
            } else if let selected = surface.selectedProvider, !switcherProviders.contains(selected) {
                surface.selectProvider(switcherProviders.first)
            }
        }
        .onChange(of: preferences.allowedTrackingProviders) { _, _ in
            if let selected = surface.selectedProvider, !switcherProviders.contains(selected) {
                surface.selectProvider(switcherProviders.first)
            } else if surface.selectedProvider == nil {
                surface.selectProvider(switcherProviders.first)
            }
        }
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
