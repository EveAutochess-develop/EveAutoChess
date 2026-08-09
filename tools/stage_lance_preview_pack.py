# -*- coding: utf-8 -*-
"""Stage TQ Lance (长枪) icons + FX texture candidates + SDE stats for eyeball confirm.

Outputs:
  eveautochess-design/docs/_review/lance_preview/
  eveautochess-dev/godot_project/assets/vfx/lance/
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(r"H:\game_dev\eveautochess-dev")
DESIGN = Path(r"H:\game_dev\eveautochess-design")
sys.path.insert(0, str(ROOT / "tools"))

from eve_pc.dds_decode import save_png  # noqa: E402
from eve_pc.resfile_index import fetch_resfile  # noqa: E402

REVIEW = DESIGN / "docs" / "_review" / "lance_preview"
GODOT_TEX = ROOT / "godot_project" / "assets" / "vfx" / "lance"
SDE_MODULES = DESIGN / "docs" / "_extracted" / "pc_client_sde_3448696" / "modules_all.json"

RES_REF = re.compile(rb"res:/[A-Za-z0-9_./\-]+\.(?:dds|png|gr2|black)", re.I)

## Racial titan/super lances (group Super Weapon) — TQ icons are *lance.png.
RACIAL_LANCES = [
    {
        "type_id": 40631,
        "race": "amarr",
        "code": "A",
        "damage": "em",
        "icon": "res:/ui/texture/icons/modules/amarrlance.png",
        "fx_black": "res:/fisfx/module/modular_damagebeam_a_st_t1a.black",
        "tint": [1.0, 0.82, 0.28, 1.0],
    },
    {
        "type_id": 41439,
        "race": "caldari",
        "code": "C",
        "damage": "kinetic",
        "icon": "res:/ui/texture/icons/modules/caldarilance.png",
        "fx_black": "res:/fisfx/module/modular_damagebeam_c_st_t1a.black",
        "tint": [0.35, 0.72, 1.0, 1.0],
    },
    {
        "type_id": 41440,
        "race": "gallente",
        "code": "G",
        "damage": "thermal",
        "icon": "res:/ui/texture/icons/modules/gallentelance.png",
        "fx_black": "res:/fisfx/module/modular_damagebeam_g_st_t1a.black",
        "tint": [0.35, 1.0, 0.55, 1.0],
    },
    {
        "type_id": 41441,
        "race": "minmatar",
        "code": "M",
        "damage": "explosive",
        "icon": "res:/ui/texture/icons/modules/minmatarlance.png",
        "fx_black": "res:/fisfx/module/modular_damagebeam_m_st_t1a.black",
        "tint": [1.0, 0.42, 0.12, 1.0],
    },
]

DISRUPTIVE_LANCES = [77398, 77399, 77400, 77401]

## Prepare-phase FX (aiming/charge telegraph before damagebeam fire).
PREPARE_FX = [
    {
        "id": "modular_indicatorbeam_st_t1a",
        "black": "res:/fisfx/module/modular_indicatorbeam_st_t1a.black",
    },
    {
        "id": "modular_indicatorbeamactivation_st_t1a",
        "black": "res:/fisfx/module/modular_indicatorbeamactivation_st_t1a.black",
    },
    {
        "id": "superweaponcylinder",
        "black": "res:/ui/inflight/tactical/superweaponcylinder.black",
        "fallback_tex": "res:/texture/sprite/softwhite2_harsh.dds",
    },
    {
        "id": "superweaponcone",
        "black": "res:/ui/inflight/tactical/superweaponcone.black",
        "fallback_tex": "res:/texture/sprite/softwhite2_harsh.dds",
    },
]

## Extra fire candidates removed from parallel columns (kept out of preview columns).
EXTRA_FX_IDS_LEGACY = (
    "damagebeam_generic",
    "doomsday_slash",
    "drifter_superweapon",
    "drifter_superweapon_xl",
    "tactical_cylinder",
    "tactical_cone",
    "tactical_slice",
)

## Prefer these stems when picking a "beam" texture from a black's refs.
BEAM_PREF = (
    "beam",
    "laser",
    "lightning",
    "gradient",
    "whitesharp",
    "caustic",
    "plasma",
    "softwhite",
    "headlight",
    "white",
)


def _refs_in_black(raw: bytes) -> list[str]:
    return sorted({m.group(0).decode("ascii", "ignore") for m in RES_REF.finditer(raw)})


def _pick_beam_tex(refs: list[str]) -> list[str]:
    dds = [r for r in refs if r.lower().endswith(".dds")]
    scored: list[tuple[int, str]] = []
    for r in dds:
        low = r.lower()
        score = 0
        for i, key in enumerate(BEAM_PREF):
            if key in low:
                score = 100 - i
                break
        if "normal" in low or "_n.dds" in low or "warp_n" in low:
            score -= 50
        scored.append((score, r))
    scored.sort(key=lambda t: (-t[0], t[1]))
    # Keep top unique stems for parallel review.
    out: list[str] = []
    seen: set[str] = set()
    for _s, r in scored:
        stem = Path(r).stem.lower()
        if stem in seen:
            continue
        seen.add(stem)
        out.append(r)
        if len(out) >= 4:
            break
    return out


def _copy_png_icon(res_path: str, dst: Path) -> bool:
    src = Path(fetch_resfile(res_path))
    dst.parent.mkdir(parents=True, exist_ok=True)
    # ResFiles hashes drop the .png suffix — detect by magic / declared path.
    head = src.read_bytes()[:8] if src.exists() else b""
    if head.startswith(b"\x89PNG") or res_path.lower().endswith(".png") or src.suffix.lower() == ".png":
        shutil.copy2(src, dst)
        return dst.exists() and dst.stat().st_size > 0
    return bool(save_png(src, dst, max_dim=512))


def _extract_fx_bundle(
    fx_id: str,
    black_res: str,
    out_dir: Path,
    godot_dir: Path,
    extra_tex: list[str] | None = None,
) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    godot_dir.mkdir(parents=True, exist_ok=True)
    black_path = Path(fetch_resfile(black_res))
    shutil.copy2(black_path, out_dir / Path(black_res).name)
    refs = _refs_in_black(black_path.read_bytes())
    (out_dir / "refs.json").write_text(
        json.dumps(refs, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    tex_written: list[str] = []
    primary = ""
    candidates = _pick_beam_tex(refs)
    if extra_tex:
        for t in extra_tex:
            if t not in candidates:
                candidates.append(t)
    for res in candidates:
        stem = Path(res).stem
        try:
            src = Path(fetch_resfile(res))
            dst = out_dir / f"{stem}.png"
            ok = save_png(src, dst, max_dim=1024)
            if not ok:
                print(f"  dds fail {res}")
                continue
            shutil.copy2(dst, godot_dir / f"{stem}.png")
            tex_written.append(stem)
            if not primary:
                primary = f"res://assets/vfx/lance/{fx_id}/{stem}.png"
        except Exception as e:
            print(f"  tex fail {res}: {e}")
    return {
        "id": fx_id,
        "black": black_res,
        "textures": tex_written,
        "primary": primary,
        "refs_n": len(refs),
    }


def _sde_row(type_id: int, modules: dict) -> dict:
    row = modules.get(str(type_id), {})
    attrs = row.get("attrs") if isinstance(row.get("attrs"), dict) else {}
    return {
        "type_id": type_id,
        "name_en": row.get("nameEN", ""),
        "name_zh": row.get("nameZH") or row.get("nameZH_SDE", ""),
        "group": row.get("groupName", ""),
        "group_zh": row.get("groupNameZH", ""),
        "em": attrs.get("emDamage", row.get("emDamage")),
        "thermal": attrs.get("thermalDamage", row.get("thermalDamage")),
        "kinetic": attrs.get("kineticDamage", row.get("kineticDamage")),
        "explosive": attrs.get("explosiveDamage", row.get("explosiveDamage")),
        "max_range": attrs.get("maxRange", row.get("maxRange")),
        "duration_ms": attrs.get("duration", row.get("duration")),
        "capacitor_need": attrs.get("capacitorNeed", row.get("capacitorNeed")),
        "power": attrs.get("power", row.get("power")),
        "cpu": attrs.get("cpu", row.get("cpu")),
        "dogma_raw": row.get("dogmaRaw", {}),
    }


def main() -> int:
    REVIEW.mkdir(parents=True, exist_ok=True)
    GODOT_TEX.mkdir(parents=True, exist_ok=True)
    modules = json.loads(SDE_MODULES.read_text(encoding="utf-8"))

    icons_dir = REVIEW / "icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    racial_report = []
    for lance in RACIAL_LANCES:
        race = lance["race"]
        icon_dst = icons_dir / f"{race}_lance.png"
        ok = _copy_png_icon(lance["icon"], icon_dst)
        shutil.copy2(icon_dst, GODOT_TEX / f"icon_{race}.png") if icon_dst.exists() else None
        fx = _extract_fx_bundle(
            f"damagebeam_{lance['code'].lower()}",
            lance["fx_black"],
            REVIEW / "fx" / f"damagebeam_{lance['code'].lower()}",
            GODOT_TEX / f"damagebeam_{lance['code'].lower()}",
        )
        gicon = GODOT_TEX / f"icon_{race}.png"
        if icon_dst.exists():
            shutil.copy2(icon_dst, gicon)
        stats = _sde_row(int(lance["type_id"]), modules)
        racial_report.append(
            {
                **lance,
                "icon_ok": ok and icon_dst.exists(),
                "icon_rel": f"icons/{race}_lance.png",
                "godot_icon": f"res://assets/vfx/lance/icon_{race}.png",
                "fx": fx,
                "stats": stats,
            }
        )
        print(f"[racial] {race} icon={ok and icon_dst.exists()} fx_tex={fx['textures']}")

    disruptive = [_sde_row(tid, modules) for tid in DISRUPTIVE_LANCES]

    prepare_report = []
    prep_godot = GODOT_TEX / "prepare"
    prep_review = REVIEW / "fx" / "prepare"
    prep_godot.mkdir(parents=True, exist_ok=True)
    prep_review.mkdir(parents=True, exist_ok=True)
    for prep in PREPARE_FX:
        fx = _extract_fx_bundle(
            prep["id"],
            prep["black"],
            prep_review / prep["id"],
            prep_godot / prep["id"],
            extra_tex=[prep["fallback_tex"]] if prep.get("fallback_tex") else None,
        )
        # Shared extras useful for telegraph.
        for extra in (
            "res:/texture/sprite/y_positive_ramp_01.dds",
            "res:/texture/sprite/headlight.dds",
            "res:/texture/sprite/softwhite2_harsh.dds",
            "res:/texture/fx/gradients/lasergradient_01a.dds",
        ):
            stem = Path(extra).stem.lower()
            if stem in fx.get("textures", []):
                continue
            try:
                src = Path(fetch_resfile(extra))
                if src.stat().st_size < 500:
                    continue
                dst = prep_godot / prep["id"] / f"{stem}.png"
                save_png(src, dst)
                shutil.copy2(dst, prep_review / prep["id"] / dst.name)
                fx.setdefault("textures", []).append(stem)
            except Exception as exc:  # noqa: BLE001
                print(f"  prep extra fail {extra}: {exc}")
        prepare_report.append({**prep, "fx": fx})
        print(f"[prepare] {prep['id']} tex={fx.get('textures')}")

    # Drop legacy extra FX dirs from earlier parallel-candidate packs.
    for eid in EXTRA_FX_IDS_LEGACY:
        for root in (REVIEW / "fx" / eid, GODOT_TEX / eid):
            if root.exists():
                shutil.rmtree(root, ignore_errors=True)
                print(f"[clean] removed {root}")

    stats_doc = {
        "note": "TQ Super Weapon · Lance head-4. Fire=modular_damagebeam_*; "
        "Prepare=modular_indicatorbeam* + superweaponcylinder.",
        "racial_lances": racial_report,
        "disruptive_lances": disruptive,
        "prepare_fx": prepare_report,
    }
    (REVIEW / "STATS.json").write_text(
        json.dumps(stats_doc, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    races_json = {
        r["race"]: {
            "type_id": r["type_id"],
            "code": r["code"],
            "damage": r["damage"],
            "tint": r["tint"],
            "name_zh": r["stats"]["name_zh"],
            "name_en": r["stats"]["name_en"],
            "icon": r["godot_icon"],
            "beam": r["fx"]["primary"],
            "label": f"{r['stats']['name_zh']} · {r['race']}",
        }
        for r in racial_report
    }
    (GODOT_TEX / "races.json").write_text(
        json.dumps(races_json, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    columns = []
    for r in racial_report:
        columns.append(
            {
                "id": f"racial_{r['code'].lower()}",
                "label": r["stats"]["name_zh"] or r["race"],
                "sub": r["stats"]["name_en"],
                "tint": r["tint"],
                "icon": r["godot_icon"],
                "beam": r["fx"]["primary"],
                "kind": "racial_damagebeam",
            }
        )
    (GODOT_TEX / "preview_columns.json").write_text(
        json.dumps({"columns": columns}, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    shutil.copy2(GODOT_TEX / "preview_columns.json", REVIEW / "preview_columns.json")

    manifest = {
        "pack": "lance_preview",
        "godot_scene": "res://scenes/lance_fx_preview.tscn",
        "stats": "STATS.json",
        "racial_n": len(racial_report),
        "extra_n": 0,
        "note": "Four racial Lance columns only (table head-4) for eyeball confirm.",
    }
    (REVIEW / "MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    readme = """# 长枪 Lance · 素材确认包

