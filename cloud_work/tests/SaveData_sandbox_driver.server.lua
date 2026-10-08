-- SaveData_sandbox_driver.server.lua (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- TEMPORARY. STUDIO ONLY. NOT PART OF THE GAME. A throwaway Script that exercises SaveData against the
-- real DataStore with Studio API access on (Game Settings > Security > Enable Studio Access to API
-- Services): load, get, set, isDirty, save, a clean save, a forced save, stats, PlayerRemoving and the
-- BindToClose flush, printing each step. It uses the store "PlayerData_sandbox", never Place1's real
-- records. Delete it after the sandbox session; nothing references it.
--
-- Where the module lives: put this Script in ServerScriptService with a `Fishing` folder next to it
-- holding Server/SaveData (the module's own requires are relative string paths). To run against the
-- live tree, replace the require with the Rojo path.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Fishing = script.Parent:WaitForChild("Fishing")
local SaveData = require(Fishing:WaitForChild("Server"):WaitForChild("SaveData"))

local TAG = "[SaveData sandbox]"
local function step(label, ...)
	print(TAG, label, ...)
end

local sd = SaveData.new({
	DataStoreService = DataStoreService,
	Players = Players,
	HttpService = HttpService,
	Enum = Enum,
	task = task,
	clock = os.time,
	warn = warn,
	jobId = game.JobId,
}, {
	storeName = "PlayerData_sandbox",
	schemaVersion = 1,
	defaults = function()
		return { coins = 0, visits = 0, gear = { rod = "rod_basic" } }
	end,
	autosaveS = 30,
})
step("jobId (a GUID in Studio when game.JobId is empty):", sd:jobId())

local function exercise(player)
	local profile, why = sd:load(player)
	step("load", player.Name, "->", why)
	if not profile then
		step("no profile (locked by another session? wait 30 min or clear the key); giving up")
		return
	end
	step("data on load: coins", profile:get("coins"), "visits", profile:get("visits"), "gear.rod", profile:get("gear.rod"), "readOnly", profile.readOnly)
	step("isDirty after load:", profile:isDirty(), "(expected false)")

	profile:set("visits", (profile:get("visits") or 0) + 1)
	profile:set("coins", (profile:get("coins") or 0) + 8)
	profile:set("gear.rod", "rod_carbon")
	step("after three set(): isDirty", profile:isDirty(), "(expected true)")

	local ok, reason = sd:save(player, "sandbox")
	step("save ->", ok, reason, "(expected true saved)")
	ok, reason = sd:save(player, "sandbox-clean")
	step("save again, nothing changed ->", ok, reason, "(expected false clean)")
	ok, reason = sd:save(player, "sandbox-forced", true)
	step("save forced ->", ok, reason, "(expected true saved; refreshes _lock.t)")

	local bad = pcall(function()
		profile:set("coins", 0 / 0)
	end)
	step("set(NaN) refused:", not bad, "(expected true: the profile stays saveable)")

	local st = sd:stats()
	step(string.format("stats: loads %d saves %d retries %d failures %d refused %d locked %d budgetWaits %d", st.loads, st.saves, st.retries, st.failures, st.refused, st.locked, st.budgetWaits))
	step("the raw record (GetAsync) for a look at _v, _lock, _savedAt:")
	local okGet, raw = pcall(function()
		return DataStoreService:GetDataStore("PlayerData_sandbox"):GetAsync(SaveData.keyFor(player))
	end)
	if okGet then
		print(TAG, HttpService:JSONEncode(raw))
	else
		step("GetAsync failed:", raw)
	end
	step("now leave the game (or stop the session): PlayerRemoving force-saves and releases the lock; BindToClose flushes")
end

Players.PlayerAdded:Connect(exercise)
for _, player in Players:GetPlayers() do
	task.spawn(exercise, player)
end

Players.PlayerRemoving:Connect(function(player)
	local ok, reason = sd:onPlayerRemoving(player)
	step("PlayerRemoving", player.Name, "->", ok, reason, "(expected true saved, then the lock is cleared)")
end)

game:BindToClose(function()
	local n = sd:flushAll("close")
	step("BindToClose flushed", n, "profile(s)")
end)

sd:startAutosave()
step("ready: join the sandbox; every step prints here")
