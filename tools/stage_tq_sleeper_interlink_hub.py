# -*- coding: utf-8 -*-
"""Stage TQ Sleeper Interlink Hub mesh (graphic 3519 = sl_station01_v3).

CCP type 30275/30302 Interlink Hub uses graphic_id 3519, which is the
battlestation variant sl_station01_v3 — not a separate jellyfish hull.
Echoes portrait 10701003210 is a mobile redesign; no matching NeoX mesh
exists in current unpacks.
"""
from __future__ import annotations

import json
import shutil
import struct
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
from reexport_titan_glb_with_uv import MultiSectionGr2, write_obj  # noqa: E402
from stage_mining_threeviews import auto_orient, pick_best_mesh, render_ortho, SIZE, Gr2Meshes  # noqa: E402

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\sleeper_assets_confirm\tq_hub_interlink"
)
PORTRAIT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\sleeper_assets_confirm\echoes_portraits_bilingual"
)

# graphic_id → battlestation variant (icon folder number matches graphic id)
VARIANTS = [
    {
        "key": "sl_station01_v3",
        "role": "Interlink Hub",
        "type_ids": [30275, 30302],
        "graphic_id": 3519,
        "gr2": "res:/dx9/model/structure/sleeper/battlestation/sl_station01/sl_station01_v3/sl_station01_v3.gr2",
        "icon": "res:/dx9/model/structure/sleeper/battlestation/sl_station01/sl_station01_v3/icons/3519_512.jpg",
        "is_hub": True,
    },
    {
        "key": "sl_station01_v1",
        "role": "Abandoned Sleeper Enclave (likely)",
        "type_ids": [30273],
        "graphic_id": 3517,
        "gr2": "res:/dx9/model/structure/sleeper/battlestation/sl_station01/sl_station01_v1/sl_station01_v1_lowdetail.gr2",
        "icon": "res:/dx9/model/structure/sleeper/battlestation/sl_station01/sl_station01_v1/icons/3517_512.jpg",
        "is_hub": False,
    },
    {
        "key": "sl_station01_v5",
        "role": "Multiplex Forwarder (likely)",
        "type_ids": [30301, 30277],
        "graphic_id": 3521,
        "gr2": "res:/dx9/model/structure/sleeper/battlestation/sl_station01/sl_station01_v5/sl_station01_v5_lowdetail.gr2",
        "icon": "res:/dx9/model/structure/sleeper/battlestation/sl_station01/sl_station01_v5/icons/3521_512.jpg",
        "is_hub": False,
    },
]


def extract_mesh(gr2_res: str):
    path = Path(fetch_resfile(gr2_res))
    # Prefer MultiSectionGr2 (handles 32/64); fall back to Gr2Meshes helper.
    try:
        g = MultiSectionGr2(path)
        from reexport_titan_glb_with_uv import _extract_best

        verts, faces, uvs, stride, uv_off = _extract_best(g)
        return verts, faces, {"method": "MultiSectionGr2", "stride": stride, "uv_off": uv_off}
    except Exception as e1:  # noqa: BLE001
        gm = Gr2Meshes(path)
        name, verts, faces = pick_best_mesh(gm)
        return verts, faces, {"method": "Gr2Meshes", "mesh": name, "fallback_err": str(e1)}


def stage_one(spec: dict) -> dict:
    dest = OUT / spec["key"]
    dest.mkdir(parents=True, exist_ok=True)
    report = {"key": spec["key"], "role": spec["role"], "graphic_id": spec["graphic_id"]}
    try:
        icon = Path(fetch_resfile(spec["icon"]))
        shutil.copy2(icon, dest / "tq_icon_512.jpg")
        report["icon"] = "tq_icon_512.jpg"
    except Exception as e:  # noqa: BLE001
        report["icon_err"] = str(e)
    try:
        verts, faces, meta = extract_mesh(spec["gr2"])
        verts = auto_orient(verts, faces)
        report.update(meta)
        report["verts"] = int(len(verts))
        report["tris"] = int(len(faces))
        obj = dest / f"{spec['key']}.obj"
        write_obj(verts, faces, np.zeros((len(verts), 2)), obj)
        glb = dest / f"{spec['key']}.glb"
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
    except Exception as e:  # noqa: BLE001
        report["status"] = "fail"
        report["error"] = str(e)
    return report


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)
    for p in PORTRAIT.glob("*10701003210*"):
        shutil.copy2(p, OUT / "echoes_hub_portrait_10701003210.png")
        break
    reports = []
    for spec in VARIANTS:
        print("==", spec["key"], spec["role"])
        r = stage_one(spec)
        reports.append(r)
        print(r)
    (OUT / "REPORT.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [
        "# TQ 冬眠者交互枢纽（Interlink Hub）",
        "",
        "## 结论",
        "",
        "- 端游 type **30275 / 30302**「Sleeper Interlink Hub」的 `graphic_id=3519`。",
        "- 该 graphic **就是** `structure/sleeper/battlestation/sl_station01/sl_station01_v3`（圆盘战斗站变体），不是独立水母壳。",
        "- 手游立绘 `10701003210`（水母+触须）是 **Echoes 重绘**；当前解包 **没有** 同形 NeoX mesh。",
        "- PVE「中枢」若要 **3D 壳**：用本目录 `sl_station01_v3`（端游权威同 graphic）。",
        "- 若必须用水母外形：只能立绘/图标，或再解更高版本 Echoes。",
        "",
        "## 本目录",
        "",
        "| 键 | 角色 | graphic | 状态 |",
        "|----|------|---------|------|",
    ]
    for r in reports:
        lines.append(
            f"| `{r.get('key')}` | {r.get('role')} | {r.get('graphic_id')} | {r.get('status')} |"
        )
    lines += [
        "",
        "`echoes_hub_portrait_10701003210.png` = 手游立绘对照。",
        "",
    ]
    (OUT / "README.md").write_text("\n".join(lines), encoding="utf-8")
    print("done", OUT)


if __name__ == "__main__":
    main()
