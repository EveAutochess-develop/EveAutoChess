extends Control
class_name ShipDataEditor
## UI_AND_SHELL §2.5.1 — developer table for ships + equipment modules.
## Opens paused, edits a working copy, writes back on exit (content_runtime + editor baseline).

## Equipment edits change manned DPH too (SHIP_STATS_V2 §2.2), so they must reach guests
## even when no ship JSON moved.
signal closed(changed_ids: Array, equipment_changed: bool)

enum Tab { SHIPS, MODULES, DAMAGE, HEALTH }

const _CANCEL_HINT := "退出即自动保存；改动写入 content_runtime，删除该文件即回滚基线。"
const EXPORT_SHIPS_FILE := "eveac_ships_table.csv"
const EXPORT_EQUIP_FILE := "eveac_equipment_table.csv"
## UI_AND_SHELL §2.5.1 — identity / art / equipment-icon keys stay display-only.
const _LOCKED_SHIP_ROOTS := {
	"race": true,
	"model_key": true,
	"sof_hull": true,
	"portrait": true,
	"weapon_fx": true,
	"weapon_tier": true,
	"source_module_type_id": true,
	"source_repair_module_type_id": true,
}
const _LOCKED_MODULE_ROOTS := {
	"typeID": true,
}
const _CHART_BAR_MIN_W := 260.0
const _CHART_ROW_H := 34.0
const _CHART_INFO_W := 410.0
const _REPEAT_DELAY_S := 0.5
const _REPEAT_INTERVAL_S := 0.05
const _UNMANNED_RATE_STEP := 1.0
const _COLOR_HULL_DPS := Color(0.34, 0.75, 1.0, 0.92)
const _COLOR_HULL_HPS := Color(0.28, 0.9, 0.48, 0.94)
const _COLOR_WING := Color(0.78, 0.28, 1.0, 0.96)  ## drone / fighter segment — distinct purple
const _COLOR_UNMANNED_DPS := Color(0.7, 0.38, 1.0, 0.94)
const _DRONE_BW_COST := 5.0
const _RACE_DRONE_LIGHT := {"amarr": 1001, "caldari": 1002, "gallente": 1003, "minmatar": 1004}
const _RACE_DRONE_MEDIUM := {"amarr": 1005, "caldari": 1006, "gallente": 1007, "minmatar": 1008}
const _RACE_DRONE_HEAVY := {"amarr": 1011, "caldari": 1012, "gallente": 1013, "minmatar": 1014}
const _DRONE_COUNT_EXCEPTIONS := {42: 5, 44: 4, 55: 4, 56: 5}
const _CAPITAL_GROUPS := {
	"dreadnought": true,
	"carrier": true,
	"force_auxiliary": true,
	"capital_industrial": true,  # 长须鲸 · UI_AND_SHELL §2.5.1 chart bucket
}
const _GROUP_ORDER := {
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
var _dirty_ships: Dictionary = {}
var _dirty_modules: bool = false
var _current_id: int = -1
var _pause_owner: bool = false
var _was_paused: bool = false
var _last_equipment_saved: bool = false

var _cap: Label
var _list: ItemList
var _search: LineEdit
var _title: Label
var _grid: GridContainer
var _status: Label
var _export_btn: Button
var _tab_btns: Array[Button] = []
var _left_panel: VBoxContainer
var _field_scroll: ScrollContainer
var _chart_entries: Array = []
var _chart_kind: Tab = Tab.DAMAGE


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
	_working_ships.clear()
	_working_modules = DataStore.modules.duplicate(true)
	_dirty_ships.clear()
	_dirty_modules = false
	_set_tab(Tab.SHIPS, true)
	visible = true
	if pause_game and not _pause_owner:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_pause_owner = true
	if _export_btn:
		_export_btn.visible = _can_export_table()
	_status.text = _CANCEL_HINT


## Autosave + restore pause. Emits the ship ids whose JSON actually changed.
func close_and_save() -> void:
	_finish_close(_save_all())


## PC-only: save, overwrite Downloads CSVs, then exit.
func close_and_save_and_export() -> void:
	if not _can_export_table():
		_status.text = "仅 PC 可导出表格"
		return
	var changed := _save_all()
	var ship_path := _export_ships_csv()
	var equip_path := _export_equipment_csv()
	if ship_path == "" and equip_path == "":
		_status.text = "保存成功，但导出失败（无法写入下载目录）"
		_finish_close(changed)
		return
	_status.text = "已导出：%s · %s" % [ship_path, equip_path]
	_finish_close(changed)


func _finish_close(changed: Array) -> void:
	visible = false
	if _pause_owner:
		get_tree().paused = _was_paused
		_pause_owner = false
	closed.emit(changed, _last_equipment_saved)


static func _can_export_table() -> bool:
	return not UiLayout.is_mobile()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60
	frame.offset_top = 40
	frame.offset_right = -60
	frame.offset_bottom = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.98)
	sb.border_color = Color(0.35, 0.72, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UiLayout.margin_px(14, self))
	frame.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
	_cap = Label.new()
	_cap.text = "全舰船装备数据调整"
	_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(_cap, true, UiLayout.font_size(22, self))
	head.add_child(_cap)
	var save_btn := Button.new()
	save_btn.text = "保存并退出"
	UiAssets.apply_button_font(save_btn, UiLayout.font_size(16, self))
	save_btn.pressed.connect(close_and_save)
	head.add_child(save_btn)
	_export_btn = Button.new()
	_export_btn.text = "保存并退出顺带导出表格"
	UiAssets.apply_button_font(_export_btn, UiLayout.font_size(16, self))
	_export_btn.pressed.connect(close_and_save_and_export)
	_export_btn.visible = _can_export_table()
	head.add_child(_export_btn)
	col.add_child(head)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", UiLayout.margin_px(6, self))
	col.add_child(tabs)
	_tab_btns.clear()
	for pair in [
		[Tab.SHIPS, "舰船"],
		[Tab.MODULES, "装备"],
		[Tab.DAMAGE, "伤害"],
		[Tab.HEALTH, "血量"],
	]:
		var b := Button.new()
		b.text = str(pair[1])
		b.toggle_mode = true
		b.button_pressed = int(pair[0]) == int(Tab.SHIPS)
		UiAssets.apply_button_font(b, UiLayout.font_size(15, self))
		var t: Tab = pair[0]
		b.pressed.connect(func(): _set_tab(t, false))
		tabs.add_child(b)
		_tab_btns.append(b)

	var body := HBoxContainer.new()
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
	_list.item_selected.connect(_on_list_selected)
	_left_panel.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_title = Label.new()
	UiAssets.apply_label_font(_title, true, UiLayout.font_size(18, self))
	right.add_child(_title)
	_field_scroll = ScrollContainer.new()
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
	var f := UiAssets.body_font()
	if f:
		edit.add_theme_font_override("font", f)
	edit.add_theme_font_size_override("font_size", UiLayout.font_size(design_size, self))


