--!strict
-- EncounterReplay (About Fishing F1, WS-P; Cloud, 2026-10-06; design/WSP_parity_log.md)
-- Record-and-replay for net traffic. A Recorder taps every message one side sends ("out") or receives
-- ("in") with a time relative to the recording start; stop() yields a tape. serialize/deserialize make
-- the tape JSON-safe for a StringValue or a file. A Player feeds the "in" entries of a tape back to a
-- sink in time order and checks what the side under test sends against the recorded "out" entries, so a
-- reviewer can reproduce an encounter offline and see exactly which message differed and when.
--
-- WRITTEN WITHOUT THE PROJECT FILES. Integration points a dev must wire:
--   * FishingNet (server) / FishingNetClient (client): call rec:tap("out", channel, payload) just before a
--     remote fires and rec:tap("in", channel, payload) at the top of the OnServerEvent / OnClientEvent
--     handler, after the v2 codec decodes. channel = the remote or cue name ("Cue/Notice", "Press");
--     payload = the decoded JSON-safe table (string keys or arrays, finite numbers). Tap one side only.
--   * clock = os.clock on either side (only differences matter). A dev verb ("RecordEncounter") makes a
--     Recorder, stop() it at the catch scene, and HttpService:JSONEncode(serialize(tape)) into a
--     StringValue or the output for Adrian to copy.
--   * Replay in an offline test: Player.new(tape, function(channel, payload) <call the handler> end);
--     player:step(t) at each time of interest; where the handler would fire a remote, call
--     player:expectOut(channel, payload); player:report() lists every mismatch with t and channel.

local EncounterReplay = {}

export type Entry = { t: number, dir: string, channel: string, payload: any }
export type Tape = { v: number, t0: number, entries: { Entry }, dropped: number }
export type Mismatch = { t: number, channel: string, expected: any, got: any, gotChannel: string? }
export type Report = { delivered: number, outMatched: number, outMismatched: number, outPending: number, mismatches: { Mismatch } }

local TAPE_VERSION = 1
EncounterReplay.TAPE_VERSION = TAPE_VERSION

