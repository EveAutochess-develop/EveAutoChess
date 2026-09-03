# Mod 作者协议 · MOD_PROTOCOL

> **读者**：mod 作者与仓2实现。  
> **玩法/联机/安全/免责权威**：仓4 [`MODS.md`](../../../eveautochess-design/docs/MODS.md)（勿在本文件另写一套规则口径）。  
> **Mod 开发手册**：仓4 [`MOD_DEV_HANDBOOK.md`](../../../eveautochess-design/docs/MOD_DEV_HANDBOOK.md) — 主项目 **只提供本协议与引擎实现，不含 mod 内容**；扩展协议或 debug 主项目须先书面说明，由用户单独改 A 轨后镜像给 mod 开发。  
> **字段名与目录以本文为准**。  
> **修订**：2026-08-28（§0 主项目接口范围；§9 去 SG 专属示例）；2026-08-28（P1–P8：locked slot · shop_rules · coin · relation overlay · blink · strike drone · ally repair · grant_fetter）；2026-08-28（`titan_picks` 联机泰坦列表/模型/羁绊）；2026-08-27（`trail_override` 引擎拖尾表现）；2026-08-27（`interaction_fx_override` / `fx_protocol: 2` / COMBAT §8.4）；2026-08-27（`weapon_fx_override` / `fx_kind` / `mod.json.menu`）；2026-08-27（狈头样例改 `mod_samples` + `disv1` 旁路 zip，取消随包种子）；2026-08-26（商店保底：`shop_pity` / `pity_bucket` 缺省不进）；2026-08-26（棋盘射程 `attack_range`：主装格距 + 船体 `-1` 继承）；2026-08-26 首批；随包种子机制 · `function_allowed_sizes` / `allowed_ships` / `set_resist_active`

---

## 文首免责（作者须知）

第三方 mod 由创作者制作与分发，**内容、质量、安全性及合法性由创作者及传播者自行负责**。若涉及侵权、违法、欺诈、恶意软件或其它恶意行为，**与《星视寰宇EVE自走棋》开发组无关**。请只分发你有权分发的素材与数值。

---

## 0. 主项目接口范围（A 轨 · 不含 mod 内容）

> 完整边界与协作流程：仓4 [`MOD_DEV_HANDBOOK.md`](../../../eveautochess-design/docs/MOD_DEV_HANDBOOK.md)。  
> **主项目只实现下表「引擎能力」**；舰船/装备/美术/数值 JSON 由 mod 包提供（B 轨内容仓）。

### 0.1 主项目提供（通用协议）

| 批次 | 能力 | 作者面（摘要） | 实现落点 |
|------|------|----------------|----------|
| 首批 | 包导入/启用/卸载/digest | `mod.json` · zip/文件夹 · `disable_*` · `tonnage_groups` · `replacements` | `ModManager` · `NullsecNetSession` |
| 首批 | 一文件夹一单位 | `units/ships|equipment|unmanned/<dir>/` + `unit.json` | `ModManager` 扫描合并 |
| 首批 | 立体 / 2.5D | `visual.json` · `model/` · `sprite25d/` | `ShipUnit` · `DataStore.visual` |
| 首批 | 数值补全 / 回合动作 | autofill · `round_actions` · `shop_pity` | `ModManager` · `MatchRoot` |
| FX | 攻击/装备特效 | `weapon_fx` + `weapon_fx_override`（`base` 须为**官方** `weapon_fx.json` kind）· `fx_kind` | `ModFxResolve` · `FiringFx` |
| FX | 互动爆发 | `fx_protocol: 2` · `interaction_fx*` | `ModInteractionFxResolve` · `InteractionFxPlayer` |
| FX | 引擎拖尾 | `trail_override` | `ModTrailResolve` · `EngineBoosterTrail` |
| UI | 主菜单 / 商店点缀 | `menu` · `shop_bg` · `ui_overrides.coin_icon` | `main_menu.gd` · `UiAssets` |
| 联机 | 泰坦列表 | `titan_picks` + `fetters/titan_*.json` | `ModTitanResolve` · `NullsecRoomUI` |
| 扩展 | P1–P8 | `locked` · `shop_rules` · `spawn_strike_drone` · `blink` · `grant_fetter` 等 | 见 §9 |

