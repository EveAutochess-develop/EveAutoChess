#!/usr/bin/env python3
"""Compact GR2 corpus audit for native decoder/import coverage."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.decompress import DecompressionError, DecompressionUnsupported, decompress_section
from io_scene_gr2.gr2.file import read_gr2
from io_scene_gr2.gr2.fixup import load_sections
from io_scene_gr2.gr2.geometry import extract_mesh_geometries
from io_scene_gr2.gr2.skeleton import extract_skeletons


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--max-files", type=int, default=0)
    parser.add_argument("--max-sections", type=int, default=0)
    parser.add_argument("--max-failures", type=int, default=40)
    parser.add_argument("--progress-every", type=int, default=0)
    parser.add_argument("--import-check", action="store_true")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    report = audit(args)
    text = json.dumps(report, indent=2, sort_keys=True)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n")
    print(text)
    return 1 if report["parse_failures"] or report["decode_failures"] or report["import_failures"] else 0


def audit(args: argparse.Namespace) -> dict:
    totals = Counter()
    section_totals = Counter()
    decode_ok = Counter()
    decode_failures = []
    parse_failures = []
    import_ok = 0
    import_failures = []
    files = 0
    sections = 0

    for path in iter_gr2_paths(args.paths):
        if args.max_files and files >= args.max_files:
            break
        if args.max_sections and sections >= args.max_sections:
            break
        files += 1
        if args.progress_every and files % args.progress_every == 0:
            print(f"progress files={files} sections={sections} path={path}", file=sys.stderr)
        try:
            gr2 = read_gr2(path)
        except Exception as exc:
            append_limited(parse_failures, args.max_failures, {"path": str(path), "error": str(exc)})
            continue

        file_formats = Counter(section.compression_name for section in gr2.sections)
        totals.update(file_formats)
        for section in gr2.sections:
            if args.max_sections and sections >= args.max_sections:
                break
            sections += 1
            section_totals[section.compression_name] += 1
            try:
                data = decompress_section(section, gr2.section_bytes(section))
            except (DecompressionUnsupported, DecompressionError, Exception) as exc:
                append_limited(
                    decode_failures,
                    args.max_failures,
                    {
                        "path": str(path),
                        "section": section.index,
                        "semantic": section.semantic_name,
                        "compression": section.compression_name,
                        "data_size": section.data_size,
                        "expanded_size": section.expanded_size,
                        "error_type": type(exc).__name__,
                        "error": str(exc),
                    },
                )
                continue
            if len(data) == section.expanded_size:
                decode_ok[section.compression_name] += 1
            else:
                append_limited(
                    decode_failures,
                    args.max_failures,
                    {
                        "path": str(path),
                        "section": section.index,
                        "semantic": section.semantic_name,
                        "compression": section.compression_name,
                        "data_size": section.data_size,
                        "expanded_size": section.expanded_size,
                        "error_type": "SizeMismatch",
                        "error": f"{len(data)} != {section.expanded_size}",
                    },
                )

        if args.import_check:
            try:
                loaded = load_sections(gr2)
                geometries = extract_mesh_geometries(loaded)
                skeletons = extract_skeletons(loaded)
                import_ok += 1
                totals["import_geometry_count"] += len(geometries)
                totals["import_skeleton_count"] += len(skeletons)
            except Exception as exc:
                append_limited(
                    import_failures,
                    args.max_failures,
                    {"path": str(path), "error_type": type(exc).__name__, "error": str(exc)},
                )

    return {
        "files": files,
        "sections": sections,
        "format_sections": dict(section_totals),
        "format_mentions": dict(totals),
        "decode_ok": dict(decode_ok),
        "parse_failures": parse_failures,
        "decode_failures": decode_failures,
        "import_ok": import_ok,
        "import_failures": import_failures,
    }


def append_limited(items: list[dict], limit: int, item: dict) -> None:
    if limit <= 0 or len(items) < limit:
        items.append(item)


def iter_gr2_paths(paths: list[Path]):
    seen = set()
    for root in paths:
        candidates = [root] if root.is_file() else sorted(
            path
            for path in root.rglob("*")
            if path.is_file() and path.suffix.lower() == ".gr2"
        )
        for path in candidates:
            key = path.resolve()
            if key in seen:
                continue
            seen.add(key)
            yield path


if __name__ == "__main__":
    raise SystemExit(main())
