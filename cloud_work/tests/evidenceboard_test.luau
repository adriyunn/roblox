--!strict
-- evidenceboard_test (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- Proves EvidenceBoard: discovery with when/where, manual links only between discovered clues the
-- defs allow, automatic links appearing when their required clues are found, conclusions, pins in
-- discovery order, rollFind's bands by source and zone (exact edges with a fixed rng, a seeded LCG
-- for the rate, never a known clue twice, requires gating), a serialize round trip through real JSON,
-- merge (union, earliest wins, commutative, inputs untouched) and deserialize refusing a save with an
-- unknown clue id (negative control). Every id is a placeholder.
-- Run from this folder: luau evidenceboard_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("evidenceboard_test")
local EvidenceBoard = require("../src/Fishing/Shared/EvidenceBoard")

local function rawDefs(): EvidenceBoard.Defs
	return {
		clues = {
			clue_01 = { kind = "item", source = "fish", tags = { "net" }, chance = 0.2, zones = { shore = 1, reeds = 0.5 } },
			clue_02 = { kind = "note", source = "cast", tags = { "letter" }, chance = 0.3 },
			clue_03 = { kind = "photo", source = "npc", tags = { "photo", "npc_a" } },
			clue_04 = { kind = "testimony", source = "npc", tags = { "talk", "npc_b" }, requires = { "clue_01" } },
			clue_05 = { kind = "item", source = "fish", tags = { "ring" }, chance = 0.1, zones = { deep = 1 }, requires = { "clue_02" } },
			clue_06 = { kind = "item", source = "cast", tags = { "key" }, chance = 0.05 },
		},
		links = {
			{ a = "clue_01", b = "clue_02", kind = "string" },
			{ id = "note_a", a = "clue_02", b = "clue_03", kind = "note", requires = { "clue_04" } },
			{ a = "clue_03", b = "clue_04", kind = "string" },
			{ a = "clue_05", b = "clue_06", kind = "string" },
		},
		conclusions = {
			{ id = "concl_a", requires = { "clue_01", "link:clue_01+clue_02" } },
			{ id = "concl_b", requires = { "note_a", "clue_04" } },
		},
	}
end

local defs = EvidenceBoard.compile(rawDefs())
T.check(EvidenceBoard.compile(defs) == defs, "compile() of a compiled defs table returns it unchanged")
T.eq(table.concat(defs.clueIds, ","), "clue_01,clue_02,clue_03,clue_04,clue_05,clue_06", "clue ids are sorted once at compile")
T.check(defs.links[1].id == "link:clue_01+clue_02" and defs.links[1].auto == false and defs.links[2].auto == true, "a link without requires is manual, one with requires is automatic; default ids are link:a+b")

local function ctx(dayN: number, timeOfDay: number, zoneId: string): EvidenceBoard.Found
	return { dayN = dayN, timeOfDay = timeOfDay, zoneId = zoneId }
end

local function wire(board: EvidenceBoard.Board): string
	return Stub.jsonEncode(EvidenceBoard.serialize(board))
end

-- a fixed-number rng and a seeded LCG with the Roblox Random shape
local function fixed(u: number)
	return { NextNumber = function(_self: any): number return u end, NextInteger = function(_self: any, a: number, _b: number): number return a end }
