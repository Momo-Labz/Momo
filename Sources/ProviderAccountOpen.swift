import AppKit
import Foundation

/// Opens desktop AI apps via Launch Services without writing into their bundles.
/// Prefer activating an already-running instance; never modify another .app.
///
/// **Never block the MainActor.** `NSWorkspace.openApplication` completions often hop
/// back to the main thread — waiting on a semaphore from MainActor deadlocks the UI
/// (same class of hang as VoicePermission’s continuation deadlock).
enum DesktopAppConnect {
    /// Test seam — production uses Launch Services openApplication.
    static var openApplicationAtURL: (URL) -> Bool = { url in
        openViaLaunchServices(url)
    }

    /// Synchronous fire-and-forget open. Safe from MainActor: never waits on a semaphore.
    @discardableResult
    static func openDesktopApp(for provider: AIProvider) -> Bool {
        if activateRunning(provider) { return true }
        guard let url = DesktopAppCatalog.locate(provider) else { return false }
        return openApplicationAtURL(url)
    }

    /// Async open that reports whether Launch Services accepted the request.
    static func openDesktopAppAsync(for provider: AIProvider) async -> Bool {
        if activateRunning(provider) { return true }
        guard let url = DesktopAppCatalog.locate(provider) else { return false }
        return await openViaLaunchServicesAsync(url)
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
    /// Returns immediately after requesting open; does **not** wait for the completion handler.
    private static func openViaLaunchServices(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" || url.hasDirectoryPath else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            // Intentionally ignored — readiness is confirmed by DesktopConnectionVerifier off-main.
        }
        return true
    }

    private static func openViaLaunchServicesAsync(_ url: URL) async -> Bool {
        guard url.pathExtension.lowercased() == "app" || url.hasDirectoryPath else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        return await withCheckedContinuation { continuation in
            var resumed = false
            let lock = NSLock()
            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                // Resume off the callback thread; do not assume MainActor.
                DispatchQueue.global(qos: .userInitiated).async {
                    finish(error == nil)
                }
            }
            // Bound wait so a stuck Launch Services callback cannot hang connect forever.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.5) {
                finish(true) // Request was issued; verifier decides connected vs not.
            }
        }
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
