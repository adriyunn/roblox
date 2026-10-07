--!strict
-- tackleboxui_test (About Fishing F1 cloud work; Cloud, 2026-10-07)
-- Proves TackleBoxUI against a local TackleBox: the layout maths at cellPx 32, gap 2, origin (10, 20)
-- with the pixel rectangles written out; hitTest on a cell, in a gap (nil) and outside; a full drag
-- (down on an item, three cells right, up) producing the move action and the canPlace callback's
-- arguments; an illegal drop (overlap, off-grid) returning nil with the item unmoved; rotate mid-drag
-- keeping the grabbed cell under the pointer through all four rotations; cancel; the tap -> menu
-- state; the clamped cursor; cursorSelect twice = a move; a refused cursor drop; setItems guards and
-- negative controls (cols 0, cellPx 0, a fractional cell).
-- Run from this folder: luau tackleboxui_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("tackleboxui_test")
local TackleBox = require("../src/Fishing/Shared/TackleBox")
local TackleBoxUI = require("../src/Fishing/Client/TackleBoxUI")

type Rect = TackleBoxUI.Rect

local function rectStr(r: Rect?): string
	if r == nil then
		return "nil"
	end
	return string.format("{%d, %d, %d, %d}", r.x, r.y, r.w, r.h)
end

local function rectIs(r: Rect?, x: number, y: number, w: number, h: number, label: string)
	local same = r ~= nil and r.x == x and r.y == y and r.w == w and r.h == h
	T.check(same, label .. (same and "" or string.format("  (got %s, want {%d, %d, %d, %d})", rectStr(r), x, y, w, h)))
end

local function contains(r: Rect, px: number, py: number): boolean
	return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

-- the cell a pixel pair lands in, read back through the preview: the rect among the ghost cells that
-- contains the pointer, or nil
local function previewCellUnder(pv: TackleBoxUI.Preview?, px: number, py: number): Rect?
	if pv == nil then
		return nil
	end
	for _, r in pv.cells do
		if contains(r, px, py) then
			return r
		end
	end
	return nil
end

-- centre pixel of cell (cx, cy) for the standard layout: origin (10, 20), pitch 34
local function centre(cx: number, cy: number): (number, number)
	return 10 + (cx - 1) * 34 + 16, 20 + (cy - 1) * 34 + 16
end

-- ---------------------------------------------------------------- a box with three items
-- A: line2 fish at (2,2) -> cells (2,2) (3,2)      id 1
-- B: L3 gear at (3,3)    -> cells (3,3) (3,4) (4,4) id 2
-- C: line1 lure at (7,5) -> cell (7,5)             id 3
local function sampleBox(): TackleBox.Box
	local box = TackleBox.new(8, 6)
	assert(TackleBox.place(box, { kind = "fish", key = "trout", shape = TackleBox.SHAPES.line2 }, 0, 2, 2))
	assert(TackleBox.place(box, { kind = "gear", key = "hook", shape = TackleBox.SHAPES.L3 }, 0, 3, 3))
	assert(TackleBox.place(box, { kind = "lure", key = "spinner", shape = TackleBox.SHAPES.line1 }, 0, 7, 5))
	return box
end

local calls: { { number } } = {}
local box = sampleBox()
local ui = TackleBoxUI.new({
	cols = 8,
	rows = 6,
	cellPx = 32,
	gapPx = 2,
	originPx = { x = 10, y = 20 },
	canPlace = function(id: number, rot: number, x: number, y: number): boolean
		table.insert(calls, { id, rot, x, y })
		-- the server's test (TackleBox.move without mutating): bounds, own cells ignored
		local p = box.placed[id]
		for _, c in TackleBox.shapeCells(p.item.shape, rot) do
			local other = TackleBox.at(box, x + c[1], y + c[2])
			if x + c[1] < 1 or y + c[2] < 1 or x + c[1] > box.w or y + c[2] > box.h or (other ~= nil and other ~= id) then
				return false
			end
		end
		return true
	end,
})
TackleBoxUI.setItems(ui, TackleBox.items(box))

