# Blender fish generator (About Fishing F2 species placeholders)

Written by Cloud, 2026-10-06, WITHOUT the GameOne project files. These fish are placeholders for the
F2 species pass; F1 keeps the trout rig the team already has. A dev must check two things against the
real project before using them: the import scale (metres vs the game's stud ratio, see "Scale") and the
facing axis `TroutView` expects (see "Facing"). Nothing here is copied from About Fishing: the shapes
are generic fish built from numbers, the colours are ours.

Files:

| path | what |
|---|---|
| `fish_generator.py` | the script: parameters table at the top, no dependency beyond `bpy` |
| `exports/fish_<name>.fbx` | one mesh per preset, triangles only, 5 or 6 flat-colour materials |
| `exports/fish_manifest.json` | length, triangle count, dimensions, axis, paths per preset |
| `previews/fish_<name>.png` | 480x360 Cycles 3/4-view preview of what was exported |

## How to run

Needs Python with `bpy` installed as a module (the cloud session has Python 3.13 + bpy 5.2.2). No
display is needed: each preset starts from `read_factory_settings(use_empty=True)` and renders with
Cycles on the CPU (24 samples, 480x360, about 3 s per view). `scene.render.filepath` is always absolute.

```
python3 fish_generator.py --all                       # all 5 presets -> exports/ and previews/ next to the script
python3 fish_generator.py --preset trout --out <dir>  # one preset -> <dir>/exports and <dir>/previews
python3 fish_generator.py --preset pike --preset carp --views 34,side,top   # extra debug views
python3 fish_generator.py --all --no-render           # FBX only
python3 fish_generator.py --all --face-negz           # nose on Roblox LookVector (-Z) instead of +X
python3 fish_generator.py --list
```

Extra views are written as `fish_<name>_side.png` / `_top.png` / `_front.png`; the plain
`fish_<name>.png` is always the 3/4 view. The script exits 1 if any preset is over 1,500 triangles.

## Presets and triangle counts

| preset | length | tris | dims x,y,z (m) | notes |
|---|---|---|---|---|
| trout | 0.40 m | 652 | 0.400, 0.123, 0.139 | olive back, pink lateral band (1 face row), dark spots, moderate fork |
| perch | 0.25 m | 532 | 0.250, 0.082, 0.141 | deep humped body, tall dorsal, dark vertical bars, orange fins |
| pike | 0.70 m | 628 | 0.700, 0.152, 0.165 | long and shallow, flattened wide head, dorsal far back, light spots |
| carp | 0.50 m | 652 | 0.500, 0.181, 0.229 | deep heavy body, long dorsal base, golden brown |
| minnow | 0.08 m | 428 | 0.080, 0.022, 0.023 | slim silver body, dark lateral stripe |

All far under the 1,500-tri budget (Roblox's import limit is 10k; low-poly fits the PSX look the
reference has). Faces are flat-shaded on purpose.

## Parameters

Every size except `length_m` is a ratio of `length_m`, so a preset keeps its shape when scaled. The
full table with ranges is at the top of the script; the ones that matter most:

| key | meaning |
|---|---|
| `length_m` | total length, mouth tip to tail tips, metres (scale factor 1.0: a 0.40 m trout is 0.40 units) |
| `body_depth_ratio`, `body_width_ratio` | max height / width of the body as a fraction of length |
| `head_ratio` | head length as a fraction of the body (body = length minus the tail fin) |
| `head_flat`, `head_width_boost` | flatten / widen the head towards the nose (pike's duck-bill) |
| `back_arch` | back hump taller than the belly (perch, carp) |
| `tail_fork_depth` | 0 = rounded tail, 0.6 = deep fork; `tail_len_ratio`, `tail_span_ratio` size the fin |
| `dorsal_fin_height`, `dorsal_pos`, `dorsal_len` | dorsal fin size and where it sits along the back |
| `anal_fin_height`, `pectoral_fin_length` | the other fins (0 = none) |
| `segments`, `sides` | rings along the body and vertices per ring (14-20 and 10-14 in the presets) |
| `base_colour`, `band_colour`, `belly_colour`, `fin_colour`, `spot_colour` | linear RGB 0..1 |
| `band_width`, `bar_every`, `spot_density`, `spot_light` | lateral band, perch bars, spots (seeded, deterministic) |
| `eyes`, `eye_size_ratio` | two low-poly eyes (36 tris each); `eyes=False` keeps the 3+2 body materials only |

How the mesh is built: a lathe-like body (rings of vertices along X with an elliptical cross-section
whose half-depth and half-width follow two profile curves, a nose pole at the origin, a small cap at the
tail root), a forked caudal fin as a thin extruded polygon, dorsal / anal / pectoral fins as thin
extruded triangles or trapezoids whose bases sit slightly inside the body so there is no gap, then
`recalc_face_normals` and triangulation. Materials by region: `FishBack`, `FishBelly`, `FishFins`
(the three the spec asks for) plus `FishBand`, `FishSpot` and `FishEye` for the band, spots and eyes.
Each is a flat Principled colour; the FBX carries the colour per material.

## Axes, origin, scale

- Built with the mouth tip at the origin, +X forward (nose), +Z up, +Y the fish's left side.
- Exported with `axis_forward='-Z', axis_up='Y'` and `bake_space_transform=True`, which is what Roblox
  expects (Y-up file, mesh data converted, no leftover rotation on the node). Verified by re-importing
  the FBX raw: nose at the origin, body along -X, dorsal tip at +Y.
- Default facing in Roblox: the nose points along the MeshPart's +X (`RightVector`), the back along +Y.
  With `--face-negz` the mesh is rotated so the nose points along the FBX -Z, which is the MeshPart's
  `LookVector`. Pick whichever matches how `TroutView` orients the F1 trout rig (unknown here).
- Units: 1 Blender unit = 1 metre. Blender writes the FBX in centimetres (its default unit scale), so
  the trout is 40 cm long in the file. Roblox's 3D Importer reads that unit; see import step 3.
- Roblox re-centres a MeshPart's origin at the bounding-box centre, so the mouth-at-origin is lost on
  import. In part-local space the mouth is then at about `(+Size.X/2, 0, 0)` (the vertical centre sits a
  little above the body axis because the dorsal fin is taller than the anal fin). If `TroutView` needs
  the mouth, add an Attachment there after import.

## Import into Roblox Studio

1. Avatar / 3D Importer (Home tab, Import 3D), pick `exports/fish_<name>.fbx`.
2. In the importer: untick "Add Model to Inventory" unless you want it in the toolbox; keep "Merge
   Meshes" off; "Rig Type" none (no armature in the file); keep per-material import so the colour
   regions survive (if the importer collapses the materials into one Color, re-import with the split
   option, or accept one colour for a placeholder).
3. Scale Unit: the file is in centimetres. Set the importer's unit so a 0.40 m trout comes out at the
   length the game's fish sim expects: the sim is in metres (`C.AF.Fish`, `LureSim RadiusM`), but the
   metre-to-stud ratio the project uses is in the real `FishingConfig`, which the cloud session cannot
   see. After import read the MeshPart `Size.X` and compare with the species length; fix the importer's
   scale (or `MeshPart.Size`) until they match.
4. Insert into Workspace, set `Anchored`, `CanCollide` off (fish are visual, the sim is in `FishPool`).
5. The imported MeshPart has a single `Color`/material per region; no texture is needed. Keep
   `CastShadow` on; the flat-shaded look is intended.

## What TroutView expects (from the team's notes, not from the code)

`TroutView.setBend(view, k)` bends the fish when it turns, so a species mesh needs enough segments
along the length for a future bone or vertex bend: all presets have 14-20 rings (10+ as asked), spaced
slightly denser at the head. F1 uses the trout rig the team already has, so nothing in F1 should switch
to these meshes; they are for the F2 species rows (X60/X61 in `design/PARITY_rows_F2plus.md`). When a
bend is needed, the cheapest route is a 3-bone chain (head / mid / tail) skinned in Blender with
automatic weights, exported with `add_leaf_bones=False`; the script does not do this yet.

## Checks a dev must do with the real files

- The facing axis (`+X` vs `--face-negz`) against `TroutView` / `FishPoolView`.
- The import scale against the project's metre-to-stud ratio.
- Whether Studio imports the six materials as one MeshPart with colour regions or as several parts;
  the fish must stay one part for `setBend`.
