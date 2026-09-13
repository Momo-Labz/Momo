# MOMO handoff

## Current state

Version 0.5 is a buildable native macOS 14 menu-bar app, a buildable iOS 17 MOMO RELAY companion, and a printable Agent Desk prototype. The Mac opens as a compact models-only strip and expands in place into a Chat/Ask workflow plus mini Home, Agents, Tools, and Brain previews. Both apps prioritize the human return queue and expose model/MCP/plugin/skill provenance when sessions provide it. The Mac separately inventories installed MCP servers, plugins, marketplaces, and skills and marks only capabilities with recorded session evidence as `USED`. Core monitoring remains local and requires no provider credentials.

## Before public distribution

1. Set the Momo Labz Apple Developer Team in `project.yml`.
2. Replace the development icon with a 1024×1024 source if a higher-resolution original is available.
3. Enable hardened runtime, sign with Developer ID Application, and notarize.
4. Implement `SMAppService.mainApp.register()` before enabling Launch at Login.
5. Confirm that the GitHub Sponsors URL is the intended Support Us destination.
6. Run a privacy review against real session files for every enabled adapter after schema changes.
7. Treat needs-attention parsing as conservative. Claude, Codex, Cursor, Gemini public-schema, and Grok documented-schema fixtures exist; add sanitized real-account fixtures before broadening either Gemini or Grok behavior.
8. Validate the enclosure against the actual purchased LCD PCB and connector locations before a production print.
9. Replace local HTTP with an authenticated encrypted channel before selling pre-paired hardware.
10. Add the Momo Labz Apple Developer Team, iOS app icon, signing, and TestFlight configuration before installing MOMO RELAY on customer iPhones.
11. Implement the OpenAI/Anthropic organization-usage adapters behind Keychain before changing `ORG API` from an access path into a connected state.
12. Add APNs and an opt-in encrypted relay before promising alerts while the iPhone is away from the local network or the companion is suspended.

## Architecture

- `BarBoyApp.swift`: menu-bar, settings, and preview window scenes.
- `ActivityMonitor.swift`: enabled-provider process scanning, parallel recent-session parsing, installed-inventory refresh, and the 30-second refresh loop. Each provider keeps only the newest 20 candidate files while walking folders. Parsed metadata is cached by provider, path, modification date, and file size; each provider prunes only its own stale cache entries. Its process pipe must be drained before waiting or large process tables can deadlock.
- `Adapters/ProviderSessionAdapter.swift`: provider parser seam and generic fallbacks.
- `Adapters/{Claude,Codex,Cursor}SessionAdapter.swift`: streaming, provider-specific local session readers.
- `Adapters/CapabilityInventory.swift`: metadata-only installed MCP/plugin/marketplace/skill inventory. It does not retain config values, commands, paths, or secrets.
- `DashboardView.swift`: the compact popup plus expanded three-tab workspace.
- `DesignSystem.swift` and `DESIGN.md`: Momo Labz visual tokens, provider marks, components, and motion contract. Ink `#201E1D`, paper `#F3F2F2`, and attention coral `#E25C48` come from the supplied Momo Labz sources.
- `SettingsView.swift`: provider controls and privacy disclosure.
- `Models.swift`: providers, sessions, and snapshots.
- `AttentionNotifier.swift`: opt-in user notifications for newly urgent sessions.
- `GlobalShortcutService.swift` and `CommandPaletteView.swift`: global Quick Ask routing.
- `DeskDisplayServer.swift`: token-paired local 480 × 320 status page and untruncated relay JSON endpoint with supplied provider-icon routes, Bearer/cookie auth, Host validation, redaction, CSP, and dynamic-port fallback.
- `Shared/RelayContract.swift`: the versioned status/provider/session payload shared by Mac and iOS.
- `iOS/Sources/`: MOMO RELAY pairing, separated Keychain credential storage, local polling, notifications, official provider icon assets, and iPhone return-queue UI.
- `Hardware/`: kiosk setup, OpenSCAD source, STL exporter, and generated printable parts.
- `Tests/Fixtures/`: sanitized Claude, Codex, Cursor, and installed-inventory fixtures.

