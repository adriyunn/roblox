# DRAFT doc patch: `FishJudge.lua` header after the J-2 ruling

Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files. From Dev1's
re-freeze workflow (2026-10-04): "FishJudge is unchanged, as instructed, but its header doc is now
incomplete. FishJudge.lua:12 still describes Late as eject only, and :19 explains engagedAt only for
Early and Good; a Late press now uses it too. This is a doc nit for the next FishJudge delta."
Dev1 owns the file. This is comment text only; no behaviour changes.

## Facts the header must now state
- The press verdict is Early, Good or Late. Late is judged at `tS + 0.55 + LB` (the deadline) or by a
  press after that window (`detail.byPress`).
- J-2 (Coordinator ruling 11:04, 2026-10-04): a **Late press** ejects the pressed fish *and* spooks every
  other fish in `engagedAt` for that angler (`FishBrain.spook(fish, cfg, t, REASON_EARLY, rng, nil)`),
  sending one Spook cue (`a = Early reason, b = 255`). The **deadline Late** (no press) spooks no one.
  A stale press (after the eject) changes nothing.
- `engagedAt` is therefore read for Early, Good **and** Late-by-press; it is the list of fish ids engaged
  with this angler at the time of the press.

## Proposed replacement lines (Dev1 fits them to the real header)

```lua
-- @@@ OLD (line 12, shape only)
-- Late: the press came after the window; the fish is ejected.
-- @@@ NEW
-- Late: the press came after the window (tS + 0.55 + LB), or the deadline passed with no press.
--   A Late *press* ejects the pressed fish and spooks every other fish engaged with this angler
--   (J-2 ruling, 2026-10-04: FishPool runs FishBrain.spook with REASON_EARLY for each id in engagedAt
--   other than detail.fishId, and sends one Spook cue a = Early, b = 255). The *deadline* Late ejects
--   only; it spooks no one. A stale press after the eject changes nothing.
```

```lua
-- @@@ OLD (line 19, shape only)
-- engagedAt: the fish engaged with this angler when the press lands (used by Early and Good).
-- @@@ NEW
-- engagedAt: the fish engaged with this angler when the press lands. Early and Good use it to pick
--   the pressed fish; a Late press uses it to find the other fish to spook (J-2).
```

## Where else the same words appear
- `w3/WSD_impl_plan_Dev1_ALIENWARE.md` plan item c3 and §2.3 ("Late: eject") are overridden for presses
  by the ruling; WordAgent should add a one-line "superseded by J-2 for presses" note rather than rewrite.
- `WSD_fish_detail.md:120-123` already matches the new behaviour (per Dev1). No change.
- `FishPool.lua:966-969` (the verdict header) was already updated in the re-freeze. No change.

## Checklist for Dev1
- [ ] Fold into the next FishJudge delta (not its own patch; it is comments only).
- [ ] Re-run `fishpool_test.luau` (294 checks) — unchanged, since nothing executable moves.
