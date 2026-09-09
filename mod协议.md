# Mod 协议入口 · Mod Protocol Entry

> **本文件唯一职责 / Sole role of this file**  
> 仓根面向 **Agent（兼人读）** 的双语入口与硬门禁摘要。  
> Bilingual root entry for **agents** (humans may read it).  
> **不**另写字段细则；**不**替代权威专文。  
> Does **not** redefine field schemas; does **not** replace authority docs.

| 语言 | 权威字段与目录 | 玩法 / 联机 / 安全 | 主项目 ↔ Mod 协作 |
|------|----------------|-------------------|-------------------|
| 中文 | [`godot_project/docs/MOD_PROTOCOL.md`](godot_project/docs/MOD_PROTOCOL.md) | 仓4 `eveautochess-design/docs/MODS.md` | 仓4 `MOD_DEV_HANDBOOK.md` |
| EN | Same `MOD_PROTOCOL.md` (field names / layout authority) | Same `MODS.md` (rules / netplay / safety) | Same `MOD_DEV_HANDBOOK.md` |

样例包 / sample package：`godot_project/mod_samples/beitou-float-turret/`（机制样例；默认不启用 / mechanism sample; disabled by default）。

---

## 0. Agent 先读 · Agent read-first

### 中文

1. **本仓（EveAutoChess / `eveautochess-dev`）= A 轨**：只提供 **通用 Mod 引擎接口与协议实现**，**禁止**提交某一商业/内容 mod 的舰表、美术、专属硬编码。
2. **字段名、包目录、JSON 形状** → 只认 [`MOD_PROTOCOL.md`](godot_project/docs/MOD_PROTOCOL.md)。
3. **允许/禁止玩法、联机传包、硬拒绝、Lint** → 只认仓4 `MODS.md`。
4. **日常改 mod 内容** → 在 **B 轨内容仓**（如 `eveautochess_sgmod`）迭代；**不要**为单包在本仓写引擎特例。
5. **镜像同步方向**：默认 **主 → mod 镜像**；**禁止**默认把 mod/镜像回写本仓 `godot_project`。
6. 冲突时：**仓4 玩法口径优先于实现猜测**；作者字段以 `MOD_PROTOCOL` 为准；本入口只作导航。

### English

1. **This repo (EveAutoChess / `eveautochess-dev`) = Track A**: generic mod **engine interfaces + protocol only**. Do **not** commit a commercial/content mod’s ship tables, art, or one-off hardcodes here.
2. **Field names, package layout, JSON shape** → [`MOD_PROTOCOL.md`](godot_project/docs/MOD_PROTOCOL.md) only.
3. **Allowed/forbidden gameplay, netplay transfer, hard rejects, lint** → design-repo `MODS.md` only.
4. **Day-to-day mod content** → iterate in a **Track B content repo** (e.g. `eveautochess_sgmod`); do **not** add engine special-cases for one package in this repo.
5. **Mirror sync direction**: default **main → mod mirror**; never silently overwrite this repo’s `godot_project` from a mod/mirror tree.
6. On conflict: **design-repo gameplay rules beat guesswork**; author fields follow `MOD_PROTOCOL`; this file is navigation only.

---

## 1. 包是什么 · What a mod package is

### 中文

- 一个可导入的 **zip 或文件夹**，根上必须有可解析的 `mod.json`（`package_name` 主键）。
- 单位采用 **一文件夹一单位**：`units/ships|unmanned|equipment/<dir>/` + `unit.json`。
- 作者只写 `local_id`（XXXX，0–9999）；运行时 id = `xx * 10000 + XXXX`（`xx` 由安装序分配）。**禁止**手写六位抢 `xx`。
- **禁止**：`.gd` / `.gdshader` / `.dll` / 可执行文件、zip-slip、symlink、覆盖原版同 id 文件。
- FX / 拖尾 / 菜单等：只能走协议允许的 override（克隆官方 kind + 贴图/色参等），**禁止**自定义 shader/脚本粒子。

### English

- An importable **zip or folder** with a parseable root `mod.json` (`package_name` is the primary key).
- Units are **one folder per unit**: `units/ships|unmanned|equipment/<dir>/` + `unit.json`.
- Authors write only `local_id` (XXXX, 0–9999); runtime id = `xx * 10000 + XXXX` (`xx` from install order). Do **not** hand-write six-digit ids to steal `xx`.
- **Forbidden**: `.gd` / `.gdshader` / `.dll` / executables, zip-slip, symlinks, overwriting vanilla files by the same integer id.
- FX / trails / menu: only protocol-allowed overrides (clone official kinds + textures/params). **No** custom shaders or scripted particles.

