--!strict
-- GameData (About Fishing F1, WS-E economy data; Cloud, 2026-10-06; design/WSE_economy.md not yet written)
-- Lures, gear (rods, lines, hooks) and prices: the starter loadout, a fish's sell price from
-- SpeciesTable's price per kg and a size bonus, receipt totals, loadout multipliers, upgrade costs
-- and a validate() that cross-checks every id against SpeciesTable.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * Shop / sell (server side): sellTotal(catches) when the player sells; add `total` to the coins.
--   * CastFlight / InputController: multiply the cast range by castDistanceMul(loadout).
--   * FishJudge: multiply the Good press window by hookSetWindowMul(loadout).
--   * TroutFight: lineStrengthN(loadout) against the species' fight.strengthN is the snap check.
--   * SaveData: a loadout is {rod=, line=, hook=, lure=} of ids from GEAR / LURES; STARTER is the
--     default for a new player.
-- Calibration (the preview's "four fish is at least 30 bucks"): a median trout is 0.40 m ->
-- 11 * 0.40^3 = 0.704 kg -> 11 coins/kg * 0.704 * bonus 1.0 = 7.74 -> 8 coins; four = 32 coins.
-- A minimum trout (0.25 m, 0.172 kg, x0.6) sells for 1 coin, a maximum (0.55 m, 1.83 kg, x1.5) for 30.
-- Every other price is UNTUNED. No Roblox globals.

local SpeciesTable = require("./SpeciesTable")

local GameData = {}

export type Lure = { name: string, price: number, tags: { string } } -- tags = species ids it is sold for
export type Rod = { name: string, price: number, castDistanceMul: number, tier: number }
export type Line = { name: string, price: number, strengthN: number, castDistanceMul: number, tier: number }
export type Hook = { name: string, price: number, hookSetWindowMul: number, tier: number }
export type Gear = { rods: { [string]: Rod }, lines: { [string]: Line }, hooks: { [string]: Hook } }
export type Loadout = { rod: string, line: string, hook: string, lure: string }
export type Catch = { speciesId: string, lengthM: number, weightKg: number }
export type ReceiptLine = { speciesId: string, name: string, lengthM: number, weightKg: number, coins: number }
export type Data = { LURES: { [string]: Lure }, GEAR: Gear, STARTER: Loadout }

GameData.BONUS_MAX = 1.5 -- size bonus at the species' max length
GameData.BONUS_MIN = 0.6 -- size bonus at the species' min length

GameData.LURES = {
	worm = { name = "Worm", price = 2, tags = { "trout", "perch", "carp" } },
	spinner = { name = "Spinner", price = 10, tags = { "trout", "perch", "pike" } },
	fly = { name = "Dry Fly", price = 12, tags = { "trout", "minnow" } },
	spoon = { name = "Spoon", price = 18, tags = { "pike" } },
	jig = { name = "Jig", price = 8, tags = { "perch", "pike" } },
	boilie = { name = "Boilie", price = 6, tags = { "carp" } },
} :: { [string]: Lure }

GameData.GEAR = {
	rods = {
		rod_basic = { name = "Basic Rod", price = 0, castDistanceMul = 1.0, tier = 1 },
		rod_carbon = { name = "Carbon Rod", price = 60, castDistanceMul = 1.15, tier = 2 },
		rod_pro = { name = "Pro Rod", price = 180, castDistanceMul = 1.3, tier = 3 },
	},
	-- the reference's line upgrade adds cast distance as well as strength
	lines = {
		line_mono = { name = "Mono Line", price = 0, strengthN = 20, castDistanceMul = 1.0, tier = 1 },
		line_braid = { name = "Braid Line", price = 40, strengthN = 35, castDistanceMul = 1.1, tier = 2 },
		line_fluoro = { name = "Fluoro Line", price = 120, strengthN = 50, castDistanceMul = 1.2, tier = 3 },
	},
	hooks = {
		hook_basic = { name = "Basic Hook", price = 0, hookSetWindowMul = 1.0, tier = 1 },
		hook_sharp = { name = "Sharp Hook", price = 30, hookSetWindowMul = 1.2, tier = 2 },
		hook_wide = { name = "Wide Gape Hook", price = 90, hookSetWindowMul = 1.4, tier = 3 },
	},
} :: Gear

GameData.STARTER = { rod = "rod_basic", line = "line_mono", hook = "hook_basic", lure = "worm" } :: Loadout

local KIND_ALIAS: { [string]: string } = { rod = "rods", rods = "rods", line = "lines", lines = "lines", hook = "hooks", hooks = "hooks" }

local function isNum(v: any): boolean
	return typeof(v) == "number" and v == v and math.abs(v) < math.huge
end

-- A gear entry by kind ("rods"|"lines"|"hooks", singular accepted) and id; errors when unknown.
local function gearGet(gear: Gear, kind: string, id: string): any
	local k = KIND_ALIAS[kind]
	if not k then
		error("GameData: unknown gear kind '" .. tostring(kind) .. "'")
	end
	local entry = (gear :: any)[k][id]
	if not entry then
		error(string.format("GameData: unknown %s id '%s'", k, tostring(id)))
	end
	return entry
end

-- ---------------------------------------------------------------- prices
-- Size bonus: 1.0 at the species median, linear to BONUS_MAX at max and BONUS_MIN at min (clamped).
function GameData.sizeBonus(speciesId: string, lengthM: number): number
	local L = SpeciesTable.get(speciesId).lengthM
	if lengthM >= L.median then
		local f = math.clamp((lengthM - L.median) / (L.max - L.median), 0, 1)
		return 1 + (GameData.BONUS_MAX - 1) * f
	end
	local f = math.clamp((L.median - lengthM) / (L.median - L.min), 0, 1)
	return 1 - (1 - GameData.BONUS_MIN) * f
end

-- Sell price in whole coins: pricePerKg * weightKg * sizeBonus, rounded, never below 1. Errors on a
-- non-finite input and on a product that overflows to inf (a weight near 1e308), so an infinite coin
-- value never reaches a profile.
function GameData.priceFor(speciesId: string, lengthM: number, weightKg: number): number
	if not isNum(lengthM) or not isNum(weightKg) or lengthM < 0 or weightKg < 0 then
		error("GameData.priceFor: lengthM and weightKg must be numbers >= 0")
	end
	local row = SpeciesTable.get(speciesId)
	local coins = math.floor(row.pricePerKg * weightKg * GameData.sizeBonus(speciesId, lengthM) + 0.5)
	if not isNum(coins) then
		error(string.format("GameData.priceFor: the price of %s at %g kg overflows", speciesId, weightKg))
	end
	return math.max(1, coins)
end

-- Total coins and one receipt line per catch, in the order given.
function GameData.sellTotal(catches: { Catch }): (number, { ReceiptLine })
	local total = 0
	local lines: { ReceiptLine } = {}
	for i, c in catches do
		local coins = GameData.priceFor(c.speciesId, c.lengthM, c.weightKg)
		total += coins
		lines[i] = { speciesId = c.speciesId, name = SpeciesTable.get(c.speciesId).name, lengthM = c.lengthM, weightKg = c.weightKg, coins = coins }
	end
	return total, lines
end

-- ---------------------------------------------------------------- loadout
-- Cast distance multiplier of a loadout: rod mul x line mul.
function GameData.castDistanceMul(loadout: Loadout): number
	local rod: Rod = gearGet(GameData.GEAR, "rods", loadout.rod)
	local line: Line = gearGet(GameData.GEAR, "lines", loadout.line)
	return rod.castDistanceMul * line.castDistanceMul
end

-- Breaking strength of the loadout's line in newtons.
function GameData.lineStrengthN(loadout: Loadout): number
	local line: Line = gearGet(GameData.GEAR, "lines", loadout.line)
	return line.strengthN
end

-- Hook-set window multiplier of the loadout's hook.
function GameData.hookSetWindowMul(loadout: Loadout): number
	local hook: Hook = gearGet(GameData.GEAR, "hooks", loadout.hook)
	return hook.hookSetWindowMul
end

-- Coins to go from one gear item to a higher tier of the same kind (price difference, never negative).
function GameData.upgradeCost(kind: string, fromId: string, toId: string): number
	local from = gearGet(GameData.GEAR, kind, fromId)
	local to = gearGet(GameData.GEAR, kind, toId)
	if to.tier <= from.tier then
		error(string.format("GameData.upgradeCost: %s -> %s is not an upgrade (tier %d -> %d)", fromId, toId, from.tier, to.tier))
	end
	return math.max(0, to.price - from.price)
end

-- ---------------------------------------------------------------- validation
-- Checks LURES, GEAR and STARTER (or the given data) against each other and SpeciesTable. Returns true.
function GameData.validate(data: Data?): boolean
	local d: Data = data or { LURES = GameData.LURES, GEAR = GameData.GEAR, STARTER = GameData.STARTER }
	SpeciesTable.validate()
	local function fail(where: string, why: string)
		error(string.format("GameData.validate: %s: %s", where, why))
	end
	for id, lure in d.LURES do
		if typeof(lure.name) ~= "string" or lure.name == "" then
			fail("LURES." .. id .. ".name", "must be a non-empty string")
		end
		if not isNum(lure.price) or lure.price < 0 then
			fail("LURES." .. id .. ".price", "must be a number >= 0")
		end
		if typeof(lure.tags) ~= "table" then
			fail("LURES." .. id .. ".tags", "must be an array of species ids")
		end
		for _, tag in lure.tags do
			if SpeciesTable.ROWS[tag] == nil then
				fail("LURES." .. id .. ".tags", "unknown species '" .. tostring(tag) .. "'")
			end
		end
	end
	local numericFields: { [string]: { string } } = {
		rods = { "castDistanceMul" },
		lines = { "strengthN", "castDistanceMul" },
		hooks = { "hookSetWindowMul" },
	}
	for kind, fields in numericFields do
		local entries: { [string]: any } = (d.GEAR :: any)[kind]
		if typeof(entries) ~= "table" or next(entries) == nil then
			fail("GEAR." .. kind, "must be a non-empty table")
		end
		local byTier: { [number]: string } = {}
		local ids: { string } = {}
		for id, e in entries do
			local where = "GEAR." .. kind .. "." .. id
			if typeof(e.name) ~= "string" or e.name == "" then
				fail(where .. ".name", "must be a non-empty string")
			end
			if not isNum(e.price) or e.price < 0 then
				fail(where .. ".price", "must be a number >= 0")
			end
			if not isNum(e.tier) or e.tier < 1 or e.tier ~= math.floor(e.tier) then
				fail(where .. ".tier", "must be a positive integer")
			end
			local tier: number = e.tier
			local prev = byTier[tier]
			if prev then
				fail("GEAR." .. kind, string.format("tier %d used twice (%s, %s)", tier, prev, id))
			end
			byTier[tier] = id
			for _, f in fields do
				if not isNum(e[f]) or e[f] <= 0 then
					fail(where .. "." .. f, "must be > 0")
				end
			end
			table.insert(ids, id)
		end
		table.sort(ids, function(a: string, b: string): boolean
			return entries[a].tier < entries[b].tier
		end)
		for i = 2, #ids do
			local lower, upper = entries[ids[i - 1]], entries[ids[i]]
			if upper.price < lower.price then
				fail("GEAR." .. kind .. "." .. ids[i] .. ".price", string.format("%g is below lower tier %s's %g", upper.price, ids[i - 1], lower.price))
			end
		end
	end
	for _, slot in { "rod", "line", "hook" } do
		local id = (d.STARTER :: any)[slot]
		if typeof(id) ~= "string" or (d.GEAR :: any)[KIND_ALIAS[slot]][id] == nil then
			fail("STARTER." .. slot, "unknown id '" .. tostring(id) .. "'")
		end
	end
	if d.LURES[d.STARTER.lure] == nil then
		fail("STARTER.lure", "unknown lure '" .. tostring(d.STARTER.lure) .. "'")
	end
	for speciesId, row in SpeciesTable.ROWS do
		for lureId in row.lures do
			if lureId ~= "default" and d.LURES[lureId] == nil then
				fail("species " .. speciesId .. ".lures." .. lureId, "unknown lure '" .. lureId .. "'")
			end
		end
	end
	return true
end

return GameData
