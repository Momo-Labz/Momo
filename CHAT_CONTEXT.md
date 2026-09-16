# MOMO Chat Context and Handoff

Updated: 2026-09-16 (Mac retest tip `31d180a`: Claude usage bars, safe launch, no pills, four tabs)

Branch `cursor/force-onboarding-momo-talk-0ef6` / PR https://github.com/Momo-Labz/Momo/pull/3

## Latest Mac retest fixes

### Claude / Cursor usage (honest local only)
- **Source:** `LocalUsageArtifactReader` — never invents %.
  - Claude: `~/.claude/usage-cache.json` (and siblings), `~/Library/Application Support/Claude/…`, `/tmp/claude/statusline-usage-cache*.json` (Claude Code statusline / OAuth cache shapes: `five_hour`/`seven_day` with `used_percentage` or `utilization`).
  - Also: Claude JSONL `rate_limits` when present (`ClaudeSessionAdapter`).
  - Cursor: only if an explicit local `usage-cache.json` exists (transcripts have no account %).
- Wired into `LocalActivityScanner` → `recordedQuota` / `recordedQuotas` → `DualUsageMeters` on strip + Usage tab.
- Empty meters stay `—` with guidance (FDA / missing cache), not fake fills.

### Safe desktop open (no “modifying apps”)
- `DesktopAppConnect` / `ProviderAccountOpen`: activate running app, else `NSWorkspace.openApplication(at:configuration:)` on the `.app` URL only.
- Never writes into Claude.app / Cursor.app / Application Scripts.
- “MOMO was prevented from modifying apps” was App Management TCC from unsafe bundle touch — Launch Services open avoids that path.
- **Permissions:** Full Disk Access is the least privilege for reading another app’s session roots when TCC blocks listing. App Management is not required for read-only Launch Services open; surface FDA guidance when session root exists but listing fails (`DesktopConnectionVerifier.privacyBlocked`). No Info.plist key prompts FDA/App Management (System Settings only).

### Nav
- Removed Free Codex|Claude segmented pills under the strip.
- Tabs: **Activity · Usage · Brain · Upgrade**.
- Usage tab = local 5HR/W meters + top-3 chats per provider (no WebKit Connect Usage).

### Connect verification
- Verified = installed + running + readable session **or** readable local usage artifact.
- Privacy-blocked → guidance + Open Privacy Settings deep-link; Retry until readable.

## P0 — Mic Allow freeze (fixed earlier)

**Root cause:** MainActor-awaited permission continuations resumed on main → deadlock after Allow.
**Fix:** resume off-main; engine start off MainActor; latched denied guidance.

## Preserve
- No Connect Usage / WebKit scrape
- Mic deadlock fix / latch
- Free ≤2 providers soft-lock (Upgrade for more)
- Top-3 chats per provider
- Compact 5HR+W when data exists
- Desktop `/Applications` connect; schema v4

## QA reset
```sh
defaults delete com.momolabz.barboy trackingOnboardingComplete.v4
defaults delete com.momolabz.barboy trackingOnboardingComplete.v3
defaults delete com.momolabz.barboy trackingOnboardingSeen.v1
defaults delete com.momolabz.barboy trackingOnboardingSchemaVersion.v1
defaults delete com.momolabz.barboy allowedTrackingProviders.v1
defaults delete com.momolabz.barboy voiceMicrophonePrompted.v1
defaults delete com.momolabz.barboy voiceSpeechPrompted.v1
```

Mac verify:
```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```
