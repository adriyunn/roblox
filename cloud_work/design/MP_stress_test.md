Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files;
every line number, key name and existing-code claim below comes from the team's transcripts and must be checked by Dev3 (tests, net, guard) and Dev1 (FishPool, FishJudge, FishingServer) against the real files.

# MP: a multiplayer stress test for the shared fish pool

Status: DRAFT, FOR RULING (section 7). Net and state impact: none (no new cue, state, guard rule or wire byte;
`CueRoute` is a lift of the existing fan-out into a pure module).

**Decision.** One lake, N anglers (2, 4, 8), a scripted driver on every client, the server's EncounterLog as the record.
The test proves the pool's sharing rules under load: one fish per angler at a time, Spook 255 to every engaged angler
and nobody else, a Late press by A spooking B's fish with exactly one Spook cue (the J-2 ruling), no starvation, no
duplicate ids, RequestGuard and LatencyBudget holding under 8 clients, the held fish visible to every observer, the
strain loop owner-only with the snap 3D within 40 m. The offline half is a FishPool suite with 8 fake anglers, checks
Z1..Z12, runnable under the CLI. The evidence is one file per N.

## 1. What to verify

| # | Rule | Where it is decided |
|---|---|---|
| R1 | A fish is engaged by at most one angler at any step | FishPool `takeHooked` / engagement bookkeeping |
| R2 | Spook with fish id 255 reaches every engaged angler and no one else | FishingServer's cue fan-out |
| R3 | A Late press by A ejects A's fish and spooks B's engaged fish (J-2); exactly one Spook cue, id 255 | FishJudge (Late eject at tS + 0.55 + LB) and FishPool |
| R4 | The pool refills; no angler with a presented hook in valid water waits more than `StarveMaxS` for a Notice | FishPool refill, `SPAWN_RETRY_S`, `RehomeAfterS`, GiveUp |
| R5 | RequestGuard rejects no legitimate message at 8 clients' rates; a flooding client is throttled alone | RequestGuard |
| R6 | LatencyBudget applies each client's own LB to its verdicts | LatencyBudget, FishJudge |
| R7 | Cue count per second stays under the ceiling, no burst over 10 cues in one step | FishingServer |
| R8 | No duplicate fish id across anglers at any time; a released fish is re-engaged only after Cooldown U(4,5) s | FishPool `handBack` / `released` |
| R9 | The held fish (CatchScene, Holding) shows for every observer, not only the owner | FishingVisuals (held fish from the presented state) |
| R10 | The strain loop plays on the owner only; the snap is a 3D sound heard within 40 m and not beyond | StrainAudio |

## 2. Procedure (Studio local server)

Studio's Test tab, "Clients and Servers", N players, where N is 2, 4 and 8 (8 is Studio's limit; one machine runs all
clients, so the 8-player run is a correctness run, not a frame-time run; PERF_budget.md covers frame time at 4).

