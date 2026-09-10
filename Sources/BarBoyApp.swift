import SwiftUI

@main
struct BarBoyApp: App {
    @StateObject private var monitor = ActivityMonitor()
    @StateObject private var preferences = PreferencesStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(monitor)
                .environmentObject(preferences)
        } label: {
            MenuBarLabelView(snapshots: monitor.snapshots, compact: preferences.compactMenuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .environmentObject(preferences)
        }

        Window("BAR BOY", id: "dashboard") {
            DashboardView()
                .environmentObject(monitor)
                .environmentObject(preferences)
                .frame(width: 420, height: 650)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
    }
}

