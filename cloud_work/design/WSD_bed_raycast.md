Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files;
every line number, key name and existing-code claim below comes from the team's transcripts and must be checked by Dev1 (FishZones, FishBrain, FishPool) and Dev2 (FishPoolView) against the real files.

# WS-D: a real bed under the fish (raycast beside `FishZones.depthAt`)

Status: DRAFT, FOR RULING (section 9). Net and state impact: none (ruling 3 keeps `bedY` off the wire; the client
samples its own rays).

**Decision.** Each fish gets a bed height from a raycast straight down, cached and refreshed every `BedSampleS = 0.5 s`
or after moving more than `BedSampleMoveM = 0.5 m`, with `FishZones.depthAt` kept as the fallback when the ray misses.
The ray is the primary source for FishBrain's `fish.bedY` (the X01 sight rays and the mouth floor) and for the home
depth test; the client FishPoolView uses the same helper for its per-frame clamp so both sides stand on the same bed.
Cost is negligible (section 4). Offline tests and the oracle share one injected `bedAt(x, z)`, so nothing in the pure
code knows about `workspace:Raycast`.

## 1. Why

`FishZones.depthAt` is an estimate, off by -9..+9 cm against the real terrain. Dev1's X01 data: the BedSightLift fix
is clean when the estimate is at or above the real surface and fails progressively when the estimate sits 3, 6 or 9 cm
below it (the real mouth is lower than the model's, the lifted ray grazes again). The backup knob `BedMouthM` papers over
the 3 cm case. A ray removes the error at its source and makes `BedMouthM` unnecessary unless section 8 says otherwise.

## 2. The sampler (`Fishing/Shared/FishBed.lua`, new; strict; author Cloud draft, Dev1 owns)

Pure part (shared by server, client, tests and the oracle's twin):

```
FishBed.new(bedAt: (x: number, z: number) -> number?, cfg) -> sampler
sampler:bedY(fish, now: number) -> (bedY: number, source: "ray" | "est" | "none")
```
- Cache per fish id: `{ y, t, x, z, source }`.
- Refresh when `now - t >= cfg.BedSampleS` or `dist2((x, z), fish pos) >= cfg.BedSampleMoveM^2`.
- On refresh: `y = bedAt(fish.x, fish.z)`; if `nil`, `y = estimateAt(fish.x, fish.z)` (FishZones.depthAt's bed) with
  `source = "est"`; if that is nil too, keep the last cache and `source = "none"`.
- Before the first refresh the value is `-math.huge` (X01's "before the first bed query" case stays as it is).

Studio adapter (server and client, the only Roblox-touching lines):

```lua
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain, bedPartsFolder }  -- bedPartsFolder: the lake's bed meshes, if any
params.IgnoreWater = true        -- without this the ray stops at the water surface and bedY = waterY
local function rayBedAt(x: number, z: number): number?
	local origin = Vector3.new(x, waterY(x, z) + 0.5, z)   -- start above the surface, never from inside the terrain
	local hit = workspace:Raycast(origin, Vector3.new(0, -(C.AF.Fish.BedRayLenM), 0), params)
	return hit and hit.Position.Y or nil
end
```
The origin is above the water, not at the fish's pivot: if the pivot is already inside the terrain (estimate too low),
a ray from the pivot would miss or hit the next layer down. `BedRayLenM = 6` covers any F1 lake.

Config, block `C.AF.Fish`:

```lua
BedSampleS     = 0.5, -- WS-D bed ray (Dev1, 2026-10-06): a fish re-samples its bed this often; 2 rays/s/fish
BedSampleMoveM = 0.5, -- or sooner after moving this far; a seek at 1 m/s re-samples twice a second anyway
BedRayLenM     = 6.0, -- ray length down from 0.5 m above the surface; deeper lakes raise it
BedRayEnabled  = true, -- false = depthAt only (the rollback switch; also the negative control in B5)
```

## 3. Who reads `bedY`

| Reader | Today | After |
|---|---|---|
| FishBrain (X01 sight rays, mouth floor, `PathLiftM` path) | `fish.bedY` from the first `depthAt` query | `fish.bedY` from `sampler:bedY(fish, now)` each step; same field, the brain does not change |
| FishPool home test (`WSD_shallow_shore.md`) | `depthAt` | `bedAt` through the same sampler's `bedAt` function (no cache: a candidate is one point, sampled once) |
| FishPoolView per-frame clamp (bed + 0.0895) | `_waterAt`'s bed on the client | the client's own `FishBed` sampler on the same cadence; the clamp stays per frame, the *source* refreshes at 2 Hz |
| FishPoolView swim-off (waterAt every 0.5 m) | unchanged | unchanged |

Interactions.
- **Bed clamp (bed + 0.0895).** Server and client both clamp against a ray bed now, so the client's fish no longer floats
  up to 9 cm above or sinks 9 cm into the visual bed where the estimate was wrong. The two sides sample the same
  replicated terrain, so they agree to float noise; no net field is added (ruling 3 if Dev1 prefers to replicate).
- **BedSightLiftM (X01).** Sized for an exact bed at 0.03 = the hook radius. With the ray bed the remaining error is
  the terrain surface's own (section 8), so the lift stays 0.03 and `BedMouthM` stays unapplied.
- **The hook.** LureSim's hook rests on the real terrain by contact (WaterTruth / LureSim contact). With the ray the
  fish's bed and the hook's bed are the same surface, which is the whole point.

## 4. Cost

8 fish x 2 rays/s = 16 rays/s. A terrain raycast of 6 m costs on the order of 5..20 us (Dev1 measures once with
`os.clock` around 1,000 rays). At 20 us: 16 x 20 us = 320 us per second = 0.32 ms/s, which is 0.0053 ms per 60 Hz
step. The client adds the same for its own sampler. At 16 fish and a seek-heavy pool (every fish moving, so the move
trigger fires ~4 times/s): 64 rays/s x 20 us = 1.3 ms/s = 0.02 ms per step. All of it is inside the noise of the
`PERF_budget.md` server budget (1.0 ms per step for 8 fish).

## 5. Offline test approach

- FishBrain and FishPool take `bedAt` as an injected function (the sampler's constructor argument). The Studio adapter
  passes `rayBedAt`; the tests pass an analytic bed; the oracle (`fish_oracle.py`) implements the same analytic bed.
- Analytic beds, shared by name between the Luau suite and the oracle: `flat(y0)`, `slope(k)` (`bedY = -k x`),
  `ledge(x0, drop)` (a step of `drop` at `x = x0`), `hole(cx, cz, r)` (returns nil inside the hole, to exercise the
  fallback), `estimateError(bed, e)` (the bed plus a constant error e, standing in for `depthAt`).
- The sampler's cache needs a clock: the suite passes `now` explicitly (no `os.clock` in pure code).
- The oracle's trace gains `bed_y` and `bed_source` columns; parity compares them.

## 6. Acceptance tests (rows B1..B8; Studio rows marked)

| Row | Setup | Expect |
|---|---|---|
| B1 (Studio) | the flat test lake, 10 points, a part dropped to rest at each point | `rayBedAt` within 1 cm of the part's resting Y |
| B2 (Studio) | the 0.3-slope beach, 20 points along the slope | `|ray - depthAt| <= 9 cm` everywhere (documents the estimate error); ray within the voxel surface error of the rendered bed (section 8) |
| B3 | offline, `ledge(2.0, 0.2)`, a fish seeking at 1 m/s across x = 2.0 | `bedY` steps by 0.2 within 0.5 s of crossing (the move trigger fires at 0.5 m, so within 0.5 s at 1 m/s) |
| B4 | offline, `hole(0, 0, 1)` under a fish | `source = "est"` and `bedY` = the estimate; the fish keeps stepping |
| B5 | offline, X01 bed rows with `estimateError(flat, -0.06)` as `depthAt` | `BedRayEnabled = true`: PASS (the ray ignores the estimate). `BedRayEnabled = false`: FAIL (negative control; reproduces Dev1's 6 cm data) |
| B6 (Studio) | 16 fish, 60 s, the PERF probe around the ray calls | median <= 0.02 ms per step, p95 <= 0.05 ms |
| B7 (Studio) | `IgnoreWater = false` once, on purpose | `bedY == waterY` at every point: proves the flag matters (negative control) |
| B8 | offline, cache cadence: a still fish for 10 s with a counting `bedAt` | exactly 20 calls (+1 for the first) |

## 7. PARITY

Reference: the fish body collides with the level's collision shapes, so its bed is exact and needs no estimate.
We: `depthAt` was an estimate with up to 9 cm of error; a raycast against the terrain is the same exact bed the reference
has. No player-visible difference once in; the fish stops floating or sinking into the bed on uneven lakes.

## 8. Risk: terrain voxel resolution

Roblox terrain is 4 x 4 x 4 stud voxels (about 1.1 m at Roblox's usual 0.28 m per stud; the team's WS0b scale note has
the figure that applies). The raycast hits the terrain's smoothed collision surface, which is the surface the player
sees, so the ray's error against the *visual* bed is small. Its error against the *analytic* bed the lake was built from
can still be several cm wherever the voxel surface rounds a slope or a ledge. That error is real for the fish too (the
fish is drawn against the visual surface), so it is the right one to carry. **Measure in Studio** (B1, B2): if the ray
sits more than 3 cm under the rendered surface anywhere on the beach, `BedMouthM` comes back for that case; if it does
not, retire the knob.

Second risk: the lake has bed meshes or parts (docks, rocks) that are not terrain. `FilterDescendantsInstances` must
include them or the fish will stand inside a rock. Dev1 lists the lake's non-terrain bed instances once; a
CollectionService tag `FishBed` on them keeps the list out of code.

## 9. Rulings needed (Coordinator)

1. Ray as the primary bed source with `depthAt` as fallback (proposal), or ray only as a backup behind the estimate.
2. `BedSampleS = 0.5` and `BedSampleMoveM = 0.5`. Faster costs nothing measurable; slower makes B3 lag.
3. Client samples its own rays (proposal; no wire change) vs the server replicating `bedY` in the fish pose message
   (a FishingNet v2 codec change, Dev3's net vectors, W2 wire gate again). Proposal: client rays.
4. `FishBed.lua` under `Fishing/Shared/` (both sides read it) and therefore Dev1's review.
5. `BedMouthM` retired once B1/B2 show the ray within 3 cm of the rendered bed.

## 10. Who does what

- Dev1: `Fishing/Shared/FishBed.lua` (new), the `bedAt` injection in `FishBrain.lua` and `FishPool.lua`, the server
  adapter in `FishingServer`, the config keys (`patches/WSD_FishingConfig_bedRay.patch.txt`), `tools/fish_oracle.py`
  columns, B3/B4/B5/B8 rows in `tests/wsa/fishbrain_test.luau` or a new `tests/wsa/fishbed_test.luau`, B1/B2/B6/B7 in
  the sandbox with the frames to `evidence/WSD/`.
- Dev2: `Fishing/Client/FishPoolView.lua` (the clamp's bed source becomes the client sampler; the swim-off is
  unchanged), the client adapter; Dev1 reviews.
- Dev3: reviews the negative controls (B5, B7), PARITY_CHECKLIST row, the `FishBed` tag list check.
- WordAgent: the config patch doc, README rows.
