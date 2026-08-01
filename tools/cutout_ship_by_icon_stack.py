# -*- coding: utf-8 -*-
"""Cut a ship out of its 512 icon using other ships' icons as the background.

Every TQ ship icon of a race is the same backdrop render at a different zoom:
warping one icon by a pure scale about the frame centre reproduces another's
background to ~1/255 (see probe_icon_zoom_relation.py). So instead of
approximating the backdrop from the 32x32 blur cube, take real icons of other
hulls, solve each one's scale against the target's corner-triangle seeds, warp
them into the target's frame and median-stack. Each donor hull sits somewhere
different, so the median is the bare background - including underneath the
target hull.

Smaller hulls are the useful donors, exactly as intended: their ship covers
little of the frame, so they contribute background almost everywhere.
"""
from __future__ import annotations

import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools" / "eve_pc")]
from cutout_ship_by_iconbackground import render_background, solve_background  # noqa: E402
from eve_pc.resfile_index import INDEX_PATH, fetch_resfile  # noqa: E402
from verify_iconbackground_match import cube_faces  # noqa: E402

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\titan_assets_confirm\iconbackground_for_cutout\_stack_cutout"
)

SIZE = 512
CORNER_FRAC = 0.14
ACCEPT_RMS = 6.0    # corner RMS (0-255) below which a donor shares the backdrop
MAX_DONORS = 70
SCALE_LO, SCALE_HI = 0.25, 2.60

ICON_RE = re.compile(
    r"^res:/dx9/model/ship/([a-z]+)/([a-z0-9_]+)/([a-z0-9_]+)/icons/(\d+)_512\.jpg$"
)

# races sharing one iconbackground cube; wrong guesses are filtered by ACCEPT_RMS
POOLS = {
    "amarr": ["amarr", "sansha"],
    "caldari": ["caldari", "guristas", "mordu"],
    "gallente": ["gallente", "serpentis"],
    "minmatar": ["minmatar", "angel"],
}
TARGETS = {
    "amarr": "res:/dx9/model/ship/amarr/titan/at1/icons/2910_512.jpg",
    "caldari": "res:/dx9/model/ship/caldari/titan/ct1/icons/2930_512.jpg",
    "gallente": "res:/dx9/model/ship/gallente/titan/gt1/icons/2942_512.jpg",
    "minmatar": "res:/dx9/model/ship/minmatar/titan/mt1/icons/2906_512.jpg",
}
# donor hull classes ordered small-first; small hulls expose the most backdrop
CLASS_RANK = {
    "shuttle": 0, "frigate": 1, "destroyer": 2, "industrial": 3, "cruiser": 4,
    "strategiccruiser": 4, "battlecruiser": 5, "battleship": 6, "barge": 6,
    "freighter": 7, "carrier": 8, "dreadnought": 8, "forceauxillary": 8,
    "capital": 9, "titan": 10, "fighter": 11, "capsule": 12,
}

CENTER = (SIZE - 1) / 2.0


def corner_mask(frac: float = CORNER_FRAC) -> np.ndarray:
    n = int(SIZE * frac)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    return (
        ((xx + yy) < n)
        | (((SIZE - 1 - xx) + yy) < n)
        | ((xx + (SIZE - 1 - yy)) < n)
        | (((SIZE - 1 - xx) + (SIZE - 1 - yy)) < n)
    )


