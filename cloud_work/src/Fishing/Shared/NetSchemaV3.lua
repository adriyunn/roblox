--!strict
-- NetSchemaV3 (About Fishing F1, WS-N net v3 messages; Cloud, 2026-10-07; design/WSN_net_v3_messages.md)
-- The declarative schema of the v3 messages (ids 32..63; nothing in v2 changes): per message the direction,
-- the player states that may send it, the fields with types and ranges, and the RequestGuard rate.
-- validate() checks a payload, allowed() answers the StateRules question, check() checks the schema itself.
-- encode()/decode() are a REFERENCE canonical encoding, NOT the team's FishingNet v2 codec: little-endian
-- fixed widths, the u8 message id first, str as u8 length + ASCII bytes, ids as u8 count + u16 items, f32
-- via string.pack("<f"), free-form tables as the tagged form of the design note's section 4. It exists so
-- Dev3's vectors (tools/net_vectors_v3.py -> tests/fixtures/net_vectors_v3.json) have one unambiguous
-- byte form to compare against; Dev3 maps every field to the real codec from the same table.
-- WRITTEN WITHOUT THE PROJECT FILES. Dev3 owns the wire (FishingNet, RequestGuard, the StateRules rows),
-- Dev1 the server handlers. The state names are the F1 list from CONTEXT.md and must match StateRules'
-- row names byte for byte. The u8 enums (kind, option keys, reason codes) are listed in the design note,
-- section 6; here they are ranges. No Roblox globals.

local NetSchemaV3 = {}

export type FieldType = "u8" | "u16" | "i16" | "u32" | "f32" | "bool" | "str" | "ids" | "table"
export type Field = { name: string, type: FieldType, min: number?, max: number?, maxLen: number? }
export type Rate = { perS: number, burst: number }
export type Message = { id: number, dir: "C2S" | "S2C", states: { string }, fields: { Field }, rate: Rate }
export type Messages = { [string]: Message }

NetSchemaV3.ID_MIN, NetSchemaV3.ID_MAX = 32, 63
NetSchemaV3.C2S_MAX = 47 -- C2S ids 32..47, S2C ids 48..63
NetSchemaV3.F32_MAX = 3.4028234663852886e38
NetSchemaV3.TABLE_DEPTH_MAX = 8 -- a table field's own table is level 1
NetSchemaV3.STR_MAX = 255 -- u8 length prefix; strings inside tables share the cap

-- The F1 player states (server-checked), the StateRules row names.
NetSchemaV3.STATES = { "Walking", "Aiming", "Flight", "Presenting", "Retrieving", "Inspected", "HookWindow", "Hooked", "CatchScene", "Holding" }
local STATE_SET: { [string]: boolean } = {}
for _, s in NetSchemaV3.STATES do STATE_SET[s] = true end

local TYPES: { [string]: boolean } = { u8 = true, u16 = true, i16 = true, u32 = true, f32 = true, bool = true, str = true, ids = true, table = true }
-- natural ranges of the integer types; a field's min/max narrow them
local INT_RANGE: { [string]: { number } } = { u8 = { 0, 255 }, u16 = { 0, 65535 }, i16 = { -32768, 32767 }, u32 = { 0, 4294967295 } }
local PACK: { [string]: string } = { u8 = "<B", u16 = "<I2", i16 = "<i2", u32 = "<I4", f32 = "<f" }
local WIDTH: { [string]: number } = { u8 = 1, u16 = 2, i16 = 2, u32 = 4, f32 = 4 }

local BOX_AND_SHOP: { string } = { "Walking", "Holding" }
local NOT_FLIGHT_OR_HOOKED: { string } = { "Walking", "Aiming", "Presenting", "Retrieving", "Inspected", "HookWindow", "CatchScene", "Holding" }
local NONE: { string } = {}

