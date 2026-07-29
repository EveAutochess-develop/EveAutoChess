# -*- coding: utf-8 -*-
"""Decode all KTX under known Echoes asset roots into a mirrored PNG tree."""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import texture2ddecoder
from PIL import Image

PVR = Path(
    r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\bin\PVRTexToolCLI.exe"
)
OUT_ROOT = Path(r"H:\game_dev\eveautochess-design\docs\_review\ktx_png_mirror")

# (label, source_root) → OUT_ROOT / label / <relative path>.png
SOURCES: list[tuple[str, Path]] = [
    (
        "equipment_textures",
        Path(r"H:\eve手游\history\1.9.62_unpacked\asset_library\equipment_textures"),
    ),
    (
        "items_icons",
        Path(r"H:\eve手游\history\asset_library\items\icons"),
    ),
    (
        "entities_ships",
        Path(r"H:\eve手游\history\asset_library\entities\ships"),
    ),
]

ASTC_BLOCK = {
    0x93B0: (4, 4), 0x93B1: (5, 5), 0x93B2: (5, 6), 0x93B3: (6, 5), 0x93B4: (6, 6),
    0x93B5: (8, 5), 0x93B6: (8, 6), 0x93B7: (8, 8), 0x93B8: (10, 5), 0x93B9: (10, 6),
    0x93BA: (10, 8), 0x93BB: (10, 10), 0x93BC: (12, 10), 0x93BD: (12, 12),
    0x93D0: (4, 4), 0x93D1: (5, 5), 0x93D2: (5, 6), 0x93D3: (6, 5), 0x93D4: (6, 6),
    0x93D5: (8, 5), 0x93D6: (8, 6), 0x93D7: (8, 8), 0x93D8: (10, 5), 0x93D9: (10, 6),
    0x93DA: (10, 8), 0x93DB: (10, 10), 0x93DC: (12, 10), 0x93DD: (12, 12),
}

WORKERS = max(2, min(8, (os.cpu_count() or 4)))


def decode_ktx_bytes(data: bytes) -> Image.Image | None:
    if data[:7] != b"\xabKTX 11":
        return None
    vals = struct.unpack_from("<12I", data, 16)
    internal, w, h, kv = vals[3], vals[5], vals[6], vals[11]
    bw, bh = ASTC_BLOCK.get(internal, (0, 0))
    if bw == 0:
        return None
    off = 64 + kv
    if off + 4 > len(data):
        return None
    sz = struct.unpack_from("<I", data, off)[0]
    off += 4
    raw = data[off : off + sz]
    rgba = texture2ddecoder.decode_astc(raw, w, h, bw, bh)
    return Image.frombytes("RGBA", (w, h), rgba, "raw", "BGRA")


def decode_via_pvr(src: Path) -> Image.Image | None:
    if not PVR.is_file():
        return None
    with tempfile.TemporaryDirectory(prefix="pvr_") as td:
        dst = Path(td) / "out.png"
        try:
            subprocess.run(
                [str(PVR), "-i", str(src), "-noout", "-d", str(dst)],
                capture_output=True,
                text=True,
                timeout=120,
            )
        except Exception:
            return None
        if dst.is_file():
            return Image.open(dst).convert("RGBA")
    return None


def convert_one(src_s: str, dst_s: str) -> tuple[str, str, str]:
    """Return (status, src, detail). status: ok|skip|fail."""
    src = Path(src_s)
    dst = Path(dst_s)
    try:
        if dst.is_file() and dst.stat().st_size > 64:
            return ("skip", src_s, "exists")
        data = src.read_bytes()
        im = decode_ktx_bytes(data)
        how = "astc"
        if im is None:
            im = decode_via_pvr(src)
            how = "pvr"
        if im is None:
            return ("fail", src_s, "decode")
        dst.parent.mkdir(parents=True, exist_ok=True)
        # large albedo: keep full; icons already small
        im.save(dst, "PNG", optimize=False)
        return ("ok", src_s, how)
    except Exception as e:
        return ("fail", src_s, repr(e))


def collect_jobs() -> list[tuple[str, str]]:
    jobs: list[tuple[str, str]] = []
    for label, root in SOURCES:
        if not root.is_dir():
            print(f"[warn] missing {root}")
            continue
        for src in root.rglob("*.ktx"):
            rel = src.relative_to(root)
            dst = OUT_ROOT / label / rel.with_suffix(".png")
            jobs.append((str(src), str(dst)))
    return jobs


def main() -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    jobs = collect_jobs()
    print(f"jobs={len(jobs)} workers={WORKERS} out={OUT_ROOT}")
    t0 = time.time()
    ok = skip = fail = 0
    fails: list[dict] = []
    # ProcessPool needs top-level convert_one
    with ProcessPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(convert_one, s, d) for s, d in jobs]
        done = 0
        for fut in as_completed(futs):
            status, src, detail = fut.result()
            done += 1
            if status == "ok":
                ok += 1
            elif status == "skip":
                skip += 1
            else:
                fail += 1
                fails.append({"src": src, "detail": detail})
            if done % 200 == 0 or done == len(jobs):
                elapsed = time.time() - t0
                rate = done / max(elapsed, 1e-6)
                print(
                    f"[{done}/{len(jobs)}] ok={ok} skip={skip} fail={fail} "
                    f"{rate:.1f}/s elapsed={elapsed:.0f}s",
                    flush=True,
                )

    report = {
        "out_root": str(OUT_ROOT),
        "total": len(jobs),
        "ok": ok,
        "skip": skip,
        "fail": fail,
        "elapsed_sec": round(time.time() - t0, 1),
        "sources": [{"label": a, "root": str(b)} for a, b in SOURCES],
        "fails": fails[:500],
        "fails_truncated": len(fails) > 500,
    }
    (OUT_ROOT / "_convert_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    readme = [
        "# KTX → PNG 镜像目录",
        "",
        f"输出根：`{OUT_ROOT}`",
        "",
        "结构与源目录对应：",
        "",
        "| 子目录 | 源 |",
        "|--------|----|",
    ]
    for label, root in SOURCES:
        readme.append(f"| `{label}/` | `{root}` |")
    readme += [
        "",
        f"转换：ok={ok} skip={skip} fail={fail} / total={len(jobs)}",
        "",
        "失败列表见 `_convert_report.json`。",
        "",
    ]
    (OUT_ROOT / "README.md").write_text("\n".join(readme), encoding="utf-8")
    print(f"DONE ok={ok} skip={skip} fail={fail} -> {OUT_ROOT}")


if __name__ == "__main__":
    main()
