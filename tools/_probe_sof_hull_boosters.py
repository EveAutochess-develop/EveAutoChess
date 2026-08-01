"""Heuristic extract of hull booster transforms from SOF data.black.

Black files are typed object graphs. We don't fully decode them yet; this scan
finds EveSOFDataHullBooster / HullBoosterItem neighborhoods and nearby float
triplets that look like positions (reasonable ship-local scales).
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

OUT = Path(__file__).resolve().parent / "_extracted" / "sof_booster_probe.json"


def _ascii_runs(raw: bytes, i0: int, i1: int) -> list[str]:
    out: list[str] = []
    cur = bytearray()
    for b in raw[i0:i1]:
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= 4:
                out.append(cur.decode("ascii", errors="ignore"))
            cur.clear()
    if len(cur) >= 4:
        out.append(cur.decode("ascii", errors="ignore"))
    return out


def _triplet_candidates(raw: bytes, center: int, radius: int = 1024) -> list[dict]:
    """Aligned float triples near center with ship-ish magnitude."""
    lo = max(0, (center - radius + 3) & ~3)
    hi = min(len(raw) - 12, center + radius)
    out: list[dict] = []
    for o in range(lo, hi, 4):
        x, y, z = struct.unpack_from("<fff", raw, o)
        if not all(math.isfinite(v) for v in (x, y, z)):
            continue
        mag = math.sqrt(x * x + y * y + z * z)
        if mag < 0.05 or mag > 800.0:
            continue
        # Skip near-axis-aligned unit vectors that look like basis rows
        if abs(mag - 1.0) < 0.02 and max(abs(x), abs(y), abs(z)) > 0.9:
            continue
        out.append({"offset": o, "pos": [round(x, 4), round(y, 4), round(z, 4)], "mag": round(mag, 4)})
    return out


def main() -> None:
    p = Path(fetch_resfile("res:/dx9/model/spaceobjectfactory/data.black"))
    raw = p.read_bytes()
    marker = b"EveSOFDataHullBooster"
    item_m = b"EveSOFDataHullBoosterItem"
    hulls_of_interest = [
        b"af1_t1",
        b"gf4_t1",
        b"cb1_t1",
        b"oreba_t1",
        b"oreb1_t1",
        b"orecs1_t1",
        b"adn1_t1",
        b"gdn1_t1",
    ]

    # Map hull name occurrences → nearby booster sections
    report: dict = {"source": str(p), "size": len(raw), "hulls": {}}

    # Find all HullBooster type markers
    booster_sites: list[int] = []
    start = 0
    while True:
        i = raw.find(marker, start)
        if i < 0:
            break
        booster_sites.append(i)
        start = i + 1
    item_sites: list[int] = []
    start = 0
    while True:
        i = raw.find(item_m, start)
        if i < 0:
            break
        item_sites.append(i)
        start = i + 1
    report["hull_booster_type_sites"] = len(booster_sites)
    report["hull_booster_item_sites"] = len(item_sites)

    # For each hull string, gather nearby type names + float triples in ±8KB window
    for hull in hulls_of_interest:
        sites = []
        start = 0
        while True:
            i = raw.find(hull, start)
            if i < 0:
                break
            sites.append(i)
            start = i + 1
        entries = []
        for i in sites[:12]:
            win0, win1 = max(0, i - 4096), min(len(raw), i + 8192)
            strings = _ascii_runs(raw, win0, win1)
            interesting = [
                s
                for s in strings
                if any(
                    k in s.lower()
                    for k in (
                        "booster",
                        "exhaust",
                        "locator",
                        "transform",
                        "trail",
                        "glow",
                        hull.decode(),
                    )
                )
            ]
            # Prefer windows that mention booster
            has_boost = any("booster" in s.lower() for s in interesting)
            floats = []
            trips = _triplet_candidates(raw, i, 1024)[:40]
            entries.append(
                {
                    "offset": i,
                    "has_booster_nearby": has_boost,
                    "interesting_strings": interesting[:40],
                    "float_triplets": trips[:20],
                }
            )
        report["hulls"][hull.decode()] = {"occurrences": len(sites), "samples": entries}

    # Global: dump strings immediately after first few HullBoosterItem markers
    item_samples = []
    for i in item_sites[:8]:
        item_samples.append(
            {
                "offset": i,
                "strings": _ascii_runs(raw, i, i + 400)[:30],
                "triplets": _triplet_candidates(raw, i + 64, 256)[:15],
            }
        )
    report["booster_item_samples"] = item_samples

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"wrote {OUT} booster_type={len(booster_sites)} items={len(item_sites)}")
    for h, info in report["hulls"].items():
        boosty = sum(1 for s in info["samples"] if s["has_booster_nearby"])
        print(f"  {h}: occ={info['occurrences']} booster_near={boosty}/{len(info['samples'])}")


if __name__ == "__main__":
    main()
