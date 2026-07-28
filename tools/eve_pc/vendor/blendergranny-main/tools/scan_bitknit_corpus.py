#!/usr/bin/env python3
"""Scan BitKnit2 corpus headers against small 2.11.8 oracle prefixes.

This is research tooling, not shipped decoder logic. It keeps oracle output
under research_artifacts/ so we can rerun header/model probes without paying
Wine startup cost for every iteration.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import struct
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT_HEADER_SIZE,
    BITKNIT_LITERAL_LIMIT,
    BitKnitOutputWindow,
    make_decoder_state,
    make_zero_biased_literal_profile,
    parse_bitknit_plan,
)
from io_scene_gr2.gr2.file import read_gr2
from tools.oracle_sections import GRANNY_2118_SHA256
from tools.probe_bitknit_dll import DEFAULT_BUILD_DIR, DEFAULT_DLL, _build_probe


DEFAULT_ROOT = Path(os.environ.get("GR2_CORPUS_ROOT", "__missing_gr2_corpus_root__"))
DEFAULT_CACHE_DIR = Path("research_artifacts/bitknit_corpus")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", type=Path, default=[DEFAULT_ROOT])
    parser.add_argument("--bytes", type=int, default=8)
    parser.add_argument("--max-files", type=int, default=20)
    parser.add_argument("--max-input-files", type=int, default=0)
    parser.add_argument("--max-sections", type=int, default=60)
    parser.add_argument("--zero-max", type=int, default=0)
    parser.add_argument("--dll", type=Path, default=DEFAULT_DLL)
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    args = parser.parse_args()

    if args.bytes <= 0:
        raise SystemExit("--bytes must be positive")
    if args.max_files <= 0 or args.max_sections <= 0:
        raise SystemExit("--max-files and --max-sections must be positive")
    if args.max_input_files < 0:
        raise SystemExit("--max-input-files must be non-negative")
    if args.zero_max < 0:
        raise SystemExit("--zero-max must be non-negative")

    _check_dll(args.dll)
    args.cache_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    files_scanned = 0
    bitknit_files_seen = 0
    parse_failures = []
    for path in _iter_gr2_paths(args.paths):
        if bitknit_files_seen >= args.max_files or len(rows) >= args.max_sections:
            break
        if args.max_input_files and files_scanned >= args.max_input_files:
            break
        files_scanned += 1
        try:
            gr2 = read_gr2(path)
        except Exception as exc:  # pragma: no cover - research report path
            parse_failures.append({"path": str(path), "error": str(exc)})
            continue
        file_rows = []
        for section in gr2.sections:
            if len(rows) + len(file_rows) >= args.max_sections:
                break
            if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
                continue
            if section.expanded_size == 0:
                continue
            compressed = gr2.section_bytes(section)
            plan = parse_bitknit_plan(section, compressed)
            oracle = _oracle_bytes(args, path, section.index, compressed, section.expanded_size)
            row = _make_row(path, section.index, compressed, plan, oracle[: args.bytes])
            if args.zero_max:
                row["zero_probe"] = _best_zero_weight(
                    plan,
                    compressed,
                    oracle[: args.bytes],
                    args.zero_max,
                )
            file_rows.append(row)
        if file_rows:
            bitknit_files_seen += 1
            rows.extend(file_rows)

    report = {
        "paths": [str(path) for path in args.paths],
        "bytes": args.bytes,
        "files_scanned": files_scanned,
        "bitknit_files_seen": bitknit_files_seen,
        "sections_seen": len(rows),
        "parse_failures": parse_failures,
        "groups": _group_rows(rows),
        "rows": rows,
    }
    print(json.dumps(report, indent=2))
    return 0


def _iter_gr2_paths(paths: list[Path]):
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


def _check_dll(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != GRANNY_2118_SHA256:
        raise RuntimeError(f"{path} is not Granny 2.11.8.0 oracle: {digest}")


def _oracle_bytes(
    args: argparse.Namespace,
    path: Path,
    section_index: int,
    compressed: bytes,
    expanded_size: int,
) -> bytes:
    stem = hashlib.sha256(f"{path}:{section_index}".encode("utf-8")).hexdigest()[:16]
    raw_path = args.cache_dir / f"{stem}.compressed.bin"
    out_path = args.cache_dir / f"{stem}.oracle.bin"
    meta_path = args.cache_dir / f"{stem}.json"
    compressed_digest = hashlib.sha256(compressed).hexdigest()
    if out_path.is_file() and meta_path.is_file():
        try:
            meta = json.loads(meta_path.read_text())
        except json.JSONDecodeError:
            meta = {}
        if (
            meta.get("path") == str(path)
            and meta.get("section") == section_index
            and meta.get("compressed_sha256") == compressed_digest
            and meta.get("expanded_size") == expanded_size
        ):
            return out_path.read_bytes()

    raw_path.write_bytes(compressed)
    exe = _build_probe(args.build_dir)
    command = [str(exe), str(args.dll), str(raw_path), str(expanded_size), str(out_path)]
    if platform.system() != "Windows":
        command = [args.wine, *command]
    proc = subprocess.run(command, check=False, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip())
    meta_path.write_text(
        json.dumps(
            {
                "path": str(path),
                "section": section_index,
                "compressed_sha256": compressed_digest,
                "expanded_size": expanded_size,
            },
            indent=2,
        )
    )
    return out_path.read_bytes()


def _make_row(path: Path, section_index: int, compressed: bytes, plan, oracle_prefix: bytes) -> dict:
    header_words = plan.header.words if plan.header else ()
    payload_words = _payload_words(compressed)
    return {
        "path": str(path),
        "section": section_index,
        "compression": plan.compression_name,
        "compressed_size": plan.compressed_size,
        "expanded_size": plan.expanded_size,
        "first_16bit": plan.first_16bit,
        "first_8bit": plan.first_8bit,
        "header_marker": plan.header.marker if plan.header else None,
        "header_tag": plan.header.header_tag if plan.header else None,
        "header_words": [f"0x{word:08x}" for word in header_words],
        "payload_words": [f"0x{word:08x}" for word in payload_words],
        "oracle_prefix": oracle_prefix.hex(" "),
        "oracle_first_u32": _first_u32(oracle_prefix),
    }


def _payload_words(compressed: bytes, count: int = 4) -> tuple[int, ...]:
    start = BITKNIT_HEADER_SIZE
    end = min(len(compressed), start + count * 4)
    payload = compressed[start:end]
    payload += b"\x00" * ((4 - len(payload) % 4) % 4)
    if not payload:
        return ()
    return struct.unpack("<" + "I" * (len(payload) // 4), payload)


def _first_u32(data: bytes) -> str | None:
    if len(data) < 4:
        return None
    return f"0x{struct.unpack_from('<I', data, 0)[0]:08x}"


def _best_zero_weight(plan, compressed: bytes, oracle_prefix: bytes, max_weight: int) -> dict:
    best = {"zero_weight": None, "score": -1, "clean_prefix": "", "stop": None}
    for zero_weight in range(1, max_weight + 1):
        clean, stop = _clean_prefix(plan, compressed, len(oracle_prefix), zero_weight)
        score = _prefix_score(clean, oracle_prefix)
        if score > best["score"]:
            best = {
                "zero_weight": zero_weight,
                "score": score,
                "clean_prefix": clean.hex(" "),
                "stop": stop,
            }
    return best


def _clean_prefix(plan, compressed: bytes, count: int, zero_weight: int) -> tuple[bytes, dict | None]:
    state = make_decoder_state(plan, compressed, make_zero_biased_literal_profile(zero_weight))
    output = BitKnitOutputWindow(count)
    stop = None
    while output.offset < count:
        token = state.decode_literal_token(output.offset)
        if token.symbol >= BITKNIT_LITERAL_LIMIT:
            stop = token.to_dict()
            break
        output.append_literal_delta(token.symbol)
    return bytes(output.data), stop


def _prefix_score(clean: bytes, oracle: bytes) -> int:
    score = 0
    for left, right in zip(clean, oracle):
        if left != right:
            break
        score += 1
    return score


def _group_rows(rows: list[dict]) -> dict:
    by_tag = defaultdict(list)
    first_u32_counter = Counter()
    for row in rows:
        by_tag[str(row["header_tag"])].append(row)
        first_u32_counter[row["oracle_first_u32"]] += 1
    return {
        "header_tag_counts": {
            tag: len(tag_rows)
            for tag, tag_rows in sorted(by_tag.items(), key=lambda item: (-len(item[1]), item[0]))
        },
        "oracle_first_u32_counts": dict(first_u32_counter.most_common()),
    }


if __name__ == "__main__":
    raise SystemExit(main())
