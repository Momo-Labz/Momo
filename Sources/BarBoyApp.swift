import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class MomoRuntime: ObservableObject {
    static let shared = MomoRuntime()

    let monitor = ActivityMonitor()
    let preferences = PreferencesStore()
    let deskDisplay = DeskDisplayServer()
    let attentionNotifier = AttentionNotifier()
    let statusItem = MomoStatusItemController()

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        statusItem.install(runtime: self)
        applyProviderAuthorization()
        syncDeskDisplay()

        preferences.$enabledProviders.dropFirst().sink { [weak self] _ in self?.applyProviderAuthorization() }.store(in: &cancellables)
        preferences.$allowedTrackingProviders.dropFirst().sink { [weak self] _ in self?.applyProviderAuthorization() }.store(in: &cancellables)
        preferences.$localProviderRoots.dropFirst().sink { [weak self] _ in self?.applyProviderAuthorization() }.store(in: &cancellables)
        Publishers.CombineLatest(preferences.$deskDisplayEnabled, preferences.$showDeskDisplayTitles)
            .dropFirst().sink { [weak self] _ in self?.syncDeskDisplay() }.store(in: &cancellables)
        monitor.$snapshots.sink { [weak self] snapshots in
            guard let self else { return }
            self.deskDisplay.update(snapshots: snapshots, includeTitles: self.preferences.showDeskDisplayTitles)
            self.attentionNotifier.update(
                snapshots: snapshots.map { snapshot in
                    var presented = snapshot
                    presented.sessions = snapshot.sessions.map(self.preferences.presented)
                    return presented
                },
                enabled: self.preferences.attentionAlertsEnabled
            )
            self.statusItem.update(snapshots: snapshots)
        }.store(in: &cancellables)

        // First-run: open the panel so Welcome is visible without hunting the status item.
        TalkSessionCoordinator.shared.install(monitor: monitor, preferences: preferences)
        if preferences.needsTrackingOnboarding {
            MomoSurface.shared.expanded = true
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.presentPanelForOnboarding()
            }
        }
    }

    private func applyProviderAuthorization() {
        let roots = Dictionary(uniqueKeysWithValues: preferences.localProviderRoots.map { provider, paths in
            (provider, paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
        })
        monitor.setAuthorizedRoots(roots)
        let authorized = preferences.enabledProviders.union(preferences.allowedTrackingProviders)
        monitor.setAuthorizedProviders(authorized)
    }

    private func syncDeskDisplay() {
        deskDisplay.update(snapshots: monitor.snapshots, includeTitles: preferences.showDeskDisplayTitles)
        preferences.deskDisplayEnabled ? deskDisplay.start() : deskDisplay.stop()
    }
}

@main
@MainActor
final class BarBoyApp: NSObject, NSApplicationDelegate {
    private var runtime: MomoRuntime?

    static func main() {
        let application = NSApplication.shared
        let delegate = BarBoyApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = MomoRuntime.shared
        self.runtime = runtime
        runtime.start()
    }
}

@MainActor
final class MomoStatusItemController: NSObject, ObservableObject, NSWindowDelegate {
    private var item: NSStatusItem?
    private var panel: MomoPanel?
    private var peekPanel: MomoPanel?
    private weak var runtime: MomoRuntime?
    private var surfaceObservation: AnyCancellable?
    private var voiceObservation: AnyCancellable?
    private var talkObservation: AnyCancellable?
    private var lastUsageSegment: Int?
    private var singleClickWorkItem: DispatchWorkItem?
    private var activityPulseTimer: Timer?
    private var activityPulseVisible = false
    private enum MenuBarTalkState { case idle, listening, thinking, speaking }
    private var menuBarTalkState: MenuBarTalkState = .idle

