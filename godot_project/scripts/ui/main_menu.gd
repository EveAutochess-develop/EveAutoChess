extends Control
## StartScene — left menu column; sizes relative to viewport (UiLayout).

# preload: class_name may be missing from shell global cache after load_resource_pack
const _BgMusic: Script = preload("res://scripts/audio/bg_music.gd")

const BILIBILI_URL: String = "https://space.bilibili.com/1581878"
const TITLE_TEXT: String = "星视寰宇EVE自走棋"
const DECLARE_TEXT: String = "EVE以及其相关之图标/设计均属CCP所有.\n所有数据均来自 网易 EVE Online ."
const CREDITS_TEXT: String = """制作人员名单:

制作人
小鱼

联合制作人
Nafix

项目管理
夜殇

策划组
主策划
古兔

关卡设计
SFW

本移植为爱好者重制（Godot），玩法对齐原版 DUST 243。"""

var _options: Control
var _about: Control
var _load_panel: Control
var _load_list: VBoxContainer
var _rename_panel: Control
var _rename_edit: LineEdit
var _rename_slot_id: String = ""
var _fps_slider: HSlider
var _fps_lbl: Label
var _bgm_check: CheckBox
var _bgm_slider: HSlider
var _bgm_lbl: Label
var _dev_panel: Control
var _dev_master_check: CheckBox
var _dev_soften_check: CheckBox
var _dev_economy_check: CheckBox
var _dev_enemy_layout_check: CheckBox
var _dev_ship_data_btn: Button
var _ship_data_editor: ShipDataEditor
var _options_export_status: Label
var _announce: TextureRect
var _announce_texs: Array[Texture2D] = []
var _announce_i: int = 0
var _col: Control
var _title: Label
var _btn_box: VBoxContainer
var _footer: VBoxContainer
var _nullsec_lobby: NullsecLobbyPopup
var _nullsec_room: NullsecRoomUI
var _nullsec_net: NullsecNetSession
## Silent match gate: ignore spam clicks while a scan/try-join is in flight (no UI hint).
var _nullsec_match_busy: bool = false
## Continue-last: invalidate in-flight remote rejoin when user cancels / picks local.
var _continue_rejoin_gen: int = 0
var _continue_search_dlg: ConfirmationDialog = null

func _bgm() -> BgMusic:
	var n: Variant = _BgMusic.call("instance")
	if n is BgMusic:
		var bgm: BgMusic = n
		return bgm
	return null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Leftover load bar from a failed nullsec enter must not eat menu clicks.
	MatchLoadOverlay.hide_overlay()
	_bgm()
	MatchSave.list_slots()  ## seed 旗舰测试 from last_match if needed
	_build()
	_apply_adaptive_layout()
	resized.connect(_apply_adaptive_layout)
	Engine.max_fps = int(GameSession.target_fps)
	_start_announce_cycle()
	SessionDiagnostics.log(
		"boot.ready",
		"shell=%s content=%s nomodel=%d fps_cap=%d breathe=%d soften=%d" % [
			GameSession.shell_version,
			DataStore.content_version,
			1 if GameSession.no_model_perf_mode else 0,
			int(GameSession.target_fps),
			1 if GameSession.camera_breathe_enabled else 0,
			1 if GameSession.player_citadel_soften else 0,
		]
	)

func _build() -> void:
	var base: ColorRect = ColorRect.new()
	base.name = "BaseFill"
	UiAssets.full_rect(base)
	base.color = Color(0.04, 0.05, 0.08, 1)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	var bg: TextureRect = TextureRect.new()
	bg.name = "BG"
	UiAssets.full_rect(bg)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_tex: Texture2D = UiAssets.tex(UiAssets.MAIN_BG)
	if bg_tex:
		bg.texture = bg_tex
	add_child(bg)

	_col = Control.new()
	_col.name = "Left"
	add_child(_col)

	_title = Label.new()
	_title.name = "Title"
	_title.text = TITLE_TEXT
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_col.add_child(_title)

	_btn_box = VBoxContainer.new()
	_btn_box.name = "Buttons"
	_col.add_child(_btn_box)

	_btn_box.add_child(_menu_btn("开始无尽模式", _on_endless))
	_btn_box.add_child(_menu_btn("开始对战模式", _on_versus))
	_btn_box.add_child(_menu_btn("多人联机对战", _on_nullsec_open))
	var cont: Button = _menu_btn("继续上次对局", _on_continue)
	cont.disabled = not MatchSave.exists() and not NullsecRejoinTicket.exists()
	_btn_box.add_child(cont)
	var load_btn: Button = _menu_btn("读取存档", _on_load_open)
	load_btn.disabled = MatchSave.list_slots().is_empty() and not MatchSave.exists()
	_btn_box.add_child(load_btn)
	_btn_box.add_child(_menu_btn("选项", _on_options_open))
	_btn_box.add_child(_menu_btn("退出游戏", _on_quit))
	_btn_box.add_child(_menu_btn("关于我们", _on_about_open))

	_footer = VBoxContainer.new()
	_footer.name = "Right"
	_col.add_child(_footer)

	var declare: Label = Label.new()
	declare.name = "Declare"
	declare.text = DECLARE_TEXT
	declare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	declare.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 0.95))
	declare.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_footer.add_child(declare)

	var ver: Label = Label.new()
	ver.name = "VersionLabel"
	ver.text = "游戏版本:%s | 内容 %s" % [GameSession.shell_version, DataStore.content_version]
	ver.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_footer.add_child(ver)

	_announce = TextureRect.new()
	_announce.name = "Announcements"
	_announce.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_announce.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announce.z_index = 8
	_announce_texs = UiAssets.announcement_textures()
	if _announce_texs.size() > 0:
		_announce.texture = _announce_texs[0]
		_announce.visible = true
	else:
		_announce.visible = false
		push_warning("MainMenu: no announcement textures (check Pack UI / ANNOUNCE_FILES)")
	add_child(_announce)

	_options = _build_options()
	add_child(_options)
	_about = _build_about()
	add_child(_about)
	_load_panel = _build_load_panel()
	add_child(_load_panel)
	_rename_panel = _build_rename_panel()
	add_child(_rename_panel)
	_nullsec_lobby = NullsecLobbyPopup.new()
	_nullsec_lobby.visible = false
	add_child(_nullsec_lobby)
	_nullsec_lobby.request_match_public.connect(_on_nullsec_match_public)
	_nullsec_lobby.request_host_room.connect(_on_nullsec_host_room)
	_nullsec_lobby.request_history.connect(_on_nullsec_history)
	_nullsec_lobby.request_join_share.connect(_on_nullsec_join_share)

