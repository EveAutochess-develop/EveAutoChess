# -*- coding: utf-8 -*-
"""Stage capital/cyno review pack: PNG icons + orthographic three-views."""
from __future__ import annotations

import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np
import texture2ddecoder
import trimesh
from PIL import Image, ImageDraw

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
from assimp_convert import convert as assimp_convert  # noqa: E402

OUT = Path(r"H:\game_dev\eveautochess-design\docs\_review\capital_cyno_assets_confirm")
EQ_TEX = Path(r"H:\eve手游\history\1.9.62_unpacked\asset_library\equipment_textures")
LIB_ICONS = Path(r"H:\eve手游\history\asset_library\items\icons")
LIB_SHIPS = Path(r"H:\eve手游\history\asset_library\entities\ships")
NEOX_CONV = Path(
    r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\converter.py"
)
PVR = Path(
    r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\bin\PVRTexToolCLI.exe"
)
TMP_GLB = OUT / "_tmp_glb"

ASTC_BLOCK = {
    0x93B0: (4, 4), 0x93B1: (5, 5), 0x93B2: (5, 6), 0x93B3: (6, 5), 0x93B4: (6, 6),
    0x93B5: (8, 5), 0x93B6: (8, 6), 0x93B7: (8, 8), 0x93B8: (10, 5), 0x93B9: (10, 6),
    0x93BA: (10, 8), 0x93BB: (10, 10), 0x93BC: (12, 10), 0x93BD: (12, 12),
    0x93D0: (4, 4), 0x93D1: (5, 5), 0x93D2: (5, 6), 0x93D3: (6, 5), 0x93D4: (6, 6),
    0x93D5: (8, 5), 0x93D6: (8, 6), 0x93D7: (8, 8), 0x93D8: (10, 5), 0x93D9: (10, 6),
    0x93DA: (10, 8), 0x93DB: (10, 10), 0x93DC: (12, 10), 0x93DD: (12, 12),
}

# (stem, label, ktx candidates relative to EQ_TEX or abs, note)
SHIP_ICONS = [
    ("01_主宰级隐匿型", "主宰级隐匿型", ["item__10302000000.ktx"], "Echoes item icon"),
    ("02_黑鸟级隐匿型", "黑鸟级隐匿型", ["item__10302000001.ktx"], "Echoes item icon"),
    ("03_星空级隐匿型", "星空级隐匿型", ["item__10302000002.ktx"], "Echoes item icon"),
    ("04_挑战级隐匿型", "挑战级隐匿型", ["item__10302000003.ktx"], "Echoes item icon"),
    ("05_神示级", "神示级 / Revelation", ["shiptree__adn1_t1_isis.ktx"], "Echoes shiptree isis"),
    ("06_摩洛级", "摩洛级 / Moros", ["shiptree__gdn1_t1_isis.ktx"], "Echoes shiptree isis"),
    ("07_凤凰级", "凤凰级 / Phoenix", ["shiptree__cdn1_t1_isis.ktx"], "Echoes shiptree isis"),
    ("08_纳迦法级", "纳迦法级 / Naglfar", ["shiptree__mdn1_t1_isis.ktx"], "Echoes shiptree isis"),
    ("09_执政官级", "执政官级 / Archon", ["shiptree__aca2_t1_isis.ktx", "item__10500000002.ktx"], "shiptree aca2 isis"),
    ("10_奇美拉级", "奇美拉级 / Chimera", ["shiptree__cca1_t1_isis.ktx"], "Echoes shiptree isis"),
    ("11_绝念级", "绝念级 / Thanatos", ["shiptree__gca2_t1_isis.ktx"], "Echoes shiptree isis"),
    # mca2=冥府超航；库无 mca1；立绘请用 UI 截图或 fix_nidhoggur_review_assets.py
    ("12_尼铎格尔级", "尼铎格尔级 / Nidhoggur", ["shiptree__mca1_t1_isis.ktx"], "库无 mca1；勿用 mca2"),
]

