Written by Cloud on 2026-10-08 from the team transcripts and the cloud package, without access to the project files;
the checker is the Coordinator (the order and the stop rules), with each session confirming its own rows against its STATUS file and its kickoff. Hours are relative to the moment both machines are back (H0), not clock times. Nothing here changes the critical path in `kickoff/Coordinator.md`; it puts it on a clock.

# Day one: the first day the MSI and the Alienware are back

The state this starts from (CONTEXT "Open items", HANDOFF sections 0 and R2.0, the kickoff queues): batch 1 (W2.1
LureSim/LineKinks, the camera beats, AimMarker 3b) waits only on Dev3's verdict; batch 2 (W3+W4) is promoted in
staging, 23 relayed / 32 candidate, waiting on Dev1's re-freeze delta (WasdHoldS, DriftMaxM) and the rows file; Dev1
has three workflows cut off by the limit; Adrian's four hand steps are batched in `process/ADRIAN_WINDOW.md`. The
cloud package (24 + 9 routed items) is read during waits, never ahead of the batches.

## H0: pull and kickoffs (15 min)
| Who | Does | Needs | Output |
|---|---|---|---|
| Adrian | `pull_cloud_work.bat` on both machines; pastes `kickoff/Coordinator.md` first, then the other five | the machines up, OneDrive synced | `%CW%` on both; six sessions resumed |
| Adrian | step 1 of the window: types `resume` in Dev3's chat on the MSI | nothing | Dev3's first STATUS line within 5 min |
| Coordinator | reads HANDOFF section 0 and R2.0; posts one STATUS line: day one, H0, critical path unchanged | the kickoff | the STATUS file's mtime moves |
| everyone else | reads its kickoff; starts its H0-H1 row | | one `BACK` line each |

## H0-H1: Dev3's verdict, Dev1's resumes
| Who | Does | Needs | Output |
|---|---|---|---|
| Dev3 (MSI) | reads `handoffs/INBOX_Dev3_MSI.md`; reads the W2.1 review workflow's result back from its journal; writes the verdict (ACCEPT / ACCEPT WITH FIXES / FIXES) to `handoffs/STATUS_Dev3_MSI.md` | the inbox | `VERDICT W2.1 <...>`, one line to the Coordinator |
| Dev1 (Alienware) | resumes `wsd-refreeze-fixes-wf_0160d274-8d1` (the consolidate step only), then `wsd-x01-bed-knob-wf_98a927c6-4eb` (implement + verify, starting from `design/X01_BedSightLift_draft.md`), then `review-fv-heldfish-wf_d500a4c4-250`; all from cache, none rebuilt | the workflows' caches | `RE-FREEZE DONE` with the three files as the kickoff lists them; the X01 rows `PASS 128`; the held-fish review sent |
| FableDev (MSI) | answers "safe to save?" in one line; re-reads `W2_RUNBOOK.md`; prepares the batch 1 window (pre-images, `promote_batch1.py --dry`) without opening it | Dev3's verdict pending | `BATCH 1 READY, waiting on verdict` |
| Dev2 (Alienware) | CameraAF R1/R2: runs the three sweep probes (check 8 expected to FAIL on rev 4), fixes the thresholds, finishes R1/R2 in both copies (:479, :426) | nothing | the delta to Dev1 |
| WordAgent (Alienware) | BACKLOG rows AF-C1.. from HANDOFF section 0; copies the handoff and kickoffs to `handoffs/cloud_2026-10-07/` with a pre-image | `%CW%` | two files, LF |
| Coordinator | watches STATUS mtimes every 30 min; no "nothing new" replies | | silence |

## H1: the Coordinator's rulings, the batch 1 window
| Who | Does | Needs | Output |
|---|---|---|---|
| Coordinator | rulings R1-R8 from `kickoff/Coordinator.md`, in order: R1 review backups (yes/no and the table), R2 the token settings (applied today), R3 `HomeMinDepthM = 0.35` (asks Adrian for the V-clip check first), R4 the InputMap seam, R5 the options rows, R6 the world clock, R7 git migration and cloud quota (after batch 2), R8 the FishingConfig split as the first R1 item | the eight documents | one STATUS line per ruling, numbered |
| Coordinator | on Dev3's ACCEPT (or ACCEPT WITH FIXES with the fixes already staged): "batch 1 go" to FableDev; on FIXES: no window (stop rule 3) | Dev3's verdict | `BATCH 1 GO <size / hash from the holder's line>` |
| FableDev | the batch 1 window per `W2_RUNBOOK.md`: the Studio lock, Rojo, `promote_batch1.py`, `verify_all.py` MATCH every script / UNMANAGED 0; posts "batch 1 done" | the go; nobody else in Studio on the MSI | `WINDOW batch1 MATCH <n> / UNMANAGED 0` |
| WordAgent | on "batch 1 done": checker rev 6 into the canonical name | the line | one rename, one README table refresh |
| Dev1 | the re-freeze delta for FishingConfig (WasdHoldS, DriftMaxM) to FableDev | the re-freeze done | `FC DELTA <size / hash>` |
| Adrian | the V-clip check for R3 (a trout holding in water under 0.35 m, the 48 cm fish as the ruler) | R3's request | one line to the Coordinator |

