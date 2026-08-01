# -*- coding: utf-8 -*-
"""Decide hull bow/stern from SOF booster facing, not booster position.

A booster can sit anywhere on the hull (pylons, mid-body sponsons), but its plume
always fires aft. The SOF transform is row-major: rows 0..2 are the scaled local
basis and row 3 is the translation, so row 2 normalised is the plume axis.

Reports, per hull, the plume axis in raw GR2 model space and the same axis pushed
through the staging `auto_orient` remap, so a hull that ends up with its bow at +X
(convention is -X) is visible as a sign flip against the known-good hulls.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best  # noqa: E402
from stage_mining_threeviews import orient_basis  # noqa: E402

BOOSTERS = ROOT / "tools" / "_extracted" / "sof_hull_boosters.json"

## Supercarrier hull numbers are per-race, not uniform — see
## stage_supercarrier_ingame_bundles.py. These must mirror what that script stages.
HULLS = {
    "aca1_t1": ("tq_supercarrier_a", "res:/dx9/model/ship/amarr/carrier/aca1/aca1_t1_lowdetail.gr2"),
    "cca2_t1": ("tq_supercarrier_c", "res:/dx9/model/ship/caldari/carrier/cca2/cca2_t1_lowdetail.gr2"),
    "gca1_t1": ("tq_supercarrier_g", "res:/dx9/model/ship/gallente/carrier/gca1/gca1_t1_lowdetail.gr2"),
    "mca1_t1": ("tq_supercarrier_m", "res:/dx9/model/ship/minmatar/carrier/mca1/mca1_t1.gr2"),
    "at1_t1": ("tq_titan_a", "res:/dx9/model/ship/amarr/titan/at1/at1_t1_lowdetail.gr2"),
    "mt1_t1": ("tq_titan_m", "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1_lowdetail.gr2"),
}


def orient_matrix(
    verts: np.ndarray, faces: np.ndarray, aft_hint: np.ndarray | None = None
) -> tuple[np.ndarray, bool]:
    """Remap + flip actually used by the exporter, so probes can't drift from it."""
    m, flipped, _why = orient_basis(verts, faces, aft_hint)
    return m, flipped


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hulls", nargs="*", default=list(HULLS))
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    data = json.loads(BOOSTERS.read_text(encoding="utf-8"))
    for hull in args.hulls:
        key, res = HULLS[hull]
        items = (data.get(hull) or {}).get("items") or []
        if not items:
            print(f"{hull}: no booster items")
            continue

        axes = []
        pos = []
        for it in items:
            t = np.asarray(it["transform"], dtype=np.float64)
            z = t[2, :3]
            n = float(np.linalg.norm(z))
            if n < 1e-9:
                continue
            axes.append(z / n)
            pos.append(t[3, :3])
        axes_arr = np.asarray(axes)
        pos_arr = np.asarray(pos)
        plume = axes_arr.mean(axis=0)
        plume /= max(float(np.linalg.norm(plume)), 1e-9)
        agree = float(np.mean(axes_arr @ plume))

        verts, faces, _uvs, _stride, _uv = _extract_best(MultiSectionGr2(Path(fetch_resfile(res))))
        m, flipped = orient_matrix(verts, faces)

        plume_o = m @ plume
        pos_o = pos_arr @ m.T
        verts_o = verts @ m.T
        if flipped:
            plume_o = plume_o * np.array([-1.0, 1.0, 1.0])
            pos_o = pos_o * np.array([-1.0, 1.0, 1.0])
            verts_o = verts_o * np.array([-1.0, 1.0, 1.0])

        used = np.unique(faces.reshape(-1))
        hull_mid = float(verts_o[used, 0].mean())
        print(
            f"{hull:<8s} {key:<20s} nozzles={len(axes_arr)} axis_agree={agree:.3f}\n"
            f"    raw plume axis   = {np.round(plume, 3)}\n"
            f"    oriented plume X = {plume_o[0]:+.3f}   (want +1: plume fires toward +X aft)\n"
            f"    nozzle mean X    = {pos_o[:, 0].mean():+.1f}  hull mid X = {hull_mid:+.1f}"
            f"  flipped_by_heuristic={flipped}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
