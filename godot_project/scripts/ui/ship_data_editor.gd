extends Control
class_name ShipDataEditor
## UI_AND_SHELL §2.5.1 — developer table for ships + equipment modules.
## Opens paused, edits a working copy, writes back on exit (content_runtime + editor baseline).

## Equipment edits change manned DPH too (SHIP_STATS_V2 §2.2), so they must reach guests
## even when no ship JSON moved.
signal closed(changed_ids: Array, equipment_changed: bool)

enum Tab { SHIPS, MODULES, FUNCTION_MODULES, DAMAGE, HEALTH, MATCH_CONTROL, COMBAT_EVAL }

const _CANCEL_HINT: String = "退出即自动保存；改动写入 content_runtime，删除该文件即回滚基线。"
const EXPORT_SHIPS_FILE: String = "eveac_ships_table.csv"
const EXPORT_EQUIP_FILE: String = "eveac_equipment_table.csv"
## UI_AND_SHELL §2.5.1 — identity / art / equipment-icon keys stay display-only.
const _LOCKED_SHIP_ROOTS: Dictionary = {
	"race": true,
	"model_key": true,
	"sof_hull": true,
	"portrait": true,
	"weapon_fx": true,
	"weapon_tier": true,
	"source_module_type_id": true,
	"source_repair_module_type_id": true,
}
const _LOCKED_MODULE_ROOTS: Dictionary = {
	"typeID": true,
}
const _CHART_BAR_MIN_W: float = 260.0
const _CHART_ROW_H: float = 34.0
const _CHART_INFO_W: float = 410.0
const _REPEAT_DELAY_S: float = 0.5
const _REPEAT_INTERVAL_S: float = 0.05
const _UNMANNED_RATE_STEP: float = 1.0
const _COLOR_HULL_DPS: Color = Color(0.34, 0.75, 1.0, 0.92)
const _COLOR_HULL_HPS: Color = Color(0.28, 0.9, 0.48, 0.94)
const _COLOR_WING: Color = Color(0.78, 0.28, 1.0, 0.96)  ## drone / fighter segment — distinct purple
const _COLOR_UNMANNED_DPS: Color = Color(0.7, 0.38, 1.0, 0.94)
const _DRONE_BW_COST: float = 5.0
const _RACE_DRONE_LIGHT: Dictionary = {"amarr": 1001, "caldari": 1002, "gallente": 1003, "minmatar": 1004}
const _RACE_DRONE_MEDIUM: Dictionary = {"amarr": 1005, "caldari": 1006, "gallente": 1007, "minmatar": 1008}
const _RACE_DRONE_HEAVY: Dictionary = {"amarr": 1011, "caldari": 1012, "gallente": 1013, "minmatar": 1014}
const _DRONE_COUNT_EXCEPTIONS: Dictionary = {42: 5, 44: 4, 55: 4, 56: 5}
const _CAPITAL_GROUPS: Dictionary = {
	"dreadnought": true,
	"carrier": true,
	"force_auxiliary": true,
	"capital_industrial": true,  # 长须鲸 · UI_AND_SHELL §2.5.1 chart bucket
}
const _GROUP_ORDER: Dictionary = {
	"drone_light": 1,
	"drone_medium": 2,
	"drone_heavy": 3,
	"fighter": 4,
	"repair_drone": 5,
	"heavy_repair_drone": 5,
	"frigate": 10,
	"destroyer": 20,
	"cruiser": 30,
	"battlecruiser": 40,
	"battleship": 50,
	"mining_barge": 60,
	"industrial_command": 70,
	"freighter": 90,
}

var _tab: Tab = Tab.SHIPS
var _ids: Array[int] = []
var _filtered: Array[int] = []
var _working_ships: Dictionary = {}  # id -> edited ship dict
var _working_modules: Dictionary = {}
var _working_function_modules: Dictionary = {}
var _dirty_ships: Dictionary = {}
var _dirty_modules: bool = false
var _dirty_function_modules: bool = false
var _working_titan_pvp: Dictionary = {}
var _dirty_titan_pvp: bool = false
var _fn_ids: Array[String] = []
var _filtered_fn: Array[String] = []
var _current_fn_id: String = ""
var _current_id: int = -1
var _pause_owner: bool = false
var _was_paused: bool = false
var _last_equipment_saved: bool = false

var _cap: Label
var _list: ItemList
var _search: LineEdit
var _title_icon: TextureRect
var _title: Label
var _grid: GridContainer
var _status: Label
var _export_btn: Button
var _tab_btns: Array[Button] = []
var _left_panel: VBoxContainer
var _field_scroll: ScrollContainer
var _chart_entries: Array = []
var _chart_kind: Tab = Tab.DAMAGE
## Cancel stale async builds when switching tabs / reopening.
var _load_gen: int = 0
const _STEP_BUDGET_MS: int = 10 ## Wall-clock budget per frame while building lists (SEMI_ASYNC §E).


func _init() -> void:
	name = "ShipDataEditor"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	_build()
	_reload_ids()


func open(pause_game: bool = true) -> void:
	_load_gen += 1
	_working_ships.clear()
	_working_modules = {}
	_working_function_modules = {}
	if "modules" in DataStore:
		_working_modules = DataStore.modules.duplicate(true)
	else:
		push_error("[ShipDataEditor] DataStore.modules missing — shell Autoload outdated")
		SessionDiagnostics.log("error", "DataStore.modules missing")
	if "function_modules" in DataStore:
		_working_function_modules = DataStore.function_modules.duplicate(true)
	else:
		push_error("[ShipDataEditor] DataStore.function_modules missing — shell Autoload outdated")
		SessionDiagnostics.log("error", "DataStore.function_modules missing")
	_dirty_ships.clear()
	_dirty_modules = false
	_dirty_function_modules = false
	_working_titan_pvp = DataStore.titan_pvp.duplicate(true) if "titan_pvp" in DataStore else {}
	_dirty_titan_pvp = false
	_current_fn_id = ""
	visible = true
	if pause_game and not _pause_owner:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_pause_owner = true
	if _export_btn:
		_export_btn.visible = _can_export_table()
	if _status:
		_status.text = (
			_CANCEL_HINT
			if "modules" in DataStore and "function_modules" in DataStore
			else "壳 DataStore 过旧（无装备表）· 请重装最新壳"
		)
	await _set_tab(Tab.SHIPS, true)


## Autosave + restore pause. Emits the ship ids whose JSON actually changed.
func close_and_save() -> void:
	_finish_close(_save_all())


## Save, overwrite Downloads CSVs (all platforms), then exit.
func close_and_save_and_export() -> void:
	if not _can_export_table():
		_status.text = "无法导出表格"
		return
	var changed: Array = _save_all()
	var ship_path: String = _export_ships_csv()
	var equip_path: String = _export_equipment_csv()
	if ship_path == "" and equip_path == "":
		_status.text = "保存成功，但导出失败（无法写入下载目录或回退路径）"
		_finish_close(changed)
		return
	var shown: String = "%s · %s" % [ship_path, equip_path]
	DisplayServer.clipboard_set(shown)
	SessionDiagnostics.log("editor.export", "ships=%s equip=%s" % [ship_path, equip_path])
	_status.text = "已导出（路径已复制）：%s" % shown
	_finish_close(changed)


func _on_pull_default_pressed() -> void:
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = "确认覆盖本地数据"
	dlg.dialog_text = (
		"将拉取官方默认全舰船与装备数据并覆盖本地 content_runtime 明文副本。\n"
		+ "本地手改将丢失，操作不可逆。是否继续？"
	)
	dlg.ok_button_text = "确认覆盖"
	dlg.cancel_button_text = "取消"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		_pull_default_overwrite()
	, CONNECT_ONE_SHOT)
	dlg.canceled.connect(func() -> void: dlg.queue_free(), CONNECT_ONE_SHOT)
	dlg.popup_centered()


func _pull_default_overwrite() -> void:
	if _status:
		_status.text = "正在拉取默认全舰船数据…"
	var result: Dictionary = await _force_pull_default_data()
	if not TypedVariant.as_bool(result.get("ok", false), false):
		if _status:
			_status.text = "拉取失败：%s" % str(result.get("error", "unknown"))
		push_warning("[ShipDataEditor] force pull failed: %s" % result.get("error", ""))
		return
	_working_ships.clear()
	_dirty_ships.clear()
	_dirty_modules = false
	_dirty_function_modules = false
	DataStore.reload_all()
	if "modules" in DataStore:
		_working_modules = DataStore.modules.duplicate(true)
	if "function_modules" in DataStore:
		_working_function_modules = DataStore.function_modules.duplicate(true)
	_reload_ids()
	await _set_tab(_tab, true)
	if _status:
		_status.text = "已用官方默认表覆盖本地（wrote=%s）" % str(result.get("wrote", 0))
	SessionDiagnostics.log("editor.force_pull_default", "wrote=%s" % result.get("wrote", 0))


