# -*- coding: utf-8 -*-
"""Full-decode small BitKnit2 GR2 files and check the result is structurally sane.

Without a BitKnit-capable granny2.dll there is no byte oracle, so the GR2 container
itself is the oracle: if the decoded section 0 yields parseable pointer fixups and a
mesh with plausible vertex/triangle counts, the entropy core is producing real data.
"""
from __future__ import annotations

import argparse
import sys
import traceback
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from io_scene_gr2.gr2.file import read_gr2  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best  # noqa: E402

TARGETS = [
    "res:/dx9/model/ship/amarr/carrier/aca2/effects/aca2_t2_fx_vents_geo_01a.gr2",
    "res:/dx9/model/ship/amarr/carrier/aca2/effects/aca2_t2_fx_commandburst_electro_01a.gr2",
    "res:/dx9/model/ship/amarr/carrier/aca2/effects/spawn_turretmesh_aca2_t1_1a_packed_ts.gr2",
    "res:/dx9/model/ship/amarr/carrier/aca2/effects/aca2_forcefield_darkener_01a.gr2",
    "res:/dx9/model/ship/amarr/carrier/aca2/effects/aca2_t2_fx_fork_geo_01a_lowdetail.gr2",
    "res:/dx9/model/ship/minmatar/carrier/mca2/effects/mca2_t1_fx_sidecircles_01a.gr2",
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", default=None)
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    for res in (args.only or TARGETS):
        print("=" * 78)
        print(res)
        try:
            path = Path(fetch_resfile(res))
        except Exception as exc:  # noqa: BLE001
            print("  fetch fail:", exc)
            continue
        gr2 = read_gr2(path)
        for s in gr2.sections:
            if s.expanded_size:
                print(f"    s{s.index} {s.compression_name:9s} exp={s.expanded_size}")
        try:
            g = MultiSectionGr2(path, allow_partial=False)
        except Exception as exc:  # noqa: BLE001
            print(f"  strict load FAIL: {type(exc).__name__}: {exc}")
            continue
        print("  strict load OK (all sections fully decoded)")
        try:
            verts, faces, uvs, stride, uv_off = _extract_best(g)
            print(f"  MESH ok verts={len(verts)} tris={len(faces)} stride={stride} uv_off={uv_off}")
        except Exception as exc:  # noqa: BLE001
            print(f"  mesh fail: {type(exc).__name__}: {exc}")
            traceback.print_exc(limit=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