## Verified 0.5 checks

- `BAR_BOY_REAL_DATA_CHECK=1 BAR_BOY_RENDER_SNAPSHOTS=1` runs the complete 20-test suite, live metadata smoke check, and six Mac snapshot states.
- The real-machine smoke test reports aggregate inventory/session counts only; it does not emit names, paths, titles, prompts, or details.
- MOMO RELAY has been built, installed, launched with sanitized demo data, and screenshot-checked on an iPhone simulator.
- The hardware body, vented back, and stand STL files are generated; dimensions still require validation against the purchased 3.5-inch 480 × 320 display board.

## Distribution command

Generate the Xcode project, archive with the configured Developer ID, export a notarized app, then package it in a DMG. Do not publish the current unsigned development build as a trusted download.

## Provider truth and chat replies, work in progress (2026-09-12)

Implemented and tested in this checkout:
- Local provider scans default off. Legacy visibility preferences do not count as consent. Settings explicitly requests local-folder authorization per provider, and revocation clears published sessions and rejects stale scan results.
- Clicking a session opens Quick Ask directly with that session's title and recorded problem. The global shortcut retains the selected session. Drafts are isolated by session ID and stored in memory only; the editor supports the user's macOS Dictation shortcut. Details remains a secondary action.
- Replies currently copy to clipboard. Exact provider-chat reopening is not implemented; the UI states this rather than opening a generic destination. The source session file can be opened separately when recorded.
- Capability extraction ignores arbitrary nested prompt/catalog text. Codex turn metadata and actual function calls, Claude assistant model/tool-call records, Cursor schema fields, and Grok documented `updates.jsonl` init records are selected explicitly. Gemini tool names are not treated as capability evidence.
- A running provider process no longer marks an unrelated disk session live. Other session-state and token heuristics still require replacement.

Validation: macOS xcodebuild test passed 15 tests with zero failures using `/tmp/momo-truth-build`. Rendered and inspected `/tmp/momo-chat-reply.png`. This is a source/build update, not an installed release. Live shortcut focus, notification routing, and dictation still require interactive validation.

Remaining full-goal work:
- User authorization for Gemini fixture capture covered the absent default `.gemini/tmp` folder only; Grok authorization must be requested separately. No account-specific permission should be inferred from an automatic goal continuation. Do not read those account session files until authorized.
- Capture sanitized real Gemini and Grok local schemas after the user approves each account folder. Local provider permission currently covers selected Mac folders, not individual remote account identity; do not call it remote account authorization.
- Verified exact-chat destinations and notification-to-chat routing.
- Expanded view as a longer continuation of the existing provider strip; full per-provider session state lists, including recorded stops after usage growth.
- Source-recorded quota window percentages/reset times, truthful unknown states, and actionable timing notifications. No invented usage-window percentages or causal rate-limit claims.


## MOMO index animation port (2026-09-12)

`DesignSystem.swift` now uses the branding index's exact 13 × 14 character geometry, LOOK/WALK sequence, and wave/blink frame holds. The compact and expanded headers use LOOK/WALK; Quick Ask uses the wave. Native tasks cancel on disappearance, pause in inactive scenes, and use the resting pose for Reduce Motion. `Tests/Fixtures/momo-index-frames.json` was extracted from the inspected pure grid and pose definitions of `../Branding/index.html`; tests compare every cell and duration. Updated source has not been installed over the user's running release.

## Latest verified progress (2026-09-12; supersedes pending items above)