func _force_pull_default_data() -> Dictionary:
	## Editor / no shell update scripts: force from res://.
	## Packaged shell: download data.pck via UpdateClient then force-reseed.
	var client_path: String = "res://scripts/online_update/update_client.gd"
	var config_path: String = "res://scripts/online_update/update_config.gd"
	if OS.has_feature("editor") or not ResourceLoader.exists(client_path) or not ResourceLoader.exists(config_path):
		var seed_res: Dictionary = ContentRuntimeData.force_reseed_ships_equipment_unmanned()
		return {"ok": true, "wrote": TypedVariant.as_int(seed_res.get("wrote", 0), 0), "error": ""}
	var client_scr: GDScript = load(client_path) as GDScript
	var config_scr: GDScript = load(config_path) as GDScript
	if client_scr == null or config_scr == null:
		var local_seed: Dictionary = ContentRuntimeData.force_reseed_ships_equipment_unmanned()
		return {"ok": true, "wrote": TypedVariant.as_int(local_seed.get("wrote", 0), 0), "error": ""}
	var http: HTTPRequest = HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var client: RefCounted = client_scr.new(self, http)
	var platform_id: String = str(config_scr.call("get_platform_id"))
	var version_url: String = str(config_scr.call("version_url"))
	var ver_got: Dictionary = await client.call("http_get_text", version_url, 30.0)
	if TypedVariant.as_bool(ver_got.get("ok", false), false):
		var ver_data: Variant = JSON.parse_string(str(ver_got.get("text", "")))
		if typeof(ver_data) == TYPE_DICTIONARY:
			var ver_dict: Dictionary = TypedVariant.as_dict(ver_data)
			config_scr.call("apply_remote_base_url", str(ver_dict.get("baseUrl", "")))
	var manifest_url: String = str(config_scr.call("manifest_url"))
	var man_got: Dictionary = await client.call("http_get_text", manifest_url, 30.0)
	http.queue_free()
	if not TypedVariant.as_bool(man_got.get("ok", false), false):
		return {"ok": false, "error": "manifest: %s" % man_got.get("error", "")}
	var man: Variant = JSON.parse_string(str(man_got.get("text", "")))
	if typeof(man) != TYPE_DICTIONARY:
		return {"ok": false, "error": "manifest JSON invalid"}
	var files: Array = TypedVariant.as_array(TypedVariant.as_dict(man).get("files", []))
	http = HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	client = client_scr.new(self, http)
	var applied: Dictionary = await client.call("force_fetch_and_apply_data_pack", files, platform_id)
	http.queue_free()
	return applied


func _finish_close(changed: Array) -> void:
	_load_gen += 1
	visible = false
	if _pause_owner:
		get_tree().paused = _was_paused
		_pause_owner = false
	closed.emit(changed, _last_equipment_saved)


static func _can_export_table() -> bool:
	return true


func _build() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var frame: PanelContainer = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60
	frame.offset_top = 40
	frame.offset_right = -60
	frame.offset_bottom = -40
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.98)
	sb.border_color = Color(0.35, 0.72, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UiLayout.margin_px(14, self))
	frame.add_child(margin)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
	margin.add_child(col)

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
	_cap = Label.new()
	_cap.text = "全舰船装备数据调整"
	_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(_cap, true, UiLayout.font_size(22, self))
	head.add_child(_cap)
	var save_btn: Button = Button.new()
	save_btn.text = "保存并退出"
	UiAssets.apply_button_font(save_btn, UiLayout.font_size(16, self))
	save_btn.pressed.connect(close_and_save)
	head.add_child(save_btn)
	var pull_btn: Button = Button.new()
	pull_btn.text = "拉取默认全舰船数据覆盖本地"
	UiAssets.apply_button_font(pull_btn, UiLayout.font_size(16, self))
	pull_btn.pressed.connect(_on_pull_default_pressed)
	head.add_child(pull_btn)
	_export_btn = Button.new()
	_export_btn.text = "保存并退出顺带导出表格"
	UiAssets.apply_button_font(_export_btn, UiLayout.font_size(16, self))
	_export_btn.pressed.connect(close_and_save_and_export)
	_export_btn.visible = _can_export_table()
	head.add_child(_export_btn)
	col.add_child(head)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", UiLayout.margin_px(6, self))
	col.add_child(tabs)
	_tab_btns.clear()
	for pair: Array in [
		[Tab.SHIPS, "舰船"],
		[Tab.MODULES, "主装备"],
		[Tab.FUNCTION_MODULES, "副装备"],
		[Tab.DAMAGE, "伤害"],
		[Tab.HEALTH, "血量"],
		[Tab.MATCH_CONTROL, "对局控制参数"],
		[Tab.COMBAT_EVAL, "战评"],
	]:
		var b: Button = Button.new()
		b.text = str(pair[1])
		b.toggle_mode = true
		b.button_pressed = TypedVariant.as_int(pair[0], 0) == int(Tab.SHIPS)
		UiAssets.apply_button_font(b, UiLayout.font_size(15, self))
		## Enum values inside Array become ints — do not use `is Tab` (always false).
		var tab_idx: int = TypedVariant.as_int(pair[0], 0)
		b.pressed.connect(func() -> void: _set_tab(tab_idx as Tab, false))
		tabs.add_child(b)
		_tab_btns.append(b)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	col.add_child(body)

	_left_panel = VBoxContainer.new()
	_left_panel.custom_minimum_size = Vector2(UiLayout.px(260, self), 0)
	body.add_child(_left_panel)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索名 / id"
	_apply_edit_font(_search, 15)
	_search.text_changed.connect(_apply_filter)
	_left_panel.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(UiLayout.px(28, self), UiLayout.px(28, self))
	_list.icon_mode = ItemList.ICON_MODE_LEFT
	_list.item_selected.connect(_on_list_selected)
	_left_panel.add_child(_list)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
	right.add_child(title_row)
	_title_icon = TextureRect.new()
	_title_icon.visible = false
	_title_icon.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	_title_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_title_icon)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiAssets.apply_label_font(_title, true, UiLayout.font_size(18, self))
	title_row.add_child(_title)
	_field_scroll = ScrollContainer.new()
	_field_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_field_scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_scroll.add_child(_grid)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(_status, false, UiLayout.font_size(13, self))
	col.add_child(_status)


func _apply_edit_font(edit: LineEdit, design_size: int) -> void:
	var f: Font = UiAssets.body_font()
	if f:
		edit.add_theme_font_override("font", f)
	edit.add_theme_font_size_override("font_size", UiLayout.font_size(design_size, self))


func _set_tab(tab: Tab, force: bool) -> void:
	if not force and _tab == tab:
		for i: int in range(_tab_btns.size()):
			_tab_btns[i].button_pressed = (i == int(tab))
		return
	_load_gen += 1
	var gen: int = _load_gen
	_tab = tab
	for i: int in range(_tab_btns.size()):
		_tab_btns[i].button_pressed = (i == int(tab))
	var visual: bool = tab == Tab.DAMAGE or tab == Tab.HEALTH
	_left_panel.visible = not visual and tab != Tab.MATCH_CONTROL and tab != Tab.COMBAT_EVAL
	## Visualization tables are vertical so a normal mouse wheel traverses all hulls.
	_field_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid.columns = 1 if visual or tab == Tab.FUNCTION_MODULES or tab == Tab.MATCH_CONTROL or tab == Tab.COMBAT_EVAL else 2
	_search.text = ""
	if tab == Tab.MATCH_CONTROL:
		_current_id = -1
		_current_fn_id = ""
		_build_match_control_fields()
		return
	if tab == Tab.COMBAT_EVAL:
		_current_id = -1
		_current_fn_id = ""
		_build_combat_eval_fields()
		return
	if visual:
		_current_id = -1
		_current_fn_id = ""
		await _build_visualization_stepwise(tab, gen)
		return
	await _reload_list_stepwise(gen)
	if gen != _load_gen:
		return
	if _tab == Tab.FUNCTION_MODULES:
		if _filtered_fn.size() > 0:
			_select_fn_id(_filtered_fn[0])
		else:
			_current_fn_id = ""
			_current_id = -1
			_title.text = "（无条目）"
			_set_title_icon(null)
			for c: Node in _grid.get_children():
				c.queue_free()
			if _status:
				_status.text = _CANCEL_HINT
		return
	if _filtered.size() > 0:
		_select_id(_filtered[0])
	else:
		_current_id = -1
		_current_fn_id = ""
		_title.text = "（无条目）"
		_set_title_icon(null)
		for c: Node in _grid.get_children():
			c.queue_free()
		if _status:
			_status.text = _CANCEL_HINT


func _reload_list_stepwise(gen: int) -> void:
	_reload_ids()
	_filtered.clear()
	_filtered_fn.clear()
	if _list:
		_list.clear()
	if _tab == Tab.FUNCTION_MODULES:
		var nfn: int = _fn_ids.size()
		var t0: int = Time.get_ticks_msec()
		for i: int in range(nfn):
			if gen != _load_gen:
				return
			var fid: String = _fn_ids[i]
			var label: String = _fn_list_label(fid)
			_filtered_fn.append(fid)
			if _list:
				_list.add_item(label, _fn_list_icon(fid))
			if _status and (i == 0 or i + 1 == nfn or (Time.get_ticks_msec() - t0) >= _STEP_BUDGET_MS):
				_status.text = "正在加载列表… %d / %d" % [i + 1, nfn]
			if (Time.get_ticks_msec() - t0) >= _STEP_BUDGET_MS:
				await get_tree().process_frame
				t0 = Time.get_ticks_msec()
		if gen == _load_gen and _status:
			_status.text = _CANCEL_HINT
		return
	var n: int = _ids.size()
	var t1: int = Time.get_ticks_msec()
	for i: int in range(n):
		if gen != _load_gen:
			return
		var sid: int = _ids[i]
		var label: String = _list_label(sid)
		_filtered.append(sid)
		if _list:
			_list.add_item(label)
		if _status and (i == 0 or i + 1 == n or (Time.get_ticks_msec() - t1) >= _STEP_BUDGET_MS):
			_status.text = "正在加载列表… %d / %d" % [i + 1, n]
		if (Time.get_ticks_msec() - t1) >= _STEP_BUDGET_MS:
			await get_tree().process_frame
			t1 = Time.get_ticks_msec()
	if gen == _load_gen and _status:
		_status.text = _CANCEL_HINT


