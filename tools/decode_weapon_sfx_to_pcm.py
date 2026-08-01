# -*- coding: utf-8 -*-
"""Decode Wwise-ADPCM weapon SFX WAVs to plain PCM so Godot can import them.

BNK-extracted clips are RIFF containers with Wwise IMA ADPCM (fmt tag 0x8311);
Godot's wav importer only accepts PCM, so every clip failed to load at runtime.
"""
from __future__ import annotations

import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
SFX = ROOT / "godot_project" / "assets" / "audio" / "weapon_sfx"
VGM = ROOT / "tools" / "_tmp" / "vgmstream" / "vgmstream-cli.exe"
BACKUP = ROOT / "tools" / "_tmp" / "weapon_sfx_adpcm_backup"

PCM_TAGS = {1, 3, 0xFFFE}


def fmt_tag(path: Path) -> int:
    with path.open("rb") as f:
        head = f.read(64)
    if len(head) < 36 or head[:4] != b"RIFF":
        return -1
    return struct.unpack_from("<H", head, 20)[0]


def main() -> None:
    if not VGM.exists():
        print(f"missing vgmstream: {VGM}")
        sys.exit(1)
    BACKUP.mkdir(parents=True, exist_ok=True)
    converted, skipped, failed = 0, 0, []
    for wav in sorted(SFX.rglob("*.wav")):
        tag = fmt_tag(wav)
        if tag in PCM_TAGS:
            skipped += 1
            continue
        rel = wav.relative_to(SFX)
        keep = BACKUP / rel
        keep.parent.mkdir(parents=True, exist_ok=True)
        if not keep.exists():
            shutil.copy2(wav, keep)
        out = wav.with_suffix(".pcm.wav")
        proc = subprocess.run(
            [str(VGM), "-o", str(out), str(keep)],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0 or not out.exists():
            failed.append((str(rel), proc.stderr.strip()[:160]))
            continue
        out.replace(wav)
        converted += 1
        print(f"[pcm] {rel} (tag 0x{tag:04x})")
    print(f"converted={converted} already_pcm={skipped} failed={len(failed)}")
    for name, err in failed:
        print(f"  FAIL {name}: {err}")


if __name__ == "__main__":
    main()
