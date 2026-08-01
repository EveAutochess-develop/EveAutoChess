extends Control
## StartScene — left menu column; sizes relative to viewport (UiLayout).

# preload: class_name may be missing from shell global cache after load_resource_pack
const _BgMusic := preload("res://scripts/audio/bg_music.gd")

const BILIBILI_URL := "https://space.bilibili.com/1581878"
const TITLE_TEXT := "星视寰宇EVE自走棋"
const DECLARE_TEXT := "EVE以及其相关之图标/设计均属CCP所有.\n所有数据均来自 网易 EVE Online ."
const CREDITS_TEXT := """制作人员名单:

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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_BgMusic.instance()
	MatchSave.list_slots()  ## seed 旗舰测试 from last_match if needed
	_build()
	_apply_adaptive_layout()
	resized.connect(_apply_adaptive_layout)
	Engine.max_fps = int(GameSession.target_fps)
	_start_announce_cycle()

func _build() -> void:
	var base := ColorRect.new()
	base.name = "BaseFill"
	UiAssets.full_rect(base)
	base.color = Color(0.04, 0.05, 0.08, 1)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	var bg := TextureRect.new()
	bg.name = "BG"
	UiAssets.full_rect(bg)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_tex := UiAssets.tex(UiAssets.MAIN_BG)
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
	var cont := _menu_btn("继续上次对局", _on_continue)
	cont.disabled = not MatchSave.exists()
	_btn_box.add_child(cont)
	var load_btn := _menu_btn("读取存档", _on_load_open)
	load_btn.disabled = MatchSave.list_slots().is_empty() and not MatchSave.exists()
	_btn_box.add_child(load_btn)
	_btn_box.add_child(_menu_btn("选项", _on_options_open))
	_btn_box.add_child(_menu_btn("退出游戏", _on_quit))
	_btn_box.add_child(_menu_btn("关于我们", _on_about_open))

	_footer = VBoxContainer.new()
	_footer.name = "Right"
	_col.add_child(_footer)

	var declare := Label.new()
	declare.name = "Declare"
	declare.text = DECLARE_TEXT
	declare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	declare.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 0.95))
	declare.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_footer.add_child(declare)

	var ver := Label.new()
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
	_nullsec_lobby.request_host_public.connect(_on_nullsec_host_public)
	_nullsec_lobby.request_host_private.connect(_on_nullsec_host_private)
	_nullsec_lobby.request_join_private.connect(_on_nullsec_join_private)
	_nullsec_lobby.request_history.connect(_on_nullsec_history)

func _apply_adaptive_layout() -> void:
	var pad := 0.035 if UiLayout.is_mobile() else 0.038
	var col_w := 0.38 if UiLayout.is_mobile() else 0.42
	UiLayout.set_rect_frac(_col, 0.0, 0.0, col_w, 1.0)

	# Title band ~ top 4%–11%
	UiLayout.set_rect_frac(_title, pad / col_w, 0.04, 0.95, 0.11)
	UiAssets.apply_label_font(_title, true, UiLayout.font_size(36, self))
	_title.add_theme_constant_override("outline_size", UiLayout.margin_px(6, self))

	# Buttons: middle of left column
	var btn_left := pad / col_w
	var btn_w := 0.55 if UiLayout.is_mobile() else 0.48
	UiLayout.set_rect_frac(_btn_box, btn_left, 0.22, btn_left + btn_w, 0.78)
	_btn_box.add_theme_constant_override("separation", UiLayout.margin_px(18 if UiLayout.is_mobile() else 28, self))
	var bh := UiLayout.px(48 if UiLayout.is_mobile() else 56, self)
	var bw := UiLayout.px(160 if UiLayout.is_mobile() else 200, self)
	var bfs := UiLayout.font_size(18 if UiLayout.is_mobile() else 22, self)
	for c in _btn_box.get_children():
		if c is Button:
			(c as Button).custom_minimum_size = Vector2(bw, bh)
			UiAssets.apply_button_font(c as Button, bfs)

	# Footer bottom of column
	UiLayout.set_rect_frac(_footer, pad / col_w, 0.82, 0.96, 0.98)
	_footer.add_theme_constant_override("separation", UiLayout.margin_px(4, self))
	var declare := _footer.get_node_or_null("Declare") as Label
	if declare:
		UiAssets.apply_label_font(declare, false, UiLayout.font_size(12, self))
		declare.add_theme_constant_override("outline_size", UiLayout.margin_px(2, self))
	var ver := _footer.get_node_or_null("VersionLabel") as Label
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
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.75, 0.4, 1))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.18, 0.82)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.26, 0.34, 0.92)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(cb)
	return b

func _build_options() -> Control:
	var panel := _modal_panel("OptionsPanel")
	var box := panel.get_node("Margin/VBox") as VBoxContainer

	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "选项菜单"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(24, self))
	cap_row.add_child(cap)
	var close_x := Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func(): panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var fps_cap := Label.new()
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

	var bgm := _BgMusic.instance()
	var bgm_on_row := HBoxContainer.new()
	bgm_on_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	_bgm_check = CheckBox.new()
	_bgm_check.text = "背景音乐"
	_bgm_check.button_pressed = bgm.enabled if bgm else false
	UiAssets.apply_button_font(_bgm_check, UiLayout.font_size(16, self))
	_bgm_check.toggled.connect(_on_bgm_toggled)
	bgm_on_row.add_child(_bgm_check)
	box.add_child(bgm_on_row)

	var nomodel_row := HBoxContainer.new()
	nomodel_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var nomodel := CheckBox.new()
	nomodel.text = "无模型性能模式"
	nomodel.button_pressed = GameSession.no_model_perf_mode
	UiAssets.apply_button_font(nomodel, UiLayout.font_size(16, self))
	nomodel.toggled.connect(_on_no_model_toggled)
	nomodel_row.add_child(nomodel)
	box.add_child(nomodel_row)

	var breathe_row := HBoxContainer.new()
	breathe_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var breathe := CheckBox.new()
	breathe.text = "镜头呼吸浮动"
	breathe.button_pressed = GameSession.camera_breathe_enabled
	UiAssets.apply_button_font(breathe, UiLayout.font_size(16, self))
	breathe.toggled.connect(_on_camera_breathe_toggled)
	breathe_row.add_child(breathe)
	box.add_child(breathe_row)

	var bgm_vol_row := HBoxContainer.new()
	bgm_vol_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var bgm_cap := Label.new()
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

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var lang_l := Label.new()
	lang_l.text = "语言"
	UiAssets.apply_label_font(lang_l, false, UiLayout.font_size(16, self))
	lang_row.add_child(lang_l)
	var lang := OptionButton.new()
	lang.add_item("中文", 0)
	lang.add_item("English", 1)
	lang_row.add_child(lang)
	box.add_child(lang_row)

	var dev_btn := Button.new()
	dev_btn.text = "开发者调试"
	dev_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(dev_btn, UiLayout.font_size(16, self))
	dev_btn.pressed.connect(_on_dev_debug_open)
	box.add_child(dev_btn)

	_dev_panel = _build_developer_debug_panel()
	add_child(_dev_panel)
	return panel


func _build_developer_debug_panel() -> Control:
	var panel := _modal_panel("DeveloperDebugPanel")
	var box := panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "开发者调试"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back := Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func():
		panel.visible = false
		if _options:
			_options.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)

	var hint := Label.new()
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

	var swap_hint := Label.new()
	swap_hint.text = "换边按钮在局内「开发者调试」中（备战阶段）"
	swap_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(swap_hint, false, 14)
	box.add_child(swap_hint)
	return panel

func _build_about() -> Control:
	var panel := _modal_panel("AboutUsPanel")
	var box := panel.get_node("Margin/VBox") as VBoxContainer

	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "关于我们"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(24, self))
	cap_row.add_child(cap)
	var close_x := Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func(): panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)

	var bili := Button.new()
	bili.text = "我们的B站主页(点击进入)\n%s" % BILIBILI_URL
	bili.custom_minimum_size = Vector2(0, UiLayout.px(52, self))
	UiAssets.apply_button_font(bili, UiLayout.font_size(14, self))
	bili.pressed.connect(func(): OS.shell_open(BILIBILI_URL))
	box.add_child(bili)

	var qq := Label.new()
	qq.text = "欢迎加入我们的QQ群关注最新进展"
	UiAssets.apply_label_font(qq, false, UiLayout.font_size(14, self))
	box.add_child(qq)

	var qr := TextureRect.new()
	qr.custom_minimum_size = Vector2(UiLayout.px(140, self), UiLayout.px(140, self))
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var qr_tex := UiAssets.qq_qr_texture()
	if qr_tex:
		qr.texture = qr_tex
	box.add_child(qr)

	var credits := Label.new()
	credits.text = CREDITS_TEXT
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(credits, false, UiLayout.font_size(12, self))
	box.add_child(credits)
	return panel

func _modal_panel(p_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = p_name
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	sb.border_color = Color(0.75, 0.65, 0.35, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	var m := UiLayout.margin_px(16, self)
	margin.add_theme_constant_override("margin_left", m)
	margin.add_theme_constant_override("margin_right", m)
	margin.add_theme_constant_override("margin_top", m)
	margin.add_theme_constant_override("margin_bottom", m)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	margin.add_child(box)
	return panel

func _start_announce_cycle() -> void:
	if _announce_texs.size() <= 1:
		return
	var t := Timer.new()
	t.wait_time = 10.0
	t.autostart = true
	t.timeout.connect(func():
		_announce_i = (_announce_i + 1) % _announce_texs.size()
		if _announce:
			_announce.texture = _announce_texs[_announce_i]
	)
	add_child(t)

func _on_fps_changed(v: float) -> void:
	GameSession.target_fps = int(v)
	Engine.max_fps = GameSession.target_fps
	GameSession.save_settings()
	if _fps_lbl:
		_fps_lbl.text = str(GameSession.target_fps)

func _on_no_model_toggled(on: bool) -> void:
	GameSession.set_no_model_perf_mode(on)

func _on_camera_breathe_toggled(on: bool) -> void:
	GameSession.set_camera_breathe_enabled(on)

func _on_nullsec_open() -> void:
	_nullsec_lobby.popup_centered(Vector2(720, 420))

func _ensure_nullsec_net() -> NullsecNetSession:
	if GameSession:
		var existing := GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession
		if existing:
			_nullsec_net = existing
			return _nullsec_net
	if _nullsec_net == null or not is_instance_valid(_nullsec_net):
		_nullsec_net = NullsecNetSession.new()
		_nullsec_net.name = "NullsecNetSession"
		add_child(_nullsec_net)
		_nullsec_net.rejected.connect(func(r: String):
			if _nullsec_lobby:
				_nullsec_lobby.set_status(r)
		)
		_nullsec_net.ships_mismatch.connect(func(_h: String):
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
	if _nullsec_net:
		_nullsec_net.close()
	if _nullsec_room:
		_nullsec_room.queue_free()
		_nullsec_room = null

func _on_nullsec_start_match(assignments: Dictionary) -> void:
	var net := _ensure_nullsec_net()
	net.persist_across_scenes()
	var spectate := net.local_is_spectator()
	GameSession.pending_mode = "nullsec"
	GameSession.pending_nullsec = {
		"assignments": assignments,
		"seats": net.seats,
		"local_seat": net.local_seat,
		"match_seed": int(net.last_match_payload.get("match_seed", Time.get_unix_time_from_system())),
		"spectator": spectate,
		"spectate_reason": "seat_spectate" if spectate else "",
	}
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _enter_nullsec_from_mid_join(net: NullsecNetSession, payload: Dictionary) -> void:
	net.persist_across_scenes()
	var asg: Dictionary = payload.get("assignments", {}) as Dictionary
	if asg.is_empty():
		var rng := MatchRng.new()
		rng.configure(int(payload.get("match_seed", 1)), str(payload.get("rules_hash", "")))
		var dir := NullsecMatchDirector.new()
		dir.setup(rng)
		dir.set_seats(payload.get("seats", []) as Array)
		asg = dir.assign_regions()
	GameSession.pending_mode = "nullsec"
	GameSession.pending_nullsec = {
		"assignments": asg,
		"seats": payload.get("seats", net.seats),
		"local_seat": net.local_seat,
		"match_seed": int(payload.get("match_seed", Time.get_unix_time_from_system())),
		"spectator": true,
		"spectate_reason": "mid_join",
	}
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_nullsec_match_public() -> void:
	var nick := _nullsec_lobby.current_nick()
	var ignore_started := _nullsec_lobby.ignore_in_match_rooms()
	_nullsec_lobby.set_status("正在扫描局域网…")
	var rules := MatchRng.compute_rules_hash()
	var rooms: Array = await LanBeacon.discover(self, LanBeacon.DISCOVER_WAIT_S)
	var pick: Dictionary = PublicRoomEnumerator.pick_public_room(rooms, rules, ignore_started)
	if pick.is_empty():
		if ignore_started:
			var skipped := PublicRoomEnumerator.count_in_match_public(rooms, rules)
			_nullsec_lobby.set_status("未发现未开局公开房 · 已略过 %d 间已开局" % skipped)
		else:
			_nullsec_lobby.set_status("未发现公开房（同版本）· 可点「主持公开房间」开一间")
		return
	var code := int(pick.get("code", 0))
	var ip := str(pick.get("ip", "127.0.0.1"))
	var port := int(pick.get("port", NullsecNetSession.port_for_code(code)))
	var in_match_ad := bool(pick.get("in_match", false))
	var net := _ensure_nullsec_net()
	net.close()
	_nullsec_lobby.set_status("正在加入公开房 %04d…" % code)
	var err := net.join(ip, port, nick, rules)
	if err != OK:
		_nullsec_lobby.set_status("加入失败: %s" % error_string(err))
		return
	var join_res: Dictionary = await _await_nullsec_join_ex(net, 4.0)
	if not bool(join_res.get("ok", false)):
		net.close()
		_nullsec_lobby.set_status("加入超时或被拒")
		return
	PublicRoomEnumerator.advance_past(code)
	var joined_in_match := bool(join_res.get("in_match", false)) or in_match_ad or net.match_started
	if joined_in_match:
		_nullsec_lobby.set_status("已加入公开房 %04d · 观战" % code)
		if net.last_match_payload.is_empty():
			var got := {"p": {}}
			var on_ms := func(p: Dictionary): got["p"] = p
			net.match_start.connect(on_ms)
			var end_ms := Time.get_ticks_msec() + 2000
			while Time.get_ticks_msec() < end_ms and net.last_match_payload.is_empty() and (got["p"] as Dictionary).is_empty():
				await get_tree().process_frame
			if net.match_start.is_connected(on_ms):
				net.match_start.disconnect(on_ms)
			if not (got["p"] as Dictionary).is_empty():
				net.last_match_payload = (got["p"] as Dictionary).duplicate(true)
		_enter_nullsec_from_mid_join(net, net.last_match_payload)
		return
	_nullsec_lobby.set_status("已加入公开房 %04d" % code)
	_show_nullsec_room()

func _on_nullsec_host_public() -> void:
	var nick := _nullsec_lobby.current_nick()
	_nullsec_lobby.set_status("正在选定空闲房号…")
	var rooms: Array = await LanBeacon.discover(self, 0.25)
	var taken: Dictionary = {}
	for r in rooms:
		if typeof(r) == TYPE_DICTIONARY and not bool((r as Dictionary).get("private", false)):
			taken[int((r as Dictionary).get("code", 0))] = true
	var code := PublicRoomEnumerator.claim_free_code(taken)
	var net := _ensure_nullsec_net()
	net.close()
	var err := net.host_public(code, nick)
	if err != OK:
		_nullsec_lobby.set_status("开房失败: %s" % error_string(err))
		return
	_nullsec_lobby.set_status("已主持公开房 %04d（局域网）" % code)
	_show_nullsec_room()

func _on_nullsec_host_private() -> void:
	var nick := _nullsec_lobby.current_nick()
	## 6-char base32-ish private code (0-9a-v), SEMI_ASYNC §7.5.
	var alphabet := "0123456789abcdefghijklmnopqrstuv"
	var code := ""
	for _i in range(6):
		code += alphabet[randi() % alphabet.length()]
	var net := _ensure_nullsec_net()
	net.close()
	var err := net.host_private(code, nick)
	if err != OK:
		_nullsec_lobby.set_status("开房失败: %s" % error_string(err))
		return
	_nullsec_lobby.set_status("已主持私密房 %s（局域网）" % code)
	_show_nullsec_room()

func _on_nullsec_join_private(raw: String) -> void:
	var nick := _nullsec_lobby.current_nick()
	var code := raw.strip_edges().to_lower()
	if code == "":
		_nullsec_lobby.set_status("请输入私密码")
		return
	var re := RegEx.new()
	re.compile("^[0-9a-v]{6}$")
	if re.search(code) == null:
		_nullsec_lobby.set_status("私密码须为 6 位 0-9a-v")
		return
	_nullsec_lobby.set_status("正在扫描局域网…")
	var rules := MatchRng.compute_rules_hash()
	var rooms: Array = await LanBeacon.discover(self, LanBeacon.DISCOVER_WAIT_S)
	var pick: Dictionary = {}
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if not bool(d.get("private", false)):
			continue
		if str(d.get("private_code", "")).to_lower() != code:
			continue
		if str(d.get("rules", "")) != rules:
			continue
		pick = d
		break
	if pick.is_empty():
		_nullsec_lobby.set_status("未找到该私密房（同版本 · 局域网）")
		return
	var ip := str(pick.get("ip", "127.0.0.1"))
	var port := int(pick.get("port", NullsecNetSession.port_for_code(NullsecNetSession.code_for_private(code))))
	var net := _ensure_nullsec_net()
	net.close()
	_nullsec_lobby.set_status("正在加入私密房…")
	var err := net.join(ip, port, nick, rules)
	if err != OK:
		_nullsec_lobby.set_status("加入失败: %s" % error_string(err))
		return
	var ok := await _await_nullsec_join(net, 4.0)
	if not ok:
		net.close()
		_nullsec_lobby.set_status("加入超时或被拒")
		return
	if net.match_started or net.local_is_spectator():
		_nullsec_lobby.set_status("已加入私密房 %s · 观战" % code)
		if net.last_match_payload.is_empty():
			var got := {"p": {}}
			var on_ms := func(p: Dictionary): got["p"] = p
			net.match_start.connect(on_ms)
			var end_ms := Time.get_ticks_msec() + 2000
			while Time.get_ticks_msec() < end_ms and net.last_match_payload.is_empty() and (got["p"] as Dictionary).is_empty():
				await get_tree().process_frame
			if net.match_start.is_connected(on_ms):
				net.match_start.disconnect(on_ms)
			if not (got["p"] as Dictionary).is_empty():
				net.last_match_payload = (got["p"] as Dictionary).duplicate(true)
		_enter_nullsec_from_mid_join(net, net.last_match_payload)
		return
	_nullsec_lobby.set_status("已加入私密房 %s" % code)
	_show_nullsec_room()

func _await_nullsec_join(net: NullsecNetSession, timeout_s: float) -> bool:
	var res: Dictionary = await _await_nullsec_join_ex(net, timeout_s)
	return bool(res.get("ok", false))

func _await_nullsec_join_ex(net: NullsecNetSession, timeout_s: float) -> Dictionary:
	if net == null:
		return {"ok": false, "in_match": false}
	if net.local_seat >= 0:
		return {"ok": true, "in_match": net.match_started}
	var done := {"ok": false, "fail": false, "in_match": false}
	var on_ok := func(_seat: int, in_match: bool = false):
		done["ok"] = true
		done["in_match"] = in_match
	var on_fail := func(_r: String): done["fail"] = true
	net.join_accepted.connect(on_ok)
	net.rejected.connect(on_fail)
	var end_ms := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if bool(done["ok"]) or net.local_seat >= 0:
			net.join_accepted.disconnect(on_ok)
			net.rejected.disconnect(on_fail)
			return {"ok": true, "in_match": bool(done["in_match"]) or net.match_started}
		if bool(done["fail"]):
			net.join_accepted.disconnect(on_ok)
			net.rejected.disconnect(on_fail)
			return {"ok": false, "in_match": false}
		await get_tree().process_frame
	if net.join_accepted.is_connected(on_ok):
		net.join_accepted.disconnect(on_ok)
	if net.rejected.is_connected(on_fail):
		net.rejected.disconnect(on_fail)
	return {"ok": net.local_seat >= 0, "in_match": net.match_started}

func _on_nullsec_history() -> void:
	var path := "user://save/nullsec_history.json"
	if not FileAccess.file_exists(path):
		_nullsec_lobby.set_status("尚无历史战绩")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).is_empty():
		_nullsec_lobby.set_status("尚无历史战绩")
		return
	var last: Dictionary = (parsed as Array).back()
	var rows: Array = last.get("rows", []) as Array
	var panel := NullsecSettlementPanel.new()
	add_child(panel)
	panel.title = "多人联机历史战绩"
	panel.show_rows(rows, false)

func _on_versus() -> void:
	GameSession.resume_save = false
	GameSession.resume_slot_id = ""
	GameSession.resume_payload = {}
	GameSession.pending_mode = "versus"
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_endless() -> void:
	GameSession.resume_save = false
	GameSession.resume_slot_id = ""
	GameSession.resume_payload = {}
	GameSession.pending_mode = "endless"
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_continue() -> void:
	if not MatchSave.exists():
		return
	GameSession.resume_save = true
	GameSession.resume_slot_id = ""
	GameSession.resume_payload = {}
	var d := MatchSave.load_dict()
	var mode := str(d.get("mode", "versus"))
	if mode == "nullsec":
		## Stale multiplayer snapshot from before §5.0b — nothing to resume into.
		GameSession.resume_save = false
		MatchSave.clear()
		_disable_continue_btn()
		return
	GameSession.pending_mode = mode
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_load_open() -> void:
	if _load_panel == null:
		return
	_refresh_load_list()
	_apply_adaptive_layout()
	_load_panel.visible = true

func _build_load_panel() -> Control:
	var panel := _modal_panel("LoadSavePanel")
	var box := panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "读取存档"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(24, self))
	cap_row.add_child(cap)
	var close_x := Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func(): panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)
	var scroll := ScrollContainer.new()
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
	for c in _load_list.get_children():
		c.queue_free()
	var slots := MatchSave.list_slots()
	if slots.is_empty() and MatchSave.exists():
		slots = [{
			"id": MatchSave.FLAGSHIP_TEST_ID,
			"name": MatchSave.FLAGSHIP_TEST_NAME,
			"path": MatchSave.FLAGSHIP_TEST_PATH if FileAccess.file_exists(MatchSave.FLAGSHIP_TEST_PATH) else MatchSave.SAVE_PATH,
			"updated_at": "",
		}]
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "暂无存档"
		UiAssets.apply_label_font(empty, false, UiLayout.font_size(16, self))
		_load_list.add_child(empty)
		return
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = s
		var sid := str(entry.get("id", ""))
		var name := str(entry.get("name", sid))
		var updated := str(entry.get("updated_at", ""))
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", UiLayout.margin_px(8, self))
		var load_btn := Button.new()
		load_btn.text = name if updated == "" else "%s\n%s" % [name, updated]
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.custom_minimum_size = Vector2(0, UiLayout.px(52, self))
		load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiAssets.apply_button_font(load_btn, UiLayout.font_size(15, self))
		load_btn.pressed.connect(_on_load_slot.bind(sid))
		row.add_child(load_btn)
		var rename_btn := Button.new()
		rename_btn.text = "重命名"
		rename_btn.custom_minimum_size = Vector2(UiLayout.px(72, self), UiLayout.px(52, self))
		UiAssets.apply_button_font(rename_btn, UiLayout.font_size(14, self))
		rename_btn.pressed.connect(_on_rename_open.bind(sid, name))
		row.add_child(rename_btn)
		var del_btn := Button.new()
		del_btn.text = "删除"
		del_btn.custom_minimum_size = Vector2(UiLayout.px(64, self), UiLayout.px(52, self))
		UiAssets.apply_button_font(del_btn, UiLayout.font_size(14, self))
		del_btn.pressed.connect(_on_delete_slot.bind(sid, name))
		row.add_child(del_btn)
		_load_list.add_child(row)


func _build_rename_panel() -> Control:
	var panel := _modal_panel("RenameSavePanel")
	var box := panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "重命名存档"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var close_x := Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(UiLayout.px(36, self), UiLayout.px(36, self))
	UiAssets.apply_button_font(close_x, UiLayout.font_size(18, self))
	close_x.pressed.connect(func(): panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)
	_rename_edit = LineEdit.new()
	_rename_edit.placeholder_text = "存档名称"
	_rename_edit.add_theme_font_size_override("font_size", UiLayout.font_size(16, self))
	box.add_child(_rename_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_button_font(cancel, UiLayout.font_size(16, self))
	cancel.pressed.connect(func(): panel.visible = false)
	row.add_child(cancel)
	var ok := Button.new()
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
	var name := _rename_edit.text if _rename_edit else ""
	var r := MatchSave.rename_slot(_rename_slot_id, name)
	if _rename_panel:
		_rename_panel.visible = false
	if bool(r.get("ok", false)):
		_refresh_load_list()
	_rename_slot_id = ""


func _on_delete_slot(slot_id: String, display_name: String) -> void:
	## Inline confirm: second press not needed — use a small confirm panel via rename-style, or AcceptDialog.
	var dlg := ConfirmationDialog.new()
	dlg.title = "删除存档"
	dlg.dialog_text = "确定删除「%s」？此操作不可恢复。" % display_name
	dlg.ok_button_text = "删除"
	dlg.cancel_button_text = "取消"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dlg)
	dlg.confirmed.connect(func():
		var r := MatchSave.delete_slot(slot_id)
		if bool(r.get("ok", false)):
			_refresh_load_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.popup_centered()


func _disable_continue_btn() -> void:
	if _btn_box == null:
		return
	for c in _btn_box.get_children():
		var b := c as Button
		if b and b.text == "继续上次对局":
			b.disabled = true
			return


func _on_load_slot(slot_id: String) -> void:
	var d := MatchSave.load_slot_dict(slot_id)
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
	GameSession.pending_mode = str(d.get("mode", "versus"))
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_bgm_toggled(on: bool) -> void:
	var bgm := _BgMusic.instance()
	if bgm:
		bgm.set_enabled(on)

func _on_bgm_volume_changed(v: float) -> void:
	if _bgm_lbl:
		_bgm_lbl.text = str(int(v))
	var bgm := _BgMusic.instance()
	if bgm:
		bgm.set_volume_pct(v)

func _on_options_open() -> void:
	if _options:
		_apply_adaptive_layout()
		_options.visible = true
		if _fps_slider:
			_fps_slider.value = GameSession.target_fps
		var bgm := _BgMusic.instance()
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
	var master_on := GameSession.developer_debug_enabled
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


func _on_ship_data_editor_closed(changed_ids: Array, equipment_changed: bool = false) -> void:
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
