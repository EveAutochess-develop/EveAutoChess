"""Probe TQ SOF data.black for booster/exhaust/locator strings."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eve_pc.resfile_index import fetch_resfile  # noqa: E402


def main() -> None:
    p = Path(fetch_resfile("res:/dx9/model/spaceobjectfactory/data.black"))
    raw = p.read_bytes()
    print("size", len(raw), "magic", raw[:16], "head", repr(raw[:64]))
    needles = [
        b"area_booster",
        b"booster",
        b"Booster",
        b"locator_booster",
        b"exhaust",
        b"LocatorSet",
        b"locatorSets",
        b"locator_sets",
        b"EveBooster",
        b"boosterItems",
        b"glowColor",
        b"warpGlowColor",
    ]
    for n in needles:
        c = raw.count(n)
        print(f"count {n!r} = {c}")
        start = 0
        shown = 0
        while shown < 2 and c:
            i = raw.find(n, start)
            if i < 0:
                break
            chunk = raw[max(0, i - 100) : i + 160]
            s = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
            print(f"  @{i}: {s}")
            start = i + 1
            shown += 1

    # Sample hull names we care about near booster context
    for hull in [b"af1_t1", b"oreba_t1", b"orei1_t1", b"orecs1_t1", b"cb1_t1", b"gf4_t1"]:
        print(f"\nhull {hull!r} count={raw.count(hull)}")


if __name__ == "__main__":
    main()
