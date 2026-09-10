# BAR BOY handoff

## Current state

Version 0.1 is a buildable native macOS 14 menu-bar app. Its core monitoring is local and requires no provider credentials.

## Before public distribution

1. Set the Momo Labz Apple Developer Team in `project.yml`.
2. Replace the development icon with a 1024×1024 source if a higher-resolution original is available.
3. Enable hardened runtime, sign with Developer ID Application, and notarize.
4. Implement `SMAppService.mainApp.register()` before enabling Launch at Login.
5. Confirm that the GitHub Sponsors URL is the intended Support Us destination.
6. Run a privacy review against real Codex, Claude, and Gemini session files after schema changes.

## Architecture

- `BarBoyApp.swift`: menu-bar, settings, and preview window scenes.
- `ActivityMonitor.swift`: process scanning and conservative JSONL metadata extraction.
- `DashboardView.swift`: the production popover UI.
- `SettingsView.swift`: provider controls and privacy disclosure.
- `Models.swift`: providers, sessions, and snapshots.

## Distribution command

Generate the Xcode project, archive with the configured Developer ID, export a notarized app, then package it in a DMG. Do not publish the current unsigned development build as a trusted download.

