import SwiftUI

struct RuntimeBridgeView: View {
    @ObservedObject var monitor: ActivityMonitor
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var deskDisplay: DeskDisplayServer
    @ObservedObject var attentionNotifier: AttentionNotifier
    @ObservedObject var shortcuts: GlobalShortcutService
    @ObservedObject private var autoResume = AutoResumeService.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                monitor.setAuthorizedProviders(preferences.enabledProviders)
                syncServer()
                if !UserDefaults.standard.bool(forKey: "codexOnboardingSeen.v1") { openWindow(id: "onboarding") }
            }
            .onChange(of: preferences.enabledProviders) { _, providers in
                monitor.setAuthorizedProviders(providers)
            }
            .onChange(of: preferences.autoResumeAfterReset) { _, _ in
                autoResume.update(snapshots: monitor.snapshots, enabled: preferences.autoResumeAfterReset, authorized: preferences.enabledProviders)
            }
            .onChange(of: preferences.deskDisplayEnabled) { _, _ in syncServer() }
            .onChange(of: preferences.showDeskDisplayTitles) { _, _ in syncServer() }
            .onReceive(monitor.$snapshots) { snapshots in
                deskDisplay.update(snapshots: snapshots, includeTitles: preferences.showDeskDisplayTitles)
                attentionNotifier.update(snapshots: snapshots, enabled: preferences.attentionAlertsEnabled)
                autoResume.update(snapshots: snapshots, enabled: preferences.autoResumeAfterReset, authorized: preferences.enabledProviders)
            }
            .onReceive(NotificationCenter.default.publisher(for: .momoShortcut)) { notification in
                guard let action = notification.object as? ShortcutAction else { return }
                MomoFeedback.perform()
                if action == .quickAsk {
                    QuickAskContext.shared.activationLabel = "Shortcut received · \(shortcuts.bindings[action]?.label ?? action.title)"
                    NotificationCenter.default.post(name: .showCommandPalette, object: nil)
                } else {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if VoiceInput.shared.isActive { VoiceInput.shared.stop() }
                    else {
                        VoiceInput.shared.prepare(action)
                        openWindow(id: "voice")
                        Task { await VoiceInput.shared.start() }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { notification in
                if let session = notification.object as? AgentSession {
                    QuickAskContext.shared.select(preferences.presented(session))
                }
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "command-palette")
            }
    }

    private func syncServer() {
        deskDisplay.update(snapshots: monitor.snapshots, includeTitles: preferences.showDeskDisplayTitles)
        if preferences.deskDisplayEnabled {
            deskDisplay.start()
        } else {
            deskDisplay.stop()
        }
    }
}
