# -*- coding: utf-8 -*-
"""Convert Echoes ship *_ad.ktx / *_n.ktx from asset_library into Godot §0 bundles.

Writes:
  godot_project/assets/models/ships/{model_key}/albedo.png
  godot_project/assets/models/ships/{model_key}/normal.png (optional)
Rewrites ship_textures.json to only real paths (no phantom entries).

Does NOT re-unpack NPK.
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

import texture2ddecoder
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
GODOT = ROOT / "godot_project"
SHIPS_JSON = GODOT / "data" / "ships"
DEST = GODOT / "assets" / "models" / "ships"
TEX_JSON = GODOT / "data" / "ship_textures.json"
LIB_SHIPS = Path(r"H:\eve手游\history\asset_library\entities\ships")
LIB_DRONES = Path(r"H:\eve手游\history\asset_library\entities\drones")

ASTC_BLOCK = {
    0x93B0: (4, 4),
    0x93B1: (5, 5),
    0x93B2: (5, 6),
    0x93B3: (6, 5),
    0x93B4: (6, 6),
    0x93B5: (8, 5),
    0x93B6: (8, 6),
    0x93B7: (8, 8),
    0x93B8: (10, 5),
    0x93B9: (10, 6),
    0x93BA: (10, 8),
    0x93BB: (10, 10),
    0x93BC: (12, 10),
    0x93BD: (12, 12),
    # sRGB variants (Echoes ship albedo)
    0x93D0: (4, 4),
    0x93D1: (5, 5),
    0x93D2: (5, 6),
    0x93D3: (6, 5),
    0x93D4: (6, 6),
    0x93D5: (8, 5),
    0x93D6: (8, 6),
    0x93D7: (8, 8),
    0x93D8: (10, 5),
    0x93D9: (10, 6),
    0x93DA: (10, 8),
    0x93DB: (10, 10),
    0x93DC: (12, 10),
    0x93DD: (12, 12),
}

LIGHT_DRONES = [
    "wrj_a_shiseng",
    "wrj_j_dahuangfeng",
    "wrj_g_dijingling",
    "wrj_m_mwushi",
]


def decode_ktx(path: Path) -> Image.Image | None:
    data = path.read_bytes()
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
    try:
        rgba = texture2ddecoder.decode_astc(raw, w, h, bw, bh)
    except Exception:
        return None
    return Image.frombytes("RGBA", (w, h), rgba, "raw", "BGRA")


def find_entity_dir(model_key: str, roots: list[Path]) -> Path | None:
    for root in roots:
        if not root.exists():
            continue
        exact = root / model_key
        if exact.is_dir():
            return exact
        for p in root.iterdir():
            if not p.is_dir():
                continue
            if p.name == model_key or p.name.startswith(model_key + "__"):
                return p
    return None


def convert_key(model_key: str, roots: list[Path]) -> dict:
    out_dir = DEST / model_key
    out_dir.mkdir(parents=True, exist_ok=True)
    info = {"albedo": "", "normal": ""}
    ent = find_entity_dir(model_key, roots)
    if ent is None:
        return info
    tex_dir = ent / "textures"
    if not tex_dir.is_dir():
        return info
    ad = tex_dir / f"{model_key}_ad.ktx"
    if not ad.exists():
        cands = list(tex_dir.glob("*_ad.ktx"))
        ad = cands[0] if cands else None
    if ad and ad.exists():
        im = decode_ktx(ad)
        if im is not None:
            # Cap large textures for Godot import speed
            if max(im.size) > 1024:
                im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            dst = out_dir / "albedo.png"
            im.convert("RGBA").save(dst)
            info["albedo"] = f"res://assets/models/ships/{model_key}/albedo.png"
    nrm = tex_dir / f"{model_key}_n.ktx"
    if not nrm.exists():
        cands = list(tex_dir.glob("*_n.ktx"))
        nrm = cands[0] if cands else None
    if nrm and nrm.exists():
        imn = decode_ktx(nrm)
        if imn is not None:
            if max(imn.size) > 1024:
                imn.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            dstn = out_dir / "normal.png"
            imn.convert("RGBA").save(dstn)
            info["normal"] = f"res://assets/models/ships/{model_key}/normal.png"
    return info


def main() -> None:
    ship_tex: dict[str, str] = {}
    keys: list[tuple[str, str]] = []  # sid, model_key
    for p in sorted(SHIPS_JSON.glob("*.json"), key=lambda x: int(x.stem)):
        d = json.loads(p.read_text(encoding="utf-8"))
        if d.get("is_unmanned"):
            continue
        key = str(d.get("model_key") or "")
        if not key:
            continue
        keys.append((str(d["id"]), key))
    ok = 0
    for sid, key in keys:
        info = convert_key(key, [LIB_SHIPS])
        if info["albedo"]:
            ship_tex[sid] = info["albedo"]
            ok += 1
            print("OK", sid, key)
        else:
            print("MISS", sid, key)
    for key in LIGHT_DRONES:
        info = convert_key(key, [LIB_DRONES, LIB_SHIPS])
        print("DRONE", key, "albedo" if info["albedo"] else "MISS")
    TEX_JSON.write_text(
        json.dumps({"ships": ship_tex}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {TEX_JSON} entries={len(ship_tex)} ok={ok}/{len(keys)}")


if __name__ == "__main__":
    main()
