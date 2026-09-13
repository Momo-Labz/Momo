import AppKit
import SwiftUI

/// Keeps the MenuBarExtra window aligned with the right side of the active
/// display. This is intentionally a no-op for ordinary SwiftUI windows.
struct MenuBarWindowPositioner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PositioningView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PositioningView)?.positionIfNeeded()
    }

    private final class PositioningView: NSView {
        private var lastWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            positionIfNeeded()
        }

        func positionIfNeeded() {
            guard let window, window !== lastWindow else { return }
            lastWindow = window
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, let screen = window.screen ?? NSScreen.main else { return }
                var frame = window.frame
                let visible = screen.visibleFrame
                frame.origin.x = visible.maxX - frame.width - 14
                frame.origin.y = visible.maxY - frame.height - 10
                window.setFrameOrigin(frame.origin)
                self.lastWindow = window
            }
        }
    }
}
