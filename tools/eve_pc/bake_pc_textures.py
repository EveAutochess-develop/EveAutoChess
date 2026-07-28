# -*- coding: utf-8 -*-
"""Bake EVE PC DDS maps into Godot §0 bundle PNGs (echoes_spaceobject shader)."""
from __future__ import annotations

import re
from pathlib import Path

from PIL import Image

from dds_decode import decode_dds, save_png
from pc_asset_map import canonical_pc_res_path
from pc_drone_map import PC_DRONE_GR2
from resfile_index import fetch_resfile

ROOT = Path(__file__).resolve().parents[2]
PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
MAX_DIM = 1024


def _gr2_base_name(res_path: str) -> str:
    """res:/.../adl1_t1.gr2 -> adl1_t1"""
    stem = Path(res_path.replace("res:/", "").replace("\\", "/")).stem
    return stem


def _res_texture(res_gr2: str, suffix: str) -> str:
    base = _gr2_base_name(res_gr2)
    folder = str(Path(res_gr2.replace("res:/", "").replace("\\", "/")).parent).replace("\\", "/")
    return f"res:/{folder}/{base}{suffix}.dds"


def _fetch_dds(res_path: str, cache: Path) -> Path | None:
    cache.mkdir(parents=True, exist_ok=True)
    name = re.sub(r"[^a-zA-Z0-9_.-]+", "_", res_path.replace("res:/", ""))
    dst = cache / name
    try:
        fetch_resfile(res_path, dst)
        return dst if dst.is_file() and dst.stat().st_size > 256 else None
    except Exception:
        return None


def _channel_gray(path: Path | None) -> Image.Image | None:
    if path is None:
        return None
    im = decode_dds(path)
    if im is None:
        return None
    return im.convert("L")


def _pack_rg(r_path: Path | None, g_path: Path | None, size: tuple[int, int]) -> Image.Image | None:
    r = _channel_gray(r_path)
    g = _channel_gray(g_path)
    if r is None and g is None:
        return None
    if r is None:
        r = Image.new("L", size, 128)
    elif r.size != size:
        r = r.resize(size, Image.Resampling.LANCZOS)
    if g is None:
        g = Image.new("L", size, 128)
    elif g.size != size:
        g = g.resize(size, Image.Resampling.LANCZOS)
    out = Image.merge("RGBA", (r, g, Image.new("L", size, 0), Image.new("L", size, 255)))
    return out


def _pack_pmwo(m_path: Path | None, d_path: Path | None, size: tuple[int, int]) -> Image.Image | None:
    m = _channel_gray(m_path)
    d = _channel_gray(d_path)
    if m is None and d is None:
        return None
    if m is None:
        m = Image.new("L", size, 180)
    elif m.size != size:
        m = m.resize(size, Image.Resampling.LANCZOS)
    if d is None:
        d = Image.new("L", size, 200)
    elif d.size != size:
        d = d.resize(size, Image.Resampling.LANCZOS)
    return Image.merge("RGBA", (m, d, Image.new("L", size, 0), Image.new("L", size, 255)))


def _pack_reduction(d_path: Path | None, a_path: Path | None, size: tuple[int, int]) -> Image.Image | None:
    d = _channel_gray(d_path)
    a = _channel_gray(a_path)
    if d is None and a is None:
        return None
    if d is None:
        d = Image.new("L", size, 255)
    elif d.size != size:
        d = d.resize(size, Image.Resampling.LANCZOS)
    if a is None:
        g = Image.new("L", size, 0)
    else:
        if a.size != size:
            a = a.resize(size, Image.Resampling.LANCZOS)
        g = a.point(lambda v: 255 if v > 200 else int(v * 0.4))
    return Image.merge("RGBA", (d, g, Image.new("L", size, 0), Image.new("L", size, 255)))


