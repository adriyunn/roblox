Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Token audit, 2026-10-04: where it went and ten settings to cut it

## The day in numbers
The weekly limit (`seven_day`) hit all six local sessions at about 17:50 UTC.

| Session | Model | Effort | ultracode | Context used at the limit | What dominated (Cloud's reading of the transcripts) |
|---|---|---|---|---|---|
| WordAgent (Alienware) | Sonnet | xhigh | on | 828,681 | `rows_batch2` built three times as items moved; README tables; seven `W34_*` suite-fix patches; relays |
| FableDev (MSI) | Opus | xhigh | on | 709,828 | batch-1 promotion script and W2.1 review; proving 6 patch orders on `FishingConfig.lua` commute; converting 16 CRLF files to LF; Dev2 rev 4-6b reviews |
| Coordinator | Opus | high | not stated | 430,439 | relays with hand-typed `size / hash` pairs, most re-relayed to 1-2 sessions; 7 monitor replies in 15 min; rulings |
| Dev1 (Alienware) | Opus | xhigh | on | 361,734 | three review workflows (3,809,068 subagent tokens on top, not in this column); X01 diagnosis; the re-freeze |
| Dev3 (MSI) | Opus | xhigh | on | 298,889 | the six-lens W2.1 review workflow (result never read back); then paused 05:34-17:50 |
| Dev2 (Alienware) | Opus | xhigh | not stated | 189,430 | FishPoolView rev 4 to 6b patch chain; held fish; Caught camera |
| Sum | | | | 2,819,001 | plus 3,809,068 in Dev1's subagents = about 6.6 M tokens visible |

"Context used" is the size of the window when the limit hit. Every turn re-sends the whole window, so what a session spends is roughly context size times turns, less what prompt caching serves. A 430 k context answered 7 times costs more than a 190 k context answered 7 times, whatever the answers say.

## The three workflow costs (Dev1's session)
| Workflow | Agents | Subagent tokens | Tool uses | Wall time | Failed on the limit | Usable result |
|---|---|---|---|---|---|---|
| review of Dev2 W4 held-fish FishingVisuals patch | 7 | 1,334,014 | 398 | 29 min | 3 of 7 | partial |
| X01 bed-stall diagnosis | 3 | 861,034 | not stated | 101 min | 2 of 3 | partial |
| Fix FableDev WS-D review findings | 7 | 1,614,020 | 467 | 44 min | the final consolidate agent | findings exist in the journal, no consolidated result |
| Sum | 17 | 3,809,068 | 865+ | 174 min | 6 of 17 | |

Dev3's "review of FableDev W2.1" (six-lens find, adversarial verify, synthesis) is not in this table: its token count is not in the transcript and its result was never read back. Whatever it cost, 100 % of it bought nothing.

Per review, 7 agents cost 1.3-1.6 M tokens. Three agents (find, refute, write) would have cost about 0.5-0.7 M for the same files, and the two lost consolidate steps would have had something on disk to consolidate.

## The monitor-reply cost
The Coordinator ran a Monitor on "new lines in FableDev/Dev3 MSI status files" and answered it at 17:37:40, 17:38:00, 17:38:20, 17:39:15, 17:43:49, 17:49:19 and 17:52:17: seven turns in 14 min 37 s, "nothing new" each time. Gaps: 20 s, 20 s, 55 s, 4 min 34 s, 5 min 30 s, 2 min 58 s.

| Case | Arithmetic | Input tokens |
|---|---|---|
| No caching | 7 x 430,439 | 3.01 M |
| With prompt caching | 5-min TTL, refreshed by each read, measured start to start. Six gaps under 5 min hit; the 5 min 30 s gap before 17:49:19 missed and re-wrote. 1-2 writes at 1.25x, 5-6 reads at about 0.1x (Opus 4.x; 0.05x on Opus 5.5) | 0.8-1.3 M uncached-equivalent |

Caching cuts the bill by about 3x. It is still waste, for four reasons:
1. The information content was zero seven times. The right number of turns was zero.
2. Each turn appends the monitor result and the reply (1-3 k tokens) to the window. Every later turn in the session carries them.
3. How the `seven_day` meter weights cache reads is not documented for the subscription. The API docs say cache reads do not count toward API input-token rate limits on most models; the weekly meter is a different thing. Confirm on the usage page before assuming reads are free.
4. The Coordinator was busy for 15 minutes saying nothing while Dev3 had been silent for 12 h. The monitor watched for new lines; the problem was the absence of lines.

## Ten settings
| # | Setting | Where | Why |
|---|---|---|---|
| 1 | Effort `medium` for relay and monitor turns; `xhigh` only inside review workflows and diagnoses | each session, at the start of a relay stretch (the harness's effort control; confirm the exact command in `/config` or `/help`) | a relay is copy work; thinking tokens at xhigh buy nothing there |
| 2 | ultracode off for WordAgent, and for FableDev's doc and script-doc work | the two sessions' settings | doc work needs volume, not depth; WordAgent at 828,681 is the largest context of the six |
| 3 | Review workflows capped at 3 agents: find, refute, write. A 4th (second finder) and 5th (second refuter) only when the first pass reports a BLOCKER | the workflow scripts | 7 agents cost 1.3-1.6 M per review; 6 of 17 agents died on the limit |
| 4 | Monitor on the STATUS file's modification time, 30-min minimum interval, alert on change and on silence over 2 h; a monitor that finds nothing writes nothing | the Coordinator's monitor | 7 "nothing new" replies in 15 min; see `REVIEW_BACKUP_RULE.md` for the pause detector |
| 5 | Relays carry a path and a commit SHA (7 chars), never a `size / hash` pair and never pasted content, once git is in (`GIT_MIGRATION.md`); the Coordinator posts once to the STATUS file, sessions read it; no re-relay | the Coordinator, TEAM_RULES | hashes typed by hand are long, error-prone and were copied to 1-2 more sessions each |
| 6 | Every workflow agent writes its partial result to disk before the consolidate step: `design/reviews/partial/<workflow>_<agent>.md`; the consolidate step reads disk | the workflow scripts | two consolidate steps failed; the findings survived only in `journal.jsonl` |
| 7 | Compaction at fixed points: after a verdict is filed, after a window closes, before a workflow launches; no session starts a heavy job above about 250 k context; compact with a focus line ("keep open rulings, SHAs, verdicts; drop relay text") | each session | contexts of 190 k-829 k were carried on every turn; the auto-compact setting's name and threshold should be confirmed in `/config` |
| 8 | Heavy reviews and workflows right after the weekly reset (Oct 6, 2 pm Denver = 20:00 UTC); docs and relays at the end of the week | the Coordinator's plan | work that dies on the limit is paid for twice |
| 9 | Generated files are built once, after the input is frozen, by the holder's script: rows files, README tables | WordAgent, FableDev | `rows_batch2` was built three times before the Coordinator ruled "build once after batch 2 final" |
| 10 | A session reads its workflow's result back in its next turn and files the verdict; a session about to pause does not launch a workflow | every session | Dev3's six-lens review was never read; a result nobody reads is 100 % waste |

### Recovering a failed consolidate from `journal.jsonl`
The workflows keep `journal.jsonl`: one JSON record per line, one or more per agent step, each with the step name and its output. To recover the WS-D fix workflow without re-running 1.6 M tokens:

1. Read the journal; keep the last record per agent that has an output.
2. Write each output to `design/reviews/partial/<workflow>_<agent>.md` (this is what rule 6 makes automatic).
3. Run one small agent, effort `high`, with only those files as input: "consolidate these into one review in the REVIEW_TEMPLATE shape". Expect about 50-100 k tokens, not 1.6 M.

```python
# recover_partials.py (sketch; the record field names come from the real journal and must be checked)
import json, pathlib, sys
journal, outdir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
last = {}
for line in journal.read_text(encoding="utf-8").splitlines():
    rec = json.loads(line)
    if rec.get("output"):
        last[rec.get("step") or rec.get("agent")] = rec["output"]
outdir.mkdir(parents=True, exist_ok=True)
for step, text in last.items():
    (outdir / f"{journal.parent.name}_{step}.md").write_text(text, encoding="utf-8", newline="\n")
print(f"recovered {len(last)} partial results")
```

## Expected savings (rough, labelled estimates)
| Setting | Baseline on 2026-10-04 | Expected after | Saving | Confidence |
|---|---|---|---|---|
| 4: monitor on mtime, 30 min | 7 turns in 15 min, 0.8-3.0 M input | 0 turns when nothing changed; 1 per 30 min otherwise | 85-100 % of monitor tokens | rough |
| 3: 3-agent reviews | 1.33 M and 1.61 M per 7-agent review | 0.5-0.7 M per review | about 55 % per review | rough |
| 6: partials on disk | 1.61 M at risk when one consolidate failed | re-run the consolidate only, 50-100 k | avoids re-running about 1.5 M per failure | rough |
| 1: effort medium on relays | Coordinator 430 k, much of it relays | fewer thinking and output tokens per relay | 20-30 % of Coordinator spend | rough |
| 2: ultracode off, medium for docs | WordAgent 829 k | smaller turns for the same files | 30-40 % of WordAgent spend | rough |
| 9: build once | 3 builds of `rows_batch2` | 1 build | 67 % of that job | exact for the count |
| 5: SHA relays, no re-relay | hash pairs typed and copied to 1-2 sessions | one path + 7 chars, read from a file | about 50 % of relay volume | rough |
| 10: results read back | one workflow unread | read and filed | 100 % of that workflow | exact for that case |
| 7: compaction at fixed points | 190-829 k carried every turn | under 250 k before heavy jobs | 20-40 % of per-turn input | rough |
| 8: reviews after the reset | 6 of 17 agents failed on the limit | 0 failed | the failed agents' tokens (split unknown) | rough |
| All ten together | about 6.6 M visible for the day's work | about 3-3.5 M for the same work | 45-55 % | rough |

None of these lowers the bar: every review keeps a finder, a refuter and a written verdict; every window keeps its gates; the effort cut applies to copy work, not to code.
