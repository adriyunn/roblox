--!strict
-- SpeciesTable (About Fishing F1, WS-S species data; Cloud, 2026-10-06; design/WSS_species.md not yet written)
-- Data-driven species rows: length law, weight law, tackle-box size classes, fish-brain overrides,
-- fight numbers, spawn rules (depth, time of day, zones), lure multipliers and price per kg; plus the
-- small pure functions that read them (rollLength, weightFor, sizeClass, brainConfig, spawnWeight).
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * FishPool (spawn): pick a species with spawnWeight(id, timeOfDay, FishZones.depthAt(pos)) as the
--     weight, then rollLength(id, rng) with the pool's Random, weightFor(id, L) for the record.
--   * FishBrain: build the per-fish config with brainConfig(FishingConfig.AF.Fish, id). The override
--     keys are the F1 names as this author remembers them (NoticeRangeM, HoverMinS, HoverMaxS,
--     ChargeSpeedMps, CooldownMinS, CooldownMaxS); check them against the real C.AF.Fish block and fix
--     BRAIN_KEYS. brainConfig errors on a key the base does not have, so a mismatch shows up at once.
--   * FishingServer (catch): sizeClass(id, L) gives the TackleBox.SHAPES name for the fish item.
--   * TroutFight: the `fight` block is where a per-species fight would read from (F1 only has trout).
-- Only trout is tuned: its base config IS the F1 fish, so its brain overrides are empty. Every other
-- number is UNTUNED (marked per row): real-world sizes and weights, placeholder behaviour values.
-- No Roblox globals.

local TackleBox = require("./TackleBox")

local SpeciesTable = {}

export type Rng = { NextNumber: (self: Rng, a: number?, b: number?) -> number, NextInteger: (self: Rng, a: number, b: number) -> number }
export type SizeClass = { maxM: number, class: string, shape: string }
export type Row = {
	name: string,
	lengthM: { min: number, max: number, median: number },
	weightA: number, -- weight(kg) = weightA * lengthM ^ weightB
	weightB: number,
	sizeClasses: { SizeClass }, -- ascending maxM, last >= lengthM.max
	brain: { [string]: number }, -- overrides merged over the base fish config
	fight: { strengthN: number, runChance: number, runSpeedMps: number, tireS: number },
	spawn: { depthM: { min: number, max: number }, timeWeights: { [string]: number }, zones: { string } | string },
	lures: { [string]: number }, -- lureId -> multiplier, with `default`
	pricePerKg: number,
	tuned: boolean,
}

-- The fish-brain keys a row may override (placeholders for the real C.AF.Fish names).
SpeciesTable.BRAIN_KEYS = { "NoticeRangeM", "HoverMinS", "HoverMaxS", "ChargeSpeedMps", "CooldownMinS", "CooldownMaxS" }
local BRAIN_KEY_SET: { [string]: boolean } = {}
for _, k in SpeciesTable.BRAIN_KEYS do
	BRAIN_KEY_SET[k] = true
end

local PERIODS = { "dawn", "day", "dusk", "night" }
local BOUNDARIES = { 5, 8, 17, 20 } -- dawn 5-8, day 8-17, dusk 17-20, night otherwise
SpeciesTable.BLEND_H = 0.5 -- linear blend this many hours either side of each boundary
SpeciesTable.SIGMAS = 5 -- min..max spans this many sigma of the log-normal (2.5 each side)

