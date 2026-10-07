Written by Cloud (session roblox-9d) on 2026-10-07 without access to the project files;
the module `cloud_work/src/Fishing/Server/SaveData.lua` and `tests/savedata_test.luau` are real and pass here (PASS 97) against the stub DataStore in `tests/RobloxStub.luau`. The Roblox platform facts below are from memory of the DataStore documentation and must be checked by Dev1 against the current docs before the module is wired; Dev3 checks the two-server Studio test.

# WS-S: per-player save data (P20)

```
WS-S savedata (About Fishing F1; Cloud, 2026-10-07; rev 1)
Status: FOR RULING (rulings 1-3)
```

## Lead
One profile per player, loaded once with a session lock, written only through `UpdateAsync` and only when dirty, migrated by schema version, and never written when it could not be read.
When it is right a player never loses more than one autosave interval, two servers never fight over one record, and a corrupt or newer save is kept intact for a human to look at.

## Reference behaviour
The reference is a single-player game with one save; nothing to record. Ours is one record per player on a shared Roblox server (PARITY_rows_F2plus.md, P20). The facts to honour are Roblox's, not the reference's.

| Claim | Source | Ref | Value |
|---|---|---|---|
| DataStore requests are budgeted per request type; a call over budget is throttled | Roblox docs (check) | `GetRequestBudgetForRequestType` | the module waits below `budgetFloor` 5 |
| one value is at most 4 MB | Roblox docs (check) | 4,194,304 B | the module refuses a record over `maxBytes` 4,000,000 B after JSON encode |
| `UpdateAsync` reads the current value and writes atomically; a transform returning nil writes nothing | Roblox docs (check) | `UpdateAsync` | the lock refusal relies on nil = no write; `SetAsync` would overwrite blind |
| writes to one key more often than every 6 s are throttled | Roblox docs (check) | per-key cooldown | the retry and backoff absorb it |
| `game.JobId` is empty in Studio | Roblox docs (check) | `game.JobId` | the module mints a GUID so a Studio lock still means something |
| `BindToClose` callbacks get up to 30 s | Roblox docs (check) | `BindToClose` | `flushAll` must finish inside it; at 8 players, 8 writes |

## Our rule
- Key `u<UserId>` in the store `PlayerData`. The stored record is the data table plus `_v` (schema), `_lock = { jobId, t }` and `_savedAt`; `_lock` and `_savedAt` are stripped from `profile.data` on load. `deps` are injected (`DataStoreService`, `Players`, `HttpService`, `task`, `Enum`, `clock = os.time`, `warn`, `jobId = game.JobId`), so the suite runs on the stub and Studio runs on the real services.
- Load (`sd:load(player)`): `GetAsync` with retries; nil -> `defaults()`; a non-table -> read-only `corrupt`; `_v` above `schemaVersion` -> read-only `newer`; a live foreign lock -> `nil, "locked"`; then migrations `migrations[v]` run in order from the stored `_v` up (a missing or non-table step -> read-only `no-migration`); then one `UpdateAsync` claims the lock and persists the migrated record. The profile is clean after load. Returns `profile, "new" | "loaded" | "already-loaded"` or the read-only reasons, or `nil, "locked" | "GetAsync failed: .." | "UpdateAsync failed: .."`.
- Session lock: a lock is live when it is another server's and `now - t < lockStaleS` (1800 s), with `now` from `os.time` on every server. On load a stale lock is taken over; a live one refuses. The `UpdateAsync` transform re-reads the lock, so a claim that lands between our `GetAsync` and our `UpdateAsync` loses the race (transform returns nil, nothing written). On save any foreign lock refuses (`foreign-lock`), the profile stays dirty, the counter `refused` goes up. `release` clears `_lock` only when it is ours.
- Writes: `profile:set("gear.rod", id)` marks dirty; `save` writes only when dirty (or `force`), as one `UpdateAsync`; `_savedAt` and `_lock.t` take the clock at the write. A record that `JSONEncode` refuses or that exceeds `maxBytes` is not written and warns.
- Retries: every DataStore call gets `maxRetries` 5 attempts with waits `min(backoffS * 2^(attempt-1), backoffCapS)` = 1, 2, 4, 8 s (15 s to give up; the 16 s cap applies from a sixth attempt). Below `budgetFloor` 5 requests of that type the call waits the same backoff, at most 5 waits, before trying.
- Cadence: autosave every `autosaveS` 60 s for dirty profiles (a `task.delay` loop with a generation counter; `stopAutosave` ends it); `onPlayerRemoving` force-saves then releases; `game:BindToClose` -> `flushAll("close")` saves every dirty profile and releases every lock, dirty or not.
- Read-only profiles (`newer`, `corrupt`, `no-migration`) play from memory, are never written (zero `UpdateAsync` in the suite) and are not lock holders; the caller tells the player this session will not save. Never overwrite what cannot be read.
- Risk 1, clock skew: the lock compares `t` across servers, so only a wall clock shared by every server works (`os.time`), never `os.clock` or `tick`. A skew of seconds is nothing against 1800 s.
- Risk 2, a crash and a rejoin inside the stale window: a crashed server never releases; the player joining another server inside 1800 s gets `nil, "locked"`. Takeover rule: only a stale lock is taken, never a live one, because the live one may be a healthy server mid-write. The caller retries `load` every 5 s for 30 s, then kicks with a plain message (rejoin in a few minutes); at most one autosave interval of progress is at stake.
- Gap found while writing this note: `_lock.t` is refreshed only by a write, and autosave skips clean profiles, so an idle player's lock goes stale after 1800 s and another server could take it while they are still connected. Fix (Dev1, one line in the autosave tick): force a save when `now - p.savedAt >= lockStaleS / 2` (900 s), a heartbeat.