### 0.2 主项目 **不** 提供（须在 mod 包 / B 轨）

| 禁止入主项目 | 正确做法 |
|--------------|----------|
| 某 mod 的舰船/装备/羁绊 JSON | `eveautochess_sgmod` 等内容仓 |
| 某 mod 专属 `weapon_fx` kind（如 `sg_energy_beam`） | `weapon_fx: "laser"` + `weapon_fx_override.base: "laser"` + 单位 `fx/` 贴图 |
| 某 mod 势力/吨位/羁绊的硬编码 UI 回退 | `mod.json` → `tonnage_groups[].icon`；羁绊图 `assets/ui/sprites/FetterIcons/{id}.png` 或同名 mod 资源 |
| `line: sg_superweapon` 等引擎特例 | 功能装写 `shop_category: "superweapon"` |
| `tools/godot/mods/` 下已导入包 | 本地开发缓存；**不进** git（见 `.gitignore`） |
| 随包商业 mod 种子 | 仅 `mod_samples/` 机制样例（狈头）+ `disv1` 旁路 zip；默认不启用 |

### 0.3 协议版本

| 字段 | 说明 |
|------|------|
| `mod.json` → `schema_ver` | 包格式；客户端当前最大 **1** |
| 引擎能力钉扎 | B 轨 Handoff 可写 `engine_protocol: 9`（对应本文 §9 P1–P8）；低于要求壳拒载或黄标 |

---

## 1. 包结构

```
mod.json
units/
  ships/<unit_dir>/
    unit.json
    visual.json          # 可选
    model/               # 可选 GLB 管线
    portrait/portrait.png
    shop_bg/tips_skybox.png   # 可选；商店卡星空
    fx/                  # 可选；攻击特效贴图（weapon_fx_override）
    sprite25d/           # 可选 impostor
  unmanned/<unit_dir>/   # 同构；unit.json 须 is_unmanned；不进商店
  equipment/<unit_dir>/
    unit.json            # kind: main | function
    visual.json?
    icon/icon.png
    fx/                  # 可选；主装/功能特效贴图
fetters/<id>.json        # 可选新羁绊
assets/
  menu/main_bg.jpg       # 可选；主菜单背景（须在 mod.json.menu.bg 声明）
thumbnail.png            # 可选；相对 mod 根
```

套一层目录合法：zip 根无 `mod.json`、唯一顶层文件夹内有 → 视为该文件夹为包根。

### 1.1 `mod.json`

```json
{
  "package_name": "example-mod",
  "version": "1.0.0",
  "display_name": "样例 Mod",
  "author": "Author",
  "description": "最小可加载样例",
  "thumbnail": "thumbnail.png",
  "min_content_rev": "0",
  "schema_ver": 1,
  "dependencies": [],
  "incompatibilities": [],
  "disable_ships": [],
  "disable_equipment": [],
  "tonnage_groups": [],
  "replacements": [],
  "titan_picks": [],
  "shop_rules": {},
  "ui_overrides": {},
  "platforms": { "pc": true, "mobile": true, "mobile_notes": "" },
  "menu": {
    "title": "自定义标题",
    "bg": "assets/menu/main_bg.jpg"
  }
}
```

| 字段 | 说明 |
|------|------|
| `package_name` | kebab `^[a-z][a-z0-9_-]{1,63}$`；主键 |
| `schema_ver` | 首批客户端最大 **1**；更高拒启用 |
| `dependencies` | `[{ "package": "...", "min_version": "1.0.0" }]`；`min_version` 可选 |
| `incompatibilities` | `[{ "package": "..." }]` |
| `disable_ships` / `disable_equipment` | 原版整数 id，或 `{"package","local_id"}` |
| `tonnage_groups` | 见 §4 |
| `replacements` | `[{ "from": 1, "to_local": 234, "mode": "role" }]`；跨 mod from 用对象 |
| `titan_picks` | 可选。联机房间泰坦下拉 + 停泊模型 + meta 羁绊绑定；见 §1.4 |
| `platforms` | 缺省 pc/mobile 皆 true |
| `menu` | 可选。`title` 纯字符串（缺省不改官方标题）；`bg` 相对包根，允许 jpg/png/webp。多启用包：最大 `install_order` 胜（同序比 `enabled_at`）。改启用后须回主菜单或重启。见仓4 MODS §3.3 · UI_AND_SHELL §1 |
| `shop_rules` | 可选。覆盖商店保底子集；见 §9.2 |
| `ui_overrides` | 可选。`coin_icon` 相对包根 PNG；见 §9.3 |

