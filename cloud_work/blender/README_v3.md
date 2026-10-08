# Blender fish + prop generator v3 (sprites, trout animation, normal/roughness maps, new props)

Written by Cloud, 2026-10-08, WITHOUT the GameOne project files. Dev2 checks the imports in Studio
(scale, facing axis, whether the importer keeps the three maps); Adrian checks the look. Round 3 sits
on top of round 2: `fish_realistic_v3.py` imports `fish_realistic.py` (v2) as a library and swaps
in only what changed. v1 (`fish_generator.py`, `exports/`, `previews/`) and v2 (`fish_realistic.py`,
`exports_v2/`, `previews_v2/`, `README_v2.md`) are untouched. Nothing is copied from About
Fishing: shapes come from numbers, textures are procedural, colours are ours.

Files (all under `cloud_work/blender/`):

| path | what |
|---|---|
| `fish_realistic_v3.py` | the v3 script: parameters at the top (`SCALES`, `RIDGE`, `ROUGH`, `SWIM`, `BEND`, `PROP3`), then fins, eye, material, hi-res scale source, bakes, sprites, animation, props, driver |
| `exports_v3/fish_<name>.fbx` | one mesh per species, ONE material, three textures embedded (and next to it as PNG) |
| `exports_v3/fish_<name>_diffuse.png` | 1024x1024 RGBA base colour (alpha 0.85 fins, 0.22 cornea, 1 elsewhere) |
| `exports_v3/fish_<name>_normal.png` | 1024x1024 tangent-space normal map (overlapping scales, gill seam, eye socket) |
| `exports_v3/fish_<name>_roughness.png` | 1024x1024 roughness (grey): wet back, matte belly and fins, glossy eye |
| `exports_v3/fish_trout_animated.fbx` | the trout + 7-bone rig + two actions `Swim` and `Bend` |
| `exports_v3/sprites/<name>_side.png`, `<name>_icon.png` | UI sprites: 512x192 side view facing right, 96x96 head icon, transparent |
| `exports_v3/sprites/sprites.json`, `sheet.png` | pixel bounds + scale per sprite, and a contact sheet of them |
| `exports_v3/rod_and_reel.fbx` | the v2 rod with a real spinning reel |
| `exports_v3/lure_spinner.fbx`, `lure_spoon.fbx`, `lure_fly.fbx` | three lures (6 cm, 7 cm, 2 cm) |
| `exports_v3/boat.fbx`, `tacklebox.fbx` | clinker rowing boat 3.5 m, the open tackle box 0.6 x 0.4 x 0.25 m |
| `exports_v3/<prop>_diffuse.png` | one baked colour map per prop |
| `exports_v3/manifest.json` | per asset: triangles, dimensions, textures, origin, previews, sprite data, animation check |
| `previews_v3/fish_<name>_34.png`, `_side.png` | 800x600 Cycles product shots (128 samples) |
| `previews_v3/contact_sheet.png` | all five fish side-on at ONE scale, rendered from the RE-IMPORTED FBX files |
| `previews_v3/materials_closeup.png` | the carp's flank at 2x with a raking light: the scale normal map catching it |
| `previews_v3/trout_swim_strip.png` | six frames of the Swim loop, top view and 3/4 view |
| `previews_v3/<prop>_34.png`, `rod_and_reel_reel.png` | prop previews |

## How to run

Same environment as v2 (Python 3.13 + bpy 5.2.2 as a module, its numpy, Pillow for the sheets; no
display, Cycles on the CPU, absolute paths). The script reads `fish_realistic.py` from its own folder.

```
python3 fish_realistic_v3.py --all --final        # everything at 128 samples (what is checked in, ~15 min on 4 cores)
python3 fish_realistic_v3.py --all                # same at 64 samples
python3 fish_realistic_v3.py --preset trout --quick          # one fish at 16 samples (about 1 min)
python3 fish_realistic_v3.py --preset carp --closeup         # plus the materials close-up
python3 fish_realistic_v3.py --preset boat --preset tacklebox
python3 fish_realistic_v3.py --sheet                         # rebuild the two sheets from exports_v3
python3 fish_realistic_v3.py --all --out /some/dir           # writes <dir>/exports_v3 and <dir>/previews_v3
python3 fish_realistic_v3.py --list
```

