Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# R1: split `FishingConfig.lua` into per-system modules

Priority R1: after F1 closes, before the next workstream touches config. Estimate: 11 dev-hours across three owners plus FableDev (table at the end).

## The problem
`Fishing/FishingConfig.lua` is one file of about 70 KB. On 2026-10-04 it took three concurrent patch chains (WSD W3 to W4 catchScene, aimClick, Dev1's re-freeze delta) and FableDev had to prove that all 6 application orders give the same bytes. Every config patch is hash-gated against the whole file, so any other patch landing first invalidates it. The blocks inside the file already belong to different people:

| Block | Content (from the transcripts) | Who changes it |
|---|---|---|
| `C.AF` | net and cast block (WSA1) | Dev1 |
| `C.AF.Fish` | fish brain knobs: `PathLiftM`, `BedSightLiftM`, `BedMouthM`, ... | Dev1 |
| `C.CameraAF` | camera beats, `Caught` | Dev2 |
| `C.Sounds` | `AimClick` = the `ReelClick` id, strain sounds | WordAgent, Dev2 |
| `C.Feedback` | FeedbackUI block (WSH) | WordAgent |
| `C.Avatar`, `C.View` | WSG step 1 | Dev2 |
| scale constants | WS0b (factor 1.0, body ratio 0.74) | Dev3 wrote them; Dev1 owns |
| `AimClick` keys, `FishSensitivity` | WSH | Dev2, WordAgent |

## Proposed layout
```
src/Fishing/
  FishingConfig.lua          <- step 1: the shim; step 3: deleted
  Config/
    init.lua                 <- assembles C and returns it
    Scale.lua                <- WS0b constants; required first, others read it
    AF.lua                   <- C.AF without Fish
    Fish.lua                 <- C.AF.Fish
    CameraAF.lua             <- C.CameraAF
    Sounds.lua               <- C.Sounds
    Feedback.lua             <- C.Feedback
    Avatar.lua               <- C.Avatar
    View.lua                 <- C.View
    Input.lua                <- AimClick keys, FishSensitivity
```
Place path: `ReplicatedStorage.Fishing.Config` (a ModuleScript, from `init.lua`) with nine child ModuleScripts.

`init.lua`:
```lua
--!strict
-- Config (About Fishing F1, R1; Cloud, 2026-10-06; process/R1_FishingConfig_split.md)
-- Assembles the config table C from the per-system modules. Same keys, same values as the old FishingConfig.lua.
local Scale = require(script.Scale)        -- first: other blocks read it
local AF = require(script.AF)
AF.Fish = require(script.Fish)
local C = {
	Scale = Scale,
	AF = AF,
	CameraAF = require(script.CameraAF),
	Sounds = require(script.Sounds),
	Feedback = require(script.Feedback),
	Avatar = require(script.Avatar),
	View = require(script.View),
}
local Input = require(script.Input)
for k, v in pairs(Input) do C[k] = v end   -- top-level keys the old file kept at the root (AimClick keys, FishSensitivity)
return C
```
The real key names at the root and the nesting of `Fish` under `AF` must be read off the real file; the above follows the transcripts.

A sub-module that needs the scale requires it: `local Scale = require(script.Parent.Scale)`. No sub-module requires `init.lua` or `FishingConfig.lua` (cycle).

## The compatibility shim
Step 1 keeps `FishingConfig.lua` at its path and its place name. It becomes:
```lua
--!strict
-- FishingConfig (About Fishing F1, R1 shim; Cloud, 2026-10-06; process/R1_FishingConfig_split.md)
-- Returns the same C table as before, now assembled by Fishing/Config. Delete in R1 step 3.
return require(script.Parent.Config)
```
Every consumer still does `require(...FishingConfig)` and gets the same table, same identity. No consumer changes in step 1.

## Three-step migration
| Step | What | Proof | Who |
|---|---|---|---|
| 1 | Cut the old file into the nine modules plus `init.lua`; replace the old file with the shim | the offline deep-compare below prints `PASS`; `luau-compile --null` on all eleven files; one sandbox Play with no new output; `verify_all.py` MATCH every script | owners cut their blocks (table below); FableDev assembles and promotes |
| 2 | Consumers that read one block require it directly: `require(Fishing.Config.Fish)` in `FishBrain`, `require(Fishing.Config.CameraAF)` in `CameraAF`, and so on | each consumer's existing suites pass; `luau-analyze` clean under `--!strict` | each consumer's owner, one patch per file, no hurry |
| 3 | Delete the shim; `scan_refs.py --check` style grep shows 0 requires of `FishingConfig` | grep 0; `verify_all.py` MATCH; UNMANAGED 0 | FableDev, in a window |

Step 1 is one window. Steps 2 and 3 can wait weeks.

## Ownership per file
| File | Owner | Reviewer |
|---|---|---|
| `Config/AF.lua`, `Config/Fish.lua`, `Config/Scale.lua` | Dev1 | Dev3 (Scale is WS0b's; Fish is the oracle's) |
| `Config/CameraAF.lua`, `Config/Avatar.lua`, `Config/View.lua`, `Config/Input.lua` | Dev2 | Dev1 |
| `Config/Feedback.lua`, `Config/Sounds.lua` | WordAgent | Dev2 (his Feedback block today) |
| `Config/init.lua`, the shim, the rows | FableDev | Dev1 |

A patch to `Fish.lua` is gated against `Fish.lua`'s hash (or blob SHA) only. Dev2's camera patch and Dev1's fish patch stop colliding.

## The offline test
`tests/config_split/config_split_parity.luau`, run from its own folder with `luau config_split_parity.luau`. It requires a frozen byte copy of the pre-split file (`FishingConfig_pre.lua`, taken from `pre/` or `git show <sha>:Phase5_AF/src/Fishing/FishingConfig.lua`) and the new `Config/init.lua`, deep-compares every key both ways and prints the first mismatch.

```lua
--!strict
-- ConfigSplitParity (About Fishing F1, R1; Cloud, 2026-10-06; process/R1_FishingConfig_split.md)
-- Deep-compares the pre-split FishingConfig with Config/init.lua. Prints MISMATCH lines, ends with PASS n or FAIL k of n.
require("./roblox_stubs")                        -- only if the config calls Vector3.new, Color3.fromRGB, Enum..., UDim2.new
local OLD = require("./FishingConfig_pre")
local NEW = require("./Config")                  -- a copy or junction of src/Fishing/Config for the CLI; script.* does not exist offline

local checks, fails = 0, 0
local firstMismatch: string? = nil

local function fail(path: string, msg: string)
	fails += 1
	if firstMismatch == nil then firstMismatch = path .. ": " .. msg end
	print("MISMATCH " .. path .. ": " .. msg)
end

local function compare(a: any, b: any, path: string, seen: { [any]: boolean })
	checks += 1
	local ta, tb = typeof(a), typeof(b)
	if ta ~= tb then fail(path, "type " .. ta .. " vs " .. tb); return end
	if ta == "number" then
		local bothNaN = a ~= a and b ~= b
		if a ~= b and not bothNaN then fail(path, tostring(a) .. " vs " .. tostring(b)) end
		return
	end
	if ta == "function" then return end          -- presence only; a function in the config is compared by hand
	if ta ~= "table" then
		if a ~= b then fail(path, tostring(a) .. " vs " .. tostring(b)) end
		return
	end
	if seen[a] then return end
	seen[a] = true
	for k, v in pairs(a) do
		local p = path .. "." .. tostring(k)
		if b[k] == nil then fail(p, "missing in new") else compare(v, b[k], p, seen) end
	end
	for k in pairs(b) do
		if a[k] == nil then fail(path .. "." .. tostring(k), "extra in new") end
	end
	if getmetatable(a) ~= getmetatable(b) then fail(path, "metatable differs") end
end

compare(OLD, NEW, "C", {})

-- negative control: a copy with one extra key must be caught
local control = table.clone(NEW)
control.__probe = 1
local before = fails
compare(OLD, control, "C(control)", {})
local caught = fails == before + 1
fails = before
checks += 1
if not caught then fails += 1; print("MISMATCH negative control: an extra key was not caught") end

if fails == 0 then
	print("PASS " .. checks)
else
	print("FAIL " .. fails .. " of " .. checks)
	error("first mismatch: " .. tostring(firstMismatch))
end
```
Notes for the dev who runs it:
- `script.Scale` does not exist under the Luau CLI. Either the modules use `require("./Scale")` style paths that work in both (Luau's string requires resolve relative to the file; check the team's CLI version), or the test copies the folder and rewrites `script.X` to `./X` with a 5-line Python step. The team's existing `tests/wsa/*` already run real `src/` modules offline, so follow whatever they do.
- If the config uses Roblox globals, `roblox_stubs.luau` defines them as plain tables (`Vector3.new(x, y, z)` returns `{ _t = "Vector3", x, y, z }`, `Enum` is a proxy that returns `"Enum.Name.Item"` strings) so the deep-compare sees values.
- Expect `checks` in the hundreds for a 70 KB file. The count is the regression number for future config changes.

## Rojo map change
`init.lua` in a folder is Rojo's rule for "this folder is a ModuleScript named after the folder, with children". If `src/Fishing/` is mapped with `$path` in `Phase4/rojo/default.project.json`, Rojo picks `Config/` up with no JSON change: one folder appears, nothing else moves. If `FishingConfig.lua` is mapped as its own `$path` entry, add one entry for `Config`. Either way the map checker (`b11_map_check`) and the rows file need 10 new rows (`Config` plus nine children) and keep the `FishingConfig` row for the shim until step 3.

## Risks
| Risk | What goes wrong | Mitigation |
|---|---|---|
| Require order | a block reads another at build time (`CameraAF` reading a scale constant); split across modules the read happens before the other module exists, or cycles | `Scale.lua` first and required by name; no sub-module requires `init` or the shim; the deep-compare catches a wrong value |
| `--!strict` types | consumers index `C.AF.Fish.PathLiftM`; today the type is inferred from one literal; after the split `C`'s type is a table of module return types and `luau-analyze` may flag new places | each sub-module ends with `export type T = typeof(M)`; `init.lua` builds `C` from the module values so inference carries through; run `luau-analyze` on every consumer in step 1, fix annotations, no behaviour change |
| Hash gates and rows | promote scripts and `rows_batch*.json` know one `FishingConfig` row; ten new scripts in the place | new rows before the window; `b11_map_check --overlay` rehearsal; `verify_all.py` MATCH every script, UNMANAGED 0 |
| Shared root keys | keys kept at the root of `C` (AimClick keys, FishSensitivity) are easy to lose when cutting | `Input.lua` holds every root key that is not a block; the deep-compare's "missing in new" catches a dropped one |
| Two definitions of a key during the migration | a patch lands on the old file after the cut began | freeze config patches from the cut to the window (one day); the three chains of 2026-10-04 are exactly what this prevents afterwards |
| Studio identity | `require` returns one table per ModuleScript; today everyone shares one `C`; after step 2 a consumer holds `Fish` directly | same table object either way (`C.AF.Fish` is the `Fish` module's table); nothing is copied |

## Estimate
| Work | Hours | Who |
|---|---|---|
| Cut the nine blocks into files, headers, `export type` | 3.0 | Dev1 1.0, Dev2 1.0, WordAgent 0.5, FableDev 0.5 (`init`, shim) |
| Offline deep-compare test, stubs, negative control | 2.0 | Dev3 |
| Review of the cut (one review, three reviewers' blocks) | 2.0 | per the ownership table |
| Rows, map check rehearsal, promote script rows | 1.0 | FableDev |
| Window: promote, dry run, sandbox Play | 1.0 | FableDev (holder) |
| Step 2: consumers require sub-modules (about 8 files, one patch each) | 1.5 | owners, over time |
| Step 3: delete the shim, grep 0, window | 0.5 | FableDev |
| Total | 11.0 | |

Rulings needed: 1. R1 after F1, yes or no. 2. Root keys into `Input.lua` or into their nearest block. 3. Freeze window for config patches during the cut (Cloud proposes one day).
