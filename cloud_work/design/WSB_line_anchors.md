Written by Cloud on 2026-10-08 without access to the project files;
every claim about LineKinks (the kink model, the W2.1 dock fixes, the release rule), LineShape, HookLineView, LureSim's retrieve and the line-kink oracle below is from the team's transcripts and is marked "confirm": FableDev (LineKinks, LureSim, the oracle) and Dev1 (FishingServer, the hook state) check them against the real files; Dev3 checks the net rows and assigns the ids. Batch 1 (the W2.1 fixes) is not promoted as this is written; nothing here touches `w21/`.

# WS-B: line anchor points (X67)

```
WS-B line_anchors (About Fishing F1; Cloud, 2026-10-08; rev 1)
Status: DRAFT, FOR RULING (rulings 1-5)
```

## Lead
An anchor is a tagged part; while Retrieving with the line near one, a press-and-hold latches the line to it as a pinned kink, and the reel then pulls the hook toward the anchor instead of the rod tip; release unlatches. The server validates the latch distance; the kink model is LineKinks' own.
When it is right the player hooks a piling with the line, winds the lure around it and out of the weed, lets go, and the line springs straight as it does today.

## Reference behaviour
Preview fact, UNVERIFIED until Adrian records V59 (the clip list's id; the kickoff brief called it V62-V63, the list wins).

| Claim | Source | Ref | Value |
|---|---|---|---|
| the line latches onto nearby anchor points | preview (UNVERIFIED) | RECORD IN DEMO: V59 | how: cast onto it, aim lock, or proximity |
| "work the line" to pull around obstacles | preview (UNVERIFIED) | V59 | whether the player or the hook moves; pull speed in frames per metre |
| release | preview (UNVERIFIED) | V59 | key up, or a second press |
| a fish on the line at the same time | preview (UNVERIFIED) | V59 | allowed or not |
| the line bends around dock edges and pilings today | team, W2.1 (confirm) | FableDev's LureSim/LineKinks batch 1 | kinks at contact points; released when the contact opens (confirm) |

## Our rule
- `Anchor` = a part with the CollectionService tag `LineAnchor` and attributes `AnchorId` (u16, unique per place) and `AnchorRadiusM` (0.6 default). Level design places them on pilings, rocks and buoys; the server trusts only tagged parts.
- Latch. In Retrieving, when the line (the polyline rod tip -> kinks -> hook that LineShape draws, confirm) passes within `AnchorLatchM` of an anchor, the client shows a marker on it (the AimMarker selector's look, Dev2) and a press-and-hold of the latch binding sends `LineLatch { anchorId, on = true }`. The server checks: state Retrieving; the anchor exists in this place; the server's own line passes within `AnchorLatchM + AnchorLatchSlackM` of the anchor part (segment-to-point distance on the server's hook position, never the client's); no latch already; no fish engaged (ruling 3). On ok it pins a kink at the anchor's contact point and answers `LineLatchResult { ok = true }`; on a refusal it answers the reason and the client drops its predicted kink on the next frame.
- Pinned kink. LineKinks today makes a kink where the line meets a dock edge or a piling and releases it when the line straightens past the contact (confirm; the W2.1 fixes changed the contact test and the release for pilings, confirm). A pinned kink is the same record with `pinned = true`: the release rule skips it; everything else (the polyline, the length accounting, the draw) treats it as any kink. One pinned kink per line in F3 (`AnchorMaxPinned` 1); chaining is release, then latch the next.
- Pull. While pinned, LureSim's retrieve pulls the hook toward the last kink (the anchor), not the rod tip: the retrieve direction is `anchorPos - hookPos`, the speed the normal retrieve speed (`AnchorPullMps` defaults to it; confirm LureSim's key). Line out = |tip - anchor| + |anchor - hook|; the reel shortens the second leg. Within `AnchorStopM` of the anchor the hook stops; the reel does nothing more until release.
- Release. Key up sends `LineLatch { on = false }`; the server unpins; the kink is then an ordinary contact kink and LineKinks releases it by its own rule when the line straightens (confirm), so the line behaves as after any piling today. Leaving Retrieving (a cancel, a Notice into Inspected, a snap) unpins on the server without a message.
- Not changed: the kink geometry, the contact test, the dock-grid behaviour with no anchor in reach (byte-identical traces), FishBrain, the fight, the cast.

## Config keys
| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `AnchorLatchM` | the LineKinks keys' block (confirm) | m | 0.6 | 0.3..1.5 | one hook length past a 0.3 m piling radius |
| `AnchorLatchSlackM` | same | m | 0.3 | 0..0.5 | one round trip of hook travel at the retrieve speed; the server forgives latency, not distance |
| `AnchorPullMps` | same | m/s | = the retrieve speed | 0.5..2 | the pull is the reel; no new speed to learn |
| `AnchorStopM` | same | m | 0.1 | 0.05..0.3 | the hook stops short of the part; no clipping |
| `AnchorMaxPinned` | same | count | 1 | 1..3 | F3: one; chains are ruling 4 |
| `AnchorHoldMinS` | same | s | 0.15 | 0.1..0.3 | a tap is not a latch; a flutter sends no pair |
| `AnchorPromptM` | `C.View` | m | 2.0 | 1..5 | the marker shows before the latch is possible |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none new; a new action `LineLatch`: Y in Retrieving only, dropped and counted elsewhere (Hooked per ruling 3) | `StateRules` row |
| Cues | `LineLatch` (C->S, proposed id 38: `anchorId` u16, `on` bool; 4 B) and `LineLatchResult` (S->C, proposed id 56: `ok` bool, `reason` u8: 0 ok, 1 wrong state, 2 no anchor, 3 too far, 4 already latched, 5 fish on; 3 B). 38 and 56 are the next free in WSN's ranges (55 is pencilled for `LoadoutSync`); Dev3 assigns the final numbers | `FishingNet` v3, `NetSchemaV3` |
| Guard rules | `LineLatch` 4 / s, burst 8; drop and count | `RequestGuard` |
| Wire size | +4 B / +3 B per latch; +0 B on every v2 message | `net_vectors_v3.py` gains both |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/LineKinks.lua` | `pinned` on the kink record; `pin(pos)`, `unpin()`; the release rule skips pinned (confirm the release site) | FableDev | Dev1 |
| `Fishing/Shared/LureSim.lua` | a `retrieveTarget` override while a pinned kink exists | FableDev | Dev1 |
| `Fishing/Server/FishingServer.lua` | the handler: validation, pin, unpin on state exit | Dev1 | Dev3 |
| `Fishing/Shared/StateRules.lua`, `Server/RequestGuard.lua`, `Shared/NetSchemaV3.lua`, `tools/net_vectors_v3.py` | the row, the rate, the two messages, the vectors | Dev3 | Dev1 |
| `Fishing/Client/HookLineView.lua`, `AimMarker.lua` (or a small `AnchorPrompt`) | the marker; the predicted kink; the drop on refusal | Dev2 | Dev1 |
| the line-kink oracle in `sim/` (confirm the name) | the anchor case | FableDev | Dev3 |
| the places | tagged parts on pilings, rocks, buoys | Dev2 (Studio) | FableDev |

## What it reuses and what is new
| From LineKinks (confirm each) | New |
|---|---|
| the kink record and the polyline it feeds LineShape | the `pinned` flag and `pin` / `unpin` |
| the contact test and the W2.1 piling fixes | the release rule's skip for a pinned kink |
| the length accounting along the kinked line | the retrieve target override in LureSim |
| HookLineView's draw of the kinked line | the server validation, the message pair, the tag and attributes, the marker |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/wsa/linekinks_test.luau` (confirm the name) rows A1-A6 | A1 a pinned kink stays while the line straightens past it; A2 with a pinned kink the hook's distance to the anchor strictly decreases at the retrieve speed within 5 % per step and stops at 0.1 m; A3 after `unpin` the next 600 steps equal the no-anchor trace started from that state; A4 the dock-grid traces (the 2 cm plank gaps and 6 pilings of the Blender dock) with no anchor are byte-identical to the W2.1 golden; A5 the validation geometry: a line 0.59 m from the anchor accepted, 0.91 m refused (0.6 + 0.3), state Hooked refused with reason 5; A6 the kink list with a pinned flag serializes and deserializes equal (LineKinks keeps a state table, confirm) | A1 run without `pinned` releases: FAIL; a mutant that pulls toward the tip fails A2; a mutant that keeps `pinned` after `unpin` fails A3 | FableDev names the count |
| the line-kink oracle `--parity` | the anchor case matches the Luau trace row by row; the existing cases unchanged | the Python with the pull toward the tip shows the first mismatch step | MATCH |
| `tests/netschemav3_test.luau` | the two messages encode and validate; `allowed("LineLatch", "Retrieving")` true, every other state false | vectors with `anchorId = 0` and `reason = 6` refused | `PASS 210` + Dev3's rows |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | dock sandbox: cast past a piling, retrieve, hold the latch key in reach | the marker; the line pinned to the piling; the hook winding toward it; release and the line straightens as today | frames in `evidence/WSB/` |
| 2 | the same with no anchor tagged | nothing: the line kinks and releases as in batch 1 | frames |
| 3 | hold the key 1.2 m from the piling | refused, reason 3; no kink | server output |
| 4 | a buoy, a rock | the same; the buoy's pin follows the part | frames |
| 5 | two players at one piling | each line pins alone; no cross talk | both clients |

## Risks
- Batch 1 is under review: the pinned flag lands only after the W2.1 LineKinks is in Place1; this note changes nothing in `w21/`.
- The line-kink oracle must gain the anchor case, or A1-A3 prove the Luau against itself (FableDev).
- The dock-grid tests are the regression fence: any byte change there without an anchor is a bug in the "inert when absent" rule.
- Latency: the client predicts the pin; a refusal must drop it in one frame or the player sees a snap-back.
- Exploit: a client naming a far anchor is refused by the server's own geometry; the slack is 0.3 m of latency, not a distance.

## Rulings needed
1. What the pull moves.
   - A: the hook (this note). Cost: LineKinks and LureSim only. Fidelity: unknown until V59; keeps the character out of the sim.
   - B: the character (X67's row as written): the server moves the player toward the anchor at a capped speed. Cost: a new state `Anchored`, server-side character motion, a camera beat. Fidelity: matches if V59 shows the player moving.
   - Recommendation: A for F3; re-rule after V59.
2. The binding: hold (release on key up) or toggle.
   - A: hold. Cost: none. Fidelity: "work the line" reads as a rhythm of hold and let go.
   - B: toggle. Cost: a second press to release; an extra state on the client. Fidelity: if V59 shows it.
   - Recommendation: A.
3. A latch while Hooked (a fish on).
   - A: refused (reason 5). Cost: none. Fidelity: V59 says.
   - B: allowed; the fight's strain reads the kinked length. Cost: TroutFight learns about kinks. Fidelity: same.
   - Recommendation: A for F3.
4. One pinned kink or chains. Recommendation: one; a chain is a second pin after V59 shows it.
5. Anchors by hand-placed tag, or every piling auto-tagged. Recommendation: by hand; a level decides where the trick works.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| X67 line anchor points | latch onto anchors, work the line, pull around obstacles (V59) | tagged `LineAnchor` parts; `LineLatch` in Retrieving; a pinned kink in LineKinks; the reel pulls the hook toward the anchor; release unpins; server-validated distance 0.6 + 0.3 m | planned | rows A1-A6; the oracle's anchor case; V59 |

## Open questions
- The latch binding on mouse and keyboard (Dev1; `Client/InputMap.lua`, the cloud's WS-I layer, gets a `latch` intent for touch and gamepad).
- Whether LineKinks' release rule is one site or several (FableDev, confirm).
- Whether a buoy's part should move at all in F3 (Dev2).
- The oracle's file name and whether it covers pilings today (FableDev).
- The kickoff brief cited V62-V63; the clip list gives V59 to anchors (Adrian, no action).