## H2-H4: the all-orders check, batch 2 final, the rows, the batch 2 window
| Who | Does | Needs | Output |
|---|---|---|---|
| FableDev | the all-orders check with Dev1's delta last in the FishingConfig chain (6 orders must commute); flags a conflict to the Coordinator instead of resolving it | the delta | `FC CHAIN 6/6 COMMUTE` or `FC CONFLICT <hunk>` |
| Dev3 | WS-E (`design/reviews/WSE_fight_build_FableDev.md`), StrainAudio rev 2, then the W4Suites:1224 nil constant and the `W34_*` suite fixes; no Studio while the MSI window is open | | verdict lines |
| Coordinator | "batch 2 final" when the chain commutes and Dev3's two reviews are in (or the backup rule has closed them) | the two lines | `BATCH 2 FINAL` |
| WordAgent | builds `rows_batch2` ONCE: `make_rows_batch2_WordAgent_ALIENWARE.py --write` from FableDev's dry run; sends the hash | `BATCH 2 FINAL` | `ROWS <size / hash>` |
| FableDev | `promote_batch2.py --dry` (rows_check); pins if clean; the play check; posts lines 2 and 3 of WINDOW READY (`BATCH 2 PROMOTED, dry run MATCH <n> / UNMANAGED 0, FishingServer pending`; `PLAY CHECK DONE, Place1 saved, Rojo connected`) | the rows hash | the two lines |
| Coordinator | posts WINDOW READY (Dev1's line 1, the holder's lines 2 and 3) | the three lines | the block |
| Adrian | steps 2 and 3 of `ADRIAN_WINDOW.md` with `adrian_window.bat`: paste FishingServer into Dev1's test copy (the size check), the FS copy command once, `verify_all.py` MATCH <n> / UNMANAGED 0 | WINDOW READY | `WINDOW DONE ...` |
| Dev2 | the Blender import check in a sandbox (facing axis, scale, texture kept, one MeshPart) | the Alienware sandbox | one line, four answers, to the Coordinator |

## H4-H6: suites, the MP and PERF runs, the close-out, the feel review
| Who | Does | Needs | Output |
|---|---|---|---|
| Dev3 | `W3Suites_Dev3.luau` and `W4Verdicts_Dev3.luau` on the batch-2 build (after the 1224 fix); then the MP run (`design/MP_stress_test.md`, N = 2 and 4 today, 8 if time) and the PERF matrix (`design/PERF_budget.md`: 1/2/4 anglers x 8/16 fish, 60 s each) on the MSI local server, after FableDev's window has closed | the window closed; `PerfProbe` if Dev1 wired it, else the MicroProfiler alone | `evidence/MP/`, `evidence/PERF/` tables |
| FableDev | the close-out runbook: `verify_all.py` once more, pre-images filed, the STATUS line with the live inventory; the git migration day-one checklist starts only if R7 said today | the window done | `CLOSEOUT MATCH <n> / UNMANAGED 0` |
| Adrian | step 4: the feel review per `Phase5_AF/F1_FEEL_REVIEW.md`, 30 min, one line per item; from memory today, by numbers once item 17 (EncounterLog) is wired | the window done | `FEEL REVIEW DONE` |
| Dev1 | reads the held-fish review back; fits the two small patches (`lineM` clamp, FishJudge header) to the real bytes, unapplied | idle after the window | two real patch files in `patches/` |
| Coordinator | the end-of-day STATUS: what landed, what is open, the first item for tomorrow | | one block |

## What runs in parallel per machine
| Machine | Pair | Safe? | Why |
|---|---|---|---|
| Alienware | Dev1 workflow + WordAgent docs | yes | disjoint files; WordAgent is light |
| Alienware | Dev1 workflow + Dev2 Studio sandbox | yes, staggered | disjoint files; both are heavy, so Dev2 runs its sweeps while Dev1's agents are between steps, not during a consolidate |
| Alienware | Dev2 Studio sandbox + WordAgent rows build | yes | the rows script reads staging; Studio reads a TEMP replica of the map |
| Alienware | two Studio instances | no | one Studio per machine; Dev2 owns the Alienware sandbox |
| MSI | Dev3 offline suites + FableDev's window | yes | the suites run under the CLI from `tests/`; the window owns Studio |
| MSI | Dev3's MP or PERF run + FableDev's window | no | both need Studio; Dev3 waits for `WINDOW DONE` |
| MSI | Dev3 review workflow + FableDev dry runs | yes | files only |
| both | a write on one machine read on the other | only after the sync | OneDrive lag: the reader checks the `size / hash` in the relay before using the file (the Oct 4 lesson) |

