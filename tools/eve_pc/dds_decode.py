# -*- coding: utf-8 -*-
"""Decode EVE Tranquility DX10 DDS (BC7/BC5/BC4) to PIL images."""
from __future__ import annotations

import struct
from pathlib import Path

import texture2ddecoder
from PIL import Image


def _dxgi(data: bytes) -> int | None:
    if data[84:88] != b"DX10" or len(data) < 148:
        return None
    return struct.unpack_from("<I", data, 128)[0]


def _size(data: bytes) -> tuple[int, int]:
    h = struct.unpack_from("<I", data, 12)[0]
    w = struct.unpack_from("<I", data, 16)[0]
    return w, h


def decode_dds(path: Path) -> Image.Image | None:
    data = path.read_bytes()
    if data[:4] != b"DDS ":
        return None
    w, h = _size(data)
    dxgi = _dxgi(data)
    payload = data[148:] if dxgi is not None else data[128:]
    try:
        if dxgi == 98:  # BC7_UNORM
            need = w * h
            dec = texture2ddecoder.decode_bc7(payload[:need], w, h)
            return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
        if dxgi == 80:  # BC4_UNORM
            need = w * h // 2
            dec = texture2ddecoder.decode_bc4(payload[:need], w, h)
            return Image.frombytes("L", (w, h), dec).convert("RGBA")
        if dxgi == 83:  # BC5_UNORM
            need = w * h
            dec = texture2ddecoder.decode_bc5(payload[:need], w, h)
            return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
        if dxgi == 71:  # BC1
            need = w * h // 2
            dec = texture2ddecoder.decode_bc1(payload[:need], w, h)
            return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
        if dxgi == 77:  # BC3
            need = w * h
            dec = texture2ddecoder.decode_bc3(payload[:need], w, h)
            return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
    except Exception:
        return None
    try:
        return Image.open(path).convert("RGBA")
    except Exception:
        return None


def save_png(src: Path, dst: Path, *, max_dim: int = 1024) -> bool:
    im = decode_dds(src)
    if im is None:
        return False
    if max(im.size) > max_dim:
        im.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.convert("RGBA").save(dst, "PNG")
    return True
