# -*- coding: utf-8 -*-
"""Build §0 titan bundles (TQ mesh+maps) for doomsday preview / in-game look pipeline.

Keys: tq_titan_a / tq_titan_c / tq_titan_g / tq_titan_m
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from bake_pc_textures import bake_bundle_for_res_path  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from stage_mining_threeviews import Gr2Meshes, auto_orient, pick_best_mesh  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
REVIEW = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\doomsday_preview"
)

TITANS = [
    {
        "key": "tq_titan_a",
        "race": "A",
        "zh": "圣像级",
        "en": "Avatar",
        "gr2": [
            "res:/dx9/model/ship/amarr/titan/at1/at1_t1.gr2",
            "res:/dx9/model/ship/amarr/titan/at1/at1_t1_lowdetail.gr2",
            "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck_lowdetail.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/amarr/titan/at1/at1_t1.gr2",
        # TQ titans ~18km class; curve clamps at max_mul — keep above dread (~580).
        "model_long_axis": 2200.0,
    },
    {
        "key": "tq_titan_c",
        "race": "C",
        "zh": "利维坦级",
        "en": "Leviathan",
        "gr2": [
            "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1.gr2",
            "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1_lowdetail.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1.gr2",
        "model_long_axis": 2200.0,
    },
    {
        "key": "tq_titan_g",
        "race": "G",
        "zh": "厄勒布洛斯级",
        "en": "Erebus",
        "gr2": [
            "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1_lowdetail.gr2",
            "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1.gr2",
        "model_long_axis": 2200.0,
    },
    {
        "key": "tq_titan_m",
        "race": "M",
        "zh": "诸神黄昏级",
        "en": "Ragnarok",
        "gr2": [
            "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1.gr2",
            "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1_lowdetail.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1.gr2",
        "model_long_axis": 2200.0,
    },
]


def write_obj(verts: np.ndarray, faces: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", errors="replace") as f:
        f.write("# titan §0\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for tri in faces:
            f.write(f"f {int(tri[0]) + 1} {int(tri[1]) + 1} {int(tri[2]) + 1}\n")


def export_glb(t: dict) -> dict:
    out = PACKS / t["key"]
    out.mkdir(parents=True, exist_ok=True)
    last = ""
    for res in t["gr2"]:
        try:
            print(f"[mesh] {t['key']} <- {res}")
            g = Gr2Meshes(Path(fetch_resfile(res)))
            name, verts, faces = pick_best_mesh(g)
            verts = auto_orient(verts, faces)
            obj = out / "_tmp.obj"
            write_obj(verts, faces, obj)
            glb = out / "model.glb"
            assimp_convert(obj, glb, "glb2")
            obj.unlink(missing_ok=True)
            # also mirror into preview folder for review pack
            dst = REVIEW / "titans" / t["race"]
            dst.mkdir(parents=True, exist_ok=True)
            shutil.copy2(glb, dst / "model.glb")
            return {
                "key": t["key"],
                "status": "ok",
                "mesh": name,
                "res": res,
                "verts": int(len(verts)),
                "tris": int(len(faces)),
            }
        except Exception as e:
            last = str(e)
            print(f"  fail: {e}")
    return {"key": t["key"], "status": "fail", "error": last}


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass
    reports = []
    for t in TITANS:
        mesh = export_glb(t)
        print(f"[tex] {t['key']}")
        try:
            written = bake_bundle_for_res_path(t["key"], t["bake_gr2"])
        except Exception as e:
            written = {"error": str(e)}
            print(f"  bake fail: {e}")
        mesh["textures"] = written
        mesh["model_long_axis"] = t["model_long_axis"]
        reports.append(mesh)
    REVIEW.mkdir(parents=True, exist_ok=True)
    (REVIEW / "ingame_bundles.json").write_text(
        json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    ok = sum(1 for r in reports if r.get("status") == "ok")
    print(f"done ok={ok}/{len(reports)} -> {PACKS}")


if __name__ == "__main__":
    main()
