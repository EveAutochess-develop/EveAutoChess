# -*- coding: utf-8 -*-
"""Extract TQ ship iconbackground assets for 512 portrait cutout research.

Source: res:/dx9/scene/iconbackground/
512 icons are rendered against racial cubemap environments (not a flat nebula paste).
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools" / "eve_pc")]
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\titan_assets_confirm\iconbackground_for_cutout"
)

RACES = {
    "minmatar": "ship_minmatar_cube",
    "amarr": "ship_amarr_cube",
    "caldari": "ship_caldari_cube",
    "gallente": "ship_gallente_cube",
    "other": "ship_other_cube",
}

BLACKS = ["minmatar", "amarr", "caldari", "gallente", "angel", "sleeper", "generic"]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    report: dict = {"source": "res:/dx9/scene/iconbackground/", "races": {}}

    for race, stem in RACES.items():
        rdir = OUT / race
        rdir.mkdir(exist_ok=True)
        entry = {"stem": stem, "files": {}}
        for suf, tag in ((".dds", "cube0"), ("_blur.dds", "blur"), ("_refl.dds", "refl")):
            res = f"res:/dx9/scene/iconbackground/{stem}{suf}"
            src = Path(fetch_resfile(res))
            dst_dds = rdir / f"{tag}.dds"
            shutil.copy2(src, dst_dds)
            im = Image.open(src).convert("RGBA")
            png = rdir / f"{tag}_pillow.png"
            im.save(png)
            mean = np.asarray(im.convert("RGB")).mean(axis=(0, 1)).astype(int).tolist()
            entry["files"][tag] = {
                "res": res,
                "png": str(png.relative_to(OUT)).replace("\\", "/"),
                "size": list(im.size),
                "mean_rgb": mean,
            }
            print(race, tag, im.size, mean)
        report["races"][race] = entry

    for race in BLACKS:
        res = f"res:/dx9/scene/iconbackground/{race}.black"
        try:
            src = Path(fetch_resfile(res))
        except Exception as e:
            print("skip black", race, e)
            continue
        (OUT / f"{race}.black").write_bytes(src.read_bytes())

    fade_res = "res:/ui/texture/classes/cosmetics/ship/nebula_bg_fade.png"
    fade = Path(fetch_resfile(fade_res))
    Image.open(fade).save(OUT / "nebula_bg_fade.png")

    (OUT / "README.md").write_text(
        "\n".join(
            [
                "# TQ 舰船图标星云底（iconbackground）",
                "",
                "来源：`res:/dx9/scene/iconbackground/`",
                "",
                "| 族场景 `.black` | 立方体环境贴图 |",
                "|-----------------|----------------|",
                "| `minmatar.black` / `angel.black` | `ship_minmatar_cube.dds` |",
                "| `amarr.black` | `ship_amarr_cube.dds` |",
                "| `caldari.black` | `ship_caldari_cube.dds` |",
                "| `gallente.black` | `ship_gallente_cube.dds` |",
                "",
                "每个 `.black` 还引用 `*_cube_refl.dds`、`*_cube_blur.dds`、`background.fx`。",
                "",
                "## 重要",
                "",
                "`*_512.jpg` 立绘是客户端 **对着立方体环境渲染** 的结果，不是把某张 2D 星云原图直接垫在背后。",
                "",
                "本目录：",
                "- `*/cube0_pillow.png` — 立方体 Pillow 可读出的第 0 面（全六面 BC7_SRGB 需专用解码）",
                "- `*/blur_pillow.png` / `*/refl_pillow.png` — 模糊/反射辅助（blur 均值更接近立绘星云色）",
                "- 各族 `*.black`",
                "- `nebula_bg_fade.png`（UI cosmetics，未必是图标渲染底）",
                "",
                "差分抠图可拿 blur 上采样作粗背景估计；生产透明图标仍优先 ISIS。",
                "",
                "提取：`eveautochess-dev/tools/extract_iconbackground_cubes.py`",
                "",
            ]
        ),
        encoding="utf-8",
    )
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
