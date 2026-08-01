# -*- coding: utf-8 -*-
"""Write SOF engine_boosters.json for unmanned model packs + stamp sof_hull on JSON.

Combat drones / FAX repair / excavator / fighters were missing pack boosters (or had
has_trail:false-only items). Runtime maps these SOF nozzles into live mesh AABB.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from rewrite_engine_boosters_godot import SOF_RES, _aabb_from_hull, _mat_item

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
UNMANNED = ROOT / "godot_project" / "data" / "unmanned_units"
SHIPS = ROOT / "godot_project" / "data" / "ships"
HULLS = TOOLS / "_extracted" / "sof_hull_boosters.json"

## model_key → sof_hull (from textures_pc.txt GR2 stem / ESI for fighters)
MODEL_SOF: dict[str, str] = {
    "wrj_a_shiseng": "adl1_t1",
    "wrj_a_shentouzhe": "adm1_t1",
    "wrj_j_dahuangfeng": "cdl1_t1",
    "wrj_j_jinxing": "cdm1_t1",
    "wrj_g_dijingling": "gdl1_t1",
    "wrj_g_zhanchui": "gdm1_t1",
    "wrj_m_mwushi": "mdl1_t1",
    "wrj_m_waerjili": "mdm1_t1",
    "heavy_repair_amarr": "adh1_t1",
    "heavy_repair_caldari": "cdh1_t2",
    "heavy_repair_gallente": "gdh1_t1",
    "heavy_repair_minmatar": "mdh1_t1",
    "wrj_ore_excavator": "oredh2_t1",
    "equite": "afi1_t1",
    "locust": "cfi1_t1",
    "satyr": "gfi1_t1",
    "gram": "mfi1_t1",
}

GR2_RE = re.compile(r"gr2=res:/dx9/model/.+/([^/]+)\.gr2", re.I)


def _sof_from_textures_pc(pack: Path) -> str:
    txt = pack / "textures_pc.txt"
    if not txt.is_file():
        return ""
    m = GR2_RE.search(txt.read_text(encoding="utf-8", errors="ignore"))
    return m.group(1).strip() if m else ""


def _resolve_hull(hulls: dict, sof_hull: str) -> tuple[str, dict | None]:
    info = hulls.get(sof_hull)
    if info is not None:
        return sof_hull, info
    for k, v in hulls.items():
        if k.lower() == sof_hull.lower():
            return k, v
    return sof_hull, None


def _write_pack(model_key: str, sof_hull: str, hulls: dict, meta: dict) -> bool:
    pack = PACKS / model_key
    if not pack.is_dir():
        print(f"skip missing pack {model_key}")
        return False
    sof_hull, info = _resolve_hull(hulls, sof_hull)
    if info is None:
        print(f"skip no SOF hull {model_key} → {sof_hull}")
        return False
    raw_items = info.get("items") or []
    if not raw_items:
        print(f"skip empty boosters {model_key} → {sof_hull}")
        return False
    items_out = [_mat_item(it) for it in raw_items if isinstance(it.get("transform"), list)]
    ## Game trails need nozzle pins even when TQ marks has_trail=false (drone glow only).
    if items_out and not any(bool(it.get("has_trail", True)) for it in items_out):
        for it in items_out:
            it["has_trail"] = True
            it["game_trail_forced"] = True
    payload = {
        "sof_hull": sof_hull,
        "source": SOF_RES,
        "ship_id": meta.get("id"),
        "model_key": model_key,
        "name_en": meta.get("name_en"),
        "always_on": info.get("always_on", False),
        "has_trails": True if any(it.get("has_trail") for it in items_out) else info.get("has_trails", True),
        "space": "sof_hull_native",
        "axis_note": "SOF native (aft typically min Z). Runtime maps hull_aabb → mesh AABB with Z flipped (Godot aft=max Z).",
        "hull_aabb": _aabb_from_hull(info, raw_items),
        "items": items_out,
    }
    (pack / "engine_boosters.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"wrote {model_key}/engine_boosters.json sof={sof_hull} nozzles={len(items_out)}")
    return True


def _stamp_sof_hull(path: Path, sof_hull: str) -> None:
    doc = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(doc, dict):
        return
    if str(doc.get("sof_hull") or "") == sof_hull:
        return
    doc["sof_hull"] = sof_hull
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    hulls = json.loads(HULLS.read_text(encoding="utf-8"))
    ## Discover pack→sof from map + textures_pc fallback.
    pack_sof: dict[str, str] = dict(MODEL_SOF)
    for pack in PACKS.iterdir():
        if not pack.is_dir():
            continue
        if pack.name in pack_sof:
            continue
        stem = _sof_from_textures_pc(pack)
        if stem and stem in hulls:
            ## Only auto-add drone/fighter-ish packs (avoid rewriting every manned hull here).
            if stem.startswith(("adl", "adm", "adh", "cdl", "cdm", "cdh", "gdl", "gdm", "gdh", "mdl", "mdm", "mdh", "afi", "cfi", "gfi", "mfi", "ored")):
                pack_sof[pack.name] = stem

    written = 0
    ## Meta from unmanned_units + excavator ship 139.
    meta_by_key: dict[str, dict] = {}
    for folder in (UNMANNED, SHIPS):
        for p in folder.glob("*.json"):
            if p.name.startswith("_"):
                continue
            d = json.loads(p.read_text(encoding="utf-8"))
            if not isinstance(d, dict):
                continue
            mk = str(d.get("model_key") or "").strip()
            if not mk:
                continue
            if mk not in meta_by_key:
                meta_by_key[mk] = d
            sof = pack_sof.get(mk, "")
            if sof and bool(d.get("is_unmanned", False)):
                _stamp_sof_hull(p, sof)
            if sof and mk == "wrj_ore_excavator":
                _stamp_sof_hull(p, sof)

    for model_key, sof_hull in sorted(pack_sof.items()):
        meta = meta_by_key.get(model_key, {"model_key": model_key, "name_en": model_key})
        if _write_pack(model_key, sof_hull, hulls, meta):
            written += 1
    print(f"done packs={written}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
