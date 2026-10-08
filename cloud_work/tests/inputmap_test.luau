--!strict
-- inputmap_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves InputMap against a spy sink: for each device one representative event per state producing
-- the right sink call with the numbers written out (a 10 px touch move -> rodDelta(20, 0); a held
-- right stick at 0.8 -> orbit 150 x 0.8 x dt per axis over two frames; a stick swing -1 -> +1 ->
-- rodDelta 150 then -300); the events the table ignores counted in stats().ignored; the R2 crossing
-- firing once per crossing (0.1 -> 0.3 -> 0.2 -> 0.4 = two presses) with hysteresis at 0.20; the
-- deadzone; invert Y and sensitivity acting on orbit and aim turn but never on the rod; hold-to-toggle;
-- the reel carrying across a state change and forced off outside the reel states; cast flick samples
-- with increasing t; describe() agreeing with the conversions; a JSON round trip of the controls
-- table; negative controls (unknown state errors, unknown region ignored, NaN dropped and counted).
-- Run from this folder: luau inputmap_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("inputmap_test")
local InputMap = require("../src/Fishing/Client/InputMap")

-- ---------------------------------------------------------------- the spy sink and a fake clock
type Call = { name: string, args: { any } }
local calls: { Call } = {}
local now = 0

local SINK_NAMES = { "rodDelta", "aimTurn", "orbit", "press", "reelStart", "reelStop", "cancel", "catchDone", "castGesture", "toggleBox" }

local function spySink(): InputMap.Sink
	local sink: { [string]: any } = {}
	for _, name in SINK_NAMES do
		sink[name] = function(...: any)
			table.insert(calls, { name = name, args = { ... } })
		end
	end
	return sink :: any
end

local function make(opts: { [string]: any }?): InputMap.InputMap
	local o: { [string]: any } = opts or {}
	o.sink = spySink()
	o.clock = function()
		return now
	end
	return InputMap.new(o :: any)
end

local function reset()
	table.clear(calls)
end

local function names(): string
	local out = {}
	for _, c in calls do
		table.insert(out, c.name)
	end
	return table.concat(out, ",")
end

local function near(a: any, b: number): boolean
	return typeof(a) == "number" and math.abs(a - b) < 1e-9
end

-- exactly one call, of this name, with these numeric args
local function only(name: string, ...: number): boolean
	if #calls ~= 1 or calls[1].name ~= name then
		return false
	end
	local want = { ... }
	for i, w in want do
		if not near(calls[1].args[i], w) then
			return false
		end
	end
	return true
end

local function argsOf(i: number): { any }
	return calls[i].args
end

local function describeHas(map: InputMap.InputMap, state: InputMap.State, device: InputMap.Device, input: string, action: string): boolean
	for _, r in map:describe(state, device) do
		if r.input == input and r.action == action then
			return true
		end
	end
	return false
end

-- ================================================================ mouse + keyboard, one event per state
local m = make()
T.eq(m:state(), "Walking", "a new map starts in Walking")

reset()
m:mouse({ kind = "move", dx = 10, dy = -4 })
T.check(only("orbit", 10, -4), "Walking: a mouse move of (10, -4) orbits (10, -4) at sensitivity 1")
T.check(describeHas(m, "Walking", "mouse", "move", "orbit"), "describe(Walking, mouse) lists move -> orbit (cross-check 1)")

