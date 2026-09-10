import SwiftUI

enum BarBoyStyle {
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let surface = Color.primary.opacity(0.045)
    static let raised = Color.primary.opacity(0.085)
    static let hairline = Color.primary.opacity(0.22)
    static let quiet = Color.secondary.opacity(0.72)
    static let coral = Color(red: 0.88, green: 0.36, blue: 0.28)
    static let ink = Color(red: 0.125, green: 0.118, blue: 0.114)
    static let paper = Color(red: 0.953, green: 0.949, blue: 0.949)
}

struct ProviderMark: View {
    let provider: AIProvider
    var size: CGFloat = 28
    var active = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(active ? Color.primary : BarBoyStyle.raised)
            Text(provider.monogram)
                .font(.system(size: size * 0.40, weight: .black, design: .monospaced))
                .foregroundStyle(active ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .accessibilityLabel(provider.name)
    }
}

struct PixelBarBoyMark: View {
    var size: CGFloat = 34
    var tile = false

    var body: some View {
        ZStack {
            if tile {
                Rectangle()
                    .fill(Color.primary)
            }
            PixelBarBoyShape()
                .fill(tile ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .padding(tile ? size * 0.12 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct PixelBarBoyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let origin = CGPoint(x: rect.midX - 8 * scale, y: rect.midY - 8 * scale)
        var path = Path()
        func block(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
            path.addRect(CGRect(x: origin.x + CGFloat(x) * scale,
                                y: origin.y + CGFloat(y) * scale,
                                width: CGFloat(width) * scale,
                                height: CGFloat(height) * scale))
        }
        // Monitor frame and stand, expressed on a crisp 16 × 16 pixel grid.
        block(2, 1, 12, 1); block(2, 2, 1, 7); block(13, 2, 1, 7)
        block(2, 9, 12, 1); block(2, 11, 12, 1); block(7, 10, 2, 3)
        // Face.
        block(5, 3, 1, 1); block(8, 3, 1, 1)
        block(4, 5, 1, 2); block(5, 6, 5, 1); block(10, 5, 1, 2)
        // Pixel person beneath the screen.
        block(6, 12, 4, 1); block(5, 13, 3, 1); block(8, 13, 3, 1)
        block(4, 14, 3, 1); block(10, 14, 3, 1); block(3, 15, 3, 1); block(11, 15, 3, 1)
        return path
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(12)
            .background(BarBoyStyle.surface, in: Rectangle())
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }
}

extension View {
    func barBoyButton() -> some View {
        self.buttonStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(BarBoyStyle.raised, in: Rectangle())
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }
}
