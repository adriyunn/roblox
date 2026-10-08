#!/usr/bin/env python3
"""mutate_test.py (About Fishing F1 cloud work; Cloud, 2026-10-08)

Proves tools/mutate.py: the tokenizer leaves comments and strings alone, each operator makes the mutant
it promises (and skips what it must: the index 1 in t[1], the module's own `return M`), --quick --module
WorldClock on the real tree kills more mutants than it lets through and writes that to the JSON, a
module nobody has matches exit 2, and the negative control: a copy of the tree whose
worldclock_test.luau is an always-pass stub must show survival 1.0 and exit 1.
Run from tools/: python3 -I mutate_test.py
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MUTATE = HERE / "mutate.py"
sys.path.insert(0, str(HERE))
import mutate  # noqa: E402  (the module under test, next to this file)

checks: list[str] = []
fails: list[str] = []


def check(cond, label: str) -> bool:
    checks.append(label)
    if not cond:
        fails.append(label)
    print(f"  {'ok  ' if cond else 'FAIL'} {len(checks):<4} {label}")
    return bool(cond)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", str(MUTATE), *args], capture_output=True, text=True)


def main() -> int:
    # the tokenizer and the operators on a small source
    src = (
        "--!strict\n"
        "-- a < b in a comment, and 42 too\n"
        "local S = \"x < y and 7\"\n"
        "local function f(a, b, t)\n"
        "\tif a < b and b == 1 then\n"
        "\t\treturn a + 2.5\n"
        "\tend\n"
        "\treturn t[1]\n"
        "end\n"
        "return f\n"
    )
    toks = mutate.tokenize(src)
    check([t.kind for t in toks if t.kind in ("comment", "string")] == ["comment", "comment", "string"], "tokenize: two comments and one string, nothing inside them mutable")
    ms = mutate.mutants_for(src)
    by_op = {op: [m for m in ms if m.op == op] for op in mutate.OPERATORS}
    check(sorted(m.replacement for m in by_op["compare"]) == ["<=", "~="], "compare: < -> <= and == -> ~= (none from the comment or the string)")
    check([m.replacement for m in by_op["logic"]] == ["or"], "logic: the one `and` becomes `or`")
    check(sorted(m.replacement for m in by_op["number"]) == ["2", "3.75"], "number: 1 -> 2, 2.5 -> 3.75; the index in t[1] and the 42 in the comment are skipped")
    check(len(by_op["return"]) == 2 and all(m.replacement == "do end" for m in by_op["return"]), "return: both returns inside f become `do end`")
    check(all(m.line != 10 for m in by_op["return"]), "return: the module's own `return f` at column 1 is never touched")
    check([m.replacement for m in by_op["negate"]] == ["not (a < b and b == 1)"], "negate: the if condition is wrapped in not (...)")
    neg = by_op["negate"][0]
    check("if not (a < b and b == 1) then" in neg.apply(src) and src.count("\n") == neg.apply(src).count("\n"), "apply: a mutant keeps every other byte and the line count")
    check(len(mutate.select(ms, "x.lua", 3)) == 3 and len({m.op for m in mutate.select(ms, "x.lua", 3)}) == 3, "select: a quick pick of 3 spreads over 3 operators")
    check([m.line for m in mutate.select(ms, "x.lua", 3)] == [m.line for m in mutate.select(ms, "x.lua", 3)], "select: the pick is deterministic")
    check(mutate.mutants_for("local t = { a = 1.0 }\nreturn t\n")[0].replacement == "1.50", "number: a float keeps its decimal form (1.0 -> 1.50)")

    # the real tree, one module
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "quick.json"
        proc = run("--quick", "--module", "WorldClock", "--json", str(out))
        check(proc.returncode in (0, 1) and out.is_file(), f"--quick --module WorldClock runs (exit {proc.returncode}) and writes the JSON")
        data = json.loads(out.read_text(encoding="utf-8"))
        wc = data["modules"].get("WorldClock", {})
        check(wc.get("mutants", 0) > 5, f"WorldClock: more than 5 mutants ({wc.get('mutants')})")
        check(wc.get("killed", 0) > wc.get("survived", 0), f"WorldClock: killed {wc.get('killed')} > survived {wc.get('survived')}")
        check(wc.get("mutants") == wc.get("killed", 0) + wc.get("survived", 0), "WorldClock: mutants = killed + survived")
        check(data["totals"]["mutants"] == wc.get("mutants") and "mutate: " in proc.stdout, "totals match the one module and the summary line is printed")
        check(run("--quick", "--module", "NoSuchModule").returncode == 2, "an unknown --module exits 2")

    # negative control: a suite that cannot fail lets every mutant through
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "tree"
        shutil.copytree(ROOT / "src", root / "src")
        shutil.copytree(ROOT / "tests", root / "tests")
        (root / "tests" / "worldclock_test.luau").write_text('print("worldclock_test: PASS 1")\n', encoding="utf-8")
        out = Path(tmp) / "neg.json"
        proc = run("--root", str(root), "--quick", "--module", "WorldClock", "--json", str(out))
        data = json.loads(out.read_text(encoding="utf-8"))
        wc = data["modules"]["WorldClock"]
        check(proc.returncode == 1, "negative control: an always-pass suite makes mutate.py exit 1")
        check(wc["survival"] == 1.0 and wc["killed"] == 0 and wc["survived"] == wc["mutants"] > 5, f"negative control: survival 1.0 ({wc['survived']} of {wc['mutants']} survived)")
        check("FAIL WorldClock" in proc.stdout and "mutate: FAIL" in proc.stdout, "negative control: the module line and the summary say FAIL")
        proc_adv = run("--root", str(root), "--quick", "--module", "WorldClock", "--advisory", "WorldClock")
        check(proc_adv.returncode == 0 and "adv  WorldClock" in proc_adv.stdout, "--advisory reports the module without failing the run")

    if fails:
        print(f"mutate_test: FAIL {len(fails)} of {len(checks)}")
        for f in fails:
            print("   - " + f)
        return 1
    print(f"mutate_test: PASS {len(checks)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
