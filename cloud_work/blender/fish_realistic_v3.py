#!/usr/bin/env python3
# fish_realistic_v3.py (About Fishing F2 species, realism pass v3; Cloud, 2026-10-08; blender/README_v3.md)
# Round 3 on top of fish_realistic.py (v2, imported and reused, not modified):
#   A) UI sprites per species (side view 512x192 RGBA, 96x96 icon, sprites.json, sheet.png)
#   B) the rigged trout with two actions (Swim loop, Bend poses) exported as an animated FBX
#   C) fish v3: baked tangent-space NORMAL map from a hi-res source with overlapping scales, a baked
#      ROUGHNESS map, fins with real ray ridges and a scalloped edge, an eye with a pupil disc and a
#      translucent cornea cap, triangle counts under 8,000
#   D) new props: a spinning reel with line wrap on the rod, three lures, a clinker rowing boat, the
#      tackle box (the 3D version of the inventory frame)
#
# Written in the cloud session WITHOUT the GameOne project files. A dev must check the import scale
# (metres vs the game's stud ratio), the facing axis TroutView expects, and whether Roblox's importer
# picks the normal/roughness maps up from the FBX or needs them set on a SurfaceAppearance by hand.
#
# Needs only `bpy` (Blender 5.2 as a Python module), numpy (bundled), Pillow (sheets). No display:
# every scene starts from read_factory_settings(use_empty=True); renders and bakes use CYCLES on CPU.
#
# Usage:
#   python3 fish_realistic_v3.py --all                   # 5 fish + animated trout + 6 props + sheets
#   python3 fish_realistic_v3.py --all --final           # 128 samples (what is checked in)
#   python3 fish_realistic_v3.py --preset trout --quick  # one fish at 16 samples, for iteration
#   python3 fish_realistic_v3.py --preset carp --closeup # also the materials close-up
#   python3 fish_realistic_v3.py --sheet                 # rebuild the contact sheet + sprite sheet
#   python3 fish_realistic_v3.py --list
#
# Axes: fish mouth tip at the origin, +X forward (nose), +Z up, +Y = the fish's left side. 1 BU = 1 m.
# Lures: line eye at the origin, hanging along -Z (spinner, spoon) or lying along -X (fly).

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
sys.path.insert(0, HERE)
import fish_realistic as v2  # noqa: E402  (round 2, reused as a library)

log = v2.log
ATLAS = v2.ATLAS
FISH_NAMES = [k for k, p in v2.PRESETS.items() if p["kind"] == "fish"]
BUDGET3 = dict(fish_max=8000, prop_max=4000, roblox_max=20000)
SPRITE = dict(side_w=512, side_h=192, icon=96, fill=0.92)

# ----------------------------------------------------------------------------------------------
# PARAMETERS (v3 additions)
# ----------------------------------------------------------------------------------------------
# scales: cell = scale pitch in metres at the deepest section (the row count around the body is
# circumference / cell; the pitch along the body shrinks with the local radius so scales get smaller
# towards the tail, as on a real fish); height = step at a scale's free edge in metres.
SCALES = {
    "carp": dict(cell=0.020, height=0.00075),     # large, cupped
    "perch": dict(cell=0.0075, height=0.00030),   # medium, ctenoid
    "trout": dict(cell=0.0040, height=0.00018),   # fine
    "pike": dict(cell=0.0085, height=0.00032),    # medium
    "minnow": dict(cell=0.0018, height=0.00007),  # fine
}
RIDGE = dict(membrane=0.55, height=0.5, tip_taper=0.45)   # fin ray ridges relative to fin_th
ROUGH = dict(back=0.22, belly=0.42, fin=0.65, iris=0.30, pupil=0.12, cornea=0.05, scale_edge=0.28)
SWIM = dict(frames=30, fps=30, amp_deg=[0.0, 2.0, 3.6, 6.2, 10.4, 16.0, 25.0], lag_rad=0.6)
BEND = dict(frames=(1, 15, 30), k=(-1, 0, 1), deg_per_bone=6.0, bones=(1, 2, 3, 4, 5))  # body1..peduncle
REGION_CORNEA, REGION_PUPIL = 3.0, 4.0

# fin dicts get `cols` = 2 * rays + 1 so the ridge/trough pattern is sampled exactly, and a visible
# scallop on the trailing edge
PRESETS3 = {}
for _n in FISH_NAMES:
    _p = dict(v2.PRESETS[_n])
    _fins = []
    for _f in _p["fins"]:
        _f = dict(_f)
        if _f.get("rays", 0):
            _f["cols"] = 2 * _f["rays"] + 1
            if _f["kind"] in ("dorsal", "dorsal2", "anal"):
                _f.setdefault("scallop", 0.07)
        _fins.append(_f)
    _p["fins"] = _fins
    PRESETS3[_n] = _p

PROP3 = {
    "rod_and_reel": dict(kind="rod3", length_m=2.1, budget=4000),
    "lure_spinner": dict(kind="spinner", length_m=0.06, budget=4000),
    "lure_spoon": dict(kind="spoon", length_m=0.07, budget=4000),
    "lure_fly": dict(kind="fly", length_m=0.02, budget=4000),
    "boat": dict(kind="boat", length_m=3.5, budget=4000),
    "tacklebox": dict(kind="tacklebox", length_m=0.6, budget=4000),
}
ORIGINS3 = {
    "rod3": "butt end, rod along +X, guides and reel hang on -Z",
    "spinner": "line eye at the origin, lure hangs along -Z",
    "spoon": "line eye at the origin, lure hangs along -Z, painted face on -Y",
    "fly": "hook eye at the origin, shank along -X, hook point down (-Z)",
    "boat": "centre of the bottom of the keel, bow +X, up +Z, waterline about z = 0.22",
    "tacklebox": "centre of the base (bottom face), front (latches) on -Y, lid hinged on +Y, open 100 deg",
}
PROP_VIEWS3 = {
    "rod3": {"34": Vector((0.35, -1.0, 0.45)), "reel": Vector((0.6, -1.0, 0.55))},
    "spinner": {"34": Vector((0.9, -1.0, 0.35))},
    "spoon": {"34": Vector((0.6, -1.0, 0.45))},
    "fly": {"34": Vector((0.7, -1.0, 0.55))},
    "boat": {"34": Vector((0.9, -1.0, 0.75))},
    "tacklebox": {"34": Vector((0.7, -1.0, 0.75))},
}

# extra prop regions (v2.PR is the id table PropBuilder tags vertices with; v3 adds names at import
# time, the v2 file itself is untouched)
NEW_REGIONS = ["brass", "nickel", "hook", "lead", "bead", "paint", "hackle", "thread", "wing", "hull",
               "hull_in", "oar", "box_wood", "felt", "divider", "line", "rubber"]
for _r in NEW_REGIONS:
    if _r not in v2.PR:
        v2.PR[_r] = float(len(v2.PR))
        v2.PROP_REGIONS.append(_r)
PR = v2.PR


def smoothstep(a, b, x):
    return v2.smoothstep(a, b, x)


# ----------------------------------------------------------------------------------------------
# C2. FINS WITH RAY RIDGES (drop-in for v2.fin_grid while the v2 fin builders run)
# ----------------------------------------------------------------------------------------------
def fin_grid3(bm, lay, grid, normal, th, fid, uv_rect, uvs, rays=0):
    """Two-sided slab like v2.fin_grid, but the thickness follows the rays: ridges at integer
    s*rays (the painted ray lines are moved onto them), a thin membrane between, ridges tapering
    towards the tip. The grid has 2*rays+1 columns so every ridge and trough is a column."""
    rows, cols = len(grid), len(grid[0])
    top, bot = [], []
    for ri in range(rows):
        r = ri / (rows - 1)
        trow, brow = [], []
        for ci in range(cols):
            s = ci / (cols - 1)
            p = grid[ri][ci]
            n = normal(ri, ci)
            if rays:
                ridge = 0.5 + 0.5 * math.cos(2.0 * math.pi * s * rays)
                ht = 0.5 * th * (RIDGE["membrane"] + (1.0 - RIDGE["membrane"]) * ridge)
                ht += RIDGE["height"] * th * ridge * (1.0 - RIDGE["tip_taper"] * r)
                rayv = s * rays + 0.5
            else:
                ht = 0.5 * th
                rayv = 0.0
            vt = bm.verts.new(p + n * ht)
            vb = bm.verts.new(p - n * ht)
            for v in (vt, vb):
                v2.set_attrs(v, lay, ux=0, vz=0, region=1, fid=fid, fr=r, fs=s, ray=rayv, eyea=1)
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
            if (a in topset) != (b in topset):
                e.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


class patched:
    """with patched(module, name, value): temporarily swap a module attribute."""

    def __init__(self, mod, name, value):
        self.mod, self.name, self.value = mod, name, value

    def __enter__(self):
        self.old = getattr(self.mod, self.name)
        setattr(self.mod, self.name, self.value)

    def __exit__(self, *exc):
        setattr(self.mod, self.name, self.old)


# ----------------------------------------------------------------------------------------------
# C3. EYE: eyeball sphere (v2) + flattened pupil disc + translucent cornea cap
# ----------------------------------------------------------------------------------------------
def fin_rects3(fins):
    """v2.fin_rects plus rects for the two corneas and pupils (bottom strip of the atlas)."""
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
    for side in "LR":
        pieces.append((f"eye_{side}", 0.45))
        pieces.append((f"cornea_{side}", 0.45))
        pieces.append((f"pupil_{side}", 0.22))
    pieces.append(("barbel", 0.15))
    total = sum(w for _, w in pieces)
    gap = 0.006
    x0, y0, x1, y1 = v2.STRIP
    width = (x1 - x0) - gap * (len(pieces) - 1)
    rects = {}
    x = x0
    for name, w in pieces:
        ww = width * w / total
        if name.startswith(("eye", "cornea", "pupil")):
            side = min(ww, y1 - y0)
            rects[name] = (x, y0, x + side, y0 + side)
        else:
            rects[name] = (x, y0, x + ww, y1)
        x += ww + gap
    return rects


def eye_geometry(P, side):
    """Centre, radius and outward axis of the eye, the way v2.add_eye places it."""
    L = P["length_m"]
    Lb = v2.body_len(P)
    t = P["eye_t"] * P["head_len"]
    zt, zb, w = v2.section(P, t)
    r = min(P["eye_r"] * L, 0.45 * (zt - zb) * 0.5)
    phi = math.acos(P["eye_z"])
    y, z = v2.section_point(P, t, phi, zt, zb, w)
    centre = Vector((-t * Lb, side * y * 0.84, z))
    return centre, r, Vector((0.0, side, 0.0))


