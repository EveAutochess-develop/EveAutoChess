# -*- coding: utf-8 -*-
"""Bake PC textures + SOF engine_boosters for the pirate/Sansha/titan preview batch."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "eve_pc"))

from bake_pc_textures import bake_bundle_for_res_path  # noqa: E402
from rewrite_engine_boosters_godot import _aabb_from_hull, _mat_item  # noqa: E402

PACKS = ROOT / "godot_project" / "assets" / "models" / "ships"
HULLS = ROOT / "tools" / "_extracted" / "sof_hull_boosters.json"
REVIEW = Path(
    r"H:\game_dev\eveautochess-design\docs\_review\preview\pirate_faction_ships\pc_models"
)
SOF_RES = "res:/dx9/model/spaceobjectfactory/data.black"

# model_key → (sof_hull, bake_gr2, model_long_axis, zh, en, faction, cls)
BATCH: dict[str, tuple] = {
    "gsts_duxi": ("cf7_t1", "res:/dx9/model/ship/caldari/frigate/cf7/cf7_t1.gr2", 80.0, "毒蜥级", "Worm", "古斯塔斯", "护卫"),
    "gsts_qianlong": ("cc2_t1", "res:/dx9/model/ship/caldari/cruiser/cc2/cc2_t1.gr2", 174.0, "潜龙级", "Gila", "古斯塔斯", "巡洋"),
    "gsts_xiangweishe": ("cb2_t1", "res:/dx9/model/ship/caldari/battleship/cb2/cb2_t1.gr2", 450.0, "响尾蛇级", "Rattlesnake", "古斯塔斯", "战列"),
    "tsl_delamier": ("angf1_t1", "res:/dx9/model/ship/angel/frigate/angf1/angf1_t1.gr2", 80.0, "德拉米尔级", "Dramiel", "天使", "护卫"),
    "tsl_sainabo": ("angbc1_t1", "res:/dx9/model/ship/angel/battlecruiser/angbc1/angbc1_t1.gr2", 200.0, "塞纳波级", "Cynabal", "天使", "巡洋"),
    "tsl_makerui": ("angb1_t1", "res:/dx9/model/ship/angel/battleship/angb1/angb1_t1.gr2", 450.0, "马克瑞级", "Machariel", "天使", "战列"),
    "ts_yemoxia": ("angf2_t1", "res:/dx9/model/ship/angel/frigate/angf2/angf2_t1.gr2", 80.0, "夜魔侠级", "Daredevil", "天蛇", "护卫"),
    "ts_jingti": ("gc4_t1", "res:/dx9/model/ship/gallente/cruiser/gc4/gc4_t1.gr2", 174.0, "警惕级", "Vigilant", "天蛇", "巡洋"),
    "ts_fuchouzhe": ("gb2_t1", "res:/dx9/model/ship/gallente/battleship/gb2/gb2_t1.gr2", 450.0, "复仇者级", "Vindicator", "天蛇", "战列"),
    "jmh_asiteluo": ("soef1_t1", "res:/dx9/model/ship/soe/frigate/soef1/soef1_t1.gr2", 80.0, "阿斯特罗级", "Astero", "姐妹会", "护卫"),
    "jmh_sitexiusi": ("soec1_t1", "res:/dx9/model/ship/soe/cruiser/soec1/soec1_t1.gr2", 174.0, "斯特修斯级", "Stratios", "姐妹会", "巡洋"),
    "jmh_niesituo": ("soeb1_t1", "res:/dx9/model/ship/soe/battleship/soeb1/soeb1_t1.gr2", 450.0, "涅斯托级", "Nestor", "姐妹会", "战列"),
    "xxz_ningxue": ("af8_t1", "res:/dx9/model/ship/amarr/frigate/af8/af8_t1.gr2", 80.0, "凝血级", "Cruor", "血袭者", "护卫"),
    "xxz_ashimu": ("ac6_t1", "res:/dx9/model/ship/amarr/cruiser/ac6/ac6_t1.gr2", 174.0, "阿什姆级", "Ashimmu", "血袭者", "巡洋"),
    "xxz_bagelong": ("ab2_t1", "res:/dx9/model/ship/amarr/battleship/ab2/ab2_t1.gr2", 450.0, "巴戈龙级", "Bhaalgorn", "血袭者", "战列"),
    "mdt_jiamu": ("morf1_t1", "res:/dx9/model/ship/mordu/frigate/morf1/morf1_t1.gr2", 80.0, "加姆级", "Garmur", "莫德团", "护卫"),
    "mdt_aosusi": ("morc1_t1", "res:/dx9/model/ship/mordu/cruiser/morc1/morc1_t1.gr2", 174.0, "奥苏斯级", "Orthrus", "莫德团", "巡洋"),
    "mdt_bagaisi": ("morb1_t1", "res:/dx9/model/ship/mordu/battleship/morb1/morb1_t1.gr2", 450.0, "巴盖斯级", "Barghest", "莫德团", "战列"),
    "ss_monv": ("sf1_t1", "res:/dx9/model/ship/sansha/frigate/sf1/sf1_t1.gr2", 80.0, "魔女级", "Succubus", "萨沙", "护卫"),
    "ss_youling": ("sc1_t1", "res:/dx9/model/ship/sansha/cruiser/sc1/sc1_t1.gr2", 174.0, "幽灵级", "Phantasm", "萨沙", "巡洋"),
    "ss_emeng": ("sb1_t1", "res:/dx9/model/ship/sansha/battleship/sb1/sb1_t1.gr2", 450.0, "噩梦级", "Nightmare", "萨沙", "战列"),
    "ss_revenant": ("sca1_t1", "res:/dx9/model/ship/sansha/carrier/sca1/sca1_t1.gr2", 1100.0, "Revenant", "Revenant", "萨沙", "超航"),
    "jmh_odysseus": ("soebc1_t1", "res:/dx9/model/ship/soe/battlecruiser/soebc1/soebc1_t1.gr2", 280.0, "奥德修斯级", "Odysseus", "姐妹会", "远征指挥"),
    "tsl_zhengfuzhe": ("angt1_t1", "res:/dx9/model/ship/angel/titan/angt1/angt1_t1.gr2", 2200.0, "征服者级", "Vanquisher", "天使", "泰坦"),
}


def write_boosters(model_key: str, sof_hull: str, hulls: dict) -> dict:
    info = hulls.get(sof_hull)
    if info is None:
        for k, v in hulls.items():
            if k.lower() == sof_hull.lower():
                info = v
                sof_hull = k
                break
    if info is None:
        return {"error": f"no sof record {sof_hull}"}
    pack = PACKS / model_key
    pack.mkdir(parents=True, exist_ok=True)
    raw_items = info.get("items") or []
    items_out = [_mat_item(it) for it in raw_items if isinstance(it.get("transform"), list)]
    hull_aabb = _aabb_from_hull(info, raw_items) if raw_items else {
        "position": [0, 0, 0],
        "size": [1, 1, 1],
        "source": "empty",
    }
    payload = {
        "sof_hull": sof_hull,
        "source": SOF_RES,
        "model_key": model_key,
        "always_on": info.get("always_on", False),
        "has_trails": info.get("has_trails", True),
        "space": "sof_hull_native",
        "axis_note": "SOF native. Runtime maps hull_aabb → mesh AABB with Z flipped.",
        "hull_aabb": hull_aabb,
        "items": items_out,
    }
    (pack / "engine_boosters.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return {"sof_hull": sof_hull, "nozzles": len(items_out)}


def mirror_textures(model_key: str) -> None:
    src = PACKS / model_key
    dst = REVIEW / model_key
    dst.mkdir(parents=True, exist_ok=True)
    for name in ("albedo.png", "normal.png", "rg.png", "pmwo.png", "reduction.png",
                 "engine_boosters.json", "textures_pc.txt", "source_pc.json", "model.glb"):
        p = src / name
        if p.is_file():
            (dst / name).write_bytes(p.read_bytes())


def main() -> int:
    hulls = json.loads(HULLS.read_text(encoding="utf-8"))
    report = []
    for key, (sof, gr2, long_axis, zh, en, fac, cls) in BATCH.items():
        row = {
            "model_key": key,
            "zh": zh,
            "en": en,
            "faction": fac,
            "class": cls,
            "sof_hull": sof,
            "model_long_axis": long_axis,
        }
        print(f"\n== bake {key}")
        try:
            written = bake_bundle_for_res_path(key, gr2)
            row["textures"] = written
        except Exception as e:
            row["textures"] = {"error": str(e)}
            print(f"  bake fail: {e}")
        try:
            row["boosters"] = write_boosters(key, sof, hulls)
            print(f"  boosters {row['boosters']}")
        except Exception as e:
            row["boosters"] = {"error": str(e)}
            print(f"  booster fail: {e}")
        # keep long_axis on source_pc
        sp = PACKS / key / "source_pc.json"
        meta = {}
        if sp.is_file():
            meta = json.loads(sp.read_text(encoding="utf-8"))
        meta.update(
            {
                "model_key": key,
                "zh": zh,
                "en": en,
                "faction": fac,
                "class": cls,
                "sof_hull": sof,
                "pc_res_path": gr2,
                "model_long_axis": long_axis,
            }
        )
        sp.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        mirror_textures(key)
        report.append(row)

    out = REVIEW / "BAKE_BATCH.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    # preview ship list for Godot
    preview_list = []
    for i, row in enumerate(report):
        preview_list.append(
            {
                "id": 8000 + i,
                "model_key": row["model_key"],
                "name": row["zh"],
                "name_en": row["en"],
                "race": row["faction"],
                "ship_group": row["class"],
                "model_long_axis": row["model_long_axis"],
                "sof_hull": row["sof_hull"],
            }
        )
    plist = ROOT / "godot_project" / "data" / "dev" / "faction_batch_preview_ships.json"
    plist.parent.mkdir(parents=True, exist_ok=True)
    plist.write_text(json.dumps(preview_list, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nWrote {out} and {plist} ({len(report)} ships)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
