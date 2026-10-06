# About Fishing demo: recording list V42-V70

Written by Cloud, 2026-10-06, without the project files; modelled on the team's F1 `CLIP_LIST`
(V01-V41). Adrian captures these in the About Fishing demo (Steam). Each clip settles one or more
UNVERIFIED rows in `design/PARITY_rows_F2plus.md`; the row ids are in the "feeds" column.

## How to record

- Studio clips stay as they are (PrintWindow captures). For the Steam demo use Steam's Game Recording
  (Steam > Settings > Game Recording, record in the background, clip with the hotkey) or the Windows
  Game Bar (Win+Alt+R). 1080p60. Keep the raw files; trim later, never re-encode the originals.
- Name files `V42_tacklebox_grid.mp4`, `V43_...` continuing the F1 numbering V01-V41. One clip per
  number; if a clip needs a retake, keep the best one and add `b` (`V47b`).
- The demo does not draw the mouse, so for V44, V45, V59 and V60 run a free on-screen input overlay
  (any key/mouse display app) or say the inputs aloud with the mic on. Mic track = Adrian's notes only.
- At the start of every clip say the clip number, the in-game time and the place. Measurements are
  taken by frame-stepping at 60 fps, so keep the camera still where the list says "still".
- Put the files in the team's `evidence/` folder with a one-line log per clip (number, length, what
  happened, anything that surprised you).

## What NOT to copy

Record for mechanics only. Nothing in these clips goes into GameOne as an asset: no art, no models,
no UI layout copied pixel for pixel, no text, no names (people, places, fish nicknames, items), no
sounds, no music, no voice. We measure numbers, timings, rules and flows. The clips stay private in
`evidence/`; they are never published or shared outside the team.

## Run plan (two demo runs, 40-60 min each)

- Run 1 (fresh save): V42, V43, V44, V46, V47, V48, V49, V50, V53, V54, V57, V64, V66, V68, V70.
- Run 2 (continue the save, or a second fresh save that rushes money): V45, V51, V52, V55, V56,
  V58-V63, V65, V67, V69.
- Total footage about 66 min; the demo is 40-60 min, so two runs (80-120 min of play) leave slack for
  retakes and for clips that need waiting (V54, V64, V66).

## Clips

