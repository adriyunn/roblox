--!strict
-- Tutorial (About Fishing F1, WS-T opening; Cloud, 2026-10-08; design/PARITY_rows_F2plus.md row P18)
-- A step engine for scripted sequences: a script is an ordered list of steps, each with a prompt id,
-- a requirement over game events, player states, event counts and flags (combinable with any/all),
-- an input gate (only the listed inputs pass; the rest are swallowed), timed hints, a timeout that
-- hints or skips, and flags it sets when done. The engine is pure: the game feeds events, state
-- changes and the clock; three optional hooks (prompt, clear, allow) drive the UI and the input layer.
-- F1_SCRIPT is the childhood lesson as data: the F1 loop (walk to the dock, aim, cast, wait for the
-- notice, press on the swallow, fight, catch, hold the fish, let it go) with prompt ids only; the
-- words, the father and the place are the writing pass's, not this file's.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * The client owns the engine (the tutorial is per player, P18): Tutorial.new(Tutorial.F1_SCRIPT,
--     { prompt = TutorialUI.show, clear = TutorialUI.hide, allow = InputMap.setAllowed }); call
--     Tutorial.tick(tut, os.clock()) each frame BEFORE forwarding that frame's events, so a step
--     that begins on an event takes the current time as its start.
--   * Events are the F1 net cues and client events by name (Notice, Swallow, Cast, Caught,
--     Released, ReachedDock from a trigger volume); states are the player states (Aiming, Hooked,
--     CatchScene, Holding) via Tutorial.stateChanged; inputs are WSI_touch_gamepad.md's intents
--     (walk, aimEnter, aimTurn, rodDelta, press, hold, steer): InputMap calls Tutorial.input(tut,
--     intent) and drops the intent when it returns false.
--   * SaveData: store serialize(tut) with the player's data so a disconnect resumes mid-step;
--     deserialize(tbl, script, hooks) re-shows the step. Once done, flags.TutorialDone is true:
--     SaveData.TutorialDone is the one bit that skips the whole lesson on later visits.
-- No Roblox globals; no clock of its own.

local Tutorial = {}

export type Req = { event: string?, data: { [string]: any }?, state: string?, count: { event: string, n: number, data: { [string]: any }? }?, flag: string?, any: { Req }?, all: { Req }? }
export type Hint = { afterS: number, prompt: string }
export type Gate = { input: string?, inputs: { string }? }
export type Step = { id: string, prompt: string, require: Req, timeoutS: number?, onTimeout: string?, gate: Gate?, hints: { Hint }?, skippable: boolean?, sets: { [string]: any }? }
export type Script = { id: string?, steps: { Step }, flags: { [string]: any }? }
export type Hooks = { prompt: ((string) -> ())?, clear: (() -> ())?, allow: ((({ [string]: boolean })?) -> ())? }
export type Progress = { index: number, total: number, done: boolean }

type Leaf = { kind: string, name: string, n: number, data: { [string]: any }? }
type Node = { leaf: number?, any: { Node }?, all: { Node }? }
type Compiled = { leaves: { Leaf }, tree: Node, allow: { [string]: boolean }?, hints: { Hint } }

export type Tut = {
	script: Script,
	hooks: Hooks,
	compiled: { Compiled },
	index: number,
	leafCounts: { number },
	hintsFired: { boolean },
	timeoutFired: boolean,
	elapsedS: number,
	startedAt: number?,
	t: number,
	flags: { [string]: any },
	lastState: string?,
	swallowed: number,
	done: boolean,
}

Tutorial.VERSION = 1

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

local function isScalar(v: any): boolean
	return typeof(v) == "boolean" or typeof(v) == "string" or isNum(v)
end

local function checkScalars(label: string, t: any): { [string]: any }
	if typeof(t) ~= "table" then
		error(label .. " must be a table of flag = boolean/number/string")
	end
	local out: { [string]: any } = {}
	for k, v in t do
		if not nonEmpty(k) or not isScalar(v) then
			error(label .. " must map flag names to boolean/number/string values")
		end
		out[k] = v
	end
	return out
