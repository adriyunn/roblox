--!strict
-- savedata_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves src/Fishing/Server/SaveData.lua against the RobloxStub DataStore: defaults and _v stamping,
-- migrations in order, newer schema -> read-only, retries with doubling backoff on the fake clock,
-- give-up after maxRetries, dot paths, dirty-only saves, session locks (foreign fresh lock refuses the
-- load, stale lock taken over, foreign lock refuses the save), autosave timing, PlayerRemoving,
-- flushAll, budget waits, and the negative control (a corrupted record is never overwritten).
-- Run from this folder: luau savedata_test.luau

local Stub = require("./RobloxStub")
local SaveData = require("../src/Fishing/Server/SaveData")
local R = Stub.new()
local T = Stub.harness("savedata_test")

local STORE = "PlayerData"

-- a fresh runtime + wrapper per scenario so call counts and clocks start at zero
local function fresh(optOverrides: { [string]: any }?, jobId: string?)
	local RR = Stub.new()
	local deps = {
		DataStoreService = RR.DataStoreService,
		Players = RR.Players,
		HttpService = RR.HttpService,
		task = RR.task,
		Enum = RR.Enum,
		clock = function()
			return RR.clock.now
		end,
		warn = RR.warn,
		jobId = jobId or "job-A",
	}
	local opts: { [string]: any } = {
		storeName = STORE,
		schemaVersion = 1,
		defaults = function()
			return { coins = 0, gear = { rod = "basic" }, bag = {} }
		end,
		migrations = {},
		autosaveS = 60,
		maxRetries = 5,
		backoffS = 1,
		lockStaleS = 1800,
		budgetFloor = 5,
	}
	for k, v in optOverrides or {} do
		opts[k] = v
	end
	local sd = SaveData.new(deps :: any, opts :: any)
	return RR, sd
end

local function countCalls(RR: any, op: string?): number
	local n = 0
	for _, c in RR.dataStores.calls do
		if op == nil or c.op == op then
			n += 1
		end
	end
	return n
end

