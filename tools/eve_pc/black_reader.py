# -*- coding: utf-8 -*-
"""Minimal CCP black-file reader (SOF-oriented) with unknown-property recovery.

Format (black-reader-js compatible): FOURCC 0xB1ACF11E, version 1,
string table, comment table, then typed object graph.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Any, Callable, Optional


FOURCC = 0xB1ACF11E


class BlackError(Exception):
    pass


@dataclass
class Reader:
    data: memoryview
    offset: int = 0
    strings: list[str] = field(default_factory=list)
    references: dict[int, Any] = field(default_factory=dict)
    schemas: dict[str, dict[str, Callable]] = field(default_factory=dict)

    def remaining(self) -> int:
        return len(self.data) - self.offset

    def at_end(self) -> bool:
        return self.offset >= len(self.data)

    def slice(self, n: int) -> "Reader":
        if n < 0 or n > self.remaining():
            raise BlackError(f"slice {n} beyond remaining {self.remaining()}")
        sub = Reader(
            self.data[self.offset : self.offset + n],
            0,
            self.strings,
            self.references,
            self.schemas,
        )
        self.offset += n
        return sub

    def u8(self) -> int:
        v = self.data[self.offset]
        self.offset += 1
        return v

    def u16(self) -> int:
        (v,) = struct.unpack_from("<H", self.data, self.offset)
        self.offset += 2
        return v

    def u32(self) -> int:
        (v,) = struct.unpack_from("<I", self.data, self.offset)
        self.offset += 4
        return v

    def i32(self) -> int:
        (v,) = struct.unpack_from("<i", self.data, self.offset)
        self.offset += 4
        return v

    def f32(self) -> float:
        (v,) = struct.unpack_from("<f", self.data, self.offset)
        self.offset += 4
        return float(v)

    def cstring(self) -> str:
        start = self.offset
        while self.offset < len(self.data) and self.data[self.offset] != 0:
            self.offset += 1
        s = bytes(self.data[start : self.offset]).decode("utf-8", "replace")
        self.offset += 1
        return s

    def cwstring(self) -> str:
        start = self.offset
        while self.offset + 1 < len(self.data):
            (ch,) = struct.unpack_from("<H", self.data, self.offset)
            self.offset += 2
            if ch == 0:
                break
        return bytes(self.data[start : self.offset - 2]).decode("utf-16le", "replace")

    def string_u16(self) -> str:
        key = self.u16()
        if key >= len(self.strings):
            raise BlackError(f"string key {key} >= {len(self.strings)}")
        return self.strings[key]

    def expect_u32(self, expected: int, msg: str) -> None:
        got = self.u32()
        if got != expected:
            raise BlackError(f"{msg}: got {got:#x}, expected {expected:#x}")


def _boolean(r: Reader) -> bool:
    return r.u8() != 0


def _byte(r: Reader) -> int:
    return r.u8()


def _float(r: Reader) -> float:
    return r.f32()


def _uint(r: Reader) -> int:
    return r.u32()


def _ushort(r: Reader) -> int:
    return r.u16()


def _string(r: Reader) -> str:
    return r.string_u16()


def _path(r: Reader) -> str:
    return r.string_u16()


def _vector2(r: Reader) -> list[float]:
    return [r.f32(), r.f32()]


def _vector3(r: Reader) -> list[float]:
    return [r.f32(), r.f32(), r.f32()]


def _vector4(r: Reader) -> list[float]:
    return [r.f32(), r.f32(), r.f32(), r.f32()]


def _color(r: Reader) -> list[float]:
    return _vector4(r)


def _quaternion(r: Reader) -> list[float]:
    return _vector4(r)


def _matrix4(r: Reader) -> list[list[float]]:
    return [_vector4(r), _vector4(r), _vector4(r), _vector4(r)]


def _array(r: Reader) -> list[Any]:
    count = r.u32()
    return [_object(r) for _ in range(count)]


def _raw_object(r: Reader) -> Any:
    return _object(r, forced_id=None)


def _object(r: Reader, forced_id: Optional[int] = ...) -> Any:  # type: ignore[assignment]
    if forced_id is ...:
        oid = r.u32()
        if oid == 0:
            return None
        if oid in r.references:
            return r.references[oid]
    else:
        oid = forced_id

    length = r.u32()
    obj_r = r.slice(length)
    typ = obj_r.string_u16()
    result: dict[str, Any] = {"__type": typ, "__id": oid}
    if oid is not None:
        r.references[oid] = result

    schema = r.schemas.get(typ)
    if schema is None or len(schema) == 0:
        ## Opaque / unused type: skip rest of this object blob (keeps stream synced).
        obj_r.offset = len(obj_r.data)
        return result

    while not obj_r.at_end():
        prop = obj_r.string_u16()
        if prop in schema:
            result[prop] = schema[prop](obj_r)
            continue
        # Known type, new property: recover without desyncing the object.
        result[prop] = _recover_value(obj_r)
    return result


def _peek_next_is_prop_or_end(r: Reader) -> bool:
    if r.at_end():
        return True
    if r.remaining() < 2:
        return False
    key = struct.unpack_from("<H", r.data, r.offset)[0]
    return 0 <= key < len(r.strings)


def _recover_value(r: Reader) -> Any:
    """Best-effort skip of an unknown property value."""
    trials: list[tuple[str, Callable[[Reader], Any]]] = [
        ("object", lambda rr: _object(rr)),
        ("array", _array),
        ("matrix4", _matrix4),
        ("vector4", _vector4),
        ("vector3", _vector3),
        ("vector2", _vector2),
        ("float", _float),
        ("uint", _uint),
        ("ushort", _ushort),
        ("boolean", _boolean),
        ("string", _string),
        ("byte", _byte),
    ]
    for name, fn in trials:
        saved = r.offset
        try:
            val = fn(r)
            if _peek_next_is_prop_or_end(r):
                return {"__recovered": name, "value": val}
        except Exception:
            pass
        r.offset = saved
    # Last resort: consume rest of object (caller object ends).
    leftover = bytes(r.data[r.offset :])
    r.offset = len(r.data)
    return {"__recovered": "opaque", "bytes": len(leftover)}


# Bind object readers that need mutual recursion.
_object.complex = True  # type: ignore[attr-defined]
_array.complex = True  # type: ignore[attr-defined]
_raw_object.complex = True  # type: ignore[attr-defined]


def sof_schemas() -> dict[str, dict[str, Callable]]:
    """Subset + full SOF hull/booster schemas we care about (unknown props recovered)."""
    s: dict[str, dict[str, Callable]] = {}

    def d(typ: str, props: dict[str, Callable]) -> None:
        s[typ] = props

    d(
        "EveSOFData",
        {
            "faction": _array,
            "generic": _object,
            "hull": _array,
            "layout": _array,
            "material": _array,
            "pattern": _array,
            "race": _array,
        },
    )
    d(
        "EveSOFDataHull",
        {
            "additiveAreas": _array,
            "animations": _array,
            "audioPosition": _vector3,
            "banners": _array,
            "bannerSets": _array,
            "booster": _object,
            "boundingSphere": _vector4,
            "buildClass": _uint,
            "buildFilter": _uint,
            "castShadow": _boolean,
            "category": _string,
            "children": _array,
            "childSets": _array,
            "controllers": _array,
            "decalAreas": _array,
            "decalSets": _array,
            "defaultPattern": _object,
            "depthAreas": _array,
            "description": _string,
            "distortionAreas": _array,
            "enableDynamicBoundingSphere": _boolean,
            "geometryResFilePath": _path,
            "hazeSets": _array,
            "hullDecals": _array,
            "impactEffectType": _uint,
            "instancedMeshes": _array,
            "isSkinned": _boolean,
            "lightSets": _array,
            "locatorSets": _array,
            "locatorTurrets": _array,
            "name": _string,
            "opaqueAreas": _array,
            "planeSets": _array,
            "modelRotationCurvePath": _path,
            "shapeEllipsoidCenter": _vector3,
            "shapeEllipsoidRadius": _vector3,
            "sof6": _boolean,
            "soundEmitters": _array,
            "spotlightSets": _array,
            "spriteLineSets": _array,
            "spriteSets": _array,
            "transparentAreas": _array,
            "visibilityGroup": _string,
        },
    )
    d(
        "EveSOFDataHullBooster",
        {
            "alwaysOn": _boolean,
            "hasTrails": _boolean,
            "items": _array,
        },
    )
    d(
        "EveSOFDataHullBoosterItem",
        {
            "atlasIndex0": _uint,
            "atlasIndex1": _uint,
            "functionality": _vector4,
            "hasTrail": _boolean,
            "lightScale": _float,
            "transform": _matrix4,
        },
    )
    d(
        "EveSOFDataHullLocator",
        {
            "name": _string,
            "transform": _matrix4,
        },
    )
    d(
        "EveSOFDataHullLocatorSet",
        {
            "name": _string,
            "locators": _array,
        },
    )
    d(
        "EveSOFDataHullLocatorSetGroup",
        {
            "name": _string,
            "locatorSets": _array,
        },
    )
    d(
        "EveSOFDataRace",
        {
            "booster": _object,
            "damage": _object,
            "name": _string,
        },
    )
    d(
        "EveSOFDataBooster",
        {
            "glowColor": _color,
            "glowScale": _float,
            "gradient0ResPath": _path,
            "gradient1ResPath": _path,
            "haloColor": _color,
            "haloScaleX": _float,
            "haloScaleY": _float,
            "lightFlickerAmplitude": _float,
            "lightFlickerColor": _color,
            "lightFlickerFrequency": _float,
            "lightFlickerRadius": _float,
            "lightColor": _color,
            "lightRadius": _float,
            "lightWarpColor": _color,
            "lightWarpRadius": _float,
            "shape0": _object,
            "shape1": _object,
            "shapeAtlasCount": _uint,
            "shapeAtlasHeight": _uint,
            "shapeAtlasResPath": _path,
            "shapeAtlasWidth": _uint,
            "symHaloScale": _float,
            "trailColor": _color,
            "trailSize": _vector4,
            "volumetric": _boolean,
            "warpGlowColor": _color,
            "warpHalpColor": _color,
            "warpShape0": _object,
            "warpShape1": _object,
        },
    )
    d(
        "EveSOFDataBoosterShape",
        {
            "color": _color,
            "noiseFunction": _float,
            "noiseSpeed": _float,
            "noiseAmplitureStart": _vector4,
            "noiseAmplitureEnd": _vector4,
            "noiseFrequency": _vector4,
        },
    )
    # Empty / passthrough types commonly nested; unknown props recovered.
    for empty in (
        "EveSOFDataGeneric",
        "EveSOFDataFaction",
        "EveSOFDataMaterial",
        "EveSOFDataPattern",
        "EveSOFDataLayout",
        "EveSOFDataHullArea",
        "EveSOFDataHullAnimation",
        "EveSOFDataHullChild",
        "EveSOFDataHullController",
        "EveSOFDataHullDecalSet",
        "EveSOFDataHullDecalSetItem",
        "EveSOFDataHullBanner",
        "EveSOFDataHullBannerSet",
        "EveSOFDataHullBannerSetItem",
        "EveSOFDataHullBannerLight",
        "EveSOFDataHullChildSet",
        "EveSOFDataHullChildSetItem",
        "EveSOFDataHullHazeSet",
        "EveSOFDataHullHazeSetItem",
        "EveSOFDataHullLightSet",
        "EveSOFDataHullLightSetItem",
        "EveSOFDataHullPlaneSet",
        "EveSOFDataHullPlaneSetItem",
        "EveSOFDataHullSpotlightSet",
        "EveSOFDataHullSpotlightSetItem",
        "EveSOFDataHullSpriteSet",
        "EveSOFDataHullSpriteSetItem",
        "EveSOFDataHullSpriteLineSet",
        "EveSOFDataHullSpriteLineSetItem",
        "EveSOFDataHullSoundEmitter",
        "EveSOFDataInstancedMesh",
        "EveSOFDataTexture",
        "EveSOFDataParameter",
        "EveSOFDataTransform",
        "EveSOFDataVisibilityGroup",
        "EveSOFDataArea",
        "EveSOFDataAreaMaterial",
        "EveSOFDataFactionColorSet",
        "EveSOFDataFactionChild",
        "EveSOFDataFactionDecal",
        "EveSOFDataFactionPlaneSet",
        "EveSOFDataFactionSpotlightSet",
        "EveSOFDataFactionVisibilityGroupSet",
        "EveSOFDataLogo",
        "EveSOFDataLogoSet",
        "EveSOFDataGenericString",
        "EveSOFDataGenericDamage",
        "EveSOFDataGenericHullDamage",
        "EveSOFDataGenericShader",
        "EveSOFDataGenericDecalShader",
        "EveSOFDataGenericSwarm",
        "EveSOFDataGenericVariant",
        "EveSOFDataGenericHullCategory",
        "EveSOFDataRaceDamage",
        "EveSOFDataPatternLayer",
        "EveSOFDataPatternPerHull",
        "EveSOFDataPatternTransform",
        "EveSOFDNADescriptor",
        "EveSOFDataHullExtensionPlacement",
        "EveSOFDataHullExtensionPlacementGroup",
        "EveSOFDataDistributionDepletionCounter",
        "EveSOFDataPointLightAttachment",
        "EveSOFDataSpotLightAttachment",
        "EveSOFDataHullLightSetSpotLight",
        "EveSOFDataHullLightSetTexturedPointLight",
        "EveSOFDataDecalIndexBuffer",
        "EveSOFDataMultiHullDecalIndexBuffers",
    ):
        d(empty, {})
    return s


def read_black(raw: bytes, schemas: Optional[dict[str, dict[str, Callable]]] = None) -> Any:
    r = Reader(memoryview(raw), schemas=schemas or sof_schemas())
    r.expect_u32(FOURCC, "wrong FOURCC")
    r.expect_u32(1, "wrong version")
    strings_len = r.u32()
    sr = r.slice(strings_len)
    count = sr.u16()
    strings: list[str] = []
    for _ in range(count):
        strings.append(sr.cstring())
    if not sr.at_end():
        raise BlackError(f"strings leftover {sr.remaining()}")
    r.strings = strings
    comments_len = r.u32()
    cr = r.slice(comments_len)
    ccount = cr.u16()
    for _ in range(ccount):
        cr.cwstring()
    if not cr.at_end():
        raise BlackError(f"comments leftover {cr.remaining()}")
    return _object(r)


def extract_hull_boosters(sof_root: dict) -> dict[str, dict]:
    """Return sof_hull_name -> {items: [...], geometry: str, category: str}."""
    out: dict[str, dict] = {}
    hulls = sof_root.get("hull") or []
    if not isinstance(hulls, list):
        return out
    for h in hulls:
        if not isinstance(h, dict):
            continue
        name = str(h.get("name") or "").strip()
        if not name:
            continue
        booster = h.get("booster")
        items_out: list[dict] = []
        if isinstance(booster, dict):
            for it in booster.get("items") or []:
                if not isinstance(it, dict):
                    continue
                xf = it.get("transform")
                if not isinstance(xf, list) or len(xf) != 4:
                    continue
                items_out.append(
                    {
                        "has_trail": bool(it.get("hasTrail", True)),
                        "light_scale": float(it.get("lightScale") or 1.0),
                        "atlas_index0": int(it.get("atlasIndex0") or 0),
                        "atlas_index1": int(it.get("atlasIndex1") or 0),
                        "functionality": it.get("functionality") or [0, 0, 0, 0],
                        "transform": xf,
                    }
                )
        out[name] = {
            "sof_hull": name,
            "geometry": str(h.get("geometryResFilePath") or ""),
            "category": str(h.get("category") or ""),
            "bounding_sphere": h.get("boundingSphere"),
            "ellipsoid_center": h.get("shapeEllipsoidCenter"),
            "ellipsoid_radius": h.get("shapeEllipsoidRadius"),
            "items": items_out,
            "always_on": bool((booster or {}).get("alwaysOn")) if isinstance(booster, dict) else False,
            "has_trails": bool((booster or {}).get("hasTrails", True)) if isinstance(booster, dict) else True,
        }
    return out
