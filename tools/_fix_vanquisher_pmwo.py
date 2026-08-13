# -*- coding: utf-8 -*-
"""Fix Angel Vanquisher (tsl_zhengfuzhe) pmwo Material map.

COMBAT.md §14D 征服者上色:
  TQ angt1_t1_m is clustered IDs, not a low histogram that needs a 2–98% stretch.
  Main hull ~170 (0.667) sits on the gold threshold knife-edge; paint ~85; trim ~180;
  empty atlas ~45% with equally bright _a (cannot be the hull mask).

  1) Hull = _m > 8, dilated 2px so island rims stay in-band.
  2) Cluster-map into unity-standard slots. IDs are sRGB u8 such that AFTER
     shader `source_color` (sRGB→linear) they land in gray (>0.35) / gold (>0.68).
     File 118/148 looks "gray" as u8/255 but decodes to 0.18/0.30 → 白模.
     Do NOT percentile-stretch; do NOT fill residuals with 200 (gold).
  3) Outside hull / remaining holes → main-hull gray (mip/UV safe).
  4) Pack Dirt into G; write pmwo.png to Godot + wreck + design preview packs.

Does NOT touch global ship_look thresholds/colors or shader source_color.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools" / "eve_pc")]

from eve_pc.dds_decode import decode_dds  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

KEY = "tsl_zhengfuzhe"
SIZE = (1024, 1024)
GR2 = "res:/dx9/model/ship/angel/titan/angt1/angt1_t1.gr2"
# unity-standard slots as sRGB u8. Shader samples pmwo_tex with source_color,
# so mat_id is linear. threshold2/3 = 0.35/0.68 linear ≈ u8 160 / 215.
# 118/148 decode to ~0.18/0.30 → color2 white × bright albedo = 白模.
ID_PAINT = 175.0   # linear ~0.43 gray
ID_HULL = 198.0    # linear ~0.56 gray
ID_TRIM = 232.0    # linear ~0.81 gold (+metallic ≥0.75)
EMPTY_THR = 8.0


def _srgb8_to_linear(u8: np.ndarray) -> np.ndarray:
	c = np.clip(u8.astype(np.float32) / 255.0, 0.0, 1.0)
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


DESTS = [
	ROOT / "godot_project" / "assets" / "models" / "ships" / KEY,
	ROOT / "godot_project" / "assets" / "models" / "ships" / f"{KEY}_wreck",
	Path(
		r"H:\game_dev\eveautochess-design\docs\_review\preview"
		r"\pirate_faction_ships\pc_models"
	)
	/ KEY,
]


def _gray_dds(suffix: str) -> Image.Image:
	folder = Path(GR2.replace("res:/", "")).parent.as_posix()
	stem = Path(GR2).stem
	res = f"res:/{folder}/{stem}{suffix}.dds"
	path = Path(fetch_resfile(res))
	im = decode_dds(path)
	if im is None:
		raise RuntimeError(f"decode failed: {res}")
	g = im.convert("L")
	if g.size != SIZE:
		g = g.resize(SIZE, Image.Resampling.LANCZOS)
	return g


def _dilate(mask: np.ndarray, iterations: int = 2) -> np.ndarray:
	out = mask.astype(bool)
	for _ in range(iterations):
		up = np.roll(out, -1, axis=0)
		down = np.roll(out, 1, axis=0)
		left = np.roll(out, -1, axis=1)
		right = np.roll(out, 1, axis=1)
		out = out | up | down | left | right
	return out


def _inpaint_empty_material(m: np.ndarray, hull: np.ndarray, empty_thr: float = EMPTY_THR) -> tuple[np.ndarray, int]:
	"""Fill dilated-hull pixels that still have empty Material from nearest valid ID."""
	from scipy import ndimage  # type: ignore

	m = m.astype(np.float32).copy()
	need = hull & (m < empty_thr)
	have = hull & (m >= empty_thr)
	n_need = int(need.sum())
	if n_need == 0 or not have.any():
		return m, 0
	inv = ~have
	_, indices = ndimage.distance_transform_edt(inv, return_distances=True, return_indices=True)
	iy = indices[0]
	ix = indices[1]
	filled = m[iy, ix]
	m[need] = filled[need]
	still = hull & (m < empty_thr)
	m[still] = ID_HULL
	return m, n_need


def _inpaint_empty_material_fallback(m: np.ndarray, hull: np.ndarray, empty_thr: float = EMPTY_THR) -> tuple[np.ndarray, int]:
	"""Pure-numpy multi-pass dilate fill when scipy is unavailable."""
	m = m.astype(np.float32).copy()
	need0 = hull & (m < empty_thr)
	n_need = int(need0.sum())
	if n_need == 0:
		return m, 0
	kernel_offsets = [
		(-1, 0),
		(1, 0),
		(0, -1),
		(0, 1),
		(-1, -1),
		(-1, 1),
		(1, -1),
		(1, 1),
	]
	for _pass in range(64):
		need = hull & (m < empty_thr)
		if not need.any():
			break
		acc = np.zeros_like(m)
		cnt = np.zeros_like(m)
		for dy, dx in kernel_offsets:
			shifted = np.roll(np.roll(m, dy, axis=0), dx, axis=1)
			valid = np.roll(np.roll((m >= empty_thr) & hull, dy, axis=0), dx, axis=1)
			acc += np.where(valid, shifted, 0.0)
			cnt += valid.astype(np.float32)
		fillable = need & (cnt > 0)
		if not fillable.any():
			break
		m[fillable] = acc[fillable] / cnt[fillable]
	still = hull & (m < empty_thr)
	m[still] = ID_HULL
	return m, n_need


def _cluster_map(m_raw: np.ndarray, hull: np.ndarray) -> np.ndarray:
	"""Map Angel titan Material clusters into 4-band slots. No stretch."""
	out = np.full(m_raw.shape, ID_HULL, dtype=np.float32)
	paint = hull & (m_raw >= EMPTY_THR) & (m_raw < 120.0)
	hull_main = hull & (m_raw >= 120.0) & (m_raw < 176.0)
	trim = hull & (m_raw >= 176.0)
	out[paint] = ID_PAINT
	out[hull_main] = ID_HULL
	out[trim] = ID_TRIM
	return out


def main() -> int:
	mat_raw = _gray_dds("_m")
	dirt = _gray_dds("_d")

	m_raw = np.asarray(mat_raw, dtype=np.float32)
	d = np.asarray(dirt, dtype=np.float32)

	hull_core = m_raw > EMPTY_THR
	hull = _dilate(hull_core, 2)
	print(
		f"hull_core={hull_core.mean()*100:.1f}% hull_dilate={hull.mean()*100:.1f}% "
		f"raw_m mean={m_raw.mean():.1f} empty_on_dilate={(hull & (m_raw < EMPTY_THR)).mean()*100:.1f}%"
	)

	try:
		m_filled, n_filled = _inpaint_empty_material(m_raw, hull)
		method = "scipy-edt"
	except Exception as exc:  # noqa: BLE001
		print("scipy unavailable, dilate fallback:", exc)
		m_filled, n_filled = _inpaint_empty_material_fallback(m_raw, hull)
		method = "dilate"
	print(f"inpaint[{method}] filled={n_filled} residual_empty={(hull & (m_filled < EMPTY_THR)).mean()*100:.1f}%")

	m = _cluster_map(m_filled, hull)
	lin = _srgb8_to_linear(m)
	print(
		"shader-linear bands white "
		f"{(lin <= 0.35).mean()*100:.1f}% gray "
		f"{((lin > 0.35) & (lin <= 0.68)).mean()*100:.1f}% gold "
		f"{(lin > 0.68).mean()*100:.1f}% lin_mean={lin.mean():.3f} u8_mean={m.mean():.1f}"
	)

	pmwo = Image.merge(
		"RGBA",
		(
			Image.fromarray(np.clip(m, 0, 255).astype(np.uint8), mode="L"),
			Image.fromarray(np.clip(d, 0, 255).astype(np.uint8), mode="L"),
			Image.new("L", SIZE, 0),
			Image.new("L", SIZE, 255),
		),
	)

	meta = {
		"model_key": KEY,
		"fix": "vanquisher_pmwo_cluster_map",
		"hull_core_frac": float(hull_core.mean()),
		"hull_frac": float(hull.mean()),
		"filled_pixels": int(n_filled),
		"method": method,
		"id_paint": ID_PAINT,
		"id_hull": ID_HULL,
		"id_trim": ID_TRIM,
		"band_white_linear": float((lin <= 0.35).mean()),
		"band_gray_linear": float(((lin > 0.35) & (lin <= 0.68)).mean()),
		"band_gold_linear": float((lin > 0.68).mean()),
		"m_mean": float(m.mean()),
		"lin_mean": float(lin.mean()),
	}
	for dest in DESTS:
		if not dest.exists() and dest.name.endswith("_wreck"):
			print("skip missing", dest)
			continue
		dest.mkdir(parents=True, exist_ok=True)
		out = dest / "pmwo.png"
		pmwo.save(out, "PNG")
		imp = dest / "pmwo.png.import"
		if imp.exists():
			imp.unlink()
		note = dest / "pmwo_fix.json"
		note.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
		print("wrote", out, out.stat().st_size)

	glb = DESTS[0] / "model.glb"
	if glb.is_file():
		_probe_mesh_uv_empty(glb, pmwo)
	return 0


def _probe_mesh_uv_empty(glb: Path, pmwo_img: Image.Image) -> None:
	import struct

	data = glb.read_bytes()
	off = 12
	length = struct.unpack_from("<I", data, 8)[0]
	chunks: list[tuple[bytes, bytes]] = []
	while off + 8 <= length:
		clen, ctype = struct.unpack_from("<I4s", data, off)
		off += 8
		chunks.append((ctype, data[off : off + clen]))
		off += clen
	j = json.loads(chunks[0][1])
	blob = chunks[1][1]
	prim = j["meshes"][0]["primitives"][0]["attributes"]
	acc = j["accessors"][prim["TEXCOORD_0"]]
	bv = j["bufferViews"][acc["bufferView"]]
	base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
	uvs = np.frombuffer(blob, dtype="<f4", count=acc["count"] * 2, offset=base).reshape(acc["count"], 2)
	pm = np.asarray(pmwo_img.convert("RGBA"))
	h, w = pm.shape[:2]
	idx = np.linspace(0, len(uvs) - 1, min(100_000, len(uvs))).astype(int)
	su = uvs[idx]
	x = np.clip((su[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
	y = np.clip((su[:, 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
	lin = _srgb8_to_linear(pm[y, x, 0].astype(np.float32))
	print(
		f"mesh-UV probe (shader linear): white={(lin <= 0.35).mean()*100:.1f}% "
		f"gray={((lin > 0.35) & (lin <= 0.68)).mean()*100:.1f}% "
		f"gold={(lin > 0.68).mean()*100:.1f}% lin_mean={lin.mean():.3f}"
	)


if __name__ == "__main__":
	raise SystemExit(main())
