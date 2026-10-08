--!strict
-- schedule_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves Schedule: slot lookup at hour boundaries, conditional slots (weather, flags), byDay
-- overrides (exact day > storm > even/odd > base), next-change timing in real seconds, the day plan,
-- the town toggles by day and flags, a serialize round trip through real JSON that re-validates, and
-- DEFINE refusing gaps, overlaps, all-conditional lists and same-slot town conflicts (negative
-- controls). Every name here is a placeholder id. Run from this folder: luau schedule_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("schedule_test")
local Schedule = require("../src/Fishing/Shared/Schedule")

local function slot(fromH: number, toH: number, place: string, activity: string, lineSet: string?, conditions: any?): Schedule.Slot
	return { fromH = fromH, toH = toH, place = place, activity = activity, lineSet = lineSet, conditions = conditions }
end

local function allDay(place: string, activity: string, lineSet: string?): { Schedule.Slot }
	return { slot(0, 24, place, activity, lineSet) }
end

local function npcs(): { [string]: any }
	return {
		npc_a = {
			slots = {
				slot(0, 6, "home", "sleeping"),
				slot(6, 12, "dock", "fishing", "greet_a"),
				slot(12, 13, "stall", "selling", "greet_b"),
				slot(13, 20, "dock", "fishing", "greet_a"),
				slot(20, 24, "home", "sleeping"),
				slot(6, 20, "home", "sheltering", "rain_a", { weather = "rain" }),
			},
		},
		npc_b = {
			slots = {
				slot(0, 8, "home", "sleeping"),
				slot(8, 18, "stall", "selling", "greet_c"),
				slot(18, 24, "home", "resting"),
				slot(12, 14, "sign", "reading", "clue_c", { flags = { foundClue_01 = true } }),
			},
			byDay = {
				[3] = { slots = allDay("square", "festival", "fest_c") },
				even = { slots = { slot(0, 10, "home", "sleeping"), slot(10, 24, "pier", "fishing", "greet_c") } },
				storm = { slots = allDay("home", "sheltering", "rain_c") },
			},
		},
		npc_c = { slots = { slot(0, 12, "dock", "fishing"), slot(12, 24, "dock", "fishing") } },
	}
end

local function town(): any
	return {
		changes = {
			{ id = "stall_b_closed_sign", slot = "stall_b", toDay = 2 },
			{ id = "stall_b_open", slot = "stall_b", fromDay = 3 },
			{ id = "sign_default", slot = "sign", notFlags = { "foundClue_01" } },
			{ id = "sign_changed", slot = "sign", flags = { "foundClue_01" } },
			{ id = "festival_lanterns", days = "even", fromDay = 2 },
		},
	}
end

local def = Schedule.DEFINE(npcs(), town())
T.eq(table.concat(def.order, ","), "npc_a,npc_b,npc_c", "DEFINE lists npc ids sorted")

-- at(): boundaries and the base slots
local function at(id: string, h: number, d: number?, ctx: any?): Schedule.At
	local r, why = Schedule.at(def, id, h, d or 1, ctx)
	assert(r, why)
	return r
end
local a0 = at("npc_a", 0)
T.check(a0.place == "home" and a0.activity == "sleeping" and a0.slotIndex == 1 and a0.lineSet == nil, "npc_a 00:00 is home sleeping, slot 1, no line set")
local a6 = at("npc_a", 6)
T.check(a6.place == "dock" and a6.lineSet == "greet_a" and a6.slotIndex == 2, "06:00 is the dock (fromH inclusive)")
T.eq(at("npc_a", 5.999).place, "home", "05:59.9 is still home (toH exclusive)")
local a12 = at("npc_a", 12)
T.check(a12.place == "stall" and a12.activity == "selling" and a12.lineSet == "greet_b", "12:00 is the stall selling with greet_b")
T.eq(at("npc_a", 23.5).slotIndex, 5, "23:30 is the last slot")
T.eq(at("npc_a", 24).slotIndex, 1, "24:00 wraps to the first slot")
local r, why = Schedule.at(def, "npc_zz", 9, 1)
T.check(r == nil and why ~= nil and why:find("unknown npc", 1, true) ~= nil, "an unknown npc gives nil, reason")
r, why = Schedule.at(def, "npc_a", 25, 1)
T.check(r == nil and why ~= nil and why:find("timeH", 1, true) ~= nil, "25:00 gives nil, reason")
r, why = Schedule.at(def, "npc_a", 9, 0)
T.check(r == nil and why ~= nil and why:find("dayN", 1, true) ~= nil, "day 0 gives nil, reason")

