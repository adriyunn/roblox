--!strict
-- EvidenceBoard (About Fishing F1, WS-T story clues; Cloud, 2026-10-08; design/PARITY_rows_F2plus.md rows P14, P15)
-- Clues, the string between them and the conclusions they reach, as pure state over a validated
-- definition: discover(clueId, where/when), the player's manual links between discovered clues the
-- defs allow, automatic links ("handwritten notes") that appear once their required clues are found,
-- conclusions reached when their clue and link ids are all present, pins for the board UI placed by
-- discovery order, a JSON-safe save form that re-validates against the defs, a commutative merge for
-- save conflicts (union of discoveries, earliest time wins), and rollFind: the "clues surface while
-- fishing or casting in random spots" draw, weighted by source and zone with one rng number and a
-- sorted id order so the same seed always finds the same clue.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * Every id here (clue_01, npc_a, zone ids, link ids, conclusion ids) is a placeholder; the defs
--     table is the writing team's data and this module never holds text, only ids and tags.
--   * FishingServer: on a catch (source "fish") or a cast landing (source "cast") call
--     EvidenceBoard.rollFind(defs, rng, { source, zoneId, board }) with the server rng; a non-nil id
--     goes to EvidenceBoard.discover(board, id, { dayN, timeOfDay, zoneId }) and, when isNew, to a
--     "clue found" cue over FishingNet. NPC talk and place triggers call discover directly.
--   * The board UI sends Link(a, b) / Unlink(a, b) requests through FishingNet and RequestGuard; the
--     server answers with link()/unlink()'s ok, reason and replicates pins()/links()/conclusions().
--   * SaveData: store serialize(board); rebuild with deserialize(tbl, defs) in pcall; a save naming
--     an unknown clue id errors (a changed defs file or a tampered save) and the caller decides.
--     merge(a, b) resolves a local-vs-remote conflict: both must come from the same compiled defs.
-- No Roblox globals; no rng of its own.

local EvidenceBoard = {}

export type ClueDef = { kind: string, source: string, tags: { string }, chance: number?, zones: { [string]: number }?, requires: { string }? }
export type LinkDef = { id: string?, a: string, b: string, kind: string, requires: { string }? }
export type ConclusionDef = { id: string, requires: { string } }
export type Defs = { clues: { [string]: ClueDef }, links: { LinkDef }?, conclusions: { ConclusionDef }? }
export type Link = { id: string, a: string, b: string, kind: string, requires: { string }, auto: boolean, index: number }
export type Compiled = {
	clues: { [string]: ClueDef },
	clueIds: { string },
	links: { Link },
	linkById: { [string]: Link },
	linkByPair: { [string]: Link },
	conclusions: { ConclusionDef },
	_compiled: boolean,
}
export type Found = { dayN: number, timeOfDay: number, zoneId: string }
export type Board = { defs: Compiled, found: { [string]: Found }, order: { string }, links: { [string]: boolean } }
export type FindCtx = { source: string, zoneId: string, board: Board? }
export type Pin = { clueId: string, kind: string, source: string, tags: { string }, dayN: number, timeOfDay: number, zoneId: string, slot: number, col: number, row: number }
export type LinkRow = { id: string, a: string, b: string, kind: string, auto: boolean }
export type Progress = { discovered: number, total: number, linked: number, totalLinks: number, conclusions: number, totalConclusions: number }

EvidenceBoard.VERSION = 1
EvidenceBoard.KINDS = { "item", "note", "photo", "testimony" }
EvidenceBoard.SOURCES = { "fish", "cast", "npc", "place" }
EvidenceBoard.LINK_KINDS = { "string", "note" }
EvidenceBoard.PinColumns = 4 -- pins fill the board left to right, four to a row (UI placeholder)

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

local function pairKey(a: string, b: string): string
	return if a < b then a .. "|" .. b else b .. "|" .. a
end

local function checkIdList(label: string, list: any, known: { [string]: any }, what: string): { string }
	if typeof(list) ~= "table" then
		error(label .. ": requires must be an array of " .. what .. " ids")
	end
	local out: { string } = {}
	for i = 1, #list do
		local id = list[i]
		if not nonEmpty(id) then
			error(label .. ": requires[" .. i .. "] must be a non-empty string")
		end
		if known[id] == nil then
			error(label .. ": requires unknown " .. what .. " " .. tostring(id))
		end
		out[i] = id
	end
	return out
end

