--!strict
-- inventoryservice_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves src/Fishing/Server/InventoryService.lua with the stub: a fake player, a SaveData over the stub's
-- DataStore, a spy net.send. Join syncs; catch placement; TackleMove accepted, refused by the schema (bad
-- rot), refused by the state (Hooked), refused by the box (overlap, bounds, no item); TackleDrop; Sell of
-- four median trout = 32 coins, an id not owned, a duplicate, a gear item, read-only; BuyGear without
-- coins, owned, not an upgrade; Equip of unowned gear; a catch into a full box -> make-room -> drops ->
-- placed, a move or a sell that frees the room, cancel; a corrupt saved box / log / coins / loadout ->
-- empty + warn + ProfileReady still sent; a read-only profile; the profile round-trips through the stub
-- store into a second server; every S2C payload passes the schema; a mutated schema is consulted
-- (negative control); and a 200-request seeded fuzz asserting coins >= 0, check(), unique ids and the
-- profile's box equal to the live box after every request.
-- Run from this folder: luau inventoryservice_test.luau

local Stub = require("./RobloxStub")
local SaveData = require("../src/Fishing/Server/SaveData")
local InventoryService = require("../src/Fishing/Server/InventoryService")
local TackleBox = require("../src/Fishing/Shared/TackleBox")
local GameData = require("../src/Fishing/Shared/GameData")
local SpeciesTable = require("../src/Fishing/Shared/SpeciesTable")
local CatchLog = require("../src/Fishing/Shared/CatchLog")
local NetSchemaV3 = require("../src/Fishing/Shared/NetSchemaV3")
local T = Stub.harness("inventoryservice_test")

local STORE = "PlayerData"

