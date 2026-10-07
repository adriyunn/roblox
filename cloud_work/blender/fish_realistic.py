#!/usr/bin/env python3
# fish_realistic.py (About Fishing F2 species, realism pass v2; Cloud, 2026-10-07; blender/README_v2.md)
# Lofted fish bodies with real proportions (two profile curves, elliptical sections, snout, mouth notch,
# gill-plate seam, eye spheres with pupil and iris), thin curved fins, a baked 1024x1024 painted texture
# per species (countershading, lateral band, spots/bars/scales, mouth and gill lines, fin rays) and a
# boned trout. Also builds three props (rod and reel, dock, trader stall). Exports FBX for Roblox and
# renders Cycles product-shot previews. The v1 script fish_generator.py is untouched.
#
# Written in the cloud session WITHOUT the GameOne project files. A dev must check the import scale
# (metres vs the game's stud ratio) and the facing axis TroutView expects (README_v2.md).
#
# Needs only `bpy` (Blender 5.2 as a Python module), numpy (bundled), bmesh, mathutils. No display:
# every scene starts from read_factory_settings(use_empty=True), renders with CYCLES on the CPU and
# bakes textures with Cycles on the CPU.
#
# Usage:
#   python3 fish_realistic.py --all                      # 5 fish + rigged trout + 3 props + contact sheet
#   python3 fish_realistic.py --preset trout --preset dock
#   python3 fish_realistic.py --all --out /some/dir       # writes <dir>/exports_v2 and <dir>/previews_v2
#   python3 fish_realistic.py --preset pike --views 34,side,top,front
#   python3 fish_realistic.py --all --no-fbx --no-render  # just bake + manifest
#   python3 fish_realistic.py --list
#
# Axes: mouth tip at the origin, +X forward (nose), +Z up, +Y = the fish's left side. 1 BU = 1 m.

import argparse
import json
import math
import os
import sys
import time

import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------------------------------
# PARAMETERS (fish)
# ----------------------------------------------------------------------------------------------
# Every length is a FRACTION of length_m unless the key ends in _m. t = fraction of the BODY length
# (0 = mouth tip, 1 = end of the caudal peduncle = root of the tail fin); fin positions use the
# fraction of the TOTAL length (0 = mouth tip, 1 = tail tips) as the spec gives them.
#
# key              meaning                                                               typical
# length_m         total length, mouth tip to tail tips, metres                           0.08 .. 0.70
# tail_len         caudal fin length / total length                                       0.14 .. 0.20
# top              dorsal outline: (t, z/L) points, z above the mouth-tip axis            z 0 .. 0.17
# bot              ventral outline: (t, z/L) points, z below the axis (negative)          z 0 .. -0.17
# wid              half-width outline: (t, w/L) points                                    w 0 .. 0.09
# sec_exp          cross-section superellipse exponent: 1 ellipse, 0.8 flatter flanks    0.75 .. 1.0
# belly_taper      0..0.5 narrows the lower half of the section (keeled belly)            0.1 .. 0.35
# head_len         head length (snout to gill-plate edge) / body length                   0.22 .. 0.34
# head_flat        0..0.6 flattens the top of the snout (pike duck-bill)                  0.0 .. 0.5
# head_wide        0..0.4 widens the snout (pike)                                         0.0 .. 0.3
# nose_t           t of the first ring (blunt snout: bigger = blunter)                    0.012 .. 0.03
# mouth_t          t of the mouth-line notch ring                                         0.05 .. 0.09
# mouth_notch      radial indent of the notch ring (fraction of local radius)             0.03 .. 0.08
# jaw_proj         lower-jaw projection beyond the upper lip / L (trout, pike)            0 .. 0.02
# gill_inset       radial inset of the gill-plate seam ring                               0.02 .. 0.04
# gill_bulge       how far the seam bows backwards at mid-height / L                      0.01 .. 0.03
# eye_t            eye centre along the head (0 snout .. 1 gill)                          0.35 .. 0.5
# eye_z            eye height in the section (-1 belly .. +1 back)                        0.25 .. 0.45
# eye_r            eye radius / L                                                         0.025 .. 0.04
# rings, sides     body rings along the length, vertices per ring                         24-32, 16-20
# subdiv           apply one Catmull-Clark level to the body if the budget allows         True/False
# fin_th           fin slab thickness / L                                                 0.003 .. 0.006
# fins             list of fin dicts (kind, t0, t1 along TOTAL length, h height/L, rake,
#                  outline [(s, h fraction)], rays, cols, rows, curl; paddles: dir, len)
# barbels          carp: True adds two small cones at the mouth corners
# colours/pattern  see the PATTERN block in each preset (back, side, belly, band, spots, bars, scales,
#                  fin colours per fin kind, eye iris). All linear RGB 0..1.

ATLAS = 1024
RENDER = dict(res_x=800, res_y=600, samples_preview=64, samples_final=128)
BUDGET = dict(fish_min=2500, fish_max=6000, roblox_max=10000)
FIN_KINDS = ["none", "dorsal", "adipose", "caudal", "anal", "pelvic", "pectoral", "dorsal2"]
FIN_ID = {k: i for i, k in enumerate(FIN_KINDS)}

# shared outline templates (s along the fin base 0 front .. 1 rear, height fraction)
OUT_DORSAL = [(0.0, 0.62), (0.10, 1.0), (0.35, 0.86), (0.70, 0.60), (1.0, 0.40)]
OUT_SPINY = [(0.0, 0.30), (0.28, 1.0), (0.55, 0.88), (0.80, 0.62), (1.0, 0.30)]
OUT_SOFT = [(0.0, 0.40), (0.22, 1.0), (0.60, 0.82), (1.0, 0.42)]
OUT_ROUND = [(0.0, 0.40), (0.35, 1.0), (0.70, 0.88), (1.0, 0.35)]
OUT_ANAL = [(0.0, 0.60), (0.15, 1.0), (0.55, 0.75), (1.0, 0.40)]
OUT_LOBE = [(0.0, 0.20), (0.35, 1.0), (0.75, 0.85), (1.0, 0.25)]
OUT_CARP_DORSAL = [(0.0, 0.40), (0.07, 1.0), (0.25, 0.62), (0.60, 0.42), (1.0, 0.30)]

