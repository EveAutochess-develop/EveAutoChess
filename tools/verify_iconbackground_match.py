# -*- coding: utf-8 -*-
"""Verify that the name-matched TQ iconbackground asset really is each 512
portrait's background.

Method (per user): take the four corner TRIANGLES of the 512 portrait as
background-only seeds, then search every racial iconbackground cubemap for a
face/orientation/crop whose pixels explain those seeds. If the name-based
mapping is right, the diagonal of the cross-match matrix must win.

res:/dx9/scene/iconbackground/<race>.black binds the icon scene to
background.fx + ship_<race>_cube{,_blur,_refl}.dds, so the visible backdrop is
the *_blur cube sampled by view direction.

Caveat: the cubes are BC6H_SF16 (HDR) and Pillow clamps them to 0-255, so
burnt highlights are excluded from scoring; only unclipped pixels are compared,
with a single scalar exposure gain fitted per candidate.
"""
from __future__ import annotations

import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools" / "eve_pc")]
from eve_pc.resfile_index import resolve_resfile  # noqa: E402

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\titan_assets_confirm\iconbackground_for_cutout"
)

FACES = ["pX", "mX", "pY", "mY", "pZ", "mZ"]

PORTRAITS = {
    "amarr": "res:/dx9/model/ship/amarr/titan/at1/icons/2910_512.jpg",
    "caldari": "res:/dx9/model/ship/caldari/titan/ct1/icons/2930_512.jpg",
    "gallente": "res:/dx9/model/ship/gallente/titan/gt1/icons/2942_512.jpg",
    "minmatar": "res:/dx9/model/ship/minmatar/titan/mt1/icons/2906_512.jpg",
}

# The *_blur cube is only 32x32 (ambient probe) and *_refl 128x128; the sharp
# 512x512 cube is the one matching icon resolution, i.e. the visible backdrop.
CUBE_RACES = ["amarr", "caldari", "gallente", "minmatar", "other"]
CUBE_KIND = sys.argv[1] if len(sys.argv) > 1 else "_blur"
if CUBE_KIND == "sharp":
    CUBE_KIND = ""
CUBES = {r: f"res:/dx9/scene/iconbackground/ship_{r}_cube{CUBE_KIND}.dds" for r in CUBE_RACES}

# The titan sits on the image diagonal, so its bow/stern poke into the TR/BL
# corners; keep the triangles small and trim outliers when fitting.
CORNER_FRAC = 0.14
CLIP_HI = 248.0     # ignore pixels Pillow burnt out when clamping HDR
CROPS = [1.0, 0.8, 0.6, 0.45, 0.32]
GAMMAS = [1.0, 1.6, 2.2]  # icon render tonemap vs stored texture encoding
TRIM = 0.25               # fraction of worst-residual pixels dropped (ship leakage)
SIZE = 512


def cube_faces(res: str) -> list[np.ndarray]:
    """Decode a cubemap face-by-face by rebuilding a single-face DDS per face.

    Handles both the sharp DX10/BC6H_SF16 cubes and the legacy DXT1 *_blur /
    *_refl cubes (which carry mip chains, so face stride must include them).
    """
    data = bytearray(Path(resolve_resfile(res)).read_bytes())
    h = struct.unpack_from("<I", data, 12)[0]
    w = struct.unpack_from("<I", data, 16)[0]
    mips = max(1, struct.unpack_from("<I", data, 28)[0])
    fourcc = bytes(data[84:88])
    dx10 = fourcc == b"DX10"
    struct.pack_into("<I", data, 112, 0)  # caps2: drop cubemap bits
    struct.pack_into("<I", data, 28, 1)   # single mip per rebuilt face
    if dx10:
        struct.pack_into("<I", data, 136, 0)  # misc: drop TEXTURECUBE
        struct.pack_into("<I", data, 140, 1)  # arraysize
    hdr_len = 148 if dx10 else 128
    head = bytes(data[:hdr_len])
    payload = bytes(data[hdr_len:])

    if dx10:
        bpp_num, bpp_den = 1, 1          # BC6H: 16 bytes / 4x4 block
    elif fourcc == b"DXT1":
        bpp_num, bpp_den = 1, 2          # BC1: 8 bytes / 4x4 block
    else:
        raise RuntimeError(f"unsupported cube format {fourcc!r}")

    def mip_bytes(level: int) -> int:
        mw, mh = max(4, w >> level), max(4, h >> level)
        return mw * mh * bpp_num // bpp_den

    face_stride = sum(mip_bytes(i) for i in range(mips))
    faces = []
    for i in range(6):
        blob = head + payload[i * face_stride : i * face_stride + mip_bytes(0)]
        im = Image.open(io.BytesIO(blob))
        faces.append(np.asarray(im.convert("RGB"), dtype=np.float32))
    return faces


def corner_triangles(size: int, frac: float = CORNER_FRAC) -> np.ndarray:
    """Boolean mask: four right triangles hugging the image corners."""
    n = int(size * frac)
    yy, xx = np.mgrid[0:size, 0:size]
    return (
        ((xx + yy) < n)
        | (((size - 1 - xx) + yy) < n)
        | ((xx + (size - 1 - yy)) < n)
        | (((size - 1 - xx) + (size - 1 - yy)) < n)
    )


def orientations(a: np.ndarray):
    for k in range(4):
        r = np.rot90(a, k)
        yield f"rot{k * 90}", r
        yield f"rot{k * 90}+flip", r[:, ::-1]


