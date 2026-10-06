Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Cloud sessions: a second quota pool for the work that needs no Studio

## The fact
On 2026-10-04 at about 17:50 UTC all six local Remote Control sessions reported rate-limit type `seven_day` and stopped. This cloud session (claude.ai/code) reports `ccr_promotional`, a different pool. While the six were out, a cloud session could still read, write, review and run offline tests.

## The proposal
Once the code is in git (`GIT_MIGRATION.md`), move every task that needs only files to cloud sessions. Keep the local sessions for what only a machine with Studio can do.

| Task | Where | Why |
|---|---|---|
| Code reviews (find, refute, write) | cloud | needs the branch and the suites; no Studio |
| Oracle sweeps (`tools/*.py`, `sim/`) | cloud | Python and Luau CLI run anywhere; the cloud box has Python; the Luau CLI is one download |
| Offline suites (`tests/wsa/*.luau`, W3/W4 suites) | cloud | same |
| Design notes, ruling requests, README tables, rows files | cloud | files only |
| Patch and branch preparation, rebases, conflict resolution | cloud | git only |
| Diagnoses from evidence frames and transcripts (X01-style) | cloud | reads images and files; writes a note |
| Rojo serve, Place1 windows, `verify_all.py` against live Studio | local, lock holder | needs Studio and the live inventory |
| Play tests, sandbox tests, frames and clips | local | needs Studio and the machine's screen |
| Computer-use steps (Studio UI, typing `resume`) | local or Adrian | needs the desktop |
| Adrian's hand steps (`ADRIAN_WINDOW.md`) | Adrian | by rule |

## What a cloud session cannot do
- No Roblox Studio: no Rojo serve to Place1, no Play test, no live inventory for `verify_all.py`, no frames.
- No OneDrive: it sees only what is pushed to GitHub. Until the migration, it sees nothing of the project (this document was written blind).
- No computer-use on Adrian's machines: it cannot type `resume`, paste a script into Studio, or press Play.
- No Luau CLI until one is installed in the session's setup (a SessionStart hook can download it; the local path `...\Capital Rift\tools\luau\` does not exist there).

## Handing work across
One branch and one STATUS line each way.

| Direction | Steps |
|---|---|
| Local to cloud (a review) | Dev pushes `dev2/<topic>`; STATUS line `REVIEW dev2/<topic> <sha7> -> cloud`; the Coordinator starts a cloud session with the branch name and the review template; the cloud session writes `design/reviews/<topic>_review_Cloud.md` on `cloud/review-<topic>`, pushes, STATUS line `VERDICT <topic> <sha7> ACCEPT WITH FIXES, F1 must, N1-N3` |
| Cloud to local (a fix to test in Studio) | cloud pushes `cloud/<topic>`; STATUS line `TEST cloud/<topic> <sha7> -> Dev1 sandbox`; Dev1 fetches, tests, replies with frames or a pass line |
| Either way | the STATUS file is the single channel; nothing is pasted; the SHA is the identity |

A cloud session has no standing memory of the team. Its prompt must carry: the branch, the template, `CONTEXT.md` (or the README), and the one question it is to answer.

## Caveat
Quota pools are set by the account plan and by promotions, not by where the session runs. `ccr_promotional` may end or change without notice. Before relying on it, confirm on the usage page (claude.ai settings) which pool cloud sessions draw from this week, and re-check after the weekly reset (Oct 6, 2 pm Denver). If both kinds of session report the same pool, this document's split still saves local time but no quota.
