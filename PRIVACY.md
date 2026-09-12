# Privacy

MOMO is local-first.

- It inspects running process command lines only for providers you enable.
- It reads recent local session metadata and capability inventory only for enabled Codex, Claude, Gemini, Cursor, and Grok adapters.
- It does not upload prompts, source code, session text, or usage data.
- It does not include analytics or advertising SDKs.
- Disabling a provider stops its process and file inspection and excludes it from Desk Display and MOMO RELAY status payloads.

The Support Us and provider Usage buttons open external websites in the default browser only when clicked.

Desk Display is disabled by default. When enabled, MOMO starts a read-only HTTP listener for the local display, protects status routes with a random pairing credential, and can redact session/project titles. The connection is local-network HTTP, so use it only on a trusted network; a future hardware release should add mutually authenticated encryption.

MOMO RELAY stores the paired status URL and its local credential in the iPhone Keychain. It makes read-only requests to the Mac while active. MOMO has no cloud relay, analytics, or background push service. Provider-account passwords, browser cookies, and consumer session tokens are never requested.
