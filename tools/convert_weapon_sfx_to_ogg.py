# -*- coding: utf-8 -*-
"""Convert weapon_sfx WAV → Ogg Vorbis and refresh WeaponSfxCatalog.

Uses imageio-ffmpeg's bundled ffmpeg (no system ffmpeg required).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg

ROOT = Path(r"H:\game_dev\eveautochess-dev")
SFX = ROOT / "godot_project" / "assets" / "audio" / "weapon_sfx"
CATALOG = ROOT / "godot_project" / "scripts" / "audio" / "weapon_sfx_catalog.gd"
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def convert_one(wav: Path) -> Path:
    ogg = wav.with_suffix(".ogg")
    cmd = [
        FFMPEG,
        "-y",
        "-i",
        str(wav),
        "-c:a",
        "libvorbis",
        "-q:a",
        "5",
        str(ogg),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0 or not ogg.exists():
        raise RuntimeError(proc.stderr[-400:] if proc.stderr else "ffmpeg failed")
    return ogg


def write_catalog(ogg_files: list[Path]) -> None:
    pools: dict[str, list[str]] = {}
    for ogg in sorted(ogg_files):
        rel = ogg.relative_to(SFX).as_posix()
        # family/size/file.ogg
        parts = rel.split("/")
        if len(parts) < 3:
            continue
        key = f"{parts[0]}/{parts[1]}"
        res = f"res://assets/audio/weapon_sfx/{rel}"
        pools.setdefault(key, []).append(res)
    lines = [
        "extends RefCounted",
        "class_name WeaponSfxCatalog",
        "## Baked weapon SFX paths (COMBAT §8.1). Regenerated when wav/ogg set changes.",
        "",
        "static func pools() -> Dictionary:",
        "\tvar d: Dictionary = {}",
    ]
    for key in sorted(pools.keys()):
        lines.append(f'\td["{key}"] = PackedStringArray([')
        for p in pools[key]:
            lines.append(f'\t\t"{p}",')
        lines.append("\t])")
    lines.append("\treturn d")
    lines.append("")
    CATALOG.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    wavs = sorted(SFX.rglob("*.wav"))
    if not wavs:
        print("no wav under", SFX)
        sys.exit(1)
    oggs: list[Path] = []
    ok, fail = 0, 0
    for wav in wavs:
        try:
            ogg = convert_one(wav)
            oggs.append(ogg)
            ok += 1
            print(f"[ogg] {ogg.relative_to(SFX)}")
        except Exception as e:
            fail += 1
            print(f"[FAIL] {wav.relative_to(SFX)}: {e}")
    write_catalog(oggs)
    print(f"done ok={ok} fail={fail} catalog={CATALOG}")


if __name__ == "__main__":
    main()
