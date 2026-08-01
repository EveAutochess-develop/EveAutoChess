# -*- coding: utf-8 -*-
"""Localise where the clean BitKnit2 state-7 decoder gives up on a GR2 section.

Reports per-64KiB-block progress plus the last decoded tokens, so the stop can be
attributed to a specific grammar branch rather than "decode incomplete".
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from io_scene_gr2.gr2.decompress import bitknit as bk  # noqa: E402
from io_scene_gr2.gr2.file import read_gr2  # noqa: E402

BLOCK = bk.BITKNIT2_BLOCK_OUTPUT_SIZE


def probe(compressed: bytes, expanded: int, cap: int, trace_tail: int) -> None:
    checkpoint = bk.probe_bitknit_chunk_fsm_entry(compressed)
    print(f"  entry: {checkpoint.to_dict()}")
    target = min(cap, expanded)

    core = bk.BitKnitState7Core(compressed, expanded, with_trace=True)
    input_offset = checkpoint.input_offset
    block_index = 0
    stopped = None

    while core.output.offset < target:
        block_end = min(((core.output.offset // BLOCK) + 1) * BLOCK, target)
        seed, decoder = core.start_block(input_offset, emit_initial_literal=block_index == 0)
        before = core.output.offset
        stopped = core.decode_block(decoder, block_end)
        input_offset = decoder.word_offset

        tail = ""
        if stopped is not None:
            tail = f" STOP={stopped}"
        elif core.output.offset > block_end:
            tail = f" OVERSHOOT+{core.output.offset - block_end}"
        elif core.output.offset < block_end:
            tail = " SHORT"
        if tail or block_index < 3 or block_index % 8 == 0:
            print(
                f"  blk {block_index:>4d} out {before:>9d}->{core.output.offset:>9d} "
                f"(end {block_end}) in={input_offset} "
                f"rw=0x{decoder.range_window:08x} ew=0x{decoder.extra_window:08x}"
                f" seed_extra={seed.extra_bits}{tail}"
            )
        if tail.startswith(" OVERSHOOT"):
            print("    tokens around the overshoot:")
            for row in core.trace[-6:]:
                print("     ", row)

        if stopped is not None:
            break
        if core.output.offset >= target:
            break
        if decoder.range_window != 0x10000 or decoder.extra_window != 0x10000:
            stopped = (
                f"no word sentinel (range=0x{decoder.range_window:08x}, "
                f"extra=0x{decoder.extra_window:08x})"
            )
            print(f"  blk {block_index:>4d} STOP={stopped}")
            break
        if input_offset + 2 > len(compressed):
            stopped = "missing next block word"
            print(f"  blk {block_index:>4d} STOP={stopped}")
            break
        import struct

        block_word = struct.unpack_from("<H", compressed, input_offset)[0]
        if block_word == 0:
            stopped = "raw copy block not implemented"
            print(f"  blk {block_index:>4d} STOP={stopped} (block_word==0)")
            break
        block_index += 1

    print(f"  final: out={core.output.offset}/{expanded} stopped={stopped}")

    hist: dict[int, int] = {}
    first: dict[int, int] = {}
    for row in core.trace:
        direct = row.get("direct_distance")
        if not direct:
            continue
        s = int(direct["short_symbol"])
        hist[s] = hist.get(s, 0) + 1
        first.setdefault(s, int(row["offset"]))
    print("  short-distance symbol histogram (count, first output offset):")
    for s in sorted(hist):
        print(f"    s={s:>2d} n={hist[s]:>7d} first@{first[s]}")

    print(f"  last {trace_tail} tokens:")
    for row in core.trace[-trace_tail:]:
        print("   ", row)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("res", help="res:/... path or local file")
    parser.add_argument("--section", type=int, default=0)
    parser.add_argument("--cap", type=int, default=3_000_000)
    parser.add_argument("--trace-tail", type=int, default=12)
    args = parser.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    path = Path(fetch_resfile(args.res)) if args.res.startswith("res:") else Path(args.res)
    gr2 = read_gr2(path)
    section = gr2.sections[args.section]
    print(f"{args.res} section {args.section} {section.compression_name} exp={section.expanded_size}")
    probe(gr2.section_bytes(section), section.expanded_size, args.cap, args.trace_tail)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