local function foundProblem(ctx: any): string?
	if typeof(ctx) ~= "table" then
		return "ctx must be a table"
	elseif not isInt(ctx.dayN) or ctx.dayN < 0 then
		return "dayN must be an integer >= 0"
	elseif not isNum(ctx.timeOfDay) or ctx.timeOfDay < 0 or ctx.timeOfDay > 24 then
		return "timeOfDay must be in 0..24"
	elseif not nonEmpty(ctx.zoneId) then
		return "zoneId must be a non-empty string"
	end
	return nil
end

-- Strict "earlier" order on discoveries: day, time, then zone and id so equal times still order.
local function foundLess(a: Found, b: Found, idA: string, idB: string): boolean
	if a.dayN ~= b.dayN then
		return a.dayN < b.dayN
	elseif a.timeOfDay ~= b.timeOfDay then
		return a.timeOfDay < b.timeOfDay
	elseif a.zoneId ~= b.zoneId then
		return a.zoneId < b.zoneId
	end
	return idA < idB
end

-- ---------------------------------------------------------------- the definition
-- Validates a defs table once: every id is checked, every link and conclusion refers to known ids,
-- link pairs are unique, and the sorted clue id list rollFind draws in is fixed here.
function EvidenceBoard.compile(defs: any): Compiled
	if typeof(defs) == "table" and defs._compiled == true then
		return defs
	end
	if typeof(defs) ~= "table" or typeof(defs.clues) ~= "table" then
		error("EvidenceBoard.compile: defs.clues must be a table of clueId = { kind, source, tags }")
	end
	local clues: { [string]: ClueDef } = {}
	local clueIds: { string } = {}
	for id in defs.clues do
		if not nonEmpty(id) then
			error("EvidenceBoard.compile: clue ids must be non-empty strings")
		end
		if id:find("|", 1, true) then
			error("EvidenceBoard.compile: clue " .. id .. ": ids must not contain '|'")
		end
		table.insert(clueIds, id)
	end
	table.sort(clueIds)
	for _, id in clueIds do
		local c: any = defs.clues[id]
		local label = "EvidenceBoard.compile: clue " .. id
		if typeof(c) ~= "table" then
			error(label .. ": must be a table")
		end
		if table.find(EvidenceBoard.KINDS, c.kind) == nil then
			error(label .. ": kind must be one of " .. table.concat(EvidenceBoard.KINDS, "/") .. " (got " .. tostring(c.kind) .. ")")
		end
		if table.find(EvidenceBoard.SOURCES, c.source) == nil then
			error(label .. ": source must be one of " .. table.concat(EvidenceBoard.SOURCES, "/") .. " (got " .. tostring(c.source) .. ")")
		end
		if typeof(c.tags) ~= "table" then
			error(label .. ": tags must be an array of strings")
		end
		local tags: { string } = {}
		for i = 1, #c.tags do
			if not nonEmpty(c.tags[i]) then
				error(label .. ": tags must be non-empty strings")
			end
			tags[i] = c.tags[i]
		end
		if c.chance ~= nil and (not isNum(c.chance) or c.chance < 0 or c.chance > 1) then
			error(label .. ": chance must be in 0..1")
		end
		local zones: { [string]: number }? = nil
		if c.zones ~= nil then
			if typeof(c.zones) ~= "table" then
				error(label .. ": zones must be a table of zoneId = weight")
			end
			local z: { [string]: number } = {}
			for zoneId, w in c.zones do
				if not nonEmpty(zoneId) or not isNum(w) or w < 0 then
					error(label .. ": zones must map zone ids to weights >= 0")
				end
				z[zoneId] = w
			end
			zones = z
		end
		clues[id] = { kind = c.kind, source = c.source, tags = tags, chance = c.chance, zones = zones, requires = nil }
	end
	for _, id in clueIds do
		local c: any = defs.clues[id]
		if c.requires ~= nil then
			local req = checkIdList("EvidenceBoard.compile: clue " .. id, c.requires, clues, "clue")
			if table.find(req, id) then
				error("EvidenceBoard.compile: clue " .. id .. ": requires itself")
			end
			clues[id].requires = req
		end
	end
	local links: { Link } = {}
	local linkById: { [string]: Link } = {}
	local linkByPair: { [string]: Link } = {}
	local linkList: { any } = defs.links or {}
	if typeof(linkList) ~= "table" then
		error("EvidenceBoard.compile: links must be an array")
	end
	for i = 1, #linkList do
		local l: any = linkList[i]
		local label = "EvidenceBoard.compile: link " .. i
		if typeof(l) ~= "table" or not nonEmpty(l.a) or not nonEmpty(l.b) then
			error(label .. ": a and b must be clue ids")
		end
		if clues[l.a] == nil or clues[l.b] == nil then
			error(label .. ": unknown clue " .. tostring(if clues[l.a] == nil then l.a else l.b))
		end
		if l.a == l.b then
			error(label .. ": a and b must differ")
		end
		if table.find(EvidenceBoard.LINK_KINDS, l.kind) == nil then
			error(label .. ": kind must be string or note (got " .. tostring(l.kind) .. ")")
		end
		local id: string = if l.id ~= nil then l.id else "link:" .. l.a .. "+" .. l.b
		if not nonEmpty(id) then
			error(label .. ": id must be a non-empty string when given")
		end
		if linkById[id] or clues[id] then
			error(label .. ": id " .. id .. " is already used")
		end
		local key = pairKey(l.a, l.b)
		if linkByPair[key] then
			error(label .. ": the pair " .. l.a .. ", " .. l.b .. " is already linked by " .. linkByPair[key].id)
		end
		local requires: { string } = if l.requires ~= nil then checkIdList(label, l.requires, clues, "clue") else {}
		local link: Link = { id = id, a = l.a, b = l.b, kind = l.kind, requires = requires, auto = #requires > 0, index = i }
		links[i] = link
		linkById[id] = link
		linkByPair[key] = link
	end
	local conclusions: { ConclusionDef } = {}
	local concList: { any } = defs.conclusions or {}
	if typeof(concList) ~= "table" then
		error("EvidenceBoard.compile: conclusions must be an array")
	end
	local known: { [string]: any } = table.clone(clues)
	for id in linkById do
		known[id] = true
	end
	local concIds: { [string]: boolean } = {}
	for i = 1, #concList do
		local c: any = concList[i]
		if typeof(c) ~= "table" or not nonEmpty(c.id) then
			error("EvidenceBoard.compile: conclusion " .. i .. ": id must be a non-empty string")
		end
		local label = "EvidenceBoard.compile: conclusion " .. c.id
		if concIds[c.id] then
			error(label .. ": duplicate id")
		end
		concIds[c.id] = true
		local req = checkIdList(label, c.requires, known, "clue or link")
		if #req == 0 then
			error(label .. ": requires must name at least one clue or link")
		end
		conclusions[i] = { id = c.id, requires = req }
	end
	return { clues = clues, clueIds = clueIds, links = links, linkById = linkById, linkByPair = linkByPair, conclusions = conclusions, _compiled = true }
end

-- ---------------------------------------------------------------- the board
-- An empty board over a defs table (raw or compiled).
function EvidenceBoard.new(defs: any): Board
	return { defs = EvidenceBoard.compile(defs), found = {}, order = {}, links = {} }
end

local function allFound(board: Board, ids: { string }): boolean
	for _, id in ids do
		if board.found[id] == nil then
			return false
		end
	end
	return true
end

-- Draws every automatic link whose ends and required clues are all discovered.
local function refreshAuto(board: Board)
	for _, l in board.defs.links do
		if l.auto and board.links[l.id] == nil and board.found[l.a] and board.found[l.b] and allFound(board, l.requires) then
			board.links[l.id] = false
		end
	end
end

-- Records a clue with when and where it was found; true when it is new, false when already known,
-- nil, reason for an unknown clue id. A bad ctx is a programmer error.
function EvidenceBoard.discover(board: Board, clueId: string, ctx: Found): (boolean?, string?)
	if board.defs.clues[clueId] == nil then
		return nil, "unknown clue " .. tostring(clueId)
	end
	local problem = foundProblem(ctx)
	if problem then
		error("EvidenceBoard.discover: " .. problem)
	end
	if board.found[clueId] then
		return false, nil
	end
	board.found[clueId] = { dayN = ctx.dayN, timeOfDay = ctx.timeOfDay, zoneId = ctx.zoneId }
	table.insert(board.order, clueId)
	refreshAuto(board)
	return true, nil
end

-- True when the clue is on the board.
function EvidenceBoard.has(board: Board, clueId: string): boolean
	return board.found[clueId] ~= nil
end

local function linkFor(board: Board, a: any, b: any): (Link?, string?)
	if not nonEmpty(a) or not nonEmpty(b) then
		return nil, "clue ids must be strings"
	end
	if board.defs.clues[a] == nil then
		return nil, "unknown clue " .. tostring(a)
	elseif board.defs.clues[b] == nil then
		return nil, "unknown clue " .. tostring(b)
	end
	if board.found[a] == nil then
		return nil, "clue " .. a .. " is not discovered"
	elseif board.found[b] == nil then
		return nil, "clue " .. b .. " is not discovered"
	end
	local l = board.defs.linkByPair[pairKey(a, b)]
	if l == nil then
		return nil, "no link between " .. a .. " and " .. b
	end
	return l, nil
end

-- The player draws a string between two discovered clues; only pairs the defs allow, and only manual
-- ones (an automatic link appears by itself). Returns ok, reason.
function EvidenceBoard.link(board: Board, a: string, b: string): (boolean, string?)
	local l, why = linkFor(board, a, b)
	if l == nil then
		return false, why
	end
	if l.auto then
		return false, "link " .. l.id .. " is automatic"
	end
	if board.links[l.id] ~= nil then
		return false, "already linked"
	end
	board.links[l.id] = true
	return true, nil
end

-- Removes a manual link. Returns ok, reason.
function EvidenceBoard.unlink(board: Board, a: string, b: string): (boolean, string?)
	local l, why = linkFor(board, a, b)
	if l == nil then
		return false, why
	end
	local manual = board.links[l.id]
	if manual == nil then
		return false, "not linked"
	elseif manual == false then
		return false, "link " .. l.id .. " is automatic"
	end
	board.links[l.id] = nil
	return true, nil
end

-- True when the pair is linked (manually or automatically).
function EvidenceBoard.isLinked(board: Board, a: string, b: string): boolean
	local l = board.defs.linkByPair[pairKey(a, b)]
	return l ~= nil and board.links[l.id] ~= nil
end

-- The manual links the player could draw now (both ends discovered, not yet drawn), in defs order.
function EvidenceBoard.available(board: Board): { LinkRow }
	local out: { LinkRow } = {}
	for _, l in board.defs.links do
		if not l.auto and board.links[l.id] == nil and board.found[l.a] and board.found[l.b] then
			table.insert(out, { id = l.id, a = l.a, b = l.b, kind = l.kind, auto = false })
		end
	end
	return out
end

-- Every drawn link (manual and automatic), in defs order.
function EvidenceBoard.links(board: Board): { LinkRow }
	local out: { LinkRow } = {}
	for _, l in board.defs.links do
		local manual = board.links[l.id]
		if manual ~= nil then
			table.insert(out, { id = l.id, a = l.a, b = l.b, kind = l.kind, auto = not manual })
		end
	end
	return out
end

-- The conclusions whose required clues and links are all present, in defs order.
function EvidenceBoard.conclusions(board: Board): { string }
	local out: { string } = {}
	for _, c in board.defs.conclusions do
		local ok = true
		for _, id in c.requires do
			if board.found[id] == nil and board.links[id] == nil then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, c.id)
		end
	end
	return out
