"""GR2 file header and section table parsing."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .binary import BinaryReader, swap_u32
from .constants import (
    COMPRESSION_NAMES,
    EXTRA_TAG_COUNT,
    MAGIC_32BE,
    MAGIC_32LE,
    MAGIC_64BE,
    MAGIC_64LE,
    MAGIC_OLD,
    MAGIC_SIZE,
    SECTION_NAMES,
    SECTION_RECORD_SIZE,
)


@dataclass(frozen=True)
class GR2Section:
    index: int
    compression: int
    data_offset: int
    data_size: int
    expanded_size: int
    internal_alignment: int
    first_16bit: int
    first_8bit: int
    pointer_fixup_offset: int
    pointer_fixup_count: int
    mixed_marshalling_offset: int
    mixed_marshalling_count: int

    @property
    def compression_name(self) -> str:
        return COMPRESSION_NAMES.get(self.compression, f"unknown_{self.compression}")

    @property
    def semantic_name(self) -> str:
        return SECTION_NAMES.get(self.index, f"section_{self.index}")


@dataclass(frozen=True)
class GR2Header:
    version: int
    total_size: int
    crc: int
    section_array_offset: int
    section_count: int
    root_type: tuple[int, int]
    root_object: tuple[int, int]
    type_tag: int
    extra_tags: tuple[int, ...]
    string_db_crc: int
    reserved: tuple[int, ...]
    pointer_size: int
    byte_reversed: bool


@dataclass(frozen=True)
class GR2File:
    path: Path
    header: GR2Header
    sections: tuple[GR2Section, ...]
    data: bytes

    def section_bytes(self, section: GR2Section) -> bytes:
        start = section.data_offset
        end = start + section.data_size
        if start < 0 or end > len(self.data):
            raise ValueError(f"section {section.index} points outside file")
        return self.data[start:end]


def _magic_words(data: bytes, *, byte_reversed: bool) -> tuple[int, int, int, int]:
    reader = BinaryReader(data, byte_reversed=byte_reversed)
    return tuple(reader.u32(i * 4) for i in range(4))


def detect_gr2(data: bytes) -> tuple[bool, bool, int]:
    if len(data) < MAGIC_SIZE:
        return False, False, 0

    little = _magic_words(data, byte_reversed=False)
    if little in (MAGIC_OLD, MAGIC_32LE):
        return True, False, 32
    if little == MAGIC_64LE:
        return True, False, 64

    swapped = tuple(swap_u32(word) for word in little)
    if swapped in (MAGIC_OLD, MAGIC_32BE):
        return True, True, 32
    if swapped == MAGIC_64BE:
        return True, True, 64

    return False, False, 0


def read_gr2(path: str | Path) -> GR2File:
    file_path = Path(path)
    return read_gr2_bytes(file_path.read_bytes(), path=file_path)


def read_gr2_bytes(data: bytes, *, path: str | Path = "<memory>") -> GR2File:
    ok, byte_reversed, pointer_size = detect_gr2(data)
    if not ok:
        raise ValueError("not a Granny2 file")

    reader = BinaryReader(data, byte_reversed=byte_reversed)
    header_offset = MAGIC_SIZE
    version = reader.u32(header_offset)
    total_size = reader.u32(header_offset + 4)
    crc = reader.u32(header_offset + 8)
    section_array_offset = reader.u32(header_offset + 12)
    section_count = reader.u32(header_offset + 16)
    root_type = (reader.u32(header_offset + 20), reader.u32(header_offset + 24))
    root_object = (reader.u32(header_offset + 28), reader.u32(header_offset + 32))
    type_tag = reader.u32(header_offset + 36)
    extra_tags = tuple(reader.u32(header_offset + 40 + i * 4) for i in range(EXTRA_TAG_COUNT))

    string_db_crc = 0
    reserved: tuple[int, ...] = ()
    if version >= 7:
        string_db_crc = reader.u32(header_offset + 56)
        reserved = tuple(reader.u32(header_offset + 60 + i * 4) for i in range(3))

    sections = tuple(_read_sections(reader, section_array_offset, section_count))
    header = GR2Header(
        version=version,
        total_size=total_size,
        crc=crc,
        section_array_offset=section_array_offset,
        section_count=section_count,
        root_type=root_type,
        root_object=root_object,
        type_tag=type_tag,
        extra_tags=extra_tags,
        string_db_crc=string_db_crc,
        reserved=reserved,
        pointer_size=pointer_size,
        byte_reversed=byte_reversed,
    )
    return GR2File(Path(path), header, sections, data)


def _read_sections(reader: BinaryReader, section_array_offset: int, count: int) -> Iterable[GR2Section]:
    base = MAGIC_SIZE + section_array_offset
    for index in range(count):
        offset = base + index * SECTION_RECORD_SIZE
        yield GR2Section(
            index=index,
            compression=reader.u32(offset),
            data_offset=reader.u32(offset + 4),
            data_size=reader.u32(offset + 8),
            expanded_size=reader.u32(offset + 12),
            internal_alignment=reader.u32(offset + 16),
            first_16bit=reader.u32(offset + 20),
            first_8bit=reader.u32(offset + 24),
            pointer_fixup_offset=reader.u32(offset + 28),
            pointer_fixup_count=reader.u32(offset + 32),
            mixed_marshalling_offset=reader.u32(offset + 36),
            mixed_marshalling_count=reader.u32(offset + 40),
        )
