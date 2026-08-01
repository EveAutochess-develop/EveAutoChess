# -*- coding: utf-8 -*-
"""Consolidate this-update _review assets + stage racial doomsday VFX + titan GLBs.

Single review folder:
  eveautochess-design/docs/_review/20260731_confirm/

Also writes Godot preview meshes/textures under:
  godot_project/assets/models/preview/titans/
  godot_project/assets/vfx/doomsday/
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
DESIGN = Path(r"H:\game_dev\eveautochess-design")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.dds_decode import save_png  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from stage_mining_threeviews import Gr2Meshes, auto_orient, pick_best_mesh  # noqa: E402

REVIEW_ROOT = DESIGN / "docs" / "_review"
OUT = REVIEW_ROOT / "20260731_confirm"
GODOT = ROOT / "godot_project"
TITAN_GLB = GODOT / "assets" / "models" / "preview" / "titans"
DOOM_TEX = GODOT / "assets" / "vfx" / "doomsday"

# Folders created this update that must live under the single confirm pack.
MIGRATE = (
    "titan_assets_confirm",
    "sleeper_assets_confirm",
    "sleeper_pve_portraits",
    "tonnage_icon_overlays",
)

TITANS = [
    {
        "race": "A",
        "zh": "圣像级",
        "en": "Avatar",
        "weapon_zh": "审判之日",
        "weapon_en": "Judgment",
        "hull": "at1",
        "gr2": [
            "res:/dx9/model/ship/amarr/titan/at1/at1_t1.gr2",
            "res:/dx9/model/ship/amarr/titan/at1/at1_t1_lowdetail.gr2",
        ],
        "stretch": "res:/fisfx/module/doomsday_a_st_t1a.black",
        "color": [1.0, 0.82, 0.28, 1.0],  # EM gold
        "style": "beam_lightning",
        "textures": [
            "res:/texture/sprite/beam8.dds",
            "res:/texture/fx/lightnings/fx_electro_03b.dds",
            "res:/texture/fx/caustics/caustic_16d.dds",
            "res:/texture/fx/gradients/lasergradient_01h.dds",
            "res:/texture/particle/whitesharp2_gradient.dds",
        ],
    },
    {
        "race": "C",
        "zh": "利维坦级",
        "en": "Leviathan",
        "weapon_zh": "湮没之圣光",
        "weapon_en": "Oblivion",
        "hull": "ct1",
        "gr2": [
            "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1.gr2",
            "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1_lowdetail.gr2",
        ],
        "stretch": "res:/fisfx/module/doomsday_c_st_t1a.black",
        "color": [0.35, 0.72, 1.0, 1.0],  # kinetic cyan
        "style": "particle_smoke",
        "textures": [
            "res:/texture/fx/smoke/smoke_atlas_01.dds",
            "res:/texture/fx/caustics/caustic_06.dds",
            "res:/texture/sprite/outburst12.dds",
            "res:/texture/flare/thick_streaks.dds",
            "res:/texture/particle/whitesharp2_gradient.dds",
        ],
    },
    {
        "race": "G",
        "zh": "厄勒布洛斯级",
        "en": "Erebus",
        "weapon_zh": "极光之仪",
        "weapon_en": "Aurora Ominae",
        "hull": "gt1",
        "gr2": [
            "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1_lowdetail.gr2",
            "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1.gr2",
        ],
        "stretch": "res:/fisfx/module/doomsday_g_st_t1a.black",
        "color": [0.35, 1.0, 0.55, 1.0],  # thermal green
        "style": "beam_aurora",
        "textures": [
            "res:/texture/sprite/laser.dds",
            "res:/texture/sprite/beam8.dds",
            "res:/texture/fx/lightnings/lightning5x_h_01.dds",
            "res:/texture/fx/caustics/caustic_07.dds",
            "res:/texture/sprite/sun2.dds",
        ],
    },
    {
        "race": "M",
        "zh": "诸神黄昏级",
        "en": "Ragnarok",
        "weapon_zh": "赫姆达洱之咆哮",
        "weapon_en": "Gjallarhorn",
        "hull": "mt1",
        "gr2": [
            "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1.gr2",
            "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1_lowdetail.gr2",
        ],
        "stretch": "res:/fisfx/module/doomsday_m_st_t1a.black",
        "color": [1.0, 0.42, 0.12, 1.0],  # explosive orange
        "style": "explosion_smoke",
        "textures": [
            "res:/texture/fx/smoke/smoke_atlas_02.dds",
            "res:/texture/sprite/outburst12.dds",
            "res:/texture/fx/caustics/caustic_04.dds",
            "res:/texture/particle/cloudglobe.dds",
            "res:/texture/particle/whitesharphifi.dds",
        ],
    },
]


def _reconfigure_stdio() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass


def consolidate_review() -> list[str]:
    OUT.mkdir(parents=True, exist_ok=True)
    moved: list[str] = []
    for name in MIGRATE:
        src = REVIEW_ROOT / name
        dst = OUT / name
        if dst.exists():
            moved.append(f"keep {name}")
            continue
        if src.exists():
            shutil.move(str(src), str(dst))
            moved.append(f"moved {name}")
            # Leave a stub pointer so old links don't silently vanish.
            stub = REVIEW_ROOT / name
            stub.mkdir(parents=True, exist_ok=True)
            (stub / "MOVED.md").write_text(
                f"已合并到 `docs/_review/20260731_confirm/{name}/`。\n",
                encoding="utf-8",
            )
        else:
            moved.append(f"missing {name}")
    return moved


def write_obj(verts: np.ndarray, faces: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", errors="replace") as f:
        f.write("# titan preview\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for tri in faces:
            f.write(f"f {int(tri[0]) + 1} {int(tri[1]) + 1} {int(tri[2]) + 1}\n")


def export_titan_glb(t: dict) -> dict:
    TITAN_GLB.mkdir(parents=True, exist_ok=True)
    review_mesh = OUT / "doomsday_preview" / "titans" / t["race"]
    review_mesh.mkdir(parents=True, exist_ok=True)
    last_err = ""
    for res in t["gr2"]:
        try:
            gr2 = Path(fetch_resfile(res))
            print(f"[mesh] {t['race']} try {res}")
            g = Gr2Meshes(gr2)
            name, verts, faces = pick_best_mesh(g)
            verts = auto_orient(verts, faces)
            # Normalize long axis ~ 8 units for preview lineup.
            mins = verts.min(axis=0)
            maxs = verts.max(axis=0)
            extent = float(np.max(maxs - mins))
            if extent > 1e-6:
                verts = (verts - (mins + maxs) * 0.5) * (8.0 / extent)
            obj = review_mesh / f"{t['hull']}.obj"
            write_obj(verts, faces, obj)
            glb = TITAN_GLB / f"{t['hull']}.glb"
            assimp_convert(obj, glb, "glb2")
            shutil.copy2(glb, review_mesh / f"{t['hull']}.glb")
            return {
                "race": t["race"],
                "status": "ok",
                "mesh": name,
                "res": res,
                "verts": int(len(verts)),
                "tris": int(len(faces)),
                "glb": str(glb.relative_to(GODOT)).replace("\\", "/"),
            }
        except Exception as e:
            last_err = str(e)
            print(f"  fail {res}: {e}")
    return {"race": t["race"], "status": "fail", "error": last_err}


def extract_textures(t: dict) -> dict:
    race_dir = DOOM_TEX / t["race"].lower()
    review_dir = OUT / "doomsday_preview" / "textures" / t["race"].lower()
    race_dir.mkdir(parents=True, exist_ok=True)
    review_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for res in t["textures"]:
        stem = Path(res.replace("\\", "/").split("/")[-1]).stem
        try:
            src = Path(fetch_resfile(res))
            dst = race_dir / f"{stem}.png"
            ok = save_png(src, dst, max_dim=1024)
            if ok:
                shutil.copy2(dst, review_dir / f"{stem}.png")
                written.append(stem)
            else:
                print(f"  dds decode fail {res}")
        except Exception as e:
            print(f"  tex fail {res}: {e}")
    # Also stash the stretch black for reference.
    try:
        black = Path(fetch_resfile(t["stretch"]))
        shutil.copy2(black, review_dir / Path(t["stretch"]).name)
    except Exception as e:
        print(f"  black copy fail: {e}")
    return {"race": t["race"], "textures": written, "style": t["style"], "color": t["color"]}


def write_manifest(mesh_reports: list, tex_reports: list, moved: list[str]) -> None:
    doom = OUT / "doomsday_preview"
    doom.mkdir(parents=True, exist_ok=True)
    manifest = {
        "pack": "20260731_confirm",
        "migrated": moved,
        "titans": mesh_reports,
        "doomsday": tex_reports,
        "godot_scene": "res://scenes/doomsday_titan_preview.tscn",
        "note": "Four racial doomsday stretch FX textures from TQ fisfx; Godot preview approximates EveStretch with racial materials.",
    }
    (doom / "MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (DOOM_TEX / "races.json").write_text(
        json.dumps(
            {
                t["race"]: {
                    "zh": t["zh"],
                    "en": t["en"],
                    "weapon_zh": t["weapon_zh"],
                    "weapon_en": t["weapon_en"],
                    "hull": t["hull"],
                    "color": t["color"],
                    "style": t["style"],
                    "stretch_black": t["stretch"],
                }
                for t in TITANS
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    lines = [
        "# 2026-07-31 确认包（单一文件夹）",
        "",
        "> 本次更新预览确认素材集中于此，不再拆多个 `*_confirm` 顶层目录。",
        "",
        "## 内容",
        "",
        "| 子目录 | 内容 |",
        "|--------|------|",
        "| `titan_assets_confirm/` | 四族泰坦图标 + 三视图 |",
        "| `sleeper_assets_confirm/` | 冬眠者立绘/三视图/武器音效 |",
        "| `sleeper_pve_portraits/` | PVE 立绘索引 |",
        "| `tonnage_icon_overlays/` | 吨位角标/底图 |",
        "| `doomsday_preview/` | 四族末日贴图 + 泰坦 GLB + 预览截图 |",
        "",
        "## 末日特效预览",
        "",
        "Godot 场景：`eveautochess-dev/godot_project/scenes/doomsday_titan_preview.tscn`",
        "",
        "四泰坦并列，共同对准中央陨石，循环播放各族末日（审判之日 / 湮没之圣光 / 极光之仪 / 赫姆达洱之咆哮）。",
        "贴图来自 TQ `res:/fisfx/module/doomsday_{a|c|g|m}_st_t1a.black` 引用的 DDS。",
        "",
    ]
    for t, mr in zip(TITANS, mesh_reports):
        st = mr.get("status")
        lines.append(
            f"- **{t['race']} {t['zh']} / {t['en']}** · {t['weapon_zh']} ({t['weapon_en']}) · mesh `{st}`"
        )
    lines.append("")
    (OUT / "README.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    _reconfigure_stdio()
    print("=== consolidate _review ===")
    moved = consolidate_review()
    for m in moved:
        print(" ", m)

    mesh_reports = []
    tex_reports = []
    print("=== titan glb ===")
    for t in TITANS:
        mesh_reports.append(export_titan_glb(t))
    print("=== doomsday textures ===")
    for t in TITANS:
        print(f"[tex] {t['race']}")
        tex_reports.append(extract_textures(t))

    write_manifest(mesh_reports, tex_reports, moved)
    print(f"done -> {OUT}")


if __name__ == "__main__":
    main()
