# -*- coding: utf-8 -*-
"""Import EVE Tranquility asteroid-belt rock meshes → Godot GLB pack.

Source: res:/dx9/model/celestial/asteroid/rock_* and
        res:/dx9/model/celestial/environment/rock/asteroidset_01/*
Pipeline: fetch GR2 → Gr2Meshes → OBJ → Assimp glb2.
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
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from stage_fighter_threeviews import Gr2Meshes, auto_orient, pick_best_mesh  # noqa: E402

OUT = ROOT / "godot_project" / "assets" / "models" / "env" / "asteroids"
MANIFEST = OUT / "manifest.json"

# Prefer small/medium ore rocks + asteroid-belt set variants for board scatter.
SOURCES: list[tuple[str, str]] = [
    ("as1_s_01", "res:/dx9/model/celestial/environment/rock/asteroidset_01/small/as1_s_01/as1_s_01.gr2"),
    ("as1_s_02", "res:/dx9/model/celestial/environment/rock/asteroidset_01/small/as1_s_02/as1_s_02.gr2"),
    ("as1_s_03", "res:/dx9/model/celestial/environment/rock/asteroidset_01/small/as1_s_03/as1_s_03.gr2"),
    ("as1_m_01", "res:/dx9/model/celestial/environment/rock/asteroidset_01/medium/as1_m_01/as1_m_01.gr2"),
    ("as1_m_02", "res:/dx9/model/celestial/environment/rock/asteroidset_01/medium/as1_m_02/as1_m_02.gr2"),
    ("as1_m_03", "res:/dx9/model/celestial/environment/rock/asteroidset_01/medium/as1_m_03/as1_m_03.gr2"),
    ("rock_01_m_v1", "res:/dx9/model/celestial/asteroid/rock_01/medium/rock_01_m_v1.gr2"),
    ("rock_01_m_v2", "res:/dx9/model/celestial/asteroid/rock_01/medium/rock_01_m_v2.gr2"),
    ("rock_02_m_v1", "res:/dx9/model/celestial/asteroid/rock_02/medium/rock_02_m_v1.gr2"),
    ("rock_03_v1", "res:/dx9/model/celestial/asteroid/rock_03/rock_03v1.gr2"),
    ("rock_03_v2", "res:/dx9/model/celestial/asteroid/rock_03/rock_03v2.gr2"),
    ("rock_05_v01", "res:/dx9/model/celestial/asteroid/rock_05/rock_05v01.gr2"),
]


def write_obj(path: Path, verts: np.ndarray, faces: np.ndarray) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as f:
        f.write("# eve asteroid\n")
        for v in verts:
            f.write(f"v {float(v[0]):.6f} {float(v[1]):.6f} {float(v[2]):.6f}\n")
        for tri in faces:
            f.write(f"f {int(tri[0]) + 1} {int(tri[1]) + 1} {int(tri[2]) + 1}\n")


def import_one(stem: str, res_path: str) -> dict:
    dst = OUT / f"{stem}.glb"
    gr2 = fetch_resfile(res_path)
    g = Gr2Meshes(gr2)
    name, verts, faces = pick_best_mesh(g)
    verts = auto_orient(verts, faces)
    with tempfile.TemporaryDirectory(prefix="ast_") as td:
        obj = Path(td) / f"{stem}.obj"
        write_obj(obj, verts, faces)
        assimp_convert(obj, dst, "glb2")
    return {
        "stem": stem,
        "res": res_path,
        "glb": str(dst.relative_to(ROOT / "godot_project")).replace("\\", "/"),
        "mesh": name,
        "verts": int(len(verts)),
        "tris": int(len(faces)),
        "bytes": dst.stat().st_size,
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []
    for stem, res in SOURCES:
        try:
            row = import_one(stem, res)
            print(f"[ok] {stem} verts={row['verts']} tris={row['tris']} -> {row['glb']}")
            results.append(row)
        except Exception as e:
            print(f"[fail] {stem}: {type(e).__name__}: {e}")
            results.append({"stem": stem, "res": res, "error": str(e)})
    MANIFEST.write_text(json.dumps({"asteroids": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    ok = sum(1 for r in results if "glb" in r)
    print(f"done {ok}/{len(SOURCES)} -> {MANIFEST}")


if __name__ == "__main__":
    main()
