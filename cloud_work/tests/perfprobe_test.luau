--!strict
-- perfprobe_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves src/Fishing/Shared/PerfProbe.lua with an injected clock: ms conversion, the 1..100 report
-- (median 50.5, p95 95), the ring keeping the last 3600 of 4000, a small ring, the budget rule (median
-- over, p95 over 2x, the boundaries), enabled off = no clock calls and report nil, unbalanced and nested
-- sections, interleaved labels, the profiler hooks, reset, toLine and toTable, and the negative control
-- (a wrong p95 index would read 94 or 96). No save form here.
-- Run from this folder: luau perfprobe_test.luau

local Stub = require("./RobloxStub")
local PerfProbe = require("../src/Fishing/Shared/PerfProbe")
local T = Stub.harness("perfprobe_test")

-- a fake seconds clock that counts its calls
local function fakeClock()
	local state = { now = 0, calls = 0 }
	local function clock(): number
		state.calls += 1
		return state.now
	end
	return clock, state
end

-- one section of `ms` milliseconds on a seconds clock
local function section(probe: PerfProbe.PerfProbe, state: { now: number, calls: number }, label: string, ms: number)
	probe:begin(label)
	state.now += ms / 1000
	probe:finish(label)
end

local function near(a: number?, b: number): boolean
	return a ~= nil and math.abs(a - b) < 1e-9
end

