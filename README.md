# BAR BOY

BAR BOY is a working title for a private, local-first Momo Labz agent desk: one compact place to see Codex, Claude, Gemini, Cursor, and Grok work at once—and notice when any of them needs you.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Docs/barboy-dark.png">
  <img alt="BAR BOY dashboard in light and dark mode" src="Docs/barboy-light.png" width="420">
</picture>

## What works in 0.2

- Native SwiftUI `MenuBarExtra` with monochrome light and dark appearances.
- Local detection of active Codex, Claude Code, Gemini CLI, Cursor, and Grok processes.
- Recent main-agent and subagent session summaries from local JSONL files.
- Conservative `NEEDS YOU`, failed, completed, working, and idle states when local event data exposes them.
- Optional macOS notifications for newly blocked or failed sessions.
- A deliberately short menu-bar mark: one icon plus at most one attention/activity count.
- Quick local token counts for session files that expose token metadata.
- One-click links to each provider’s official usage page.
- A global **Control–Option–Space** Quick Ask palette that routes a copied prompt to any supported provider.
- An opt-in, token-paired local Desk Display page designed for 480 × 320 screens.
- A Raspberry Pi kiosk recipe plus printable body, back, and stand STL files under `Hardware/`.
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

macOS has no supported public API that lets BAR BOY remove arbitrary third-party menu-bar items. Menu Calm opens Apple’s supported controls. Likewise, consumer subscription quota APIs are not consistently public, so unlinked short/week quota cells show an honest dash, official usage pages remain one click away, and local token counts are labeled as local.

Quick Ask currently copies the request and opens the chosen provider; it does not secretly inject keystrokes or execute an AI action. Voice capture and delegated actions stay visibly marked as next-stage features until their permission and confirmation model is complete.

## Strong next additions

1. Provider-supported quota adapters and OAuth/account linking, with secrets in Keychain.
2. Speech-to-text Talk, Dictate, and Hands-free modes with contextual microphone permission.
3. A trust ladder for actions: suggest → prepare → confirm → execute, plus per-action allowlists and an audit log.
4. Click a blocked session to focus the exact terminal/editor/task that needs a response.
5. Git branch/worktree, tests, PR status, and concrete outcome context beside each agent.
6. A signed, notarized DMG, Sparkle updates, and `SMAppService` launch at login.

## Privacy

See [PRIVACY.md](PRIVACY.md). The Desk Display server is off by default and stays on the local network when enabled.
