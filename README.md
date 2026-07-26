# EveAutoChess

EVE 自走棋（DUST 243）**Godot 4** 开发 / 代码存档仓。  
壳包经本仓 **[GitHub Releases](https://github.com/EveAutochess-develop/EveAutoChess/releases)** 发布（无独立 release 仓）。

| | |
|--|--|
| Org | [EveAutochess-develop](https://github.com/orgs/EveAutochess-develop/repositories) |
| 设计权威 | [EveAutoChess-design](https://github.com/EveAutochess-develop/EveAutoChess-design) |
| 热更指针 | [eveautochess-online-update](https://github.com/EveAutochess-develop/eveautochess-online-update) |
| HF 桶 | [liketocode789/eveautochess](https://huggingface.co/buckets/liketocode789/eveautochess) |

## 本仓职责

- Godot 工程与玩法实现（砖块化、balance 外置、AdminBus — 见设计仓）
- 永恒薄壳 Boot + 热更下载器（内容在 HF）
- 批准后的 Win / Android **壳** Releases

**不做**：设计细则长文（在 design 仓）；擅自 Push HF；未批准打壳。

## 目录

| 路径 | 说明 |
|------|------|
| `godot_project/` | Godot **4.7.1** 工程（当前多为脚手架） |
| `tools/godot/` | 本机引擎二进制（通常 gitignore，不进远端） |
| `docs/` | 指向设计仓的短说明 |

## 打开工程

```powershell
& "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe" --path "H:\game_dev\eveautochess-dev\godot_project"
```

（路径按本机 `eveautochess-dev` 安装位置调整。）

## 文档入口（设计仓）

- 总览：[DESIGN_MANUAL.md](https://github.com/EveAutochess-develop/EveAutoChess-design/blob/main/docs/DESIGN_MANUAL.md)
- 迁移 / 一次到位 HF 交付：[ENGINE_MIGRATION.md](https://github.com/EveAutochess-develop/EveAutoChess-design/blob/main/docs/ENGINE_MIGRATION.md)
- 内容格式 / 砖块：[CONTENT_FORMAT.md](https://github.com/EveAutochess-develop/EveAutoChess-design/blob/main/docs/CONTENT_FORMAT.md)
- AdminBus：[ADMIN_BUS.md](https://github.com/EveAutochess-develop/EveAutoChess-design/blob/main/docs/ADMIN_BUS.md)
- Godot 约定：[GODOT_PORT.md](https://github.com/EveAutochess-develop/EveAutoChess-design/blob/main/docs/GODOT_PORT.md)

改玩法 / UI / 热更协议：**先更新设计仓专文，再改本仓代码**。

## 五仓关系（摘要）

1. `eveautochess-original` — 原版 Unity 只读对照  
2. **本仓** — 开发 + 壳 Releases  
3. `eveautochess-hf` — 热更材料本地准备（确认后才推桶）  
4. `EveAutoChess-design` — 设计手册权威  
5. `eveautochess-online-update` — HF 指针，无大文件  

枢纽索引：本地 `H:\game_dev\eveautochess\README.md`。

## 许可与素材

玩法为爱好者向移植/重做；自原版导出的模型/贴图须注意授权，勿默认视为可再分发。
