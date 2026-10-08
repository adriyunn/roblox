Written by Cloud on 2026-10-08 without access to the project files;
every claim about FishBrain (the notice roll, the hover band, the nip rule), LureSim, the hook state and FishingConfig below comes from the team's transcripts and must be checked by Dev1 (FishBrain, FishingServer, the hook state) and FableDev (LureSim, the oracles) against the real files; Dev3 checks the PARITY row. The cloud modules named (SpeciesTable, GameData, EncounterLog) are real in `cloud_work/src` and pass their suites; `SpeciesTable.lureMultiplier` is the function the brief calls `lureMul`.

# WS-D: lures change what the fish does (X65)

```
WS-D lures (About Fishing F1; Cloud, 2026-10-08; rev 1)
Status: DRAFT, FOR RULING (rulings 1-4)
```

## Lead
The equipped lure rides on the hook state; FishBrain reads one number from it, `SpeciesTable.lureMultiplier(speciesId, lureId)`, at one site (the notice roll), and the lure's own motion (a spinner spins on retrieve, a fly floats) is a LureSim profile. Bite timing and the nip rule do not move.
When it is right a trout on a fly comes in sooner and more often than on a worm, a pike mostly ignores the worm, and the trout on the starter lure is the F1 trout to the byte.

## Reference behaviour
Preview facts, UNVERIFIED until Adrian records V53 (V55 shows the same lure at night, for X66). F1 numbers are measured and win.

| Claim | Source | Ref | Value |
|---|---|---|---|
| lures attract different fish types | preview (UNVERIFIED) | RECORD IN DEMO: V53 | lure -> species table |
| a wrong lure: no interest, or less | preview (UNVERIFIED) | V53 (3 casts per lure, same spot) | zero or a lower rate; ruling 2 |
| when a swap is allowed | preview (UNVERIFIED) | V53 (the swap screen) | standing only, or mid-cast |
| the same lure at night | preview (UNVERIFIED) | V54, V55 | species present and nip timing at night; feeds X66, not this note |
| notice to first nip (trout) | F1 measured | CONTEXT.md | 4.083 s, unchanged by any lure |
| cooldown between charges | F1 measured | CONTEXT.md | U(4, 5) s, unchanged |

## Our rule
- The lure id travels with the hook state. At the cast the server copies the player's equipped lure (`Equip`, WSN id 36; P06: Walking and Holding only) onto the hook record as `hook.lureId`; a cast in flight or a hook in the water never changes lure. FishBrain, LureSim and EncounterLog read `hook.lureId`; nothing reads the loadout directly.
- One site. FishBrain's notice roll (the per-step chance that a fish inside `NoticeRangeM` with a clear sight ray enters Notice; the ~:1077 site of X01, confirm) multiplies its chance by `m = clamp(SpeciesTable.lureMultiplier(fish.speciesId, hook.lureId), LureMulMin, LureMulMax)`. At the same site, when the roll succeeds, the hover band for that engagement is drawn once as `[HoverMinS, HoverMaxS] / m` and stored on the fish; no later state reads the lure. Seek, charge/nip, Swallow, Cooldown and the give-up are untouched; the oracle gains one column.
- Starter identity: `m = 1.0` for the starter lure on trout, so the F1 fish is unchanged by construction. `SpeciesTable.ROWS.trout.lures.worm` moves from 1.1 to 1.0 (worm is `GameData.STARTER.lure`); spinner 1.3 and fly 1.5 stay (ruling 4).
- `hookMode`. The hook state's mode, the one EncounterLog already takes (`bed | mid | lure`), is `"lure"` whenever `GameData.LURES[hook.lureId].motion ~= "none"`; otherwise `"bed"` or `"mid"` by position as today. A worm or boilie resting on the bed is a bed hook; a spinner is a lure hook even when still.
- Motion profiles, in LureSim, from `GameData.LURES[id].motion`: `none` (worm, boilie: F1 behaviour); `spin` (spinner, spoon: while the reel moves the hook faster than `SpinMinReelMps`, the hook centre wobbles sideways by `SpinWobbleM` at `SpinHz`; still when still); `float` (fly: the hook rests at the surface minus `RadiusM` 0.03 m with no sink until the reel pulls it faster than `FloatSinkPullMps`, then it sinks as the worm does); `jig` (`spin` with the wobble vertical, same keys). The wobble is a displacement added after the step, so the F1 integration order is unchanged.
- Not changed: the notice-to-first-nip timer (4.083 s), the nips-before-swallow rule, Cooldown U(4, 5) s, FishJudge's windows, the fight, the Spook reasons. A lure changes how often and how soon the fish comes, never what it does once it has come.
- Bait is a lure row with `motion = "none"` (ruling 3); no second table in F2.