def sample_scaled(img: np.ndarray, s: float, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    u = (xs - CENTER) * s + CENTER
    v = (ys - CENTER) * s + CENTER
    return np.stack(
        [ndimage.map_coordinates(img[..., k], [v, u], order=1, mode="constant", cval=np.nan)
         for k in range(3)],
        axis=-1,
    )


def warp_scale(img: np.ndarray, s: float) -> np.ndarray:
    gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    return sample_scaled(img, s, gx.ravel(), gy.ravel()).reshape(SIZE, SIZE, 3)


def fit_scale(donor: np.ndarray, tgt_px: np.ndarray, xs: np.ndarray,
              ys: np.ndarray) -> tuple[float, float]:
    """Scale mapping donor's backdrop onto the target's corner seeds."""
    def rms(s: float) -> float:
        w = sample_scaled(donor, s, xs, ys)
        ok = np.isfinite(w).all(axis=-1)
        if ok.sum() < len(xs) * 0.6:
            return 1e9
        d = np.abs(w[ok] - tgt_px[ok]).mean(axis=-1)
        # trim: the donor's own hull may intrude into the target's corners
        return float(np.sqrt((np.sort(d)[: int(len(d) * 0.85)] ** 2).mean()))

    best = (1e9, 1.0)
    for s in np.arange(SCALE_LO, SCALE_HI, 0.02):
        r = rms(float(s))
        if r < best[0]:
            best = (r, float(s))
    step = 0.01
    cur = best[1]
    while step > 1e-4:
        moved = False
        for cand in (cur - step, cur + step):
            r = rms(cand)
            if r < best[0] - 1e-6:
                best, cur, moved = (r, cand), cand, True
        if not moved:
            step *= 0.5
    return best[1], best[0]


def index_pool(races: list[str]) -> list[tuple[str, str, str]]:
    rows = []
    for line in Path(INDEX_PATH).read_text(encoding="utf-8", errors="ignore").splitlines():
        res = line.split(",")[0]
        m = ICON_RE.match(res)
        if m and m.group(1) in races:
            rows.append((m.group(2), m.group(4), res))
    rows.sort(key=lambda r: CLASS_RANK.get(r[0], 5))
    return rows


def load(paths: list[str]) -> list[np.ndarray | None]:
    def one(p):
        f = fetch_resfile(p)
        if not f:
            return None
        a = np.asarray(Image.open(f).convert("RGB"), dtype=np.float32)
        return a if a.shape == (SIZE, SIZE, 3) else None

    with ThreadPoolExecutor(12) as ex:
        return list(ex.map(one, paths))


def build_plate(tgt: np.ndarray, donors: list[tuple[str, str, np.ndarray]]) -> tuple:
    cm = corner_mask()
    ys, xs = np.nonzero(cm)
    sub = slice(None, None, 4)
    ys = ys.astype(np.float32)[sub]
    xs = xs.astype(np.float32)[sub]
    tgt_px = tgt[cm][sub]
    # brighter backdrops carry proportionally larger absolute error
    accept = max(ACCEPT_RMS, 0.055 * float(tgt_px.mean()))

    accepted = []
    for cls, tid, img in donors:
        s, r = fit_scale(img, tgt_px, xs, ys)
        if r <= accept:
            accepted.append((r, s, cls, tid, img))
        if len(accepted) >= MAX_DONORS:
            break
    accepted.sort(key=lambda a: a[0])

    if not accepted:
        raise RuntimeError("no donor icon shares this backdrop")
    stack = np.stack([warp_scale(a[4], a[1]) for a in accepted])
    plate, votes = combine_stack(stack)
    return plate, votes, [(a[2], a[3], round(a[1], 4), round(a[0], 2)) for a in accepted]


def combine_stack(stack: np.ndarray, k: int = 5) -> tuple[np.ndarray, np.ndarray]:
    """Per-pixel background estimate from the smoothest donors.

    A plain median keeps a hull ghost: every icon frames its ship on the same
    diagonal, so at those pixels most donors are ship. Backdrop is smooth and
    hulls are not, so pick the donors with the lowest local variance instead.
    """
    n = stack.shape[0]
    gray = stack.mean(axis=-1)
    sd = np.empty_like(gray)
    for i in range(n):
        g = np.nan_to_num(gray[i], nan=0.0)
        m = ndimage.gaussian_filter(g, 2.0)
        m2 = ndimage.gaussian_filter(g * g, 2.0)
        sd[i] = np.sqrt(np.maximum(m2 - m * m, 0.0))
    sd = ndimage.maximum_filter(sd, size=(1, 5, 5))
    sd[~np.isfinite(gray)] = np.inf

    k = min(k, n)
    order = np.argsort(sd, axis=0)[:k]
    sel = np.take_along_axis(stack, order[..., None], axis=0)
    plate = np.nanmedian(sel, axis=0)

    # drop donors that disagree with the estimate, then re-median what is left
    keep = np.abs(stack - plate).max(axis=-1) < 14.0
    votes = keep.sum(axis=0)
    refined = np.nanmedian(np.where(keep[..., None], stack, np.nan), axis=0)
    plate = np.where((votes >= 3)[..., None], refined, plate)
    return plate, votes


def fill_gaps(plate: np.ndarray, votes: np.ndarray) -> np.ndarray:
    bad = ~np.isfinite(plate).all(axis=-1) | (votes < 3)
    if not bad.any():
        return plate
    out = plate.copy()
    idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
    filled = out[tuple(idx)]
    out[bad] = filled[bad]
    return ndimage.gaussian_filter(out, (1.0, 1.0, 0))


def matte(port: np.ndarray, bg: np.ndarray) -> np.ndarray:
    diff = np.abs(port - bg).max(axis=-1)
    strong = diff > 40.0
    weak = diff > 12.0
    core = ndimage.binary_propagation(strong, mask=weak)
    core = ndimage.binary_fill_holes(ndimage.binary_closing(core, np.ones((5, 5))))
    lab, k = ndimage.label(core)
    if k:
        sizes = ndimage.sum(core, lab, range(1, k + 1))
        core = lab == (int(np.argmax(sizes)) + 1)
    a = np.clip((diff - 8.0) / 18.0, 0.0, 1.0)
    halo = ndimage.binary_dilation(core, np.ones((9, 9)))
    a = np.where(halo, np.maximum(a, core.astype(np.float32)), 0.0)
    return ndimage.gaussian_filter(a, 0.6)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    report = {}
    for cube, target in TARGETS.items():
        rows = index_pool(POOLS[cube])
        imgs = load([r[2] for r in rows])
        donors = [(c, t, im) for (c, t, res), im in zip(rows, imgs)
                  if im is not None and res != target]
        tgt = np.asarray(Image.open(fetch_resfile(target)).convert("RGB"), dtype=np.float32)

        plate, votes, used = build_plate(tgt, donors)
        plate = fill_gaps(plate, votes)
        a = matte(tgt, plate)

        Image.fromarray(np.dstack([tgt, a * 255]).astype(np.uint8), "RGBA").save(
            OUT / f"{cube}_cutout.png")
        Image.fromarray(plate.clip(0, 255).astype(np.uint8)).save(OUT / f"{cube}_plate.png")
        Image.fromarray((a * 255).astype(np.uint8)).save(OUT / f"{cube}_alpha.png")
        Image.fromarray(np.abs(tgt - plate).max(-1).clip(0, 255).astype(np.uint8)).save(
            OUT / f"{cube}_residual.png")

        cm = corner_mask()
        report[cube] = {
            "donors_used": len(used),
            "corner_mean_abs_err": round(float(np.abs(tgt - plate)[cm].mean()), 2),
            "alpha_coverage": round(float((a > 0.5).mean()), 4),
            "donors": used[:20],
        }
        print(f"{cube:9s} donors={len(used):3d} "
              f"cornerErr={report[cube]['corner_mean_abs_err']:5.2f} "
              f"cover={report[cube]['alpha_coverage']:.3f} "
              f"best={used[0][0]}/{used[0][1]} s={used[0][2]} rms={used[0][3]}")

    (OUT / "stack_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
