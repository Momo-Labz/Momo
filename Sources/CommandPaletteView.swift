import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @State private var provider: AIProvider = .codex
    @State private var prompt = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var versionLabel: String {
        let version = BarBoyAppInfo.marketingVersion
        return version == "Development" ? version.uppercased() : "V\(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PixelBarBoyMark(size: 32, tile: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MOMO LABZ / QUICK ASK")
                        .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1)
                    Text("Route a thought without losing your place")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("⌃⌥SPACE").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(AIProvider.allCases) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : BarBoyStyle.pageAnimation) { provider = item }
                    } label: {
                        Text(item.name.uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(provider == item ? Color.primary : BarBoyStyle.surface)
                            .foregroundStyle(provider == item ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                    }
                    .buttonStyle(.plain)
                    if item != AIProvider.allCases.last { Rectangle().fill(BarBoyStyle.hairline).frame(width: 1) }
                }
            }
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))

            TextEditor(text: $prompt)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(9)
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .frame(height: 108)

            HStack {
                Text("\(versionLabel) COPIES YOUR PROMPT, THEN OPENS THE PROVIDER")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("CANCEL") { dismiss() }.barBoyButton()
                Button("COPY + OPEN \(provider.name.uppercased())") { routePrompt() }
                    .barBoyButton().disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520, height: 280)
        .background(BarBoyStyle.panel)
    }

    private func routePrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        if provider == .cursor,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        } else if let url = provider.conversationURL {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}
