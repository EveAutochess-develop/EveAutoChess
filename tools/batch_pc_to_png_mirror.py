# -*- coding: utf-8 -*-
"""Mirror all EVE TQ client images into a browsable PNG/JPG tree (like ktx_png_mirror).

Sources: H:\\EVE\\tq\\resfileindex.txt + ResFiles (CDN fetch on miss).
Output:  H:\\game_dev\\eveautochess-design\\docs\\_review\\pc_png_mirror\\
  - .dds / .tga → decoded .png (full resolution)
  - .png / .jpg / .jpeg → copied with logical res:/ path
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
if str(TOOLS / "eve_pc") not in sys.path:
    sys.path.insert(0, str(TOOLS / "eve_pc"))

from eve_pc.dds_decode import decode_dds  # noqa: E402

EVE_ROOT = Path(r"H:\EVE")
INDEX_PATH = EVE_ROOT / "tq" / "resfileindex.txt"
RESFILES_ROOT = EVE_ROOT / "ResFiles"
CDN_BASE = "https://resources.eveonline.com"
USER_AGENT = "EVE Online/tx_22.02"

OUT_ROOT = Path(r"H:\game_dev\eveautochess-design\docs\_review\pc_png_mirror")

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".dds", ".tga", ".bmp", ".webp"}
# Threads avoid BrokenProcessPool; keep low to limit peak RAM on large BC7 DDS.
WORKERS = 4


def _parse_index() -> list[tuple[str, str, int]]:
    """Return [(res_path, hash_rel, size)]."""
    rows: list[tuple[str, str, int]] = []
    for line in INDEX_PATH.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line or "," not in line:
            continue
        parts = line.split(",")
        if len(parts) < 3:
            continue
        respath = parts[0].strip()
        ext = Path(respath).suffix.lower()
        if ext not in IMAGE_EXTS:
            continue
        rel = parts[1].strip()
        try:
            size = int(parts[3]) if len(parts) > 3 else 0
        except ValueError:
            size = 0
        rows.append((respath, rel, size))
    return rows


def _logical_rel(res_path: str) -> Path:
    """res:/dx9/model/foo.dds → dx9/model/foo.png (dds/tga→png; else keep ext)."""
    p = res_path.strip()
    if p.lower().startswith("res:/"):
        p = p[5:]
    p = p.lstrip("/").replace("\\", "/")
    path = Path(p)
    if path.suffix.lower() in {".dds", ".tga", ".bmp"}:
        return path.with_suffix(".png")
    return path


def _ensure_local(rel: str) -> Path | None:
    local = RESFILES_ROOT / Path(rel)
    if local.is_file() and local.stat().st_size > 16:
        return local
    url = f"{CDN_BASE}/{rel}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = resp.read()
    except Exception:
        return None
    if len(data) < 16:
        return None
    local.parent.mkdir(parents=True, exist_ok=True)
    local.write_bytes(data)
    return local


def convert_one(res_path: str, rel: str, dst_s: str) -> tuple[str, str, str]:
    """Return (status, res_path, detail). status: ok|skip|fail."""
    dst = Path(dst_s)
    try:
        if dst.is_file() and dst.stat().st_size > 32:
            return ("skip", res_path, "exists")
        src = _ensure_local(rel)
        if src is None:
            return ("fail", res_path, "fetch")
        ext = Path(res_path).suffix.lower()
        dst.parent.mkdir(parents=True, exist_ok=True)
        if ext in {".png", ".jpg", ".jpeg", ".webp"}:
            shutil.copyfile(src, dst)
            return ("ok", res_path, "copy")
        if ext == ".dds":
            im = decode_dds(src)
            if im is None:
                return ("fail", res_path, "dds_decode")
            im.save(dst, "PNG", optimize=False)
            return ("ok", res_path, "dds")
        # tga / bmp / fallback
        from PIL import Image

        im = Image.open(src).convert("RGBA")
        im.save(dst, "PNG", optimize=False)
        return ("ok", res_path, "pil")
    except Exception as e:
        return ("fail", res_path, repr(e))


def main() -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    rows = _parse_index()
    jobs: list[tuple[str, str, str]] = []
    for res_path, rel, _size in rows:
        dst = OUT_ROOT / _logical_rel(res_path)
        jobs.append((res_path, rel, str(dst)))
    print(f"jobs={len(jobs)} workers={WORKERS} out={OUT_ROOT}", flush=True)
    t0 = time.time()
    ok = skip = fail = 0
    fails: list[dict] = []
    done = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(convert_one, r, rel, d) for r, rel, d in jobs]
        for fut in as_completed(futs):
            try:
                status, src, detail = fut.result()
            except Exception as e:
                status, src, detail = "fail", "?", repr(e)
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
        "index": str(INDEX_PATH),
        "total": len(jobs),
        "ok": ok,
        "skip": skip,
        "fail": fail,
        "elapsed_sec": round(time.time() - t0, 1),
        "fails": fails[:1000],
        "fails_truncated": len(fails) > 1000,
    }
    (OUT_ROOT / "_convert_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    readme = [
        "# 端游 TQ 图片镜像目录",
        "",
        f"输出根：`{OUT_ROOT}`",
        "",
        "对照手游 `ktx_png_mirror`：按 `resfileindex.txt` 逻辑路径展开全部图片资源。",
        "",
        "| 规则 | 说明 |",
        "|------|------|",
        "| 源索引 | `H:\\EVE\\tq\\resfileindex.txt` |",
        "| 源缓存 | `H:\\EVE\\ResFiles`（缺则 CDN `resources.eveonline.com`） |",
        "| `.dds` / `.tga` | 解码为 `.png`（全分辨率） |",
        "| `.png` / `.jpg` | 按逻辑路径原样拷贝 |",
        "",
        f"转换：ok={ok} skip={skip} fail={fail} / total={len(jobs)}",
        "",
        "失败列表见 `_convert_report.json`。",
        "",
    ]
    (OUT_ROOT / "README.md").write_text("\n".join(readme), encoding="utf-8")
    print(f"DONE ok={ok} skip={skip} fail={fail} -> {OUT_ROOT}", flush=True)


if __name__ == "__main__":
    main()
