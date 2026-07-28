# -*- coding: utf-8 -*-
"""Assemble Godot §0 ship bundles from Echoes indexes.

Sources (no NPK re-unpack):
  - ship JSON model_key + optional echoes_item_id
  - asset_library/entities/ships|drones/{key}*/  (identity + textures + mesh)
  - ship_classified/by_key/{key}/meshes/*.obj   (optional → GLB)
  - items_icon_compose_index + items/icons/*.ktx (portraits)

Rules:
  - One folder per model_key: assets/models/ships/{key}/{model.glb,albedo.png,normal.png}
  - Match only assets belonging to that key / item id
  - Missing assets stay empty — no placeholders / no ghost JSON paths
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

import texture2ddecoder
from PIL import Image

from eve_pc.pc_asset_map import canonical_pc_res_path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
GODOT = ROOT / "godot_project"
SHIPS = GODOT / "data" / "ships"
UNMANNED = GODOT / "data" / "unmanned_units"
PACKS = GODOT / "assets" / "models" / "ships"
PORTRAITS = GODOT / "assets" / "ui" / "portraits"
MESH_JSON = GODOT / "data" / "visual_meshes.json"
TEX_JSON = GODOT / "data" / "ship_textures.json"
PORT_JSON = GODOT / "data" / "ship_portraits.json"
MATCH_OUT = GODOT / "data" / "_extracted" / "ship_asset_match_index.json"
REPORT = ROOT / "tools" / "_assemble_match_report.txt"

LIB_SHIPS = Path(r"H:\eve手游\history\asset_library\entities\ships")
LIB_DRONES = Path(r"H:\eve手游\history\asset_library\entities\drones")
LIB_ICONS = Path(r"H:\eve手游\history\asset_library\items\icons")
NAME_ZH = Path(r"H:\eve手游\history\asset_library\indexes\items_id_to_name_zh.json")
COMPOSE = Path(r"H:\eve手游\history\asset_library\indexes\items_icon_compose_index.json")
BY_KEY = Path(r"H:\eve手游\history\1.0.0_unpacked\art_extract\ship_classified\by_key")

NAME_ALIASES = {"弥尔米顿级": "弥洱米顿级", "密尔米顿级": "弥洱米顿级"}

ASTC_BLOCK = {
    0x93B0: (4, 4), 0x93B1: (5, 5), 0x93B2: (5, 6), 0x93B3: (6, 5), 0x93B4: (6, 6),
    0x93B5: (8, 5), 0x93B6: (8, 6), 0x93B7: (8, 8), 0x93B8: (10, 5), 0x93B9: (10, 6),
    0x93BA: (10, 8), 0x93BB: (10, 10), 0x93BC: (12, 10), 0x93BD: (12, 12),
    0x93D0: (4, 4), 0x93D1: (5, 5), 0x93D2: (5, 6), 0x93D3: (6, 5), 0x93D4: (6, 6),
    0x93D5: (8, 5), 0x93D6: (8, 6), 0x93D7: (8, 8), 0x93D8: (10, 5), 0x93D9: (10, 6),
    0x93DA: (10, 8), 0x93DB: (10, 10), 0x93DC: (12, 10), 0x93DD: (12, 12),
}


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


def find_entity_dir(model_key: str, roots: list[Path]) -> Path | None:
    for root in roots:
        if not root.is_dir():
            continue
        exact = root / model_key
        if exact.is_dir():
            return exact
        for p in root.iterdir():
            if p.is_dir() and (p.name == model_key or p.name.startswith(model_key + "__")):
                return p
    return None


def pick_ad_ktx(ent: Path, model_key: str) -> Path | None:
    tex = ent / "textures"
    if not tex.is_dir():
        return None
    preferred = tex / f"{model_key}_ad.ktx"
    if preferred.is_file():
        return preferred
    # same-key variants only (reject skin packs that don't contain key)
    cands = [p for p in tex.glob("*_ad.ktx") if model_key in p.stem]
    return cands[0] if cands else None


def pick_n_ktx(ent: Path, model_key: str) -> Path | None:
    tex = ent / "textures"
    if not tex.is_dir():
        return None
    preferred = tex / f"{model_key}_n.ktx"
    if preferred.is_file():
        return preferred
    cands = [p for p in tex.glob("*_n.ktx") if model_key in p.stem]
    return cands[0] if cands else None


def pick_named_ktx(ent: Path, model_key: str, suffix: str) -> Path | None:
    tex = ent / "textures"
    if not tex.is_dir():
        return None
    preferred = tex / f"{model_key}_{suffix}.ktx"
    if preferred.is_file():
        return preferred
    cands = [p for p in tex.glob(f"*_{suffix}.ktx") if model_key in p.stem]
    return cands[0] if cands else None


def ensure_textures(model_key: str, ent: Path | None) -> dict:
    out_dir = PACKS / model_key
    out_dir.mkdir(parents=True, exist_ok=True)
    info = {
        "albedo": "", "normal": "", "pmwo": "", "rg": "", "reduction": "",
        "albedo_src": "", "normal_src": "", "pmwo_src": "", "rg_src": "", "reduction_src": "",
    }
    if ent is None:
        return info
    ad = pick_ad_ktx(ent, model_key)
    if ad:
        im = decode_ktx(ad)
        if im is not None:
            if max(im.size) > 1024:
                im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            dst = out_dir / "albedo.png"
            im.convert("RGBA").save(dst)
            info["albedo"] = f"res://assets/models/ships/{model_key}/albedo.png"
            info["albedo_src"] = str(ad)
    nrm = pick_n_ktx(ent, model_key)
    if nrm:
        imn = decode_ktx(nrm)
        if imn is not None:
            if max(imn.size) > 1024:
                imn.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            dstn = out_dir / "normal.png"
            imn.convert("RGBA").save(dstn)
            info["normal"] = f"res://assets/models/ships/{model_key}/normal.png"
            info["normal_src"] = str(nrm)
    for suffix, out_name in [("pmwo", "pmwo.png"), ("rg", "rg.png"), ("reduction", "reduction.png")]:
        ktx = pick_named_ktx(ent, model_key, suffix)
        if not ktx:
            continue
        imx = decode_ktx(ktx)
        if imx is None:
            continue
        if max(imx.size) > 1024:
            imx.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        dstx = out_dir / out_name
        imx.convert("RGBA").save(dstx)
        info[suffix] = f"res://assets/models/ships/{model_key}/{out_name}"
        info[f"{suffix}_src"] = str(ktx)
    return info


def ensure_model(model_key: str) -> dict:
    """Keep existing §0 GLB, or convert classified OBJ. Else leave empty."""
    out_dir = PACKS / model_key
    out_dir.mkdir(parents=True, exist_ok=True)
    dst = out_dir / "model.glb"
    info = {"mesh": "", "mesh_src": ""}
    if dst.is_file() and dst.stat().st_size > 1000:
        info["mesh"] = f"res://assets/models/ships/{model_key}/model.glb"
        info["mesh_src"] = str(dst)
        return info
    # legacy flat glb from older convert
    legacy = PACKS.parent / f"{model_key}.glb"
    if legacy.is_file() and legacy.stat().st_size > 1000:
        shutil.copy2(legacy, dst)
        info["mesh"] = f"res://assets/models/ships/{model_key}/model.glb"
        info["mesh_src"] = str(legacy)
        return info
    # classified OBJ → GLB
    meshes = BY_KEY / model_key / "meshes"
    if meshes.is_dir():
        objs = sorted(meshes.glob("*.obj"))
        if objs:
            try:
                from assimp_convert import convert as assimp_convert

                assimp_convert(objs[0], dst, "glb2")
                if dst.is_file() and dst.stat().st_size > 1000:
                    info["mesh"] = f"res://assets/models/ships/{model_key}/model.glb"
                    info["mesh_src"] = str(objs[0])
                    return info
            except Exception as e:
                info["mesh_error"] = str(e)
                if dst.is_file():
                    dst.unlink()
    # NeoX .mesh → OBJ → GLB (zhouhang95 converter + Assimp)
    ent = find_entity_dir(model_key, [LIB_SHIPS, LIB_DRONES])
    if ent is not None:
        mesh_dir = ent / "mesh"
        if mesh_dir.is_dir():
            preferred = [
                mesh_dir / f"{model_key}_lod1.mesh",
                mesh_dir / f"{model_key}_lod0.mesh",
                mesh_dir / f"{model_key}_lod2.mesh",
            ]
            mesh = next((p for p in preferred if p.is_file() and p.stat().st_size > 1000), None)
            if mesh is None:
                cands = sorted(
                    (p for p in mesh_dir.glob("*.mesh") if p.stat().st_size > 1000),
                    key=lambda x: (0 if "lod1" in x.name else 1 if "lod0" in x.name else 2, x.name),
                )
                mesh = cands[0] if cands else None
            if mesh is not None:
                try:
                    from complete_missing_glb_from_neox import mesh_to_glb

                    mesh_to_glb(mesh, dst)
                    if dst.is_file() and dst.stat().st_size > 1000:
                        info["mesh"] = f"res://assets/models/ships/{model_key}/model.glb"
                        info["mesh_src"] = str(mesh)
                        return info
                except Exception as e:
                    info["mesh_error"] = str(e)
                    if dst.is_file():
                        try:
                            dst.unlink()
                        except OSError:
                            pass
    return info


def load_name_to_ids() -> dict[str, list[int]]:
    raw = json.loads(NAME_ZH.read_text(encoding="utf-8"))
    out: dict[str, list[int]] = {}
    for k, v in raw.items():
        if isinstance(v, str):
            try:
                out.setdefault(v, []).append(int(k))
            except ValueError:
                pass
    return out


def pick_item_id(name: str, ids: list[int], compose_items: dict) -> int | None:
    if not ids:
        return None
    preferred = []
    for iid in ids:
        s = str(iid)
        if s.startswith(("1010", "1011", "1020", "1030", "1040", "1050")):
            preferred.append(iid)
    for iid in preferred or ids:
        it = compose_items.get(str(iid))
        if isinstance(it, dict) and it.get("icon_id"):
            return iid
    return (preferred or ids)[0]


def ensure_portrait(model_key: str, name: str, echoes_item_id: int | None, compose_items: dict, name_map: dict) -> dict:
    PORTRAITS.mkdir(parents=True, exist_ok=True)
    dst = PORTRAITS / f"{model_key}.png"
    info = {"portrait": "", "portrait_src": ""}

    # 1) item icon via echoes_item_id / name
    eids = []
    if echoes_item_id:
        eids.append(int(echoes_item_id))
    lookup = NAME_ALIASES.get(name, name)
    eids.extend(name_map.get(lookup, []) or name_map.get(name, []))
    eid = pick_item_id(name, eids, compose_items)
    if eid is not None:
        it = compose_items.get(str(eid), {})
        icon_candidates: list[Path] = []
        if it.get("icon_id"):
            icon_candidates.append(LIB_ICONS / f"{it['icon_id']}.ktx")
        icon_candidates.append(LIB_ICONS / f"{eid}.ktx")
        base = (it.get("compose") or {}).get("base") or ""
        if base:
            icon_candidates.append(LIB_ICONS / Path(base).name)
        seen: set[str] = set()
        for icon in icon_candidates:
            key2 = str(icon)
            if key2 in seen:
                continue
            seen.add(key2)
            if icon.is_file():
                im = decode_ktx(icon)
                if im is not None:
                    im = im.convert("RGBA")
                    im.thumbnail((256, 256), Image.Resampling.LANCZOS)
                    im.save(dst)
                    info["portrait"] = f"res://assets/ui/portraits/{model_key}.png"
                    info["portrait_src"] = str(icon)
                    info["echoes_item_id"] = eid
                    return info
        # compose base path under art_extract ui?
        if base.startswith("res/"):
            # try unpacked gui
            for root in [
                Path(r"H:\eve手游\history\1.0.0_unpacked\art_extract"),
                Path(r"H:\eve手游\history\asset_library"),
            ]:
                cand = root / base.replace("res/", "", 1)
                if cand.is_file():
                    im = decode_ktx(cand) if cand.suffix.lower() == ".ktx" else Image.open(cand)
                    if im is not None:
                        im = im.convert("RGBA")
                        im.thumbnail((256, 256), Image.Resampling.LANCZOS)
                        im.save(dst)
                        info["portrait"] = f"res://assets/ui/portraits/{model_key}.png"
                        info["portrait_src"] = str(cand)
                        info["echoes_item_id"] = eid
                        return info

    # 2) keep existing portrait only if looks like real art (not tiny flat name-card)
    if dst.is_file():
        try:
            im = Image.open(dst)
            # name-cards ~160x128 avg dark; keep if large enough or many colors
            if im.size[0] >= 128 and im.size[1] >= 96:
                info["portrait"] = f"res://assets/ui/portraits/{model_key}.png"
                info["portrait_src"] = "existing"
                return info
        except Exception:
            pass
        # remove non-matched / bad
        dst.unlink(missing_ok=True)
    return info


def iter_units() -> list[dict]:
    units = []
    for p in sorted(SHIPS.glob("*.json"), key=lambda x: int(x.stem)):
        d = json.loads(p.read_text(encoding="utf-8"))
        units.append(
            {
                "id": int(d["id"]),
                "name": d.get("name", ""),
                "name_en": d.get("name_en", ""),
                "model_key": d.get("model_key", ""),
                "echoes_item_id": d.get("echoes_item_id"),
                "kind": "ship",
                "json_path": p,
            }
        )
    for p in sorted(UNMANNED.glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        if "id" not in d:
            continue
        units.append(
            {
                "id": int(d["id"]),
                "name": d.get("name", ""),
                "name_en": d.get("name_en", ""),
                "model_key": d.get("model_key", ""),
                "echoes_item_id": d.get("echoes_item_id"),
                "kind": "drone",
                "json_path": p,
            }
        )
    return units


def main() -> None:
    compose = json.loads(COMPOSE.read_text(encoding="utf-8"))
    compose_items = compose.get("items", compose)
    name_map = load_name_to_ids()

    mesh_map: dict[str, str] = {}
    tex_map: dict[str, str] = {}
    port_map: dict[str, str] = {}
    match_index: dict[str, dict] = {}
    lines = ["id\tname\tkey\tkind\tmesh\talbedo\tportrait\tlib"]

    for u in iter_units():
        key = str(u["model_key"] or "")
        sid = str(u["id"])
        if not key:
            lines.append(f"{sid}\t{u['name']}\t\t{u['kind']}\tMISS\tMISS\tMISS\tno_key")
            continue
        roots = [LIB_DRONES, LIB_SHIPS] if u["kind"] == "drone" else [LIB_SHIPS, LIB_DRONES]
        ent = find_entity_dir(key, roots)
        tex_info = ensure_textures(key, ent)
        mesh_info = ensure_model(key)
        port_info = ensure_portrait(key, str(u["name"]), u.get("echoes_item_id"), compose_items, name_map)

        if mesh_info["mesh"]:
            mesh_map[sid] = mesh_info["mesh"]
        if tex_info["albedo"]:
            tex_map[sid] = tex_info["albedo"]
        if port_info["portrait"]:
            port_map[sid] = port_info["portrait"]

        # persist echoes_item_id when discovered
        if port_info.get("echoes_item_id") and u["json_path"].is_file():
            d = json.loads(u["json_path"].read_text(encoding="utf-8"))
            if not d.get("echoes_item_id"):
                d["echoes_item_id"] = int(port_info["echoes_item_id"])
                u["json_path"].write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        entry = {
            "id": u["id"],
            "name": u["name"],
            "name_en": u.get("name_en", ""),
            "model_key": key,
            "kind": u["kind"],
            "pc_res_path": canonical_pc_res_path(u),
            "lib_entity": str(ent) if ent else "",
            "mesh": mesh_info.get("mesh", ""),
            "mesh_src": mesh_info.get("mesh_src", ""),
            "albedo": tex_info.get("albedo", ""),
            "albedo_src": tex_info.get("albedo_src", ""),
            "normal": tex_info.get("normal", ""),
            "normal_src": tex_info.get("normal_src", ""),
            "pmwo": tex_info.get("pmwo", ""),
            "pmwo_src": tex_info.get("pmwo_src", ""),
            "rg": tex_info.get("rg", ""),
            "rg_src": tex_info.get("rg_src", ""),
            "reduction": tex_info.get("reduction", ""),
            "reduction_src": tex_info.get("reduction_src", ""),
            "portrait": port_info.get("portrait", ""),
            "portrait_src": port_info.get("portrait_src", ""),
        }
        match_index[sid] = entry
        lines.append(
            f"{sid}\t{u['name']}\t{key}\t{u['kind']}\t"
            f"{'Y' if entry['mesh'] else '-'}\t{'Y' if entry['albedo'] else '-'}\t{'Y' if entry['portrait'] else '-'}\t"
            f"{'Y' if ent else '-'}"
        )
        print(sid, key, "M" if entry["mesh"] else ".", "A" if entry["albedo"] else ".", "P" if entry["portrait"] else ".")

    # citadel note (building — not ship pack schema)
    citadel = {
        "mesh": "res://assets/models/structures/citadel.glb",
        "albedo": "res://assets/textures/structures_png/citadel_d.png",
        "normal": "res://assets/textures/structures_png/citadel_n.png",
        "portrait": "",
    }
    cit_ok = {
        "mesh": (GODOT / "assets/models/structures/citadel.glb").is_file(),
        "albedo": (GODOT / "assets/textures/structures_png/citadel_d.png").is_file(),
        "normal": (GODOT / "assets/textures/structures_png/citadel_n.png").is_file(),
    }
    match_index["citadel"] = {**citadel, "kind": "structure", "present": cit_ok}

    MESH_JSON.write_text(json.dumps({"ships": mesh_map}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    TEX_JSON.write_text(json.dumps({"ships": tex_map}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    PORT_JSON.write_text(json.dumps({"ships": port_map}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    MATCH_OUT.parent.mkdir(parents=True, exist_ok=True)
    MATCH_OUT.write_text(json.dumps(match_index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    n = len([k for k in match_index if k != "citadel"])
    triple = sum(
        1
        for k, e in match_index.items()
        if k != "citadel" and e.get("mesh") and e.get("albedo") and e.get("portrait")
    )
    summary = [
        "",
        f"units={n}",
        f"mesh={len(mesh_map)} albedo={len(tex_map)} portrait={len(port_map)} triple={triple}",
        f"citadel mesh={cit_ok['mesh']} albedo={cit_ok['albedo']}",
        f"wrote {MESH_JSON.name} {TEX_JSON.name} {PORT_JSON.name}",
        f"index {MATCH_OUT}",
    ]
    REPORT.write_text("\n".join(lines + summary) + "\n", encoding="utf-8")
    print("\n".join(summary))


if __name__ == "__main__":
    main()
