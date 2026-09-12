#!/usr/bin/env python3
"""Capture one explicitly authorized Gemini or Grok session folder safely.

The output keeps schema fields needed by MOMO's adapters while removing prompts,
responses, tool arguments/results, paths, credentials, and account identifiers.
Review the generated files before adding them to Tests/Fixtures/captured/.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DROP_KEYS = {
    "prompt", "text", "content", "args", "input", "output", "response",
    "result", "tool_arguments", "tool_result", "command", "transcript",
    "credentials", "password", "cookie", "secret", "token",
}
PATH_KEYS = {"cwd", "path", "project", "project_path", "directory", "file"}
IDENTITY_KEYS = {"session_id", "sessionId", "conversation_id", "conversationId", "account_id", "accountId"}
TITLE_KEYS = {"title", "generated_title", "session_summary", "summary"}


def stable_id(value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8", "ignore")).hexdigest()[:10]
    return f"fixture-{digest}"


def sanitize(key: str, value: Any) -> Any:
    lowered = key.lower()
    if lowered in DROP_KEYS or any(term in lowered for term in ("password", "cookie", "credential", "secret")):
        return None
    if key in PATH_KEYS or lowered.endswith("_path"):
        return "/private/tmp/momo-fixture-project"
    if key in IDENTITY_KEYS:
        return stable_id(str(value))
    if key in TITLE_KEYS:
        return "Sanitized provider session"
    if isinstance(value, dict):
        return {k: cleaned for k, v in value.items() if (cleaned := sanitize(k, v)) is not None}
    if isinstance(value, list):
        return [cleaned for item in value if (cleaned := sanitize(key, item)) is not None]
    return value


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return sanitize(path.name, value)


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def capture_gemini(root: Path, output: Path) -> int:
    files = sorted(
        (p for p in root.rglob("*") if p.suffix in {".json", ".jsonl"} and p.is_file()),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )[:20]
    count = 0
    for index, source in enumerate(files, 1):
        target = output / f"gemini-session-{index:02d}{source.suffix}"
        if source.suffix == ".jsonl":
            lines = []
            for line in source.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    item = sanitize("record", json.loads(line))
                except json.JSONDecodeError:
                    continue
                if item is not None:
                    lines.append(json.dumps(item, sort_keys=True))
            target.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
        else:
            item = read_json(source)
            if item is None:
                continue
            write_json(target, item)
        count += 1
    return count


def capture_grok(root: Path, output: Path) -> int:
    sessions = sorted(
        (p.parent for p in root.rglob("updates.jsonl") if p.is_file()),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )[:20]
    count = 0
    for index, session in enumerate(sessions, 1):
        target = output / f"grok-session-{index:02d}"
        target.mkdir(parents=True, exist_ok=True)
        summary = read_json(session / "summary.json") if (session / "summary.json").exists() else {}
        write_json(target / "summary.json", summary or {"info": {"session_id": f"fixture-{index}"}})
        lines = []
        for line in (session / "updates.jsonl").read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                item = sanitize("record", json.loads(line))
            except json.JSONDecodeError:
                continue
            if item is not None:
                lines.append(json.dumps(item, sort_keys=True))
        (target / "updates.jsonl").write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("provider", choices=("gemini", "grok"))
    parser.add_argument("root", type=Path, help="one account's already-authorized local session folder")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--account-label", required=True, help="non-identifying label such as account-1")
    parser.add_argument("--confirm-authorization", action="store_true", help="confirm this folder was authorized in MOMO")
    args = parser.parse_args()
    if not args.confirm_authorization:
        parser.error("pass --confirm-authorization after approving this exact folder in MOMO")
    if not args.root.is_dir():
        parser.error(f"session folder does not exist: {args.root}")
    args.output.mkdir(parents=True, exist_ok=True)
    count = capture_gemini(args.root, args.output) if args.provider == "gemini" else capture_grok(args.root, args.output)
    write_json(args.output / "capture-manifest.json", {
        "provider": args.provider,
        "accountLabel": args.account_label,
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "sessionCount": count,
        "redacted": True,
        "sourcePathRecorded": False,
    })
    print(f"Captured {count} sanitized {args.provider} session(s) into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