## Config keys
`SaveData.new(deps, opts)` options; nothing in `FishingConfig`.

| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `autosaveS` | `opts` | s | 60 | 30-300 | one write per dirty player per minute; at most 60 s lost on a crash (ruling 1) |
| `maxRetries` | `opts` | attempts | 5 | 3-8 | 15 s of backoff before giving up |
| `backoffS` | `opts` | s | 1 | 0.5-4 | the first wait |
| `backoffCapS` | `opts` | s | 16 | 8-60 | no single wait longer than this |
| `lockStaleS` | `opts` | s | 1800 | 300-3600 | longer than any healthy save gap (60 s) by 30x; the crash lockout (risk 2) |
| `budgetFloor` | `opts` | requests | 5 | 1-20 | headroom for the leave saves of several players at once |
| `maxBytes` | `opts` | B | 4,000,000 | <= 4,194,304 | under the platform limit with room for the lock fields |
| `schemaVersion` | `opts` | int | 1 | >= 1 | bump with every shape change, with a `migrations[from]` |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none | `StateRules` |
| Cues | none; the profile is server-only. `SetOption(key, value)` (WSH_options_panel_additions.md) and the F2 verbs write through `profile:set`; all proposed, defined in `design/WSN_net_v3_messages.md` (a sibling is writing it) | `FishingNet` v3 |
| Guard rules | none; no client message reaches SaveData directly | `RequestGuard` |
| Wire size | +0 B | `net_codec_test.luau` |

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Server/SaveData.lua` | new, as in `cloud_work/src`, plus the lock heartbeat | Dev1 | Dev3 |
| `ServerScriptService/ProfileService.server.lua` | new: `deps` from the real globals; `PlayerAdded` -> `load` (retry, kick); `PlayerRemoving` -> `onPlayerRemoving`; `BindToClose` -> `flushAll`; `startAutosave` once | Dev1 | Dev3 |
| `Fishing/Server/FishingServer.lua` | reads and writes through `profile:get` / `profile:set` (coins, loadout, box, log, options) | Dev1 | Dev3 |
| `tests/savedata_test.luau`, `tests/RobloxStub.luau` | adopt as is; add the heartbeat check | Dev3 | Dev1 |
| `PARITY_CHECKLIST.md`, `README.md` | P20 in the module's names | Dev3, WordAgent | Coordinator |

## Offline tests
| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/savedata_test.luau` | defaults stamped `_v`; existing data loads with `_lock` stripped and refreshed; migrations 1 -> 2 -> 3 in order and persisted; a missing migration and a newer `_v` give read-only profiles with zero `UpdateAsync`; two 503s then success (clock at 3 s); five 503s give up at 15 s; dot paths and dirty-only saves; a foreign lock refuses the save; a fresh foreign lock refuses the load, a 1801 s one is taken over, a lock claimed between Get and Update loses the race; autosave at 60 s and `stopAutosave`; `onPlayerRemoving` saves and releases; `flushAll` saves 2 of 3 and releases all; a budget of 2 delays the save by 3 s; an empty `JobId` becomes a GUID | a string record gives a read-only default profile; `set`, a forced `save` and `onPlayerRemoving` never overwrite it (the store still holds the string, zero `UpdateAsync`) | `PASS 97` |
| heartbeat check (Dev3 adds) | a clean profile idle for 900 s gets a forced write that refreshes `_lock.t` | a mutant without the heartbeat lets a second server take the lock at 1801 s while the first is loaded; must FAIL | `PASS 99` |

