# -*- coding: utf-8 -*-
"""Import ORE mining hulls + Excavator §0 GLB with UVs + PC albedo bake.

UV: TQ ship GR2 uses stride-32 verts; UV is float16 pair at bytes 28..31.
Orientation: auto_orient (length→X, bow@minX) then remap to Godot (bow@minZ/−Z forward).
Engine anchors: stern vertex clusters → engine_anchors.json (ShipUnit local after normalize).
"""
from __future__ import annotations

import json
import struct
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from bake_pc_textures import bake_bundle_for_res_path  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from rewrite_visual_maps import main as rewrite_visual_maps  # noqa: E402
from stage_mining_threeviews import Gr2Meshes, auto_orient  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
MESH_JSON = ROOT / "godot_project" / "data" / "visual_meshes.json"
PORTRAIT_SRC = Path(r"H:\game_dev\eveautochess-design\docs\_review\mining_assets_confirm\portraits")
PORTRAIT_DST = ROOT / "godot_project" / "assets" / "ui" / "portraits"
CAPITAL_PORTRAIT_DST = ROOT / "godot_project" / "assets" / "ui" / "ship_portraits_capital"

HULLS = [
    # Retriever hull GR2 is oreba2; shared barge maps live under oreba_t1_*.dds
    ("lhky_huixuanzhe", "res:/dx9/model/ship/ore/barge/oreba2/oreba2_t1.gr2", "res:/dx9/model/ship/ore/barge/oreba_t1.gr2"),
    ("lhky_haitun", "res:/dx9/model/ship/ore/battleship/oreb1/oreb1_t1.gr2", ""),
    ("lhky_nijijing", "res:/dx9/model/ship/ore/freighter/orefr1/orefr1_t1.gr2", ""),
    ("lhky_changxujing", "res:/dx9/model/ship/ore/capital/orecs1/orecs1_t1.gr2", ""),
    ("wrj_ore_excavator", "res:/dx9/model/drone/ore/heavy/oredh2/oredh2_t1.gr2", ""),
]


def _f16(u: int) -> float:
    return float(np.frombuffer(struct.pack("<H", u & 0xFFFF), dtype="<f2")[0])


def extract_mesh_with_uv(g: Gr2Meshes) -> tuple[str, np.ndarray, np.ndarray, np.ndarray, int]:
    """Return name, verts, faces, uvs(Nx2), stride for best LOD mesh."""
    meshes = g.mesh_list()
    ranked: list[tuple] = []
    for name, off in meshes:
        try:
            verts, faces, uvs, stride = _extract_one(g, off)
            used = np.unique(faces.reshape(-1))
            ext = np.ptp(verts[used], axis=0)
            score = (0 if "LOD" in name.upper() else 1, len(faces), float(ext.max()))
            ranked.append((score, name, verts, faces, uvs, stride))
            print(f"  mesh {name!r}: verts={len(verts)} tris={len(faces)} uv={uvs is not None} stride={stride} ext={ext}")
        except Exception as e:
            print(f"  mesh {name!r}: FAIL {e}")
    if not ranked:
        raise RuntimeError("no usable mesh")
    ranked.sort(key=lambda t: t[0], reverse=True)
    _s, name, verts, faces, uvs, stride = ranked[0]
    if uvs is None:
        uvs = np.zeros((len(verts), 2), dtype=np.float64)
    return name, verts, faces, uvs, stride


