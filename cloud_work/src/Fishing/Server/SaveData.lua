--!strict
-- SaveData (About Fishing F1, WS-S; Cloud, 2026-10-06; design/WSS_savedata.md)
-- DataStore wrapper for player profiles: load with retries, schema migrations, a per-player session
-- lock so two servers never write the same key, dirty-tracked saves through UpdateAsync, autosave and
-- a BindToClose flush. Every later feature (catches, coins, gear, the tackle box, the catch log) saves
-- through one profile per player: profile:set("coins", n) then the autosave or leave does the write.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire (FishingServer or a new
-- ProfileService script under ServerScriptService):
--   * deps = { DataStoreService, Players, HttpService, Enum, task } from the real globals;
--     clock = os.time (a wall clock shared by every server: the lock timestamp is compared across
--     servers, so never os.clock or tick); warn = warn; jobId = game.JobId ("" in Studio, the module
--     then mints a GUID so the lock still means something in a Studio test server).
--   * opts.defaults() returns the empty profile table; bump opts.schemaVersion and add
--     opts.migrations[fromVersion] whenever the shape changes. Keep values JSON-safe (string keys or
--     proper arrays, finite numbers): the save refuses anything HttpService:JSONEncode cannot encode.
--   * Players.PlayerAdded -> sd:load(player) (on nil, "locked": retry after a few seconds, then kick);
--     Players.PlayerRemoving -> sd:onPlayerRemoving(player); game:BindToClose(function()
--     sd:flushAll("close") end); sd:startAutosave() once at server start.
--   * The key is "u<UserId>" (SaveData.keyFor). The stored record is the data table plus _v (schema),
--     _lock = { jobId, t } and _savedAt; _lock and _savedAt are stripped from profile.data on load.
--   * A read-only profile (newer schema, corrupt record, missing migration) plays from memory and is
--     never written; the caller may tell the player their progress will not save this session.

local SaveData = {}
SaveData.__index = SaveData

export type Deps = {
	DataStoreService: any, Players: any, HttpService: any, task: any, Enum: any?,
	clock: () -> number, warn: (...any) -> (), jobId: string?,
}

export type Opts = {
	storeName: string?, schemaVersion: number?, defaults: (() -> { [string]: any })?,
	migrations: { [number]: (any) -> any }?, autosaveS: number?, maxRetries: number?, backoffS: number?,
	backoffCapS: number?, lockStaleS: number?, budgetFloor: number?, maxBytes: number?,
}

export type Profile = {
	player: any, userId: number, key: string, data: { [string]: any },
	readOnly: boolean, reason: string?, locked: boolean, savedAt: number?, lastSaveReason: string?,
	_changes: number, _savedChanges: number,
	get: (self: Profile, path: string) -> any,
	set: (self: Profile, path: string, value: any) -> (),
	isDirty: (self: Profile) -> boolean,
}

export type Stats = { loads: number, saves: number, retries: number, failures: number, refused: number, locked: number, budgetWaits: number }

type Fields = {
	_deps: Deps, _store: any, _storeName: string, _schemaVersion: number,
	_defaults: () -> { [string]: any }, _migrations: { [number]: (any) -> any },
	_autosaveS: number, _maxRetries: number, _backoffS: number, _backoffCapS: number,
	_lockStaleS: number, _budgetFloor: number, _maxBytes: number, _jobId: string,
	_profiles: { [number]: Profile }, _order: { number }, _autosaveGen: number, _stats: Stats,
}

export type SaveData = typeof(setmetatable({} :: Fields, SaveData))

-- Splits "gear.rod" into { "gear", "rod" }; an all-digit segment becomes a number (array index).
local function splitPath(path: string): { any }
	local parts: { any } = {}
	for seg in string.gmatch(path, "[^%.]+") do
		table.insert(parts, if string.match(seg, "^%d+$") then tonumber(seg) else seg)
	end
	return parts
end

