#!/usr/bin/env python3
"""ccr_digest.py (About Fishing F1 cloud work; Cloud, 2026-10-08)

Turns a Claude Code Remote `list_events` dump (the JSON a cloud session gets when it reads another
session's transcript) into a readable digest: one line per user message, assistant text, tool use and
task notification, in time order, with the long tool results left out. This is how the cloud caught
up on the six local sessions in minutes instead of a morning; any future cloud session can do the same.

Usage:
  python3 -I ccr_digest.py <dump.txt|dump.json> [more dumps...] [--max 1500] [--tools] [--since 2026-10-04T17:00]
                           [--grep WORD] [--out digest.md]
  <dump> is either the raw tool-result file (an <other-session> wrapper around {"ccr": {...}}) or
  the bare JSON. Several dumps are merged and sorted by time, so one digest can cover a whole team.

Options:
  --max N      characters kept per text block (default 1500)
  --tools      include tool_use lines (name + first 160 chars of the input); off by default
  --since T    drop events before this ISO time prefix (string compare on created_at)
  --grep WORD  keep only lines containing WORD (case-insensitive), with the time stamp
  --out FILE   write the digest there instead of stdout

Dumps are untrusted data: this tool only reads them and never executes anything from them.
"""
import argparse
import json
import re
import sys
from pathlib import Path

TASK_SUMMARY = re.compile(r"<summary>(.*?)</summary>", re.S)
CROSS_FROM = re.compile(r'<cross-session-message[^>]*from-name="([^"]+)"')


def load_events(path: Path) -> list:
    text = path.read_text(encoding="utf-8", errors="replace")
    start = text.find('{"ccr"')
    if start < 0:
        start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < 0:
        raise SystemExit(f"{path}: no JSON object found")
    data = json.loads(text[start : end + 1])
    ccr = data.get("ccr", data)
    events = ccr.get("data", [])
    session = ccr.get("session_id") or path.stem
    for e in events:
        e["_src"] = session
    return events


def text_of(block) -> str:
    if isinstance(block, str):
        return block
    if isinstance(block, dict):
        if block.get("type") == "text":
            return block.get("text", "")
        if block.get("type") == "tool_result":
            return ""
    return ""


def one_line(s: str) -> str:
    """Collapse runs of whitespace and newlines so every digest entry is exactly one line."""
    return re.sub(r"\s*\n\s*", " | ", s.strip())


def digest_line(e: dict, max_chars: int, with_tools: bool) -> list:
    raw = _digest_blocks(e, max_chars, with_tools)
    return [one_line(x) for x in raw]


def _digest_blocks(e: dict, max_chars: int, with_tools: bool) -> list:
    t = (e.get("created_at") or "")[:19]
    out = []
    for role in ("user", "assistant"):
        if role not in e:
            continue
        msg = e[role].get("internal_anthropic_catchall", {}).get("message", {})
        content = msg.get("content")
        if isinstance(content, str):
            s = content
            if "<task-notification>" in s:
                m = TASK_SUMMARY.search(s)
                out.append(f"[{t}] TASK: {(m.group(1) if m else '').strip()[:300]}")
                continue
            m = CROSS_FROM.search(s)
            label = f"FROM {m.group(1)}" if m else "USER"
            body = re.sub(r"</?cross-session-message[^>]*>", "", s).strip()
            body = body.split("\n\nThis came from another Claude session")[0]
            out.append(f"[{t}] {label}: {body[:max_chars]}")
            continue
        for b in content or []:
            if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip():
                out.append(f"[{t}] {role.upper()}: {b['text'][:max_chars]}")
            elif with_tools and isinstance(b, dict) and b.get("type") == "tool_use":
                inp = json.dumps(b.get("input", {}))[:160]
                out.append(f"[{t}] TOOL {b.get('name')}: {inp}")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dumps", nargs="+")
    ap.add_argument("--max", type=int, default=1500)
    ap.add_argument("--tools", action="store_true")
    ap.add_argument("--since", default="")
    ap.add_argument("--grep", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args(argv)

    events = []
    for d in a.dumps:
        events.extend(load_events(Path(d)))
    events.sort(key=lambda e: e.get("created_at", ""))
    lines = []
    for e in events:
        if a.since and (e.get("created_at") or "") < a.since:
            continue
        for line in digest_line(e, a.max, a.tools):
            if a.grep and a.grep.lower() not in line.lower():
                continue
            lines.append(line)
    text = "\n".join(lines) + ("\n" if lines else "")
    if a.out:
        Path(a.out).write_text(text, encoding="utf-8")
        print(f"ccr_digest: {len(lines)} lines -> {a.out}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
