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
    @Published var promptEnhancementEnabled = true
    @Published private var drafts: [String: String] = [:]
    @Published private var attachmentSets: [String: [URL]] = [:]
    @Published private var folderSelections: [String: String] = [:]
    @Published private var newFolders: [AIProvider: String] = [:]

    private var draftKey: String { session.map { "chat:\($0.provider.rawValue):\($0.conversationID ?? $0.id)" } ?? "new:\(provider.rawValue):\(newFolders[provider] ?? "")" }
    var draft: String {
        get { drafts[draftKey] ?? "" }
        set { drafts[draftKey] = newValue }
    }
    var attachments: [URL] { attachmentSets[draftKey] ?? [] }
    var selectedFolder: String? { session == nil ? newFolders[provider] : folderSelections[draftKey] }

    func select(_ session: AgentSession) {
        self.session = session
        provider = session.provider
        targetProvider = session.provider
    }

    func newChat() { session = nil }

    func beginChat(in folder: String) {
        session = nil
        selectFolder(folder)
    }

    func switchProvider(_ provider: AIProvider) {
        if session?.provider != provider { session = nil }
        self.provider = provider
        targetProvider = provider
    }

    func attach(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var current = attachmentSets[draftKey] ?? []
        for url in urls where !current.contains(url) { current.append(url) }
        attachmentSets[draftKey] = current
    }

    func removeAttachment(_ url: URL) {
        attachmentSets[draftKey] = attachments.filter { $0 != url }
    }

    func selectFolder(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if session == nil { newFolders[provider] = cleaned.isEmpty ? nil : cleaned }
        else { folderSelections[draftKey] = cleaned.isEmpty ? nil : cleaned }
    }

    var composedPrompt: String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard promptEnhancementEnabled else { return trimmed }
        var lines: [String] = [
            "Task:",
            trimmed
        ]
        if let selectedFolder, !selectedFolder.isEmpty {
            lines += ["", "Working context:", "- Folder: \(selectedFolder)"]
        }
        if !attachments.isEmpty {
            lines += ["", "Attached local files:"]
            lines += attachments.map { "- \($0.path)" }
        }
        lines += [
            "",
            "Please respond with:",
            "- The likely root cause or best next step.",
            "- The exact action to take next.",
            "- Any missing information needed before acting.",
            "",
            "Keep the answer specific to this chat and do not invent capabilities or usage data."
        ]
        return lines.joined(separator: "\n")
    }
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
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var routingMessage: String?
    @State private var originalChatURL: URL?
    @State private var showDetails = false
    @State private var editingLabel = false
    @State private var editedName = ""
    @State private var editedFolder = ""
    @ObservedObject private var autoResume = AutoResumeService.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ConversationSidebar(context: context)
                .frame(width: embedded ? 200 : 150)
            composer
        }
        .padding(12)
        .background(BarBoyStyle.panel)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AnimatedMomoMark(size: 32, motion: .wave)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.session == nil ? "MOMO LABZ / QUICK ASK" : "REPLY / \(context.provider.name.uppercased())")
                        .font(BarBoyStyle.sectionLabel)
                    Text(context.session.map { SessionPresentation.title(for: $0) } ?? "New chat · Type or use voice")
                        .font(BarBoyStyle.bodySmall).lineLimit(2)
                }
                Spacer()
                Text(GlobalShortcutService.shared.bindings[.quickAsk]?.label ?? "").font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            }

            Text("\(context.selectedFolder ?? context.session?.project ?? "Choose a project") / \(context.session.map { SessionPresentation.title(for: $0) } ?? "New chat")")
                .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary).lineLimit(2)
            if let session = context.session, session.attention.isUrgent {
                Text(session.attentionReason ?? session.detail)
                    .font(BarBoyStyle.bodySmall).foregroundStyle(BarBoyStyle.amber).lineLimit(3)
            }
            HStack {
                Toggle("Improve prompt", isOn: $context.promptEnhancementEnabled).toggleStyle(.checkbox)
                Spacer()
                Button("ATTACH") { attachFiles() }.barBoyButton()
            }.font(BarBoyStyle.bodySmall)
            if !context.attachments.isEmpty {
                Text(context.attachments.map(\.lastPathComponent).joined(separator: ", "))
                    .font(BarBoyStyle.bodySmall).lineLimit(2)
                Button("CLEAR ATTACHMENTS") {
                    for url in context.attachments { context.removeAttachment(url) }
                }.barBoyButton()
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: Binding(get: { context.draft }, set: { context.draft = $0 }))
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                        .padding(9)
                        .background(BarBoyStyle.surface)
                        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
                        .frame(height: context.session == nil ? 142 : 116)
                        .accessibilityLabel(context.session.map { "Reply to \($0.title)" } ?? "New prompt")
                    VoiceInlineBar()
                }
            }

            Text(routingMessage ?? context.activationLabel ?? (context.session == nil
                ? "Copies your text, then opens the provider."
                : "Draft for this chat. Use your Mac’s Dictation shortcut to speak."))
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                if context.session != nil {
                    Button("DETAILS") { showDetails = true }.barBoyButton()
                }
                if let session = context.session {
                    Button(continueLabel(for: session)) { continueConversation(session) }.barBoyButton()
                        .disabled(context.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let url = originalChatURL {
                    Button("OPEN ORIGINAL CHAT") { NSWorkspace.shared.open(url) }.barBoyButton()
                }
                Spacer()
                Button("CLOSE") { leave() }.barBoyButton()
                if context.session == nil {
                    Button("COPY + OPEN") { routePrompt() }
                        .barBoyButton()
                        .disabled(context.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
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
        // A sheet launched from MenuBarExtra is attached to the transient
        // menu window. Dismissing it also dismisses the menu, which made the
        // inspector's Done button appear to quit MOMO. Keep the inspector in
        // the same surface when embedded; standalone palettes may still use
        // a sheet.
        .sheet(isPresented: Binding(
            get: { showDetails && !embedded },
            set: { showDetails = $0 }
        )) {
            if let session = context.session { SessionInspectorView(session: session) }
        }
        .overlay {
            if embedded && showDetails, let session = context.session {
                ZStack {
                    BarBoyStyle.panel.opacity(0.96)
                    SessionInspectorView(session: session, onDone: { showDetails = false })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            editorFocused = true

        }
        .task(id: context.session?.id) {
            originalChatURL = nil
            guard let session = context.session, session.provider == .codex,
                  CodexDesktopConnection.applicationURL != nil else { return }
            let source = session.sourceURL
            let url = await Task.detached(priority: .utility) { CodexDesktopConnection.taskURL(source: source) }.value
            if !Task.isCancelled { originalChatURL = url }
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
        guard session.provider == .codex, let url = CodexDesktopConnection.taskURL(source: session.sourceURL),
              CodexDesktopConnection.applicationURL != nil else {
            routingMessage = "No recorded task ID or Codex desktop installation available."; return
        }
        routingMessage = NSWorkspace.shared.open(url) ? "Task link opened. Paste your copied reply in Codex." : "Codex could not open this task link."
    }

    private func routePrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context.composedPrompt, forType: .string)
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
        if context.targetProvider == .grok { return "RESUME GROK" }
        return "COPY + OPEN \(context.targetProvider.name.uppercased())"
    }

    private func continueConversation(_ session: AgentSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context.composedPrompt, forType: .string)
        guard context.targetProvider == session.provider else {
            if let url = context.targetProvider.conversationURL { NSWorkspace.shared.open(url) }
            routingMessage = "Reply copied. Opened provider; this is not the original conversation."
            return
        }
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
        case .grok:
            guard let id = session.conversationID, !id.isEmpty else {
                routingMessage = "Grok session ID was not recorded; reply copied."
                return
            }
            let command = "grok --resume \(id)"
            NSPasteboard.general.setString(command, forType: .string)
            if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                NSWorkspace.shared.open(terminal)
                routingMessage = "Grok resume command copied. Paste it in Terminal, then paste your reply."
            } else {
                routingMessage = "Grok resume command copied: \(command)"
            }
        default:
            if let url = context.targetProvider.conversationURL { NSWorkspace.shared.open(url) }
            routingMessage = "Reply copied. This provider’s exact chat continuation is not recorded."
        }
    }

    private func recentFolders(for provider: AIProvider) -> [String] {
        var seen = Set<String>()
        return monitor.snapshot(for: provider).sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { session in
                let folder = session.project.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !folder.isEmpty, seen.insert(folder).inserted else { return nil }
                return folder
            }
            .prefix(3)
            .map { $0 }
    }

    private func attachFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            context.attach(panel.urls)
            MomoFeedback.perform()
        }
    }
}

