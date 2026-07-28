#!/usr/bin/env python3
"""Hash/decode sections through a private Granny DLL bridge.

Research-only helper. It executes an external `gr2_raw_dump.exe` plus
`granny2.dll` that must live outside this repository. No vendor binaries or
decoded section dumps are committed.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import platform
import subprocess
import sys
from pathlib import Path


DEFAULT_HELPER = Path(os.environ.get("GR2_ORACLE_HELPER", "__missing_gr2_oracle_helper__"))
GRANNY_2118_SHA256 = "786954a7652133f793b1e974d791fed8d2ae24d5ad3accd92310d02ef18beca3"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--helper", type=Path, default=DEFAULT_HELPER)
    parser.add_argument(
        "--allow-any-dll",
        action="store_true",
        help="skip the default check that the helper uses Granny 2.11.8.0",
    )
    parser.add_argument("--wine", default=os.environ.get("WINE", "wine"))
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--write-dir", type=Path)
    args = parser.parse_args()

    failed = 0
    if not args.allow_any_dll:
        try:
            _check_oracle_dll(args.helper)
        except Exception as exc:
            print(f"FAIL oracle dll: {exc}")
            return 1

    for path in _iter_files(args.paths):
        try:
            sections = _dump_sections(path, args.helper, args.wine, args.timeout)
        except Exception as exc:
            failed += 1
            print(f"FAIL oracle {path}: {exc}")
            continue

        print(f"{path}: oracle_sections={len(sections)} helper={args.helper}")
        for index, data in sections:
            if args.write_dir is not None:
                out_path = args.write_dir / f"{path.stem}.section{index}.bin"
                out_path.parent.mkdir(parents=True, exist_ok=True)
                out_path.write_bytes(data)
            print(
                "  "
                + json.dumps(
                    {
                        "section": index,
                        "size": len(data),
                        "sha256": hashlib.sha256(data).hexdigest(),
                    },
                    sort_keys=True,
                )
            )
    print(f"TOTAL failed={failed}")
    return 1 if failed else 0


def _iter_files(paths: list[Path]):
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.gr2"))
            yield from sorted(path.rglob("*.GR2"))
        else:
            yield path


def _dump_sections(path: Path, helper: Path, wine: str, timeout: float) -> list[tuple[int, bytes]]:
    if not helper.is_file():
        raise FileNotFoundError(helper)
    command = [str(helper), str(path)]
    env = None
    if platform.system() != "Windows":
        command = [wine, *command]
        env = dict(os.environ)
        env["WINEPREFIX"] = env.get("WINEPREFIX", str(Path.home() / ".wine64"))

    proc = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"helper exited {proc.returncode}: {proc.stderr[-400:]}")

    payload = _parse_json(proc.stdout)
    result = []
    for section in payload.get("sections", []):
        encoded = section.get("d64")
        if encoded:
            data = base64.b64decode(encoded)
            size = int(section.get("sz", len(data)))
            result.append((int(section["i"]), data[:size]))
    if not result:
        raise ValueError("oracle returned no section data")
    return result


def _check_oracle_dll(helper: Path) -> None:
    dll = helper.parent / "granny2.dll"
    if not dll.is_file():
        raise FileNotFoundError(dll)
    digest = hashlib.sha256(dll.read_bytes()).hexdigest()
    if digest != GRANNY_2118_SHA256:
        raise RuntimeError(
            f"{dll} is not Granny 2.11.8.0 oracle "
            f"(sha256={digest}, expected={GRANNY_2118_SHA256})"
        )


def _parse_json(text: str) -> dict:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end < start:
            raise
        return json.loads(text[start : end + 1])


if __name__ == "__main__":
    raise SystemExit(main())