EQUIP_ICONS = [
    ("01_极光中型舰队诱导立场", "隐秘诱导力场（库内对位）", [
        "certification__skill_yinshenzhuangbei_pic.ktx",
        "icon__icon_fold_jump.ktx",
    ], "compose 有 50023000000 但 npk 未收割到 item ktx；暂用隐身装备认证图+跃迁图标对照"),
    ("02_旗舰级脉冲激光炮", "超级脉冲激光器", ["item__120040202.ktx", "arms__120040202.ktx"], "Echoes XL pulse proxy"),
    ("03_旗舰级短管磁轨", "重型疾速中子炮", ["item__120020103.ktx", "arms__120020103.ktx"], "Echoes blaster proxy"),
    ("04_旗舰级自动加农炮", "800mm自动加农炮", ["item__120100202.ktx", "arms__120100202.ktx"], "Echoes AC proxy"),
    ("05_旗舰级鱼雷", "鱼雷发射器", ["item__120300201.ktx"], "Echoes torpedo launcher proxy"),
]

FIGHTER_ICONS_NOTE = [
    ("01_骑士_Equite", "骑士 Equite I", "Echoes 无舰载机物品图标（仅文案）"),
    ("02_蚂蚱_Locust", "蚂蚱/蚱蜢 Locust I", "Echoes 无舰载机物品图标"),
    ("03_萨梯_Satyr", "萨梯 Satyr I", "Echoes 无舰载机物品图标"),
    ("04_拉格墨_Gram", "拉格墨/格拉墨 Gram I", "Echoes 无舰载机物品图标"),
]

# model_key for three-view (Echoes entity)
MODELS = [
    ("01_主宰级隐匿型", "am_zhuzai", "Pilgrim 用主宰级 hull 预览；PC 为 ac1_t2b"),
    ("02_黑鸟级隐匿型", "jdl_heiniao", "Falcon 用黑鸟级 hull"),
    ("03_星空级隐匿型", "glt_xingkong", "Arazu 用星空级 hull"),
    ("04_挑战级隐匿型", "mmte_tiaozhan", "Rapier 用挑战级 hull"),
    ("05_神示级", "am_shenshi", "Revelation"),
    ("06_摩洛级", "glt_moluo", "Moros"),
    ("07_凤凰级", "jdl_fenghuang", "Phoenix"),
    ("08_纳迦法级", "mmte_najiafa", "Naglfar"),
    ("09_执政官级", "am_zhizhengguan", "Archon"),
    ("10_奇美拉级", "jdl_qimeila", "Chimera"),
    ("11_绝念级", "glt_juenian", "Thanatos"),
    ("12_尼铎格尔级", "mmte_niyigeer", "Nidhoggur；非 lhky_nijijing 尼基京"),
]

SIZE = 512


def decode_ktx(path: Path) -> Image.Image | None:
    data = path.read_bytes()
    if data[:7] != b"\xabKTX 11":
        return None
    vals = struct.unpack_from("<12I", data, 16)
    internal, w, h, kv = vals[3], vals[5], vals[6], vals[11]
    bw, bh = ASTC_BLOCK.get(internal, (0, 0))
    if bw == 0:
        # try PVRTexTool for ETC2 etc.
        if PVR.is_file():
            with tempfile.TemporaryDirectory() as td:
                dst = Path(td) / "out.png"
                r = subprocess.run(
                    [str(PVR), "-i", str(path), "-noout", "-d", str(dst)],
                    capture_output=True, text=True, timeout=120,
                )
                if dst.is_file():
                    return Image.open(dst).convert("RGBA")
        return None
    off = 64 + kv
    if off + 4 > len(data):
        return None
    sz = struct.unpack_from("<I", data, off)[0]
    off += 4
    raw = data[off : off + sz]
    rgba = texture2ddecoder.decode_astc(raw, w, h, bw, bh)
    return Image.frombytes("RGBA", (w, h), rgba, "raw", "BGRA")


