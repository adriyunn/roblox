# cloud_work: offline work for About Fishing F1 and after

Written by Cloud (session roblox-9d) on 2026-10-06/07, in the cloud, without access to the project
files on the MSI and Alienware. Everything here is either **new and self-tested** (modules, tools,
assets) or a **draft against code I only know from the transcripts** (patches, design notes). Every
file says which it is at the top and names the dev who checks it.

Start with `HANDOFF_COORDINATOR.md`: it routes every item to its owner.

## Layout
| Path | What | State |
|---|---|---|
| `CONTEXT.md` | The digest of the six sessions' transcripts the rest was written from | reference |
| `HANDOFF_COORDINATOR.md` | What each item is, who takes it, what it unblocks | read first |
| `pull_cloud_work.bat` | Pulls this branch next to GameOne on Windows and opens the handoff | run on either machine |
| `src/Fishing/Shared/*.lua`, `src/Fishing/Server/SaveData.lua`, `src/Fishing/Client/*.lua` | Eleven pure Luau modules with no Roblox globals; services are injected; reviewed adversarially (`design/reviews/`) | tested, `luau-analyze` clean |
| `tests/` | `RobloxStub.luau` (fake clock, DataStore, JSON, Instance, Players, RunService), one `*_test.luau` per module, `run_all.sh`, `fixtures/` (encounter samples, net vectors) | 15 suites, 1,018 checks, all PASS |
| `tools/` | `setup_luau.sh`, `check_lf.py`, `parity_report.py` + `parity_bands.json`, `net_vectors_v3.py` | tested |
| `design/` | 14 design notes, `PARITY_rows_F2plus.md`, `SFX_ART_LIST.md`, `ROBLOX_constraints.md`, `reviews/`, `mockups/`, `templates/` | drafts for rulings |
| `kickoff/` | One ready-to-paste message per session | for Adrian |
| `process/` | Git migration, reviewer backup rule, token audit, cloud quota, Adrian's window, FishingConfig split | proposals |
| `patches/` | Two DRAFT patch docs (lineM clamp, FishJudge header) | Dev1 fits to real bytes |
| `clips/DEMO_CLIP_LIST.md` | 29 clips (V42-V70) to record in the About Fishing demo | for Adrian |
| `blender/` | `fish_generator.py`, 5 FBX presets in `exports/`, previews in `previews/` | placeholders for F2 |
| `../.github/workflows/luau-ci.yml` | The same gate as CI on every push | live on this branch |

## Run the gate
```
bash cloud_work/tools/setup_luau.sh      # Linux: installs luau, luau-compile, luau-analyze (once)
bash cloud_work/tests/run_all.sh         # compile at -O0/-O1/-O2, every suite, python tests, LF check
```
On Windows with the team's CLI on PATH: run each suite from its folder, `luau tacklebox_test.luau`.

## Modules (all `--!strict`, services injected, JSON-safe save forms)
| Module | Checks | One line |
|---|---|---|
| `TackleBox` | 71 | The reference's grid inventory: polyomino items, 4 rotations, place/move/remove, first-fit, "would it fit if I dropped these", a save form that rejects a tampered box |
| `SpeciesTable` | 53 | Species rows (trout tuned, 4 placeholders): length roll, weight law, size class → box shape, brain overrides, fight, spawn by depth and time of day, lure multipliers, price per kg |
| `GameData` | 45 | Lures, rods, lines, hooks, the starter loadout, sell prices (four median trout = 32 coins), upgrade costs |
| `CatchLog` | 48 | Per-player firsts, records, counts per zone; commutative merge for save conflicts |
| `SaveData` | 103 | DataStore wrapper: retries with backoff, schema migrations, a compare-and-set session lock with a heartbeat, UpdateAsync merges, autosave, BindToClose flush, read-only on corrupt or newer data |
| `EncounterLog` | 68 | One record per fish-angler encounter (capped at 1,000); medians and p95; bands per hook mode; CSV/JSON out |
| `EncounterReplay` | 66 | Tap net traffic, save a tape, replay "in" messages offline and diff the "out" ones |
| `WorldClock` | 40 | 24 h day, phases, weather machine, rain ramp, waves capped at 0.1 m so fish stay visible, bite multiplier |
| `NetSchemaV3` | 210 (+27 py) | The 13 v3 messages: declarative schema, validator, per-state permission, a reference canonical encoding checked against 92 independent Python vectors |
| `TackleBoxUI` (Client) | 127 | Grid geometry, hit testing, a drag state machine with the same four verbs for mouse, touch and gamepad; the renderer injects `canPlace` |
| `CatchCard` (Client) | 49 | The catch card's text: metric or imperial with ounce carry, badges in a fixed order, the price |

## Rules this work follows
LF line endings everywhere (`tools/check_lf.py` enforces it). No sizes or hashes invented: file
identity here is the commit SHA. Nothing copied from About Fishing except how it plays.
