# MOMO Chat Context and Handoff

Updated: 2026-09-16 (Mac retest tip `02d1f59` → schema v5 + Claude Code–style Usage tab)

Branch `cursor/force-onboarding-momo-talk-0ef6` / PR https://github.com/Momo-Labz/Momo/pull/3

## P0 — Forced onboarding (schema v5)

**Root cause:** v4 could leave `trackingOnboardingComplete.v4` / `seen` true while allow-list was empty (or stale), so TRACKR opened with zero providers and no Welcome overlay.

**Fix:**
- Schema **v5** (`trackingOnboardingComplete.v5`); bump clears allow-list + all complete/seen flags (v2–v5)
- `needsTrackingOnboarding = !seen || allowedTrackingProviders.isEmpty`
- `markTrackingOnboardingSeen()` no-ops unless ≥1 allow-listed provider
- Finish / Skip Talk trial blocked when `allowed` is empty
- Continue still requires `DesktopConnectionVerifier` verified

### QA reset
```sh
defaults delete com.momolabz.barboy trackingOnboardingComplete.v5
defaults delete com.momolabz.barboy trackingOnboardingComplete.v4
defaults delete com.momolabz.barboy trackingOnboardingComplete.v3
defaults delete com.momolabz.barboy trackingOnboardingComplete.v2
defaults delete com.momolabz.barboy trackingOnboardingSeen.v1
defaults delete com.momolabz.barboy trackingOnboardingSchemaVersion.v1
defaults delete com.momolabz.barboy allowedTrackingProviders.v1
defaults delete com.momolabz.barboy voiceMicrophonePrompted.v1
defaults delete com.momolabz.barboy voiceSpeechPrompted.v1
```

## P0 — Usage tab (Claude Code `/usage` style)

- **Removed** TOP CHATS / activity rows from Usage (chats stay on Activity, max 3)
- Per provider: Session stats (cost / API+wall duration / lines / token breakdown) when present; Current session % bar; Current week % bar; “Resets …” caption; LOCAL ONLY disclaimer
- Strip still uses compact `DualUsageMeters` / `UsageMeter`

### Claude cache → UI mapping
| Local field | UI row |
|---|---|
| `rate_limits.five_hour.used_percentage` / `five_hour.utilization` | Current session % bar |
| `rate_limits.five_hour.resets_at` | Resets caption under session bar |
| `rate_limits.seven_day.used_percentage` / `seven_day.utilization` | Current week % bar |
| `rate_limits.seven_day.resets_at` | Resets caption under week bar |
| `cost.total_cost_usd` | Total cost |
| `cost.total_api_duration_ms` | Total duration (API) |
| `cost.total_duration_ms` | Total duration (wall) |
| `cost.total_lines_added/removed` | Total code changes |
| `context_window` / usage token keys | input / output / cache read / cache write |

Sources: `~/.claude/usage-cache.json` (+ siblings), Application Support/Claude, `/tmp/claude/statusline-usage-cache*.json`. Artifact freshness = 24h or until `resets_at` (not 15m transcript freshness).

Codex/Cursor: same layout shape; only fields that exist locally (Codex from transcript `rate_limits`; Cursor only if explicit usage-cache).

## Preserve
- Strip UsageMeter bars; four tabs; no WebKit; no Free pills; mic deadlock fix; safe Launch Services open

Mac verify:
```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```
