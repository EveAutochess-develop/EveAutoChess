"""Clean decompression facade."""

from __future__ import annotations

from io_scene_gr2.gr2.constants import (
    COMPRESSION_BITKNIT,
    COMPRESSION_BITKNIT2,
    COMPRESSION_NONE,
    COMPRESSION_OODLE0,
    COMPRESSION_OODLE1,
)
from io_scene_gr2.gr2.file import GR2Section


class DecompressionError(RuntimeError):
    pass


class DecompressionUnsupported(DecompressionError):
    pass


def decompress_section(section: GR2Section, compressed: bytes) -> bytes:
    if section.expanded_size == 0:
        return b""

    if section.compression == COMPRESSION_NONE:
        if len(compressed) < section.expanded_size:
            raise DecompressionError(
                f"section {section.index} short: {len(compressed)} < {section.expanded_size}"
            )
        return compressed[: section.expanded_size]

    if section.compression == COMPRESSION_OODLE0:
        from io_scene_gr2.gr2.decompress.oodle0 import decompress_oodle0

        return decompress_oodle0(section, compressed)

    if section.compression in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
        from io_scene_gr2.gr2.decompress.bitknit import decompress_bitknit

        return decompress_bitknit(section, compressed)

    if section.compression == COMPRESSION_OODLE1:
        from io_scene_gr2.gr2.decompress.oodle1 import decompress_oodle1

        return decompress_oodle1(section, compressed)

    raise DecompressionUnsupported(f"unknown compression id {section.compression}")