SpeciesTable.ROWS = {
	-- TUNED: the F1 fish is a 0.40 m trout; the base fish config is this species, so no overrides.
	trout = {
		name = "Trout",
		lengthM = { min = 0.25, max = 0.55, median = 0.40 },
		weightA = 11.0, -- 0.40 m -> 0.704 kg, 0.55 m -> 1.83 kg (brown trout condition)
		weightB = 3.0,
		sizeClasses = {
			{ maxM = 0.32, class = "small", shape = "line1" },
			{ maxM = 0.46, class = "medium", shape = "line2" },
			{ maxM = 0.55, class = "large", shape = "line3" },
		},
		brain = {},
		fight = { strengthN = 12, runChance = 0.35, runSpeedMps = 2.5, tireS = 20 },
		spawn = { depthM = { min = 0.3, max = 3.0 }, timeWeights = { dawn = 1.0, day = 0.6, dusk = 1.0, night = 0.3 }, zones = "*" },
		lures = { default = 1, spinner = 1.3, fly = 1.5, worm = 1.1 },
		pricePerKg = 11, -- GameData calibration: four median trout = 32 coins
		tuned = true,
	},
	-- UNTUNED placeholders below: real-world lengths and weights, guessed behaviour and prices.
	perch = {
		name = "Perch",
		lengthM = { min = 0.12, max = 0.40, median = 0.22 },
		weightA = 14.0, -- 0.22 m -> 0.149 kg, 0.40 m -> 0.90 kg
		weightB = 3.0,
		sizeClasses = {
			{ maxM = 0.18, class = "small", shape = "line1" },
			{ maxM = 0.30, class = "medium", shape = "line2" },
			{ maxM = 0.40, class = "large", shape = "L3" },
		},
		brain = { NoticeRangeM = 2.5, HoverMinS = 0.8, HoverMaxS = 1.6, ChargeSpeedMps = 2.0 }, -- UNTUNED
		fight = { strengthN = 6, runChance = 0.2, runSpeedMps = 1.5, tireS = 10 }, -- UNTUNED
		spawn = { depthM = { min = 0.5, max = 4.0 }, timeWeights = { dawn = 0.8, day = 0.7, dusk = 0.9, night = 0.2 }, zones = "*" },
		lures = { default = 1, worm = 1.3, jig = 1.4, spinner = 1.1 },
		pricePerKg = 9,
		tuned = false,
	},
	pike = {
		name = "Pike",
		lengthM = { min = 0.40, max = 1.20, median = 0.65 },
		weightA = 7.3, -- 0.65 m -> 2.0 kg, 1.20 m -> 12.6 kg
		weightB = 3.0,
		sizeClasses = {
			{ maxM = 0.55, class = "small", shape = "line2" },
			{ maxM = 0.85, class = "medium", shape = "line3" },
			{ maxM = 1.20, class = "large", shape = "line4" },
		},
		brain = { NoticeRangeM = 4.0, HoverMinS = 1.5, HoverMaxS = 3.0, ChargeSpeedMps = 4.5 }, -- UNTUNED
		fight = { strengthN = 35, runChance = 0.6, runSpeedMps = 4.0, tireS = 45 }, -- UNTUNED
		spawn = { depthM = { min = 0.8, max = 6.0 }, timeWeights = { dawn = 1.0, day = 0.4, dusk = 1.0, night = 0.5 }, zones = { "reeds", "deep" } },
		lures = { default = 0.6, spoon = 1.5, spinner = 1.2, jig = 1.0 },
		pricePerKg = 8,
		tuned = false,
	},
	carp = {
		name = "Carp",
		lengthM = { min = 0.30, max = 0.90, median = 0.55 },
		weightA = 18.0, -- 0.55 m -> 3.0 kg, 0.90 m -> 13.1 kg
		weightB = 3.0,
		sizeClasses = {
			{ maxM = 0.40, class = "small", shape = "line2" },
			{ maxM = 0.65, class = "medium", shape = "rect2x2" },
			{ maxM = 0.90, class = "large", shape = "rect2x3" },
		},
		brain = { NoticeRangeM = 2.0, HoverMinS = 2.0, HoverMaxS = 4.0, ChargeSpeedMps = 1.2, CooldownMinS = 5, CooldownMaxS = 8 }, -- UNTUNED
		fight = { strengthN = 30, runChance = 0.5, runSpeedMps = 2.0, tireS = 60 }, -- UNTUNED
		spawn = { depthM = { min = 0.5, max = 5.0 }, timeWeights = { dawn = 0.9, day = 0.5, dusk = 0.9, night = 0.8 }, zones = { "lily", "deep" } },
		lures = { default = 0.5, boilie = 1.6, worm = 1.2 },
		pricePerKg = 6,
		tuned = false,
	},
	minnow = {
		name = "Minnow",
		lengthM = { min = 0.04, max = 0.10, median = 0.06 },
		weightA = 9.3, -- 0.06 m -> 0.002 kg
		weightB = 3.0,
		sizeClasses = {
			{ maxM = 0.07, class = "small", shape = "line1" },
			{ maxM = 0.09, class = "medium", shape = "line1" },
			{ maxM = 0.10, class = "large", shape = "line1" },
		},
		brain = { NoticeRangeM = 1.0, HoverMinS = 0.3, HoverMaxS = 0.7, ChargeSpeedMps = 1.0, CooldownMinS = 2, CooldownMaxS = 3 }, -- UNTUNED
		fight = { strengthN = 0.5, runChance = 0.05, runSpeedMps = 0.5, tireS = 2 }, -- UNTUNED
		spawn = { depthM = { min = 0.1, max = 1.0 }, timeWeights = { dawn = 0.7, day = 1.0, dusk = 0.7, night = 0.2 }, zones = { "shallows" } },
		lures = { default = 1, fly = 1.2 },
		pricePerKg = 20, -- so tiny that GameData's minimum of 1 coin applies
		tuned = false,
	},
} :: { [string]: Row }

