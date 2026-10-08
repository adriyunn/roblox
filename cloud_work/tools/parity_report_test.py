#!/usr/bin/env python3
"""parity_report_test.py (About Fishing F1 cloud work; Cloud, 2026-10-06)

Proves tools/parity_report.py: the --selftest passes (exit codes 0 / 1 / 2 both ways), and the real
EncounterLog exports are readable. The Luau CLI has no file I/O, so tests/encounterlog_test.luau prints
its 20-record sample between FIXTURE markers; this test runs that suite, harvests the CSV and JSON into
tests/fixtures/encounters_sample.{csv,json}, and runs the report on both (identical tables, exit 0),
then on tightened bands (exit 1). Without a luau binary on PATH (or $LUAU) it uses the committed
fixtures. Run from tools/: python3 -I parity_report_test.py
"""
from __future__ import annotations

import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TESTS = ROOT / "tests"
FIXTURES = TESTS / "fixtures"
REPORT = HERE / "parity_report.py"
BANDS = HERE / "parity_bands.json"
LUAU_SUITE = "encounterlog_test.luau"
BEGIN, END = "-----BEGIN FIXTURE ", "-----END FIXTURE-----"

checks: list[str] = []
fails: list[str] = []


def check(cond, label: str) -> bool:
    checks.append(label)
    if not cond:
        fails.append(label)
    print(f"  {'ok  ' if cond else 'FAIL'} {len(checks):<4} {label}")
    return bool(cond)


