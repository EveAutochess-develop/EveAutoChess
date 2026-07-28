#!/usr/bin/env python3
"""Run BitKnit mutation probes against Granny 2.11.8 oracle."""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.file import read_gr2
from tools.oracle_sections import GRANNY_2118_SHA256

DEFAULT_DLL = Path(os.environ.get("GR2_ORACLE_DLL", "__missing_gr2_oracle_dll__"))
DEFAULT_BUILD_DIR = Path("research_artifacts/bitknit_mutation_probe")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--section", type=int, required=True)
    parser.add_argument("--dll", type=Path, default=DEFAULT_DLL)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    args = parser.parse_args()

    _check_dll(args.dll)
    exe = _build_probe(args.build_dir)
    gr2 = read_gr2(args.path)
    section = gr2.sections[args.section]
    if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
        raise SystemExit(f"section {args.section} is {section.compression_name}, not BitKnit")

    args.build_dir.mkdir(parents=True, exist_ok=True)
    raw_path = args.build_dir / f"{args.path.stem}.section{section.index}.compressed.bin"
    raw_path.write_bytes(gr2.section_bytes(section))

    command = [str(exe), str(args.dll), str(raw_path), str(section.expanded_size)]
    if platform.system() != "Windows":
        command = [args.wine, *command]
    proc = subprocess.run(command, check=False, capture_output=True, text=True)
    if proc.stderr:
        print(proc.stderr.strip(), file=sys.stderr)
    print(proc.stdout, end="")
    return proc.returncode


def _check_dll(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != GRANNY_2118_SHA256:
        raise RuntimeError(f"{path} is not Granny 2.11.8.0 oracle: {digest}")


def _build_probe(build_dir: Path) -> Path:
    build_dir.mkdir(parents=True, exist_ok=True)
    exe = build_dir / "bitknit_mutation_probe.exe"
    source = Path(__file__).with_name("bitknit_mutation_probe.c")
    compiler = shutil.which("i686-w64-mingw32-gcc")
    if compiler is None:
        raise RuntimeError("i686-w64-mingw32-gcc not found")
    if exe.exists() and exe.stat().st_mtime >= source.stat().st_mtime:
        return exe
    subprocess.run([compiler, "-O2", "-static", "-o", str(exe), str(source)], check=True)
    return exe


if __name__ == "__main__":
    raise SystemExit(main())
