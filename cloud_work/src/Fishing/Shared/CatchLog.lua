--!strict
-- CatchLog (About Fishing F1, WS-L catch record; Cloud, 2026-10-06; design/WSL_catchlog.md not yet written)
-- The per-player catch record: per species a count, the first catch (day, time, zone, length), the
-- best length and weight with the full best-length catch, and per-zone counts; a summary in
-- first-catch order; a JSON-safe save form that re-validates on load; and a deterministic,
-- commutative merge for save conflicts.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * FishingServer (CatchScene entry): CatchLog.record(log, { speciesId, lengthM, weightKg, zoneId,
--     dayN, timeOfDay, lureId }); the result's isFirst / isLengthRecord / isWeightRecord drive the
--     "New species!" / "New record!" cues in CatchSceneView (over FishingNet).
--   * SaveData: store CatchLog.serialize(log); rebuild with CatchLog.deserialize(tbl) in pcall; on a
--     DataStore conflict (UpdateAsync with two versions) use CatchLog.merge(local, remote).
--   * dayN / timeOfDay come from whatever owns the day clock; zoneId from FishZones; speciesId from
--     SpeciesTable (not checked here, so the log stays decoupled from the species list).
-- No Roblox globals.

local CatchLog = {}

export type Catch = { speciesId: string, lengthM: number, weightKg: number, zoneId: string, dayN: number, timeOfDay: number, lureId: string }
export type First = { dayN: number, timeOfDay: number, zoneId: string, lengthM: number }
export type Record = {
	count: number,
	first: First,
	bestLengthM: number,
	bestWeightKg: number,
	bestLengthCatch: Catch,
	zones: { [string]: number },
}
export type Log = { species: { [string]: Record }, order: { string }, totalCount: number }
export type Result = { isFirst: boolean, isLengthRecord: boolean, isWeightRecord: boolean, countNow: number }
export type SummaryRow = { speciesId: string, count: number, first: First, bestLengthM: number, bestWeightKg: number }
export type Summary = { speciesCount: number, totalCount: number, species: { SummaryRow } }

CatchLog.VERSION = 1

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

-- Why an untrusted catch table is not a catch, or nil when it is one.
local function catchProblem(c: any): string?
	if typeof(c) ~= "table" then
		return "catch must be a table"
	elseif not nonEmpty(c.speciesId) then
		return "speciesId must be a non-empty string"
	elseif not isNum(c.lengthM) or c.lengthM <= 0 then
		return "lengthM must be > 0"
	elseif not isNum(c.weightKg) or c.weightKg <= 0 then
		return "weightKg must be > 0"
	elseif not nonEmpty(c.zoneId) then
		return "zoneId must be a non-empty string"
	elseif not isInt(c.dayN) or c.dayN < 0 then
		return "dayN must be an integer >= 0"
	elseif not isNum(c.timeOfDay) or c.timeOfDay < 0 or c.timeOfDay > 24 then
		return "timeOfDay must be in 0..24"
	elseif not nonEmpty(c.lureId) then
		return "lureId must be a non-empty string"
	end
	return nil
end

local function copyCatch(c: Catch): Catch
	return { speciesId = c.speciesId, lengthM = c.lengthM, weightKg = c.weightKg, zoneId = c.zoneId, dayN = c.dayN, timeOfDay = c.timeOfDay, lureId = c.lureId }
end

local function copyFirst(f: First): First
	return { dayN = f.dayN, timeOfDay = f.timeOfDay, zoneId = f.zoneId, lengthM = f.lengthM }
end

local function copyRecord(r: Record): Record
	return {
		count = r.count,
		first = copyFirst(r.first),
		bestLengthM = r.bestLengthM,
		bestWeightKg = r.bestWeightKg,
		bestLengthCatch = copyCatch(r.bestLengthCatch),
		zones = table.clone(r.zones),
	}
end

-- Strict "earlier" order on firsts: day, time, then zone and length so equal times still order.
local function firstLess(a: First, b: First): boolean
	if a.dayN ~= b.dayN then
		return a.dayN < b.dayN
	elseif a.timeOfDay ~= b.timeOfDay then
		return a.timeOfDay < b.timeOfDay
	elseif a.zoneId ~= b.zoneId then
		return a.zoneId < b.zoneId
	end
	return a.lengthM < b.lengthM
end