def _extract_one(g: Gr2Meshes, mesh_off: int) -> tuple[np.ndarray, np.ndarray, np.ndarray | None, int]:
    pvd = g.res(g.u64(mesh_off + 8))
    topo = g.res(g.u64(mesh_off + 28))
    if not pvd or not topo:
        raise RuntimeError("missing PVD/topology")
    vcount, varr = g.aor(pvd.offset + 8)
    if not varr or vcount < 3:
        raise RuntimeError(f"bad vertex array count={vcount}")

    i16_count, i16_arr = g.aor(topo.offset + 24)
    if not i16_arr or i16_count < 3:
        i32_count, i32_arr = g.aor(topo.offset + 12)
        if not i32_arr or i32_count < 3:
            raise RuntimeError("no indices")
        idx = np.frombuffer(
            g.data[i32_arr.offset : i32_arr.offset + i32_count * 4], dtype="<u4"
        ).astype(np.int32)
    else:
        idx = np.frombuffer(
            g.data[i16_arr.offset : i16_arr.offset + i16_count * 2], dtype="<u2"
        ).astype(np.int32)

    usable = len(idx) - (len(idx) % 3)
    faces_all = idx[:usable].reshape(-1, 3)
    faces_all = faces_all[(faces_all < vcount).all(axis=1)]

    best = None
    for stride in (32, 28, 24, 36, 40, 48, 20, 16, 12):
        need = vcount * stride
        if varr.offset + need > len(g.data):
            continue
        blob = g.data[varr.offset : varr.offset + need]
        arr = np.frombuffer(blob, dtype="<f4")
        fpp = stride // 4
        verts = arr.reshape(-1, fpp)[:vcount, :3].astype(np.float64)
        if not np.isfinite(verts).all():
            continue
        faces = faces_all
        mag = np.linalg.norm(verts, axis=1)
        sane = mag < 1e6
        if int(sane.sum()) < 32:
            continue
        p50 = float(np.median(mag[sane]))
        keep = mag <= max(p50 * 8.0, 50.0)
        faces = faces[keep[faces].all(axis=1)]
        if len(faces) < 32:
            continue
        e1 = np.linalg.norm(verts[faces[:, 0]] - verts[faces[:, 1]], axis=1)
        e2 = np.linalg.norm(verts[faces[:, 1]] - verts[faces[:, 2]], axis=1)
        e3 = np.linalg.norm(verts[faces[:, 2]] - verts[faces[:, 0]], axis=1)
        emax = np.maximum(np.maximum(e1, e2), e3)
        med = float(np.median(emax))
        if med < 1e-4 or med > 5000.0:
            continue
        faces = faces[emax <= med * 6.0]
        if len(faces) < 32:
            continue
        uvs = _try_uvs(blob, vcount, stride)
        score = (med, -len(faces), 0 if uvs is not None else 1)
        if best is None or score < (best[0], -best[1], best[5]):
            best = (med, len(faces), verts, faces, uvs, 0 if uvs is not None else 1, stride)
    if best is None:
        raise RuntimeError("no usable stride")
    _med, _n, verts, faces, uvs, _uvmiss, stride = best
    print(f"    stride={stride} edge_med={_med:.3f} tris={_n} has_uv={uvs is not None}")
    return verts, faces, uvs, stride


