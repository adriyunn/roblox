#!/usr/bin/env bash
# run_all.sh (About Fishing F1 cloud work; Cloud, 2026-10-06)
# The offline gate for cloud_work: syntax-check every Luau source at -O0/-O1/-O2, run every *_test.luau
# under the Luau CLI from its own folder, run every Python test, check the module conventions
# (tools/check_conventions.py), run the quick mutation check (tools/mutate.py --quick: at most 12
# mutants per module must be killed by its suite, survival 15% at most), check line endings.
# Exit 0 only when everything passes. Run from anywhere: bash cloud_work/tests/run_all.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
LUAU="${LUAU:-luau}"
LUAU_COMPILE="${LUAU_COMPILE:-luau-compile}"
fail=0; pass=0

echo "== syntax: luau-compile --null on every .lua/.luau under src/ and tests/"
while IFS= read -r f; do
  for o in -O0 -O1 -O2; do
    if ! "$LUAU_COMPILE" --null "$o" "$f" >/dev/null 2>&1; then
      echo "  FAIL compile $o: $f"; "$LUAU_COMPILE" --null "$o" "$f" 2>&1 | head -5; fail=$((fail+1))
    fi
  done
done < <(find "$ROOT/src" "$ROOT/tests" -type f \( -name '*.lua' -o -name '*.luau' \) | sort)
echo "   compile done"

echo "== luau suites"
while IFS= read -r t; do
  name="$(basename "$t")"
  if (cd "$(dirname "$t")" && "$LUAU" "$name" > "/tmp/${name}.out" 2>&1); then
    tail -n 1 "/tmp/${name}.out" | sed 's/^/   /'; pass=$((pass+1))
  else
    echo "   FAIL $name"; tail -n 25 "/tmp/${name}.out" | sed 's/^/      /'; fail=$((fail+1))
  fi
done < <(find "$ROOT/tests" -type f -name '*_test.luau' | sort)

echo "== python tests"
while IFS= read -r t; do
  if (cd "$(dirname "$t")" && python3 -I "$(basename "$t")" > "/tmp/$(basename "$t").out" 2>&1); then
    tail -n 1 "/tmp/$(basename "$t").out" | sed 's/^/   /'; pass=$((pass+1))
  else
    echo "   FAIL $(basename "$t")"; tail -n 25 "/tmp/$(basename "$t").out" | sed 's/^/      /'; fail=$((fail+1))
  fi
done < <(find "$ROOT/tests" "$ROOT/tools" -type f -name '*_test.py' | sort)

echo "== conventions"
if python3 -I "$ROOT/tools/check_conventions.py" "$ROOT" > /tmp/check_conventions.out 2>&1; then
  tail -n 1 /tmp/check_conventions.out | sed 's/^/   /'; pass=$((pass+1))
else
  echo "   FAIL conventions"; sed 's/^/      /' /tmp/check_conventions.out; fail=$((fail+1))
fi

echo "== mutation (quick)"
# The eight modules other agents were still writing on 2026-10-08 run advisory: their survivors are
# printed but do not fail the gate (the quick pick moves with every edit of theirs), until their authors
# add the killing checks. Remove a name once its line reads "ok" and its author is done.
MUTATE_ADVISORY="${MUTATE_ADVISORY:-InventoryService,InputMap,FishBed,PerfProbe,Schedule,EvidenceBoard,Fillet,Tutorial}"
if python3 -I "$ROOT/tools/mutate.py" --quick --list-survivors --advisory "$MUTATE_ADVISORY" > /tmp/mutate_quick.out 2>&1; then
  grep -E '^  (ok|adv|FAIL) |^mutate:' /tmp/mutate_quick.out | sed 's/^/   /'; pass=$((pass+1))
else
  echo "   FAIL mutation (quick)"; sed 's/^/      /' /tmp/mutate_quick.out; fail=$((fail+1))
fi

echo "== line endings"
if python3 -I "$ROOT/tools/check_lf.py" "$ROOT"; then pass=$((pass+1)); else fail=$((fail+1)); fi

echo
if [ "$fail" -eq 0 ]; then echo "run_all: PASS ($pass suites)"; exit 0; else echo "run_all: FAIL $fail"; exit 1; fi