-- S2C rates are the server's own per-client send ceiling (fan-out cost), not a RequestGuard row.
NetSchemaV3.MESSAGES = {
	TackleMove = { id = 32, dir = "C2S", states = BOX_AND_SHOP, rate = { perS = 10, burst = 20 }, fields = {
		{ name = "id", type = "u16", min = 1 }, { name = "rot", type = "u8", max = 3 },
		{ name = "x", type = "u8", min = 1, max = 32 }, { name = "y", type = "u8", min = 1, max = 32 } } },
	TackleDrop = { id = 33, dir = "C2S", states = BOX_AND_SHOP, rate = { perS = 2, burst = 4 }, fields = {
		{ name = "id", type = "u16", min = 1 } } },
	Sell = { id = 34, dir = "C2S", states = BOX_AND_SHOP, rate = { perS = 1, burst = 2 }, fields = {
		{ name = "ids", type = "ids", maxLen = 48 } } },
	BuyGear = { id = 35, dir = "C2S", states = BOX_AND_SHOP, rate = { perS = 1, burst = 2 }, fields = {
		{ name = "kind", type = "u8", max = 3 }, { name = "id", type = "str", maxLen = 24 } } },
	Equip = { id = 36, dir = "C2S", states = BOX_AND_SHOP, rate = { perS = 2, burst = 4 }, fields = {
		{ name = "kind", type = "u8", max = 3 }, { name = "id", type = "str", maxLen = 24 } } },
	SetOption = { id = 37, dir = "C2S", states = NOT_FLIGHT_OR_HOOKED, rate = { perS = 5, burst = 10 }, fields = {
		{ name = "key", type = "u8", max = 5 }, { name = "value", type = "f32", min = 0, max = 90 } } },
	TackleMoveResult = { id = 48, dir = "S2C", states = NONE, rate = { perS = 10, burst = 20 }, fields = {
		{ name = "ok", type = "bool" }, { name = "reason", type = "u8", max = 7 } } },
	TackleSync = { id = 49, dir = "S2C", states = NONE, rate = { perS = 10, burst = 20 }, fields = {
		{ name = "w", type = "u8", min = 1, max = 32 }, { name = "h", type = "u8", min = 1, max = 32 },
		{ name = "nextId", type = "u16", min = 1 }, { name = "items", type = "table", maxLen = 4096 } } },
	SellResult = { id = 50, dir = "S2C", states = NONE, rate = { perS = 1, burst = 2 }, fields = {
		{ name = "reason", type = "u8", max = 4 }, { name = "total", type = "u32" }, { name = "coins", type = "u32" },
		{ name = "lines", type = "table", maxLen = 1024 } } },
	BuyResult = { id = 51, dir = "S2C", states = NONE, rate = { perS = 2, burst = 4 }, fields = {
		{ name = "op", type = "u8", max = 1 }, { name = "ok", type = "bool" }, { name = "reason", type = "u8", max = 6 },
		{ name = "coins", type = "u32" } } },
	CatchLogSync = { id = 52, dir = "S2C", states = NONE, rate = { perS = 1, burst = 2 }, fields = {
		{ name = "log", type = "table", maxLen = 4096 } } },
	WorldSync = { id = 53, dir = "S2C", states = NONE, rate = { perS = 0.2, burst = 2 }, fields = {
		{ name = "clockTime", type = "f32", min = 0, max = 24 }, { name = "dayN", type = "u16", min = 1 },
		{ name = "phase", type = "u8", max = 3 }, { name = "weather", type = "u8", max = 2 },
		{ name = "rain", type = "f32", min = 0, max = 1 }, { name = "waveM", type = "f32", min = 0, max = 0.5 },
		{ name = "sun", type = "f32", min = -1, max = 1 } } },
	ProfileReady = { id = 54, dir = "S2C", states = NONE, rate = { perS = 1, burst = 1 }, fields = {
		{ name = "readOnly", type = "bool" }, { name = "reason", type = "u8", max = 5 } } },
} :: Messages

