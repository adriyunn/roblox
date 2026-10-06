Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Git migration: `Roblox/GameOne` from OneDrive + hand hashes to `adriyunn/roblox`

## Why now
On 2026-10-04 the team paid for the lack of version control four times:

| What happened | Cost | What git does instead |
|---|---|---|
| Every relay carried a `size / hash` pair typed by hand (e.g. `43,609 / 1409089990`); most relays were copied on to one or two more sessions | Coordinator context 430,439 tokens, much of it relays | one commit SHA names the whole tree; a STATUS line carries 7 characters |
| Dev2's rev 6b patch files "hadn't synced to the MSI" | a review waited on OneDrive | `git fetch` is sync you can see and check |
| 16 saved files had CRLF endings from Windows stdout redirection; FableDev converted them to LF by hand | FableDev time inside a window | `.gitattributes` normalises on commit; `git ls-files --eol` finds the rest |
| `FishingConfig.lua` (~70 KB) took three concurrent patch chains; FableDev proved all 6 orders commute by hand | review time, risk | a merge finds overlapping hunks; non-overlapping ones merge alone |

## What replaces what
| Today | After | Note |
|---|---|---|
| `size / hash` per file in messages | commit SHA (7 chars) in the STATUS line; blob SHA (`git hash-object`) when one file matters | `verify_all.py` keeps its 32-bit checksum for live Studio vs disk |
| `patches/*.patch.txt` + `pre/` pre-images | a commit on a branch; the pre-image is the parent (`git show <sha>^:<path>`) | `patch_tool.py` still works inside a branch during the transition |
| `w21/`, `w3/` staging folders | branches `stage/w21`, `stage/w3`, files at their mapped paths | a promotion is a merge, not a copy |
| `promote_batch1.py`, `promote_batch2.py` (hash-gated copy) | `git merge --no-ff stage/<batch>` into `gameone/main`, gated by the same rows file reading `git hash-object` | the rows file gains a `sha` field |
| OneDrive as the transport between MSI and Alienware | `git fetch` before work, `git push` after | OneDrive keeps `.rbxl` backups and clips only |
| `verify_all.py` | unchanged | the gate at every handover stays (TEAM_RULES §5) |
| Rojo map `Phase4/rojo/default.project.json` | unchanged | paths are relative to the GameOne root |
| `README.md` tables (`size / hash` columns) | one more column, `sha`, from `git rev-parse HEAD:<path>` | `make_readme_tables.py` reads git once |

## Repository layout
The repo `adriyunn/roblox` already has `main` with an unrelated `main.html`. GameOne does not touch it.

| Branch | Holds | Who writes |
|---|---|---|
| `gameone/main` | the tree Place1 runs (what `src/` is today), a root branch with its own history | the Studio-lock holder, by merge, inside a window |
| `stage/w21`, `stage/w3` | batch 1 and batch 2, reviewed and accepted, waiting for a window | the Coordinator, by merge from a dev branch on ACCEPT |
| `dev1/<topic>`, `dev2/<topic>`, `dev3/<topic>`, `fable/<topic>`, `word/<topic>`, `cloud/<topic>` | one piece of work each, branched from the stage it targets | the owning session |
| tags `w2-closed`, `batch1-promoted`, `batch2-promoted`, `f1-closed` | the tree at each window | the holder, after the dry run reads MATCH |

The GameOne folder is the root of the tree on `gameone/main`: `Phase3/`, `Phase4/`, `Phase5_AF/`, `BACKLOG.md`, `TEAM_RULES.md`, and so on, exactly as on disk.

## Where the folder lives
Two choices. A is the plan; B is the fallback if the sessions cannot change their working directory this week.

