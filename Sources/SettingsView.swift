import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsView: View {
    var embedded = false
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var deskDisplay: DeskDisplayServer
    @EnvironmentObject private var attentionNotifier: AttentionNotifier

    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var shortcutService = GlobalShortcutService.shared
    @State private var recordingShortcut: ShortcutAction?
    @State private var shortcutError: String?
    @State private var shortcutNotice: String?
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("notifyNeedsInput") private var notifyNeedsInput = true
    @AppStorage("notifyFailure") private var notifyFailure = true
    @AppStorage("notifyCompletion") private var notifyCompletion = true
    @AppStorage("notifyUsageReset") private var notifyUsageReset = true
    @AppStorage("notifyThreshold50") private var notifyThreshold50 = false
    @AppStorage("notifyThreshold75") private var notifyThreshold75 = true
    @AppStorage("notifyThreshold90") private var notifyThreshold90 = true
    @AppStorage("notifyThreshold100") private var notifyThreshold100 = true
    @State private var pendingProvider: AIProvider?
    @State private var pendingRoot: String?
    private var refreshIntervalLabel: String {
        let seconds = Int(ActivityMonitor.refreshInterval)
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    var body: some View {
        TabView {
            providers
                .tabItem { Label("Providers", systemImage: "sparkles") }
            accountAccess
                .tabItem { Label("Access", systemImage: "key.horizontal") }
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            notifications
                .tabItem { Label("Notifications", systemImage: "bell") }
            deskDisplaySettings
                .tabItem { Label("Desk Display", systemImage: "display") }
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: embedded ? nil : 590, height: embedded ? nil : 480)
        .frame(maxWidth: embedded ? .infinity : nil, maxHeight: embedded ? .infinity : nil)
        .alert("Authorize local access", isPresented: Binding(
            get: { pendingProvider != nil },
            set: { if !$0 { pendingProvider = nil; pendingRoot = nil } }
        ), presenting: pendingProvider) { provider in
            Button("Authorize \(provider.name)") {
                if let pendingRoot { preferences.addLocalRoot(pendingRoot, for: provider) }
                preferences.setEnabled(true, for: provider)
                monitor.setAuthorizedRoots(authorizedRootURLs)
                monitor.setAuthorizedProviders(preferences.enabledProviders)
                pendingProvider = nil; pendingRoot = nil
            }
            Button("Cancel", role: .cancel) { pendingProvider = nil; pendingRoot = nil }
        } message: { provider in
            Text(authorizationMessage(for: provider, root: pendingRoot))
        }
    }

    private var accountAccess: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider access").font(.title2.bold())
                Text("One permission map for usage, models, MCPs, plugins, and skills.")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ProviderAccessPlan.all) { plan in
                        HStack(alignment: .top, spacing: 12) {
                            ProviderMark(provider: plan.provider, size: 34, active: monitor.snapshot(for: plan.provider).activeCount > 0)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(plan.provider.name).font(.headline)
                                    Spacer()
                                    Text(plan.current.rawValue)
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(BarBoyStyle.raised)
                                        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                                }
                                Text(plan.detail).font(.caption)
                                Text(plan.future).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(11)
                        .background(BarBoyStyle.surface)
                        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                    }
                }
            }
            Text("MOMO will use OAuth 2.1 + PKCE for compatible remote MCP servers and Keychain for tokens. It will not import browser cookies or collect ChatGPT, Claude, Cursor, Gemini, or Grok passwords.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear { monitor.setAuthorizedRoots(authorizedRootURLs) }
    }

    private var authorizedRootURLs: [AIProvider: [URL]] {
        Dictionary(uniqueKeysWithValues: preferences.localProviderRoots.map { provider, paths in
            (provider, paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
        })
    }

    private var providers: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local providers").font(.title2.bold())
                Button("Set up Codex desktop access") { openWindow(id: "onboarding") }
                Text("BAR BOY reads local session files and running processes. It never asks for your account password.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(AIProvider.allCases) { provider in
                    providerRow(provider)
                }
            }
            Spacer()
            Text("Consumer plan quotas are shown through each provider’s official usage page because they do not all expose a supported API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear { monitor.setAuthorizedRoots(authorizedRootURLs) }
    }

    private func authorizationMessage(for provider: AIProvider, root: String? = nil) -> String {
        let location = root ?? provider.sessionRoots.joined(separator: " or ")
        return "Allow MOMO to read \(provider.name) session metadata and recorded capability fields under \(location)? This approval is for this local folder only. If an account uses another folder, authorize that folder separately. MOMO will not read passwords, browser cookies, prompts, tool arguments, or credentials. You can revoke access here."
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        let snapshot = monitor.snapshot(for: provider)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
            ProviderMark(provider: provider, size: 34, active: snapshot.activeCount > 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name).font(.headline)
                Text(!preferences.isEnabled(provider) ? "Authorization required" : snapshot.activeCount > 0 ? "\(snapshot.activeCount) local process\(snapshot.activeCount == 1 ? "" : "es") detected" : "No active local process")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = provider.usageURL {
                Button("Usage") { NSWorkspace.shared.open(url) }
                    .barBoyButton()
            }
            Toggle("", isOn: Binding(
                get: { preferences.isEnabled(provider) },
                set: { enabled in
                    if enabled { pendingProvider = provider }
                    else {
                        preferences.setEnabled(false, for: provider)
                        monitor.setAuthorizedRoots(authorizedRootURLs)
                        monitor.setAuthorizedProviders(preferences.enabledProviders)
                    }
                }
            ))
            .labelsHidden()
            }
            HStack(spacing: 8) {
                Button(preferences.roots(for: provider).isEmpty ? "Authorize account folder" : "Add account folder") { chooseLocalRoot(for: provider) }
                    .barBoyButton()
                if !preferences.roots(for: provider).isEmpty {
                    Text(preferences.roots(for: provider).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .help(preferences.roots(for: provider).joined(separator: "\n"))
                } else {
                    Text("Default: \(provider.sessionRoots.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(11)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private func chooseLocalRoot(for provider: AIProvider) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the \(provider.name) session folder MOMO may read."
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingRoot = url.path
        pendingProvider = provider
    }

    private var general: some View {
        Form {
            Toggle("Compact menu bar icon", isOn: $preferences.compactMenuBar)
            Toggle("Hide idle providers", isOn: $preferences.hideIdleProviders)
            Toggle("Show provider usage bars", isOn: $preferences.showProviderUsageBars)
            Toggle("Show provider card details", isOn: $preferences.showProviderCardDetails)
            Text("When off, cards keep only the provider, chat state, and one-line usage summary. Hover a card for the full folder, model, and process details.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Notify when an agent needs me", isOn: Binding(
                get: { preferences.attentionAlertsEnabled },
                set: { enabled in
                    if enabled {
                        Task { preferences.attentionAlertsEnabled = await attentionNotifier.requestAuthorization() }
                    } else {
                        preferences.attentionAlertsEnabled = false
                    }
                }
            ))
            LabeledContent("Alert permission", value: attentionNotifier.authorizationLabel)
            Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                .disabled(true)
            Button("Open macOS menu bar controls") { openMenuBarSettings() }
            LabeledContent("Refresh interval", value: refreshIntervalLabel)
            LabeledContent("Version", value: BarBoyAppInfo.marketingVersion)
        }
        .formStyle(.grouped)
        .padding(10)
    }

    private var notifications: some View {
        Form {
            Toggle("Enable notifications", isOn: $preferences.attentionAlertsEnabled)
            Toggle("Completion", isOn: $notifyCompletion)
            Toggle("Approval or input needed", isOn: $notifyNeedsInput)
            Toggle("Failure", isOn: $notifyFailure)
            Toggle("Usage limit reset", isOn: $notifyUsageReset)
            Text("Usage thresholds").font(.headline)
            Toggle("50%", isOn: $notifyThreshold50)
            Toggle("75%", isOn: $notifyThreshold75)
            Toggle("90%", isOn: $notifyThreshold90)
            Toggle("100%", isOn: $notifyThreshold100)
            Text("MOMO notifies once per crossing for the selected thresholds.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(10)
    }

    private var deskDisplaySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Desk Display").font(.title2.bold())
                    Text("Pair a 3D-printed screen or any local browser with this Mac.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $preferences.deskDisplayEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack(alignment: .top, spacing: 18) {
                QRCodeView(value: deskDisplay.displayURL?.absoluteString ?? "MOMO")
                    .frame(width: 132, height: 132)
                    .padding(10)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                    .opacity(preferences.deskDisplayEnabled ? 1 : 0.35)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(deskDisplay.state == .ready ? Color.primary : Color.secondary.opacity(0.45))
                            .frame(width: 7, height: 7)
                        Text(deskDisplay.state.label).font(.headline)
                    }
                    Text("PAIRING CODE  \(deskDisplay.pairingCode)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                    Text(deskDisplay.displayURL?.absoluteString ?? "Address unavailable")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    HStack {
                        Button("Copy address") { copyDisplayAddress() }
                            .barBoyButton()
                        Button("Preview") {
                            if let url = deskDisplay.displayURL { NSWorkspace.shared.open(url) }
                        }
                        .barBoyButton()
                        .disabled(!preferences.deskDisplayEnabled)
                    }
                }
            }

            Toggle("Show session and project titles on the physical screen", isOn: $preferences.showDeskDisplayTitles)
            Text("The server is off by default, accepts read-only requests, requires the unguessable pairing key, and never leaves your local network. Anyone who can see the paired screen can see the titles you enable above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = deskDisplay.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(24)
        .onChange(of: preferences.deskDisplayEnabled) { _, enabled in
            deskDisplay.update(snapshots: monitor.snapshots, includeTitles: preferences.showDeskDisplayTitles)
            if enabled { deskDisplay.start() } else { deskDisplay.stop() }
        }
        .onChange(of: preferences.showDeskDisplayTitles) { _, includeTitles in
            deskDisplay.update(snapshots: monitor.snapshots, includeTitles: includeTitles)
        }
    }

    private var shortcutsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts").font(.title2.bold())
                Text("Get back into an AI workflow without hunting through windows.")
                    .foregroundStyle(.secondary)
            }
            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title).font(.headline)
                        Text(shortcutService.isEnabled(action) ? "Shortcut active" : "Shortcut off")
                            .font(.caption).foregroundStyle(shortcutService.isEnabled(action) ? .secondary : BarBoyStyle.coral)
                    }
                    Spacer()
                    Button(shortcutService.bindings[action]?.label ?? "Set shortcut") { recordingShortcut = action; shortcutError = nil }.barBoyButton()
                    Toggle("", isOn: Binding(
                        get: { shortcutService.isEnabled(action) },
                        set: { value in
                            shortcutError = shortcutService.setEnabled(value, for: action)
                            shortcutNotice = shortcutError == nil ? "\(action.title) \(value ? "enabled" : "turned off")" : nil
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    Menu {
                        Button("Change shortcut") { recordingShortcut = action; shortcutError = nil }
                        Button(shortcutService.isEnabled(action) ? "Turn off" : "Turn on") {
                            let value = !shortcutService.isEnabled(action)
                            shortcutError = shortcutService.setEnabled(value, for: action)
                            shortcutNotice = shortcutError == nil ? "\(action.title) \(value ? "enabled" : "turned off")" : nil
                        }
                        Button("Reset to default") {
                            shortcutError = shortcutService.reset(action)
                            shortcutNotice = shortcutError == nil ? "Reset \(action.title) to its default" : nil
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .barBoyIconButton()
                    .help("More options for \(action.title)")
                    Text(shortcutService.errors[action] ?? (shortcutService.isEnabled(action) ? "ACTIVE" : "OFF"))
                        .font(.caption).foregroundStyle(shortcutService.isEnabled(action) ? .secondary : BarBoyStyle.coral)
                }
            }
            Toggle("Haptic feedback", isOn: $hapticFeedback)
            Text("Talk stops after a pause. Dictate and Hands-free listen until stopped. Voice stays on this Mac and requires supported on-device speech recognition. Haptics require a compatible trackpad.").font(.caption).foregroundStyle(.secondary)
            if let shortcutNotice { Text(shortcutNotice).font(.caption).foregroundStyle(.green) }
            if let shortcutError { Text(shortcutError).font(.caption).foregroundStyle(.red) }
            Spacer()
        }
        .padding(24)
        .sheet(item: $recordingShortcut) { action in
            VStack(spacing: 16) {
                Text("Press a new shortcut for \(action.title)").font(.headline)
                Text("Include Control, Option or Command. Escape cancels.").font(.caption)
                ShortcutRecorder { binding in
                    if let binding {
                        shortcutError = shortcutService.update(binding, for: action)
                        shortcutNotice = shortcutError == nil ? "Saved \(action.title): \(binding.label)" : nil
                    }
                    recordingShortcut = nil
                }.frame(width: 350, height: 35)
                Button("Cancel") { recordingShortcut = nil }
            }.padding(24)
        }
    }

    private func copyDisplayAddress() {
        guard let address = deskDisplay.displayURL?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
    }

    private func openMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock"
        ]
        if let url = candidates.compactMap(URL.init(string:)).first { NSWorkspace.shared.open(url) }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 38, weight: .light))
            Text("Your work stays on your Mac").font(.title2.bold())
            Text("MOMO inspects running process names and recent local session metadata only for providers you enable. It does not upload prompts, source code, or usage data.")
                .foregroundStyle(.secondary)
            Text("Disable a provider in the Providers tab to stop its process and file scanning and exclude it from Desk Display and MOMO RELAY status.")
                .font(.callout)
            Spacer()
        }
        .padding(28)
    }
}