func _apply_adaptive_layout() -> void:
	var pad: float = 0.035 if UiLayout.is_mobile() else 0.038
	var col_w: float = 0.38 if UiLayout.is_mobile() else 0.42
	UiLayout.set_rect_frac(_col, 0.0, 0.0, col_w, 1.0)

	# Title band ~ top 4%–11%
	UiLayout.set_rect_frac(_title, pad / col_w, 0.04, 0.95, 0.11)
	UiAssets.apply_label_font(_title, true, UiLayout.font_size(36, self))
	_title.add_theme_constant_override("outline_size", UiLayout.margin_px(6, self))

	# Buttons: middle of left column
	var btn_left: float = pad / col_w
	var btn_w: float = 0.55 if UiLayout.is_mobile() else 0.48
	UiLayout.set_rect_frac(_btn_box, btn_left, 0.22, btn_left + btn_w, 0.78)
	_btn_box.add_theme_constant_override("separation", UiLayout.margin_px(18 if UiLayout.is_mobile() else 28, self))
	var bh: float = UiLayout.px(48 if UiLayout.is_mobile() else 56, self)
	var bw: float = UiLayout.px(160 if UiLayout.is_mobile() else 200, self)
	var bfs: int = UiLayout.font_size(18 if UiLayout.is_mobile() else 22, self)
	for c: Node in _btn_box.get_children():
		if c is Button:
			(c as Button).custom_minimum_size = Vector2(bw, bh)
			UiAssets.apply_button_font(c as Button, bfs)

	# Footer bottom of column
	UiLayout.set_rect_frac(_footer, pad / col_w, 0.82, 0.96, 0.98)
	_footer.add_theme_constant_override("separation", UiLayout.margin_px(4, self))
	var declare: Label = _footer.get_node_or_null("Declare") as Label
	if declare:
		UiAssets.apply_label_font(declare, false, UiLayout.font_size(12, self))
		declare.add_theme_constant_override("outline_size", UiLayout.margin_px(2, self))
	var ver: Label = _footer.get_node_or_null("VersionLabel") as Label
	if ver:
		UiAssets.apply_label_font(ver, false, UiLayout.font_size(13, self))
		ver.add_theme_constant_override("outline_size", UiLayout.margin_px(2, self))

	# Announcements: bottom-right ~28%×18%
	if UiLayout.is_mobile():
		UiLayout.set_rect_frac(_announce, 0.62, 0.72, 0.985, 0.96)
	else:
		UiLayout.set_rect_frac(_announce, 0.68, 0.68, 0.98, 0.92)

	if _options and _options.visible == false:
		pass
	if _options:
		UiLayout.set_center_panel_frac(_options, 0.78 if UiLayout.is_mobile() else 0.72, 0.68 if UiLayout.is_mobile() else 0.64)
	if _about:
		UiLayout.set_center_panel_frac(_about, 0.7 if UiLayout.is_mobile() else 0.42, 0.82 if UiLayout.is_mobile() else 0.78)
	if _load_panel:
		UiLayout.set_center_panel_frac(_load_panel, 0.86 if UiLayout.is_mobile() else 0.58, 0.72 if UiLayout.is_mobile() else 0.66)
	if _rename_panel:
		UiLayout.set_center_panel_frac(_rename_panel, 0.72 if UiLayout.is_mobile() else 0.42, 0.36)
	if _dev_panel:
		UiLayout.set_center_panel_frac(_dev_panel, 0.78 if UiLayout.is_mobile() else 0.52, 0.52 if UiLayout.is_mobile() else 0.46)

func _menu_btn(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.75, 0.4, 1))
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.18, 0.82)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(8)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.26, 0.34, 0.92)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(cb)
	return b

func _build_options() -> Control:
	var panel: PanelContainer = _modal_panel("OptionsPanel")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer

	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "选项菜单"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(24, self))
	cap_row.add_child(cap)
	var close_x: Button = Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func() -> void: panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var fps_cap: Label = Label.new()
	fps_cap.text = "FPS限制"
	UiAssets.apply_label_font(fps_cap, false, UiLayout.font_size(16, self))
	row.add_child(fps_cap)
	_fps_slider = HSlider.new()
	_fps_slider.min_value = 30
	_fps_slider.max_value = 240
	_fps_slider.step = 1
	_fps_slider.value = GameSession.target_fps
	_fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_slider.value_changed.connect(_on_fps_changed)
	row.add_child(_fps_slider)
	_fps_lbl = Label.new()
	_fps_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_fps_lbl.text = str(int(GameSession.target_fps))
	UiAssets.apply_label_font(_fps_lbl, false, UiLayout.font_size(16, self))
	row.add_child(_fps_lbl)
	box.add_child(row)

	var bgm: BgMusic = _bgm()
	var bgm_on_row: HBoxContainer = HBoxContainer.new()
	bgm_on_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	_bgm_check = CheckBox.new()
	_bgm_check.text = "背景音乐"
	_bgm_check.button_pressed = bgm.enabled if bgm else false
	UiAssets.apply_button_font(_bgm_check, UiLayout.font_size(16, self))
	_bgm_check.toggled.connect(_on_bgm_toggled)
	bgm_on_row.add_child(_bgm_check)
	box.add_child(bgm_on_row)

	var nomodel_row: HBoxContainer = HBoxContainer.new()
	nomodel_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var nomodel: CheckBox = CheckBox.new()
	nomodel.text = "无模型性能模式（亦关血条特效）"
	nomodel.button_pressed = GameSession.no_model_perf_mode
	UiAssets.apply_button_font(nomodel, UiLayout.font_size(16, self))
	nomodel.toggled.connect(_on_no_model_toggled)
	nomodel_row.add_child(nomodel)
	box.add_child(nomodel_row)

	var breathe_row: HBoxContainer = HBoxContainer.new()
	breathe_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var breathe: CheckBox = CheckBox.new()
	breathe.text = "镜头呼吸浮动"
	breathe.button_pressed = GameSession.camera_breathe_enabled
	UiAssets.apply_button_font(breathe, UiLayout.font_size(16, self))
	breathe.toggled.connect(_on_camera_breathe_toggled)
	breathe_row.add_child(breathe)
	box.add_child(breathe_row)

	var hp_row: HBoxContainer = HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var hp_cap: Label = Label.new()
	hp_cap.text = "血量展示"
	UiAssets.apply_label_font(hp_cap, false, UiLayout.font_size(16, self))
	hp_row.add_child(hp_cap)
	var hp_opt: OptionButton = OptionButton.new()
	hp_opt.add_item("环形血量展示", 0)
	hp_opt.add_item("四条血量展示", 1)
	var bars_on: bool = str(GameSession.get("health_bar_style")) == "bars"
	hp_opt.select(1 if bars_on else 0)
	UiAssets.apply_button_font(hp_opt, UiLayout.font_size(16, self))
	hp_opt.item_selected.connect(_on_health_bar_style_selected)
	hp_row.add_child(hp_opt)
	box.add_child(hp_row)

	var bgm_vol_row: HBoxContainer = HBoxContainer.new()
	bgm_vol_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var bgm_cap: Label = Label.new()
	bgm_cap.text = "背景音乐音量"
	UiAssets.apply_label_font(bgm_cap, false, UiLayout.font_size(16, self))
	bgm_vol_row.add_child(bgm_cap)
	_bgm_slider = HSlider.new()
	_bgm_slider.min_value = 0
	_bgm_slider.max_value = 100
	_bgm_slider.step = 1
	_bgm_slider.value = bgm.volume_pct if bgm else 60.0
	_bgm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bgm_slider.value_changed.connect(_on_bgm_volume_changed)
	bgm_vol_row.add_child(_bgm_slider)
	_bgm_lbl = Label.new()
	_bgm_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_bgm_lbl.text = str(int(_bgm_slider.value))
	UiAssets.apply_label_font(_bgm_lbl, false, UiLayout.font_size(16, self))
	bgm_vol_row.add_child(_bgm_lbl)
	box.add_child(bgm_vol_row)

	var export_btn: Button = Button.new()
	export_btn.text = "导出 debug 日志"
	export_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(export_btn, UiLayout.font_size(16, self))
	export_btn.pressed.connect(_on_export_debug_log)
	box.add_child(export_btn)

	var verify_btn: Button = Button.new()
	verify_btn.text = "核实版本是否最新"
	verify_btn.tooltip_text = "主动检查远端是否有新内容；默认启动不会自动联网验版"
	verify_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(verify_btn, UiLayout.font_size(16, self))
	verify_btn.pressed.connect(_on_verify_content_version)
	box.add_child(verify_btn)

	_options_export_status = Label.new()
	_options_export_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(_options_export_status, false, UiLayout.font_size(12, self))
	box.add_child(_options_export_status)

	var dev_btn: Button = Button.new()
	dev_btn.text = "开发者调试"
	dev_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(dev_btn, UiLayout.font_size(16, self))
	dev_btn.pressed.connect(_on_dev_debug_open)
	box.add_child(dev_btn)

	_dev_panel = _build_developer_debug_panel()
	add_child(_dev_panel)
	return panel


