--!strict
-- WorldClock (About Fishing F1 cloud work, F4 time and weather; Cloud, 2026-10-06; design/PARITY_rows_F2plus.md)
-- The in-game day and the weather, server-owned: a 24-hour clock that advances with real time, the
-- day phase (dawn/day/dusk/night) that SpeciesTable.spawnWeight and the bite rate read, a small
-- weather state machine (clear / overcast / rain) driven by an injected rng, and the numbers the client
-- needs (Lighting.ClockTime, rain intensity, wave amplitude capped so pool fish stay visible).
--
-- Written without the project files. Integration points a dev must wire:
--   * FishingServer: one WorldClock per server; call WorldClock.advance(clock, dt) from Heartbeat and
--     publish WorldClock.snapshot(clock) as attributes on a ReplicatedStorage folder (ClockTime, DayN,
--     Weather, Rain, WaveM) so every client reads one source of truth.
--   * FishPool / FishBrain: multiply the notice or bite chance by WorldClock.biteMul(clock) and pass
--     WorldClock.timeOfDay(clock) to SpeciesTable.spawnWeight.
--   * The water: FishPoolView hides fish under waves above ~0.1 (team finding, 2026-10-04), so
--     WorldClock.waveAmplitudeM never exceeds WaveMaxM = 0.1 whatever the weather.
--   * SaveData: serialize/deserialize keep dayN and timeH across server restarts if the design wants a
--     persistent world day; otherwise each server starts at StartHour.
-- Every rate below marked UNTUNED is a placeholder for the feel review and the demo recordings.

local WorldClock = {}

export type Weather = "clear" | "overcast" | "rain"
export type Phase = "dawn" | "day" | "dusk" | "night"

export type Clock = {
	timeH: number, -- 0 <= timeH < 24, in-game hours
	dayN: number, -- the in-game day, starts at 1
	dayLengthS: number, -- real seconds per in-game day
	weather: Weather,
	weatherLeftS: number, -- real seconds until the next weather roll
	rain: number, -- 0..1 target intensity for the current weather
	rainNow: number, -- 0..1 smoothed intensity the client shows
	waveNow: number, -- metres, the smoothed wave amplitude (ramps toward WAVE_M[weather], read capped)
	_opts: { [string]: any }?, -- the opts given to new(), so advance() and waveAmplitudeM() need not be handed them again
}

-- Defaults; everything here is a placeholder until the demo recordings fix the real pacing (UNTUNED).
WorldClock.DEFAULTS = {
	DayLengthS = 1440, -- 24 real minutes per in-game day
	StartHour = 7, -- servers start at 07:00, dawn
	WeatherMinS = 180, -- a weather state lasts 3..8 real minutes
	WeatherMaxS = 480,
	RainRampS = 20, -- rain fades in and out over 20 s
	WaveMaxM = 0.1, -- the hard cap: pool fish vanish under larger waves (team finding)
}

-- Phase boundaries in hours; SpeciesTable uses the same numbers so the two never disagree.
WorldClock.PHASES = { dawn = { 5, 8 }, day = { 8, 17 }, dusk = { 17, 20 } }

-- Weather transition table: from -> { to = weight }. Rain never follows rain directly. UNTUNED.
local TRANSITIONS: { [Weather]: { [Weather]: number } } = {
	clear = { clear = 0.6, overcast = 0.35, rain = 0.05 },
	overcast = { clear = 0.4, overcast = 0.3, rain = 0.3 },
	rain = { clear = 0.3, overcast = 0.7, rain = 0 },
}
WorldClock.TRANSITIONS = TRANSITIONS

-- Rain intensity per weather and the wave amplitude each weather ramps toward (metres, before the cap).
local RAIN: { [Weather]: number } = { clear = 0, overcast = 0, rain = 0.8 }
local WAVE_M: { [Weather]: number } = { clear = 0.02, overcast = 0.05, rain = 0.1 }
WorldClock.RAIN = RAIN
WorldClock.WAVE_M = WAVE_M

-- Bite multipliers by phase and weather (1.0 = the F1 baseline measured in daylight). UNTUNED.
local BITE_PHASE: { [Phase]: number } = { dawn = 1.2, day = 1.0, dusk = 1.2, night = 0.8 }
local BITE_WEATHER: { [Weather]: number } = { clear = 1.0, overcast = 1.1, rain = 1.15 }
WorldClock.BITE_PHASE = BITE_PHASE
WorldClock.BITE_WEATHER = BITE_WEATHER
local WEATHERS: { Weather } = { "clear", "overcast", "rain" }
local MAX_ROLLS = 1000 -- weather states one advance() may roll through before the timer is simply reset

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v < math.huge and v > -math.huge
end

