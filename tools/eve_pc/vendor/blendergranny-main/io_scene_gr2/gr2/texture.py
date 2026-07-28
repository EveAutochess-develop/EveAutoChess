"""Texture path resolution helpers."""

from __future__ import annotations

import ntpath
from pathlib import Path


def texture_basename(texture_file: str) -> str:
    normalized = texture_file.replace("\\", "/")
    return ntpath.basename(normalized)


def texture_candidates(texture_file: str, gr2_path: Path, roots: tuple[Path, ...] = ()) -> tuple[Path, ...]:
    if not texture_file:
        return ()
    raw = Path(texture_file)
    names = tuple(dict.fromkeys(name for name in (texture_file, texture_basename(texture_file)) if name))
    candidates: list[Path] = []

    if raw.is_absolute():
        candidates.append(raw)

    search_roots = _search_roots(gr2_path, roots)
    for root in search_roots:
        for name in names:
            candidates.append(root / name)
    return tuple(dict.fromkeys(candidates))


def resolve_texture_path(texture_file: str, gr2_path: Path, roots: tuple[Path, ...] = ()) -> Path | None:
    for path in texture_candidates(texture_file, gr2_path, roots):
        if path.is_file():
            return path
    basename = texture_basename(texture_file)
    if not basename:
        return None
    for root in _search_roots(gr2_path, roots):
        try:
            match = next(root.rglob(basename))
        except (OSError, StopIteration):
            continue
        if match.is_file():
            return match
    return None


def _search_roots(gr2_path: Path, roots: tuple[Path, ...]) -> tuple[Path, ...]:
    base = gr2_path.parent if gr2_path.suffix else gr2_path
    candidates = [base, *base.parents[:4], *roots]
    return tuple(dict.fromkeys(path.resolve() for path in candidates if path))
