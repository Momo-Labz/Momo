import AppKit
import CoreImage
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

// Native port of Branding/index.html: fig(), LOOK, WALK and ANIMS.
// Coordinates and holds match the index; animation never implies session status.
enum MomoMotion {
    case loop, wave, blink

    var frames: [MomoPixelFrame] {
        switch self {
        case .loop:
            let walk = [
                MomoPixelFrame(look: 1, arms: .up, legs: .swingR, milliseconds: 220),
                MomoPixelFrame(look: 1, legs: .pass, milliseconds: 180),
                MomoPixelFrame(look: 1, arms: .down, legs: .swingL, milliseconds: 220),
                MomoPixelFrame(look: 1, legs: .pass, milliseconds: 180)
            ]
            return [
                MomoPixelFrame(milliseconds: 1100), MomoPixelFrame(look: 1, milliseconds: 220),
                MomoPixelFrame(look: 2, milliseconds: 1000), MomoPixelFrame(look: 1, milliseconds: 220),
                MomoPixelFrame(milliseconds: 700)
            ] + walk + walk + [MomoPixelFrame(milliseconds: 600)]
        case .wave:
            return [MomoPixelFrame(look: 1, arms: .up, milliseconds: 300),
                    MomoPixelFrame(look: 1, arms: .down, milliseconds: 300)]
        case .blink:
            return [MomoPixelFrame(milliseconds: 2200), MomoPixelFrame(closed: true, milliseconds: 200)]
        }
    }
}

struct MomoPixelFrame {
    enum Arms { case flat, up, down }
    enum Legs { case stand, swingR, pass, swingL }
    var look = 0
    var closed = false
    var arms: Arms = .flat
    var legs: Legs = .stand
    var milliseconds = 100

    var rows: [[Bool]] {
        func line(_ pixels: [Int]) -> [Bool] { (0..<13).map { pixels.contains($0) } }
        let edge = [1, 11]
        var rows = [line(Array(1...11)), line(edge),
                    line(closed ? edge : edge + [4 + look, 6 + look]), line(edge),
                    line(edge + [3 + look, 7 + look]), line(edge + Array((3 + look)...(7 + look))),
                    line(edge), line(Array(1...11)), line([6])]
        switch arms {
        case .flat: rows += [line(Array(1...11)), line([6])]
        case .up: rows += [line(Array(1...6)), line(Array(6...11))]
        case .down: rows += [line(Array(6...11)), line(Array(1...6))]
        }
        rows += [line([5, 6, 7]), line([4, 5, 7, 8])]
        switch legs {
        case .stand: rows += [line([3, 4, 8, 9])]
        case .swingR: rows += [line([4, 5, 8, 9])]
        case .pass: rows += [line([4, 5, 7, 8])]
        case .swingL: rows += [line([3, 4, 7, 8])]
        }
        return rows
    }
}

struct AnimatedMomoMark: View {
    let size: CGFloat
    var tile = true
    var animated = true
    var motion: MomoMotion = .loop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var frame = MomoPixelFrame()

    private var shouldAnimate: Bool { animated && !reduceMotion && scenePhase == .active }

    var body: some View {
        PixelBarBoyMark(size: size, tile: tile, frame: shouldAnimate ? frame : MomoPixelFrame())
            .task(id: shouldAnimate) {
                guard shouldAnimate else { return }
                while !Task.isCancelled {
                    for next in motion.frames {
                        guard !Task.isCancelled else { return }
                        frame = next
                        do { try await Task.sleep(for: .milliseconds(next.milliseconds)) }
                        catch { return }
                    }
                }
            }
    }
}

struct PixelBarBoyMark: View {
    var size: CGFloat = 34
    var tile = false
    var frame = MomoPixelFrame()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if tile { Rectangle().fill(Color.primary) }
            Canvas { context, bounds in
                let inset = tile ? size * 0.12 : 0
                let unit = max(1, ((size - inset * 2) * displayScale / 14).rounded()) / displayScale
                let x = floor((bounds.width - unit * 13) * displayScale / 2) / displayScale
                let y = floor((bounds.height - unit * 14) * displayScale / 2) / displayScale
                var pixels = Path()
                for (row, cells) in frame.rows.enumerated() {
                    for (column, filled) in cells.enumerated() where filled {
                        pixels.addRect(CGRect(x: x + CGFloat(column) * unit, y: y + CGFloat(row) * unit, width: unit, height: unit))
                    }
                }
                context.fill(pixels, with: .color(tile ? Color(nsColor: .windowBackgroundColor) : .primary))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
