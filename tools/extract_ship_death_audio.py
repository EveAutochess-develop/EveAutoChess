# -*- coding: utf-8 -*-
"""Extract TQ ship-death / wreck-fire audio into Echoes ship-death confirm pack.

Primary bank: Effects.bnk (NPCdeath_* / npc-death-* / shipSFX* / poddeath*).
Also pulls wreck spark loops from ShipAmbience and fire_wreck from Structures.
"""
from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

OUT_GODOT = ROOT / "godot_project" / "assets" / "vfx" / "ship_death_echoes" / "audio"
OUT_REVIEW = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\titan_kill_preview\echoes_ship_death\audio"
)

# Prefer capital/XL-ish + large + a few medium/small for reference.
WANT_PATTERNS = (
    re.compile(r"npcdeath_l", re.I),
    re.compile(r"npcdeath_m", re.I),
    re.compile(r"npc-death-", re.I),
    re.compile(r"shipsfx", re.I),
    re.compile(r"poddeath|pod-explode", re.I),
    re.compile(r"individual_explosion", re.I),
    re.compile(r"asteroid_death_explosion", re.I),
    re.compile(r"fire_wreck", re.I),
    re.compile(r"wreck_spark", re.I),
)

BANK_CANDIDATES = {
    "Effects": [
        "res:/audio/essential_media/effects.bnk",
        "res:/audio/effects.bnk",
        "res:/audio/ingame/effects.bnk",
    ],
    "ShipAmbience": [
        "res:/audio/essential_media/shipambience.bnk",
        "res:/audio/essential_media/ship_ambience.bnk",
        "res:/audio/shipambience.bnk",
    ],
    "Structures": [
        "res:/audio/essential_media/structures.bnk",
        "res:/audio/structures.bnk",
    ],
}


def sanitize(name: str) -> str:
    name = name.replace("\\", "/")
    name = Path(name).stem
    name = re.sub(r"[^\w\-]+", "_", name, flags=re.UNICODE)
    name = re.sub(r"_+", "_", name).strip("_")
    return name[:120] or "sfx"


def load_didx(raw: bytes) -> dict[int, tuple[int, int]]:
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


def resolve_bank_path(short: str, bank_obj: dict) -> Path:
    path = str(bank_obj.get("Path") or "")
    cands = []
    if path:
        # Path may be just Effects.bnk
        name = Path(path.replace("\\", "/")).name
        cands.extend(
            [
                f"res:/audio/essential_media/{name}",
                f"res:/audio/{name}",
                f"res:/audio/ingame/{name}",
            ]
        )
    cands.extend(BANK_CANDIDATES.get(short, []))
    last = None
    for res in cands:
        try:
            return Path(fetch_resfile(res))
        except Exception as e:
            last = e
    raise RuntimeError(f"cannot resolve bank {short}: {last}")


def wanted(short: str) -> bool:
    return any(p.search(short) for p in WANT_PATTERNS)


def main() -> None:
    OUT_GODOT.mkdir(parents=True, exist_ok=True)
    OUT_REVIEW.mkdir(parents=True, exist_ok=True)
    info = json.loads(Path(fetch_resfile("res:/audio/soundbanksinfo.json")).read_text(encoding="utf-8"))
    banks = {b["ShortName"]: b for b in info["SoundBanksInfo"]["SoundBanks"]}

    report = []
    for bank_name in ("Effects", "ShipAmbience", "Structures"):
        bank = banks.get(bank_name)
        if not bank:
            print("MISS bank meta", bank_name)
            continue
        media = [m for m in (bank.get("Media") or []) if wanted(str(m.get("ShortName") or ""))]
        print(f"{bank_name}: matched media {len(media)}")
        if not media:
            continue
        bnk_path = resolve_bank_path(bank_name, bank)
        print(f"  bnk {bnk_path} size={bnk_path.stat().st_size}")
        raw = bnk_path.read_bytes()
        didx = load_didx(raw)
        data0 = data_payload_start(raw)
        bank_out_g = OUT_GODOT / bank_name.lower()
        bank_out_r = OUT_REVIEW / bank_name.lower()
        bank_out_g.mkdir(parents=True, exist_ok=True)
        bank_out_r.mkdir(parents=True, exist_ok=True)
        for m in media:
            mid = int(m["Id"])
            sn = str(m.get("ShortName") or mid)
            if mid not in didx:
                report.append({"bank": bank_name, "id": mid, "shortName": sn, "status": "missing_in_bnk"})
                continue
            off, sz = didx[mid]
            chunk = raw[data0 + off : data0 + off + sz]
            ext = ".wav" if chunk[:4] == b"RIFF" else ".wem"
            fname = f"{mid}_{sanitize(sn)}{ext}"
            (bank_out_g / fname).write_bytes(chunk)
            (bank_out_r / fname).write_bytes(chunk)
            report.append(
                {
                    "bank": bank_name,
                    "id": mid,
                    "shortName": sn,
                    "file": f"{bank_name.lower()}/{fname}",
                    "bytes": len(chunk),
                    "status": "ok",
                    "format": ext[1:],
                }
            )
            print("  wrote", fname, len(chunk))

    (OUT_GODOT / "EXTRACT_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (OUT_REVIEW / "EXTRACT_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    ok = sum(1 for r in report if r.get("status") == "ok")
    lines = [
        "# 舰船击毁 / 残骸火声音效",
        "",
        "来源：TQ Wwise `Effects.bnk`（主）+ `ShipAmbience.bnk`（残骸火星）+ `Structures.bnk`（fire_wreck）。",
        "用途：配合 Echoes `fx_ship_death_xl` 通用击毁火光预览；泰坦档优先 `NPCdeath_L*` / `shipSFX*`。",
        "",
        f"- 写出成功：{ok}/{len(report)}",
        "",
        "| bank | shortName | file | bytes |",
        "|---|---|---|---|",
    ]
    for r in report:
        if r.get("status") != "ok":
            continue
        lines.append(
            f"| {r['bank']} | `{r['shortName']}` | `{r['file']}` | {r['bytes']} |"
        )
    (OUT_REVIEW / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"done ok={ok}/{len(report)}")


if __name__ == "__main__":
    main()
