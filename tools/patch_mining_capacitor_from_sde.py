# -*- coding: utf-8 -*-
"""Patch mining hull capacitor from TQ SDE dgmTypeAttributes."""
from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project")
SDE = Path(r"H:\game_dev\eveautochess-design\scripts\.sde_cache")
SHIPS = ROOT / "data" / "ships"

SHIP_TYPE_IDS = {
	135: 17478,  # Retriever
	136: 42244,  # Porpoise
	137: 28606,  # Orca
	138: 28352,  # Rorqual
}


def _clean(s: str) -> str:
	return s.lstrip("\ufeff").strip().strip('"')


def load_attr_names() -> dict[int, str]:
	path = SDE / "dgmAttributeTypes.csv"
	out: dict[int, str] = {}
	with path.open(encoding="utf-8", newline="") as f:
		reader = csv.reader(f)
		next(reader)
		for row in reader:
			if not row or len(row) < 2 or not row[0]:
				continue
			try:
				aid = int(_clean(row[0]))
			except ValueError:
				continue
			out[aid] = row[1]
	return out


def load_type_attrs(type_ids: set[int], attrs: dict[int, str]) -> dict[int, dict[str, float]]:
	want = {"capacitorCapacity", "rechargeRate"}
	want_ids = {aid for aid, name in attrs.items() if name in want}
	path = SDE / "dgmTypeAttributes.csv"
	vals = {tid: {} for tid in type_ids}
	with path.open(encoding="utf-8", newline="") as f:
		reader = csv.reader(f)
		next(reader)
		for row in reader:
			if len(row) < 3:
				continue
			try:
				tid = int(_clean(row[0]))
				aid = int(_clean(row[1]))
			except ValueError:
				continue
			if tid not in vals or aid not in want_ids:
				continue
			raw = row[3] if len(row) > 3 and row[3] not in ("", None) else (row[2] if len(row) > 2 else "0")
			if raw == "":
				raw = "0"
			vals[tid][attrs[aid]] = float(raw)
	return vals


def main() -> None:
	attrs = load_attr_names()
	vals = load_type_attrs(set(SHIP_TYPE_IDS.values()), attrs)
	for sid, tid in SHIP_TYPE_IDS.items():
		st = vals.get(tid, {})
		path = SHIPS / f"{sid}.json"
		data = json.loads(path.read_text(encoding="utf-8"))
		cap = float(st.get("capacitorCapacity", 0.0))
		ms = float(st.get("rechargeRate", 0.0))
		data["capacitor_capacity"] = cap
		if ms > 0.0:
			data["capacitor_recharge_s"] = round(ms / 1000.0, 3)
		path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
		print(f"{sid} type={tid} cap={cap} recharge_s={data.get('capacitor_recharge_s')}")


if __name__ == "__main__":
	main()
