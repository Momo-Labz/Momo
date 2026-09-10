import AppKit
import SwiftUI

struct DashboardView: View {
    var refreshOnAppear = true
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var deskDisplay: DeskDisplayServer
    @Environment(\.openSettings) private var openSettings
    @State private var selection: AIProvider?

    private var visibleSnapshots: [ProviderSnapshot] {
        monitor.snapshots.filter { snapshot in
            preferences.isEnabled(snapshot.provider)
                && (!preferences.hideIdleProviders || snapshot.activeCount > 0 || !snapshot.sessions.isEmpty)
                && (selection == nil || selection == snapshot.provider)
        }
    }

    private var allSessions: [AgentSession] {
        visibleSnapshots.flatMap(\.sessions).sorted {
            if $0.attention.isUrgent != $1.attention.isUrgent { return $0.attention.isUrgent }
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private var urgentCount: Int { allSessions.filter { $0.attention.isUrgent }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if urgentCount > 0 { attentionBanner }
                    usageTable
                    activitySection
                    if preferences.deskDisplayEnabled { deskDisplaySection }
                }
                .padding(14)
            }
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            footer
        }
        .frame(width: 420, height: 650)
        .background(BarBoyStyle.panel)
        .task { if refreshOnAppear { monitor.refresh() } }
    }

    private var header: some View {
        HStack(spacing: 11) {
            PixelBarBoyMark(size: 34, tile: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("MOMO LABZ")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text("BAR BOY")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .tracking(1.1)
            }
            Spacer()
            if urgentCount > 0 {
                Text("! \(urgentCount) NEED\(urgentCount == 1 ? "S" : "") YOU")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(BarBoyStyle.coral)
            }
            Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .barBoyButton().help("Refresh local activity")
            Button { openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                .barBoyButton().help("Settings")
        }
        .padding(14)
    }

    private var attentionBanner: some View {
        HStack(spacing: 10) {
            AttentionPulse()
            VStack(alignment: .leading, spacing: 2) {
                Text(urgentCount == 1 ? "AN AGENT NEEDS YOU" : "\(urgentCount) AGENTS NEED YOU")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                Text("Open the session below to approve, answer, or recover it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(11)
        .background(BarBoyStyle.coral.opacity(0.10))
        .overlay(Rectangle().stroke(BarBoyStyle.coral, lineWidth: 1.5))
    }

    private var usageTable: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("MODELS", note: "local + linked usage")
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("PROVIDER").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SHORT").frame(width: 46, alignment: .trailing)
                    Text("WEEK").frame(width: 46, alignment: .trailing)
                    Text("SESS").frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
                ForEach(monitor.snapshots.filter { preferences.isEnabled($0.provider) }) { snapshot in
                    ProviderUsageRow(snapshot: snapshot, selected: selection == snapshot.provider) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            selection = selection == snapshot.provider ? nil : snapshot.provider
                        }
                    }
                    if snapshot.provider != monitor.snapshots.filter({ preferences.isEnabled($0.provider) }).last?.provider {
                        Rectangle().fill(BarBoyStyle.hairline.opacity(0.7)).frame(height: 1).padding(.leading, 42)
                    }
                }
            }
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("AGENTS + SESSIONS", note: "\(allSessions.filter(\.isRunning).count) live")
            if allSessions.isEmpty {
                Surface {
                    HStack(spacing: 12) {
                        PixelBarBoyMark(size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QUIET RIGHT NOW").font(.system(size: 10, weight: .black, design: .monospaced))
                            Text("New local AI sessions will appear here.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(allSessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                        SessionRow(session: session)
                        if index < min(allSessions.count, 6) - 1 {
                            Rectangle().fill(BarBoyStyle.hairline.opacity(0.7)).frame(height: 1).padding(.leading, 43)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            }
        }
    }

    private var deskDisplaySection: some View {
        HStack(spacing: 9) {
            Text("DESK DISPLAY").font(.system(size: 9, weight: .black, design: .monospaced))
            Rectangle().fill(deskDisplay.state == .ready ? Color.primary : Color.secondary).frame(width: 7, height: 7)
            Text("\(deskDisplay.state.label.uppercased()) · \(deskDisplay.pairingCode)")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
            Button("OPEN") { if let url = deskDisplay.displayURL { NSWorkspace.shared.open(url) } }.barBoyButton()
        }
    }

    private var footer: some View {
        HStack {
            Button("ASK AI") { NotificationCenter.default.post(name: .showCommandPalette, object: nil) }
                .barBoyButton().help("Quick Ask · Control–Option–Space")
            Button("SUPPORT US") { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/Momo-Labz")!) }
                .barBoyButton()
            Spacer()
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                Text(lastUpdateLabel.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            }
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.plain).help("Quit BAR BOY")
        }
        .padding(11)
    }

    private func sectionLabel(_ title: String, note: String) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .black, design: .monospaced)).tracking(0.9).foregroundStyle(.secondary)
            Spacer()
            Text(note).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }

    private var lastUpdateLabel: String {
        guard let date = monitor.lastUpdated else { return "Reading local activity" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        return seconds < 5 ? "Updated now" : "Updated \(seconds)s ago"
    }

}

private struct ProviderUsageRow: View {
    let snapshot: ProviderSnapshot
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ProviderMark(provider: snapshot.provider, size: 24, active: snapshot.activeCount > 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.provider.name.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                    Text(snapshot.usageText.uppercased())
                        .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(percent(snapshot.shortWindowPercent)).frame(width: 46, alignment: .trailing)
                Text(percent(snapshot.weekWindowPercent)).frame(width: 46, alignment: .trailing)
                ZStack(alignment: .topTrailing) {
                    Text("\(snapshot.sessions.count)").frame(width: 38, alignment: .trailing)
                    if snapshot.needsAttentionCount > 0 {
                        Rectangle().fill(BarBoyStyle.coral).frame(width: 5, height: 11).offset(x: 5, y: -5)
                    }
                }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? Color.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "—" }
}

private struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 9) {
            ProviderMark(provider: session.provider, size: 27, active: session.isRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(session.role.rawValue.uppercased()) · \(session.project.uppercased())")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(session.attention.isUrgent ? session.attention.label : session.ageLabel)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(session.attention.isUrgent ? BarBoyStyle.coral : .secondary)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(session.attention.isUrgent ? BarBoyStyle.coral.opacity(0.10) : BarBoyStyle.raised)
                .overlay(Rectangle().stroke(session.attention.isUrgent ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
        }
        .padding(.vertical, 8)
        .help(session.attentionReason ?? session.detail)
    }
}

private struct AttentionPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Rectangle()
            .fill(BarBoyStyle.coral)
            .frame(width: 8, height: 24)
            .opacity(pulse && !reduceMotion ? 0.42 : 1)
            .scaleEffect(pulse && !reduceMotion ? 0.88 : 1)
            .onAppear { pulse = true }
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.85).repeatForever(autoreverses: true), value: pulse)
    }
}

extension Notification.Name {
    static let showCommandPalette = Notification.Name("BarBoyShowCommandPalette")
}
