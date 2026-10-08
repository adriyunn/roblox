--!nocheck
--!nolint UnknownGlobal
-- InputMapAdapter.client.lua (About Fishing F1, WS-I touch and gamepad; Cloud, 2026-10-08; design/WSI_touch_gamepad.md)
-- TEMPORARY WIRING REFERENCE. COMPILE-ONLY (luau-compile --null at -O0/-O1/-O2; never run offline,
-- never shipped as is). Dev1 and Dev2 merge it into InputController; nothing requires it.
-- A LocalScript that turns UserInputService, ContextActionService, gamepad and device-rotation
-- events into the plain tables Fishing/Client/InputMap.lua consumes, computes the touch regions
-- from the viewport (right half "rod", left half "camera", the buttons by name), reads the WSH
-- option attributes off the LocalPlayer, and drives InputMap.step(dt) from RenderStepped.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * sink: every function below forwards to a stub that prints; Dev1 points each at the real
--     InputController function (the mouse path's own calls: the rod / CastGesture feed, the aim turn,
--     CameraAF.addLook for orbit, press, the reel hold on / off, cancel, sendCatchDone, the tackle box).
--   * onStateChanged(name): connect it to InputController's state change so InputMap.setState runs
--     before the first event of the new state. It also disables the PlayerModule controls outside
--     Walking and Holding (the note, section 3) and shows the touch buttons for the state (section 3 table).
--   * opts.clock: the clock InputController stamps the press with today (os.clock here; Dev1 checks).
--   * C.Input gains: fill opts from FishingConfig once WordAgent's WSI_FishingConfig_input patch lands;
--     the defaults in InputMap.new are the note's starting values.
--   * Gyro: DeviceRotationChanged's Delta axes and signs are a Studio check on a phone (section 3):
--     a forward flick must reach InputMap as negative dy.
--   * ROD_SPLIT is 0.5 per the renderer spec; the note's 40% left region (the thumbstick) is the knob.
-- Design decisions a dev must know: see the header of InputMap.lua; this file adds none.

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fishing = ReplicatedStorage:WaitForChild("Fishing")
local InputMap = require(Fishing:WaitForChild("Client"):WaitForChild("InputMap"))
-- local InputController = require(Fishing.Client.InputController)  -- Dev1: the real sink targets
-- local C = require(Fishing.FishingConfig)                           -- the C.Input gains

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ROD_SPLIT = 0.5 -- x < ROD_SPLIT x viewport width is the camera region, the rest the rod

-- ---------------------------------------------------------------- the sink (Dev1 replaces the stubs)
local function stub(name)
	return function(...)
		print("[InputMap] " .. name, ...)
	end
end
local sink = {
	rodDelta = stub("rodDelta"), -- InputController's rod / CastGesture sample feed (dx, dy px)
	aimTurn = stub("aimTurn"), -- the WSA2b aim turn (yawRate, pitchRate in -1..1 of the full rate)
	orbit = stub("orbit"), -- CameraAF.addLook(dx, dy): sensitivity and invert already applied here
	press = stub("press"), -- the hook set, stamped at this call
	reelStart = stub("reelStart"), -- the reel hold on message
	reelStop = stub("reelStop"), -- the reel hold off message
	cancel = stub("cancel"), -- InputController's cancel / reset
	catchDone = stub("catchDone"), -- InputController.sendCatchDone()
	castGesture = stub("castGesture"), -- CastGesture's sample { t, dx, dy }, if the feed is separate from rodDelta
	toggleBox = stub("toggleBox"), -- the tackle box screen (WS-T)
}

-- ---------------------------------------------------------------- options (WSH attributes on the LocalPlayer)
local OPTION_ATTRS = {
	mouseSensitivity = "OptMouseSensitivity",
	touchSensitivity = "OptTouchSensitivity",
	gamepadSensitivity = "OptGamepadSensitivity",
	invertY = "OptInvertY",
	holdToToggleReel = "OptHoldToToggleReel",
	gyroCastEnabled = "OptGyroCastEnabled",
}

