"""Minimal raw GR2 writer."""

from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

from .constants import (
    COMPRESSION_NONE,
    MAGIC_32LE,
    MAGIC_SIZE,
    SECTION_RECORD_SIZE,
)
from .export import ExportScene
from .fixup import PointerRef
from .types import (
    MT_ARRAY_OF_REFERENCES,
    MT_END,
    MT_INT16,
    MT_INT32,
    MT_NORMAL_UINT8,
    MT_REAL32,
    MT_REFERENCE,
    MT_REFERENCE_TO_ARRAY,
    MT_REFERENCE_TO_VARIANT_ARRAY,
    MT_STRING,
    MT_TRANSFORM,
    MT_UINT8,
    MT_UINT16,
    MT_UINT32,
    MT_VARIANT_REFERENCE,
)


SECTION_COUNT = 8
HEADER_SIZE = 72
SECTION_ARRAY_OFFSET = HEADER_SIZE
DATA_START = MAGIC_SIZE + HEADER_SIZE + SECTION_COUNT * SECTION_RECORD_SIZE
TYPE_TAG = 0x80000037


@dataclass(frozen=True)
class _Fixup:
    source: PointerRef
    target: PointerRef


@dataclass
class _SectionBuilder:
    index: int
    data: bytearray
    fixups: list[_Fixup]
    internal_alignment: int = 4

    def tell(self) -> int:
        return len(self.data)

    def align(self, amount: int = 4) -> None:
        while len(self.data) % amount:
            self.data.append(0)

    def reserve(self, size: int, *, align: int = 4) -> int:
        self.align(align)
        offset = len(self.data)
        self.data.extend(b"\x00" * size)
        return offset

    def u32(self, value: int) -> int:
        offset = len(self.data)
        self.data.extend(struct.pack("<I", value))
        return offset

    def f32(self, value: float) -> int:
        offset = len(self.data)
        self.data.extend(struct.pack("<f", float(value)))
        return offset

    def bytes(self, value: bytes, *, align: int = 4) -> int:
        self.align(align)
        offset = len(self.data)
        self.data.extend(value)
        return offset

    def c_string(self, value: str) -> int:
        raw = value.encode("utf-8", "replace") + b"\x00"
        return self.bytes(raw, align=1)

    def pointer_to(self, source_offset: int, target: PointerRef) -> None:
        self.fixups.append(_Fixup(PointerRef(self.index, source_offset), target))

    def patch_pointer(self, source_offset: int, target: PointerRef) -> None:
        struct.pack_into("<I", self.data, source_offset, 0)
        self.pointer_to(source_offset, target)


class _TypeWriter:
    def __init__(self, section: _SectionBuilder):
        self.section = section
        self.type_offsets: dict[str, int] = {}
        self.string_offsets: dict[str, int] = {}
        self.entries: list[tuple[str, tuple[tuple[int, str, str, int], ...]]] = []

    def add(self, name: str, members: tuple[tuple[int, str, str, int], ...]) -> None:
        self.type_offsets[name] = self.section.reserve((len(members) + 1) * 32)
        self.entries.append((name, members))

    def finish(self) -> None:
        for type_name, members in self.entries:
            base = self.type_offsets[type_name]
            for index, (member_type, name, ref_type, width) in enumerate(members):
                offset = base + index * 32
                name_ptr = offset + 4
                type_ptr = offset + 8
                struct.pack_into("<I", self.section.data, offset, member_type)
                self.section.patch_pointer(name_ptr, PointerRef(self.section.index, self._string(name)))
                if ref_type:
                    self.section.patch_pointer(type_ptr, PointerRef(self.section.index, self.type_offsets[ref_type]))
                struct.pack_into("<I", self.section.data, offset + 12, width or 1)
            struct.pack_into("<I", self.section.data, base + len(members) * 32, MT_END)

    def _string(self, value: str) -> int:
        offset = self.string_offsets.get(value)
        if offset is None:
            offset = self.section.c_string(value)
            self.string_offsets[value] = offset
        return offset


