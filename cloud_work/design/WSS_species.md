Written by Cloud (session roblox-9d) on 2026-10-07 without access to the project files;
the module `cloud_work/src/Fishing/Shared/SpeciesTable.lua` and `tests/speciestable_test.luau` are real and pass here (PASS 52). The `BRAIN_KEYS` names, the fight numbers and every claim about FishPool, FishBrain, FishZones and TroutFight are from the transcripts and must be checked by Dev1 against the real `C.AF.Fish` block and files; Dev3 checks the PARITY rows.

# WS-S: species rows (X60, X61, X65, X66)

```
WS-S species (About Fishing F1; Cloud, 2026-10-07; rev 1)
Status: FOR RULING (rulings 1-4)
```

## Lead
Every F2 species is one row in `SpeciesTable.ROWS`: length law, weight law, box shape by size, brain overrides, fight numbers, spawn rules, lure multipliers and price per kg; nothing about a species lives in code.
When it is right a player learns each fish by how it behaves at the lure, when it shows and what it is worth, and a new species costs the team a row, a model and a PARITY row.

## Reference behaviour
Preview facts, UNVERIFIED until Adrian records V53, V55, V68 (`clips/DEMO_CLIP_LIST.md`). F1 numbers are measured and win where they apply.

| Claim | Source | Ref | Value |
|---|---|---|---|
| species have their own behaviour patterns at the lure | preview (UNVERIFIED) | RECORD IN DEMO: V68 | per species: notice to first nip, nips before the take, hover distance |
| the trout's notice to first nip | F1 measured | CONTEXT.md (FishBrain) | 4.083 s |
| the trout's cooldown between charges | F1 measured | CONTEXT.md (FishBrain) | U(4, 5) s |
| lures attract different species | preview (UNVERIFIED) | V53 | lure -> species table; zero or just less interest on a wrong lure |
| fish behave differently at night | preview (UNVERIFIED) | V54, V55 | which species show; approach and nip timing at night vs day |
| fish come in sizes; price and footprint depend on the fish | preview (UNVERIFIED) | V50, V68 | size display and its units |

## Our rule
- `SpeciesTable.ROWS` has five rows: `trout` (tuned: the F1 fish, `lengthM` 0.25-0.55, median 0.40, no brain overrides) and `perch`, `pike`, `carp`, `minnow` (UNTUNED placeholders with real-world sizes). `validate()` checks every field of every row and errors naming `row.field`; `ids()` is sorted.
- Length law: `rollLength(id, rng)` draws a bounded log-normal around the median, `sigma = (ln max - ln min) / SIGMAS` (5), Box-Muller from two `rng:NextNumber()` draws, clamped to `[min, max]`. Trout: sigma 0.158; about 8 % of trout are small (<= 0.32 m), 73 % medium, 19 % large; about 2 % clamp to exactly 0.55 m (open question 3). A seeded rng repeats exactly.
- Weight law: `weightFor(id, L) = weightA * L ^ weightB`. Trout `11.0 * L^3`: 0.25 m -> 0.172 kg, 0.40 m -> 0.704 kg, 0.55 m -> 1.830 kg.
- Size classes: `sizeClass(id, L)` returns the first class whose `maxM >= L` (inclusive) and its `TackleBox.SHAPES` name; above `max` the last class. Trout: small `line1` to 0.32, medium `line2` to 0.46, large `line3` to 0.55. Pike reaches `line4`, carp `rect2x3`; `validate` refuses a shape name TackleBox does not have and a last `maxM` below `lengthM.max`.
- Brain overrides: `brainConfig(C.AF.Fish, id)` clones the base and applies the row's `brain` keys; it errors on a key the base lacks, so a wrong name fails at the first spawn, not in play. `BRAIN_KEYS` (`NoticeRangeM`, `HoverMinS`, `HoverMaxS`, `ChargeSpeedMps`, `CooldownMinS`, `CooldownMaxS`) are the F1 names as remembered (HANDOFF section 5); Dev1 replaces the list with the real `C.AF.Fish` names before wiring. Trout overrides nothing, so the F1 trout is unchanged by construction.
- Spawn weight: `spawnWeight(id, timeOfDay, depthM)` is 0 outside the row's `depthM` range (trout 0.3-3.0 m), else the phase weight (trout dawn 1.0, day 0.6, dusk 1.0, night 0.3) blended linearly within `BLEND_H` 0.5 h of each boundary. Boundaries are 5, 8, 17, 20 h, the same numbers as `WorldClock.PHASES` (dawn 5-8, day 8-17, dusk 17-20), so the two never disagree. `zones` is `"*"` or a list of FishZones ids; the module does not check that the ids exist.
- Lure multiplier: `lureMultiplier(id, lureId)` falls back to the row's `default` (trout 1.0: spinner 1.3, fly 1.5, worm 1.1; pike default 0.6). A wrong lure gives less, never zero, until V53 says otherwise (X65).
- Fight: the `fight` block (`strengthN`, `runChance`, `runSpeedMps`, `tireS`) is where a per-species fight reads from; the trout values are placeholders until Dev1 copies the real TroutFight constants (ruling 2).
- Adding a species: a row (validate passes), a model (`blender/exports/fish_<id>.fbx` placeholders exist for all five), a `GameData.LURES` tag for each lure sold for it (`GameData.validate` cross-checks both ways), a PARITY row with a V68-style clip, and an EncounterLog band set per hook mode (WSP_parity_log.md).
- Where the rule departs from the F2 rows file: X61 says triangular, the module is log-normal (ruling 4); X60 names keys (`NoticeM`, `NoticeToFirstNipS`, `NipsBeforeSwallow`, `SpookSensitivity`) the module does not have; the row is rewritten to the real `C.AF.Fish` names once Dev1 fixes `BRAIN_KEYS`.

