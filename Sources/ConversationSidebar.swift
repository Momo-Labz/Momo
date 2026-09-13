import AppKit
import SwiftUI

/// Uses authorized provider records only. No filesystem discovery occurs here.
struct ConversationSidebar: View {
    @ObservedObject var context: QuickAskContext
    @EnvironmentObject private var monitor: ActivityMonitor
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var query = ""
    @State private var showMore = false
    @State private var expandedFolders: Set<String> = []

    private var sessions: [AgentSession] {
        SessionPresentation.relevant(monitor.snapshot(for: context.provider).sessions.map { preferences.presented($0) }, limit: 200)
    }
    private var folders: [String] {
        var seen = Set<String>()
        return sessions.compactMap { session in
            guard seen.insert(session.project).inserted else { return nil }
            return session.project
        }.filter { folder in
            query.isEmpty || folder.localizedCaseInsensitiveContains(query) || sessions.contains {
                $0.project == folder && SessionPresentation.title(for: $0).localizedCaseInsensitiveContains(query)
            }
        }
    }
    private var visibleFolders: [String] {
        var result = Array(folders.prefix(showMore || !query.isEmpty ? 50 : 3))
        if let current = context.selectedFolder ?? context.session?.project, folders.contains(current), !result.contains(current) {
            result.insert(current, at: 0)
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Provider", selection: Binding(get: { context.provider }, set: {
                context.switchProvider($0)
                MomoSurface.shared.selectProvider($0)
                query = ""; showMore = false
            })) {
                ForEach(AIProvider.allCases) { Text($0.name).tag($0) }
            }.labelsHidden()
            TextField("Search projects or chats", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search known projects and chats")
            Button("NEW CHAT") { context.newChat() }.barBoyButton()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleFolders, id: \.self) { folder in
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                context.newChat(); context.selectFolder(folder)
                            } label: {
                                Label(folder, systemImage: "folder")
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 5)
                            }.buttonStyle(.plain).help(folder)
                            let chats = sessions.filter { $0.project == folder && (query.isEmpty || folder.localizedCaseInsensitiveContains(query) || SessionPresentation.title(for: $0).localizedCaseInsensitiveContains(query)) }
                            ForEach(Array(chats.prefix(expandedFolders.contains(folder) || !query.isEmpty ? 50 : 5))) { chat in
                                Button {
                                    context.select(chat); context.selectFolder(folder)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(SessionPresentation.title(for: chat)).font(.system(size: 12)).lineLimit(1)
                                        Text(chat.isRunning ? "Running now" : chat.ageLabel)
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(context.session?.id == chat.id ? BarBoyStyle.raised : .clear)
                                    .overlay(Rectangle().stroke(context.session?.id == chat.id ? Color.white : .clear, lineWidth: 1))
                                }.buttonStyle(.plain).padding(.leading, 12)
                                    .help(SessionPresentation.title(for: chat))
                            }
                            if chats.count > 5 && !expandedFolders.contains(folder) {
                                Button("Show older chats") { expandedFolders.insert(folder) }
                                    .font(BarBoyStyle.bodySmall).buttonStyle(.plain).padding(.leading, 19)
                            }
                        }
                    }
                    if folders.isEmpty {
                        Text(query.isEmpty ? "No recent projects available. Enable provider access in Settings or choose a folder." : "No matching chats in the available history.")
                            .font(BarBoyStyle.bodySmall).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxHeight: 360)
            if folders.count > 3 && !showMore {
                Button("SHOW MORE PROJECTS") { showMore = true }.barBoyButton()
            }
            Button("Choose another folder…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false; panel.canChooseDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    context.newChat(); context.selectFolder(url.path)
                }
            }.buttonStyle(.plain).font(BarBoyStyle.bodySmall)
            Text("Available local history. ChatGPT history isn’t connected.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(BarBoyStyle.surface)
    }
}
