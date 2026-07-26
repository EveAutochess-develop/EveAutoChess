# EveAutoChess · 开发仓

Godot 4.7.1 工程：`godot_project/`

## 打开

```powershell
& "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe" --path "H:\game_dev\eveautochess-dev\godot_project"
```

Boot → 热更检查；可点「跳过热更」用内置 content。主菜单：对战 / 无尽。

## 结构

- `scripts/admin` · AdminBus  
- `scripts/{match,board,shop,combat,ai,ship,ui,boot,core}`  
- `data/balance|ships|fetters|admin` — 禁止魔法数  

## 打 HF 材料（不推）

```powershell
& "H:\game_dev\eveautochess-dev\tools\pack_hf_content.ps1"
```

导出壳：`build/EVEAutochess.exe`（上传 Releases 须批准）。

设计权威：`eveautochess-design` · [`ENGINE_MIGRATION.md`](../eveautochess-design/docs/ENGINE_MIGRATION.md)