func _set_tab(tab: Tab, force: bool) -> void:
	if not force and _tab == tab:
		for i in range(_tab_btns.size()):
			_tab_btns[i].button_pressed = (i == int(tab))
		return
	_tab = tab
	for i in range(_tab_btns.size()):
		_tab_btns[i].button_pressed = (i == int(tab))
	var visual := tab == Tab.DAMAGE or tab == Tab.HEALTH
	_left_panel.visible = not visual
	## Visualization tables are vertical so a normal mouse wheel traverses all hulls.
	_field_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid.columns = 1 if visual else 2
	_search.text = ""
	if visual:
		_current_id = -1
		_build_visualization(tab)
		return
	_reload_ids()
	_apply_filter("")
	if _filtered.size() > 0:
		_select_id(_filtered[0])
	else:
		_current_id = -1
		_title.text = "（无条目）"
		for c in _grid.get_children():
			c.queue_free()


func _reload_ids() -> void:
	_ids.clear()
	match _tab:
		Tab.SHIPS:
			var keys: Array = DataStore.ships.keys()
			keys.sort()
			for k in keys:
				_ids.append(int(k))
		Tab.MODULES:
			var mk: Array = _working_modules.keys() if not _working_modules.is_empty() else DataStore.modules.keys()
			mk.sort()
			for k in mk:
				_ids.append(int(k))
		_:
			pass


func _apply_filter(query: String) -> void:
	var q := query.strip_edges().to_lower()
	_filtered.clear()
	if _list:
		_list.clear()
	for sid in _ids:
		var label := _list_label(sid)
		var en := _list_en(sid)
		if q != "" and not label.to_lower().contains(q) and not en.to_lower().contains(q):
			continue
		_filtered.append(sid)
		if _list:
			_list.add_item(label)


func _list_label(sid: int) -> String:
	match _tab:
		Tab.SHIPS:
			var d: Dictionary = DataStore.get_ship(sid)
			var label := "%d · %s" % [sid, str(d.get("name", "?"))]
			if bool(d.get("is_unmanned", false)):
				label += "（无人）"
			return label
		_:
			var m: Dictionary = _working_modules.get(sid, DataStore.get_module(sid))
			var zh := str(m.get("nameZH", ""))
			var en := str(m.get("nameEN", m.get("nameSDE", "?")))
			return "%d · %s" % [sid, zh if zh.strip_edges() != "" else en]


func _list_en(sid: int) -> String:
	match _tab:
		Tab.SHIPS:
			return str(DataStore.get_ship(sid).get("name_en", ""))
		_:
			return str(_working_modules.get(sid, DataStore.get_module(sid)).get("nameEN", ""))


func _on_list_selected(idx: int) -> void:
	if idx < 0 or idx >= _filtered.size():
		return
	_select_id(_filtered[idx])


func _select_id(item_id: int) -> void:
	_current_id = item_id
	var d: Dictionary = _ensure_working(item_id)
	match _tab:
		Tab.SHIPS:
			_title.text = "%d · %s（%s）" % [item_id, str(d.get("name", "?")), str(d.get("name_en", ""))]
		_:
			_title.text = "装备 %d · %s" % [item_id, str(d.get("nameEN", d.get("nameSDE", "?")))]
	var sel := _filtered.find(item_id)
	if _list and sel >= 0 and not _list.is_selected(sel):
		_list.select(sel)
	_rebuild_fields(d)


func _ensure_working(item_id: int) -> Dictionary:
	match _tab:
		Tab.SHIPS:
			if not _working_ships.has(item_id):
				_working_ships[item_id] = DataStore.get_ship(item_id).duplicate(true)
			return _working_ships[item_id]
		_:
			if not _working_modules.has(item_id):
				_working_modules[item_id] = DataStore.get_module(item_id).duplicate(true)
			return _working_modules[item_id]


