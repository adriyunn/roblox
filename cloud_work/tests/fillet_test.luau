--!strict
-- fillet_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves Fillet: the whole timeline of a 0.40 m trout with every window written out, presses at the
-- window edges, early and late presses, a miss by timeout, the score arithmetic and the fillet count,
-- the price multiplier (FilletBonus), SpeedMul widening for touch, rng jitter bounded and
-- deterministic, custom cut lists, a serialize round trip through real JSON mid-run, and deserialize
-- refusing a tampered run (negative control). Run from this folder: luau fillet_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("fillet_test")
local Fillet = require("../src/Fishing/Shared/Fillet")

local function lcg(seed: number)
	local s = seed
	local rng = {}
	function rng:NextNumber(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
	function rng:NextInteger(a: number, b: number): number
		return a + math.floor(self:NextNumber() * (b - a + 1))
	end
	return rng
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

local function trout(opts: { [string]: any }?, rng: any?): Fillet.Game
	return Fillet.new("trout", 0.40, opts, rng)
end

-- the whole timeline of a 0.40 m trout: 5 + 5 x 0.40 = 7 s, centres at 20/50/80%
local g = trout()
T.eq(g.durationS, 7, "a 0.40 m trout gives a 7 s timeline")
T.check(#g.cuts == 3 and g.cuts[1].name == "gill" and g.cuts[2].name == "spine" and g.cuts[3].name == "belly", "three cuts: gill, spine, belly")
local function window(c: Fillet.Cut, s: number, cs: number, ce: number, e: number): boolean
	return near(c.startT, s) and near(c.cleanStartT, cs) and near(c.cleanEndT, ce) and near(c.endT, e)
end
T.check(window(g.cuts[1], 1.10, 1.28, 1.52, 1.70), "gill: rough 1.10..1.70 s, clean 1.28..1.52 s (centre 1.4)")
T.check(window(g.cuts[2], 3.20, 3.38, 3.62, 3.80), "spine: rough 3.20..3.80 s, clean 3.38..3.62 s (centre 3.5)")
T.check(window(g.cuts[3], 5.30, 5.48, 5.72, 5.90), "belly: rough 5.30..5.90 s, clean 5.48..5.72 s (centre 5.6)")
local tl = Fillet.timeline(g)
T.check(tl.durationS == 7 and #tl.cuts == 3 and near(tl.cuts[3].cleanEndT, 5.72) and (tl.cuts[1] :: any).quality == nil, "timeline() carries the windows and nothing about presses")
T.eq(Fillet.new("trout", 0.55).durationS, 7.75, "a 0.55 m fish gives 7.75 s")
T.eq(Fillet.new("trout", 0.25).durationS, 6.25, "a 0.25 m fish gives 6.25 s")

-- states
T.eq(Fillet.state(g), "waiting", "the run starts waiting")
T.eq((Fillet.advance(g, 1.1)), "cut1", "at 1.10 s the gill window is open: cut1")
T.eq((Fillet.advance(g, 1.75)), "waiting", "after the gill window with no press the run waits for the spine")
T.eq(g.cuts[1].quality, "miss", "and the gill is a miss by timeout")
T.eq(g.index, 2, "the next cut is the spine")
T.check(not Fillet.done(g), "not done yet")
T.throws(function() Fillet.advance(g, -1) end, "t must be", "a negative time is a programmer error")

-- a perfect run
g = trout()
local p1 = Fillet.press(g, 1.4) :: Fillet.Press
T.check(p1.cut == 1 and p1.name == "gill" and p1.quality == "clean" and p1.points == 100, "a press on the centre of the gill is clean")
T.eq(p1.score, 33, "the running score after one clean cut of three is 33")
local p2 = Fillet.press(g, 3.5) :: Fillet.Press
local p3 = Fillet.press(g, 5.6) :: Fillet.Press
T.check(p2.quality == "clean" and p3.quality == "clean" and p3.score == 100, "three centre presses score 100")
T.eq(Fillet.state(g), "done", "state is done after the last cut")
T.check(Fillet.done(g), "done() is true")
local r = Fillet.result(g) :: Fillet.Result
T.check(r.score == 100 and r.fillets == 2 and r.misses == 0, "a perfect run: score 100, 2 fillets, 0 misses")
T.eq(r.priceMul, 1.5, "a perfect run's fillets sell for FilletBonus 1.5 x the whole fish")
T.check(Fillet.FilletBonus > 1, "FilletBonus is above 1: clean fillets beat selling whole")
T.check(#r.cuts == 3 and r.cuts[2].pressT == 3.5 and r.timeline.durationS == 7, "the result lists every cut with its press and the timeline")
local none, why = Fillet.press(g, 6)
T.check(none == nil and why == "done", "a press after the last cut is nil, done")

-- presses at the edges (fresh runs; times from the run's own windows)
local function edge(t: number): string
	local e = trout()
	local p = Fillet.press(e, t)
	return if p then p.quality else "nil"
end
T.eq(edge(trout().cuts[1].startT), "rough", "a press at the rough window's start is rough")
T.eq(edge(trout().cuts[1].endT), "rough", "a press at the rough window's end is rough")
T.eq(edge(trout().cuts[1].cleanStartT), "clean", "a press at the clean window's start is clean")
T.eq(edge(trout().cuts[1].cleanEndT), "clean", "a press at the clean window's end is clean")
T.eq(edge(trout().cuts[1].cleanEndT + 1e-6), "rough", "a press a microsecond past the clean window is rough")
T.eq(edge(1.0), "miss", "a press at 1.00 s, before the window but past the midpoint, is an early miss")
local e1 = trout()
local pe, whyE = Fillet.press(e1, 0.3)
T.check(pe == nil and whyE == "early" and e1.index == 1 and e1.cuts[1].quality == nil, "a press at 0.30 s is ignored as early and costs nothing")
local e2 = trout()
local pl, whyL = Fillet.press(e2, 1.8)
T.check(pl == nil and whyL == "late" and e2.cuts[1].quality == "miss" and e2.index == 2, "a press at 1.80 s times the gill out and is ignored as late: one miss, not two")
local e3 = trout()
Fillet.press(e3, 3.5)
local pb, whyB = Fillet.press(e3, 2)
T.check(pb == nil and whyB == "time went backwards", "a press before the last advance is refused")

-- a miss by timeout mid-run
g = trout()
Fillet.press(g, 1.4)
local st, missed = Fillet.advance(g, 4.0)
T.check(st == "waiting" and missed == 1 and g.cuts[2].quality == "miss", "advance to 4.0 s with no spine press: one miss, waiting for the belly")
T.eq((Fillet.advance(g, 5.3)), "cut3", "at 5.30 s the belly window opens")
T.eq(Fillet.score(g), 33, "the running score is 33 with one clean and one miss")
local notDone, notDoneWhy = Fillet.result(g)
T.check(notDone == nil and notDoneWhy == "not done", "result() before the last cut is nil, not done")
Fillet.press(g, 5.6)
r = Fillet.result(g) :: Fillet.Result
T.check(r.score == 67 and r.fillets == 1 and r.misses == 1, "clean, miss, clean: score 67, 1 fillet")
T.check(near(r.priceMul, 0.6675), "one fillet at score 67 sells for 0.5 x 1.335 = 0.6675 x the whole fish (got " .. r.priceMul .. ")")

-- score arithmetic
local function run(times: { number }): Fillet.Result
	local x = trout()
	for _, t in times do
		Fillet.press(x, t)
	end
	Fillet.advance(x, 7)
	return Fillet.result(x) :: Fillet.Result
end
local ccr = run({ 1.4, 3.5, 5.3 })
T.check(ccr.score == 87 and ccr.fillets == 2 and near(ccr.priceMul, 1.435), "clean, clean, rough: 260/3 rounds to 87, 2 fillets, priceMul 1.435")
local rrr = run({ 1.1, 3.2, 5.3 })
T.check(rrr.score == 60 and near(rrr.priceMul, 1.3), "three rough cuts: 60, priceMul 1.3")
local mmc = run({ 5.6 })
T.check(mmc.score == 33 and mmc.fillets == 0 and mmc.misses == 2 and mmc.priceMul == 0, "two timeouts and one clean: 33, 0 fillets, priceMul 0")
local mmm = run({})
T.check(mmm.score == 0 and mmm.fillets == 0 and mmm.priceMul == 0, "no press at all: 0, 0 fillets")
local x = trout()
Fillet.advance(x, 7)
T.eq((Fillet.result(x, { MinFillets = 1 }) :: Fillet.Result).fillets, 1, "MinFillets 1 keeps one fillet after a total fail (the V62 knob)")
T.eq(Fillet.priceMul(100, 2), Fillet.FilletBonus, "priceMul(100, 2) is FilletBonus")
T.eq(Fillet.priceMul(0, 2), 1, "priceMul(0, 2) is 1: the whole-fish price")
T.eq(Fillet.priceMul(50, 1), 0.625, "priceMul(50, 1) is 0.5 x 1.25")

-- SpeedMul widens the windows (touch)
local touch = trout({ SpeedMul = Fillet.TouchSpeedMul })
T.check(window(touch.cuts[1], 0.98, 1.232, 1.568, 1.82), "SpeedMul 1.4: gill rough 0.98..1.82 s, clean 1.232..1.568 s")
T.eq(edge(1.55), "rough", "a press at 1.55 s is rough with a mouse (clean ends at 1.52)")
T.eq((Fillet.press(touch, 1.55) :: Fillet.Press).quality, "clean", "the same press is clean on touch (clean ends at 1.568)")
T.check(touch.durationS == 7 and touch.speedMul == 1.4, "SpeedMul changes the windows, not the timeline length")
T.throws(function() trout({ SpeedMul = 2.5 }) end, "SpeedMul", "SpeedMul above SpeedMulMax is refused")
T.throws(function() trout({ SpeedMul = 0 }) end, "SpeedMul", "SpeedMul 0 is refused")
local alt = { n = 0 }
function alt:NextNumber(): number
	self.n += 1
	return if self.n % 2 == 1 then 1 else 0
end
local tight = Fillet.new("minnow", Fillet.MinLengthM, { SpeedMul = Fillet.DEFAULTS.SpeedMulMax }, alt)
T.check(tight.cuts[1].endT <= tight.cuts[2].startT and tight.cuts[2].endT <= tight.cuts[3].startT, "the smallest fish at the widest SpeedMul with worst-case jitter keeps the windows disjoint")

-- rng jitter: bounded, deterministic, different from the plain bar
local j1 = trout(nil, lcg(3))
local j2 = trout(nil, lcg(3))
local maxShift = 0
for i, c in j1.cuts do
	maxShift = math.max(maxShift, math.abs((c.startT + c.endT) / 2 - g.cuts[i].startT - 0.3))
end
T.check(maxShift > 0 and maxShift <= Fillet.DEFAULTS.JitterS + 1e-9, "jitter moves the centres by at most JitterS (got " .. string.format("%.3f", maxShift) .. ")")
T.check(near(j1.cuts[1].startT, j2.cuts[1].startT) and near(j1.cuts[3].endT, j2.cuts[3].endT), "the same seed gives the same bar")
T.eq(g.cuts[3].startT, 5.3, "window times are exact to 0.1 ms: the belly opens at 5.3, not 5.300000000000001")
T.check(trout({ JitterS = 0 }, lcg(3)).cuts[1].startT == g.cuts[1].startT, "JitterS 0 ignores the rng")

-- custom cuts and bad input
local two = Fillet.new("pike", 0.8, { cuts = { { name = "a", at = 0.3 }, { name = "b", at = 0.7 } } })
T.check(#two.cuts == 2 and near(two.cuts[2].startT, 9 * 0.7 - 0.3), "a custom cut list: two cuts on a 9 s pike")
T.throws(function() Fillet.new("pike", 0.8, { cuts = { { name = "a", at = 0.7 }, { name = "b", at = 0.3 } } }) end, "strictly increasing", "cuts out of order are refused")
T.throws(function() Fillet.new("pike", 0.8, { cuts = { { name = "a", at = 0.3 }, { name = "a", at = 0.7 } } }) end, "unique", "a duplicate cut name is refused")
T.throws(function() Fillet.new("trout", 0.01) end, "lengthM", "a 1 cm fish is refused")
T.throws(function() Fillet.new("", 0.4) end, "speciesId", "an empty species id is refused")
T.throws(function() trout({ RoughHalfS = 5 }) end, "do not fit", "windows wider than the bar are refused")

-- round trip through real JSON mid-run, then the rebuilt run continues identically
local a = trout()
Fillet.press(a, 1.3)
local wire = Stub.jsonEncode(Fillet.serialize(a))
local b = Fillet.deserialize(Stub.jsonDecode(wire))
T.eq(Stub.jsonEncode(Fillet.serialize(b)), wire, "deserialize(serialize()) serializes identically")
T.check(b.index == 2 and b.cuts[1].quality == "clean" and b.cuts[1].pressT == 1.3 and b.cuts[2].quality == nil, "the rebuilt run keeps the resolved cut and the pending ones")
Fillet.press(a, 3.7)
Fillet.press(b, 3.7)
Fillet.advance(a, 7)
Fillet.advance(b, 7)
T.eq(Stub.jsonEncode(Fillet.serialize(a)), Stub.jsonEncode(Fillet.serialize(b)), "the same presses on both runs give the same end state")
local tampered = Stub.jsonDecode(wire)
tampered.cuts[2].quality = "clean"
T.throws(function() Fillet.deserialize(tampered) end, "quality must be set exactly", "negative control: a quality on an unresolved cut is refused")
tampered = Stub.jsonDecode(wire)
tampered.cuts[1].pressT = 0.2
T.throws(function() Fillet.deserialize(tampered) end, "disagrees", "a clean cut whose press is outside its window is refused")
tampered = Stub.jsonDecode(wire)
tampered.cuts[1].pressT = nil
T.throws(function() Fillet.deserialize(tampered) end, "needs a pressT", "a clean cut without a press is refused")
tampered = Stub.jsonDecode(wire)
tampered.index = 5
T.throws(function() Fillet.deserialize(tampered) end, "index", "an index past the cuts is refused")
tampered = Stub.jsonDecode(wire)
tampered.cuts[3].endT = 9
T.throws(function() Fillet.deserialize(tampered) end, "windows must satisfy", "a window past the end of the bar is refused")
tampered = Stub.jsonDecode(wire)
tampered.cuts[2].startT = 1.5
T.throws(function() Fillet.deserialize(tampered) end, "overlaps", "overlapping windows are refused")
T.throws(function() Fillet.deserialize({ v = 2 }) end, "not a serialized", "a wrong version is refused")

T.finish()
