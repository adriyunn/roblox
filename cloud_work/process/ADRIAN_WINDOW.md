Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Adrian's window: four hand steps in 10 minutes

## Why one window
On 2026-10-04 Adrian's four hand steps were spread over the day: Dev3 waited for `resume` from 05:34 to 17:50; the FishingServer paste and copy each wait on a different session; the feel review waits on both. Batched into one window, Adrian sits down once, the sessions queue their prerequisites before it, and nothing waits on him afterwards.

`adrian_window.bat` beside this file walks the steps with a pause after each. It reads, runs the dry run and opens one document. It never copies FishingServer (team rule: no agent writes that file), never deletes, never writes under `src/`.

## Before the window: WINDOW READY
The Coordinator posts one STATUS block with three lines. The window does not open without all three.

| Line | From | Text |
|---|---|---|
| 1 | Dev1 | `RE-FREEZE DONE FishingServer.server.lua <size> / <hash>` (or a commit SHA once git is in) |
| 2 | Holder (FableDev) | `BATCH 2 PROMOTED, dry run MATCH <n> / UNMANAGED 0, FishingServer pending` |
| 3 | Holder | `PLAY CHECK DONE, Place1 saved, Rojo connected` |

## The steps
| # | Step | Machine | Waits on | Adrian does | Exact check | Time |
|---|---|---|---|---|---|---|
| 1 | Resume Dev3 | MSI | nothing | types `resume` in Dev3's Claude Code chat | within 5 min Dev3 writes a new STATUS line (`BACK ...` or its W2.1 verdict); the `.bat` shows the newest 3 lines of Dev3's STATUS file if `DEV3_STATUS` is set | 1 min + wait |
| 2 | Paste FishingServer into Dev1's test copy | Alienware | line 1 | follows `Phase5_AF/W2_ADRIAN_SERVER_INSTALL.md` with the re-frozen script, into Dev1's sandbox copy only, never Place1 | the staged file's size in bytes (the `.bat` prints it) equals the size in Dev1's line; then Dev1 confirms `TEST COPY INSTALLED <size> / <hash>`. The hash itself is checked by the dry run in step 3, not by Adrian | 3 min |
| 3 | The FishingServer copy | MSI | line 2 and line 3 | runs the one copy command from `Phase5_AF/ADRIAN_FS_COPY.md`, exactly once, in his own window; the holder confirms `SYNCED`; then the `.bat` runs `python Phase4\closeout\verify_all.py <live inventory json> <report>` | MATCH count equals the holder's `n` (every mapped script), UNMANAGED 0, no MISMATCH, exit code 0, and the FishingServer row shows the new size | 3 min |
| 4 | Start the feel review | MSI | step 3 passed | plays the F1 loop in the order `Phase5_AF/F1_FEEL_REVIEW.md` gives; writes one line per item in that document | none; this is the review. Ends with `FEEL REVIEW DONE` to the Coordinator | 30 min, outside the 10 |

Steps 1 to 3 fit in 10 minutes when WINDOW READY is complete. Step 4 is its own 30 minutes.

## Stop rule
If a check fails, Adrian answers anything but `y` at the pause. The script stops and prints the step number. Adrian posts the failing line (and the report path if step 3 ran) to the Coordinator and does nothing else. He does not continue the remaining steps by hand, does not re-run the copy, does not undo anything. The holder rolls back (`pre/`, or git after the migration) and re-posts WINDOW READY.

A step whose prerequisite line is missing is a failed check too.

## Placeholders the `.bat` uses
| Variable | Meaning | Default if unset |
|---|---|---|
| `GAMEONE` | project root, no trailing backslash | none; the script stops |
| `LIVE_JSON` | the live inventory json for `verify_all.py`; the holder names it in line 3 | `%GAMEONE%\Phase4\closeout\live_inventory.json` (a guess; set it) |
| `FS_STAGED` | the re-frozen FishingServer in staging, for the size check | `%GAMEONE%\Phase5_AF\w3\Phase5_AF\src\FishingServer.server.lua` (the README's staging layout; set it if Dev1 names another path) |
| `DEV3_STATUS` | Dev3's STATUS file, for the step 1 check | unset; the check is then by eye |
| report | written by `verify_all.py` | `%GAMEONE%\Phase5_AF\evidence\window\verify_window_step3.txt` |

The only file the window writes is that report.

## After the window
The Coordinator's STATUS line: `WINDOW DONE: Dev3 resumed; test copy installed; FS copied, dry run MATCH <n> / UNMANAGED 0; feel review started`. WordAgent refreshes the README tables once, after.
