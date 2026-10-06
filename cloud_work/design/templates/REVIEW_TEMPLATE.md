Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Review template

File name: `design/reviews/<topic>_review_<Dev>_<MACHINE>.md`. A backup review (process/REVIEW_BACKUP_RULE.md) adds a first line `Backup review for <Original> (paused since <time>)`.

---

```
# Review: <topic>
Reviewer: <Dev> (<MACHINE>), <YYYY-MM-DD HH:MM UTC>
Reviewed: <file or patch or branch>, <size / hash> or <sha7>
Base: <the file or commit the change is against>, <size / hash> or <sha7>
Design note: design/<WS>_<topic>.md rev <n>; rulings applied: <ids>

## Verdict
<ACCEPT | ACCEPT WITH FIXES | FIXES | BLOCKER>
<one line: what decides it>

## Findings
| Id | Severity | File:line | Claim | Reproduced by | Fix asked |
|---|---|---|---|---|---|
| F1 | must | Fishing/Client/InputController.lua:412 | lineM is not clamped; an out-of-range click holds the pitch at 2.07 | tests/wsa/<name>.luau check 7, and a sandbox click past the marker | clamp to C.AF.Cast.LineMaxM before the pitch lookup |
| N1 | nit | FishJudge.lua:12 | header says Late = eject only; Late now spooks the other engaged fish too | read | update the two header lines |

## What was run
| Suite or check | Command | Result |
|---|---|---|
| <suite> | luau tests/wsa/<name>.luau | PASS 41 |
| syntax | luau-compile --null <file> | ok |
| types | luau-analyze <file> | 0 errors, <n> warnings (list any new) |
| patch gate | python Phase3/tools/patch_tool.py check <patch> <file> | every block once |
| sandbox | <what was played, how long> | <what was seen>; frames in evidence/<WS>/ |

## What was not checked
- <thing>, because <reason> (no Studio in this session / the oracle has no case for it / out of scope)
- <thing>

## Reply line for the Coordinator
REVIEW <topic> <sha7 or size / hash> by <Dev> (<MACHINE>): <VERDICT>; <F ids by severity>; <N count> nits; suites <pass>/<total>; design/reviews/<file>.md
```

---

## Rules
| Item | Rule |
|---|---|
| Verdict words | `ACCEPT` (nothing to change), `ACCEPT WITH FIXES` (only `should` and `nit`; the author fixes, no re-review), `FIXES` (at least one `must`; re-review of the fixed hunks only), `BLOCKER` (the change must not be promoted; names what unblocks it) |
| Ids | `F1..` for `must` and `should`, `N1..` for `nit`; never renumbered in a later rev; a late finding is `F<n>-late` |
| Severity | `must`: wrong behaviour, a broken gate, a departure from an approved note; `should`: right behaviour, wrong way (cost, clarity, a missing negative control); `nit`: text, naming, a comment |
| Claim | one sentence, with the number that proves it (a value, a count, a time) |
| Reproduced by | a suite and check number, a command, or a sandbox step; "read" is allowed for nits only |
| Fix asked | what to change, not how to feel about it; one line |
| What was run | every command with its printed result; a suite that was not run is not listed here, it goes under "not checked" |
| Not checked | always present; "nothing" is not an answer |
| Reply line | one line, pasteable; the Coordinator relays this and nothing else |

## Example reply lines
```
REVIEW W4_FishingVisuals_heldFish 22,426 / 917709886 by Dev1 (ALIENWARE): ACCEPT WITH FIXES; F1 should; N1-N3 nits; suites 41/41; design/reviews/W4_heldFish_review_Dev1_ALIENWARE.md
REVIEW dev2/w4-heldfish 3f9c2ab by Dev1 (ALIENWARE): FIXES; F1 must, F2 should; N1 nit; suites 40/41 (check 7 fails); design/reviews/W4_heldFish_review_Dev1_ALIENWARE.md
```
