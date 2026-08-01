# -*- coding: utf-8 -*-
"""Extract SOF hull booster transforms → model pack engine_boosters.json.

Formal path (CONTENT_FORMAT): one sidecar per model_key. Runtime reads only this
file; missing → single AABB stern fallback (no multi-source priority).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from eve_pc.black_reader import extract_hull_boosters, read_black  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

ROOT = TOOLS.parent
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
SHIPS = ROOT / "godot_project" / "data" / "ships"
OUT_INDEX = TOOLS / "_extracted" / "sof_hull_boosters.json"
SOF_RES = "res:/dx9/model/spaceobjectfactory/data.black"


def _stem_from_gr2(res_path: str) -> str:
    # res:/dx9/model/ship/.../af1_t1.gr2 → af1_t1
    m = re.search(r"/([^/]+)\.gr2$", res_path.replace("\\", "/"), re.I)
    return m.group(1).lower() if m else ""


def _load_ship_rows() -> list[dict]:
    rows: list[dict] = []
    for p in sorted(SHIPS.glob("*.json")):
        if p.name.startswith("_"):
            continue
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(d, dict) or "model_key" not in d:
            continue
        rows.append(d)
    return rows


def _geometry_to_hull(hulls: dict[str, dict]) -> dict[str, str]:
    """Map lowercase geometry res path → sof hull name."""
    out: dict[str, str] = {}
    for name, info in hulls.items():
        geo = str(info.get("geometry") or "").lower()
        if geo:
            out[geo] = name
            stem = _stem_from_gr2(geo)
            if stem:
                out[stem] = name
                out[f"{stem}.gr2"] = name
    return out


def main() -> int:
    print(f"fetch {SOF_RES}")
    sof_path = Path(fetch_resfile(SOF_RES))
    raw = sof_path.read_bytes()
    print(f"parse black ({len(raw)} bytes)…")
    root = read_black(raw)
    if not isinstance(root, dict):
        print("FAIL: root not dict", type(root))
        return 1
    print(f"root type={root.get('__type')} keys={list(k for k in root if not str(k).startswith('__'))[:12]}")
    hulls = extract_hull_boosters(root)
    print(f"hulls with records={len(hulls)} with_booster_items={sum(1 for h in hulls.values() if h['items'])}")
    OUT_INDEX.parent.mkdir(parents=True, exist_ok=True)
    # Compact index: only hulls that have booster items (plus empty markers sample)
    OUT_INDEX.write_text(json.dumps(hulls, indent=2), encoding="utf-8")
    print(f"wrote {OUT_INDEX}")

    geo_map = _geometry_to_hull(hulls)
    ships = _load_ship_rows()
    written = 0
    missing = 0
    for ship in ships:
        model_key = str(ship.get("model_key") or "").strip()
        if not model_key:
            continue
        pack = PACKS / model_key
        if not pack.is_dir():
            continue
        sof_hull = str(ship.get("sof_hull") or "").strip()
        info = hulls.get(sof_hull) if sof_hull else None
        if info is None:
            # Try match by common stems from model_key heuristics later; for now
            # look up by explicit sof_hull only + geometry index if pc path known.
            pass
        if info is None and sof_hull:
            # case-insensitive
            for k, v in hulls.items():
                if k.lower() == sof_hull.lower():
                    info = v
                    sof_hull = k
                    break
        if info is None:
            missing += 1
            continue
        payload = {
            "sof_hull": info["sof_hull"],
            "source": SOF_RES,
            "ship_id": ship.get("id"),
            "model_key": model_key,
            "name_en": ship.get("name_en"),
            "always_on": info.get("always_on", False),
            "has_trails": info.get("has_trails", True),
            "items": info["items"],
            "space": "sof_hull_local",
            "note": "transform = EveSOFDataHullBoosterItem.matrix4; apply with same axis map as GR2→GLB import",
        }
        out_p = pack / "engine_boosters.json"
        out_p.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        written += 1
        print(f"  OK {ship.get('id')} {model_key} sof={info['sof_hull']} nozzles={len(info['items'])}")

    print(f"done written={written} ships_without_sof_hull_field={missing} geo_keys={len(geo_map)}")
    # Also dump a small sample of hull names for mapping work
    sample = sorted(hulls.keys())[:40]
    print("sample hull names:", ", ".join(sample))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
