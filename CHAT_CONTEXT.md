# MOMO Chat Context and Handoff

Updated: 2026-09-16 (P0 mic deadlock fix + UX pass: 5HR/W bars, top-3 chats, verified connect, Free switcher)

Branch `cursor/force-onboarding-momo-talk-0ef6` / PR https://github.com/Momo-Labz/Momo/pull/3

## P0 — Mic Allow freeze (fixed)

**Root cause:** `VoiceInput.start()` is `@MainActor` and awaited `AVAudioApplication.requestRecordPermission` / `SFSpeechRecognizer.requestAuthorization` via `withCheckedContinuation`. Those APIs often invoke completions on the **main thread**. Resuming the MainActor-awaited continuation from that main-thread callback deadlocks the UI after Allow.

**Fix (`VoicePermission` / `VoiceInput`):**
- Always resume permission continuations on a background queue (`resumeOffMain`)
- Move `AVAudioEngine` install/start off MainActor
- Explicit states: `permission` → `starting` → `listening` / `unavailable`
- 20s start timeout; debounce while `isPendingStart`
- Mic then speech sequenced with status copy; denied still latched guidance-only

## UX pass

### Compact 5HR + W + MOMO3 bars
- Shared `UsageMeter` (continuous amber/coral track from MOMO3 `CompactProviderCell`)
- `DualUsageMeters` on provider strip cards (compact + expanded)
- Usage peek labels `5HR` / `W`; unknown stays `—`
- `UsagePeekMapping` also reads recorded quota windows by minutes

### Top 3 chats / provider
- `SessionPresentation.topChatsPerProvider` (limit 3) used by Activity listing

### Verified desktop onboarding (schema v4)
- `DesktopConnectionVerifier`: installed + running + **readable local session file** (not process-only)
- Pending → guidance + Retry / Back; Continue disabled until ≥1 verified
- Free still ≤2 verified providers
- Completion key: `trackingOnboardingComplete.v4`

### Free provider switcher
- Segmented icon+name pills under strip when ≤2 connected (or Free plan)
- One-click sets `selectedProvider` and filters Activity

## Honest limitation
Third-party “logged in” cannot be proven via account APIs without cookies/credentials. Verification = app installed + running + at least one readable local session artifact under that provider’s session roots. Mid sign-in (app open, no session files yet) surfaces **awaitingSignIn** / “Finish signing in… Retry”.

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

## Preserve
- No Connect Usage / WebKit
- Desktop `/Applications` connect
- Upgrade tab soft Plus (Talk / >2 providers / analytics framing)
- Local-first; never invent %

Mac verify:
```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```