def add_eye3(bm, lay, P, side, rects, uvs):
    S = "L" if side > 0 else "R"
    faces = v2.add_eye(bm, lay, P, side, rects[f"eye_{S}"], uvs)
    centre, r, out = eye_geometry(P, side)
    ex, ez = Vector((1.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0))
    segs = 12

    def planar_uv(fs, rect, radius, origin):
        u0, v0, u1, v1 = rect
        for f in fs:
            uvs[f] = {}
            for v in f.verts:
                d = (v.co - origin) / radius
                uvs[f][v] = (u0 + (u1 - u0) * (0.5 + 0.48 * d.x), v0 + (v1 - v0) * (0.5 + 0.48 * d.z))

    # pupil: a flattened disc at the outward pole, rim sunk just under the sphere, centre lifted
    pr = 0.42 * r
    pole = centre + out * r
    ring = []
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        p = pole + (ex * math.cos(a) + ez * math.sin(a)) * pr - out * (0.10 * r)
        v = bm.verts.new(p)
        v2.set_attrs(v, lay, ux=0, vz=0, region=REGION_PUPIL, fid=0, fr=0, fs=0, ray=0, eyea=0.2)
        ring.append(v)
    vc = bm.verts.new(pole + out * (0.01 * r))
    v2.set_attrs(vc, lay, ux=0, vz=0, region=REGION_PUPIL, fid=0, fr=0, fs=0, ray=0, eyea=0.0)
    pupil_faces = []
    for i in range(segs):
        pupil_faces.append(bm.faces.new((vc, ring[i], ring[(i + 1) % segs])))
    bmesh.ops.recalc_face_normals(bm, faces=pupil_faces)
    planar_uv(pupil_faces, rects[f"pupil_{S}"], pr, pole)
    # cornea: spherical cap of radius 1.07 r, 0..64 deg from the outward axis
    rc = 1.07 * r
    angs = [0.0, 22.0, 44.0, 64.0]
    rings = []
    for ai, adeg in enumerate(angs):
        a = math.radians(adeg)
        if ai == 0:
            v = bm.verts.new(centre + out * rc)
            v2.set_attrs(v, lay, ux=0, vz=0, region=REGION_CORNEA, fid=0, fr=0, fs=0, ray=0, eyea=0.0)
            rings.append([v])
            continue
        row = []
        for i in range(segs):
            b = 2.0 * math.pi * i / segs
            p = centre + out * (rc * math.cos(a)) + (ex * math.cos(b) + ez * math.sin(b)) * (rc * math.sin(a))
            v = bm.verts.new(p)
            v2.set_attrs(v, lay, ux=0, vz=0, region=REGION_CORNEA, fid=0, fr=0, fs=0, ray=0, eyea=a / math.pi * 2.0)
            row.append(v)
        rings.append(row)
    cfaces = []
    for i in range(segs):
        cfaces.append(bm.faces.new((rings[0][0], rings[1][i], rings[1][(i + 1) % segs])))
    for k in range(1, len(rings) - 1):
        a_, b_ = rings[k], rings[k + 1]
        for i in range(segs):
            cfaces.append(bm.faces.new((a_[i], b_[i], b_[(i + 1) % segs], a_[(i + 1) % segs])))
    bmesh.ops.recalc_face_normals(bm, faces=cfaces)
    for f in cfaces:
        f.smooth = True
    planar_uv(cfaces, rects[f"cornea_{S}"], rc, centre)
    return list(faces) + pupil_faces + cfaces


# ----------------------------------------------------------------------------------------------
# C1. MATERIAL v3: v2's painted skin + cornea/pupil colours, cornea alpha, a roughness socket
# ----------------------------------------------------------------------------------------------
def build_fish_material3(name, P):
    mat, img_node, alpha, col, bsdf, out = v2.build_fish_material(name, P)
    nb = v2.NB(mat.node_tree)
    nb.x = 4000
    region = nb.attr("region")
    vz = nb.attr("vz")
    cm = nb.smooth(REGION_CORNEA - 0.5, REGION_CORNEA - 0.4, region)
    pm = nb.smooth(REGION_PUPIL - 0.5, REGION_PUPIL - 0.4, region)
    col3 = nb.mix(cm, col, (0.80, 0.88, 0.94))
    col3 = nb.mix(pm, col3, (0.012, 0.012, 0.014))
    nb.links.new(col3, bsdf.inputs["Base Color"])
    # alpha: v2 (0.85 fins, 1 elsewhere) with 0.35 on the cornea
    alpha3 = nb.math("ADD", nb.math("MULTIPLY", alpha, nb.math("SUBTRACT", 1.0, cm)), nb.math("MULTIPLY", cm, 0.35))
    # roughness: back wet/glossy, belly matter, fins matte, iris/pupil/cornea
    fm = nb.smooth(0.5, 0.6, nb.math("MULTIPLY", region, nb.smooth(1.6, 1.5, region)))   # fins only
    em = nb.smooth(1.5, 1.6, region)                                                   # any eye part
    h = nb.math("MULTIPLY_ADD", vz, 0.5, 0.5)
    body_r = nb.math("MULTIPLY_ADD", h, ROUGH["back"] - ROUGH["belly"], ROUGH["belly"])
    rough = nb.math("ADD", nb.math("MULTIPLY", body_r, nb.math("SUBTRACT", 1.0, fm)), nb.math("MULTIPLY", fm, ROUGH["fin"]))
    rough = nb.math("ADD", nb.math("MULTIPLY", rough, nb.math("SUBTRACT", 1.0, em)), nb.math("MULTIPLY", em, ROUGH["iris"]))
    rough = nb.math("ADD", nb.math("MULTIPLY", rough, nb.math("SUBTRACT", 1.0, cm)), nb.math("MULTIPLY", cm, ROUGH["cornea"]))
    rough = nb.math("ADD", nb.math("MULTIPLY", rough, nb.math("SUBTRACT", 1.0, pm)), nb.math("MULTIPLY", pm, ROUGH["pupil"]))
    return mat, img_node, alpha3, col3, bsdf, out, rough


