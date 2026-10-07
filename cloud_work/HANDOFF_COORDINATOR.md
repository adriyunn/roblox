# Handoff to the Coordinator: cloud work of 2026-10-06/07

From Cloud (claude.ai/code session roblox-9d), written while the MSI and Alienware were offline, with
no access to `Roblox/GameOne`. Branch `claude/hello-b2aghd` of `adriyunn/roblox`, folder `cloud_work/`.
Pull it with `cloud_work/pull_cloud_work.bat` (clones next to GameOne, never into it).

**How to read this:** every item is either NEW (self-contained, tested here, drop in and review) or a
DRAFT (written against code I only know from the transcripts; the named dev fits it to the real
bytes). Nothing here carries a size/hash pair: I cannot compute the team's checksum, so identity is
the commit SHA. Treat every line number in the drafts as "from the transcripts, confirm".

## 0. Suggested routing, one line each (paste into the right chat)

| # | Item | Owner | Action | Unblocks |
|---|---|---|---|---|
| 1 | `design/X01_BedSightLift_draft.md` | Dev1 | Fit the `sightY` helper + 4 call sites to FishBrain; run fishbrain_test (expect 128) and `fish_oracle.py --parity` | the bed-resting bite, batch 2 |
| 2 | `patches/W21_InputController_lineM_clamp_DRAFT.md` | Dev1 | Write the real patch (one clamp at the `lineM` source) | Dev1's #4, AimMarker pitch plateau |
| 3 | `patches/W3_FishJudge_header_DRAFT.md` | Dev1 | Fold into the next FishJudge delta (comments only) | the J-2 doc nit |
| 4 | `process/REVIEW_BACKUP_RULE.md` | Coordinator | Rule on it; add to TEAM_RULES | no 12-hour stalls on one paused reviewer |
| 5 | `process/TOKEN_AUDIT.md` | Coordinator | Apply the 10 settings (effort per turn type, 3-agent reviews, 30-min monitor) | the weekly limit |
| 6 | `process/GIT_MIGRATION.md` | Coordinator, FableDev | Rule; FableDev does the day-one checklist after batch 2 | hashes in chat, OneDrive lag, CRLF |
| 7 | `process/CLOUD_QUOTA.md` | Coordinator | Decide which work moves to cloud sessions | a second quota pool |
| 8 | `process/ADRIAN_WINDOW.md` + `.bat` | Adrian | Run once when batch 1 and the re-freeze are ready | the four hand steps in 10 min |
| 9 | `process/R1_FishingConfig_split.md` | Coordinator | Queue as the first R1 item | patch collisions on FishingConfig |
| 10 | `design/WSD_shallow_shore.md` | Dev1, Dev3 | Rule on `HomeMinDepthM = 0.35`; Dev3 moves the W3 beach row's angler | fish on shallow beaches |
| 11 | `design/WSD_bed_raycast.md` | Dev1, Dev2 | Measure the bed estimate error in Studio first (section 7), then decide | the BedMouthM backup |
| 12 | `design/WSH_options_panel_additions.md` | Dev2 | Three cheap rows in F1 if there is a slot; FOV in R1 | camera feel for more players |
| 13 | `design/WSI_touch_gamepad.md` | Dev1, Dev2 | Rule: the `InputMap` seam in F1 with #2, profiles in R1 | phone and gamepad players |
| 14 | `design/PERF_budget.md` | Dev3 | Run the matrix once batch 2 is in; file the results table | a budget before the pool grows |
| 15 | `design/MP_stress_test.md` | Dev3, Dev1 | Offline suite Z1..Z12 now; the Studio run with batch 2 | the two-player test, 8 anglers |
| 16 | `src/` modules + `tests/` | Dev1 (Shared, Server), Dev3 (tests) | Review as new files; wire per each header's "Integration points" | F2-F4 features |
| 17 | `tools/parity_report.py`, `EncounterLog` | Dev3 | Adopt as the parity gate's number source | feel review by numbers |
| 18 | `design/PARITY_rows_F2plus.md` | Dev3 | Merge into PARITY_CHECKLIST.md (ids X60-X68, P01-P20) | F2+ acceptance |
| 19 | `clips/DEMO_CLIP_LIST.md` | Adrian | Record V42-V70 in the About Fishing demo (~66 min, two runs) | every F2+ design |
| 20 | `design/SFX_ART_LIST.md` | Coordinator, Adrian | Approve the list; generation spends credits | original sounds and UI art |
| 21 | `blender/` | Dev2 | Import one FBX into a sandbox; confirm the facing axis and scale | F2 species placeholders |
| 22 | `design/templates/` | WordAgent | Adopt for new notes, ruling requests and reviews | shorter Coordinator round trips |
| 23 | `.github/workflows/luau-ci.yml` | FableDev | Point at Phase5_AF after item 6 | the gate runs on every push |
| 24 | `src/Fishing/Shared/WorldClock.lua` | Dev1 | Rule on per-player vs shared world clock (PARITY ruling 1) | F4 time and weather |

