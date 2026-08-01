# -*- coding: utf-8 -*-
"""Does the span-heuristic bow pick disagree with the SOF nozzle cloud on titans?

The four titans are the only TQ hulls the main game loads (defs 201-204 set
`model_auto_orient`), so this answers whether the Aeon/Hel reversal also shipped
in-game. Both GR2 LODs are checked because staging falls back between them.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from _probe_bow_from_boosters import orient_matrix  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best  # noqa: E402
from sof_orientation import aft_report, hull_aft_axis  # noqa: E402

TITANS = {
    "at1_t1": ("tq_titan_a", "amarr/titan/at1/at1_t1"),
    "ct1_t1": ("tq_titan_c", "caldari/titan/ct1/ct1_t1"),
    "gt1_t1": ("tq_titan_g", "gallente/titan/gt1/gt1_t1"),
    "mt1_t1": ("tq_titan_m", "minmatar/titan/mt1/mt1_t1"),
}


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    bad = 0
    for hull, (key, stem) in TITANS.items():
        for suffix in ("", "_lowdetail"):
            res = f"res:/dx9/model/ship/{stem}{suffix}.gr2"
            try:
                v, f, *_ = _extract_best(MultiSectionGr2(Path(fetch_resfile(res))))
            except Exception as e:
                print(f"{key}{suffix}: skip ({e})")
                continue
            centroid = v[np.unique(f.reshape(-1))].mean(axis=0)
            _m, old = orient_matrix(v, f)
            _m, new = orient_matrix(v, f, hull_aft_axis(hull, centroid))
            flag = "OK" if old == new else "REVERSED"
            if old != new:
                bad += 1
            print(f"{key}{suffix or '(full)':<12s} span_flip={old} sof_flip={new} {flag}")
            print(f"    {aft_report(hull, centroid)}")
    print(f"\ndisagreements={bad}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
