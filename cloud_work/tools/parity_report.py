#!/usr/bin/env python3
"""parity_report.py (About Fishing F1 cloud work; Cloud, 2026-10-06)

Reads one or more EncounterLog exports, groups the encounters by hookMode, computes n / median / p95
per metric and compares each median with a band; prints a fixed-width table with an OK/FAIL column.

WRITTEN WITHOUT THE PROJECT FILES. What a dev must keep in sync:
  * CSV_HEADER below must equal EncounterLog.CSV_HEADER in src/Fishing/Shared/EncounterLog.lua.
    The CSV is EncounterLog.toCsv (seconds with 3 decimals, counts as integers, nil as empty); the JSON
    is HttpService:JSONEncode(EncounterLog.toTable(records)) = {"v": 1, "fields": [...], "records": [...]}
    (a bare list of record objects is accepted too).
  * Bands come from --bands <file.json>, the same shape as the Luau bandTable:
    {"bed": {"hoverS": [5, 45]}, "mid": {...}}; default = parity_bands.json next to this script.
  * A band is OK when n >= 5 and lo <= median <= hi (nearest-rank p95 is printed for information).
    A hookMode in the bands with no records fails (n<5) unless --skip-empty prints it as SKIP.

Header:
  id,anglerId,fishId,speciesId,hookMode,outcome,tNotice,tEnd,noticeToFirstNip,hoverS,pressOffset,verdict,fightS,jumps,spooks

Usage (standard library only, run with -I):
  python3 -I parity_report.py <encounters.csv|encounters.json> [more files] [--bands parity_bands.json] [--skip-empty]
  python3 -I parity_report.py --selftest
Exit 0 = every band OK (or SKIP), 1 = any FAIL, 2 = bad input (unknown header, bad JSON, missing file).
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CSV_HEADER = [
    "id", "anglerId", "fishId", "speciesId", "hookMode", "outcome", "tNotice", "tEnd",
    "noticeToFirstNip", "hoverS", "pressOffset", "verdict", "fightS", "jumps", "spooks",
]
SECONDS = {"tNotice", "tEnd", "noticeToFirstNip", "hoverS", "pressOffset", "fightS"}
COUNTS = {"jumps", "spooks"}
NUMERIC = SECONDS | COUNTS
MIN_N = 5

# the same numbers as parity_bands.json (used when that file is missing)
DEFAULT_BANDS = {
    "bed": {"hoverS": [5, 45], "noticeToFirstNip": [3.5, 4.5], "fightS": [5, 60]},
    "mid": {"hoverS": [2, 20], "noticeToFirstNip": [3.5, 4.5], "fightS": [5, 60]},
    "lure": {"noticeToFirstNip": [3.5, 4.5], "fightS": [5, 60]},
}


class InputError(Exception):
    """Bad input file: wrong header, bad JSON, unknown metric."""


def _num(value):
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        raise InputError(f"boolean where a number was expected: {value!r}")
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise InputError(f"not a number: {value!r}") from exc


def _normalise(row: dict, where: str) -> dict:
    out = {}
    for field in CSV_HEADER:
        v = row.get(field)
        if field in NUMERIC:
            try:
                out[field] = _num(v)
            except InputError as exc:
                raise InputError(f"{where}: field {field}: {exc}") from exc
        else:
            out[field] = None if v in (None, "") else str(v)
    if not out["hookMode"]:
        raise InputError(f"{where}: hookMode is empty")
    return out


def load_records(path: Path) -> list[dict]:
    """Reads a CSV (EncounterLog.toCsv) or JSON (EncounterLog.toTable) export into a list of dicts."""
    if not path.is_file():
        raise InputError(f"no such file: {path}")
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json" or text.lstrip().startswith(("{", "[")):
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            raise InputError(f"{path}: bad JSON: {exc}") from exc
        if isinstance(data, dict):
            if "records" not in data:
                raise InputError(f"{path}: JSON object has no 'records' key")
            if data.get("v", 1) != 1:
                raise InputError(f"{path}: unsupported toTable version {data.get('v')!r}")
            fields = data.get("fields")
            if fields is not None and list(fields) != CSV_HEADER:
                raise InputError(f"{path}: JSON fields differ from the known header: {fields}")
            rows = data["records"]
        elif isinstance(data, list):
            rows = data
        else:
            raise InputError(f"{path}: JSON must be an object with 'records' or a list")
        return [_normalise(r, f"{path} record {i + 1}") for i, r in enumerate(rows)]
    lines = text.splitlines()
    reader = csv.reader(lines)
    try:
        header = next(reader)
    except StopIteration as exc:
        raise InputError(f"{path}: empty file") from exc
    if header != CSV_HEADER:
        raise InputError(f"{path}: unexpected header {header!r}; expected {','.join(CSV_HEADER)}")
    records = []
    for i, cells in enumerate(reader, start=2):
        if not cells:
            continue
        if len(cells) != len(CSV_HEADER):
            raise InputError(f"{path} line {i}: {len(cells)} cells, expected {len(CSV_HEADER)}")
        records.append(_normalise(dict(zip(CSV_HEADER, cells)), f"{path} line {i}"))
    return records


def load_bands(path: Path | None) -> dict:
    """Loads the band table; without a path uses parity_bands.json next to the script, else DEFAULT_BANDS."""
    if path is None:
        candidate = Path(__file__).resolve().parent / "parity_bands.json"
        if not candidate.is_file():
            return json.loads(json.dumps(DEFAULT_BANDS))
        path = candidate
    if not path.is_file():
        raise InputError(f"no such bands file: {path}")
    try:
        bands = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise InputError(f"{path}: bad JSON: {exc}") from exc
    if not isinstance(bands, dict):
        raise InputError(f"{path}: bands must be an object keyed by hookMode")
    for mode, metrics in bands.items():
        if not isinstance(metrics, dict):
            raise InputError(f"{path}: bands[{mode!r}] must be an object keyed by metric")
        for metric, rng in metrics.items():
            if metric not in NUMERIC:
                raise InputError(f"{path}: unknown metric {metric!r} (numeric fields: {', '.join(sorted(NUMERIC))})")
            if not (isinstance(rng, list) and len(rng) == 2 and all(isinstance(x, (int, float)) for x in rng) and rng[0] <= rng[1]):
                raise InputError(f"{path}: band {mode}.{metric} must be [lo, hi] with lo <= hi, got {rng!r}")
    return bands


def median(values: list[float]) -> float:
    s = sorted(values)
    n = len(s)
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) / 2


def p95(values: list[float]) -> float:
    """Nearest-rank 95th percentile (the same rule as EncounterLog.summary)."""
    s = sorted(values)
    rank = max(1, math.ceil(0.95 * len(s)))
    return s[rank - 1]


def evaluate(records: list[dict], bands: dict, skip_empty: bool = False) -> list[dict]:
    """One row per (hookMode, metric) in sorted order with n, median, p95, lo, hi, status, reason."""
    rows = []
    for mode in sorted(bands):
        subset = [r for r in records if r["hookMode"] == mode]
        for metric in sorted(bands[mode]):
            lo, hi = bands[mode][metric]
            vals = [r[metric] for r in subset if r.get(metric) is not None]
            n = len(vals)
            row = {"hookMode": mode, "metric": metric, "n": n, "median": None, "p95": None, "lo": lo, "hi": hi, "status": "OK", "reason": ""}
            if n:
                row["median"], row["p95"] = median(vals), p95(vals)
            if n == 0 and skip_empty:
                row["status"], row["reason"] = "SKIP", "no records for this hookMode"
            elif n < MIN_N:
                row["status"], row["reason"] = "FAIL", f"n<{MIN_N} (n={n})"
            elif not (lo <= row["median"] <= hi):
                row["status"], row["reason"] = "FAIL", f"median {row['median']:.3f} outside {lo:.3f}..{hi:.3f}"
            rows.append(row)
    return rows


def format_table(rows: list[dict]) -> str:
    def num(v):
        return "" if v is None else f"{v:.3f}"

    head = f"{'hookMode':<8}  {'metric':<16}  {'n':>4}  {'median':>9}  {'p95':>9}  {'lo':>9}  {'hi':>9}  {'status':<6}  reason"
    out = [head, "-" * len(head)]
    for r in rows:
        out.append(
            f"{r['hookMode']:<8}  {r['metric']:<16}  {r['n']:>4}  {num(r['median']):>9}  {num(r['p95']):>9}  "
            f"{num(r['lo']):>9}  {num(r['hi']):>9}  {r['status']:<6}  {r['reason']}".rstrip()
        )
    return "\n".join(out)


def run(argv: list[str]) -> int:
    """The command line: returns the exit code instead of exiting (the selftest calls it too)."""
    ap = argparse.ArgumentParser(description="EncounterLog parity report (About Fishing F1)")
    ap.add_argument("files", nargs="*", help="EncounterLog CSV or JSON exports")
    ap.add_argument("--bands", type=Path, default=None, help="bands JSON (default: parity_bands.json next to this script)")
    ap.add_argument("--skip-empty", action="store_true", help="print SKIP instead of FAIL for a hookMode with no records")
    ap.add_argument("--selftest", action="store_true", help="prove the exit codes on synthetic in-band and out-of-band sets")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if not args.files:
        ap.print_usage()
        print("parity_report: no input files", file=sys.stderr)
        return 2
    try:
        bands = load_bands(args.bands)
        records = []
        for f in args.files:
            records.extend(load_records(Path(f)))
    except InputError as exc:
        print(f"parity_report: {exc}", file=sys.stderr)
        return 2
    per_mode = {}
    for r in records:
        per_mode[r["hookMode"]] = per_mode.get(r["hookMode"], 0) + 1
    modes = ", ".join(f"{m} {c}" for m, c in sorted(per_mode.items()))
    print(f"records: {len(records)} from {len(args.files)} file(s); {modes or 'none'}")
    print(f"bands: {args.bands or 'default parity_bands.json'}")
    rows = evaluate(records, bands, args.skip_empty)
    print(format_table(rows))
    fails = sum(1 for r in rows if r["status"] == "FAIL")
    print(f"parity_report: {'FAIL ' + str(fails) if fails else 'OK'} ({len(rows)} bands)")
    return 1 if fails else 0


# ---------------------------------------------------------------- selftest
def _synthetic(mode: str, n: int, hover: float, nip: float, fight: float, start: int) -> list[dict]:
    rows = []
    for i in range(n):
        k = start + i
        rows.append({
            "id": f"syn-{k:02d}", "anglerId": 1, "fishId": f"fish-{k}", "speciesId": "trout", "hookMode": mode,
            "outcome": "Caught", "tNotice": k * 100.0, "tEnd": k * 100.0 + hover + fight, "noticeToFirstNip": nip + 0.01 * i,
            "hoverS": hover + i, "pressOffset": 0.2, "verdict": "Good", "fightS": fight + i, "jumps": i % 3, "spooks": 0,
        })
    return rows


def _cell(field: str, v) -> str:
    if v is None:
        return ""
    if field in SECONDS:
        return f"{v:.3f}"
    if field in COUNTS:
        return f"{int(v):d}"
    return str(v)


def write_csv(path: Path, records: list[dict]) -> None:
    """Writes records the way EncounterLog.toCsv does (same header, formats, LF endings)."""
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(CSV_HEADER)
        for r in records:
            w.writerow([_cell(f, r.get(f)) for f in CSV_HEADER])


def write_json(path: Path, records: list[dict]) -> None:
    """Writes records the way HttpService:JSONEncode(EncounterLog.toTable(records)) does."""
    rows = [{k: v for k, v in r.items() if v is not None} for r in records]
    path.write_text(json.dumps({"v": 1, "fields": CSV_HEADER, "records": rows}) + "\n", encoding="utf-8")


def selftest() -> int:
    """Generates an in-band and an out-of-band set in a temp dir and proves exit 0 / 1 (and 2 on a bad header)."""
    script = os.path.abspath(__file__)
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        bands = d / "bands.json"
        bands.write_text(json.dumps(DEFAULT_BANDS, indent=1) + "\n", encoding="utf-8")
        good = (_synthetic("bed", 6, 12.0, 4.05, 20.0, 1) + _synthetic("mid", 6, 6.0, 4.08, 22.0, 7)
                + _synthetic("lure", 6, 3.0, 4.10, 25.0, 13))
        bad = _synthetic("bed", 6, 50.0, 4.05, 20.0, 1) + _synthetic("mid", 6, 6.0, 4.08, 22.0, 7) + _synthetic("lure", 6, 3.0, 4.10, 25.0, 13)
        write_csv(d / "inband.csv", good)
        write_json(d / "inband.json", good)
        write_csv(d / "outband.csv", bad)
        (d / "badheader.csv").write_text("id,hookMode\nx,bed\n", encoding="utf-8")
        cases = [
            ("in-band CSV", [str(d / "inband.csv")], 0),
            ("in-band JSON", [str(d / "inband.json")], 0),
            ("out-of-band CSV (bed hoverS 50 s)", [str(d / "outband.csv")], 1),
            ("bad header", [str(d / "badheader.csv")], 2),
        ]
        for label, files, want in cases:
            proc = subprocess.run([sys.executable, "-I", script, *files, "--bands", str(bands)], capture_output=True, text=True)
            ok = proc.returncode == want
            results.append(ok)
            print(f"  {'ok  ' if ok else 'FAIL'} selftest: {label}: exit {proc.returncode} (want {want})")
            if not ok:
                print(proc.stdout)
                print(proc.stderr, file=sys.stderr)
    if all(results):
        print(f"selftest: PASS {len(results)}")
        return 0
    print(f"selftest: FAIL {results.count(False)} of {len(results)}")
    return 1


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
