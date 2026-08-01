# -*- coding: utf-8 -*-
"""Top/side views of staged hulls with SOF nozzles overlaid in the same space.

The nozzle cloud is the ground truth for which end is aft, so drawing it on top of
the exported silhouette makes a reversed `auto_orient` flip obvious. Shipped hulls
land stern-on-(-X), so the dots belong on the -X end — compare against the titans,
which are the confirmed-good reference.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import trimesh
from PIL import ImageDraw

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from _probe_bow_from_boosters import HULLS, orient_matrix  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best  # noqa: E402
from sof_orientation import hull_aft_axis  # noqa: E402
from stage_mining_threeviews import render_ortho  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
BOOSTERS = ROOT / "tools" / "_extracted" / "sof_hull_boosters.json"
AXES = {"side": (0, 1), "top": (0, 2)}


def load_glb(path: Path) -> tuple[np.ndarray, np.ndarray]:
    scene = trimesh.load(path, force="scene")
    mesh = trimesh.util.concatenate(
        [g for g in scene.geometry.values() if isinstance(g, trimesh.Trimesh)]
    )
    return np.asarray(mesh.vertices, dtype=np.float64), np.asarray(mesh.faces, dtype=np.int64)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hulls", nargs="*", default=list(HULLS))
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--size", type=int, default=520)
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    args.out.mkdir(parents=True, exist_ok=True)

    data = json.loads(BOOSTERS.read_text(encoding="utf-8"))
    for hull in args.hulls:
        key, res = HULLS[hull]
        glb = PACKS / key / "model.glb"
        if not glb.is_file():
            print(f"{hull} {key}: no model.glb")
            continue

        raw_v, raw_f, _u, _s, _o = _extract_best(MultiSectionGr2(Path(fetch_resfile(res))))
        raw_centroid = raw_v[np.unique(raw_f.reshape(-1))].mean(axis=0)
        m, flipped = orient_matrix(raw_v, raw_f, hull_aft_axis(hull, raw_centroid))
        sof = np.asarray(
            [it["transform"][3][:3] for it in (data.get(hull) or {}).get("items") or []],
            dtype=np.float64,
        )
        sof_o = sof @ m.T
        if flipped:
            sof_o = sof_o * np.array([-1.0, 1.0, 1.0])

        verts, faces = load_glb(glb)
        used = np.unique(faces.reshape(-1))
        center = verts[used].mean(axis=0)
        radius = float(np.abs(verts[used] - center).max()) * 1.05

        for view, (ax_h, ax_v) in AXES.items():
            img = render_ortho(verts, faces, view, size=args.size).convert("RGB")
            draw = ImageDraw.Draw(img)
            half = args.size * 0.5
            for p in sof_o - center:
                px = half + p[ax_h] / radius * half
                py = half - p[ax_v] / radius * half
                draw.ellipse([px - 4, py - 4, px + 4, py + 4], fill=(255, 40, 40))
            draw.text((6, 6), f"{key} {view}  TQ convention: stern LEFT(-X)", fill=(120, 220, 255))
            img.save(args.out / f"{key}_{view}_nozzles.png")
        print(f"{hull} {key}: flipped={flipped} nozzle_mean_X={sof_o[:,0].mean():+.0f} "
              f"hull_center_X={center[0]:+.0f}")
    print(f"wrote -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