def resolve_ktx(cands: list[str]) -> Path | None:
    for name in cands:
        p = EQ_TEX / name
        if p.is_file():
            return p
        # also hardlink library by stripping item__
        if name.startswith("item__"):
            iid = name[len("item__") :].replace(".ktx", "")
            p2 = LIB_ICONS / f"{iid}.ktx"
            if p2.is_file():
                return p2
    return None


def note_png(title: str, body: str) -> Image.Image:
    im = Image.new("RGBA", (SIZE, SIZE), (28, 32, 40, 255))
    dr = ImageDraw.Draw(im)
    dr.rectangle((12, 12, SIZE - 13, SIZE - 13), outline=(200, 120, 80, 255), width=3)
    dr.text((24, 40), title[:40], fill=(240, 220, 180, 255))
    y = 90
    for line in body.split("\n"):
        dr.text((24, y), line[:48], fill=(180, 180, 190, 255))
        y += 28
    return im


def save_icon(stem: str, label: str, cands: list[str], note: str, folder: Path) -> dict:
    src = resolve_ktx(cands)
    out = folder / f"{stem}.png"
    if src is None:
        note_png(label, f"KTX not found\n{note}").save(out)
        return {"file": str(out.relative_to(OUT)).replace("\\", "/"), "label": label, "status": "missing_ktx", "source": "", "note": note}
    im = decode_ktx(src)
    if im is None:
        note_png(label, f"decode failed\n{src.name}\n{note}").save(out)
        return {"file": str(out.relative_to(OUT)).replace("\\", "/"), "label": label, "status": "decode_fail", "source": str(src), "note": note}
    im.save(out, "PNG")
    print(f"[icon ok] {out.name} <- {src.name}")
    return {"file": str(out.relative_to(OUT)).replace("\\", "/"), "label": label, "status": "ok", "source": str(src), "note": note}


def find_entity(model_key: str) -> Path | None:
    exact = LIB_SHIPS / model_key
    if exact.is_dir():
        return exact
    for p in LIB_SHIPS.iterdir():
        if p.is_dir() and (p.name == model_key or p.name.startswith(model_key + "__")):
            return p
    return None


def pick_mesh(ent: Path, model_key: str) -> Path | None:
    mesh_dir = ent / "mesh"
    if not mesh_dir.is_dir():
        return None
    for name in (f"{model_key}_lod1.mesh", f"{model_key}_lod0.mesh", f"{model_key}_lod2.mesh"):
        p = mesh_dir / name
        if p.is_file() and p.stat().st_size > 1000:
            return p
    cands = sorted(
        (p for p in mesh_dir.glob("*.mesh") if p.stat().st_size > 1000 and "canhai" not in p.name),
        key=lambda x: (0 if "lod1" in x.name else 1 if "lod0" in x.name else 2, x.name),
    )
    return cands[0] if cands else None


def mesh_to_glb(mesh: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="neox_") as td:
        work = Path(td)
        local = work / mesh.name
        shutil.copy2(mesh, local)
        subprocess.run(
            [sys.executable, str(NEOX_CONV), str(local), "--mode", "obj"],
            capture_output=True, text=True, timeout=300, cwd=str(NEOX_CONV.parent),
        )
        obj = next((c for c in [Path(str(local) + ".obj"), local.with_suffix(".obj")] if c.is_file()), None)
        if obj is None:
            objs = list(work.glob("*.obj"))
            obj = objs[0] if objs else None
        if obj is None:
            raise RuntimeError(f"no obj for {mesh.name}")
        assimp_convert(obj, dst, "glb2")


def load_mesh(glb: Path) -> trimesh.Trimesh:
    sc = trimesh.load(str(glb), force="scene")
    geoms = [g for g in sc.dump() if isinstance(g, trimesh.Trimesh)]
    if not geoms:
        raise RuntimeError(f"empty {glb}")
    mesh = trimesh.util.concatenate(geoms)
    mesh.remove_unreferenced_vertices()
    return mesh


