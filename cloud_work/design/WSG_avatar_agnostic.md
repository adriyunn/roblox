Written by Cloud on 2026-10-08 without access to the project files;
every claim about the forced Boy avatar, the Caught camera's body ratio, AnglerPose, the cast pose's arm swing, FishingVisuals' held fish and the aim pivot below is from the team's transcripts and the R1 seed in CONTEXT.md and must be checked by Dev2 (camera, poses, held fish) and Dev1 (the aim pivot, the server's rod tip) against the real files; Dev3 checks the tests and the PARITY row. The formula `ratio = height x 0.28 / 1.905` is the team's (WS0b); 0.735 for Boy comes from CONTEXT, 0.74 from the WS0b line in `process/R1_FishingConfig_split.md`; Dev2 says which is live.

# WS-G: avatar-agnostic poses and camera (RigMetrics)

```
WS-G avatar_agnostic (About Fishing F1; Cloud, 2026-10-08; rev 1)
Status: DRAFT, FOR RULING (rulings 1-4)
```

## Lead
One module, `RigMetrics`, measures each character once on spawn (height, head top, shoulder height, hand grip offsets, body ratio); every camera beat and pose offset is written in rig units, `k x <the Boy-tuned metres>`, so Boy gives today's bytes and any other rig scales; the rod hangs from the hand's grip attachment; extreme rigs are clamped to 0.5..1.5 of Boy.
When it is right a player in their own avatar sees their head in the catch shot, the rod on their shoulder and the fish in their hand, and the Boy player sees exactly F1.

## Reference behaviour
The reference has one fixed protagonist; there is nothing to measure. The facts below are ours and the platform's.

| Claim | Source | Ref | Value |
|---|---|---|---|
| F1 forces the ROBLOX Boy avatar | team | CONTEXT.md (open items) | body ratio 0.735 (the WS0b line says 0.74; confirm) |
| the Caught camera cropped a default R15's head | team (the R1 seed) | CONTEXT.md; WSH_options_panel_additions.md section 4.2 | ratio about 0.92 |
| body ratio formula | team (WS0b) | the kickoff brief | `heightStuds x 0.28 / 1.905` (0.28 m per stud; 1.905 m = the reference height) |
| players bring their own avatars | platform | ROBLOX_constraints.md section 4 | any scale, bundles, layered clothing, R6 or R15 |

By the formula: Boy at ratio 0.735 is 5.00 studs tall; a default R15 at 0.92 is 6.26 studs; a 0.5 scale of Boy is 2.50 studs.

## Our rule
- `Fishing/Shared/RigMetrics.lua` (pure: `measure(parts) -> Metrics | nil, reason`, `scale(metrics) -> k`, `serialize` / `deserialize`): `heightM` (foot bottom to head top), `headTopM`, `shoulderM` (R15: the top of `RightUpperArm`; R6: the top of `Torso`), `gripOffsetM` (`RightGripAttachment` of `RightHand`, R6 `Right Arm`, relative to the root), `ratio = heightStuds x 0.28 / 1.905`, `k = clamp(ratio / BoyBodyRatio, RigScaleMin, RigScaleMax)`, `clamped` (bool), `rig` (`R15` | `R6`). Measured once per character on both the client (poses, camera) and the server (the rod tip for the cast start, the aim pivot) from the same replicated parts, so the two agree and a client never reports a height.
- When: on `CharacterAdded` after the appearance has loaded, again after `RigMeasureRetryS` (0.5 s) if a part was missing, and again on a scale change. Stored as attributes `RigK`, `RigRatio`, `RigShoulderM`, `RigHeadTopM` on the character for anything that reads without requiring the module.
- Rig units. Every metre that was tuned on Boy and depends on the body (the Caught beat's height and distance, HookFollow's shoulder lead, the shoulder-carry rest point, the cast pose's arm swing radius, the held-fish hand offset, the aim pivot height) becomes `k x <that metre>`. The constants do not change; the multiply happens where each is read. Boy gives `k = 1.0` and the F1 bytes.
- The rod grip is welded to the right hand's `RightGripAttachment` instead of a root offset; the shoulder carry targets `RigShoulderM`.
- Clamps: `k` in 0.5..1.5 of Boy. Outside, the clamp applies, `clamped = true` and one output line names the player: a 0.3 scale rig gets the 0.5 framing, the camera may crop, nothing errors.
- Avatar policy (ruling 1): F1 keeps the forced Boy (`C.Avatar.ForceBoy`, confirm the key) with RigMetrics underneath, so k is 1.0 by construction and the F1 gate is unchanged; R1 drops the force.

## What breaks today
| Where | What a non-Boy rig does today | With rig units |
|---|---|---|
| `CameraAF` Caught beat (`C.CameraAF.Caught`) | frames the fish at Boy's ratio; a 0.92 rig's head is cropped (the R1 seed) | height and distance x k; the head top from `RigHeadTopM` |
| `AnglerPose` shoulder carry | the rod rests at Boy's shoulder; a taller rig carries it in the chest, a shorter one above the head | the rest point = `RigShoulderM` |
| the cast pose arm swing (`AnglerPose`, with `CastGesture`'s timing) | the swing radius is Boy's arm; a long arm passes through the torso, a short one leaves the rod floating | radius x k; the grip attachment moves the rod with the hand |
| `FishingVisuals` held fish | the fish is held at Boy's hand offset; on a 0.5 rig it floats beside the body | the hand's attachment, offset x k |
| `InputController` aim pivot height | the pitch origin is Boy's eye; a tall rig aims from the chest and the marker lands short (it meets the `lineM` clamp, Dev1 #4) | pivot = `RigHeadTopM` minus k x (Boy head top minus Boy eye) |
| layered clothing, bundles | the root size changes; the parts do not lie | measured from parts, never from the root size |
| R6 rigs | no `RightHand`, no `RightUpperArm` | the R6 fallbacks above, or force R15 (ruling 4) |

## Config keys
| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `BoyBodyRatio` | `C.Avatar` | ratio | 0.735 | fixed | the F1 rig; `k` is relative to it |
| `RigScaleMin`, `RigScaleMax` | `C.Avatar` | ratio of Boy | 0.5, 1.5 | 0.3..2 | the camera and poses are checked in this band only |
| `RigMeasureRetryS` | `C.Avatar` | s | 0.5 | 0.1..2 | parts arrive after the character |
| `ForceBoy` | `C.Avatar` (confirm the key) | bool | true in F1, false in R1 | | ruling 1 |
| `GripAttachmentName` | `C.Avatar` | string | `RightGripAttachment` | | Roblox's name on R15 and R6 |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none | `StateRules` |
| Cues | none; the metrics are measured on both sides from replicated parts, so no message carries a height (a client-sent 1.5 k would lengthen the cast start) | `FishingNet` |
| Guard rules | none | `RequestGuard` |
| Wire size | +0 B | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/RigMetrics.lua` | new, pure | Dev2 | Dev1 |
| `Fishing/Client/CameraAF.lua`, `CameraRigAF.lua`, `CameraController.lua` | the Caught and HookFollow metres x k; the head top from the metrics | Dev2 | Dev1 |
| `Fishing/Client/AnglerPose.lua` | the shoulder carry and the cast pose x k; the grip attachment | Dev2 | Dev1 |
| `Fishing/Client/FishingVisuals.lua` | the held fish from the hand attachment | Dev2 | Dev1 |
| `Fishing/Client/InputController.lua`, `Server/FishingServer.lua` | the aim pivot and the rod tip from the metrics, both sides | Dev1 | Dev2 |
| `Fishing/FishingAvatar.lua` | measure on spawn; the attributes; `ForceBoy` | Dev2 | Dev1 |
| `tests/rigmetrics_test.luau` | new | Dev3 | Dev2 |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/rigmetrics_test.luau` (RobloxStub Instances for the parts) | three fake rigs: Boy 5.00 studs -> ratio 0.735, k 1.0; default R15 6.26 -> 0.920, k 1.25; a 0.5 scale bundle 2.50 -> 0.367, k 0.5 (at the clamp, `clamped` false); a 0.3 scale -> k 0.5, `clamped` true; a 2.0 scale -> 1.5, clamped; every Boy-tuned beat metre x k equals the F1 constant on Boy to the byte; R6 parts give the Torso and Right Arm fallbacks; no hand on either rig -> `nil, "no grip"`; `serialize` -> `deserialize` equal and JSON-safe; a tampered `k = 9` is refused | a Boy one stud taller gives different bytes (the identity check is live); a mutant with 0.3 m per stud fails the ratio row | `PASS 30` |
| Dev2's CameraAF sweep (confirm the file) | the Caught framing keeps the head top inside the frame for k 0.5, 1.0, 1.25, 1.5 | k 1.25 without the multiply crops (the R1 seed reproduced) | Dev2 names the count |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | Boy (forced) | every F1 beat and pose as today; `RigK` 1.0 | frames in `evidence/WSG/` beside the F1 ones |
| 2 | default R15 (`ForceBoy` off) | the catch shot shows the head; the rod on the shoulder; the fish in the hand; the aim marker lands where Boy's does | frames |
| 3 | a 0.5 scale bundle | the same five checks at k 0.5 | frames |
| 4 | a layered-clothing bundle | the metrics do not change with the clothing | the attributes |
| 5 | an R6 avatar | the fallbacks, or the R15 force refuses it (ruling 4) | frames |

## Rulings needed
1. Avatar policy.
   - A: force Boy for F1, RigMetrics underneath with k = 1.0, ship avatar-agnostic in R1. Cost: the module and the multiplies now, no F1 byte changes, the Studio matrix in R1. Fidelity: F1 has one fixed protagonist like the reference.
   - B: allow any avatar now with the clamps. Cost: the Studio matrix before the F1 gate; the Caught crop fix joins the F1 critical path. Fidelity: departs from the reference on purpose, earlier.
   - Recommendation: A.
2. The clamp band.
   - A: 0.5..1.5 of Boy. Cost: five Studio rows. Fidelity: n/a.
   - B: 0.7..1.3. Cost: fewer edge cases; more players clamped. Fidelity: n/a.
   - Recommendation: A, widened only after the matrix.
3. Rig units.
   - A: `k x <Boy-tuned metres>`; the constants stay. Cost: one multiply per read. Fidelity: F1 bytes hold.
   - B: re-tune every constant in metres per rig unit. Cost: the F1 bytes move and the sweeps re-run. Fidelity: same.
   - Recommendation: A.
4. R6.
   - A: R6 fallbacks in the module. Cost: a second rig family in every Studio row. Fidelity: n/a.
   - B: force R15 in the experience's avatar settings (Roblox allows it) and drop R6 from the matrix. Cost: one setting. Fidelity: n/a.
   - Recommendation: B for R1; one rig family to check.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| the avatar (no X id: a platform difference, on purpose) | one fixed protagonist | the player's own avatar; poses and camera in rig units; Boy reproduces F1 to the byte | planned (R1) | `tests/rigmetrics_test.luau`; the Studio matrix |

## Open questions
- Which of 0.735 and 0.74 is the live Boy ratio (Dev2, from the WS0b constants).
- Whether the server's cast start uses a rod tip offset today or the client's reported tip (Dev1; the latter is the exploit this note closes).
- Whether `CameraRigAF` already has a per-rig hook (Dev2).
- The key that forces Boy and where the HumanoidDescription is applied (Dev2, `FishingAvatar`).
- Phone players (WSI) more often wear scaled avatars; the R1 matrix should include one phone run (Dev3).