-- a tiny seeded LCG with the Roblox Random shape
local function lcg(seed: number): SpeciesTable.Rng
	local s = seed
	local function nextNumber(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
	local rng = {}
	function rng.NextNumber(_self: any, _a: number?, _b: number?): number
		return nextNumber()
	end
	function rng.NextInteger(_self: any, a: number, b: number): number
		return a + math.floor(nextNumber() * (b - a + 1))
	end
	return rng
end

type Sent = { player: any, name: string, payload: { [string]: any } }

-- A fresh runtime: stub services, a SaveData over the stub store (optionally pre-seeded for user 1), a spy
-- net, the service, and player 1 loaded through the real load -> onProfileLoaded path.
local function world(stored: { [string]: any }?, schema: any?)
	local R = Stub.new()
	local deps = {
		DataStoreService = R.DataStoreService, Players = R.Players, HttpService = R.HttpService, task = R.task, Enum = R.Enum,
		clock = function(): number
			return R.clock.now
		end,
		warn = R.warn,
		jobId = "job-A",
	}
	local sd = SaveData.new(deps :: any, { storeName = STORE, schemaVersion = 1, defaults = InventoryService.defaults })
	local sent: { Sent } = {}
	local net = {
		send = function(player: any, name: string, payload: { [string]: any })
			table.insert(sent, { player = player, name = name, payload = payload })
		end,
	}
	local svc = InventoryService.new({
		saveData = sd, net = net, schema = schema, warn = R.warn,
		clock = function(): number
			return R.clock.now
		end,
	})
	if stored then
		R.dataStores.stores[STORE]["u1"] = stored
	end
	local p = R.Players:addFake(1, "Angler")
	local prof, why = sd:load(p)
	assert(prof, "load failed: " .. tostring(why))
	svc:onProfileLoaded(p, prof, why)
	local W = { R = R, sd = sd, svc = svc, p = p, prof = prof, why = why, sent = sent }
	-- the last payload of a name, or nil
	function W.last(name: string): { [string]: any }?
		for i = #sent, 1, -1 do
			if sent[i].name == name then
				return sent[i].payload
			end
		end
		return nil
	end
	function W.count(name: string): number
		local n = 0
		for _, s in sent do
			if s.name == name then
				n += 1
			end
		end
		return n
	end
	function W.clear()
		table.clear(sent)
	end
	return W
end

-- A stored record: the defaults plus _v plus overrides.
local function storedWith(over: { [string]: any }): { [string]: any }
	local d = InventoryService.defaults()
	d._v = 1
	for k, v in over do
		d[k] = v
	end
	return d
end

local function catchOf(speciesId: string, lengthM: number): CatchLog.Catch
	return { speciesId = speciesId, lengthM = lengthM, weightKg = SpeciesTable.weightFor(speciesId, lengthM), zoneId = "shore", dayN = 1, timeOfDay = 9, lureId = "worm" }
end

local function json(v: any): string
	return Stub.jsonEncode(v)
end

-- ---------------------------------------------------------------- defaults
do
	local d = InventoryService.defaults()
	T.check(d.box.w == 8 and d.box.h == 6 and d.box.nextId == 1 and #d.box.items == 0, "defaults: an empty 8 x 6 box in serialize form")
	T.eq(d.coins, 0, "defaults: coins 0 (WSE ruling 1A)")
	T.check(d.loadout.rod == GameData.STARTER.rod and d.loadout.lure == GameData.STARTER.lure and d.loadout.owned.lure.worm == true and d.loadout.owned.rod.rod_basic == true, "defaults: the starter loadout, every starter item owned")
	T.check(d.catchLog.v == 1 and d.catchLog.totalCount == 0, "defaults: an empty catch log in serialize form")
	T.check(pcall(json, d), "defaults: the whole profile is JSON-safe")
end

-- ---------------------------------------------------------------- join
do
	local W = world()
	T.eq(W.why, "new", "join: a new player loads as new")
	T.check(W.sent[1] and W.sent[1].name == "ProfileReady", "join: ProfileReady is the first message")
	local ready = W.last("ProfileReady")
	T.check(ready and ready.readOnly == false and ready.reason == 0, "join: ProfileReady { readOnly = false, reason = 0 new }")
	T.check(W.sent[2].name == "TackleSync" and W.sent[3].name == "CatchLogSync", "join: TackleSync then CatchLogSync follow")
	local sync = W.last("TackleSync")
	T.check(sync and sync.w == 8 and sync.h == 6 and sync.nextId == 1 and #sync.items == 0, "join: TackleSync carries the empty box")
	local logSync = W.last("CatchLogSync")
	T.check(logSync and logSync.log.totalCount == 0, "join: CatchLogSync carries the empty log")
	T.check(W.svc:has(W.p) and W.svc:coins(W.p) == 0 and not W.svc:isMakeRoom(W.p), "join: the record exists with 0 coins and nothing held")
	T.eq(W.svc:onProfileLoaded(W.p, W.prof, "loaded"), false, "join: a second onProfileLoaded for the same player is refused")
	T.check(W.R.warnings[#W.R.warnings]:find("already loaded", 1, true) ~= nil, "join: ... and warns")
end

-- ---------------------------------------------------------------- a catch, moves, a drop
do
	local W = world()
	W.clear()
	local r = W.svc:onCatch(W.p, catchOf("trout", 0.40))
	assert(r)
	T.check(r.placed and r.id == 1 and not r.makeRoom, "catch: a median trout is placed as id 1")
	T.check(r.flags.isFirst and r.flags.isLengthRecord and r.flags.countNow == 1, "catch: the CatchLog flags come back (first, record)")
	local sync = W.last("TackleSync")
	assert(sync)
	T.check(#sync.items == 1 and sync.items[1].kind == "fish" and sync.items[1].key == "trout" and sync.items[1].x == 1 and sync.items[1].y == 1 and #sync.items[1].shape == 2, "catch: TackleSync shows the fish at (1,1), shape line2 for 0.40 m")
	T.check(sync.items[1].data.speciesId == "trout" and sync.items[1].data.lengthM == 0.40, "catch: the item data carries speciesId / lengthM / weightKg for the sale")
	local logSync = W.last("CatchLogSync")
	local logT: any = if logSync then logSync.log else nil
	T.check(logT and logT.totalCount == 1 and logT.species[1].id == "trout", "catch: CatchLogSync shows the trout")
	T.check(#W.prof.data.box.items == 1 and W.prof.data.catchLog.totalCount == 1 and W.prof:isDirty(), "catch: box and catchLog are written back to the profile (dirty)")

	W.clear()
	local ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 1, x = 3, y = 3 }, "Walking")
	local res = W.last("TackleMoveResult")
	T.check(ok and code == 0 and res and res.ok == true and res.reason == 0, "move: an accepted move answers { ok = true, reason = 0 }")
	sync = W.last("TackleSync")
	assert(sync)
	T.check(sync.items[1].x == 3 and sync.items[1].y == 3 and sync.items[1].rot == 1, "move: TackleSync shows the new cell and rotation")
	T.check(W.prof.data.box.items[1].x == 3 and W.prof.data.box.items[1].rot == 1, "move: the profile's box follows")

	W.clear()
	ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 4, x = 1, y = 1 }, "Walking")
	res = W.last("TackleMoveResult")
	T.check(not ok and code == 2 and res and res.ok == false and res.reason == 2, "move: rot 4 fails the schema -> { false, 2 bad rotation }")
	T.eq(W.count("TackleSync"), 0, "move: a refused move sends no TackleSync")
	T.eq(W.svc:stats().rejected.TackleMove, 1, "move: the schema refusal counts in rejected")
	T.check(TackleBox.at(W.svc:box(W.p) :: TackleBox.Box, 3, 3) == 1, "move: the box is unchanged")

	W.clear()
	ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 0, x = 1, y = 1 }, "Hooked")
	res = W.last("TackleMoveResult")
	T.check(not ok and code == 6 and res and res.reason == 6, "move: Hooked is not a box state -> { false, 6 wrong state }")
	T.eq(W.svc:stats().rejected.TackleMove, 2, "move: the state refusal counts too")
	T.eq(W.svc:stats().handled.TackleMove, 1, "move: handled counts only the requests that passed the gate")

	W.svc:onCatch(W.p, catchOf("trout", 0.30)) -- id 2, line1 at (1,1)
	W.clear()
	ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 0, x = 1, y = 1 }, "Walking")
	T.check(not ok and code == 5, "move: onto another item -> 5 overlap")
	ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 0, x = 8, y = 6 }, "Holding")
	T.check(not ok and code == 4, "move: off the grid -> 4 out of bounds")
	ok, code = W.svc:handleTackleMove(W.p, { id = 99, rot = 0, x = 1, y = 1 }, "Walking")
	T.check(not ok and code == 1, "move: an id the player does not hold -> 1 no item")
	ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 0, x = 2, y = 2, extra = 1 }, "Walking")
	T.check(not ok and code == 3, "move: an unexpected field -> the catch-all 3 bad position")
	ok, code = W.svc:handleTackleMove(W.p, "nope", "Walking")
	T.check(not ok and code == 3, "move: a non-table payload -> 3")
	ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 0, y = 2 }, "Walking")
	T.check(not ok and code == 3, "move: a missing x -> 3")
	T.eq(W.count("TackleMoveResult"), 6, "move: every refusal above was answered")

	W.clear()
	ok, code = W.svc:handleTackleDrop(W.p, { id = 2 }, "Walking")
	res = W.last("TackleMoveResult")
	sync = W.last("TackleSync")
	T.check(ok and code == 0 and res and res.ok == true and sync and #sync.items == 1, "drop: a drop answers { true, 0 } and syncs the box without the item")
	T.check(W.svc:log(W.p) and (W.svc:log(W.p) :: CatchLog.Log).totalCount == 2, "drop: the catch log keeps the dropped fish (history, not inventory)")
	ok, code = W.svc:handleTackleDrop(W.p, { id = 2 }, "Walking")
	T.check(not ok and code == 1, "drop: the same id again -> 1 no item (anti-dupe)")
	ok, code = W.svc:handleTackleDrop(W.p, { id = 1 }, "Aiming")
	T.check(not ok and code == 6, "drop: not in Aiming -> 6")
end

-- ---------------------------------------------------------------- sell
do
	local W = world()
	for _ = 1, 4 do
		W.svc:onCatch(W.p, catchOf("trout", 0.40)) -- ids 1..4
	end
	W.clear()
	local ok, code = W.svc:handleSell(W.p, { ids = { 1, 2, 3, 4 } }, "Walking")
	local res = W.last("SellResult")
	assert(res)
	T.check(ok and code == 0 and res.reason == 0, "sell: four median trout sell")
	T.check(res.total == 32 and res.coins == 32, "sell: total 32 = four x 8 coins (WSE calibration), wallet 32")
	T.check(#res.lines == 4 and res.lines[1].speciesId == "trout" and res.lines[1].coins == 8 and res.lines[1].name == nil, "sell: one line per fish without the name (the client has SpeciesTable)")
	local sync = W.last("TackleSync")
	T.check(sync and #sync.items == 0, "sell: TackleSync shows the empty box")
	T.check(W.svc:coins(W.p) == 32 and W.prof:get("coins") == 32 and #W.prof.data.box.items == 0, "sell: coins and box written back to the profile together")
	T.check(#W.sent >= 2 and W.sent[1].name == "SellResult" and W.sent[2].name == "TackleSync", "sell: SellResult then TackleSync")

	W.svc:onCatch(W.p, catchOf("trout", 0.40)) -- id 5
	W.clear()
	ok, code = W.svc:handleSell(W.p, { ids = { 5, 99 } }, "Walking")
	res = W.last("SellResult")
	T.check(not ok and code == 2 and res and res.reason == 2 and res.total == 0 and res.coins == 32, "sell: an id the player does not own -> 2, nothing sold")
	T.check(TackleBox.at(W.svc:box(W.p) :: TackleBox.Box, 1, 1) == 5 and W.svc:coins(W.p) == 32, "sell: ... the good id in the same request stays in the box (atomic)")
	ok, code = W.svc:handleSell(W.p, { ids = { 5, 5 } }, "Walking")
	T.check(not ok and code == 2, "sell: the same id twice in one request -> 2")
	ok, code = W.svc:handleSell(W.p, { ids = {} }, "Walking")
	T.check(not ok and code == 1, "sell: an empty list -> 1 nothing to sell")
	local gearId = TackleBox.place(W.svc:box(W.p) :: TackleBox.Box, { kind = "gear", key = "hook_sharp", shape = TackleBox.SHAPES.L3 }, 0, 4, 4)
	ok, code = W.svc:handleSell(W.p, { ids = { gearId :: number } }, "Walking")
	T.check(not ok and code == 3, "sell: a gear item -> 3 not a fish")
	W.clear()
	ok, code = W.svc:handleSell(W.p, { ids = { 5 } }, "Hooked")
	T.check(not ok and code == nil and #W.sent == 0, "sell: in Hooked there is no SellResult code for wrong state: dropped silently")
	T.eq(W.svc:stats().rejected.Sell, 1, "sell: ... but counted")
	ok, code = W.svc:handleSell(W.p, { ids = "x" }, "Walking")
	res = W.last("SellResult")
	T.check(not ok and code == 2 and res and res.reason == 2, "sell: a bad ids field -> 2")
	ok, code = W.svc:handleSell(W.p, { ids = { 5 } }, "Holding")
	T.check(ok and W.svc:coins(W.p) == 40, "sell: Holding is a shop state; wallet 40")
end

-- ---------------------------------------------------------------- buy and equip
do
	local W = world()
	for _ = 1, 4 do
		W.svc:onCatch(W.p, catchOf("trout", 0.40))
	end
	W.svc:handleSell(W.p, { ids = { 1, 2, 3, 4 } }, "Walking") -- 32 coins
	W.clear()
	local ok, code = W.svc:handleBuyGear(W.p, { kind = 2, id = "line_braid" }, "Walking")
	local res = W.last("BuyResult")
	T.check(not ok and code == 2 and res and res.op == 0 and res.ok == false and res.reason == 2 and res.coins == 32, "buy: line_braid (40) with 32 coins -> 2 not enough coins")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 0, id = "spinner" }, "Walking")
	res = W.last("BuyResult")
	T.check(ok and code == 0 and res and res.ok == true and res.coins == 22, "buy: a spinner (10) -> ok, wallet 22")
	local lo = W.svc:loadout(W.p) :: InventoryService.Loadout
	T.check(lo.owned.lure.spinner == true and lo.lure == "worm", "buy: the spinner is owned, not equipped")
	T.check(W.prof.data.loadout.owned.lure.spinner == true and W.prof:get("coins") == 22, "buy: loadout and coins written to the profile")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 0, id = "spinner" }, "Walking")
	T.check(not ok and code == 3, "buy: the same lure again -> 3 owned")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 1, id = "rod_basic" }, "Walking")
	T.check(not ok and code == 3, "buy: the starter rod -> 3 owned")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 1, id = "rod_x" }, "Walking")
	T.check(not ok and code == 1, "buy: an unknown id -> 1")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 0, id = "rod_carbon" }, "Walking")
	T.check(not ok and code == 1, "buy: a rod id under the lure kind -> 1 unknown")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 4, id = "worm" }, "Walking")
	res = W.last("BuyResult")
	T.check(not ok and code == 1 and res and res.reason == 1, "buy: kind 4 fails the schema -> BuyResult 1")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 0, id = "w\195\182rm" }, "Walking")
	T.check(not ok and code == 1, "buy: a non-ASCII id fails the schema -> 1")

	W.clear()
	ok, code = W.svc:handleEquip(W.p, { kind = 2, id = "line_fluoro" }, "Walking")
	res = W.last("BuyResult")
	T.check(not ok and code == 4 and res and res.op == 1 and res.reason == 4, "equip: unowned gear -> BuyResult op 1 reason 4 not owned")
	ok, code = W.svc:handleEquip(W.p, { kind = 2, id = "nope" }, "Walking")
	T.check(not ok and code == 1, "equip: an unknown id -> 1")
	ok, code = W.svc:handleEquip(W.p, { kind = 0, id = "spinner" }, "Walking")
	res = W.last("BuyResult")
	T.check(ok and code == 0 and res and res.op == 1 and res.ok == true and res.coins == 22, "equip: the owned spinner -> op 1 ok, coins unchanged")
	T.check((W.svc:loadout(W.p) :: InventoryService.Loadout).lure == "spinner" and W.prof.data.loadout.lure == "spinner", "equip: the loadout slot changed, in memory and in the profile")
	W.clear()
	ok, code = W.svc:handleEquip(W.p, { kind = 0, id = "worm" }, "Hooked")
	T.check(not ok and code == nil and #W.sent == 0 and W.svc:stats().rejected.Equip == 1, "equip: in Hooked (P06) -> dropped and counted")
	T.eq((W.svc:loadout(W.p) :: InventoryService.Loadout).lure, "spinner", "equip: ... the loadout did not change")

	-- gear tiers: 500 coins stored, buy up and down
	local W2 = world(storedWith({ coins = 500 }))
	T.eq(W2.why, "loaded", "tiers: the seeded record loads")
	ok, code = W2.svc:handleBuyGear(W2.p, { kind = 1, id = "rod_pro" }, "Walking")
	T.check(ok and W2.svc:coins(W2.p) == 320, "tiers: rod_pro from rod_basic costs upgradeCost 180")
	ok, code = W2.svc:handleEquip(W2.p, { kind = 1, id = "rod_pro" }, "Walking")
	T.check(ok and (W2.svc:loadout(W2.p) :: InventoryService.Loadout).rod == "rod_pro", "tiers: equip rod_pro")
	ok, code = W2.svc:handleBuyGear(W2.p, { kind = 1, id = "rod_carbon" }, "Walking")
	T.check(not ok and code == 5 and W2.svc:coins(W2.p) == 320, "tiers: rod_carbon under the equipped rod_pro -> 5 not an upgrade")
	ok, code = W2.svc:handleBuyGear(W2.p, { kind = 3, id = "hook_wide" }, "Walking")
	T.check(ok and W2.svc:coins(W2.p) == 230, "tiers: hook_wide from hook_basic costs 90")
	ok, code = W2.svc:handleBuyGear(W2.p, { kind = 2, id = "line_braid" }, "Walking")
	ok, code = W2.svc:handleEquip(W2.p, { kind = 2, id = "line_braid" }, "Walking")
	ok, code = W2.svc:handleBuyGear(W2.p, { kind = 2, id = "line_fluoro" }, "Walking")
	T.check(ok and W2.svc:coins(W2.p) == 230 - 40 - 80, "tiers: line_fluoro from the equipped line_braid costs the difference, 80")
	T.check(pcall(json, W2.prof.data), "tiers: the profile stays JSON-safe after every purchase")
end

-- ---------------------------------------------------------------- a full box: make room
do
	local W = world()
	for _ = 1, 48 do
		W.svc:onCatch(W.p, catchOf("trout", 0.30)) -- line1 each: ids 1..48 fill 8 x 6
	end
	T.eq(TackleBox.freeCells(W.svc:box(W.p) :: TackleBox.Box), 0, "make room: 48 small trout fill the box")
	W.clear()
	local r = W.svc:onCatch(W.p, catchOf("pike", 1.0)) -- line4
	assert(r)
	T.check(not r.placed and r.makeRoom and r.id == nil and r.flags.isFirst, "make room: the 49th fish (a 1.0 m pike, line4) does not fit -> makeRoom, still recorded")
	local cue = W.last("TackleMoveResult")
	T.check(cue and cue.ok == false and cue.reason == 7, "make room: the cue is TackleMoveResult { false, 7 no room }")
	T.check(W.last("CatchLogSync") ~= nil and W.last("TackleSync") ~= nil, "make room: the log and the box are synced on entry")
	T.check(W.svc:isMakeRoom(W.p) and (W.svc:heldFish(W.p) :: TackleBox.Item).key == "pike" and W.svc:heldSinceT(W.p) == 0, "make room: the pike is held (since clock 0)")
	local r2, why2 = W.svc:onCatch(W.p, catchOf("trout", 0.30))
	T.check(r2 == nil and why2 == "holding", "make room: a second catch while holding is refused")

	local ok, code = W.svc:handleTackleDrop(W.p, { id = 1 }, "Holding")
	T.check(ok and code == 7, "make room: dropping one small trout frees 1 cell -> { true, 7 } still no room")
	ok, code = W.svc:handleTackleDrop(W.p, { id = 2 }, "Holding")
	ok, code = W.svc:handleTackleDrop(W.p, { id = 3 }, "Holding")
	T.check(ok and code == 7 and W.svc:isMakeRoom(W.p), "make room: three cells in a row are still not four")
	W.clear()
	ok, code = W.svc:handleTackleDrop(W.p, { id = 4 }, "Holding")
	local res = W.last("TackleMoveResult")
	T.check(ok and code == 0 and res and res.ok == true and res.reason == 0, "make room: the fourth drop places the pike -> { true, 0 }")
	T.check(not W.svc:isMakeRoom(W.p) and TackleBox.at(W.svc:box(W.p) :: TackleBox.Box, 1, 1) == 49 and TackleBox.at(W.svc:box(W.p) :: TackleBox.Box, 4, 1) == 49, "make room: the pike is id 49 along row 1")
	local sync = W.last("TackleSync")
	T.check(sync and #sync.items == 45 and W.prof.data.box.nextId == 50, "make room: TackleSync shows 44 trout + the pike; the profile's nextId is 50")
	T.check(TackleBox.check(W.svc:box(W.p) :: TackleBox.Box), "make room: the box invariant holds")

	-- a move that frees the room
	local W3 = world()
	for _ = 1, 48 do
		W3.svc:onCatch(W3.p, catchOf("trout", 0.30))
	end
	W3.svc:onCatch(W3.p, catchOf("trout", 0.40)) -- line2 held
	W3.svc:handleTackleDrop(W3.p, { id = 1 }, "Holding") -- (1,1) free
	ok, code = W3.svc:handleTackleDrop(W3.p, { id = 3 }, "Holding") -- (3,1) free, not adjacent
	T.check(code == 7 and W3.svc:isMakeRoom(W3.p), "make room (move): two free cells apart do not fit a line2")
	W3.clear()
	ok, code = W3.svc:handleTackleMove(W3.p, { id = 2, rot = 0, x = 1, y = 1 }, "Holding") -- (2,1) joins (3,1)
	T.check(ok and code == 0 and not W3.svc:isMakeRoom(W3.p), "make room (move): a move that joins the gap places the held fish -> { true, 0 }")
	T.check(TackleBox.at(W3.svc:box(W3.p) :: TackleBox.Box, 2, 1) == 49 and TackleBox.at(W3.svc:box(W3.p) :: TackleBox.Box, 3, 1) == 49, "make room (move): the trout sits on (2,1)-(3,1) as id 49 (a held fish takes no id until placed)")

	-- a sell that frees the room
	local W4 = world()
	for _ = 1, 48 do
		W4.svc:onCatch(W4.p, catchOf("trout", 0.30))
	end
	W4.svc:onCatch(W4.p, catchOf("trout", 0.40))
	W4.clear()
	ok, code = W4.svc:handleSell(W4.p, { ids = { 1, 2 } }, "Holding")
	local names = {}
	for _, s in W4.sent do
		table.insert(names, s.name)
	end
	T.check(ok and table.concat(names, ",") == "SellResult,TackleMoveResult,TackleSync", "make room (sell): SellResult, then the { true, 0 } cue, then TackleSync")
	T.check(not W4.svc:isMakeRoom(W4.p) and TackleBox.at(W4.svc:box(W4.p) :: TackleBox.Box, 1, 1) == 49, "make room (sell): the held trout took the sold cells")

	-- cancel
	local W5 = world()
	for _ = 1, 48 do
		W5.svc:onCatch(W5.p, catchOf("trout", 0.30))
	end
	W5.svc:onCatch(W5.p, catchOf("trout", 0.40))
	W5.clear()
	T.check(W5.svc:cancelMakeRoom(W5.p) and not W5.svc:isMakeRoom(W5.p), "cancel: cancelMakeRoom lets the fish go")
	local c = W5.last("TackleMoveResult")
	T.check(c and c.ok == true and c.reason == 0, "cancel: ... and sends the { true, 0 } cue")
	T.eq(W5.svc:cancelMakeRoom(W5.p), false, "cancel: nothing held -> false")
	ok, code = W5.svc:handleTackleDrop(W5.p, { id = 1 }, "Walking")
	T.check(ok and code == 0 and #TackleBox.items(W5.svc:box(W5.p) :: TackleBox.Box) == 47, "cancel: a later drop is an ordinary drop; no fish appears")
	T.eq((W5.svc:log(W5.p) :: CatchLog.Log).totalCount, 49, "cancel: the released fish stays in the catch log")
end

-- ---------------------------------------------------------------- corrupt fields
do
	local bad = storedWith({ box = { w = 8, h = 6, nextId = 1, items = { { id = 1, kind = "fish", key = "trout", shape = { { 0, 0 } }, rot = 0, x = 9, y = 1 } } } })
	local W = world(bad)
	local ready = W.last("ProfileReady")
	T.check(ready and ready.readOnly == false and ready.reason == 1, "corrupt box: ProfileReady is still sent (writable, loaded)")
	local sync = W.last("TackleSync")
	T.check(sync and #sync.items == 0 and sync.nextId == 1, "corrupt box: the player gets an empty box")
	local warned = false
	for _, w in W.R.warnings do
		if w:find("box is corrupt", 1, true) and w:find("out of bounds", 1, true) then
			warned = true
		end
	end
	T.check(warned, "corrupt box: a warn names the field and TackleBox's reason")
	T.check(W.prof.data.corrupt and W.prof.data.corrupt.box and W.prof.data.corrupt.box.items[1].x == 9, "corrupt box: the stored bytes are kept under data.corrupt.box")
	T.check(W.prof.data.box.items[1].x == 9, "corrupt box: the live field is not overwritten before the first mutation")
	W.svc:onCatch(W.p, catchOf("trout", 0.40))
	T.check(#W.prof.data.box.items == 1 and W.prof.data.box.items[1].x == 1, "corrupt box: the first mutation writes the fresh box")

	local W2 = world(storedWith({ catchLog = { v = 1, totalCount = 3, species = { { id = "trout", count = 0 } } }, coins = -5, loadout = { rod = "rod_gold", line = "line_mono", hook = "hook_basic", lure = "worm", owned = {} } }))
	local logSync = W2.last("CatchLogSync")
	T.check(logSync and logSync.log.totalCount == 0, "corrupt log: an empty log in memory")
	T.eq(W2.svc:coins(W2.p), 0, "corrupt coins (-5): 0 in memory")
	T.eq((W2.svc:loadout(W2.p) :: InventoryService.Loadout).rod, "rod_basic", "corrupt loadout (unknown rod): the starter in memory")
	T.eq(#W2.R.warnings, 3, "corrupt log / coins / loadout: three warns")
	T.check(W2.prof.data.corrupt.catchLog ~= nil and W2.prof.data.corrupt.coins == -5 and W2.prof.data.corrupt.loadout.rod == "rod_gold", "corrupt: all three stashed")
	local W3 = world(storedWith({ coins = 2 ^ 40 }))
	T.eq(W3.svc:coins(W3.p), 0, "corrupt coins (above u32): 0, not a gift of four billion")
	local W4 = world(storedWith({ loadout = { rod = "rod_basic", line = "line_mono", hook = "hook_basic", lure = "spinner", owned = { lure = { worm = true }, rod = { rod_basic = true }, line = { line_mono = true }, hook = { hook_basic = true } } } }))
	T.eq((W4.svc:loadout(W4.p) :: InventoryService.Loadout).lure, "worm", "corrupt loadout (equipped but not owned): the starter")
end

-- ---------------------------------------------------------------- read-only
do
	local W = world(storedWith({ _v = 9, coins = 100 }))
	T.check(W.prof.readOnly and W.why == "newer", "read-only: a newer schema loads read-only")
	local ready = W.last("ProfileReady")
	T.check(ready and ready.readOnly == true and ready.reason == 3, "read-only: ProfileReady { true, 3 newer }")
	W.svc:onCatch(W.p, catchOf("trout", 0.40))
	T.check(TackleBox.at(W.svc:box(W.p) :: TackleBox.Box, 1, 1) == 1, "read-only: a catch still lands in the box in memory")
	local ok, code = W.svc:handleSell(W.p, { ids = { 1 } }, "Walking")
	local res = W.last("SellResult")
	T.check(not ok and code == 4 and res and res.reason == 4 and res.coins == 100, "read-only: Sell -> 4, wallet unchanged")
	ok, code = W.svc:handleBuyGear(W.p, { kind = 0, id = "spinner" }, "Walking")
	T.check(not ok and code == 6 and W.svc:coins(W.p) == 100, "read-only: BuyGear -> 6")
	ok, code = W.svc:handleEquip(W.p, { kind = 0, id = "worm" }, "Walking")
	T.check(not ok and code == 6, "read-only: Equip -> 6")
	ok, code = W.svc:handleTackleMove(W.p, { id = 1, rot = 0, x = 2, y = 2 }, "Walking")
	T.check(ok and code == 0, "read-only: the box can still be rearranged")
	local saved, why = W.sd:save(W.p, "test")
	T.check(not saved and why == "read-only", "read-only: SaveData never writes it")
	local ready2 = world(storedWith({}))
	local r2: any = ready2.last("ProfileReady")
	T.check(r2.readOnly == (r2.reason >= 3), "ProfileReady cross-field rule: readOnly == (reason >= 3) for a writable profile")
	T.check(ready ~= nil and ready.readOnly == (ready.reason >= 3), "ProfileReady cross-field rule: ... and for the read-only one")
end

-- ---------------------------------------------------------------- release and round trip
do
	local W = world()
	W.svc:onCatch(W.p, catchOf("trout", 0.40))
	W.svc:onCatch(W.p, catchOf("trout", 0.52))
	W.svc:onCatch(W.p, catchOf("perch", 0.30))
	W.svc:handleSell(W.p, { ids = { 1 } }, "Walking")
	W.svc:handleBuyGear(W.p, { kind = 0, id = "worm" }, "Walking") -- owned: 3
	W.svc:handleBuyGear(W.p, { kind = 0, id = "boilie" }, "Walking")
	W.svc:handleEquip(W.p, { kind = 0, id = "boilie" }, "Walking")
	W.svc:handleTackleMove(W.p, { id = 2, rot = 1, x = 5, y = 2 }, "Walking")
	local boxJson = json(TackleBox.serialize(W.svc:box(W.p) :: TackleBox.Box))
	local logJson = json(CatchLog.serialize(W.svc:log(W.p) :: CatchLog.Log))
	local coins = W.svc:coins(W.p)
	local okSave, whySave = W.sd:onPlayerRemoving(W.p)
	T.check(okSave and whySave == "saved", "round trip: leaving saves the profile")
	T.check(W.svc:onProfileReleased(W.p) and not W.svc:has(W.p), "round trip: onProfileReleased drops the record")
	local ok, code = W.svc:handleTackleMove(W.p, { id = 2, rot = 0, x = 1, y = 1 }, "Walking")
	T.check(not ok and code == 6, "round trip: a request after release is refused (6) and counted")
	T.eq(W.svc:onProfileReleased(W.p), false, "round trip: a second release -> false")

	-- a second server loads the stored bytes
	local stored = W.R.dataStores.stores[STORE]["u1"]
	T.check(stored and stored._lock == nil, "round trip: the lock was released")
	local W2 = world(Stub.jsonDecode(json(stored)))
	T.eq(W2.why, "loaded", "round trip: the second server loads the record")
	T.eq(json(TackleBox.serialize(W2.svc:box(W2.p) :: TackleBox.Box)), boxJson, "round trip: the box is equal cell for cell")
	T.eq(json(CatchLog.serialize(W2.svc:log(W2.p) :: CatchLog.Log)), logJson, "round trip: the catch log is equal")
	T.eq(W2.svc:coins(W2.p), coins, "round trip: the coins are equal")
	local lo = W2.svc:loadout(W2.p) :: InventoryService.Loadout
	local ownedLures: { [string]: boolean } = lo.owned.lure
	T.check(lo.lure == "boilie" and ownedLures.boilie == true and ownedLures.worm == true, "round trip: the loadout and the owned set are equal")
	T.eq(#W2.R.warnings, 0, "round trip: no warns on a clean record")
	local sync = W2.last("TackleSync")
	T.check(sync and #sync.items == 2 and sync.nextId == 4, "round trip: the join sync shows the two fish left, nextId 4")
end

-- ---------------------------------------------------------------- the schema gate
do
	-- every S2C payload the service built so far passes the schema (the service validates before sending)
	local W = world()
	W.svc:onCatch(W.p, catchOf("carp", 0.80))
	W.svc:handleSell(W.p, { ids = { 1 } }, "Walking")
	W.svc:handleBuyGear(W.p, { kind = 0, id = "worm" }, "Walking")
	local allOk = true
	for _, s in W.sent do
		local ok = NetSchemaV3.validate(s.name, s.payload)
		allOk = allOk and ok
	end
	T.check(allOk and #W.sent >= 7, string.format("schema: all %d sent payloads validate", #W.sent))
	T.eq(W.svc:stats().sendRefused, 0, "schema: nothing was refused on the way out")
	T.check(not NetSchemaV3.validate("TackleMoveResult", { ok = false, reason = 9 }), "schema: negative control: a reason outside the range would not validate")

	-- a mutated schema that forbids TackleMove everywhere is consulted by the gate
	local mutated = table.clone(NetSchemaV3)
	local messages = table.clone(NetSchemaV3.MESSAGES)
	messages.TackleMove = table.clone(messages.TackleMove)
	messages.TackleMove.states = {}
	mutated.allowed = function(name: string, state: string): boolean
		return NetSchemaV3.allowed(name, state, messages)
	end
	local W2 = world(nil, mutated)
	W2.svc:onCatch(W2.p, catchOf("trout", 0.40))
	local ok, code = W2.svc:handleTackleMove(W2.p, { id = 1, rot = 0, x = 2, y = 2 }, "Walking")
	T.check(not ok and code == 6, "schema: negative control: with TackleMove allowed nowhere, a Walking move is refused with 6")
	ok, code = W2.svc:handleTackleDrop(W2.p, { id = 1 }, "Walking")
	T.check(ok, "schema: ... while TackleDrop, untouched in the copy, still works")

	-- coins cap on the wire
	local W3 = world(storedWith({ coins = InventoryService.COINS_MAX }))
	W3.svc:onCatch(W3.p, catchOf("trout", 0.40))
	W3.clear()
	ok, code = W3.svc:handleSell(W3.p, { ids = { 1 } }, "Walking")
	local res = W3.last("SellResult")
	T.check(ok and res and res.coins == InventoryService.COINS_MAX and res.total == 8, "coins: a sale at the u32 cap stays at the cap and still validates")

	-- dispatch
	W3.clear()
	ok, code = W3.svc:dispatch("Equip", W3.p, { kind = 0, id = "worm" }, "Walking")
	T.check(ok and code == 0 and W3.last("BuyResult") ~= nil, "dispatch: routes a name to its handler")
	ok, code = W3.svc:dispatch("SetOption", W3.p, { key = 0, value = 1 }, "Walking")
	T.check(not ok and code == nil and W3.svc:stats().rejected.SetOption == 1, "dispatch: SetOption is not this service's (WS-H): rejected and counted")
	ok, code = W3.svc:dispatch("TackleSync", W3.p, {}, "Walking")
	T.check(not ok and W3.svc:stats().rejected.TackleSync == 1, "dispatch: an S2C name from a client is rejected")
end

-- ---------------------------------------------------------------- fuzz: 200 random requests, invariants after each
do
	local rng = lcg(20261008)
	local W = world(storedWith({ coins = 300 }))
	local states = { "Walking", "Holding", "Hooked", "Aiming", "CatchScene" }
	local species = SpeciesTable.ids()
	-- ids per wire kind (0 lure, 1 rod, 2 line, 3 hook), each list with one bogus id
	local idsByKind = {
		[0] = { "worm", "spinner", "fly", "boilie", "jig", "nope" },
		[1] = { "rod_basic", "rod_carbon", "rod_pro", "nope" },
		[2] = { "line_mono", "line_braid", "line_fluoro", "nope" },
		[3] = { "hook_basic", "hook_sharp", "hook_wide", "nope" },
	}
	local function gearPick(): (number, string)
		local kind = rng:NextInteger(0, 3)
		local list = idsByKind[kind]
		local id = list[rng:NextInteger(1, #list)]
		if rng:NextNumber() < 0.1 then
			kind = 4 -- fails the schema
		end
		return kind, id
	end
	local okAll, coinsOk, uniqueOk, mirrorOk, errored = true, true, true, true, false
	local catches, sells, buys = 0, 0, 0
	for _ = 1, 200 do
		local state = states[rng:NextInteger(1, #states)]
		local box = W.svc:box(W.p) :: TackleBox.Box
		local items = TackleBox.items(box)
		local function someId(): number
			if #items > 0 and rng:NextNumber() < 0.8 then
				return items[rng:NextInteger(1, #items)].id
			end
			return rng:NextInteger(0, 70)
		end
		local op = rng:NextInteger(1, 9)
		local okCall, err = pcall(function()
			if op <= 2 then
				local sp = species[rng:NextInteger(1, #species)]
				local L = SpeciesTable.get(sp).lengthM
				local r = W.svc:onCatch(W.p, catchOf(sp, L.min + (L.max - L.min) * rng:NextNumber()))
				if r then
					catches += 1
				end
			elseif op == 3 then
				W.svc:handleTackleMove(W.p, { id = someId(), rot = rng:NextInteger(0, 4), x = rng:NextInteger(0, 9), y = rng:NextInteger(0, 7) }, state)
			elseif op == 4 then
				W.svc:handleTackleDrop(W.p, { id = someId() }, state)
			elseif op == 5 then
				local ids = {}
				for _ = 1, rng:NextInteger(0, 4) do
					table.insert(ids, if rng:NextNumber() < 0.7 and #items > 0 then items[rng:NextInteger(1, #items)].id else someId())
				end
				local okSell = W.svc:handleSell(W.p, { ids = ids }, state)
				if okSell then
					sells += 1
				end
			elseif op == 6 then
				local kind, id = gearPick()
				local okBuy = W.svc:handleBuyGear(W.p, { kind = kind, id = id }, state)
				if okBuy then
					buys += 1
				end
			elseif op == 7 then
				local kind, id = gearPick()
				W.svc:handleEquip(W.p, { kind = kind, id = id }, state)
			elseif op == 8 then
				W.svc:cancelMakeRoom(W.p)
			else
				W.svc:dispatch("TackleMove", W.p, "garbage", state)
			end
		end)
		if not okCall then
			errored = true
			print("fuzz error: " .. tostring(err))
		end
		box = W.svc:box(W.p) :: TackleBox.Box
		okAll = okAll and pcall(TackleBox.check, box)
		local coins = W.svc:coins(W.p) :: number
		coinsOk = coinsOk and coins >= 0 and coins == math.floor(coins) and coins == W.prof:get("coins")
		local seen: { [number]: boolean } = {}
		for _, p in TackleBox.items(box) do
			if seen[p.id] then
				uniqueOk = false
			end
			seen[p.id] = true
		end
		mirrorOk = mirrorOk and json(TackleBox.serialize(box)) == json(W.prof.data.box)
	end
	T.check(not errored, "fuzz: no handler errored on 200 random requests")
	T.check(okAll, "fuzz: TackleBox.check held after every request")
	T.check(coinsOk, "fuzz: coins never negative, always an integer, always equal to the profile's")
	T.check(uniqueOk, "fuzz: every placed item id unique")
	T.check(mirrorOk, "fuzz: the profile's box equals the live box after every request")
	T.check(catches >= 20 and sells >= 3 and buys >= 1, string.format("fuzz exercised the flows (%d catches, %d sells, %d buys)", catches, sells, buys))
	T.eq(W.svc:stats().sendRefused, 0, "fuzz: every outgoing payload passed the schema")
	local st = W.svc:stats()
	T.check((st.rejected.TackleMove or 0) > 0 and (st.handled.TackleMove or 0) > 0, "fuzz: both counters moved")
	T.check(pcall(json, W.prof.data), "fuzz: the profile is still JSON-safe")
	local okSave, whySave = W.sd:save(W.p, "fuzz")
	T.check(okSave and whySave == "saved", "fuzz: the profile saves through the stub store")
end

T.finish()