PRESETS = {
    # rainbow trout 0.40 m: streamlined, rounded snout, lower jaw a touch longer, adipose fin
    "trout": dict(
        kind="fish", length_m=0.40, tail_len=0.17,
        top=[(0.0, 0.0), (0.02, 0.034), (0.08, 0.064), (0.22, 0.098), (0.42, 0.118), (0.62, 0.105),
             (0.80, 0.068), (0.92, 0.046), (1.0, 0.042)],
        bot=[(0.0, 0.0), (0.02, -0.028), (0.08, -0.056), (0.22, -0.086), (0.40, -0.104), (0.60, -0.094),
             (0.80, -0.058), (0.92, -0.040), (1.0, -0.036)],
        wid=[(0.0, 0.0), (0.02, 0.016), (0.08, 0.038), (0.22, 0.056), (0.42, 0.062), (0.62, 0.054),
             (0.80, 0.034), (0.92, 0.020), (1.0, 0.016)],
        sec_exp=0.88, belly_taper=0.18, head_len=0.26, head_flat=0.0, head_wide=0.0,
        nose_t=0.02, mouth_t=0.065, mouth_notch=0.05, jaw_proj=0.010,
        gill_inset=0.045, gill_bulge=0.022, eye_t=0.38, eye_z=0.42, eye_r=0.021,
        rings=30, sides=18, subdiv=True, fin_th=0.004, barbels=False,
        fins=[
            dict(kind="dorsal", t0=0.44, t1=0.57, h=0.085, rake=0.30, outline=OUT_DORSAL, rays=10),
            dict(kind="adipose", t0=0.77, t1=0.81, h=0.030, rake=0.6, outline=OUT_LOBE, rays=0, cols=5),
            dict(kind="caudal", span=0.23, fork=0.18, round=0.45, rays=14),
            dict(kind="anal", t0=0.72, t1=0.80, h=0.065, rake=0.35, outline=OUT_ANAL, rays=8),
            dict(kind="pelvic", t0=0.50, base=0.035, len=0.070, dir=(-0.55, 0.45, -0.55), rays=6),
            dict(kind="pectoral", t0=0.235, base=0.040, len=0.095, dir=(-0.60, 0.70, -0.45), rays=8),
        ],
        pattern=dict(
            back=(0.12, 0.19, 0.11), side=(0.60, 0.65, 0.60), belly=(0.92, 0.92, 0.86),
            back_pos=0.80, side_pos=0.50, belly_pos=0.22,
            band=(0.80, 0.28, 0.32), band_vz=0.0, band_w=0.22, band_strength=0.8, band_ux=(0.06, 0.95),
            cheek=(0.82, 0.40, 0.42), cheek_strength=0.6,
            spots=(0.05, 0.05, 0.04), spot_cell_m=0.0080, spot_size=0.19, spot_density=0.55,
            spot_floor=-0.15, spot_aniso=(1.0, 1.0, 1.0), spot_fins=("dorsal", "adipose", "caudal"),
            bars=0, scale_cell_m=0.006, scale_strength=0.10, scale_var=0.06,
            fins={"dorsal": (0.26, 0.30, 0.20), "adipose": (0.30, 0.26, 0.20), "caudal": (0.30, 0.32, 0.24),
                  "anal": (0.50, 0.38, 0.32), "pelvic": (0.54, 0.40, 0.32), "pectoral": (0.50, 0.42, 0.32)},
            fin_tip=(0.90, 0.90, 0.86), fin_tip_strength=0.2, fin_edge_dark=0.3, fin_ray_dark=0.12,
            iris=(0.86, 0.72, 0.36), pupil=(0.02, 0.02, 0.02),
            mouth_vz=-0.18, mouth_len=0.42, gill_dark=0.40,
        ),
    ),
    # European perch 0.25 m: deep humped body, two dorsals (spiny + soft), bars, orange lower fins
    "perch": dict(
        kind="fish", length_m=0.25, tail_len=0.16,
        top=[(0.0, 0.0), (0.02, 0.028), (0.10, 0.075), (0.25, 0.135), (0.42, 0.158), (0.60, 0.132),
             (0.80, 0.078), (0.92, 0.050), (1.0, 0.046)],
        bot=[(0.0, 0.0), (0.02, -0.024), (0.10, -0.062), (0.25, -0.098), (0.42, -0.108), (0.60, -0.096),
             (0.80, -0.056), (0.92, -0.040), (1.0, -0.036)],
        wid=[(0.0, 0.0), (0.02, 0.014), (0.10, 0.040), (0.25, 0.060), (0.42, 0.064), (0.60, 0.056),
             (0.80, 0.034), (0.92, 0.020), (1.0, 0.016)],
        sec_exp=0.86, belly_taper=0.25, head_len=0.30, head_flat=0.0, head_wide=0.0,
        nose_t=0.016, mouth_t=0.07, mouth_notch=0.05, jaw_proj=0.004,
        gill_inset=0.05, gill_bulge=0.025, eye_t=0.38, eye_z=0.42, eye_r=0.028,
        rings=28, sides=18, subdiv=True, fin_th=0.004, barbels=False,
        fins=[
            dict(kind="dorsal", t0=0.30, t1=0.53, h=0.145, rake=0.10, outline=OUT_SPINY, rays=13, scallop=0.12),
            dict(kind="dorsal2", t0=0.56, t1=0.69, h=0.085, rake=0.25, outline=OUT_SOFT, rays=9),
            dict(kind="caudal", span=0.26, fork=0.08, round=0.45, rays=14),
            dict(kind="anal", t0=0.60, t1=0.71, h=0.085, rake=0.30, outline=OUT_ANAL, rays=8),
            dict(kind="pelvic", t0=0.36, base=0.035, len=0.085, dir=(-0.50, 0.42, -0.62), rays=6),
            dict(kind="pectoral", t0=0.30, base=0.040, len=0.100, dir=(-0.60, 0.70, -0.30), rays=8),
        ],
        pattern=dict(
            back=(0.14, 0.22, 0.08), side=(0.60, 0.58, 0.22), belly=(0.92, 0.90, 0.72),
            back_pos=0.82, side_pos=0.48, belly_pos=0.20,
            band=None, cheek=(0.62, 0.60, 0.26), cheek_strength=0.3,
            spots=None, spot_fins=(),
            bars=6, bar_colour=(0.05, 0.09, 0.03), bar_strength=0.92, bar_width=0.40, bar_ux=(0.27, 0.86),
            bar_floor=-0.45,
            scale_cell_m=0.0055, scale_strength=0.14, scale_var=0.08,
            fins={"dorsal": (0.30, 0.34, 0.22), "dorsal2": (0.42, 0.44, 0.28), "caudal": (0.86, 0.36, 0.08),
                  "anal": (0.90, 0.38, 0.06), "pelvic": (0.92, 0.40, 0.06), "pectoral": (0.70, 0.56, 0.30)},
            fin_tip=(0.30, 0.30, 0.22), fin_tip_strength=0.2, fin_edge_dark=0.3, fin_ray_dark=0.22,
            dorsal_spot=True,
            iris=(0.88, 0.66, 0.20), pupil=(0.02, 0.02, 0.02),
            mouth_vz=-0.20, mouth_len=0.45, gill_dark=0.45,
        ),
    ),
    # northern pike 0.70 m: long, flat duck-bill snout, fins set far back, pale bean spots
    "pike": dict(
        kind="fish", length_m=0.70, tail_len=0.15,
        top=[(0.0, 0.0), (0.02, 0.014), (0.10, 0.032), (0.25, 0.052), (0.42, 0.066), (0.62, 0.070),
             (0.80, 0.056), (0.92, 0.038), (1.0, 0.034)],
        bot=[(0.0, 0.0), (0.02, -0.016), (0.10, -0.036), (0.25, -0.056), (0.42, -0.068), (0.62, -0.068),
             (0.80, -0.052), (0.92, -0.036), (1.0, -0.032)],
        wid=[(0.0, 0.0), (0.02, 0.016), (0.10, 0.034), (0.25, 0.046), (0.42, 0.050), (0.62, 0.048),
             (0.80, 0.034), (0.92, 0.020), (1.0, 0.016)],
        sec_exp=0.92, belly_taper=0.12, head_len=0.32, head_flat=0.45, head_wide=0.30,
        nose_t=0.02, mouth_t=0.10, mouth_notch=0.045, jaw_proj=0.014,
        gill_inset=0.04, gill_bulge=0.025, eye_t=0.56, eye_z=0.55, eye_r=0.017,
        rings=28, sides=18, subdiv=True, fin_th=0.004, barbels=False,
        fins=[
            dict(kind="dorsal", t0=0.68, t1=0.81, h=0.085, rake=0.30, outline=OUT_ROUND, rays=10),
            dict(kind="caudal", span=0.22, fork=0.25, round=0.40, rays=14),
            dict(kind="anal", t0=0.70, t1=0.81, h=0.078, rake=0.30, outline=OUT_ROUND, rays=9),
            dict(kind="pelvic", t0=0.50, base=0.035, len=0.075, dir=(-0.55, 0.42, -0.58), rays=6),
            dict(kind="pectoral", t0=0.30, base=0.040, len=0.085, dir=(-0.60, 0.68, -0.40), rays=8),
        ],
        pattern=dict(
            back=(0.10, 0.18, 0.07), side=(0.34, 0.42, 0.18), belly=(0.90, 0.90, 0.74),
            back_pos=0.80, side_pos=0.45, belly_pos=0.22,
            band=None, cheek=(0.42, 0.46, 0.20), cheek_strength=0.3,
            spots=(0.88, 0.84, 0.50), spot_cell_m=0.021, spot_size=0.30, spot_density=0.85, spot_random=0.5,
            spot_floor=-0.55, spot_aniso=(0.42, 1.5, 1.5), spot_fins=(),
            fin_blotch=(0.08, 0.08, 0.05), fin_blotch_cell_m=0.02,
            bars=0, scale_cell_m=0.006, scale_strength=0.10, scale_var=0.05,
            fins={"dorsal": (0.52, 0.46, 0.22), "caudal": (0.50, 0.44, 0.22), "anal": (0.56, 0.46, 0.24),
                  "pelvic": (0.62, 0.50, 0.26), "pectoral": (0.60, 0.50, 0.28)},
            fin_tip=(0.5, 0.45, 0.25), fin_tip_strength=0.1, fin_edge_dark=0.35, fin_ray_dark=0.2,
            iris=(0.90, 0.80, 0.30), pupil=(0.02, 0.02, 0.02),
            mouth_vz=-0.22, mouth_len=0.60, gill_dark=0.40,
        ),
    ),
    # common carp 0.50 m: deep heavy body, big scales, long dorsal base, barbels
    "carp": dict(
        kind="fish", length_m=0.50, tail_len=0.17,
        top=[(0.0, 0.0), (0.02, 0.030), (0.10, 0.080), (0.26, 0.150), (0.42, 0.166), (0.62, 0.140),
             (0.80, 0.085), (0.92, 0.056), (1.0, 0.050)],
        bot=[(0.0, 0.0), (0.02, -0.028), (0.10, -0.070), (0.26, -0.110), (0.42, -0.122), (0.62, -0.108),
             (0.80, -0.064), (0.92, -0.044), (1.0, -0.040)],
        wid=[(0.0, 0.0), (0.02, 0.018), (0.10, 0.050), (0.26, 0.078), (0.42, 0.084), (0.62, 0.074),
             (0.80, 0.044), (0.92, 0.026), (1.0, 0.020)],
        sec_exp=0.86, belly_taper=0.22, head_len=0.27, head_flat=0.0, head_wide=0.0,
        nose_t=0.018, mouth_t=0.06, mouth_notch=0.06, jaw_proj=0.0,
        gill_inset=0.045, gill_bulge=0.022, eye_t=0.42, eye_z=0.38, eye_r=0.018,
        rings=28, sides=18, subdiv=True, fin_th=0.005, barbels=True,
        fins=[
            dict(kind="dorsal", t0=0.38, t1=0.70, h=0.140, rake=0.20, outline=OUT_CARP_DORSAL, rays=16),
            dict(kind="caudal", span=0.28, fork=0.30, round=0.30, rays=14),
            dict(kind="anal", t0=0.70, t1=0.78, h=0.085, rake=0.35, outline=OUT_ANAL, rays=7),
            dict(kind="pelvic", t0=0.46, base=0.040, len=0.095, dir=(-0.50, 0.45, -0.60), rays=7),
            dict(kind="pectoral", t0=0.27, base=0.045, len=0.115, dir=(-0.60, 0.70, -0.35), rays=9),
        ],
        pattern=dict(
            back=(0.24, 0.16, 0.05), side=(0.70, 0.50, 0.17), belly=(0.92, 0.82, 0.50),
            back_pos=0.82, side_pos=0.45, belly_pos=0.18,
            band=None, cheek=(0.70, 0.52, 0.22), cheek_strength=0.25,
            spots=None, spot_fins=(),
            bars=0, scale_cell_m=0.019, scale_strength=0.36, scale_var=0.16,
            fins={"dorsal": (0.40, 0.30, 0.14), "caudal": (0.62, 0.36, 0.14), "anal": (0.72, 0.38, 0.14),
                  "pelvic": (0.78, 0.42, 0.16), "pectoral": (0.74, 0.42, 0.18)},
            fin_tip=(0.5, 0.3, 0.12), fin_tip_strength=0.2, fin_edge_dark=0.35, fin_ray_dark=0.2,
            iris=(0.90, 0.70, 0.30), pupil=(0.02, 0.02, 0.02),
            mouth_vz=-0.30, mouth_len=0.35, gill_dark=0.40,
        ),
    ),
    # minnow 0.08 m: slim, silver-olive, dark lateral stripe
    "minnow": dict(
        kind="fish", length_m=0.08, tail_len=0.18,
        top=[(0.0, 0.0), (0.02, 0.022), (0.10, 0.050), (0.25, 0.078), (0.42, 0.090), (0.62, 0.082),
             (0.80, 0.056), (0.92, 0.040), (1.0, 0.036)],
        bot=[(0.0, 0.0), (0.02, -0.020), (0.10, -0.046), (0.25, -0.070), (0.42, -0.080), (0.62, -0.072),
             (0.80, -0.048), (0.92, -0.034), (1.0, -0.030)],
        wid=[(0.0, 0.0), (0.02, 0.014), (0.10, 0.034), (0.25, 0.048), (0.42, 0.052), (0.62, 0.046),
             (0.80, 0.030), (0.92, 0.018), (1.0, 0.014)],
        sec_exp=0.95, belly_taper=0.15, head_len=0.26, head_flat=0.0, head_wide=0.0,
        nose_t=0.02, mouth_t=0.07, mouth_notch=0.04, jaw_proj=0.004,
        gill_inset=0.04, gill_bulge=0.02, eye_t=0.42, eye_z=0.42, eye_r=0.030,
        rings=26, sides=16, subdiv=True, fin_th=0.004, barbels=False,
        fins=[
            dict(kind="dorsal", t0=0.48, t1=0.58, h=0.095, rake=0.30, outline=OUT_SOFT, rays=8),
            dict(kind="caudal", span=0.25, fork=0.30, round=0.30, rays=12),
            dict(kind="anal", t0=0.66, t1=0.76, h=0.075, rake=0.35, outline=OUT_ANAL, rays=7),
            dict(kind="pelvic", t0=0.46, base=0.030, len=0.065, dir=(-0.55, 0.45, -0.55), rays=5),
            dict(kind="pectoral", t0=0.27, base=0.035, len=0.095, dir=(-0.60, 0.70, -0.35), rays=7),
        ],
        pattern=dict(
            back=(0.20, 0.26, 0.16), side=(0.70, 0.72, 0.66), belly=(0.94, 0.94, 0.92),
            back_pos=0.80, side_pos=0.50, belly_pos=0.25,
            band=(0.07, 0.08, 0.09), band_vz=-0.02, band_w=0.17, band_strength=0.95, band_ux=(0.16, 0.98),
            cheek=(0.72, 0.72, 0.66), cheek_strength=0.3,
            spots=None, spot_fins=(),
            bars=0, scale_cell_m=0.0022, scale_strength=0.08, scale_var=0.05,
            fins={"dorsal": (0.60, 0.62, 0.52), "caudal": (0.60, 0.62, 0.52), "anal": (0.72, 0.70, 0.60),
                  "pelvic": (0.74, 0.72, 0.62), "pectoral": (0.72, 0.70, 0.60)},
            fin_tip=(0.8, 0.8, 0.75), fin_tip_strength=0.2, fin_edge_dark=0.3, fin_ray_dark=0.15,
            iris=(0.86, 0.80, 0.50), pupil=(0.02, 0.02, 0.02),
            mouth_vz=-0.15, mouth_len=0.40, gill_dark=0.35,
        ),
    ),
    # props (built by prop builders below; kind decides the builder)
    "rod_and_reel": dict(kind="rod", length_m=2.1),
    "dock": dict(kind="dock", length_m=6.0),
    "trader_stall": dict(kind="stall", length_m=2.0),
}

VIEW_DIRS = {              # camera direction FROM the subject centre (subject faces +X, +Z up)
    "34": Vector((0.85, -1.0, 0.42)),
    "side": Vector((0.0, -1.0, 0.06)),
    "top": Vector((0.05, -0.05, 1.0)),
    "front": Vector((1.0, -0.25, 0.2)),
}


def log(msg):
    print(f"[v2] {msg}", flush=True)


# ----------------------------------------------------------------------------------------------
# CURVES
# ----------------------------------------------------------------------------------------------
def hermite(points, t):
    """Cubic Hermite through (t, y) points, finite-difference tangents (non-uniform Catmull-Rom)."""
    n = len(points)
    if t <= points[0][0]:
        return points[0][1]
    if t >= points[-1][0]:
        return points[-1][1]
    k = 0
    while k < n - 2 and t > points[k + 1][0]:
        k += 1
    t0, y0 = points[k]
    t1, y1 = points[k + 1]
    h = t1 - t0

    def slope(i):
        if i <= 0:
            return (points[1][1] - points[0][1]) / (points[1][0] - points[0][0])
        if i >= n - 1:
            return (points[-1][1] - points[-2][1]) / (points[-1][0] - points[-2][0])
        a = (points[i][1] - points[i - 1][1]) / (points[i][0] - points[i - 1][0])
        b = (points[i + 1][1] - points[i][1]) / (points[i + 1][0] - points[i][0])
        return 0.5 * (a + b)

    m0, m1 = slope(k) * h, slope(k + 1) * h
    u = (t - t0) / h
    u2, u3 = u * u, u * u * u
    return ((2 * u3 - 3 * u2 + 1) * y0 + (u3 - 2 * u2 + u) * m0
            + (-2 * u3 + 3 * u2) * y1 + (u3 - u2) * m1)


def smoothstep(a, b, x):
    if a == b:
        return 1.0 if x >= b else 0.0
    u = min(1.0, max(0.0, (x - a) / (b - a)))
    return u * u * (3.0 - 2.0 * u)


def body_len(P):
    return P["length_m"] * (1.0 - P["tail_len"])


def section(P, t):
    """(z_top, z_bot, half_width) in metres at body fraction t, head shaping included."""
    L = P["length_m"]
    zt = hermite(P["top"], t) * L
    zb = hermite(P["bot"], t) * L
    w = hermite(P["wid"], t) * L
    hl = P["head_len"]
    if t < hl:
        u = 1.0 - t / hl                                  # 1 at the snout, 0 at the gill
        zc = 0.5 * (zt + zb)
        zt = zc + (zt - zc) * (1.0 - P["head_flat"] * u ** 1.3)
        w *= (1.0 + P["head_wide"] * u ** 1.2)
    return zt, zb, w


def section_point(P, t, phi, zt, zb, w):
    """Point on the section at angle phi (0 = top of the back, pi = belly). +Y is the left side."""
    c, s = math.cos(phi), math.sin(phi)
    p = P["sec_exp"]
    zc = 0.5 * (zt + zb)
    hu, hl = zt - zc, zc - zb
    cz = math.copysign(abs(c) ** p, c)
    sy = math.copysign(abs(s) ** p, s)
    z = zc + (hu if c >= 0 else hl) * cz
    y = w * sy * (1.0 - P["belly_taper"] * max(0.0, -c))
    return y, z


