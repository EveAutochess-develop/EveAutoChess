#!/usr/bin/env python3
"""Find candidate section 6 BitKnit header fill bit offsets."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT_SECTION6_RECORD_SIZE,
    find_section6_control_fill_candidate,
    find_section6_fill_candidates,
)
from io_scene_gr2.gr2.file import read_gr2
from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL
from tools.scan_bitknit_corpus import DEFAULT_CACHE_DIR, DEFAULT_ROOT, _iter_gr2_paths, _oracle_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", type=Path, default=[DEFAULT_ROOT])
    parser.add_argument("--section", type=int, default=6)
    parser.add_argument("--max-files", type=int, default=8)
    parser.add_argument("--max-input-files", type=int, default=0)
    parser.add_argument("--prefix", type=int, default=BITKNIT_SECTION6_RECORD_SIZE)
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
        candidates = find_section6_fill_candidates(compressed, oracle[: args.prefix])
        selected = find_section6_control_fill_candidate(compressed, oracle[: args.prefix])
        rows.append(
            {
                "path": str(path),
                "section": section.index,
                "oracle_prefix": oracle[: min(args.prefix, 16)].hex(" "),
                "selected": selected.to_dict() if selected else None,
                "candidate_count": len(candidates),
                "candidates": [candidate.to_dict() for candidate in candidates[:24]],
            }
        )
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


if __name__ == "__main__":
    raise SystemExit(main())
