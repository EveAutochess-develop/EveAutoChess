# -*- coding: utf-8 -*-
"""Set sleeper model_long_axis = mean of four-race same-tonnage shop combat ships.

Racial long_axis comes from ships JSON; if missing, Echoes dogma attr 105 (radius).
Writes only sleeper hulls 221–225 (and any other sleeper-tagged combat hull).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from decode_echoes_type_attributes import dump_type_attributes  # noqa: E402

ROOT = TOOLS.parent
SHIPS = ROOT / "godot_project" / "data" / "ships"
RACES = {"amarr", "caldari", "gallente", "minmatar"}
COMBAT = {"frigate", "destroyer", "cruiser", "battleship"}
RADIUS_ATTR = 105


def racial_axes(ships: list[dict], group: str, type_attrs: dict) -> list[float]:
    vals: list[float] = []
    for d in ships:
        if d.get("ship_group") != group:
            continue
        if d.get("race") not in RACES:
            continue
        if d.get("is_logistic"):
            continue
        if not bool(d.get("shop_eligible", True)):
            continue
        if "sleeper" in (d.get("tags") or []):
            continue
        ax = float(d.get("model_long_axis") or 0)
        if ax <= 0:
            eid = int(d.get("echoes_item_id") or 0)
            raw = type_attrs.get(eid, {}).get(RADIUS_ATTR) if eid else None
            if raw is not None and float(raw) > 0:
                ax = float(raw)
        if ax > 0:
            vals.append(ax)
    return vals


def main() -> None:
    type_attrs = dump_type_attributes()
    ships: list[dict] = []
    paths: dict[int, Path] = {}
    for p in sorted(SHIPS.glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        ships.append(d)
        paths[int(d["id"])] = p

    means: dict[str, float] = {}
    for g in sorted(COMBAT):
        vals = racial_axes(ships, g, type_attrs)
        if not vals:
            print(f"{g}: NO DATA")
            continue
        means[g] = round(sum(vals) / len(vals), 1)
        print(f"{g}: n={len(vals)} mean={means[g]}  min={min(vals):.0f} max={max(vals):.0f}")

    patched = 0
    for d in ships:
        tags = d.get("tags") or []
        if "sleeper" not in tags and d.get("race") != "sleeper":
            continue
        g = str(d.get("ship_group", ""))
        if g not in means:
            print(f"skip sleeper {d.get('id')} group={g}")
            continue
        path = paths[int(d["id"])]
        doc = json.loads(path.read_text(encoding="utf-8"))
        before = doc.get("model_long_axis")
        doc["model_long_axis"] = means[g]
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"  {d['id']} {d['name']}: {before} -> {means[g]}")
        patched += 1
    print(f"patched {patched} sleepers; means={means}")


if __name__ == "__main__":
    main()