func _build_developer_debug_panel() -> Control:
	var panel: PanelContainer = _modal_panel("DeveloperDebugPanel")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "开发者调试"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back: Button = Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func() -> void:
		panel.visible = false
		if _options:
			_options.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)

	var hint: Label = Label.new()
	hint.text = "默认关闭。开关状态写入本地设置文件，与对局存档无关。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(hint, false, UiLayout.font_size(13, self))
	box.add_child(hint)

	_dev_master_check = CheckBox.new()
	_dev_master_check.text = "启用开发者调试"
	_dev_master_check.button_pressed = GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_master_check, UiLayout.font_size(16, self))
	_dev_master_check.toggled.connect(_on_dev_master_toggled)
	box.add_child(_dev_master_check)

	_dev_soften_check = CheckBox.new()
	_dev_soften_check.text = "我方扣血软化（失败惩罚减为 1）"
	_dev_soften_check.button_pressed = GameSession.player_citadel_soften
	_dev_soften_check.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_soften_check, UiLayout.font_size(16, self))
	_dev_soften_check.toggled.connect(_on_dev_soften_toggled)
	box.add_child(_dev_soften_check)

	_dev_economy_check = CheckBox.new()
	_dev_economy_check.text = "人机双倍经济（我方战斗收入×同人机）"
	_dev_economy_check.button_pressed = GameSession.player_ai_double_economy
	_dev_economy_check.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_economy_check, UiLayout.font_size(16, self))
	_dev_economy_check.toggled.connect(_on_dev_economy_toggled)
	box.add_child(_dev_economy_check)

	_dev_enemy_layout_check = CheckBox.new()
	_dev_enemy_layout_check.text = "敌方布局调整许可（暂停时可拖敌方单位）"
	_dev_enemy_layout_check.button_pressed = GameSession.enemy_layout_adjust
	_dev_enemy_layout_check.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_enemy_layout_check, UiLayout.font_size(16, self))
	_dev_enemy_layout_check.toggled.connect(_on_dev_enemy_layout_toggled)
	box.add_child(_dev_enemy_layout_check)

	_dev_ship_data_btn = Button.new()
	_dev_ship_data_btn.text = "全舰船装备数据调整"
	_dev_ship_data_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	_dev_ship_data_btn.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_ship_data_btn, UiLayout.font_size(16, self))
	_dev_ship_data_btn.pressed.connect(_on_dev_ship_data_open)
	box.add_child(_dev_ship_data_btn)

	var swap_hint: Label = Label.new()
	swap_hint.text = "换边按钮在局内「开发者调试」中（备战阶段）"
	swap_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(swap_hint, false, 14)
	box.add_child(swap_hint)
	return panel

func _build_about() -> Control:
	var panel: PanelContainer = _modal_panel("AboutUsPanel")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer

	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "关于我们"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(24, self))
	cap_row.add_child(cap)
	var close_x: Button = Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func() -> void: panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)

	var bili: Button = Button.new()
	bili.text = "我们的B站主页(点击进入)\n%s" % BILIBILI_URL
	bili.custom_minimum_size = Vector2(0, UiLayout.px(52, self))
	UiAssets.apply_button_font(bili, UiLayout.font_size(14, self))
	bili.pressed.connect(func() -> void: OS.shell_open(BILIBILI_URL))
	box.add_child(bili)

	var qq: Label = Label.new()
	qq.text = "欢迎加入我们的QQ群关注最新进展"
	UiAssets.apply_label_font(qq, false, UiLayout.font_size(14, self))
	box.add_child(qq)

	var qr: TextureRect = TextureRect.new()
	qr.custom_minimum_size = Vector2(UiLayout.px(140, self), UiLayout.px(140, self))
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var qr_tex: Texture2D = UiAssets.qq_qr_texture()
	if qr_tex:
		qr.texture = qr_tex
	box.add_child(qr)

	var credits: Label = Label.new()
	credits.text = CREDITS_TEXT
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(credits, false, UiLayout.font_size(12, self))
	box.add_child(credits)
	return panel