def write_raw_gr2(path: str | Path, scene: ExportScene) -> Path:
    """Write uncompressed mesh-only GR2 that this addon can re-import."""

    if not scene.meshes:
        raise ValueError("cannot export GR2 with no meshes")
    sections = [_SectionBuilder(index, bytearray(), []) for index in range(SECTION_COUNT)]
    main = sections[0]
    skeleton_bone_names = tuple(bone.name for bone in scene.skeletons[0].bones) if scene.skeletons else ()
    mesh_bone_binding_plan = tuple(_mesh_bone_bindings(mesh, skeleton_bone_names) for mesh in scene.meshes)
    all_rigid = all(not bone_bindings for bone_bindings in mesh_bone_binding_plan)
    vertex_section = main if all_rigid else sections[3]
    index_section = main if all_rigid else sections[4]
    if not all_rigid:
        vertex_section.internal_alignment = 32
    type_section = sections[6]
    type_writer = _build_type_tree(type_section)

    materials = _scene_materials(scene)

    root_offset = main.reserve(92)
    art_tool_info_ref = PointerRef(0, main.reserve(76))
    exporter_info_ref = PointerRef(0, main.reserve(28))
    texture_root_ref_array_offset = main.reserve(4 * len([material for material in materials if material[1]]))
    skeleton_ref_array_offset = main.reserve(4 * len(scene.skeletons))
    material_ref_array_offset = main.reserve(4 * len(materials))
    vertex_data_ref_array_offset = main.reserve(4 * len(scene.meshes))
    topology_ref_array_offset = main.reserve(4 * len(scene.meshes))
    mesh_ref_array_offset = main.reserve(4 * len(scene.meshes))
    model_ref_array_offset = main.reserve(4)
    skeleton_refs: list[PointerRef] = []
    bone_array_refs: list[PointerRef] = []
    material_refs: list[PointerRef] = []
    texture_refs: list[PointerRef | None] = []
    mesh_refs: list[PointerRef] = []
    model_ref = PointerRef(0, 0)
    model_mesh_binding_ref = PointerRef(0, 0)
    vertex_data_refs: list[PointerRef] = []
    topology_refs: list[PointerRef] = []
    material_binding_refs: list[PointerRef] = []
    triangle_group_refs: list[PointerRef] = []
    bone_binding_refs: list[PointerRef] = []
    mesh_bounds_refs: list[PointerRef] = []
    vertex_component_array_refs: list[PointerRef] = []
    vertex_component_object_refs: list[list[PointerRef]] = []
    topology_map_refs: list[tuple[PointerRef, PointerRef, PointerRef]] = []
    bone_bindings_by_mesh: list[tuple[str, ...]] = []
    vertex_offsets: list[int] = []
    index_offsets: list[int] = []
    index32_flags: list[bool] = []

    for mesh, bone_bindings in zip(scene.meshes, mesh_bone_binding_plan):
        bone_bindings_by_mesh.append(bone_bindings)
        vertex_offsets.append(_write_vertices(vertex_section, mesh, bone_bindings))
        index_offsets.append(_write_indices(index_section, mesh))
        index32_flags.append(_uses_32bit_indices(mesh))

    for skeleton in scene.skeletons:
        bone_array_refs.append(PointerRef(0, main.reserve(140 * len(skeleton.bones))))
        skeleton_refs.append(PointerRef(0, main.reserve(16)))

    for material in materials:
        material_refs.append(PointerRef(0, main.reserve(16)))
        if material[1]:
            texture_refs.append(PointerRef(0, main.reserve(16)))
        else:
            texture_refs.append(None)

    for mesh in scene.meshes:
        vertex_data_refs.append(PointerRef(0, main.reserve(28)))
        topology_refs.append(PointerRef(0, main.reserve(72)))
        triangle_group_refs.append(PointerRef(0, main.reserve(12 * len(_triangle_groups(mesh)))))
        material_binding_refs.append(PointerRef(0, main.reserve(4 * len(mesh.material_names))))
        bone_binding_refs.append(PointerRef(0, main.reserve(36 * max(1, len(bone_bindings_by_mesh[len(bone_binding_refs)])))))
        mesh_bounds_refs.append(PointerRef(0, main.reserve(24)))
        component_names = _vertex_component_names(bone_bindings_by_mesh[len(vertex_component_array_refs)])
        vertex_component_array_refs.append(PointerRef(0, main.reserve(4 * len(component_names))))
        vertex_component_object_refs.append([PointerRef(0, main.reserve(4)) for _ in component_names])
        topology_map_refs.append((PointerRef(0, 0), PointerRef(0, 0), PointerRef(0, 0)))
        mesh_refs.append(PointerRef(0, main.reserve(44)))
    model_mesh_binding_ref = PointerRef(0, main.reserve(4 * len(scene.meshes)))
    model_ref = PointerRef(0, main.reserve(92))

    from_file_name = Path(path).name
    from_file_offset = main.c_string(from_file_name)
    main.patch_pointer(root_offset, art_tool_info_ref)
    main.patch_pointer(root_offset + 4, exporter_info_ref)
    main.patch_pointer(root_offset + 8, PointerRef(0, from_file_offset))
    _write_art_tool_info(main, art_tool_info_ref.offset)
    _write_exporter_info(main, exporter_info_ref.offset)
    root_texture_refs = [] if all_rigid else [texture_ref for texture_ref in texture_refs if texture_ref is not None]
    root_material_refs = [] if all_rigid else material_refs
    root_vertex_data_refs = [] if all_rigid else vertex_data_refs
    root_topology_refs = [] if all_rigid else topology_refs
    root_model_refs_count = 0 if all_rigid else 1
    _patch_reference_array_or_empty(main, root_offset + 12, len(root_texture_refs), PointerRef(0, texture_root_ref_array_offset))
    _patch_reference_array_or_empty(main, root_offset + 20, len(root_material_refs), PointerRef(0, material_ref_array_offset))
    _patch_reference_array_or_empty(main, root_offset + 28, len(skeleton_refs), PointerRef(0, skeleton_ref_array_offset))
    _patch_reference_array_or_empty(main, root_offset + 36, len(root_vertex_data_refs), PointerRef(0, vertex_data_ref_array_offset))
    _patch_reference_array_or_empty(main, root_offset + 44, len(root_topology_refs), PointerRef(0, topology_ref_array_offset))
    _patch_reference_array_or_empty(main, root_offset + 52, len(mesh_refs), PointerRef(0, mesh_ref_array_offset))
    _patch_reference_array_or_empty(main, root_offset + 60, root_model_refs_count, PointerRef(0, model_ref_array_offset))
    struct.pack_into("<IIIIII", main.data, root_offset + 68, 0, 0, 0, 0, 0, 0)
    for index, texture_ref in enumerate(root_texture_refs):
        main.patch_pointer(texture_root_ref_array_offset + index * 4, texture_ref)
    for index, skeleton_ref in enumerate(skeleton_refs):
        main.patch_pointer(skeleton_ref_array_offset + index * 4, skeleton_ref)
    for index, material_ref in enumerate(root_material_refs):
        main.patch_pointer(material_ref_array_offset + index * 4, material_ref)
    for index, vertex_data_ref in enumerate(root_vertex_data_refs):
        main.patch_pointer(vertex_data_ref_array_offset + index * 4, vertex_data_ref)
    for index, topology_ref in enumerate(root_topology_refs):
        main.patch_pointer(topology_ref_array_offset + index * 4, topology_ref)
    for index, mesh_ref in enumerate(mesh_refs):
        main.patch_pointer(mesh_ref_array_offset + index * 4, mesh_ref)
        main.patch_pointer(model_mesh_binding_ref.offset + index * 4, mesh_ref)
    if root_model_refs_count:
        main.patch_pointer(model_ref_array_offset, model_ref)

    for index, skeleton in enumerate(scene.skeletons):
        _write_bones(main, bone_array_refs[index].offset, skeleton, root_identity=bool(skeleton.initial_placement))
        _write_skeleton(main, skeleton_refs[index].offset, skeleton, bone_array_refs[index])

    for index, material in enumerate(materials):
        texture_ref = texture_refs[index]
        if texture_ref is not None:
            _write_texture(main, texture_ref.offset, material[1], material[2])
        _write_material(main, material_refs[index].offset, material[0], texture_ref)

    material_index_by_key = {material: index for index, material in enumerate(materials)}
    for index, mesh in enumerate(scene.meshes):
        _write_material_bindings(
            main,
            material_binding_refs[index].offset,
            mesh,
            [] if all_rigid else material_refs,
            material_index_by_key,
        )
        _write_triangle_groups(main, triangle_group_refs[index].offset, mesh)
        _write_bone_bindings(main, bone_binding_refs[index].offset, mesh, bone_bindings_by_mesh[index])
        _write_vertex_component_names(
            main,
            _vertex_component_names(bone_bindings_by_mesh[index]),
            vertex_component_array_refs[index],
            vertex_component_object_refs[index],
        )
        _write_vertex_data(
            main,
            vertex_data_refs[index].offset,
            len(mesh.vertices),
            PointerRef(vertex_section.index, vertex_offsets[index]),
            PointerRef(6, type_writer.type_offsets[_vertex_type_name(bone_bindings_by_mesh[index])]),
            len(_vertex_component_names(bone_bindings_by_mesh[index])),
            vertex_component_array_refs[index],
        )
        _write_topology(
            main,
            topology_refs[index].offset,
            len(mesh.indices),
            PointerRef(index_section.index, index_offsets[index]),
            index32_flags[index],
            triangle_group_refs[index],
            len(_triangle_groups(mesh)),
            topology_map_refs[index],
            len(mesh.vertices),
        )
        _write_mesh(
            main,
            mesh_refs[index].offset,
            mesh.name,
            vertex_data_refs[index],
            topology_refs[index],
            material_binding_refs[index],
            len(mesh.material_names),
            bone_binding_refs[index],
            len(bone_bindings_by_mesh[index]),
            mesh_bounds_refs[index],
            PointerRef(6, type_writer.type_offsets["MeshBounds"]),
            bool(bone_bindings_by_mesh[index]),
        )
        _write_mesh_bounds(main, mesh_bounds_refs[index].offset, mesh)

    _write_model(
        main,
        model_ref.offset,
        _model_name(scene),
        skeleton_refs[0] if skeleton_refs else None,
        scene.skeletons[0].initial_placement if skeleton_refs else (),
        model_mesh_binding_ref,
        len(mesh_refs),
    )

    type_writer.finish()
    output = _assemble_file(
        sections,
        root_type=PointerRef(6, type_writer.type_offsets["Root"]),
        root_object=PointerRef(0, root_offset),
    )
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(output)
    return output_path


