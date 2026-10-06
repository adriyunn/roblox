Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files;
every line number, key name and existing-code claim below comes from the team's transcripts and must be checked by Dev1 (server, FishBrain, FishPool), Dev2 (FishPoolView, HookLineView) and Dev3 (the Studio runs) against the real files.

# PERF: a frame-time budget for the fish view and the pool

Status: DRAFT, FOR RULING (section 9). Net and state impact: none (no new cue, state, guard rule or wire byte).

**Decision.** Three budgets, measured the same way every time: server fish step **<= 1.0 ms** per step for 8 fish at
60 Hz; client `FishPoolView` **<= 0.5 ms** per frame for 8 fish; `HookLineView` line draw **<= 0.3 ms** per frame. Medians
over a 60 s window must be under budget and p95 under twice the budget, at 4 anglers and 16 fish. A `PerfProbe` module
wraps `os.clock` and a MicroProfiler label; an offline harness catches regressions in FishBrain's pure functions before
Studio. Over budget means fewer rays, wider samples or distance LOD, never a change of step rate (the bite timing is
pinned to dt).

## 1. Known costs

| Where | Cost driver | Scales with |
|---|---|---|
| FishBrain (server) | sight rays: 3 samples per ray, several rays per step per fish (notice, LOS, two Seek rays after X01); the bed query; Seek path | fish x rays x samples, every step |
| FishPool (server) | refills: `ringHome` candidates with `depthAt` (two per attempt after WSD_shallow_shore), `SPAWN_RETRY_S` cadence; `takeHooked`/`handBack`/`endHooked` | attempts, not fish |
| FishPoolView (client) | per-frame bed clamp per fish (bed + 0.0895); depth fade per fish; the swim-off samples `waterAt` every 0.5 m along the path | fish, every frame; swim-off only while a fish fades |
| HookLineView (client) | LineShape segments, kinks, the per-frame rebuild of the line's parts or beams | segments, every frame, one line per visible angler |
| Net cues (both) | FishingNet v2 encode/decode, FeedbackUI and FishingWaterFX handlers | cues/s, bursty at Nip/Swallow/Snap |
| StrainAudio, CameraAF | one loop, a few lerps | constant |

## 2. Budgets

| Budget | Value | Why that number |
|---|---|---|
| Server fish step (FishBrain + FishPool per step) | <= 1.0 ms at 8 fish; <= 2.0 ms at 16 | a 60 Hz server step has 16.7 ms; physics and replication take most of it; the fishing server should stay under 3 ms in total with 4 anglers |
| Server refill | <= 0.2 ms amortised per step; a single attempt <= 1.0 ms | attempts are rare; one must not spike a step |
| Client FishPoolView | <= 0.5 ms per frame at 8 fish; <= 1.0 ms at 16 | a 60 fps client frame has 16.7 ms; rendering takes most; fishing client code in total <= 2 ms |
| Client HookLineView | <= 0.3 ms per frame per visible line | 4 visible anglers = 1.2 ms worst case |
| Net cues | <= 0.1 ms per frame on the client; <= 30 cues/s per angler on the wire (RequestGuard's ceiling, Dev3's number) | bursts at Snap must not stall a frame |

Per fish: 0.125 ms server, 0.0625 ms client. A new fish feature that costs more than that per fish needs a ruling.

## 3. Measurement in Studio

`Fishing/Shared/PerfProbe.lua` (new, strict, both sides; the `budget_probe.luau` idea from the WSC_WSF benchmarks made
permanent):

```
PerfProbe.begin(label)          -- os.clock() start; debug.profilebegin(label) so the MicroProfiler shows the same name
PerfProbe.finish(label)         -- debug.profileend(); pushes (now - start) into a 3600-sample ring per label
PerfProbe.report(label) -> { n, medMs, p95Ms, maxMs }   -- sorts a copy of the ring
PerfProbe.enabled               -- false by default; one bool check per begin/finish when off
```
Enabled by a workspace attribute `PerfProbe = true` (Studio only; the attribute is never set in Place1 builds). Labels:
`AF_FishStep`, `AF_PoolRefill`, `AF_FishPoolView`, `AF_HookLineView`, `AF_NetCues`.

Procedure (Dev3, sandbox or a local server):
1. Set the attribute, start the run, wait 10 s for the pool to fill.
2. Record 60 s (3600 samples at 60 Hz). Drive the loop with AF1Playtest so fish actually engage (idle fish are cheap).
3. Print `PerfProbe.report` for every label as one line each:
   `PERF AF_FishStep anglers=4 fish=16 n=3600 med=0.61ms p95=1.12ms max=3.4ms`.
4. Repeat for the matrix: anglers 1 / 2 / 4, fish 8 / 16 (6 runs). Fish count via the pool size config or
   `SpawnVisibleFish`.
5. Screenshot the MicroProfiler with the `AF_` labels visible once per matrix row, to `evidence/PERF/`.
6. Any single sample over 5 ms gets its step logged (state counts, refill yes/no) so the spike has a cause.

## 4. The offline harness (spec; Dev1 writes the code)

`tests/perf/fishbrain_bench.luau`, run from its folder with the Luau CLI like the `wsa/` suites:
- Requires `FishBrain` by the relative path the other suites use; injects the analytic bed (`WSD_bed_raycast.md`
  section 5) and a counting LOS function so rays and samples are counted, not guessed.
- Scenarios: `bed` (8 fish, a hook resting on a flat bed 2 m from the homes), `midwater` (hook at 0.5 m above the
  bed), `idle` (no hook; Seek and hover only), `engaged` (one fish through notice, nip, swallow with a scripted press).