def report(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", str(REPORT), *args], capture_output=True, text=True)


def table_rows(stdout: str) -> list[str]:
    return [line for line in stdout.splitlines() if line.startswith(("bed ", "mid ", "lure ", "surface "))]


def harvest() -> str:
    """Runs the Luau suite and writes the FIXTURE blocks into tests/fixtures; returns 'luau' or 'committed'."""
    luau = shutil.which(os.environ.get("LUAU", "luau"))
    if luau is None:
        print("  note: no luau binary found; using the committed fixtures")
        return "committed"
    proc = subprocess.run([luau, LUAU_SUITE], cwd=TESTS, capture_output=True, text=True)
    check(proc.returncode == 0, f"{LUAU_SUITE} passes under the Luau CLI")
    blocks: dict[str, list[str]] = {}
    current = None
    for line in proc.stdout.splitlines():
        if line.startswith(BEGIN) and line.endswith("-----"):
            current = line[len(BEGIN):-5]
            blocks[current] = []
        elif line == END:
            current = None
        elif current is not None:
            blocks[current].append(line)
    check(set(blocks) == {"encounters_sample.csv", "encounters_sample.json"}, "the Luau suite printed both fixture blocks")
    FIXTURES.mkdir(parents=True, exist_ok=True)
    for name, lines in blocks.items():
        (FIXTURES / name).write_bytes(("\n".join(lines).rstrip("\n") + "\n").encode("utf-8"))
    return "luau"


def main() -> int:
    # 1. the tool's own selftest (exit codes both ways)
    proc = report("--selftest")
    check(proc.returncode == 0, "--selftest exits 0")
    check("selftest: PASS" in proc.stdout, "--selftest prints selftest: PASS")
    check("exit 1 (want 1)" in proc.stdout, "--selftest saw the out-of-band set exit 1")
    check("exit 2 (want 2)" in proc.stdout, "--selftest saw the bad header exit 2")

    # 2. the real Luau exports
    source = harvest()
    csv_path, json_path = FIXTURES / "encounters_sample.csv", FIXTURES / "encounters_sample.json"
    check(csv_path.is_file() and json_path.is_file(), f"fixtures present ({source})")
    csv_text = csv_path.read_text(encoding="utf-8")
    lines = csv_text.splitlines()
    check(len(lines) == 21, "sample CSV has header + 20 rows")
    check(lines[0] == "id,anglerId,fishId,speciesId,hookMode,outcome,tNotice,tEnd,noticeToFirstNip,hoverS,pressOffset,verdict,fightS,jumps,spooks", "sample CSV header is the fixed header")
    check(b"\r" not in csv_path.read_bytes() and csv_text.endswith("\n"), "sample CSV is LF with a final newline")
    sample = json.loads(json_path.read_text(encoding="utf-8"))
    check(sample.get("v") == 1 and len(sample.get("records", [])) == 20, "sample JSON is toTable v1 with 20 records")
    check(sample["records"][0]["id"] == "enc-01" and sample["records"][0]["hookMode"] == "bed", "sample JSON first record")

    proc_csv = report(str(csv_path), "--bands", str(BANDS))
    check(proc_csv.returncode == 0, "report on the Luau CSV exits 0 with the default bands")
    rows_csv = table_rows(proc_csv.stdout)
    check(len(rows_csv) == 8, "CSV report has 8 band rows (bed 3, mid 3, lure 2)")
    check(all("  OK" in r for r in rows_csv), "every CSV band row is OK")
    check("records: 20 from 1 file(s); bed 8, lure 5, mid 7" in proc_csv.stdout, "CSV report counts 8 bed, 7 mid, 5 lure")
    bed_nip = [r for r in rows_csv if r.startswith("bed ") and "noticeToFirstNip" in r]
    check(bool(bed_nip) and "4.083" in bed_nip[0], "bed noticeToFirstNip median is F1's 4.083 s")

    proc_json = report(str(json_path), "--bands", str(BANDS))
    check(proc_json.returncode == 0, "report on the Luau JSON exits 0")
    check(table_rows(proc_json.stdout) == rows_csv, "CSV and JSON exports give the identical table")

    proc_both = report(str(csv_path), str(json_path))
    check(proc_both.returncode == 0 and "records: 40 from 2 file(s)" in proc_both.stdout, "two files merge (default bands file found next to the script)")

    # 3. tightened bands fail, SKIP handling, bad input
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        tight = json.loads(BANDS.read_text(encoding="utf-8"))
        tight["bed"]["hoverS"] = [100, 200]
        (d / "tight.json").write_text(json.dumps(tight), encoding="utf-8")
        proc_tight = report(str(csv_path), "--bands", str(d / "tight.json"))
        check(proc_tight.returncode == 1, "tightened bed hoverS band exits 1")
        check(any("bed " in r and "hoverS" in r and "FAIL" in r and "outside" in r for r in table_rows(proc_tight.stdout)), "the failing row names bed hoverS and the reason")
        check("parity_report: FAIL 1" in proc_tight.stdout, "the summary line counts one FAIL")

        extra = json.loads(BANDS.read_text(encoding="utf-8"))
        extra["surface"] = {"hoverS": [1, 2]}
        (d / "extra.json").write_text(json.dumps(extra), encoding="utf-8")
        check(report(str(csv_path), "--bands", str(d / "extra.json")).returncode == 1, "a hookMode with no records fails by default")
        proc_skip = report(str(csv_path), "--bands", str(d / "extra.json"), "--skip-empty")
        check(proc_skip.returncode == 0 and any(r.startswith("surface ") and "SKIP" in r for r in table_rows(proc_skip.stdout)), "--skip-empty prints SKIP and exits 0")

        (d / "bad.csv").write_text("id,hookMode\nx,bed\n", encoding="utf-8")
        proc_bad = report(str(d / "bad.csv"))
        check(proc_bad.returncode == 2 and "unexpected header" in proc_bad.stderr, "a CSV with another header exits 2 and says so")
        check(report(str(d / "missing.csv")).returncode == 2, "a missing file exits 2")
        (d / "badband.json").write_text(json.dumps({"bed": {"verdict": [1, 2]}}), encoding="utf-8")
        check(report(str(csv_path), "--bands", str(d / "badband.json")).returncode == 2, "a band on a non-numeric field exits 2")
        check(report().returncode == 2, "no input files exits 2")

    # R8 (F6, F7): a BOM-prefixed CSV (Notepad) reads like the plain one; a JSON record that is not an object exits 2
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "bom.csv").write_bytes(b"\xef\xbb\xbf" + csv_path.read_bytes())
        proc_bom = report(str(d / "bom.csv"), "--bands", str(BANDS))
        check(proc_bom.returncode == 0 and table_rows(proc_bom.stdout) == rows_csv, "R8a (F6): a UTF-8 BOM before the header is ignored (was: exit 2, unexpected header)")
        (d / "notobj.json").write_text('{"v": 1, "records": [1]}', encoding="utf-8")
        proc_notobj = report(str(d / "notobj.json"), "--bands", str(BANDS))
        check(proc_notobj.returncode == 2 and "not an object" in proc_notobj.stderr, "R8b (F7): a JSON record that is not an object exits 2 with a message (was: a traceback, exit 1)")

    # N9: "nan" / "inf" cells and a boolean band edge are input errors (exit 2), not numbers
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        rows_nan = list(csv.reader(lines))
        rows_nan[1][rows_nan[0].index("hoverS")] = "nan"
        p = d / "nan.csv"
        with p.open("w", encoding="utf-8", newline="\n") as fh:
            csv.writer(fh, lineterminator="\n").writerows(rows_nan)
        proc_nan = report(str(p), "--bands", str(BANDS))
        (d / "boolband.json").write_text('{"bed": {"hoverS": [true, 45]}}', encoding="utf-8")
        proc_bool = report(str(csv_path), "--bands", str(d / "boolband.json"))
        check(proc_nan.returncode == 2 and "non-finite" in proc_nan.stderr and proc_bool.returncode == 2 and "must be [lo, hi]" in proc_bool.stderr,
              "N9: a nan cell and a boolean band edge both exit 2 with a message (was: nan parsed as a number, true passed the int check)")

    # negative control: the report must be able to fail on the real export once a column is out of band
    with tempfile.TemporaryDirectory() as tmp:
        rows = list(csv.reader(lines))
        hover_col, mode_col = rows[0].index("hoverS"), rows[0].index("hookMode")
        for r in rows[1:]:
            if r[mode_col] == "mid":
                r[hover_col] = "30.000"
        p = Path(tmp) / "shifted.csv"
        with p.open("w", encoding="utf-8", newline="\n") as fh:
            csv.writer(fh, lineterminator="\n").writerows(rows)
        proc_neg = report(str(p), "--bands", str(BANDS))
        check(proc_neg.returncode == 1 and any(r.startswith("mid ") and "hoverS" in r and "FAIL" in r and "30.000" in r for r in table_rows(proc_neg.stdout)),
              "negative control: the real export with mid hoverS pushed to 30 s fails the 2..20 band")
        check(sum("FAIL" in r for r in table_rows(proc_neg.stdout)) == 1, "negative control: only that one band fails")

    if fails:
        print(f"parity_report_test: FAIL {len(fails)} of {len(checks)}")
        for f in fails:
            print("   - " + f)
        return 1
    print(f"parity_report_test: PASS {len(checks)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
