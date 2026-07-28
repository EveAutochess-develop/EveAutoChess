#!/usr/bin/env python3
"""Summarize simple BitKnit zero-bias profile probes for all sections."""

from __future__ import annotations

import argparse
import json
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
from tools.compare_bitknit_prefix import _oracle_bytes
from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--bytes", type=int, default=16)
    parser.add_argument("--max-weight", type=int, default=4096)
    parser.add_argument("--dll", type=Path, default=DEFAULT_DLL)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--wine", default="wine")
    args = parser.parse_args()

    gr2 = read_gr2(args.path)
    sections = []
    for section in gr2.sections:
        if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
            continue
        if section.expanded_size == 0:
            continue
        compressed = gr2.section_bytes(section)
        plan = parse_bitknit_plan(section, compressed)
        oracle = _oracle_bytes(_OracleArgs(args, section.index), compressed, section.expanded_size)
        best = _best_zero_weight(plan, compressed, oracle[: args.bytes], args.max_weight)
        sections.append(
            {
                "section": section.index,
                "header_tag": plan.header.header_tag if plan.header else None,
                "compressed_size": len(compressed),
                "expanded_size": section.expanded_size,
                "oracle_prefix": oracle[: args.bytes].hex(" "),
                "best_zero_weight": best,
            }
        )
    print(json.dumps({"path": str(args.path), "sections": sections}, indent=2))
    return 0


class _OracleArgs:
    def __init__(self, args: argparse.Namespace, section: int) -> None:
        self.path = args.path
        self.section = section
        self.dll = args.dll
        self.build_dir = args.build_dir
        self.wine = args.wine


def _best_zero_weight(plan, compressed: bytes, oracle_prefix: bytes, max_weight: int) -> dict:
    best = {
        "zero_weight": None,
        "score": -1,
        "clean_prefix": "",
        "stop": None,
    }
    for zero_weight in range(1, max_weight + 1):
        clean, stop = _clean_prefix(plan, compressed, len(oracle_prefix), zero_weight)
        score = _prefix_score(clean, oracle_prefix)
        if score > best["score"]:
            best = {
                "zero_weight": zero_weight,
                "score": score,
                "clean_prefix": clean.hex(" "),
                "stop": stop,
            }
    return best


def _clean_prefix(plan, compressed: bytes, count: int, zero_weight: int) -> tuple[bytes, dict | None]:
    state = make_decoder_state(plan, compressed, make_zero_biased_literal_profile(zero_weight))
    output = BitKnitOutputWindow(count)
    stop = None
    while output.offset < count:
        token = state.decode_literal_token(output.offset)
        if token.symbol >= BITKNIT_LITERAL_LIMIT:
            stop = token.to_dict()
            break
        output.append_literal_delta(token.symbol)
    return bytes(output.data), stop


def _prefix_score(clean: bytes, oracle: bytes) -> int:
    score = 0
    for left, right in zip(clean, oracle):
        if left != right:
            break
        score += 1
    return score


if __name__ == "__main__":
    raise SystemExit(main())
