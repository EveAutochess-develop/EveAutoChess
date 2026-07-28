#!/usr/bin/env python3
"""Build a redistributable Blender addon zip."""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADDON_DIR = ROOT / "io_scene_gr2"
DIST_DIR = ROOT / "dist"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    version = _addon_version()
    out_path = args.out or DIST_DIR / f"io_scene_gr2-{version}.zip"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(ADDON_DIR.rglob("*")):
            if not path.is_file() or _skip(path):
                continue
            archive.write(path, path.relative_to(ROOT))
        for name in ("README.md", "LICENSE"):
            path = ROOT / name
            if path.is_file():
                archive.write(path, path.name)

    print(out_path)
    return 0


def _addon_version() -> str:
    source = (ADDON_DIR / "__init__.py").read_text(encoding="utf-8")
    marker = '"version": ('
    start = source.index(marker) + len(marker)
    end = source.index(")", start)
    parts = [part.strip() for part in source[start:end].split(",") if part.strip()]
    return ".".join(parts)


def _skip(path: Path) -> bool:
    parts = set(path.parts)
    if "__pycache__" in parts or path.suffix in {".pyc", ".pyo"}:
        return True
    return path.name == "research_native.py"


if __name__ == "__main__":
    raise SystemExit(main())