private struct ShortcutRow: View {
    let name: String
    let keys: [String]
    let state: String

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.headline).frame(width: 110, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(BarBoyStyle.raised)
                        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                }
            }
            Spacer()
            Text(state)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(state == "ACTIVE" ? Color.primary : Color.secondary)
        }
        .padding(12)
    }
}

private struct QRCodeView: View {
    let value: String

    var body: some View {
        if let image = makeImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .accessibilityLabel("Desk Display pairing QR code")
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.black)
        }
    }

    private func makeImage() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}


/// Connection setup deliberately separates observation from sending a turn.
struct CodexOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var notifier: AttentionNotifier
    @Environment(\.dismiss) private var dismiss
    @AppStorage("codexOnboardingSeen.v1") private var seen = false
    @State private var confirmAccess = false
    @State private var celebrating = false
    @State private var showVoiceGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AnimatedMomoMark(size: 44, animated: celebrating, motion: .wave)
                VStack(alignment: .leading) {
                    Text("MOMO / CONNECT CODEX").font(BarBoyStyle.sectionLabel)
                    Text("Keep your task within reach.").foregroundStyle(.secondary)
                }
            }
            Text(CodexDesktopConnection.applicationURL == nil ? "1. Install Codex desktop to open tasks." : "1. Codex desktop detected.").font(.headline)
            HStack {
                Image(systemName: preferences.isEnabled(.codex) ? "checkmark.circle.fill" : "lock.circle")
                Text(preferences.isEnabled(.codex) ? "Local access authorized" : "2. Authorize local access").font(.headline)
            }
            .foregroundStyle(preferences.isEnabled(.codex) ? Color.green : Color.primary)
            .id(preferences.isEnabled(.codex))
            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
            Text("Read local tasks, recorded usage and tool configuration. This covers all accounts saved in your local Codex folders; it does not sign in to an account.")
                .font(.callout).foregroundStyle(.secondary)
            Button(preferences.isEnabled(.codex) ? "Revoke Codex access" : "Authorize Codex local access") {
                if preferences.isEnabled(.codex) {
                    preferences.setEnabled(false, for: .codex)
                    monitor.setAuthorizedProviders(preferences.enabledProviders)
                } else { confirmAccess = true }
            }.barBoyButton()
            Text("3. Open the exact task").font(.headline)
            Text("Choose a task in MOMO. Copy + Open takes you to that task with your reply ready to paste.")
                .font(.callout).foregroundStyle(.secondary)
            Button(preferences.attentionAlertsEnabled ? "Notifications enabled" : "Enable task notifications") {
                Task { preferences.attentionAlertsEnabled = await notifier.requestAuthorization() }
            }.barBoyButton().disabled(preferences.attentionAlertsEnabled || !preferences.isEnabled(.codex))
            Text("4. Voice, usage and continuing after a reset").font(.headline)
            Text("How voice permission works, what the two usage rows mean, and which chats continue on their own.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Set up voice & continuing") { showVoiceGuide = true }.barBoyButton()
            Text("Codex desktop chats cannot be continued unattended. CLI auto-resume is a separate setting.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("No password, browser cookies or Accessibility permission needed.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { seen = true; dismiss() }.barBoyButton()
            }
        }
        .padding(24).frame(width: 500).background(BarBoyStyle.panel)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.22), value: preferences.isEnabled(.codex))
         .onChange(of: preferences.isEnabled(.codex)) { _, enabled in
            MomoFeedback.perform(); celebrating = enabled
            Task { try? await Task.sleep(for: .seconds(1.2)); celebrating = false }
        }
        .sheet(isPresented: $showVoiceGuide) { VoiceSetupGuide() }
        .alert("Allow local Codex access?", isPresented: $confirmAccess) {
            Button("Authorize") {
                preferences.setEnabled(true, for: .codex)
                monitor.setAuthorizedProviders(preferences.enabledProviders)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Authorize MOMO to read session metadata and capability configuration for all Codex accounts saved in this Mac user's local session folders and detect Codex processes. Revoke anytime in Settings. This does not authorize automatic desktop messages.")
        }
    }
}