def _build_type_tree(section: _SectionBuilder) -> _TypeWriter:
    writer = _TypeWriter(section)
    writer.add(
        "RigidExportVertex",
        (
            (MT_REAL32, "Position", "", 3),
            (MT_REAL32, "Normal", "", 3),
            (MT_REAL32, "Tangent", "", 3),
            (MT_REAL32, "TextureCoordinates0", "", 2),
        ),
    )
    writer.add(
        "Root",
        (
            (MT_REFERENCE, "ArtToolInfo", "ArtToolInfo", 1),
            (MT_REFERENCE, "ExporterInfo", "ExporterInfo", 1),
            (MT_STRING, "FromFileName", "", 1),
            (MT_ARRAY_OF_REFERENCES, "Textures", "Texture", 1),
            (MT_ARRAY_OF_REFERENCES, "Materials", "Material", 1),
            (MT_ARRAY_OF_REFERENCES, "Skeletons", "Skeleton", 1),
            (MT_ARRAY_OF_REFERENCES, "VertexDatas", "VertexData", 1),
            (MT_ARRAY_OF_REFERENCES, "TriTopologies", "TriTopology", 1),
            (MT_ARRAY_OF_REFERENCES, "Meshes", "Mesh", 1),
            (MT_ARRAY_OF_REFERENCES, "Models", "Model", 1),
            (MT_ARRAY_OF_REFERENCES, "TrackGroups", "TrackGroup", 1),
            (MT_ARRAY_OF_REFERENCES, "Animations", "Animation", 1),
            (MT_VARIANT_REFERENCE, "ExtendedData", "", 1),
        ),
    )
    writer.add(
        "ArtToolInfo",
        (
            (MT_STRING, "FromArtToolName", "", 1),
            (MT_INT32, "ArtToolMajorRevision", "", 1),
            (MT_INT32, "ArtToolMinorRevision", "", 1),
            (MT_INT32, "ArtToolPointerSize", "", 1),
            (MT_REAL32, "UnitsPerMeter", "", 1),
            (MT_REAL32, "Origin", "", 3),
            (MT_REAL32, "RightVector", "", 3),
            (MT_REAL32, "UpVector", "", 3),
            (MT_REAL32, "BackVector", "", 3),
            (MT_VARIANT_REFERENCE, "ExtendedData", "", 1),
        ),
    )
    writer.add(
        "ExporterInfo",
        (
            (MT_STRING, "ExporterName", "", 1),
            (MT_INT32, "ExporterMajorRevision", "", 1),
            (MT_INT32, "ExporterMinorRevision", "", 1),
            (MT_INT32, "ExporterCustomization", "", 1),
            (MT_INT32, "ExporterBuildNumber", "", 1),
            (MT_VARIANT_REFERENCE, "ExtendedData", "", 1),
        ),
    )
    writer.add(
        "MeshBounds",
        (
            (MT_REAL32, "MinPosition", "", 3),
            (MT_REAL32, "MaxPosition", "", 3),
        ),
    )
    writer.add(
        "Mesh",
        (
            (MT_STRING, "Name", "", 1),
            (MT_REFERENCE, "PrimaryVertexData", "VertexData", 1),
            (MT_REFERENCE_TO_ARRAY, "MorphTargets", "Mesh", 1),
            (MT_REFERENCE, "PrimaryTopology", "TriTopology", 1),
            (MT_REFERENCE_TO_ARRAY, "MaterialBindings", "MaterialBinding", 1),
            (MT_REFERENCE_TO_ARRAY, "BoneBindings", "BoneBinding", 1),
            (MT_VARIANT_REFERENCE, "ExtendedData", "", 1),
        ),
    )
    writer.add(
        "VertexData",
        (
            (MT_REFERENCE_TO_VARIANT_ARRAY, "Vertices", "", 1),
            (MT_REFERENCE_TO_ARRAY, "VertexComponentNames", "StringObject", 1),
            (MT_REFERENCE_TO_ARRAY, "VertexAnnotationSets", "VertexAnnotationSet", 1),
        ),
    )
    writer.add("StringObject", ((MT_STRING, "String", "", 1),))
    writer.add(
        "TriTopology",
        (
            (MT_REFERENCE_TO_ARRAY, "Groups", "TriMaterialGroup", 1),
            (MT_REFERENCE_TO_ARRAY, "Indices", "Int32", 1),
            (MT_REFERENCE_TO_ARRAY, "Indices16", "Int16", 1),
            (MT_REFERENCE_TO_ARRAY, "VertexToVertexMap", "Int32", 1),
            (MT_REFERENCE_TO_ARRAY, "VertexToTriangleMap", "Int32", 1),
            (MT_REFERENCE_TO_ARRAY, "SideToNeighborMap", "Int32", 1),
            (MT_REFERENCE_TO_ARRAY, "BonesForTriangle", "Int32", 1),
            (MT_REFERENCE_TO_ARRAY, "TriangleToBoneIndices", "Int32", 1),
            (MT_REFERENCE_TO_ARRAY, "TriAnnotationSets", "TriAnnotationSet", 1),
        ),
    )
    writer.add(
        "ExportVertex",
        (
            (MT_REAL32, "Position", "", 3),
            (MT_NORMAL_UINT8, "BoneWeights", "", 4),
            (MT_UINT8, "BoneIndices", "", 4),
            (MT_REAL32, "Normal", "", 3),
            (MT_REAL32, "TextureCoordinates0", "", 2),
        ),
    )
    writer.add(
        "Skeleton",
        (
            (MT_STRING, "Name", "", 1),
            (MT_REFERENCE_TO_ARRAY, "Bones", "Bone", 1),
            (MT_INT32, "LODType", "", 1),
        ),
    )
    writer.add(
        "Bone",
        (
            (MT_STRING, "Name", "", 1),
            (MT_INT32, "ParentIndex", "", 1),
            (MT_TRANSFORM, "Transform", "", 1),
            (MT_REAL32, "InverseWorldTransform", "", 16),
        ),
    )
    writer.add(
        "Model",
        (
            (MT_STRING, "Name", "", 1),
            (MT_REFERENCE, "Skeleton", "Skeleton", 1),
            (MT_TRANSFORM, "InitialPlacement", "", 1),
            (MT_REFERENCE_TO_ARRAY, "MeshBindings", "ModelMeshBinding", 1),
            (MT_VARIANT_REFERENCE, "ExtendedData", "", 1),
        ),
    )
    writer.add("ModelMeshBinding", ((MT_REFERENCE, "Mesh", "Mesh", 1),))
    writer.add("TrackGroup", ())
    writer.add("Animation", ())
    writer.add("VertexAnnotationSet", ())
    writer.add("TriAnnotationSet", ())
    writer.add(
        "Material",
        (
            (MT_STRING, "Name", "", 1),
            (MT_REFERENCE_TO_ARRAY, "Maps", "MaterialMap", 1),
            (MT_REFERENCE, "Texture", "Texture", 1),
        ),
    )
    writer.add("MaterialMap", ())
    writer.add(
        "Texture",
        (
            (MT_STRING, "FromFileName", "", 1),
            (MT_INT32, "TextureType", "", 1),
            (MT_INT32, "Width", "", 1),
            (MT_INT32, "Height", "", 1),
        ),
    )
    writer.add("MaterialBinding", ((MT_REFERENCE, "Material", "Material", 1),))
    writer.add(
        "BoneBinding",
        (
            (MT_STRING, "BoneName", "", 1),
            (MT_REAL32, "OBBMin", "", 3),
            (MT_REAL32, "OBBMax", "", 3),
            (MT_REFERENCE_TO_ARRAY, "TriangleIndices", "Int32", 1),
        ),
    )
    writer.add(
        "TriMaterialGroup",
        (
            (MT_INT32, "MaterialIndex", "", 1),
            (MT_INT32, "TriFirst", "", 1),
            (MT_INT32, "TriCount", "", 1),
        ),
    )
    writer.add("Int16", ((MT_INT16, "Int16", "", 1),))
    writer.add("Int32", ((MT_INT32, "Int32", "", 1),))
    return writer


