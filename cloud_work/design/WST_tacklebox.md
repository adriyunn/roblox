Written by Cloud (session roblox-9d) on 2026-10-07 without access to the project files;
the module `cloud_work/src/Fishing/Shared/TackleBox.lua` and `tests/tacklebox_test.luau` are real and pass here (PASS 70). Every claim about FishingServer, FishingNet, StateRules and the catch scene is from the transcripts and must be checked by Dev1 (server wiring), Dev2 (box UI) and Dev3 (net, guard, StateRules rows) against the real files.

# WS-T: the tackle box (P01, P02)

```
WS-T tacklebox (About Fishing F1; Cloud, 2026-10-07; rev 1)
Status: FOR RULING (rulings 1-5)
```

## Lead
The box is a server-owned 8 x 6 grid of polyomino items; the client only asks to move, drop or sell what it already holds, by id.
When it is right the player feels the reference's puzzle: a big fish needs room, and making room is a choice the player makes, never something the game does for them.

## Reference behaviour
Preview facts (demo builds shown March-September 2026). UNVERIFIED until Adrian records V46-V48 (`clips/DEMO_CLIP_LIST.md`). R4 wins over this table when they disagree.

| Claim | Source | Ref | Value |
|---|---|---|---|
| the box is a Tetris-style grid | preview (UNVERIFIED) | RECORD IN DEMO: V46 | grid columns x rows: count the cells |
| each fish takes a different number of squares | preview (UNVERIFIED) | V46 | cells per fish per species and size |
| a fish can be turned to fit ("different angles") | preview (UNVERIFIED) | V47 | rotation step: 90 degrees or finer |
| you must make room when it does not fit | preview (UNVERIFIED) | V47, V48 | the actions offered: move, discard, other |
| what happens on a catch with a full box | preview (UNVERIFIED) | V48 | catch scene plays or not; fish lost, held or auto-discarded |

## Our rule
- One `TackleBox.Box` per player on the server, 8 x 6 = 48 cells (`DEFAULT_W`, `DEFAULT_H`), 1-based, origin top-left. A save asking for more than `MAX_DIM` 32 on a side or a shape with more than `MAX_CELLS` 64 cells is refused.
- Items are `{ kind = fish | lure | gear, key, shape, data }`. A fish's shape comes from `SpeciesTable.sizeClass(id, lengthM)` (trout: `line1` to 0.32 m, `line2` to 0.46 m, `line3` to 0.55 m); `TackleBox.SHAPES` has 10 named shapes (`line1`-`line4`, `L3`, `L4`, `rect2x2`, `rect2x3`, `T4`, `S4`), every one valid at rotations 0-3 (90 degrees clockwise per step; `shapeCells` normalises so the bounding box's top-left is the origin).
- The server owns the box. On a catch (CatchScene entry) FishingServer calls `autoPlace(box, item)` (first fit: rotations 0-3, then rows, then columns). On `nil, "no room"` the player enters MakeRoom (P02): the box opens with the new fish held; the client proposes ids to drop; the server checks each id exists (`box.placed[id]`; `canFitAfterRemoving` errors on an unknown id, so the check comes first), then `canFitAfterRemoving(box, shape, ids)`; on true it removes those ids and places the fish. A dropped fish is gone: not sold, not returned (ruling 4).
- The client sends `TackleMove(id, rot, x, y)`; the server answers with `TackleBox.move` and sends `TackleBox.items(box)` to the owner only. A refused move returns a reason (`no item`, `bad rotation`, `bad position`, `out of bounds`, `overlap`) and changes nothing. Client-facing operations never error; only a malformed item, shape or save does (a programmer error or a tampered save).
- Anti-dupe: ids come from `box.nextId` on the server at `place` time and are never reused after a `remove`; the client never names a new id, it only refers to ids it was sent. Sell and drop remove by id; a second message for the same id gets `no item`.
- Save form: `serialize(box)` is `{ w, h, nextId, items = { { id, kind, key, shape, rot, x, y, data } } }`, items by id. `deserialize` rebuilds the grid and re-checks every item (bad id, duplicate id, bad kind or key, bad rotation, bad data, bad shape, out of bounds, overlap, grid over 32), erroring with the item id; `nextId` becomes `max(stored, maxId + 1)`. SaveData calls it in `pcall`; a failing box is a corrupt profile (WSS_savedata.md ruling 2), never silently emptied.
- Multiplayer: one box per player, never shared; another player's box is never sent to you. Observers see the held fish (MP_stress_test.md Z11), not the box.

