Written by Cloud (session roblox-9d) on 2026-10-07 without access to the project files;
the module `cloud_work/src/Fishing/Shared/GameData.lua` and `tests/gamedata_test.luau` are real and pass here (PASS 45). Every claim about CastFlight, FishJudge, TroutFight, the coins field and the net layer is from the transcripts and must be checked by Dev1 (server and shared), Dev2 (shop and sell UI) and Dev3 (net, guard) against the real files.

# WS-E: the economy (P03, P04, P05, P06, X64)

```
WS-E economy (About Fishing F1; Cloud, 2026-10-07; rev 1)
Status: FOR RULING (rulings 1-3)
```

## Lead
Prices, lures and gear are data in `GameData`; the server sells from the TackleBox and credits `coins` in SaveData in one step; each gear multiplier is read in exactly one place.
When it is right four ordinary trout pay about 32 coins, a trophy pays 30 on its own, and a line upgrade visibly casts further.

## Reference behaviour
Preview facts, UNVERIFIED until Adrian records V49-V53 and V69.

| Claim | Source | Ref | Value |
|---|---|---|---|
| fish sell for money | preview (UNVERIFIED) | RECORD IN DEMO: V49 | money before and after; per fish or whole box |
| "four fish is at least 30 bucks" | preview (UNVERIFIED) | V49, V50 | the per-fish price and its basis (species, size) |
| price depends on size | preview (UNVERIFIED) | V50 | linear, stepped or flat in size |
| gear upgrades are for sale | preview (UNVERIFIED) | V51, V69 | the upgrade types, prices, prerequisites |
| a line upgrade adds cast distance | preview (UNVERIFIED) | V52 | the before/after distance ratio |
| lures attract different species | preview (UNVERIFIED) | V53 | lure -> species; when a swap is allowed |

## Our rule
- Price: `priceFor(speciesId, lengthM, weightKg) = max(1, round(pricePerKg * weightKg * sizeBonus))`. `sizeBonus` is 1.0 at the species median, linear to `BONUS_MAX` 1.5 at `max` and `BONUS_MIN` 0.6 at `min`, clamped. Calibration on the trout row (`pricePerKg` 11): median 0.40 m, 0.704 kg -> 7.74 -> 8 coins, four = 32; minimum 0.25 m, 0.172 kg, x0.6 -> 1 coin; maximum 0.55 m, 1.830 kg, x1.5 -> 30 coins. A median minnow rounds to 0 and sells for the floor, 1. `sellTotal(catches)` returns the total and one receipt line per catch, in order.
- Lures: six (`worm` 2, `spinner` 10, `fly` 12, `spoon` 18, `jig` 8, `boilie` 6 coins), each tagged with the species it is sold for; `validate` refuses a tag naming no species and a species lure id that no lure has.
- Gear, three tiers each, price never below the tier under it: rods `rod_basic` 0 / x1.0, `rod_carbon` 60 / x1.15, `rod_pro` 180 / x1.3 cast distance; lines `line_mono` 0 / 20 N / x1.0, `line_braid` 40 / 35 N / x1.1, `line_fluoro` 120 / 50 N / x1.2; hooks `hook_basic` 0 / x1.0, `hook_sharp` 30 / x1.2, `hook_wide` 90 / x1.4 hook-set window. `STARTER` = `rod_basic`, `line_mono`, `hook_basic`, `worm`: every starter item is free.
- Upgrade cost: `upgradeCost(kind, from, to) = max(0, to.price - from.price)`; a downgrade, the same item or an unknown id errors (a programmer error: the shop UI only offers the next tier).
- Where each multiplier is read, once: `castDistanceMul(loadout)` (rod x line) scales the CastFlight range on the server; `hookSetWindowMul(loadout)` scales FishJudge's Good window; `lineStrengthN(loadout)` is compared with the species' `fight.strengthN` in TroutFight's snap check (starter 20 N holds a trout at 12 N, not a pike at 35 N). The client never computes a price or a multiplier; it shows what the server sends.
- The sell flow is server-side with the TackleBox as the source of truth: `Sell(ids)` -> for each id `TackleBox.remove(box, id)` (an unknown id or a non-fish item is refused by id, nothing else changes) -> `priceFor` from the item's `data` `{ speciesId, lengthM, weightKg }` -> `profile:set("coins", coins + total)` -> the receipt to the client. Remove and credit happen in one server step on in-memory state, so the next save writes both or neither (P03).
- The `coins` field lives in the SaveData profile; the client readout is a replicated value; no client message adds money (P04). Buying: `Buy(id)` checks coins >= price and the previous tier owned, then debits and sets the loadout slot; `Equip(lureId)` sets `loadout.lure` to an owned lure.
- Departure from the F2 rows file: X64's placeholder was tier 2 = 1.25 x tier 1 as one `CastRangeM` per tier; the module uses multipliers (line x1.1, rod x1.15, both x1.265) until V52 is measured. The rows are rewritten to the module's names.

