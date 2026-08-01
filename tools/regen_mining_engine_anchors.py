# -*- coding: utf-8 -*-
"""Regenerate engine_anchors.json for mining hulls (multi-nozzle) without rewriting GLB."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from import_mining_pc_meshes import (  # noqa: E402
    HULLS,
    PACKS,
    engine_anchors_local,
    extract_mesh_with_uv,
    to_godot_axes,
)
from stage_mining_threeviews import Gr2Meshes, auto_orient  # noqa: E402


def main() -> int:
    for key, res, _tex in HULLS:
        print(f"== {key}")
        g = Gr2Meshes(fetch_resfile(res))
        _n, verts, faces, _u, _s = extract_mesh_with_uv(g)
        verts = to_godot_axes(auto_orient(verts, faces))
        anchors = engine_anchors_local(verts, faces)
        out = PACKS / key / "engine_anchors.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            json.dumps({"model_key": key, "anchors_mesh_local": anchors}, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"  {len(anchors)} nozzles -> {out}")
        for a in anchors:
            print(f"    {a}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
