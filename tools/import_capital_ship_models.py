# -*- coding: utf-8 -*-
"""Import capital hull §0 bundles from Echoes NeoX entities.

Aligns English capital model_keys to Echoes entity keys, converts
.mesh → model.glb, decodes *_ad/_n/_pmwo/_rg/_reduction.ktx → PNG,
then rewrites visual_meshes.json / ship_textures.json.

Nonlinear display scale stays in ShipUnit._normalize_model_scale
(model_long_axis + visual.json curve); this script only restores meshes.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
from assimp_convert import AssimpError, convert as assimp_convert  # noqa: E402
from convert_ship_ktx_albedo import decode_ktx  # noqa: E402
from rewrite_visual_maps import main as rewrite_visual_maps  # noqa: E402

GODOT = ROOT / "godot_project"
SHIPS = GODOT / "data" / "ships"
PACKS = GODOT / "assets" / "models" / "ships"
LIB_SHIPS = Path(r"H:\eve手游\history\asset_library\entities\ships")
NEOX_CONV = Path(
    r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\converter.py"
)

## ship_id → Echoes entity key (bundle model_key)
CAPITAL_ECHOES_KEY: dict[int, str] = {
    111: "am_shenshi",
    112: "glt_moluo",
    113: "jdl_fenghuang",
    114: "mmte_najiafa",
    121: "am_zhizhengguan",
    122: "jdl_qimeila",
    123: "glt_juenian",
    124: "mmte_niyigeer",
    131: "am_shitu",
    132: "jdl_longniao",
    133: "mmte_lifu",
    134: "glt_ninasu",
}

TEX_SUFFIXES = {
    "_ad.ktx": "albedo.png",
    "_n.ktx": "normal.png",
    "_pmwo.ktx": "pmwo.png",
    "_rg.ktx": "rg.png",
    "_reduction.ktx": "reduction.png",
}


def find_entity(key: str) -> Path | None:
    exact = LIB_SHIPS / key
    if exact.is_dir():
        return exact
    for p in LIB_SHIPS.iterdir():
        if p.is_dir() and (p.name == key or p.name.startswith(key + "__")):
            return p
    return None


def pick_mesh(ent: Path, key: str) -> Path | None:
    mesh_dir = ent / "mesh"
    if not mesh_dir.is_dir():
        return None
    for name in (f"{key}_lod1.mesh", f"{key}_lod0.mesh", f"{key}_lod2.mesh"):
        p = mesh_dir / name
        if p.is_file() and p.stat().st_size > 1000:
            return p
    cands = sorted(
        (p for p in mesh_dir.glob("*.mesh") if p.stat().st_size > 1000),
        key=lambda x: (0 if "lod1" in x.name else 1 if "lod0" in x.name else 2, x.name),
    )
    return cands[0] if cands else None


def mesh_to_glb(mesh: Path, dst_glb: Path) -> None:
    if not NEOX_CONV.is_file():
        raise RuntimeError(f"NeoX converter missing: {NEOX_CONV}")
    dst_glb.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="capital_neox_") as td:
        work = Path(td)
        local = work / mesh.name
        shutil.copy2(mesh, local)
        r = subprocess.run(
            [sys.executable, str(NEOX_CONV), str(local), "--mode", "obj"],
            capture_output=True,
            text=True,
            timeout=600,
            cwd=str(NEOX_CONV.parent),
        )
        obj = None
        for cand in (Path(str(local) + ".obj"), local.with_suffix(".obj")):
            if cand.is_file() and cand.stat().st_size > 100:
                obj = cand
                break
        if obj is None:
            objs = list(work.glob("*.obj"))
            obj = objs[0] if objs else None
        if obj is None:
            err = (r.stderr or r.stdout or "")[-500:]
            raise RuntimeError(f"NeoX OBJ missing for {mesh.name}: {err}")
        assimp_convert(obj, dst_glb, "glb2")
        if not dst_glb.is_file() or dst_glb.stat().st_size < 1000:
            raise AssimpError(f"GLB too small: {dst_glb}")


def decode_textures(ent: Path, key: str, out_dir: Path) -> dict[str, str]:
    tex_dir = ent / "textures"
    written: dict[str, str] = {}
    if not tex_dir.is_dir():
        return written
    for suffix, png_name in TEX_SUFFIXES.items():
        src = tex_dir / f"{key}{suffix}"
        if not src.is_file():
            cands = list(tex_dir.glob(f"*{suffix}"))
            # Prefer non-skin variants (no maze/neon prefix).
            cands = [c for c in cands if not any(x in c.name for x in ("maze", "neon", "skin"))]
            src = cands[0] if cands else None
        if src is None or not src.is_file():
            continue
        im = decode_ktx(src)
        if im is None:
            print(f"  WARN decode fail {src.name}")
            continue
        if max(im.size) > 1024:
            im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        dst = out_dir / png_name
        im.convert("RGBA").save(dst)
        written[png_name] = f"res://assets/models/ships/{key}/{png_name}"
        print(f"  tex {png_name} <- {src.name} {im.size}")
    return written


def patch_ship_json(ship_id: int, echoes_key: str) -> Path:
    path = SHIPS / f"{ship_id}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    old = str(data.get("model_key", ""))
    data["model_key"] = echoes_key
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if old != echoes_key:
        print(f"  model_key {old} → {echoes_key}")
    return path


def import_one(ship_id: int, echoes_key: str) -> str:
    print(f"== {ship_id} {echoes_key}")
    patch_ship_json(ship_id, echoes_key)
    ent = find_entity(echoes_key)
    if ent is None:
        return "no_entity"
    mesh = pick_mesh(ent, echoes_key)
    if mesh is None:
        return "no_mesh"
    out_dir = PACKS / echoes_key
    out_dir.mkdir(parents=True, exist_ok=True)
    glb = out_dir / "model.glb"
    if glb.is_file() and glb.stat().st_size > 1000:
        print(f"  glb exists {glb.stat().st_size}")
    else:
        print(f"  convert {mesh.name}")
        mesh_to_glb(mesh, glb)
        print(f"  wrote glb {glb.stat().st_size}")
    decode_textures(ent, echoes_key, out_dir)
    if not (out_dir / "albedo.png").is_file():
        return "no_albedo"
    return "ok"


def main() -> int:
    results: dict[str, list[int]] = {}
    for sid, key in CAPITAL_ECHOES_KEY.items():
        try:
            status = import_one(sid, key)
        except Exception as e:
            status = f"fail:{e}"
            print(f"  ERROR {e}")
        results.setdefault(status, []).append(sid)
    print("--- rewrite visual maps ---")
    rewrite_visual_maps()
    print("SUMMARY", {k: v for k, v in results.items()})
    return 0 if all(k == "ok" for k in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
