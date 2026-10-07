Written by Cloud (session roblox-9d) on 2026-10-07 without access to the project files;
the module `cloud_work/src/Fishing/Shared/CatchLog.lua` and `tests/catchlog_test.luau` are real and pass here (PASS 48). Every claim about CatchSceneView, FishZones, the day clock and the net layer is from the transcripts and must be checked by Dev1 (server wiring), Dev2 (CatchSceneView cues, the log screen) and Dev3 (net, guard) against the real files.

# WS-L: the catch log (P08)

```
WS-L catchlog (About Fishing F1; Cloud, 2026-10-07; rev 1)
Status: FOR RULING (rulings 1-2)
```

## Lead
The server records every catch in a per-player `CatchLog` (count, first, best length, best weight, per-zone counts) and tells the catch scene when it is a first or a record; the client reads all of it and writes none of it.
When it is right the player sees "New species!" or "New record!" on the card the moment the fish comes up, and the log screen lists species in the order they were first caught.

## Reference behaviour
Not confirmed in the previews: the demo may have a species list or record screen. UNVERIFIED until Adrian records V70 (menu tour) and V50 (size display).

| Claim | Source | Ref | Value |
|---|---|---|---|
| a log or records screen exists | preview (UNVERIFIED) | RECORD IN DEMO: V70 | which screens exist: log, records, catch card |
| the catch card shows a size | preview (UNVERIFIED) | V50, V68 | the units shown (cm, in, kg, lb) |
| fish come in sizes per catch | preview (UNVERIFIED) | V50 | size display per catch |

