# -*- coding: utf-8 -*-
"""Match user screenshots + stage FAX ships / heavy repair drone refs."""
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
EQ = Path(r"H:\eve手游\history\1.9.62_unpacked\asset_library\equipment_textures")
LIB_ICONS = Path(r"H:\eve手游\history\asset_library\items\icons")
LIB_SHIPS = Path(r"H:\eve手游\history\asset_library\entities\ships")
NEOX = Path(r"H:\eve手游\extracted\tools\neox_tools_zhouhang95\neox_tools-master\converter.py")
ASSETS = Path(r"C:\Users\WXH\.cursor\projects\h\assets")
TMP_GLB = OUT / "_tmp_glb"

ASTC = {
    0x93B0: (4, 4), 0x93B1: (5, 5), 0x93B2: (5, 6), 0x93B3: (6, 5), 0x93B4: (6, 6),
    0x93B5: (8, 5), 0x93B6: (8, 6), 0x93B7: (8, 8), 0x93B8: (10, 5), 0x93B9: (10, 6),
    0x93BA: (10, 8), 0x93BB: (10, 10), 0x93BC: (12, 10), 0x93BD: (12, 12),
    0x93D0: (4, 4), 0x93D1: (5, 5), 0x93D2: (5, 6), 0x93D3: (6, 5), 0x93D4: (6, 6),
    0x93D5: (8, 5), 0x93D6: (8, 6), 0x93D7: (8, 8), 0x93D8: (10, 5), 0x93D9: (10, 6),
    0x93DA: (10, 8), 0x93DB: (10, 10), 0x93DC: (12, 10), 0x93DD: (12, 12),
}

# User-dropped portrait filenames → FAX mapping (by race digit in Echoes id)
# 10701000X11 pattern: X≈race bucket; verify via visual vs entity later
# Echoes id 10701000X11：X=1加达里 / 2盖伦特 / 3米玛塔尔 / 4艾玛（与立绘目视一致）
FAX_PORTRAITS = [
    ("13_龙鸟级", "Minokawa", 37605, "jdl_longniao", "cfaux1", "10701000111"),
    ("14_尼纳苏级", "Ninazu", 37607, "glt_ninasu", "gfaux1", "10701000211"),
    ("15_立夫级_利夫", "Lif", 37606, "mmte_lifu", "mfaux1", "10701000311"),
    ("16_使徒级", "Apostle", 37604, "am_shitu", "afaux1", "10701000411"),
]

# PC heavy maintenance bots (SDE graphic → sofHull)
HEAVY_REPAIR = [
    ("重型装甲维护机器人_I", "Heavy Armor Maintenance Bot I", 23523, "adh1",
     r"res:/dx9/model/drone/amarr/heavy/adh1/adh1_t1_lowdetail.gr2",
     r"H:\EVE\ResFiles\00\00ca9a3db02a7f8b_c70765a292c41ff5a08df1593ad45a3a"),
    ("重型护盾维护机器人_I", "Heavy Shield Maintenance Bot I", 22765, "cdh1",
     r"res:/dx9/model/drone/caldari/heavy/cdh1/cdh1_t1_lowdetail.gr2",
     r"H:\EVE\ResFiles\a9\a9ba0127329017cc_3f72795149221c871407e5055561958e"),
]


def decode_ktx(path: Path) -> Image.Image | None:
    data = path.read_bytes()
    if data[:7] != b"\xabKTX 11":
        return None
    vals = struct.unpack_from("<12I", data, 16)
    internal, w, h, kv = vals[3], vals[5], vals[6], vals[11]
    bw, bh = ASTC.get(internal, (0, 0))
    if bw == 0:
        return None
    off = 64 + kv
    sz = struct.unpack_from("<I", data, off)[0]
    off += 4
    rgba = texture2ddecoder.decode_astc(data[off : off + sz], w, h, bw, bh)
    return Image.frombytes("RGBA", (w, h), rgba, "raw", "BGRA")


def find_shot(substr: str) -> Path | None:
    for p in ASSETS.glob("*.png"):
        if substr in p.name:
            return p
    return None


def crop_card_icon(im: Image.Image) -> Image.Image:
    w, h = im.size
    side = int(min(w, h) * 0.52)
    left = (w - side) // 2
    top = int(h * 0.30)
    return im.crop((left, top, left + side, top + side))