func _modal_panel(p_name: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = p_name
	panel.visible = false
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	sb.border_color = Color(0.75, 0.65, 0.35, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	var m: int = UiLayout.margin_px(16, self)
	margin.add_theme_constant_override("margin_left", m)
	margin.add_theme_constant_override("margin_right", m)
	margin.add_theme_constant_override("margin_top", m)
	margin.add_theme_constant_override("margin_bottom", m)
	panel.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "VBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	margin.add_child(box)
	return panel

func _start_announce_cycle() -> void:
	if _announce_texs.size() <= 1:
		return
	var t: Timer = Timer.new()
	t.wait_time = 10.0
	t.autostart = true
	t.timeout.connect(func() -> void:
		_announce_i = (_announce_i + 1) % _announce_texs.size()
		if _announce:
			_announce.texture = _announce_texs[_announce_i]
	)
	add_child(t)

func _on_fps_changed(v: float) -> void:
	if GameSession.has_method("set_target_fps"):
		GameSession.set_target_fps(int(v))
	else:
		GameSession.target_fps = int(v)
		Engine.max_fps = GameSession.target_fps
		GameSession.save_settings()
	if _fps_lbl:
		_fps_lbl.text = str(GameSession.target_fps)

func _on_no_model_toggled(on: bool) -> void:
	GameSession.set_no_model_perf_mode(on)

func _on_camera_breathe_toggled(on: bool) -> void:
	GameSession.set_camera_breathe_enabled(on)

func _on_health_bar_style_selected(idx: int) -> void:
	var style: String = "bars" if idx == 1 else "ring"
	if GameSession.has_method("set_health_bar_style"):
		GameSession.set_health_bar_style(style)
	else:
		GameSession.set("health_bar_style", style)
		if GameSession.has_method("save_settings"):
			GameSession.save_settings()
	get_tree().call_group("match_root", "rebuild_all_ship_health_bars")

func _on_nullsec_open() -> void:
	_nullsec_lobby.popup_centered(Vector2(720, 420))

func _ensure_nullsec_net() -> NullsecNetSession:
	if GameSession:
		var existing: NullsecNetSession = GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession
		if existing:
			_nullsec_net = existing
			return _nullsec_net
	if _nullsec_net == null or not is_instance_valid(_nullsec_net):
		_nullsec_net = NullsecNetSession.new()
		_nullsec_net.name = "NullsecNetSession"
		add_child(_nullsec_net)
		_nullsec_net.rejected.connect(func(r: String) -> void:
			SessionDiagnostics.log("net.reject", str(r))
			if _nullsec_lobby:
				_nullsec_lobby.set_status(r)
		)
		_nullsec_net.ships_mismatch.connect(func(_h: String) -> void:
			if _nullsec_lobby:
				_nullsec_lobby.set_status("全舰船数据与房主不一致 · 进入对局后将临时应用房主舰船数据")
		)
	return _nullsec_net

func _show_nullsec_room() -> void:
	if _nullsec_room != null and is_instance_valid(_nullsec_room):
		_nullsec_room.queue_free()
	_nullsec_room = NullsecRoomUI.new()
	_nullsec_room.setup(_ensure_nullsec_net())
	_nullsec_room.leave_room.connect(_on_nullsec_leave)
	_nullsec_room.start_match.connect(_on_nullsec_start_match)
	add_child(_nullsec_room)
	_nullsec_lobby.hide()

func _on_nullsec_leave() -> void:
	MatchLoadOverlay.hide_overlay()
	if _nullsec_net:
		_nullsec_net.close()
	if _nullsec_room:
		_nullsec_room.queue_free()
		_nullsec_room = null

func _on_nullsec_start_match(assignments: Dictionary) -> void:
	var net: NullsecNetSession = _ensure_nullsec_net()
	SessionDiagnostics.log("net.match_start", "seat=%d host=%s" % [net.local_seat, net.is_host])
	MatchLoadOverlay.set_phase("正在进入对局场景", 0.28)
	net.persist_across_scenes()
	var spectate: bool = net.local_is_spectator()
	GameSession.pending_mode = "nullsec"
	GameSession.pending_nullsec = {
		"assignments": assignments,
		"seats": net.seats,
		"local_seat": net.local_seat,
		"host_seat": TypedVariant.as_int(net.last_match_payload.get("host_seat", 0), 0),
		"match_seed": TypedVariant.as_int(net.last_match_payload.get("match_seed", Time.get_unix_time_from_system()), int(Time.get_unix_time_from_system())),
		"spectator": spectate,
		"spectate_reason": "seat_spectate" if spectate else "",
		"security_mode": str(net.last_match_payload.get("security_mode", net.security_mode)),
	}
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _enter_nullsec_from_mid_join(net: NullsecNetSession, payload: Dictionary) -> void:
	MatchLoadOverlay.set_phase("正在进入对局场景", 0.28)
	net.persist_across_scenes()
	var asg: Dictionary = TypedVariant.as_dict(payload.get("assignments", {}))
	var sec: String = str(payload.get("security_mode", net.security_mode))
	if asg.is_empty():
		var rng: MatchRng = MatchRng.new()
		rng.configure(TypedVariant.as_int(payload.get("match_seed", 1), 1), str(payload.get("rules_hash", "")))
		var dir: NullsecMatchDirector = NullsecMatchDirector.new()
		dir.setup(rng)
		dir.set_seats(TypedVariant.as_array(payload.get("seats", [])))
		asg = dir.assign_regions(sec)
	GameSession.pending_mode = "nullsec"
	GameSession.pending_nullsec = {
		"assignments": asg,
		"seats": payload.get("seats", net.seats),
		"local_seat": net.local_seat,
		"host_seat": TypedVariant.as_int(payload.get("host_seat", 0), 0),
		"match_seed": TypedVariant.as_int(payload.get("match_seed", Time.get_unix_time_from_system()), int(Time.get_unix_time_from_system())),
		"spectator": true,
		"spectate_reason": "mid_join",
		"security_mode": sec,
	}
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _nullsec_mismatch_suffix(mismatch_n: int) -> String:
	if mismatch_n <= 0:
		return ""
	return " · 另有 %d 间版本不符" % mismatch_n


func _on_nullsec_match_public() -> void:
	## Invisible busy lock until the current scan/try-join finishes; spam clicks ignored silently.
	if _nullsec_match_busy:
		return
	_nullsec_match_busy = true
	await _nullsec_match_public_run()
	_nullsec_match_busy = false


func _nullsec_match_public_run() -> void:
	var nick: String = _nullsec_lobby.current_nick()
	var ignore_started: bool = _nullsec_lobby.ignore_in_match_rooms()
	_nullsec_lobby.set_status("正在扫描局域网…")
	var rules: String = MatchRng.compute_rules_hash()
	## -1 → platform default (emulator waits longer for shared-net peers).
	var rooms: Array = await LanBeacon.discover(self, -1.0)
	var mismatch_n: int = PublicRoomEnumerator.count_rules_mismatch(rooms, rules)
	var started_n: int = PublicRoomEnumerator.count_in_match(rooms, rules)
	var full_n: int = PublicRoomEnumerator.count_full(rooms, rules)
	var candidates: Array = PublicRoomEnumerator.list_join_candidates(rooms, rules, ignore_started)
	var private_n: int = 0
	var net: NullsecNetSession = _ensure_nullsec_net()
	## Same room_code may map to multiple endpoints — try each; one reject does not skip siblings.
	for pick: Variant in candidates:
		if typeof(pick) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = pick
		var code: int = TypedVariant.as_int(d.get("code", 0), 0)
		var ip: String = str(d.get("ip", "127.0.0.1"))
		var port: int = TypedVariant.as_int(d.get("port", NullsecNetSession.port_for_code(code)), NullsecNetSession.port_for_code(code))
		var in_match_ad: bool = TypedVariant.as_bool(d.get("in_match", false), false)
		net.close()
		_nullsec_lobby.set_status("正在试加入房间…")
		var err: Error = net.join(ip, port, nick, rules, "")
		if err != OK:
			continue
		var join_res: Dictionary = await _await_nullsec_join_ex(net, 2.0)
		if not TypedVariant.as_bool(join_res.get("ok", false), false):
			var reason: String = str(join_res.get("reason", ""))
			net.close()
			if reason == "need_password" or reason.find("需要房间密码") >= 0:
				private_n += 1
				continue
			if reason.find("已满") >= 0 or reason == "room full":
				full_n += 1
				continue
			continue
		PublicRoomEnumerator.advance_past(code)
		SessionDiagnostics.log("net.join", "ok match code=%04d ep=%s:%d" % [code, ip, port])
		var joined_in_match: bool = TypedVariant.as_bool(join_res.get("in_match", false), false) or in_match_ad or net.match_started
		var tip_extra: String = _nullsec_match_skip_suffix(started_n if ignore_started else 0, full_n, private_n, mismatch_n)
		if joined_in_match:
			_nullsec_lobby.set_status("已加入房间 · 观战%s" % tip_extra)
			if net.last_match_payload.is_empty():
				var got: Dictionary = {"p": {}}
				var on_ms: Callable = func(p: Dictionary) -> void: got["p"] = p
				net.match_start.connect(on_ms)
				var end_ms: int = Time.get_ticks_msec() + 2000
				while Time.get_ticks_msec() < end_ms and net.last_match_payload.is_empty() and TypedVariant.as_dict(got["p"]).is_empty():
					await get_tree().process_frame
				if net.match_start.is_connected(on_ms):
					net.match_start.disconnect(on_ms)
				if not TypedVariant.as_dict(got["p"]).is_empty():
					net.last_match_payload = TypedVariant.as_dict(got["p"]).duplicate(true)
			_enter_nullsec_from_mid_join(net, net.last_match_payload)
			return
		_nullsec_lobby.set_status("已加入房间%s" % tip_extra)
		_show_nullsec_room()
		return
	var parts: PackedStringArray = ["未发现可加入房间"]
	if ignore_started and started_n > 0:
		parts.append("已略过 %d 间已开局" % started_n)
	if full_n > 0:
		parts.append("已满 %d 间" % full_n)
	if private_n > 0:
		parts.append("私密房 %d 间" % private_n)
	if mismatch_n > 0:
		parts.append("版本不符 %d 间" % mismatch_n)
	parts.append("可点「主持公开房间」开一间")
	_nullsec_lobby.set_status(" · ".join(parts))


func _nullsec_match_skip_suffix(started_n: int, full_n: int, private_n: int, mismatch_n: int) -> String:
	var bits: PackedStringArray = []
	if started_n > 0:
		bits.append("已略过 %d 间已开局" % started_n)
	if full_n > 0:
		bits.append("已满 %d 间" % full_n)
	if private_n > 0:
		bits.append("私密房 %d 间" % private_n)
	if mismatch_n > 0:
		bits.append("另有 %d 间版本不符" % mismatch_n)
	if bits.is_empty():
		return ""
	return " · " + " · ".join(bits)


func _on_nullsec_host_room(password: String = "") -> void:
	var nick: String = _nullsec_lobby.current_nick()
	var pw: String = password.strip_edges()
	_nullsec_lobby.set_status("正在选定空闲房间…")
	## Host path: strictly avoid LAN-announced codes; bind fail → retry next code.
	## -1 → longer wait on Android emulator (shared-net peers).
	var rooms: Array = await LanBeacon.discover(self, -1.0)
	var taken: Dictionary = {}
	for r: Variant in rooms:
		if typeof(r) == TYPE_DICTIONARY:
			var rd: Dictionary = r
			taken[TypedVariant.as_int(rd.get("code", 0), 0)] = true
	var rules: String = MatchRng.compute_rules_hash()
	var net: NullsecNetSession = _ensure_nullsec_net()
	var last_err: String = ""
	for _attempt: int in range(64):
		if taken.size() >= 9999:
			break
		var code: int = PublicRoomEnumerator.claim_free_code(taken)
		if code <= 0 or taken.has(code):
			break
		var claim: Dictionary = ShortcodeSignaling.claim_public_sync(code, rules, {"nick": nick})
		if not TypedVariant.as_bool(claim.get("ok", false), false):
			taken[code] = true
			last_err = str(claim.get("reason", "claim_failed"))
			continue
		code = TypedVariant.as_int(claim.get("code", code), code)
		net.close()
		var err: Error = net.host_room(code, nick, pw)
		if err == OK:
			var via: String = str(claim.get("via", "lan_local"))
			var stun_note: String = " · STUN开" if NetConnectivity.public_stun_enabled() else ""
			var verbal: String = "私密" if not pw.is_empty() else "公开"
			SessionDiagnostics.log("net.host", "ok code=%04d pw=%s" % [code, "yes" if not pw.is_empty() else "no"])
			_nullsec_lobby.set_status("已主持%s房（%s%s）· 进房后可复制房间码" % [verbal, via, stun_note])
			_show_nullsec_room()
			return
		SessionDiagnostics.log("net.host", "bind fail code=%04d err=%s → retry" % [code, error_string(err)])
		taken[code] = true
		last_err = error_string(err)
	SessionDiagnostics.log("net.host", "fail exhausted last=%s" % last_err)
	_nullsec_lobby.set_status("开房失败: %s" % (last_err if last_err != "" else "无可用听口"))


func _on_nullsec_join_share(raw: String) -> void:
	var kind: String = InviteBlobHelper.classify(raw)
	if kind == InviteBlobHelper.KIND_INVALID:
		_nullsec_lobby.set_status("请粘贴房间码（EAC…）")
		return
	await _on_nullsec_join_full_share(raw)


func _on_nullsec_join_full_share(blob: String) -> void:
	var decoded: Dictionary = InviteBlobHelper.decode(blob)
	if decoded.is_empty():
		_nullsec_lobby.set_status("房间码无法解析")
		return
	var password: String = str(decoded.get("password", ""))
	var room_code: int = TypedVariant.as_int(decoded.get("room_code", TypedVariant.as_int(decoded.get("room", 0), 0)), 0)
	var nick: String = _nullsec_lobby.current_nick()
	var local_rules: String = MatchRng.compute_rules_hash()
	var host_rules: String = str(decoded.get("rules", ""))
	if host_rules == "":
		host_rules = local_rules
	if host_rules != local_rules:
		_nullsec_lobby.set_status("版本不符 · 房间主持 %s · 本机 %s" % [host_rules, local_rules])
		return
	## Build try order: LAN same room → ipv6 → ipv4 → reflexive.
	var endpoints: Array = []
	if room_code >= 1 and room_code <= 9999:
		_nullsec_lobby.set_status("正在扫描局域网…")
		var rooms: Array = await LanBeacon.discover(self, -1.0)
		for r: Variant in rooms:
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = r
			if TypedVariant.as_int(d.get("code", 0), 0) != room_code:
				continue
			endpoints.append({
				"ip": str(d.get("ip", "")),
				"port": TypedVariant.as_int(d.get("port", NullsecNetSession.port_for_code(room_code)), NullsecNetSession.port_for_code(room_code)),
			})
	for e: Dictionary in InviteBlobHelper.join_endpoints(decoded):
		endpoints.append(e)
	## Dedup
	var seen: Dictionary = {}
	var uniq: Array = []
	for e: Variant in endpoints:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ep: Dictionary = e
		var key: String = "%s:%d" % [str(ep.get("ip", "")), TypedVariant.as_int(ep.get("port", 0), 0)]
		if key == ":0" or seen.has(key):
			continue
		seen[key] = true
		uniq.append(ep)
	if uniq.is_empty():
		var addr: Dictionary = InviteBlobHelper.join_address(decoded)
		var room: String = str(addr.get("room", decoded.get("room", "")))
		var resolved: Dictionary = ShortcodeSignaling.resolve_join_sync("public", room, host_rules)
		if TypedVariant.as_bool(resolved.get("ok", false), false):
			uniq.append({"ip": str(resolved.get("ip", "")), "port": TypedVariant.as_int(resolved.get("port", 0), 0)})
	if uniq.is_empty():
		_nullsec_lobby.set_status("房间码无有效地址（可配 signaling_url / TURN）")
		return
	var net: NullsecNetSession = _ensure_nullsec_net()
	var last_err: String = ""
	for e: Variant in uniq:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ep: Dictionary = e
		var ip: String = str(ep.get("ip", ""))
		var port: int = TypedVariant.as_int(ep.get("port", 0), 0)
		if ip == "" or port <= 0:
			continue
		net.close()
		_nullsec_lobby.set_status("正在试连 %s:%d… · 房间主持 %s" % [ip, port, host_rules])
		var err: Error = net.join(ip, port, nick, local_rules, password)
		if err != OK:
			last_err = error_string(err)
			continue
		var join_share: Dictionary = await _await_nullsec_join_ex(net, 1.5)
		if TypedVariant.as_bool(join_share.get("ok", false), false):
			_nullsec_lobby.set_status("已通过房间码加入 · 房间主持 %s" % host_rules)
			_show_nullsec_room()
			return
		last_err = str(join_share.get("reason", "超时"))
		net.close()
	var turn_n: int = NetConnectivity.turn_urls().size()
	if turn_n > 0:
		_nullsec_lobby.set_status("双栈试连失败 · 已配置 TURN 但仍不可达: %s" % last_err)
	else:
		_nullsec_lobby.set_status("加入失败: %s（可在 user://net_connectivity.cfg 配 TURN）" % last_err)


func _await_nullsec_join(net: NullsecNetSession, timeout_s: float) -> bool:
	var res: Dictionary = await _await_nullsec_join_ex(net, timeout_s)
	return TypedVariant.as_bool(res.get("ok", false), false)

func _await_nullsec_join_ex(net: NullsecNetSession, timeout_s: float) -> Dictionary:
	if net == null:
		return {"ok": false, "in_match": false, "reason": ""}
	if net.local_seat >= 0:
		return {"ok": true, "in_match": net.match_started, "reason": ""}
	var done: Dictionary = {"ok": false, "fail": false, "in_match": false, "reason": ""}
	var on_ok: Callable = func(_seat: int, in_match: bool = false) -> void:
		done["ok"] = true
		done["in_match"] = in_match
	var on_fail: Callable = func(r: String) -> void:
		done["fail"] = true
		done["reason"] = r
	net.join_accepted.connect(on_ok)
	net.rejected.connect(on_fail)
	var end_ms: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if TypedVariant.as_bool(done["ok"], false) or net.local_seat >= 0:
			net.join_accepted.disconnect(on_ok)
			net.rejected.disconnect(on_fail)
			return {"ok": true, "in_match": TypedVariant.as_bool(done["in_match"], false) or net.match_started, "reason": ""}
		if TypedVariant.as_bool(done["fail"], false):
			net.join_accepted.disconnect(on_ok)
			net.rejected.disconnect(on_fail)
			return {"ok": false, "in_match": false, "reason": str(done["reason"])}
		await get_tree().process_frame
	if net.join_accepted.is_connected(on_ok):
		net.join_accepted.disconnect(on_ok)
	if net.rejected.is_connected(on_fail):
		net.rejected.disconnect(on_fail)
	return {"ok": net.local_seat >= 0, "in_match": net.match_started, "reason": ""}

func _on_nullsec_history() -> void:
	var path: String = "user://save/nullsec_history.json"
	if not FileAccess.file_exists(path):
		_nullsec_lobby.set_status("尚无历史战绩")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		_nullsec_lobby.set_status("尚无历史战绩")
		return
	var parsed_arr: Array = TypedVariant.as_array(parsed)
	if parsed_arr.is_empty():
		_nullsec_lobby.set_status("尚无历史战绩")
		return
	var last_entry: Variant = parsed_arr.back()
	var last: Dictionary = TypedVariant.as_dict(last_entry)
	var rows: Array = TypedVariant.as_array(last.get("rows", []))
	var panel: NullsecSettlementPanel = NullsecSettlementPanel.new()
	add_child(panel)
	panel.title = "多人联机历史战绩"
	panel.show_rows(rows, false)

func _on_versus() -> void:
	if not DataStore.host_ships_override.is_empty():
		DataStore.clear_host_ships_override()
	GameSession.resume_save = false
	GameSession.resume_slot_id = ""
	GameSession.resume_payload = {}
	GameSession.pending_mode = "versus"
	GameSession.pending_nullsec = {}
	MatchLoadOverlay.set_phase("正在进入对局场景", 0.15)
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_endless() -> void:
	if not DataStore.host_ships_override.is_empty():
		DataStore.clear_host_ships_override()
	GameSession.resume_save = false
	GameSession.resume_slot_id = ""
	GameSession.resume_payload = {}
	GameSession.pending_mode = "endless"
	GameSession.pending_nullsec = {}
	MatchLoadOverlay.set_phase("正在进入对局场景", 0.15)
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_continue() -> void:
	## Prefer live nullsec rejoin ticket (SEMI_ASYNC §5.3a); else single-player last_match.
	if NullsecRejoinTicket.exists():
		await _continue_nullsec_rejoin()
		return
	_continue_local_last_match()


func _usable_local_last_match() -> Dictionary:
	## Non-nullsec last_match suitable for single-player resume.
	if not MatchSave.exists():
		return {}
	var d: Dictionary = MatchSave.load_dict()
	if d.is_empty():
		return {}
	if str(d.get("mode", "")) == "nullsec":
		return {}
	var solo: String = MatchSave.normalize_solo_mode(d.get("mode", "versus"))
	if solo == "":
		solo = "versus"
	d["mode"] = solo
	return d


func _continue_local_last_match() -> void:
	var d: Dictionary = _usable_local_last_match()
	if d.is_empty():
		if MatchSave.exists() and str(MatchSave.load_dict().get("mode", "")) == "nullsec":
			## Stale combat snapshot — multiplayer uses nullsec_rejoin.json instead.
			MatchSave.clear()
			_refresh_continue_btn()
		return
	GameSession.resume_save = true
	GameSession.resume_slot_id = ""
	GameSession.resume_payload = {}
	## Must match save before match.tscn boots MapEnv (versus = dual citadel).
	GameSession.pending_mode = MatchSave.normalize_solo_mode(d.get("mode", "versus"))
	if GameSession.pending_mode == "":
		GameSession.pending_mode = "versus"
	MatchLoadOverlay.set_phase("正在进入对局场景", 0.15)
	get_tree().change_scene_to_file("res://scenes/match.tscn")


func _close_continue_search_dlg() -> void:
	if _continue_search_dlg != null and is_instance_valid(_continue_search_dlg):
		_continue_search_dlg.queue_free()
	_continue_search_dlg = null


func _ask_fallback_local_last_match() -> void:
	## After failed remote rejoin (2A): offer local autosave if present (MATCH_FLOW §5.0b).
	var d: Dictionary = _usable_local_last_match()
	if d.is_empty():
		return
	var mode: String = MatchSave.normalize_solo_mode(d.get("mode", "versus"))
	if mode == "":
		mode = "versus"
	var mode_l: String = "对战" if mode == "versus" else "无尽"
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = "无法加入远程对局"
	dlg.dialog_text = "联机对局已无法重连。是否回落本地上次自动存档（%s）？" % mode_l
	dlg.ok_button_text = "读取本地存档"
	dlg.cancel_button_text = "取消"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		_continue_local_last_match()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()


func _continue_nullsec_rejoin() -> void:
	## MATCH_FLOW §5.0b / UI_AND_SHELL：点继续立刻弹「搜索上次远程房间中」+ 读本地 / 取消。
	var ticket: Dictionary = NullsecRejoinTicket.load_dict()
	if ticket.is_empty():
		NullsecRejoinTicket.clear()
		_refresh_continue_btn()
		return
	_continue_rejoin_gen += 1
	var gen: int = _continue_rejoin_gen
	_close_continue_search_dlg()
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = "继续上次对局"
	dlg.dialog_text = "搜索上次远程房间中"
	dlg.ok_button_text = "读取本地存档"
	dlg.cancel_button_text = "取消"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dlg)
	_continue_search_dlg = dlg
	var has_local: bool = not _usable_local_last_match().is_empty()
	var ok_btn: Button = dlg.get_ok_button()
	if ok_btn:
		ok_btn.disabled = not has_local
	dlg.confirmed.connect(func() -> void:
		## Abandon remote search; load local autosave.
		_continue_rejoin_gen += 1
		_close_continue_search_dlg()
		_continue_local_last_match()
	)
	dlg.canceled.connect(func() -> void:
		_continue_rejoin_gen += 1
		_close_continue_search_dlg()
	)
	dlg.close_requested.connect(func() -> void:
		_continue_rejoin_gen += 1
		_close_continue_search_dlg()
	)
	dlg.popup_centered()
	## Paint the dialog before LAN / join awaits (instant feedback).
	await get_tree().process_frame
	await get_tree().process_frame
	if gen != _continue_rejoin_gen:
		return
	var joined: bool = await _try_nullsec_rejoin_from_ticket(ticket, gen)
	if gen != _continue_rejoin_gen:
		return
	_close_continue_search_dlg()
	if joined:
		_enter_nullsec_from_rejoin(_ensure_nullsec_net(), _ensure_nullsec_net().last_match_payload)
		return
	## 2A: nobody online → clear ticket; offer local last_match if any.
	NullsecRejoinTicket.clear()
	_refresh_continue_btn()
	if _nullsec_lobby:
		_nullsec_lobby.set_status("无法重连 · 对局已解散")
	push_warning("Nullsec rejoin failed — ticket cleared (2A)")
	_ask_fallback_local_last_match()


func _try_nullsec_rejoin_from_ticket(ticket: Dictionary, gen: int) -> bool:
	var nick: String = str(ticket.get("nick", "玩家"))
	var rules: String = str(ticket.get("rules_hash", MatchRng.compute_rules_hash()))
	var net: NullsecNetSession = _ensure_nullsec_net()
	net.close()
	net.pending_rejoin_seat = TypedVariant.as_int(ticket.get("seat_id", -1), -1)
	net.pending_rejoin_secret = str(ticket.get("session_secret", ""))
	net.session_secret = str(ticket.get("session_secret", ""))
	net.match_id = str(ticket.get("match_id", ""))
	net.opening_host_platform = str(ticket.get("opening_host_platform", "pc"))
	net.opening_host_ships_hash = str(ticket.get("opening_host_ships_hash", ""))
	net.host_migrate_generation = TypedVariant.as_int(ticket.get("host_migrate_generation", 0), 0)
	net.security_mode = str(ticket.get("security_mode", NullsecNetSession.SECURITY_NULLSEC))
	net.room_code = TypedVariant.as_int(ticket.get("room_code", 0), 0)
	net.room_password = str(ticket.get("room_password", ticket.get("private_code", "")))
	net.room_has_password = not net.room_password.is_empty() or TypedVariant.as_bool(ticket.get("is_private", false), false)
	var candidates: Array = []
	var tip: String = str(ticket.get("host_ip", ""))
	var tport: int = TypedVariant.as_int(ticket.get("host_port", 0), 0)
	if tip != "" and tport > 0:
		candidates.append({"ip": tip, "port": tport})
	var blob: String = str(ticket.get("room_blob", ""))
	if blob != "":
		var decoded: Dictionary = InviteBlobHelper.decode(blob)
		for e: Dictionary in InviteBlobHelper.join_endpoints(decoded):
			candidates.append(e)
		if str(ticket.get("room_password", "")) == "" and str(decoded.get("password", "")) != "":
			net.room_password = str(decoded.get("password", ""))
			net.room_has_password = true
	if gen != _continue_rejoin_gen:
		return false
	## LAN beacon for same room_code / in_match.
	var rooms: Array = await LanBeacon.discover(self, -1.0)
	if gen != _continue_rejoin_gen:
		return false
	var want_code: int = TypedVariant.as_int(ticket.get("room_code", 0), 0)
	for r: Variant in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if TypedVariant.as_int(d.get("code", -1), -1) != want_code:
			continue
		if not TypedVariant.as_bool(d.get("in_match", false), false):
			continue
		candidates.append({
			"ip": str(d.get("ip", "127.0.0.1")),
			"port": TypedVariant.as_int(d.get("port", NullsecNetSession.port_for_code(want_code)), NullsecNetSession.port_for_code(want_code)),
		})
	for c: Variant in candidates:
		if gen != _continue_rejoin_gen:
			return false
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cand: Dictionary = c
		var ip: String = str(cand.get("ip", ""))
		var port: int = TypedVariant.as_int(cand.get("port", 0), 0)
		if ip == "" or port <= 0:
			continue
		net.pending_rejoin_seat = TypedVariant.as_int(ticket.get("seat_id", -1), -1)
		net.pending_rejoin_secret = str(ticket.get("session_secret", ""))
		var err: Error = net.join(ip, port, nick, rules, str(ticket.get("room_password", net.room_password)))
		if err != OK:
			continue
		var join_res: Dictionary = await _await_nullsec_join_ex(net, 5.0)
		if gen != _continue_rejoin_gen:
			net.close()
			return false
		if TypedVariant.as_bool(join_res.get("ok", false), false) and net.local_seat == TypedVariant.as_int(ticket.get("seat_id", -2), -2):
			return true
		net.close()
	return false


func _enter_nullsec_from_rejoin(net: NullsecNetSession, payload: Dictionary) -> void:
	net.persist_across_scenes()
	var asg: Dictionary = TypedVariant.as_dict(payload.get("assignments", {}))
	var sec: String = str(payload.get("security_mode", net.security_mode))
	if asg.is_empty():
		var rng: MatchRng = MatchRng.new()
		rng.configure(TypedVariant.as_int(payload.get("match_seed", 1), 1), str(payload.get("rules_hash", "")))
		var dir: NullsecMatchDirector = NullsecMatchDirector.new()
		dir.setup(rng)
		dir.set_seats(TypedVariant.as_array(payload.get("seats", [])))
		asg = dir.assign_regions(sec)
	GameSession.resume_save = false
	GameSession.pending_mode = "nullsec"
	GameSession.pending_nullsec = {
		"assignments": asg,
		"seats": payload.get("seats", net.seats),
		"local_seat": net.local_seat,
		"host_seat": TypedVariant.as_int(payload.get("host_seat", 0), 0),
		"match_seed": TypedVariant.as_int(payload.get("match_seed", Time.get_unix_time_from_system()), int(Time.get_unix_time_from_system())),
		"spectator": false,
		"spectate_reason": "",
		"rejoin": true,
		"security_mode": sec,
	}
	NullsecRejoinTicket.write_from_session(net)
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_load_open() -> void:
	if _load_panel == null:
		return
	_refresh_load_list()
	_apply_adaptive_layout()
	_load_panel.visible = true

func _build_load_panel() -> Control:
	var panel: PanelContainer = _modal_panel("LoadSavePanel")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "读取存档"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(24, self))
	cap_row.add_child(cap)
	var close_x: Button = Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func() -> void: panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, UiLayout.px(220, self))
	box.add_child(scroll)
	_load_list = VBoxContainer.new()
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	scroll.add_child(_load_list)
	return panel

