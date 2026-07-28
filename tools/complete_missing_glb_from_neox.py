# -*- coding: utf-8 -*-
"""Convert NeoX .mesh → OBJ → §0 model.glb for roster keys still missing GLB.

Uses zhouhang95/neox_tools converter + Assimp. Prefer lod1, else lod0/any.
Does not invent textures/portraits — only fills mesh when library has .mesh.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
from assimp_convert import AssimpError, convert as assimp_convert  # noqa: E402

GODOT = ROOT / "godot_project"
PACKS = GODOT / "assets" / "models" / "ships"
SHIPS = GODOT / "data" / "ships"
UNMANNED = GODOT / "data" / "unmanned_units"
LIB_SHIPS = Path(r"H:\eve手游\history\asset_library\entities\ships")
LIB_DRONES = Path(r"H:\eve手游\history\asset_library\entities\drones")
NEOX_CONV = Path(
    r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\converter.py"
)
REPORT = ROOT / "tools" / "_complete_glb_report.txt"


def find_entity_dir(model_key: str) -> Path | None:
    for root in (LIB_SHIPS, LIB_DRONES):
        if not root.is_dir():
            continue
        exact = root / model_key
        if exact.is_dir():
            return exact
        for p in root.iterdir():
            if p.is_dir() and (p.name == model_key or p.name.startswith(model_key + "__")):
                return p
    return None


def pick_mesh(ent: Path, model_key: str) -> Path | None:
    mesh_dir = ent / "mesh"
    if not mesh_dir.is_dir():
        return None
    preferred = [
        mesh_dir / f"{model_key}_lod1.mesh",
        mesh_dir / f"{model_key}_lod0.mesh",
        mesh_dir / f"{model_key}_lod2.mesh",
    ]
    for p in preferred:
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
    with tempfile.TemporaryDirectory(prefix="neox_mesh_") as td:
        work = Path(td)
        local = work / mesh.name
        shutil.copy2(mesh, local)
        r = subprocess.run(
            [sys.executable, str(NEOX_CONV), str(local), "--mode", "obj"],
            capture_output=True,
            text=True,
            timeout=300,
            cwd=str(NEOX_CONV.parent),
        )
        obj = None
        for cand in (
            Path(str(local) + ".obj"),
            local.with_suffix(".obj"),
            work / f"{local.name}.obj",
        ):
            if cand.is_file() and cand.stat().st_size > 100:
                obj = cand
                break
        if obj is None:
            for cand in work.glob("*.obj"):
                obj = cand
                break
        if obj is None:
            err = (r.stderr or r.stdout or "")[-400:]
            raise RuntimeError(f"NeoX OBJ missing for {mesh.name}: {err}")
        assimp_convert(obj, dst_glb, "glb2")
        if not dst_glb.is_file() or dst_glb.stat().st_size < 1000:
            raise AssimpError(f"GLB too small: {dst_glb}")


def roster_keys() -> list[tuple[str, str, str]]:
    """[(kind, id, model_key), ...]"""
    out: list[tuple[str, str, str]] = []
    for folder, kind in ((SHIPS, "ship"), (UNMANNED, "drone")):
        for f in sorted(folder.glob("*.json")):
            j = json.loads(f.read_text(encoding="utf-8"))
            key = (j.get("model_key") or "").strip()
            sid = str(j.get("id") or f.stem)
            if key:
                out.append((kind, sid, key))
    return out


def main() -> int:
    rows = []
    ok = skip = fail = 0
    for kind, sid, key in roster_keys():
        dst = PACKS / key / "model.glb"
        if dst.is_file() and dst.stat().st_size > 1000:
            skip += 1
            rows.append(f"SKIP {kind} {sid} {key} (exists {dst.stat().st_size})")
            continue
        ent = find_entity_dir(key)
        if ent is None:
            fail += 1
            rows.append(f"FAIL {kind} {sid} {key} no_entity")
            continue
        mesh = pick_mesh(ent, key)
        if mesh is None:
            fail += 1
            rows.append(f"FAIL {kind} {sid} {key} no_mesh in {ent.name}")
            continue
        try:
            mesh_to_glb(mesh, dst)
            ok += 1
            rows.append(f"OK {kind} {sid} {key} <- {mesh.name} ({dst.stat().st_size})")
            print(rows[-1], flush=True)
        except Exception as e:
            fail += 1
            if dst.is_file():
                try:
                    dst.unlink()
                except OSError:
                    pass
            rows.append(f"FAIL {kind} {sid} {key} {e}")
            print(rows[-1], flush=True)

    # remove obvious typo empty/partial folders not in roster
    roster = {k for _, _, k in roster_keys()}
    for d in list(PACKS.iterdir()) if PACKS.is_dir() else []:
        if d.is_dir() and d.name not in roster and d.name.startswith(("am_", "jdl_", "glt_", "mmte_", "wrj_")):
            # only delete if clearly typo variants of existing keys
            typos = {
                "am_diyutienshi": "am_diyutianshi",
                "jdl_chaxun": "jdl_chasun",
                "jdl_youliong": "jdl_youlong",
            }
            if d.name in typos:
                shutil.rmtree(d, ignore_errors=True)
                rows.append(f"CLEAN typo_dir {d.name}")

    summary = f"done ok={ok} skip={skip} fail={fail}"
    rows.append(summary)
    REPORT.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(summary)
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
