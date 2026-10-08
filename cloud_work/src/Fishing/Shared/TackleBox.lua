--!strict
-- TackleBox (About Fishing F1, WS-T tackle box; Cloud, 2026-10-06; design/WST_tacklebox.md not yet written)
-- The Tetris-style tackle box from the reference: a W x H grid of 1-based cells holding polyomino items
-- (fish, lures, gear). Place / move / remove, first-fit auto placement, the "would it fit if I dropped
-- these" question, a JSON-safe save form that re-validates on load, and an invariant check for tests.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * FishingServer (on a catch): TackleBox.autoPlace(box, { kind = "fish", key = speciesId,
--     shape = TackleBox.SHAPES[shapeName], data = catchRecord }), shapeName from SpeciesTable.sizeClass.
--     nil + "no room" means the player must make room: canFitAfterRemoving(box, shape, ids) drives that.
--   * SaveData (the player's DataStore record): store TackleBox.serialize(box); rebuild with
--     TackleBox.deserialize(tbl) inside pcall, since a tampered save errors naming the item id.
--   * The client box UI sends (id, rot, x, y) move requests over FishingNet; the server answers with
--     TackleBox.move and replicates TackleBox.items(box).
-- Client-facing operations (place, move, remove, autoPlace) never error on a bad request: they return
-- nil/false plus a reason. Programmer errors (a malformed shape or item, a bad save) do error.
-- No Roblox globals; nothing here needs the engine.

local TackleBox = {}

export type Cell = { number } -- {dx, dy}
export type Shape = { Cell } -- polyomino cell offsets; the origin cell {0, 0} is included
export type Item = { kind: string, key: string, shape: Shape, data: { [string]: any }? }
export type Placed = { id: number, item: Item, rot: number, x: number, y: number }
-- grid maps cell key (y-1)*w + x -> item id
export type Box = { w: number, h: number, nextId: number, placed: { [number]: Placed }, grid: { [number]: number } }

TackleBox.DEFAULT_W = 8
TackleBox.DEFAULT_H = 6
TackleBox.MAX_DIM = 32 -- a save asking for a bigger grid is refused (keeps every scan bounded)
TackleBox.MAX_CELLS = 64 -- a shape with more cells than this is refused
TackleBox.MAX_ID = 2 ^ 31 -- a save with an id or nextId above this is refused (at 2^53, nextId + 1 == nextId: ids would repeat)

local KINDS: { [string]: boolean } = { fish = true, lure = true, gear = true }

-- Named shapes the species table references by name (origin {0,0} top-left, +dx right, +dy down).
TackleBox.SHAPES = {
	line1 = { { 0, 0 } },
	line2 = { { 0, 0 }, { 1, 0 } },
	line3 = { { 0, 0 }, { 1, 0 }, { 2, 0 } },
	line4 = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } },
	L3 = { { 0, 0 }, { 0, 1 }, { 1, 1 } },
	L4 = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 1, 2 } },
	rect2x2 = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } },
	rect2x3 = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0, 2 }, { 1, 2 } },
	T4 = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } },
	S4 = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } },
} :: { [string]: Shape }

-- ---------------------------------------------------------------- helpers
local function isInt(v: any): boolean
	return typeof(v) == "number" and v == math.floor(v) and math.abs(v) < math.huge
end

-- Checks a shape: non-empty array of integer {dx, dy} pairs, no duplicates, origin present.
local function shapeProblem(shape: any): string?
	if typeof(shape) ~= "table" or #shape == 0 or #shape > TackleBox.MAX_CELLS then
		return "bad shape"
	end
	local seen: { [string]: boolean } = {}
	for i = 1, #shape do
		local c = shape[i]
		if typeof(c) ~= "table" or not isInt(c[1]) or not isInt(c[2]) or seen[tostring(c[1]) .. "," .. tostring(c[2])] then
			return "bad shape"
		end
		seen[tostring(c[1]) .. "," .. tostring(c[2])] = true
	end
	return if seen["0,0"] then nil else "bad shape"
end

local function validRot(rot: any): boolean
	return isInt(rot) and rot >= 0 and rot <= 3
end

local function cellKey(box: Box, x: number, y: number): number
	return (y - 1) * box.w + x
end

