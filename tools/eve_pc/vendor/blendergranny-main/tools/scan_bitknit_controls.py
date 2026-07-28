#!/usr/bin/env python3
"""Scan first BitKnit control token candidates across oracle-backed samples."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT_LITERAL_LIMIT,
    BitKnitOutputWindow,
    make_decoder_state,
    make_zero_biased_literal_profile,
    parse_bitknit_plan,
)
from io_scene_gr2.gr2.file import read_gr2
from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL
from tools.scan_bitknit_corpus import (
    DEFAULT_CACHE_DIR,
    DEFAULT_ROOT,
    _iter_gr2_paths,
    _oracle_bytes,
)


DEFAULT_WEIGHTS = (1, 64, 128, 256, 512, 1024, 2048, 3072, 3985, 4096)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", type=Path, default=[DEFAULT_ROOT])
    parser.add_argument("--bytes", type=int, default=16)
    parser.add_argument("--max-files", type=int, default=4)
    parser.add_argument("--max-sections", type=int, default=24)
    parser.add_argument("--max-input-files", type=int, default=0)
    parser.add_argument("--weights", default=",".join(str(value) for value in DEFAULT_WEIGHTS))
    parser.add_argument("--summary-only", action="store_true")
    parser.add_argument("--dll", type=Path, default=Path(os.environ.get("GR2_ORACLE_DLL", DEFAULT_DLL)))
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    args = parser.parse_args()

    weights = _parse_weights(args.weights)
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
            if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
                continue
            if section.expanded_size == 0:
                continue
            compressed = gr2.section_bytes(section)
            plan = parse_bitknit_plan(section, compressed)
            oracle = _oracle_bytes(args, path, section.index, compressed, section.expanded_size)
            probes = [
                _probe_weight(plan, compressed, oracle[: args.bytes], zero_weight)
                for zero_weight in weights
            ]
            best = max(probes, key=lambda item: (item["score"], item["literal_count"]))
            file_rows.append(
                {
                    "path": str(path),
                    "section": section.index,
                    "header_tag": plan.header.header_tag if plan.header else None,
                    "expanded_size": section.expanded_size,
                    "oracle_prefix": oracle[: args.bytes].hex(" "),
                    "best": best,
                    "probes": [] if args.summary_only else probes,
                }
            )
        if file_rows:
            bitknit_files_seen += 1
            rows.extend(file_rows)

    print(
        json.dumps(
            {
                "paths": [str(path) for path in args.paths],
                "weights": weights,
                "files_scanned": files_scanned,
                "bitknit_files_seen": bitknit_files_seen,
                "sections_seen": len(rows),
                "rows": rows,
            },
            indent=2,
        )
    )
    return 0


def _parse_weights(text: str) -> tuple[int, ...]:
    weights = tuple(int(part.strip()) for part in text.split(",") if part.strip())
    if not weights or any(weight <= 0 for weight in weights):
        raise ValueError("--weights must contain positive integers")
    return weights


def _probe_weight(plan, compressed: bytes, oracle_prefix: bytes, zero_weight: int) -> dict:
    state = make_decoder_state(plan, compressed, make_zero_biased_literal_profile(zero_weight))
    output = BitKnitOutputWindow(len(oracle_prefix))
    trace = []
    stop = None
    while output.offset < len(oracle_prefix):
        token = state.decode_literal_token(output.offset)
        trace.append(token.to_dict())
        if token.symbol >= BITKNIT_LITERAL_LIMIT:
            stop = token.to_dict()
            break
        output.append_literal_delta(token.symbol)
    clean = bytes(output.data)
    return {
        "zero_weight": zero_weight,
        "score": _prefix_score(clean, oracle_prefix),
        "clean_prefix": clean.hex(" "),
        "literal_count": len(clean),
        "stop": stop,
        "last_code": f"0x{state.range_decoder.code:08x}",
        "last_span": f"0x{state.range_decoder.span:08x}",
        "byte_offset": state.range_decoder.byte_offset,
    }


def _prefix_score(clean: bytes, oracle: bytes) -> int:
    score = 0
    for left, right in zip(clean, oracle):
        if left != right:
            break
        score += 1
    return score


if __name__ == "__main__":
    raise SystemExit(main())
