# -*- coding: utf-8 -*-
"""Derive a hull's nozzles from the pack mesh itself, for hulls with no usable SOF record.

`fit_bow_yaw_from_nozzles.py` is the normal path: it maps the SOF booster cloud onto the
mesh. That needs the SOF record to belong to *this* hull. Where it does not (e.g. an
Echoes model whose `sof_hull` points at another ship), the booster positions are
meaningless and land off the hull.

Here the stern face of the mesh is the only evidence, so it is used directly: take the
aft-most slab, find the separate blobs of geometry in it, and treat each blob as one
nozzle. Output goes to the pack's `engine_boosters.json` `bow_fit`, the same contract
`ShipUnit._load_baked_nozzles` consumes (0..1 inside the post-yaw mesh AABB).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
import trimesh
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"


def yaw_matrix(deg: float) -> np.ndarray:
    a = math.radians(deg)
    return np.array(
        [[math.cos(a), 0.0, math.sin(a)], [0.0, 1.0, 0.0], [-math.sin(a), 0.0, math.cos(a)]]
    )


def load_mesh(key: str) -> np.ndarray:
    scene = trimesh.load(PACKS / key / "model.glb", force="scene")
    parts = [np.asarray(g.vertices) for g in scene.geometry.values()]
    return np.vstack(parts)


def find_nozzles(
    verts: np.ndarray, slab_frac: float, grid: int, min_cells: int
) -> tuple[list[np.ndarray], list[float], float]:
    """Blobs in the aft slab. Stern is +Z here (ShipUnit convention)."""
    z_len = float(verts[:, 2].max() - verts[:, 2].min())
    z_cut = float(verts[:, 2].max()) - z_len * slab_frac
    slab = verts[verts[:, 2] >= z_cut]
    if len(slab) < min_cells:
        return [], [], z_cut

    lo = slab[:, :2].min(0)
    hi = slab[:, :2].max(0)
    span = np.maximum(hi - lo, 1e-6)
    cell = float(span.max()) / float(grid)
    ij = np.floor((slab[:, :2] - lo) / cell).astype(int)
    ij = np.clip(ij, 0, grid)
    occ = np.zeros((grid + 1, grid + 1), dtype=bool)
    occ[ij[:, 0], ij[:, 1]] = True
    ## 8-connectivity: nozzle rims are rings, and a 4-connected ring can break apart.
    labels, n = ndimage.label(occ, structure=np.ones((3, 3), dtype=int))
    if n == 0:
        return [], [], z_cut

    vert_label = labels[ij[:, 0], ij[:, 1]]
    centres: list[np.ndarray] = []
    radii: list[float] = []
    for li in range(1, n + 1):
        members = slab[vert_label == li]
        if len(members) < min_cells:
            continue
        c = members.mean(0)
        ## Radius from the blob's planar footprint, not its vertex spread, so a dense
        ## rim and a sparse disc of the same size give the same plume width.
        area = float((labels == li).sum()) * cell * cell
        radii.append(math.sqrt(area / math.pi))
        centres.append(np.array([c[0], c[1], float(members[:, 2].max())]))
    return centres, radii, z_cut


def fit(key: str, yaw_deg: float, slab_frac: float, grid: int, min_cells: int) -> dict | None:
    verts = load_mesh(key)
    rot = verts @ yaw_matrix(yaw_deg).T
    centres, radii, z_cut = find_nozzles(rot, slab_frac, grid, min_cells)
    if not centres:
        print(f"{key}: no nozzle blobs in the aft {slab_frac:.0%} slab")
        return None

    lo, hi = rot.min(0), rot.max(0)
    size = np.maximum(hi - lo, 1e-6)
    norm = [((c - lo) / size) for c in centres]
    longest = float(size.max())
    order = np.argsort([-c[2] for c in centres])
    print(f"{key}: yaw={yaw_deg:.0f} slab z>={z_cut:.1f} of {lo[2]:.1f}..{hi[2]:.1f} -> {len(centres)} nozzle(s)")
    for i in order:
        n = norm[i]
        print(
            f"    centre={np.round(centres[i], 1)} norm=({n[0]:.3f},{n[1]:.3f},{n[2]:.3f}) "
            f"r={radii[i]:.1f}"
        )
    return {
        "sof_hull": None,
        "model_yaw_deg": float(yaw_deg),
        "nozzles_ship_norm": [[round(float(v), 6) for v in norm[i]] for i in order],
        "nozzle_radius_norm": [round(float(radii[i] / longest), 6) for i in order],
        "rule": "nozzles read off the mesh aft face; pack SOF record belongs to another hull",
        "slab_frac": slab_frac,
        "grid": grid,
        "min_cells": min_cells,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="+")
    ap.add_argument("--yaw", type=float, default=180.0, help="ShipUnit model yaw for the pack")
    ap.add_argument("--slab", type=float, default=0.04, help="aft fraction of hull length")
    ap.add_argument("--grid", type=int, default=64)
    ap.add_argument("--min-cells", type=int, default=12)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    written = 0
    for key in args.keys:
        r = fit(key, args.yaw, args.slab, args.grid, args.min_cells)
        if r is None or not args.write:
            continue
        ebj = PACKS / key / "engine_boosters.json"
        doc = json.loads(ebj.read_text(encoding="utf-8"))
        doc["bow_fit"] = r
        ebj.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        written += 1
    print(f"written={written}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
