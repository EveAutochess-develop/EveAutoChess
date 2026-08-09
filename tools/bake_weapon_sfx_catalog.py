# -*- coding: utf-8 -*-
"""Refresh WeaponSfxCatalog using Array[String] (not PackedStringArray).

PackedStringArray across exported PCK + TypedVariant.as_array has caused
runtime pools_n=0 → silent fire SFX on install.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
SFX = ROOT / "godot_project" / "assets" / "audio" / "weapon_sfx"
CATALOG = ROOT / "godot_project" / "scripts" / "audio" / "weapon_sfx_catalog.gd"


def main() -> None:
    pools: dict[str, list[str]] = {}
    for ogg in sorted(SFX.rglob("*.ogg")):
        rel = ogg.relative_to(SFX).as_posix()
        parts = rel.split("/")
        if len(parts) < 3:
            continue
        key = f"{parts[0]}/{parts[1]}"
        pools.setdefault(key, []).append(f"res://assets/audio/weapon_sfx/{rel}")
    if not pools:
        print("no ogg under", SFX)
        sys.exit(1)
    lines = [
        "extends RefCounted",
        "class_name WeaponSfxCatalog",
        "## Baked weapon SFX paths (COMBAT §8.1). Use Array (not PackedStringArray) for PCK-safe TypedVariant.",
        "",
        "static func pools() -> Dictionary:",
        "\tvar d: Dictionary = {}",
    ]
    for key in sorted(pools.keys()):
        lines.append(f'\td["{key}"] = [')
        for p in pools[key]:
            lines.append(f'\t\t"{p}",')
        lines.append("\t]")
    lines.append("\treturn d")
    lines.append("")
    CATALOG.write_text("\n".join(lines) + "\n", encoding="utf-8")
    n = sum(len(v) for v in pools.values())
    print(f"catalog keys={len(pools)} files={n} -> {CATALOG}")


if __name__ == "__main__":
    main()
