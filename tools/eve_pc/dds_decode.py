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


def _reconstruct_normal_z(im: Image.Image) -> Image.Image:
    """Fill B from XY when BC5 left Z empty (B≈0)."""
    rgba = im.convert("RGBA")
    px = rgba.load()
    w, h = rgba.size
    # Fast path: if mean B already mid-gray, leave alone.
    sample = [px[x, y][2] for y in range(0, h, max(1, h // 32)) for x in range(0, w, max(1, w // 32))]
    if sample and (sum(sample) / len(sample)) > 8:
        return rgba
    for y in range(h):
        for x in range(w):
            r, g, _b, a = px[x, y]
            nx = r / 127.5 - 1.0
            ny = g / 127.5 - 1.0
            nz = max(0.0, 1.0 - nx * nx - ny * ny) ** 0.5
            px[x, y] = (r, g, int(nz * 127.5 + 128.0), a)
    return rgba


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
            # texture2ddecoder returns RGBA (4 Bpp); luminance is in channel 2 (B).
            # Interpreting as mode "L" used every 4th byte (often A=255) → vertical stripes / moiré.
            if len(dec) >= w * h * 4:
                rgba = Image.frombytes("RGBA", (w, h), dec)
                return rgba.getchannel("B").convert("RGBA")
            return Image.frombytes("L", (w, h), dec[: w * h]).convert("RGBA")
        if dxgi == 83:  # BC5_UNORM — XY only; reconstruct Z for Godot NORMAL_MAP
            need = w * h
            dec = texture2ddecoder.decode_bc5(payload[:need], w, h)
            im = Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
            return _reconstruct_normal_z(im)
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