end

-- One pin per discovered clue in discovery order; slot/col/row place it on the board deterministically.
function EvidenceBoard.pins(board: Board): { Pin }
	local out: { Pin } = {}
	local cols = EvidenceBoard.PinColumns
	for i, id in board.order do
		local c = board.defs.clues[id]
		local f = board.found[id]
		out[i] = {
			clueId = id,
			kind = c.kind,
			source = c.source,
			tags = table.clone(c.tags),
			dayN = f.dayN,
			timeOfDay = f.timeOfDay,
			zoneId = f.zoneId,
			slot = i,
			col = (i - 1) % cols + 1,
			row = (i - 1) // cols + 1,
		}
	end
	return out
end

-- Counts for a progress readout.
function EvidenceBoard.progress(board: Board): Progress
	local linked = 0
	for _ in board.links do
		linked += 1
	end
	return {
		discovered = #board.order,
		total = #board.defs.clueIds,
		linked = linked,
		totalLinks = #board.defs.links,
		conclusions = #EvidenceBoard.conclusions(board),
		totalConclusions = #board.defs.conclusions,
	}
end

-- ---------------------------------------------------------------- the random find
-- The clue that surfaces on a catch or a cast landing, or nil. Eligible clues share ctx.source, allow
-- ctx.zoneId (no zones = everywhere, weight 1), have a chance, are not on the board and have every
-- required clue on it (no board = nothing known: a clue with requires never surfaces). One rng draw
-- u in [0, 1): walking the SORTED ids, clue i is found when u falls
-- in its band of width chance * zoneWeight; past the last band nothing surfaces. So with bands adding
-- to at most 1 each clue's chance per event is exactly its chance * zone weight.
function EvidenceBoard.rollFind(defs: any, rng: any, ctx: FindCtx): string?
	local d = EvidenceBoard.compile(defs)
	if table.find(EvidenceBoard.SOURCES, ctx.source) == nil then
		error("EvidenceBoard.rollFind: ctx.source must be one of " .. table.concat(EvidenceBoard.SOURCES, "/"))
	end
	if not nonEmpty(ctx.zoneId) then
		error("EvidenceBoard.rollFind: ctx.zoneId must be a non-empty string")
	end
	local board = ctx.board
	local u = rng:NextNumber()
	local acc = 0
	for _, id in d.clueIds do
		local c = d.clues[id]
		if c.source == ctx.source and c.chance ~= nil and c.chance > 0 and (board == nil or board.found[id] == nil) then
			local w = if c.zones then c.zones[ctx.zoneId] or 0 else 1
			if w > 0 and (c.requires == nil or (board ~= nil and allFound(board, c.requires))) then
				acc += c.chance * w
				if u < acc then
					return id
				end
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- save form
export type SerializedFound = { id: string, dayN: number, timeOfDay: number, zoneId: string }
export type Serialized = { v: number, found: { SerializedFound }, links: { string } }

