#!/usr/bin/env python3
"""Print merged POSITION bounds (and node transforms) of a GLB, to find the hull long axis."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def read_glb_json(path: Path) -> dict:
    data = path.read_bytes()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError(f"not GLB: {path}")
    offset = 12
    while offset < len(data):
        chunk_len, chunk_type = struct.unpack_from("<I4s", data, offset)
        offset += 8
        if chunk_type == b"JSON":
            return json.loads(data[offset : offset + chunk_len])
        offset += chunk_len + (-chunk_len % 4)
    raise ValueError("no JSON chunk")


def main(paths: list[str]) -> None:
    for raw in paths:
        p = Path(raw)
        gltf = read_glb_json(p)
        lo = [float("inf")] * 3
        hi = [float("-inf")] * 3
        accessors = gltf.get("accessors", [])
        for mesh in gltf.get("meshes", []):
            for prim in mesh.get("primitives", []):
                idx = prim.get("attributes", {}).get("POSITION")
                if idx is None:
                    continue
                acc = accessors[idx]
                amin = acc.get("min")
                amax = acc.get("max")
                if not amin or not amax:
                    continue
                for i in range(3):
                    lo[i] = min(lo[i], amin[i])
                    hi[i] = max(hi[i], amax[i])
        size = [hi[i] - lo[i] for i in range(3)]
        axis = "XYZ"[size.index(max(size))]
        rotated_nodes = [
            n.get("name", "?")
            for n in gltf.get("nodes", [])
            if n.get("rotation") or n.get("matrix")
        ]
        print(f"{p.parent.name}: size x={size[0]:.1f} y={size[1]:.1f} z={size[2]:.1f} long={axis}")
        print(f"    min={[round(v,1) for v in lo]} max={[round(v,1) for v in hi]}")
        if rotated_nodes:
            print(f"    nodes with rotation/matrix: {rotated_nodes[:6]}")


if __name__ == "__main__":
    main(sys.argv[1:])
