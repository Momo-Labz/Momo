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
        private var observations: [NSObjectProtocol] = []
        private var scheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.forEach(NotificationCenter.default.removeObserver)
            observations = []
            if let window {
                for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification] {
                    observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.positionIfNeeded()
                    })
                }
            }
            positionIfNeeded()
        }

        deinit { observations.forEach(NotificationCenter.default.removeObserver) }

        func positionIfNeeded() {
            guard let window, !scheduled else { return }
            // MenuBarExtra uses an NSPanel. Keep it alive while Finder or an
            // Open panel is the drag source; the menu icon/Contract action
            // remains the explicit way to dismiss MOMO.
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = false
                panel.isFloatingPanel = true
                panel.becomesKeyOnlyIfNeeded = false
            }
            scheduled = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self else { return }
                self.scheduled = false
                guard let window, let screen = window.screen ?? NSScreen.main else { return }
                var frame = window.frame
                let visible = screen.visibleFrame
                frame.origin.x = max(visible.minX, visible.maxX - frame.width - 14)
                frame.origin.y = max(visible.minY, visible.maxY - frame.height - 10)
                if window.frame.origin != frame.origin { window.setFrameOrigin(frame.origin) }
            }
        }
    }
}
