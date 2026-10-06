Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files;
every line number, key name and existing-code claim below comes from the team's transcripts and must be checked by Dev1 against the real files.

# X01: BedSightLift, the bite fix for a hook resting on the bed (implementation draft for Dev1)

**Decision.** One new knob, `BedSightLiftM = 0.03`, and one helper, `sightY(fish, hook)`. Every sight ray that today
aims at the hook's centre aims at `sightY` instead: the hook's top when the hook lies on the bed, its centre
everywhere else. Nothing else in FishBrain moves. Mid-water behaviour is byte-identical to the frozen module;
only the bed rows change. `BedMouthM = 0.054` stays in the drawer unless Studio shows the bed estimate 3 cm or more
under the terrain (section 7). This is Dev1's own diagnosis written out as a patch doc; he owns every number.

## 1. The fault, in one paragraph

A hook resting on the bed has its centre at bed + 0.03 m (LureSim `RadiusM` 0.03). The fish's mouth sinks to
bed + 0.04..0.055 m. The mouth-to-hook sight ray is sampled at 1/4, 1/2 and 3/4 of its length, so its lowest
samples sit 3..4 cm above the bed estimate, inside the bed tolerance, and the ray reads as blocked. A blocked ray
sends the fish to Seek. Seek re-arms any bite timer with <= 1 s left and resets the 2 s give-up. The fish never
bites and never leaves. Aiming the ray at the hook's top (bed + 0.06 m) lifts every sample above the graze line;
the mouth-to-hook distance test, the charge, the nip and the swallow are untouched because they do not use the
ray's end point.

## 2. Config: `Fishing/FishingConfig.lua`, block `C.AF.Fish`

New line, placed next to the other bed/hook metres in the block (after the hook radius if that is in this block,
else at the end of the block). Draft patch block:

```
@@@ OLD
<the last line of the existing C.AF.Fish bed/hook metres; Dev1 picks the anchor line>
@@@ NEW
<that line, unchanged>
	BedSightLiftM = 0.03, -- X01 (Dev1, 2026-10-06): a hook lying on the bed is sighted at its top (centre + this), not its centre; = the hook radius (LureSim RadiusM 0.03). 0 restores the old rays.
@@@ END
```

Range: 0 (old behaviour) .. 0.05. Units metres. Not a tuning knob for feel; it is the hook's radius with a name.

## 3. FishBrain `DEFAULTS`, the entry after `PathLiftM`

FishBrain is pure and offline-tested, so it carries its own `DEFAULTS` table that the Studio adapter overrides from
`C.AF.Fish`. The new entry goes directly after `PathLiftM` so the two "lift" metres read together:

```
@@@ OLD
	PathLiftM = <existing value>,
@@@ NEW
	PathLiftM = <existing value>,
	BedSightLiftM = 0.03, -- X01: sight rays aim at a bed-resting hook's top (design/X01_BedSightLift_draft.md)
@@@ END
```

If FishBrain reads config through a `cfg` table on the fish (`fish.cfg`) the helper below reads `fish.cfg.BedSightLiftM`;
if it reads a module-level `CFG`, substitute. Dev1 knows which.

## 4. The helper (strict Luau; compiled and run under the CLI on 2026-10-06, 7/7 rows)

Put it next to the other small geometry helpers near the top of FishBrain, above the first call site (:959).
`BodyBoxY` is the body box height key FishBrain already reads from `C.AF.Fish`; the formula is Dev1's.

```lua
-- X01: the height a sight ray aims at on the hook. A hook lying on the bed (its centre within
-- BodyBoxY/2 + lift of the fish's bed estimate) is sighted at its top so the ray clears the bed;
-- a hook in open water, or any hook before the first bed query (bedY = -inf), is sighted at its centre.
local function sightYCore(hy: number, bedY: number, bodyBoxY: number, lift: number): number
	if hy - bedY <= bodyBoxY * 0.5 + lift then
		return hy + lift
	end
	return hy
end

local function sightY(fish: Fish, hook: Hook): number
	return sightYCore(hook.y, fish.bedY, fish.cfg.BodyBoxY, fish.cfg.BedSightLiftM)
end
```

Notes.
- `fish.bedY` is `-math.huge` before the first bed query. `hy - (-inf)` is `+inf`, the test is false, the ray aims at
  the centre. No special case needed, and the oracle must do the same (section 6).
