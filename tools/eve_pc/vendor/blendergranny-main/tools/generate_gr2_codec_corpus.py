#!/usr/bin/env python3
"""Generate a private GR2 compression corpus with the local Granny preprocessor."""

from __future__ import annotations

import argparse
import json
import os
import platform
import random
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.file import read_gr2


DEFAULT_PREPROCESSOR = Path(os.environ.get("GR2_PREPROCESSOR", "preprocessor.exe"))
CODECS = {
    "oodle1": "CompressOodle1",
    "bitknit": "CompressBitKnit",
    "bitknit2": "CompressBitKnit2",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("roots", nargs="+", type=Path)
    parser.add_argument("--out-root", type=Path, default=Path("gr2_codec_corpus"))
    parser.add_argument("--preprocessor", type=Path, default=DEFAULT_PREPROCESSOR)
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--seed", type=int, default=20260517)
    parser.add_argument("--max-source-bytes", type=int, default=8_000_000)
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--codec", choices=sorted(CODECS), action="append")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    if args.count <= 0:
        raise SystemExit("--count must be positive")
    if not args.preprocessor.is_file():
        raise SystemExit(f"missing preprocessor: {args.preprocessor}")

    codecs = args.codec or sorted(CODECS)
    for folder in ("raw", "oodle0", "oodle1", "bitknit", "bitknit2"):
        (args.out_root / folder).mkdir(parents=True, exist_ok=True)

    sources = select_sources(args)
    rows = []
    failures = []
    for index, source in enumerate(sources, 1):
        stem = f"{index:03d}_{safe_stem(source)}"
        raw_path = args.out_root / "raw" / f"{stem}.gr2"
        print(f"[{index}/{len(sources)}] raw {source}", flush=True)
        if args.overwrite or not raw_path.is_file():
            proc = run_preprocessor(args, "Decompress", source, raw_path)
            if not command_ok(proc, raw_path):
                failures.append(row_failure(source, "raw", proc, raw_path))
                print(f"  raw failed rc={proc.returncode}", flush=True)
                continue

        row = {
            "index": index,
            "source": str(source),
            "raw": str(raw_path),
            "outputs": {},
        }
        for codec in codecs:
            out_path = args.out_root / codec / f"{stem}_{codec}.gr2"
            print(f"  {codec}", flush=True)
            if args.overwrite or not out_path.is_file():
                proc = run_preprocessor(args, CODECS[codec], raw_path, out_path)
                if not command_ok(proc, out_path):
                    failures.append(row_failure(source, codec, proc, out_path))
                    print(f"  {codec} failed rc={proc.returncode}", flush=True)
                    continue
            row["outputs"][codec] = str(out_path)
        rows.append(row)

    manifest = {
        "schema": "gr2_codec_corpus.v1",
        "preprocessor": str(args.preprocessor),
        "count_requested": args.count,
        "count_selected": len(sources),
        "seed": args.seed,
        "codecs": codecs,
        "note": "Oodle0 generation unavailable in Granny 2.11.8 preprocessor; SDK marks Oodle0 compression obsolete/decompression-only.",
        "rows": rows,
        "failures": failures,
    }
    manifest_path = args.out_root / "manifest_codec_corpus.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"manifest {manifest_path}")
    print(json.dumps({"rows": len(rows), "failures": len(failures)}, sort_keys=True))
    return 1 if failures else 0


def select_sources(args: argparse.Namespace) -> list[Path]:
    candidates = []
    for path in iter_gr2_paths(args.roots):
        try:
            if path.stat().st_size > args.max_source_bytes:
                continue
            read_gr2(path)
        except Exception:
            continue
        candidates.append(path)
    rng = random.Random(args.seed)
    rng.shuffle(candidates)
    return candidates[: args.count]


def iter_gr2_paths(roots: list[Path]):
    seen = set()
    for root in roots:
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


def run_preprocessor(args: argparse.Namespace, command_name: str, source: Path, out_path: Path):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    if tmp_path.exists():
        tmp_path.unlink()
    command = [str(args.preprocessor), command_name, str(source), "-output", str(tmp_path)]
    if platform.system() != "Windows":
        command = [args.wine, *command]
    proc = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=args.timeout,
    )
    if proc.returncode == 0 and tmp_path.is_file():
        shutil.move(tmp_path, out_path)
    elif tmp_path.exists():
        tmp_path.unlink()
    return proc


def command_ok(proc: subprocess.CompletedProcess, out_path: Path) -> bool:
    return proc.returncode == 0 and out_path.is_file() and out_path.stat().st_size > 0


def row_failure(source: Path, codec: str, proc: subprocess.CompletedProcess, out_path: Path) -> dict:
    return {
        "source": str(source),
        "codec": codec,
        "output": str(out_path),
        "returncode": proc.returncode,
        "stdout_tail": proc.stdout.strip()[-1000:],
        "stderr_tail": proc.stderr.strip()[-1000:],
    }


def safe_stem(path: Path) -> str:
    name = path.stem.lower()
    safe = "".join(ch if ch.isalnum() else "_" for ch in name).strip("_")
    return safe[:80] or "sample"


if __name__ == "__main__":
    raise SystemExit(main())
