"""Blender scene collection for future GR2 export writers."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class ExportVertexWeight:
    bone: str
    weight: float


@dataclass(frozen=True)
class ExportVertex:
    position: tuple[float, float, float]
    normal: tuple[float, float, float]
    uv: tuple[float, float] | None
    weights: tuple[ExportVertexWeight, ...]


@dataclass(frozen=True)
class ExportMesh:
    name: str
    vertices: tuple[ExportVertex, ...]
    indices: tuple[int, ...]
    material_names: tuple[str, ...]
    material_indices: tuple[int, ...] = ()
    material_texture_files: tuple[str, ...] = ()
    material_texture_sizes: tuple[tuple[int, int] | None, ...] = ()
    bone_binding_names: tuple[str, ...] = ()

    @property
    def triangle_count(self) -> int:
        return len(self.indices) // 3


@dataclass(frozen=True)
class ExportBone:
    name: str
    parent: str
    matrix_local: tuple[float, ...]
    granny_rest_local: tuple[float, ...] = ()
    inverse_world_transform: tuple[float, ...] = ()
    granny_transform_flags: int = 0
    granny_local_position: tuple[float, ...] = ()
    granny_local_orientation_xyzw: tuple[float, ...] = ()


@dataclass(frozen=True)
class ExportSkeleton:
    name: str
    bones: tuple[ExportBone, ...]
    initial_placement: tuple[float, ...] = ()


@dataclass(frozen=True)
class ExportScene:
    meshes: tuple[ExportMesh, ...]
    skeletons: tuple[ExportSkeleton, ...]

    @property
    def mesh_count(self) -> int:
        return len(self.meshes)

    @property
    def skeleton_count(self) -> int:
        return len(self.skeletons)

    @property
    def vertex_count(self) -> int:
        return sum(len(mesh.vertices) for mesh in self.meshes)

    @property
    def triangle_count(self) -> int:
        return sum(mesh.triangle_count for mesh in self.meshes)


def collect_export_scene(
    context,
    *,
    selected_only: bool = True,
    apply_modifiers: bool = False,
    scale: float = 1.0,
    flip_uv_v: bool = True,
) -> ExportScene:
    """Collect Blender data into writer-ready, Blender-free dataclasses."""

    objects = _export_objects(context, selected_only=selected_only)
    mesh_objects = [obj for obj in objects if getattr(obj, "type", None) == "MESH"]
    armatures = _referenced_armatures(mesh_objects)
    armatures.extend(obj for obj in objects if getattr(obj, "type", None) == "ARMATURE" and obj not in armatures)
    return ExportScene(
        meshes=tuple(
            _collect_mesh(context, obj, apply_modifiers=apply_modifiers, scale=scale, flip_uv_v=flip_uv_v)
            for obj in mesh_objects
        ),
        skeletons=tuple(_collect_skeleton(obj) for obj in armatures),
    )


def write_export_manifest(path: str | Path, scene: ExportScene) -> Path:
    """Write exporter manifest used to verify raw-writer inputs."""

    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "format": "blendergranny.export_manifest.v1",
        "exporter_schema": 2,
        "summary": {
            "mesh_count": scene.mesh_count,
            "skeleton_count": scene.skeleton_count,
            "vertex_count": scene.vertex_count,
            "triangle_count": scene.triangle_count,
        },
        "scene": asdict(scene),
    }
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    return output_path


def _export_objects(context, *, selected_only: bool) -> list:
    if selected_only:
        selected = list(getattr(context, "selected_objects", ()))
        if selected:
            return selected
    return [obj for obj in context.scene.objects if not getattr(obj, "hide_get", lambda: False)()]


def _collect_mesh(context, obj, *, apply_modifiers: bool, scale: float, flip_uv_v: bool) -> ExportMesh:
    depsgraph = context.evaluated_depsgraph_get() if apply_modifiers else None
    eval_obj = obj.evaluated_get(depsgraph) if depsgraph is not None else obj
    mesh = eval_obj.to_mesh() if depsgraph is not None else obj.data
    try:
        mesh.calc_loop_triangles()
        uv_layer = mesh.uv_layers.active.data if mesh.uv_layers.active else None
        vertices: list[ExportVertex] = []
        indices: list[int] = []
        material_indices: list[int] = []
        vertex_cache: dict[tuple, int] = {}
        for triangle in mesh.loop_triangles:
            material_indices.append(int(triangle.material_index))
            for loop_index in triangle.loops:
                loop = mesh.loops[loop_index]
                source_vertex = mesh.vertices[loop.vertex_index]
                uv = None
                if uv_layer is not None:
                    raw_uv = uv_layer[loop_index].uv
                    uv = (float(raw_uv.x), float(1.0 - raw_uv.y) if flip_uv_v else float(raw_uv.y))
                vertex = ExportVertex(
                    position=_scaled_tuple(source_vertex.co, scale),
                    normal=_float_tuple(loop.normal, 3),
                    uv=uv,
                    weights=_vertex_weights(obj, source_vertex.index, source_vertex.co),
                )
                key = _vertex_key(vertex)
                index = vertex_cache.get(key)
                if index is None:
                    index = len(vertices)
                    vertex_cache[key] = index
                    vertices.append(vertex)
                indices.append(index)
        return ExportMesh(
            name=obj.name,
            vertices=tuple(vertices),
            indices=tuple(indices),
            material_names=tuple(_material_names(mesh.materials)),
            material_indices=tuple(material_indices),
            material_texture_files=tuple(_material_texture_files(mesh.materials)),
            material_texture_sizes=tuple(_material_texture_sizes(mesh.materials)),
            bone_binding_names=_stored_bone_bindings(obj),
        )
    finally:
        if depsgraph is not None:
            eval_obj.to_mesh_clear()


def _vertex_weights(obj, vertex_index: int, position=None) -> tuple[ExportVertexWeight, ...]:
    groups = []
    vertex_groups = obj.vertex_groups
    for item in obj.data.vertices[vertex_index].groups:
        if item.weight <= 0.0 or item.group >= len(vertex_groups):
            continue
        groups.append(ExportVertexWeight(vertex_groups[item.group].name, float(item.weight)))
    groups.sort(key=lambda item: item.weight, reverse=True)
    total = sum(item.weight for item in groups[:4])
    if total <= 0.0:
        fallback_bone = _rigid_mesh_fallback_bone(obj, position)
        return (ExportVertexWeight(fallback_bone, 1.0),) if fallback_bone else ()
    return tuple(ExportVertexWeight(item.bone, item.weight / total) for item in groups[:4])


def _rigid_mesh_fallback_bone(obj, position=None) -> str:
    name = getattr(obj, "name", "").lower()
    armature = _object_armature(obj)
    if armature is None:
        return ""
    bones = getattr(getattr(armature, "data", None), "bones", {})
    if "face" in name or "head" in name:
        for preferred in ("Bip01 Head", "Head", "head"):
            if preferred in bones:
                return preferred
        for bone in bones:
            if "head" in bone.name.lower():
                return bone.name
    if position is not None:
        best_name = ""
        best_distance = None
        for bone in bones:
            head = getattr(bone, "head_local", None)
            if head is None:
                continue
            dx = float(position.x) - float(head.x)
            dy = float(position.y) - float(head.y)
            dz = float(position.z) - float(head.z)
            distance = dx * dx + dy * dy + dz * dz
            if best_distance is None or distance < best_distance:
                best_name = bone.name
                best_distance = distance
        if best_name:
            return best_name
    return ""


def _object_armature(obj):
    for modifier in getattr(obj, "modifiers", ()):
        if modifier.type == "ARMATURE" and modifier.object is not None:
            return modifier.object
    return None


def _referenced_armatures(mesh_objects: Iterable) -> list:
    armatures = []
    for obj in mesh_objects:
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE" and modifier.object is not None and modifier.object not in armatures:
                armatures.append(modifier.object)
    return armatures


def _collect_skeleton(obj) -> ExportSkeleton:
    bones = tuple(
        ExportBone(
            name=bone.name,
            parent=bone.parent.name if bone.parent else "",
            matrix_local=_matrix_tuple(bone.matrix_local),
            granny_rest_local=_prop_tuple(bone, "gr2_granny_rest_local", 16),
            inverse_world_transform=_prop_tuple(bone, "gr2_inverse_world_transform", 16),
            granny_transform_flags=_pose_prop_int(obj, bone.name, "gr2_transform_flags"),
            granny_local_position=_pose_prop_tuple(obj, bone.name, "gr2_local_position", 3),
            granny_local_orientation_xyzw=_pose_prop_tuple(obj, bone.name, "gr2_local_orientation_xyzw", 4),
        )
        for bone in obj.data.bones
    )
    return ExportSkeleton(
        name=obj.name,
        bones=bones,
        initial_placement=_skeleton_initial_placement(bones),
    )


def _material_names(materials) -> list[str]:
    names = []
    for index, material in enumerate(materials):
        names.append(material.name if material is not None else f"Material_{index}")
    return names


def _material_texture_files(materials) -> list[str]:
    return [_material_texture_file(material) if material is not None else "" for material in materials]


def _material_texture_sizes(materials) -> list[tuple[int, int] | None]:
    return [_material_texture_size(material) if material is not None else None for material in materials]


def _stored_bone_bindings(obj) -> tuple[str, ...]:
    value = obj.get("gr2_bone_bindings") if hasattr(obj, "get") else None
    if not value:
        return ()
    names = []
    for item in str(value).split(","):
        name = item.strip()
        if name and name not in names:
            names.append(name)
    return tuple(names)


def _material_texture_file(material) -> str:
    for key in ("gr2_texture_file", "gr2_texture_resolved"):
        value = material.get(key)
        if value:
            return str(value)
    if getattr(material, "use_nodes", False) and material.node_tree is not None:
        for node in material.node_tree.nodes:
            image = getattr(node, "image", None)
            if getattr(node, "type", "") == "TEX_IMAGE" and image is not None:
                filepath = getattr(image, "filepath", "")
                return str(filepath or getattr(image, "name", ""))
    return ""


def _material_texture_size(material) -> tuple[int, int] | None:
    width = material.get("gr2_texture_width")
    height = material.get("gr2_texture_height")
    if width is not None and height is not None:
        return int(width), int(height)
    if getattr(material, "use_nodes", False) and material.node_tree is not None:
        for node in material.node_tree.nodes:
            image = getattr(node, "image", None)
            if getattr(node, "type", "") == "TEX_IMAGE" and image is not None and len(image.size) >= 2:
                return int(image.size[0]), int(image.size[1])
    return None


def _scaled_tuple(vector, scale: float) -> tuple[float, float, float]:
    return (float(vector.x) * scale, float(vector.y) * scale, float(vector.z) * scale)


def _float_tuple(vector, width: int) -> tuple[float, ...]:
    return tuple(float(vector[index]) for index in range(width))


def _matrix_tuple(matrix) -> tuple[float, ...]:
    return tuple(float(matrix[row][column]) for row in range(4) for column in range(4))


def _prop_tuple(item, name: str, count: int) -> tuple[float, ...]:
    value = item.get(name)
    if value is None or len(value) != count:
        return ()
    return tuple(float(item) for item in value)


def _pose_prop_tuple(obj, bone_name: str, name: str, count: int) -> tuple[float, ...]:
    pose_bone = getattr(getattr(obj, "pose", None), "bones", {}).get(bone_name)
    if pose_bone is None:
        return ()
    return _prop_tuple(pose_bone, name, count)


def _pose_prop_int(obj, bone_name: str, name: str) -> int:
    pose_bone = getattr(getattr(obj, "pose", None), "bones", {}).get(bone_name)
    if pose_bone is None:
        return 0
    value = pose_bone.get(name)
    return int(value) if value is not None else 0


def _skeleton_initial_placement(bones: tuple[ExportBone, ...]) -> tuple[float, ...]:
    for bone in bones:
        if bone.parent:
            continue
        if bone.granny_local_position and bone.granny_local_orientation_xyzw:
            return bone.matrix_local
        break
    return ()


def _vertex_key(vertex: ExportVertex) -> tuple:
    weights = tuple((item.bone, round(item.weight, 8)) for item in vertex.weights)
    uv = None if vertex.uv is None else tuple(round(value, 8) for value in vertex.uv)
    return (
        tuple(round(value, 8) for value in vertex.position),
        tuple(round(value, 8) for value in vertex.normal),
        uv,
        weights,
    )