Flags: `--no-fbx`, `--no-render`, `--no-sprites`, `--no-anim`, `--views 34,side,top,front`. Exit code 1
if a fish passes 8,000 triangles or a prop 4,000 (Roblox's own limit is now 20,000).

## A. Species sprites (`exports_v3/sprites/`) for `TackleBoxUI.lua` and `CatchCard.lua`

For each species: `<name>_side.png`, 512x192 RGBA, orthographic side view, soft 3-point light, no
ground, transparent background, the fish FACING RIGHT (mouth tip = +X is on the right), filling
92 % of the width unless its height limits it (perch and carp are deep: they fill 92 % of the
height instead, and `bounds_px` says what they actually cover). `<name>_icon.png` is a 96x96
orthographic crop of the head and front body (a square window of `max(1.12 x fish height,
0.52 x length)`, the nose 6 % in from the right edge). `sheet.png` shows all ten on a dark
green ground with the bounds boxes drawn.

Note for Dev2: `design/mockups/tacklebox_mockup.png` draws the heads on the LEFT. The brief for
this round asked for heads on the right, so that is what is here; an `ImageLabel` with a negative
`Size.X.Scale` or `ImageRectSize.X < 0` mirrors a sprite, or set `SPRITE_FACE_RIGHT` in the UI to
flip the rect, or ask Cloud for a `--face-left` build (it is a one-line camera change).

`sprites.json` (v3):

```
{
  "version": 3, "facing": "right", "side_size": [512, 192], "icon_size": [96, 96],
  "species": {
    "trout": {
      "length_m": 0.40, "facing": "right",
      "side": {
        "file": "trout_side.png", "w": 512, "h": 192,
        "bounds_px": {"x0": 20, "y0": 24, "x1": 492, "y1": 167},   -- opaque box (alpha > 8), x1/y1 exclusive
        "px_per_m": 1181.17,                                        -- sprite pixels per metre of fish
        "nose_px": [492.9, 116.8],                                  -- where the mouth tip lands in the sprite
        "length_px": 472.5,                                         -- length_m * px_per_m
        "fish_bbox_m": [0.3988, 0.1201]                             -- mesh extent along x and z
      },
      "icon": {"file": "trout_icon.png", "w": 96, "h": 96, "px_per_m": 461.54, "window_m": 0.208,
               "bounds_px": {"x0": 0, "y0": 20, "x1": 90, "y1": 76}}
    }, ...
  }
}
```

How the UI scales by cells (`TackleBoxUI.itemRect` gives the item's pixel rectangle; a fish item's
shape comes from `SpeciesTable.sizeClass`, e.g. `line2` = 2 cells wide): with `wpx` = the rect's
width in pixels, `scale = wpx / (bounds_px.x1 - bounds_px.x0)`, draw the sprite in an `ImageLabel`
of size `(512 * scale, 192 * scale)` offset by `(-bounds_px.x0 * scale, -bounds_px.y0 * scale)` inside
the rect, or crop with `ImageRectOffset = (x0, y0)` and `ImageRectSize = (x1 - x0, y1 - y0)` and let
`ScaleType = Fit` do it. Because every sprite has the same 512-px width but a different `px_per_m`,
sizes across species are NOT comparable pixel for pixel: a 0.70 m pike at 675 px/m and a 0.08 m
minnow at 5911 px/m both fill the sprite. The catch card can show the real proportion with
`length_px / px_per_m` if it wants (it does not have to; the mockup paints the fish to fill the card).
Icons are for the trader list, the catch log grid and the "Selected" panel.

## B. Trout animation (`exports_v3/fish_trout_animated.fbx`)

The rig is v2's: seven bones along the spine, root at the mouth, `head` > `body1` > `body2` >
`body3` > `body4` > `peduncle` > `tail`, +X forward in Blender (Roblox: after the Y-up conversion the
fish still points along the part's +X and the vertical axis is Y). v3 weights every vertex with a
smooth hat along x per bone (normalised) instead of bone heat, which failed on the thin fin ridges
and the eye shells; a spine rig wants exactly that 1-D weighting anyway.

Two actions, keyed on every bone's `rotation_euler.z` (yaw about the bone's local Z, which is the
world vertical for bones that run along -X), at 30 fps:

| action | frames | what |
|---|---|---|
| `Swim` | 1-30, loops (frame 31 = frame 1) | a travelling sine wave: bone i has amplitude `[0, 2, 3.6, 6.2, 10.4, 16, 25]` degrees (head .. tail) and phase `2 pi (f-1)/30 - 0.6 rad * (i-1)` (0.6 rad lag per bone from `body1`), so the wave runs head to tail |
| `Bend` | 1 / 15 / 30 | three poses: k = -1 / 0 / +1; `body1`, `body2`, `body3`, `body4`, `peduncle` each rotate `k x 6 deg` about the vertical; `head` and `tail` stay. Linear in between, so frame 1->30 sweeps k from -1 to +1 |

`Bend` is the `TroutView.setBend(view, k)` mapping from README_v2 written as poses: the five middle
bones share the bend, the rotations compound down the chain so the tail ends up turned by `5 x 6 deg
x k` = 30 deg at k = 1 (README_v2 wrote it as `k / 5` radians per bone for a radian k; here k is
-1..1 and the per-bone step is 6 deg; scale it if `setBend` passes radians).

Export settings (as asked): `bake_anim=True, bake_anim_use_all_actions=True,
bake_anim_use_nla_strips=False, bake_anim_use_all_bones=True, bake_anim_force_startend_keying=True,
bake_anim_step=1, bake_anim_simplify_factor=0, add_leaf_bones=False`, axes `-Z forward, Y up`, mesh
and armature selected, textures embedded. Blender names each FBX animation stack `<armature>|<action>`,
so the stacks are `fish_trout_rig|Swim` and `fish_trout_rig|Bend`.

Verified by the script itself (fresh scene, `import_scene.fbx`, `manifest.json` > `trout.animation`):
both actions are present with frame range (1, 30); setting each action and evaluating the mesh at
frame 1 and frame 15 moves the tail-tip vertex by about 177 mm (`Swim`) and 118 mm (`Bend`), i.e. the
mesh deforms, it is not only the bones that move. `previews_v3/trout_swim_strip.png` shows frames
1/6/11/16/21/26 of `Swim` from the top (the wave) and from 3/4.

Roblox import (Studio steps; "confirm" = not run here, no Studio in the cloud):

1. 3D Importer (Avatar tab or File > Import 3D), pick `fish_trout_animated.fbx`. In "Rig General"
   set Rig Type to `Custom` (R15 would try to map the bone names) and keep "Import textures". The
   result is a `Model` with one `MeshPart` carrying `Bone` instances `head` .. `tail` under it and an
   `AnimationController` is NOT added automatically: add one (`AnimationController` + `Animator`)
   under the model, or a `Humanoid` if the team prefers the humanoid path. [confirm the importer's
   current panel names]
2. Animation: open the Animation Editor with the imported rig selected, "..." menu > `Import` >
   `From FBX Animation` (this is the Animation Importer: it reads the animation stacks of an FBX
   against the selected rig, matching bones by name). Pick the same FBX; it lists both stacks; import
   `Swim` and `Bend` as two keyframe sequences, then `Publish to Roblox` each to get an animation
   asset id. [confirm: some Studio versions import all stacks at once, some ask you to pick one]
3. Play: `Animator:LoadAnimation(swimAnim)`, `Looped = true` for `Swim`; for `Bend` either play it
   with `TimePosition` = `(k + 1) / 2 * length` and `Speed = 0` (the sweep from frame 1 to 30 IS the
   k = -1..+1 range), or keep driving `Bone.Transform` from `setBend` as README_v2 describes and use
   only `Swim`. Both actions key the same bones, so do not play them together at full weight.
4. Units: the FBX is in centimetres with 1 Blender unit = 1 m; set the importer's scale so the
   0.40 m trout has the `Size.X` the sim expects (the stud ratio is in the real `FishingConfig`).

## C. Fish v3 against the round-2 "still off" list

| round-2 item | v3 |
|---|---|
| carp scales a Voronoi lattice, no overlap; diffuse only, no normal/specular | a NORMAL map baked from a hi-res source with real overlapping scales, a ROUGHNESS map, and the same scale lattice painted into the diffuse; v2's painted Voronoi lattice is off |
| fins flat slabs with painted rays | thin ridges along every ray (the slab's thickness follows the rays), a scalloped trailing edge |
| the eye one sphere | eyeball + a flattened dark pupil disc + a translucent cornea cap, glossy in the roughness map |
| the reel a block model | spool with visible line wrap, bail wire, crank with knob, foot in the seat |

How the scales are made (`hires_scaled_body`): a dense loft of v2's analytic body (0.3-1.0 mm vertex
spacing, 25k-170k faces) is displaced along its normal by a height field in surface coordinates
`(U, V)`: V = angle around the body in units of `circumference / cell` rows (18-56 rows per species),
U = distance along the body divided by a pitch that shrinks with the local radius (so scales get
smaller towards the tail, as on a real fish). Scales sit on a staggered (brick) lattice as discs of
radius 0.8 pitch; where discs overlap the most ANTERIOR one wins, which leaves each scale its
posterior crescent; the height rises across the exposed part to the free edge (sawtooth) with a
transverse dome, then drops onto the next scale. No scales on the head (fade in 0.5 to 6 % behind the
gill plate), fade out at the tail root, a faint lateral-line groove. Per species (`SCALES`): carp
20 mm cells / 3.0 mm step, pike 8.5 / 1.3, perch 6.5 / 1.0, trout 4.0 / 0.65, minnow 1.5 / 0.22.
The step is about 12-15 % of the cell: exaggerated on purpose, a normal map needs slope to read.

Bakes, in order, all Cycles CPU on the ONE low-res fish with its v2 UV layout (two side islands,
fins and eyes in the bottom strip): `DIFFUSE` colour + `EMIT` alpha (v2, unchanged), `EMIT` base
roughness (back 0.22 .. belly 0.42 by the `vz` attribute, fins 0.65, iris 0.30, pupil 0.12, cornea
0.05), `EMIT` body mask, then with the hi-res body selected and the fish active
`bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT', use_selected_to_active=True,
cage_extrusion=0.012 L, max_ray_distance=0.035 L)` and an `EMIT` selected-to-active bake of the hi-res
height attribute. Post in numpy: fin/eye texels set to the flat normal (their relief IS geometry), the
normal's tangent X/Y gain 2.0 then renormalised (otherwise the free edges are one texel wide and
read faint; the renders are honest about the result), roughness = base + 0.28 x |grad height| (matte
scale rims, glossy scale centres), diffuse x (1 - 0.22 x |grad height|) x (0.95 + 0.10 x height).
The hi-res source is deleted; the FBX carries the low-res mesh and three images.

