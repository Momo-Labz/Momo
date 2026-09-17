# MOMO Chat Context and Handoff

Updated: 2026-09-16 (schema v7 forces Welcome again + usage/CLI + Settings deep-links + TCC resume)

Branch `cursor/usage-cli-onboarding-resume-02e3` / PR #6 off `main` after PR #5 (`6d816e9`).

## P0 — Connected honesty (usage meters only)

**Connected** requires readable usage % meters (cache / CLI / rate_limits). Opening the desktop app or finding a session file alone is **Not ready** / Searching… — never “Connected — no readable usage %”. Allow stays disabled until meters exist. Same rule for Claude, Codex/ChatGPT, Cursor, Grok.

## P0 — Mic false-off

Do not treat `undetermined` + prompted latch as denied. Prefer `AVCaptureDevice` (matches System Settings) and accept `AVAudioApplication` when granted. Open Microphone Settings remains for real denied/restricted.

## P0 — Onboarding skip regression (schema v7)

**Cause:** PR #5 wrote `trackingOnboardingSchemaVersion=6` + `onboardingMigration.v6=true`. A broken/skipped grok9–10 run could also leave `trackingOnboardingComplete.v6` + a non-empty allow-list. This branch’s gate treated that as finished (`needsTrackingOnboarding == false`) and opened the main UI with no Welcome.

**Fix:** Schema **v7** + one-time `onboardingMigration.v7` clears allow-list, completion flags (v2…v7), and stale resume keys, then forces Welcome → intents → connect. No Terminal `defaults delete`.

**Resume preserved:** After v7 is applied, genuine mid-flow TCC checkpoints (`onboardingResumeStep.v1` while `trackingOnboardingSeen == false`) still restore the unfinished step — never used to skip a forced Welcome upgrade.

Settings → **Replay onboarding** remains the retest path.

## P0 — Usage sources that match the apps (no invented %)

MOMO never scrapes WebKit / cookies and never invents percentages. Empty providers always show a **specific reason**.

| Provider | Readable sources (priority order) | Honest empty reason |
|---|---|---|
| **Claude** | `~/.claude/usage-limits.json` (ccusage), `usage-cache.json` / statusline caches, `Library/Application Support/Claude(-3p)/`, `/tmp/claude/statusline-*`, then optional `ccusage json` CLI | Claude.app menu % is live from Anthropic — not a plaintext local file. Install/sign in Claude Code or run `ccusage`. |
| **Codex / ChatGPT** | Newest `~/.codex/sessions/**/rollout-*.jsonl` `token_count.rate_limits` (primary=5h, secondary=week). Fresh **until reset**, not 15 minutes. | ChatGPT.app “usage remaining” is not a local file. Run Codex once so rate_limits exist. MOMO shows **used %** (`100 − remaining` when only remaining is present). |
| **Cursor** | `Library/Application Support/Cursor/usage-cache.json`, `~/.cursor/usage-cache.json` | Transcripts lack account %; need a usage-cache.json or say CLI/cache missing. |
| **Grok** | None supported today | Exact “no local cache / CLI missing” copy. |

### CLI commands (read-only, timeout off-main)

```sh
ccusage json
which claude
which codex
which cursor
which grok
```

## P0 — Settings deep-link buttons

`SystemSettingsDeepLink`: Microphone, Notifications (MOMO bundle), Speech, FDA.

## P0 — Survive TCC quit/relaunch mid-onboarding

Checkpoint: step + partial allow-list + pending provider. Cleared on Finish / Replay / schema upgrade wipe.

## P1 — Minute refresh

Honors 1/5/10/30 min prefs; Usage tab shows last-updated.

Mac verify:

```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Manual: upgrade from grok10/PR#5 install (even with prior complete flags) → Welcome without `defaults delete`; mid-flow Allow that relaunches → same unfinished step; Finish once → next launch stays on main UI.