local function copyShape(shape: Shape): Shape
	local out: Shape = {}
	for i, c in shape do
		out[i] = { c[1], c[2] }
	end
	return out
end

-- Rotated, normalised, row-major sorted cells; errors on a malformed shape or rotation.
function TackleBox.shapeCells(shape: Shape, rot: number): { Cell }
	local problem = shapeProblem(shape)
	if problem then
		error("TackleBox.shapeCells: " .. problem)
	end
	if not validRot(rot) then
		error("TackleBox.shapeCells: bad rotation " .. tostring(rot))
	end
	local out: { Cell } = {}
	local minX, minY = math.huge, math.huge
	for i, c in shape do
		local dx, dy = c[1], c[2]
		for _ = 1, rot do
			dx, dy = -dy, dx -- 90 degrees clockwise on a y-down grid
		end
		out[i] = { dx, dy }
		minX = math.min(minX, dx)
		minY = math.min(minY, dy)
	end
	for _, c in out do
		c[1] -= minX
		c[2] -= minY
	end
	table.sort(out, function(a: Cell, b: Cell): boolean
		return if a[2] == b[2] then a[1] < b[1] else a[2] < b[2]
	end)
	return out
end

-- Width and height of the shape's bounding box at that rotation.
function TackleBox.shapeSize(shape: Shape, rot: number): (number, number)
	local w, h = 0, 0
	for _, c in TackleBox.shapeCells(shape, rot) do
		w = math.max(w, c[1] + 1)
		h = math.max(h, c[2] + 1)
	end
	return w, h
end

-- Bounds and overlap test for already-rotated cells; ids in `ignore` do not block.
local function fits(box: Box, cells: { Cell }, x: number, y: number, ignore: { [number]: boolean }?): (boolean, string?)
	if not isInt(x) or not isInt(y) then
		return false, "bad position"
	end
	for _, c in cells do
		local cx, cy = x + c[1], y + c[2]
		if cx < 1 or cy < 1 or cx > box.w or cy > box.h then
			return false, "out of bounds"
		end
	end
	for _, c in cells do
		local id = box.grid[cellKey(box, x + c[1], y + c[2])]
		if id ~= nil and not (ignore ~= nil and ignore[id]) then
			return false, "overlap"
		end
	end
	return true, nil
end

-- First fit scanning rotations 0..3, then rows, then columns; ids in `ignore` do not block.
local function scan(box: Box, shape: Shape, ignore: { [number]: boolean }?): (number?, number?, number?)
	for rot = 0, 3 do
		local cells = TackleBox.shapeCells(shape, rot)
		local sw, sh = TackleBox.shapeSize(shape, rot)
		for y = 1, box.h - sh + 1 do
			for x = 1, box.w - sw + 1 do
				if fits(box, cells, x, y, ignore) then
					return rot, x, y
				end
			end
		end
	end
	return nil, nil, nil
end

local function writeCells(box: Box, p: Placed, id: number?)
	for _, c in TackleBox.shapeCells(p.item.shape, p.rot) do
		box.grid[cellKey(box, p.x + c[1], p.y + c[2])] = id
	end
end

-- ---------------------------------------------------------------- the box
-- A new empty box; w and h default to 8 x 6 and must be integers in 1..MAX_DIM.
function TackleBox.new(w: number?, h: number?): Box
	local bw = w or TackleBox.DEFAULT_W
	local bh = h or TackleBox.DEFAULT_H
	if not isInt(bw) or not isInt(bh) or bw < 1 or bh < 1 or bw > TackleBox.MAX_DIM or bh > TackleBox.MAX_DIM then
		error(string.format("TackleBox.new: bad size %s x %s", tostring(w), tostring(h)))
	end
	return { w = bw, h = bh, nextId = 1, placed = {}, grid = {} }
end

-- Could a shape at this rotation sit with its origin cell at (x, y)? Returns ok, reason.
function TackleBox.canPlace(box: Box, shape: Shape, rot: number, x: number, y: number): (boolean, string?)
	if not validRot(rot) then
		return false, "bad rotation"
	end
	return fits(box, TackleBox.shapeCells(shape, rot), x, y, nil)
end

