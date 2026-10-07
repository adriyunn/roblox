--!strict
-- TackleBoxUI (About Fishing F1, WS-T tackle box; Cloud, 2026-10-07; design/WST_tacklebox.md)
-- State and geometry of the tackle-box screen: every cell and item as an integer-pixel rectangle, hit
-- testing, the pick-up / move / rotate / drop state machine and the keyboard-gamepad cursor. The
-- renderer (Frames, UserInputService) sits on top and does no grid maths; this module never touches a
-- GUI object, so it runs under the offline Luau CLI.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * The renderer builds one Frame per cell from layout() once, one Frame per item cell from
--     itemCells() after every setItems(), and a ghost from preview() every frame while dragging.
--   * Input (design/WSI_touch_gamepad.md, one device layer): mouse button 1 and a touch call
--     pointerDown / pointerMove / pointerUp with the pixel position; a key, a gamepad button or a
--     touch button calls rotate / cancel; the gamepad D-pad or the arrow keys call cursorMove and
--     A / Return call cursorSelect. Every device therefore drives the same four verbs: pick up, move,
--     rotate, drop (plus cancel). Nothing device-specific lives here.
--   * The only output that reaches the server is the move action from pointerUp / cursorSelect:
--     { kind = "move", id, rot, x, y } -> FishingNet -> TackleBox.move(box, id, rot, x, y). The
--     server replies with TackleBox.items(box), which the renderer feeds back into setItems().
--   * canPlace: pass opts.canPlace(id, rot, x, y) -> boolean to judge drops with the client's replica
--     of the box (the same bounds + overlap-ignoring-own-cells test as TackleBox.move), so the ghost
--     colour and the server verdict agree. Without it, the built-in canPlaceLocal() runs the same
--     test on the items last given to setItems().
-- Design decisions a dev must know:
--   * A press and release on an item without moving it (a tap or a click, or cursorSelect twice on
--     the same cell) does not move it: it enters the `menu` state with that item selected, which is
--     where touch and gamepad get their Sell / Discard buttons. The renderer reads selectedId() and
--     state(), sends its own request, then calls cancel(). A real drag put back where it started
--     ends in `idle` with no action (nothing to send).
--   * A pointer release on an illegal cell ends the drag (the finger is up): idle, nil, item unmoved.
--     cursorSelect on an illegal cell refuses the drop and keeps holding the item (the ghost stays
--     red until the cursor finds room or cancel is pressed), because a button press is a request,
--     not a lift.
--   * Pixel to cell: a gap belongs to no cell for hitTest (nil), but to the cell before it for the
--     drag hover, and hover cells may lie outside the grid (the ghost then draws off-grid and red).
--   * The grabbed cell is remembered as a cell of the item's unrotated shape, so rotate() re-anchors
--     the item and the grabbed cell stays under the pointer through all four rotations.
-- No Roblox globals.

local TackleBox = require("../Shared/TackleBox")

local TackleBoxUI = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Cell = { x: number, y: number }
export type Placed = TackleBox.Placed
export type CanPlace = (id: number, rot: number, x: number, y: number) -> boolean
export type Opts = {
	cols: number,
	rows: number,
	cellPx: number,
	gapPx: number,
	originPx: { x: number, y: number },
	canPlace: CanPlace?,
}
export type State = "idle" | "dragging" | "menu"
export type Action = { kind: "move", id: number, rot: number, x: number, y: number }
export type Drag = {
	id: number,
	rot: number,
	x: number, -- origin cell of the rotated shape (hover - grab)
	y: number,
	hover: Cell, -- the cell under the pointer or cursor; may be off-grid
	grabIndex: number, -- index into the item's unrotated shape of the grabbed cell
	grab: Cell, -- that cell's offset from the origin at the current rotation
	moved: boolean, -- the hover left the grab cell, or rotate was pressed
}
export type Preview = { cells: { Rect }, valid: boolean, rot: number, x: number, y: number }
export type Layout = { gridRect: Rect, cellRects: { Rect } }
export type UI = {
	cols: number,
	rows: number,
	cellPx: number,
	gapPx: number,
	origin: Cell, -- px
	canPlace: CanPlace?,
	items: { [number]: Placed },
	order: { number }, -- ids ascending
	grid: { [number]: number }, -- (y-1)*cols + x -> id
	state: State,
	drag: Drag?,
	menuId: number?,
	cursor: Cell, -- always inside the grid
}

