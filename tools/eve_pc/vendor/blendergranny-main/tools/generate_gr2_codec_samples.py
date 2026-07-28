#!/usr/bin/env python3
"""Generate private GR2 codec fixtures through a local Granny preprocessor.

This is a research-only helper. It calls a user-provided Granny preprocessor
outside this repository and writes generated `.gr2` files to a local output
directory. No SDK files, DLLs, or generated binaries are required by the
runtime addon.
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path


DEFAULT_PREPROCESSOR = Path(os.environ.get("GR2_PREPROCESSOR", "preprocessor.exe"))
CODECS = {
    "oodle1": ("CompressOodle1", "oodle1"),
    "bitknit": ("CompressBitKnit", "bitknit"),
    "bitknit2": ("CompressBitKnit2", "bitknit2"),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--out-dir", type=Path, default=Path("gr2_codec_gen"))
    parser.add_argument("--preprocessor", type=Path, default=DEFAULT_PREPROCESSOR)
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    parser.add_argument("--codec", choices=sorted(CODECS), action="append")
    parser.add_argument("--keep-source-copy", action="store_true")
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    if not args.source.is_file():
        raise SystemExit(f"missing source: {args.source}")
    if not args.preprocessor.is_file():
        raise SystemExit(f"missing preprocessor: {args.preprocessor}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    source = args.source.resolve()
    if args.keep_source_copy:
        source = args.out_dir / f"{args.source.stem}_src{args.source.suffix}"
        shutil.copy2(args.source, source)

    codecs = args.codec or sorted(CODECS)
    failed = 0
    for codec in codecs:
        command_name, suffix = CODECS[codec]
        out_path = args.out_dir / f"{args.source.stem}_{suffix}{args.source.suffix}"
        command = [str(args.preprocessor), command_name, str(source), "-output", str(out_path)]
        if platform.system() != "Windows":
            command = [args.wine, *command]
        proc = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=args.timeout,
        )
        status = "ok" if proc.returncode == 0 and out_path.is_file() else "failed"
        if status != "ok":
            failed += 1
        print(
            f"{codec}: {status} command={command_name} output={out_path} "
            f"returncode={proc.returncode} size={out_path.stat().st_size if out_path.is_file() else 0}"
        )
        if proc.stderr.strip():
            print(proc.stderr.strip()[-800:])
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