func _reload_ids() -> void:
	_ids.clear()
	_fn_ids.clear()
	match _tab:
		Tab.SHIPS:
			var keys: Array = DataStore.ships.keys()
			keys.sort()
			for k: Variant in keys:
				_ids.append(TypedVariant.as_int(k, 0))
		Tab.MODULES:
			var mk: Array = _working_modules.keys() if not _working_modules.is_empty() else (
				DataStore.modules.keys() if "modules" in DataStore else []
			)
			mk.sort()
			for k: Variant in mk:
				_ids.append(TypedVariant.as_int(k, 0))
		Tab.FUNCTION_MODULES:
			var fk: Array = _working_function_modules.keys() if not _working_function_modules.is_empty() else (
				DataStore.function_modules.keys() if "function_modules" in DataStore else []
			)
			fk.sort()
			for k: Variant in fk:
				_fn_ids.append(str(k))
		_:
			pass


func _apply_filter(query: String) -> void:
	var q: String = query.strip_edges().to_lower()
	_filtered.clear()
	_filtered_fn.clear()
	if _list:
		_list.clear()
	if _tab == Tab.FUNCTION_MODULES:
		for fid: String in _fn_ids:
			var label: String = _fn_list_label(fid)
			if q != "" and not label.to_lower().contains(q) and not fid.to_lower().contains(q):
				continue
			_filtered_fn.append(fid)
			if _list:
				_list.add_item(label, _fn_list_icon(fid))
		return
	for sid: int in _ids:
		var label: String = _list_label(sid)
		var en: String = _list_en(sid)
		if q != "" and not label.to_lower().contains(q) and not en.to_lower().contains(q):
			continue
		_filtered.append(sid)
		if _list:
			_list.add_item(label)


func _fn_list_label(fid: String) -> String:
	var m: Dictionary = _working_function_modules.get(fid, DataStore.get_function_module(fid))
	return "%s · %s" % [fid, str(m.get("name", "?"))]


func _fn_list_icon(fid: String) -> Texture2D:
	var m: Dictionary = TypedVariant.as_dict(
		_working_function_modules.get(fid, DataStore.get_function_module(fid))
	)
	return UiAssets.function_module_icon(m)


func _set_title_icon(tex: Texture2D) -> void:
	if _title_icon == null:
		return
	_title_icon.texture = tex
	_title_icon.visible = tex != null


func _list_label(sid: int) -> String:
	match _tab:
		Tab.SHIPS:
			var d: Dictionary = DataStore.get_ship(sid)
			var label: String = "%d · %s" % [sid, str(d.get("name", "?"))]
			if TypedVariant.as_bool(d.get("is_unmanned", false)):
				label += "（无人）"
			return label
		Tab.MODULES:
			var m: Dictionary = _working_modules.get(sid, DataStore.get_module(sid))
			var zh: String = str(m.get("nameZH", ""))
			var en: String = str(m.get("nameEN", m.get("nameSDE", "?")))
			return "%d · %s" % [sid, zh if zh.strip_edges() != "" else en]
		_:
			return str(sid)


func _list_en(sid: int) -> String:
	match _tab:
		Tab.SHIPS:
			return str(DataStore.get_ship(sid).get("name_en", ""))
		Tab.MODULES:
			var m: Dictionary = TypedVariant.as_dict(_working_modules.get(sid, DataStore.get_module(sid)))
			return str(m.get("nameEN", ""))
		_:
			return ""


func _on_list_selected(idx: int) -> void:
	if _tab == Tab.FUNCTION_MODULES:
		if idx < 0 or idx >= _filtered_fn.size():
			return
		_select_fn_id(_filtered_fn[idx])
		return
	if idx < 0 or idx >= _filtered.size():
		return
	_select_id(_filtered[idx])


func _select_fn_id(item_id: String) -> void:
	_current_fn_id = item_id
	_current_id = -1
	var d: Dictionary = _ensure_working_fn(item_id)
	_title.text = "副装备 %s · %s" % [item_id, str(d.get("name", "?"))]
	_set_title_icon(UiAssets.function_module_icon(d))
	var sel: int = _filtered_fn.find(item_id)
	if _list and sel >= 0 and not _list.is_selected(sel):
		_list.select(sel)
	_rebuild_function_module_fields(d)


func _ensure_working_fn(item_id: String) -> Dictionary:
	if not _working_function_modules.has(item_id):
		_working_function_modules[item_id] = DataStore.get_function_module(item_id).duplicate(true)
	return _working_function_modules[item_id]


func _build_match_control_fields() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_title.text = "对局控制参数（泰坦三管 / 末日伤）"
	_set_title_icon(null)
	if _working_titan_pvp.is_empty():
		_working_titan_pvp = {
			"pipe_shield_max": 100,
			"pipe_armor_max": 100,
			"pipe_structure_max": 100,
			"pvp_loss_damage": 20,
			"lowsec_pvp_loss_mul": 0.25,
		}
	var keys: Array[String] = [
		"pipe_shield_max", "pipe_armor_max", "pipe_structure_max",
		"pvp_loss_damage", "lowsec_pvp_loss_mul",
	]
	var labels: Dictionary = {
		"pipe_shield_max": "盾管上限",
		"pipe_armor_max": "甲管上限",
		"pipe_structure_max": "构管上限",
		"pvp_loss_damage": "失败/平局扣血",
		"lowsec_pvp_loss_mul": "低安伤倍率",
	}
	for k: String in keys:
		var row: HBoxContainer = HBoxContainer.new()
		_grid.add_child(row)
		var lab: Label = Label.new()
		lab.text = str(labels.get(k, k))
		lab.custom_minimum_size = Vector2(220, 0)
		row.add_child(lab)
		var edit: LineEdit = LineEdit.new()
		edit.text = str(_working_titan_pvp.get(k, 0))
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key_cap: String = k
		edit.text_submitted.connect(func(t: String) -> void:
			var parsed: Variant = 0
			if key_cap.ends_with("mul"):
				parsed = float(t)
			else:
				parsed = int(t)
			_working_titan_pvp[key_cap] = parsed
			_dirty_titan_pvp = true
		)
		edit.focus_exited.connect(func() -> void:
			var parsed2: Variant = 0
			if key_cap.ends_with("mul"):
				parsed2 = float(edit.text)
			else:
				parsed2 = int(edit.text)
			_working_titan_pvp[key_cap] = parsed2
			_dirty_titan_pvp = true
		)
		row.add_child(edit)
	if _status:
		_status.text = "改完点保存并退出 · 写入 balance/titan_pvp.json"


func _build_combat_eval_fields() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_title.text = "战评称号目录（只读 · MULTIPLAYER_PVP §7.1）"
	_set_title_icon(null)
	_grid.columns = 1
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var items: Array = TypedVariant.as_array(DataStore.get("combat_evals"))
	## Shell Autoload may lag content — fall back to balance JSON directly.
	if items.is_empty():
		var raw: Dictionary = ContentRuntimeData.load_json_prefer_runtime("balance/combat_evals.json")
		items = TypedVariant.as_array(raw.get("items", []))
	var eval_wrap: VBoxContainer = VBoxContainer.new()
	eval_wrap.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	eval_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(eval_wrap)
	## Autowrap Labels collapse to a 1-glyph strip unless the scroll width is known.
	var panel_w: float = maxf(_field_scroll.size.x, size.x * 0.72)
	if panel_w < 120.0:
		panel_w = float(UiLayout.px(520, self))
	eval_wrap.custom_minimum_size = Vector2(panel_w, 0)
	if items.is_empty():
		var empty: Label = Label.new()
		empty.text = "（无 combat_evals.json 条目）"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eval_wrap.add_child(empty)
		if _status:
			_status.text = "只读 · 不可编辑"
		return
	for item_v: Variant in items:
		var item: Dictionary = TypedVariant.as_dict(item_v)
		var row: VBoxContainer = VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eval_wrap.add_child(row)
		var name_l: Label = Label.new()
		name_l.text = str(item.get("name", item.get("id", "?")))
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiAssets.apply_label_font(name_l, true, UiLayout.font_size(16, self))
		row.add_child(name_l)
		var cond: Label = Label.new()
		cond.text = str(item.get("condition", ""))
		cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cond.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cond.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
		UiAssets.apply_label_font(cond, false, UiLayout.font_size(13, self))
		row.add_child(cond)
		var sep: HSeparator = HSeparator.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eval_wrap.add_child(sep)
	if _status:
		_status.text = "只读 · 条件文案来自 balance/combat_evals.json · 不可编辑"


func _select_id(item_id: int) -> void:
	_current_id = item_id
	_current_fn_id = ""
	var d: Dictionary = _ensure_working(item_id)
	_set_title_icon(null)
	match _tab:
		Tab.SHIPS:
			_title.text = "%d · %s（%s）" % [item_id, str(d.get("name", "?")), str(d.get("name_en", ""))]
		Tab.MODULES:
			_title.text = "主装备 %d · %s" % [item_id, str(d.get("nameEN", d.get("nameSDE", "?")))]
	var sel: int = _filtered.find(item_id)
	if _list and sel >= 0 and not _list.is_selected(sel):
		_list.select(sel)
	_rebuild_fields(d)


func _ensure_working(item_id: int) -> Dictionary:
	match _tab:
		Tab.SHIPS:
			if not _working_ships.has(item_id):
				_working_ships[item_id] = DataStore.get_ship(item_id).duplicate(true)
			return _working_ships[item_id]
		Tab.MODULES:
			if not _working_modules.has(item_id):
				_working_modules[item_id] = DataStore.get_module(item_id).duplicate(true)
			return _working_modules[item_id]
		_:
			return {}


