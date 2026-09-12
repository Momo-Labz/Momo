import SwiftUI

@main
struct BarBoyApp: App {
    @StateObject private var monitor = ActivityMonitor()
    @StateObject private var preferences = PreferencesStore()
    @StateObject private var deskDisplay = DeskDisplayServer()
    @StateObject private var attentionNotifier = AttentionNotifier()
    @StateObject private var shortcuts = GlobalShortcutService.shared

    var body: some Scene {
        MenuBarExtra {
            CompactDashboardView()
                .environmentObject(monitor)
                .environmentObject(preferences)
        } label: {
            ZStack {
                MenuBarLabelView(snapshots: monitor.snapshots, compact: preferences.compactMenuBar, attentionNotifier: attentionNotifier)
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

        Window("MOMO", id: "dashboard") {
            DashboardView()
                .environmentObject(monitor)
                .environmentObject(preferences)
                .environmentObject(deskDisplay)
                .environmentObject(attentionNotifier)
                .frame(width: 430)
                .frame(minHeight: 500)
        }
        .defaultPosition(.center)
        .defaultSize(width: 430, height: 640)
        .windowResizability(.contentSize)

        Window("Connect Codex", id: "onboarding") {
            CodexOnboardingView()
                .environmentObject(preferences)
                .environmentObject(monitor)
                .environmentObject(attentionNotifier)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        Window("MOMO Overview", id: "overview") {
            DashboardView(showsOverview: true)
                .environmentObject(monitor)
                .environmentObject(preferences)
                .environmentObject(deskDisplay)
                .environmentObject(attentionNotifier)
        }.defaultPosition(.center).windowResizability(.contentSize)

    }
}