struct VoiceSetupGuide: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AnimatedMomoMark(size: 40, animated: false)
                Text("MOMO / VOICE & USAGE").font(BarBoyStyle.sectionLabel)
            }
            Text("Ready → Listening → Draft ready").font(.headline)
            Text("Start voice input to request Microphone and Speech Recognition permissions. Nothing records when you simply open onboarding.")
            Text("See your words live. Hands-free recognizes “MOMO stop” to finish and “MOMO use draft” to return to the composer. Talk ends after a pause; Dictate stops with its shortcut or Stop. Each recording lasts up to 55 seconds.")
            Text("Speech runs on this Mac when supported. If your language or device is unavailable, MOMO offers typed input. Voice never sends a provider message.")
            Divider()
            Text("5HR + WEEK, when recorded").font(.headline)
            Text("The two rows beneath tokens show the provider’s recorded short and long usage windows. Other durations keep their own labels. A dash means missing or expired data, never zero usage.")
            Divider()
            Text("Continuing after a reset").font(.headline)
            Text("Every conversation shows its own line: how long until its recorded window resets, named by the chat and folder you gave it.")
            Text("Codex CLI chats continue on their own once the window opens, if Settings → General → Auto-resume after usage reset is on. Other providers have no supported way to send a turn unattended, so MOMO notifies you the moment the window opens and one click reopens that exact chat. MOMO never claims to have continued something it did not.")
            Text("Edit keys and turn haptics on or off in Settings → Shortcuts.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Done") { dismiss() }.barBoyButton()
                Spacer()
                Button("Try Hands-free") {
                    dismiss()
                    NotificationCenter.default.post(name: .momoShortcut, object: ShortcutAction.handsFree)
                }.barBoyButton()
            }
        }.padding(24).frame(width: 460).fixedSize(horizontal: false, vertical: true)
    }
}
