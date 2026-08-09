# -*- coding: utf-8 -*-
"""Stage TQ turret near/far shared_textures → assets/vfx/turret_fx.

Sources (resfile index):
  energy  pulse/beam   → laserpulsefx_01a / laserbeamfx_01a
  hybrid  blast/rail   → hybridblastfx_01a / hybridrailfx_01a
  projectile auto/artil → projectileautofx_01a / projectileartilleryfx_01a
Plus shared laser.dds / blast.dds / noise.dds when present.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
DESIGN = Path(r"H:\game_dev\eveautochess-design")
sys.path.insert(0, str(ROOT / "tools"))

from eve_pc.dds_decode import save_png  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

REVIEW = DESIGN / "docs" / "_review" / "turret_fx"
GODOT = ROOT / "godot_project" / "assets" / "vfx" / "turret_fx"

## kind → near/far role names + TQ DDS + representative fx.black (for review copy)
PACKS = [
    {
        "kind": "laser",
        "near": {
            "role": "pulse",
            "tex": "res:/dx9/model/turret/shared_textures/laserpulsefx_01a.dds",
            "fx_black": "res:/dx9/model/turret/energy/pulse/s/pulse_dual_fx.black",
        },
        "far": {
            "role": "beam",
            "tex": "res:/dx9/model/turret/shared_textures/laserbeamfx_01a.dds",
            "fx_black": "res:/dx9/model/turret/energy/beam/s/beam_dual_fx.black",
        },
        "shared": [
            "res:/dx9/model/turret/shared_textures/laser.dds",
            "res:/texture/global/noise.dds",
        ],
    },
    {
        "kind": "rail",
        "near": {
            "role": "blast",
            "tex": "res:/dx9/model/turret/shared_textures/hybridblastfx_01a.dds",
            "fx_black": "res:/dx9/model/turret/hybrid/blast/s/blast_electron_fx.black",
        },
        "far": {
            "role": "rail",
            "tex": "res:/dx9/model/turret/shared_textures/hybridrailfx_01a.dds",
            "fx_black": "res:/dx9/model/turret/hybrid/rail/s/rail_125mm_fx.black",
        },
        "shared": [
            "res:/dx9/model/turret/shared_textures/blast.dds",
            "res:/dx9/model/turret/shared_textures/hybridblastfx_01b.dds",
            "res:/dx9/model/turret/shared_textures/hybridblastfx_01c.dds",
            "res:/texture/global/noise.dds",
        ],
    },
    {
        "kind": "cannon",
        "near": {
            "role": "auto",
            "tex": "res:/dx9/model/turret/shared_textures/projectileautofx_01a.dds",
            "fx_black": "res:/dx9/model/turret/projectile/auto/s/auto_125mm_fx.black",
        },
        "far": {
            "role": "artil",
            "tex": "res:/dx9/model/turret/shared_textures/projectileartilleryfx_01a.dds",
            "fx_black": "res:/dx9/model/turret/projectile/artil/s/artil_250mm_fx.black",
        },
        "shared": [
            "res:/dx9/model/turret/shared_textures/laser.dds",
            "res:/texture/global/noise.dds",
        ],
    },
]


def _decode(res: str, out_dir: Path, godot_dir: Path) -> str:
    stem = Path(res).stem.lower()
    out_dir.mkdir(parents=True, exist_ok=True)
    godot_dir.mkdir(parents=True, exist_ok=True)
    src = Path(fetch_resfile(res))
    dst = out_dir / f"{stem}.png"
    if not save_png(src, dst, max_dim=1024):
        raise RuntimeError(f"dds decode fail {res}")
    gdst = godot_dir / f"{stem}.png"
    shutil.copy2(dst, gdst)
    return f"res://assets/vfx/turret_fx/{godot_dir.name}/{stem}.png"


def main() -> int:
    REVIEW.mkdir(parents=True, exist_ok=True)
    GODOT.mkdir(parents=True, exist_ok=True)
    report: dict = {"kinds": {}, "weapon_fx_patch": {}}
    for pack in PACKS:
        kind = pack["kind"]
        print(f"=== {kind}")
        rev = REVIEW / kind
        god = GODOT / kind
        rev.mkdir(parents=True, exist_ok=True)
        roles: dict[str, str] = {}
        for band in ("near", "far"):
            info = pack[band]
            role = info["role"]
            try:
                path = _decode(info["tex"], rev / "tex", god)
                roles[f"tex_{band}"] = path
                roles[f"role_{band}"] = role
                print(f"  OK {band}/{role} → {path}")
            except Exception as e:
                print(f"  FAIL {band} {info['tex']}: {e}")
            # keep a black copy for audit
            try:
                bp = Path(fetch_resfile(info["fx_black"]))
                shutil.copy2(bp, rev / Path(info["fx_black"]).name)
            except Exception as e:
                print(f"  black skip {info['fx_black']}: {e}")
        shared_paths: list[str] = []
        for res in pack.get("shared") or []:
            try:
                shared_paths.append(_decode(res, rev / "tex", god))
                print(f"  OK shared {Path(res).stem}")
            except Exception as e:
                print(f"  shared fail {res}: {e}")
        if shared_paths:
            roles["tex_shared"] = shared_paths[0]
        report["kinds"][kind] = {"roles": roles, "shared": shared_paths}
        report["weapon_fx_patch"][kind] = roles

    (REVIEW / "stage_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (GODOT / "manifest.json").write_text(
        json.dumps(report["weapon_fx_patch"], indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {REVIEW / 'stage_report.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
