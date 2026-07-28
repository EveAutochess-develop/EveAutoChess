"""Small dynamic Granny type-tree reader."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Any

from .fixup import LoadedGR2, PointerRef, decode_fake_pointer

MT_END = 0
MT_INLINE = 1
MT_REFERENCE = 2
MT_REFERENCE_TO_ARRAY = 3
MT_ARRAY_OF_REFERENCES = 4
MT_VARIANT_REFERENCE = 5
MT_UNSUPPORTED = 6
MT_REFERENCE_TO_VARIANT_ARRAY = 7
MT_STRING = 8
MT_TRANSFORM = 9
MT_REAL32 = 10
MT_INT8 = 11
MT_UINT8 = 12
MT_BINORMAL_INT8 = 13
MT_NORMAL_UINT8 = 14
MT_INT16 = 15
MT_UINT16 = 16
MT_BINORMAL_INT16 = 17
MT_NORMAL_UINT16 = 18
MT_INT32 = 19
MT_UINT32 = 20
MT_REAL16 = 21
MT_EMPTY_REFERENCE = 22

MEMBER_TYPE_NAMES = {
    MT_END: "end",
    MT_INLINE: "inline",
    MT_REFERENCE: "reference",
    MT_REFERENCE_TO_ARRAY: "reference_to_array",
    MT_ARRAY_OF_REFERENCES: "array_of_references",
    MT_VARIANT_REFERENCE: "variant_reference",
    MT_UNSUPPORTED: "unsupported",
    MT_REFERENCE_TO_VARIANT_ARRAY: "reference_to_variant_array",
    MT_STRING: "string",
    MT_TRANSFORM: "transform",
    MT_REAL32: "real32",
    MT_INT8: "int8",
    MT_UINT8: "uint8",
    MT_BINORMAL_INT8: "binormal_int8",
    MT_NORMAL_UINT8: "normal_uint8",
    MT_INT16: "int16",
    MT_UINT16: "uint16",
    MT_BINORMAL_INT16: "binormal_int16",
    MT_NORMAL_UINT16: "normal_uint16",
    MT_INT32: "int32",
    MT_UINT32: "uint32",
    MT_REAL16: "real16",
    MT_EMPTY_REFERENCE: "empty_reference",
}

_SCALAR_SIZES = {
    MT_REAL32: 4,
    MT_INT8: 1,
    MT_UINT8: 1,
    MT_BINORMAL_INT8: 1,
    MT_NORMAL_UINT8: 1,
    MT_INT16: 2,
    MT_UINT16: 2,
    MT_BINORMAL_INT16: 2,
    MT_NORMAL_UINT16: 2,
    MT_INT32: 4,
    MT_UINT32: 4,
    MT_REAL16: 2,
}


@dataclass(frozen=True)
class TypeDefinition:
    member_type: int
    name: str
    reference_type: PointerRef | None
    array_width: int
    extra: tuple[int, int, int]
    offset: int

    @property
    def member_type_name(self) -> str:
        return MEMBER_TYPE_NAMES.get(self.member_type, f"type_{self.member_type}")


def parse_type_definition_array(
    loaded: LoadedGR2,
    ref: PointerRef,
    *,
    max_members: int = 512,
) -> tuple[TypeDefinition, ...]:
    if ref.section >= len(loaded.sections_fixed):
        return ()
    data = loaded.sections_fixed[ref.section]
    entries: list[TypeDefinition] = []
    offset = ref.offset
    for _ in range(max_members):
        if offset + 32 > len(data):
            break
        member_type, name_ptr, type_ptr, array_width, extra0, extra1, extra2, _unused = struct.unpack_from(
            "<8I", data, offset
        )
        if member_type == MT_END:
            break
        name = read_string_pointer(loaded, name_ptr) or f"member_{len(entries)}"
        type_ref = loaded.resolve_fake_pointer(type_ptr)
        entries.append(
            TypeDefinition(
                member_type=member_type,
                name=name,
                reference_type=type_ref,
                array_width=array_width or 1,
                extra=(extra0, extra1, extra2),
                offset=offset,
            )
        )
        offset += 32
    return tuple(entries)


def read_string_pointer(loaded: LoadedGR2, pointer: int) -> str:
    ref = loaded.resolve_fake_pointer(pointer)
    if ref is None:
        return ""
    return read_granny_string(loaded, ref)


def read_granny_string(loaded: LoadedGR2, ref: PointerRef, max_length: int = 1024) -> str:
    if ref.section >= len(loaded.sections_original):
        return ""
    data = loaded.sections_original[ref.section]
    if ref.offset >= len(data):
        return ""

    if ref.offset + 4 <= len(data):
        length = struct.unpack_from("<I", data, ref.offset)[0]
        end = ref.offset + 4 + length
        if 0 < length <= max_length and end <= len(data) and _looks_text(data[ref.offset + 4 : end]):
            return data[ref.offset + 4 : end].decode("utf-8", "replace").rstrip("\x00")

    end = data.find(b"\x00", ref.offset, min(len(data), ref.offset + max_length))
    if end < 0:
        end = min(len(data), ref.offset + max_length)
    raw = data[ref.offset:end]
    if not _looks_text(raw):
        return ""
    return raw.decode("utf-8", "replace")


def member_storage_size(member: TypeDefinition, pointer_size: int) -> int:
    width = member.array_width or 1
    if member.member_type in _SCALAR_SIZES:
        return _SCALAR_SIZES[member.member_type] * width
    if member.member_type in (MT_REFERENCE, MT_EMPTY_REFERENCE, MT_STRING):
        return pointer_size
    if member.member_type in (MT_REFERENCE_TO_ARRAY, MT_ARRAY_OF_REFERENCES):
        return 4 + pointer_size
    if member.member_type == MT_VARIANT_REFERENCE:
        return pointer_size * 2
    if member.member_type == MT_REFERENCE_TO_VARIANT_ARRAY:
        return pointer_size + 4 + pointer_size
    if member.member_type == MT_TRANSFORM:
        return 68
    if member.member_type == MT_INLINE:
        return 0
    return pointer_size


def summarize_object(
    loaded: LoadedGR2,
    object_ref: PointerRef,
    type_ref: PointerRef,
    *,
    max_array_refs: int = 16,
) -> dict[str, Any]:
    members = parse_type_definition_array(loaded, type_ref)
    return _summarize_object_members(
        loaded,
        object_ref,
        members,
        type_ref=type_ref,
        max_array_refs=max_array_refs,
    )


def summarize_root_object(loaded: LoadedGR2, max_arrays: int = 64) -> dict[str, Any]:
    root_type = PointerRef(*loaded.gr2.header.root_type)
    root_object = PointerRef(*loaded.gr2.header.root_object)
    members = parse_type_definition_array(loaded, root_type)
    return _summarize_object_members(
        loaded,
        root_object,
        members,
        type_ref=root_type,
        max_array_refs=max_arrays,
    )


def summarize_meshes(loaded: LoadedGR2, max_meshes: int = 32) -> dict[str, Any]:
    root_type = PointerRef(*loaded.gr2.header.root_type)
    root_object = PointerRef(*loaded.gr2.header.root_object)
    root_members = parse_type_definition_array(loaded, root_type)
    mesh_member = next((member for member in root_members if member.name == "Meshes"), None)
    if mesh_member is None or mesh_member.reference_type is None:
        return {"meshes": []}

    root_fields = _field_map(
        _summarize_object_members(
            loaded,
            root_object,
            root_members,
            type_ref=root_type,
            max_array_refs=max_meshes,
        )
    )
    mesh_field = root_fields.get("Meshes", {})
    mesh_refs = [
        PointerRef(ref["section"], ref["offset"])
        for ref in mesh_field.get("element_refs", [])[:max_meshes]
    ]
    mesh_type = mesh_member.reference_type
    mesh_type_members = parse_type_definition_array(loaded, mesh_type)
    mesh_type_map = {member.name: member for member in mesh_type_members}

    meshes = []
    for index, mesh_ref in enumerate(mesh_refs):
        mesh_summary = summarize_object(loaded, mesh_ref, mesh_type)
        fields = _field_map(mesh_summary)
        mesh = {
            "index": index,
            "name": fields.get("Name", {}).get("value") or f"Mesh_{index}",
            "object": _pointer_ref_dict(mesh_ref),
            "fields": mesh_summary["fields"],
        }
        for field_name, output_name in (
            ("PrimaryVertexData", "primary_vertex_data"),
            ("PrimaryTopology", "primary_topology"),
        ):
            target = fields.get(field_name, {}).get("target")
            member = mesh_type_map.get(field_name)
            if target and member and member.reference_type:
                target_ref = PointerRef(target["section"], target["offset"])
                mesh[output_name] = summarize_object(loaded, target_ref, member.reference_type)
        vertex_data = mesh.get("primary_vertex_data")
        if isinstance(vertex_data, dict):
            vd_fields = _field_map(vertex_data)
            component_field = vd_fields.get("VertexComponentNames")
            mesh["vertex_components"] = _read_string_object_array(loaded, component_field)
        meshes.append(mesh)

    return {
        "count": mesh_field.get("count", 0),
        "meshes": meshes,
    }


def read_array_references(
    loaded: LoadedGR2,
    array_ref: PointerRef | None,
    count: int,
    *,
    max_count: int = 64,
) -> tuple[PointerRef, ...]:
    if array_ref is None or count <= 0:
        return ()
    pointer_size = loaded.gr2.header.pointer_size // 8
    data = loaded.sections_fixed[array_ref.section]
    refs: list[PointerRef] = []
    for index in range(min(count, max_count)):
        offset = array_ref.offset + index * pointer_size
        if offset + pointer_size > len(data):
            break
        ref = loaded.resolve_fake_pointer(_read_pointer(data, offset, pointer_size))
        if ref is not None:
            refs.append(ref)
    return tuple(refs)


def read_reference_array_objects(
    loaded: LoadedGR2,
    array_ref: PointerRef | None,
    count: int,
    type_ref: PointerRef | None,
    *,
    max_count: int = 64,
) -> tuple[dict[str, Any], ...]:
    if array_ref is None or type_ref is None or count <= 0:
        return ()
    pointer_size = loaded.gr2.header.pointer_size // 8
    members = parse_type_definition_array(loaded, type_ref)
    stride = _object_storage_size(loaded, members, pointer_size)
    if stride <= 0:
        return ()
    objects = []
    for index in range(min(count, max_count)):
        ref = PointerRef(array_ref.section, array_ref.offset + index * stride)
        objects.append(
            _summarize_object_members(
                loaded,
                ref,
                members,
                type_ref=type_ref,
                max_array_refs=max_count,
            )
        )
    return tuple(objects)


def _summarize_object_members(
    loaded: LoadedGR2,
    object_ref: PointerRef,
    members: tuple[TypeDefinition, ...],
    *,
    type_ref: PointerRef,
    max_array_refs: int,
) -> dict[str, Any]:
    pointer_size = loaded.gr2.header.pointer_size // 8
    data = loaded.sections_fixed[object_ref.section]
    raw = loaded.sections_original[object_ref.section]
    offset = object_ref.offset

    fields: list[dict[str, Any]] = []
    for member in members:
        size = member_storage_size(member, pointer_size)
        if offset + size > len(data):
            break
        field: dict[str, Any] = {
            "name": member.name,
            "type": member.member_type_name,
            "offset": offset,
        }
        if member.reference_type:
            field["reference_type"] = _pointer_ref_dict(member.reference_type)
        if member.member_type in (MT_REFERENCE, MT_EMPTY_REFERENCE):
            field["target"] = _pointer_field(loaded, data, offset, pointer_size)
        elif member.member_type == MT_STRING:
            pointer = _read_pointer(data, offset, pointer_size)
            field["value"] = read_string_pointer(loaded, pointer)
            field["target"] = _pointer_ref_dict(loaded.resolve_fake_pointer(pointer))
        elif member.member_type in (MT_REFERENCE_TO_ARRAY, MT_ARRAY_OF_REFERENCES):
            count = struct.unpack_from("<I", raw, offset)[0]
            pointer = _read_pointer(data, offset + 4, pointer_size)
            field["count"] = count
            target = loaded.resolve_fake_pointer(pointer)
            field["target"] = _pointer_ref_dict(target)
            field["truncated"] = count > max_array_refs
            if member.member_type == MT_ARRAY_OF_REFERENCES:
                field["element_refs"] = [
                    _pointer_ref_dict(ref)
                    for ref in read_array_references(
                        loaded,
                        target,
                        count,
                        max_count=max_array_refs,
                    )
                ]
        elif member.member_type == MT_REFERENCE_TO_VARIANT_ARRAY:
            type_pointer = _read_pointer(data, offset, pointer_size)
            count = struct.unpack_from("<I", raw, offset + pointer_size)[0]
            object_pointer = _read_pointer(data, offset + pointer_size + 4, pointer_size)
            field["variant_type"] = _pointer_ref_dict(loaded.resolve_fake_pointer(type_pointer))
            field["count"] = count
            field["target"] = _pointer_ref_dict(loaded.resolve_fake_pointer(object_pointer))
            field["truncated"] = count > max_array_refs
        elif member.member_type == MT_VARIANT_REFERENCE:
            type_pointer = _read_pointer(data, offset, pointer_size)
            object_pointer = _read_pointer(data, offset + pointer_size, pointer_size)
            field["variant_type"] = _pointer_ref_dict(loaded.resolve_fake_pointer(type_pointer))
            field["target"] = _pointer_ref_dict(loaded.resolve_fake_pointer(object_pointer))
        elif member.member_type in (MT_INT32, MT_UINT32):
            fmt = "<i" if member.member_type == MT_INT32 else "<I"
            field["value"] = struct.unpack_from(fmt, raw, offset)[0]
        elif member.member_type == MT_REAL32:
            field["value"] = struct.unpack_from("<f", raw, offset)[0]
        fields.append(field)
        offset += size

    return {
        "type": _pointer_ref_dict(type_ref),
        "object": _pointer_ref_dict(object_ref),
        "member_count": len(members),
        "fields": fields,
    }


def _object_storage_size(
    loaded: LoadedGR2,
    members: tuple[TypeDefinition, ...],
    pointer_size: int,
    *,
    seen: frozenset[PointerRef] = frozenset(),
) -> int:
    size = 0
    for member in members:
        if member.member_type == MT_INLINE and member.reference_type and member.reference_type not in seen:
            sub_members = parse_type_definition_array(loaded, member.reference_type)
            size += _object_storage_size(
                loaded,
                sub_members,
                pointer_size,
                seen=seen | {member.reference_type},
            )
        else:
            size += member_storage_size(member, pointer_size)
    return size


def _read_pointer(data: bytes, offset: int, pointer_size: int) -> int:
    if pointer_size == 4:
        return struct.unpack_from("<I", data, offset)[0]
    return struct.unpack_from("<Q", data, offset)[0]


def _pointer_field(loaded: LoadedGR2, data: bytes, offset: int, pointer_size: int) -> dict[str, int] | None:
    return _pointer_ref_dict(loaded.resolve_fake_pointer(_read_pointer(data, offset, pointer_size)))


def _pointer_ref_dict(ref: PointerRef | None) -> dict[str, int] | None:
    if ref is None:
        return None
    return {"section": ref.section, "offset": ref.offset}


def _field_map(summary: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {field["name"]: field for field in summary.get("fields", [])}


def _read_string_object_array(
    loaded: LoadedGR2,
    field: dict[str, Any] | None,
) -> list[str]:
    if not field:
        return []
    target = field.get("target")
    type_ref = field.get("reference_type")
    if not target or not type_ref:
        return []
    objects = read_reference_array_objects(
        loaded,
        PointerRef(target["section"], target["offset"]),
        field.get("count", 0),
        PointerRef(type_ref["section"], type_ref["offset"]),
    )
    values = []
    for obj in objects:
        value = _field_map(obj).get("String", {}).get("value")
        if isinstance(value, str):
            values.append(value)
    return values


def _looks_text(raw: bytes) -> bool:
    if not raw:
        return False
    for value in raw:
        if value in (9, 10, 13):
            continue
        if value < 32 or value == 127:
            return False
    return True
