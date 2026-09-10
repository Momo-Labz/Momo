import SwiftUI

struct RuntimeBridgeView: View {
    @ObservedObject var monitor: ActivityMonitor
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var deskDisplay: DeskDisplayServer
    @ObservedObject var attentionNotifier: AttentionNotifier
    @ObservedObject var shortcuts: GlobalShortcutService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear { syncServer() }
            .onChange(of: preferences.deskDisplayEnabled) { _, _ in syncServer() }
            .onChange(of: preferences.showDeskDisplayTitles) { _, _ in syncServer() }
            .onReceive(monitor.$snapshots) { snapshots in
                deskDisplay.update(snapshots: snapshots, includeTitles: preferences.showDeskDisplayTitles)
                attentionNotifier.update(snapshots: snapshots, enabled: preferences.attentionAlertsEnabled)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
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
