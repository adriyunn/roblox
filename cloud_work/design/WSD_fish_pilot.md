Written by Cloud on 2026-10-08 without access to the project files;
every claim about TroutFight (the fish's run target, strain, snap), the Hooked state's messages, CameraAF's HookFollow beat and FishPool below is from the team's transcripts and must be checked by Dev1 (TroutFight, FishingServer, FishPool) and Dev2 (the camera beat) against the real files; Dev3 checks the StateRules claim and the PARITY row. `EvidenceBoard.rollFind(defs, rng, { source, zoneId, board })` is real in `cloud_work/src/Fishing/Shared/EvidenceBoard.lua` (a sibling cloud session, 2026-10-08; `SOURCES` includes `fish`); its wiring into FishingServer is still a draft.

# WS-D: piloting a hooked fish (X68)

```
WS-D fish_pilot (About Fishing F1; Cloud, 2026-10-08; rev 1)
Status: DRAFT, FOR RULING (rulings 1-4)
```

## Lead
A hooked fish of a `pilotable` species enters a pilot mode inside Hooked when the player stops reeling; W/A/S/D then steer the fish's swim target instead of the angler, the line out is the leash, HookFollow keeps the camera on it, and reaching a tagged `PilotGoal` rolls a find or unlocks a place; reeling in or a snap ends it.
When it is right the player feels the fish towing the line into a cave mouth they could not reach on foot, with the strain and the snap rule exactly as in the fight.

## Reference behaviour
Preview fact, UNVERIFIED until Adrian records V60 (the clip list's id; the kickoff brief called it V64-V65, the list wins).

| Claim | Source | Ref | Value |
|---|---|---|---|
| some fish can be controlled to reach places | preview (UNVERIFIED) | RECORD IN DEMO: V60 | which species; what starts it (species, item, story) |
| the controls and the camera | preview (UNVERIFIED) | V60 | keys; whether the camera follows the fish |
| the limits | preview (UNVERIFIED) | V60 | a leash, a timer, a speed |
| how it ends | preview (UNVERIFIED) | V60 | a key, a timer, a trigger |
| the fight: strain, give line, snap | F1 built | CONTEXT.md (TroutFight, StrainAudio) | unchanged by this note |

## Our rule
- `SpeciesTable.ROWS[id].pilot = nil | { speedMps, turnDegPerS, leashM }`; a row with a `pilot` table is pilotable (`validate` checks the three numbers > 0). Trout has none; the F3 demonstrator is one species (ruling 1).
- Enter. In Hooked, when the species is pilotable, the fight is at least `EnterMinFightS` (2.0 s) old (the hook set and the first run happen as in F1), the reel hold has been off for `EnterHoldOffS` (1.0 s) and, under ruling 2A, a `PilotGoal` lies within `pilot.leashM`: the server sets `pilot = true` on the engagement and the player's `PilotOn` attribute. No key, no new message (ruling 3).
- Steer. The client's W/A/S/D, which the Hooked state does not use today (WSI section 5: Hooked = reel hold and give line; confirm), are sent as the direction the fight already carries (the rod or pull direction message of the Hooked state; confirm its name) and the server reads it as the swim heading relative to the camera yaw. TroutFight gets one override, `setTargetOverride(pos | nil)`: while set, the run logic picks no targets and the fish swims to `pos` at `pilot.speedMps`, turning at `pilot.turnDegPerS`. Everything else in TroutFight runs as is: strain from the line angle and speed, the tire timer, the snap rule, the jump cues (they fire from runs, so they stay quiet).
- Leash. The fish never goes beyond `min(pilot.leashM, lineOutM + LeashSlackM)` of the rod tip (`lineOutM` = the line out today; confirm LureSim's name). At the limit the target clamps to the circle and the fish stops; the strain stays whatever the angle gives; a snap still needs the strain rule. The leash is range, not punishment.
- Camera. HookFollow (a batch-1 CameraAF beat, confirm) already tracks the hook, which is in the fish's mouth; in pilot it keeps tracking with a longer lead (`PilotLeadM` 1.5 m) so the player sees where the fish is going. No new beat.
- Goal. A part tagged `PilotGoal` with `GoalId` (u16), `GoalKind` (`find` | `unlock`), `GoalRadiusM` (0.5) and, for a find, `ZoneId`. Each server step in pilot, if the fish is within the radius: `find` calls `EvidenceBoard.rollFind(defs, rng, { source = "fish", zoneId = goal.ZoneId, board })` once per goal per encounter and, on a clue id, `EvidenceBoard.discover(board, id, { dayN, timeOfDay, zoneId })`; a clue already on the board is not new, so a goal pays out once per player and the board is saved as P15 says; `unlock` sets the P10 unlock flag of `GoalId`'s place. The clue cue and the unlock cue of those rows tell the client; this note adds no cue. The goal does not release the fish: the fight resumes when the player reels (ruling 4).
- Exit. Reel held for `ExitReelS` (1.5 s) -> `pilot = false`, the override cleared, the fight continues from the fish's position and strain; a Snap ends the encounter as today; Caught follows a normal reel-in. A GiveUp cannot happen in pilot (the fish is hooked).
- Not changed: FishJudge, the hook set, strain, snap, the pool's bookkeeping (`takeHooked` .. `endHooked`), the cues, the StateRules matrix.

## Config keys
| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `EnterMinFightS` | `C.AF.Pilot` (new) | s | 2.0 | 0.5..5 | the hook set and the first run stay F1 |
| `EnterHoldOffS` | `C.AF.Pilot` | s | 1.0 | 0.3..3 | "stop reeling" is the intent; a give-line under a second is the fight |
| `ExitReelS` | `C.AF.Pilot` | s | 1.5 | 0.5..3 | longer than the fight's give-and-take, so a reel pulse does not exit |
| `LeashSlackM` | `C.AF.Pilot` | m | 0.5 | 0..2 | the leash reads the line out, plus a little |
| `PilotLeadM` | `C.CameraAF.HookFollow` | m | 1.5 | 0..4 | the camera leads the fish |
| `GoalRadiusM` | `PilotGoal` attribute | m | 0.5 | 0.2..2 | a cave mouth is wider; the goal part sits at its centre |
| `pilot.speedMps`, `turnDegPerS`, `leashM` | `SpeciesTable.ROWS[id].pilot` | m/s, deg/s, m | carp: 1.2, 90, 25 | > 0 | UNTUNED until V60 |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none: pilot is a flag inside Hooked (a `Piloting` state is option B of X68's row, open question 1) | `StateRules` unchanged |
| Cues | none new; the Hooked direction message is reused as the heading; `PilotOn` is a player attribute; the goal's cue belongs to P14 / P10 | `FishingNet` v2 untouched |
| Guard rules | none; the direction message keeps its rate | `RequestGuard` |
| Wire size | +0 B | `net_vectors_test.luau` unchanged |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/TroutFight.lua` | `setTargetOverride`; the leash clamp | Dev1 | Dev3 (W3/W4 suites) |
| `Fishing/Server/FishingServer.lua` | the enter and exit rules; the goal check; `PilotOn`; the `rollFind` or unlock call | Dev1 | Dev3 |
| `Fishing/Shared/SpeciesTable.lua` | `pilot` per row; `validate` | Dev1 | Dev3 |
| `Fishing/Client/InputController.lua` | W/A/S/D in Hooked -> the direction message while `PilotOn` | Dev1 | Dev2 |
| `Fishing/Client/CameraAF.lua` | the HookFollow lead in pilot | Dev2 | Dev1 |
| `Fishing/Shared/EvidenceBoard.lua` (cloud, real) | none; the server passes `source = "fish"` and the goal's zone | Dev1 | Dev3 |
| `Fishing/FishingConfig.lua` | `C.AF.Pilot` | WordAgent (patch doc) | Dev1 |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| the TroutFight rows of Dev3's W3/W4 suites (confirm which file) P1-P7 | P1 trout (no `pilot`): hold off 30 s never enters pilot; P2 carp: enters at fight 2.0 s + hold off 1.0 s, not at 2.9 s; P3 heading W for 60 steps: the fish moves along camera-forward at 1.2 m/s within 5 %; P4 leash: at 25 m the fish stops and the strain column equals the plain fight's for the same angle; P5 reel 1.5 s: pilot off, the next 300 steps equal a plain fight started from that state; P6 a goal at 10 m: `rollFind` called once with `source = "fish"` and the goal's zone, not again over the next 600 steps, and `discover` answers isNew true once and false on a second encounter; P7 a Snap in pilot ends the encounter as in the fight rows | a mutant that ignores the leash fails P4; a mutant that calls `rollFind` per step fails P6; a mutant that enters on trout fails P1 | Dev3 names the count |
| `tests/speciestable_test.luau` | `pilot` present on carp, absent on trout; `validate` refuses `speedMps = 0` | `turnDegPerS = -1` fails `validate` | `PASS 54` |
| `tests/savedata_test.luau` | an unlock flag set by a goal survives `serialize` -> `deserialize`; a find id is stored once | a tampered duplicate find id is refused | `PASS 98` |
| `rules_test.luau` (Dev3) | the matrix is unchanged | (its existing flipped-row control) | unchanged count |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | `SpawnVisibleFish` carp, hook it, let go of the reel | after 1 s the `PilotOn` attribute; W/A/S/D move the fish; the camera follows with a lead | frames in `evidence/WSD_pilot/` |
| 2 | steer to 25 m | the fish stops; the strain does not spike | StrainAudio stays in the loop |
| 3 | a `PilotGoal` at a cave mouth | the clue cue once; a second pass gives nothing | server output |
| 4 | reel 1.5 s | the fight resumes; land the fish | the catch scene |
| 5 | trout | no pilot however long the reel is off | server output |

## Rulings needed
1. Which species.
   - A: one, carp (the big slow one), as the F3 demonstrator; trout never. Cost: one row field, one model that exists. Fidelity: V60 names the species; a rename is one row.
   - B: every species with the flag from V60. Cost: five tunes. Fidelity: same in the end.
   - Recommendation: A.
2. A story-only mechanic.
   - A: pilot enters only when a `PilotGoal` lies within `pilot.leashM` of the hook (a tagged place says "this is a pilot spot"). Cost: one distance check. Fidelity: "to reach places" reads as a story device.
   - B: anywhere a pilotable fish is hooked. Cost: none; more to balance (a fish towed into weed). Fidelity: if V60 shows free piloting.
   - Recommendation: A.
3. Enter automatically (hold off) or by a key.
   - A: automatic; it reuses the hold on/off the wire has and adds no id. Cost: none. Fidelity: unknown.
   - B: a key (an InputMap intent, a new C->S message). Cost: one id, one row. Fidelity: if V60 shows one.
   - Recommendation: A.
4. At the goal: the fight resumes (A) or the fish is released and the find is the reward (B). Recommendation: A; the player keeps the fish and the find.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| X68 controlling a fish | some fish can be steered to reach places (V60) | a pilot flag inside Hooked for `pilotable` species: W/A/S/D steer the fight's target override, leash = line out, HookFollow follows, a `PilotGoal` rolls a find (source "fish") or unlocks; exit by reel 1.5 s or snap | planned | rows P1-P7; V60 |

## Open questions
- A flag inside Hooked (this note) or a `Piloting` state as X68's row says; the flag keeps the matrix and the guard untouched (Dev3 with the Coordinator).
- The name of the Hooked direction message and its rate (Dev1 with Dev3); if none exists, pilot needs one C->S id (Dev3 assigns).
- Whether HookFollow is one beat or two (chase, HookFollow, ChaseFallback are batch-1 beats) (Dev2).
- The `defs` entries for the pilot goals' clues (ids only; `EvidenceBoard` holds no text) and whether a goal find should bypass the chance roll (Dev1, with the Coordinator's F4 plan).
- What the fish's view does in pilot: `TroutView.setBend` at the pilot speed (Dev2).
- Whether the strain should rise when the player steers against the line (Dev1, after a Studio feel pass).
- The kickoff brief cited V64-V65; the clip list gives V60 to fish control (Adrian, no action).
