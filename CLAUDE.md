# adriyunn/roblox

Two unrelated things live here. The root (`README.md`, `main.html`) is Adrian's original page: leave
it alone. `cloud_work/` is offline work for **GameOne**, a Roblox Studio fishing game that copies the
*mechanics* of the Steam game About Fishing (never its art, text, names or sounds), built by six
Claude Code sessions on Adrian's MSI and Alienware machines. The real project files
(`Roblox/GameOne/Phase5_AF/...`) are NOT in this repo until `cloud_work/process/GIT_MIGRATION.md` is
done, so everything under `cloud_work/` is either self-contained and tested, or a draft against code
known only from transcripts.

## Read first
- `cloud_work/CONTEXT.md`: the project, the team, their conventions, what exists, the open items.
- `cloud_work/HANDOFF_COORDINATOR.md`: what each file is for and who takes it.
- `cloud_work/README.md`: the layout and the module table.

## The gate (run before every commit)
```
bash cloud_work/tests/run_all.sh
```
Compiles every `.lua`/`.luau` at -O0/-O1/-O2, runs every `tests/*_test.luau` from its own folder
under the Luau CLI, every `*_test.py` under `tests/` and `tools/` with `python3 -I`, and the LF
check. It must end `run_all: PASS`. `luau-analyze <module>` must be clean for every file under
`cloud_work/src/`. CI (`.github/workflows/luau-ci.yml`) runs the same on every push.

The SessionStart hook (`.claude/hooks/session-start.sh`) installs the Luau CLI, `bpy` and Pillow in
cloud sessions. If `luau` is missing, run `bash cloud_work/tools/setup_luau.sh`.

## Rules for code under `cloud_work/src/`
- `--!strict`; header lines in the team's style:
  `-- Name (About Fishing F1, WS-X; Cloud, YYYY-MM-DD; design/<note>.md)` then a one-line purpose,
  then a `WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:` block.
- Pure Luau: no `game`, `script`, `workspace`, `Instance`, `task`, `Random` at module level. Every
  Roblox service is injected (see `SaveData.new(deps, opts)`); randomness is an injected `rng` with
  `NextNumber`/`NextInteger`. Tests use `tests/RobloxStub.luau` (`Stub.new()` for services,
  `Stub.harness(name)` for checks). Add to the stub rather than stubbing inside a suite.
- Save forms are JSON-safe plain tables; `deserialize` re-validates and errors on tampering.
- Client-facing functions return `nil, reason` on bad input; programmer errors `error()`.
- Units in names: `M` metres, `S` seconds, `Deg`, `Px`, `Kg`.
- One `tests/<name>_test.luau` per module, 25+ labelled checks, at least one negative control and one
  serialize round trip, ending with `T.finish()`.

## Rules for docs under `cloud_work/`
- Every file starts with a banner saying it was written without the project files and who checks it.
- Never invent a `size / hash` pair (the team's 32-bit checksum cannot be computed here); identify
  files by commit SHA. Line numbers quoted from transcripts are marked "confirm".
- Design notes follow `cloud_work/design/templates/DESIGN_NOTE_TEMPLATE.md`; reviews follow
  `REVIEW_TEMPLATE.md`; a question for the Coordinator follows `RULING_REQUEST_TEMPLATE.md`.
- Plain words, numbers with units, tables for items with attributes, no filler.

## Line endings and git
LF everywhere except `*.bat` (`.gitattributes` enforces it; `tools/check_lf.py` checks). Work on
branch `claude/hello-b2aghd` unless told otherwise; commit small, push after the gate passes; never
force-push. Commit messages: what changed and why, no model names.

## Blender (`cloud_work/blender/`)
`bpy` runs headless: start scenes with `bpy.ops.wm.read_factory_settings(use_empty=True)`; render with
Cycles on CPU (EEVEE has no GPU here); always absolute output paths; export FBX with
`axis_forward='-Z', axis_up='Y'`; look at every render with the Read tool before calling it done.
