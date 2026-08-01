# -*- coding: utf-8 -*-
"""Stage CMAG racial freighters (TQ) for PVE salvage rescue targets.

Order: Caldari Charon → Minmatar Fenrir → Amarr Providence → Gallente Obelisk.
Echoes display names (权威): 渡神级 / 芬利厄级 / 普罗维登斯级 / 方尖塔级.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from reexport_titan_glb_with_uv import MultiSectionGr2, _extract_best, write_obj  # noqa: E402
from stage_mining_threeviews import auto_orient, render_ortho, SIZE  # noqa: E402

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\sleeper_assets_confirm\freighter_rescue_cmag"
)

# CMAG order — Echoes name 权威
FREIGHTERS = [
    {
        "cmag": "C",
        "race_zh": "加达里",
        "name_zh": "渡神级",
        "name_en": "Charon",
        "hull": "cfr1",
        "tq_type_id": 20185,
        "echoes_type_id": "10705000101",
        "gr2": "res:/dx9/model/ship/caldari/freighter/cfr1/cfr1_t1.gr2",
        "icon": "res:/dx9/model/ship/caldari/freighter/cfr1/icons/2740_512.jpg",
    },
    {
        "cmag": "M",
        "race_zh": "米玛塔尔",
        "name_zh": "芬利厄级",
        "name_en": "Fenrir",
        "hull": "mfr1",
        "tq_type_id": 20189,
        "echoes_type_id": "10705000201",
        "gr2": "res:/dx9/model/ship/minmatar/freighter/mfr1/mfr1_t1.gr2",
        "icon": "res:/dx9/model/ship/minmatar/freighter/mfr1/icons/2737_512.jpg",
    },
    {
        "cmag": "A",
        "race_zh": "艾玛",
        "name_zh": "普罗维登斯级",
        "name_en": "Providence",
        "hull": "afr1",
        "tq_type_id": 20183,
        "echoes_type_id": "10705000301",
        "gr2": "res:/dx9/model/ship/amarr/freighter/afr1/afr1_t1.gr2",
        "icon": "res:/dx9/model/ship/amarr/freighter/afr1/icons/2738_512.jpg",
    },
    {
        "cmag": "G",
        "race_zh": "盖伦特",
        "name_zh": "方尖塔级",
        "name_en": "Obelisk",
        "hull": "gfr1",
        "tq_type_id": 20187,
        "echoes_type_id": "10705000401",
        "gr2": "res:/dx9/model/ship/gallente/freighter/gfr1/gfr1_t1.gr2",
        "icon": "res:/dx9/model/ship/gallente/freighter/gfr1/icons/2739_512.jpg",
    },
]


def export_one(spec: dict) -> dict:
    stem = f"{spec['cmag']}_{spec['hull']}_{spec['name_zh']}_{spec['name_en']}"
    dest = OUT / stem
    dest.mkdir(parents=True, exist_ok=True)
    report = {**{k: spec[k] for k in ("cmag", "race_zh", "name_zh", "name_en", "hull", "tq_type_id", "echoes_type_id")}}
    try:
        icon = Path(fetch_resfile(spec["icon"]))
        shutil.copy2(icon, dest / "tq_icon_512.jpg")
        report["icon"] = "tq_icon_512.jpg"
    except Exception as e:  # noqa: BLE001
        report["icon_err"] = str(e)
    try:
        g = MultiSectionGr2(Path(fetch_resfile(spec["gr2"])))
        verts, faces, uvs, stride, uv_off = _extract_best(g)
        verts = auto_orient(verts, faces)
        report.update({"stride": stride, "uv_off": uv_off, "verts": int(len(verts)), "tris": int(len(faces))})
        obj = dest / f"{spec['hull']}.obj"
        write_obj(verts, faces, uvs if uv_off >= 0 else np.zeros((len(verts), 2)), obj)
        glb = dest / f"{spec['hull']}.glb"
        assimp_convert(obj, glb, "glb2")
        obj.unlink(missing_ok=True)
        for view in ("front", "side", "top"):
            render_ortho(verts, faces, view, size=SIZE).save(dest / f"{view}.png")
        imgs = [Image.open(dest / f"{v}.png").convert("RGB") for v in ("front", "side", "top")]
        strip = Image.new("RGB", (SIZE * 3, SIZE), (12, 14, 20))
        for i, im in enumerate(imgs):
            strip.paste(im, (i * SIZE, 0))
        strip.save(dest / "strip.png")
        report["status"] = "ok"
        report["glb"] = glb.name
        report["gr2"] = spec["gr2"]
    except Exception as e:  # noqa: BLE001
        report["status"] = "fail"
        report["error"] = str(e)
    return report


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)
    reports = []
    for spec in FREIGHTERS:
        print("==", spec["cmag"], spec["name_zh"], spec["name_en"])
        r = export_one(spec)
        reports.append(r)
        print(r)
    (OUT / "REPORT.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [
        "# 四族货舰 · 抢救 PVE 目标（CMAG）",
        "",
        "用途：`pve_salvage` 抢救对象（非中枢代泰坦）。模型与数值取自端游 TQ。",
        "中文名：Echoes 手游译名权威。",
        "",
        "| 序 | CMAG | ZH | EN | TQ type | Echoes type | 壳 |",
        "|----|------|----|----|---------|-------------|-----|",
    ]
    for i, s in enumerate(FREIGHTERS, 1):
        lines.append(
            f"| {i} | {s['cmag']} | {s['name_zh']} | {s['name_en']} | {s['tq_type_id']} | `{s['echoes_type_id']}` | `{s['hull']}` |"
        )
    lines += [
        "",
        "数值：见同级 `../FREIGHTER_STATS_TQ.json` / `../FREIGHTER_STATS.md`。",
        "权威流程：[`MULTIPLAYER_MATCH_FLOW.md`](../../../../MULTIPLAYER_MATCH_FLOW.md) §5.1.1。",
        "",
    ]
    (OUT / "README.md").write_text("\n".join(lines), encoding="utf-8")
    ok = sum(1 for r in reports if r.get("status") == "ok")
    print(f"done ok={ok}/{len(reports)} -> {OUT}")


if __name__ == "__main__":
    main()