| | A: clone outside OneDrive (recommended) | B: stay in OneDrive |
|---|---|---|
| Path | `C:\Dev\GameOne` on the MSI and on the Alienware | `C:\Users\adria\OneDrive\Desktop\Claude\Roblox\GameOne` as today |
| Git dir | normal `.git` inside the clone | `git init --separate-git-dir "%LOCALAPPDATA%\GameOne.git"` so OneDrive never syncs the object store; the worktree keeps a one-line `.git` pointer file |
| Transport | GitHub | still OneDrive for the bytes, git only as the ledger |
| Sessions | each session's working directory moves to its worktree (below); best done at the limit reset when sessions restart anyway | nothing changes |
| Sync lag | gone | stays |
| Two machines | two clones, `fetch` before work | one shared worktree, two indexes that go stale as OneDrive changes files; expect `git status` noise |

The OneDrive copy stays untouched in both cases until the first window succeeds from git (see Rollback).

## Line endings and ignores
`.gitattributes` at the root:

```
* text=auto eol=lf
*.lua  text eol=lf
*.luau text eol=lf
*.py   text eol=lf
*.json text eol=lf
*.md   text eol=lf
*.bat  text eol=crlf
*.rbxl binary
*.png  binary
```
The first four lines are the rule; the rest are Cloud's additions (`.bat` needs CRLF for `goto` labels in cmd).

`.gitignore` at the root:

```
# Place files and backups stay in OneDrive
*.rbxl
*.rbxlx
*.rbxl.lock
Backups/
sandboxes/
# recordings live in C:\Users\adria\Videos; contact sheets are large
*.mp4
*.mkv
# python
__pycache__/
*.pyc
```

Large images. Git cannot ignore by size, so two rules:

| Rule | How |
|---|---|
| `evidence/**/*.png` of 5 MB or less | committed as normal files |
| over 5 MB | kept out: moved to OneDrive `Roblox/GameOne_media/evidence/<same path>` and referenced by that path from the evidence note. Alternative: Git LFS (`git lfs install`, `git lfs track "evidence/**/*.png"`); GitHub's free LFS quota is about 1 GB of storage and 1 GB per month of bandwidth, so check it before choosing. Cloud recommends keep-out. |

A pre-commit hook enforces the 5 MB line. `.githooks/pre-commit` (Git for Windows runs bash hooks):

```bash
#!/bin/bash
# refuse any staged file over 5 MB that is not LFS-tracked
limit=5242880
git diff --cached --name-only --diff-filter=AM -z | while IFS= read -r -d '' f; do
  if git check-attr filter -- "$f" | grep -q 'filter: lfs'; then continue; fi
  size=$(git cat-file -s ":$f")
  if [ "$size" -gt "$limit" ]; then
    echo "refused: $f is $size B (> 5 MB). Keep it in OneDrive or track it with LFS." >&2
    exit 1
  fi
done
```
Install once per clone: `git config core.hooksPath .githooks`.

## The hash gates with git
The gate keeps its shape: a rows file says what each mapped file must be; a script checks it before and after the promotion; `verify_all.py` checks live Studio against disk. Only the identity changes.

| Step | Today | With git |
|---|---|---|
| The reviewer accepts | verdict names `size / hash` | verdict names the commit SHA on the dev branch; the rows file gets `"sha": "<40 hex>"` per path from `git rev-parse <branch>:<path>` |
| Before the window | holder compares `size / hash` of the staged file | holder runs, in `gameone/main`: `git status --porcelain` empty; `git fetch`; for each row `git rev-parse stage/<batch>:<path>` equals the row's `sha` |
| The promotion | hash-gated copy `w3/...` to `src/...` | `git merge --no-ff stage/<batch>`; a conflict stops the window (nothing is written to Studio yet) |
| After the merge | `verify_all.py` dry run | for each row `git hash-object --no-filters <path>` equals the row's `sha`, and `git ls-files --eol <path>` shows `w/lf`; then `verify_all.py` dry run as today: MATCH every script, UNMANAGED 0 |
| Pre-image | copy to `pre/` | `git rev-parse HEAD` before the merge, written in the window log; rollback is `git reset --hard <that sha>` before `rojo serve`, or `git revert -m 1 <merge sha>` after |

Why `--no-filters`: with `text=auto eol=lf` the filtered hash would hide a CRLF file on disk. The gate must hash the bytes Rojo serves.
`git hash-object` returns SHA-1 (40 hex). `rows_batch*.json` keeps `size` and `hash` for one batch so both scripts can run side by side.

