--!strict
-- tutorial_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves Tutorial: the whole F1 childhood script walked with events and states (every prompt in
-- order), gated inputs swallowed, timed hints and a timeout hint firing once, skip refused on a
-- fixed step and allowed on a skippable one, the flags set at the end, any/all/count/data/flag
-- requirements on a small script, a serialize round trip through real JSON that resumes mid-step
-- with its counters and elapsed time, and deserialize refusing a tampered save (negative control).
-- Every prompt is an id. Run from this folder: luau tutorial_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("tutorial_test")
local Tutorial = require("../src/Fishing/Shared/Tutorial")

-- hooks that log what the UI and the input layer would be told
local function logger()
	local log = { prompts = {} :: { string }, clears = 0, allows = {} :: { any } }
	local hooks: Tutorial.Hooks = {
		prompt = function(id: string)
			table.insert(log.prompts, id)
		end,
		clear = function()
			log.clears += 1
		end,
		allow = function(set: { [string]: boolean }?)
			table.insert(log.allows, if set then set else "all")
		end,
	}
	return log, hooks
end

local function lastAllow(log: any): string
	local v = log.allows[#log.allows]
	if typeof(v) ~= "table" then
		return tostring(v)
	end
	local names: { string } = {}
	for k in v do
		table.insert(names, k)
	end
	table.sort(names)
	return table.concat(names, ",")
end

-- the F1 script is ordered and complete: nine steps, unique ids, prompt ids only
local F1 = Tutorial.F1_SCRIPT
T.eq(#F1.steps, 9, "the F1 script has nine steps")
local ids: { string } = {}
local promptsOk = true
for _, s in F1.steps do
	table.insert(ids, s.id)
	if not s.prompt:match("^tut_") then
		promptsOk = false
	end
end
T.eq(table.concat(ids, ","), "walk_to_dock,aim,cast,wait_notice,set_hook,fight,catch,hold_fish,let_go", "the steps follow the F1 loop in order")
T.check(promptsOk, "every prompt is a tut_ id, never prose")

-- walking the F1 script
local log, hooks = logger()
local tut = Tutorial.new(F1, hooks)
local pr = Tutorial.progress(tut)
T.check(pr.index == 1 and pr.total == 9 and not pr.done, "progress starts at 1 of 9")
T.eq(Tutorial.currentId(tut), "walk_to_dock", "the first step is walk_to_dock")
T.check(log.prompts[1] == "tut_walk_dock" and lastAllow(log) == "walk", "new() shows the first prompt and allows only walk")
T.check(Tutorial.allows(tut, "walk") and not Tutorial.allows(tut, "press"), "allows(): walk yes, press no")
T.check(Tutorial.input(tut, "press") == false and tut.swallowed == 1, "a gated input is swallowed and counted")
T.check(Tutorial.input(tut, "walk") == true and Tutorial.currentId(tut) == "walk_to_dock", "an allowed input passes and the step stays")
T.check(Tutorial.event(tut, "Nip") == false, "an event the step does not want changes nothing")
Tutorial.tick(tut, 0)
T.check(Tutorial.event(tut, "ReachedDock") == true and Tutorial.currentId(tut) == "aim", "ReachedDock completes step 1: now aim")
T.check(log.clears == 1 and log.prompts[#log.prompts] == "tut_aim" and lastAllow(log) == "aimEnter,aimTurn,walk", "the prompt was cleared, the aim prompt shown, the aim inputs allowed")
T.check(Tutorial.stateChanged(tut, "Walking") == false, "a state the step does not want changes nothing")
T.check(Tutorial.stateChanged(tut, "Aiming") == true and Tutorial.currentId(tut) == "cast", "state Aiming completes aim: now cast")

-- timed hint and timeout hint on the cast step (started at t = 0)
Tutorial.tick(tut, 5)
T.eq(log.prompts[#log.prompts], "tut_cast", "at 5 s no hint yet")
Tutorial.tick(tut, 10)
T.eq(log.prompts[#log.prompts], "tut_hint_pullback", "at 10 s the pull-back hint fires")
local nPrompts = #log.prompts
Tutorial.tick(tut, 12)
T.eq(#log.prompts, nPrompts, "the hint fires once")
Tutorial.tick(tut, 30)
T.eq(log.prompts[#log.prompts], "tut_hint_flick", "at 30 s the timeout hint fires")
nPrompts = #log.prompts
Tutorial.tick(tut, 45)
T.check(#log.prompts == nPrompts and Tutorial.currentId(tut) == "cast", "the timeout hint fires once and the step stays (onTimeout hint, not skip)")
T.check(Tutorial.event(tut, "Cast") and Tutorial.currentId(tut) == "wait_notice", "Cast completes the step: now wait_notice")
T.check(lastAllow(log) == "" and not Tutorial.allows(tut, "walk"), "an empty gate swallows every input while waiting")
Tutorial.tick(tut, 104)
T.eq(log.prompts[#log.prompts], "tut_wait", "59 s into the wait no patience hint yet (the step's clock started at 45 s)")
Tutorial.tick(tut, 105)
T.eq(log.prompts[#log.prompts], "tut_hint_patience", "at 60 s of waiting the patience hint fires")
T.check(Tutorial.event(tut, "Notice") and Tutorial.currentId(tut) == "set_hook", "Notice: now set_hook")
T.check(lastAllow(log) == "press", "the single-input gate form allows press only")
T.check(Tutorial.event(tut, "Swallow") == false and Tutorial.currentId(tut) == "set_hook", "Swallow alone does not finish set_hook (all of Swallow and Hooked)")
T.check(Tutorial.input(tut, "press") == true, "the press passes the gate")
T.check(Tutorial.stateChanged(tut, "Hooked") == true and Tutorial.currentId(tut) == "fight", "Hooked after Swallow completes set_hook: now fight")
T.check(Tutorial.stateChanged(tut, "CatchScene") and Tutorial.currentId(tut) == "catch", "CatchScene ends the fight: now catch")
local ok, why = Tutorial.skip(tut)
T.check(not ok and why ~= nil and why:find("not skippable", 1, true) ~= nil, "skip is refused on catch")
T.check(Tutorial.event(tut, "Caught") and Tutorial.currentId(tut) == "hold_fish", "Caught: now hold_fish")
T.check(Tutorial.stateChanged(tut, "Holding") == true and Tutorial.currentId(tut) == "let_go", "Holding completes hold_fish: now let_go")
T.check(tut.flags.TutorialDone == false and not Tutorial.done(tut), "TutorialDone is still false before the last step")
T.check(Tutorial.event(tut, "Released") and Tutorial.done(tut), "Released finishes the lesson")
T.check(tut.flags.TutorialDone == true, "the last step sets TutorialDone")
pr = Tutorial.progress(tut)
T.check(pr.index == 9 and pr.total == 9 and pr.done, "progress ends at 9 of 9, done")
T.check(Tutorial.current(tut) == nil and lastAllow(log) == "all", "once done there is no current step and every input is allowed")
T.check(Tutorial.event(tut, "Cast") == false and Tutorial.input(tut, "press") == true and Tutorial.tick(tut, 999) == false, "events, inputs and ticks after done are inert")
ok, why = Tutorial.skip(tut)
T.check(not ok and why == "done", "skip after done is refused")
local shown: { string } = {}
for _, p in log.prompts do
	if p:match("^tut_hint") == nil then
		table.insert(shown, p)
	end
end
T.eq(table.concat(shown, ","), "tut_walk_dock,tut_aim,tut_cast,tut_wait,tut_press,tut_fight,tut_catch,tut_hold,tut_release", "the nine step prompts were shown in order")
T.eq(log.clears, 9, "every step cleared its prompt once")

-- skip allowed on a skippable step
local log2, hooks2 = logger()
local tut2 = Tutorial.new(F1, hooks2)
ok = Tutorial.skip(tut2)
T.check(ok and Tutorial.currentId(tut2) == "aim", "walk_to_dock is skippable: skip moves to aim")
ok, why = Tutorial.skip(tut2)
T.check(not ok and why ~= nil and why:find("aim", 1, true) ~= nil, "aim is not skippable and the reason names it")
T.check(log2.prompts[#log2.prompts] == "tut_aim", "the skipped step's successor is shown")

-- a state already held when a step begins counts
local tut3 = Tutorial.new(F1)
Tutorial.stateChanged(tut3, "Aiming")
Tutorial.event(tut3, "ReachedDock")
T.eq(Tutorial.currentId(tut3), "cast", "reaching the dock while already Aiming passes straight through aim")

-- small scripts: any, count with data, flag, timeout skip, sets chaining
local small: Tutorial.Script = {
	id = "small",
	flags = { seen = false },
	steps = {
		{ id = "either", prompt = "p_either", require = { any = { { event = "A" }, { event = "B" } } } },
		{ id = "twice_good", prompt = "p_twice", require = { count = { event = "Press", n = 2, data = { verdict = "Good" } } }, hints = { { afterS = 10, prompt = "h_twice" } } },
		{ id = "impatient", prompt = "p_wait", require = { event = "Never" }, timeoutS = 5, onTimeout = "skip", sets = { seen = true } },
		{ id = "needs_flag", prompt = "p_flag", require = { flag = "seen" } },
		{ id = "last", prompt = "p_last", require = { event = "End" } },
	},
}
local log4, hooks4 = logger()
local s = Tutorial.new(small, hooks4)
T.check(Tutorial.event(s, "B") and Tutorial.currentId(s) == "twice_good", "any: event B alone completes the step")
T.check(Tutorial.event(s, "Press", { verdict = "Early" }) == false and s.leafCounts[1] == 0, "a Press with the wrong data does not count")
T.check(Tutorial.event(s, "Press", { verdict = "Good" }) == false and s.leafCounts[1] == 1, "one Good press counts 1 of 2")
Tutorial.tick(s, 3)
local savedMid = Tutorial.serialize(s)
Tutorial.tick(s, 100)
T.eq(log4.prompts[#log4.prompts], "h_twice", "the 10 s hint fires at 100 s on the original engine")
T.check(Tutorial.event(s, "Press", { verdict = "Good", extra = 1 }) and Tutorial.currentId(s) == "impatient", "the second Good press (with extra data) completes the count")
Tutorial.tick(s, 104)
T.eq(Tutorial.currentId(s), "impatient", "4 s in, the impatient step still waits")
T.check(Tutorial.tick(s, 105) == true and Tutorial.currentId(s) == "last", "at 5 s the timeout skips it, sets seen, and needs_flag passes by itself: now last")
T.check(s.flags.seen == true, "the skipped step's sets applied")
T.check(Tutorial.allows(s, "anything"), "a step without a gate allows everything")
T.check(Tutorial.event(s, "End") and Tutorial.done(s), "End finishes the small script")
local shown4: { string } = {}
for _, p in log4.prompts do
	if p:match("^h_") == nil then
		table.insert(shown4, p)
	end
end
T.eq(table.concat(shown4, ","), "p_either,p_twice,p_wait,p_flag,p_last", "every step prompt shown once, in order")

-- round trip through real JSON: resume mid-step with counters and elapsed time
local wire = Stub.jsonEncode(savedMid)
local log5, hooks5 = logger()
local back = Tutorial.deserialize(Stub.jsonDecode(wire), small, hooks5)
T.eq(Stub.jsonEncode(Tutorial.serialize(back)), wire, "deserialize(serialize()) serializes identically")
T.check(Tutorial.currentId(back) == "twice_good" and back.leafCounts[1] == 1, "the rebuilt engine is on twice_good with 1 of 2 presses")
T.check(log5.prompts[1] == "p_twice" and lastAllow(log5) == "all", "resuming shows the step's prompt again and its gate")
Tutorial.tick(back, 5000)
T.eq(back.elapsedS, 3, "the first tick after a resume re-bases the clock: 3 s elapsed")
T.eq(#log5.prompts, 1, "no hint yet at 3 s")
Tutorial.tick(back, 5007)
T.check(#log5.prompts == 2 and log5.prompts[2] == "h_twice", "at 10 s of step time the hint fires on the resumed engine (it had not fired before the save)")
T.check(Tutorial.event(back, "Press", { verdict = "Good" }) and Tutorial.currentId(back) == "impatient", "one more Good press completes the resumed step")
local doneWire = Stub.jsonEncode(Tutorial.serialize(s))
local backDone = Tutorial.deserialize(Stub.jsonDecode(doneWire), small)
T.check(Tutorial.done(backDone) and Tutorial.progress(backDone).index == 5, "a finished tutorial resumes as done")
Tutorial.tick(s, 50)
T.check(s.t == 50, "a clock that restarts below the last tick is accepted")

-- tampered saves are refused
local tampered = Stub.jsonDecode(wire)
tampered.index = 20
T.throws(function() Tutorial.deserialize(tampered, small) end, "index", "negative control: an index past the steps is refused")
tampered = Stub.jsonDecode(wire)
tampered.leafCounts = { 1, 1 }
T.throws(function() Tutorial.deserialize(tampered, small) end, "leafCounts", "leafCounts of the wrong length are refused")
tampered = Stub.jsonDecode(wire)
tampered.leafCounts = { -1 }
T.throws(function() Tutorial.deserialize(tampered, small) end, "leafCounts", "a negative count is refused")
tampered = Stub.jsonDecode(wire)
tampered.hintsFired = {}
T.throws(function() Tutorial.deserialize(tampered, small) end, "hintsFired", "hintsFired of the wrong length is refused")
tampered = Stub.jsonDecode(wire)
tampered.elapsedS = -3
T.throws(function() Tutorial.deserialize(tampered, small) end, "elapsedS", "a negative elapsed time is refused")
tampered = Stub.jsonDecode(wire)
tampered.flags = { seen = { nested = true } }
T.throws(function() Tutorial.deserialize(tampered, small) end, "flags", "a non-scalar flag is refused")
T.throws(function() Tutorial.deserialize(Stub.jsonDecode(wire), F1) end, "script id", "a save from another script is refused")
T.throws(function() Tutorial.deserialize({ v = 2 }, small) end, "not a serialized", "a wrong version is refused")

-- script validation
local function scriptWith(step: any)
	return function()
		Tutorial.new({ steps = { step } })
	end
end
T.throws(function() Tutorial.new({ steps = {} }) end, "non-empty", "an empty step list is refused")
T.throws(function() Tutorial.new({ steps = { { id = "a", prompt = "p", require = { event = "X" } }, { id = "a", prompt = "p", require = { event = "X" } } } }) end, "duplicate id", "a duplicate step id is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { wish = "X" } }), "one of event, state, count, flag, any, all", "an unknown requirement shape is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { event = "X", state = "Y" } }), "event requires", "two requirement keys in one table are refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { count = { event = "X", n = 0 } } }), "count requires", "a count of 0 is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { any = {} } }), "non-empty array", "an empty any is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { event = "X" }, timeoutS = 5 }), "needs onTimeout", "timeoutS without onTimeout is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { event = "X" }, timeoutS = 5, onTimeout = "explode" }), "onTimeout", "an unknown onTimeout is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { event = "X" }, gate = { input = "press", inputs = { "walk" } } }), "gate", "a gate with both forms is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { event = "X" }, hints = { { afterS = 0, prompt = "h" } } }), "hint 1", "a hint at 0 s is refused")
T.throws(scriptWith({ id = "a", prompt = "", require = { event = "X" } }), "prompt", "an empty prompt id is refused")
T.throws(scriptWith({ id = "a", prompt = "p", require = { event = "X" }, sets = { x = {} } }), "sets", "a non-scalar sets value is refused")
T.throws(function() Tutorial.new(small, { prompt = 5 } :: any) end, "hooks.prompt", "a non-function hook is refused")

T.finish()