-- ---------------------------------------------------------------- helpers
local function isInt(v: any): boolean
	return typeof(v) == "number" and v == math.floor(v) and math.abs(v) < math.huge
end

local function cellKey(ui: UI, x: number, y: number): number
	return (y - 1) * ui.cols + x
end

local function inBounds(ui: UI, x: number, y: number): boolean
	return x >= 1 and y >= 1 and x <= ui.cols and y <= ui.rows
end

-- Offset of one shape cell after rotation and normalisation: the same 90-degree-clockwise law and
-- the same min-x / min-y shift as TackleBox.shapeCells, kept per cell so a grabbed cell can be
-- followed through rotations (shapeCells sorts its output and loses which cell was which).
local function rotatedOffset(shape: TackleBox.Shape, rot: number, index: number): (number, number)
	local minX, minY = math.huge, math.huge
	local rx, ry = 0, 0
	for i, c in shape do
		local dx, dy = c[1], c[2]
		for _ = 1, rot do
			dx, dy = -dy, dx
		end
		if i == index then
			rx, ry = dx, dy
		end
		minX = math.min(minX, dx)
		minY = math.min(minY, dy)
	end
	return rx - minX, ry - minY
end

-- Pixel coordinate -> 1-based cell index along one axis. Strict: nil before the origin or inside a
-- gap (hitTest). Loose: the gap belongs to the cell before it and indices run past both ends (hover).
local function axisCell(origin: number, cellPx: number, gapPx: number, p: number, strict: boolean): number?
	local rel = math.floor(p) - origin
	if strict and rel < 0 then
		return nil
	end
	local pitch = cellPx + gapPx
	local i = math.floor(rel / pitch)
	if strict and rel - i * pitch >= cellPx then
		return nil
	end
	return i + 1
end

local function hoverCell(ui: UI, px: number, py: number): (number, number)
	local cx = axisCell(ui.origin.x, ui.cellPx, ui.gapPx, px, false) :: number
	local cy = axisCell(ui.origin.y, ui.cellPx, ui.gapPx, py, false) :: number
	return cx, cy
end

local function cellsAt(ui: UI, shape: TackleBox.Shape, rot: number, x: number, y: number): { Rect }
	local out: { Rect } = {}
	for i, c in TackleBox.shapeCells(shape, rot) do
		out[i] = TackleBoxUI.cellRect(ui, x + c[1], y + c[2])
	end
	return out
end

local function clearSelection(ui: UI)
	ui.state = "idle"
	ui.drag = nil
	ui.menuId = nil
end