-- A new clock. opts overrides any DEFAULTS key; rng (Roblox Random shape) rolls the first weather length.
function WorldClock.new(opts: { [string]: any }?, rng: any?): Clock
	local o = opts or {}
	local D = WorldClock.DEFAULTS
	local dayLengthS = o.DayLengthS or D.DayLengthS
	assert(finite(dayLengthS) and dayLengthS > 0, "WorldClock.new: DayLengthS must be a positive number (0 would make advance loop forever)")
	local clock: Clock = {
		timeH = o.StartHour or D.StartHour,
		dayN = 1,
		dayLengthS = dayLengthS,
		weather = "clear",
		weatherLeftS = WorldClock._rollLength(o, rng),
		rain = 0,
		rainNow = 0,
		waveNow = WAVE_M.clear,
		_opts = o,
	}
	return clock
end

-- How long the next weather state lasts (real seconds).
function WorldClock._rollLength(o: { [string]: any }, rng: any?): number
	local D = WorldClock.DEFAULTS
	local lo = o.WeatherMinS or D.WeatherMinS
	local hi = o.WeatherMaxS or D.WeatherMaxS
	assert(finite(lo) and finite(hi) and lo > 0 and hi >= lo, "WorldClock: WeatherMinS must be > 0 and WeatherMaxS >= WeatherMinS (a zero length would roll forever)")
	local u = if rng then rng:NextNumber() else 0.5
	return lo + (hi - lo) * u
end

-- The day phase for an hour in 0..24.
function WorldClock.phaseAt(timeH: number): Phase
	local P = WorldClock.PHASES
	local h = timeH % 24
	if h >= P.dawn[1] and h < P.dawn[2] then
		return "dawn"
	elseif h >= P.day[1] and h < P.day[2] then
		return "day"
	elseif h >= P.dusk[1] and h < P.dusk[2] then
		return "dusk"
	end
	return "night"
end

-- The clock's current phase.
function WorldClock.phase(clock: Clock): Phase
	return WorldClock.phaseAt(clock.timeH)
end

-- The hour in 0..24, the form SpeciesTable.spawnWeight takes.
function WorldClock.timeOfDay(clock: Clock): number
	return clock.timeH
end

-- Advance by dt real seconds: the hour, the day counter, the weather timer, the rain and wave ramps.
-- opts defaults to what new() was given. Returns the number of weather changes (0 or 1 for small dt).
function WorldClock.advance(clock: Clock, dt: number, rng: any?, opts: { [string]: any }?): number
	assert(finite(dt) and dt >= 0, "WorldClock.advance: dt must be a finite number >= 0")
	local o = opts or clock._opts or {}
	local D = WorldClock.DEFAULTS
	-- time of day (whole days by arithmetic, not a loop: an infinite or huge dt must never hang Heartbeat)
	local hours = dt / clock.dayLengthS * 24
	local t = clock.timeH + hours
	local days = math.floor(t / 24)
	if days > 0 then
		clock.dayN += days
		t -= days * 24
	end
	if t >= 24 then -- float fix-up at an exact multiple of 24
		t -= 24
		clock.dayN += 1
	end
	clock.timeH = math.max(t, 0)
	-- weather
	local changes = 0
	clock.weatherLeftS -= dt
	while clock.weatherLeftS <= 0 do
		clock.weather = WorldClock._nextWeather(clock.weather, rng)
		clock.rain = RAIN[clock.weather]
		clock.weatherLeftS += WorldClock._rollLength(o, rng)
		changes += 1
		if changes >= MAX_ROLLS then -- a dt spanning more states than this: skip them and start a fresh timer
			clock.weatherLeftS = WorldClock._rollLength(o, rng)
			break
		end
	end
	-- rain ramp toward the target
	local ramp = o.RainRampS or D.RainRampS
	local step = if ramp > 0 then dt / ramp else 1
	if clock.rainNow < clock.rain then
		clock.rainNow = math.min(clock.rain, clock.rainNow + step)
	elseif clock.rainNow > clock.rain then
		clock.rainNow = math.max(clock.rain, clock.rainNow - step)
	end
	-- wave ramp toward the weather's amplitude at the rain's pace (the whole clear..rain swing over
	-- RainRampS), from wherever it was: the surface never jumps at any weather change
	local waveTarget = WAVE_M[clock.weather]
	local waveStep = (WAVE_M.rain - WAVE_M.clear) * step
	if clock.waveNow < waveTarget then
		clock.waveNow = math.min(waveTarget, clock.waveNow + waveStep)
	elseif clock.waveNow > waveTarget then
		clock.waveNow = math.max(waveTarget, clock.waveNow - waveStep)
	end
	return changes
end

-- Roll the next weather from the transition table with one rng draw (0.5 when no rng: deterministic).
function WorldClock._nextWeather(from: Weather, rng: any?): Weather
	local row = TRANSITIONS[from]
	local total = 0
	for _, w in row do
		total += w
	end
	local u = (if rng then rng:NextNumber() else 0.5) * total
	local acc = 0
	for _, name in WEATHERS do
		acc += row[name]
		if u < acc then
			return name
		end
	end
	return "overcast"
