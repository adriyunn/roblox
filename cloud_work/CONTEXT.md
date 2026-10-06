# Context for cloud work on GameOne / About Fishing F1

Read this before writing anything under `cloud_work/`. It is a digest of the six team sessions'
transcripts as of 2026-10-04 17:52 UTC. The real project files are NOT in this repo: they live on
Adrian's MSI and Alienware machines under `C:\Users\adria\OneDrive\Desktop\Claude\Roblox\GameOne\`.
Everything here is written blind to the real code, so anything that touches an existing file is a
DRAFT for a dev to check against the real bytes.

## The project
- A Roblox Studio game (Luau) that plays almost 1:1 like **About Fishing** (Steam, The Water Museum /
  Playstack): About Fishing is the *mechanics* reference; GameOne keeps its own art, world and sounds.
  Copy how it plays, never its story, names, text, art, models or sounds.
- Milestone **About Fishing F1** = one encounter, trout only: aim, cast, steer, sink or retrieve, a
  visible trout that inspects and nips, the hook set, the fight, the haul-out, the catch scene, walking
  on holding the fish. About 75% done.
- Workspace on the machines: `Roblox/GameOne/Phase5_AF/` with `design/`, `design/detail/`,
  `design/reviews/`, `src/` (live in Studio through Rojo since 2026-10-04 04:17), `patches/`, `pre/`
  (pre-images), `tests/`, `tests/wsa/`, `sim/`, `evidence/`, `w21/` and `w3/` (staging), `tools/promote/`.
  Team-level docs one level up: `BACKLOG.md`, `TEAM_RULES.md`, `STUDIO_LOCK.md`, `MORNING_CHECKLIST.md`.
- Place: `Place1` = `FishTest.rbxl`. Rojo map: `Phase4/rojo/default.project.json`. Only the Studio-lock
  holder writes `src/`; staged work goes to `w21/` or `w3/`, promoted by hash-gated scripts
  (`promote_batch1.py`, `promote_batch2.py`), checked by `verify_all.py` (MATCH every script, UNMANAGED 0).
- Files are identified everywhere as `size / hash` (e.g. `43,609 / 1409089990`; a 32-bit checksum
  computed by their own tool). We cannot compute it here: never invent one.

## The team (six Claude sessions, all Remote Control on Adrian's machines)
| Session | Role | Owns / reviews |
|---|---|---|
| Coordinator | assigns work, makes rulings, relays between sessions | `BACKLOG.md`, rulings |
| Dev1 (Alienware) | server + shared code | `FishingServer`, `FishingVisuals`, `Fishing/Shared/*`, `FishBrain`, `FishPool`, `FishJudge`, `InputController`, `FishingController`; reviews Dev2's client work |
| Dev2 (Alienware) | client: body, view, camera, catch, feedback (WS-G, WS-H) | `CameraAF`, `CameraRigAF`, `CameraController`, `AnglerPose`, `AimMarker`, `FishPoolView`, `FishingPoolView`, `TroutView`, `StrainAudio`, `FishingWaterFX`, `CatchSceneView` |
| Dev3 (MSI) | tests, guard, net, every removal; keeps `PARITY_CHECKLIST.md` | `AF1Playtest`, W3/W4 suites (`W3Suites_Dev3.luau`, `W4Verdicts_Dev3.luau`…), guard findings |
| FableDev (MSI) | batch promotion scripts, reviews, Studio lock holder for windows | `tools/promote/*`, `LureSim`/`LineKinks` W2.1 work, oracles |
| WordAgent (Alienware, Sonnet) | docs, README tables, WS-R removals, the rows file | `Phase5_AF/README.md`, `Phase4/rojo/rows_batch2_*.json`, `make_rows_batch2_WordAgent_ALIENWARE.py` |
Adrian (the user) records clips, runs the Studio windows' hand steps, does the feel review.

## Conventions the team uses (match them)
- Luau module header, first lines:
  `--!strict`
  `-- ModuleName (About Fishing F1, WS-X; Author, YYYY-MM-DD; design/<note>.md)`
  `-- One or two lines on what it does.`
  Use author `Cloud` and date `2026-10-06` for cloud work. Keep comments plain and specific.
- Offline tests are `.luau` files run with the Luau CLI from their own folder: `luau <file>`. They print
  one line per check and end with `PASS <n>` or `FAIL <k> of <n>`; a failing suite exits non-zero
  (`error()` at the end). Negative controls (a check that proves the test can fail) are valued.
  Python tools are run with `python <file>`; `luau-compile --null <file>` is the syntax check.
- Patches are `.patch.txt` files applied by `Phase3/tools/patch_tool.py`, hash-gated. Format: a first line
  naming the target file and author/date/purpose, then blocks of
  `@@@ OLD` / `<exact old text>` / `@@@ NEW` / `<new text>` / `@@@ END`. We cannot match real bytes
  here, so cloud "patches" are written as DRAFT patch docs with the intended old/new text clearly marked.
- Design notes live in `design/` as `WS<letter>_<topic>.md`; rulings needed are listed explicitly;
  the Coordinator approves "for fidelity" against the reference. Reviews go in `design/reviews/` as
  `<topic>_review_<Dev>_<MACHINE>.md` with verdicts ACCEPT / ACCEPT WITH FIXES / FIXES, findings
  numbered F1.. (major), N1.. (nits), with severity words must/should/nit.