def bake_bundle_for_res_path(model_key: str, res_gr2: str, *, cache_dir: Path | None = None) -> dict[str, str]:
    """Write §0 PNGs for an explicit PC GR2 path; return res:// paths written."""
    out_dir = PACKS / model_key
    out_dir.mkdir(parents=True, exist_ok=True)
    cache = cache_dir or (Path(__file__).resolve().parent / "_dds_cache")
    written: dict[str, str] = {}

    paths = {
        "a": _fetch_dds(_res_texture(res_gr2, "_a"), cache),
        "n": _fetch_dds(_res_texture(res_gr2, "_n"), cache),
        "r": _fetch_dds(_res_texture(res_gr2, "_r"), cache),
        "g": _fetch_dds(_res_texture(res_gr2, "_g"), cache),
        "m": _fetch_dds(_res_texture(res_gr2, "_m"), cache),
        "d": _fetch_dds(_res_texture(res_gr2, "_d"), cache),
    }

    if paths["a"] and save_png(paths["a"], out_dir / "albedo.png", max_dim=MAX_DIM):
        written["albedo"] = f"res://assets/models/ships/{model_key}/albedo.png"
    if paths["n"] and save_png(paths["n"], out_dir / "normal.png", max_dim=MAX_DIM):
        written["normal"] = f"res://assets/models/ships/{model_key}/normal.png"

    size = (1024, 1024)
    if paths["a"]:
        probe = decode_dds(paths["a"])
        if probe is not None:
            size = probe.size
            if max(size) > MAX_DIM:
                scale = MAX_DIM / max(size)
                size = (int(size[0] * scale), int(size[1] * scale))

    rg = _pack_rg(paths["r"], paths["g"], size)
    if rg is not None:
        rg.save(out_dir / "rg.png", "PNG")
        written["rg"] = f"res://assets/models/ships/{model_key}/rg.png"

    pmwo = _pack_pmwo(paths["m"], paths["d"], size)
    if pmwo is not None:
        pmwo.save(out_dir / "pmwo.png", "PNG")
        written["pmwo"] = f"res://assets/models/ships/{model_key}/pmwo.png"

    red = _pack_reduction(paths["d"], paths["a"], size)
    if red is not None:
        red.save(out_dir / "reduction.png", "PNG")
        written["reduction"] = f"res://assets/models/ships/{model_key}/reduction.png"

    manifest = out_dir / "textures_pc.txt"
    lines = [f"gr2={res_gr2}", "sources:"]
    for k, p in paths.items():
        if p:
            lines.append(f"  {k}={p.name}")
    lines.append("written:")
    for k, v in written.items():
        lines.append(f"  {k}={v}")
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return written


def bake_bundle(model_key: str, *, cache_dir: Path | None = None) -> dict[str, str]:
    """Write §0 PNGs for model_key; return res:// paths written."""
    res_gr2 = PC_DRONE_GR2.get(model_key)
    if not res_gr2:
        raise KeyError(model_key)
    return bake_bundle_for_res_path(model_key, res_gr2, cache_dir=cache_dir)


def bake_bundle_for_unit(data: dict, *, cache_dir: Path | None = None) -> dict[str, str]:
    model_key = str(data.get("model_key") or "").strip()
    if not model_key:
        raise KeyError("missing model_key")
    res_gr2 = canonical_pc_res_path(data)
    if not res_gr2:
        raise KeyError(model_key)
    return bake_bundle_for_res_path(model_key, res_gr2, cache_dir=cache_dir)


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description="Bake EVE PC drone DDS into §0 bundle PNGs")
    ap.add_argument("--keys", nargs="*", help="model_key subset (default: all PC_DRONE_GR2)")
    args = ap.parse_args()
    keys = args.keys or sorted(PC_DRONE_GR2)
    for key in keys:
        try:
            w = bake_bundle(key)
            print(f"OK {key}: {', '.join(w.keys())}")
        except Exception as exc:
            print(f"FAIL {key}: {exc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
