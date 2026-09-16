import AppKit
import Foundation

/// Connects a provider by opening its desktop app (when installed) and granting local tracking permission.
/// Does not open WebKit usage pages or import browser cookies.
enum DesktopAppConnect {
    /// Test seam for open calls.
    static var openApplicationURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    @discardableResult
    static func openDesktopApp(for provider: AIProvider) -> Bool {
        guard let url = DesktopAppCatalog.locate(provider) else { return false }
        return openApplicationURL(url)
    }

    static func isInstalled(_ provider: AIProvider) -> Bool {
        DesktopAppCatalog.locate(provider) != nil
    }
}

/// Legacy name kept for older call sites / tests — now opens the desktop app, not a browser login.
enum ProviderAccountOpen {
    static var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    @discardableResult
    static func openLogin(for provider: AIProvider) -> Bool {
        if let url = DesktopAppCatalog.locate(provider) {
            return openURL(url)
        }
        return false
    }
}
