#!/usr/bin/env python3
"""net_vectors_v3.py (About Fishing F1 cloud work, WS-N net v3; Cloud, 2026-10-07; design/WSN_net_v3_messages.md)

Byte vectors for the v3 messages in Dev3's net_sim_f1.py style: an INDEPENDENT Python implementation of
the design note's canonical reference encoding (section 4) and validation rules (section 5), written
from the note's field tables, not from NetSchemaV3.lua. The Luau suite tests/netschemav3_test.luau
replays every vector against the module: same hex for every valid payload, same rejection reason for
every invalid one. Two implementations agreeing on bytes is the wire gate; one copying the other is not.

Per message at least four vectors: minimal (every field at its minimum), maximal (every field at its
maximum; table fields at their realistic maximum, e.g. a full 8 x 6 box), typical, and one or more
INVALID payloads with the expected rejection reason. f32 values are chosen with few digits so the Luau
side's 1e-6 compare after the float32 round trip holds.

Usage (from anywhere, deterministic output, standard library only):
  python3 -I net_vectors_v3.py                 writes tests/fixtures/net_vectors_v3.json and
                                               tests/fixtures/net_vectors_v3_data.luau (the same vectors
                                               as a Luau module, since the Luau CLI has no file I/O)
  python3 -I net_vectors_v3.py --out DIR       writes both files into DIR
  python3 -I net_vectors_v3.py --check [JSON]  re-reads the JSON, re-encodes every valid vector and
                                               re-validates every invalid one; exit 1 on any drift
  python3 -I net_vectors_v3.py --selftest      proves --check fails on one flipped byte, a changed
                                               reason and a missing message; exit 0 when it does
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
FIXTURES = ROOT / "tests" / "fixtures"
JSON_NAME = "net_vectors_v3.json"
LUAU_NAME = "net_vectors_v3_data.luau"

# ---------------------------------------------------------------- the schema (design note sections 3 and 6)
STATES = ["Walking", "Aiming", "Flight", "Presenting", "Retrieving", "Inspected", "HookWindow", "Hooked", "CatchScene", "Holding"]
BOX_AND_SHOP = ["Walking", "Holding"]
NOT_FLIGHT_OR_HOOKED = ["Walking", "Aiming", "Presenting", "Retrieving", "Inspected", "HookWindow", "CatchScene", "Holding"]

INT_RANGE = {"u8": (0, 255), "u16": (0, 65535), "i16": (-32768, 32767), "u32": (0, 4294967295)}
INT_FMT = {"u8": "<B", "u16": "<H", "i16": "<h", "u32": "<I"}
F32_MAX = 3.4028234663852886e38
STR_MAX = 255
DEPTH_MAX = 8
ID_MIN, ID_MAX, C2S_MAX = 32, 63, 47


def F(name: str, type_: str, **lim) -> dict:
    return {"name": name, "type": type_, **lim}


def M(id_: int, dir_: str, states: list, rate: tuple, fields: list) -> dict:
    return {"id": id_, "dir": dir_, "states": states, "rate": {"perS": rate[0], "burst": rate[1]}, "fields": fields}


MESSAGES = {
    "TackleMove": M(32, "C2S", BOX_AND_SHOP, (10, 20), [F("id", "u16", min=1), F("rot", "u8", max=3), F("x", "u8", min=1, max=32), F("y", "u8", min=1, max=32)]),
    "TackleDrop": M(33, "C2S", BOX_AND_SHOP, (2, 4), [F("id", "u16", min=1)]),
    "Sell": M(34, "C2S", BOX_AND_SHOP, (1, 2), [F("ids", "ids", maxLen=48)]),
    "BuyGear": M(35, "C2S", BOX_AND_SHOP, (1, 2), [F("kind", "u8", max=3), F("id", "str", maxLen=24)]),
    "Equip": M(36, "C2S", BOX_AND_SHOP, (2, 4), [F("kind", "u8", max=3), F("id", "str", maxLen=24)]),
    "SetOption": M(37, "C2S", NOT_FLIGHT_OR_HOOKED, (5, 10), [F("key", "u8", max=5), F("value", "f32", min=0, max=90)]),
    "TackleMoveResult": M(48, "S2C", [], (10, 20), [F("ok", "bool"), F("reason", "u8", max=7)]),
    "TackleSync": M(49, "S2C", [], (10, 20), [F("w", "u8", min=1, max=32), F("h", "u8", min=1, max=32), F("nextId", "u16", min=1), F("items", "table", maxLen=4096)]),
    "SellResult": M(50, "S2C", [], (1, 2), [F("reason", "u8", max=4), F("total", "u32"), F("coins", "u32"), F("lines", "table", maxLen=1024)]),
    "BuyResult": M(51, "S2C", [], (2, 4), [F("op", "u8", max=1), F("ok", "bool"), F("reason", "u8", max=6), F("coins", "u32")]),
    "CatchLogSync": M(52, "S2C", [], (1, 2), [F("log", "table", maxLen=4096)]),
    "WorldSync": M(53, "S2C", [], (0.2, 2), [F("clockTime", "f32", min=0, max=24), F("dayN", "u16", min=1), F("phase", "u8", max=3), F("weather", "u8", max=2),
                                              F("rain", "f32", min=0, max=1), F("waveM", "f32", min=0, max=0.5), F("sun", "f32", min=-1, max=1)]),
    "ProfileReady": M(54, "S2C", [], (1, 1), [F("readOnly", "bool"), F("reason", "u8", max=5)]),
}


# ---------------------------------------------------------------- validation (design note section 5)
class Bad(Exception):
    pass


def is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def is_int(v) -> bool:
    return is_num(v) and float(v).is_integer()


def is_ascii(s: str) -> bool:
    return all(32 <= ord(c) <= 126 for c in s)


def blen(s: str) -> int:
    return len(s.encode("utf-8"))


def walk(v, depth: int) -> int:
    """Node count of a JSON-safe printable-ASCII tree; raises Bad when it is not one."""
    if isinstance(v, bool) or is_num(v):
        return 1
    if isinstance(v, str):
        if blen(v) <= STR_MAX and is_ascii(v):
            return 1
        raise Bad
    if isinstance(v, list):
        if depth > DEPTH_MAX:
            raise Bad
        return 1 + sum(walk(x, depth + 1) for x in v)
    if isinstance(v, dict):
        if depth > DEPTH_MAX:
            raise Bad
        for k in v:
            if not isinstance(k, str) or blen(k) > STR_MAX or not is_ascii(k):
                raise Bad
        return 1 + sum(walk(x, depth + 1) for x in v.values())
    raise Bad


def field_problem(f: dict, v) -> str | None:
    name, t = f["name"], f["type"]
    if t in INT_RANGE:
        lo, hi = INT_RANGE[t]
        if not is_int(v):
            return f"{name}: expected {t}"
        if v < max(lo, f.get("min", lo)) or v > min(hi, f.get("max", hi)):
            return f"{name}: out of range"
    elif t == "f32":
        if not is_num(v):
            return f"{name}: expected f32"
        if v < f.get("min", -F32_MAX) or v > f.get("max", F32_MAX):
            return f"{name}: out of range"
    elif t == "bool":
        if not isinstance(v, bool):
            return f"{name}: expected bool"
    elif t == "str":
        if not isinstance(v, str):
            return f"{name}: expected str"
        if blen(v) > f.get("maxLen", STR_MAX):
            return f"{name}: too long"
        if not is_ascii(v):
            return f"{name}: not ASCII"
    elif t == "ids":
        if not isinstance(v, list):
            return f"{name}: expected ids"
        if len(v) > f.get("maxLen", 255):
            return f"{name}: too long"
        lo, hi = f.get("min", 1), f.get("max", 65535)
        if any(not is_int(e) or e < lo or e > hi for e in v):
            return f"{name}: bad id"
    elif t == "table":
        if not isinstance(v, (list, dict)):
            return f"{name}: expected table"
        try:
            n = walk(v, 1)
        except Bad:
            return f"{name}: bad table"
        if n > f.get("maxLen", 1024):
            return f"{name}: too long"
    else:
        raise ValueError(f"unknown field type {t}")
    return None


def validate(name: str, payload) -> tuple[bool, str | None]:
    m = MESSAGES.get(name)
    if m is None:
        return False, "unknown message"
    if not isinstance(payload, dict):
        return False, "payload must be a table"
    for f in m["fields"]:
        if f["name"] not in payload:
            return False, f"missing {f['name']}"
    for f in m["fields"]:
        p = field_problem(f, payload[f["name"]])
        if p:
            return False, p
    known = {f["name"] for f in m["fields"]}
    extra = sorted(str(k) for k in payload if k not in known)
    if extra:
        return False, f"unexpected {extra[0]}"
    return True, None


# ---------------------------------------------------------------- the canonical reference encoding (section 4)
def pack_value(v) -> bytes:
    """Tagged form: 1 false, 2 true, 3 i32, 4 f64, 5 str (u16 len), 6 array (u16 count), 7 map (u16 count,
    sorted keys as u16 len + bytes). An empty dict is an empty array, like HttpService:JSONEncode."""
    if isinstance(v, bool):
        return b"\x02" if v else b"\x01"
    if is_num(v):
        if float(v).is_integer() and -2147483648 <= v <= 2147483647:
            return b"\x03" + struct.pack("<i", int(v))
        return b"\x04" + struct.pack("<d", float(v))
    if isinstance(v, str):
        b = v.encode("ascii")
        return b"\x05" + struct.pack("<H", len(b)) + b
    if isinstance(v, list):
        return b"\x06" + struct.pack("<H", len(v)) + b"".join(pack_value(x) for x in v)
    if isinstance(v, dict):
        if not v:
            return b"\x06\x00\x00"
        out = [b"\x07" + struct.pack("<H", len(v))]
        for k in sorted(v):
            kb = k.encode("ascii")
            out.append(struct.pack("<H", len(kb)) + kb + pack_value(v[k]))
        return b"".join(out)
    raise ValueError(f"not JSON-safe: {v!r}")


def pack_field(f: dict, v) -> bytes:
    t = f["type"]
    if t in INT_FMT:
        return struct.pack(INT_FMT[t], int(v))
    if t == "f32":
        return struct.pack("<f", float(v))
    if t == "bool":
        return b"\x01" if v else b"\x00"
    if t == "str":
        b = v.encode("ascii")
        return struct.pack("<B", len(b)) + b
    if t == "ids":
        return struct.pack("<B", len(v)) + b"".join(struct.pack("<H", int(e)) for e in v)
    return pack_value(v)


def encode(name: str, payload: dict) -> bytes:
    ok, why = validate(name, payload)
    if not ok:
        raise ValueError(f"{name}: {why}")
    m = MESSAGES[name]
    return struct.pack("<B", m["id"]) + b"".join(pack_field(f, payload[f["name"]]) for f in m["fields"])


# ---------------------------------------------------------------- the vectors
def ok(name: str, payload: dict) -> dict:
    return {"name": name, "payload": payload, "valid": True, "hex": encode(name, payload).hex()}


def bad(name: str, payload, reason: str) -> dict:
    got = validate(name, payload)
    if got != (False, reason):
        raise AssertionError(f"vector for {name} expects {reason!r} but this validator says {got}")
    return {"name": name, "payload": payload, "valid": False, "reason": reason, "hex": ""}


SHAPES = {"line1": [[0, 0]], "line3": [[0, 0], [1, 0], [2, 0]], "L3": [[0, 0], [0, 1], [1, 1]], "rect2x2": [[0, 0], [1, 0], [0, 1], [1, 1]]}


def item(id_: int, kind: str, key: str, shape: str, rot: int, x: int, y: int, data: dict | None = None) -> dict:
    d = {"id": id_, "kind": kind, "key": key, "shape": SHAPES[shape], "rot": rot, "x": x, "y": y}
    if data is not None:
        d["data"] = data
    return d


def catch(species: str, length_m: float, weight_kg: float, zone: str, day: int, tod: float, lure: str) -> dict:
    return {"speciesId": species, "lengthM": length_m, "weightKg": weight_kg, "zoneId": zone, "dayN": day, "timeOfDay": tod, "lureId": lure}


def species_record(species: str, count: int, first: dict, best: dict, zones: dict) -> dict:
    return {"id": species, "count": count, "first": first, "bestLengthM": best["lengthM"], "bestWeightKg": best["weightKg"], "bestLengthCatch": best, "zones": zones}


def nested(depth: int):
    v = 1
    for _ in range(depth):
        v = [v]
    return v


def build_vectors() -> list:
    V: list = []
    long_id = "abcdefghijklmnopqrstuvwx"  # 24 = BuyGear/Equip id maxLen
    # TackleMove
    V += [ok("TackleMove", {"id": 1, "rot": 0, "x": 1, "y": 1}),
          ok("TackleMove", {"id": 65535, "rot": 3, "x": 32, "y": 32}),
          ok("TackleMove", {"id": 3, "rot": 1, "x": 5, "y": 2}),
          bad("TackleMove", {"id": 3, "rot": 4, "x": 5, "y": 2}, "rot: out of range"),
          bad("TackleMove", {"id": "3", "rot": 1, "x": 5, "y": 2}, "id: expected u16"),
          bad("TackleMove", {"id": 3, "rot": 1, "x": 0, "y": 2}, "x: out of range"),
          bad("TackleMove", {"id": 3, "rot": 1, "x": 5}, "missing y"),
          bad("TackleMove", {"id": 3, "rot": 1, "x": 5, "y": 2, "z": 1}, "unexpected z")]
    # TackleDrop
    V += [ok("TackleDrop", {"id": 1}), ok("TackleDrop", {"id": 65535}), ok("TackleDrop", {"id": 7}),
          bad("TackleDrop", {"id": 0}, "id: out of range"),
          bad("TackleDrop", {"id": 1.5}, "id: expected u16"),
          bad("TackleDrop", 5, "payload must be a table")]
    # Sell
    V += [ok("Sell", {"ids": [1]}), ok("Sell", {"ids": list(range(65488, 65536))}), ok("Sell", {"ids": [2, 5, 7]}),
          ok("Sell", {"ids": []}),
          bad("Sell", {"ids": "1"}, "ids: expected ids"),
          bad("Sell", {"ids": {"a": 1}}, "ids: expected ids"),
          bad("Sell", {"ids": list(range(1, 50))}, "ids: too long"),
          bad("Sell", {"ids": [0]}, "ids: bad id"),
          bad("Sell", {"ids": [1.5]}, "ids: bad id")]
    # BuyGear / Equip (kind: 0 lure, 1 rod, 2 line, 3 hook)
    V += [ok("BuyGear", {"kind": 0, "id": ""}), ok("BuyGear", {"kind": 3, "id": long_id}), ok("BuyGear", {"kind": 1, "id": "rod_carbon"}),
          bad("BuyGear", {"kind": 1, "id": long_id + "y"}, "id: too long"),
          bad("BuyGear", {"kind": 1, "id": "rod_cörbon"}, "id: not ASCII"),
          bad("BuyGear", {"kind": 4, "id": "rod_carbon"}, "kind: out of range"),
          bad("BuyGear", {"kind": 1, "id": 7}, "id: expected str")]
    V += [ok("Equip", {"kind": 0, "id": ""}), ok("Equip", {"kind": 3, "id": long_id}), ok("Equip", {"kind": 0, "id": "spinner"}),
          bad("Equip", {"kind": -1, "id": "spinner"}, "kind: out of range"),
          bad("Equip", {"kind": 0, "id": True}, "id: expected str")]
    # SetOption (key: 0 MouseSensitivity .. 5 HoldToToggleReel; bools are 0/1)
    V += [ok("SetOption", {"key": 0, "value": 0}), ok("SetOption", {"key": 5, "value": 90}), ok("SetOption", {"key": 0, "value": 1.25}),
          ok("SetOption", {"key": 4, "value": 70}),
          bad("SetOption", {"key": 4, "value": 90.5}, "value: out of range"),
          bad("SetOption", {"key": 0, "value": -0.5}, "value: out of range"),
          bad("SetOption", {"key": 0, "value": "1"}, "value: expected f32"),
          bad("SetOption", {"key": 6, "value": 1}, "key: out of range")]
    # TackleMoveResult
    V += [ok("TackleMoveResult", {"ok": False, "reason": 0}), ok("TackleMoveResult", {"ok": True, "reason": 7}),
          ok("TackleMoveResult", {"ok": False, "reason": 5}),
          bad("TackleMoveResult", {"ok": 1, "reason": 0}, "ok: expected bool"),
          bad("TackleMoveResult", {"ok": True, "reason": 8}, "reason: out of range")]
    # TackleSync: items = TackleBox.serialize(box).items
    full_box = [item(i + 1, "fish" if i % 2 == 0 else "lure", "trout" if i % 2 == 0 else "worm", "line1", 0, i % 8 + 1, i // 8 + 1) for i in range(48)]
    typical_items = [item(1, "fish", "trout", "L3", 1, 1, 1, {"speciesId": "trout", "lengthM": 0.4, "weightKg": 0.704}),
                     item(2, "lure", "spinner", "line1", 0, 4, 1),
                     item(3, "gear", "rod_carbon", "line3", 0, 1, 4)]
    V += [ok("TackleSync", {"w": 1, "h": 1, "nextId": 1, "items": []}),
          ok("TackleSync", {"w": 32, "h": 32, "nextId": 65535, "items": full_box}),
          ok("TackleSync", {"w": 8, "h": 6, "nextId": 4, "items": typical_items}),
          bad("TackleSync", {"w": 8, "h": 6, "nextId": 4, "items": 5}, "items: expected table"),
          bad("TackleSync", {"w": 8, "h": 6, "nextId": 4, "items": ["tröut"]}, "items: bad table"),
          bad("TackleSync", {"w": 8, "h": 6, "nextId": 4, "items": nested(10)}, "items: bad table"),
          bad("TackleSync", {"w": 0, "h": 6, "nextId": 4, "items": []}, "w: out of range"),
          bad("TackleSync", {"w": 8, "h": 6, "nextId": 0, "items": []}, "nextId: out of range")]
    # SellResult: lines = GameData.sellTotal lines minus the name (the client has SpeciesTable)
    line = {"speciesId": "trout", "lengthM": 0.4, "weightKg": 0.704, "coins": 8}
    V += [ok("SellResult", {"reason": 0, "total": 0, "coins": 0, "lines": []}),
          ok("SellResult", {"reason": 4, "total": 4294967295, "coins": 4294967295, "lines": [line] * 48}),
          ok("SellResult", {"reason": 0, "total": 32, "coins": 132, "lines": [line] * 4}),
          bad("SellResult", {"reason": 0, "total": -1, "coins": 0, "lines": []}, "total: out of range"),
          bad("SellResult", {"reason": 0, "total": 4294967296, "coins": 0, "lines": []}, "total: out of range"),
          bad("SellResult", {"reason": 0, "total": 1.5, "coins": 0, "lines": []}, "total: expected u32"),
          bad("SellResult", {"reason": 0, "total": 0, "coins": 0, "lines": [0] * 1100}, "lines: too long"),
          bad("SellResult", {"reason": 0, "total": 0, "coins": 0, "lines": "x"}, "lines: expected table")]
    # BuyResult (op: 0 buy, 1 equip)
    V += [ok("BuyResult", {"op": 0, "ok": False, "reason": 0, "coins": 0}), ok("BuyResult", {"op": 1, "ok": True, "reason": 6, "coins": 4294967295}),
          ok("BuyResult", {"op": 0, "ok": True, "reason": 0, "coins": 72}),
          bad("BuyResult", {"op": 2, "ok": True, "reason": 0, "coins": 72}, "op: out of range"),
          bad("BuyResult", {"op": 0, "ok": "yes", "reason": 0, "coins": 72}, "ok: expected bool")]
    # CatchLogSync: log = CatchLog.serialize(log)
    trout_first = {"dayN": 1, "timeOfDay": 7.5, "zoneId": "shore_a", "lengthM": 0.4}
    trout_best = catch("trout", 0.46, 1.07, "shore_a", 2, 18.25, "spinner")
    typical_log = {"v": 1, "totalCount": 3, "species": [species_record("trout", 3, trout_first, trout_best, {"shore_a": 2, "dock": 1})]}
    big_species = []
    for i, sp in enumerate(["trout", "perch", "pike", "carp", "minnow"]):
        best = catch(sp, 0.5 + i * 0.1, 1.0 + i, "shore_a", i + 1, 12.5, "worm")
        big_species.append(species_record(sp, 12 + i, {"dayN": 1, "timeOfDay": 6.25, "zoneId": "dock", "lengthM": 0.3}, best, {"shore_a": 10, "dock": 1, "reeds": 1 + i}))
    V += [ok("CatchLogSync", {"log": {"v": 1, "totalCount": 0, "species": []}}),
          ok("CatchLogSync", {"log": {"v": 1, "totalCount": 70, "species": big_species}}),
          ok("CatchLogSync", {"log": typical_log}),
          bad("CatchLogSync", {"log": 1}, "log: expected table"),
          bad("CatchLogSync", {"log": {"a": nested(9)}}, "log: bad table"),
          bad("CatchLogSync", {"log": {"note": "x" * 256}}, "log: bad table")]
    # WorldSync = WorldClock.snapshot (phase: 0 dawn 1 day 2 dusk 3 night; weather: 0 clear 1 overcast 2 rain)
    V += [ok("WorldSync", {"clockTime": 0, "dayN": 1, "phase": 0, "weather": 0, "rain": 0, "waveM": 0, "sun": -1}),
          ok("WorldSync", {"clockTime": 24, "dayN": 65535, "phase": 3, "weather": 2, "rain": 1, "waveM": 0.5, "sun": 1}),
          ok("WorldSync", {"clockTime": 7.25, "dayN": 1, "phase": 0, "weather": 0, "rain": 0, "waveM": 0.02, "sun": 0.3214}),
          ok("WorldSync", {"clockTime": 18.5, "dayN": 3, "phase": 2, "weather": 2, "rain": 0.8, "waveM": 0.1, "sun": -0.1305}),
          bad("WorldSync", {"clockTime": 7.25, "dayN": 1, "phase": 0, "weather": 3, "rain": 0, "waveM": 0.02, "sun": 0.3}, "weather: out of range"),
          bad("WorldSync", {"clockTime": 7.25, "dayN": 1, "phase": 0, "weather": 0, "rain": 0, "waveM": 0.02, "sun": 1.5}, "sun: out of range"),
          bad("WorldSync", {"clockTime": 24.5, "dayN": 1, "phase": 0, "weather": 0, "rain": 0, "waveM": 0.02, "sun": 0.3}, "clockTime: out of range"),
          bad("WorldSync", {"clockTime": 7.25, "dayN": 0, "phase": 0, "weather": 0, "rain": 0, "waveM": 0.02, "sun": 0.3}, "dayN: out of range"),
          bad("WorldSync", {"clockTime": 7.25, "dayN": 1, "phase": 0, "weather": 0, "rain": True, "waveM": 0.02, "sun": 0.3}, "rain: expected f32")]
    # ProfileReady (reason: 0 new 1 loaded 2 already-loaded 3 newer 4 corrupt 5 no-migration)
    V += [ok("ProfileReady", {"readOnly": False, "reason": 0}), ok("ProfileReady", {"readOnly": True, "reason": 5}),
          ok("ProfileReady", {"readOnly": False, "reason": 1}), ok("ProfileReady", {"readOnly": True, "reason": 4}),
          bad("ProfileReady", {"readOnly": True, "reason": 6}, "reason: out of range"),
          bad("ProfileReady", {"readOnly": "yes", "reason": 1}, "readOnly: expected bool"),
          bad("ProfileReady", {"readOnly": False}, "missing reason")]
    # not a v3 message at all
    V.append(bad("Teleport", {}, "unknown message"))
    return V


# ---------------------------------------------------------------- checking a vector set
def check_vectors(vectors: list) -> list[str]:
    """Every problem found: drift between a vector's hex/reason and a fresh encode/validate, bad shape,
    thin coverage. Empty means the set is current."""
    problems: list[str] = []
    per: dict[str, list[bool]] = {name: [] for name in MESSAGES}
    for i, v in enumerate(vectors):
        where = f"vector {i} ({v.get('name')})"
        if not isinstance(v, dict) or set(v) - {"name", "payload", "valid", "hex", "reason"} or "name" not in v or "payload" not in v or "valid" not in v or "hex" not in v:
            problems.append(f"{where}: bad vector shape")
            continue
        name, payload = v["name"], v["payload"]
        if name in per:
            per[name].append(bool(v["valid"]))
        elif v["valid"] or v.get("reason") != "unknown message":
            problems.append(f"{where}: unknown message name")
            continue
        got_ok, got_why = validate(name, payload)
        if v["valid"]:
            if not got_ok:
                problems.append(f"{where}: marked valid but validate says {got_why!r}")
                continue
            fresh = encode(name, payload).hex()
            if fresh != v["hex"]:
                problems.append(f"{where}: hex drift: file {v['hex'][:32]}.. fresh {fresh[:32]}..")
        else:
            if got_ok or got_why != v.get("reason"):
                problems.append(f"{where}: expected reason {v.get('reason')!r}, validate says {(got_ok, got_why)}")
            if v["hex"] != "":
                problems.append(f"{where}: an invalid vector carries hex")
    for name, flags in per.items():
        if len(flags) < 4 or sum(flags) < 3 or not any(not f for f in flags):
            problems.append(f"{name}: needs at least 4 vectors with 3 valid and 1 invalid (has {len(flags)}, {sum(flags)} valid)")
    return problems


# ---------------------------------------------------------------- output
def lua_str(s: str) -> str:
    out = []
    for b in s.encode("utf-8"):
        if b == 0x22:
            out.append('\\"')
        elif b == 0x5C:
            out.append("\\\\")
        elif 32 <= b <= 126:
            out.append(chr(b))
        else:
            out.append(f"\\{b}")
    return '"' + "".join(out) + '"'


def lua_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua_value(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ", ".join(f"[{lua_str(k)}] = {lua_value(v[k])}" for k in sorted(v)) + "}"
    raise ValueError(f"cannot emit {v!r}")


def luau_module(vectors: list) -> str:
    lines = ["--!strict",
             "-- net_vectors_v3_data (About Fishing F1 cloud work, WS-N net v3; GENERATED by tools/net_vectors_v3.py, do not edit)",
             "-- The same vectors as tests/fixtures/net_vectors_v3.json as a Luau module, because the Luau CLI has no",
             "-- file I/O. Each entry: { name, payload, valid, hex, reason? }. Regenerate: python3 -I tools/net_vectors_v3.py",
             "", "local V: { any } = {}"]
    for i, v in enumerate(vectors, 1):
        lines.append(f"V[{i}] = {lua_value(v)}")
    lines += ["", "return V", ""]
    return "\n".join(lines)


def json_text(vectors: list) -> str:
    return json.dumps(vectors, indent=1, sort_keys=True) + "\n"


def write(out_dir: Path, vectors: list) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    jp, lp = out_dir / JSON_NAME, out_dir / LUAU_NAME
    jp.write_bytes(json_text(vectors).encode("utf-8"))
    lp.write_bytes(luau_module(vectors).encode("utf-8"))
    return jp, lp


def summary(vectors: list) -> str:
    valid = sum(1 for v in vectors if v["valid"])
    return f"{len(vectors)} vectors ({valid} valid, {len(vectors) - valid} invalid) for {len(MESSAGES)} messages"


def run_check(json_path: Path) -> int:
    vectors = json.loads(json_path.read_text(encoding="utf-8"))
    problems = check_vectors(vectors)
    luau_path = json_path.with_name(LUAU_NAME)
    if luau_path.is_file() and luau_path.read_bytes() != luau_module(vectors).encode("utf-8"):
        problems.append(f"{luau_path.name} is not the Luau form of {json_path.name} (regenerate)")
    for p in problems:
        print("  drift: " + p)
    if problems:
        print(f"net_vectors_v3 --check: FAIL {len(problems)} ({json_path})")
        return 1
    print(f"net_vectors_v3 --check: OK {summary(vectors)} ({json_path})")
    return 0


def run_selftest() -> int:
    fails = 0

    def expect(cond: bool, label: str) -> None:
        nonlocal fails
        print(f"  {'ok  ' if cond else 'FAIL'} {label}")
        if not cond:
            fails += 1

    vectors = build_vectors()
    expect(check_vectors(vectors) == [], "a fresh vector set checks clean")
    expect(json.loads(json_text(vectors)) == vectors, "the JSON form round-trips")
    expect(json_text(vectors) == json_text(build_vectors()), "generation is deterministic")
    first_valid = next(i for i, v in enumerate(vectors) if v["valid"])
    flipped = copy.deepcopy(vectors)
    hx = flipped[first_valid]["hex"]
    flipped[first_valid]["hex"] = hx[:-2] + f"{int(hx[-2:], 16) ^ 0x01:02x}"
    problems = check_vectors(flipped)
    expect(len(problems) == 1 and "hex drift" in problems[0], f"one flipped byte in vector {first_valid} is caught: {problems[:1]}")
    changed = copy.deepcopy(vectors)
    first_bad = next(i for i, v in enumerate(vectors) if not v["valid"])
    changed[first_bad]["reason"] = "something else"
    problems = check_vectors(changed)
    expect(len(problems) == 1 and "expected reason" in problems[0], "a changed rejection reason is caught")
    thin = [v for v in vectors if v["name"] != "Sell"]
    problems = check_vectors(thin)
    expect(len(problems) == 1 and problems[0].startswith("Sell:"), "a message with no vectors is caught")
    expect(len({MESSAGES[n]["id"] for n in MESSAGES}) == len(MESSAGES) and all(ID_MIN <= m["id"] <= ID_MAX for m in MESSAGES.values()), "ids unique and in 32..63")
    expect(all((m["dir"] == "C2S") == (m["id"] <= C2S_MAX) for m in MESSAGES.values()), "C2S ids 32..47, S2C ids 48..63")
    expect(all(s in STATES for m in MESSAGES.values() for s in m["states"]), "every sender state is an F1 state")
    print(f"selftest: {'PASS' if fails == 0 else 'FAIL ' + str(fails)} ({summary(vectors)})")
    return 1 if fails else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="v3 net vectors: generate, --check, --selftest")
    ap.add_argument("--out", type=Path, default=FIXTURES, help="output folder (default tests/fixtures)")
    ap.add_argument("--check", nargs="?", const=FIXTURES / JSON_NAME, type=Path, metavar="JSON", help="verify a vectors file against a fresh encode")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return run_selftest()
    if args.check is not None:
        return run_check(args.check)
    vectors = build_vectors()
    problems = check_vectors(vectors)
    if problems:
        for p in problems:
            print("  " + p)
        print("net_vectors_v3: FAIL (the generator disagrees with itself)")
        return 1
    jp, lp = write(args.out, vectors)
    print(f"net_vectors_v3: wrote {summary(vectors)} to {jp} and {lp}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
