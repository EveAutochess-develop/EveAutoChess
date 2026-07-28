# -*- coding: utf-8 -*-
"""Import EVE PC ship/unmanned .gr2 → decimated §0 GLB bundles + baked DDS maps.

This is the canonical importer for the PC asset pipeline. It consumes the
English-name canonical index and a verified PC GR2 mapping table, then keeps
the existing runtime contract unchanged:

  assets/models/ships/{model_key}/...
  data/visual_meshes.json
  data/ship_textures.json

Unmapped hulls are reported but skipped; no scenario-specific branches are
introduced for ships vs unmanned units.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
EVE_PC = TOOLS / "eve_pc"
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(EVE_PC))

from assimp_convert import AssimpError, convert as assimp_convert  # noqa: E402
from eve_pc.bake_pc_textures import bake_bundle_for_unit  # noqa: E402
from eve_pc.find_gr2 import DROP_IN, find_gr2  # noqa: E402
from eve_pc.gr2_convert import gr2_to_obj  # noqa: E402
from eve_pc.mesh_decimate import decimate_mesh_file  # noqa: E402
from ship_canonical_index import OUT as INDEX_JSON  # noqa: E402
from ship_canonical_index import build_index  # noqa: E402

GODOT = ROOT / "godot_project"
PACKS = GODOT / "assets" / "models" / "ships"
MESH_JSON = GODOT / "data" / "visual_meshes.json"
TEX_JSON = GODOT / "data" / "ship_textures.json"
REPORT = TOOLS / "_import_eve_pc_assets_report.txt"


def load_units() -> list[dict]:
    payload = build_index()
    return [payload["by_id"][key] for key in sorted(payload["by_id"], key=lambda x: int(x))]


def select_units(
    units: list[dict],
    *,
    kinds: set[str],
    ids: set[int],
    names: set[str],
    keys: set[str],
) -> list[dict]:
    selected: list[dict] = []
    for unit in units:
        if unit["kind"] not in kinds:
            continue
        if ids and int(unit["id"]) not in ids:
            continue
        if names and str(unit.get("name_en") or "") not in names:
            continue
        if keys and str(unit.get("model_key") or "") not in keys:
            continue
        selected.append(unit)
    return selected


def resolve_gr2(unit: dict) -> Path | None:
    model_key = str(unit.get("model_key") or "")
    return find_gr2(model_key, allow_fetch=True)


def import_mesh(unit: dict, *, decimate_ratio: float, dry_run: bool) -> str:
    model_key = str(unit["model_key"])
    ship_id = str(unit["id"])
    res_gr2 = str(unit.get("pc_res_path") or "")
    if not res_gr2:
        return f"MISS {ship_id} {model_key}: no verified pc_res_path for {unit.get('name_en')}"
    gr2 = resolve_gr2(unit)
    if gr2 is None:
        return (
            f"MISS {ship_id} {model_key}: no .gr2 "
            f"(need sharedcache or {DROP_IN / (model_key + '.gr2')}; expect {res_gr2})"
        )
    dst_dir = PACKS / model_key
    dst_glb = dst_dir / "model.glb"
    if dry_run:
        return f"DRY  {ship_id} {model_key} <= {gr2}"
    with tempfile.TemporaryDirectory(prefix="eve_pc_asset_") as td:
        work = Path(td)
        obj_raw = work / "raw.obj"
        obj_half = work / "half.obj"
        glb_tmp = work / "model.glb"
        gr2_to_obj(gr2, obj_raw)
        n_out = decimate_mesh_file(obj_raw, obj_half, decimate_ratio)
        assimp_convert(obj_half, glb_tmp, "glb2")
        if not glb_tmp.is_file() or glb_tmp.stat().st_size < 500:
            raise AssimpError(f"GLB too small for {model_key}")
        dst_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(glb_tmp, dst_glb)
        (dst_dir / "source_pc.txt").write_text(
            f"gr2={gr2}\npath={res_gr2}\ndecimate_ratio={decimate_ratio}\nfaces_out={n_out}\n",
            encoding="utf-8",
        )
    return f"OK   {ship_id} {model_key} <= {gr2} (faces~{n_out}) → {dst_glb}"


def refresh_runtime_maps(units: list[dict]) -> None:
    meshes = json.loads(MESH_JSON.read_text(encoding="utf-8"))
    tex = json.loads(TEX_JSON.read_text(encoding="utf-8"))
    mesh_map = meshes.setdefault("ships", {})
    tex_map = tex.setdefault("ships", {})
    for unit in units:
        sid = str(unit["id"])
        key = str(unit["model_key"])
        glb = PACKS / key / "model.glb"
        alb = PACKS / key / "albedo.png"
        if glb.is_file() and glb.stat().st_size > 500:
            mesh_map[sid] = f"res://assets/models/ships/{key}/model.glb"
        if alb.is_file() and alb.stat().st_size > 500:
            tex_map[sid] = f"res://assets/models/ships/{key}/albedo.png"
    MESH_JSON.write_text(json.dumps(meshes, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    TEX_JSON.write_text(json.dumps(tex, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="Import EVE PC ship/unmanned assets into §0 bundles")
    ap.add_argument("--kind", choices=["ship", "unmanned", "all"], default="all")
    ap.add_argument("--ids", nargs="*", type=int, default=[])
    ap.add_argument("--names", nargs="*", default=[])
    ap.add_argument("--keys", nargs="*", default=[])
    ap.add_argument("--decimate-ratio", type=float, default=0.5)
    ap.add_argument("--textures-only", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    units = load_units()
    kinds = {"ship", "unmanned"} if args.kind == "all" else {args.kind}
    selected = select_units(
        units,
        kinds=kinds,
        ids=set(args.ids),
        names=set(args.names),
        keys=set(args.keys),
    )
    lines: list[str] = [f"selected={len(selected)} index={INDEX_JSON}"]
    touched: list[dict] = []
    for unit in selected:
        ship_id = str(unit["id"])
        model_key = str(unit["model_key"])
        try:
            if args.textures_only:
                written = bake_bundle_for_unit(unit)
                line = f"TEX  {ship_id} {model_key}: {','.join(sorted(written))}"
            else:
                line = import_mesh(unit, decimate_ratio=args.decimate_ratio, dry_run=args.dry_run)
                if not args.dry_run and str(unit.get("pc_res_path") or ""):
                    written = bake_bundle_for_unit(unit)
                    if written:
                        line += f" | tex={','.join(sorted(written))}"
            touched.append(unit)
        except Exception as exc:
            line = f"FAIL {ship_id} {model_key}: {exc}"
        print(line)
        lines.append(line)
    if not args.dry_run:
        refresh_runtime_maps(touched)
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
