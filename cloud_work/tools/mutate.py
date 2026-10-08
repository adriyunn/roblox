#!/usr/bin/env python3
"""mutate.py (About Fishing F1 cloud work; Cloud, 2026-10-08)

Mutation checker for the cloud modules: does each module's suite notice when the module changes? In the
spirit of the team's run_fishpool_test.py --selftest (which proved 69/69 mutants killed). For every
module under src/ that has a tests/<name>_test.luau (lowercase name), it applies ONE change at a time to
a copy of the module in a temp dir (the real file is never touched), copies the whole src/ + tests/ tree
next to it with the mutant swapped in, runs the suite with the Luau CLI from that tests folder, and
records killed (the suite exits non-zero, or hangs past --timeout) against survived (the suite still
passes). A mutant that does not compile is "invalid" and counts on neither side.

Mutation operators (one per mutant):
  compare   flip one comparison: < <-> <=, > <-> >=, == <-> ~=
  logic     swap one `and` for `or` (or back)
  number    one numeric literal: an integer +1, a float x1.5 (0 and 1 in a table-index position t[1] skipped)
  return    one `return` inside a function body becomes `do end` (single-line returns only; the module's
            own `return M` at column 1 is never touched)
  negate    one statement-level `if` / `elseif` condition becomes `not (...)`

Modes: --quick (at most --per-module 12 mutants per module, spread over the five operators and chosen
within each by hashing the mutant's position, so the pick is the same on every machine and every run
until the module's text moves) or --full (every mutant). --module Name limits the run to one module,
--list-survivors prints each survivor's one-line diff, --json out.json writes the per-module numbers.
Exit 0 when every module's survival rate (survived / counted mutants) is at most --max-survival
(default 0.15), else 1; 2 on a usage error. A suite may carry its own threshold in a comment line,
`-- mutate-max-survival: 0.35 (why: ...)`, for mutants that are equivalent or change placeholder data;
--advisory Name,Name reports those modules without letting them fail the run (for a module another
agent is still writing). Run: python3 -I tools/mutate.py --quick
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parent
LUAU = os.environ.get("LUAU", "luau")
LUAU_COMPILE = os.environ.get("LUAU_COMPILE", "luau-compile")

COMPARE_FLIP = {"<": "<=", "<=": "<", ">": ">=", ">=": ">", "==": "~=", "~=": "=="}
BLOCK_OPENERS = {"function", "if", "do", "while", "for", "repeat", "then", "else", "elseif"}
STATEMENT_ENDERS = {"end", "else", "elseif", "until"}
CONTINUATION_OPS = {"..", "+", "-", "*", "/", "//", "%", "^", "==", "~=", "<", "<=", ">", ">=", ".", ":"}
OPS3 = ("...", "..=", "//=")
OPS2 = ("..", "==", "~=", "<=", ">=", "->", "+=", "-=", "*=", "/=", "%=", "^=", "//", "::")
LONG_BRACKET = re.compile(r"\[(=*)\[")
NUMBER = re.compile(r"0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.(?!\.)[\d_]*)?(?:[eE][-+]?\d+)?|\.\d[\d_]*(?:[eE][-+]?\d+)?")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
OVERRIDE = re.compile(r"--\s*mutate-max-survival:\s*([0-9]*\.?[0-9]+)")
OPERATORS = ("compare", "logic", "number", "return", "negate")


# ---------------------------------------------------------------- a small Luau tokenizer
class Tok:
    __slots__ = ("kind", "text", "start", "end", "line", "col")

    def __init__(self, kind: str, text: str, start: int, end: int, line: int, col: int):
        self.kind, self.text, self.start, self.end, self.line, self.col = kind, text, start, end, line, col


def tokenize(src: str) -> list[Tok]:
    """Tokens of kind ws | comment | string | number | name | op, each with its byte span, line and column."""
    toks: list[Tok] = []
    i, n = 0, len(src)
    line, line_start = 1, 0

    def add(kind: str, start: int, end: int) -> None:
        nonlocal line, line_start
        toks.append(Tok(kind, src[start:end], start, end, line, start - line_start + 1))
        nl = src.count("\n", start, end)
        if nl:
            line += nl
            line_start = src.rfind("\n", start, end) + 1

    def long_bracket_end(start: int) -> int:
        m = LONG_BRACKET.match(src, start)
        assert m is not None
        close = "]" + m.group(1) + "]"
        j = src.find(close, m.end())
        return n if j < 0 else j + len(close)

    while i < n:
        c = src[i]
        if c in " \t\r\n":
            j = i
            while j < n and src[j] in " \t\r\n":
                j += 1
            add("ws", i, j)
        elif src.startswith("--", i):
            if LONG_BRACKET.match(src, i + 2):
                j = long_bracket_end(i + 2)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            add("comment", i, j)
        elif c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            add("string", i, min(j + 1, n))
        elif c == "[" and LONG_BRACKET.match(src, i):
            add("string", i, long_bracket_end(i))
        elif c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            m = NUMBER.match(src, i)
            assert m is not None
            add("number", i, m.end())
        elif c.isalpha() or c == "_":
            m = NAME.match(src, i)
            assert m is not None
            add("name", i, m.end())
        else:
            op = next((o for o in OPS3 + OPS2 if src.startswith(o, i)), c)
            add("op", i, i + len(op))
        i = toks[-1].end
    return toks


# ---------------------------------------------------------------- mutants
class Mutant:
    __slots__ = ("op", "start", "end", "replacement", "line", "col", "key")

    def __init__(self, op: str, start: int, end: int, replacement: str, line: int, col: int):
        self.op, self.start, self.end, self.replacement, self.line, self.col = op, start, end, replacement, line, col
        self.key = ""

    def apply(self, src: str) -> str:
        return src[: self.start] + self.replacement + src[self.end :]

    def diff(self, src: str) -> tuple[str, str]:
        """The source line before and after the change (every operator stays on one line)."""
        ls = src.rfind("\n", 0, self.start) + 1
        le = src.find("\n", self.end)
        le = len(src) if le < 0 else le
        before = src[ls:le]
        after = src[ls : self.start] + self.replacement + src[self.end : le]
        return before.strip(), after.strip()


def mutants_for(src: str) -> list[Mutant]:
    """Every single-change mutant of a Luau source, in source order."""
    sig = [t for t in tokenize(src) if t.kind not in ("ws", "comment")]
    out: list[Mutant] = []
    for idx, t in enumerate(sig):
        prev = sig[idx - 1] if idx > 0 else None
        nxt = sig[idx + 1] if idx + 1 < len(sig) else None
        if t.kind == "op" and t.text in COMPARE_FLIP:
            out.append(Mutant("compare", t.start, t.end, COMPARE_FLIP[t.text], t.line, t.col))
        elif t.kind == "name" and t.text in ("and", "or"):
            out.append(Mutant("logic", t.start, t.end, "or" if t.text == "and" else "and", t.line, t.col))
        elif t.kind == "number":
            txt = t.text
            if txt[:2].lower() in ("0x", "0b") or "_" in txt:
                continue
            is_index = prev is not None and prev.text == "[" and nxt is not None and nxt.text == "]"
            if "." in txt or "e" in txt.lower():
                d = Decimal(txt)
                if d == 0:
                    continue
                rep = str(d * Decimal("1.5"))
            else:
                v = int(txt)
                if is_index and v in (0, 1):
                    continue
                rep = str(v + 1)
            out.append(Mutant("number", t.start, t.end, rep, t.line, t.col))
        elif t.kind == "name" and t.text == "return":
            if t.col == 1:
                continue  # the module's own `return M`
            j, depth, last, ok = idx + 1, 0, None, True
            while j < len(sig) and sig[j].line == t.line:
                s = sig[j]
                if s.kind == "name" and s.text in STATEMENT_ENDERS and depth == 0:
                    break
                if s.kind == "name" and s.text in BLOCK_OPENERS:
                    ok = False
                    break
                if s.text in ("(", "[", "{"):
                    depth += 1
                elif s.text in (")", "]", "}"):
                    if depth == 0:
                        break
                    depth -= 1
                last = s
                j += 1
            if not ok or depth != 0:
                continue
            if last is not None and last.kind == "op" and last.text not in (")", "]", "}"):
                continue  # a trailing operator or comma: the expression goes on below
            follow = sig[j] if j < len(sig) else None
            if follow is not None and follow.line != t.line and ((follow.kind == "op" and follow.text in CONTINUATION_OPS) or (follow.kind == "name" and follow.text in ("and", "or"))):
                continue
            out.append(Mutant("return", t.start, last.end if last else t.end, "do end", t.line, t.col))
        elif t.kind == "name" and t.text in ("if", "elseif"):
            if prev is not None and prev.line == t.line:
                continue  # an if-expression, not a statement
            j, depth, then_tok = idx + 1, 0, None
            while j < len(sig) and sig[j].line == t.line:
                s = sig[j]
                if s.text in ("(", "[", "{"):
                    depth += 1
                elif s.text in (")", "]", "}"):
                    depth -= 1
                elif s.kind == "name" and s.text == "then" and depth == 0:
                    then_tok = s
                    break
                j += 1
            if then_tok is None or j == idx + 1:
                continue
            cstart, cend = sig[idx + 1].start, sig[j - 1].end
            out.append(Mutant("negate", cstart, cend, "not (" + src[cstart:cend] + ")", t.line, t.col))
    return out


# ---------------------------------------------------------------- modules and the runner
class Module:
    def __init__(self, name: str, path: Path, test: Path, root: Path):
        self.name, self.path, self.test, self.root = name, path, test, root
        self.rel = path.relative_to(root)
        self.src = path.read_text(encoding="utf-8")


def find_modules(root: Path, only: str | None) -> list[Module]:
    out = []
    for p in sorted((root / "src").rglob("*.lua")):
        if p.name.endswith((".client.lua", ".server.lua")):
            continue
        name = p.stem
        if only is not None and name.lower() != only.lower():
            continue
        test = root / "tests" / f"{name.lower()}_test.luau"
        if test.is_file():
            out.append(Module(name, p, test, root))
    return out


def select(mutants: list[Mutant], rel: str, limit: int | None) -> list[Mutant]:
    """All mutants, or at most `limit` of them: round-robin over the operators (so a data-heavy module is not
    sampled on its number literals alone), each operator's mutants ordered by the hash of their position."""
    for m in mutants:
        m.key = hashlib.sha1(f"{rel}|{m.line}|{m.col}|{m.op}".encode()).hexdigest()
    if limit is None or len(mutants) <= limit:
        return mutants
    queues = {op: sorted((m for m in mutants if m.op == op), key=lambda m: m.key) for op in OPERATORS}
    picked: list[Mutant] = []
    while len(picked) < limit and any(queues.values()):
        for op in OPERATORS:
            if queues[op] and len(picked) < limit:
                picked.append(queues[op].pop(0))
    return sorted(picked, key=lambda m: (m.line, m.col))


