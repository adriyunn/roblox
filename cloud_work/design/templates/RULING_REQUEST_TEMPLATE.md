Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Ruling request template

One screen. Posted as a STATUS line `RULING <id> <topic> -> Coordinator` with the file `design/rulings/<id>_<topic>.md`, or pasted whole when it fits in one message. The Coordinator answers with the id and a letter.

---

```
# Ruling <id>: <topic>
Asked by: <Session> (<MACHINE>), <YYYY-MM-DD HH:MM UTC>

Question: <one line, answerable with a letter>

Blocks: <batch / file / review that cannot move until this is answered>

Options:
A. <what we would do>. Cost: <lines, hours, risk>. Fidelity: <matches / departs from the reference, how>.
B. <what we would do>. Cost: <...>. Fidelity: <...>.
C. <what we would do>. Cost: <...>. Fidelity: <...>.

Recommendation: <letter>, because <one line>.

Default if no answer in 2 h: <letter>. (The asker proceeds with it and says so in STATUS.)

Evidence:
- <path or clip ref, one line on what it shows>
- <path or clip ref>

Ruling (Coordinator): <letter>. <one line>. <date time>
```

---

## Rules
- One question per request. Two questions are two requests.
- Three options at most. If only two exist, write two. C is often "do nothing"; say its cost too.
- The default is not a threat; it is what keeps the batch moving. It must be a safe option (reversible, or the recommendation).
- Evidence is paths and clip refs, not pasted content.
- The Coordinator may answer with a letter alone. Anything more is a gift.

## Filled example: X01 bed-stall (as the transcripts record it)
```
# Ruling X01: bed-resting hook, bite timing
Asked by: Dev1 (Alienware), 2026-10-04

Question: when the hook lies on the bed, do we match the clips' 5-45 s hover (then bite or leave), or keep the model that predicts a 60 s stall?

Blocks: batch 2 (W3 FishBrain in w3/), the W4 verdicts, the feel review.

Options:
A. Aim all four sight rays at the hook's top when it lies on the bed: BedSightLiftM = 0.03 m (notice :1077, LOS :986, Seek :959 and :963; "lying on the bed" = hy - fish.bedY <= BodyBoxY/2 + lift; before the first bed query bedY = -inf, so aim at the centre). Cost: 4 call sites in FishBrain, oracle model B gains sight_y and a bed_seen flag, tests at g = 0.045; about 3 h. Fidelity: the fish hovers, bites or gives up within the clips' 5-45 s.
B. Raise the mouth floor above a bed-resting hook: BedMouthM = 0.054 m. Cost: one knob, no ray change; about 1 h. Fidelity: fixes the graze only when the bed estimate sits within 3 cm of the terrain; a backup if A is not enough.
C. Keep the current rays. Cost: none. Fidelity: the mouth sinks to bed + 0.04..0.055 m, the hook centre is at bed + 0.03 m, the mouth-to-hook ray grazes the bed (sampled at 1/4, 1/2, 3/4), a blocked ray sends the fish to Seek, Seek re-arms any bite timer with <= 1 s left and resets the 2 s give-up: the fish never bites and never leaves. No clip shows a 60 s stall.

Recommendation: A, with B kept as the backup knob.

Default if no answer in 2 h: A.

Evidence:
- evidence/X01/: hover frames behind the bite timing
- Dev1's diagnosis in the X01 bed-stall workflow (3 agents, 101 min)
- research R4 vs R2: R4 wins when they disagree

Ruling (Coordinator): A. Match the clips' 5-45 s hover rather than the predicted 60 s stall. BedMouthM stays as the backup knob. 2026-10-04.
```
