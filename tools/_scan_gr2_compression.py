# -*- coding: utf-8 -*-
"""Report GR2 section compression for a set of res:/ paths (headers only, no decode)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from io_scene_gr2.gr2.file import read_gr2  # noqa: E402

INDEX = Path(r"H:\EVE\tq\resfileindex.txt")


def iter_paths(pattern: str) -> list[str]:
    out = []
    for line in INDEX.read_text(encoding="utf-8", errors="replace").splitlines():
        res = line.split(",", 1)[0].strip().lower()
        if res.endswith(".gr2") and pattern in res:
            out.append(res)
    return sorted(set(out))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pattern", help="substring to match in res path")
    parser.add_argument("--limit", type=int, default=200)
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    paths = iter_paths(args.pattern)[: args.limit]
    print(f"matched {len(paths)} gr2 for '{args.pattern}'")
    for res in paths:
        try:
            gr2 = read_gr2(Path(fetch_resfile(res)))
        except Exception as exc:  # noqa: BLE001
            print(f"  {res}\n      FAIL {type(exc).__name__}: {exc}")
            continue
        kinds = {}
        for s in gr2.sections:
            if s.expanded_size == 0:
                continue
            kinds[s.compression_name] = kinds.get(s.compression_name, 0) + 1
        biggest = max((s.expanded_size for s in gr2.sections), default=0)
        print(f"  {res}\n      ptr={gr2.header.pointer_size} {kinds} max_exp={biggest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