- Expanded dashboard now continues the same 430-point compact strip downward into all returned sessions grouped by provider. Quota percentage/window has a dedicated line beneath tokens; absent/invalid source data renders `QUOTA —`. The 76% / 5HR screenshot value is synthetic test data, not live account usage.
- Gemini public-schema adapter handles full JSON and JSONL message replacement, checkpoints, and rewinds, keeping unsupported capabilities/liveness unknown. Model and complete per-message token totals come only from selected schema fields. `gemini-public-*` fixtures are synthetic public-schema tests, NOT sanitized local captures. The upstream references are in Tests/Fixtures/README.md.
- Grok has a schema-specific documented-session adapter for `summary.json` plus `updates.jsonl`. Real account captures remain pending explicit Grok folder authorization, and process detection remains separate.
- Structured lifecycle extraction replaces recursive error detection. Nested tool errors do not classify their containing session as failed. Missing lifecycle state is UNKNOWN; an old recorded working state is displayed as LAST: WORKING when liveness is not established.
- Session observations can mark a failed/interrupted session as STOPPED AFTER USAGE when it was previously working and recorded tokens increased. Recovery resets this marker. It does not infer rate-limit causation or historical transitions before monitoring began.
- Notification default-action routing now opens the matching current chat reply draft. Revoked or resolved sessions are no longer actionable through the stored notification mapping. Delivery, cold-launch behavior, and global shortcut focus still need interactive validation.
- Session deduplication uses stable IDs, preserving distinct chats with identical titles.

Latest verification: 22 macOS tests, zero failures; light/dark expanded screenshots inspected at `/tmp/barboy-light.png` and `/tmp/barboy-dark.png`. No installation or release overwrite performed.

Still required for the full goal: separate account authorization and sanitized real Gemini/Grok captures; actual quota/reset data adapters and timing optimization beyond Codex-recorded windows; verified provider chat reopening; live notification/shortcut/dictation validation; account-level identity boundaries beyond the explicit local-provider-folder consent.


## Authorized Gemini capture check

The user authorized Gemini read-only fixture capture. The authorized default session folder `.gemini/tmp` does not exist on this Mac, so no local Gemini sessions or real fixtures were captured. See `Docs/gemini-capture-status.json`. The public-schema tests remain the only Gemini adapter evidence. A user-provided alternate session location or a new Gemini CLI session is needed for real local validation. Grok access is not yet authorized.

## Global automatic continuation (2026-09-12)

User clarified this should be one setting, with no per-chat resume confirmation. Settings > General now has `Auto-resume after usage reset`, persisted and off until enabled. Provider authorization remains separate.

First implemented backend: local Codex CLI recordings (`session_meta.payload.source == cli`) with a valid UUID/project directory, a structured usage-limit error, a terminal task record, and explicit exhausted-window reset timestamps. Desktop/extension sessions are excluded because CLI resumption cannot guarantee their app-specific tools/context. The installed CLI's `exec resume --help` and generated app-server schemas were inspected without opening account session data.

Runtime checks the latest authorized snapshots every refresh, waits until five seconds after the latest exhausted-window reset, re-reads the source before launching, then invokes the exact UUID using Process arguments, without a shell or permission-bypass flags. Attempts are persisted before dispatch, one per session/reset pair, including uncertain/failed launches. Disabling stops new automatic launches; it does not terminate an already resumed task. New user input, manual interruption, or a new task event invalidates the candidate. It does not infer usage stops from prose, token growth, generic failures, or process presence.

Verification: 25 macOS tests passed. Dispatch timing and restart deduplication were tested using `/usr/bin/true` and synthetic files, never a real provider continuation. End-to-end account validation and desktop chat control remain unverified. Gemini/Grok local captures and adapters are deferred at the user's request until those tools are in use.

## Recorded quota ingestion (2026-09-12)

Codex `event_msg/token_count/rate_limits` windows now flow through the scanner into each session and the compact/expanded provider quota line. The provider line selects the latest recorded session observation (shortest window when observation timestamps match); it is not an account-identity binding or a live account API poll. Hover text discloses the observation time and missing account identity. Session Details lists the recorded usage windows. Expired windows render `QUOTA —`, never an invented zero. Invalid numeric values, booleans, missing duration/timestamp, and nested prompt lookalikes are rejected.

Validation: 27 macOS tests passed with zero failures. A new integration test scans only a temporary synthetic `.codex/sessions` root with process detection disabled and verifies the quota reaches both session and provider models. Live account data has not been inspected or validated.

## Codex desktop onboarding (2026-09-12)

