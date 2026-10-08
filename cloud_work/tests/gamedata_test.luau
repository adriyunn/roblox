--!strict
-- gamedata_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves GameData: validate passes, priceFor at min / median / max and the linear size bonus between,
-- the "four median trout = about 30 coins" calibration, loadout multipliers, upgrade costs and their
-- errors, and negative controls (a lure tag naming no species, duplicate tiers, a price out of tier
-- order, a species lure that does not exist).
-- Run from this folder: luau gamedata_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("gamedata_test")
local GameData = require("../src/Fishing/Shared/GameData")
local SpeciesTable = require("../src/Fishing/Shared/SpeciesTable")

local function deepCopy(v: any): any
	if typeof(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function dataCopy(): any
	return deepCopy({ LURES = GameData.LURES, GEAR = GameData.GEAR, STARTER = GameData.STARTER })
end

-- the data itself
T.check(GameData.validate(), "validate() passes on the shipped data")
local S = GameData.STARTER
T.check(GameData.GEAR.rods[S.rod] ~= nil and GameData.GEAR.lines[S.line] ~= nil and GameData.GEAR.hooks[S.hook] ~= nil and GameData.LURES[S.lure] ~= nil, "the starter ids all exist")
T.check(GameData.GEAR.rods[S.rod].tier == 1 and GameData.GEAR.rods[S.rod].price == 0, "the starter rod is tier 1 and free")
local lureTagsOk, lureCount = true, 0
for _, lure in GameData.LURES do
	lureCount += 1
	for _, tag in lure.tags do
		lureTagsOk = lureTagsOk and SpeciesTable.ROWS[tag] ~= nil
	end
end
T.check(lureTagsOk and lureCount == 6, "all 6 lures tag real species")
local speciesLuresOk = true
for _, row in SpeciesTable.ROWS do
	for lureId in row.lures do
		speciesLuresOk = speciesLuresOk and (lureId == "default" or GameData.LURES[lureId] ~= nil)
	end
end
T.check(speciesLuresOk, "every species lure multiplier names a real lure")

-- priceFor: min / median / max and the linear bonus
local wMin, wMed, wMax = SpeciesTable.weightFor("trout", 0.25), SpeciesTable.weightFor("trout", 0.40), SpeciesTable.weightFor("trout", 0.55)
T.eq(GameData.priceFor("trout", 0.40, wMed), 8, "a median trout (0.704 kg) sells for 8 coins")
T.eq(GameData.priceFor("trout", 0.25, wMin), 1, "a minimum trout sells for 1 coin")
T.eq(GameData.priceFor("trout", 0.55, wMax), 30, "a maximum trout sells for 30 coins")
T.eq(GameData.sizeBonus("trout", 0.40), 1.0, "size bonus is 1.0 at the median")
T.eq(GameData.sizeBonus("trout", 0.55), 1.5, "size bonus is 1.5 at max")
T.eq(GameData.sizeBonus("trout", 0.25), 0.6, "size bonus is 0.6 at min")
T.eq(GameData.sizeBonus("trout", 0.475), 1.25, "size bonus is linear above the median (1.25 halfway)")
T.eq(GameData.sizeBonus("trout", 0.325), 0.8, "size bonus is linear below the median (0.8 halfway)")
T.eq(GameData.priceFor("trout", 0.475, 1.0), 14, "1 kg at 0.475 m: 11 x 1.25 = 13.75 -> 14")
T.eq(GameData.priceFor("trout", 0.325, 1.0), 9, "1 kg at 0.325 m: 11 x 0.8 = 8.8 -> 9")
T.eq(GameData.priceFor("trout", 0.70, 1.0), GameData.priceFor("trout", 0.55, 1.0), "a length above max is clamped to the max bonus")
T.eq(GameData.priceFor("minnow", 0.06, SpeciesTable.weightFor("minnow", 0.06)), 1, "a median minnow rounds to 0 but sells for the minimum 1")
T.throws(function() GameData.priceFor("salmon", 0.4, 1) end, "unknown species", "priceFor refuses an unknown species")
T.throws(function() GameData.priceFor("trout", 0.4, -1) end, "must be numbers >= 0", "priceFor refuses a negative weight")
T.throws(function() GameData.priceFor("trout", 0.4, 1e308) end, "overflows", "N3: a 1e308 kg weight errors at the call site (was: inf coins returned; an infinite weight was already refused)")
T.throws(function() GameData.priceFor("trout", 0 / 0, 1) end, "must be numbers >= 0", "M1 (mutation checker): a NaN length is refused even with a good weight")
T.eq(GameData.priceFor("trout", 0.40, 0.755), 8, "M2: 8.305 coins round down (floor(x + 0.5))")

-- sellTotal: the calibration
local four = {}
for i = 1, 4 do
	four[i] = { speciesId = "trout", lengthM = 0.40, weightKg = wMed }
end
local total, lines = GameData.sellTotal(four)
T.check(total >= 28 and total <= 34, string.format("four median trout sell for %d coins (28..34)", total))
T.check(#lines == 4 and lines[1].coins == 8 and lines[4].coins == 8 and lines[1].name == "Trout", "the receipt has four 8-coin trout lines")
local none, noneLines = GameData.sellTotal({})
T.check(none == 0 and #noneLines == 0, "selling nothing is 0 coins and no lines")
local mixedTotal = GameData.sellTotal({ { speciesId = "trout", lengthM = 0.55, weightKg = wMax }, { speciesId = "minnow", lengthM = 0.06, weightKg = 0.002 } })
T.eq(mixedTotal, 31, "a trophy trout plus a minnow is 30 + 1")

-- loadout multipliers
T.eq(GameData.castDistanceMul(S), 1.0, "the starter casts at x1.0")
T.eq(GameData.castDistanceMul({ rod = "rod_basic", line = "line_braid", hook = "hook_basic", lure = "worm" }), 1.1, "a line upgrade raises cast distance to x1.1")
T.eq(GameData.castDistanceMul({ rod = "rod_carbon", line = "line_braid", hook = "hook_basic", lure = "worm" }), 1.15 * 1.1, "rod and line multiply")
T.throws(function() GameData.castDistanceMul({ rod = "rod_gold", line = "line_mono", hook = "hook_basic", lure = "worm" }) end, "unknown rods id 'rod_gold'", "an unknown rod id errors")
T.eq(GameData.lineStrengthN(S), 20, "the starter line holds 20 N")
T.eq(GameData.hookSetWindowMul({ rod = "rod_basic", line = "line_mono", hook = "hook_sharp", lure = "worm" }), 1.2, "the sharp hook widens the window x1.2")
T.check(GameData.lineStrengthN(S) < SpeciesTable.get("pike").fight.strengthN, "a starter line is weaker than a pike (design hook for the snap check)")

-- upgradeCost
T.eq(GameData.upgradeCost("rods", "rod_basic", "rod_carbon"), 60, "basic -> carbon rod costs 60")
T.eq(GameData.upgradeCost("rods", "rod_carbon", "rod_pro"), 120, "carbon -> pro rod costs the difference, 120")
T.eq(GameData.upgradeCost("rod", "rod_basic", "rod_pro"), 180, "the singular kind name is accepted")
T.eq(GameData.upgradeCost("lines", "line_mono", "line_fluoro"), 120, "mono -> fluoro line costs 120")
T.throws(function() GameData.upgradeCost("rods", "rod_pro", "rod_carbon") end, "not an upgrade", "a downgrade errors")
T.throws(function() GameData.upgradeCost("hooks", "hook_sharp", "hook_sharp") end, "not an upgrade", "the same item is not an upgrade")
T.throws(function() GameData.upgradeCost("reels", "a", "b") end, "unknown gear kind", "an unknown kind errors")
T.throws(function() GameData.upgradeCost("rods", "rod_basic", "rod_gold") end, "unknown rods id", "an unknown target id errors")

-- negative controls: mutated copies fail validate
local bad = dataCopy()
bad.LURES.spinner.tags[1] = "salmon"
T.throws(function() GameData.validate(bad) end, "LURES.spinner.tags: unknown species 'salmon'", "negative control: a lure tag naming no species fails")
bad = dataCopy()
bad.GEAR.rods.rod_pro.tier = 2
T.throws(function() GameData.validate(bad) end, "tier 2 used twice", "a duplicate gear tier fails")
bad = dataCopy()
bad.GEAR.lines.line_fluoro.price = 10
T.throws(function() GameData.validate(bad) end, "GEAR.lines.line_fluoro.price", "a higher tier cheaper than a lower one fails")
bad = dataCopy()
bad.LURES.fly = nil
T.throws(function() GameData.validate(bad) end, "unknown lure 'fly'", "a species lure with no LURES entry fails")
bad = dataCopy()
bad.STARTER.rod = "rod_gold"
T.throws(function() GameData.validate(bad) end, "STARTER.rod", "a starter id that does not exist fails")
bad = dataCopy()
bad.GEAR.hooks.hook_wide.hookSetWindowMul = 0
T.throws(function() GameData.validate(bad) end, "hook_wide.hookSetWindowMul", "a zero multiplier fails")
bad = dataCopy()
bad.GEAR.rods.rod_pro.name = ""
T.throws(function() GameData.validate(bad) end, "rod_pro.name", "M3: an empty gear name fails")
T.check(GameData.validate(), "the live data is untouched by the mutated copies")

T.finish()
