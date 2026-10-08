--!strict
-- Fillet (About Fishing F1, WS-T filleting; Cloud, 2026-10-08; design/PARITY_rows_F2plus.md row P12, design/ROBLOX_constraints.md section 1)
-- The filleting minigame as a timing state machine: a fish of length L gives a timeline of durationS
-- (longer for a longer fish) with one window per cut (behind the gill, along the spine, the belly);
-- the player presses once per cut and lands clean (inside the narrow window), rough (inside the wide
-- one) or miss (outside, or no press before the window closes). The run scores 0..100, gives 2, 1 or 0
-- fillets, and a price multiplier against selling the fish whole (FilletBonus: clean fillets are
-- worth more than the whole fish, a sloppy run less). STYLISED BY DESIGN: this module carries no gore
-- state at all, no blood, no organs, no wound geometry: only cut names, windows and qualities, so the
-- view can only ever draw a stylised knife line and the game stays inside Roblox's Mild label.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * A server-side Fillet.new(speciesId, lengthM, { SpeedMul = touch and Fillet.TouchSpeedMul or 1 },
--     rng) per run; the client gets Fillet.timeline(game) to draw the bar and sends Press(t) through
--     FishingNet with its own clock time, which the server maps to the run's clock (LatencyBudget).
--   * The result: Fillet.result(game).fillets items go to TackleBox in the fish's place (a fillet
--     item per species, footprint from WST_tacklebox.md), priced at GameData.priceFor(whole fish) x
--     result.priceMul. MinFillets (default 0) is the knob for V62 ("a fail never deletes the fish
--     for free"): set it to 1 if the demo shows a failed run still yields something.
--   * Sounds: C.Sounds.FilletCut1..3 on each press by cut index (SFX_ART_LIST.md), never by quality.
-- Every number below is UNTUNED until V61/V62 are recorded. No Roblox globals; rng is injected.

local Fillet = {}

export type Quality = "clean" | "rough" | "miss"
export type CutDef = { name: string, at: number }
export type Cut = { name: string, startT: number, endT: number, cleanStartT: number, cleanEndT: number, quality: Quality?, pressT: number? }
export type Game = { speciesId: string, lengthM: number, durationS: number, speedMul: number, cuts: { Cut }, index: number, nowT: number }
export type Press = { cut: number, name: string, quality: Quality, points: number, score: number }
export type TimelineCut = { name: string, startT: number, endT: number, cleanStartT: number, cleanEndT: number }
export type Timeline = { durationS: number, cuts: { TimelineCut } }
export type ResultCut = { name: string, quality: Quality, pressT: number?, startT: number, endT: number, cleanStartT: number, cleanEndT: number }
export type Result = { score: number, fillets: number, misses: number, priceMul: number, cuts: { ResultCut }, timeline: Timeline }

Fillet.VERSION = 1

-- Placeholders for the feel review (UNTUNED). Windows are in real seconds, not scaled by the fish:
-- a reaction window is a human constant; a bigger fish only spreads its cuts over a longer bar.
Fillet.DEFAULTS = {
	BaseDurationS = 5, -- a 0 m fish would take 5 s; durationS = BaseDurationS + DurationPerM * lengthM
	DurationPerM = 5, -- a 0.40 m trout: 7 s
	CleanHalfS = 0.12, -- half-width of the clean window around each cut's centre
	RoughHalfS = 0.30, -- half-width of the rough window
	JitterS = 0.15, -- the rng moves each centre by up to this (0 without an rng)
	SpeedMul = 1, -- multiplies both half-widths; > 1 widens (touch), max SpeedMulMax
	SpeedMulMax = 2, -- the widest allowed: with JitterS it keeps consecutive windows disjoint for any length
	MinFillets = 0, -- the floor on fillets after misses (V62 knob)
	FilletsPerFish = 2, -- a perfect run yields this many
}
Fillet.TouchSpeedMul = 1.4 -- SpeedMul for phones: thumbs land later than clicks (WSI_touch_gamepad.md, UNTUNED)
Fillet.FilletBonus = 1.5 -- a perfect run's fillets sell for this times the whole fish
Fillet.POINTS = { clean = 100, rough = 60, miss = 0 }
Fillet.CUTS = { { name = "gill", at = 0.2 }, { name = "spine", at = 0.5 }, { name = "belly", at = 0.8 } } -- centre at `at` x durationS
Fillet.MinLengthM = 0.05
Fillet.MaxLengthM = 3

-- ---------------------------------------------------------------- helpers
local function isNum(v: any): boolean
	return typeof(v) == "number" and v == v and math.abs(v) < math.huge
end

local function isInt(v: any): boolean
	return isNum(v) and v == math.floor(v)
end

local function nonEmpty(v: any): boolean
	return typeof(v) == "string" and v ~= ""
end

local function round(v: number): number
	return math.floor(v + 0.5)
end

-- Window times are kept to 0.1 ms so the bar's numbers are stable across platforms and JSON
-- (7 x 0.8 - 0.3 is 5.300000000000001 in doubles; the UI and the net want 5.3).
local function tenthMs(v: number): number
	return math.floor(v * 1e4 + 0.5) / 1e4
end

-- Why a cut list is not a valid timeline (ordered, nested, disjoint, inside 0..durationS), or nil.
local function cutsProblem(cuts: { Cut }, durationS: number): string?
	if #cuts == 0 then
		return "no cuts"
	end
	local prevEnd = 0
	local names: { [string]: boolean } = {}
	for i, c in cuts do
		if not nonEmpty(c.name) or names[c.name] then
			return "cut " .. i .. ": name must be a unique non-empty string"
		end
		names[c.name] = true
		if not (isNum(c.startT) and isNum(c.endT) and isNum(c.cleanStartT) and isNum(c.cleanEndT)) then
			return "cut " .. i .. ": window times must be numbers"
		end
		if not (0 <= c.startT and c.startT <= c.cleanStartT and c.cleanStartT < c.cleanEndT and c.cleanEndT <= c.endT and c.endT <= durationS) then
			return "cut " .. i .. ": windows must satisfy 0 <= startT <= cleanStartT < cleanEndT <= endT <= durationS"
		end
		if c.startT < prevEnd then
			return "cut " .. i .. ": overlaps the previous cut"
		end
		prevEnd = c.endT
	end
	return nil
end

-- ---------------------------------------------------------------- the game
-- A new run. opts overrides any DEFAULTS key and may give `cuts` (a list of { name, at }); rng (Roblox
-- Random shape) jitters each centre by up to JitterS so the bar is not the same twice; no rng = no jitter.
function Fillet.new(speciesId: string, lengthM: number, opts: { [string]: any }?, rng: any?): Game
	assert(nonEmpty(speciesId), "Fillet.new: speciesId must be a non-empty string")
	assert(isNum(lengthM) and lengthM >= Fillet.MinLengthM and lengthM <= Fillet.MaxLengthM, "Fillet.new: lengthM must be in " .. Fillet.MinLengthM .. ".." .. Fillet.MaxLengthM .. " m")
	local o = opts or {}
	local D = Fillet.DEFAULTS
	local function num(key: string, min: number): number
		local v = if o[key] ~= nil then o[key] else D[key]
		assert(isNum(v) and v >= min, "Fillet.new: " .. key .. " must be a number >= " .. min)
		return v
	end
	local speedMul = num("SpeedMul", 0)
	local speedMax = num("SpeedMulMax", 0)
	assert(speedMul > 0 and speedMul <= speedMax, "Fillet.new: SpeedMul must be in (0, SpeedMulMax]")
	local durationS = tenthMs(num("BaseDurationS", 0) + num("DurationPerM", 0) * lengthM)
	assert(durationS > 0, "Fillet.new: the timeline must be longer than 0 s")
	local cleanHalf = num("CleanHalfS", 0) * speedMul
	local roughHalf = num("RoughHalfS", 0) * speedMul
	assert(cleanHalf > 0 and roughHalf >= cleanHalf, "Fillet.new: need 0 < CleanHalfS <= RoughHalfS")
	local jitter = num("JitterS", 0)
	local cutDefs: { CutDef } = o.cuts or Fillet.CUTS
	assert(typeof(cutDefs) == "table" and #cutDefs > 0, "Fillet.new: cuts must be a non-empty array of { name, at }")
	local cuts: { Cut } = {}
	local lastAt = 0
	for i, cd in cutDefs do
		assert(typeof(cd) == "table" and nonEmpty(cd.name) and isNum(cd.at) and cd.at > lastAt and cd.at < 1, "Fillet.new: cut " .. i .. " needs a name and an `at` strictly increasing inside (0, 1)")
		lastAt = cd.at
		local centre = durationS * cd.at
		if rng and jitter > 0 then
			centre += (rng:NextNumber() * 2 - 1) * jitter
		end
		cuts[i] = {
			name = cd.name,
			startT = tenthMs(centre - roughHalf),
			endT = tenthMs(centre + roughHalf),
			cleanStartT = tenthMs(centre - cleanHalf),
			cleanEndT = tenthMs(centre + cleanHalf),
			quality = nil,
			pressT = nil,
		}
	end
	local problem = cutsProblem(cuts, durationS)
	assert(problem == nil, "Fillet.new: the cuts do not fit the timeline (" .. tostring(problem) .. "); widen BaseDurationS or narrow the windows")
	return { speciesId = speciesId, lengthM = lengthM, durationS = durationS, speedMul = speedMul, cuts = cuts, index = 1, nowT = 0 }
end

-- The bar for the UI: every window, nothing about presses.
function Fillet.timeline(game: Game): Timeline
	local cuts: { TimelineCut } = {}
	for i, c in game.cuts do
		cuts[i] = { name = c.name, startT = c.startT, endT = c.endT, cleanStartT = c.cleanStartT, cleanEndT = c.cleanEndT }
	end
	return { durationS = game.durationS, cuts = cuts }
end

-- "waiting" before the current cut's window, "cut<i>" while it is open, "done" after the last cut.
function Fillet.state(game: Game): string
	if game.index > #game.cuts then
		return "done"
	end
	local c = game.cuts[game.index]
	if game.nowT >= c.startT and game.nowT <= c.endT then
		return "cut" .. game.index
	end
	return "waiting"
end

-- True once every cut is resolved.
function Fillet.done(game: Game): boolean
	return game.index > #game.cuts
end

-- Moves the clock to t (never backwards): every unresolved cut whose window has closed is a miss.
-- Returns the state and how many cuts were missed by this call.
function Fillet.advance(game: Game, t: number): (string, number)
	assert(isNum(t) and t >= 0, "Fillet.advance: t must be a number >= 0")
	if t > game.nowT then
		game.nowT = t
	end
	local missed = 0
	while game.index <= #game.cuts and game.cuts[game.index].endT < game.nowT do
		local c = game.cuts[game.index]
		c.quality = "miss"
		game.index += 1
		missed += 1
	end
	return Fillet.state(game), missed
end

-- The running score: mean points of the resolved cuts over ALL cuts (unresolved count as 0 so far).
function Fillet.score(game: Game): number
	local sum = 0
	for _, c in game.cuts do
		if c.quality then
			sum += Fillet.POINTS[c.quality]
		end
	end
	return round(sum / #game.cuts)
end

-- The player presses at run time t. Resolves the current cut: clean inside the narrow window, rough
-- inside the wide one, miss when pressed early (from the midpoint of the gap before the window on).
-- A press in the first half of a gap belongs to the cut that just closed (already a miss by timeout)
-- and is ignored with nil, "late"; before the first cut's midpoint it is nil, "early". So mashing
-- never helps: at most one press counts per cut and an early one costs the cut. nil, "done" after
-- the last cut; t before the last advance is nil, "time went backwards".
function Fillet.press(game: Game, t: number): (Press?, string?)
	assert(isNum(t) and t >= 0, "Fillet.press: t must be a number >= 0")
	if t < game.nowT then
		return nil, "time went backwards"
	end
	Fillet.advance(game, t)
	if game.index > #game.cuts then
		return nil, "done"
	end
	local i = game.index
	local c = game.cuts[i]
	local prevEnd = if i > 1 then game.cuts[i - 1].endT else 0
	local mid = (prevEnd + c.startT) / 2
	if t < mid then
		return nil, if i > 1 then "late" else "early"
	end
	local q: Quality
	if t >= c.cleanStartT and t <= c.cleanEndT then
		q = "clean"
	elseif t >= c.startT and t <= c.endT then
		q = "rough"
	else
		q = "miss"
	end
	c.quality = q
	c.pressT = t
	game.index = i + 1
	return { cut = i, name = c.name, quality = q, points = Fillet.POINTS[q], score = Fillet.score(game) }, nil
end

-- The price multiplier against the whole fish for a score and a fillet count (pure, for the shop).
function Fillet.priceMul(score: number, fillets: number, opts: { [string]: any }?): number
	local per = (opts and opts.FilletsPerFish) or Fillet.DEFAULTS.FilletsPerFish
	local bonus = (opts and opts.FilletBonus) or Fillet.FilletBonus
	return fillets / per * (1 + (bonus - 1) * math.clamp(score, 0, 100) / 100)
end

-- The outcome once every cut is resolved: score, fillets (FilletsPerFish minus misses, floored at
-- MinFillets), the price multiplier, every cut's quality and the timeline. nil, "not done" before.
function Fillet.result(game: Game, opts: { [string]: any }?): (Result?, string?)
	if game.index <= #game.cuts then
		return nil, "not done"
	end
	local D = Fillet.DEFAULTS
	local per = (opts and opts.FilletsPerFish) or D.FilletsPerFish
	local minF = (opts and opts.MinFillets) or D.MinFillets
	local misses = 0
	local cuts: { ResultCut } = {}
	for i, c in game.cuts do
		local q = c.quality :: Quality
		if q == "miss" then
			misses += 1
		end
		cuts[i] = { name = c.name, quality = q, pressT = c.pressT, startT = c.startT, endT = c.endT, cleanStartT = c.cleanStartT, cleanEndT = c.cleanEndT }
	end
	local score = Fillet.score(game)
	local fillets = math.max(minF, per - misses)
	return { score = score, fillets = fillets, misses = misses, priceMul = Fillet.priceMul(score, fillets, opts), cuts = cuts, timeline = Fillet.timeline(game) }, nil
end

-- ---------------------------------------------------------------- save form
-- A plain JSON-safe table of the run (so a run survives a server hand-over mid-cut).
function Fillet.serialize(game: Game): { [string]: any }
	local cuts: { any } = {}
	for i, c in game.cuts do
		cuts[i] = { name = c.name, startT = c.startT, endT = c.endT, cleanStartT = c.cleanStartT, cleanEndT = c.cleanEndT, quality = c.quality, pressT = c.pressT }
	end
	return { v = Fillet.VERSION, speciesId = game.speciesId, lengthM = game.lengthM, durationS = game.durationS, speedMul = game.speedMul, index = game.index, nowT = game.nowT, cuts = cuts }
end

-- The inverse of serialize; every window, quality and the index are re-checked so a tampered run
-- (a quality on an unresolved cut, a press outside its window, a window past the end) is refused.
function Fillet.deserialize(tbl: any): Game
	if typeof(tbl) ~= "table" or tbl.v ~= Fillet.VERSION or typeof(tbl.cuts) ~= "table" then
		error("Fillet.deserialize: not a serialized run")
	end
	local function fail(why: string)
		error("Fillet.deserialize: " .. why)
	end
	if not nonEmpty(tbl.speciesId) then
		fail("speciesId must be a non-empty string")
	end
	if not isNum(tbl.lengthM) or tbl.lengthM < Fillet.MinLengthM or tbl.lengthM > Fillet.MaxLengthM then
		fail("bad lengthM")
	end
	if not isNum(tbl.durationS) or tbl.durationS <= 0 then
		fail("durationS must be > 0")
	end
	if not isNum(tbl.speedMul) or tbl.speedMul <= 0 then
		fail("speedMul must be > 0")
	end
	if not isNum(tbl.nowT) or tbl.nowT < 0 then
		fail("nowT must be >= 0")
	end
	local n = #tbl.cuts
	if not isInt(tbl.index) or tbl.index < 1 or tbl.index > n + 1 then
		fail("index must be an integer in 1..cuts+1")
	end
	local cuts: { Cut } = {}
	for i = 1, n do
		local c: any = tbl.cuts[i]
		if typeof(c) ~= "table" then
			fail("cut " .. i .. ": must be a table")
		end
		if c.quality ~= nil and Fillet.POINTS[c.quality] == nil then
			fail("cut " .. i .. ": bad quality " .. tostring(c.quality))
		end
		if (i < tbl.index) ~= (c.quality ~= nil) then
			fail("cut " .. i .. ": quality must be set exactly for cuts before index")
		end
		if c.pressT ~= nil then
			if c.quality == nil or not isNum(c.pressT) or c.pressT < 0 or c.pressT > tbl.nowT then
				fail("cut " .. i .. ": pressT must be a time <= nowT on a resolved cut")
			end
			local inClean = c.pressT >= c.cleanStartT and c.pressT <= c.cleanEndT
			local inRough = c.pressT >= c.startT and c.pressT <= c.endT
			local want: Quality = if inClean then "clean" elseif inRough then "rough" else "miss"
			if want ~= c.quality then
				fail("cut " .. i .. ": quality " .. tostring(c.quality) .. " disagrees with pressT")
			end
		elseif c.quality ~= nil and c.quality ~= "miss" then
			fail("cut " .. i .. ": a " .. tostring(c.quality) .. " cut needs a pressT")
		end
		cuts[i] = { name = c.name, startT = c.startT, endT = c.endT, cleanStartT = c.cleanStartT, cleanEndT = c.cleanEndT, quality = c.quality, pressT = c.pressT }
	end
	local problem = cutsProblem(cuts, tbl.durationS)
	if problem then
		fail(problem)
	end
	return { speciesId = tbl.speciesId, lengthM = tbl.lengthM, durationS = tbl.durationS, speedMul = tbl.speedMul, cuts = cuts, index = tbl.index, nowT = tbl.nowT }
end

return Fillet
