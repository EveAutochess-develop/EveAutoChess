# -*- coding: utf-8 -*-
"""Rewrite engine_boosters.json: keep SOF-native pos + hull AABB for runtime remapping.

Do NOT bake a guessed Godot Z-flip into positions — Echoes GLB space ≠ TQ SOF space.
Runtime maps sof_pos from sof_hull_aabb → live mesh AABB (aft axes flipped).
"""
from __future__ import annotations

import json
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
SHIPS = ROOT / "godot_project" / "data" / "ships"
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
HULLS = TOOLS / "_extracted" / "sof_hull_boosters.json"
SOF_RES = "res:/dx9/model/spaceobjectfactory/data.black"


def _aabb_from_hull(info: dict, items: list) -> dict:
    """Prefer SOF ellipsoid/sphere; else expand from booster translations."""
    ec = info.get("ellipsoid_center")
    er = info.get("ellipsoid_radius")
    if (
        isinstance(ec, list)
        and len(ec) >= 3
        and isinstance(er, list)
        and len(er) >= 3
        and max(abs(float(v)) for v in er[:3]) > 1e-3
    ):
        cx, cy, cz = float(ec[0]), float(ec[1]), float(ec[2])
        rx, ry, rz = abs(float(er[0])), abs(float(er[1])), abs(float(er[2]))
        return {
            "position": [cx - rx, cy - ry, cz - rz],
            "size": [rx * 2.0, ry * 2.0, rz * 2.0],
            "source": "shapeEllipsoid",
        }
    bs = info.get("bounding_sphere")
    if isinstance(bs, list) and len(bs) >= 4 and abs(float(bs[3])) > 1e-3:
        cx, cy, cz, r = float(bs[0]), float(bs[1]), float(bs[2]), abs(float(bs[3]))
        return {
            "position": [cx - r, cy - r, cz - r],
            "size": [r * 2.0, r * 2.0, r * 2.0],
            "source": "boundingSphere",
        }
    # Fallback: pad booster cluster to a box (stern-only → still better than raw).
    xs = [float(it["transform"][3][0]) for it in items]
    ys = [float(it["transform"][3][1]) for it in items]
    zs = [float(it["transform"][3][2]) for it in items]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    minz, maxz = min(zs), max(zs)
    # Inflate toward bow: SOF aft is typically min Z; extend +Z span ×3 toward bow.
    z_span = max(maxz - minz, 1.0)
    minz_ext = minz - z_span * 2.5  # toward bow if aft=minZ... wait aft is more negative = minz
    # aft = minz, bow = larger z. Extend maxz toward bow.
    maxz_ext = maxz + z_span * 2.5
    pad = max((maxx - minx), (maxy - miny), 1.0) * 0.35
    return {
        "position": [minx - pad, miny - pad, minz],
        "size": [(maxx - minx) + pad * 2, (maxy - miny) + pad * 2, maxz_ext - minz],
        "source": "booster_cluster_padded",
    }


def _mat_item(it: dict) -> dict:
    xf = it["transform"]
    tx, ty, tz = float(xf[3][0]), float(xf[3][1]), float(xf[3][2])
    sx = abs(float(xf[0][0]))
    sy = abs(float(xf[1][1]))
    return {
        "has_trail": bool(it.get("has_trail", True)),
        "light_scale": float(it.get("light_scale") or 1.0),
        "pos": [round(tx, 6), round(ty, 6), round(tz, 6)],
        "radius": round(max(0.02, 0.5 * (sx + sy)), 6),
        "transform": xf,
    }


def main() -> int:
    hulls = json.loads(HULLS.read_text(encoding="utf-8"))
    n = 0
    for p in sorted(SHIPS.glob("*.json")):
        if p.name.startswith("_"):
            continue
        ship = json.loads(p.read_text(encoding="utf-8"))
        model_key = str(ship.get("model_key") or "").strip()
        sof_hull = str(ship.get("sof_hull") or "").strip()
        if not model_key or not sof_hull:
            continue
        info = hulls.get(sof_hull)
        if info is None:
            for k, v in hulls.items():
                if k.lower() == sof_hull.lower():
                    info = v
                    sof_hull = k
                    break
        if info is None:
            continue
        pack = PACKS / model_key
        if not pack.is_dir():
            continue
        raw_items = info.get("items") or []
        if not raw_items:
            continue
        items_out = [_mat_item(it) for it in raw_items if isinstance(it.get("transform"), list)]
        hull_aabb = _aabb_from_hull(info, raw_items)
        payload = {
            "sof_hull": sof_hull,
            "source": SOF_RES,
            "ship_id": ship.get("id"),
            "model_key": model_key,
            "name_en": ship.get("name_en"),
            "always_on": info.get("always_on", False),
            "has_trails": info.get("has_trails", True),
            "space": "sof_hull_native",
            "axis_note": "SOF native (aft typically min Z). Runtime maps hull_aabb → mesh AABB with Z flipped (Godot aft=max Z).",
            "hull_aabb": hull_aabb,
            "items": items_out,
        }
        (pack / "engine_boosters.json").write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        n += 1
    print(f"rewrote {n} packs with sof-native pos + hull_aabb")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
