import SwiftUI

/// Tracking-first iPhone surface. It keeps the relay read-only and mirrors the
/// same three destinations as the Mac surface.
struct ContentView: View {
    @EnvironmentObject private var store: RelayStore
    @State private var tab: TrackerTab = .activity
    @State private var selected: RelaySession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: RelayStatus { store.status ?? .demo }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RelayMark(size: 28)
                Text("MOMO").font(.system(size: 17, weight: .black, design: .monospaced)).tracking(1)
                Spacer()
                Text(store.status == nil ? "NOT CONNECTED" : store.connection.label.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(16)
            Divider()
            HStack(spacing: 4) {
                ForEach(TrackerTab.allCases) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { tab = item }
                    } label: {
                        Text(item.title.uppercased()).font(.system(size: 10, weight: .black, design: .monospaced))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(tab == item ? Color(.systemBackground) : .primary)
                            .background(tab == item ? Color.primary : .clear)
                    }.buttonStyle(.plain)
                }
            }.padding(4)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .activity: activity
                    case .usage: usage
                    case .brain: brain
                    case .upgrade: upgrade
                    }
                }.padding(16)
            }
        }
        .background(Color(.systemBackground))
        .sheet(item: $selected) { session in MobileSessionDetail(session: session) }
        .refreshable { await store.refresh() }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVITY").font(.system(size: 11, weight: .black, design: .monospaced))
            ForEach(status.sessions) { session in
                Button { selected = session } label: {
                    HStack(spacing: 10) {
                        Rectangle().fill(session.urgent ? Color.orange : Color.primary).frame(width: 4, height: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                            Text("\(session.provider.uppercased()) · \(session.project) · \(session.attentionLabel)").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(); Text(session.age).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
                    }.padding(11).background(Color.primary.opacity(0.05)).overlay(Rectangle().stroke(Color.primary.opacity(0.2)))
                }.buttonStyle(.plain)
            }
            if status.sessions.isEmpty { Text("No recorded activity yet.").foregroundStyle(.secondary) }
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("USAGE").font(.system(size: 11, weight: .black, design: .monospaced))
            Text("Usage meters live on the Mac app from desktop-local data only. Empty means unknown — never invented.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var upgrade: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UPGRADE").font(.system(size: 11, weight: .black, design: .monospaced))
            Text("MOMO+ unlocks unlimited Talk, more than 2 providers, and analytics on the Mac app.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var brain: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BRAIN").font(.system(size: 11, weight: .black, design: .monospaced))
            Text("Not connected").font(.headline)
            Text("Connect a local MOMO Brain vault to see memory. No provider content is inferred.").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MobileSessionDetail: View {
    let session: RelaySession
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.title).font(.title2.bold())
            Text("\(session.provider) · \(session.project)").font(.caption).foregroundStyle(.secondary)
            Text(session.attentionReason ?? session.attentionLabel).font(.body)
            Spacer()
            Text("READ ONLY").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(20)
    }
}
