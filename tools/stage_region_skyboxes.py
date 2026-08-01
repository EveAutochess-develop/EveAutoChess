# -*- coding: utf-8 -*-
"""Nullsec region skyboxes: TQ cube -> equirect JPEG + data/regions tables.

Only one sky is on screen at a time and the camera looks down at the board, so
the 25 MB sharp cubes stay out of the build: each region's cube is unwrapped
into one panorama that Godot hands straight to PanoramaSkyMaterial, keeping the
region <-> sky pairing 1:1 (NEW_EDEN_REGIONS 2 天空盒).

Source is `_cube_refl` (128 per face, DXT3), not the sharper BC6H
`_cube_lowdetail`: the HDR cube stores nebulae far down in the linear range, so
Pillow's clamp leaves ~9 usable levels and any gamma lift posterizes into
blotches. The refl cube is the already-tonemapped LDR copy of the same sky.
"""
from __future__ import annotations

import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

DESIGN = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\skyboxes_tq"
)
UNIVERSE = DESIGN / "universe"
MAP_JSON = DESIGN / "region_skybox_map.json"

ROOT = Path(__file__).resolve().parent.parent / "godot_project"
SKY_OUT = ROOT / "assets" / "skyboxes" / "regions"
DATA_OUT = ROOT / "data" / "regions"

PANO_W = 1024
PANO_H = 512
JPEG_QUALITY = 88
MUST_INCLUDE = ["period_basis"]


def cube_faces(dds: Path) -> list[np.ndarray]:
    """Six RGB faces in DDS order (+X -X +Y -Y +Z -Z), rebuilt one DDS at a time."""
    data = bytearray(dds.read_bytes())
    w = struct.unpack_from("<I", data, 16)[0]
    mips = max(1, struct.unpack_from("<I", data, 28)[0])
    struct.pack_into("<I", data, 112, 0)  # dwCaps2: drop the cubemap flags
    struct.pack_into("<I", data, 28, 1)  # one mip per rebuilt face
    head = bytes(data[:128])
    payload = bytes(data[128:])
    ## DXT3: 16 bytes per 4x4 block = 1 byte per pixel, mips included in the stride.
    stride = sum(max(4, w >> i) * max(4, w >> i) for i in range(mips))
    faces = []
    for i in range(6):
        blob = head + payload[i * stride : i * stride + w * w]
        im = Image.open(io.BytesIO(blob))
        im.load()
        faces.append(np.asarray(im.convert("RGB"), dtype=np.float32))
    return faces


def _sample(face: np.ndarray, s: np.ndarray, t: np.ndarray) -> np.ndarray:
    n = face.shape[0]
    x = np.clip(s * n - 0.5, 0.0, n - 1.0)
    y = np.clip(t * n - 0.5, 0.0, n - 1.0)
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    x1 = np.minimum(x0 + 1, n - 1)
    y1 = np.minimum(y0 + 1, n - 1)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    top = face[y0, x0] * (1.0 - fx) + face[y0, x1] * fx
    bot = face[y1, x0] * (1.0 - fx) + face[y1, x1] * fx
    return top * (1.0 - fy) + bot * fy


def equirect(faces: list[np.ndarray], w: int = PANO_W, h: int = PANO_H) -> Image.Image:
    yy, xx = np.mgrid[0:h, 0:w]
    phi = (xx + 0.5) / w * 2.0 * np.pi - np.pi
    theta = (yy + 0.5) / h * np.pi
    dx = (np.sin(theta) * np.sin(phi)).ravel()
    dy = np.cos(theta).ravel()
    dz = (-np.sin(theta) * np.cos(phi)).ravel()
    ax, ay, az = np.abs(dx), np.abs(dy), np.abs(dz)
    out = np.zeros((h * w, 3), dtype=np.float32)
    # D3D cubemap convention: uc/vc per major axis, then to [0,1].
    picks = [
        (0, (ax >= ay) & (ax >= az) & (dx > 0), lambda: (-dz, -dy, ax)),
        (1, (ax >= ay) & (ax >= az) & (dx <= 0), lambda: (dz, -dy, ax)),
        (2, (ay > ax) & (ay >= az) & (dy > 0), lambda: (dx, dz, ay)),
        (3, (ay > ax) & (ay >= az) & (dy <= 0), lambda: (dx, -dz, ay)),
        (4, (az > ax) & (az > ay) & (dz > 0), lambda: (dx, -dy, az)),
        (5, (az > ax) & (az > ay) & (dz <= 0), lambda: (-dx, -dy, az)),
    ]
    for idx, mask, fn in picks:
        if not mask.any():
            continue
        uc, vc, ma = fn()
        m = np.maximum(ma[mask], 1e-9)
        s = (uc[mask] / m + 1.0) * 0.5
        t = (vc[mask] / m + 1.0) * 0.5
        out[mask] = _sample(faces[idx], s, t)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8).reshape(h, w, 3))


def main() -> None:
    rows = json.loads(MAP_JSON.read_text(encoding="utf-8"))
    pool = [r for r in rows if r.get("in_nullsec_pool") and r.get("region_id")]
    SKY_OUT.mkdir(parents=True, exist_ok=True)
    DATA_OUT.mkdir(parents=True, exist_ok=True)

    entries: list[dict] = []
    smap: dict[str, str] = {}
    total = 0
    for i, r in enumerate(sorted(pool, key=lambda x: x["region_id"]), 1):
        rid = str(r["region_id"])
        stem = str(r["skybox_stem"])
        src = UNIVERSE / stem / f"{stem}_cube_refl.dds"
        if not src.is_file():
            print(f"[{i:2}/{len(pool)}] {rid}: MISSING {src.name} -> out of pool")
            continue
        dst = SKY_OUT / f"{rid}.jpg"
        if not dst.is_file():
            equirect(cube_faces(src)).save(dst, quality=JPEG_QUALITY, optimize=True)
        kb = dst.stat().st_size / 1024
        total += dst.stat().st_size
        print(f"[{i:2}/{len(pool)}] {rid} <- {stem} ({kb:.0f} KB)")
        smap[rid] = stem
        entries.append(
            {
                "region_id": rid,
                "name_en": r.get("name_en", ""),
                "name_zh": r.get("name_zh", ""),
                "skybox_stem": stem,
                "skybox_key": r.get("skybox_key", ""),
                "eve_region_id": r.get("eve_region_id", 0),
            }
        )

    (DATA_OUT / "skybox_map.json").write_text(
        json.dumps(smap, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (DATA_OUT / "nullsec_pool.json").write_text(
        json.dumps(
            {"must_include": MUST_INCLUDE, "regions": entries},
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"staged {len(entries)} regions, {total / 1024 / 1024:.1f} MB -> {SKY_OUT}")


if __name__ == "__main__":
    main()
