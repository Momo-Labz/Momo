# BAR BOY handoff

## Current state

Version 0.3 is a buildable native macOS 14 menu-bar app, a buildable iOS 17 MOMO RELAY companion, and a printable Agent Desk prototype. The Mac now prioritizes a human return queue and records model/MCP/plugin/skill provenance when sessions expose it. Core monitoring remains local and requires no provider credentials.

## Before public distribution

1. Set the Momo Labz Apple Developer Team in `project.yml`.
2. Replace the development icon with a 1024×1024 source if a higher-resolution original is available.
3. Enable hardened runtime, sign with Developer ID Application, and notarize.
4. Implement `SMAppService.mainApp.register()` before enabling Launch at Login.
5. Confirm that the GitHub Sponsors URL is the intended Support Us destination.
6. Run a privacy review against real session files for every enabled adapter after schema changes.
7. Treat the current needs-attention parser as a conservative heuristic; add schema fixtures per provider before promising guaranteed alert delivery.
8. Validate the enclosure against the actual purchased LCD PCB and connector locations before a production print.
9. Replace local HTTP with an authenticated encrypted channel before selling pre-paired hardware.
10. Add the Momo Labz Apple Developer Team, iOS app icon, signing, and TestFlight configuration before installing MOMO RELAY on customer iPhones.
11. Implement the OpenAI/Anthropic organization-usage adapters behind Keychain before changing `ORG API` from an access path into a connected state.
12. Add APNs and an opt-in encrypted relay before promising alerts while the iPhone is away from the local network or the companion is suspended.

## Architecture

- `BarBoyApp.swift`: menu-bar, settings, and preview window scenes.
- `ActivityMonitor.swift`: process scanning and conservative JSONL metadata extraction.
- `DashboardView.swift`: the production popover UI.
- `SettingsView.swift`: provider controls and privacy disclosure.
- `Models.swift`: providers, sessions, and snapshots.
- `AttentionNotifier.swift`: opt-in user notifications for newly urgent sessions.
- `GlobalShortcutService.swift` and `CommandPaletteView.swift`: global Quick Ask routing.
- `DeskDisplayServer.swift`: token-paired local 480 × 320 status page and JSON endpoint.
- `iOS/Sources/`: MOMO RELAY pairing, Keychain storage, local polling, notifications, and iPhone return-queue UI.
- `Hardware/`: kiosk setup, OpenSCAD source, STL exporter, and generated printable parts.

## Distribution command

Generate the Xcode project, archive with the configured Developer ID, export a notarized app, then package it in a DMG. Do not publish the current unsigned development build as a trusted download.
