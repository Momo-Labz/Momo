# Fixture provenance

- `momo-index-frames.json`: extracted from the inspected pure geometry/pose definitions in `../../../Branding/index.html`.
- `gemini-public-conversation.json` and `gemini-public-revisions.jsonl`: synthetic, non-account fixtures based on Google Gemini CLI's public `ConversationRecord` schema and JSONL loader. They are NOT captured local sessions. Prompt and tool-argument strings intentionally test false capability detection; revision and rewind records test accounting.

Sources inspected 2026-09-12:
- https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingTypes.ts
- https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingService.ts

Authorized sanitized local Gemini and Grok captures remain pending. Never add raw prompts, responses, personal paths, account identifiers, tool arguments/results, or credentials to captured fixtures.