-- Places an item; returns its id, or nil plus a reason. Errors on a malformed item.
function TackleBox.place(box: Box, item: Item, rot: number, x: number, y: number): (number?, string?)
	if typeof(item) ~= "table" or not KINDS[item.kind] or typeof(item.key) ~= "string" or (item.data ~= nil and typeof(item.data) ~= "table") then
		error("TackleBox.place: bad item (kind must be fish|lure|gear, key a string, data a table or nil)")
	end
	local problem = shapeProblem(item.shape)
	if problem then
		error("TackleBox.place: " .. problem .. " for item " .. item.key)
	end
	local ok, why = TackleBox.canPlace(box, item.shape, rot, x, y)
	if not ok then
		return nil, why
	end
	local id = box.nextId
	box.nextId += 1
	local p: Placed = {
		id = id,
		item = { kind = item.kind, key = item.key, shape = copyShape(item.shape), data = item.data },
		rot = rot,
		x = x,
		y = y,
	}
	box.placed[id] = p
	writeCells(box, p, id)
	return id, nil
end

-- Removes an item and frees its cells; returns the item, or nil plus a reason for an unknown id.
function TackleBox.remove(box: Box, id: number): (Item?, string?)
	local p = box.placed[id]
	if not p then
		return nil, "no item"
	end
	writeCells(box, p, nil)
	box.placed[id] = nil
	return p.item, nil
end

-- Moves or rotates an item in place; its own cells never block it. Returns ok, reason.
function TackleBox.move(box: Box, id: number, rot: number, x: number, y: number): (boolean, string?)
	local p = box.placed[id]
	if not p then
		return false, "no item"
	end
	if not validRot(rot) then
		return false, "bad rotation"
	end
	local cells = TackleBox.shapeCells(p.item.shape, rot)
	local ok, why = fits(box, cells, x, y, { [id] = true })
	if not ok then
		return false, why
	end
	writeCells(box, p, nil)
	p.rot, p.x, p.y = rot, x, y
	writeCells(box, p, id)
	return true, nil
end

-- First free fit for a shape: rot, x, y (rotations 0..3, then rows, then columns), or nil.
function TackleBox.findFit(box: Box, shape: Shape): (number?, number?, number?)
	return scan(box, shape, nil)
end

-- Places an item at its first fit; returns the id, or nil, "no room".
function TackleBox.autoPlace(box: Box, item: Item): (number?, string?)
	local rot, x, y = TackleBox.findFit(box, item.shape)
	if rot == nil or x == nil or y == nil then
		return nil, "no room"
	end
	return TackleBox.place(box, item, rot, x, y)
end

-- The id occupying cell (x, y), or nil when empty or out of bounds.
function TackleBox.at(box: Box, x: number, y: number): number?
	if not isInt(x) or not isInt(y) or x < 1 or y < 1 or x > box.w or y > box.h then
		return nil
	end
	return box.grid[cellKey(box, x, y)]
end

-- Every placed item as {id, item, rot, x, y}, ordered by id. Each entry is a copy (the shape by value,
-- `data` by reference): a caller mutating what it got back cannot break the grid invariant.
function TackleBox.items(box: Box): { Placed }
	local out: { Placed } = {}
	for _, p in box.placed do
		local item: Item = { kind = p.item.kind, key = p.item.key, shape = copyShape(p.item.shape), data = p.item.data }
		table.insert(out, { id = p.id, item = item, rot = p.rot, x = p.x, y = p.y })
	end
	table.sort(out, function(a: Placed, b: Placed): boolean return a.id < b.id end)
	return out
end

-- Number of unoccupied cells.
function TackleBox.freeCells(box: Box): number
	local used = 0
	for _ in box.grid do
		used += 1
	end
	return box.w * box.h - used
end

-- True when no item is placed.
function TackleBox.isEmpty(box: Box): boolean
	return next(box.placed) == nil
end

-- The "make room" question: would the shape fit anywhere if these items were taken out?
function TackleBox.canFitAfterRemoving(box: Box, shape: Shape, idsToRemove: { number }): boolean
	local ignore: { [number]: boolean } = {}
	for _, id in idsToRemove do
		if not box.placed[id] then
			error("TackleBox.canFitAfterRemoving: no item " .. tostring(id))
		end
		ignore[id] = true
	end
	local rot = scan(box, shape, ignore)
	return rot ~= nil
