#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Batch-blend ultra-transparent B&W noise into ship + main-equipment portraits.

Layers (in order), each with transparency strictly > 99% (opacity < 1%):
  1) Gaussian grayscale noise
  2) Dense salt-and-pepper grayscale noise

RGB only; original alpha is preserved. Transparent pixels (alpha==0) stay untouched.

Idempotent: first run copies pristine PNGs into a backup tree; later runs always
re-read from that backup so re-runs do not stack noise.

Does not touch design handbook docs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / "godot_project"
DEFAULT_BACKUP = ROOT / "tools" / "_portrait_noise_backup"

# Transparency > 99% ⇒ opacity < 0.01. Default 0.8% opacity (99.2% transparent).
DEFAULT_GAUSS_OPACITY = 0.008
DEFAULT_SP_OPACITY = 0.008
DEFAULT_SP_DENSITY = 0.45  # fraction of pixels that become salt or pepper


def _collect_targets(godot: Path) -> list[Path]:
    """Ship portraits from ship_portraits.json + all main-equipment item_icons."""
    out: set[Path] = set()

    portraits_json = godot / "data" / "ship_portraits.json"
    if portraits_json.is_file():
        data = json.loads(portraits_json.read_text(encoding="utf-8"))
        for rel in data.get("ships", {}).values():
            rel_s = str(rel).replace("res://", "").replace("\\", "/")
            p = godot / rel_s
            if p.is_file() and p.suffix.lower() == ".png":
                out.add(p.resolve())

    item_dir = godot / "assets" / "ui" / "item_icons"
    if item_dir.is_dir():
        for p in item_dir.glob("*.png"):
            out.add(p.resolve())

    return sorted(out)


def _backup_path(backup_root: Path, src: Path, godot: Path) -> Path:
    try:
        rel = src.relative_to(godot)
    except ValueError:
        rel = Path(src.name)
    return backup_root / rel


def _ensure_backup(src: Path, backup_root: Path, godot: Path) -> Path:
    dst = _backup_path(backup_root, src, godot)
    if not dst.is_file():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
    return dst


def _gaussian_bw(h: int, w: int, rng: np.random.Generator) -> np.ndarray:
    """Float32 grayscale [0, 1] Gaussian noise."""
    g = rng.normal(loc=0.5, scale=0.25, size=(h, w)).astype(np.float32)
    return np.clip(g, 0.0, 1.0)


def _salt_pepper_bw(h: int, w: int, density: float, rng: np.random.Generator) -> np.ndarray:
    """Dense salt-and-pepper: mid-gray base with many pure black/white hits."""
    out = np.full((h, w), 0.5, dtype=np.float32)
    mask = rng.random((h, w)) < density
    salt = rng.random((h, w)) < 0.5
    out[mask & salt] = 1.0
    out[mask & ~salt] = 0.0
    return out


def _blend_noise_rgb(
    rgb: np.ndarray,
    alpha: np.ndarray,
    noise_bw: np.ndarray,
    opacity: float,
) -> np.ndarray:
    """Blend grayscale noise into RGB where alpha > 0. opacity in (0, 1)."""
    if opacity <= 0.0:
        return rgb
    if opacity >= 0.01:
        raise ValueError(f"opacity must be < 0.01 (transparency > 99%), got {opacity}")

    noise3 = np.stack([noise_bw, noise_bw, noise_bw], axis=-1)
    visible = (alpha > 0).astype(np.float32)[..., None]
    # Effective blend weight only on opaque/visible pixels.
    w = opacity * visible
    return rgb * (1.0 - w) + noise3 * w


def process_one(
    src_pristine: Path,
    dst_out: Path,
    *,
    gauss_opacity: float,
    sp_opacity: float,
    sp_density: float,
    seed: int,
) -> None:
    im = Image.open(src_pristine).convert("RGBA")
    arr = np.asarray(im).astype(np.float32) / 255.0
    h, w = arr.shape[:2]
    rgb = arr[..., :3]
    alpha = arr[..., 3]

    rng = np.random.default_rng(seed)
    gauss = _gaussian_bw(h, w, rng)
    rgb = _blend_noise_rgb(rgb, alpha, gauss, gauss_opacity)

    sp = _salt_pepper_bw(h, w, sp_density, rng)
    rgb = _blend_noise_rgb(rgb, alpha, sp, sp_opacity)

    out = np.concatenate([rgb, alpha[..., None]], axis=-1)
    out_u8 = np.clip(np.rint(out * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(out_u8, mode="RGBA").save(dst_out, format="PNG", optimize=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", type=Path, default=GODOT, help="godot_project root")
    ap.add_argument("--backup", type=Path, default=DEFAULT_BACKUP, help="pristine backup tree")
    ap.add_argument(
        "--gauss-opacity",
        type=float,
        default=DEFAULT_GAUSS_OPACITY,
        help="Gaussian layer opacity (<0.01; default 0.008 → 99.2%% transparent)",
    )
    ap.add_argument(
        "--sp-opacity",
        type=float,
        default=DEFAULT_SP_OPACITY,
        help="Salt-pepper layer opacity (<0.01; default 0.008)",
    )
    ap.add_argument(
        "--sp-density",
        type=float,
        default=DEFAULT_SP_DENSITY,
        help="Fraction of pixels hit by salt/pepper (default 0.45)",
    )
    ap.add_argument("--seed", type=int, default=20260805, help="Base RNG seed")
    ap.add_argument("--dry-run", action="store_true", help="List targets only")
    ap.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Process at most N files (0 = all)",
    )
    args = ap.parse_args(argv)

    for name, val in (("gauss", args.gauss_opacity), ("sp", args.sp_opacity)):
        if not (0.0 < val < 0.01):
            print(f"error: {name} opacity must satisfy 0 < x < 0.01 (transparency > 99%)", file=sys.stderr)
            return 2

    godot = args.godot.resolve()
    backup_root = args.backup.resolve()
    targets = _collect_targets(godot)
    if args.limit > 0:
        targets = targets[: args.limit]

    print(f"targets: {len(targets)}")
    print(f"backup:  {backup_root}")
    print(f"gauss opacity={args.gauss_opacity} ({(1 - args.gauss_opacity) * 100:.2f}% transparent)")
    print(f"sp    opacity={args.sp_opacity} ({(1 - args.sp_opacity) * 100:.2f}% transparent), density={args.sp_density}")

    if args.dry_run:
        for p in targets:
            print(p.relative_to(godot))
        return 0

    ok = 0
    fail = 0
    for i, out_path in enumerate(targets):
        try:
            pristine = _ensure_backup(out_path, backup_root, godot)
            # Stable per-file seed so same file always gets same noise from backup.
            rel = str(out_path.relative_to(godot)).replace("\\", "/")
            digest = int(hashlib.md5(rel.encode("utf-8")).hexdigest()[:8], 16)
            file_seed = (args.seed + digest) & 0x7FFFFFFF
            process_one(
                pristine,
                out_path,
                gauss_opacity=args.gauss_opacity,
                sp_opacity=args.sp_opacity,
                sp_density=args.sp_density,
                seed=file_seed,
            )
            ok += 1
            if (i + 1) % 25 == 0 or i + 1 == len(targets):
                print(f"  [{i + 1}/{len(targets)}] ok={ok} fail={fail}")
        except Exception as exc:  # noqa: BLE001 — batch: continue other files
            fail += 1
            print(f"FAIL {out_path}: {exc}", file=sys.stderr)

    print(f"done: ok={ok} fail={fail}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
