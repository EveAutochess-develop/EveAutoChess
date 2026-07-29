# -*- coding: utf-8 -*-
"""Stage heavy-repair-drone orthographic three-views from PC GR2.

Race hulls = TQ heavy combat drone sofHull (same mesh as maintenance bots):
  a Amarr   Heavy Armor Maintenance Bot I  → adh1_t1
  c Caldari Heavy Shield Maintenance Bot II → cdh1_t2
            (cdh1_t1.gr2 FileInfo.Meshes AOR broken / unreadable)
  g Gallente Heavy Hull Maintenance Bot I  → gdh1_t1
  m Minmatar (Echoes race slot; TQ has no Heavy Minmatar maint bot) → mdh1_t1
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))

from stage_fighter_threeviews import (  # noqa: E402
    OUT,
    SIZE,
    Gr2Meshes,
    auto_orient,
    pick_best_mesh,
    render_ortho,
)
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

DRONES = [
    (
        "21_重型a后勤_Amarr",
        "重型a后勤无人机",
        "Heavy Armor Maintenance Bot I / adh1_t1",
        "res:/dx9/model/drone/amarr/heavy/adh1/adh1_t1.gr2",
        23523,
    ),
    (
        "22_重型c后勤_Caldari",
        "重型c后勤无人机",
        # cdh1_t1.gr2 FileInfo Meshes AOR 不可解析；T2 同族壳（Shield Maint Bot II）
        "Heavy Shield Maintenance Bot II / cdh1_t2",
        "res:/dx9/model/drone/caldari/heavy/cdh1/cdh1_t2.gr2",
        28199,
    ),
    (
        "23_重型g后勤_Gallente",
        "重型g后勤无人机",
        "Heavy Hull Maintenance Bot I / gdh1_t1",
        "res:/dx9/model/drone/gallente/heavy/gdh1/gdh1_t1.gr2",
        33671,
    ),
    (
        "24_重型m后勤_Minmatar",
        "重型m后勤无人机",
        "Berserker I hull / mdh1_t1",
        "res:/dx9/model/drone/minmatar/heavy/mdh1/mdh1_t1.gr2",
        2476,
    ),
]


def stage_one(stem: str, zh: str, en: str, res_path: str) -> dict:
    out_dir = OUT / "models_threeview" / stem
    out_dir.mkdir(parents=True, exist_ok=True)
    gr2 = fetch_resfile(res_path)
    print(f"[drone] {stem} <- {res_path}")
    g = Gr2Meshes(gr2)
    name, verts, faces = pick_best_mesh(g)
    verts = auto_orient(verts, faces)
    print(f"  selected {name!r} verts={len(verts)} tris={len(faces)}")

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
        "status": "ok",
        "mesh": name,
        "verts": len(verts),
        "tris": int(len(faces)),
        "res": res_path,
    }


def patch_readme(results: list[dict]) -> None:
    readme = OUT / "README.md"
    if not readme.is_file():
        return
    text = readme.read_text(encoding="utf-8")
    marker = "## heavy_repair_drones threeview"
    rows = [
        "",
        marker,
        "",
        "重型后勤无人机正交三视图（端游 GR2 · 各族 heavy drone hull，与维修机器人同壳）：",
        "",
        "| 目录 | 状态 |",
        "|------|------|",
    ]
    for r in results:
        if r["status"] == "ok":
            rows.append(
                f"| `models_threeview/{r['stem']}/` | ok {r['mesh']} verts={r['verts']} tris={r['tris']} |"
            )
        else:
            rows.append(f"| `models_threeview/{r['stem']}/` | fail {r.get('error')} |")
    rows.append("")
    block = "\n".join(rows)
    if marker in text:
        # keep content before marker; drop old drone threeview section only
        head = text.split(marker)[0].rstrip()
        # if fighters section follows in old layout, preserve nothing after marker
        # but fighters marker is earlier — so only replace from our marker to EOF-ish
        # Prefer: replace from marker through end, then re-append nothing else after
        rest_after = text.split(marker, 1)[1]
        # stop at next ## if any (shouldn't for drones at end)
        if "\n## " in rest_after:
            after = "\n## " + rest_after.split("\n## ", 1)[1]
            text = head + "\n" + block + after
        else:
            text = head + "\n" + block
    else:
        text = text.rstrip() + "\n" + block
    text = text.replace(
        "| models_threeview/ | 舰船 + 舰载机正交三视图 |",
        "| models_threeview/ | 舰船 + 舰载机 + 后勤无人机正交三视图 |",
    )
    readme.write_text(text, encoding="utf-8")


def patch_icons_md() -> None:
    md = OUT / "USER_CONFIRMED_ICONS.md"
    if not md.is_file():
        return
    text = md.read_text(encoding="utf-8")
    marker = "## 重型后勤无人机模型三视图"
    section = """
## 重型后勤无人机模型三视图

端游 GR2（各族 heavy drone `sofHull`，与维修机器人同壳；无独立 Minmatar Heavy Maintenance Bot，m 用 `mdh1_t1`）：

| 无人机 | TQ 参照 | typeID | 确认包目录 |
|--------|---------|--------|------------|
| 重型a后勤 | Heavy Armor Maintenance Bot I / adh1_t1 | 23523 | `models_threeview/21_重型a后勤_Amarr/` |
| 重型c后勤 | Heavy Shield Maintenance Bot II / cdh1_t2（T1 GR2 FileInfo 损坏） | 28199 | `models_threeview/22_重型c后勤_Caldari/` |
| 重型g后勤 | Heavy Hull Maintenance Bot I / gdh1_t1 | 33671 | `models_threeview/23_重型g后勤_Gallente/` |
| 重型m后勤 | Berserker I hull / mdh1_t1 | 2476 | `models_threeview/24_重型m后勤_Minmatar/` |

每目录含 `front.png` / `side.png` / `top.png` / `threeview_strip.png`。脚本：`eveautochess-dev/tools/stage_heavy_repair_drone_threeviews.py`。
"""
    if marker in text:
        head = text.split(marker)[0].rstrip()
        rest = text.split(marker, 1)[1]
        if "\n## " in rest:
            after = "\n## " + rest.split("\n## ", 1)[1]
            text = head + "\n" + section.rstrip() + "\n" + after.lstrip("\n")
        else:
            text = head + "\n" + section.rstrip() + "\n"
    else:
        text = text.rstrip() + "\n" + section
    md.write_text(text, encoding="utf-8")


def main() -> None:
    results = []
    for stem, zh, en, res, _tid in DRONES:
        try:
            results.append(stage_one(stem, zh, en, res))
        except Exception as e:
            print(f"[FAIL] {stem}: {e}")
            results.append({"stem": stem, "status": "fail", "error": str(e)})

    patch_readme(results)
    patch_icons_md()
    ok = sum(1 for r in results if r["status"] == "ok")
    print(f"done ok={ok}/{len(results)}")


if __name__ == "__main__":
    main()
