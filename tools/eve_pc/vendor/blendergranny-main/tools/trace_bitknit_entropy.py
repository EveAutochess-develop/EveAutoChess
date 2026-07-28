#!/usr/bin/env python3
"""Trace clean BitKnit entropy model steps.

Research helper only. It decodes symbols through the current clean range/model
scaffold without claiming the full BitKnit stream grammar is solved.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT_LITERAL_SYMBOLS,
    BitKnitAdaptiveModel,
    BitKnitModelProfile,
    BitKnitRangeDecoder,
    BitKnitWordRangeDecoder,
    decode_bitknit_state7_prefix,
    make_decoder_state,
    make_dll_literal_table_profile,
    parse_bitknit_plan,
    probe_bitknit_chunk_fsm_entry,
    seed_bitknit_state7_word_ranges,
)
from io_scene_gr2.gr2.file import read_gr2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--section", type=int, required=True)
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument(
        "--model",
        choices=("literal", "match", "dll-literal", "state7-dll-literal", "state7-token"),
        default="literal",
    )
    parser.add_argument("--literal-zero-weight", type=int, default=1)
    args = parser.parse_args()

    gr2 = read_gr2(args.path)
    section = gr2.sections[args.section]
    if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
        raise SystemExit(f"section {args.section} is {section.compression_name}, not BitKnit")

    compressed = gr2.section_bytes(section)
    plan = parse_bitknit_plan(section, compressed)
    if args.model == "dll-literal":
        trace = _trace_dll_literal_table(compressed, plan.payload_offset, args.steps)
        print(
            json.dumps(
                {
                    "path": str(args.path),
                    "section": args.section,
                    "model": args.model,
                    "trace": trace,
                },
                indent=2,
            )
        )
        return 0
    if args.model == "state7-dll-literal":
        checkpoint = probe_bitknit_chunk_fsm_entry(compressed)
        if not checkpoint.uses_compressed_handler:
            raise SystemExit(f"section {args.section} does not enter state7: {checkpoint.to_dict()}")
        seed = seed_bitknit_state7_word_ranges(compressed, checkpoint.input_offset)
        trace = _trace_state7_dll_literal_table(compressed, seed, args.steps)
        print(
            json.dumps(
                {
                    "path": str(args.path),
                    "section": args.section,
                    "model": args.model,
                    "checkpoint": checkpoint.to_dict(),
                    "seed": seed.to_dict(),
                    "trace": trace,
                },
                indent=2,
            )
        )
        return 0
    if args.model == "state7-token":
        checkpoint = probe_bitknit_chunk_fsm_entry(compressed)
        if not checkpoint.uses_compressed_handler:
            raise SystemExit(f"section {args.section} does not enter state7: {checkpoint.to_dict()}")
        seed = seed_bitknit_state7_word_ranges(compressed, checkpoint.input_offset)
        trace = _trace_state7_tokens(compressed, seed, section.expanded_size, args.steps)
        print(
            json.dumps(
                {
                    "path": str(args.path),
                    "section": args.section,
                    "model": args.model,
                    "checkpoint": checkpoint.to_dict(),
                    "seed": seed.to_dict(),
                    "trace": trace,
                },
                indent=2,
            )
        )
        return 0

    profile = _profile_from_args(args)
    state = make_decoder_state(plan, compressed, profile)
    trace = []
    for output_offset in range(max(0, args.steps)):
        if args.model == "literal":
            decoded = state.decode_literal_symbol(output_offset)
        else:
            decoded = state.decode_match_symbol(output_offset)
        trace.append(
            {
                "step": output_offset,
                "context": state.context_index(output_offset),
                "symbol": decoded.symbol,
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
                "model": args.model,
                "literal_zero_weight": args.literal_zero_weight,
                "trace": trace,
            },
            indent=2,
        )
    )
    return 0


def _trace_dll_literal_table(compressed: bytes, payload_offset: int, steps: int) -> list[dict]:
    profile = make_dll_literal_table_profile()
    models = tuple(
        BitKnitAdaptiveModel(
            len(profile.weights),
            initial_weights=profile.weights,
            update_weight=profile.update_weight,
            rebuild_interval=profile.rebuild_interval,
        )
        for _ in range(4)
    )
    decoder = BitKnitRangeDecoder.from_payload(compressed, payload_offset)
    trace = []
    for output_offset in range(max(0, steps)):
        decoded = decoder.take_from_model(models[output_offset & 3])
        trace.append(
            {
                "step": output_offset,
                "context": output_offset & 3,
                "symbol": decoded.symbol,
                "range": [decoded.low, decoded.high, decoded.total],
                "code": f"0x{decoder.code:08x}",
                "span": f"0x{decoder.span:08x}",
                "byte_offset": decoder.byte_offset,
            }
        )
    return trace


def _trace_state7_dll_literal_table(compressed, seed, steps: int) -> list[dict]:
    profile = make_dll_literal_table_profile()
    decoder = BitKnitWordRangeDecoder(compressed, seed.input_offset, seed.range_window)
    trace = []
    for output_offset in range(max(0, steps)):
        decoded = decoder.take_from_dll_profile(profile)
        trace.append(
            {
                "step": output_offset,
                "context": output_offset & 3,
                "symbol": decoded.symbol,
                "range": [decoded.low, decoded.high, decoded.total],
                "window": f"0x{decoder.window:08x}",
                "word_offset": decoder.word_offset,
            }
        )
    return trace


def _trace_state7_tokens(compressed, seed, expanded_size: int, steps: int) -> list[dict]:
    result = decode_bitknit_state7_prefix(
        compressed,
        expanded_size,
        max_steps=max(0, steps),
        with_trace=True,
    )
    trace = list(result.trace)
    if result.stopped and (not trace or trace[-1].get("stop") != result.stopped):
        trace.append({"stop": result.stopped})
    return trace


def _profile_from_args(args: argparse.Namespace) -> BitKnitModelProfile:
    if args.literal_zero_weight <= 0:
        raise ValueError("--literal-zero-weight must be positive")
    if args.literal_zero_weight == 1:
        return BitKnitModelProfile()
    return BitKnitModelProfile(
        literal_weights=(args.literal_zero_weight,) + (1,) * (BITKNIT_LITERAL_SYMBOLS - 1)
    )


if __name__ == "__main__":
    raise SystemExit(main())