### 1.2 单位 `unit.json`（舰/无人）

只写 **`local_id`（XXXX，0–9999）**，禁止完整六位抢 `xx`。玩法字段对齐 CONTENT_FORMAT / SHIP_STATS_V2 / COMBAT §3.1。

```json
{
  "local_id": 1,
  "name": "样例护卫",
  "name_en": "Sample Frigate",
  "ship_group": "frigate",
  "cost": 2,
  "race": "amarr",
  "weapon_fx": "laser",
  "weapon_fx_override": null,
  "source_module_type_id": 1001,
  "replaces": null,
  "is_unmanned": false,
  "stars": [
    {
      "shield_hp": 400,
      "armor_hp": 500,
      "structure_hp": 250,
      "attack_range": -1
    }
  ],
  "fetter_ids": [],
  "round_actions": []
}
```

跨包替换目标：`"replaces": { "package": "other-mod", "local_id": 10 }` 或原版整数。

可选：`function_allowed_sizes: ["S","M","L","XL"]` — 非空时覆盖按 `ship_group` 推断的副装尺寸门（见仓4 EQUIPMENT §2）。

可选：`"shop_pity": true` — **显式**加入商店刷新保底（吨位 / ID 递增）。**缺省 false**：mod 单位可刷但不吃官方保底（仓4 MODS §3.2）。官方 content 无此字段、一律进保底。

#### 1.2.0 攻击特效 override

| 字段 | 说明 |
|------|------|
| `weapon_fx` | 内置 kind 名（`laser`/`rail`/`cannon`/`missile`/`heal`/…）；SFX 与无 override 时的底板。**禁止**要求主项目在 `weapon_fx.json` 新增 mod 专属 kind；自定义表现用 `weapon_fx_override.base` 指向官方 kind + 单位 `fx/` 贴图 |
| `weapon_fx_override` | 可选对象。必填 `base`（必须是 `weapon_fx.json` → `kinds` 已有键）。允许覆盖：`color`、`width`、`duration_scale`、`duration_scale_near`/`far`、`strobe_hz`、`scroll_speed`、`grid_mix`、`tex_near`/`tex_far`/`tex_shared`/`tex_noise`/`tex_beam`/`tex_grid`/`tex_target`、`strobe_layers_near`/`far`（字符串数组）。贴图路径相对本单位 `fx/`（或包内相对路径）；导入时解析为绝对路径。**禁止**写 `style`/`look`/`evemu_*`（忽略 + Lint） |

运行时：`ShipUnit.resolve_weapon_fx_def()` = 克隆 `kinds[base]` 后合并 override；`FiringFx` 读合并后 def。仅改 `weapon_fx` 字符串时与现网一致。

#### 1.2.0b 互动爆发特效 override（`fx_protocol: 2`）

| 字段 | 说明 |
|------|------|
| `interaction_fx` | 内置 kind 名（`burst_sprite`/`burst_ring`/`attach_loop`/`channel_beam`）；见 `interaction_fx.json` |
| `interaction_fx_override` | 可选。必填 `base`（必须是 `interaction_fx.json` → `kinds` 已有键）。允许：`recipe`（相对本单位 `fx/` 的 JSON，schema 1）· `color` · `scale` · `duration_scale` · `emit_boost` · `tex_ring`/`tex_sprite`。**禁止** `style`/`look`/脚本 |
| `mod.json` → `fx_protocol` | 整数；`2` = 使用互动 recipe。壳 `< 2` 时 Lint 黄标，运行时忽略互动字段 |

运行时：`ModInteractionFxResolve.merge_override` → `InteractionFxResolve` → `InteractionFxPlayer.play_burst`。触发：`weapon_hit` / `module_activate` / `superweapon_fire`（见 COMBAT §8.4）。

