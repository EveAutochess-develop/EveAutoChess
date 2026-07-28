"""Decompressed section bundle and pointer fixup handling."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Protocol

from .binary import BinaryReader
from .constants import COMPRESSION_BITKNIT2
from .decompress import decompress_section
from .file import GR2File, GR2Section

FAKE_POINTER_BASE = 0x10000000
FAKE_SECTION_STRIDE = 0x100000


class SectionBackend(Protocol):
    def decompress(self, section, compressed: bytes) -> bytes:
        ...


@dataclass(frozen=True)
class PointerRef:
    section: int
    offset: int


@dataclass(frozen=True)
class PointerFixup:
    source_section: int
    source_offset: int
    target: PointerRef


@dataclass(frozen=True)
class MixedMarshallingFixup:
    source_section: int
    count: int
    offset: int
    type_ref: PointerRef | None


@dataclass(frozen=True)
class LoadedGR2:
    gr2: GR2File
    sections_original: tuple[bytes, ...]
    sections_fixed: tuple[bytes, ...]
    pointer_fixups: tuple[PointerFixup, ...]
    mixed_marshalling_fixups: tuple[MixedMarshallingFixup, ...]

    def resolve_fake_pointer(self, pointer: int) -> PointerRef | None:
        return decode_fake_pointer(pointer, len(self.sections_fixed))

    def read_ref(self, ref: PointerRef, size: int | None = None, *, fixed: bool = True) -> bytes:
        sections = self.sections_fixed if fixed else self.sections_original
        if ref.section < 0 or ref.section >= len(sections):
            raise ValueError(f"section {ref.section} out of range")
        data = sections[ref.section]
        end = len(data) if size is None else ref.offset + size
        if ref.offset < 0 or end > len(data):
            raise ValueError(f"reference {ref.section}:{ref.offset:#x} out of range")
        return data[ref.offset:end]


def make_fake_pointer(ref: PointerRef) -> int:
    return FAKE_POINTER_BASE + ref.section * FAKE_SECTION_STRIDE + ref.offset


def decode_fake_pointer(pointer: int, section_count: int) -> PointerRef | None:
    if pointer < FAKE_POINTER_BASE:
        return None
    value = pointer - FAKE_POINTER_BASE
    section = value // FAKE_SECTION_STRIDE
    offset = value - section * FAKE_SECTION_STRIDE
    if section < 0 or section >= section_count:
        return None
    return PointerRef(section, offset)


def load_sections(gr2: GR2File, backend: SectionBackend | None = None) -> LoadedGR2:
    validate_file = getattr(backend, "validate_file", None)
    if validate_file is not None:
        validate_file(gr2)

    original = tuple(
        backend.decompress(section, gr2.section_bytes(section))
        if backend
        else decompress_section(section, gr2.section_bytes(section))
        for section in gr2.sections
    )
    fixed = [bytearray(section) for section in original]
    pointer_fixups = tuple(_read_pointer_fixups(gr2))
    mixed_fixups = tuple(_read_mixed_marshalling_fixups(gr2))

    pointer_size = gr2.header.pointer_size // 8
    if pointer_size not in (4, 8):
        raise ValueError(f"unsupported pointer size {gr2.header.pointer_size}")

    for fixup in pointer_fixups:
        if fixup.source_section >= len(fixed):
            continue
        data = fixed[fixup.source_section]
        if fixup.source_offset + pointer_size > len(data):
            continue
        fake = make_fake_pointer(fixup.target)
        if pointer_size == 4:
            struct.pack_into("<I", data, fixup.source_offset, fake)
        else:
            struct.pack_into("<Q", data, fixup.source_offset, fake)

    return LoadedGR2(
        gr2=gr2,
        sections_original=original,
        sections_fixed=tuple(bytes(section) for section in fixed),
        pointer_fixups=pointer_fixups,
        mixed_marshalling_fixups=mixed_fixups,
    )


def _read_pointer_fixups(gr2: GR2File):
    for section in gr2.sections:
        if section.pointer_fixup_count == 0 or section.pointer_fixup_offset == 0:
            continue
        entry_size = _pointer_fixup_entry_size(gr2, section.index)
        data = _read_fixup_blob(
            gr2,
            section.index,
            section.pointer_fixup_offset,
            section.pointer_fixup_count,
            entry_size,
        )
        reader = BinaryReader(data, byte_reversed=gr2.header.byte_reversed)
        for index in range(section.pointer_fixup_count):
            offset = index * entry_size
            if offset + entry_size > len(data):
                break
            source_offset = reader.u32(offset)
            if entry_size == 12:
                target = PointerRef(reader.u32(offset + 4), reader.u32(offset + 8))
            else:
                target = _decode_legacy_fake_pointer(reader.u32(offset + 4), len(gr2.sections))
            yield PointerFixup(section.index, source_offset, target)


def _read_mixed_marshalling_fixups(gr2: GR2File):
    for section in gr2.sections:
        if section.mixed_marshalling_count == 0 or section.mixed_marshalling_offset == 0:
            continue
        entry_size = 16 if gr2.header.version >= 7 else 8
        data = _read_fixup_blob(
            gr2,
            section.index,
            section.mixed_marshalling_offset,
            section.mixed_marshalling_count,
            entry_size,
        )
        reader = BinaryReader(data, byte_reversed=gr2.header.byte_reversed)
        for index in range(section.mixed_marshalling_count):
            offset = index * entry_size
            if offset + entry_size > len(data):
                break
            type_ref = None
            if entry_size == 16:
                type_ref = PointerRef(reader.u32(offset + 8), reader.u32(offset + 12))
            yield MixedMarshallingFixup(
                source_section=section.index,
                count=reader.u32(offset),
                offset=reader.u32(offset + 4),
                type_ref=type_ref,
            )


def _pointer_fixup_entry_size(gr2: GR2File, section_index: int) -> int:
    section = gr2.sections[section_index]
    span = _metadata_span_after(gr2, section.pointer_fixup_offset)
    if span is not None:
        if span >= section.pointer_fixup_count * 12:
            return 12
        if span >= section.pointer_fixup_count * 8:
            return 8
    if gr2.header.version >= 7:
        return 12
    if section.pointer_fixup_offset + section.pointer_fixup_count * 12 <= len(gr2.data):
        return 12
    return 8


def _read_fixup_blob(
    gr2: GR2File,
    section_index: int,
    offset: int,
    count: int,
    entry_size: int,
) -> bytes:
    expected_size = count * entry_size
    span = _metadata_span_after(gr2, offset)
    raw = gr2.data[offset : offset + span] if span is not None else gr2.data[offset:]
    if len(raw) >= 4:
        payload_size = struct.unpack_from("<I", raw, 0)[0]
        payload = raw[4 : 4 + min(payload_size, max(0, len(raw) - 4))]
        if payload[:2] == b"\xb1\x75":
            if len(payload) >= 48:
                return _decompress_bitknit2_fixup_blob(
                    section_index,
                    payload,
                    expected_size,
                )
            if len(payload) >= 4 + expected_size:
                return payload[4 : 4 + expected_size]
        if len(payload) == expected_size:
            return payload
    if len(raw) >= expected_size:
        return raw[:expected_size]
    return raw


def _decompress_bitknit2_fixup_blob(section_index: int, compressed: bytes, expanded_size: int) -> bytes:
    from .decompress.bitknit import decompress_bitknit

    section = GR2Section(
        index=section_index,
        compression=COMPRESSION_BITKNIT2,
        data_offset=0,
        data_size=len(compressed),
        expanded_size=expanded_size,
        internal_alignment=4,
        first_16bit=expanded_size,
        first_8bit=expanded_size,
        pointer_fixup_offset=0,
        pointer_fixup_count=0,
        mixed_marshalling_offset=0,
        mixed_marshalling_count=0,
    )
    return decompress_bitknit(section, compressed)


def _metadata_span_after(gr2: GR2File, offset: int) -> int | None:
    candidates: list[int] = []
    for section in gr2.sections:
        for value in (
            section.pointer_fixup_offset,
            section.mixed_marshalling_offset,
            section.data_offset,
        ):
            if value > offset:
                candidates.append(value)
    if not candidates:
        return None
    return min(candidates) - offset


def _decode_legacy_fake_pointer(pointer: int, section_count: int) -> PointerRef:
    ref = decode_fake_pointer(pointer, section_count)
    if ref is not None:
        return ref
    section = pointer // FAKE_SECTION_STRIDE
    offset = pointer - section * FAKE_SECTION_STRIDE
    return PointerRef(section, offset)
