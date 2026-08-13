# -*- coding: utf-8 -*-
"""Stage TQ defense stance / ship-shield FX → review + Godot preview assets.

Kinds (COMBAT §8.3 · preview only):
  shield_sphere  — warfarelinksphere_shield
  ship_shield    — shieldboosting_skinned (+ hardening refs)
  armor_sphere   — warfarelinksphere_armor

GR2 meshes stay TQ-side; preview rebuilds SphereMesh with staged PNG.
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

REVIEW = DESIGN / "docs" / "_review" / "defense_stance_fx_preview"
GODOT = ROOT / "godot_project" / "assets" / "vfx" / "defense_stance"
RES_REF = re.compile(rb"res:/[A-Za-z0-9_./\-]+\.(?:dds|png|gr2|black)", re.I)

PACKS: list[dict] = [
    {
        "kind": "shield_sphere",
        "label": "护盾立场",
        "black": "res:/fisfx/module/warfarelinksphere_shield_rt_t1a.black",
        "tint": [0.35, 0.72, 1.0, 0.72],
        "roles": {
            "tex_shell": ["3dfx_shield", "whiteglobe", "whiteglobetight", "shield", "sphere", "bubble"],
            "tex_flow": ["caustic", "pulse_half", "aurora", "lightning", "wave", "noise"],
        },
    },
    {
        "kind": "ship_shield",
        "label": "舰船护盾",
        "black": "res:/dx9/model/effect/shieldboosting_skinned.black",
        "extra_blacks": [
            "res:/dx9/model/effect/shieldhardening_skinned.black",
        ],
        "tint": [0.45, 0.85, 1.0, 0.55],
        "roles": {
            "tex_shell": ["waves", "caustics2", "caustics", "shield", "boost"],
            "tex_flow": ["caustics2", "caustics", "waves"],
        },
    },
    {
        "kind": "armor_sphere",
        "label": "装甲连接立场",
        "black": "res:/fisfx/module/warfarelinksphere_armor_rt_t1a.black",
        "tint": [0.95, 0.72, 0.28, 0.72],
        "roles": {
            "tex_shell": ["3dfx_voronoi", "whiteglobetight", "radial_deformed", "armor", "sphere", "bubble"],
            "tex_flow": ["caustic_18", "caustic_07", "caustic", "vertical_graviton", "aurora"],
        },
    },
]

## Shield impact splash (TQ fisfx/impact + shieldimpactgradient) — no single black.
HIT_PACK: dict = {
    "kind": "ship_shield_hit",
    "label": "护盾受击落点",
    "tint": [0.55, 0.9, 1.0, 0.95],
    "dds": [
        "res:/texture/fx/gradients/floatingpoint/shieldimpactgradient_01a.dds",
        "res:/fisfx/impact/gradientmap_01a.dds",
        "res:/fisfx/impact/insidemap_01a.dds",
        "res:/fisfx/impact/insidemap_03a.dds",
        "res:/fisfx/impact/3dfx_layerallmap_01a.dds",
        "res:/fisfx/impact/temporalfadeout_01a.dds",
        "res:/fisfx/impact/3dfx_cutoffsetmap_01a.dds",
    ],
    "roles": {
        ## Prefer real impact maps; FP shieldimpactgradient often stages as empty PNG.
        "tex_impact": ["insidemap_03", "insidemap", "3dfx_layerallmap", "gradientmap", "shieldimpactgradient"],
        "tex_layer": ["3dfx_layerallmap", "insidemap_01", "temporalfadeout"],
    },
}


def _refs(raw: bytes) -> list[str]:
    return sorted({m.group(0).decode("ascii", "ignore") for m in RES_REF.finditer(raw)})


def _stem(res: str) -> str:
    return Path(res).stem.lower()


def _decode_all_dds(refs: list[str], out_dir: Path, godot_dir: Path, kind: str) -> dict[str, str]:
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
            out[stem] = f"res://assets/vfx/defense_stance/{kind}/{stem}.png"
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
    report: dict = {"packs": {}, "preview_roles": {}}
    for pack in PACKS:
        kind = pack["kind"]
        black = pack["black"]
        print(f"=== {kind} {black}")
        black_path = Path(fetch_resfile(black))
        rev = REVIEW / kind
        god = GODOT / kind
        if rev.exists():
            shutil.rmtree(rev)
        if god.exists():
            shutil.rmtree(god)
        rev.mkdir(parents=True, exist_ok=True)
        god.mkdir(parents=True, exist_ok=True)
        shutil.copy2(black_path, rev / Path(black).name)
        refs = _refs(black_path.read_bytes())
        for extra in pack.get("extra_blacks", []):
            print(f"  +extra {extra}")
            try:
                ep = Path(fetch_resfile(extra))
                shutil.copy2(ep, rev / Path(extra).name)
                refs = sorted(set(refs) | set(_refs(ep.read_bytes())))
            except Exception as e:
                print(f"  extra fail {extra}: {e}")
        (rev / "refs.json").write_text(json.dumps(refs, indent=2), encoding="utf-8")
        stems = _decode_all_dds(refs, rev / "tex", god, kind)
        roles_out: dict[str, str] = {}
        for role, prefer in pack["roles"].items():
            path = _pick(stems, prefer)
            if path:
                roles_out[role] = path
        # Ensure shell/flow both set when only one texture exists.
        if "tex_shell" not in roles_out and stems:
            roles_out["tex_shell"] = next(iter(stems.values()))
        if "tex_flow" not in roles_out:
            roles_out["tex_flow"] = roles_out.get("tex_shell", "")
        entry = {
            "label": pack["label"],
            "black": black,
            "extra_blacks": pack.get("extra_blacks", []),
            "tint": pack["tint"],
            "textures": stems,
            "roles": roles_out,
            "gr2": [r for r in refs if r.lower().endswith(".gr2")],
        }
        report["packs"][kind] = entry
        report["preview_roles"][kind] = {
            "label": pack["label"],
            "tint": pack["tint"],
            **roles_out,
        }
        print(f"  roles {roles_out}")

    ## Explicit DDS pack for shield hit splash (COMBAT §8.3).
    hit = HIT_PACK
    kind = hit["kind"]
    print(f"=== {kind} (explicit DDS)")
    rev = REVIEW / kind
    god = GODOT / kind
    if rev.exists():
        shutil.rmtree(rev)
    if god.exists():
        shutil.rmtree(god)
    rev.mkdir(parents=True, exist_ok=True)
    god.mkdir(parents=True, exist_ok=True)
    (rev / "refs.json").write_text(json.dumps(hit["dds"], indent=2), encoding="utf-8")
    stems = _decode_all_dds(hit["dds"], rev / "tex", god, kind)
    roles_out = {}
    for role, prefer in hit["roles"].items():
        path = _pick(stems, prefer)
        if path:
            roles_out[role] = path
    if "tex_impact" not in roles_out and stems:
        roles_out["tex_impact"] = next(iter(stems.values()))
    if "tex_layer" not in roles_out:
        roles_out["tex_layer"] = roles_out.get("tex_impact", "")
    report["packs"][kind] = {
        "label": hit["label"],
        "dds": hit["dds"],
        "tint": hit["tint"],
        "textures": stems,
        "roles": roles_out,
    }
    report["preview_roles"][kind] = {
        "label": hit["label"],
        "tint": hit["tint"],
        **roles_out,
    }
    print(f"  roles {roles_out}")

    (REVIEW / "stage_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (GODOT / "manifest.json").write_text(
        json.dumps(report["preview_roles"], indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {REVIEW / 'stage_report.json'}")
    print(f"wrote {GODOT / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