local function makeProfile(player: any, key: string, data: { [string]: any }, readOnly: boolean, reason: string?): Profile
	local p: any = {
		player = player, userId = player.UserId, key = key, data = data,
		readOnly = readOnly, reason = reason, locked = false, savedAt = nil, lastSaveReason = nil,
		_changes = 0, _savedChanges = 0,
	}
	-- Reads a dot path ("gear.rod"); nil when any segment is missing.
	function p.get(self: Profile, path: string): any
		local node: any = self.data
		for _, seg in splitPath(path) do
			if typeof(node) ~= "table" then
				return nil
			end
			node = node[seg]
		end
		return node
	end
	-- Writes a dot path, creating intermediate tables, and marks the profile dirty.
	function p.set(self: Profile, path: string, value: any)
		local parts = splitPath(path)
		assert(#parts > 0, "SaveData: empty path")
		local node: any = self.data
		for i = 1, #parts - 1 do
			local nxt = node[parts[i]]
			if typeof(nxt) ~= "table" then
				nxt = {}
				node[parts[i]] = nxt
			end
			node = nxt
		end
		node[parts[#parts]] = value
		self._changes += 1
	end
	-- True when a set() happened since the last successful save (or load).
	function p.isDirty(self: Profile): boolean
		return self._changes ~= self._savedChanges
	end
	return p :: Profile
end

-- The DataStore key for a player: "u<UserId>".
function SaveData.keyFor(player: any): string
	return "u" .. tostring(player.UserId)
end

-- Builds a wrapper over one DataStore; nothing is read until load().
function SaveData.new(deps: Deps, opts: Opts?): SaveData
	local o: Opts = opts or {}
	assert(typeof(deps) == "table" and deps.DataStoreService ~= nil and deps.task ~= nil, "SaveData.new: deps need DataStoreService and task")
	assert(typeof(deps.clock) == "function" and typeof(deps.warn) == "function", "SaveData.new: deps need clock and warn")
	local jobId = deps.jobId
	if typeof(jobId) ~= "string" or jobId == "" then
		jobId = deps.HttpService:GenerateGUID(false)
	end
	if deps.Enum == nil then
		deps.warn("SaveData: deps.Enum missing; request budget checks are disabled")
	end
	local storeName = o.storeName or "PlayerData"
	local self: Fields = {
		_deps = deps,
		_store = deps.DataStoreService:GetDataStore(storeName),
		_storeName = storeName,
		_schemaVersion = o.schemaVersion or 1,
		_defaults = o.defaults or function(): { [string]: any }
			return {}
		end,
		_migrations = o.migrations or {},
		_autosaveS = o.autosaveS or 60,
		_maxRetries = o.maxRetries or 5,
		_backoffS = o.backoffS or 1,
		_backoffCapS = o.backoffCapS or 16,
		_lockStaleS = o.lockStaleS or 1800,
		_budgetFloor = o.budgetFloor or 5,
		_maxBytes = o.maxBytes or 4000000,
		_jobId = jobId :: string,
		_profiles = {},
		_order = {},
		_autosaveGen = 0,
		_stats = { loads = 0, saves = 0, retries = 0, failures = 0, refused = 0, locked = 0, budgetWaits = 0 },
	}
	return setmetatable(self, SaveData)
end

-- The jobId this server locks with (game.JobId, or a GUID when that was empty).
function SaveData.jobId(self: SaveData): string
	return self._jobId
end

function SaveData._backoff(self: SaveData, attempt: number): number
	return math.min(self._backoffS * 2 ^ (attempt - 1), self._backoffCapS)
end

-- Waits (doubling backoff, at most maxRetries waits) while the request budget sits below budgetFloor.
function SaveData._waitBudget(self: SaveData, op: string)
	local Enum = self._deps.Enum
	if Enum == nil then
		return
	end
	local requestType = Enum.DataStoreRequestType[op]
	for i = 1, self._maxRetries do
		if self._deps.DataStoreService:GetRequestBudgetForRequestType(requestType) >= self._budgetFloor then
			return
		end
		self._stats.budgetWaits += 1
		self._deps.task.wait(self:_backoff(i))
	end
end

-- Runs one DataStore call with retries and doubling backoff on the injected task.wait.
function SaveData._call(self: SaveData, op: string, key: string, fn: () -> any): (boolean, any)
	self:_waitBudget(op)
	local attempt = 0
	while true do
		attempt += 1
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		if attempt >= self._maxRetries then
			self._stats.failures += 1
			self._deps.warn(string.format("SaveData: %s %s failed after %d attempts: %s", op, key, attempt, tostring(res)))
			return false, res
		end
		self._stats.retries += 1
		self._deps.task.wait(self:_backoff(attempt))
	end
end

-- True when another server's lock is younger than staleS.
local function lockIsLive(lock: any, jobId: string, now: number, staleS: number): boolean
	if typeof(lock) ~= "table" or lock.jobId == jobId then
		return false
	end
	local t = if typeof(lock.t) == "number" then lock.t else -math.huge
	return now - t < staleS
end

-- One UpdateAsync writing the profile's record (data + _v, _lock, _savedAt) unless a foreign lock holds
-- the key. claiming = true (load): only a live foreign lock blocks, a stale one is taken over.
-- claiming = false (save): any foreign lock blocks. Returns "written" | "foreign" | "failed", err.
function SaveData._write(self: SaveData, p: Profile, claiming: boolean): (string, any)
	local now = self._deps.clock()
	local rec = table.clone(p.data)
	rec._v = self._schemaVersion
	rec._lock = { jobId = self._jobId, t = now }
	rec._savedAt = now
	local okJ, encoded = pcall(function()
		return self._deps.HttpService:JSONEncode(rec)
	end)
	if not okJ then
		self._deps.warn(string.format("SaveData: %s not JSON-safe, not written: %s", p.key, tostring(encoded)))
		return "failed", encoded
	elseif #encoded > self._maxBytes then
		self._deps.warn(string.format("SaveData: %s is %d bytes (limit %d), not written", p.key, #encoded, self._maxBytes))
		return "failed", "too large"
	end
	local foreign = false
	local ok, err = self:_call("UpdateAsync", p.key, function()
		return self._store:UpdateAsync(p.key, function(old: any): any
			if typeof(old) == "table" and typeof(old._lock) == "table" and old._lock.jobId ~= self._jobId then
				if not claiming or lockIsLive(old._lock, self._jobId, self._deps.clock(), self._lockStaleS) then
					foreign = true
					return nil
				end
			end
			return rec
		end)
	end)
	if not ok then
		return "failed", err
	elseif foreign then
		return "foreign", nil
	end
	p.savedAt = now
	return "written", nil
end

function SaveData._track(self: SaveData, p: Profile)
	self._profiles[p.userId] = p
	table.insert(self._order, p.userId)
end

-- Warns, then tracks a read-only profile (never written) for the given reason.
function SaveData._readOnly(self: SaveData, player: any, key: string, data: { [string]: any }, reason: string, msg: string): (Profile, string)
	self._deps.warn(string.format("SaveData: %s %s; read-only profile, nothing will be written", key, msg))
	local p = makeProfile(player, key, data, true, reason)
	self:_track(p)
	return p, reason
end

-- Loads (or creates) a player's profile and claims its session lock. Returns profile, reason where
-- reason is "new" | "loaded" | "already-loaded" | "newer" | "corrupt" | "no-migration" (the last three
-- are read-only), or nil, "locked" | "GetAsync failed: .." | "UpdateAsync failed: ..".
function SaveData.load(self: SaveData, player: any): (Profile?, string)
	local existing = self._profiles[player.UserId]
	if existing then
		return existing, "already-loaded"
	end
	local key = SaveData.keyFor(player)
	self._stats.loads += 1
	local ok, stored = self:_call("GetAsync", key, function()
		return (self._store:GetAsync(key))
	end)
	if not ok then
		return nil, "GetAsync failed: " .. tostring(stored)
	end
	local now = self._deps.clock()
	local data: { [string]: any }
	if stored == nil then
		data = self._defaults()
	elseif typeof(stored) ~= "table" then
		local fresh = self._defaults()
		fresh._v = self._schemaVersion
		return self:_readOnly(player, key, fresh, "corrupt", "holds a " .. typeof(stored) .. " instead of a table")
	else
		data = stored
		local v: number = if typeof(data._v) == "number" then data._v else 0
		if v > self._schemaVersion then
			data._lock = nil
			data._savedAt = nil
			return self:_readOnly(player, key, data, "newer", string.format("has schema %d, this server knows %d", v, self._schemaVersion))
		end
		if lockIsLive(data._lock, self._jobId, now, self._lockStaleS) then
			self._stats.locked += 1
			return nil, "locked"
		end
		data._lock = nil
		data._savedAt = nil
		while v < self._schemaVersion do
			local migrate = self._migrations[v]
			if migrate == nil then
				return self:_readOnly(player, key, data, "no-migration", string.format("has schema %d and no migration from it", v))
			end
			local migrated = migrate(data)
			if typeof(migrated) ~= "table" then
				return self:_readOnly(player, key, data, "no-migration", string.format("migration %d returned %s", v, typeof(migrated)))
			end
			data = migrated
			v += 1
			data._v = v
		end
	end
	data._v = self._schemaVersion
	local p = makeProfile(player, key, data, false, nil)
	local status, err = self:_write(p, true)
	if status == "foreign" then
		self._stats.locked += 1
		return nil, "locked"
	elseif status ~= "written" then
		return nil, "UpdateAsync failed: " .. tostring(err)
	end
	p.locked = true
	self:_track(p)
	return p, if stored == nil then "new" else "loaded"
end

-- The loaded profile for a player, or nil.
function SaveData.getProfile(self: SaveData, player: any): Profile?
	return self._profiles[player.UserId]
end

-- Saves a loaded profile when dirty (or force). Returns ok, "saved" | "clean" | "read-only" |
-- "not-loaded" | "foreign-lock" | "failed: ..".
function SaveData.save(self: SaveData, player: any, reason: string?, force: boolean?): (boolean, string)
	local p = self._profiles[player.UserId]
	if p == nil then
		return false, "not-loaded"
	elseif p.readOnly then
		return false, "read-only"
	elseif not p:isDirty() and not force then
		return false, "clean"
	end
	local changesBefore = p._changes
	local status, err = self:_write(p, false)
	if status == "written" then
		p._savedChanges = changesBefore
		p.lastSaveReason = reason
		self._stats.saves += 1
		return true, "saved"
	elseif status == "foreign" then
		self._stats.refused += 1
		self._deps.warn(string.format("SaveData: %s is locked by another server, save (%s) refused", p.key, tostring(reason)))
		return false, "foreign-lock"
	end
	return false, "failed: " .. tostring(err)
end

-- Releases the session lock (UpdateAsync clearing _lock when it is ours) and forgets the profile.
function SaveData.release(self: SaveData, player: any): boolean
	local p = self._profiles[player.UserId]
	if p == nil then
		return false
	end
	self._profiles[p.userId] = nil
	local i = table.find(self._order, p.userId)
	if i then
		table.remove(self._order, i)
	end
	if not p.locked then
		return true
	end
	local ok = self:_call("UpdateAsync", p.key, function()
		return self._store:UpdateAsync(p.key, function(old: any): any
			if typeof(old) == "table" and typeof(old._lock) == "table" and old._lock.jobId == self._jobId then
				old._lock = nil
				return old
			end
			return nil
		end)
	end)
	p.locked = false
	return ok
end

-- PlayerRemoving: force-save then release.
function SaveData.onPlayerRemoving(self: SaveData, player: any): (boolean, string)
	local ok, why = self:save(player, "leave", true)
	self:release(player)
	return ok, why
end

-- BindToClose: saves every dirty profile and releases every lock; returns the number saved.
function SaveData.flushAll(self: SaveData, reason: string?): number
	local saved = 0
	for _, userId in table.clone(self._order) do
		local p = self._profiles[userId]
		if p then
			if p:isDirty() and not p.readOnly and self:save(p.player, reason or "flush") then
				saved += 1
			end
			self:release(p.player)
		end
	end
	return saved
end

-- Starts the autosave loop: every autosaveS, saves each dirty profile (task.delay rescheduling itself).
function SaveData.startAutosave(self: SaveData)
	self._autosaveGen += 1
	local gen = self._autosaveGen
	local function tick()
		if gen ~= self._autosaveGen then
			return
		end
		for _, userId in table.clone(self._order) do
			local p = self._profiles[userId]
			if p and p:isDirty() and not p.readOnly then
				self:save(p.player, "autosave")
			end
		end
		if gen == self._autosaveGen then
			self._deps.task.delay(self._autosaveS, tick)
		end
	end
	self._deps.task.delay(self._autosaveS, tick)
end

-- Stops the autosave loop (the pending tick becomes a no-op).
function SaveData.stopAutosave(self: SaveData)
	self._autosaveGen += 1
end

-- Counters: loads, saves, retries, failures, refused (foreign-lock saves), locked, budgetWaits.
function SaveData.stats(self: SaveData): Stats
	return table.clone(self._stats)
end

-- UserIds of the loaded profiles in load order.
function SaveData.loadedUserIds(self: SaveData): { number }
	return table.clone(self._order)
end

return SaveData
