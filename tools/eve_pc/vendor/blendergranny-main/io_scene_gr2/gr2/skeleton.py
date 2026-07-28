"""Skeleton extraction from loaded GR2 sections."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Iterable

from .fixup import LoadedGR2, PointerRef
from .types import (
    read_reference_array_objects,
    summarize_object,
    summarize_root_object,
)


@dataclass(frozen=True)
class Transform:
    flags: int
    position: tuple[float, float, float]
    orientation: tuple[float, float, float, float]
    scale_shear: tuple[float, ...]


@dataclass(frozen=True)
class SkeletonBone:
    index: int
    name: str
    parent_index: int
    transform: Transform
    inverse_world_transform: tuple[float, ...]


@dataclass(frozen=True)
class Skeleton:
    name: str
    bones: tuple[SkeletonBone, ...]
    lod_type: int


def extract_skeletons(loaded: LoadedGR2, max_skeletons: int = 16) -> tuple[Skeleton, ...]:
    root = summarize_root_object(loaded, max_arrays=max_skeletons)
    skeleton_field = _field_map(root).get("Skeletons")
    if not skeleton_field:
        return ()
    skeleton_type = _dict_ref(skeleton_field.get("reference_type"))
    skeleton_refs = [
        _dict_ref(ref)
        for ref in skeleton_field.get("element_refs", [])[:max_skeletons]
    ]

    skeletons: list[Skeleton] = []
    for skeleton_ref in skeleton_refs:
        if skeleton_ref is None or skeleton_type is None:
            continue
        summary = summarize_object(loaded, skeleton_ref, skeleton_type, max_array_refs=4096)
        fields = _field_map(summary)
        bone_field = fields.get("Bones", {})
        bone_target = _dict_ref(bone_field.get("target"))
        bone_type = _dict_ref(bone_field.get("reference_type"))
        bone_objects = read_reference_array_objects(
            loaded,
            bone_target,
            int(bone_field.get("count") or 0),
            bone_type,
            max_count=4096,
        )
        bones = tuple(
            _read_bone(loaded, bone_index, bone_object)
            for bone_index, bone_object in enumerate(bone_objects)
        )
        skeletons.append(
            Skeleton(
                name=str(fields.get("Name", {}).get("value") or f"Skeleton_{len(skeletons)}"),
                bones=bones,
                lod_type=_field_int(fields, "LODType", 0),
            )
        )
    return tuple(skeletons)


def skeleton_summary(skeletons: Iterable[Skeleton]) -> list[dict]:
    result = []
    for skeleton in skeletons:
        result.append(
            {
                "name": skeleton.name,
                "bone_count": len(skeleton.bones),
                "lod_type": skeleton.lod_type,
                "root_bones": [bone.name for bone in skeleton.bones if bone.parent_index < 0],
                "first_bones": [
                    {
                        "name": bone.name,
                        "parent_index": bone.parent_index,
                        "position": bone.transform.position,
                    }
                    for bone in skeleton.bones[:8]
                ],
            }
        )
    return result


def _read_bone(loaded: LoadedGR2, index: int, bone_object: dict) -> SkeletonBone:
    fields = _field_map(bone_object)
    transform_offset = int(fields.get("Transform", {}).get("offset") or 0)
    object_ref = _dict_ref(bone_object.get("object"))
    transform = Transform(0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0))
    inverse_world_transform: tuple[float, ...] = ()

    if object_ref is not None:
        transform = _read_transform(loaded, PointerRef(object_ref.section, transform_offset))
        inverse_offset = int(fields.get("InverseWorldTransform", {}).get("offset") or 0)
        inverse_world_transform = _read_real32_array(
            loaded,
            PointerRef(object_ref.section, inverse_offset),
            16,
        )

    return SkeletonBone(
        index=index,
        name=str(fields.get("Name", {}).get("value") or f"Bone_{index}"),
        parent_index=_field_int(fields, "ParentIndex", -1),
        transform=transform,
        inverse_world_transform=inverse_world_transform,
    )


def _read_transform(loaded: LoadedGR2, ref: PointerRef) -> Transform:
    data = loaded.read_ref(ref, 68, fixed=False)
    flags = struct.unpack_from("<I", data, 0)[0]
    values = struct.unpack_from("<16f", data, 4)
    return Transform(
        flags=flags,
        position=values[0:3],
        orientation=values[3:7],
        scale_shear=values[7:16],
    )


def _read_real32_array(loaded: LoadedGR2, ref: PointerRef, count: int) -> tuple[float, ...]:
    data = loaded.read_ref(ref, count * 4, fixed=False)
    return struct.unpack_from("<" + "f" * count, data, 0)


def _dict_ref(value: dict | None) -> PointerRef | None:
    if not value:
        return None
    return PointerRef(int(value["section"]), int(value["offset"]))


def _field_map(summary: dict) -> dict[str, dict]:
    return {field["name"]: field for field in summary.get("fields", [])}


def _field_int(fields: dict[str, dict], name: str, default: int) -> int:
    value = fields.get(name, {}).get("value")
    return default if value is None else int(value)
