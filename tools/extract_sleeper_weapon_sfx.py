# -*- coding: utf-8 -*-
"""Extract TQ Turrets weapon SFX from turrets.bnk into sleeper confirm folder.

Media is embedded in the BNK (DIDX/DATA). Chunks are RIFF/WAVE — save as .wav.
"""
from __future__ import annotations

import json
import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

OUT = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\sleeper_assets_confirm\weapon_sfx"
)


def sanitize(name: str) -> str:
    name = name.replace("\\", "/")
    name = Path(name).stem
    name = re.sub(r"[^\w\-]+", "_", name, flags=re.UNICODE)
    name = re.sub(r"_+", "_", name).strip("_")
    return name[:100] or "sfx"


def classify(short: str) -> str:
    s = short.replace("\\", "/").lower()
    if "missile" in s or "rocket" in s or "torpedo" in s or "cruise" in s:
        return "missile"
    if "hybrid" in s or "blaster" in s or "rail" in s:
        return "hybrid"
    if "laser" in s or "pulse" in s or "beam" in s or "energy" in s:
        return "laser"
    if "projectile" in s or "artillery" in s or "autocannon" in s or "cannon" in s:
        return "projectile"
    if "mining" in s:
        return "mining"
    return "other"


def size_tag(short: str) -> str:
    s = short.lower()
    for k in ("small", "medium", "large", "xl", "extra", "capital"):
        if k in s:
            return "xlarge" if k in ("xl", "extra") else k
    return "unk"


def score_clip(short: str) -> int:
    low = short.lower()
    score = 0
    if "close" in low:
        score += 3
    if any(k in low for k in ("shot", "fire", "outburst")):
        score += 2
    if "body" in low:
        score += 1
    if "loop" in low or "hum" in low or "idle" in low:
        score -= 3
    if "mech" in low and "body" not in low:
        score -= 1
    if "impact" in low:
        score -= 1
    return score


def load_didx(raw: bytes) -> dict[int, tuple[int, int]]:
    """id -> (offset_in_DATA, size)."""
    pos = raw.find(b"DIDX")
    if pos < 0:
        raise RuntimeError("no DIDX")
    size = struct.unpack_from("<I", raw, pos + 4)[0]
    data = raw[pos + 8 : pos + 8 + size]
    out = {}
    for i in range(0, size, 12):
        mid, off, sz = struct.unpack_from("<III", data, i)
        out[mid] = (off, sz)
    return out


def data_payload_start(raw: bytes) -> int:
    pos = raw.find(b"DATA")
    if pos < 0:
        raise RuntimeError("no DATA")
    return pos + 8


