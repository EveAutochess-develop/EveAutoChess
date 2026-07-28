#!/usr/bin/env python3
"""Trace BitKnit literal stream until first control/match token, then match model."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    describe_distance_symbol,
    make_decoder_state,
    make_zero_biased_literal_profile,
    parse_bitknit_plan,
)
from io_scene_gr2.gr2.file import read_gr2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--section", type=int, required=True)
    parser.add_argument("--literal-zero-weight", type=int, default=3985)
    parser.add_argument("--match-steps", type=int, default=4)
    args = parser.parse_args()

    gr2 = read_gr2(args.path)
    section = gr2.sections[args.section]
    if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
        raise SystemExit(f"section {args.section} is {section.compression_name}, not BitKnit")

    compressed = gr2.section_bytes(section)
    plan = parse_bitknit_plan(section, compressed)
    state = make_decoder_state(
        plan,
        compressed,
        make_zero_biased_literal_profile(args.literal_zero_weight),
    )

    literal_trace = []
    token = None
    output_offset = 0
    while output_offset < section.expanded_size:
        token = state.decode_literal_token(output_offset)
        literal_trace.append(token.to_dict())
        if token.kind.name != "literal":
            break
        output_offset += 1

    match_trace = []
    if token and token.kind.name == "match":
        for index in range(max(0, args.match_steps)):
            decoded = state.decode_match_symbol(output_offset)
            match_trace.append(
                {
                    "step": index,
                    "output_offset": output_offset,
                    "context": state.context_index(output_offset),
                    "symbol": decoded.symbol,
                    "distance": describe_distance_symbol(decoded.symbol).to_dict(),
                    "range": [decoded.low, decoded.high, decoded.total],
                    "code": f"0x{state.range_decoder.code:08x}",
                    "span": f"0x{state.range_decoder.span:08x}",
                    "byte_offset": state.range_decoder.byte_offset,
                }
            )

    print(
        json.dumps(
            {
                "path": str(args.path),
                "section": args.section,
                "literal_zero_weight": args.literal_zero_weight,
                "literal_trace": literal_trace,
                "match_trace": match_trace,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
