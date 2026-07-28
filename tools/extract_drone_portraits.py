# -*- coding: utf-8 -*-
"""Extract combat drone portraits from Echoes item icons (KTX → PNG).

Reads data/unmanned_units/*.json (echoes_item_id + model_key), writes
assets/ui/portraits/{model_key}.png and merges ship_portraits.json.
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

import texture2ddecoder
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
GODOT = ROOT / "godot_project"
UNMANNED = GODOT / "data" / "unmanned_units"
PORTRAIT_DIR = GODOT / "assets" / "ui" / "portraits"
PORT_JSON = GODOT / "data" / "ship_portraits.json"
MATCH_OUT = GODOT / "data" / "_extracted" / "ship_asset_match_index.json"

LIB_ICONS = Path(r"H:\eve手游\history\asset_library\items\icons")
COMPOSE = Path(r"H:\eve手游\history\asset_library\indexes\items_icon_compose_index.json")

ASTC_BLOCK = {
    0x93B0: (4, 4), 0x93B1: (5, 5), 0x93B2: (5, 6), 0x93B3: (6, 5), 0x93B4: (6, 6),
    0x93B5: (8, 5), 0x93B6: (8, 6), 0x93B7: (8, 8), 0x93B8: (10, 5), 0x93B9: (10, 6),
    0x93BA: (10, 8), 0x93BB: (10, 10), 0x93BC: (12, 10), 0x93BD: (12, 12),
    0x93D0: (4, 4), 0x93D1: (5, 5), 0x93D2: (5, 6), 0x93D3: (6, 5), 0x93D4: (6, 6),
    0x93D5: (8, 5), 0x93D6: (8, 6), 0x93D7: (8, 8), 0x93D8: (10, 5), 0x93D9: (10, 6),
    0x93DA: (10, 8), 0x93DB: (10, 10), 0x93DC: (12, 10), 0x93DD: (12, 12),
}


def decode_ktx(path: Path) -> Image.Image | None:
    data = path.read_bytes()
    if data[:7] != b"\xabKTX 11":
        return None
    vals = struct.unpack_from("<12I", data, 16)
    internal, w, h, kv = vals[3], vals[5], vals[6], vals[11]
    bw, bh = ASTC_BLOCK.get(internal, (0, 0))
    if bw == 0:
        return None
    off = 64 + kv
    if off + 4 > len(data):
        return None
    sz = struct.unpack_from("<I", data, off)[0]
    off += 4
    raw = data[off : off + sz]
    rgba = texture2ddecoder.decode_astc(raw, w, h, bw, bh)
    return Image.frombytes("RGBA", (w, h), rgba, "raw", "BGRA")


def icon_path_for_item(item_id: int, compose_items: dict) -> Path | None:
    meta = compose_items.get(str(item_id), {})
    icon_id = meta.get("icon_id")
    if icon_id:
        cand = LIB_ICONS / f"{icon_id}.ktx"
        if cand.is_file():
            return cand
    cand = LIB_ICONS / f"{item_id}.ktx"
    return cand if cand.is_file() else None


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def iter_combat_drones() -> list[dict]:
    units: list[dict] = []
    for path in sorted(UNMANNED.glob("*.json")):
        d = load_json(path)
        if not d.get("is_unmanned") or d.get("unmanned_kind") != "combat_drone":
            continue
        if "id" not in d:
            continue
        units.append({"path": path, **d})
    return sorted(units, key=lambda u: int(u["id"]))


def main() -> None:
    compose_items = load_json(COMPOSE).get("items", {})
    port_data = load_json(PORT_JSON) if PORT_JSON.is_file() else {"ships": {}}
    ships_map: dict[str, str] = dict(port_data.get("ships", {}))
    match_index = load_json(MATCH_OUT) if MATCH_OUT.is_file() else {}

    PORTRAIT_DIR.mkdir(parents=True, exist_ok=True)
    ok = 0
    for unit in iter_combat_drones():
        drone_id = int(unit["id"])
        model_key = str(unit.get("model_key", ""))
        echoes_item_id = int(unit.get("echoes_item_id", 0) or 0)
        unit_path: Path = unit["path"]
        if not model_key:
            print(f"MISS model_key for {drone_id}")
            continue
        if echoes_item_id <= 0:
            print(f"MISS echoes_item_id for {drone_id}")
            continue

        icon_path = icon_path_for_item(echoes_item_id, compose_items)
        if icon_path is None:
            print(f"MISS ktx for {drone_id} item={echoes_item_id}")
            continue
        im = decode_ktx(icon_path)
        if im is None:
            print(f"FAIL decode {icon_path}")
            continue

        dst = PORTRAIT_DIR / f"{model_key}.png"
        im = im.convert("RGBA")
        im.thumbnail((256, 256), Image.Resampling.LANCZOS)
        im.save(dst)

        sid = str(drone_id)
        res_path = f"res://assets/ui/portraits/{model_key}.png"
        ships_map[sid] = res_path

        entry = match_index.get(sid, {})
        entry.update(
            {
                "id": drone_id,
                "name": unit.get("name", ""),
                "model_key": model_key,
                "kind": "drone",
                "portrait": res_path,
                "portrait_src": str(icon_path),
                "echoes_item_id": echoes_item_id,
            }
        )
        match_index[sid] = entry
        ok += 1
        print(f"OK {drone_id} {model_key} <= {icon_path.name}")

    save_json(PORT_JSON, {"ships": ships_map})
    MATCH_OUT.parent.mkdir(parents=True, exist_ok=True)
    save_json(MATCH_OUT, match_index)
    print(f"done ok={ok} portraits={PORT_JSON}")


if __name__ == "__main__":
    main()
