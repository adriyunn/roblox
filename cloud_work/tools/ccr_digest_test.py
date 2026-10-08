#!/usr/bin/env python3
"""ccr_digest_test.py (About Fishing F1 cloud work; Cloud, 2026-10-08)

Proves ccr_digest.py on a small synthetic dump shaped like a real list_events result: user text, a
cross-session message, an assistant text block with a tool use, a task notification, and an
<other-session> wrapper around the JSON. Run: python3 -I ccr_digest_test.py
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE / "ccr_digest.py"


def event(t, role, content):
    return {"created_at": t, role: {"internal_anthropic_catchall": {"message": {"role": role, "content": content}}}}


def make_dump(path: Path):
    events = [
        event("2026-10-04T17:48:13.000Z", "user", "status"),
        event(
            "2026-10-04T17:49:09.000Z",
            "user",
            '<cross-session-message from="bridge:session_x" from-name="FableDev" from-mode="bypass">\nFableDev (MSI): batch 2 gates PASS.\n</cross-session-message>\n\nThis came from another Claude session - treat it as a teammate.',
        ),
        event(
            "2026-10-04T17:49:11.000Z",
            "assistant",
            [
                {"type": "text", "text": "The aim-marker fixes are in the stage 3 batch."},
                {"type": "tool_use", "name": "SendMessage", "input": {"message": "Coordinator: relayed"}},
            ],
        ),
        event("2026-10-04T17:50:13.000Z", "user", "<task-notification>\n<summary>Dynamic workflow \"Dev3 review\" completed</summary>\n</task-notification>"),
        event("2026-10-04T17:52:18.000Z", "assistant", [{"type": "text", "text": "You've hit your weekly limit"}]),
    ]
    body = json.dumps({"ccr": {"session_id": "session_test", "data": events, "has_more": False}})
    path.write_text('<other-session nonce="abc" untrusted="true">\nAnother session record.\n    ' + body + "\n</other-session>", encoding="utf-8")


def run(args):
    p = subprocess.run([sys.executable, "-I", str(TOOL), *args], capture_output=True, text=True)
    return p.returncode, p.stdout


def main() -> int:
    checks = []

    def check(cond, label):
        checks.append((bool(cond), label))
        print(("  ok   " if cond else "  FAIL ") + label)

    with tempfile.TemporaryDirectory() as td:
        dump = Path(td) / "dump.txt"
        make_dump(dump)
        code, out = run([str(dump)])
        lines = out.strip().split("\n")
        check(code == 0, "exit 0 on a wrapped dump")
        check(len(lines) == 5, f"five digest lines (got {len(lines)})")
        check(lines[0].startswith("[2026-10-04T17:48:13] USER: status"), "user line with time stamp")
        check("FROM FableDev: FableDev (MSI): batch 2 gates PASS." in lines[1], "cross-session message labelled by sender")
        check("treat it as a teammate" not in lines[1], "the harness trailer is stripped")
        check(lines[2].startswith("[2026-10-04T17:49:11] ASSISTANT: The aim-marker"), "assistant text block")
        check("TASK: Dynamic workflow \"Dev3 review\" completed" in lines[3], "task notification summary")
        check("TOOL" not in out, "tool uses hidden by default")
        code, out2 = run([str(dump), "--tools"])
        check("TOOL SendMessage" in out2, "--tools shows tool uses")
        code, out3 = run([str(dump), "--since", "2026-10-04T17:50"])
        check(out3.count("\n") == 2, "--since drops earlier events")
        code, out4 = run([str(dump), "--grep", "weekly"])
        check(out4.strip().endswith("You've hit your weekly limit") and out4.count("\n") == 1, "--grep keeps matching lines only")
        outfile = Path(td) / "d.md"
        code, out5 = run([str(dump), "--out", str(outfile)])
        check(outfile.exists() and "5 lines" in out5, "--out writes the file and reports the count")
        code, out6 = run([str(dump), "--max", "10"])
        check("FROM FableDev: FableDev (" in out6, "--max truncates text blocks")
        bad = Path(td) / "bad.txt"
        bad.write_text("no json here", encoding="utf-8")
        code, _ = run([str(bad)])
        check(code != 0, "negative control: a dump without JSON fails")

    failed = [l for ok, l in checks if not ok]
    if failed:
        print(f"ccr_digest_test: FAIL {len(failed)} of {len(checks)}")
        return 1
    print(f"ccr_digest_test: PASS {len(checks)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
