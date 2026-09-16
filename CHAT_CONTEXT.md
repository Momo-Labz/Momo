# MOMO Chat Context and Handoff

Updated: 2026-09-16 (connect hang fix + schema v6 + Claude usage honesty)

Branch `cursor/connect-status-migration-3a53` off `main` after PR #3 squash `32ec350`.

## P0 — Never freeze during connect (root cause)

**Verified hang:** Onboarding `beginVerification` ran on MainActor and:

1. Called `DesktopAppConnect.openViaLaunchServices`, which **`DispatchSemaphore.wait`’d up to 2.5s** while `NSWorkspace.openApplication` completions hop to the main thread → classic MainActor deadlock / multi-second freeze (same class as the mic permission continuation hang).
2. Then called `DesktopConnectionVerifier.verify` on MainActor (`ps waitUntilExit` + up to 2 000-file session walk + Claude cache reads).

**Fix:**
- Launch Services open is fire-and-forget / async — **never semaphore-wait on MainActor**
- Verify + Claude cache / FDA checks run in `Task.detached`; UI updates via MainActor progress callbacks only
- Live status UI: Opening app → Waiting for sign-in → Reading local usage → Connected / Needs permission / Failed / Timed out + Retry
- Spinners while in-flight; debounce repeat clicks; 20s hard timeout with Retry recovery
- Usage tab Claude artifact load also off-main (`.task` + ProgressView)

Mic path already avoided MainActor continuation resume (`VoicePermission`); connect no longer shares the blocking pattern.

## P0 — Claude connect + data honesty

On verified connect, surface `ConnectUsageHonesty` (never invent %):

| Outcome | UI |
|---|---|
| Usage found | Connected + Session N% / Week N% from real cache |
| No readable cache | Connected — honest empty + `~/.claude` / `/tmp/claude` next steps |
| Privacy blocked | Needs permission + FDA / App Management guidance |

Parses existing statusline + usage-cache paths only (`LocalUsageArtifactReader`).

## P0 — No manual `defaults delete` for shipping QA

Schema **v6** (`trackingOnboardingComplete.v6`) + one-time `onboardingMigration.v6`:

- Upgrade from prior main/grok (schema &lt; 6 or missing migration flag) clears allow-list + complete/seen and forces Welcome→connect
- Empty allow-list never counts as finished
- **Settings → Replay onboarding** remains the supported retest path

### Optional advanced reset (not primary)

Only if Replay is unavailable:

```sh
defaults delete com.momolabz.barboy
```

Do not document per-key `defaults delete` as the normal QA wipe.

## Preserve

Desktop-app connect, Claude Code–style Usage tab (no Activity clone), four tabs, no WebKit Connect Usage, mic latch, safe Launch Services open.

Mac verify:

```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Manual: upgrade install → Welcome without Terminal; connect Claude → status stages + found/missing/blocked; Retry after timeout; Replay onboarding; Usage tab spinner then honest empty or %.
