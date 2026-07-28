#!/usr/bin/env python3
"""Compare current clean BitKnit prefix attempt against 2.11.8 oracle bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT_LITERAL_LIMIT,
    BITKNIT_SECTION6_INITIAL_FILL_RECORDS,
    BitKnitOutputWindow,
    decode_section6_initial_fill_records_from_header,
    find_section6_control_fill_candidate,
    make_decoder_state,
    make_zero_biased_literal_profile,
    parse_bitknit_plan,
)
from io_scene_gr2.gr2.file import read_gr2
from tools.oracle_sections import GRANNY_2118_SHA256
from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL, _build_probe


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--section", type=int, required=True)
    parser.add_argument("--bytes", type=int, default=16)
    parser.add_argument("--literal-zero-weight", type=int, default=1)
    parser.add_argument("--section6-fill-prelude", action="store_true")
    parser.add_argument("--section6-fill-records", type=int, default=BITKNIT_SECTION6_INITIAL_FILL_RECORDS)
    parser.add_argument("--dll", type=Path, default=Path(os.environ.get("GR2_ORACLE_DLL", DEFAULT_DLL)))
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    args = parser.parse_args()

    gr2 = read_gr2(args.path)
    section = gr2.sections[args.section]
    if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
        raise SystemExit(f"section {args.section} is {section.compression_name}, not BitKnit")

    compressed = gr2.section_bytes(section)
    plan = parse_bitknit_plan(section, compressed)
    oracle = _oracle_bytes(args, compressed, section.expanded_size)
    profile = _profile_from_args(args)
    oracle_prefix = oracle[: args.bytes]
    if args.section6_fill_prelude:
        clean, trace, stopped = _section6_fill_prelude(
            compressed,
            oracle_prefix,
            args.section6_fill_records,
        )
    else:
        clean, trace, stopped = _literal_only_prefix(
            plan,
            compressed,
            min(args.bytes, section.expanded_size),
            profile,
        )
    mismatch = next(
        (index for index, (left, right) in enumerate(zip(clean, oracle_prefix)) if left != right),
        None,
    )
    if mismatch is None and len(clean) != len(oracle_prefix):
        mismatch = min(len(clean), len(oracle_prefix))
    result = {
        "path": str(args.path),
        "section": section.index,
        "oracle_sha256": hashlib.sha256(oracle).hexdigest(),
        "oracle_prefix": oracle_prefix.hex(" "),
        "clean_prefix": clean.hex(" "),
        "literal_zero_weight": args.literal_zero_weight,
        "clean_trace": trace,
        "stopped": stopped,
        "first_mismatch": mismatch,
    }
    print(json.dumps(result, indent=2))
    return 0


def _profile_from_args(args: argparse.Namespace) -> BitKnitModelProfile:
    if args.literal_zero_weight <= 0:
        raise ValueError("--literal-zero-weight must be positive")
    return make_zero_biased_literal_profile(args.literal_zero_weight)


def _oracle_bytes(args: argparse.Namespace, compressed: bytes, expanded_size: int) -> bytes:
    _check_dll(args.dll)
    exe = _build_probe(args.build_dir)
    args.build_dir.mkdir(parents=True, exist_ok=True)
    raw_path = args.build_dir / f"{args.path.stem}.section{args.section}.compressed.bin"
    out_path = args.build_dir / f"{args.path.stem}.section{args.section}.dll.bin"
    raw_path.write_bytes(compressed)
    command = [str(exe), str(args.dll), str(raw_path), str(expanded_size), str(out_path)]
    if platform.system() != "Windows":
        command = [args.wine, *command]
    proc = subprocess.run(command, check=False, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip())
    return out_path.read_bytes()


def _check_dll(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != GRANNY_2118_SHA256:
        raise RuntimeError(f"{path} is not Granny 2.11.8.0 oracle: {digest}")


def _literal_only_prefix(
    plan,
    compressed: bytes,
    count: int,
    profile,
) -> tuple[bytes, list[dict], str | None]:
    state = make_decoder_state(plan, compressed, profile)
    output = BitKnitOutputWindow(count)
    trace = []
    stopped = None
    while output.offset < count:
        token = state.decode_literal_token(output.offset)
        trace.append(token.to_dict())
        if token.symbol >= BITKNIT_LITERAL_LIMIT:
            stopped = (
                f"{token.kind.name} symbol {token.symbol} at offset {output.offset}"
            )
            break
        output.append_literal_delta(token.symbol)
    return bytes(output.data), trace, stopped


def _section6_fill_prelude(
    compressed: bytes,
    oracle_prefix: bytes,
    record_count: int,
) -> tuple[bytes, list[dict], str | None]:
    selected = find_section6_control_fill_candidate(compressed, oracle_prefix)
    if selected is None:
        return b"", [], "no section6 fill candidate"
    clean = decode_section6_initial_fill_records_from_header(
        compressed,
        selected.bit_offset,
        record_count,
    )
    clean = clean[: len(oracle_prefix)]
    trace = [selected.to_dict() | {"record_count": record_count, "clean_size": len(clean)}]
    return clean, trace, None


if __name__ == "__main__":
    raise SystemExit(main())
