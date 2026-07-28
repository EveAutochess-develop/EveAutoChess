# -*- coding: utf-8 -*-
from __future__ import annotations

import json
from pathlib import Path

root = Path(r"H:\game_dev\eveautochess-dev\godot_project")
ships_dir = root / "data" / "ships"
unmanned = root / "data" / "unmanned_units"
packs = root / "assets" / "models" / "ships"
portraits = root / "assets" / "ui" / "portraits"

vm = json.loads((root / "data/visual_meshes.json").read_text(encoding="utf-8")).get("ships", {})
tex = json.loads((root / "data/ship_textures.json").read_text(encoding="utf-8")).get("ships", {})
port = json.loads((root / "data/ship_portraits.json").read_text(encoding="utf-8")).get("ships", {})


def exists_res(path: str) -> bool:
    if not path:
        return False
    return (root / path.replace("res://", "")).is_file()


rows = []
for p in sorted(ships_dir.glob("*.json"), key=lambda x: int(x.stem)):
    d = json.loads(p.read_text(encoding="utf-8"))
    sid = str(d["id"])
    key = d.get("model_key") or ""
    pack = packs / key if key else None
    has_glb = bool(pack and (pack / "model.glb").is_file())
    has_alb = bool(pack and (pack / "albedo.png").is_file())
    pp = port.get(sid, "")
    has_port = exists_res(pp) if pp else bool(key and (portraits / f"{key}.png").is_file())
    mesh_ok = has_glb or exists_res(vm.get(sid, ""))
    tex_ok = has_alb or exists_res(tex.get(sid, ""))
    rows.append(
        {
            "id": int(sid),
            "name": d.get("name"),
            "key": key,
            "mesh": mesh_ok,
            "tex": tex_ok,
            "port": has_port,
            "pack": bool(pack and pack.is_dir()),
            "kind": "ship",
            "files": sorted(x.name for x in pack.iterdir()) if pack and pack.is_dir() else [],
        }
    )

for p in sorted(unmanned.glob("*.json")):
    d = json.loads(p.read_text(encoding="utf-8"))
    if "id" not in d:
        continue
    sid = str(d["id"])
    key = d.get("model_key") or ""
    pack = packs / key if key else None
    has_glb = bool(pack and (pack / "model.glb").is_file())
    has_alb = bool(pack and (pack / "albedo.png").is_file())
    has_port = bool(key and (portraits / f"{key}.png").is_file())
    rows.append(
        {
            "id": int(sid),
            "name": d.get("name"),
            "key": key,
            "mesh": has_glb,
            "tex": has_alb,
            "port": has_port,
            "pack": bool(pack and pack.is_dir()),
            "kind": "drone",
            "files": sorted(x.name for x in pack.iterdir()) if pack and pack.is_dir() else [],
        }
    )

complete = [r for r in rows if r["mesh"] and r["tex"] and r["port"]]
mesh_tex = [r for r in rows if r["mesh"] and r["tex"]]
tex_only = [r for r in rows if r["tex"] and not r["mesh"]]
mesh_only = [r for r in rows if r["mesh"] and not r["tex"]]
port_only = [r for r in rows if r["port"] and not (r["mesh"] and r["tex"])]

pack_names = sorted(p.name for p in packs.iterdir() if p.is_dir()) if packs.is_dir() else []
drop_in_ok = drop_in_partial = drop_empty = 0
std_names = {"model.glb", "albedo.png", "normal.png"}
nonstd = []
for pn in pack_names:
    p = packs / pn
    names = {x.name for x in p.iterdir() if x.is_file() and not x.name.endswith(".import")}
    has_m = "model.glb" in names
    has_a = "albedo.png" in names
    if has_m and has_a:
        drop_in_ok += 1
    elif has_m or has_a or names:
        drop_in_partial += 1
    else:
        drop_empty += 1
    extra = sorted(n for n in names if n not in std_names and not n.endswith(".import"))
    if extra:
        nonstd.append((pn, extra))

cn_folders = [n for n in pack_names if any(ord(c) > 127 for c in n)]
keys = [r["key"] for r in rows if r["key"]]
pinyin_prefix = sum(1 for k in keys if k.startswith(("am_", "jdl_", "glt_", "mmte_", "wrj_", "lhky_")))
english_ccp = []  # punisher / raven style
for k in keys:
    if k and k.replace("_", "").isalpha() and not k.startswith(("am_", "jdl_", "glt_", "mmte_", "wrj_", "lhky_")):
        english_ccp.append(k)

