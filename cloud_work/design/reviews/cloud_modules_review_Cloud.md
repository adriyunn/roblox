# Review: cloud modules (TackleBox, SpeciesTable, GameData, CatchLog, EncounterLog, EncounterReplay, WorldClock, SaveData, parity_report.py, RobloxStub)
Reviewer: Cloud (adversarial review session), 2026-10-07 05:20 UTC
Reviewed: branch claude/hello-b2aghd, commit a1c3185 (cloud_work/src/Fishing/Shared/{TackleBox,SpeciesTable,GameData,CatchLog,EncounterLog,EncounterReplay,WorldClock}.lua, src/Fishing/Server/SaveData.lua, tools/parity_report.py, tests/RobloxStub.luau)
Base: n/a (first review of new files; a WIP checkpoint 4a1ee92 landed mid-review and carries the first three fixes below)
Design note: none yet for WS-T / WS-S / WS-E / WS-L; design/WSP_parity_log.md and design/WSS_savedata.md (notes written in parallel); rulings applied: none

Method: six-lens find/refute. Every candidate was reproduced with a small Luau snippet run under the Luau CLI (or
python3 -I for the tool) against the RobloxStub before it was kept; candidates that did not reproduce were dropped
(the WorldClock transition sums are identical in every addition order; CatchLog.merge is commutative and
associative under exact best-length ties; the Python csv reader survives a quoted id with a newline). Every kept
finding is fixed with a minimal change and one regression check labelled `R<n> (F<id>)` in the module's suite; each
check was run against the a1c3185 modules and fails there (savedata_test FAIL 6 of 103, the others FAIL 1 each;
worldclock R4c hangs the old code instead of failing, which is the bug). F14 was left open as design-level at
review time and is fixed in the follow-up pass at the end of this file (savedata_test R9a-R9c).

## Verdict
FIXES (overall): WorldClock and SaveData each had at least one `must`; all `must` and `should` findings except F14
are fixed in this pass (F14 in the follow-up pass below), so what Dev1 re-reviews is the fixed hunks, not the modules.

| Module | Verdict | Decides it |
|---|---|---|
| TackleBox | ACCEPT WITH FIXES | F1 should (fixed, R1); N1 |
| SpeciesTable | ACCEPT WITH FIXES | F2 should (fixed, R2); N2 |
| GameData | ACCEPT | nothing reproduced beyond N3 |
| CatchLog | ACCEPT WITH FIXES | N4 only (header claim corrected); merge algebra and deserialize hold |
| EncounterLog | ACCEPT WITH FIXES | F5 should (fixed, R7); N5 |
| EncounterReplay | ACCEPT WITH FIXES | F3 should (fixed, R3); N6 |
| WorldClock | FIXES | F4 must (fixed, R4a-c): three ways to hang Heartbeat, one from a save |
| SaveData | FIXES | F8, F9, F12 must (fixed), F10, F11, F13 should (fixed), F14 should (fixed in the follow-up, R9a-c); N8 |
| parity_report.py | ACCEPT WITH FIXES | F6, F7 should (fixed, R8a-b); N9 |
| RobloxStub | ACCEPT | N10 (fidelity nits; three pre-existing analyze warnings, unchanged) |

## Findings
File:line is in the reviewed a1c3185 file. "Fix asked" is the fix made unless marked open.

