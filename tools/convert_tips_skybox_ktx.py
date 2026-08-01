#!/usr/bin/env python3
"""Decode Echoes tips_skybox KTX1 ASTC4x4 → PNG for assets/ui/tips_skybox/."""
from __future__ import annotations

import struct
from pathlib import Path

import texture2ddecoder
from PIL import Image

SRC = Path(r"H:\eve手游\history\1.9.62_unpacked\asset_library\equipment_textures")
DST = Path(r"H:\game_dev\eveautochess-dev\godot_project\assets\ui\tips_skybox")

MAP = {
    "tips_skybox__tips_a01_pic.ktx": "tips_a01_pic.png",
    "tips_skybox__tips_c01_pic.ktx": "tips_c01_pic.png",
    "tips_skybox__tips_g01_pic.ktx": "tips_g01_pic.png",
    "tips_skybox__tips_m01_pic.ktx": "tips_m01_pic.png",
    "tips_skybox__tips_ore_a01_pic.ktx": "tips_ore_a01_pic.png",
    "tips_skybox__tips_ore_c01_pic.ktx": "tips_ore_c01_pic.png",
    "tips_skybox__tips_ore_g01_pic.ktx": "tips_ore_g01_pic.png",
    "tips_skybox__tips_ore_m01.ktx": "tips_ore_m01.png",
}

KTX_ID = b"\xabKTX 11\xbb\r\n\x1a\n"
# GL_COMPRESSED_RGBA_ASTC_*_KHR → (block_w, block_h). Echoes tips ship as 6x6 (0x93B4).
ASTC_BLOCKS = {
    0x93B0: (4, 4),
    0x93B1: (5, 4),
    0x93B2: (5, 5),
    0x93B3: (6, 5),
    0x93B4: (6, 6),
    0x93B5: (8, 5),
    0x93B6: (8, 6),
    0x93B7: (8, 8),
    0x93D0: (4, 4),
    0x93D4: (6, 6),
}


def decode_ktx_astc(path: Path) -> Image.Image:
    data = path.read_bytes()
    if data[:12] != KTX_ID:
        raise ValueError(f"not KTX1: {path.name}")
    # After identifier: endian(4) glType glTypeSize glFormat glInternalFormat
    # glBaseInternalFormat pixelWidth pixelHeight pixelDepth numberOfArrayElements
    # numberOfFaces numberOfMipmapLevels bytesOfKeyValueData
    (
        endian,
        gl_type,
        gl_type_size,
        gl_format,
        gl_internal,
        gl_base,
        width,
        height,
        depth,
        arrays,
        faces,
        mips,
        kv_bytes,
    ) = struct.unpack_from("<13I", data, 12)
    if endian != 0x04030201:
        raise ValueError(f"unexpected endian {endian:#x}")
    if gl_internal not in ASTC_BLOCKS:
        raise ValueError(f"unsupported internalFormat {gl_internal:#x}")
    block_w, block_h = ASTC_BLOCKS[gl_internal]
    offset = 12 + 13 * 4 + kv_bytes
    (image_size,) = struct.unpack_from("<I", data, offset)
    offset += 4
    blocks_x = (width + block_w - 1) // block_w
    blocks_y = (height + block_h - 1) // block_h
    expected = blocks_x * blocks_y * 16
    if image_size != expected:
        raise ValueError(
            f"{path.name}: imageSize {image_size} != {expected} for ASTC {block_w}x{block_h}"
        )
    payload = data[offset : offset + image_size]
    raw = texture2ddecoder.decode_astc(payload, width, height, block_w, block_h)
    # BGRA → RGBA
    img = Image.frombytes("RGBA", (width, height), raw, "raw", "BGRA")
    return img


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    ok = fail = 0
    for src_name, dst_name in MAP.items():
        src = SRC / src_name
        dst = DST / dst_name
        try:
            img = decode_ktx_astc(src)
            img.save(dst, "PNG")
            print(f"OK {src_name} → {dst_name} {img.size}")
            ok += 1
        except Exception as e:
            print(f"FAIL {src_name}: {e}")
            fail += 1
    print(f"done ok={ok} fail={fail}")


if __name__ == "__main__":
    main()