-- ---------------------------------------------------------------- construction
-- A new screen state. cols, rows, cellPx >= 1 and gapPx >= 0 must be integers (cols/rows at most
-- TackleBox.MAX_DIM); originPx is floored to whole pixels. Errors on a bad option.
function TackleBoxUI.new(opts: Opts): UI
	if typeof(opts) ~= "table" then
		error("TackleBoxUI.new: opts must be a table")
	end
	local o: any = opts
	if not isInt(o.cols) or not isInt(o.rows) or o.cols < 1 or o.rows < 1 or o.cols > TackleBox.MAX_DIM or o.rows > TackleBox.MAX_DIM then
		error(string.format("TackleBoxUI.new: bad grid %s x %s", tostring(o.cols), tostring(o.rows)))
	end
	if not isInt(o.cellPx) or o.cellPx < 1 then
		error("TackleBoxUI.new: cellPx must be an integer >= 1, got " .. tostring(o.cellPx))
	end
	if not isInt(o.gapPx) or o.gapPx < 0 then
		error("TackleBoxUI.new: gapPx must be an integer >= 0, got " .. tostring(o.gapPx))
	end
	if typeof(o.originPx) ~= "table" or typeof(o.originPx.x) ~= "number" or typeof(o.originPx.y) ~= "number" then
		error("TackleBoxUI.new: originPx must be {x, y} in pixels")
	end
	if o.canPlace ~= nil and typeof(o.canPlace) ~= "function" then
		error("TackleBoxUI.new: canPlace must be a function (id, rot, x, y) -> boolean, or nil")
	end
	return {
		cols = o.cols,
		rows = o.rows,
		cellPx = o.cellPx,
		gapPx = o.gapPx,
		origin = { x = math.floor(o.originPx.x), y = math.floor(o.originPx.y) },
		canPlace = o.canPlace,
		items = {},
		order = {},
		grid = {},
		state = "idle",
		drag = nil,
		menuId = nil,
		cursor = { x = 1, y = 1 },
	}
end