def _write_vertices(section: _SectionBuilder, mesh, bone_bindings: tuple[str, ...]) -> int:
    section.align(32)
    offset = section.tell()
    if not bone_bindings:
        for vertex in mesh.vertices:
            for value in vertex.position:
                section.f32(value)
            for value in vertex.normal:
                section.f32(value)
            tangent = _orthogonal_tangent(vertex.normal)
            for value in tangent:
                section.f32(value)
            uv = vertex.uv or (0.0, 0.0)
            section.f32(uv[0])
            section.f32(uv[1])
        return offset

    bone_indices = {name: index for index, name in enumerate(bone_bindings)}
    for vertex in mesh.vertices:
        for value in vertex.position:
            section.f32(value)
        lanes = list(vertex.weights[:4])
        encoded_weights = _encoded_weights([item.weight for item in lanes])
        encoded_indices = [bone_indices.get(item.bone, 0) for item in lanes]
        while len(encoded_indices) < 4:
            encoded_indices.append(0)
        section.data.extend(bytes(encoded_weights))
        section.data.extend(bytes(encoded_indices[:4]))
        for value in vertex.normal:
            section.f32(value)
        uv = vertex.uv or (0.0, 0.0)
        section.f32(uv[0])
        section.f32(uv[1])
    return offset