- Units: metres in the fish/line simulation (`BedSightLiftM = 0.03` m, hook radius `LureSim RadiusM` 0.03 m);
  config keys end in `M` (metres), `S` (seconds), `Deg`. Config is one file `Fishing/FishingConfig.lua`
  (~70 KB) with blocks `C.AF.Fish`, `C.CameraAF`, `C.Sounds`, `C.Feedback`, `C.Avatar`, `C.View`.
- Keep every file LF line endings (a CRLF slip cost the team time on 2026-10-04).

## What exists (do not rebuild; design around it)
Live (W1+W2): `FishingConfig`, `FishingAvatar`, `AnglerPose` (shoulder carry), `CastGesture`, `CastFlight`,
`HookStep`, `InputController`, `LureSim`, `WaterTruth`, `LineKinks`, `LineShape`, `HookLineView`, `SimFilter`,
`FishingNet` (v2 codec), `FishingNetClient`, `StateRules` (state x action matrix), `RequestGuard`,
`LatencyBudget`, `AnglerTrack`, `FishingServer`, `FeedbackUI`, `OptionsPanel` (fishing sensitivity).
Batch 1 (W2.1, staged): `LureSim`/`LineKinks` dock fixes, `CameraAF`, `CameraRigAF`, `CameraController`
beats (Aim, chase, HookFollow, ChaseFallback, AimHold, orbit, Reset, Caught), `AimMarker` rev 3b (3D
selector + click).
Batch 2 (W3+W4, staged): `FishPoolView` rev 6b, `FishingPoolView`, `TroutView`, `FishBrain`, `FishZones`
(`depthAt` bed estimate), `FishPool` (homes ring, `HomeBubbleM` 0.74 m, `SPAWN_RETRY_S`, `RehomeAfterS`,
`GiveUp`, `SpawnVisibleFish` dev verb, `takeHooked`/`handBack`/`released`/`endHooked('Caught'|'Snap'|'GiveUp')`),
`FishJudge` (press verdict Early/Good/Late; Late eject at tS + 0.55 + LB; Late press now spooks the other
engaged fish), `TroutFight`, `StrainAudio` (one loop, -40 dB floor, owner-only loop/reel, snap 3D 40 m),
`FishingWaterFX` (fight cues, jump kick at cue startT), `CatchSceneView`, `AnglerPose` F1 poses,
`FishingVisuals` (held fish, Inspected crank), `FishingUI` (tension panel and cast-power bar removed).
Player states (server-checked): Walking, Aiming, Flight, Presenting, Retrieving, Inspected, HookWindow,
Hooked/fight, CatchScene, Holding. Net cues include Notice, Nip, Swallow, BaitGone, Spook(reason, fishId;
255 = all engaged), Jump, Snap. Fish brain: Seek, hover, charge/nip, Swallow, Cooldown U(4,5) s; notice to
first nip 4.083 s; a Late/Early press spooks (REASON_EARLY).

## Open items the team left (facts, from Dev1's diagnosis)
- X01 bed-resting hook: the fish's mouth sinks to bed + 0.04..0.055 m while the hook centre is at
  bed + 0.03 m, the mouth-to-hook sight ray grazes the bed (sampled at 1/4, 1/2, 3/4), a blocked ray
  sends the fish to Seek, Seek re-arms any bite timer with <= 1 s left and resets the 2 s give-up, so
  the fish never bites or leaves. Fix chosen: `BedSightLiftM = 0.03` (aim all four sight rays at the
  hook's top when the hook lies on the bed: notice :1077, LOS :986, Seek :959 and :963; "lying on the
  bed" = `hy - fish.bedY <= BodyBoxY/2 + lift`; before the first bed query bedY = -inf so aim at the
  centre). Backup knob `BedMouthM = 0.054` (mouth floor above a bed-resting hook) if the bed estimate sits
  3 cm or more under the terrain. Oracle model B gets `sight_y` + a `bed_seen` flag; tests at g = 0.045.
- Dev1 #4: an unclamped `lineM` in the W2.1 InputController; the out-of-range click pitch holds at 2.07.
- `FishJudge.lua:12` header still says Late = eject only; :19 explains engagedAt only for Early/Good.
- POOL-1: homes need SDF >= 0.74 m from the shore (horizontal); shallow beaches may get 0 fish.
- Waves above ~0.1 hide pool fish: weather must keep shore waves small.
- Caught camera uses the rig's body ratio (Boy 0.735); default R15 ~0.92 cropped the head (R1 seed).
- Known R1 seeds: dead peak-tracking branch in FishingUI, checker rows #25-27, NF2/NF4 camera items.

## Where cloud work goes
`cloud_work/` in this repo (branch `claude/hello-b2aghd`), mirrored to the team's layout:
`src/Fishing/{Shared,Server,Client}/`, `tests/`, `tools/`, `design/`, `design/templates/`, `process/`,
`clips/`, `blender/`, `patches/`. Every file states at the top that it was written without the real
project files and names what a dev must check.
