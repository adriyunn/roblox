--!strict
-- EncounterLog (About Fishing F1, WS-P; Cloud, 2026-10-06; design/WSP_parity_log.md)
-- Parity logger: one encounter = one fish engaging one angler. Records the F1 cue timeline per
-- encounter, derives the numbers the parity checklist compares against About Fishing (notice to first
-- nip, hover time, press offset, fight time, jumps, spooks), summarises them (median, p95) and checks
-- them against per-hook-mode bands. toCsv/toTable feed tools/parity_report.py: keep the header below
-- and CSV_HEADER in that file identical.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * FishingServer (where FishBrain/FishJudge/FishPool report) calls start(log, id, info) when a fish
--     notices a hook (the Notice cue), event(log, id, name, t, data) for each cue it sends (Nip, Swallow,
--     Press, Verdict {verdict}, Hooked, Jump, Snap, Caught, GiveUp, Spook {reason}, Leave) and
--     finish(log, id, t, outcome) when the fish is Caught / Snap / GiveUp / Leave / Spook.
--   * Times are seconds on one clock (os.clock() or workspace:GetServerTimeNow()); only differences
--     matter. info.t is the Notice time. hookMode is "bed" | "mid" | "lure" from the hook state.
--   * Export: toCsv(records) into a StringValue or the output for Adrian to copy, or
--     HttpService:JSONEncode(toTable(records)); then
--     python tools/parity_report.py <file> --bands tools/parity_bands.json
-- CSV header (one line per record; seconds with 3 decimals, counts as integers, nil as empty):
--   id,anglerId,fishId,speciesId,hookMode,outcome,tNotice,tEnd,noticeToFirstNip,hoverS,pressOffset,verdict,fightS,jumps,spooks

local EncounterLog = {}

export type Info = { anglerId: any, fishId: any, speciesId: string?, hookMode: string, t: number }
export type Event = { name: string, t: number, data: { [string]: any }? }
export type Record = {
	id: string,
	info: Info,
	outcome: string,
	tNotice: number,
	tEnd: number,
	noticeToFirstNip: number?,
	hoverS: number?,
	pressOffset: number?,
	verdict: string?,
	fightS: number?,
	jumps: number,
	spooks: number,
	events: { Event },
}
export type Summary = { n: number, min: number?, median: number?, p95: number?, max: number?, mean: number? }
export type Band = { metric: string, hookMode: string, n: number, median: number?, lo: number, hi: number, ok: boolean, reason: string? }
export type BandTable = { [string]: { [string]: { number } } }
export type Log = { active: { [string]: { info: Info, events: { Event } } }, records: { Record }, maxRecords: number, dropped: number }

local FIELDS = {
	"id", "anglerId", "fishId", "speciesId", "hookMode", "outcome", "tNotice", "tEnd",
	"noticeToFirstNip", "hoverS", "pressOffset", "verdict", "fightS", "jumps", "spooks",
}
local SECONDS = { tNotice = true, tEnd = true, noticeToFirstNip = true, hoverS = true, pressOffset = true, fightS = true }
local COUNTS = { jumps = true, spooks = true }
local HOOK_MODES = { bed = true, mid = true, lure = true }

EncounterLog.FIELDS = FIELDS
EncounterLog.CSV_HEADER = table.concat(FIELDS, ",")
EncounterLog.DEFAULT_MAX_RECORDS = 1000

-- A new, empty log. opts.maxRecords (default 1000) caps the finished records kept: the oldest drops and
-- log.dropped counts, so a long-lived server with the logger left on does not grow without bound.
function EncounterLog.new(opts: { maxRecords: number? }?): Log
	local max = if opts and opts.maxRecords ~= nil then opts.maxRecords else EncounterLog.DEFAULT_MAX_RECORDS
	assert(typeof(max) == "number" and max >= 1 and max == math.floor(max), "EncounterLog.new: maxRecords must be a positive integer")
	return { active = {}, records = {}, maxRecords = max, dropped = 0 }