## 双击打开 Godot 预览

[`打开长枪特效预览.bat`](打开长枪特效预览.bat) → `res://scenes/lance_fx_preview.tscn`

- 仅表头四族装备（立绘 + `modular_damagebeam_*`）
- **准备阶段**：`modular_indicatorbeam*` + `superweaponcylinder`（预览内 准备↔开火 循环）
- 窗口化启动；贴图走磁盘直读（不依赖 `.import`，避免卡死）
- 相机：WASD 移动 · QE 升降 · RF 俯仰 · TG 偏航 · Shift 加速 · Space 暂停 · 1/2 切阶段

## 本包内容

| 项 | 说明 |
|----|------|
| `icons/*_lance.png` | TQ 四族长枪立绘 |
| `STATS.json` | SDE 数值（四族 + Disruptive 参考） |
| `fx/damagebeam_{a,c,g,m}/` | 开火光束贴图 |
| `fx/prepare/` | 准备阶段 indicator / activation / cylinder |

## TQ 溯源（仅保留）

| typeID | 中文 | 英文 | 主伤 |
|--------|------|------|------|
| 40631 | "神圣命运"电磁长枪 | Holy Destiny Electromagnetic Lance | EM |
| 41439 | "铁矛"动能长枪 | Iron Pike Kinetic Lance | Kinetic |
| 41440 | "费拉里卡"热能长枪 | Phalarica Thermal Lance | Thermal |
| 41441 | "吉拉沃"爆炸长枪 | Geiravor Explosive Lance | Explosive |

