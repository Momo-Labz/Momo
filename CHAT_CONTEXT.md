# MOMO Chat Context and Handoff

Updated: 2026-09-16 (force Welcome onboarding + MOMO alerts + Talk Free/Plus)

This file records the product direction, implementation decisions, verification, and remaining work from the MOMO conversation so the next session can continue without reconstructing the history.

## September 16 — Force Welcome + MOMO alerts + Talk (new PR)

Branch `cursor/force-onboarding-momo-talk-0ef6` off `main` after PR #1 merge.

### Priority 1 — onboarding gate (Mac-test blocker)
- Auto-open expanded panel on launch when `needsTrackingOnboarding` (`!trackingOnboardingSeen`)
- Full-screen Welcome overlay blocks chrome until finished; Settings → **Replay onboarding** clears the flag and reopens Welcome
- Settings → Providers cleaned: **Replay onboarding** / **Connect providers** + folder authorize only (no button pile)
- Provider strip: allowed-only + equal flexible widths
- Connect still opens default system browser; soft return → Confirm usage banner (no cookie import)

### Priority 2 — animated MOMO + sound
- Header: status → animated MOMO → alert legend → chrome icons
- Alerts flash MOMO coral + optional system sound (Settings → Notifications; mute wins)
- Wired from AttentionNotifier for failure / needs-you / session stopped / usage thresholds

### Priority 3 — Talk Free → MOMO+
- Hands-free Talk: local Ollama Q&A on usage + activity only (no task routing)
- Free = 1 onboarding trial + 3 uses; then CMO upsell copy verbatim
- Soft Plus entitlement toggle (no StoreKit); shortcut editable in Settings → General

Mac verify (Linux cannot `xcodebuild`):

```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Manual: fresh defaults → Welcome auto-opens → intent → browser allow → Talk trial; strip proportional; Replay onboarding; MOMO flashes on alert; Talk free quota → upsell.

## September 16 — PR #1 onboarding redesign + UX fixes

Landed on `cursor/wire-usage-capture-4177` (merged to main):

### Onboarding (replaces plugins-style toggles)
- CMO verbatim copy in Welcome / intents / provider chooser / return CTA (do not paraphrase)
- **Welcome to MOMO Trackr** — “Local tracking for the AI tools you already use. On-device only — we don’t scrape browser cookies or invent usage %.”
- **What do you want help with?** — Track usage across models / Organize prompts / Keep project folders tidy (`onboardingIntents.v1`)
- **Allow the providers you use** — “Tap to sign in on their official site in your browser…”; confirm snapshot before verified numbers
- Primary **Continue**; after return **Confirm usage snapshot** + “Verified % unlock after you preview and accept. Timed refresh is MOMO+.”
- Soft return uses existing Manual Preview→Confirm `UsageCaptureService` (not auto-opened on first connect tap)
- Timed 15/30/60 stay NEXT / unscheduled (MOMO+)
- Settings revisit: onboarding, intents, connect providers + existing Connect Usage
- Banned: “live sync,” “connected to your account quota,” fake gauges before Manual confirm

### Proportional strip
- Only allowed providers after onboarding; empty strip shows CONNECT PROVIDERS CTA
- Equal flexible widths via `ProviderStripLayout.equalCardWidth`

### UX fixes
- User-facing thinking/status: **MOMO THINKING** / **CHECKING LOCAL MODEL** (Ollama remains engine; model picker still shows e.g. `llama3:latest`)
- Settings: sticky Tracking header + provider strip stay above Settings; embedded custom tabs + Back (no overlapping BACK/SETTINGS over system TabView)
- Full-box hit targets: `MomoBoxedButtonStyle` for `barBoyButton` / `barBoyIconButton`; Brain ASK / SUGGEST LINKS / SAVE use bordered buttons

## September 16 — prior PR #1 slice (A/B/C + MainActor fix)

- **A Sticky chrome:** header + provider strip + tab bar outside scrolling tab body
- **B** (superseded by Welcome→intent→connect above): earlier plugins-style allow chooser
- **C Usage peek:** double-click status item → peek for allowed providers
- **Compile fix:** `UsageCaptureHostAllowlist` + `nonisolated` capture helpers

Mac verify (Linux cannot `xcodebuild`):

```sh
xcodegen generate   # or use committed BarBoy.xcodeproj
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Manual: first-run Welcome→intents→browser+permission; Confirm usage banner; proportional strip; Settings under sticky chrome; Brain shows MOMO THINKING; header boxes click full area.

