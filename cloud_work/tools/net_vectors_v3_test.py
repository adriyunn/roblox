#!/usr/bin/env python3
"""net_vectors_v3_test.py (About Fishing F1 cloud work, WS-N net v3; Cloud, 2026-10-07)

Proves tools/net_vectors_v3.py through subprocess, the way the gate runs it: --selftest passes (and
shows a flipped byte, a changed reason and a missing message are caught); generation into a temp folder
is deterministic and byte-identical to the committed tests/fixtures/net_vectors_v3.{json,_data.luau}
(so the committed vectors are current); every message has at least 4 vectors with 3 valid and 1 invalid;
each valid vector's first byte is its message id, unique and in 32..63; --check exits 0 on the committed
file and 1 on a copy with one flipped byte (negative control); the Luau data module compiles when a
luau-compile binary is on PATH. Run from tools/: python3 -I net_vectors_v3_test.py
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
FIXTURES = ROOT / "tests" / "fixtures"
TOOL = HERE / "net_vectors_v3.py"
JSON_NAME, LUAU_NAME = "net_vectors_v3.json", "net_vectors_v3_data.luau"
MESSAGE_NAMES = ["TackleMove", "TackleDrop", "Sell", "BuyGear", "Equip", "SetOption", "TackleMoveResult", "TackleSync",
                 "SellResult", "BuyResult", "CatchLogSync", "WorldSync", "ProfileReady"]

checks: list[str] = []
fails: list[str] = []


def check(cond, label: str) -> bool:
    checks.append(label)
    if not cond:
        fails.append(label)
    print(f"  {'ok  ' if cond else 'FAIL'} {len(checks):<4} {label}")
    return bool(cond)


def tool(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", str(TOOL), *args], capture_output=True, text=True)


def main() -> int:
    # 1. the tool's own selftest
    proc = tool("--selftest")
    check(proc.returncode == 0, "--selftest exits 0")
    check("selftest: PASS" in proc.stdout, "--selftest prints selftest: PASS")
    check("flipped byte" in proc.stdout and "changed rejection reason" in proc.stdout and "no vectors is caught" in proc.stdout,
          "--selftest proves a flipped byte, a changed reason and a missing message are caught")

    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        # 2. generation: deterministic, and the committed fixtures are current
        gen1 = tool("--out", str(d / "a"))
        check(gen1.returncode == 0 and "wrote" in gen1.stdout, "generation into a temp folder exits 0")
        gen2 = tool("--out", str(d / "b"))
        check(gen2.returncode == 0, "a second generation exits 0")
        ja, jb = d / "a" / JSON_NAME, d / "b" / JSON_NAME
        la, lb = d / "a" / LUAU_NAME, d / "b" / LUAU_NAME
        check(ja.is_file() and la.is_file(), "both files are written (JSON and the Luau data module)")
        check(ja.read_bytes() == jb.read_bytes() and la.read_bytes() == lb.read_bytes(), "two generations are byte-identical (deterministic)")
        committed_json, committed_luau = FIXTURES / JSON_NAME, FIXTURES / LUAU_NAME
        check(committed_json.is_file() and committed_luau.is_file(), "the committed fixtures exist (run the generator once)")
        if committed_json.is_file() and committed_luau.is_file():
            check(committed_json.read_bytes() == ja.read_bytes(), "committed JSON equals a fresh generation (current)")
            check(committed_luau.read_bytes() == la.read_bytes(), "committed Luau data module equals a fresh generation (current)")
        for p in (ja, la):
            data = p.read_bytes()
            check(b"\r" not in data and data.endswith(b"\n") and not data.startswith(b"\xef\xbb\xbf"), f"{p.name} is LF with a final newline and no BOM")

        # 3. the vectors' shape and coverage
        vectors = json.loads(ja.read_text(encoding="utf-8"))
        check(isinstance(vectors, list) and len(vectors) >= 4 * len(MESSAGE_NAMES) + 1, f"at least 4 vectors per message plus the unknown-message one ({len(vectors)} total)")
        per = {n: [v for v in vectors if v["name"] == n] for n in MESSAGE_NAMES}
        check(all(len(vs) >= 4 and sum(v["valid"] for v in vs) >= 3 and any(not v["valid"] for v in vs) for vs in per.values()),
              "every message has >= 4 vectors, >= 3 valid and >= 1 invalid")
        check(all(set(v) == {"name", "payload", "valid", "hex"} for v in vectors if v["valid"]), "valid vectors carry exactly name, payload, valid, hex")
        check(all(set(v) == {"name", "payload", "valid", "hex", "reason"} and v["hex"] == "" for v in vectors if not v["valid"]),
              "invalid vectors carry a reason and no hex")
        hexes = [v["hex"] for v in vectors if v["valid"]]
        check(all(len(h) % 2 == 0 and len(h) >= 2 and h == h.lower() and all(c in "0123456789abcdef" for c in h) for h in hexes), "hex is lower-case, even length, non-empty")
        ids = {}
        for v in vectors:
            if v["valid"]:
                ids.setdefault(v["name"], set()).add(int(v["hex"][:2], 16))
        check(all(len(s) == 1 for s in ids.values()), "every message's valid vectors share one first byte (the id)")
        flat = sorted(next(iter(s)) for s in ids.values())
        check(len(flat) == len(set(flat)) and all(32 <= i <= 63 for i in flat), f"ids unique and in 32..63: {flat}")
        c2s = {"TackleMove", "TackleDrop", "Sell", "BuyGear", "Equip", "SetOption"}
        check(all((next(iter(ids[n])) <= 47) == (n in c2s) for n in ids), "C2S ids are 32..47 and S2C ids 48..63")
        kinds = {v["reason"].split(":")[-1].strip().split(" ")[0] for v in vectors if not v["valid"]}
        check({"expected", "out", "too", "not", "bad", "missing", "unexpected", "unknown", "payload"} <= kinds, f"invalid vectors cover every reason kind ({sorted(kinds)})")
        unknown = [v for v in vectors if v["name"] not in MESSAGE_NAMES]
        check(len(unknown) == 1 and unknown[0]["reason"] == "unknown message", "one vector names a message that does not exist")

        # 4. --check on the committed file, and the negative control
        chk = tool("--check")
        check(chk.returncode == 0 and "--check: OK" in chk.stdout, "--check on the committed fixtures exits 0")
        chk_tmp = tool("--check", str(ja))
        check(chk_tmp.returncode == 0, "--check on the temp copy exits 0")
        first_valid = next(i for i, v in enumerate(vectors) if v["valid"])
        flipped = json.loads(json.dumps(vectors))
        h = flipped[first_valid]["hex"]
        flipped[first_valid]["hex"] = h[:-2] + f"{int(h[-2:], 16) ^ 0x01:02x}"
        neg_dir = d / "neg"
        neg_dir.mkdir()
        (neg_dir / JSON_NAME).write_text(json.dumps(flipped, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        neg = tool("--check", str(neg_dir / JSON_NAME))
        check(neg.returncode == 1 and "hex drift" in neg.stdout and vectors[first_valid]["name"] in neg.stdout,
              "negative control: one flipped byte makes --check exit 1 and name the vector")
        stale_dir = d / "stale"
        shutil.copytree(d / "a", stale_dir)
        (stale_dir / LUAU_NAME).write_bytes((stale_dir / LUAU_NAME).read_bytes().replace(b"V[1] = ", b"V[1] = -- stale\n"))
        stale = tool("--check", str(stale_dir / JSON_NAME))
        check(stale.returncode == 1 and "not the Luau form" in stale.stdout, "a Luau data module out of step with the JSON fails --check")

        # 5. the Luau data module compiles (when the CLI is here)
        luau_compile = shutil.which(os.environ.get("LUAU_COMPILE", "luau-compile"))
        if luau_compile is None:
            print("  note: no luau-compile on PATH; the gate's compile step covers the data module")
        else:
            comp = subprocess.run([luau_compile, "--null", "-O2", str(la)], capture_output=True, text=True)
            check(comp.returncode == 0, "the Luau data module compiles with luau-compile --null -O2")

    if fails:
        print(f"net_vectors_v3_test: FAIL {len(fails)} of {len(checks)}")
        for f in fails:
            print("   - " + f)
        return 1
    print(f"net_vectors_v3_test: PASS {len(checks)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
