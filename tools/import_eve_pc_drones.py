# -*- coding: utf-8 -*-

"""Import EVE PC drone .gr2 → decimated §0 GLB bundles + PC DDS textures for Godot.



Mesh prerequisites (one of):

  1. EVE launcher with sharedcache populated, or CDN fetch via resfile_index

  2. Drop .gr2 files into tools/eve_pc/gr2_in/{model_key}.gr2

  3. 64-bit granny2.dll + evegr2toobj_x64.exe in tools/eve_pc/

     (legacy 32-bit evegr2toobj_legacy/ cannot read ptr64 Tranquility gr2)



Textures are always baked from EVE CDN/local ResFiles:

  *_a.dds → albedo.png, *_n.dds → normal.png, *_r/_g → rg.png,

  *_m/_d → pmwo.png + reduction.png (echoes_spaceobject shader)



Usage:

  python tools/import_eve_pc_drones.py

  python tools/import_eve_pc_drones.py --textures-only

  python tools/import_eve_pc_drones.py --keys wrj_a_shentouzhe wrj_j_jinxing

  python tools/import_eve_pc_drones.py --decimate-ratio 0.5

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

from eve_pc.bake_pc_textures import bake_bundle  # noqa: E402

from eve_pc.find_gr2 import DROP_IN, find_gr2, search_roots  # noqa: E402

from eve_pc.gr2_convert import Gr2ConvertError, gr2_to_obj  # noqa: E402

from eve_pc.mesh_decimate import decimate_mesh_file  # noqa: E402

from eve_pc.pc_drone_map import PC_DRONE_GR2  # noqa: E402



GODOT = ROOT / "godot_project"

UNMANNED = GODOT / "data" / "unmanned_units"

PACKS = GODOT / "assets" / "models" / "ships"

MESH_JSON = GODOT / "data" / "visual_meshes.json"

REPORT = TOOLS / "_import_eve_pc_drones_report.txt"





def roster_keys(filter_keys: list[str] | None) -> list[tuple[str, str]]:

    """[(ship_id, model_key), ...] from unmanned_units JSON."""

    out: list[tuple[str, str]] = []

    for f in sorted(UNMANNED.glob("*.json")):

        if f.name == "DRONE_BUCKETS.md":

            continue

        j = json.loads(f.read_text(encoding="utf-8"))

        key = (j.get("model_key") or "").strip()

        sid = str(j.get("id") or f.stem)

        if not key:

            continue

        if filter_keys and key not in filter_keys:

            continue

        if key not in PC_DRONE_GR2:

            continue

        out.append((sid, key))

    return out





def resolve_gr2(model_key: str) -> Path | None:

    return find_gr2(model_key, allow_fetch=True)





def bake_textures(model_key: str) -> str:

    written = bake_bundle(model_key)

    return f"TEX  {model_key} maps={','.join(sorted(written))}"





def import_mesh(

    ship_id: str,

    model_key: str,

    *,

    decimate_ratio: float,

    dry_run: bool,

) -> str:

    gr2 = resolve_gr2(model_key)

    if gr2 is None:

        rel = PC_DRONE_GR2[model_key]

        return (

            f"MISS {ship_id} {model_key}: no .gr2 "

            f"(need sharedcache or {DROP_IN / (model_key + '.gr2')}; expect {rel})"

        )

    dst_dir = PACKS / model_key

    dst_glb = dst_dir / "model.glb"

    if dry_run:

        return f"DRY  {ship_id} {model_key} <= {gr2}"

    with tempfile.TemporaryDirectory(prefix="eve_pc_drone_") as td:

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

            f"gr2={gr2}\npath={PC_DRONE_GR2[model_key]}\ndecimate_ratio={decimate_ratio}\nfaces_out={n_out}\n",

            encoding="utf-8",

        )

    return f"OK   {ship_id} {model_key} <= {gr2} (faces~{n_out}) → {dst_glb}"





def patch_visual_meshes(entries: list[tuple[str, str]]) -> None:

    data = json.loads(MESH_JSON.read_text(encoding="utf-8"))

    ships = data.setdefault("ships", {})

    for sid, key in entries:

        path = f"res://assets/models/ships/{key}/model.glb"

        ships[sid] = path

    MESH_JSON.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")





def main() -> int:

    ap = argparse.ArgumentParser(description="Import EVE PC drone models into §0 GLB bundles")

    ap.add_argument("--keys", nargs="*", help="model_key subset (default: all mapped unmanned_units)")

    ap.add_argument("--decimate-ratio", type=float, default=0.5, help="triangle ratio after import (default 0.5)")

    ap.add_argument("--textures-only", action="store_true", help="only bake DDS → §0 PNG maps")

    ap.add_argument("--dry-run", action="store_true")

    ap.add_argument("--list-roots", action="store_true", help="print gr2 search roots and exit")

    args = ap.parse_args()



    if args.list_roots:

        for r in search_roots():

            print(r)

        return 0



    roster = roster_keys(args.keys or None)

    if not roster:

        print("No unmanned_units entries match PC_DRONE_GR2.", file=sys.stderr)

        return 1



    rows: list[str] = []

    ok = miss = fail = tex_ok = 0

    imported: list[tuple[str, str]] = []

    for sid, key in roster:

        try:

            if not args.dry_run:

                rows.append(bake_textures(key))

                tex_ok += 1

        except Exception as exc:

            fail += 1

            rows.append(f"TEXFAIL {sid} {key}: {exc}")



        if args.textures_only:

            continue



        try:

            row = import_mesh(

                sid,

                key,

                decimate_ratio=args.decimate_ratio,

                dry_run=args.dry_run,

            )

            rows.append(row)

            if row.startswith("OK"):

                ok += 1

                imported.append((sid, key))

            elif row.startswith("MISS"):

                miss += 1

            else:

                ok += 1

        except Gr2ConvertError as exc:

            fail += 1

            rows.append(f"GR2  {sid} {key}: {exc}")

        except Exception as exc:

            fail += 1

            rows.append(f"FAIL {sid} {key}: {exc}")



    if imported and not args.dry_run and not args.textures_only:

        patch_visual_meshes(imported)



    header = [

        f"roots={len(search_roots())} textures_baked={tex_ok}",

        f"decimate_ratio={args.decimate_ratio} textures_only={args.textures_only}",

        f"mesh_ok={ok} miss={miss} fail={fail}",

        "",

    ]

    REPORT.write_text("\n".join(header + rows) + "\n", encoding="utf-8")

    print("\n".join(header + rows))

    print(f"\nReport: {REPORT}")

    if miss and not args.textures_only:

        print(

            f"\nHint: ensure gr2 is cached under {DROP_IN} or H:\\EVE\\ResFiles,\n"

            f"and install 64-bit granny2.dll + converter in {EVE_PC}.",

            file=sys.stderr,

        )

    return 0 if fail == 0 else 2





if __name__ == "__main__":

    raise SystemExit(main())

