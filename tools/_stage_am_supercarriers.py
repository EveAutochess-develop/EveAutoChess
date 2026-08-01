# -*- coding: utf-8 -*-
"""Stage only Amarr/Minmatar supercarriers after the BitKnit2 fix."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))

from stage_supercarrier_ingame_bundles import (  # noqa: E402
    PACKS,
    REVIEW,
    SUPERCARRIERS,
    export_glb,
)

# Imported after path setup via the staging module's own imports when available.
from bake_pc_textures import bake_bundle_for_res_path  # noqa: E402


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    REVIEW.mkdir(parents=True, exist_ok=True)
    reports = []
    for t in SUPERCARRIERS:
        if t["race"] not in ("A", "M"):
            continue
        mesh = export_glb(t)
        print(f"[tex] {t['key']}")
        try:
            written = bake_bundle_for_res_path(t["key"], t["bake_gr2"])
        except Exception as exc:  # noqa: BLE001
            written = {"error": str(exc)}
            print("  bake fail:", exc)
        mesh["textures"] = written
        mesh["model_long_axis"] = t["model_long_axis"]
        reports.append(mesh)
        print(
            " ",
            mesh.get("status"),
            mesh.get("key"),
            "tris=",
            mesh.get("tris"),
            "uv_off=",
            mesh.get("uv_off"),
        )

    path = REVIEW / "ingame_bundles.json"
    existing = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else []
    by_key = {r["key"]: r for r in existing if "key" in r}
    for r in reports:
        by_key[r["key"]] = r
    path.write_text(json.dumps(list(by_key.values()), ensure_ascii=False, indent=2), encoding="utf-8")

    for key in ("tq_supercarrier_a", "tq_supercarrier_m"):
        glb = PACKS / key / "model.glb"
        print(key, "glb=", glb.is_file(), "size=", glb.stat().st_size if glb.is_file() else 0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