Added first-run setup and Settings → Providers → Set up Codex desktop access. Local reads remain opt-in and revocable; the prompt explicitly covers all accounts present in the authorized local folders rather than claiming account-specific OAuth. Notification permission is separate. The installed com.openai.codex app registers the codex scheme, and its bundled task viewer uses codex://threads/<id>. MOMO now validates a UUID from the first session_meta record before opening that task; Copy + Open never sends a message. No account files were read to validate this integration. Desktop automatic turn submission remains unavailable; the existing automatic continuation implementation is CLI-only. Gemini and Grok real captures remain deferred by user direction.

Verification before upstream merge: 29 macOS tests passed; onboarding screenshot /tmp/momo-onboarding.png inspected for clipping and readable controls. No installed app replacement or live-account continuation was performed.

### Upstream integration

Merged origin/main through 6216ec3, preserving its MOMO product naming, relay fixes, installed-capability reader and schema-specific Codex/Claude/Cursor adapters. The consent gate now also covers capability configuration; revocation clears both session snapshots and the inventory. Gemini uses public-schema fixtures; Grok uses a documented `summary.json` plus `updates.jsonl` fixture adapter and still needs real authorized account captures. Codex quota observations and source links now flow through the full-stream Codex adapter. Provider process presence no longer marks a specific transcript as running. Distinct historical task IDs remain separate even when titles match. The requested expanded view replaces the previous tabbed hub layout.

Combined verification: 40 macOS tests, 1 explicitly skipped live-account check, 0 failures. Dark compact/expanded and onboarding screenshots inspected. Desktop deep-link dispatch is based on installed app code and synthetic UUID tests; real-account navigation and automatic CLI continuation have not been exercised. Desktop unattended turn submission remains an integration gap and is not advertised as supported.

## Voice, editable shortcuts, overview and conversation organization (2026-09-12)

- Settings → Shortcuts records and persists separate Quick Ask, Talk, Dictate and Hands-free combinations. Duplicates and modifier-free combinations are rejected; a failed registration keeps the old hotkey. Voice defaults use Control–Option with T/D/H. Haptics can be disabled and require compatible hardware.
- Voice uses AVAudioEngine and Apple's Speech framework, requests permissions at Start, and requires on-device recognition with no network fallback. Talk finishes after a pause; Dictate and Hands-free stop on the button/shortcut, recognition completion or 55-second limit. Hands-free accepts “MOMO stop” and “MOMO use draft”; neither sends a provider message. Closing the voice window releases capture. Microphone and speech usage descriptions are in project.yml.
- Access approval now shows an explicit authorized state and a short MOMO wave. Button presses change appearance immediately; keyboard popups open without entrance delay. Reduced Motion disables the character movement and waveform motion. Onboarding includes a separate Voice & Usage guide.
- Compact mode now has Add Provider, Refresh and Overview. Overview restores Home/Agents/Tools; Expand remains the longer provider strip. Both observed usage windows are displayed below tokens; a week is labeled WEEK. Missing/expired values remain dashes.
- Authorized Codex scans resolve names from its append-only session_index.jsonl (last name update wins), then group tasks by the recorded folder. Unknown names use an ID-based fallback instead of the prompt. Process-only rows explicitly remain unlinked to a chat.
- Quick Ask → Edit Name / Folder stores MOMO-only labels keyed by provider and task ID. This does not rename provider chats or move working directories. Each conversation shows auto-resume state, including unsupported connections, reset waiting and attempts. The global setting still controls future verified Codex CLI continuations only. Universal desktop/provider automatic continuation remains unfinished and is explicitly marked unavailable.

## UI and memory-pressure cleanup (2026-09-12)

- The menu-bar Expand action now grows the same MOMO menu surface downward through `MomoSurface.expanded` instead of opening a separate dashboard shell. The standalone dashboard window remains for shortcuts and fallback opening paths.
- The expanded menu adds compact Home, Agents, Tools, and Brain preview buttons above the Chat/Ask/Voice pane switcher. The Network page is now `MOMO BRAIN`: provider nodes, recent chat nodes, and recorded skill/MCP/plugin nodes.
- Quick Ask shows the top three recent folders for the selected provider, supports local file/folder attachments, and copies an improved prompt structure with task, working context, attached paths, requested output, and a truth check. Prompt text and attachments stay in memory until the user copies/opens.
- The return/reply panel now says what MOMO recorded, whether continuation is automatic or manual, and the next action to press. Details uses the same language and no longer leaves the user at a generic failure line.
- Memory pressure guardrails: scans never internalize every historical chat, candidate file lists are bounded while enumerating, parsed sessions are metadata-only, and unavailable quota/capability fields remain dashes rather than guessed values.