func _refresh_load_list() -> void:
	if _load_list == null:
		return
	for c: Node in _load_list.get_children():
		c.queue_free()
	var slots: Array = MatchSave.list_slots()
	if slots.is_empty() and MatchSave.exists():
		slots = [{
			"id": MatchSave.FLAGSHIP_TEST_ID,
			"name": MatchSave.FLAGSHIP_TEST_NAME,
			"path": MatchSave.FLAGSHIP_TEST_PATH if FileAccess.file_exists(MatchSave.FLAGSHIP_TEST_PATH) else MatchSave.SAVE_PATH,
			"updated_at": "",
		}]
	if slots.is_empty():
		var empty: Label = Label.new()
		empty.text = "暂无存档"
		UiAssets.apply_label_font(empty, false, UiLayout.font_size(16, self))
		_load_list.add_child(empty)
		return
	for s: Variant in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = s
		var sid: String = str(entry.get("id", ""))
		var slot_name: String = str(entry.get("name", sid))
		var updated: String = str(entry.get("updated_at", ""))
		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
		var load_btn: Button = Button.new()
		load_btn.text = slot_name if updated == "" else "%s\n%s" % [slot_name, updated]
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.custom_minimum_size = Vector2(0, UiLayout.px(52, self))
		load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiAssets.apply_button_font(load_btn, UiLayout.font_size(15, self))
		load_btn.pressed.connect(_on_load_slot.bind(sid))
		row.add_child(load_btn)
		var rename_btn: Button = Button.new()
		rename_btn.text = "重命名"
		rename_btn.custom_minimum_size = Vector2(UiLayout.px(72, self), UiLayout.px(52, self))
		UiAssets.apply_button_font(rename_btn, UiLayout.font_size(14, self))
		rename_btn.pressed.connect(_on_rename_open.bind(sid, slot_name))
		row.add_child(rename_btn)
		var del_btn: Button = Button.new()
		del_btn.text = "删除"
		del_btn.custom_minimum_size = Vector2(UiLayout.px(64, self), UiLayout.px(52, self))
		UiAssets.apply_button_font(del_btn, UiLayout.font_size(14, self))
		del_btn.pressed.connect(_on_delete_slot.bind(sid, slot_name))
		row.add_child(del_btn)
		_load_list.add_child(row)