## Config keys
Module constants and data tables; nothing in `FishingConfig` yet.

| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `BONUS_MAX` | `GameData` | factor | 1.5 | 1.0-2.0 | a maximum trout pays 30, under 4 x the median |
| `BONUS_MIN` | `GameData` | factor | 0.6 | 0.3-1.0 | a minimum trout still pays 1 |
| `pricePerKg` | `SpeciesTable.ROWS[id]` | coins/kg | trout 11 | > 0 | four median trout = 32 coins |
| `castDistanceMul` | `GEAR.rods[id]`, `GEAR.lines[id]` | factor | 1.0 / 1.15 / 1.3; 1.0 / 1.1 / 1.2 | > 0 | placeholders until V52 |
| `strengthN` | `GEAR.lines[id]` | N | 20 / 35 / 50 | > 0 | the starter holds a trout (12 N), not a pike (35 N) |
| `hookSetWindowMul` | `GEAR.hooks[id]` | factor | 1.0 / 1.2 / 1.4 | > 0 | a wider Good window per tier (UNTUNED) |
| `StartCoins` (proposed, ruling 1) | `SaveData` defaults | coins | 0 | 0-50 | the starter kit is free |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none new; `Sell`, `Buy` and `Equip` are legal in Walking and Holding only (a swap mid-cast or mid-fight is refused, P06); the trader is a place, not a state | `StateRules` matrix rows `Sell`, `Buy`, `Equip` |
| Cues / messages | proposed `Sell(ids)`, `Buy(id)`, `Equip(lureId)` client -> server; a receipt and the coins value server -> client. All proposed, defined in `design/WSN_net_v3_messages.md` (a sibling is writing it) | `FishingNet` v3, `FishingNetClient` |
| Guard rules | no client verb can add coins (the codec has none); `Sell` at most 2 per s; an id not in the box is a counted rejection | `RequestGuard` |
| Wire size | `Sell`: 1 B count + 2 B per id; `Buy`, `Equip`: 1 B index into the sorted id list (estimate, Dev3 sizes it) | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/GameData.lua` | new, as in `cloud_work/src` | Dev1 | Dev3 |
| `Fishing/Server/FishingServer.lua` (or a `Shop` server module) | `Sell`, `Buy`, `Equip` handlers; coins in the profile; the loadout read at cast, press and fight | Dev1 | Dev3 |
| `Fishing/Shared/CastFlight.lua` | range x `castDistanceMul` | Dev1 | Dev3 |
| `Fishing/Shared/FishJudge.lua` | Good window x `hookSetWindowMul` | Dev1 | Dev3 |
| `Fishing/Shared/TroutFight.lua` | the snap compare reads `lineStrengthN` | Dev1 | Dev3 |
| `Fishing/Client/ShopView.lua`, the coins readout | new: stock list with `upgradeCost`, sell list with receipt | Dev2 | Dev1 |
| `tests/gamedata_test.luau` | adopt as is | Dev3 | Dev1 |
| `PARITY_CHECKLIST.md`, `README.md` | P03-P06, X64 in the module's names | Dev3, WordAgent | Coordinator |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/gamedata_test.luau` | `validate()` passes; prices at min / median / max (1, 8, 30) and the linear bonus between (1.25 at 0.475 m, 0.8 at 0.325 m); four median trout = 32 within 28-34; a trophy plus a minnow = 31; `castDistanceMul` 1.0 / 1.1 / 1.265; `lineStrengthN` 20 < pike 35; `upgradeCost` 60, 120, 180 and its errors | six mutated copies fail `validate` naming the field (a lure tag naming no species, a duplicate tier, a higher tier cheaper, a species lure with no entry, a starter id that does not exist, a zero multiplier); the live data is untouched after | `PASS 45` |
| sell suite (Dev3, P03) | `Sell(ids)` against a fake box and profile: remove and credit together; an unknown id removes nothing and credits nothing | a mutant that credits before `remove` returns must FAIL on a bad id | Dev3 names the count |
| guard suite (Dev3, P04) | the codec has no add-coins verb; `Sell` with an id another player holds is rejected | | Dev3 names the count |

