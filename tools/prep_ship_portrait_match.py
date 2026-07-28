# -*- coding: utf-8 -*-
"""Prepare Echoes market icon candidates per ship via silhouette contour match.

Renders each roster GLB from a fixed pose (camera ahead of bow, ~45° left-up),
extracts outer contour, matches against decoded gui_v1/icon/item/*.ktx silhouettes,
and writes MULTIPLE candidates into a folder per ship for manual pruning
(faction skins share hull silhouettes and will false-match).

Usage:
  python prep_ship_portrait_match.py                  # full run
  python prep_ship_portrait_match.py --ships am_chengfazhe,glt_cujin
  python prep_ship_portrait_match.py --top 12 --skip-icons-cache
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

import cv2
import numpy as np
import texture2ddecoder
import trimesh
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
GODOT = ROOT / "godot_project"
SHIPS_GLB = GODOT / "assets" / "models" / "ships"
SHIPS_JSON = GODOT / "data" / "ships"
OUT = ROOT / "tools" / "_portrait_match"
SIL_SHIPS = OUT / "silhouettes_ships"
SIL_ICONS = OUT / "silhouettes_icons"
CAND_DIR = OUT / "candidates"  # candidates/<model_key__中文名>/<rank>_dSCORE_iconid.png
POOL_DIR = OUT / "icons_pool"  # shared decoded icons by icon_id (non-exclusive)
REPORT = OUT / "match_report.json"

ASSET_META = Path(
    r"H:\eve手游\history\1.9.62_unpacked\asset_library\_meta\path_hash_map.json"
)
TEX_DIR = Path(r"H:\eve手游\history\1.9.62_unpacked\art_extract\textures")

# Render / match knobs
RENDER_SIZE = 256
ICON_SIZE = 128
# Camera: ahead of bow (−Z), left (−X), up (+Y), ~45° elevation/azimuth blend.
CAM_DIR = np.array([-1.0, 1.0, -1.0], dtype=np.float64)
# Model yaw applied before camera (matches visual.json ship_model_yaw_deg=180).
MODEL_YAW_DEG = 180.0
FD_SAMPLES = 128  # resampled boundary points
FD_KEEP = 24  # low-frequency Fourier coeffs used for distance (skip DC)

DEFAULT_TOP_K = 24
# Keep candidates whose curve distance <= best * ratio OR under absolute floor.
SCORE_RATIO = 1.8
SCORE_ABS_MAX = 0.45


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
    # sRGB variants
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


def roster(keys_filter: set[str] | None) -> list[dict]:
    rows = []
    for f in sorted(SHIPS_JSON.glob("*.json"), key=lambda p: int(p.stem)):
        d = json.loads(f.read_text(encoding="utf-8"))
        key = str(d["model_key"])
        if keys_filter and key not in keys_filter:
            continue
        rows.append(
            {
                "id": int(d["id"]),
                "name": str(d["name"]),
                "model_key": key,
                "type_id": int(d.get("type_id") or 0),
                "glb": SHIPS_GLB / f"{key}.glb",
            }
        )
    return rows


def rot_y(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def load_mesh(glb: Path) -> trimesh.Trimesh:
    sc = trimesh.load(str(glb), force="scene")
    geoms = [g for g in sc.dump() if isinstance(g, trimesh.Trimesh)]
    if not geoms:
        raise RuntimeError(f"no mesh in {glb}")
    mesh = trimesh.util.concatenate(geoms)
    mesh.remove_unreferenced_vertices()
    return mesh


def look_at_basis(eye: np.ndarray, target: np.ndarray, up: np.ndarray) -> np.ndarray:
    """Rows = camera axes in world: X right, Y up, Z toward camera (OpenCV-ish)."""
    f = target - eye
    f = f / (np.linalg.norm(f) + 1e-12)
    # camera looks along -Z in view space; forward view = f
    r = np.cross(f, up)
    if np.linalg.norm(r) < 1e-8:
        r = np.cross(f, np.array([1.0, 0.0, 0.0]))
    r = r / (np.linalg.norm(r) + 1e-12)
    u = np.cross(r, f)
    u = u / (np.linalg.norm(u) + 1e-12)
    # view transform: world -> camera (x=right, y=up, z=back)
    # point_cam = R @ (p - eye) with R rows = [r, u, -f]
    return np.stack([r, u, -f], axis=0)


def rasterize_silhouette(
    verts: np.ndarray, faces: np.ndarray, size: int = RENDER_SIZE
) -> np.ndarray:
    """Orthographic silhouette; verts already in camera XY (Z ignored for fill)."""
    if len(verts) == 0 or len(faces) == 0:
        return np.zeros((size, size), dtype=np.uint8)
    xy = verts[:, :2]
    mn = xy.min(axis=0)
    mx = xy.max(axis=0)
    span = np.maximum(mx - mn, 1e-6)
    pad = 0.06 * span.max()
    mn = mn - pad
    mx = mx + pad
    span = mx - mn
    scale = (size - 1) / span.max()
    # center
    mid = (mn + mx) * 0.5
    px = (xy - mid) * scale + (size - 1) * 0.5
    # flip Y for image coords
    img_pts = np.empty_like(px)
    img_pts[:, 0] = px[:, 0]
    img_pts[:, 1] = (size - 1) - px[:, 1]

    mask = np.zeros((size, size), dtype=np.uint8)
    tris = img_pts[faces].astype(np.float32)
    # cv2.fill one triangle at a time is slow; batch via approx polylines
    for tri in tris:
        cv2.fillConvexPoly(mask, np.round(tri).astype(np.int32), 255)
    return mask


def render_ship_silhouette(glb: Path, size: int = RENDER_SIZE) -> np.ndarray:
    mesh = load_mesh(glb)
    R = rot_y(MODEL_YAW_DEG)
    v = (mesh.vertices.astype(np.float64) @ R.T)
    faces = mesh.faces.astype(np.int32)
    # center
    c = v.mean(axis=0)
    v0 = v - c
    # longest axis after yaw — used only for framing distance
    extent = v0.max(axis=0) - v0.min(axis=0)
    radius = float(np.linalg.norm(extent) * 0.5)
    cam_dir = CAM_DIR / (np.linalg.norm(CAM_DIR) + 1e-12)
    eye = cam_dir * (radius * 2.4)
    basis = look_at_basis(eye, np.zeros(3), np.array([0.0, 1.0, 0.0]))
    v_cam = (v0 - eye) @ basis.T
    return rasterize_silhouette(v_cam, faces, size=size)


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


def has_transparent_background(im: Image.Image, min_clear_frac: float = 0.25) -> bool:
    """Reject opaque/solid-bg icons; market ship art uses alpha."""
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    a = np.array(im.split()[-1])
    clear = float(np.mean(a < 16))
    opaque = float(np.mean(a > 200))
    # need meaningful clear area AND some solid ship body
    return clear >= min_clear_frac and opaque >= 0.02


def alpha_boundary_mask(im: Image.Image, size: int = ICON_SIZE) -> np.ndarray | None:
    """Silhouette from alpha edge only (opaque vs transparent junction)."""
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    if not has_transparent_background(im):
        return None
    a = np.array(im.split()[-1])
    # hard mask from alpha — boundary = ship outline against clear bg
    mask = (a > 24).astype(np.uint8) * 255
    ys, xs = np.where(mask > 0)
    if len(xs) < 40:
        return None
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop = mask[y0:y1, x0:x1]
    h, w = crop.shape
    side = max(h, w)
    pad = np.zeros((side, side), dtype=np.uint8)
    oy, ox = (side - h) // 2, (side - w) // 2
    pad[oy : oy + h, ox : ox + w] = crop
    out = cv2.resize(pad, (size, size), interpolation=cv2.INTER_NEAREST)
    _, out = cv2.threshold(out, 127, 255, cv2.THRESH_BINARY)
    return out


def contour_from_mask(mask: np.ndarray):
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cnts:
        return None
    c = max(cnts, key=cv2.contourArea)
    if cv2.contourArea(c) < 80:
        return None
    return c


def resample_contour(cnt: np.ndarray, n: int = FD_SAMPLES) -> np.ndarray:
    """Uniform arc-length resample → (n, 2) float64."""
    pts = cnt.reshape(-1, 2).astype(np.float64)
    if len(pts) < 3:
        return np.zeros((n, 2), dtype=np.float64)
    # close
    if not np.allclose(pts[0], pts[-1]):
        pts = np.vstack([pts, pts[0]])
    d = np.sqrt(((pts[1:] - pts[:-1]) ** 2).sum(axis=1))
    s = np.concatenate([[0.0], np.cumsum(d)])
    total = float(s[-1])
    if total < 1e-6:
        return np.zeros((n, 2), dtype=np.float64)
    samples = np.linspace(0.0, total, n, endpoint=False)
    x = np.interp(samples, s, pts[:, 0])
    y = np.interp(samples, s, pts[:, 1])
    return np.stack([x, y], axis=1)


def fourier_curve_desc(cnt: np.ndarray, n: int = FD_SAMPLES, keep: int = FD_KEEP) -> np.ndarray | None:
    """Complex Fourier descriptors of the closed edge curve (scale/start normalized).

    Describes the boundary as a periodic complex function z(t)=x+iy; low-frequency
    coeffs capture the global outline used for matching.
    """
    pts = resample_contour(cnt, n)
    if float(np.ptp(pts)) < 1e-6:
        return None
    z = pts[:, 0] + 1j * pts[:, 1]
    z = z - z.mean()
    scale = np.sqrt(np.mean(np.abs(z) ** 2))
    if scale < 1e-9:
        return None
    z = z / scale
    Z = np.fft.fft(z)
    # drop DC; take next `keep` coeffs; rotate so arg(Z[1])≈0 (start-point invariant)
    if abs(Z[1]) > 1e-12:
        Z = Z * np.exp(-1j * np.angle(Z[1]))
    # use complex coeffs 1..keep as real/imag vector (rotation partially fixed by phase)
    coeffs = Z[1 : keep + 1]
    # magnitude+phase-aligned complex → real vector; also keep mag for stability
    feat = np.concatenate([np.real(coeffs), np.imag(coeffs), np.abs(coeffs)])
    feat = feat / (np.linalg.norm(feat) + 1e-12)
    return feat.astype(np.float64)


def curve_distance(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a - b))


def list_item_icons() -> list[dict]:
    meta = json.loads(ASSET_META.read_text(encoding="utf-8"))
    out = []
    for it in meta:
        path = it.get("path", "")
        if not path.startswith("gui_v1/icon/item/") or not path.endswith(".ktx"):
            continue
        icon_id = Path(path).stem
        stem = it.get("stem", "")
        src = TEX_DIR / f"{stem}.ktx"
        if not src.is_file():
            continue
        out.append({"icon_id": icon_id, "path": path, "stem": stem, "src": src})
    return out


def build_icon_sil_cache(force: bool = False) -> dict[str, dict]:
    """icon_id -> meta. Only transparent-bg icons; sil from alpha boundary."""
    SIL_ICONS.mkdir(parents=True, exist_ok=True)
    index_path = SIL_ICONS / "_index.json"
    if index_path.exists() and not force:
        idx = json.loads(index_path.read_text(encoding="utf-8"))
        # old cache without transparent filter / fd — rebuild if marker missing
        if idx and next(iter(idx.values())).get("transparent") is True:
            return idx

    icons = list_item_icons()
    index: dict[str, dict] = {}
    ok = 0
    skip = 0
    skip_opaque = 0
    for i, it in enumerate(icons):
        if i % 200 == 0:
            print(
                f"  icons {i}/{len(icons)} ok={ok} skip={skip} opaque={skip_opaque}",
                flush=True,
            )
        im = decode_ktx(it["src"])
        if im is None:
            skip += 1
            continue
        if not has_transparent_background(im):
            skip_opaque += 1
            continue
        sil = alpha_boundary_mask(im, ICON_SIZE)
        if sil is None:
            skip += 1
            continue
        cnt = contour_from_mask(sil)
        if cnt is None:
            skip += 1
            continue
        fd = fourier_curve_desc(cnt)
        if fd is None:
            skip += 1
            continue
        png = SIL_ICONS / f"{it['icon_id']}.png"
        Image.fromarray(sil).save(png)
        # store descriptor alongside for fast preload
        np.save(SIL_ICONS / f"{it['icon_id']}.fd.npy", fd)
        index[it["icon_id"]] = {
            "sil": str(png.relative_to(OUT)).replace("\\", "/"),
            "stem": it["stem"],
            "src": str(it["src"]),
            "logic": it["path"],
            "transparent": True,
        }
        ok += 1
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"icon sil cache: ok={ok} skip={skip} opaque={skip_opaque} -> {index_path}")
    return index


def preload_icon_curves(index: dict[str, dict]) -> list[tuple[str, np.ndarray]]:
    """Load Fourier curve descriptors for all transparent icons."""
    out: list[tuple[str, np.ndarray]] = []
    for i, icon_id in enumerate(index.keys()):
        if i % 500 == 0:
            print(f"  preload curves {i}/{len(index)}", flush=True)
        npy = SIL_ICONS / f"{icon_id}.fd.npy"
        if npy.exists():
            fd = np.load(npy)
        else:
            png = SIL_ICONS / f"{icon_id}.png"
            if not png.exists():
                continue
            mask = np.array(Image.open(png).convert("L"))
            _, mask = cv2.threshold(mask, 127, 255, cv2.THRESH_BINARY)
            cnt = contour_from_mask(mask)
            if cnt is None:
                continue
            fd = fourier_curve_desc(cnt)
            if fd is None:
                continue
            np.save(npy, fd)
        out.append((icon_id, fd))
    print(f"  curves ready: {len(out)}")
    return out


def decode_icon_rgba(icon_id: str, index: dict) -> Image.Image | None:
    meta = index.get(icon_id)
    if not meta:
        return None
    im = decode_ktx(Path(meta["src"]))
    if im is None or not has_transparent_background(im):
        return None
    return im.convert("RGBA")


def match_ship(
    ship_sil: np.ndarray,
    icon_curves: list[tuple[str, np.ndarray]],
    top_k: int,
) -> list[tuple[str, float]]:
    cnt = contour_from_mask(ship_sil)
    if cnt is None:
        return []
    ship_fd = fourier_curve_desc(cnt)
    if ship_fd is None:
        return []
    scored: list[tuple[str, float]] = []
    for icon_id, fd in icon_curves:
        d = curve_distance(ship_fd, fd)
        if math.isnan(d) or math.isinf(d):
            continue
        scored.append((icon_id, d))
    scored.sort(key=lambda x: x[1])
    if not scored:
        return []
    best = scored[0][1]
    kept = []
    for icon_id, d in scored:
        if len(kept) >= top_k:
            break
        if d <= best * SCORE_RATIO or d <= SCORE_ABS_MAX:
            kept.append((icon_id, d))
        elif len(kept) < 3:
            kept.append((icon_id, d))
        else:
            break
    return kept


def write_candidates(
    model_key: str,
    zh_name: str,
    matches: list[tuple[str, float]],
    index: dict[str, dict],
) -> list[dict]:
    folder = f"{model_key}__{zh_name}" if zh_name else model_key
    dest = CAND_DIR / folder
    legacy = CAND_DIR / model_key
    if legacy.exists() and legacy.is_dir() and legacy != dest:
        for old in legacy.glob("*"):
            if old.is_file():
                old.unlink()
        try:
            legacy.rmdir()
        except OSError:
            pass
    if dest.exists():
        for old in dest.glob("*"):
            if old.is_file():
                old.unlink()
    else:
        dest.mkdir(parents=True, exist_ok=True)

    POOL_DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    for rank, (icon_id, score) in enumerate(matches, start=1):
        im = decode_icon_rgba(icon_id, index)
        if im is None:
            continue
        # transparent only — no dark composite baked into files
        pool_rgba = POOL_DIR / f"{icon_id}.png"
        if not pool_rgba.exists():
            im.save(pool_rgba)
        fname = f"{rank:02d}_d{score:.4f}_{icon_id}.png"
        out = dest / fname
        im.save(out)
        rows.append(
            {
                "rank": rank,
                "icon_id": icon_id,
                "score": score,
                "file": fname,
                "pool": pool_rgba.name,
                "logic": index[icon_id]["logic"],
            }
        )
    (dest / "README.txt").write_text(
        f"{model_key} / {zh_name}\n"
        "Edge-curve (Fourier) match on transparent alpha boundary only.\n"
        "Files are RGBA with clear background. Use portrait_pick_gui.py to choose.\n",
        encoding="utf-8",
    )
    return rows


def validate_against_selections(icon_curves: list[tuple[str, np.ndarray]], top_k: int = 24) -> None:
    """Report rank of user-confirmed icon_id for each selected ship (algorithm QA)."""
    sel_path = OUT / "selections.json"
    if not sel_path.exists():
        print("no selections.json — skip validation")
        return
    sel = json.loads(sel_path.read_text(encoding="utf-8"))
    print("=== validate vs your selections ===")
    for key, row in sorted(sel.items()):
        if row.get("status") != "ok" or not row.get("icon_id"):
            continue
        glb = SHIPS_GLB / f"{key}.glb"
        if not glb.is_file():
            print(f"  {key}: missing glb")
            continue
        sil = render_ship_silhouette(glb, RENDER_SIZE)
        matches = match_ship(sil, icon_curves, top_k=max(top_k, 50))
        want = str(row["icon_id"])
        rank = next((i + 1 for i, (iid, _) in enumerate(matches) if iid == want), None)
        # also search full list if not in top
        if rank is None:
            cnt = contour_from_mask(sil)
            ship_fd = fourier_curve_desc(cnt) if cnt is not None else None
            if ship_fd is not None:
                full = sorted(
                    ((iid, curve_distance(ship_fd, fd)) for iid, fd in icon_curves),
                    key=lambda x: x[1],
                )
                rank = next((i + 1 for i, (iid, _) in enumerate(full) if iid == want), None)
                score = next((d for iid, d in full if iid == want), None)
            else:
                score = None
        else:
            score = matches[rank - 1][1]
        print(f"  {key}: want={want} rank={rank} score={score}")


# keep old names used by render path
def contour_feature(mask: np.ndarray):
    return contour_from_mask(mask)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ships", default="", help="comma model_keys, empty=all 40")
    ap.add_argument("--top", type=int, default=DEFAULT_TOP_K)
    ap.add_argument("--skip-icons-cache", action="store_true", help="rebuild icon sil cache")
    ap.add_argument("--icons-only", action="store_true")
    ap.add_argument("--ships-only", action="store_true")
    ap.add_argument("--validate-only", action="store_true", help="only rank vs selections.json")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    SIL_SHIPS.mkdir(parents=True, exist_ok=True)
    CAND_DIR.mkdir(parents=True, exist_ok=True)

    keys = {k.strip() for k in args.ships.split(",") if k.strip()} or None
    ships = roster(keys)
    print(f"ships to process: {len(ships)}")

    # rebuild cache if forced OR old cache lacks transparent marker
    force_cache = args.skip_icons_cache
    if not args.ships_only:
        print("building icon silhouette cache (transparent alpha boundary)…")
        index = build_icon_sil_cache(force=force_cache)
    else:
        index = json.loads((SIL_ICONS / "_index.json").read_text(encoding="utf-8"))

    if args.icons_only:
        return 0

    print("preloading edge-curve descriptors…")
    icon_curves = preload_icon_curves(index)

    if args.validate_only:
        validate_against_selections(icon_curves, top_k=args.top)
        return 0

        # refresh shared pool files for newly matched icons
        import shutil

        if POOL_DIR.exists():
            shutil.rmtree(POOL_DIR)
        POOL_DIR.mkdir(parents=True, exist_ok=True)

    validate_against_selections(icon_curves, top_k=args.top)

    report = {
        "camera": CAM_DIR.tolist(),
        "model_yaw_deg": MODEL_YAW_DEG,
        "matcher": "fourier_edge_curve_transparent",
        "ships": {},
    }
    for row in ships:
        key = row["model_key"]
        print(f"render+match {key} ({row['name']})…", flush=True)
        if not row["glb"].is_file():
            print(f"  MISSING glb {row['glb']}")
            report["ships"][key] = {"error": "missing_glb"}
            continue
        sil = render_ship_silhouette(row["glb"], RENDER_SIZE)
        sil_path = SIL_SHIPS / f"{key}.png"
        Image.fromarray(sil).save(sil_path)
        matches = match_ship(sil, icon_curves, top_k=args.top)
        cands = write_candidates(key, row["name"], matches, index)
        folder = f"{key}__{row['name']}"
        report["ships"][key] = {
            "id": row["id"],
            "name": row["name"],
            "type_id": row["type_id"],
            "folder": folder,
            "silhouette": str(sil_path.relative_to(OUT)).replace("\\", "/"),
            "candidates": cands,
        }
        print(f"  -> {len(cands)} candidates in {CAND_DIR / folder}")

    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"report -> {REPORT}")
    print(f"manual prune folders -> {CAND_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