- Steps: 600 warm-up steps untimed, then N = 6000 steps (100 s at dt = 1/60) x 8 fish, `os.clock` around the loop, 10
  repeats, median taken.
- Output, one line per scenario: `BENCH bed fish=8 steps=6000 ns/step/fish=1840 rays/step=3.1 samples/step=9.3`.
- Baseline: `evidence/PERF/bench_baseline_<MACHINE>.txt` (ns/step/fish per scenario), written once per machine.
  Pass rule: every scenario <= 1.2 x its baseline on the same machine; prints `PASS 4` or `FAIL k of 4`.
- Negative control: `--mutant rays2x` doubles the rays per step and must FAIL the `bed` row.
- The harness is a regression detector, not a Studio prediction: CLI ns do not convert to Studio ms (different VM
  settings, no engine work around the step). The budget is checked in Studio; the harness says "FishBrain got slower".

## 5. Pass / fail

- PASS: at 4 anglers / 16 fish, every label's median <= budget and p95 <= 2 x budget; no sample over 5 ms without a
  logged cause; the offline harness within 1.2 x baseline.
- FAIL: any median over budget, or p95 over 2 x budget, at any matrix row; or a harness row over 1.2 x baseline.
- A FAIL blocks the next Place1 window for the file that regressed, same as a failing offline suite.

## 6. Over budget: the order to pull levers (cheapest and least visible first)

1. **Rays per step.** Stagger: a fish runs its sight rays on every other step (two cohorts by fish id parity).
   Halves ray cost; the notice-to-nip timing (4.083 s) is set by timers, not by ray cadence, so the offline rows must
   still pass byte for byte in the timers' columns. If they do not, the stagger is wrong.
2. **Samples per ray.** 3 -> 2 (1/3, 2/3) only where the ray is long (> 1 m); keep 3 on the X01 bed case, which is the
   one that needs the low sample.
3. **Swim-off sample spacing.** `waterAt` every 0.5 m -> every 1.0 m along the swim-off; only while a fish fades.
4. **LOD by distance (client).** A fish beyond `ViewClampLodM = 40 m` from the camera (the same 40 m as the snap sound
   radius) refreshes its bed clamp every 0.5 s instead of every frame and skips the depth fade update when its alpha did
   not change. Fish beyond 80 m are not drawn at all (the pool is per lake; a second lake's fish are another pool).
5. **Line segments.** HookLineView draws fewer segments for a line further than 20 m from the camera.
6. **Never** change the server step rate or dt: FishBrain's timing is pinned to dt by the oracle parity.

## 7. Results table template (`evidence/PERF/perf_<date>_<MACHINE>.md`)

| Run | Anglers | Fish | AF_FishStep med / p95 (ms) | AF_PoolRefill med / p95 | AF_FishPoolView med / p95 | AF_HookLineView med / p95 | Cues/s | Max sample (ms, cause) | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 8 | | | | | | | |
| 2 | 1 | 16 | | | | | | | |
| 3 | 2 | 8 | | | | | | | |
| 4 | 2 | 16 | | | | | | | |
| 5 | 4 | 8 | | | | | | | |
| 6 | 4 | 16 | | | | | | | |

Below the table: Studio version, place size/hash, the `FishingConfig` hash, the bench baseline lines, the MicroProfiler
screenshots' file names.

## 8. PARITY

No reference behaviour: the reference is single-player at 60 fps and its budget is its own. Ours is set so the client
holds 60 fps and the server holds 60 Hz with 4 anglers and 16 fish. The one parity constraint is that no lever in
section 6 changes bite timing, which the oracle rows guard.

## 9. Rulings needed (Coordinator)

1. The three budgets in section 2 (1.0 / 0.5 / 0.3 ms) and the p95 = 2 x rule.
2. The matrix (1/2/4 anglers x 8/16 fish) as the standing PERF gate before each Place1 window that touches FishBrain,
   FishPool, FishPoolView or HookLineView; or only at the F1 close-out.
3. `PerfProbe` under `Fishing/Shared/` (Dev1 reviews) and left in the shipped code behind the attribute, or stripped
   by WS-R after F1.
4. The LOD distance 40 m (shared with the snap radius) and the 80 m cull.

## 10. Acceptance tests

- Offline: `luau tests/perf/fishbrain_bench.luau` -> `PASS 4`; with `--mutant rays2x` -> `FAIL 1 of 4`.
- Offline: `PerfProbe` unit rows in `tests/wsa/perfprobe_test.luau`: a ring of 3600 keeps the last 3600; median and
  p95 of a known sequence (1..100) are 50.5 and 95; `enabled = false` makes begin/finish return without touching the
  ring (counted calls = 0). Negative control: a wrong p95 index fails the row.
- Studio: the six-run matrix filled in the section 7 table, every row PASS by the section 5 rule.

## 11. Who does what

- Dev1: `Fishing/Shared/PerfProbe.lua`, the server labels in `FishingServer` around the FishBrain step and the pool
  refill, `tests/perf/fishbrain_bench.luau`, the baseline file, the stagger lever if needed.
- Dev2: the client labels in `FishPoolView` and `HookLineView`, the LOD lever (section 6.4, 6.5) if needed.
- Dev3: runs the matrix, fills `evidence/PERF/perf_<date>_<MACHINE>.md`, keeps the gate in the close-out runbook.
- FableDev: reviews the harness and the baseline method.
- Coordinator: section 9.