## Studio tests
| # | Do | See | Evidence |
|---|---|---|---|
| 1 | sell one 0.40 m trout | coins +8; the item leaves the box; the receipt names Trout, 0.40 m, 0.70 kg, 8 | frames in `evidence/WSE/` |
| 2 | sell the same id again (replayed message) | refused, coins unchanged | server output |
| 3 | buy `line_braid` with 39 coins, then with 40 | refused, then bought; coins 0 | frames |
| 4 | three max casts from one spot before and after the line | distance ratio 1.10 +- 5 % | splash positions |
| 5 | try `Equip` during Flight and during a fight | refused; a guard count, no state change | guard counters |

## Rulings needed
1. Starting coins.
   - A: 0; the starter kit is free and the first sale funds the first lure (worm 2, jig 8). Cost: none. Fidelity: the reference starts from nothing as far as the previews show (V42, V49).
   - B: 10 coins so a second lure can be bought before the first sale. Cost: one default. Fidelity: departs unless V42 shows a starting purse.
   - Recommendation: A.
2. Price scale against the demo's readouts (V49-V51).
   - A: keep coins 1:1 with the demo's readout so "four fish >= 30" reads the same; after V50 retune `pricePerKg` per species to the measured per-fish price, keeping `BONUS_MIN` / `BONUS_MAX`. Cost: one number per row. Fidelity: matches the readout.
   - B: GameOne's own scale (x10, whole hundreds) and rescale every shop price with it. Cost: every price. Fidelity: departs on purpose; the feel of "four fish buys a line" must be re-checked.
   - Recommendation: A.
3. Selling per fish or the whole box.
   - A: per item id (`Sell(ids)`, one or many), so the player keeps a trophy. Cost: a sell list UI. Fidelity: unknown until V49.
   - B: one action sells every fish item. Cost: smaller UI; no choice. Fidelity: only if V49 shows a sell-all.
   - Recommendation: A, because it covers B (send every id).

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| P03 selling fish for money | "four fish is at least 30 bucks" (V49, V50) | `priceFor` = pricePerKg x kg x size bonus; four median trout = 32; sell = remove + credit on the server | staged (module), planned (flow) | `tests/gamedata_test.luau` PASS 45 |
| P04 money readout | a total at the trader (V49) | `coins` in the SaveData profile; a replicated value; no client verb adds money | planned | guard suite |
| P05 gear shop and upgrades | upgrades for sale (V51, V69) | `GEAR` tiers 1-3 per kind; `upgradeCost`; one tier at a time | staged (data), planned (Buy) | the `upgradeCost` checks |
| P06 lures as items | a swap (V53) | `LURES`; `Equip(lureId)` in Walking and Holding | planned | StateRules row |
| X64 line upgrade adds cast distance | before/after ratio (V52) | `castDistanceMul` rod x line (1.1 for `line_braid`) into CastFlight | staged (data), planned (CastFlight) | Studio test 4 |

## Open questions
- The real per-fish prices and the size relation (Adrian, V49, V50; then Dev1 retunes `pricePerKg`).
- The line-upgrade distance ratio (Adrian, V52; then Dev1 sets `castDistanceMul`).
- Whether rods and hooks exist as upgrades in the reference or only the line (Adrian, V51, V69); if not, two gear kinds become F3.
- Whether the Good window should widen by hook tier at all, or the snap threshold instead (Dev1 with FishJudge's owner).
- Where the trader stands and whether selling needs a place or works from the box anywhere (Coordinator, after V49).