func _build_rename_panel() -> Control:
	var panel: PanelContainer = _modal_panel("RenameSavePanel")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "重命名存档"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var close_x: Button = Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func() -> void: panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)
	_rename_edit = LineEdit.new()
	_rename_edit.placeholder_text = "存档名称"
	_rename_edit.add_theme_font_size_override("font_size", UiLayout.font_size(16, self))
	box.add_child(_rename_edit)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var cancel: Button = Button.new()
	cancel.text = "取消"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_button_font(cancel, UiLayout.font_size(16, self))
	cancel.pressed.connect(func() -> void: panel.visible = false)
	row.add_child(cancel)
	var ok: Button = Button.new()
	ok.text = "确认"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_button_font(ok, UiLayout.font_size(16, self))
	ok.pressed.connect(_on_rename_confirm)
	row.add_child(ok)
	box.add_child(row)
	return panel


func _on_rename_open(slot_id: String, current_name: String) -> void:
	_rename_slot_id = slot_id
	if _rename_edit:
		_rename_edit.text = current_name
	_apply_adaptive_layout()
	if _rename_panel:
		_rename_panel.visible = true


func _on_rename_confirm() -> void:
	var save_name: String = _rename_edit.text if _rename_edit else ""
	var r: Dictionary = MatchSave.rename_slot(_rename_slot_id, save_name)
	if _rename_panel:
		_rename_panel.visible = false
	if TypedVariant.as_bool(r.get("ok", false), false):
		_refresh_load_list()
	_rename_slot_id = ""


