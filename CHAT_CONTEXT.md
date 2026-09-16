# MOMO Chat Context and Handoff

Updated: 2026-09-16 (desktop-app pivot — Connect Usage removed, schema v3, Upgrade tab)

This file records the product direction, implementation decisions, verification, and remaining work from the MOMO conversation so the next session can continue without reconstructing the history.

## September 16 — Desktop-app pivot (PR #3)

Branch `cursor/force-onboarding-momo-talk-0ef6` / PR https://github.com/Momo-Labz/Momo/pull/3

### Product change
- **Removed Connect Usage WebKit** (`UsageCaptureView` / `UsageCaptureService` deleted). No Preview/Confirm scrape.
- **Desktop-app connection:** onboarding + Settings open apps from `/Applications` (ChatGPT/Codex, Claude, Cursor, Grok, Gemini when present). Local process + session monitoring supplies LIVE / usage when known; missing values stay `—`.
- **Onboarding UX:** providers start **empty**; each click opens the desktop app + local permission; strip fills only after Allow. Free ≤ **2** providers; MOMO+ unlocks more.
- **Tabs:** Activity / Brain / **Upgrade** (Usage tab removed). Upgrade soft-locks: unlimited Talk, >2 providers, analytics (`momoPlusEntitled.v1`).
- **Strip layout:** padding inside card width (no overlap); usage % shown on cards when desktop/local observations exist.
- **Mic:** prompt latched per install (`voiceMicrophonePrompted.v1` / `voiceSpeechPrompted.v1`); never re-request after first dialog.

### Onboarding schema v3
- `trackingOnboardingSchemaVersion.v1` = **3**
- Completion: `trackingOnboardingComplete.v3`
- Schema < 3 → force re-run and **clear** allow-list

**QA reset:**
```sh
defaults delete com.momolabz.barboy trackingOnboardingComplete.v3
defaults delete com.momolabz.barboy trackingOnboardingComplete.v2
defaults delete com.momolabz.barboy trackingOnboardingSeen.v1
defaults delete com.momolabz.barboy trackingOnboardingSchemaVersion.v1
defaults delete com.momolabz.barboy allowedTrackingProviders.v1
defaults delete com.momolabz.barboy onboardingIntents.v1
defaults delete com.momolabz.barboy authorizedLocalProviders.v1
defaults delete com.momolabz.barboy voiceMicrophonePrompted.v1
defaults delete com.momolabz.barboy voiceSpeechPrompted.v1
defaults delete com.momolabz.barboy momoPlusEntitled.v1
defaults delete com.momolabz.barboy talkOnboardingUsed.v1
defaults delete com.momolabz.barboy talkFreeUsesConsumed.v1
```

### Key types
- `DesktopAppCatalog` / `DesktopAppConnect` — locate & open desktop apps
- `PreferencesStore.connectDesktopProvider` — allow-list + enable local scan; Free soft-lock
- `TalkQuotaStore.UpsellCopy` — Plus framing (Talk / providers / analytics)

Mac verify:
```sh
xcodebuild -project BarBoy.xcodeproj -scheme BarBoy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

## Prior notes (still relevant)

- Talk Free = 1 onboarding trial + 3 uses; soft Plus via `momoPlusEntitled.v1` (no StoreKit)
- Header mic + Talk shortcut; silence → think → respond via `TalkSessionCoordinator`
- Menu bar states: idle / listening / thinking / speaking
- Local-first: never invent quotas; never import browser cookies

## Working constraints

- Do not reintroduce WebKit Connect Usage.
- Do not invent provider quotas or fake live sync labels.
- Soft locks only for MOMO+.
- Keep MainActor default-arg compile rules clean.