def pick(media: list[dict], per_bucket: int = 4) -> list[dict]:
    buckets: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for m in media:
        sn = m.get("ShortName") or ""
        fam = classify(sn)
        if fam in ("other", "mining"):
            continue
        item = dict(m)
        item["_fam"] = fam
        item["_size"] = size_tag(sn)
        item["_score"] = score_clip(sn)
        buckets[(fam, item["_size"])].append(item)
    picked = []
    for _, items in sorted(buckets.items()):
        items.sort(key=lambda x: (-x["_score"], str(x.get("Id"))))
        picked.extend(items[:per_bucket])
    return picked


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # clean previous empty dirs noise
    for p in OUT.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".wem", ".ogg", ".wav", ".bnk", ".md", ".json"}:
            pass

    info = Path(fetch_resfile("res:/audio/soundbanksinfo.json"))
    banks = {
        b["ShortName"]: b
        for b in json.loads(info.read_text(encoding="utf-8"))["SoundBanksInfo"]["SoundBanks"]
    }
    turret = banks["Turrets"]
    media = turret.get("Media") or []
    print(f"Turrets media={len(media)}")

    bnk_path = Path(fetch_resfile("res:/audio/essential_media/turrets.bnk"))
    print(f"loading bnk {bnk_path.stat().st_size} bytes ...")
    raw = bnk_path.read_bytes()
    didx = load_didx(raw)
    data0 = data_payload_start(raw)
    print(f"didx={len(didx)}")

    picked = pick(media, per_bucket=4)
    # also include a few missile-named from full media if any missed
    print(f"picked={len(picked)}")

    results = []
    for m in picked:
        mid = int(m["Id"])
        sn = m.get("ShortName") or str(mid)
        fam = m["_fam"]
        size = m["_size"]
        nice = sanitize(sn)
        if mid not in didx:
            results.append(
                {
                    "id": mid,
                    "family": fam,
                    "size": size,
                    "shortName": sn,
                    "status": "missing_in_bnk",
                }
            )
            continue
        off, sz = didx[mid]
        chunk = raw[data0 + off : data0 + off + sz]
        ext = ".wav" if chunk[:4] == b"RIFF" else ".wem"
        rel = Path(fam) / size / f"{mid}_{nice}{ext}"
        dst = OUT / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(chunk)
        results.append(
            {
                "id": mid,
                "family": fam,
                "size": size,
                "shortName": sn,
                "file": str(rel).replace("\\", "/"),
                "bytes": sz,
                "status": "ok",
                "riff": chunk[:4] == b"RIFF",
            }
        )
        print("ok", fam, size, mid, nice[:50], f"{sz}b")

    # full bank copy optional — too large (390MB); skip, note in README
    report = {
        "source": "res:/audio/essential_media/turrets.bnk",
        "soundbanksinfo": "res:/audio/soundbanksinfo.json",
        "turrets_media_total": len(media),
        "didx_entries": len(didx),
        "family_counts_all": dict(Counter(classify(m.get("ShortName") or "") for m in media)),
        "extracted": results,
        "note_sleeper": "No sleeper-named weapon clips in Wwise banks; Sleepers use generic turret/missile SFX.",
    }
    (OUT / "EXTRACT_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# 端游武器音效（确认）",
        "",
        "> 来源：TQ `res:/audio/essential_media/turrets.bnk` + `soundbanksinfo.json`",
        "> 冬眠者**没有**独立武器音效 bank；PVE 可复用下列通用炮台/导弹采样。",
        "",
        f"- turrets 媒体总条目：{len(media)}",
        f"- 本包抽样：{sum(1 for r in results if r['status']=='ok')} 条（各族×体型各最多 4，偏好 CLOSE / Shot / Body）",
        "- 格式：多为可直接播放的 **`.wav`**（BNK 内 RIFF）",
        "- **未**整包拷贝 `turrets.bnk`（约 390MB）；需要全量再说",
        "",
        "## 目录",
        "",
        "| 族 | 说明 |",
        "|----|------|",
        "| `laser/` | 脉冲/光束（电热向） |",
        "| `hybrid/` | 磁轨/爆破（动能热向） |",
        "| `projectile/` | 射弹/火炮 |",
        "| `missile/` | 导弹爆发/撞击 |",
        "",
        "## 清单",
        "",
        "| 族 | 体型 | 文件 |",
        "|----|------|------|",
    ]
    for r in results:
        if r["status"] != "ok":
            lines.append(f"| {r['family']} | {r['size']} | MISSING `{r.get('shortName')}` |")
        else:
            lines.append(f"| {r['family']} | {r['size']} | `{r['file']}` |")
    lines.append("")
    (OUT / "README.md").write_text("\n".join(lines), encoding="utf-8")

    # patch CONFIRM.md pointer
    confirm = OUT.parent / "CONFIRM.md"
    if confirm.is_file():
        text = confirm.read_text(encoding="utf-8")
        marker = "## 武器音效"
        block = (
            "## 武器音效\n\n"
            "端游通用炮台/导弹抽样（非冬眠者专属）：[`weapon_sfx/`](weapon_sfx/) · 见其中 `README.md`。\n"
        )
        if marker in text:
            # replace section roughly
            head, rest = text.split(marker, 1)
            # drop until next ## or end
            nxt = rest.find("\n## ")
            if nxt >= 0:
                text = head + block + rest[nxt + 1 :]
            else:
                text = head + block
        else:
            text = text.rstrip() + "\n\n" + block
        confirm.write_text(text, encoding="utf-8")

    ok = sum(1 for r in results if r["status"] == "ok")
    print(f"done ok={ok}/{len(results)} -> {OUT}")


if __name__ == "__main__":
    main()
