Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Proposed TEAM_RULES addition: review backups

## The rule in one line
No review gate waits on one paused session.

## What it fixes
On 2026-10-04 Dev3 was paused from 05:34 to at least 17:50 UTC (12 h 16 min): it needed Adrian to type `resume` in its chat on the MSI. Both batches waited on Dev3's W2.1 verdict for the whole time. One idle session held 60 + 69 scripts out of Place1 for half a day.

## Definitions
| Term | Meaning |
|---|---|
| Paused | no new STATUS line from the session for more than 2 h, or a prompt is waiting in its chat that only Adrian can answer (`resume`, a permission, a question) |
| Reviewer of record | the session TEAM_RULES names for that file class (step 5 of "How a change reaches Place1") |
| Backup | the session in the table below for that domain |
| Existing evidence | the design note, the patch or branch, the suites already in `tests/`, the sandbox notes and frames the author filed |

## Rules
1. A review has a reviewer of record and a named backup from the moment it is assigned. The assignment line names both: `REVIEW <topic> <sha7> -> Dev3 (backup Dev1)`.
2. If the reviewer of record is paused for more than 2 h while a review is open, the Coordinator reassigns to the backup with one line: `REASSIGN <topic> Dev3 -> Dev1, Dev3 paused since 05:34`. No wait for the original to agree; it is paused.
3. The backup's review goes in `design/reviews/<topic>_review_<Backup>_<MACHINE>.md` with the first line `Backup review for <Original> (paused since <time>)`. The verdict carries the same weight as the original's.
4. The gate closes on the backup's verdict. The batch does not wait for the original.
5. The original, once back, reads the backup's review first. It may add findings for 1 h after it resumes, as `F<n>-late` / `N<n>-late` rows under the backup's table. It does not re-review, and it does not change the verdict; a `-late` finding at severity `must` goes to the Coordinator as a new ruling, not as a reopened gate.
6. One backup per review. If the backup is also paused, the Coordinator picks any session that did not write the change. The author never reviews its own work.

## Backup table
| Reviewer of record | Domain | Backup | Why this backup |
|---|---|---|---|
| Dev3 | net, guard, `StateRules`, `RequestGuard`, `LatencyBudget` | Dev1 | owns the server side those modules sit in |
| Dev3 | tests and suites (`W3Suites_Dev3.luau`, `W4Verdicts_Dev3.luau`, `tests/wsa/*`) | FableDev | runs the oracles and parity comparers already |
| Dev3 | removals of client code (WS-R) | Dev2 | owns the client files the removals touch |
| Dev1 | `FishingServer`, `FishingVisuals`, `Fishing/Shared/*` | FableDev | reviewed W2.1 server-side work; holds the promotion scripts that gate them |
| Dev1 | `FishBrain`, `FishPool` | Dev3, through the oracle (model B, `sight_y`, `bed_seen`) | the offline oracle is the evidence; Dev3 runs suites, not Studio |
| Dev2 | client: camera, view, catch, feedback, poses | Dev1 | already reviews Dev2's client work (TEAM_RULES) |
| FableDev | sims (`LureSim`, `LineKinks`, `LineShape`, oracles in `sim/`) | Dev1 | wrote the parity tests in `tests/wsa/` |
| FableDev | promotion scripts and their docs (`tools/promote/*`, rows files) | WordAgent, doc checks only | keeps the README tables and the rows file; checks that the script matches its doc and the rows, not that it is correct |
| WordAgent | docs, README tables | Coordinator | reads them anyway |

## What the backup may do
- Give a verdict (ACCEPT / ACCEPT WITH FIXES / FIXES / BLOCKER) on the existing evidence.
- Re-run existing suites and oracles and quote the pass counts.
- Read the change in a sandbox and record what it saw.
- Ask the author one round of questions, with a 1 h reply window.

## What the backup may not do
- Write new suites, checks or oracle cases in the original's name or in the original's files (`*_Dev3.luau` stays Dev3's). A new check the backup needs goes in its own file, `<topic>_backupcheck_<Backup>.luau`, and is listed in the review.
- Change the review's scope (a backup review of the W2.1 batch is a review of the W2.1 batch).
- Lower the bar: the same verdict words, the same `must/should/nit` severities, the same "what was run / not checked" sections (see `design/templates/REVIEW_TEMPLATE.md`).

## How the original catches up
| When | What |
|---|---|
| Back online | reads the backup's review before anything else; STATUS line `BACK, read <topic>_review_<Backup>` |
| Within 1 h | may append `-late` findings with evidence; nothing else |
| After 1 h | the review is closed to it; new concerns go to the Coordinator as a ruling request (`design/templates/RULING_REQUEST_TEMPLATE.md`) |
| Always | takes the next review in its domain as reviewer of record; the backup rule is not a transfer of ownership |

## Pause detector for the Coordinator's monitor
One line, not a loop:

> Watch the modification time of each session's STATUS file. Alert when `now - mtime > 2 h` for a session that holds an open review. Check every 30 min, never every minute. Say nothing when nothing changed.

Why: on 2026-10-04 the Coordinator's monitor on "new lines in FableDev/Dev3 MSI status files" fired at 17:37:40, 17:38:00, 17:38:20, 17:39:15, 17:43:49, 17:49:19 and 17:52:17 and the Coordinator answered "nothing new" each time. That monitor could not see the one thing that mattered, Dev3 silent for 12 h, because it watched for new lines and the problem was the absence of lines. An mtime check sees absence.

With git in place (`process/GIT_MIGRATION.md`) the same check reads `git log -1 --format=%ct origin/dev3/<branch>`.

## Cost of the rule
One reassignment line and one backup review, roughly the same tokens as the original review would have cost. The alternative on 2026-10-04 was 12 h of two batches waiting and an Adrian hand step (`resume`) that no agent could do.
