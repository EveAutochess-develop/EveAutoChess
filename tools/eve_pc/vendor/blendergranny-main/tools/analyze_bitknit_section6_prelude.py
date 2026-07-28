#!/usr/bin/env python3
"""Analyze BitKnit2 section 6 header prelude records."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import find_section6_control_fill_candidate
from io_scene_gr2.gr2.file import read_gr2
from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL
from tools.scan_bitknit_corpus import DEFAULT_CACHE_DIR, DEFAULT_ROOT, _iter_gr2_paths, _oracle_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", type=Path, default=[DEFAULT_ROOT])
    parser.add_argument("--section", type=int, default=6)
    parser.add_argument("--records", type=int, default=8)
    parser.add_argument("--max-files", type=int, default=12)
    parser.add_argument("--max-input-files", type=int, default=0)
    parser.add_argument("--dll", type=Path, default=Path(os.environ.get("GR2_ORACLE_DLL", DEFAULT_DLL)))
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    args = parser.parse_args()

    rows = []
    files_scanned = 0
    bitknit_files_seen = 0
    for path in _iter_gr2_paths(args.paths):
        if bitknit_files_seen >= args.max_files:
            break
        if args.max_input_files and files_scanned >= args.max_input_files:
            break
        files_scanned += 1
        gr2 = read_gr2(path)
        if args.section >= len(gr2.sections):
            continue
        section = gr2.sections[args.section]
        if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
            continue
        if section.expanded_size == 0:
            continue
        compressed = gr2.section_bytes(section)
        oracle = _oracle_bytes(args, path, section.index, compressed, section.expanded_size)
        rows.append(_make_row(path, section.index, compressed, oracle, args.records))
        bitknit_files_seen += 1

    print(
        json.dumps(
            {
                "files_scanned": files_scanned,
                "bitknit_files_seen": bitknit_files_seen,
                "rows": rows,
            },
            indent=2,
        )
    )
    return 0


def _make_row(path: Path, section_index: int, compressed: bytes, oracle: bytes, records: int) -> dict:
    candidate = find_section6_control_fill_candidate(compressed, oracle[:32])
    return {
        "path": str(path),
        "section": section_index,
        "expanded_size": len(oracle),
        "header_tag": int.from_bytes(compressed[2:4], "little") if len(compressed) >= 4 else None,
        "header_16_18": compressed[16:19].hex(" ") if len(compressed) >= 19 else "",
        "fill_offset": candidate.bit_offset if candidate else None,
        "fill_seed": candidate.seed if candidate else None,
        "records": _records(oracle, records),
    }


def _records(data: bytes, count: int) -> list[int]:
    result = []
    for offset in range(0, min(len(data), count * 32), 32):
        if offset + 4 > len(data):
            break
        result.append(int.from_bytes(data[offset : offset + 4], "little"))
    return result


if __name__ == "__main__":
    raise SystemExit(main())
