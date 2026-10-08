--!strict
-- fishbed_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves src/Fishing/Shared/FishBed.lua with analytic beds (flat, slope, ledge, a hole) behind an injected
-- raycast that honours the origin and the ray length: the ray's origin and direction, the ledge seen
-- within 0.5 s of crossing (note B3), the hole -> fallback used and counted (B4), the cache interval
-- (B8: a still fish for 10 s = 20 rays + 1), the move threshold, the note's arithmetic (8 fish x 2 rays/s),
-- Enabled = false as the rollback switch (B5), no bed at all, forget, and the negative control that a ray
-- stopping at the water reports the water as the bed (B7: IgnoreWater matters). No save form here.
-- Run from this folder: luau fishbed_test.luau

local Stub = require("./RobloxStub")
local FishBed = require("../src/Fishing/Shared/FishBed")
local T = Stub.harness("fishbed_test")

type Bed = (x: number, z: number) -> number?
type Cast = { origin: any, dir: any }

-- analytic beds (the names the note's section 5 shares with the oracle)
local function flat(y0: number): Bed
	return function(_x: number, _z: number): number?
		return y0
	end
end
local function slope(k: number): Bed
	return function(x: number, _z: number): number?
		return -k * x
	end
end
local function ledge(x0: number, yLeft: number, drop: number): Bed
	return function(x: number, _z: number): number?
		return if x >= x0 then yLeft - drop else yLeft
	end
end
local function hole(cx: number, cz: number, r: number, bed: Bed): Bed
	return function(x: number, z: number): number?
		local dx, dz = x - cx, z - cz
		if dx * dx + dz * dz < r * r then
			return nil
		end
		return bed(x, z)
	end
end

-- A raycast over an analytic bed that behaves like workspace:Raycast: it records every cast, misses a bed
-- above the origin or beyond the ray's reach, and returns the hit height.
local function rayOver(bed: Bed): (FishBed.Raycast, { Cast })
	local casts: { Cast } = {}
	local function cast(origin: any, dir: any): number?
		table.insert(casts, { origin = origin, dir = dir })
		local y = bed(origin.X, origin.Z)
		if y == nil or y > origin.Y or origin.Y - y > -dir.Y then
			return nil
		end
		return y
	end
	return cast, casts
end

local function near(a: number?, b: number, eps: number?): boolean
	return a ~= nil and math.abs(a - b) <= (eps or 1e-9)
end

-- ---------------------------------------------------------------- construction
do
	T.check(FishBed.DEFAULTS.BedSampleS == 0.5 and FishBed.DEFAULTS.MoveResampleM == 0.5 and FishBed.DEFAULTS.StartAboveM == 0.5 and FishBed.DEFAULTS.RayLenM == 6, "defaults are the note's 0.5 s / 0.5 m / 0.5 m / 6 m")
	T.throws(function() FishBed.new({ BedSampleS = -1 }, rayOver(flat(0))) end, "BedSampleS", "new refuses a negative BedSampleS")
	T.throws(function() FishBed.new({ RayLenM = 0 }, rayOver(flat(0))) end, "RayLenM", "new refuses RayLenM 0")
	T.throws(function() FishBed.new({}, nil) end, "raycast", "new refuses a missing raycast while enabled")
	T.throws(function() FishBed.new({ fallback = 3 :: any }, rayOver(flat(0))) end, "fallback", "new refuses a non-function fallback")
	T.check(FishBed.new({ Enabled = false, fallback = flat(-1) }, nil) ~= nil, "new accepts no raycast when Enabled = false")
end

-- ---------------------------------------------------------------- flat bed, origin and direction
do
	local cast, casts = rayOver(flat(-2))
	local bed = FishBed.new({ waterAt = function(_x: number, _z: number): number
		return 0.3
	end }, cast)
	local fish = { id = 1 }
	local y, source = bed:bedY(fish, 1, 2, 0)
	T.check(y == -2 and source == "ray", "flat(-2): bedY is -2 from the ray")
	T.eq(#casts, 1, "flat: one cast")
	local c = casts[1]
	T.check(c.origin.X == 1 and c.origin.Z == 2 and near(c.origin.Y, 0.8), "flat: the origin is (x, waterAt + StartAboveM, z) = (1, 0.8, 2)")
	T.check(c.dir.X == 0 and c.dir.Y == -6 and c.dir.Z == 0, "flat: the direction is (0, -RayLenM, 0)")
	local s = bed:stats()
	T.check(s.calls == 1 and s.samples == 1 and s.rays == 1 and s.hits == 1 and s.misses == 0 and s.cached == 0, "flat: stats count the call, the sample, the ray and the hit")
	local e = bed:cached(fish)
	T.check(e ~= nil and e.y == -2 and e.t == 0 and e.x == 1 and e.z == 2 and e.source == "ray", "flat: the cache entry holds y, t, x, z, source")
	local cast2, casts2 = rayOver(flat(-1))
	local bed2 = FishBed.new({ vec3 = Stub.Vector3.new }, cast2)
	bed2:bedY(fish, 0, 0, 0)
	T.check(typeof(casts2[1].origin.Magnitude) == "number" and near(casts2[1].origin.Y, 0.5), "vec3: an injected Vector3.new builds the stub's vectors (origin y 0.5 over water at 0)")
end

-- ---------------------------------------------------------------- slope, ledge (B3), hole (B4)
do
	local bed = FishBed.new({}, rayOver(slope(0.3)))
	T.check(near(bed:bedY("a", 4, 0, 0), -1.2), "slope(0.3): bedY at x = 4 is -1.2")
	T.check(near(bed:bedY("b", 10, 0, 0), -3.0), "slope(0.3): bedY at x = 10 is -3.0 (a second fish, its own entry)")
	T.check(near(bed:bedY("a", 4, 0, 0.1), -1.2) and bed:stats().cached == 1, "slope: the first fish's value is served from its cache")

	local lb = FishBed.new({}, rayOver(ledge(2.0, -1.0, 0.2)))
	T.check(lb:bedY("l", 1, 0, 0) == -1.0 and lb:bedY("r", 3, 0, 0) == -1.2, "ledge(2.0, 0.2): -1.0 left of the step, -1.2 right of it")
	-- B3: a fish seeking at 1 m/s across x = 2 at 60 Hz; the bed must step within 0.5 s of crossing
	local fish = {}
	local tStep: number? = nil
	for i = 0, 240 do
		local t = i / 60
		local y = lb:bedY(fish, t, 0, t) -- x = t at 1 m/s
		if tStep == nil and y == -1.2 then
			tStep = t
		end
	end
	T.check(tStep ~= nil and tStep >= 2.0 and tStep <= 2.5, string.format("B3: the ledge is seen at t = %.3f s, within 0.5 s of crossing x = 2 at 1 m/s", tStep or -1))
	local lbs = lb:stats()
	T.check(lbs.rays == 2 + 9, "B3: 4 s at 1 m/s re-samples every 0.5 m = 9 rays for the seeking fish (plus the two still ones)")

	-- B4: a hole under the fish -> the estimate
	local hb = FishBed.new({ fallback = function(_x: number, _z: number): number?
		return -0.9
	end }, rayOver(hole(0, 0, 1, flat(-1))))
	local y, source = hb:bedY("h", 0, 0, 0)
	T.check(y == -0.9 and source == "est", "B4: in the hole the ray misses and the fallback's -0.9 is used")
	local hs = hb:stats()
	T.check(hs.rays == 1 and hs.misses == 1 and hs.fallbacks == 1 and hs.hits == 0, "B4: the miss and the fallback are counted")
	y, source = hb:bedY("h", 3, 0, 0)
	T.check(y == -1 and source == "ray" and hb:stats().fallbacks == 1, "B4: out of the hole (moved 3 m) the ray hits again")

	-- no fallback at all
	local nb = FishBed.new({}, rayOver(hole(0, 0, 1, flat(-1))))
	y, source = nb:bedY("n", 0, 0, 0)
	T.check(y == FishBed.NO_BED and source == "none" and nb:stats().none == 1, "no fallback: the first sample in a hole gives NO_BED (-inf), source none")
	nb:bedY("n", 3, 0, 0)
	y, source = nb:bedY("n", 0, 0, 1)
	T.check(y == -1 and source == "none", "no fallback: back in the hole the fish keeps its last bed (-1) with source none")
	T.check(nb:bedY("n", 0, 0, 1.1) == -1 and nb:stats().cached == 1, "no fallback: ... and the miss is cached too, not re-asked every step")
	local fb = FishBed.new({ fallback = function(_x: number, _z: number): number?
		return nil
	end }, rayOver(hole(0, 0, 1, flat(-1))))
	T.check(fb:bedY("f", 0, 0, 0) == FishBed.NO_BED and fb:stats().fallbacks == 0, "a fallback returning nil counts as none, not as a fallback")

	-- beyond the ray's reach
	local deep = FishBed.new({ fallback = function(_x: number, _z: number): number?
		return -7
	end }, rayOver(flat(-7)))
	y, source = deep:bedY("d", 0, 0, 0)
	T.check(y == -7 and source == "est" and deep:stats().misses == 1, "a bed 7.5 m under the origin is past RayLenM 6: miss, fallback")
	local longer = FishBed.new({ RayLenM = 8 }, rayOver(flat(-7)))
	T.check(select(2, longer:bedY("d", 0, 0, 0)) == "ray", "... and RayLenM 8 reaches it")
	local junk = FishBed.new({}, function(_o: any, _d: any): number?
		return "nope" :: any
	end)
	T.check(junk:bedY("j", 0, 0, 0) == FishBed.NO_BED and junk:stats().misses == 1, "a raycast returning a non-number is a miss")
end

-- ---------------------------------------------------------------- cache cadence (B8) and the move threshold
do
	local bed = FishBed.new({}, rayOver(flat(-1)))
	local fish = {}
	for i = 0, 600 do
		bed:bedY(fish, 0, 0, i / 60) -- a still fish, 10 s at 60 Hz
	end
	local s = bed:stats()
	T.eq(s.rays, 21, "B8: a still fish for 10 s costs exactly 20 rays + the first")
	T.check(s.calls == 601 and s.cached == 580, "B8: 601 calls, 580 answered from the cache")

	local mb = FishBed.new({}, rayOver(flat(-1)))
	for i = 0, 8 do
		mb:bedY(fish, i * 0.125, 0, 0) -- time frozen, moving 0.125 m per call
	end
	T.eq(mb:stats().rays, 3, "move threshold: at 0.125 m per call a ray every 4 calls (0.5 m): calls 0, 4, 8")
	local mz = FishBed.new({}, rayOver(flat(-1)))
	for i = 0, 8 do
		mz:bedY(fish, 0, i * 0.125, 0)
	end
	T.eq(mz:stats().rays, 3, "move threshold: the same along z")
	local every = FishBed.new({ BedSampleS = 0, MoveResampleM = 0 }, rayOver(flat(-1)))
	for _ = 1, 5 do
		every:bedY(fish, 0, 0, 0)
	end
	T.eq(every:stats().rays, 5, "BedSampleS 0 and MoveResampleM 0: every call samples")

	-- the note's arithmetic: 8 fish x 2 rays/s
	local ab = FishBed.new({}, rayOver(slope(0.1)))
	local fishes = {}
	for f = 1, 8 do
		fishes[f] = { x = f }
	end
	for i = 0, 600 do
		for _, f in fishes do
			ab:bedY(f, f.x, 0, i / 60)
		end
	end
	local a = ab:stats()
	T.eq(a.rays, 168, "arithmetic: 8 still fish for 10 s = 8 x (20 + 1) = 168 rays")
	T.check(near((a.rays - 8) / 8 / 10, 2), "arithmetic: that is 2 rays/s per fish, 16 rays/s for 8, as the note says")
	T.check(near(ab:bedY(fishes[8], 8, 0, 10), -0.8), "arithmetic: each fish has its own bed (fish 8 at x = 8 on the 0.1 slope: -0.8)")

	-- forget and reset
	ab:forget(fishes[1])
	T.check(ab:cached(fishes[1]) == nil and ab:cached(fishes[2]) ~= nil, "forget drops one fish's entry only")
	ab:bedY(fishes[1], 1, 0, 10)
	T.eq(ab:stats().rays, 169, "... so its next call samples again")
	ab:reset()
	T.check(ab:cached(fishes[2]) == nil, "reset drops every entry")
	ab:resetStats()
	T.check(ab:stats().rays == 0 and ab:stats().calls == 0, "resetStats zeroes the counters")
	local st = ab:stats()
	st.rays = 99
	T.eq(ab:stats().rays, 0, "stats returns a copy")
end

-- ---------------------------------------------------------------- the rollback switch (B5) and sampleAt
do
	local cast, casts = rayOver(flat(-1))
	local bed = FishBed.new({ Enabled = false, fallback = function(_x: number, _z: number): number?
		return -1.06
	end }, cast)
	local y, source = bed:bedY("e", 0, 0, 0)
	T.check(y == -1.06 and source == "est" and #casts == 0, "Enabled = false: no ray is cast, the estimate (6 cm low, Dev1's data) is what the fish gets")
	T.check(bed:stats().rays == 0 and bed:stats().fallbacks == 1 and not bed:isEnabled(), "Enabled = false: rays 0, fallbacks 1")
	bed:setEnabled(true)
	y, source = bed:bedY("e", 0, 0, 1)
	T.check(y == -1 and source == "ray" and #casts == 1, "setEnabled(true): the next sample is a ray again (B5 passes with the ray, fails without)")
	local noRay = FishBed.new({ Enabled = false, fallback = flat(-1) }, nil)
	T.throws(function() noRay:setEnabled(true) end, "no raycast", "setEnabled(true) without a raycast function errors")

	-- sampleAt: one point, no cache (the home test)
	local before = bed:stats()
	local sy, ss = bed:sampleAt(5, 5)
	local after = bed:stats()
	T.check(sy == -1 and ss == "ray" and after.samples == before.samples + 1 and after.calls == before.calls and bed:cached({}) == nil, "sampleAt samples once and touches neither the cache nor the calls counter")
end

-- ---------------------------------------------------------------- negative control: the water surface (B7)
do
	local waterY = 0.3
	local stopsAtWater = function(origin: any, _dir: any): number?
		return math.min(origin.Y, waterY) -- IgnoreWater = false: the first thing under the origin is the surface
	end
	local bed = FishBed.new({ waterAt = function(_x: number, _z: number): number
		return waterY
	end }, stopsAtWater)
	local y, source = bed:bedY("w", 0, 0, 0)
	T.check(y == waterY and source == "ray", "negative control (B7): a ray that stops at the water reports the water as the bed; the sampler cannot tell, so IgnoreWater = true matters")
end

T.finish()