    func install(runtime: MomoRuntime) {
        guard item == nil else { return }
        self.runtime = runtime
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = status
        status.button?.image = MenuBarLabelView.statusIcon
        status.button?.image?.isTemplate = false
        status.button?.target = self
        status.button?.action = #selector(handleStatusItemClick(_:))
        status.button?.sendAction(on: [.leftMouseUp])
        status.button?.toolTip = "MOMO provider activity · double-click for usage peek"
        surfaceObservation = MomoSurface.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeForSurface() }
        }
        voiceObservation = VoiceInput.shared.$state.sink { [weak self] _ in
            self?.refreshTalkMenuBarState()
        }
        talkObservation = TalkService.shared.$phase.sink { [weak self] _ in
            self?.refreshTalkMenuBarState()
        }
        update(snapshots: runtime.monitor.snapshots)
    }

    func update(snapshots: [ProviderSnapshot]) {
        guard let button = item?.button else { return }
        let attention = snapshots.reduce(0) { $0 + $1.needsAttentionCount }
        let percent = snapshots.flatMap { [$0.shortWindowPercent, $0.weekWindowPercent].compactMap { $0 } }
            .filter { (0...100).contains($0) }.max()
        let nextSegment = percent.map { min(4, Int(ceil(Double($0) / 25.0))) }
        if attention > 0 {
            button.attributedTitle = NSAttributedString(
                string: " !\(min(attention, 99))",
                attributes: [.foregroundColor: NSColor(BarBoyStyle.coral)]
            )
            button.contentTintColor = nil
            button.toolTip = "\(attention) session\(attention == 1 ? "" : "s") need attention · double-click for usage peek"
        } else if let nextSegment {
            button.attributedTitle = NSAttributedString(
                string: " " + String(repeating: "▮", count: nextSegment) + String(repeating: "▯", count: 4 - nextSegment),
                attributes: [.foregroundColor: NSColor.white]
            )
            button.contentTintColor = nil
            button.toolTip = percent.map { "Highest verified provider usage: \($0)% · double-click for usage peek" }
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.contentTintColor = nil
            button.toolTip = "MOMO provider activity · double-click for usage peek"
        }
        if let previous = lastUsageSegment, let nextSegment, nextSegment > previous,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            button.alphaValue = 0.58
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                button.animator().alphaValue = 1
            }
        }
        lastUsageSegment = nextSegment
        if peekPanel?.isVisible == true {
            refreshPeekContent()
        }
    }

    private func refreshTalkMenuBarState() {
        let voice = VoiceInput.shared
        let talk = TalkService.shared
        let next: MenuBarTalkState
        switch talk.phase {
        case .speaking: next = .speaking
        case .thinking: next = .thinking
        case .listening: next = .listening
        default:
            if voice.mode == .talk, voice.state == .listening || voice.state == .permission {
                next = .listening
            } else {
                next = .idle
            }
        }
        guard next != menuBarTalkState else { return }
        menuBarTalkState = next
        updateTalkMenuBarIndicator(next)
    }

    private func updateTalkMenuBarIndicator(_ state: MenuBarTalkState) {
        guard let button = item?.button else { return }
        activityPulseTimer?.invalidate()
        activityPulseTimer = nil
        activityPulseVisible = false
        switch state {
        case .idle:
            button.alphaValue = 1
            runtime.map { update(snapshots: $0.monitor.snapshots) }
        case .listening:
            activityPulseVisible = true
            button.attributedTitle = NSAttributedString(
                string: " 🎙",
                attributes: [.foregroundColor: NSColor(BarBoyStyle.coral)]
            )
            activityPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: true) { [weak self] _ in
                guard let self, let button = self.item?.button else { return }
                self.activityPulseVisible.toggle()
                button.alphaValue = self.activityPulseVisible ? 1 : 0.45
            }
            button.toolTip = "Talk · listening"
        case .thinking:
            activityPulseVisible = true
            button.attributedTitle = NSAttributedString(
                string: " …",
                attributes: [.foregroundColor: NSColor(BarBoyStyle.amber)]
            )
            activityPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
                guard let self, let button = self.item?.button else { return }
                self.activityPulseVisible.toggle()
                let glyph = self.activityPulseVisible ? " …" : " ··"
                button.attributedTitle = NSAttributedString(
                    string: glyph,
                    attributes: [.foregroundColor: NSColor(BarBoyStyle.amber)]
                )
            }
            button.toolTip = "Talk · MOMO thinking"
        case .speaking:
            activityPulseVisible = true
            button.attributedTitle = NSAttributedString(
                string: " 🔊",
                attributes: [.foregroundColor: NSColor(BarBoyStyle.coral)]
            )
            activityPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: true) { [weak self] _ in
                guard let self, let button = self.item?.button else { return }
                self.activityPulseVisible.toggle()
                button.alphaValue = self.activityPulseVisible ? 1 : 0.55
            }
            button.toolTip = "Talk · speaking"
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        let clicks = NSApp.currentEvent?.clickCount ?? 1
        if clicks >= 2 {
            singleClickWorkItem?.cancel()
            singleClickWorkItem = nil
            togglePeek()
            return
        }
        singleClickWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.togglePanel()
        }
        singleClickWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func togglePanel() {
        hidePeek()
        if panel?.isVisible == true {
            panel?.orderOut(nil)
            runtime?.monitor.setMenuVisible(false)
        } else {
            show()
        }
    }

    /// Opens the tracking panel expanded for first-run Welcome (or Replay).
    func presentPanelForOnboarding() {
        MomoSurface.shared.expanded = true
        show()
    }

    private func togglePeek() {
        if peekPanel?.isVisible == true {
            hidePeek()
            return
        }
        if panel?.isVisible == true {
            panel?.orderOut(nil)
            runtime?.monitor.setMenuVisible(false)
        }
        showPeek()
    }

    private func hidePeek() {
        peekPanel?.orderOut(nil)
    }

    private func showPeek() {
        guard runtime != nil else { return }
        if peekPanel == nil {
            let panel = MomoPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 280, height: 120)),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            self.peekPanel = panel
        }
        refreshPeekContent()
        positionPeek()
        peekPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshPeekContent() {
        guard let runtime, let peekPanel else { return }
        let allowed = runtime.preferences.trackingStripProviders()
        let rows = UsagePeekMapping.rows(
            allowed: allowed,
            observations: runtime.monitor.usageObservations,
            snapshots: runtime.monitor.snapshots
        )
        let root = UsagePeekView(rows: rows)
            .environmentObject(runtime.monitor)
            .environmentObject(runtime.preferences)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        peekPanel.contentView = hosting
        peekPanel.setContentSize(hosting.fittingSize)
        positionPeek()
    }

    private func positionPeek() {
        guard let peekPanel else { return }
        let size = peekPanel.frame.size
        let screen = item?.button?.window?.screen ?? peekPanel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let anchor = item?.button.flatMap { button in button.window?.convertToScreen(button.frame) }
        var frame = NSRect(origin: .zero, size: size)
        frame.origin.x = max(visible.minX, min((anchor?.midX ?? visible.maxX) - size.width / 2, visible.maxX - size.width - 8))
        frame.origin.y = min(visible.maxY - size.height, max(visible.minY, (anchor?.minY ?? visible.maxY) - size.height - 6))
        peekPanel.setFrame(frame, display: true)
    }

    private func show() {
        guard let runtime else { return }
        hidePeek()
        if panel == nil {
            let root = DashboardView()
                .environmentObject(runtime.monitor)
                .environmentObject(runtime.preferences)
                .environmentObject(runtime.deskDisplay)
                .environmentObject(runtime.attentionNotifier)
            let panel = MomoPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: root)
            self.panel = panel
        }
        runtime.monitor.setMenuVisible(true)
        resizeForSurface()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var panelSize: NSSize {
        let screenHeight = item?.button?.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 700
        let surface = MomoSurface.shared
        return NSSize(
            width: surface.usesExpandedSize ? MomoSurface.expandedWidth : MomoSurface.compactWidth,
            height: surface.usesExpandedSize ? min(MomoSurface.expandedHeight, screenHeight - 20) : MomoSurface.compactHeight
        )
    }

    private func resizeForSurface() {
        guard let panel else { return }
        let size = panelSize
        let screen = item?.button?.window?.screen ?? panel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let anchor = item?.button.flatMap { button in button.window?.convertToScreen(button.frame) }
        var frame = NSRect(origin: panel.frame.origin, size: size)
        // MOMO is a right-side utility. Every state shares this edge so the
        // attached panel expands leftward without jumping across the display.
        frame.origin.x = max(visible.minX, visible.maxX - size.width - 8)
        frame.origin.y = min(visible.maxY - size.height, max(visible.minY, (anchor?.minY ?? visible.maxY) - size.height))
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !MomoSurface.shared.lastChangeWasKeyboard
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if sender === panel {
            runtime?.monitor.setMenuVisible(false)
        }
        return false
    }
}

private final class MomoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