-- Replaces the items shown (TackleBox.items() output, replicated from the server). Errors on a
-- malformed record, an item outside the grid or two items sharing a cell, since the replica would then
-- disagree with the server. A drag or menu selection whose item disappeared is cancelled; a drag whose
-- item is still there continues (the ghost follows the pointer, not the item's home).
function TackleBoxUI.setItems(ui: UI, items: { Placed })
	if typeof(items) ~= "table" then
		error("TackleBoxUI.setItems: items must be an array")
	end
	local newItems: { [number]: Placed } = {}
	local order: { number } = {}
	local grid: { [number]: number } = {}
	local list: { any } = items
	for i = 1, #list do
		local p: any = list[i]
		if typeof(p) ~= "table" or not isInt(p.id) or typeof(p.item) ~= "table" or not isInt(p.rot) or p.rot < 0 or p.rot > 3 or not isInt(p.x) or not isInt(p.y) then
			error("TackleBoxUI.setItems: item " .. tostring(i) .. " is not a TackleBox placed item")
		end
		local id: number, rot: number, x: number, y: number = p.id, p.rot, p.x, p.y
		if newItems[id] then
			error("TackleBoxUI.setItems: duplicate item id " .. tostring(id))
		end
		for _, c in TackleBox.shapeCells(p.item.shape, rot) do
			local cx, cy = x + c[1], y + c[2]
			if not inBounds(ui, cx, cy) then
				error(string.format("TackleBoxUI.setItems: item %d is outside the %d x %d grid at (%d, %d)", id, ui.cols, ui.rows, cx, cy))
			end
			local k = cellKey(ui, cx, cy)
			if grid[k] then
				error(string.format("TackleBoxUI.setItems: items %d and %d share cell (%d, %d)", grid[k], id, cx, cy))
			end
			grid[k] = id
		end
		newItems[id] = { id = id, item = p.item, rot = rot, x = x, y = y }
		table.insert(order, id)
	end
	table.sort(order)
	ui.items, ui.order, ui.grid = newItems, order, grid
	local sel = TackleBoxUI.selectedId(ui)
	if sel ~= nil and newItems[sel] == nil then
		clearSelection(ui)
	end
end

-- ---------------------------------------------------------------- geometry (integer pixels)
-- The rectangle of cell (x, y). Any integer cell is accepted, including one outside the grid, so the
-- drag ghost can be drawn where an off-grid drop would land.
function TackleBoxUI.cellRect(ui: UI, x: number, y: number): Rect
	if not isInt(x) or not isInt(y) then
		error(string.format("TackleBoxUI.cellRect: cell must be integers, got (%s, %s)", tostring(x), tostring(y)))
	end
	local pitch = ui.cellPx + ui.gapPx
	return { x = ui.origin.x + (x - 1) * pitch, y = ui.origin.y + (y - 1) * pitch, w = ui.cellPx, h = ui.cellPx }
end

-- True when (x, y) is a grid cell.
function TackleBoxUI.inBounds(ui: UI, x: number, y: number): boolean
	return isInt(x) and isInt(y) and inBounds(ui, x, y)
end

-- One rectangle per cell of a placed item (TackleBox.shapeCells order: rows, then columns).
function TackleBoxUI.itemCells(ui: UI, placed: Placed): { Rect }
	return cellsAt(ui, placed.item.shape, placed.rot, placed.x, placed.y)
end

-- The bounding box of a placed item's rotated cells.
function TackleBoxUI.itemRect(ui: UI, placed: Placed): Rect
	local sw, sh = TackleBox.shapeSize(placed.item.shape, placed.rot)
	local r = TackleBoxUI.cellRect(ui, placed.x, placed.y)
	return { x = r.x, y = r.y, w = sw * ui.cellPx + (sw - 1) * ui.gapPx, h = sh * ui.cellPx + (sh - 1) * ui.gapPx }
end

-- The whole grid's rectangle and every cell's rectangle, row-major (index = (y-1)*cols + x), for the
-- renderer to build its Frames once.
function TackleBoxUI.layout(ui: UI): Layout
	local cellRects: { Rect } = {}
	for y = 1, ui.rows do
		for x = 1, ui.cols do
			cellRects[cellKey(ui, x, y)] = TackleBoxUI.cellRect(ui, x, y)
		end
	end
	return {
		gridRect = {
			x = ui.origin.x,
			y = ui.origin.y,
			w = ui.cols * ui.cellPx + (ui.cols - 1) * ui.gapPx,
			h = ui.rows * ui.cellPx + (ui.rows - 1) * ui.gapPx,
		},
		cellRects = cellRects,
	}
end

-- What is under a pixel: the item id (or nil for an empty cell) plus the cell; all nil outside the
-- grid or inside a gap. Fractional pixels are floored.
function TackleBoxUI.hitTest(ui: UI, px: number, py: number): (number?, number?, number?)
	local cx = axisCell(ui.origin.x, ui.cellPx, ui.gapPx, px, true)
	local cy = axisCell(ui.origin.y, ui.cellPx, ui.gapPx, py, true)
	if cx == nil or cy == nil or not inBounds(ui, cx, cy) then
		return nil, nil, nil
	end
	return ui.grid[cellKey(ui, cx, cy)], cx, cy
end

-- The item id occupying a cell, or nil (also nil off-grid).
function TackleBoxUI.itemAt(ui: UI, x: number, y: number): number?
	if not TackleBoxUI.inBounds(ui, x, y) then
		return nil
	end
	return ui.grid[cellKey(ui, x, y)]
end

-- ---------------------------------------------------------------- the drop test
-- The built-in drop test on the replica: every cell inside the grid and free or the item's own. This
-- is TackleBox.move's test without the box; opts.canPlace replaces it when given.
function TackleBoxUI.canPlaceLocal(ui: UI, id: number, rot: number, x: number, y: number): boolean
	local p = ui.items[id]
	if p == nil then
		return false
	end
	for _, c in TackleBox.shapeCells(p.item.shape, rot) do
		local cx, cy = x + c[1], y + c[2]
		if not inBounds(ui, cx, cy) then
			return false
		end
		local other = ui.grid[cellKey(ui, cx, cy)]
		if other ~= nil and other ~= id then
			return false
		end
	end
	return true
end

local function dropAllowed(ui: UI, id: number, rot: number, x: number, y: number): boolean
	local cb = ui.canPlace
	if cb ~= nil then
		return cb(id, rot, x, y) == true
	end
	return TackleBoxUI.canPlaceLocal(ui, id, rot, x, y)
end

-- ---------------------------------------------------------------- the drag state machine
local function beginDrag(ui: UI, id: number, cx: number, cy: number)
	local p = ui.items[id]
	local lx, ly = cx - p.x, cy - p.y
	local grabIndex: number? = nil
	for i in p.item.shape do
		local ox, oy = rotatedOffset(p.item.shape, p.rot, i)
		if ox == lx and oy == ly then
			grabIndex = i
			break
		end
	end
	if grabIndex == nil then
		error(string.format("TackleBoxUI: cell (%d, %d) is not a cell of item %d", cx, cy, id))
	end
	ui.state = "dragging"
	ui.menuId = nil
	ui.drag = {
		id = id,
		rot = p.rot,
		x = p.x,
		y = p.y,
		hover = { x = cx, y = cy },
		grabIndex = grabIndex,
		grab = { x = lx, y = ly },
		moved = false,
	}
end

local function setHover(d: Drag, hx: number, hy: number)
	if hx ~= d.hover.x or hy ~= d.hover.y then
		d.moved = true
	end
	d.hover = { x = hx, y = hy }
	d.x = hx - d.grab.x
	d.y = hy - d.grab.y
end

-- Judges the current drag position: "menu" (released in place without moving), "noop" (put back where
-- it was after moving), "move" (a legal new placement, with the action) or "illegal".
local function resolveDrop(ui: UI, d: Drag): (string, Action?)
	local home = ui.items[d.id]
	local inPlace = d.rot == home.rot and d.x == home.x and d.y == home.y
	if inPlace then
		return if d.moved then "noop" else "menu", nil
	end
	if dropAllowed(ui, d.id, d.rot, d.x, d.y) then
		return "move", { kind = "move", id = d.id, rot = d.rot, x = d.x, y = d.y }
	end
	return "illegal", nil
end

local function endDrag(ui: UI, d: Drag, outcome: string)
	if outcome == "menu" then
		ui.state = "menu"
		ui.menuId = d.id
	else
		ui.state = "idle"
		ui.menuId = nil
	end
	ui.drag = nil
end

-- Press at a pixel. On an item: pick it up (dragging); the cursor jumps to that cell. Elsewhere: closes
-- the menu if open, otherwise nothing. Ignored while already dragging (a second finger or button).
function TackleBoxUI.pointerDown(ui: UI, px: number, py: number)
	if ui.state == "dragging" then
		return
	end
	if ui.state == "menu" then
		clearSelection(ui)
	end
	local id, cx, cy = TackleBoxUI.hitTest(ui, px, py)
	if id == nil or cx == nil or cy == nil then
		return
	end
	ui.cursor = { x = cx, y = cy }
	beginDrag(ui, id, cx, cy)
end

-- Pointer moved to a pixel: while dragging, the hover cell and the ghost follow (gaps count as the
-- cell before them; off-grid cells are allowed). Nothing otherwise.
function TackleBoxUI.pointerMove(ui: UI, px: number, py: number)
	local d = ui.drag
	if ui.state ~= "dragging" or d == nil then
		return
	end
	local hx, hy = hoverCell(ui, px, py)
	setHover(d, hx, hy)
end

-- Release at a pixel: ends a drag. Returns the move action when the drop is a legal new placement
-- (per canPlace), nil otherwise: in place without moving -> menu; put back after moving -> idle;
-- illegal -> idle with the item unmoved (the server was never asked).
function TackleBoxUI.pointerUp(ui: UI, px: number, py: number): Action?
	local d = ui.drag
	if ui.state ~= "dragging" or d == nil then
		return nil
	end
	local hx, hy = hoverCell(ui, px, py)
	setHover(d, hx, hy)
	local outcome, action = resolveDrop(ui, d)
	endDrag(ui, d, outcome)
	return action
end

-- Rotates the held item 90 degrees clockwise and re-anchors it so the grabbed cell stays under the
-- pointer. Nothing when not dragging.
function TackleBoxUI.rotate(ui: UI)
	local d = ui.drag
	if ui.state ~= "dragging" or d == nil then
		return
	end
	local shape = ui.items[d.id].item.shape
	d.rot = (d.rot + 1) % 4
	local gx, gy = rotatedOffset(shape, d.rot, d.grabIndex)
	d.grab = { x = gx, y = gy }
	d.x = d.hover.x - gx
	d.y = d.hover.y - gy
	d.moved = true
end

-- Drops any drag or menu selection; the item stays where the server has it.
function TackleBoxUI.cancel(ui: UI)
	clearSelection(ui)
end

-- The ghost while dragging: one rect per cell at the current position and rotation, and whether the
-- drop would be legal. nil when not dragging.
function TackleBoxUI.preview(ui: UI): Preview?
	local d = ui.drag
	if ui.state ~= "dragging" or d == nil then
		return nil
	end
	local shape = ui.items[d.id].item.shape
	return {
		cells = cellsAt(ui, shape, d.rot, d.x, d.y),
		valid = dropAllowed(ui, d.id, d.rot, d.x, d.y),
		rot = d.rot,
		x = d.x,
		y = d.y,
	}
end

-- ---------------------------------------------------------------- keyboard / gamepad cursor
-- Moves the cursor by whole cells, clamped to the grid. While dragging, the held item follows the
-- cursor exactly as it follows the pointer.
function TackleBoxUI.cursorMove(ui: UI, dx: number, dy: number)
	if not isInt(dx) or not isInt(dy) then
		error(string.format("TackleBoxUI.cursorMove: dx, dy must be integers, got (%s, %s)", tostring(dx), tostring(dy)))
	end
	ui.cursor = { x = math.clamp(ui.cursor.x + dx, 1, ui.cols), y = math.clamp(ui.cursor.y + dy, 1, ui.rows) }
	local d = ui.drag
	if ui.state == "dragging" and d ~= nil then
		setHover(d, ui.cursor.x, ui.cursor.y)
	end
end

-- The select button. Idle (or menu): picks up the item under the cursor, if any. Dragging: drops it
-- at the cursor with the same outcomes as pointerUp, except that an illegal drop is refused and the
-- item stays held. Returns the move action or nil.
function TackleBoxUI.cursorSelect(ui: UI): Action?
	if ui.state == "menu" then
		clearSelection(ui)
	end
	local d = ui.drag
	if ui.state ~= "dragging" or d == nil then
		local id = ui.grid[cellKey(ui, ui.cursor.x, ui.cursor.y)]
		if id ~= nil then
			beginDrag(ui, id, ui.cursor.x, ui.cursor.y)
		end
		return nil
	end
	setHover(d, ui.cursor.x, ui.cursor.y)
	local outcome, action = resolveDrop(ui, d)
	if outcome == "illegal" then
		return nil
	end
	endDrag(ui, d, outcome)
	return action
end

-- ---------------------------------------------------------------- read-only views
-- The current state: "idle", "dragging" or "menu".
function TackleBoxUI.state(ui: UI): State
	return ui.state
end

-- The item being dragged or selected in the menu, or nil.
function TackleBoxUI.selectedId(ui: UI): number?
	local d = ui.drag
	if ui.state == "dragging" and d ~= nil then
		return d.id
	elseif ui.state == "menu" then
		return ui.menuId
	end
	return nil
end

-- A copy of the cursor cell.
function TackleBoxUI.cursor(ui: UI): Cell
	return { x = ui.cursor.x, y = ui.cursor.y }
end

-- A copy of the drag in progress (id, rot, x, y, hover, grab, moved), or nil.
function TackleBoxUI.drag(ui: UI): Drag?
	local d = ui.drag
	if ui.state ~= "dragging" or d == nil then
		return nil
	end
	return {
		id = d.id,
		rot = d.rot,
		x = d.x,
		y = d.y,
		hover = { x = d.hover.x, y = d.hover.y },
		grabIndex = d.grabIndex,
		grab = { x = d.grab.x, y = d.grab.y },
		moved = d.moved,
	}
end

-- The items shown, ordered by id (the records setItems was given; do not mutate).
function TackleBoxUI.items(ui: UI): { Placed }
	local out: { Placed } = {}
	for i, id in ui.order do
		out[i] = ui.items[id]
	end
	return out
end

return TackleBoxUI
