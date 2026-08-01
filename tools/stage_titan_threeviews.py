# -*- coding: utf-8 -*-
"""Stage TQ empire Titan icons (prefer transparent) + orthographic three-views.

Output: eveautochess-design/docs/_review/20260731_confirm/titan_assets_confirm/
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
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from stage_mining_threeviews import (  # noqa: E402
    Gr2Meshes,
    auto_orient,
    pick_best_mesh,
    render_ortho,
    SIZE,
)

OUT = Path(r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\titan_assets_confirm")

# Four empire titans used by MULTIPLAYER_PVP §2 (+ Angel optional at end).
TITANS = [
    {
        "stem": "01_A_圣像级_Avatar",
        "race": "A",
        "zh": "圣像级",
        "en": "Avatar",
        "faction": "amarr",
        "hull": "at1",
        "gr2": "res:/dx9/model/ship/amarr/titan/at1/at1_t1.gr2",
        "isis": "res:/dx9/model/ship/amarr/titan/at1/icons/at1_t1_isis.png",
        "png128": "res:/dx9/model/ship/amarr/titan/at1/icons/2910_128.png",
        "png64": "res:/dx9/model/ship/amarr/titan/at1/icons/2910_64.png",
        "jpg512": "res:/dx9/model/ship/amarr/titan/at1/icons/2910_512.jpg",
    },
    {
        "stem": "02_C_利维坦级_Leviathan",
        "race": "C",
        "zh": "利维坦级",
        "en": "Leviathan",
        "faction": "caldari",
        "hull": "ct1",
        "gr2": "res:/dx9/model/ship/caldari/titan/ct1/ct1_t1.gr2",
        "isis": "res:/dx9/model/ship/caldari/titan/ct1/icons/ct1_t1_isis.png",
        "png128": "res:/dx9/model/ship/caldari/titan/ct1/icons/2930_128.png",
        "png64": "res:/dx9/model/ship/caldari/titan/ct1/icons/2930_64.png",
        "jpg512": "res:/dx9/model/ship/caldari/titan/ct1/icons/2930_512.jpg",
    },
    {
        "stem": "03_G_厄勒布洛斯级_Erebus",
        "race": "G",
        "zh": "厄勒布洛斯级",
        "en": "Erebus",
        "faction": "gallente",
        "hull": "gt1",
        "gr2": "res:/dx9/model/ship/gallente/titan/gt1/gt1_t1.gr2",
        "isis": "res:/dx9/model/ship/gallente/titan/gt1/icons/gt1_t1_isis.png",
        "png128": "res:/dx9/model/ship/gallente/titan/gt1/icons/2942_128.png",
        "png64": "res:/dx9/model/ship/gallente/titan/gt1/icons/2942_64.png",
        "jpg512": "res:/dx9/model/ship/gallente/titan/gt1/icons/2942_512.jpg",
    },
    {
        "stem": "04_M_诸神黄昏级_Ragnarok",
        "race": "M",
        "zh": "诸神黄昏级",
        "en": "Ragnarok",
        "faction": "minmatar",
        "hull": "mt1",
        "gr2": "res:/dx9/model/ship/minmatar/titan/mt1/mt1_t1.gr2",
        "isis": "res:/dx9/model/ship/minmatar/titan/mt1/icons/mt1_t1_isis.png",
        "png128": "res:/dx9/model/ship/minmatar/titan/mt1/icons/2906_128.png",
        "png64": "res:/dx9/model/ship/minmatar/titan/mt1/icons/2906_64.png",
        "jpg512": "res:/dx9/model/ship/minmatar/titan/mt1/icons/2906_512.jpg",
    },
    {
        "stem": "05_Angel_征服者级_Vanquisher",
        "race": "Angel",
        "zh": "征服者级",
        "en": "Vanquisher",
        "faction": "angel",
        "hull": "angt1",
        "gr2": "res:/dx9/model/ship/angel/titan/angt1/angt1_t1.gr2",
        "isis": "res:/dx9/model/ship/angel/titan/angt1/icons/angt1_t1_isis.png",
        "png128": "res:/dx9/model/ship/angel/titan/angt1/icons/26445_128.png",
        "png64": "res:/dx9/model/ship/angel/titan/angt1/icons/26445_64.png",
        "jpg512": "res:/dx9/model/ship/angel/titan/angt1/icons/26445_512.jpg",
    },
]


def black_to_alpha(im: Image.Image, thresh: int = 18, soft: int = 8) -> Image.Image:
    """Turn near-black background into transparency (ISIS / silhouette icons)."""
    rgba = im.convert("RGBA")
    arr = np.asarray(rgba).astype(np.float32)
    rgb = arr[..., :3]
    lum = rgb.max(axis=2)
    # hard transparent below thresh; soft ramp over soft px
    alpha = np.clip((lum - thresh) / max(soft, 1), 0, 1) * 255.0
    # keep existing alpha if any was meaningful (usually 255)
    out = arr.copy()
    out[..., 3] = np.minimum(out[..., 3], alpha)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def copy_fetch(res: str, dst: Path) -> Path | None:
    try:
        src = Path(fetch_resfile(res))
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        return dst
    except Exception as e:
        print(f"  fetch fail {res}: {e}")
        return None


def stage_icons(t: dict) -> dict:
    icon_dir = OUT / "icons" / t["stem"]
    icon_dir.mkdir(parents=True, exist_ok=True)
    info = {"stem": t["stem"], "zh": t["zh"], "en": t["en"], "race": t["race"]}

    # Raw copies
    for key, name in (
        ("isis", "raw_isis.png"),
        ("png128", "raw_128.png"),
        ("png64", "raw_64.png"),
        ("jpg512", "raw_512.jpg"),
    ):
        p = copy_fetch(t[key], icon_dir / name)
        info[key] = str(p.relative_to(OUT)).replace("\\", "/") if p else None

    # Transparent preferred: ISIS (pure black bg)
    isis_path = icon_dir / "raw_isis.png"
    if isis_path.is_file():
        tr = black_to_alpha(Image.open(isis_path), thresh=16, soft=10)
        out = icon_dir / f"{t['zh']}_{t['en']}__isis_transparent.png"
        # also ASCII-only name for packaging safety
        out_ascii = icon_dir / f"{t['race']}_{t['hull']}_isis_transparent.png"
        tr.save(out)
        tr.save(out_ascii)
        info["transparent_preferred"] = str(out_ascii.relative_to(OUT)).replace("\\", "/")
        info["transparent_bilingual"] = str(out.relative_to(OUT)).replace("\\", "/")

    # Also try 64/128 if mostly dark corners (optional)
    for raw_name, tag in (("raw_64.png", "64"), ("raw_128.png", "128")):
        rp = icon_dir / raw_name
        if not rp.is_file():
            continue
        im = Image.open(rp).convert("RGB")
        arr = np.asarray(im)
        corners = np.stack(
            [arr[0, 0], arr[0, -1], arr[-1, 0], arr[-1, -1]], axis=0
        ).astype(np.float32)
        if float(corners.max()) <= 24:
            tr = black_to_alpha(im, thresh=20, soft=12)
            dst = icon_dir / f"{t['race']}_{t['hull']}_{tag}_transparent.png"
            tr.save(dst)
            info[f"transparent_{tag}"] = str(dst.relative_to(OUT)).replace("\\", "/")
        else:
            info[f"transparent_{tag}"] = None
            info[f"note_{tag}"] = "portrait-style opaque bg; kept raw only"

    return info


def stage_threeview(t: dict) -> dict:
    out_dir = OUT / "models_threeview" / t["stem"]
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        gr2 = fetch_resfile(t["gr2"])
        print(f"[titan] {t['stem']} <- {t['gr2']}")
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
        ImageDraw.Draw(bar).text(
            (12, 8),
            f"{t['zh']} / {t['en']} ({t['race']})  {name}",
            fill=(200, 200, 210, 255),
        )
        full = Image.new("RGBA", (strip.width, SIZE + 36), (20, 22, 28, 255))
        full.paste(bar, (0, 0))
        full.paste(strip, (0, 36))
        full.save(out_dir / "threeview_strip.png")
        # also drop preferred transparent icon next to threeview for convenience
        pref = OUT / "icons" / t["stem"] / f"{t['race']}_{t['hull']}_isis_transparent.png"
        if pref.is_file():
            shutil.copy2(pref, out_dir / "icon_isis_transparent.png")
        return {
            "stem": t["stem"],
            "status": "ok",
            "mesh": name,
            "verts": len(verts),
            "tris": int(len(faces)),
            "res": t["gr2"],
        }
    except Exception as e:
        print(f"[FAIL] {t['stem']}: {e}")
        return {"stem": t["stem"], "status": "fail", "error": str(e), "res": t["gr2"]}


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
            sys.stderr.reconfigure(errors="replace")
        except Exception:
            pass

    OUT.mkdir(parents=True, exist_ok=True)
    icon_reports = []
    tv_reports = []

    print("=== icons ===")
    for t in TITANS:
        icon_reports.append(stage_icons(t))

    print("=== threeviews ===")
    for t in TITANS:
        tv_reports.append(stage_threeview(t))

    (OUT / "report.json").write_text(
        json.dumps({"icons": icon_reports, "threeviews": tv_reports}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    rows = [
        "# 端游泰坦素材确认包 · titan_assets_confirm",
        "",
        "> 四族泰坦（MULTIPLAYER_PVP §2）+ 天使征服者级（可选对照）",
        "> 脚本：`eveautochess-dev/tools/stage_titan_threeviews.py`",
        "",
        "## 图标（尽量透明底）",
        "",
        "TQ 船体目录里的 `*_128.png` / `*_512.jpg` 多为**渲染立绘不透明底**。",
        "**优先透明**：ISIS 舰树剪影 `*_isis.png`（纯黑底）→ 抠黑得 alpha，见 `icons/*/…_isis_transparent.png`。",
        "",
        "| 舰 | 推荐透明图标 | 原始立绘 |",
        "|----|--------------|----------|",
    ]
    for r in icon_reports:
        pref = r.get("transparent_preferred") or "—"
        raw = r.get("jpg512") or r.get("png128") or "—"
        rows.append(f"| {r['zh']} / {r['en']} ({r['race']}) | `{pref}` | `{raw}` |")

    rows += [
        "",
        "## models_threeview",
        "",
        "| 目录 | 状态 |",
        "|------|------|",
    ]
    for r in tv_reports:
        if r["status"] == "ok":
            rows.append(
                f"| `models_threeview/{r['stem']}/` | ok `{r['mesh']}` verts={r['verts']} tris={r['tris']} |"
            )
        else:
            rows.append(f"| `models_threeview/{r['stem']}/` | fail {r.get('error')} |")
    rows.append("")
    (OUT / "README.md").write_text("\n".join(rows), encoding="utf-8")

    ok = sum(1 for r in tv_reports if r["status"] == "ok")
    print(f"done threeview ok={ok}/{len(tv_reports)} icons={len(icon_reports)} -> {OUT}")


if __name__ == "__main__":
    main()
