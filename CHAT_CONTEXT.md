# MOMO Chat Context and Handoff

Updated: 2026-09-14

This file records the product direction, implementation decisions, verification, and remaining work from the MOMO conversation so the next session can continue without reconstructing the history.

## Overall project handoff

MOMO began as a compact menu-bar monitor for Codex, Claude, and Cursor work. The project grew into a single local workspace that combines provider activity, recent project/chat navigation, a Quick Ask composer, voice input, an Obsidian-style knowledge graph, and optional Ollama assistance. The product is intended to reduce context switching: a person should be able to glance at the menu, see what finished or needs attention, expand the same surface when more context is needed, choose a relevant folder and named chat, and continue work without opening a separate dashboard for every provider.

The project is deliberately local-first. Provider sessions are read from authorized local folders, Brain data comes from an explicitly connected Obsidian vault, and Ollama is contacted only through its loopback server when the person asks for an answer or suggestion. MOMO must distinguish recorded facts from unavailable provider data and from AI suggestions. It should never imply that an account quota, running state, chat destination, or continuation is known when the source did not record it.

The current codebase is a native SwiftUI macOS menu-bar app generated from `project.yml`. `Sources/` contains the application and services, `Tests/` contains fixture and backend/visual tests, `Resources/` contains provider artwork, and `Docs/` contains supporting project documentation. `BarBoy.xcodeproj` is generated output; regenerate it with XcodeGen after adding or removing source files. The app is branded MOMO/MomoLabz even though some legacy filenames still use BAR BOY/BarBoy.

The next chat should treat this document as the working contract: preserve the local-first boundary, inspect the current checkout before editing, continue from the latest commit rather than recreating the UI, and update this handoff whenever a major behavior or limitation changes.

## Product goal

MOMO is a local-first macOS menu-bar workspace for seeing when AI work finishes, what is running, which provider needs attention, and which project or chat should be opened next. The compact menu should stay readable and low distraction. Expand should grow from the same menu surface rather than opening a second browser or detached workflow.

## Interface direction requested

- Keep the dark MOMO identity, restrained status colors, larger readable type, consistent spacing, and dividers between Home, Agents, Tools, and Network.
- Keep the brand block, compact provider cards, settings control, power/off control, refresh, provider, expand/contract, and overview actions proportional.
- Place the attention control beside the MOMO/live/reset header information. Use amber for errors or approvals and red only for a recorded provider limit.
- Show running-session count and the nearest recorded reset in the header gap.
- Compact Home, Agents, Tools, and Network should each show page-specific content instead of only repeating navigation.
- Expand grows downward from the same menu surface. Contract returns to compact mode while preserving provider selection, folder selection, and drafts.
- The expanded Ask surface shows only relevant recent folders and chats first, with search and an explicit way to show more. It must display chat names, not opaque IDs, and clearly say when ChatGPT history is not connected.
- Provide “Open original chat” only when MOMO has a verified destination.
- The attention inspector must remain inside MOMO. Done/Contract must not close the entire app.

## Brain and Ollama direction

- Network/Brain is based on an explicitly connected Obsidian vault.
- Index Markdown metadata, titles, tags, and explicit links incrementally; skip hidden directories and attachments.
- Keep the graph bounded: 80 visible nodes by default, with an explicit expansion up to 200.
- Distinguish recorded links from Ollama suggestions. Suggestions require acceptance before becoming links.
- Ollama is local-only, optional, and on-demand. It must not download models or run inference while idle.
- Ollama answers cite selected notes, keeps one generation active, bounds prompt/output size, supports cancellation and timeout states, and caches answers for five minutes keyed by model, prompt, and source revision.
- Save-to-Obsidian previews a new note and writes only after an explicit Save; filenames are collision-safe and existing notes are never overwritten.

## Provider usage truthfulness

Codex has recorded local rate-limit events and can show observed short/long windows and reset times. Claude transcripts can contain session token totals and provider-owned limit/error events, but normally do not expose consumer account quota. Cursor agent transcripts currently do not expose reliable token usage or account quota. MOMO therefore shows dashes or an unavailable explanation rather than fabricating percentages.

The safe future path for Claude/Cursor account usage is an explicit “Analyze usage page with Ollama” flow: open the official provider page, let the user copy the visible usage section, send only that pasted text to local Ollama, validate the extracted percentage/reset, label it as copied provider-page data, and cache it briefly. Browser cookies and credentials must not be given to Ollama.

