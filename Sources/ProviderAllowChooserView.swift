import AppKit
import SwiftUI

enum TrackingOnboardingStep: Int, CaseIterable {
    case welcome
    case intents
    case connectProviders
    case talkTrial
}

/// Welcome → intent → browser + local-permission → Talk trial onboarding for MOMO Trackr.
/// First connect tap opens the default system browser; it does not start WebKit capture.
struct TrackingOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: TrackingOnboardingStep
    @State private var intents: Set<OnboardingIntent>
    @State private var allowed: Set<AIProvider>
    @State private var permissionProvider: AIProvider?
    @State private var allowUsage = true
    @State private var allowRecentPrompts = true

    var initialStep: TrackingOnboardingStep
    var onFinish: (_ intents: Set<OnboardingIntent>, _ allowed: Set<AIProvider>) -> Void
    var onDismiss: (() -> Void)?
    var onTalkTrial: (() -> Void)?

    init(
        initialStep: TrackingOnboardingStep = .welcome,
        initialIntents: Set<OnboardingIntent> = [],
        initialAllowed: Set<AIProvider> = [],
        onFinish: @escaping (_ intents: Set<OnboardingIntent>, _ allowed: Set<AIProvider>) -> Void,
        onDismiss: (() -> Void)? = nil,
        onTalkTrial: (() -> Void)? = nil
    ) {
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)
        _intents = State(initialValue: initialIntents)
        _allowed = State(initialValue: initialAllowed)
        self.onFinish = onFinish
        self.onDismiss = onDismiss
        self.onTalkTrial = onTalkTrial
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step != .welcome {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            step = TrackingOnboardingStep(rawValue: max(0, step.rawValue - 1)) ?? .welcome
                            permissionProvider = nil
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
            Text("Local tracking for the AI tools you already use. On-device only — we don’t scrape browser cookies or invent usage %.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            primaryButton("Continue") {
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
            Text("Allow the providers you use")
                .font(BarBoyStyle.display)
                .multilineTextAlignment(.center)
            Text("Tap to sign in on their official site in your browser. When you’re back, MOMO can use on-device usage and recent prompts — you still confirm a snapshot before any verified numbers show.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let permissionProvider {
                permissionPanel(for: permissionProvider)
            } else {
                VStack(spacing: 8) {
                    ForEach(AIProvider.allCases) { provider in
                        providerConnectButton(provider)
                    }
                }

                primaryButton("Continue") {
                    if onDismiss == nil {
                        step = .talkTrial
                    } else {
                        onFinish(intents, allowed)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 20)
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
        return Button {
            _ = ProviderAccountOpen.openLogin(for: provider)
            allowUsage = true
            allowRecentPrompts = true
            permissionProvider = provider
        } label: {
            HStack(spacing: 12) {
                ProviderMark(provider: provider, size: 28, active: isAllowed)
                Text(isAllowed ? "\(provider.connectButtonTitle) · Allowed" : provider.connectButtonTitle)
                    .font(BarBoyStyle.rowTitle)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isAllowed ? "checkmark" : "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(isAllowed ? Color.primary : BarBoyStyle.hairline, lineWidth: isAllowed ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.connectButtonTitle)
    }

    private func permissionPanel(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(provider.name)
                .font(BarBoyStyle.sectionLabel)

            Toggle(isOn: $allowUsage) {
                Text("Track usage").font(BarBoyStyle.rowTitle)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $allowRecentPrompts) {
                Text("Track recent prompts").font(BarBoyStyle.rowTitle)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 8) {
                Button("Not now") {
                    permissionProvider = nil
                }
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .buttonStyle(.plain)

                Button("Continue") {
                    guard allowUsage || allowRecentPrompts else { return }
                    allowed.insert(provider)
                    permissionProvider = nil
                }
                .font(BarBoyStyle.navLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .foregroundStyle(BarBoyStyle.inverseInk)
                .background((allowUsage || allowRecentPrompts) ? Color.primary : Color.primary.opacity(0.35))
                .buttonStyle(.plain)
                .disabled(!(allowUsage || allowRecentPrompts))
            }
        }
        .padding(14)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
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
