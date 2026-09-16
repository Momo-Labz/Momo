import SwiftUI

/// Which pane the one MOMO window is showing.
///
/// MOMO used to open a separate window for Quick Ask and for Voice. They are
/// panes of the window that is already open instead, so using the app does not
/// scatter windows across the desktop.
enum MomoPane: String, CaseIterable, Identifiable {
    case sessions, quickAsk, voice
    var id: String { rawValue }

    static var primaryCases: [MomoPane] { [.sessions, .quickAsk] }

    var title: String {
        switch self {
        case .sessions: return "FOLDERS"
        case .quickAsk: return "ASK"
        case .voice: return "VOICE"
        }
    }

    var symbol: String {
        switch self {
        case .sessions: return "bubble.left.and.bubble.right"
        case .quickAsk: return "square.and.pencil"
        case .voice: return "waveform"
        }
    }
}

enum MomoRoute: Equatable {
    case dashboard
    case settings
    case session(String)
    case usage(AIProvider)
}

@MainActor
final class MomoSurface: ObservableObject {
    static let shared = MomoSurface()
    static let compactWidth: CGFloat = 700
    static let expandedWidth: CGFloat = 920
    static let compactHeight: CGFloat = 310
    static let expandedHeight: CGFloat = 620

    @Published var pane: MomoPane = .sessions
    @Published var expanded = false
    @Published var trackerTab: TrackerTab = .activity
    @Published var selectedSessionID: String?
    /// State shared by the compact menu and its in-place expanded surface.
    /// Keeping this here prevents the menu and the expanded content from
    /// drifting apart when the user changes provider or page.
    @Published var selectedProvider: AIProvider?
    @Published var page: DashboardTab = .home
    @Published var attentionOnly = false
    /// True when the pane changed from a keyboard shortcut, which must not animate.
    @Published var lastChangeWasKeyboard = false
    @Published private(set) var route: MomoRoute = .dashboard
    /// Connect Usage providers queued after allow-list connect (Manual preview path).
    @Published private(set) var pendingUsageConnect: [AIProvider] = []
    /// Providers ready for a lightweight “Confirm usage when ready” return (no auto WebKit).
    @Published private(set) var pendingUsageReturn: [AIProvider] = []
    private var expandedBeforeRoute = false

    var presentsFullPage: Bool { route != .dashboard }
    var usesExpandedSize: Bool { expanded || presentsFullPage }

    func show(_ pane: MomoPane, fromKeyboard: Bool = false) {
        lastChangeWasKeyboard = fromKeyboard
        self.pane = pane
    }

    func selectProvider(_ provider: AIProvider?) {
        selectedProvider = provider
    }

    func selectSession(_ session: AgentSession?) {
        selectedSessionID = session?.id
        if let session { selectProvider(session.provider) }
    }

    func openSettings(fromKeyboard: Bool = false) {
        open(.settings, fromKeyboard: fromKeyboard)
    }

    func openSession(_ session: AgentSession, fromKeyboard: Bool = false) {
        selectSession(session)
        open(.session(session.id), fromKeyboard: fromKeyboard)
    }

    func openUsage(_ provider: AIProvider, fromKeyboard: Bool = false) {
        selectProvider(provider)
        open(.usage(provider), fromKeyboard: fromKeyboard)
    }

    /// Soft return after browser login: banner only until the person chooses Confirm usage.
    func offerUsageReturn(_ providers: [AIProvider]) {
        pendingUsageReturn = providers.filter(\.supportsUsageCapture)
    }

    func dismissUsageReturn() {
        pendingUsageReturn = []
    }

    /// Start Manual Confirm for the first pending return provider (existing capture path).
    func beginPendingUsageReturn(fromKeyboard: Bool = false) {
        let next = pendingUsageReturn
        pendingUsageReturn = []
        queueUsageConnect(next, fromKeyboard: fromKeyboard)
    }

    /// Persist an ordered Connect Usage queue and open the first allowlisted provider.
    func queueUsageConnect(_ providers: [AIProvider], fromKeyboard: Bool = false) {
        let next = providers.filter(\.supportsUsageCapture)
        guard let first = next.first else {
            pendingUsageConnect = []
            return
        }
        pendingUsageConnect = Array(next.dropFirst())
        openUsage(first, fromKeyboard: fromKeyboard)
    }

    func goBack(fromKeyboard: Bool = false) {
        lastChangeWasKeyboard = fromKeyboard
        if case .usage = route, let next = pendingUsageConnect.first {
            pendingUsageConnect = Array(pendingUsageConnect.dropFirst())
            selectProvider(next)
            route = .usage(next)
            expanded = true
            return
        }
        pendingUsageConnect = []
        route = .dashboard
        expanded = expandedBeforeRoute
    }

    private func open(_ destination: MomoRoute, fromKeyboard: Bool) {
        lastChangeWasKeyboard = fromKeyboard
        if route == .dashboard { expandedBeforeRoute = expanded }
        route = destination
        expanded = true
    }

}