def surface_point(P, t, phi):
    zt, zb, w = section(P, t)
    y, z = section_point(P, t, phi, zt, zb, w)
    return Vector((-t * body_len(P), y, z))


# ----------------------------------------------------------------------------------------------
# ATTRIBUTE LAYERS (point domain floats read by the Cycles Attribute node)
# ----------------------------------------------------------------------------------------------
ATTRS = ["ux", "vz", "region", "fid", "fr", "fs", "ray", "eyea"]


def attr_layers(bm):
    return {n: (bm.verts.layers.float.get(n) or bm.verts.layers.float.new(n)) for n in ATTRS}


def set_attrs(v, lay, **kw):
    for k, val in kw.items():
        v[lay[k]] = float(val)


# ----------------------------------------------------------------------------------------------
# BODY
# ----------------------------------------------------------------------------------------------
def ring_stations(P):
    """Sorted t values of the body rings: uniform-ish (denser at the head) plus anatomical rings."""
    n = P["rings"]
    gill_t = P["head_len"]
    stations = [P["nose_t"], P["mouth_t"], gill_t - 0.012, gill_t, gill_t + 0.014, 1.0]
    fill = [(i / (n - 1)) ** 0.92 for i in range(1, n - 1)]
    fill = [t for t in fill if t > P["nose_t"] + 0.015]
    spacing = 1.0 / n
    out = list(stations)
    for t in fill:
        if all(abs(t - s) > 0.45 * spacing for s in stations):
            out.append(t)
    return sorted(set(out))


def build_body(P, lay, bm):
    """Lofted body with nose pole, mouth notch ring, curved gill seam, peduncle and tail cap.
    Returns (rings, faces)."""
    L = P["length_m"]
    Lb = body_len(P)
    sides = P["sides"]
    gill_t = P["head_len"]
    ts = ring_stations(P)
    rings = []
    for t in ts:
        zt, zb, w = section(P, t)
        scale = 1.0
        if abs(t - P["mouth_t"]) < 1e-9:
            scale = 1.0 - P["mouth_notch"]
        if abs(t - gill_t) < 1e-9:
            scale = 1.0 - P["gill_inset"]
        ring = []
        for j in range(sides):
            phi = 2.0 * math.pi * j / sides
            c, s = math.cos(phi), math.sin(phi)
            y, z = section_point(P, t, phi, zt, zb, w)
            zc = 0.5 * (zt + zb)
            y, z = y * scale, zc + (z - zc) * scale
            x = -t * Lb
            # lower jaw slightly longer: push the lower half of the first rings forward
            if t < P["mouth_t"] * 1.6 and P["jaw_proj"] > 0:
                x += P["jaw_proj"] * L * max(0.0, -c) ** 1.5 * (1.0 - t / (P["mouth_t"] * 1.6))
            # gill-plate seam bows backwards at mid-height (operculum edge)
            if abs(t - gill_t) < 1e-9 or abs(t - (gill_t + 0.014)) < 1e-9 or abs(t - (gill_t - 0.012)) < 1e-9:
                x -= P["gill_bulge"] * L * abs(s) ** 1.4
            v = bm.verts.new((x, y, z))
            set_attrs(v, lay, ux=t * (1.0 - P["tail_len"]), vz=c, region=0, fid=0, fr=0, fs=0, ray=0, eyea=1)
            ring.append(v)
        rings.append(ring)

    nose = bm.verts.new((0.0, 0.0, 0.0))
    set_attrs(nose, lay, ux=0, vz=0, region=0, fid=0, fr=0, fs=0, ray=0, eyea=1)
    zt, zb, _ = section(P, 1.0)
    tail = bm.verts.new((-Lb - 0.01 * L, 0.0, 0.5 * (zt + zb)))
    set_attrs(tail, lay, ux=1.0 - P["tail_len"], vz=0, region=0, fid=0, fr=0, fs=0, ray=0, eyea=1)

    faces = []
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(sides):
            jn = (j + 1) % sides
            faces.append(bm.faces.new((a[j], a[jn], b[jn], b[j])))
    for j in range(sides):
        jn = (j + 1) % sides
        faces.append(bm.faces.new((nose, rings[0][jn], rings[0][j])))
    last = rings[-1]
    for j in range(sides):
        jn = (j + 1) % sides
        faces.append(bm.faces.new((tail, last[j], last[jn])))

    # seams for the unwrap: along the back (j = 0) and the belly (j = sides/2), nose to tail
    half = sides // 2
    for i in range(len(rings) - 1):
        for j in (0, half):
            e = bm.edges.get((rings[i][j], rings[i + 1][j]))
            if e:
                e.seam = True
    for j in (0, half):
        e = bm.edges.get((nose, rings[0][j]))
        if e:
            e.seam = True
        e = bm.edges.get((tail, rings[-1][j]))
        if e:
            e.seam = True
    # gill seam ring edges sharp so the step catches the light
    gi = ts.index(gill_t)
    for j in range(sides):
        e = bm.edges.get((rings[gi][j], rings[gi][(j + 1) % sides]))
        if e:
            e.smooth = False
    return rings, faces


# ----------------------------------------------------------------------------------------------
# FINS (thin slabs built from a base curve and an outline; UV = (s, r))
# ----------------------------------------------------------------------------------------------
def fin_grid(bm, lay, grid, normal, th, fid, uv_rect, uvs, rays=0):
    """grid: rows x cols of Vectors (row 0 = base). Makes a two-sided slab with a rim.
    Writes (s, r) UVs mapped into uv_rect for every face loop. Returns faces."""
    rows, cols = len(grid), len(grid[0])
    top, bot = [], []
    for ri in range(rows):
        r = ri / (rows - 1)
        trow, brow = [], []
        for ci in range(cols):
            s = ci / (cols - 1)
            p = grid[ri][ci]
            n = normal(ri, ci) * (0.5 * th)
            vt = bm.verts.new(p + n)
            vb = bm.verts.new(p - n)
            for v in (vt, vb):
                set_attrs(v, lay, ux=0, vz=0, region=1, fid=fid, fr=r, fs=s, ray=s * rays, eyea=1)
            trow.append(vt)
            brow.append(vb)
        top.append(trow)
        bot.append(brow)
    faces = []
    u0, v0, u1, v1 = uv_rect

    def uv(ci, ri):
        return (u0 + (u1 - u0) * ci / (cols - 1), v0 + (v1 - v0) * ri / (rows - 1))

    def quad(verts, coords):
        f = bm.faces.new(verts)
        uvs[f] = {v: c for v, c in zip(verts, coords)}
        return f

    for ri in range(rows - 1):
        for ci in range(cols - 1):
            faces.append(quad((top[ri][ci], top[ri][ci + 1], top[ri + 1][ci + 1], top[ri + 1][ci]),
                              (uv(ci, ri), uv(ci + 1, ri), uv(ci + 1, ri + 1), uv(ci, ri + 1))))
            faces.append(quad((bot[ri][ci], bot[ri + 1][ci], bot[ri + 1][ci + 1], bot[ri][ci + 1]),
                              (uv(ci, ri), uv(ci, ri + 1), uv(ci + 1, ri + 1), uv(ci + 1, ri))))
    # rim: outer edge (last row), front and rear columns (the base row is buried in the body)
    rim = []
    for ci in range(cols - 1):
        rim.append(((rows - 1, ci), (rows - 1, ci + 1)))
    for ri in range(rows - 1):
        rim.append(((ri, 0), (ri + 1, 0)))
        rim.append(((ri + 1, cols - 1), (ri, cols - 1)))
    for (ra, ca), (rb, cb) in rim:
        faces.append(quad((top[ra][ca], bot[ra][ca], bot[rb][cb], top[rb][cb]),
                          (uv(ca, ra), uv(ca, ra), uv(cb, rb), uv(cb, rb))))
    topset = {v for row in top for v in row}
    for f in faces:
        for e in f.edges:
            a, b = e.verts
            if (a in topset) != (b in topset):               # edges that cross the slab = rim edges
                e.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def outline_h(fin, s):
    h = hermite(fin["outline"], s)
    rays = fin.get("rays", 0)
    if rays:
        amp = fin.get("scallop", 0.035)
        h *= 1.0 - amp * (0.5 - 0.5 * math.cos(2.0 * math.pi * s * rays))
    return h


def add_median_fin(bm, lay, P, fin, uv_rect, uvs):
    """dorsal / dorsal2 / adipose / anal: base on the top or bottom midline, rows grow away from it."""
    L = P["length_m"]
    Lb = body_len(P)
    kind = fin["kind"]
    down = kind == "anal"
    cols = fin.get("cols", 9)
    rows = fin.get("rows", 4)
    t0 = fin["t0"] * L / Lb
    t1 = fin["t1"] * L / Lb
    H = fin["h"] * L
    curl = fin.get("curl", 0.0) * L
    grid = []
    for ri in range(rows):
        r = ri / (rows - 1)
        row = []
        for ci in range(cols):
            s = ci / (cols - 1)
            t = t0 + (t1 - t0) * s
            zt, zb, w = section(P, t)
            embed = 0.25 * (zt - zb) * 0.5
            base = Vector((-t * Lb, 0.0, (zb + embed) if down else (zt - embed)))
            h = outline_h(fin, s) * H + embed
            d = Vector((-fin["rake"], 0.0, -1.0 if down else 1.0)).normalized()
            p = base + d * (h * r) + Vector((0.0, curl * r * r, 0.0))
            row.append(p)
        grid.append(row)
    return fin_grid(bm, lay, grid, lambda ri, ci: Vector((0.0, 1.0, 0.0)), P["fin_th"] * L, FIN_ID[kind],
                    uv_rect, uvs, rays=fin.get("rays", 0))


def add_caudal(bm, lay, P, fin, uv_rect, uvs):
    L = P["length_m"]
    Lb = body_len(P)
    cols = fin.get("cols", 13)
    rows = fin.get("rows", 5)
    Lt = P["tail_len"] * L
    span = fin["span"] * L
    fork = fin["fork"]
    rnd = fin["round"]
    zt, zb, _ = section(P, 1.0)
    zc = 0.5 * (zt + zb)
    rays = fin.get("rays", 0)
    xr = -Lb + 0.035 * L

    def ray_len(v):
        f = 1.0 - fork * (1.0 - abs(v) ** 1.5)
        if abs(v) > 0.62:
            q = (abs(v) - 0.62) / 0.38
            f *= 1.0 - rnd * (1.0 - math.sqrt(max(0.0, 1.0 - q * q)))
        return f

    norm = max(ray_len(1.0 - 2.0 * k / 200.0) for k in range(201))
    grid = []
    for ri in range(rows):
        r = ri / (rows - 1)
        row = []
        for ci in range(cols):
            s = ci / (cols - 1)
            v = 1.0 - 2.0 * s                                  # +1 top lobe .. -1 bottom lobe
            z0 = zc + v * 0.85 * (zt - zc if v >= 0 else zc - zb)
            ln = (Lt + 0.035 * L) * ray_len(v) / norm
            if rays:
                ln *= 1.0 - 0.025 * (0.5 - 0.5 * math.cos(2.0 * math.pi * s * rays))
            spread = v * (0.5 * span) - (z0 - zc)
            if abs(v) > 0.62:
                q = (abs(v) - 0.62) / 0.38
                spread *= 1.0 - 0.45 * rnd * (1.0 - math.sqrt(max(0.0, 1.0 - q * q)))
            p = Vector((xr - ln * r, 0.0, z0 + spread * r * (0.35 + 0.65 * r)))
            row.append(p)
        grid.append(row)
    return fin_grid(bm, lay, grid, lambda ri, ci: Vector((0.0, 1.0, 0.0)), P["fin_th"] * L,
                    FIN_ID["caudal"], uv_rect, uvs, rays=rays)


def add_paddle(bm, lay, P, fin, side, uv_rect, uvs):
    """pectoral / pelvic: a rounded paddle on the flank, angled down and back."""
    L = P["length_m"]
    Lb = body_len(P)
    cols = fin.get("cols", 7)
    rows = fin.get("rows", 4)
    kind = fin["kind"]
    t0 = fin["t0"] * L / Lb
    t1 = t0 + fin["base"] * L / Lb
    phi = math.radians(112.0 if kind == "pectoral" else 150.0)
    d = Vector(fin["dir"])
    d = Vector((d.x, d.y * side, d.z)).normalized()
    ln = fin["len"] * L
    grid = []
    for ri in range(rows):
        r = ri / (rows - 1)
        row = []
        for ci in range(cols):
            s = ci / (cols - 1)
            t = t0 + (t1 - t0) * s
            zt, zb, w = section(P, t)
            sp = surface_point(P, t, phi * side if side > 0 else -phi)
            centre = Vector((sp.x, 0.0, 0.5 * (zt + zb)))
            base = centre + (sp - centre) * 0.72                   # embedded ~28 % of the local radius
            h = (0.30 + 0.70 * math.sin(math.pi * s) ** 0.55) * ln
            rays = fin.get("rays", 0)
            if rays:
                h *= 1.0 - 0.04 * (0.5 - 0.5 * math.cos(2.0 * math.pi * s * rays))
            sweep = Vector((-0.25 * ln * s, 0.0, 0.0))             # rear rays trail further back
            row.append(base + d * (h * r) + sweep * r)
        grid.append(row)
    along = (grid[0][-1] - grid[0][0]).normalized()
    n = along.cross(d).normalized()
    return fin_grid(bm, lay, grid, lambda ri, ci: n, P["fin_th"] * L, FIN_ID[kind], uv_rect, uvs,
                    rays=fin.get("rays", 0))