-- Strict total order on catches, used only to break exact best-length ties deterministically.
local function catchLess(a: Catch, b: Catch): boolean
	if a.dayN ~= b.dayN then
		return a.dayN < b.dayN
	elseif a.timeOfDay ~= b.timeOfDay then
		return a.timeOfDay < b.timeOfDay
	elseif a.zoneId ~= b.zoneId then
		return a.zoneId < b.zoneId
	elseif a.lureId ~= b.lureId then
		return a.lureId < b.lureId
	elseif a.weightKg ~= b.weightKg then
		return a.weightKg < b.weightKg
	end
	return a.lengthM < b.lengthM
end

-- ---------------------------------------------------------------- the log
-- An empty log.
function CatchLog.new(): Log
	return { species = {}, order = {}, totalCount = 0 }
end

-- Records a catch (copied in) and says whether it is a first, a length record or a weight record.
function CatchLog.record(log: Log, catch: Catch): Result
	local problem = catchProblem(catch)
	if problem then
		error("CatchLog.record: " .. problem)
	end
	local c = copyCatch(catch)
	local rec = log.species[c.speciesId]
	local isFirst = rec == nil
	local isLengthRecord, isWeightRecord
	if rec == nil then
		rec = {
			count = 0,
			first = { dayN = c.dayN, timeOfDay = c.timeOfDay, zoneId = c.zoneId, lengthM = c.lengthM },
			bestLengthM = c.lengthM,
			bestWeightKg = c.weightKg,
			bestLengthCatch = c,
			zones = {},
		}
		log.species[c.speciesId] = rec
		table.insert(log.order, c.speciesId)
		isLengthRecord, isWeightRecord = true, true
	else
		isLengthRecord = c.lengthM > rec.bestLengthM
		isWeightRecord = c.weightKg > rec.bestWeightKg
		if isLengthRecord then
			rec.bestLengthM = c.lengthM
			rec.bestLengthCatch = c
		end
		if isWeightRecord then
			rec.bestWeightKg = c.weightKg
		end
	end
	rec.count += 1
	rec.zones[c.zoneId] = (rec.zones[c.zoneId] or 0) + 1
	log.totalCount += 1
	return { isFirst = isFirst, isLengthRecord = isLengthRecord, isWeightRecord = isWeightRecord, countNow = rec.count }
end

-- True when the species has been caught at least once.
function CatchLog.has(log: Log, speciesId: string): boolean
	return log.species[speciesId] ~= nil
end

-- The species' record (live reference), or nil.
function CatchLog.get(log: Log, speciesId: string): Record?
	return log.species[speciesId]
end

