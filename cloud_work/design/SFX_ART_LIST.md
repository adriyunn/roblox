# SFX and art shopping list (original GameOne assets to generate)

Written by Cloud, 2026-10-06, without the project files. This is the list to APPROVE; nothing has
been generated. The cloud session has an ElevenLabs sound-effects and image pipeline; every
generation spends credits, so the Coordinator ticks what is wanted and Cloud generates only those
(2-3 variations per item is the pipeline's default and is useful, so count about 3 generations per
line below).

Config keys are proposed under `C.Sounds` in `Fishing/FishingConfig.lua`; the real file may already
use other names (StrainAudio owns the strain loop, reel and snap today), so a dev maps each key before
any patch. "Replaces" names what is in F1 today as far as the transcripts say; "placeholder" means the
F1 sound is a stand-in with no decided source.

Mix rules carried over from `StrainAudio`: owner-only sounds play on the owning client only; 3D sounds
are parented to a part in Workspace with a rolloff (snap is heard to 40 m); loops start at -40 dB and
fade in; nothing plays before the first user input on the client.

## Licensing

All generated assets are original to GameOne, made from text prompts with no reference audio or
images. Nothing is sampled, traced or extracted from About Fishing (no sounds, music, art, text or
UI), and the prompts never name it. Keep this file with the assets as the provenance note.

## Sounds

| name | config key | generation prompt | target length | loop | 3D / owner-only | replaces |
|---|---|---|---|---|---|---|
| Strain loop | `C.Sounds.StrainLoop` | A thin nylon fishing line under rising tension: a tight, steady creaking hum with a faint high whine, no music, clean and seamless so it can loop. | 4 s | yes | owner-only | the F1 strain loop in `StrainAudio` (one loop, pitch rides tension) |
| Reel click | `C.Sounds.ReelClick` | A single dry click of a small spinning-reel ratchet, close, no room reverb. Three slightly different takes. | 0.15 s | no | owner-only | the F1 reel tick |
| Line run-out | `C.Sounds.LineRunOut` | A fishing reel's drag screaming as line is pulled off fast by a running fish: a rapid ratchet buzz rising in pitch, seamless loop. | 3 s | yes | owner-only | new (fight: fish run) |
| Splash small | `C.Sounds.SplashSmall` | A small lure plopping into calm lake water, a light clean splash with a short drip tail, outdoor, no echo. | 0.8 s | no | 3D at the hook | the F1 landing splash (placeholder) |
| Splash large | `C.Sounds.SplashLarge` | A heavy splash of a large fish thrashing at the surface of a lake, water churning, half a second of spray and drips. | 1.5 s | no | 3D at the fish | the F1 haul-out splash (placeholder) |
| Jump splash | `C.Sounds.JumpSplash` | A fish leaping out of a lake and falling back: a quick wet breach, a short silence, then a slapping splash with drips. | 1.6 s | no | 3D at the fish | the Jump cue sound in `FishingWaterFX` (placeholder) |
| Hook set thunk | `C.Sounds.HookSet` | A short solid thunk of a fishing line snapping taut with a soft low thump, felt more than heard, no metallic ring. | 0.4 s | no | owner-only | the F1 hook-set hit (placeholder) |
| Line snap | `C.Sounds.LineSnap` | A fishing line breaking under load: a sharp high twang followed by a loose whip of slack line and a tiny splash. | 0.9 s | no | 3D at the rod tip, heard to 40 m | the F1 snap in `StrainAudio` |
| Bite nip tick | `C.Sounds.NipTick` | A tiny muffled tick, like a fingernail tapping a taut string once, very short, soft. Three takes. | 0.12 s | no | owner-only | the Nip cue sound (placeholder) |
| Water lapping ambience | `C.Sounds.WaterLap` | Gentle lake water lapping against a wooden dock post, calm, with occasional soft gurgles, distant birds absent, seamless loop. | 12 s | yes | 3D along the shore (several emitters) | the F1 shore ambience (placeholder) |
| Dock creak | `C.Sounds.DockCreak` | An old wooden dock plank creaking and settling under a footstep, dry wood, short, no squeak. Three takes. | 0.5 s | no | 3D at the dock | new |
| Rain loop | `C.Sounds.RainLoop` | Steady medium rain falling on a lake and on wooden planks, soft hiss with light patter, no thunder, no wind, seamless loop. | 15 s | yes | owner-only (2D, per-player weather) | new (P09) |
| Filleting cut 1-3 | `C.Sounds.FilletCut1..3` | A stylised knife cut on a cutting board for a cartoon cooking game: a clean swish and a soft tap on wood, no squelch, no gore. Three distinct cuts. | 0.3 s | no | owner-only | new (P12) |
| Coins / sell chime | `C.Sounds.SellChime` | A friendly short coin chime for a shop sale: two or three small coins dropping into a tin with a bright soft ding, cheerful, no music. | 0.8 s | no | owner-only | new (P03) |
| UI click | `C.Sounds.UIClick` | A soft rounded UI click, like a wooden bead tapping, very short, pleasant, no digital beep. | 0.08 s | no | owner-only | the Roblox default button sound |
| Aquarium bubbles | `C.Sounds.AquariumBubbles` | A home aquarium air stone: soft steady bubbling with a faint pump hum, calm, seamless loop. | 8 s | yes | 3D at the tank | new (P13) |
| Footsteps on dock 1-4 | `C.Sounds.StepDock1..4` | A single footstep of a soft boot on dry wooden dock boards, light, slight hollow resonance. Four distinct steps. | 0.3 s each | no | 3D at the character | the F1 footstep set (placeholder) |
| Footsteps on sand 1-4 | `C.Sounds.StepSand1..4` | A single footstep on damp lakeside sand, soft crunch with a light grit, no gravel. Four distinct steps. | 0.3 s each | no | 3D at the character | the F1 footstep set (placeholder) |