#### 1.2.0c 引擎拖尾表现 override（舰 / 无人）

| 字段 | 说明 |
|------|------|
| `trail_override` | 可选对象（写在舰或无人 `unit.json`；也可写在同单位 `visual.json`，导入时上提）。**无** `base`。允许：`mesh_style`（`ribbon`/`tube`）· `brightness` · `fade_power` · `lifetime_s` · `stamp_interval_s` · `unmanned_stamp_interval_s` · `min_stamp_wu` · `max_segments` · `width_mul` · `single_strand`（bool，仅非舰载机无人有意义）。**禁止** `tint_*` / `booster_tint_*` / 喷口坐标 / `engine_boosters` / 脚本 / shader |

运行时：`ModTrailResolve.merge_onto_visual` 将允许键叠到全局 `DataStore.visual` 拖尾默认上；`EngineBoosterTrail` 按舰读 override。喷口仍只走官方 `engine_boosters.json`（经 `model_key`）或 AABB 尾兜底。阵营蓝/红 tint **始终**全局，不可被 mod 覆盖（COMBAT §14D）。

#### 1.2.1 棋盘交战射程（强制口径）

与原版同一套解析：`ShipWeaponDerive.resolve_attack_range`（仓4 [`COMBAT.md`](../../../eveautochess-design/docs/COMBAT.md) §3.1）。

| 字段 | 谁写 | 允许值 | 含义 |
|------|------|--------|------|
| 主装备 `attack_range` | `units/equipment/.../unit.json`（`kind: main`）或原版 `modules.json` | **`0`–`999`**（格） | 默认棋盘交战距；**不是**米制 `maxRange` |
| 船体 `stars[].attack_range` | 舰 / 无人 `unit.json` | **`-1`** 或 **`0`–`999`** | **`-1`**（或缺键）= **继承**代表主装；**`0`–`999`** = **覆盖**主装；其它值运行时钳到 `0`–`999` |
| 无人 | 通常写死船上 `0`–`999` | 同上 | 无人无高槽套件时不读主装；`-1` 会落到安全默认 1 格 |

代表主装解析顺序与原版相同：`source_module_type_id`（原版 typeID **或** 本进程运行时六位 id）→ 否则按 `weapon_fx` + 吨位套件。自研主装须在同包（或依赖包）提供 `kind: main`，并让舰的 `source_module_type_id` 指向其运行时 id（或文档化用原版套件 id）。

**推荐**：有人舰星级写 `"attack_range": -1`，只在主装上调格距，避免船/装两处漂移。狈头种子样例即 `-1` + 原版旗舰磁轨 `11000320000`（装备侧 `999`）。

### 1.3 装备 `unit.json`

```json
{
  "local_id": 50,
  "kind": "main",
  "name": "样例炮",
  "name_en": "Sample Gun",
  "size": "S",
  "attack_range": 3,
  "maxRange": 10000,
  "falloff": 5000
}
```

`kind`: `main` | `function`。副装另对齐 EQUIPMENT（`allowed_on` / `shop_category` 等）。

副装可选：`"shop_pity": true` — 加入装备 ID / 分类保底；**缺省不进**（同 §1.2）。

**主装（`kind: main`）**：须带棋盘 **`attack_range`（0–999 格）**；缺省时运行时按 COMBAT §3.1 表回退（炮台吨位×族 / 导弹·旗舰 999 / 远维 4·8·12），Lint 黄标。米制 `maxRange`/`falloff` 仍只服务命中最优/失准，**禁止**用米数冒充棋盘格距。可写 `weapon_fx` + 可选 `weapon_fx_override`（同 §1.2.0；贴图在本装备 `fx/`）。

**功能装（`kind: function`）**：

| 字段 | 说明 |
|------|------|
| `fx_kind` | 可选。优先于 `line`/`id` 启发式，映射到 `weapon_fx.json` 功能 kind（`nos`/`neut`/`remote_cap`/`sensor_damp`/…）或炮台 kind |
| `weapon_fx_override` | 可选；同 §1.2.0，`base` 可为功能 kind |

