--!strict
-- encounterreplay_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves src/Fishing/Shared/EncounterReplay.lua: a Recorder on the fake clock gives relative times and
-- copies payloads, the tape round-trips through JSON, a Player delivers "in" entries in time order and
-- never early, expectOut matches and records diffs naming channel and t, the ring limit drops the
-- oldest and counts, deepEqual on nested tables and arrays vs maps, and the negative control
-- (deserialize of a v = 2 tape errors).
-- Run from this folder: luau encounterreplay_test.luau

local Stub = require("./RobloxStub")
local EncounterReplay = require("../src/Fishing/Shared/EncounterReplay")
local R = Stub.new()
local T = Stub.harness("encounterreplay_test")

local Recorder, Player = EncounterReplay.Recorder, EncounterReplay.Player
local clock = function()
	return R.clock.now
end

-- ---------------------------------------------------------------- recording
R.advance(10)
local rec = Recorder.new(clock)
local castPayload = { power = 0.8, aim = { 1, 2, 3 } }
rec:tap("in", "Cast", castPayload)
R.advance(0.5)
rec:tap("out", "Cue/Notice", { fishId = 3 })
R.advance(0.5)
rec:tap("in", "Press", { t = 11 })
R.advance(0.2)
rec:tap("out", "Cue/Verdict", { verdict = "Good", fishId = 3 })
R.advance(0.8)
rec:tap("in", "Reel", { on = true })
castPayload.power = 0.1
T.eq(rec:count(), 5, "five entries recorded")
local tape = rec:stop()
T.eq(tape.v, 1, "tape version is 1")
T.eq(tape.t0, 10, "t0 is the clock at Recorder.new")
T.eq(#tape.entries, 5, "the tape holds 3 in + 2 out entries")
T.eq(tape.entries[1].t, 0, "first entry at relative t = 0")
T.eq(tape.entries[2].t, 0.5, "second entry at relative t = 0.5")
T.eq(tape.entries[5].t, 2, "last entry at relative t = 2.0")
T.check(tape.entries[1].dir == "in" and tape.entries[2].dir == "out", "dir is kept per entry")
T.eq(tape.entries[4].channel, "Cue/Verdict", "channel is kept per entry")
T.eq(tape.entries[1].payload.power, 0.8, "the payload is copied at tap time (later mutation does not leak)")
T.eq(tape.dropped, 0, "nothing dropped under the ring limit")
T.throws(function()
	rec:tap("in", "Late", {})
end, "stopped", "tap after stop errors")
T.throws(function()
	Recorder.new(clock):tap("sideways", "x", {})
end, "dir must be", "tap with a bad dir errors")

-- ---------------------------------------------------------------- serialize round trip
local wire = R.HttpService:JSONEncode(EncounterReplay.serialize(tape))
local back = EncounterReplay.deserialize(R.HttpService:JSONDecode(wire))
T.check(EncounterReplay.deepEqual(back, tape), "serialize -> JSON -> deserialize equals the original tape")
T.eq(back.entries[4].payload.verdict, "Good", "round-tripped payload field")
T.eq(#back.entries[1].payload.aim, 3, "round-tripped array payload keeps its length")
T.check(back.entries ~= tape.entries, "deserialize returns fresh tables")

-- ---------------------------------------------------------------- replay
local got = {}
local player = Player.new(back, function(channel, payload)
	table.insert(got, channel .. "@" .. tostring(payload.power or payload.t or payload.on))
end)
T.eq(player:step(0.4), 1, "step(0.4) delivers only the entry at t = 0")
T.eq(#got, 1, "the sink saw one message")
T.eq(got[1], "Cast@0.8", "the sink got the Cast payload")
T.eq(player:step(0.9), 0, "step(0.9) delivers nothing (Press is at 1.0, not early)")
T.eq(player:step(1.0), 1, "step(1.0) delivers Press exactly at its time")
T.eq(player:step(5), 1, "step(5) delivers the remaining Reel")
T.eq(table.concat(got, " "), "Cast@0.8 Press@11 Reel@true", "in entries arrive in time order")
T.eq(player:step(10), 0, "nothing left to deliver")
T.check(player:done(), "done() once every in entry is delivered")
T.eq(player:now(), 10, "now() is the largest time stepped to")

-- out checks: first matches, second mismatches
T.check(player:expectOut("Cue/Notice", { fishId = 3 }), "expectOut matches the first recorded out entry")
T.check(not player:expectOut("Cue/Verdict", { verdict = "Late", fishId = 3 }), "expectOut mismatches on a different payload")
T.check(not player:expectOut("Cue/Extra", { x = 1 }), "expectOut past the end of the recorded outs mismatches")
local rep = player:report()
T.eq(rep.delivered, 3, "report.delivered == 3")
T.eq(rep.outMatched, 1, "report.outMatched == 1")
T.eq(rep.outMismatched, 2, "report.outMismatched == 2")
T.eq(#rep.mismatches, 2, "report lists both mismatches")
T.eq(rep.mismatches[1].channel, "Cue/Verdict", "the diff names the recorded channel")
T.eq(rep.mismatches[1].t, 1.2, "the diff names the recorded t")
T.eq(rep.mismatches[1].expected.verdict, "Good", "the diff carries the expected payload")
T.eq(rep.mismatches[1].got.verdict, "Late", "the diff carries the payload that was sent")
T.eq(rep.mismatches[2].expected, nil, "a surplus out has no expected payload")
T.eq(rep.mismatches[2].gotChannel, "Cue/Extra", "a surplus out names the channel that was sent")
T.eq(rep.outPending, 0, "no recorded out entries are pending")

-- a fresh player with a mismatching channel on the first out
local p2 = Player.new(back, function() end)
p2:step(0.5)
T.check(not p2:expectOut("Cue/Nip", { fishId = 3 }), "a different channel with the same payload mismatches")
T.eq(p2:report().mismatches[1].gotChannel, "Cue/Nip", "the diff keeps the channel that was sent")
T.eq(p2:pendingOut(), 0, "the first out was consumed by the mismatch")
local p3 = Player.new(back, function() end)
p3:step(2)
T.eq(p3:pendingOut(), 2, "pendingOut counts recorded outs at or before now that were never expected")
T.eq(p3:report().outPending, 2, "report carries outPending")

-- ---------------------------------------------------------------- ring limit
local ring = Recorder.new(clock, 3)
for i = 1, 5 do
	R.advance(1)
	ring:tap("in", "n" .. i, { i = i })
end
T.eq(ring:count(), 3, "ring keeps at most maxEntries")
T.eq(ring.dropped, 2, "ring counts the two dropped entries")
local rt = ring:stop()
T.eq(#rt.entries, 3, "ring tape has 3 entries")
T.eq(rt.entries[1].channel .. rt.entries[2].channel .. rt.entries[3].channel, "n3n4n5", "the oldest two were dropped, order kept")
T.eq(rt.dropped, 2, "the tape records dropped")
T.check(rt.entries[1].t < rt.entries[3].t, "ring entries stay in time order")
T.throws(function()
	Recorder.new(clock, 0)
end, "positive integer", "maxEntries 0 is refused")

-- ---------------------------------------------------------------- deepEqual
local dE = EncounterReplay.deepEqual
T.check(dE({ a = { b = { 1, 2, { c = "x" } } } }, { a = { b = { 1, 2, { c = "x" } } } }), "deepEqual: nested tables equal")
T.check(not dE({ a = { b = { 1, 2, { c = "x" } } } }, { a = { b = { 1, 2, { c = "y" } } } }), "deepEqual: a differing leaf")
T.check(not dE({ 1, 2 }, { a = 1, b = 2 }), "deepEqual: array vs map")
T.check(not dE({ 1, 2 }, { 1, 2, 3 }), "deepEqual: shorter array vs longer")
T.check(not dE({ 1, 2, 3 }, { 1, 2 }), "deepEqual: longer array vs shorter")
T.check(dE({}, {}), "deepEqual: two empty tables")
T.check(not dE(1, "1"), "deepEqual: number vs string")
T.check(dE(nil, nil) and not dE(nil, {}), "deepEqual: nil vs nil, nil vs table")
local copy = EncounterReplay.deepCopy({ a = { 1 } })
T.check(copy.a[1] == 1 and dE(copy, { a = { 1 } }), "deepCopy copies nested values")

-- ---------------------------------------------------------------- negative controls
T.throws(function()
	EncounterReplay.deserialize({ v = 2, t0 = 0, entries = {} })
end, "unsupported tape version 2", "negative control: deserialize of a tape with v = 2 errors")
T.throws(function()
	EncounterReplay.deserialize({ v = 1, t0 = 0, entries = { { t = 0, dir = "up", channel = "x" } } })
end, "bad dir", "deserialize refuses a bad dir")
T.throws(function()
	EncounterReplay.deserialize({ v = 1, t0 = 0, entries = { { t = 1, dir = "in", channel = "x" }, { t = 0, dir = "in", channel = "y" } } })
end, "out of time order", "deserialize refuses entries out of time order")

T.finish()