最小骨架 / minimal skeleton：

```text
mod.json
units/ships/<unit_dir>/unit.json
units/equipment/<unit_dir>/unit.json   # optional
fetters/<id>.json                      # optional
assets/…                               # optional
```

---

## 2. A 轨 vs B 轨 · Track A vs Track B

| | A 轨 · Track A（本仓） | B 轨 · Track B（内容仓） |
|--|------------------------|---------------------------|
| 中文 | 协议实现、`ModManager`、通用解析、联机 digest、机制样例 `mod_samples/` | `mod.json`、单位 JSON、美术、catalog；日常 debug 在此 |
| EN | Protocol impl, `ModManager`, generic resolve, netplay digest, `mod_samples/` | `mod.json`, unit JSON, art, catalog; daily debug here |
| 禁止 / Forbidden | 某 mod 专属舰表/美术进 git；`sg_*` 等专属引擎分支 | 在镜像 `scripts/` 长期手改引擎凑合缺接口 |

扩展协议（新字段 / 新 P 能力）：先书面汇总 → 用户合入 A 轨 → 再镜像给 B 轨。  
To extend the protocol: written handoff → user merges Track A → then mirror to Track B.

---

## 3. Agent 硬禁止 · Hard agent bans

### 中文

- 不要在本仓为单一 mod 写 `if package_name == …` / 专属 id 分支。
- 不要用同整数 id **覆盖**官方 `data/**` JSON 或美术充当「mod」。
- 不要把 `tools/godot/mods/` 已导入缓存提交进 git。
- 不要默认 **mod → 主项目** 整树覆盖；用户须按项目门禁 **连续两次确认** 才可例外执行一次。
- 不要擅自推 Hugging Face / GitHub Releases（推送本文件除外，须用户已要求）。
- 改玩法口径前先改仓4 专文（`DOC_WORKFLOW`），再改本仓实现。

### English

- Do not add per-mod `if package_name == …` / exclusive id branches in this repo.
- Do not **overwrite** official `data/**` JSON or art by reusing the same integer id as a “mod”.
- Do not commit imported caches under `tools/godot/mods/`.
- Do not default **mod → main** whole-tree overwrite; project gates require **two consecutive user confirms** for a one-shot exception.
- Do not push Hugging Face / GitHub Releases on your own (pushing this file is allowed only when the user already asked).
- Change design-repo docs first when altering gameplay rules (`DOC_WORKFLOW`), then implement here.

---

## 4. 实现落点速查 · Implementation map

| 能力 / Capability | 主要代码 / Primary code |
|-------------------|-------------------------|
| 导入 / 启用 / digest | `godot_project/scripts/mod/mod_manager.gd` |
| 攻击 FX override | `ModFxResolve` · `FiringFx` |
| 互动爆发 FX | `ModInteractionFxResolve` · `InteractionFxPlayer` |
| 引擎拖尾 | `ModTrailResolve` · `EngineBoosterTrail` |
| 联机泰坦 | `ModTitanResolve` · `NullsecRoomUI` |
| 菜单加载 UI | `scripts/ui/main_menu.gd`（选项 → 加载 mod） |
| 存档 / 续局 | `MatchSave` · `mod_ref` |

协议版本：`mod.json.schema_ver` 当前最大 **1**；引擎能力钉扎见 `MOD_PROTOCOL` §0.3 / §9（P1–P8）。  
Protocol version: `mod.json.schema_ver` max **1** today; engine capability pins in `MOD_PROTOCOL` §0.3 / §9 (P1–P8).

---

## 5. 免责 · Disclaimer

第三方 mod 的内容、质量、安全与合法性由创作者与传播者负责；侵权、违法或恶意行为与《星视寰宇EVE自走棋》开发组无关。  
Third-party mods are the responsibility of their creators and distributors. Infringement, illegal content, or malware is not the responsibility of the Eve Auto Chess development team.

---

## 6. 维护约定 · Maintenance

- 仓根 **仅保留本文件** 作为 Mod 双语入口；不要再堆第二份根目录「mod 说明」。  
  Keep **only this file** as the bilingual Mod entry at repo root; do not add a second root “mod guide”.
- 字段或能力变更：先改 `MOD_PROTOCOL.md`（及仓4 `MODS.md`），再视需要改本节摘要（保持短小）。  
  When fields/capabilities change: update `MOD_PROTOCOL.md` (and design-repo `MODS.md`) first; then trim this summary if needed.
- 英文段落与中文同义；字段名、路径、代码标识符保持英文原文。  
  EN sections are semantic peers of ZH; keep field names, paths, and code identifiers in English.
