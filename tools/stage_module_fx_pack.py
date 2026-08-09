# -*- coding: utf-8 -*-
"""Stage TQ fisfx module packs → Godot assets/vfx/module_fx (faithful copy).

Pulls DDS from res:/fisfx/module/*.black refs (painter disc, vampire cyclone,
remote-armor rail/trumpet, damp/TD wavegrid). GR2 meshes stay TQ-side for now;
runtime reconstructs trumpet/helix/disc/cone with these textures (COMBAT §8.2).
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
DESIGN = Path(r"H:\game_dev\eveautochess-design")
sys.path.insert(0, str(ROOT / "tools"))

from eve_pc.dds_decode import save_png  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

REVIEW = DESIGN / "docs" / "_review" / "module_fx"
GODOT = ROOT / "godot_project" / "assets" / "vfx" / "module_fx"
RES_REF = re.compile(rb"res:/[A-Za-z0-9_./\-]+\.(?:dds|png|gr2|black)", re.I)

## kind → TQ black + preferred texture stems (order = priority for roles).
PACKS: list[dict] = [
    {
        "kind": "heal",
        "black": "res:/fisfx/module/remotearmorrepair_st_t1a.black",
        "roles": {
            "tex_beam": ["energyneutralize", "empulse2", "whitesharphifi"],
            "tex_grid": ["waves", "caustic_08"],
            "tex_flare": ["whitesharphifi", "empulse2"],
        },
    },
    {
        "kind": "nos",
        "black": "res:/fisfx/module/energyvampire_st_t1a.black",
        "roles": {
            "tex_beam": ["energyneutralize_2", "beam8b_3", "empulse4"],
            "tex_grid": ["fx_electro_03b", "astroiddirt"],
            "tex_flare": ["empulse4", "beam8b_3"],
        },
    },
    {
        "kind": "neut",
        "black": "res:/fisfx/module/energydestabilization_st_t1a.black",
        "roles": {
            "tex_beam": ["energyneutralize", "lightningmodulator"],
            "tex_grid": ["waves", "lightning5x_v_01", "y_negative_ramp_01_blue"],
            "tex_flare": ["lightningmodulator"],
        },
    },
    {
        "kind": "remote_cap",
        "black": "res:/fisfx/module/energytransfer_st_t1a.black",
        "roles": {
            "tex_beam": ["energytransfer", "lightningmodulator"],
            "tex_grid": ["waves", "lightning5x_v_01", "y_negative_ramp_01"],
            "tex_flare": ["energytransfer"],
        },
    },
    {
        "kind": "sensor_damp",
        "black": "res:/fisfx/module/sensordampener_st_t1a.black",
        "roles": {
            "tex_beam": ["whitesharpproper_cyan_01a", "whitewideproper_01a", "aurora_01c"],
            "tex_grid": ["wavegrid_01a", "waves", "caustic_06"],
            "tex_flare": ["aurora_01"],
        },
    },
    {
        "kind": "tracking_disrupt",
        "black": "res:/fisfx/module/trackingdisruptor_st_t1a.black",
        "roles": {
            "tex_beam": ["whitesharpproper_cyan_01a", "aurora_01c"],
            "tex_grid": ["wavegrid_01a", "lightning_04", "caustic_14"],
            "tex_flare": ["aurora_01"],
        },
    },
    {
        "kind": "guidance_disrupt",
        "black": "res:/fisfx/module/modular_guidancedisruption_tr_t1a.black",
        "roles": {
            "tex_beam": ["whitesharpproper_01a", "whitesharpproper_cyan_01a"],
            "tex_grid": ["fireshape_01a", "caustic_14b", "lightning_02"],
            "tex_flare": ["aurora_01_bw", "aurora_01"],
        },
    },
    {
        "kind": "target_painter",
        "black": "res:/fisfx/module/targetpaint_st_t1a.black",
        "roles": {
            "tex_beam": ["beam8_bigb", "caustics2b", "gradient_02"],
            "tex_grid": ["caustic_10"],
            "tex_target": ["sensor", "gradient_02"],
            "tex_flare": ["sensor", "beam8_bigb"],
        },
    },
]


def _refs(raw: bytes) -> list[str]:
    return sorted({m.group(0).decode("ascii", "ignore") for m in RES_REF.finditer(raw)})


def _stem(res: str) -> str:
    return Path(res).stem.lower()


def _decode_all_dds(refs: list[str], out_dir: Path, godot_dir: Path) -> dict[str, str]:
    """stem → res:// path for every DDS we can decode."""
    out: dict[str, str] = {}
    out_dir.mkdir(parents=True, exist_ok=True)
    godot_dir.mkdir(parents=True, exist_ok=True)
    for res in refs:
        if not res.lower().endswith(".dds"):
            continue
        stem = _stem(res)
        try:
            src = Path(fetch_resfile(res))
            dst = out_dir / f"{stem}.png"
            if not save_png(src, dst, max_dim=1024):
                print(f"  dds fail {res}")
                continue
            gdst = godot_dir / f"{stem}.png"
            shutil.copy2(dst, gdst)
            out[stem] = f"res://assets/vfx/module_fx/{godot_dir.name}/{stem}.png"
            print(f"  OK {stem}")
        except Exception as e:
            print(f"  tex fail {res}: {e}")
    return out


def _pick(stems_map: dict[str, str], prefer: list[str]) -> str:
    for p in prefer:
        key = p.lower()
        if key in stems_map:
            return stems_map[key]
        for s, path in stems_map.items():
            if key in s:
                return path
    return next(iter(stems_map.values()), "")


def main() -> int:
    REVIEW.mkdir(parents=True, exist_ok=True)
    GODOT.mkdir(parents=True, exist_ok=True)
    report: dict = {"packs": {}, "weapon_fx_patch": {}}
    for pack in PACKS:
        kind = pack["kind"]
        black = pack["black"]
        print(f"=== {kind} {black}")
        black_path = Path(fetch_resfile(black))
        rev = REVIEW / kind
        god = GODOT / kind
        rev.mkdir(parents=True, exist_ok=True)
        shutil.copy2(black_path, rev / Path(black).name)
        refs = _refs(black_path.read_bytes())
        (rev / "refs.json").write_text(json.dumps(refs, indent=2), encoding="utf-8")
        stems = _decode_all_dds(refs, rev / "tex", god)
        roles_out: dict[str, str] = {}
        for role, prefer in pack["roles"].items():
            path = _pick(stems, prefer)
            if path:
                roles_out[role] = path
        report["packs"][kind] = {
            "black": black,
            "textures": stems,
            "roles": roles_out,
            "gr2": [r for r in refs if r.lower().endswith(".gr2")],
        }
        report["weapon_fx_patch"][kind] = roles_out
        print(f"  roles {roles_out}")

    (REVIEW / "stage_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (GODOT / "manifest.json").write_text(
        json.dumps(report["weapon_fx_patch"], indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {REVIEW / 'stage_report.json'}")
    print(f"wrote {GODOT / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
