"""Mesh geometry extraction from loaded GR2 sections."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Iterable

from .fixup import LoadedGR2, PointerRef
from .material import MaterialInfo, material_map
from .types import (
    MT_BINORMAL_INT8,
    MT_BINORMAL_INT16,
    MT_INT16,
    MT_INT32,
    MT_INT8,
    MT_NORMAL_UINT8,
    MT_NORMAL_UINT16,
    MT_REAL32,
    MT_UINT16,
    MT_UINT32,
    MT_UINT8,
    TypeDefinition,
    parse_type_definition_array,
    read_reference_array_objects,
    summarize_meshes,
)


@dataclass(frozen=True)
class VertexComponent:
    name: str
    offset: int
    width: int
    member_type: int


@dataclass(frozen=True)
class BoneBinding:
    index: int
    name: str


@dataclass(frozen=True)
class VertexBoneWeight:
    bone_index: int
    weight: float


@dataclass(frozen=True)
class MeshTriangleGroup:
    material_index: int
    tri_first: int
    tri_count: int


@dataclass(frozen=True)
class MeshGeometry:
    name: str
    vertex_count: int
    index_count: int
    vertex_stride: int
    components: tuple[VertexComponent, ...]
    positions: tuple[tuple[float, float, float], ...]
    normals: tuple[tuple[float, float, float], ...]
    uvs: tuple[tuple[float, float], ...]
    indices: tuple[int, ...]
    bone_bindings: tuple[BoneBinding, ...]
    vertex_weights: tuple[tuple[VertexBoneWeight, ...], ...]
    materials: tuple[MaterialInfo, ...]
    triangle_groups: tuple[MeshTriangleGroup, ...]

    @property
    def triangles(self) -> tuple[tuple[int, int, int], ...]:
        usable = len(self.indices) - (len(self.indices) % 3)
        return tuple(
            (self.indices[index], self.indices[index + 1], self.indices[index + 2])
            for index in range(0, usable, 3)
        )

    @property
    def bounds(self) -> tuple[tuple[float, float, float], tuple[float, float, float]] | None:
        if not self.positions:
            return None
        mins = tuple(min(vertex[axis] for vertex in self.positions) for axis in range(3))
        maxs = tuple(max(vertex[axis] for vertex in self.positions) for axis in range(3))
        return mins, maxs


def extract_mesh_geometries(loaded: LoadedGR2, max_meshes: int = 32) -> tuple[MeshGeometry, ...]:
    summary = summarize_meshes(loaded, max_meshes=max_meshes)
    materials_by_ref = material_map(loaded)
    meshes: list[MeshGeometry] = []
    for mesh in summary.get("meshes", []):
        vertex_data = mesh.get("primary_vertex_data", {})
        topology = mesh.get("primary_topology", {})
        vertex_fields = _field_map(vertex_data)
        topology_fields = _field_map(topology)

        vertices = vertex_fields.get("Vertices", {})
        vertex_ref = _dict_ref(vertices.get("target"))
        vertex_type_ref = _dict_ref(vertices.get("variant_type"))
        vertex_count = int(vertices.get("count") or 0)
        if vertex_ref is None or vertex_type_ref is None or vertex_count <= 0:
            continue

        type_members = parse_type_definition_array(loaded, vertex_type_ref)
        components = _vertex_components(type_members)
        stride = _vertex_stride(components)
        try:
            vertex_bytes = loaded.read_ref(vertex_ref, vertex_count * stride, fixed=False)
        except ValueError:
            continue

        index_field = _best_index_field(topology_fields)
        index_ref = _dict_ref(index_field.get("target") if index_field else None)
        index_count = int(index_field.get("count") or 0) if index_field else 0
        index_member_type = _index_member_type(index_field, default=MT_UINT16)
        try:
            indices = _read_indices(loaded, index_ref, index_count, index_member_type)
        except ValueError:
            indices = ()

        bone_bindings = _read_bone_bindings(loaded, mesh)
        materials = _read_material_bindings(loaded, mesh, materials_by_ref)
        meshes.append(
            MeshGeometry(
                name=str(mesh.get("name") or f"Mesh_{len(meshes)}"),
                vertex_count=vertex_count,
                index_count=len(indices),
                vertex_stride=stride,
                components=components,
                positions=_read_float_component(vertex_bytes, vertex_count, stride, components, "Position", 3),
                normals=_read_float_component(vertex_bytes, vertex_count, stride, components, "Normal", 3),
                uvs=_read_float_component(
                    vertex_bytes,
                    vertex_count,
                    stride,
                    components,
                    "TextureCoordinates",
                    2,
                    prefix=True,
                ),
                indices=indices,
                bone_bindings=bone_bindings,
                vertex_weights=_read_vertex_weights(vertex_bytes, vertex_count, stride, components, len(bone_bindings)),
                materials=materials,
                triangle_groups=_read_triangle_groups(loaded, topology_fields),
            )
        )
    return tuple(meshes)


def geometry_summary(geometries: Iterable[MeshGeometry]) -> list[dict]:
    result = []
    for mesh in geometries:
        result.append(
            {
                "name": mesh.name,
                "vertex_count": mesh.vertex_count,
                "index_count": mesh.index_count,
                "triangle_count": len(mesh.triangles),
                "vertex_stride": mesh.vertex_stride,
                "components": [component.name for component in mesh.components],
                "bone_bindings": [binding.name for binding in mesh.bone_bindings],
                "materials": [
                    {"name": material.name, "texture_file": material.texture_file}
                    for material in mesh.materials
                ],
                "triangle_groups": [
                    {
                        "material_index": group.material_index,
                        "tri_first": group.tri_first,
                        "tri_count": group.tri_count,
                    }
                    for group in mesh.triangle_groups
                ],
                "bounds": mesh.bounds,
                "first_position": mesh.positions[0] if mesh.positions else None,
                "first_normal": mesh.normals[0] if mesh.normals else None,
                "first_uv": mesh.uvs[0] if mesh.uvs else None,
                "first_triangle": mesh.triangles[0] if mesh.triangles else None,
                "first_weights": [
                    {"bone": mesh.bone_bindings[item.bone_index].name, "weight": item.weight}
                    for item in (mesh.vertex_weights[0] if mesh.vertex_weights else ())
                    if item.bone_index < len(mesh.bone_bindings)
                ],
            }
        )
    return result


def _vertex_components(members: tuple[TypeDefinition, ...]) -> tuple[VertexComponent, ...]:
    components: list[VertexComponent] = []
    offset = 0
    for member in members:
        size = _component_size(member)
        components.append(
            VertexComponent(
                name=member.name,
                offset=offset,
                width=member.array_width or 1,
                member_type=member.member_type,
            )
        )
        offset += size
    return tuple(components)


def _vertex_stride(components: tuple[VertexComponent, ...]) -> int:
    if not components:
        return 0
    return max(component.offset + _component_storage_size(component) for component in components)


def _component_size(member: TypeDefinition) -> int:
    if member.member_type == MT_REAL32:
        return 4 * (member.array_width or 1)
    if member.member_type in (MT_INT32, MT_UINT32):
        return 4 * (member.array_width or 1)
    if member.member_type in (MT_INT16, MT_UINT16, MT_BINORMAL_INT16, MT_NORMAL_UINT16):
        return 2 * (member.array_width or 1)
    if member.member_type in (MT_INT8, MT_UINT8, MT_BINORMAL_INT8, MT_NORMAL_UINT8):
        return member.array_width or 1
    return 4 * (member.array_width or 1)


def _component_storage_size(component: VertexComponent) -> int:
    if component.member_type == MT_REAL32:
        return 4 * component.width
    if component.member_type in (MT_INT32, MT_UINT32):
        return 4 * component.width
    if component.member_type in (MT_INT16, MT_UINT16, MT_BINORMAL_INT16, MT_NORMAL_UINT16):
        return 2 * component.width
    if component.member_type in (MT_INT8, MT_UINT8, MT_BINORMAL_INT8, MT_NORMAL_UINT8):
        return component.width
    return 4 * component.width


def _read_float_component(
    data: bytes,
    vertex_count: int,
    stride: int,
    components: tuple[VertexComponent, ...],
    name: str,
    width: int,
    *,
    prefix: bool = False,
) -> tuple:
    component = next(
        (
            item
            for item in components
            if item.member_type == MT_REAL32
            and (item.name.startswith(name) if prefix else item.name == name)
            and item.width >= width
        ),
        None,
    )
    if component is None:
        return ()
    fmt = "<" + "f" * width
    values = []
    for index in range(vertex_count):
        offset = index * stride + component.offset
        if offset + width * 4 > len(data):
            break
        values.append(struct.unpack_from(fmt, data, offset))
    return tuple(values)


def _read_indices(
    loaded: LoadedGR2,
    ref: PointerRef | None,
    count: int,
    member_type: int,
) -> tuple[int, ...]:
    if ref is None or count <= 0:
        return ()
    if member_type in (MT_INT32, MT_UINT32):
        data = loaded.read_ref(ref, count * 4, fixed=False)
        return tuple(struct.unpack_from("<" + "I" * count, data, 0))
    data = loaded.read_ref(ref, count * 2, fixed=False)
    return tuple(struct.unpack_from("<" + "H" * count, data, 0))


def _read_bone_bindings(loaded: LoadedGR2, mesh: dict) -> tuple[BoneBinding, ...]:
    binding_field = _field_map({"fields": mesh.get("fields", [])}).get("BoneBindings")
    if not binding_field:
        return ()
    target = _dict_ref(binding_field.get("target"))
    type_ref = _dict_ref(binding_field.get("reference_type"))
    objects = read_reference_array_objects(
        loaded,
        target,
        int(binding_field.get("count") or 0),
        type_ref,
        max_count=4096,
    )
    bindings: list[BoneBinding] = []
    for index, obj in enumerate(objects):
        name = _field_map(obj).get("BoneName", {}).get("value")
        if isinstance(name, str) and name:
            bindings.append(BoneBinding(index=index, name=name))
        else:
            bindings.append(BoneBinding(index=index, name=f"Bone_{index}"))
    return tuple(bindings)


def _read_material_bindings(
    loaded: LoadedGR2,
    mesh: dict,
    materials_by_ref: dict[tuple[int, int], MaterialInfo],
) -> tuple[MaterialInfo, ...]:
    binding_field = _field_map({"fields": mesh.get("fields", [])}).get("MaterialBindings")
    if not binding_field:
        return ()
    target = _dict_ref(binding_field.get("target"))
    type_ref = _dict_ref(binding_field.get("reference_type"))
    objects = read_reference_array_objects(
        loaded,
        target,
        int(binding_field.get("count") or 0),
        type_ref,
        max_count=4096,
    )
    materials: list[MaterialInfo] = []
    for index, obj in enumerate(objects):
        material_ref = _dict_ref(_field_map(obj).get("Material", {}).get("target"))
        material = materials_by_ref.get((material_ref.section, material_ref.offset)) if material_ref else None
        materials.append(material or MaterialInfo(index=index, name=f"Material_{index}", texture_file="", texture_size=None))
    return tuple(materials)


def _read_triangle_groups(
    loaded: LoadedGR2,
    topology_fields: dict[str, dict],
) -> tuple[MeshTriangleGroup, ...]:
    group_field = topology_fields.get("Groups")
    if not group_field:
        return ()
    target = _dict_ref(group_field.get("target"))
    type_ref = _dict_ref(group_field.get("reference_type"))
    objects = read_reference_array_objects(
        loaded,
        target,
        int(group_field.get("count") or 0),
        type_ref,
        max_count=4096,
    )
    groups: list[MeshTriangleGroup] = []
    for obj in objects:
        fields = _field_map(obj)
        groups.append(
            MeshTriangleGroup(
                material_index=_field_int(fields, "MaterialIndex", 0),
                tri_first=_field_int(fields, "TriFirst", 0),
                tri_count=_field_int(fields, "TriCount", 0),
            )
        )
    return tuple(groups)


def _read_vertex_weights(
    data: bytes,
    vertex_count: int,
    stride: int,
    components: tuple[VertexComponent, ...],
    binding_count: int,
) -> tuple[tuple[VertexBoneWeight, ...], ...]:
    weights_component = _component_by_name(components, "BoneWeights")
    indices_component = _component_by_name(components, "BoneIndices")
    if weights_component is None or indices_component is None or binding_count <= 0:
        return ()

    width = min(weights_component.width, indices_component.width)
    vertices: list[tuple[VertexBoneWeight, ...]] = []
    for vertex_index in range(vertex_count):
        weights = []
        base = vertex_index * stride
        for lane in range(width):
            weight = _read_weight_value(data, base + weights_component.offset, lane, weights_component)
            bone_index = _read_int_value(data, base + indices_component.offset, lane, indices_component)
            if weight <= 0.0 or bone_index < 0 or bone_index >= binding_count:
                continue
            weights.append(VertexBoneWeight(bone_index=bone_index, weight=weight))
        vertices.append(tuple(weights))
    return tuple(vertices)


def _component_by_name(
    components: tuple[VertexComponent, ...],
    name: str,
) -> VertexComponent | None:
    return next((component for component in components if component.name == name), None)


def _read_weight_value(data: bytes, offset: int, lane: int, component: VertexComponent) -> float:
    if component.member_type == MT_REAL32:
        start = offset + lane * 4
        if start + 4 > len(data):
            return 0.0
        return max(0.0, min(1.0, struct.unpack_from("<f", data, start)[0]))
    if component.member_type in (MT_UINT16, MT_NORMAL_UINT16):
        start = offset + lane * 2
        if start + 2 > len(data):
            return 0.0
        value = struct.unpack_from("<H", data, start)[0]
        return value / 65535.0 if component.member_type == MT_NORMAL_UINT16 else float(value)
    if component.member_type in (MT_UINT8, MT_NORMAL_UINT8):
        start = offset + lane
        if start >= len(data):
            return 0.0
        value = data[start]
        return value / 255.0 if component.member_type == MT_NORMAL_UINT8 else float(value)
    return 0.0


def _read_int_value(data: bytes, offset: int, lane: int, component: VertexComponent) -> int:
    if component.member_type in (MT_INT32, MT_UINT32):
        start = offset + lane * 4
        if start + 4 > len(data):
            return -1
        fmt = "<i" if component.member_type == MT_INT32 else "<I"
        return int(struct.unpack_from(fmt, data, start)[0])
    if component.member_type in (MT_INT16, MT_UINT16):
        start = offset + lane * 2
        if start + 2 > len(data):
            return -1
        fmt = "<h" if component.member_type == MT_INT16 else "<H"
        return int(struct.unpack_from(fmt, data, start)[0])
    if component.member_type in (MT_INT8, MT_UINT8):
        start = offset + lane
        if start >= len(data):
            return -1
        if component.member_type == MT_INT8:
            return struct.unpack_from("<b", data, start)[0]
        return data[start]
    return -1


def _index_member_type(field: dict | None, *, default: int) -> int:
    if not field:
        return default
    if field.get("name") == "Indices":
        return MT_UINT32
    return default


def _best_index_field(topology_fields: dict[str, dict]) -> dict | None:
    indices16 = topology_fields.get("Indices16")
    indices32 = topology_fields.get("Indices")
    if indices16 and int(indices16.get("count") or 0) > 0:
        return indices16
    if indices32 and int(indices32.get("count") or 0) > 0:
        return indices32
    return indices16 or indices32


def _dict_ref(value: dict | None) -> PointerRef | None:
    if not value:
        return None
    return PointerRef(int(value["section"]), int(value["offset"]))


def _field_map(summary: dict) -> dict[str, dict]:
    return {field["name"]: field for field in summary.get("fields", [])}


def _field_int(fields: dict[str, dict], name: str, default: int) -> int:
    value = fields.get(name, {}).get("value")
    return default if value is None else int(value)
