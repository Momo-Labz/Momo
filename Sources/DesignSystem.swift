import AppKit
import CoreImage
import SwiftUI

enum BarBoyStyle {
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let surface = Color.primary.opacity(0.045)
    static let raised = Color.primary.opacity(0.085)
    static let hairline = Color.primary.opacity(0.22)
    static let coral = Color(red: 226 / 255, green: 92 / 255, blue: 72 / 255)
    static let ink = Color(red: 0.125, green: 0.118, blue: 0.114)
    static let paper = Color(red: 0.953, green: 0.949, blue: 0.949)
    static let inverseInk = Color(nsColor: .windowBackgroundColor)

    static let display = Font.custom("Menlo-Bold", fixedSize: 15)
    static let navLabel = Font.custom("Menlo-Bold", fixedSize: 10)
    static let sectionLabel = Font.custom("Menlo-Bold", fixedSize: 9)
    static let microLabel = Font.custom("Menlo-Bold", fixedSize: 8)
    static let alertLabel = Font.custom("Menlo-Bold", fixedSize: 9)
    static let actionLabel = Font.custom("Menlo-Bold", fixedSize: 11)
    static let rowTitle = Font.custom("Menlo-Bold", fixedSize: 10)
    static let bodySmall = Font.system(size: 11, weight: .medium)
    static let tableHeader = Font.custom("Menlo-Bold", fixedSize: 7)
    static let metric = Font.custom("Menlo-Bold", fixedSize: 13)
    static let metricSmall = Font.custom("Menlo-Bold", fixedSize: 9)
    static let capabilityMark = Font.custom("Menlo-Bold", fixedSize: 16)
    static let keycap = Font.custom("Menlo-Bold", fixedSize: 9)
    static let stroke: CGFloat = 1
    static let strokeStrong: CGFloat = 1.5
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let pageAnimation = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.20)
}

struct ProviderMark: View {
    let provider: AIProvider
    var size: CGFloat = 28
    var active = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(active ? Color.primary : BarBoyStyle.raised)
            if let icon = applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .saturation(0)
                    .contrast(1.25)
                    .padding(size * 0.14)
            } else {
                ProviderGlyph(provider: provider)
                    .foregroundStyle(active ? BarBoyStyle.inverseInk : Color.primary)
                    .padding(size * 0.19)
            }
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .accessibilityLabel(provider.name)
    }

    private var applicationIcon: NSImage? {
        for identifier in provider.applicationBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return monochrome(NSWorkspace.shared.icon(forFile: url.path))
            }
        }
        return nil
    }

    private func monochrome(_ image: NSImage) -> NSImage {
        guard let data = image.tiffRepresentation,
              let input = CIImage(data: data),
              let filter = CIFilter(name: "CIPhotoEffectMono") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        guard let output = filter.outputImage,
              let cgImage = CIContext(options: nil).createCGImage(output, from: output.extent) else { return image }
        return NSImage(cgImage: cgImage, size: image.size)
    }
}

private struct ProviderGlyph: View {
    let provider: AIProvider

    @ViewBuilder var body: some View {
        switch provider {
        case .codex:
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(lineWidth: 1.8)
                        .frame(width: 12, height: 5)
                        .offset(y: -5)
                        .rotationEffect(.degrees(Double(index) * 60))
                }
            }
        case .claude:
            Text("✳").font(.system(size: 18, weight: .bold))
        case .gemini:
            GeminiGlyphShape().fill()
        case .cursor:
            CursorGlyphShape().fill(style: FillStyle(eoFill: true))
        case .grok:
            ZStack {
                Capsule().frame(width: 4, height: 20).rotationEffect(.degrees(45))
                Capsule().frame(width: 4, height: 20).rotationEffect(.degrees(-45))
                Capsule().frame(width: 3, height: 13).rotationEffect(.degrees(45)).offset(x: 5, y: -5)
            }
        }
    }
}

private struct GeminiGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control1: CGPoint(x: rect.midX, y: rect.midY * 0.25), control2: CGPoint(x: rect.maxX * 0.75, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control1: CGPoint(x: rect.maxX * 0.75, y: rect.midY), control2: CGPoint(x: rect.midX, y: rect.maxY * 0.75))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY), control1: CGPoint(x: rect.midX, y: rect.maxY * 0.75), control2: CGPoint(x: rect.maxX * 0.25, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY), control1: CGPoint(x: rect.maxX * 0.25, y: rect.midY), control2: CGPoint(x: rect.midX, y: rect.midY * 0.25))
        return path
    }
}

private struct CursorGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX * 0.92, y: rect.midY * 1.08))
        path.closeSubpath()
        let hole = CGRect(x: rect.width * 0.34, y: rect.height * 0.34, width: rect.width * 0.24, height: rect.height * 0.24)
        path.addEllipse(in: hole)
        return path
    }
}

struct AnimatedMomoMark: View {
    let size: CGFloat
    var tile = true
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        PixelBarBoyMark(size: size, tile: tile)
            .opacity(appeared || reduceMotion || !animated ? 1 : 0.35)
            .offset(y: appeared || reduceMotion || !animated ? 0 : 4)
            .onAppear {
                guard animated && !reduceMotion else { appeared = true; return }
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)) { appeared = true }
            }
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

    func barBoyIconButton() -> some View {
        self.buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .background(BarBoyStyle.raised)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }
}

struct BarBoyPressButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.08), value: configuration.isPressed)
    }
}
