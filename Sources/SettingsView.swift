import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var deskDisplay: DeskDisplayServer
    @EnvironmentObject private var attentionNotifier: AttentionNotifier

    var body: some View {
        TabView {
            providers
                .tabItem { Label("Providers", systemImage: "sparkles") }
            accountAccess
                .tabItem { Label("Access", systemImage: "key.horizontal") }
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            deskDisplaySettings
                .tabItem { Label("Desk Display", systemImage: "display") }
            shortcutsSettings
                .tabItem { Label("Shortcuts", systemImage: "command") }
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 590, height: 480)
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
            Text("BAR BOY will use OAuth 2.1 + PKCE for compatible remote MCP servers and Keychain for tokens. It will not import browser cookies or collect ChatGPT, Claude, Cursor, Gemini, or Grok passwords.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var providers: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local providers").font(.title2.bold())
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
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        let snapshot = monitor.snapshot(for: provider)
        return HStack(spacing: 12) {
            ProviderMark(provider: provider, size: 34, active: snapshot.activeCount > 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name).font(.headline)
                Text(snapshot.activeCount > 0 ? "\(snapshot.activeCount) local process\(snapshot.activeCount == 1 ? "" : "es") detected" : "No active local process")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = provider.usageURL {
                Button("Usage") { NSWorkspace.shared.open(url) }
                    .barBoyButton()
            }
            Toggle("", isOn: Binding(
                get: { preferences.isEnabled(provider) },
                set: { preferences.setEnabled($0, for: provider); monitor.refresh() }
            ))
            .labelsHidden()
        }
        .padding(11)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private var general: some View {
        Form {
            Toggle("Compact menu bar icon", isOn: $preferences.compactMenuBar)
            Toggle("Hide idle providers", isOn: $preferences.hideIdleProviders)
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
            LabeledContent("Refresh interval", value: "15 seconds")
            LabeledContent("Version", value: "0.3.0")
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
                QRCodeView(value: deskDisplay.displayURL?.absoluteString ?? "BAR BOY")
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
            VStack(spacing: 0) {
                ShortcutRow(name: "Quick Ask", keys: ["⌃", "⌥", "SPACE"], state: "ACTIVE")
                Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
                ShortcutRow(name: "Talk", keys: ["⌃", "⌥", "T"], state: "VOICE NEXT")
                Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
                ShortcutRow(name: "Dictate", keys: ["FN", "⌃", "D"], state: "VOICE NEXT")
                Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
                ShortcutRow(name: "Hands-free", keys: ["FN", "⌃", "H"], state: "VOICE NEXT")
            }
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            Text("Quick Ask works now: it copies your request and opens Codex, Claude, Gemini, Cursor, or Grok. Voice modes are deliberately marked as next-stage until microphone permission, transcription, and action confirmations are implemented.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
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
            Text("BAR BOY reads process names and recent local session metadata for Codex, Claude, Gemini, Cursor, and Grok. It does not upload prompts, source code, or usage data.")
                .foregroundStyle(.secondary)
            Text("Disable any provider in the Providers tab to stop scanning its session folder.")
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
