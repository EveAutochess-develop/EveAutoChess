# -*- coding: utf-8 -*-
import json
import hashlib
import shutil
from pathlib import Path

proj = Path(r"H:/game_dev/eveautochess-dev/godot_project")
src = proj / "assets/ui/sprites/ChampionIcons"
dst = proj / "assets/ui/sprites/champ_icons"
dst.mkdir(parents=True, exist_ok=True)
for f in list(dst.iterdir()):
	f.unlink()

name_to_id = {}
for p in (proj / "data/ships").glob("*.json"):
	j = json.loads(p.read_text(encoding="utf-8"))
	name_to_id[j["name"]] = j["id"]

mapping = {}
for f in src.iterdir():
	if f.suffix.lower() not in (".jpg", ".jpeg", ".png"):
		continue
	if f.name.endswith(".meta"):
		continue
	head = f.read_bytes()[:8]
	is_png = head[:4] == b"\x89PNG"
	is_jpg = head[:2] == b"\xff\xd8"
	if is_png:
		ext = ".png"
	elif is_jpg:
		ext = ".jpg"
	else:
		ext = f.suffix.lower()
	stem = f.stem
	if stem in name_to_id:
		ascii_name = f"ship_{name_to_id[stem]}{ext}"
	else:
		h = hashlib.sha1(stem.encode("utf-8")).hexdigest()[:8]
		ascii_name = f"extra_{h}{ext}"
	shutil.copy2(f, dst / ascii_name)
	mapping[stem] = f"res://assets/ui/sprites/champ_icons/{ascii_name}"
	kind = "png" if is_png else ("jpg" if is_jpg else "?")
	print(f"{stem}: magic={kind} -> {ascii_name}")

(proj / "data/champion_icons.json").write_text(
	json.dumps(mapping, ensure_ascii=False, indent=2), encoding="utf-8"
)
print("mapped", len(mapping))