-- ---------------------------------------------------------------- construction and the off state
do
	local clock, state = fakeClock()
	T.throws(function() PerfProbe.new("tick" :: any) end, "clock", "new refuses a non-function clock")
	T.throws(function() PerfProbe.new(clock, { ringN = 0 }) end, "ringN", "new refuses ringN 0")
	T.throws(function() PerfProbe.new(clock, { budgets = { AF_FishStep = -1 } }) end, "budgets", "new refuses a negative budget")
	local probe = PerfProbe.new(clock)
	T.eq(probe.enabled, false, "enabled is false by default (on only by the Studio attribute)")
	T.eq(PerfProbe.DEFAULT_RING_N, 3600, "the default ring is 3600 samples (60 s at 60 Hz)")
	probe:begin("AF_FishStep")
	state.now += 0.001
	T.check(probe:finish("AF_FishStep") == nil, "off: finish returns nil")
	T.check(state.calls == 0, "off: begin and finish never call the clock (they cost one bool check)")
	T.check(probe:report("AF_FishStep") == nil, "off: report returns nil")
	T.check(probe:stats().begins == 0 and probe:stats().finishes == 0, "off: nothing is counted")
	T.eq(#probe:samples("AF_FishStep"), 0, "off: no sample was stored")
end

-- ---------------------------------------------------------------- one section, ms conversion
do
	local clock, state = fakeClock()
	local probe = PerfProbe.new(clock, { enabled = true })
	probe:begin("AF_FishStep")
	state.now += 0.002
	local ms = probe:finish("AF_FishStep")
	T.check(near(ms, 2), "a 0.002 s section is stored as 2 ms (msPerUnit 1000)")
	local r = probe:report("AF_FishStep")
	T.check(r ~= nil and r.n == 1 and near(r.min, 2) and near(r.median, 2) and near(r.p95, 2) and near(r.max, 2) and near(r.mean, 2), "report of one sample: every statistic is that sample")
	T.check(state.calls == 2, "on: begin and finish each read the clock once")
	local raw = PerfProbe.new(clock, { enabled = true, msPerUnit = 1 })
	section(raw, state, "x", 3000) -- the helper adds 3 clock units
	T.check(near((raw:report("x") :: PerfProbe.Report).median, 3), "msPerUnit 1: a clock already in ms stores the raw difference")
	T.check(probe:report("nothing") == nil and not probe:overBudget("nothing"), "an unknown label reports nil and is not over budget")
end

-- ---------------------------------------------------------------- 1..100 and the ring
do
	local clock, state = fakeClock()
	local probe = PerfProbe.new(clock, { enabled = true })
	for i = 1, 100 do
		section(probe, state, "seq", i)
	end
	local r = probe:report("seq") :: PerfProbe.Report
	T.eq(r.n, 100, "1..100: n = 100")
	T.check(near(r.median, 50.5), "1..100: median 50.5 (even n: the mean of the two middle values)")
	T.check(near(r.p95, 95), "1..100: p95 = 95 (nearest rank, ceil(0.95 x 100) = 95)")
	T.check(near(r.max, 100) and near(r.min, 1) and near(r.mean, 50.5), "1..100: max 100, min 1, mean 50.5")
	T.check(not near(r.p95, 96) and not near(r.p95, 94), "negative control: an off-by-one p95 index (94 or 96) would fail the row above")
	local s = probe:samples("seq")
	T.check(#s == 100 and near(s[1], 1) and near(s[100], 100), "samples come back oldest first")

	local ring = PerfProbe.new(clock, { enabled = true })
	for i = 1, 4000 do
		section(ring, state, "ring", i)
	end
	local rr = ring:report("ring") :: PerfProbe.Report
	T.check(rr.n == 3600 and near(rr.min, 401) and near(rr.max, 4000), "ring: 4000 samples keep the last 3600 (401..4000)")
	local rs = ring:samples("ring")
	T.check(near(rs[1], 401) and near(rs[3600], 4000), "ring: the oldest kept sample is 401, the newest 4000")

	local small = PerfProbe.new(clock, { enabled = true, ringN = 4 })
	for i = 1, 6 do
		section(small, state, "s", i)
	end
	local ss = small:samples("s")
	T.check(#ss == 4 and near(ss[1], 3) and near(ss[4], 6), "a ring of 4 keeps {3, 4, 5, 6} after six samples")
	local odd = PerfProbe.new(clock, { enabled = true })
	for _, v in { 5, 1, 3 } do
		section(odd, state, "o", v)
	end
	T.check(near((odd:report("o") :: PerfProbe.Report).median, 3), "an odd n takes the middle value after sorting")
end

-- ---------------------------------------------------------------- budgets
do
	local clock, state = fakeClock()
	local probe = PerfProbe.new(clock, { enabled = true, budgets = { AF_FishStep = 1.0, AF_FishPoolView = 0.5 } })
	for _ = 1, 20 do
		section(probe, state, "AF_FishStep", 0.5)
	end
	T.eq(probe:overBudget("AF_FishStep"), false, "budget: 20 x 0.5 ms against 1.0 ms is under")
	probe:reset("AF_FishStep")
	for _ = 1, 20 do
		section(probe, state, "AF_FishStep", 1.0)
	end
	T.eq(probe:overBudget("AF_FishStep"), false, "budget: a median exactly at the budget is not over (strict >)")
	probe:reset("AF_FishStep")
	for _ = 1, 20 do
		section(probe, state, "AF_FishStep", 1.2)
	end
	T.eq(probe:overBudget("AF_FishStep"), true, "budget: median 1.2 over 1.0 is over")
	probe:reset("AF_FishStep")
	for i = 1, 20 do
		section(probe, state, "AF_FishStep", if i <= 18 then 0.5 else 2.5) -- rank 19 of 20 is a 2.5
	end
	local r = probe:report("AF_FishStep") :: PerfProbe.Report
	T.check(near(r.median, 0.5) and near(r.p95, 2.5), "budget: median 0.5 but p95 2.5 ...")
	T.eq(probe:overBudget("AF_FishStep"), true, "budget: ... is over because p95 > 2 x 1.0")
	probe:reset("AF_FishStep")
	for i = 1, 20 do
		section(probe, state, "AF_FishStep", if i <= 18 then 0.5 else 2.0)
	end
	T.eq(probe:overBudget("AF_FishStep"), false, "budget: p95 exactly 2 x the budget is not over")
	section(probe, state, "AF_NetCues", 50)
	T.eq(probe:overBudget("AF_NetCues"), false, "budget: a label without a budget is never over")
	T.eq(probe:overBudget("AF_FishPoolView"), false, "budget: a budget without samples is not over")
end

-- ---------------------------------------------------------------- unbalanced, nested, interleaved, hooks
do
	local clock, state = fakeClock()
	local hooks = { begins = {} :: { string }, ends = 0 }
	local probe = PerfProbe.new(clock, {
		enabled = true,
		profileBegin = function(label: string)
			table.insert(hooks.begins, label)
		end,
		profileEnd = function()
			hooks.ends += 1
		end,
	})
	T.check(probe:finish("A") == nil and probe:stats().unbalanced == 1, "a finish without a begin is ignored and counted")
	T.eq(#probe:samples("A"), 0, "... and stores nothing")
	probe:begin("A")
	state.now += 1
	probe:begin("A") -- restarts the section
	state.now += 2
	local ms = probe:finish("A")
	T.check(near(ms, 2000) and probe:stats().dropped == 1, "a second begin restarts the section (2 s from the last start) and counts the dropped start")
	probe:begin("A")
	state.now += 0.001
	probe:begin("B")
	state.now += 0.002
	probe:finish("B")
	state.now += 0.003
	probe:finish("A")
	T.check(near(probe:samples("B")[1], 2) and near(probe:samples("A")[2], 6), "interleaved labels: B = 2 ms inside A = 6 ms")
	T.check(#hooks.begins == 4 and hooks.begins[1] == "A" and hooks.begins[3] == "A" and hooks.begins[4] == "B" and hooks.ends == 4, "profileBegin gets the label, profileEnd fires on every finish (the unbalanced one too)")
	T.check(probe:stats().begins == 4 and probe:stats().finishes == 3, "stats: 4 begins, 3 finishes")
	probe:setEnabled(false)
	T.check(probe:report("A") == nil and #probe:samples("A") == 2, "off again: report is nil but the samples are kept")
	probe:setEnabled(true)
	T.check((probe:report("A") :: PerfProbe.Report).n == 2, "on again: the report is back")
	T.check(table.concat(probe:labels(), ",") == "A,B", "labels are sorted")
	probe:reset()
	T.check(#probe:labels() == 0 and probe:report("A") == nil, "reset() drops every label")
end

-- ---------------------------------------------------------------- toLine and toTable
do
	local clock, state = fakeClock()
	local probe = PerfProbe.new(clock, { enabled = true, budgets = { AF_FishStep = 1.0, AF_PoolRefill = 0.2 } })
	for _, v in { 0.61, 0.2, 1.12 } do
		section(probe, state, "AF_FishStep", v)
	end
	T.eq(probe:toLine("AF_FishStep", "anglers=4 fish=16"), "PERF AF_FishStep anglers=4 fish=16 n=3 med=0.610ms p95=1.120ms max=1.120ms", "toLine is the note's one-line form")
	T.eq(probe:toLine("AF_PoolRefill"), "PERF AF_PoolRefill n=0", "toLine without samples says n=0")
	section(probe, state, "AF_NetCues", 0.05)
	for _ = 1, 5 do
		section(probe, state, "AF_HookLineView", 0.1)
	end
	probe.budgets.AF_HookLineView = 0.3
	local rows = probe:toTable()
	local labels = {}
	for _, row in rows do
		table.insert(labels, row.label .. ":" .. row.verdict)
	end
	T.eq(table.concat(labels, " "), "AF_FishStep:PASS AF_HookLineView:PASS AF_NetCues:n/a AF_PoolRefill:no data", "toTable: one row per label with samples or a budget, sorted, with the verdict")
	local fs = rows[1]
	T.check(fs.n == 3 and near(fs.medianMs, 0.61) and near(fs.p95Ms, 1.12) and near(fs.maxMs, 1.12) and near(fs.budgetMs, 1.0), "toTable: the AF_FishStep row carries n, median, p95, max and the budget")
	T.check(rows[4].n == 0 and rows[4].medianMs == nil and near(rows[4].budgetMs, 0.2), "toTable: a budget with no data has n 0 and nil statistics")
	probe:reset("AF_FishStep")
	for _ = 1, 10 do
		section(probe, state, "AF_FishStep", 1.5)
	end
	T.eq(probe:toTable()[1].verdict, "FAIL", "toTable: an over-budget label reads FAIL")
end

T.finish()
