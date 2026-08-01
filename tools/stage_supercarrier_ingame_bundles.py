# -*- coding: utf-8 -*-
"""Build §0 TQ supercarrier bundles for opening CG parade (阅兵通场).

Uses MultiSectionGr2 UV path (same as freighter / titan reexport).
BitKnit2 state-7 now handles >=16-bit extra-distance records (raw low u16),
so the Amarr/Minmatar hulls extract the same way as Caldari/Gallente.

Supercarrier hull numbering is NOT uniform across races — only Caldari uses *ca2.
Getting this wrong staged three carriers as supercarriers (see below), which also
duplicated the carrier already in the fleet:

  Amarr    aca1 = Aeon (永恒级/万古)      · aca2 = Archon (执政官级) — carrier
  Caldari  cca2 = Wyvern (飞龙级)         · cca1 = Chimera (奇美拉级) — carrier
  Gallente gca1 = Nyx (尼克斯级/夜神)     · gca2 = Thanatos (绝念级) — carrier
  Minmatar mca1 = Hel (地狱级/冥府)       · mca2 = Nidhoggur (尼铎格尔级) — carrier

Cross-check before changing a hull: SOF `ellipsoid_radius` in
`tools/_extracted/sof_hull_boosters.json` (supercarriers are ~2.5× the carrier), and
the carrier ship defs in `godot_project/data/ships/12{1..4}.json`, whose `sof_hull`
already claims aca2 / cca1 / gca2 / mca2.

Keys: tq_supercarrier_a / _c / _g / _m
中文：CCP 端游常用译名（Echoes 可玩表未必收录超航）。
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from bake_pc_textures import bake_bundle_for_res_path  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best, write_obj  # noqa: E402
from rewrite_engine_boosters_godot import SOF_RES, _aabb_from_hull, _mat_item  # noqa: E402
from sof_orientation import aft_report, hull_aft_axis  # noqa: E402
from stage_mining_threeviews import auto_orient  # noqa: E402

HULL_BOOSTERS = ROOT / "tools" / "_extracted" / "sof_hull_boosters.json"

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
REVIEW = Path(
    r"H:\game_dev\cg-director-studio\projects\eveautochess-opening\_review\supercarrier_cg"
)

SUPERCARRIERS = [
    {
        "key": "tq_supercarrier_a",
        "race": "A",
        "zh": "永恒级",
        "en": "Aeon",
        "hull": "aca1",
        "tq_type_id": 23919,
        ## CgOpeningDirector.RACES[].sc_id — supercarriers are injected at runtime and
        ## have no data/ships/*.json, so the usual booster tools skip them.
        "sc_id": 971,
        ## CG film wants full GR2; lowdetail is fallback only.
        "gr2": [
            "res:/dx9/model/ship/amarr/carrier/aca1/aca1_t1.gr2",
            "res:/dx9/model/ship/amarr/carrier/aca1/aca1_t1_lowdetail.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/amarr/carrier/aca1/aca1_t1.gr2",
        ## Matches CgOpeningDirector.CG_SC_LONG_AXIS; 1400 here was sized off the
        ## carrier hulls this script used to stage by mistake.
        "model_long_axis": 3200.0,
    },
    {
        "key": "tq_supercarrier_c",
        "race": "C",
        "zh": "飞龙级",
        "en": "Wyvern",
        "hull": "cca2",
        "tq_type_id": 23917,
        "sc_id": 972,
        "gr2": [
            "res:/dx9/model/ship/caldari/carrier/cca2/cca2_t1.gr2",
            "res:/dx9/model/ship/caldari/carrier/cca2/cca2_t1_lowdetail.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/caldari/carrier/cca2/cca2_t1.gr2",
        ## Matches CgOpeningDirector.CG_SC_LONG_AXIS; 1400 here was sized off the
        ## carrier hulls this script used to stage by mistake.
        "model_long_axis": 3200.0,
    },
    {
        "key": "tq_supercarrier_g",
        "race": "G",
        "zh": "尼克斯级",
        "en": "Nyx",
        "hull": "gca1",
        "tq_type_id": 23913,
        "sc_id": 973,
        "gr2": [
            "res:/dx9/model/ship/gallente/carrier/gca1/gca1_t1.gr2",
            "res:/dx9/model/ship/gallente/carrier/gca1/gca1_t1_lowdetail.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/gallente/carrier/gca1/gca1_t1.gr2",
        ## Matches CgOpeningDirector.CG_SC_LONG_AXIS; 1400 here was sized off the
        ## carrier hulls this script used to stage by mistake.
        "model_long_axis": 3200.0,
    },
    {
        "key": "tq_supercarrier_m",
        "race": "M",
        "zh": "地狱级",
        "en": "Hel",
        "hull": "mca1",
        "tq_type_id": 22852,
        "sc_id": 974,
        "gr2": [
            "res:/dx9/model/ship/minmatar/carrier/mca1/mca1_t1.gr2",
            "res:/dx9/model/ship/minmatar/carrier/mca1/mca1_t1_lowdetail.gr2",
        ],
        "bake_gr2": "res:/dx9/model/ship/minmatar/carrier/mca1/mca1_t1.gr2",
        ## Matches CgOpeningDirector.CG_SC_LONG_AXIS; 1400 here was sized off the
        ## carrier hulls this script used to stage by mistake.
        "model_long_axis": 3200.0,
    },
]


def write_engine_boosters(t: dict) -> int:
    """Emit the pack's nozzle sidecar; without it ShipUnit falls back to one stern point.

    `apply_sof_engine_boosters.py` only walks `data/ships/*.json`, and supercarriers are
    injected by CgOpeningDirector at runtime, so they are invisible to it. Writing this
    here keeps the nozzles tied to whichever hull the bundle was actually staged from.
    """
    hulls = json.loads(HULL_BOOSTERS.read_text(encoding="utf-8"))
    hull_key = f"{t['hull']}_t1"
    info = hulls.get(hull_key) or {}
    raw_items = info.get("items") or []
    if not raw_items:
        print(f"    boosters: NONE for {hull_key} — trails will collapse to a single stern point")
        return 0
    items_out = [it for it in raw_items if isinstance(it.get("transform"), list)]
    payload = {
        "sof_hull": hull_key,
        "source": SOF_RES,
        "ship_id": t.get("sc_id"),
        "model_key": t["key"],
        "name_en": t["en"],
        "always_on": info.get("always_on", False),
        "has_trails": info.get("has_trails", True),
        "space": "sof_hull_native",
        "axis_note": (
            "SOF native (aft typically min Z). Runtime maps hull_aabb → mesh AABB with "
            "Z flipped (Godot aft=max Z)."
        ),
        "hull_aabb": _aabb_from_hull(info, items_out),
        "items": [_mat_item(it) for it in items_out],
    }
    out = PACKS / t["key"] / "engine_boosters.json"
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    n_trail = sum(1 for it in payload["items"] if it["has_trail"])
    print(f"    boosters: {len(payload['items'])} nozzles ({n_trail} with trail) -> {out.name}")
    return len(payload["items"])


def export_glb(t: dict) -> dict:
    out = PACKS / t["key"]
    out.mkdir(parents=True, exist_ok=True)
    last = ""
    for res in t["gr2"]:
        try:
            print(f"[mesh] {t['key']} {t['en']} <- {res}")
            g = MultiSectionGr2(Path(fetch_resfile(res)))
            verts, faces, uvs, stride, uv_off = _extract_best(g)
            ## Span heuristic flips hulls whose broadest point is forward;
            ## the SOF nozzle cloud pins the stern instead.
            hull_key = f"{t['hull']}_t1"
            centroid = verts[np.unique(faces.reshape(-1))].mean(axis=0)
            print(f"    {aft_report(hull_key, centroid)}")
            verts = auto_orient(verts, faces, hull_aft_axis(hull_key, centroid))
            if uv_off < 0:
                uvs = np.zeros((len(verts), 2), dtype=np.float32)
            obj = out / "_tmp.obj"
            write_obj(verts, faces, uvs, obj)
            glb = out / "model.glb"
            assimp_convert(obj, glb, "glb2")
            obj.unlink(missing_ok=True)
            dst = REVIEW / t["race"]
            dst.mkdir(parents=True, exist_ok=True)
            shutil.copy2(glb, dst / "model.glb")
            meta = {
                "key": t["key"],
                "en": t["en"],
                "zh": t["zh"],
                "race": t["race"],
                "hull": t["hull"],
                "tq_type_id": t["tq_type_id"],
                "status": "ok",
                "res": res,
                "stride": stride,
                "uv_off": uv_off,
                "verts": int(len(verts)),
                "tris": int(len(faces)),
            }
            (out / "bundle_meta.json").write_text(
                json.dumps({**meta, "model_long_axis": t["model_long_axis"]}, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            meta["nozzles"] = write_engine_boosters(t)
            return meta
        except Exception as e:
            last = str(e)
            print(f"  fail: {e}")
    return {"key": t["key"], "en": t["en"], "status": "fail", "error": last}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keys", nargs="*", help="restage a subset (default: all)")
    parser.add_argument(
        "--skip-textures",
        action="store_true",
        help="mesh only — orientation fixes do not invalidate baked maps",
    )
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass
    REVIEW.mkdir(parents=True, exist_ok=True)
    targets = [t for t in SUPERCARRIERS if not args.keys or t["key"] in args.keys]
    reports = []
    for t in targets:
        mesh = export_glb(t)
        if args.skip_textures:
            mesh["textures"] = "skipped"
        else:
            print(f"[tex] {t['key']}")
            try:
                written = bake_bundle_for_res_path(t["key"], t["bake_gr2"])
            except Exception as e:
                written = {"error": str(e)}
                print(f"  bake fail: {e}")
            mesh["textures"] = written
        mesh["model_long_axis"] = t["model_long_axis"]
        reports.append(mesh)
    if not args.keys:
        (REVIEW / "ingame_bundles.json").write_text(
            json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    ok = sum(1 for r in reports if r.get("status") == "ok")
    print(f"done ok={ok}/{len(reports)} -> {PACKS}")
    for r in reports:
        print(" ", r.get("status"), r.get("key"), r.get("en"), r.get("tris") or r.get("error"))


if __name__ == "__main__":
    main()
