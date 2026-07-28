"""Animation metadata extraction from loaded GR2 sections."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Iterable

from .fixup import LoadedGR2, PointerRef
from .types import (
    MT_INLINE,
    TypeDefinition,
    parse_type_definition_array,
    read_array_references,
    read_reference_array_objects,
    read_string_pointer,
    summarize_object,
    summarize_root_object,
)


@dataclass(frozen=True)
class TrackGroup:
    index: int
    name: str
    vector_track_count: int
    transform_track_count: int
    text_track_count: int
    accumulation_flags: int
    loop_translation: float
    vector_track_names: tuple[str, ...]
    transform_track_names: tuple[str, ...]
    transform_tracks: tuple["TransformTrack", ...]


@dataclass(frozen=True)
class CurveMetadata:
    codec: str
    format: int
    degree: int
    dimension: int
    knot_control_count: int
    sample_value: tuple[float, ...] = ()
    knot_values: tuple[float, ...] = ()
    control_values: tuple[tuple[float, ...], ...] = ()


@dataclass(frozen=True)
class TransformTrack:
    index: int
    name: str
    flags: int
    orientation: CurveMetadata | None
    position: CurveMetadata | None
    scale_shear: CurveMetadata | None


@dataclass(frozen=True)
class Animation:
    index: int
    name: str
    duration: float
    time_step: float
    oversampling: float
    default_loop_count: int
    flags: int
    track_group_names: tuple[str, ...]


@dataclass(frozen=True)
class AnimationSet:
    track_groups: tuple[TrackGroup, ...]
    animations: tuple[Animation, ...]


def extract_animation_set(
    loaded: LoadedGR2,
    *,
    max_track_groups: int = 64,
    max_tracks_per_group: int = 512,
    max_animations: int = 64,
) -> AnimationSet:
    root = summarize_root_object(loaded, max_arrays=max(max_track_groups, max_animations))
    fields = _field_map(root)
    track_groups = _read_track_groups(
        loaded,
        fields.get("TrackGroups"),
        max_track_groups=max_track_groups,
        max_tracks_per_group=max_tracks_per_group,
    )
    animations = _read_animations(
        loaded,
        fields.get("Animations"),
        max_animations=max_animations,
    )
    return AnimationSet(track_groups=track_groups, animations=animations)


def animation_summary(animation_set: AnimationSet | Iterable[Animation]) -> dict | list[dict]:
    if isinstance(animation_set, AnimationSet):
        return {
            "track_groups": [
                {
                    "index": item.index,
                    "name": item.name,
                    "vector_track_count": item.vector_track_count,
                    "transform_track_count": item.transform_track_count,
                    "text_track_count": item.text_track_count,
                    "accumulation_flags": item.accumulation_flags,
                    "loop_translation": item.loop_translation,
                    "first_vector_tracks": list(item.vector_track_names[:8]),
                    "first_transform_tracks": [
                        {
                            "name": track.name,
                            "orientation": _curve_metadata_dict(track.orientation),
                            "position": _curve_metadata_dict(track.position),
                            "scale_shear": _curve_metadata_dict(track.scale_shear),
                        }
                        for track in item.transform_tracks[:8]
                    ],
                }
                for item in animation_set.track_groups
            ],
            "animations": animation_summary(animation_set.animations),
        }
    return [
        {
            "index": item.index,
            "name": item.name,
            "duration": item.duration,
            "time_step": item.time_step,
            "oversampling": item.oversampling,
            "default_loop_count": item.default_loop_count,
            "flags": item.flags,
            "track_groups": list(item.track_group_names),
        }
        for item in animation_set
    ]


def sample_curve_values(
    curve: CurveMetadata,
    duration: float,
    time_step: float,
) -> tuple[float, tuple[tuple[float, ...], ...]]:
    if not curve.control_values:
        return time_step, ()
    if time_step <= 0.0:
        return time_step, curve.control_values
    sample_count = max(1, int(round(duration / time_step)) + 1)
    samples = []
    for index in range(sample_count):
        t = min(duration, index * time_step)
        samples.append(_evaluate_curve(curve, t))
    return time_step, tuple(samples)


def _read_track_groups(
    loaded: LoadedGR2,
    field: dict | None,
    *,
    max_track_groups: int,
    max_tracks_per_group: int,
) -> tuple[TrackGroup, ...]:
    type_ref = _dict_ref(field.get("reference_type") if field else None)
    refs = _read_object_refs(
        loaded,
        field,
        max_count=max_track_groups,
    )
    return tuple(
        _read_track_group(
            loaded,
            index,
            summarize_object(loaded, ref, type_ref, max_array_refs=max_tracks_per_group),
            max_tracks_per_group=max_tracks_per_group,
        )
        for index, ref in enumerate(refs)
        if type_ref is not None
    )


def _read_track_group(
    loaded: LoadedGR2,
    index: int,
    obj: dict,
    *,
    max_tracks_per_group: int,
) -> TrackGroup:
    fields = _field_map(obj)
    vector_tracks = fields.get("VectorTracks", {})
    transform_tracks = fields.get("TransformTracks", {})
    text_tracks = fields.get("TextTracks", {})
    transform_track_items = _read_transform_tracks(
        loaded,
        transform_tracks,
        max_tracks_per_group,
    )
    return TrackGroup(
        index=index,
        name=str(fields.get("Name", {}).get("value") or f"TrackGroup_{index}"),
        vector_track_count=int(vector_tracks.get("count") or 0),
        transform_track_count=int(transform_tracks.get("count") or 0),
        text_track_count=int(text_tracks.get("count") or 0),
        accumulation_flags=_field_int(fields, "AccumulationFlags", 0),
        loop_translation=_field_float(fields, "LoopTranslation", 0.0),
        vector_track_names=_read_track_names(loaded, vector_tracks, max_tracks_per_group),
        transform_track_names=tuple(track.name for track in transform_track_items),
        transform_tracks=transform_track_items,
    )


def _read_animations(
    loaded: LoadedGR2,
    field: dict | None,
    *,
    max_animations: int,
) -> tuple[Animation, ...]:
    type_ref = _dict_ref(field.get("reference_type") if field else None)
    refs = _read_object_refs(
        loaded,
        field,
        max_count=max_animations,
    )
    return tuple(
        _read_animation(loaded, index, summarize_object(loaded, ref, type_ref, max_array_refs=64))
        for index, ref in enumerate(refs)
        if type_ref is not None
    )


def _read_animation(loaded: LoadedGR2, index: int, obj: dict) -> Animation:
    fields = _field_map(obj)
    track_groups = fields.get("TrackGroups", {})
    return Animation(
        index=index,
        name=str(fields.get("Name", {}).get("value") or f"Animation_{index}"),
        duration=_field_float(fields, "Duration", 0.0),
        time_step=_field_float(fields, "TimeStep", 0.0),
        oversampling=_field_float(fields, "Oversampling", 0.0),
        default_loop_count=_field_int(fields, "DefaultLoopCount", 0),
        flags=_field_int(fields, "Flags", 0),
        track_group_names=_read_track_group_reference_names(loaded, track_groups),
    )


def _read_track_names(
    loaded: LoadedGR2,
    field: dict,
    max_count: int,
) -> tuple[str, ...]:
    target = _dict_ref(field.get("target"))
    type_ref = _dict_ref(field.get("reference_type"))
    objects = read_reference_array_objects(
        loaded,
        target,
        int(field.get("count") or 0),
        type_ref,
        max_count=max_count,
    )
    names = []
    for index, obj in enumerate(objects):
        name = _field_map(obj).get("Name", {}).get("value")
        names.append(str(name or f"Track_{index}"))
    return tuple(names)


def _read_transform_tracks(
    loaded: LoadedGR2,
    field: dict,
    max_count: int,
) -> tuple[TransformTrack, ...]:
    target = _dict_ref(field.get("target"))
    type_ref = _dict_ref(field.get("reference_type"))
    if target is None or type_ref is None:
        return ()
    members = parse_type_definition_array(loaded, type_ref)
    offsets = _member_offsets(loaded, members)
    refs = [
        PointerRef(target.section, target.offset + index * _object_storage_size(loaded, members))
        for index in range(min(int(field.get("count") or 0), max_count))
    ]
    tracks = []
    for index, ref in enumerate(refs):
        data = loaded.sections_fixed[ref.section]
        name_offset = ref.offset + offsets.get("Name", 0)
        flags_offset = ref.offset + offsets.get("Flags", 4)
        name = read_string_pointer(loaded, _read_pointer(data, name_offset, loaded.gr2.header.pointer_size // 8))
        flags = struct.unpack_from("<i", data, flags_offset)[0]
        tracks.append(
            TransformTrack(
                index=index,
                name=name or f"TransformTrack_{index}",
                flags=flags,
                orientation=_read_curve_metadata(loaded, ref.offset + offsets.get("OrientationCurve", 8), ref.section),
                position=_read_curve_metadata(loaded, ref.offset + offsets.get("PositionCurve", 16), ref.section),
                scale_shear=_read_curve_metadata(loaded, ref.offset + offsets.get("ScaleShearCurve", 24), ref.section),
            )
        )
    return tuple(tracks)


def _read_curve_metadata(
    loaded: LoadedGR2,
    offset: int,
    section: int,
) -> CurveMetadata | None:
    pointer_size = loaded.gr2.header.pointer_size // 8
    data = loaded.sections_fixed[section]
    if offset + pointer_size * 2 > len(data):
        return None
    old_curve = _read_legacy_curve_metadata(loaded, offset, section)
    if old_curve is not None:
        return old_curve
    type_ref = loaded.resolve_fake_pointer(_read_pointer(data, offset, pointer_size))
    object_ref = loaded.resolve_fake_pointer(_read_pointer(data, offset + pointer_size, pointer_size))
    if type_ref is None or object_ref is None:
        return None
    members = parse_type_definition_array(loaded, type_ref)
    if not members:
        return None
    codec = members[0].name.replace("CurveDataHeader_", "")
    offsets = _member_offsets(loaded, members)
    raw = loaded.sections_original[object_ref.section]
    if object_ref.offset + 2 > len(raw):
        return None
    fmt, degree = struct.unpack_from("<BB", raw, object_ref.offset)
    dimension = _curve_dimension(codec)
    if codec == "DaIdentity":
        dim_offset = object_ref.offset + offsets.get("Dimension", 2)
        if dim_offset + 2 <= len(raw):
            dimension = struct.unpack_from("<h", raw, dim_offset)[0]
    count = 0
    kc_offset = offsets.get("KnotsControls")
    if kc_offset is not None and object_ref.offset + kc_offset + 4 <= len(raw):
        count = struct.unpack_from("<I", raw, object_ref.offset + kc_offset)[0]
    knot_values, control_values = _read_curve_knots_controls(
        loaded,
        codec,
        dimension,
        raw,
        loaded.sections_fixed[object_ref.section],
        object_ref.offset,
        offsets,
        count,
    )
    return CurveMetadata(
        codec=codec,
        format=fmt,
        degree=degree,
        dimension=dimension,
        knot_control_count=count,
        sample_value=_read_static_curve_value(codec, dimension, raw, object_ref.offset),
        knot_values=knot_values,
        control_values=control_values,
    )


def _read_legacy_curve_metadata(
    loaded: LoadedGR2,
    offset: int,
    section: int,
) -> CurveMetadata | None:
    pointer_size = loaded.gr2.header.pointer_size // 8
    raw = loaded.sections_original[section]
    fixed = loaded.sections_fixed[section]
    if offset + 4 + (4 + pointer_size) * 2 > len(raw):
        return None
    degree = struct.unpack_from("<i", raw, offset)[0]
    if degree < 0 or degree > 3:
        return None
    knot_count = struct.unpack_from("<I", raw, offset + 4)[0]
    control_count = struct.unpack_from("<I", raw, offset + 4 + pointer_size + 4)[0]
    if knot_count == 0 and control_count == 0:
        return None
    if knot_count <= 0 or control_count <= 0 or control_count % knot_count:
        return None
    dimension = control_count // knot_count
    if dimension <= 0 or dimension > 16:
        return None
    knots_ref = _read_reference_array_pointer(loaded, fixed, offset + 4)
    controls_ref = _read_reference_array_pointer(loaded, fixed, offset + 4 + pointer_size + 4)
    if knots_ref is None or controls_ref is None:
        return None
    knot_bytes = loaded.sections_fixed[knots_ref.section][knots_ref.offset : knots_ref.offset + knot_count * 4]
    control_bytes = loaded.sections_fixed[controls_ref.section][controls_ref.offset : controls_ref.offset + control_count * 4]
    if len(knot_bytes) < knot_count * 4 or len(control_bytes) < control_count * 4:
        return None
    knots = struct.unpack_from("<" + "f" * knot_count, knot_bytes, 0)
    flat_controls = struct.unpack_from("<" + "f" * control_count, control_bytes, 0)
    controls = tuple(
        tuple(flat_controls[index * dimension + dim] for dim in range(dimension))
        for index in range(knot_count)
    )
    sample_value = controls[0] if knot_count == 1 else ()
    return CurveMetadata(
        codec="LegacyCurve32f",
        format=-1,
        degree=degree,
        dimension=dimension,
        knot_control_count=knot_count + control_count,
        sample_value=sample_value,
        knot_values=tuple(knots),
        control_values=controls,
    )


def _read_track_group_reference_names(loaded: LoadedGR2, field: dict) -> tuple[str, ...]:
    target = _dict_ref(field.get("target"))
    type_ref = _dict_ref(field.get("reference_type"))
    refs = read_array_references(
        loaded,
        target,
        int(field.get("count") or 0),
        max_count=64,
    )
    names = []
    for index, ref in enumerate(refs):
        if type_ref is None:
            names.append(f"TrackGroup_{index}")
            continue
        fields = _field_map(summarize_object(loaded, ref, type_ref, max_array_refs=0))
        names.append(str(fields.get("Name", {}).get("value") or f"TrackGroup_{index}"))
    return tuple(names)


def _read_object_refs(
    loaded: LoadedGR2,
    field: dict | None,
    *,
    max_count: int,
) -> tuple[PointerRef, ...]:
    target = _dict_ref(field.get("target") if field else None)
    return read_array_references(
        loaded,
        target,
        int(field.get("count") or 0) if field else 0,
        max_count=max_count,
    )


def _dict_ref(value: dict | None) -> PointerRef | None:
    if not value:
        return None
    return PointerRef(int(value["section"]), int(value["offset"]))


def _curve_dimension(codec: str) -> int:
    if codec.startswith("D") and len(codec) >= 2 and codec[1].isdigit():
        return int(codec[1])
    return 0


def _curve_metadata_dict(curve: CurveMetadata | None) -> dict | None:
    if curve is None:
        return None
    result = {
        "codec": curve.codec,
        "format": curve.format,
        "degree": curve.degree,
        "dimension": curve.dimension,
        "knot_control_count": curve.knot_control_count,
    }
    if curve.sample_value:
        result["sample_value"] = list(curve.sample_value)
    if curve.knot_values:
        result["knot_count"] = len(curve.knot_values)
        result["first_knot_values"] = list(curve.knot_values[:4])
    if curve.control_values:
        result["control_count"] = len(curve.control_values)
        result["first_control_values"] = [list(item) for item in curve.control_values[:2]]
    return result


def _read_curve_knots_controls(
    loaded: LoadedGR2,
    codec: str,
    dimension: int,
    raw: bytes,
    fixed: bytes,
    offset: int,
    offsets: dict[str, int],
    knot_control_count: int,
) -> tuple[tuple[float, ...], tuple[tuple[float, ...], ...]]:
    if knot_control_count <= 0 or dimension <= 0:
        return (), ()
    kc_offset = offsets.get("KnotsControls")
    if kc_offset is None:
        return (), ()
    array_offset = offset + kc_offset
    array_ref = _read_reference_array_pointer(loaded, fixed, array_offset)
    if array_ref is None:
        return (), ()
    if codec in {"D3K16uC16u", "D3I1K16uC16u"}:
        return _read_d3_k16u_c16u_curve(loaded, codec, dimension, raw, offset, offsets, knot_control_count, array_ref)
    if codec == "D4nK8uC7u":
        return _read_d4n_k8u_c7u_curve(loaded, raw, offset, offsets, knot_control_count, array_ref)
    if codec == "D4nK16uC15u":
        return _read_d4n_k16u_c15u_curve(loaded, raw, offset, offsets, knot_control_count, array_ref)
    return (), ()


def _read_d3_k16u_c16u_curve(
    loaded: LoadedGR2,
    codec: str,
    dimension: int,
    raw: bytes,
    offset: int,
    offsets: dict[str, int],
    knot_control_count: int,
    array_ref: PointerRef,
) -> tuple[tuple[float, ...], tuple[tuple[float, ...], ...]]:
    knot_count = knot_control_count // (2 if codec == "D3I1K16uC16u" else dimension + 1)
    if knot_count <= 0:
        return (), ()
    one_over_offset = offset + offsets.get("OneOverKnotScaleTrunc", 2)
    scales_offset = offset + offsets.get("ControlScales", 4)
    offsets_offset = offset + offsets.get("ControlOffsets", 16)
    if offsets_offset + dimension * 4 > len(raw):
        return (), ()
    one_over = _float_from_high_u16(struct.unpack_from("<H", raw, one_over_offset)[0])
    if one_over == 0.0:
        return (), ()
    control_scales = struct.unpack_from("<" + "f" * dimension, raw, scales_offset)
    control_offsets = struct.unpack_from("<" + "f" * dimension, raw, offsets_offset)
    array_data = loaded.sections_fixed[array_ref.section]
    data = array_data[array_ref.offset : array_ref.offset + knot_control_count * 2]
    if len(data) < knot_control_count * 2:
        return (), ()
    values = struct.unpack_from("<" + "H" * knot_control_count, data, 0)
    knot_scale = 1.0 / one_over
    knots = tuple(knot_scale * value for value in values[:knot_count])
    controls: list[tuple[float, ...]] = []
    if codec == "D3I1K16uC16u":
        for param in values[knot_count : knot_count * 2]:
            controls.append(tuple(control_offsets[dim] + control_scales[dim] * param for dim in range(dimension)))
    else:
        control_data = values[knot_count : knot_count + knot_count * dimension]
        for index in range(knot_count):
            base = index * dimension
            controls.append(
                tuple(
                    control_offsets[dim] + control_scales[dim] * control_data[base + dim]
                    for dim in range(dimension)
                )
            )
    return knots, tuple(controls)


def _read_d4n_k8u_c7u_curve(
    loaded: LoadedGR2,
    raw: bytes,
    offset: int,
    offsets: dict[str, int],
    knot_control_count: int,
    array_ref: PointerRef,
) -> tuple[tuple[float, ...], tuple[tuple[float, ...], ...]]:
    knot_count = knot_control_count // 4
    if knot_count <= 0:
        return (), ()
    scale_entries_offset = offset + offsets.get("ScaleOffsetTableEntries", 2)
    one_over_offset = offset + offsets.get("OneOverKnotScale", 4)
    if one_over_offset + 4 > len(raw):
        return (), ()
    one_over = struct.unpack_from("<f", raw, one_over_offset)[0]
    if one_over == 0.0:
        return (), ()
    array_data = loaded.sections_fixed[array_ref.section]
    data = array_data[array_ref.offset : array_ref.offset + knot_control_count]
    if len(data) < knot_control_count:
        return (), ()
    knot_scale = 1.0 / one_over
    knots = tuple(knot_scale * float(value) for value in data[:knot_count])
    scales, offsets_values = _quaternion_scales_offsets(struct.unpack_from("<H", raw, scale_entries_offset)[0])
    controls = []
    control_bytes = data[knot_count : knot_count + knot_count * 3]
    for index in range(knot_count):
        cur = control_bytes[index * 3 : index * 3 + 3]
        missing_negative = (cur[0] & 0x80) != 0
        missing_index = ((cur[1] >> 6) & 0x2) | (cur[2] >> 7)
        result = [0.0, 0.0, 0.0, 0.0]
        dst = missing_index
        summed_sq = 0.0
        for src in range(3):
            dst = (dst + 1) & 0x3
            value = offsets_values[dst] + scales[dst] * float(cur[src] & 0x7F)
            result[dst] = value
            summed_sq += value * value
        missing = max(0.0, 1.0 - summed_sq) ** 0.5
        result[missing_index] = -missing if missing_negative else missing
        controls.append(tuple(result))
    return knots, tuple(controls)


def _read_d4n_k16u_c15u_curve(
    loaded: LoadedGR2,
    raw: bytes,
    offset: int,
    offsets: dict[str, int],
    knot_control_count: int,
    array_ref: PointerRef,
) -> tuple[tuple[float, ...], tuple[tuple[float, ...], ...]]:
    knot_count = knot_control_count // 4
    if knot_count <= 0:
        return (), ()
    scale_entries_offset = offset + offsets.get("ScaleOffsetTableEntries", 2)
    one_over_offset = offset + offsets.get("OneOverKnotScale", 4)
    if one_over_offset + 4 > len(raw):
        return (), ()
    one_over = struct.unpack_from("<f", raw, one_over_offset)[0]
    if one_over == 0.0:
        return (), ()
    array_data = loaded.sections_fixed[array_ref.section]
    data = array_data[array_ref.offset : array_ref.offset + knot_control_count * 2]
    if len(data) < knot_control_count * 2:
        return (), ()
    values = struct.unpack_from("<" + "H" * knot_control_count, data, 0)
    knot_scale = 1.0 / one_over
    knots = tuple(knot_scale * float(value) for value in values[:knot_count])
    scales, offsets_values = _quaternion_scales_offsets(
        struct.unpack_from("<H", raw, scale_entries_offset)[0],
        quantized_max=32767.0,
    )
    controls = []
    control_values = values[knot_count : knot_count + knot_count * 3]
    for index in range(knot_count):
        cur = control_values[index * 3 : index * 3 + 3]
        missing_negative = (cur[0] & 0x8000) != 0
        missing_index = ((cur[1] >> 14) & 0x2) | (cur[2] >> 15)
        result = [0.0, 0.0, 0.0, 0.0]
        dst = missing_index
        summed_sq = 0.0
        for src in range(3):
            dst = (dst + 1) & 0x3
            value = offsets_values[dst] + scales[dst] * float(cur[src] & 0x7FFF)
            result[dst] = value
            summed_sq += value * value
        missing = max(0.0, 1.0 - summed_sq) ** 0.5
        result[missing_index] = -missing if missing_negative else missing
        controls.append(tuple(result))
    return knots, tuple(controls)


def _read_reference_array_pointer(loaded: LoadedGR2, fixed: bytes, offset: int) -> PointerRef | None:
    pointer_size = loaded.gr2.header.pointer_size // 8
    if offset + 4 + pointer_size > len(fixed):
        return None
    return loaded.resolve_fake_pointer(_read_pointer(fixed, offset + 4, pointer_size))


def _evaluate_curve(curve: CurveMetadata, t: float) -> tuple[float, ...]:
    knots = curve.knot_values
    controls = curve.control_values
    if not knots or not controls:
        return curve.sample_value
    degree = max(0, int(curve.degree))
    if degree == 0 or len(knots) == 1:
        return controls[min(_find_knot(knots, t), len(controls) - 1)]
    knot_index = min(_find_knot(knots, t), len(knots) - 1)
    window = 2 * degree
    base = knot_index - degree
    ti = []
    pi = []
    for local_index in range(window):
        source_index = min(max(base + local_index, 0), len(knots) - 1)
        ti.append(knots[source_index])
        pi.append(controls[min(source_index, len(controls) - 1)])
    value = _sample_bspline(degree, curve.dimension, curve.dimension == 4, ti, pi, degree, t)
    if curve.dimension == 4:
        return _normalize_tuple(value)
    return value


def _find_knot(knots: tuple[float, ...], t: float) -> int:
    for index, value in enumerate(knots):
        if value > t:
            return index
    return max(0, len(knots) - 1)


def _sample_bspline(
    degree: int,
    dimension: int,
    normalize: bool,
    ti: list[float],
    pi: list[tuple[float, ...]],
    center: int,
    t: float,
) -> tuple[float, ...]:
    if degree == 1:
        c_prev, c_curr = _linear_coefficients(ti[center - 1], ti[center], t)
        result = tuple(c_prev * pi[center - 1][dim] + c_curr * pi[center][dim] for dim in range(dimension))
    elif degree == 2:
        c2, c1, c0 = _quadratic_coefficients(ti[center - 2], ti[center - 1], ti[center], ti[center + 1], t)
        result = tuple(
            c2 * pi[center - 2][dim] + c1 * pi[center - 1][dim] + c0 * pi[center][dim]
            for dim in range(dimension)
        )
    else:
        result = pi[center]
    return _normalize_tuple(result) if normalize else result


def _linear_coefficients(ti_prev: float, ti_curr: float, t: float) -> tuple[float, float]:
    blend = _safe_div(t - ti_prev, ti_curr - ti_prev)
    return 1.0 - blend, blend


def _quadratic_coefficients(
    ti_2: float,
    ti_1: float,
    ti: float,
    ti1: float,
    t: float,
) -> tuple[float, float, float]:
    l0 = _safe_div(t - ti_1, ti - ti_1)
    l1_1 = _safe_div(t - ti_2, ti - ti_2)
    l1_2 = _safe_div(t - ti_1, ti1 - ti_1)
    ci_2_plus_ci_1 = (l1_1 + l0) - l0 * l1_1
    ci = l0 * l1_2
    ci_1 = ci_2_plus_ci_1 - ci
    ci_2 = 1.0 - ci_2_plus_ci_1
    return ci_2, ci_1, ci


def _safe_div(numerator: float, denominator: float) -> float:
    if abs(denominator) < 1e-12:
        return 0.0
    return numerator / denominator


def _normalize_tuple(values: tuple[float, ...]) -> tuple[float, ...]:
    length_sq = sum(value * value for value in values)
    if length_sq <= 0.0:
        return values
    inv_length = length_sq ** -0.5
    return tuple(value * inv_length for value in values)


def _float_from_high_u16(value: int) -> float:
    return struct.unpack("<f", struct.pack("<I", value << 16))[0]


def _quaternion_scales_offsets(
    entries: int,
    *,
    quantized_max: float = 127.0,
) -> tuple[tuple[float, ...], tuple[float, ...]]:
    table = _quaternion_scale_offset_table()
    scales = []
    offsets = []
    for _ in range(4):
        index = entries & 0xF
        entries >>= 4
        scales.append(table[index][0] / quantized_max)
        offsets.append(table[index][1])
    return tuple(scales), tuple(offsets)


def _quaternion_scale_offset_table() -> tuple[tuple[float, float], ...]:
    one_over_sqrt2 = 0.707106781
    return (
        (one_over_sqrt2 * 2.0, -one_over_sqrt2),
        (one_over_sqrt2 * 1.0, -one_over_sqrt2 * 0.5),
        (one_over_sqrt2 * 0.5, -one_over_sqrt2 * 0.75),
        (one_over_sqrt2 * 0.5, -one_over_sqrt2 * 0.25),
        (one_over_sqrt2 * 0.5, one_over_sqrt2 * 0.25),
        (one_over_sqrt2 * 0.25, -one_over_sqrt2 * 0.250),
        (one_over_sqrt2 * 0.25, -one_over_sqrt2 * 0.125),
        (one_over_sqrt2 * 0.25, one_over_sqrt2 * 0.000),
        (-one_over_sqrt2 * 2.0, one_over_sqrt2),
        (-one_over_sqrt2 * 1.0, one_over_sqrt2 * 0.5),
        (-one_over_sqrt2 * 0.5, one_over_sqrt2 * 0.75),
        (-one_over_sqrt2 * 0.5, one_over_sqrt2 * 0.25),
        (-one_over_sqrt2 * 0.5, -one_over_sqrt2 * 0.25),
        (-one_over_sqrt2 * 0.25, one_over_sqrt2 * 0.250),
        (-one_over_sqrt2 * 0.25, one_over_sqrt2 * 0.125),
        (-one_over_sqrt2 * 0.25, -one_over_sqrt2 * 0.000),
    )


def _read_static_curve_value(
    codec: str,
    dimension: int,
    raw: bytes,
    offset: int,
) -> tuple[float, ...]:
    if dimension <= 0:
        return ()
    if codec.endswith("Constant32f"):
        controls_offset = offset + 4
        byte_count = dimension * 4
        if controls_offset + byte_count <= len(raw):
            return struct.unpack_from("<" + "f" * dimension, raw, controls_offset)
        return ()
    if codec == "DaIdentity":
        if dimension == 9:
            return (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        if dimension == 4:
            return (0.0, 0.0, 0.0, 1.0)
        return tuple(0.0 for _ in range(dimension))
    return ()


def _member_offsets(loaded: LoadedGR2, members: tuple[TypeDefinition, ...]) -> dict[str, int]:
    offsets = {}
    offset = 0
    for member in members:
        offsets[member.name] = offset
        offset += _member_size(loaded, member)
    return offsets


def _object_storage_size(loaded: LoadedGR2, members: tuple[TypeDefinition, ...]) -> int:
    return sum(_member_size(loaded, member) for member in members)


def _member_size(loaded: LoadedGR2, member: TypeDefinition) -> int:
    pointer_size = loaded.gr2.header.pointer_size // 8
    if member.member_type == MT_INLINE and member.reference_type is not None:
        return _object_storage_size(loaded, parse_type_definition_array(loaded, member.reference_type))
    from .types import member_storage_size

    return member_storage_size(member, pointer_size)


def _read_pointer(data: bytes, offset: int, pointer_size: int) -> int:
    if pointer_size == 4:
        return struct.unpack_from("<I", data, offset)[0]
    return struct.unpack_from("<Q", data, offset)[0]


def _field_map(summary: dict) -> dict[str, dict]:
    return {field["name"]: field for field in summary.get("fields", [])}


def _field_int(fields: dict[str, dict], name: str, default: int) -> int:
    value = fields.get(name, {}).get("value")
    return default if value is None else int(value)


def _field_float(fields: dict[str, dict], name: str, default: float) -> float:
    value = fields.get(name, {}).get("value")
    return default if value is None else float(value)
