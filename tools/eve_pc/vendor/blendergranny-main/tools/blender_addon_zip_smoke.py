#!/usr/bin/env python3
"""Install addon zip in Blender and run a path-free import smoke test."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    args = _parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    import bpy  # type: ignore

    zip_path = args.addon_zip.resolve()
    if not zip_path.is_file():
        raise SystemExit(f"missing addon zip: {zip_path}")

    bpy.ops.preferences.addon_install(filepath=str(zip_path), overwrite=True)
    bpy.ops.preferences.addon_enable(module="io_scene_gr2")

    result = {
        "addon_zip": str(zip_path),
        "addon_enabled": "io_scene_gr2" in bpy.context.preferences.addons,
        "imports": [],
    }

    for path in args.paths:
        _clear_scene(bpy)
        kwargs = {
            "filepath": str(path),
            "load_textures": False,
        }
        if args.animation_path:
            kwargs["animation_filepath"] = str(args.animation_path)
        op_result = bpy.ops.import_scene.gr2_native(**kwargs)
        result["imports"].append(
            {
                "path": str(path),
                "result": sorted(op_result),
                "meshes": len(bpy.data.meshes),
                "armatures": len(bpy.data.armatures),
                "actions": len(bpy.data.actions),
                "objects": len(bpy.data.objects),
            }
        )

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["addon_enabled"] else 1


def _clear_scene(bpy) -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for collection_name in ("meshes", "armatures", "actions", "materials", "images"):
        collection = getattr(bpy.data, collection_name)
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)
    if hasattr(bpy.ops.outliner, "orphans_purge"):
        try:
            bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
        except Exception:
            pass


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon-zip", type=Path, required=True)
    parser.add_argument("--animation-path", type=Path)
    parser.add_argument("paths", nargs="+", type=Path)
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(main())
