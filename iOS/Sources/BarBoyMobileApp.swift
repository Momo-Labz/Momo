import SwiftUI

@main
struct BarBoyMobileApp: App {
    @StateObject private var store = RelayStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(nil)
        }
    }
}
