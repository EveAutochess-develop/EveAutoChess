"""Private local decompression backend for research checks.

This module loads a local `.so` from outside this repository when explicitly
requested by tools. It is not part of the clean Blender addon release path.
"""

from __future__ import annotations

import ctypes
import os
from pathlib import Path

from io_scene_gr2.gr2.constants import COMPRESSION_OODLE0, COMPRESSION_OODLE1
from io_scene_gr2.gr2.decompress.base import (
    DecompressionError,
    DecompressionUnsupported,
    decompress_section,
)
from io_scene_gr2.gr2.file import GR2File, GR2Section


DEFAULT_RESEARCH_LIB = Path(
    os.environ.get(
        "GR2_RESEARCH_LIB",
        "__missing_gr2_research_lib__",
    )
)


class ResearchNativeBackend:
    def __init__(
        self,
        path: str | Path = DEFAULT_RESEARCH_LIB,
        *,
        allow_oodle0: bool | None = None,
    ):
        self.path = Path(path)
        self.allow_oodle0 = (
            bool(os.environ.get("GR2_RESEARCH_ALLOW_OODLE0"))
            if allow_oodle0 is None
            else allow_oodle0
        )
        self.lib = ctypes.CDLL(str(self.path))
        self._setup()

    def _setup(self) -> None:
        args = [
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
        ]
        self.lib.gr2_oodle0_decompress.argtypes = args
        self.lib.gr2_oodle0_decompress.restype = ctypes.c_int
        self.lib.gr2_oodle1_decompress.argtypes = args
        self.lib.gr2_oodle1_decompress.restype = ctypes.c_int

    def validate_file(self, gr2: GR2File) -> None:
        if gr2.header.byte_reversed:
            raise DecompressionUnsupported(
                "research backend disabled for byte-reversed GR2 files"
            )

    def decompress(self, section: GR2Section, compressed: bytes) -> bytes:
        if section.expanded_size == 0:
            return b""

        if section.compression not in (COMPRESSION_OODLE0, COMPRESSION_OODLE1):
            return decompress_section(section, compressed)
        if section.compression == COMPRESSION_OODLE0 and not self.allow_oodle0:
            raise DecompressionUnsupported(
                "oodle0 research backend disabled because current local native path can segfault"
            )

        in_buf = (ctypes.c_uint8 * len(compressed)).from_buffer_copy(compressed)
        out_buf = (ctypes.c_uint8 * section.expanded_size)()
        fn = (
            self.lib.gr2_oodle0_decompress
            if section.compression == COMPRESSION_OODLE0
            else self.lib.gr2_oodle1_decompress
        )
        ret = fn(
            in_buf,
            len(compressed),
            out_buf,
            section.first_16bit,
            section.first_8bit,
            section.expanded_size,
        )
        if ret < 0:
            raise DecompressionError(
                f"{section.compression_name} research backend failed with code {ret}"
            )
        if ret != section.expanded_size:
            raise DecompressionError(
                f"{section.compression_name} research backend returned {ret}, "
                f"expected {section.expanded_size}"
            )
        return bytes(out_buf)