Primary API/schema references: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition and https://github.com/openai/codex/blob/main/codex-rs/rollout/src/session_index.rs . No real microphone recording, speech accuracy, physical haptic sensation, or external-account continuation was exercised by automated tests. The installed app must be replaced/relaunched to use this build.

## Conversation identity and reset countdowns (2026-09-12)

Fixed a failing baseline test: `testAutoResumeSettingPersistsAndDefaultsOff` authorized every
provider and then asserted the status mentioned authorization, which only happens when Codex is
*not* authorized. It now checks both directions with an injected executable.

The user's MOMO-only name/folder labels were saved but only applied in Quick Ask. `presented(_:)`
is now also applied in the compact popup and in notification content, so a renamed chat reads the
same on every surface.

Recorded quota windows render image-3 style: `5HR 76% · 59M`, `WEEK 32% · 23H`. A window with no
recorded reset shows percent only; an expired or invalid one stays `QUOTA —`, never zero.

Per-conversation auto-continue state now names the countdown. A recorded Codex CLI rollout reads
`Resumes in 4H`; everything else reads `Manual · resets in 4H`, or `Manual · desktop control not
connected` / `Manual · <Provider> control not connected` when no window is recorded. No provider
without a supported unattended path is ever described as automatic, and a regression test asserts
those states never contain "Resumes", "Continuing" or "automatic".

Notifications carry the chat name and folder as the subtitle, declare a visible action button
("Open reply" / "Continue chat"), and a new alert fires once when a recorded window has reopened
within the last 30 minutes — saying MOMO will continue it automatically only when that is true.

The compact provider cell names the running conversation instead of a generic activity count, with
the folder in its tooltip. Session rows drop the folder line when the surrounding list already
groups by folder header.

Verification: 50 macOS tests, 1 skipped, 0 failures (baseline was 47 with 1 failure). Compact and
expanded snapshots inspected in light and dark at `/tmp/barboy-compact-{light,dark}.png` and
`/tmp/barboy-{light,dark}.png`. Notification delivery, the action button, and live countdown
behaviour still need interactive validation on an installed build.

## Inspectable provider issues (commit 4bc12e4)

- Compact provider cards are now buttons. Selecting one opens the most urgent recorded chat first, so a visible failure or waiting state leads directly to the chat name, MOMO folder, source file, recorded usage windows, and latest provider detail.
- The investigation pane shows a per-chat continuation state and explicitly marks chats that stopped after usage grew. It includes the recorded reset time when the source provides one.
- Compact quota labels recompute on a 30-second timeline, so recorded 5HR/WEEK reset countdowns visibly advance instead of staying at the render-time value.
- Quick Ask keeps a separate draft per conversation, supports changing the MOMO-only name/folder, and offers a provider target picker. Claude continuation copies a validated `claude --resume <session-id>` command; Codex opens a validated `codex://threads/<uuid>` task link. Neither path sends a message automatically.

Static validation after this change: `swiftc -parse Sources/*.swift Sources/Adapters/*.swift` and `git diff --check` passed. The full Xcode test run was not repeated because the environment's automatic approval review rejected the build after the account usage limit was reached. The interaction commit is `4bc12e4`; the later adapter commit is `7be5408`.

## Gemini and Grok schema adapters (2026-09-12)

- Gemini continues to use the documented `ConversationRecord` adapter and public-schema fixtures. The authorized default `.gemini/tmp` folder is absent, so no real Gemini account data was copied.
- Grok now has a schema-specific `GrokSessionAdapter` for the documented Grok Build layout: sibling `summary.json` metadata plus `updates.jsonl` ACP `system/init`, `assistant`, and terminal `result` records. It records only source-backed title, folder, model, tokens, MCP names, skills, session state, and session ID; omitted plugins, account quota, and liveness remain unavailable.
- Synthetic Grok fixtures and malformed-input tests cover the adapter. They are explicitly non-account fixtures. `Docs/grok-capture-status.json` records that Grok authorization has not been granted and no local account files were read.
- A recorded Grok chat can now copy `grok --resume <session-id>` for manual continuation. MOMO does not claim unattended Grok continuation or send a message automatically.