-- A plain JSON-safe table: discoveries in order, manual link ids (automatic links are recomputed).
function EvidenceBoard.serialize(board: Board): Serialized
	local found: { SerializedFound } = {}
	for i, id in board.order do
		local f = board.found[id]
		found[i] = { id = id, dayN = f.dayN, timeOfDay = f.timeOfDay, zoneId = f.zoneId }
	end
	local links: { string } = {}
	for _, l in board.defs.links do
		if board.links[l.id] == true then
			table.insert(links, l.id)
		end
	end
	return { v = EvidenceBoard.VERSION, found = found, links = links }
end

-- Rebuilds a board from its save form against the defs; every id and every when/where is checked,
-- so an unknown clue id (a changed defs file, a tampered save) errors instead of loading.
function EvidenceBoard.deserialize(tbl: any, defs: any): Board
	if typeof(tbl) ~= "table" or tbl.v ~= EvidenceBoard.VERSION or typeof(tbl.found) ~= "table" or typeof(tbl.links) ~= "table" then
		error("EvidenceBoard.deserialize: not a serialized board")
	end
	local board = EvidenceBoard.new(defs)
	for i = 1, #tbl.found do
		local f: any = tbl.found[i]
		local label = "EvidenceBoard.deserialize: found " .. tostring(typeof(f) == "table" and f.id or i)
		if typeof(f) ~= "table" or not nonEmpty(f.id) then
			error(label .. ": id must be a non-empty string")
		end
		if board.defs.clues[f.id] == nil then
			error(label .. ": unknown clue id")
		end
		if board.found[f.id] then
			error(label .. ": duplicate")
		end
		local problem = foundProblem(f)
		if problem then
			error(label .. ": " .. problem)
		end
		board.found[f.id] = { dayN = f.dayN, timeOfDay = f.timeOfDay, zoneId = f.zoneId }
		table.insert(board.order, f.id)
	end
	for i = 1, #tbl.links do
		local id = tbl.links[i]
		local label = "EvidenceBoard.deserialize: link " .. tostring(id)
		local l = if nonEmpty(id) then board.defs.linkById[id] else nil
		if l == nil then
			error(label .. ": unknown link id")
		end
		if l.auto then
			error(label .. ": is automatic, not a saved manual link")
		end
		if board.found[l.a] == nil or board.found[l.b] == nil then
			error(label .. ": an end is not discovered")
		end
		if board.links[l.id] ~= nil then
			error(label .. ": duplicate")
		end
		board.links[l.id] = true
	end
	refreshAuto(board)
	return board
end

-- ---------------------------------------------------------------- merge
-- A new board with every discovery of either (the earlier when/where wins), every manual link of
-- either, automatic links recomputed; order by discovery time. Commutative; inputs untouched.
function EvidenceBoard.merge(a: Board, b: Board): Board
	if a.defs ~= b.defs then
		error("EvidenceBoard.merge: boards come from different defs")
	end
	local out = EvidenceBoard.new(a.defs)
	for _, src in { a, b } do
		for id, f in src.found do
			local have = out.found[id]
			if have == nil or foundLess(f, have, id, id) then
				out.found[id] = { dayN = f.dayN, timeOfDay = f.timeOfDay, zoneId = f.zoneId }
			end
		end
	end
	for id in out.found do
		table.insert(out.order, id)
	end
	table.sort(out.order, function(x: string, y: string): boolean
		return foundLess(out.found[x], out.found[y], x, y)
	end)
	for _, src in { a, b } do
		for id, manual in src.links do
			if manual then
				out.links[id] = true
			end
		end
	end
	refreshAuto(out)
	return out
end

return EvidenceBoard
