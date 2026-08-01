# -*- coding: utf-8 -*-
"""Try candidate semantics for BitKnit2 extra-bit reads of 16+ bits.

Granny packs extra-bit intervals as one record below 16 bits, but as a
(bits-16) high record plus a full 16-bit low record at or above 16 bits. The clean
decoder collapses both into a single window read, which is where large streams die:
the very first `short_symbol >= 16` token yields an impossible match distance.

This probe swaps in candidate readers and reports how far each one gets.
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

ORIGINAL = bk.BitKnitState7WindowDecoder.read_extra_bits


def _window_read(self, count: int) -> int:
    if count <= 0:
        return 0
    before = self.extra_window
    shifted = before >> count
    if shifted < 0x10000:
        shifted = ((shifted & 0xFFFF) << 16) | self.read_u16le()
    self.extra_window = shifted & bk.BITKNIT_WORD_MASK
    return before & ((1 << count) - 1)


def make_reader(mode: str):
    def reader(self, count: int) -> int:
        if count < 16:
            return _window_read(self, count)
        high_bits = count - 16
        if mode == "two":
            high = _window_read(self, high_bits)
            low = _window_read(self, 16)
        elif mode == "twoswap":
            low = _window_read(self, 16)
            high = _window_read(self, high_bits)
        elif mode == "raw16":
            high = _window_read(self, high_bits)
            low = self.read_u16le()
        elif mode == "rawhigh":
            high = self.read_u16le() & ((1 << high_bits) - 1) if high_bits else 0
            low = _window_read(self, 16)
        else:
            raise ValueError(mode)
        return ((high << 16) | low) & ((1 << count) - 1)

    return reader


MODES = ["single", "two", "twoswap", "raw16", "rawhigh"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("res")
    parser.add_argument("--section", type=int, default=0)
    parser.add_argument("--cap", type=int, default=4_000_000)
    parser.add_argument("--modes", nargs="*", default=MODES)
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    path = Path(fetch_resfile(args.res)) if args.res.startswith("res:") else Path(args.res)
    gr2 = read_gr2(path)
    section = gr2.sections[args.section]
    compressed = gr2.section_bytes(section)
    print(f"{args.res} s{args.section} exp={section.expanded_size} cap={args.cap}")

    for mode in args.modes:
        if mode == "single":
            bk.BitKnitState7WindowDecoder.read_extra_bits = ORIGINAL
        else:
            bk.BitKnitState7WindowDecoder.read_extra_bits = make_reader(mode)
        try:
            result = bk.decode_bitknit_state7_stream(
                compressed, section.expanded_size, max_output_size=args.cap
            )
            print(f"  {mode:<8s} out={len(result.output):>9d} stopped={result.stopped}")
        except Exception as exc:  # noqa: BLE001
            print(f"  {mode:<8s} EXC {type(exc).__name__}: {exc}")
    bk.BitKnitState7WindowDecoder.read_extra_bits = ORIGINAL
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
