#!/usr/bin/env python3
"""Check clean Oodle0 output against known oracle hashes."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_OODLE0
from io_scene_gr2.gr2.decompress import DecompressionError, decompress_section
from io_scene_gr2.gr2.file import read_gr2


GRANNYROCKS_HASHES = {
    0: "5927c92a3c26f043e3d4666006c68c10cf00ab241c6243888ca8866a6970c8b2",
    1: "e555866abd0b7cf5b8592e61e5e9d00aaf6ba186172c78ff989dd8abf6677fa9",
    2: "eb91551a31cbe807155d0c1b7023c896a3a091c9ca0c5372379282aa3e955ea7",
    3: "9bcbb9dd5df90dee1cbfe7dcdbe5bd614193940157befe32c4a0dfb8c5ee6d77",
    4: "6be27601874b3ca35aeb7ec5cdc1076c4b294001c9c98a92d118b4de4a336f67",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()

    gr2 = read_gr2(args.path)
    expected = GRANNYROCKS_HASHES if args.path.name == "GrannyRocks.gr2" else {}
    failed = 0
    unsupported = 0
    for section in gr2.sections:
        if section.compression != COMPRESSION_OODLE0:
            continue
        try:
            data = decompress_section(section, gr2.section_bytes(section))
        except DecompressionError as exc:
            unsupported += 1
            print(f"[{section.index}] unsupported {exc}")
            continue

        digest = hashlib.sha256(data).hexdigest()
        want = expected.get(section.index)
        ok = want is not None and digest == want
        if not ok:
            failed += 1
        print(f"[{section.index}] {'ok' if ok else 'mismatch'} size={len(data)} sha256={digest}")

    print(f"TOTAL failed={failed} unsupported={unsupported}")
    return 1 if failed or unsupported else 0


if __name__ == "__main__":
    raise SystemExit(main())
