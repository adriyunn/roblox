#!/usr/bin/env python3
# fish_generator.py (About Fishing F2 species placeholders; Cloud, 2026-10-06; blender/README.md)
# Parametric low-poly fish: tapered lathe body, forked tail, dorsal/anal/pectoral fins, flat
# colour materials. Exports fish_<name>.fbx (Roblox axes) and a Cycles preview PNG per preset.
#
# Written in the cloud session WITHOUT the GameOne project files. These are placeholders for the
# F2 species pass; F1 keeps the trout rig the team already has. A dev must check the import scale
# (metres vs the game's stud ratio) and the facing axis TroutView expects (see README).
#
# Needs only `bpy` (Blender 5.2 as a Python module) and its bundled mathutils / bmesh.
# No display is needed: every scene starts from read_factory_settings(use_empty=True) and renders
# with CYCLES on the CPU.
#
# Usage:
#   python3 fish_generator.py --all
#   python3 fish_generator.py --preset trout --out /some/dir
#   python3 fish_generator.py --preset pike --preset carp --views 34,side,top --no-fbx
#   python3 fish_generator.py --all --face-negz        # nose on Roblox LookVector (-Z) instead of +X
#
# Axes: the fish is built with the mouth tip at the origin, +X forward (nose), +Z up, +Y = the fish's
# left side. 1 Blender unit = 1 metre; length_m is the real total length including the tail fin.

import argparse
import json
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

# ----------------------------------------------------------------------------------------------
# PARAMETERS
# ----------------------------------------------------------------------------------------------
# Every size that is not length_m is a RATIO of length_m, so a preset keeps its shape when scaled.
#
# key                  meaning                                                       typical
# length_m             total length, mouth tip to tail tips, metres                  0.08 .. 0.70
# body_depth_ratio     max body height (top to belly) / length                       0.13 .. 0.32
# body_width_ratio     max body width (side to side) / length                        0.09 .. 0.17
# head_ratio           head length / body length (body = length minus tail fin)       0.22 .. 0.32
# head_flat            0..1, flattens the head top-to-bottom towards the nose (pike)  0.0 .. 0.5
# head_width_boost     0..1, widens the head towards the nose (pike duck-bill)        0.0 .. 0.3
# back_arch            0..0.35, back hump taller than belly (perch, carp)             0.0 .. 0.3
# peduncle_ratio       half-depth at the tail root / max half-depth                   0.12 .. 0.2
# tail_len_ratio       caudal fin length / total length                              0.16 .. 0.22
# tail_span_ratio      caudal fin tip-to-tip span / length                           0.18 .. 0.26
# tail_fork_depth      0..1, how deep the fork notch cuts into the tail fin           0.0 .. 0.6
# dorsal_fin_height    dorsal fin height above the back / length                     0.08 .. 0.22
# dorsal_pos           where the dorsal starts, 0 nose .. 1 tail root (of body)      0.30 .. 0.72
# dorsal_len           dorsal base length / body length                              0.12 .. 0.40
# anal_fin_height      anal fin height / length (0 = none)                           0.0 .. 0.10
# pectoral_fin_length  pectoral fin length / length (0 = none)                       0.09 .. 0.15
# fin_thickness_ratio  fin slab thickness / length                                   0.006 .. 0.012
# segments             rings along the body (10+ so a future bend bone has room)     14 .. 20
# sides                vertices per ring                                             10 .. 14
# base_colour          back colour, linear RGB 0..1
# band_colour          lateral band / vertical bar / light-spot colour
# belly_colour         belly colour
# fin_colour           fin colour (None = darkened base colour)
# spot_colour          dark spot colour (None = dark brown)
# band_width           0..1, width of the lateral band (0 = no band); a face row is  0.0 .. 0.5
#                      in the band when its centre angle is within band_width*45deg of the
#                      lateral line, so with 14 sides 0.30 gives one row, with 12 sides you need
#                      >= 0.34 (two rows)
# bar_every            0 = none, n = vertical bars every n rings (perch)              0 .. 3
# spot_density         0..1, fraction of back faces painted as spots                 0.0 .. 0.25
# spot_light           True = spots use band_colour (pike), False = spot_colour       -
# belly_start          0..1, where the belly material begins (angle from the top /pi) 0.58 .. 0.68
# eyes                 True to add two low-poly eyes                                  -
# eye_size_ratio       eye radius / length                                            0.025 .. 0.04
# seed                 random seed for spot placement (deterministic exports)         -

