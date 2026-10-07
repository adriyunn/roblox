local WorldClock = require("../src/Fishing/Shared/WorldClock")
-- does the transition sum depend on addition order?
local function sums(vals)
	local perms = { {1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1} }
	local seen = {}
	for _, p in perms do
		local s = vals[p[1]] + vals[p[2]] + vals[p[3]]
		seen[string.format("%.17g", s)] = true
	end
	local out = {}
	for k in seen do table.insert(out, k) end
	table.sort(out)
	return table.concat(out, " | ")
end
print("clear row sums:", sums({ 0.6, 0.35, 0.05 }))
print("overcast row sums:", sums({ 0.4, 0.3, 0.3 }))
print("rain row sums:", sums({ 0.3, 0.7, 0 }))
-- weather roll near the boundary: u*total vs acc
local c = WorldClock.new()
print("phase at 24.0:", WorldClock.phaseAt(24))
-- wave jump rain -> overcast
local r = WorldClock.new({ RainRampS = 10 })
WorldClock.setWeather(r, "rain", 1000)
WorldClock.advance(r, 100, nil, { RainRampS = 10 })
print("wave in full rain:", WorldClock.waveAmplitudeM(r), "(WAVE_M.rain =", WorldClock.WAVE_M.rain, ")")
WorldClock.setWeather(r, "overcast", 1000)
print("wave right after rain->overcast:", WorldClock.waveAmplitudeM(r), "rainNow", r.rainNow)
-- deserialize with dayLengthS = 0 then advance: hangs?
local bad = WorldClock.deserialize({ v = 1, timeH = 7, dayN = 1, weather = "clear", dayLengthS = 0 })
print("deserialize accepted dayLengthS = 0:", bad.dayLengthS)
print("advance(bad, 1) ... (a hang here is the bug)")
WorldClock.advance(bad, 1)
print("returned", bad.timeH, bad.dayN)
