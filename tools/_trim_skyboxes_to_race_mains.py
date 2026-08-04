# -*- coding: utf-8 -*-
"""Generate 4 race main panoramas from TQ *h1_cube_refl.dds; rewrite region maps.

Sources stay in eveautochess-design review tree (tq_universe is not shipped).
Bake pipeline (NEW_EDEN_REGIONS §2):
  1) unwrap cube → equirect
  2) gamma + p99 stretch so mid-horizon is not near-black under a top-down camera
  Do NOT vertically roll the equirect: that breaks pole↔latitude mapping and
  PanoramaSkyMaterial pinches detailed rows into a fan/V singularity.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage_region_skyboxes import JPEG_QUALITY, cube_faces, equirect

ROOT = Path(__file__).resolve().parent.parent / "godot_project"
DESIGN_UNIVERSE = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\skyboxes_tq\universe"
)
RACE_OUT = ROOT / "assets" / "skyboxes" / "races"
DATA = ROOT / "data" / "regions"
POOL = DATA / "nullsec_pool.json"

RACES = {
    "a": "ah1",
    "c": "ch1",
    "g": "gh1",
    "m": "mh1",
}

PANO_W = 2048
PANO_H = 1024
GAMMA = 0.55
## Neutral dark floor only — never navy blue (was washing the whole dome).
SPACE_FLOOR = np.array([4.0, 4.0, 5.0], dtype=np.float32)


def _lift_for_display(im: Image.Image) -> Image.Image:
    a = np.asarray(im, dtype=np.float32)
    p99 = max(float(np.percentile(a, 99.5)), 1.0)
    n = np.clip(a / p99, 0.0, 1.0)
    n = np.power(n, GAMMA)
    ## Lift nebulae; empty space stays near-black, not tinted blue.
    out = np.clip(n * 220.0 + SPACE_FLOOR[None, None, :] * (1.0 - n), 0, 255)
    return Image.fromarray(out.astype(np.uint8), mode="RGB")


def _rewrite_import(jpg: Path) -> None:
    """Panorama-friendly import: no 3D detect compress, no alpha-border fix."""
    imp = Path(str(jpg) + ".import")
    if not imp.is_file():
        return
    text = imp.read_text(encoding="utf-8")
    text = text.replace("detect_3d/compress_to=1", "detect_3d/compress_to=0")
    text = text.replace("process/fix_alpha_border=true", "process/fix_alpha_border=false")
    imp.write_text(text, encoding="utf-8")


def main() -> None:
    RACE_OUT.mkdir(parents=True, exist_ok=True)
    for _letter, stem in RACES.items():
        src = DESIGN_UNIVERSE / stem / f"{stem}_cube_refl.dds"
        if not src.is_file():
            raise SystemExit(f"missing {src}")
        dst = RACE_OUT / f"{stem}.jpg"
        raw = equirect(cube_faces(src), w=PANO_W, h=PANO_H)
        im = _lift_for_display(raw)
        im.save(dst, quality=JPEG_QUALITY, optimize=True)
        _rewrite_import(dst)
        a = np.asarray(im, dtype=np.float32)
        mid = a[a.shape[0] // 3 : 2 * a.shape[0] // 3]
        print(
            f"OK {stem} <- {src.name} ({dst.stat().st_size / 1024:.0f} KB) "
            f"mean={a.mean():.1f} mid={mid.mean():.1f} p99={np.percentile(a, 99):.0f}"
        )

    pool = json.loads(POOL.read_text(encoding="utf-8"))
    smap: dict[str, str] = {}
    for r in pool["regions"]:
        old = str(r.get("skybox_stem", ""))
        letter = old[:1].lower() if old else "a"
        if letter not in RACES:
            letter = "a"
        stem = RACES[letter]
        r["skybox_stem"] = stem
        r["skybox_key"] = f"{stem}_cube"
        r["skybox_race"] = letter
        smap[str(r["region_id"])] = stem

    (DATA / "skybox_map.json").write_text(
        json.dumps(smap, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    POOL.write_text(json.dumps(pool, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"rewrote {len(smap)} region -> race stem maps")


if __name__ == "__main__":
    main()