DEFAULTS = dict(
    length_m=0.40, body_depth_ratio=0.21, body_width_ratio=0.12,
    head_ratio=0.22, head_flat=0.0, head_width_boost=0.0, back_arch=0.05, peduncle_ratio=0.16,
    tail_len_ratio=0.19, tail_span_ratio=0.22, tail_fork_depth=0.25,
    dorsal_fin_height=0.11, dorsal_pos=0.42, dorsal_len=0.14, anal_fin_height=0.06,
    pectoral_fin_length=0.13, fin_thickness_ratio=0.008,
    segments=18, sides=12,
    base_colour=(0.33, 0.42, 0.27), band_colour=(0.78, 0.45, 0.42), belly_colour=(0.88, 0.86, 0.72),
    fin_colour=None, spot_colour=None,
    band_width=0.4, bar_every=0, spot_density=0.0, spot_light=False, belly_start=0.63,
    eyes=True, eye_size_ratio=0.032, seed=7,
)

PRESETS = {
    # trout: 0.40 m, olive back, pink lateral band, dark spots, moderate fork
    "trout": dict(
        length_m=0.40, body_depth_ratio=0.21, body_width_ratio=0.12, head_ratio=0.22,
        back_arch=0.05, tail_fork_depth=0.25, dorsal_fin_height=0.11, dorsal_pos=0.42, dorsal_len=0.14,
        pectoral_fin_length=0.13, segments=18, sides=14,
        base_colour=(0.33, 0.42, 0.27), band_colour=(0.80, 0.46, 0.44), belly_colour=(0.88, 0.86, 0.72),
        band_width=0.30, spot_density=0.16, spot_colour=(0.12, 0.10, 0.08), seed=7,
    ),
    # perch: 0.25 m, deep humped body, tall spiny dorsal, dark vertical bars, orange fins
    "perch": dict(
        length_m=0.25, body_depth_ratio=0.32, body_width_ratio=0.13, head_ratio=0.26,
        back_arch=0.25, tail_fork_depth=0.18, tail_span_ratio=0.24,
        dorsal_fin_height=0.20, dorsal_pos=0.30, dorsal_len=0.28, anal_fin_height=0.08,
        pectoral_fin_length=0.14, segments=16, sides=12,
        base_colour=(0.42, 0.50, 0.20), band_colour=(0.17, 0.21, 0.12), belly_colour=(0.90, 0.85, 0.60),
        fin_colour=(0.85, 0.38, 0.12), band_width=0.0, bar_every=2, spot_density=0.0, seed=3,
    ),
    # pike: 0.70 m, long and shallow, flat wide head, dorsal set far back, light spots
    "pike": dict(
        length_m=0.70, body_depth_ratio=0.13, body_width_ratio=0.09, head_ratio=0.32,
        head_flat=0.45, head_width_boost=0.22, back_arch=0.0, peduncle_ratio=0.2,
        tail_len_ratio=0.17, tail_span_ratio=0.18, tail_fork_depth=0.30,
        dorsal_fin_height=0.08, dorsal_pos=0.70, dorsal_len=0.14, anal_fin_height=0.07,
        pectoral_fin_length=0.09, segments=20, sides=12,
        base_colour=(0.28, 0.40, 0.22), band_colour=(0.82, 0.80, 0.52), belly_colour=(0.85, 0.85, 0.70),
        band_width=0.0, spot_density=0.16, spot_light=True, seed=11,
    ),
    # carp: 0.50 m, deep heavy body, long dorsal base, golden brown (scale texture not needed)
    "carp": dict(
        length_m=0.50, body_depth_ratio=0.30, body_width_ratio=0.17, head_ratio=0.24,
        back_arch=0.30, tail_fork_depth=0.28, tail_span_ratio=0.24,
        dorsal_fin_height=0.11, dorsal_pos=0.34, dorsal_len=0.40, anal_fin_height=0.07,
        pectoral_fin_length=0.14, segments=18, sides=14,
        base_colour=(0.52, 0.42, 0.20), band_colour=(0.72, 0.58, 0.30), belly_colour=(0.90, 0.80, 0.55),
        fin_colour=(0.45, 0.30, 0.14), band_width=0.30, spot_density=0.0, seed=5,
    ),
    # minnow: 0.08 m, slim silver body, dark lateral stripe, small fins
    "minnow": dict(
        length_m=0.08, body_depth_ratio=0.17, body_width_ratio=0.10, head_ratio=0.24,
        back_arch=0.0, tail_fork_depth=0.32, dorsal_fin_height=0.09, dorsal_pos=0.48, dorsal_len=0.12,
        anal_fin_height=0.05, pectoral_fin_length=0.12, segments=14, sides=10,
        base_colour=(0.40, 0.46, 0.42), band_colour=(0.18, 0.20, 0.24), belly_colour=(0.90, 0.90, 0.88),
        band_width=0.35, spot_density=0.0, eye_size_ratio=0.03, seed=2,
    ),
}