- The boundary `hy - bedY == BodyBoxY/2 + lift` counts as "on the bed" (`<=`), matching Dev1's wording.
- `sightYCore` exists so the test suite and the oracle comparer can hit the arithmetic without building a fish.
- Export `sightYCore` on the module table (`FishBrain._sightYCore`) only if the suite needs it; otherwise keep it local.
- With `BedSightLiftM = 0` both functions return `hy` for every input: the old module.

## 5. The four call sites (before/after pseudo-diffs; line numbers from the transcripts, Dev1 confirms)

Only the y of the ray's **end point** changes. The hook's position used for distances, the swim target, the mouth
offset and the strike stays `hook.y`.

**5.1 Notice, ~:1077.** "Can the fish see the hook from where it is?" on the way into Notice.
```
@@@ OLD
<the ray from the fish's eye/mouth to (hook.x, hook.y, hook.z); the call that returns seen/blocked>
@@@ NEW
<the same call with hook.y replaced by sightY(fish, hook) in the end point only>
@@@ END
```

**5.2 LOS check, ~:986.** The per-step line-of-sight test with the 1/4, 1/2, 3/4 samples.
```
@@@ OLD
<losClear(fish, hook.x, hook.y, hook.z) or the inline sample loop ending at hook.y>
@@@ NEW
<losClear(fish, hook.x, sightY(fish, hook), hook.z); the sample loop interpolates toward the lifted y>
@@@ END
```
If the loop computes the samples from a `dy` it must take `dy` from the lifted end point, not from `hook.y`.

**5.3 Seek, ~:959 and ~:963.** Seek's two ray tests (the one that decides whether the hook is in view from the
current pose and the one that decides whether a candidate approach point has a clear line). Both get the same
substitution in the end point. The approach point itself (where the fish swims to) does not change; if :963 derives
the approach point *from* the ray's end point, derive it from `hook.y` as before and lift only the ray.

**Invariant to keep.** `grep -n "hook.y\|hook\.pos\.y" FishBrain.lua` after the change: every remaining `hook.y` is a
distance, a target or a strike height; none is a sight-ray end point. List them in the patch's first-line comment.

## 6. Oracle model B (`tools/fish_oracle.py`)

Model B is the Python twin of FishBrain the parity comparer runs against.
1. Add `sight_y(hook_y, bed_y, body_box_y, lift)` with the exact arithmetic of `sightYCore`
   (`if hook_y - bed_y <= body_box_y * 0.5 + lift: return hook_y + lift; return hook_y`), `bed_y = float('-inf')`
   before the first bed query.
2. In `integrate()`, set `bed_seen = True` on the step the first bed query happens (where `bed_y` leaves `-inf`).
   The flag exists so the comparer catches a Luau/Python disagreement on *when* that first query lands; before it the
   two models must both aim at the centre.
3. Add `sight_y` and `bed_seen` as trace columns. The mid-water golden trace gains two columns but no row changes.
4. `fish_oracle.py --parity` compares the Luau trace to the Python trace row by row, including the new columns.

## 7. Backup knob `BedMouthM = 0.054` (only if Studio shows the bed estimate 3 cm or more under the terrain)

Do not apply with section 5. If, in the X01 gate, the fish's rendered mouth sits visibly inside the terrain or the
bed rows pass offline but the fish still goes to Seek in Studio, the bed estimate (`FishZones.depthAt`, off by
-9..+9 cm) is sitting under the real surface and the real mouth is lower than the model thinks.

- `BedMouthM = 0.054`: the mouth never sinks below `fish.bedY + BedMouthM` while a hook lies on the bed
  (same "on the bed" test as `sightY`). 0.054 is the top of the observed 0.04..0.055 band, so it only bites when
  the mouth would have gone lower than it ever does on an exact bed.
- Config line: `BedMouthM = 0.054, -- X01 backup (Dev1): mouth floor above a bed-resting hook; 0 = off. Apply only if the bed estimate sits >= 3 cm under the terrain (design/X01_BedSightLift_draft.md section 7).`
- The longer fix is a real bed under the fish: `design/WSD_bed_raycast.md`.

## 8. Tests to add (`tests/wsa/fishbrain_test.luau`, today 122/122; g = 0.045)

`g` is the suite's bed-gap parameter for the bed rows (the mouth-above-bed value, mid of the 0.04..0.055 band;
Dev1 confirms the name). Rows in the suite's style, 50 seeds each where a median is asked for:

