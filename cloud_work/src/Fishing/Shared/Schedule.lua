--!strict
-- Schedule (About Fishing F1, WS-T town routines; Cloud, 2026-10-08; design/PARITY_rows_F2plus.md rows P16, P17)
-- NPC daily routines and the day-to-day town changes as validated data: each NPC has an ordered list
-- of slots tiling 0..24 h (where it is, what it does, which line set it speaks), optional per-day
-- replacements (an exact day, "even"/"odd" days, "storm" days) and conditional slots that win while
-- the weather or a story flag matches; the town has a list of toggles (a stall opens on day 3, a sign
-- changes once a clue is found). Everything is a pure lookup on (timeH, dayN, ctx): no rng, no clock
-- of its own; WorldClock supplies timeH and dayN.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * The NPC table and the town toggles are placeholder ids (npc_a, dock, greet_a, stall_b_open):
--     the game's own writing and world replace them; this module never carries text.
--   * FishingServer: Schedule.everyone(def, clock.timeH, clock.dayN, ctx) each time the hour crosses a
--     slot edge (Schedule.next gives the seconds to wait) moves the NPC objects; ctx = { weather =
--     clock.weather, flags = the player's story flags }. NPCs are server objects shared by everyone
--     on the server (P16): drive them from the server clock and a server-wide flag set, and use the
--     per-player flags only for lineSet (the dialogue) if the P07 ruling makes the clock per player.
--   * Town variants (P17): Schedule.townState(def, dayN, flags).changes is the list of toggles to
--     apply (props, stalls, signs); .slots says which toggle holds each prop slot, so no two variants
--     place props in the same slot (DEFINE refuses such a table).
--   * Walking between stops needs the world's waypoint graph; Schedule.plan(def, npcId, dayN, ctx)
--     lists the day's stops in order so a test can check a route exists between consecutive ones.
-- Hour values are in-game hours (0 <= h < 24); seconds come from WorldClock's dayLengthS.

local Schedule = {}

export type Conditions = { weather: string?, flags: { [string]: boolean }? }
export type Slot = { fromH: number, toH: number, place: string, activity: string, lineSet: string?, conditions: Conditions? }
export type DayOverride = { slots: { Slot } }
export type NpcDef = { slots: { Slot }, byDay: { [any]: DayOverride }? }
export type TownChange = { id: string, slot: string?, fromDay: number?, toDay: number?, days: string?, flags: { string }?, notFlags: { string }? }
export type Town = { changes: { TownChange } }
export type Def = { npcs: { [string]: NpcDef }, order: { string }, town: Town }
export type Ctx = { weather: string?, flags: { [string]: any }? }
export type At = { place: string, activity: string, lineSet: string?, slotIndex: number }
export type PlanRow = { fromH: number, toH: number, place: string, activity: string, lineSet: string? }
export type TownState = { dayN: number, changes: { string }, slots: { [string]: string } }

Schedule.DAY_KEYS = { "even", "odd", "storm" } -- the string keys byDay accepts besides an exact day number
Schedule.STORM_WEATHER = "rain" -- the "storm" override applies while ctx.weather equals this
local MAX_NEXT_DAYS = 2 -- Schedule.next looks this many days ahead for a change

-- ---------------------------------------------------------------- helpers
local function isNum(v: any): boolean
	return typeof(v) == "number" and v == v and math.abs(v) < math.huge
end

local function isInt(v: any): boolean
	return isNum(v) and v == math.floor(v)
end

local function nonEmpty(v: any): boolean
	return typeof(v) == "string" and v ~= ""
end

local function fmt(h: number): string
	return string.format("%g", h)
end

local function checkConditions(label: string, c: any)
	if typeof(c) ~= "table" then
		error(label .. ": conditions must be a table")
	end
	if c.weather ~= nil and not nonEmpty(c.weather) then
		error(label .. ": conditions.weather must be a non-empty string")
	end
	if c.flags ~= nil then
		if typeof(c.flags) ~= "table" then
			error(label .. ": conditions.flags must be a table of flag = true/false")
		end
		for name, want in c.flags do
			if not nonEmpty(name) or typeof(want) ~= "boolean" then
				error(label .. ": conditions.flags must map flag names to true/false")
			end
		end
	end
	for k in c do
		if k ~= "weather" and k ~= "flags" then
			error(label .. ": unknown condition " .. tostring(k))
		end
	end
end

-- Errors naming the npc and the gap or overlap when the unconditional slots do not tile 0..24 exactly.
local function checkSlots(label: string, slots: any)
	if typeof(slots) ~= "table" or #slots == 0 then
		error(label .. ": slots must be a non-empty array")
	end
	local cursor = 0
	local unconditional = 0
	for i = 1, #slots do
		local s: any = slots[i]
		local sl = label .. " slot " .. i
		if typeof(s) ~= "table" then
			error(sl .. ": must be a table")
		end
		if not isNum(s.fromH) or not isNum(s.toH) or s.fromH < 0 or s.toH > 24 or s.fromH >= s.toH then
			error(sl .. ": needs 0 <= fromH < toH <= 24 (got " .. tostring(s.fromH) .. ".." .. tostring(s.toH) .. ")")
		end
		if not nonEmpty(s.place) then
			error(sl .. ": place must be a non-empty string")
		end
		if not nonEmpty(s.activity) then
			error(sl .. ": activity must be a non-empty string")
		end
		if s.lineSet ~= nil and not nonEmpty(s.lineSet) then
			error(sl .. ": lineSet must be a non-empty string when given")
		end
		if s.conditions ~= nil then
			checkConditions(sl, s.conditions)
		else
			if s.fromH > cursor then
				error(label .. ": gap " .. fmt(cursor) .. ".." .. fmt(s.fromH) .. " before slot " .. i)
			elseif s.fromH < cursor then
				error(label .. ": overlap " .. fmt(s.fromH) .. ".." .. fmt(math.min(cursor, s.toH)) .. " at slot " .. i)
			end
			cursor = s.toH
			unconditional += 1
		end
	end
	if unconditional == 0 then
		error(label .. ": every slot is conditional; at least one unconditional slot must cover each hour")
	end
	if cursor < 24 then
		error(label .. ": gap " .. fmt(cursor) .. "..24 after the last slot")
	end
end

local function copySlot(s: Slot): Slot
	local c: Conditions? = nil
	if s.conditions then
		c = { weather = s.conditions.weather, flags = if s.conditions.flags then table.clone(s.conditions.flags) else nil }
	end
	return { fromH = s.fromH, toH = s.toH, place = s.place, activity = s.activity, lineSet = s.lineSet, conditions = c }
end

local function copySlots(slots: { Slot }): { Slot }
	local out = {}
	for i, s in slots do
		out[i] = copySlot(s)
	end
	return out
end

local function checkStringList(label: string, list: any): { string }
	if typeof(list) ~= "table" then
		error(label .. " must be an array of strings")
	end
	local out = {}
	for i = 1, #list do
		if not nonEmpty(list[i]) then
			error(label .. " must be an array of non-empty strings")
		end
		out[i] = list[i]
	end
	return out
end

local function has(list: { string }?, name: string): boolean
	return list ~= nil and table.find(list, name) ~= nil
end

-- Two town changes can never be active on the same day when a flag one needs is one the other forbids.
local function exclusive(a: TownChange, b: TownChange): boolean
	if a.days and b.days and a.days ~= b.days then
		return true
	end
	local aFrom, aTo = a.fromDay or 1, a.toDay or math.huge
	local bFrom, bTo = b.fromDay or 1, b.toDay or math.huge
	if aTo < bFrom or bTo < aFrom then
		return true
	end
	for _, f in a.flags or {} do
		if has(b.notFlags, f) then
			return true
		end
	end
	for _, f in b.flags or {} do
		if has(a.notFlags, f) then
			return true
		end
	end
	return false
end

local function checkTown(town: any): Town
	if town == nil then
		return { changes = {} }
	end
	if typeof(town) ~= "table" or typeof(town.changes) ~= "table" then
		error("Schedule.DEFINE: town.changes must be an array")
	end
	local out: { TownChange } = {}
	local seen: { [string]: boolean } = {}
	for i = 1, #town.changes do
		local c: any = town.changes[i]
		local label = "Schedule.DEFINE: town change " .. i
		if typeof(c) ~= "table" or not nonEmpty(c.id) then
			error(label .. ": id must be a non-empty string")
		end
		label = "Schedule.DEFINE: town change " .. c.id
		if seen[c.id] then
			error(label .. ": duplicate id")
		end
		seen[c.id] = true
		if c.slot ~= nil and not nonEmpty(c.slot) then
			error(label .. ": slot must be a non-empty string when given")
		end
		if c.fromDay ~= nil and (not isInt(c.fromDay) or c.fromDay < 1) then
			error(label .. ": fromDay must be an integer >= 1")
		end
		if c.toDay ~= nil and (not isInt(c.toDay) or c.toDay < (c.fromDay or 1)) then
			error(label .. ": toDay must be an integer >= fromDay")
		end
		if c.days ~= nil and c.days ~= "even" and c.days ~= "odd" then
			error(label .. ": days must be \"even\" or \"odd\"")
		end
		local change: TownChange = {
			id = c.id,
			slot = c.slot,
			fromDay = c.fromDay,
			toDay = c.toDay,
			days = c.days,
			flags = if c.flags ~= nil then checkStringList(label .. ": flags", c.flags) else nil,
			notFlags = if c.notFlags ~= nil then checkStringList(label .. ": notFlags", c.notFlags) else nil,
		}
		for _, other in out do
			if change.slot ~= nil and other.slot == change.slot and not exclusive(change, other) then
				error(label .. " and " .. other.id .. " can both hold slot " .. change.slot .. " on the same day")
			end
		end
		table.insert(out, change)
	end
	return { changes = out }
end

-- ---------------------------------------------------------------- the definition
-- Validates and copies the NPC table (and the optional town toggles). Errors name the npc, the slot
-- and the gap or overlap so a data mistake is one line to fix.
function Schedule.DEFINE(npcs: { [string]: any }, town: any?): Def
	if typeof(npcs) ~= "table" then
		error("Schedule.DEFINE: npcs must be a table of npcId = { slots = ... }")
	end
	local order: { string } = {}
	for id in npcs do
		if not nonEmpty(id) then
			error("Schedule.DEFINE: npc ids must be non-empty strings")
		end
		table.insert(order, id)
	end
	table.sort(order)
	local defs: { [string]: NpcDef } = {}
	for _, id in order do
		local npc: any = npcs[id]
		if typeof(npc) ~= "table" then
			error("Schedule.DEFINE: " .. id .. " must be a table")
		end
		local label = "Schedule.DEFINE: " .. id
		checkSlots(label, npc.slots)
		local byDay: { [any]: DayOverride }? = nil
		if npc.byDay ~= nil then
			if typeof(npc.byDay) ~= "table" then
				error(label .. ": byDay must be a table")
			end
			local bd: { [any]: DayOverride } = {}
			for key, ov in npc.byDay do
				local keyOk = (isInt(key) and key >= 1) or table.find(Schedule.DAY_KEYS, key) ~= nil
				if not keyOk then
					error(label .. ": byDay key must be a day number >= 1, \"even\", \"odd\" or \"storm\" (got " .. tostring(key) .. ")")
				end
				if typeof(ov) ~= "table" then
					error(label .. " byDay " .. tostring(key) .. ": must be { slots = ... }")
				end
				checkSlots(label .. " byDay " .. tostring(key), ov.slots)
				bd[key] = { slots = copySlots(ov.slots) }
			end
			byDay = bd
		end
		defs[id] = { slots = copySlots(npc.slots), byDay = byDay }
	end
	return { npcs = defs, order = order, town = checkTown(town) }
end

-- ---------------------------------------------------------------- lookups
local function conditionsHold(c: Conditions?, ctx: Ctx): boolean
	if c == nil then
		return true
	end
	if c.weather ~= nil and ctx.weather ~= c.weather then
		return false
	end
	if c.flags then
		local flags: { [string]: any } = ctx.flags or {}
		for name, want in c.flags do
			if (flags[name] == true) ~= want then
				return false
			end
		end
	end
	return true
end

-- The slot list in force on a day: exact day, then "storm" while it rains, then even/odd, then base.
local function activeSlots(npc: NpcDef, dayN: number, ctx: Ctx): { Slot }
	local byDay = npc.byDay
	if byDay then
		local exact: DayOverride? = byDay[dayN]
		if exact then
			return exact.slots
		end
		local storm: DayOverride? = byDay.storm
		if storm and ctx.weather == Schedule.STORM_WEATHER then
			return storm.slots
		end
		local parity: DayOverride? = byDay[if dayN % 2 == 0 then "even" else "odd"]
		if parity then
			return parity.slots
		end
	end
	return npc.slots
end

-- The first matching conditional slot wins; otherwise the unconditional slot covering the hour.
local function resolve(slots: { Slot }, h: number, ctx: Ctx): At
	local base: number? = nil
	for i, s in slots do
		if h >= s.fromH and h < s.toH then
			if s.conditions == nil then
				if base == nil then
					base = i
				end
			elseif conditionsHold(s.conditions, ctx) then
				local c = s
				return { place = c.place, activity = c.activity, lineSet = c.lineSet, slotIndex = i }
			end
		end
	end
	local b = slots[base :: number]
	return { place = b.place, activity = b.activity, lineSet = b.lineSet, slotIndex = base :: number }
end

local function sameAt(a: At, b: At): boolean
	return a.place == b.place and a.activity == b.activity and a.lineSet == b.lineSet
end

local function checkTime(timeH: any): (number?, string?)
	if not isNum(timeH) or timeH < 0 or timeH > 24 then
		return nil, "timeH must be in 0..24"
	end
	return timeH % 24, nil
end

local function checkDay(dayN: any): string?
	if not isInt(dayN) or dayN < 1 then
		return "dayN must be an integer >= 1"
	end
	return nil
end

-- Where an NPC is at an hour of a day: { place, activity, lineSet, slotIndex }, or nil, reason.
function Schedule.at(def: Def, npcId: string, timeH: number, dayN: number, ctx: Ctx?): (At?, string?)
	local npc = def.npcs[npcId]
	if npc == nil then
		return nil, "unknown npc " .. tostring(npcId)
	end
	local h, why = checkTime(timeH)
	if h == nil then
		return nil, why
	end
	local dayWhy = checkDay(dayN)
	if dayWhy then
		return nil, dayWhy
	end
	local c: Ctx = ctx or {}
	return resolve(activeSlots(npc, dayN, c), h, c), nil
end

-- Real seconds until the NPC's place, activity or line set next changes (ctx held fixed), looking up
-- to two days ahead; nil, reason when nothing changes in that span or the input is bad.
function Schedule.next(def: Def, npcId: string, timeH: number, dayLengthS: number, dayN: number?, ctx: Ctx?): (number?, string?)
	if not isNum(dayLengthS) or dayLengthS <= 0 then
		return nil, "dayLengthS must be > 0"
	end
	local day = dayN or 1
	local c: Ctx = ctx or {}
	local now, why = Schedule.at(def, npcId, timeH, day, c)
	if now == nil then
		return nil, why
	end
	local h = timeH % 24
	local npc = def.npcs[npcId]
	local offsetH = 0 -- hours from timeH to the start of the day being scanned
	for d = 0, MAX_NEXT_DAYS - 1 do
		local slots = activeSlots(npc, day + d, c)
		local edges: { number } = {}
		local seen: { [number]: boolean } = {}
		local from = if d == 0 then h else 0
		if d > 0 then
			edges[1] = 0
			seen[0] = true
		end
		for _, s in slots do
			for _, e in { s.fromH, s.toH } do
				if e > from and e < 24 and not seen[e] then
					seen[e] = true
					table.insert(edges, e)
				end
			end
		end
		table.sort(edges)
		for _, e in edges do
			if not sameAt(resolve(slots, e, c), now) then
				return (offsetH + e - from) / 24 * dayLengthS, nil
			end
		end
		offsetH += 24 - from
	end
	return nil, "no change within " .. MAX_NEXT_DAYS .. " days"
end

-- Every NPC at once, keyed by id (iteration order of the result is by sorted id via def.order).
function Schedule.everyone(def: Def, timeH: number, dayN: number, ctx: Ctx?): { [string]: At }
	local out: { [string]: At } = {}
	for _, id in def.order do
		local at, why = Schedule.at(def, id, timeH, dayN, ctx)
		if at == nil then
			error("Schedule.everyone: " .. tostring(why))
		end
		out[id] = at
	end
	return out
end

-- The resolved day for one NPC as rows { fromH, toH, place, activity, lineSet } (ctx held fixed),
-- adjacent identical rows merged: the stop list a route check or a debug panel wants.
function Schedule.plan(def: Def, npcId: string, dayN: number?, ctx: Ctx?): ({ PlanRow }?, string?)
	local npc = def.npcs[npcId]
	if npc == nil then
		return nil, "unknown npc " .. tostring(npcId)
	end
	local day = dayN or 1
	local dayWhy = checkDay(day)
	if dayWhy then
		return nil, dayWhy
	end
	local c: Ctx = ctx or {}
	local slots = activeSlots(npc, day, c)
	local edges: { number } = { 0 }
	local seen: { [number]: boolean } = { [0] = true }
	for _, s in slots do
		for _, e in { s.fromH, s.toH } do
			if e < 24 and not seen[e] then
				seen[e] = true
				table.insert(edges, e)
			end
		end
	end
	table.sort(edges)
	local rows: { PlanRow } = {}
	for i, e in edges do
		local at = resolve(slots, e, c)
		local toH = edges[i + 1] or 24
		local last = rows[#rows]
		if last and last.place == at.place and last.activity == at.activity and last.lineSet == at.lineSet then
			last.toH = toH
		else
			table.insert(rows, { fromH = e, toH = toH, place = at.place, activity = at.activity, lineSet = at.lineSet })
		end
	end
	return rows, nil
end

-- ---------------------------------------------------------------- the town
-- Which toggles are on for a day and a flag set: { dayN, changes = ids in definition order,
-- slots = { [slot] = id } }. "The town changes with each passing day" is this list, applied by the
-- client (per-player day) or the server (shared day) to props, stalls and signs.
function Schedule.townState(def: Def, dayN: number, flags: { [string]: any }?): TownState
	local dayWhy = checkDay(dayN)
	if dayWhy then
		error("Schedule.townState: " .. dayWhy)
	end
	local f: { [string]: any } = flags or {}
	local parity = if dayN % 2 == 0 then "even" else "odd"
	local changes: { string } = {}
	local slots: { [string]: string } = {}
	for _, c in def.town.changes do
		local on = (c.fromDay == nil or dayN >= c.fromDay) and (c.toDay == nil or dayN <= c.toDay) and (c.days == nil or c.days == parity)
		if on and c.flags then
			for _, name in c.flags do
				if f[name] ~= true then
					on = false
					break
				end
			end
		end
		if on and c.notFlags then
			for _, name in c.notFlags do
				if f[name] == true then
					on = false
					break
				end
			end
		end
		if on then
			table.insert(changes, c.id)
			if c.slot then
				slots[c.slot] = c.id
			end
		end
	end
	return { dayN = dayN, changes = changes, slots = slots }
end

-- ---------------------------------------------------------------- data file form
-- A JSON-safe copy of the definition (byDay as an array of { key, slots } because JSON has no numeric
-- keys), so the routines can live in a data file the writing pass edits; deserialize runs DEFINE again.
function Schedule.serialize(def: Def): { [string]: any }
	local npcs: { any } = {}
	for _, id in def.order do
		local npc = def.npcs[id]
		local row: { [string]: any } = { id = id, slots = copySlots(npc.slots) }
		if npc.byDay then
			local keys: { any } = {}
			for key in npc.byDay do
				table.insert(keys, key)
			end
			table.sort(keys, function(x: any, y: any): boolean
				if typeof(x) ~= typeof(y) then
					return typeof(x) == "number"
				end
				return x < y
			end)
			local byDay: { any } = {}
			for _, key in keys do
				table.insert(byDay, { key = key, slots = copySlots(npc.byDay[key].slots) })
			end
			row.byDay = byDay
		end
		table.insert(npcs, row)
	end
	local changes: { any } = {}
	for _, c in def.town.changes do
		table.insert(changes, {
			id = c.id,
			slot = c.slot,
			fromDay = c.fromDay,
			toDay = c.toDay,
			days = c.days,
			flags = if c.flags then table.clone(c.flags) else nil,
			notFlags = if c.notFlags then table.clone(c.notFlags) else nil,
		})
	end
	return { v = 1, npcs = npcs, town = { changes = changes } }
end

-- The inverse of serialize: rebuilds the npc table and runs every DEFINE check again, so a hand-edited
-- or tampered file fails with the same messages.
function Schedule.deserialize(tbl: any): Def
	if typeof(tbl) ~= "table" or tbl.v ~= 1 or typeof(tbl.npcs) ~= "table" then
		error("Schedule.deserialize: not a serialized schedule (v 1 with npcs)")
	end
	local npcs: { [string]: any } = {}
	for i = 1, #tbl.npcs do
		local row: any = tbl.npcs[i]
		if typeof(row) ~= "table" or not nonEmpty(row.id) then
			error("Schedule.deserialize: npc " .. i .. ": id must be a non-empty string")
		end
		if npcs[row.id] then
			error("Schedule.deserialize: npc " .. row.id .. ": duplicate id")
		end
		local npc: { [string]: any } = { slots = row.slots }
		if row.byDay ~= nil then
			if typeof(row.byDay) ~= "table" then
				error("Schedule.deserialize: npc " .. row.id .. ": byDay must be an array of { key, slots }")
			end
			local byDay: { [any]: any } = {}
			for j = 1, #row.byDay do
				local ov: any = row.byDay[j]
				if typeof(ov) ~= "table" or ov.key == nil then
					error("Schedule.deserialize: npc " .. row.id .. ": byDay " .. j .. " must be { key, slots }")
				end
				if byDay[ov.key] ~= nil then
					error("Schedule.deserialize: npc " .. row.id .. ": byDay key " .. tostring(ov.key) .. " given twice")
				end
				byDay[ov.key] = { slots = ov.slots }
			end
			npc.byDay = byDay
		end
		npcs[row.id] = npc
	end
	return Schedule.DEFINE(npcs, tbl.town)
end

-- The sorted list of every place id any slot names (for a world check that each place exists).
function Schedule.places(def: Def): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local function take(slots: { Slot })
		for _, s in slots do
			if not seen[s.place] then
				seen[s.place] = true
				table.insert(out, s.place)
			end
		end
	end
	for _, id in def.order do
		local npc = def.npcs[id]
		take(npc.slots)
		if npc.byDay then
			for _, ov in npc.byDay do
				take(ov.slots)
			end
		end
	end
	table.sort(out)
	return out
end

return Schedule
