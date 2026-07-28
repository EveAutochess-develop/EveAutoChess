#!/usr/bin/env python3
"""Run focused BitKnit prefix mutation probes against Granny 2.11.8 oracle."""

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
from tools.probe_bitknit_dll import DEFAULT_DLL

DEFAULT_BUILD_DIR = Path("research_artifacts/bitknit_prefix_mutation_probe")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--section", type=int, required=True)
    parser.add_argument("--start", type=int, default=48)
    parser.add_argument("--end", type=int, default=64)
    parser.add_argument("--prefix", type=int, default=16)
    parser.add_argument("--mode", choices=("all-bits", "bit0", "zero"), default="all-bits")
    parser.add_argument(
        "--filter",
        choices=("all", "ok", "prefix-changed", "later-changed", "fill-bits", "record-changed"),
        default="all",
    )
    parser.add_argument("--record-index", type=int, default=2)
    parser.add_argument("--dll", type=Path, default=Path(os.environ.get("GR2_ORACLE_DLL", DEFAULT_DLL)))
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
    mode = {"all-bits": "0", "bit0": "1", "zero": "2"}[args.mode]
    command = [
        str(exe),
        str(args.dll),
        str(raw_path),
        str(section.expanded_size),
        str(args.start),
        str(args.end),
        str(args.prefix),
        mode,
    ]
    if platform.system() != "Windows":
        command = [args.wine, *command]
    proc = subprocess.run(command, check=False, capture_output=True, text=True)
    if proc.stderr:
        print(proc.stderr.strip(), file=sys.stderr)
    print(_filter_output(proc.stdout, args.filter, args.record_index), end="")
    return proc.returncode


def _filter_output(output: str, mode: str, record_index: int) -> str:
    if mode == "all":
        return output
    lines = output.splitlines()
    baseline = next((line for line in lines if line.startswith("baseline ")), "")
    baseline_prefix = _line_prefix(baseline)
    kept = [baseline] if baseline else []
    baseline_record = _record_u32(baseline_prefix, record_index)
    fill_bits = []
    for line in lines:
        if not line.startswith("off="):
            continue
        ok = " ok=1 " in f" {line} "
        prefix = _line_prefix(line)
        first = _line_first(line)
        if mode == "ok" and ok:
            kept.append(line)
        elif mode == "prefix-changed" and prefix != baseline_prefix:
            kept.append(line)
        elif mode == "later-changed" and ok and first is not None and first >= 0 and prefix == baseline_prefix:
            kept.append(line)
        elif mode == "fill-bits":
            fill = _fill_value(prefix)
            if ok and fill is not None and fill != 0:
                off = _line_int(line, "off")
                bit = _line_int(line, "bit")
                if off is not None and bit is not None:
                    fill_bits.append((off * 8 + bit, off, bit, fill, line))
        elif mode == "record-changed":
            record = _record_u32(prefix, record_index)
            if record is not None and record != baseline_record:
                kept.append(f"record={record} baseline={baseline_record} {line}")
    if mode == "fill-bits":
        for bitpos, off, bit, fill, line in sorted(fill_bits, key=lambda item: abs(item[3])):
            kept.append(f"fill bitpos={bitpos} off={off} bit={bit} fill={fill} line={line}")
    return "\n".join(kept) + ("\n" if kept else "")


def _line_prefix(line: str) -> str:
    marker = " prefix="
    if marker not in line:
        return ""
    return line.split(marker, 1)[1]


def _line_first(line: str) -> int | None:
    return _line_int(line, "first")


def _line_int(line: str, key: str) -> int | None:
    prefix = f"{key}="
    for part in line.split():
        if part.startswith(prefix):
            try:
                return int(part.split("=", 1)[1])
            except ValueError:
                return None
    return None


def _fill_value(prefix: str) -> int | None:
    try:
        values = [int(part, 16) for part in prefix.split()]
    except ValueError:
        return None
    if len(values) < 4:
        return None
    fill = values[1]
    if fill >= 0x80:
        signed_fill = fill - 0x100
    else:
        signed_fill = fill
    if values[0] != ((fill + 2) & 0xFF):
        return None
    if any(value != fill for value in values[1:]):
        return None
    return signed_fill


def _record_u32(prefix: str, record_index: int, record_size: int = 32) -> int | None:
    if record_index < 0:
        return None
    try:
        values = bytes(int(part, 16) for part in prefix.split())
    except ValueError:
        return None
    offset = record_index * record_size
    if offset + 4 > len(values):
        return None
    return int.from_bytes(values[offset : offset + 4], "little")


def _check_dll(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != GRANNY_2118_SHA256:
        raise RuntimeError(f"{path} is not Granny 2.11.8.0 oracle: {digest}")


def _build_probe(build_dir: Path) -> Path:
    build_dir.mkdir(parents=True, exist_ok=True)
    exe = build_dir / "bitknit_prefix_mutation_probe.exe"
    source = Path(__file__).with_name("bitknit_prefix_mutation_probe.c")
    compiler = shutil.which("i686-w64-mingw32-gcc")
    if compiler is None:
        raise RuntimeError("i686-w64-mingw32-gcc not found")
    if exe.exists() and exe.stat().st_mtime >= source.stat().st_mtime:
        return exe
    subprocess.run([compiler, "-O2", "-static", "-o", str(exe), str(source)], check=True)
    return exe


if __name__ == "__main__":
    raise SystemExit(main())
