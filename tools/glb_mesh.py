# -*- coding: utf-8 -*-
"""Minimal GLB reader: world-space vertex cloud (node transforms applied)."""
from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np


def glb_chunks(path: Path):
    b = path.read_bytes()
    if b[:4] != b"glTF":
        raise ValueError(f"not a GLB: {path}")
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


def _local_matrix(node: dict) -> np.ndarray:
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


def world_vertices(path: Path) -> np.ndarray | None:
    j, binb = glb_chunks(path)
    parent: dict[int, int] = {}
    for i, n in enumerate(j["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    chunks = []
    for ni, n in enumerate(j["nodes"]):
        if "mesh" not in n:
            continue
        m = _local_matrix(n)
        cur = ni
        while cur in parent:
            cur = parent[cur]
            m = _local_matrix(j["nodes"][cur]) @ m
        for pr in j["meshes"][n["mesh"]]["primitives"]:
            acc = j["accessors"][pr["attributes"]["POSITION"]]
            if acc.get("componentType") != 5126 or acc.get("type") != "VEC3":
                continue
            bv = j["bufferViews"][acc["bufferView"]]
            off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = bv.get("byteStride") or 12
            cnt = acc["count"]
            raw = np.frombuffer(
                binb, dtype=np.uint8, count=cnt * stride, offset=off
            ).reshape(cnt, stride)[:, :12]
            arr = raw.copy().view(np.float32).reshape(cnt, 3).astype(float)
            h = np.concatenate([arr, np.ones((cnt, 1))], axis=1)
            chunks.append((m @ h.T).T[:, :3])
    if not chunks:
        return None
    return np.concatenate(chunks, axis=0)