func _build_visualization_stepwise(kind: Tab, gen: int) -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_chart_entries.clear()
	_chart_kind = kind
	_title.text = (
		"伤害可视化 · 蓝/绿=船体 · 紫=无人机/舰载机 · 无人可调DPS→DPH"
		if kind == Tab.DAMAGE
		else "血量可视化 · 纵向滚轮表 · 盾 / 甲 / 结构"
	)
	_set_title_icon(null)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", UiLayout.px(18, self))
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(root)
	if _status:
		_status.text = "正在加载可视化…"
	await _build_chart_section_stepwise(root, false, gen)
	if gen != _load_gen:
		return
	await _build_chart_section_stepwise(root, true, gen)
	if gen != _load_gen:
		return
	_refresh_chart_values()
	if _status:
		_status.text = (
			"箭头按下立即调整；按住0.5秒后每0.05秒连调 · " + _CANCEL_HINT
		)


func _build_chart_section_stepwise(root: VBoxContainer, capital: bool, gen: int) -> void:
	var title: Label = Label.new()
	title.text = (
		(
			"旗舰量级（无畏 / 航母 / 战辅 / 逆戟鲸 / 长须鲸 / 货舰）"
			if _chart_kind == Tab.HEALTH
			else "旗舰（无畏 / 航母 / 战辅 / 长须鲸 / 货舰）"
		)
		if capital
		else "普通舰船 + 无人单位 + 冬眠者"
	)
	UiAssets.apply_label_font(title, true, UiLayout.font_size(16, self))
	root.add_child(title)
	var axis: Label = Label.new()
	axis.text = (
		"Y：单位（小→大） · X：每秒输出（蓝/绿=船体 · 紫=僚机）"
		if _chart_kind == Tab.DAMAGE
		else "Y：舰船 / 无人单位（小→大） · X：总血量（蓝=盾 / 黄=甲 / 红=结构）"
	)
	UiAssets.apply_label_font(axis, false, UiLayout.font_size(12, self))
	root.add_child(axis)
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", UiLayout.px(1, self))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(list)
	var ids: Array[int] = _chart_ship_ids(capital)
	if ids.is_empty():
		var empty: Label = Label.new()
		empty.text = "（无舰船）"
		UiAssets.apply_label_font(empty, false, UiLayout.font_size(13, self))
		list.add_child(empty)
		return
	var n: int = ids.size()
	var section: String = "旗舰" if capital else "普通"
	var t0: int = Time.get_ticks_msec()
	for i: int in range(n):
		if gen != _load_gen:
			return
		_build_chart_row(list, ids[i], capital)
		if _status and (i == 0 or i + 1 == n or (Time.get_ticks_msec() - t0) >= _STEP_BUDGET_MS):
			_status.text = "正在加载%s… %d / %d" % [section, i + 1, n]
		if (Time.get_ticks_msec() - t0) >= _STEP_BUDGET_MS:
			await get_tree().process_frame
			t0 = Time.get_ticks_msec()


func _chart_ship_ids(capital: bool) -> Array[int]:
	var ids: Array[int] = []
	for key: Variant in DataStore.ships.keys():
		var sid: int = TypedVariant.as_int(key, 0)
		var ship: Dictionary = _chart_ship(sid)
		if ship.is_empty():
			continue
		var unmanned: bool = TypedVariant.as_bool(ship.get("is_unmanned", false))
		if unmanned:
			## Health lists every unmanned unit as a ship; damage still excludes mining.
			if capital or (_chart_kind == Tab.DAMAGE and _is_mining_unmanned(ship)):
				continue
			ids.append(sid)
			continue
		if not _chart_include_manned(ship):
			continue
		var is_capital: bool = _chart_uses_capital_scale(ship)
		if is_capital == capital:
			ids.append(sid)
	ids.sort_custom(func(a: int, b: int) -> bool:
		var sa: Dictionary = _chart_ship(a)
		var sb: Dictionary = _chart_ship(b)
		var oa: int = _group_sort_key(str(sa.get("ship_group", "")), capital)
		var ob: int = _group_sort_key(str(sb.get("ship_group", "")), capital)
		return a < b if oa == ob else oa < ob
	)
	return ids


## Charts list shop ships plus chart-only PVE / salvage hulls.
func _chart_include_manned(ship: Dictionary) -> bool:
	var tags: Array = ship.get("tags", [])
	if str(ship.get("ship_group", "")) == "freighter" or "sleeper" in tags or "pve_creep" in tags:
		return true
	if not TypedVariant.as_bool(ship.get("shop_eligible", true)):
		return false
	return not ("shop_ineligible" in tags)


## Health: Orca HP is capital-scale; freighters always share the capital axis.
func _chart_uses_capital_scale(ship: Dictionary) -> bool:
	var group: String = str(ship.get("ship_group", ""))
	if _CAPITAL_GROUPS.has(group) or group == "freighter":
		return true
	return _chart_kind == Tab.HEALTH and group == "industrial_command"


func _group_sort_key(group: String, capital: bool) -> int:
	if capital:
		return {
			"dreadnought": 10,
			"carrier": 20,
			"force_auxiliary": 30,
			"industrial_command": 35,  # 小鱼 · share capital HP axis
			"capital_industrial": 40,
			"freighter": 50,
		}.get(group, 99)
	return TypedVariant.as_int(_GROUP_ORDER.get(group, 99), 99)


func _chart_ship(sid: int) -> Dictionary:
	if not _working_ships.has(sid):
		var source: Dictionary = DataStore.get_ship(sid)
		if not source.is_empty():
			_working_ships[sid] = source.duplicate(true)
	return _working_ships.get(sid, {})


func _build_chart_row(list: VBoxContainer, sid: int, capital: bool) -> void:
	var ship: Dictionary = _chart_ship(sid)
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = UiLayout.px(54 if _chart_kind == Tab.DAMAGE else 40, self)
	row.add_theme_constant_override("separation", UiLayout.px(5, self))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(row)
	var tonnage: TextureRect = TextureRect.new()
	tonnage.custom_minimum_size = Vector2(UiLayout.px(28, self), UiLayout.px(28, self))
	tonnage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tonnage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tonnage.texture = UiAssets.tonnage_icon(str(ship.get("ship_group", "")))
	tonnage.tooltip_text = str(ship.get("ship_group", ""))
	row.add_child(tonnage)
	var info: VBoxContainer = VBoxContainer.new()
	info.custom_minimum_size.x = UiLayout.px(_CHART_INFO_W, self)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var top_line: HBoxContainer = HBoxContainer.new()
	top_line.alignment = BoxContainer.ALIGNMENT_CENTER
	top_line.add_theme_constant_override("separation", UiLayout.px(3, self))
	info.add_child(top_line)
	var name_label: Label = Label.new()
	name_label.text = str(ship.get("name", sid))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = UiLayout.px(96, self)
	UiAssets.apply_label_font(name_label, true, UiLayout.font_size(13, self))
	top_line.add_child(name_label)
	var weapon_label: Label = Label.new()
	weapon_label.text = _ship_weapon_name(ship) if _chart_kind == Tab.DAMAGE else ""
	weapon_label.visible = _chart_kind == Tab.DAMAGE
	weapon_label.modulate = Color(0.76, 0.82, 0.9, 1.0)
	UiAssets.apply_label_font(weapon_label, false, UiLayout.font_size(11, self))
	var slots_label: Label = null
	var hp_labels: Dictionary = {}
	if _chart_kind == Tab.DAMAGE:
		if TypedVariant.as_bool(ship.get("is_unmanned", false)):
			var rate_label: Label = Label.new()
			rate_label.custom_minimum_size.x = UiLayout.px(54, self)
			rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rate_label.modulate = (
				_COLOR_HULL_HPS if _is_logistic_ship(ship) else _COLOR_UNMANNED_DPS
			)
			UiAssets.apply_label_font(rate_label, false, UiLayout.font_size(11, self))
			top_line.add_child(rate_label)
			slots_label = rate_label
			top_line.add_child(_make_arrow_row(
				func() -> void: _adjust_chart_unmanned_rate(sid, -_UNMANNED_RATE_STEP),
				func() -> void: _adjust_chart_unmanned_rate(sid, _UNMANNED_RATE_STEP)
			))
		else:
			slots_label = Label.new()
			slots_label.custom_minimum_size.x = UiLayout.px(54, self)
			slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			UiAssets.apply_label_font(slots_label, false, UiLayout.font_size(11, self))
			top_line.add_child(slots_label)
			top_line.add_child(_make_arrow_row(
				func() -> void: _adjust_chart_slots(sid, -1),
				func() -> void: _adjust_chart_slots(sid, 1)
			))
		info.add_child(weapon_label)
	else:
		for spec: Array in [
			["盾", "shield_hp"],
			["甲", "armor_hp"],
			["构", "structure_hp"],
		]:
			var hp_field: String = str(spec[1])
			var layer_group: HBoxContainer = HBoxContainer.new()
			layer_group.add_theme_constant_override("separation", UiLayout.px(1, self))
			var layer_label: Label = Label.new()
			layer_label.text = spec[0]
			layer_label.custom_minimum_size.x = UiLayout.px(48, self)
			layer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			UiAssets.apply_label_font(layer_label, false, UiLayout.font_size(10, self))
			layer_group.add_child(layer_label)
			hp_labels[hp_field] = layer_label
			layer_group.add_child(_make_arrow_row(
				func() -> void: _adjust_chart_hp(sid, hp_field, -10.0),
				func() -> void: _adjust_chart_hp(sid, hp_field, 10.0)
			))
			top_line.add_child(layer_group)
	var bar_space: Control = Control.new()
	bar_space.custom_minimum_size = Vector2(
		UiLayout.px(_CHART_BAR_MIN_W, self), UiLayout.px(_CHART_ROW_H, self)
	)
	bar_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_space.clip_contents = true
	row.add_child(bar_space)
	var value_label: Label = Label.new()
	value_label.custom_minimum_size.x = UiLayout.px(110, self)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiAssets.apply_label_font(value_label, true, UiLayout.font_size(12, self))
	row.add_child(value_label)
	var entry: Dictionary = {
		"sid": sid,
		"capital": capital,
		"value_label": value_label,
		"bar_space": bar_space,
		"slots_label": slots_label,
		"hp_labels": hp_labels,
	}
	bar_space.resized.connect(func() -> void: call_deferred("_refresh_chart_values"))
	if _chart_kind == Tab.DAMAGE:
		var hull_bar: ColorRect = ColorRect.new()
		hull_bar.color = (
			_COLOR_UNMANNED_DPS
			if TypedVariant.as_bool(ship.get("is_unmanned", false)) and not _is_logistic_ship(ship)
			else (_COLOR_HULL_HPS if _is_logistic_ship(ship) else _COLOR_HULL_DPS)
		)
		hull_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_space.add_child(hull_bar)
		var wing_bar: ColorRect = ColorRect.new()
		wing_bar.color = _COLOR_WING
		wing_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_space.add_child(wing_bar)
		entry["bar_hull"] = hull_bar
		entry["bar_wing"] = wing_bar
	else:
		var layers: Dictionary = {}
		for pair: Array in [
			["shield", Color(0.24, 0.65, 1.0, 0.94)],
			["armor", Color(0.95, 0.73, 0.22, 0.94)],
			["structure", Color(0.9, 0.3, 0.25, 0.94)],
		]:
			var layer: ColorRect = ColorRect.new()
			layer.color = pair[1]
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_space.add_child(layer)
			layers[pair[0]] = layer
		entry["layers"] = layers
	_chart_entries.append(entry)


