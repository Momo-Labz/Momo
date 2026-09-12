import SwiftUI

/// Which pane the one MOMO window is showing.
///
/// MOMO used to open a separate window for Quick Ask and for Voice. They are
/// panes of the window that is already open instead, so using the app does not
/// scatter windows across the desktop.
enum MomoPane: String, CaseIterable, Identifiable {
    case sessions, quickAsk, voice
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "CHATS"
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
    /// True when the pane changed from a keyboard shortcut, which must not animate.
    @Published var lastChangeWasKeyboard = false

    func show(_ pane: MomoPane, fromKeyboard: Bool = false) {
        lastChangeWasKeyboard = fromKeyboard
        self.pane = pane
    }
}
