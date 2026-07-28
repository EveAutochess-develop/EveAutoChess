# -*- coding: utf-8 -*-
"""Decimate OBJ/GLB meshes (~50% triangles) before Godot import."""
from __future__ import annotations

from pathlib import Path

import trimesh


def decimate_mesh_file(src: Path, dst: Path, ratio: float = 0.5) -> int:
    """Return output triangle count."""
    mesh = trimesh.load(src, force="mesh", process=False)
    if isinstance(mesh, trimesh.Scene):
        geoms = [g for g in mesh.geometry.values() if isinstance(g, trimesh.Trimesh)]
        if not geoms:
            raise RuntimeError(f"no mesh geometry in scene: {src}")
        mesh = trimesh.util.concatenate(geoms)
    if not isinstance(mesh, trimesh.Trimesh):
        raise RuntimeError(f"unsupported mesh type: {type(mesh)} from {src}")
    faces = len(mesh.faces)
    if faces < 8:
        dst.parent.mkdir(parents=True, exist_ok=True)
        mesh.export(dst)
        return faces
    target = max(4, int(faces * max(0.05, min(1.0, ratio))))
    if target >= faces:
        dst.parent.mkdir(parents=True, exist_ok=True)
        mesh.export(dst)
        return faces
    simplified = mesh.simplify_quadric_decimation(target)
    dst.parent.mkdir(parents=True, exist_ok=True)
    simplified.export(dst)
    return len(simplified.faces)