-- ---------------------------------------------------------------- lookups
-- The row for a species id; errors naming the id when unknown.
function SpeciesTable.get(id: string): Row
	local row = SpeciesTable.ROWS[id]
	if not row then
		error("SpeciesTable.get: unknown species '" .. tostring(id) .. "'")
	end
	return row
end

-- All species ids, sorted.
function SpeciesTable.ids(): { string }
	local out = {}
	for id in SpeciesTable.ROWS do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

-- A length in metres: bounded log-normal around the median (Box-Muller from two rng draws), clamped.
-- The median is not the geometric centre of min..max, so each side gets its own sigma: min and max
-- both sit SIGMAS/2 sigma from the median (one sigma for the whole span put trout's max 2.0 sigma out
-- and clamped 2.2% of all trout to exactly 0.55 m).
function SpeciesTable.rollLength(id: string, rng: Rng): number
	local L = SpeciesTable.get(id).lengthM
	local half = SpeciesTable.SIGMAS / 2
	local u1 = math.max(rng:NextNumber(), 1e-12)
	local u2 = rng:NextNumber()
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	local sigma = if z >= 0 then (math.log(L.max) - math.log(L.median)) / half else (math.log(L.median) - math.log(L.min)) / half
	return math.clamp(L.median * math.exp(sigma * z), L.min, L.max)
end

-- Weight in kg for a length: weightA * L ^ weightB.
function SpeciesTable.weightFor(id: string, lengthM: number): number
	local row = SpeciesTable.get(id)
	return row.weightA * lengthM ^ row.weightB
end

