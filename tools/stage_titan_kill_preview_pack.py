# -*- coding: utf-8 -*-
"""Stage titan WRECK meshes + copy racial kill FX blacks/textures.

Rule: if GR2/decode fails → leave empty. Do NOT stand in with icons/fragments/fake FX.
Does NOT touch doomsday VFX / doomsday_titan_preview.
"""
from __future__ import annotations

import json
import shutil
import sys
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

OUT = DESIGN / "docs" / "_review" / "20260731_confirm" / "titan_kill_preview"
GODOT = ROOT / "godot_project"
WRECK_GLB = GODOT / "assets" / "models" / "preview" / "titans" / "wreck"
KILL_TEX = GODOT / "assets" / "vfx" / "titan_kill"

TITANS = [
    {
        "race": "A",
        "hull": "at1",
        "zh": "圣像级",
        "en": "Avatar",
        "faction": "amarr",
        "wreck": [
            "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck.gr2",
        ],
        "fragment": "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck_fragment_01_lowdetail.gr2",
        "cloud_black": "res:/dx9/model/ship/amarr/titan/at1/wreck/at1_t1_wreck_cloud.black",
        "kill_black": "res:/fisfx/explosion/ecx_titan_amarr_explosive_01a.black",
        "color": [1.0, 0.82, 0.28, 1.0],
    },
    {
        "race": "C",
        "hull": "ct1",
        "zh": "利维坦级",
        "en": "Leviathan",
        "faction": "caldari",
        "wreck": [
            "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck.gr2",
        ],
        "fragment": "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck_fragment_01_lowdetail.gr2",
        "cloud_black": "res:/dx9/model/ship/caldari/titan/ct1/wreck/ct1_t1_wreck_cloud.black",
        "kill_black": "res:/fisfx/explosion/ecx_titan_caldari_explosive_01a.black",
        "color": [0.35, 0.72, 1.0, 1.0],
    },
    {
        "race": "G",
        "hull": "gt1",
        "zh": "厄勒布洛斯级",
        "en": "Erebus",
        "faction": "gallente",
        "wreck": [
            "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck.gr2",
        ],
        "fragment": "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck_fragment_01_lowdetail.gr2",
        "cloud_black": "res:/dx9/model/ship/gallente/titan/gt1/wreck/gt1_t1_wreck_cloud.black",
        "kill_black": "res:/fisfx/explosion/ecx_titan_gallente_explosive_01a.black",
        "color": [0.35, 1.0, 0.55, 1.0],
    },
    {
        "race": "M",
        "hull": "mt1",
        "zh": "诸神黄昏级",
        "en": "Ragnarok",
        "faction": "minmatar",
        "wreck": [
            "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck_lowdetail.gr2",
            "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck.gr2",
        ],
        "fragment": "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck_fragment_01_lowdetail.gr2",
        "cloud_black": "res:/dx9/model/ship/minmatar/titan/mt1/wreck/mt1_t1_wreck_cloud.black",
        "kill_black": "res:/fisfx/explosion/ecx_titan_minmatar_explosive_01a.black",
        "color": [1.0, 0.42, 0.12, 1.0],
    },
]

# Shared death-explosion textures referenced by ecx_titan_* blacks.
SHARED_TEX = [
    "res:/texture/fx/fire/firetile_04a.dds",
    "res:/texture/fx/fire/firetile_05a.dds",
    "res:/texture/fx/fire/fireshape_01a.dds",
    "res:/texture/fx/gradients/deathexplosion_01a.dds",
    "res:/texture/fx/gradients/deathexplosion_01b.dds",
    "res:/texture/fx/gradients/deathexplosion_01bw.dds",
    "res:/texture/fx/gradients/vertical_plasma_01a.dds",
    "res:/texture/fx/motionparticles/mparticleexplosion_01b.dds",
    "res:/texture/fx/motionparticles/mparticle_05a.dds",
    "res:/texture/fx/debris/debris_01_d.dds",
    "res:/texture/particle/cloudglobe.dds",
    "res:/texture/particle/whiteglobe.dds",
    "res:/fisfx/explosion/fire/wreckfire_generic_15000.black",
]


def _reconfigure() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass


