import AppKit
import SwiftUI

/// In-memory drafts never cross chat boundaries or persist prompt text to disk.
@MainActor
final class QuickAskContext: ObservableObject {
    static let shared = QuickAskContext()
    @Published private(set) var session: AgentSession?
    @Published var activationLabel: String?
    @Published var provider: AIProvider = .codex
    @Published var targetProvider: AIProvider = .codex
    @Published private var drafts: [String: String] = [:]

    private var draftKey: String { session.map { "chat:\($0.id)" } ?? "new:\(provider.rawValue)" }
    var draft: String {
        get { drafts[draftKey] ?? "" }
        set { drafts[draftKey] = newValue }
    }

    func select(_ session: AgentSession) {
        self.session = session
        provider = session.provider
        targetProvider = session.provider
    }

    func newChat() { session = nil }
}

struct CommandPaletteView: View {
    /// Rendered inside the MOMO window rather than a window of its own.
    var embedded = false

    /// Closing a pane returns to the chat list; closing a window dismisses it.
    private func leave() {
        if embedded { MomoSurface.shared.show(.sessions) } else { dismiss() }
    }
    @ObservedObject var context = QuickAskContext.shared
    @FocusState private var editorFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var routingMessage: String?
    @State private var showDetails = false
    @State private var editingLabel = false
    @State private var editedName = ""
    @State private var editedFolder = ""
    @ObservedObject private var autoResume = AutoResumeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AnimatedMomoMark(size: 32, motion: .wave)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.session == nil ? "MOMO LABZ / QUICK ASK" : "REPLY / \(context.provider.name.uppercased())")
                        .font(BarBoyStyle.sectionLabel)
                    Text(context.session?.title ?? "Type a thought or use macOS Dictation")
                        .font(BarBoyStyle.bodySmall).lineLimit(2)
                }
                Spacer()
                Text(GlobalShortcutService.shared.bindings[.quickAsk]?.label ?? "").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }

            if let session = context.session {
                HStack {
                    Text(session.attentionReason ?? session.detail)
                        .font(BarBoyStyle.bodySmall).lineLimit(3)
                        .foregroundStyle(session.attention.isUrgent ? BarBoyStyle.coral : Color.secondary)
                    Spacer()
                    Button("NEW CHAT") { context.newChat(); routingMessage = nil }.barBoyButton()
                }
            } else {
                Picker("Provider", selection: $context.provider) {
                    ForEach(AIProvider.allCases) { item in Text(item.name).tag(item) }
                }.pickerStyle(.segmented)
            }

            if let session = context.session {
                HStack {
                    Label(session.project, systemImage: "folder").lineLimit(1)
                    Spacer()
                    Button("EDIT NAME / FOLDER") {
                        editedName = session.title; editedFolder = session.project; editingLabel = true
                    }.barBoyButton()
                }.font(.caption)
                Text("Auto-resume: \(autoResume.state(for: session))").font(.caption).foregroundStyle(.secondary)
                Picker("Continue with", selection: $context.targetProvider) {
                    ForEach(AIProvider.allCases) { provider in Text(provider.name).tag(provider) }
                }.pickerStyle(.menu)
            }

            TextEditor(text: Binding(get: { context.draft }, set: { context.draft = $0 }))
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(9)
                .background(BarBoyStyle.surface)
                .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                .frame(height: 90)
                .accessibilityLabel(context.session.map { "Reply to \($0.title)" } ?? "New prompt")

            Text(routingMessage ?? context.activationLabel ?? (context.session == nil
                ? "Copies your text, then opens the provider."
                : "Draft for this chat. Use your Mac’s Dictation shortcut to speak."))
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("VOICE") { NotificationCenter.default.post(name: .momoShortcut, object: ShortcutAction.handsFree) }.barBoyButton()
                if context.session != nil {
                    Button("DETAILS") { showDetails = true }.barBoyButton()
                }
                if let session = context.session {
                    Button(continueLabel(for: session)) { continueConversation(session) }.barBoyButton()
                }
                if let source = context.session?.sourceURL, context.session?.provider != .codex {
                    Button("OPEN SESSION FILE") { NSWorkspace.shared.open(source) }.barBoyButton()
                }
                Spacer()
                Button("CLOSE") { leave() }.barBoyButton()
                Button(context.session == nil || context.provider == .codex ? "COPY + OPEN" : "COPY REPLY") { routePrompt() }
                    .barBoyButton()
                    .disabled(context.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: embedded ? .infinity : 520)
        .frame(width: embedded ? nil : 520)
        .background(BarBoyStyle.panel)
        .sheet(isPresented: $editingLabel) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Organize this conversation").font(.headline)
                TextField("Name in MOMO", text: $editedName)
                TextField("Folder label in MOMO", text: $editedFolder)
                Text("These labels organize MOMO. They do not rename the provider’s chat or change its working directory.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { editingLabel = false }
                    Spacer()
                    Button("Save") {
                        if let session = context.session {
                            preferences.setLabel(name: editedName, folder: editedFolder, for: session)
                            context.select(preferences.presented(session))
                        }
                        editingLabel = false; MomoFeedback.perform()
                    }.barBoyButton().disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 390)
        }
        .sheet(isPresented: $showDetails) {
            if let session = context.session { SessionInspectorView(session: session) }
        }
        .onAppear {
            editorFocused = true
            if context.session?.attention.isUrgent == true { showDetails = true }
        }
        .task(id: context.activationLabel) {
            guard context.activationLabel != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { context.activationLabel = nil }
        }
        .onChange(of: context.session?.id) { _, _ in editorFocused = true; routingMessage = nil }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in editorFocused = true }
    }

    private func openCodexTask(_ session: AgentSession) {
        guard preferences.isEnabled(.codex) else { routingMessage = "Authorize Codex in Settings first."; return }
        guard let url = CodexDesktopConnection.taskURL(source: session.sourceURL),
              CodexDesktopConnection.applicationURL != nil else {
            routingMessage = "No recorded task ID or Codex desktop installation available."; return
        }
        routingMessage = NSWorkspace.shared.open(url) ? "Task link opened. Paste your copied reply in Codex." : "Codex could not open this task link."
    }

    private func routePrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context.draft, forType: .string)
        if let session = context.session {
            continueConversation(session)
        } else if context.session != nil {
            routingMessage = "Reply copied. Exact chat opening is not yet recorded for this session."
        } else {
            if let url = context.provider.conversationURL { NSWorkspace.shared.open(url) }
            leave()
        }
    }

    private func continueLabel(for session: AgentSession) -> String {
        if context.targetProvider == .codex { return "OPEN CODEX TASK" }
        if context.targetProvider == .claude { return "RESUME CLAUDE" }
        return "COPY + OPEN \(context.targetProvider.name.uppercased())"
    }

    private func continueConversation(_ session: AgentSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context.draft, forType: .string)
        switch context.targetProvider {
        case .codex:
            openCodexTask(session)
        case .claude:
            guard let id = session.conversationID, UUID(uuidString: id) != nil else {
                routingMessage = "Claude session ID was not recorded; reply copied."
                return
            }
            let command = "claude --resume \(id)"
            NSPasteboard.general.setString(command, forType: .string)
            if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                NSWorkspace.shared.open(terminal)
                routingMessage = "Claude resume command copied. Paste it in Terminal, then paste your reply."
            } else {
                routingMessage = "Claude resume command copied: \(command)"
            }
        default:
            if let url = context.targetProvider.conversationURL { NSWorkspace.shared.open(url) }
            routingMessage = "Reply copied. This provider’s exact chat continuation is not recorded."
        }
    }
}


enum CodexDesktopConnection {
    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
    }

    static func taskURL(source: URL?) -> URL? {
        guard let source, let handle = try? FileHandle(forReadingFrom: source) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024) else { return nil }
        return taskURL(metadata: data)
    }

    static func taskURL(metadata: Data) -> URL? {
        // Only the first, complete session_meta record establishes identity.
        guard let line = metadata.split(separator: 10).first,
              let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              record["type"] as? String == "session_meta",
              let payload = record["payload"] as? [String: Any],
              let id = payload["id"] as? String, UUID(uuidString: id) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }
}
