"""Headless Blender import smoke test for the GR2 addon.

Run with:
    blender --background --python tools/blender_smoke_import.py -- file1.gr2 file2.gr2
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy  # type: ignore


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--max-meshes", type=int, default=16)
    parser.add_argument("--no-textures", action="store_true")
    parser.add_argument("--animation-path", default="")
    args = parser.parse_args(argv)

    import io_scene_gr2

    io_scene_gr2.register()
    results = []
    try:
        _clear_scene()
        for raw_path in args.paths:
            path = Path(raw_path)
            before = _counts()
            bpy.ops.import_scene.gr2_native(
                filepath=str(path),
                scale=args.scale,
                max_meshes=args.max_meshes,
                load_textures=not args.no_textures,
                animation_filepath=args.animation_path,
            )
            after = _counts()
            results.append(
                {
                    "path": str(path),
                    "delta": {key: after[key] - before[key] for key in after},
                    "actions": _action_summary(),
                    "armatures": _armature_summary(),
                    "meshes": _mesh_summary(),
                }
            )
            _clear_scene()
    finally:
        io_scene_gr2.unregister()

    print(json.dumps(results, indent=2, sort_keys=True))
    failures = [
        item
        for item in results
        if item["delta"]["objects"] <= 0 and item["delta"]["actions"] <= 0
    ]
    return 1 if failures else 0


def _counts() -> dict[str, int]:
    return {
        "actions": len(bpy.data.actions),
        "armatures": len(bpy.data.armatures),
        "meshes": len(bpy.data.meshes),
        "objects": len(bpy.data.objects),
    }


def _action_summary() -> list[dict[str, object]]:
    return [
        {
            "name": action.name,
            "fcurves": _action_fcurve_count(action),
            "frame_range": list(action.frame_range),
            "static_keyed_bones": action.get("gr2_static_keyed_bones"),
        }
        for action in bpy.data.actions
    ]


def _armature_summary() -> list[dict[str, object]]:
    return [
        {
            "name": armature.name,
            "bones": len(armature.bones),
        }
        for armature in bpy.data.armatures
    ]


def _mesh_summary() -> list[dict[str, object]]:
    return [
        {
            "name": mesh.name,
            "vertices": len(mesh.vertices),
            "polygons": len(mesh.polygons),
            "materials": len(mesh.materials),
        }
        for mesh in bpy.data.meshes
    ]


def _action_fcurve_count(action) -> int:
    if hasattr(action, "fcurves"):
        return len(action.fcurves)
    count = 0
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                count += len(bag.fcurves)
    return count


def _clear_scene() -> None:
    for datablock in (
        bpy.data.objects,
        bpy.data.meshes,
        bpy.data.armatures,
        bpy.data.actions,
        bpy.data.materials,
        bpy.data.images,
    ):
        for item in list(datablock):
            datablock.remove(item)


if __name__ == "__main__":
    script_args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    raise SystemExit(main(script_args))