local opts = { sink = sink, clock = os.clock }
for key, attr in OPTION_ATTRS do
	local v = player:GetAttribute(attr)
	if v ~= nil then
		opts[key] = v
	end
end
-- opts.touchRodGainPxPerPx = C.Input.TouchRodGainPxPerPx; opts.gamepadRodGainPxPerUnit = ...; etc.
local TRIGGER_PRESS_AT = opts.gamepadTriggerPressAt or 0.25

local map = InputMap.new(opts)

for key, attr in OPTION_ATTRS do
	player:GetAttributeChangedSignal(attr):Connect(function()
		local ok, why = map:setOption(key, player:GetAttribute(attr))
		if not ok then
			warn("[InputMap] option " .. key .. ": " .. tostring(why))
		end
	end)
end

-- ---------------------------------------------------------------- touch buttons (ContextActionService, the note's cluster)
-- Positions are px from the bottom-right corner at 1x (TouchButtonPx 84); Dev2 scales by the option.
local BUTTONS = {
	{ name = "cancel", title = "CANCEL", pos = UDim2.new(1, -260, 1, -120), states = { Aiming = true, Presenting = true, Retrieving = true, Inspected = true } },
	{ name = "reel", title = "REEL", pos = UDim2.new(1, -120, 1, -120), states = { Presenting = true, Retrieving = true, Inspected = true, HookWindow = true, Hooked = true } },
	{ name = "hook", title = "HOOK", pos = UDim2.new(1, -120, 1, -240), states = { HookWindow = true, Inspected = true } },
	{ name = "box", title = "BOX", pos = UDim2.new(1, -120, 1, -120), states = { Walking = true, Holding = true } },
}

-- InputMap wants a number or a string as the touch id; the InputObject is the identity
local touchIds = setmetatable({}, { __mode = "k" })
local nextTouchId = 0
local function touchId(input)
	local id = touchIds[input]
	if id == nil then
		nextTouchId += 1
		id = nextTouchId
		touchIds[input] = id
	end
	return id
end

local function bindButton(b)
	local actionName = "AF_" .. b.name
	ContextActionService:BindAction(actionName, function(_, state, input)
		if state == Enum.UserInputState.Begin or state == Enum.UserInputState.End then
			local p = input.Position
			map:touch({
				kind = state == Enum.UserInputState.Begin and "began" or "ended",
				id = touchId(input),
				x = p.X,
				y = p.Y,
				region = "button:" .. b.name,
			})
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:SetPosition(actionName, b.pos)
	ContextActionService:SetTitle(actionName, b.title)
end

local bound = {}
local function showButtonsFor(state)
	if not UserInputService.TouchEnabled then
		return
	end
	for _, b in BUTTONS do
		local want = b.states[state] == true
		if want and not bound[b.name] then
			bindButton(b)
			bound[b.name] = true
		elseif not want and bound[b.name] then
			ContextActionService:UnbindAction("AF_" .. b.name)
			bound[b.name] = nil
		end
	end
end

-- ---------------------------------------------------------------- state (Dev1 connects InputController's change)
local controls = nil
pcall(function()
	local PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	controls = PlayerModule:GetControls()
end)

local function onStateChanged(name)
	map:setState(name)
	if controls then
		if name == "Walking" or name == "Holding" then
			controls:Enable()
		else
			controls:Disable()
		end
	end
	showButtonsFor(name)
end
-- InputController.StateChanged:Connect(onStateChanged)   -- Dev1: the real signal
onStateChanged("Walking")

-- ---------------------------------------------------------------- screen regions for a bare touch
local function regionAt(x)
	if x < camera.ViewportSize.X * ROD_SPLIT then
		return "camera"
	end
	return "rod"
end

-- ---------------------------------------------------------------- UserInputService -> plain tables
local KEY_NAMES = {
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.D] = "D",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.Escape] = "Escape",
	[Enum.KeyCode.Space] = "Space",
	[Enum.KeyCode.Tab] = "Tab",
}
local GAMEPAD_BUTTONS = {
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonL1] = "L1",
	[Enum.KeyCode.ButtonR1] = "R1",
	[Enum.KeyCode.ButtonStart] = "Start",
}
local TRIGGERS = {
	[Enum.KeyCode.ButtonL2] = "L2",
	[Enum.KeyCode.ButtonR2] = "R2",
}

