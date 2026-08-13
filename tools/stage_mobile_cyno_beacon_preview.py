# -*- coding: utf-8 -*-
"""Stage Mobile Cynosural Beacon (移动式诱导信标) from TQ into docs/_review.

typeID 57319 · hull cyb01 · 32-bit Granny GR2 → OBJ (legacy) → GLB + threeviews + icons.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.dds_decode import decode_dds, save_png  # noqa: E402
from eve_pc.gr2_convert import gr2_to_obj  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from stage_mining_threeviews import auto_orient, render_ortho  # noqa: E402

OUT = Path(r"H:\game_dev\eveautochess-design\docs\_review\mobile_cyno_beacon_preview")
SIZE = 512

TYPE_ID = 57319
NAME_ZH = "移动式诱导信标"
NAME_EN = "Mobile Cynosural Beacon"
HULL = "cyb01"
GR2_RES = "res:/dx9/model/deployables/generic/navigation/cynobeacon/cyb01.gr2"

TEX_RES = {
    "albedo": "res:/dx9/model/shared/upwell/textures/uw_structure_02a_a.dds",
    "normal": "res:/dx9/model/shared/upwell/textures/uw_structure_02a_n.dds",
    "roughness": "res:/dx9/model/shared/upwell/textures/uw_structure_02a_r.dds",
    "metal": "res:/dx9/model/shared/upwell/textures/uw_structure_02a_m.dds",
    "glow": "res:/dx9/model/shared/upwell/textures/uw_structure_02a_g.dds",
}

ICON_RES = {
    "icon_512.jpg": "res:/dx9/model/deployables/generic/navigation/cynobeacon/icons/22262_512.jpg",
    "icon_128.png": "res:/dx9/model/deployables/generic/navigation/cynobeacon/icons/22262_128.png",
    "isis.png": "res:/dx9/model/deployables/generic/navigation/cynobeacon/icons/cyb01_isis.png",
}


def _parse_obj(path: Path) -> tuple[np.ndarray, np.ndarray]:
    verts: list[list[float]] = []
    faces: list[list[int]] = []
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("v "):
                parts = line.split()
                verts.append([float(parts[1]), float(parts[2]), float(parts[3])])
            elif line.startswith("f "):
                idxs = []
                for tok in line.split()[1:]:
                    idxs.append(int(tok.split("/")[0]) - 1)
                if len(idxs) >= 3:
                    for i in range(1, len(idxs) - 1):
                        faces.append([idxs[0], idxs[i], idxs[i + 1]])
    return np.asarray(verts, dtype=np.float64), np.asarray(faces, dtype=np.int32)


def _stage_icons(dst: Path) -> dict[str, str]:
    dst.mkdir(parents=True, exist_ok=True)
    out: dict[str, str] = {}
    for name, res in ICON_RES.items():
        p = fetch_resfile(res, dst / name)
        out[name] = str(p)
        print(f"  icon {name} ← {res}")
    return out


def _stage_textures(dst: Path) -> dict[str, str]:
    dst.mkdir(parents=True, exist_ok=True)
    cache = ROOT / "tools" / "eve_pc" / "_dds_cache"
    written: dict[str, str] = {}
    for key, res in TEX_RES.items():
        dds = fetch_resfile(res, cache / Path(res).name)
        png = dst / f"{key}.png"
        if save_png(dds, png, max_dim=1024):
            written[key] = str(png)
            print(f"  tex {key}.png ← {res}")
        else:
            im = decode_dds(dds)
            if im is None:
                print(f"  tex FAIL {key}")
                continue
            im = im.convert("RGBA")
            if max(im.size) > 1024:
                im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            im.save(png)
            written[key] = str(png)
            print(f"  tex {key}.png (decode) ← {res}")
    return written


def _threeviews(obj: Path, dst: Path) -> dict:
    dst.mkdir(parents=True, exist_ok=True)
    verts, faces = _parse_obj(obj)
    verts = auto_orient(verts, faces)
    views = {}
    for view in ("front", "side", "top"):
        im = render_ortho(verts, faces, view, SIZE)
        path = dst / f"{view}.png"
        im.save(path)
        views[view] = str(path)
    strip = Image.new("RGB", (SIZE * 3 + 24, SIZE + 48), (18, 20, 26))
    draw = ImageDraw.Draw(strip)
    draw.text((8, 8), f"{NAME_ZH} / {NAME_EN} (typeID {TYPE_ID})", fill=(230, 220, 180))
    for i, view in enumerate(("front", "side", "top")):
        im = Image.open(views[view]).convert("RGB")
        strip.paste(im, (8 + i * (SIZE + 4), 36))
        draw.text((8 + i * (SIZE + 4), SIZE + 28), view, fill=(180, 185, 200))
    strip_path = dst / "threeview_strip.png"
    strip.save(strip_path)
    used = np.unique(faces.reshape(-1))
    return {
        "views": views,
        "strip": str(strip_path),
        "verts": int(len(verts)),
        "tris": int(len(faces)),
        "extent": [float(x) for x in np.ptp(verts[used], axis=0)],
    }


def main() -> int:
    print("=== stage_mobile_cyno_beacon_preview ===")
    OUT.mkdir(parents=True, exist_ok=True)
    models = OUT / "models"
    models.mkdir(parents=True, exist_ok=True)
    work = OUT / "_tmp"
    work.mkdir(parents=True, exist_ok=True)

    gr2 = fetch_resfile(GR2_RES, work / "cyb01.gr2")
    print(f"GR2 {gr2} ({gr2.stat().st_size} bytes)")
    obj = work / "cyb01.obj"
    gr2_to_obj(gr2, obj)
    print(f"OBJ {obj} ({obj.stat().st_size} bytes)")

    glb = models / "model.glb"
    assimp_convert(obj, glb, "glb2")
    shutil.copy2(obj, models / "model.obj")
    print(f"GLB {glb} ({glb.stat().st_size} bytes)")

    tex = _stage_textures(models / "tex")
    icons = _stage_icons(OUT / "icons")
    tv = _threeviews(obj, OUT / "models_threeview" / f"01_{NAME_ZH}_{HULL}")

    manifest = {
        "typeID": TYPE_ID,
        "name_zh": NAME_ZH,
        "name_en": NAME_EN,
        "hull": HULL,
        "gr2": GR2_RES,
        "model_glb": str(glb),
        "textures": tex,
        "icons": icons,
        "threeview": tv,
        "sof_material": "uw_structure_02a (from cyb01_vul_active_state.black)",
        "preview_scene": "H:/game_dev/eveautochess-design/tools/visual_preview/scenes/mobile_cyno_beacon_preview.tscn",
    }
    (OUT / "MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    readme = f"""# {NAME_ZH} · 建模确认预览

