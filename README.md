自9.13起，与EVE星视寰宇所有合作解除，本仓库内代码与godot重构材料均未经星视寰宇触碰，仓库将维持现状封存，后续的维护等版本（假设真的需要维护或有恶性bug的话）只会以狈头个人名义维护。
十分抱歉我们内部的冲突导致了这一事件，后续其他作品欢迎关注github账号 liketocood345 如果你觉得项目不错（测试版包内所有代码实现均由liketocood345通过AI编写）并希望寻求合作，欢迎在github上留言。

始终易得，初心难忘。

---

要体验游戏看右边releases——————————》

# EveAutoChess · 开发仓

Godot 4.7.1 工程：`godot_project/`

## 打开

```powershell
& "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe" --path "H:\game_dev\eveautochess-dev\godot_project"
```

Boot → 热更检查；可点「跳过热更」用内置 content。主菜单：对战 / 无尽。


要体验游戏看右边releases——————————》



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

## License

本仓**原创源代码**（如 `godot_project/scripts/**`、`tools/**`）采用 [BSD 3-Clause License](LICENSE)。

游戏内第三方或 EVE 相关美术、音频、模型等资源**不在**上述许可范围内，其权利归属各自权利人。
