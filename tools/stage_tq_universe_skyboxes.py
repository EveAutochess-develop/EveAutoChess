# -*- coding: utf-8 -*-
"""Copy full TQ universe skybox suite + build region↔skybox map."""
from __future__ import annotations

import csv
import io
import json
import re
import struct
import shutil
import urllib.request
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eve_pc.resfile_index import _load_index, fetch_resfile

OUT = Path(r"H:\game_dev\eveautochess-design\docs\_review\20260731_confirm\skyboxes_tq")
GODOT_OUT = Path(r"H:\game_dev\eveautochess-dev\godot_project\assets\skyboxes\tq_universe")
VARIANTS = (
    "_cube.dds",
    "_cube_lowdetail.dds",
    "_cube_blur.dds",
    "_cube_refl.dds",
    "_cube.black",
)

NULLSEC_CN = {
    "Period Basis": "贝斯星域",
    "Delve": "绝地之域",
    "Fountain": "源泉之域",
    "Querious": "逑瑞斯星域",
    "Outer Ring": "外环星域",
    "Cloud Ring": "云环星域",
    "Syndicate": "辛迪加",
    "Catch": "卡彻星域",
    "Providence": "普罗维登斯",
    "Stain": "混浊星域",
    "Impass": "绝径星域",
    "Immensea": "伊梅瑟亚",
    "Tenerifis": "特里菲斯",
    "Feythabolis": "非塔波利斯",
    "Esoteria": "埃索特亚",
    "Omist": "欧米斯特",
    "Paragon Soul": "摄魂之域",
    "Detorid": "底特里德",
    "Insmother": "因斯姆尔",
    "Cache": "地窖星域",
    "Scalding Pass": "灼热之径",
    "Wicked Creek": "邪恶湾流",
    "Curse": "柯尔斯",
    "Great Wildlands": "大荒野星域",
    "Venal": "维纳尔星域",
    "Vale of the Silent": "静寂谷星域",
    "Tribute": "特布特星域",
    "Branch": "血脉星域",
    "Deklein": "德克廉星域",
    "Fade": "斐德星域",
    "Pure Blind": "黑渊星域",
    "Tenal": "特纳",
    "Geminate": "对舞之域",
    "Outer Passage": "域外走廊",
    "Etherium Reach": "琉蓝之穹",
    "Kalevala Expanse": "卡勒瓦拉阔地",
    "The Kalevala Expanse": "卡勒瓦拉阔地",
    "Oasa": "欧莎",
    "Cobalt Edge": "钴蓝边域",
    "Malpais": "糟粕之域",
    "Perrigen Falls": "佩利根弗",
    "The Spire": "螺旋之域",
}

REGION_ID_SLUG = {
    "Period Basis": "period_basis",
    "Delve": "delve",
    "Fountain": "fountain",
    "Querious": "querious",
    "Outer Ring": "period_outer_ring",
    "Cloud Ring": "cloud_ring",
    "Syndicate": "syndicate",
    "Catch": "catch",
    "Providence": "providence",
    "Stain": "stain",
    "Impass": "impass",
    "Immensea": "immensea",
    "Tenerifis": "tenerifis",
    "Feythabolis": "feythabolis",
    "Esoteria": "esoteria",
    "Omist": "omist",
    "Paragon Soul": "paragon_soul",
    "Detorid": "detorid",
    "Insmother": "insmother",
    "Cache": "cache",
    "Scalding Pass": "scalding_pass",
    "Wicked Creek": "wicked_creek",
    "Curse": "curse",
    "Great Wildlands": "great_wildlands",
    "Venal": "venal",
    "Vale of the Silent": "vale_of_the_silent",
    "Tribute": "tribute",
    "Branch": "branch",
    "Deklein": "deklein",
    "Fade": "fade",
    "Pure Blind": "pure_blind",
    "Tenal": "tenal",
    "Geminate": "geminate",
    "Outer Passage": "outer_passage",
    "Etherium Reach": "etherium_reach",
    "Kalevala Expanse": "kalevala_expanse",
    "The Kalevala Expanse": "kalevala_expanse",
    "Oasa": "oasa",
    "Cobalt Edge": "cobalt_edge",
    "Malpais": "malpais",
    "Perrigen Falls": "perrigen_falls",
    "The Spire": "the_spire",
}