| # | clip | do on screen | must show | measurement we take | ~length | feeds |
|---|---|---|---|---|---|---|
| V42 | First 5 minutes uncut | Start a new game and play without pausing or skipping for 5:00. Natural pace. | Every screen, prompt and transition from the title to the first time you are free to walk. | Order of beats and the time stamp of each; where the first cast, first bite, first catch and first free-roam happen. | 5:00 | P18, P19 |
| V43 | Childhood tutorial | Play the whole father tutorial to its end (continue from V42 if it runs past 5:00). | Each prompt as it appears, every step the game forces, what you can skip, the handover to adult play. | The step list in order; how many casts/catches it demands; total tutorial length; whether the tutorial fish behaves differently (bites faster, never leaves). | 4:00 | P18, X60 |
| V44 | Rod control, flick to cast | From one marked spot (stand on a dock plank or a rock you can find again), cast 5 times: 2 slow drags, 3 flicks of rising speed. Input overlay or spoken inputs. Camera still. | The rod following the mouse, which movement starts a cast, where each cast lands. | Does a slow drag cast at all; distance per flick speed (frames from release to splash, splash position against a landmark); the max distance. | 1:30 | X62, X64 |
| V45 | Second catch step | Hook 3 fish. Fish 1 and 2: play it straight. Fish 3: do nothing or do the wrong thing until the line snaps. | What happens between the hook set and the haul-out: any bar, prompt, direction cue, timing cue; the snap. | Whether this is tension management (our fight) or a separate step; the prompt type; time from hook set to snap when you do nothing; what you lose on a snap (fish, lure, line). | 2:00 | X63 |
| V46 | Tackle box: open and grid | Open the box with 2-3 fish in it. Hover each fish. Camera still for 10 s on the grid. | The whole grid, each fish's footprint, any labels (size, value). | Grid columns x rows (count cells); cells per fish per species; whether footprints are rectangles or shapes. | 1:00 | P01 |
| V47 | Tackle box: rotate, fail, make room | With the box nearly full, catch a fish and try to place it: rotate it through every angle, try a spot where it does not fit, then make room (move another fish, discard, or whatever the game allows) and place it. | The rotation steps, the "does not fit" response, every way of making room the UI offers. | Rotation step (90 or finer); whether rotation changes the footprint; the actions available to make room; whether a fish can be dropped/discarded and what that costs. | 2:00 | P01, P02 |
| V48 | Tackle box: full box on a catch | Fill the box completely, then catch one more fish. | What the game does when there is no room at the moment of the catch. | Does the catch scene still play; is the fish lost, held, or auto-discarded; does the game open the box for you. | 1:30 | P02 |
| V49 | Selling: trader and money | Walk to the trader with 3+ fish. Show the money readout before. Sell the fish one at a time with a 2 s pause on each price. Show the readout after. | The trader screen, each fish's price as it is offered, the money total changing. | Money before and after; price per fish with its species and size; whether selling is per fish or whole box; whether fish leave the grid on sale. | 2:00 | P03, P04 |
| V50 | Selling: price by size | Sell two fish of the SAME species but different sizes (catch them first; sizes shown on the catch card or box). | Both prices with both sizes visible. | Price vs size relation (linear, stepped, flat); the species base price; check "four fish >= 30". | 1:30 | P03, X61 |
| V51 | Shop stock and prices | Open the gear shop. Scroll the whole stock slowly, 2 s per item, read any description. | Every item, its price, any lock/requirement text. | The list of upgrade types (line, rod, reel, lures, other) with prices and prerequisites. | 2:00 | P05, P06 |
| V52 | Line upgrade and cast distance | Stand on the V44 spot. Cast 3 max flicks (BEFORE). Buy the line upgrade. Return to the exact spot. Cast 3 max flicks (AFTER). Camera still, same angle. | The splash positions before and after against the same landmark; the purchase. | Cast distance before vs after (landmark or frames to splash) -> the distance ratio for `GameData.Gear.Line`; any other change (line thickness, colour, strength). | 2:30 | X64 |
| V53 | Lures: swap and response | Show the lure list. Cast 3 times with lure A in one spot and note which fish come to inspect. Swap to lure B (show the swap screen). Cast 3 times in the same spot. | The lure swap UI, which species approach or bite with each lure, whether some fish ignore a lure completely. | Lure -> species table; whether a wrong lure gives zero interest or just less; when you are allowed to swap (standing, mid-cast, mid-fight). | 3:00 | X65, P06 |
| V54 | Day/night: time passing | Find the time display (clock, sun, UI). Stand still at a spot with sky and water in view through a full dusk: record from late afternoon to full night without pausing. | The time display, the sky and lighting changing, any fish visibility change on the water. | Real seconds per in-game hour; the hours at which dusk starts and night is full; whether time stops in menus; whether you can sleep or skip time. | 3:00 | P07, X66 |
| V55 | Night fishing | At night, fish the V53 spot with the same lure for 3 casts. | Which fish show at night, how they behave at the lure, the visibility of fish under the water at night. | Species present at night vs day at the same spot; approach and nip timing at night vs day. | 2:00 | X66 |
| V56 | Weather | When it rains (or from the start if it always rains): 30 s still on the water, then fish 2 casts. If the rain stops at any point, record the change. | Rain on screen, the water surface, the visibility, any fish or bite difference, any weather change. | Does weather change at all; wave size (do fish stay visible); bite timing in rain vs clear if both exist. | 2:00 | P09 |
| V57 | A place unlocking | Record the moment a new place opens: the prompt, what you paid or did, the first walk in. | The gate (money, item, story step) and the unlock message. | The unlock condition for each place reached; whether it is per place or a chain. | 1:30 | P10 |
| V58 | Underwater cave | Enter a cave. Walk/swim around for 30 s, then cast or fish however the cave allows. | How you move there, how fishing works there (cast arc, drop, sink), what the camera does. | Movement mode; whether cast/retrieve rules differ; fish species in the cave. | 2:00 | P11 |
| V59 | Line anchor points | Find anchor points. Latch onto 3 of them in a row, pull around an obstacle, release. Input overlay or spoken inputs. | The anchor marker, the latch moment, the pull, the release. | How you latch (cast onto it, aim lock, proximity); pull speed (frames per metre against a landmark); how release works; whether a fish can be on the line at the same time. | 2:00 | X67 |
| V60 | Controlling a fish | Trigger fish control (whatever starts it). Steer the fish to a place you cannot reach on foot. Let it end. | The start trigger, the controls, the camera, the limits, how it ends. | What starts it (species, item, story); speed; leash or time limit; what you can reach; how it ends (key, timer, trigger). | 2:30 | X68 |
| V61 | Filleting: full minigame | Fillet one fish start to finish, playing it well. Input overlay on. | Every stage, the prompts, the score or result, what you get out. | The step list; the controls; the timing windows (frames) per cut; the result (fillet count, quality, money). | 2:00 | P12 |
| V62 | Filleting: fail | Fillet another fish and fail on purpose (cut wrong, miss the timing, stop early). | The fail response and what it costs. | What a fail costs (fewer fillets, nothing, the fish); can you retry. | 1:30 | P12 |
| V63 | Aquarium | Open the aquarium. Put a fish in it (from the box). Watch 20 s. Take it out if the game allows. | What the aquarium is for, the transfer UI, the fish inside. | Capacity; whether the fish leaves the box; any benefit (money over time, display, record); can it come back out. | 2:00 | P13 |
| V64 | A clue surfacing | Fish and cast into unusual spots (edges, under docks, far corners) until a clue surfaces. Keep recording until it happens, say what you were doing. | The clue moment and what preceded it (a cast, a catch, a spot). | The trigger (a cast landing somewhere, a catch, random); the clue type (item, note, dialogue); whether the same spot gives another. | 3:00 | P14 |
| V65 | Evidence board | Open the board with 2+ clues. Pin a clue, draw string between two clues, read a note. Try a wrong connection. | The board layout, how connections are made, what the game says for a right and a wrong connection. | The interaction model (drag string, select two); what completes a deduction; whether notes are automatic or player-written. | 2:00 | P15 |
| V66 | NPC routine | Pick one NPC at dawn and follow them for one in-game hour (per V54's rate). Say the in-game time every few minutes. | Where the NPC goes, what they do at each stop, when they move. | Waypoints with in-game times; what they do at each stop; whether they react to you. | 4:00 | P16 |
| V67 | Town day to day | Record 30 s of the same street from the same spot on day 1 and again on day 2 (same in-game hour). | What changed (props, stalls, who is around, open shops). | The list of differences; whether the change follows the day count or the story. | 1:30 | P17 |
| V68 | Species behaviour | For 4 different species: record from the fish noticing the lure to the take or the leave. Camera still on the lure. | The approach, the inspect, the nips, the take or the leave, per species. | Per species: notice-to-first-nip time, number of nips before the take, hover distance, how a wrong move spooks it. Compare the trout against F1's 4.083 s. | 3:00 | X60, X61 |
| V69 | Other gear upgrades | Buy or try any non-line upgrade (rod, reel, net). Use it once. | The purchase and the visible effect. | What each upgrade changes (reel speed, strain, cast accuracy) in numbers where possible. | 2:00 | P05 |
| V70 | HUD and menu tour | Open every menu and screen in the demo for 3 s each: HUD, box, shop, catch card, log or records, map, settings, board, aquarium. | Every UI surface once, still. | What screens exist (for the catch log row and the UI mockup brief in `design/SFX_ART_LIST.md`); never the layout itself. | 2:00 | P08 |

Total: about 66 minutes of clips across the two runs.
