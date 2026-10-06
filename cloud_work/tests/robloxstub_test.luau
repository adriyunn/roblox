--!strict
-- robloxstub_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves the stub itself: the fake clock orders callbacks, JSON round-trips, Vector3 maths,
-- Instance attributes and tree, the DataStore fake (budget, injected failures, copies not references),
-- and that the harness can fail (negative control at the end, run in a child pcall).
-- Run from this folder: luau robloxstub_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("robloxstub_test")
local R = Stub.new()

-- clock and task
local order = {}
R.task.delay(2, function() table.insert(order, "b") end)
R.task.delay(1, function() table.insert(order, "a") end)
R.task.defer(function() table.insert(order, "d") end)
R.task.wait(1.5)
T.eq(table.concat(order), "da", "task.delay runs in time order; defer runs first")
T.eq(R.clock.now, 1.5, "task.wait advances the clock")
R.task.wait(1)
T.eq(table.concat(order), "dab", "the later delay fires once the clock passes it")

-- JSON
local obj = { a = 1, b = "x\ny", c = { 1, 2, 3 }, d = { e = true, f = false }, g = 1.5 }
local s = R.HttpService:JSONEncode(obj)
local back = R.HttpService:JSONDecode(s)
T.eq(back.a, 1, "JSON round-trip integer")
T.eq(back.b, "x\ny", "JSON round-trip escaped string")
T.eq(#back.c, 3, "JSON round-trip array")
T.eq(back.d.e, true, "JSON round-trip nested bool")
T.eq(back.g, 1.5, "JSON round-trip float")
T.eq(R.HttpService:JSONEncode({}), "[]", "empty table encodes as []")
T.eq(R.HttpService:JSONDecode("null"), nil, "null decodes to nil")
T.throws(function() R.HttpService:JSONEncode({ [1.5] = 1 }) end, "non-string key", "non-string keys are refused")

-- Vector3
local V3 = R.Vector3
local v = V3.new(3, 4, 0)
T.eq(v.Magnitude, 5, "Vector3.Magnitude")
T.eq((v.Unit).X, 0.6, "Vector3.Unit")
T.eq((v + V3.new(1, 1, 1)).Y, 5, "Vector3 add")
T.eq((v * 2).X, 6, "Vector3 scalar multiply")
T.eq(V3.Dot(v, V3.new(1, 0, 0)), 3, "Vector3 dot")
T.check(V3.new(1, 2, 3) == V3.new(1, 2, 3), "Vector3 equality")

-- Instance
local root = R.Instance.new("Folder")
local child = R.Instance.new("Part", root)
child.Name = "Hook"
T.eq(root.Hook, child, "child lookup by name")
T.eq(root:FindFirstChild("Hook"), child, "FindFirstChild")
local fired = 0
child:GetAttributeChangedSignal("Depth"):Connect(function() fired += 1 end)
child:SetAttribute("Depth", 0.3)
T.eq(child:GetAttribute("Depth"), 0.3, "attribute set/get")
T.eq(fired, 1, "attribute changed signal fires")
child:Destroy()
T.eq(#root:GetChildren(), 0, "Destroy removes from parent")

-- Players
local p = R.Players:addFake(7, "Adrian")
T.eq(#R.Players:GetPlayers(), 1, "fake player added")
T.eq(p.UserId, 7, "fake player has UserId")

-- DataStore
local store = R.DataStoreService:GetDataStore("Saves")
local saved = { coins = 10, fish = { "trout" } }
store:SetAsync("u7", saved)
saved.coins = 999
local got = store:GetAsync("u7")
T.eq(got.coins, 10, "SetAsync stores a copy, not a reference")
store:UpdateAsync("u7", function(old) old.coins += 5; return old end)
T.eq(store:GetAsync("u7").coins, 15, "UpdateAsync applies the transform")
R.dataStores.failNext("SetAsync", "503: Service Unavailable")
T.throws(function() store:SetAsync("u7", {}) end, "503", "injected failure on the next SetAsync")
store:SetAsync("u7", { coins = 1 })
T.eq(store:GetAsync("u7").coins, 1, "the failure was one-shot")
R.dataStores.budget = 1
store:GetAsync("u7")
T.throws(function() store:GetAsync("u7") end, "throttled", "budget exhaustion throttles")
R.dataStores.budget = math.huge
T.eq(#R.dataStores.calls, 9, "every call is logged")

-- RunService
local beats = 0
R.RunService.Heartbeat:Connect(function(dt) beats += 1 end)
R.step(1 / 60)
R.step(1 / 60)
T.eq(beats, 2, "R.step fires Heartbeat")

-- warn is captured
R.warn("x", 1)
T.eq(R.warnings[1], "x 1", "warn is captured")

-- negative control: a harness with a failing check must error on finish
local T2 = Stub.harness("negative-control")
T2.check(false, "this is meant to fail")
local ok = pcall(T2.finish)
T.check(not ok, "negative control: a failing suite errors on finish")

T.finish()
