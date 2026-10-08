-- EncounterLog_sandbox_driver.server.lua (About Fishing F1 cloud work; Cloud, 2026-10-08)
-- TEMPORARY. STUDIO ONLY. NOT PART OF THE GAME. A throwaway Script that fakes three encounters (a Good
-- press and a catch, a Late press that spooks, a Leave with no press) through EncounterLog, prints the
-- summary and writes toCsv into a StringValue "EncounterCsv" under ServerStorage, for Adrian to copy
-- from its Value in the Properties window into a file for tools/parity_report.py. Delete it after the
-- sandbox session; nothing references it.
--
-- Where the module lives: a `Fishing` folder next to this Script holding Shared/EncounterLog, or the
-- Rojo path (ReplicatedStorage.Fishing.Shared.EncounterLog) in the live tree.

local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local Fishing = script.Parent:WaitForChild("Fishing")
local EncounterLog = require(Fishing:WaitForChild("Shared"):WaitForChild("EncounterLog"))

local TAG = "[EncounterLog sandbox]"
local log = EncounterLog.new()
local t0 = os.clock()

-- 1: notice, two nips, swallow, a Good press, hooked, a jump, caught
EncounterLog.start(log, "sb-1", { anglerId = 1, fishId = "trout-1", speciesId = "trout", hookMode = "bed", t = t0 })
EncounterLog.event(log, "sb-1", "Notice", t0)
EncounterLog.event(log, "sb-1", "Nip", t0 + 4.083)
EncounterLog.event(log, "sb-1", "Nip", t0 + 6.0)
EncounterLog.event(log, "sb-1", "Swallow", t0 + 12.5)
EncounterLog.event(log, "sb-1", "Press", t0 + 12.7)
EncounterLog.event(log, "sb-1", "Verdict", t0 + 12.7, { verdict = "Good" })
EncounterLog.event(log, "sb-1", "Hooked", t0 + 12.8)
EncounterLog.event(log, "sb-1", "Jump", t0 + 15.0)
EncounterLog.event(log, "sb-1", "Caught", t0 + 31.2)
EncounterLog.finish(log, "sb-1", t0 + 31.2, "Caught")

-- 2: notice, a nip, swallow, a Late press, spooked
EncounterLog.start(log, "sb-2", { anglerId = 1, fishId = "trout-2", speciesId = "trout", hookMode = "mid", t = t0 + 40 })
EncounterLog.event(log, "sb-2", "Notice", t0 + 40)
EncounterLog.event(log, "sb-2", "Nip", t0 + 44.1)
EncounterLog.event(log, "sb-2", "Swallow", t0 + 49.0)
EncounterLog.event(log, "sb-2", "Press", t0 + 49.9)
EncounterLog.event(log, "sb-2", "Verdict", t0 + 49.9, { verdict = "Late" })
EncounterLog.event(log, "sb-2", "Spook", t0 + 49.9, { reason = "Late" })
EncounterLog.finish(log, "sb-2", t0 + 49.9, "Spook")

-- 3: notice, hover, no press, leaves
EncounterLog.start(log, "sb-3", { anglerId = 2, fishId = "trout-3", speciesId = "trout", hookMode = "lure", t = t0 + 60 })
EncounterLog.event(log, "sb-3", "Notice", t0 + 60)
EncounterLog.event(log, "sb-3", "Nip", t0 + 64.2)
EncounterLog.event(log, "sb-3", "Leave", t0 + 70.5)
EncounterLog.finish(log, "sb-3", t0 + 70.5, "Leave")

local records = EncounterLog.records(log)
for _, metric in { "noticeToFirstNip", "hoverS", "pressOffset", "fightS" } do
	local s = EncounterLog.summary(records, metric)
	print(TAG, string.format("%s: n=%d median=%s p95=%s", metric, s.n, tostring(s.median), tostring(s.p95)))
end

local csv = EncounterLog.toCsv(records)
local holder = ServerStorage:FindFirstChild("EncounterCsv") or Instance.new("StringValue")
holder.Name = "EncounterCsv"
holder.Value = csv
holder.Parent = ServerStorage

local jsonHolder = ServerStorage:FindFirstChild("EncounterJson") or Instance.new("StringValue")
jsonHolder.Name = "EncounterJson"
jsonHolder.Value = HttpService:JSONEncode(EncounterLog.toTable(records))
jsonHolder.Parent = ServerStorage

print(TAG, "wrote", #records, "records to ServerStorage.EncounterCsv (copy its Value into a .csv; then python tools/parity_report.py <file> --bands tools/parity_bands.json)")
print(csv)
