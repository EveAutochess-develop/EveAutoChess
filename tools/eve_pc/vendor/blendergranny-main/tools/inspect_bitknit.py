#!/usr/bin/env python3
"""Inspect BitKnit/BitKnit2 section headers."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT_LITERAL_SYMBOLS,
    BITKNIT_MATCH_SYMBOLS,
    make_chunk_stream,
    make_decoder_state,
    make_range_decoder,
    parse_bitknit_plan,
)
from io_scene_gr2.gr2.file import read_gr2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()

    failed = 0
    for path in args.paths:
        try:
            gr2 = read_gr2(path)
        except Exception as exc:
            failed += 1
            print(f"FAIL parse {path}: {exc}")
            continue

        sections = [
            section
            for section in gr2.sections
            if section.compression in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2)
        ]
        print(f"{path}: bitknit_sections={len(sections)}")
        for section in sections:
            try:
                compressed = gr2.section_bytes(section)
                plan = parse_bitknit_plan(section, compressed)
            except Exception as exc:
                failed += 1
                print(f"  [{section.index}] FAIL {exc}")
                continue
            details = plan.to_dict()
            if not plan.is_empty:
                chunk = make_chunk_stream(plan, compressed).read_chunk()
                range_decoder = make_range_decoder(plan, compressed)
                range_decoder.normalize()
                preview_state = make_decoder_state(plan, compressed)
                first_literal = preview_state.decode_literal_symbol(0)
                details["first_chunk"] = {
                    "offset": chunk.offset,
                    "size": len(chunk.data),
                    "words": [f"0x{word:08x}" for word in chunk.words],
                }
                details["range_preview"] = {
                    "code": f"0x{range_decoder.code:08x}",
                    "span": f"0x{range_decoder.span:08x}",
                    "carry_bit": range_decoder.carry_bit,
                    "byte_offset": range_decoder.byte_offset,
                    "literal_bucket": range_decoder.peek(BITKNIT_LITERAL_SYMBOLS),
                    "match_bucket": range_decoder.peek(BITKNIT_MATCH_SYMBOLS),
                }
                details["first_uniform_literal_symbol"] = {
                    "symbol": first_literal.symbol,
                    "range": [first_literal.low, first_literal.high, first_literal.total],
                    "next_code": f"0x{preview_state.range_decoder.code:08x}",
                    "next_span": f"0x{preview_state.range_decoder.span:08x}",
                }
            print("  " + json.dumps(details, sort_keys=True))

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