def write_obj(verts: np.ndarray, faces: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", errors="replace") as f:
        f.write("# titan wreck\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for tri in faces:
            f.write(f"f {int(tri[0]) + 1} {int(tri[1]) + 1} {int(tri[2]) + 1}\n")


def export_wreck(t: dict) -> dict:
    WRECK_GLB.mkdir(parents=True, exist_ok=True)
    review = OUT / "wrecks" / t["race"]
    review.mkdir(parents=True, exist_ok=True)
    last = ""
    for res in t["wreck"]:
        try:
            print(f"[wreck] {t['race']} try {res}")
            g = Gr2Meshes(Path(fetch_resfile(res)))
            name, verts, faces = pick_best_mesh(g)
            verts = auto_orient(verts, faces)
            mins, maxs = verts.min(0), verts.max(0)
            extent = float(np.max(maxs - mins))
            if extent > 1e-6:
                verts = (verts - (mins + maxs) * 0.5) * (8.0 / extent)
            obj = review / f"{t['hull']}_wreck.obj"
            write_obj(verts, faces, obj)
            glb = WRECK_GLB / f"{t['hull']}.glb"
            assimp_convert(obj, glb, "glb2")
            shutil.copy2(glb, review / f"{t['hull']}.glb")
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
            last = str(e)
            print(f"  fail: {e}")
    return {"race": t["race"], "status": "fail", "error": last}


def copy_blacks(t: dict) -> None:
    race_dir = OUT / "kill_fx" / t["race"].lower()
    race_dir.mkdir(parents=True, exist_ok=True)
    godot_race = KILL_TEX / t["race"].lower()
    godot_race.mkdir(parents=True, exist_ok=True)
    for key in ("kill_black", "cloud_black"):
        res = t[key]
        try:
            src = Path(fetch_resfile(res))
            name = Path(res).name
            shutil.copy2(src, race_dir / name)
            shutil.copy2(src, godot_race / name)
        except Exception as e:
            print(f"  black fail {res}: {e}")


def extract_shared() -> list[str]:
    shared_out = KILL_TEX / "shared"
    review = OUT / "kill_fx" / "shared"
    shared_out.mkdir(parents=True, exist_ok=True)
    review.mkdir(parents=True, exist_ok=True)
    written = []
    for res in SHARED_TEX:
        stem = Path(res.replace("\\", "/").split("/")[-1])
        try:
            src = Path(fetch_resfile(res))
            if stem.suffix.lower() == ".black":
                shutil.copy2(src, shared_out / stem.name)
                shutil.copy2(src, review / stem.name)
                written.append(stem.name)
            else:
                dst = shared_out / f"{stem.stem}.png"
                if save_png(src, dst, max_dim=1024):
                    shutil.copy2(dst, review / dst.name)
                    written.append(dst.stem)
                else:
                    print(f"  decode fail {res}")
        except Exception as e:
            print(f"  shared fail {res}: {e}")
    return written


def write_readme(wreck_reports: list, shared: list[str]) -> None:
    races = {
        t["race"]: {
            "zh": t["zh"],
            "en": t["en"],
            "hull": t["hull"],
            "kill_black": t["kill_black"],
            "wreck": t["wreck"][0],
            "color": t["color"],
        }
        for t in TITANS
    }
    (KILL_TEX / "races.json").write_text(
        json.dumps(races, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    manifest = {
        "pack": "titan_kill_preview",
        "note": "Parallel to doomsday_preview — do not overwrite doomsday assets.",
        "godot_scene": "res://scenes/titan_kill_preview.tscn",
        "wrecks": wreck_reports,
        "shared_textures": shared,
        "park_slot": "MapEnv player_citadel / former 空堡 seat (board bottom)",
    }
    (OUT / "MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    lines = [
        "# 泰坦残骸 + 击毁特效确认 · titan_kill_preview",
        "",
        "> 与 `doomsday_preview` **并行独立**；勿改末日贴图/末日预览场景。",
        "",
        "## TQ 入口",
        "",
        "| 族 | 击毁爆炸 | 残骸 GR2 |",
        "|----|----------|----------|",
    ]
    for t in TITANS:
        lines.append(
            f"| {t['race']} {t['zh']} | `{t['kill_black']}` | `{t['wreck'][0]}` |"
        )
    lines += [
        "",
        "## Godot 预览",
        "",
        "`res://scenes/titan_kill_preview.tscn` — 四族一字排开：完好 **2s** → 爆炸 → 残骸 → 循环。",
        "",
        f"停泊口径：负安局泰坦最终停在棋盘下方原玩家空堡位（见 MULTIPLAYER_PVP §2.5）。",
        "",
    ]
    for r in wreck_reports:
        lines.append(f"- wreck {r['race']}: `{r.get('status')}` {r.get('glb', r.get('error', ''))}")
    lines.append("")
    (OUT / "README.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    _reconfigure()
    OUT.mkdir(parents=True, exist_ok=True)
    print("=== shared kill textures ===")
    shared = extract_shared()
    print("=== wrecks ===")
    wreck_reports = []
    for t in TITANS:
        wreck_reports.append(export_wreck(t))
        copy_blacks(t)
    write_readme(wreck_reports, shared)
    # Point parent README
    parent = OUT.parent / "README.md"
    if parent.is_file():
        text = parent.read_text(encoding="utf-8")
        if "titan_kill_preview" not in text:
            text = text.replace(
                "| `doomsday_preview/` | 四族末日贴图 + 泰坦 GLB + 预览截图 |",
                "| `doomsday_preview/` | 四族末日贴图 + 泰坦 GLB + 预览截图 |\n"
                "| `titan_kill_preview/` | 残骸建模 + 各族击毁爆炸贴图 + 击毁循环预览 |",
            )
            parent.write_text(text, encoding="utf-8")
    print(f"done -> {OUT}")


if __name__ == "__main__":
    main()