func _make_arrow_row(down_action: Callable, up_action: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiLayout.px(1, self))
	for pair: Array in [["▼", down_action], ["▲", up_action]]:
		var btn: Button = Button.new()
		btn.text = str(pair[0])
		btn.custom_minimum_size = Vector2(UiLayout.px(27, self), UiLayout.px(24, self))
		UiAssets.apply_button_font(btn, UiLayout.font_size(10, self))
		var action: Callable = pair[1]
		_wire_repeat_button(btn, action)
		row.add_child(btn)
	return row


func _wire_repeat_button(btn: Button, action: Callable) -> void:
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.process_callback = Timer.TIMER_PROCESS_IDLE
	btn.add_child(timer)
	btn.button_down.connect(func() -> void:
		action.call()
		timer.wait_time = _REPEAT_DELAY_S
		timer.start()
	)
	btn.button_up.connect(func() -> void: timer.stop())
	timer.timeout.connect(func() -> void:
		action.call()
		timer.wait_time = _REPEAT_INTERVAL_S
		timer.start()
	)


func _adjust_chart_slots(sid: int, delta: int) -> void:
	var ship: Dictionary = _chart_ship(sid)
	if ship.is_empty():
		return
	var old_hi: int = TypedVariant.as_int(ship.get("hi_slots", 0), 0)
	var new_hi: int = maxi(0, old_hi + delta)
	if new_hi == old_hi:
		return
	ship["hi_slots"] = new_hi
	if ship.has("attack_weapon_slots"):
		var old_attack: int = TypedVariant.as_int(ship.get("attack_weapon_slots", 0), 0)
		ship["attack_weapon_slots"] = clampi(old_attack + delta, 0, new_hi)
	_dirty_ships[sid] = true
	_refresh_chart_values()


func _adjust_chart_hp(sid: int, field: String, delta_1star: float) -> void:
	var ship: Dictionary = _chart_ship(sid)
	var stars: Array = ship.get("stars", [])
	if stars.is_empty():
		return
	var changed: bool = false
	for i: int in range(stars.size()):
		var star_v: Variant = stars[i]
		if not star_v is Dictionary:
			continue
		var star: Dictionary = star_v
		if not star.has(field):
			continue
		var old: float = TypedVariant.as_float(star.get(field, 0.0), 0.0)
		var value: float = maxf(0.0, old + delta_1star * float(i + 1))
		if not is_equal_approx(old, value):
			star[field] = value
			changed = true
	if changed:
		ship["stars"] = stars
		_dirty_ships[sid] = true
		_refresh_chart_values()


## Unmanned chart arrows: adjust target DPS/HPS; write-back scales star-1 DPH / repair.
func _adjust_chart_unmanned_rate(sid: int, delta_rate: float) -> void:
	var ship: Dictionary = _chart_ship(sid)
	if ship.is_empty() or not TypedVariant.as_bool(ship.get("is_unmanned", false), false):
		return
	var logistic: bool = _is_logistic_ship(ship)
	var key: String = "repair" if logistic else "damage"
	var fields: Array = (
		["shield", "armor", "structure"]
		if logistic
		else ["emp", "thermal", "kinetic", "explosive"]
	)
	var cycle: float = maxf(TypedVariant.as_float(ship.get("attack_cycle_s", 1.0), 1.0), 0.001)
	var old_rate: float = _unmanned_hps(ship) if logistic else _unmanned_dps(ship)
	var new_rate: float = maxf(0.0, old_rate + delta_rate)
	var target_dph: float = new_rate * cycle
	var stars: Array = ship.get("stars", [])
	if stars.is_empty():
		return
	var star0_v: Variant = stars[0]
	if not star0_v is Dictionary:
		return
	var star0: Dictionary = star0_v
	var base: Dictionary = TypedVariant.as_dict(star0.get(key, {}))
	var old_total: float = 0.0
	for field: Variant in fields:
		old_total += TypedVariant.as_float(base.get(field, 0.0), 0.0)
	for i: int in range(stars.size()):
		var star_v: Variant = stars[i]
		if not star_v is Dictionary:
			continue
		var star: Dictionary = star_v
		var payload: Dictionary = TypedVariant.as_dict(star.get(key, {})).duplicate(true)
		if old_total > 0.001:
			var star1_scale: float = target_dph / old_total
			for field: Variant in fields:
				payload[field] = maxf(0.0, TypedVariant.as_float(base.get(field, 0.0), 0.0) * star1_scale * float(i + 1))
		else:
			for field: Variant in fields:
				payload[field] = 0.0
			var primary: String = "armor" if logistic else "emp"
			payload[primary] = target_dph * float(i + 1)
		star[key] = payload
	ship["stars"] = stars
	_dirty_ships[sid] = true
	_refresh_chart_values()


func _is_logistic_ship(ship: Dictionary) -> bool:
	return TypedVariant.as_bool(ship.get("is_logistic", false)) or str(ship.get("weapon_fx", "")) == "heal"


func _is_mining_unmanned(ship: Dictionary) -> bool:
	var kind: String = str(ship.get("unmanned_kind", ""))
	return (
		kind == "mining_drone"
		or kind == "mining_excavator"
		or str(ship.get("weapon_fx", "")) == "mining"
		or str(ship.get("ship_group", "")) == "mining_drone"
	)


func _ship_weapon_name(ship: Dictionary) -> String:
	if TypedVariant.as_bool(ship.get("is_unmanned", false)):
		var family: String = str({
			"laser": "激光",
			"rail": "磁轨",
			"cannon": "加农炮",
			"missile": "导弹",
			"heal": "维修器",
			"mining": "露天采矿器",
		}.get(str(ship.get("weapon_fx", "")), "武器"))
		return "内置%s" % family
	var module_id: int = (
		ShipWeaponDerive.resolve_repair_module_id(ship)
		if _is_logistic_ship(ship)
		else ShipWeaponDerive.resolve_module_id(ship)
	)
	var module: Dictionary = _working_modules.get(module_id, DataStore.get_module(module_id))
	var base: String = str(module.get("nameZH", "")).strip_edges()
	if base == "":
		base = str(module.get("nameEN", module.get("nameSDE", ""))).strip_edges()
	var wing: String = _ship_wing_name(ship)
	if wing == "":
		return base if base != "" else "无武器"
	return wing if base == "" else "%s + %s" % [base, wing]


func _ship_hull_hps(ship: Dictionary) -> float:
	if TypedVariant.as_bool(ship.get("is_unmanned", false)):
		return _unmanned_hps(ship)
	var module_id: int = TypedVariant.as_int(ship.get("source_repair_module_type_id", 0), 0)
	if module_id <= 0:
		module_id = ShipWeaponDerive.resolve_repair_module_id(ship)
	var module: Dictionary = _working_modules.get(module_id, DataStore.get_module(module_id))
	if module.is_empty():
		return 0.0
	var per_slot: float = TypedVariant.as_float(module.get("structureDamageAmount", module.get("armorDamageAmount", module.get("shieldBonus", 0.0))), 0.0)
	var cycle_ms: float = TypedVariant.as_float(module.get("duration", module.get("rateOfFire", 3000.0)), 3000.0)
	var slots: int = maxi(TypedVariant.as_int(ship.get("hi_slots", 0), 0), 0)
	return per_slot * float(slots) / maxf(cycle_ms / 1000.0, 0.001)


func _ship_hps(ship: Dictionary) -> float:
	return _ship_hull_hps(ship) + _ship_wing_hps(ship)


## Built-in output of a drone / fighter template: star-1 payload over its own cycle.
func _unmanned_dps(ship: Dictionary) -> float:
	return _unmanned_star_rate(ship, "damage", ["emp", "thermal", "kinetic", "explosive"])


func _unmanned_hps(ship: Dictionary) -> float:
	return _unmanned_star_rate(ship, "repair", ["shield", "armor", "structure"])


