"""Material and texture metadata extraction."""

from __future__ import annotations

from dataclasses import dataclass

from .fixup import LoadedGR2, PointerRef
from .types import read_reference_array_objects, summarize_object, summarize_root_object


@dataclass(frozen=True)
class MaterialInfo:
    index: int
    name: str
    texture_file: str
    texture_size: tuple[int, int] | None


def material_map(loaded: LoadedGR2, max_materials: int = 4096) -> dict[tuple[int, int], MaterialInfo]:
    root = summarize_root_object(loaded, max_arrays=max_materials)
    material_field = _field_map(root).get("Materials")
    material_type = _dict_ref(material_field.get("reference_type") if material_field else None)
    refs = [
        _dict_ref(ref)
        for ref in (material_field or {}).get("element_refs", [])[:max_materials]
    ]
    result: dict[tuple[int, int], MaterialInfo] = {}
    for index, ref in enumerate(ref for ref in refs if ref is not None):
        result[(ref.section, ref.offset)] = _read_material(loaded, ref, material_type, index, result, frozenset())
    return result


def extract_materials(loaded: LoadedGR2, max_materials: int = 4096) -> tuple[MaterialInfo, ...]:
    return tuple(sorted(material_map(loaded, max_materials).values(), key=lambda item: item.index))


def _read_material(
    loaded: LoadedGR2,
    ref: PointerRef,
    material_type: PointerRef | None,
    index: int,
    cache: dict[tuple[int, int], MaterialInfo],
    seen: frozenset[tuple[int, int]],
) -> MaterialInfo:
    key = (ref.section, ref.offset)
    if key in cache:
        return cache[key]
    if material_type is None or key in seen:
        return MaterialInfo(index=index, name=f"Material_{index}", texture_file="", texture_size=None)

    summary = summarize_object(loaded, ref, material_type, max_array_refs=16)
    fields = _field_map(summary)
    texture = _read_texture_field(loaded, fields.get("Texture"))
    if texture is None:
        texture = _read_first_map_texture(loaded, fields.get("Maps"), material_type, cache, seen | {key})

    texture_file = texture[0] if texture else ""
    texture_size = texture[1] if texture else None
    return MaterialInfo(
        index=index,
        name=str(fields.get("Name", {}).get("value") or f"Material_{index}"),
        texture_file=texture_file,
        texture_size=texture_size,
    )


def _read_first_map_texture(
    loaded: LoadedGR2,
    maps_field: dict | None,
    material_type: PointerRef,
    cache: dict[tuple[int, int], MaterialInfo],
    seen: frozenset[tuple[int, int]],
) -> tuple[str, tuple[int, int] | None] | None:
    if not maps_field:
        return None
    target = _dict_ref(maps_field.get("target"))
    map_type = _dict_ref(maps_field.get("reference_type"))
    maps = read_reference_array_objects(
        loaded,
        target,
        int(maps_field.get("count") or 0),
        map_type,
        max_count=16,
    )
    for item in maps:
        fields = _field_map(item)
        map_ref = _dict_ref(fields.get("Map", {}).get("target"))
        if map_ref is None:
            continue
        material = _read_material(loaded, map_ref, material_type, -1, cache, seen)
        if material.texture_file:
            return material.texture_file, material.texture_size
    return None


def _read_texture_field(
    loaded: LoadedGR2,
    texture_field: dict | None,
) -> tuple[str, tuple[int, int] | None] | None:
    if not texture_field:
        return None
    target = _dict_ref(texture_field.get("target"))
    texture_type = _dict_ref(texture_field.get("reference_type"))
    if target is None or texture_type is None:
        return None
    summary = summarize_object(loaded, target, texture_type, max_array_refs=8)
    fields = _field_map(summary)
    width = fields.get("Width", {}).get("value")
    height = fields.get("Height", {}).get("value")
    size = (int(width), int(height)) if width is not None and height is not None else None
    return str(fields.get("FromFileName", {}).get("value") or ""), size


def _dict_ref(value: dict | None) -> PointerRef | None:
    if not value:
        return None
    return PointerRef(int(value["section"]), int(value["offset"]))


def _field_map(summary: dict) -> dict[str, dict]:
    return {field["name"]: field for field in summary.get("fields", [])}
