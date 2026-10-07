# Handoff to the Coordinator: cloud work of 2026-10-06/07

From Cloud (claude.ai/code session roblox-9d), written while the MSI and Alienware were offline, with
no access to `Roblox/GameOne`. Branch `claude/hello-b2aghd` of `adriyunn/roblox`, folder `cloud_work/`.
Pull it with `cloud_work/pull_cloud_work.bat` (clones next to GameOne, never into it).

**Round 2 (2026-10-07) is at the end of this file:** the adversarial review that fixed 13 bugs in the
modules, six more design notes, the v3 net schema with vectors, the tackle-box and catch-card client
logic, the Roblox constraints note, UI mockups, the kickoff messages, and the cloud session hook.

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

---

# Round 2 (2026-10-07)

Everything below is on the same branch. The gate after round 2: **run_all: PASS, 15 suites, 1,018
checks, `luau-analyze` clean on every module under `src/`.** Round 1's modules were reviewed and
fixed (section R2.1), so the file list in section 1 above still holds but the code moved; Dev1
re-reviews the fixed hunks, not the whole files.

## R2.0 Routing, one line each

| # | Item | Owner | Action | Unblocks |
|---|---|---|---|---|
| 25 | `design/reviews/cloud_modules_review_Cloud.md` | Dev1 | Re-review the 13 fixed hunks (listed by finding id); rule on F14 | the modules' approval |
| 26 | `design/WST_tacklebox.md`, `WSS_species.md`, `WSE_economy.md`, `WSL_catchlog.md`, `WSS_savedata.md`, `WSP_parity_log.md` | Coordinator | Rule on each note's rulings (the key one per note is in R2.2) | F2 design approval |
| 27 | `design/WSN_net_v3_messages.md` + `src/Fishing/Shared/NetSchemaV3.lua` + `tools/net_vectors_v3.py` | Dev3 | Review the 13 messages and the StateRules/RequestGuard rows; keep the vectors for the real codec | the F2 wire |
| 28 | `src/Fishing/Client/TackleBoxUI.lua`, `CatchCard.lua`, `tests/TackleBoxUI_sandbox_driver.client.lua` | Dev2 | Review as new files; run the driver in a sandbox | the box and card screens |
| 29 | `design/ROBLOX_constraints.md` | Coordinator, Adrian | Read section 7 (12 decisions it forces); the maturity label and the mobile share come first | F2-F5 scope |
| 30 | `design/mockups/` | Dev2, Adrian | Look reference for the three screens; swap the PlayStation glyphs | the screens' look |
| 31 | `kickoff/*.md` | Adrian | Paste one per session after the pull; Coordinator first | the restart |
| 32 | `../CLAUDE.md`, `../.claude/hooks/session-start.sh` | FableDev | Cloud sessions on this repo now install the Luau CLI and bpy on start; merge to the default branch when the tree moves to git | cloud sessions |
| 33 | `blender/exports_v2/`, `blender/README_v2.md` | Dev2 | (see R2.6 when it lands) | F2 species, props |

## R2.1 The review (item 25)

An adversarial pass over the eight modules, the parity tool and the stub, in the team's find/refute
shape: every finding was reproduced with a snippet before it was kept, every fix got a regression
check that fails on the round-1 code (commit `a1c3185`). 14 confirmed findings, 13 fixed, 1 open:

| Severity | Where | What it was | Fix |
|---|---|---|---|
| must | WorldClock F4 | `advance` hung on an infinite dt, a zero day length from a save, or zero weather lengths | floor-arithmetic day wrap, validated `new`/`deserialize`, a roll cap |
| must | SaveData F8 | a save retrying across `release()` re-planted our lock after the player left (30-minute lockout elsewhere) | release flips the profile first; the save transform cancels |
| must | SaveData F9 | a player leaving during a retrying load left an orphan profile holding the lock | `onPlayerRemoving` marks the load; load unlocks and returns nil, "left" |
| must | SaveData F12 | `set()` accepted NaN, sparse arrays, functions; every later save failed silently | `set()` validates and errors at the call site |
| should | SaveData F10, F11, F13 | the claim was not compare-and-set (a concurrent write was lost); two loads in flight made two profiles; an idle player's lock went stale while connected | CAS on `_savedAt`; in-flight guard; a heartbeat save at half the stale window |
| should | TackleBox F1 | an id of 2^53 in a save made `nextId + 1 == nextId`, two items got one id | `MAX_ID = 2^31`, refused in `deserialize` |
| should | SpeciesTable F2 | one sigma for the whole range clamped 2.2 % of trout to exactly 0.55 m | one sigma per side (0.65 %) |
| should | EncounterReplay F3, EncounterLog F5, parity_report F6, F7 | replay timestamps off by one step; records unbounded; a BOM or a bad record crashed the tool | fixed; `maxRecords` default 1,000 |
| open | SaveData F14 | `flushAll` on shutdown is sequential with budget waits: 3 dirty profiles under a zero budget took 276 s of fake time against Roblox's 30 s `BindToClose` | design-level: parallel saves, no budget wait on close; Dev1 rules |

