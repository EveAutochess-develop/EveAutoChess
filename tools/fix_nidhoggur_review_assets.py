# -*- coding: utf-8 -*-
"""Fix Nidhoggur (尼铎格尔) confirm pack: correct mesh + UI crop portrait; drop stray Archon alt."""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
from stage_capital_cyno_review_assets import (  # noqa: E402
    OUT,
    TMP_GLB,
    decode_ktx,
    threeview_for,
)

OLD_STEM = "12_尼格尔泽级"
NEW_STEM = "12_尼铎格尔级"
MODEL_KEY = "mmte_niyigeer"
SCREENSHOT = Path(
    r"C:\Users\WXH\.cursor\projects\h\assets"
    r"\c__Users_WXH_AppData_Roaming_Cursor_User_workspaceStorage"
    r"_a6e066ac4a2afb80200e61f3e501804f_images"
    r"_1cdd3fa9249d2d9d71e9e7facf9fecd7-9fb5bd05-65ea-42f0-ac8b-3cd7747cd73c.png"
)
ALBEDO = Path(
    r"H:\eve手游\history\asset_library\entities\ships\mmte_niyigeer"
    r"\textures\mmte_niyigeer_ad.ktx"
)
STRAY_STEM = "09b_地狱天使级"
STRAY_GLB = TMP_GLB / "am_diyutianshi.glb"
WRONG_GLB = TMP_GLB / "lhky_nijijing.glb"


def crop_ui_portrait(dst: Path) -> None:
    """Crop ship art from Echoes market card screenshot (尼铎格尔级)."""
    im = Image.open(SCREENSHOT).convert("RGBA")
    w, h = im.size
    # Card art sits above the price bar; leave title strip + bottom chrome out.
    box = (int(w * 0.06), int(h * 0.14), int(w * 0.94), int(h * 0.78))
    crop = im.crop(box)
    # Fit into 512 square on dark panel.
    size = 512
    canvas = Image.new("RGBA", (size, size), (28, 32, 40, 255))
    crop.thumbnail((size - 24, size - 24), Image.Resampling.LANCZOS)
    ox = (size - crop.width) // 2
    oy = (size - crop.height) // 2
    canvas.paste(crop, (ox, oy), crop)
    canvas.save(dst, "PNG")
    print(f"[portrait] {dst.name} <- screenshot crop {box}")


def save_albedo_ref(dst: Path) -> None:
    if not ALBEDO.is_file():
        return
    im = decode_ktx(ALBEDO)
    if im is None:
        return
    im.save(dst, "PNG")
    print(f"[albedo] {dst.name} <- {ALBEDO.name}")


def patch_manifest(tv: dict) -> None:
    man_path = OUT / "manifest.json"
    if not man_path.is_file():
        return
    man = json.loads(man_path.read_text(encoding="utf-8"))
    ships = []
    for r in man.get("ships", []):
        f = r.get("file", "")
        if OLD_STEM in f or NEW_STEM in f:
            ships.append({
                "file": f"ships/{NEW_STEM}.png",
                "label": "尼铎格尔级 / Nidhoggur",
                "status": "ok",
                "source": str(SCREENSHOT),
                "note": "Echoes UI 截图裁切；库无 mca1 isis（mca2=冥府超航）",
            })
        else:
            ships.append(r)
    man["ships"] = ships
    tvs = []
    for r in man.get("models_threeview", []):
        stem = r.get("stem", "")
        if stem == STRAY_STEM:
            continue
        if stem in (OLD_STEM, NEW_STEM):
            tvs.append(tv)
        else:
            tvs.append(r)
    man["models_threeview"] = tvs
    man_path.write_text(json.dumps(man, ensure_ascii=False, indent=2), encoding="utf-8")
    print("[manifest] patched")


def patch_readme() -> None:
    rd = OUT / "README.md"
    if not rd.is_file():
        return
    text = rd.read_text(encoding="utf-8")
    text = text.replace(OLD_STEM, NEW_STEM)
    text = text.replace("`lhky_nijijing`", f"`{MODEL_KEY}`")
    text = text.replace("| Nidhoggur |", "| 米玛塔尔航母 Nidhoggur；原误用尼基京 |")
    # drop 09b row if present
    lines = []
    for line in text.splitlines():
        if STRAY_STEM in line or "am_diyutianshi" in line and "09b" in line:
            continue
        if "地狱天使玩家立绘" in line and "09_执政官" in line:
            line = line.replace("shiptree + 地狱天使玩家立绘", "shiptree aca2 isis（执政官）")
        lines.append(line)
    note = (
        "\n## 2026-07-29 修正\n\n"
        f"- **{NEW_STEM}**：立绘改为你提供的 Echoes「尼铎格尔级」市场卡裁切；"
        f"三视图改为 `{MODEL_KEY}`（米玛塔尔小航）。\n"
        "- 误用：`shiptree__mca2`=冥府级超航；`lhky_nijijing`=尼基京级，≠ Nidhoggur。\n"
        f"- 已删除确认包内多余的 `{STRAY_STEM}`（`am_diyutianshi`，手游 Archon 键，"
        "不是地狱天使战列；执政官以 `09_执政官级`/`am_zhizhengguan` 为准）。\n"
    )
    body = "\n".join(lines)
    if "## 2026-07-29 修正" not in body:
        body = body.rstrip() + "\n" + note
    rd.write_text(body, encoding="utf-8")
    print("[readme] patched")


def main() -> None:
    ships = OUT / "ships"
    ships.mkdir(parents=True, exist_ok=True)

    # rename / replace portrait
    for p in ships.glob("12_*.png"):
        if p.stem != NEW_STEM:
            p.unlink(missing_ok=True)
    crop_ui_portrait(ships / f"{NEW_STEM}.png")
    save_albedo_ref(ships / f"{NEW_STEM}_albedo_ref.png")

    # remove wrong threeview dirs
    tv_root = OUT / "models_threeview"
    for stem in (OLD_STEM, NEW_STEM, STRAY_STEM):
        d = tv_root / stem
        if d.is_dir():
            shutil.rmtree(d, ignore_errors=True)
            print(f"[rm] {d.name}")

    for glb in (STRAY_GLB, WRONG_GLB):
        if glb.is_file():
            glb.unlink()
            print(f"[rm] {glb.name}")

    # force rebuild glb for correct key
    good = TMP_GLB / f"{MODEL_KEY}.glb"
    if good.is_file():
        good.unlink()

    tv = threeview_for(
        NEW_STEM,
        MODEL_KEY,
        "Nidhoggur / 尼铎格尔；Echoes mmte_niyigeer（非 lhky_nijijing 尼基京）",
    )
    patch_manifest(tv)
    patch_readme()
    print(f"\nDONE status={tv.get('status')} strip={tv.get('strip')}")


if __name__ == "__main__":
    main()
