# -*- coding: utf-8 -*-
"""Patch ships/*.json with Echoes dogma radius (attr 105) as model_long_axis."""
from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from decode_echoes_type_attributes import dump_type_attributes  # noqa: E402

DEV_ROOT = TOOLS.parent
SHIPS_DIR = DEV_ROOT / "godot_project" / "data" / "ships"
OUT_MAP = DEV_ROOT / "godot_project" / "data" / "_extracted" / "echoes_ship_model_long_axis.json"
RADIUS_ATTR_ID = 105


def main() -> None:
    type_attrs = dump_type_attributes()
    summary: dict[str, object] = {
        "source": "echoes type_attributes.sd attr 105 (radius / 长轴)",
        "attr_id": RADIUS_ATTR_ID,
        "ships": {},
        "roster_mean": 0.0,
        "patched": 0,
        "missing": [],
    }
    vals: list[float] = []

    for path in sorted(SHIPS_DIR.glob("*.json"), key=lambda p: int(p.stem)):
        doc = json.loads(path.read_text(encoding="utf-8"))
        sid = int(doc.get("id", path.stem))
        eid = int(doc.get("echoes_item_id") or 0)
        axis = None
        if eid > 0:
            raw = type_attrs.get(eid, {}).get(RADIUS_ATTR_ID)
            if raw is not None and float(raw) > 0:
                axis = float(raw)
        if axis is not None:
            doc["model_long_axis"] = round(axis, 3)
            vals.append(axis)
            summary["ships"][str(sid)] = {
                "name": doc.get("name", ""),
                "echoes_item_id": eid,
                "model_long_axis": doc["model_long_axis"],
            }
            summary["patched"] = int(summary["patched"]) + 1
        else:
            doc.pop("model_long_axis", None)
            summary["missing"].append({"id": sid, "name": doc.get("name", ""), "echoes_item_id": eid})
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if vals:
        summary["roster_mean"] = round(sum(vals) / len(vals), 3)
    OUT_MAP.parent.mkdir(parents=True, exist_ok=True)
    OUT_MAP.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"patched {summary['patched']} ships, mean long_axis={summary['roster_mean']}")
    print(f"map -> {OUT_MAP}")
    if summary["missing"]:
        print(f"missing {len(summary['missing'])} (no echoes_item_id / attr 105)")


if __name__ == "__main__":
    main()