private struct PromptAssistPanel: View {
    let provider: AIProvider
    let folders: [String]
    let selectedFolder: String?
    let attachments: [URL]
    @Binding var enhancePrompt: Bool
    let selectFolder: (String) -> Void
    let attachFiles: () -> Void
    let removeAttachment: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(provider.name.uppercased()).font(BarBoyStyle.microLabel).foregroundStyle(.secondary)
            Toggle("IMPROVE PROMPT", isOn: $enhancePrompt)
                .font(BarBoyStyle.microLabel)
                .toggleStyle(.checkbox)
                .help("Copy a cleaner prompt with task, context, files, next steps, and truth checks.")
            Button("ATTACH") { attachFiles() }.barBoyButton()
            if folders.isEmpty && attachments.isEmpty {
                Text("No recent folders")
                    .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
            } else {
                FolderList(items: folders, selected: selectedFolder, action: selectFolder)
                if !attachments.isEmpty {
                    FolderList(items: attachments.map(\.lastPathComponent), selected: nil) { name in
                        if let match = attachments.first(where: { $0.lastPathComponent == name }) {
                            removeAttachment(match)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(BarBoyStyle.surface)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
    }
}

private struct FolderList: View {
    let items: [String]
    let selected: String?
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Text(item.uppercased())
                        .font(BarBoyStyle.microLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 7)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .background(selected == item ? Color.primary.opacity(0.12) : BarBoyStyle.raised)
                        .overlay(Rectangle().stroke(selected == item ? Color.white : BarBoyStyle.hairline, lineWidth: selected == item ? 1.5 : 1))
                }
                .buttonStyle(.plain)
                .help(item)
            }
        }
    }
}

