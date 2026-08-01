#!/usr/bin/env python3
"""Import TQ siege / industrial morph assets into ship model packs.

Near-term (this script):
  - Convert cached siege *addon* GR2 meshes (static) → siege_addon.glb under the ship pack
  - Write hull_morph.json clip-name sidecars for AnimationPlayer state machines

Full skeletal SiegeLoop (Rorqual orecs1 / dread FX):
  - Requires blendergranny headless export (tools/eve_pc/vendor/blendergranny-main)
  - Current Echoes/OBJ packs have animations:[] — replace model.glb only after verified Skeleton3D+clips

See: tools/_siege_morph_asset_map.json · CAPITAL_AND_CYNO.md §4 · MINING_AND_DUST.md §2.4
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

MAP_PATH = TOOLS / "_siege_morph_asset_map.json"
SHIPS = ROOT / "godot_project" / "assets" / "models" / "ships"
RES_ROOTS = [
    Path(r"H:\EVE\ResFiles"),
    Path(r"H:\eve\ResFiles"),
]
INDEX_CANDIDATES = [
    Path(r"H:\EVE\tq\resfileindex.txt"),
    Path(r"H:\eve\tq\resfileindex.txt"),
]

# model_key → TQ siege addon res paths (subset present in local cache)
ADDONS: dict[str, list[str]] = {
    "am_shenshi": [
        "res:/dx9/model/ship/amarr/dreadnought/adn1/effects/adn1_fx_siegecore_01a.gr2",
    ],
    "jdl_fenghuang": [
        "res:/dx9/model/ship/caldari/dreadnought/cdn1/effects/cdn_t1_fx_animatedflaps_01a.gr2",
    ],
}

HULL_MORPH_JSON = {
    "am_shenshi": {"kind": "siege", "start_clips": ["StartSiege"], "loop_clips": ["SiegeLoop"]},
    "glt_moluo": {"kind": "siege", "start_clips": ["StartSiege"], "loop_clips": ["SiegeLoop"]},
    "jdl_fenghuang": {"kind": "siege", "start_clips": ["StartSiege"], "loop_clips": ["SiegeLoop"]},
    "mmte_najiafa": {"kind": "siege", "start_clips": ["StartSiege"], "loop_clips": ["SiegeLoop"]},
    "lhky_changxujing": {
        "kind": "industrial",
        "start_clips": ["Normal2Siege", "StartSiege"],
        "loop_clips": ["SiegeLoop", "SiegeMode", "InSiegeMode"],
    },
}


def _load_index() -> dict[str, str]:
    """res path lower -> cache relative hash path."""
    out: dict[str, str] = {}
    idx = next((p for p in INDEX_CANDIDATES if p.is_file()), None)
    if idx is None:
        return out
    for line in idx.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = line.split(",")
        if len(parts) < 3:
            continue
        res = parts[0].strip().lower()
        # format: res,xx/hash_fullhash,fullhash,size,...
        rel = parts[1].strip()
        out[res] = rel
    return out


def _find_resfile(rel: str) -> Path | None:
    for root in RES_ROOTS:
        p = root / rel.replace("/", os.sep)
        if p.is_file():
            return p
    return None


def _write_hull_morph_json() -> None:
    for key, cfg in HULL_MORPH_JSON.items():
        pack = SHIPS / key
        if not pack.is_dir():
            print(f"SKIP json {key}: pack missing")
            continue
        dst = pack / "hull_morph.json"
        dst.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"OK   hull_morph.json → {dst}")


def _gr2_to_obj_via_meshes(gr2_path: Path, obj_path: Path) -> bool:
    try:
        from stage_fighter_threeviews import Gr2Meshes, pick_best_mesh  # type: ignore
    except Exception as e:
        print(f"FAIL import Gr2Meshes: {e}")
        return False
    try:
        g = Gr2Meshes(str(gr2_path))
        name, verts, faces = pick_best_mesh(g)
    except Exception as e:
        print(f"FAIL pick mesh {gr2_path.name}: {e}")
        return False
    obj_path.parent.mkdir(parents=True, exist_ok=True)
    with obj_path.open("w", encoding="utf-8") as f:
        f.write(f"# siege addon from {gr2_path.name} mesh={name}\n")
        for v in verts:
            f.write(f"v {v[0]} {v[1]} {v[2]}\n")
        for tri in faces:
            f.write(f"f {tri[0]+1} {tri[1]+1} {tri[2]+1}\n")
    return True


def _assimp_obj_to_glb(obj_path: Path, glb_path: Path) -> bool:
    assimp = os.environ.get("ASSIMP_EXE", "assimp")
    cmd = [assimp, "export", str(obj_path), str(glb_path), "-fglb2"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as e:
        print(f"FAIL assimp: {e}")
        return False
    if r.returncode != 0 or not glb_path.is_file():
        print(f"FAIL assimp {obj_path.name}: {r.stderr[-400:]}")
        return False
    return True


def _convert_addons(index: dict[str, str]) -> None:
    tmp = TOOLS / "_tmp_siege_addon"
    tmp.mkdir(exist_ok=True)
    for model_key, res_list in ADDONS.items():
        pack = SHIPS / model_key
        if not pack.is_dir():
            print(f"SKIP addon {model_key}: pack missing")
            continue
        for res in res_list:
            rel = index.get(res.lower())
            if not rel:
                print(f"MISS index {res}")
                continue
            src = _find_resfile(rel)
            if src is None:
                print(f"MISS file {res} → {rel}")
                continue
            stem = Path(res).stem
            obj = tmp / f"{model_key}_{stem}.obj"
            glb = pack / "siege_addon.glb"
            if not _gr2_to_obj_via_meshes(src, obj):
                continue
            if _assimp_obj_to_glb(obj, glb):
                print(f"OK   siege_addon.glb ← {res} → {glb}")
            else:
                print(f"WARN left OBJ only {obj}")


def main() -> int:
    print("=== import_siege_morph_assets ===")
    if MAP_PATH.is_file():
        print(f"map: {MAP_PATH}")
    _write_hull_morph_json()
    index = _load_index()
    print(f"index entries: {len(index)}")
    _convert_addons(index)
    print(
        "NOTE: Full SiegeLoop skeletal import needs blendergranny → replace model.glb; "
        "runtime already prefers AnimationPlayer when clips exist (HullMorphFx)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
