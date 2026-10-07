Written by Cloud (session roblox-9d) on 2026-10-07 without access to the project files;
every claim about FishingNet v2, RequestGuard, StateRules and the W2 LEGACY gate below comes from the team's transcripts and must be checked by Dev3 (owner of the wire: codec, vectors, guard, matrix) and Dev1 (owner of the server handlers) against the real files.

# WS-N: net v3 messages (tackle box, shop, options, syncs, profile)

Status: DRAFT, FOR RULING (section 10). Net and state impact: 13 new message ids (32..63 reserved for v3), 6 new
StateRules actions, 6 new RequestGuard rows, no change to any v2 id, field, enum or sentinel.

**Decision.** The next features (TackleBox, GameData shop, CatchLog, WorldClock, SaveData, the WS-H options) get
their wire now, as a declarative schema, so Dev3's gate is ready before Dev1 writes a handler. Thirteen messages, ids
32..63 only (C→S 32..47, S→C 48..63), each with typed fields and ranges, the sender states, one validation rule, a
RequestGuard rate and a size. Three things are code, not prose: `src/Fishing/Shared/NetSchemaV3.lua` (the schema,
`validate`, `allowed`, `check`, and a REFERENCE encoding), `tools/net_vectors_v3.py` (an independent Python encoder
in Dev3's `net_sim_f1.py` style that writes `tests/fixtures/net_vectors_v3.json` and the same vectors as a Luau
module) and `tests/netschemav3_test.luau` (every vector replayed through the module). The reference encoding is not
the team's compact codec: it is the one unambiguous byte form two implementations agree on, so that when Dev3 maps
each field to the real codec the field tables, ranges and reason strings are already pinned by 92 vectors.

## 1. What exists (from the transcripts)

- `FishingNet` v2, one compact codec for every cue and request (Notice, Nip, Swallow, BaitGone, Spook(reason, fishId;
  255 = all engaged), Jump, Snap; Press, hold on/off...), with `FishingNetClient` on the other end.
- `RequestGuard`: a rate limit per message (per second, with a burst), rejections counted per client; the ceiling the
  PERF note quotes is 30 cues/s per angler.
- `StateRules`: the state x action matrix; the server drops a request whose action is not legal in the player's state.
  States: Walking, Aiming, Flight, Presenting, Retrieving, Inspected, HookWindow, Hooked, CatchScene, Holding.
- Dev3's wire gate: `net_sim_f1.py`, an independent Python byte simulator, writes `net_vectors.json`;
  `net_vectors_test.luau` checks the Luau codec against those bytes (via `vectors_to_luau.py` →
  `net_vectors_data.luau`, since the Luau CLI reads no files). The W2 LEGACY gate pins v2's sentinel values.
- The cloud modules the new messages carry: `TackleBox` (`serialize(box).items`, `move(box, id, rot, x, y)`,
  `remove`), `GameData` (`sellTotal`, `upgradeCost`, LURES/GEAR ids), `CatchLog` (`serialize(log)`), `WorldClock`
  (`snapshot(clock)`), `SaveData.load` (`profile.readOnly`, `reason`).

## 2. The v2 → v3 rule

