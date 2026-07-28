#!/usr/bin/env python3
"""Check clean BitKnit output against known oracle hashes."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress import DecompressionError, decompress_section
from io_scene_gr2.gr2.file import read_gr2


KNOWN_HASHES = {
    "290325alin_frz_vafreacamarc.GR2": {
        0: "ba9d4da6c28d8e482b9f5e13f1e7172677d4341df0f8ca45262207d71750f7fb",
        1: "97e8ddd89cf9c1a304e1f5d73e70f6d07a026760785b6fc970aa5ef6f16eae22",
        2: "778810305aa259453bcd99d3a87abd40291d6072dbe2525ceb46e9bd93f06b0f",
        3: "ef03f49816290ffdb32d737b1da7a4d4508ceeba6a6bf8882af5114bf24be5ec",
        4: "3ab52a1bee394801b45e5f11f3d42ad9d70209b647da6143cabb3ac4f72ce14d",
        6: "9804f0d40ee5da4cf97a754479930545638c474f846591b22f2fa67ffb9280dd",
    },
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()

    expected = KNOWN_HASHES.get(args.path.name)
    if expected is None:
        print(f"no known hashes for {args.path.name}")
        return 2

    gr2 = read_gr2(args.path)
    failed = 0
    unsupported = 0
    for section in gr2.sections:
        if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
            continue
        if section.index not in expected:
            continue
        try:
            data = decompress_section(section, gr2.section_bytes(section))
        except DecompressionError as exc:
            unsupported += 1
            print(f"[{section.index}] unsupported {exc}")
            continue
        digest = hashlib.sha256(data).hexdigest()
        if digest != expected[section.index]:
            failed += 1
            print(f"[{section.index}] FAIL {digest} expected {expected[section.index]}")
        else:
            print(f"[{section.index}] ok {digest}")

    print(f"TOTAL failed={failed} unsupported={unsupported}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
