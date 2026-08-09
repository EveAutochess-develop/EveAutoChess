# -*- coding: utf-8 -*-
"""Write model-pack turret_anchors.json from TQ SOF locatorTurrets (full copy).

Formal path (CONTENT_FORMAT §turret_anchors.json): one sidecar per model_key.
Runtime maps sof-native pos via hull_aabb → live mesh AABB (Z flip), same as
engine_boosters. Do not subsample by hi_slots / attack_weapon_slots.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from eve_pc.black_reader import read_black  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from rewrite_engine_boosters_godot import SOF_RES, _aabb_from_hull  # noqa: E402

ROOT = TOOLS.parent
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
SHIPS = ROOT / "godot_project" / "data" / "ships"
OUT_INDEX = TOOLS / "_extracted" / "sof_hull_turrets.json"


def _kind_from_name(name: str) -> str:
    n = (name or "").lower()
    if "launcher" in n:
        return "launcher"
    if "turretm" in n:
        return "turret_missile"
    if "turret" in n:
        return "turret"
    return "other"


def _extract_hull_turrets(sof_root: dict) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for h in sof_root.get("hull") or []:
        if not isinstance(h, dict):
            continue
        name = str(h.get("name") or "").strip()
        if not name:
            continue
        items_out: list[dict] = []
        for loc in h.get("locatorTurrets") or []:
            if not isinstance(loc, dict):
                continue
            xf = loc.get("transform")
            if not isinstance(xf, list) or len(xf) != 4:
                continue
            try:
                tx, ty, tz = float(xf[3][0]), float(xf[3][1]), float(xf[3][2])
            except (TypeError, ValueError, IndexError):
                continue
            loc_name = str(loc.get("name") or "").strip()
            items_out.append(
                {
                    "name": loc_name,
                    "kind": _kind_from_name(loc_name),
                    "pos": [round(tx, 6), round(ty, 6), round(tz, 6)],
                    "transform": xf,
                }
            )
        booster = h.get("booster") if isinstance(h.get("booster"), dict) else {}
        booster_items = booster.get("items") or []
        hull_info = {
            "ellipsoid_center": h.get("shapeEllipsoidCenter"),
            "ellipsoid_radius": h.get("shapeEllipsoidRadius"),
            "bounding_sphere": h.get("boundingSphere"),
        }
        out[name] = {
            "sof_hull": name,
            "geometry": str(h.get("geometryResFilePath") or ""),
            "category": str(h.get("category") or ""),
            "ellipsoid_center": hull_info["ellipsoid_center"],
            "ellipsoid_radius": hull_info["ellipsoid_radius"],
            "bounding_sphere": hull_info["bounding_sphere"],
            "items": items_out,
            "booster_items_for_aabb": booster_items,
        }
    return out


def _hull_aabb_for(info: dict, pack: Path) -> dict:
    """Prefer same-pack engine_boosters hull_aabb so muzzle/nozzle share one frame."""
    eb = pack / "engine_boosters.json"
    if eb.is_file():
        try:
            doc = json.loads(eb.read_text(encoding="utf-8"))
            hb = doc.get("hull_aabb")
            if isinstance(hb, dict) and isinstance(hb.get("position"), list) and isinstance(hb.get("size"), list):
                return hb
        except Exception:
            pass
    raw_items = info.get("booster_items_for_aabb") or []
    if not raw_items and info.get("items"):
        # Pad AABB from turret cluster if no boosters (rare).
        raw_items = [{"transform": it["transform"]} for it in info["items"] if "transform" in it]
    return _aabb_from_hull(info, raw_items)


def main() -> int:
    print(f"fetch {SOF_RES}")
    sof_path = Path(fetch_resfile(SOF_RES))
    root = read_black(sof_path.read_bytes())
    if not isinstance(root, dict):
        print("FAIL: root not dict", type(root))
        return 1
    hulls = _extract_hull_turrets(root)
    with_items = sum(1 for h in hulls.values() if h["items"])
    print(f"hulls={len(hulls)} with_locatorTurrets={with_items}")
    OUT_INDEX.parent.mkdir(parents=True, exist_ok=True)
    # Compact index for audits (drop booster pad).
    index = {
        k: {
            "sof_hull": v["sof_hull"],
            "geometry": v["geometry"],
            "category": v["category"],
            "count": len(v["items"]),
            "kinds": sorted({it["kind"] for it in v["items"]}),
            "names": [it["name"] for it in v["items"]],
        }
        for k, v in hulls.items()
        if v["items"]
    }
    OUT_INDEX.write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {OUT_INDEX}")

    written = 0
    missing = 0
    empty = 0
    for p in sorted(SHIPS.glob("*.json")):
        if p.name.startswith("_"):
            continue
        ship = json.loads(p.read_text(encoding="utf-8"))
        model_key = str(ship.get("model_key") or "").strip()
        sof_hull = str(ship.get("sof_hull") or "").strip()
        if not model_key or not sof_hull:
            continue
        pack = PACKS / model_key
        if not pack.is_dir():
            continue
        info = hulls.get(sof_hull)
        if info is None:
            for k, v in hulls.items():
                if k.lower() == sof_hull.lower():
                    info = v
                    sof_hull = k
                    break
        if info is None:
            missing += 1
            print(f"  MISS sof {ship.get('id')} {model_key} sof={sof_hull}")
            continue
        items = info["items"]
        if not items:
            empty += 1
            print(f"  EMPTY lt {ship.get('id')} {model_key} sof={sof_hull}")
            continue
        hull_aabb = _hull_aabb_for(info, pack)
        payload = {
            "sof_hull": sof_hull,
            "source": SOF_RES,
            "ship_id": ship.get("id"),
            "model_key": model_key,
            "name_en": ship.get("name_en"),
            "space": "sof_hull_native",
            "axis_note": (
                "SOF locatorTurrets full copy (aft typically min Z). "
                "Runtime maps hull_aabb → mesh AABB with Z flipped (Godot aft=max Z)."
            ),
            "hull_aabb": hull_aabb,
            "items": [
                {
                    "name": it["name"],
                    "kind": it["kind"],
                    "pos": it["pos"],
                    "transform": it["transform"],
                }
                for it in items
            ],
        }
        out_p = pack / "turret_anchors.json"
        out_p.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        written += 1
        print(f"  OK {ship.get('id')} {model_key} sof={sof_hull} mounts={len(items)}")

    print(f"done written={written} missing_sof={missing} empty_lt={empty}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