-- conditional slots
local rain = at("npc_a", 9, 1, { weather = "rain" })
T.check(rain.place == "home" and rain.activity == "sheltering" and rain.lineSet == "rain_a" and rain.slotIndex == 6, "in rain the conditional slot wins at 09:00")
T.eq(at("npc_a", 9, 1, { weather = "clear" }).place, "dock", "in clear weather the base slot holds")
T.eq(at("npc_a", 21, 1, { weather = "rain" }).slotIndex, 5, "rain outside the conditional slot's hours changes nothing")
local flagged = at("npc_b", 13, 1, { flags = { foundClue_01 = true } })
T.check(flagged.place == "sign" and flagged.lineSet == "clue_c", "a flag condition switches npc_b to the sign at 13:00")
T.eq(at("npc_b", 13, 1, {}).place, "stall", "without the flag npc_b sells at the stall")
T.eq(at("npc_b", 13, 1, { flags = { foundClue_01 = false } }).place, "stall", "a false flag does not satisfy the condition")

-- byDay precedence: exact day > storm > even/odd > base
T.eq(at("npc_b", 13, 3).place, "square", "day 3 uses the exact-day override")
T.eq(at("npc_b", 13, 2).place, "pier", "day 2 uses the even override")
T.eq(at("npc_b", 13, 1).place, "stall", "day 1 (odd, no override) uses the base list")
T.eq(at("npc_b", 13, 1, { weather = "rain" }).lineSet, "rain_c", "a rainy day 1 uses the storm override")
T.eq(at("npc_b", 13, 2, { weather = "rain" }).lineSet, "rain_c", "storm beats the even override")
T.eq(at("npc_b", 13, 3, { weather = "rain" }).place, "square", "the exact day beats storm")

-- everyone()
local all = Schedule.everyone(def, 13, 1, {})
T.check(all.npc_a.place == "dock" and all.npc_b.place == "stall" and all.npc_c.place == "dock", "everyone() gives every npc's place")
local all2 = Schedule.everyone(def, 13, 1, {})
T.check(all2.npc_a.slotIndex == all.npc_a.slotIndex and all2.npc_b.lineSet == all.npc_b.lineSet, "everyone() is deterministic")

-- next(): seconds to the next visible change at 1440 s per day (60 s per hour)
local function nextS(id: string, h: number, d: number?, ctx: any?): number?
	local s = Schedule.next(def, id, h, 1440, d, ctx)
	return s
end
T.eq(nextS("npc_a", 5), 60, "npc_a at 05:00 changes in 1 h = 60 s")
T.eq(nextS("npc_a", 6), 360, "at 06:00 the next change is 12:00, 360 s")
T.eq(nextS("npc_a", 23), 420, "at 23:00 the next change is 06:00 next day, 420 s")
T.eq(nextS("npc_a", 9, 1, { weather = "rain" }), 660, "in rain (held fixed) the shelter lasts until 20:00, 660 s")
T.eq(nextS("npc_b", 23, 2), 60, "a byDay change at midnight counts: day 2 pier -> day 3 square in 60 s")
local none, noneWhy = Schedule.next(def, "npc_c", 9, 1440)
T.check(none == nil and noneWhy ~= nil and noneWhy:find("no change", 1, true) ~= nil, "an npc that never moves gives nil, no change")
local bad, badWhy = Schedule.next(def, "npc_a", 9, 0)
T.check(bad == nil and badWhy ~= nil and badWhy:find("dayLengthS", 1, true) ~= nil, "dayLengthS 0 gives nil, reason")

-- plan(): the resolved day
local plan = Schedule.plan(def, "npc_a", 1, {}) :: { Schedule.PlanRow }
local rows: { string } = {}
for _, p in plan do
	table.insert(rows, string.format("%g-%g %s", p.fromH, p.toH, p.place))