func _build_visualization(kind: Tab) -> void:
	for c in _grid.get_children():
		c.queue_free()
	_chart_entries.clear()
	_chart_kind = kind
	_title.text = (
		"伤害可视化 · 蓝/绿=船体 · 紫=无人机/舰载机 · 无人可调DPS→DPH"
		if kind == Tab.DAMAGE
		else "血量可视化 · 纵向滚轮表 · 盾 / 甲 / 结构"
	)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UiLayout.px(18, self))
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(root)
	_build_chart_section(root, false)
	_build_chart_section(root, true)
	_refresh_chart_values()
	_status.text = (
		"箭头按下立即调整；按住0.5秒后每0.05秒连调 · " + _CANCEL_HINT
	)


func _build_chart_section(root: VBoxContainer, capital: bool) -> void:
	var title := Label.new()
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
	var axis := Label.new()
	axis.text = (
		"Y：单位（小→大） · X：每秒输出（蓝/绿=船体 · 紫=僚机）"
		if _chart_kind == Tab.DAMAGE
		else "Y：舰船 / 无人单位（小→大） · X：总血量（蓝=盾 / 黄=甲 / 红=结构）"
	)
	UiAssets.apply_label_font(axis, false, UiLayout.font_size(12, self))
	root.add_child(axis)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UiLayout.px(1, self))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(list)
	var ids := _chart_ship_ids(capital)
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "（无舰船）"
		UiAssets.apply_label_font(empty, false, UiLayout.font_size(13, self))
		list.add_child(empty)
		return
	for sid in ids:
		_build_chart_row(list, sid, capital)


func _chart_ship_ids(capital: bool) -> Array[int]:
	var ids: Array[int] = []
	for key in DataStore.ships.keys():
		var sid := int(key)
		var ship: Dictionary = _chart_ship(sid)
		if ship.is_empty():
			continue
		var unmanned := bool(ship.get("is_unmanned", false))
		if unmanned:
			## Health lists every unmanned unit as a ship; damage still excludes mining.
			if capital or (_chart_kind == Tab.DAMAGE and _is_mining_unmanned(ship)):
				continue
			ids.append(sid)
			continue
		if not _chart_include_manned(ship):
			continue
		var is_capital := _chart_uses_capital_scale(ship)
		if is_capital == capital:
			ids.append(sid)
	ids.sort_custom(func(a: int, b: int):
		var sa := _chart_ship(a)
		var sb := _chart_ship(b)
		var oa := _group_sort_key(str(sa.get("ship_group", "")), capital)
		var ob := _group_sort_key(str(sb.get("ship_group", "")), capital)
		return a < b if oa == ob else oa < ob
	)
	return ids


## Charts list shop ships plus chart-only PVE / salvage hulls.
func _chart_include_manned(ship: Dictionary) -> bool:
	var tags: Array = ship.get("tags", [])
	if str(ship.get("ship_group", "")) == "freighter" or "sleeper" in tags or "pve_creep" in tags:
		return true
	if not bool(ship.get("shop_eligible", true)):
		return false
	return not ("shop_ineligible" in tags)


## Health: Orca HP is capital-scale; freighters always share the capital axis.
func _chart_uses_capital_scale(ship: Dictionary) -> bool:
	var group := str(ship.get("ship_group", ""))
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
	return int(_GROUP_ORDER.get(group, 99))


func _chart_ship(sid: int) -> Dictionary:
	if not _working_ships.has(sid):
		var source: Dictionary = DataStore.get_ship(sid)
		if not source.is_empty():
			_working_ships[sid] = source.duplicate(true)
	return _working_ships.get(sid, {})


