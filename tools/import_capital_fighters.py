# -*- coding: utf-8 -*-
"""Import carrier fighter §0 GLBs from PC GR2 (FileInfo.Meshes parse → OBJ → Assimp)."""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from rewrite_visual_maps import main as rewrite_visual_maps  # noqa: E402
from stage_fighter_threeviews import Gr2Meshes, pick_best_mesh, auto_orient  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"

FIGHTERS = [
    ("equite", "res:/dx9/model/ship/amarr/fighter/afi1/afi1_t1.gr2"),
    ("locust", "res:/dx9/model/ship/caldari/fighter/cfi1/cfi1_t1.gr2"),
    ("satyr", "res:/dx9/model/ship/gallente/fighter/gfi1/gfi1_t1.gr2"),
    ("gram", "res:/dx9/model/ship/minmatar/fighter/mfi1/mfi1_t1.gr2"),
]


def write_obj(path: Path, verts: np.ndarray, faces: np.ndarray) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("# fighter import\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for tri in faces:
            f.write(f"f {tri[0]+1} {tri[1]+1} {tri[2]+1}\n")


def ensure_albedo(out_dir: Path, tint: tuple[int, int, int]) -> None:
    dst = out_dir / "albedo.png"
    if dst.is_file() and dst.stat().st_size > 500:
        return
    im = Image.new("RGBA", (256, 256), (*tint, 255))
    im.save(dst)


def import_one(key: str, res_path: str) -> None:
    print(f"== {key}")
    gr2 = fetch_resfile(res_path)
    g = Gr2Meshes(gr2)
    _name, verts, faces = pick_best_mesh(g)
    verts = auto_orient(verts, faces)
    out_dir = PACKS / key
    out_dir.mkdir(parents=True, exist_ok=True)
    glb = out_dir / "model.glb"
    with tempfile.TemporaryDirectory(prefix="fighter_") as td:
        obj = Path(td) / f"{key}.obj"
        write_obj(obj, verts, faces)
        assimp_convert(obj, glb, "glb2")
    print(f"  glb {glb.stat().st_size} verts={len(verts)} tris={len(faces)}")
    tints = {
        "equite": (180, 160, 120),
        "locust": (120, 150, 180),
        "satyr": (120, 170, 130),
        "gram": (170, 120, 110),
    }
    ensure_albedo(out_dir, tints.get(key, (140, 140, 140)))


def main() -> int:
    for key, res in FIGHTERS:
        try:
            import_one(key, res)
        except Exception as e:
            print(f"FAIL {key}: {e}")
            return 1
    rewrite_visual_maps()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
