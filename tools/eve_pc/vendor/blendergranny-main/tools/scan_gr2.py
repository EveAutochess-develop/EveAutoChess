#!/usr/bin/env python3
"""Scan GR2 files without Blender."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.decompress import DecompressionError, DecompressionUnsupported, decompress_section
from io_scene_gr2.gr2.decompress.research_native import ResearchNativeBackend
from io_scene_gr2.gr2.file import read_gr2
from io_scene_gr2.gr2.fixup import load_sections
from io_scene_gr2.gr2.animation import animation_summary, extract_animation_set
from io_scene_gr2.gr2.geometry import extract_mesh_geometries, geometry_summary
from io_scene_gr2.gr2.skeleton import extract_skeletons, skeleton_summary
from io_scene_gr2.gr2.types import summarize_meshes, summarize_root_object


def iter_files(paths: list[Path]):
    seen: set[Path] = set()
    for path in paths:
        candidates = [path] if path.is_file() else sorted(
            candidate
            for candidate in path.rglob("*")
            if candidate.is_file() and candidate.suffix.lower() == ".gr2"
        )
        for candidate in candidates:
            key = candidate.resolve()
            if key in seen:
                continue
            seen.add(key)
            yield candidate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--max-files", type=int, default=0)
    parser.add_argument("--decompress", action="store_true")
    parser.add_argument("--research-native", action="store_true")
    parser.add_argument("--unsafe-oodle0", action="store_true")
    parser.add_argument("--inspect-root", action="store_true")
    parser.add_argument("--inspect-meshes", action="store_true")
    parser.add_argument("--inspect-geometry", action="store_true")
    parser.add_argument("--inspect-skeletons", action="store_true")
    parser.add_argument("--inspect-animations", action="store_true")
    args = parser.parse_args()

    backend = ResearchNativeBackend(allow_oodle0=args.unsafe_oodle0) if args.research_native else None
    totals: Counter[str] = Counter()
    failed = 0
    scanned = 0

    for path in iter_files(args.paths):
        if args.max_files and scanned >= args.max_files:
            break
        scanned += 1
        try:
            gr2 = read_gr2(path)
        except Exception as exc:
            failed += 1
            print(f"FAIL parse {path}: {exc}")
            continue

        formats = Counter(section.compression_name for section in gr2.sections)
        totals.update(formats)
        print(
            f"{path}: v{gr2.header.version} ptr{gr2.header.pointer_size} "
            f"rev={gr2.header.byte_reversed} sections={len(gr2.sections)} "
            f"formats={dict(formats)}"
        )

        file_backend = backend
        backend_skip: DecompressionUnsupported | None = None
        if backend is not None:
            try:
                backend.validate_file(gr2)
            except DecompressionUnsupported as exc:
                file_backend = None
                backend_skip = exc

        if args.decompress:
            for section in gr2.sections:
                raw = gr2.section_bytes(section)
                try:
                    if backend_skip is not None:
                        raise backend_skip
                    data = file_backend.decompress(section, raw) if file_backend else decompress_section(section, raw)
                    digest = hashlib.sha256(data).hexdigest()[:16]
                    print(
                        f"  [{section.index}] {section.semantic_name} "
                        f"{section.compression_name} ok size={len(data)} sha256={digest}"
                    )
                except (DecompressionUnsupported, DecompressionError) as exc:
                    print(
                        f"  [{section.index}] {section.semantic_name} "
                        f"{section.compression_name} skip {exc}"
                    )
                except Exception as exc:
                    failed += 1
                    print(
                        f"  [{section.index}] {section.semantic_name} "
                        f"{section.compression_name} FAIL {exc}"
                    )

        loaded = None
        if (
            args.inspect_root
            or args.inspect_meshes
            or args.inspect_geometry
            or args.inspect_skeletons
            or args.inspect_animations
        ):
            try:
                loaded = load_sections(gr2, file_backend)
            except DecompressionUnsupported as exc:
                print(f"  load skip {exc}")
            except Exception as exc:
                failed += 1
                print(f"  load FAIL {exc}")

        if args.inspect_root and loaded is not None:
            try:
                summary = summarize_root_object(loaded)
                print("  root " + json.dumps(summary, indent=2, sort_keys=True))
            except Exception as exc:
                failed += 1
                print(f"  root FAIL {exc}")

        if args.inspect_meshes and loaded is not None:
            try:
                summary = summarize_meshes(loaded)
                print("  meshes " + json.dumps(summary, indent=2, sort_keys=True))
            except Exception as exc:
                failed += 1
                print(f"  meshes FAIL {exc}")

        if args.inspect_geometry and loaded is not None:
            try:
                summary = geometry_summary(extract_mesh_geometries(loaded))
                print("  geometry " + json.dumps(summary, indent=2, sort_keys=True))
            except Exception as exc:
                failed += 1
                print(f"  geometry FAIL {exc}")

        if args.inspect_skeletons and loaded is not None:
            try:
                summary = skeleton_summary(extract_skeletons(loaded))
                print("  skeletons " + json.dumps(summary, indent=2, sort_keys=True))
            except Exception as exc:
                failed += 1
                print(f"  skeletons FAIL {exc}")

        if args.inspect_animations and loaded is not None:
            try:
                summary = animation_summary(extract_animation_set(loaded))
                print("  animations " + json.dumps(summary, indent=2, sort_keys=True))
            except Exception as exc:
                failed += 1
                print(f"  animations FAIL {exc}")

    print(f"TOTAL files={scanned} formats={dict(totals)} failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
