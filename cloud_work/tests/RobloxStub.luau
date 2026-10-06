--!strict
-- RobloxStub (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Enough of the Roblox API to run game modules under the offline Luau CLI: a fake clock, task.*,
-- Instance with attributes and a parent/child tree, game:GetService for Players, RunService,
-- HttpService (JSON + GUIDs) and DataStoreService (in-memory, with injectable failures and a budget),
-- Vector3, Enum and warn. Nothing here is faithful beyond what offline tests need; when a test needs
-- more, add it here so every suite shares one stub instead of each stubbing its own piece.
--
-- Use: local Stub = require("./RobloxStub"); local R = Stub.new()
--      R.task.wait(1)           -- advances R.clock.now by 1 and runs scheduled callbacks
--      R.game:GetService("DataStoreService"):GetDataStore("x"):SetAsync(k, v)
--      R.dataStores.failNext("SetAsync", "503")  -- the next SetAsync errors with "503"
-- Modules under test take these services as arguments (dependency injection) so the same file runs in
-- Studio with the real services and here with the stub.

local Stub = {}

-- ---------------------------------------------------------------- JSON (HttpService:JSONEncode/Decode)
local function jsonEncode(v: any): string
	local t = typeof(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return v and "true" or "false"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("Cannot encode non-finite number")
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.17g", v)
	elseif t == "string" then
		local s = v:gsub('[%c"\\]', function(c)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return map[c] or string.format("\\u%04x", string.byte(c))
		end)
		return '"' .. s .. '"'
	elseif t == "table" then
		-- an array when keys are exactly 1..n; an empty table encodes as [] like Roblox's HttpService
		local n = #v
		if n == 0 and next(v) == nil then
			return "[]"
		end
		local isArray = n > 0
		if isArray then
			for k in v do
				if typeof(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
					isArray = false
					break
				end
			end
		end
		local parts = {}
		if isArray then
			for i = 1, n do
				parts[i] = jsonEncode(v[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in v do
			if typeof(k) ~= "string" then
				error("Cannot encode table with non-string key: " .. tostring(k))
			end
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in keys do
			table.insert(parts, jsonEncode(k) .. ":" .. jsonEncode(v[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("Cannot encode " .. t)
end

local function jsonDecode(s: string): any
	local pos = 1
	local function skip()
		local _, e = s:find("^[ \t\r\n]*", pos)
		pos = (e or pos - 1) + 1
	end
	local parseValue: () -> any
	local function parseString(): string
		assert(s:sub(pos, pos) == '"', "JSON: expected string at " .. pos)
		pos += 1
		local out = {}
		while true do
			local c = s:sub(pos, pos)
			if c == "" then
				error("JSON: unterminated string")
			elseif c == '"' then
				pos += 1
				return table.concat(out)
			elseif c == "\\" then
				local n = s:sub(pos + 1, pos + 1)
				local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				if n == "u" then
					local hex = s:sub(pos + 2, pos + 5)
					table.insert(out, utf8.char(tonumber(hex, 16) :: number))
					pos += 6
				else
					table.insert(out, map[n] or n)
					pos += 2
				end
			else
				table.insert(out, c)
				pos += 1
			end
		end
	end
	function parseValue(): any
		skip()
		local c = s:sub(pos, pos)
		if c == "{" then
			pos += 1
			local obj = {}
			skip()
			if s:sub(pos, pos) == "}" then
				pos += 1
				return obj
			end
			while true do
				skip()
				local k = parseString()
				skip()
				assert(s:sub(pos, pos) == ":", "JSON: expected ':' at " .. pos)
				pos += 1
				obj[k] = parseValue()
				skip()
				local d = s:sub(pos, pos)
				pos += 1
				if d == "}" then
					return obj
				end
				assert(d == ",", "JSON: expected ',' or '}' at " .. (pos - 1))
			end
		elseif c == "[" then
			pos += 1
			local arr = {}
			skip()
			if s:sub(pos, pos) == "]" then
				pos += 1
				return arr
			end
			while true do
				table.insert(arr, parseValue())
				skip()
				local d = s:sub(pos, pos)
				pos += 1
				if d == "]" then
					return arr
				end
				assert(d == ",", "JSON: expected ',' or ']' at " .. (pos - 1))
			end
		elseif c == '"' then
			return parseString()
		elseif s:sub(pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif s:sub(pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif s:sub(pos, pos + 3) == "null" then
			pos += 4
			return nil
		else
			local numStr = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			assert(numStr and #numStr > 0, "JSON: unexpected character at " .. pos)
			pos += #numStr
			return tonumber(numStr)
		end
	end
	local v = parseValue()
	skip()
	assert(pos > #s, "JSON: trailing characters at " .. pos)
	return v
end

Stub.jsonEncode = jsonEncode
Stub.jsonDecode = jsonDecode

-- ---------------------------------------------------------------- Vector3
export type Vector3 = { X: number, Y: number, Z: number, Magnitude: number, Unit: any }
local V3 = {}
V3.__index = function(self: any, k: string)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif k == "Unit" then
		local m = self.Magnitude
		return m > 0 and V3.new(self.X / m, self.Y / m, self.Z / m) or V3.new(0, 0, 0)
	end
	return (V3 :: any)[k]
end
V3.__add = function(a: any, b: any) return V3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a: any, b: any) return V3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a: any) return V3.new(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a: any, b: any)
	if typeof(a) == "number" then return V3.new(a * b.X, a * b.Y, a * b.Z) end
	if typeof(b) == "number" then return V3.new(a.X * b, a.Y * b, a.Z * b) end
	return V3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a: any, b: number) return V3.new(a.X / b, a.Y / b, a.Z / b) end
V3.__eq = function(a: any, b: any) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a: any) return string.format("%g, %g, %g", a.X, a.Y, a.Z) end
function V3.new(x: number?, y: number?, z: number?): Vector3
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) :: any
end
function V3.Dot(a: any, b: any): number return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3.Cross(a: any, b: any)
	return V3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a: any, b: any, t: number) return a + (b - a) * t end
V3.zero = V3.new(0, 0, 0)
V3.one = V3.new(1, 1, 1)
V3.xAxis = V3.new(1, 0, 0)
V3.yAxis = V3.new(0, 1, 0)
V3.zAxis = V3.new(0, 0, 1)
Stub.Vector3 = V3

-- ---------------------------------------------------------------- Signal (RBXScriptSignal-like)
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ _handlers = {} :: { (...any) -> () } }, Signal)
end
function Signal:Connect(fn: (...any) -> ())
	table.insert(self._handlers, fn)
	local conn = { Connected = true }
	function conn.Disconnect(c)
		c.Connected = false
		local i = table.find(self._handlers, fn)
		if i then table.remove(self._handlers, i) end
	end
	return conn
end
Signal.Once = Signal.Connect
function Signal:Fire(...: any)
	for _, fn in table.clone(self._handlers) do
		fn(...)
	end
end
function Signal:Wait(): ...any
	error("Signal:Wait is not supported in the stub; use a callback")
end
Stub.Signal = Signal

-- ---------------------------------------------------------------- Instance (attributes, tree, Destroy)
local Instance = {}
Instance.__index = function(self: any, k: string)
	local v = rawget(Instance, k)
	if v ~= nil then return v end
	-- child lookup by name, like Roblox
	for _, c in rawget(self, "_children") do
		if c.Name == k then return c end
	end
	return nil
end
function Instance.new(className: string, parent: any?): any
	local inst: any = setmetatable({
		ClassName = className,
		Name = className,
		Parent = nil,
		_children = {},
		_attributes = {},
		_attrChanged = Signal.new(),
		_destroyed = false,
	}, Instance)
	if parent then (inst :: any).Parent = parent; table.insert(parent._children, inst) end
	return inst
end
function Instance:SetAttribute(name: string, value: any)
	self._attributes[name] = value
	self._attrChanged:Fire(name)
end
function Instance:GetAttribute(name: string): any return self._attributes[name] end
function Instance:GetAttributes(): { [string]: any } return table.clone(self._attributes) end
function Instance:GetAttributeChangedSignal(_name: string) return self._attrChanged end
function Instance:GetChildren() return table.clone(self._children) end
function Instance:FindFirstChild(name: string)
	for _, c in self._children do if c.Name == name then return c end end
	return nil
end
function Instance:WaitForChild(name: string) return self:FindFirstChild(name) end
function Instance:IsA(className: string): boolean return self.ClassName == className end
function Instance:Destroy()
	self._destroyed = true
	if self.Parent then
		local i = table.find(self.Parent._children, self)
		if i then table.remove(self.Parent._children, i) end
	end
	self.Parent = nil
end
Stub.Instance = Instance

-- ---------------------------------------------------------------- Enum (just enough)
Stub.Enum = {
	RaycastFilterType = { Include = "Include", Exclude = "Exclude" },
	UserInputType = { MouseButton1 = "MouseButton1", Touch = "Touch", Gamepad1 = "Gamepad1" },
	KeyCode = { ButtonR2 = "ButtonR2", ButtonL2 = "ButtonL2", ButtonA = "ButtonA", ButtonB = "ButtonB" },
	RenderPriority = { Camera = { Value = 200 }, Input = { Value = 100 } },
	DataStoreRequestType = { GetAsync = "GetAsync", SetIncrementAsync = "SetIncrementAsync", UpdateAsync = "UpdateAsync" },
}

-- ---------------------------------------------------------------- the runtime: clock, task, services
function Stub.new()
	local R: any = {}

	-- the fake clock: R.task.wait advances it; scheduled callbacks run in time order
	local clock = { now = 0 }
	local queue: { { at: number, fn: () -> (), seq: number } } = {}
	local seq = 0
	local function schedule(at: number, fn: () -> ())
		seq += 1
		table.insert(queue, { at = at, fn = fn, seq = seq })
		table.sort(queue, function(a, b)
			if a.at == b.at then return a.seq < b.seq end
			return a.at < b.at
		end)
	end
	local function runUntil(t: number)
		while #queue > 0 and queue[1].at <= t do
			local item = table.remove(queue, 1) :: any
			clock.now = item.at
			item.fn()
		end
		clock.now = t
	end
	R.clock = clock
	R.advance = function(dt: number) runUntil(clock.now + dt) end
	R.runAll = function() runUntil(math.huge); end

	R.task = {
		wait = function(dt: number?): number
			local d = dt or 0
			runUntil(clock.now + d)
			return d
		end,
		spawn = function(fn: (...any) -> (), ...: any) fn(...) end,
		defer = function(fn: (...any) -> (), ...: any)
			local args = table.pack(...)
			schedule(clock.now, function() fn(table.unpack(args, 1, args.n)) end)
		end,
		delay = function(dt: number, fn: (...any) -> (), ...: any)
			local args = table.pack(...)
			schedule(clock.now + dt, function() fn(table.unpack(args, 1, args.n)) end)
		end,
		cancel = function() end,
	}
	R.tick = function() return clock.now end
	R.warnings = {}
	R.warn = function(...: any)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		table.insert(R.warnings, table.concat(parts, " "))
	end

	-- Players
	local Players = Instance.new("Players")
	Players.PlayerAdded = Signal.new()
	Players.PlayerRemoving = Signal.new()
	Players._players = {}
	function Players:GetPlayers() return table.clone(self._players) end
	function Players:addFake(userId: number, name: string?)
		local p = Instance.new("Player")
		p.Name = name or ("Player" .. userId)
		p.UserId = userId
		p.DisplayName = p.Name
		table.insert(self._players, p)
		self.PlayerAdded:Fire(p)
		return p
	end
	function Players:removeFake(p: any)
		local i = table.find(self._players, p)
		if i then table.remove(self._players, i) end
		self.PlayerRemoving:Fire(p)
	end

	-- RunService: Heartbeat/Stepped fired by R.step(dt)
	local RunService = Instance.new("RunService")
	RunService.Heartbeat = Signal.new()
	RunService.Stepped = Signal.new()
	RunService.RenderStepped = Signal.new()
	function RunService:IsServer() return true end
	function RunService:IsClient() return false end
	function RunService:IsStudio() return false end
	R.step = function(dt: number)
		runUntil(clock.now + dt)
		RunService.Stepped:Fire(clock.now, dt)
		RunService.Heartbeat:Fire(dt)
	end

	-- HttpService
	local HttpService = Instance.new("HttpService")
	local guidN = 0
	function HttpService:JSONEncode(v: any) return jsonEncode(v) end
	function HttpService:JSONDecode(s: string) return jsonDecode(s) end
	function HttpService:GenerateGUID(wrap: boolean?)
		guidN += 1
		local g = string.format("%08X-0000-4000-8000-%012X", guidN, guidN)
		return wrap == false and g or "{" .. g .. "}"
	end

	-- DataStoreService: in-memory stores, a request budget, injectable failures, call log
	local DataStoreService = Instance.new("DataStoreService")
	local ds = {
		stores = {} :: { [string]: { [string]: any } },
		calls = {} :: { { op: string, store: string, key: string, t: number } },
		budget = math.huge,
		_failQueue = {} :: { { op: string, msg: string } },
	}
	R.dataStores = ds
	function ds.failNext(op: string, msg: string) table.insert(ds._failQueue, { op = op, msg = msg }) end
	function ds.dump(storeName: string) return table.clone(ds.stores[storeName] or {}) end
	local function record(op: string, storeName: string, key: string)
		table.insert(ds.calls, { op = op, store = storeName, key = key, t = clock.now })
		if ds.budget <= 0 then error("502: API Services rejected request with error. Error code: 3 Reason: Request throttled") end
		ds.budget -= 1
		local f = ds._failQueue[1]
		if f and (f.op == op or f.op == "*") then
			table.remove(ds._failQueue, 1)
			error(f.msg)
		end
	end
	local DataStore = {}
	DataStore.__index = DataStore
	function DataStore:GetAsync(key: string)
		record("GetAsync", self._name, key)
		local v = self._data[key]
		return v ~= nil and jsonDecode(jsonEncode(v)) or nil, { Version = self._versions[key] or "" }
	end
	function DataStore:SetAsync(key: string, value: any, _userIds: any?, _options: any?)
		record("SetAsync", self._name, key)
		self._data[key] = jsonDecode(jsonEncode(value))
		self._versions[key] = tostring((tonumber(self._versions[key]) or 0) + 1)
		return self._versions[key]
	end
	function DataStore:UpdateAsync(key: string, transform: (any, any) -> any)
		record("UpdateAsync", self._name, key)
		local old = self._data[key]
		local copy = old ~= nil and jsonDecode(jsonEncode(old)) or nil
		local new = transform(copy, { Version = self._versions[key] or "" })
		if new == nil then
			return old
		end
		self._data[key] = jsonDecode(jsonEncode(new))
		self._versions[key] = tostring((tonumber(self._versions[key]) or 0) + 1)
		return self._data[key]
	end
	function DataStore:RemoveAsync(key: string)
		record("RemoveAsync", self._name, key)
		local old = self._data[key]
		self._data[key] = nil
		return old
	end
	function DataStoreService:GetDataStore(name: string, _scope: string?)
		ds.stores[name] = ds.stores[name] or {}
		return setmetatable({ _name = name, _data = ds.stores[name], _versions = {} }, DataStore)
	end
	function DataStoreService:GetRequestBudgetForRequestType(_t: any) return ds.budget end

	local services: { [string]: any } = {
		Players = Players,
		RunService = RunService,
		HttpService = HttpService,
		DataStoreService = DataStoreService,
	}
	R.game = {
		GetService = function(_self: any, name: string)
			local s = services[name]
			if not s then error("RobloxStub: no service " .. name .. " (add it to RobloxStub.luau)") end
			return s
		end,
		PlaceId = 0,
		JobId = "stub",
	}
	R.Players, R.RunService, R.HttpService, R.DataStoreService = Players, RunService, HttpService, DataStoreService
	R.Instance = Instance
	R.Vector3 = V3
	R.Enum = Stub.Enum
	return R
end

-- ---------------------------------------------------------------- a tiny check harness for suites
-- local T = Stub.harness("name"); T.check(cond, "label"); ... T.finish()  -> prints PASS n / FAIL k of n, exits 1 on fail
function Stub.harness(name: string)
	local n, fails = 0, {}
	local H = {}
	function H.check(cond: any, label: string)
		n += 1
		if cond then
			print(string.format("  ok   %-4d %s", n, label))
		else
			table.insert(fails, label)
			print(string.format("  FAIL %-4d %s", n, label))
		end
		return cond
	end
	function H.eq(a: any, b: any, label: string)
		local same = a == b
		if not same and typeof(a) == "number" and typeof(b) == "number" then
			same = math.abs(a - b) < 1e-9
		end
		return H.check(same, label .. (same and "" or string.format("  (got %s, want %s)", tostring(a), tostring(b))))
	end
	function H.throws(fn: () -> (), pattern: string?, label: string)
		local ok, err = pcall(fn)
		local hit = not ok and (pattern == nil or tostring(err):find(pattern, 1, true) ~= nil)
		return H.check(hit, label .. (hit and "" or ("  (got " .. tostring(err) .. ")")))
	end
	function H.finish()
		if #fails == 0 then
			print(string.format("%s: PASS %d", name, n))
		else
			print(string.format("%s: FAIL %d of %d", name, #fails, n))
			for _, f in fails do print("   - " .. f) end
			error(string.format("%s failed", name), 0)
		end
	end
	return H
end

return Stub