def _vertex_type_name(bone_bindings: tuple[str, ...]) -> str:
    return "ExportVertex" if bone_bindings else "RigidExportVertex"


def _vertex_component_names(bone_bindings: tuple[str, ...]) -> tuple[str, ...]:
    if bone_bindings:
        return ("Position", "BoneWeights", "BoneIndices", "Normal", "TextureCoordinates0")
    return ("Position", "Normal", "Tangent", "TextureCoordinates0")


def _orthogonal_tangent(normal: tuple[float, float, float]) -> tuple[float, float, float]:
    nx, ny, nz = normal
    if abs(nz) < 0.9:
        tangent = (ny, -nx, 0.0)
    else:
        tangent = (1.0, 0.0, 0.0)
    length = (tangent[0] * tangent[0] + tangent[1] * tangent[1] + tangent[2] * tangent[2]) ** 0.5
    if length <= 0.0:
        return (1.0, 0.0, 0.0)
    return (tangent[0] / length, tangent[1] / length, tangent[2] / length)


def _write_indices(section: _SectionBuilder, mesh) -> int:
    offset = section.tell()
    for index in mesh.indices:
        section.data.extend(struct.pack("<I", index))
    section.align(4)
    return offset


def _write_vertex_component_names(
    main: _SectionBuilder,
    names: tuple[str, ...],
    array_ref: PointerRef,
    object_refs: list[PointerRef],
) -> None:
    for index, name in enumerate(names):
        if index >= len(object_refs):
            break
        main.patch_pointer(array_ref.offset + index * 4, object_refs[index])
        name_offset = main.c_string(name)
        main.patch_pointer(object_refs[index].offset, PointerRef(0, name_offset))


def _write_topology_maps(
    main: _SectionBuilder,
    mesh,
    vertex_to_vertex_ref: PointerRef,
    vertex_to_triangle_ref: PointerRef,
    side_to_neighbor_ref: PointerRef,
) -> None:
    first_triangle_by_vertex = [0 for _ in mesh.vertices]
    for tri_index, base in enumerate(range(0, len(mesh.indices), 3)):
        for index in mesh.indices[base : base + 3]:
            if 0 <= index < len(first_triangle_by_vertex):
                first_triangle_by_vertex[index] = tri_index
    for index in range(len(mesh.vertices)):
        struct.pack_into("<I", main.data, vertex_to_vertex_ref.offset + index * 4, index)
        struct.pack_into("<I", main.data, vertex_to_triangle_ref.offset + index * 4, first_triangle_by_vertex[index])
    for index in range(len(mesh.indices)):
        struct.pack_into("<I", main.data, side_to_neighbor_ref.offset + index * 4, index)


def _write_vertex_data(
    main: _SectionBuilder,
    offset: int,
    vertex_count: int,
    vertices_ref: PointerRef,
    vertex_type_ref: PointerRef,
    component_name_count: int,
    component_names_ref: PointerRef,
) -> None:
    main.patch_pointer(offset, vertex_type_ref)
    struct.pack_into("<I", main.data, offset + 4, vertex_count)
    main.patch_pointer(offset + 8, vertices_ref)
    _patch_reference_array_or_empty(main, offset + 12, component_name_count, component_names_ref)
    struct.pack_into("<II", main.data, offset + 20, 0, 0)


def _write_topology(
    main: _SectionBuilder,
    offset: int,
    index_count: int,
    indices_ref: PointerRef,
    use_32bit: bool,
    group_ref: PointerRef,
    group_count: int,
    map_refs: tuple[PointerRef, PointerRef, PointerRef],
    vertex_count: int,
) -> None:
    _patch_reference_array_or_empty(main, offset, group_count, group_ref)
    _patch_reference_array(main, offset + 8, index_count, indices_ref)
    struct.pack_into("<II", main.data, offset + 16, 0, 0)
    vertex_to_vertex_ref, vertex_to_triangle_ref, side_to_neighbor_ref = map_refs
    struct.pack_into("<IIIIII", main.data, offset + 24, 0, 0, 0, 0, 0, 0)
    struct.pack_into("<IIIIII", main.data, offset + 48, 0, 0, 0, 0, 0, 0)


