Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
Numbers are from the transcripts; the proposals are for the Coordinator to rule on.

# Design note template

File name: `design/WS<letter>_<topic>.md` (detail in `design/detail/`). Fill every section; write "none" rather than leaving one out. Keep sentences short, give units, put items with attributes in tables.

---

```
<WS letter> <topic> (About Fishing F1; <Author>, <YYYY-MM-DD>; rev <n>)
Status: DRAFT | FOR RULING | APPROVED for fidelity (<Coordinator>, <date>) | SUPERSEDED by <note>
```

## Lead
Two lines. The decision this note makes, and what the player feels when it is right.

## Reference behaviour
What About Fishing does, with the source of each claim. R4 (the recordings) wins over R1/R2 (the recovered source) when they disagree.

| Claim | Source | Ref | Value |
|---|---|---|---|
| the fish hovers before the first nip | R4 | clip V17 0:42-1:05 | 5-45 s |
| notice to first nip | R2 | `fish_brain.gd:<line>` | 4.083 s |

Clip refs: `V<nn> m:ss-m:ss` from `clips/INDEX.md`. Source refs: `<file>:<line>` from `research/R1_*` or `R2_*`.

## Our rule
What GameOne does, in GameOne's own terms. One paragraph or a short list. Where we differ from the reference, say so and say why (art, world, sounds, or a ruling).

## Config keys
All keys this note adds or changes. Names end in `M` (metres), `S` (seconds), `Deg` (degrees); say the block.

| Key | Block | Unit | Default | Range | Why this default |
|---|---|---|---|---|---|
| `BedSightLiftM` | `C.AF.Fish` | m | 0.03 | 0.00-0.06 | the hook's radius; aims the sight rays at its top |

## Net and state impact
| Item | Change | Where |
|---|---|---|
| Player states | none / adds `<State>` / changes `<State> x <Action>` | `StateRules` matrix row |
| Cues | none / adds `<Cue>(args)` | `FishingNet` v2 codec, `FishingNetClient` |
| Guard rules | none / `<rule>` | `RequestGuard`, `LatencyBudget` |
| Wire size | +0 B / +<n> B per `<cue>` | `net_codec_test.luau` |

Write "none" when none. A note that touches none of these still has this table.

## Files touched
| File | Change | Owner | Reviewer |
|---|---|---|---|
| `Fishing/Shared/FishBrain.lua` | sight rays aim at the hook's top when it lies on the bed | Dev1 | Dev3 via the oracle |

## Offline tests
Each a `.luau` or `.py` in `tests/`; says what it proves and its negative control.

| Test | Proves | Negative control | Expected |
|---|---|---|---|
| `tests/wsa/<name>.luau` | <claim> | <the check that fails on the old code> | `PASS <n>` |

## Studio tests
Steps in a sandbox copy, never Place1. One row per thing to see.

| # | Do | See | Evidence |
|---|---|---|---|
| 1 | cast onto the bed at g = 0.045 | the trout hovers 5-45 s then bites or leaves | frames in `evidence/<WS>/` |

## Rulings needed
Numbered. Each has options A and B, one line each on cost and fidelity, and the author's recommendation. The Coordinator answers by number.

1. <question in one line>
   - A: <option>. Cost: <lines, hours, risk>. Fidelity: <matches / departs from the reference, how>.
   - B: <option>. Cost: <...>. Fidelity: <...>.
   - Recommendation: A, because <one line>.

## PARITY rows
Rows for `PARITY_CHECKLIST.md` (Dev3 merges them). One per mechanic this note covers.

| Mechanic | Reference | Ours | Status | Evidence |
|---|---|---|---|---|
| <mechanic> | <value or behaviour, ref> | <value or behaviour> | planned / staged / live / verified | <test or clip> |

## Open questions
Things this note does not settle and who is expected to settle them. Not rulings (those are above); unknowns.

- <question> (<who>, by <when>)
```

---

## Notes on using it
- A note with no rulings needed says "Rulings needed: none" and can be approved on reading.
- A rev changes the first line's `rev <n>` and adds a one-line changelog at the end: `rev 2 (<date>): <what changed and why>`.
- Reviews of the implementation go in `design/reviews/`, not in the note.
- Units in the fish and line simulation are metres; a value in studs is a bug.
