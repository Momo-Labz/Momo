import AppKit
import SwiftUI

enum TrackingOnboardingStep: Int, CaseIterable {
    case welcome
    case intents
    case connectProviders
    case preferences
    case talkTrial
}

/// Welcome → intent → desktop-app allow → prefs → Talk trial.
/// Providers start empty; each click opens the desktop app and grants local tracking.
struct TrackingOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var talkQuota = TalkService.shared.quota

    @State private var step: TrackingOnboardingStep
    @State private var intents: Set<OnboardingIntent>
    @State private var allowed: Set<AIProvider>
    @State private var permissionProvider: AIProvider?
    @State private var pendingStatus: DesktopConnectionVerifier.Status?
    @State private var isVerifying = false
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
        onFinish: @escaping (_ intents: Set<OnboardingIntent>, _ allowed: Set<AIProvider>) -> Void,
        onDismiss: (() -> Void)? = nil,
        onTalkTrial: (() -> Void)? = nil,
        onProviderConnected: ((_ allowed: Set<AIProvider>) -> Void)? = nil
    ) {
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)
        _intents = State(initialValue: initialIntents)
        // Connect UI always starts empty; strip fills only after each successful allow.
        _allowed = State(initialValue: [])
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
                            permissionProvider = nil
                            plusGateMessage = nil
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
    }

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            AnimatedMomoMark(size: 52, animated: !reduceMotion)
            Text("Welcome to MOMO Trackr")
                .font(BarBoyStyle.display)
                .multilineTextAlignment(.center)
            Text("Local tracking for the AI desktop apps you already use. On-device only — we don’t scrape browser cookies or invent usage %.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            primaryButton("Continue") {
                allowed = []
                step = .intents
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 22)
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
            Text("Connect the desktop apps you use")
                .font(BarBoyStyle.display)
                .multilineTextAlignment(.center)
            Text("Start empty. Click a provider to open its Mac app. MOMO marks it connected only after a real local readiness check — not just because the process is running. Free includes up to \(DesktopAppCatalog.freeProviderLimit) verified providers.")
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
                    ForEach(AIProvider.allCases) { provider in
                        providerConnectButton(provider)
                    }
                }

                Button {
                    guard !allowed.isEmpty else { return }
                    step = .preferences
                } label: {
                    Text(allowed.isEmpty ? "Connect at least one app to continue" : "Continue")
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
            }

            primaryButton("Continue") {
                UserDefaults.standard.set(selectedRefreshInterval, forKey: "refreshIntervalSeconds.v1")
                step = .talkTrial
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

            if onTalkTrial != nil {
                primaryButton("Try Talk (1 free)") {
                    onTalkTrial?()
                }
            }

            Button("Skip for now") {
                onFinish(intents, allowed)
            }
            .font(BarBoyStyle.navLabel)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            .buttonStyle(.plain)

            primaryButton("Finish setup") {
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
            allowUsage = true
            allowRecentPrompts = true
            pendingStatus = nil
            permissionProvider = provider
            beginVerification(for: provider, openApp: true)
        } label: {
            HStack(spacing: 12) {
                ProviderMark(provider: provider, size: 28, active: isAllowed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAllowed ? "\(provider.connectButtonTitle) · Verified" : provider.connectButtonTitle)
                        .font(BarBoyStyle.rowTitle)
                        .foregroundStyle(Color.primary)
                    Text(match.isInstalled ? match.displayName : "Not installed in Applications")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isAllowed ? "checkmark" : (match.isInstalled ? "arrow.up.forward.app" : "plus"))
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

    private func verificationPanel(for provider: AIProvider) -> some View {
        let match = DesktopAppCatalog.match(for: provider)
        return VStack(alignment: .leading, spacing: 12) {
            Text(provider.name)
                .font(BarBoyStyle.sectionLabel)
            Text("MOMO opens \(match.displayName) and checks for a readable local session source. Running alone is not enough.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $allowUsage) {
                Text("Track usage").font(BarBoyStyle.rowTitle)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $allowRecentPrompts) {
                Text("Track recent prompts").font(BarBoyStyle.rowTitle)
            }
            .toggleStyle(.checkbox)

            if isVerifying {
                Text("Checking connection…")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            } else if let pendingStatus {
                Text(pendingStatus.guidance)
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(pendingStatus.isVerified ? Color.primary : BarBoyStyle.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Back") {
                    permissionProvider = nil
                    pendingStatus = nil
                    isVerifying = false
                }
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .buttonStyle(.plain)

                Button("Retry") {
                    beginVerification(for: provider, openApp: true)
                }
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .buttonStyle(.plain)
                .disabled(isVerifying)

                Button("Allow") {
                    commitVerifiedConnection(provider)
                }
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .foregroundStyle(BarBoyStyle.inverseInk)
                .background(canCommit(provider) ? Color.primary : Color.primary.opacity(0.35))
                .buttonStyle(.plain)
                .disabled(!canCommit(provider))
            }
        }
        .padding(14)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private func canCommit(_ provider: AIProvider) -> Bool {
        guard allowUsage || allowRecentPrompts else { return false }
        guard pendingStatus?.isVerified == true, !isVerifying else { return false }
        let already = allowed.contains(provider)
        return talkQuota.momoPlusEntitled
            || MomoPlusGate.canAllowAdditionalProvider(currentAllowedCount: allowed.count, alreadyAllowed: already)
    }

    private func beginVerification(for provider: AIProvider, openApp: Bool) {
        isVerifying = true
        pendingStatus = nil
        if openApp {
            _ = DesktopAppConnect.openDesktopApp(for: provider)
        }
        Task { @MainActor in
            // Give the app a moment to come to the foreground / finish launching.
            try? await Task.sleep(for: .milliseconds(900))
            let status = DesktopConnectionVerifier.verify(provider)
            pendingStatus = status
            isVerifying = false
        }
    }

    private func commitVerifiedConnection(_ provider: AIProvider) {
        guard canCommit(provider) else { return }
        allowed.insert(provider)
        permissionProvider = nil
        pendingStatus = nil
        isVerifying = false
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
