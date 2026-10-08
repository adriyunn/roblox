--!strict
-- catchlog_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves CatchLog: first-catch flags, length and weight records tracked independently, zones and the
-- preserved first, summary order, a serialize round trip through real JSON, merge (counts add, earlier
-- first, larger bests, commutative, inputs untouched), and deserialize refusing a tampered save
-- (negative controls: a negative count, a zero length, zones that do not add up).
-- Run from this folder: luau catchlog_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("catchlog_test")
local CatchLog = require("../src/Fishing/Shared/CatchLog")

type Catch = CatchLog.Catch

local function catch(speciesId: string, lengthM: number, weightKg: number, zoneId: string, dayN: number, timeOfDay: number, lureId: string): Catch
	return { speciesId = speciesId, lengthM = lengthM, weightKg = weightKg, zoneId = zoneId, dayN = dayN, timeOfDay = timeOfDay, lureId = lureId }
end

local function wire(log: CatchLog.Log): string
	return Stub.jsonEncode(CatchLog.serialize(log))
end

-- an empty log
local log = CatchLog.new()
local sum = CatchLog.summary(log)
T.check(sum.speciesCount == 0 and sum.totalCount == 0 and #sum.species == 0, "a new log is empty")
T.check(not CatchLog.has(log, "trout"), "has() is false before any catch")

-- first catch
local r1 = CatchLog.record(log, catch("trout", 0.40, 0.704, "shore", 1, 9.5, "worm"))
T.check(r1.isFirst, "first trout: isFirst")
T.check(r1.isLengthRecord, "first trout: isLengthRecord")
T.check(r1.isWeightRecord, "first trout: isWeightRecord")
T.eq(r1.countNow, 1, "first trout: countNow 1")
T.check(CatchLog.has(log, "trout"), "has() is true after the catch")

-- second, smaller catch
local r2 = CatchLog.record(log, catch("trout", 0.35, 0.47, "shore", 1, 10, "worm"))
T.check(not r2.isFirst, "second trout is not a first")
T.check(not r2.isLengthRecord and not r2.isWeightRecord, "a smaller trout sets no record")
T.eq(r2.countNow, 2, "second trout: countNow 2")

-- records are independent
local r3 = CatchLog.record(log, catch("trout", 0.45, 0.60, "reeds", 1, 11, "spinner"))
T.check(r3.isLengthRecord and not r3.isWeightRecord, "longer but lighter: length record only")
local r4 = CatchLog.record(log, catch("trout", 0.38, 0.90, "shore", 2, 7, "fly"))
T.check(not r4.isLengthRecord and r4.isWeightRecord, "shorter but heavier: weight record only")
local r5 = CatchLog.record(log, catch("trout", 0.45, 0.50, "shore", 2, 8, "fly"))
T.check(not r5.isLengthRecord, "an equal length is not a new record")
local rec = CatchLog.get(log, "trout") :: CatchLog.Record
T.check(rec.count == 5 and rec.bestLengthM == 0.45 and rec.bestWeightKg == 0.90, "trout record: 5 caught, best 0.45 m / 0.90 kg")
T.check(rec.bestLengthCatch.lureId == "spinner" and rec.bestLengthCatch.zoneId == "reeds", "bestLengthCatch is the full spinner catch from the reeds")
T.check(rec.first.dayN == 1 and rec.first.timeOfDay == 9.5 and rec.first.zoneId == "shore" and rec.first.lengthM == 0.40, "first stays the day-1 shore catch")
T.check(rec.zones.shore == 4 and rec.zones.reeds == 1, "zones count 4 shore, 1 reeds")

-- the caller's table is copied in
local mine = catch("perch", 0.20, 0.12, "pier", 2, 12, "jig")
CatchLog.record(log, mine)
mine.lengthM = 9
T.eq((CatchLog.get(log, "perch") :: CatchLog.Record).bestLengthM, 0.20, "record copies the catch (later mutation does not reach the log)")

-- summary order
sum = CatchLog.summary(log)
T.check(sum.speciesCount == 2 and sum.totalCount == 6, "summary: 2 species, 6 catches")
T.check(sum.species[1].speciesId == "trout" and sum.species[2].speciesId == "perch", "summary lists species in first-catch order")
T.check(sum.species[1].count == 5 and sum.species[1].bestLengthM == 0.45, "summary row carries count and best")
local other = CatchLog.new()
CatchLog.record(other, catch("perch", 0.20, 0.12, "pier", 1, 6, "jig"))
CatchLog.record(other, catch("trout", 0.30, 0.30, "pier", 1, 7, "worm"))
T.eq(CatchLog.summary(other).species[1].speciesId, "perch", "a log that saw perch first lists perch first")

-- record rejects a bad catch
T.throws(function() CatchLog.record(log, catch("trout", 0, 0.5, "shore", 1, 9, "worm")) end, "lengthM", "record refuses lengthM 0")
T.throws(function() CatchLog.record(log, { lengthM = 0.4, weightKg = 0.5, zoneId = "shore", dayN = 1, timeOfDay = 9, lureId = "worm" } :: any) end, "speciesId", "record refuses a missing speciesId")
T.throws(function() CatchLog.record(log, catch("trout", 0.4, 0.5, "shore", 1, 25, "worm")) end, "timeOfDay", "record refuses 25:00")
T.throws(function() CatchLog.record(log, catch("trout", 0.4, 0.5, "shore", 1.5, 9, "worm")) end, "dayN", "record refuses a fractional day")
T.eq(log.totalCount, 6, "rejected catches change nothing")

-- round trip through real JSON
local w = wire(log)
local back = CatchLog.deserialize(Stub.jsonDecode(w))
T.eq(wire(back), w, "deserialize(serialize()) serializes identically")
local backSum = CatchLog.summary(back)
T.check(backSum.speciesCount == 2 and backSum.totalCount == 6 and backSum.species[2].speciesId == "perch", "the rebuilt log has the same summary and order")
T.check((CatchLog.get(back, "trout") :: CatchLog.Record).bestLengthCatch.lureId == "spinner", "the rebuilt log keeps the full best catch")
T.eq(CatchLog.record(back, catch("trout", 0.41, 0.70, "shore", 3, 9, "worm")).countNow, 6, "recording continues on the rebuilt log")

-- merge
local a = CatchLog.new()
CatchLog.record(a, catch("trout", 0.40, 0.70, "shore", 1, 9, "worm"))
CatchLog.record(a, catch("trout", 0.42, 0.75, "shore", 1, 10, "worm"))
CatchLog.record(a, catch("perch", 0.20, 0.12, "pier", 3, 8, "jig"))
local b = CatchLog.new()
CatchLog.record(b, catch("trout", 0.50, 1.20, "reeds", 2, 6, "fly"))
CatchLog.record(b, catch("pike", 0.80, 3.5, "deep", 2, 7, "spoon"))
local aBefore, bBefore = wire(a), wire(b)
local m = CatchLog.merge(a, b)
local mt = CatchLog.get(m, "trout") :: CatchLog.Record
T.eq(mt.count, 3, "merge adds counts")
T.check(mt.first.dayN == 1 and mt.first.timeOfDay == 9, "merge keeps the earlier first")
T.check(mt.bestLengthM == 0.50 and mt.bestWeightKg == 1.20 and mt.bestLengthCatch.lureId == "fly", "merge keeps the larger bests with their catch")
T.check(mt.zones.shore == 2 and mt.zones.reeds == 1, "merge adds zones")
T.eq(m.totalCount, 5, "merge total is 5")
local mergedOrder: { string } = {}
for _, row in CatchLog.summary(m).species do
	table.insert(mergedOrder, row.speciesId)
end
T.eq(table.concat(mergedOrder, ","), "trout,pike,perch", "merged order is by first catch: trout (day 1), pike (day 2), perch (day 3)")
T.eq(wire(CatchLog.merge(a, b)), wire(CatchLog.merge(b, a)), "merge(a, b) serializes equal to merge(b, a)")
T.check(wire(a) == aBefore and wire(b) == bBefore, "merge leaves both inputs untouched")
T.eq(wire(CatchLog.merge(a, CatchLog.new())), wire(a), "merging with an empty log is the identity")
T.eq(wire(CatchLog.deserialize(Stub.jsonDecode(wire(m)))), wire(m), "a merged log round-trips")

-- negative controls: tampered saves are refused
local tampered = Stub.jsonDecode(w)
tampered.species[1].count = -1
T.throws(function() CatchLog.deserialize(tampered) end, "count", "negative control: a negative count is refused")
tampered = Stub.jsonDecode(w)
tampered.species[1].first.lengthM = 0
T.throws(function() CatchLog.deserialize(tampered) end, "lengthM", "a zero first length is refused")
tampered = Stub.jsonDecode(w)
tampered.species[2].bestLengthM = -0.2
T.throws(function() CatchLog.deserialize(tampered) end, "bestLengthM", "a negative best length is refused")
tampered = Stub.jsonDecode(w)
tampered.species[1].zones.shore = 1
T.throws(function() CatchLog.deserialize(tampered) end, "zones do not add up", "zones that do not add up to count are refused")
tampered = Stub.jsonDecode(w)
tampered.species[1].bestLengthCatch.speciesId = "perch"
T.throws(function() CatchLog.deserialize(tampered) end, "another species", "a best catch of another species is refused")
tampered = Stub.jsonDecode(w)
tampered.species[2].id = "trout"
T.throws(function() CatchLog.deserialize(tampered) end, "duplicate id", "a duplicate species id is refused")
T.throws(function() CatchLog.deserialize(42) end, "not a serialized log", "a non-table is refused")

-- M1-M5 (mutation checker, tools/mutate.py): the 0..24 edges, count 0, and the best-length tie-break order
-- Known equivalent mutant: firstLess's last `a.lengthM < b.lengthM` -> `<=` only differs for two identical firsts.
T.eq(CatchLog.record(CatchLog.new(), catch("trout", 0.4, 0.5, "shore", 0, 0, "worm")).countNow, 1, "M1: day 0 at 00:00 is a valid catch")
tampered = Stub.jsonDecode(w)
tampered.species[1].count = 0
tampered.species[1].zones = {}
T.throws(function() CatchLog.deserialize(tampered) end, "integer >= 1", "M2: count 0 with no zones is refused on the count itself")
tampered = Stub.jsonDecode(w)
tampered.species[1].first.timeOfDay = 24.5
T.throws(function() CatchLog.deserialize(tampered) end, "first must have", "M3: a first at 24.5 h is refused")
local tieA, tieB = CatchLog.new(), CatchLog.new()
CatchLog.record(tieA, catch("trout", 0.50, 1.0, "reeds", 3, 6, "worm"))
CatchLog.record(tieB, catch("trout", 0.50, 1.1, "shore", 2, 7, "fly"))
local tieBest = (CatchLog.get(CatchLog.merge(tieA, tieB), "trout") :: CatchLog.Record).bestLengthCatch
T.check(tieBest.dayN == 2 and tieBest.zoneId == "shore", "M4: an exact best-length tie goes to the earlier day (day 2 at 07:00 beats day 3 at 06:00)")
local tieC, tieD = CatchLog.new(), CatchLog.new()
CatchLog.record(tieC, catch("trout", 0.50, 1.0, "reeds", 2, 7, "worm"))
CatchLog.record(tieD, catch("trout", 0.50, 1.1, "shore", 2, 7, "fly"))
local tieBest2 = (CatchLog.get(CatchLog.merge(tieD, tieC), "trout") :: CatchLog.Record).bestLengthCatch
T.check(tieBest2.zoneId == "reeds" and tieBest2.lureId == "worm", "M5: a tie on day and time goes to the lower zone id (reeds before shore, whatever the lure)")

T.finish()