## Config keys
Module constants; per-species values are row fields, not config keys.

| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `SIGMAS` | `SpeciesTable` | sigma | 5 | 4-6 | min..max spans 2.5 sigma each side of the median |
| `BLEND_H` | `SpeciesTable` | h | 0.5 | 0-1 | a 1 h linear fade at each phase boundary; no step in the spawn mix |
| phase boundaries | `SpeciesTable` (`BOUNDARIES`), `WorldClock.PHASES` | h | 5, 8, 17, 20 | fixed | shared by both modules; change both or neither |
| `lengthM`, `weightA/B`, `sizeClasses`, `brain`, `fight`, `spawn`, `lures`, `pricePerKg` | `ROWS[id]` | m, kg, s, N, m/s, coins/kg | per row | `validate()` | the row is the species |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none | `StateRules` |
| Cues | none new; the fish record every observer reads (MP_stress_test.md Z11) carries `speciesId` and `lengthM` instead of a trout-only record | the replicated fish record, not a cue |
| Guard rules | none | `RequestGuard` |
| Wire size | +1 B per fish record if `speciesId` rides as an index into `ids()` | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/SpeciesTable.lua` | new, as in `cloud_work/src`; `BRAIN_KEYS` fixed to the real names | Dev1 | Dev3 |
| `Fishing/Shared/FishPool.lua` | pick a species by `spawnWeight` x `lureMultiplier`; `rollLength`, `weightFor` on the fish record | Dev1 | Dev3 via the oracle |
| `Fishing/Shared/FishBrain.lua` | per-fish config from `brainConfig` | Dev1 | Dev3 |
| `Fishing/Server/FishingServer.lua` | `sizeClass` at the catch for the box item | Dev1 | Dev3 |
| `Fishing/Client/TroutView.lua` and a view per species | model per `speciesId`; `setBend` needs one MeshPart (HANDOFF section 5) | Dev2 | Dev1 |
| `tests/speciestable_test.luau` | adopt as is | Dev3 | Dev1 |
| `PARITY_CHECKLIST.md`, `README.md` | X60, X61, X65, X66 rewritten to the module's names | Dev3, WordAgent | Coordinator |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/speciestable_test.luau` | `validate()` passes; 2,000 seeded trout lengths stay in 0.25-0.55 m with the sample median within 10 % of 0.40; a seed repeats; `weightFor` monotonic and 0.704 kg at the median; size-class boundaries inclusive; `brainConfig` merges without touching the base and refuses an unknown key; phase weights, the 30-minute blends (07:45 -> 0.9, 08:00 -> 0.8, 04:45 -> 0.475), the depth gate; lure fallbacks | eight mutated copies fail `validate` naming row and field (median > max, unknown shape, time weight 1.5, classes stopping short, non-ascending classes, unknown brain key, `weightA` 0, `runChance` 1.5); the live rows are untouched after | `PASS 52` |
| FishPool spawn-mix suite (Dev3, X65/X66) | 10,000 draws with lure A vs lure B give the mixes the rows predict within 3 points; the night mix differs from day for at least one species | an all-zero lure table must FAIL | Dev3 names the count |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | spawn 8 trout with the species wiring in | identical F1 behaviour: notice to first nip 4.083 s, cooldown U(4, 5) s | EncounterLog bands, `bed.noticeToFirstNip` 3.5-4.5 s |
| 2 | `SpawnVisibleFish` with `speciesId = pike` | the pike model, a `brainConfig` with `NoticeRangeM` 4.0, no error at spawn | server output |
| 3 | set the clock to 23:00 (WorldClock `setTime`) | the pool's species mix shifts to the night weights | the spawn log |
| 4 | catch a 0.47 m trout | a `line3` item in the box | the items list |