end

-- ---------------------------------------------------------------- save form
export type SerializedItem = { id: number, kind: string, key: string, shape: Shape, rot: number, x: number, y: number, data: { [string]: any }? }
export type Serialized = { w: number, h: number, nextId: number, items: { SerializedItem } }

-- A plain JSON-safe table of the whole box (items ordered by id; shapes copied, `data` by reference,
-- so encode it, do not edit it).
function TackleBox.serialize(box: Box): Serialized
	local items: { SerializedItem } = {}
	for _, p in TackleBox.items(box) do
		table.insert(items, {
			id = p.id,
			kind = p.item.kind,
			key = p.item.key,
			shape = copyShape(p.item.shape),
			rot = p.rot,
			x = p.x,
			y = p.y,
			data = p.item.data,
		})
	end
	return { w = box.w, h = box.h, nextId = box.nextId, items = items }
end

-- Rebuilds a box from its save form, re-checking every item; errors name the offending item id.
function TackleBox.deserialize(tbl: any): Box
	if typeof(tbl) ~= "table" or typeof(tbl.items) ~= "table" then
		error("TackleBox.deserialize: not a serialized box")
	end
	local box = TackleBox.new(tbl.w, tbl.h)
	local maxId = 0
	local list: { any } = tbl.items
	for i = 1, #list do
		-- the record is untrusted save data: read it through `any` and check every field
		local s: any = typeof(list[i]) == "table" and list[i] or {}
		local label = "TackleBox.deserialize: item " .. tostring(s.id ~= nil and s.id or i)
		local problem: string? = if not isInt(s.id) or s.id < 1 or s.id > TackleBox.MAX_ID then "bad id"
			elseif box.placed[s.id] then "duplicate id"
			elseif not KINDS[s.kind] or typeof(s.key) ~= "string" then "bad kind or key"
			elseif not validRot(s.rot) then "bad rotation"
			elseif s.data ~= nil and typeof(s.data) ~= "table" then "bad data"
			else shapeProblem(s.shape)
		if problem == nil then
			local _, why = fits(box, TackleBox.shapeCells(s.shape, s.rot), s.x, s.y, nil)
			problem = why
		end
		if problem then
			error(label .. ": " .. problem)
		end
		local p: Placed = {
			id = s.id,
			item = { kind = s.kind, key = s.key, shape = copyShape(s.shape), data = s.data },
			rot = s.rot,
			x = s.x,
			y = s.y,
		}
		box.placed[s.id] = p
		writeCells(box, p, s.id)
		maxId = math.max(maxId, s.id)
	end
	local nextId = isInt(tbl.nextId) and tbl.nextId or 0
	if nextId > TackleBox.MAX_ID then
		error("TackleBox.deserialize: bad nextId " .. tostring(tbl.nextId))
	end
	box.nextId = math.max(nextId, maxId + 1)
	return box
end

-- Invariant check for tests: every item in bounds, no shared cells, grid matches items. True or error.
function TackleBox.check(box: Box): boolean
	local fresh: { [number]: number } = {}
	for id, p in box.placed do
		if p.id ~= id or id >= box.nextId then
			error(string.format("TackleBox.check: item %d has a bad id (key %d, nextId %d)", p.id, id, box.nextId))
		end
		for _, c in TackleBox.shapeCells(p.item.shape, p.rot) do
			local cx, cy = p.x + c[1], p.y + c[2]
			if cx < 1 or cy < 1 or cx > box.w or cy > box.h then
				error(string.format("TackleBox.check: item %d out of bounds at (%d, %d)", id, cx, cy))
			end
			local k = cellKey(box, cx, cy)
			if fresh[k] ~= nil then
				error(string.format("TackleBox.check: items %d and %d share cell (%d, %d)", fresh[k], id, cx, cy))
			end
			fresh[k] = id
		end
	end
	for k, id in fresh do
		if box.grid[k] ~= id then
			error(string.format("TackleBox.check: grid cell %d holds %s, items say %d", k, tostring(box.grid[k]), id))
		end
	end
	for k, id in box.grid do
		if fresh[k] ~= id then
			error(string.format("TackleBox.check: grid cell %d holds stray id %d", k, id))
		end
	end
	return true
end

return TackleBox
