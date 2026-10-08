--!strict
-- PerfProbe (About Fishing F1, PERF budget; Cloud, 2026-10-08; design/PERF_budget.md)
-- Labelled timing sections with a ring of the last N samples per label (default 3600 = 60 s at 60 Hz),
-- median / p95 / max / mean reports in milliseconds, budgets with the note's rule (median over budget or
-- p95 over twice it), an enabled flag that makes begin/finish one bool check when off, and the rows of
-- the note's results table.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * One probe per side: PerfProbe.new(os.clock, { budgets = { AF_FishStep = 1.0, AF_PoolRefill = 0.2,
--     AF_FishPoolView = 0.5, AF_HookLineView = 0.3, AF_NetCues = 0.1 }, profileBegin = debug.profilebegin,
--     profileEnd = debug.profileend }); probe:setEnabled(workspace:GetAttribute("PerfProbe") == true).
--   * FishingServer around the FishBrain step and the pool refill, FishPoolView and HookLineView around
--     their per-frame work: probe:begin("AF_FishStep") ... probe:finish("AF_FishStep").
--   * Dev3's matrix run (note section 3): print(probe:toLine(label, "anglers=4 fish=16")) per label;
--     probe:toTable() gives the rows of the section 7 template.
-- Decisions a dev must know:
--   * Samples are stored in milliseconds: (finish - begin) * msPerUnit, msPerUnit 1000 for os.clock
--     (seconds). Budgets, reports and the table are all ms, so nothing mixes units.
--   * p95 is the nearest-rank value (ceil(0.95 n)), the same rule as EncounterLog.summary.
--   * enabled is false by default (the note: on only by the Studio attribute); report() is nil while off
--     and the rings keep their samples.
--   * A finish without a begin is ignored and counted (stats().unbalanced); a second begin on the same
--     label before its finish restarts the section and counts the dropped start (stats().dropped).
-- No Roblox globals; debug.profilebegin / profileend are injected, so the CLI never sees them.

local PerfProbe = {}
PerfProbe.__index = PerfProbe

export type Report = { n: number, min: number, median: number, p95: number, max: number, mean: number }
export type Row = { label: string, n: number, medianMs: number?, p95Ms: number?, maxMs: number?, meanMs: number?, budgetMs: number?, verdict: string }
export type Opts = {
	ringN: number?, -- samples kept per label
	msPerUnit: number?, -- how many ms one clock unit is (1000 for a seconds clock)
	budgets: { [string]: number }?, -- ms per label
	enabled: boolean?,
	profileBegin: ((label: string) -> ())?, -- debug.profilebegin
	profileEnd: (() -> ())?, -- debug.profileend
}
export type Stats = { begins: number, finishes: number, unbalanced: number, dropped: number }

type Ring = { buf: { number }, n: number, next: number }
type Fields = {
	enabled: boolean,
	budgets: { [string]: number },
	_clock: () -> number,
	_ringN: number,
	_msPerUnit: number,
	_rings: { [string]: Ring },
	_open: { [string]: number },
	_profileBegin: ((label: string) -> ())?,
	_profileEnd: (() -> ())?,
	_stats: Stats,
}
export type PerfProbe = typeof(setmetatable({} :: Fields, PerfProbe))

PerfProbe.DEFAULT_RING_N = 3600
PerfProbe.P95 = 0.95
PerfProbe.P95_FACTOR = 2 -- the note's rule: p95 may be at most this many times the budget

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v < math.huge and v > -math.huge
end

-- A probe over a clock (os.clock in Studio; a fake in tests).
function PerfProbe.new(clock: () -> number, opts: Opts?): PerfProbe
	assert(typeof(clock) == "function", "PerfProbe.new: clock must be a function returning a number")
	local o: Opts = opts or {}
	local ringN = o.ringN or PerfProbe.DEFAULT_RING_N
	local msPerUnit = o.msPerUnit or 1000
	assert(finite(ringN) and ringN >= 1 and ringN == math.floor(ringN), "PerfProbe.new: ringN must be a positive integer")
	assert(finite(msPerUnit) and msPerUnit > 0, "PerfProbe.new: msPerUnit must be > 0")
	local budgets: { [string]: number } = {}
	for label, ms in o.budgets or {} do
		assert(typeof(label) == "string" and finite(ms) and ms > 0, "PerfProbe.new: budgets map labels to ms > 0")
		budgets[label] = ms
	end
	local self: Fields = {
		enabled = o.enabled == true,
		budgets = budgets,
		_clock = clock,
		_ringN = ringN,
		_msPerUnit = msPerUnit,
		_rings = {},
		_open = {},
		_profileBegin = o.profileBegin,
		_profileEnd = o.profileEnd,
		_stats = { begins = 0, finishes = 0, unbalanced = 0, dropped = 0 },
	}
	return setmetatable(self, PerfProbe)
end

function PerfProbe.setEnabled(self: PerfProbe, enabled: boolean)
	self.enabled = enabled == true
end