func _build_chart_row(list: VBoxContainer, sid: int, capital: bool) -> void:
	var ship := _chart_ship(sid)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = UiLayout.px(54 if _chart_kind == Tab.DAMAGE else 40, self)
	row.add_theme_constant_override("separation", UiLayout.px(5, self))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(row)
	var tonnage := TextureRect.new()
	tonnage.custom_minimum_size = Vector2(UiLayout.px(28, self), UiLayout.px(28, self))
	tonnage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tonnage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tonnage.texture = UiAssets.tonnage_icon(str(ship.get("ship_group", "")))
	tonnage.tooltip_text = str(ship.get("ship_group", ""))
	row.add_child(tonnage)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = UiLayout.px(_CHART_INFO_W, self)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var top_line := HBoxContainer.new()
	top_line.alignment = BoxContainer.ALIGNMENT_CENTER
	top_line.add_theme_constant_override("separation", UiLayout.px(3, self))
	info.add_child(top_line)
	var name_label := Label.new()
	name_label.text = str(ship.get("name", sid))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = UiLayout.px(96, self)
	UiAssets.apply_label_font(name_label, true, UiLayout.font_size(13, self))
	top_line.add_child(name_label)
	var weapon_label := Label.new()
	weapon_label.text = _ship_weapon_name(ship) if _chart_kind == Tab.DAMAGE else ""
	weapon_label.visible = _chart_kind == Tab.DAMAGE
	weapon_label.modulate = Color(0.76, 0.82, 0.9, 1.0)
	UiAssets.apply_label_font(weapon_label, false, UiLayout.font_size(11, self))
	var slots_label: Label = null
	var hp_labels := {}
	if _chart_kind == Tab.DAMAGE:
		if bool(ship.get("is_unmanned", false)):
			var rate_label := Label.new()
			rate_label.custom_minimum_size.x = UiLayout.px(54, self)
			rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rate_label.modulate = (
				_COLOR_HULL_HPS if _is_logistic_ship(ship) else _COLOR_UNMANNED_DPS
			)
			UiAssets.apply_label_font(rate_label, false, UiLayout.font_size(11, self))
			top_line.add_child(rate_label)
			slots_label = rate_label
			top_line.add_child(_make_arrow_row(
				func(): _adjust_chart_unmanned_rate(sid, -_UNMANNED_RATE_STEP),
				func(): _adjust_chart_unmanned_rate(sid, _UNMANNED_RATE_STEP)
			))
		else:
			slots_label = Label.new()
			slots_label.custom_minimum_size.x = UiLayout.px(54, self)
			slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			UiAssets.apply_label_font(slots_label, false, UiLayout.font_size(11, self))
			top_line.add_child(slots_label)
			top_line.add_child(_make_arrow_row(
				func(): _adjust_chart_slots(sid, -1),
				func(): _adjust_chart_slots(sid, 1)
			))
		info.add_child(weapon_label)
	else:
		for spec in [
			["盾", "shield_hp"],
			["甲", "armor_hp"],
			["构", "structure_hp"],
		]:
			var hp_field := str(spec[1])
			var layer_group := HBoxContainer.new()
			layer_group.add_theme_constant_override("separation", UiLayout.px(1, self))
			var layer_label := Label.new()
			layer_label.text = spec[0]
			layer_label.custom_minimum_size.x = UiLayout.px(48, self)
			layer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			UiAssets.apply_label_font(layer_label, false, UiLayout.font_size(10, self))
			layer_group.add_child(layer_label)
			hp_labels[hp_field] = layer_label
			layer_group.add_child(_make_arrow_row(
				func(): _adjust_chart_hp(sid, hp_field, -10.0),
				func(): _adjust_chart_hp(sid, hp_field, 10.0)
			))
			top_line.add_child(layer_group)
	var bar_space := Control.new()
	bar_space.custom_minimum_size = Vector2(
		UiLayout.px(_CHART_BAR_MIN_W, self), UiLayout.px(_CHART_ROW_H, self)
	)
	bar_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_space.clip_contents = true
	row.add_child(bar_space)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = UiLayout.px(110, self)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiAssets.apply_label_font(value_label, true, UiLayout.font_size(12, self))
	row.add_child(value_label)
	var entry := {
		"sid": sid,
		"capital": capital,
		"value_label": value_label,
		"bar_space": bar_space,
		"slots_label": slots_label,
		"hp_labels": hp_labels,
	}
	bar_space.resized.connect(func(): call_deferred("_refresh_chart_values"))
	if _chart_kind == Tab.DAMAGE:
		var hull_bar := ColorRect.new()
		hull_bar.color = (
			_COLOR_UNMANNED_DPS
			if bool(ship.get("is_unmanned", false)) and not _is_logistic_ship(ship)
			else (_COLOR_HULL_HPS if _is_logistic_ship(ship) else _COLOR_HULL_DPS)
		)
		hull_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_space.add_child(hull_bar)
		var wing_bar := ColorRect.new()
		wing_bar.color = _COLOR_WING
		wing_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_space.add_child(wing_bar)
		entry["bar_hull"] = hull_bar
		entry["bar_wing"] = wing_bar
	else:
		var layers := {}
		for pair in [
			["shield", Color(0.24, 0.65, 1.0, 0.94)],
			["armor", Color(0.95, 0.73, 0.22, 0.94)],
			["structure", Color(0.9, 0.3, 0.25, 0.94)],
		]:
			var layer := ColorRect.new()
			layer.color = pair[1]
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_space.add_child(layer)
			layers[pair[0]] = layer
		entry["layers"] = layers
	_chart_entries.append(entry)


func _make_arrow_row(down_action: Callable, up_action: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiLayout.px(1, self))
	for pair in [["▼", down_action], ["▲", up_action]]:
		var btn := Button.new()
		btn.text = pair[0]
		btn.custom_minimum_size = Vector2(UiLayout.px(27, self), UiLayout.px(24, self))
		UiAssets.apply_button_font(btn, UiLayout.font_size(10, self))
		_wire_repeat_button(btn, pair[1])
		row.add_child(btn)
	return row


func _wire_repeat_button(btn: Button, action: Callable) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_callback = Timer.TIMER_PROCESS_IDLE
	btn.add_child(timer)
	btn.button_down.connect(func():
		action.call()
		timer.wait_time = _REPEAT_DELAY_S
		timer.start()
	)
	btn.button_up.connect(func(): timer.stop())
	timer.timeout.connect(func():
		action.call()
		timer.wait_time = _REPEAT_INTERVAL_S
		timer.start()
	)


func _adjust_chart_slots(sid: int, delta: int) -> void:
	var ship := _chart_ship(sid)
	if ship.is_empty():
		return
	var old_hi := int(ship.get("hi_slots", 0))
	var new_hi := maxi(0, old_hi + delta)
	if new_hi == old_hi:
		return
	ship["hi_slots"] = new_hi
	if ship.has("attack_weapon_slots"):
		var old_attack := int(ship.get("attack_weapon_slots", 0))
		ship["attack_weapon_slots"] = clampi(old_attack + delta, 0, new_hi)
	_dirty_ships[sid] = true
	_refresh_chart_values()


func _adjust_chart_hp(sid: int, field: String, delta_1star: float) -> void:
	var ship := _chart_ship(sid)
	var stars: Array = ship.get("stars", [])
	if stars.is_empty():
		return
	var changed := false
	for i in range(stars.size()):
		var star: Dictionary = stars[i]
		if not star.has(field):
			continue
		var old := float(star.get(field, 0.0))
		var value := maxf(0.0, old + delta_1star * float(i + 1))
		if not is_equal_approx(old, value):
			star[field] = value
			changed = true
	if changed:
		ship["stars"] = stars
		_dirty_ships[sid] = true
		_refresh_chart_values()