副装可选：`allowed_ships: [{ "package": "my-mod", "local_id": 1 }]` — 非空时仅列中稳定键可装；原版舰无 package → 拒装。

主动抗性效果：`{ "op": "set_resist_active", "layer": "armor", "amount": 100 }` — 持续内四抗绝对设为 `amount/100`（可到 1.0）；加算仍用 `add_resist` / `add_resist_active`（封顶 0.95）。

### 1.4 联机泰坦（`titan_picks` · 停泊模型 · meta 羁绊）

负安/低安房间席位「泰坦」下拉、主场停泊 GLB、`BoardController` 泰坦 meta 羁绊，共用 **`race` 字符串** 绑定。官方四族 + 天使为默认；mod 可 **追加** 或 **同 race 覆盖**（按 `install_order`，后启用包胜）。

**`mod.json` → `titan_picks`**（数组，可选）：

```json
"titan_picks": [
  {
    "race": "my_titan",
    "label": "样例泰坦 · 某某",
    "icon": "amarr",
    "ship_local_id": 900,
    "fetter_id": "titan_my_titan"
  }
]
```

| 字段 | 说明 |
|------|------|
| `race` | 小写 lobby 键；同步为 `titan_race`；**禁止** `spectate` |
| `label` | 房间下拉展示文案 |
| `icon` | 种族图标键（`res://assets/ui/race_icons/{icon}.png`）；缺省 = `race` |
| `ship_local_id` | 本包 `units/ships/*/unit.json` 的 XXXX；对应舰须 `ship_group: "titan"`、`shop_eligible: false` |
| `fetter_id` | 可选；缺省 `titan_{race}`；须存在 `fetters/{fetter_id}.json` 且 **`meta: true`** |

**同 race 覆盖官方**：仅换停泊模型时写 `race: "amarr"` + 本包泰坦舰；羁绊仍用官方 `titan_amarr` 时可省略 `fetter_id`。**换羁绊**时提供 `fetters/titan_{race}.json` 并在 pick 里写 `fetter_id`（可覆盖官方 `titan_*` meta 羁绊）。

**不进商店/棋盘**：泰坦 symbol 舰 `shop_eligible: false`；不参与人口与 Field 计数（FREIGHTER_AND_TITAN · FETTERS §4.2）。

**联机**：`titan_race` 随席位同步；双方须启用含相同 `titan_picks` 的 mod（mod digest 门禁不变）。

---

## 2. 运行时 id 与稳定键

| 段 | 谁写 |
|----|------|
| `xx`（01–99） | 系统按 `install_order` |
| `XXXX` | 作者 `local_id`；整包舰+无人+装唯一 |
| 运行时 | `xx*10000+XXXX` |

存档/跨 mod 引用用稳定键 `{package_name, local_id}`，见仓4 MODS §2。

---

## 3. `visual.json`（舰）

缺键回退全局 `visual.ship_look`。禁止任意自定义 shader 路径。

| 分组 | 示例键 |
|------|--------|
| 尺寸 | `model_long_axis`、`model_size_compensate`、`model_auto_orient`、`display_scale_mul` |
| 网格 | `mesh`（相对 `model/model.glb`） |
| 贴图 | `albedo`/`diffuse`/`normal`/`pmwo`/`rg`/`reduction` |
| 上色/打光 | `tint_mode`、`color1..4_*`、`key_energy`/`rim_energy`/… |
| 材质 | `transparency`、`cull`、`unshaded`（枚举） |
| 渲染 | `render_mode`: `auto` \| `mesh` \| `sprite25d` |
| 商店 | `shop_skybox` 相对路径覆盖 |

**模型加载失败**：不显示真船体美术；挂**完全透明选中球**（`albedo.a=0`，与「无模型性能」同代理），保证 BOARD 选舰 raycast 可命中；玩法代理仍在；日志 `{名或id} 模型美术素材加载失败`。有 `model/model.glb` 时禁止用球替代。

### 3.1 2.5D (`sprite25d/`)

`views.json` 示例：

```json
{
  "yaw_bins": 16,
  "pitch_bins": 1,
  "frames": ["view_000.png", "view_001.png"]
}
```