## Config keys
Today these are module constants; the first three move to a `C.AF.Box` block only if ruling 2 asks for a configurable grid.

| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `DEFAULT_W` | `TackleBox` | cells | 8 | 1-32 | placeholder until V46 is counted |
| `DEFAULT_H` | `TackleBox` | cells | 6 | 1-32 | placeholder until V46 is counted |
| `MAX_DIM` | `TackleBox` | cells | 32 | 8-64 | bounds every scan; a save asking for more is refused |
| `MAX_CELLS` | `TackleBox` | cells | 64 | 6-64 | the largest shape a save may carry (`rect2x3` is 6) |
| `BoxFullReleaseS` (proposed, only under ruling 1A) | `C.AF.Box` | s | 20 | 10-60 | time to read the box before a held fish swims off |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | adds `MakeRoom` (CatchScene -> MakeRoom -> Holding or Walking); the box UI opens in Walking and Holding only, never Aiming through CatchScene | `StateRules` matrix rows `BoxOpen`, `TackleMove`, `TackleDrop` |
| Cues / messages | proposed `TackleMove(id, rot, x, y)` client -> server; proposed `TackleDrop(ids)` client -> server (MakeRoom only); the owner-only items list server -> client. All proposed, defined in `design/WSN_net_v3_messages.md` (a sibling is writing it) | `FishingNet` v3, `FishingNetClient` |
| Guard rules | `TackleMove` at most 10 per s per player; an id the player does not hold is a counted rejection, not an error | `RequestGuard` |
| Wire size | about +5 B per `TackleMove` (id u16, rot u8, x u8, y u8); the items list at most 48 items (estimate, Dev3 sizes it) | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/TackleBox.lua` | new, as in `cloud_work/src` | Dev1 | Dev3 |
| `Fishing/Server/FishingServer.lua` | one box per player; `autoPlace` on a catch; MakeRoom; `TackleMove` and `TackleDrop` handlers | Dev1 | Dev3 |
| `Fishing/Shared/StateRules.lua` | `MakeRoom` state; `BoxOpen`, `TackleMove`, `TackleDrop` actions | Dev3 | Dev1 |
| `FishingNet`, `FishingNetClient` | the three proposed messages (per WSN_net_v3_messages.md) | Dev3 | Dev1 |
| `Fishing/Client/TackleBoxView.lua` | new: grid, drag, rotate key, MakeRoom prompt | Dev2 | Dev1 |
| `Fishing/Server/SaveData.lua` wiring | `box` field: `serialize` on save, `deserialize` in `pcall` on load | Dev1 | Dev3 |
| `tests/tacklebox_test.luau` | adopt as is | Dev3 | Dev1 |
| `PARITY_CHECKLIST.md`, `README.md` | rows P01, P02; the module table | Dev3, WordAgent | Coordinator |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/tacklebox_test.luau` | all four L4 rotations written out; bounds and overlap; remove frees cells; move over own cells; first-fit order; 48 `line1` items fill 8 x 6 and the 49th is `no room`; `canFitAfterRemoving`; a JSON round trip equal cell for cell; a 500-operation seeded fuzz (seed 20261006) never breaks `check` | `deserialize` refuses a tampered save naming the item (overlap, out of bounds, duplicate id, unknown kind, grid 1000); `check()` itself reports a hand-corrupted grid cell (`stray id 999`) | `PASS 70` |
| `tests/rules_test.luau` (Dev3's, to extend) | `TackleMove` legal in Walking, Holding, MakeRoom; illegal in Aiming through CatchScene | a mutant row allowing it in Hooked must FAIL | Dev3 names the count |
| guard suite (Dev3's, to extend) | a `TackleMove` naming an id the player does not hold is rejected and counted; 11 moves in 1 s throttle the 11th | | Dev3 names the count |

## Studio tests
Sandbox copy, never Place1.

| # | Do | See | Evidence |
|---|---|---|---|
| 1 | catch a trout with an empty box | the fish lands at (1,1) rot 0 without a prompt; the box shows it | frames in `evidence/WST/` |
| 2 | open the box while Walking and while Holding; try during a fight | opens in the first two; nothing happens mid-fight, no message sent | server guard counters |
| 3 | drag a fish onto another; rotate it off the bottom edge | both refused, the box unchanged, the reason shown | frames |
| 4 | fill the box (24 medium trout, `line2`), catch one more | MakeRoom: the box opens, the fish is held, no fish lost | frames + the server's items list |
| 5 | in MakeRoom drop two fish that free a fitting space | the new fish is placed; the dropped two are gone from items and the save | the saved `items` |
| 6 | leave and rejoin | the same box, cell for cell | `deserialize(serialize())` equality |

## Rulings needed
1. A full box at the catch and the player does nothing in MakeRoom.
   - A: release after `BoxFullReleaseS` = 20 s; the fish swims off, the catch is already in the CatchLog. Cost: one timer and one cue; a fish lost while the player reads the UI. Fidelity: unknown until V48.
   - B: no timer; MakeRoom waits until the player drops something or lets the new fish go (a "let it go" action). Cost: one more UI action; a player can idle in MakeRoom. Fidelity: matches "you must make room"; nothing is lost silently (P02).
   - Recommendation: B, because a timer decides for the player and the reference makes them decide.
2. Grid size when V46 is counted.
   - A: change `DEFAULT_W` and `DEFAULT_H` once; old saves carry their own `w`, `h`, so they keep their grid until a migration re-packs them by `autoPlace`. Cost: a one-line change plus one migration. Fidelity: the measured grid.
   - B: keep 8 x 6 as GameOne's own size whatever V46 shows. Cost: none. Fidelity: departs if the reference differs.
   - Recommendation: A, because the save form already carries the grid.
3. Rotation step.
   - A: 90-degree steps only (`rot` 0-3, as built). Cost: none. Fidelity: expected; V47 confirms.
   - B: finer steps. Cost: not a grid any more; a rewrite. Fidelity: only if V47 shows it.
   - Recommendation: A.
4. What a dropped fish is worth.
   - A: nothing; it is gone (a release at the shore). Cost: none. Fidelity: unknown until V47.
   - B: it sells at a discount from MakeRoom. Cost: a second price path and a UI. Fidelity: only if V47 shows a payout.
   - Recommendation: A, because making room should cost something.
5. Do lures and gear take cells in F2.
   - A: fish only in the box for F2; gear lives in `GameData.Loadout`; the `lure` and `gear` kinds stay in the module for later. Cost: none. Fidelity: open (V46 shows what sits in the grid).
   - B: lures and gear occupy cells now. Cost: shop and equip flows must place items; more full boxes. Fidelity: only if V46 shows gear in the grid.
   - Recommendation: A for F2.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| P01 tackle box grid inventory | Tetris-style grid; cells per fish; rotation (V46, V47) | `TackleBox` 8 x 6, polyomino shapes by size class, `rot` 0-3, server-owned, `TackleMove` by id | staged (module), planned (wiring) | `tests/tacklebox_test.luau` PASS 70 |
| P02 catch with no room | "you must make room" (V48) | MakeRoom after CatchScene; `canFitAfterRemoving` drives the drop choice; ruling 1 | planned | Studio test 4, 5 |
| P20 per-player save | single save in the reference | `serialize` / `deserialize` re-validated inside SaveData | staged | the round-trip and tampered-save checks |

## Open questions
- Grid columns x rows and cells per species in the reference (Adrian, V46, before Dev1 wires the catch).
- Whether the reference lets a fish be discarded and what it costs (Adrian, V47).
- Whether the owner-only items list is a message or a replicated value (Dev3, in WSN_net_v3_messages.md).
- A box that fails `deserialize` inside an otherwise good profile: read-only session or empty box in memory (Dev1 with WSS_savedata.md ruling 2).
- The MakeRoom camera and pose: the fish is held, the box is open; who owns that beat (Dev2, after the Caught camera is in).