## 1. What is NEW and tested (drop in, review as new files)

All eight modules are pure Luau (`--!strict`, no Roblox globals; services are injected), each with
an offline suite under `tests/` run by `bash cloud_work/tests/run_all.sh`. Result on the last commit:
**run_all: PASS, 11 suites, 576 checks, `luau-analyze` clean on every module.**

| Module | Checks | What it gives the project | Wire-up (details in each file's header) |
|---|---|---|---|
| `Shared/TackleBox.lua` | 70 | The reference's Tetris tackle box. Rotations, overlaps, first-fit, "make room", a save form that re-validates (a tampered save cannot create an impossible box). Server-owned so clients cannot duplicate items | FishingServer on a catch: `autoPlace`; client sends (id, rot, x, y) moves over FishingNet |
| `Shared/SpeciesTable.lua` | 52 | Adding a species becomes a row, not code. Trout is tuned (0.25-0.55 m, median 0.40); perch, pike, carp, minnow are placeholders. `brainConfig` errors on a key the real `C.AF.Fish` lacks, so a name mismatch shows up at once | FishPool spawn weights, FishBrain per-fish config, TroutFight per-species fight |
| `Shared/GameData.lua` | 45 | Lures, rods, lines, hooks, prices. Calibrated so four median trout sell for 32 coins (the preview's "four fish is at least 30 bucks") | sell on the server; `castDistanceMul` into CastFlight; `hookSetWindowMul` into FishJudge |
| `Shared/CatchLog.lua` | 48 | Firsts, records and counts per zone; the "New species!" / "New record!" cues come from `record()`'s result; `merge` is commutative for save conflicts | CatchScene entry; SaveData |
| `Server/SaveData.lua` | 97 | One profile per player for every later feature. Retries with backoff, migrations by version, a session lock so two servers never write one player, UpdateAsync merges that refuse a foreign lock, autosave, BindToClose flush, read-only on corrupt or newer data (never overwrites what it cannot read) | a ProfileService script: `deps` from the real globals, `clock = os.time`, `jobId = game.JobId` |
| `Shared/EncounterLog.lua` | 67 | The feel review by numbers: per encounter notice-to-first-nip, hover, press offset, verdict, fight time, jumps, spooks; medians and p95; bands per hook mode (bed 5-45 s from the X01 ruling) | FishingServer calls start/event/finish where it sends the cues |
| `Shared/EncounterReplay.lua` | 65 | A reviewer reproduces an encounter offline: tap the net layer, save a tape, replay the "in" messages, diff the "out" ones with the time and channel of the first mismatch | one tap in FishingNet/FishingNetClient; a dev verb "RecordEncounter" |
| `Shared/WorldClock.lua` | 37 | F4's day and weather: 24 h clock, phases shared with SpeciesTable, a weather machine, rain ramp, waves capped at 0.1 m (the pool-fish visibility finding), bite multipliers | FishingServer owns one; publishes a snapshot as attributes |

Tools: `tools/parity_report.py` reads EncounterLog CSV/JSON, prints n/median/p95 per metric per hook
mode against `parity_bands.json`, exits 1 on a FAIL (31 checks, self-test proves both exit codes);
`tools/check_lf.py` fails on CRLF, a BOM or a missing final newline; `tests/RobloxStub.luau` is the
one shared stub (fake clock, DataStore with injectable failures and a budget, JSON, Instance
attributes, Players, RunService) so suites stop stubbing their own pieces.

## 2. What is DRAFT (fit to the real files before anything moves)

- **X01 bite fix** (`design/X01_BedSightLift_draft.md`): `BedSightLiftM = 0.03`, a `sightY(fish, hook)`
  helper (`hy + lift` when `hy - bedY <= BodyBoxY/2 + lift`, else `hy`; bedY = -inf falls through), the
  four call sites change only the ray's end-point y, tests X01-1..6, the 0.02 mutant as the negative
  control, BedMouthM = 0.054 kept as the backup. The helper was compiled and run here (7/7).
- **lineM clamp** and **FishJudge header**: `patches/*_DRAFT.md`, shape-only old/new blocks.
- **Seven design notes** in the team's shape (decision, numbered sections, rulings needed, acceptance
  tests with negative controls, who does what, PARITY): touch/gamepad (`InputMap` seam, 10 states x 3
  devices), shallow shore (depth 0.35 m instead of the 0.74 m horizontal bubble; on a 0.3 slope the
  first home moves from 0.74 m to 1.17 m out), bed raycast (0.5 s cache, 0.005 ms per step for 8
  fish; measure voxel error in Studio first), options panel (sensitivity per device, invert Y, FOV in
  Walk/Aim only, hold-to-toggle reel), frame-time budget (1.0 / 0.5 / 0.3 ms), the 8-angler stress test
  (rules R1-R10, offline Z1-Z12; the key check: one Spook cue id 255 fanned to every engaged angler).

## 3. Process proposals (rulings for you)

- **Reviewer backup rule:** a reviewer paused > 2 h is reassigned by one Coordinator line to a named
  backup per domain; the backup rules on existing evidence and may not write suites in the original's
  name. The Oct 4 monitor watched for new STATUS lines and could not see 12 hours of silence: watch the
  STATUS file's mtime instead, alert at 2 h, check every 30 min.
- **Token audit:** 6.6 M visible tokens on Oct 4 (2.8 M context across six sessions + 3.8 M in three
  workflows of which 6 of 17 agents failed on the limit, plus seven "nothing new" monitor replies in
  15 min on a 430 k context). Ten settings; expected saving 45-55 %, labelled rough.
- **Git migration:** GameOne on an orphan branch `gameone/main` (the repo's `main` stays as is),
  `stage/w21` and `stage/w3` branches, promotion = `git merge --no-ff` with the same rows gate reading
  `git hash-object`, `.gitattributes` for LF, clones outside OneDrive with one worktree per session.
  Rollback: the OneDrive copy is untouched until the first window succeeds from git.
- **Cloud quota:** this session reports `ccr_promotional`; the six local sessions `seven_day`. Reviews,
  oracle sweeps, suites and docs can run in cloud sessions once the code is in git; Studio, Rojo and
  computer-use stay local. Confirm the pool on the usage page after the reset before relying on it.
- **FishingConfig split (R1):** `Fishing/Config/init.lua` assembling `C` from nine files behind a shim
  that returns the same table, proven byte-identical by an offline deep-compare; about 11 dev-hours.

## 4. For Adrian

- `process/ADRIAN_WINDOW.md` + `adrian_window.bat`: resume Dev3 → paste FishingServer into Dev1's
  test copy → run the FS copy command yourself → dry run → open the feel review. The .bat only prints,
  prompts and reads; it never copies FishingServer and never writes `src/`.
- `clips/DEMO_CLIP_LIST.md`: 29 clips, V42-V70, about 66 min over two demo runs (one fresh save, one
  with money). Mechanics only: no art, text, names or sounds are copied.
- `design/SFX_ART_LIST.md`: 29 sound files and 10 images to generate as GameOne's own assets;
  nothing was generated (it spends credits) until you approve the list.

## 5. Known gaps and risks

- Every existing-code claim is from the transcripts: config key names (`C.AF.Fish.*`, `C.AF.Cast.*`),
  FishBrain line numbers, the FishJudge header lines, the net channel names. The drafts say so and
  name the checker.
- `SpeciesTable.BRAIN_KEYS` uses the F1 names as remembered (`NoticeRangeM`, `HoverMinS`...); fix the
  list once against the real `C.AF.Fish`.
- The Blender fish face +X (Roblox RightVector) by default; `--face-negz` builds them along the
  LookVector. Studio re-centres the pivot at the bounding-box centre; `TroutView.setBend` needs one
  MeshPart. F1 keeps its existing rig; these are F2 placeholders (428-652 triangles each).
- The CI workflow runs only on `cloud_work/**` until the GameOne tree is in git.
- Two module agents stopped reporting when the cloud container restarted; their files were complete
  on disk and pass the gate, which is the evidence here, not their reports.