-- Deep copy of a JSON-like value (tables by value, everything else as is).
function EncounterReplay.deepCopy(v: any): any
	if typeof(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = EncounterReplay.deepCopy(x)
	end
	return out
end

-- Structural equality: same keys both ways and equal leaves; { 1, 2 } ~= { a = 1, b = 2 }. Two NaN
-- leaves count as equal (NaN never equals itself, which made every tape holding one mismatch).
function EncounterReplay.deepEqual(a: any, b: any): boolean
	if a == b or (a ~= a and b ~= b) then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not EncounterReplay.deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- ---------------------------------------------------------------- Recorder
local Recorder = {}
Recorder.__index = Recorder
type RecorderFields = { _clock: () -> number, _t0: number, _buf: { Entry }, _head: number, _count: number, _max: number, dropped: number, stopped: boolean }
export type Recorder = typeof(setmetatable({} :: RecorderFields, Recorder))

-- A recorder started now; maxEntries (default 10000) is a ring: the oldest entry drops, dropped counts.
function Recorder.new(clock: () -> number, maxEntries: number?): Recorder
	assert(typeof(clock) == "function", "Recorder.new: clock must be a function")
	local max = maxEntries or 10000
	assert(typeof(max) == "number" and max >= 1 and max == math.floor(max), "Recorder.new: maxEntries must be a positive integer")
	local self: RecorderFields = { _clock = clock, _t0 = clock(), _buf = {}, _head = 1, _count = 0, _max = max, dropped = 0, stopped = false }
	return setmetatable(self, Recorder)
end

-- Records one message: dir = "in" (received by this side) | "out" (sent); the payload is copied.
function Recorder.tap(self: Recorder, dir: string, channel: string, payload: any)
	assert(not self.stopped, "Recorder.tap: recorder is stopped")
	assert(dir == "in" or dir == "out", "Recorder.tap: dir must be \"in\" or \"out\", got " .. tostring(dir))
	assert(typeof(channel) == "string", "Recorder.tap: channel must be a string")
	local e: Entry = { t = self._clock() - self._t0, dir = dir, channel = channel, payload = EncounterReplay.deepCopy(payload) }
	if self._count < self._max then
		self._buf[(self._head + self._count - 1) % self._max + 1] = e
		self._count += 1
	else
		self._buf[self._head] = e
		self._head = self._head % self._max + 1
		self.dropped += 1
	end
end

-- Entries held right now (at most maxEntries).
function Recorder.count(self: Recorder): number
	return self._count
end

-- Stops recording and returns the tape { v, t0, entries (oldest first, t relative to t0), dropped }.
function Recorder.stop(self: Recorder): Tape
	self.stopped = true
	local entries: { Entry } = {}
	for i = 0, self._count - 1 do
		entries[i + 1] = self._buf[(self._head + i - 1) % self._max + 1]
	end
	return { v = TAPE_VERSION, t0 = self._t0, entries = entries, dropped = self.dropped }
end

EncounterReplay.Recorder = Recorder

-- ---------------------------------------------------------------- serialize / deserialize
-- A JSON-safe plain copy of the tape (HttpService:JSONEncode ready).
function EncounterReplay.serialize(tape: Tape): { [string]: any }
	local entries = {}
	for i, e in tape.entries do
		entries[i] = { t = e.t, dir = e.dir, channel = e.channel, payload = EncounterReplay.deepCopy(e.payload) }
	end
	return { v = tape.v, t0 = tape.t0, entries = entries, dropped = tape.dropped or 0 }
end

-- Validates a decoded table and returns a Tape; errors on another version or a malformed entry.
function EncounterReplay.deserialize(tbl: any): Tape
	assert(typeof(tbl) == "table", "EncounterReplay.deserialize: expected a table")
	if tbl.v ~= TAPE_VERSION then
		error(string.format("EncounterReplay.deserialize: unsupported tape version %s (this build reads %d)", tostring(tbl.v), TAPE_VERSION))
	end
	assert(typeof(tbl.t0) == "number", "EncounterReplay.deserialize: t0 must be a number")
	assert(typeof(tbl.entries) == "table", "EncounterReplay.deserialize: entries must be an array")
	local keyCount = 0
	for _ in tbl.entries do
		keyCount += 1
	end
	assert(keyCount == #tbl.entries, "EncounterReplay.deserialize: entries must be an array (1..n), not a map")
	local entries: { Entry } = {}
	local lastT = -math.huge
	for i, raw in ipairs(tbl.entries) do
		local e: any = raw
		assert(typeof(e) == "table" and typeof(e.t) == "number" and typeof(e.channel) == "string", "EncounterReplay.deserialize: bad entry " .. i)
		assert(e.dir == "in" or e.dir == "out", "EncounterReplay.deserialize: bad dir in entry " .. i)
		assert(e.t >= lastT, "EncounterReplay.deserialize: entries out of time order at " .. i)
		lastT = e.t
		entries[i] = { t = e.t, dir = e.dir, channel = e.channel, payload = EncounterReplay.deepCopy(e.payload) }
	end
	return { v = TAPE_VERSION, t0 = tbl.t0, entries = entries, dropped = if typeof(tbl.dropped) == "number" then tbl.dropped else 0 }
end

-- ---------------------------------------------------------------- Player
local Player = {}
Player.__index = Player
type PlayerFields = {
	_sink: (string, any) -> (),
	_ins: { Entry },
	_outs: { Entry },
	_inIdx: number,
	_outIdx: number,
	_now: number,
	delivered: number,
	outMatched: number,
	outMismatched: number,
	mismatches: { Mismatch },
}
export type Player = typeof(setmetatable({} :: PlayerFields, Player))

-- A player over a tape; sink(channel, payload) receives every "in" entry as step() reaches it.
function Player.new(tape: Tape, sink: (string, any) -> ()): Player
	assert(typeof(tape) == "table" and typeof(tape.entries) == "table", "Player.new: tape required")
	assert(typeof(sink) == "function", "Player.new: sink must be a function")
	local ins: { Entry }, outs: { Entry } = {}, {}
	for _, e in tape.entries do
		table.insert(if e.dir == "in" then ins else outs, e)
	end
	local self: PlayerFields = {
		_sink = sink, _ins = ins, _outs = outs, _inIdx = 1, _outIdx = 1, _now = -math.huge,
		delivered = 0, outMatched = 0, outMismatched = 0, mismatches = {},
	}
	return setmetatable(self, Player)
end

-- Delivers every undelivered "in" entry with t <= untilT, in order; returns how many. The replay time
-- moves to untilT first, so an expectOut raised from inside the sink reports this step's time.
function Player.step(self: Player, untilT: number): number
	if untilT > self._now then
		self._now = untilT
	end
	local n = 0
	while self._inIdx <= #self._ins and self._ins[self._inIdx].t <= untilT do
		local e = self._ins[self._inIdx]
		self._inIdx += 1
		n += 1
		self.delivered += 1
		self._sink(e.channel, EncounterReplay.deepCopy(e.payload))
	end
	return n
end

-- The replay time (the largest untilT stepped to so far).
function Player.now(self: Player): number
	return self._now
end

-- True once every "in" entry has been delivered.
function Player.done(self: Player): boolean
	return self._inIdx > #self._ins
end

-- Checks the next recorded "out" entry against what the side under test sent (channel + deep-equal
-- payload). Records a mismatch { t, channel, expected, got } otherwise. Returns ok.
function Player.expectOut(self: Player, channel: string, payload: any): boolean
	local e = self._outs[self._outIdx]
	if e == nil then
		self.outMismatched += 1
		table.insert(self.mismatches, { t = self._now, channel = channel, expected = nil, got = payload, gotChannel = channel })
		return false
	end
	self._outIdx += 1
	if e.channel == channel and EncounterReplay.deepEqual(e.payload, payload) then
		self.outMatched += 1
		return true
	end
	self.outMismatched += 1
	table.insert(self.mismatches, { t = e.t, channel = e.channel, expected = EncounterReplay.deepCopy(e.payload), got = payload, gotChannel = channel })
	return false
end

-- Recorded "out" entries at or before now that the side under test has not produced yet.
function Player.pendingOut(self: Player): number
	local n = 0
	for i = self._outIdx, #self._outs do
		if self._outs[i].t <= self._now then
			n += 1
		end
	end
	return n
end

-- { delivered, outMatched, outMismatched, outPending, mismatches }.
function Player.report(self: Player): Report
	return {
		delivered = self.delivered,
		outMatched = self.outMatched,
		outMismatched = self.outMismatched,
		outPending = self:pendingOut(),
		mismatches = EncounterReplay.deepCopy(self.mismatches),
	}
end

EncounterReplay.Player = Player

return EncounterReplay