def gold_mask(a: np.ndarray) -> np.ndarray:
    r, g, b, al = a[:, :, 0], a[:, :, 1], a[:, :, 2], a[:, :, 3]
    return (r > 125) & (g > 85) & (b < 130) & (r > g + 8) & (al > 40)


def match_fist(query: Image.Image, pool: list[Path], out_dir: Path, top_k: int = 12) -> list[dict]:
    q = query.convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS)
    qa = np.array(q)
    qg = gold_mask(qa)
    hits: list[tuple[float, Path, Image.Image]] = []
    for path in pool:
        im = decode_ktx(path)
        if im is None:
            continue
        im64 = im.resize((64, 64), Image.Resampling.LANCZOS)
        a = np.array(im64)
        g = gold_mask(a)
        if g.mean() < 0.08:
            continue
        inter = np.logical_and(qg, g).sum()
        union = np.logical_or(qg, g).sum() + 1e-6
        iou = inter / union
        # also RGB hist on masked pixels
        if qg.sum() < 20 or g.sum() < 20:
            continue
        score = float(iou + 0.35 * g.mean())
        hits.append((score, path, im))
    hits.sort(key=lambda x: x[0], reverse=True)
    rows = []
    for i, (score, path, im) in enumerate(hits[:top_k]):
        name = f"fist_rank{i+1:02d}_{path.stem}.png"
        im.save(out_dir / name)
        rows.append({"rank": i + 1, "score": round(score, 4), "file": name, "source": str(path)})
    return rows


def hist_feat(im: Image.Image, size: int = 64) -> np.ndarray | None:
    im = im.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    a = np.array(im)
    mask = a[:, :, 3] > 20
    if mask.sum() < 40:
        return None
    hist = []
    for c in range(3):
        h, _ = np.histogram(a[:, :, c][mask], bins=16, range=(0, 255), density=True)
        hist.append(h)
    gray = cv2.cvtColor(a, cv2.COLOR_RGBA2GRAY)
    edges = cv2.Canny(gray, 40, 140)
    eh = cv2.resize(edges, (16, 16)).astype(np.float32).ravel() / 255.0
    return np.concatenate(hist + [eh])


def match_hist(query: Image.Image, pool: list[Path], out_dir: Path, prefix: str, top_k: int = 10) -> list[dict]:
    qf = hist_feat(query)
    if qf is None:
        return []
    hits: list[tuple[float, Path, Image.Image]] = []
    for path in pool:
        im = decode_ktx(path)
        if im is None:
            continue
        f = hist_feat(im)
        if f is None:
            continue
        sim = float(np.dot(qf, f) / (np.linalg.norm(qf) * np.linalg.norm(f) + 1e-9))
        hits.append((sim, path, im))
    hits.sort(key=lambda x: x[0], reverse=True)
    rows = []
    for i, (sim, path, im) in enumerate(hits[:top_k]):
        name = f"{prefix}_rank{i+1:02d}_{path.stem}.png"
        im.save(out_dir / name)
        rows.append({"rank": i + 1, "score": round(sim, 4), "file": name, "source": str(path)})
    return rows


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
    for name in (f"{model_key}_lod1.mesh", f"{model_key}_lod0.mesh"):
        p = mesh_dir / name
        if p.is_file() and p.stat().st_size > 1000:
            return p
    cands = sorted(
        (p for p in mesh_dir.glob("*.mesh") if p.stat().st_size > 1000 and "canhai" not in p.name),
        key=lambda x: (0 if "lod1" in x.name else 1, x.name),
    )
    return cands[0] if cands else None


def mesh_to_glb(mesh: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="neox_") as td:
        work = Path(td)
        local = work / mesh.name
        shutil.copy2(mesh, local)
        subprocess.run(
            [sys.executable, str(NEOX), str(local), "--mode", "obj"],
            capture_output=True, text=True, timeout=300, cwd=str(NEOX.parent),
        )
        obj = next((c for c in [Path(str(local) + ".obj"), local.with_suffix(".obj")] if c.is_file()), None)
        if obj is None:
            objs = list(work.glob("*.obj"))
            obj = objs[0] if objs else None
        if obj is None:
            raise RuntimeError(f"no obj for {mesh.name}")
        assimp_convert(obj, dst, "glb2")


