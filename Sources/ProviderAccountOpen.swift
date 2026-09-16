import AppKit
import Foundation

/// Opens a provider’s official login URL in the default system browser.
/// Does not import cookies and does not start isolated WebKit capture.
enum ProviderAccountOpen {
    /// Test seam; production uses `NSWorkspace.shared.open`.
    static var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    @discardableResult
    static func openLogin(for provider: AIProvider) -> Bool {
        guard let url = provider.accountLoginURL else { return false }
        return openURL(url)
    }
}
