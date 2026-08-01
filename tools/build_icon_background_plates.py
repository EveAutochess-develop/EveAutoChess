# -*- coding: utf-8 -*-
"""Recover exact TQ icon background plates by stacking same-backdrop icons.

Fitting the 32x32 blur cube only approximates the backdrop. But TQ renders all
ship icons of a race against a small set of fixed backdrops, and icons sharing
one are pixel-identical outside the hull. So: cluster a race's icons by their
border ring, then median-stack each cluster - every hull sits somewhere
different, so the median is the bare background at full resolution.

Small hulls are what make this work: a frigate covers little of the frame, so
its cluster's median is background almost everywhere.

`angel` ships share the minmatar cube (angel.black -> ship_minmatar_cube), so
they are pooled with minmatar.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools" / "eve_pc")]
from eve_pc.resfile_index import INDEX_PATH, fetch_resfile  # noqa: E402

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm"
    r"\titan_assets_confirm\iconbackground_for_cutout\_plates"
)

# races pooled per cube; angel rides on the minmatar cube
POOLS = {
    "minmatar": ["minmatar", "angel"],
    "amarr": ["amarr", "sansha"],
    "caldari": ["caldari", "guristas", "mordu"],
    "gallente": ["gallente", "serpentis"],
}
SIZE = 512
RING = 10
RING_TOL = 4.0     # max per-channel ring diff for "same backdrop"
MIN_CLUSTER = 4

ICON_RE = re.compile(
    r"^res:/dx9/model/ship/([a-z]+)/([a-z0-9_]+)/([a-z0-9_]+)/icons/(\d+)_512\.jpg$"
)


def ring_mask() -> np.ndarray:
    m = np.zeros((SIZE, SIZE), bool)
    m[:RING] = m[-RING:] = True
    m[:, :RING] = m[:, -RING:] = True
    return m


def index_icons() -> list[tuple[str, str, str, str]]:
    rows = []
    for line in Path(INDEX_PATH).read_text(encoding="utf-8", errors="ignore").splitlines():
        res = line.split(",")[0]
        m = ICON_RE.match(res)
        if m:
            rows.append((m.group(1), m.group(2), m.group(4), res))
    return rows


def load_pool(races: list[str], rows) -> tuple[list[tuple[str, str, str]], np.ndarray]:
    sel = [r for r in rows if r[0] in races]
    with ThreadPoolExecutor(12) as ex:
        paths = list(ex.map(fetch_resfile, [r[3] for r in sel]))
    keys, imgs = [], []
    for (race, cls, tid, _), p in zip(sel, paths):
        if not p:
            continue
        a = np.asarray(Image.open(p).convert("RGB"), dtype=np.uint8)
        if a.shape[:2] != (SIZE, SIZE):
            continue
        keys.append((race, cls, tid))
        imgs.append(a)
    return keys, np.stack(imgs) if imgs else np.zeros((0, SIZE, SIZE, 3), np.uint8)


def cluster(sigs: np.ndarray) -> list[list[int]]:
    """Greedy grouping of icons whose border rings agree."""
    left = list(range(len(sigs)))
    out = []
    while left:
        i = left[0]
        members = [j for j in left if np.abs(sigs[j] - sigs[i]).max() <= RING_TOL]
        out.append(members)
        drop = set(members)
        left = [j for j in left if j not in drop]
    out.sort(key=len, reverse=True)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = index_icons()
    report = {}
    for cube, races in POOLS.items():
        keys, imgs = load_pool(races, rows)
        if not len(imgs):
            print(f"[{cube}] no icons")
            continue
        rm = ring_mask()
        sigs = imgs[:, rm].astype(np.float32)
        groups = cluster(sigs)
        print(f"\n[{cube}] icons={len(keys)} clusters={len(groups)}")

        info = []
        for gi, g in enumerate(groups):
            classes = Counter(keys[j][1] for j in g)
            plate_path = None
            if len(g) >= MIN_CLUSTER:
                plate = np.median(imgs[g].astype(np.float32), axis=0)
                plate_path = OUT / f"{cube}_plate{gi}.png"
                Image.fromarray(plate.clip(0, 255).astype(np.uint8)).save(plate_path)
                # how bare is it? spread of the stack away from the frame centre
                spread = float(np.median(np.abs(imgs[g].astype(np.float32) - plate)))
            else:
                spread = float("nan")
            info.append({
                "cluster": gi,
                "n": len(g),
                "classes": dict(classes),
                "type_ids": [keys[j][2] for j in g],
                "plate": plate_path.name if plate_path else None,
                "median_abs_dev": None if np.isnan(spread) else round(spread, 2),
            })
            tag = "*" if len(g) >= MIN_CLUSTER else " "
            print(f"  {tag} cluster{gi:<3d} n={len(g):3d} {dict(classes)}")
        report[cube] = info

    (OUT / "plates.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("\nwrote", OUT / "plates.json")


if __name__ == "__main__":
    main()