Roblox: in Studio add a `SurfaceAppearance` under the MeshPart and set `ColorMap` =
`fish_<name>_diffuse.png`, `NormalMap` = `fish_<name>_normal.png`, `RoughnessMap` =
`fish_<name>_roughness.png` (no `MetalnessMap`: fish are dielectric; leave it empty = 0),
`AlphaMode = Transparency` so the fins read 0.85 and the cornea 0.22 (the diffuse alpha). Upload the
three PNGs through the Asset Manager (the 3D Importer may also pick them up from the FBX: it reads
the material's colour map for sure, the normal/roughness ones go in as `ShininessExponent` /
`NormalMap` FBX properties which Studio's PBR import should map [confirm; if not, set them by hand]).
The normal map is Blender's default convention, +Y up (OpenGL); that is the convention Roblox's
SurfaceAppearance docs describe [confirm]: if the scales look inset instead of raised in Studio, invert
the green channel. `MeshPart.Color` stays white, `TextureID` empty when a SurfaceAppearance is used.
`previews_v3/contact_sheet.png` is rendered from the re-imported FBX files in Blender: the three
maps come back wired (Base Color sRGB, Normal Map node tangent space, roughness Non-Color), so what
is in the file is what the previews show.

The eye: `add_eye3` keeps v2's eyeball (iris and a painted pupil on `eyea`), adds a 12-segment
pupil disc at the outward pole (radius 0.42 r, rim sunk 0.1 r into the ball, region 4, black, roughness
0.12) and a cornea cap (a 1.07 r sphere cut at 64 deg from the outward axis, 3 rings x 12, region 3,
colour (0.55, 0.66, 0.78) at alpha 0.22, roughness 0.05 so the highlight sits on it).

Fins: `fin_grid3` replaces v2's slab builder while v2's dorsal/caudal/paddle builders run: the grid
has `2 x rays + 1` columns so every ray and every trough is a column; the half-thickness is
`0.5 th (0.5 + 0.5 ridge) + 0.28 th ridge (1 - 0.45 r)` with `ridge = 0.5 + 0.5 cos(2 pi s rays)`;
the painted ray lines are moved onto the ridges (`ray` attribute + 0.5); the scalloped trailing edge
(0.045 of the height, in v2's `outline_h`) is now sampled on-grid so it shows.

## D. Props

| asset | what, origin, how it is textured |
|---|---|
| `rod_and_reel.fbx` | v2's 2.1 m rod (butt at the origin, +X to the tip, guides on -Z) with a new spinning reel under the seat at x = 0.38: a 118 mm foot plate whose ends sit under the two hood rings, a curved stem, a rounded gear housing with a rear cap and a side plate, a rotor with two arms to the bail pivots, a spool (core, back flange, front lip, drag knob) with the LINE WRAP as 10 tori of 1.6 mm, a bail wire bent over the front of the spool from the line roller (+Y) to the bail lever (-Y), a 48 mm crank arm at 35 deg with a rubber knob on a stub, an anti-reverse switch. Regions baked to one colour map |
| `lure_spinner.fbx` | 6 cm: line eye at the origin, hangs along -Z. Split ring, 0.5 mm wire shaft, clevis, a dished willow blade (26 x 9 mm, brass, 28 deg off the shaft), three beads (red middle), a grooved lead body, split ring, treble hook (3 bends at 120 deg, tapering points) |
| `lure_spoon.fbx` | 7 cm: line eye at the origin, hangs along -Z. Curved oval blade 52 x 24 mm (dished across and bowed along), the painted face (red/white diagonal stripes) on -Y, nickel on +Y, eyelets, split rings, treble hook |
| `lure_fly.fbx` | 2 cm: hook eye at the origin, shank along -X, bend and point down. Ribbed olive thread body, dark thorax, 20 hackle fibres as thin two-sided strips swept 25 deg back, four tail fibres, two grey wing slips |
| `boat.fbx` | 3.5 m clinker hull: 6 strakes per side on 22 stations, each lower edge 14 mm proud of the strake below (the lands are real faces), inner skin, transom, keel, stem, gunwales, 6 ribs, floorboards, three thwarts (x = -0.9, 0, 0.9, seat height 0.30), oarlocks at x = 0.25, two 2.4 m oars resting across the thwarts, blades aft. Origin at the centre of the bottom of the keel, bow +X, up +Z. Outside: pale blue-grey paint with a dark boot-top below z = 0.22; inside: varnished wood; thwarts/oars pale wood |
| `tacklebox.fbx` | 0.6 x 0.4 x 0.25 m closed size (base 0.20 + lid 0.05), 12 mm walls, origin at the centre of the base. Lower tier: dark green felt floor and an 8 x 6 divider grid (7 + 5 dividers, 4 mm, 85 mm tall) matching `TackleBoxUI`'s cols x rows. Upper tier: a 0.57 x 0.17 x 0.06 three-compartment tray swung FORWARD over the front edge on two steel arms (cantilever box), so the grid stays visible. Lid hinged on the back (+Y) edge, open at 100 deg (10 deg past vertical), felt inside, two hinges, a bail handle on its outer face, two latches (catch plates on the front wall, hasps on the lid), brass corner caps. This is the 3D version of the inventory screen's frame; the mockup's box IS this layout seen from the front |

Prop previews: `<name>_34.png` (+ `rod_and_reel_reel.png`, a close-up of the reel). Lure previews
are padded so the whole lure is in frame.

## Triangle counts and dimensions (from exports_v3/manifest.json)

| asset | tris | dims x, y, z (m) | notes |
|---|---|---|---|
| fish_trout | 7,012 | 0.399 x 0.084 x 0.120 | body 1,152 x4 subdiv, fins + eyes 2,332 (v2: 5,852) |
| fish_trout_animated | 7,012 | same | + 7 bones, actions Swim (1-30) and Bend (1-30) |
| fish_perch | 7,004 | 0.249 x 0.056 x 0.114 | (v2: 5,620) |
| fish_pike | 6,684 | 0.698 x 0.128 x 0.173 | (v2: 5,496) |
| fish_carp | 6,804 | 0.498 x 0.134 x 0.215 | (v2: 5,392) |
| fish_minnow | 5,772 | 0.080 x 0.016 x 0.023 | (v2: 4,880) |
| rod_and_reel | 3,524 | 2.101 x 0.098 x 0.124 | v2: 1,858; the reel is 1,900 of it (the line-wrap tori are 1,120) |
| lure_spinner | 1,298 | 0.018 x 0.012 x 0.061 | |
| lure_spoon | 1,098 | 0.021 x 0.015 x 0.071 | |
| lure_fly | 366 | 0.018 x 0.011 x 0.011 | |
| boat | 3,010 | 3.522 x 1.526 x 0.864 | |
| tacklebox | 952 | 0.608 x 0.676 x 0.605 | open: the lid stands 0.60 high, the tray overhangs the front by 0.17 |

Every fish is under the 8,000 budget (the extra 1,000-1,500 over v2 is the fin columns and the eye
parts), every prop under 4,000; all far under Roblox's 20,000.

## What still looks off (honest list)

- The scales are a regular staggered lattice: real scales vary in size and the rows follow the
  lateral line and bend around the fin bases; here the rows are straight rings. The crescents are a
  little hexagonal because the discs tile a square lattice. The tangent X/Y gain of 2.0 means the map
  is stronger than the geometry it was baked from.
- The scale rims painted into the diffuse are hard dark lines; at Roblox's low quality levels (no
  normal maps) the fish will show those lines without the relief.
- The fin rays are a triangle-wave corrugation (two columns per ray); the spiny perch dorsal reads
  as a saw, the soft fins as corrugated card from close up. Still no fin flex and no membrane
  translucency beyond the alpha.
- The cornea is a half-sphere of alpha 0.22 over the eyeball; in Roblox the sort order of
  overlapping transparent faces in one MeshPart is up to the engine. The pupil is a flat disc; it
  reads from the side and 3/4, not from the front.
- `Swim` is a planar sine; a real fish's wave grows faster at the peduncle and the tail fin lags by
  flexing, which a slab cannot do. The weights are a 1-D hat along x, so the pectoral and pelvic fins
  move with the body segment they sit on, rigidly.
- The reel's gear housing is a cylinder with caps, the bail arm has no spring cover, the line wrap
  is ten identical tori. The lures have no split-ring gaps, the fly's hackle is 20 flat strips. The
  boat's strakes are not twisted into the stem (the lands fade to zero width there), the oars are
  straight cylinders with a box blade. The tackle box's lid and tray have no real hinge pins; the
  latches are blocks.
- Props are still one baked colour map each, no normal/roughness maps (lures would gain most from
  a metallic map, which Roblox's SurfaceAppearance supports as `MetalnessMap`).
- Sprites are rendered with Cycles under the studio rig: the fish's own shadowing and the fin alpha
  give soft edges, but the look is a 3D render, not the painted style of the mockups.

## Checks a dev must do with the real files

- Facing axis (`+X` nose) against `TroutView` / `FishPoolView`, and the sprite facing against the UI
  (see the note in A).
- Import scale against the project's metre-to-stud ratio (read `MeshPart.Size.X` after import).
- That the importer keeps each fish one MeshPart, and whether it picks the normal/roughness maps up
  from the FBX or they have to go on a `SurfaceAppearance` by hand; and the normal map's green
  channel convention.
- That the Animation Importer lists both stacks and that `Bend` at `TimePosition` 0 / mid / end
  matches `setBend(-1 / 0 / +1)` in direction (if the fish bends the other way, the sign of the
  per-bone angle in `BEND` is the one line to flip).
- Whether the uploaded textures pass moderation (plain fish skins, a normal map and grey maps should).