end

-- Opens an encounter; info.t is the Notice time. Errors on a duplicate id or a bad hookMode.
function EncounterLog.start(log: Log, id: string, info: Info)
	assert(typeof(id) == "string" and id ~= "", "EncounterLog.start: id must be a non-empty string")
	assert(log.active[id] == nil, "EncounterLog.start: encounter already started: " .. id)
	assert(typeof(info) == "table" and typeof(info.t) == "number", "EncounterLog.start: info.t (Notice time) is required")
	assert(HOOK_MODES[info.hookMode] == true, "EncounterLog.start: hookMode must be bed | mid | lure, got " .. tostring(info.hookMode))
	log.active[id] = {
		info = { anglerId = info.anglerId, fishId = info.fishId, speciesId = info.speciesId, hookMode = info.hookMode, t = info.t },
		events = {},
	}
end

-- Appends a cue to an open encounter. Errors on an unknown id.
function EncounterLog.event(log: Log, id: string, name: string, t: number, data: { [string]: any }?)
	local enc = log.active[id]
	if enc == nil then
		error("EncounterLog.event: unknown encounter id: " .. tostring(id))
	end
	assert(typeof(name) == "string" and typeof(t) == "number", "EncounterLog.event: name must be a string and t a number")
	table.insert(enc.events, { name = name, t = t, data = data })
end

local function firstT(events: { Event }, name: string): number?
	for _, e in events do
		if e.name == name then
			return e.t
		end
	end
	return nil
end

local function countName(events: { Event }, name: string): number
	local n = 0
	for _, e in events do
		if e.name == name then
			n += 1
		end
	end
	return n
end

-- Closes an encounter and derives its numbers; returns the record (also appended to records(log)).
function EncounterLog.finish(log: Log, id: string, t: number, outcome: string): Record
	local enc = log.active[id]
	if enc == nil then
		error("EncounterLog.finish: unknown encounter id: " .. tostring(id))
	end
	log.active[id] = nil
	local ev = enc.events
	local tNotice = enc.info.t
	local tNip = firstT(ev, "Nip")
	local tSwallow = firstT(ev, "Swallow")
	local tLeave = firstT(ev, "Leave")
	local tPress = firstT(ev, "Press")
	local tHooked = firstT(ev, "Hooked")
	local tFightEnd = firstT(ev, "Caught") or firstT(ev, "Snap") or firstT(ev, "GiveUp")
	local verdict: string? = nil
	for _, e in ev do
		if e.name == "Verdict" and e.data and typeof(e.data.verdict) == "string" then
			verdict = e.data.verdict
			break
		end
	end
	local hoverEnd = tSwallow or tLeave
	local rec: Record = {
		id = id,
		info = enc.info,
		outcome = outcome,
		tNotice = tNotice,
		tEnd = t,
		noticeToFirstNip = if tNip then tNip - tNotice else nil,
		hoverS = if hoverEnd then hoverEnd - tNotice else nil,
		pressOffset = if tPress and tSwallow then tPress - tSwallow else nil,
		verdict = verdict,
		-- a hooked fish's fight ends at its Caught / Snap / GiveUp cue, or at finish() when that cue was
		-- not logged as an event (finish(t, outcome) alone is enough)
		fightS = if tHooked then (tFightEnd or t) - tHooked else nil,
		jumps = countName(ev, "Jump"),
		spooks = countName(ev, "Spook"),
		events = ev,
	}
	table.insert(log.records, rec)
	if #log.records > log.maxRecords then
		table.remove(log.records, 1)
		log.dropped += 1
	end
	return rec
end

-- The finished records in finish order (at most maxRecords; log.dropped counts the oldest dropped).
function EncounterLog.records(log: Log): { Record }
	return log.records
end