Security section in the review: what a malicious client payload can and cannot do through
`TackleBox` moves, `SaveData` paths, the deserializers and `brainConfig`.

## R2.2 The six design notes (item 26), the key ruling each asks for

| Note | Asks | Recommends |
|---|---|---|
| `WST_tacklebox.md` | A full box at the catch and the player does nothing: release after 20 s, or wait for a choice | B, wait: the reference makes the player decide; nothing is lost silently |
| `WSS_species.md` | Per-species fight numbers in F2, or the one F1 fight for all with only the snap compare per species | B: the 75 %-done F1 fight does not move for F2 |
| `WSE_economy.md` | Coins 1:1 with the demo's readouts (four median trout = 32), retuned after clip V50, or GameOne's own scale | A |
| `WSL_catchlog.md` | Does a released fish count | A, yes: `record` runs at CatchScene entry, before the box |
| `WSS_savedata.md` | The lock in the record (one UpdateAsync) or in MemoryStoreService (~120 s TTL) | A for F2 |
| `WSP_parity_log.md` | Logging always on with a 1,000-record cap, or behind a dev flag | A; drop the placeholder mid-water band until 5 measured encounters exist |

## R2.3 The wire (item 27)

Thirteen v3 messages in ids 32..63 (C→S 32..47, S→C 48..63); no v2 id changes, so the W2 LEGACY
sentinel gate holds. `NetSchemaV3.lua` is a declarative schema with `validate`, `allowed(name,
state)`, and a REFERENCE canonical encoding so Dev3's vectors have one unambiguous byte form; the real
codec stays FishingNet's. `net_vectors_v3.py` is the independent Python encoder (Dev3's
`net_sim_f1.py` style): 92 vectors, 43 valid and 49 invalid with reasons, a `--check` that fails on
drift. The note recommends attributes for the 5 s world tick and `WorldSync` only on a weather change,
and a full `TackleSync` over deltas at this size (~490 bytes compact for a full 8x6 box).

## R2.4 The screens (items 28, 30)

`TackleBoxUI` owns the grid geometry, hit testing and a drag state machine whose four verbs are the
same for mouse, touch and gamepad; the renderer injects `canPlace` so the ghost colour and the drop
agree with the server. A press-and-release without moving enters a `menu` state (sell/discard for
touch and gamepad) and sends nothing. `CatchCard` formats the card (metric or imperial with ounce
carry, badges in a fixed order, the price). The sandbox driver draws it with Frames in a Play session;
it compiled here and was never run in Studio. The mockups show the intended feel; the tackle-box one
uses PlayStation button shapes that must be replaced.

## R2.5 Roblox constraints (item 29), the five numbers that change decisions

1. Blood: "heavy realistic blood" is Restricted (verified 18+); pixelated, off-colour blood stays
   Mild. Filleting must be stylised and dark, not red, to keep the Mild label.
2. About 4 in 5 Roblox users are on mobile; 44 % of FY2025 revenue came through Apple and Google.
   Touch is F1-to-R1 work, not a later phase. Keep Phone/Tablet unticked until a phone playtest passes.
3. DataStore write budget 60 + 40 x players per minute per server (380 at 8 players); `UpdateAsync`
   counts as read + write; per-key 4 MB/min. The 60 s autosave holds; add jitter.
4. Audio uploads are private to the uploader since 2022: generated sounds must be uploaded by the game
   owner's account or group, a day before a playtest (moderation takes hours).
5. Remotes cap at ~500 requests/s per client across all RemoteEvents; the mesh import limit is now
   20,000 triangles, not 10,000.

## R2.6 Blender round 2 (item 33)

Written when the asset agent reports; see `blender/README_v2.md`.

## R2.7 Housekeeping

`CLAUDE.md` at the repo root carries the conventions above; `.claude/hooks/session-start.sh` installs
the Luau CLI, `bpy` and Pillow in every cloud session on this repo (validated: hook exit 0, lint and a
suite pass). `kickoff/` holds one message per session. Probe files from the review were removed.
