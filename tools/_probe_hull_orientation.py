# -*- coding: utf-8 -*-
"""Render side/top views of staged ship model.glb and report bow direction.

`auto_orient` picks the nose by cross-section span: whichever half has the smaller
Y/Z span is treated as the bow and pushed to -X. Hulls whose widest point is at the
bow (some Minmatar designs) come out reversed, which is invisible in the staging log
because the sym score only reports the beam-axis pick.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import trimesh

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))

from stage_mining_threeviews import render_ortho  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"


def load_glb(path: Path) -> tuple[np.ndarray, np.ndarray]:
    scene = trimesh.load(path, force="scene")
    mesh = trimesh.util.concatenate(
        [g for g in scene.geometry.values() if isinstance(g, trimesh.Trimesh)]
    )
    return np.asarray(mesh.vertices, dtype=np.float64), np.asarray(mesh.faces, dtype=np.int64)


def describe(verts: np.ndarray, faces: np.ndarray) -> str:
    used = np.unique(faces.reshape(-1))
    v = verts[used]
    ext = np.ptp(v, axis=0)
    length_ax = int(np.argmax(ext))
    mid = float(v[:, length_ax].mean())
    hi = v[v[:, length_ax] > mid]
    lo = v[v[:, length_ax] <= mid]
    others = [i for i in range(3) if i != length_ax]

    def span(part: np.ndarray) -> float:
        return float(np.ptp(part[:, others], axis=0).sum()) if len(part) >= 8 else float("nan")

    return (
        f"length_ax={length_ax} ext={np.round(ext, 1)} "
        f"span(+)={span(hi):.1f} span(-)={span(lo):.1f} "
        f"narrow_end={'+' if span(hi) < span(lo) else '-'}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("keys", nargs="+")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--size", type=int, default=420)
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    args.out.mkdir(parents=True, exist_ok=True)
    for key in args.keys:
        glb = PACKS / key / "model.glb"
        if not glb.is_file():
            print(f"{key}: no model.glb")
            continue
        verts, faces = load_glb(glb)
        print(f"{key}: verts={len(verts)} tris={len(faces)} {describe(verts, faces)}")
        for view in ("side", "top"):
            img = render_ortho(verts, faces, view, size=args.size)
            img.save(args.out / f"{key}_{view}.png")
    print(f"wrote -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