end

-- Force a weather state (dev verb, the feel review): sets the target and a fresh timer.
function WorldClock.setWeather(clock: Clock, weather: Weather, lengthS: number?)
	assert(TRANSITIONS[weather], "WorldClock.setWeather: unknown weather " .. tostring(weather))
	clock.weather = weather
	clock.rain = RAIN[weather]
	clock.weatherLeftS = lengthS or WorldClock.DEFAULTS.WeatherMinS
end

-- Force the hour (dev verb). Keeps the day counter.
function WorldClock.setTime(clock: Clock, timeH: number)
	assert(timeH >= 0 and timeH < 24, "WorldClock.setTime: hour must be in [0, 24)")
	clock.timeH = timeH
end

-- Wave amplitude in metres for the water surface (the ramped waveNow), never above WaveMaxM (pool fish
-- must stay visible). opts defaults to what new() was given.
function WorldClock.waveAmplitudeM(clock: Clock, opts: { [string]: any }?): number
	local o: { [string]: any } = opts or clock._opts or {}
	local cap = o.WaveMaxM or WorldClock.DEFAULTS.WaveMaxM
	return math.min(clock.waveNow, cap)
end

-- The combined bite multiplier for the current phase and weather.
function WorldClock.biteMul(clock: Clock): number
	return BITE_PHASE[WorldClock.phase(clock)] * BITE_WEATHER[clock.weather]
end

-- Sun height in -1..1 for lighting: 1 at 12:00, 0 at 06:00 and 18:00, -1 at 00:00.
function WorldClock.sun(clock: Clock): number
	return -math.cos(clock.timeH / 24 * 2 * math.pi)
end

-- What the server publishes each tick (plain values, attribute-safe).
function WorldClock.snapshot(clock: Clock): { [string]: any }
	return {
		ClockTime = clock.timeH, -- Lighting.ClockTime takes 0..24 directly
		DayN = clock.dayN,
		Phase = WorldClock.phase(clock),
		Weather = clock.weather,
		Rain = clock.rainNow,
		WaveM = WorldClock.waveAmplitudeM(clock),
		Sun = WorldClock.sun(clock),
	}
end

-- JSON-safe state for SaveData (a persistent world day) or a server hand-over.
function WorldClock.serialize(clock: Clock): { [string]: any }
	return {
		v = 1,
		timeH = clock.timeH,
		dayN = clock.dayN,
		dayLengthS = clock.dayLengthS,
		weather = clock.weather,
		weatherLeftS = clock.weatherLeftS,
		rain = clock.rain,
		rainNow = clock.rainNow,
		waveNow = clock.waveNow,
	}
end

-- The inverse of serialize; refuses bad versions, out-of-range hours and non-positive or non-numeric
-- lengths so a corrupt save cannot freeze the day or hang advance().
function WorldClock.deserialize(t: { [string]: any }): Clock
	assert(typeof(t) == "table" and t.v == 1, "WorldClock.deserialize: unsupported version " .. tostring(typeof(t) == "table" and t.v or t))
	assert(finite(t.timeH) and t.timeH >= 0 and t.timeH < 24, "WorldClock.deserialize: bad timeH")
	assert(finite(t.dayN) and t.dayN >= 1, "WorldClock.deserialize: bad dayN")
	assert(TRANSITIONS[t.weather], "WorldClock.deserialize: bad weather " .. tostring(t.weather))
	assert(t.dayLengthS == nil or (finite(t.dayLengthS) and t.dayLengthS > 0), "WorldClock.deserialize: bad dayLengthS")
	assert(t.weatherLeftS == nil or (finite(t.weatherLeftS) and t.weatherLeftS >= 0), "WorldClock.deserialize: bad weatherLeftS")
	assert(t.rain == nil or (finite(t.rain) and t.rain >= 0 and t.rain <= 1), "WorldClock.deserialize: bad rain")
	assert(t.rainNow == nil or (finite(t.rainNow) and t.rainNow >= 0 and t.rainNow <= 1), "WorldClock.deserialize: bad rainNow")
	assert(t.waveNow == nil or (finite(t.waveNow) and t.waveNow >= 0 and t.waveNow <= 1), "WorldClock.deserialize: bad waveNow")
	return {
		timeH = t.timeH,
		dayN = t.dayN,
		dayLengthS = t.dayLengthS or WorldClock.DEFAULTS.DayLengthS,
		weather = t.weather,
		weatherLeftS = t.weatherLeftS or WorldClock.DEFAULTS.WeatherMinS,
		rain = t.rain or RAIN[t.weather :: Weather],
		rainNow = t.rainNow or 0,
		waveNow = t.waveNow or WAVE_M[t.weather :: Weather], -- a save from before waveNow starts at its weather's amplitude
	}
end

return WorldClock
