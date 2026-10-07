--!strict
-- worldclock_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- WorldClock under the Luau CLI: the hour and day roll over, phases match SpeciesTable's boundaries,
-- the weather machine rolls from the table with a seeded rng, rain ramps, waves never pass the cap,
-- snapshot and serialize round-trip, and a corrupt save is refused (negative control).
-- Run from this folder: luau worldclock_test.luau

local Stub = require("./RobloxStub")
local WorldClock = require("../src/Fishing/Shared/WorldClock")
local T = Stub.harness("worldclock_test")

-- a tiny seeded LCG with the Roblox Random shape
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

-- W1-W4: construction and the hour
local c = WorldClock.new({ DayLengthS = 240 }) -- 4 real minutes per day: 10 s = 1 hour
T.eq(c.timeH, 7, "W1 starts at StartHour 07:00")
T.eq(c.dayN, 1, "W2 starts on day 1")
WorldClock.advance(c, 10)
T.eq(c.timeH, 8, "W3 10 s advances one hour at DayLengthS 240")
WorldClock.advance(c, 160) -- +16 h -> 24:00 -> day 2, 00:00
T.eq(c.timeH, 0, "W4 the hour wraps at 24")
T.eq(c.dayN, 2, "W5 the day counter increments on wrap")
WorldClock.advance(c, 240 * 2 + 10) -- two full days + 1 h
T.eq(c.dayN, 4, "W6 a long dt rolls several days")
T.eq(c.timeH, 1, "W7 and keeps the remainder hour")

-- W8-W13: phases (the same boundaries SpeciesTable uses)
T.eq(WorldClock.phaseAt(5), "dawn", "W8 05:00 is dawn")
T.eq(WorldClock.phaseAt(7.99), "dawn", "W9 07:59 is dawn")
T.eq(WorldClock.phaseAt(8), "day", "W10 08:00 is day")
T.eq(WorldClock.phaseAt(17), "dusk", "W11 17:00 is dusk")
T.eq(WorldClock.phaseAt(20), "night", "W12 20:00 is night")
T.eq(WorldClock.phaseAt(4.5), "night", "W13 04:30 is night")

-- W14-W18: weather machine with a seeded rng is deterministic and follows the table
local rng = lcg(42)
local w = WorldClock.new({ WeatherMinS = 10, WeatherMaxS = 10 }, rng)
T.eq(w.weather, "clear", "W14 weather starts clear")
local seen: { [string]: number } = { clear = 0, overcast = 0, rain = 0 }
local rainAfterRain = 0
local changes = 0
for _ = 1, 400 do
	local before = w.weather
	changes += WorldClock.advance(w, 10, rng, { WeatherMinS = 10, WeatherMaxS = 10 })
	seen[w.weather] += 1
	if before == "rain" and w.weather == "rain" then
		rainAfterRain += 1
	end
end
T.eq(changes, 400, "W15 one change per 10 s window at a fixed 10 s length")
T.check(seen.clear > 0 and seen.overcast > 0 and seen.rain > 0, "W16 every weather occurs over 400 rolls")
T.eq(rainAfterRain, 0, "W17 rain never follows rain directly (table weight 0)")
local rng2 = lcg(42)
local w2 = WorldClock.new({ WeatherMinS = 10, WeatherMaxS = 10 }, rng2)
local same = true
local rng1 = lcg(42)
local w1 = WorldClock.new({ WeatherMinS = 10, WeatherMaxS = 10 }, rng1)
for _ = 1, 100 do
	WorldClock.advance(w1, 10, rng1, { WeatherMinS = 10, WeatherMaxS = 10 })
	WorldClock.advance(w2, 10, rng2, { WeatherMinS = 10, WeatherMaxS = 10 })
	if w1.weather ~= w2.weather then
		same = false
	end
end
T.check(same, "W18 the same seed gives the same weather sequence")

-- W19-W23: rain ramp and waves
local r = WorldClock.new({ RainRampS = 10 })
WorldClock.setWeather(r, "rain", 1000)
T.eq(r.rain, 0.8, "W19 rain target 0.8 in rain")
T.eq(r.rainNow, 0, "W20 rainNow starts at 0")
WorldClock.advance(r, 5, nil, { RainRampS = 10 })
T.eq(r.rainNow, 0.5, "W21 rain ramps linearly (5 s of a 10 s ramp = 0.5)")
WorldClock.advance(r, 10, nil, { RainRampS = 10 })
T.eq(r.rainNow, 0.8, "W22 rain stops at the target")
T.check(WorldClock.waveAmplitudeM(r) <= WorldClock.DEFAULTS.WaveMaxM + 1e-9, "W23 waves never pass WaveMaxM 0.1")
WorldClock.setWeather(r, "clear", 1000)
WorldClock.advance(r, 20, nil, { RainRampS = 10 })
T.eq(r.rainNow, 0, "W24 rain ramps back down after clear")
T.eq(WorldClock.waveAmplitudeM(r), 0.02, "W25 clear water wave 0.02 m")

-- W26-W28: bite multiplier and sun
local b = WorldClock.new()
WorldClock.setTime(b, 12)
T.eq(WorldClock.biteMul(b), 1.0, "W26 day + clear = 1.0")
WorldClock.setTime(b, 6)
WorldClock.setWeather(b, "rain")
T.eq(WorldClock.biteMul(b), 1.2 * 1.15, "W27 dawn + rain multiplies")
WorldClock.setTime(b, 12)
T.check(math.abs(WorldClock.sun(b) - 1) < 1e-9, "W28 sun is 1 at noon")
WorldClock.setTime(b, 0)
T.check(math.abs(WorldClock.sun(b) + 1) < 1e-9, "W29 sun is -1 at midnight")

-- W30-W33: snapshot and serialize round trip
local s = WorldClock.snapshot(b)
T.eq(s.ClockTime, 0, "W30 snapshot ClockTime")
T.eq(s.Weather, "rain", "W31 snapshot Weather")
local R = Stub.new()
local json = R.HttpService:JSONEncode(WorldClock.serialize(b))
local back = WorldClock.deserialize(R.HttpService:JSONDecode(json))
T.eq(back.timeH, b.timeH, "W32 round trip timeH")
T.eq(back.weather, b.weather, "W33 round trip weather")
T.eq(back.dayN, b.dayN, "W34 round trip dayN")

-- W35-W37: negative controls
T.throws(function() WorldClock.deserialize({ v = 2 }) end, "unsupported version", "W35 deserialize refuses v = 2")
T.throws(function() WorldClock.deserialize({ v = 1, timeH = 25, dayN = 1, weather = "clear" }) end, "bad timeH", "W36 deserialize refuses hour 25")
T.throws(function() WorldClock.setWeather(b, "snow" :: any) end, "unknown weather", "W37 setWeather refuses an unknown state")

-- R4 (F4): a corrupt save or a zero config must error, never hang Heartbeat
T.throws(function() WorldClock.deserialize({ v = 1, timeH = 7, dayN = 1, weather = "clear", dayLengthS = 0 }) end, "bad dayLengthS", "R4a (F4) deserialize refuses dayLengthS 0 (advance looped forever on it)")
T.throws(function() WorldClock.new({ WeatherMinS = 0, WeatherMaxS = 0 }) end, "WeatherMinS", "R4b (F4) new refuses a zero weather length (advance looped forever on it)")
T.throws(function() WorldClock.advance(WorldClock.new(), math.huge) end, "finite", "R4c (F4) advance refuses an infinite dt (on the old code this check hangs instead of failing)")

T.finish()