RENDER = dict(engine="CYCLES", device="CPU", samples=24, res_x=480, res_y=360)
VIEW_DIRS = {              # camera direction from the fish centre (fish faces +X, +Z up)
    "34": Vector((0.9, -1.0, 0.6)),
    "side": Vector((0.0, -1.0, 0.08)),
    "top": Vector((0.05, -0.05, 1.0)),
    "front": Vector((1.0, -0.15, 0.2)),
}


# ----------------------------------------------------------------------------------------------
# PROFILE CURVES
# ----------------------------------------------------------------------------------------------
def hermite(points, t):
    """Cubic Hermite through (t, y) points with finite-difference tangents (non-uniform Catmull-Rom)."""
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


def depth_profile_points(P):
    hr = P["head_ratio"]
    peak = max(hr + 0.06, 0.40)
    return [(0.0, 0.36), (hr * 0.45, 0.72), (hr, 0.92), (peak, 1.0),
            (0.62, 0.80), (0.82, 0.42), (1.0, P["peduncle_ratio"])]


def width_profile_points(P):
    hr = P["head_ratio"]
    return [(0.0, 0.40), (hr * 0.5, 0.86), (hr, 1.0), (0.45, 0.92),
            (0.65, 0.66), (0.85, 0.34), (1.0, max(0.18, P["peduncle_ratio"]))]


def radii_at(P, t):
    """Half-sizes of the elliptical cross-section at body fraction t (0 nose, 1 tail root).
    Returns (half_depth_top, half_depth_bottom, half_width)."""
    L = P["length_m"]
    hr = P["head_ratio"]
    f = hermite(depth_profile_points(P), t)
    g = hermite(width_profile_points(P), t)
    if t < hr:
        head_u = 1.0 - t / hr                       # 1 at the nose, 0 at the gill
        f *= (1.0 - P["head_flat"] * head_u)
        g *= (1.0 + P["head_width_boost"] * head_u)
    half_depth = f * P["body_depth_ratio"] * L * 0.5
    half_width = g * P["body_width_ratio"] * L * 0.5
    arch = P["back_arch"]
    return half_depth * (1.0 + arch), half_depth * (1.0 - arch * 0.5), half_width


def body_length(P):
    return P["length_m"] * (1.0 - P["tail_len_ratio"])


# ----------------------------------------------------------------------------------------------
# MATERIALS
# ----------------------------------------------------------------------------------------------
MAT_BACK, MAT_BELLY, MAT_FINS, MAT_BAND, MAT_SPOT, MAT_EYE = range(6)
MAT_NAMES = ["FishBack", "FishBelly", "FishFins", "FishBand", "FishSpot", "FishEye"]


def make_material(name, rgb, roughness=0.6, specular=0.3):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)   # what the FBX exporter writes as diffuse
    return mat


def material_colours(P):
    base, band, belly = P["base_colour"], P["band_colour"], P["belly_colour"]
    fins = P["fin_colour"] or (base[0] * 0.70, base[1] * 0.65, base[2] * 0.60)
    spot = band if P["spot_light"] else (P["spot_colour"] or (0.12, 0.10, 0.08))
    eye = (0.03, 0.03, 0.03)
    return [base, belly, fins, band, spot, eye]


# ----------------------------------------------------------------------------------------------
# GEOMETRY
# ----------------------------------------------------------------------------------------------
def polygon_normal(pts):
    """Newell's method; works for concave planar polygons."""
    n = Vector((0.0, 0.0, 0.0))
    k = len(pts)
    for i in range(k):
        a, b = pts[i], pts[(i + 1) % k]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n.normalized()