def rot_y(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_x(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def render_ortho(mesh: trimesh.Trimesh, view: str, size: int = SIZE) -> Image.Image:
    """front=-Z, side=+X, top=-Y orthographic shaded."""
    v = mesh.vertices.astype(np.float64)
    f = mesh.faces.astype(np.int32)
    c = v.mean(axis=0)
    v = v - c
    # align: yaw 180 like game
    v = v @ rot_y(180.0).T
    if view == "front":
        # look from -Z
        xy = v[:, [0, 1]]
        # for lighting use normals vs +Z camera
        cam = np.array([0.0, 0.0, 1.0])
    elif view == "side":
        # look from +X → use Z as x, Y as y
        xy = np.stack([v[:, 2], v[:, 1]], axis=1)
        cam = np.array([-1.0, 0.0, 0.0])
    elif view == "top":
        # look from +Y → X as x, -Z as y
        xy = np.stack([v[:, 0], -v[:, 2]], axis=1)
        cam = np.array([0.0, -1.0, 0.0])
    else:
        raise ValueError(view)

    # face normals
    try:
        normals = mesh.face_normals.astype(np.float64)
        # recompute after rotation: apply same rot to normals
        normals = normals @ rot_y(180.0).T
    except Exception:
        normals = np.tile(cam, (len(f), 1))

    light = cam / (np.linalg.norm(cam) + 1e-9)
    ndot = np.clip(normals @ light, 0.05, 1.0)
    shade = (40 + 200 * ndot).astype(np.uint8)

    mn = xy.min(axis=0)
    mx = xy.max(axis=0)
    span = np.maximum(mx - mn, 1e-6)
    pad = 0.08 * float(span.max())
    mn = mn - pad
    mx = mx + pad
    span = mx - mn
    scale = (size - 1) / float(span.max())
    mid = (mn + mx) * 0.5
    pts = (xy - mid) * scale + (size - 1) * 0.5
    img_pts = np.empty_like(pts)
    img_pts[:, 0] = pts[:, 0]
    img_pts[:, 1] = (size - 1) - pts[:, 1]

    canvas = np.full((size, size, 3), 36, dtype=np.uint8)
    order = np.argsort(ndot)  # painter rough
    for i in order:
        tri = np.round(img_pts[f[i]]).astype(np.int32)
        col = (int(shade[i]), int(min(255, shade[i] + 12)), int(min(255, shade[i] + 28)))
        cv2.fillConvexPoly(canvas, tri, col)
    # label
    cv2.putText(canvas, view, (16, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (220, 220, 230), 2, cv2.LINE_AA)
    return Image.fromarray(canvas, "RGB").convert("RGBA")


def threeview_for(stem: str, model_key: str, note: str) -> dict:
    out_dir = OUT / "models_threeview" / stem
    out_dir.mkdir(parents=True, exist_ok=True)
    ent = find_entity(model_key)
    if ent is None:
        for view in ("front", "side", "top"):
            note_png(stem, f"no entity {model_key}\n{note}").save(out_dir / f"{view}.png")
        return {"stem": stem, "model_key": model_key, "status": "no_entity", "note": note}
    mesh_path = pick_mesh(ent, model_key)
    if mesh_path is None:
        for view in ("front", "side", "top"):
            note_png(stem, f"no mesh {model_key}").save(out_dir / f"{view}.png")
        return {"stem": stem, "model_key": model_key, "status": "no_mesh", "note": note}
    glb = TMP_GLB / f"{model_key}.glb"
    try:
        if not glb.is_file() or glb.stat().st_size < 1000:
            mesh_to_glb(mesh_path, glb)
        mesh = load_mesh(glb)
        panels = []
        for view in ("front", "side", "top"):
            im = render_ortho(mesh, view)
            im.save(out_dir / f"{view}.png")
            panels.append(im)
        # strip
        strip = Image.new("RGBA", (SIZE * 3 + 16, SIZE), (20, 22, 28, 255))
        for i, im in enumerate(panels):
            strip.paste(im, (i * (SIZE + 8), 0))
        strip.save(out_dir / "threeview_strip.png")
        print(f"[3view ok] {stem} <- {mesh_path.name}")
        return {
            "stem": stem,
            "model_key": model_key,
            "status": "ok",
            "mesh": str(mesh_path),
            "strip": str((out_dir / "threeview_strip.png").relative_to(OUT)).replace("\\", "/"),
            "note": note,
        }
    except Exception as e:
        for view in ("front", "side", "top"):
            note_png(stem, f"render fail\n{e}").save(out_dir / f"{view}.png")
        print(f"[3view FAIL] {stem}: {e}")
        return {"stem": stem, "model_key": model_key, "status": "fail", "note": f"{note}; {e}"}


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT, ignore_errors=True)
    ships_d = OUT / "ships"
    equip_d = OUT / "equip"
    fight_d = OUT / "fighters"
    for d in (ships_d, equip_d, fight_d, TMP_GLB):
        d.mkdir(parents=True, exist_ok=True)

    manifest: dict = {"out_dir": str(OUT), "ships": [], "equip": [], "fighters": [], "models_threeview": []}

    for stem, label, cands, note in SHIP_ICONS:
        manifest["ships"].append(save_icon(stem, label, cands, note, ships_d))
    for stem, label, cands, note in EQUIP_ICONS:
        manifest["equip"].append(save_icon(stem, label, cands, note, equip_d))
    for stem, label, note in FIGHTER_ICONS_NOTE:
        out = fight_d / f"{stem}.png"
        note_png(label, note + "\n三视图需端游 GR2 转换器").save(out)
        manifest["fighters"].append({
            "file": str(out.relative_to(OUT)).replace("\\", "/"),
            "label": label,
            "status": "no_echoes_item_icon",
            "note": note,
        })
        print(f"[fighter note] {out.name}")

    for stem, key, note in MODELS:
        manifest["models_threeview"].append(threeview_for(stem, key, note))

    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# 旗舰/隐秘诱导 · 素材确认包（PNG）",
        "",
        f"目录：`{OUT}`",
        "",
        "## ships/ 立绘 PNG",
        "",
        "| 文件 | 状态 | 来源说明 |",
        "|------|------|----------|",
    ]
    for r in manifest["ships"]:
        lines.append(f"| `{r['file']}` | {r['status']} | {r['note']} |")
    lines += ["", "## equip/ 装备 PNG", ""]
    for r in manifest["equip"]:
        lines.append(f"| `{r['file']}` | {r['status']} | {r['note']} |")
    lines += ["", "## fighters/", ""]
    for r in manifest["fighters"]:
        lines.append(f"| `{r['file']}` | {r['status']} | {r['note']} |")
    lines += ["", "## models_threeview/ 正交三视图（front/side/top + strip）", ""]
    for r in manifest["models_threeview"]:
        lines.append(f"| `{r['stem']}` | `{r.get('model_key')}` | {r['status']} | {r.get('note','')} |")
    lines += [
        "",
        "## 说明",
        "",
        "- 立绘/图标一律 PNG；模型为 NeoX `.mesh`→GLB 后正交渲染截图。",
        "- 旗舰立绘优先 Echoes **shiptree `*_isis`**（库内确有）；隐匿型用 `item__1030200000x`。",
        "- 诱导物品 `50023000000` 在 compose 有逻辑路径，但本机 1.0.0/1.9.62 npk **未收割到对应 item ktx**；确认包用认证/跃迁图标占位并标明。",
        "- 舰载机 Echoes 无物品图标；三视图待端游 GR2→OBJ 工具链。",
        "",
    ]
    (OUT / "README.md").write_text("\n".join(lines), encoding="utf-8")

    ok_i = sum(1 for r in manifest["ships"] + manifest["equip"] if r["status"] == "ok")
    ok_m = sum(1 for r in manifest["models_threeview"] if r["status"] == "ok")
    print(f"\nDONE {OUT}")
    print(f"icons_ok={ok_i} threeview_ok={ok_m}")


if __name__ == "__main__":
    main()
