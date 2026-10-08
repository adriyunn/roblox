#!/usr/bin/env python3
"""check_conventions.py (About Fishing F1 cloud work; Cloud, 2026-10-08)

Checks every .lua under cloud_work/src/ against the module rules in CLAUDE.md and prints one line per
violation (exit 1 on any, 0 when clean):
  * line 1 is `--!strict`;
  * line 2 is the team header `-- <Name> (About Fishing F1<anything>; Cloud, YYYY-MM-DD; design/<note>.md<...>)`
    with <Name> equal to the file name (a .client.lua / .server.lua may use its full file name);
  * the first 40 lines carry `WRITTEN WITHOUT THE PROJECT FILES` and `Integration points`;
  * no top-level line (indentation 0, outside comments and strings) touches an engine global: game, script,
    workspace, Instance.new, task., Random.new, os.clock, tick(, wait( (every service is injected).
    Exception, narrowly: a `function` / `local function` declaration line is the function's own header,
    so a parameter named `game` or `script` there, or a method named `tick`, is not a global reference;
    a method call `X.tick(` / `X.wait(` is not the global either;
  * tests/<name>_test.luau exists (lowercase name), holds at least 25 `T.` checks, at least one negative
    control (`negative control` or `T.throws`) and ends with `T.finish()`.
A .client.lua / .server.lua (a Studio script, not a module) is held to the header rules only: it may start
with `--!` directive lines (`--!nocheck`, `--!nolint ...`: it touches the real engine, so strict typing is
not asked of it, as the team's own sandbox driver shows), its header is the first line after them, it
must say WRITTEN WITHOUT THE PROJECT FILES, it is itself the wiring (no `Integration points` block
asked), it may touch the engine at top level and needs no suite.
Run: python3 -I tools/check_conventions.py [cloud_work]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HEADER = re.compile(r"^-- (\S+) \(About Fishing F1[^;]*; Cloud, \d{4}-\d{2}-\d{2}; design/[^\s)]+\.md[^)]*\)\s*$")
GLOBALS = re.compile(r"\b(?:game|script|workspace)\b|Instance\.new|\btask\.|Random\.new|os\.clock|(?<![\w.:])tick\(|(?<![\w.:])wait\(")
DECLARATION = re.compile(r"^(?:local\s+)?function\b")
DIRECTIVE = re.compile(r"^--!")
CHECK_CALL = re.compile(r"\bT\.(\w+)\(")
LONG_OPEN = re.compile(r"\[(=*)\[")
MIN_CHECKS = 25
HEADER_LINES = 40
SCRIPT_SUFFIXES = (".client.lua", ".server.lua")


def strip_code(line: str, in_block: str | None) -> tuple[str, str | None]:
    """The line with strings and comments blanked; in_block is the closing bracket of an open --[[ comment."""
    out = []
    i, n = 0, len(line)
    while i < n:
        if in_block is not None:
            j = line.find(in_block, i)
            if j < 0:
                return "".join(out), in_block
            i, in_block = j + len(in_block), None
            continue
        c = line[i]
        if line.startswith("--", i):
            m = LONG_OPEN.match(line, i + 2)
            if m is None:
                break  # a line comment: the rest is not code
            in_block = "]" + m.group(1) + "]"
            i = m.end()
        elif c in "\"'":
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == "\\" else 1
            out.append(" ")
            i = j + 1
        elif c == "[" and LONG_OPEN.match(line, i):
            m = LONG_OPEN.match(line, i)
            close = "]" + m.group(1) + "]"
            j = line.find(close, m.end())
            if j < 0:
                in_block = close  # a multi-line long string: treated like a block comment (not code)
                return "".join(out), in_block
            out.append(" ")
            i = j + len(close)
        else:
            out.append(c)
            i += 1
    return "".join(out), in_block


def check_module(path: Path, root: Path) -> list[str]:
    rel = path.relative_to(root)
    problems: list[str] = []
    lines = path.read_text(encoding="utf-8").split("\n")
    is_script = path.name.endswith(SCRIPT_SUFFIXES)
    name = path.name[: -len(".client.lua")] if is_script else path.stem
    header_at = 1  # 0-based line of the header: line 2 for a module, the first non-directive line for a script
    if is_script:
        while header_at < len(lines) and DIRECTIVE.match(lines[header_at]):
            header_at += 1
        if header_at == 0 or not DIRECTIVE.match(lines[0]):
            problems.append(f"{rel}: line 1 must be a --! directive (--!strict, or --!nocheck for a script on the real engine)")
    elif not lines or lines[0] != "--!strict":
        problems.append(f"{rel}: line 1 must be --!strict")
    m = HEADER.match(lines[header_at]) if len(lines) > header_at else None
    if m is None:
        problems.append(f"{rel}: line {header_at + 1} must be `-- {name} (About Fishing F1, <WS-..>; Cloud, YYYY-MM-DD; design/<note>.md)`")
    elif m.group(1) not in (name, path.name):
        problems.append(f"{rel}: line {header_at + 1} names `{m.group(1)}`, the file is `{name}`")
    head = "\n".join(lines[:HEADER_LINES])
    if "WRITTEN WITHOUT THE PROJECT FILES" not in head:
        problems.append(f"{rel}: the first {HEADER_LINES} lines must say WRITTEN WITHOUT THE PROJECT FILES")
    if is_script:
        return problems
    if "Integration points" not in head:
        problems.append(f"{rel}: the first {HEADER_LINES} lines must list the `Integration points` a dev must wire")
    in_block: str | None = None
    for i, line in enumerate(lines, start=1):
        code, in_block = strip_code(line, in_block)
        if line[:1] in (" ", "\t") or not code.strip() or DECLARATION.match(code):
            continue  # indented (inside a function or a table), nothing but a comment, or a function's own header line
        hit = GLOBALS.search(code)
        if hit:
            problems.append(f"{rel}:{i}: top-level use of `{hit.group(0)}` (inject it through deps instead)")
    test = root / "tests" / f"{name.lower()}_test.luau"
    if not test.is_file():
        problems.append(f"{rel}: no suite tests/{name.lower()}_test.luau")
        return problems
    body = test.read_text(encoding="utf-8")
    calls = [c for c in CHECK_CALL.findall(body) if c != "finish"]
    if len(calls) < MIN_CHECKS:
        problems.append(f"{test.relative_to(root)}: {len(calls)} T. checks, at least {MIN_CHECKS} needed")
    if "negative control" not in body and "T.throws" not in body:
        problems.append(f"{test.relative_to(root)}: no negative control (a `negative control` label or a T.throws)")
    last = [l for l in body.split("\n") if l.strip()]
    if not last or last[-1].strip() != "T.finish()":
        problems.append(f"{test.relative_to(root)}: must end with T.finish()")
    return problems


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else Path(__file__).resolve().parent.parent).resolve()
    files = sorted((root / "src").rglob("*.lua"))
    if not files:
        print(f"check_conventions: no .lua under {root / 'src'}")
        return 1
    problems: list[str] = []
    for f in files:
        problems.extend(check_module(f, root))
    for p in problems:
        print("  " + p)
    if problems:
        print(f"check_conventions: FAIL {len(problems)} ({len(files)} files)")
        return 1
    print(f"check_conventions: PASS {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
