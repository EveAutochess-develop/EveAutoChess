#!/usr/bin/env python3
"""Print ship model AABB stats from ship_model_bbox_stats.json."""
import json
from collections import defaultdict
from pathlib import Path

STATS = Path(__file__).resolve().parents[2] / "eveautochess-design/data/_extracted/ship_model_bbox_stats.json"


def infer_group(id_: int | None) -> str:
    if id_ is None:
        return "extra_model"
    if id_ >= 1000:
        return "drone"
    if id_ <= 10:
        return "frigate"
    if id_ <= 20:
        return "destroyer"
    if id_ <= 30:
        return "cruiser"
    if id_ <= 40:
        return "battlecruiser"
    if id_ <= 50:
        return "battleship"
    return "stub_51+"


def main() -> None:
    data = json.loads(STATS.read_text(encoding="utf-8"))
    rows = [r for r in data["rows"] if "error" not in r]

    by: dict[str, list] = defaultdict(list)
    for r in rows:
        by[infer_group(r.get("id"))].append(r)

    print("=== By class (mean longest / mean volume) ===")
    order = ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship", "stub_51+", "drone", "extra_model"]
    for g in order:
        if g not in by:
            continue
        rs = by[g]
        ml = sum(r["size_long"] for r in rs) / len(rs)
        mv = sum(r["bbox_volume"] for r in rs) / len(rs)
        print(f"{g}: n={len(rs)} longest_mean={ml:.1f} vol_mean={mv:,.0f}")

    print()
    print("=== Full table ===")
    print("id\tname\tmodel_key\tshort\tmid\tlong\tvolume\tlong_axis\tratio")
    for r in sorted(rows, key=lambda x: (x.get("id") is None, x.get("id") or 9999)):
        la = r.get("model_long_axis")
        la_s = la if la is not None else "-"
        ratio = r.get("mesh_over_long_axis")
        ratio_s = ratio if ratio is not None else "-"
        name = r.get("name") or r["model_key"]
        id_s = r.get("id") if r.get("id") is not None else "--"
        print(
            f"{id_s}\t{name}\t{r['model_key']}\t{r['size_short']}\t{r['size_mid']}\t{r['size_long']}\t"
            f"{int(r['bbox_volume'])}\t{la_s}\t{ratio_s}"
        )


if __name__ == "__main__":
    main()
