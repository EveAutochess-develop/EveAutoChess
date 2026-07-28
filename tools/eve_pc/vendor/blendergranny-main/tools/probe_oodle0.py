#!/usr/bin/env python3
"""Run Oodle0 research decompression in isolated subprocesses.

This tool is research-only. It calls the private local backend outside this
repository and never ships vendor code or binaries.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_OODLE0
from io_scene_gr2.gr2.decompress.research_native import DEFAULT_RESEARCH_LIB, ResearchNativeBackend
from io_scene_gr2.gr2.file import read_gr2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--section-index", type=int, default=-1, help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.worker:
        if len(args.paths) != 1 or args.section_index < 0:
            raise SystemExit("worker needs one path and --section-index")
        return _worker(args.paths[0], args.section_index)

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
        print(
            f"{path}: oodle0_sections={len(sections)} "
            f"research_lib={DEFAULT_RESEARCH_LIB}"
        )
        for section in sections:
            result = _run_worker(path, section.index, args.timeout)
            if result["status"] != "ok":
                failed += 1
            print("  " + json.dumps(result, sort_keys=True))
    print(f"TOTAL failed={failed}")
    return 1 if failed else 0


def _iter_files(paths: list[Path]):
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.gr2"))
            yield from sorted(path.rglob("*.GR2"))
        else:
            yield path


def _run_worker(path: Path, section_index: int, timeout: float) -> dict:
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--worker",
        "--section-index",
        str(section_index),
        str(path),
    ]
    try:
        proc = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"section": section_index, "status": "timeout", "timeout": timeout}

    if proc.returncode == 0:
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {
                "section": section_index,
                "status": "bad-json",
                "stdout": proc.stdout[-400:],
                "stderr": proc.stderr[-400:],
            }
    return {
        "section": section_index,
        "status": "crash" if proc.returncode < 0 else "error",
        "returncode": proc.returncode,
        "stdout": proc.stdout[-400:],
        "stderr": proc.stderr[-400:],
    }


def _worker(path: Path, section_index: int) -> int:
    gr2 = read_gr2(path)
    section = gr2.sections[section_index]
    backend = ResearchNativeBackend(allow_oodle0=True)
    data = backend.decompress(section, gr2.section_bytes(section))
    print(
        json.dumps(
            {
                "section": section.index,
                "status": "ok",
                "semantic": section.semantic_name,
                "compressed_size": section.data_size,
                "expanded_size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