| 项 | 值 |
|----|----|
| typeID | {TYPE_ID} |
| 英文 | {NAME_EN} |
| Hull | `{HULL}` |
| TQ GR2 | `{GR2_RES}` |
| 网格 | verts={tv['verts']} · tris={tv['tris']} |
| 材质 | SOF `uw_structure_02a_*`（active state black） |

## 双击打开 Godot 预览

[`打开移动式诱导信标预览.bat`](打开移动式诱导信标预览.bat) → 设计仓 `tools/visual_preview` · `res://scenes/mobile_cyno_beacon_preview.tscn`

- WASD 平移 · QE 升降 · 右键环视 · 滚轮远近 · R 复位
- 模型/贴图从本目录 `models/` 直读（无需等 `.import`）
- **禁止**在仓2 `godot_project` 打开此审查预览

## 目录

| 路径 | 内容 |
|------|------|
| `models/model.glb` | 端游壳（legacy 32-bit GR2→OBJ→assimp） |
| `models/tex/` | albedo / normal / roughness / metal / glow |
| `models_threeview/` | front · side · top · strip |
| `icons/` | TQ 物品图标 + isis |

脚本：`eveautochess-dev/tools/stage_mobile_cyno_beacon_preview.py` · 预览 `eveautochess-design/tools/visual_preview/scripts/dev/mobile_cyno_beacon_preview.gd`
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")

    bat = OUT / "打开移动式诱导信标预览.bat"
    bat.write_text(
        "\r\n".join(
            [
                "@echo off",
                "chcp 65001 >nul",
                "setlocal",
                "rem Forward to design-handbook visual_preview (do not launch仓2 godot_project).",
                'call "H:\\game_dev\\eveautochess-design\\tools\\visual_preview\\打开移动式诱导信标预览.bat"',
                "endlocal",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"OK → {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
