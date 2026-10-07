--!strict
-- CatchCard (About Fishing F1, WS-L catch record; Cloud, 2026-10-07; design/WSL_catchlog.md)
-- The data the catch card shows after a catch: species name, length and weight in the player's units,
-- size class, the "New species!" / "New record!" badges from CatchLog.record()'s result, the sell
-- price from GameData, the zone and lure names, and the ordered lines a renderer draws top to bottom.
-- Pure: strings in, strings out; CatchSceneView (Dev2) owns the Frames.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * FishingServer sends the catch {speciesId, lengthM, weightKg, zoneId, lureId} and CatchLog's
--     result {isFirst, isLengthRecord, isWeightRecord, countNow} over FishingNet at CatchScene entry;
--     CatchSceneView calls CatchCard.build(catch, result, opts) and draws card.lines.
--   * opts.units comes from the options panel ("metric" | "imperial"; design/WSH_options_panel_additions.md
--     would hold the row); opts.showPrice is off when the fish goes to the tackle box unsold.
--   * opts.zoneNames / opts.lureNames map ids to display names (FishZones, GameData.LURES); a missing
--     entry falls back to GameData.LURES[id].name for lures, then to the raw id.
-- Design decisions a dev must know:
--   * Imperial weight is pounds and whole ounces: total ounces = round(kg x 35.27396195), carried into
--     pounds at 16 ("1 lb 9 oz", "1 lb 0 oz", and under a pound just "11 oz"). Metric is "0.70 kg";
--     lengths are "40.0 cm" / "15.7 in". Rounding is floor(x + 0.5), never banker's.
--   * Badges keep badgeOrder. A first catch shows only "New species!" (CatchLog flags it as a length
--     and weight record too, which the badge would merely repeat); a repeat shows "New record!" for a
--     length record and "Heaviest yet!" for a weight record, both when both.
-- No Roblox globals.

local SpeciesTable = require("../Shared/SpeciesTable")
local GameData = require("../Shared/GameData")

local CatchCard = {}

export type Units = "metric" | "imperial"
export type Catch = { speciesId: string, lengthM: number, weightKg: number, zoneId: string, lureId: string }
export type Result = { isFirst: boolean, isLengthRecord: boolean, isWeightRecord: boolean, countNow: number } -- CatchLog.Result's shape
export type Opts = {
	units: Units?,
	showPrice: boolean?,
	zoneNames: { [string]: string }?,
	lureNames: { [string]: string }?,
}
export type Card = {
	title: string,
	lengthText: string,
	weightText: string,
	sizeClass: string, -- "small" | "medium" | "large" as SpeciesTable.sizeClass says it
	sizeText: string, -- the same, capitalised for display
	badges: { string },
	priceText: string?,
	zoneText: string,
	lureText: string,
	lines: { string },
}

CatchCard.badgeOrder = { "New species!", "New record!", "Heaviest yet!" }
CatchCard.BADGE_NEW_SPECIES = "New species!"
CatchCard.BADGE_LENGTH_RECORD = "New record!"
CatchCard.BADGE_WEIGHT_RECORD = "Heaviest yet!"

CatchCard.CM_PER_M = 100
CatchCard.IN_PER_M = 39.37007874
CatchCard.OZ_PER_KG = 35.27396195
CatchCard.OZ_PER_LB = 16

-- ---------------------------------------------------------------- helpers
local function isNum(v: any): boolean
	return typeof(v) == "number" and v == v and math.abs(v) < math.huge
end

local function round(v: number): number
	return math.floor(v + 0.5)
end

local function checkUnits(units: any): Units
	if units == "metric" or units == "imperial" then
		return units
	end
	error("CatchCard: units must be \"metric\" or \"imperial\", got " .. tostring(units))
end

local function capitalise(s: string): string
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- ---------------------------------------------------------------- formatting
-- A length in metres as "40.0 cm" or "15.7 in".
function CatchCard.formatLength(m: number, units: Units): string
	local u = checkUnits(units)
	if not isNum(m) or m < 0 then
		error("CatchCard.formatLength: lengthM must be a number >= 0, got " .. tostring(m))
	end
	if u == "metric" then
		return string.format("%.1f cm", m * CatchCard.CM_PER_M)
	end
	return string.format("%.1f in", m * CatchCard.IN_PER_M)
end