func _unmanned_star_rate(ship: Dictionary, key: String, fields: Array) -> float:
	var stars: Array = ship.get("stars", [])
	if stars.is_empty():
		return 0.0
	var star0_v: Variant = stars[0]
	if not star0_v is Dictionary:
		return 0.0
	var star0: Dictionary = star0_v
	var payload: Dictionary = TypedVariant.as_dict(star0.get(key, {}))
	var total: float = 0.0
	for field: Variant in fields:
		total += TypedVariant.as_float(payload.get(field, 0.0), 0.0)
	return total / maxf(TypedVariant.as_float(ship.get("attack_cycle_s", 1.0), 1.0), 0.001)


## Same launch policy as CombatResolver._drone_spawn_policy_for_ship / capital aux.
func _drone_spawn_policy(ship: Dictionary) -> Dictionary:
	var mining_drone_id: int = TypedVariant.as_int(ship.get("mining_drone_id", 0), 0)
	if mining_drone_id > 0:
		var mcount: int = TypedVariant.as_int(ship.get("drone_bay_slots", ship.get("drone_count_cap", 0)), 0)
		if mcount <= 0:
			mcount = TypedVariant.as_int(ship.get("mining_drone_count", 4), 4)
		return {"count": maxi(mcount, 0), "drone_id": mining_drone_id}
	var fighter_id: int = TypedVariant.as_int(ship.get("fighter_unit_id", 0), 0)
	if fighter_id > 0 or str(ship.get("capital_role", "")) == "carrier":
		if fighter_id <= 0:
			return {"count": 0, "drone_id": 0}
		var tubes: int = maxi(TypedVariant.as_int(ship.get("fighter_squadrons", 3), 3), 1) * maxi(
			TypedVariant.as_int(ship.get("fighter_tubes_per_squadron", 3), 3), 1
		)
		return {"count": tubes, "drone_id": fighter_id}
	var repair_id: int = TypedVariant.as_int(ship.get("heavy_repair_drone_id", 0), 0)
	if repair_id > 0 or str(ship.get("capital_role", "")) == "force_auxiliary":
		if repair_id <= 0:
			return {"count": 0, "drone_id": 0}
		return {
			"count": maxi(TypedVariant.as_int(ship.get("heavy_repair_drone_count", 4), 4), 0),
			"drone_id": repair_id,
		}
	var race: String = str(ship.get("race", "amarr")).to_lower()
	var group: String = str(ship.get("ship_group", "")).to_lower()
	var sid: int = TypedVariant.as_int(ship.get("id", 0), 0)
	if _DRONE_COUNT_EXCEPTIONS.has(sid):
		var cnt: int = TypedVariant.as_int(_DRONE_COUNT_EXCEPTIONS[sid], 0)
		if group == "battlecruiser":
			return {"count": cnt, "drone_id": TypedVariant.as_int(_RACE_DRONE_MEDIUM.get(race, 1005), 1005)}
		if group == "battleship":
			return {"count": cnt, "drone_id": TypedVariant.as_int(_RACE_DRONE_HEAVY.get(race, 1011), 1011)}
	if group == "battlecruiser":
		return {"count": 1, "drone_id": TypedVariant.as_int(_RACE_DRONE_MEDIUM.get(race, 1005), 1005)}
	if group == "battleship":
		return {"count": 2, "drone_id": TypedVariant.as_int(_RACE_DRONE_HEAVY.get(race, 1011), 1011)}
	var slots: int = TypedVariant.as_int(ship.get("drone_bay_slots", ship.get("drone_count_cap", 0)), 0)
	if slots <= 0:
		var bw: float = TypedVariant.as_float(ship.get("drone_bandwidth", 0.0), 0.0)
		if bw > 0.0:
			slots = floori(bw / _DRONE_BW_COST)
	if slots <= 0:
		return {"count": 0, "drone_id": 0}
	return {"count": slots, "drone_id": TypedVariant.as_int(_RACE_DRONE_LIGHT.get(race, 1001), 1001)}


func _is_combat_wing_unit(drone: Dictionary) -> bool:
	if drone.is_empty() or _is_mining_unmanned(drone):
		return false
	return not _is_logistic_ship(drone)


## Capitals / bay ships whose combat/logistics output comes from launched units.
func _ship_wing_name(ship: Dictionary) -> String:
	var wing: Dictionary = _drone_spawn_policy(ship)
	var unit_id: int = TypedVariant.as_int(wing.get("drone_id", 0), 0)
	var count: int = TypedVariant.as_int(wing.get("count", 0), 0)
	if unit_id <= 0 or count <= 0:
		return ""
	var drone: Dictionary = _chart_ship(unit_id)
	## Damage chart only labels combat / repair wings — excavators are mining, not DPS/HPS.
	if _is_mining_unmanned(drone):
		return ""
	return "%s ×%d" % [str(drone.get("name", "僚机")), count]


func _ship_wing_hps(ship: Dictionary) -> float:
	if TypedVariant.as_bool(ship.get("is_unmanned", false)):
		return 0.0
	var wing: Dictionary = _drone_spawn_policy(ship)
	var drone_id: int = TypedVariant.as_int(wing.get("drone_id", 0), 0)
	var count: int = TypedVariant.as_int(wing.get("count", 0), 0)
	if drone_id <= 0 or count <= 0:
		return 0.0
	var drone: Dictionary = _chart_ship(drone_id)
	if not _is_logistic_ship(drone):
		return 0.0
	return _unmanned_hps(drone) * float(count)


func _ship_wing_dps(ship: Dictionary) -> float:
	if TypedVariant.as_bool(ship.get("is_unmanned", false)):
		return 0.0
	var wing: Dictionary = _drone_spawn_policy(ship)
	var drone_id: int = TypedVariant.as_int(wing.get("drone_id", 0), 0)
	var count: int = TypedVariant.as_int(wing.get("count", 0), 0)
	if drone_id <= 0 or count <= 0:
		return 0.0
	var drone: Dictionary = _chart_ship(drone_id)
	if not _is_combat_wing_unit(drone):
		return 0.0
	return _unmanned_dps(drone) * float(count)


func _ship_hull_dps(ship: Dictionary) -> float:
	if TypedVariant.as_bool(ship.get("is_unmanned", false)):
		return _unmanned_dps(ship)
	if str(ship.get("capital_role", "")) == "carrier":
		return 0.0
	var slots: int = TypedVariant.as_int(ship.get("attack_weapon_slots", 0), 0)
	if slots <= 0:
		slots = TypedVariant.as_int(ship.get("hi_slots", 0), 0)
	var module_id: int = TypedVariant.as_int(ship.get("source_module_type_id", 0), 0)
	if module_id <= 0:
		module_id = ShipWeaponDerive.resolve_module_id(ship)
	var module: Dictionary = _working_modules.get(module_id, DataStore.get_module(module_id))
	if not module.is_empty():
		var dph: float = 0.0
		for field: String in ["emDamage", "thermalDamage", "kineticDamage", "explosiveDamage"]:
			dph += TypedVariant.as_float(module.get(field, 0.0), 0.0)
		var cycle: float = TypedVariant.as_float(module.get("rateOfFire", 1000.0), 1000.0) / 1000.0
		return dph * float(maxi(slots, 0)) / maxf(cycle, 0.001)
	return 0.0


func _ship_output_parts(ship: Dictionary) -> Dictionary:
	if _is_logistic_ship(ship):
		return {"hull": _ship_hull_hps(ship), "wing": _ship_wing_hps(ship)}
	return {"hull": _ship_hull_dps(ship), "wing": _ship_wing_dps(ship)}


func _ship_output_per_s(ship: Dictionary) -> float:
	var parts: Dictionary = _ship_output_parts(ship)
	return TypedVariant.as_float(parts["hull"], 0.0) + TypedVariant.as_float(parts["wing"], 0.0)


func _ship_dps(ship: Dictionary) -> float:
	return _ship_hull_dps(ship) + _ship_wing_dps(ship)


func _ship_hp(ship: Dictionary) -> Dictionary:
	var stars: Array = ship.get("stars", [])
	if stars.is_empty():
		return {"shield": 0.0, "armor": 0.0, "structure": 0.0, "total": 0.0}
	var star0_v: Variant = stars[0]
	if not star0_v is Dictionary:
		return {"shield": 0.0, "armor": 0.0, "structure": 0.0, "total": 0.0}
	var star: Dictionary = star0_v
	var shield: float = TypedVariant.as_float(star.get("shield_hp", 0.0), 0.0)
	var armor: float = TypedVariant.as_float(star.get("armor_hp", 0.0), 0.0)
	var structure: float = TypedVariant.as_float(star.get("structure_hp", 0.0), 0.0)
	return {
		"shield": shield,
		"armor": armor,
		"structure": structure,
		"total": shield + armor + structure,
	}