| Rule | Detail |
|---|---|
| v3 only ADDS ids | Ids 32..63 are v3. No v2 id changes, no v2 field, enum or sentinel changes (Spook's 255 stays 255). `net_vectors.json` stays byte-identical and the W2 LEGACY gate keeps running unchanged next to the v3 chain |
| Id ranges | C→S requests 32..47, S→C replies and replicates 48..63. `NetSchemaV3.check()` enforces the split. Used now: 32..37 and 48..54; 38..47 and 55..63 are reserved for later v3 messages (55 is pencilled for a `LoadoutSync`, section 12) |
| No version byte | The id byte is the version: a v2 decoder sees an id >= 32 as unknown. A version byte would cost one byte on every v2 cue AND change every v2 vector, which is exactly what the LEGACY gate forbids. If the real v2 decoder errors on an unknown id instead of dropping it, the one v2-side change is a guard that drops and counts it (Dev3 confirms which it does today) |
| Two vector chains | `net_sim_f1.py → net_vectors.json → net_vectors_test.luau` (v2, untouched) and `net_vectors_v3.py → net_vectors_v3.json + net_vectors_v3_data.luau → netschemav3_test.luau` (v3). Both run in the gate; neither reads the other's file |
| Mapping to the real codec | Dev3 maps each field of section 6 to the compact codec and extends `net_sim_f1.py` from the same tables. The reference bytes (section 4) are for the schema's own gate, not the wire. When the real codec's vectors exist, `netschemav3_test.luau` keeps running as the schema gate and the real vectors get their own suite |

## 3. The messages

Sizes are the reference encoding's bytes from the generated vectors (min / typical / max, the id byte included) and
a compact estimate for Dev3's codec (species, shapes and gear as u8 indices, metres as u16 mm).

| Message | Id | Dir | Sender states | Rate (per s / burst) | Reply | Reference bytes | Compact est. |
|---|---|---|---|---|---|---|---|
| `TackleMove` | 32 | C→S | Walking, Holding | 10 / 20 | `TackleMoveResult` + `TackleSync` | 6 | 6 |
| `TackleDrop` | 33 | C→S | Walking, Holding | 2 / 4 | `TackleMoveResult` + `TackleSync` | 3 | 3 |
| `Sell` | 34 | C→S | Walking, Holding | 1 / 2 | `SellResult` + `TackleSync` | 2 / 8 / 98 | 2 + 2n |
| `BuyGear` | 35 | C→S | Walking, Holding | 1 / 2 | `BuyResult` (op 0) | 3 / 13 / 27 | 3 (id as u8) |
| `Equip` | 36 | C→S | Walking, Holding | 2 / 4 | `BuyResult` (op 1) | 3 / 10 / 27 | 3 |
| `SetOption` | 37 | C→S | all but Flight, Hooked | 5 / 10 | none (attributes echo) | 6 | 6 |
| `TackleMoveResult` | 48 | S→C reply | — | 10 / 20 | — | 3 | 3 |
| `TackleSync` | 49 | S→C replicate | — | 10 / 20 | — | 8 / 393 / 4160 | 5 + 8..12 per item (≈ 490 full) |
| `SellResult` | 50 | S→C reply | — | 1 / 2 | — | 13 / 297 / 3421 | 10 + 7 per line (≈ 346 full) |
| `BuyResult` | 51 | S→C reply | — | 2 / 4 | — | 8 | 8 |
| `CatchLogSync` | 52 | S→C replicate | — | 1 / 2 | — | 41 / 368 / 1664 | 6 + ≈ 30 + 3 zones per species |
| `WorldSync` | 53 | S→C replicate | — | 0.2 / 2 | — | 21 | 12 |
| `ProfileReady` | 54 | S→C cue | — | 1 / 1 | — | 3 | 3 |

S→C rates are the server's own per-client send ceiling (the fan-out cost at 8 anglers), not RequestGuard rows.

## 4. The reference encoding (what the vectors pin)

One byte form, little-endian, no padding, no version byte:

| Type | Bytes | Note |
|---|---|---|
| message | `u8 id` then the fields in schema order | nothing else: no length, no checksum |
| `u8`, `u16`, `i16`, `u32` | 1, 2, 2, 4 | `string.pack("<B" / "<I2" / "<i2" / "<I4")`; Python `struct` `<B <H <h <I` |
| `f32` | 4 | `string.pack("<f")`; Python `struct.pack("<f")`. Round-to-nearest on both sides, so bytes agree; a decoded value is within 1e-6 of the payload for the ranges here |
| `bool` | 1 | 0 or 1; a decoder refuses 2..255 |
| `str` | 1 + n | u8 length, then printable-ASCII bytes (0x20..0x7E); no terminator |
| `ids` | 1 + 2n | u8 count, then u16 items |
| `table` | tagged | a free-form JSON-safe tree: tag 1 false, 2 true, 3 i32 (any integral number in i32 range), 4 f64, 5 str (u16 length + bytes), 6 array (u16 count + values), 7 map (u16 count, then per entry u16 key length + key + value, keys in byte order). An empty table is an empty array (like `HttpService:JSONEncode`). Depth at most 8 |

Why a tagged form for `table` fields and not a fixed layout: `TackleSync.items`, `SellResult.lines` and
`CatchLogSync.log` carry the modules' serialize forms, which will grow (species data, a second zone key) before the
real codec is written. Pinning their bytes field by field now would pin the wrong thing; pinning the serialize form
through one generic rule pins the contract (JSON-safe, ASCII keys, sorted) and leaves the compact layout to Dev3.

## 5. Validation rules and reason strings

`NetSchemaV3.validate(name, payload)` returns `ok, reason`. The reasons are a fixed grammar, because the Python
vectors carry the expected string and the Luau module must produce the same one:

| Reason | When |
|---|---|
| `unknown message` | the name is not in the schema |
| `payload must be a table` | the payload is not a table |
| `missing <field>` | a schema field is absent (checked first, in schema order) |
| `<field>: expected <type>` | wrong type: integer types need an integral finite number, f32 a finite number, bool a boolean, str a string, ids an array, table a table |
| `<field>: out of range` | outside the field's min..max (defaults: the type's natural range; f32 ± 3.4028e38; ids items 1..65535) |
| `<field>: too long` | str over maxLen bytes, ids over maxLen items, table over maxLen nodes (every value and every container counts one) |
| `<field>: not ASCII` | a str with a byte outside 0x20..0x7E (control characters and UTF-8 included) |
| `<field>: bad id` | an ids item that is not an integer in range |
| `<field>: bad table` | a table that is not JSON-safe printable ASCII: mixed array/string keys, a hole, a non-finite number, a non-ASCII or over-255-byte string or key, a function, deeper than 8 levels |
| `unexpected <field>` | a key the schema does not list (checked last; the first in sorted order is named) |

