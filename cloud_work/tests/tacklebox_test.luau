--!strict
-- tacklebox_test (About Fishing F1 cloud work; Cloud, 2026-10-06)
-- Proves TackleBox: rotation normalisation (all four L4 rotations written out), bounds, overlap,
-- remove frees cells, move onto own cells, first-fit scan order, autoPlace filling an 8x6 box,
-- canFitAfterRemoving, a serialize round trip through real JSON, deserialize refusing a tampered
-- save (negative controls), and a 500-operation seeded fuzz against TackleBox.check.
-- Run from this folder: luau tacklebox_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("tacklebox_test")
local TackleBox = require("../src/Fishing/Shared/TackleBox")

type Cell = TackleBox.Cell
type Item = TackleBox.Item

-- a small seeded LCG with Roblox's Random shape (Park-Miller minimal standard)
local function lcg(seed: number)
	local s = seed % 2147483647
	if s == 0 then
		s = 1
	end
	local R = {}
	function R.NextNumber(_self: any, a: number?, b: number?): number
		s = (s * 48271) % 2147483647
		local u = s / 2147483647
		if a ~= nil and b ~= nil then
			return a + u * (b - a)
		end
		return u
	end
	function R.NextInteger(self: any, a: number, b: number): number
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	return R
end

local function cellsStr(cells: { Cell }): string
	local parts = {}
	for i, c in cells do
		parts[i] = c[1] .. "," .. c[2]
	end
	return table.concat(parts, " ")
end

local function item(kind: string, key: string, shapeName: string, data: { [string]: any }?): Item
	return { kind = kind, key = key, shape = TackleBox.SHAPES[shapeName], data = data }
end

-- rotation normalisation: L4 = (0,0) (0,1) (0,2) (1,2), rotated clockwise on a y-down grid
local L4 = TackleBox.SHAPES.L4
T.eq(cellsStr(TackleBox.shapeCells(L4, 0)), "0,0 0,1 0,2 1,2", "L4 rot 0 cells")
T.eq(cellsStr(TackleBox.shapeCells(L4, 1)), "0,0 1,0 2,0 0,1", "L4 rot 1 cells")
T.eq(cellsStr(TackleBox.shapeCells(L4, 2)), "0,0 1,0 1,1 1,2", "L4 rot 2 cells")
T.eq(cellsStr(TackleBox.shapeCells(L4, 3)), "2,0 0,1 1,1 2,1", "L4 rot 3 cells")
local sw, sh = TackleBox.shapeSize(L4, 0)
T.check(sw == 2 and sh == 3, "L4 rot 0 is 2 wide 3 tall")
sw, sh = TackleBox.shapeSize(L4, 1)
T.check(sw == 3 and sh == 2, "L4 rot 1 is 3 wide 2 tall")
T.eq(cellsStr(TackleBox.shapeCells({ { 2, 1 }, { 0, 0 } }, 0)), "0,0 2,1", "cells are sorted row-major")
T.throws(function() TackleBox.shapeCells(L4, 4) end, "bad rotation", "rotation 4 is refused")
T.throws(function() TackleBox.shapeCells({ { 1, 0 } }, 0) end, "bad shape", "a shape without its origin cell is refused")
T.throws(function() TackleBox.shapeCells({ { 0, 0 }, { 0, 0 } }, 0) end, "bad shape", "duplicate cells are refused")

-- every named shape is valid at every rotation
local shapeCount, shapeOk = 0, true
for name, shape in TackleBox.SHAPES do
	shapeCount += 1
	for rot = 0, 3 do
		local ok = pcall(TackleBox.shapeCells, shape, rot)
		shapeOk = shapeOk and ok
	end
