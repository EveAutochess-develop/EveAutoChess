#!/usr/bin/env python3
"""Search simple zero-heavy BitKnit literal profiles against oracle prefix."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT_LITERAL_SYMBOLS,
    BitKnitModelProfile,
    make_decoder_state,
    parse_bitknit_plan,
)
from io_scene_gr2.gr2.file import read_gr2
from tools.compare_bitknit_prefix import _oracle_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--section", type=int, required=True)
    parser.add_argument("--bytes", type=int, default=16)
    parser.add_argument("--max-weight", type=int, default=512)
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--dll", type=Path)
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--wine", default="wine")
    args = parser.parse_args()

    from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL

    if args.dll is None:
        args.dll = DEFAULT_DLL
    if args.build_dir is None:
        args.build_dir = DEFAULT_BUILD_DIR

    gr2 = read_gr2(args.path)
    section = gr2.sections[args.section]
    if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
        raise SystemExit(f"section {args.section} is {section.compression_name}, not BitKnit")

    compressed = gr2.section_bytes(section)
    plan = parse_bitknit_plan(section, compressed)
    oracle = _oracle_bytes(args, compressed, section.expanded_size)[: args.bytes]
    results = []
    for zero_weight in range(1, args.max_weight + 1):
        clean, stopped = _clean_prefix(plan, compressed, args.bytes, zero_weight)
        score = _prefix_score(clean, oracle)
        results.append(
            {
                "zero_weight": zero_weight,
                "score": score,
                "clean_prefix": clean.hex(" "),
                "stopped": stopped,
            }
        )
    results.sort(key=lambda item: (-item["score"], item["zero_weight"]))
    print(
        json.dumps(
            {
                "path": str(args.path),
                "section": args.section,
                "oracle_prefix": oracle.hex(" "),
                "best": results[: args.top],
            },
            indent=2,
        )
    )
    return 0


def _clean_prefix(plan, compressed: bytes, count: int, zero_weight: int) -> tuple[bytes, str | None]:
    from io_scene_gr2.gr2.decompress.bitknit import BITKNIT_LITERAL_LIMIT, BitKnitOutputWindow

    profile = BitKnitModelProfile(
        literal_weights=(zero_weight,) + (1,) * (BITKNIT_LITERAL_SYMBOLS - 1)
    )
    state = make_decoder_state(plan, compressed, profile)
    output = BitKnitOutputWindow(count)
    stopped = None
    while output.offset < count:
        decoded = state.decode_literal_symbol(output.offset)
        if decoded.symbol >= BITKNIT_LITERAL_LIMIT:
            stopped = f"non-literal symbol {decoded.symbol} at offset {output.offset}"
            break
        output.append_literal_delta(decoded.symbol)
    return bytes(output.data), stopped


def _prefix_score(clean: bytes, oracle: bytes) -> int:
    score = 0
    for left, right in zip(clean, oracle):
        if left != right:
            break
        score += 1
    return score


if __name__ == "__main__":
    raise SystemExit(main())
