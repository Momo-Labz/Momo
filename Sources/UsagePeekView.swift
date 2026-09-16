import SwiftUI

/// Compact metric row for the menu-bar usage peek (5-hour + Weekly).
struct UsagePeekMetric: Equatable {
    var percentage: Int?
    var resetsAt: Date?

    static let empty = UsagePeekMetric(percentage: nil, resetsAt: nil)

    func valueLabel(now: Date = .now) -> String {
        guard let percentage else { return "—" }
        if let resetsAt, resetsAt > now {
            return "\(percentage)% · resets \(Self.resetShort(resetsAt, now: now))"
        }
        return "\(percentage)%"
    }

    private static func resetShort(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds >= 86_400 {
            let days = Int((seconds / 86_400).rounded(.down))
            return "\(max(1, days))d"
        }
        if seconds >= 3_600 {
            let hours = Int((seconds / 3_600).rounded(.down))
            return "\(max(1, hours))h"
        }
        let minutes = max(1, Int((seconds / 60).rounded(.down)))
        return "\(minutes)m"
    }
}

struct UsagePeekRow: Identifiable, Equatable {
    let provider: AIProvider
    var fiveHour: UsagePeekMetric
    var weekly: UsagePeekMetric
    var id: AIProvider { provider }
}

/// Maps accepted observations / recorded snapshot windows onto 5-hour and Weekly peek slots.
/// Never invents percentages — unmatched metrics stay empty dashes.
enum UsagePeekMapping {
    enum LimitKind: Equatable {
        case fiveHour
        case weekly
    }

    static func rows(
        allowed: [AIProvider],
        observations: [ProviderUsageObservation],
        snapshots: [ProviderSnapshot],
        now: Date = .now
    ) -> [UsagePeekRow] {
        let byProvider = Dictionary(grouping: observations.filter { $0.isFresh(at: now) }, by: \.provider)
        let snapshotByProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        return allowed.map { provider in
            let mapped = map(
                observations: byProvider[provider] ?? [],
                snapshot: snapshotByProvider[provider],
                now: now
            )
            return UsagePeekRow(provider: provider, fiveHour: mapped.fiveHour, weekly: mapped.weekly)
        }
    }

    static func map(
        observations: [ProviderUsageObservation],
        snapshot: ProviderSnapshot?,
        now: Date = .now
    ) -> (fiveHour: UsagePeekMetric, weekly: UsagePeekMetric) {
        let fresh = observations.filter { $0.isFresh(at: now) }
        let fiveHour = pick(fresh, kind: .fiveHour)
            ?? windowMetric(from: snapshot, kind: .fiveHour)
            ?? snapshotMetric(percent: snapshot?.shortWindowPercent, resetsAt: shortReset(from: snapshot))
            ?? .empty
        let weekly = pick(fresh, kind: .weekly)
            ?? windowMetric(from: snapshot, kind: .weekly)
            ?? snapshotMetric(percent: snapshot?.weekWindowPercent, resetsAt: weekReset(from: snapshot))
            ?? .empty
        return (fiveHour, weekly)
    }

    /// Prefer recorded quota windows by duration (5h / week) when observation labels are absent.
    private static func windowMetric(from snapshot: ProviderSnapshot?, kind: LimitKind) -> UsagePeekMetric? {
        let windows = recordedWindows(snapshot)
        let match: RecordedQuotaWindow?
        switch kind {
        case .fiveHour:
            match = windows.filter { $0.minutes < 10080 }.sorted { $0.minutes < $1.minutes }.first
        case .weekly:
            match = windows.filter { $0.minutes >= 10080 }.sorted { $0.minutes > $1.minutes }.first
        }
        guard let match else { return nil }
        let percent = Int(match.percent.rounded())
        guard (0...100).contains(percent) else { return nil }
        return UsagePeekMetric(percentage: percent, resetsAt: match.resetsAt)
    }

    private static func pick(_ observations: [ProviderUsageObservation], kind: LimitKind) -> UsagePeekMetric? {
        guard let match = observations.first(where: { matches($0.metric, kind: kind) }) else { return nil }
        return UsagePeekMetric(percentage: match.percentage, resetsAt: match.resetsAt)
    }

    static func matches(_ metric: String, kind: LimitKind) -> Bool {
        let normalized = metric.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        switch kind {
        case .fiveHour:
            if normalized.contains("week") || normalized.contains("7 day") || normalized == "long" { return false }
            if normalized.contains("5 hour") || normalized.contains("5hour") || normalized.contains("5hr") { return true }
            if normalized == "5h" || normalized.hasPrefix("5h ") { return true }
            if normalized == "short" || normalized.contains("short window") { return true }
            if normalized.contains("300") && normalized.contains("min") { return true }
            return false
        case .weekly:
            if normalized.contains("5 hour") || normalized.contains("5hr") || normalized == "5h" { return false }
            if normalized.contains("week") || normalized.contains("1 week") || normalized.contains("7 day") { return true }
            if normalized == "long" || normalized.contains("long window") { return true }
            if normalized.contains("10080") { return true }
            return false
        }
    }

    private static func snapshotMetric(percent: Int?, resetsAt: Date?) -> UsagePeekMetric? {
        guard let percent, (0...100).contains(percent) else { return nil }
        return UsagePeekMetric(percentage: percent, resetsAt: resetsAt)
    }

    private static func shortReset(from snapshot: ProviderSnapshot?) -> Date? {
        let windows = recordedWindows(snapshot)
        return windows.filter { $0.minutes < 10080 }.compactMap(\.resetsAt).min()
    }

    private static func weekReset(from snapshot: ProviderSnapshot?) -> Date? {
        let windows = recordedWindows(snapshot)
        return windows.filter { $0.minutes >= 10080 }.compactMap(\.resetsAt).min()
    }

    private static func recordedWindows(_ snapshot: ProviderSnapshot?) -> [RecordedQuotaWindow] {
        guard let snapshot else { return [] }
        if !snapshot.recordedQuotas.isEmpty { return snapshot.recordedQuotas }
        return snapshot.recordedQuota.map { [$0] } ?? []
    }
}

struct UsagePeekView: View {
    let rows: [UsagePeekRow]
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR USAGE LIMITS")
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("No providers allowed yet. Choose providers in Settings.")
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    providerBlock(row)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(BarBoyStyle.panel)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }

    private func providerBlock(_ row: UsagePeekRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderMark(provider: row.provider, size: 18, active: true)
                Text(row.provider.name.uppercased())
                    .font(BarBoyStyle.microLabel)
                Spacer(minLength: 0)
            }
            limitRow(title: "5HR", metric: row.fiveHour)
            limitRow(title: "W", metric: row.weekly)
        }
        .padding(.vertical, 4)
    }

    private func limitRow(title: String, metric: UsagePeekMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(BarBoyStyle.bodySmall)
                Spacer(minLength: 8)
                Text(metric.valueLabel(now: now))
                    .font(BarBoyStyle.microLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            UsageMeter(percent: metric.percentage, alert: (metric.percentage ?? 0) >= 100, height: 6)
        }
    }
}