## Unmanned chart arrows: adjust target DPS/HPS; write-back scales star-1 DPH / repair.
func _adjust_chart_unmanned_rate(sid: int, delta_rate: float) -> void:
	var ship := _chart_ship(sid)
	if ship.is_empty() or not bool(ship.get("is_unmanned", false)):
		return
	var logistic := _is_logistic_ship(ship)
	var key := "repair" if logistic else "damage"
	var fields: Array = (
		["shield", "armor", "structure"]
		if logistic
		else ["emp", "thermal", "kinetic", "explosive"]
	)
	var cycle := maxf(float(ship.get("attack_cycle_s", 1.0)), 0.001)
	var old_rate := _unmanned_hps(ship) if logistic else _unmanned_dps(ship)
	var new_rate := maxf(0.0, old_rate + delta_rate)
	var target_dph := new_rate * cycle
	var stars: Array = ship.get("stars", [])
	if stars.is_empty():
		return
	var base: Dictionary = (stars[0] as Dictionary).get(key, {})
	var old_total := 0.0
	for field in fields:
		old_total += float(base.get(field, 0.0))
	for i in range(stars.size()):
		var star: Dictionary = stars[i]
		var payload: Dictionary = star.get(key, {}).duplicate(true)
		if old_total > 0.001:
			var star1_scale := target_dph / old_total
			for field in fields:
				payload[field] = maxf(0.0, float(base.get(field, 0.0)) * star1_scale * float(i + 1))
		else:
			for field in fields:
				payload[field] = 0.0
			var primary := "armor" if logistic else "emp"
			payload[primary] = target_dph * float(i + 1)
		star[key] = payload
	ship["stars"] = stars
	_dirty_ships[sid] = true
	_refresh_chart_values()


func _is_logistic_ship(ship: Dictionary) -> bool:
	return bool(ship.get("is_logistic", false)) or str(ship.get("weapon_fx", "")) == "heal"


func _is_mining_unmanned(ship: Dictionary) -> bool:
	var kind := str(ship.get("unmanned_kind", ""))
	return (
		kind == "mining_drone"
		or kind == "mining_excavator"
		or str(ship.get("weapon_fx", "")) == "mining"
		or str(ship.get("ship_group", "")) == "mining_drone"
	)


func _ship_weapon_name(ship: Dictionary) -> String:
	if bool(ship.get("is_unmanned", false)):
		var family: String = str({
			"laser": "激光",
			"rail": "磁轨",
			"cannon": "加农炮",
			"missile": "导弹",
			"heal": "维修器",
			"mining": "露天采矿器",
		}.get(str(ship.get("weapon_fx", "")), "武器"))
		return "内置%s" % family
	var module_id := (
		ShipWeaponDerive.resolve_repair_module_id(ship)
		if _is_logistic_ship(ship)
		else ShipWeaponDerive.resolve_module_id(ship)
	)
	var module: Dictionary = _working_modules.get(module_id, DataStore.get_module(module_id))
	var base := str(module.get("nameZH", "")).strip_edges()
	if base == "":
		base = str(module.get("nameEN", module.get("nameSDE", ""))).strip_edges()
	var wing := _ship_wing_name(ship)
	if wing == "":
		return base if base != "" else "无武器"
	return wing if base == "" else "%s + %s" % [base, wing]


func _ship_hull_hps(ship: Dictionary) -> float:
	if bool(ship.get("is_unmanned", false)):
		return _unmanned_hps(ship)
	var module_id := int(ship.get("source_repair_module_type_id", 0))
	if module_id <= 0:
		module_id = ShipWeaponDerive.resolve_repair_module_id(ship)
	var module: Dictionary = _working_modules.get(module_id, DataStore.get_module(module_id))
	if module.is_empty():
		return 0.0
	var per_slot := float(
		module.get(
			"structureDamageAmount",
			module.get("armorDamageAmount", module.get("shieldBonus", 0.0))
		)
	)
	var cycle_ms := float(module.get("duration", module.get("rateOfFire", 3000.0)))
	var slots := maxi(int(ship.get("hi_slots", 0)), 0)
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
	var payload: Dictionary = (stars[0] as Dictionary).get(key, {})
	var total := 0.0
	for field in fields:
		total += float(payload.get(field, 0.0))
	return total / maxf(float(ship.get("attack_cycle_s", 1.0)), 0.001)


