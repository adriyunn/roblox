Written by Cloud on 2026-10-08 without access to the project files;
every claim about the town place, FishPoolView's LOD, CatchSceneView and the box flow below comes from the team's transcripts and must be checked by Dev2 (the view), Dev1 (CatchLog wiring, SaveData) and Dev3 (PARITY P13, the net) against the real files. The cloud modules named (CatchLog, TackleBox, SaveData) are real in `cloud_work/src` and pass their suites. The demo clip is not recorded: both options stand until Adrian records it.

# WS-F: the aquarium (P13)

```
WS-F aquarium (About Fishing F1; Cloud, 2026-10-08; rev 1)
Status: DRAFT, FOR RULING (rulings 1-5); option A proposed for F3
```

## Lead
Option A: a place in the town with one tank per species the player has caught, filled from the catch log (the best-length fish, drawn with the v2 Blender models); no new save field, no new message. Option B: a home tank that holds live fish taken out of the tackle box; it waits for the box flow.
When it is right a player walks into the aquarium and sees their own best of every species idling behind glass with the length under it, and another player beside them sees theirs.

## Reference behaviour
The June 2026 demo added an aquarium; what it is for is UNVERIFIED until Adrian records V63 (the clip list's id; the kickoff brief called it V60-V61, the list wins).

| Claim | Source | Ref | Value |
|---|---|---|---|
| an aquarium exists | preview (UNVERIFIED) | RECORD IN DEMO: V63 | a place, or a tank you fill |
| a fish goes in from the box | preview (UNVERIFIED) | V63 (put a fish in, watch 20 s, take it out) | whether the fish leaves the box; capacity; whether it comes back |
| any benefit (money, record, display) | preview (UNVERIFIED) | V63, V70 (menu tour) | display only, or income |
| a catch log or records screen | preview (UNVERIFIED) | V70 | feeds P08; option A reads it |

## Our rule
Option A (proposed for F3), the gallery:
- A town place holds `AquariumTanksMax` (8) tank parts tagged `AquariumTank` (CollectionService) with a `TankIndex` attribute 1..8. The client fills them for the local player only: tank i shows species i of `CatchLog.summary(log).species` in first-catch order (the order the log already keeps), from the `CatchLogSync` image (WSN id 52) the client already receives. Other players' tanks are not drawn; two players in the room each see their own fish. Nothing is sent, nothing is saved: the log is the data.
- The fish shown is the best-length catch: the model `blender/exports_v2/fish_<speciesId>.fbx` scaled by `bestLengthM / SpeciesTable.ROWS[id].modelLengthM` (a new row field, the length the model was built at: trout 0.40, perch 0.25, pike 0.70, carp 0.50, minnow 0.08 m), clamped to `TankScaleMin..TankScaleMax` (0.5..2.0) so a 0.08 m minnow and a 1.2 m pike both fit a tank. A plaque under the tank shows the species name, best length (cm), count and first day: server-authored text from the sync, no filtering needed (ROBLOX_constraints.md section 5).
- Idle motion is client-only: a figure-of-eight inside the tank's bounds at `TankSwimMps` (0.15), the `TroutView.setBend` curve on the rigged trout, a straight glide on the others. No FishBrain, no FishPool, no server step.
- A species beyond the 8th tank is not shown; the plaque on tank 8 says how many more (ruling 5).
- Rendering budget: 8 models x 4,880-5,852 triangles (v2 set), under 47 k in all, one SurfaceAppearance each. The PERF note's client budget for FishPoolView is 0.5 ms per frame for 8 fish and the tanks run where no pool runs, so the same 0.5 ms is the ceiling under a label `AF_AquariumView`; LOD per PERF section 6.4: beyond `ViewClampLodM` 40 m the swim path updates every 0.5 s, beyond 80 m the models are not drawn. The room is small, so in practice every tank is near.
Option B (needs the box flow; not for F3), the live tank:
- A home tank with `TankCapacity` (6) slots; `TankMove(itemId)` takes a fish item out of `TackleBox` and into `SaveData.Aquarium` (the P20 schema already lists the field); `TankTake(slot)` puts it back when the box has room (`TackleBox.autoPlace`, else reason 7 as in the make-room flow); the fish keeps species and length; no feeding, no death, no income in F3 (ruling 4). Two C->S and one S->C message; Dev3 assigns ids in the 32..47 and 48..63 ranges (39 and 57 are the next free after `WSB_line_anchors.md`); the handlers join `Server/InventoryService.lua` (the cloud's v3 inventory glue); StateRules rows like the box's (Walking, Holding).
- B is built on A: the tank view is the same code reading a different list.

## Config keys
| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `AquariumTanksMax` | `C.View` | count | 8 | 1..16 | the v2 set has 5 species; 8 leaves room for F3 additions |
| `TankScaleMin`, `TankScaleMax` | `C.View` | ratio | 0.5, 2.0 | 0.25..4 | keeps every species inside a 1.2 m tank |
| `TankSwimMps` | `C.View` | m/s | 0.15 | 0..0.5 | a calm idle; pool fish swim faster, the tank should feel still |
| `modelLengthM` | `SpeciesTable.ROWS[id]` | m | per row | > 0 | the length each FBX was built at (`blender/README_v2.md`) |
| `TankCapacity` (B only) | `C.AF.Box` | count | 6 | 1..12 | V63 sets it |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | A: none (the room is Walking). B: `TankMove`, `TankTake` legal in Walking and Holding like `TackleMove` | `StateRules` rows |
| Cues | A: none; reads `CatchLogSync` (52). B: `TankMove` (C->S), `TankTake` (C->S), `TankSync` (S->C); Dev3 assigns the ids | `FishingNet` v3, `NetSchemaV3` |
| Guard rules | A: none. B: 2 / s, burst 4 each; drop and count | `RequestGuard` |
| Wire size | A: +0 B. B: 3 B per request; `TankSync` about 8 B per slot compact | `netschemav3_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Client/AquariumView.lua` | new: tank discovery by tag, the models, the plaques, the idle path, LOD, the `PerfProbe` label | Dev2 | Dev1 |
| `Fishing/Shared/AquariumLayout.lua` | new, pure: `assign(summary, tanksMax) -> { { tankIndex, speciesId, scale, plaque } }, overflow`; `scaleFor(id, bestLengthM)`; no Roblox globals, so the suite runs under the CLI | Dev2 | Dev3 |
| `Fishing/Shared/SpeciesTable.lua` | `modelLengthM` per row; `validate` | Dev1 | Dev3 |
| the town place | 8 tagged tank parts, a glass material, a plaque SurfaceGui each; GameOne's own look | Dev2 (Studio) | Adrian (look) |
| `Fishing/Shared/TackleBox.lua`, `Server/SaveData.lua` (B only) | the `Aquarium` field; the two moves | Dev1 | Dev3 |
| `PARITY_CHECKLIST.md` | P13 rewritten per the option ruled | Dev3 | Coordinator |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/aquariumlayout_test.luau` | 3 species in first-catch order land in tanks 1..3; 9 species in 8 tanks: the 9th is in `overflow` with its count; an empty log gives 8 empty tanks; `scaleFor`: trout 0.40 -> 1.0, 0.55 -> 1.375, minnow 0.04 -> 0.5 (clamped), pike 1.2 -> 1.714; the layout from `CatchLog.serialize(log)` -> `deserialize` equals the layout from `log` (the sync image is the input); `assign` is pure (the same summary twice gives equal tables, the input untouched) | a mutant that scales by `count` instead of `bestLengthM` fails the scale rows; a mutant that orders by species id fails the order row | `PASS 25` |
| `tests/catchlog_test.luau` | unchanged: the best-length catch survives the round trip, which is what the tank shows | (its seven tampered saves) | `PASS 48` |
| B only, `tests/tacklebox_test.luau` rows | box -> tank -> box keeps species and length; capacity 6 refuses the 7th; a save with 7 slots is refused by `deserialize` | a mutant that lets the 7th in fails | Dev1 names the count |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | a fresh profile enters the room | 8 empty tanks, blank plaques | frames in `evidence/WSF/` |
| 2 | catch a trout, return | tank 1: a trout at scale `length / 0.40`; plaque 40 cm (or the caught length), 1, day 1 | frames |
| 3 | catch a longer trout | the model grows; count 2 | frames |
| 4 | two players in the room | each sees their own tanks; the other's are empty to them | both clients' frames |
| 5 | `PerfProbe` label `AF_AquariumView`, 8 tanks filled | median <= 0.5 ms per frame, p95 <= 1.0 ms | a row in the PERF table |

## Rulings needed
1. A or B for F3.
   - A: the gallery from the catch log. Cost: one client module, one pure module, a room; no net, no save. Fidelity: unknown until V63; a display is the safest reading of "aquarium".
   - B: the live tank from the box. Cost: three messages, a save field, the make-room interplay (WST_tacklebox.md), two StateRules rows; blocked until the box flow lands. Fidelity: matches only if V63 shows a fish leaving the box.
   - Recommendation: A for F3, B as an F4 item if V63 shows it; A's view is reused either way.
2. One tank per species, or one per record (length and weight records separately).
   - A: per species, the best-length fish. Cost: none. Fidelity: n/a.
   - B: per record. Cost: two tanks for one species; a busier room. Fidelity: n/a.
   - Recommendation: A.
3. The room open from the start, or behind a P10 unlock.
   - A: open. Cost: none. Fidelity: V57 and V63 decide.
   - B: `GameData.Places.aquarium.Unlock` (money or story). Cost: one predicate. Fidelity: same.
   - Recommendation: A until V63.
4. B's feeding and decay.
   - A: none, ever; a fish in the tank is a trophy. Cost: none. Fidelity: unknown.
   - B: a feed timer with a hungry state. Cost: a clock hook, a cue, a chore. Fidelity: only if V63 shows it.
   - Recommendation: A; the Mild maturity label and the no-chores rule both prefer it.
5. Overflow past 8 species: the plaque ("and 3 more") or a second room. Recommendation: the plaque; 8 species is beyond F3.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| P13 aquarium | display, income or bonus; fish from the box (V63) | A: one tank per caught species from `CatchLog`, the best-length model, client-only, no save field. B (later): `SaveData.Aquarium`, box <-> tank moves, a capacity | planned (A) | `tests/aquariumlayout_test.luau`; V63 |

## Open questions
- Whether the demo's aquarium takes the fish out of the box (Adrian, V63); B's whole case rests on it.
- The room's place in the town layout and its art (Adrian with the `SFX_ART_LIST.md` brief; nothing from the reference).
- Whether `CatchLogSync` keeps `bestLengthCatch` in the compact codec (Dev3, WSN open question); A needs only `bestLengthM`.
- `modelLengthM` for the rigged trout against the plain one (Dev2, on import; `README_v2.md` says 0.40 m for both).
- Whether `TroutView.setBend` works on a scaled MeshPart (Dev2).