local function onBeganOrEnded(input, gameProcessed, down)
	if gameProcessed then
		return -- a GUI took it (our own buttons arrive through ContextActionService)
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 then
		map:mouse({ kind = "button", button = 1, down = down })
	elseif t == Enum.UserInputType.MouseButton2 then
		map:mouse({ kind = "button", button = 2, down = down })
	elseif t == Enum.UserInputType.Keyboard then
		local name = KEY_NAMES[input.KeyCode]
		if name then
			map:mouse({ kind = "key", key = name, down = down })
		end
	elseif t == Enum.UserInputType.Touch then
		local p = input.Position
		map:touch({ kind = down and "began" or "ended", id = touchId(input), x = p.X, y = p.Y, region = regionAt(p.X) })
	elseif t == Enum.UserInputType.Gamepad1 then
		local name = GAMEPAD_BUTTONS[input.KeyCode]
		if name then
			map:gamepad({ kind = "button", name = name, down = down })
			return
		end
		local trigger = TRIGGERS[input.KeyCode]
		if trigger then
			-- section 4.3: InputBegan at Roblox's own threshold or Position.Z >= 0.25, whichever is first;
			-- both reach InputMap as the same trigger event, so the crossing fires once
			map:gamepad({ kind = "trigger", which = trigger, value = down and math.max(input.Position.Z, TRIGGER_PRESS_AT) or 0 })
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	onBeganOrEnded(input, gameProcessed, true)
end)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
	onBeganOrEnded(input, gameProcessed, false)
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseMovement then
		map:mouse({ kind = "move", dx = input.Delta.X, dy = input.Delta.Y })
	elseif t == Enum.UserInputType.Touch then
		if gameProcessed then
			return
		end
		local p = input.Position
		map:touch({ kind = "moved", id = touchId(input), x = p.X, y = p.Y, region = regionAt(p.X) })
	elseif t == Enum.UserInputType.Gamepad1 then
		local k = input.KeyCode
		if k == Enum.KeyCode.Thumbstick1 then
			map:gamepad({ kind = "stick", which = "left", x = input.Position.X, y = input.Position.Y })
		elseif k == Enum.KeyCode.Thumbstick2 then
			map:gamepad({ kind = "stick", which = "right", x = input.Position.X, y = input.Position.Y })
		elseif TRIGGERS[k] then
			map:gamepad({ kind = "trigger", which = TRIGGERS[k], value = input.Position.Z })
		end
	elseif t == Enum.UserInputType.Gyro then
		-- the same sample DeviceRotationChanged gives below; one of the two paths is enough (Studio check)
		local d = input.Delta
		map:gyro({ kind = "rotation", dx = math.deg(d.Y), dy = -math.deg(d.X) })
	end
end)

-- phone gyro (the note, section 3): Delta is the rotation since the last sample; forward pitch -> negative dy
if UserInputService.GyroscopeEnabled then
	UserInputService.DeviceRotationChanged:Connect(function(input, _cframe)
		local d = input.Delta
		map:gyro({ kind = "rotation", dx = math.deg(d.Y), dy = -math.deg(d.X) })
	end)
end

-- a held right stick orbits per second from here
RunService.RenderStepped:Connect(function(dt)
	map:step(dt)
end)

-- the one device-related value anywhere: an analytics attribute, never read by game code (section 7)
UserInputService.LastInputTypeChanged:Connect(function(lastType)
	player:SetAttribute("InputDevice", lastType.Name)
end)
