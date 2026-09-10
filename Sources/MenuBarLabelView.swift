import SwiftUI

struct MenuBarLabelView: View {
    let snapshots: [ProviderSnapshot]
    let compact: Bool

    var body: some View {
        let urgent = snapshots.reduce(0) { $0 + $1.needsAttentionCount }
        let active = snapshots.reduce(0) { $0 + $1.activeCount }
        HStack(spacing: 3) {
            PixelBarBoyMark(size: 17)
            if urgent > 0 {
                Text("!\(min(urgent, 9))")
                    .foregroundStyle(BarBoyStyle.coral)
                    .accessibilityLabel("\(urgent) sessions need attention")
            } else if !compact, active > 0 {
                Text("\(min(active, 9))")
                    .accessibilityLabel("\(active) active agents")
            }
        }
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .monospacedDigit()
        .accessibilityLabel("BAR BOY AI activity")
    }
}
