Written by Cloud (session roblox-9d) on 2026-10-07 without access to the project files;
the modules `cloud_work/src/Fishing/Shared/EncounterLog.lua`, `EncounterReplay.lua`, the tool `tools/parity_report.py` and their suites are real and pass here (PASS 67, 65, 31). Every claim about where FishingServer sends its cues, the FishingNet v2 codec and the dev verbs is from the transcripts and must be checked by Dev1 (the server call sites) and Dev3 (the net taps, the gate) against the real files.

# WS-P: the parity log, the replay tape and the report (number source for X60, X63, X66)

```
WS-P parity_log (About Fishing F1; Cloud, 2026-10-07; rev 1)
Status: FOR RULING (rulings 1-3)
```

## Lead
Every fish-angler encounter becomes one record of measured seconds and counts; a Python report compares the medians per hook mode with bands and exits non-zero when one is out; a net tape lets a reviewer replay an encounter offline and see the first message that differs.
When it is right the feel review argues with numbers, and "the trout feels slow" becomes "bed hoverS median 31 s against 5-45".

## Reference behaviour
| Claim | Source | Ref | Value |
|---|---|---|---|
| the fish hovers over a bed-resting hook before it takes | X01 ruling (team) | `design/X01_BedSightLift_draft.md` row X01-1 | median first Swallow in 5-45 s |
| notice to first nip | F1 measured | CONTEXT.md (FishBrain) | 4.083 s |
| cooldown between charges | F1 measured | CONTEXT.md (FishBrain) | U(4, 5) s |
| per-species timings (notice to first nip, nips before the take) | preview (UNVERIFIED) | RECORD IN DEMO: V68 | per species, against the trout's 4.083 s |
| night vs day approach and nip timing | preview (UNVERIFIED) | V55 | the same numbers by phase |
| hook set to snap when the player does nothing | preview (UNVERIFIED) | V45 | seconds; feeds `fightS` and X63 |