## Overall project handoff

MOMO is now a tracking-first utility for Codex, Claude, Gemini, Cursor, and Grok. The MVP monitors recorded provider activity, verified usage observations, completions, failures, approvals, and resets. It does not try to replace provider chat interfaces. Obsidian Brain remains an optional local extension with Ollama used only on explicit requests.

The project is deliberately local-first. Provider sessions are read from authorized local folders, Brain data comes from an explicitly connected Obsidian vault, and Ollama is contacted only through its loopback server when the person asks for an answer or suggestion. MOMO must distinguish recorded facts from unavailable provider data and from AI suggestions. It should never imply that an account quota, running state, chat destination, or continuation is known when the source did not record it.

The current codebase is a native SwiftUI macOS menu-bar app generated from `project.yml`. `Sources/` contains the application and services, `Tests/` contains fixture and backend/visual tests, `Resources/` contains provider artwork, and `Docs/` contains supporting project documentation. `BarBoy.xcodeproj` is generated output; regenerate it with XcodeGen after adding or removing source files. The app is branded MOMO/MomoLabz even though some legacy filenames still use BAR BOY/BarBoy.

The next chat should treat this document as the working contract: preserve the local-first boundary, inspect the current checkout before editing, continue from the latest commit rather than recreating the UI, and update this handoff whenever a major behavior or limitation changes.

## Product goal

MOMO is a local-first macOS menu-bar workspace for seeing when AI work finishes, what is running, which provider needs attention, and which project or chat should be opened next. The compact menu should stay readable and low distraction. Expand should grow from the same menu surface rather than opening a second browser or detached workflow.

## Current interface direction

- Keep the dark MOMO identity, restrained status colors, larger readable type, consistent spacing, and dividers between Home, Agents, Tools, and Network.
- Keep the brand block, compact provider cards, settings control, power/off control, refresh, provider, expand/contract, and overview actions proportional.
- Place the attention control beside the MOMO/live/reset header information. Use amber for errors or approvals and red only for a recorded provider limit.
- Show running-session count and the nearest recorded reset in the header gap.
- Activity, Usage, and Brain replace the former Home, Agents, Tools, and Network navigation.
- The provider strip stays above the active page. After onboarding it shows only allowed tracking providers; before onboarding it still lists all five.
- Activity / Usage / Brain share that sticky chrome; only the tab body scrolls (Brain included).
- The panel is pinned to the right edge of the active display. Expand grows the same surface leftward and downward; Contract restores compact mode while preserving selection.
- Settings, session details, and usage capture are routes inside the attached menu-bar panel. They use one Back control and do not create competing top-level app windows.
- Status item single-click opens the Tracking panel; double-click opens the compact usage peek for allowed providers.
- Relevant sessions load in bounded pages and display readable names instead of opaque IDs.
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

- `MomoSurface` stores the tracker page, selected provider/session, and expansion state together.
- `ActivityMonitor` performs bounded provider scans, coalesces refresh requests, slows polling while the menu is closed, and caches unchanged session files by modification time and size.
- Session history is bounded and deduplicated by provider plus conversation identity. Process presence alone is not treated as proof that every chat is running.
- `ClaudeSessionAdapter`, `CodexSessionAdapter`, and `CursorSessionAdapter` preserve provider-specific provenance and leave unsupported fields unavailable.
- `SessionPresentation` supplies relevant recent chats and readable names.
- `TrackingDashboardView` keeps the provider strip above Activity, Usage, and Brain, paginates recent evidence, and owns the in-panel Settings/session/usage routes. The full Activity, Usage, and Brain rectangles are interactive.
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
2. Run a real-vault Brain profile and verify that unchanged refreshes do not re-index note bodies.
3. Capture compact, expanded, attention, Usage, Settings, and Brain screenshots after the tracking-first UI change.
4. Complete a signed and notarized release after the local behavior is accepted.

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