def _write_mesh(
    main: _SectionBuilder,
    offset: int,
    name: str,
    vertex_data_ref: PointerRef,
    topology_ref: PointerRef,
    material_binding_ref: PointerRef,
    material_binding_count: int,
    bone_binding_ref: PointerRef,
    bone_binding_count: int,
    bounds_ref: PointerRef,
    bounds_type_ref: PointerRef,
    use_bounds: bool,
) -> None:
    name_offset = main.c_string(name or "Mesh")
    main.patch_pointer(offset, PointerRef(0, name_offset))
    main.patch_pointer(offset + 4, vertex_data_ref)
    struct.pack_into("<II", main.data, offset + 8, 0, 0)
    main.patch_pointer(offset + 16, topology_ref)
    _patch_reference_array_or_empty(main, offset + 20, material_binding_count, material_binding_ref)
    _patch_reference_array_or_empty(main, offset + 28, bone_binding_count, bone_binding_ref)
    if use_bounds:
        main.patch_pointer(offset + 36, bounds_type_ref)
        main.patch_pointer(offset + 40, bounds_ref)
    else:
        struct.pack_into("<II", main.data, offset + 36, 0, 0)


def _write_mesh_bounds(main: _SectionBuilder, offset: int, mesh) -> None:
    bound_min, bound_max = _mesh_bounds(mesh)
    struct.pack_into("<3f", main.data, offset, *bound_min)
    struct.pack_into("<3f", main.data, offset + 12, *bound_max)


def _write_art_tool_info(main: _SectionBuilder, offset: int) -> None:
    name_offset = main.c_string("Blender")
    main.patch_pointer(offset, PointerRef(0, name_offset))
    struct.pack_into(
        "<iii f 3f 3f 3f 3f II",
        main.data,
        offset + 4,
        5,
        1,
        0,
        100.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        -1.0,
        0.0,
        0,
        0,
    )


def _write_exporter_info(main: _SectionBuilder, offset: int) -> None:
    name_offset = main.c_string("blendergranny native exporter")
    main.patch_pointer(offset, PointerRef(0, name_offset))
    struct.pack_into("<iiiiII", main.data, offset + 4, 0, 1, 0, 42, 0, 0)


def _write_material(main: _SectionBuilder, offset: int, name: str, texture_ref: PointerRef | None) -> None:
    name_offset = main.c_string(name or "Material")
    main.patch_pointer(offset, PointerRef(0, name_offset))
    struct.pack_into("<II", main.data, offset + 4, 0, 0)
    if texture_ref is not None:
        main.patch_pointer(offset + 12, texture_ref)
    else:
        struct.pack_into("<I", main.data, offset + 12, 0)


def _write_texture(main: _SectionBuilder, offset: int, texture_file: str, texture_size: tuple[int, int] | None) -> None:
    name_offset = main.c_string(texture_file)
    width, height = texture_size or (0, 0)
    main.patch_pointer(offset, PointerRef(0, name_offset))
    struct.pack_into("<iii", main.data, offset + 4, 0, int(width), int(height))


def _write_material_bindings(
    main: _SectionBuilder,
    offset: int,
    mesh,
    material_refs: list[PointerRef],
    material_index_by_key: dict[tuple[str, str, tuple[int, int] | None], int],
) -> None:
    for index, material in enumerate(_mesh_materials(mesh)):
        material_index = material_index_by_key.get(material, 0)
        if material_index < len(material_refs):
            main.patch_pointer(offset + index * 4, material_refs[material_index])


def _write_triangle_groups(main: _SectionBuilder, offset: int, mesh) -> None:
    for index, (material_index, tri_first, tri_count) in enumerate(_triangle_groups(mesh)):
        struct.pack_into("<iii", main.data, offset + index * 12, material_index, tri_first, tri_count)


def _write_bone_bindings(main: _SectionBuilder, offset: int, mesh, bone_names: tuple[str, ...]) -> None:
    bounds = _bone_bounds(mesh, bone_names)
    for index, name in enumerate(bone_names):
        binding_offset = offset + index * 36
        bound_min, bound_max = bounds.get(name, _mesh_bounds(mesh))
        name_offset = main.c_string(name)
        main.patch_pointer(binding_offset, PointerRef(0, name_offset))
        struct.pack_into("<3f", main.data, binding_offset + 4, *bound_min)
        struct.pack_into("<3f", main.data, binding_offset + 16, *bound_max)
        struct.pack_into("<III", main.data, binding_offset + 28, 0, 0, 0)


def _write_model(
    main: _SectionBuilder,
    offset: int,
    name: str,
    skeleton_ref: PointerRef | None,
    initial_placement: tuple[float, ...],
    mesh_bindings_ref: PointerRef,
    mesh_binding_count: int,
) -> None:
    name_offset = main.c_string(name or "Model")
    main.patch_pointer(offset, PointerRef(0, name_offset))
    if skeleton_ref is not None:
        main.patch_pointer(offset + 4, skeleton_ref)
    else:
        struct.pack_into("<I", main.data, offset + 4, 0)
    if len(initial_placement) == 16:
        _pack_transform(main.data, offset + 8, initial_placement, flags=3)
    else:
        _pack_identity_transform(main.data, offset + 8)
    _patch_reference_array(main, offset + 76, mesh_binding_count, mesh_bindings_ref)
    struct.pack_into("<II", main.data, offset + 84, 0, 0)


def _write_skeleton(main: _SectionBuilder, offset: int, skeleton, bones_ref: PointerRef) -> None:
    name_offset = main.c_string(skeleton.name or "Skeleton")
    main.patch_pointer(offset, PointerRef(0, name_offset))
    _patch_reference_array(main, offset + 4, len(skeleton.bones), bones_ref)
    struct.pack_into("<i", main.data, offset + 12, 0)