end
T.check(shapeCount == 10 and shapeOk, "all 10 named shapes rotate cleanly")
T.eq(#TackleBox.SHAPES.T4 + #TackleBox.SHAPES.S4 + #TackleBox.SHAPES.rect2x3, 14, "T4, S4, rect2x3 cell counts")

-- a fresh box
local box = TackleBox.new()
T.check(box.w == 8 and box.h == 6 and TackleBox.freeCells(box) == 48 and TackleBox.isEmpty(box), "new() is an empty 8x6 box with 48 free cells")
T.throws(function() TackleBox.new(0, 6) end, "bad size", "new refuses a zero width")

-- bounds and overlap
T.check(TackleBox.canPlace(box, TackleBox.SHAPES.line2, 0, 7, 1) == true, "line2 at x=7 fits")
local ok, why = TackleBox.canPlace(box, TackleBox.SHAPES.line2, 0, 8, 1)
T.check(ok == false and why == "out of bounds", "line2 at x=8 is out of bounds")
ok, why = TackleBox.canPlace(box, TackleBox.SHAPES.line2, 5, 1, 1)
T.check(ok == false and why == "bad rotation", "canPlace with rotation 5 says bad rotation")
ok, why = TackleBox.canPlace(box, TackleBox.SHAPES.line2, 0, 1.5, 1)
T.check(ok == false and why == "bad position", "canPlace with a fractional x says bad position")

local idA = TackleBox.place(box, item("fish", "trout", "line3"), 0, 1, 1)
T.eq(idA, 1, "first placed item gets id 1")
T.eq(TackleBox.at(box, 3, 1), 1, "at() sees the item on its third cell")
T.eq(TackleBox.at(box, 4, 1), nil, "at() is nil on an empty cell")
T.eq(TackleBox.at(box, 9, 1), nil, "at() is nil out of bounds")
ok, why = TackleBox.canPlace(box, TackleBox.SHAPES.line1, 0, 2, 1)
T.check(ok == false and why == "overlap", "canPlace over the item says overlap")
local idNil, whyNil = TackleBox.place(box, item("lure", "worm", "line1"), 0, 2, 1)
T.check(idNil == nil and whyNil == "overlap", "place over the item returns nil, overlap")
T.eq(TackleBox.freeCells(box), 45, "three cells used")
T.throws(function() TackleBox.place(box, { kind = "hat", key = "x", shape = L4 } :: any, 0, 1, 1) end, "bad item", "place refuses an unknown kind")

-- remove frees cells
local removed = TackleBox.remove(box, 1)
T.check(removed ~= nil and removed.key == "trout", "remove returns the item")
T.check(TackleBox.freeCells(box) == 48 and TackleBox.at(box, 1, 1) == nil, "remove frees the cells")
local gone, goneWhy = TackleBox.remove(box, 1)
T.check(gone == nil and goneWhy == "no item", "removing again says no item")
T.eq(TackleBox.place(box, item("lure", "worm", "line1"), 0, 2, 1), 2, "ids keep increasing after a remove")
TackleBox.remove(box, 2)

-- move: own cells never block, other items do
local idB = TackleBox.place(box, item("fish", "trout", "line3"), 0, 1, 1) :: number
local idC = TackleBox.place(box, item("gear", "hook_basic", "line1"), 0, 5, 1) :: number
T.check(TackleBox.move(box, idB, 0, 2, 1) == true, "move one cell right over own cells is ok")
T.check(TackleBox.at(box, 1, 1) == nil and TackleBox.at(box, 4, 1) == idB, "after the move the old cell is free and the new one taken")
ok, why = TackleBox.move(box, idB, 0, 3, 1)
T.check(ok == false and why == "overlap", "move onto another item is rejected")
T.check(TackleBox.at(box, 2, 1) == idB and TackleBox.at(box, 5, 1) == idC, "a rejected move changes nothing")
ok, why = TackleBox.move(box, idB, 1, 2, 5)
T.check(ok == false and why == "out of bounds", "move that rotates off the bottom is rejected")
T.check(TackleBox.move(box, idB, 1, 1, 2) == true, "move with rotation 1 to (1,2) is ok")
T.check(TackleBox.at(box, 1, 4) == idB and TackleBox.at(box, 2, 1) == nil, "rotated line3 now runs down column 1")
ok, why = TackleBox.move(box, 999, 0, 1, 1)
T.check(ok == false and why == "no item", "move of an unknown id says no item")
T.check(TackleBox.check(box), "invariant holds after the moves")

-- findFit scan order
local empty = TackleBox.new()
local r, fx, fy = TackleBox.findFit(empty, L4)
T.check(r == 0 and fx == 1 and fy == 1, "findFit on an empty box is rot 0 at (1,1)")
TackleBox.place(empty, item("lure", "worm", "line1"), 0, 1, 1)
r, fx, fy = TackleBox.findFit(empty, L4)
T.check(r == 0 and fx == 2 and fy == 1, "findFit skips to x=2 when (1,1) is taken (columns before rows)")
local short = TackleBox.new(3, 2)
r, fx, fy = TackleBox.findFit(short, L4)
T.check(r == 1 and fx == 1 and fy == 1, "findFit tries rot 1 when rot 0 cannot fit anywhere")
local tiny = TackleBox.new(1, 1)
r = TackleBox.findFit(tiny, TackleBox.SHAPES.line2)
T.eq(r, nil, "findFit is nil when nothing fits")

-- autoPlace fills 8x6 with 48 line1 items, then says no room
local full = TackleBox.new()
local placed = 0
for i = 1, 48 do
	local id = TackleBox.autoPlace(full, item("lure", "lure" .. i, "line1"))
	if id == i then
		placed += 1
	end
end
T.eq(placed, 48, "autoPlace placed 48 line1 items with ids 1..48")
T.eq(TackleBox.freeCells(full), 0, "the box is full")
local noId, noWhy = TackleBox.autoPlace(full, item("lure", "lure49", "line1"))
T.check(noId == nil and noWhy == "no room", "the 49th autoPlace returns nil, no room")
T.check(TackleBox.check(full), "invariant holds on the full box")
local list = TackleBox.items(full)
T.check(#list == 48 and list[1].id == 1 and list[48].id == 48 and list[9].x == 1 and list[9].y == 2, "items() lists 48 by id; item 9 starts row 2")

-- canFitAfterRemoving
local corner = { TackleBox.at(full, 1, 1) :: number, TackleBox.at(full, 2, 1) :: number, TackleBox.at(full, 1, 2) :: number, TackleBox.at(full, 2, 2) :: number }
T.check(TackleBox.canFitAfterRemoving(full, TackleBox.SHAPES.rect2x2, corner), "rect2x2 fits once the four corner items go")
T.check(not TackleBox.canFitAfterRemoving(full, TackleBox.SHAPES.rect2x2, { corner[1], corner[2], corner[3] }), "rect2x2 does not fit with only three removed")
T.check(not TackleBox.canFitAfterRemoving(full, TackleBox.SHAPES.line1, {}), "nothing fits a full box with nothing removed")
T.check(TackleBox.freeCells(full) == 0 and #TackleBox.items(full) == 48, "canFitAfterRemoving removed nothing")
T.throws(function() TackleBox.canFitAfterRemoving(full, L4, { 999 }) end, "no item 999", "canFitAfterRemoving names an unknown id")

-- serialize round trip through real JSON, equal cell for cell
local src = TackleBox.new()
TackleBox.place(src, item("fish", "trout", "L4", { lengthM = 0.41 }), 0, 1, 1)
TackleBox.place(src, item("fish", "pike", "line4", { lengthM = 0.9 }), 1, 8, 1)
TackleBox.place(src, item("lure", "spinner", "T4"), 2, 3, 2)
TackleBox.place(src, item("gear", "hook_sharp", "S4"), 3, 5, 4)
TackleBox.remove(src, 3)
local wire = Stub.jsonEncode(TackleBox.serialize(src))
local back = TackleBox.deserialize(Stub.jsonDecode(wire))
local sameCells = true
for y = 1, 6 do
	for x = 1, 8 do
		sameCells = sameCells and TackleBox.at(src, x, y) == TackleBox.at(back, x, y)
	end
end
T.check(sameCells, "deserialize(serialize()) matches cell for cell")
T.check(back.nextId == src.nextId and #TackleBox.items(back) == 3, "round trip keeps nextId and the item count after a remove")
T.eq(Stub.jsonEncode(TackleBox.serialize(back)), wire, "serialize is stable across a round trip")
local backItems = TackleBox.items(back)
T.check(backItems[1].item.data ~= nil and (backItems[1].item.data :: any).lengthM == 0.41 and backItems[3].rot == 3, "item data and rotation survive the round trip")
T.check(TackleBox.check(back), "invariant holds on the rebuilt box")
T.eq(TackleBox.place(back, item("lure", "fly", "line1"), 0, 1, 6), 5, "the rebuilt box hands out the next id")

-- deserialize refuses a tampered save (negative controls)
local tampered = Stub.jsonDecode(wire)
tampered.items[2].x = 1
tampered.items[2].y = 1
T.throws(function() TackleBox.deserialize(tampered) end, "item 2: overlap", "deserialize rejects an overlap naming the item")
tampered = Stub.jsonDecode(wire)
tampered.items[1].y = 5
T.throws(function() TackleBox.deserialize(tampered) end, "item 1: out of bounds", "deserialize rejects an out-of-bounds cell naming the item")
tampered = Stub.jsonDecode(wire)
tampered.items[2].id = 1
T.throws(function() TackleBox.deserialize(tampered) end, "duplicate id", "deserialize rejects a duplicate id")
tampered = Stub.jsonDecode(wire)
tampered.items[1].kind = "hat"
T.throws(function() TackleBox.deserialize(tampered) end, "bad kind", "deserialize rejects an unknown kind")
tampered = Stub.jsonDecode(wire)
tampered.w = 1000
T.throws(function() TackleBox.deserialize(tampered) end, "bad size", "deserialize rejects an oversized grid")
T.throws(function() TackleBox.deserialize("nope") end, "not a serialized box", "deserialize rejects a non-table")

-- check() itself can fail: corrupt the grid by hand
local corrupt = TackleBox.new()
TackleBox.place(corrupt, item("lure", "worm", "line1"), 0, 1, 1)
corrupt.grid[2] = 999
T.throws(function() TackleBox.check(corrupt) end, "stray id 999", "negative control: check() reports a stray grid cell")

-- seeded fuzz: 500 random place / remove / move operations never break the invariant
local rng = lcg(20261006)
local names = {}
for name in TackleBox.SHAPES do
	table.insert(names, name)
end
table.sort(names)
local fuzz = TackleBox.new()
local ids: { number } = {}
local placesOk, movesOk, removesOk, invariantOk = 0, 0, 0, true
for step = 1, 500 do
	local op = rng:NextInteger(1, 3)
	if op == 1 or #ids == 0 then
		local shapeName = names[rng:NextInteger(1, #names)]
		local id = TackleBox.place(fuzz, item("fish", shapeName, shapeName), rng:NextInteger(0, 3), rng:NextInteger(1, 8), rng:NextInteger(1, 6))
		if id then
			placesOk += 1
			table.insert(ids, id)
		end
	elseif op == 2 then
		local i = rng:NextInteger(1, #ids)
		if TackleBox.remove(fuzz, ids[i]) then
			removesOk += 1
		end
		table.remove(ids, i)
	else
		local id = ids[rng:NextInteger(1, #ids)]
		if TackleBox.move(fuzz, id, rng:NextInteger(0, 3), rng:NextInteger(1, 8), rng:NextInteger(1, 6)) then
			movesOk += 1
		end
	end
	local okStep = pcall(TackleBox.check, fuzz)
	invariantOk = invariantOk and okStep
end
T.check(invariantOk, "fuzz: 500 operations never left two items on one cell")
T.check(placesOk >= 50 and movesOk >= 20 and removesOk >= 20, string.format("fuzz exercised the box (%d places, %d moves, %d removes ok)", placesOk, movesOk, removesOk))
local fuzzCells = 0
for _, p in TackleBox.items(fuzz) do
	fuzzCells += #p.item.shape
end
T.eq(TackleBox.freeCells(fuzz), 48 - fuzzCells, "fuzz: free cells agree with the items' cell counts")
T.eq(Stub.jsonEncode(TackleBox.serialize(TackleBox.deserialize(TackleBox.serialize(fuzz)))), Stub.jsonEncode(TackleBox.serialize(fuzz)), "fuzz: the final box round-trips")

T.finish()