def add_fin(bm, pts, thickness, mat_index):
    """A thin slab: the planar polygon `pts` offset +-thickness/2 along its normal, plus a rim."""
    nrm = polygon_normal(pts) * (thickness * 0.5)
    top = [bm.verts.new(p + nrm) for p in pts]
    bot = [bm.verts.new(p - nrm) for p in pts]
    faces = [bm.faces.new(top), bm.faces.new(list(reversed(bot)))]
    k = len(pts)
    for i in range(k):
        faces.append(bm.faces.new((top[i], top[(i + 1) % k], bot[(i + 1) % k], bot[i])))
    for f in faces:
        f.material_index = mat_index
    return faces


def ring_t(P, i):
    """Body fraction of ring i; slightly denser near the head. Ring 0 sits just behind the nose pole."""
    seg = P["segments"]
    return ((i + 1) / seg) ** 0.9


def add_body(bm, P, rng):
    L = P["length_m"]
    Lb = body_length(P)
    seg, sides = P["segments"], P["sides"]
    rings = []
    for i in range(seg):
        t = ring_t(P, i)
        x = -t * Lb
        hz_top, hz_bot, wy = radii_at(P, t)
        ring = []
        for j in range(sides):
            phi = 2.0 * math.pi * j / sides           # 0 = top of the back, pi = belly
            c, s = math.cos(phi), math.sin(phi)
            z = (hz_top if c >= 0 else hz_bot) * c
            ring.append(bm.verts.new((x, wy * s, z)))
        rings.append(ring)

    nose = bm.verts.new((0.0, 0.0, 0.0))                       # mouth tip = origin
    tail_pole = bm.verts.new((-Lb - 0.012 * L, 0.0, 0.0))

    belly_angle = P["belly_start"] * math.pi
    band_half = P["band_width"] * (math.pi / 4.0)

    def region(i, j):
        phi = 2.0 * math.pi * (j + 0.5) / sides
        a = phi if phi <= math.pi else 2.0 * math.pi - phi      # 0 top .. pi belly
        if a > belly_angle:
            return MAT_BELLY
        if band_half > 0 and abs(a - math.pi / 2.0) < band_half:
            return MAT_BAND
        if P["bar_every"] > 0 and (i // P["bar_every"]) % 2 == 1 and a < belly_angle * 0.92:
            return MAT_BAND
        if P["spot_density"] > 0 and rng.random() < P["spot_density"]:
            return MAT_SPOT
        return MAT_BACK

    for i in range(seg - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(sides):
            jn = (j + 1) % sides
            f = bm.faces.new((a[j], a[jn], b[jn], b[j]))
            f.material_index = region(i, j)
    for j in range(sides):                                      # nose fan
        jn = (j + 1) % sides
        f = bm.faces.new((nose, rings[0][jn], rings[0][j]))
        phi = 2.0 * math.pi * (j + 0.5) / sides
        a = phi if phi <= math.pi else 2.0 * math.pi - phi
        f.material_index = MAT_BELLY if a > belly_angle else MAT_BACK
    last = rings[-1]
    for j in range(sides):                                      # tail root cap
        jn = (j + 1) % sides
        f = bm.faces.new((tail_pole, last[j], last[jn]))
        f.material_index = MAT_BACK
    return rings


def surface_top_z(P, x):
    t = min(1.0, max(0.0, -x / body_length(P)))
    return radii_at(P, t)[0]


def surface_bot_z(P, x):
    t = min(1.0, max(0.0, -x / body_length(P)))
    return -radii_at(P, t)[1]


def add_tail(bm, P):
    L = P["length_m"]
    Lb = body_length(P)
    Lt = L - Lb
    span = P["tail_span_ratio"] * L
    fork = P["tail_fork_depth"]
    rz = radii_at(P, 1.0)[0]
    xr = -Lb + 0.05 * L                                          # root sits inside the peduncle
    pts = [
        Vector((xr, 0.0, rz * 0.75)),
        Vector((-Lb - 0.45 * Lt, 0.0, span * 0.30)),
        Vector((-L, 0.0, span * 0.50)),
        Vector((-L + fork * Lt * 0.55, 0.0, span * 0.17)),
        Vector((-L + fork * Lt, 0.0, 0.0)),
        Vector((-L + fork * Lt * 0.55, 0.0, -span * 0.17)),
        Vector((-L, 0.0, -span * 0.50)),
        Vector((-Lb - 0.45 * Lt, 0.0, -span * 0.30)),
        Vector((xr, 0.0, -rz * 0.75)),
    ]
    if fork <= 0.02:                                             # rounded tail: drop the notch
        pts = pts[:4] + pts[5:]
    return add_fin(bm, pts, P["fin_thickness_ratio"] * L, MAT_FINS)


def add_dorsal(bm, P):
    L = P["length_m"]
    Lb = body_length(P)
    H = P["dorsal_fin_height"] * L
    x0 = -P["dorsal_pos"] * Lb
    dlen = P["dorsal_len"] * Lb
    x1 = x0 - dlen
    inset = 0.30 * radii_at(P, -x0 / Lb)[0]
    xm = x0 - 0.5 * dlen
    pts = [
        Vector((x0, 0.0, surface_top_z(P, x0) - inset)),
        Vector((x1, 0.0, surface_top_z(P, x1) - inset)),
        Vector((x1, 0.0, surface_top_z(P, x1) + 0.40 * H)),
        Vector((xm, 0.0, surface_top_z(P, xm) + 0.78 * H)),
        Vector((x0 - 0.22 * dlen, 0.0, surface_top_z(P, x0) + H)),
    ]
    return add_fin(bm, pts, P["fin_thickness_ratio"] * L, MAT_FINS)


def add_anal(bm, P):
    if P["anal_fin_height"] <= 0:
        return []
    L = P["length_m"]
    Lb = body_length(P)
    H = P["anal_fin_height"] * L
    x0 = -0.70 * Lb
    x1 = -0.83 * Lb
    inset = 0.30 * radii_at(P, 0.75)[1]
    pts = [
        Vector((x0, 0.0, surface_bot_z(P, x0) + inset)),
        Vector((x0 - 0.25 * (x0 - x1), 0.0, surface_bot_z(P, x0) - H)),
        Vector((x1, 0.0, surface_bot_z(P, x1) - 0.45 * H)),
        Vector((x1, 0.0, surface_bot_z(P, x1) + inset)),
    ]
    return add_fin(bm, pts, P["fin_thickness_ratio"] * L, MAT_FINS)


def add_pectorals(bm, P):
    if P["pectoral_fin_length"] <= 0:
        return []
    L = P["length_m"]
    Lb = body_length(P)
    pl = P["pectoral_fin_length"] * L
    x0 = -P["head_ratio"] * Lb - 0.01 * L
    x1 = x0 - 0.06 * L
    theta = 0.35                                                 # 20 deg below the lateral line
    faces = []
    for side in (+1.0, -1.0):                                    # +Y = fish's left, -Y = right
        def on_body(x):
            _, hz_bot, wy = radii_at(P, -x / Lb)
            return Vector((x, side * wy * math.cos(theta) * 0.85, -hz_bot * math.sin(theta) * 0.85))
        a, b = on_body(x0), on_body(x1)
        mid = (a + b) * 0.5
        tip = mid + Vector((-0.55 * pl, side * 0.80 * pl, -0.25 * pl))
        faces += add_fin(bm, [a, b, tip], P["fin_thickness_ratio"] * L, MAT_FINS)
    return faces


def add_eyes(bm, P):
    if not P["eyes"]:
        return []
    L = P["length_m"]
    Lb = body_length(P)
    t = P["head_ratio"] * 0.50
    x = -t * Lb
    hz_top, _, wy = radii_at(P, t)
    # clamp to the local head size so a tiny fish (minnow) does not get an eye bigger than its head
    r = min(P["eye_size_ratio"] * L, 0.42 * hz_top, 0.80 * wy)
    faces = []
    for side in (+1.0, -1.0):
        pos = Vector((x, side * wy * 0.92, hz_top * 0.30))
        mtx = Matrix.Translation(pos) @ Matrix.Rotation(math.pi / 2.0, 4, "X") @ Matrix.Diagonal((r, r * 0.6, r, 1.0))
        res = bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=1.0, matrix=mtx)
        new_faces = set()
        for v in res["verts"]:
            new_faces.update(v.link_faces)
        for f in new_faces:
            f.material_index = MAT_EYE
        faces += list(new_faces)
    return faces


def build_fish(name, P):
    """Builds the fish object in the current (empty) scene. Returns (object, triangle_count)."""
    rng = random.Random(P["seed"])
    bm = bmesh.new()
    add_body(bm, P, rng)
    add_tail(bm, P)
    add_dorsal(bm, P)
    add_anal(bm, P)
    add_pectorals(bm, P)
    add_eyes(bm, P)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    tri_count = len(bm.faces)

    me = bpy.data.meshes.new(f"fish_{name}")
    bm.to_mesh(me)
    bm.free()
    me.update()
    for poly in me.polygons:
        poly.use_smooth = False                                  # flat shading: the PSX look
    colours = material_colours(P)
    for idx, mname in enumerate(MAT_NAMES):
        rough = 0.25 if idx == MAT_EYE else (0.5 if idx == MAT_FINS else 0.6)
        me.materials.append(make_material(f"{mname}_{name}", colours[idx], roughness=rough))
    obj = bpy.data.objects.new(f"fish_{name}", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj, tri_count


# ----------------------------------------------------------------------------------------------
# PREVIEW SCENE
# ----------------------------------------------------------------------------------------------
def setup_preview_scene(scene, obj, P, view_key):
    L = P["length_m"]
    corners = [Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    centre = (lo + hi) * 0.5
    radius = (hi - lo).length * 0.5

    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.52, 0.60, 0.68, 1.0)
    bg.inputs["Strength"].default_value = 0.55
    scene.world = world

    ground_me = bpy.data.meshes.new("Ground")
    ground_bm = bmesh.new()
    s = 8.0 * L
    zg = lo.z - 0.03 * L
    ground_bm.faces.new([ground_bm.verts.new(v) for v in
                         ((-s, -s, zg), (s, -s, zg), (s, s, zg), (-s, s, zg))])
    ground_bm.to_mesh(ground_me)
    ground_bm.free()
    ground_me.materials.append(make_material("GroundMat", (0.42, 0.44, 0.46), roughness=0.9))
    ground = bpy.data.objects.new("Ground", ground_me)
    scene.collection.objects.link(ground)

    def add_sun(name, from_dir, energy, colour):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.angle = math.radians(12.0)
        ld.color = colour
        lo_ = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo_)
        lo_.location = centre + Vector(from_dir).normalized() * (4.0 * L)
        lo_.rotation_euler = (-Vector(from_dir)).to_track_quat("-Z", "Y").to_euler()

    add_sun("Key", (0.6, -0.8, 1.2), 4.8, (1.0, 0.97, 0.92))
    add_sun("Fill", (-0.5, 1.0, 0.5), 1.3, (0.85, 0.92, 1.0))

    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = 50.0
    cam_d.clip_start = 0.001          # default 0.1 m would slice the 8 cm minnow's head open
    cam_d.clip_end = 100.0
    cam = bpy.data.objects.new("Cam", cam_d)
    scene.collection.objects.link(cam)
    direction = VIEW_DIRS[view_key].normalized()
    hfov = 2.0 * math.atan(cam_d.sensor_width / (2.0 * cam_d.lens))
    dist = radius / math.sin(hfov * 0.5) * 0.84
    cam.location = centre + direction * dist
    # explicit look-at: camera -Z points at the fish, camera +Y follows `up` (nose-up for the top view)
    up = Vector((1.0, 0.0, 0.0)) if view_key == "top" else Vector((0.0, 0.0, 1.0))
    z_axis = direction
    x_axis = up.cross(z_axis).normalized()
    y_axis = z_axis.cross(x_axis)
    cam.rotation_euler = Matrix((x_axis, y_axis, z_axis)).transposed().to_euler()
    scene.camera = cam

    scene.render.engine = RENDER["engine"]
    scene.cycles.device = RENDER["device"]
    scene.cycles.samples = RENDER["samples"]
    scene.render.resolution_x = RENDER["res_x"]
    scene.render.resolution_y = RENDER["res_y"]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def render_preview(scene, path_abs):
    scene.render.filepath = path_abs                              # ALWAYS absolute
    bpy.ops.render.render(write_still=True)


def export_fbx(scene, obj, path_abs, face_negz=False):
    if face_negz:
        # Rotate the mesh data so the nose points to Blender -Y, which the exporter maps to FBX -Z
        # (Roblox's LookVector). Done on the mesh, not the object, so no transform is left in the file.
        obj.data.transform(Matrix.Rotation(-math.pi / 2.0, 4, "Z"))
        obj.data.update()
    for o in scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=path_abs, use_selection=True, object_types={"MESH"},
        axis_forward="-Z", axis_up="Y", bake_space_transform=True,
        global_scale=1.0, apply_unit_scale=True, apply_scale_options="FBX_SCALE_NONE",
        use_mesh_modifiers=True, mesh_smooth_type="FACE", use_triangles=True,
        add_leaf_bones=False, path_mode="AUTO",
    )
    if face_negz:
        obj.data.transform(Matrix.Rotation(math.pi / 2.0, 4, "Z"))
        obj.data.update()


