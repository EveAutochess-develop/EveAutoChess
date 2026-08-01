# -*- coding: utf-8 -*-
"""Test whether TQ ship icons share one backdrop render differing only by zoom.

Icon clusters turned out to be per-hull (same hull, different skins), so
stacking a cluster cannot remove the ship. But if every icon of a race is the
same cube rendered at a different FOV, then for a fixed camera direction the
backdrops are related by a pure scale about the frame centre, and a small hull's
icon can supply real background pixels for a titan's frame.
"""
from __future__ import annotations

import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools" / "eve_pc")]
from eve_pc.resfile_index import INDEX_PATH, fetch_resfile  # noqa: E402

SIZE = 512
TARGET = "res:/dx9/model/ship/minmatar/titan/mt1/icons/2906_512.jpg"
ICON_RE = re.compile(
    r"^res:/dx9/model/ship/(minmatar|angel)/([a-z0-9_]+)/([a-z0-9_]+)/icons/(\d+)_512\.jpg$"
)


def corner_mask(frac: float = 0.14) -> np.ndarray:
    n = int(SIZE * frac)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    return (
        ((xx + yy) < n)
        | (((SIZE - 1 - xx) + yy) < n)
        | ((xx + (SIZE - 1 - yy)) < n)
        | (((SIZE - 1 - xx) + (SIZE - 1 - yy)) < n)
    )


def warp_scale(img: np.ndarray, s: float) -> np.ndarray:
    """Resample img as if seen at 1/s the field of view, about the centre."""
    c = (SIZE - 1) / 2.0
    gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    u = (gx - c) * s + c
    v = (gy - c) * s + c
    out = np.stack(
        [ndimage.map_coordinates(img[..., k], [v, u], order=1, mode="constant", cval=np.nan)
         for k in range(3)],
        axis=-1,
    )
    return out


def main() -> None:
    rows = []
    for line in Path(INDEX_PATH).read_text(encoding="utf-8", errors="ignore").splitlines():
        res = line.split(",")[0]
        m = ICON_RE.match(res)
        if m:
            rows.append((m.group(2), m.group(4), res))
    with ThreadPoolExecutor(12) as ex:
        paths = dict(zip([r[2] for r in rows], ex.map(fetch_resfile, [r[2] for r in rows])))

    tgt = np.asarray(Image.open(paths[TARGET]).convert("RGB"), dtype=np.float32)
    cm = corner_mask()
    big = [r for r in rows if r[0] in
           ("dreadnought", "carrier", "freighter", "forceauxillary", "titan", "battleship")]

    print(f"{'class':16s}{'typeID':>8s}{'bestScale':>11s}{'cornerRMS':>11s}{'cover%':>8s}")
    for cls, tid, res in big:
        if res == TARGET:
            continue
        img = np.asarray(Image.open(paths[res]).convert("RGB"), dtype=np.float32)
        best = (1e9, 1.0, 0.0)
        for s in np.arange(0.30, 1.61, 0.01):
            w = warp_scale(img, s)
            ok = cm & np.isfinite(w).all(axis=-1)
            if ok.sum() < 2000:
                continue
            d = np.abs(w[ok] - tgt[ok]).mean(axis=-1)
            rms = float(np.sqrt((np.sort(d)[: int(len(d) * 0.9)] ** 2).mean()))
            if rms < best[0]:
                best = (rms, float(s), ok.sum() / cm.sum())
        print(f"{cls:16s}{tid:>8s}{best[1]:>11.3f}{best[0]:>11.2f}{best[2] * 100:>7.1f}%")


if __name__ == "__main__":
    main()
