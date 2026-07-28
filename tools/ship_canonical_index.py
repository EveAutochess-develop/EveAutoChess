# -*- coding: utf-8 -*-
"""Build canonical ship/unmanned asset index keyed by English name."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
GODOT = ROOT / "godot_project"
SHIPS = GODOT / "data" / "ships"
UNMANNED = GODOT / "data" / "unmanned_units"
PACKS = GODOT / "assets" / "models" / "ships"
PORTRAITS = GODOT / "assets" / "ui" / "portraits"
OUT = GODOT / "data" / "_extracted" / "ship_canonical_index.json"


def iter_roster_jsons() -> list[Path]:
    files = list(SHIPS.glob("*.json")) + list(UNMANNED.glob("*.json"))
    rows: list[tuple[int, Path]] = []
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        sid = int(data.get("id") or 0)
        if sid <= 0:
            continue
        rows.append((sid, path))
    return [path for _, path in sorted(rows)]


def build_index() -> dict:
    from eve_pc.pc_asset_map import canonical_pc_res_path

    by_id: dict[str, dict] = {}
    by_name_en: dict[str, dict] = {}
    collisions: dict[str, list[int]] = {}
    for path in iter_roster_jsons():
        data = json.loads(path.read_text(encoding="utf-8"))
        sid = int(data["id"])
        name_en = str(data.get("name_en") or "").strip()
        model_key = str(data.get("model_key") or "").strip()
        kind = "unmanned" if bool(data.get("is_unmanned")) else "ship"
        pack_dir = PACKS / model_key if model_key else None
        portrait = PORTRAITS / f"{model_key}.png" if model_key else None
        entry = {
            "id": sid,
            "kind": kind,
            "name": str(data.get("name") or ""),
            "name_en": name_en,
            "model_key": model_key,
            "ship_group": str(data.get("ship_group") or ""),
            "race": str(data.get("race") or ""),
            "echoes_item_id": data.get("echoes_item_id"),
            "json_path": str(path),
            "pack_dir": str(pack_dir) if pack_dir else "",
            "portrait_path": str(portrait) if portrait and portrait.is_file() else "",
            "pc_res_path": canonical_pc_res_path(data),
        }
        by_id[str(sid)] = entry
        if name_en:
            if name_en in by_name_en:
                collisions.setdefault(name_en, [by_name_en[name_en]["id"]]).append(sid)
            else:
                by_name_en[name_en] = entry
    return {"by_id": by_id, "by_name_en": by_name_en, "collisions": collisions}


def main() -> None:
    payload = build_index()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"ids={len(payload['by_id'])} names={len(payload['by_name_en'])} collisions={len(payload['collisions'])} -> {OUT}"
    )


if __name__ == "__main__":
    main()
