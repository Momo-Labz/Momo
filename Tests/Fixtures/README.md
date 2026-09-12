# Fixture provenance

- `momo-index-frames.json`: extracted from the inspected pure geometry/pose definitions in `../../../Branding/index.html`.
- `gemini-public-conversation.json` and `gemini-public-revisions.jsonl`: synthetic, non-account fixtures based on Google Gemini CLI's public `ConversationRecord` schema and JSONL loader. They are NOT captured local sessions. Prompt and tool-argument strings intentionally test false capability detection; revision and rewind records test accounting.
- `grok-session/summary.json` and `grok-session/updates.jsonl`: synthetic, non-account fixtures based on Grok Build's documented local session layout. They exercise the `summary.json` metadata plus ACP `updates.jsonl` init/result records. They are NOT captured local sessions.

Sources inspected 2026-09-12:
- https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingTypes.ts
- https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingService.ts

Authorized sanitized local Gemini and Grok captures remain pending. Never add raw prompts, responses, personal paths, account identifiers, tool arguments/results, or credentials to captured fixtures. Grok's documented schema reference is https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/17-sessions.md and https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/14-headless-mode.md.

## Authorized capture workflow

MOMO asks for one local account folder at a time in Settings → Access. After approving that exact folder, create a reviewable sanitized capture with:

```sh
python3 Scripts/capture_sanitized_fixture.py gemini /path/to/one-account-session-folder \
  --output Tests/Fixtures/captured/gemini/account-1 \
  --account-label account-1 --confirm-authorization
```

Use `grok` and a Grok session folder for the other provider. The script records only schema fields needed by the adapters, removes prompts, responses, paths, credentials, tool arguments/results, and account identifiers, and writes a manifest without the source path. Review the generated files before committing them.
