import SwiftUI

private enum RelayStyle {
    static let ink = Color.primary
    static let panel = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 32 / 255, green: 30 / 255, blue: 29 / 255, alpha: 1)
            : UIColor(red: 243 / 255, green: 242 / 255, blue: 242 / 255, alpha: 1)
    })
    static let inverseInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 32 / 255, green: 30 / 255, blue: 29 / 255, alpha: 1)
            : UIColor(red: 243 / 255, green: 242 / 255, blue: 242 / 255, alpha: 1)
    })
    static let surface = Color.primary.opacity(0.045)
    static let line = Color.primary.opacity(0.24)
    static let coral = Color(red: 226.0 / 255.0, green: 92.0 / 255.0, blue: 72.0 / 255.0)
}

struct RelayRootView: View {
    @EnvironmentObject private var store: RelayStore

    var body: some View {
        NavigationStack {
            Group {
                if store.status == nil { PairView() } else { HubView() }
            }
            .background(RelayStyle.panel.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct PairView: View {
    @EnvironmentObject private var store: RelayStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            RelayMark(size: 70)
            Text("MOMO RELAY")
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .tracking(1.2)
                .padding(.top, 22)
            Text("Your agents return here.")
                .font(.title3.weight(.semibold))
                .padding(.top, 6)
            Text("Paste the pairing address from BAR BOY on your Mac. Its one-time setup key is stored separately from the status address in this iPhone's Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            TextField("http://your-mac.local:7377/display?key=…", text: $store.pairAddress, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 11, design: .monospaced))
                .padding(12)
                .background(RelayStyle.surface)
                .overlay(Rectangle().stroke(RelayStyle.line, lineWidth: 1))
                .padding(.top, 22)
            Button("PAIR WITH MAC") { store.connect() }
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(RelayStyle.inverseInk)
                .background(Color.primary)
                .padding(.top, 10)
            if case let .offline(message) = store.connection {
                Text(message).font(.caption).foregroundStyle(RelayStyle.coral).padding(.top, 10)
            }
            Spacer()
            Text("PRIVATE / LOCAL NETWORK / READ ONLY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

private struct HubView: View {
    @EnvironmentObject private var store: RelayStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: RelaySession?
    @State private var tab: MobileHubTab = .home

    private var status: RelayStatus { store.status ?? .demo }
    private var urgent: [RelaySession] { status.sessions.filter(\.urgent) }
    private var working: [RelaySession] { status.sessions.filter { !$0.urgent } }
    private var skills: [String] { unique(status.sessions.flatMap { $0.skills ?? [] }) }
    private var mcps: [String] { unique(status.sessions.flatMap { $0.mcpServers ?? [] }) }
    private var plugins: [String] { unique(status.sessions.flatMap { $0.plugins ?? [] }) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(RelayStyle.line).frame(height: 1)
            tabBar
            Rectangle().fill(RelayStyle.line).frame(height: 1)
            ScrollView {
                Group {
                    switch tab {
                    case .home:
                        VStack(alignment: .leading, spacing: 18) { returnQueue; providerStrip }
                    case .agents:
                        sessionList
                    case .tools:
                        toolsList
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
                .padding(16)
            }
        }
        .sheet(item: $selected) { SessionSheet(session: $0) }
        .refreshable { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            RelayAnimatedMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("MOMO LABZ").font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary)
                Text("RELAY").font(.system(size: 17, weight: .black, design: .monospaced)).tracking(1)
            }
            Spacer()
            Menu {
                Button("Refresh") { Task { await store.refresh() } }
                Button("Disconnect from Mac", role: .destructive) { store.disconnect() }
            } label: {
                Text(store.connection.label)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(store.connection == .live ? .primary : RelayStyle.coral)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .overlay(Rectangle().stroke(store.connection == .live ? RelayStyle.line : RelayStyle.coral, lineWidth: 1))
            }
        }
        .padding(16)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MobileHubTab.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.20)) { tab = item }
                } label: {
                    Label(item.label, systemImage: item.symbol)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(tab == item ? RelayStyle.panel : Color.primary)
                        .background(tab == item ? Color.primary : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
    }

    private var returnQueue: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelLine(title: "YOUR TURN", note: urgent.isEmpty ? "KEEP MOVING" : "\(urgent.count) BLOCKING")
            VStack(spacing: 0) {
                if urgent.isEmpty {
                    HStack(spacing: 11) {
                        Rectangle().fill(Color.primary).frame(width: 7, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NO ONE IS WAITING").font(.system(size: 11, weight: .black, design: .monospaced))
                            Text("Your agents can keep working.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                } else {
                    ForEach(Array(urgent.enumerated()), id: \.element.id) { index, session in
                        SessionButton(session: session) { selected = session }
                        if index < urgent.count - 1 { Rectangle().fill(RelayStyle.coral.opacity(0.35)).frame(height: 1).padding(.leading, 52) }
                    }
                }
            }
            .background(urgent.isEmpty ? RelayStyle.surface : RelayStyle.coral.opacity(0.08))
            .overlay(Rectangle().stroke(urgent.isEmpty ? RelayStyle.line : RelayStyle.coral, lineWidth: urgent.isEmpty ? 1 : 1.5))
        }
    }

    private var providerStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelLine(title: "MODELS", note: "\(status.activeCount) WORKING")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(status.providers) { provider in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { RelayProviderIcon(provider: provider, size: 25); Spacer(); Text(provider.active > 0 ? "LIVE" : "IDLE").font(.system(size: 8, weight: .black, design: .monospaced)).foregroundStyle(.secondary) }
                            Text(provider.name.uppercased()).font(.system(size: 11, weight: .black, design: .monospaced))
                            Text(provider.usage.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .frame(width: 104, alignment: .leading)
                        .padding(11)
                        .background(RelayStyle.surface)
                        .overlay(Rectangle().stroke(provider.needsAttention > 0 ? RelayStyle.coral : RelayStyle.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelLine(title: "IN MOTION", note: "MODEL / MCP / SKILL / PLUGIN")
            VStack(spacing: 0) {
                ForEach(Array(working.enumerated()), id: \.element.id) { index, session in
                    SessionButton(session: session) { selected = session }
                    if index < working.count - 1 { Rectangle().fill(RelayStyle.line).frame(height: 1).padding(.leading, 52) }
                }
                if working.isEmpty { Text("CLEAR THE RETURN QUEUE ABOVE").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.secondary).padding(14) }
            }
            .background(RelayStyle.surface)
            .overlay(Rectangle().stroke(RelayStyle.line, lineWidth: 1))
        }
    }

    private var toolsList: some View {
        VStack(alignment: .leading, spacing: 18) {
            MobileCapabilitySection(title: "SKILLS", values: skills)
            MobileCapabilitySection(title: "MCP SERVERS", values: mcps)
            MobileCapabilitySection(title: "PLUGINS", values: plugins)
            Text("CAPABILITIES ARE READ FROM EACH SESSION'S LOCAL EVENT LOG.")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func unique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private enum MobileHubTab: String, CaseIterable, Identifiable {
    case home, agents, tools
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .agents: return "sparkles"
        case .tools: return "square.stack.3d.up.fill"
        }
    }
}

private struct MobileCapabilitySection: View {
    let title: String
    let values: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelLine(title: title, note: "\(values.count) DETECTED")
            VStack(spacing: 0) {
                if values.isEmpty {
                    Text("NONE RECORDED").font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                } else {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        HStack { Text(value.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)); Spacer() }
                            .padding(12)
                        if index < values.count - 1 { Rectangle().fill(RelayStyle.line).frame(height: 1) }
                    }
                }
            }
            .background(RelayStyle.surface)
            .overlay(Rectangle().stroke(RelayStyle.line, lineWidth: 1))
        }
    }
}

private struct RelayProviderIcon: View {
    let provider: RelayProvider
    let size: CGFloat
    var body: some View {
        ZStack {
            Rectangle().fill(provider.active > 0 ? Color.primary : RelayStyle.surface)
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .saturation(0)
                    .contrast(1.2)
                    .padding(size * 0.13)
            } else {
                Group {
                    switch provider.id.lowercased() {
                    case "gemini": Text("✦")
                    case "grok": Text("𝕏")
                    default: Text(provider.mark)
                    }
                }
                .font(.system(size: size * 0.52, weight: .black, design: .monospaced))
                .foregroundStyle(provider.active > 0 ? RelayStyle.panel : Color.primary)
            }
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().stroke(RelayStyle.line, lineWidth: 1))
        .accessibilityLabel(provider.name)
    }

    private var assetName: String? {
        switch provider.id.lowercased() {
        case "codex": return "ProviderCodex"
        case "claude": return "ProviderClaude"
        case "cursor": return "ProviderCursor"
        default: return nil
        }
    }
}

private struct SessionButton: View {
    let session: RelaySession
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(session.mark).font(.headline).frame(width: 31, height: 31).foregroundStyle(Color(UIColor.systemBackground)).background(Color.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(session.urgent ? (session.attentionReason ?? session.attentionLabel) : session.provenance)
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(session.urgent ? RelayStyle.coral : .secondary).lineLimit(1)
                }
                Spacer()
                Text(session.urgent ? "!" : session.age).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(session.urgent ? RelayStyle.coral : .secondary)
            }
            .padding(11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: RelaySession

    var body: some View {
        NavigationStack {
            List {
                if session.urgent { Section("Return") { Text(session.attentionReason ?? "This agent needs you") } }
                Section("Model") { Text((session.model?.isEmpty == false ? session.model : nil) ?? "Not recorded") }
                Section("MCP servers") { rows(session.mcpServers) }
                Section("Skills") { rows(session.skills) }
                Section("Plugins") { rows(session.plugins) }
            }
            .navigationTitle(session.provider)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    @ViewBuilder private func rows(_ values: [String]?) -> some View {
        if let values, !values.isEmpty { ForEach(values, id: \.self) { Text($0) } } else { Text("None recorded").foregroundStyle(.secondary) }
    }
}

private struct LabelLine: View {
    let title: String
    let note: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .black, design: .monospaced)).tracking(0.8).foregroundStyle(.secondary)
            Spacer()
            Text(note).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }
}

private struct RelayMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Rectangle().stroke(Color.primary, lineWidth: max(2, size * 0.06))
            VStack(spacing: size * 0.08) {
                HStack(spacing: size * 0.13) { Rectangle().frame(width: size * 0.12, height: size * 0.12); Rectangle().frame(width: size * 0.12, height: size * 0.12) }
                Rectangle().frame(width: size * 0.38, height: max(2, size * 0.06))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct RelayAnimatedMark: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        RelayMark(size: size)
            .opacity(appeared || reduceMotion ? 1 : 0.35)
            .offset(y: appeared || reduceMotion ? 0 : 4)
            .onAppear {
                guard !reduceMotion else { appeared = true; return }
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)) { appeared = true }
            }
    }
}
