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


def _legacy_uncompressed(data: bytes, w: int, h: int) -> Image.Image | None:
    """Decode non-DX10 uncompressed DDS (RGB/RGBA/L8)."""
    if len(data) < 128:
        return None
    flags, fourcc, bitcount = struct.unpack_from("<I4sI", data, 80)
    # DDPF_FOURCC = 0x4 — leave to other paths / PIL
    if flags & 0x4 and fourcc not in (b"\x00\x00\x00\x00", b""):
        return None
    payload = data[128:]
    pixels = w * h
    if bitcount == 32 and len(payload) >= pixels * 4:
        # EVE traffic sprites: typically BGRA masks
        return Image.frombytes("RGBA", (w, h), payload[: pixels * 4], "raw", "BGRA")
    if bitcount == 24 and len(payload) >= pixels * 3:
        return Image.frombytes("RGB", (w, h), payload[: pixels * 3], "raw", "BGR").convert("RGBA")
    if bitcount == 8 and len(payload) >= pixels:
        return Image.frombytes("L", (w, h), payload[:pixels]).convert("RGBA")
    if bitcount == 16 and len(payload) >= pixels * 2:
        # R16_UNORM-like: take high byte as luminance
        raw = payload[: pixels * 2]
        lum = bytes(raw[i + 1] for i in range(0, len(raw), 2))
        return Image.frombytes("L", (w, h), lum).convert("RGBA")
    return None


def _float_to_u8(vals: list[float]) -> bytes:
    """Map float channel(s) into 0..255 with a simple abs-clip (review mirror)."""
    out = bytearray(len(vals))
    for i, v in enumerate(vals):
        if v != v:  # NaN
            out[i] = 0
            continue
        out[i] = max(0, min(255, int(abs(v) * 255.0 + 0.5))) if abs(v) <= 1.0 else max(
            0, min(255, int(abs(v) + 0.5))
        )
    return bytes(out)


def _legacy_float_fourcc(data: bytes, w: int, h: int) -> Image.Image | None:
    """D3DFMT numeric FourCC: R16F=111, R32F=114, A32B32G32R32F=116."""
    if len(data) < 128:
        return None
    flags, fourcc_i = struct.unpack_from("<II", data, 80)
    if not (flags & 0x4):
        return None
    payload = data[128:]
    pixels = w * h
    if fourcc_i == 114:  # D3DFMT_R32F
        need = pixels * 4
        if len(payload) < need:
            return None
        floats = list(struct.unpack_from(f"<{pixels}f", payload, 0))
        return Image.frombytes("L", (w, h), _float_to_u8(floats)).convert("RGBA")
    if fourcc_i == 111:  # D3DFMT_R16F
        need = pixels * 2
        if len(payload) < need:
            return None
        import numpy as np

        f16 = np.frombuffer(payload[:need], dtype=np.float16).astype(np.float32)
        return Image.frombytes("L", (w, h), _float_to_u8(f16.tolist())).convert("RGBA")
    if fourcc_i == 116:  # D3DFMT_A32B32G32R32F
        need = pixels * 16
        if len(payload) < need:
            return None
        floats = struct.unpack_from(f"<{pixels * 4}f", payload, 0)
        # D3D stores as ARGB float; map to RGBA u8
        rgba = bytearray(pixels * 4)
        for i in range(pixels):
            a, r, g, b = floats[i * 4 : i * 4 + 4]
            rgba[i * 4] = _float_to_u8([r])[0]
            rgba[i * 4 + 1] = _float_to_u8([g])[0]
            rgba[i * 4 + 2] = _float_to_u8([b])[0]
            rgba[i * 4 + 3] = _float_to_u8([a])[0]
        return Image.frombytes("RGBA", (w, h), bytes(rgba))
    return None


def decode_dds(path: Path) -> Image.Image | None:
    data = path.read_bytes()
    if data[:4] != b"DDS ":
        return None
    w, h = _size(data)
    if w <= 0 or h <= 0:
        return None
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
        if dxgi in (71, 72):  # BC1 / BC1_SRGB
            need = w * h // 2
            dec = texture2ddecoder.decode_bc1(payload[:need], w, h)
            return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
        if dxgi in (77, 78):  # BC3 / BC3_SRGB
            need = w * h
            dec = texture2ddecoder.decode_bc3(payload[:need], w, h)
            return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
        if dxgi == 56:  # R16_UNORM
            need = w * h * 2
            raw = payload[:need]
            if len(raw) >= need:
                lum = bytes(raw[i + 1] for i in range(0, need, 2))
                return Image.frombytes("L", (w, h), lum).convert("RGBA")
        if dxgi == 61:  # R8G8_UNORM
            need = w * h * 2
            raw = payload[:need]
            if len(raw) >= need:
                rgba = bytearray(w * h * 4)
                for i in range(w * h):
                    rgba[i * 4] = raw[i * 2]
                    rgba[i * 4 + 1] = raw[i * 2 + 1]
                    rgba[i * 4 + 2] = 0
                    rgba[i * 4 + 3] = 255
                return Image.frombytes("RGBA", (w, h), bytes(rgba))
        if dxgi is None:
            im = _legacy_float_fourcc(data, w, h)
            if im is not None:
                return im
            im = _legacy_uncompressed(data, w, h)
            if im is not None:
                return im
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