func _on_delete_slot(slot_id: String, display_name: String) -> void:
	## Inline confirm: second press not needed — use a small confirm panel via rename-style, or AcceptDialog.
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = "删除存档"
	dlg.dialog_text = "确定删除「%s」？此操作不可恢复。" % display_name
	dlg.ok_button_text = "删除"
	dlg.cancel_button_text = "取消"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		var r: Dictionary = MatchSave.delete_slot(slot_id)
		if TypedVariant.as_bool(r.get("ok", false), false):
			_refresh_load_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()


func _disable_continue_btn() -> void:
	if _btn_box == null:
		return
	for c: Node in _btn_box.get_children():
		var b: Button = c as Button
		if b and b.text == "继续上次对局":
			b.disabled = true
			return


func _refresh_continue_btn() -> void:
	if _btn_box == null:
		return
	var enable: bool = MatchSave.exists() or NullsecRejoinTicket.exists()
	for c: Node in _btn_box.get_children():
		var b: Button = c as Button
		if b and b.text == "继续上次对局":
			b.disabled = not enable
			return


func _on_load_slot(slot_id: String) -> void:
	var d: Dictionary = MatchSave.load_slot_dict(slot_id)
	if d.is_empty() and slot_id == MatchSave.FLAGSHIP_TEST_ID:
		## Retry after bundled→user seed (fresh install / deleted slot).
		MatchSave.list_slots()
		d = MatchSave.load_slot_dict(slot_id)
		if d.is_empty():
			d = MatchSave.load_dict()
	if d.is_empty():
		push_warning("MainMenu load_slot empty id=%s" % slot_id)
		return
	if str(d.get("mode", "")) == "nullsec":
		## Left over from before nullsec stopped writing saves — it has no room,
		## no seats and no host to rejoin (MATCH_FLOW §5.0b).
		push_warning("MainMenu load_slot nullsec slot refused id=%s" % slot_id)
		return
	## 随机诱导/旗舰注入：仅「读取存档」点选旗舰测试；不写回冻结档，不进 load_slot / 继续上次。
	if slot_id == MatchSave.FLAGSHIP_TEST_ID:
		d = MatchSave.inject_flagship_test_ai_kit(d)
		GameSession.resume_payload = d
		## 勿再带 slot_id 进对局，避免 match 侧二次读盘误注入或读到未注入快照。
		GameSession.resume_slot_id = ""
	else:
		GameSession.resume_payload = {}
		GameSession.resume_slot_id = slot_id
	GameSession.resume_save = true
	var solo: String = MatchSave.normalize_solo_mode(d.get("mode", "versus"))
	GameSession.pending_mode = solo if solo != "" else "versus"
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_bgm_toggled(on: bool) -> void:
	var bgm: BgMusic = _bgm()
	if bgm:
		bgm.set_enabled(on)

