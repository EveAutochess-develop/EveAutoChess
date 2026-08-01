# -*- coding: utf-8 -*-
"""Bake §0 texture bundles for the PVE sleeper hulls used in nullsec.

Meshes were already staged (model.glb); only albedo/normal/rg/pmwo/reduction
were missing, which made the creeps render as untextured white hulls.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from bake_pc_textures import bake_bundle_for_res_path  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"

# key -> TQ GR2 whose sibling *_a/_n/_r/_g/_m/_d DDS maps get baked.
HULLS = {
    "tq_sleeper_slf1": "res:/dx9/model/ship/sleeper/frigate/slf1/slf1_t1.gr2",
    "tq_sleeper_slf2": "res:/dx9/model/ship/sleeper/frigate/slf2/slf2_t1.gr2",
    "tq_sleeper_slde1": "res:/dx9/model/ship/sleeper/destroyer/slde1/slde1_t1.gr2",
    "tq_sleeper_slc1": "res:/dx9/model/ship/sleeper/cruiser/slc1/slc1_t1.gr2",
    "tq_sleeper_slb1": "res:/dx9/model/ship/sleeper/battleship/slb1/slb1_t1.gr2",
    "tq_freighter_cfr1": "res:/dx9/model/ship/caldari/freighter/cfr1/cfr1_t1.gr2",
    "tq_freighter_mfr1": "res:/dx9/model/ship/minmatar/freighter/mfr1/mfr1_t1.gr2",
    "tq_freighter_afr1": "res:/dx9/model/ship/amarr/freighter/afr1/afr1_t1.gr2",
    "tq_freighter_gfr1": "res:/dx9/model/ship/gallente/freighter/gfr1/gfr1_t1.gr2",
}


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass
    report = []
    for key, res in HULLS.items():
        if not (PACKS / key).exists():
            print(f"[skip] {key}: no bundle dir")
            continue
        print(f"[tex] {key} <- {res}")
        try:
            written = bake_bundle_for_res_path(key, res)
        except Exception as exc:  # keep going; one missing hull must not stop the batch
            written = {"error": str(exc)}
            print(f"  fail: {exc}")
        report.append({"key": key, "res": res, "written": written})
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
