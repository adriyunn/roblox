--!nocheck
--!nolint UnknownGlobal
-- ProfileService.server.lua (About Fishing F1, WS-S + WS-N wiring; Cloud, 2026-10-08; design/WSS_savedata.md, design/WSN_net_v3_messages.md)
-- A WIRING SCRIPT FOR STUDIO, NOT A PURE MODULE: the one file under cloud_work/src that touches the Roblox
-- globals (game, script, Instance, task, warn, Enum). It builds SaveData + InventoryService from the real
-- services, loads a profile per player, routes one RemoteEvent per v3 message to the handlers, autosaves
-- and flushes on close. A dev replaces it with, or merges it into, FishingServer (Dev1 holds the Studio
-- lock). It has no offline suite because it is not pure; the gate only compiles it (-O0/-O1/-O2).
-- The two hot-comments above exist only because the offline luau-analyze has no Roblox type definitions
-- (every `game` would be an unknown global); Studio and luau-lsp with the Roblox types still check it.
-- Remove them when merging into FishingServer.
--
-- WRITTEN WITHOUT THE PROJECT FILES. What a dev checks before running it:
--   * Where it lives: ServerScriptService.ProfileService with a `Fishing` folder next to it holding
--     Server/SaveData, Server/InventoryService and Shared/* (the script.Parent-relative requires below), or
--     the live Rojo tree (the commented requires). The modules use string requires ("../Shared/TackleBox"),
--     the same convention as every cloud module.
--   * The player's state: read from a "State" attribute on the Player (PLACEHOLDER). FishingServer owns the
--     F1 state machine and StateRules; the real call passes that state instead of the attribute.
--   * The wire: payloads are plain tables on RemoteEvents under ReplicatedStorage.Fishing.Net.V3, one per
--     message, named like the schema. Dev3's FishingNet v3 codec replaces FireClient / OnServerEvent with
--     the compact bytes and RequestGuard sits in front; the handler calls do not change.
--   * SetOption (WS-H) has no handler here: InventoryService.dispatch counts it as rejected until the
--     options handler lands in FishingServer.
--   * DataStores in Studio need "Enable Studio Access to API Services" (Game Settings > Security); the
--     store name below is the real one, so point it at a sandbox store ("PlayerData_sandbox") for tests.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- requires, script.Parent-relative (a `Fishing` folder next to this script)
local Fishing = script.Parent:WaitForChild("Fishing")
local Server = Fishing:WaitForChild("Server")
local Shared = Fishing:WaitForChild("Shared")
local SaveData = require(Server:WaitForChild("SaveData"))
local InventoryService = require(Server:WaitForChild("InventoryService"))
local NetSchemaV3 = require(Shared:WaitForChild("NetSchemaV3"))
-- the live tree instead (Rojo map Phase4/rojo/default.project.json; confirm the paths):
-- local SaveData = require(game:GetService("ServerScriptService").Fishing.Server.SaveData)
-- local InventoryService = require(game:GetService("ServerScriptService").Fishing.Server.InventoryService)
-- local NetSchemaV3 = require(ReplicatedStorage.Fishing.Shared.NetSchemaV3)

local STORE_NAME = "PlayerData" -- "PlayerData_sandbox" for a sandbox place
local SCHEMA_VERSION = 1
local LOAD_RETRY_S = 5 -- WSS risk 2: retry a locked record every 5 s for 30 s, then kick
local LOAD_RETRIES = 6

-- ---------------------------------------------------------------- the net: one RemoteEvent per v3 message
local netFolder = ReplicatedStorage:FindFirstChild("Fishing") or Instance.new("Folder")
netFolder.Name = "Fishing"
netFolder.Parent = ReplicatedStorage
local net = netFolder:FindFirstChild("Net") or Instance.new("Folder")
net.Name = "Net"
net.Parent = netFolder
local v3 = net:FindFirstChild("V3") or Instance.new("Folder")
v3.Name = "V3"
v3.Parent = net

local remotes = {}
for name, message in NetSchemaV3.MESSAGES do
	local ev = v3:FindFirstChild(name) or Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = v3
	remotes[name] = ev
end

-- ---------------------------------------------------------------- SaveData + InventoryService
local sd = SaveData.new({
	DataStoreService = DataStoreService,
	Players = Players,
	HttpService = HttpService,
	Enum = Enum,
	task = task,
	clock = os.time, -- a wall clock shared by every server: the lock timestamp is compared across servers
	warn = warn,
	jobId = game.JobId, -- "" in Studio: SaveData mints a GUID so the lock still means something
}, {
	storeName = STORE_NAME,
	schemaVersion = SCHEMA_VERSION,
	defaults = InventoryService.defaults, -- box, coins, loadout, catchLog
	migrations = {},
})

local svc = InventoryService.new({
	saveData = sd,
	net = {
		send = function(player, name, payload)
			local ev = remotes[name]
			if ev then
				ev:FireClient(player, payload)
			end
		end,
	},
	schema = NetSchemaV3,
	clock = os.clock,
	warn = warn,
})

-- PLACEHOLDER for StateRules: FishingServer passes the player's real F1 state here.
local function stateOf(player)
	local state = player:GetAttribute("State")
	return if typeof(state) == "string" then state else "Walking"
end

for name, message in NetSchemaV3.MESSAGES do
	if message.dir == "C2S" then
		remotes[name].OnServerEvent:Connect(function(player, payload)
			svc:dispatch(name, player, payload, stateOf(player))
		end)
	end
end

-- ---------------------------------------------------------------- players
local function onPlayerAdded(player)
	local profile, why
	for attempt = 1, LOAD_RETRIES do
		profile, why = sd:load(player)
		if profile or why == "left" then
			break
		end
		warn(string.format("ProfileService: load for %s: %s (attempt %d of %d)", player.Name, tostring(why), attempt, LOAD_RETRIES))
		task.wait(LOAD_RETRY_S)
		if player.Parent == nil then
			return -- left while we waited; nothing was loaded
		end
	end
	if not profile then
		if why ~= "left" then
			player:Kick("Your progress is still held by another server. Please rejoin in a few minutes.")
		end
		return
	end
	if player.Parent == nil then
		sd:onPlayerRemoving(player) -- left between the load and here: save and give the lock back
		return
	end
	svc:onProfileLoaded(player, profile, why)
	print(string.format("ProfileService: %s ready (%s%s)", player.Name, tostring(why), if profile.readOnly then ", read-only" else ""))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player) -- players already in (the script started late in Studio)
end

Players.PlayerRemoving:Connect(function(player)
	local ok, why = sd:onPlayerRemoving(player) -- force-save then release (always, even mid-load)
	svc:onProfileReleased(player)
	if not ok and why ~= "not-loaded" and why ~= "read-only" then
		warn(string.format("ProfileService: leave save for %s: %s", player.Name, tostring(why)))
	end
end)

game:BindToClose(function()
	local saved = sd:flushAll("close")
	print(string.format("ProfileService: BindToClose saved %d profile(s)", saved))
end)

sd:startAutosave()
print("ProfileService: up; store " .. STORE_NAME .. ", schema " .. SCHEMA_VERSION .. ", " .. tostring(#NetSchemaV3.ids()) .. " v3 remotes under ReplicatedStorage.Fishing.Net.V3")