## Our rule
- One encounter = one fish engaging one angler, id `anglerId .. ":" .. fishId .. ":" .. tNotice` (MP_stress_test.md). FishingServer calls `EncounterLog.start(log, id, { anglerId, fishId, speciesId, hookMode, t })` where it sends the Notice cue (`t` = the Notice time, `hookMode` = `bed | mid | lure` from the hook state, else `start` errors), `event(log, id, name, t, data)` where it sends each cue (`Nip`, `Swallow`, `Hooked`, `Jump`, `Snap`, `Caught`, `GiveUp`, `Spook { reason }`, `Leave`), where it receives the press (`Press`) and where FishJudge rules (`Verdict { verdict }`), and `finish(log, id, t, outcome)` where the fish is Caught, Snap, GiveUp, Leave or Spook. All times on one clock (`os.clock()` or `workspace:GetServerTimeNow()`); only differences matter.
- Derived numbers (`finish`): `noticeToFirstNip` = first Nip - Notice; `hoverS` = (first Swallow or first Leave) - Notice; `pressOffset` = first Press - first Swallow; `verdict` = the first Verdict event's `data.verdict`; `fightS` = (first Caught, Snap or GiveUp) - first Hooked; `jumps`, `spooks` = counts of those events. A missing input leaves the number nil (a Leave has no `pressOffset`, no `fightS`).
- Export: `toCsv(records)` with the fixed header `id,anglerId,fishId,speciesId,hookMode,outcome,tNotice,tEnd,noticeToFirstNip,hoverS,pressOffset,verdict,fightS,jumps,spooks` (seconds with 3 decimals, counts as integers, nil empty, LF endings), or `HttpService:JSONEncode(toTable(records))` = `{ v = 1, fields, records = [ ...the same fields, plus events ] }`. `EncounterLog.CSV_HEADER` and `parity_report.CSV_HEADER` are tested equal; a dev who changes one changes both.
- Summary and bands: `summary(records, metric)` gives n, min, median (even n: the mean of the middle two), p95 (nearest rank, `ceil(0.95 n)`), max, mean. `bands(records, table)` is OK when `n >= 5` and `lo <= median <= hi`, one row per (hookMode, metric), sorted. The bands in `tools/parity_bands.json`: bed `hoverS` 5-45 s (X01 ruling), bed and mid `noticeToFirstNip` 3.5-4.5 s (F1's 4.083 s, +-0.5 s), `fightS` 5-60 s (placeholder), mid `hoverS` 2-20 s (placeholder, ruling 1); lure has no hover band because a retrieved lure does not hover.
- The report: `python3 -I tools/parity_report.py <csv|json> [more] [--bands parity_bands.json] [--skip-empty]` prints the record counts per hookMode and a fixed-width table (n, median, p95, lo, hi, OK/FAIL/SKIP, reason). Exit 0 = every band OK or SKIP, 1 = any FAIL, 2 = bad input (unknown header, bad JSON, a band on a non-numeric field, a missing file, no files). A hookMode with no records fails unless `--skip-empty`. `--selftest` proves exits 0, 1 and 2 on synthetic sets. It is the parity gate's number source (HANDOFF item 17).
- The tape (`EncounterReplay`): a `Recorder` taps one side's messages; `rec:tap("out", channel, payload)` just before a remote fires and `rec:tap("in", channel, payload)` at the top of the `OnServerEvent` / `OnClientEvent` handler after the v2 codec decodes; `channel` is the remote or cue name (`Cue/Notice`, `Press`), the payload the decoded JSON-safe table, copied at tap time. Tap one side only. `stop()` gives the tape `{ v = 1, t0, entries = { { t (relative), dir, channel, payload } }, dropped }`; the buffer is a ring of 10,000 entries, the oldest dropped and counted. `serialize` / `deserialize` make it JSON-safe; another `v` is refused.
- The dev verb `RecordEncounter` (dev-only, like `SpawnVisibleFish`) makes a Recorder at the cast, stops it at the catch scene and writes `JSONEncode(serialize(tape))` to a StringValue or the output for Adrian to copy into `evidence/`.
- How a reviewer uses a tape: `Player.new(tape, sink)` with `sink(channel, payload)` calling the handler under test; `player:step(t)` at each time of interest delivers the "in" entries up to `t`, never early; where the handler would fire a remote, `player:expectOut(channel, payload)` checks it against the next recorded "out" (channel and deep-equal payload); `player:report()` gives delivered, matched, mismatched, pending, and every mismatch with the recorded `t`, channel, expected and got. The first mismatch's `t` and channel is the finding.
- Privacy: records and tapes carry `anglerId` only: FishingServer passes `player.UserId` or the session's angler index, never `Name` or `DisplayName`; the v2 payloads are numeric ids, so a tape holds no name either. Exports stay in `evidence/`, never published.
- Gap found: `log.records` has no cap; on a long-lived server it grows one record per encounter. Dev1 caps it (drop the oldest beyond `MaxRecords`, ruling 3) before it is always on.

## Config keys
| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `MIN_N` | `parity_report.py`, hard-coded 5 in `EncounterLog.bands` | records | 5 | 5-20 | a median of fewer is noise (ruling 2) |
| bands | `tools/parity_bands.json` | s per (hookMode, metric) | see Our rule | lo <= hi | the X01 and F1 numbers; placeholders marked |
| `maxEntries` | `Recorder.new(clock, maxEntries)` | entries | 10,000 | >= 1 | one encounter is a few hundred messages; a ring bounds memory |
| `MaxRecords` (proposed, ruling 3) | `EncounterLog` | records | 1,000 | 100-10,000 | bounds a server's memory; export before it rotates |
| `ParityLog` (proposed, ruling 3B) | `C.AF.Dev` | bool | true | | whether the server logs encounters |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none | `StateRules` |
| Cues | none new; the log reads the cues the server already sends; the tape taps the existing remotes. `RecordEncounter` is a dev verb, not a player message | `FishingServer`, `FishingNet`, `FishingNetClient` |
| Guard rules | none; `RecordEncounter` is refused outside Studio or for a non-dev | the dev-verb gate |
| Wire size | +0 B | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/EncounterLog.lua`, `EncounterReplay.lua` | new, as in `cloud_work/src`; the records cap | Dev1 | Dev3 |
| `Fishing/Server/FishingServer.lua` | `start` at Notice, `event` at each cue, press and verdict, `finish` at the outcome; the export and `RecordEncounter` verbs | Dev1 | Dev3 |
| `FishingNet`, `FishingNetClient` | one `tap` on the send path and one at the top of the receive handler, behind the recorder being present | Dev3 | Dev1 |
| `tools/parity_report.py`, `tools/parity_bands.json`, `tools/parity_report_test.py` | adopt; the gate calls the report and fails on exit 1 | Dev3 | FableDev |
| `tests/encounterlog_test.luau`, `tests/encounterreplay_test.luau`, `tests/fixtures/encounters_sample.{csv,json}` | adopt as is | Dev3 | Dev1 |
| `PARITY_CHECKLIST.md`, `README.md` | the evidence column of X60, X63, X66 points at the report | Dev3, WordAgent | Coordinator |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/encounterlog_test.luau` | a full encounter's numbers written out (4.083, 12.5, 0.2, 27.5, 2 jumps, 1 spook); a Leave with nil press and fight; even-n median and nearest-rank p95 on 1..20; bands OK, out of band, n < 5, sorted rows; CSV header, cells, quoting, LF; `toTable` JSON round trip; the 20-record sample passes every default band and is printed between FIXTURE markers | `event` on an unknown id errors; also `finish` unknown, a duplicate `start`, hookMode `surface`, a band with lo > hi | `PASS 67` |
| `tests/encounterreplay_test.luau` | relative times and copied payloads; a JSON round trip equal to the tape; `step` delivers in order and never early; `expectOut` matches and diffs with `t` and channel; a surplus out; `pendingOut`; the ring drops the oldest two and counts; `deepEqual` arrays vs maps | `deserialize` of a `v = 2` tape errors; a bad `dir`; entries out of time order | `PASS 65` |
| `tools/parity_report_test.py` | `--selftest` exits 0 with exits 0 / 1 / 2 seen; the Luau fixtures (harvested from the suite above, so writer and reader meet on the same bytes) give 8 OK rows, bed `noticeToFirstNip` median 4.083, identical tables from CSV and JSON, two files merge; tightened bands exit 1; an unknown hookMode fails or SKIPs; a bad header, a missing file, a bad band, no files exit 2 | the real export with mid `hoverS` pushed to 30.000 fails the 2-20 band and only that band | `PASS 31` |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | five bed encounters on the sandbox lake, export CSV, run the report | 3 bed rows: `noticeToFirstNip` median about 4.083 OK; `hoverS` and `fightS` OK; mid and lure FAIL on n or SKIP with `--skip-empty` | the table in `evidence/WSP/` |
| 2 | a Late press | the record has `verdict` Late, `spooks` 1; the fight numbers nil | the CSV row |
| 3 | `RecordEncounter`, one full catch, copy the tape | a `v = 1` tape with Notice..Caught as "out" and Cast, Press as "in", `dropped` 0 | the JSON in `evidence/WSP/` |
| 4 | replay the tape against FishingNetClient's handler offline | `report()` with 0 mismatches on the same build; a changed cue payload names its `t` and channel | the suite output |

## Rulings needed
1. Mid-water bands.
   - A: keep mid `hoverS` 2-20 s as a gating placeholder. Cost: none. Fidelity: a guess gates a feel.
   - B: drop `mid.hoverS` from `parity_bands.json` until 5 measured mid encounters (Studio or V-clips) set it; keep mid `noticeToFirstNip` and `fightS`. Cost: one line. Fidelity: no false gate.
   - Recommendation: B.
2. Minimum n per band.
   - A: 5, as built in both the Luau and the Python. Cost: none; one Studio session gives 10-20 encounters. Fidelity: n/a.
   - B: 10 for the gate, 5 printed for information. Cost: longer sessions; two thresholds to keep aligned. Fidelity: n/a.
   - Recommendation: A now, B when the 8-angler stress run supplies the numbers.
3. Logging always on or behind a dev flag.
   - A: always on on the server with `MaxRecords` 1,000 and an export verb; tapes stay dev-only. Cost: about 15 numbers plus the event list per encounter in memory; one cap. Gain: numbers from real play.
   - B: `ParityLog` flag, off outside Studio and the feel review. Cost: a flag; no numbers from live servers. Gain: zero cost in production.
   - Recommendation: A with the cap.

## PARITY rows
This note adds no mechanic; it is the evidence column for the rows below (and proposes X69, open question 1).

| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| X60 species behaviour patterns | per species (V68); trout 4.083 s | `bed.noticeToFirstNip` 3.5-4.5 s per species once V68 sets the bands | planned | `parity_report.py` exit 0 |
| X63 second catch step | hook set to snap (V45) | `fightS` and the Snap outcome per hook mode | planned | the `fightS` band |
| X66 day/night behaviour | night timings (V55) | the same bands split by WorldClock phase (a `phase` column, X69) | planned | the report by phase |

## Open questions
- A row X69 "parity numbers from play" (the next free id in PARITY_rows_F2plus.md): the report exit 0 on a live export as an acceptance test, and a `phase` column for X66 (Dev3, when merging the rows).
- Where the server's clock for `t` comes from: `os.clock()` on the server or `workspace:GetServerTimeNow()`, one choice for every call site (Dev1).
- Whether the press is logged at receipt on the server or at the client's stamped time (the LatencyBudget value), which changes `pressOffset` by the one-way latency (Dev1 with Dev3).
- The `Spook` outcome: `finish` on a Spook or keep the encounter open for the fish's return (Dev1; the MP Z4 row expects one cue per Late press).
- Who runs the report in the gate and where the live exports land (`evidence/parity/<date>.csv`) (FableDev, with the CI workflow).
