import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    let snapshots: [ProviderSnapshot]
    let compact: Bool
    @ObservedObject var attentionNotifier: AttentionNotifier

    var body: some View {
        let waiting = snapshots.reduce(0) { $0 + $1.waitingCount }
        let failed = snapshots.reduce(0) { $0 + $1.failedCount }
        let active = snapshots.reduce(0) { $0 + $1.activeCount }
        let completed = attentionNotifier.completedSessions.count
        HStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: Self.statusIcon)
                    .renderingMode(.template)
                    .interpolation(.none)
                    .frame(width: 18, height: 18)
                // A flat tab on the corner of the mark. Deliberately static:
                // a menu-bar item is on screen all day and must not pulse.
                if waiting > 0 || failed > 0 || completed > 0 {
                    Rectangle()
                        .fill(failed > 0 ? BarBoyStyle.coral : (waiting > 0 ? BarBoyStyle.amber : .green))
                        .frame(width: 5, height: 5)
                        .offset(x: 1, y: -1)
                }
            }
            if failed > 0 {
                Text("!\(min(failed, 9))")
                    .foregroundStyle(BarBoyStyle.coral)
                    .accessibilityLabel("\(failed) sessions failed")
            } else if waiting > 0 {
                Text("?\(min(waiting, 9))")
                    .foregroundStyle(BarBoyStyle.amber)
                    .accessibilityLabel("\(waiting) sessions are waiting for you")
            } else if completed > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(completed) sessions finished")
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
            // Keep the menu-bar mark readable against the dark MOMO surface.
            // This is intentionally an explicit white mark rather than a
            // template image so AppKit does not tint it gray in compact mode.
            NSColor.white.setFill()
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
        image.isTemplate = false
        return image
    }()
}
