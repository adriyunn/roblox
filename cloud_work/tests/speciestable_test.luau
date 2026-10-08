--!strict
-- speciestable_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves SpeciesTable: validate passes and fails on mutated copies (negative controls), rollLength
-- stays bounded with the right median over 2,000 seeded draws, weightFor is monotonic, sizeClass
-- boundaries, brainConfig merges without touching the base and rejects unknown keys, spawnWeight
-- periods and the 30-minute boundary blends, depth gating, and lure multipliers.
-- Run from this folder: luau speciestable_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("speciestable_test")
local SpeciesTable = require("../src/Fishing/Shared/SpeciesTable")
local TackleBox = require("../src/Fishing/Shared/TackleBox")

-- a small seeded LCG with Roblox's Random shape (Park-Miller minimal standard)
local function lcg(seed: number)
	local s = seed % 2147483647
	if s == 0 then
		s = 1
	end
	local R = {}
	function R.NextNumber(_self: any, a: number?, b: number?): number
		s = (s * 48271) % 2147483647
		local u = s / 2147483647
		if a ~= nil and b ~= nil then
			return a + u * (b - a)
		end
		return u
	end
	function R.NextInteger(self: any, a: number, b: number): number
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	return R
end

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

-- the table itself
T.check(SpeciesTable.validate(), "validate() passes on the shipped rows")
T.eq(table.concat(SpeciesTable.ids(), ","), "carp,minnow,perch,pike,trout", "ids() is sorted and has the five species")
T.throws(function() SpeciesTable.get("salmon") end, "unknown species 'salmon'", "get() names an unknown id")
local trout = SpeciesTable.get("trout")
T.check(trout.tuned == true and trout.lengthM.median == 0.40, "trout is tuned with a 0.40 m median")
T.check(next(trout.brain) == nil, "trout has no brain overrides (the F1 base config is trout)")
local untuned = 0
for _, id in SpeciesTable.ids() do
	if not SpeciesTable.get(id).tuned then
		untuned += 1
	end
end
T.eq(untuned, 4, "the other four species are marked untuned")
local shapesOk = true
for _, id in SpeciesTable.ids() do
	for _, sc in SpeciesTable.get(id).sizeClasses do
		shapesOk = shapesOk and TackleBox.SHAPES[sc.shape] ~= nil
	end
end
T.check(shapesOk, "every size class names a real TackleBox shape")

-- negative controls: mutated copies fail validate, naming row and field
local bad = deepCopy(SpeciesTable.ROWS)
bad.trout.lengthM.median = 0.9
T.throws(function() SpeciesTable.validate(bad) end, "trout.lengthM", "negative control: median > max fails naming trout.lengthM")
bad = deepCopy(SpeciesTable.ROWS)
bad.perch.sizeClasses[1].shape = "bogus"
T.throws(function() SpeciesTable.validate(bad) end, "perch.sizeClasses[1].shape", "an unknown shape name fails")
bad = deepCopy(SpeciesTable.ROWS)
bad.pike.spawn.timeWeights.day = 1.5
T.throws(function() SpeciesTable.validate(bad) end, "pike.spawn.timeWeights.day", "a time weight above 1 fails")
bad = deepCopy(SpeciesTable.ROWS)
bad.carp.sizeClasses[3].maxM = 0.80
T.throws(function() SpeciesTable.validate(bad) end, "last maxM", "size classes that stop short of max fail")
bad = deepCopy(SpeciesTable.ROWS)
bad.carp.sizeClasses[2].maxM = 0.30
T.throws(function() SpeciesTable.validate(bad) end, "carp.sizeClasses[2].maxM", "non-ascending size classes fail")
bad = deepCopy(SpeciesTable.ROWS)
bad.minnow.brain.Bogus = 1
T.throws(function() SpeciesTable.validate(bad) end, "minnow.brain.Bogus", "an unknown brain key fails")
bad = deepCopy(SpeciesTable.ROWS)
bad.trout.weightA = 0
T.throws(function() SpeciesTable.validate(bad) end, "trout.weightA", "weightA of 0 fails")
bad = deepCopy(SpeciesTable.ROWS)
bad.pike.fight.runChance = 1.5
T.throws(function() SpeciesTable.validate(bad) end, "pike.fight.runChance", "runChance above 1 fails")
T.check(SpeciesTable.validate(), "the live rows are untouched by the mutated copies")

-- rollLength: bounded, right median, deterministic
local rng = lcg(7)
local draws = {}
local inRange = true
for i = 1, 2000 do
	local L = SpeciesTable.rollLength("trout", rng)
	draws[i] = L
	inRange = inRange and L >= 0.25 and L <= 0.55
end
T.check(inRange, "2,000 trout lengths all within 0.25..0.55 m")
table.sort(draws)
local med = (draws[1000] + draws[1001]) / 2
T.check(math.abs(med - 0.40) <= 0.04, string.format("sample median %.3f within 10%% of 0.40", med))
T.check(draws[1] < 0.30 and draws[2000] > 0.50, string.format("lengths spread over the range (%.3f .. %.3f)", draws[1], draws[2000]))
local a, b = lcg(99), lcg(99)
local same = true
for _ = 1, 10 do
	same = same and SpeciesTable.rollLength("pike", a) == SpeciesTable.rollLength("pike", b)
end
T.check(same, "the same seed gives the same lengths")
T.throws(function() SpeciesTable.rollLength("salmon", lcg(1)) end, "unknown species", "rollLength refuses an unknown id")

-- R2 (F2): one sigma per side of the median; the seeded share clamped to exactly max stays under 1%
local rngR2 = lcg(12345)
local atMax = 0
for _ = 1, 100000 do
	if SpeciesTable.rollLength("trout", rngR2) == 0.55 then
		atMax += 1
	end