开火：`res:/fisfx/module/modular_damagebeam_{a|c|g|m}_st_t1a.black`  
准备：`modular_indicatorbeam_st_t1a` · `modular_indicatorbeamactivation_st_t1a` · `superweaponcylinder`

> 玩法口径（无畏装备 / 贯穿棋盘柱状 AOE）待你确认特效后再写入设计专文。
"""
    (REVIEW / "README.md").write_text(readme, encoding="utf-8")

    bat = REVIEW / "打开长枪特效预览.bat"
    bat.write_text(
        """@echo off
chcp 65001 >nul
setlocal
set "GODOT=H:\\game_dev\\eveautochess-dev\\tools\\godot\\Godot_v4.7.1-stable_win64.exe"
set "PROJ=H:\\game_dev\\eveautochess-dev\\godot_project"
set "SCENE=res://scenes/lance_fx_preview.tscn"
if not exist "%GODOT%" (
  echo [ERROR] Godot not found: %GODOT%
  pause
  exit /b 1
)
echo Opening lance FX preview (windowed, 4 racial only)...
echo   %SCENE%
echo Camera: WASD  QE  RF pitch  TG yaw  Shift boost
REM --windowed avoids project fullscreen; textures load from disk in script (no .import wait).
start "" "%GODOT%" --path "%PROJ%" --windowed --resolution 1600x900 "%SCENE%"
endlocal
""",
        encoding="utf-8",
    )
    print(f"OK review={REVIEW}")
    print(f"OK godot={GODOT_TEX}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