# ----------------------------------------------------------------------------------------------
# EYES AND BARBELS
# ----------------------------------------------------------------------------------------------
def add_eye(bm, lay, P, side, uv_rect, uvs):
    L = P["length_m"]
    Lb = body_len(P)
    t = P["eye_t"] * P["head_len"]
    zt, zb, w = section(P, t)
    r = P["eye_r"] * L
    r = min(r, 0.45 * (zt - zb) * 0.5)
    phi = math.acos(P["eye_z"])                                  # angle from the top
    y, z = section_point(P, t, phi, zt, zb, w)
    centre = Vector((-t * Lb, side * y * 0.84, z))
    mtx = Matrix.Translation(centre) @ Matrix.Diagonal((r, r, r, 1.0))
    res = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=7, radius=1.0, matrix=mtx)
    verts = res["verts"]
    out_axis = Vector((0.0, side, 0.0))
    u0, v0, u1, v1 = uv_rect
    faces = set()
    for v in verts:
        d = (v.co - centre) / r
        ang = math.acos(max(-1.0, min(1.0, d.dot(out_axis))))
        set_attrs(v, lay, ux=0, vz=0, region=2, fid=0, fr=0, fs=0, ray=0, eyea=ang / math.pi * 2.0)
        faces.update(v.link_faces)
    for f in faces:
        d_ = {}
        for v in f.verts:
            d = (v.co - centre) / r
            d_[v] = (u0 + (u1 - u0) * (0.5 + 0.48 * d.x), v0 + (v1 - v0) * (0.5 + 0.48 * d.z))
        uvs[f] = d_
    return list(faces)


def add_barbels(bm, lay, P, uvs, uv_rect):
    L = P["length_m"]
    Lb = body_len(P)
    faces = []
    t = P["mouth_t"] * 1.3
    zt, zb, w = section(P, t)
    for side in (1.0, -1.0):
        y, z = section_point(P, t, math.radians(118.0), zt, zb, w)
        base = Vector((-t * Lb + 0.004 * L, side * y * 0.9, z))
        d = Vector((0.35, side * 0.9, -0.6)).normalized()
        mtx = Matrix.Translation(base + d * 0.022 * L) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=5, radius1=0.0035 * L,
                                    radius2=0.0006 * L, depth=0.05 * L, matrix=mtx)
        fs = set()
        cen = base + d * 0.022 * L
        for v in res["verts"]:
            set_attrs(v, lay, ux=0, vz=0, region=1, fid=FIN_ID["pectoral"], fr=0.3, fs=0.5, ray=0, eyea=1)
            fs.update(v.link_faces)
        u0, v0, u1, v1 = uv_rect
        for f in fs:
            uvs[f] = {}
            for v in f.verts:
                q = (v.co - cen) / (0.03 * L)
                uvs[f][v] = (u0 + (u1 - u0) * (0.5 + 0.45 * q.x), v0 + (v1 - v0) * (0.5 + 0.45 * q.z))
        faces += list(fs)
    return faces


# ----------------------------------------------------------------------------------------------
# UV LAYOUT
# ----------------------------------------------------------------------------------------------
BODY_L_RECT = (0.01, 0.635, 0.99, 0.99)
BODY_R_RECT = (0.01, 0.27, 0.99, 0.625)
STRIP = (0.01, 0.01, 0.99, 0.26)


def fin_rects(fins):
    """One rect per fin piece in the bottom strip: caudal gets a square, paddles a half square."""
    pieces = []
    for fin in fins:
        if fin["kind"] in ("pectoral", "pelvic"):
            pieces.append((fin["kind"] + "_L", 0.55))
            pieces.append((fin["kind"] + "_R", 0.55))
        elif fin["kind"] == "caudal":
            pieces.append((fin["kind"], 1.0))
        elif fin["kind"] == "adipose":
            pieces.append((fin["kind"], 0.35))
        else:
            pieces.append((fin["kind"], 0.8))
    pieces.append(("eye_L", 0.5))
    pieces.append(("eye_R", 0.5))
    pieces.append(("barbel", 0.15))
    total = sum(w for _, w in pieces)
    gap = 0.006
    x0, y0, x1, y1 = STRIP
    width = (x1 - x0) - gap * (len(pieces) - 1)
    rects = {}
    x = x0
    for name, w in pieces:
        ww = width * w / total
        if name.startswith("eye"):
            side = min(ww, y1 - y0)
            rects[name] = (x, y0, x + side, y0 + side)
        else:
            rects[name] = (x, y0, x + ww, y1)
        x += ww + gap
    return rects


def unwrap_body(obj, body_face_idx):
    """Angle-based unwrap of the body faces only (seams on back and belly), then fit the two
    islands (left +Y / right -Y) into their atlas rects. Falls back to a cylindrical map."""
    me = obj.data
    for p in me.polygons:
        p.select = p.index in body_face_idx
    ok = True
    try:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.001)
        bpy.ops.object.mode_set(mode="OBJECT")
    except Exception as exc:          # pragma: no cover
        log(f"uv.unwrap failed ({exc}); using the cylindrical fallback")
        ok = False
        if obj.mode != "OBJECT":
            bpy.ops.object.mode_set(mode="OBJECT")
    uv = me.uv_layers.active.data
    groups = {"L": [], "R": []}
    for pi in body_face_idx:
        p = me.polygons[pi]
        cy = sum(me.vertices[v].co.y for v in p.vertices) / len(p.vertices)
        groups["L" if cy >= -1e-7 else "R"].append(p)
    for key, polys in groups.items():
        rect = BODY_L_RECT if key == "L" else BODY_R_RECT
        if not ok:
            for p in polys:
                for li in p.loop_indices:
                    co = me.vertices[me.loops[li].vertex_index].co
                    uv[li].uv = (-co.x, 0.5 * (co.z + 1.0))
        us = [uv[li].uv.x for p in polys for li in p.loop_indices]
        vs = [uv[li].uv.y for p in polys for li in p.loop_indices]
        umin, umax, vmin, vmax = min(us), max(us), min(vs), max(vs)
        # the unwrap orients islands arbitrarily: rotate so the long axis is horizontal
        if (vmax - vmin) > (umax - umin):
            for p in polys:
                for li in p.loop_indices:
                    x, y = uv[li].uv
                    uv[li].uv = (y, -x)
            us = [uv[li].uv.x for p in polys for li in p.loop_indices]
            vs = [uv[li].uv.y for p in polys for li in p.loop_indices]
            umin, umax, vmin, vmax = min(us), max(us), min(vs), max(vs)
        # nose on the left (u small): the nose pole has x = 0 (max x)
        nose_u = None
        for p in polys:
            for li in p.loop_indices:
                if me.vertices[me.loops[li].vertex_index].co.x > -1e-6:
                    nose_u = uv[li].uv.x
        flip_u = nose_u is not None and nose_u > 0.5 * (umin + umax)
        # back on top (v large): compare the mean v of back vertices vs belly vertices
        back_v, belly_v = [], []
        for p in polys:
            for li in p.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                (back_v if co.z > 0.0 else belly_v).append(uv[li].uv.y)
        flip_v = back_v and belly_v and (sum(back_v) / len(back_v) < sum(belly_v) / len(belly_v))
        sx = (rect[2] - rect[0]) / max(1e-9, umax - umin)
        sy = (rect[3] - rect[1]) / max(1e-9, vmax - vmin)
        sc = min(sx, sy)
        wu, wv = (umax - umin) * sc, (vmax - vmin) * sc
        ox = rect[0] + 0.5 * ((rect[2] - rect[0]) - wu)
        oy = rect[1] + 0.5 * ((rect[3] - rect[1]) - wv)
        for p in polys:
            for li in p.loop_indices:
                x, y = uv[li].uv
                fx = (umax - x) if flip_u else (x - umin)
                fy = (vmax - y) if flip_v else (y - vmin)
                uv[li].uv = (ox + fx * sc, oy + fy * sc)
    for p in me.polygons:
        p.select = False
    return ok


# ----------------------------------------------------------------------------------------------
# MATERIAL (procedural, baked)
# ----------------------------------------------------------------------------------------------
class NB:
    """Tiny node-builder: nb.n(type, **props) then nb.link / value helpers."""

    def __init__(self, tree):
        self.t = tree
        self.nodes = tree.nodes
        self.links = tree.links
        self.x = 0

    def n(self, kind, **props):
        node = self.nodes.new(kind)
        node.location = (self.x, 0)
        self.x += 180
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def put(self, sock, val):
        if val is None:
            return
        if hasattr(val, "is_linked"):           # a socket
            self.links.new(val, sock)
        elif isinstance(val, (tuple, list)) and len(val) == 3 and sock.type == "RGBA":
            sock.default_value = (val[0], val[1], val[2], 1.0)
        else:
            sock.default_value = val

    def math(self, op, a, b=None, c=None, clamp=False):
        m = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.put(m.inputs[0], a)
        self.put(m.inputs[1], b)
        self.put(m.inputs[2], c)
        return m.outputs[0]

    def mix(self, fac, a, b):
        m = self.n("ShaderNodeMix", data_type="RGBA", blend_type="MIX", clamp_factor=True)
        ins = {(s.name, s.type): s for s in m.inputs}
        self.put(ins[("Factor", "VALUE")], fac)
        self.put(ins[("A", "RGBA")], a)
        self.put(ins[("B", "RGBA")], b)
        return [s for s in m.outputs if s.type == "RGBA"][0]

    def mul(self, a, b):
        m = self.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY", clamp_factor=True)
        ins = {(s.name, s.type): s for s in m.inputs}
        self.put(ins[("Factor", "VALUE")], 1.0)
        self.put(ins[("A", "RGBA")], a)
        self.put(ins[("B", "RGBA")], b)
        return [s for s in m.outputs if s.type == "RGBA"][0]

    def ramp(self, fac, stops, interp="LINEAR"):
        r = self.n("ShaderNodeValToRGB")
        r.color_ramp.interpolation = interp
        els = r.color_ramp.elements
        while len(els) > 1:
            els.remove(els[-1])
        els[0].position = stops[0][0]
        els[0].color = (*stops[0][1], 1.0)
        for pos, col in stops[1:]:
            e = els.new(pos)
            e.color = (*col, 1.0)
        self.put(r.inputs["Fac"], fac)
        return r.outputs["Color"]

    def attr(self, name):
        a = self.n("ShaderNodeAttribute", attribute_name=name)
        return a.outputs["Fac"]

    def smooth(self, lo, hi, x):
        """smoothstep(lo, hi, x) with Map Range (smoothstep interpolation)."""
        m = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        self.put(m.inputs["Value"], x)
        m.inputs["From Min"].default_value = lo
        m.inputs["From Max"].default_value = hi
        return m.outputs["Result"]

    def gauss(self, x, centre, width):
        d = self.math("SUBTRACT", x, centre)
        d = self.math("DIVIDE", d, width)
        d = self.math("MULTIPLY", d, d)
        d = self.math("MULTIPLY", d, -1.0)
        return self.math("EXPONENT", d)

    def voronoi(self, vec, scale, feature="F1", randomness=1.0):
        v = self.n("ShaderNodeTexVoronoi", feature=feature, distance="EUCLIDEAN", voronoi_dimensions="3D")
        self.put(v.inputs["Vector"], vec)
        v.inputs["Scale"].default_value = scale
        v.inputs["Randomness"].default_value = randomness
        return v

    def noise(self, vec, scale, detail=2.0):
        nz = self.n("ShaderNodeTexNoise")
        self.put(nz.inputs["Vector"], vec)
        nz.inputs["Scale"].default_value = scale
        nz.inputs["Detail"].default_value = detail
        return nz.outputs["Fac"]

    def mapping(self, vec, scale=(1, 1, 1), loc=(0, 0, 0)):
        m = self.n("ShaderNodeMapping")
        self.put(m.inputs["Vector"], vec)
        m.inputs["Scale"].default_value = scale
        m.inputs["Location"].default_value = loc
        return m.outputs["Vector"]


