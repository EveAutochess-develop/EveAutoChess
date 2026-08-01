# -*- coding: utf-8 -*-
"""Cut a ship out of its 512 icon by reconstructing the TQ icon background.

verify_iconbackground_match.py established that the visible backdrop of a 512
ship icon is the 32x32 ship_<race>_cube_blur.dds face upscaled, so the
background can be rebuilt analytically instead of guessed by flood fill.

Pipeline:
  1. corner-triangle seeds from the portrait (background-only pixels)
  2. coarse-to-fine search over face / orientation / scale / offset / gain
     to find the cube window that reproduces those seeds
  3. rebuild the full-frame background, take the residual, threshold into an
     alpha matte and write an RGBA cutout
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path[:0] = [str(ROOT / "tools")]
from verify_iconbackground_match import (  # noqa: E402
    CLIP_HI,
    PORTRAITS,
    SIZE,
    corner_triangles,
    cube_faces,
)

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\titan_assets_confirm\iconbackground_for_cutout\_cutout"
)
BLUR = "res:/dx9/scene/iconbackground/ship_{race}_cube_blur.dds"
GAMMAS = [1.0, 1.3, 1.6, 2.0, 2.2]


def sample_cube(cube: np.ndarray, d: np.ndarray) -> np.ndarray:
    """Bilinear cubemap lookup by direction. cube is (6, n, n, 3) in D3D face
    order +X -X +Y -Y +Z -Z; a single-face crop cannot cover the icon's field of
    view, it spills across cube edges, so sampling must be seam-aware."""
    n = cube.shape[1]
    x, y, z = d[:, 0], d[:, 1], d[:, 2]
    ax, ay, az = np.abs(x), np.abs(y), np.abs(z)
    face = np.where(
        (ax >= ay) & (ax >= az),
        np.where(x > 0, 0, 1),
        np.where(ay >= az, np.where(y > 0, 2, 3), np.where(z > 0, 4, 5)),
    )
    ma = np.choose(face // 2, [ax, ay, az])
    ma = np.maximum(ma, 1e-9)
    sc = np.select(
        [face == 0, face == 1, face == 2, face == 3, face == 4, face == 5],
        [-z, z, x, x, x, -x],
    )
    tc = np.select(
        [face == 0, face == 1, face == 2, face == 3, face == 4, face == 5],
        [-y, -y, z, -z, -y, -y],
    )
    u = np.clip((sc / ma + 1.0) * 0.5, 0.0, 1.0) * (n - 1)
    v = np.clip((tc / ma + 1.0) * 0.5, 0.0, 1.0) * (n - 1)
    u0, v0 = np.floor(u).astype(np.int32), np.floor(v).astype(np.int32)
    u1, v1 = np.minimum(u0 + 1, n - 1), np.minimum(v0 + 1, n - 1)
    fu, fv = (u - u0)[:, None], (v - v0)[:, None]
    c00 = cube[face, v0, u0]
    c10 = cube[face, v0, u1]
    c01 = cube[face, v1, u0]
    c11 = cube[face, v1, u1]
    return (c00 * (1 - fu) + c10 * fu) * (1 - fv) + (c01 * (1 - fu) + c11 * fu) * fv


def view_dirs(xs: np.ndarray, ys: np.ndarray, yaw: float, pitch: float,
              roll: float, fov: float) -> np.ndarray:
    """Camera rays for normalised image coords (0..1, y down)."""
    t = np.tan(np.radians(fov) * 0.5)
    px = (xs * 2.0 - 1.0) * t
    py = (1.0 - ys * 2.0) * t
    cr, sr = np.cos(np.radians(roll)), np.sin(np.radians(roll))
    rx, ry = px * cr - py * sr, px * sr + py * cr
    d = np.stack([rx, ry, np.ones_like(rx)], axis=-1)
    cp, sp = np.cos(np.radians(pitch)), np.sin(np.radians(pitch))
    cy, sy = np.cos(np.radians(yaw)), np.sin(np.radians(yaw))
    rot_p = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]], dtype=np.float64)
    rot_y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]], dtype=np.float64)
    d = d @ rot_p.T @ rot_y.T
    return d / np.linalg.norm(d, axis=-1, keepdims=True)


def fit_gain(p: np.ndarray, c: np.ndarray) -> tuple[float, float, float]:
    """Best (score, gain, gamma) mapping candidate pixels onto seed pixels.

    A single scalar gain is deliberate: giving the fit per-channel freedom lets
    wrong camera orientations match the seeds and the solve drifts off.
    """
    best = (9.99, 1.0, 1.0)
    norm = max(float(np.sqrt((p**2).mean())), 1e-6)
    for g in GAMMAS:
        cc = np.power(np.maximum(c, 0.0) / 255.0, g) * 255.0
        denom = float((cc * cc).sum())
        if denom < 1e-6:
            continue
        gain = float((p * cc).sum() / denom)
        err = ((p - gain * cc) ** 2).mean(axis=1)
        trimmed = np.sort(err)[: max(100, int(len(err) * 0.75))]
        s = float(np.sqrt(trimmed.mean())) / norm
        if s < best[0]:
            best = (s, gain, g)
    return best


def solve_background(port: np.ndarray, cube: np.ndarray, mask: np.ndarray) -> dict:
    ys, xs = np.nonzero(mask)
    xs_n = xs / (SIZE - 1.0)
    ys_n = ys / (SIZE - 1.0)
    seed = port[mask]
    keep = seed.max(axis=1) < CLIP_HI
    seed_k, xs_k, ys_k = seed[keep], xs_n[keep], ys_n[keep]
    sub = slice(None, None, max(1, len(seed_k) // 2500))
    seed_c, xs_c, ys_c = seed_k[sub], xs_k[sub], ys_k[sub]

    def score_at(p, coarse: bool):
        yaw, pitch, roll, fov = p
        if coarse:
            d = view_dirs(xs_c, ys_c, yaw, pitch, roll, fov)
            return fit_gain(seed_c, sample_cube(cube, d))
        d = view_dirs(xs_k, ys_k, yaw, pitch, roll, fov)
        return fit_gain(seed_k, sample_cube(cube, d))

    best = {"score": 9.99}
    for yaw in range(0, 360, 15):
        for pitch in range(-60, 61, 15):
            for roll in (0, 90, 180, 270):
                for fov in (30, 50, 70, 90, 110):
                    s, gain, gamma = score_at((yaw, pitch, roll, fov), True)
                    if s < best["score"]:
                        best = {"score": s, "yaw": float(yaw), "pitch": float(pitch),
                                "roll": float(roll), "fov": float(fov),
                                "gain": gain, "gamma": gamma}

    steps = np.array([8.0, 8.0, 8.0, 8.0])
    cur = np.array([best["yaw"], best["pitch"], best["roll"], best["fov"]])
    best["score"], best["gain"], best["gamma"] = score_at(cur, False)
    for _ in range(40):
        improved = False
        for i in range(4):
            for sgn in (-1.0, 1.0):
                trial = cur.copy()
                trial[i] += sgn * steps[i]
                trial[3] = float(np.clip(trial[3], 10.0, 140.0))
                trial[1] = float(np.clip(trial[1], -89.0, 89.0))
                s, gain, gamma = score_at(trial, False)
                if s < best["score"] - 1e-6:
                    cur = trial
                    best.update(score=s, gain=gain, gamma=gamma)
                    improved = True
        if not improved:
            steps *= 0.5
            if steps.max() < 0.02:
                break
    best.update(yaw=float(cur[0]), pitch=float(cur[1]), roll=float(cur[2]), fov=float(cur[3]))
    return best


def render_background(cube: np.ndarray, sol: dict) -> np.ndarray:
    gx, gy = np.meshgrid(np.linspace(0, 1, SIZE), np.linspace(0, 1, SIZE))
    d = view_dirs(gx.ravel(), gy.ravel(), sol["yaw"], sol["pitch"], sol["roll"], sol["fov"])
    c = sample_cube(cube, d)
    c = np.power(np.maximum(c, 0.0) / 255.0, sol["gamma"]) * 255.0 * sol["gain"]
    return c.reshape(SIZE, SIZE, 3)


def refine_background(port: np.ndarray, bg: np.ndarray, rough: np.ndarray) -> np.ndarray:
    """Absorb the fitted cube's residual low-frequency error.

    The 32x32 blur cube reproduces the backdrop only approximately, leaving a
    soft gradient band. Estimate that band from background-only pixels via
    normalised convolution and fold it into the background plate.
    """
    err = port - bg
    valid = (~rough).astype(np.float32)
    sigma = 40.0
    wsum = ndimage.gaussian_filter(valid, sigma, mode="nearest")
    corr = np.stack(
        [
            ndimage.gaussian_filter(err[..., c] * valid, sigma, mode="nearest")
            / np.maximum(wsum, 1e-4)
            for c in range(3)
        ],
        axis=-1,
    )
    return bg + corr


STRONG, WEAK = 90.0, 34.0
DETAIL_MIN = 2.5
FEATHER_LO, FEATHER_HI = 18.0, 45.0


def local_detail(port: np.ndarray) -> np.ndarray:
    """Local stddev: hull plating is high frequency, nebula backdrop is not.

    Residual magnitude alone leaks, because leftover low-frequency background
    error touches the hull and floods through hysteresis.
    """
    g = port.mean(axis=-1)
    m = ndimage.gaussian_filter(g, 2.0)
    m2 = ndimage.gaussian_filter(g * g, 2.0)
    return np.sqrt(np.maximum(m2 - m * m, 0.0))


def hull_mask(diff: np.ndarray, detail: np.ndarray, weak: float = WEAK) -> np.ndarray:
    """Hysteresis: grow confident hull seeds into the faint-but-plausible band."""
    strong = (diff > STRONG) & (detail > DETAIL_MIN)
    weak = (diff > weak) & (detail > DETAIL_MIN)
    grown = ndimage.binary_propagation(strong, mask=weak)
    grown = ndimage.binary_closing(grown, np.ones((9, 9)))
    grown = ndimage.binary_fill_holes(grown)
    lab, k = ndimage.label(grown)
    if not k:
        return grown
    sizes = ndimage.sum(grown, lab, range(1, k + 1))
    return lab == (int(np.argmax(sizes)) + 1)


def matte(port: np.ndarray, bg: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    detail = local_detail(port)
    bg2 = bg
    hull = ndimage.binary_dilation(
        np.abs(port - bg).max(axis=-1) > STRONG, np.ones((9, 9))
    )
    for _ in range(3):
        bg2 = refine_background(port, bg, hull)
        diff = np.abs(port - bg2).max(axis=-1)
        hull = ndimage.binary_dilation(hull_mask(diff, detail), np.ones((7, 7)))

    diff = np.abs(port - bg2).max(axis=-1)
    # Lift the weak threshold above the measured background noise floor so a
    # poorly fitted plate does not leave a halo welded to the hull.
    off_hull = diff[~ndimage.binary_dilation(hull, np.ones((21, 21)))]
    floor = float(np.percentile(off_hull, 99.5)) if off_hull.size else WEAK
    weak = min(max(WEAK, floor * 1.15), 55.0)
    core = hull_mask(diff, detail, weak)
    lo = min(max(FEATHER_LO, floor), 35.0)
    a = np.clip((diff - lo) / max(FEATHER_HI - lo, 6.0), 0.0, 1.0)
    halo = ndimage.binary_dilation(core, np.ones((11, 11)))
    a = np.where(halo, np.maximum(a, core.astype(np.float32)), 0.0)
    return ndimage.gaussian_filter(a, 0.7), bg2


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    mask = corner_triangles(SIZE)
    report = {}
    for race, res in PORTRAITS.items():
        from eve_pc.resfile_index import resolve_resfile

        port = np.asarray(Image.open(resolve_resfile(res)).convert("RGB"), dtype=np.float32)
        cube = np.stack(cube_faces(BLUR.format(race=race))).astype(np.float32)
        sol = solve_background(port, cube, mask)
        bg = render_background(cube, sol)
        a, bg2 = matte(port, bg)

        rgba = np.dstack([port, a * 255.0]).astype(np.uint8)
        Image.fromarray(rgba, "RGBA").save(OUT / f"{race}_cutout.png")
        Image.fromarray(bg2.clip(0, 255).astype(np.uint8)).save(OUT / f"{race}_bg.png")
        Image.fromarray((a * 255).astype(np.uint8)).save(OUT / f"{race}_alpha.png")
        resid = np.abs(port - bg2).max(axis=-1)
        Image.fromarray(resid.clip(0, 255).astype(np.uint8)).save(OUT / f"{race}_residual.png")

        corner_err = float(np.abs(port - bg2)[mask].mean())
        report[race] = {
            "yaw": round(sol["yaw"], 2), "pitch": round(sol["pitch"], 2),
            "roll": round(sol["roll"], 2), "fov": round(sol["fov"], 2),
            "gain_rgb": [round(float(v), 4) for v in np.atleast_1d(sol["gain"])],
            "gamma": sol["gamma"],
            "seed_score": round(sol["score"], 4),
            "corner_mean_abs_err": round(corner_err, 2),
            "alpha_coverage": round(float((a > 0.5).mean()), 4),
        }
        print(
            f"{race:9s} yaw={sol['yaw']:7.2f} pitch={sol['pitch']:6.2f} "
            f"roll={sol['roll']:7.2f} fov={sol['fov']:6.2f} "
            f"gain={np.round(np.atleast_1d(sol['gain']), 2)} "
            f"gamma={sol['gamma']} seed={sol['score']:.4f} "
            f"cornerErr={corner_err:.1f} cover={report[race]['alpha_coverage']:.3f}"
        )
    (OUT / "cutout_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("wrote", OUT)


if __name__ == "__main__":
    main()