1. Place: a sandbox copy of Place1 with the W3+W4 batch, pool size per section 7 ruling 1, `PerfProbe` on.
2. Slots: N shore slots 3 m apart along one bank so the rings overlap (two anglers' rings must share water, or sharing
   is never exercised). The driver teleports its player to slot k (k = the player's join order).
3. Driver: `tests/MPStressDriver.client.lua`, a throwaway LocalScript in the AF1Playtest style (Dev3 owns; not part of
   the game). It uses the same client entry points AF1Playtest uses to cast and press (Dev1 names them; the W4 patch
   gave `sendCatchDone()` as the model: public functions on InputController, no synthetic mouse events). Per angler:
   - wait 2 s x k after spawn (stagger the first casts), enter Aim, cast at power 0.6 toward the lake centre;
   - wait for the Notice cue; log it;
   - on the Swallow cue, press per the schedule: `Good` = Swallow startT + 0.20 s; `Early` = 0.30 s before the Swallow
     (on the last Nip; the driver predicts from the Nip cadence, or presses on a Nip); `Late` = the Good window's end +
     LB/2 (Dev3 reads the window from FishJudge's constants, never hard-codes them);
   - schedule per angler, seeded by k: `Good, Late, Early, Good, Good, Late, Early, Good` then repeat; so at any
     moment some angler is pressing Late while another is engaged (R3 gets exercised about N/4 times per cycle);
   - after a hook set: hold the reel until CatchScene or Snap, then `sendCatchDone()`; after BaitGone or Spook, reel in,
     re-cast; after Holding, stow, re-cast;
   - run for 10 minutes, then print the client's own counters.
4. Server log: EncounterLog (`cloud_work/src/Fishing/Shared/EncounterLog.lua`; Dev1 wires its three calls in
   FishingServer as that file's header lists). One encounter = one fish engaging one angler: `start(log, id, info)` at
   the Notice with `info = { anglerId, fishId, speciesId, hookMode = "bed" | "mid" | "lure", t = tNotice }` and
   `id = anglerId .. ":" .. fishId .. ":" .. tNotice`; `event(log, id, name, t, data)` for every cue the server sends
   that encounter (Nip, Swallow, Press, Verdict {verdict}, Hooked, Jump, Snap, Caught, GiveUp, Spook {reason}, Leave);
   `finish(log, id, t, outcome)` at Caught / Snap / GiveUp / Leave / Spook. Export both forms at the end of the run:
   `toCsv(records)` (header `id,anglerId,fishId,speciesId,hookMode,outcome,tNotice,tEnd,noticeToFirstNip,hoverS,pressOffset,verdict,fightS,jumps,spooks`)
   for the parity bands, and `HttpService:JSONEncode(toTable(records))`, which keeps every record's `events` with their
   times; the checker reads the JSON because R1..R3 and R8 need the timeline. Beside it, a one-line-per-second server
   tally `CUES t=<s> Notice=<n> Nip=<n> Swallow=<n> Spook=<n> ... maxStep=<n>` of cues actually sent (R3's "exactly one"
   and R7 are wire counts, which EncounterLog does not hold). The driver's client log counts cues received per kind and
   stamps the client time of each press, for the latency column.
5. Observers: the Studio server view (every fish, every angler) and one client window per run watched for R9 (a held
   fish on another angler) and R10 (no strain loop while another angler fights; a snap heard at 30 m, not at 60 m: two
   slots at those distances in the 4- and 8-player runs).
6. After 10 minutes: run `tools/mp_stress_check.py` (Dev3; new) over the server log; it prints one line per rule
   R1..R10 with counts and PASS/FAIL.

Verdicts the checker computes (from the JSON records, the CUES tally and the client counts):
- R1: encounters are intervals [tNotice, tEnd] per (anglerId, fishId); no two encounters with the same fishId and
  different anglerIds overlap in time.
- R2: for every Spook at time t, the set of encounters holding a Spook event at t equals the set of encounters open at
  t (every engaged angler got it); the client counts show 0 Spook cues on clients with no open encounter at t.
- R3: for every encounter with Verdict {verdict = "Late"} at t: that encounter ends (the Late eject), every other
  encounter open at t has a Spook event at t, and the client counts show +1 Spook on each engaged client and +0 on the
  rest, with the CUES tally's Spook count for that second equal to the number of Late presses in it (one cue per Late
  press, fanned out by the server; not one per spooked fish).
- R4: per angler, the longest gap between a Presenting start (the driver's client log) and the next encounter's
  tNotice <= `StarveMaxS` (60 s).
- R5: RequestGuard rejections of driver messages = 0 (the server's guard counters); the flood client (section 3) is
  throttled, its neighbours not.
- R7: per second, the CUES tally <= the per-angler ceiling x anglers; the tally's `maxStep` (the most cues sent in one
  step that second) <= 10.
- R8: no two open encounters share a fishId; for each fishId, the gap from one encounter's tEnd to the next encounter's
  tNotice on that fish >= 4 s (Cooldown U(4,5)).
- Parity under load: `python tools/parity_report.py <csv> --bands tools/parity_bands.json` on the run's CSV; the
  per-angler numbers (noticeToFirstNip 4.083 s, hoverS 5..45 s on bed hooks) must still sit in band with N anglers.

## 3. The flood client (R5)

In the 4- and 8-player runs, one driver (k = N) runs a second schedule for 60 s: hold on/off at 20 Hz and aim updates at
60 Hz. Expect RequestGuard to throttle that client (its rejection count > 0) and every other client's rejection count
to stay 0. Then it returns to the normal schedule and must recover (its next Notice arrives).

## 4. The offline half: `tests/wsa/fishpool_mp_test.luau` (8 fake anglers, Luau CLI)

The FishPool, FishJudge and the server's cue fan-out run under a fake clock with 8 fake anglers that follow the section
2 schedule. Where FishingServer's fan-out is not a pure function, Dev1 lifts the recipient computation into
`Fishing/Shared/CueRoute.lua` (pure: `recipients(cue, engagedSet, ownerId) -> set`) so the suite and the server share it.

| Check | What it asserts | Negative control |
|---|---|---|
| Z1 | 8 anglers, 8 fish, 10,000 steps: at every step the engaged (fish, angler) pairs have unique fish ids | a mutant that skips the engaged check lets two anglers take one fish: Z1 FAILs |
| Z2 | no angler with a hook presented in valid water waits > 60 simulated s for a Notice | pool size 2 with 8 anglers makes Z2 FAIL (the starvation case, kept as the control) |
| Z3 | `CueRoute.recipients(Spook 255)` equals the engaged set exactly, for 1,000 random engaged sets | a mutant that adds the owner when not engaged FAILs |
| Z4 | A presses Late while B is engaged: A's fish ejects, B's fish spooks (REASON per J-2), exactly one Spook cue with id 255, C (not engaged) gets nothing | a mutant that emits one cue per spooked fish FAILs (two cues) |
| Z5 | fish ids handed out in one step are unique; a released fish is re-engaged no sooner than 4 s and no later than 5 s + one step (Cooldown U(4,5)) | a mutant cooldown of 0 FAILs |
| Z6 | pool conservation: swimming + hooked + refilling = pool size after every `takeHooked`, `handBack`, `released`, `endHooked('Caught'|'Snap'|'GiveUp')` over 10,000 steps | a mutant that forgets `handBack` FAILs |
| Z7 | after `endHooked('Caught')` the slot refills within 3 x `SPAWN_RETRY_S`; GiveUp fallbacks <= 10% of refills on the flat test bed | |
| Z8 | RequestGuard with 8 fake clients at the maximum legal cadence: 0 rejections; client 8 at 2x cadence: rejected > 0, clients 1..7 still 0 | |
| Z9 | LatencyBudget: injected RTTs 20, 50, 100, 150, 200, 250, 300, 400 ms for the 8 clients; a press at the Good/Late boundary flips verdict with the client's own LB and no one else's | a mutant using a shared LB FAILs |
| Z10 | cue rate over 60 simulated s with 8 anglers: <= the per-angler ceiling; no step with > 10 cues | |
| Z11 | the fish record (species, lengthCm) for an angler in CatchScene/Holding is in the replicated state every observer reads, not in an owner-only message | a mutant that puts it in the owner cue FAILs |
| Z12 | StrainAudio's routing predicate: loop plays iff `isOwner`; snap plays iff `distance <= 40 m`; 40.0 plays, 40.1 does not | |

Each check prints one line; the suite ends `PASS 12` or `FAIL k of 12` and exits non-zero on FAIL. The mutants run
under `--mutant <name>` and the suite asserts the named check FAILs.

## 5. Pass criteria

- Offline: `luau fishpool_mp_test.luau` -> `PASS 12`; every listed mutant -> the named FAIL.
- Studio, for N = 2, 4 and 8: the checker prints PASS on R1..R8; R9 and R10 observed and screenshotted; the flood client
  throttled alone and recovered; 0 Luau errors in the server output; PerfProbe's `AF_FishStep` median under
  PERF_budget.md's budget at N = 4 (N = 8 is not a frame-time run).
- Any FAIL names the rule, the fish id and the server time, and is filed as a finding in the evidence file.

## 6. Evidence file: `evidence/MP/mp_stress_<date>_<N>p.md` (one per N)

Sections: setup (Studio version, place size/hash, `FishingConfig` hash, pool size, slot positions, driver hash,
schedule seed); the checker's R1..R10 lines; the counts table (per angler: casts, Notices, Nips, Swallows, presses by
verdict, Catches, Snaps, Spooks sent/received, RequestGuard rejections, median client-to-server press latency); the
flood client's 60 s window; R9/R10 screenshots' file names; beside the file: `mp_stress_<date>_<N>p.csv`
(`EncounterLog.toCsv`), `mp_stress_<date>_<N>p.json` (`toTable`, with the events), `mp_stress_<date>_<N>p_cues.log`
(the CUES tally) and the N client count files; the `parity_report.py` band lines; the offline suite's `PASS 12` output;
verdict.

## 7. Rulings needed (Coordinator)

1. Pool size with N anglers: fixed at 8 per lake (then Z2 is a hard test at 8 anglers, as it should be if the fish are
   shared) or `max(8, 2 x anglers)` (then Z2 is easy). Proposal: fixed 8, and `StarveMaxS = 60 s` as the rule; if 8
   anglers starve, that is a design fact to know before R1, not a test to loosen.
2. J-2 cue semantics: one Spook cue with id 255 to every engaged angler per Late press (what Z4 asserts), not one cue per
   spooked fish. Confirm against the J-2 ruling text.
3. Is the stress test part of the F1 close-out (the runbook already has the two-player test) or R1? Proposal: N = 2 at
   close-out with the offline suite; N = 4 and 8 in R1.
4. `CueRoute.lua` under `Fishing/Shared/` so the fan-out is testable offline; Dev1 reviews.
5. The driver's press timings (section 2 step 3) read FishJudge's constants at run time; confirm Dev3 may require
   FishJudge from the test LocalScript (it is a server module today; the constants may need a small shared table).

## 8. PARITY

The reference is single-player: one fish, one angler, one line. Multiplayer is ours. What we keep from the reference per
angler is unchanged by sharing: the notice-to-nip 4.083 s, the Early/Good/Late windows, the Late eject at tS + 0.55 + LB,
the spook rules. The test's job is to show that two anglers on one lake each still get the reference's encounter.

## 9. Acceptance tests

Section 4 (offline, Z1..Z12 with their mutants) and section 5 (Studio, N = 2/4/8). The offline suite is the gate for any
FishPool, FishJudge or cue fan-out patch after this note; the Studio runs are the gate for the close-out (N = 2) and R1
(N = 4, 8) per ruling 3.

## 10. Who does what

- Dev3: `tests/MPStressDriver.client.lua`, `tools/mp_stress_check.py`, `tests/wsa/fishpool_mp_test.luau` (Z1..Z12 and
  the mutants), the Studio runs, the evidence files, PARITY_CHECKLIST rows.
- Dev1: `Fishing/Shared/CueRoute.lua` (new, pure), the FishPool seams the suite needs (fake clock, fake anglers,
  injected `bedAt`), confirmation of the J-2 semantics in `FishJudge.lua` (and the stale `:12` header and `:19` comment
  while there), the EncounterLog `start`/`event`/`finish` calls in FishingServer (the integration points in that file's
  header) and the per-second CUES tally.
- Dev2: R9 and R10 observation in the client windows; a `StrainAudio` routing predicate exposed for Z12 if it is inline.
- FableDev: reviews the suite and the checker.
- Adrian: watches the N = 2 close-out run; no hand steps.
- Coordinator: section 7.
