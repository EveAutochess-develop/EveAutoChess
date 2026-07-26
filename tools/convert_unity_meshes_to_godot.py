# -*- coding: utf-8 -*-
"""
Unity 3D assets → Godot-ready GLB/OBJ.

Pipeline (auto-detected):
  1. .fbx  → FBX2glTF (preferred) or Assimp DLL
  2. .3ds  → Assimp DLL (glb2)
  3. .obj  → Assimp DLL to glb, or copy .obj

Usage:
  python convert_unity_meshes_to_godot.py
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from assimp_convert import AssimpError, convert as assimp_convert  # noqa: E402

UNITY_ROOT = Path(r"H:\game_dev\eveautochess-original\unity-source\DUST_243-main\Assets")
OUT_ROOT = Path(r"H:\game_dev\eveautochess-dev\godot_project\assets\models")
TOOLS = Path(r"H:\game_dev\eveautochess-dev\tools")
MANIFEST_OUT = OUT_ROOT / "conversion_manifest.json"

SHIP_3DS_MAP = {
    1: "惩罚者级",
    2: "检察官级",
    3: "巨神兵级",
    4: "富豪级",
    5: "强制者级",
    6: "龙骑兵级",
    7: "启示级",
    8: "奥格诺级",
    9: "暴君级",
    10: "主宰级",
}

MESH_GLOBS = [
    "Models/**/*.fbx",
    "Models/**/*.FBX",
    "Models/**/*.3ds",
    "Models/**/*.3DS",
    "Models/**/*.obj",
    "Models/**/*.OBJ",
    "Resources/Visual/Models/**/*.obj",
    "Resources/Visual/Models/**/*.OBJ",
]


def find_fbx2gltf() -> Path | None:
    for p in TOOLS.rglob("FBX2glTF*.exe"):
        return p
    return None


def rel_key(src: Path) -> str:
    try:
        return src.relative_to(UNITY_ROOT).as_posix()
    except ValueError:
        return src.name


def out_path_for(src: Path, ext: str = ".glb") -> Path:
    rel = Path(rel_key(src))
    if "Champions" in rel.parts and src.suffix.lower() == ".3ds":
        return OUT_ROOT / "ships" / f"{src.stem}{ext}"
    if "Structures" in rel.parts:
        return OUT_ROOT / "structures" / f"{src.stem}{ext}"
    safe = "_".join(rel.with_suffix("").parts).replace(" ", "_")
    return OUT_ROOT / "env" / f"{safe}{ext}"


def convert_fbx_fbx2gltf(fbx2gltf: Path, src: Path, dst: Path) -> bool:
    dst.parent.mkdir(parents=True, exist_ok=True)
    out_base = dst.with_suffix("")
    cmd = [str(fbx2gltf), "-i", str(src), "-o", str(out_base), "-b"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  FBX2glTF fail {src.name}: {(r.stderr or r.stdout)[-300:]}", file=sys.stderr)
        return False
    produced = out_base.with_suffix(".glb")
    if produced.is_file() and produced.resolve() != dst.resolve():
        produced.replace(dst)
    return dst.is_file() and dst.stat().st_size > 0


def convert_via_assimp(src: Path, dst: Path) -> bool:
    try:
        assimp_convert(src, dst, "glb2")
        return dst.is_file() and dst.stat().st_size > 0
    except AssimpError as e:
        print(f"  Assimp fail {src.name}: {e}", file=sys.stderr)
        return False


def collect_sources() -> list[Path]:
    found: list[Path] = []
    for pattern in MESH_GLOBS:
        found.extend(UNITY_ROOT.glob(pattern))
    uniq = {p.resolve(): p for p in found}
    return sorted(uniq.values(), key=lambda p: str(p).lower())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    fbx2gltf = find_fbx2gltf()
    print("FBX2glTF:", fbx2gltf)

    sources = collect_sources()
    print(f"Found {len(sources)} mesh files under {UNITY_ROOT}")
    OUT_ROOT.mkdir(parents=True, exist_ok=True)

    results = []
    ok_n = fail_n = 0
    for src in sources:
        suffix = src.suffix.lower()
        dst = out_path_for(src, ".glb")
        entry = {
            "src": rel_key(src),
            "dst": "res://assets/models/" + str(dst.relative_to(OUT_ROOT)).replace("\\", "/"),
            "ok": False,
            "method": "",
            "bytes": 0,
        }
        if args.dry_run:
            print(f"DRY {entry['src']} -> {entry['dst']}")
            results.append(entry)
            continue

        success = False
        if suffix == ".fbx":
            if fbx2gltf:
                success = convert_fbx_fbx2gltf(fbx2gltf, src, dst)
                entry["method"] = "FBX2glTF"
            if not success:
                success = convert_via_assimp(src, dst)
                entry["method"] = "Assimp"
        elif suffix == ".3ds":
            success = convert_via_assimp(src, dst)
            entry["method"] = "Assimp"
        elif suffix == ".obj":
            success = convert_via_assimp(src, dst)
            entry["method"] = "Assimp"
            if not success:
                dst_obj = out_path_for(src, ".obj")
                dst_obj.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst_obj)
                success = dst_obj.is_file()
                entry["method"] = "copy-obj"
                entry["dst"] = "res://assets/models/" + str(dst_obj.relative_to(OUT_ROOT)).replace("\\", "/")
                dst = dst_obj
        else:
            entry["method"] = "skip"

        if success:
            entry["ok"] = True
            entry["bytes"] = dst.stat().st_size
            ok_n += 1
            print(f"OK [{entry['method']}] {src.name} ({entry['bytes']} B)")
        else:
            fail_n += 1
            print(f"FAIL {src}")
        results.append(entry)

    ship_map = {}
    for sid, stem in SHIP_3DS_MAP.items():
        glb = OUT_ROOT / "ships" / f"{stem}.glb"
        if glb.is_file():
            ship_map[str(sid)] = f"res://assets/models/ships/{stem}.glb"
    (OUT_ROOT / "ship_mesh_map.json").write_text(
        json.dumps(ship_map, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # also into data/ for DataStore convenience
    data_map = Path(r"H:\game_dev\eveautochess-dev\godot_project\data\visual_meshes.json")
    data_map.write_text(json.dumps({"ships": ship_map}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    MANIFEST_OUT.write_text(
        json.dumps(
            {"ok": ok_n, "fail": fail_n, "files": results, "ship_mesh_map": ship_map},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Done ok={ok_n} fail={fail_n}")
    print(f"ship_mesh_map entries: {len(ship_map)}")
    print(f"manifest: {MANIFEST_OUT}")
    return 0 if ok_n > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