## Rulings needed
1. Which four species after trout.
   - A: perch, pike, carp, minnow as built (0.12-1.20 m, shapes `line1` to `rect2x3`, placeholder models exist). Cost: none now; a rename is one row key if V68 shows other fish. Fidelity: the kinds are ours; the behaviours are tuned to V68 later.
   - B: wait for V68 and write the rows then. Cost: F2 blocked on a clip. Fidelity: same in the end.
   - Recommendation: A.
2. Per-species fight numbers.
   - A: `fight` drives TroutFight from F2 (strength vs line, runs, tire). Cost: TroutFight takes a config table; four untuned fights to review. Fidelity: the reference fights differ by species (V45, V68 would show).
   - B: F2 keeps the one F1 fight for every species; only the snap compare (`lineStrengthN` vs `strengthN`, WSE_economy.md) reads the row. Cost: one line. Fidelity: departs until F3.
   - Recommendation: B, because the F1 fight is 75 % done and must not move for F2.
3. Minnows: catchable fish or bait.
   - A: a catchable `line1` fish worth 1 coin, counted in the CatchLog; a candidate for the tutorial fish (P18). Cost: none. Fidelity: unknown.
   - B: bait only: the row goes, a `GameData.LURES` entry comes. Cost: one row, one lure. Fidelity: only if V53 shows live bait.
   - Recommendation: A for F2.
4. Length law.
   - A: keep the log-normal and rewrite X61's test (in range, seed repeats, sample median within 5 % of the row median). Cost: one row edit. Fidelity: sizes cluster at the median like real fish.
   - B: triangular as X61 says. Cost: rewrite `rollLength` and the suite. Fidelity: the same to the player.
   - Recommendation: A.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| X60 species behaviour patterns | per-species approach, inspect, nips (V68) | `ROWS[id].brain` over `C.AF.Fish`; trout = F1 by construction | staged (rows), planned (wiring) | `tests/speciestable_test.luau` PASS 52 |
| X61 fish length per catch | sizes shown; price and footprint follow (V50, V68) | `rollLength` log-normal in `[min, max]`; `weightFor`; `sizeClass` -> shape | staged | the 2,000-draw checks |
| X65 lures attract different fish | lure -> species (V53) | `lures[lureId]` with a per-row `default` floor | staged (rows), planned (FishPool) | spawn-mix suite |
| X66 day/night changes behaviour | night species and boldness (V54, V55) | `timeWeights` by phase with the WorldClock boundaries | staged | the blend checks |

## Open questions
- The real `C.AF.Fish` key names for the six overrides (Dev1, before FishBrain reads `brainConfig`).
- The zone ids `reeds`, `deep`, `lily`, `shallows` do not exist in FishZones yet; who names them (Dev1, with the F3 places).
- About 2 % of trout clamp to exactly 0.55 m and sell for the 30-coin maximum: widen `max` to 0.60 with the same classes, or accept the trophy pile (Coordinator, after V50).
- Spawn depth minima below `HomeMinDepthM` 0.35 m (WSD_shallow_shore.md) are dead range: minnow 0.1 m and trout 0.3 m never happen (Dev1, when the shore rule lands).
- Per-species V68 timings to replace the UNTUNED brain values (Adrian, V68; then Dev1).
