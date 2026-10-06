Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files;
every line number, key name and existing-code claim below comes from the team's transcripts and must be checked by Dev1 (FishPool, FishZones) and Dev3 (W3 rows) against the real files.

# WS-D: fish near shallow shores (POOL-1)

**Decision.** A home is valid when the water there is deep enough for a fish to be a fish: `depth(home) >= HomeMinDepthM`
(0.35 m), plus a small horizontal shore clearance `HomeShoreClearM` (0.3 m) so a turning fish never pokes its nose onto
the beach. The 0.74 m horizontal bubble (`HomeBubbleM`) was a proxy for depth; we measure depth instead. Retry timing
is unchanged; `ringHome` keeps one try per attempt and adds one outward step on a depth-only miss; the GiveUp fallback
may no longer place a fish in water shallower than the rule. The angler placement in Dev3's W3 rows moves so the
ring reaches water that passes.

## 1. The problem

POOL-1: FishPool keeps every home at `shoreSdf >= HomeBubbleM = 0.74 m`, measured horizontally to the shoreline.
Dev3's W3 beach row (slope 0.3, the angler 5..6.7 m back from the water) gets 0 fish, and on shallow shores in general
the GiveUp path falls back to the clamped pose more often than on the test lake.

Two things are wrong with a horizontal-only rule.
1. It accepts bad homes. On a 0.3 slope the bubble's edge sits in 0.3 x 0.74 = 0.22 m of water. The fish's pivot is
   clamped to bed + 0.0895 m and its back is another half body box up (about 0.05 m), so the back is 0.14 m above the
   bed and only 0.08 m under the surface. Waves above ~0.1 hide pool fish (CONTEXT). A fish there is invisible or
   half out of the water.
2. It rejects good homes. On a steep bank (slope 1.0) the water is 0.74 m deep at the bubble's edge; anything inside it
   is rejected although 0.35 m of water would do. On narrow lakes and coves the ring finds nothing, the retries run out,
   GiveUp clamps.

The depth rule fixes both: it rejects the 0.22 m home and accepts the 0.35 m one whatever the slope.

## 2. The rule

```
depth(h)      = waterY - bedAt(h.x, h.z)                      -- bedAt = FishZones.depthAt today, the raycast later (WSD_bed_raycast.md)
valid(h)      = inLake(h)
            and depth(h)    >= HomeMinDepthM                   -- 0.35 m
            and shoreSdf(h) >= HomeShoreClearM                 -- 0.30 m, horizontal
            and <the existing angler and hook exclusions, unchanged>
```
Today: `valid(h) = inLake(h) and shoreSdf(h) >= HomeBubbleM (0.74)`.

Config, block `C.AF.Fish` (the Pool keys), with `HomeBubbleM` kept one release for the rollback and the old rows:

```lua
HomeMinDepthM   = 0.35, -- POOL-1 (Dev1, 2026-10-06): a home needs this much water; pivot clamp 0.0895 + half body box 0.05 + turn room 0.10 + wave cover 0.10 (design/WSD_shallow_shore.md section 3)
HomeShoreClearM = 0.30, -- POOL-1: horizontal clearance to the shoreline so a turning 48 cm trout (half length 0.24) stays wet; replaces HomeBubbleM
HomeBubbleM     = 0.74, -- superseded by HomeMinDepthM + HomeShoreClearM; read by nothing after the POOL-1 patch, removed in the next WS-R pass
```

## 3. Why 0.35 m and 0.30 m

