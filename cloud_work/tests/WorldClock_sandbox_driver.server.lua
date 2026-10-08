-- WorldClock_sandbox_driver.server.lua (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- TEMPORARY. STUDIO ONLY. NOT PART OF THE GAME. A throwaway Script that advances a WorldClock on
-- Heartbeat with a short day (4 real minutes), writes Lighting.ClockTime from snapshot().ClockTime and
-- the snapshot's values as attributes (ClockTime, DayN, Phase, Weather, Rain, WaveM, Sun) on a
-- ReplicatedStorage folder, and prints every weather change, so a dev can watch the sky and a client can
-- read the attributes. Delete it after the sandbox session; nothing references it.
--
-- Where the module lives: a `Fishing` folder next to this Script holding Shared/WorldClock, or the Rojo
-- path (ReplicatedStorage.Fishing.Shared.WorldClock) in the live tree.

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fishing = script.Parent:WaitForChild("Fishing")
local WorldClock = require(Fishing:WaitForChild("Shared"):WaitForChild("WorldClock"))

local TAG = "[WorldClock sandbox]"
local OPTS = { DayLengthS = 240, WeatherMinS = 20, WeatherMaxS = 60, RainRampS = 5 } -- fast for watching
local rng = Random.new(20261008)
local clock = WorldClock.new(OPTS, rng)

local folder = ReplicatedStorage:FindFirstChild("World") or Instance.new("Folder")
folder.Name = "World"
folder.Parent = ReplicatedStorage

local function publish()
	local snap = WorldClock.snapshot(clock)
	Lighting.ClockTime = snap.ClockTime
	for key, value in snap do
		folder:SetAttribute(key, value)
	end
	return snap
end

local lastPhase = WorldClock.phase(clock)
local lastPrint = 0
RunService.Heartbeat:Connect(function(dt)
	local changes = WorldClock.advance(clock, dt, rng, OPTS)
	local snap = publish()
	if changes > 0 then
		print(TAG, string.format("weather -> %s at %02d:%02d (day %d), waves %.3f m, bite x%.2f", snap.Weather, math.floor(snap.ClockTime), math.floor(snap.ClockTime % 1 * 60), snap.DayN, snap.WaveM, WorldClock.biteMul(clock)))
	end
	if snap.Phase ~= lastPhase then
		print(TAG, string.format("phase %s -> %s at %05.2f h", lastPhase, snap.Phase, snap.ClockTime))
		lastPhase = snap.Phase
	end
	if os.clock() - lastPrint >= 10 then
		lastPrint = os.clock()
		print(TAG, string.format("%05.2f h day %d %s %s rain %.2f waves %.3f m sun %.2f", snap.ClockTime, snap.DayN, snap.Phase, snap.Weather, snap.Rain, snap.WaveM, snap.Sun))
	end
end)

-- dev verbs: set the attributes on the folder to force a state (a client or the command bar can too)
folder:GetAttributeChangedSignal("ForceWeather"):Connect(function()
	local w = folder:GetAttribute("ForceWeather")
	if w == "clear" or w == "overcast" or w == "rain" then
		WorldClock.setWeather(clock, w, 60)
		print(TAG, "forced weather", w)
	end
end)
folder:GetAttributeChangedSignal("ForceHour"):Connect(function()
	local h = folder:GetAttribute("ForceHour")
	if typeof(h) == "number" and h >= 0 and h < 24 then
		WorldClock.setTime(clock, h)
		print(TAG, "forced hour", h)
	end
end)

publish()
print(TAG, "ready: a 4-minute day from 07:00; set ReplicatedStorage.World attributes ForceWeather (clear|overcast|rain) or ForceHour (0..24) to drive it")