def bake_emit_image(obj, mat, img_node, sock, bsdf, out_node, name, size=ATLAS, sources=None, extrusion=0.0,
                    ray_dist=0.0):
    """EMIT-bake a float socket of `mat` (or, with `sources`, the sources' own emission) into a
    Non-Color image on `obj`. Returns the numpy RGBA array (size*size*4)."""
    scene = bpy.context.scene
    tree = mat.node_tree
    img = bpy.data.images.new(name, size, size, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img_node.image = img
    tree.nodes.active = img_node
    emit = None
    if sources is None:
        emit = tree.nodes.new("ShaderNodeEmission")
        tree.links.new(sock, emit.inputs["Color"])
        tree.links.new(emit.outputs[0], out_node.inputs[0])
    for o in scene.objects:
        o.select_set(False)
    for o in (sources or []):
        o.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kw = dict(type="EMIT", margin=8, use_clear=True)
    if sources:
        kw.update(use_selected_to_active=True, cage_extrusion=extrusion, max_ray_distance=ray_dist)
    bpy.ops.object.bake(**kw)
    if emit is not None:
        tree.links.new(bsdf.outputs[0], out_node.inputs[0])
        tree.nodes.remove(emit)
    px = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(size, size, 4)


def save_png(path, rgb, alpha=None, size=ATLAS, noncolor=True):
    """Write an RGB(A) float array (size, size, 3) to PNG through a Blender image (Non-Color for
    data maps so no transform is applied)."""
    img = bpy.data.images.new(os.path.basename(path), size, size, alpha=alpha is not None)
    if noncolor:
        img.colorspace_settings.name = "Non-Color"
    out = np.empty((size, size, 4), dtype=np.float32)
    out[..., :3] = np.clip(rgb, 0.0, 1.0)
    out[..., 3] = 1.0 if alpha is None else np.clip(alpha, 0.0, 1.0)
    img.pixels.foreach_set(out.ravel())
    img.update()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


# ----------------------------------------------------------------------------------------------
# C1. HI-RES SOURCE WITH OVERLAPPING SCALES (numpy loft on v2's section curves) + NORMAL bake
# ----------------------------------------------------------------------------------------------
def section_np(P, t, phis):
    """Vectorised v2.section_point for one ring: returns (y, z) arrays and the section numbers."""
    zt, zb, w = v2.section(P, t)
    c, s = np.cos(phis), np.sin(phis)
    p = P["sec_exp"]
    zc = 0.5 * (zt + zb)
    hu, hl = zt - zc, zc - zb
    cz = np.sign(c) * np.abs(c) ** p
    sy = np.sign(s) * np.abs(s) ** p
    z = zc + np.where(c >= 0, hu, hl) * cz
    y = w * sy * (1.0 - P["belly_taper"] * np.maximum(0.0, -c))
    return y, z, zt, zb, w, c, s


def hires_scaled_body(name, P, cell, height):
    """Dense loft of the analytic body, displaced along its normal by an overlapping-scale height
    field (staggered rows of discs, the most anterior disc wins, height rising to the free edge).
    Returns (object, max_height). A float point attribute `h` holds height/max for the EMIT bake."""
    L = P["length_m"]
    Lb = v2.body_len(P)
    probe = np.linspace(0.02, 1.0, 40)
    circ = []
    for t in probe:
        y, z, *_ = section_np(P, t, np.linspace(0.0, 2.0 * math.pi, 181))
        circ.append(float(np.sum(np.hypot(np.diff(y), np.diff(z)))))
    circ_ref = max(circ)
    N_rows = max(16, int(round(circ_ref / cell)))
    spacing = min(max(cell / 5.0, 0.0003), 0.0012)
    n_t = int(min(700, max(120, Lb / spacing)))
    n_phi = int(min(520, max(96, circ_ref / spacing)))
    ts = np.linspace(0.003, 1.0, n_t)
    phis = np.linspace(0.0, 2.0 * math.pi, n_phi, endpoint=False)
    pos = np.zeros((n_t, n_phi, 3), dtype=np.float64)
    radius = np.zeros(n_t)
    gill_t, mouth_t = P["head_len"], P["mouth_t"]
    for i, t in enumerate(ts):
        y, z, zt, zb, w, c, s = section_np(P, t, phis)
        zc = 0.5 * (zt + zb)
        sc = 1.0
        sc -= P["mouth_notch"] * max(0.0, 1.0 - abs(t - mouth_t) / 0.02) ** 2
        sc -= P["gill_inset"] * max(0.0, 1.0 - abs(t - gill_t) / 0.014) ** 2
        y, z = y * sc, zc + (z - zc) * sc
        x = np.full(n_phi, -t * Lb)
        if t < mouth_t * 1.6 and P["jaw_proj"] > 0:
            x = x + P["jaw_proj"] * L * np.maximum(0.0, -c) ** 1.5 * (1.0 - t / (mouth_t * 1.6))
        gb = max(0.0, 1.0 - abs(t - gill_t) / 0.014) ** 2
        x = x - P["gill_bulge"] * L * np.abs(s) ** 1.4 * gb
        pos[i, :, 0], pos[i, :, 1], pos[i, :, 2] = x, y, z
        yy, zz = np.append(y, y[0]), np.append(z, z[0])
        radius[i] = float(np.sum(np.hypot(np.diff(yy), np.diff(zz)))) / (2.0 * math.pi)
    # normals from the parametric grid (periodic in phi)
    dt = np.gradient(pos, axis=0)
    dp = (np.roll(pos, -1, axis=1) - np.roll(pos, 1, axis=1)) * 0.5
    nrm = np.cross(dp, dt)
    nl = np.linalg.norm(nrm, axis=2, keepdims=True)
    nrm = nrm / np.maximum(nl, 1e-12)
    # outward check: the normal should point away from the ring centre
    cen = pos.mean(axis=1, keepdims=True)
    cen[..., 0] = pos[..., 0]
    flip = np.sum(nrm * (pos - cen), axis=2) < 0
    nrm[flip] *= -1.0
    # scale lattice: U (columns along the body, pitch = cell * local radius / reference radius),
    # V (rows around, N_rows per turn), rows staggered by half a column
    r_ref = circ_ref / (2.0 * math.pi)
    pitch = cell * np.clip(radius / r_ref, 0.22, 1.0)
    ds = np.diff(ts, prepend=ts[0]) * Lb
    U = np.cumsum(ds / pitch)
    V = phis / (2.0 * math.pi / N_rows)
    UU = U[:, None] * np.ones((1, n_phi))
    VV = np.ones((n_t, 1)) * V[None, :]
    R = 0.80
    best_u = np.full((n_t, n_phi), np.inf)
    best_du = np.zeros((n_t, n_phi))
    best_dv = np.zeros((n_t, n_phi))
    row0 = np.floor(VV)
    for dr in (-1, 0, 1):
        row = row0 + dr
        stag = 0.5 * np.mod(row, 2)
        Us = UU + stag
        col0 = np.floor(Us)
        for dc in (-1, 0, 1):
            col = col0 + dc
            cu, cv = col + 0.5, row + 0.5
            du, dv = Us - cu, VV - cv
            inside = (du * du + dv * dv) < R * R
            cu_abs = cu - stag
            take = inside & (cu_abs < best_u)
            best_u = np.where(take, cu_abs, best_u)
            best_du = np.where(take, du, best_du)
            best_dv = np.where(take, dv, best_dv)
    rise = np.clip(0.5 + best_du / (2.0 * R), 0.0, 1.0)
    h = (0.25 + 0.75 * rise) * (1.0 - 0.30 * (best_dv / R) ** 2)
    h = np.where(np.isfinite(best_u), h, 0.0)
    # no scales on the head, fade in behind the gill plate, fade out at the tail root
    tt = ts[:, None]
    mask = np.vectorize(lambda t: smoothstep(gill_t + 0.005, gill_t + 0.06, t) * smoothstep(1.0, 0.94, t))(ts)[:, None]
    h = h * mask
    # lateral line: a faint groove at mid-height on both flanks
    ll = np.exp(-((np.abs(VV / N_rows * 2.0 * math.pi - math.pi * 0.5) % math.pi) / 0.08) ** 2)
    ll = np.exp(-(((phis - math.pi * 0.5 + math.pi) % math.pi - math.pi * 0.5) / 0.07) ** 2)[None, :]
    h = h - 0.35 * ll * mask * (0.5 + 0.5 * np.ones_like(tt))
    hm = height
    disp = pos + nrm * (h * hm)
    # mesh
    verts = disp.reshape(-1, 3)
    idx = np.arange(n_t * n_phi).reshape(n_t, n_phi)
    a = idx[:-1, :]
    b = idx[1:, :]
    an = np.roll(a, -1, axis=1)
    bn = np.roll(b, -1, axis=1)
    quads = np.stack([a, an, bn, b], axis=2).reshape(-1, 4)
    nose_i = len(verts)
    tail_i = nose_i + 1
    zt, zb, _ = v2.section(P, 1.0)
    verts = np.vstack([verts, [[0.0, 0.0, 0.0]], [[-Lb - 0.01 * L, 0.0, 0.5 * (zt + zb)]]])
    faces = quads.tolist()
    for j in range(n_phi):
        jn = (j + 1) % n_phi
        faces.append([nose_i, int(idx[0, jn]), int(idx[0, j])])
        faces.append([tail_i, int(idx[-1, j]), int(idx[-1, jn])])
    me = bpy.data.meshes.new(f"hires_{name}")
    me.from_pydata(verts.tolist(), [], faces)
    me.update()
    me.shade_smooth()
    attr = me.attributes.new("h", "FLOAT", "POINT")
    hv = np.concatenate([np.clip(h.ravel(), 0.0, 1.0), [0.0, 0.0]]).astype(np.float32)
    attr.data.foreach_set("value", hv)
    ob = bpy.data.objects.new(f"hires_{name}", me)
    bpy.context.scene.collection.objects.link(ob)
    # emission material: height attribute (for the EMIT selected-to-active bake)
    m = bpy.data.materials.new(f"HiresH_{name}")
    m.use_nodes = True
    tr = m.node_tree
    for nd in list(tr.nodes):
        tr.nodes.remove(nd)
    at = tr.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "h"
    em = tr.nodes.new("ShaderNodeEmission")
    ou = tr.nodes.new("ShaderNodeOutputMaterial")
    tr.links.new(at.outputs["Fac"], em.inputs["Color"])
    tr.links.new(em.outputs[0], ou.inputs[0])
    me.materials.append(m)
    log(f"{name}: hi-res scale source {n_t}x{n_phi} rings/sides, {len(faces)} faces, {N_rows} scale rows, "
        f"spacing {spacing * 1000:.2f} mm, step {hm * 1000:.2f} mm")
    return ob, hm


def flat_emission_material(name, value):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    tr = m.node_tree
    for nd in list(tr.nodes):
        tr.nodes.remove(nd)
    em = tr.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (value, value, value, 1.0)
    ou = tr.nodes.new("ShaderNodeOutputMaterial")
    tr.links.new(em.outputs[0], ou.inputs[0])
    return m


def bake_normal_and_height(obj, mat, img_node, name, P, sources, out_dir):
    """Selected-to-active NORMAL bake (tangent space, +Y up) from the hi-res sources, then an EMIT
    bake of their height attribute. Saves <name>_normal.png and returns (normal_path, height array)."""
    scene = bpy.context.scene
    L = P["length_m"]
    extrusion, ray = 0.012 * L, 0.035 * L
    tree = mat.node_tree
    img = bpy.data.images.new(f"fish_{name}_normal", ATLAS, ATLAS, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img_node.image = img
    tree.nodes.active = img_node
    for o in scene.objects:
        o.select_set(False)
    for o in sources:
        o.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bk = scene.render.bake
    bk.use_selected_to_active = True
    bk.cage_extrusion = extrusion
    bk.max_ray_distance = ray
    bk.normal_space = "TANGENT"
    bk.normal_r, bk.normal_g, bk.normal_b = "POS_X", "POS_Y", "POS_Z"
    t = time.time()
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_selected_to_active=True,
                        cage_extrusion=extrusion, max_ray_distance=ray, margin=8, use_clear=True)
    log(f"{name}: normal bake {ATLAS}x{ATLAS} from {len(sources)} sources: {time.time() - t:.1f}s")
    px = np.empty(ATLAS * ATLAS * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(ATLAS, ATLAS, 4)
    # texels no ray reached: flat normal
    miss = px[..., 3] < 0.5
    px[miss, 0:3] = (0.5, 0.5, 1.0)
    normal_path = os.path.join(out_dir, f"fish_{name}_normal.png")
    save_png(normal_path, px[..., :3], None, ATLAS, noncolor=True)
    bpy.data.images.remove(img)
    log(f"{name}: normal map -> {normal_path} ({int(miss.sum())} texels unreached)")
    hpx = bake_emit_image(obj, mat, img_node, None, None, None, f"fish_{name}_height", sources=sources,
                          extrusion=extrusion, ray_dist=ray)
    bk.use_selected_to_active = False
    return normal_path, hpx


def compose_roughness(name, base, height, out_dir):
    """Roughness = baked base (by region and height on the body) + matte scale rims from the height
    map's gradient. Saves <name>_roughness.png (grey RGB)."""
    hgt = height[..., 0]
    valid = height[..., 3] > 0.5
    gy, gx = np.gradient(np.where(valid, hgt, 0.0))
    edge = np.clip(np.hypot(gx, gy) * 6.0, 0.0, 1.0)
    rough = base[..., 0] + ROUGH["scale_edge"] * edge
    rough = np.where(base[..., 3] > 0.5, rough, 0.5)
    rough = np.clip(rough, 0.03, 0.95)
    path = os.path.join(out_dir, f"fish_{name}_roughness.png")
    save_png(path, np.stack([rough, rough, rough], axis=2), None, ATLAS, noncolor=True)
    return path


def make_textured_material3(name, diffuse, normal, roughness, alpha=True, nstrength=1.0):
    """Principled BSDF with Base Color + Alpha (diffuse), Roughness (image) and Normal (Normal Map
    node, tangent space): what the FBX carries."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(diffuse, check_existing=False)
    tex.image.alpha_mode = "STRAIGHT"
    tex.location = (-600, 300)
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    if roughness:
        rt = tree.nodes.new("ShaderNodeTexImage")
        rt.image = bpy.data.images.load(roughness, check_existing=False)
        rt.image.colorspace_settings.name = "Non-Color"
        rt.location = (-600, 0)
        tree.links.new(rt.outputs["Color"], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = 0.35
    if normal:
        nt = tree.nodes.new("ShaderNodeTexImage")
        nt.image = bpy.data.images.load(normal, check_existing=False)
        nt.image.colorspace_settings.name = "Non-Color"
        nt.location = (-600, -300)
        nm = tree.nodes.new("ShaderNodeNormalMap")
        nm.space = "TANGENT"
        nm.inputs["Strength"].default_value = nstrength
        nm.location = (-300, -300)
        tree.links.new(nt.outputs["Color"], nm.inputs["Color"])
        tree.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.5
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.12
    mat.diffuse_color = (0.6, 0.6, 0.6, 1.0)
    return mat


# ----------------------------------------------------------------------------------------------
# FISH ASSEMBLY v3
# ----------------------------------------------------------------------------------------------
def build_fish3(name, P, textures_dir):
    """One mesh, one material with diffuse + normal + roughness. Returns (obj, info)."""
    L = P["length_m"]
    scene = bpy.context.scene
    bm = bmesh.new()
    lay = v2.attr_layers(bm)
    v2.build_body(P, lay, bm)
    me = bpy.data.meshes.new(f"fish_{name}_body")
    bm.to_mesh(me)
    bm.free()
    me.update()
    body = bpy.data.objects.new(f"fish_{name}_body", me)
    scene.collection.objects.link(body)
    me.uv_layers.new(name="UVMap")
    me.shade_smooth()
    v2.unwrap_body(body, set(range(len(me.polygons))))
    base_tris = v2.tri_count(me)

    bm2 = bmesh.new()
    lay2 = v2.attr_layers(bm2)
    uvs = {}
    rects = fin_rects3(P["fins"])
    with patched(v2, "fin_grid", fin_grid3):
        for fin in P["fins"]:
            k = fin["kind"]
            if k in ("dorsal", "dorsal2", "adipose", "anal"):
                v2.add_median_fin(bm2, lay2, P, fin, rects[k], uvs)
            elif k == "caudal":
                v2.add_caudal(bm2, lay2, P, fin, rects[k], uvs)
            elif k in ("pectoral", "pelvic"):
                v2.add_paddle(bm2, lay2, P, fin, +1.0, rects[k + "_L"], uvs)
                v2.add_paddle(bm2, lay2, P, fin, -1.0, rects[k + "_R"], uvs)
    add_eye3(bm2, lay2, P, +1.0, rects, uvs)
    add_eye3(bm2, lay2, P, -1.0, rects, uvs)
    if P.get("barbels"):
        v2.add_barbels(bm2, lay2, P, uvs, rects["barbel"])
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
    fin_tris = v2.tri_count(me2)
    fins_copy_mesh = me2.copy()          # exact copy for the bake source (flat normals on fins/eyes)

    subdiv_used = False
    if P.get("subdiv") and base_tris * 4 + fin_tris <= BUDGET3["fish_max"]:
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
    for o in scene.objects:
        o.select_set(False)
    body.select_set(True)
    fins.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    obj = body
    obj.name = f"fish_{name}"
    obj.data.name = f"fish_{name}"
    obj.data.shade_smooth()
    tris = v2.tri_count(obj.data)

    # procedural material: diffuse + alpha bake (v2), roughness base bake (v3)
    mat, img_node, alpha_sock, col_sock, bsdf, out_node, rough_sock = build_fish_material3(name, P)
    obj.data.materials.append(mat)
    diffuse = os.path.join(textures_dir, f"fish_{name}_diffuse.png")
    v2.bake_material(obj, mat, img_node, alpha_sock, col_sock, bsdf, out_node, diffuse)
    rough_base = bake_emit_image(obj, mat, img_node, rough_sock, bsdf, out_node, f"fish_{name}_roughbase")

    # hi-res scale source + copy of the fins/eyes, normal + height bakes
    sc = SCALES[name]
    hires, hmax = hires_scaled_body(name, P, sc["cell"], sc["height"])
    fcopy = bpy.data.objects.new(f"fincopy_{name}", fins_copy_mesh)
    scene.collection.objects.link(fcopy)
    fins_copy_mesh.materials.append(flat_emission_material(f"FlatH_{name}", 0.5))
    normal_png, height = bake_normal_and_height(obj, mat, img_node, name, P, [hires, fcopy], textures_dir)
    rough_png = compose_roughness(name, rough_base, height, textures_dir)
    bpy.data.objects.remove(hires, do_unlink=True)
    bpy.data.objects.remove(fcopy, do_unlink=True)

    tex_mat = make_textured_material3(f"FishSkin_{name}", diffuse, normal_png, rough_png)
    obj.data.materials.clear()
    obj.data.materials.append(tex_mat)
    bpy.data.materials.remove(mat)
    info = dict(triangles=tris, subdiv=subdiv_used, body_tris_before_subdiv=base_tris, fin_eye_tris=fin_tris,
                textures=dict(diffuse=diffuse, normal=normal_png, roughness=rough_png))
    return obj, info


# ----------------------------------------------------------------------------------------------
# A. SPRITES
# ----------------------------------------------------------------------------------------------
def transparent_render(scene, path, w, h, samples):
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.cycles.samples = samples
    try:
        scene.view_settings.look = "None"
    except TypeError:
        pass
    v2.render_to(scene, path)


def alpha_bounds(path):
    from PIL import Image
    a = np.array(Image.open(path).convert("RGBA"))[..., 3]
    ys, xs = np.where(a > 8)
    if len(xs) == 0:
        return None
    return dict(x0=int(xs.min()), y0=int(ys.min()), x1=int(xs.max()) + 1, y1=int(ys.max()) + 1)


def render_sprites(scene, obj, name, P, sprites_dir, samples):
    """Side view facing right (nose = +X on the right), transparent, 512x192, the fish filling 92 %
    of the width unless its height limits it; and a 96x96 icon of the head and front body."""
    L = P["length_m"]
    lo, hi = v2.bounds([obj])
    dx, dz = hi.x - lo.x, hi.z - lo.z
    W, H, fill = SPRITE["side_w"], SPRITE["side_h"], SPRITE["fill"]
    px_per_m = min(fill * W / dx, fill * H / dz)
    ortho = W / px_per_m
    v2.clear_studio(scene, {obj})
    v2.studio(scene, [obj], Vector((0.0, -1.0, 0.0)), samples, ortho_scale=ortho, ground=False,
              up=Vector((0.0, 0.0, 1.0)))
    side_path = os.path.join(sprites_dir, f"{name}_side.png")
    transparent_render(scene, side_path, W, H, samples)
    cx, cz = 0.5 * (lo.x + hi.x), 0.5 * (lo.z + hi.z)
    nose_px = (0.5 * W + (0.0 - cx) * px_per_m, 0.5 * H - (0.0 - cz) * px_per_m)
    b = alpha_bounds(side_path)
    # icon: a square window with the nose 6 % in from the right edge
    win = max(dz * 1.12, 0.52 * L)
    icx = -0.44 * win
    icz = cz
    frame = ((icx - 0.5 * win, lo.y, icz - 0.5 * win), (icx + 0.5 * win, hi.y, icz + 0.5 * win))
    v2.clear_studio(scene, {obj})
    v2.studio(scene, [obj], Vector((0.0, -1.0, 0.0)), samples, ortho_scale=win, ground=False,
              up=Vector((0.0, 0.0, 1.0)), frame=frame)
    icon_path = os.path.join(sprites_dir, f"{name}_icon.png")
    transparent_render(scene, icon_path, SPRITE["icon"], SPRITE["icon"], samples)
    v2.clear_studio(scene, {obj})
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGB"
    return dict(
        side=dict(file=os.path.basename(side_path), w=W, h=H, bounds_px=b, px_per_m=round(px_per_m, 2),
                  nose_px=[round(nose_px[0], 1), round(nose_px[1], 1)],
                  length_px=round(L * px_per_m, 1), fish_bbox_m=[round(dx, 4), round(dz, 4)]),
        icon=dict(file=os.path.basename(icon_path), w=SPRITE["icon"], h=SPRITE["icon"],
                  px_per_m=round(SPRITE["icon"] / win, 2), window_m=round(win, 4), bounds_px=alpha_bounds(icon_path)),
        length_m=L, facing="right",
    )


def sprite_sheet(sprites_dir, entries, path):
    """Contact sheet of the sprites (Pillow): one row per species on a dark-green UI-like ground."""
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    except Exception:
        font = ImageFont.load_default()
    names = [n for n in FISH_NAMES if n in entries]
    W, H = SPRITE["side_w"], SPRITE["side_h"]
    pad, label_w = 12, 150
    sheet = Image.new("RGBA", (pad + label_w + W + pad + SPRITE["icon"] + pad, pad + len(names) * (H + pad)),
                      (28, 42, 36, 255))
    d = ImageDraw.Draw(sheet)
    y = pad
    for n in names:
        e = entries[n]
        side = Image.open(os.path.join(sprites_dir, e["side"]["file"])).convert("RGBA")
        icon = Image.open(os.path.join(sprites_dir, e["icon"]["file"])).convert("RGBA")
        d.rectangle([pad + label_w, y, pad + label_w + W, y + H], outline=(70, 90, 80, 255))
        sheet.alpha_composite(side, (pad + label_w, y))
        b = e["side"]["bounds_px"]
        if b:
            d.rectangle([pad + label_w + b["x0"], y + b["y0"], pad + label_w + b["x1"] - 1, y + b["y1"] - 1],
                        outline=(120, 200, 140, 160))
        sheet.alpha_composite(icon, (pad + label_w + W + pad, y + (H - SPRITE["icon"]) // 2))
        d.text((pad, y + 10), n, fill=(230, 230, 220, 255), font=font)
        d.text((pad, y + 36), f"{e['length_m']:.2f} m", fill=(200, 200, 190, 255), font=font)
        d.text((pad, y + 60), f"{e['side']['px_per_m']:.0f} px/m", fill=(170, 170, 160, 255), font=font)
        y += H + pad
    sheet.save(path)
    return path


# ----------------------------------------------------------------------------------------------
# B. TROUT ANIMATION: two actions on the 7-bone rig, animated FBX, re-import check, swim strip
# ----------------------------------------------------------------------------------------------
def make_actions(armob):
    """Swim: 30-frame travelling sine wave (yaw about the bone's local Z = world vertical, amplitude
    2 deg at body1 to 25 deg at the tail, 0.6 rad lag per bone). Bend: poses k=-1,0,+1 at frames
    1/15/30, bones body1..peduncle each k*6 deg (= TroutView.setBend(view, k))."""
    scene = bpy.context.scene
    scene.render.fps = SWIM["fps"]
    scene.frame_start, scene.frame_end = 1, SWIM["frames"]
    bpy.context.view_layer.objects.active = armob
    for o in scene.objects:
        o.select_set(o is armob)
    bpy.ops.object.mode_set(mode="POSE")
    for pb in armob.pose.bones:
        pb.rotation_mode = "XYZ"
    armob.animation_data_create()
    names = v2.BONE_NAMES
    swim = bpy.data.actions.new("Swim")
    armob.animation_data.action = swim
    n = SWIM["frames"]
    for f in range(1, n + 1):
        phase = 2.0 * math.pi * (f - 1) / n
        for i, bn in enumerate(names):
            pb = armob.pose.bones[bn]
            amp = math.radians(SWIM["amp_deg"][i])
            pb.rotation_euler = (0.0, 0.0, amp * math.sin(phase - SWIM["lag_rad"] * max(0, i - 1)))
            pb.keyframe_insert("rotation_euler", frame=f)
    swim.use_frame_range = True
    swim.frame_start, swim.frame_end = 1, n
    swim.use_cyclic = True
    bend = bpy.data.actions.new("Bend")
    armob.animation_data.action = bend
    for f, k in zip(BEND["frames"], BEND["k"]):
        for i, bn in enumerate(names):
            pb = armob.pose.bones[bn]
            ang = math.radians(BEND["deg_per_bone"]) * k if i in BEND["bones"] else 0.0
            pb.rotation_euler = (0.0, 0.0, ang)
            pb.keyframe_insert("rotation_euler", frame=f)
    bend.use_frame_range = True
    bend.frame_start, bend.frame_end = BEND["frames"][0], BEND["frames"][-1]
    for pb in armob.pose.bones:
        pb.rotation_euler = (0.0, 0.0, 0.0)
    armob.animation_data.action = swim
    bpy.ops.object.mode_set(mode="OBJECT")
    return swim, bend


def export_fbx3(scene, objs, path_abs, anim=False):
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
        bake_anim=anim, bake_anim_use_all_actions=anim, bake_anim_use_nla_strips=False,
        bake_anim_use_all_bones=True, bake_anim_force_startend_keying=True,
        bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
    )


def verify_animated_fbx(path):
    """Fresh scene, import, list actions + frame ranges, prove the mesh deforms (tail vertex at
    frame 1 vs 15 under each action). Returns a dict for the manifest."""
    scene = v2.new_scene()
    bpy.ops.import_scene.fbx(filepath=path)
    arm = [o for o in scene.objects if o.type == "ARMATURE"]
    mesh = [o for o in scene.objects if o.type == "MESH"]
    out = dict(file=path, armatures=[o.name for o in arm], meshes=[o.name for o in mesh],
               bones=[b.name for b in arm[0].data.bones] if arm else [], actions=[])
    acts = list(bpy.data.actions)
    for a in acts:
        out["actions"].append(dict(name=a.name, frame_range=[round(a.frame_range[0], 1), round(a.frame_range[1], 1)]))
    if arm and mesh:
        ob = arm[0]
        me = mesh[0]
        if ob.animation_data is None:
            ob.animation_data_create()
        tail_i = min(range(len(me.data.vertices)), key=lambda i: me.data.vertices[i].co.x)
        dg = bpy.context.evaluated_depsgraph_get()
        for a in acts:
            ob.animation_data.action = a
            if a.slots and ob.animation_data.action_slot is None:
                ob.animation_data.action_slot = a.slots[0]
            pos = {}
            for f in (1, 15):
                scene.frame_set(f)
                dg = bpy.context.evaluated_depsgraph_get()
                ev = me.evaluated_get(dg)
                co = ev.matrix_world @ ev.data.vertices[tail_i].co
                pos[f] = [round(c, 5) for c in co]
            moved = math.dist(pos[1], pos[15])
            for d in out["actions"]:
                if d["name"] == a.name:
                    d.update(tail_vertex_frame1=pos[1], tail_vertex_frame15=pos[15], tail_moved_m=round(moved, 5))
            log(f"verify {os.path.basename(path)}: action {a.name} range {tuple(a.frame_range)} "
                f"tail vertex f1 {pos[1]} f15 {pos[15]} moved {moved * 1000:.1f} mm")
    return out


def render_swim_strip(scene, obj, armob, previews, samples, swim):
    """Six frames of the Swim loop, top view (nose right) over a 3/4 view, stitched with Pillow."""
    from PIL import Image, ImageDraw, ImageFont
    armob.animation_data.action = swim
    frames = [1, 6, 11, 16, 21, 26]
    tiles = []
    w, h = 400, 300
    for vk, vd, up in (("top", Vector((0.0, 0.0, 1.0)), Vector((0.0, 1.0, 0.0))),
                       ("34", v2.VIEW_DIRS["34"], None)):
        for f in frames:
            scene.frame_set(f)
            v2.clear_studio(scene, {obj, armob})
            lo, hi = v2.bounds([obj])
            frame = ((-0.42, -0.12, lo.z), (0.03, 0.12, hi.z))
            v2.studio(scene, [obj], vd, samples, ground=vk == "34", up=up, frame=frame,
                      ortho_scale=0.48 if vk == "top" else None)
            scene.render.resolution_x, scene.render.resolution_y = w, h
            scene.cycles.samples = samples
            p = os.path.join(previews, f"_swim_{vk}_{f:02d}.png")
            v2.render_to(scene, p)
            tiles.append((vk, f, p))
    v2.clear_studio(scene, {obj, armob})
    scene.frame_set(1)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    except Exception:
        font = ImageFont.load_default()
    strip = Image.new("RGB", (len(frames) * w, 2 * h), (60, 66, 74))
    d = ImageDraw.Draw(strip)
    for vk, f, p in tiles:
        row = 0 if vk == "top" else 1
        col = frames.index(f)
        strip.paste(Image.open(p).convert("RGB"), (col * w, row * h))
        d.text((col * w + 8, row * h + 6), f"Swim f{f} ({vk})", fill=(240, 240, 230), font=font)
        os.remove(p)
    path = os.path.join(previews, "trout_swim_strip.png")
    strip.save(path)
    return path


# ----------------------------------------------------------------------------------------------
# FISH DRIVER
# ----------------------------------------------------------------------------------------------
def generate_fish3(name, P, exports, previews, sprites_dir, views, do_fbx, do_render, samples, do_anim,
                   do_sprites, do_closeup):
    scene = v2.new_scene()
    t0 = time.time()
    obj, info = build_fish3(name, P, exports)
    dims = tuple(round(v, 4) for v in obj.dimensions)
    log(f"{name}: {info['triangles']} tris (body {info['body_tris_before_subdiv']} x4 subdiv={info['subdiv']}, "
        f"fins+eyes {info['fin_eye_tris']}), dims {dims}, built+baked in {time.time() - t0:.1f}s")
    pngs = []
    if do_render:
        for vk in views:
            v2.clear_studio(scene, {obj})
            v2.studio(scene, [obj], v2.VIEW_DIRS[vk], samples)
            png = os.path.join(previews, f"fish_{name}_{vk}.png")
            t1 = time.time()
            v2.render_to(scene, png)
            log(f"{name}: rendered {vk} in {time.time() - t1:.1f}s -> {png}")
            pngs.append(png)
        if do_closeup:
            png = os.path.join(previews, "materials_closeup.png")
            render_closeup(scene, obj, P, png, samples)
            pngs.append(png)
        v2.clear_studio(scene, {obj})
    sprites = None
    if do_sprites:
        t1 = time.time()
        sprites = render_sprites(scene, obj, name, P, sprites_dir, max(32, samples // 2))
        log(f"{name}: sprites in {time.time() - t1:.1f}s -> {sprites['side']['file']}, {sprites['icon']['file']}")
    fbx = rigged = animated = None
    bones = []
    anim_info = None
    if do_fbx:
        fbx = os.path.join(exports, f"fish_{name}.fbx")
        export_fbx3(scene, [obj], fbx)
        if name == "trout" and do_anim:
            armob = v2.add_armature(obj, P)
            bones = v2.BONE_NAMES[:]
            swim, bend = make_actions(armob)
            animated = os.path.join(exports, "fish_trout_animated.fbx")
            export_fbx3(scene, [obj, armob], animated, anim=True)
            log(f"trout: animated FBX -> {animated}")
            if do_render:
                strip = render_swim_strip(scene, obj, armob, previews, samples, swim)
                pngs.append(strip)
                log(f"trout: swim strip -> {strip}")
            anim_info = verify_animated_fbx(animated)
    return dict(
        preset=name, kind="fish", length_m=P["length_m"], triangles=info["triangles"],
        subdiv_applied=info["subdiv"], dimensions_m=list(dims), rings=P["rings"], sides=P["sides"],
        textures=info["textures"], scales=SCALES[name], fbx=fbx, fbx_animated=animated, bones=bones,
        animation=anim_info, previews=pngs, sprites=sprites, forward_axis="FBX +X (Roblox RightVector)",
    )


def render_closeup(scene, obj, P, path, samples):
    """2x zoom on the flank with a raking light so the scale normal map catches it."""
    L = P["length_m"]
    lo, hi = v2.bounds([obj])
    frame = ((-0.62 * L, lo.y, lo.z + 0.25 * (hi.z - lo.z)), (-0.18 * L, hi.y, lo.z + 0.85 * (hi.z - lo.z)))
    v2.clear_studio(scene, {obj})
    v2.studio(scene, [obj], Vector((0.30, -1.0, 0.30)), samples, ground=False, frame=frame, lens=85.0)
    # raking light from behind-above the flank
    ld = bpy.data.lights.new("Rake", "AREA")
    ld.energy = 25.0 * L * L * 40.0
    ld.size = 0.4 * L
    ld.color = (1.0, 0.95, 0.85)
    lo_ = bpy.data.objects.new("Rake", ld)
    scene.collection.objects.link(lo_)
    centre = Vector(((frame[0][0] + frame[1][0]) * 0.5, 0.0, (frame[0][2] + frame[1][2]) * 0.5))
    d = Vector((-0.9, -0.5, 0.35)).normalized()
    lo_.location = centre + d * (1.2 * L)
    lo_.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    v2.render_to(scene, path)
    v2.clear_studio(scene, {obj})
    return path


# ----------------------------------------------------------------------------------------------
# D. PROPS: helpers
# ----------------------------------------------------------------------------------------------
class PB3(v2.PropBuilder):
    """v2.PropBuilder + tubes along polylines, dished plates, spheres and thin strips."""

    def tube(self, pts, r, region, segs=6, caps=True, r_end=None, smooth=True):
        pts = [Vector(p) for p in pts]
        n = len(pts)
        radii = [r] * n if r_end is None else [r + (r_end - r) * i / (n - 1) for i in range(n)]
        rings = []
        ref = None
        for i in range(n):
            if i == 0:
                tan = (pts[1] - pts[0]).normalized()
            elif i == n - 1:
                tan = (pts[-1] - pts[-2]).normalized()
            else:
                tan = (pts[i + 1] - pts[i - 1]).normalized()
            if ref is None:
                ref = Vector((0.0, 0.0, 1.0)) if abs(tan.z) < 0.9 else Vector((1.0, 0.0, 0.0))
            u = (ref - tan * ref.dot(tan)).normalized()
            w = tan.cross(u).normalized()
            ref = u
            ring = []
            for j in range(segs):
                a = 2.0 * math.pi * j / segs
                v = self.bm.verts.new(pts[i] + (u * math.cos(a) + w * math.sin(a)) * radii[i])
                v[self.lay] = PR[region]
                ring.append(v)
            rings.append(ring)
        faces = []
        for i in range(n - 1):
            a_, b_ = rings[i], rings[i + 1]
            for j in range(segs):
                f = self.bm.faces.new((a_[j], b_[j], b_[(j + 1) % segs], a_[(j + 1) % segs]))
                f.smooth = smooth
                faces.append(f)
        if caps:
            for ring, flip in ((rings[0], True), (rings[-1], False)):
                f = self.bm.faces.new(list(reversed(ring)) if flip else ring)
                f.smooth = False
                faces.append(f)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        return faces

    def sphere(self, centre, r, region, u=10, v=7):
        mtx = Matrix.Translation(Vector(centre)) @ Matrix.Diagonal((r, r, r, 1.0))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0, matrix=mtx)
        faces = self._tag(res["verts"], region)
        for f in faces:
            f.smooth = True
        return faces

    def plate(self, origin, axis_l, axis_w, length, width_fn, th, region_top, region_bot, rows=9, cols=5,
              dish=0.0, bow=0.0, dish_dir=None):
        """Two-sided curved plate: rows along axis_l (s 0..1), cols across axis_w (c -1..1),
        half-width width_fn(s); dish bends it across, bow along; both towards dish_dir."""
        origin, al, aw = Vector(origin), Vector(axis_l).normalized(), Vector(axis_w).normalized()
        nrm = al.cross(aw).normalized() if dish_dir is None else Vector(dish_dir).normalized()
        top, bot = [], []
        for ri in range(rows):
            s = ri / (rows - 1)
            trow, brow = [], []
            for ci in range(cols):
                c = 2.0 * ci / (cols - 1) - 1.0
                base = origin + al * (s * length) + aw * (c * width_fn(s))
                off = nrm * (dish * (1.0 - c * c) * (1.0 - (2 * s - 1) ** 2) ** 0.5 + bow * (1.0 - (2 * s - 1) ** 2))
                p = base + off
                vt = self.bm.verts.new(p + nrm * (0.5 * th))
                vb = self.bm.verts.new(p - nrm * (0.5 * th))
                vt[self.lay] = PR[region_top]
                vb[self.lay] = PR[region_bot]
                trow.append(vt)
                brow.append(vb)
            top.append(trow)
            bot.append(brow)
        faces = []
        for ri in range(rows - 1):
            for ci in range(cols - 1):
                faces.append(self.bm.faces.new((top[ri][ci], top[ri][ci + 1], top[ri + 1][ci + 1], top[ri + 1][ci])))
                faces.append(self.bm.faces.new((bot[ri][ci], bot[ri + 1][ci], bot[ri + 1][ci + 1], bot[ri][ci + 1])))
        rim = []
        for ci in range(cols - 1):
            rim.append(((0, ci + 1), (0, ci)))
            rim.append(((rows - 1, ci), (rows - 1, ci + 1)))
        for ri in range(rows - 1):
            rim.append(((ri, 0), (ri + 1, 0)))
            rim.append(((ri + 1, cols - 1), (ri, cols - 1)))
        for (ra, ca), (rb, cb) in rim:
            if top[ra][ca] is top[rb][cb]:
                continue
            try:
                faces.append(self.bm.faces.new((top[ra][ca], bot[ra][ca], bot[rb][cb], top[rb][cb])))
            except ValueError:
                pass
        for f in faces:
            f.smooth = True
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        return faces

    def strip(self, p0, p1, width_dir, width, region, taper=0.3):
        """A thin two-sided strip (one quad each side) from p0 to p1: hackle fibre, tail, wing."""
        p0, p1, wd = Vector(p0), Vector(p1), Vector(width_dir).normalized()
        a = p0 + wd * (0.5 * width)
        b = p0 - wd * (0.5 * width)
        c = p1 - wd * (0.5 * width * taper)
        d = p1 + wd * (0.5 * width * taper)
        vs = [self.bm.verts.new(p) for p in (a, b, c, d)]
        for v in vs:
            v[self.lay] = PR[region]
        f1 = self.bm.faces.new(vs)
        f2 = self.bm.faces.new(list(reversed(vs)))
        f1.smooth = f2.smooth = False
        return [f1, f2]

    def treble(self, top, shank, bend_r, wire, region="hook", n_bends=3, segs=5):
        """Treble hook: shank down -Z from `top`, then n bends curving out and up to a point."""
        top = Vector(top)
        bottom = top + Vector((0.0, 0.0, -shank))
        self.tube([top, bottom], wire, region, segs=segs)
        self.sphere(top, wire * 1.6, region, u=6, v=4)                     # eye blob
        for k in range(n_bends):
            a0 = 2.0 * math.pi * k / n_bends + (0.0 if n_bends > 1 else 0.0)
            d = Vector((math.cos(a0), math.sin(a0), 0.0))
            c = bottom + d * bend_r
            pts = []
            for i in range(11):
                a = 1.32 * math.pi * i / 10
                pts.append(c - d * (bend_r * math.cos(a)) - Vector((0.0, 0.0, bend_r * math.sin(a))))
            self.tube(pts, wire, region, segs=segs, r_end=wire * 0.18)
        return bottom.z - bend_r

    def transformed(self, mtx):
        """Returns a helper that maps points through mtx (for the open tackle-box lid)."""
        return lambda p: (mtx @ Vector(p).to_4d()).to_3d()


def split_ring(b, centre, R, r, axis=(0.0, 1.0, 0.0), region="nickel"):
    return b.torus(centre, axis, R, r, region, segs=12, rings=5)


# ----------------------------------------------------------------------------------------------
# D. ROD + a real spinning reel (spool with line wrap, bail wire, crank with knob, foot in the seat)
# ----------------------------------------------------------------------------------------------
ROD_STATIONS = [(0.0, 0.012, "dark"), (0.02, 0.012, "dark"), (0.02, 0.013, "cork"), (0.26, 0.013, "cork"),
                (0.26, 0.011, "graphite"), (0.30, 0.011, "graphite"), (0.30, 0.0125, "metal"), (0.32, 0.0125, "metal"),
                (0.32, 0.011, "graphite"), (0.44, 0.011, "graphite"), (0.44, 0.0125, "metal"), (0.46, 0.0125, "metal"),
                (0.46, 0.012, "cork"), (0.58, 0.012, "cork"), (0.58, 0.0075, "graphite"), (0.80, 0.0062, "graphite"),
                (1.05, 0.0050, "graphite"), (1.30, 0.0040, "graphite"), (1.55, 0.0031, "graphite"),
                (1.80, 0.0023, "graphite"), (2.0, 0.0018, "graphite"), (2.1, 0.0015, "graphite")]


def blank_radius(x):
    st = ROD_STATIONS
    for (x0, r0, _), (x1, r1, _) in zip(st, st[1:]):
        if x0 <= x <= x1 and x1 > x0:
            return r0 + (r1 - r0) * (x - x0) / (x1 - x0)
    return 0.0015


def add_reel(b, xr=0.38):
    """Spinning reel hanging under the reel seat (x 0.32..0.44). Spool axis along +X."""
    zb = -(blank_radius(xr) + 0.002)                # underside of the blank
    # foot: a flat plate in the seat, its ends under the two hood rings
    b.box((xr, 0.0, zb - 0.0015), (0.118, 0.014, 0.003), "dark")
    b.box((xr, 0.0, zb - 0.006), (0.030, 0.010, 0.008), "dark")                     # foot boss
    # stem: curved leg down to the gear body
    b.tube([(xr, 0.0, zb - 0.008), (xr - 0.004, 0.0, zb - 0.028), (xr - 0.010, 0.0, zb - 0.050)],
           0.0055, "dark", segs=8, r_end=0.0085)
    zc = zb - 0.072                                 # spool axis height
    # gear body: rounded housing along X, rear cap, side plate with screws
    b.cyl((xr - 0.028, 0.0, zc), (xr + 0.012, 0.0, zc), 0.023, None, "dark", segs=16)
    b.cyl((xr - 0.036, 0.0, zc), (xr - 0.028, 0.0, zc), 0.016, 0.021, "dark", segs=16)
    b.cyl((xr - 0.008, -0.0232, zc), (xr - 0.008, -0.026, zc), 0.012, None, "graphite", segs=12)  # side plate
    # rotor with two arms reaching forward to the bail pivots
    b.cyl((xr + 0.012, 0.0, zc), (xr + 0.026, 0.0, zc), 0.0215, None, "graphite", segs=16)
    for sy in (1.0, -1.0):
        b.box((xr + 0.040, sy * 0.021, zc), (0.030, 0.007, 0.012), "graphite")
        b.cyl((xr + 0.052, sy * 0.021, zc), (xr + 0.058, sy * 0.021, zc), 0.005, None, "dark", segs=8)  # pivot
    # spool: core, back flange, front lip, and the LINE WRAP as a stack of tori
    b.cyl((xr + 0.030, 0.0, zc), (xr + 0.072, 0.0, zc), 0.0125, None, "metal", segs=16)
    b.cyl((xr + 0.030, 0.0, zc), (xr + 0.034, 0.0, zc), 0.0185, None, "metal", segs=16)   # back flange
    b.cyl((xr + 0.068, 0.0, zc), (xr + 0.0735, 0.0, zc), 0.0185, None, "metal", segs=16)  # front lip
    x = xr + 0.0365
    while x < xr + 0.0665:
        b.torus((x, 0.0, zc), (1.0, 0.0, 0.0), 0.0160, 0.0016, "line", segs=16, rings=5)
        x += 0.0032
    b.cyl((xr + 0.0735, 0.0, zc), (xr + 0.079, 0.0, zc), 0.009, 0.006, "dark", segs=12)   # drag knob
    b.cyl((xr + 0.079, 0.0, zc), (xr + 0.082, 0.0, zc), 0.004, None, "metal", segs=8)
    # bail wire: a bent cylinder from the line roller (+Y arm) over the front of the spool to -Y
    pts = []
    for i in range(15):
        a = math.pi * i / 14
        pts.append((xr + 0.060 + 0.006 * math.sin(a), 0.026 * math.cos(a), zc + 0.026 * math.sin(a)))
    b.tube(pts, 0.0013, "metal", segs=6)
    b.cyl((xr + 0.058, 0.021, zc), (xr + 0.066, 0.023, zc), 0.0042, None, "metal", segs=8)   # line roller
    b.cyl((xr + 0.056, -0.021, zc), (xr + 0.064, -0.026, zc), 0.003, None, "dark", segs=6)   # bail arm lever
    # crank: shaft out of the -Y side plate, arm, knob on a stub
    b.cyl((xr - 0.008, -0.026, zc), (xr - 0.008, -0.036, zc), 0.0035, None, "metal", segs=8)
    arm_len = 0.048
    ang = math.radians(35.0)
    ax, az = -math.sin(ang) * arm_len, math.cos(ang) * arm_len
    rot = Matrix.Rotation(-ang, 4, "Y")
    b.box((xr - 0.008 + 0.5 * ax, -0.038, zc + 0.5 * az), (0.008, 0.004, arm_len), "metal", rot=rot)
    kx, kz = xr - 0.008 + ax, zc + az
    b.cyl((kx, -0.038, kz), (kx, -0.060, kz), 0.0028, None, "metal", segs=6)
    b.cyl((kx, -0.044, kz), (kx, -0.064, kz), 0.0075, 0.0065, "rubber", segs=10)
    b.sphere((kx, -0.064, kz), 0.0065, "rubber", u=10, v=6)
    # anti-reverse switch under the body
    b.box((xr - 0.030, 0.0, zc - 0.024), (0.010, 0.006, 0.006), "dark")


def build_rod3(name):
    b = PB3()
    b.loft(ROD_STATIONS, None, segs=10)
    guides = [(0.72, 0.020), (0.98, 0.015), (1.24, 0.011), (1.50, 0.008), (1.74, 0.0065), (1.94, 0.0055)]
    for x, R in guides:
        rb = blank_radius(x)
        zc = -(rb + 0.004 + R)
        b.torus((x, 0.0, zc), (1.0, 0.0, 0.0), R, 0.0011, "metal", segs=10, rings=5)
        b.box((x, 0.0, -(rb + 0.002)), (0.03, 0.004, 0.004), "dark")
        b.cyl((x, 0.0, -(rb + 0.002)), (x, 0.0, zc + R), 0.0012, None, "metal", segs=6)
    Lr = 2.1
    rb = blank_radius(Lr)
    b.torus((Lr, 0.0, -(rb + 0.0045)), (1.0, 0.0, 0.0), 0.0045, 0.0009, "metal", segs=10, rings=5)
    b.cyl((Lr - 0.012, 0.0, 0.0), (Lr - 0.012, 0.0, -(rb + 0.002)), 0.0012, None, "metal", segs=6)
    add_reel(b)
    return b.finish(name)


# ----------------------------------------------------------------------------------------------
# D. LURES
# ----------------------------------------------------------------------------------------------
def build_spinner(name):
    b = PB3()
    split_ring(b, (0.0, 0.0, -0.0027), 0.0022, 0.0005, region="nickel")              # line eye
    b.tube([(0.0, 0.0, -0.005), (0.0, 0.0, -0.047)], 0.0005, "nickel", segs=6)        # wire shaft
    b.torus((0.0, 0.0, -0.011), (0.0, 0.0, 1.0), 0.0016, 0.0004, "nickel", segs=8, rings=4)   # clevis
    # willow blade hanging from the clevis, 26 mm, dished, 28 deg off the shaft
    ang = math.radians(28.0)
    al = Vector((math.sin(ang), 0.0, -math.cos(ang)))
    aw = Vector((0.0, 1.0, 0.0))
    b.plate((0.0017, 0.0, -0.011), al, aw, 0.026, lambda s: 0.0045 * (s ** 0.55 * (1 - s) ** 0.85) / 0.33,
            0.0006, "brass", "brass", rows=11, cols=5, dish=-0.0012, dish_dir=al.cross(aw))
    for i, z in enumerate((-0.0155, -0.0195, -0.0235)):
        b.sphere((0.0, 0.0, z), 0.0020, "bead" if i == 1 else "nickel", u=8, v=5)
    b.cyl((0.0, 0.0, -0.0255), (0.0, 0.0, -0.040), 0.0032, 0.0022, "lead", segs=10)  # body
    for z in (-0.029, -0.034):
        b.torus((0.0, 0.0, z), (0.0, 0.0, 1.0), 0.0031, 0.0004, "nickel", segs=10, rings=4)  # body grooves
    split_ring(b, (0.0, 0.0, -0.0485), 0.0022, 0.0004, region="nickel")
    b.treble((0.0, 0.0, -0.0505), 0.0065, 0.0035, 0.00045)
    return b.finish(name)


def build_spoon(name):
    b = PB3()
    split_ring(b, (0.0, 0.0, -0.0035), 0.0030, 0.0005, region="nickel")
    b.torus((0.0, 0.0, -0.0075), (0.0, 0.0, 1.0), 0.0022, 0.0005, "nickel", segs=8, rings=4)  # blade eyelet
    al = Vector((0.0, 0.0, -1.0))
    aw = Vector((1.0, 0.0, 0.0))
    b.plate((0.0, 0.0, -0.0085), al, aw, 0.052,
            lambda s: 0.012 * math.sqrt(max(0.0, 1.0 - (2 * s - 1) ** 2)) ** 0.85 * (0.72 + 0.28 * s),
            0.0009, "nickel", "paint", rows=13, cols=7, dish=0.0035, bow=0.0045, dish_dir=(0.0, 1.0, 0.0))
    b.torus((0.0, 0.0, -0.0605), (0.0, 0.0, 1.0), 0.0022, 0.0005, "nickel", segs=8, rings=4)
    split_ring(b, (0.0, 0.0, -0.0635), 0.0026, 0.0004, region="nickel")
    b.treble((0.0, 0.0, -0.0655), 0.0010, 0.0038, 0.00045)
    return b.finish(name)


def build_fly(name):
    b = PB3()
    w = 0.00025
    b.torus((-0.0009, 0.0, 0.0), (0.0, 0.0, 1.0), 0.0009, w, "hook", segs=8, rings=4)      # hook eye
    b.tube([(-0.0018, 0.0, 0.0), (-0.0128, 0.0, 0.0)], w, "hook", segs=5)                  # shank
    rb = 0.0028
    c = Vector((-0.0128, 0.0, -rb))
    pts = []
    for i in range(13):
        a = 1.40 * math.pi * i / 12
        pts.append(c + Vector((-rb * math.sin(a), 0.0, rb * math.cos(a))))
    b.tube(pts, w, "hook", segs=5, r_end=w * 0.2)                                           # bend + point
    b.cyl((-0.0045, 0.0, 0.0), (-0.0125, 0.0, 0.0), 0.0009, 0.0013, "thread", segs=8)       # ribbed body
    b.cyl((-0.0028, 0.0, 0.0), (-0.0046, 0.0, 0.0), 0.0014, 0.0012, "dark", segs=8)         # thorax
    for i in range(20):                                                                    # hackle collar
        a = 2.0 * math.pi * i / 20 + 0.1
        d = Vector((-0.45, math.cos(a), math.sin(a))).normalized()
        p0 = Vector((-0.0030, 0.0, 0.0)) + Vector((0.0, math.cos(a), math.sin(a))) * 0.0012
        wd = Vector((0.0, -math.sin(a), math.cos(a)))
        b.strip(p0, p0 + d * 0.0048, wd, 0.00035, "hackle", taper=0.2)
    for i, (dy, dz) in enumerate(((-0.25, 0.3), (-0.08, 0.45), (0.08, 0.45), (0.25, 0.3))):   # tail fibres
        p0 = Vector((-0.0126, 0.0, 0.0010))
        d = Vector((-1.0, dy, dz)).normalized()
        b.strip(p0, p0 + d * 0.0055, (0.0, 1.0, 0.0), 0.0003, "hackle", taper=0.2)
    for sy in (-1.0, 1.0):                                                                  # wing slips
        p0 = Vector((-0.0036, sy * 0.0006, 0.0012))
        d = Vector((-0.75, sy * 0.12, 0.65)).normalized()
        b.strip(p0, p0 + d * 0.0065, (0.0, 1.0, 0.0), 0.0012, "wing", taper=0.5)
    return b.finish(name)


# ----------------------------------------------------------------------------------------------
# D. ROWING BOAT (clinker hull, three thwarts, two oars inside)
# ----------------------------------------------------------------------------------------------
def build_boat(name):
    b = PB3()
    X0, X1 = -1.55, 1.75
    n_st, n_str = 22, 6

    def u(x):
        return (x - 0.1) / 1.70

    def beam(x):
        return 0.72 * max(0.0, 1.0 - u(x) ** 2) ** 0.35

    def keel(x):
        return 0.16 * u(x) ** 2

    def sheer(x):
        return 0.50 + 0.14 * u(x) ** 2 + 0.10 * max(0.0, u(x)) ** 2

    def g(f):
        return f ** 0.45

    xs = [X0 + (X1 - X0) * i / (n_st - 1) for i in range(n_st)]
    land = 0.014

    def pt(x, f, side, extra=0.0):
        B = beam(x)
        off = extra * min(1.0, B / 0.18)
        return Vector((x, side * (B * g(f) + off), keel(x) + (sheer(x) - keel(x)) * f))

    def strip_faces(rows_a, rows_b, region, smooth=True):
        faces = []
        for i in range(len(rows_a) - 1):
            try:
                f = b.bm.faces.new((rows_a[i], rows_a[i + 1], rows_b[i + 1], rows_b[i]))
            except ValueError:
                continue
            f.smooth = smooth
            faces.append(f)
        return faces

    def mkrow(fn, region):
        out = []
        for x in xs:
            v = b.bm.verts.new(fn(x))
            v[b.lay] = PR[region]
            out.append(v)
        return out

    all_faces = []
    for side in (1.0, -1.0):
        for k in range(n_str):
            f0, f1 = k / n_str, (k + 1) / n_str
            lower = mkrow(lambda x, f0=f0: pt(x, f0, side, land if k > 0 else 0.0), "hull")
            upper = mkrow(lambda x, f1=f1: pt(x, f1, side), "hull")
            all_faces += strip_faces(lower, upper, "hull")
            if k > 0:                                                   # the land (overlap lip)
                inner = mkrow(lambda x, f0=f0: pt(x, f0, side), "hull")
                all_faces += strip_faces(inner, lower, "hull", smooth=False)
        # inner skin, offset inward
        for k in range(n_str):
            f0, f1 = k / n_str, (k + 1) / n_str
            lower = mkrow(lambda x, f0=f0: pt(x, f0, side, -0.02), "hull_in")
            upper = mkrow(lambda x, f1=f1: pt(x, f1, side, -0.02), "hull_in")
            all_faces += strip_faces(upper, lower, "hull_in")
    bmesh.ops.recalc_face_normals(b.bm, faces=all_faces)
    # transom
    tr = [pt(X0, f, s) for s, f in [(1, 0), (1, 0.33), (1, 0.66), (1, 1.0), (-1, 1.0), (-1, 0.66), (-1, 0.33)]]
    tv = [b.bm.verts.new(p + Vector((-0.012, 0.0, 0.0))) for p in tr]
    for v in tv:
        v[b.lay] = PR["hull"]
    ft = b.bm.faces.new(tv)
    ft.smooth = False
    tv2 = [b.bm.verts.new(p + Vector((0.012, 0.0, 0.0))) for p in tr]
    for v in tv2:
        v[b.lay] = PR["hull_in"]
    fi = b.bm.faces.new(list(reversed(tv2)))
    fi.smooth = False
    bmesh.ops.recalc_face_normals(b.bm, faces=[ft, fi])
    b.box((X0, 0.0, 0.5 * (keel(X0) + sheer(X0))), (0.05, 2 * beam(X0) * 0.9, sheer(X0) - keel(X0)), "oar")  # transom board
    # keel, stem, gunwales
    b.tube([(x, 0.0, keel(x) - 0.025) for x in xs], 0.025, "oar", segs=4, smooth=False)
    b.box((X1 - 0.02, 0.0, 0.5 * (keel(X1) + sheer(X1)) + 0.03), (0.06, 0.05, sheer(X1) - keel(X1) + 0.10), "oar")
    for side in (1.0, -1.0):
        b.tube([pt(x, 1.0, side, 0.0) + Vector((0.0, 0.0, 0.012)) for x in xs], 0.022, "oar", segs=6)
    # ribs (frames) inside
    for x in (-1.2, -0.75, -0.3, 0.15, 0.6, 1.05):
        pts = [pt(x, f, -1.0, -0.03) for f in (1.0, 0.75, 0.5, 0.25, 0.08)]
        pts += [pt(x, f, 1.0, -0.03) for f in (0.08, 0.25, 0.5, 0.75, 1.0)]
        b.tube(pts, 0.018, "hull_in", segs=4, smooth=False)
    # floorboards
    b.box((0.05, 0.0, keel(0.0) + 0.06), (2.4, 0.56, 0.025), "oar")
    # thwarts (seats)
    zt = 0.30
    for x in (-0.9, 0.0, 0.9):
        f = (zt - keel(x)) / (sheer(x) - keel(x))
        b.box((x, 0.0, keel(x) + (sheer(x) - keel(x)) * f), (0.22, 2.0 * beam(x) * g(f) - 0.03, 0.035), "oar")
    # oarlocks on the gunwales
    for side in (1.0, -1.0):
        p = pt(0.25, 1.0, side, 0.0) + Vector((0.0, 0.0, 0.035))
        b.cyl(p + Vector((0.0, 0.0, -0.035)), p + Vector((0.0, 0.0, 0.03)), 0.012, None, "metal", segs=8)
        b.torus(p + Vector((0.0, 0.0, 0.06)), (1.0, 0.0, 0.0), 0.035, 0.009, "metal", segs=8, rings=5,
                arc=math.pi, closed=False)
    # two oars resting inside, blades aft
    for side in (1.0, -1.0):
        y = side * 0.16
        z0 = zt + 0.06
        b.cyl((1.15, y, z0), (-1.05, y * 0.8, z0 + 0.02), 0.02, 0.024, "oar", segs=8)
        b.box((-1.30, y * 0.8, z0 + 0.02), (0.55, 0.13, 0.018), "oar")
        b.cyl((1.15, y, z0), (1.32, y, z0), 0.016, None, "oar", segs=8)                    # handle
    return b.finish(name)


# ----------------------------------------------------------------------------------------------
# D. TACKLE BOX (open two-tier wooden box, 8 x 6 divider grid, lid at 100 deg, handle, latches)
# ----------------------------------------------------------------------------------------------
def build_tacklebox(name):
    b = PB3()
    Lx, Ly, Hb, Hl, t = 0.60, 0.40, 0.20, 0.05, 0.012
    # base: bottom and four walls
    b.box((0.0, 0.0, 0.5 * t), (Lx, Ly, t), "box_wood")
    b.box((0.0, -0.5 * Ly + 0.5 * t, 0.5 * Hb), (Lx, t, Hb), "box_wood")
    b.box((0.0, 0.5 * Ly - 0.5 * t, 0.5 * Hb), (Lx, t, Hb), "box_wood")
    b.box((-0.5 * Lx + 0.5 * t, 0.0, 0.5 * Hb), (t, Ly - 2 * t, Hb), "box_wood")
    b.box((0.5 * Lx - 0.5 * t, 0.0, 0.5 * Hb), (t, Ly - 2 * t, Hb), "box_wood")
    # felt floor of the lower tier
    ix, iy = Lx - 2 * t, Ly - 2 * t
    b.box((0.0, 0.0, t + 0.002), (ix, iy, 0.004), "felt")
    # 8 x 6 divider grid (7 + 5 dividers), 85 mm tall
    dh, dt = 0.085, 0.004
    for k in range(1, 8):
        x = -0.5 * ix + ix * k / 8
        b.box((x, 0.0, t + 0.004 + 0.5 * dh), (dt, iy, dh), "divider")
    for k in range(1, 6):
        y = -0.5 * iy + iy * k / 6
        b.box((0.0, y, t + 0.004 + 0.5 * dh), (ix, dt, dh), "divider")
    # upper tier: a cantilever tray swung forward over the front edge on two arms
    tx, ty, th = Lx - 0.03, 0.17, 0.06
    tc = Vector((0.0, -0.5 * Ly - 0.5 * ty + 0.03, Hb + 0.045))
    b.box(tc + Vector((0.0, 0.0, 0.004)), (tx, ty, 0.008), "box_wood")
    b.box(tc + Vector((0.0, -0.5 * ty + 0.004, 0.5 * th)), (tx, 0.008, th), "box_wood")
    b.box(tc + Vector((0.0, 0.5 * ty - 0.004, 0.5 * th)), (tx, 0.008, th), "box_wood")
    b.box(tc + Vector((-0.5 * tx + 0.004, 0.0, 0.5 * th)), (0.008, ty, th), "box_wood")
    b.box(tc + Vector((0.5 * tx - 0.004, 0.0, 0.5 * th)), (0.008, ty, th), "box_wood")
    for k in (1, 2):
        b.box(tc + Vector((-0.5 * tx + tx * k / 3, 0.0, 0.5 * th)), (dt, ty - 0.016, th - 0.01), "divider")
    b.box(tc + Vector((0.0, 0.0, 0.010)), (tx - 0.016, ty - 0.016, 0.004), "felt")
    for sx in (-1.0, 1.0):                                                      # swing arms
        p0 = Vector((sx * (0.5 * Lx - 0.03), -0.5 * Ly + 0.09, Hb - 0.06))
        p1 = Vector((sx * (0.5 * tx - 0.01), tc.y + 0.5 * ty - 0.02, tc.z + 0.01))
        d = p1 - p0
        rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        b.box(0.5 * (p0 + p1), (0.006, 0.018, d.length), "metal", rot=rot)
        b.cyl(p0 + Vector((sx * -0.004, 0.0, 0.0)), p0 + Vector((sx * 0.006, 0.0, 0.0)), 0.006, None, "metal", segs=8)
    # lid: built closed (z Hb..Hb+Hl) then rotated -100 deg about the back hinge (y = +Ly/2, z = Hb)
    hinge = Vector((0.0, 0.5 * Ly, Hb))
    R = Matrix.Rotation(math.radians(-100.0), 4, "X")
    T = Matrix.Translation(hinge) @ R @ Matrix.Translation(-hinge)
    tf = b.transformed(T)

    def lid_box(centre, size, region):
        b.box(tf(centre), size, region, rot=R)

    lid_box((0.0, 0.0, Hb + Hl - 0.5 * t), (Lx, Ly, t), "box_wood")
    lid_box((0.0, -0.5 * Ly + 0.5 * t, Hb + 0.5 * (Hl - t)), (Lx, t, Hl - t), "box_wood")
    lid_box((0.0, 0.5 * Ly - 0.5 * t, Hb + 0.5 * (Hl - t)), (Lx, t, Hl - t), "box_wood")
    lid_box((-0.5 * Lx + 0.5 * t, 0.0, Hb + 0.5 * (Hl - t)), (t, Ly - 2 * t, Hl - t), "box_wood")
    lid_box((0.5 * Lx - 0.5 * t, 0.0, Hb + 0.5 * (Hl - t)), (t, Ly - 2 * t, Hl - t), "box_wood")
    lid_box((0.0, 0.0, Hb + Hl - t - 0.002), (Lx - 2 * t, Ly - 2 * t, 0.004), "felt")
    for sx in (-0.18, 0.18):                                                    # hinges
        b.cyl((sx - 0.03, hinge.y, hinge.z), (sx + 0.03, hinge.y, hinge.z), 0.008, None, "metal", segs=10)
    # handle on the lid's outer face: two feet and a bail (closed frame, transformed)
    for sx in (-0.07, 0.07):
        lid_box((sx, 0.0, Hb + Hl + 0.006), (0.024, 0.024, 0.012), "metal")
    bail = []
    for i in range(11):
        a = math.pi * i / 10
        bail.append(tf((-0.07 * math.cos(a), 0.0, Hb + Hl + 0.012 + 0.035 * math.sin(a))))
    b.tube(bail, 0.006, "rubber", segs=6)
    # two latches on the front: catch plate on the base, hasp hanging from the lid's front edge
    for sx in (-0.18, 0.18):
        b.box((sx, -0.5 * Ly - 0.004, Hb - 0.035), (0.030, 0.008, 0.045), "metal")
        b.box((sx, -0.5 * Ly - 0.010, Hb - 0.028), (0.018, 0.006, 0.010), "metal")
        lid_box((sx, -0.5 * Ly - 0.006, Hb + 0.5 * Hl), (0.034, 0.006, Hl + 0.02), "metal")
    # brass corner caps on the base bottom and the lid top
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx, cy = sx * (0.5 * Lx - 0.02), sy * (0.5 * Ly - 0.02)
            b.box((cx, cy, 0.003), (0.045, 0.045, 0.006), "brass")
            b.box((sx * (0.5 * Lx + 0.002), cy, 0.02), (0.004, 0.045, 0.04), "brass")
            b.box((cx, sy * (0.5 * Ly + 0.002), 0.02), (0.045, 0.004, 0.04), "brass")
            lid_box((cx, cy, Hb + Hl + 0.002), (0.045, 0.045, 0.004), "brass")
    return b.finish(name)


# ----------------------------------------------------------------------------------------------
# D. PROP MATERIAL v3 (regions -> colours; wood grain, brushed metal, paint stripes, hackle fibres)
# ----------------------------------------------------------------------------------------------
def build_prop_material3(name, P):
    mat = bpy.data.materials.new(f"Prop_{name}")
    mat.use_nodes = True
    tree = mat.node_tree
    for nd in list(tree.nodes):
        tree.nodes.remove(nd)
    nb = v2.NB(tree)
    coord = nb.n("ShaderNodeTexCoord")
    obj_co = coord.outputs["Object"]
    region = nb.attr("region")
    sep = nb.n("ShaderNodeSeparateXYZ")
    nb.put(sep.inputs[0], obj_co)
    L = P["length_m"]
    gs = 1.0 if L > 0.5 else L / 0.5                     # texture scale follows the prop size
    wave = nb.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Y")
    nb.put(wave.inputs["Vector"], nb.mapping(obj_co, scale=(1.0 / gs, 0.08 / gs, 1.0 / gs)))
    wave.inputs["Scale"].default_value = 18.0
    wave.inputs["Distortion"].default_value = 4.0
    wave.inputs["Detail"].default_value = 2.0
    fine = nb.noise(nb.mapping(obj_co, scale=(1.0 / gs, 0.15 / gs, 1.0 / gs)), 40.0, 3.0)
    g = nb.math("MULTIPLY_ADD", wave.outputs["Fac"], 0.35, 0.72)
    g = nb.math("MULTIPLY", g, nb.math("MULTIPLY_ADD", fine, 0.25, 0.88))
    wood = nb.ramp(g, [(0.0, (0.26, 0.17, 0.09)), (1.0, (0.60, 0.45, 0.26))])
    box_wood = nb.ramp(g, [(0.0, (0.18, 0.10, 0.05)), (1.0, (0.46, 0.30, 0.15))])
    divider = nb.ramp(g, [(0.0, (0.40, 0.29, 0.16)), (1.0, (0.70, 0.55, 0.34))])
    oar = nb.ramp(g, [(0.0, (0.50, 0.38, 0.22)), (1.0, (0.80, 0.68, 0.46))])
    hull_in = nb.ramp(g, [(0.0, (0.36, 0.24, 0.12)), (1.0, (0.66, 0.48, 0.26))])
    # hull: pale blue-grey paint, grain faintly through, a dark boot-top below the waterline
    hull_paint = nb.mix(nb.math("MULTIPLY", g, 0.25), (0.62, 0.70, 0.72), (0.40, 0.48, 0.52))
    hull = nb.mix(nb.smooth(0.24, 0.20, sep.outputs["Z"]), hull_paint, (0.22, 0.12, 0.10))
    brushed = nb.math("MULTIPLY_ADD", nb.noise(nb.mapping(obj_co, scale=(1.0, 40.0, 1.0)), 300.0 / gs, 2.0), 0.3, 0.85)
    brass = nb.mul(nb.mix(0.0, (0.82, 0.60, 0.22), (0.82, 0.60, 0.22)), v2.shade_to_col(nb, brushed))
    nickel = nb.mul(nb.mix(0.0, (0.80, 0.81, 0.84), (0.80, 0.81, 0.84)), v2.shade_to_col(nb, brushed))
    # spoon paint: red / white diagonal stripes in the blade plane (x, z)
    stripe = nb.smooth(-0.08, 0.08, nb.math("SINE", nb.math("MULTIPLY", nb.math("ADD", sep.outputs["X"], sep.outputs["Z"]),
                                                                 2.0 * math.pi / 0.014)))
    paint = nb.mix(stripe, (0.92, 0.90, 0.86), (0.80, 0.10, 0.06))
    # hackle: ginger with fibre streaks; thread: olive with ribs along x
    streak = nb.noise(nb.mapping(obj_co, scale=(60.0, 1.0, 1.0)), 600.0, 2.0)
    hackle = nb.mix(nb.math("MULTIPLY_ADD", streak, 0.6, 0.2), (0.62, 0.36, 0.14), (0.30, 0.16, 0.06))
    rib = nb.smooth(0.2, 0.9, nb.math("SINE", nb.math("MULTIPLY", sep.outputs["X"], 2.0 * math.pi / 0.0012)))
    thread = nb.mix(rib, (0.22, 0.26, 0.10), (0.70, 0.62, 0.30))
    cork = nb.mix(nb.smooth(0.45, 0.75, nb.noise(obj_co, 400.0, 2.0)), (0.72, 0.56, 0.36), (0.42, 0.28, 0.14))
    pil = nb.ramp(g, [(0.0, (0.30, 0.26, 0.20)), (1.0, (0.56, 0.50, 0.40))])
    canvas = nb.mix(0.5, (0.90, 0.86, 0.76), (0.72, 0.16, 0.14))
    stops = [("wood", wood), ("metal", (0.55, 0.56, 0.58)), ("canvas", canvas), ("cork", cork),
             ("graphite", (0.09, 0.09, 0.10)), ("dark", (0.05, 0.05, 0.06)), ("crate", oar),
             ("rope", (0.80, 0.76, 0.64)), ("piling", pil), ("sign", oar),
             ("brass", brass), ("nickel", nickel), ("hook", (0.16, 0.14, 0.12)), ("lead", (0.36, 0.37, 0.40)),
             ("bead", (0.80, 0.08, 0.06)), ("paint", paint), ("hackle", hackle), ("thread", thread),
             ("wing", (0.70, 0.70, 0.66)), ("hull", hull), ("hull_in", hull_in), ("oar", oar),
             ("box_wood", box_wood), ("felt", (0.07, 0.16, 0.10)), ("divider", divider),
             ("line", (0.86, 0.84, 0.70)), ("rubber", (0.08, 0.08, 0.08))]
    col = None
    for k, c in stops:
        if col is None:
            col = c if hasattr(c, "is_linked") else nb.mix(0.0, c, c)
            continue
        m = nb.smooth(PR[k] - 0.5, PR[k] - 0.4, region)
        col = nb.mix(m, col, c)
    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    nb.put(bsdf.inputs["Base Color"], col)
    bsdf.inputs["Roughness"].default_value = 0.5
    out = nb.n("ShaderNodeOutputMaterial")
    nb.links.new(bsdf.outputs[0], out.inputs[0])
    alpha = nb.math("ADD", 1.0, 0.0)
    img_node = nb.n("ShaderNodeTexImage")
    tree.nodes.active = img_node
    return mat, img_node, alpha, col, bsdf, out


PROP_BUILDERS = {"rod3": build_rod3, "spinner": build_spinner, "spoon": build_spoon, "fly": build_fly,
                 "boat": build_boat, "tacklebox": build_tacklebox}


def generate_prop3(name, P, exports, previews, do_fbx, do_render, samples):
    scene = v2.new_scene()
    t0 = time.time()
    obj = PROP_BUILDERS[P["kind"]](name)
    v2.smart_uv(obj)
    tris = v2.tri_count(obj.data)
    mat, img_node, alpha_sock, col_sock, bsdf, out_node = build_prop_material3(name, P)
    obj.data.materials.append(mat)
    png = os.path.join(exports, f"{name}_diffuse.png")
    v2.bake_material(obj, mat, img_node, alpha_sock, col_sock, bsdf, out_node, png)
    rough = 0.32 if P["kind"] in ("spinner", "spoon") else 0.55
    tex_mat = v2.make_textured_material(f"Prop_{name}", png, roughness=rough, alpha=False)
    obj.data.materials.clear()
    obj.data.materials.append(tex_mat)
    bpy.data.materials.remove(mat)
    dims = tuple(round(v, 4) for v in obj.dimensions)
    log(f"{name}: {tris} tris, dims {dims}, built+baked in {time.time() - t0:.1f}s")
    pngs = []
    if do_render:
        for vk, vd in PROP_VIEWS3[P["kind"]].items():
            v2.clear_studio(scene, {obj})
            frame = None
            ground = P["kind"] in ("boat", "tacklebox", "rod3")
            if vk == "reel":
                frame = ((0.26, -0.10, -0.15), (0.50, 0.10, 0.02))
            v2.studio(scene, [obj], vd, samples, ground=ground, lens=50.0, frame=frame)
            png_ = os.path.join(previews, f"{name}_{vk}.png")
            t1 = time.time()
            v2.render_to(scene, png_)
            log(f"{name}: rendered {vk} in {time.time() - t1:.1f}s")
            pngs.append(png_)
        v2.clear_studio(scene, {obj})
    fbx = None
    if do_fbx:
        fbx = os.path.join(exports, f"{name}.fbx")
        export_fbx3(scene, [obj], fbx)
    return dict(preset=name, kind=P["kind"], length_m=P["length_m"], triangles=tris, subdiv_applied=False,
                dimensions_m=list(dims), textures=dict(diffuse=png), fbx=fbx, bones=[], previews=pngs,
                forward_axis="FBX +X", origin=ORIGINS3[P["kind"]])


# ----------------------------------------------------------------------------------------------
# DRIVER
# ----------------------------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description="GameOne v3 fish + prop generator (Blender bpy, Cycles CPU).")
    ap.add_argument("--all", action="store_true", help="every fish (+ animated trout), every prop, sheets, closeup")
    ap.add_argument("--preset", action="append", default=[], help="preset name (repeatable)")
    ap.add_argument("--out", default=HERE, help="base dir; writes <out>/exports_v3 and <out>/previews_v3")
    ap.add_argument("--views", default="34,side")
    ap.add_argument("--no-fbx", action="store_true")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--no-sprites", action="store_true")
    ap.add_argument("--no-anim", action="store_true", help="skip the trout actions / animated FBX")
    ap.add_argument("--final", action="store_true", help="128 samples instead of 64")
    ap.add_argument("--quick", action="store_true", help="16 samples, for iteration")
    ap.add_argument("--sheet", action="store_true", help="rebuild the fish contact sheet + sprite sheet")
    ap.add_argument("--closeup", action="store_true", help="render materials_closeup.png (carp if built, else the first fish)")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(argv)
    all_presets = {**PRESETS3, **PROP3}
    if args.list:
        for k, v in all_presets.items():
            print(f"{k:14s} {v['kind']:9s} {v['length_m']:.2f} m")
        return 0
    names = list(all_presets) if args.all else args.preset
    if not names:
        ap.error("give --all or at least one --preset NAME")
    for n in names:
        if n not in all_presets:
            ap.error(f"unknown preset '{n}'; known: {', '.join(all_presets)}")
    views = [v.strip() for v in args.views.split(",") if v.strip()]
    samples = v2.RENDER["samples_final"] if args.final else (16 if args.quick else v2.RENDER["samples_preview"])
    out = os.path.abspath(args.out)
    exports = os.path.join(out, "exports_v3")
    previews = os.path.join(out, "previews_v3")
    sprites_dir = os.path.join(exports, "sprites")
    for d in (exports, previews, sprites_dir):
        os.makedirs(d, exist_ok=True)
    man_path = os.path.join(exports, "manifest.json")
    manifest = {}
    if os.path.exists(man_path):
        try:
            with open(man_path, "r", encoding="utf-8") as fh:
                manifest = {m["preset"]: m for m in json.load(fh)}
        except Exception:
            manifest = {}
    fish_in_run = [n for n in names if n in PRESETS3]
    closeup_on = "carp" if "carp" in fish_in_run else (fish_in_run[0] if fish_in_run else None)
    for name in names:
        t0 = time.time()
        if name in PRESETS3:
            info = generate_fish3(name, PRESETS3[name], exports, previews, sprites_dir, views, not args.no_fbx,
                                  not args.no_render, samples, not args.no_anim, not args.no_sprites,
                                  (args.closeup or args.all) and name == closeup_on)
        else:
            info = generate_prop3(name, PROP3[name], exports, previews, not args.no_fbx, not args.no_render, samples)
        manifest[name] = info
        print(f"[v3] {name:14s} {info['triangles']:5d} tris  dims {info['dimensions_m']}  "
              f"fbx={bool(info.get('fbx'))}  {time.time() - t0:.0f}s", flush=True)
    if (args.sheet or args.all) and not args.no_render:
        sheet = v2.contact_sheet(exports, previews, FISH_NAMES)
        log(f"contact sheet (re-imported FBX) -> {sheet}")
    # sprite sheet + sprites.json from whatever sprites exist in the manifest
    entries = {k: m["sprites"] for k, m in manifest.items() if m.get("sprites")}
    if entries:
        sj = dict(version=3, generated="2026-10-08", facing="right", note="nose at +X renders on the RIGHT; "
                  "bounds_px is the opaque box of the sprite; px_per_m scales metres to sprite pixels; the UI "
                  "scales a sprite so bounds width -> cells * cellPx (+ gaps)", species=entries,
                  side_size=[SPRITE["side_w"], SPRITE["side_h"]], icon_size=[SPRITE["icon"], SPRITE["icon"]])
        with open(os.path.join(sprites_dir, "sprites.json"), "w", encoding="utf-8", newline="\n") as fh:
            json.dump(sj, fh, indent=2)
            fh.write("\n")
        sheet = sprite_sheet(sprites_dir, entries, os.path.join(sprites_dir, "sheet.png"))
        log(f"sprite sheet -> {sheet}")
    with open(man_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump([manifest[k] for k in all_presets if k in manifest], fh, indent=2)
        fh.write("\n")
    log(f"manifest -> {man_path}")
    over = []
    for k, m in manifest.items():
        lim = BUDGET3["fish_max"] if m["kind"] == "fish" else BUDGET3["prop_max"]
        if m["triangles"] > lim:
            over.append(f"{k} ({m['triangles']} > {lim})")
    if over:
        log(f"WARNING over budget: {over}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