def center_crop_resize(a: np.ndarray, frac: float, size: int) -> np.ndarray:
    n = a.shape[0]
    c = max(4, int(round(n * frac)))
    o = (n - c) // 2
    sub = a[o : o + c, o : o + c]
    return np.asarray(
        Image.fromarray(sub.astype(np.uint8)).resize((size, size), Image.BICUBIC),
        dtype=np.float32,
    )


def fit_residual(port_px: np.ndarray, cand_px: np.ndarray) -> tuple[float, float, float, int]:
    """Trimmed, gamma+gain fitted relative RMS between seed and candidate pixels."""
    keep = (cand_px.max(axis=1) < CLIP_HI) & (port_px.max(axis=1) < CLIP_HI)
    if keep.sum() < 300:
        return 9.99, 0.0, 0.0, int(keep.sum())
    p = port_px[keep]
    best = (9.99, 0.0, 0.0)
    for g in GAMMAS:
        c = np.power(np.maximum(cand_px[keep], 0.0) / 255.0, g) * 255.0
        denom = float((c * c).sum())
        if denom < 1e-6:
            continue
        gain = float((p * c).sum() / denom)
        err = ((p - gain * c) ** 2).mean(axis=1)
        cut = np.sort(err)[: max(100, int(len(err) * (1.0 - TRIM)))]
        rel = float(np.sqrt(cut.mean())) / max(float(np.sqrt((p**2).mean())), 1e-6)
        if rel < best[0]:
            best = (rel, gain, g)
    return best[0], best[1], best[2], int(keep.sum())


def best_match(port: np.ndarray, mask: np.ndarray, faces: list[np.ndarray]) -> dict:
    port_px = port[mask]
    best = {"score": 9.99}
    for fi, face in enumerate(faces):
        for oname, o in orientations(face):
            for frac in CROPS:
                cand = center_crop_resize(np.ascontiguousarray(o), frac, SIZE)
                score, gain, gamma, n = fit_residual(port_px, cand[mask])
                if score < best["score"]:
                    best = {
                        "score": score,
                        "face": FACES[fi],
                        "orient": oname,
                        "crop": frac,
                        "gain": gain,
                        "gamma": gamma,
                        "px": n,
                    }
    return best


def main() -> None:
    dbg = OUT / "_match_check"
    dbg.mkdir(parents=True, exist_ok=True)
    mask = corner_triangles(SIZE)

    ports = {}
    for race, res in PORTRAITS.items():
        p = np.asarray(Image.open(resolve_resfile(res)).convert("RGB"), dtype=np.float32)
        ports[race] = p
        vis = p.copy()
        vis[~mask] *= 0.15
        Image.fromarray(vis.astype(np.uint8)).save(dbg / f"seed_{race}.png")
        print(f"[seed] {race:11s} corner px={mask.sum()} mean={p[mask].mean(0).round(1)}")

    cubes = {}
    for race, res in CUBES.items():
        f = cube_faces(res)
        cubes[race] = f
        w = f[0].shape[1]
        sheet = Image.new("RGB", (w * 3, w * 2))
        for i, im in enumerate(f):
            sheet.paste(Image.fromarray(im.astype(np.uint8)), ((i % 3) * w, (i // 3) * w))
        sheet.save(dbg / f"cube{CUBE_KIND}_{race}.png")
        print(f"[cand] {race:11s} face={w}px mean={np.stack(f).mean((0, 1, 2)).round(1)}")

    matrix, detail, verdicts = {}, {}, {}
    print("\n=== corner-seed match (relative RMS after exposure fit; lower = better) ===")
    print("portrait\\cube ".ljust(15) + "".join(f"{c:>12s}" for c in CUBES))
    for pr in PORTRAITS:
        row, det = {}, {}
        for cb in CUBES:
            b = best_match(ports[pr], mask, cubes[cb])
            row[cb] = b["score"]
            det[cb] = b
        matrix[pr], detail[pr] = row, det
        order = sorted(row, key=row.get)
        best, second = order[0], order[1]
        verdicts[pr] = {
            "expected": pr,
            "best": best,
            "ok": best == pr,
            "best_score": row[best],
            "expected_score": row[pr],
            "runner_up": second,
            "separation": row[second] - row[best],
            "best_detail": det[best],
            "expected_detail": det[pr],
        }
        print(
            f"{pr:14s}"
            + "".join(f"{row[c]:12.4f}" for c in CUBES)
            + f"   -> {best} ({'OK' if best == pr else 'MISMATCH'})"
        )

    for pr, v in verdicts.items():
        d = v["best_detail"]
        e = v["expected_detail"]
        print(
            f"\n{pr}: best={v['best']} score={v['best_score']:.4f} "
            f"face={d['face']} {d['orient']} crop={d['crop']} gain={d['gain']:.2f} "
            f"gamma={d['gamma']} | runner-up {v['runner_up']} (+{v['separation']:.4f})"
            f"\n    name-matched {pr}: score={v['expected_score']:.4f} face={e['face']} "
            f"{e['orient']} crop={e['crop']} gain={e['gain']:.2f} gamma={e['gamma']}"
        )

    hits = sum(1 for v in verdicts.values() if v["ok"])
    print(f"\nname-match verified: {hits}/{len(verdicts)}")
    (dbg / "match_report.json").write_text(
        json.dumps(
            {
                "cube_kind": CUBE_KIND,
                "corner_frac": CORNER_FRAC,
                "matrix": matrix,
                "verdicts": verdicts,
                "hits": hits,
            },
            ensure_ascii=False,
            indent=2,
            default=float,
        ),
        encoding="utf-8",
    )
    print("wrote", dbg / "match_report.json")


if __name__ == "__main__":
    main()
