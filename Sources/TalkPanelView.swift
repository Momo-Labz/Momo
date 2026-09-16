import SwiftUI

/// Hands-free / typed Talk about usage + activity. Free quota + MOMO+ upsell.
struct TalkPanelView: View {
    var isOnboardingTrial = false
    var onFinishedOnboardingTrial: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @ObservedObject private var talk = TalkService.shared
    @ObservedObject private var voice = VoiceInput.shared
    @ObservedObject private var shortcuts = GlobalShortcutService.shared
    @State private var recordingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AnimatedMomoMark(
                    size: 40,
                    animated: talk.phase == .thinking || talk.phase == .speaking || voice.isActive,
                    motion: talk.phase == .thinking ? .alert : .wave,
                    flashAlert: talk.phase == .thinking
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(isOnboardingTrial ? "MOMO / TALK TRIAL" : "MOMO / TALK")
                        .font(BarBoyStyle.sectionLabel)
                    Text(statusLine)
                        .font(BarBoyStyle.bodySmall)
                        .foregroundStyle(.secondary)
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
                }
            }

            if talk.phase == .upsell {
                upsellBlock
            } else {
                TextField("Ask about usage or what’s running…", text: $talk.typedAsk)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(BarBoyStyle.surface)
                    .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))

                if !talk.reply.isEmpty {
                    ScrollView {
                        Text(talk.reply)
                            .font(BarBoyStyle.bodySmall)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }

                HStack(spacing: 8) {
                    Button(voice.isActive ? "Stop mic" : "Speak") {
                        if voice.isActive {
                            voice.stop()
                        } else {
                            voice.prepare(.talk)
                            Task { await voice.start() }
                        }
                    }
                    .barBoyButton()

                    Button("Ask MOMO") {
                        Task { await submit() }
                    }
                    .barBoyButton()
                    .disabled(talk.phase == .thinking)

                    Spacer(minLength: 0)

                    if isOnboardingTrial {
                        Button("Set Talk shortcut") { recordingShortcut = true }
                            .barBoyButton()
                    }
                }

                if isOnboardingTrial {
                    Text("Free trial includes this guided ask. Shortcut: \(shortcuts.bindings[.talk]?.label ?? "⌃⌥ T")")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                } else if !talk.quota.momoPlusEntitled {
                    Text("Free Talk left: \(talk.quota.freeUsesRemaining) of \(TalkQuotaStore.freeUsesLimit)")
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(BarBoyStyle.panel)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .onAppear { talk.begin(isOnboardingTrial: isOnboardingTrial) }
        .onDisappear { talk.cancel(); voice.stop() }
        .sheet(isPresented: $recordingShortcut) {
            VStack(spacing: 16) {
                Text("Press a shortcut for Talk").font(.headline)
                Text("Include Control, Option or Command. Escape cancels.").font(.caption)
                ShortcutRecorder { binding in
                    if let binding {
                        _ = shortcuts.update(binding, for: .talk)
                        _ = shortcuts.setEnabled(true, for: .talk)
                    }
                    recordingShortcut = false
                }
                .frame(width: 350, height: 35)
                Button("Cancel") { recordingShortcut = false }
            }
            .padding(24)
        }
    }

    private var statusLine: String {
        switch talk.phase {
        case .idle: return voice.isActive ? "Listening…" : "Usage + activity only · local Ollama"
        case .listening: return "Listening…"
        case .thinking: return "MOMO THINKING"
        case .speaking: return "Speaking"
        case .upsell: return "MOMO+ required"
        case .offline: return "Local model offline"
        case .error(let message): return message
        }
    }

    private var upsellBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TalkQuotaStore.UpsellCopy.inline)
                .font(BarBoyStyle.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(TalkQuotaStore.UpsellCopy.primaryButton) {
                    talk.markPlusFromUpsell()
                }
                .barBoyButton()
                Button(TalkQuotaStore.UpsellCopy.secondaryButton) {
                    talk.dismissUpsell()
                    onDismiss?()
                }
                .barBoyButton()
            }
            Text(TalkQuotaStore.UpsellCopy.optionalOneLiner)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() async {
        let prompt = talk.typedAsk.isEmpty ? voice.text : talk.typedAsk
        await talk.ask(
            prompt: prompt,
            snapshots: monitor.snapshots,
            observations: monitor.usageObservations,
            allowed: preferences.allowedTrackingProviders
        )
    }
}