| Id | Severity | File:line | Claim | Reproduced by | Fix asked |
|---|---|---|---|---|---|
| F1 | should | Shared/TackleBox.lua:338, :362 | deserialize accepts an id or nextId of 2^53; there nextId += 1 is a no-op, so two place() calls returned the same id 9007199254740992, items() listed 1 item while freeCells said 46, and check() failed after the first place | snippet: deserialize({w=8,h=6,nextId=2^53,items={}}) then two place(); tacklebox_test R1 | TackleBox.MAX_ID = 2^31; deserialize refuses "bad id" above it and errors "bad nextId" above it |
| F2 | should | Shared/SpeciesTable.lua:165 | one sigma for the whole min..max span puts the edges at unequal distances (trout: min 2.97 sigma, max 2.02 sigma), so 2,220 of 100,000 seeded trout clamp to exactly 0.55 m (every 45th fish a 30-coin trophy); the SIGMAS comment promises 2.5 each side | 100,000-draw count with the suite's LCG(12345); speciestable_test R2 | one sigma per side of the median (max and min both at SIGMAS/2 sigma); the count is now 650 (0.65%) per side |
| F3 | should | Shared/EncounterReplay.lua:185 | Player.step updates _now after delivering, so a surplus expectOut raised from inside the sink is stamped with the previous step's time (0.5 instead of 1.0) and the report names the wrong moment | snippet: sink calls expectOut on "Press"; encounterreplay_test R3 | move the _now update before the delivery loop |
| F4 | must | Shared/WorldClock.lua:121, :127, :135, :241 | advance() loops forever on dt = inf, on dayLengthS = 0 (which deserialize accepts from a save; a string dayLengthS errors in Heartbeat instead) and on WeatherMinS = WeatherMaxS = 0; the header says a corrupt save cannot freeze the day, and it can | three snippets under `timeout 5` (exit 124 each); worldclock_test R4a, R4b, R4c | day wrap by floor arithmetic; assert dt finite; new()/_rollLength refuse non-positive lengths; deserialize validates dayLengthS, weatherLeftS, rain, rainNow; MAX_ROLLS caps one call at 1000 weather rolls |
| F5 | should | Shared/EncounterLog.lua:141 | log.records has no cap: 1,005 finishes keep 1,005 records with their full event lists, so a server with the logger left on grows without bound (reported by the WSP_parity_log notes) | snippet with 1,005 start/finish pairs; encounterlog_test R7 | EncounterLog.new({ maxRecords = n }) (default DEFAULT_MAX_RECORDS = 1000); the oldest drops, log.dropped counts |
| F6 | should | tools/parity_report.py:89 | a UTF-8 BOM before the header (what Notepad writes when Adrian pastes the CSV) fails the header check with '﻿id' and exits 2 | python3 -I on a BOM-prefixed copy of the fixture; parity_report_test R8a | read with encoding utf-8-sig |
| F7 | should | tools/parity_report.py:108 | a JSON record that is not an object (`{"v":1,"records":[1]}`) or a "records" that is not a list tracebacks (AttributeError) and exits 1, not the documented 2 | python3 -I on both files; parity_report_test R8b | InputError for a non-list records and a non-object record |
| F8 | must | Server/SaveData.lua:226, :370 | a save that is retrying (UpdateAsync failed once, 1 s backoff) while release() runs re-plants our _lock after the player is gone, so the player is "locked" on every other server for lockStaleS (30 min) | stub: failNext UpdateAsync, release at +0.5 s, store _lock.jobId == job-A afterwards; savedata_test R5a | release() sets p.locked = false before its UpdateAsync; the save transform cancels when p.locked is false and save() returns false, "released" |
| F9 | must | Server/SaveData.lua:313, :384 | a player who leaves while load() is retrying gets an orphan tracked profile holding the lock until server close (onPlayerRemoving ran first and found "not-loaded"); other servers see "locked" | stub: failNext GetAsync, onPlayerRemoving at +0.5 s, loadedUserIds = {2}, store locked; savedata_test R5b | onPlayerRemoving marks _left while a load is in flight; the load then unlocks and returns nil, "left" |
| F10 | should | Server/SaveData.lua:227 | the claim is not compare-and-set: a record written by another server between our GetAsync and our UpdateAsync (its whole load/save/release inside our 1..15 s retry window) is overwritten with the stale data we hold (store coins 10, the other server's 100 lost) | stub: failNext UpdateAsync, store rewritten at +0.5 s; savedata_test R5c | the claim transform compares old._savedAt with the _savedAt GetAsync returned and refuses (nil, "locked") on a change; the retry loads the fresh record |
| F11 | should | Server/SaveData.lua:262 | two load() calls in flight for one player (rejoin during a retrying load) both claim: two profile objects, _order = {4, 4}, the first caller holds a profile that is never saved | stub: failNext GetAsync, second load at +0.5 s; savedata_test R5d | an in-flight guard: the second call returns nil, "loading" |
| F12 | must | Server/SaveData.lua:87 | set() accepts what the save refuses: set("bag.2", x) on an empty bag (sparse), set("x", 0/0), a function, or set("bag.1", nil) of two (a hole) each make every later save of the whole profile fail ("not JSON-safe") or, for the hole, store the array shifted; 50 coins set before were never written | stub: three set() shapes then save(); savedata_test R5e | set() validates the value (finite numbers, strings, booleans, string-keyed or 1..n tables, 32 deep) and the resulting parent keys, restores and errors at the call site |
| F13 | should | Server/SaveData.lua:406, :291 | _lock.t is refreshed only by a write and autosave skips clean profiles, so a connected idle player's lock is stale after lockStaleS and a second SaveData (job-B) took it over at 1900 s (reported by the WSS_savedata notes) | stub: load, startAutosave, advance 1900 with no set(), job-B load returned "loaded"; savedata_test R6 | the autosave tick force-saves a clean locked profile ("heartbeat") when now - savedAt >= lockStaleS/2; 2 saves in 1900 s, job-B now gets "locked" |
| F14 | should | Server/SaveData.lua:391, :162 | flushAll("close") is sequential and each profile pays the budget wait (1+2+4+8+16 = 31 s) plus the retries (15 s) twice (save, release); three dirty profiles under a zero budget took 276 s of fake time and saved 0; BindToClose allows 30 s | stub: budget = 0 for 1000 s, flushAll on three dirty profiles; savedata_test R9a-R9c | fixed (follow-up pass): flushAll marks the service closing (load returns nil, "closing", also for a load that was in flight), runs one task.spawn per profile and waits on a counter, _call skips _waitBudget and caps attempts at opts.closeRetries (default 1) with opts.closeBackoffS (default 0.5) while closing, then releases every lock; returns saved, failed. R9a: the same three profiles now flush in 0.00 s of fake time (0 saved, 3 failed, honestly reported); R9b: a load after flushAll is nil, "closing"; R9c: with budget all three save and every stored _lock is nil |
| N1 | nit | Shared/TackleBox.lua:271, :320 | items() and serialize() hand out the live item table (data by reference, shape copied only on place); mutating items(box)[1].item.shape breaks check() | snippet | copy the item in items() or document that callers must not mutate |
| N2 | nit | Shared/SpeciesTable.lua:216 | spawnWeight(id, NaN, d) returns 1 and spawnWeight(id, t, NaN) skips the depth gate (comparisons with NaN are false) | snippet | return 0 when either input is not finite |
| N3 | nit | Shared/GameData.lua:103 | priceFor(trout, 0.4, 1e308) returns inf (isNum passes, the product overflows); an inf coin value would now be refused by profile:set (F12) rather than silently poison the save | snippet | clamp the product or error on a non-finite result |
| N4 | nit | Shared/CatchLog.lua:12 | the header told SaveData to merge(local, remote) on a DataStore conflict; both sides share the ancestor, so 2 real catches merge to count 3 | snippet | header rewritten: merge adds DISJOINT logs; the session lock makes the conflict impossible (done) |
| N5 | nit | Shared/EncounterLog.lua:117, :44 | fightS is nil when the Caught/Snap/GiveUp cue is not also logged as an event (finish(t, outcome) alone does not count); log.active has no cap or timeout for a fish that despawns without finish | read | fall back to tEnd for fightS; add abandon(log, id) or finish on despawn |
| N6 | nit | Shared/EncounterReplay.lua:44, :132 | deepEqual({x=0/0},{x=0/0}) is false (NaN never matches itself); deserialize with entries given as a map yields an empty tape silently (ipairs) | snippet | treat NaN==NaN as equal in deepEqual; assert #entries == count of keys |
| N7 | nit | Shared/WorldClock.lua:185, :70 | the wave jumps from 0.084 to 0.05 at rain -> overcast (only rain is ramped) and never reaches WAVE_M.rain 0.1 because rainNow tops at 0.8; opts given to new() are not remembered by advance() (the test passes them twice) | snippet | ramp the wave from the previous weather's value; store opts on the clock |
| N8 | nit | Server/SaveData.lua:76, :210, :198 | get("") returns the whole data table; _write takes `now` before the retries, so _lock.t and _savedAt can lag by up to 46 s; a server whose os.time is more than lockStaleS behind lets its live lock be taken over (inherent to a time-based lock) | read | assert a non-empty path in get(); take `now` inside the transform; keep lockStaleS large and say so in the note |
| N9 | nit | tools/parity_report.py:58, :148 | "nan" and "inf" parse as numbers (median inf, band FAIL with a confusing row); a bool in a band passes the int/float check | python3 -I | reject non-finite numbers; exclude bool |
| N10 | nit | tests/RobloxStub.luau:147, :168 | jsonDecode drops a null inside an array ([1,null,3] -> {1,3}, later elements shift) unlike Roblox, and decodes "1-2" as nil without error; task.spawn runs synchronously; Signal.Once never disconnects | snippet | keep holes with an explicit index; stricter number pattern |

## Security (what a malicious client payload can and cannot do)
- TackleBox place/move/remove: the only client-sourced call is move(id, rot, x, y) (place and remove take server-built
  items and ids). Any non-number id, NaN, inf or a fraction is "no item" / "bad rotation" / "bad position"; x, y
  are integer- and bounds-checked, overlap is checked against every other item, and the id space is server-side
  (nextId), so a client cannot duplicate an item, place one it does not own, write outside its own box or break
  the grid invariant. It can spam moves; rate limiting is RequestGuard's job. A client-supplied item table must
  never reach place(): place() errors (not returns) on a malformed one.
- SaveData profile:set paths: set() must only ever take server-chosen paths and values. If a client string reached
  it, the client could write any key of its own profile (coins, gear) and, before F12, poison the profile so it
  never saved again (NaN, sparse array); after F12 that errors at the call site. _v, _lock and _savedAt in data
  are overwritten by _write, so a client cannot forge the schema version or the lock. Another player's record is
  unreachable: the key comes from player.UserId.
- EncounterReplay deserialize: every entry is type-, dir- and order-checked; a bad tape errors (assert) and
  touches nothing else. A hostile tape can only be large or deeply nested (deepCopy recursion ends in a Luau
  "stack overflow" error, not a crash). It is a dev/offline tool: never feed it a client payload in a live server.
- CatchLog deserialize: every field is typed and cross-checked (count >= 1, zones sum to count, bests agree with
  the catches, best catch is the same species). What it cannot know is whether the catches happened: a client-
  supplied log could claim any species and any length, so a log must only come from the player's own DataStore
  record. A huge count (1e300) is accepted and inflates totalCount; harmless for a server-built log.
- SpeciesTable brainConfig(base, id): a non-string or unknown id errors ("unknown species"), so the server handler
  must pcall or validate the id first; a known id applies only that row's validated numeric overrides to a clone
  of the base; the base is never mutated and no client value reaches the fish config.

## What was run
| Suite or check | Command | Result |
|---|---|---|
| gate | bash cloud_work/tests/run_all.sh | run_all: PASS (15 suites at 05:27 UTC; five are other agents' new suites, netschemav3_test among them, which failed 3 of 210 for a few minutes while its author was still writing and requires none of the reviewed modules) |
| catchlog | luau catchlog_test.luau | PASS 48 |
| encounterlog | luau encounterlog_test.luau | PASS 68 (+R7) |
| encounterreplay | luau encounterreplay_test.luau | PASS 66 (+R3) |
| gamedata | luau gamedata_test.luau | PASS 45 |
| robloxstub | luau robloxstub_test.luau | PASS 33 |
| savedata | luau savedata_test.luau | PASS 103 (+R5a-e, R6) |
| speciestable | luau speciestable_test.luau | PASS 53 (+R2) |
| tacklebox | luau tacklebox_test.luau | PASS 71 (+R1) |
| worldclock | luau worldclock_test.luau | PASS 40 (+R4a-c) |
| parity report test | python3 -I tools/parity_report_test.py | PASS 33 (+R8a-b; fixtures re-harvested from the Luau suite, unchanged) |
| parity selftest | python3 -I tools/parity_report.py --selftest | selftest: PASS 4 |
| parity on the sample | python3 -I tools/parity_report.py tests/fixtures/encounters_sample.csv --bands tools/parity_bands.json | parity_report: OK (8 bands) |
| syntax | luau-compile --null -O0/-O1/-O2 on every .lua/.luau under src/ and tests/ (in run_all) | compile done, 0 failures |
| types | luau-analyze on each of the eight modules | 0 errors, 0 warnings each (RobloxStub.luau: 3 pre-existing "could be nil" warnings, unchanged) |
| regressions on old code | a1c3185 modules swapped in, the new suites run | tacklebox FAIL 1/71 (R1), speciestable FAIL 1/53 (R2: 2222 clamped), encounterreplay FAIL 1/66 (R3), encounterlog FAIL 1/68 (R7), savedata FAIL 6/103 (R5a-e, R6), worldclock: R4a and R4b FAIL, R4c hangs (killed at 10 s), parity_report_test FAIL 3/33 (R8a, R8b, harvest) |
| line endings | python3 -I tools/check_lf.py cloud_work | check_lf: PASS |

## What was not checked
- Nothing ran in Studio: no real DataStoreService (the stub's UpdateAsync is synchronous and single-key; real
  request queuing between two coroutines, throttling and the 4 MB limit are not modelled), no real Players
  lifecycle (F9 relies on onPlayerRemoving being wired as the header says), no BindToClose timing (F14's 276 s is
  fake-clock time), no HttpService:JSONEncode (the stub refuses sparse and mixed tables; Roblox's exact behaviour
  on them was not verified, which is why set() now refuses both).
- No real FishingNet: the "client-reachable" analysis above is from the headers' integration notes, not from a
  handler; RequestGuard rate limits were not seen.
- Clock skew between servers beyond lockStaleS (N8) and a server crash mid-UpdateAsync are reasoned, not tested.
- The real C.AF.Fish key names for brainConfig (BRAIN_KEYS are the author's guesses) and the species numbers
  themselves (UNTUNED) are out of scope.
- Performance: scan() recomputes shapeCells per rotation per step; a 32x32 box with a 64-cell shape was not timed.
- Other agents' files that arrived during the review (Client/TackleBoxUI.lua, Client/CatchCard.lua,
  Shared/NetSchemaV3.lua and their suites) were not reviewed; their suites pass in the gate.

## API changes (no public function renamed; every caller in cloud_work checked by grep: none outside the suites)
- EncounterLog.new(opts?) takes { maxRecords } (default 1000); Log gains maxRecords and dropped; records() now
  holds at most maxRecords, so a parity export after more than 1000 encounters is the last 1000 (dropped says how
  many are gone).
- SaveData: load() can also return nil, "loading" or nil, "left"; save() can return false, "released";
  profile:set() errors on a JSON-unsafe value or shape instead of accepting it; onPlayerRemoving must be called
  even while a load is in flight (it was documented that way). Internals: _write(p, claiming, expectSavedAt),
  _loadInner, _unlock.
- TackleBox.MAX_ID (2^31): deserialize refuses larger ids / nextId.
- WorldClock.new, advance, _rollLength and deserialize now error (assert) on non-positive or non-finite config
  instead of hanging; advance() rolls at most MAX_ROLLS = 1000 weather states per call.
- parity_report.py reads UTF-8 with or without a BOM; exit 2 on a non-object record.

## Reply line for the Coordinator
REVIEW cloud_modules a1c3185 by Cloud (CLOUD): FIXES; F4, F8, F9, F12 must (fixed), F1-F3, F5-F7, F10, F11, F13 should (fixed), F14 should (fixed in the follow-up pass: parallel flushAll, R9a-c); N1-N10 nits (see the follow-up pass); suites 15/15 (run_all PASS, 560 checks in the ten reviewed suites, 15 new R checks that fail on a1c3185); design/reviews/cloud_modules_review_Cloud.md

## Follow-up pass (Cloud, 2026-10-08): F14 and the nits
Same method: each change is minimal and carries one labelled check that was run against the pre-change module
and fails there (noted per item). Nothing public was renamed; flushAll gained a second return value (failed),
which a caller taking one value never sees.

| Id | Fixed | Change | Check (suite) |
|---|---|---|---|
| F14 | yes | flushAll: `_closing` flag (load -> nil, "closing", also for a load in flight at either DataStore call), one task.spawn per profile + a done counter, _call skips the budget wait and uses opts.closeRetries (1) / opts.closeBackoffS (0.5) while closing; returns saved, failed | R9a (276.00 s -> 0.00 s of fake time under budget 0), R9b, R9c (savedata_test) |
| N1 | yes | TackleBox.items() returns a copy per entry (shape by value, `data` by reference); serialize() documents the same sharing | N1 (tacklebox_test): mutating items(box)[1].item.shape no longer breaks check() |
| N2 | yes | SpeciesTable.spawnWeight returns 0 for a NaN or infinite time or depth (isNum moved above it) | N2 (speciestable_test) |
| N3 | yes | GameData.priceFor errors when the product overflows to inf (a finite 1e308 kg; inf itself was already refused by isNum) | N3 (gamedata_test) |
| N4 | already | the CatchLog header was rewritten in the review pass; nothing left | none |
| N5 | part | EncounterLog fightS falls back to the finish time when the Caught / Snap / GiveUp cue was not logged as an event. Not done: a cap or abandon() for log.active (a fish that despawns without finish): that needs the FishPool despawn hook and a design decision, so it stays in the WSP note | N5 (encounterlog_test) |
| N6 | yes | EncounterReplay.deepEqual treats two NaN leaves as equal; deserialize refuses entries given as a map instead of yielding an empty tape | N6a, N6b (encounterreplay_test) |
| N7 | yes | WorldClock: a `waveNow` field ramps toward WAVE_M[weather] at the rain's pace from wherever it was, so no weather change jumps the surface and rain reaches 0.1 (serialize/deserialize carry it; a save without it starts at its weather's amplitude); new()'s opts are kept on the clock (`_opts`) so advance() and waveAmplitudeM() use them when not handed opts | N7a, N7b (worldclock_test) |
| N8 | part | profile:get("") errors "empty path" like set() does (read profile.data for the whole table); the clock-skew caveat is in the header (lockStaleS stays 30 min). Not changed: `now` is still taken before the retries (a lag of up to 46 s against an 1800 s stale window changes nothing) | N8 (savedata_test) |
| N9 | yes | parity_report.py: a "nan" / "inf" cell is an InputError (exit 2); a boolean or non-finite band edge is refused | N9 (parity_report_test) |
| N10 | part | RobloxStub: a null array element is a nil hole at its index like Roblox's JSONDecode (documented at the decoder: # of such a table is a border); "1-2" is a JSON error (mantissa and exponent matched apart); Signal.Once disconnects after one Fire; luau-analyze clean under both solvers (the three Instance.new warnings were a type cycle through the __index closure's rawget, cured with a cast; the other new-solver errors were missing return and self annotations). Not changed: task.spawn stays synchronous, which the suites rely on | N10a, N10b, N10c (robloxstub_test) |

Run on 2026-10-08: run_all PASS (18 suites: evidenceboard_test, schedule_test and ccr_digest_test are other agents' new suites);
savedata_test 107, tacklebox_test 72, speciestable_test 54, gamedata_test 46, encounterlog_test 69, encounterreplay_test 68,
worldclock_test 42, robloxstub_test 36, parity_report_test 34. Every R9 and N check was also run against the HEAD (df2ab2b)
modules, stub and parity report: all 15 fail there (R9a reports 276.00 s). luau-analyze (default solver) is clean on every
module under src/ and on the stub; the stub is also clean under --solver=old.