Order: missing fields, then each field's type and range in schema order, then extra keys. The server validates every
C→S payload before StateRules and RequestGuard see it (a malformed payload is dropped and counted like a rate
rejection); a debug build validates S→C payloads before sending.

## 6. Each message

Enum columns are u8 values; the schema checks the range, the handler maps the value.

### 6.1 `TackleMove` (32, C→S) → `TackleMoveResult` (48) + `TackleSync` (49)

| Field | Type | Range | Meaning |
|---|---|---|---|
| `id` | u16 | 1..65535 | the placed item's id (`TackleBox.Placed.id`) |
| `rot` | u8 | 0..3 | quarter turns clockwise |
| `x`, `y` | u8 | 1..32 | origin cell, 1-based (`TackleBox.MAX_DIM` = 32) |

Server rule: `TackleBox.move(box, id, rot, x, y)`; on ok, replicate `TackleSync`; always answer `TackleMoveResult`.
RequestGuard 10/s, burst 20 (one message per drop in the box UI, never per pixel). Reply reasons: 0 ok, 1 no item,
2 bad rotation, 3 bad position, 4 out of bounds, 5 overlap (the `TackleBox.move` strings), 6 wrong state, 7 no room
(reserved for `TackleDrop` in the make-room flow). 6 bytes.

`TackleMoveResult`: `ok` bool, `reason` u8 0..7. 3 bytes. Sent to the requester only.