隐形 3D 代理 + 相对相机 yaw 选帧。单帧 billboard 仅降级。加载失败不跨模式兜底。

---

## 4. `tonnage_groups`

```json
{
  "id": "modpack_strike_cruiser",
  "icon": "res://assets/ui/tonnage_overlays/modpack_strike_cruiser_32.png",
  "shop_unlock_level": 6,
  "function_equip_sizes": ["S", "M"],
  "weapon_tier_default": "medium",
  "pity_bucket": false,
  "autofill_profile": "cruiser"
}
```

| 字段 | 缺省 | 说明 |
|------|------|------|
| `pity_bucket` | **false** | `true` 时该**新**吨位键进入吨位保底解锁表；`false`/缺省 → 有舰可刷但不做吨位保底 |

撞原版键 → Lint 跳过该条。icon 进包内 `assets/`。单位级 ID 保底仍须各舰 `"shop_pity": true`（§1.2）；仅开 `pity_bucket` 不够给未声明舰做 ID 强制。

---

## 5. 规范树哈希（伪代码）

```text
files = all regular files under package root
         excluding __MACOSX/, .DS_Store, Thumbs.db
sort by relative path (posix /)
h = sha256()
for each path, bytes:
  h.update(path.encode("utf-8") + b"\0" + bytes)
content_hash = h.hexdigest()
```

联机 digest 与存档用 `content_hash`。zip 另记 `zip_sha256`/`byte_size`。

---

## 6. PC / 移动

| 项 | 口径 |
|----|------|
| PC | 可用完整 GLB + visual；安装旁 `mods/` 优先 |
| 移动 | 推荐 `sprite25d` 或低面数；仅 `user://mods/` |
| `platforms.mobile: false` | 移动端默认不启用 + 黄字 |

---

## 7. Lint 与硬拒绝

见仓4 MODS §1.2。本地导入**无体积上限**；联机同步单包/合计 ≤10 GiB。

---

## 8. 样例

1. **导入样例**（作者手测）：同目录 [`example_mod/`](example_mod/)。打成 zip 后可在选项→加载mod→导入新mod 试用。
2. **投放旁路样例（狈头）**：仓2 `mod_samples/beitou-float-turret/`（**不进** PCK / 壳）。`publish_disv1.ps1` 产出 `H:\disv1\beitou-float-turret.zip`，与 Setup/APK 并列；玩家手动导入。列表 `display_name` 为全文「狈头级浮游炮台与专属格挡器（不包含美术素材用于测试逻辑是否正确样例mod）」；故意无 model/portrait/icon 测缺美术加载。舰 `local_id` 5438 · 副装 `9438`（作者只写 XXXX）。舰星级 `attack_range: -1`，继承原版旗舰磁轨 `source_module_type_id: 11000320000` 的棋盘 `attack_range: 999`。副装带 `"fx_kind": "remote_cap"`（无启发式 line 也可播束）。**不测** `interaction_fx*` / `fx_protocol`（机制 + `weapon_fx: rail` / `remote_cap` 烟测）；interaction 样例见 `data/dev/interaction_fx_sample_recipe.json` 或 Plan B sgmod。`mods_seed/` 仍保留给未来真正随包种子，当前可为空。
3. **导入样例扩展**：`example_mod` 舰带 `weapon_fx_override`（色/宽）与 `trail_override`（亮度/寿命等）；`mod.json.menu.title` 演示主菜单标题覆盖（无强制 bg 文件）。

---

## 9. 协议扩展 P1–P8（通用 · 非某 mod 专属）

> 实现：`function_fit.gd` · `ship_unit.gd` · `mod_manager.gd` · `shop_controller.gd` · `ui_assets.gd` · `ship_health_bar.gd` · `board_controller.gd`  
> B 轨填表示例：[`SG_MOD_HANDOFF.md`](../../../eveautochess_sgmod-design/docs/SG_MOD_HANDOFF.md)（JSON 在内容仓，不在主项目）

### 9.1 P1 · 功能槽锁定 `function_slots.slots[].locked`

舰 `unit.json`：

```json
"function_slots": {
  "slots": [
    { "id": "mod_super_weapon_01", "locked": true },
    { "id": "" },
    { "id": "" }
  ]
}
```