func _on_bgm_volume_changed(v: float) -> void:
	if _bgm_lbl:
		_bgm_lbl.text = str(int(v))
	var bgm: BgMusic = _bgm()
	if bgm:
		bgm.set_volume_pct(v)

func _on_options_open() -> void:
	if _options:
		_apply_adaptive_layout()
		_options.visible = true
		if _fps_slider:
			_fps_slider.value = GameSession.target_fps
		var bgm: BgMusic = _bgm()
		if bgm:
			if _bgm_check:
				_bgm_check.set_pressed_no_signal(bgm.enabled)
			if _bgm_slider:
				_bgm_slider.set_value_no_signal(bgm.volume_pct)
			if _bgm_lbl:
				_bgm_lbl.text = str(int(bgm.volume_pct))


func _on_dev_debug_open() -> void:
	if _options:
		_options.visible = false
	_sync_dev_debug_widgets()
	if _dev_panel:
		_apply_adaptive_layout()
		_dev_panel.visible = true


func _sync_dev_debug_widgets() -> void:
	if _dev_master_check:
		_dev_master_check.set_pressed_no_signal(GameSession.developer_debug_enabled)
	var master_on: bool = GameSession.developer_debug_enabled
	if _dev_soften_check:
		_dev_soften_check.set_pressed_no_signal(GameSession.player_citadel_soften)
		_dev_soften_check.disabled = not master_on
	if _dev_economy_check:
		_dev_economy_check.set_pressed_no_signal(GameSession.player_ai_double_economy)
		_dev_economy_check.disabled = not master_on
	if _dev_enemy_layout_check:
		_dev_enemy_layout_check.set_pressed_no_signal(GameSession.enemy_layout_adjust)
		_dev_enemy_layout_check.disabled = not master_on
	if _dev_ship_data_btn:
		_dev_ship_data_btn.disabled = not master_on


func _on_dev_master_toggled(on: bool) -> void:
	GameSession.set_developer_debug_enabled(on)
	SessionDiagnostics.log("dev.debug", "on=%s" % on)
	if _dev_soften_check:
		_dev_soften_check.disabled = not on
	if _dev_economy_check:
		_dev_economy_check.disabled = not on
	if _dev_enemy_layout_check:
		_dev_enemy_layout_check.disabled = not on
	if _dev_ship_data_btn:
		_dev_ship_data_btn.disabled = not on


## UI_AND_SHELL §2.5.1 — same editor as in-match; exit autosaves and reloads DataStore.
func _on_dev_ship_data_open() -> void:
	if not GameSession.developer_debug_enabled:
		return
	if _ship_data_editor == null or not is_instance_valid(_ship_data_editor):
		_ship_data_editor = ShipDataEditor.new()
		_ship_data_editor.closed.connect(_on_ship_data_editor_closed)
		add_child(_ship_data_editor)
	_ship_data_editor.z_index = 9
	_ship_data_editor.open(false)
	SessionDiagnostics.log("editor.open", "menu")


func _on_export_debug_log() -> void:
	var res: Dictionary = SessionDiagnostics.export_session_log()
	var msg: String = ""
	if TypedVariant.as_bool(res.get("ok", false), false):
		msg = "已导出并复制路径: %s" % str(res.get("path", ""))
	else:
		var reason: String = str(res.get("reason", ""))
		if reason == "no_log":
			msg = "尚无会话日志"
		else:
			msg = "导出失败（%s）" % reason
	if _options_export_status:
		_options_export_status.text = msg


func _on_verify_content_version() -> void:
	if GameSession and GameSession.has_method("request_verify_content_version"):
		GameSession.request_verify_content_version()
	elif _options_export_status:
		_options_export_status.text = "当前壳不支持主动验版（需 202608.4.3+）"


func _on_ship_data_editor_closed(changed_ids: Array, equipment_changed: bool = false) -> void:
	SessionDiagnostics.log("editor.close", "changed=%d eq=%s" % [changed_ids.size(), equipment_changed])
	if changed_ids.is_empty() and not equipment_changed:
		return
	if _nullsec_net == null or not is_instance_valid(_nullsec_net) or not _nullsec_net.is_host:
		return
	## Hosting already: guests must learn the roster changed (§3.7).
	if _nullsec_net.match_started:
		_nullsec_net.broadcast_ships_table()
	else:
		_nullsec_net.broadcast_ships_hash()


func _on_dev_soften_toggled(on: bool) -> void:
	GameSession.set_player_citadel_soften(on)


func _on_dev_economy_toggled(on: bool) -> void:
	GameSession.set_player_ai_double_economy(on)


func _on_dev_enemy_layout_toggled(on: bool) -> void:
	GameSession.set_enemy_layout_adjust(on)


func _on_about_open() -> void:
	if _about:
		_apply_adaptive_layout()
		_about.visible = true

func _on_quit() -> void:
	get_tree().quit()