`TackleSync`: `w` u8 1..32, `h` u8 1..32, `nextId` u16 >= 1, `items` table (<= 4096 nodes) = `TackleBox.serialize(box).items`,
each `{ id, kind, key, shape, rot, x, y, data? }`. Sent to the owner on join (after `ProfileReady`) and after every
accepted `TackleMove`, `TackleDrop`, `Sell` and catch placement. Why a full sync beats deltas at this size: the whole
box is at most 48 items, about 490 bytes compact (section 3) and 4 KB in the reference form; a change happens a few
times a minute at most; one full image makes the client stateless (no ordering, no lost-delta recovery, no "which
version is this delta against"), a late joiner and a reconnect need no second path, and the handler is one function.
Deltas would save perhaps 400 bytes per move at the cost of a second code path and a resync message anyway.

### 6.2 `TackleDrop` (33, C→S) → `TackleMoveResult` + `TackleSync`

| Field | Type | Range | Meaning |
|---|---|---|---|
| `id` | u16 | 1..65535 | the item to discard |

The make-room flow (PARITY P02): after CatchScene, when `TackleBox.autoPlace` returns "no room", the player holds the
fish and the box opens; `TackleDrop` discards an item (`TackleBox.remove`), the server retries `autoPlace` for the
held fish and, when it fits, places it and sends `TackleSync`; `TackleMoveResult` carries 7 (no room) while the held
fish still does not fit, 0 when it was placed. A fish is never lost silently: dropping is explicit, one id per message.
Server rule: `TackleBox.remove(box, id)`; a dropped fish is gone, a dropped lure or gear is gone (no refund; ruling 4).
RequestGuard 2/s, burst 4. 3 bytes.

### 6.3 `Sell` (34, C→S) → `SellResult` (50) + `TackleSync`

| Field | Type | Range | Meaning |
|---|---|---|---|
| `ids` | ids | 0..48 items, each 1..65535 | box item ids to sell, all of kind `fish` |

Server rule: every id must exist in the box and be a fish (else reason 2 or 3 and nothing is sold); the catches'
`data` ({ speciesId, lengthM, weightKg }) go to `GameData.sellTotal`, `total` is added to the profile's coins
(`profile:set("coins", ...)`), the items are removed, `TackleSync` follows. Empty `ids` → reason 1. A read-only profile
(section 6.8) → reason 4, nothing sold. RequestGuard 1/s, burst 2. 2 + 2n bytes.

`SellResult`: `reason` u8 (0 ok, 1 nothing to sell, 2 no item, 3 not a fish, 4 read-only profile), `total` u32 (coins
this sale), `coins` u32 (the wallet after), `lines` table (<= 1024 nodes) = `GameData.sellTotal`'s lines without
`name` (the client has SpeciesTable): `{ speciesId, lengthM, weightKg, coins }` each. 13 bytes empty, 297 for four
trout.

### 6.4 `BuyGear` (35) and `Equip` (36), C→S → `BuyResult` (51)

| Field | Type | Range | Meaning |
|---|---|---|---|
| `kind` | u8 | 0..3 | 0 lure, 1 rod, 2 line, 3 hook |
| `id` | str | 0..24 ASCII bytes | a `GameData.LURES` or `GameData.GEAR` id (`rod_carbon`, `spinner`) |

`BuyGear` server rule: the id exists for that kind; a lure costs `LURES[id].price`; gear must be a higher tier than
the equipped one and costs `GameData.upgradeCost(kind, equipped, id)`; coins >= price; not already owned. On ok:
coins -= price, the id joins the owned set, `BuyResult` op 0. RequestGuard 1/s, burst 2.
`Equip` server rule: the id is owned (the starter loadout is owned); on ok the loadout slot changes and the server
reads it on the next cast (`castDistanceMul`, `lineStrengthN`, `hookSetWindowMul`). RequestGuard 2/s, burst 4.
Both 3 + len(id) bytes (13 typical).

`BuyResult`: `op` u8 (0 buy, 1 equip), `ok` bool, `reason` u8 (0 ok, 1 unknown id, 2 not enough coins, 3 owned,
4 not owned, 5 not an upgrade, 6 read-only profile), `coins` u32 (the wallet after). One reply for the shop pair so the
shop UI has one handler (ruling 1). 8 bytes.

### 6.5 `SetOption` (37, C→S), no reply

| Field | Type | Range | Meaning |
|---|---|---|---|
| `key` | u8 | 0..5 | 0 MouseSensitivity, 1 TouchSensitivity, 2 GamepadSensitivity, 3 InvertY, 4 FieldOfViewDeg, 5 HoldToToggleReel (WSH_options_panel_additions.md section 2) |
| `value` | f32 | 0..90 | the option's value; bool options carry 0 or 1 |

Server rule: clamp against `C.Options[key]` (Min..Max, Step; a bool key accepts only 0 or 1, anything else is dropped),
then `profile:set("options.<Key>", value)`. No reply: the client already applied the value locally (WS-H section 3) and
on join the server sends the saved options as attributes, which is the echo. Sender states: every state except Flight
and Hooked (a slider drag during a cast or a fight is not a thing the player means). RequestGuard 5/s, burst 10: the
panel sends on release, or at most every 200 ms during a drag. 6 bytes.

### 6.6 `CatchLogSync` (52, S→C)

| Field | Type | Range | Meaning |
|---|---|---|---|
| `log` | table | <= 4096 nodes | `CatchLog.serialize(log)`: `{ v, totalCount, species = { { id, count, first, bestLengthM, bestWeightKg, bestLengthCatch, zones } } }` |

Sent to the owner on join and after every `CatchLog.record` (the "New species!" / "New record!" cue flags come from
`record()`'s result and ride the existing CatchScene cue, not this message). A full image for the same reasons as
`TackleSync`: 20 species is about 1.7 KB reference, 300 bytes compact, once per catch. Server ceiling 1/s, burst 2.

### 6.7 `WorldSync` (53, S→C) = `WorldClock.snapshot(clock)`

| Field | Type | Range | Meaning |
|---|---|---|---|
| `clockTime` | f32 | 0..24 | `Lighting.ClockTime` |
| `dayN` | u16 | 1..65535 | the in-game day |
| `phase` | u8 | 0..3 | 0 dawn, 1 day, 2 dusk, 3 night |
| `weather` | u8 | 0..2 | 0 clear, 1 overcast, 2 rain |
| `rain` | f32 | 0..1 | smoothed intensity |
| `waveM` | f32 | 0..0.5 | wave amplitude; WorldClock caps it at 0.1 m (pool-fish visibility), the schema range leaves headroom so an f32 rounding of the cap never fails validation on the client |
| `sun` | f32 | -1..1 | sun height |

Attributes may be better than a message: the snapshot is seven slow, independent, idempotent values that every client
wants and a late joiner needs at once. Attributes on a ReplicatedStorage folder give engine replication, the current
value to a joiner with no join code, `GetAttributeChangedSignal` per value, no per-client fan-out loop, and the
`WorldClock` header already says so. A message wins only when the values must land together (a weather change: the
client plays one transition at one instant, and attributes set one by one can be observed half-updated for a frame).
Recommendation (ruling 2): attributes for the 5 s tick (`ClockTime`, `DayN`, `Phase`, `Weather`, `Rain`, `WaveM`,
`Sun`, the snapshot's own keys), and `WorldSync` only on a weather change, as the one atomic event the client scores
a cue on; the id stays allocated and vectored either way. 21 bytes; at 8 anglers every 5 s that is 34 B/s.

### 6.8 `ProfileReady` (54, S→C), after `SaveData.load`

| Field | Type | Range | Meaning |
|---|---|---|---|
| `readOnly` | bool | | true when nothing will be saved this session |
| `reason` | u8 | 0..5 | 0 new, 1 loaded, 2 already-loaded, 3 newer, 4 corrupt, 5 no-migration (`SaveData.load`'s reasons; 3..5 are read-only) |

Handler rule: `readOnly` is true exactly when `reason` >= 3 (a cross-field rule the handler asserts; the schema cannot).
Sent once per join, before `TackleSync` and `CatchLogSync`; a "locked" load (nil profile) sends nothing, the join is
retried and then the player is kicked, as the SaveData header says. The client shows "progress will not save" on
readOnly and disables Sell/Buy (the server refuses them anyway, reason 4 / 6). 3 bytes.

## 7. StateRules rows to append

Y = the action is legal in that state; - = dropped and counted. One row per new action; the existing rows are unchanged.

| Action | Walking | Aiming | Flight | Presenting | Retrieving | Inspected | HookWindow | Hooked | CatchScene | Holding |
|---|---|---|---|---|---|---|---|---|---|---|
| `TackleMove` | Y | - | - | - | - | - | - | - | - | Y |
| `TackleDrop` | Y | - | - | - | - | - | - | - | - | Y |
| `Sell` | Y | - | - | - | - | - | - | - | - | Y |
| `BuyGear` | Y | - | - | - | - | - | - | - | - | Y |
| `Equip` | Y | - | - | - | - | - | - | - | - | Y |
| `SetOption` | Y | Y | - | Y | Y | Y | Y | - | Y | Y |

Box and shop in Walking and Holding only: the box opens while walking and in the make-room flow (holding the fish);
an equip during a cast would change the line strength mid-fight. `SetOption` everywhere but Flight and Hooked, where
a stray slider message during the two timing-critical states is noise the server need not process. The S→C messages
have no row: a client sending id 48..63 is dropped by `NetSchemaV3.allowed` (false for every S→C name) before the
matrix is consulted. `NetSchemaV3.allowed(name, state)` is the same answer as these rows; `rules_test.luau` can assert
the two agree.

## 8. RequestGuard rows to append

| Message | Per second | Burst | On exceed |
|---|---|---|---|
| `TackleMove` | 10 | 20 | drop, count; no kick (a fast rearrange is legitimate) |
| `TackleDrop` | 2 | 4 | drop, count |
| `Sell` | 1 | 2 | drop, count |
| `BuyGear` | 1 | 2 | drop, count |
| `Equip` | 2 | 4 | drop, count |
| `SetOption` | 5 | 10 | drop, count; the panel debounces to 200 ms so a legitimate drag never trips it |

Worst case for one client at every ceiling: 21 messages/s, 90 bytes/s compact, under the 30/s ceiling the PERF note
quotes for cues. The MP stress test's Z8 (8 clients at the legal cadence: 0 rejections; one at 2x: rejected alone)
extends to these six rows with the same driver.

## 9. Net and state impact

| Item | Change | Where |
|---|---|---|
| Player states | none; 6 new actions (section 7) | `StateRules` matrix rows |
| Cues | none in v2; 13 v3 ids 32..54 | `FishingNet` (v3 dispatch on id >= 32), `FishingNetClient` |
| Guard rules | 6 rows (section 8); malformed payloads drop and count like a rate rejection | `RequestGuard` |
| Wire size | +0 B on every v2 message; v3 sizes in section 3 | `net_vectors_v3.json`, `netschemav3_test.luau` |

## 10. Rulings needed (Coordinator)

1. `Equip`'s reply.
   - A: `BuyResult` with an `op` byte answers both `BuyGear` and `Equip` (one shop reply, one handler). Cost: one byte
     per reply. Fidelity: n/a (UI plumbing).
   - B: a separate `EquipResult` (id 55). Cost: one more id and handler; the shop UI has two reply paths.
   - Recommendation: A.
2. `WorldSync` carrier.
   - A: attributes for the 5 s tick, the message only on a weather change (section 6.7). Cost: two paths, both tiny.
   - B: the message every 5 s and on change, no attributes. Cost: a join path and a per-client loop for a value every
     client wants anyway.
   - Recommendation: A.
3. `SetOption.value` for bool options.
   - A: one message, bools as 0/1 in the f32 (section 6.5). Cost: none on the wire; the server checks 0/1 per key.
   - B: two messages, `SetOptionNum` and `SetOptionBool`. Cost: one more id, two handlers, the same clamp twice.
   - Recommendation: A.
4. `TackleDrop` of a lure or gear item: no refund (A) or sell-price refund (B). Recommendation: A, it is "discard";
   selling is `Sell`. (A dropped fish has no refund in either option.)

## 11. Files touched

| File | Change | Owner | Reviewer |
|---|---|---|---|
| `src/Fishing/Shared/NetSchemaV3.lua` | new, the schema + validate/allowed/check + reference codec (398 lines, `luau-analyze` clean) | Cloud → Dev3 | Dev1 |
| `tools/net_vectors_v3.py`, `tools/net_vectors_v3_test.py` | new, Dev3-style independent encoder, `--check`, `--selftest` | Cloud → Dev3 | Dev1 |
| `tests/fixtures/net_vectors_v3.json`, `tests/fixtures/net_vectors_v3_data.luau` | generated, 92 vectors (43 valid, 49 invalid) | generated | Dev3 |
| `tests/netschemav3_test.luau` | new, the schema gate (every vector) | Cloud → Dev3 | Dev1 |
| `Fishing/Shared/FishingNet.lua` | v3 dispatch: id >= 32 goes to the v3 table; v2 untouched | Dev3 | Dev1 |
| `Fishing/Shared/StateRules.lua` | the 6 rows of section 7 | Dev3 | Dev1 |
| `Fishing/Server/RequestGuard.lua` | the 6 rows of section 8 | Dev3 | Dev1 |
| `Fishing/Server/FishingServer.lua` (or a `ShopServer`/`BoxServer` script) | handlers per section 6 | Dev1 | Dev3 |
| `tools/net_sim_f1.py` | v3 tables added from section 6, writing `net_vectors.json` v3 entries in the compact form | Dev3 | Dev1 |

## 12. Offline tests

| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/netschemav3_test.luau` | check() passes; mutated schema copies fail; every field type and reason; allowed per state; encode/decode; all 92 vectors agree with the Python encoder | a duplicate id fails check(); a flipped byte and a changed payload no longer match | `netschemav3_test: PASS 190` |
| `tools/net_vectors_v3_test.py` | --selftest; deterministic generation; the committed fixtures are current; --check exits 0 | one flipped hex byte makes --check exit 1; a stale Luau data module fails | `net_vectors_v3_test: PASS 27` |
| `rules_test.luau` (Dev3) | the 6 new rows match `NetSchemaV3.allowed` for all 10 states | a row flipped by hand FAILs | Dev3 |
| `net_vectors_test.luau` (Dev3, v2) | unchanged bytes: the LEGACY gate still passes with v3 in the tree | — | unchanged count |

## 13. PARITY rows

| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| P01 box moves are server-checked | the box is the player's inventory | `TackleMove` → `TackleBox.move` on the server; the client only draws `TackleSync` | planned | `netschemav3_test.luau` |
| P02 make room | "you must make room" | `TackleDrop` + reason 7 until the held fish fits | planned | section 6.2 |
| P04 money readout | a total at the trader | `SellResult.coins` / `BuyResult.coins`; no client message adds money | planned | `allowed` has no such action |
| P06 lure swap only when idle | swapping a lure | `Equip` legal in Walking/Holding only | planned | section 7 row |

## 14. Open questions

- The real v2 id range and whether the v2 decoder drops or errors on an unknown id (Dev3, before the v3 dispatch).
- Whether `StateRules` names the states exactly as CONTEXT lists them (`Hooked` vs `Fight`); `NetSchemaV3.STATES` must
  match byte for byte (Dev3, on reading the matrix).
- The compact layout of `TackleSync.items` once SpeciesTable's shape names are indexed (Dev3, with the `net_sim_f1.py`
  tables).
- A `LoadoutSync` (coins, loadout, owned ids) on join: id 55, not defined here because WS-E's loadout save shape is not
  settled (Dev1, with GameData's SaveData wiring).