reset()
local act, why = m:mouse({ kind = "button", button = 1, down = true })
T.check(act == nil and why == "ignored" and #calls == 0 and m:stats().ignored == 1, "Walking: a press is not in the table: nil, ignored, counted, no call")
T.check(not describeHas(m, "Walking", "mouse", "button1", "press"), "describe(Walking, mouse) has no button1 row, as the ignored press says (cross-check 2)")
m:mouse({ kind = "button", button = 1, down = false })

m:setState("Aiming")
reset()
now = 1.5
m:mouse({ kind = "move", dx = 10, dy = -30 })
T.eq(names(), "rodDelta,castGesture", "Aiming: a mouse move is the rod and a CastGesture sample")
T.check(near(argsOf(1)[1], 10) and near(argsOf(1)[2], -30), "Aiming: rodDelta(10, -30) unscaled")
local sample = argsOf(2)[1]
T.check(near(sample.t, 1.5) and near(sample.dx, 10) and near(sample.dy, -30), "Aiming: the sample is { t = clock, dx = 10, dy = -30 }")

reset()
m:mouse({ kind = "key", key = "W", down = true })
T.check(only("aimTurn", 0, 1), "Aiming: W down -> aimTurn(0, 1)")
reset()
m:mouse({ kind = "key", key = "D", down = true })
T.check(only("aimTurn", 1, 1), "Aiming: D down with W held -> aimTurn(1, 1)")
reset()
m:mouse({ kind = "key", key = "W", down = false })
T.check(only("aimTurn", 1, 0), "Aiming: W up with D held -> aimTurn(1, 0)")
reset()
m:mouse({ kind = "key", key = "D", down = false })
T.check(only("aimTurn", 0, 0), "Aiming: D up -> aimTurn(0, 0)")
reset()
m:mouse({ kind = "key", key = "Escape", down = true })
T.check(only("cancel"), "Aiming: Escape -> cancel")
m:mouse({ kind = "key", key = "Escape", down = false })

m:setState("Flight")
reset()
local before = m:stats().ignored
m:mouse({ kind = "move", dx = 5, dy = 5 })
m:mouse({ kind = "button", button = 1, down = true })
m:mouse({ kind = "button", button = 1, down = false })
m:mouse({ kind = "key", key = "R", down = true })
m:mouse({ kind = "key", key = "R", down = false })
T.check(#calls == 0 and m:stats().ignored == before + 5, "Flight: a move, a press and the reel key are all ignored and counted (5)")

m:setState("Presenting")
reset()
m:mouse({ kind = "button", button = 1, down = true })
T.check(only("reelStart"), "Presenting: mouse 1 down -> reelStart")
reset()
m:mouse({ kind = "button", button = 1, down = false })
T.check(only("reelStop"), "Presenting: mouse 1 up -> reelStop")
reset()
m:mouse({ kind = "move", dx = 3, dy = 0 })
T.check(only("orbit", 3, 0), "Presenting: a mouse move orbits")

m:setState("Retrieving")
reset()
m:mouse({ kind = "button", button = 1, down = true })
m:mouse({ kind = "button", button = 1, down = false })
T.eq(names(), "reelStart,reelStop", "Retrieving: mouse 1 down / up = reelStart / reelStop")

m:setState("Inspected")
reset()
m:mouse({ kind = "button", button = 1, down = true })
T.check(only("press"), "Inspected: mouse 1 down is the (early) press, not the reel")
m:mouse({ kind = "button", button = 1, down = false })
reset()
m:mouse({ kind = "key", key = "R", down = true })
m:mouse({ kind = "key", key = "R", down = false })
T.eq(names(), "reelStart,reelStop", "Inspected: the R key reels (the crank while held)")

m:setState("HookWindow")
reset()
m:mouse({ kind = "button", button = 1, down = true })
T.check(only("press"), "HookWindow: mouse 1 down -> press")
m:mouse({ kind = "button", button = 1, down = false })
reset()
before = m:stats().ignored
m:mouse({ kind = "move", dx = 9, dy = 9 })
T.check(#calls == 0 and m:stats().ignored == before + 1, "HookWindow: a mouse move does not orbit (ignored)")

m:setState("Hooked")
reset()
m:mouse({ kind = "button", button = 1, down = true })
m:mouse({ kind = "button", button = 1, down = false })
T.eq(names(), "reelStart,reelStop", "Hooked: hold mouse 1 = reel, release = give line")

m:setState("CatchScene")
reset()
m:mouse({ kind = "button", button = 1, down = true })
m:mouse({ kind = "button", button = 1, down = false })
T.check(only("catchDone"), "CatchScene: a mouse 1 click -> catchDone, once")
reset()
m:mouse({ kind = "key", key = "Space", down = true })
T.check(only("catchDone"), "CatchScene: Space -> catchDone")
m:mouse({ kind = "key", key = "Space", down = false })

m:setState("Holding")
reset()
m:mouse({ kind = "move", dx = -2, dy = 1 })
T.check(only("orbit", -2, 1), "Holding: a mouse move orbits")
reset()
m:mouse({ kind = "key", key = "Tab", down = true })
T.check(only("toggleBox"), "Holding: Tab -> toggleBox")
m:mouse({ kind = "key", key = "Tab", down = false })
reset()
before = m:stats().ignored
m:mouse({ kind = "button", button = 2, down = true })
T.check(#calls == 0 and m:stats().ignored == before + 1, "mouse button 2 has no row anywhere: ignored")

-- ================================================================ touch, one event per state
local tm = make()
reset()
tm:touch({ kind = "began", id = 1, x = 500, y = 300, region = "rod" })
T.check(#calls == 0, "Walking: a touch began on the rod region moves nothing")
tm:touch({ kind = "moved", id = 1, x = 510, y = 296, region = "rod" })
T.check(only("orbit", 20, -8), "Walking: a rod drag of (10, -4) orbits (20, -8): touch orbit gain 2.0")
tm:touch({ kind = "ended", id = 1, x = 510, y = 296, region = "rod" })

tm:setState("Aiming")
reset()
now = 0
tm:touch({ kind = "began", id = 2, x = 600, y = 400, region = "rod" })
tm:touch({ kind = "moved", id = 2, x = 610, y = 400, region = "rod" })
T.eq(names(), "rodDelta,castGesture", "Aiming: a rod drag is rodDelta plus a cast sample")
T.check(near(argsOf(1)[1], 20) and near(argsOf(1)[2], 0), "Aiming: a touch move of 10 px -> rodDelta(20, 0) at TouchRodGainPxPerPx 2.0")
T.check(describeHas(tm, "Aiming", "touch", "rod", "rod"), "describe(Aiming, touch) lists rod -> rod (cross-check 3)")
-- a flick: three frames of a forward drag, the clock advancing
reset()
now = 0.016
tm:touch({ kind = "moved", id = 2, x = 610, y = 380, region = "rod" })
now = 0.032
tm:touch({ kind = "moved", id = 2, x = 610, y = 340, region = "rod" })
now = 0.048
tm:touch({ kind = "moved", id = 2, x = 610, y = 280, region = "rod" })
local s1, s2, s3 = argsOf(2)[1], argsOf(4)[1], argsOf(6)[1]
T.check(s1.t < s2.t and s2.t < s3.t and near(s1.t, 0.016) and near(s3.t, 0.048), "a cast flick produces samples with increasing t from the clock")
T.check(near(s1.dy, -40) and near(s2.dy, -80) and near(s3.dy, -120), "the flick samples carry the scaled dy (-40, -80, -120)")
-- the finger keeps the region it began in
reset()
tm:touch({ kind = "moved", id = 2, x = 620, y = 280, region = "camera" })
T.eq(names(), "rodDelta,castGesture", "a finger that began on the rod stays the rod when the renderer relabels it")
tm:touch({ kind = "ended", id = 2, x = 620, y = 280, region = "rod" })
-- the camera region in Aiming is a virtual thumbstick (radius 60 px)
reset()
tm:touch({ kind = "began", id = 3, x = 100, y = 300, region = "camera" })
tm:touch({ kind = "moved", id = 3, x = 130, y = 300, region = "camera" })
T.check(only("aimTurn", 0.5, 0), "Aiming: a camera drag of 30 px right -> aimTurn(0.5, 0)")
reset()
tm:touch({ kind = "moved", id = 3, x = 190, y = 240, region = "camera" })
T.check(only("aimTurn", 1, 1), "Aiming: 90 px right and 60 px up clamps to aimTurn(1, 1)")
reset()
tm:touch({ kind = "ended", id = 3, x = 190, y = 240, region = "camera" })
T.check(only("aimTurn", 0, 0), "Aiming: lifting the camera finger -> aimTurn(0, 0)")
reset()
tm:touch({ kind = "began", id = 4, x = 700, y = 100, region = "button:cancel" })
T.check(only("cancel"), "Aiming: the CANCEL button -> cancel")
tm:touch({ kind = "ended", id = 4, x = 700, y = 100, region = "button:cancel" })

tm:setState("Flight")
reset()
before = tm:stats().ignored
tm:touch({ kind = "began", id = 5, x = 500, y = 300, region = "rod" })
tm:touch({ kind = "moved", id = 5, x = 520, y = 300, region = "rod" })
tm:touch({ kind = "ended", id = 5, x = 520, y = 300, region = "rod" })
tm:touch({ kind = "began", id = 6, x = 700, y = 500, region = "button:reel" })
tm:touch({ kind = "ended", id = 6, x = 700, y = 500, region = "button:reel" })
T.check(#calls == 0 and tm:stats().ignored == before + 5, "Flight: a rod drag and a REEL tap are ignored and counted (5)")

tm:setState("Presenting")
reset()
tm:touch({ kind = "began", id = 7, x = 700, y = 500, region = "button:reel" })
T.check(only("reelStart"), "Presenting: REEL down -> reelStart")
reset()
tm:touch({ kind = "ended", id = 7, x = 700, y = 500, region = "button:reel" })
T.check(only("reelStop"), "Presenting: REEL up -> reelStop")

tm:setState("Retrieving")
reset()
tm:touch({ kind = "began", id = 8, x = 100, y = 300, region = "camera" })
tm:touch({ kind = "moved", id = 8, x = 105, y = 300, region = "camera" })
T.check(only("orbit", 10, 0), "Retrieving: a camera drag of 5 px orbits (10, 0)")
tm:touch({ kind = "ended", id = 8, x = 105, y = 300, region = "camera" })

tm:setState("Inspected")
reset()
tm:touch({ kind = "began", id = 9, x = 700, y = 380, region = "button:hook" })
T.check(only("press"), "Inspected: the dimmed HOOK button still presses (the early press)")
tm:touch({ kind = "ended", id = 9, x = 700, y = 380, region = "button:hook" })

tm:setState("HookWindow")
reset()
tm:touch({ kind = "began", id = 10, x = 650, y = 350, region = "rod" })
T.check(only("press"), "HookWindow: a tap on the rod region is the hook set (TouchHookTapAnywhere on)")
tm:touch({ kind = "ended", id = 10, x = 650, y = 350, region = "rod" })
reset()
tm:touch({ kind = "began", id = 11, x = 700, y = 380, region = "button:hook" })
T.check(only("press"), "HookWindow: the HOOK button -> press")
tm:touch({ kind = "ended", id = 11, x = 700, y = 380, region = "button:hook" })

tm:setState("Hooked")
reset()
tm:touch({ kind = "began", id = 12, x = 700, y = 500, region = "button:reel" })
T.check(only("reelStart"), "Hooked: REEL down -> reelStart")
reset()
before = tm:stats().ignored
tm:touch({ kind = "began", id = 13, x = 500, y = 300, region = "rod" })
tm:touch({ kind = "moved", id = 13, x = 520, y = 300, region = "rod" })
T.check(#calls == 0 and tm:stats().ignored == before + 2, "Hooked: a rod drag is ignored (the chase beat owns the camera)")
tm:touch({ kind = "ended", id = 13, x = 520, y = 300, region = "rod" })
reset()
tm:touch({ kind = "ended", id = 12, x = 700, y = 500, region = "button:reel" })
T.check(only("reelStop"), "Hooked: REEL up -> reelStop")

tm:setState("CatchScene")
reset()
tm:touch({ kind = "began", id = 14, x = 100, y = 100, region = "camera" })
T.check(only("catchDone"), "CatchScene: a tap anywhere -> catchDone")
tm:touch({ kind = "ended", id = 14, x = 100, y = 100, region = "camera" })
reset()
tm:touch({ kind = "began", id = 15, x = 700, y = 500, region = "button:reel" })
T.check(only("catchDone"), "CatchScene: a tap on a button is still anywhere -> catchDone")
tm:touch({ kind = "ended", id = 15, x = 700, y = 500, region = "button:reel" })

tm:setState("Holding")
reset()
tm:touch({ kind = "began", id = 16, x = 700, y = 500, region = "button:box" })
T.check(only("toggleBox"), "Holding: the BOX button -> toggleBox")
tm:touch({ kind = "ended", id = 16, x = 700, y = 500, region = "button:box" })

-- the tap-anywhere option off: the rod tap in HookWindow is ignored and the row leaves describe()
local tm2 = make({ touchHookTapAnywhere = false })
tm2:setState("HookWindow")
reset()
tm2:touch({ kind = "began", id = 1, x = 650, y = 350, region = "rod" })
T.check(#calls == 0 and tm2:stats().ignored == 1, "TouchHookTapAnywhere off: a rod tap in HookWindow is ignored")
T.check(not describeHas(tm2, "HookWindow", "touch", "rod", "press") and describeHas(tm, "HookWindow", "touch", "rod", "press"), "describe(HookWindow, touch) lists the rod tap only when the option is on")

-- ================================================================ gamepad, one event per state
local g = make()
reset()
g:gamepad({ kind = "stick", which = "right", x = 0.8, y = 0.8 })
T.check(#calls == 0, "Walking: a right-stick event alone orbits nothing (step does)")
g:step(0.1)
T.check(only("orbit", 150 * 0.8 * 0.1, -150 * 0.8 * 0.1), "Walking: step(0.1) with the right stick at 0.8 -> orbit(12, -12): 150 x 0.8 x dt per axis, y up = dy negative")
reset()
g:step(0.1)
T.check(only("orbit", 12, -12), "a second frame orbits the same again (per second, not per event)")
reset()
g:gamepad({ kind = "stick", which = "right", x = 0, y = 0 })
g:step(0.1)
T.check(#calls == 0, "a centred stick orbits nothing")
reset()
before = g:stats().ignored
g:gamepad({ kind = "stick", which = "left", x = 1, y = 0 })
T.check(#calls == 0 and g:stats().ignored == before + 1, "Walking: the left stick is the PlayerModule's walk: ignored here")
g:gamepad({ kind = "stick", which = "left", x = 0, y = 0 })
reset()
g:gamepad({ kind = "button", name = "X", down = true })
T.check(only("toggleBox"), "Walking: X -> toggleBox")
g:gamepad({ kind = "button", name = "X", down = false })

g:setState("Aiming")
reset()
g:gamepad({ kind = "stick", which = "right", x = 0, y = -1 })
T.eq(names(), "rodDelta,castGesture", "Aiming: a right-stick pull back is a rod delta and a sample")
T.check(near(argsOf(1)[1], 0) and near(argsOf(1)[2], 150), "Aiming: stick 0 -> -1 (back) = rodDelta(0, 150): mouse pulled back")
reset()
g:gamepad({ kind = "stick", which = "right", x = 0, y = 1 })
T.check(near(argsOf(1)[1], 0) and near(argsOf(1)[2], -300), "Aiming: stick -1 -> +1 (the snap forward) = rodDelta(0, -300): a 300 px flick")
reset()
g:step(0.1)
T.check(#calls == 0, "Aiming: a held right stick moves the rod no further (travel, not rate)")
g:gamepad({ kind = "stick", which = "right", x = 0, y = 0 })
reset()
g:gamepad({ kind = "stick", which = "left", x = 0.5, y = -0.5 })
T.check(only("aimTurn", 0.5, -0.5), "Aiming: left stick (0.5, -0.5) -> aimTurn(0.5, -0.5)")
reset()
g:gamepad({ kind = "stick", which = "left", x = 0.1, y = 0.1 })
T.check(only("aimTurn", 0, 0), "deadzone: a left stick at (0.1, 0.1) is (0, 0)")
reset()
g:gamepad({ kind = "stick", which = "left", x = 0.14, y = 0.9 })
T.check(only("aimTurn", 0, 0.9), "deadzone: 0.14 is cut per axis, 0.9 passes unchanged")
g:gamepad({ kind = "stick", which = "left", x = 0, y = 0 })
reset()
g:gamepad({ kind = "button", name = "B", down = true })
T.check(only("cancel"), "Aiming: B -> cancel")
g:gamepad({ kind = "button", name = "B", down = false })

g:setState("Flight")
reset()
before = g:stats().ignored
g:gamepad({ kind = "stick", which = "right", x = 1, y = 0 })
g:step(0.1)
g:gamepad({ kind = "trigger", which = "L2", value = 1 })
g:gamepad({ kind = "trigger", which = "L2", value = 0 })
g:gamepad({ kind = "stick", which = "right", x = 0, y = 0 })
T.check(#calls == 0 and g:stats().ignored == before + 4, "Flight: the right stick, step and the L2 reel are ignored and counted (4)")

g:setState("Presenting")
reset()
g:gamepad({ kind = "trigger", which = "L2", value = 0.3 })
T.check(only("reelStart"), "Presenting: L2 past 0.25 -> reelStart")
reset()
g:gamepad({ kind = "trigger", which = "L2", value = 0.1 })
T.check(only("reelStop"), "Presenting: L2 back to 0.1 -> reelStop")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0.5 })
g:gamepad({ kind = "trigger", which = "R2", value = 0 })
T.eq(names(), "reelStart,reelStop", "Presenting: R2 has mouse 1's role: hold = reel")
reset()
g:gamepad({ kind = "button", name = "L1", down = true })
T.check(only("cancel"), "Presenting: L1 -> cancel (reset)")
g:gamepad({ kind = "button", name = "L1", down = false })

g:setState("Retrieving")
reset()
g:gamepad({ kind = "stick", which = "right", x = -0.5, y = 0 })
g:step(0.2)
T.check(only("orbit", -15, 0), "Retrieving: right stick (-0.5, 0) for 0.2 s -> orbit(-15, 0)")
g:gamepad({ kind = "stick", which = "right", x = 0, y = 0 })
reset()
g:gamepad({ kind = "trigger", which = "L2", value = 0.9 })
g:gamepad({ kind = "trigger", which = "L2", value = 0 })
T.eq(names(), "reelStart,reelStop", "Retrieving: L2 reels")

g:setState("Inspected")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0.5 })
T.check(only("press"), "Inspected: R2 crossing -> press (the early press), as mouse 1")
g:gamepad({ kind = "trigger", which = "R2", value = 0 })
reset()
g:gamepad({ kind = "button", name = "A", down = true })
T.check(only("press"), "Inspected: A -> press")
reset()
g:gamepad({ kind = "button", name = "A", down = false })
T.check(#calls == 0 and g:stats().ignored == before + 4, "a release of a mapped button makes no call and is not counted as ignored")
reset()
g:gamepad({ kind = "button", name = "R1", down = true })
T.check(only("press"), "Inspected: R1 -> press (ruling 3's second binding)")
g:gamepad({ kind = "button", name = "R1", down = false })

g:setState("HookWindow")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0.1 })
g:gamepad({ kind = "trigger", which = "R2", value = 0.3 })
g:gamepad({ kind = "trigger", which = "R2", value = 0.2 })
g:gamepad({ kind = "trigger", which = "R2", value = 0.4 })
T.eq(names(), "press,press", "HookWindow: R2 0.1 -> 0.3 -> 0.2 -> 0.4 = two presses, one per crossing")
T.check(describeHas(g, "HookWindow", "gamepad", "R2", "press"), "describe(HookWindow, gamepad) lists R2 -> press (cross-check 4)")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0.22 })
g:gamepad({ kind = "trigger", which = "R2", value = 0.4 })
T.check(#calls == 0, "hysteresis: falling only to 0.22 does not re-arm, so 0.4 again is no press")
g:gamepad({ kind = "trigger", which = "R2", value = 0.2 })
g:gamepad({ kind = "trigger", which = "R2", value = 0.4 })
T.check(only("press"), "hysteresis: falling to 0.20 re-arms; the next rise presses")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0 })
g:gamepad({ kind = "trigger", which = "R2", value = 0.25 })
T.check(only("press"), "exactly 0.25 registers the press")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0 })
g:gamepad({ kind = "trigger", which = "R2", value = 1.5 })
T.check(only("press"), "a trigger value above 1 is clamped, not refused")
g:gamepad({ kind = "trigger", which = "R2", value = 0 })

g:setState("Hooked")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0.6 })
g:gamepad({ kind = "trigger", which = "R2", value = 0.1 })
T.eq(names(), "reelStart,reelStop", "Hooked: R2 hold = reel, release = give line")
reset()
before = g:stats().ignored
g:gamepad({ kind = "button", name = "B", down = true })
g:gamepad({ kind = "button", name = "B", down = false })
g:gamepad({ kind = "stick", which = "right", x = 1, y = 0 })
g:step(0.1)
g:gamepad({ kind = "stick", which = "right", x = 0, y = 0 })
T.check(#calls == 0 and g:stats().ignored == before + 4, "Hooked: no cancel and no orbit (the chase beat): ignored")

g:setState("CatchScene")
reset()
g:gamepad({ kind = "button", name = "A", down = true })
g:gamepad({ kind = "button", name = "A", down = false })
T.check(only("catchDone"), "CatchScene: A -> catchDone")
reset()
g:gamepad({ kind = "button", name = "Start", down = true })
g:gamepad({ kind = "button", name = "Start", down = false })
T.check(only("catchDone"), "CatchScene: Start -> catchDone")
reset()
g:gamepad({ kind = "trigger", which = "R2", value = 0.9 })
g:gamepad({ kind = "trigger", which = "R2", value = 0 })
T.check(only("catchDone"), "CatchScene: an R2 pull -> catchDone, once")

g:setState("Holding")
reset()
g:gamepad({ kind = "button", name = "X", down = true })
T.check(only("toggleBox"), "Holding: X -> toggleBox")
g:gamepad({ kind = "button", name = "X", down = false })
reset()
g:gamepad({ kind = "stick", which = "right", x = 0, y = -1 })
g:step(0.05)
T.check(only("orbit", 0, 7.5), "Holding: right stick down (y -1) for 0.05 s -> orbit(0, 7.5)")
g:gamepad({ kind = "stick", which = "right", x = 0, y = 0 })
reset()
before = g:stats().ignored
g:gamepad({ kind = "button", name = "Y", down = true })
T.check(#calls == 0 and g:stats().ignored == before + 1, "Y has no row: ignored")

-- ================================================================ phone gyro
local gy = make()
gy:setState("Aiming")
reset()
gy:gyro({ kind = "rotation", dx = 0, dy = -2 })
T.check(#calls == 0 and gy:stats().gyro == 1 and gy:stats().ignored == 1, "gyro off by default: the sample is counted in stats().gyro and ignored (the stub)")
local gy2 = make({ gyroCastEnabled = true })
gy2:setState("Aiming")
reset()
gy2:gyro({ kind = "rotation", dx = 0, dy = -2 })
T.eq(names(), "rodDelta,castGesture", "gyro on, Aiming: a rotation sample feeds the rod")
T.check(near(argsOf(1)[1], 0) and near(argsOf(1)[2], -12), "gyro: 2 deg of forward pitch -> rodDelta(0, -12) at 6 px/deg")
gy2:setState("Walking")
reset()
gy2:gyro({ kind = "rotation", dx = 0, dy = -2 })
T.check(#calls == 0 and gy2:stats().ignored == 1, "gyro on, Walking: ignored")

-- ================================================================ options: invert Y, sensitivity, hold-to-toggle
local inv = make({ invertY = true })
reset()
inv:mouse({ kind = "move", dx = 10, dy = 4 })
T.check(only("orbit", 10, -4), "invertY: orbit's dy flips: (10, 4) -> (10, -4)")
inv:setState("Aiming")
reset()
inv:mouse({ kind = "key", key = "W", down = true })
T.check(only("aimTurn", 0, -1), "invertY: W -> aimTurn(0, -1)")
inv:mouse({ kind = "key", key = "W", down = false })
reset()
inv:mouse({ kind = "move", dx = 0, dy = -30 })
T.check(near(argsOf(1)[2], -30), "invertY never touches the rod: rodDelta(0, -30)")
inv:setState("Walking")
reset()
inv:gamepad({ kind = "stick", which = "right", x = 0, y = 0.8 })
inv:step(0.1)
T.check(only("orbit", 0, 12), "invertY on the gamepad: stick up for 0.1 s -> orbit(0, 12)")

local sens = make({ mouseSensitivity = 2.0, gamepadSensitivity = 2.0, touchSensitivity = 0.5 })
reset()
sens:mouse({ kind = "move", dx = 10, dy = 4 })
T.check(only("orbit", 20, 8), "sensitivity 2.0 doubles the mouse orbit: (10, 4) -> (20, 8)")
reset()
sens:gamepad({ kind = "stick", which = "right", x = 0.8, y = 0.8 })
sens:step(0.1)
T.check(only("orbit", 24, -24), "sensitivity 2.0 doubles the gamepad orbit: (24, -24)")
sens:gamepad({ kind = "stick", which = "right", x = 0, y = 0 })
reset()
sens:touch({ kind = "began", id = 1, x = 500, y = 300, region = "rod" })
sens:touch({ kind = "moved", id = 1, x = 510, y = 300, region = "rod" })
T.check(only("orbit", 10, 0), "touch sensitivity 0.5 halves the touch orbit: 10 px -> (10, 0)")
sens:touch({ kind = "ended", id = 1, x = 510, y = 300, region = "rod" })
sens:setState("Aiming")
reset()
sens:mouse({ kind = "move", dx = 10, dy = 4 })
T.check(near(argsOf(1)[1], 10) and near(argsOf(1)[2], 4), "sensitivity never touches the rod: rodDelta(10, 4)")
T.check(sens:setOption("mouseSensitivity", 0.5) == true, "setOption changes a sensitivity live")
sens:setState("Walking")
reset()
sens:mouse({ kind = "move", dx = 10, dy = 4 })
T.check(only("orbit", 5, 2), "after setOption(mouseSensitivity, 0.5): (10, 4) -> (5, 2)")
local okOpt, whyOpt = sens:setOption("bogus", 1)
T.check(okOpt == nil and typeof(whyOpt) == "string", "setOption refuses an unknown key with nil, reason")
okOpt, whyOpt = sens:setOption("invertY", "yes" :: any)
T.check(okOpt == nil and typeof(whyOpt) == "string", "setOption refuses a non-boolean invertY with nil, reason")

local tog = make({ holdToToggleReel = true })
tog:setState("Presenting")
reset()
tog:mouse({ kind = "button", button = 1, down = true })
tog:mouse({ kind = "button", button = 1, down = false })
T.check(only("reelStart") and tog:isReeling(), "hold-to-toggle: a tap turns the reel on; the release does nothing")
reset()
tog:mouse({ kind = "button", button = 1, down = true })
tog:mouse({ kind = "button", button = 1, down = false })
T.check(only("reelStop") and not tog:isReeling(), "hold-to-toggle: the next tap turns it off")
reset()
tog:gamepad({ kind = "trigger", which = "L2", value = 0.5 })
tog:gamepad({ kind = "trigger", which = "L2", value = 0 })
T.check(only("reelStart"), "hold-to-toggle on the gamepad: an L2 pull toggles on, the release does nothing")
reset()
tog:setState("CatchScene")
T.check(only("reelStop"), "hold-to-toggle: a state change out of the reel states forces the reel off")
T.check(tog:stats().reelStart == 2 and tog:stats().reelStop == 2, "exactly two reel on and two reel off messages")
tog:setState("HookWindow")
reset()
tog:mouse({ kind = "button", button = 1, down = true })
tog:mouse({ kind = "button", button = 1, down = false })
T.check(only("press"), "hold-to-toggle never applies to the hook set: in HookWindow a tap is a press")

-- ================================================================ the reel across states
local r = make()
r:setState("HookWindow")
reset()
r:gamepad({ kind = "trigger", which = "R2", value = 0.5 })
T.check(only("press"), "set the hook with R2 in HookWindow")
reset()
r:setState("Hooked")
T.check(only("reelStart") and r:isReeling(), "keep the trigger in: entering Hooked starts the reel (the hold carries over)")
reset()
r:gamepad({ kind = "trigger", which = "R2", value = 0 })
T.check(only("reelStop"), "letting the trigger out stops it")

r:setState("Presenting")
reset()
r:mouse({ kind = "button", button = 1, down = true })
r:setState("Flight")
T.eq(names(), "reelStart,reelStop", "a reel on in Presenting is forced off on a state change to Flight")
reset()
r:mouse({ kind = "button", button = 1, down = false })
T.check(#calls == 0, "the later release of that button makes no second stop")

r:setState("Inspected")
reset()
r:mouse({ kind = "key", key = "R", down = true })
r:setState("HookWindow")
r:setState("Hooked")
T.check(only("reelStart") and r:isReeling(), "a reel held from Inspected continues through HookWindow into Hooked (REEL still holds)")
reset()
r:mouse({ kind = "key", key = "R", down = false })
T.check(only("reelStop"), "and stops on the release")

r:setState("Presenting")
reset()
r:gamepad({ kind = "trigger", which = "L2", value = 0.5 })
r:mouse({ kind = "button", button = 1, down = true })
r:mouse({ kind = "button", button = 1, down = false })
T.check(only("reelStart") and r:isReeling(), "one reel at a time: a second source down and up neither restarts nor stops it")
reset()
r:gamepad({ kind = "trigger", which = "L2", value = 0 })
T.check(only("reelStop"), "only the source that started the reel stops it")
reset()
r:mouse({ kind = "button", button = 1, down = true })
r:mouse({ kind = "key", key = "Escape", down = true })
T.eq(names(), "reelStart,reelStop,cancel", "cancel stops the reel first, then cancels")
r:mouse({ kind = "key", key = "Escape", down = false })
r:mouse({ kind = "button", button = 1, down = false })
reset()
r:setState("HookWindow")
r:touch({ kind = "began", id = 1, x = 700, y = 500, region = "button:reel" })
T.check(#calls == 0 and r:stats().ignored >= 1, "HookWindow: a REEL press cannot start a reel (ignored)")
reset()
r:setState("Hooked")
T.check(only("reelStart") and r:isReeling(), "the REEL finger still down when Hooked begins starts the reel (the touch hold carries over)")
r:touch({ kind = "ended", id = 1, x = 700, y = 500, region = "button:reel" })
r:setState("Inspected")
reset()
r:touch({ kind = "began", id = 2, x = 700, y = 500, region = "button:reel" })
r:setState("HookWindow")
local lifted = r:touch({ kind = "ended", id = 2, x = 700, y = 500, region = "button:reel" })
T.check(names() == "reelStart,reelStop" and lifted == "reel", "a REEL finger lifted in HookWindow still stops the reel and reports reel, not ignored")

-- ================================================================ the aim turn across states
local a = make()
a:setState("Aiming")
reset()
a:mouse({ kind = "key", key = "W", down = true })
a:setState("Flight")
T.eq(names(), "aimTurn,aimTurn", "leaving Aiming with W held emits aimTurn(0, 0)")
T.check(near(argsOf(2)[1], 0) and near(argsOf(2)[2], 0), "the zeroing call is (0, 0)")
a:mouse({ kind = "key", key = "W", down = false })
a:setState("Walking")
reset()
a:mouse({ kind = "key", key = "D", down = true })
T.check(#calls == 0, "Walking: D is the walk, ignored here")
a:setState("Aiming")
T.check(only("aimTurn", 1, 0), "entering Aiming with D already held emits aimTurn(1, 0)")
a:mouse({ kind = "key", key = "D", down = false })
reset()
a:gamepad({ kind = "stick", which = "left", x = 0, y = 0.6 })
a:setState("Walking")
a:setState("Aiming")
T.eq(names(), "aimTurn,aimTurn,aimTurn", "a held left stick: the rate, (0, 0) on leaving, the rate again on re-entering Aiming")
T.check(near(argsOf(3)[1], 0) and near(argsOf(3)[2], 0.6), "the re-entry rate is the stick's (0, 0.6)")

-- ================================================================ describe: the table has one source
local d = make()
T.check(#d:describe("Flight", "mouse") == 0 and #d:describe("Flight", "touch") == 0 and #d:describe("Flight", "gamepad") == 0 and #d:describe("Flight", "gyro") == 0, "describe(Flight, *) is empty: no sink exists for steer, so nothing is mapped")
T.check(#d:describe("Walking", "gyro") == 0 and #make({ gyroCastEnabled = true }):describe("Aiming", "gyro") == 1, "describe(Aiming, gyro) has its one row only when the gyro is on")
local aimingGamepad = d:describe("Aiming", "gamepad")
T.check(aimingGamepad[1].input == "rightStick" and aimingGamepad[1].action == "rod" and aimingGamepad[2].input == "leftStick" and aimingGamepad[2].action == "aimTurn", "describe(Aiming, gamepad) starts rightStick -> rod, leftStick -> aimTurn in table order")
local known = { orbit = true, rod = true, aimTurn = true, press = true, reel = true, cancel = true, catchDone = true, toggleBox = true }
local rowsSeen, allKnown = 0, true
for _, st in InputMap.STATES do
	for _, dev in InputMap.DEVICES do
		for _, row in d:describe(st, dev) do
			rowsSeen += 1
			if not known[row.action] then
				allKnown = false
			end
		end
	end
end
T.check(rowsSeen > 60 and allKnown, "every describe row names one of the eight actions (" .. rowsSeen .. " rows over 10 states x 4 devices)")
T.throws(function()
	d:describe("Fighting" :: any, "mouse")
end, "unknown state", "describe with an unknown state errors")
T.throws(function()
	d:describe("Walking", "wheel" :: any)
end, "unknown device", "describe with an unknown device errors")

-- the controls table is plain data: a JSON round trip of every (state, device) page comes back equal
local pages: { [string]: any } = {}
for _, st in InputMap.STATES do
	for _, dev in InputMap.DEVICES do
		pages[st .. "/" .. dev] = d:describe(st, dev)
	end
end
local back = Stub.jsonDecode(Stub.jsonEncode(pages))
local function sameRows(x: { any }, y: { any }): boolean
	if #x ~= #y then
		return false
	end
	for i, rx in x do
		if rx.input ~= y[i].input or rx.action ~= y[i].action then
			return false
		end
	end
	return true
end
local roundTrip = true
for key, rows in pages do
	if not sameRows(rows, back[key]) then
		roundTrip = false
	end
end
T.check(roundTrip, "describe pages survive a JSON serialize round trip unchanged")
local statsBack = Stub.jsonDecode(Stub.jsonEncode(g:stats()))
T.check(statsBack.press == g:stats().press and statsBack.ignored == g:stats().ignored, "stats() survives a JSON round trip")

-- stats count what the spy saw
local sc = make()
reset()
sc:mouse({ kind = "move", dx = 1, dy = 1 })
sc:setState("Aiming")
sc:mouse({ kind = "move", dx = 1, dy = 1 })
sc:mouse({ kind = "key", key = "A", down = true })
sc:mouse({ kind = "key", key = "A", down = false })
sc:setState("HookWindow")
sc:mouse({ kind = "button", button = 1, down = true })
sc:mouse({ kind = "button", button = 1, down = false })
sc:setState("CatchScene")
sc:mouse({ kind = "button", button = 1, down = true })
local counted: { [string]: number } = {}
for _, c in calls do
	counted[c.name] = (counted[c.name] or 0) + 1
end
local st = sc:stats()
T.check(st.orbit == 1 and st.rodDelta == 1 and st.castGesture == 1 and st.aimTurn == 2 and st.press == 1 and st.catchDone == 1 and st.reelStart == 0, "stats() counts per sink call match the spy (orbit 1, rod 1, sample 1, aimTurn 2, press 1, done 1)")
T.check(counted.orbit == st.orbit and counted.aimTurn == st.aimTurn and counted.press == st.press and counted.catchDone == st.catchDone, "the spy agrees")

-- ================================================================ negative controls
local n = make()
T.throws(function()
	n:setState("Fighting" :: any)
end, "unknown state", "setState with an unknown state errors")
T.eq(n:state(), "Walking", "and the state is unchanged")
reset()
before = n:stats().ignored
n:touch({ kind = "began", id = 1, x = 10, y = 10, region = "minimap" })
n:touch({ kind = "moved", id = 1, x = 20, y = 10, region = "minimap" })
T.check(#calls == 0 and n:stats().ignored == before + 2 and n:stats().malformed == 0, "an unknown region is ignored (counted), not malformed")
n:touch({ kind = "ended", id = 1, x = 20, y = 10, region = "minimap" })
reset()
act, why = n:mouse({ kind = "move", dx = 0 / 0, dy = 0 })
T.check(act == nil and why ~= "ignored" and typeof(why) == "string" and #calls == 0 and n:stats().malformed == 1, "a mouse move with NaN dx is dropped with a reason and counted in malformed")
act, why = n:touch({ kind = "began", id = 2, x = math.huge, y = 0, region = "rod" })
T.check(act == nil and n:stats().malformed == 2, "a touch with an infinite x is dropped and counted")
act, why = n:gamepad({ kind = "stick", which = "right", x = 0, y = 0 / 0 })
T.check(act == nil and n:stats().malformed == 3, "a stick with NaN y is dropped and counted")
act, why = n:gyro({ kind = "rotation", dx = 0 / 0, dy = 0 })
T.check(act == nil and n:stats().malformed == 4 and n:stats().gyro == 0, "a gyro sample with NaN dx is dropped before it is counted as a sample")
act, why = n:gamepad({ kind = "trigger", which = "L3", value = 1 })
T.check(act == nil and n:stats().malformed == 5, "an unknown trigger name is malformed")
act, why = n:mouse({ kind = "key", key = "Q", down = true })
T.check(act == nil and n:stats().malformed == 6, "an unmapped key name is malformed (the adapter filters keys)")
act, why = n:touch({ kind = "moved", id = 99, x = 1, y = 1, region = "rod" })
T.check(act == nil and why == "ignored", "a moved for a finger that never began is ignored")
T.check(#calls == 0, "none of the bad events reached the sink")
T.throws(function()
	n:step(-1)
end, "dt", "step with a negative dt errors")
T.throws(function()
	n:step(0 / 0)
end, "dt", "step with NaN dt errors")
T.throws(function()
	InputMap.new({ sink = spySink() } :: any)
end, "clock", "new without a clock errors")
T.throws(function()
	local s: { [string]: any } = spySink() :: any
	s.press = nil
	InputMap.new({ sink = s, clock = function()
		return 0
	end } :: any)
end, "sink.press", "new with a sink missing press errors")
T.throws(function()
	make({ gamepadTriggerPressAt = 0.25, gamepadTriggerReleaseAt = 0.3 })
end, "ReleaseAt", "new with a release threshold above the press threshold errors")
T.throws(function()
	make({ gamepadDeadzone = 1.5 })
end, "gamepadDeadzone", "new with a deadzone of 1.5 errors")

T.finish()