-- Starts a section. Off: one bool check and nothing else.
function PerfProbe.begin(self: PerfProbe, label: string)
	if not self.enabled then
		return
	end
	if self._open[label] ~= nil then
		self._stats.dropped += 1
	end
	local pb = self._profileBegin
	if pb then
		pb(label)
	end
	self._stats.begins += 1
	self._open[label] = self._clock()
end

-- Ends a section and records its ms; returns the ms, or nil when off or unbalanced.
function PerfProbe.finish(self: PerfProbe, label: string): number?
	if not self.enabled then
		return nil
	end
	local t1 = self._clock()
	local pe = self._profileEnd
	if pe then
		pe()
	end
	local t0 = self._open[label]
	if t0 == nil then
		self._stats.unbalanced += 1
		return nil
	end
	self._open[label] = nil
	local ms = (t1 - t0) * self._msPerUnit
	local ring = self._rings[label]
	if ring == nil then
		ring = { buf = {}, n = 0, next = 1 }
		self._rings[label] = ring
	end
	ring.buf[ring.next] = ms
	ring.next = ring.next % self._ringN + 1
	if ring.n < self._ringN then
		ring.n += 1
	end
	self._stats.finishes += 1
	return ms
end

-- The label's samples oldest first (a copy), or an empty array.
function PerfProbe.samples(self: PerfProbe, label: string): { number }
	local ring = self._rings[label]
	local out: { number } = {}
	if ring == nil then
		return out
	end
	local start = if ring.n < self._ringN then 1 else ring.next
	for i = 0, ring.n - 1 do
		out[i + 1] = ring.buf[(start - 1 + i) % self._ringN + 1]
	end
	return out
end

-- n, min, median, p95 (nearest rank), max, mean in ms; nil while off or with no samples.
function PerfProbe.report(self: PerfProbe, label: string): Report?
	if not self.enabled then
		return nil
	end
	local vals = self:samples(label)
	local n = #vals
	if n == 0 then
		return nil
	end
	table.sort(vals)
	local sum = 0
	for _, v in vals do
		sum += v
	end
	local median = if n % 2 == 1 then vals[(n + 1) // 2] else (vals[n // 2] + vals[n // 2 + 1]) / 2
	local rank = math.max(1, math.ceil(PerfProbe.P95 * n))
	return { n = n, min = vals[1], median = median, p95 = vals[rank], max = vals[n], mean = sum / n }
end

-- The note's rule: median over the budget, or p95 over P95_FACTOR x the budget. False without a
-- budget or without samples.
function PerfProbe.overBudget(self: PerfProbe, label: string): boolean
	local budget = self.budgets[label]
	local r = self:report(label)
	if budget == nil or r == nil then
		return false
	end
	return r.median > budget or r.p95 > PerfProbe.P95_FACTOR * budget
end

-- Every label with samples, sorted.
function PerfProbe.labels(self: PerfProbe): { string }
	local out: { string } = {}
	for label in self._rings do
		table.insert(out, label)
	end
	table.sort(out)
	return out
end

-- Drops one label's samples (or every label's) and any open section.
function PerfProbe.reset(self: PerfProbe, label: string?)
	if label then
		self._rings[label] = nil
		self._open[label] = nil
	else
		self._rings = {}
		self._open = {}
	end
end

-- One line per label in the note's form: PERF <label> [extra] n=3600 med=0.610ms p95=1.120ms max=3.400ms
function PerfProbe.toLine(self: PerfProbe, label: string, extra: string?): string
	local head = "PERF " .. label .. (if extra and extra ~= "" then " " .. extra else "")
	local r = self:report(label)
	if r == nil then
		return head .. " n=0"
	end
	return string.format("%s n=%d med=%.3fms p95=%.3fms max=%.3fms", head, r.n, r.median, r.p95, r.max)
end

-- The rows of the results table (note section 7), one per label with samples or a budget, sorted:
-- verdict PASS / FAIL by the budget rule, "n/a" without a budget, "no data" without samples.
function PerfProbe.toTable(self: PerfProbe): { Row }
	local names: { [string]: boolean } = {}
	for label in self._rings do
		names[label] = true
	end
	for label in self.budgets do
		names[label] = true
	end
	local labels: { string } = {}
	for label in names do
		table.insert(labels, label)
	end
	table.sort(labels)
	local rows: { Row } = {}
	for _, label in labels do
		local r = self:report(label)
		local budget = self.budgets[label]
		local verdict: string
		if r == nil then
			verdict = "no data"
		elseif budget == nil then
			verdict = "n/a"
		else
			verdict = if self:overBudget(label) then "FAIL" else "PASS"
		end
		table.insert(rows, {
			label = label,
			n = if r then r.n else 0,
			medianMs = if r then r.median else nil,
			p95Ms = if r then r.p95 else nil,
			maxMs = if r then r.max else nil,
			meanMs = if r then r.mean else nil,
			budgetMs = budget,
			verdict = verdict,
		})
	end
	return rows
end

-- Counters: begins, finishes, unbalanced (finish without begin), dropped (begin over an open section).
function PerfProbe.stats(self: PerfProbe): Stats
	return table.clone(self._stats)
end

return PerfProbe
