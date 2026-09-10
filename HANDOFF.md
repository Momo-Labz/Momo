# BAR BOY handoff

## Current state

Version 0.2 is a buildable native macOS 14 menu-bar app plus a printable Agent Desk prototype. Core monitoring is local and requires no provider credentials.

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

## Architecture

- `BarBoyApp.swift`: menu-bar, settings, and preview window scenes.
- `ActivityMonitor.swift`: process scanning and conservative JSONL metadata extraction.
- `DashboardView.swift`: the production popover UI.
- `SettingsView.swift`: provider controls and privacy disclosure.
- `Models.swift`: providers, sessions, and snapshots.
- `AttentionNotifier.swift`: opt-in user notifications for newly urgent sessions.
- `GlobalShortcutService.swift` and `CommandPaletteView.swift`: global Quick Ask routing.
- `DeskDisplayServer.swift`: token-paired local 480 × 320 status page and JSON endpoint.
- `Hardware/`: kiosk setup, OpenSCAD source, STL exporter, and generated printable parts.

## Distribution command

Generate the Xcode project, archive with the configured Developer ID, export a notarized app, then package it in a DMG. Do not publish the current unsigned development build as a trusted download.