-- ---------------------------------------------------------------- helpers
local function isFinite(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v: any): boolean return isFinite(v) and v == math.floor(v) end

-- printable ASCII only (0x20..0x7E)
local function isAscii(s: string): boolean
	return string.find(s, "[^\32-\126]") == nil
end

-- "array" (keys exactly 1..n; an empty table is an array), "map" (all string keys) or nil (mixed), plus n.
local function tableKind(t: { [any]: any }): (string?, number)
	local n, ints, strs = 0, 0, 0
	for k in t do
		n += 1
		if typeof(k) == "string" then strs += 1 elseif isInt(k) and k >= 1 then ints += 1 end
	end
	if ints == n then
		for i = 1, n do if t[i] == nil then return nil, n end end
		return "array", n
	end
	return if strs == n then "map" else nil, n
end

-- Node count of a JSON-safe printable-ASCII tree, or nil when it is not one (mixed keys, non-finite
-- numbers, non-ASCII or over-long strings, functions, deeper than TABLE_DEPTH_MAX).
local function walk(v: any, depth: number): number?
	local t = typeof(v)
	if t == "boolean" then return 1 end
	if t == "number" then return if isFinite(v) then 1 else nil end
	if t == "string" then return if #v <= NetSchemaV3.STR_MAX and isAscii(v) then 1 else nil end
	if t ~= "table" or depth > NetSchemaV3.TABLE_DEPTH_MAX then return nil end
	local kind = tableKind(v)
	if kind == nil then return nil end
	local total = 1
	for k, child in v do
		local key: string = if kind == "map" then k else ""
		if #key > NetSchemaV3.STR_MAX or not isAscii(key) then return nil end
		local c = walk(child, depth + 1)
		if c == nil then return nil end
		total += c
	end
	return total
end

local function messagesOf(messages: Messages?): Messages return messages or NetSchemaV3.MESSAGES end

-- ---------------------------------------------------------------- validation
-- Why a value is not a legal value of the field (the reason strings of the design note, section 5), or nil.
function NetSchemaV3.fieldProblem(f: Field, v: any): string?
	local t, range = f.type, INT_RANGE[f.type]
	if range then
		if not isInt(v) then return f.name .. ": expected " .. t end
		if v < math.max(range[1], f.min or range[1]) or v > math.min(range[2], f.max or range[2]) then return f.name .. ": out of range" end
	elseif t == "f32" then
		if not isFinite(v) then return f.name .. ": expected f32" end
		if v < (f.min or -NetSchemaV3.F32_MAX) or v > (f.max or NetSchemaV3.F32_MAX) then return f.name .. ": out of range" end
	elseif t == "bool" then
		if typeof(v) ~= "boolean" then return f.name .. ": expected bool" end
	elseif t == "str" then
		if typeof(v) ~= "string" then return f.name .. ": expected str" end
		if #v > (f.maxLen or NetSchemaV3.STR_MAX) then return f.name .. ": too long" end
		if not isAscii(v) then return f.name .. ": not ASCII" end
	elseif t == "ids" then
		local kind: string?, n = nil, 0
		if typeof(v) == "table" then kind, n = tableKind(v) end
		if kind ~= "array" then return f.name .. ": expected ids" end
		if n > (f.maxLen or 255) then return f.name .. ": too long" end
		local lo, hi = f.min or 1, f.max or 65535
		for i = 1, n do
			local e = v[i]
			if not isInt(e) or e < lo or e > hi then return f.name .. ": bad id" end
		end
	elseif t == "table" then
		if typeof(v) ~= "table" then return f.name .. ": expected table" end
		local n = walk(v, 1)
		if n == nil then return f.name .. ": bad table" end
		if n > (f.maxLen or 1024) then return f.name .. ": too long" end
	else
		error("NetSchemaV3: unknown field type " .. tostring(t))
	end
	return nil
end

