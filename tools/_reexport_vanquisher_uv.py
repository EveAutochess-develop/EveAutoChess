# -*- coding: utf-8 -*-
"""Re-export Angel Vanquisher (angt1) with unorm16 UVs at byte offset 28.

Pick V vs 1-V by _m island hit rate. A hard V-flip against the DDS atlas
sends large hull areas into bright padding → unity-standard solid color plates.
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path[:0] = [
    str(ROOT / "tools"),
    str(ROOT / "tools" / "eve_pc"),
    str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"),
]

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.dds_decode import decode_dds  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, write_obj  # noqa: E402
from stage_mining_threeviews import auto_orient  # noqa: E402

KEY = "tsl_zhengfuzhe"
GODOT = ROOT / "godot_project" / "assets" / "models" / "ships" / KEY
DESIGN = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\preview\pirate_faction_ships\pc_models"
) / KEY
IMPORT_SNIPPET = """meshes/generate_lods=false
meshes/force_disable_compression=true
"""


def _island_hit(uvs: np.ndarray, mat: np.ndarray) -> float:
    h, w = mat.shape[:2]
    idx = np.linspace(0, len(uvs) - 1, min(120_000, len(uvs))).astype(int)
    u = np.mod(uvs[idx, 0], 1.0)
    v = np.mod(uvs[idx, 1], 1.0)
    x = np.clip((u * (w - 1)).astype(int), 0, w - 1)
    y = np.clip((v * (h - 1)).astype(int), 0, h - 1)
    return float((mat[y, x] > 8).mean())


def _glb_uvs(path: Path) -> np.ndarray:
    import struct

    data = path.read_bytes()
    off = 12
    chunks: list[tuple[bytes, bytes]] = []
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        off += 8
        chunks.append((ctype, data[off : off + clen]))
        off += clen
        if ctype == b"BIN\x00":
            break
    j = json.loads(chunks[0][1])
    blob = chunks[1][1]
    prim = j["meshes"][0]["primitives"][0]["attributes"]
    acc = j["accessors"][prim["TEXCOORD_0"]]
    bv = j["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return np.frombuffer(blob, dtype="<f4", count=acc["count"] * 2, offset=base).reshape(
        acc["count"], 2
    )


def _ensure_import_flags(dest: Path) -> None:
    imp = dest / "model.glb.import"
    if not imp.exists():
        return
    text = imp.read_text(encoding="utf-8")
    text = text.replace("meshes/generate_lods=true", "meshes/generate_lods=false")
    text = text.replace(
        "meshes/force_disable_compression=false",
        "meshes/force_disable_compression=true",
    )
    imp.write_text(text, encoding="utf-8")


def main() -> None:
    gr2 = Path(fetch_resfile("res:/dx9/model/ship/angel/titan/angt1/angt1_t1.gr2"))
    mat = np.asarray(
        decode_dds(
            Path(fetch_resfile("res:/dx9/model/ship/angel/titan/angt1/angt1_t1_m.dds"))
        ).convert("L")
    )
    g = MultiSectionGr2(gr2)
    _name, mref = g.mesh_list()[0]
    pvd = g.resolve_ptr(mref, g.off("mesh_vertex_data"))
    topo = g.resolve_ptr(mref, g.off("mesh_topology"))
    vcount, varr = g.aor(pvd, g.off("vertex_data_verts"))
    i16_count, i16_arr = g.aor(topo, g.off("topology_indices16"))
    if i16_arr and i16_count >= 3:
        idx = np.frombuffer(g.read_bytes(i16_arr, i16_count * 2), dtype="<u2").astype(np.int32)
    else:
        i32_count, i32_arr = g.aor(topo, g.off("topology_indices32"))
        idx = np.frombuffer(g.read_bytes(i32_arr, i32_count * 4), dtype="<u4").astype(np.int32)
    faces = idx[: (len(idx) // 3) * 3].reshape(-1, 3)
    faces = faces[(faces < vcount).all(1)]
    stride = 32
    blob = g.read_bytes(varr, vcount * stride)
    verts = np.frombuffer(blob, dtype="<f4").reshape(vcount, stride // 4)[:, :3].astype(np.float64)
    u16 = np.frombuffer(blob, dtype="<u2").reshape(vcount, stride // 2)
    raw = u16[:, 14:16].astype(np.float64) / 65535.0
    flipped = raw.copy()
    flipped[:, 1] = 1.0 - flipped[:, 1]
    hit_raw = _island_hit(raw, mat)
    hit_flip = _island_hit(flipped, mat)
    uvs = raw if hit_raw >= hit_flip else flipped
    v_mode = "raw" if hit_raw >= hit_flip else "vflip"
    print(f"pre-assimp island hit raw={hit_raw*100:.1f}% flip={hit_flip*100:.1f}% -> {v_mode}")

    mag = np.linalg.norm(verts, axis=1)
    sane = np.isfinite(mag) & (mag < 1e6)
    p50 = float(np.median(mag[sane]))
    keep = sane & (mag <= max(p50 * 8, 50))
    faces = faces[keep[faces].all(1)]
    print("faces", len(faces), "verts", vcount)
    verts = auto_orient(verts, faces)

    with tempfile.TemporaryDirectory(prefix="angt1_uv_") as td:
        td_path = Path(td)
        obj = td_path / "m.obj"
        glb = td_path / "m.glb"
        write_obj(verts, faces, uvs, obj)
        assimp_convert(obj, glb, "glb2")
        print("glb", glb.stat().st_size)
        post = _island_hit(_glb_uvs(glb), mat)
        print(f"post-assimp island hit={post*100:.1f}%")
        if post + 0.02 < max(hit_raw, hit_flip):
            ## Assimp flipped V; write the other convention and reconvert.
            other = flipped if v_mode == "raw" else raw
            write_obj(verts, faces, other, obj)
            assimp_convert(obj, glb, "glb2")
            post2 = _island_hit(_glb_uvs(glb), mat)
            print(f"compensated island hit={post2*100:.1f}%")
            v_mode = v_mode + "+assimp_compensate"
        for dest in (GODOT, DESIGN):
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy2(glb, dest / "model.glb")
            _ensure_import_flags(dest)

    for dest in (GODOT, DESIGN):
        sp = dest / "source_pc.json"
        meta = json.loads(sp.read_text(encoding="utf-8")) if sp.exists() else {}
        meta.update(
            {
                "uv_off": 28,
                "uv_format": "unorm16",
                "stride": 32,
                "uv_fix": f"byte28 unorm16 pick-by-_m-island ({v_mode})",
                "tris": int(len(faces)),
                "verts": int(vcount),
            }
        )
        sp.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("done", KEY)


if __name__ == "__main__":
    main()