def _write_bones(main: _SectionBuilder, offset: int, skeleton, *, root_identity: bool = False) -> None:
    bone_indices = {bone.name: index for index, bone in enumerate(skeleton.bones)}
    for index, bone in enumerate(skeleton.bones):
        bone_offset = offset + index * 140
        name_offset = main.c_string(bone.name or f"Bone_{index}")
        main.patch_pointer(bone_offset, PointerRef(0, name_offset))
        parent_index = bone_indices.get(bone.parent, -1)
        struct.pack_into("<i", main.data, bone_offset + 4, parent_index)
        if root_identity and index == 0 and not bone.parent:
            _pack_transform_values(
                main.data,
                bone_offset + 8,
                int(getattr(bone, "granny_transform_flags", 0) or 0),
                (0.0, 0.0, 0.0),
                (0.0, 0.0, 0.0, 1.0),
            )
        else:
            _pack_bone_transform(main.data, bone_offset + 8, bone)
        _pack_inverse_world(main.data, bone_offset + 76, bone.inverse_world_transform)


def _pack_bone_transform(data: bytearray, offset: int, bone) -> None:
    position = tuple(getattr(bone, "granny_local_position", ()) or ())
    orientation = tuple(getattr(bone, "granny_local_orientation_xyzw", ()) or ())
    if len(position) == 3 and len(orientation) == 4:
        _pack_transform_values(
            data,
            offset,
            int(getattr(bone, "granny_transform_flags", 0) or 0),
            position,
            orientation,
        )
        return
    _pack_transform(data, offset, _bone_local_matrix(bone))


def _pack_transform(data: bytearray, offset: int, matrix: tuple[float, ...], *, flags: int = 0) -> None:
    position = _matrix_translation(matrix)
    orientation = _matrix_quaternion_xyzw(matrix)
    _pack_transform_values(data, offset, flags, position, orientation)


def _pack_transform_values(
    data: bytearray,
    offset: int,
    flags: int,
    position: tuple[float, float, float],
    orientation: tuple[float, float, float, float],
) -> None:
    values = (
        flags,
        position[0],
        position[1],
        position[2],
        orientation[0],
        orientation[1],
        orientation[2],
        orientation[3],
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
    )
    struct.pack_into("<I16f", data, offset, *values)


def _pack_identity_transform(data: bytearray, offset: int) -> None:
    struct.pack_into(
        "<I16f",
        data,
        offset,
        0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
    )


def _pack_inverse_world(data: bytearray, offset: int, values: tuple[float, ...]) -> None:
    if len(values) == 16:
        struct.pack_into("<16f", data, offset, *values)
        return
    struct.pack_into(
        "<16f",
        data,
        offset,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
    )


def _bone_local_matrix(bone) -> tuple[float, ...]:
    return bone.granny_rest_local if len(bone.granny_rest_local) == 16 else bone.matrix_local


def _matrix_translation(matrix: tuple[float, ...]) -> tuple[float, float, float]:
    if len(matrix) != 16:
        return (0.0, 0.0, 0.0)
    return (float(matrix[3]), float(matrix[7]), float(matrix[11]))


def _matrix_quaternion_xyzw(matrix: tuple[float, ...]) -> tuple[float, float, float, float]:
    if len(matrix) != 16:
        return (0.0, 0.0, 0.0, 1.0)
    m00, m01, m02 = matrix[0], matrix[1], matrix[2]
    m10, m11, m12 = matrix[4], matrix[5], matrix[6]
    m20, m21, m22 = matrix[8], matrix[9], matrix[10]
    trace = m00 + m11 + m22
    if trace > 0.0:
        scale = (trace + 1.0) ** 0.5 * 2.0
        w = 0.25 * scale
        x = (m21 - m12) / scale
        y = (m02 - m20) / scale
        z = (m10 - m01) / scale
    elif m00 > m11 and m00 > m22:
        scale = (1.0 + m00 - m11 - m22) ** 0.5 * 2.0
        w = (m21 - m12) / scale
        x = 0.25 * scale
        y = (m01 + m10) / scale
        z = (m02 + m20) / scale
    elif m11 > m22:
        scale = (1.0 + m11 - m00 - m22) ** 0.5 * 2.0
        w = (m02 - m20) / scale
        x = (m01 + m10) / scale
        y = 0.25 * scale
        z = (m12 + m21) / scale
    else:
        scale = (1.0 + m22 - m00 - m11) ** 0.5 * 2.0
        w = (m10 - m01) / scale
        x = (m02 + m20) / scale
        y = (m12 + m21) / scale
        z = 0.25 * scale
    length = (x * x + y * y + z * z + w * w) ** 0.5
    if length <= 0.0:
        return (0.0, 0.0, 0.0, 1.0)
    return (x / length, y / length, z / length, w / length)


def _mesh_bone_bindings(mesh, skeleton_bone_names: tuple[str, ...] = ()) -> tuple[str, ...]:
    stored = tuple(getattr(mesh, "bone_binding_names", ()) or ())
    if stored:
        return stored
    names: list[str] = []
    for vertex in mesh.vertices:
        for weight in vertex.weights:
            if weight.bone and weight.bone not in names:
                names.append(weight.bone)
    return tuple(names)


def _bone_bounds(mesh, bone_names: tuple[str, ...]) -> dict[str, tuple[tuple[float, float, float], tuple[float, float, float]]]:
    points: dict[str, list[tuple[float, float, float]]] = {name: [] for name in bone_names}
    for vertex in mesh.vertices:
        for weight in vertex.weights:
            if weight.weight > 0.0 and weight.bone in points:
                points[weight.bone].append(vertex.position)
    return {name: _bounds_from_points(points[name]) for name in bone_names if points[name]}


def _mesh_bounds(mesh) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    return _bounds_from_points([vertex.position for vertex in mesh.vertices])