## Config keys
| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `LureMulMin` | `C.AF.Fish` | ratio | 0.15 | 0..1 | X65's floor: a wrong lure gives fewer notices, never none, until V53 |
| `LureMulMax` | `C.AF.Fish` | ratio | 2.0 | 1..4 | a row typo cannot make a fish notice on every step |
| `SpinWobbleM` | the LureSim keys' block (FableDev names it) | m | 0.02 | 0..0.05 | under the hook radius 0.03 m, so a resting spinner never digs into the bed |
| `SpinHz` | same | Hz | 4 | 1..8 | 15 frames per cycle at 60 fps, visible without blur |
| `SpinMinReelMps` | same | m/s | 0.3 | 0.1..1 | below it the spinner hangs like a worm |
| `FloatSinkPullMps` | same | m/s | 0.5 | 0.2..1 | a fly stays up on a slow retrieve |
| `motion` | `GameData.LURES[id]` | enum | per row | none, spin, float, jig | `GameData.validate` refuses another word |
| `lures.worm` | `SpeciesTable.ROWS.trout` | ratio | 1.0 | fixed | the starter identity |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none; the `Equip` rows are already in WSN section 7 | `StateRules` |
| Cues | none new. The replicated hook state the observers' view reads carries the lure as a u8 index into the sorted `GameData.LURES` ids, so the view draws the right model | the replicated hook state (Dev3 sizes it), not a cue |
| Guard rules | none | `RequestGuard` |
| Wire size | +1 B per replicated hook state; +0 B on every cue | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/FishBrain.lua` | the notice roll reads `m`; the hover band drawn once per engagement | Dev1 | Dev3 via the oracle |
| `Fishing/Server/FishingServer.lua` | `hook.lureId` at the cast; `hookMode` for EncounterLog | Dev1 | Dev3 |
| `Fishing/Shared/LureSim.lua` | the motion profiles (a displacement after the step) | FableDev | Dev1 |
| `Fishing/Shared/SpeciesTable.lua` | `trout.lures.worm = 1.0` | Dev1 | Dev3 |
| `Fishing/Shared/GameData.lua` | `motion` per lure; `validate` | Dev1 | Dev3 |
| `Fishing/FishingConfig.lua` | the keys above | WordAgent (patch doc) | Dev1 |
| `Fishing/Client/HookLineView.lua` or a small `LureView` | the lure model per id; the spin drawn from the replicated position, no client sim | Dev2 | Dev1 |
| `tools/fish_oracle.py` | model B gains `lure_mul` | Dev1 | FableDev |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/wsa/fishbrain_test.luau` rows L1-L6 | L1 starter lure, mid-water: the trace is byte-identical to the frozen golden (the X01-3 scenario with `lureId = worm`); L2 fly on trout, 50 seeds x 10,000 steps: notices per 1,000 steps = 1.5 x the worm rate within 5 %; L3 the hover median = the worm median / 1.5 within 10 %; L4 worm on pike (row default 0.6): fewer notices than on trout, more than 0 in every seed; L5 a row value 5.0 is applied as 2.0; L6 `hookMode` is `lure` for a still spinner and `bed` for a resting worm | a mutant that reads `m` a second time at the hover entry (double-applied) fails L3; `LureMulMin = 0` with a 0 row fails L4 | `PASS 134` (128 after X01 + 6) |
| `tests/wsa/luresim_test.luau` (FableDev's suite, confirm the name) rows M1-M4 | M1 worm: every F1 trace byte-identical; M2 spinner at reel 0.4 m/s: lateral amplitude 0.02 m at 4 Hz, 0 at reel 0.2 m/s; M3 fly: the hook at surface minus 0.03 m for 30 s with no reel, sinking at reel 0.6 m/s; M4 the dock-grid traces with `motion = none` unchanged | a mutant that wobbles while still fails M2 | FableDev names the count |
| `tools/fish_oracle.py --parity` | every row MATCH including `lure_mul`; the mid-water golden gains the column and no row changes | a Luau `m` of 1.3 against a Python 1.0 shows the first mismatch row | MATCH |
| `tests/speciestable_test.luau` | `trout.lures.worm == 1.0` and `lureMultiplier("trout", "worm") == 1.0`; the row still validates | the live 1.1 fails the row until the edit | `PASS 53` |
| `tests/gamedata_test.luau` | every lure has `motion` in the set; a loadout with the lure id survives serialize -> deserialize | `motion = "spinny"` fails `validate` | `PASS 47` |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | `SpawnVisibleFish`, worm, a bed hook 2 m from the home | F1: notice -> first nip 4.083 s, hover 5-45 s | EncounterLog `bed` rows in band |
| 2 | swap to the fly in Walking, cast the same spot, 10 encounters | notice sooner and more often; `hookMode` lure in the CSV; nip timing unchanged | `parity_report.py` lure rows |
| 3 | spinner, a steady retrieve | the lure wobbles on the way in; still when the reel stops | frames in `evidence/WSD_lures/` |
| 4 | `Equip` during Flight | refused by StateRules; the hook keeps its lure | server output |

## Rulings needed
1. How many lures in F2.
   - A: three, the trout's own: worm (starter), spinner, fly. Cost: three models, one V53 check. Fidelity: enough to show the mechanic on the one tuned species.
   - B: all six in `GameData.LURES` (spoon, jig, boilie too). Cost: six models; four matter only for UNTUNED species. Fidelity: a fuller shop, nothing more proven.
   - Recommendation: A.
2. A wrong lure: zero notices or fewer.
   - A: fewer; `LureMulMin = 0.15` clamps every row. Cost: none. Fidelity: departs if V53 shows a fish that never looks.
   - B: zero when the row says 0 (`LureMulMin = 0`); the fish never enters Notice. Cost: a species can be uncatchable on a lure and the shop must say so. Fidelity: matches only if V53 shows it.
   - Recommendation: A until V53.
3. Bait as a separate thing.
   - A: bait is a lure row with `motion = "none"`; one table, one `Equip`. Cost: none. Fidelity: the swap screen looks the same either way.
   - B: a `GameData.BAITS` table consumed per cast. Cost: a second table, a count in SaveData, a BaitGone cost. Fidelity: only if V53 shows bait being used up.
   - Recommendation: A.
4. `trout.lures.worm` 1.1 -> 1.0.
   - A: change the row so the starter is the identity and the F1 bytes hold. Cost: one number. Fidelity: F1 unchanged.
   - B: keep 1.1 and regenerate the golden traces. Cost: a new golden with no player-visible reason. Fidelity: the same.
   - Recommendation: A.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| X65 lures attract different fish types | lure -> species; zero or less interest on a wrong lure (V53) | `hook.lureId` -> `SpeciesTable.lureMultiplier` at the notice roll, clamped 0.15..2.0; hover band / m; motion profiles in LureSim; `hookMode` lure | planned | rows L1-L6, M1-M4; V53 against the CSV's lure rows |

## Open questions
- Whether FishPool's spawn mix also reads `lureMultiplier` (WSS_species.md says yes; this note scales notices only): both or one, after V53 (Dev1 with the Coordinator).
- The name of the LureSim keys' config block (FableDev).
- The brief for this note cited V53-V55; the clip list gives V53 to lures and V54-V55 to X66, so V54-V55 are context here, not evidence (Adrian, no action).
- Whether `hookMode = "lure"` should also apply to a worm being retrieved, since a moving bait does not hover either (Dev1, with the bands in WSP_parity_log.md).
- Lure models: the v2 Blender set has none; three placeholders (Dev2 with `blender/`).
