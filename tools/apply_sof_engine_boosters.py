# -*- coding: utf-8 -*-
"""Map ships type_id → ESI sof_hull_name; write sof_hull field + engine_boosters.json."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

from rewrite_engine_boosters_godot import main as rewrite_boosters

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
SHIPS = ROOT / "godot_project" / "data" / "ships"
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
HULLS = TOOLS / "_extracted" / "sof_hull_boosters.json"
SOF_RES = "res:/dx9/model/spaceobjectfactory/data.black"
CACHE = TOOLS / "_extracted" / "esi_sof_hull_by_type.json"


def _esi_get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "eveautochess-sof-extract/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    hulls = json.loads(HULLS.read_text(encoding="utf-8"))
    cache: dict = {}
    if CACHE.exists():
        cache = json.loads(CACHE.read_text(encoding="utf-8"))

    ships = []
    for p in sorted(SHIPS.glob("*.json")):
        if p.name.startswith("_"):
            continue
        d = json.loads(p.read_text(encoding="utf-8"))
        if isinstance(d, dict) and d.get("model_key"):
            ships.append((p, d))

    written_field = 0
    written_pack = 0
    missing_hull = []
    for path, ship in ships:
        tid = int(ship.get("type_id") or 0)
        model_key = str(ship.get("model_key") or "").strip()
        sof_hull = str(ship.get("sof_hull") or "").strip()
        if not sof_hull and tid > 0:
            key = str(tid)
            if key not in cache:
                try:
                    t = _esi_get(f"https://esi.evetech.net/latest/universe/types/{tid}/?datasource=tranquility")
                    gid = int(t.get("graphic_id") or 0)
                    hull_name = ""
                    if gid:
                        g = _esi_get(
                            f"https://esi.evetech.net/latest/universe/graphics/{gid}/?datasource=tranquility"
                        )
                        hull_name = str(g.get("sof_hull_name") or "").strip()
                    cache[key] = {"graphic_id": gid, "sof_hull_name": hull_name, "name": t.get("name")}
                    time.sleep(0.05)
                except Exception as e:
                    cache[key] = {"error": str(e)}
                    print(f"ESI fail type={tid}: {e}")
            sof_hull = str((cache.get(str(tid)) or {}).get("sof_hull_name") or "").strip()
            if sof_hull:
                ship["sof_hull"] = sof_hull
                path.write_text(json.dumps(ship, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
                written_field += 1

        if not sof_hull:
            missing_hull.append((ship.get("id"), model_key, tid))
            continue
        info = hulls.get(sof_hull)
        if info is None:
            # case fold
            for k, v in hulls.items():
                if k.lower() == sof_hull.lower():
                    info = v
                    sof_hull = k
                    break
        if info is None:
            missing_hull.append((ship.get("id"), model_key, f"no_sof_record:{sof_hull}"))
            continue
        pack = PACKS / model_key
        if not pack.is_dir():
            missing_hull.append((ship.get("id"), model_key, "no_pack"))
            continue
        payload = {
            "sof_hull": sof_hull,
            "source": SOF_RES,
            "ship_id": ship.get("id"),
            "model_key": model_key,
            "name_en": ship.get("name_en"),
            "always_on": info.get("always_on", False),
            "has_trails": info.get("has_trails", True),
            "items": info.get("items") or [],
            "space": "sof_hull_mesh_local",
            "note": "transform from EveSOFDataHullBoosterItem; mesh-local like GR2; runtime × model root.transform after normalize",
        }
        (pack / "engine_boosters.json").write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        written_pack += 1
        n = len(payload["items"])
        print(f"OK id={ship.get('id')} {model_key} sof={sof_hull} nozzles={n}")

    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache, indent=2), encoding="utf-8")
    print(f"sof_hull fields written={written_field} packs={written_pack} missing={len(missing_hull)}")
    for row in missing_hull[:20]:
        print("  MISS", row)
    # Normalize every generated sidecar to the runtime contract:
    # SOF-native pos + hull_aabb for mapping into the live GLB AABB.
    rewrite_boosters()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