local function lastWarn(RR: any): string
	return RR.warnings[#RR.warnings] or ""
end

-- ---------------------------------------------------------------- new player
do
	local RR, sd = fresh()
	local p1 = RR.Players:addFake(1)
	local prof, why = sd:load(p1)
	T.check(prof ~= nil, "new player: load returns a profile")
	T.eq(why, "new", "new player: reason is new")
	assert(prof)
	T.eq(prof.data._v, 1, "new player: defaults stamped with _v = schemaVersion")
	T.eq(prof.data.coins, 0, "new player: defaults applied")
	T.eq(prof:get("gear.rod"), "basic", "new player: get() reads a nested default")
	T.eq(prof.readOnly, false, "new player: profile is writable")
	T.eq(prof:isDirty(), false, "new player: profile starts clean (the claim wrote it)")
	local stored = RR.dataStores.stores[STORE]["u1"]
	T.check(stored ~= nil and stored._lock ~= nil and stored._lock.jobId == "job-A", "new player: the store holds our _lock")
	T.eq(stored and stored._v, 1, "new player: the store holds _v")
	T.eq(stored and stored._savedAt, 0, "new player: _savedAt = clock()")
	T.eq(countCalls(RR), 2, "new player: one GetAsync + one UpdateAsync")
	T.eq(sd:stats().loads, 1, "stats().loads counts the load")
	local again, why2 = sd:load(p1)
	T.check(again == prof and why2 == "already-loaded", "loading twice returns the same profile")
	T.eq(SaveData.keyFor(p1), "u1", "keyFor is u<UserId>")
end

-- ---------------------------------------------------------------- existing data
do
	local RR, sd = fresh()
	RR.dataStores.stores[STORE]["u2"] = { _v = 1, coins = 42, gear = { rod = "carbon" }, _lock = { jobId = "job-A", t = -5000 }, _savedAt = -5000 }
	local p2 = RR.Players:addFake(2)
	local prof, why = sd:load(p2)
	assert(prof)
	T.eq(why, "loaded", "existing player: reason is loaded")
	T.eq(prof.data.coins, 42, "existing player: stored data loads")
	T.eq(prof.data._lock, nil, "existing player: _lock is stripped from data")
	T.eq(prof.data._savedAt, nil, "existing player: _savedAt is stripped from data")
	T.eq(RR.dataStores.stores[STORE]["u2"]._lock.t, 0, "existing player: the lock timestamp is refreshed")
end

-- ---------------------------------------------------------------- migrations 1 -> 2 -> 3
do
	local order = {}
	local RR, sd = fresh({
		schemaVersion = 3,
		migrations = {
			[1] = function(d: any)
				table.insert(order, 1)
				d.bait = "worm"
				return d
			end,
			[2] = function(d: any)
				table.insert(order, 2)
				d.gold = d.coins
				d.coins = nil
				return d
			end,
		},
	})
	RR.dataStores.stores[STORE]["u3"] = { _v = 1, coins = 7 }
	local prof = sd:load(RR.Players:addFake(3))
	assert(prof)
	T.eq(table.concat(order, ","), "1,2", "migrations run in order 1 then 2")
	T.eq(prof.data._v, 3, "migrated profile is stamped _v = 3")
	T.check(prof.data.gold == 7 and prof.data.coins == nil and prof.data.bait == "worm", "both migrations applied")
	T.eq(RR.dataStores.stores[STORE]["u3"]._v, 3, "the migrated record is persisted at load")
	T.eq(prof.readOnly, false, "migrated profile is writable")
end

-- ---------------------------------------------------------------- missing migration
do
	local RR, sd = fresh({ schemaVersion = 2 })
	RR.dataStores.stores[STORE]["u4"] = { _v = 1, coins = 1 }
	local prof, why = sd:load(RR.Players:addFake(4))
	assert(prof)
	T.check(prof.readOnly and why == "no-migration", "no migration from the stored _v -> read-only profile")
	T.check(lastWarn(RR):find("no migration", 1, true) ~= nil, "missing migration warns")
end

-- ---------------------------------------------------------------- newer schema
do
	local RR, sd = fresh()
	RR.dataStores.stores[STORE]["u5"] = { _v = 9, coins = 5, future = true }
	local p5 = RR.Players:addFake(5)
	local prof, why = sd:load(p5)
	assert(prof)
	T.check(prof.readOnly == true and why == "newer", "newer _v than the server knows -> read-only")
	T.check(lastWarn(RR):find("schema 9", 1, true) ~= nil, "newer _v warns")
	T.eq(prof.data.coins, 5, "newer _v: the stored data is still readable")
	T.eq(countCalls(RR, "UpdateAsync"), 0, "newer _v: no lock written, no UpdateAsync")
	prof:set("coins", 100)
	local ok, reason = sd:save(p5, "test")
	T.check(ok == false and reason == "read-only", "save on a read-only profile is refused silently")
	T.eq(RR.dataStores.stores[STORE]["u5"].coins, 5, "newer _v: the store is untouched")
end

-- ---------------------------------------------------------------- retries
do
	local RR, sd = fresh()
	RR.dataStores.failNext("GetAsync", "503: Service Unavailable")
	RR.dataStores.failNext("GetAsync", "503: Service Unavailable")
	local prof = sd:load(RR.Players:addFake(6))
	T.check(prof ~= nil, "GetAsync fails twice then succeeds -> profile")
	T.eq(countCalls(RR, "GetAsync"), 3, "three GetAsync calls (two failed, one ok)")
	T.eq(#RR.dataStores.calls, 4, "four calls in total (3 GetAsync + 1 UpdateAsync)")
	T.eq(RR.clock.now, 3, "the clock advanced 1 + 2 s of backoff")
	T.eq(sd:stats().retries, 2, "stats().retries == 2")
	T.eq(sd:stats().failures, 0, "no failure counted when a retry succeeds")
end

do
	local RR, sd = fresh()
	for _ = 1, 5 do
		RR.dataStores.failNext("GetAsync", "503: Service Unavailable")
	end
	local prof, why = sd:load(RR.Players:addFake(7))
	T.check(prof == nil and why:find("503", 1, true) ~= nil, "fails maxRetries times -> nil + reason")
	T.check(lastWarn(RR):find("after 5 attempts", 1, true) ~= nil, "give-up warns with the attempt count")
	T.eq(sd:stats().failures, 1, "stats().failures == 1")
	T.eq(RR.clock.now, 15, "backoff 1 + 2 + 4 + 8 between the five attempts")
	T.eq(countCalls(RR, "UpdateAsync"), 0, "no lock written after a failed load")
end

-- ---------------------------------------------------------------- dot paths, dirty-only saves
do
	local RR, sd = fresh()
	local p8 = RR.Players:addFake(8)
	local prof = sd:load(p8)
	assert(prof)
	local before = #RR.dataStores.calls
	local ok, reason = sd:save(p8, "idle")
	T.check(ok == false and reason == "clean", "save on a clean profile does nothing")
	T.eq(#RR.dataStores.calls, before, "clean save makes no DataStore call")
	prof:set("gear.lure.color", "red")
	T.eq(prof:get("gear.lure.color"), "red", "set/get a deep dot path creates intermediate tables")
	T.eq(prof:get("gear.rod"), "basic", "set does not clobber siblings")
	T.eq(prof:get("nope.deeper"), nil, "get on a missing path is nil")
	prof:set("bag.1", "trout")
	T.eq(prof.data.bag[1], "trout", "an all-digit segment indexes an array")
	T.eq(prof:isDirty(), true, "set marks the profile dirty")
	RR.advance(10)
	ok, reason = sd:save(p8, "test")
	T.check(ok and reason == "saved", "dirty save writes")
	T.eq(#RR.dataStores.calls, before + 1, "dirty save is one UpdateAsync")
	local stored = RR.dataStores.stores[STORE]["u8"]
	T.eq(stored.gear.lure.color, "red", "the store holds the new value")
	T.eq(stored._savedAt, 10, "_savedAt is the clock at the save")
	T.eq(prof:isDirty(), false, "profile is clean after the save")
	T.eq(prof.lastSaveReason, "test", "the save reason is kept on the profile")
	T.eq(sd:stats().saves, 1, "stats().saves counts it")
	ok, reason = sd:save(p8, "forced", true)
	T.check(ok and reason == "saved", "force saves a clean profile")
	ok, reason = sd:save(RR.Players:addFake(80), "x")
	T.check(ok == false and reason == "not-loaded", "save on a player never loaded -> not-loaded")
end

-- ---------------------------------------------------------------- foreign lock refuses the save
do
	local RR, sd = fresh()
	local p9 = RR.Players:addFake(9)
	local prof = sd:load(p9)
	assert(prof)
	RR.dataStores.stores[STORE]["u9"]._lock.jobId = "other"
	prof:set("coins", 999)
	local ok, reason = sd:save(p9, "test")
	T.check(ok == false and reason == "foreign-lock", "UpdateAsync transform refuses a foreign lock")
	T.eq(RR.dataStores.stores[STORE]["u9"].coins, 0, "no write happened")
	T.check(lastWarn(RR):find("locked by another server", 1, true) ~= nil, "foreign lock warns")
	T.eq(sd:stats().refused, 1, "stats().refused == 1")
	T.eq(prof:isDirty(), true, "the profile stays dirty after a refused save")
end

-- ---------------------------------------------------------------- lock on load
do
	local RR, sd = fresh()
	RR.advance(10000)
	RR.dataStores.stores[STORE]["u10"] = { _v = 1, coins = 3, _lock = { jobId = "other", t = 10000 - 60 } }
	local prof, why = sd:load(RR.Players:addFake(10))
	T.check(prof == nil and why == "locked", "another server's fresh lock refuses the load")
	T.eq(countCalls(RR, "UpdateAsync"), 0, "a refused load writes nothing")
	T.eq(sd:stats().locked, 1, "stats().locked == 1")
	RR.dataStores.stores[STORE]["u11"] = { _v = 1, coins = 4, _lock = { jobId = "other", t = 10000 - 1801 } }
	local prof11 = sd:load(RR.Players:addFake(11))
	T.check(prof11 ~= nil, "a stale lock (older than lockStaleS) is taken over")
	T.eq(RR.dataStores.stores[STORE]["u11"]._lock.jobId, "job-A", "the stale lock now carries our jobId")
	-- a race: the other server claims between our GetAsync and our UpdateAsync
	RR.dataStores.stores[STORE]["u12"] = { _v = 1, coins = 1 }
	local origGet = RR.DataStoreService:GetDataStore(STORE).GetAsync
	local DS = getmetatable(RR.DataStoreService:GetDataStore(STORE))
	DS.GetAsync = function(self: any, key: string)
		local v, info = origGet(self, key)
		if key == "u12" then
			RR.dataStores.stores[STORE]["u12"]._lock = { jobId = "racer", t = RR.clock.now }
		end
		return v, info
	end
	local prof12, why12 = sd:load(RR.Players:addFake(12))
	DS.GetAsync = origGet
	T.check(prof12 == nil and why12 == "locked", "a lock claimed between Get and Update loses the race (transform returns nil)")
	T.eq(RR.dataStores.stores[STORE]["u12"]._lock.jobId, "racer", "the racer's lock is untouched")
end

-- ---------------------------------------------------------------- autosave on the fake clock
do
	local RR, sd = fresh()
	local p13 = RR.Players:addFake(13)
	local prof = sd:load(p13)
	assert(prof)
	prof:set("coins", 1)
	sd:startAutosave()
	RR.advance(59)
	T.eq(sd:stats().saves, 0, "autosave has not fired before autosaveS")
	RR.advance(1)
	T.eq(sd:stats().saves, 1, "autosave fires at autosaveS")
	T.eq(RR.dataStores.stores[STORE]["u13"].coins, 1, "autosave wrote the value")
	RR.advance(60)
	T.eq(sd:stats().saves, 1, "a clean profile is skipped by the next tick")
	prof:set("coins", 2)
	RR.advance(60)
	T.eq(sd:stats().saves, 2, "the loop keeps rescheduling itself")
	sd:stopAutosave()
	prof:set("coins", 3)
	RR.advance(180)
	T.eq(sd:stats().saves, 2, "stopAutosave stops the loop")
end

-- ---------------------------------------------------------------- PlayerRemoving
do
	local RR, sd = fresh()
	local p14 = RR.Players:addFake(14)
	local prof = sd:load(p14)
	assert(prof)
	prof:set("coins", 55)
	local ok = sd:onPlayerRemoving(p14)
	T.check(ok == true, "onPlayerRemoving saves")
	T.eq(RR.dataStores.stores[STORE]["u14"].coins, 55, "the leave save reached the store")
	T.eq(RR.dataStores.stores[STORE]["u14"]._lock, nil, "the lock is released (stored _lock is nil)")
	T.eq(sd:getProfile(p14), nil, "the profile is forgotten after release")
	T.eq(#sd:loadedUserIds(), 0, "no loaded players remain")
end

-- ---------------------------------------------------------------- flushAll
do
	local RR, sd = fresh()
	local a, b, c = RR.Players:addFake(15), RR.Players:addFake(16), RR.Players:addFake(17)
	local pa, pb = sd:load(a), sd:load(b)
	sd:load(c)
	assert(pa and pb)
	pa:set("coins", 1)
	pb:set("coins", 2)
	local n = sd:flushAll("close")
	T.eq(n, 2, "flushAll saves the two dirty profiles and returns 2")
	T.eq(RR.dataStores.stores[STORE]["u15"].coins + RR.dataStores.stores[STORE]["u16"].coins, 3, "both values are stored")
	T.check(RR.dataStores.stores[STORE]["u15"]._lock == nil and RR.dataStores.stores[STORE]["u17"]._lock == nil, "every lock is released, dirty or not")
	T.eq(#sd:loadedUserIds(), 0, "flushAll forgets every profile")
end

-- ---------------------------------------------------------------- budget
do
	local RR, sd = fresh()
	local p18 = RR.Players:addFake(18)
	local prof = sd:load(p18)
	assert(prof)
	prof:set("coins", 9)
	RR.dataStores.budget = 2
	RR.task.delay(3, function()
		RR.dataStores.budget = math.huge
	end)
	local t0 = RR.clock.now
	local ok = sd:save(p18, "test")
	T.check(ok, "the save goes through once the budget recovers")
	T.eq(RR.clock.now - t0, 3, "budget below floor delayed the save by 1 + 2 s")
	T.eq(sd:stats().budgetWaits, 2, "two budget waits counted")
end

-- ---------------------------------------------------------------- Studio jobId and deps checks
do
	local RR, sd = fresh(nil, "")
	T.check(sd:jobId() ~= "" and #sd:jobId() > 8, "an empty game.JobId (Studio) is replaced by a GUID")
	T.throws(function()
		SaveData.new({} :: any, {})
	end, "deps", "new() without deps errors")
	local _ = RR
end

-- ---------------------------------------------------------------- negative control: corrupted record
do
	local RR, sd = fresh()
	RR.dataStores.stores[STORE]["u99"] = "this is not a table"
	local p99 = RR.Players:addFake(99)
	local prof, why = sd:load(p99)
	assert(prof)
	T.check(prof.readOnly == true and why == "corrupt", "negative control: a string record gives a read-only default profile")
	T.eq(prof.data.coins, 0, "negative control: the read-only profile carries defaults")
	T.eq(prof.data._v, 1, "negative control: ... stamped with _v")
	T.check(lastWarn(RR):find("string instead of a table", 1, true) ~= nil, "negative control: corrupt record warns")
	prof:set("coins", 5)
	sd:save(p99, "test", true)
	sd:onPlayerRemoving(p99)
	T.eq(RR.dataStores.stores[STORE]["u99"], "this is not a table", "negative control: the store still holds the string (never overwritten)")
	T.eq(countCalls(RR, "UpdateAsync"), 0, "negative control: no UpdateAsync at all for a corrupt record")
end

T.finish()