-- ---------------------------------------------------------------- layout maths
rectIs(TackleBoxUI.cellRect(ui, 1, 1), 10, 20, 32, 32, "cellRect(1,1) = {10, 20, 32, 32}")
rectIs(TackleBoxUI.cellRect(ui, 2, 1), 44, 20, 32, 32, "cellRect(2,1) = {44, 20, 32, 32}: pitch is cellPx + gapPx = 34")
rectIs(TackleBoxUI.cellRect(ui, 1, 2), 10, 54, 32, 32, "cellRect(1,2) = {10, 54, 32, 32}")
rectIs(TackleBoxUI.cellRect(ui, 8, 6), 248, 190, 32, 32, "cellRect(8,6) = {248, 190, 32, 32}")
rectIs(TackleBoxUI.cellRect(ui, 0, 0), -24, -14, 32, 32, "cellRect accepts an off-grid cell (the ghost can hang off the grid)")
local layout = TackleBoxUI.layout(ui)
rectIs(layout.gridRect, 10, 20, 270, 202, "gridRect = {10, 20, 8*32+7*2, 6*32+5*2}")
T.eq(#layout.cellRects, 48, "layout has one rect per cell")
rectIs(layout.cellRects[1], 10, 20, 32, 32, "cellRects[1] is (1,1)")
rectIs(layout.cellRects[9], 10, 54, 32, 32, "cellRects[9] is (1,2): row-major")
rectIs(layout.cellRects[48], 248, 190, 32, 32, "cellRects[48] is (8,6)")
local items = TackleBoxUI.items(ui)
rectIs(TackleBoxUI.itemRect(ui, items[1]), 44, 54, 66, 32, "itemRect of line2 at (2,2) = {44, 54, 2*32+2, 32}")
rectIs(TackleBoxUI.itemRect(ui, items[2]), 78, 88, 66, 66, "itemRect of L3 at (3,3) is its 2x2 bounding box")
local cellsA = TackleBoxUI.itemCells(ui, items[1])
T.eq(#cellsA, 2, "itemCells of line2 has two rects")
rectIs(cellsA[2], 78, 54, 32, 32, "itemCells[2] of line2 at (2,2) is cell (3,2)")
local cellsB = TackleBoxUI.itemCells(ui, items[2])
rectIs(cellsB[3], 112, 122, 32, 32, "itemCells[3] of L3 at (3,3) is cell (4,4)")
local fractional = TackleBoxUI.new({ cols = 2, rows = 2, cellPx = 32, gapPx = 2, originPx = { x = 10.7, y = 20.2 } })
rectIs(TackleBoxUI.cellRect(fractional, 1, 1), 10, 20, 32, 32, "a fractional origin is floored to whole pixels")

-- ---------------------------------------------------------------- hitTest
local id, cx, cy = TackleBoxUI.hitTest(ui, centre(2, 2))
T.check(id == 1 and cx == 2 and cy == 2, "hitTest on item A's cell -> id 1, (2,2)")
id, cx, cy = TackleBoxUI.hitTest(ui, 10, 20)
T.check(id == nil and cx == 1 and cy == 1, "hitTest on an empty cell -> nil id, (1,1)")
id, cx, cy = TackleBoxUI.hitTest(ui, 41, 20)
T.check(cx == 1 and cy == 1, "hitTest on the last pixel of cell 1 (x=41) is still cell 1")
id, cx, cy = TackleBoxUI.hitTest(ui, 42, 20)
T.check(id == nil and cx == nil and cy == nil, "hitTest in the gap (x=42) returns nil")
id, cx, cy = TackleBoxUI.hitTest(ui, 43, 25)
T.check(cx == nil, "hitTest in the gap (x=43) returns nil")
id, cx, cy = TackleBoxUI.hitTest(ui, 44, 20)
T.check(cx == 2 and cy == 1, "hitTest on the first pixel of cell 2 (x=44) is cell 2")
id, cx, cy = TackleBoxUI.hitTest(ui, 9, 20)
T.check(cx == nil, "hitTest left of the grid returns nil")
id, cx, cy = TackleBoxUI.hitTest(ui, 10, 19)
T.check(cy == nil, "hitTest above the grid returns nil")
id, cx, cy = TackleBoxUI.hitTest(ui, 280, 100)
T.check(cx == nil, "hitTest at the grid's right edge (x=280, exclusive) returns nil")
id, cx, cy = TackleBoxUI.hitTest(ui, 279, 100)
T.check(id == nil and cx == 8 and cy == 3, "hitTest at x=279, y=100 is the empty cell (8,3)")
id, cx, cy = TackleBoxUI.hitTest(ui, 100, 300)
T.check(cy == nil, "hitTest below the grid returns nil")
id, cx, cy = TackleBoxUI.hitTest(ui, 60.9, 70.4)
T.check(id == 1 and cx == 2 and cy == 2, "hitTest floors fractional pixels")
T.eq(TackleBoxUI.itemAt(ui, 4, 4), 2, "itemAt(4,4) is item B")
T.eq(TackleBoxUI.itemAt(ui, 9, 1), nil, "itemAt off-grid is nil")

-- ---------------------------------------------------------------- a full drag
T.eq(TackleBoxUI.state(ui), "idle", "starts idle")
T.eq(TackleBoxUI.preview(ui), nil, "no preview while idle")
TackleBoxUI.pointerDown(ui, centre(2, 2))
T.eq(TackleBoxUI.state(ui), "dragging", "pointerDown on an item starts a drag")
T.eq(TackleBoxUI.selectedId(ui), 1, "selectedId is the dragged item")
local c = TackleBoxUI.cursor(ui)
T.check(c.x == 2 and c.y == 2, "the cursor jumps to the pressed cell")
local pv = TackleBoxUI.preview(ui)
T.check(pv ~= nil and pv.valid and #pv.cells == 2, "preview in place is valid with two cells")
rectIs(pv and pv.cells[1], 44, 54, 32, 32, "preview cell 1 is the item's own cell (2,2)")
local d = TackleBoxUI.drag(ui)
T.check(d ~= nil and d.grab.x == 0 and d.grab.y == 0 and not d.moved, "grab offset (0,0), not yet moved")
TackleBoxUI.pointerMove(ui, centre(5, 2))
d = TackleBoxUI.drag(ui)
T.check(d ~= nil and d.x == 5 and d.y == 2 and d.moved, "three cells right: the drag origin is (5,2)")
pv = TackleBoxUI.preview(ui)
rectIs(pv and pv.cells[1], 146, 54, 32, 32, "preview cell 1 moved to (5,2) = {146, 54}")
rectIs(pv and pv.cells[2], 180, 54, 32, 32, "preview cell 2 moved to (6,2) = {180, 54}")
T.check(pv ~= nil and pv.valid, "preview at (5,2) is valid")
calls = {}
local action = TackleBoxUI.pointerUp(ui, centre(5, 2))
T.check(action ~= nil and action.kind == "move" and action.id == 1 and action.rot == 0 and action.x == 5 and action.y == 2, "pointerUp returns { move, id 1, rot 0, x 5, y 2 }")
local last = calls[#calls]
T.check(#calls >= 1 and last[1] == 1 and last[2] == 0 and last[3] == 5 and last[4] == 2, "canPlace was called with (1, 0, 5, 2)")
T.eq(TackleBoxUI.state(ui), "idle", "idle after the drop")
T.eq(TackleBoxUI.selectedId(ui), nil, "nothing selected after the drop")
T.eq(TackleBoxUI.items(ui)[1].x, 2, "the UI does not move the item itself: it waits for the server")
-- the server applies it and replicates
T.check(TackleBox.move(box, action and action.id or 0, action and action.rot or 0, action and action.x or 0, action and action.y or 0), "the server accepts the same move")
TackleBoxUI.setItems(ui, TackleBox.items(box))
T.eq((TackleBoxUI.hitTest(ui, centre(5, 2))), 1, "after replication hitTest finds A at (5,2)")
T.eq((TackleBoxUI.hitTest(ui, centre(2, 2))), nil, "and (2,2) is empty")

-- ---------------------------------------------------------------- illegal drops
TackleBoxUI.pointerDown(ui, centre(5, 2))
TackleBoxUI.pointerMove(ui, centre(3, 3)) -- cells (3,3) (4,3): (3,3) is B's
pv = TackleBoxUI.preview(ui)
T.check(pv ~= nil and not pv.valid, "preview over another item is invalid")
T.eq(TackleBoxUI.pointerUp(ui, centre(3, 3)), nil, "dropping onto another item returns nil")
T.eq(TackleBoxUI.state(ui), "idle", "state is idle after the illegal drop")
T.eq((TackleBoxUI.hitTest(ui, centre(5, 2))), 1, "the item is unmoved")
TackleBoxUI.pointerDown(ui, centre(5, 2))
TackleBoxUI.pointerMove(ui, centre(8, 2)) -- cells (8,2) (9,2): off the grid
pv = TackleBoxUI.preview(ui)
T.check(pv ~= nil and not pv.valid and #pv.cells == 2, "an off-grid preview is invalid but still has both cells")
rectIs(pv and pv.cells[2], 282, 54, 32, 32, "the off-grid ghost cell (9,2) is drawn at x=282")
T.eq(TackleBoxUI.pointerUp(ui, centre(8, 2)), nil, "dropping off the grid returns nil")
T.eq(TackleBoxUI.state(ui), "idle", "idle after the off-grid drop")
TackleBoxUI.pointerDown(ui, centre(5, 2))
TackleBoxUI.pointerMove(ui, 0, 0)
d = TackleBoxUI.drag(ui)
T.check(d ~= nil and d.hover.x == 0 and d.hover.y == 0, "hover before the origin is cell (0,0)")
TackleBoxUI.pointerMove(ui, 43, 70) -- x=43 is the gap after cell 1
d = TackleBoxUI.drag(ui)
T.check(d ~= nil and d.hover.x == 1, "a gap belongs to the cell before it for the drag hover")
TackleBoxUI.cancel(ui)
T.eq(TackleBoxUI.state(ui), "idle", "cancel ends the drag")
T.eq(TackleBoxUI.preview(ui), nil, "no preview after cancel")
T.eq(TackleBoxUI.pointerUp(ui, centre(1, 1)), nil, "pointerUp without a drag is nil")
-- the injected canPlace is the authority: a callback saying no blocks an empty cell
local refuse = TackleBoxUI.new({ cols = 8, rows = 6, cellPx = 32, gapPx = 2, originPx = { x = 10, y = 20 }, canPlace = function() return false end })
TackleBoxUI.setItems(refuse, TackleBox.items(box))
TackleBoxUI.pointerDown(refuse, centre(5, 2))
TackleBoxUI.pointerMove(refuse, centre(1, 1))
pv = TackleBoxUI.preview(refuse)
T.check(pv ~= nil and not pv.valid, "an injected canPlace that refuses makes the preview invalid")
T.eq(TackleBoxUI.pointerUp(refuse, centre(1, 1)), nil, "and the drop returns nil")
-- without a callback the built-in replica test runs
local builtin = TackleBoxUI.new({ cols = 8, rows = 6, cellPx = 32, gapPx = 2, originPx = { x = 10, y = 20 } })
TackleBoxUI.setItems(builtin, TackleBox.items(box))
TackleBoxUI.pointerDown(builtin, centre(5, 2))
TackleBoxUI.pointerMove(builtin, centre(1, 1))
action = TackleBoxUI.pointerUp(builtin, centre(1, 1))
T.check(action ~= nil and action.x == 1 and action.y == 1, "without a callback the built-in test allows an empty cell")
T.check(not TackleBoxUI.canPlaceLocal(builtin, 1, 0, 3, 3), "canPlaceLocal refuses an overlap")
T.check(TackleBoxUI.canPlaceLocal(builtin, 1, 0, 5, 2), "canPlaceLocal ignores the item's own cells")

-- ---------------------------------------------------------------- rotate mid-drag
local gx, gy = centre(4, 4) -- B's corner cell (4,4)
TackleBoxUI.pointerDown(ui, gx, gy)
d = TackleBoxUI.drag(ui)
T.check(d ~= nil and d.id == 2 and d.grab.x == 1 and d.grab.y == 1, "grabbed B by its (1,1) cell")
rectIs(previewCellUnder(TackleBoxUI.preview(ui), gx, gy), 112, 122, 32, 32, "before rotate the pointer is over cell (4,4)")
local expectOrigin = { { 4, 3 }, { 4, 4 }, { 3, 4 }, { 3, 3 } }
for rot = 1, 4 do
	TackleBoxUI.rotate(ui)
	d = TackleBoxUI.drag(ui)
	pv = TackleBoxUI.preview(ui)
	local under = previewCellUnder(pv, gx, gy)
	local e = expectOrigin[rot]
	T.check(d ~= nil and d.rot == rot % 4 and d.x == e[1] and d.y == e[2], string.format("rotate %d: rot %d, origin re-anchored to (%d, %d)", rot, rot % 4, e[1], e[2]))
	rectIs(under, 112, 122, 32, 32, string.format("rotate %d: the pointer is still over the grabbed cell (4,4)", rot))
	-- the ghost cells are exactly TackleBox.shapeCells at that rotation and origin
	local agree = pv ~= nil and d ~= nil
	if pv ~= nil and d ~= nil then
		for i, cell in TackleBox.shapeCells(TackleBox.SHAPES.L3, d.rot) do
			local r = TackleBoxUI.cellRect(ui, d.x + cell[1], d.y + cell[2])
			agree = agree and pv.cells[i].x == r.x and pv.cells[i].y == r.y
		end
	end
	T.check(agree, string.format("rotate %d: ghost cells agree with TackleBox.shapeCells", rot))
end
T.eq(TackleBoxUI.pointerUp(ui, gx, gy), nil, "four rotations put B back: a no-op drop returns nil")
T.eq(TackleBoxUI.state(ui), "idle", "and ends idle, not in the menu (it moved)")
TackleBoxUI.pointerDown(ui, gx, gy)
TackleBoxUI.rotate(ui)
action = TackleBoxUI.pointerUp(ui, gx, gy)
T.check(action ~= nil and action.id == 2 and action.rot == 1 and action.x == 4 and action.y == 3, "one rotation then release: move { id 2, rot 1, x 4, y 3 }")
T.check(TackleBox.move(box, 2, 1, 4, 3), "the server accepts the rotated placement")
TackleBoxUI.setItems(ui, TackleBox.items(box))
TackleBoxUI.rotate(ui)
T.eq(TackleBoxUI.state(ui), "idle", "rotate while idle does nothing")

-- ---------------------------------------------------------------- tap -> menu, put back -> idle
TackleBoxUI.pointerDown(ui, centre(5, 2))
T.eq(TackleBoxUI.pointerUp(ui, centre(5, 2)), nil, "a tap (release in place, no move) returns no action")
T.eq(TackleBoxUI.state(ui), "menu", "and opens the menu state")
T.eq(TackleBoxUI.selectedId(ui), 1, "with the tapped item selected")
T.eq(TackleBoxUI.preview(ui), nil, "no ghost in the menu")
TackleBoxUI.cancel(ui)
T.eq(TackleBoxUI.state(ui), "idle", "cancel closes the menu")
TackleBoxUI.pointerDown(ui, centre(5, 2))
TackleBoxUI.pointerUp(ui, centre(5, 2))
TackleBoxUI.pointerDown(ui, centre(1, 1))
T.eq(TackleBoxUI.state(ui), "idle", "pointerDown on an empty cell closes the menu")
TackleBoxUI.pointerDown(ui, centre(5, 2))
TackleBoxUI.pointerUp(ui, centre(5, 2))
TackleBoxUI.pointerDown(ui, centre(7, 5))
T.check(TackleBoxUI.state(ui) == "dragging" and TackleBoxUI.selectedId(ui) == 3, "pointerDown on another item from the menu drags that item")
TackleBoxUI.cancel(ui)
TackleBoxUI.pointerDown(ui, centre(5, 2))
TackleBoxUI.pointerMove(ui, centre(1, 1))
TackleBoxUI.pointerMove(ui, centre(5, 2))
T.eq(TackleBoxUI.pointerUp(ui, centre(5, 2)), nil, "dragged away and put back: nil")
T.eq(TackleBoxUI.state(ui), "idle", "and idle, not the menu")
TackleBoxUI.pointerDown(ui, centre(5, 2))
TackleBoxUI.pointerDown(ui, centre(7, 5))
T.eq(TackleBoxUI.selectedId(ui), 1, "a second pointerDown while dragging is ignored")
TackleBoxUI.cancel(ui)

-- ---------------------------------------------------------------- cursor (keyboard / gamepad)
local cur = TackleBoxUI.new({ cols = 8, rows = 6, cellPx = 32, gapPx = 2, originPx = { x = 10, y = 20 } })
TackleBoxUI.setItems(cur, TackleBox.items(sampleBox()))
c = TackleBoxUI.cursor(cur)
T.check(c.x == 1 and c.y == 1, "the cursor starts at (1,1)")
TackleBoxUI.cursorMove(cur, -1, -1)
c = TackleBoxUI.cursor(cur)
T.check(c.x == 1 and c.y == 1, "cursorMove clamps at the top-left")
TackleBoxUI.cursorMove(cur, 100, 100)
c = TackleBoxUI.cursor(cur)
T.check(c.x == 8 and c.y == 6, "cursorMove clamps at the bottom-right")
TackleBoxUI.cursorMove(cur, -7, -5)
T.eq(TackleBoxUI.cursorSelect(cur), nil, "cursorSelect on an empty cell does nothing")
T.eq(TackleBoxUI.state(cur), "idle", "and stays idle")
TackleBoxUI.cursorMove(cur, 1, 1) -- (2,2): item A
T.eq(TackleBoxUI.cursorSelect(cur), nil, "cursorSelect on an item picks it up (no action yet)")
T.check(TackleBoxUI.state(cur) == "dragging" and TackleBoxUI.selectedId(cur) == 1, "dragging A from the cursor")
TackleBoxUI.cursorMove(cur, 0, 3) -- (2,5)
d = TackleBoxUI.drag(cur)
T.check(d ~= nil and d.x == 2 and d.y == 5, "the held item follows the cursor")
action = TackleBoxUI.cursorSelect(cur)
T.check(action ~= nil and action.kind == "move" and action.id == 1 and action.rot == 0 and action.x == 2 and action.y == 5, "cursorSelect again drops it: move { id 1, rot 0, x 2, y 5 }")
T.eq(TackleBoxUI.state(cur), "idle", "idle after the cursor drop")
TackleBoxUI.cursorMove(cur, 0, -3) -- back to (2,2), A still there (not replicated)
TackleBoxUI.cursorSelect(cur)
TackleBoxUI.cursorMove(cur, 1, 1) -- (3,3): cells (3,3) (4,3) overlap B
pv = TackleBoxUI.preview(cur)
T.check(pv ~= nil and not pv.valid, "the cursor ghost over B is invalid")
T.eq(TackleBoxUI.cursorSelect(cur), nil, "cursorSelect on an illegal cell is refused")
T.eq(TackleBoxUI.state(cur), "dragging", "and the item stays held")
TackleBoxUI.cursorMove(cur, 0, 2) -- (3,5): free
action = TackleBoxUI.cursorSelect(cur)
T.check(action ~= nil and action.x == 3 and action.y == 5, "moving on to a free cell then select drops it there")
TackleBoxUI.cursorMove(cur, -1, -3) -- (2,2)
TackleBoxUI.cursorSelect(cur)
TackleBoxUI.rotate(cur)
d = TackleBoxUI.drag(cur)
T.check(d ~= nil and d.rot == 1 and d.x == 2 and d.y == 2, "rotate under the cursor re-anchors on the cursor cell")
TackleBoxUI.cancel(cur)
TackleBoxUI.cursorSelect(cur)
T.eq(TackleBoxUI.cursorSelect(cur), nil, "select twice on the same cell is a tap")
T.eq(TackleBoxUI.state(cur), "menu", "which opens the menu")
T.eq(TackleBoxUI.cursorSelect(cur), nil, "select from the menu picks the item up again")
T.eq(TackleBoxUI.state(cur), "dragging", "(dragging)")
TackleBoxUI.cancel(cur)
T.throws(function() TackleBoxUI.cursorMove(cur, 1.5, 0) end, "integers", "cursorMove with a fractional step errors")

-- ---------------------------------------------------------------- setItems guards
local guard = TackleBoxUI.new({ cols = 4, rows = 4, cellPx = 32, gapPx = 2, originPx = { x = 0, y = 0 } })
local shapeL2 = TackleBox.SHAPES.line2
T.throws(function()
	TackleBoxUI.setItems(guard, { { id = 1, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 4, y = 1 } })
end, "outside", "setItems refuses an item hanging off the grid")
T.throws(function()
	TackleBoxUI.setItems(guard, {
		{ id = 1, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 1, y = 1 },
		{ id = 2, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 2, y = 1 },
	})
end, "share cell", "setItems refuses two items sharing a cell")
T.throws(function()
	TackleBoxUI.setItems(guard, {
		{ id = 1, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 1, y = 1 },
		{ id = 1, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 1, y = 3 },
	})
end, "duplicate", "setItems refuses a duplicate id")
TackleBoxUI.setItems(guard, { { id = 1, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 1, y = 1 } })
TackleBoxUI.pointerDown(guard, 16, 16)
TackleBoxUI.setItems(guard, {})
T.eq(TackleBoxUI.state(guard), "idle", "a drag is cancelled when its item disappears from setItems")
TackleBoxUI.setItems(guard, { { id = 1, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 1, y = 1 } })
TackleBoxUI.pointerDown(guard, 16, 16)
TackleBoxUI.pointerMove(guard, 16 + 68, 16)
TackleBoxUI.setItems(guard, { { id = 1, item = { kind = "fish", key = "t", shape = shapeL2 }, rot = 0, x = 1, y = 1 } })
d = TackleBoxUI.drag(guard)
T.check(TackleBoxUI.state(guard) == "dragging" and d ~= nil and d.x == 3, "a drag survives a setItems that keeps its item, hover intact")

-- ---------------------------------------------------------------- negative controls
T.throws(function() TackleBoxUI.new({ cols = 0, rows = 6, cellPx = 32, gapPx = 2, originPx = { x = 0, y = 0 } }) end, "bad grid", "new with cols 0 errors")
T.throws(function() TackleBoxUI.new({ cols = 8, rows = 6, cellPx = 0, gapPx = 2, originPx = { x = 0, y = 0 } }) end, "cellPx", "new with cellPx 0 errors")
T.throws(function() TackleBoxUI.new({ cols = 8, rows = 6, cellPx = 32, gapPx = -1, originPx = { x = 0, y = 0 } }) end, "gapPx", "new with a negative gap errors")
T.throws(function() TackleBoxUI.new({ cols = 8, rows = 6, cellPx = 32, gapPx = 2, originPx = nil :: any }) end, "originPx", "new without an origin errors")
T.throws(function() TackleBoxUI.cellRect(ui, 1.5, 1) end, "integers", "cellRect with a fractional cell errors")

T.finish()