## Same launch policy as CombatResolver._drone_spawn_policy_for_ship / capital aux.
func _drone_spawn_policy(ship: Dictionary) -> Dictionary:
	var mining_drone_id := int(ship.get("mining_drone_id", 0))
	if mining_drone_id > 0:
		var mcount := int(ship.get("drone_bay_slots", ship.get("drone_count_cap", 0)))
		if mcount <= 0:
			mcount = int(ship.get("mining_drone_count", 4))
		return {"count": maxi(mcount, 0), "drone_id": mining_drone_id}
	var fighter_id := int(ship.get("fighter_unit_id", 0))
	if fighter_id > 0 or str(ship.get("capital_role", "")) == "carrier":
		if fighter_id <= 0:
			return {"count": 0, "drone_id": 0}
		var tubes := maxi(int(ship.get("fighter_squadrons", 3)), 1) * maxi(
			int(ship.get("fighter_tubes_per_squadron", 3)), 1
		)
		return {"count": tubes, "drone_id": fighter_id}
	var repair_id := int(ship.get("heavy_repair_drone_id", 0))
	if repair_id > 0 or str(ship.get("capital_role", "")) == "force_auxiliary":
		if repair_id <= 0:
			return {"count": 0, "drone_id": 0}
		return {
			"count": maxi(int(ship.get("heavy_repair_drone_count", 4)), 0),
			"drone_id": repair_id,
		}
	var race := str(ship.get("race", "amarr")).to_lower()
	var group := str(ship.get("ship_group", "")).to_lower()
	var sid := int(ship.get("id", 0))
	if _DRONE_COUNT_EXCEPTIONS.has(sid):
		var cnt := int(_DRONE_COUNT_EXCEPTIONS[sid])
		if group == "battlecruiser":
			return {"count": cnt, "drone_id": int(_RACE_DRONE_MEDIUM.get(race, 1005))}
		if group == "battleship":
			return {"count": cnt, "drone_id": int(_RACE_DRONE_HEAVY.get(race, 1011))}
	if group == "battlecruiser":
		return {"count": 1, "drone_id": int(_RACE_DRONE_MEDIUM.get(race, 1005))}
	if group == "battleship":
		return {"count": 2, "drone_id": int(_RACE_DRONE_HEAVY.get(race, 1011))}
	var slots := int(ship.get("drone_bay_slots", ship.get("drone_count_cap", 0)))
	if slots <= 0:
		var bw := float(ship.get("drone_bandwidth", 0.0))
		if bw > 0.0:
			slots = int(floor(bw / _DRONE_BW_COST))
	if slots <= 0:
		return {"count": 0, "drone_id": 0}
	return {"count": slots, "drone_id": int(_RACE_DRONE_LIGHT.get(race, 1001))}


func _is_combat_wing_unit(drone: Dictionary) -> bool:
	if drone.is_empty() or _is_mining_unmanned(drone):
		return false
	return not _is_logistic_ship(drone)


## Capitals / bay ships whose combat/logistics output comes from launched units.
func _ship_wing_name(ship: Dictionary) -> String:
	var wing := _drone_spawn_policy(ship)
	var unit_id := int(wing.get("drone_id", 0))
	var count := int(wing.get("count", 0))
	if unit_id <= 0 or count <= 0:
		return ""
	var drone := _chart_ship(unit_id)
	## Damage chart only labels combat / repair wings — excavators are mining, not DPS/HPS.
	if _is_mining_unmanned(drone):
		return ""
	return "%s ×%d" % [str(drone.get("name", "僚机")), count]


func _ship_wing_hps(ship: Dictionary) -> float:
	if bool(ship.get("is_unmanned", false)):
		return 0.0
	var wing := _drone_spawn_policy(ship)
	var drone_id := int(wing.get("drone_id", 0))
	var count := int(wing.get("count", 0))
	if drone_id <= 0 or count <= 0:
		return 0.0
	var drone := _chart_ship(drone_id)
	if not _is_logistic_ship(drone):
		return 0.0
	return _unmanned_hps(drone) * float(count)


func _ship_wing_dps(ship: Dictionary) -> float:
	if bool(ship.get("is_unmanned", false)):
		return 0.0
	var wing := _drone_spawn_policy(ship)
	var drone_id := int(wing.get("drone_id", 0))
	var count := int(wing.get("count", 0))
	if drone_id <= 0 or count <= 0:
		return 0.0
	var drone := _chart_ship(drone_id)
	if not _is_combat_wing_unit(drone):
		return 0.0
	return _unmanned_dps(drone) * float(count)


func _ship_hull_dps(ship: Dictionary) -> float:
	if bool(ship.get("is_unmanned", false)):
		return _unmanned_dps(ship)
	if str(ship.get("capital_role", "")) == "carrier":
		return 0.0
	var slots := int(ship.get("attack_weapon_slots", 0))
	if slots <= 0:
		slots = int(ship.get("hi_slots", 0))
	var module_id := int(ship.get("source_module_type_id", 0))
	if module_id <= 0:
		module_id = ShipWeaponDerive.resolve_module_id(ship)
	var module: Dictionary = _working_modules.get(module_id, DataStore.get_module(module_id))
	if not module.is_empty():
		var dph := 0.0
		for field in ["emDamage", "thermalDamage", "kineticDamage", "explosiveDamage"]:
			dph += float(module.get(field, 0.0))
		var cycle := float(module.get("rateOfFire", 1000.0)) / 1000.0
		return dph * float(maxi(slots, 0)) / maxf(cycle, 0.001)
	return 0.0


func _ship_output_parts(ship: Dictionary) -> Dictionary:
	if _is_logistic_ship(ship):
		return {"hull": _ship_hull_hps(ship), "wing": _ship_wing_hps(ship)}
	return {"hull": _ship_hull_dps(ship), "wing": _ship_wing_dps(ship)}


func _ship_output_per_s(ship: Dictionary) -> float:
	var parts := _ship_output_parts(ship)
	return float(parts["hull"]) + float(parts["wing"])


func _ship_dps(ship: Dictionary) -> float:
	return _ship_hull_dps(ship) + _ship_wing_dps(ship)


func _ship_hp(ship: Dictionary) -> Dictionary:
	var stars: Array = ship.get("stars", [])
	if stars.is_empty():
		return {"shield": 0.0, "armor": 0.0, "structure": 0.0, "total": 0.0}
	var star: Dictionary = stars[0]
	var shield := float(star.get("shield_hp", 0.0))
	var armor := float(star.get("armor_hp", 0.0))
	var structure := float(star.get("structure_hp", 0.0))
	return {
		"shield": shield,
		"armor": armor,
		"structure": structure,
		"total": shield + armor + structure,
	}


