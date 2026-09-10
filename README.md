# BAR BOY

BAR BOY is a private, local-first macOS menu-bar companion for seeing Codex, Claude Code, and Gemini CLI activity in one calm place.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Docs/barboy-dark.png">
  <img alt="BAR BOY dashboard in light and dark mode" src="Docs/barboy-light.png" width="420">
</picture>

## What works in 0.1

- Native SwiftUI `MenuBarExtra` with monochrome light and dark appearances.
- Local detection of active Codex, Claude Code, and Gemini CLI processes.
- Recent main-agent and subagent session summaries from local JSONL files.
- Quick local token counts for session files that expose token metadata.
- One-click links to each provider’s official usage page.
- Compact menu-bar mode, idle-provider filtering, and macOS menu-bar cleanup guidance.
- No analytics, backend, prompt upload, or account-password collection.

## Build

Requirements: macOS 14+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -configuration Release -derivedDataPath DerivedData build
```

The unsigned development app is created at `DerivedData/Build/Products/Release/BAR BOY.app`.

Release builds are universal binaries for Apple silicon and Intel Macs. The development DMG is ad-hoc signed but not Apple-notarized; a public download should be signed with the Momo Labz Developer ID and notarized first.

## Product truth

macOS has no supported public API that lets BAR BOY remove arbitrary third-party menu-bar items. The Menu Calm action opens Apple’s supported controls and explains the built-in Command-drag gesture. Likewise, consumer subscription quota APIs are not consistently public, so BAR BOY links to official usage pages and labels local token counts as local estimates.

## Strong next additions

1. Notification thresholds for long-running/stalled agents and high usage.
2. Session search, pinning, and project filters.
3. Git branch/worktree and test-status context beside each agent.
4. Opt-in OpenAI and Anthropic organization-admin usage adapters, with keys stored in Keychain.
5. A signed, notarized DMG plus Sparkle updates.
6. Launch-at-login using `SMAppService` after signing is configured.
7. Accessibility-permission-powered advanced menu-bar shelf, only if it can remain App Store compliant.

## Privacy

See [PRIVACY.md](PRIVACY.md). BAR BOY currently makes no network request except when you explicitly open a provider usage page or Support Us.