-- ok, reason. Every field present and legal (schema order), then no extra keys (first in sorted order).
function NetSchemaV3.validate(name: string, payload: any, messages: Messages?): (boolean, string?)
	local m = messagesOf(messages)[name]
	if m == nil then return false, "unknown message" end
	if typeof(payload) ~= "table" then return false, "payload must be a table" end
	local known: { [string]: boolean } = {}
	for _, f in m.fields do
		known[f.name] = true
		if payload[f.name] == nil then return false, "missing " .. f.name end
	end
	for _, f in m.fields do
		local problem = NetSchemaV3.fieldProblem(f, payload[f.name])
		if problem then return false, problem end
	end
	local extra: { string } = {}
	for k in payload do
		if typeof(k) ~= "string" or not known[k] then table.insert(extra, tostring(k)) end
	end
	if #extra > 0 then
		table.sort(extra)
		return false, "unexpected " .. extra[1]
	end
	return true, nil
end

-- May a client in this state send the message? False for S2C messages, unknown names and unknown states.
function NetSchemaV3.allowed(name: string, state: string, messages: Messages?): boolean
	local m = messagesOf(messages)[name]
	if m == nil or m.dir ~= "C2S" or not STATE_SET[state] then return false end
	return table.find(m.states, state) ~= nil
end

-- Every message id, sorted.
function NetSchemaV3.ids(messages: Messages?): { number }
	local out: { number } = {}
	for _, m in messagesOf(messages) do table.insert(out, m.id) end
	table.sort(out)
	return out
end

-- The message name for an id, or nil.
function NetSchemaV3.nameOf(id: number, messages: Messages?): string?
	for name, m in messagesOf(messages) do
		if m.id == id then return name end
	end
	return nil
end

