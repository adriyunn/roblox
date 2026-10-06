# DRAFT patch: clamp `lineM` in the W2.1 InputController (Dev1's open item #4)

Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files. Every claim
below comes from the team transcripts (Dev1, 17:47 UTC on 2026-10-04: "Still open and mine: #4, the
unclamped lineM (W2.1 IC). Until then the out-of-range click pitch holds at 2.07"). Dev1 owns the file
and confirms the names and lines before any of this becomes a real `.patch.txt`.

## What is wrong
The W2.1 `InputController` (IC 44,261 B, the copy with `aimTurn`) computes a line length `lineM` for the
aim and the AimMarker click sound without clamping it to the cast's reachable range. When the aim lands
out of range, the value runs past the maximum and the click pitch that is derived from it saturates at
2.07 (the ratio the AimMarker rev 3b `distant_click` maps from distance to pitch). Symptom: every
out-of-range click sounds the same, and any consumer that scales by `lineM` (the marker's size, the
cast's predicted flight) gets a length the cast cannot deliver.

## The fix (two lines)
Clamp at the one place `lineM` is produced, so every consumer sees the same bounded value.

```lua
-- @@@ OLD (shape only; Dev1 matches the real text)
local lineM = (aimPoint - rodTip).Magnitude
-- @@@ NEW
local lineM = math.clamp((aimPoint - rodTip).Magnitude, C.AF.Cast.MinLineM, C.AF.Cast.MaxLineM)
```

- `C.AF.Cast.MinLineM` / `MaxLineM`: use the keys the cast already has for its reachable range (the
  W2 cast loop has a minimum pickup distance and a maximum cast distance; Dev1 knows the names — they
  may be `C.AF.Cast.MinM` / `MaxM` or live in `CastFlight`). If no such keys exist, add
  `MaxLineM = <the longest cast the flight model can deliver at full power>` to the `C.AF.Cast`
  block with a comment line in the team's style, and `MinLineM = 0`.
- The AimMarker then needs no change: its pitch map is a function of `lineM` and now receives a bounded
  input, so the pitch ramps up to the maximum and stops instead of holding a saturated value. If the
  marker clamps on its own as well (rev 3b "guards against the hook being absent or erroring"), both
  clamps agree and the second is harmless.

## Why clamp here and not in the marker
The marker is a client view. The length also feeds the predicted flight the server validates
(`CastFlight`, `HookStep`: "the server's flight loop and the owner's prediction give the SAME hook, tick
for tick"). An unclamped client length that the server clamps later would make the prediction disagree
with the server at the edge of range, which is exactly the class of bug `hookstep_test.luau` guards.
Clamping at the source keeps the owner's prediction and the server's flight identical.

## Tests to add (offline, `tests/wsa/`)
1. `ic_linem_test.luau`: feed an aim point 2 x `MaxLineM` away; assert `lineM == MaxLineM`; feed a point
   inside; assert unchanged; feed a point at 0; assert `MinLineM`.
2. In the AimMarker runner (Dev2's 82/82 suite): the pitch at an out-of-range aim equals the pitch at
   exactly `MaxLineM` (no plateau at 2.07 beyond it unless 2.07 is the pitch *at* `MaxLineM`).
3. `hookstep_test.luau` already compares prediction and server; add one case at `MaxLineM + 1 m`.

## Checklist for Dev1
- [ ] Confirm where `lineM` is produced (one site) and that no consumer re-derives it.
- [ ] Confirm the key names for the reachable range; add `MaxLineM` only if none exist.
- [ ] Write the real `W21_InputController_lineMClamp.patch.txt` against the frozen IC bytes.
- [ ] Run `hookstep_test`, the AimMarker runner, `luau-compile --null` at -O0/-O1/-O2.
- [ ] Note in `PARITY_CHECKLIST.md`: the reference clamps cast distance by rod power; we clamp the aim
      length the same way (no behaviour difference once the clamp is in).
