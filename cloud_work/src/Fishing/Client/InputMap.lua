--!strict
-- InputMap (About Fishing F1, WS-I touch and gamepad; Cloud, 2026-10-08; design/WSI_touch_gamepad.md)
-- The one device layer: raw mouse, keyboard, touch, gamepad and phone-gyro events arrive as plain
-- tables; out go the exact calls InputController makes for the mouse today, in mouse-pixel-equivalent
-- units, chosen by one state x device mapping table (ROWS). describe() reads the same table for the
-- options screen's controls page, so the table has one source. Pure: no Roblox globals; the Roblox
-- adapter that builds the tables from UserInputService is InputMapAdapter.client.lua.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * sink (opts.sink): the ten functions InputController owns today, named from the design note:
--     rodDelta(dx, dy) px, aimTurn(yawRate, pitchRate) in -1..1 of the full turn rate, orbit(dx, dy)
--     px for CameraAF.addLook, press(), reelStart() / reelStop() (the hold on / off messages),
--     cancel(), catchDone() (InputController.sendCatchDone), castGesture({ t, dx, dy }) (CastGesture's
--     sample feed, px and the client clock), toggleBox() (the tackle box screen, WS-T).
--   * setState(name): InputController (or the state cue from FishingNetClient) calls it on every
--     state change before the first event of the new state. The map starts in Walking.
--   * step(dt): RunService.RenderStepped -> map:step(dt); a held right stick orbits per second here.
--   * opts: the C.Input gains (WSI section 2) and the C.Options rows (WSH_options_panel_additions.md:
--     MouseSensitivity, TouchSensitivity, GamepadSensitivity, InvertY, HoldToToggleReel) are read once
--     in new(); the panel re-creates the map or calls setOption(key, value) on a change.
--   * Key names "R" (reel), "Space" (hook set / catch done), "Escape" (cancel) and "Tab" (tackle box)
--     stand in for InputController's real bindings (the note's "today's binding"): Dev1 renames them
--     in KEY_INPUT below and in the adapter; the rows do not change.
-- Design decisions a dev must know:
--   * Sensitivity and invert Y act HERE, once: orbit(dx, dy) leaves already scaled by the active
--     device's sensitivity with dy's sign flipped when InvertY is on, and aimTurn's pitchRate carries
--     the same flip. CameraAF.addLook must therefore multiply by the base 0.044 deg/px only (or keep
--     its own scaling and hand this module 1.0 / false), never both. The rod (rodDelta, castGesture)
--     is never scaled or inverted: CastGesture's windows must not drift with a camera option.
--   * The gamepad rod is travel, the gamepad orbit is rate. In Aiming the right stick's CHANGE of
--     position x GamepadRodGainPxPerUnit is the rod delta, emitted on the stick event (a back-then-
--     forward snap is a 300 px flick in a few frames, the mouse's shape; a stick held still moves
--     nothing, like a mouse held still). In the orbit beats the held deflection x GamepadOrbitPxPerS
--     x dt is the orbit, emitted from step(dt). Stick y is up-positive, mouse dy is down-positive, so
--     dy = -y x gain on both paths.
--   * Every rod delta in Aiming also goes to castGesture as { t = clock(), dx, dy }: this module does
--     not detect flicks; CastGesture's windows judge the stream, as they do for the mouse today.
--   * One reel at a time, held by the source that started it (mouse 1, the R key, L2, R2 or one touch
--     on the REEL button); only that source's release stops it. A hold carries across a state change
--     into a reel state (set the hook with R2 in HookWindow, keep it in, the reel starts in Hooked), and
--     the reel is forced off on leaving Presenting / Retrieving / Inspected / HookWindow / Hooked and
--     on cancel. HoldToToggleReel makes a down toggle it and a release do nothing.
--   * R2 has mouse 1's whole role by state (press in HookWindow and Inspected, reel in Presenting,
--     Retrieving and Hooked, done in CatchScene), with hysteresis: a press registers when the value
--     crosses GamepadTriggerPressAt (0.25) upward and arms again only once it falls to
--     GamepadTriggerReleaseAt (0.20) or below. L2 is reel only; A and R1 are digital hook sets.
--   * Touch regions come from the renderer (right half "rod", left half "camera", buttons by name);
--     a finger keeps the region it began in. In Aiming the camera region is a virtual thumbstick:
--     the offset from the touch's start point over TouchAimStickRadiusPx, clamped to -1..1, is the
--     aim-turn rate; lifting the finger emits aimTurn(0, 0).
--   * Phone gyro feeds the rod only when GyroCastEnabled (off by default, the note's ruling 4); off,
--     the events are counted in stats().gyro and ignored, so the gamepad-gyro stub is the same path.
-- No Roblox globals.

local InputMap = {}
InputMap.__index = InputMap

export type State = "Walking" | "Aiming" | "Flight" | "Presenting" | "Retrieving" | "Inspected" | "HookWindow" | "Hooked" | "CatchScene" | "Holding"
export type Device = "mouse" | "touch" | "gamepad" | "gyro"
export type Action = "orbit" | "rod" | "aimTurn" | "press" | "reel" | "cancel" | "catchDone" | "toggleBox"

export type Sample = { t: number, dx: number, dy: number }
export type Sink = {
	rodDelta: (dx: number, dy: number) -> (),
	aimTurn: (yawRate: number, pitchRate: number) -> (),
	orbit: (dx: number, dy: number) -> (),
	press: () -> (),
	reelStart: () -> (),
	reelStop: () -> (),
	cancel: () -> (),
	catchDone: () -> (),
	castGesture: (sample: Sample) -> (),
	toggleBox: () -> (),
}

export type Opts = {
	sink: Sink,
	clock: () -> number, -- seconds; stamps castGesture samples
	-- gains (C.Input, WSI section 2)
	touchRodGainPxPerPx: number?, -- 2.0: a thumb drag is about half a mouse flick for the same intent
	touchOrbitGainPxPerPx: number?, -- 2.0: the note's TouchOrbitDegPerPx 0.09 over the mouse's 0.044
	touchAimStickRadiusPx: number?, -- 60: the virtual thumbstick's full deflection in Aiming
	touchHookTapAnywhere: boolean?, -- true: a tap on the rod region is the hook set in HookWindow
	gamepadRodGainPxPerUnit: number?, -- 150: 1.0 of right-stick travel = 150 px of mouse
	gamepadOrbitPxPerS: number?, -- 150: px per second at full deflection in the orbit beats
	gamepadDeadzone: number?, -- 0.15 per axis
	gamepadStickCurve: number?, -- 1.0 (linear); the note's 2.0 is a feel-pass knob
	gamepadTriggerPressAt: number?, -- 0.25
	gamepadTriggerReleaseAt: number?, -- 0.20: the trigger must fall to this to arm again
	gyroCastEnabled: boolean?, -- false
	gyroCastGainPxPerDeg: number?, -- 6.0
	-- options (C.Options, WSH)
	mouseSensitivity: number?, -- 1.0, 0.5..2.0
	touchSensitivity: number?,
	gamepadSensitivity: number?,
	invertY: boolean?, -- false
	holdToToggleReel: boolean?, -- false
}

export type Row = { device: Device, input: string, states: { State }, action: Action, needs: string? }
export type Stats = {
	ignored: number,
	malformed: number,
	gyro: number,
	rodDelta: number,
	aimTurn: number,
	orbit: number,
	press: number,
	reelStart: number,
	reelStop: number,
	cancel: number,
	catchDone: number,
	castGesture: number,
	toggleBox: number,
}

-- raw events, one shape per device (the adapter builds them; tests build them by hand)
export type MouseEvent = { kind: string, dx: number?, dy: number?, button: number?, key: string?, down: boolean? }
export type TouchEvent = { kind: string, id: any, x: number, y: number, region: string }
export type GamepadEvent = { kind: string, which: string?, x: number?, y: number?, value: number?, name: string?, down: boolean? }
export type GyroEvent = { kind: string, dx: number, dy: number }

type Touch = { region: string, x: number, y: number, startX: number, startY: number, stickOn: boolean }
type Trigger = { value: number, held: boolean }
type Fields = {
	_sink: Sink,
	_clock: () -> number,
	_touchRodGain: number,
	_touchOrbitGain: number,
	_touchStickRadius: number,
	_gamepadRodGain: number,
	_gamepadOrbitPxPerS: number,
	_deadzone: number,
	_curve: number,
	_pressAt: number,
	_releaseAt: number,
	_gyroGain: number,
	_mouseSens: number,
	_touchSens: number,
	_gamepadSens: number,
	_invertY: boolean,
	_holdToToggle: boolean,
	_flags: { [string]: boolean },
	_state: State,
	_stats: Stats,
	_keys: { [string]: boolean },
	_mouse1: boolean,
	_keyR: boolean,
	_touches: { [any]: Touch },
	_left: { x: number, y: number },
	_right: { x: number, y: number },
	_triggers: { [string]: Trigger },
	_reelOn: boolean,
	_reelSource: string?,
	_lastAim: { yaw: number, pitch: number },
}
export type InputMap = typeof(setmetatable({} :: Fields, InputMap))

-- ---------------------------------------------------------------- the mapping table (one source)
InputMap.STATES = { "Walking", "Aiming", "Flight", "Presenting", "Retrieving", "Inspected", "HookWindow", "Hooked", "CatchScene", "Holding" } :: { State }
InputMap.DEVICES = { "mouse", "touch", "gamepad", "gyro" } :: { Device }

local ORBIT: { State } = { "Walking", "Presenting", "Retrieving", "Inspected", "Holding" } -- the orbit beats
local PRESS: { State } = { "HookWindow", "Inspected" } -- the hook set (Inspected = the early press FishJudge judges)
local REEL_START: { State } = { "Presenting", "Retrieving", "Inspected", "Hooked" } -- where a reel may start (WSH 4.3)
local REEL_HOLD: { State } = { "Presenting", "Retrieving", "Inspected", "HookWindow", "Hooked" } -- where a held reel continues
local MOUSE1_REEL: { State } = { "Presenting", "Retrieving", "Hooked" } -- mouse 1 and R2 press in Inspected, so they reel only here
local CANCEL: { State } = { "Aiming", "Presenting", "Retrieving", "Inspected" }
local BOX: { State } = { "Walking", "Holding" }

-- Cells of the note's section 5 table, one row per (device, input, action). "needs" names an option
-- that must be on for the row to exist; describe() and the dispatch both honour it.
InputMap.ROWS = {
	-- mouse + keyboard
	{ device = "mouse", input = "move", states = ORBIT, action = "orbit" },
	{ device = "mouse", input = "move", states = { "Aiming" }, action = "rod" },
	{ device = "mouse", input = "button1", states = PRESS, action = "press" },
	{ device = "mouse", input = "button1", states = MOUSE1_REEL, action = "reel" },
	{ device = "mouse", input = "button1", states = { "CatchScene" }, action = "catchDone" },
	{ device = "mouse", input = "W/A/S/D", states = { "Aiming" }, action = "aimTurn" },
	{ device = "mouse", input = "Space", states = PRESS, action = "press" },
	{ device = "mouse", input = "Space", states = { "CatchScene" }, action = "catchDone" },
	{ device = "mouse", input = "R", states = REEL_START, action = "reel" },
	{ device = "mouse", input = "Escape", states = CANCEL, action = "cancel" },
	{ device = "mouse", input = "Tab", states = BOX, action = "toggleBox" },
	-- touch (regions from the renderer: right half "rod", left half "camera", buttons by name)
	{ device = "touch", input = "rod", states = ORBIT, action = "orbit" },
	{ device = "touch", input = "rod", states = { "Aiming" }, action = "rod" },
	{ device = "touch", input = "rod", states = { "HookWindow" }, action = "press", needs = "touchHookTapAnywhere" },
	{ device = "touch", input = "camera", states = ORBIT, action = "orbit" },
	{ device = "touch", input = "camera", states = { "Aiming" }, action = "aimTurn" },
	{ device = "touch", input = "button:hook", states = PRESS, action = "press" },
	{ device = "touch", input = "button:reel", states = REEL_START, action = "reel" },
	{ device = "touch", input = "button:cancel", states = CANCEL, action = "cancel" },
	{ device = "touch", input = "button:box", states = BOX, action = "toggleBox" },
	{ device = "touch", input = "anywhere", states = { "CatchScene" }, action = "catchDone" },
	-- gamepad
	{ device = "gamepad", input = "rightStick", states = ORBIT, action = "orbit" },
	{ device = "gamepad", input = "rightStick", states = { "Aiming" }, action = "rod" },
	{ device = "gamepad", input = "leftStick", states = { "Aiming" }, action = "aimTurn" },
	{ device = "gamepad", input = "R2", states = PRESS, action = "press" },
	{ device = "gamepad", input = "R2", states = MOUSE1_REEL, action = "reel" },
	{ device = "gamepad", input = "R2", states = { "CatchScene" }, action = "catchDone" },
	{ device = "gamepad", input = "L2", states = REEL_START, action = "reel" },
	{ device = "gamepad", input = "A", states = PRESS, action = "press" },
	{ device = "gamepad", input = "A", states = { "CatchScene" }, action = "catchDone" },
	{ device = "gamepad", input = "R1", states = PRESS, action = "press" },
	{ device = "gamepad", input = "B", states = CANCEL, action = "cancel" },
	{ device = "gamepad", input = "L1", states = CANCEL, action = "cancel" },
	{ device = "gamepad", input = "X", states = BOX, action = "toggleBox" },
	{ device = "gamepad", input = "Start", states = { "CatchScene" }, action = "catchDone" },
	-- phone gyro (UserInputService.InputChanged with UserInputType.Gyro; off by default)
	{ device = "gyro", input = "rotation", states = { "Aiming" }, action = "rod", needs = "gyroCastEnabled" },
} :: { Row }

local STATE_SET: { [string]: boolean } = {}
for _, s in InputMap.STATES do
	STATE_SET[s] = true
end
local DEVICE_SET: { [string]: boolean } = {}
for _, d in InputMap.DEVICES do
	DEVICE_SET[d] = true
end
local function setOf(list: { State }): { [string]: boolean }
	local set = {}
	for _, s in list do
		set[s] = true
	end
	return set
end
local REEL_START_SET = setOf(REEL_START)
local REEL_HOLD_SET = setOf(REEL_HOLD)

-- LOOKUP[device][input][state] = row; built once, refusing two actions for one cell
local LOOKUP: { [string]: { [string]: { [string]: Row } } } = {}
for _, row in InputMap.ROWS do
	assert(DEVICE_SET[row.device], "InputMap.ROWS: unknown device " .. tostring(row.device))
	local byInput = LOOKUP[row.device]
	if byInput == nil then
		byInput = {}
		LOOKUP[row.device] = byInput
	end
	local byState = byInput[row.input]
	if byState == nil then
		byState = {}
		byInput[row.input] = byState
	end
	for _, s in row.states do
		assert(STATE_SET[s], "InputMap.ROWS: unknown state " .. tostring(s))
		assert(byState[s] == nil, "InputMap.ROWS: two actions for " .. row.device .. " " .. row.input .. " in " .. s)
		byState[s] = row
	end
end

-- keyboard: a key name to its table input ("today's binding" names; Dev1 renames)
local KEY_INPUT: { [string]: string } = {
	W = "W/A/S/D",
	A = "W/A/S/D",
	S = "W/A/S/D",
	D = "W/A/S/D",
	R = "R",
	Escape = "Escape",
	Space = "Space",
	Tab = "Tab",
}

-- ---------------------------------------------------------------- helpers
local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp(v: number, lo: number, hi: number): number
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function numberOpt(o: { [string]: any }, key: string, default: number, lo: number, hi: number): number
	local v = o[key]
	if v == nil then
		return default
	end
	if not finite(v) or v < lo or v > hi then
		error(string.format("InputMap.new: opts.%s must be a number in %g..%g", key, lo, hi))
	end
	return v
end

local function boolOpt(o: { [string]: any }, key: string, default: boolean): boolean
	local v = o[key]
	if v == nil then
		return default
	end
	if typeof(v) ~= "boolean" then
		error("InputMap.new: opts." .. key .. " must be a boolean")
	end
	return v
end

local SINK_NAMES = { "rodDelta", "aimTurn", "orbit", "press", "reelStart", "reelStop", "cancel", "catchDone", "castGesture", "toggleBox" }

-- ---------------------------------------------------------------- construction
function InputMap.new(opts: Opts): InputMap
	if typeof(opts) ~= "table" then
		error("InputMap.new: opts table required")
	end
	local o: { [string]: any } = opts :: any
	local sink = o.sink
	if typeof(sink) ~= "table" then
		error("InputMap.new: opts.sink table required")
	end
	for _, name in SINK_NAMES do
		if typeof(sink[name]) ~= "function" then
			error("InputMap.new: opts.sink." .. name .. " must be a function")
		end
	end
	if typeof(o.clock) ~= "function" then
		error("InputMap.new: opts.clock function required")
	end
	local pressAt = numberOpt(o, "gamepadTriggerPressAt", 0.25, 0.01, 1)
	local releaseAt = numberOpt(o, "gamepadTriggerReleaseAt", 0.20, 0, 1)
	if releaseAt >= pressAt then
		error("InputMap.new: opts.gamepadTriggerReleaseAt must be below gamepadTriggerPressAt")
	end
	local self: Fields = {
		_sink = sink,
		_clock = o.clock,
		_touchRodGain = numberOpt(o, "touchRodGainPxPerPx", 2.0, 0.01, 100),
		_touchOrbitGain = numberOpt(o, "touchOrbitGainPxPerPx", 2.0, 0.01, 100),
		_touchStickRadius = numberOpt(o, "touchAimStickRadiusPx", 60, 1, 10000),
		_gamepadRodGain = numberOpt(o, "gamepadRodGainPxPerUnit", 150, 0.01, 100000),
		_gamepadOrbitPxPerS = numberOpt(o, "gamepadOrbitPxPerS", 150, 0.01, 100000),
		_deadzone = numberOpt(o, "gamepadDeadzone", 0.15, 0, 0.99),
		_curve = numberOpt(o, "gamepadStickCurve", 1.0, 0.1, 10),
		_pressAt = pressAt,
		_releaseAt = releaseAt,
		_gyroGain = numberOpt(o, "gyroCastGainPxPerDeg", 6.0, 0.01, 1000),
		_mouseSens = numberOpt(o, "mouseSensitivity", 1.0, 0.01, 100),
		_touchSens = numberOpt(o, "touchSensitivity", 1.0, 0.01, 100),
		_gamepadSens = numberOpt(o, "gamepadSensitivity", 1.0, 0.01, 100),
		_invertY = boolOpt(o, "invertY", false),
		_holdToToggle = boolOpt(o, "holdToToggleReel", false),
		_flags = {
			touchHookTapAnywhere = boolOpt(o, "touchHookTapAnywhere", true),
			gyroCastEnabled = boolOpt(o, "gyroCastEnabled", false),
		},
		_state = "Walking",
		_stats = {
			ignored = 0,
			malformed = 0,
			gyro = 0,
			rodDelta = 0,
			aimTurn = 0,
			orbit = 0,
			press = 0,
			reelStart = 0,
			reelStop = 0,
			cancel = 0,
			catchDone = 0,
			castGesture = 0,
			toggleBox = 0,
		},
		_keys = {},
		_mouse1 = false,
		_keyR = false,
		_touches = {},
		_left = { x = 0, y = 0 },
		_right = { x = 0, y = 0 },
		_triggers = { L2 = { value = 0, held = false }, R2 = { value = 0, held = false } },
		_reelOn = false,
		_reelSource = nil,
		_lastAim = { yaw = 0, pitch = 0 },
	}
	return setmetatable(self, InputMap)
end

-- Changes one option after construction (the panel's live slider): the five C.Options keys plus the
-- two row flags. Returns nil, reason on a bad key or value.
function InputMap.setOption(self: InputMap, key: string, value: any): (boolean?, string?)
	if key == "mouseSensitivity" or key == "touchSensitivity" or key == "gamepadSensitivity" then
		if not finite(value) or value <= 0 then
			return nil, key .. " must be a positive number"
		end
		if key == "mouseSensitivity" then
			self._mouseSens = value
		elseif key == "touchSensitivity" then
			self._touchSens = value
		else
			self._gamepadSens = value
		end
		return true, nil
	elseif key == "invertY" or key == "holdToToggleReel" or key == "touchHookTapAnywhere" or key == "gyroCastEnabled" then
		if typeof(value) ~= "boolean" then
			return nil, key .. " must be a boolean"
		end
		if key == "invertY" then
			self._invertY = value
		elseif key == "holdToToggleReel" then
			self._holdToToggle = value
		else
			self._flags[key] = value
		end
		return true, nil
	end
	return nil, "unknown option " .. tostring(key)
end

-- ---------------------------------------------------------------- the table, read
local function rowFor(self: InputMap, device: Device, input: string): Row?
	local byInput = LOOKUP[device][input]
	if byInput == nil then
		return nil
	end
	local row = byInput[self._state]
	if row ~= nil and row.needs ~= nil and not self._flags[row.needs :: string] then
		return nil
	end
	return row
end

-- The rows for one state and device, in table order, as { input, action } pairs for the controls
-- page. Rows gated by an option that is off are left out, as the dispatch leaves them out.
function InputMap.describe(self: InputMap, state: State, device: Device): { { input: string, action: Action } }
	if not STATE_SET[state] then
		error("InputMap.describe: unknown state " .. tostring(state))
	end
	if not DEVICE_SET[device] then
		error("InputMap.describe: unknown device " .. tostring(device))
	end
	local out = {}
	for _, row in InputMap.ROWS do
		if row.device == device and (row.needs == nil or self._flags[row.needs :: string]) then
			for _, s in row.states do
				if s == state then
					table.insert(out, { input = row.input, action = row.action })
					break
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- the emitters (each sink call in one place)
local function ignored(self: InputMap): (nil, string)
	self._stats.ignored += 1
	return nil, "ignored"
end

local function malformed(self: InputMap, reason: string): (nil, string)
	self._stats.malformed += 1
	return nil, reason
end

-- the one place invert Y acts: orbit's dy and aimTurn's pitchRate pass through it, the rod never does
local function pitchSign(self: InputMap): number
	return self._invertY and -1 or 1
end

-- the one place sensitivity acts
local function emitOrbit(self: InputMap, dx: number, dy: number, sens: number)
	self._stats.orbit += 1
	self._sink.orbit(dx * sens, dy * sens * pitchSign(self))
end

local function emitRod(self: InputMap, dx: number, dy: number)
	self._stats.rodDelta += 1
	self._sink.rodDelta(dx, dy)
	self._stats.castGesture += 1
	self._sink.castGesture({ t = self._clock(), dx = dx, dy = dy })
end

local function emitAim(self: InputMap, yaw: number, pitch: number)
	local p = pitch * pitchSign(self)
	self._lastAim.yaw, self._lastAim.pitch = yaw, p
	self._stats.aimTurn += 1
	self._sink.aimTurn(yaw, p)
end

local function emitPress(self: InputMap)
	self._stats.press += 1
	self._sink.press()
end

local function emitCatchDone(self: InputMap)
	self._stats.catchDone += 1
	self._sink.catchDone()
end

local function emitToggleBox(self: InputMap)
	self._stats.toggleBox += 1
	self._sink.toggleBox()
end

local function reelStart(self: InputMap, source: string)
	self._reelOn, self._reelSource = true, source
	self._stats.reelStart += 1
	self._sink.reelStart()
end

local function reelStop(self: InputMap)
	self._reelOn, self._reelSource = false, nil
	self._stats.reelStop += 1
	self._sink.reelStop()
end

-- a reel-like input went down in a state whose row says "reel"
local function reelDown(self: InputMap, source: string)
	if self._holdToToggle then
		if self._reelOn then
			reelStop(self)
		else
			reelStart(self, source)
		end
	elseif not self._reelOn then
		reelStart(self, source)
	end
end

-- a reel-like input was released, in any state: only the source that holds the reel stops it
local function reelUp(self: InputMap, source: string): boolean
	if self._reelOn and not self._holdToToggle and self._reelSource == source then
		reelStop(self)
		return true
	end
	return false
end

local function emitCancel(self: InputMap)
	if self._reelOn then
		reelStop(self)
	end
	self._stats.cancel += 1
	self._sink.cancel()
end

-- a digital input (button, key, trigger crossing) against its row
local function digital(self: InputMap, row: Row, down: boolean, source: string): string
	if down then
		local a = row.action
		if a == "press" then
			emitPress(self)
		elseif a == "reel" then
			reelDown(self, source)
		elseif a == "cancel" then
			emitCancel(self)
		elseif a == "catchDone" then
			emitCatchDone(self)
		elseif a == "toggleBox" then
			emitToggleBox(self)
		end
	end
	return row.action
end

-- the W/A/S/D rates from the keys held: D - A for yaw, W - S for pitch (up positive)
local function keyRates(self: InputMap): (number, number)
	local k = self._keys
	local yaw = (k.D and 1 or 0) - (k.A and 1 or 0)
	local pitch = (k.W and 1 or 0) - (k.S and 1 or 0)
	return yaw, pitch
end

-- deadzone (cut-off per axis, no rescale) then the response curve, clamped to -1..1
local function shape(self: InputMap, v: number): number
	local a = math.abs(v)
	if a < self._deadzone then
		return 0
	end
	if a > 1 then
		a = 1
	end
	if self._curve ~= 1 then
		a = a ^ self._curve
	end
	return v < 0 and -a or a
end

-- the reel-like source physically held whose row in the current state is "reel", for the carry-over
local function heldReelSource(self: InputMap): string?
	local function reels(device: Device, input: string): boolean
		local row = rowFor(self, device, input)
		return row ~= nil and row.action == "reel"
	end
	if self._mouse1 and reels("mouse", "button1") then
		return "mouse1"
	end
	if self._keyR and reels("mouse", "R") then
		return "keyR"
	end
	if self._triggers.L2.held and reels("gamepad", "L2") then
		return "L2"
	end
	if self._triggers.R2.held and reels("gamepad", "R2") then
		return "R2"
	end
	for id, t in self._touches do
		if t.region == "button:reel" and reels("touch", "button:reel") then
			return "touch:" .. tostring(id)
		end
	end
	return nil
end

-- ---------------------------------------------------------------- state
function InputMap.state(self: InputMap): State
	return self._state
end

function InputMap.isReeling(self: InputMap): boolean
	return self._reelOn
end

function InputMap.setState(self: InputMap, state: State)
	if not STATE_SET[state] then
		error("InputMap.setState: unknown state " .. tostring(state))
	end
	local prev = self._state
	if state == prev then
		return
	end
	self._state = state
	-- the reel: forced off outside the hold states; a held source carries into a reel state (hold mode)
	if self._reelOn and not REEL_HOLD_SET[state] then
		reelStop(self)
	end
	if not self._reelOn and not self._holdToToggle and REEL_START_SET[state] then
		local src = heldReelSource(self)
		if src ~= nil then
			reelStart(self, src)
		end
	end
	-- the aim turn: leaving Aiming zeroes a running rate; entering it emits the rate already held
	if prev == "Aiming" then
		if self._lastAim.yaw ~= 0 or self._lastAim.pitch ~= 0 then
			emitAim(self, 0, 0)
		end
		for _, t in self._touches do
			t.stickOn = false
		end
	elseif state == "Aiming" then
		local yaw, pitch = keyRates(self)
		if yaw == 0 and pitch == 0 then
			yaw, pitch = self._left.x, self._left.y
		end
		if yaw ~= 0 or pitch ~= 0 then
			emitAim(self, yaw, pitch)
		end
	end
end

-- ---------------------------------------------------------------- mouse + keyboard
-- { kind = "move", dx, dy } | { kind = "button", button = 1|2, down } | { kind = "key", key, down }
-- Returns the action taken (the row's name), or nil and "ignored" / the malformed reason.
function InputMap.mouse(self: InputMap, ev: MouseEvent): (string?, string?)
	if typeof(ev) ~= "table" then
		return malformed(self, "mouse: event table required")
	end
	if ev.kind == "move" then
		if not finite(ev.dx) or not finite(ev.dy) then
			return malformed(self, "mouse move: dx, dy must be finite numbers")
		end
		local dx, dy = ev.dx :: number, ev.dy :: number
		local row = rowFor(self, "mouse", "move")
		if row == nil then
			return ignored(self)
		end
		if row.action == "orbit" then
			emitOrbit(self, dx, dy, self._mouseSens)
		else
			emitRod(self, dx, dy)
		end
		return row.action, nil
	elseif ev.kind == "button" then
		if (ev.button ~= 1 and ev.button ~= 2) or typeof(ev.down) ~= "boolean" then
			return malformed(self, "mouse button: button must be 1 or 2 and down a boolean")
		end
		local down = ev.down :: boolean
		if ev.button == 2 then
			return ignored(self)
		end
		self._mouse1 = down
		local stopped = not down and reelUp(self, "mouse1")
		local row = rowFor(self, "mouse", "button1")
		if row == nil then
			if stopped then
				return "reel", nil
			end
			return ignored(self)
		end
		return digital(self, row, down, "mouse1"), nil
	elseif ev.kind == "key" then
		local input = typeof(ev.key) == "string" and KEY_INPUT[ev.key :: string] or nil
		if input == nil or typeof(ev.down) ~= "boolean" then
			return malformed(self, "mouse key: key must be W/A/S/D/R/Escape/Space/Tab and down a boolean")
		end
		local key, down = ev.key :: string, ev.down :: boolean
		local stopped = false
		if input == "W/A/S/D" then
			self._keys[key] = down or nil
		elseif key == "R" then
			self._keyR = down
			stopped = not down and reelUp(self, "keyR")
		end
		local row = rowFor(self, "mouse", input)
		if row == nil then
			if stopped then
				return "reel", nil
			end
			return ignored(self)
		end
		if row.action == "aimTurn" then
			emitAim(self, keyRates(self))
			return row.action, nil
		end
		return digital(self, row, down, "keyR"), nil
	end
	return malformed(self, "mouse: kind must be move, button or key")
end

-- ---------------------------------------------------------------- touch
-- { kind = "began"|"moved"|"ended", id, x, y, region = "rod"|"camera"|"button:<name>" }; a finger keeps
-- the region it began in. In CatchScene a began anywhere is catchDone.
function InputMap.touch(self: InputMap, ev: TouchEvent): (string?, string?)
	if typeof(ev) ~= "table" then
		return malformed(self, "touch: event table required")
	end
	if ev.kind ~= "began" and ev.kind ~= "moved" and ev.kind ~= "ended" then
		return malformed(self, "touch: kind must be began, moved or ended")
	end
	if ev.id == nil or (typeof(ev.id) ~= "number" and typeof(ev.id) ~= "string") then
		return malformed(self, "touch: id must be a number or a string")
	end
	if not finite(ev.x) or not finite(ev.y) then
		return malformed(self, "touch: x, y must be finite numbers")
	end
	if ev.kind == "began" then
		if typeof(ev.region) ~= "string" then
			return malformed(self, "touch began: region must be a string")
		end
		self._touches[ev.id] = { region = ev.region, x = ev.x, y = ev.y, startX = ev.x, startY = ev.y, stickOn = false }
		local anywhere = rowFor(self, "touch", "anywhere")
		if anywhere ~= nil then
			return digital(self, anywhere, true, "touch:" .. tostring(ev.id)), nil
		end
		local row = rowFor(self, "touch", ev.region)
		if row == nil then
			return ignored(self)
		end
		-- orbit, rod and the virtual stick move nothing on a began; the digital rows act now
		return digital(self, row, true, "touch:" .. tostring(ev.id)), nil
	end
	local t = self._touches[ev.id]
	if t == nil then
		return ignored(self)
	end
	if ev.kind == "moved" then
		local dx, dy = ev.x - t.x, ev.y - t.y
		t.x, t.y = ev.x, ev.y
		local row = rowFor(self, "touch", t.region)
		if row == nil then
			return ignored(self)
		end
		if row.action == "orbit" then
			emitOrbit(self, dx * self._touchOrbitGain, dy * self._touchOrbitGain, self._touchSens)
		elseif row.action == "rod" then
			emitRod(self, dx * self._touchRodGain, dy * self._touchRodGain)
		elseif row.action == "aimTurn" then
			local r = self._touchStickRadius
			t.stickOn = true
			emitAim(self, clamp((ev.x - t.startX) / r, -1, 1), clamp(-(ev.y - t.startY) / r, -1, 1))
		end
		return row.action, nil
	end
	-- ended
	self._touches[ev.id] = nil
	local stopped = reelUp(self, "touch:" .. tostring(ev.id))
	local row = rowFor(self, "touch", t.region)
	if row == nil then
		if stopped then
			return "reel", nil
		end
		return ignored(self)
	end
	if row.action == "aimTurn" and t.stickOn then
		emitAim(self, 0, 0)
	end
	return row.action, nil
end

-- ---------------------------------------------------------------- gamepad
-- { kind = "stick", which = "left"|"right", x, y } | { kind = "trigger", which = "L2"|"R2", value }
-- | { kind = "button", name, down }. Stick y is up-positive (Roblox); mouse dy is down-positive.
function InputMap.gamepad(self: InputMap, ev: GamepadEvent): (string?, string?)
	if typeof(ev) ~= "table" then
		return malformed(self, "gamepad: event table required")
	end
	if ev.kind == "stick" then
		if (ev.which ~= "left" and ev.which ~= "right") or not finite(ev.x) or not finite(ev.y) then
			return malformed(self, "gamepad stick: which must be left or right and x, y finite numbers")
		end
		local x, y = shape(self, ev.x :: number), shape(self, ev.y :: number)
		if ev.which == "left" then
			self._left.x, self._left.y = x, y
			local row = rowFor(self, "gamepad", "leftStick")
			if row == nil then
				return ignored(self)
			end
			emitAim(self, x, y)
			return row.action, nil
		end
		local px, py = self._right.x, self._right.y
		self._right.x, self._right.y = x, y
		local row = rowFor(self, "gamepad", "rightStick")
		if row == nil then
			return ignored(self)
		end
		if row.action == "rod" then
			local dx, dy = (x - px) * self._gamepadRodGain, -(y - py) * self._gamepadRodGain
			if dx ~= 0 or dy ~= 0 then
				emitRod(self, dx, dy)
			end
		end
		-- orbit reads the held position from step(dt)
		return row.action, nil
	elseif ev.kind == "trigger" then
		if (ev.which ~= "L2" and ev.which ~= "R2") or not finite(ev.value) then
			return malformed(self, "gamepad trigger: which must be L2 or R2 and value a finite number")
		end
		local which = ev.which :: string
		local tr = self._triggers[which]
		local value = clamp(ev.value :: number, 0, 1)
		local wasHeld = tr.held
		tr.value = value
		local stopped = false
		if not wasHeld and value >= self._pressAt then
			tr.held = true
		elseif wasHeld and value <= self._releaseAt then
			tr.held = false
			stopped = reelUp(self, which)
		end
		local row = rowFor(self, "gamepad", which)
		if row == nil then
			if stopped then
				return "reel", nil
			end
			return ignored(self)
		end
		if tr.held and not wasHeld then
			return digital(self, row, true, which), nil
		end
		return row.action, nil
	elseif ev.kind == "button" then
		if typeof(ev.name) ~= "string" or typeof(ev.down) ~= "boolean" then
			return malformed(self, "gamepad button: name must be a string and down a boolean")
		end
		local row = rowFor(self, "gamepad", ev.name :: string)
		if row == nil then
			return ignored(self)
		end
		return digital(self, row, ev.down :: boolean, "button:" .. (ev.name :: string)), nil
	end
	return malformed(self, "gamepad: kind must be stick, trigger or button")
end

-- ---------------------------------------------------------------- phone gyro
-- { kind = "rotation", dx, dy }: degrees of device rotation this sample, already in mouse direction
-- (forward pitch = negative dy). Counted always; the rod only when gyroCastEnabled and Aiming.
function InputMap.gyro(self: InputMap, ev: GyroEvent): (string?, string?)
	if typeof(ev) ~= "table" or ev.kind ~= "rotation" then
		return malformed(self, "gyro: kind must be rotation")
	end
	if not finite(ev.dx) or not finite(ev.dy) then
		return malformed(self, "gyro: dx, dy must be finite numbers")
	end
	self._stats.gyro += 1
	local row = rowFor(self, "gyro", "rotation")
	if row == nil then
		return ignored(self)
	end
	emitRod(self, ev.dx * self._gyroGain, ev.dy * self._gyroGain)
	return row.action, nil
end

-- ---------------------------------------------------------------- per frame
-- The renderer calls step(dt) every RenderStepped: a held right stick orbits at GamepadOrbitPxPerS x
-- deflection x dt in the orbit beats. Nothing else is time-based here.
function InputMap.step(self: InputMap, dt: number)
	if not finite(dt) or dt < 0 then
		error("InputMap.step: dt must be a finite number >= 0")
	end
	local r = self._right
	if dt == 0 or (r.x == 0 and r.y == 0) then
		return
	end
	local row = rowFor(self, "gamepad", "rightStick")
	if row ~= nil and row.action == "orbit" then
		local k = self._gamepadOrbitPxPerS * dt
		emitOrbit(self, r.x * k, -r.y * k, self._gamepadSens)
	end
end

-- ---------------------------------------------------------------- stats
function InputMap.stats(self: InputMap): Stats
	return table.clone(self._stats)
end

return InputMap
