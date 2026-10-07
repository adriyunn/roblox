# Blender fish + prop generator v2 (About Fishing F2 species, realism pass)

Written by Cloud, 2026-10-07, WITHOUT the GameOne project files. v2 replaces the v1 placeholders
(`fish_generator.py`, kept untouched) after the verdict on them: "not even close to our realism
references". v2 fish have real anatomy, smooth shading, a baked painted texture per species, eyes
with pupil and iris, a gill-plate seam and a mouth line. Three props (rod and reel, dock, trader
stall) come from the same script. Nothing is copied from About Fishing: shapes come from numbers,
textures are procedural, colours are ours. A dev must still check two things against the real
project: the import scale (metres vs the game's stud ratio) and the facing axis `TroutView` expects.

Files (all under `cloud_work/blender/`):

| path | what |
|---|---|
| `fish_realistic.py` | the v2 script: parameter table at the top, presets, builders, bake, render, export |
| `exports_v2/fish_<name>.fbx` | one mesh per fish, ONE material, texture embedded (and next to it as PNG) |
| `exports_v2/fish_<name>_diffuse.png` | the baked 1024x1024 RGBA skin (alpha 0.85 on the fins, 1 on the body) |
| `exports_v2/fish_trout_rigged.fbx` | the trout with a 7-bone armature, auto weights |
| `exports_v2/rod_and_reel.fbx`, `dock.fbx`, `trader_stall.fbx` + `<name>_diffuse.png` | the props, one baked material each |
| `exports_v2/manifest.json` | per asset: triangles, dimensions, texture files, bones, origin, preview paths |
| `previews_v2/fish_<name>_34.png`, `_side.png` | 800x600 Cycles product shots (3/4 view and side view) |
| `previews_v2/<prop>_34.png`, `_side.png`, `rod_and_reel_reel.png` | prop previews (the reel one is a close-up) |
| `previews_v2/contact_sheet.png` | all five fish side-on at ONE scale, rendered from the re-imported FBX files |

## How to run

Needs Python with `bpy` as a module (the cloud session: Python 3.13 + bpy 5.2.2) and its bundled
numpy. No display: every scene starts from `read_factory_settings(use_empty=True)`, renders with
Cycles on the CPU (64 samples, 128 with `--final`, OpenImageDenoise on) and bakes with Cycles on the
CPU. Output paths are always absolute.

```
python3 fish_realistic.py --all                       # 5 fish + rigged trout + 3 props + contact sheet
python3 fish_realistic.py --all --final               # same at 128 samples (what is checked in)
python3 fish_realistic.py --preset trout --preset dock
python3 fish_realistic.py --preset pike --views 34,side,top,front
python3 fish_realistic.py --all --out /some/dir       # writes <dir>/exports_v2 and <dir>/previews_v2
python3 fish_realistic.py --all --no-fbx --no-render  # bake + manifest only
python3 fish_realistic.py --preset trout --sheet      # also rebuild the contact sheet from exports_v2
python3 fish_realistic.py --list
```

Timing on 4 CPU cores: a fish takes about 50 s (4 s build + bake, two 20 s renders, export); the
whole `--all --final` run about 12 minutes. The script exits 1 only if an asset passes Roblox's 10k
triangle limit.

## Parameters (fish presets)

Every length is a fraction of `length_m` unless the key ends in `_m`. `t` is the fraction of the
BODY length (0 = mouth tip, 1 = root of the tail fin); fin positions use the fraction of the TOTAL
length (0 = mouth tip, 1 = tail tips), the way the spec gives them. The full table with ranges is at
the top of the script.

| key | meaning |
|---|---|
| `length_m` | total length, mouth tip to tail tips (trout 0.40, perch 0.25, pike 0.70, carp 0.50, minnow 0.08) |
| `tail_len` | caudal fin length / total length |
| `top`, `bot`, `wid` | the three profile curves as `(t, value/L)` points: dorsal outline (z above the mouth axis), ventral outline (z below), half-width. Dorsal and ventral differ, so the back arches and the belly is rounder in front and flattens at the peduncle |
| `sec_exp`, `belly_taper` | cross-section shape: superellipse exponent (1 ellipse, 0.85 flatter flanks) and how much the lower half narrows (keeled belly) |
| `head_len` | snout to gill-plate edge / body length |
| `head_flat`, `head_wide` | flatten / widen the snout towards the nose (pike duck-bill) |
| `nose_t`, `mouth_t`, `mouth_notch`, `jaw_proj` | first ring (blunt snout), mouth-line notch ring and its radial indent, lower-jaw projection (trout, pike) |
| `gill_inset`, `gill_bulge` | the gill-plate seam: an inset edge loop (with a support loop before it so the crease survives the subdivision) that bows backwards at mid-height |
| `eye_t`, `eye_z`, `eye_r` | eye centre along the head, height in the section, radius (real sizes: trout 0.021 L = 8 mm) |
| `rings`, `sides`, `subdiv` | 26-30 rings, 16-18 sides, one Catmull-Clark level applied to the body when the total stays under 6,000 tris (always true for the five presets) |
| `fin_th`, `fins` | fin slab thickness and the fin list: `dorsal`, `dorsal2` (perch), `adipose` (trout), `caudal` (`span`, `fork`, `round`), `anal`, `pelvic`, `pectoral` (paddles with `dir`, `base`, `len`); each has an `outline` curve, `rays`, `rake` |
| `barbels` | carp: two small cones at the mouth corners |
| `pattern` | the texture: `back/side/belly` colours and ramp positions, lateral `band`, `cheek`, `spots` (Voronoi cell size, size, density, anisotropy, `spot_fins`), `bars` (perch), scale cell size and strength, fin colours per kind, fin tip / edge / ray darkening, `dorsal_spot`, `fin_blotch` (pike), `iris`/`pupil`, mouth and gill line |

How the mesh is built: a lofted body (rings along X whose elliptical section follows the two profile
curves; ring stations include the mouth notch and the gill seam loops; a nose pole at the origin, a
tail cap inside the caudal fin base), the lower half of the first rings pushed forward for the longer
lower jaw, fins as thin two-sided slabs built from a base curve on the body and an outline curve
(cols x rows grid, scalloped "rayed" edge, bases embedded 25-28 % of the local radius), eyes as
UV spheres (10x7) sunk into the head, everything joined into ONE mesh with smooth shading and sharp
edges only on the gill seam loop and the fin rims.

## Species looks

| preset | length | look (what the texture paints) |
|---|---|---|
| trout (rainbow) | 0.40 m | dark olive back to silver sides to white belly, pink-red lateral band from the gill plate to the tail, pink cheek, many small black spots on the back, head, dorsal, adipose and tail, pale-tipped lower fins, gold iris. Slightly forked tail, adipose fin at 78 % |
| perch | 0.25 m | deep humped body, greenish-gold with 6 dark wedge-shaped bars fading at the belly, two dorsals (spiny with a dark spot at its rear, then soft), orange-red caudal, anal and pelvic fins, pale pectorals, big gold eye, rounded tail |
| pike | 0.70 m | long shallow body, flat duck-bill snout with the eye high on the head, olive back to cream belly, rows of pale yellow bean-shaped spots (anisotropic Voronoi cells), dorsal and anal far back and rounded, dark blotches on the fins, forked tail |
| carp | 0.50 m | deep heavy body, bronze-gold with large cupped scales (big Voronoi cells, dark rims, lighter centres, per-scale brightness variation), long dorsal with a tall front, orange-tinted fins, down-turned mouth with two barbels |
| minnow | 0.08 m | slim, silver-olive, dark lateral stripe nose to tail, pale fins, relatively big eye |

## Textures: baking and how to attach them in Roblox

Each fish is UV-unwrapped with a seam along the back and one along the belly (nose to tail), so
`bpy.ops.uv.unwrap(ANGLE_BASED)` gives two clean side-view islands (left flank top, right flank
below); fins and eyes get their own rectangles in a strip at the bottom of the atlas (fins: u along
the base, v base to tip; eyes: a planar projection with the pupil in the middle). The material is a
Cycles node tree driven by per-vertex attributes written at build time (`ux` length fraction, `vz`
-1 belly..+1 back, `region` body/fin/eye, `fid` fin kind, `fr`/`fs` fin coordinates, `ray` ray phase,
`eyea` angle from the eye's outward pole) plus object-space Voronoi/noise for spots, bars and
scales. It is baked with `bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})` at 1024x1024
with an 8 px margin, then an `EMIT` bake of a fin mask is written into the alpha channel (0.85 on the
fins, 1 elsewhere), saved as `fish_<name>_diffuse.png`, and the material is swapped to a plain
Principled BSDF + Image Texture (roughness 0.35, a little coat) before export, so the FBX carries one
real texture (`path_mode='COPY'`, `embed_textures=True`). The previews render that same baked
material, not the procedural one, so they show what Roblox gets.

In Roblox Studio:

1. Avatar tab / 3D Importer, pick `exports_v2/fish_<name>.fbx`. The importer lists the embedded
   texture; keep "Import textures" (it uploads the PNG as an image asset, which goes through
   moderation) or untick it and upload `fish_<name>_diffuse.png` yourself through the Asset Manager.
2. One MeshPart per fish (one material in the file, so the importer does not split it). Either set
   `MeshPart.TextureID` to the uploaded image (`rbxassetid://<id>`), which honours the texture's
   alpha, or add a `SurfaceAppearance` under the MeshPart with `ColorMap` = the image and
   `AlphaMode` = `Transparency` so the fins read slightly translucent. SurfaceAppearance wins if both
   are set. `MeshPart.Color` should stay white (it tints the texture).
3. Units: 1 Blender unit = 1 m, written in centimetres in the FBX (Blender's default). Set the
   importer's unit so a 0.40 m trout has the `Size.X` the game's fish sim expects; the metre-to-stud
   ratio lives in the real `FishingConfig`, which this session cannot see.
4. `Anchored` on, `CanCollide` off (fish are visual; the sim is in `FishPool`). Keep `CastShadow`.
5. Roblox re-centres the part origin at the bounding box; the mouth is then at about
   `(+Size.X/2, 0, 0)` in part space (slightly below the vertical centre because the dorsal fin is
   taller than the anal fin). Add an Attachment there if `TroutView` needs the mouth.

## The rig (fish_trout_rigged.fbx)

Seven bones along the spine, root at the mouth, each the child of the previous (connected):
`head` (mouth to gill plate), `body1`..`body4` (gill plate to 78 % of the body in four equal parts),
`peduncle` (78 % to the tail-fin root), `tail` (through the caudal fin). Weights come from
`bpy.ops.object.parent_set(type='ARMATURE_AUTO')` (bone heat); vertices the solver left empty get
weights by distance along X (the log says how many; 0 in the last run). Exported with
`add_leaf_bones=False`, mesh + armature selected, same axes as the plain file. Re-importing the FBX
in Blender gives the mesh with an Armature modifier, the seven vertex groups and the root at (0,0,0).

Driving it from `TroutView.setBend(view, k)`: import with Rig Type "custom" so the MeshPart gets
`Bone` instances (`head` > `body1` > ... > `tail`). A bend of `k` radians is spread over the five
middle bones: each frame set `Bone.Transform = CFrame.Angles(0, k / 5, 0)` on `body1`, `body2`,
`body3`, `body4` and `peduncle` (rotation about the vertical axis, which is Y after the Y-up import),
leave `head` and `tail` at identity. The rotations compound down the chain, so the tail ends up
turned by `k` and the body follows a smooth arc; negative `k` bends the other way. If the team keeps
the vertex-bend path instead, the body still has 28-30 rings, which is plenty for a CFrame-driven
bend of the vertices.

## Triangle counts and dimensions (from exports_v2/manifest.json)

| asset | tris | dims x, y, z (m) | notes |
|---|---|---|---|
| fish_trout | 5,852 | 0.397 x 0.083 x 0.120 | body 1,152 tris before the subdivision (x4), fins + eyes 1,172 |
| fish_trout_rigged | 5,852 | same | + 7 bones |
| fish_perch | 5,620 | 0.248 x 0.056 x 0.113 | |
| fish_pike | 5,496 | 0.695 x 0.128 x 0.170 | |
| fish_carp | 5,392 | 0.498 x 0.131 x 0.215 | |
| fish_minnow | 4,880 | 0.080 x 0.016 x 0.023 | |
| rod_and_reel | 1,858 | 2.101 x 0.101 x 0.107 | origin at the butt, rod along +X, guides hang on -Z |
| dock | 1,108 | 6.000 x 2.082 x 2.550 | origin at the shore end on the centre line, water at z = 0, deck top z = 0.75 |
| trader_stall | 1,248 | 1.945 x 2.735 x 2.371 | origin on the floor under the middle of the counter's front edge, customer side +X |

All fish are inside the 2,500-6,000 budget and far under Roblox's 10k; the props are under their
2,500 / 3,000 / 3,500 budgets. Each fish's x extent is a few millimetres under its nominal length
because the longest tail ray is normalised to the total length and the lobes are rounded.

## Props

- `rod_and_reel.fbx`: a 2.1 m spinning rod lofted from a station list (butt cap, 24 cm cork rear
  grip, graphite reel seat with two metal rings, cork fore grip, blank tapering 1.6 cm to 0.3 cm),
  six line guides as thin tori hanging under the blank with a leg and a thread wrap each, a tip-top
  ring, and a spinning reel on the seat (foot, stem, gear body, rotor, spool with a line band, spool
  cap, half-torus bail arm with two pivots, handle shaft, crank and knob). One material: regions
  (cork, graphite, metal, dark, line) baked to `rod_and_reel_diffuse.png`.
- `dock.fbx`: 6 x 2 m, 37 planks 14 cm wide with REAL 2 cm gaps and flat-shaded sharp edges (the
  line-kink tests need edges to catch on), on two stringers and three cross bearers bolted to six
  pilings of 0.3 m diameter, 2.2 m tall, from z = -1.5 (1.5 m under the water, which is z = 0) to
  z = 0.70 under the planks; a mooring cleat near the far end on the +Y side; a ladder on the -Y side
  at x = 4 m from under the water to above the deck. Wood grain baked (smart UV projection, so the
  grain direction is per island), pilings weathered grey above the water line and dark green-brown
  below it.
- `trader_stall.fbx`: counter 2 x 0.9 x 1 m with an overhanging top and grooved front planks, four
  posts, a sloped striped canvas canopy with a scalloped valance, a hanging sign board without text
  on two ropes, a platform scale with a dial on the counter, two slatted fish crates (one on the
  counter, one on the floor).

## What changed vs v1 and why

v1 was a 500-tri flat-shaded lathe with five solid-colour materials: a blob with triangles for fins,
no texture, no eye detail, no gill, no mouth, so it could not read as a species at a glance. v2
fixes the four things realism needs at this polygon count. Anatomy: two separate profile curves and
a shaped cross-section give a real silhouette (arched back, round front belly, true caudal peduncle,
distinct snout, longer lower jaw on trout and pike, duck-bill on the pike, hump on the perch); the
fins are curved rayed slabs in the right places and sizes (adipose on the trout, two dorsals on the
perch, fins set back on the pike, long dorsal on the carp). Shading: smooth normals with one
subdivision level and sharp edges only on the gill crease and fin rims, so the body reads as a
rounded fish instead of a faceted tube. Texture: a baked painted skin per species (countershading,
band, spots, bars, scales, mouth and gill lines, fin rays) which is what a Dreamcast-era fishing game
relied on, and which Roblox can use directly. Head: a separate eye sphere with pupil and iris, a
gill-plate seam that catches the light, a mouth notch and painted mouth line.

## What still looks off (honest list)

- The fins are flat slabs with a painted ray pattern; they do not flex and have no membrane
  translucency beyond the 0.85 alpha. The pectorals and pelvics are simple paddles.
- The textures are procedural approximations, not hand-painted: the perch bars are more regular than
  on a real fish, the trout spots are uniform discs, the carp scales are a Voronoi lattice rather than
  overlapping scales, and there is no specular/normal map (diffuse only, which is what the bake does).
- The eye is a single sphere with no socket geometry; it reads well from the side and 3/4 but not
  from the front.
- The mouth is a notch ring plus a painted line, not an openable jaw.
- Nothing is animated; the rig is only on the trout.
- The props have a single baked material each; the dock planks are exact copies (no per-plank
  variation), the reel is a stylised block model.

## Checks a dev must do with the real files

- Facing axis (`+X` nose) against `TroutView` / `FishPoolView`; v1's `--face-negz` is not in v2, but
  rotating the MeshPart 90 degrees at import does the same.
- Import scale against the project's metre-to-stud ratio.
- That the importer keeps each fish one MeshPart (one material per file is what makes it do so).
- Whether the uploaded textures pass moderation (plain fish skins should).