Verification after adding the adapter: the focused Grok fixture test and the full macOS suite passed (`54 tests`, `2 skipped`, `0 failures`); the app target also built successfully.

Settings now names each provider's local session roots in its authorization dialog and states that one provider permission covers every account stored in those folders. The latest source commit is `bfcf595`. A subsequent isolated build passed; a later full test invocation was unable to start the test runner because CoreSimulator/testmanagerd was unavailable in the sandbox, so the last authoritative full-suite result remains the passing 54-test run above.

The scanner now has a dedicated Grok integration test (`0ab62f9`) that builds an isolated authorized `.grok/sessions` tree and verifies the production scanner publishes the adapter's recorded MCP and skill fields. The test source parses cleanly; rerunning it requires a functioning macOS testmanagerd service.

Custom local roots are persisted per provider. Settings → Providers → Choose local session folder opens a native folder picker, then shows the provider-specific authorization confirmation. The scanner applies those roots on settings launch and after authorization; revoking a provider still removes it from scanning. Latest implementation commits: `fb5b807` and `3c920a7`.

## Provider card usage controls (2026-09-12)

- Compact and expanded provider cards now show a larger hierarchy: provider, live state, token count, running/total session count, an optional usage bar, recorded usage percentage, and a reset countdown. Red is reserved for a recorded limit; amber marks an action or approval; white marks the selected card.
- Settings → General → Show provider usage bars controls the bar without changing recorded values. Missing provider usage remains `—`; MOMO never derives a quota from process presence or token totals.
- Screenshots: `/tmp/momo-compact-models.png` and `/tmp/momo-expanded-folders.png`. Latest build: `/tmp/momo-derived/Build/Products/Debug/MOMO.app`.
- Full macOS validation after this pass: 64 tests, 2 skipped, 0 failures. A later snapshot-only rerun was blocked by the sandbox's Xcode DerivedData/CoreSimulator permissions.

## Obsidian-style brain graph and compact header (2026-09-12)

- MOMO BRAIN now uses a local graph view inspired by Obsidian: provider, project, chat, source-file, skill, MCP, and plugin nodes are connected by recorded edges. Nodes are derived only from authorized local session metadata; no vault-wide content is imported.
- Chat and file nodes open the existing conversation inspector. Provider nodes open the most urgent recorded chat for that provider. The legend makes node types visible without requiring a separate explanation panel.
- The compact surface now carries the MOMO header treatment, four mini navigation controls, and a labeled OFF button alongside Expand. The power action still terminates MOMO immediately and does not change provider authorization.
- Validation after this pass: full macOS suite passed with 64 tests, 2 skipped, 0 failures; debug build completed. Screenshot: `/tmp/momo-network-brain.png`.

## Local Ollama bridge (2026-09-12)

- MOMO Brain checks the local Ollama API at `127.0.0.1:11434` and shows its model count/status in the Brain header. The service is only contacted from the Brain page, uses short timeouts, and stays offline when Ollama is not running.
- `OllamaService.complete(prompt:model:)` is the local-only seam for future Brain and agent actions. Prompts are bounded before sending, no remote fallback exists, and unavailable models leave the UI truthful.
- On this Mac the `ollama` executable is installed, but the API was offline during validation. The app therefore reports `OLLAMA OFFLINE` until the user starts Ollama and has a model available.
- The compact header was tightened to the MOMO navigation treatment: mini Home, Agents, Tools, and Brain buttons sit beside the status badge, labeled OFF control, and Expand.
- When a local model is available, `ASK LOCAL AGENT` asks Ollama for a three-bullet graph summary using only recorded provider, project, and chat names. The result appears below the graph; the action is disabled while Ollama is offline.
- When Ollama is offline, Brain shows `SET UP OLLAMA`. The button requires an explicit confirmation, then opens Ollama's official macOS download page; MOMO never downloads or installs a server silently.
