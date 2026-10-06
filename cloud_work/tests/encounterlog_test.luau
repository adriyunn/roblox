--!strict
-- encounterlog_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves src/Fishing/Shared/EncounterLog.lua: derived numbers of a full encounter (times written out),
-- a Leave with no press, counts, summary (even-n median, nearest-rank p95), bands ok / out of band /
-- n < 5, CSV header and cells, toTable JSON round trip, and the negative control (event on an unknown
-- id errors). It also builds the 20-record parity sample and prints it between FIXTURE markers:
-- tools/parity_report_test.py harvests those lines into tests/fixtures/encounters_sample.{csv,json}
-- (the Luau CLI has no file I/O), so the Luau writer and the Python reader are proven on the same bytes.
-- Run from this folder: luau encounterlog_test.luau

local Stub = require("./RobloxStub")
local EncounterLog = require("../src/Fishing/Shared/EncounterLog")
local R = Stub.new()
local T = Stub.harness("encounterlog_test")

local HEADER = "id,anglerId,fishId,speciesId,hookMode,outcome,tNotice,tEnd,noticeToFirstNip,hoverS,pressOffset,verdict,fightS,jumps,spooks"

-- ---------------------------------------------------------------- a full encounter, times written out
local log = EncounterLog.new()
EncounterLog.start(log, "e1", { anglerId = 7, fishId = "fish-1", speciesId = "trout", hookMode = "bed", t = 100 })
EncounterLog.event(log, "e1", "Notice", 100)
EncounterLog.event(log, "e1", "Nip", 104.083)
EncounterLog.event(log, "e1", "Nip", 106)
EncounterLog.event(log, "e1", "Swallow", 112.5)
EncounterLog.event(log, "e1", "Press", 112.7)
EncounterLog.event(log, "e1", "Verdict", 112.7, { verdict = "Good" })
EncounterLog.event(log, "e1", "Hooked", 112.8)
EncounterLog.event(log, "e1", "Jump", 115)
EncounterLog.event(log, "e1", "Spook", 116, { reason = "Late" })
EncounterLog.event(log, "e1", "Jump", 120)
EncounterLog.event(log, "e1", "Caught", 140.3)
local r1 = EncounterLog.finish(log, "e1", 140.3, "Caught")
T.eq(r1.tNotice, 100, "tNotice comes from start()")
T.eq(r1.noticeToFirstNip, 4.083, "noticeToFirstNip = first Nip - Notice (104.083 - 100)")
T.eq(r1.hoverS, 12.5, "hoverS = Swallow - Notice (112.5 - 100)")
T.eq(r1.pressOffset, 0.2, "pressOffset = Press - Swallow (112.7 - 112.5)")
T.eq(r1.verdict, "Good", "verdict from the Verdict event data")
T.eq(r1.fightS, 27.5, "fightS = Caught - Hooked (140.3 - 112.8)")
T.eq(r1.jumps, 2, "two Jump events count 2")
T.eq(r1.spooks, 1, "one Spook event counts 1")
T.eq(r1.outcome, "Caught", "outcome is kept")
T.eq(r1.tEnd, 140.3, "tEnd is the finish time")
T.eq(#r1.events, 11, "the raw event list is kept")
T.eq(r1.events[2].name, "Nip", "events keep their order")
T.eq(r1.info.hookMode, "bed", "info is kept on the record")

-- ---------------------------------------------------------------- a Leave with no press
EncounterLog.start(log, "e2", { anglerId = 7, fishId = "fish-2", speciesId = "trout", hookMode = "mid", t = 200 })
EncounterLog.event(log, "e2", "Nip", 204.1)
EncounterLog.event(log, "e2", "Leave", 215)
local r2 = EncounterLog.finish(log, "e2", 215, "Leave")
T.eq(r2.hoverS, 15, "hoverS = Leave - Notice when the fish never swallows")
T.eq(r2.pressOffset, nil, "a Leave with no press has pressOffset == nil")
T.eq(r2.fightS, nil, "no Hooked -> fightS == nil")
T.eq(r2.verdict, nil, "no Verdict -> verdict == nil")
T.eq(r2.jumps, 0, "no jumps counts 0")
T.eq(#EncounterLog.records(log), 2, "records(log) holds both finished encounters")
T.eq(EncounterLog.records(log)[1].id, "e1", "records are in finish order")

-- ---------------------------------------------------------------- summary
local s2 = EncounterLog.summary(EncounterLog.records(log), "hoverS")
T.eq(s2.n, 2, "summary n over the two records")
T.eq(s2.median, 13.75, "summary median of even n = mean of the two middle values")
T.check(s2.min == 12.5 and s2.max == 15, "summary min/max")
T.eq(s2.mean, 13.75, "summary mean")
T.eq(EncounterLog.summary(EncounterLog.records(log), "fightS").n, 1, "summary skips records without the metric")
T.eq(EncounterLog.summary({}, "hoverS").n, 0, "summary of nothing has n = 0")

-- twenty synthetic bed records with hoverS = 1..20 (built in reverse so sorting matters)
local function synth(n: number, mode: string, hoverFn: (number) -> number): { any }
	local lg = EncounterLog.new()
	for i = n, 1, -1 do
		local id = string.format("s%d", i)
		EncounterLog.start(lg, id, { anglerId = 1, fishId = id, speciesId = "trout", hookMode = mode, t = 0 })
		EncounterLog.event(lg, id, "Swallow", hoverFn(i))
		EncounterLog.finish(lg, id, hoverFn(i) + 1, "Leave")
	end
	return EncounterLog.records(lg)
end
local twenty = synth(20, "bed", function(i)
	return i
end)
local s20 = EncounterLog.summary(twenty, "hoverS")
T.eq(s20.p95, 19, "p95 nearest rank on 20 values (ceil(0.95*20) = 19th) = 19")
T.eq(s20.median, 10.5, "median of 1..20 = 10.5")
T.check(s20.min == 1 and s20.max == 20, "min 1, max 20 after sorting")

-- ---------------------------------------------------------------- bands
local okBands = EncounterLog.bands(twenty, { bed = { hoverS = { 5, 45 } } })
T.eq(#okBands, 1, "bands: one row per (mode, metric)")
T.check(okBands[1].ok == true and okBands[1].reason == nil, "bands: median 10.5 inside 5..45 is ok")
T.check(okBands[1].metric == "hoverS" and okBands[1].hookMode == "bed" and okBands[1].n == 20, "bands: row names metric, hookMode, n")
local fifty = synth(20, "bed", function(i)
	return 39.5 + i
end)
local badBands = EncounterLog.bands(fifty, { bed = { hoverS = { 5, 45 } } })
T.check(badBands[1].ok == false and badBands[1].median == 50, "bands: median 50 s against 5..45 is not ok")
T.check(badBands[1].reason ~= nil and badBands[1].reason:find("outside", 1, true) ~= nil, "bands: the reason names the band")
local few = EncounterLog.bands(synth(3, "mid", function(i)
	return i
end), { mid = { hoverS = { 2, 20 } } })
T.check(few[1].ok == false and few[1].reason:find("n<5", 1, true) ~= nil, "bands: n < 5 fails with reason n<5")
local multi = EncounterLog.bands(twenty, { mid = { hoverS = { 2, 20 } }, bed = { hoverS = { 5, 45 }, fightS = { 5, 60 } } })
T.check(multi[1].hookMode == "bed" and multi[1].metric == "fightS" and multi[3].hookMode == "mid", "bands: rows sorted by hookMode then metric")
T.check(multi[3].ok == false and multi[3].n == 0, "bands: a mode with no records has n = 0 and fails")

-- ---------------------------------------------------------------- CSV
local csv = EncounterLog.toCsv(EncounterLog.records(log))
local lines = {}
for line in csv:gmatch("[^\n]+") do
	table.insert(lines, line)
end
T.eq(lines[1], HEADER, "CSV header is the fixed header")
T.eq(EncounterLog.CSV_HEADER, HEADER, "EncounterLog.CSV_HEADER matches the documented header")
T.eq(#lines, 3, "CSV has header + one line per record")
T.check(csv:sub(-1) == "\n" and csv:find("\r") == nil, "CSV ends with LF and has no CR")
local cells1 = string.split(lines[2], ",")
T.eq(cells1[10], "12.500", "CSV cell hoverS of e1 is 12.500 (3 decimals)")
T.eq(cells1[9], "4.083", "CSV cell noticeToFirstNip of e1 is 4.083")
T.eq(cells1[11], "0.200", "CSV cell pressOffset of e1 is 0.200")
T.eq(cells1[14], "2", "CSV cell jumps is an integer")
T.eq(cells1[2], "7", "CSV cell anglerId is printed as given (a number)")
local cells2 = string.split(lines[3], ",")
T.eq(cells2[11], "", "CSV cell pressOffset of the Leave row is empty (nil)")
T.eq(cells2[12], "", "CSV cell verdict of the Leave row is empty")
T.eq(#cells2, 15, "CSV row has 15 cells")
local quoted = EncounterLog.new()
EncounterLog.start(quoted, 'a,b "c"', { anglerId = "x", fishId = "y", speciesId = nil, hookMode = "lure", t = 0 })
local qcsv = EncounterLog.toCsv({ EncounterLog.finish(quoted, 'a,b "c"', 1, "Leave") })
T.check(qcsv:find('\n"a,b ""c""",x,y,,lure', 1, true) ~= nil, "CSV quotes a cell with a comma or quote and leaves nil speciesId empty")

-- ---------------------------------------------------------------- toTable round trip through JSON
local tbl = EncounterLog.toTable(EncounterLog.records(log))
T.eq(tbl.v, 1, "toTable has v = 1")
T.eq(#tbl.records, 2, "toTable has one row per record")
T.eq(table.concat(tbl.fields, ","), HEADER, "toTable.fields is the CSV header")
local back = R.HttpService:JSONDecode(R.HttpService:JSONEncode(tbl))
local same = true
for i, row in tbl.records do
	for _, f in tbl.fields do
		if back.records[i][f] ~= row[f] then
			same = false
		end
	end
end
T.check(same, "toTable round-trips through JSONEncode/JSONDecode equal field by field")
T.eq(back.records[1].hoverS, 12.5, "round-tripped hoverS")
T.eq(back.records[2].pressOffset, nil, "round-tripped nil stays nil (absent)")
T.eq(#back.records[1].events, 11, "events ride along in toTable")
T.eq(back.records[1].events[6].data.verdict, "Good", "event data rides along")

-- ---------------------------------------------------------------- negative controls
T.throws(function()
	EncounterLog.event(log, "nope", "Nip", 1)
end, "unknown encounter", "negative control: event on an unknown id errors")
T.throws(function()
	EncounterLog.finish(log, "nope", 1, "Leave")
end, "unknown encounter", "finish on an unknown id errors")
EncounterLog.start(log, "dup", { anglerId = 1, fishId = "f", hookMode = "bed", t = 0 })
T.throws(function()
	EncounterLog.start(log, "dup", { anglerId = 1, fishId = "f", hookMode = "bed", t = 0 })
end, "already started", "start on a duplicate id errors")
T.throws(function()
	EncounterLog.start(log, "badmode", { anglerId = 1, fishId = "f", hookMode = "surface", t = 0 })
end, "hookMode", "start with an unknown hookMode errors")
T.throws(function()
	EncounterLog.bands(twenty, { bed = { hoverS = { 45, 5 } } })
end, "band must be", "bands with lo > hi errors")

-- ---------------------------------------------------------------- the 20-record parity sample
-- 8 bed, 7 mid, 5 lure (three Leaves: enc-04, enc-08, enc-12); every number inside the default
-- parity_bands.json bands (noticeToFirstNip about F1's 4.083 s; bed hover 11..18 s, mid hover 6..12 s,
-- lure hover 4..8 s; fights 20.5..30 s).
local sample = EncounterLog.new()
for i = 1, 20 do
	local mode = if i <= 8 then "bed" elseif i <= 15 then "mid" else "lure"
	local id = string.format("enc-%02d", i)
	local t0 = i * 100
	local hover = if mode == "bed" then 10 + i elseif mode == "mid" then 5 + (i - 8) else 3 + (i - 15)
	EncounterLog.start(sample, id, { anglerId = 1000 + (i % 3), fishId = "fish-" .. i, speciesId = "trout", hookMode = mode, t = t0 })
	EncounterLog.event(sample, id, "Notice", t0)
	EncounterLog.event(sample, id, "Nip", t0 + 4.083 + ((i % 5) - 2) * 0.05)
	EncounterLog.event(sample, id, "Swallow", t0 + hover)
	if i % 4 == 0 and i <= 15 then
		EncounterLog.event(sample, id, "Leave", t0 + hover + 1)
		EncounterLog.finish(sample, id, t0 + hover + 1, "Leave")
	else
		EncounterLog.event(sample, id, "Press", t0 + hover + 0.2)
		EncounterLog.event(sample, id, "Verdict", t0 + hover + 0.2, { verdict = "Good" })
		EncounterLog.event(sample, id, "Hooked", t0 + hover + 0.3)
		for _ = 1, i % 3 do
			EncounterLog.event(sample, id, "Jump", t0 + hover + 5)
		end
		local fight = 20 + i * 0.5
		local outcome = if i % 7 == 0 then "Snap" else "Caught"
		EncounterLog.event(sample, id, outcome, t0 + hover + 0.3 + fight)
		EncounterLog.finish(sample, id, t0 + hover + 0.3 + fight, outcome)
	end
end
local sampleRecords = EncounterLog.records(sample)
T.eq(#sampleRecords, 20, "sample: 20 records")
local sampleBands = EncounterLog.bands(sampleRecords, {
	bed = { hoverS = { 5, 45 }, noticeToFirstNip = { 3.5, 4.5 }, fightS = { 5, 60 } },
	mid = { hoverS = { 2, 20 }, noticeToFirstNip = { 3.5, 4.5 }, fightS = { 5, 60 } },
	lure = { noticeToFirstNip = { 3.5, 4.5 }, fightS = { 5, 60 } },
})
local notOk = {}
for _, b in sampleBands do
	if not b.ok then
		table.insert(notOk, b.hookMode .. "." .. b.metric .. ": " .. tostring(b.reason))
	end
end
T.check(#notOk == 0, "sample: every default band is ok in Luau (the Python report must agree)" .. (if #notOk > 0 then " " .. table.concat(notOk, "; ") else ""))
T.eq(#sampleBands, 8, "sample: eight band rows (3 + 3 + 2)")
local sampleCsv = EncounterLog.toCsv(sampleRecords)
local n = 0
for _ in sampleCsv:gmatch("[^\n]+") do
	n += 1
end
T.eq(n, 21, "sample CSV: header + 20 rows")

print("-----BEGIN FIXTURE encounters_sample.csv-----")
print(sampleCsv:sub(1, -2))
print("-----END FIXTURE-----")
print("-----BEGIN FIXTURE encounters_sample.json-----")
print(R.HttpService:JSONEncode(EncounterLog.toTable(sampleRecords)))
print("-----END FIXTURE-----")

T.finish()