end
T.eq(table.concat(rows, ","), "0-6 home,6-12 dock,12-13 stall,13-20 dock,20-24 home", "plan lists the five stops of a clear day")
local rainPlan = Schedule.plan(def, "npc_a", 1, { weather = "rain" }) :: { Schedule.PlanRow }
T.check(#rainPlan == 3 and rainPlan[2].fromH == 6 and rainPlan[2].toH == 20 and rainPlan[2].activity == "sheltering", "a rainy plan merges the shelter into one 06-20 row")
local noPlan, noPlanWhy = Schedule.plan(def, "npc_zz")
T.check(noPlan == nil and noPlanWhy ~= nil, "plan of an unknown npc gives nil, reason")
T.eq(table.concat(Schedule.places(def), ","), "dock,home,pier,sign,square,stall", "places() lists every place sorted, overrides included")

-- townState()
local t1 = Schedule.townState(def, 1)
T.eq(table.concat(t1.changes, ","), "stall_b_closed_sign,sign_default", "day 1 with no flags: the closed sign and the default sign")
T.check(t1.slots.stall_b == "stall_b_closed_sign" and t1.slots.sign == "sign_default", "slots name which toggle holds each prop slot")
local t3 = Schedule.townState(def, 3)
T.check(t3.slots.stall_b == "stall_b_open" and table.find(t3.changes, "stall_b_closed_sign") == nil, "day 3: the stall opens and the closed sign is gone")
T.check(table.find(Schedule.townState(def, 2).changes, "festival_lanterns") ~= nil and table.find(t3.changes, "festival_lanterns") == nil and table.find(Schedule.townState(def, 4).changes, "festival_lanterns") ~= nil, "even-day lanterns on days 2 and 4, not 3")
local tf = Schedule.townState(def, 1, { foundClue_01 = true })
T.check(tf.slots.sign == "sign_changed" and table.find(tf.changes, "sign_default") == nil, "with foundClue_01 the sign changes and the default sign is off")
T.throws(function() Schedule.townState(def, 0) end, "dayN", "townState refuses day 0")

-- DEFINE copies its input
local src = npcs()
local copied = Schedule.DEFINE(src)
src.npc_a.slots[2].place = "moon"
T.eq((Schedule.at(copied, "npc_a", 7, 1) :: Schedule.At).place, "dock", "DEFINE copies the slots (later mutation of the source does not reach the def)")

-- round trip through real JSON, re-validated by DEFINE
local wire = Stub.jsonEncode(Schedule.serialize(def))
local back = Schedule.deserialize(Stub.jsonDecode(wire))
T.eq(Stub.jsonEncode(Schedule.serialize(back)), wire, "deserialize(serialize()) serializes identically")
T.check((Schedule.at(back, "npc_b", 13, 3) :: Schedule.At).place == "square" and (Schedule.at(back, "npc_b", 13, 2, { weather = "rain" }) :: Schedule.At).lineSet == "rain_c", "the rebuilt def keeps numeric and string byDay keys")
T.eq(table.concat(Schedule.townState(back, 3).changes, ","), table.concat(t3.changes, ","), "the rebuilt def keeps the town toggles")
local tampered = Stub.jsonDecode(wire)
tampered.npcs[1].slots[2].toH = 11
T.throws(function() Schedule.deserialize(tampered) end, "npc_a: gap 11..12", "negative control: a tampered file with a gap is refused by name")
tampered = Stub.jsonDecode(wire)
tampered.npcs[2].byDay[1].key = "even"
T.throws(function() Schedule.deserialize(tampered) end, "given twice", "a byDay key given twice is refused")
T.throws(function() Schedule.deserialize({ v = 2 }) end, "not a serialized", "a wrong version is refused")

-- DEFINE refusals name the npc and the problem
local function defineWith(slots: { any }, byDay: any?)
	return function()
		Schedule.DEFINE({ npc_x = { slots = slots, byDay = byDay } })
	end
end
T.throws(defineWith({ slot(0, 8, "home", "sleeping"), slot(9, 24, "dock", "fishing") }), "npc_x: gap 8..9 before slot 2", "a gap is refused naming the npc and the hours")
T.throws(defineWith({ slot(0, 10, "home", "sleeping"), slot(9, 24, "dock", "fishing") }), "npc_x: overlap 9..10 at slot 2", "an overlap is refused naming the hours")
T.throws(defineWith({ slot(1, 24, "home", "sleeping") }), "gap 0..1", "a first slot after 00:00 is a gap")
T.throws(defineWith({ slot(0, 23, "home", "sleeping") }), "gap 23..24", "a last slot before 24:00 is a gap")
T.throws(defineWith({ slot(0, 24, "home", "sleeping", nil, { weather = "rain" }) }), "every slot is conditional", "an all-conditional list is refused")
T.throws(defineWith({ slot(0, 24, "", "sleeping") }), "place", "an empty place is refused")
T.throws(defineWith({ slot(0, 25, "home", "sleeping") }), "toH", "toH 25 is refused")
T.throws(defineWith({ slot(0, 24, "home", "sleeping", nil, { moon = true }) }), "unknown condition", "an unknown condition key is refused")
T.throws(defineWith(allDay("home", "sleeping"), { friday = { slots = allDay("dock", "fishing") } }), "byDay key", "a byDay key other than a day number, even, odd or storm is refused")
T.throws(defineWith(allDay("home", "sleeping"), { [2] = { slots = { slot(0, 12, "dock", "fishing") } } }), "byDay 2: gap 12..24", "a gap inside a byDay override is refused naming the day")
T.throws(function()
	Schedule.DEFINE({ npc_x = { slots = allDay("home", "sleeping") } }, { changes = { { id = "p1", slot = "s", fromDay = 1 }, { id = "p2", slot = "s", fromDay = 2 } } })
end, "can both hold slot s", "two town changes that can share a prop slot on one day are refused")
T.throws(function()
	Schedule.DEFINE({ npc_x = { slots = allDay("home", "sleeping") } }, { changes = { { id = "p1" }, { id = "p1" } } })
end, "duplicate id", "a duplicate town change id is refused")
T.throws(function()
	Schedule.DEFINE({ npc_x = { slots = allDay("home", "sleeping") } }, { changes = { { id = "p1", fromDay = 3, toDay = 2 } } })
end, "toDay", "toDay before fromDay is refused")

T.finish()
