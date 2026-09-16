import SwiftUI

/// MOMO3-era continuous usage bar (from CompactProviderCell / UsageMeter).
/// Unknown percentages render as an empty track — never invents a fill.
struct UsageMeter: View {
    let percent: Double?
    var alert = false
    var height: CGFloat = 6

    init(percent: Int?, alert: Bool = false, height: CGFloat = 6) {
        self.percent = percent.map(Double.init)
        self.alert = alert
        self.height = height
    }

    init(percent: Double?, alert: Bool = false, height: CGFloat = 6) {
        self.percent = percent
        self.alert = alert
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(BarBoyStyle.hairline.opacity(0.5))
                if let percent {
                    Rectangle()
                        .fill(alert || percent >= 100 ? BarBoyStyle.coral : BarBoyStyle.amber)
                        .frame(width: proxy.size.width * CGFloat(min(max(percent, 0), 100) / 100))
                }
            }
        }
        .frame(height: height)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .help(percent.map { "Recorded usage \(String(format: "%.0f", $0))%" } ?? "No recorded usage percentage")
        .accessibilityLabel(percent.map { "Usage \($0.rounded()) percent" } ?? "Usage unknown")
    }
}

/// Compact dual-window meter: always shows 5HR + W slots (dashes when unknown).
struct DualUsageMeters: View {
    let fiveHour: UsagePeekMetric
    let weekly: UsagePeekMetric
    var compact = false
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            windowRow(label: "5HR", metric: fiveHour)
            windowRow(label: "W", metric: weekly)
        }
    }

    private func windowRow(label: String, metric: UsagePeekMetric) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 22 : 28, alignment: .leading)
            UsageMeter(percent: metric.percentage, alert: (metric.percentage ?? 0) >= 100, height: compact ? 4 : 6)
            Text(metric.percentage.map { "\($0)%" } ?? "—")
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: compact ? 28 : 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(metric.valueLabel(now: now))")
    }
}
