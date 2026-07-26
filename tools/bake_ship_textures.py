# -*- coding: utf-8 -*-
"""Bake ship/citadel DDS → ASCII PNG for reliable Godot loads.

DUST/EVE maps (DX10):
  *_a.dds  BC7  — grayscale albedo intensity (use as albedo)
  *_d.dds  BC4  — dark detail / dirt (NOT color diffuse)
  *_n.dds  BC5  — normal
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

import texture2ddecoder
from PIL import Image

PROJ = Path(r"H:/game_dev/eveautochess-dev/godot_project")
SHIPS_SRC = PROJ / "assets/textures/ships"
SHIPS_DST = PROJ / "assets/textures/ships_png"
CITADEL_SRC = PROJ / "assets/textures/structures"
CITADEL_DST = PROJ / "assets/textures/structures_png"
MAP_OUT = PROJ / "data/ship_textures.json"


def _dxgi(data: bytes) -> int | None:
	if data[84:88] != b"DX10" or len(data) < 148:
		return None
	return struct.unpack_from("<I", data, 128)[0]


def _size(data: bytes) -> tuple[int, int]:
	h = struct.unpack_from("<I", data, 12)[0]
	w = struct.unpack_from("<I", data, 16)[0]
	return w, h


def decode_dds(path: Path) -> Image.Image | None:
	data = path.read_bytes()
	if data[:4] != b"DDS ":
		return None
	w, h = _size(data)
	dxgi = _dxgi(data)
	payload = data[148:] if dxgi is not None else data[128:]
	try:
		if dxgi == 98:  # BC7_UNORM
			need = w * h
			dec = texture2ddecoder.decode_bc7(payload[:need], w, h)
			return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
		if dxgi == 80:  # BC4_UNORM
			need = w * h // 2
			dec = texture2ddecoder.decode_bc4(payload[:need], w, h)
			return Image.frombytes("L", (w, h), dec).convert("RGBA")
		if dxgi == 83:  # BC5_UNORM
			need = w * h
			dec = texture2ddecoder.decode_bc5(payload[:need], w, h)
			return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
		if dxgi == 71:  # BC1
			need = w * h // 2
			dec = texture2ddecoder.decode_bc1(payload[:need], w, h)
			return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
		if dxgi == 77:  # BC3
			need = w * h
			dec = texture2ddecoder.decode_bc3(payload[:need], w, h)
			return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
	except Exception as e:
		print("DECODE FAIL", path, e)
		return None
	# Fallback: Pillow (often wrong for DX10)
	try:
		im = Image.open(path)
		return im.convert("RGBA")
	except Exception as e:
		print("PIL FAIL", path, e)
		return None


def _save_png(src: Path, dst: Path) -> bool:
	im = decode_dds(src)
	if im is None:
		return False
	dst.parent.mkdir(parents=True, exist_ok=True)
	im.save(dst, "PNG")
	return True


def _pick_albedo(folder: Path) -> Path | None:
	"""Prefer *_a.dds (BC7 intensity); fall back to *_d.dds."""
	a = next(folder.glob("*_a.dds"), None)
	if a is not None:
		return a
	return next(folder.glob("*_d.dds"), None)


def main() -> None:
	name_to_id: dict[str, int] = {}
	for p in (PROJ / "data/ships").glob("*.json"):
		j = json.loads(p.read_text(encoding="utf-8"))
		name_to_id[j["name"]] = int(j["id"])

	ships_map: dict[str, str] = {}
	SHIPS_DST.mkdir(parents=True, exist_ok=True)
	for folder in SHIPS_SRC.iterdir():
		if not folder.is_dir():
			continue
		stem = folder.name
		sid = name_to_id.get(stem)
		if sid is None:
			print("skip unmapped", stem)
			continue
		a_src = _pick_albedo(folder)
		n_src = next(folder.glob("*_n.dds"), None)
		if a_src is None:
			print("no albedo", stem)
			continue
		d_dst = SHIPS_DST / f"ship_{sid}_d.png"
		if _save_png(a_src, d_dst):
			ships_map[str(sid)] = f"res://assets/textures/ships_png/ship_{sid}_d.png"
			print(stem, a_src.name, "->", d_dst.name)
		if n_src is not None:
			_save_png(n_src, SHIPS_DST / f"ship_{sid}_n.png")

	CITADEL_DST.mkdir(parents=True, exist_ok=True)
	citadel_src: Path | None = None
	for folder in CITADEL_SRC.iterdir():
		if not folder.is_dir():
			continue
		if "空堡" in folder.name:
			citadel_src = _pick_albedo(folder)
			if citadel_src:
				break
	if citadel_src is None:
		cands = list(CITADEL_SRC.rglob("*_a.dds"))
		if not cands:
			cands = list(CITADEL_SRC.rglob("cm1_t10_d.dds"))
		citadel_src = cands[0] if cands else None
	if citadel_src and _save_png(citadel_src, CITADEL_DST / "citadel_d.png"):
		print("citadel", citadel_src.name, "-> citadel_d.png")
		n = citadel_src.with_name(citadel_src.name.replace("_a.", "_n.").replace("_d.", "_n."))
		if n.exists():
			_save_png(n, CITADEL_DST / "citadel_n.png")

	out = {"ships": ships_map, "citadel_diffuse": "res://assets/textures/structures_png/citadel_d.png"}
	MAP_OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
	print("wrote", MAP_OUT, "ships", len(ships_map))


if __name__ == "__main__":
	main()