func _refresh_chart_values() -> void:
	if _chart_entries.is_empty():
		return
	var maxima: Dictionary = {false: 1.0, true: 1.0}
	for entry: Dictionary in _chart_entries:
		var ship: Dictionary = _chart_ship(TypedVariant.as_int(entry["sid"], 0))
		var value: float = (
			_ship_output_per_s(ship)
			if _chart_kind == Tab.DAMAGE
			else TypedVariant.as_float(_ship_hp(ship)["total"], 0.0)
		)
		entry["value"] = value
		var capital: bool = TypedVariant.as_bool(entry["capital"], false)
		maxima[capital] = maxf(TypedVariant.as_float(maxima[capital], 1.0), value)
	for entry: Dictionary in _chart_entries:
		var ship: Dictionary = _chart_ship(TypedVariant.as_int(entry["sid"], 0))
		var capital: bool = TypedVariant.as_bool(entry["capital"], false)
		var maximum: float = maxf(TypedVariant.as_float(maxima[capital], 1.0), 1.0)
		var value: float = TypedVariant.as_float(entry["value"], 0.0)
		var bar_space_v: Variant = entry["bar_space"]
		if not bar_space_v is Control:
			continue
		var bar_space: Control = bar_space_v
		var chart_w: float = maxf(
			bar_space.size.x,
			UiLayout.px(_CHART_BAR_MIN_W, self)
		)
		var bar_h: float = UiLayout.px(_CHART_ROW_H - 10.0, self)
		if _chart_kind == Tab.DAMAGE:
			var parts: Dictionary = _ship_output_parts(ship)
			var hull: float = TypedVariant.as_float(parts["hull"], 0.0)
			var wing: float = TypedVariant.as_float(parts["wing"], 0.0)
			var unit: String = "HPS" if _is_logistic_ship(ship) else "DPS"
			var value_label_v: Variant = entry["value_label"]
			if value_label_v is Label:
				var value_label: Label = value_label_v
				if wing > 0.05:
					value_label.text = "%.1f %s (%.0f+%.0f)" % [value, unit, hull, wing]
				else:
					value_label.text = "%.1f %s" % [value, unit]
			var y: float = UiLayout.px(5, self)
			var hull_w: float = chart_w * clampf(hull / maximum, 0.0, 1.0)
			var wing_w: float = chart_w * clampf(wing / maximum, 0.0, 1.0)
			var hull_bar_v: Variant = entry.get("bar_hull")
			var wing_bar_v: Variant = entry.get("bar_wing")
			if hull_bar_v is ColorRect and wing_bar_v is ColorRect:
				var hull_bar: ColorRect = hull_bar_v
				var wing_bar: ColorRect = wing_bar_v
				hull_bar.position = Vector2(0.0, y)
				hull_bar.size = Vector2(hull_w, bar_h)
				wing_bar.position = Vector2(hull_w, y)
				wing_bar.size = Vector2(wing_w, bar_h)
				wing_bar.visible = wing > 0.0
			var slots_label_v: Variant = entry.get("slots_label")
			if slots_label_v is Label:
				var slots_label: Label = slots_label_v
				if TypedVariant.as_bool(ship.get("is_unmanned", false), false):
					slots_label.text = "%.0f %s" % [value, unit]
				else:
					slots_label.text = "高槽 %d" % TypedVariant.as_int(ship.get("hi_slots", 0), 0)
		else:
			var value_label_v: Variant = entry["value_label"]
			if value_label_v is Label:
				var value_label_else: Label = value_label_v
				value_label_else.text = "%.0f" % value
			var hp: Dictionary = _ship_hp(ship)
			var hp_labels_v: Variant = entry.get("hp_labels")
			if hp_labels_v is Dictionary:
				var hp_labels: Dictionary = hp_labels_v
				var shield_l_v: Variant = hp_labels.get("shield_hp")
				var armor_l_v: Variant = hp_labels.get("armor_hp")
				var struct_l_v: Variant = hp_labels.get("structure_hp")
				if shield_l_v is Label:
					var shield_l: Label = shield_l_v
					shield_l.text = "盾 %.0f" % TypedVariant.as_float(hp["shield"], 0.0)
				if armor_l_v is Label:
					var armor_l: Label = armor_l_v
					armor_l.text = "甲 %.0f" % TypedVariant.as_float(hp["armor"], 0.0)
				if struct_l_v is Label:
					var struct_l: Label = struct_l_v
					struct_l.text = "构 %.0f" % TypedVariant.as_float(hp["structure"], 0.0)
			var layers_v: Variant = entry.get("layers")
			if layers_v is Dictionary:
				var layers: Dictionary = layers_v
				var x: float = 0.0
				for key: String in ["shield", "armor", "structure"]:
					var layer_v: Variant = layers.get(key)
					if not layer_v is ColorRect:
						continue
					var layer: ColorRect = layer_v
					var layer_w: float = chart_w * TypedVariant.as_float(hp[key], 0.0) / maximum
					layer.position = Vector2(x, UiLayout.px(5, self))
					layer.size = Vector2(layer_w, bar_h)
					x += layer_w


func _rebuild_function_module_fields(data: Dictionary) -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_grid.columns = 1
	var blurb: String = str(data.get("blurb", ""))
	var owner_id: String = _current_fn_id
	if blurb.strip_edges() == "":
		var empty: Label = Label.new()
		empty.text = "（无 blurb 模板）"
		UiAssets.apply_label_font(empty, false, UiLayout.font_size(14, self))
		_grid.add_child(empty)
		return
	var holes: Dictionary = data.get("blurb_holes", {}) if typeof(data.get("blurb_holes", {})) == TYPE_DICTIONARY else {}
	var fn_wrap: VBoxContainer = VBoxContainer.new()
	fn_wrap.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
	fn_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(fn_wrap)
	var hint: Label = Label.new()
	hint.text = "简介中挖洞改数值（洞嵌在文句里；悬停洞可见字段名）"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(hint, true, UiLayout.font_size(13, self))
	fn_wrap.add_child(hint)
	## Flow the prose with holes inline — not a fixed form row with text wrapping around it.
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 0)
	flow.add_theme_constant_override("v_separation", UiLayout.margin_px(6, self))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fn_wrap.add_child(flow)
	var fs: float = UiLayout.font_size(15, self)
	for part_v: Variant in _split_blurb_template(blurb):
		var part: String = str(part_v)
		if part.begins_with("{") and part.ends_with("}") and part.length() >= 2:
			var key: String = part.substr(1, part.length() - 2)
			var edit: LineEdit = LineEdit.new()
			var sample: Variant = holes.get(key, 0)
			edit.text = _value_text(sample)
			edit.tooltip_text = key
			edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
			edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var pad: float = float(UiLayout.px(18, self))
			var min_w: float = float(UiLayout.px(52, self))
			var approx: float = float(edit.text.length()) * float(fs) * 0.62 + pad
			edit.custom_minimum_size = Vector2(maxf(min_w, approx), float(UiLayout.px(28, self)))
			_apply_edit_font(edit, 14)
			_style_fn_hole_edit(edit)
			edit.text_submitted.connect(func(t: String) -> void: _commit_fn_hole(owner_id, key, t))
			edit.focus_exited.connect(func() -> void: _commit_fn_hole(owner_id, key, edit.text))
			flow.add_child(edit)
		else:
			_append_inline_blurb_chars(flow, part, fs)


func _append_inline_blurb_chars(flow: HFlowContainer, text: String, font_size: int) -> void:
	## One Label per character so HFlow can wrap mid-sentence around inline holes.
	for i: int in text.length():
		var lab: Label = Label.new()
		lab.text = text.substr(i, 1)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiAssets.apply_label_font(lab, false, font_size)
		flow.add_child(lab)


func _style_fn_hole_edit(edit: LineEdit) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.18, 0.26, 0.95)
	sb.border_color = Color(0.55, 0.82, 0.95, 0.95)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	edit.add_theme_stylebox_override("normal", sb)
	var sb_f: StyleBoxFlat = sb.duplicate() as StyleBoxFlat as StyleBoxFlat
	sb_f.border_color = Color(0.85, 0.95, 1.0, 1.0)
	edit.add_theme_stylebox_override("focus", sb_f)


func _split_blurb_template(blurb: String) -> Array:
	var out: Array = []
	var i: int = 0
	while i < blurb.length():
		var j: int = blurb.find("{", i)
		if j < 0:
			out.append(blurb.substr(i))
			break
		if j > i:
			out.append(blurb.substr(i, j - i))
		var k: int = blurb.find("}", j)
		if k < 0:
			out.append(blurb.substr(j))
			break
		out.append(blurb.substr(j, k - j + 1))
		i = k + 1
	return out


func _commit_fn_hole(item_id: String, key: String, text: String) -> void:
	if item_id == "" or key == "":
		return
	if not _working_function_modules.has(item_id):
		return
	var data: Dictionary = _working_function_modules[item_id]
	var holes: Dictionary = data.get("blurb_holes", {}) if typeof(data.get("blurb_holes", {})) == TYPE_DICTIONARY else {}
	if not holes.has(key):
		holes[key] = 0
	var old_value: Variant = holes[key]
	var new_value: Variant = _parse_like(old_value, text)
	if _same_value(old_value, new_value):
		return
	holes[key] = new_value
	data["blurb_holes"] = holes
	_apply_fn_hole_to_module(data, key, new_value)
	_dirty_function_modules = true
	if _tab == Tab.FUNCTION_MODULES and item_id == _current_fn_id:
		_status.text = "blurb_holes.%s → %s（未保存）· %s" % [key, _value_text(new_value), _CANCEL_HINT]
		_rebuild_function_module_fields(data)


