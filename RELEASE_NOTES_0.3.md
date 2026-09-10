# BAR BOY 0.3 — the return queue

This release reframes BAR BOY around the expensive part of parallel AI work: a person noticing, understanding, and answering every agent return.

## New

- `YOUR TURN` priority queue for questions, approvals, and failures.
- Session inspector with recorded model, MCP server, skill, and plugin provenance.
- Capability receipts in the Mac dashboard, local status API, and 3D-print display.
- Native iOS 17 companion target, **MOMO RELAY**.
- Local Mac-to-iPhone pairing with the secret stored in iOS Keychain.
- Foreground-detected iPhone notifications for new urgent returns.
- Provider access map separating local visibility, organization API usage, delegated OAuth, and unsupported consumer-account access.
- Nine passing macOS tests, including provenance extraction and privacy redaction.

## Deliberate limits

- The iPhone companion is local-network and read-only in 0.3. Background/remote alerts require an opt-in encrypted relay and APNs.
- OpenAI and Anthropic organization usage adapters are documented access paths, not connected until administrative credentials are supplied and the Keychain-backed fetchers ship.
- Personal ChatGPT, Claude, Cursor, Gemini, and Grok quotas are not scraped. Unsupported cells remain dashes.
- The development DMG is ad-hoc signed and not notarized.