def _bounds_from_points(points: list[tuple[float, float, float]]) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    if not points:
        return ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
    mins = [min(point[axis] for point in points) for axis in range(3)]
    maxs = [max(point[axis] for point in points) for axis in range(3)]
    padding = 0.001
    return (
        (mins[0] - padding, mins[1] - padding, mins[2] - padding),
        (maxs[0] + padding, maxs[1] + padding, maxs[2] + padding),
    )


def _scene_materials(scene: ExportScene) -> tuple[tuple[str, str, tuple[int, int] | None], ...]:
    materials: list[tuple[str, str, tuple[int, int] | None]] = []
    for mesh in scene.meshes:
        for material in _mesh_materials(mesh):
            if material not in materials:
                materials.append(material)
    return tuple(materials)


def _mesh_materials(mesh) -> tuple[tuple[str, str, tuple[int, int] | None], ...]:
    result = []
    for index, name in enumerate(mesh.material_names):
        texture_file = mesh.material_texture_files[index] if index < len(mesh.material_texture_files) else ""
        texture_size = mesh.material_texture_sizes[index] if index < len(mesh.material_texture_sizes) else None
        result.append((name, texture_file, texture_size))
    return tuple(result)


def _model_name(scene: ExportScene) -> str:
    if scene.skeletons and scene.skeletons[0].name:
        return scene.skeletons[0].name
    if scene.meshes and scene.meshes[0].name:
        return scene.meshes[0].name
    return "Model"


def _triangle_groups(mesh) -> tuple[tuple[int, int, int], ...]:
    if not mesh.material_indices:
        return ()
    groups: list[tuple[int, int, int]] = []
    start = 0
    current = int(mesh.material_indices[0])
    for index, material_index in enumerate(mesh.material_indices[1:], start=1):
        material_index = int(material_index)
        if material_index == current:
            continue
        groups.append((current, start, index - start))
        start = index
        current = material_index
    groups.append((current, start, len(mesh.material_indices) - start))
    return tuple(groups)


def _uses_32bit_indices(mesh) -> bool:
    return any(index > 0xFFFF for index in mesh.indices) or len(mesh.vertices) > 0xFFFF


def _encoded_weights(weights: list[float]) -> list[int]:
    encoded = [max(0, min(255, int(round(weight * 255.0)))) for weight in weights[:4]]
    while len(encoded) < 4:
        encoded.append(0)
    total = sum(encoded)
    if total > 0:
        encoded[0] = max(0, min(255, encoded[0] + (255 - total)))
    return encoded[:4]


def _patch_reference_array(main: _SectionBuilder, offset: int, count: int, target: PointerRef) -> None:
    struct.pack_into("<I", main.data, offset, count)
    main.patch_pointer(offset + 4, target)


def _patch_reference_array_or_empty(main: _SectionBuilder, offset: int, count: int, target: PointerRef) -> None:
    if count <= 0:
        struct.pack_into("<II", main.data, offset, 0, 0)
        return
    _patch_reference_array(main, offset, count, target)


def _assemble_file(sections: list[_SectionBuilder], *, root_type: PointerRef, root_object: PointerRef) -> bytes:
    data_offsets: list[int] = []
    cursor = DATA_START
    for section in sections:
        cursor = _align(cursor, section.internal_alignment)
        data_offsets.append(cursor)
        cursor += len(section.data)

    fixup_offsets: list[int] = []
    fixup_blobs: list[bytes] = []
    for section in sections:
        cursor = _align(cursor, 4)
        fixup_offsets.append(cursor if section.fixups else 0)
        blob = b"".join(
            struct.pack("<III", fixup.source.offset, fixup.target.section, fixup.target.offset)
            for fixup in section.fixups
        )
        fixup_blobs.append(blob)
        cursor += len(blob)

    total_size = cursor
    output = bytearray()
    for word in MAGIC_32LE:
        output.extend(struct.pack("<I", word))
    output.extend(struct.pack("<4I", DATA_START, 0, 0, 0))
    output.extend(
        struct.pack(
            "<18I",
            7,
            total_size,
            0,
            SECTION_ARRAY_OFFSET,
            SECTION_COUNT,
            root_type.section,
            root_type.offset,
            root_object.section,
            root_object.offset,
            TYPE_TAG,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        )
    )
    for section, data_offset, fixup_offset in zip(sections, data_offsets, fixup_offsets):
        output.extend(
            struct.pack(
                "<11I",
                COMPRESSION_NONE,
                data_offset,
                len(section.data),
                len(section.data),
                section.internal_alignment,
                len(section.data),
                len(section.data),
                fixup_offset,
                len(section.fixups),
                total_size,
                0,
            )
        )
    for section, data_offset in zip(sections, data_offsets):
        _pad_to(output, data_offset)
        output.extend(section.data)
    for blob, fixup_offset in zip(fixup_blobs, fixup_offsets):
        if not blob:
            continue
        _pad_to(output, fixup_offset)
        output.extend(blob)
    _pad_to(output, total_size)
    _patch_crc(output, SECTION_ARRAY_OFFSET)
    return bytes(output)


def _align(value: int, amount: int) -> int:
    return (value + amount - 1) & -amount


def _pad_to(output: bytearray, offset: int) -> None:
    if len(output) > offset:
        raise ValueError("GR2 writer layout overlap")
    output.extend(b"\x00" * (offset - len(output)))


def _patch_crc(output: bytearray, section_array_offset: int) -> None:
    crc_offset = MAGIC_SIZE + 8
    table_offset = MAGIC_SIZE + section_array_offset
    struct.pack_into("<I", output, crc_offset, 0)
    crc = zlib.crc32(bytes(output[table_offset:])) & 0xFFFFFFFF
    struct.pack_into("<I", output, crc_offset, crc)
