import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore

    var body: some View {
        TabView {
            providers
                .tabItem { Label("Providers", systemImage: "sparkles") }
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 520, height: 410)
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
        .background(BarBoyStyle.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var general: some View {
        Form {
            Toggle("Compact menu bar icon", isOn: $preferences.compactMenuBar)
            Toggle("Hide idle providers", isOn: $preferences.hideIdleProviders)
            Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                .disabled(true)
            LabeledContent("Refresh interval", value: "15 seconds")
            LabeledContent("Version", value: "0.1.0")
        }
        .formStyle(.grouped)
        .padding(10)
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 38, weight: .light))
            Text("Your work stays on your Mac").font(.title2.bold())
            Text("BAR BOY reads process names and recent JSONL session metadata from ~/.codex, ~/.claude, and ~/.gemini. It does not upload prompts, source code, or usage data.")
                .foregroundStyle(.secondary)
            Text("Disable any provider in the Providers tab to stop scanning its session folder.")
                .font(.callout)
            Spacer()
        }
        .padding(28)
    }
}