func _apply_fn_hole_to_module(data: Dictionary, key: String, value: Variant) -> void:
	## Dig-hole edits write through to matching module leaves (EQUIPMENT.md §8).
	if data.has(key) and typeof(data[key]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		data[key] = value
	var effects: Variant = data.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return
	for fx_v: Variant in effects:
		if typeof(fx_v) != TYPE_DICTIONARY:
			continue
		var fx: Dictionary = fx_v
		if fx.has(key) and typeof(fx[key]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			fx[key] = value


func _rebuild_fields(data: Dictionary) -> void:
	if _tab == Tab.FUNCTION_MODULES:
		_rebuild_function_module_fields(data)
		return
	for c: Node in _grid.get_children():
		c.queue_free()
	var rows: Array = []
	_flatten(data, [], rows)
	var owner_id: int = _current_id
	var owner_tab: Tab = _tab
	for row: Dictionary in rows:
		var path: Array = row["path"]
		var label: Label = Label.new()
		label.text = _path_text(path)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiAssets.apply_label_font(label, false, UiLayout.font_size(14, self))
		_grid.add_child(label)
		var locked: bool = _is_path_locked(owner_tab, path)
		var edit: LineEdit = LineEdit.new()
		edit.text = _value_text(row["value"])
		edit.custom_minimum_size = Vector2(UiLayout.px(180, self), 0)
		_apply_edit_font(edit, 14)
		edit.editable = not locked
		if locked:
			edit.modulate = Color(0.72, 0.76, 0.82, 1.0)
			edit.tooltip_text = "只读：种族 / 模型 / 立绘 / 装备图标相关字段不可改"
		else:
			edit.text_submitted.connect(func(t: String) -> void: _commit(owner_tab, owner_id, path, t))
			edit.focus_exited.connect(func() -> void: _commit(owner_tab, owner_id, path, edit.text))
		_grid.add_child(edit)


func _is_path_locked(tab: Tab, path: Array) -> bool:
	if path.is_empty():
		return false
	var root: String = str(path[0])
	match tab:
		Tab.SHIPS:
			return _LOCKED_SHIP_ROOTS.has(root)
		Tab.MODULES:
			return _LOCKED_MODULE_ROOTS.has(root)
		_:
			return true


func _flatten(value: Variant, path: Array, out: Array) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			if value is Dictionary:
				var dict: Dictionary = value
				for k: Variant in dict.keys():
					_flatten(dict[k], path + [k], out)
		TYPE_ARRAY:
			var arr: Array = value
			for i: int in range(arr.size()):
				_flatten(arr[i], path + [i], out)
		_:
			if not path.is_empty():
				out.append({"path": path, "value": value})


func _path_text(path: Array) -> String:
	var s: String = ""
	for p: Variant in path:
		if typeof(p) == TYPE_INT:
			s += "[%d]" % TypedVariant.as_int(p, 0)
		else:
			s += ("." if s != "" else "") + str(p)
	return s


func _value_text(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return String.num(TypedVariant.as_float(v, 0.0), 4).rstrip("0").rstrip(".")
	if typeof(v) == TYPE_BOOL:
		return "true" if TypedVariant.as_bool(v, false) else "false"
	return str(v)


func _commit(tab: Tab, item_id: int, path: Array, text: String) -> void:
	if item_id < 0 or path.is_empty():
		return
	if _is_path_locked(tab, path):
		return
	var container: Dictionary = {}
	match tab:
		Tab.SHIPS:
			if not _working_ships.has(item_id):
				return
			var ship_v: Variant = _working_ships[item_id]
			if not ship_v is Dictionary:
				return
			container = ship_v
		Tab.MODULES:
			if not _working_modules.has(item_id):
				return
			var mod_v: Variant = _working_modules[item_id]
			if not mod_v is Dictionary:
				return
			container = mod_v
		_:
			return
	for i: int in range(path.size() - 1):
		var next_v: Variant = container[path[i]]
		if not next_v is Dictionary:
			return
		container = next_v
	var key: Variant = path[path.size() - 1]
	var old_value: Variant = container[key]
	var new_value: Variant = _parse_like(old_value, text)
	if _same_value(old_value, new_value):
		return
	container[key] = new_value
	match tab:
		Tab.SHIPS:
			_dirty_ships[item_id] = true
		Tab.MODULES:
			_dirty_modules = true
		_:
			pass
	if tab == _tab and item_id == _current_id:
		_status.text = "%s → %s（未保存）· %s" % [_path_text(path), _value_text(new_value), _CANCEL_HINT]


func _parse_like(old_value: Variant, text: String) -> Variant:
	var t: String = text.strip_edges()
	match typeof(old_value):
		TYPE_FLOAT:
			return float(t) if t.is_valid_float() else old_value
		TYPE_INT:
			return int(t) if t.is_valid_int() else old_value
		TYPE_BOOL:
			return t.to_lower() in ["true", "1", "yes", "on"]
		_:
			return t


func _same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(TypedVariant.as_float(a, 0.0), TypedVariant.as_float(b, 0.0))
	return a == b


func _save_all() -> Array:
	var changed: Array = []
	_last_equipment_saved = false
	for sid: Variant in _dirty_ships.keys():
		var data: Dictionary = _working_ships.get(sid, {})
		if data.is_empty():
			continue
		if DataStore.save_ship_json(TypedVariant.as_int(sid, 0), data):
			changed.append(TypedVariant.as_int(sid, 0))
	_dirty_ships.clear()
	var equip_dirty: bool = false
	if _dirty_modules:
		if DataStore.save_equipment_table(_working_modules):
			equip_dirty = true
		_dirty_modules = false
	if _dirty_function_modules:
		if DataStore.save_function_modules_table(_working_function_modules):
			equip_dirty = true
		_dirty_function_modules = false
	if _dirty_titan_pvp and DataStore.has_method("save_balance_file"):
		if DataStore.save_balance_file("titan_pvp.json", _working_titan_pvp):
			equip_dirty = true
		_dirty_titan_pvp = false
	_last_equipment_saved = equip_dirty
	if not changed.is_empty() or equip_dirty:
		DataStore.reload_all()
		_working_ships.clear()
		_working_modules = DataStore.modules.duplicate(true)
		_working_function_modules = DataStore.function_modules.duplicate(true)
		_reload_ids()
	return changed


func _downloads_dir() -> String:
	return OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)


func _export_dest(fname: String) -> String:
	var downloads: String = _downloads_dir()
	if downloads != "" and DirAccess.dir_exists_absolute(downloads):
		return downloads.path_join(fname)
	const FALLBACK: String = "user://debug/exports"
	DirAccess.make_dir_recursive_absolute(FALLBACK)
	return FALLBACK.path_join(fname)


func _path_for_display(path: String) -> String:
	if path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _export_ships_csv() -> String:
	var abs_path: String = _export_dest(EXPORT_SHIPS_FILE)
	var ids: Array = DataStore.ships.keys()
	ids.sort()
	var col_set: Dictionary = {}
	var rows_by_id: Dictionary = {}
	for k: Variant in ids:
		var sid: int = TypedVariant.as_int(k, 0)
		var data: Dictionary = DataStore.get_ship(sid)
		if data.is_empty():
			continue
		var leaves: Array = []
		_flatten(data, [], leaves)
		var flat: Dictionary = {}
		for leaf: Dictionary in leaves:
			var leaf_path_v: Variant = leaf.get("path", [])
			var leaf_path: Array = leaf_path_v if leaf_path_v is Array else []
			var col: String = _path_text(leaf_path)
			flat[col] = _value_text(leaf.get("value"))
			col_set[col] = true
		rows_by_id[sid] = flat
	var written: String = _write_csv(abs_path, ["id"], col_set, rows_by_id, ids)
	return _path_for_display(written) if written != "" else ""


func _export_equipment_csv() -> String:
	var abs_path: String = _export_dest(EXPORT_EQUIP_FILE)
	var col_set: Dictionary = {}
	var rows_by_key: Dictionary = {}
	var keys: Array = []
	var tids: Array = DataStore.modules.keys()
	tids.sort()
	for tid_v: Variant in tids:
		var tid: int = TypedVariant.as_int(tid_v, 0)
		var data: Dictionary = DataStore.modules[tid_v]
		var leaves: Array = []
		_flatten(data, [], leaves)
		var flat: Dictionary = {}
		for leaf: Dictionary in leaves:
			var leaf_path_v: Variant = leaf.get("path", [])
			var leaf_path: Array = leaf_path_v if leaf_path_v is Array else []
			var col: String = _path_text(leaf_path)
			flat[col] = _value_text(leaf.get("value"))
			col_set[col] = true
		var row_key: String = str(tid)
		rows_by_key[row_key] = flat
		keys.append(row_key)
	var written: String = _write_csv(abs_path, ["row_key"], col_set, rows_by_key, keys)
	return _path_for_display(written) if written != "" else ""


func _write_csv(abs_path: String, id_cols: Array, col_set: Dictionary, rows_by_id: Dictionary, ids: Array) -> String:
	var cols: Array = col_set.keys()
	cols.sort()
	var lines: PackedStringArray = PackedStringArray()
	var header: PackedStringArray = PackedStringArray()
	for c: Variant in id_cols:
		header.append(str(c))
	for c: Variant in cols:
		if str(c) in id_cols:
			continue
		header.append(str(c))
	lines.append(_csv_join(header))
	for sid: Variant in ids:
		if not rows_by_id.has(sid):
			continue
		var flat: Dictionary = rows_by_id[sid]
		var cells: PackedStringArray = PackedStringArray()
		if id_cols.size() == 1 and str(id_cols[0]) == "id":
			cells.append(str(TypedVariant.as_int(sid, 0)))
		elif id_cols.size() == 1 and str(id_cols[0]) == "row_key":
			cells.append(str(sid))
		for c: Variant in cols:
			if str(c) in id_cols:
				continue
			cells.append(str(flat.get(str(c), "")))
		lines.append(_csv_join(cells))
	var body: String = "\n".join(lines) + "\n"
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null and not abs_path.begins_with("user://"):
		## Downloads may exist but be unwritable (mobile scoped storage).
		const FALLBACK: String = "user://debug/exports"
		DirAccess.make_dir_recursive_absolute(FALLBACK)
		abs_path = FALLBACK.path_join(abs_path.get_file())
		f = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_warning("[ShipDataEditor] cannot write %s" % abs_path)
		return ""
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	f.store_string(body)
	f.close()
	return abs_path


func _csv_join(cells: PackedStringArray) -> String:
	var out: PackedStringArray = PackedStringArray()
	for cell: String in cells:
		out.append(_csv_escape(cell))
	return ",".join(out)


func _csv_escape(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k: InputEventKey = event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		close_and_save()
		get_viewport().set_input_as_handled()
