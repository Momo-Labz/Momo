import SwiftUI

private enum RelayStyle {
    static let ink = Color.primary
    static let panel = Color(uiColor: .systemBackground)
    static let surface = Color.primary.opacity(0.045)
    static let line = Color.primary.opacity(0.24)
    static let coral = Color(red: 0.91, green: 0.25, blue: 0.15)
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
            Text("Paste the pairing address from BAR BOY on your Mac. The address includes a private local key and stays in this iPhone's Keychain.")
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
                .foregroundStyle(Color(UIColor.systemBackground))
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
    @State private var selected: RelaySession?

    private var status: RelayStatus { store.status ?? .demo }
    private var urgent: [RelaySession] { status.sessions.filter(\.urgent) }
    private var working: [RelaySession] { status.sessions.filter { !$0.urgent } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(RelayStyle.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    returnQueue
                    providerStrip
                    sessionList
                }
                .padding(16)
            }
        }
        .sheet(item: $selected) { SessionSheet(session: $0) }
        .refreshable { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            RelayMark(size: 38)
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
                            HStack { Text(provider.mark).font(.headline); Spacer(); Text(provider.active > 0 ? "LIVE" : "IDLE").font(.system(size: 8, weight: .black, design: .monospaced)).foregroundStyle(.secondary) }
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