def nebula_gid_to_stem() -> dict[int, str]:
    g = fetch_resfile("res:/staticdata/graphicids.fsdbinary").read_bytes()
    out: dict[int, str] = {}
    for m in re.finditer(rb"res:/dx9/scene/[Uu]niverse/([A-Za-z0-9]+)_cube", g):
        stem = m.group(1).decode().lower()
        if m.start() < 184:
            continue
        v = struct.unpack_from("<I", g, m.start() - 184)[0]
        if 11780 <= v <= 26200:
            out[v] = stem
    return out


def list_universe_stems() -> list[str]:
    idx = _load_index()
    stems = set()
    for k in idx:
        m = re.search(r"scene/universe/([a-z0-9]+)_cube", k)
        if m:
            stems.add(m.group(1))
    return sorted(stems)


def ensure_map_regions_csv() -> Path:
    dst = OUT / "mapRegions.csv"
    if not dst.is_file():
        url = "https://www.fuzzwork.co.uk/dump/latest/csv/mapRegions.csv"
        req = urllib.request.Request(url, headers={"User-Agent": "eveautochess-dev"})
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(urllib.request.urlopen(req, timeout=120).read())
    return dst


def copy_stem(stem: str) -> dict:
    stem_dir = OUT / "universe" / stem
    stem_dir.mkdir(parents=True, exist_ok=True)
    godot_dir = GODOT_OUT / stem
    godot_dir.mkdir(parents=True, exist_ok=True)
    files = {}
    for suf in VARIANTS:
        res = f"res:/dx9/scene/universe/{stem}{suf}"
        try:
            src = fetch_resfile(res)
        except Exception as e:
            files[suf] = {"status": "fail", "error": str(e)}
            continue
        name = f"{stem}{suf}"
        dst = stem_dir / name
        if not dst.is_file() or dst.stat().st_size != src.stat().st_size:
            shutil.copy2(src, dst)
        gdst = godot_dir / name
        if not gdst.is_file() or gdst.stat().st_size != src.stat().st_size:
            shutil.copy2(src, gdst)
        files[suf] = {"status": "ok", "bytes": dst.stat().st_size, "res": res}
    return files


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    GODOT_OUT.mkdir(parents=True, exist_ok=True)
    ensure_map_regions_csv()
    gid_map = nebula_gid_to_stem()
    rows = list(
        csv.DictReader(
            io.StringIO((OUT / "mapRegions.csv").read_text(encoding="utf-8-sig"))
        )
    )

    region_rows = []
    for r in rows:
        name = r["regionName"]
        nid = int(r["nebula"])
        stem = gid_map.get(nid, "")
        region_rows.append(
            {
                "eve_region_id": int(r["regionID"]),
                "name_en": name,
                "name_zh": NULLSEC_CN.get(name, ""),
                "region_id": REGION_ID_SLUG.get(name, ""),
                "nebula_graphic_id": nid,
                "skybox_stem": stem,
                "skybox_key": f"{stem}_cube" if stem else "",
                "in_nullsec_pool": name in NULLSEC_CN,
            }
        )

    (OUT / "region_skybox_map.json").write_text(
        json.dumps(region_rows, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (OUT / "nebula_gid_to_stem.json").write_text(
        json.dumps(gid_map, indent=2), encoding="utf-8"
    )

    stems = list_universe_stems()
    report = {"stems": {}, "ok": 0, "fail": 0}
    for i, stem in enumerate(stems, 1):
        print(f"[{i}/{len(stems)}] {stem}", flush=True)
        files = copy_stem(stem)
        report["stems"][stem] = files
        if all(v.get("status") == "ok" for v in files.values()):
            report["ok"] += 1
        else:
            report["fail"] += 1
            print("  partial", {k: v.get("status") for k, v in files.items()})

    (OUT / "REPORT.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    nullsec = [r for r in region_rows if r["in_nullsec_pool"]]
    missing = [r for r in nullsec if not r["skybox_stem"]]
    print(
        f"done stems ok={report['ok']}/{len(stems)} nullsec={len(nullsec)} missing_sky={len(missing)}"
    )
    print("OUT", OUT)
    print("GODOT", GODOT_OUT)


if __name__ == "__main__":
    main()