-- Species count, total count and one row per species in first-catch order.
function CatchLog.summary(log: Log): Summary
	local rows: { SummaryRow } = {}
	for _, id in log.order do
		local r = log.species[id]
		table.insert(rows, { speciesId = id, count = r.count, first = copyFirst(r.first), bestLengthM = r.bestLengthM, bestWeightKg = r.bestWeightKg })
	end
	return { speciesCount = #log.order, totalCount = log.totalCount, species = rows }
end

-- ---------------------------------------------------------------- save form
export type SerializedRecord = {
	id: string,
	count: number,
	first: First,
	bestLengthM: number,
	bestWeightKg: number,
	bestLengthCatch: Catch,
	zones: { [string]: number },
}
export type Serialized = { v: number, totalCount: number, species: { SerializedRecord } }

-- A plain JSON-safe table of the whole log, species in first-catch order.
function CatchLog.serialize(log: Log): Serialized
	local species: { SerializedRecord } = {}
	for _, id in log.order do
		local r = copyRecord(log.species[id])
		table.insert(species, { id = id, count = r.count, first = r.first, bestLengthM = r.bestLengthM, bestWeightKg = r.bestWeightKg, bestLengthCatch = r.bestLengthCatch, zones = r.zones })
	end
	return { v = CatchLog.VERSION, totalCount = log.totalCount, species = species }
end

-- Rebuilds a log from its save form, checking every type and invariant; errors name the species.
function CatchLog.deserialize(tbl: any): Log
	if typeof(tbl) ~= "table" or typeof(tbl.species) ~= "table" then
		error("CatchLog.deserialize: not a serialized log")
	end
	local log = CatchLog.new()
	local list: { any } = tbl.species
	for i = 1, #list do
		local s: any = typeof(list[i]) == "table" and list[i] or {}
		local label = "CatchLog.deserialize: species " .. tostring(s.id ~= nil and s.id or i)
		local function fail(why: string)
			error(label .. ": " .. why)
		end
		if not nonEmpty(s.id) then
			fail("id must be a non-empty string")
		end
		if log.species[s.id] then
			fail("duplicate id")
		end
		if not isInt(s.count) or s.count < 1 then
			fail("count must be an integer >= 1 (got " .. tostring(s.count) .. ")")
		end
		local f: any = s.first
		if typeof(f) ~= "table" or not isInt(f.dayN) or f.dayN < 0 or not isNum(f.timeOfDay) or f.timeOfDay < 0 or f.timeOfDay > 24 or not nonEmpty(f.zoneId) then
			fail("first must have dayN, timeOfDay and zoneId")
		end
		if not isNum(f.lengthM) or f.lengthM <= 0 then
			fail("first.lengthM must be > 0")
		end
		if not isNum(s.bestLengthM) or s.bestLengthM <= 0 then
			fail("bestLengthM must be > 0")
		end
		if not isNum(s.bestWeightKg) or s.bestWeightKg <= 0 then
			fail("bestWeightKg must be > 0")
		end
		local problem = catchProblem(s.bestLengthCatch)
		if problem then
			fail("bestLengthCatch." .. problem)
		end
		local best: Catch = s.bestLengthCatch
		if best.speciesId ~= s.id then
			fail("bestLengthCatch is another species")
		end
		if best.lengthM ~= s.bestLengthM or s.bestLengthM < f.lengthM or s.bestWeightKg < best.weightKg then
			fail("bests disagree with the catches")
		end
		if typeof(s.zones) ~= "table" then
			fail("zones must be a table")
		end
		local zones: { [string]: number } = {}
		local zoneSum = 0
		for zoneId, n in s.zones do
			if not nonEmpty(zoneId) or not isInt(n) or n < 1 then
				fail("zones must map zone ids to counts >= 1")
			end
			zones[zoneId] = n
			zoneSum += n
		end
		if zoneSum ~= s.count then
			fail("zones do not add up to count")
		end
		log.species[s.id] = {
			count = s.count,
			first = { dayN = f.dayN, timeOfDay = f.timeOfDay, zoneId = f.zoneId, lengthM = f.lengthM },
			bestLengthM = s.bestLengthM,
			bestWeightKg = s.bestWeightKg,
			bestLengthCatch = copyCatch(best),
			zones = zones,
		}
		table.insert(log.order, s.id)
		log.totalCount += s.count
	end
	return log
end

-- ---------------------------------------------------------------- merge
-- A new log combining two: counts and zones add, firsts keep the earlier, bests keep the larger;
-- species order is by first catch (day, time, id). Deterministic and commutative; inputs untouched.
function CatchLog.merge(a: Log, b: Log): Log
	local out = CatchLog.new()
	local ids: { string } = {}
	for id in a.species do
		table.insert(ids, id)
	end
	for id in b.species do
		if a.species[id] == nil then
			table.insert(ids, id)
		end
	end
	for _, id in ids do
		local ra, rb = a.species[id], b.species[id]
		if ra == nil or rb == nil then
			out.species[id] = copyRecord((ra or rb) :: Record)
		else
			local zones = table.clone(ra.zones)
			for z, n in rb.zones do
				zones[z] = (zones[z] or 0) + n
			end
			local bestFrom = ra
			if rb.bestLengthM > ra.bestLengthM or (rb.bestLengthM == ra.bestLengthM and catchLess(rb.bestLengthCatch, ra.bestLengthCatch)) then
				bestFrom = rb
			end
			out.species[id] = {
				count = ra.count + rb.count,
				first = copyFirst(firstLess(rb.first, ra.first) and rb.first or ra.first),
				bestLengthM = bestFrom.bestLengthM,
				bestWeightKg = math.max(ra.bestWeightKg, rb.bestWeightKg),
				bestLengthCatch = copyCatch(bestFrom.bestLengthCatch),
				zones = zones,
			}
		end
		out.totalCount += out.species[id].count
	end
	table.sort(ids, function(x: string, y: string): boolean
		local fx, fy = out.species[x].first, out.species[y].first
		if fx.dayN ~= fy.dayN then
			return fx.dayN < fy.dayN
		elseif fx.timeOfDay ~= fy.timeOfDay then
			return fx.timeOfDay < fy.timeOfDay
		end
		return x < y
	end)
	out.order = ids
	return out
end

return CatchLog