end
local function lcg(seed: number)
	local s = seed
	local rng = {}
	function rng:NextNumber(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
	function rng:NextInteger(a: number, b: number): number
		return a + math.floor(self:NextNumber() * (b - a + 1))
	end
	return rng
end

-- an empty board
local board = EvidenceBoard.new(defs)
local p = EvidenceBoard.progress(board)
T.check(p.discovered == 0 and p.total == 6 and p.linked == 0 and p.totalLinks == 4 and p.conclusions == 0 and p.totalConclusions == 2, "a new board: 0 of 6 clues, 0 of 4 links, 0 of 2 conclusions")

-- discovery
T.eq(EvidenceBoard.discover(board, "clue_01", ctx(2, 9.5, "shore")), true, "the first discovery of clue_01 is new")
T.eq(EvidenceBoard.discover(board, "clue_01", ctx(3, 10, "reeds")), false, "discovering it again is not new")
T.check(board.found.clue_01.dayN == 2 and board.found.clue_01.zoneId == "shore", "the first when/where is kept")
local isNew, why = EvidenceBoard.discover(board, "clue_99", ctx(1, 1, "shore"))
T.check(isNew == nil and why ~= nil and why:find("unknown clue", 1, true) ~= nil, "an unknown clue id gives nil, reason")
T.throws(function() EvidenceBoard.discover(board, "clue_02", { dayN = 1.5, timeOfDay = 1, zoneId = "shore" }) end, "dayN", "a fractional dayN is a programmer error")
T.check(EvidenceBoard.has(board, "clue_01") and not EvidenceBoard.has(board, "clue_02"), "has() follows discovery")
T.eq(#EvidenceBoard.available(board), 0, "with one clue no link is available")

-- manual links
EvidenceBoard.discover(board, "clue_02", ctx(2, 11, "pier"))
local avail = EvidenceBoard.available(board)
T.check(#avail == 1 and avail[1].id == "link:clue_01+clue_02" and avail[1].kind == "string", "with clue_01 and clue_02 found their string is available")
T.eq(#EvidenceBoard.conclusions(board), 0, "no conclusion before the string is drawn")
local ok, reason = EvidenceBoard.link(board, "clue_02", "clue_01")
T.check(ok and reason == nil, "the player draws the string (either orientation)")
T.check(EvidenceBoard.isLinked(board, "clue_01", "clue_02") and EvidenceBoard.isLinked(board, "clue_02", "clue_01"), "isLinked holds both ways")
ok, reason = EvidenceBoard.link(board, "clue_01", "clue_02")
T.check(not ok and reason == "already linked", "drawing it twice is refused: already linked")
T.eq(#EvidenceBoard.available(board), 0, "a drawn link is no longer available")
T.eq(table.concat(EvidenceBoard.conclusions(board), ","), "concl_a", "concl_a is reached from clue_01 plus its string")
ok, reason = EvidenceBoard.link(board, "clue_01", "clue_03")
T.check(not ok and reason ~= nil and reason:find("not discovered", 1, true) ~= nil, "a link to an undiscovered clue is refused")
EvidenceBoard.discover(board, "clue_03", ctx(3, 8, "town"))
ok, reason = EvidenceBoard.link(board, "clue_01", "clue_03")
T.check(not ok and reason ~= nil and reason:find("no link between", 1, true) ~= nil, "a pair the defs do not allow is refused")
ok, reason = EvidenceBoard.link(board, "clue_02", "clue_03")
T.check(not ok and reason ~= nil and reason:find("automatic", 1, true) ~= nil, "the player cannot draw an automatic link by hand")
ok, reason = EvidenceBoard.link(board, "clue_01", "clue_zz")
T.check(not ok and reason ~= nil and reason:find("unknown clue", 1, true) ~= nil, "a link to an unknown id is refused")
T.eq(#EvidenceBoard.links(board), 1, "one link drawn so far")

-- automatic links
EvidenceBoard.discover(board, "clue_04", ctx(3, 9, "town"))
local drawn = EvidenceBoard.links(board)
T.check(#drawn == 2 and drawn[2].id == "note_a" and drawn[2].auto == true and drawn[2].kind == "note", "finding clue_04 draws the automatic note between clue_02 and clue_03")
ok, reason = EvidenceBoard.unlink(board, "clue_02", "clue_03")
T.check(not ok and reason ~= nil and reason:find("automatic", 1, true) ~= nil, "an automatic link cannot be removed")
T.eq(table.concat(EvidenceBoard.conclusions(board), ","), "concl_a,concl_b", "concl_b is reached from the note and clue_04")
local avail2 = EvidenceBoard.available(board)
T.check(#avail2 == 1 and avail2[1].id == "link:clue_03+clue_04", "the clue_03-clue_04 string is now available")

-- unlink
ok = EvidenceBoard.unlink(board, "clue_01", "clue_02")
T.check(ok and not EvidenceBoard.isLinked(board, "clue_01", "clue_02"), "the player removes a manual link")
T.eq(table.concat(EvidenceBoard.conclusions(board), ","), "concl_b", "removing the string drops concl_a")
ok, reason = EvidenceBoard.unlink(board, "clue_01", "clue_02")
T.check(not ok and reason == "not linked", "removing it again is refused: not linked")
T.check(EvidenceBoard.link(board, "clue_01", "clue_02") == true, "it can be drawn again")

-- pins and progress
EvidenceBoard.discover(board, "clue_06", ctx(4, 7, "shore"))
local pins = EvidenceBoard.pins(board)
T.eq(#pins, 5, "five pins for five discoveries")
T.check(pins[1].clueId == "clue_01" and pins[1].slot == 1 and pins[1].col == 1 and pins[1].row == 1, "pin 1 is clue_01 in slot 1 (col 1, row 1)")
T.check(pins[4].col == 4 and pins[4].row == 1 and pins[5].col == 1 and pins[5].row == 2, "pins fill four columns then wrap to row 2")
T.check(pins[2].kind == "note" and pins[2].source == "cast" and pins[2].dayN == 2 and pins[2].timeOfDay == 11 and pins[2].zoneId == "pier", "a pin carries kind, source and the discovery meta")
pins[1].tags[1] = "changed"
T.eq(defs.clues.clue_01.tags[1], "net", "pins copy the tags (the defs stay untouched)")
p = EvidenceBoard.progress(board)
T.check(p.discovered == 5 and p.linked == 2 and p.conclusions == 2, "progress: 5 found, 2 linked, 2 conclusions")

-- rollFind: bands by source and zone, sorted ids, exact edges
local fresh = EvidenceBoard.new(defs)
local function find(u: number, source: string, zoneId: string, b: EvidenceBoard.Board?): string?
	return EvidenceBoard.rollFind(defs, fixed(u), { source = source, zoneId = zoneId, board = b })
end
T.eq(find(0.1, "fish", "shore", fresh), "clue_01", "fish at the shore, u 0.1: clue_01 (band 0..0.2)")
T.eq(find(0.1999, "fish", "shore", fresh), "clue_01", "u just under 0.2 still finds clue_01")
T.eq(find(0.2, "fish", "shore", fresh), nil, "u 0.2 finds nothing (the band is half open)")
T.eq(find(0.09, "fish", "reeds", fresh), "clue_01", "in the reeds the zone weight 0.5 halves the band: u 0.09 finds it")
T.eq(find(0.1, "fish", "reeds", fresh), nil, "u 0.1 in the reeds finds nothing")
T.eq(find(0, "fish", "deep", fresh), nil, "a zone the clue does not list never finds it")
T.eq(find(0.29, "cast", "shore", fresh), "clue_02", "a cast at u 0.29 finds clue_02 (band 0..0.3)")
T.eq(find(0.31, "cast", "shore", fresh), "clue_06", "a cast at u 0.31 finds clue_06 (band 0.3..0.35, sorted after clue_02)")
T.eq(find(0.36, "cast", "shore", fresh), nil, "a cast at u 0.36 finds nothing")
local knows02 = EvidenceBoard.new(defs)
EvidenceBoard.discover(knows02, "clue_02", ctx(1, 1, "pier"))
T.eq(find(0.01, "cast", "shore", knows02), "clue_06", "a known clue is skipped: with clue_02 on the board the first band is clue_06's")
T.eq(find(0, "cast", "shore"), "clue_02", "with no board nothing is known")
T.eq(find(0.05, "fish", "deep", fresh), nil, "clue_05 requires clue_02: not found before it")
T.eq(find(0.05, "fish", "deep", knows02), "clue_05", "with clue_02 on the board clue_05 can surface in the deep")
T.eq(find(0, "fish", "deep"), nil, "with no board a clue with requires never surfaces")
T.eq(find(0, "npc", "town", fresh), nil, "npc clues have no chance and never roll")
T.throws(function() EvidenceBoard.rollFind(defs, fixed(0), { source = "moon", zoneId = "shore" }) end, "source", "an unknown source is a programmer error")
local hits = 0
local rngA, rngB = lcg(7), lcg(7)
local seqA, seqB = {}, {}
for _ = 1, 2000 do
	local a = EvidenceBoard.rollFind(defs, rngA, { source = "fish", zoneId = "shore", board = fresh })
	local b = EvidenceBoard.rollFind(defs, rngB, { source = "fish", zoneId = "shore", board = fresh })
	table.insert(seqA, tostring(a))
	table.insert(seqB, tostring(b))
	if a then
		hits += 1
	end
end
T.check(hits >= 340 and hits <= 460, "2000 seeded fish draws at the shore find clue_01 about 20% of the time (got " .. hits .. ")")
T.eq(table.concat(seqA, ","), table.concat(seqB, ","), "the same seed gives the same find sequence")

-- round trip through real JSON
local w = wire(board)
local back = EvidenceBoard.deserialize(Stub.jsonDecode(w), defs)
T.eq(wire(back), w, "deserialize(serialize()) serializes identically")
T.check(EvidenceBoard.isLinked(back, "clue_01", "clue_02") and EvidenceBoard.isLinked(back, "clue_02", "clue_03"), "the rebuilt board has the manual link and the recomputed automatic note")
T.eq(table.concat(EvidenceBoard.conclusions(back), ","), "concl_a,concl_b", "the rebuilt board reaches the same conclusions")
T.eq(#EvidenceBoard.pins(back), 5, "the rebuilt board has the same pins")
T.check(back.found.clue_01.dayN == 2 and back.found.clue_01.timeOfDay == 9.5, "the rebuilt board keeps the discovery meta")
local tampered = Stub.jsonDecode(w)
tampered.found[1].id = "clue_77"
T.throws(function() EvidenceBoard.deserialize(tampered, defs) end, "unknown clue id", "negative control: a save naming an unknown clue id is refused")
tampered = Stub.jsonDecode(w)
tampered.found[2].id = "clue_01"
T.throws(function() EvidenceBoard.deserialize(tampered, defs) end, "duplicate", "a duplicate discovery is refused")
tampered = Stub.jsonDecode(w)
tampered.found[1].timeOfDay = 25
T.throws(function() EvidenceBoard.deserialize(tampered, defs) end, "timeOfDay", "a discovery at 25:00 is refused")
tampered = Stub.jsonDecode(w)
tampered.links[1] = "link:clue_05+clue_06"
T.throws(function() EvidenceBoard.deserialize(tampered, defs) end, "not discovered", "a saved link whose end is not discovered is refused")
tampered = Stub.jsonDecode(w)
tampered.links[1] = "note_a"
T.throws(function() EvidenceBoard.deserialize(tampered, defs) end, "automatic", "an automatic link in the saved manual list is refused")
tampered = Stub.jsonDecode(w)
tampered.links[1] = "link:nothing"
T.throws(function() EvidenceBoard.deserialize(tampered, defs) end, "unknown link id", "an unknown link id is refused")
T.throws(function() EvidenceBoard.deserialize({ v = 2, found = {}, links = {} }, defs) end, "not a serialized", "a wrong version is refused")

-- merge
-- (a's discoveries are in time order: merge orders by time, so only then is merge(a, empty) == a)
local a = EvidenceBoard.new(defs)
EvidenceBoard.discover(a, "clue_02", ctx(1, 12, "pier"))
EvidenceBoard.discover(a, "clue_01", ctx(2, 9, "shore"))
EvidenceBoard.link(a, "clue_01", "clue_02")
local b = EvidenceBoard.new(defs)
EvidenceBoard.discover(b, "clue_03", ctx(1, 8, "town"))
EvidenceBoard.discover(b, "clue_01", ctx(1, 9, "reeds"))
EvidenceBoard.discover(b, "clue_04", ctx(2, 7, "town"))
local aBefore, bBefore = wire(a), wire(b)
local m = EvidenceBoard.merge(a, b)
T.eq(table.concat(m.order, ","), "clue_03,clue_01,clue_02,clue_04", "merged order is by discovery time")
T.check(m.found.clue_01.dayN == 1 and m.found.clue_01.zoneId == "reeds", "merge keeps the earlier discovery of clue_01")
T.check(EvidenceBoard.isLinked(m, "clue_01", "clue_02") and m.links["link:clue_01+clue_02"] == true, "merge keeps the manual link")
T.check(m.links.note_a == false, "merge recomputes the automatic note from the union")
T.eq(wire(EvidenceBoard.merge(b, a)), wire(m), "merge(a, b) serializes equal to merge(b, a)")
T.check(wire(a) == aBefore and wire(b) == bBefore, "merge leaves both inputs untouched")
T.eq(wire(EvidenceBoard.merge(a, EvidenceBoard.new(defs))), wire(a), "merging with an empty board is the identity")
T.throws(function() EvidenceBoard.merge(a, EvidenceBoard.new(rawDefs())) end, "different defs", "boards from two separate compiles cannot be merged")

-- compile refusals
local function compileWith(edit: (any) -> ())
	return function()
		local d = rawDefs()
		edit(d)
		EvidenceBoard.compile(d)
	end
end
T.throws(compileWith(function(d: any) d.clues.clue_01.kind = "rumour" end), "kind", "an unknown clue kind is refused")
T.throws(compileWith(function(d: any) d.clues.clue_01.source = "sky" end), "source", "an unknown clue source is refused")
T.throws(compileWith(function(d: any) d.clues.clue_01.chance = 1.5 end), "chance", "a chance above 1 is refused")
T.throws(compileWith(function(d: any) d.clues.clue_04.requires = { "clue_04" } end), "requires itself", "a clue requiring itself is refused")
T.throws(compileWith(function(d: any) d.clues["bad|id"] = { kind = "item", source = "fish", tags = {} } end), "must not contain", "a clue id with '|' is refused")
T.throws(compileWith(function(d: any) d.links[1].b = "clue_99" end), "unknown clue", "a link to an unknown clue is refused")
T.throws(compileWith(function(d: any) table.insert(d.links, { a = "clue_02", b = "clue_01", kind = "string" }) end), "already linked by", "a duplicate pair (either orientation) is refused")
T.throws(compileWith(function(d: any) d.links[1].kind = "rope" end), "kind", "an unknown link kind is refused")
T.throws(compileWith(function(d: any) d.conclusions[1].requires = { "nothing" } end), "unknown clue or link", "a conclusion requiring an unknown id is refused")
T.throws(compileWith(function(d: any) d.conclusions[2].id = "concl_a" end), "duplicate id", "a duplicate conclusion id is refused")

T.finish()
