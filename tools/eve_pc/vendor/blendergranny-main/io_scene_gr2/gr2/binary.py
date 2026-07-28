"""Binary helpers."""

import struct


class BinaryReader:
    def __init__(self, data: bytes, *, byte_reversed: bool = False):
        self.data = data
        self.endian = ">" if byte_reversed else "<"

    def require(self, offset: int, size: int) -> None:
        if offset < 0 or offset + size > len(self.data):
            raise ValueError(f"read out of range at {offset:#x} size {size}")

    def u32(self, offset: int) -> int:
        self.require(offset, 4)
        return struct.unpack_from(self.endian + "I", self.data, offset)[0]

    def i32(self, offset: int) -> int:
        self.require(offset, 4)
        return struct.unpack_from(self.endian + "i", self.data, offset)[0]


def swap_u32(value: int) -> int:
    return int.from_bytes(value.to_bytes(4, "little"), "big")

