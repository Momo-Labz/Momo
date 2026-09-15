import SwiftUI

/// UI seam for provider usage capture. The capture service will supply the
/// isolated WebKit/manual result once its contract is available; this view
/// deliberately does not claim a value or write a usage observation yet.
struct UsageCaptureView: View {
    let provider: AIProvider
    let onBack: () -> Void
    @State private var interval = "Manual"
    @State private var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CONNECT \(provider.name.uppercased()) USAGE").font(BarBoyStyle.sectionLabel)
            Text("Capture runs in an isolated provider page. MOMO will show a preview before any recorded value is saved.").font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
            Picker("Capture interval", selection: $interval) {
                Text("Manual").tag("Manual")
                Text("15 minutes").tag("15 minutes")
                Text("30 minutes").tag("30 minutes")
                Text("60 minutes").tag("60 minutes")
            }.pickerStyle(.segmented)
            if preview {
                Text("Preview unavailable until the usage capture service is connected.").font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                Text("No usage value has been recorded.").font(BarBoyStyle.microLabel).foregroundStyle(BarBoyStyle.amber)
            }
            HStack {
                Button("BACK", role: .cancel, action: onBack).barBoyButton()
                Spacer()
                Button(preview ? "CONFIRM PREVIEW" : "PREVIEW") { preview = true }.barBoyButton()
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(BarBoyStyle.panel)
    }
}
