# -*- coding: utf-8 -*-
"""Stage Echoes generic ship-death fire FX for titan kill preview.

Source (Echoes 1.9.62/1.9.145 asset_library):
  fx/effects/space_environment/fx_ship_death_{s,m,l,xl}.sfx
  fx/model/fx_ship_death_jh|xl  (flame / ring / particle meshes)
  fx/texture/fire/fire_01_yd.{ktx,spr}  (49-frame cutout atlas)

Rule: only 3D-space playback of the FX's own cutout/particle timeline.
Does not invent billboard stand-ins from unrelated PNGs.
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
DESIGN = Path(r"H:\game_dev\eveautochess-design")
sys.path.insert(0, str(ROOT / "tools"))

import texture2ddecoder  # noqa: E402
from assimp_convert import convert as assimp_convert  # noqa: E402

ECHOES_FX = Path(r"H:\eve手游\history\1.9.62_unpacked\asset_library\fx\fx")
LIB_MODELS = Path(r"H:\eve手游\history\asset_library\entities\fx_models")
NEOX_CONV = Path(
    r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\converter.py"
)

OUT_GODOT = ROOT / "godot_project" / "assets" / "vfx" / "ship_death_echoes"
OUT_REVIEW = DESIGN / "docs" / "_review" / "20260731_confirm" / "titan_kill_preview" / "echoes_ship_death"

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

# Titan → XL; preview also keeps L for reference.
SFX_FILES = [
    "effects/space_environment/fx_ship_death_s.sfx",
    "effects/space_environment/fx_ship_death_m.sfx",
    "effects/space_environment/fx_ship_death_l.sfx",
    "effects/space_environment/fx_ship_death_xl.sfx",
    "effects/space_environment/fx_ship_death_l_01.sfx",
    "effects/space_ship/fx_ship_death_01.sfx",
]

TEX_KEYS = [
    ("texture/fire/fire_01_yd.ktx", "texture/fire/fire_01_yd.spr"),
    ("texture/space/explosion_005.ktx", "texture/space/explosion_005.spr"),
    ("texture/space/fx_flare.ktx", None),
    ("texture/particle/crystaldebris_01_d.ktx", "texture/particle/crystaldebris_01_d.spr"),
    ("texture/noise/caustic_13.ktx", None),
    ("texture/alpha/y_negative_ramp_01_blue.ktx", None),
    ("texture/multiple_maps/noise_01_m2_pmwo.ktx", None),
    ("texture/star/star_02_jh_djs.png", None),
    ("texture/glow/glow_03_jm.png", None),
]

MESH_KEYS = [
    "fx_ship_death_xl/mesh/fx_huoyan_08.mesh",
    "fx_ship_death_xl/mesh/fx_huoyan_09.mesh",
    "fx_ship_death_xl/mesh/fx_kuosanhuan_04.mesh",
    "fx_ship_death_xl/mesh/fx_lizi_01.mesh",
    "fx_ship_death_jh/mesh/huoyan_07_jh_djs_new.mesh",
    "fx_ship_death_jh/mesh/huoyan_08_jh_djs_new.mesh",
    "fx_ship_boom/mesh/fx_fireboom_01.mesh",
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
    sz = struct.unpack_from("<I", data, off)[0]
    off += 4
    raw = data[off : off + sz]
    rgba = texture2ddecoder.decode_astc(raw, w, h, bw, bh)
    return Image.frombytes("RGBA", (w, h), rgba, "raw", "BGRA")


def parse_spr(path: Path) -> dict:
    lines = [ln.strip() for ln in path.read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip()]
    # format: version?, frame_count, duration_ms, then "name x0 y0 x1 y1"
    frame_count = int(lines[1]) if len(lines) > 1 and lines[1].isdigit() else 0
    duration_ms = int(lines[2]) if len(lines) > 2 and lines[2].isdigit() else 0
    frames = []
    for ln in lines[3:]:
        parts = ln.split()
        if len(parts) < 5:
            continue
        name, x0, y0, x1, y1 = parts[0], int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])
        frames.append({"name": name, "x0": x0, "y0": y0, "x1": x1, "y1": y1})
    return {"frame_count": frame_count or len(frames), "duration_ms": duration_ms, "frames": frames}


def copy_sfx() -> list[str]:
    written = []
    for rel in SFX_FILES:
        src = ECHOES_FX / rel.replace("\\", "/")
        if not src.is_file():
            print("MISS sfx", rel)
            continue
        dst = OUT_GODOT / "sfx" / Path(rel).name
        dst.parent.mkdir(parents=True, exist_ok=True)
        review_dst = OUT_REVIEW / "sfx" / Path(rel).name
        review_dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        shutil.copy2(src, review_dst)
        written.append(dst.name)
    return written


def convert_textures() -> list[dict]:
    out = []
    tex_dir = OUT_GODOT / "tex"
    tex_dir.mkdir(parents=True, exist_ok=True)
    (OUT_REVIEW / "tex").mkdir(parents=True, exist_ok=True)
    for ktx_rel, spr_rel in TEX_KEYS:
        src = ECHOES_FX / ktx_rel.replace("\\", "/")
        stem = Path(ktx_rel).stem
        if src.suffix.lower() == ".png" and src.is_file():
            dst = tex_dir / src.name
            shutil.copy2(src, dst)
            shutil.copy2(src, OUT_REVIEW / "tex" / src.name)
            out.append({"stem": stem, "png": dst.name})
            continue
        if not src.is_file():
            print("MISS tex", ktx_rel)
            continue
        im = decode_ktx(src)
        if im is None:
            print("FAIL decode", ktx_rel)
            continue
        dst = tex_dir / f"{stem}.png"
        im.save(dst)
        shutil.copy2(dst, OUT_REVIEW / "tex" / dst.name)
        entry = {"stem": stem, "png": dst.name, "size": list(im.size)}
        if spr_rel:
            spr = ECHOES_FX / spr_rel.replace("\\", "/")
            if spr.is_file():
                meta = parse_spr(spr)
                meta_path = tex_dir / f"{stem}.spr.json"
                meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
                shutil.copy2(meta_path, OUT_REVIEW / "tex" / meta_path.name)
                shutil.copy2(spr, OUT_REVIEW / "tex" / spr.name)
                entry["spr"] = meta
        out.append(entry)
        print("tex", stem, im.size)
    return out


def convert_meshes() -> list[dict]:
    import subprocess
    import tempfile

    written = []
    mesh_out = OUT_GODOT / "mesh"
    mesh_out.mkdir(parents=True, exist_ok=True)
    (OUT_REVIEW / "mesh").mkdir(parents=True, exist_ok=True)
    if not NEOX_CONV.is_file():
        print("MISS neox converter", NEOX_CONV)
        return written
    for rel in MESH_KEYS:
        src = LIB_MODELS / rel.replace("\\", "/")
        if not src.is_file():
            # fallback 1.9.62 tree
            alt = ECHOES_FX / "model" / rel.replace("fx_ship_death_xl/mesh/", "fx_ship_death_xl/").replace(
                "fx_ship_death_jh/mesh/", "fx_ship_death_jh/"
            ).replace("fx_ship_boom/mesh/", "fx_ship_boom/")
            src = alt if alt.is_file() else src
        if not src.is_file():
            print("MISS mesh", rel)
            continue
        stem = src.stem
        with tempfile.TemporaryDirectory(prefix="neox_death_") as td:
            td_path = Path(td)
            # converter.py accepts only: converter.py --mode obj <path>
            # It writes the OBJ beside the input, so convert a temporary copy.
            tmp_mesh = td_path / src.name
            shutil.copy2(src, tmp_mesh)
            try:
                subprocess.run(
                    [sys.executable, str(NEOX_CONV), "--mode", "obj", str(tmp_mesh)],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=120,
                )
            except Exception as e:
                print("neox fail", stem, e)
                continue
            objs = list(td_path.rglob("*.obj"))
            if not objs:
                print("no obj", stem)
                continue
            glb = mesh_out / f"{stem}.glb"
            try:
                assimp_convert(objs[0], glb, "glb2")
            except Exception as e:
                print("assimp fail", stem, e)
                continue
            shutil.copy2(glb, OUT_REVIEW / "mesh" / glb.name)
            written.append({"stem": stem, "glb": glb.name, "src": rel})
            print("mesh", stem, glb.stat().st_size)
    return written


def write_manifest(sfx: list[str], tex: list[dict], meshes: list[dict]) -> None:
    man = {
        "source": "Echoes 1.9.62/1.9.145 asset_library",
        "authority": [
            "fx/effects/space_environment/fx_ship_death_xl.sfx",
            "fx/model/fx_ship_death_xl",
            "fx/texture/fire/fire_01_yd.spr",
        ],
        "note": "Generic ship death fire. Titan uses XL tier. Playback must be 3D cutout/particle timeline from these assets.",
        "sfx": sfx,
        "textures": tex,
        "meshes": meshes,
    }
    OUT_GODOT.mkdir(parents=True, exist_ok=True)
    OUT_REVIEW.mkdir(parents=True, exist_ok=True)
    (OUT_GODOT / "MANIFEST.json").write_text(json.dumps(man, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT_REVIEW / "MANIFEST.json").write_text(json.dumps(man, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [
        "# Echoes 通用舰船被击毁火光",
        "",
        "权威：`fx_ship_death_{s,m,l,xl}.sfx` + `fx_ship_death_jh/xl` 火焰网 + `fire_01_yd.spr`（49 帧镂空序列）。",
        "",
        "泰坦档用 **XL**。本目录只落盘源与可播序列贴图/火焰 GLB；禁止用无关 PNG 单张淡入冒充。",
        "",
        f"- sfx: {len(sfx)}",
        f"- textures: {len(tex)}",
        f"- meshes: {len(meshes)}",
    ]
    (OUT_REVIEW / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    OUT_GODOT.mkdir(parents=True, exist_ok=True)
    OUT_REVIEW.mkdir(parents=True, exist_ok=True)
    sfx = copy_sfx()
    tex = convert_textures()
    meshes = convert_meshes()
    write_manifest(sfx, tex, meshes)
    print(f"done sfx={len(sfx)} tex={len(tex)} mesh={len(meshes)}")


if __name__ == "__main__":
    main()
