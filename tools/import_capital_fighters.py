# -*- coding: utf-8 -*-
"""Import carrier fighter §0 GLBs from PC GR2 (mesh+UV) + real *_d/*_n albedo/normal."""
from __future__ import annotations

import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc" / "vendor" / "blendergranny-main"))

from assimp_convert import convert as assimp_convert  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402
from rewrite_visual_maps import main as rewrite_visual_maps  # noqa: E402
from stage_fighter_threeviews import (  # noqa: E402
	Gr2Meshes,
	auto_orient,
	pick_best_mesh_with_uv,
)

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
PC_PNG = Path(r"H:\game_dev\eveautochess-design\docs\_review\pc_png_mirror\dx9\model\ship")

FIGHTERS = [
	("equite", "amarr", "afi1", "res:/dx9/model/ship/amarr/fighter/afi1/afi1_t1.gr2"),
	("locust", "caldari", "cfi1", "res:/dx9/model/ship/caldari/fighter/cfi1/cfi1_t1.gr2"),
	("satyr", "gallente", "gfi1", "res:/dx9/model/ship/gallente/fighter/gfi1/gfi1_t1.gr2"),
	("gram", "minmatar", "mfi1", "res:/dx9/model/ship/minmatar/fighter/mfi1/mfi1_t1.gr2"),
]


def write_obj(path: Path, verts: np.ndarray, faces: np.ndarray, uvs: np.ndarray) -> None:
	with path.open("w", encoding="utf-8") as f:
		f.write("# fighter import with UV\n")
		for v in verts:
			f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
		for uv in uvs:
			f.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
		for tri in faces:
			## OBJ is 1-based; pair each corner with its UV index (same as vert).
			a, b, c = int(tri[0]) + 1, int(tri[1]) + 1, int(tri[2]) + 1
			f.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")


def copy_real_maps(out_dir: Path, race: str, hull: str) -> None:
	src_dir = PC_PNG / race / "fighter" / hull
	d_src = src_dir / f"{hull}_t1_d.png"
	n_src = src_dir / f"{hull}_t1_n.png"
	if not d_src.is_file():
		raise FileNotFoundError(f"missing diffuse {d_src}")
	out_dir.mkdir(parents=True, exist_ok=True)
	shutil.copy2(d_src, out_dir / "albedo.png")
	print(f"  albedo <- {d_src.name} ({d_src.stat().st_size} B)")
	if n_src.is_file():
		shutil.copy2(n_src, out_dir / "normal.png")
		print(f"  normal <- {n_src.name} ({n_src.stat().st_size} B)")
	else:
		print(f"  WARN no normal at {n_src}")


def ensure_placeholder_albedo(out_dir: Path, tint: tuple[int, int, int]) -> None:
	## Only if real maps missing — never overwrite a real albedo with flat tint.
	dst = out_dir / "albedo.png"
	if dst.is_file() and dst.stat().st_size > 4096:
		return
	im = Image.new("RGBA", (256, 256), (*tint, 255))
	im.save(dst)


def import_one(key: str, race: str, hull: str, res_path: str) -> None:
	print(f"== {key}")
	gr2 = fetch_resfile(res_path)
	g = Gr2Meshes(gr2)
	_name, verts, faces, uvs = pick_best_mesh_with_uv(g)
	verts = auto_orient(verts, faces)
	out_dir = PACKS / key
	out_dir.mkdir(parents=True, exist_ok=True)
	glb = out_dir / "model.glb"
	with tempfile.TemporaryDirectory(prefix="fighter_") as td:
		obj = Path(td) / f"{key}.obj"
		write_obj(obj, verts, faces, uvs)
		assimp_convert(obj, glb, "glb2")
	print(f"  glb {glb.stat().st_size} verts={len(verts)} tris={len(faces)} uvs={len(uvs)}")
	try:
		copy_real_maps(out_dir, race, hull)
	except FileNotFoundError as e:
		print(f"  FALLBACK placeholder albedo: {e}")
		tints = {
			"equite": (180, 160, 120),
			"locust": (120, 150, 180),
			"satyr": (120, 170, 130),
			"gram": (170, 120, 110),
		}
		ensure_placeholder_albedo(out_dir, tints.get(key, (140, 140, 140)))


def main() -> int:
	for key, race, hull, res in FIGHTERS:
		try:
			import_one(key, race, hull, res)
		except Exception as e:
			print(f"FAIL {key}: {e}")
			return 1
	rewrite_visual_maps()
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
