import AppKit
import Foundation

/// Opens desktop AI apps via Launch Services without writing into their bundles.
/// Prefer activating an already-running instance; never modify another .app.
enum DesktopAppConnect {
    /// Test seam — production uses Launch Services openApplication.
    static var openApplicationAtURL: (URL) -> Bool = { url in
        openViaLaunchServices(url)
    }

    @discardableResult
    static func openDesktopApp(for provider: AIProvider) -> Bool {
        // Prefer activating a running instance — no App Management write path.
        if activateRunning(provider) { return true }
        guard let url = DesktopAppCatalog.locate(provider) else { return false }
        return openApplicationAtURL(url)
    }

    static func isInstalled(_ provider: AIProvider) -> Bool {
        DesktopAppCatalog.locate(provider) != nil
    }

    @discardableResult
    static func activateRunning(_ provider: AIProvider) -> Bool {
        let ids = Set(provider.applicationBundleIdentifiers)
        guard !ids.isEmpty else { return false }
        let matches = NSWorkspace.shared.runningApplications.filter { app in
            guard let bid = app.bundleIdentifier else { return false }
            return ids.contains(bid)
        }
        guard let app = matches.first else { return false }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    /// Launch Services open — does not write into the target .app bundle.
    private static func openViaLaunchServices(_ url: URL) -> Bool {
        // Guard: only open .app bundles (or symlinks to them), never nested Mach-O paths.
        guard url.pathExtension.lowercased() == "app" || url.hasDirectoryPath else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        var opened = false
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            lock.lock()
            opened = (error == nil)
            lock.unlock()
            semaphore.signal()
        }
        // Bound wait so onboarding never hangs the MainActor caller when used from a Task.
        _ = semaphore.wait(timeout: .now() + 2.5)
        lock.lock()
        let result = opened
        lock.unlock()
        if result { return true }
        // Last resort: open the .app URL through Launch Services without touching Contents/.
        return NSWorkspace.shared.open(url)
    }
}

/// Legacy name — opens the desktop app, not a browser login / WebKit scrape.
enum ProviderAccountOpen {
    static var openURL: (URL) -> Bool = { url in
        if url.pathExtension.lowercased() == "app" {
            return DesktopAppConnect.openApplicationAtURL(url)
        }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    static func openLogin(for provider: AIProvider) -> Bool {
        DesktopAppConnect.openDesktopApp(for: provider)
    }
}