## What each session must NOT do today
- Nobody writes `src/` outside a window; only the lock holder (FableDev), only during the batch 1 and batch 2 windows.
- Nobody but Adrian copies `FishingServer`; the `.bat` never does.
- Dev1 does not rebuild a cached workflow; a failed consolidate is recovered from `journal.jsonl` (the TOKEN_AUDIT recipe).
- WordAgent does not build `rows_batch2` before `BATCH 2 FINAL`, and builds it once.
- FableDev does not resolve a FishingConfig conflict; it flags the hunk.
- No cloud module goes into `src/` or staging today; the modules are reviewed as new files and routed after.
- No session launches a workflow above about 250 k context or when it is about to pause; no `xhigh` on relays (R2).
- The Coordinator posts once to the STATUS file; no re-relays; no monitor replies that say nothing.
- Only Dev3 edits `PARITY_CHECKLIST.md`; only WordAgent regenerates README tables, once, after the windows.
- Nobody types a `size / hash` pair from memory; every relay copies it from the owner's line.

## Stop rules
| Trigger | Rule | Who acts |
|---|---|---|
| a session hits the limit while it holds a review | paused from that moment; `REVIEW_BACKUP_RULE.md` applies (the 2 h clock starts at the report; on the critical path the Coordinator may reassign at once, which R1 should say) | the Coordinator reassigns; the backup rules on existing evidence |
| a red suite (any `FAIL k of n`, a compile error, `check_lf` FAIL) in a batch's files | no window; the owner fixes in staging, the reviewer re-checks the hunk, the dry run reruns | the holder refuses the go |
| Dev3's W2.1 verdict is FIXES | batch 1 stays out; FableDev fixes in `w21/`; Dev3 re-reviews (backup Dev1 if Dev3 pauses) | Coordinator |
| `verify_all.py` MISMATCH or UNMANAGED > 0 | the ADRIAN_WINDOW stop rule: stop at the step, post the line and the report, touch nothing; the holder rolls back from `pre/` and re-posts WINDOW READY | Adrian, then FableDev |
| a workflow fails on resume | recover the partials; one small consolidate agent; never a full re-run | Dev1 |
| a CRLF or BOM found by `check_lf.py` in staging | fix before promotion; no window with a `w/crlf` file | FableDev |
| a FishingConfig hunk that does not commute | the Coordinator decides the order; nobody edits another session's patch | Coordinator |

## The 12 cloud items to read during idle waits (no Studio, no `src/`, no staging)
| # | Item (HANDOFF id) | Who | When idle | Done = |
|---|---|---|---|---|
| 1 | R2.2, the six notes' key rulings (26) | Coordinator | after R1-R8 | six numbered answers |
| 2 | `design/ROBLOX_constraints.md` section 7 (29) | Coordinator, Adrian | H2-H4 | the maturity label and the mobile share answered |
| 3 | `design/reviews/cloud_modules_review_Cloud.md`, the 13 fixed hunks and F14 (25) | Dev1 | between workflows | one verdict line |
| 4 | `patches/W21_InputController_lineM_clamp_DRAFT.md`, `W3_FishJudge_header_DRAFT.md` (2, 3) | Dev1 | H4-H6 | real patches, unapplied |
| 5 | `design/WSH_options_panel_additions.md` (12) | Dev2 | waiting on R5 | the rows picked for F1 |
| 6 | `design/WSI_touch_gamepad.md` (13) | Dev2, Dev1 | waiting on R4 | one objection line, or none |
| 7 | `design/mockups/` (30) | Dev2, Adrian | any | the PlayStation glyphs marked for replacement |
| 8 | `design/PARITY_rows_F2plus.md` merge (18) | Dev3 | after the suites | 29 rows in `PARITY_CHECKLIST.md`, ids X60-X68, P01-P20 |
| 9 | `design/WSN_net_v3_messages.md` + `NetSchemaV3.lua` (27) | Dev3 | after the merge | the v2 decoder's unknown-id answer |
| 10 | `process/GIT_MIGRATION.md` day-one checklist; `tools/check_lf.py` into the dry run (6) | FableDev | after the close-out | `check_lf` in the dry run |
| 11 | `tests/run_all.sh` and `RobloxStub.luau` against the oracle runners (16) | FableDev | any | one line: adopt the stub or not |
| 12 | `design/templates/` adopted; `process/TOKEN_AUDIT.md` answered in one line (22, 5) | WordAgent, everyone | any | templates under `Phase5_AF/design/templates/`; six one-line answers |
