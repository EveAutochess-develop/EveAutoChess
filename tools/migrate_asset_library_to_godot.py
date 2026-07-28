# -*- coding: utf-8 -*-
"""Migrate Echoes asset_library packs into Godot §0 ship bundles.

Source: H:/eve手游/history/asset_library
Dest:   godot_project/assets/models/ships/{model_key}/{model.glb,albedo.png,...}

Does not re-unpack NPK. Best-effort: link/copy existing GLB/PNG; skip missing.
"""
from __future__ import annotations

import json
import os
import shutil
import glob

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "godot_project"))
SHIPS_DIR = os.path.join(ROOT, "data", "ships")
DEST = os.path.join(ROOT, "assets", "models", "ships")
LIB = r"H:\eve手游\history\asset_library"
EXISTING_MODELS = os.path.join(ROOT, "assets", "models")
MESH_JSON = os.path.join(ROOT, "data", "visual_meshes.json")
TEX_JSON = os.path.join(ROOT, "data", "ship_textures.json")

LIGHT_DRONES = [
    "wrj_a_shiseng",
    "wrj_j_dahuangfeng",
    "wrj_g_dijingling",
    "wrj_m_mwushi",
]


def ensure_dir(p: str) -> None:
    os.makedirs(p, exist_ok=True)


def find_existing_glb(model_key: str) -> str | None:
    patterns = [
        os.path.join(EXISTING_MODELS, "**", f"*{model_key}*.glb"),
        os.path.join(EXISTING_MODELS, "ships", model_key, "model.glb"),
        os.path.join(LIB, "**", model_key, "**", "*.glb"),
        os.path.join(LIB, "**", model_key, "**", "*.mesh"),
    ]
    for pat in patterns:
        hits = glob.glob(pat, recursive=True)
        for h in hits:
            if h.lower().endswith(".glb"):
                return h
    return None


def find_texture(model_key: str) -> tuple[str | None, str | None]:
    albedo = None
    normal = None
    for pat in [
        os.path.join(EXISTING_MODELS, "**", f"*{model_key}*d*.png"),
        os.path.join(EXISTING_MODELS, "**", f"*{model_key}*albedo*.png"),
        os.path.join(LIB, "**", model_key, "**", "*_d.png"),
        os.path.join(LIB, "**", model_key, "**", "*albedo*.png"),
    ]:
        for h in glob.glob(pat, recursive=True):
            low = h.lower()
            if "normal" in low or "_n." in low or "nrm" in low:
                normal = normal or h
            else:
                albedo = albedo or h
    return albedo, normal


def copy_bundle(model_key: str) -> dict:
    out_dir = os.path.join(DEST, model_key)
    ensure_dir(out_dir)
    info = {"model_key": model_key, "mesh": "", "albedo": "", "normal": ""}
    glb = find_existing_glb(model_key)
    if glb:
        dst = os.path.join(out_dir, "model.glb")
        if not os.path.exists(dst):
            shutil.copy2(glb, dst)
        info["mesh"] = f"res://assets/models/ships/{model_key}/model.glb"
    albedo, normal = find_texture(model_key)
    if albedo:
        dst = os.path.join(out_dir, "albedo.png")
        if not os.path.exists(dst):
            try:
                shutil.copy2(albedo, dst)
            except Exception:
                pass
        if os.path.exists(dst):
            info["albedo"] = f"res://assets/models/ships/{model_key}/albedo.png"
    if normal:
        dst = os.path.join(out_dir, "normal.png")
        if not os.path.exists(dst):
            try:
                shutil.copy2(normal, dst)
            except Exception:
                pass
        if os.path.exists(dst):
            info["normal"] = f"res://assets/models/ships/{model_key}/normal.png"
    return info


def main() -> None:
    ensure_dir(DEST)
    keys = []
    ship_mesh = {}
    ship_tex = {}
    for p in sorted(glob.glob(os.path.join(SHIPS_DIR, "*.json")), key=lambda x: int(os.path.splitext(os.path.basename(x))[0])):
        d = json.load(open(p, encoding="utf-8"))
        key = d.get("model_key") or ""
        sid = str(d["id"])
        if not key:
            continue
        keys.append(key)
        info = copy_bundle(key)
        # Keep prior visual_meshes path if bundle empty
        if info["mesh"]:
            ship_mesh[sid] = info["mesh"]
        if info["albedo"]:
            ship_tex[sid] = info["albedo"]
    for key in LIGHT_DRONES:
        copy_bundle(key)
        # medium drones intentionally empty
    # merge with existing maps
    old_mesh = {}
    old_tex = {}
    if os.path.exists(MESH_JSON):
        old_mesh = json.load(open(MESH_JSON, encoding="utf-8")).get("ships", {})
    if os.path.exists(TEX_JSON):
        old_tex = json.load(open(TEX_JSON, encoding="utf-8")).get("ships", {})
    for k, v in old_mesh.items():
        ship_mesh.setdefault(k, v)
    for k, v in old_tex.items():
        ship_tex.setdefault(k, v)
    with open(MESH_JSON, "w", encoding="utf-8") as f:
        json.dump({"ships": ship_mesh}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    with open(TEX_JSON, "w", encoding="utf-8") as f:
        json.dump({"ships": ship_tex}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"bundles attempted for {len(keys)} ships + {len(LIGHT_DRONES)} light drones")
    print(f"mesh entries: {len(ship_mesh)}")


if __name__ == "__main__":
    main()