end

local function keyCount(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function dataMatches(filter: { [string]: any }?, data: any): boolean
	if filter == nil then
		return true
	end
	if typeof(data) ~= "table" then
		return keyCount(filter) == 0
	end
	for k, v in filter do
		if data[k] ~= v then
			return false
		end
	end
	return true
end

-- ---------------------------------------------------------------- compiling a script
local function compileReq(label: string, r: any, leaves: { Leaf }): Node
	if typeof(r) ~= "table" then
		error(label .. ": require must be a table")
	end
	local keys = keyCount(r)
	if r.any ~= nil or r.all ~= nil then
		local list: any = if r.any ~= nil then r.any else r.all
		local word = if r.any ~= nil then "any" else "all"
		if keys ~= 1 or typeof(list) ~= "table" or #list == 0 then
			error(label .. ": " .. word .. " must be a non-empty array of requirements and nothing else")
		end
		local kids: { Node } = {}
		for i = 1, #list do
			kids[i] = compileReq(label .. " " .. word .. "[" .. i .. "]", list[i], leaves)
		end
		return if word == "any" then { any = kids } else { all = kids }
	elseif r.event ~= nil then
		if not nonEmpty(r.event) or (r.data ~= nil and typeof(r.data) ~= "table") or keys > (if r.data ~= nil then 2 else 1) then
			error(label .. ": event requires { event = name, data = table? }")
		end
		table.insert(leaves, { kind = "event", name = r.event, n = 1, data = r.data })
		return { leaf = #leaves }
	elseif r.state ~= nil then
		if not nonEmpty(r.state) or keys ~= 1 then
			error(label .. ": state requires { state = name }")
		end
		table.insert(leaves, { kind = "state", name = r.state, n = 1, data = nil })
		return { leaf = #leaves }
	elseif r.count ~= nil then
		local c: any = r.count
		if keys ~= 1 or typeof(c) ~= "table" or not nonEmpty(c.event) or not isInt(c.n) or c.n < 1 or (c.data ~= nil and typeof(c.data) ~= "table") then
			error(label .. ": count requires { count = { event = name, n >= 1, data = table? } }")
		end
		table.insert(leaves, { kind = "event", name = c.event, n = c.n, data = c.data })
		return { leaf = #leaves }
	elseif r.flag ~= nil then
		if not nonEmpty(r.flag) or keys ~= 1 then
			error(label .. ": flag requires { flag = name }")
		end
		table.insert(leaves, { kind = "flag", name = r.flag, n = 1, data = nil })
		return { leaf = #leaves }
	end
	error(label .. ": require must be one of event, state, count, flag, any, all")
end

local function compileStep(i: number, s: any, seen: { [string]: boolean }): Compiled
	local label = "Tutorial: step " .. i
	if typeof(s) ~= "table" or not nonEmpty(s.id) then
		error(label .. ": id must be a non-empty string")
	end
	label = "Tutorial: step " .. s.id
	if seen[s.id] then
		error(label .. ": duplicate id")
	end
	seen[s.id] = true
	if not nonEmpty(s.prompt) then
		error(label .. ": prompt must be a prompt id")
	end
	local leaves: { Leaf } = {}
	local tree = compileReq(label, s.require, leaves)
	if s.timeoutS ~= nil and (not isNum(s.timeoutS) or s.timeoutS <= 0) then
		error(label .. ": timeoutS must be > 0")
	end
	if s.onTimeout ~= nil then
		if s.timeoutS == nil then
			error(label .. ": onTimeout needs timeoutS")
		end
		if s.onTimeout ~= "skip" and not (typeof(s.onTimeout) == "string" and string.match(s.onTimeout, "^hint:.+$") ~= nil) then
			error(label .. ": onTimeout must be \"skip\" or \"hint:<prompt id>\"")
		end
	elseif s.timeoutS ~= nil then
		error(label .. ": timeoutS needs onTimeout")
	end
	local allow: { [string]: boolean }? = nil
	if s.gate ~= nil then
		local g: any = s.gate
		if typeof(g) ~= "table" or (g.input ~= nil) == (g.inputs ~= nil) then
			error(label .. ": gate must be { input = name } or { inputs = { names } }")
		end
		local set: { [string]: boolean } = {}
		if g.input ~= nil then
			if not nonEmpty(g.input) then
				error(label .. ": gate.input must be a non-empty string")
			end
			set[g.input] = true
		else
			if typeof(g.inputs) ~= "table" then
				error(label .. ": gate.inputs must be an array of names")
			end
			for j = 1, #g.inputs do
				if not nonEmpty(g.inputs[j]) then
					error(label .. ": gate.inputs must be non-empty strings")
				end
				set[g.inputs[j]] = true
			end
		end
		allow = set
	end
	local hints: { Hint } = {}
	if s.hints ~= nil then
		if typeof(s.hints) ~= "table" then
			error(label .. ": hints must be an array of { afterS, prompt }")
		end
		for j = 1, #s.hints do
			local h: any = s.hints[j]
			if typeof(h) ~= "table" or not isNum(h.afterS) or h.afterS <= 0 or not nonEmpty(h.prompt) then
				error(label .. ": hint " .. j .. " must be { afterS > 0, prompt = id }")
			end
			hints[j] = { afterS = h.afterS, prompt = h.prompt }
		end
	end
	if s.skippable ~= nil and typeof(s.skippable) ~= "boolean" then
		error(label .. ": skippable must be a boolean")
	end
	if s.sets ~= nil then
		checkScalars(label .. ": sets", s.sets)
	end
	return { leaves = leaves, tree = tree, allow = allow, hints = hints }
end

local function compileScript(script: any): { Compiled }
	if typeof(script) ~= "table" or typeof(script.steps) ~= "table" or #script.steps == 0 then
		error("Tutorial: script.steps must be a non-empty array")
	end
	if script.id ~= nil and not nonEmpty(script.id) then
		error("Tutorial: script.id must be a non-empty string when given")
	end
	if script.flags ~= nil then
		checkScalars("Tutorial: script.flags", script.flags)
	end
	local seen: { [string]: boolean } = {}
	local out: { Compiled } = {}
	for i = 1, #script.steps do
		out[i] = compileStep(i, script.steps[i], seen)
	end
	return out
end

local function checkHooks(hooks: any): Hooks
	if hooks == nil then
		return {}
	end
	if typeof(hooks) ~= "table" then
		error("Tutorial: hooks must be a table")
	end
	for _, name in { "prompt", "clear", "allow" } do
		if hooks[name] ~= nil and typeof(hooks[name]) ~= "function" then
			error("Tutorial: hooks." .. name .. " must be a function")
		end
	end
	return { prompt = hooks.prompt, clear = hooks.clear, allow = hooks.allow }
end

-- ---------------------------------------------------------------- the engine
local function satisfied(node: Node, tut: Tut): boolean
	if node.leaf then
		local leaf = tut.compiled[tut.index].leaves[node.leaf]
		if leaf.kind == "flag" then
			local v = tut.flags[leaf.name]
			return v ~= nil and v ~= false
		end
		return (tut.leafCounts[node.leaf] or 0) >= leaf.n
	elseif node.any then
		for _, k in node.any do
			if satisfied(k, tut) then
				return true
			end
		end
		return false
	end
	for _, k in node.all :: { Node } do
		if not satisfied(k, tut) then
			return false
		end
	end
	return true
end

local function callPrompt(tut: Tut, id: string)
	if tut.hooks.prompt then
		tut.hooks.prompt(id)
	end
end

local function callClear(tut: Tut)
	if tut.hooks.clear then
		tut.hooks.clear()
	end
end

local function callAllow(tut: Tut, set: { [string]: boolean }?)
	if tut.hooks.allow then
		tut.hooks.allow(if set then table.clone(set) else nil)
	end
end

-- Shows the current step: its prompt and its input gate.
local function show(tut: Tut)
	callPrompt(tut, tut.script.steps[tut.index].prompt)
	callAllow(tut, tut.compiled[tut.index].allow)
end

-- After the last step (complete() already cleared its prompt): nothing gated any more.
local function finish(tut: Tut)
	tut.done = true
	tut.startedAt = nil
	tut.leafCounts = {}
	tut.hintsFired = {}
	callAllow(tut, nil)
end

-- Enters step i: fresh counters, the clock from the last tick, state leaves already true count.
local function begin(tut: Tut, i: number)
	tut.index = i
	if i > #tut.script.steps then
		finish(tut)
		return
	end
	local comp = tut.compiled[i]
	tut.leafCounts = table.create(#comp.leaves, 0)
	tut.hintsFired = table.create(#comp.hints, false)
	tut.timeoutFired = false
	tut.elapsedS = 0
	tut.startedAt = tut.t
	for li, leaf in comp.leaves do
		if leaf.kind == "state" and tut.lastState == leaf.name then
			tut.leafCounts[li] = 1
		end
	end
	show(tut)
end

-- Ends the current step: applies its sets, clears the prompt, enters the next.
local function complete(tut: Tut)
	local step = tut.script.steps[tut.index]
	if step.sets then
		for k, v in step.sets do
			tut.flags[k] = v
		end
	end
	callClear(tut)
	begin(tut, tut.index + 1)
end

-- Advances through every step already satisfied (a flag set earlier, a state already held).
local function settle(tut: Tut)
	while not tut.done and satisfied(tut.compiled[tut.index].tree, tut) do
		complete(tut)
	end
end

-- A new engine on a script; validates every step and shows the first.
function Tutorial.new(script: Script, hooks: Hooks?): Tut
	local compiled = compileScript(script)
	local tut: Tut = {
		script = script,
		hooks = checkHooks(hooks),
		compiled = compiled,
		index = 0,
		leafCounts = {},
		hintsFired = {},
		timeoutFired = false,
		elapsedS = 0,
		startedAt = nil,
		t = 0,
		flags = if script.flags then table.clone(script.flags) else {},
		lastState = nil,
		swallowed = 0,
		done = false,
	}
	begin(tut, 1)
	settle(tut)
	return tut
end

-- A game event by name with optional data; true when the current step completed because of it.
function Tutorial.event(tut: Tut, name: string, data: { [string]: any }?): boolean
	if tut.done then
		return false
	end
	local comp = tut.compiled[tut.index]
	for li, leaf in comp.leaves do
		if leaf.kind == "event" and leaf.name == name and dataMatches(leaf.data, data) then
			tut.leafCounts[li] += 1
		end
	end
	local before = tut.index
	settle(tut)
	return tut.index ~= before
end

-- The player's state changed; true when the current step completed because of it.
function Tutorial.stateChanged(tut: Tut, state: string): boolean
	tut.lastState = state
	if tut.done then
		return false
	end
	local comp = tut.compiled[tut.index]
	for li, leaf in comp.leaves do
		if leaf.kind == "state" and leaf.name == state then
			tut.leafCounts[li] = 1
		end
	end
	local before = tut.index
	settle(tut)
	return tut.index ~= before
end

-- Whether an input intent passes the current step's gate (no gate, or done: everything passes).
function Tutorial.allows(tut: Tut, input: string): boolean
	if tut.done then
		return true
	end
	local allow = tut.compiled[tut.index].allow
	return allow == nil or allow[input] == true
end

-- An input intent from the input layer: swallowed (false) when the gate does not list it, else
-- passed (true) and counted as an event of the same name.
function Tutorial.input(tut: Tut, input: string, data: { [string]: any }?): boolean
	if not Tutorial.allows(tut, input) then
		tut.swallowed += 1
		return false
	end
	Tutorial.event(tut, input, data)
	return true
end

-- The clock, in seconds on any monotonic base: fires the step's timed hints and its timeout once
-- each. A clock that restarts (t below the last tick, or the first tick after a resume) re-bases
-- the step's elapsed time instead of erroring. True when the step completed (a "skip" timeout).
function Tutorial.tick(tut: Tut, t: number): boolean
	assert(isNum(t), "Tutorial.tick: t must be a finite number")
	if tut.done then
		tut.t = t
		return false
	end
	if tut.startedAt == nil or t < tut.t then
		tut.startedAt = t - tut.elapsedS
	end
	tut.t = t
	tut.elapsedS = t - (tut.startedAt :: number)
	local step = tut.script.steps[tut.index]
	local comp = tut.compiled[tut.index]
	for hi, h in comp.hints do
		if not tut.hintsFired[hi] and tut.elapsedS >= h.afterS then
			tut.hintsFired[hi] = true
			callPrompt(tut, h.prompt)
		end
	end
	if step.timeoutS and not tut.timeoutFired and tut.elapsedS >= step.timeoutS then
		tut.timeoutFired = true
		if step.onTimeout == "skip" then
			local before = tut.index
			complete(tut)
			settle(tut)
			return tut.index ~= before
		end
		callPrompt(tut, (step.onTimeout :: string):sub(#"hint:" + 1))
	end
	return false
end

-- The current step (the script's own table; do not mutate), or nil once done.
function Tutorial.current(tut: Tut): Step?
	if tut.done then
		return nil
	end
	return tut.script.steps[tut.index]
end

-- The current step's id, or nil once done.
function Tutorial.currentId(tut: Tut): string?
	local s = Tutorial.current(tut)
	return if s then s.id else nil
end

-- Skips the current step; allowed only when it says skippable. Returns ok, reason.
function Tutorial.skip(tut: Tut): (boolean, string?)
	if tut.done then
		return false, "done"
	end
	local step = tut.script.steps[tut.index]
	if step.skippable ~= true then
		return false, "step " .. step.id .. " is not skippable"
	end
	complete(tut)
	settle(tut)
	return true, nil
end

-- True once the last step completed.
function Tutorial.done(tut: Tut): boolean
	return tut.done
end

-- { index, total, done }: index stays at total once done, so a readout never says "10 of 9".
function Tutorial.progress(tut: Tut): Progress
	local total = #tut.script.steps
	return { index = math.min(tut.index, total), total = total, done = tut.done }
end

-- ---------------------------------------------------------------- save form
-- A plain JSON-safe table: the step, its elapsed time and counters, the flags and the last state.
function Tutorial.serialize(tut: Tut): { [string]: any }
	return {
		v = Tutorial.VERSION,
		scriptId = tut.script.id,
		index = tut.index,
		elapsedS = tut.elapsedS,
		leafCounts = table.clone(tut.leafCounts),
		hintsFired = table.clone(tut.hintsFired),
		timeoutFired = tut.timeoutFired,
		flags = table.clone(tut.flags),
		lastState = tut.lastState,
		swallowed = tut.swallowed,
	}
end

-- Rebuilds an engine mid-step from its save form against the script (the same script: ids must
-- match), re-checking every field, then shows the step again. The first tick re-bases the clock.
function Tutorial.deserialize(tbl: any, script: Script, hooks: Hooks?): Tut
	if typeof(tbl) ~= "table" or tbl.v ~= Tutorial.VERSION then
		error("Tutorial.deserialize: not a serialized tutorial")
	end
	local compiled = compileScript(script)
	local function fail(why: string)
		error("Tutorial.deserialize: " .. why)
	end
	if tbl.scriptId ~= script.id then
		fail("script id " .. tostring(tbl.scriptId) .. " does not match " .. tostring(script.id))
	end
	local n = #script.steps
	if not isInt(tbl.index) or tbl.index < 1 or tbl.index > n + 1 then
		fail("index must be an integer in 1..steps+1")
	end
	if not isNum(tbl.elapsedS) or tbl.elapsedS < 0 then
		fail("elapsedS must be >= 0")
	end
	local done = tbl.index > n
	local comp: Compiled? = if done then nil else compiled[tbl.index]
	local leafCounts: { number } = {}
	local hintsFired: { boolean } = {}
	if comp then
		if typeof(tbl.leafCounts) ~= "table" or #tbl.leafCounts ~= #comp.leaves then
			fail("leafCounts must have one entry per requirement leaf of the step")
		end
		for i = 1, #comp.leaves do
			local c = tbl.leafCounts[i]
			if not isInt(c) or c < 0 then
				fail("leafCounts must be integers >= 0")
			end
			leafCounts[i] = c
		end
		if typeof(tbl.hintsFired) ~= "table" or #tbl.hintsFired ~= #comp.hints then
			fail("hintsFired must have one entry per hint of the step")
		end
		for i = 1, #comp.hints do
			if typeof(tbl.hintsFired[i]) ~= "boolean" then
				fail("hintsFired must be booleans")
			end
			hintsFired[i] = tbl.hintsFired[i]
		end
	end
	if typeof(tbl.timeoutFired) ~= "boolean" then
		fail("timeoutFired must be a boolean")
	end
	local flags = checkScalars("Tutorial.deserialize: flags", tbl.flags)
	if tbl.lastState ~= nil and not nonEmpty(tbl.lastState) then
		fail("lastState must be a non-empty string when given")
	end
	if not isInt(tbl.swallowed) or tbl.swallowed < 0 then
		fail("swallowed must be an integer >= 0")
	end
	local tut: Tut = {
		script = script,
		hooks = checkHooks(hooks),
		compiled = compiled,
		index = tbl.index,
		leafCounts = leafCounts,
		hintsFired = hintsFired,
		timeoutFired = tbl.timeoutFired,
		elapsedS = tbl.elapsedS,
		startedAt = nil,
		t = 0,
		flags = flags,
		lastState = tbl.lastState,
		swallowed = tbl.swallowed,
		done = done,
	}
	if done then
		callAllow(tut, nil)
	else
		show(tut)
		settle(tut)
	end
	return tut
end

-- ---------------------------------------------------------------- the F1 lesson as data
-- Prompt ids only (tut_*); events are F1's cue names, states the player states, inputs WS-I's intents.
Tutorial.F1_SCRIPT = {
	id = "f1_childhood",
	flags = { TutorialDone = false },
	steps = {
		{ id = "walk_to_dock", prompt = "tut_walk_dock", require = { event = "ReachedDock" }, gate = { inputs = { "walk" } }, hints = { { afterS = 20, prompt = "tut_hint_walk" } }, skippable = true },
		{ id = "aim", prompt = "tut_aim", require = { state = "Aiming" }, gate = { inputs = { "walk", "aimEnter", "aimTurn" } }, hints = { { afterS = 10, prompt = "tut_hint_aim" } } },
		{ id = "cast", prompt = "tut_cast", require = { event = "Cast" }, gate = { inputs = { "aimTurn", "rodDelta" } }, timeoutS = 30, onTimeout = "hint:tut_hint_flick", hints = { { afterS = 10, prompt = "tut_hint_pullback" } } },
		{ id = "wait_notice", prompt = "tut_wait", require = { event = "Notice" }, gate = { inputs = {} }, timeoutS = 60, onTimeout = "hint:tut_hint_patience" },
		{ id = "set_hook", prompt = "tut_press", require = { all = { { event = "Swallow" }, { state = "Hooked" } } }, gate = { input = "press" }, hints = { { afterS = 15, prompt = "tut_hint_watch_mouth" } } },
		{ id = "fight", prompt = "tut_fight", require = { state = "CatchScene" }, gate = { inputs = { "hold", "steer" } }, hints = { { afterS = 8, prompt = "tut_hint_ease_off" } } },
		{ id = "catch", prompt = "tut_catch", require = { event = "Caught" }, gate = { inputs = {} } },
		{ id = "hold_fish", prompt = "tut_hold", require = { state = "Holding" }, gate = { inputs = { "walk" } }, hints = { { afterS = 10, prompt = "tut_hint_hold" } }, skippable = true },
		{ id = "let_go", prompt = "tut_release", require = { event = "Released" }, gate = { inputs = { "walk", "release" } }, sets = { TutorialDone = true } },
	},
} :: Script

return Tutorial