def _try_uvs(blob: bytes, vcount: int, stride: int) -> np.ndarray | None:
    if stride >= 16:
        # Prefer float16 UV at end of vertex (common TQ / SWTOR-like packing).
        u16 = np.frombuffer(blob, dtype="<u2").reshape(vcount, stride // 2)
        raw = u16[:, -2:].copy()
        uvs = raw.view("<f2").astype(np.float64).reshape(vcount, 2)
        if np.isfinite(uvs).all():
            span = float((uvs[:, 0].max() - uvs[:, 0].min()) + (uvs[:, 1].max() - uvs[:, 1].min()))
            if 0.05 < span < 20.0 and float(np.median(np.abs(uvs))) < 8.0:
                # Godot/Assimp often expect V flipped vs EVE.
                uvs = uvs.copy()
                uvs[:, 1] = 1.0 - uvs[:, 1]
                return uvs
    if stride >= 20 and stride % 4 == 0:
        fpp = stride // 4
        arr = np.frombuffer(blob, dtype="<f4").reshape(vcount, fpp)
        for i in range(3, fpp - 1):
            u = arr[:, i]
            v = arr[:, i + 1]
            if not (np.isfinite(u).all() and np.isfinite(v).all()):
                continue
            if u.min() < -2 or u.max() > 3 or v.min() < -2 or v.max() > 3:
                continue
            span = float((u.max() - u.min()) + (v.max() - v.min()))
            if span < 0.05:
                continue
            out = np.column_stack([u, 1.0 - v]).astype(np.float64)
            return out
    return None


def to_godot_axes(verts: np.ndarray) -> np.ndarray:
    """auto_orient → X=length (bow@minX), Y=up, Z=beam. Remap to Z=length (bow@minZ)."""
    return np.column_stack([verts[:, 2], verts[:, 1], verts[:, 0]]).astype(np.float64)


def _merge_nearby(vals: list[float], min_sep: float) -> list[float]:
	if not vals:
		return []
	ordered = sorted(vals)
	out = [ordered[0]]
	for v in ordered[1:]:
		if abs(v - out[-1]) >= min_sep:
			out.append(v)
		else:
			out[-1] = 0.5 * (out[-1] + v)
	return out


def _peaks_1d(vals: np.ndarray, bins: int = 24, min_frac: float = 0.14) -> list[float]:
	if len(vals) < 4:
		return [float(vals.mean())] if len(vals) else [0.0]
	hist, edges = np.histogram(vals, bins=bins)
	thr = max(1, int(hist.max() * min_frac))
	centers = 0.5 * (edges[:-1] + edges[1:])
	peaks: list[float] = []
	for i in range(len(hist)):
		if hist[i] < thr:
			continue
		left = hist[i - 1] if i > 0 else -1
		right = hist[i + 1] if i + 1 < len(hist) else -1
		if hist[i] >= left and hist[i] >= right:
			peaks.append(float(centers[i]))
	return peaks if peaks else [float(vals.mean())]


def engine_anchors_local(verts: np.ndarray, faces: np.ndarray, max_anchors: int = 6) -> list[list[float]]:
	"""Multi-nozzle: extreme-aft verts → X histogram peaks → one anchor per peak."""
	used = np.unique(faces.reshape(-1))
	pts = verts[used]
	z = pts[:, 2]
	z_max = float(z.max())
	z_min = float(z.min())
	span = max(z_max - z_min, 1e-3)
	# True nozzles sit on the extreme aft tip, not the whole stern slab.
	tip = pts[z >= np.percentile(z, 98.5)]
	if len(tip) < 8:
		tip = pts[z >= z_max - span * 0.05]
	if len(tip) < 4:
		c = tip.mean(axis=0) if len(tip) else np.array([0.0, 0.0, z_max])
		return [[float(c[0]), float(max(c[1], 0.0)), float(c[2])]]

	x_ptp = float(np.ptp(tip[:, 0]))
	min_sep = max(x_ptp * 0.14, span * 0.015, 1.0)
	xpeaks = _merge_nearby(_peaks_1d(tip[:, 0], bins=20, min_frac=0.14), min_sep)
	if len(xpeaks) > max_anchors:
		# Keep extremes + evenly subsample middle.
		idx = np.linspace(0, len(xpeaks) - 1, max_anchors).round().astype(int)
		xpeaks = [xpeaks[i] for i in sorted(set(idx.tolist()))]

	half = max(min_sep * 0.55, x_ptp * 0.04, 0.5)
	out: list[list[float]] = []
	for xp in xpeaks:
		near = tip[np.abs(tip[:, 0] - xp) <= half]
		if len(near) < 2:
			near = tip[np.abs(tip[:, 0] - xp).argsort()[: max(4, len(tip) // max(len(xpeaks), 1))]]
		# Prefer the aft-most slice inside this X bin.
		z_cut = float(np.percentile(near[:, 2], 70.0))
		core = near[near[:, 2] >= z_cut]
		if len(core) < 2:
			core = near
		m = core.mean(axis=0)
		out.append([float(m[0]), float(max(m[1], 0.0)), float(m[2])])

	# Drop near-duplicates after averaging.
	dedup: list[list[float]] = []
	for a in out:
		if all(abs(a[0] - b[0]) >= min_sep * 0.7 for b in dedup):
			dedup.append(a)
	if not dedup:
		m = tip.mean(axis=0)
		dedup = [[float(m[0]), float(max(m[1], 0.0)), float(m[2])]]
	return dedup[:max_anchors]


def write_obj(path: Path, verts: np.ndarray, faces: np.ndarray, uvs: np.ndarray) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("# mining import with UV\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for uv in uvs:
            f.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
        for tri in faces:
            a, b, c = int(tri[0]) + 1, int(tri[1]) + 1, int(tri[2]) + 1
            f.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")


def import_one(key: str, res_path: str, tex_res: str = "") -> None:
    print(f"== {key}")
    gr2 = fetch_resfile(res_path)
    g = Gr2Meshes(gr2)
    _name, verts, faces, uvs, _stride = extract_mesh_with_uv(g)
    verts = auto_orient(verts, faces)
    verts = to_godot_axes(verts)
    anchors = engine_anchors_local(verts, faces)
    out_dir = PACKS / key
    out_dir.mkdir(parents=True, exist_ok=True)
    glb = out_dir / "model.glb"
    with tempfile.TemporaryDirectory(prefix="mining_") as td:
        obj = Path(td) / f"{key}.obj"
        write_obj(obj, verts, faces, uvs)
        assimp_convert(obj, glb, "glb2")
    print(f"  glb {glb.stat().st_size} verts={len(verts)} tris={len(faces)} anchors={anchors}")
    (out_dir / "engine_anchors.json").write_text(
        json.dumps({"model_key": key, "anchors_mesh_local": anchors}, indent=2) + "\n",
        encoding="utf-8",
    )
    bake_res = tex_res.strip() or res_path
    try:
        written = bake_bundle_for_res_path(key, bake_res)
        print(f"  textures {', '.join(sorted(written.keys()))} (from {bake_res})")
    except Exception as e:
        print(f"  texture bake WARN: {e}")
    if key == "wrj_ore_excavator":
        side = out_dir / "source_oredh2_t1.gr2"
        side.write_bytes(Path(gr2).read_bytes())
        (out_dir / "ANIM_NOTE.txt").write_text(
            "Static §0 GLB only. TQ NormalLoop+Limb* skin is in source_oredh2_t1.gr2; "
            "import via blendergranny for Skeleton3D+AnimationPlayer.\n",
            encoding="utf-8",
        )


def sync_portraits() -> None:
    PORTRAIT_DST.mkdir(parents=True, exist_ok=True)
    CAPITAL_PORTRAIT_DST.mkdir(parents=True, exist_ok=True)
    mapping = {
        "lhky_haitun.png": PORTRAIT_DST / "lhky_haitun.png",
        "lhky_nijijing.png": PORTRAIT_DST / "lhky_nijijing.png",
        "lhky_changxujing.png": PORTRAIT_DST / "lhky_changxujing.png",
    }
    for src_name, dst in mapping.items():
        src = PORTRAIT_SRC / src_name
        if src.is_file():
            dst.write_bytes(src.read_bytes())
            print(f"  portrait {src_name} -> {dst}")
    # Capital path kept as alias for Rorqual shop cards that already point there.
    cx = PORTRAIT_SRC / "lhky_changxujing.png"
    if cx.is_file():
        (CAPITAL_PORTRAIT_DST / "rorqual.png").write_bytes(cx.read_bytes())
        print("  portrait rorqual capital alias refreshed")


def patch_visual_meshes() -> None:
    if MESH_JSON.is_file():
        data = json.loads(MESH_JSON.read_text(encoding="utf-8"))
    else:
        data = {}
    ships = data.setdefault("ships", data if "ships" not in data else data["ships"])
    if not isinstance(ships, dict):
        ships = {}
        data["ships"] = ships
    for key, _res, _tex in HULLS:
        # Prefer id map rewrite; keep model_key path fallback via rewrite_visual_maps.
        pass
    for key, _res, _tex in HULLS:
        # Also stash by model_key for tooling.
        data.setdefault("by_model_key", {})[key] = f"res://assets/models/ships/{key}/model.glb"
    MESH_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    sync_portraits()
    for key, res, tex_res in HULLS:
        try:
            import_one(key, res, tex_res)
        except Exception as e:
            print(f"FAIL {key}: {e}")
            return 1
    try:
        rewrite_visual_maps()
    except Exception as e:
        print(f"rewrite_visual_maps warn: {e}")
        patch_visual_meshes()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
