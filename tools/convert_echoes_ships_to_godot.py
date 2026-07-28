# -*- coding: utf-8 -*-
"""Convert classified Echoes ship OBJs to Godot GLB + refresh art manifests.

Input:  art_extract/ship_classified/by_key/{model_key}/meshes/*.obj
Output: godot_project/assets/models/ships/{model_key}.glb
        godot_project/assets/ui/portraits/{model_key}.png (from preview/thumb)
        data/visual_meshes.json, ship_textures.json, ship_portraits.json

Usage:
  python convert_echoes_ships_to_godot.py              # all roster keys from CSV
  python convert_echoes_ships_to_godot.py --keys am_fuhao,jdl_xiaoying
"""
from __future__ import annotations

import argparse
import csv
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
from assimp_convert import AssimpError, convert  # noqa: E402

DESIGN = Path(r"H:\game_dev\eveautochess-design")
CSV_PATH = DESIGN / "docs" / "_extracted" / "amarr_counterparts.csv"
CLASSIFIED = Path(r"H:\eve手游\history\1.0.0_unpacked\art_extract\ship_classified")
BY_KEY = CLASSIFIED / "by_key"
THUMBS = CLASSIFIED / "_thumbs"
CATALOG = CLASSIFIED / "_catalog.json"
GODOT = ROOT / "godot_project"
MODELS_OUT = GODOT / "assets" / "models" / "ships"
PORTRAITS_OUT = GODOT / "assets" / "ui" / "portraits"
DATA_OUT = GODOT / "data"
TEX_SRC = Path(r"H:\eve手游\history\1.0.0_unpacked\art_extract\textures")


def roster_keys() -> list[tuple[str, str]]:
    """Return [(ship_id, model_key), ...] for 40 ships."""
    rows = list(csv.DictReader(CSV_PATH.read_text(encoding="utf-8").splitlines()))
    out = []
    for row in rows:
        for col in ("amarr", "caldari", "minmatar", "gallente"):
            out.append((row[f"{col}_id"], row[f"{col}_key"]))
    return out


def find_obj(key: str) -> Path | None:
    mesh_dir = BY_KEY / key / "meshes"
    if not mesh_dir.is_dir():
        return None
    objs = sorted(mesh_dir.glob("*.obj"))
    return objs[0] if objs else None


def find_preview(key: str, stem: str | None) -> Path | None:
    preview = BY_KEY / key / "preview.png"
    if preview.is_file() and preview.stat().st_size > 500:
        return preview
    if stem:
        thumb = THUMBS / f"{stem}.png"
        if thumb.is_file():
            return thumb
    return None


def try_copy_diffuse(key: str) -> bool:
    """Copy TGA/PNG albedo if present in by_key/textures or nearby; else skip."""
    tex_dir = BY_KEY / key / "textures"
    dst = MODELS_OUT / f"{key}_ad.png"
    candidates = []
    if tex_dir.is_dir():
        for pat in (f"{key}_ad.png", f"{key}_ad.tga", "*_ad.png", "*_ad.tga", "*_d.png"):
            candidates.extend(tex_dir.glob(pat))
    for src in candidates:
        if src.suffix.lower() == ".png":
            shutil.copy2(src, dst)
            return True
        # TGA: leave for later; Godot can import TGA if copied as .tga
        if src.suffix.lower() == ".tga":
            tga_dst = MODELS_OUT / f"{key}_ad.tga"
            shutil.copy2(src, tga_dst)
            return True
    return False


def convert_one(ship_id: str, key: str, force: bool = False) -> dict:
    obj = find_obj(key)
    glb = MODELS_OUT / f"{key}.glb"
    result = {"id": ship_id, "key": key, "obj": str(obj) if obj else None, "ok": False}
    if not obj:
        result["error"] = "missing_obj"
        return result
    stem = obj.stem
    if (not force) and glb.is_file() and glb.stat().st_mtime >= obj.stat().st_mtime:
        # Still refresh portrait if missing
        result["skipped_glb"] = True
    else:
        try:
            convert(obj, glb, "glb2")
        except AssimpError as e:
            result["error"] = str(e)
            return result
    result["glb"] = str(glb)
    result["glb_bytes"] = glb.stat().st_size if glb.is_file() else 0
    try_copy_diffuse(key)
    preview = find_preview(key, stem)
    PORTRAITS_OUT.mkdir(parents=True, exist_ok=True)
    if preview:
        shutil.copy2(preview, PORTRAITS_OUT / f"{key}.png")
        result["portrait"] = True
    else:
        result["portrait"] = False
    result["ok"] = True
    return result


def refresh_manifests(pairs: list[tuple[str, str]]) -> None:
    meshes, textures, portraits = {}, {}, {}
    for sid, key in pairs:
        meshes[sid] = f"res://assets/models/ships/{key}.glb"
        # Prefer _ad.png; ship_unit also accepts _d.png
        ad = MODELS_OUT / f"{key}_ad.png"
        tga = MODELS_OUT / f"{key}_ad.tga"
        if ad.is_file():
            textures[sid] = f"res://assets/models/ships/{key}_ad.png"
        elif tga.is_file():
            textures[sid] = f"res://assets/models/ships/{key}_ad.tga"
        else:
            textures[sid] = f"res://assets/models/ships/{key}_ad.png"
        portraits[sid] = f"res://assets/ui/portraits/{key}.png"
    DATA_OUT.mkdir(parents=True, exist_ok=True)
    (DATA_OUT / "visual_meshes.json").write_text(
        json.dumps({"ships": meshes}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (DATA_OUT / "ship_textures.json").write_text(
        json.dumps({"ships": textures}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (DATA_OUT / "ship_portraits.json").write_text(
        json.dumps({"ships": portraits}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keys", default="", help="comma-separated model_keys (default: all 40)")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    pairs = roster_keys()
    if args.keys:
        allow = {k.strip() for k in args.keys.split(",") if k.strip()}
        pairs = [(sid, k) for sid, k in pairs if k in allow]
    MODELS_OUT.mkdir(parents=True, exist_ok=True)
    ok = fail = 0
    report = []
    for sid, key in pairs:
        r = convert_one(sid, key, force=args.force)
        report.append(r)
        if r.get("ok"):
            ok += 1
            print(f"OK {key} glb={r.get('glb_bytes')} portrait={r.get('portrait')}")
        else:
            fail += 1
            print(f"FAIL {key}: {r.get('error')}")
    refresh_manifests(roster_keys())
    (CLASSIFIED / "_convert_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"DONE ok={ok} fail={fail} models={MODELS_OUT}")


if __name__ == "__main__":
    main()
