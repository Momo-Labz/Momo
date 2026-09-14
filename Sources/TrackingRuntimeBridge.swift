import AppKit
import SwiftUI

/// Runtime synchronization retained by the tracking surface. It deliberately
/// excludes composer, shortcut, voice, and auto-resume routing.
struct TrackingRuntimeBridge: View {
    @ObservedObject var monitor: ActivityMonitor
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var deskDisplay: DeskDisplayServer
    @ObservedObject var attentionNotifier: AttentionNotifier
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                monitor.setAuthorizedRoots(authorizedRoots)
                monitor.setAuthorizedProviders(preferences.enabledProviders)
                syncServer()
                if !UserDefaults.standard.bool(forKey: "codexOnboardingSeen.v1") { openWindow(id: "onboarding") }
            }
            .onChange(of: preferences.enabledProviders) { _, providers in
                monitor.setAuthorizedRoots(authorizedRoots)
                monitor.setAuthorizedProviders(providers)
            }
            .onChange(of: preferences.deskDisplayEnabled) { _, _ in syncServer() }
            .onChange(of: preferences.showDeskDisplayTitles) { _, _ in syncServer() }
            .onReceive(monitor.$snapshots) { snapshots in
                deskDisplay.update(snapshots: snapshots, includeTitles: preferences.showDeskDisplayTitles)
                attentionNotifier.update(
                    snapshots: snapshots.map { snapshot in
                        var result = snapshot
                        result.sessions = snapshot.sessions.map(preferences.presented)
                        return result
                    },
                    enabled: preferences.attentionAlertsEnabled)
            }
    }

    private var authorizedRoots: [AIProvider: [URL]] {
        Dictionary(uniqueKeysWithValues: preferences.localProviderRoots.map { provider, paths in
            (provider, paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
        })
    }

    private func syncServer() {
        deskDisplay.update(snapshots: monitor.snapshots, includeTitles: preferences.showDeskDisplayTitles)
        if preferences.deskDisplayEnabled { deskDisplay.start() } else { deskDisplay.stop() }
    }
}
