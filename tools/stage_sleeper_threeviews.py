# -*- coding: utf-8 -*-
"""Stage all TQ Sleeper faction ship hulls as orthographic three-views.

Output: eveautochess-design/docs/_review/sleeper_assets_confirm/models_threeview/
Also copies TQ 512 icons next to each hull for portrait cross-check.
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from io_scene_gr2.gr2.file import read_gr2  # noqa: E402
from io_scene_gr2.gr2.fixup import load_sections  # noqa: E402

# Reuse mining threeview helpers
from stage_mining_threeviews import (  # noqa: E402
    Gr2Meshes,
    auto_orient,
    pick_best_mesh,
    render_ortho,
    SIZE,
)

OUT = Path(r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\sleeper_assets_confirm")

# TQ sleeper combat hulls only (no structures / wrecks / effects).
# EN class names are CCP hull-folder labels; ZH are Echoes class-level terms.
HULLS = [
    (
        "01_slf1_冬眠者护卫舰A_SleeperFrigate_A",
        "冬眠者护卫舰 A",
        "Sleeper Frigate A (slf1)",
        "res:/dx9/model/ship/sleeper/frigate/slf1/slf1_t1.gr2",
        "res:/dx9/model/ship/sleeper/frigate/slf1/icons/3528_512.jpg",
    ),
    (
        "02_slf2_冬眠者护卫舰B_SleeperFrigate_B",
        "冬眠者护卫舰 B",
        "Sleeper Frigate B (slf2)",
        "res:/dx9/model/ship/sleeper/frigate/slf2/slf2_t1.gr2",
        "res:/dx9/model/ship/sleeper/frigate/slf2/icons/3560_512.jpg",
    ),
    (
        "03_slde1_冬眠者驱逐舰_SleeperDestroyer",
        "冬眠者驱逐舰",
        "Sleeper Destroyer (slde1)",
        "res:/dx9/model/ship/sleeper/destroyer/slde1/slde1_t1.gr2",
        "res:/dx9/model/ship/sleeper/destroyer/slde1/icons/3527_512.jpg",
    ),
    (
        "04_slc1_冬眠者巡洋舰A_SleeperCruiser_A",
        "冬眠者巡洋舰 A",
        "Sleeper Cruiser A (slc1)",
        "res:/dx9/model/ship/sleeper/cruiser/slc1/slc1_t1.gr2",
        "res:/dx9/model/ship/sleeper/cruiser/slc1/icons/3536_512.jpg",
    ),
    (
        "05_slc2_冬眠者巡洋舰B_SleeperCruiser_B",
        "冬眠者巡洋舰 B",
        "Sleeper Cruiser B (slc2)",
        "res:/dx9/model/ship/sleeper/cruiser/slc2/slc2_t1.gr2",
        "res:/dx9/model/ship/sleeper/cruiser/slc2/icons/20978_512.jpg",
    ),
    (
        "06_slb1_冬眠者战列舰A_SleeperBattleship_A",
        "冬眠者战列舰 A",
        "Sleeper Battleship A (slb1)",
        "res:/dx9/model/ship/sleeper/battleship/slb1/slb1_t1.gr2",
        "res:/dx9/model/ship/sleeper/battleship/slb1/icons/3516_512.jpg",
    ),
    (
        "07_slb2_冬眠者战列舰B_SleeperBattleship_B",
        "冬眠者战列舰 B",
        "Sleeper Battleship B (slb2)",
        "res:/dx9/model/ship/sleeper/battleship/slb2/slb2_t1.gr2",
        "res:/dx9/model/ship/sleeper/battleship/slb2/icons/3559_512.jpg",
    ),
]


def _safe_print(*args, **kwargs) -> None:
    try:
        print(*args, **kwargs)
    except UnicodeEncodeError:
        text = " ".join(str(a) for a in args)
        print(text.encode("ascii", "replace").decode("ascii"), **kwargs)


def stage_one(stem: str, zh: str, en: str, gr2_res: str, icon_res: str) -> dict:
    out_dir = OUT / "models_threeview" / stem
    out_dir.mkdir(parents=True, exist_ok=True)

    # TQ stock icon
    try:
        icon_src = fetch_resfile(icon_res)
        icon_dst = out_dir / "tq_icon_512.jpg"
        shutil.copy2(icon_src, icon_dst)
    except Exception as e:
        icon_dst = None
        _safe_print(f"  icon fail: {e}")

    gr2 = fetch_resfile(gr2_res)
    _safe_print(f"[sleeper] {stem} <- {gr2_res}")
    g = Gr2Meshes(gr2)
    name, verts, faces = pick_best_mesh(g)
    verts = auto_orient(verts, faces)
    _safe_print(f"  selected {name!r} verts={len(verts)} tris={len(faces)}")

    panels = []
    for view in ("front", "side", "top"):
        im = render_ortho(verts, faces, view)
        im.save(out_dir / f"{view}.png")
        panels.append(im)
    strip = Image.new("RGBA", (SIZE * 3 + 16, SIZE), (20, 22, 28, 255))
    for i, im in enumerate(panels):
        strip.paste(im, (i * (SIZE + 8), 0))
    bar = Image.new("RGBA", (strip.width, 36), (20, 22, 28, 255))
    ImageDraw.Draw(bar).text((12, 8), f"{zh} / {en}  {name}", fill=(200, 200, 210, 255))
    full = Image.new("RGBA", (strip.width, SIZE + 36), (20, 22, 28, 255))
    full.paste(bar, (0, 0))
    full.paste(strip, (0, 36))
    full.save(out_dir / "threeview_strip.png")
    return {
        "stem": stem,
        "zh": zh,
        "en": en,
        "status": "ok",
        "mesh": name,
        "verts": len(verts),
        "tris": int(len(faces)),
        "res": gr2_res,
        "tq_icon": str(icon_dst) if icon_dst else None,
    }


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass

    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for stem, zh, en, gr2_res, icon_res in HULLS:
        try:
            results.append(stage_one(stem, zh, en, gr2_res, icon_res))
        except Exception as e:
            _safe_print(f"[FAIL] {stem}: {e}")
            results.append(
                {"stem": stem, "zh": zh, "en": en, "status": "fail", "error": str(e), "res": gr2_res}
            )

    (OUT / "threeview_report.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    rows = [
        "# 冬眠者素材确认包 · sleeper_assets_confirm",
        "",
        "> 端游 TQ `res:/dx9/model/ship/sleeper/**` 全战斗船体三视图 + 手游立绘双语命名。",
        "> 脚本：`eveautochess-dev/tools/stage_sleeper_threeviews.py`",
        "",
        "## 端游船体清单（扫全）",
        "",
        "| 键 | 吨位 | GR2 | 战巡？ |",
        "|----|------|-----|--------|",
        "| slf1 / slf2 | 护卫 | 有 | 否 |",
        "| slde1 | 驱逐 | 有 | 否 |",
        "| slc1 / slc2 | 巡洋 | 有 | 否 |",
        "| slb1 / slb2 | 战列 | 有 | 否 |",
        "| *(无)* | **战巡** | **TQ 无 `sleeper/battlecruiser`** | — |",
        "",
        "## models_threeview",
        "",
        "| 目录 | 状态 |",
        "|------|------|",
    ]
    for r in results:
        if r["status"] == "ok":
            rows.append(
                f"| `models_threeview/{r['stem']}/` | ok `{r['mesh']}` verts={r['verts']} tris={r['tris']} |"
            )
        else:
            rows.append(f"| `models_threeview/{r['stem']}/` | fail {r.get('error')} |")
    rows.append("")
    (OUT / "README.md").write_text("\n".join(rows), encoding="utf-8")

    ok = sum(1 for r in results if r["status"] == "ok")
    print(f"done ok={ok}/{len(results)} -> {OUT}")


if __name__ == "__main__":
    main()
