import AppKit
import SwiftUI

enum TrackingOnboardingStep: Int, CaseIterable {
    case welcome
    case intents
    case connectProviders
    case preferences
    case talkTrial

    var railTitle: String {
        switch self {
        case .welcome: return "WELCOME"
        case .intents: return "INTENT"
        case .connectProviders: return "CONNECT"
        case .preferences: return "PREFS"
        case .talkTrial: return "TALK"
        }
    }
}

/// Welcome → intent → desktop-app allow → prefs → Talk trial.
/// Providers start empty; each click opens the desktop app and grants local tracking.
/// Mid-flow progress is checkpointed so TCC quit/relaunch resumes the same step.
struct TrackingOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: PreferencesStore
    @ObservedObject private var talkQuota = TalkService.shared.quota

    @State private var step: TrackingOnboardingStep
    @State private var intents: Set<OnboardingIntent>
    @State private var allowed: Set<AIProvider>
    @State private var permissionProvider: AIProvider?
    @State private var connectProgress: DesktopConnectProgress?
    @State private var pendingResult: DesktopConnectionVerifier.ConnectResult?
    @State private var connectTask: Task<Void, Never>?
    @State private var connectGeneration = 0
    @State private var allowUsage = true
    @State private var allowRecentPrompts = true
    @State private var plusGateMessage: String?
    @State private var selectedRefreshInterval = PreferencesStore.normalizedRefreshInterval(UserDefaults.standard.integer(forKey: "refreshIntervalSeconds.v1"))
    @State private var recordingTalkShortcut = false
    @AppStorage("notifyFailure") private var notifyFailure = true
    @AppStorage("notifyNeedsInput") private var notifyNeedsInput = true
    @AppStorage("notifyThreshold90") private var notifyThreshold90 = true
    @AppStorage("momoAlertSoundEnabled.v1") private var alertSoundEnabled = true

    var initialStep: TrackingOnboardingStep
    var onFinish: (_ intents: Set<OnboardingIntent>, _ allowed: Set<AIProvider>) -> Void
    var onDismiss: (() -> Void)?
    var onTalkTrial: (() -> Void)?
    /// Called when a provider is successfully connected so the strip can fill immediately.
    var onProviderConnected: ((_ allowed: Set<AIProvider>) -> Void)?

    init(
        initialStep: TrackingOnboardingStep = .welcome,
        initialIntents: Set<OnboardingIntent> = [],
        initialAllowed: Set<AIProvider> = [],
        initialPendingProvider: AIProvider? = nil,
        onFinish: @escaping (_ intents: Set<OnboardingIntent>, _ allowed: Set<AIProvider>) -> Void,
        onDismiss: (() -> Void)? = nil,
        onTalkTrial: (() -> Void)? = nil,
        onProviderConnected: ((_ allowed: Set<AIProvider>) -> Void)? = nil
    ) {
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)
        _intents = State(initialValue: initialIntents)
        // Resume mid-flow allow-list when TCC relaunched the app; otherwise start empty.
        _allowed = State(initialValue: initialAllowed)
        _permissionProvider = State(initialValue: initialPendingProvider)
        self.onFinish = onFinish
        self.onDismiss = onDismiss
        self.onTalkTrial = onTalkTrial
        self.onProviderConnected = onProviderConnected
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step != .welcome {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            step = TrackingOnboardingStep(rawValue: max(0, step.rawValue - 1)) ?? .welcome
                            cancelConnect()
                            permissionProvider = nil
                            plusGateMessage = nil
                            checkpoint()
                        }
                    } label: {
                        Label("BACK", systemImage: "chevron.left")
                            .font(BarBoyStyle.navLabel)
                            .frame(minWidth: 72, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            journeyRail
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Group {
                switch step {
                case .welcome: welcomeStep
                case .intents: intentsStep
                case .connectProviders: connectStep
                case .preferences: preferencesStep
                case .talkTrial: talkTrialStep
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: step)
        }
        .frame(maxWidth: 440)
        .background(BarBoyStyle.panel)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .onAppear { checkpoint() }
        .onChange(of: step) { _, _ in checkpoint() }
        .onChange(of: allowed) { _, _ in checkpoint() }
        .onChange(of: permissionProvider) { _, _ in checkpoint() }
        .onChange(of: intents) { _, _ in checkpoint() }
    }

    private var journeyRail: some View {
        HStack(spacing: 4) {
            ForEach(TrackingOnboardingStep.allCases, id: \.rawValue) { item in
                let active = item.rawValue <= step.rawValue
                Text(item.railTitle)
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(active ? BarBoyStyle.inverseInk : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(active ? Color.primary : BarBoyStyle.surface)
                    .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding step \(step.railTitle)")
    }

    private func checkpoint() {
        preferences.saveOnboardingProgress(
            step: step,
            intents: intents,
            partialAllowed: allowed,
            pendingProvider: permissionProvider
        )
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            AnimatedMomoMark(size: 64, animated: !reduceMotion)
            Text("MOMO")
                .font(BarBoyStyle.display)
                .tracking(1.2)
            Text("TRACKR")
                .font(BarBoyStyle.sectionLabel)
                .foregroundStyle(.secondary)
            Text("Open the Mac apps you already use. MOMO watches local sessions and usage caches on this machine — never browser cookies, never invented %.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                welcomeBeat("1", "Pick what you care about")
                welcomeBeat("2", "Connect Claude, Cursor, Grok Bot, and friends")
                welcomeBeat("3", "Preview defaults, then try Talk")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))

            primaryButton("Start setup") {
                allowed = []
                step = .intents
                checkpoint()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private func welcomeBeat(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(BarBoyStyle.inverseInk)
                .frame(width: 22, height: 22)
                .background(Color.primary)
            Text(title)
                .font(BarBoyStyle.rowTitle)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
        }
    }

    private var intentsStep: some View {
        VStack(spacing: 12) {
            Text("What do you want help with?")
                .font(BarBoyStyle.display)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                ForEach(Array(OnboardingIntent.allCases.enumerated()), id: \.element.id) { index, intent in
                    if index > 0 {
                        Divider().overlay(BarBoyStyle.hairline.opacity(0.7))
                    }
                    intentRow(intent)
                }
            }
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))

            primaryButton("Continue") {
                step = .connectProviders
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private func intentRow(_ intent: OnboardingIntent) -> some View {
        let selected = intents.contains(intent)
        return Button {
            if selected { intents.remove(intent) } else { intents.insert(intent) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.primary : .secondary)
                    .frame(width: 22, height: 22)
                Text(intent.title)
                    .font(BarBoyStyle.rowTitle)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(intent.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var connectStep: some View {
        VStack(spacing: 12) {
            Text(permissionProvider.map { "MOMO / CONNECT \($0.name.uppercased())" } ?? "Connect desktop apps")
                .font(BarBoyStyle.display)
                .multilineTextAlignment(.center)
            Text(permissionProvider == nil
                 ? "Installed apps rise to the top. Tap one to open it — MOMO never writes into the other .app. Usage Connected needs a real local %; Grok Bot can Allow activity when % is not published yet."
                 : "Keep this panel open while the desktop app launches. Sign in there if asked. MOMO only reads local files on this Mac.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let plusGateMessage {
                Text(plusGateMessage)
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(BarBoyStyle.coral)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let permissionProvider {
                verificationPanel(for: permissionProvider)
            } else {
                VStack(spacing: 8) {
                    ForEach(DesktopAppCatalog.onboardingConnectProviders()) { provider in
                        providerConnectButton(provider)
                    }
                }

                Button {
                    guard !allowed.isEmpty else { return }
                    step = .preferences
                } label: {
                    Text(allowed.isEmpty ? "Connect at least one app to continue" : "Continue with \(allowed.count) connected")
                        .font(BarBoyStyle.navLabel)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                        .foregroundStyle(BarBoyStyle.inverseInk)
                        .background(allowed.isEmpty ? Color.primary.opacity(0.35) : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(allowed.isEmpty)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose your defaults")
                .font(BarBoyStyle.display)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("You can change these in Settings any time.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh interval").font(BarBoyStyle.sectionLabel)
                Picker("Refresh interval", selection: $selectedRefreshInterval) {
                    Text("1 min").tag(60)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                    Text("30 min").tag(1_800)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Talk shortcut").font(BarBoyStyle.sectionLabel)
                Button("Set Talk shortcut (\(GlobalShortcutService.shared.bindings[.talk]?.label ?? "⌃⌥ T"))") {
                    recordingTalkShortcut = true
                }
                .barBoyButton()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications").font(BarBoyStyle.sectionLabel)
                Toggle("Session stopped / error", isOn: $notifyFailure).toggleStyle(.checkbox)
                Toggle("Needs you", isOn: $notifyNeedsInput).toggleStyle(.checkbox)
                Toggle("Usage running low", isOn: $notifyThreshold90).toggleStyle(.checkbox)
                Toggle("Play notification sound", isOn: $alertSoundEnabled).toggleStyle(.checkbox)
                Button("Open Notifications Settings") {
                    checkpoint()
                    SystemSettingsDeepLink.openNotifications()
                }
                .barBoyButton()
                Text("If macOS asks to quit & reopen MOMO after Allow, setup resumes here.")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryButton("Continue") {
                UserDefaults.standard.set(selectedRefreshInterval, forKey: "refreshIntervalSeconds.v1")
                preferences.syncRefreshIntervalFromDefaults()
                step = .talkTrial
                checkpoint()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .sheet(isPresented: $recordingTalkShortcut) {
            VStack(spacing: 16) {
                Text("Press a shortcut for Talk").font(.headline)
                Text("Include Control, Option or Command. Escape cancels.").font(.caption)
                ShortcutRecorder { binding in
                    if let binding {
                        _ = GlobalShortcutService.shared.update(binding, for: .talk)
                        _ = GlobalShortcutService.shared.setEnabled(true, for: .talk)
                    }
                    recordingTalkShortcut = false
                }
                .frame(width: 350, height: 35)
                Button("Cancel") { recordingTalkShortcut = false }
            }
            .padding(24)
        }
    }

    private var talkTrialStep: some View {
        VStack(spacing: 12) {
            Text("Hands-free Talk")
                .font(BarBoyStyle.display)
                .multilineTextAlignment(.center)
            Text("Ask MOMO about usage and what’s running — answers stay on this Mac via local Ollama. Never invents %. Free includes this guided trial plus 3 later asks.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if VoicePermission.microphoneBlockReason() != nil {
                Text(VoicePermission.settingsGuidance(for: .microphoneDenied))
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Microphone Settings") {
                    checkpoint()
                    SystemSettingsDeepLink.openMicrophone()
                }
                .barBoyButton()
            }

            if onTalkTrial != nil {
                primaryButton("Try Talk (1 free)") {
                    checkpoint()
                    onTalkTrial?()
                }
            }

            Button("Skip for now") {
                guard !allowed.isEmpty else { return }
                onFinish(intents, allowed)
            }
            .font(BarBoyStyle.navLabel)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            .buttonStyle(.plain)
            .disabled(allowed.isEmpty)

            primaryButton("Finish setup") {
                guard !allowed.isEmpty else { return }
                onFinish(intents, allowed)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private func providerConnectButton(_ provider: AIProvider) -> some View {
        let isAllowed = allowed.contains(provider)
        let match = DesktopAppCatalog.match(for: provider)
        return Button {
            plusGateMessage = nil
            if isAllowed { return }
            let already = allowed.contains(provider)
            guard MomoPlusGate.canAllowAdditionalProvider(currentAllowedCount: allowed.count, alreadyAllowed: already)
                    || talkQuota.momoPlusEntitled else {
                plusGateMessage = "Free includes up to \(DesktopAppCatalog.freeProviderLimit) providers. Unlock more on the Upgrade tab with MOMO+."
                return
            }
            allowUsage = !provider.supportsActivityOnlyConnect
            allowRecentPrompts = true
            permissionProvider = provider
            beginVerification(for: provider, openApp: match.isInstalled)
        } label: {
            HStack(spacing: 12) {
                ProviderMark(provider: provider, size: 28, active: isAllowed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAllowed ? "\(provider.connectButtonTitle) · Connected" : provider.connectButtonTitle)
                        .font(BarBoyStyle.rowTitle)
                        .foregroundStyle(Color.primary)
                    Text(match.isInstalled
                         ? "\(match.displayName) · Ready to open"
                         : "Not installed — open download page")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isAllowed ? "checkmark" : (match.isInstalled ? "arrow.up.forward.app" : "arrow.down.app"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(isAllowed ? Color.primary : BarBoyStyle.hairline, lineWidth: isAllowed ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.connectButtonTitle)
    }

    private var isConnecting: Bool {
        guard let connectProgress else { return false }
        return !connectProgress.isTerminal
    }

    private func verificationPanel(for provider: AIProvider) -> some View {
        let match = DesktopAppCatalog.match(for: provider)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProviderMark(provider: provider, size: 34, active: canCommit(provider) || canCommitActivityOnly(provider))
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONNECT \(provider.name.uppercased())")
                        .font(BarBoyStyle.sectionLabel)
                    Text(match.isInstalled ? match.displayName : "Desktop app not found")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(providerConnectBlurb(provider))
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                connectGuideRow(
                    number: "1",
                    title: match.isInstalled ? "\(match.displayName) detected" : "Install \(DesktopAppCatalog.displayName(for: provider))",
                    detail: match.isInstalled
                        ? "MOMO opens the app via Launch Services — it never writes into the .app bundle."
                        : "Install the Mac app, then Retry. MOMO will not invent a connection.",
                    state: match.isInstalled ? .done : .attention
                )
                Divider().overlay(BarBoyStyle.hairline.opacity(0.7))
                connectGuideRow(
                    number: "2",
                    title: "Open & sign in if needed",
                    detail: "Finish any login prompts inside \(match.displayName). Stay signed in so local session files appear.",
                    state: guideState(for: .signIn)
                )
                Divider().overlay(BarBoyStyle.hairline.opacity(0.7))
                connectGuideRow(
                    number: "3",
                    title: provider.supportsActivityOnlyConnect ? "Local activity check" : "Local usage % check",
                    detail: provider.supportsActivityOnlyConnect
                        ? "Account % is not published locally yet. MOMO looks for sessions; usage bars stay — until a cache exists."
                        : "Reads local caches / CLI / rate_limits only. No cookies, no invented percentages.",
                    state: guideState(for: .usage)
                )
            }
            .background(BarBoyStyle.panel)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))

            if !match.isInstalled, let url = provider.desktopInstallURL {
                Button("Open download page") {
                    NSWorkspace.shared.open(url)
                }
                .barBoyButton()
            }

            Toggle(isOn: $allowUsage) {
                Text(provider.supportsActivityOnlyConnect
                     ? "Track usage % when a local meter appears"
                     : "Track usage %")
                    .font(BarBoyStyle.rowTitle)
            }
            .toggleStyle(.checkbox)
            .disabled(isConnecting || provider.supportsActivityOnlyConnect)

            Toggle(isOn: $allowRecentPrompts) {
                Text("Track recent activity / prompts").font(BarBoyStyle.rowTitle)
            }
            .toggleStyle(.checkbox)
            .disabled(isConnecting)

            connectStatusBlock(for: provider)

            HStack(spacing: 8) {
                Button("Back") {
                    cancelConnect()
                    permissionProvider = nil
                }
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .buttonStyle(.plain)

                Button(match.isInstalled ? "Retry" : "Check again") {
                    beginVerification(for: provider, openApp: match.isInstalled)
                }
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .buttonStyle(.plain)
                .disabled(isConnecting)

                if canCommit(provider) {
                    Button("Allow") {
                        commitVerifiedConnection(provider, activityOnly: false)
                    }
                    .font(BarBoyStyle.navLabel)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                    .foregroundStyle(BarBoyStyle.inverseInk)
                    .background(Color.primary)
                    .buttonStyle(.plain)
                    .help("Save this provider — usage % is readable.")
                } else if canCommitActivityOnly(provider) {
                    Button("Allow activity") {
                        allowUsage = false
                        allowRecentPrompts = true
                        commitVerifiedConnection(provider, activityOnly: true)
                    }
                    .font(BarBoyStyle.navLabel)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                    .foregroundStyle(BarBoyStyle.inverseInk)
                    .background(Color.primary)
                    .buttonStyle(.plain)
                    .help("Track local activity. Usage % stays unavailable until a cache exists.")
                } else {
                    Button(provider.supportsActivityOnlyConnect ? "Allow activity" : "Allow") {
                        // Disabled placeholder keeps layout stable.
                    }
                    .font(BarBoyStyle.navLabel)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                    .foregroundStyle(BarBoyStyle.inverseInk)
                    .background(Color.primary.opacity(0.35))
                    .buttonStyle(.plain)
                    .disabled(true)
                    .help(provider.supportsActivityOnlyConnect
                          ? "Open Grok Bot, sign in, then Retry."
                          : "Allow stays off until Retry finds readable usage %.")
                }
            }
        }
        .padding(14)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: connectProgress?.title)
    }

    private enum GuidePhase { case signIn, usage }
    private enum GuideState { case pending, active, done, attention }

    private func guideState(for phase: GuidePhase) -> GuideState {
        guard let connectProgress else { return .pending }
        switch phase {
        case .signIn:
            switch connectProgress {
            case .openingApp, .waitingForSignIn: return .active
            case .searchingUsage, .connected, .notReady, .needsPermission: return .done
            case .failed, .timedOut: return .attention
            }
        case .usage:
            switch connectProgress {
            case .openingApp, .waitingForSignIn: return .pending
            case .searchingUsage: return .active
            case .connected: return .done
            case .notReady, .needsPermission, .failed, .timedOut: return .attention
            }
        }
    }

    private func connectGuideRow(number: String, title: String, detail: String, state: GuideState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(state == .pending ? .secondary : BarBoyStyle.inverseInk)
                .frame(width: 22, height: 22)
                .background(state == .pending ? BarBoyStyle.raised : Color.primary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(BarBoyStyle.rowTitle)
                    if state == .active {
                        ProgressView().controlSize(.mini)
                    } else if state == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(detail)
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .opacity(state == .pending ? 0.72 : 1)
    }

    private func providerConnectBlurb(_ provider: AIProvider) -> String {
        switch provider {
        case .claude:
            return "MOMO opens Claude.app, then looks for Claude Code usage caches / `ccusage`. Menu-bar % inside Claude alone is not a file other apps can read."
        case .cursor:
            return "MOMO opens Cursor.app and looks for a local usage-cache.json. Transcripts alone do not expose account %."
        case .grok:
            return "MOMO opens Grok Bot.app for local activity. Account usage % is not published in a supported local cache yet — Allow activity keeps bars honest as —."
        case .codex:
            return "MOMO opens ChatGPT / Codex and reads rate_limits from ~/.codex/sessions after you run one chat."
        case .gemini:
            return "Gemini local usage % is not published yet. Activity-only connect stays honest when the desktop app is available."
        }
    }

    @ViewBuilder
    private func connectStatusBlock(for provider: AIProvider) -> some View {
        if let connectProgress {
            HStack(alignment: .top, spacing: 10) {
                if connectProgress.showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: connectStatusSymbol(connectProgress))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(connectProgress.isVerified ? Color.primary : BarBoyStyle.coral)
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectProgress.title)
                        .font(BarBoyStyle.rowTitle)
                    Text(connectStatusDetail(connectProgress, provider: provider))
                        .font(BarBoyStyle.bodySmall)
                        .foregroundStyle(connectProgress.isVerified ? Color.primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .connected(let honesty) = connectProgress,
                       case .usageFound(let session, let week) = honesty.outcome {
                        HStack(spacing: 12) {
                            Text(session.map { "Session \($0)%" } ?? "Session —")
                                .font(BarBoyStyle.microLabel)
                                .monospacedDigit()
                            Text(week.map { "Week \($0)%" } ?? "Week —")
                                .font(BarBoyStyle.microLabel)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                    if case .needsPermission = connectProgress {
                        Button("Open Privacy Settings") {
                            LocalUsageArtifactReader.openPrivacySettings()
                        }
                        .barBoyButton()
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BarBoyStyle.panel)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(connectProgress.title). \(connectStatusDetail(connectProgress, provider: provider))")
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting…")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func connectStatusSymbol(_ progress: DesktopConnectProgress) -> String {
        switch progress {
        case .connected: return "checkmark.circle.fill"
        case .notReady, .timedOut, .failed: return "circle.dashed"
        case .needsPermission: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private func connectStatusDetail(_ progress: DesktopConnectProgress, provider: AIProvider) -> String {
        switch progress {
        case .openingApp:
            return "Opening \(DesktopAppCatalog.displayName(for: provider))…"
        case .waitingForSignIn:
            return "Finish any sign-in prompts in the app if it asks."
        case .searchingUsage:
            return "Looking for local usage % (caches, CLI, rate_limits)…"
        case .connected(let honesty):
            return honesty.summary
        case .notReady(let detail):
            return detail
        case .needsPermission:
            return LocalUsageArtifactReader.privacyGuidance(for: provider)
        case .failed(let reason):
            return reason
        case .timedOut:
            return "Check timed out. Tap Retry when you’ve run a chat once so usage can appear."
        }
    }

    private func canCommit(_ provider: AIProvider) -> Bool {
        guard allowUsage || allowRecentPrompts else { return false }
        guard pendingResult?.isVerified == true, !isConnecting else { return false }
        let already = allowed.contains(provider)
        return talkQuota.momoPlusEntitled
            || MomoPlusGate.canAllowAdditionalProvider(currentAllowedCount: allowed.count, alreadyAllowed: already)
    }

    /// Honest path for providers that never publish account % locally (Grok Bot / Gemini).
    /// Requires the desktop app to be installed and the connect attempt to finish without privacy failure.
    private func canCommitActivityOnly(_ provider: AIProvider) -> Bool {
        guard provider.supportsActivityOnlyConnect else { return false }
        guard allowRecentPrompts, !isConnecting else { return false }
        guard let result = pendingResult else { return false }
        switch result.status {
        case .awaitingUsage, .awaitingSignIn, .verified:
            break
        case .notInstalled, .notRunning, .privacyBlocked, .failed:
            return false
        }
        let already = allowed.contains(provider)
        return talkQuota.momoPlusEntitled
            || MomoPlusGate.canAllowAdditionalProvider(currentAllowedCount: allowed.count, alreadyAllowed: already)
    }

    private func beginVerification(for provider: AIProvider, openApp: Bool) {
        // Debounce repeat clicks while a connect attempt is in flight.
        if isConnecting { return }
        connectTask?.cancel()
        connectTask = nil
        connectGeneration += 1
        let generation = connectGeneration
        pendingResult = nil
        connectProgress = openApp ? .openingApp : .searchingUsage
        connectTask = Task { @MainActor in
            let result = await DesktopConnectionVerifier.runConnectAttempt(
                for: provider,
                openApp: openApp
            ) { progress in
                guard generation == connectGeneration else { return }
                connectProgress = progress
            }
            guard generation == connectGeneration, !Task.isCancelled else { return }
            pendingResult = result
            connectProgress = result.progress
            connectTask = nil
        }
    }

    private func cancelConnect() {
        connectGeneration += 1
        connectTask?.cancel()
        connectTask = nil
        pendingResult = nil
        connectProgress = nil
    }

    private func commitVerifiedConnection(_ provider: AIProvider, activityOnly: Bool) {
        if activityOnly {
            guard canCommitActivityOnly(provider) else { return }
            allowUsage = false
            allowRecentPrompts = true
        } else {
            guard canCommit(provider) else { return }
        }
        allowed.insert(provider)
        cancelConnect()
        permissionProvider = nil
        onProviderConnected?(allowed)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
                .foregroundStyle(BarBoyStyle.inverseInk)
                .background(Color.primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