# model root layout
model_root = root / "assets/models"
top = []
for c in sorted(model_root.iterdir()) if model_root.is_dir() else []:
    if c.is_dir():
        top.append((c.name, sum(1 for _ in c.rglob("*") if _.is_file())))
    elif c.is_file():
        top.append((c.name, "file"))

# citadel / buildings
building_hits = []
for pat in ["*citadel*", "*Citadel*", "*station*", "*structure*", "*building*", "*主堡*", "*建筑*"]:
    building_hits.extend((root / "assets").rglob(pat))
building_hits = sorted({str(h.relative_to(root)) for h in building_hits})

# portraits naming
port_files = sorted(p.name for p in portraits.glob("*.png")) if portraits.is_dir() else []
port_pinyin = sum(1 for n in port_files if n.startswith(("am_", "jdl_", "glt_", "mmte_", "wrj_")))
port_other = [n for n in port_files if not n.startswith(("am_", "jdl_", "glt_", "mmte_", "wrj_"))]

lines = []
lines.append("## 资产齐全度统计报告")
lines.append("")
lines.append("### 1. 三项齐全（模型+贴图+立绘）")
lines.append(f"- 统计单位：舰 JSON {sum(1 for r in rows if r['kind']=='ship')} + 无人 {sum(1 for r in rows if r['kind']=='drone')} = {len(rows)}")
lines.append(f"- 三项齐全：{len(complete)}")
lines.append(f"- 模型+贴图（可不含立绘）：{len(mesh_tex)}")
lines.append(f"- 仅贴图无模型：{len(tex_only)}")
lines.append(f"- 仅模型无贴图：{len(mesh_only)}")
lines.append(f"- 有立绘但不齐：{len(port_only)}")
lines.append(f"- 有模型：{sum(1 for r in rows if r['mesh'])}")
lines.append(f"- 有贴图：{sum(1 for r in rows if r['tex'])}")
lines.append(f"- 有立绘：{sum(1 for r in rows if r['port'])}")
lines.append("")
lines.append("三项齐全清单：")
for r in complete:
    lines.append(f"  {r['id']}\t{r['name']}\t{r['key']}\t{r['kind']}")
lines.append("")
lines.append("仅贴图无模型（常见于 §7.6 stub）：")
for r in tex_only:
    lines.append(f"  {r['id']}\t{r['name']}\t{r['key']}")
lines.append("")
lines.append("### 2. 目录结构")
lines.append(f"- 舰包根目录：`assets/models/ships/{{model_key}}/`")
lines.append(f"- 现有舰包文件夹数：{len(pack_names)}")
lines.append(f"- 是否一舰一文件夹：是（按 model_key 分夹）")
lines.append(f"- models 根下子目录：{top}")
lines.append(f"- 中文文件夹名数量：{len(cn_folders)}")
lines.append("")
lines.append("### 3. 即放即用（§0：model.glb + albedo.png [+ normal.png]）")
lines.append(f"- 满足 mesh+albedo：{drop_in_ok}")
lines.append(f"- 半包（只有贴图或只有模）：{drop_in_partial}")
lines.append(f"- 空包：{drop_empty}")
lines.append(f"- 非标准额外文件样例：{nonstd[:8]}")
lines.append("")
lines.append("### 4. 命名（拼音 vs 英文）")
lines.append(f"- model_key 使用种族拼音前缀(am_/jdl_/glt_/mmte_/wrj_)：{pinyin_prefix}/{len(keys)}")
lines.append(f"- 非此前缀的 ASCII key：{english_ccp[:20]} (count={len(english_ccp)})")
lines.append(f"- 立绘文件数：{len(port_files)}；拼音键文件：{port_pinyin}；其它：{port_other[:15]}")
lines.append("- 结论：未改回 CCP 英文文件标识；仍是 Echoes 拼音键架构（am_chengfazhe 等）")
lines.append("")
lines.append("### 5. 建筑/主堡")
lines.append(f"- assets 下 citadel/station/structure/building 命中：{len(building_hits)}")
for h in building_hits[:30]:
    lines.append(f"  {h}")
lines.append("")

out = Path(r"H:\game_dev\eveautochess-dev\tools\_asset_completeness_report.txt")
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"triple={len(complete)} mesh_tex={len(mesh_tex)} packs={len(pack_names)} drop_in={drop_in_ok}")
print("wrote", out)
