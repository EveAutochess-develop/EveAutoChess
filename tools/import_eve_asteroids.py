# -*- coding: utf-8 -*-
"""Import EVE Tranquility asteroid-belt rock meshes → Godot GLB pack (with UVs).

Source: res:/dx9/model/celestial/asteroid/rock_*
Pipeline: fetch GR2 → Gr2Meshes(+UV) → OBJ(v/vt) → Assimp glb2
          + bake rock_XX_{a,n,g,r}.dds → tex/*.png
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.dds_decode import decode_dds  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from stage_fighter_threeviews import (  # noqa: E402
    Gr2Meshes,
    auto_orient,
    pick_best_mesh_with_uv,
)

OUT = ROOT / "godot_project" / "assets" / "models" / "env" / "asteroids"
TEX_OUT = OUT / "tex"
MANIFEST = OUT / "manifest.json"

# Board-scatter set: medium/large/small TQ ore rocks that previously imported.
SOURCES: list[tuple[str, str]] = [
    ("rock_01_m_v1", "res:/dx9/model/celestial/asteroid/rock_01/medium/rock_01_m_v1.gr2"),
    ("rock_01_m_v2", "res:/dx9/model/celestial/asteroid/rock_01/medium/rock_01_m_v2.gr2"),
    ("rock_01_m_v3", "res:/dx9/model/celestial/asteroid/rock_01/medium/rock_01_m_v3.gr2"),
    ("rock_01_l_v1", "res:/dx9/model/celestial/asteroid/rock_01/large/rock_01_l_v1.gr2"),
    ("rock_02_m_v1", "res:/dx9/model/celestial/asteroid/rock_02/medium/rock_02_m_v1.gr2"),
    ("rock_02_m_v2", "res:/dx9/model/celestial/asteroid/rock_02/medium/rock_02_m_v2.gr2"),
    ("rock_02_m_v3", "res:/dx9/model/celestial/asteroid/rock_02/medium/rock_02_m_v3.gr2"),
    ("rock_02_l_v1", "res:/dx9/model/celestial/asteroid/rock_02/large/rock_02_l_v1.gr2"),
    ("rock_02_s_v1", "res:/dx9/model/celestial/asteroid/rock_02/small/rock_02_s_v1.gr2"),
    ("rock_06_v1", "res:/dx9/model/celestial/asteroid/rock_06/rock_06v1.gr2"),
]

TEX_SETS = ("rock_01", "rock_02", "rock_06")
TEX_SUFFIXES = {
    "_a": "albedo",
    "_n": "normal",
    "_g": "glow",
    "_r": "rough",
    "_d": "detail",
}


def write_obj_uv(path: Path, verts: np.ndarray, faces: np.ndarray, uvs: np.ndarray) -> None:
    """Wavefront OBJ with matching v/vt/vn indices (Assimp → GLB keeps TEXCOORD_0 + NORMAL)."""
    normals = _smooth_normals(verts, faces)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        f.write("# eve asteroid with UV\n")
        for v in verts:
            f.write(f"v {float(v[0]):.6f} {float(v[1]):.6f} {float(v[2]):.6f}\n")
        for uv in uvs:
            f.write(f"vt {float(uv[0]):.6f} {float(uv[1]):.6f}\n")
        for n in normals:
            f.write(f"vn {float(n[0]):.6f} {float(n[1]):.6f} {float(n[2]):.6f}\n")
        for tri in faces:
            a, b, c = int(tri[0]) + 1, int(tri[1]) + 1, int(tri[2]) + 1
            f.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")


def _smooth_normals(verts: np.ndarray, faces: np.ndarray) -> np.ndarray:
    normals = np.zeros_like(verts, dtype=np.float64)
    v0 = verts[faces[:, 0]]
    v1 = verts[faces[:, 1]]
    v2 = verts[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    for i in range(3):
        np.add.at(normals, faces[:, i], fn)
    lens = np.linalg.norm(normals, axis=1)
    lens[lens < 1e-12] = 1.0
    return normals / lens[:, None]


def bake_textures() -> list[str]:
    TEX_OUT.mkdir(parents=True, exist_ok=True)
    done: list[str] = []
    for rock in TEX_SETS:
        for suf, name in TEX_SUFFIXES.items():
            res = f"res:/dx9/model/celestial/asteroid/{rock}/{rock}{suf}.dds"
            try:
                src = fetch_resfile(res)
                im = decode_dds(src)
                if im is None:
                    print(f"[tex-fail] decode {res}")
                    continue
                dst = TEX_OUT / f"{rock}_{name}.png"
                im.save(dst)
                done.append(dst.name)
                print(f"[tex] {dst.name} {im.size}")
            except Exception as e:
                print(f"[tex-fail] {res}: {type(e).__name__}: {e}")
    return done


def import_one(stem: str, res_path: str) -> dict:
    dst = OUT / f"{stem}.glb"
    gr2 = fetch_resfile(res_path)
    g = Gr2Meshes(gr2)
    name, verts, faces, uvs = pick_best_mesh_with_uv(g)
    verts = auto_orient(verts, faces)
    with tempfile.TemporaryDirectory(prefix="ast_") as td:
        obj = Path(td) / f"{stem}.obj"
        write_obj_uv(obj, verts, faces, uvs)
        assimp_convert(obj, dst, "glb2")
    ## Verify TEXCOORD survived Assimp.
    has_uv = _glb_has_texcoord(dst)
    return {
        "stem": stem,
        "res": res_path,
        "glb": str(dst.relative_to(ROOT / "godot_project")).replace("\\", "/"),
        "mesh": name,
        "verts": int(len(verts)),
        "tris": int(len(faces)),
        "has_uv": has_uv,
        "bytes": dst.stat().st_size,
    }


def _glb_has_texcoord(path: Path) -> bool:
    import struct

    with path.open("rb") as f:
        f.read(12)
        while True:
            hdr = f.read(8)
            if len(hdr) < 8:
                return False
            clen, ctype = struct.unpack("<I4s", hdr)
            data = f.read(clen)
            if ctype == b"JSON":
                import json as _json

                j = _json.loads(data)
                attrs = j["meshes"][0]["primitives"][0].get("attributes", {})
                return any(k.startswith("TEXCOORD") for k in attrs)
    return False


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    tex_done = bake_textures()
    results: list[dict] = []
    for stem, res in SOURCES:
        try:
            row = import_one(stem, res)
            flag = "UV" if row.get("has_uv") else "NO-UV"
            print(f"[ok/{flag}] {stem} verts={row['verts']} tris={row['tris']} -> {row['glb']}")
            results.append(row)
        except Exception as e:
            print(f"[fail] {stem}: {type(e).__name__}: {e}")
            results.append({"stem": stem, "res": res, "error": str(e)})
    MANIFEST.write_text(
        json.dumps({"asteroids": results, "textures": tex_done}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    ok = sum(1 for r in results if "glb" in r)
    uv_ok = sum(1 for r in results if r.get("has_uv"))
    print(f"done {ok}/{len(SOURCES)} glb (uv={uv_ok}) tex={len(tex_done)} -> {MANIFEST}")


if __name__ == "__main__":
    main()
