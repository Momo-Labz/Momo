import SwiftUI

@main
struct BarBoyApp: App {
    @StateObject private var monitor = ActivityMonitor()
    @StateObject private var preferences = PreferencesStore()
    @StateObject private var deskDisplay = DeskDisplayServer()
    @StateObject private var attentionNotifier = AttentionNotifier()
    @StateObject private var shortcuts = GlobalShortcutService()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(monitor)
                .environmentObject(preferences)
                .environmentObject(deskDisplay)
        } label: {
            ZStack {
                MenuBarLabelView(snapshots: monitor.snapshots, compact: preferences.compactMenuBar)
                RuntimeBridgeView(monitor: monitor, preferences: preferences, deskDisplay: deskDisplay, attentionNotifier: attentionNotifier, shortcuts: shortcuts)
                    .frame(width: 0, height: 0)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .environmentObject(preferences)
                .environmentObject(deskDisplay)
                .environmentObject(attentionNotifier)
        }

        Window("BAR BOY", id: "dashboard") {
            DashboardView()
                .environmentObject(monitor)
                .environmentObject(preferences)
                .environmentObject(deskDisplay)
                .environmentObject(attentionNotifier)
                .frame(width: 420, height: 650)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        Window("Quick Ask", id: "command-palette") {
            CommandPaletteView()
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
    }
}
