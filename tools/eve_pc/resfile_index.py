# -*- coding: utf-8 -*-
"""Resolve EVE Tranquility resfiles from H:\\EVE (index + ResFiles + CDN fallback)."""
from __future__ import annotations

import urllib.request
from pathlib import Path

EVE_ROOT = Path(r"H:\EVE")
INDEX_PATH = EVE_ROOT / "tq" / "resfileindex.txt"
RESFILES_ROOT = EVE_ROOT / "ResFiles"
CDN_BASE = "https://resources.eveonline.com"
USER_AGENT = "EVE Online/tx_22.02"


def _load_index() -> dict[str, tuple[str, int]]:
    """res path (lower) -> (rel hash path, uncompressed size)."""
    if not INDEX_PATH.is_file():
        return {}
    out: dict[str, tuple[str, int]] = {}
    for line in INDEX_PATH.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line or "," not in line:
            continue
        parts = line.split(",")
        respath = parts[0].strip()
        if len(parts) < 3:
            continue
        rel = parts[1].strip()
        try:
            size = int(parts[3]) if len(parts) > 3 else 0
        except ValueError:
            size = 0
        out[respath.lower()] = (rel, size)
    return out


def resolve_resfile(res_path: str) -> Path | None:
    """Return on-disk ResFiles path for res:/... if present."""
    key = res_path.replace("\\", "/")
    if not key.lower().startswith("res:"):
        key = "res:/" + key.lstrip("/")
    entry = _load_index().get(key.lower())
    if not entry:
        return None
    rel, _ = entry
    p = RESFILES_ROOT / Path(rel)
    return p if p.is_file() and p.stat().st_size > 512 else None


def fetch_resfile(res_path: str, dst: Path | None = None) -> Path:
    """Ensure resfile exists locally; download from CDN if missing."""
    key = res_path.replace("\\", "/")
    if not key.lower().startswith("res:"):
        key = "res:/" + key.lstrip("/")
    idx = _load_index()
    entry = idx.get(key.lower())
    if not entry:
        raise FileNotFoundError(f"not in resfileindex: {res_path}")
    rel, _ = entry
    local = RESFILES_ROOT / Path(rel)
    if local.is_file() and local.stat().st_size > 512:
        if dst:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(local.read_bytes())
            return dst
        return local
    url = f"{CDN_BASE}/{rel}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    if len(data) < 512:
        raise RuntimeError(f"CDN payload too small for {res_path}: {len(data)} bytes")
    local.parent.mkdir(parents=True, exist_ok=True)
    local.write_bytes(data)
    if dst:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
        return dst
    return local