## Our rule
- `CatchLog.record(log, catch)` takes `{ speciesId, lengthM, weightKg, zoneId, dayN, timeOfDay, lureId }` (every field checked; a bad catch errors and changes nothing), copies it in, and returns `{ isFirst, isLengthRecord, isWeightRecord, countNow }`. A first catch is both records. Length and weight records are independent (a longer, lighter fish sets the length record only); an equal length is not a record (strict greater). The best-length catch is kept whole (`bestLengthCatch`: zone, lure, day, time).
- Per species: `count`, `first` (`dayN`, `timeOfDay`, `zoneId`, `lengthM`), `bestLengthM`, `bestWeightKg`, `bestLengthCatch`, `zones` (zoneId -> count). `summary(log)` gives `speciesCount`, `totalCount` and one row per species in first-catch order (the `order` array; `merge` sorts by first day, time, then id).
- Cues: FishingServer calls `record` at CatchScene entry and sends the result's flags with the catch cue; CatchSceneView shows "New species!" on `isFirst`, else "New record!" on `isLengthRecord` or `isWeightRecord`, else nothing. The text is GameOne's own.
- Save form: `serialize(log)` is `{ v = 1, totalCount, species = { { id, count, first, bestLengthM, bestWeightKg, bestLengthCatch, zones } } }` in first-catch order. `deserialize` re-checks every record (non-empty id, no duplicate, `count >= 1`, the first's fields, lengths and weights > 0, the best catch is the same species and its length equals `bestLengthM`, `bestLengthM >= first.lengthM`, `bestWeightKg >= bestLengthCatch.weightKg`, zone counts >= 1 and adding up to `count`) and errors naming the species. SaveData calls it in `pcall`.
- Merge on a save conflict: `merge(a, b)` adds counts and zones, keeps the earlier first, the larger bests (an exact tie broken by a total order on catches), and returns a new log; it is commutative, leaves both inputs untouched, and merging with an empty log is the identity. SaveData's `UpdateAsync` transform uses it when two servers' versions meet (WSS_savedata.md); today the session lock makes that rare, so `merge` is the safety net, not the path.
- What the client may read: everything (`summary` and the per-species records go to the owner as `CatchLogSync` after each change, or whole on join). What it may write: nothing; there is no client verb that touches the log.
- Units: the log stores metres and kilograms (the simulation's units; a stud is a bug). Display conversion happens in the client view only (ruling 1).
- `dayN` and `timeOfDay` come from WorldClock (`dayN`, `timeOfDay(clock)`), `zoneId` from FishZones, `speciesId` from SpeciesTable; the log checks none of them against those modules so it stays decoupled.

## Config keys
| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `VERSION` | `CatchLog` | int | 1 | fixed | the save form's shape; a change is a SaveData migration |
| `LengthUnit` (proposed, ruling 1) | `C.Options` (WSH_options_panel_additions.md) | enum | `cm` | `cm`, `in` | display only; the log stays in metres |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none; the log screen opens in Walking and Holding only, like the box | `StateRules` row `LogOpen` (client-only if the view needs no server message) |
| Cues | the catch cue carries three flags (`isFirst`, `isLengthRecord`, `isWeightRecord`); proposed `CatchLogSync(summary)` server -> client, owner only, on join and after each catch. Proposed, defined in `design/WSN_net_v3_messages.md` (a sibling is writing it) | `FishingNet` v3, `FishingNetClient` |
| Guard rules | none new; no client verb exists for the log | `RequestGuard` |
| Wire size | +1 B on the catch cue (three flag bits); `CatchLogSync` about 12 B per species row (estimate, Dev3 sizes it) | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/CatchLog.lua` | new, as in `cloud_work/src` | Dev1 | Dev3 |
| `Fishing/Server/FishingServer.lua` | `record` at CatchScene entry; flags on the catch cue; `CatchLogSync` to the owner | Dev1 | Dev3 |
| `Fishing/Server/SaveData.lua` wiring | `log` field: `serialize` on save, `deserialize` in `pcall` on load, `merge` in the conflict transform | Dev1 | Dev3 |
| `Fishing/Client/CatchSceneView.lua` | the two cues on the card | Dev2 | Dev1 |
| `Fishing/Client/CatchLogView.lua` | new: the summary list in first-catch order; unit conversion | Dev2 | Dev1 |
| `tests/catchlog_test.luau` | adopt as is | Dev3 | Dev1 |
| `PARITY_CHECKLIST.md`, `README.md` | P08 in the module's names | Dev3, WordAgent | Coordinator |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/catchlog_test.luau` | first-catch flags; length and weight records tracked apart; an equal length is no record; the first stays the day-1 catch; zones count; the caller's table is copied; summary order per log; `record` refuses length 0, a missing species, 25:00, a fractional day; a JSON round trip serialises identically; `merge` adds counts and zones, keeps the earlier first and larger bests, orders by first (trout day 1, pike day 2, perch day 3), is commutative, leaves inputs untouched, identity with empty | seven tampered saves are refused naming the species: a negative count, a zero first length, a negative best, zones that do not add up, a best catch of another species, a duplicate id, a non-table | `PASS 48` |
| codec suite (Dev3) | the three flags survive the catch cue round trip; `CatchLogSync` decodes to the same summary | a mutant that drops `isWeightRecord` must FAIL | Dev3 names the count |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | catch the first trout of a fresh profile | "New species!" on the card; the log screen lists Trout, 1, its length | frames in `evidence/WSL/` |
| 2 | catch a shorter trout | no cue; count 2; best unchanged | the log screen |
| 3 | catch a longer trout | "New record!"; best length updates; the best catch names this zone and lure | the log screen |
| 4 | leave and rejoin | the same summary and order | `serialize` equality in the server output |
| 5 | catch in two zones | per-zone counts add up to the species count | the server's `zones` |

## Rulings needed
1. Display units.
   - A: centimetres and kilograms, whole cm, one decimal kg (0.40 m -> "40 cm", 0.704 kg -> "0.7 kg"). Cost: none; the log is metric. Fidelity: unknown until V50 shows the reference's units.
   - B: an option (`LengthUnit` cm / in) in the options panel, default cm. Cost: one options row, one conversion. Fidelity: covers either answer from V50.
   - Recommendation: A now, B if V50 shows inches; the log never changes either way.
2. Does a released fish count.
   - A: yes: `record` runs at CatchScene entry, before the box, so a fish let go in MakeRoom (WST_tacklebox.md ruling 1) or dropped later stays in the log and can set a record. Cost: none. Fidelity: the player did catch it.
   - B: only boxed fish count: `record` runs after `autoPlace` succeeds. Cost: the cue moves after MakeRoom; a trophy released for room is lost to the log. Fidelity: unknown.
   - Recommendation: A.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| P08 catch log | a species list or record screen, if any (V70) | `CatchLog` per player: count, first, best length, best weight, zones; firsts and records cued to the card; client read-only | staged (module), planned (wiring, view) | `tests/catchlog_test.luau` PASS 48 |
| P20 per-player save | single save in the reference | `serialize` / `deserialize` re-validated; `merge` for conflicts | staged | the round-trip and merge checks |

## Open questions
- Whether the reference has a log at all, and what it lists (Adrian, V70).
- The units on the reference's catch card (Adrian, V50).
- Whether the log screen is a tab of the box UI or its own screen (Dev2 with the UI mockup brief in SFX_ART_LIST.md).
- Which zone ids FishZones will expose for `zoneId` (Dev1; the log takes any non-empty string).
- Whether `CatchLogSync` sends the summary only or the per-species best catches too (Dev3, in WSN_net_v3_messages.md).
