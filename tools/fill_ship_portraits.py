# -*- coding: utf-8 -*-
"""Fill portraits for all ships 1–63 into ship_portraits.json.

Priority:
  1. existing portraits/{model_key}.png
  2. asset_library entity portrait/*.png or textures icon
  3. generate name-card PNG (never ChampionIcons)
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(r"H:\game_dev\eveautochess-dev")
GODOT = ROOT / "godot_project"
SHIPS = GODOT / "data" / "ships"
UNMANNED = GODOT / "data" / "unmanned_units"
PORTRAIT_DIR = GODOT / "assets" / "ui" / "portraits"
OUT_JSON = GODOT / "data" / "ship_portraits.json"
LIB_SHIPS = Path(r"H:\eve手游\history\asset_library\entities\ships")
ITEMS_ICONS = Path(r"H:\eve手游\history\asset_library\items\icons")


def find_font() -> ImageFont.ImageFont:
    for p in [
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\arial.ttf"),
    ]:
        if p.exists():
            try:
                return ImageFont.truetype(str(p), 28)
            except Exception:
                pass
    return ImageFont.load_default()


def make_name_card(name: str, dest: Path) -> None:
    w, h = 160, 128
    im = Image.new("RGBA", (w, h), (18, 24, 36, 255))
    draw = ImageDraw.Draw(im)
    draw.rectangle([2, 2, w - 3, h - 3], outline=(90, 140, 180, 255), width=2)
    font = find_font()
    # wrap roughly
    text = name
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = max(6, (w - tw) // 2)
    y = max(6, (h - th) // 2)
    draw.text((x, y), text, fill=(240, 245, 255, 255), font=font)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest)


def copy_lib_portrait(model_key: str, dest: Path) -> bool:
    for p in LIB_SHIPS.iterdir() if LIB_SHIPS.exists() else []:
        if not p.is_dir():
            continue
        if not (p.name == model_key or p.name.startswith(model_key + "__")):
            continue
        portrait = p / "portrait"
        if portrait.is_dir():
            for ext in ("*.png", "*.jpg", "*.webp"):
                hits = list(portrait.glob(ext))
                if hits:
                    Image.open(hits[0]).convert("RGBA").resize((160, 128)).save(dest)
                    return True
        # sometimes icon under textures
        tex = p / "textures"
        if tex.is_dir():
            for cand in tex.glob("*icon*.png"):
                Image.open(cand).convert("RGBA").resize((160, 128)).save(dest)
                return True
    return False


def iter_ship_jsons() -> list[Path]:
    paths = list(SHIPS.glob("*.json"))
    paths.extend(UNMANNED.glob("*.json"))
    return sorted(paths, key=lambda x: int(json.loads(x.read_text(encoding="utf-8"))["id"]))


def main() -> None:
    PORTRAIT_DIR.mkdir(parents=True, exist_ok=True)
    mapping: dict[str, str] = {}
    for p in iter_ship_jsons():
        d = json.loads(p.read_text(encoding="utf-8"))
        if d.get("is_unmanned") and d.get("unmanned_kind") == "combat_drone":
            # Combat drones: Echoes item icons via extract_drone_portraits.py
            continue
        sid = str(d["id"])
        key = str(d.get("model_key") or f"ship_{sid}")
        name = str(d.get("name") or key)
        dest = PORTRAIT_DIR / f"{key}.png"
        if dest.exists() and dest.stat().st_size > 500:
            mapping[sid] = f"res://assets/ui/portraits/{key}.png"
            continue
        if copy_lib_portrait(key, dest):
            mapping[sid] = f"res://assets/ui/portraits/{key}.png"
            print("LIB", sid, key)
            continue
        make_name_card(name, dest)
        mapping[sid] = f"res://assets/ui/portraits/{key}.png"
        print("CARD", sid, name)
    OUT_JSON.write_text(
        json.dumps({"ships": mapping}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {OUT_JSON} count={len(mapping)}")


if __name__ == "__main__":
    main()