| 行为 | 口径 |
|------|------|
| 锁定槽 | 备战不可拖卸/合成替换；`unequip_function_at` 返回空 |
| 顺序 | 仍须按槽序填充未锁定空槽 |
| 持久 | 锁定来自 hull 模板，不随玩家换装备清除 |

### 9.2 P2 · 商店保底子集 `shop_rules`

```json
"shop_rules": {
  "disable_tonnage_pity": true,
  "disable_equipment_category_pity": true
}
```

| 字段 | 缺省 | 说明 |
|------|------|------|
| `disable_tonnage_pity` | false | true → 关闭 `shop_tonnage_pity_window` 吨位强制 |
| `disable_equipment_category_pity` | false | true → 关闭 `equipment_shop_category_pity_window` 分类强制 |
| ID 保底 | — | **不**在此关闭；仍用 `shop_id_pity_window`（默认 30）+ 各单位 `shop_pity: true` |

多 mod 启用：**最大 `enabled_at`** 的包定义为准（与 `disable_ships` 同规则）。

### 9.3 P3 · 货币图标 `ui_overrides.coin_icon`

```json
"ui_overrides": {
  "coin_icon": "assets/ui/mod_coin.png"
}
```

相对包根 PNG；合并后替换对局内金币图标（`UiAssets.coin_icon_path()`）。缺省仍用官方 `Money.png`。

### 9.4 P4 · 关系角标 `visual.json`

```json
{
  "tonnage_overlay_profile": "relation"
}
```

仅 `_mod_package` 舰生效：HP 条吨位 overlay **无势力底图**，仅保留关系角标（己方紫舰队标 / 敌方红减）。货舰/保护目标仍走 friendly 角标。

### 9.5 P5 · 打击无人机 `spawn_strike_drone`

功能装 `effects[]`：

```json
{
  "op": "spawn_strike_drone",
  "count": 3,
  "range_cells": 6,
  "drone_local_id": 9001,
  "drone_loadout": { "module_id": "mod_cap_drainer_s" }
}
```

| 字段 | 说明 |
|------|------|
| `drone_ship_id` | 完整 runtime id（优先） |
| `drone_local_id` | 本 mod XXXX；与施放者 `_mod_package` 合成 runtime id |
| `drone_loadout.module_id` | 预装功能 mod id（电容战/弱输出等） |
| 无人 | 须 `units/unmanned/` 定义 `is_unmanned: true` |

### 9.6 P6 · 远程修 `targeting: "ally"` + `repair`

```json
{
  "targeting": "ally",
  "range_cells": 8,
  "activate": "periodic",
  "effects": [{ "op": "repair", "layer": "shield", "amount": 120 }]
}
```

`repair` 作用于锁定的友方目标（`_best_heal_ally` 或范围内友舰），非自修。

### 9.7 P7 · 跳刀 `activate: "blink"`

```json
{
  "activate": "blink",
  "range_cells": 10,
  "blink_duration_s": 0.1,
  "blink_speed_mul": 0,
  "duration_s": 15
}
```

| 字段 | 说明 |
|------|------|
| `blink_duration_s` | burst 窗口（默认 0.1s） |
| `blink_speed_mul` | 0 或未写 → 按 `combat.blink_speed_cap_wu` 拉满相对当前航速 |
| 表现 | 窗口内 `combat_move_speed` 乘区放大；与正常位移同管线 |

### 9.8 P8 · 临时羁绊 `grant_fetter`

```json
{
  "targeting": "enemy",
  "range_cells": 5,
  "effects": [{
    "op": "grant_fetter",
    "fetter_id": "mod_debuff_speed",
    "duration_s": 8,
    "target_side": "enemy"
  }]
}
```

| 项 | 口径 |
|----|------|
| 前置 | `fetters/<id>.json` 须已进包并被 merge |
| 运行时 | 目标舰 `runtime_fetter_ids` 追加；与静态 `fetter_ids` 合并后 `recalculate_fetters` |
| `target_side` | `ally` / `enemy`；缺省按 module `targeting` |
| 到期 | `duration_s` 后 prune；战后 `reset_combat_runtime` 清空 |