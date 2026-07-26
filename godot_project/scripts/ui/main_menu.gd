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
var _fps_slider: HSlider
var _fps_lbl: Label
var _bgm_check: CheckBox
var _bgm_slider: HSlider
var _bgm_lbl: Label
var _announce: TextureRect
var _announce_texs: Array[Texture2D] = []
var _announce_i: int = 0
var _col: Control
var _title: Label
var _btn_box: VBoxContainer
var _footer: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_BgMusic.instance()
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
	_announce_texs = UiAssets.announcement_textures()
	if _announce_texs.size() > 0:
		_announce.texture = _announce_texs[0]
	add_child(_announce)

	_options = _build_options()
	add_child(_options)
	_about = _build_about()
	add_child(_about)

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
		UiLayout.set_center_panel_frac(_options, 0.78 if UiLayout.is_mobile() else 0.72, 0.62 if UiLayout.is_mobile() else 0.58)
	if _about:
		UiLayout.set_center_panel_frac(_about, 0.7 if UiLayout.is_mobile() else 0.42, 0.82 if UiLayout.is_mobile() else 0.78)

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
	_bgm_check.button_pressed = bgm.enabled if bgm else true
	UiAssets.apply_button_font(_bgm_check, UiLayout.font_size(16, self))
	_bgm_check.toggled.connect(_on_bgm_toggled)
	bgm_on_row.add_child(_bgm_check)
	box.add_child(bgm_on_row)

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
	if _fps_lbl:
		_fps_lbl.text = str(GameSession.target_fps)

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

func _on_versus() -> void:
	GameSession.pending_mode = "versus"
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_endless() -> void:
	GameSession.pending_mode = "endless"
	get_tree().change_scene_to_file("res://scenes/match.tscn")

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

func _on_about_open() -> void:
	if _about:
		_apply_adaptive_layout()
		_about.visible = true

func _on_quit() -> void:
	get_tree().quit()