Depth, from the bed up:
- the pivot clamp: the fish's pivot sits at bed + 0.0895 m (FishPoolView's per-frame clamp and the server floor);
- half the body box: about 0.05 m (half of `BodyBoxY`; Dev1's value) puts the back at bed + 0.14 m;
- turn room: the inspect, charge and nip swing the body; 0.10 m of head room keeps the back under water through the swing;
- wave cover: waves ~0.1 hide the fish, so the back must sit at least 0.10 m under the surface to be seen through them.
Sum 0.0895 + 0.05 + 0.10 + 0.10 = 0.34, rounded to **0.35 m**. The hover above a bed-resting hook (mouth at
bed + 0.04..0.055) needs less than this, so it adds nothing.

Shore clearance: a 48 cm trout (`SPAWN_B = 48`, lengthCm) turning about its pivot sweeps a half length of 0.24 m;
with 0.06 m of slack, **0.30 m** keeps the nose over water on every heading.

Consequence on slopes (horizontal distance from the shoreline to the first valid home):

| Bank slope (rise/run) | Depth 0.35 reached at | Shore clear 0.30 | First valid home | Today (0.74) |
|---|---|---|---|---|
| 0.3 (beach) | 1.17 m | 0.30 m | **1.17 m** (depth governs) | 0.74 m, in 0.22 m of water |
| 0.5 | 0.70 m | 0.30 m | 0.70 m | 0.74 m |
| 1.0 (bank) | 0.35 m | 0.30 m | 0.35 m | 0.74 m, in 0.74 m of water |
| 2.0 (wall) | 0.175 m | 0.30 m | 0.30 m (clearance governs) | 0.74 m |

On the beach the first valid home moves **out** from 0.74 to 1.17 m. The ring must reach it: that is why the angler
placement in the W3 rows is part of this change (section 5), not a side effect.

## 4. `ringHome` and the retry path

- `ringHome(center, r, margin)` tries one candidate per attempt with the single margin `HomeBubbleM`. It becomes
  `ringHome(center, r, rule)` where `rule = { minDepthM, shoreClearM }`, still one candidate per attempt. New: when the
  candidate fails on depth **only** (shore clearance passed), it tries once more at `r + HomeDepthStepM` (0.5 m) along
  the same radial, because on a slope deeper water is further out. Two evaluations at most per attempt; the attempt
  count, `SPAWN_RETRY_S`, `RehomeAfterS` and the GiveUp count are unchanged.
- The GiveUp fallback today clamps the candidate to the bubble. New: it takes the deepest candidate seen in this
  attempt series that passed shore clearance; if none reaches `HomeMinDepthM`, the slot stays empty until the next
  `RehomeAfterS` tick. No fish is better than a fish standing in 0.1 m of water (ruling 3).
- `depthAt` cost: one extra bed query per candidate, at most two per attempt; attempts happen at `SPAWN_RETRY_S`
  cadence, so this is nothing against the per-step FishBrain rays.

## 5. What Dev3's W3 rows must change

- The beach row (slope 0.3, angler 5..6.7 m back): the ring's outer radius must reach at least 1.17 m past the
  shoreline, so the angler stands at most `ringMaxM - 1.17 m` back (Dev1 gives `ringMaxM`; if it is 7 m, the angler is
  at most 5.8 m back and the row's 6.7 m case moves to 5.5 m). The row's expectation changes from "0 fish, known" to
  "full pool, every home >= 0.35 m deep".
- The bank and wall rows: more valid ring points than before; expectations become "full pool" where they were
  "partial".
- The channel row (section 6, Y16) keeps its 0.
- Every row logs `depth(home)` and `shoreSdf(home)` per fish so the numbers in section 3 are checked, not assumed.

## 6. Acceptance tests (FishPool suite, continuing the Y1..Y15 numbering; offline under the CLI with an analytic bed)

| Row | Setup | Expect |
|---|---|---|
| Y16 | the W3 1 m channel row (1 m wide, centre depth below 0.35 m, the row's profile) | 0 fish, as today. Negative control: `HomeMinDepthM = 0.10` gives fish here, so the row can fail |
| Y17 | 0.3-slope beach, analytic bed `bedY = -0.3 x`, angler at the section 5 placement, 8 slots | 8/8 homes within 8 x `SPAWN_RETRY_S`; every home `depth >= 0.35` and `shoreSdf >= 0.30`; 0 GiveUp |
| Y18 | 1.0-slope bank, same angler distance | valid ring arc longer than under the 0.74 rule (count the passing candidates per 360 samples: new > old); every home depth >= 0.35 |
| Y19 | flat pond 0.30 m deep | 0 fish (depth rejects). Flat pond 0.40 m deep: 8/8 |
| Y20 | GiveUp fallback: 10,000 random attempt series on the beach with a ring that only grazes the 0.35 m line | no returned home has depth < 0.35; the slot is left empty instead |
| Y21 | `HomeShoreClearM` alone: a 2.0-slope wall, candidates at 0.20 m from the shoreline | rejected (clearance), 0.31 m accepted |

Each row prints one line; the suite ends `PASS <n>` or `FAIL <k> of <n>`.

## 7. Negative control (named, so the suite is known to bite)

Run Y17 with the rule inverted (`depth(h) >= 0` for every h, i.e. the depth test disabled): homes land in 0.22 m of water
and Y17's "every home >= 0.35" line must read FAIL. Run Y16 with `HomeMinDepthM = 0.10`: the channel gets fish and Y16
must read FAIL. Both runs are part of the suite under a `--mutant` flag, and the suite asserts they fail.

## 8. PARITY

Reference (R2): fish zones are authored per lake and drawn in water, so the reference needs no shore rule in code.
We: a generated ring around the angler filtered by depth and shore clearance, the drawn zone's stand-in. Difference
accepted for F1 because GameOne's lakes have no authored zones; the player sees the same thing, a trout holding in water
deep enough to cover it.

## 9. Rulings needed (Coordinator)

1. `HomeMinDepthM = 0.35`. Adrian checks the V-clips (`clips/INDEX.md`, the shore and approach clips) for a trout
   holding in water shallower than 0.35 m, using the 48 cm fish as the ruler: if the clips show the back under the
   surface in about one fish-height of water, 0.30 is the better number; if the fish are always in dark water, keep 0.35.
2. Keep the horizontal clearance at 0.30, or drop it entirely and rely on depth. Proposal: keep it; it is cheap and it
   is the only thing that stops a nose on a vertical wall.
3. GiveUp may leave a slot empty rather than place a fish in shallow water. Proposal: yes.
4. A narrow deep channel (1 m wide, 1 m deep) now gets homes in its middle 0.4 m; the 0.74 rule gave none. Trout do
   hold in narrow deep runs. Say if that is wanted; if not, `HomeShoreClearM = 0.50` restores the old channel behaviour
   at the cost of the wall row.
5. The W3 beach row's angler placement (section 5) is a test change, not a world change; confirm Dev3 owns it.

## 10. Who does what

- Dev1: `Fishing/Shared/FishPool.lua` (the predicate, `ringHome`'s rule argument and the outward step, the GiveUp
  fallback), `Fishing/FishingConfig.lua` keys (section 2) as `patches/WSD_FishPool_shallowShore.patch.txt` and
  `patches/WSD_FishingConfig_homeDepth.patch.txt`; the analytic-bed seam if the suite does not already inject `bedAt`.
- Dev3: the W3 rows (section 5), rows Y16..Y21 and the mutant runs in the FishPool suite, PARITY_CHECKLIST.
- Dev2: no code; confirms the FishPoolView depth fade shows a fish at 0.35 m depth at full opacity (if the fade
  starts shallower than 0.35, tell Dev1 and the Coordinator; the number in section 3 would then need the fade's start).
- WordAgent: the config patch doc, README rows, the WS-R row that retires `HomeBubbleM`.
- Adrian: ruling 1's clip check.
