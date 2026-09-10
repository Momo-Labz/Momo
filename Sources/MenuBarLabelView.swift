import SwiftUI

struct MenuBarLabelView: View {
    let snapshots: [ProviderSnapshot]
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 3 : 5) {
            PixelBarBoyMark(size: 17)
            if !compact {
                ForEach(snapshots.filter { $0.activeCount > 0 || $0.localTokensToday > 0 }.prefix(3)) { snapshot in
                    Text(snapshot.provider.monogram + " " + snapshot.usageText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityLabel("BAR BOY AI activity")
    }
}