end
T.check(atMax < 1000, string.format("R2 (F2): %d of 100,000 seeded trout clamp to exactly 0.55 m (< 1,000; one sigma for the whole span gave 2,220)", atMax))

-- weightFor
local w1, w2, w3 = SpeciesTable.weightFor("trout", 0.25), SpeciesTable.weightFor("trout", 0.40), SpeciesTable.weightFor("trout", 0.55)
T.check(w1 < w2 and w2 < w3, "weightFor is monotonic in length")
T.eq(w2, 0.704, "a median trout weighs 0.704 kg")
T.check(SpeciesTable.weightFor("pike", 1.20) > 12 and SpeciesTable.weightFor("pike", 1.20) < 13, "a 1.20 m pike weighs about 12.6 kg")

-- sizeClass boundaries (maxM inclusive)
local c, s = SpeciesTable.sizeClass("trout", 0.30)
T.check(c == "small" and s == "line1", "0.30 m trout is small / line1")
c, s = SpeciesTable.sizeClass("trout", 0.32)
T.check(c == "small", "0.32 m is still small (inclusive maxM)")
c, s = SpeciesTable.sizeClass("trout", 0.3201)
T.check(c == "medium" and s == "line2", "0.3201 m is medium / line2")
c, s = SpeciesTable.sizeClass("trout", 0.46)
T.check(c == "medium", "0.46 m is medium")
c, s = SpeciesTable.sizeClass("trout", 0.47)
T.check(c == "large" and s == "line3", "0.47 m is large / line3")
c, s = SpeciesTable.sizeClass("trout", 0.60)
T.check(c == "large", "above max still reports the last class")
c, s = SpeciesTable.sizeClass("carp", 0.90)
T.check(c == "large" and s == "rect2x3", "a max carp takes a rect2x3")

-- brainConfig merge
local base = { NoticeRangeM = 3, HoverMinS = 1, HoverMaxS = 2, ChargeSpeedMps = 3, CooldownMinS = 4, CooldownMaxS = 5 }
local merged = SpeciesTable.brainConfig(base, "pike")
T.eq(merged.NoticeRangeM, 4.0, "pike override applied")
T.eq(merged.CooldownMinS, 4, "keys pike does not override come from the base")
T.check(base.NoticeRangeM == 3 and base.HoverMinS == 1, "brainConfig does not mutate the base")
local troutCfg = SpeciesTable.brainConfig(base, "trout")
local equal = true
for k, v in base do
	equal = equal and troutCfg[k] == v
end
T.check(equal and troutCfg ~= base, "trout config equals the base and is a copy")
T.throws(function() SpeciesTable.brainConfig({ NoticeRangeM = 3 }, "pike") end, "unknown override key", "an override the base lacks errors")

-- spawnWeight: periods, blends, depth gate
T.eq(SpeciesTable.spawnWeight("trout", 12, 1.0), 0.6, "12:00 is day (0.6)")
T.eq(SpeciesTable.spawnWeight("trout", 23, 1.0), 0.3, "23:00 is night (0.3)")
T.eq(SpeciesTable.spawnWeight("trout", 6, 1.0), 1.0, "06:00 is dawn (1.0)")
T.eq(SpeciesTable.spawnWeight("trout", 18, 1.0), 1.0, "18:00 is dusk (1.0)")
T.eq(SpeciesTable.spawnWeight("trout", 7.75, 1.0), 0.9, "07:45 blends 75% dawn / 25% day = 0.9")
T.eq(SpeciesTable.spawnWeight("trout", 8.25, 1.0), 0.7, "08:15 blends 25% dawn / 75% day = 0.7")
T.eq(SpeciesTable.spawnWeight("trout", 8, 1.0), 0.8, "08:00 is the midpoint 0.8")
T.eq(SpeciesTable.spawnWeight("trout", 4.75, 1.0), 0.475, "04:45 blends night into dawn (0.475)")
T.eq(SpeciesTable.spawnWeight("trout", 19.5, 1.0), 1.0, "19:30 is the blend edge, still pure dusk")
T.eq(SpeciesTable.spawnWeight("trout", 24.5, 1.0), 0.3, "24.5 h wraps to 00:30 (night)")
T.eq(SpeciesTable.spawnWeight("trout", 12, 5.0), 0, "depth 5.0 m is outside trout's 0.3..3.0 (0)")
T.eq(SpeciesTable.spawnWeight("trout", 12, 0.2), 0, "depth 0.2 m is too shallow (0)")
T.eq(SpeciesTable.spawnWeight("minnow", 12, 0.5), 1.0, "a minnow at midday in 0.5 m is 1.0")

-- lureMultiplier
T.eq(SpeciesTable.lureMultiplier("trout", "fly"), 1.5, "trout on a fly is x1.5")
T.eq(SpeciesTable.lureMultiplier("trout", "nothing"), 1, "an unlisted lure falls back to default 1")
T.eq(SpeciesTable.lureMultiplier("pike", "worm"), 0.6, "pike default is 0.6")

-- N2: a NaN or infinite time or depth is a weight of 0, never a weight that slipped past the gates
T.check(SpeciesTable.spawnWeight("trout", 0 / 0, 1.0) == 0 and SpeciesTable.spawnWeight("trout", 12, 0 / 0) == 0 and SpeciesTable.spawnWeight("trout", math.huge, 1.0) == 0 and SpeciesTable.spawnWeight("trout", 12, math.huge) == 0, "N2: spawnWeight with a NaN or infinite time or depth is 0 (was: 1 for a NaN time, the depth gate skipped for a NaN depth)")

T.finish()