-- n, min, median, p95 (nearest rank), max, mean of one metric over records with that metric set.
function EncounterLog.summary(records: { Record }, metric: string): Summary
	local vals: { number } = {}
	for _, r in records do
		local v = (r :: any)[metric]
		if typeof(v) == "number" then
			table.insert(vals, v :: number)
		end
	end
	table.sort(vals)
	local n = #vals
	if n == 0 then
		return { n = 0 }
	end
	local sum = 0
	for _, v in vals do
		sum += v
	end
	local median: number = if n % 2 == 1 then vals[(n + 1) // 2] else (vals[n // 2] + vals[n // 2 + 1]) / 2
	local rank = math.max(1, math.ceil(0.95 * n))
	return { n = n, min = vals[1], median = median, p95 = vals[rank], max = vals[n], mean = sum / n }
end

-- Checks each (hookMode, metric) band: ok when n >= 5 and lo <= median <= hi. Rows sorted by
-- hookMode then metric; bandTable = { bed = { hoverS = {5, 45} }, mid = { ... } }.
function EncounterLog.bands(records: { Record }, bandTable: BandTable): { Band }
	local modes = {}
	for mode in bandTable do
		table.insert(modes, mode)
	end
	table.sort(modes)
	local out: { Band } = {}
	for _, mode in modes do
		local subset = {}
		for _, r in records do
			if r.info.hookMode == mode then
				table.insert(subset, r)
			end
		end
		local metrics = {}
		for metric in bandTable[mode] do
			table.insert(metrics, metric)
		end
		table.sort(metrics)
		for _, metric in metrics do
			local range = bandTable[mode][metric]
			local lo, hi = range[1], range[2]
			assert(typeof(lo) == "number" and typeof(hi) == "number" and lo <= hi, "EncounterLog.bands: band must be {lo, hi}: " .. mode .. "." .. metric)
			local s = EncounterLog.summary(subset, metric)
			local row: Band = { metric = metric, hookMode = mode, n = s.n, median = s.median, lo = lo, hi = hi, ok = true, reason = nil }
			local median: number = s.median or 0
			if s.n < 5 then
				row.ok = false
				row.reason = string.format("n<5 (n=%d)", s.n)
			elseif median < lo or median > hi then
				row.ok = false
				row.reason = string.format("median %.3f outside %.3f..%.3f", median, lo, hi)
			end
			table.insert(out, row)
		end
	end
	return out
end

local function flatValue(rec: Record, field: string): any
	if field == "anglerId" or field == "fishId" or field == "speciesId" or field == "hookMode" then
		return (rec.info :: any)[field]
	end
	return (rec :: any)[field]
end

local function csvCell(field: string, v: any): string
	if v == nil then
		return ""
	elseif SECONDS[field] then
		return string.format("%.3f", v)
	elseif COUNTS[field] then
		return string.format("%d", v)
	end
	local s = tostring(v)
	if s:find('[,"\r\n]') then
		s = '"' .. s:gsub('"', '""') .. '"'
	end
	return s
end

-- CSV with the fixed header, one line per record, LF line endings, trailing newline.
function EncounterLog.toCsv(records: { Record }): string
	local lines = { EncounterLog.CSV_HEADER }
	for _, rec in records do
		local cells = {}
		for i, field in FIELDS do
			cells[i] = csvCell(field, flatValue(rec, field))
		end
		table.insert(lines, table.concat(cells, ","))
	end
	return table.concat(lines, "\n") .. "\n"
end

-- JSON-safe { v = 1, fields = FIELDS, records = { { <the same fields as the CSV>, events = {...} } } }.
function EncounterLog.toTable(records: { Record }): { [string]: any }
	local rows = {}
	for _, rec in records do
		local row: { [string]: any } = {}
		for _, field in FIELDS do
			row[field] = flatValue(rec, field)
		end
		local events = {}
		for i, e in rec.events do
			events[i] = { name = e.name, t = e.t, data = e.data }
		end
		row.events = events
		table.insert(rows, row)
	end
	return { v = 1, fields = table.clone(FIELDS), records = rows }
end

return EncounterLog
