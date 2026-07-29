# -*- coding: utf-8 -*-
"""Stage user-confirmed capital/cyno/fighter/drone icons into review pack."""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

OUT = Path(r"H:\game_dev\eveautochess-design\docs\_review\capital_cyno_assets_confirm")
MIRROR = Path(r"H:\game_dev\eveautochess-design\docs\_review\ktx_png_mirror\equipment_textures")
EQ_TEX = Path(r"H:\eve手游\history\1.9.62_unpacked\asset_library\equipment_textures")

# User order; 「骑士蚂蚱」→ 骑士 + 蚂蚱 (4 fighters total with 萨梯/拉格墨)
ENTRIES = [
    ("equip", "01_旗舰鱼雷", "11023000000", "旗舰鱼雷"),
    ("equip", "02_旗舰加农", "11004810000", "旗舰加农"),
    ("equip", "03_旗舰激光", "11002810000", "旗舰激光"),
    ("equip", "04_旗舰磁轨", "11000320000", "旗舰磁轨"),
    ("ships", "12_尼铎格尔级", "10702000201", "尼铎格尔（用户称尼格尔泽）"),
    ("equip", "00_诱导", "11114010000", "诱导"),
    ("heavy_repair_drones", "01_重型a后勤无人机", "14000200000", "重型a后勤无人机"),
    ("heavy_repair_drones", "02_重型c后勤无人机", "14000200005", "重型c后勤无人机"),
    ("heavy_repair_drones", "03_重型g后勤无人机", "14000200010", "重型g后勤无人机"),
    ("heavy_repair_drones", "04_重型m后勤无人机", "14000200015", "重型m后勤无人机"),
    ("fighters", "01_骑士_Equite", "15100000000", "骑士"),
    ("fighters", "02_蚂蚱_Locust", "15100000010", "蚂蚱"),
    ("fighters", "03_萨梯_Satyr", "15100000020", "萨梯"),
    ("fighters", "04_拉格墨_Gram", "15100000030", "拉格墨"),
]


def main() -> None:
    confirmed = []
    for folder, stem, iid, label in ENTRIES:
        d = OUT / folder
        d.mkdir(parents=True, exist_ok=True)
        src = MIRROR / f"item__{iid}.png"
        if not src.is_file():
            raise SystemExit(f"missing mirror {src}")
        dst = d / f"{stem}.png"
        shutil.copy2(src, dst)
        shutil.copy2(src, d / f"_src_item__{iid}.png")
        ktx = EQ_TEX / f"item__{iid}.ktx"
        rel = str(dst.relative_to(OUT)).replace("\\", "/")
        confirmed.append(
            {
                "order": len(confirmed) + 1,
                "user_label": label,
                "folder": folder,
                "file": rel,
                "item_id": iid,
                "ktx": str(ktx) if ktx.is_file() else "",
                "mirror_png": str(src),
            }
        )
        print(f"OK {rel} <- item__{iid}")

    (OUT / "USER_CONFIRMED_ICONS.json").write_text(
        json.dumps(confirmed, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# 用户人工确认 · 图标对照（按你给的顺序）",
        "",
        "| # | 你的名称 | itemId | 确认包文件 | 原 KTX |",
        "|---|----------|--------|------------|--------|",
    ]
    for c in confirmed:
        lines.append(
            f"| {c['order']} | {c['user_label']} | `{c['item_id']}` | `{c['file']}` "
            f"| `item__{c['item_id']}.ktx` |"
        )
    lines += [
        "",
        "原 KTX：`H:\\eve手游\\history\\1.9.62_unpacked\\asset_library\\equipment_textures\\item__{id}.ktx`",
        "",
        "PNG 镜像：`H:\\game_dev\\eveautochess-design\\docs\\_review\\ktx_png_mirror\\equipment_textures\\item__{id}.png`",
        "",
        "说明：「骑士蚂蚱」按四帝国舰载机拆成 **骑士** + **蚂蚱**（另两张萨梯、拉格墨）。",
        "尼铎格尔立绘现用 `10702000201`。",
        "",
    ]
    (OUT / "USER_CONFIRMED_ICONS.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT / 'USER_CONFIRMED_ICONS.md'}")


if __name__ == "__main__":
    main()