Counts: 18 lines, 29 files (the 1-3 and 1-4 sets), about 30-40 generations at the pipeline's default
variations. Loops are requested with the pipeline's loop option and checked for a clean seam before
import; everything is normalised to -3 dBFS peak and exported as OGG for Roblox.

## Images and UI mockups

These are references and mockups for Dev2 and WordAgent to design from, not shipping textures. The
style line for every prompt: "low-poly PSX-era fishing game, soft daylight, muted lakeside palette
(olive, slate blue, warm wood), hand-painted feel, no text, no logos". Resolution 1536x1024 unless
noted.

| name | purpose | prompt |
|---|---|---|
| Tackle box grid screen | layout reference for the P01 UI: a grid with fish footprints, a rotate hint, a "does not fit" state | A fishing game inventory screen: an open wooden tackle box seen from above holding a 8 by 6 grid of cells, three stylised fish laid across the cells at different angles taking up different numbers of squares, one fish ghosted in red where it does not fit, flat shading, no text. |
| Catch card | the card shown at the catch scene: species silhouette, length, a value, a stamp | A small card for a fishing game shown after a catch: a painted side view of a trout on parchment, a measuring tape along its length, a hand-stamped circle in the corner, warm paper texture, no text. |
| Trader counter | the sell screen's scene: a counter, scales, a money tin | A lakeside fish trader's wooden counter in a low-poly game: a brass weighing scale, a wooden crate of ice, a tin cash box, a hanging lantern, soft morning light, no characters, no text. |
| Gear shop | the shop screen: rods, reels, line spools on pegboard | A small tackle shop wall in a low-poly fishing game: a pegboard with three fishing rods, two reels, spools of line in three colours, a row of lures on hooks, price tags left blank, warm interior light, no text. |
| Evidence board | the P15 board: cork, pins, red string, paper notes | A cork evidence board in a cosy cabin, low-poly game style: pinned paper notes and small photos connected by red string, a lantern to the side, notes left blank, slightly tilted camera, no text. |
| Catch log page | the P08 log: a notebook spread with species entries | An open field notebook for a fishing game: a two-page spread with four painted fish silhouettes in a column, blank lines beside each, a pencil, a pressed leaf, soft daylight, no text. |
| Day/night sky references (4) | lighting targets for P07: dawn, noon, dusk, night over the same lake | A calm lake with a wooden dock and low hills, low-poly PSX style, the same scene at dawn / at noon / at dusk / at night with a full moon; four separate images, same camera, no text. |

Counts: 7 lines, 10 images (the sky set is four), about 20-30 generations with variations.

## Approval

Tick the lines wanted, say any key names that differ in the real `FishingConfig`, and Cloud generates
in one batch, writes the files to `cloud_work/assets/{sfx,img}/` with this list as the manifest, and
leaves import into Studio to the Dev who holds the lock.