def suite_threshold(test: Path) -> float | None:
    """The `-- mutate-max-survival: x` a suite declares for itself, or None."""
    m = OVERRIDE.search(test.read_text(encoding="utf-8"))
    return float(m.group(1)) if m else None


def run_one(work: Path, module: Module, m: Mutant, timeout: float) -> str:
    """killed | survived | timeout | invalid for one mutant, run in its own copy of src/ + tests/."""
    d = Path(tempfile.mkdtemp(prefix="m_", dir=work))
    try:
        shutil.copytree(module.root / "src", d / "src")
        shutil.copytree(module.root / "tests", d / "tests")
        target = d / module.rel
        target.write_text(m.apply(module.src), encoding="utf-8")
        cp = subprocess.run([LUAU_COMPILE, "--null", str(target)], capture_output=True, text=True)
        if cp.returncode != 0:
            return "invalid"
        try:
            p = subprocess.run([LUAU, module.test.name], cwd=d / "tests", capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return "timeout"
        return "survived" if p.returncode == 0 else "killed"
    finally:
        shutil.rmtree(d, ignore_errors=True)


def check_module(work: Path, module: Module, limit: int | None, timeout: float, jobs: int) -> dict:
    mutants = select(mutants_for(module.src), str(module.rel), limit)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        statuses = list(pool.map(lambda m: run_one(work, module, m, timeout), mutants))
    survivors = []
    counts = {"killed": 0, "survived": 0, "timeout": 0, "invalid": 0}
    for m, st in zip(mutants, statuses):
        counts[st] += 1
        if st == "survived":
            before, after = m.diff(module.src)
            survivors.append({"line": m.line, "col": m.col, "op": m.op, "before": before, "after": after,
                              "diff": f"{module.rel.name}:{m.line} {m.op}: {before}  =>  {after}"})
    counted = counts["killed"] + counts["timeout"] + counts["survived"]
    survival = counts["survived"] / counted if counted else 0.0
    return {
        "module": module.name, "file": str(module.rel), "test": module.test.name,
        "generated": len(mutants_for(module.src)), "mutants": counted, "killed": counts["killed"] + counts["timeout"],
        "timeouts": counts["timeout"], "survived": counts["survived"], "invalid": counts["invalid"],
        "survival": round(survival, 4), "survivors": survivors,
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="mutation checker for the cloud Luau modules")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--quick", action="store_true", help="at most --per-module mutants per module (default mode)")
    mode.add_argument("--full", action="store_true", help="every mutant")
    ap.add_argument("--module", default=None, help="only this module (file stem, case-insensitive)")
    ap.add_argument("--per-module", type=int, default=12, help="quick mode: mutants per module (default 12)")
    ap.add_argument("--max-survival", type=float, default=0.15, help="largest survived/mutants per module that still passes (default 0.15)")
    ap.add_argument("--list-survivors", action="store_true", help="print every survivor's one-line diff")
    ap.add_argument("--advisory", default="", help="comma-separated module names that are reported but never fail the run")
    ap.add_argument("--json", type=Path, default=None, help="write the per-module numbers to this file")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="the folder holding src/ and tests/ (default: cloud_work)")
    ap.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 2), help="mutants run in parallel")
    ap.add_argument("--timeout", type=float, default=20.0, help="seconds a suite may run per mutant before it counts as killed (hung)")
    args = ap.parse_args(argv)
    root = args.root.resolve()
    if not (root / "src").is_dir() or not (root / "tests").is_dir():
        print(f"mutate: no src/ and tests/ under {root}", file=sys.stderr)
        return 2
    if shutil.which(LUAU) is None or shutil.which(LUAU_COMPILE) is None:
        print("mutate: luau / luau-compile not on PATH (bash cloud_work/tools/setup_luau.sh)", file=sys.stderr)
        return 2
    modules = find_modules(root, args.module)
    if not modules:
        print(f"mutate: no module with a tests/<name>_test.luau matched {args.module!r} under {root}", file=sys.stderr)
        return 2
    limit = None if args.full else args.per_module
    mode_name = "full" if args.full else "quick"
    advisory = {s.strip().lower() for s in args.advisory.split(",") if s.strip()}
    t0 = time.time()
    work = Path(tempfile.mkdtemp(prefix="mutate_"))
    results = []
    try:
        for module in modules:
            r = check_module(work, module, limit, args.timeout, args.jobs)
            own = suite_threshold(module.test)
            r["max_survival"] = own if own is not None else args.max_survival
            r["advisory"] = module.name.lower() in advisory
            r["ok"] = r["survival"] <= r["max_survival"] or r["advisory"]
            results.append(r)
            note = "" if r["invalid"] == 0 else f", {r['invalid']} invalid skipped"
            if own is not None:
                note += f", suite threshold {own:.0%}"
            flag = "ok  " if r["survival"] <= r["max_survival"] else ("adv " if r["advisory"] else "FAIL")
            print(f"  {flag} {module.name}: {r['mutants']} mutants, {r['killed']} killed, {r['survived']} survived ({r['survival']:.0%}{note})")
            if args.list_survivors:
                for s in r["survivors"]:
                    print(f"       survivor {s['diff']}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    totals = {k: sum(r[k] for r in results) for k in ("mutants", "killed", "survived", "invalid", "timeouts")}
    ok = all(r["ok"] for r in results)
    summary = (f"mutate: {'PASS' if ok else 'FAIL'} {mode_name}, {len(results)} modules, {totals['mutants']} mutants, "
               f"{totals['killed']} killed, {totals['survived']} survived, max survival {args.max_survival:.0%}, {time.time() - t0:.1f} s")
    if args.json is not None:
        args.json.write_text(json.dumps({"mode": mode_name, "max_survival": args.max_survival, "root": str(root),
                                         "modules": {r["module"]: r for r in results}, "totals": totals, "ok": ok}, indent=1) + "\n", encoding="utf-8")
    print(summary)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