def rot_y(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def render_ortho(mesh: trimesh.Trimesh, view: str, size: int = 512) -> Image.Image:
    v = mesh.vertices.astype(np.float64)
    f = mesh.faces.astype(np.int32)
    v = v - v.mean(axis=0)
    v = v @ rot_y(180.0).T
    if view == "front":
        xy = v[:, [0, 1]]
        cam = np.array([0.0, 0.0, 1.0])
    elif view == "side":
        xy = np.stack([v[:, 2], v[:, 1]], axis=1)
        cam = np.array([-1.0, 0.0, 0.0])
    else:
        xy = np.stack([v[:, 0], -v[:, 2]], axis=1)
        cam = np.array([0.0, -1.0, 0.0])
    try:
        normals = mesh.face_normals.astype(np.float64) @ rot_y(180.0).T
    except Exception:
        normals = np.tile(cam, (len(f), 1))
    light = cam / (np.linalg.norm(cam) + 1e-9)
    ndot = np.clip(normals @ light, 0.05, 1.0)
    shade = (40 + 200 * ndot).astype(np.float64)
    mn, mx = xy.min(0), xy.max(0)
    span = np.maximum(mx - mn, 1e-6)
    pad = 0.08 * float(span.max())
    mn, mx = mn - pad, mx + pad
    span = mx - mn
    scale = (size - 1) / float(span.max())
    mid = (mn + mx) * 0.5
    pts = (xy - mid) * scale + (size - 1) * 0.5
    img_pts = np.column_stack([pts[:, 0], (size - 1) - pts[:, 1]])
    canvas = np.full((size, size, 3), 36, dtype=np.uint8)
    for i in np.argsort(ndot):
        tri = np.round(img_pts[f[i]]).astype(np.int32)
        s = int(shade[i])
        cv2.fillConvexPoly(canvas, tri, (s, min(255, s + 12), min(255, s + 28)))
    cv2.putText(canvas, view, (16, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (220, 220, 230), 2, cv2.LINE_AA)
    return Image.fromarray(canvas, "RGB").convert("RGBA")


def threeview(stem: str, model_key: str) -> dict:
    out_dir = OUT / "models_threeview" / stem
    out_dir.mkdir(parents=True, exist_ok=True)
    ent = find_entity(model_key)
    if not ent:
        return {"stem": stem, "status": "no_entity", "model_key": model_key}
    mesh_path = pick_mesh(ent, model_key)
    if not mesh_path:
        return {"stem": stem, "status": "no_mesh", "model_key": model_key}
    glb = TMP_GLB / f"{model_key}.glb"
    mesh_to_glb(mesh_path, glb)
    mesh = trimesh.load(str(glb), force="scene")
    geoms = [g for g in mesh.dump() if isinstance(g, trimesh.Trimesh)]
    m = trimesh.util.concatenate(geoms)
    panels = []
    for view in ("front", "side", "top"):
        im = render_ortho(m, view)
        im.save(out_dir / f"{view}.png")
        panels.append(im)
    strip = Image.new("RGBA", (512 * 3 + 16, 512), (20, 22, 28, 255))
    for i, im in enumerate(panels):
        strip.paste(im, (i * 520, 0))
    strip.save(out_dir / "threeview_strip.png")
    print(f"[3view] {stem} ok")
    return {"stem": stem, "status": "ok", "model_key": model_key, "mesh": str(mesh_path)}


def main() -> None:
    match_dir = OUT / "_screenshot_matches"
    if match_dir.exists():
        shutil.rmtree(match_dir)
    match_dir.mkdir(parents=True)
    ships_d = OUT / "ships"
    equip_d = OUT / "equip"
    repair_d = OUT / "heavy_repair_drones"
    repair_d.mkdir(parents=True, exist_ok=True)
    TMP_GLB.mkdir(parents=True, exist_ok=True)

    pool = list(EQ.glob("item__*.ktx")) + list(EQ.glob("all__*.ktx")) + list(LIB_ICONS.glob("*.ktx"))
    report: dict = {"matches": {}, "fax": [], "heavy_repair": []}

    # --- screenshot 1: cyno fist ---
    shot1 = find_shot("c5a3553c08b20b26e383536be160c00a")
    if shot1:
        card = Image.open(shot1).convert("RGBA")
        icon = crop_card_icon(card)
        icon.save(match_dir / "00_query_极光舰队诱导_crop.png")
        # tighter fist
        w, h = icon.size
        fist = icon.crop((int(w * 0.18), int(h * 0.02), int(w * 0.82), int(h * 0.78)))
        fist.save(match_dir / "00_query_fist_tight.png")
        (match_dir / "cyno_fist").mkdir(exist_ok=True)
        (match_dir / "cyno_hist").mkdir(exist_ok=True)
        report["matches"]["极光舰队诱导力场发生器"] = {
            "query": str(shot1),
            "echoes_text": "极光 舰队诱导力场发生器 -- 中型",
            "fist_like": match_fist(fist, pool, match_dir / "cyno_fist"),
            "hist_like": match_hist(icon, pool, match_dir / "cyno_hist", "cyno"),
            "also_cyno_family_png": [],
        }
        # known cyno-looking 41802 family
        for i in ("41802000002", "41802000003", "41802000008", "41802000010"):
            p = EQ / f"item__{i}.ktx"
            im = decode_ktx(p)
            if im:
                name = f"cyno_family_{i}.png"
                im.save(match_dir / name)
                report["matches"]["极光舰队诱导力场发生器"]["also_cyno_family_png"].append(name)
        # Beatnik named remote armor (name overlap 比特尼克) icon
        for i in ("11102000000", "11102000012"):
            for p in (EQ / f"item__{i}.ktx", LIB_ICONS / f"{i}.ktx"):
                if not p.is_file():
                    continue
                im = decode_ktx(p)
                if im:
                    name = f"beatnik_remote_armor_{i}.png"
                    im.save(match_dir / name)
                break

    # --- screenshot 2/3: craft cards ---
    shot2 = find_shot("2b8577fe60167fd7c08ae3131596b4e1")
    shot3 = find_shot("414096e1ddd90dc5f513a32b16a3dcd5")
    drone_pool = list(EQ.glob("item__1*.ktx")) + list(EQ.glob("item__2*.ktx")) + list(EQ.glob("item__5*.ktx"))
    if shot2:
        icon = crop_card_icon(Image.open(shot2).convert("RGBA"))
        icon.save(match_dir / "00_query_比特尼克超重型装甲维护_crop.png")
        (match_dir / "armor_maint").mkdir(exist_ok=True)
        report["matches"]["比特尼克超重型装甲维护"] = {
            "query_text": "比特尼克 超重型装甲维护…（截图）",
            "compose_name_hit": "仅有「比特尼克 小型远程装甲维修器」11102000012，非超重型无人机",
            "pc_map": "Heavy Armor Maintenance Bot I typeID=23523 graphic=adh1",
            "hist_like": match_hist(icon, drone_pool, match_dir / "armor_maint", "armor"),
        }
    if shot3:
        icon = crop_card_icon(Image.open(shot3).convert("RGBA"))
        icon.save(match_dir / "00_query_微型超重型护盾维护_crop.png")
        (match_dir / "shield_maint").mkdir(exist_ok=True)
        report["matches"]["微型超重型护盾维护无人"] = {
            "query_text": "微型 超重型护盾维护无人…（截图）",
            "compose_name_hit": "「微型」多为远程护盾回充 meta 前缀；无超重型护盾维护无人机条目",
            "pc_map": "Heavy Shield Maintenance Bot I typeID=22765 graphic=cdh1",
            "hist_like": match_hist(icon, drone_pool, match_dir / "shield_maint", "shield"),
        }

    # --- organize FAX portraits user dropped ---
    for stem, en, tid, key, tree, eid in FAX_PORTRAITS:
        # prefer user-dropped PNG if present
        dropped = ships_d / f"{eid}.png"
        out_png = ships_d / f"{stem}.png"
        if dropped.is_file():
            shutil.copy2(dropped, out_png)
            src = str(dropped)
        else:
            ktx = EQ / f"item__{eid}.ktx"
            im = decode_ktx(ktx)
            if im is None:
                ktx = EQ / f"shiptree__{tree}_t1_isis.ktx"
                im = decode_ktx(ktx)
                src = str(ktx)
            else:
                src = str(ktx)
            if im:
                im.save(out_png)
        # also keep shiptree copy
        tree_im = decode_ktx(EQ / f"shiptree__{tree}_t1_isis.ktx")
        if tree_im:
            tree_im.save(ships_d / f"{stem}_shiptree_{tree}.png")
        tv = threeview(stem, key)
        report["fax"].append(
            {
                "stem": stem,
                "name_en": en,
                "type_id": tid,
                "model_key": key,
                "echoes_item_guess": eid,
                "portrait": str(out_png.name),
                "portrait_source": src if "src" in dir() else str(dropped),
                "threeview": tv,
                "shop": {"cost": 22, "min_level": 15, "ship_group": "force_auxiliary"},
            }
        )
        print(f"[fax] {stem} portrait+3view")

    # --- heavy repair drone refs (copy GR2 path note + try Echoes heavy drone mesh 3view as visual stand-in) ---
    # Echoes heavy combat drones as visual proxy until GR2 convert works
    echo_heavy = {
        "adh1": None,  # no echoes key; use amarr heavy if any
    }
    for stem, en, tid, sof, res, disk in HEAVY_REPAIR:
        info = {
            "label": stem,
            "name_en": en,
            "type_id": tid,
            "sofHullName": sof,
            "res": res,
            "gr2_ondisk": disk,
            "gr2_exists": Path(disk).is_file(),
            "note": "端游重型维修机器人复用各族 heavy drone 船体（SDE graphic）；需 evegr2toobj_x64 才能转 GLB",
        }
        # copy a tiny readme pointer
        (repair_d / f"{stem}.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
        report["heavy_repair"].append(info)
        print(f"[repair] {stem} gr2={'OK' if info['gr2_exists'] else 'MISS'}")

    # copy user screenshots into match folder for side-by-side
    for label, p in (
        ("shot_极光诱导", shot1),
        ("shot_比特尼克装甲维护", shot2),
        ("shot_微型护盾维护", shot3),
    ):
        if p and p.is_file():
            shutil.copy2(p, match_dir / f"{label}.png")

    (OUT / "MATCH_REPORT.md").write_text(
        "\n".join(
            [
                "# 截图匹配报告",
                "",
                "## 1. 极光 舰队诱导力场发生器（中型）",
                "- 截图图标：金色拳套圆环。",
                "- Compose **无**「极光」「舰队诱导力场发生器」条目；最接近逻辑名仍是诱导力场族。",
                "- 自动匹配结果见 `_screenshot_matches/cyno_fist/` 与 `cyno_hist/`；另附 `cyno_family_41802*.png`（蓝弧诱导仪造型）。",
                "- 「比特尼克」在 Compose 命中的是 **小型远程装甲维修器** `11102000012`，不是诱导模块。",
                "",
                "## 2. 比特尼克 超重型装甲维护…",
                "- Compose 无「超重型装甲维护」无人机/舰载机。",
                "- 端游对位：**Heavy Armor Maintenance Bot I** `23523`，graphic sof=`adh1`（艾玛重型无人机壳）。",
                "- GR2 已在 `H:\\EVE\\ResFiles\\00\\00ca9a3d...`。",
                "",
                "## 3. 微型 超重型护盾维护无人…",
                "- 「微型」在 Compose 多为远程护盾 meta 前缀。",
                "- 端游对位：**Heavy Shield Maintenance Bot I** `22765`，sof=`cdh1`。",
                "- GR2 已在 `H:\\EVE\\ResFiles\\a9\\a9ba0127...`。",
                "",
                "## 4. 后勤航（本轮补）",
                "| 展示 | EN | typeID | model_key | 你放入的立绘 id |",
                "|------|----|--------|-----------|-----------------|",
                "| 龙鸟级 | Minokawa | 37605 | jdl_longniao | 10701000111 |",
                "| 尼纳苏级 | Ninazu | 37607 | glt_ninasu | 10701000211 |",
                "| 立夫/利夫级 | Lif | 37606 | mmte_lifu | 10701000311 |",
                "| 使徒级 | Apostle | 37604 | am_shitu | 10701000411 |",
                "",
                "立绘已整理到 `ships/13_…16_….png`，三视图在 `models_threeview/`。",
                "",
                "详细 JSON：`screenshot_match_report.json`",
                "",
            ]
        ),
        encoding="utf-8",
    )
    (OUT / "screenshot_match_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("DONE", match_dir)


if __name__ == "__main__":
    main()