-- Size class and TackleBox shape name for a length (first class whose maxM >= length; last one above max).
function SpeciesTable.sizeClass(id: string, lengthM: number): (string, string)
	local classes = SpeciesTable.get(id).sizeClasses
	for _, sc in classes do
		if lengthM <= sc.maxM then
			return sc.class, sc.shape
		end
	end
	local last = classes[#classes]
	return last.class, last.shape
end

-- A copy of the base fish config with the species' overrides applied; errors on a key the base lacks.
function SpeciesTable.brainConfig(base: { [string]: any }, id: string): { [string]: any }
	local out = table.clone(base)
	for k, v in SpeciesTable.get(id).brain do
		if base[k] == nil then
			error(string.format("SpeciesTable.brainConfig: unknown override key '%s' for '%s'", k, id))
		end
		out[k] = v
	end
	return out
end

local function periodAt(t: number): string
	if t < BOUNDARIES[1] or t >= BOUNDARIES[4] then
		return "night"
	elseif t < BOUNDARIES[2] then
		return "dawn"
	elseif t < BOUNDARIES[3] then
		return "day"
	end
	return "dusk"
end

-- Spawn weight 0..1 for a time of day (hours, 0..24, wraps) and depth; 0 outside the depth range.
function SpeciesTable.spawnWeight(id: string, timeOfDay: number, depthM: number): number
	local row = SpeciesTable.get(id)
	if depthM < row.spawn.depthM.min or depthM > row.spawn.depthM.max then
		return 0
	end
	local t = timeOfDay % 24
	local w = row.spawn.timeWeights
	local blend = SpeciesTable.BLEND_H
	for _, b in BOUNDARIES do
		if math.abs(t - b) <= blend then
			local f = (t - (b - blend)) / (2 * blend)
			local before, after = w[periodAt(b - blend - 1e-9)], w[periodAt(b + blend)]
			return math.clamp((1 - f) * before + f * after, 0, 1)
		end
	end
	return math.clamp(w[periodAt(t)], 0, 1)
end

-- Catch multiplier for a lure id, falling back to the row's `default`.
function SpeciesTable.lureMultiplier(id: string, lureId: string): number
	local lures = SpeciesTable.get(id).lures
	local m = lures[lureId]
	if m == nil then
		return lures.default
	end
	return m
end

-- ---------------------------------------------------------------- validation
local function isNum(v: any): boolean
	return typeof(v) == "number" and v == v and math.abs(v) < math.huge
end

-- Checks every row (or the given rows table); errors naming the row and field. Returns true.
function SpeciesTable.validate(rows: { [string]: Row }?): boolean
	local all = rows or SpeciesTable.ROWS
	local function fail(id: string, field: string, why: string)
		error(string.format("SpeciesTable.validate: %s.%s: %s", id, field, why))
	end
	for id, row in all do
		if typeof(row.name) ~= "string" or row.name == "" then
			fail(id, "name", "must be a non-empty string")
		end
		local L = row.lengthM
		if not (isNum(L.min) and isNum(L.median) and isNum(L.max)) or not (0 < L.min and L.min < L.median and L.median < L.max) then
			fail(id, "lengthM", "needs 0 < min < median < max")
		end
		if not isNum(row.weightA) or row.weightA <= 0 then
			fail(id, "weightA", "must be > 0")
		end
		if not isNum(row.weightB) or row.weightB <= 0 then
			fail(id, "weightB", "must be > 0")
		end
		if typeof(row.sizeClasses) ~= "table" or #row.sizeClasses == 0 then
			fail(id, "sizeClasses", "must be a non-empty array")
		end
		local prev = 0
		for i, sc in row.sizeClasses do
			if not isNum(sc.maxM) or sc.maxM <= prev then
				fail(id, "sizeClasses[" .. i .. "].maxM", "must ascend")
			end
			prev = sc.maxM
			if sc.class ~= "small" and sc.class ~= "medium" and sc.class ~= "large" then
				fail(id, "sizeClasses[" .. i .. "].class", "must be small|medium|large")
			end
			if TackleBox.SHAPES[sc.shape] == nil then
				fail(id, "sizeClasses[" .. i .. "].shape", "unknown TackleBox shape '" .. tostring(sc.shape) .. "'")
			end
		end
		if prev < L.max then
			fail(id, "sizeClasses", "last maxM must be >= lengthM.max")
		end
		for k, v in row.brain do
			if not BRAIN_KEY_SET[k] then
				fail(id, "brain." .. tostring(k), "not a fish config key")
			end
			if not isNum(v) then
				fail(id, "brain." .. k, "must be a number")
			end
		end
		for _, k in { "strengthN", "runSpeedMps", "tireS" } do
			if not isNum((row.fight :: any)[k]) or (row.fight :: any)[k] <= 0 then
				fail(id, "fight." .. k, "must be > 0")
			end
		end
		if not isNum(row.fight.runChance) or row.fight.runChance < 0 or row.fight.runChance > 1 then
			fail(id, "fight.runChance", "must be in 0..1")
		end
		local d = row.spawn.depthM
		if not (isNum(d.min) and isNum(d.max)) or d.min < 0 or d.max <= d.min then
			fail(id, "spawn.depthM", "needs 0 <= min < max")
		end
		for _, p in PERIODS do
			local tw = row.spawn.timeWeights[p]
			if not isNum(tw) or tw < 0 or tw > 1 then
				fail(id, "spawn.timeWeights." .. p, "must be in 0..1")
			end
		end
		local zones = row.spawn.zones
		if zones ~= "*" and (typeof(zones) ~= "table" or #zones == 0) then
			fail(id, "spawn.zones", "must be '*' or a non-empty array of zone ids")
		end
		if not isNum(row.lures.default) or row.lures.default < 0 then
			fail(id, "lures.default", "must be a number >= 0")
		end
		for lureId, m in row.lures do
			if not isNum(m) or m < 0 then
				fail(id, "lures." .. tostring(lureId), "must be a number >= 0")
			end
		end
		if not isNum(row.pricePerKg) or row.pricePerKg <= 0 then
			fail(id, "pricePerKg", "must be > 0")
		end
		if typeof(row.tuned) ~= "boolean" then
			fail(id, "tuned", "must be a boolean")
		end
	end
	return true
end

return SpeciesTable
