#!/usr/bin/env python3
"""Smoke-test raw exporter inside Blender."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    args = _parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    import bpy  # type: ignore

    repo_root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(repo_root))
    import io_scene_gr2  # type: ignore

    io_scene_gr2.register()
    _make_test_scene(bpy)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gr2_native(filepath=str(args.output), selected_only=False)
    manifest_path = args.output.with_suffix(args.output.suffix + ".export.json")
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    from io_scene_gr2.gr2.file import read_gr2  # type: ignore
    from io_scene_gr2.gr2.fixup import load_sections  # type: ignore
    from io_scene_gr2.gr2.geometry import extract_mesh_geometries  # type: ignore

    exported = extract_mesh_geometries(load_sections(read_gr2(args.output)))
    print(
        json.dumps(
            {
                "result": sorted(result),
                "summary": payload["summary"],
                "reimport_meshes": len(exported),
                "reimport_vertices": sum(len(mesh.positions) for mesh in exported),
                "reimport_triangles": sum(len(mesh.triangles) for mesh in exported),
            },
            indent=2,
            sort_keys=True,
        )
    )
    assert payload["summary"]["mesh_count"] == 1
    assert payload["summary"]["vertex_count"] >= 3
    assert payload["summary"]["triangle_count"] == 1
    assert len(exported) == 1
    assert len(exported[0].positions) == 3
    assert len(exported[0].triangles) == 1
    return 0


def _make_test_scene(bpy) -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    mesh = bpy.data.meshes.new("ExportTriangleMesh")
    mesh.from_pydata(
        [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
        [],
        [(0, 1, 2)],
    )
    mesh.uv_layers.new(name="UVMap")
    for index, uv in enumerate(((0.0, 0.0), (1.0, 0.0), (0.0, 1.0))):
        mesh.uv_layers.active.data[index].uv = uv
    material = bpy.data.materials.new("ExportMaterial")
    mesh.materials.append(material)
    obj = bpy.data.objects.new("ExportTriangle", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("dist/export_smoke/test.gr2"))
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(main())
