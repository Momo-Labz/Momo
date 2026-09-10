import AppKit
import SwiftUI

struct DashboardView: View {
    var refreshOnAppear = true
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.openSettings) private var openSettings
    @State private var selection: AIProvider? = nil

    private var visibleSnapshots: [ProviderSnapshot] {
        monitor.snapshots.filter { snapshot in
            preferences.isEnabled(snapshot.provider)
                && (!preferences.hideIdleProviders || snapshot.activeCount > 0 || !snapshot.sessions.isEmpty)
                && (selection == nil || selection == snapshot.provider)
        }
    }

    private var allSessions: [AgentSession] {
        visibleSnapshots.flatMap(\.sessions).sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    usageStrip
                    activitySection
                    menuCalmSection
                }
                .padding(16)
            }
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 420, height: 650)
        .background(BarBoyStyle.panel)
        .task { if refreshOnAppear { monitor.refresh() } }
    }

    private var header: some View {
        HStack(spacing: 11) {
            PixelBarBoyMark(size: 34, tile: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("BAR BOY")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.8)
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    Text(lastUpdateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .opacity(monitor.isRefreshing ? 0.45 : 1)
            }
            .barBoyButton()
            .help("Refresh local activity")
            Button { openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                .barBoyButton()
                .help("Settings")
        }
        .padding(16)
    }

    private var usageStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("QUICK USAGE", note: "local estimate today")
            HStack(spacing: 8) {
                ForEach(monitor.snapshots.filter { preferences.isEnabled($0.provider) }) { snapshot in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            selection = selection == snapshot.provider ? nil : snapshot.provider
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ProviderMark(provider: snapshot.provider, size: 24, active: snapshot.activeCount > 0)
                                Spacer()
                                if snapshot.activeCount > 0 {
                                    Circle().fill(Color.primary).frame(width: 5, height: 5)
                                }
                            }
                            Text(snapshot.usageText)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(snapshot.provider.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(selection == snapshot.provider ? BarBoyStyle.raised : BarBoyStyle.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(selection == snapshot.provider ? Color.primary.opacity(0.35) : BarBoyStyle.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("SESSIONS", note: allSessions.filter(\.isRunning).count == 1 ? "1 live" : "\(allSessions.filter(\.isRunning).count) live")
            if allSessions.isEmpty {
                Surface {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.stars")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quiet right now").font(.subheadline.weight(.semibold))
                            Text("New local AI sessions will appear here.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(allSessions.prefix(7).enumerated()), id: \.element.id) { index, session in
                        SessionRow(session: session)
                        if index < min(allSessions.count, 7) - 1 { Divider().padding(.leading, 43).opacity(0.5) }
                    }
                }
                .padding(.horizontal, 12)
                .background(BarBoyStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BarBoyStyle.hairline, lineWidth: 0.5))
            }
        }
    }

    private var menuCalmSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("MENU CALM", note: "make room")
            Surface {
                VStack(spacing: 10) {
                    HStack(spacing: 11) {
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clean up the menu bar").font(.subheadline.weight(.semibold))
                            Text("Open Apple’s controls, then ⌘-drag icons to move or remove them.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        Toggle("Compact BAR BOY", isOn: $preferences.compactMenuBar)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(.caption.weight(.medium))
                        Spacer()
                        Button("Open settings") { openMenuBarSettings() }
                            .barBoyButton()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/Momo-Labz")!)
            } label: {
                Label("Support us", systemImage: "heart")
            }
            .barBoyButton()
            Spacer()
            Text("Local-first · no session data uploaded")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit BAR BOY")
        }
        .padding(12)
    }

    private func sectionLabel(_ title: String, note: String) -> some View {
        HStack {
            Text(title).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            Spacer()
            Text(note).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var lastUpdateLabel: String {
        guard let date = monitor.lastUpdated else { return "Reading local activity…" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        return seconds < 5 ? "Updated now" : "Updated \(seconds)s ago"
    }

    private func openMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock"
        ]
        if let url = candidates.compactMap(URL.init(string:)).first {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            ProviderMark(provider: session.provider, size: 30, active: session.isRunning)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(session.role.rawValue.uppercased())
                    Text("·")
                    Text(session.project)
                    if let tokens = session.tokens, tokens > 0 {
                        Text("·")
                        Text(tokens.formatted(.number.notation(.compactName)))
                    }
                }
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(session.ageLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(session.isRunning ? Color(nsColor: .windowBackgroundColor) : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(session.isRunning ? Color.primary : BarBoyStyle.raised, in: Capsule())
        }
        .padding(.vertical, 10)
        .help(session.detail)
    }
}