def build_fish_material(name, P):
    """One Cycles material for body + fins + eyes selected by the `region` attribute. Returns
    (material, image_node, alpha_socket, colour_socket)."""
    pat = P["pattern"]
    L = P["length_m"]
    mat = bpy.data.materials.new(f"FishSkin_{name}")
    mat.use_nodes = True
    tree = mat.node_tree
    for nd in list(tree.nodes):
        tree.nodes.remove(nd)
    nb = NB(tree)
    coord = nb.n("ShaderNodeTexCoord")
    obj_co = coord.outputs["Object"]
    ux, vz, region, fid, fr, fs, ray, eyea = (nb.attr(a) for a in ATTRS)
    h = nb.math("MULTIPLY_ADD", vz, 0.5, 0.5)                      # 0 belly .. 1 back

    # ---- body: countershading
    body = nb.ramp(h, [(pat["belly_pos"], pat["belly"]), (pat["side_pos"], pat["side"]),
                       (pat["back_pos"], pat["back"])])
    # subtle large-scale mottling so the gradient is not plastic
    mott = nb.noise(nb.mapping(obj_co, scale=(1, 1, 1)), 18.0 / L * 0.4, 3.0)
    mott = nb.math("MULTIPLY_ADD", mott, 0.30, 0.85)
    body = nb.mul(body, shade_to_col(nb, mott))
    # lateral band / cheek
    if pat.get("band"):
        bm_ = nb.gauss(vz, pat["band_vz"], pat["band_w"])
        rng = nb.math("MULTIPLY", nb.smooth(pat["band_ux"][0], pat["band_ux"][0] + 0.08, ux),
                      nb.smooth(pat["band_ux"][1], pat["band_ux"][1] - 0.06, ux))
        bm_ = nb.math("MULTIPLY", nb.math("MULTIPLY", bm_, rng), pat["band_strength"])
        body = nb.mix(bm_, body, pat["band"])
    head_end = P["head_len"] * (1.0 - P["tail_len"])
    if pat.get("cheek"):
        cm = nb.math("MULTIPLY", nb.smooth(head_end, head_end - 0.05, ux),
                     nb.smooth(0.03, 0.08, ux))
        cm = nb.math("MULTIPLY", cm, nb.gauss(vz, -0.05, 0.55))
        cm = nb.math("MULTIPLY", cm, pat["cheek_strength"])
        body = nb.mix(cm, body, pat["cheek"])
    # perch bars
    if pat.get("bars"):
        nzb = nb.noise(obj_co, 30.0 / L * 0.4, 2.0)
        phase = nb.math("MULTIPLY_ADD", ux, pat["bars"] * math.pi / (pat["bar_ux"][1] - pat["bar_ux"][0]),
                        -pat["bar_ux"][0] * pat["bars"] * math.pi / (pat["bar_ux"][1] - pat["bar_ux"][0]))
        phase = nb.math("ADD", phase, nb.math("MULTIPLY_ADD", nzb, 0.6, -0.30))
        bar = nb.math("SINE", phase)
        bar = nb.math("MULTIPLY", bar, bar)
        # wedge: thinner towards the belly
        thr = nb.math("MULTIPLY_ADD", h, -0.35, 1.0 - pat["bar_width"])
        bar = nb.smooth(0.0, 0.25, nb.math("SUBTRACT", bar, thr))
        bar = nb.math("MULTIPLY", bar, nb.smooth(pat["bar_floor"], pat["bar_floor"] + 0.45, vz))
        bar = nb.math("MULTIPLY", bar, nb.math("MULTIPLY", nb.smooth(pat["bar_ux"][0] - 0.03, pat["bar_ux"][0] + 0.03, ux),
                                                 nb.smooth(pat["bar_ux"][1] + 0.03, pat["bar_ux"][1] - 0.03, ux)))
        bar = nb.math("MULTIPLY", bar, pat["bar_strength"])
        body = nb.mix(bar, body, pat["bar_colour"])
    # spots (voronoi cells thresholded, random subset of cells, masked to the back)
    spot_mask = None
    if pat.get("spots"):
        vec = nb.mapping(obj_co, scale=pat["spot_aniso"])
        vor = nb.voronoi(vec, 1.0 / pat["spot_cell_m"], randomness=pat.get("spot_random", 1.0))
        sep = nb.n("ShaderNodeSeparateColor")
        nb.put(sep.inputs[0], vor.outputs["Color"])
        pick = nb.smooth(pat["spot_density"] + 0.02, pat["spot_density"] - 0.02, sep.outputs[0])   # cell R < density
        edge = nb.smooth(pat["spot_size"] + 0.05, pat["spot_size"] - 0.02, vor.outputs["Distance"])
        spot_mask = nb.math("MULTIPLY", pick, edge)
        back_m = nb.smooth(pat["spot_floor"], pat["spot_floor"] + 0.35, vz)
        body_spots = nb.math("MULTIPLY", spot_mask, back_m)
        body_spots = nb.math("MULTIPLY", body_spots, nb.smooth(0.05, 0.12, ux))
        body = nb.mix(body_spots, body, pat["spots"])
    # scales: distance-to-edge darkening + per-cell brightness variation
    svec = nb.n("ShaderNodeMapping")
    nb.put(svec.inputs["Vector"], obj_co)
    svec.inputs["Rotation"].default_value = (0.0, math.radians(45.0), 0.0)
    svec.inputs["Scale"].default_value = (1.0, 1.6, 1.0)
    svec = svec.outputs["Vector"]
    sv = nb.voronoi(svec, 1.0 / pat["scale_cell_m"], feature="DISTANCE_TO_EDGE", randomness=0.2)
    sedge = nb.smooth(0.07, 0.0, sv.outputs["Distance"])
    scv = nb.voronoi(svec, 1.0 / pat["scale_cell_m"], feature="F1", randomness=0.2)
    scsep = nb.n("ShaderNodeSeparateColor")
    nb.put(scsep.inputs[0], scv.outputs["Color"])
    cellvar = nb.math("MULTIPLY_ADD", scsep.outputs[0], 2.0 * pat["scale_var"], 1.0 - pat["scale_var"])
    cup = nb.smooth(0.15, 0.62, scv.outputs["Distance"])             # darker towards the scale rim
    shade = nb.math("MULTIPLY", cellvar, nb.math("MULTIPLY_ADD", sedge, -0.6 * pat["scale_strength"], 1.0))
    shade = nb.math("MULTIPLY", shade, nb.math("MULTIPLY_ADD", cup, -1.0 * pat["scale_strength"], 1.0))
    # no scales on the head
    shade = nb.mix(nb.smooth(head_end + 0.03, head_end - 0.02, ux), shade_to_col(nb, shade), (1, 1, 1))
    body = nb.mul(body, shade)
    # mouth line and gill line (painted)
    mouth = nb.math("MULTIPLY", nb.gauss(vz, pat["mouth_vz"], 0.10),
                    nb.smooth(pat["mouth_len"] * head_end, pat["mouth_len"] * head_end - 0.03, ux))
    mouth = nb.math("MULTIPLY", mouth, 0.8)
    body = nb.mix(mouth, body, (0.06, 0.04, 0.03))
    gill_x = nb.math("MULTIPLY_ADD", nb.math("MULTIPLY", vz, vz), -P["gill_bulge"] * 0.9, head_end + P["gill_bulge"] * 0.9)
    gill = nb.gauss(ux, gill_x, 0.0075)
    gill = nb.math("MULTIPLY", gill, nb.smooth(-0.85, -0.5, vz))
    gill = nb.math("MULTIPLY", gill, pat["gill_dark"])
    body = nb.mix(gill, body, (0.05, 0.05, 0.04))
    # eye socket shadow ring
    socket = nb.gauss(ux, P["eye_t"] * P["head_len"] * (1.0 - P["tail_len"]), 0.028)
    socket = nb.math("MULTIPLY", socket, nb.gauss(vz, P["eye_z"], 0.22))
    body = nb.mix(nb.math("MULTIPLY", socket, 0.35), body, (0.10, 0.09, 0.06))

    # ---- fins: colour per kind (constant ramp on fid/7), rays, tip, dark edge, optional spots/blotches
    stops = []
    for k, i in FIN_ID.items():
        col = pat["fins"].get(k, pat["fins"].get("dorsal", (0.5, 0.5, 0.5)))
        stops.append((i / len(FIN_KINDS), col))
    fin = nb.ramp(nb.math("DIVIDE", fid, float(len(FIN_KINDS))), stops, interp="CONSTANT")
    rayv = nb.math("SINE", nb.math("MULTIPLY", ray, math.pi))
    rayv = nb.math("MULTIPLY", rayv, rayv)
    rayv = nb.math("MULTIPLY", nb.smooth(0.45, 0.95, rayv), pat["fin_ray_dark"])
    rayv = nb.math("MULTIPLY", rayv, nb.smooth(0.08, 0.3, fr))
    fin = nb.mix(rayv, fin, (0.08, 0.08, 0.06))
    tip = nb.math("MULTIPLY", nb.smooth(0.55, 0.95, fr), pat["fin_tip_strength"])
    fin = nb.mix(tip, fin, pat["fin_tip"])
    edge = nb.math("MULTIPLY", nb.smooth(0.82, 1.0, fr), pat["fin_edge_dark"])
    fin = nb.mix(edge, fin, (0.06, 0.06, 0.05))
    if spot_mask is not None and pat.get("spot_fins"):
        sel = None
        for k in pat["spot_fins"]:
            g = nb.gauss(fid, float(FIN_ID[k]), 0.3)
            sel = g if sel is None else nb.math("ADD", sel, g)
        fin = nb.mix(nb.math("MULTIPLY", spot_mask, sel), fin, pat["spots"])
    if pat.get("fin_blotch"):
        bvor = nb.voronoi(obj_co, 1.0 / pat["fin_blotch_cell_m"])
        bsep = nb.n("ShaderNodeSeparateColor")
        nb.put(bsep.inputs[0], bvor.outputs["Color"])
        bl = nb.math("MULTIPLY", nb.smooth(0.55, 0.5, bsep.outputs[0]), nb.smooth(0.42, 0.30, bvor.outputs["Distance"]))
        fin = nb.mix(nb.math("MULTIPLY", bl, 0.8), fin, pat["fin_blotch"])
    if pat.get("dorsal_spot"):
        ds = nb.math("MULTIPLY", nb.gauss(fid, float(FIN_ID["dorsal"]), 0.3),
                     nb.math("MULTIPLY", nb.smooth(0.62, 0.80, fs), nb.smooth(0.12, 0.35, fr)))
        fin = nb.mix(nb.math("MULTIPLY", ds, 0.9), fin, (0.04, 0.04, 0.03))

    # ---- eye: pupil, iris, dark rim
    eye = nb.ramp(eyea, [(0.0, pat["pupil"]), (0.30, pat["pupil"]), (0.36, pat["iris"]),
                         (0.70, tuple(c * 0.75 for c in pat["iris"])), (0.86, (0.08, 0.07, 0.05)),
                         (1.0, (0.12, 0.12, 0.10))])

    col = nb.mix(nb.smooth(0.5, 0.6, region), body, fin)
    col = nb.mix(nb.smooth(1.5, 1.6, region), col, eye)

    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    nb.put(bsdf.inputs["Base Color"], col)
    bsdf.inputs["Roughness"].default_value = 0.35
    out = nb.n("ShaderNodeOutputMaterial")
    nb.links.new(bsdf.outputs[0], out.inputs[0])
    # alpha mask (fins 0.85, rest 1) for the EMIT bake
    alpha = nb.math("MULTIPLY_ADD", nb.smooth(0.5, 0.6, nb.math("MULTIPLY", region, nb.smooth(1.6, 1.5, region))), -0.15, 1.0)
    img_node = nb.n("ShaderNodeTexImage")
    tree.nodes.active = img_node
    return mat, img_node, alpha, col, bsdf, out


def shade_to_col(nb, f):
    c = nb.n("ShaderNodeCombineColor")
    nb.put(c.inputs[0], f)
    nb.put(c.inputs[1], f)
    nb.put(c.inputs[2], f)
    return c.outputs[0]


