--!strict
-- FishBed (About Fishing F1, WS-D bed raycast; Cloud, 2026-10-08; design/WSD_bed_raycast.md)
-- A per-fish bed-height sampler: one ray straight down from above the water, cached per fish and
-- re-sampled every BedSampleS or after the fish moved MoveResampleM, with the FishZones.depthAt estimate
-- as the fallback when the ray misses. Counts rays, hits, misses and fallbacks so the cost in the note
-- (8 fish x 2 rays/s) is checked, not guessed.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * The Studio adapter (server in FishingServer, client in FishPoolView), the only Roblox-touching lines:
--       local params = RaycastParams.new()
--       params.FilterType = Enum.RaycastFilterType.Include
--       params.FilterDescendantsInstances = { workspace.Terrain, bedPartsFolder } -- CollectionService tag FishBed
--       params.IgnoreWater = true -- without it the ray stops at the surface and bedY == waterY (note B7)
--       local bed = FishBed.new({ waterAt = WaterTruth.surfaceY, fallback = <bed Y from FishZones.depthAt>,
--           vec3 = Vector3.new, BedSampleS = C.AF.Fish.BedSampleS, MoveResampleM = C.AF.Fish.BedSampleMoveM,
--           RayLenM = C.AF.Fish.BedRayLenM, Enabled = C.AF.Fish.BedRayEnabled },
--           function(origin, direction)
--               local hit = workspace:Raycast(origin, direction, params)
--               return if hit then hit.Position.Y else nil
--           end)
--   * FishBrain each step: fish.bedY = bed:bedY(fish, fish.x, fish.z, now) (now in seconds, one clock).
--     FishPool's home test: bed:sampleAt(x, z) (no cache: one point, sampled once).
--   * Config keys (C.AF.Fish, the note's section 2): BedSampleS 0.5, BedSampleMoveM 0.5 (MoveResampleM here),
--     BedRayLenM 6 (RayLenM), BedRayEnabled true (Enabled; false = fallback only, the rollback switch).
-- Decisions a dev must know:
--   * fallback(x, z) must return a bed HEIGHT (Y) in the ray's frame, not a depth: if FishZones.depthAt
--     gives metres below the surface, wrap it: function(x, z) return waterAt(x, z) - FishZones.depthAt(x, z) end.
--   * Vectors are built by the injected opts.vec3(x, y, z) (default: a plain { X, Y, Z } table), so the pure
--     module never names Vector3; the adapter passes Vector3.new. The origin is waterAt(x, z) + StartAboveM
--     (above the surface, never the fish pivot: a pivot inside the terrain would miss), the direction
--     (0, -RayLenM, 0).
--   * Before the first sample a fish has no bed; when the ray misses and there is no fallback, bedY returns
--     the last value it had (NO_BED = -inf before the first) with source "none" and keeps the cache stamp,
--     so a missing bed is not re-asked every step.
--   * The cache is keyed by the `fish` value with weak keys: a fish table is forgotten with the fish; a
--     numeric or string id must be released with forget(fish).
-- No Roblox globals.

local FishBed = {}
FishBed.__index = FishBed

export type Vec3 = any
export type Raycast = (origin: Vec3, direction: Vec3) -> number?
export type Source = "ray" | "est" | "none"
export type Opts = {
	BedSampleS: number?, -- re-sample this often (s); 0 = every call
	MoveResampleM: number?, -- or sooner after moving this far (m); 0 = every call
	StartAboveM: number?, -- the ray starts this far above the water surface
	RayLenM: number?, -- ray length down from there
	Enabled: boolean?, -- false = never cast, fallback only (the rollback switch)
	fallback: ((x: number, z: number) -> number?)?, -- the estimate (a bed Y), used when the ray misses
	waterAt: ((x: number, z: number) -> number)?, -- the surface height (default 0)
	vec3: ((x: number, y: number, z: number) -> Vec3)?, -- Vector3.new in Studio
}
export type Entry = { y: number, t: number, x: number, z: number, source: Source }
export type Stats = { calls: number, cached: number, samples: number, rays: number, hits: number, misses: number, fallbacks: number, none: number }

FishBed.DEFAULTS = { BedSampleS = 0.5, MoveResampleM = 0.5, StartAboveM = 0.5, RayLenM = 6.0, Enabled = true }
FishBed.NO_BED = -math.huge

type Fields = {
	_raycast: Raycast?,
	_sampleS: number,
	_moveM2: number,
	_aboveM: number,
	_lenM: number,
	_enabled: boolean,
	_fallback: ((x: number, z: number) -> number?)?,
	_waterAt: (x: number, z: number) -> number,
	_vec3: (x: number, y: number, z: number) -> Vec3,
	_cache: { [any]: Entry },
	_stats: Stats,
}
export type FishBed = typeof(setmetatable({} :: Fields, FishBed))

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v < math.huge and v > -math.huge
end

local function plainVec3(x: number, y: number, z: number): Vec3
	return { X = x, Y = y, Z = z }
end

local function zero(_x: number, _z: number): number
	return 0
end

-- A sampler. opts overrides DEFAULTS; raycast is required unless Enabled = false.
function FishBed.new(opts: Opts?, raycast: Raycast?): FishBed
	local o: Opts = opts or {}
	local D = FishBed.DEFAULTS
	local sampleS = if o.BedSampleS ~= nil then o.BedSampleS else D.BedSampleS
	local moveM = if o.MoveResampleM ~= nil then o.MoveResampleM else D.MoveResampleM
	local aboveM = if o.StartAboveM ~= nil then o.StartAboveM else D.StartAboveM
	local lenM = if o.RayLenM ~= nil then o.RayLenM else D.RayLenM
	local enabled = if o.Enabled ~= nil then o.Enabled else D.Enabled
	assert(finite(sampleS) and sampleS >= 0, "FishBed.new: BedSampleS must be a number >= 0")
	assert(finite(moveM) and moveM >= 0, "FishBed.new: MoveResampleM must be a number >= 0")
	assert(finite(aboveM) and aboveM >= 0, "FishBed.new: StartAboveM must be a number >= 0")
	assert(finite(lenM) and lenM > 0, "FishBed.new: RayLenM must be a number > 0")
	assert(typeof(enabled) == "boolean", "FishBed.new: Enabled must be a boolean")
	assert(not enabled or typeof(raycast) == "function", "FishBed.new: a raycast function is required unless Enabled = false")
	assert(o.fallback == nil or typeof(o.fallback) == "function", "FishBed.new: fallback must be a function (x, z) -> bed Y")
	assert(o.waterAt == nil or typeof(o.waterAt) == "function", "FishBed.new: waterAt must be a function (x, z) -> surface Y")
	assert(o.vec3 == nil or typeof(o.vec3) == "function", "FishBed.new: vec3 must be a function (x, y, z) -> vector")
	local cache: { [any]: Entry } = setmetatable({}, { __mode = "k" }) :: any
	local self: Fields = {
		_raycast = raycast,
		_sampleS = sampleS,
		_moveM2 = moveM * moveM,
		_aboveM = aboveM,
		_lenM = lenM,
		_enabled = enabled,
		_fallback = o.fallback,
		_waterAt = o.waterAt or zero,
		_vec3 = o.vec3 or plainVec3,
		_cache = cache,
		_stats = { calls = 0, cached = 0, samples = 0, rays = 0, hits = 0, misses = 0, fallbacks = 0, none = 0 },
	}
	return setmetatable(self, FishBed)
end

-- One fresh sample at (x, z), no cache: the ray (when enabled), else the fallback. Returns y, source.
function FishBed.sampleAt(self: FishBed, x: number, z: number): (number?, Source)
	local y: number? = nil
	local source: Source = "none"
	self._stats.samples += 1
	local raycast = self._raycast
	if self._enabled and raycast then
		self._stats.rays += 1
		local top = self._waterAt(x, z) + self._aboveM
		local hit = raycast(self._vec3(x, top, z), self._vec3(0, -self._lenM, 0))
		if finite(hit) then
			self._stats.hits += 1
			y = hit
			source = "ray"
		else
			self._stats.misses += 1
		end
	end
	local fallback = self._fallback
	if y == nil and fallback then
		local est = fallback(x, z)
		if finite(est) then
			self._stats.fallbacks += 1
			y = est
			source = "est"
		end
	end
	if y == nil then
		self._stats.none += 1
	end
	return y, source
end

-- The bed height under a fish at (x, z) at time t: the cached value unless BedSampleS passed or the
-- fish moved MoveResampleM since the last sample, then a fresh one. Returns y, source.
function FishBed.bedY(self: FishBed, fish: any, x: number, z: number, t: number): (number, Source)
	self._stats.calls += 1
	local e = self._cache[fish]
	if e then
		local dx, dz = x - e.x, z - e.z
		if t - e.t < self._sampleS and dx * dx + dz * dz < self._moveM2 then
			self._stats.cached += 1
			return e.y, e.source
		end
	end
	local y, source = self:sampleAt(x, z)
	if y == nil then
		-- nothing under the fish right now: keep what it had (or no bed) and the new stamp
		e = { y = if e then e.y else FishBed.NO_BED, t = t, x = x, z = z, source = "none" }
	else
		e = { y = y, t = t, x = x, z = z, source = source }
	end
	self._cache[fish] = e
	return e.y, e.source
end

-- A copy of a fish's cache entry, or nil before its first sample.
function FishBed.cached(self: FishBed, fish: any): Entry?
	local e = self._cache[fish]
	return if e then table.clone(e) else nil
end

-- Drops a fish's cache entry (a despawn; needed for non-table fish keys).
function FishBed.forget(self: FishBed, fish: any)
	self._cache[fish] = nil
end

-- Drops every cache entry.
function FishBed.reset(self: FishBed)
	for k in self._cache do
		self._cache[k] = nil
	end
end

function FishBed.setEnabled(self: FishBed, enabled: boolean)
	assert(not enabled or self._raycast ~= nil, "FishBed.setEnabled: no raycast function to enable")
	self._enabled = enabled
end

function FishBed.isEnabled(self: FishBed): boolean
	return self._enabled
end

-- Counters: calls (bedY), cached (answered from the cache), samples, rays, hits, misses, fallbacks, none.
function FishBed.stats(self: FishBed): Stats
	return table.clone(self._stats)
end

function FishBed.resetStats(self: FishBed)
	self._stats = { calls = 0, cached = 0, samples = 0, rays = 0, hits = 0, misses = 0, fallbacks = 0, none = 0 }
end

return FishBed
