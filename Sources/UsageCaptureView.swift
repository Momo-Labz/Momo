import AppKit
import SwiftUI
import WebKit

/// Connects one provider's official usage page through `UsageCaptureService`.
/// Manual preview only: timed intervals stay visible as NEXT, not scheduled.
struct UsageCaptureView: View {
    let provider: AIProvider
    @EnvironmentObject private var monitor: ActivityMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var service = UsageCaptureService()
    @State private var webView: WKWebView?
    @State private var previewObservations: [ProviderUsageObservation] = []
    @State private var confirmed = false
    @State private var busy = false

    private var canCapture: Bool { provider.supportsUsageCapture }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    steps
                    intervalRow
                    statusBlock
                    if canCapture {
                        webPane
                        if !previewObservations.isEmpty { previewList }
                    } else {
                        awaitingProvider
                    }
                }
                .padding(14)
            }
            Divider().opacity(0.55)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BarBoyStyle.panel)
        .onAppear { openPageIfNeeded() }
        .onDisappear {
            service.cancel()
            webView?.stopLoading()
            webView = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONNECT \(provider.name.uppercased()) USAGE")
                .font(BarBoyStyle.sectionLabel)
            Text("Isolated WebKit on the official host. Sign in there if needed. Preview before any value is saved.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var steps: some View {
        HStack(spacing: 6) {
            stepChip(1, "OPEN", active: true)
            stepChip(2, "SIGN IN", active: service.state == .ready || service.state == .parsing || !previewObservations.isEmpty)
            stepChip(3, "PREVIEW", active: !previewObservations.isEmpty || service.state == .parsing)
            stepChip(4, "CONFIRM", active: confirmed)
        }
    }

    private func stepChip(_ number: Int, _ title: String, active: Bool) -> some View {
        Text("\(number) \(title)")
            .font(BarBoyStyle.microLabel)
            .foregroundStyle(active ? BarBoyStyle.inverseInk : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(active ? Color.primary : BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private var intervalRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CAPTURE INTERVAL").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                intervalChip("MANUAL", selected: true, enabled: true)
                intervalChip("15 MIN · NEXT", selected: false, enabled: false)
                intervalChip("30 MIN · NEXT", selected: false, enabled: false)
                intervalChip("60 MIN · NEXT", selected: false, enabled: false)
            }
            Text("Timed capture is not scheduled in this build. Manual preview only.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
        }
    }

    private func intervalChip(_ title: String, selected: Bool, enabled: Bool) -> some View {
        Text(title)
            .font(BarBoyStyle.microLabel)
            .foregroundStyle(selected ? BarBoyStyle.inverseInk : .secondary)
            .opacity(enabled ? 1 : 0.55)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.primary : BarBoyStyle.raised)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(service.status.isEmpty ? "IDLE" : service.status)
                .font(BarBoyStyle.navLabel)
                .foregroundStyle(statusColor)
            Text(service.guidance)
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(statusStroke, lineWidth: 1))
    }

    private var statusColor: Color {
        switch service.state {
        case .offline, .failed, .malformed: return BarBoyStyle.coral
        case .parsing, .loading: return BarBoyStyle.amber
        case .ready where confirmed: return Color.primary
        default: return Color.primary
        }
    }

    private var statusStroke: Color {
        switch service.state {
        case .offline, .failed: return BarBoyStyle.coral
        case .malformed: return BarBoyStyle.amber
        default: return BarBoyStyle.hairline
        }
    }

    @ViewBuilder private var webPane: some View {
        if let webView {
            UsageCaptureWebView(webView: webView)
                .frame(minHeight: 210, maxHeight: 280)
                .frame(maxWidth: .infinity)
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .accessibilityLabel("\(provider.name) official usage page")
        } else if canCapture {
            Text("Preparing isolated usage page…")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        }
    }

    private var previewList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            ForEach(previewObservations) { observation in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(observation.metric.uppercased())
                        .font(BarBoyStyle.rowTitle)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(observation.percentage.map { "\($0)%" } ?? "—")
                        .font(BarBoyStyle.metricSmall)
                    Text(observation.provenance.label)
                        .font(BarBoyStyle.microLabel)
                        .foregroundStyle(.secondary)
                }
                .padding(9)
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            }
            if let reset = previewObservations.compactMap(\.resetsAt).min() {
                Text("RESET · \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var awaitingProvider: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AWAITING PROVIDER PAGE")
                .font(BarBoyStyle.rowTitle)
            Text("MOMO has no allowlisted official usage URL for \(provider.name) yet. It will not invent quotas or scrape other browsers.")
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.amber, lineWidth: 1))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if busy || service.state == .parsing {
                Button("CANCEL") {
                    service.cancel()
                    busy = false
                }
                .barBoyButton()
            }
            Spacer()
            if confirmed {
                Text("SAVED LOCALLY")
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
            } else if !previewObservations.isEmpty {
                Button("CONFIRM PREVIEW") { Task { await confirmPreview() } }
                    .barBoyButton()
                    .disabled(busy)
            } else {
                Button("PREVIEW") { Task { await runPreview() } }
                    .barBoyButton()
                    .disabled(!canCapture || busy || webView == nil || service.state == .loading || service.state == .parsing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openPageIfNeeded() {
        guard canCapture, webView == nil else { return }
        webView = service.makeWebView(for: provider)
    }

    private func runPreview() async {
        guard let webView, !busy else { return }
        busy = true
        confirmed = false
        defer { busy = false }
        let observations = await service.observations(from: webView)
        withAnimation(reduceMotion ? nil : BarBoyStyle.pageAnimation) {
            previewObservations = observations
        }
    }

    private func confirmPreview() async {
        guard !previewObservations.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        let saved = await service.acceptPreview(previewObservations)
        confirmed = saved > 0
        monitor.refresh()
    }
}

private struct UsageCaptureWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
