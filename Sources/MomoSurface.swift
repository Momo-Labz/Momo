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

@MainActor
final class MomoSurface: ObservableObject {
    static let shared = MomoSurface()
    @Published var pane: MomoPane = .sessions
    @Published var expanded = false
    /// State shared by the compact menu and its in-place expanded surface.
    /// Keeping this here prevents the menu and the expanded content from
    /// drifting apart when the user changes provider or page.
    @Published var selectedProvider: AIProvider?
    @Published var page: DashboardTab = .home
    @Published var attentionOnly = false
    /// True when the pane changed from a keyboard shortcut, which must not animate.
    @Published var lastChangeWasKeyboard = false

    func show(_ pane: MomoPane, fromKeyboard: Bool = false) {
        lastChangeWasKeyboard = fromKeyboard
        self.pane = pane
    }

    func selectProvider(_ provider: AIProvider?) {
        selectedProvider = provider
        guard let provider else { return }
        QuickAskContext.shared.provider = provider
        QuickAskContext.shared.targetProvider = provider
    }
}