private struct VoiceInlineBar: View {
    @ObservedObject private var voice = VoiceInput.shared

    var body: some View {
        HStack(spacing: 6) {
            Button(voice.isActive ? "STOP" : "HANDS-FREE") {
                if voice.isActive { voice.stop() }
                else {
                    voice.prepare(.handsFree)
                    Task { await voice.start() }
                }
            }.barBoyButton()
            Button("USE VOICE") { voice.useDraft() }
                .barBoyButton()
                .disabled(voice.text.isEmpty || voice.isActive)
            Text(voice.text.isEmpty ? voice.state.rawValue : voice.text)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(voice.isActive ? BarBoyStyle.coral : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .help(voice.message)
    }
}

private struct ReturnContextPanel: View {
    let session: AgentSession
    let autoResumeState: String
    let targetProvider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReturnContextRow(title: "RECORDED", value: recordedLine, alert: session.attention.isUrgent)
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            ReturnContextRow(title: "CONTINUE", value: resumeLine, alert: autoResumeState.hasPrefix("Manual") || autoResumeState.contains("unavailable"))
            Rectangle().fill(BarBoyStyle.hairline).frame(height: 1)
            ReturnContextRow(title: "NEXT", value: nextStepLine, alert: false)
        }
        .background(session.attention.isUrgent ? BarBoyStyle.coral.opacity(0.08) : BarBoyStyle.surface)
        .overlay(Rectangle().stroke(session.attention.isUrgent ? BarBoyStyle.coral : BarBoyStyle.hairline, lineWidth: 1))
    }

    private var recordedLine: String {
        let reason = session.attentionReason ?? session.detail
        let state = session.stoppedAfterUsageGrowth ? "Stopped after usage grew" : session.attention.label.capitalized
        return "\(state): \(reason)"
    }

    private var resumeLine: String {
        if AutoResumeService.supportsUnattendedResume(session) {
            return "Auto-resume: \(autoResumeState). Codex CLI can continue without you."
        }
        if autoResumeState.hasPrefix("Manual · resets in") {
            return "\(autoResumeState). MOMO will bring you back when it opens."
        }
        if autoResumeState == "Authorize to continue" {
            return "Auto-resume needs provider access. Copy and open is manual now."
        }
        if session.provider == .codex && session.recordedSource != "cli" {
            return "\(autoResumeState). Open the task and paste the reply."
        }
        return "\(autoResumeState). Copy and open is manual for now."
    }

    private var nextStepLine: String {
        switch targetProvider {
        case .codex:
            return "Press OPEN CODEX TASK. Paste the copied reply there."
        case .claude:
            return "Press RESUME CLAUDE. Paste the copied command in Terminal."
        case .grok:
            return "Press RESUME GROK. Paste the copied command in Terminal."
        default:
            return "Press COPY + OPEN \(targetProvider.name.uppercased()). Paste the copied reply there."
        }
    }
}

private struct ReturnContextRow: View {
    let title: String
    let value: String
    var alert = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(alert ? BarBoyStyle.coral : Color.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(BarBoyStyle.bodySmall)
                .foregroundStyle(alert ? BarBoyStyle.coral : Color.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