## Implemented architecture

- `MomoSurface` stores page, selected provider, pane, attention filter, and expansion state together.
- `ActivityMonitor` performs bounded provider scans, coalesces refresh requests, slows polling while the menu is closed, and caches unchanged session files by modification time and size.
- Session history is bounded and deduplicated by provider plus conversation identity. Process presence alone is not treated as proof that every chat is running.
- `ClaudeSessionAdapter`, `CodexSessionAdapter`, and `CursorSessionAdapter` preserve provider-specific provenance and leave unsupported fields unavailable.
- `SessionPresentation` supplies relevant recent chats and readable names.
- `ConversationSidebar` provides project/chat search, recent folders, bounded chat lists, provider switching, and folder selection.
- `CommandPaletteView` is embedded in the MOMO surface. It supports text, voice, attachments, original-chat routing when verified, and continuation guidance.
- File URLs can be dragged into the prompt editor. Attachments remain in the in-memory draft and the menu panel is configured to remain present while Finder or an attachment panel is active.
- Voice partial recognition is mirrored into the prompt draft while speaking, so words are visible inside the text editor before the user stops.
- Refresh is limited to once per minute while the menu is open and every five minutes while it is closed. Ollama availability checks are throttled to two minutes.
- `MenuBarWindowPositioner` keeps the compact menu aligned to the right side of the active display.

## Recent commits

- `85b1d62` — reduced polling, preserved voice drafts, and kept attachments/menu behavior in MOMO.
- `9895cfa` — completed bounded provider workspace, page routing, usage explanations, and recent-chat presentation.
- `f8bc444` — positioned the menu and improved recorded Claude limit handling.
- `920ac3c` — kept the embedded chat inspector inside MOMO.
- `ff26921` — finished Brain visuals and documented installation.
- `e45cf86` — attached the Brain workspace to the menu bar.

The local branch is ahead of `origin/main`. A previous push attempt was blocked by the environment approval usage limit; do not claim the remote contains commits unless a later push succeeds.

## Verification

- The latest app build completed successfully with Xcode and macOS signing disabled for local development.
- The latest release ZIP passed `unzip -tq` integrity verification.
- The integrated test run completed with 89 tests, 1 intentional skip, and 0 failures. The skipped real capability inventory check requires `BAR_BOY_REAL_DATA_CHECK=1`.
- Brain graph profiling recorded 200 nodes in approximately 0.31 seconds in the fixture run.
- Fresh fixture captures covered compact Home, expanded Ask, compact Network, expanded Agents, and Tools states.

## Build artifacts

Latest packaged build:

- `MOMO Releases/0.5-usage-voice-fix/MOMO-0.5-usage-voice-fix.app`
- `MOMO Releases/0.5-usage-voice-fix/MOMO-0.5-usage-voice-fix.zip`

This is an unsigned development build. If macOS blocks the first launch, right-click the app and choose Open.

## Remaining work

1. Add the explicit copy-and-analyze usage flow for Claude and Cursor, with validated structured output and clear provenance.
2. Test drag-and-drop from Finder against the real menu-bar surface, including multiple files, denied security-scoped access, and menu dismissal behavior.
3. Test live speech with microphone permission denied, unavailable on-device recognition, partial-result replacement, Stop, and Use Voice.
4. Run a real-vault Brain profile and verify that unchanged refreshes do not re-index note bodies.
5. Rebuild and capture compact, expanded, attention, and Brain screenshots after any further UI changes.
6. Push the latest local commits to `main` when remote approval is available.

## Working constraints

- Do not invent provider quotas, model usage, running-chat state, or account identity.
- Do not read browser cookies or provider passwords.
- Do not download or start Ollama automatically.
- Keep provider credentials and usage data local.
- Keep drafts and attachments scoped to the selected provider/chat/folder.
- Use the project’s `project.yml` as the authoritative XcodeGen input and regenerate `BarBoy.xcodeproj` after source-file changes.

## How the next chat should resume

1. Read this file and `README.md`, then inspect `git status` and the latest commits.
2. Start with the remaining usage-import, live drag/drop, voice, and real-vault verification items instead of reopening already settled compact-layout questions.
3. Treat any new provider data as unverified until its source and account scope are recorded.
4. Build with XcodeGen followed by `xcodebuild` before packaging. Capture the affected compact and expanded states after UI changes.
5. Report whether changes are only local, committed locally, or pushed to the remote; these are separate states.
