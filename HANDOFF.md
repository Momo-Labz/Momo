# MOMO handoff

## Current state

Version 0.4 is a buildable native macOS 14 menu-bar app, a buildable iOS 17 MOMO RELAY companion, and a printable Agent Desk prototype. The Mac opens as a compact models-only strip and expands into a horizontal Home, Agents, and Tools workspace. Both apps prioritize the human return queue and expose model/MCP/plugin/skill provenance when sessions provide it. The Mac separately inventories installed MCP servers, plugins, marketplaces, and skills and marks only capabilities with recorded session evidence as `USED`. Core monitoring remains local and requires no provider credentials.

## Before public distribution

1. Set the Momo Labz Apple Developer Team in `project.yml`.
2. Replace the development icon with a 1024×1024 source if a higher-resolution original is available.
3. Enable hardened runtime, sign with Developer ID Application, and notarize.
4. Implement `SMAppService.mainApp.register()` before enabling Launch at Login.
5. Confirm that the GitHub Sponsors URL is the intended Support Us destination.
6. Run a privacy review against real session files for every enabled adapter after schema changes.
7. Treat needs-attention parsing as conservative. Claude, Codex, and Cursor have sanitized schema fixtures; add equivalent fixtures before replacing the generic Gemini or Grok adapters.
8. Validate the enclosure against the actual purchased LCD PCB and connector locations before a production print.
9. Replace local HTTP with an authenticated encrypted channel before selling pre-paired hardware.
10. Add the Momo Labz Apple Developer Team, iOS app icon, signing, and TestFlight configuration before installing MOMO RELAY on customer iPhones.
11. Implement the OpenAI/Anthropic organization-usage adapters behind Keychain before changing `ORG API` from an access path into a connected state.
12. Add APNs and an opt-in encrypted relay before promising alerts while the iPhone is away from the local network or the companion is suspended.

## Architecture

- `BarBoyApp.swift`: menu-bar, settings, and preview window scenes.
- `ActivityMonitor.swift`: enabled-provider process scanning, parallel recent-session parsing, installed-inventory refresh, and the 15-second refresh loop. Its process pipe must be drained before waiting or large process tables can deadlock.
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

## Verified 0.4 checks

- `BAR_BOY_REAL_DATA_CHECK=1 BAR_BOY_RENDER_SNAPSHOTS=1` runs the complete 20-test suite, live metadata smoke check, and six Mac snapshot states.
- The real-machine smoke test reports aggregate inventory/session counts only; it does not emit names, paths, titles, prompts, or details.
- MOMO RELAY has been built, installed, launched with sanitized demo data, and screenshot-checked on an iPhone simulator.
- The hardware body, vented back, and stand STL files are generated; dimensions still require validation against the purchased 3.5-inch 480 × 320 display board.

## Distribution command

Generate the Xcode project, archive with the configured Developer ID, export a notarized app, then package it in a DMG. Do not publish the current unsigned development build as a trusted download.