-- ---------------------------------------------------------------- reference encoding
-- Tagged value form for `table` fields: 1 false, 2 true, 3 i32 (integral values in i32 range), 4 f64,
-- 5 str (u16 length + bytes), 6 array (u16 count + values), 7 map (u16 count + (u16 key length + key +
-- value) pairs, keys in byte order). An empty table is an empty array, like HttpService:JSONEncode.
local function packValue(v: any): string
	local t = typeof(v)
	if t == "boolean" then return if v then "\2" else "\1" end
	if t == "number" then
		if isInt(v) and v >= -2147483648 and v <= 2147483647 then return "\3" .. string.pack("<i4", v) end
		return "\4" .. string.pack("<d", v)
	end
	if t == "string" then return "\5" .. string.pack("<I2", #v) .. v end
	if t ~= "table" then error("NetSchemaV3.encode: value is not JSON-safe (" .. t .. ")") end
	local kind, n = tableKind(v)
	if kind == "array" then
		local parts = { "\6" .. string.pack("<I2", n) }
		for i = 1, n do table.insert(parts, packValue(v[i])) end
		return table.concat(parts)
	elseif kind == "map" then
		local keys: { string } = {}
		for k in v do table.insert(keys, k) end
		table.sort(keys)
		local parts = { "\7" .. string.pack("<I2", n) }
		for _, k in keys do table.insert(parts, string.pack("<I2", #k) .. k .. packValue(v[k])) end
		return table.concat(parts)
	end
	error("NetSchemaV3.encode: table mixes array and string keys")
end

local function packField(f: Field, v: any): string
	local fmt = PACK[f.type]
	if fmt then return string.pack(fmt, v) end
	if f.type == "bool" then return string.pack("<B", if v then 1 else 0) end
	if f.type == "str" then return string.pack("<B", #v) .. v end
	if f.type == "ids" then
		local arr: { number } = v
		local parts = { string.pack("<B", #arr) }
		for i = 1, #arr do table.insert(parts, string.pack("<I2", arr[i])) end
		return table.concat(parts)
	end
	return packValue(v)
end

-- The canonical bytes of a message (validated first; a bad payload is a programmer error and errors).
function NetSchemaV3.encode(name: string, payload: { [string]: any }, messages: Messages?): string
	local ok, why = NetSchemaV3.validate(name, payload, messages)
	if not ok then error("NetSchemaV3.encode: " .. name .. ": " .. tostring(why)) end
	local m = messagesOf(messages)[name]
	local parts = { string.pack("<B", m.id) }
	for _, f in m.fields do table.insert(parts, packField(f, payload[f.name])) end
	return table.concat(parts)
end

-- name, payload from canonical bytes; errors on an unknown id, truncation, a bad tag or trailing bytes.
function NetSchemaV3.decode(bytes: string, messages: Messages?): (string, { [string]: any })
	local pos = 1
	local function read(fmt: string, width: number): any
		if pos + width - 1 > #bytes then error("NetSchemaV3.decode: truncated at byte " .. pos) end
		local v, nxt = string.unpack(fmt, bytes, pos)
		pos = nxt :: number
		return v
	end
	local function readStr(fmt: string, width: number): string
		local n: number = read(fmt, width)
		if pos + n - 1 > #bytes then error("NetSchemaV3.decode: truncated at byte " .. pos) end
		local s = string.sub(bytes, pos, pos + n - 1)
		pos += n
		return s
	end
	local function unpackValue(depth: number): any
		if depth > NetSchemaV3.TABLE_DEPTH_MAX then error("NetSchemaV3.decode: table deeper than " .. NetSchemaV3.TABLE_DEPTH_MAX) end
		local tag: number = read("<B", 1)
		if tag == 1 or tag == 2 then return tag == 2 end
		if tag == 3 then return read("<i4", 4) end
		if tag == 4 then return read("<d", 8) end
		if tag == 5 then return readStr("<I2", 2) end
		if tag == 6 then
			local n: number = read("<I2", 2)
			local out: { any } = {}
			for i = 1, n do out[i] = unpackValue(depth + 1) end
			return out
		elseif tag == 7 then
			local n: number = read("<I2", 2)
			local out: { [string]: any } = {}
			for _ = 1, n do
				local k = readStr("<I2", 2)
				out[k] = unpackValue(depth + 1)
			end
			return out
		end
		error("NetSchemaV3.decode: bad value tag " .. tostring(tag) .. " at byte " .. (pos - 1))
	end
	local id: number = read("<B", 1)
	local name = NetSchemaV3.nameOf(id, messages)
	if name == nil then error("NetSchemaV3.decode: unknown message id " .. tostring(id)) end
	local payload: { [string]: any } = {}
	for _, f in messagesOf(messages)[name].fields do
		local fmt = PACK[f.type]
		if fmt then
			payload[f.name] = read(fmt, WIDTH[f.type])
		elseif f.type == "bool" then
			local b: number = read("<B", 1)
			if b > 1 then error("NetSchemaV3.decode: bad bool byte " .. b .. " in " .. f.name) end
			payload[f.name] = b == 1
		elseif f.type == "str" then
			payload[f.name] = readStr("<B", 1)
		elseif f.type == "ids" then
			local n: number = read("<B", 1)
			local arr: { number } = {}
			for i = 1, n do arr[i] = read("<I2", 2) end
			payload[f.name] = arr
		else
			payload[f.name] = unpackValue(1)
		end
	end
	if pos <= #bytes then error("NetSchemaV3.decode: " .. (#bytes - pos + 1) .. " trailing bytes after " .. name) end
	return name, payload
end

-- Lower-case hex of a byte string, and back (the vectors' `hex` field).
function NetSchemaV3.toHex(bytes: string): string
	return (string.gsub(bytes, ".", function(c: string): string return string.format("%02x", string.byte(c)) end))
end

function NetSchemaV3.fromHex(hex: string): string
	assert(#hex % 2 == 0 and not string.find(hex, "[^0-9a-fA-F]"), "NetSchemaV3.fromHex: not a hex string")
	return (string.gsub(hex, "..", function(h: string): string return string.char(tonumber(h, 16) :: number) end))
end

-- ---------------------------------------------------------------- the schema's own check
-- Unique ids in 32..63 on the right side of the C2S/S2C split, known states and types, consistent
-- min/max/maxLen, sane rates. Checks MESSAGES or the given table. Returns true or errors naming the spot.
function NetSchemaV3.check(messages: Messages?): boolean
	local function fail(where: string, why: string) error(string.format("NetSchemaV3.check: %s: %s", where, why)) end
	local byId: { [number]: string } = {}
	for name, m in messagesOf(messages) do
		if typeof(name) ~= "string" or name == "" or typeof(m) ~= "table" then fail(tostring(name), "messages map non-empty names to tables") end
		if not isInt(m.id) or m.id < NetSchemaV3.ID_MIN or m.id > NetSchemaV3.ID_MAX then fail(name, "id must be an integer in 32..63") end
		if byId[m.id] then fail(name, string.format("id %d already used by %s", m.id, byId[m.id])) end
		byId[m.id] = name
		if m.dir ~= "C2S" and m.dir ~= "S2C" then fail(name, "dir must be C2S or S2C") end
		if (m.dir == "C2S") ~= (m.id <= NetSchemaV3.C2S_MAX) then fail(name, "C2S ids are 32..47, S2C ids 48..63") end
		if typeof(m.states) ~= "table" or typeof(m.fields) ~= "table" or typeof(m.rate) ~= "table" then fail(name, "needs states, fields and rate tables") end
		local seen: { [string]: boolean } = {}
		for _, s in m.states do
			if not STATE_SET[s] then fail(name, "unknown state '" .. tostring(s) .. "'") end
			if seen[s] then fail(name, "state listed twice: " .. s) end
			seen[s] = true
		end
		if (m.dir == "C2S") ~= (#m.states > 0) then fail(name, "a C2S message needs sender states; an S2C message has none") end
		local names: { [string]: boolean } = {}
		for _, f in m.fields do
			if typeof(f.name) ~= "string" or f.name == "" then fail(name, "field names must be non-empty strings") end
			if names[f.name] then fail(name, "field listed twice: " .. f.name) end
			names[f.name] = true
			local where = name .. "." .. f.name
			if not TYPES[f.type] then fail(where, "unknown type '" .. tostring(f.type) .. "'") end
			local range = INT_RANGE[f.type]
			local lo, hi = -NetSchemaV3.F32_MAX, NetSchemaV3.F32_MAX
			if range then
				lo, hi = range[1], range[2]
			elseif f.type == "ids" then
				lo, hi = 1, 65535
			elseif f.type ~= "f32" and (f.min ~= nil or f.max ~= nil) then
				fail(where, "min/max only on numeric and ids fields")
			end
			local integral = range ~= nil or f.type == "ids"
			if f.min ~= nil and (not isFinite(f.min) or f.min < lo or (integral and not isInt(f.min))) then fail(where, "min outside the type's range") end
			if f.max ~= nil and (not isFinite(f.max) or f.max > hi or (integral and not isInt(f.max))) then fail(where, "max outside the type's range") end
			if f.min ~= nil and f.max ~= nil and f.min > f.max then fail(where, "min above max") end
			if f.maxLen ~= nil then
				if f.type ~= "str" and f.type ~= "ids" and f.type ~= "table" then fail(where, "maxLen only on str, ids and table fields") end
				if not isInt(f.maxLen) or f.maxLen < 1 or (f.type ~= "table" and f.maxLen > 255) then fail(where, "maxLen must be an integer in 1..255 (table: any positive integer)") end
			end
		end
		local r = m.rate
		if not isFinite(r.perS) or not isFinite(r.burst) or r.perS < 0 or r.burst < 0 then fail(name, "rate needs perS and burst >= 0") end
		if m.dir == "C2S" and (r.perS <= 0 or not isInt(r.burst) or r.burst < 1) then fail(name, "a C2S rate needs perS > 0 and an integer burst >= 1") end
	end
	return true
end

return NetSchemaV3