# ----------------------------------------------------------------------------------------------
# DRIVER
# ----------------------------------------------------------------------------------------------
def preset_params(name):
    if name not in PRESETS:
        raise SystemExit(f"unknown preset '{name}'; known: {', '.join(PRESETS)}")
    P = dict(DEFAULTS)
    P.update(PRESETS[name])
    return P


def generate(name, out_dir, views=("34",), do_fbx=True, do_render=True, face_negz=False):
    P = preset_params(name)
    bpy.ops.wm.read_factory_settings(use_empty=True)              # fresh, empty scene every time
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    obj, tris = build_fish(name, P)
    fbx_dir = os.path.join(out_dir, "exports")
    png_dir = os.path.join(out_dir, "previews")
    os.makedirs(fbx_dir, exist_ok=True)
    os.makedirs(png_dir, exist_ok=True)

    written = {"fbx": None, "png": []}
    if do_render:
        for vk in views:
            # rebuild the preview rig for each view (lights/camera framing depend on the view)
            for o in list(scene.objects):
                if o is not obj:
                    bpy.data.objects.remove(o, do_unlink=True)
            setup_preview_scene(scene, obj, P, vk)
            suffix = "" if vk == "34" else f"_{vk}"
            png = os.path.abspath(os.path.join(png_dir, f"fish_{name}{suffix}.png"))
            render_preview(scene, png)
            written["png"].append(png)
    if do_fbx:
        fbx = os.path.abspath(os.path.join(fbx_dir, f"fish_{name}.fbx"))
        export_fbx(scene, obj, fbx, face_negz=face_negz)
        written["fbx"] = fbx

    dims = obj.dimensions
    info = {
        "preset": name, "length_m": P["length_m"], "triangles": tris,
        "dimensions_m": [round(dims.x, 4), round(dims.y, 4), round(dims.z, 4)],
        "segments": P["segments"], "sides": P["sides"],
        "forward_axis": "FBX -Z (Roblox LookVector)" if face_negz else "FBX +X (Roblox RightVector)",
        "fbx": written["fbx"], "previews": written["png"],
    }
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(description="Parametric low-poly fish generator (GameOne F2 placeholders).")
    ap.add_argument("--all", action="store_true", help="build every preset")
    ap.add_argument("--preset", action="append", default=[], help="preset name (repeatable)")
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)),
                    help="output base dir; writes <out>/exports/*.fbx and <out>/previews/*.png")
    ap.add_argument("--views", default="34", help="comma list of preview views: 34,side,top,front")
    ap.add_argument("--no-fbx", action="store_true")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--face-negz", action="store_true",
                    help="rotate the mesh so the nose is on FBX -Z (Roblox LookVector) instead of +X")
    ap.add_argument("--list", action="store_true", help="print the presets and exit")
    args = ap.parse_args(argv)

    if args.list:
        for k, v in PRESETS.items():
            print(f"{k:8s} {v['length_m']:.2f} m")
        return 0
    names = list(PRESETS) if args.all else args.preset
    if not names:
        ap.error("give --all or at least one --preset NAME")
    views = [v.strip() for v in args.views.split(",") if v.strip()]
    for v in views:
        if v not in VIEW_DIRS:
            ap.error(f"unknown view '{v}'; known: {', '.join(VIEW_DIRS)}")

    out_dir = os.path.abspath(args.out)
    manifest = []
    for name in names:
        info = generate(name, out_dir, views=views, do_fbx=not args.no_fbx,
                        do_render=not args.no_render, face_negz=args.face_negz)
        manifest.append(info)
        print(f"[fish] {name:7s} {info['length_m']:.2f} m  {info['triangles']:5d} tris  "
              f"dims {info['dimensions_m']}  fbx={bool(info['fbx'])} png={len(info['previews'])}")

    os.makedirs(os.path.join(out_dir, "exports"), exist_ok=True)
    man_path = os.path.join(out_dir, "exports", "fish_manifest.json")
    with open(man_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")
    print(f"[fish] manifest -> {man_path}")
    over = [m for m in manifest if m["triangles"] > 1500]
    if over:
        print(f"[fish] WARNING over the 1,500 tri budget: {[m['preset'] for m in over]}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
