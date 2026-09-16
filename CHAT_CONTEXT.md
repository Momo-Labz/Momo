# MOMO Chat Context and Handoff

Updated: 2026-09-16 (honest CLI/file usage + Settings deep-links + onboarding resume + interval refresh)

Branch `cursor/usage-cli-onboarding-resume-02e3` off `main` after PR #5 merge `6d816e9`.

## P0 — Usage sources that match the apps (no invented %)

MOMO never scrapes WebKit / cookies and never invents percentages. Empty providers always show a **specific reason**.

| Provider | Readable sources (priority order) | Honest empty reason |
|---|---|---|
| **Claude** | `~/.claude/usage-limits.json` (ccusage), `usage-cache.json` / statusline caches, `Library/Application Support/Claude(-3p)/`, `/tmp/claude/statusline-*`, then optional `ccusage json` CLI | Claude.app menu % is live from Anthropic — not a plaintext local file. Install/sign in Claude Code or run `ccusage`. |
| **Codex / ChatGPT** | Newest `~/.codex/sessions/**/rollout-*.jsonl` `token_count.rate_limits` (primary=5h, secondary=week). Fresh **until reset**, not 15 minutes. | ChatGPT.app “usage remaining” is not a local file. Run Codex once so rate_limits exist. MOMO shows **used %** (`100 − remaining` when only remaining is present). |
| **Cursor** | `Library/Application Support/Cursor/usage-cache.json`, `~/.cursor/usage-cache.json` | Transcripts lack account %; need a usage-cache.json or say CLI/cache missing. |
| **Grok** | None supported today | Exact “no local cache / CLI missing” copy. |

### CLI commands (read-only, timeout off-main)

Documented probes in `ProviderCLIUsageProbe`:

```sh
# Preferred Claude helper when installed (writes/prints OAuth windows)
ccusage json

# Detected for messaging / next steps (not required to invent %)
which claude
which codex
which cursor
which grok
```

`LocalUsageArtifactReader.probeDetail(for:)` = local files first, then optional `ccusage json`. Connect honesty uses the same probe.

## P0 — Settings deep-link buttons

`SystemSettingsDeepLink`:

- **Open Microphone Settings** → `x-apple.systempreferences:…Privacy_Microphone`
- **Open Notifications Settings** → Notifications pane for MOMO bundle id
- Also Speech / FDA helpers

Used in Talk panel (mic off), onboarding Talk + Notifications steps, Settings → Notifications.

## P0 — Survive TCC quit/relaunch mid-onboarding

`PreferencesStore.saveOnboardingProgress` persists:

- `onboardingResumeStep.v1`
- `onboardingPartialAllowed.v1`
- `onboardingPendingProvider.v1`
- intents

Relaunch resumes the same step + partial allow-list (not empty TRACKR / Welcome from scratch). Cleared on Finish / Replay.

## P1 — Minute refresh that runs

- Timer tick every `min(60, interval)`; refresh when age ≥ prefs interval (1/5/10/30 min)
- Settings picker can change interval and calls `rescheduleRefreshTimer()`
- Usage tab shows **Updated …** from `ActivityMonitor.lastUpdated`

## Preserve

Live connect status UI, no MainActor hang, schema v6 migration, four tabs, Claude Code–style Usage layout, no WebKit scrape.

Mac verify:

```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```