## First push on Windows
Done once, on the MSI, by the lock holder (FableDev) inside a window, with OneDrive paused ("Pause syncing, 2 hours") so nothing half-written syncs. Git for Windows 2.40 or later.

```bat
cd "C:\Users\adria\OneDrive\Desktop\Claude\Roblox\GameOne"
git --version
git config --global core.autocrlf false
git config --global core.longpaths true
git init --separate-git-dir "%LOCALAPPDATA%\GameOne_import.git"
```
Write `.gitattributes` and `.gitignore` as above. Then:

```bat
git add .gitattributes .gitignore
git add -A
git status --short | findstr /i "\.rbxl"          &REM must print nothing
git ls-files --eol | findstr /r "w/crlf"            &REM lists CRLF files on disk; expect none after FableDev's LF pass
git commit -m "GameOne: import from OneDrive (W1+W2 closed; FishTest.rbxl 2,009,257 B, SHA-256 28dfd07b...; verify_all MATCH 58 / UNMANAGED 0)"
git branch -M gameone/main
git remote add origin https://github.com/adriyunn/roblox
git push -u origin gameone/main
git branch stage/w21 gameone/main && git branch stage/w3 gameone/main
git push origin stage/w21 stage/w3
```
If `findstr /r "w/crlf"` lists files: convert them to LF (the same pass FableDev did), `git add -A`, check again, then commit.
The `w21/` and `w3/` folders come in with this commit as they are. Moving their files to their mapped paths on `stage/w21` and `stage/w3` is the first job on those branches (one commit each, by the holder, `git mv`), after which the folders are deleted on the stage branches only.

Then on each machine:

```bat
git clone --branch gameone/main https://github.com/adriyunn/roblox C:\Dev\GameOne
cd C:\Dev\GameOne
git config core.hooksPath .githooks
git config core.longpaths true
```
Finally, on the MSI, remove the import pointer so the OneDrive copy is a plain folder again: delete the one-line `.git` file in the OneDrive GameOne and the `%LOCALAPPDATA%\GameOne_import.git` folder. These are the only deletes in the plan, and they come after the Alienware clone has pulled the same SHA.

Optional: set the repo's default branch to `gameone/main` on GitHub so a plain `git clone` lands there. Otherwise always clone with `--branch gameone/main`.

## Per-session workflow
Three sessions share the Alienware and two share the MSI. One clone per machine with one working tree would let one session's `git switch` change the files another session is reading. So: one worktree per session.

```bat
cd C:\Dev\GameOne
git worktree add C:\Dev\wt\dev1 -b dev1/scratch gameone/main
git worktree add C:\Dev\wt\dev2 -b dev2/scratch gameone/main
git worktree add C:\Dev\wt\word -b word/scratch gameone/main
```
`C:\Dev\GameOne` itself is the holder's tree and the only one `rojo serve` points at Place1. Each session's working directory is its worktree.

| Who | Does |
|---|---|
| A Dev starting work | `git fetch origin` then `git switch -c dev2/w4-heldfish origin/stage/w3` (branch from the stage the work targets) |
| Committing | `luau-compile --null` and the suites first; `git add -p`; `git -c user.name="Dev2 (Alienware)" commit -m "FishingVisuals: held fish from the presented state (W4; design/WSG_WSH.md)"`; `git push -u origin dev2/w4-heldfish` |
| STATUS line | `REVIEW dev2/w4-heldfish 3f9c2ab -> Dev1` (7-char SHA replaces the `size / hash` pair) |
| Reviewer | `git fetch`; `git worktree add C:\Dev\wt\review-3f9c2ab 3f9c2ab`; review; the verdict names `3f9c2ab`; `git worktree remove` after |
| Coordinator on ACCEPT | `git switch stage/w3`; `git pull --ff-only`; `git merge --no-ff dev2/w4-heldfish`; `git push` |
| A conflict in `FishingConfig.lua` | the later branch's owner runs `git rebase origin/stage/w3`, resolves, re-runs suites, pushes; the reviewer re-checks the conflicted hunks only. This replaces the by-hand proof that patch orders commute |
| The lock holder before a window | `cd C:\Dev\GameOne`; `git switch gameone/main`; `git pull --ff-only`; `git status --porcelain` must be empty; the gates above; only then `rojo serve` |
| The lock holder after the dry run | `git tag batch2-promoted`; `git push --tags`; STATUS line `WINDOW batch2 <sha7> MATCH <n> / UNMANAGED 0` |

