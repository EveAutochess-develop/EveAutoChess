# -*- coding: utf-8 -*-
"""Probe aca2 / mca2 GR2 candidates: section codecs, partial decode coverage, mesh."""
from __future__ import annotations

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

CANDIDATES = [
    "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t1_lowdetail.gr2",
    "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t2_lowdetail.gr2",
    "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t1.gr2",
    "res:/dx9/model/ship/amarr/carrier/aca2/aca2_t2.gr2",
    "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t1_lowdetail.gr2",
    "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t2_lowdetail.gr2",
    "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t1.gr2",
    "res:/dx9/model/ship/minmatar/carrier/mca2/mca2_t2.gr2",
    # control: known-good hulls
    "res:/dx9/model/ship/caldari/carrier/cca2/cca2_t1_lowdetail.gr2",
    "res:/dx9/model/ship/gallente/carrier/gca2/gca2_t1_lowdetail.gr2",
]


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    for res in CANDIDATES:
        print("=" * 78)
        print(res)
        try:
            path = Path(fetch_resfile(res))
        except Exception as e:  # noqa: BLE001
            print("  fetch fail:", e)
            continue
        print(f"  file={path.stat().st_size}")
        try:
            gr2 = read_gr2(path)
            print(f"  ptr={gr2.header.pointer_size} sections={len(gr2.sections)}")
            for s in gr2.sections:
                print(
                    f"    s{s.index} {s.compression_name:9s} "
                    f"comp={len(gr2.section_bytes(s)):>9d} exp={s.expanded_size:>9d}"
                )
        except Exception as e:  # noqa: BLE001
            print("  header fail:", e)
            continue
        for partial in (False, True):
            try:
                g = MultiSectionGr2(path, allow_partial=partial)
                cov = {k: v for k, v in g._valid_len.items()}
                print(f"  [partial={partial}] load ok valid_len={cov}")
                verts, faces, uvs, stride, uv_off = _extract_best(g)
                print(
                    f"  [partial={partial}] MESH ok verts={len(verts)} tris={len(faces)} "
                    f"stride={stride} uv_off={uv_off}"
                )
                break
            except Exception as e:  # noqa: BLE001
                print(f"  [partial={partial}] fail: {type(e).__name__}: {e}")
                if partial:
                    traceback.print_exc(limit=3)


if __name__ == "__main__":
    main()