func _refresh_chart_values() -> void:
	if _chart_entries.is_empty():
		return
	var maxima := {false: 1.0, true: 1.0}
	for entry in _chart_entries:
		var ship := _chart_ship(int(entry["sid"]))
		var value := (
			_ship_output_per_s(ship)
			if _chart_kind == Tab.DAMAGE
			else float(_ship_hp(ship)["total"])
		)
		entry["value"] = value
		var capital := bool(entry["capital"])
		maxima[capital] = maxf(float(maxima[capital]), value)
	for entry in _chart_entries:
		var ship := _chart_ship(int(entry["sid"]))
		var capital := bool(entry["capital"])
		var maximum := maxf(float(maxima[capital]), 1.0)
		var value := float(entry["value"])
		var bar_space: Control = entry["bar_space"]
		var chart_w := maxf(
			bar_space.size.x,
			UiLayout.px(_CHART_BAR_MIN_W, self)
		)
		var bar_h := UiLayout.px(_CHART_ROW_H - 10.0, self)
		if _chart_kind == Tab.DAMAGE:
			var parts := _ship_output_parts(ship)
			var hull := float(parts["hull"])
			var wing := float(parts["wing"])
			var unit := "HPS" if _is_logistic_ship(ship) else "DPS"
			if wing > 0.05:
				(entry["value_label"] as Label).text = "%.1f %s (%.0f+%.0f)" % [
					value, unit, hull, wing
				]
			else:
				(entry["value_label"] as Label).text = "%.1f %s" % [value, unit]
			var y := UiLayout.px(5, self)
			var hull_w := chart_w * clampf(hull / maximum, 0.0, 1.0)
			var wing_w := chart_w * clampf(wing / maximum, 0.0, 1.0)
			var hull_bar: ColorRect = entry["bar_hull"]
			var wing_bar: ColorRect = entry["bar_wing"]
			hull_bar.position = Vector2(0.0, y)
			hull_bar.size = Vector2(hull_w, bar_h)
			wing_bar.position = Vector2(hull_w, y)
			wing_bar.size = Vector2(wing_w, bar_h)
			wing_bar.visible = wing > 0.0
			var slots_label: Label = entry.get("slots_label") as Label
			if slots_label:
				if bool(ship.get("is_unmanned", false)):
					slots_label.text = "%.0f %s" % [value, unit]
				else:
					slots_label.text = "高槽 %d" % int(ship.get("hi_slots", 0))
		else:
			(entry["value_label"] as Label).text = "%.0f" % value
			var hp := _ship_hp(ship)
			var hp_labels: Dictionary = entry["hp_labels"]
			(hp_labels["shield_hp"] as Label).text = "盾 %.0f" % float(hp["shield"])
			(hp_labels["armor_hp"] as Label).text = "甲 %.0f" % float(hp["armor"])
			(hp_labels["structure_hp"] as Label).text = "构 %.0f" % float(hp["structure"])
			var x := 0.0
			for key in ["shield", "armor", "structure"]:
				var layer_w := chart_w * float(hp[key]) / maximum
				var layer: ColorRect = (entry["layers"] as Dictionary)[key]
				layer.position = Vector2(x, UiLayout.px(5, self))
				layer.size = Vector2(layer_w, bar_h)
				x += layer_w


func _rebuild_fields(data: Dictionary) -> void:
	for c in _grid.get_children():
		c.queue_free()
	var rows: Array = []
	_flatten(data, [], rows)
	var owner_id := _current_id
	var owner_tab := _tab
	for row in rows:
		var path: Array = row["path"]
		var label := Label.new()
		label.text = _path_text(path)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiAssets.apply_label_font(label, false, UiLayout.font_size(14, self))
		_grid.add_child(label)
		var locked := _is_path_locked(owner_tab, path)
		var edit := LineEdit.new()
		edit.text = _value_text(row["value"])
		edit.custom_minimum_size = Vector2(UiLayout.px(180, self), 0)
		_apply_edit_font(edit, 14)
		edit.editable = not locked
		if locked:
			edit.modulate = Color(0.72, 0.76, 0.82, 1.0)
			edit.tooltip_text = "只读：种族 / 模型 / 立绘 / 装备图标相关字段不可改"
		else:
			edit.text_submitted.connect(func(t: String): _commit(owner_tab, owner_id, path, t))
			edit.focus_exited.connect(func(): _commit(owner_tab, owner_id, path, edit.text))
		_grid.add_child(edit)


func _is_path_locked(tab: Tab, path: Array) -> bool:
	if path.is_empty():
		return false
	var root := str(path[0])
	match tab:
		Tab.SHIPS:
			return _LOCKED_SHIP_ROOTS.has(root)
		_:
			return _LOCKED_MODULE_ROOTS.has(root)


func _flatten(value: Variant, path: Array, out: Array) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for k in (value as Dictionary).keys():
				_flatten((value as Dictionary)[k], path + [k], out)
		TYPE_ARRAY:
			var arr: Array = value
			for i in range(arr.size()):
				_flatten(arr[i], path + [i], out)
		_:
			if not path.is_empty():
				out.append({"path": path, "value": value})