# ----------------------------------------------------------------------------------------------
# BAKE
# ----------------------------------------------------------------------------------------------
def bake_material(obj, mat, img_node, alpha_sock, col_sock, bsdf, out_node, png_path, size=ATLAS):
    """Bake DIFFUSE colour, then an EMIT alpha mask, combine, save PNG. Returns the image."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.margin = 8
    scene.render.bake.use_clear = True
    for o in scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    img = bpy.data.images.new(os.path.basename(png_path), size, size, alpha=True)
    img_node.image = img
    mat.node_tree.nodes.active = img_node
    t = time.time()
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=8, use_clear=True)
    log(f"bake diffuse {size}x{size}: {time.time() - t:.1f}s")

    # alpha: emit the mask into a second (linear) image
    amask = bpy.data.images.new("alpha_mask", size, size, alpha=False)
    amask.colorspace_settings.name = "Non-Color"
    emit = mat.node_tree.nodes.new("ShaderNodeEmission")
    tree = mat.node_tree
    tree.links.new(alpha_sock, emit.inputs["Color"])
    tree.links.new(emit.outputs[0], out_node.inputs[0])
    img_node.image = amask
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
    tree.links.new(bsdf.outputs[0], out_node.inputs[0])
    tree.nodes.remove(emit)

    rgba = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(rgba)
    am = np.empty(size * size * 4, dtype=np.float32)
    amask.pixels.foreach_get(am)
    rgba[3::4] = np.clip(am[0::4], 0.0, 1.0)
    img.pixels.foreach_set(rgba)
    img.update()
    img.filepath_raw = png_path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(amask)
    img_node.image = img
    return img


def make_textured_material(name, png_path, roughness=0.35, alpha=True):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(png_path, check_existing=False)
    tex.image.alpha_mode = "STRAIGHT"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.5
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.15
    mat.diffuse_color = (0.6, 0.6, 0.6, 1.0)
    return mat


# ----------------------------------------------------------------------------------------------
# FISH ASSEMBLY
# ----------------------------------------------------------------------------------------------
def tri_count(me):
    return sum(max(0, len(p.vertices) - 2) for p in me.polygons)


def build_fish(name, P, textures_dir):
    """Builds the whole fish as ONE mesh object with one baked material. Returns (obj, info)."""
    L = P["length_m"]
    scene = bpy.context.scene
    # 1. body as its own object (for the subdiv + unwrap)
    bm = bmesh.new()
    lay = attr_layers(bm)
    rings, body_faces = build_body(P, lay, bm)
    me = bpy.data.meshes.new(f"fish_{name}_body")
    bm.to_mesh(me)
    bm.free()
    me.update()
    body = bpy.data.objects.new(f"fish_{name}_body", me)
    scene.collection.objects.link(body)
    me.uv_layers.new(name="UVMap")
    me.shade_smooth()
    body_idx = set(range(len(me.polygons)))
    unwrap_body(body, body_idx)
    base_tris = tri_count(me)
    # fins + eyes in a second bmesh (same attribute layers), then joined
    bm2 = bmesh.new()
    lay2 = attr_layers(bm2)
    uvs = {}
    rects = fin_rects(P["fins"])
    for fin in P["fins"]:
        k = fin["kind"]
        if k in ("dorsal", "dorsal2", "adipose", "anal"):
            add_median_fin(bm2, lay2, P, fin, rects[k], uvs)
        elif k == "caudal":
            add_caudal(bm2, lay2, P, fin, rects[k], uvs)
        elif k in ("pectoral", "pelvic"):
            add_paddle(bm2, lay2, P, fin, +1.0, rects[k + "_L"], uvs)
            add_paddle(bm2, lay2, P, fin, -1.0, rects[k + "_R"], uvs)
    add_eye(bm2, lay2, P, +1.0, rects["eye_L"], uvs)
    add_eye(bm2, lay2, P, -1.0, rects["eye_R"], uvs)
    if P.get("barbels"):
        add_barbels(bm2, lay2, P, uvs, rects["barbel"])
    uv_lay = bm2.loops.layers.uv.new("UVMap")
    for f, byvert in uvs.items():
        for loop in f.loops:
            loop[uv_lay].uv = byvert[loop.vert]
    me2 = bpy.data.meshes.new(f"fish_{name}_fins")
    bm2.to_mesh(me2)
    bm2.free()
    me2.update()
    me2.shade_smooth()
    fins = bpy.data.objects.new(f"fish_{name}_fins", me2)
    scene.collection.objects.link(fins)
    fin_tris = tri_count(me2)

    # 2. subdivide the body once if it fits the budget
    subdiv_used = False
    if P.get("subdiv") and base_tris * 4 + fin_tris <= BUDGET["fish_max"]:
        mod = body.modifiers.new("subd", "SUBSURF")
        mod.levels = 1
        mod.render_levels = 1
        mod.uv_smooth = "PRESERVE_BOUNDARIES"
        for o in scene.objects:
            o.select_set(False)
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.modifier_apply(modifier="subd")
        subdiv_used = True
        me.shade_smooth()
    # 3. join into one object
    for o in scene.objects:
        o.select_set(False)
    body.select_set(True)
    fins.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    obj = body
    obj.name = f"fish_{name}"
    obj.data.name = f"fish_{name}"
    # re-mark the gill ring sharp edges survived the join; shade smooth everywhere
    obj.data.shade_smooth()
    tris = tri_count(obj.data)

    # 4. procedural material + bake
    mat, img_node, alpha_sock, col_sock, bsdf, out_node = build_fish_material(name, P)
    obj.data.materials.append(mat)
    png = os.path.join(textures_dir, f"fish_{name}_diffuse.png")
    bake_material(obj, mat, img_node, alpha_sock, col_sock, bsdf, out_node, png)
    # 5. swap to the image material for export + preview
    tex_mat = make_textured_material(f"FishSkin_{name}", png)
    obj.data.materials.clear()
    obj.data.materials.append(tex_mat)
    bpy.data.materials.remove(mat)
    info = dict(triangles=tris, subdiv=subdiv_used, body_tris_before_subdiv=base_tris, fin_eye_tris=fin_tris,
                texture=png)
    return obj, info


# ----------------------------------------------------------------------------------------------
# RIG (trout)
# ----------------------------------------------------------------------------------------------
BONE_NAMES = ["head", "body1", "body2", "body3", "body4", "peduncle", "tail"]


def add_armature(obj, P):
    """7 bones along the spine, root at the mouth, auto weights; zero-weight verts get x-based weights."""
    L = P["length_m"]
    Lb = body_len(P)
    scene = bpy.context.scene
    arm = bpy.data.armatures.new(f"{obj.name}_rig")
    armob = bpy.data.objects.new(f"{obj.name}_rig", arm)
    scene.collection.objects.link(armob)
    bpy.context.view_layer.objects.active = armob
    bpy.ops.object.mode_set(mode="EDIT")
    hl = P["head_len"]
    cuts = [0.0, hl, hl + (0.78 - hl) * 0.25, hl + (0.78 - hl) * 0.5, hl + (0.78 - hl) * 0.75, 0.78, 1.0,
            L / Lb]                                              # t of the body length; last = tail tip
    prev = None
    for i, bname in enumerate(BONE_NAMES):
        t0, t1 = cuts[i], cuts[i + 1]
        z0 = 0.5 * sum(section(P, min(1.0, t0))[:2])
        z1 = 0.5 * sum(section(P, min(1.0, t1))[:2])
        b = arm.edit_bones.new(bname)
        b.head = (-t0 * Lb, 0.0, z0)
        b.tail = (-t1 * Lb, 0.0, z1)
        if prev is not None:
            b.parent = prev
            b.use_connect = True
        prev = b
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in scene.objects:
        o.select_set(False)
    obj.select_set(True)
    armob.select_set(True)
    bpy.context.view_layer.objects.active = armob
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # fallback for vertices the heat solver left unweighted (fins are separate shells)
    me = obj.data
    groups = {vg.name: vg for vg in obj.vertex_groups}
    fixed = 0
    for v in me.vertices:
        if sum(g.weight for g in v.groups) < 1e-4:
            t = -v.co.x / Lb
            for i, bname in enumerate(BONE_NAMES):
                t0, t1 = cuts[i], cuts[i + 1]
                mid = 0.5 * (t0 + t1)
                w = max(0.0, 1.0 - abs(t - mid) / (t1 - t0))
                if w > 0:
                    groups[bname].add([v.index], w, "REPLACE")
            fixed += 1
    if fixed:
        log(f"rig: {fixed} vertices weighted by x-distance fallback")
    return armob


# ----------------------------------------------------------------------------------------------
# PREVIEW SCENE
# ----------------------------------------------------------------------------------------------
def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def studio(scene, objs, view_dir, samples, ortho_scale=None, ground=True, up=None, lens=65.0, frame=None):
    """3-point rig (key sun, fill area, rim), soft ground, blue-grey world, camera framing."""
    lo, hi = bounds(objs)
    glo = lo
    if frame is not None:
        lo, hi = Vector(frame[0]), Vector(frame[1])
    centre = 0.5 * (lo + hi)
    radius = 0.5 * (hi - lo).length
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.42, 0.47, 0.54, 1.0)
    bg.inputs["Strength"].default_value = 0.6
    scene.world = world
    if ground:
        gm = bpy.data.meshes.new("Ground")
        gb = bmesh.new()
        s = 12.0 * radius + 20.0
        zg = glo.z - 0.04 * radius
        gb.faces.new([gb.verts.new(v) for v in ((-s, -s, zg), (s, -s, zg), (s, s, zg), (-s, s, zg))])
        gb.to_mesh(gm)
        gb.free()
        gmat = bpy.data.materials.new("GroundMat")
        gmat.use_nodes = True
        gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.40, 0.42, 0.45, 1.0)
        gmat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
        gm.materials.append(gmat)
        g = bpy.data.objects.new("Ground", gm)
        scene.collection.objects.link(g)

    def light(name, kind, from_dir, energy, colour, size=None):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = colour
        if kind == "SUN":
            ld.angle = math.radians(6.0)
        if kind == "AREA":
            ld.shape = "RECTANGLE"
            ld.size = size
            ld.size_y = size * 0.6
        lo_ = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo_)
        d = Vector(from_dir).normalized()
        lo_.location = centre + d * (6.0 * radius)
        lo_.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()

    light("Key", "SUN", (0.5, -0.7, 1.0), 4.5, (1.0, 0.97, 0.92))
    light("Fill", "AREA", (-0.4, -1.0, 0.5), 130.0 * radius * radius, (0.85, 0.92, 1.0), size=6.0 * radius)
    light("Rim", "AREA", (-0.8, 0.9, 0.7), 180.0 * radius * radius, (1.0, 0.95, 0.9), size=4.0 * radius)

    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = lens
    cam_d.clip_start = 0.001
    cam_d.clip_end = 200.0
    cam = bpy.data.objects.new("Cam", cam_d)
    scene.collection.objects.link(cam)
    direction = Vector(view_dir).normalized()
    if ortho_scale:
        cam_d.type = "ORTHO"
        cam_d.ortho_scale = ortho_scale
        dist = 10.0 * radius + 1.0
    else:
        hfov = 2.0 * math.atan(cam_d.sensor_width / (2.0 * cam_d.lens))
        dist = radius / math.sin(hfov * 0.5) * 0.92
    cam.location = centre + direction * dist
    up = up or (Vector((1.0, 0.0, 0.0)) if abs(direction.z) > 0.9 else Vector((0.0, 0.0, 1.0)))
    z_axis = direction
    x_axis = up.cross(z_axis).normalized()
    y_axis = z_axis.cross(x_axis)
    cam.rotation_euler = Matrix((x_axis, y_axis, z_axis)).transposed().to_euler()
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = RENDER["res_x"]
    scene.render.resolution_y = RENDER["res_y"]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Punchy"
    except TypeError:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0


def render_to(scene, path_abs):
    scene.render.filepath = path_abs
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as exc:                                     # denoiser missing etc.
        log(f"render with denoise failed ({exc}); retrying without")
        scene.cycles.use_denoising = False
        bpy.ops.render.render(write_still=True)


def clear_studio(scene, keep):
    for o in list(scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)


# ----------------------------------------------------------------------------------------------
# EXPORT
# ----------------------------------------------------------------------------------------------
def export_fbx(scene, objs, path_abs):
    for o in scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.fbx(
        filepath=path_abs, use_selection=True, object_types={"MESH", "ARMATURE"},
        axis_forward="-Z", axis_up="Y", bake_space_transform=True,
        global_scale=1.0, apply_unit_scale=True, apply_scale_options="FBX_SCALE_NONE",
        use_mesh_modifiers=True, mesh_smooth_type="OFF", use_triangles=True,
        add_leaf_bones=False, path_mode="COPY", embed_textures=True,
    )


# ----------------------------------------------------------------------------------------------
# DRIVER
# ----------------------------------------------------------------------------------------------
def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


def generate_fish(name, P, exports, previews, views, do_fbx, do_render, final):
    scene = new_scene()
    t0 = time.time()
    obj, info = build_fish(name, P, exports)
    dims = tuple(round(v, 4) for v in obj.dimensions)
    log(f"{name}: {info['triangles']} tris (body {info['body_tris_before_subdiv']} x4 subdiv={info['subdiv']}, "
        f"fins+eyes {info['fin_eye_tris']}), dims {dims}, built in {time.time() - t0:.1f}s")
    pngs = []
    if do_render:
        samples = RENDER["samples_final"] if final else RENDER["samples_preview"]
        for vk in views:
            clear_studio(scene, {obj})
            studio(scene, [obj], VIEW_DIRS[vk], samples)
            png = os.path.join(previews, f"fish_{name}_{vk}.png")
            t1 = time.time()
            render_to(scene, png)
            log(f"{name}: rendered {vk} in {time.time() - t1:.1f}s -> {png}")
            pngs.append(png)
        clear_studio(scene, {obj})
    fbx = None
    rigged = None
    bones = []
    if do_fbx:
        fbx = os.path.join(exports, f"fish_{name}.fbx")
        export_fbx(scene, [obj], fbx)
        if name == "trout":
            armob = add_armature(obj, P)
            bones = BONE_NAMES[:]
            rigged = os.path.join(exports, f"fish_{name}_rigged.fbx")
            export_fbx(scene, [obj, armob], rigged)
    return dict(
        preset=name, kind="fish", length_m=P["length_m"], triangles=info["triangles"],
        subdiv_applied=info["subdiv"], dimensions_m=list(dims),
        rings=P["rings"], sides=P["sides"], textures=[info["texture"]],
        fbx=fbx, fbx_rigged=rigged, bones=bones, previews=pngs,
        forward_axis="FBX +X (Roblox RightVector)",
    )


# ----------------------------------------------------------------------------------------------
# PROPS: rod and reel, dock, trader stall (one baked material each, region attribute -> colour)
# ----------------------------------------------------------------------------------------------
PROP_REGIONS = ["wood", "metal", "canvas", "cork", "graphite", "dark", "crate", "rope", "piling", "sign"]
PR = {k: float(i) for i, k in enumerate(PROP_REGIONS)}


class PropBuilder:
    """bmesh helpers that tag every vertex with a region id and keep cylinder sides smooth."""

    def __init__(self):
        self.bm = bmesh.new()
        self.lay = self.bm.verts.layers.float.new("region")
        self.vz = self.bm.verts.layers.float.new("vz")     # unused by props, keeps the attr set uniform

    def _tag(self, verts, region):
        faces = set()
        for v in verts:
            v[self.lay] = PR[region]
            faces.update(v.link_faces)
        return faces

    def box(self, centre, size, region, rot=None):
        mtx = Matrix.Translation(Vector(centre))
        if rot is not None:
            mtx = mtx @ rot
        mtx = mtx @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mtx)
        faces = self._tag(res["verts"], region)
        for f in faces:
            f.smooth = False
        return faces

    def cyl(self, p0, p1, r0, r1=None, region="metal", segs=12, caps=True):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        length = d.length
        mtx = Matrix.Translation(0.5 * (p0 + p1)) @ d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r0,
                                    radius2=r0 if r1 is None else r1, depth=length, matrix=mtx)
        faces = self._tag(res["verts"], region)
        for f in faces:
            f.smooth = len(f.verts) == 4            # sides smooth, caps flat
        return faces

    def torus(self, centre, axis, R, r, region="metal", segs=10, rings=6, arc=2.0 * math.pi, closed=True):
        centre = Vector(centre)
        rot = Vector(axis).normalized().to_track_quat("Z", "Y").to_matrix()
        grid = []
        n = segs if closed else segs + 1
        for i in range(n):
            a = arc * i / segs
            ring = []
            for j in range(rings):
                b = 2.0 * math.pi * j / rings
                p = Vector(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
                v = self.bm.verts.new(centre + rot @ p)
                v[self.lay] = PR[region]
                ring.append(v)
            grid.append(ring)
        faces = []
        m = segs if closed else segs
        for i in range(m):
            a, b = grid[i], grid[(i + 1) % n]
            for j in range(rings):
                f = self.bm.faces.new((a[j], a[(j + 1) % rings], b[(j + 1) % rings], b[j]))
                f.smooth = True
                faces.append(f)
        return faces

    def loft(self, stations, region_fn, segs=10):
        """stations: list of (x, radius, region) along +X; duplicate x with different radius = hard step."""
        rings = []
        for x, r, region in stations:
            ring = []
            for j in range(segs):
                a = 2.0 * math.pi * j / segs
                v = self.bm.verts.new((x, r * math.cos(a), r * math.sin(a)))
                v[self.lay] = PR[region]
                ring.append(v)
            rings.append(ring)
        faces = []
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            for j in range(segs):
                f = self.bm.faces.new((a[j], b[j], b[(j + 1) % segs], a[(j + 1) % segs]))
                f.smooth = stations[i][0] != stations[i + 1][0]
                faces.append(f)
        for ring, flip in ((rings[0], False), (rings[-1], True)):
            f = self.bm.faces.new(ring if flip else list(reversed(ring)))
            f.smooth = False
            faces.append(f)
        return faces

    def finish(self, name):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for e in bm.edges:
            if any(not f.smooth for f in e.link_faces):
                e.smooth = False
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.update()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def build_rod(name):
    b = PropBuilder()
    Lr = 2.1
    # shaft: butt cap, rear cork grip, reel seat, fore grip, tapered blank
    st = [(0.0, 0.012, "dark"), (0.02, 0.012, "dark"), (0.02, 0.013, "cork"), (0.26, 0.013, "cork"),
          (0.26, 0.011, "graphite"), (0.30, 0.011, "graphite"), (0.30, 0.0125, "metal"), (0.32, 0.0125, "metal"),
          (0.32, 0.011, "graphite"), (0.44, 0.011, "graphite"), (0.44, 0.0125, "metal"), (0.46, 0.0125, "metal"),
          (0.46, 0.012, "cork"), (0.58, 0.012, "cork"), (0.58, 0.0075, "graphite"), (0.80, 0.0062, "graphite"),
          (1.05, 0.0050, "graphite"), (1.30, 0.0040, "graphite"), (1.55, 0.0031, "graphite"),
          (1.80, 0.0023, "graphite"), (2.0, 0.0018, "graphite"), (Lr, 0.0015, "graphite")]
    b.loft(st, None, segs=10)

    def blank_r(x):
        for (x0, r0, _), (x1, r1, _) in zip(st, st[1:]):
            if x0 <= x <= x1 and x1 > x0:
                return r0 + (r1 - r0) * (x - x0) / (x1 - x0)
        return 0.0015

    # 6 line guides (tori hanging under the blank) with feet, plus the tip top
    guides = [(0.72, 0.020), (0.98, 0.015), (1.24, 0.011), (1.50, 0.008), (1.74, 0.0065), (1.94, 0.0055)]
    for x, R in guides:
        rb = blank_r(x)
        zc = -(rb + 0.004 + R)
        b.torus((x, 0.0, zc), (1.0, 0.0, 0.0), R, 0.0011, "metal", segs=10, rings=5)
        b.box((x, 0.0, -(rb + 0.002)), (0.03, 0.004, 0.004), "dark")                 # foot wrap
        b.cyl((x, 0.0, -(rb + 0.002)), (x, 0.0, zc + R), 0.0012, None, "metal", segs=6)   # frame leg
    rb = blank_r(Lr)
    b.torus((Lr, 0.0, -(rb + 0.0045)), (1.0, 0.0, 0.0), 0.0045, 0.0009, "metal", segs=10, rings=5)
    b.cyl((Lr - 0.012, 0.0, 0.0), (Lr - 0.012, 0.0, -(rb + 0.002)), 0.0012, None, "metal", segs=6)

    # spinning reel on the seat (x 0.32..0.44): foot, stem, body, rotor/spool, bail, handle
    xr = 0.38
    b.box((xr, 0.0, -0.013), (0.075, 0.012, 0.004), "dark")                           # reel foot
    b.cyl((xr, 0.0, -0.015), (xr, 0.0, -0.055), 0.006, 0.009, "dark", segs=8)         # stem
    b.cyl((xr - 0.018, 0.0, -0.072), (xr + 0.022, 0.0, -0.072), 0.023, None, "dark", segs=14)  # gear body
    b.cyl((xr + 0.022, 0.0, -0.072), (xr + 0.036, 0.0, -0.072), 0.020, None, "graphite", segs=14)  # rotor
    b.cyl((xr + 0.036, 0.0, -0.072), (xr + 0.070, 0.0, -0.072), 0.018, None, "metal", segs=14)  # spool
    b.cyl((xr + 0.040, 0.0, -0.072), (xr + 0.066, 0.0, -0.072), 0.0185, None, "rope", segs=14)  # line on spool
    b.cyl((xr + 0.070, 0.0, -0.072), (xr + 0.076, 0.0, -0.072), 0.012, None, "dark", segs=10)  # spool cap
    # bail arm: half torus around the spool
    b.torus((xr + 0.050, 0.0, -0.072), (1.0, 0.0, 0.0), 0.026, 0.0015, "metal", segs=9, rings=5,
            arc=math.pi, closed=False)
    b.cyl((xr + 0.036, 0.026, -0.072), (xr + 0.050, 0.026, -0.072), 0.003, None, "dark", segs=6)  # bail pivots
    b.cyl((xr + 0.036, -0.026, -0.072), (xr + 0.050, -0.026, -0.072), 0.003, None, "dark", segs=6)
    # handle: shaft out of the body side (+Y), crank arm, knob
    b.cyl((xr, 0.023, -0.072), (xr, 0.040, -0.072), 0.004, None, "metal", segs=8)
    b.box((xr, 0.042, -0.055), (0.008, 0.004, 0.040), "dark")
    b.cyl((xr, 0.040, -0.038), (xr, 0.062, -0.038), 0.0035, None, "metal", segs=6)
    b.cyl((xr, 0.052, -0.038), (xr, 0.072, -0.038), 0.008, 0.007, "cork", segs=10)
    obj = b.finish(name)
    return obj


def build_dock(name):
    b = PropBuilder()
    Ld, Wd = 6.0, 2.0
    deck_top = 0.75
    plank_w, gap, plank_t = 0.14, 0.02, 0.05
    # pilings: 2.2 m tall, 1.5 m under water (water = z 0), tops at 0.70 under the planks
    px = [0.45, 3.0, 5.55]
    for x in px:
        for y in (-0.85, 0.85):
            b.cyl((x, y, -1.5), (x, y, 0.70), 0.15, None, "piling", segs=12)
        b.box((x, 0.0, 0.46), (0.16, Wd - 0.10, 0.16), "wood")                 # cross bearer bolted to the pilings
    for y in (-0.66, 0.66):
        b.box((Ld * 0.5, y, 0.62), (Ld, 0.12, 0.16), "wood")                   # stringers under the planks
    n = int((Ld + gap) // (plank_w + gap))
    x = 0.0
    for i in range(n):
        b.box((x + plank_w * 0.5, 0.0, deck_top - plank_t * 0.5), (plank_w, Wd, plank_t), "wood")
        x += plank_w + gap
    # mooring cleat near the far end, starboard side
    cx, cy = 5.3, 0.75
    b.box((cx, cy, deck_top + 0.01), (0.22, 0.09, 0.02), "metal")
    b.cyl((cx - 0.05, cy, deck_top + 0.02), (cx - 0.05, cy, deck_top + 0.075), 0.016, None, "metal", segs=8)
    b.cyl((cx + 0.05, cy, deck_top + 0.02), (cx + 0.05, cy, deck_top + 0.075), 0.016, None, "metal", segs=8)
    b.cyl((cx - 0.16, cy, deck_top + 0.075), (cx + 0.16, cy, deck_top + 0.075), 0.02, None, "metal", segs=8)
    # ladder on the port side (-Y) at x = 4.0, from under water to above the deck
    lx = 4.0
    for dx in (-0.22, 0.22):
        b.cyl((lx + dx, -1.06, -0.9), (lx + dx, -1.06, 1.05), 0.022, None, "metal", segs=8)
        b.box((lx + dx, -0.93, deck_top - 0.10), (0.06, 0.26, 0.06), "metal")     # bracket to the stringer
        b.box((lx + dx, -0.93, 0.05), (0.06, 0.26, 0.06), "metal")
    for z in (-0.65, -0.30, 0.05, 0.40, 0.75):
        b.cyl((lx - 0.22, -1.06, z), (lx + 0.22, -1.06, z), 0.016, None, "metal", segs=8)
    return b.finish(name)


def build_stall(name):
    b = PropBuilder()
    # counter 2 x 0.9 x 1 (y x x x z), origin at the floor under the centre of the front edge (+X = customer side)
    b.box((-0.45, 0.0, 0.50), (0.90, 2.0, 1.0), "wood")
    b.box((-0.45, 0.0, 1.025), (1.0, 2.1, 0.05), "wood")                          # counter top overhang
    for i in range(9):                                                            # front plank grooves
        b.box((0.006, -0.95 + i * 0.2375 + 0.1, 0.50), (0.012, 0.012, 0.96), "dark")
    for y in (-1.05, 1.05):                                                       # 4 posts
        for x in (0.15, -1.05):
            b.box((x, y, 1.10), (0.08, 0.08, 2.20), "wood")
    # canopy: sloped slab, beam at the front, scalloped valance
    rot = Matrix.Rotation(math.radians(-8.0), 4, "Y")
    b.box((-0.45, 0.0, 2.24), (1.60, 2.40, 0.04), "canvas", rot=rot)
    b.box((0.28, 0.0, 2.10), (0.06, 2.30, 0.06), "wood")
    for i in range(12):
        y = -1.1 + 0.2 * i
        b.cyl((0.315, y, 2.09), (0.325, y, 2.09), 0.1, None, "canvas", segs=10, caps=True)  # scallop discs
    # hanging sign board (no text) under the front beam
    for y in (-0.33, 0.33):
        b.cyl((0.28, y, 2.07), (0.28, y, 1.84), 0.006, None, "rope", segs=6)
    b.box((0.28, 0.0, 1.70), (0.03, 0.85, 0.30), "sign")
    b.box((0.30, 0.0, 1.70), (0.004, 0.80, 0.25), "wood")
    # platform scale on the counter: base, pan, dial post, dial
    sx, sy = -0.55, 0.55
    b.box((sx, sy, 1.08), (0.36, 0.30, 0.06), "metal")
    b.cyl((sx + 0.04, sy, 1.11), (sx + 0.04, sy, 1.125), 0.14, None, "metal", segs=16)
    b.cyl((sx - 0.14, sy, 1.11), (sx - 0.14, sy, 1.42), 0.015, None, "metal", segs=8)
    b.cyl((sx - 0.14 - 0.015, sy, 1.45), (sx - 0.14 + 0.015, sy, 1.45), 0.11, None, "metal", segs=18)
    b.cyl((sx - 0.14 + 0.015, sy, 1.45), (sx - 0.14 + 0.02, sy, 1.45), 0.09, None, "sign", segs=18)
    # two fish crates: one on the counter, one on the floor at the side
    def crate(cx, cy, cz, L=0.50, W=0.36, H=0.26):
        b.box((cx, cy, cz + 0.01), (L, W, 0.02), "crate")
        for dx, dy, sx_, sy_ in ((0, W * 0.5 - 0.01, L, 0.02), (0, -W * 0.5 + 0.01, L, 0.02)):
            for k in range(3):
                b.box((cx + dx, cy + dy, cz + 0.05 + k * 0.08), (sx_, sy_, 0.055), "crate")
        for dy in (W * 0.5 - 0.01, -W * 0.5 + 0.01):
            for dx in (L * 0.5 - 0.02, -L * 0.5 + 0.02):
                b.box((cx + dx, cy + dy, cz + H * 0.5), (0.03, 0.03, H), "crate")
        for dx in (L * 0.5 - 0.01, -L * 0.5 + 0.01):
            b.box((cx + dx, cy, cz + H * 0.5), (0.02, W - 0.06, H - 0.02), "crate")
    crate(-0.45, -0.55, 1.05)
    crate(0.45, -1.35, 0.0)
    return b.finish(name)


def build_prop_material(name, P):
    """Region -> colour with procedural wood grain, canvas stripes, wet pilings. Same bake path as fish."""
    mat = bpy.data.materials.new(f"Prop_{name}")
    mat.use_nodes = True
    tree = mat.node_tree
    for nd in list(tree.nodes):
        tree.nodes.remove(nd)
    nb = NB(tree)
    coord = nb.n("ShaderNodeTexCoord")
    obj_co = coord.outputs["Object"]
    region = nb.attr("region")
    sep = nb.n("ShaderNodeSeparateXYZ")
    nb.put(sep.inputs[0], obj_co)
    # wood grain: stretched noise along the long axis, banded
    wave = nb.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Y")
    nb.put(wave.inputs["Vector"], nb.mapping(obj_co, scale=(1.0, 0.08, 1.0)))
    wave.inputs["Scale"].default_value = 18.0
    wave.inputs["Distortion"].default_value = 4.0
    wave.inputs["Detail"].default_value = 2.0
    grain = wave.outputs["Fac"]
    fine = nb.noise(nb.mapping(obj_co, scale=(1.0, 0.15, 1.0)), 40.0, 3.0)
    g = nb.math("MULTIPLY_ADD", grain, 0.35, 0.72)
    g = nb.math("MULTIPLY", g, nb.math("MULTIPLY_ADD", fine, 0.25, 0.88))
    wood = nb.ramp(g, [(0.0, (0.26, 0.17, 0.09)), (1.0, (0.60, 0.45, 0.26))])
    crate = nb.ramp(g, [(0.0, (0.52, 0.40, 0.22)), (1.0, (0.82, 0.68, 0.42))])
    sign = nb.ramp(g, [(0.0, (0.62, 0.50, 0.30)), (1.0, (0.86, 0.76, 0.52))])
    cork = nb.mix(nb.smooth(0.45, 0.75, nb.noise(obj_co, 400.0, 2.0)), (0.72, 0.56, 0.36), (0.42, 0.28, 0.14))
    # pilings: weathered grey above the water, dark green-brown wet band below
    pil = nb.ramp(g, [(0.0, (0.30, 0.26, 0.20)), (1.0, (0.56, 0.50, 0.40))])
    wet = nb.smooth(0.15, -0.25, sep.outputs["Z"])
    pil = nb.mix(wet, pil, nb.mul(pil, (0.45, 0.55, 0.42)))
    # canvas: red / cream stripes along Y
    stripe = nb.smooth(-0.05, 0.05, nb.math("SINE", nb.math("MULTIPLY", sep.outputs["Y"], 2.0 * math.pi / 0.40)))
    canvas = nb.mix(stripe, (0.90, 0.86, 0.76), (0.72, 0.16, 0.14))
    stops = [("wood", wood), ("metal", (0.55, 0.56, 0.58)), ("canvas", canvas), ("cork", cork),
             ("graphite", (0.09, 0.09, 0.10)), ("dark", (0.05, 0.05, 0.06)), ("crate", crate),
             ("rope", (0.80, 0.76, 0.64)), ("piling", pil), ("sign", sign)]
    col = None
    for k, c in stops:
        if col is None:
            col = c if hasattr(c, "is_linked") else nb.mix(0.0, c, c)
            continue
        m = nb.smooth(PR[k] - 0.5, PR[k] - 0.4, region)
        col = nb.mix(m, col, c)
    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    nb.put(bsdf.inputs["Base Color"], col)
    bsdf.inputs["Roughness"].default_value = 0.55
    out = nb.n("ShaderNodeOutputMaterial")
    nb.links.new(bsdf.outputs[0], out.inputs[0])
    alpha = nb.math("ADD", 1.0, 0.0)
    img_node = nb.n("ShaderNodeTexImage")
    tree.nodes.active = img_node
    return mat, img_node, alpha, col, bsdf, out


def smart_uv(obj):
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.scene.objects:
        o.select_set(o is obj)
    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.004, correct_aspect=True,
                             scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


PROP_VIEWS = {"rod": {"34": Vector((0.35, -1.0, 0.45)), "side": Vector((0.0, -1.0, 0.08)),
                      "reel": Vector((0.6, -1.0, 0.55))},
              "dock": {"34": Vector((0.9, -1.0, 0.7)), "side": Vector((0.0, -1.0, 0.12))},
              "stall": {"34": Vector((1.0, -0.8, 0.5)), "side": Vector((1.0, 0.0, 0.08))}}


def generate_prop(name, P, exports, previews, views, do_fbx, do_render, final):
    scene = new_scene()
    t0 = time.time()
    builder = {"rod": build_rod, "dock": build_dock, "stall": build_stall}[P["kind"]]
    obj = builder(name)
    smart_uv(obj)
    tris = tri_count(obj.data)
    mat, img_node, alpha_sock, col_sock, bsdf, out_node = build_prop_material(name, P)
    obj.data.materials.append(mat)
    png = os.path.join(exports, f"{name}_diffuse.png")
    bake_material(obj, mat, img_node, alpha_sock, col_sock, bsdf, out_node, png)
    tex_mat = make_textured_material(f"Prop_{name}", png, roughness=0.55, alpha=False)
    obj.data.materials.clear()
    obj.data.materials.append(tex_mat)
    bpy.data.materials.remove(mat)
    dims = tuple(round(v, 4) for v in obj.dimensions)
    log(f"{name}: {tris} tris, dims {dims}, built+baked in {time.time() - t0:.1f}s")
    pngs = []
    if do_render:
        samples = RENDER["samples_final"] if final else RENDER["samples_preview"]
        extra = ["reel"] if P["kind"] == "rod" else []
        for vk in list(views) + extra:
            vd = PROP_VIEWS[P["kind"]].get(vk) or VIEW_DIRS[vk]
            clear_studio(scene, {obj})
            frame = ((0.0, -0.08, -0.11), (0.62, 0.08, 0.03)) if vk == "reel" else None
            studio(scene, [obj], vd, samples, ground=P["kind"] != "dock", lens=50.0, frame=frame)
            png_ = os.path.join(previews, f"{name}_{vk}.png")
            t1 = time.time()
            render_to(scene, png_)
            log(f"{name}: rendered {vk} in {time.time() - t1:.1f}s")
            pngs.append(png_)
        clear_studio(scene, {obj})
    fbx = None
    if do_fbx:
        fbx = os.path.join(exports, f"{name}.fbx")
        export_fbx(scene, [obj], fbx)
    return dict(preset=name, kind=P["kind"], length_m=P["length_m"], triangles=tris, subdiv_applied=False,
                dimensions_m=list(dims), textures=[png], fbx=fbx, fbx_rigged=None, bones=[], previews=pngs,
                forward_axis="FBX +X", origin=ORIGINS[P["kind"]])


ORIGINS = {"rod": "butt end, rod along +X, guides hang on -Z",
           "dock": "shore end, centre line, deck top at z = 0.70, water at z = 0",
           "stall": "floor under the centre of the counter front edge, customer side = +X"}


def contact_sheet(exports, previews, names):
    """Re-imports the exported FBX files (a real check of what Roblox gets) and renders all fish
    side-on with one orthographic camera, so sizes compare 1:1."""
    scene = new_scene()
    fish = []
    for n in names:
        path = os.path.join(exports, f"fish_{n}.fbx")
        if not os.path.exists(path):
            continue
        before = set(scene.objects)
        bpy.ops.import_scene.fbx(filepath=path)
        new = [o for o in scene.objects if o not in before and o.type == "MESH"]
        if not new:
            continue
        o = new[0]
        o.name = f"sheet_{n}"
        fish.append((n, o))
    # layout: rows of (name, x offset); each fish's nose at x0, body along -X
    rows = [[("pike",)], [("carp",), ("perch",)], [("trout",), ("minnow",)]]
    placed = []
    y = 0.0
    row_h = 0.26
    by_name = dict(fish)
    labels = []
    for row in rows:
        x = 0.42
        for (n,) in row:
            if n not in by_name:
                continue
            o = by_name[n]
            o.location = (x, 0.0, y)
            placed.append(o)
            L = PRESETS[n]["length_m"]
            labels.append((f"{n}  {L:.2f} m", x - 0.5 * L, y - 0.095))
            x -= L + 0.10
        y -= row_h
    for text, lx, lz in labels:
        cu = bpy.data.curves.new("lbl", "FONT")
        cu.body = text
        cu.size = 0.030
        cu.align_x = "CENTER"
        tx = bpy.data.objects.new("lbl", cu)
        tx.location = (lx, -0.02, lz)
        tx.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        m = bpy.data.materials.new("LabelMat")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.05, 0.06, 1.0)
        cu.materials.append(m)
        scene.collection.objects.link(tx)
        placed.append(tx)
    bpy.context.view_layer.update()
    studio(scene, placed, Vector((0.0, -1.0, 0.0)), RENDER["samples_preview"], ortho_scale=1.0, ground=False,
           up=Vector((0.0, 0.0, 1.0)))
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    path = os.path.join(previews, "contact_sheet.png")
    render_to(scene, path)
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description="GameOne v2 fish + prop generator (Blender bpy, Cycles CPU).")
    ap.add_argument("--all", action="store_true", help="build every preset (fish, props) and the contact sheet")
    ap.add_argument("--preset", action="append", default=[], help="preset name (repeatable)")
    ap.add_argument("--out", default=HERE, help="base dir; writes <out>/exports_v2 and <out>/previews_v2")
    ap.add_argument("--views", default="34,side", help="comma list of preview views: 34,side,top,front")
    ap.add_argument("--no-fbx", action="store_true")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--final", action="store_true", help="128 samples instead of 64")
    ap.add_argument("--no-sheet", action="store_true", help="skip the contact sheet")
    ap.add_argument("--sheet", action="store_true", help="also build the contact sheet from the exported fish")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(argv)
    if args.list:
        for k, v in PRESETS.items():
            print(f"{k:14s} {v['kind']:5s} {v['length_m']:.2f} m")
        return 0
    names = list(PRESETS) if args.all else args.preset
    if not names:
        ap.error("give --all or at least one --preset NAME")
    for n in names:
        if n not in PRESETS:
            ap.error(f"unknown preset '{n}'; known: {', '.join(PRESETS)}")
    views = [v.strip() for v in args.views.split(",") if v.strip()]
    for v in views:
        if v not in VIEW_DIRS:
            ap.error(f"unknown view '{v}'; known: {', '.join(VIEW_DIRS)}")
    out = os.path.abspath(args.out)
    exports = os.path.join(out, "exports_v2")
    previews = os.path.join(out, "previews_v2")
    os.makedirs(exports, exist_ok=True)
    os.makedirs(previews, exist_ok=True)

    man_path = os.path.join(exports, "manifest.json")
    manifest = {}
    if os.path.exists(man_path):
        try:
            with open(man_path, "r", encoding="utf-8") as fh:
                manifest = {m["preset"]: m for m in json.load(fh)}
        except Exception:
            manifest = {}
    for name in names:
        P = PRESETS[name]
        if P["kind"] == "fish":
            info = generate_fish(name, P, exports, previews, views, not args.no_fbx, not args.no_render, args.final)
        else:
            info = generate_prop(name, P, exports, previews, views, not args.no_fbx, not args.no_render, args.final)
        manifest[name] = info
        print(f"[v2] {name:14s} {info['triangles']:5d} tris  dims {info['dimensions_m']}  fbx={bool(info.get('fbx'))}")
    if (args.sheet or args.all) and not args.no_sheet and not args.no_render:
        sheet = contact_sheet(exports, previews, [n for n in PRESETS if PRESETS[n]["kind"] == "fish"])
        log(f"contact sheet -> {sheet}")
    with open(man_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump([manifest[k] for k in PRESETS if k in manifest], fh, indent=2)
        fh.write("\n")
    log(f"manifest -> {man_path}")
    over = [k for k, m in manifest.items() if m["triangles"] > BUDGET["roblox_max"]]
    if over:
        log(f"WARNING over the Roblox 10k budget: {over}")
        return 1
    return 0


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    sys.exit(main())
