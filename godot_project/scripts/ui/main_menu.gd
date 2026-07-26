extends Control
## StartScene MainCanvas — menu column flush LEFT (用户验收：贴左侧).

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
var _announce: TextureRect
var _announce_texs: Array[Texture2D] = []
var _announce_i: int = 0

func _ready() -> void:
	_build()
	Engine.max_fps = int(GameSession.target_fps)
	_start_announce_cycle()

func _build() -> void:
	var base := ColorRect.new()
	base.name = "BaseFill"
	UiAssets.full_rect(base)
	base.color = Color(0.04, 0.05, 0.08, 1)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# Full-bleed BG — no full-screen dim (原版无整屏压暗)
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

	# Menu column flush to left edge
	var col := Control.new()
	col.name = "Left"
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.anchor_right = 0.42
	col.offset_left = 0
	col.offset_right = 0
	add_child(col)

	# Title — top-left
	var title := Label.new()
	title.name = "Title"
	title.text = TITLE_TEXT
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 72
	title.offset_top = 48
	title.offset_right = 520
	title.offset_bottom = 110
	UiAssets.apply_label_font(title, true, 36)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 6)
	col.add_child(title)

	# Button stack — left, ~200×60
	var btn_box := VBoxContainer.new()
	btn_box.name = "Buttons"
	btn_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	btn_box.anchor_left = 0.0
	btn_box.anchor_top = 0.5
	btn_box.anchor_right = 0.0
	btn_box.anchor_bottom = 0.5
	btn_box.offset_left = 72
	btn_box.offset_top = -280
	btn_box.offset_right = 292
	btn_box.offset_bottom = 280
	btn_box.add_theme_constant_override("separation", 40)
	col.add_child(btn_box)

	btn_box.add_child(_menu_btn("开始无尽模式", _on_endless))
	btn_box.add_child(_menu_btn("开始对战模式", _on_versus))
	btn_box.add_child(_menu_btn("选项", _on_options_open))
	btn_box.add_child(_menu_btn("退出游戏", _on_quit))
	btn_box.add_child(_menu_btn("关于我们", _on_about_open))

	# Declare + Version — bottom of left column
	var footer := VBoxContainer.new()
	footer.name = "Right"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 48
	footer.offset_top = -120
	footer.offset_right = -24
	footer.offset_bottom = -28
	footer.add_theme_constant_override("separation", 6)
	col.add_child(footer)

	var declare := Label.new()
	declare.name = "Declare"
	declare.text = DECLARE_TEXT
	declare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(declare, false, 13)
	declare.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 0.95))
	declare.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	declare.add_theme_constant_override("outline_size", 3)
	footer.add_child(declare)

	var ver := Label.new()
	ver.name = "VersionLabel"
	ver.text = "游戏版本:%s | 内容 %s" % [GameSession.shell_version, DataStore.content_version]
	UiAssets.apply_label_font(ver, false, 15)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	ver.add_theme_constant_override("outline_size", 3)
	footer.add_child(ver)

	# Announcements — bottom-right ~600×211 (scale to 1080p)
	_announce = TextureRect.new()
	_announce.name = "Announcements"
	_announce.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_announce.anchor_left = 1.0
	_announce.anchor_top = 1.0
	_announce.anchor_right = 1.0
	_announce.anchor_bottom = 1.0
	_announce.offset_left = -620
	_announce.offset_top = -420
	_announce.offset_right = -40
	_announce.offset_bottom = -180
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

func _menu_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiAssets.apply_button_font(b, 22)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.75, 0.4, 1))
	# Flat dark plate like default uGUI
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
	var panel := _modal_panel("OptionsPanel", Vector2(1520, 680))
	var box := panel.get_node("Margin/VBox") as VBoxContainer

	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "选项菜单"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, 28)
	cap_row.add_child(cap)
	var close_x := Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(40, 40)
	UiAssets.apply_button_font(close_x, 20)
	close_x.pressed.connect(func(): panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var fps_cap := Label.new()
	fps_cap.text = "FPS限制"
	UiAssets.apply_label_font(fps_cap, false, 18)
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
	_fps_lbl.custom_minimum_size = Vector2(48, 0)
	_fps_lbl.text = str(int(GameSession.target_fps))
	UiAssets.apply_label_font(_fps_lbl, false, 18)
	row.add_child(_fps_lbl)
	box.add_child(row)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 12)
	var lang_l := Label.new()
	lang_l.text = "语言"
	UiAssets.apply_label_font(lang_l, false, 18)
	lang_row.add_child(lang_l)
	var lang := OptionButton.new()
	lang.add_item("中文", 0)
	lang.add_item("English", 1)
	lang_row.add_child(lang)
	box.add_child(lang_row)
	return panel

func _build_about() -> Control:
	var panel := _modal_panel("AboutUsPanel", Vector2(800, 840))
	var box := panel.get_node("Margin/VBox") as VBoxContainer

	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "关于我们"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, 28)
	cap_row.add_child(cap)
	var close_x := Button.new()
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(40, 40)
	UiAssets.apply_button_font(close_x, 20)
	close_x.pressed.connect(func(): panel.visible = false)
	cap_row.add_child(close_x)
	box.add_child(cap_row)

	var bili := Button.new()
	bili.text = "我们的B站主页(点击进入)\n%s" % BILIBILI_URL
	bili.custom_minimum_size = Vector2(0, 64)
	UiAssets.apply_button_font(bili, 16)
	bili.pressed.connect(func(): OS.shell_open(BILIBILI_URL))
	box.add_child(bili)

	var qq := Label.new()
	qq.text = "欢迎加入我们的QQ群关注最新进展"
	UiAssets.apply_label_font(qq, false, 16)
	box.add_child(qq)

	var qr := TextureRect.new()
	qr.custom_minimum_size = Vector2(180, 180)
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var qr_tex := UiAssets.qq_qr_texture()
	if qr_tex:
		qr.texture = qr_tex
	box.add_child(qr)

	var credits := Label.new()
	credits.text = CREDITS_TEXT
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(credits, false, 14)
	box.add_child(credits)
	return panel

func _modal_panel(p_name: String, panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = p_name
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_bottom = panel_size.y * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	sb.border_color = Color(0.75, 0.65, 0.35, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
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

func _on_versus() -> void:
	GameSession.pending_mode = "versus"
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_endless() -> void:
	GameSession.pending_mode = "endless"
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_options_open() -> void:
	if _options:
		_options.visible = true
		if _fps_slider:
			_fps_slider.value = GameSession.target_fps

func _on_about_open() -> void:
	if _about:
		_about.visible = true

func _on_quit() -> void:
	get_tree().quit()
