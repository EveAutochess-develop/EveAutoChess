# -*- coding: utf-8 -*-
"""Rewrite runtime visual manifests and canonical asset index."""
from __future__ import annotations

import json
from pathlib import Path

from ship_canonical_index import OUT as CANONICAL_JSON
from ship_canonical_index import build_index

ROOT = Path(__file__).resolve().parents[1] / "godot_project"
SHIPS = ROOT / "data" / "ships"
UNMANNED = ROOT / "data" / "unmanned_units"
PACKS = ROOT / "assets" / "models" / "ships"
MESH_JSON = ROOT / "data" / "visual_meshes.json"
TEX_JSON = ROOT / "data" / "ship_textures.json"


def _roster_jsons() -> list[Path]:
    files = list(SHIPS.glob("*.json")) + list(UNMANNED.glob("*.json"))
    return sorted(files, key=lambda x: int(json.loads(x.read_text(encoding="utf-8")).get("id") or x.stem))


def main() -> None:
    meshes: dict[str, str] = {}
    tex: dict[str, str] = {}
    for p in _roster_jsons():
        d = json.loads(p.read_text(encoding="utf-8"))
        sid = str(d.get("id") or p.stem)
        key = (d.get("model_key") or "").strip()
        if not key:
            continue
        pack = PACKS / key
        glb = pack / "model.glb"
        alb = pack / "albedo.png"
        if glb.is_file() and glb.stat().st_size > 500:
            meshes[sid] = f"res://assets/models/ships/{key}/model.glb"
        if alb.is_file() and alb.stat().st_size > 500:
            tex[sid] = f"res://assets/models/ships/{key}/albedo.png"
    MESH_JSON.write_text(json.dumps({"ships": meshes}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    TEX_JSON.write_text(json.dumps({"ships": tex}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    canonical = build_index()
    CANONICAL_JSON.parent.mkdir(parents=True, exist_ok=True)
    CANONICAL_JSON.write_text(json.dumps(canonical, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"meshes={len(meshes)} textures={len(tex)} "
        f"canonical_ids={len(canonical['by_id'])} canonical_names={len(canonical['by_name_en'])}"
    )


if __name__ == "__main__":
    main()
