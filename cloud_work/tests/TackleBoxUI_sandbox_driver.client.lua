-- TackleBoxUI_sandbox_driver.client.lua (About Fishing F1 cloud work; Cloud, 2026-10-07)
-- TEMPORARY. STUDIO ONLY. NOT PART OF THE GAME. A throwaway LocalScript that draws TackleBoxUI over a
-- local TackleBox with three sample items and no server, so a dev can drag with the mouse, a touch or
-- a gamepad, watch the ghost turn green or red, and see the move action that would go over the net.
-- Delete it after the sandbox session; nothing references it.
--
-- Where the modules live in the place (the Rojo tree): ReplicatedStorage.Fishing.Client.TackleBoxUI
-- and ReplicatedStorage.Fishing.Shared.TackleBox. The requires below are script.Parent-relative: put
-- this LocalScript in StarterPlayer.StarterPlayerScripts with a copy of the `Fishing` folder next to it
-- (keep the Client / Shared layout: TackleBoxUI requires "../Shared/TackleBox"). To run against the
-- live tree instead, set `Fishing` to game:GetService("ReplicatedStorage"):WaitForChild("Fishing").
--
-- Controls (one device layer, design/WSI_touch_gamepad.md: every device drives the same verbs):
--   pick up / move / drop   mouse button 1 or a touch drag; arrows + Return, D-pad + A for the cursor
--   rotate                  R, gamepad X
--   cancel                  Backspace, gamepad B
-- A press and release without moving (a tap, a click, Return twice) opens the menu state: the item
-- goes translucent; Backspace / B closes it. The thumbstick is not bound; the D-pad is enough here.
-- The ScreenGui ignores the GUI inset so UserInputService positions and Frame offsets share one origin.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Fishing = script.Parent:WaitForChild("Fishing")
local TackleBoxUI = require(Fishing:WaitForChild("Client"):WaitForChild("TackleBoxUI"))
local TackleBox = require(Fishing:WaitForChild("Shared"):WaitForChild("TackleBox"))

local COLS, ROWS, CELL_PX, GAP_PX = 8, 6, 48, 4
local ORIGIN = { x = 40, y = 120 }

-- ---------------------------------------------------------------- the "server": a local box
local box = TackleBox.new(COLS, ROWS)
assert(TackleBox.place(box, { kind = "fish", key = "trout", shape = TackleBox.SHAPES.line2, data = { lengthM = 0.40 } }, 0, 2, 2))
assert(TackleBox.place(box, { kind = "gear", key = "hook_sharp", shape = TackleBox.SHAPES.L3 }, 0, 3, 3))
assert(TackleBox.place(box, { kind = "lure", key = "spinner", shape = TackleBox.SHAPES.line1 }, 0, 7, 5))

