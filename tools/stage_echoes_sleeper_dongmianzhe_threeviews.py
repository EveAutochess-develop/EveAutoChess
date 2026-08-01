# -*- coding: utf-8 -*-
"""Convert Echoes sleeper_props dongmianzhe_01..07 to threeviews for hub matching."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from stage_mining_threeviews import auto_orient, render_ortho, SIZE  # noqa: E402

NEOX = Path(
    r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\converter.py"
)
PROPS = Path(r"H:\eve手游\history\asset_library\entities\sleeper_props")
OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\sleeper_assets_confirm\echoes_dongmianzhe_threeview"
)
PORTRAIT_DIR = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\sleeper_assets_confirm\echoes_portraits_bilingual"
)


def load_obj(path: Path) -> tuple[np.ndarray, np.ndarray]:
    verts: list[list[float]] = []
    faces: list[list[int]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("v "):
            parts = line.split()
            verts.append([float(parts[1]), float(parts[2]), float(parts[3])])
        elif line.startswith("f "):
            idx = []
            for tok in line.split()[1:]:
                idx.append(int(tok.split("/")[0]) - 1)
            if len(idx) >= 3:
                for i in range(1, len(idx) - 1):
                    faces.append([idx[0], idx[i], idx[i + 1]])
    return np.asarray(verts, dtype=np.float64), np.asarray(faces, dtype=np.int32)


def convert_one(stem: str) -> dict:
    mesh = PROPS / stem / "mesh" / f"{stem}_lod1.mesh"
    if not mesh.is_file():
        mesh = PROPS / stem / "mesh" / f"{stem}_lod0.mesh"
    if not mesh.is_file():
        return {"stem": stem, "status": "miss", "error": "no mesh"}
    dest = OUT / stem
    dest.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="neox_dm_") as td:
        td_path = Path(td)
        tmp = td_path / mesh.name
        shutil.copy2(mesh, tmp)
        try:
            subprocess.run(
                [sys.executable, str(NEOX), "--mode", "obj", str(tmp)],
                check=True,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except Exception as e:  # noqa: BLE001
            return {"stem": stem, "status": "neox_fail", "error": str(e)}
        objs = list(td_path.rglob("*.obj"))
        if not objs:
            return {"stem": stem, "status": "no_obj"}
        obj = objs[0]
        shutil.copy2(obj, dest / f"{stem}.obj")
        glb = dest / f"{stem}.glb"
        try:
            assimp_convert(obj, glb, "glb2")
        except Exception as e:  # noqa: BLE001
            return {"stem": stem, "status": "assimp_fail", "error": str(e)}
        verts, faces = load_obj(obj)
        if len(verts) < 8 or len(faces) < 8:
            return {"stem": stem, "status": "empty_geo", "verts": int(len(verts))}
        verts = auto_orient(verts, faces)
        views = {}
        for view in ("front", "side", "top"):
            img = render_ortho(verts, faces, view, size=SIZE)
            img.save(dest / f"{view}.png")
            views[view] = f"{view}.png"
        # strip
        imgs = [Image.open(dest / f"{v}.png").convert("RGB") for v in ("front", "side", "top")]
        strip = Image.new("RGB", (SIZE * 3, SIZE), (12, 14, 20))
        for i, im in enumerate(imgs):
            strip.paste(im, (i * SIZE, 0))
        strip.save(dest / "strip.png")
        return {
            "stem": stem,
            "status": "ok",
            "verts": int(len(verts)),
            "tris": int(len(faces)),
            "glb": str(glb),
            "views": views,
            "src": str(mesh),
        }


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)
    # copy hub portrait for side-by-side
    for p in PORTRAIT_DIR.glob("*10701003210*"):
        shutil.copy2(p, OUT / "hub_portrait_10701003210.png")
        break
    reports = []
    for i in range(1, 8):
        stem = f"dongmianzhe_{i:02d}"
        print("==", stem)
        r = convert_one(stem)
        reports.append(r)
        print(r)
    (OUT / "REPORT.json").write_text(
        json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    lines = [
        "# Echoes `sleeper_props` · dongmianzhe_01..07",
        "",
        "来源：`H:\\eve手游\\history\\asset_library\\entities\\sleeper_props\\`",
        "用途：对照手游立绘「冬眠者交互枢纽」`10701003210`（本目录 `hub_portrait_10701003210.png`）。",
        "端游 TQ **无** Interlink Hub 同形壳；这七套是目前唯一可用的原生冬眠者结构 mesh 候选。",
        "",
        "| 键 | 状态 | verts | tris |",
        "|----|------|------|------|",
    ]
    for r in reports:
        lines.append(
            f"| `{r.get('stem')}` | {r.get('status')} | {r.get('verts','')} | {r.get('tris','')} |"
        )
    lines += [
        "",
        "请人工对照立绘，标出哪一枚是中枢（以及其余是否对应包体/尸棺/工程站等）。",
        "",
    ]
    (OUT / "README.md").write_text("\n".join(lines), encoding="utf-8")
    ok = sum(1 for r in reports if r.get("status") == "ok")
    print(f"done ok={ok}/{len(reports)} -> {OUT}")


if __name__ == "__main__":
    main()
