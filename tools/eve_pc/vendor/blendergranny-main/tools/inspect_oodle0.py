#!/usr/bin/env python3
"""Inspect Oodle0 section headers without decoding."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_OODLE0
from io_scene_gr2.gr2.decompress.oodle0 import parse_oodle0_plan
from io_scene_gr2.gr2.file import read_gr2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()

    failed = 0
    for path in _iter_files(args.paths):
        try:
            gr2 = read_gr2(path)
        except Exception as exc:
            failed += 1
            print(f"FAIL parse {path}: {exc}")
            continue

        sections = [section for section in gr2.sections if section.compression == COMPRESSION_OODLE0]
        if not sections:
            continue
        print(f"{path}: oodle0_sections={len(sections)}")
        for section in sections:
            try:
                plan = parse_oodle0_plan(section, gr2.section_bytes(section))
                print("  " + json.dumps(plan.to_dict(), sort_keys=True))
            except Exception as exc:
                failed += 1
                print(f"  FAIL section {section.index}: {exc}")
    print(f"TOTAL failed={failed}")
    return 1 if failed else 0


def _iter_files(paths: list[Path]):
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.gr2"))
            yield from sorted(path.rglob("*.GR2"))
        else:
            yield path


if __name__ == "__main__":
    raise SystemExit(main())
