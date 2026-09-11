import SwiftUI

enum CapabilityInventoryScope: String, Identifiable {
    case skills
    case integrations

    var id: String { rawValue }
    var title: String { self == .skills ? "SKILLS" : "INTEGRATIONS" }
}

struct CapabilityInventoryView: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var scope: CapabilityInventoryScope

    init(initialScope: CapabilityInventoryScope) {
        _scope = State(initialValue: initialScope)
    }

    private var items: [InstalledCapability] {
        monitor.capabilityInventory.items
            .filter { capability in
                scope == .skills ? capability.kind == .skill : capability.kind != .skill
            }
            .sorted {
                if $0.isUsed != $1.isUsed { return $0.isUsed }
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var usedCount: Int { items.filter(\.isUsed).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PixelBarBoyMark(size: 30, tile: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("INSTALLED INVENTORY").font(BarBoyStyle.display)
                    Text("LOCAL METADATA ONLY / USED MARKS COME FROM SESSION RECEIPTS")
                        .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                }
                Spacer()
                Button("DONE") { dismiss() }.barBoyButton()
            }
            .padding(16)

            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)

            HStack(spacing: 4) {
                ForEach([CapabilityInventoryScope.skills, .integrations]) { item in
                    Button {
                        scope = item
                    } label: {
                        Text(item.title).font(BarBoyStyle.navLabel)
                            .foregroundStyle(scope == item ? BarBoyStyle.inverseInk : Color.primary)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(scope == item ? Color.primary : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(usedCount) USED / \(items.count) INSTALLED")
                    .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }
            .padding(12)

            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(items) { item in
                        CapabilityInventoryRow(item: item)
                    }
                }
                .padding(12)
            }
            .overlay {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.dashed").font(.system(size: 22))
                        Text("NO \(scope.title) FOUND").font(BarBoyStyle.sectionLabel)
                        Text("Enable a provider after installing its local tools.")
                            .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                    }
                }
            }

            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)

            HStack {
                Text("USED means a supported transcript recorded the capability.")
                    .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                Spacer()
                if !monitor.capabilityInventory.marketplaces.isEmpty {
                    Text("\(monitor.capabilityInventory.marketplaces.count) MARKETPLACES")
                        .font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).frame(height: 42)
        }
        .frame(width: 600, height: 480)
        .background(BarBoyStyle.panel)
    }
}

private struct CapabilityInventoryRow: View {
    let item: InstalledCapability

    private var owners: String {
        let providerNames = item.providerOwners.map(\.rawValue).sorted().map { $0.uppercased() }
        let values = providerNames + (item.isShared ? ["SHARED"] : [])
        return values.isEmpty ? "LOCAL" : values.joined(separator: " + ")
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Rectangle().fill(item.isUsed ? Color.primary : BarBoyStyle.raised)
                Text(String(item.name.prefix(2)).uppercased())
                    .font(BarBoyStyle.rowTitle)
                    .foregroundStyle(item.isUsed ? BarBoyStyle.inverseInk : Color.primary)
            }
            .frame(width: 34, height: 34)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.uppercased()).font(BarBoyStyle.rowTitle).lineLimit(1)
                Text("\(item.kind.label) / \(owners)")
                    .font(BarBoyStyle.microLabel).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(item.isUsed ? "USED" : "INSTALLED")
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(item.isUsed ? Color.primary : Color.secondary)
        }
        .padding(9)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.kind.label), \(item.isUsed ? "used in a session" : "installed"), \(owners)")
    }
}
