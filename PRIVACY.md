# Privacy

BAR BOY is local-first.

- It reads running process command lines to identify supported local AI tools.
- It reads recent local session metadata for enabled Codex, Claude, Gemini, Cursor, and Grok adapters.
- It does not upload prompts, source code, session text, or usage data.
- It does not include analytics or advertising SDKs.
- Provider folders can be disabled individually in Settings.

The Support Us and provider Usage buttons open external websites in the default browser only when clicked.

Desk Display is disabled by default. When enabled, BAR BOY starts a read-only HTTP listener on port 7377 for the local display, protects status routes with a random pairing token, and can redact session/project titles. The connection is local-network HTTP, so use it only on a trusted network; a future hardware release should add mutually authenticated encryption.