-- A weight in kg as "0.70 kg" or "1 lb 9 oz" (whole ounces, carried into pounds; "11 oz" under a pound).
function CatchCard.formatWeight(kg: number, units: Units): string
	local u = checkUnits(units)
	if not isNum(kg) or kg < 0 then
		error("CatchCard.formatWeight: weightKg must be a number >= 0, got " .. tostring(kg))
	end
	if u == "metric" then
		return string.format("%.2f kg", kg)
	end
	local oz = round(kg * CatchCard.OZ_PER_KG)
	local lb = math.floor(oz / CatchCard.OZ_PER_LB)
	oz -= lb * CatchCard.OZ_PER_LB
	if lb == 0 then
		return string.format("%d oz", oz)
	end
	return string.format("%d lb %d oz", lb, oz)
end

-- "8 coins" / "1 coin".
function CatchCard.formatCoins(coins: number): string
	if not isNum(coins) or coins < 0 or coins ~= math.floor(coins) then
		error("CatchCard.formatCoins: coins must be an integer >= 0, got " .. tostring(coins))
	end
	return string.format("%d %s", coins, if coins == 1 then "coin" else "coins")
end

-- The badges for a CatchLog result, in badgeOrder.
function CatchCard.badgesFor(result: Result): { string }
	if typeof(result) ~= "table" then
		error("CatchCard.badgesFor: result must be CatchLog.record()'s result table")
	end
	local first = result.isFirst == true
	local want: { [string]: boolean } = {
		[CatchCard.BADGE_NEW_SPECIES] = first,
		[CatchCard.BADGE_LENGTH_RECORD] = not first and result.isLengthRecord == true,
		[CatchCard.BADGE_WEIGHT_RECORD] = not first and result.isWeightRecord == true,
	}
	local out: { string } = {}
	for _, b in CatchCard.badgeOrder do
		if want[b] then
			table.insert(out, b)
		end
	end
	return out
end

-- ---------------------------------------------------------------- the card
-- Builds the card. Errors on an unknown species, a bad number or bad units.
function CatchCard.build(catch: Catch, result: Result, opts: Opts?): Card
	if typeof(catch) ~= "table" then
		error("CatchCard.build: catch must be a table")
	end
	local c: any = catch
	if typeof(c.speciesId) ~= "string" then
		error("CatchCard.build: catch.speciesId must be a string")
	end
	if not isNum(c.lengthM) or c.lengthM <= 0 then
		error("CatchCard.build: catch.lengthM must be > 0, got " .. tostring(c.lengthM))
	end
	if not isNum(c.weightKg) or c.weightKg <= 0 then
		error("CatchCard.build: catch.weightKg must be > 0, got " .. tostring(c.weightKg))
	end
	local speciesId: string, lengthM: number, weightKg: number = c.speciesId, c.lengthM, c.weightKg
	local zoneId = if typeof(c.zoneId) == "string" then c.zoneId else ""
	local lureId = if typeof(c.lureId) == "string" then c.lureId else ""
	local o: Opts = opts or {}
	local units = checkUnits(o.units or "metric")

	local row = SpeciesTable.get(speciesId) -- errors naming an unknown species
	local sizeClass = SpeciesTable.sizeClass(speciesId, lengthM)
	local badges = CatchCard.badgesFor(result)

	local priceText: string? = nil
	if o.showPrice == true then
		priceText = CatchCard.formatCoins(GameData.priceFor(speciesId, lengthM, weightKg))
	end

	local zoneNames = o.zoneNames
	local zoneText = if zoneNames ~= nil and zoneNames[zoneId] ~= nil then zoneNames[zoneId] else zoneId
	local lureNames = o.lureNames
	local lureText: string
	if lureNames ~= nil and lureNames[lureId] ~= nil then
		lureText = lureNames[lureId]
	elseif GameData.LURES[lureId] ~= nil then
		lureText = GameData.LURES[lureId].name
	else
		lureText = lureId
	end

	local card: Card = {
		title = row.name,
		lengthText = CatchCard.formatLength(lengthM, units),
		weightText = CatchCard.formatWeight(weightKg, units),
		sizeClass = sizeClass,
		sizeText = capitalise(sizeClass),
		badges = badges,
		priceText = priceText,
		zoneText = zoneText,
		lureText = lureText,
		lines = {},
	}
	local lines = card.lines
	table.insert(lines, card.title)
	for _, b in badges do
		table.insert(lines, b)
	end
	table.insert(lines, "Length: " .. card.lengthText)
	table.insert(lines, "Weight: " .. card.weightText)
	table.insert(lines, "Size: " .. card.sizeText)
	if zoneText ~= "" then
		table.insert(lines, "Zone: " .. zoneText)
	end
	if lureText ~= "" then
		table.insert(lines, "Lure: " .. lureText)
	end
	if priceText ~= nil then
		table.insert(lines, "Sells for " .. priceText)
	end
	return card
end

return CatchCard
