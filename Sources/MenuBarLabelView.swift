import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    let snapshots: [ProviderSnapshot]
    let compact: Bool

    var body: some View {
        let urgent = snapshots.reduce(0) { $0 + $1.needsAttentionCount }
        let active = snapshots.reduce(0) { $0 + $1.activeCount }
        HStack(spacing: 3) {
            Image(nsImage: Self.statusIcon)
                .renderingMode(.template)
                .interpolation(.none)
                .frame(width: 18, height: 18)
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
        .accessibilityLabel("MOMO AI activity")
    }

    static let statusIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { bounds in
            NSColor.black.setFill()
            let scale = min(bounds.width, bounds.height) / 16
            let origin = CGPoint(x: bounds.midX - 8 * scale, y: bounds.midY - 8 * scale)

            func block(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
                NSBezierPath(rect: NSRect(
                    x: origin.x + CGFloat(x) * scale,
                    y: origin.y + CGFloat(y) * scale,
                    width: CGFloat(width) * scale,
                    height: CGFloat(height) * scale
                )).fill()
            }

            block(2, 1, 12, 1); block(2, 2, 1, 7); block(13, 2, 1, 7)
            block(2, 9, 12, 1); block(2, 11, 12, 1); block(7, 10, 2, 3)
            block(5, 3, 1, 1); block(8, 3, 1, 1)
            block(4, 5, 1, 2); block(5, 6, 5, 1); block(10, 5, 1, 2)
            block(6, 12, 4, 1); block(5, 13, 3, 1); block(8, 13, 3, 1)
            block(4, 14, 3, 1); block(10, 14, 3, 1); block(3, 15, 3, 1); block(11, 15, 3, 1)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