func _path_text(path: Array) -> String:
	var s := ""
	for p in path:
		if typeof(p) == TYPE_INT:
			s += "[%d]" % int(p)
		else:
			s += ("." if s != "" else "") + str(p)
	return s


func _value_text(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return String.num(float(v), 4).rstrip("0").rstrip(".")
	if typeof(v) == TYPE_BOOL:
		return "true" if bool(v) else "false"
	return str(v)


func _commit(tab: Tab, item_id: int, path: Array, text: String) -> void:
	if item_id < 0 or path.is_empty():
		return
	if _is_path_locked(tab, path):
		return
	var container: Variant = null
	match tab:
		Tab.SHIPS:
			if not _working_ships.has(item_id):
				return
			container = _working_ships[item_id]
		_:
			if not _working_modules.has(item_id):
				return
			container = _working_modules[item_id]
	for i in range(path.size() - 1):
		container = container[path[i]]
	var key: Variant = path[path.size() - 1]
	var old_value: Variant = container[key]
	var new_value: Variant = _parse_like(old_value, text)
	if _same_value(old_value, new_value):
		return
	container[key] = new_value
	match tab:
		Tab.SHIPS:
			_dirty_ships[item_id] = true
		_:
			_dirty_modules = true
	if tab == _tab and item_id == _current_id:
		_status.text = "%s → %s（未保存）· %s" % [_path_text(path), _value_text(new_value), _CANCEL_HINT]


func _parse_like(old_value: Variant, text: String) -> Variant:
	var t := text.strip_edges()
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
		return is_equal_approx(float(a), float(b))
	return a == b


func _save_all() -> Array:
	var changed: Array = []
	_last_equipment_saved = false
	for sid in _dirty_ships.keys():
		var data: Dictionary = _working_ships.get(sid, {})
		if data.is_empty():
			continue
		if DataStore.save_ship_json(int(sid), data):
			changed.append(int(sid))
	_dirty_ships.clear()
	var equip_dirty := false
	if _dirty_modules:
		if DataStore.save_equipment_table(_working_modules):
			equip_dirty = true
		_dirty_modules = false
	_last_equipment_saved = equip_dirty
	if not changed.is_empty() or equip_dirty:
		DataStore.reload_all()
		_working_ships.clear()
		_working_modules = DataStore.modules.duplicate(true)
		_reload_ids()
	return changed


func _downloads_dir() -> String:
	return OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)


func _export_ships_csv() -> String:
	var downloads := _downloads_dir()
	if downloads == "":
		return ""
	var abs_path := downloads.path_join(EXPORT_SHIPS_FILE)
	var ids: Array = DataStore.ships.keys()
	ids.sort()
	var col_set: Dictionary = {}
	var rows_by_id: Dictionary = {}
	for k in ids:
		var sid := int(k)
		var data: Dictionary = DataStore.get_ship(sid)
		if data.is_empty():
			continue
		var leaves: Array = []
		_flatten(data, [], leaves)
		var flat: Dictionary = {}
		for leaf in leaves:
			var col := _path_text(leaf["path"])
			flat[col] = _value_text(leaf["value"])
			col_set[col] = true
		rows_by_id[sid] = flat
	return _write_csv(abs_path, ["id"], col_set, rows_by_id, ids)


func _export_equipment_csv() -> String:
	var downloads := _downloads_dir()
	if downloads == "":
		return ""
	var abs_path := downloads.path_join(EXPORT_EQUIP_FILE)
	var col_set: Dictionary = {}
	var rows_by_key: Dictionary = {}
	var keys: Array = []
	var tids: Array = DataStore.modules.keys()
	tids.sort()
	for tid_v in tids:
		var tid := int(tid_v)
		var data: Dictionary = DataStore.modules[tid_v]
		var leaves: Array = []
		_flatten(data, [], leaves)
		var flat: Dictionary = {}
		for leaf in leaves:
			var col := _path_text(leaf["path"])
			flat[col] = _value_text(leaf["value"])
			col_set[col] = true
		var row_key := str(tid)
		rows_by_key[row_key] = flat
		keys.append(row_key)
	return _write_csv(abs_path, ["row_key"], col_set, rows_by_key, keys)


func _write_csv(abs_path: String, id_cols: Array, col_set: Dictionary, rows_by_id: Dictionary, ids: Array) -> String:
	var cols: Array = col_set.keys()
	cols.sort()
	var lines := PackedStringArray()
	var header := PackedStringArray()
	for c in id_cols:
		header.append(str(c))
	for c in cols:
		if str(c) in id_cols:
			continue
		header.append(str(c))
	lines.append(_csv_join(header))
	for sid in ids:
		if not rows_by_id.has(sid):
			continue
		var flat: Dictionary = rows_by_id[sid]
		var cells := PackedStringArray()
		if id_cols.size() == 1 and str(id_cols[0]) == "id":
			cells.append(str(int(sid)))
		elif id_cols.size() == 1 and str(id_cols[0]) == "row_key":
			cells.append(str(sid))
		for c in cols:
			if str(c) in id_cols:
				continue
			cells.append(str(flat.get(str(c), "")))
		lines.append(_csv_join(cells))
	var body := "\n".join(lines) + "\n"
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_warning("[ShipDataEditor] cannot write %s" % abs_path)
		return ""
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	f.store_string(body)
	f.close()
	return abs_path


func _csv_join(cells: PackedStringArray) -> String:
	var out := PackedStringArray()
	for cell in cells:
		out.append(_csv_escape(cell))
	return ",".join(out)


func _csv_escape(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		close_and_save()
		get_viewport().set_input_as_handled()
