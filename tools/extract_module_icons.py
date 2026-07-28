from __future__ import annotations

import json
import struct
from pathlib import Path

import texture2ddecoder
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
GODOT = ROOT / "godot_project"
SHIPS_DIR = GODOT / "data" / "ships"
MODULES_RAW = Path(r"H:\game_dev\eveautochess-design\docs\_extracted\modules_raw.json")
OUT_DIR = GODOT / "assets" / "ui" / "item_icons"
MANIFEST = GODOT / "data" / "weapon_module_icons.json"

HISTORY = Path(r"H:\eve手游\history")
LIB_ICONS = HISTORY / "asset_library" / "items" / "icons"
NAME_ZH = HISTORY / "asset_library" / "indexes" / "items_id_to_name_zh.json"
COMPOSE = HISTORY / "asset_library" / "indexes" / "items_icon_compose_index.json"
ART_ROOTS = [
    HISTORY / "1.0.0_unpacked" / "art_extract",
    HISTORY / "asset_library",
]
MANUAL_ICON_ID: dict[int, int] = {
    # Visual ground truth — some ktx exist only under items/icons/ (not in compose index).
    453: 120040002,  # 小激光：单管白金色（图1）
    456: 120040103,  # 中激光：双管
    485: 120100001,  # 小加农：双管铜色（图2；勿用 120100002=200mm）
    491: 120100101,  # 中加农：425mm
}
MANUAL_ITEM_FALLBACK = {
    453: [11002510002],  # MK1 小型聚焦脉冲激光器
    456: [11002600006],  # MK5 重型脉冲激光器（手游中型对位）
    491: [11004220006],  # MK5 425mm自动加农炮
    499: [11012000002],
    501: [11012000002],
    561: [11000020002],
    570: [11000120004],
    3586: [11101000004],
    3596: [11101000004],
    11355: [11102000004],
    11357: [11102000004],
}

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


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def collect_module_ids() -> set[int]:
    ids: set[int] = set()
    for path in SHIPS_DIR.glob("*.json"):
        ship = load_json(path)
        for key in ("source_module_type_id", "source_repair_module_type_id"):
            mid = int(ship.get(key, 0) or 0)
            if mid > 0:
                ids.add(mid)
    return ids


def icon_candidates(item_id: int, compose_items: dict) -> list[Path]:
    out: list[Path] = []
    meta = compose_items.get(str(item_id), {})
    icon_id = meta.get("icon_id")
    if icon_id:
        out.append(LIB_ICONS / f"{icon_id}.ktx")
    out.append(LIB_ICONS / f"{item_id}.ktx")
    base = (meta.get("compose") or {}).get("base") or ""
    if isinstance(base, str) and base.startswith("res/"):
        rel = base.replace("res/", "", 1)
        for root in ART_ROOTS:
            out.append(root / rel)
    return out


def decode_any(path: Path) -> Image.Image | None:
    if not path.is_file():
        return None
    if path.suffix.lower() == ".ktx":
        return decode_ktx(path)
    return Image.open(path)


def fuzzy_item_ids(name_zh: str, item_names: dict) -> list[int]:
    tokens: list[str] = []
    if "小型" in name_zh:
        tokens.append("小型")
    elif "中型" in name_zh:
        tokens.append("中型")
    elif "大型" in name_zh:
        tokens.append("大型")
    if "激光" in name_zh:
        tokens.append("激光")
    elif "磁轨" in name_zh:
        tokens.append("磁轨")
    elif "加农" in name_zh:
        tokens.append("加农")
    elif "导弹发射器" in name_zh:
        tokens.extend(["导弹", "发射器"])
    elif "远维盾" in name_zh:
        tokens.extend(["远程", "护盾"])
    elif "远维甲" in name_zh:
        tokens.extend(["远程", "装甲", "维修"])
    if not tokens:
        tokens = [name_zh]
    hits: list[tuple[int, str]] = []
    for item_id, item_name in item_names.items():
        text = str(item_name)
        if all(tok in text for tok in tokens):
            hits.append((int(item_id), text))
    def score(row: tuple[int, str]) -> tuple[int, int, int]:
        item_id, text = row
        return (
            0 if text.startswith("MK1 ") else 1,
            0 if text.startswith("MK") else 1,
            item_id,
        )
    hits.sort(key=score)
    return [item_id for item_id, _ in hits]


def save_module_icon(module_id: int, name_zh: str, cand: Path, item_id: int, icon_id: int | None) -> tuple[bool, str, dict]:
    im = decode_any(cand)
    if im is None:
        return False, f"no icon decoded for {name_zh}", {}
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dst = OUT_DIR / f"{module_id}.png"
    im = im.convert("RGBA")
    im.thumbnail((256, 256), Image.Resampling.LANCZOS)
    im.save(dst)
    return True, f"{name_zh} <= {cand.name}", {
        "module_type_id": module_id,
        "name_zh": name_zh,
        "echoes_item_id": item_id,
        "icon_ktx": str(cand),
        "png": f"res://assets/ui/item_icons/{module_id}.png",
        "icon_id": icon_id,
    }


def extract_for_module(module_id: int, modules_raw: dict, item_names: dict, compose_items: dict) -> tuple[bool, str, dict]:
    mod = modules_raw.get(str(module_id), {})
    name_zh = str(mod.get("nameZH", "")).strip()
    if not name_zh:
        return False, "missing nameZH", {}
    if module_id in MANUAL_ICON_ID:
        icon_id = int(MANUAL_ICON_ID[module_id])
        cand = LIB_ICONS / f"{icon_id}.ktx"
        item_id = int((MANUAL_ITEM_FALLBACK.get(module_id) or [0])[0])
        ok, note, info = save_module_icon(module_id, name_zh, cand, item_id, icon_id)
        if ok:
            return ok, note, info
    item_ids = MANUAL_ITEM_FALLBACK.get(module_id, []) + fuzzy_item_ids(name_zh, item_names)
    if not item_ids:
        return False, f"no item ids for {name_zh}", {}
    seen: set[str] = set()
    for item_id in item_ids:
        for cand in icon_candidates(int(item_id), compose_items):
            key = str(cand)
            if key in seen:
                continue
            seen.add(key)
            meta = compose_items.get(str(item_id), {})
            ok, note, info = save_module_icon(
                module_id, name_zh, cand, int(item_id), meta.get("icon_id")
            )
            if ok:
                return ok, note, info
    return False, f"no icon decoded for {name_zh}", {}


def main() -> None:
    modules_raw = load_json(MODULES_RAW)
    item_names = load_json(NAME_ZH)
    compose_items = load_json(COMPOSE).get("items", {})
    ok = 0
    fail = []
    manifest: dict[str, dict] = {}
    for module_id in sorted(collect_module_ids()):
        success, note, info = extract_for_module(module_id, modules_raw, item_names, compose_items)
        if success:
            ok += 1
            manifest[str(module_id)] = info
            print(f"OK {module_id}: {note}")
        else:
            fail.append((module_id, note))
            print(f"MISS {module_id}: {note}")
    MANIFEST.write_text(
        json.dumps({"modules": manifest, "echoes_icon_dir": str(LIB_ICONS)}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"done ok={ok} fail={len(fail)} out={OUT_DIR} manifest={MANIFEST}")
    if fail:
        print("failed:", fail)


if __name__ == "__main__":
    main()