-- The drop test the server would run (TackleBox.move's bounds + overlap test, own cells ignored),
-- injected so the ghost colour and the server verdict come from the same rule.
local function serverCanPlace(id, rot, x, y)
	local p = box.placed[id]
	if not p then
		return false
	end
	for _, c in TackleBox.shapeCells(p.item.shape, rot) do
		local cx, cy = x + c[1], y + c[2]
		if cx < 1 or cy < 1 or cx > box.w or cy > box.h then
			return false
		end
		local other = TackleBox.at(box, cx, cy)
		if other ~= nil and other ~= id then
			return false
		end
	end
	return true
end

local ui = TackleBoxUI.new({ cols = COLS, rows = ROWS, cellPx = CELL_PX, gapPx = GAP_PX, originPx = ORIGIN, canPlace = serverCanPlace })
TackleBoxUI.setItems(ui, TackleBox.items(box))

-- ---------------------------------------------------------------- the GUI
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "TackleBoxSandbox"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function frame(rect, color, z, name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(rect.x, rect.y)
	f.Size = UDim2.fromOffset(rect.w, rect.h)
	f.ZIndex = z
	f.Parent = gui
	return f
end

local KIND_COLORS = {
	fish = Color3.fromRGB(90, 160, 230),
	lure = Color3.fromRGB(230, 170, 60),
	gear = Color3.fromRGB(150, 150, 150),
}
local GHOST_OK = Color3.fromRGB(70, 200, 90)
local GHOST_BAD = Color3.fromRGB(220, 70, 70)

-- the grid, built once from layout()
local layout = TackleBoxUI.layout(ui)
frame(layout.gridRect, Color3.fromRGB(30, 30, 35), 1, "Grid")
for i, r in layout.cellRects do
	frame(r, Color3.fromRGB(60, 60, 70), 2, "Cell" .. i)
end

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.TextColor3 = Color3.new(1, 1, 1)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.Code
status.TextSize = 16
status.Position = UDim2.fromOffset(ORIGIN.x, ORIGIN.y - 40)
status.Size = UDim2.fromOffset(600, 32)
status.ZIndex = 6
status.Parent = gui

local cursorFrame = frame(TackleBoxUI.cellRect(ui, 1, 1), Color3.new(1, 1, 1), 5, "Cursor")
cursorFrame.BackgroundTransparency = 1
cursorFrame.BorderSizePixel = 2
cursorFrame.BorderColor3 = Color3.new(1, 1, 1)

local itemFrames = {}
local ghostFrames = {}

local function redraw()
	for _, f in itemFrames do
		f:Destroy()
	end
	itemFrames = {}
	local selected = TackleBoxUI.selectedId(ui)
	for _, p in TackleBoxUI.items(ui) do
		for _, r in TackleBoxUI.itemCells(ui, p) do
			local f = frame(r, KIND_COLORS[p.item.kind] or Color3.new(1, 1, 1), 3, "Item" .. p.id)
			f.BackgroundTransparency = if selected == p.id then 0.5 else 0
			table.insert(itemFrames, f)
		end
	end
	for _, f in ghostFrames do
		f:Destroy()
	end
	ghostFrames = {}
	local pv = TackleBoxUI.preview(ui)
	if pv then
		for _, r in pv.cells do
			local f = frame(r, if pv.valid then GHOST_OK else GHOST_BAD, 4, "Ghost")
			f.BackgroundTransparency = 0.35
			table.insert(ghostFrames, f)
		end
	end
	local c = TackleBoxUI.cursor(ui)
	local r = TackleBoxUI.cellRect(ui, c.x, c.y)
	cursorFrame.Position = UDim2.fromOffset(r.x, r.y)
	status.Text = string.format("state %s   selected %s   cursor (%d, %d)", TackleBoxUI.state(ui), tostring(selected), c.x, c.y)
end

-- ---------------------------------------------------------------- the "net"
-- What pointerUp / cursorSelect would send over FishingNet; here the local box plays the server and
-- its items() output plays the replication back into setItems.
local function send(action)
	if not action then
		return
	end
	print(string.format("[TackleBoxUI sandbox] would send move { id = %d, rot = %d, x = %d, y = %d }", action.id, action.rot, action.x, action.y))
	local ok, why = TackleBox.move(box, action.id, action.rot, action.x, action.y)
	print("[TackleBoxUI sandbox] server verdict:", ok, why)
	TackleBoxUI.setItems(ui, TackleBox.items(box))
end

-- ---------------------------------------------------------------- the verbs, one device layer
local function pointerDown(pos)
	TackleBoxUI.pointerDown(ui, pos.X, pos.Y)
	redraw()
end
local function pointerMove(pos)
	TackleBoxUI.pointerMove(ui, pos.X, pos.Y)
	redraw()
end
local function pointerUp(pos)
	send(TackleBoxUI.pointerUp(ui, pos.X, pos.Y))
	redraw()
end
local function rotate()
	TackleBoxUI.rotate(ui)
	redraw()
end
local function cancel()
	TackleBoxUI.cancel(ui)
	redraw()
end
local function cursorMove(dx, dy)
	TackleBoxUI.cursorMove(ui, dx, dy)
	redraw()
end
local function cursorSelect()
	send(TackleBoxUI.cursorSelect(ui))
	redraw()
end

local KEY_VERBS = {
	[Enum.KeyCode.R] = rotate,
	[Enum.KeyCode.Backspace] = cancel,
	[Enum.KeyCode.Left] = function() cursorMove(-1, 0) end,
	[Enum.KeyCode.Right] = function() cursorMove(1, 0) end,
	[Enum.KeyCode.Up] = function() cursorMove(0, -1) end,
	[Enum.KeyCode.Down] = function() cursorMove(0, 1) end,
	[Enum.KeyCode.Return] = cursorSelect,
	[Enum.KeyCode.ButtonX] = rotate,
	[Enum.KeyCode.ButtonB] = cancel,
	[Enum.KeyCode.DPadLeft] = function() cursorMove(-1, 0) end,
	[Enum.KeyCode.DPadRight] = function() cursorMove(1, 0) end,
	[Enum.KeyCode.DPadUp] = function() cursorMove(0, -1) end,
	[Enum.KeyCode.DPadDown] = function() cursorMove(0, 1) end,
	[Enum.KeyCode.ButtonA] = cursorSelect,
}

UserInputService.InputBegan:Connect(function(input, _processed)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		pointerDown(input.Position)
	elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.Gamepad1 then
		local verb = KEY_VERBS[input.KeyCode]
		if verb then
			verb()
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, _processed)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
		pointerMove(input.Position)
	end
end)

UserInputService.InputEnded:Connect(function(input, _processed)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		pointerUp(input.Position)
	end
end)

redraw()
print("[TackleBoxUI sandbox] ready: drag with the mouse or a touch, R / X rotates, Backspace / B cancels, arrows or D-pad + Return / A for the cursor")