## Studio tests
Needs "Enable Studio Access to API Services" on a sandbox place; Studio's local test servers have no DataStore access (confirm), so the two-server rows use a published test place on two devices.

| # | Do | See | Evidence |
|---|---|---|---|
| 1 | join, catch, leave, rejoin | coins, box and log back as left; output `loaded` | server output in `evidence/WSS/` |
| 2 | join on device A, then join on device B inside a minute | B: `locked`, retries, then the kick message; A unaffected | both outputs |
| 3 | leave A, join B | B loads at once (A released) | outputs |
| 4 | kill A's server (stop the instance), join B inside 30 min | B locked until the stale window passes (ruling 3 if this is unacceptable) | outputs with times |
| 5 | write a record with `_v = 99` by hand in the DataStore editor | read-only `newer`, play continues, the record untouched after leaving | the editor |

## Rulings needed
1. Autosave interval.
   - A: 60 s as built. Cost: one write per dirty player per minute, well inside the budget at 8 players; at most 60 s lost on a crash. Fidelity: n/a.
   - B: 120 s. Cost: half the writes; up to 2 min lost. Fidelity: n/a.
   - Recommendation: A.
2. A load that fails after the retries (DataStore outage, not a lock).
   - A: kick with a plain message. Cost: the player cannot play during an outage; nothing is ever lost. Fidelity: n/a.
   - B: play read-only from defaults with a visible banner; nothing is written this session. Cost: a banner; a player who ignores it loses the session's progress. Fidelity: n/a.
   - Recommendation: B, because a session that cannot save is still a session, and the record is never touched. A `locked` load is not this case: retry 30 s then kick.
3. Where the lock lives.
   - A: inside the record, as built: one `UpdateAsync` carries data and lock, so they never disagree; the crash lockout is `lockStaleS`. Cost: none. Fidelity: n/a.
   - B: `MemoryStoreService` (a SortedMap entry per player with a TTL of about 120 s, refreshed by a heartbeat). Cost: a second service with its own budget and failures; two writes per save; the lock and the data can disagree after a partial failure. Gain: a crash frees the player in the TTL, not 30 min.
   - Recommendation: A for F2; B only if test row 4 turns into real complaints.

## PARITY rows
| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| P20 per-player save data | one save in the reference | `SaveData`: a profile per player with `_v`, migrations, a session lock, `UpdateAsync` merges, autosave 60 s, leave and close flushes, read-only on unreadable data | staged (module), planned (ProfileService) | `tests/savedata_test.luau` PASS 97 |
| P04 money readout | a total at the trader (V49) | `coins` lives in the profile; the round trip keeps it | staged | the dot-path and round-trip checks |

## Open questions
- The platform facts in the reference table against the current docs: budgets, 4 MB, the 6 s per-key cooldown, the 30 s close window (Dev1, before wiring).
- Whether Studio's local multi-client test can reach DataStores at all; if not, the two-server rows need the published place (Dev3).
- The lock heartbeat (the gap above) and whether a sell followed by a leave inside 6 s needs an explicit wait or the retry covers it (Dev1).
- A corrupt sub-record (a box that fails `deserialize`) inside a readable profile: whole profile read-only or that field reset in memory (Dev1 with WST_tacklebox.md).
- `log.records`-style growth: `_order` and `_profiles` are released on leave; confirm nothing holds a profile after `release` (Dev3, with the 8-angler stress run).