Commit messages: `<File or area>: <what> (<WS or batch>; <design note>)`. Author name per session, so `git log` shows who.

## Rojo keeps working
- The map is `Phase4/rojo/default.project.json` with paths relative to the GameOne root. The root moves; the paths do not.
- `rojo serve Phase4/rojo/default.project.json` is started from `C:\Dev\GameOne` by the holder only. Sandboxes keep reading a TEMP replica of the map as today.
- `b11_map_check_WordAgent_ALIENWARE.py` reads the same map and rows files; unchanged.
- Before the move, grep every tool and note for an absolute path: `findstr /s /i /n "OneDrive\\Desktop\\Claude" *.py *.md *.bat *.json` from the GameOne root. Each hit is either made relative or becomes a `GAMEONE` environment variable. The Luau CLI path (`...\Capital Rift\tools\luau\`) is outside GameOne and stays.

## Three risks
| Risk | What goes wrong | Mitigation |
|---|---|---|
| OneDrive and git in the same folder | OneDrive syncs `.git/objects` and lock files mid-write; the repo corrupts or two machines fight over `index.lock` | Plan A: the clone lives outside OneDrive. Plan B: `--separate-git-dir` under `%LOCALAPPDATA%`, never under OneDrive. Never both a synced `.git` and a clone |
| Two machines, two clones | a session edits a file another machine already changed; the merge surprises at window time | `git fetch` before every piece of work; branch from `origin/stage/*`, not from a local branch; the holder's `git pull --ff-only` refuses a diverged `gameone/main` and stops the window |
| Large binaries | a 2 MB `.rbxl` per save or a 20 MB contact sheet bloats the history for ever | `.gitignore` for `*.rbxl`, `Backups/`, `sandboxes/`; the 5 MB pre-commit hook; media stays in OneDrive |

## Rollback
The OneDrive copy is not changed, moved or renamed until the first Place1 window has run from `C:\Dev\GameOne` and `verify_all.py` reads MATCH for every script and UNMANAGED 0. Until then every session can go back to the OneDrive folder and the `size / hash` relays with no loss. After that window the OneDrive GameOne is renamed `GameOne_onedrive_2026-10-xx` and kept read-only as the pre-git snapshot, beside `Backups/` and the clips.

## Day one checklist
1. Coordinator rules: Plan A or B, keep-out or LFS for large PNGs, default branch yes or no.
2. Holder takes the Studio lock; pauses OneDrive on the MSI.
3. Holder writes `.gitattributes`, `.gitignore`, `.githooks/pre-commit`; `git init --separate-git-dir`; `git add -A`; checks for `.rbxl` and `w/crlf`.
4. Holder commits, renames to `gameone/main`, pushes; creates `stage/w21` and `stage/w3`; pushes.
5. Both machines clone to `C:\Dev\GameOne`; `git log -1` shows the same SHA on both; hooks path set.
6. One worktree per session; each session's STATUS line reports its worktree and `git rev-parse --short HEAD`.
7. Holder moves `w21/` files to mapped paths on `stage/w21`, `w3/` files on `stage/w3`; one commit each; the rows files get a `sha` per row.
8. FableDev adds the `sha` check to `promote_batch1.py` and `promote_batch2.py` beside the `size / hash` check; both run on one batch.
9. First window from git: `git pull --ff-only`, gates, `rojo serve`, `verify_all.py` MATCH every script / UNMANAGED 0, tag.
10. Only then: rename the OneDrive GameOne; relays switch to SHAs; `README.md` tables gain the `sha` column.
