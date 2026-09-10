import SwiftUI

@main
struct BarBoyMobileApp: App {
    @StateObject private var store = RelayStore()

    var body: some Scene {
        WindowGroup {
            RelayRootView()
                .environmentObject(store)
                .preferredColorScheme(nil)
        }
    }
}