| Row | Setup | Expect |
|---|---|---|
| X01-1 | fixed hook on a flat bed, centre at bed + 0.03, g = 0.045 | every seed swallows; median first Swallow in 5..45 s |
| X01-2 | lure hook (LureSim-driven, resting then twitched by a reel pulse) on the same bed | same as X01-1 |
| X01-3 | hook mid-water (hy - bedY = 0.5 m), the frozen scenario | trace byte-identical to the frozen module's golden trace (`sim/` golden file; the two new oracle columns excluded from the byte compare or regenerated once with Dev1's sign-off) |
| X01-4 | X01-1 with `BedSightLiftM = 0.02` (mutant) | the bed rows FAIL (negative control: the lowest sample still grazes). If 0.02 passes, the rows are not sensitive enough: lower g to 0.04 until the mutant fails, and record the g that separates them |
| X01-5 | `sightYCore` table: (0.03, 0, 0.1, 0.03) -> 0.06; (0.08, 0, 0.1, 0.03) -> 0.11; (0.0801, 0, 0.1, 0.03) -> 0.0801; (0.03, -inf, 0.1, 0.03) -> 0.03; (0.03, 0, 0.1, 0) -> 0.03 | exact |
| X01-6 | bedY = -inf for the first 3 steps then a bed at 0: the aim switches from centre to top on the first bed step | aim y 0.03, 0.03, 0.03, 0.06 |

Expected summary line: `PASS 128` (122 + 6). Any FAIL stops the patch.

## 9. PARITY

Reference: the fish's sight ray aims at the hook origin; its physics mouth cannot graze because its bed is exact.
We: the ray aims at the hook's top when the hook lies on the bed, at the centre everywhere else; mid-water identical to
the reference's aim and to our frozen module. The difference exists only because our bed is an estimate; it is
invisible to the player (no timing, speed or pose changes).

## 10. Rulings needed (Coordinator)

1. Approve `BedSightLiftM = 0.03` as the X01 fix for fidelity (no player-visible change; the bite now happens).
2. `BedMouthM` stays unapplied unless the section 7 condition is met in the X01 gate. Confirm.
3. The mid-water golden trace: keep byte-identical by excluding the two new oracle columns, or regenerate once.

## 11. Acceptance tests

Offline: section 8 rows, `luau fishbrain_test.luau` -> `PASS 128`; `python fish_oracle.py --parity` -> every row
MATCH including `sight_y` and `bed_seen`; `luau-compile --null FishBrain.lua` clean.
Studio (the X01 gate, sandbox then Place1): `SpawnVisibleFish`, a hook rested on a flat bed 2 m from the fish's home.
Expect Notice -> first nip at 4.083 s -> Swallow inside 45 s on 5 of 5 runs; if the angler never presses, the fish
leaves on the 2 s give-up instead of hovering forever. Record the hover frames to `evidence/X01/` beside the
existing ones.

## 12. Who does what

- Dev1: `Fishing/Shared/FishBrain.lua` (helper, DEFAULTS, the four call sites), `tools/fish_oracle.py` model B,
  `tests/wsa/fishbrain_test.luau` rows X01-1..6, the two patch docs
  `patches/X01_FishBrain_bedSightLift.patch.txt` and `patches/X01_FishingConfig_bedSightLift.patch.txt`,
  the X01 gate run, the evidence.
- Dev3: reviews the suite rows and the negative control; adds the PARITY_CHECKLIST row.
- WordAgent: README patch table rows after the patches land.
- Coordinator: section 10.

## 13. Dev1's checklist

1. Pre-image `FishBrain.lua` and `FishingConfig.lua` to `pre/`.
2. Diff after the edit: only the helper, the DEFAULTS line and the four end points changed. Run the `grep -n "hook.y"` invariant from section 5.
3. `luau-compile --null FishBrain.lua`.
4. `luau fishbrain_test.luau` from `tests/wsa/`: `PASS 128`; then flip the lift to 0.02 and see `FAIL` on the bed rows; flip back.
5. `python fish_oracle.py --parity`: MATCH every row.
6. `python Phase3/tools/patch_tool.py check <patch> <mapped file>` for both patches against the live bytes.
7. Sandbox: the X01 gate (section 11), frames to `evidence/X01/`.
8. Hand to the lock holder for the Place1 window; `verify_all.py` MATCH / UNMANAGED 0 after.
