--!strict
-- InventoryService (About Fishing F1, WS-N server glue for WS-T / WS-E / WS-L; Cloud, 2026-10-08; design/WSN_net_v3_messages.md)
-- The server side of the v3 inventory messages: per player a TackleBox, a CatchLog, coins and a loadout
-- restored from the SaveData profile; the five request handlers (TackleMove, TackleDrop, Sell, BuyGear,
-- Equip) that gate with NetSchemaV3.validate + allowed, call the modules and reply with the note's codes;
-- the catch placement with the make-room flow (P02); the owner-only syncs (ProfileReady, TackleSync,
-- CatchLogSync); counters per message.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * ProfileService.server.lua (this folder) is the whole wiring for Studio: deps = { saveData, net = { send },
--     schema = NetSchemaV3, clock, warn }; after SaveData.load: svc:onProfileLoaded(player, profile, why);
--     PlayerRemoving: svc:onProfileReleased(player); one RemoteEvent per C2S message calling
--     svc:dispatch(name, player, payload, state) with the player's F1 state from StateRules. SetOption (37)
--     belongs to WS-H and is not handled here (dispatch counts it as rejected).
--   * FishingServer at CatchScene entry: local r = svc:onCatch(player, { speciesId, lengthM, weightKg, zoneId,
--     dayN, timeOfDay, lureId }); r.flags carries CatchLog's isFirst / isLengthRecord / isWeightRecord for the
--     catch cue; r.placed == false means the player holds the fish (make room): keep them in Holding while
--     svc:isMakeRoom(player); svc:cancelMakeRoom(player) lets the fish go (WST ruling 1B: no timer here;
--     svc:heldSinceT(player) is there if ruling 1A wins).
--   * FishingServer at cast / press / fight: svc:loadout(player) feeds GameData.castDistanceMul,
--     hookSetWindowMul and lineStrengthN.
--   * Profile fields (InventoryService.defaults() is SaveData's opts.defaults): box = TackleBox.serialize form,
--     coins = integer 0..COINS_MAX, loadout = GameData.STARTER slots + owned[kind][id] = true, catchLog =
--     CatchLog.serialize form. Every mutation writes its field back with profile:set; SaveData's autosave,
--     leave and BindToClose do the DataStore writes.
-- Decisions a dev must know (each one is a check in tests/inventoryservice_test.luau):
--   * A profile field that fails to restore (box, catchLog, coins, loadout) falls back to empty / the defaults
--     in memory with a warn; the stored bytes move to data.corrupt.<field> and the live field is overwritten
--     only by its first mutation. ProfileReady, TackleSync and CatchLogSync are still sent.
--   * A request the schema or the state matrix refuses counts in stats().rejected and is answered with the
--     note's code where the reply has one: TackleMoveResult gets the named field's code (id 1, rot 2, x/y 3)
--     or 6 wrong state; SellResult 2 for a bad ids field; BuyResult 1 for a bad kind or id. Sell / BuyGear /
--     Equip in a wrong state have no code in the note and are dropped silently (note sections 5 and 7).
--   * A read-only profile refuses the economy (Sell 4, BuyGear / Equip 6) but still moves and drops in the box
--     and finishes the make-room flow in memory, so catching keeps working in a session that will not save.
--   * In make-room every accepted TackleDrop or TackleMove retries the held fish; the reply's reason is 7 while
--     it still does not fit and 0 once placed. A Sell that frees the room places it too and then sends
--     TackleMoveResult { ok = true, reason = 0 } as the "make-room over" cue; cancelMakeRoom sends the same.
--     Entering make-room sends TackleMoveResult { ok = false, reason = 7 } as the cue that opens the box UI.
--     The held fish is not saved: a leave while holding lets it go (its catch is already in the log).
--   * Every S2C payload is validated against the schema before it is sent; a refused one is warned and
--     counted in stats().sendRefused, never sent. TackleSync.nextId is u16, so a box past 65535 lifetime
--     placements stops syncing: Dev3 widens the field or the box gets an id compaction on load.
-- No Roblox globals; nothing here needs the engine.

local TackleBox = require("../Shared/TackleBox")
local GameData = require("../Shared/GameData")
local SpeciesTable = require("../Shared/SpeciesTable")
local CatchLog = require("../Shared/CatchLog")
local NetSchemaV3 = require("../Shared/NetSchemaV3")
local SaveData = require("./SaveData")

local InventoryService = {}
InventoryService.__index = InventoryService

export type Net = { send: (player: any, name: string, payload: { [string]: any }) -> () }
export type Deps = {
	saveData: any?, -- the SaveData instance (only used to find a profile when onProfileLoaded gets none)
	net: Net,
	schema: any?, -- NetSchemaV3 (default: the module next door; tests inject a mutated copy)
	clock: (() -> number)?, -- stamps when a fish was first held
	warn: ((...any) -> ())?,
	rng: any?, -- reserved: nothing in the inventory is random today
}
export type Owned = { [string]: { [string]: boolean } }
export type Loadout = { rod: string, line: string, hook: string, lure: string, owned: Owned }
export type CatchResult = { placed: boolean, id: number?, makeRoom: boolean, flags: CatchLog.Result }
export type Stats = { handled: { [string]: number }, rejected: { [string]: number }, sent: { [string]: number }, sendRefused: number }

type Held = { item: TackleBox.Item, sinceT: number }
type Rec = { player: any, userId: number, profile: SaveData.Profile, box: TackleBox.Box, log: CatchLog.Log, loadout: Loadout, coins: number, held: Held? }
type Fields = {
	_saveData: any, _net: Net, _schema: any, _clock: () -> number, _warn: (...any) -> (), _rng: any,
	_recs: { [number]: Rec }, _stats: Stats,
}
export type InventoryService = typeof(setmetatable({} :: Fields, InventoryService))

InventoryService.COINS_MAX = 4294967295 -- u32 on the wire (SellResult.coins, BuyResult.coins)
InventoryService.KINDS = { "lure", "rod", "line", "hook" } -- the wire's kind u8 is the index - 1
InventoryService.PROFILE_FIELDS = { "box", "coins", "loadout", "catchLog" }

local KIND_OF: { [number]: string } = { [0] = "lure", [1] = "rod", [2] = "line", [3] = "hook" }
local GEAR_TABLE: { [string]: string } = { rod = "rods", line = "lines", hook = "hooks" }
-- ProfileReady.reason: SaveData.load's reasons in the note's order (3..5 are read-only)
local READY_CODE: { [string]: number } = { new = 0, loaded = 1, ["already-loaded"] = 2, newer = 3, corrupt = 4, ["no-migration"] = 5 }
-- TackleMoveResult.reason: the TackleBox.move strings, then wrong state and no room
local MOVE_CODE: { [string]: number } = { ["no item"] = 1, ["bad rotation"] = 2, ["bad position"] = 3, ["out of bounds"] = 4, overlap = 5 }
local MOVE_OK, MOVE_NO_ITEM, MOVE_BAD_POSITION, MOVE_WRONG_STATE, MOVE_NO_ROOM = 0, 1, 3, 6, 7
-- SellResult.reason
local SELL_OK, SELL_NOTHING, SELL_NO_ITEM, SELL_NOT_FISH, SELL_READ_ONLY = 0, 1, 2, 3, 4
-- BuyResult.op and .reason
local OP_BUY, OP_EQUIP = 0, 1
local BUY_OK, BUY_UNKNOWN, BUY_NO_COINS, BUY_OWNED, BUY_NOT_OWNED, BUY_NOT_UPGRADE, BUY_READ_ONLY = 0, 1, 2, 3, 4, 5, 6

-- What a request refused by the gate (schema or state) is answered with: the code of the field the
-- schema named, else the message's catch-all; a wrong state only where the reply has a code for it.
type RejectRule = { reply: string, op: number?, wrongState: number?, byField: { [string]: number }, default: number? }
local REJECT: { [string]: RejectRule } = {
	TackleMove = { reply = "TackleMoveResult", wrongState = MOVE_WRONG_STATE, byField = { id = MOVE_NO_ITEM, rot = 2, x = MOVE_BAD_POSITION, y = MOVE_BAD_POSITION }, default = MOVE_BAD_POSITION },
	TackleDrop = { reply = "TackleMoveResult", wrongState = MOVE_WRONG_STATE, byField = { id = MOVE_NO_ITEM }, default = MOVE_BAD_POSITION },
	Sell = { reply = "SellResult", byField = { ids = SELL_NO_ITEM } },
	BuyGear = { reply = "BuyResult", op = OP_BUY, byField = { kind = BUY_UNKNOWN, id = BUY_UNKNOWN } },
	Equip = { reply = "BuyResult", op = OP_EQUIP, byField = { kind = BUY_UNKNOWN, id = BUY_UNKNOWN } },
}
local HANDLER: { [string]: string } = { TackleMove = "handleTackleMove", TackleDrop = "handleTackleDrop", Sell = "handleSell", BuyGear = "handleBuyGear", Equip = "handleEquip" }

-- ---------------------------------------------------------------- helpers
local function isInt(v: any): boolean
	return typeof(v) == "number" and v == math.floor(v) and math.abs(v) < math.huge
end

local function isPos(v: any): boolean
	return typeof(v) == "number" and v == v and v > 0 and v < math.huge
end

-- The GameData entry for a kind ("lure" | "rod" | "line" | "hook") and id, or nil.
local function lookup(kind: string, id: any): any
	if typeof(id) ~= "string" then
		return nil
	end
	if kind == "lure" then
		return GameData.LURES[id]
	end
	local tbl = GEAR_TABLE[kind]
	if tbl == nil then
		return nil
	end
	return (GameData.GEAR :: any)[tbl][id]
end

-- The field a validate() reason names ("missing x", "x: out of range", "unexpected x"), or nil.
local function fieldOf(reason: string): string?
	return string.match(reason, "^missing (%S+)$") or string.match(reason, "^unexpected (%S+)$") or string.match(reason, "^([^:]+): ")
end

-- Why an untrusted loadout is not one: every slot a known id, owned sets of known ids, each slot owned.
local function loadoutProblem(l: any): string?
	if typeof(l) ~= "table" or typeof(l.owned) ~= "table" then
		return "not a loadout table"
	end
	for _, kind in InventoryService.KINDS do
		local id = l[kind]
		if lookup(kind, id) == nil then
			return string.format("unknown %s '%s'", kind, tostring(id))
		end
		local set = l.owned[kind]
		if typeof(set) ~= "table" then
			return "owned." .. kind .. " missing"
		end
		for oid, v in set do
			if v ~= true or lookup(kind, oid) == nil then
				return string.format("owned.%s.%s is not an owned id", kind, tostring(oid))
			end
		end
		if set[id] ~= true then
			return string.format("%s '%s' is equipped but not owned", kind, tostring(id))
		end
	end
	return nil
end

local function parseCoins(v: any): number
	if not isInt(v) or v < 0 or v > InventoryService.COINS_MAX then
		error("coins must be an integer in 0.." .. InventoryService.COINS_MAX .. " (got " .. tostring(v) .. ")")
	end
	return v
end

local function parseLoadout(v: any): Loadout
	local problem = loadoutProblem(v)
	if problem then
		error(problem)
	end
	return v
end

-- ---------------------------------------------------------------- construction
-- The empty profile: SaveData's opts.defaults for this service's four fields.
function InventoryService.defaults(): { [string]: any }
	local S = GameData.STARTER
	return {
		box = TackleBox.serialize(TackleBox.new()),
		coins = 0,
		loadout = {
			rod = S.rod, line = S.line, hook = S.hook, lure = S.lure,
			owned = { lure = { [S.lure] = true }, rod = { [S.rod] = true }, line = { [S.line] = true }, hook = { [S.hook] = true } },
		},
		catchLog = CatchLog.serialize(CatchLog.new()),
	}
end

function InventoryService.new(deps: Deps): InventoryService
	assert(typeof(deps) == "table" and typeof(deps.net) == "table" and typeof(deps.net.send) == "function", "InventoryService.new: deps.net.send is required")
	local self: Fields = {
		_saveData = deps.saveData,
		_net = deps.net,
		_schema = deps.schema or NetSchemaV3,
		_clock = deps.clock or function(): number
			return 0
		end,
		_warn = deps.warn or function() end,
		_rng = deps.rng,
		_recs = {},
		_stats = { handled = {}, rejected = {}, sent = {}, sendRefused = 0 },
	}
	return setmetatable(self, InventoryService)
end

-- ---------------------------------------------------------------- sends and counters
-- Validates an S2C payload against the schema, then sends it; a refused payload is warned and counted.
function InventoryService._send(self: InventoryService, player: any, name: string, payload: { [string]: any }): boolean
	local ok, why = self._schema.validate(name, payload)
	if not ok then
		self._stats.sendRefused += 1
		self._warn(string.format("InventoryService: %s to %s refused by the schema, not sent: %s", name, tostring(player.Name), tostring(why)))
		return false
	end
	self._stats.sent[name] = (self._stats.sent[name] or 0) + 1
	self._net.send(player, name, payload)
	return true
end

function InventoryService._reject(self: InventoryService, rec: Rec?, player: any, name: string, code: number?)
	self._stats.rejected[name] = (self._stats.rejected[name] or 0) + 1
	local rule = REJECT[name]
	if code == nil or rule == nil then
		return
	end
	local coins = if rec then rec.coins else 0
	if rule.reply == "TackleMoveResult" then
		self:_send(player, "TackleMoveResult", { ok = false, reason = code })
	elseif rule.reply == "SellResult" then
		self:_send(player, "SellResult", { reason = code, total = 0, coins = coins, lines = {} })
	else
		self:_send(player, "BuyResult", { op = rule.op, ok = false, reason = code, coins = coins })
	end
end

-- The gate every handler runs first: schema, then profile loaded and state allowed. Returns the record
-- when the request may proceed (and counts it handled), else nil plus the code that was sent (nil = dropped).
function InventoryService._gate(self: InventoryService, name: string, player: any, payload: any, state: string): (Rec?, number?)
	local rule = REJECT[name]
	local rec = self._recs[player.UserId]
	local ok, why = self._schema.validate(name, payload)
	if not ok then
		local field = fieldOf(tostring(why))
		local code = (if field then rule.byField[field] else nil) or rule.default
		self:_reject(rec, player, name, code)
		return nil, code
	end
	if rec == nil or not self._schema.allowed(name, state) then
		self:_reject(rec, player, name, rule.wrongState)
		return nil, rule.wrongState
	end
	self._stats.handled[name] = (self._stats.handled[name] or 0) + 1
	return rec, nil
end

function InventoryService._commitBox(self: InventoryService, rec: Rec)
	rec.profile:set("box", TackleBox.serialize(rec.box))
end

function InventoryService._commitLoadout(self: InventoryService, rec: Rec)
	rec.profile:set("loadout", rec.loadout)
end

function InventoryService._setCoins(self: InventoryService, rec: Rec, coins: number)
	rec.coins = coins
	rec.profile:set("coins", coins)
end

function InventoryService._syncBox(self: InventoryService, rec: Rec)
	local s = TackleBox.serialize(rec.box)
	self:_send(rec.player, "TackleSync", { w = s.w, h = s.h, nextId = s.nextId, items = s.items })
end

function InventoryService._syncLog(self: InventoryService, rec: Rec)
	self:_send(rec.player, "CatchLogSync", { log = CatchLog.serialize(rec.log) })
end

-- After the box changed: retry the held fish, write the box back, sync. Returns 7 while a fish is still
-- held, else 0; with announce, a fish placed here is announced with TackleMoveResult { true, 0 }.
function InventoryService._afterBoxChange(self: InventoryService, rec: Rec, announce: boolean): number
	local code = MOVE_OK
	local held = rec.held
	if held then
		if TackleBox.autoPlace(rec.box, held.item) then
			rec.held = nil
			if announce then
				self:_send(rec.player, "TackleMoveResult", { ok = true, reason = MOVE_OK })
			end
		else
			code = MOVE_NO_ROOM
		end
	end
	self:_commitBox(rec)
	self:_syncBox(rec)
	return code
end

-- ---------------------------------------------------------------- profile lifecycle
-- Restores one profile field through `parse` inside pcall; a failure warns, stashes the bytes under
-- data.corrupt.<field> and returns `empty()`.
function InventoryService._restore(self: InventoryService, prof: SaveData.Profile, field: string, parse: (any) -> any, empty: () -> any): any
	local raw = prof.data[field]
	local ok, v = pcall(parse, raw)
	if ok then
		return v
	end
	self._warn(string.format("InventoryService: %s %s is corrupt, playing with an empty one: %s", prof.key, field, tostring(v)))
	pcall(function()
		prof:set("corrupt." .. field, raw)
	end)
	return empty()
end

-- After SaveData.load: builds the runtime record and sends ProfileReady, TackleSync, CatchLogSync.
-- `reason` is load's second return ("new" | "loaded" | ...); a read-only profile carries its own.
function InventoryService.onProfileLoaded(self: InventoryService, player: any, profile: SaveData.Profile?, reason: string?): boolean
	local prof = profile or (if self._saveData then self._saveData:getProfile(player) else nil)
	if prof == nil then
		error("InventoryService.onProfileLoaded: no profile for " .. tostring(player.Name))
	end
	local userId: number = player.UserId
	if self._recs[userId] then
		self._warn("InventoryService: profile already loaded for " .. tostring(player.Name) .. "; keeping the first")
		return false
	end
	local d = InventoryService.defaults()
	local rec: Rec = {
		player = player,
		userId = userId,
		profile = prof,
		box = self:_restore(prof, "box", TackleBox.deserialize, function(): TackleBox.Box
			return TackleBox.new()
		end),
		log = self:_restore(prof, "catchLog", CatchLog.deserialize, CatchLog.new),
		coins = self:_restore(prof, "coins", parseCoins, function(): number
			return 0
		end),
		loadout = self:_restore(prof, "loadout", parseLoadout, function(): Loadout
			return d.loadout
		end),
		held = nil,
	}
	self._recs[userId] = rec
	local why = if prof.readOnly then (prof.reason or "corrupt") else (reason or "loaded")
	local code = READY_CODE[why]
	if code == nil or prof.readOnly ~= (code >= 3) then
		code = if prof.readOnly then READY_CODE.corrupt else READY_CODE.loaded
	end
	self:_send(player, "ProfileReady", { readOnly = prof.readOnly, reason = code })
	self:_syncBox(rec)
	self:_syncLog(rec)
	return true
end

-- PlayerRemoving (after SaveData.onPlayerRemoving): drops the runtime record; a held fish is let go.
function InventoryService.onProfileReleased(self: InventoryService, player: any): boolean
	local rec = self._recs[player.UserId]
	if rec == nil then
		return false
	end
	self._recs[player.UserId] = nil
	return true
end

-- ---------------------------------------------------------------- handlers
function InventoryService.handleTackleMove(self: InventoryService, player: any, payload: any, state: string): (boolean, number?)
	local rec, gateCode = self:_gate("TackleMove", player, payload, state)
	if rec == nil then
		return false, gateCode
	end
	local ok, why = TackleBox.move(rec.box, payload.id, payload.rot, payload.x, payload.y)
	if not ok then
		local code = MOVE_CODE[why :: string] or MOVE_BAD_POSITION
		self:_send(player, "TackleMoveResult", { ok = false, reason = code })
		return false, code
	end
	local code = self:_afterBoxChange(rec, false)
	self:_send(player, "TackleMoveResult", { ok = true, reason = code })
	return true, code
end

function InventoryService.handleTackleDrop(self: InventoryService, player: any, payload: any, state: string): (boolean, number?)
	local rec, gateCode = self:_gate("TackleDrop", player, payload, state)
	if rec == nil then
		return false, gateCode
	end
	local item = TackleBox.remove(rec.box, payload.id)
	if item == nil then
		self:_send(player, "TackleMoveResult", { ok = false, reason = MOVE_NO_ITEM })
		return false, MOVE_NO_ITEM
	end
	local code = self:_afterBoxChange(rec, false)
	self:_send(player, "TackleMoveResult", { ok = true, reason = code })
	return true, code
end

function InventoryService._sellRefuse(self: InventoryService, player: any, coins: number, code: number): (boolean, number?)
	self:_send(player, "SellResult", { reason = code, total = 0, coins = coins, lines = {} })
	return false, code
end

function InventoryService.handleSell(self: InventoryService, player: any, payload: any, state: string): (boolean, number?)
	local rec, gateCode = self:_gate("Sell", player, payload, state)
	if rec == nil then
		return false, gateCode
	end
	if rec.profile.readOnly then
		return self:_sellRefuse(player, rec.coins, SELL_READ_ONLY)
	end
	local ids: { number } = payload.ids
	if #ids == 0 then
		return self:_sellRefuse(player, rec.coins, SELL_NOTHING)
	end
	-- every id must be a fish the player holds, once; nothing is sold until all of them pass
	local seen: { [number]: boolean } = {}
	local catches: { GameData.Catch } = {}
	for _, id in ids do
		local p = rec.box.placed[id]
		if p == nil or seen[id] then
			return self:_sellRefuse(player, rec.coins, SELL_NO_ITEM)
		end
		seen[id] = true
		local d: any = p.item.data
		if p.item.kind ~= "fish" or typeof(d) ~= "table" or typeof(d.speciesId) ~= "string" or SpeciesTable.ROWS[d.speciesId] == nil or not isPos(d.lengthM) or not isPos(d.weightKg) then
			return self:_sellRefuse(player, rec.coins, SELL_NOT_FISH)
		end
		table.insert(catches, { speciesId = d.speciesId, lengthM = d.lengthM, weightKg = d.weightKg })
	end
	local total, lines = GameData.sellTotal(catches)
	for _, id in ids do
		TackleBox.remove(rec.box, id)
	end
	self:_setCoins(rec, math.min(rec.coins + total, InventoryService.COINS_MAX))
	local out: { { [string]: any } } = {}
	for i, l in lines do
		out[i] = { speciesId = l.speciesId, lengthM = l.lengthM, weightKg = l.weightKg, coins = l.coins }
	end
	self:_send(player, "SellResult", { reason = SELL_OK, total = total, coins = rec.coins, lines = out })
	self:_afterBoxChange(rec, true)
	return true, SELL_OK
end

function InventoryService._buyRefuse(self: InventoryService, player: any, op: number, coins: number, code: number): (boolean, number?)
	self:_send(player, "BuyResult", { op = op, ok = false, reason = code, coins = coins })
	return false, code
end

function InventoryService.handleBuyGear(self: InventoryService, player: any, payload: any, state: string): (boolean, number?)
	local rec, gateCode = self:_gate("BuyGear", player, payload, state)
	if rec == nil then
		return false, gateCode
	end
	if rec.profile.readOnly then
		return self:_buyRefuse(player, OP_BUY, rec.coins, BUY_READ_ONLY)
	end
	local kind = KIND_OF[payload.kind]
	local id: string = payload.id
	local entry = lookup(kind, id)
	if entry == nil then
		return self:_buyRefuse(player, OP_BUY, rec.coins, BUY_UNKNOWN)
	end
	if rec.loadout.owned[kind][id] then
		return self:_buyRefuse(player, OP_BUY, rec.coins, BUY_OWNED)
	end
	local price: number
	if kind == "lure" then
		price = entry.price
	else
		-- gear is bought one tier up from what is equipped, at the price difference (the note, 6.4)
		local equippedId: string = (rec.loadout :: any)[kind]
		local equipped = lookup(kind, equippedId)
		if entry.tier <= equipped.tier then
			return self:_buyRefuse(player, OP_BUY, rec.coins, BUY_NOT_UPGRADE)
		end
		price = GameData.upgradeCost(kind, equippedId, id)
	end
	if rec.coins < price then
		return self:_buyRefuse(player, OP_BUY, rec.coins, BUY_NO_COINS)
	end
	rec.loadout.owned[kind][id] = true
	self:_setCoins(rec, rec.coins - price)
	self:_commitLoadout(rec)
	self:_send(player, "BuyResult", { op = OP_BUY, ok = true, reason = BUY_OK, coins = rec.coins })
	return true, BUY_OK
end

function InventoryService.handleEquip(self: InventoryService, player: any, payload: any, state: string): (boolean, number?)
	local rec, gateCode = self:_gate("Equip", player, payload, state)
	if rec == nil then
		return false, gateCode
	end
	if rec.profile.readOnly then
		return self:_buyRefuse(player, OP_EQUIP, rec.coins, BUY_READ_ONLY)
	end
	local kind = KIND_OF[payload.kind]
	local id: string = payload.id
	if lookup(kind, id) == nil then
		return self:_buyRefuse(player, OP_EQUIP, rec.coins, BUY_UNKNOWN)
	end
	if not rec.loadout.owned[kind][id] then
		return self:_buyRefuse(player, OP_EQUIP, rec.coins, BUY_NOT_OWNED)
	end
	(rec.loadout :: any)[kind] = id
	self:_commitLoadout(rec)
	self:_send(player, "BuyResult", { op = OP_EQUIP, ok = true, reason = BUY_OK, coins = rec.coins })
	return true, BUY_OK
end

-- Routes a C2S message name to its handler; an unknown name is counted as rejected and dropped.
function InventoryService.dispatch(self: InventoryService, name: string, player: any, payload: any, state: string): (boolean, number?)
	local method = HANDLER[name]
	if method == nil then
		local key = tostring(name)
		self._stats.rejected[key] = (self._stats.rejected[key] or 0) + 1
		return false, nil
	end
	return (self :: any)[method](self, player, payload, state)
end

-- ---------------------------------------------------------------- the catch
-- CatchScene entry: records the catch, sizes the fish and places it; on no room the player holds it.
-- Returns the result, or nil plus "no profile" | "holding" (a second catch while one is still held).
function InventoryService.onCatch(self: InventoryService, player: any, catch: CatchLog.Catch): (CatchResult?, string?)
	local rec = self._recs[player.UserId]
	if rec == nil then
		return nil, "no profile"
	end
	if rec.held then
		return nil, "holding"
	end
	local _, shapeName = SpeciesTable.sizeClass(catch.speciesId, catch.lengthM)
	local flags = CatchLog.record(rec.log, catch)
	rec.profile:set("catchLog", CatchLog.serialize(rec.log))
	local item: TackleBox.Item = {
		kind = "fish",
		key = catch.speciesId,
		shape = TackleBox.SHAPES[shapeName],
		data = { speciesId = catch.speciesId, lengthM = catch.lengthM, weightKg = catch.weightKg },
	}
	local id = TackleBox.autoPlace(rec.box, item)
	self:_syncLog(rec)
	if id then
		self:_commitBox(rec)
		self:_syncBox(rec)
		return { placed = true, id = id, makeRoom = false, flags = flags }, nil
	end
	rec.held = { item = item, sinceT = self._clock() }
	self:_syncBox(rec)
	self:_send(player, "TackleMoveResult", { ok = false, reason = MOVE_NO_ROOM })
	return { placed = false, id = nil, makeRoom = true, flags = flags }, nil
end

-- Lets a held fish go (make-room abandoned); true when one was held.
function InventoryService.cancelMakeRoom(self: InventoryService, player: any): boolean
	local rec = self._recs[player.UserId]
	if rec == nil or rec.held == nil then
		return false
	end
	rec.held = nil
	self:_send(player, "TackleMoveResult", { ok = true, reason = MOVE_OK })
	return true
end

-- ---------------------------------------------------------------- reads
function InventoryService.has(self: InventoryService, player: any): boolean
	return self._recs[player.UserId] ~= nil
end

function InventoryService.isMakeRoom(self: InventoryService, player: any): boolean
	local rec = self._recs[player.UserId]
	return rec ~= nil and rec.held ~= nil
end

-- The held fish item, or nil.
function InventoryService.heldFish(self: InventoryService, player: any): TackleBox.Item?
	local rec = self._recs[player.UserId]
	return if rec and rec.held then rec.held.item else nil
end

-- When the held fish was first held (deps.clock), or nil.
function InventoryService.heldSinceT(self: InventoryService, player: any): number?
	local rec = self._recs[player.UserId]
	return if rec and rec.held then rec.held.sinceT else nil
end

-- The live box (server-owned; callers read, never mutate without a sync), or nil.
function InventoryService.box(self: InventoryService, player: any): TackleBox.Box?
	local rec = self._recs[player.UserId]
	return if rec then rec.box else nil
end

function InventoryService.log(self: InventoryService, player: any): CatchLog.Log?
	local rec = self._recs[player.UserId]
	return if rec then rec.log else nil
end

function InventoryService.coins(self: InventoryService, player: any): number?
	local rec = self._recs[player.UserId]
	return if rec then rec.coins else nil
end

function InventoryService.loadout(self: InventoryService, player: any): Loadout?
	local rec = self._recs[player.UserId]
	return if rec then rec.loadout else nil
end

-- Counters: handled and rejected per C2S message, sent per S2C message, sendRefused.
function InventoryService.stats(self: InventoryService): Stats
	return {
		handled = table.clone(self._stats.handled),
		rejected = table.clone(self._stats.rejected),
		sent = table.clone(self._stats.sent),
		sendRefused = self._stats.sendRefused,
	}
end

return InventoryService
