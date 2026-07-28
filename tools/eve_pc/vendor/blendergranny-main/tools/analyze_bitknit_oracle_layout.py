#!/usr/bin/env python3
"""Analyze direct BitKnit oracle output layout for sparse u32 patterns."""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.file import read_gr2
from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL
from tools.scan_bitknit_corpus import (
    DEFAULT_CACHE_DIR,
    DEFAULT_ROOT,
    _iter_gr2_paths,
    _oracle_bytes,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", type=Path, default=[DEFAULT_ROOT])
    parser.add_argument("--section", type=int)
    parser.add_argument("--max-files", type=int, default=4)
    parser.add_argument("--max-sections", type=int, default=24)
    parser.add_argument("--max-input-files", type=int, default=0)
    parser.add_argument("--limit", type=int, default=2048)
    parser.add_argument("--stride", type=int, default=32)
    parser.add_argument("--dll", type=Path, default=Path(os.environ.get("GR2_ORACLE_DLL", DEFAULT_DLL)))
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    args = parser.parse_args()

    rows = []
    files_scanned = 0
    bitknit_files_seen = 0
    for path in _iter_gr2_paths(args.paths):
        if bitknit_files_seen >= args.max_files or len(rows) >= args.max_sections:
            break
        if args.max_input_files and files_scanned >= args.max_input_files:
            break
        files_scanned += 1
        gr2 = read_gr2(path)
        file_rows = []
        for section in gr2.sections:
            if len(rows) + len(file_rows) >= args.max_sections:
                break
            if args.section is not None and section.index != args.section:
                continue
            if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
                continue
            if section.expanded_size == 0:
                continue
            compressed = gr2.section_bytes(section)
            oracle = _oracle_bytes(args, path, section.index, compressed, section.expanded_size)
            file_rows.append(_analyze(path, section.index, oracle, args.limit, args.stride))
        if file_rows:
            bitknit_files_seen += 1
            rows.extend(file_rows)

    print(
        json.dumps(
            {
                "paths": [str(path) for path in args.paths],
                "files_scanned": files_scanned,
                "bitknit_files_seen": bitknit_files_seen,
                "sections_seen": len(rows),
                "limit": args.limit,
                "stride": args.stride,
                "rows": rows,
            },
            indent=2,
        )
    )
    return 0


def _analyze(path: Path, section_index: int, data: bytes, limit: int, stride: int) -> dict:
    window = data[: min(len(data), limit)]
    nonzero_u32 = []
    value_counts = Counter()
    stride_offsets = Counter()
    for offset in range(0, len(window) - 3, 4):
        value = int.from_bytes(window[offset : offset + 4], "little")
        if not value:
            continue
        nonzero_u32.append(
            {
                "offset": offset,
                "record": offset // stride if stride else None,
                "record_offset": offset % stride if stride else None,
                "value": value,
            }
        )
        value_counts[value] += 1
        if stride:
            stride_offsets[offset % stride] += 1
    return {
        "path": str(path),
        "section": section_index,
        "size": len(data),
        "nonzero_u32_count": len(nonzero_u32),
        "value_counts": dict(value_counts.most_common()),
        "stride_offset_counts": dict(stride_offsets.most_common()),
        "first_nonzero_u32": nonzero_u32[:96],
    }


if __name__ == "__main__":
    raise SystemExit(main())
