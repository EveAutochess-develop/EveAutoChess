# -*- coding: utf-8 -*-
"""Locate EVE PC .gr2 for a project model_key."""
from __future__ import annotations

from pathlib import Path

from pc_drone_map import PC_DRONE_GR2
from resfile_index import EVE_ROOT, fetch_resfile, resolve_resfile

TOOLS_EVE_PC = Path(__file__).resolve().parent
DROP_IN = TOOLS_EVE_PC / "gr2_in"


def search_roots() -> list[Path]:
    roots = [DROP_IN, EVE_ROOT / "ResFiles", Path(r"H:\evegame")]
    out: list[Path] = []
    seen: set[str] = set()
    for r in roots:
        if not r.is_dir():
            continue
        k = str(r).lower()
        if k not in seen:
            seen.add(k)
            out.append(r)
    return out


def find_gr2(model_key: str, *, allow_fetch: bool = True) -> Path | None:
    drop = DROP_IN / f"{model_key}.gr2"
    if drop.is_file() and drop.stat().st_size > 512:
        return drop
    res = PC_DRONE_GR2.get(model_key)
    if not res:
        return None
    local = resolve_resfile(res)
    if local:
        return local
    if not allow_fetch:
        return None
    try:
        fetch_resfile(res, drop)
        return drop if drop.is_file() else None
    except Exception:
        return None
