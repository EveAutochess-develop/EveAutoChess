# -*- coding: utf-8 -*-
"""Probe model.glb hull profile: long axis + thickness taper (nose = thin end)."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
AXES = "XYZ"


def glb_chunks(path: Path):
    b = path.read_bytes()
    assert b[:4] == b"glTF", path
    off = 12
    js = None
    binb = None
    while off < len(b):
        ln, ty = struct.unpack("<II", b[off : off + 8])
        off += 8
        data = b[off : off + ln]
        off += ln
        if ty == 0x4E4F534A:
            js = json.loads(data.decode("utf-8", "replace"))
        elif ty == 0x004E4942:
            binb = data
    return js, binb


def local_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    t = np.array(node.get("translation", [0, 0, 0]), dtype=float)
    s = np.array(node.get("scale", [1, 1, 1]), dtype=float)
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rot = np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )
    m = np.eye(4)
    m[:3, :3] = rot * s
    m[:3, 3] = t
    return m


def world_vertices(path: Path):
    j, binb = glb_chunks(path)
    parent: dict[int, int] = {}
    for i, n in enumerate(j["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    chunks = []
    for ni, n in enumerate(j["nodes"]):
        if "mesh" not in n:
            continue
        m = local_matrix(n)
        cur = ni
        while cur in parent:
            cur = parent[cur]
            m = local_matrix(j["nodes"][cur]) @ m
        for pr in j["meshes"][n["mesh"]]["primitives"]:
            acc = j["accessors"][pr["attributes"]["POSITION"]]
            bv = j["bufferViews"][acc["bufferView"]]
            off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = bv.get("byteStride") or 12
            cnt = acc["count"]
            arr = np.zeros((cnt, 3))
            for k in range(cnt):
                arr[k] = struct.unpack_from("<3f", binb, off + k * stride)
            h = np.concatenate([arr, np.ones((cnt, 1))], axis=1)
            chunks.append((m @ h.T).T[:, :3])
    return np.concatenate(chunks, axis=0) if chunks else None


def profile(path: Path, bins: int = 10):
    v = world_vertices(path)
    if v is None:
        return None
    size = v.max(0) - v.min(0)
    ax = int(np.argmax(size))
    lo, hi = float(v.min(0)[ax]), float(v.max(0)[ax])
    others = [i for i in range(3) if i != ax]
    edges = np.linspace(lo, hi, bins + 1)
    prof = []
    for i in range(bins):
        m = (v[:, ax] >= edges[i]) & (v[:, ax] < edges[i + 1])
        if int(m.sum()) < 3:
            prof.append(0.0)
            continue
        sub = v[m][:, others]
        prof.append(float(np.abs(sub - sub.mean(0)).max()))
    return {
        "axis": AXES[ax],
        "size": [round(float(x), 2) for x in size],
        "lo": round(lo, 2),
        "hi": round(hi, 2),
        "profile": [round(x, 2) for x in prof],
    }


def main(keys: list[str]) -> int:
    for key in keys:
        p = PACKS / key / "model.glb"
        if not p.is_file():
            print(f"{key:20s} NO GLB")
            continue
        r = profile(p)
        if r is None:
            print(f"{key:20s} no vertices")
            continue
        print(
            f"{key:20s} long={r['axis']} size={r['size']} range=({r['lo']}..{r['hi']}) "
            f"thickness_lo→hi={r['profile']}"
        )
    return 0


if __name__ == "__main__":
    args = sys.argv[1:] or [
        "equite",
        "locust",
        "satyr",
        "gram",
        "wrj_a_shiseng",
        "wrj_g_dijingling",
        "heavy_repair_amarr",
        "am_chengfazhe",
    ]
    raise SystemExit(main(args))
