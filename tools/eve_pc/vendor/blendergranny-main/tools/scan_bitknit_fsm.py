#!/usr/bin/env python3
"""Scan BitKnit section chunk-FSM entry decisions."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import probe_bitknit_chunk_fsm_entry
from io_scene_gr2.gr2.file import read_gr2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--rows", type=int, default=20)
    args = parser.parse_args()

    paths = sorted(args.root.rglob("*.gr2")) + sorted(args.root.rglob("*.GR2"))
    rows = []
    states: Counter[int] = Counter()
    seen = 0
    for path in paths:
        try:
            gr2 = read_gr2(path)
        except Exception:
            continue
        for section_index, section in enumerate(gr2.sections):
            if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
                continue
            data = gr2.section_bytes(section)
            if not data:
                continue
            checkpoint = probe_bitknit_chunk_fsm_entry(data)
            states[checkpoint.state] += 1
            if len(rows) < args.rows:
                rows.append(
                    {
                        "path": str(path),
                        "section": section_index,
                        "expanded_size": section.expanded_size,
                        **checkpoint.to_dict(),
                    }
                )
            seen += 1
            if seen >= args.limit:
                break
        if seen >= args.limit:
            break

    print(json.dumps({"seen": seen, "states": dict(states), "rows": rows}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
