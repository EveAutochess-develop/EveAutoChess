extends Control
## StartScene — left menu column; sizes relative to viewport (UiLayout).
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

# preload: class_name may be missing from shell global cache after load_resource_pack
const _BgMusic: Script = preload("res://scripts/audio/bg_music.gd")
const _ParaBtn: Script = preload("res://scripts/ui/menu_parallelogram_button.gd")
const _BranchReveal: Script = preload("res://scripts/ui/menu_branch_reveal.gd")
const _LobbyPanel: Script = preload("res://scripts/ui/nullsec_lobby_panel.gd")

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
var _sfx_check: CheckBox
var _sfx_slider: HSlider
var _sfx_lbl: Label
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
var _nullsec_lobby: Control
var _nullsec_room: NullsecRoomUI
var _nullsec_net: NullsecNetSession
## Silent match gate: ignore spam clicks while a scan/try-join is in flight (no UI hint).
var _nullsec_match_busy: bool = false
## Continue-last: invalidate in-flight remote rejoin when user cancels / picks local.
var _continue_rejoin_gen: int = 0
var _continue_search_dlg: ConfirmationDialog = null

## Main-menu accordion (UI_AND_SHELL §1): 开始游戏 / 选项.
const BRANCH_PLAY: String = "play"
const BRANCH_SOLO: String = "solo"
const BRANCH_ONLINE: String = "online"
const BRANCH_OPTIONS: String = "options"
var _branch_open: String = ""
var _play_mode_open: String = ""
var _branch_reveal: RefCounted = _BranchReveal.new() as RefCounted
var _play_mode_reveal: RefCounted = _BranchReveal.new() as RefCounted
var _tertiary_reveal: RefCounted = _BranchReveal.new() as RefCounted
var _primary_btns: Dictionary = {} ## id -> Button (L1 + 开始游戏内单机/联机)
var _secondary_hosts: Dictionary = {} ## id -> Control
var _branch_rows: Dictionary = {} ## id -> Control (fixed L1 height; secondary overlays)
var _btn_continue: Button
var _btn_load: Button
var _play_root: Control
var _solo_host: Control
var _online_host: Control
var _online_chrome: Control
var _options_host: Control
var _play_host: Control
var _load_tertiary_host: Control
var _load_tertiary_open: bool = false
var _history_tertiary_host: Control
var _history_list: VBoxContainer
var _history_tertiary_open: bool = false
var _btn_history: Button
var _history_reveal: RefCounted = _BranchReveal.new() as RefCounted
## 1.0 = design pixels; shrink only when tertiary chain would leave the viewport.
var _menu_fit_scale: float = 1.0
## Semi-transparent gold plate — same family as menu_parallelogram_button gold.
const _SECONDARY_BG := Color(0.48, 0.34, 0.10, 0.42)
const _SECONDARY_BORDER := Color(0.92, 0.82, 0.45, 0.40)

func _menu_design_bw() -> float:
	return 160.0 if UiLayout.is_mobile() else 200.0

func _menu_design_bh() -> float:
	return 48.0 if UiLayout.is_mobile() else 56.0

func _menu_design_host_w() -> float:
	return 280.0 if UiLayout.is_mobile() else 360.0

func _menu_design_tertiary_w() -> float:
	return 420.0 if UiLayout.is_mobile() else 520.0

func _menu_design_tertiary_h() -> float:
	return 420.0 if UiLayout.is_mobile() else 520.0

func _menu_design_gap() -> float:
	return 100.0

func _menu_design_l1_sep() -> float:
	return 14.0 if UiLayout.is_mobile() else 20.0

func _menu_design_font() -> int:
	return 18 if UiLayout.is_mobile() else 22

func _menu_px(design: float) -> float:
	return design * _menu_fit_scale

func _menu_font_px(design: int) -> int:
	return maxi(10, roundi(float(design) * _menu_fit_scale))

func _compute_menu_fit_scale() -> float:
	## Fixed design pixels unless 读取存档 tertiary chain clips the viewport (UI_AND_SHELL §1).
	var vp: Vector2 = UiLayout.viewport_size(self)
	var edge: float = 8.0
	var bw: float = _menu_design_bw()
	var bh: float = _menu_design_bh()
	var host_w: float = _menu_design_host_w()
	var tw: float = _menu_design_tertiary_w()
	var th: float = _menu_design_tertiary_h()
	var gap: float = _menu_design_gap()
	var sep: float = 8.0
	var pad: float = 0.035 if UiLayout.is_mobile() else 0.038
	var origin_x: float = vp.x * pad
	var origin_y: float = vp.y * 0.16
	if _btn_box != null and is_instance_valid(_btn_box) and _btn_box.is_inside_tree():
		var g: Vector2 = _btn_box.global_position
		if g.x > 1.0:
			origin_x = g.x
		if g.y > 1.0:
			origin_y = g.y
	## L1 chain: 开始游戏 + 单机钮 + 单机列 + 读档板.
	var chain_w: float = bw + gap + bw + gap + host_w + gap + tw
	var s: float = 1.0
	var budget_w: float = maxf(vp.x - edge - origin_x, 1.0)
	if chain_w > budget_w:
		s = minf(s, budget_w / chain_w)
	## 单机列第 4 钮为读档；再加一行「单机模式」在开始游戏二级内。
	var load_y_off: float = bh + sep + 3.0 * (bh + sep)
	var chain_h: float = load_y_off + th
	var budget_h: float = maxf(vp.y - edge - origin_y, 1.0)
	if chain_h > budget_h:
		s = minf(s, budget_h / chain_h)
	return clampf(s, 0.55, 1.0)

func _relayout_solo_branch_link() -> void:
	## 读档/历史滑钮：重铺「开始游戏→模式」与「模式→列」既有连线。
	if _play_mode_reveal != null and _play_mode_reveal.has_method("relayout_open_link"):
		_play_mode_reveal.call("relayout_open_link")
	if _branch_reveal != null and _branch_reveal.has_method("relayout_open_link"):
		_branch_reveal.call("relayout_open_link")

func _on_play_mode_slide_step() -> void:
	## 单机/联机右滑：拉长「开始游戏→该模式」白线。
	if _branch_reveal != null and _branch_reveal.has_method("relayout_open_link"):
		_branch_reveal.call("relayout_open_link")

func _on_history_slide_step() -> void:
	## 竖支线 X 锚未滑位；末段水平随滑拉长贴钮 — 须重铺一级→联机 mindmap。
	_relayout_solo_branch_link()
	if _history_tertiary_open:
		_layout_history_tertiary()
	if _history_reveal != null and _history_reveal.has_method("relayout_open_link"):
		_history_reveal.call("relayout_open_link")

func _on_history_reveal_finished() -> void:
	## Wipe restore can leave chrome short — force full plate size again.
	if _history_tertiary_open:
		_layout_history_tertiary()
		if _history_reveal != null and _history_reveal.has_method("relayout_open_link"):
			_history_reveal.call("relayout_open_link")

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
	## L1「开始游戏」→单机/联机 mindmap；模式内读档/历史滑钮重铺上级连线。
	(_tertiary_reveal as Object).set("on_slide_step", Callable(self, "_relayout_solo_branch_link"))
	(_history_reveal as Object).set("on_slide_step", Callable(self, "_on_history_slide_step"))
	(_history_reveal as Object).set("on_finished", Callable(self, "_on_history_reveal_finished"))
	(_play_mode_reveal as Object).set("on_slide_step", Callable(self, "_on_play_mode_slide_step"))
	_build()
	_apply_adaptive_layout()
	resized.connect(_apply_adaptive_layout)
	Engine.max_fps = int((PlayerSettings.instance() as PlayerSettings).target_fps)
	_start_announce_cycle()
	SessionDiagnostics.log(
		"boot.ready",
		"shell=%s content=%s nomodel=%d fps_cap=%d breathe=%d soften=%d" % [
			GameSession.shell_version,
			DataStore.content_version,
			1 if (PlayerSettings.instance() as PlayerSettings).no_model_perf_mode else 0,
			int((PlayerSettings.instance() as PlayerSettings).target_fps),
			1 if (PlayerSettings.instance() as PlayerSettings).camera_breathe_enabled else 0,
			1 if (PlayerSettings.instance() as PlayerSettings).player_citadel_soften else 0,
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
	_col.clip_contents = false
	## Keep L1 above centered modals so primaries stay clickable (UI_AND_SHELL §1.0).
	_col.z_index = 40
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
	_btn_box.clip_contents = false
	## Rows own hits; empty VBox must not steal from overflowing secondary hosts.
	_btn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(_btn_box)

	_nullsec_lobby = _LobbyPanel.new() as Control
	(_nullsec_lobby as Object).connect("request_match_public", _on_nullsec_match_public)
	(_nullsec_lobby as Object).connect("request_host_room", _on_nullsec_host_room)
	(_nullsec_lobby as Object).connect("request_join_share", _on_nullsec_join_share)
	(_nullsec_lobby as Object).connect("request_restore_room", _on_restore_room)

	_add_branch_row(BRANCH_PLAY, "开始游戏", _build_play_secondary)
	_add_branch_row(BRANCH_OPTIONS, "选项", _build_options_secondary)

	_footer = VBoxContainer.new()
	_footer.name = "Right"
	## Footer frac (0.82–0.98) overlaps Buttons (…–0.88). Must IGNORE so 联机二级底钮
	## (恢复房间 / 历史战绩) stay fully clickable under the声明/版本文字.
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(_footer)

	var declare: Label = Label.new()
	declare.name = "Declare"
	declare.text = DECLARE_TEXT
	declare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	declare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	declare.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	declare.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_footer.add_child(declare)

	var ver: Label = Label.new()
	ver.name = "VersionLabel"
	## UI_AND_SHELL §1：玩家可见只显示内容热更版。
	ver.text = "游戏版本:%s" % DataStore.content_version
	ver.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	## Load list is tertiary under 单机; keep rename panel only.
	_rename_panel = _build_rename_panel()
	add_child(_rename_panel)

func _add_branch_row(id: String, primary_text: String, build_secondary: Callable, attach_to: Control = null) -> void:
	## Plain Control row: L1 height only — secondary overlays beside without shifting peers.
	## attach_to: nest under 开始游戏二级；null → `_btn_box` 一级行.
	var row: Control = Control.new()
	row.name = "Branch_%s" % id
	row.clip_contents = false
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if attach_to != null:
		attach_to.add_child(row)
	else:
		_btn_box.add_child(row)
	_branch_rows[id] = row
	var primary_slot: Control = Control.new()
	primary_slot.name = "PrimarySlot_%s" % id
	primary_slot.custom_minimum_size = Vector2(160, 48)
	primary_slot.position = Vector2.ZERO
	primary_slot.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(primary_slot)
	var is_play_mode: bool = id == BRANCH_SOLO or id == BRANCH_ONLINE
	var primary: Button = _menu_btn(primary_text, func():
		if is_play_mode:
			_toggle_play_mode(id)
		else:
			_toggle_branch(id)
	)
	primary.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	primary.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	primary.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	primary_slot.add_child(primary)
	_primary_btns[id] = primary
	var host: Control = Control.new()
	host.name = "Secondary_%s" % id
	host.visible = false
	host.clip_contents = true
	## Above footer / later L1 rows when secondary overflows fixed L1 row height.
	host.z_index = 10
	host.z_as_relative = false
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.custom_minimum_size = Vector2(180, 48)
	row.add_child(host)
	_secondary_hosts[id] = host
	var content_v: Variant = build_secondary.call()
	var content: Control = content_v as Control
	if content:
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(content)
	match id:
		BRANCH_PLAY:
			_play_host = host
			host.clip_contents = false
		BRANCH_SOLO:
			_solo_host = host
			## Tertiary load can extend past secondary bounds.
			host.clip_contents = false
		BRANCH_ONLINE:
			_online_host = host
			host.clip_contents = false
			_setup_history_tertiary()
		BRANCH_OPTIONS:
			_options_host = host

func _build_play_secondary() -> Control:
	## 开始游戏二级：单机/联机整树（UI_AND_SHELL §1.0）。
	var root: Control = Control.new()
	root.name = "PlaySecondaryRoot"
	root.clip_contents = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_root = root
	_add_branch_row(BRANCH_SOLO, "单机模式", _build_solo_secondary, root)
	_add_branch_row(BRANCH_ONLINE, "联机模式", _build_online_secondary, root)
	return root

func _make_secondary_chrome(content: Control) -> Control:
	## Axis-aligned semi-transparent gold rect — 联机二级 / 读取存档三级 / 历史战绩三级.
	var root: Control = Control.new()
	root.name = "SecondaryChrome"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg: Panel = Panel.new()
	bg.name = "RectBackdrop"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = _SECONDARY_BG
	sb.border_color = _SECONDARY_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)
	var pad: MarginContainer = MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: int = UiLayout.margin_px(10, self)
	pad.add_theme_constant_override("margin_left", m)
	pad.add_theme_constant_override("margin_right", m)
	pad.add_theme_constant_override("margin_top", m)
	pad.add_theme_constant_override("margin_bottom", m)
	root.add_child(pad)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(content)
	return root

func _build_solo_secondary() -> Control:
	var root: Control = Control.new()
	root.name = "SoloSecondaryRoot"
	root.clip_contents = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "SoloBtns"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	box.add_child(_menu_btn("开始无尽模式", _on_endless))
	box.add_child(_menu_btn("开始对战模式", _on_versus))
	_btn_continue = _menu_btn("继续上次对局", _on_continue)
	_btn_continue.disabled = not _usable_local_last_match_exists()
	box.add_child(_btn_continue)
	_btn_load = _menu_btn("读取存档", _on_load_open)
	_btn_load.disabled = MatchSave.list_slots().is_empty() and not MatchSave.exists()
	box.add_child(_btn_load)
	_load_tertiary_host = Control.new()
	_load_tertiary_host.name = "LoadTertiary"
	_load_tertiary_host.visible = false
	_load_tertiary_host.clip_contents = true
	_load_tertiary_host.z_index = 8
	_load_tertiary_host.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_load_tertiary_host)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "LoadScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_load_list = VBoxContainer.new()
	_load_list.name = "LoadList"
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list.add_theme_constant_override("separation", UiLayout.margin_px(6, self))
	scroll.add_child(_load_list)
	var list_chrome: Control = _make_secondary_chrome(scroll)
	list_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_tertiary_host.add_child(list_chrome)
	return root

func _build_online_secondary() -> Control:
	## Root: chrome(lobby) + 历史钮 outside plate (UI_AND_SHELL §1.0).
	var root: Control = Control.new()
	root.name = "OnlineSecondaryRoot"
	root.clip_contents = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_online_chrome = _make_secondary_chrome(_nullsec_lobby)
	_online_chrome.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_online_chrome.anchor_right = 0.0
	_online_chrome.anchor_bottom = 0.0
	root.add_child(_online_chrome)
	_btn_history = _menu_btn("多人联机历史战绩", _on_nullsec_history)
	_btn_history.name = "HistoryOutside"
	_btn_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_btn_history)
	return root

func _build_options_secondary() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_menu_btn("关于我们", _on_about_open))
	box.add_child(_menu_btn("游戏设置", _on_options_open))
	return box

func _usable_local_last_match_exists() -> bool:
	return not _usable_local_last_match().is_empty()

func _close_menu_modals() -> void:
	if _options:
		_options.visible = false
	if _about:
		_about.visible = false
	if _load_panel:
		_load_panel.visible = false
	if _rename_panel:
		_rename_panel.visible = false
	if _dev_panel:
		_dev_panel.visible = false
	## Transient AcceptDialog / ConfirmationDialog children (history, delete confirm).
	for c: Node in get_children():
		if c is AcceptDialog or c is ConfirmationDialog:
			(c as Window).hide()
			c.queue_free()

func _dismiss_branch_for_modal() -> void:
	_collapse_all_tertiaries()
	_collapse_all_secondaries()
	_branch_open = ""
	_play_mode_open = ""

func _toggle_branch(id: String) -> void:
	_close_menu_modals()
	_collapse_all_tertiaries()
	_branch_reveal.call("abort")
	_play_mode_reveal.call("abort")
	if _branch_open == id:
		_collapse_all_secondaries()
		_branch_open = ""
		_play_mode_open = ""
		return
	_collapse_all_secondaries()
	_branch_open = id
	_play_mode_open = ""
	var host: Control = _secondary_hosts.get(id) as Control
	var primary: Control = _primary_btns.get(id) as Control
	if host == null or primary == null:
		return
	host.visible = true
	_apply_branch_host_sizes()
	await get_tree().process_frame
	_apply_branch_host_sizes()
	_branch_reveal.call("play", get_tree(), primary, host, _SECONDARY_BG)

func _toggle_play_mode(id: String) -> void:
	## Nested under 开始游戏 — solo/online accordion (UI_AND_SHELL §1.0).
	if _branch_open != BRANCH_PLAY:
		return
	_close_menu_modals()
	_collapse_all_tertiaries()
	_play_mode_reveal.call("abort")
	if _play_mode_open == id:
		_collapse_play_mode_hosts()
		_play_mode_open = ""
		if _branch_reveal != null and _branch_reveal.has_method("relayout_open_link"):
			_branch_reveal.call("relayout_open_link")
		return
	_collapse_play_mode_hosts()
	_play_mode_open = id
	var host: Control = _secondary_hosts.get(id) as Control
	var primary: Control = _primary_btns.get(id) as Control
	if host == null or primary == null:
		return
	host.visible = true
	_apply_branch_host_sizes()
	await get_tree().process_frame
	_apply_branch_host_sizes()
	if id == BRANCH_ONLINE and _nullsec_lobby and _nullsec_lobby.has_method("refresh_restore_enabled"):
		_nullsec_lobby.call("refresh_restore_enabled")
	_play_mode_reveal.call("play", get_tree(), primary, host, _SECONDARY_BG)

func _collapse_play_mode_hosts() -> void:
	for mid: String in [BRANCH_SOLO, BRANCH_ONLINE]:
		var h: Control = _secondary_hosts.get(mid) as Control
		if h:
			h.visible = false
		var p: Control = _primary_btns.get(mid) as Control
		if p:
			p.modulate = Color.WHITE
			if p.has_method("set_slide_offset_px"):
				p.call("set_slide_offset_px", 0.0)
			if p.has_method("set_reveal_progress"):
				p.call("set_reveal_progress", 1.0)

func _collapse_tertiary_load() -> void:
	_tertiary_reveal.call("abort")
	_load_tertiary_open = false
	if _load_tertiary_host:
		_load_tertiary_host.visible = false
	if _btn_load:
		_btn_load.modulate = Color.WHITE
		if _btn_load.has_method("set_slide_offset_px"):
			_btn_load.call("set_slide_offset_px", 0.0)
		if _btn_load.has_method("set_reveal_progress"):
			_btn_load.call("set_reveal_progress", 1.0)
	_relayout_solo_branch_link()

func _collapse_history_tertiary() -> void:
	_history_reveal.call("abort")
	_history_tertiary_open = false
	if _history_tertiary_host:
		_history_tertiary_host.visible = false
		_history_tertiary_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_history_tertiary_host.position = Vector2(-10000, -10000)
		_history_tertiary_host.size = Vector2.ZERO
		_history_tertiary_host.custom_minimum_size = Vector2.ZERO
	if _btn_history:
		_btn_history.z_index = 0
		_btn_history.modulate = Color.WHITE
		if _btn_history.has_method("set_slide_offset_px"):
			_btn_history.call("set_slide_offset_px", 0.0)
		if _btn_history.has_method("set_reveal_progress"):
			_btn_history.call("set_reveal_progress", 1.0)
	_relayout_solo_branch_link()

func _collapse_all_tertiaries() -> void:
	_collapse_tertiary_load()
	_collapse_history_tertiary()

func _collapse_all_secondaries() -> void:
	_branch_reveal.call("abort")
	_play_mode_reveal.call("abort")
	_collapse_all_tertiaries()
	_play_mode_open = ""
	for k: Variant in _secondary_hosts.keys():
		var h: Control = _secondary_hosts[k] as Control
		if h:
			h.visible = false
	for k2: Variant in _primary_btns.keys():
		var p: Control = _primary_btns[k2] as Control
		if p:
			p.modulate = Color.WHITE
			if p.has_method("set_slide_offset_px"):
				p.call("set_slide_offset_px", 0.0)
			if p.has_method("set_reveal_progress"):
				p.call("set_reveal_progress", 1.0)

func _apply_branch_host_sizes() -> void:
	var bh: float = _menu_px(_menu_design_bh())
	var bw: float = _menu_px(_menu_design_bw())
	var host_w: float = _menu_px(_menu_design_host_w())
	var gap: float = _branch_secondary_gap()
	var sep: float = _menu_px(8.0)
	var pad: float = _menu_px(10.0) * 2.0
	var host_h_solo: float = bh * 4.0 + sep * 3.0 + pad + 4.0
	var host_h_opt: float = bh * 2.0 + sep + pad + 4.0
	## Online width ×1.5 (UI_AND_SHELL §1.0). Chrome height = lobby; host adds框外历史钮.
	var host_w_online: float = host_w * 1.5
	var chrome_h_online: float = _menu_px(400.0 if UiLayout.is_mobile() else 460.0)
	var l1_sep: int = maxi(4, roundi(_menu_px(_menu_design_l1_sep())))
	if _nullsec_lobby and _nullsec_lobby.has_method("apply_layout_metrics"):
		_nullsec_lobby.call("apply_layout_metrics", bh, l1_sep)
	if _nullsec_lobby and _nullsec_lobby.has_method("content_min_size"):
		var cm: Vector2 = _nullsec_lobby.call("content_min_size") as Vector2
		if cm.y > 1.0:
			chrome_h_online = maxf(cm.y + pad + 4.0, chrome_h_online * 0.5)
			host_w_online = maxf(host_w_online, maxf(cm.x * 1.5, cm.x + pad))
	var host_h_online: float = chrome_h_online + float(l1_sep) + bh
	var mode_col_w: float = bw
	var mode_content_w: float = 0.0
	var mode_content_h: float = 0.0
	if _play_mode_open == BRANCH_SOLO:
		mode_content_w = host_w
		mode_content_h = host_h_solo
	elif _play_mode_open == BRANCH_ONLINE:
		mode_content_w = host_w_online
		mode_content_h = host_h_online
	var play_inner_w: float = mode_col_w + (gap + mode_content_w if mode_content_w > 1.0 else 0.0)
	var play_modes_h: float = bh * 2.0 + float(l1_sep)
	var play_h: float = maxf(play_modes_h, float(l1_sep) + bh + mode_content_h)
	## Row height locked to L1 — secondary overlays and must not shove peers.
	for id_v: Variant in _branch_rows.keys():
		var id: String = str(id_v)
		var row: Control = _branch_rows[id] as Control
		var host: Control = _secondary_hosts.get(id) as Control
		var primary: Control = _primary_btns.get(id) as Control
		if row == null:
			continue
		var hw: float = host_w
		var hh: float = bh
		var row_w: float = bw + gap + hw
		if id == BRANCH_PLAY:
			hw = play_inner_w
			hh = play_h
			row_w = bw + gap + hw
		elif id == BRANCH_SOLO:
			hw = host_w
			hh = host_h_solo
			row_w = bw + gap + hw
		elif id == BRANCH_ONLINE:
			hw = host_w_online
			hh = host_h_online
			row_w = bw + gap + hw
		elif id == BRANCH_OPTIONS:
			hw = host_w * 0.75
			hh = host_h_opt
			row_w = bw + gap + hw
		row.custom_minimum_size = Vector2(row_w, bh)
		row.size = Vector2(maxi(row.size.x, row_w), bh)
		if primary:
			var slot: Control = primary.get_parent() as Control
			if slot:
				slot.position = Vector2.ZERO
				slot.size = Vector2(bw, bh)
				slot.custom_minimum_size = Vector2(bw, bh)
			var slide_keep: float = 0.0
			if primary.get("slide_offset_px") != null:
				slide_keep = float(primary.get("slide_offset_px"))
			primary.custom_minimum_size = Vector2(bw, bh)
			primary.size = Vector2(bw, bh)
			if id == BRANCH_SOLO or id == BRANCH_ONLINE:
				primary.position = Vector2(slide_keep, primary.position.y)
		if host:
			host.position = Vector2(bw + gap, 0.0)
			host.custom_minimum_size = Vector2(hw, hh)
			host.size = Vector2(hw, hh)
		if id == BRANCH_ONLINE:
			_layout_online_outside_history(hw, chrome_h_online, float(l1_sep), bh)
	## Nest 单机/联机 rows inside 开始游戏 secondary root.
	if _play_root != null and is_instance_valid(_play_root):
		var solo_row: Control = _branch_rows.get(BRANCH_SOLO) as Control
		var online_row: Control = _branch_rows.get(BRANCH_ONLINE) as Control
		if solo_row:
			solo_row.position = Vector2.ZERO
			solo_row.size = Vector2(play_inner_w, bh)
		if online_row:
			online_row.position = Vector2(0.0, bh + float(l1_sep))
			online_row.size = Vector2(play_inner_w, bh)
	var solo_btns: Node = _solo_host.find_child("SoloBtns", true, false) if _solo_host else null
	if solo_btns is VBoxContainer:
		(solo_btns as VBoxContainer).add_theme_constant_override("separation", maxi(4, roundi(sep)))
	if _options_host:
		for ch: Node in _options_host.get_children():
			if ch is VBoxContainer:
				(ch as VBoxContainer).add_theme_constant_override("separation", maxi(4, roundi(sep)))
	_layout_load_tertiary()
	_layout_history_tertiary()
	if _branch_reveal != null and _branch_reveal.has_method("relayout_open_link"):
		_branch_reveal.call("relayout_open_link")
	if _play_mode_reveal != null and _play_mode_reveal.has_method("relayout_open_link"):
		_play_mode_reveal.call("relayout_open_link")
	if _tertiary_reveal != null and _tertiary_reveal.has_method("relayout_open_link"):
		_tertiary_reveal.call("relayout_open_link")
	if _history_reveal != null and _history_reveal.has_method("relayout_open_link"):
		_history_reveal.call("relayout_open_link")

func _branch_secondary_gap() -> float:
	## L1→二级外框 / 读取存档→三级外框 同一间距（UI_AND_SHELL §1.0a）.
	return _menu_px(_menu_design_gap())

func _layout_online_outside_history(hw: float, chrome_h: float, hist_gap: float, bh: float) -> void:
	## Chrome fills top; 历史钮 below plate with L1 row gap (outside底框).
	if _online_chrome != null and is_instance_valid(_online_chrome):
		_online_chrome.position = Vector2.ZERO
		_online_chrome.custom_minimum_size = Vector2(hw, chrome_h)
		_online_chrome.size = Vector2(hw, chrome_h)
	if _btn_history != null and is_instance_valid(_btn_history):
		var slide_x: float = 0.0
		if _btn_history.get("slide_offset_px") != null:
			slide_x = float(_btn_history.get("slide_offset_px"))
		_btn_history.custom_minimum_size = Vector2(hw, bh)
		_btn_history.size = Vector2(hw, bh)
		_btn_history.position = Vector2(slide_x, chrome_h + hist_gap)

func _layout_load_tertiary() -> void:
	if _load_tertiary_host == null or _btn_load == null:
		return
	var parent: Control = _load_tertiary_host.get_parent() as Control
	if parent == null:
		return
	var gap: float = _branch_secondary_gap()
	var tw: float = _menu_px(_menu_design_tertiary_w())
	var th: float = _menu_px(_menu_design_tertiary_h())
	## Place from un-slid button AABB + gap — same model as L1 host at bw+gap
	## (button slide then eats into gap, matching 联机模式→外框净距).
	var slide: float = 0.0
	if _btn_load.get("slide_offset_px") != null:
		slide = float(_btn_load.get("slide_offset_px"))
	var local: Vector2 = parent.get_global_transform_with_canvas().affine_inverse() * _btn_load.global_position
	local.x -= slide
	_load_tertiary_host.position = Vector2(local.x + _btn_load.size.x + gap, local.y)
	_load_tertiary_host.custom_minimum_size = Vector2(tw, th)
	_load_tertiary_host.size = Vector2(tw, th)
	if _load_list:
		## Force row width so long name buttons fill the plate.
		_load_list.custom_minimum_size = Vector2(maxf(tw - _menu_px(36.0), 200.0 * _menu_fit_scale), 0.0)

func _setup_history_tertiary() -> void:
	## History tertiary — chrome + scroll. Parent = MainMenu so z/hit never covers 联机二级钮.
	## _btn_history is created in _build_online_secondary (outside plate).
	_history_tertiary_host = Control.new()
	_history_tertiary_host.name = "HistoryTertiary"
	_history_tertiary_host.visible = false
	## Scroll clips list; host must not clip chrome border (bottom frame was vanishing).
	_history_tertiary_host.clip_contents = false
	_history_tertiary_host.z_index = 50
	_history_tertiary_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_history_tertiary_host.position = Vector2(-10000, -10000)
	_history_tertiary_host.size = Vector2.ZERO
	add_child(_history_tertiary_host)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "HistoryScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_history_list = VBoxContainer.new()
	_history_list.name = "HistoryList"
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list.add_theme_constant_override("separation", maxi(4, roundi(_menu_px(6.0))))
	scroll.add_child(_history_list)
	var list_chrome: Control = _make_secondary_chrome(scroll)
	list_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_history_tertiary_host.add_child(list_chrome)

func _layout_history_tertiary() -> void:
	if _history_tertiary_host == null or _btn_history == null or _online_host == null:
		return
	if not _history_tertiary_open:
		_history_tertiary_host.visible = false
		_history_tertiary_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_history_tertiary_host.position = Vector2(-10000, -10000)
		_history_tertiary_host.size = Vector2.ZERO
		_history_tertiary_host.custom_minimum_size = Vector2.ZERO
		return
	var gap: float = _branch_secondary_gap()
	var tw: float = _menu_px(_menu_design_tertiary_w())
	var th: float = _menu_px(_menu_design_tertiary_h())
	var inv := get_global_transform_with_canvas().affine_inverse()
	var btn_tl: Vector2 = inv * (_btn_history.get_global_transform_with_canvas() * Vector2.ZERO)
	var slide: float = 0.0
	if _btn_history.get("slide_offset_px") != null:
		slide = float(_btn_history.get("slide_offset_px"))
	## Rest (un-slid) for gap; slide_reserve keeps plate clear of sliding face.
	btn_tl.x -= slide
	var slide_reserve: float = maxf(_btn_history.size.x, 1.0) * 0.25
	var x: float = btn_tl.x + _btn_history.size.x + gap + slide_reserve
	var btn_bottom: float = btn_tl.y + _btn_history.size.y
	var margin: float = 8.0
	var vp: Vector2 = size
	if vp.x < 2.0 or vp.y < 2.0:
		vp = UiLayout.viewport_size(self)
	var max_h: float = maxf(160.0, vp.y - margin * 2.0)
	th = minf(th, max_h)
	## Bottom-align tertiary plate to 历史钮 bottom (UI_AND_SHELL §1.0).
	var y: float = btn_bottom - th
	if y < margin:
		th = minf(th, maxf(160.0, btn_bottom - margin))
		y = btn_bottom - th
	var max_w: float = maxf(160.0, vp.x - margin * 2.0)
	tw = minf(tw, max_w)
	x = clampf(x, margin, maxf(margin, vp.x - tw - margin))
	if y + th > vp.y - margin:
		y = maxf(margin, vp.y - th - margin)
	else:
		y = maxf(y, margin)
	_history_tertiary_host.position = Vector2(x, y)
	_history_tertiary_host.custom_minimum_size = Vector2(tw, th)
	_history_tertiary_host.size = Vector2(tw, th)
	_history_tertiary_host.mouse_filter = Control.MOUSE_FILTER_STOP
	for ch: Node in _history_tertiary_host.get_children():
		if ch is Control and not str(ch.name).begins_with("BranchReveal"):
			var c: Control = ch as Control
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			c.position = Vector2.ZERO
			c.size = Vector2(tw, th)
			break
	if _history_list:
		_history_list.custom_minimum_size = Vector2(maxf(tw - _menu_px(36.0), 200.0 * _menu_fit_scale), 0.0)

func _apply_adaptive_layout() -> void:
	var pad: float = 0.035 if UiLayout.is_mobile() else 0.038
	## Wider left column so secondary wipe fits beside primaries.
	var col_w: float = 0.72 if UiLayout.is_mobile() else 0.62
	if _col:
		_col.clip_contents = false
	UiLayout.set_rect_frac(_col, 0.0, 0.0, col_w, 1.0)

	# Title band ~ top 4%–11%
	UiLayout.set_rect_frac(_title, pad / col_w, 0.04, 0.95, 0.11)
	UiAssets.apply_label_font(_title, true, UiLayout.font_size(36, self))
	_title.add_theme_constant_override("outline_size", UiLayout.margin_px(6, self))

	# Buttons: wider when secondary may open (left column + wipe area)
	var btn_left: float = pad / col_w
	var btn_w: float = 0.92 if UiLayout.is_mobile() else 0.95
	UiLayout.set_rect_frac(_btn_box, btn_left, 0.16, minf(btn_left + btn_w, 0.98), 0.88)
	## Fixed design px for menu chrome; shrink only if tertiary would clip.
	_menu_fit_scale = _compute_menu_fit_scale()
	_btn_box.add_theme_constant_override("separation", maxi(4, roundi(_menu_px(_menu_design_l1_sep()))))
	var bh: float = _menu_px(_menu_design_bh())
	var bw: float = _menu_px(_menu_design_bw())
	var bfs: int = _menu_font_px(_menu_design_font())
	_size_menu_buttons(_btn_box, bw, bh, bfs)
	for k: Variant in _primary_btns.keys():
		var primary: Button = _primary_btns[k] as Button
		if primary:
			primary.custom_minimum_size = Vector2(bw, bh)
			primary.size = Vector2(bw, bh)
		var slot: Node = primary.get_parent() if primary else null
		if slot is Control:
			(slot as Control).custom_minimum_size = Vector2(bw, bh)
			(slot as Control).size = Vector2(bw, bh)
	_apply_branch_host_sizes()

	# Footer bottom of column
	UiLayout.set_rect_frac(_footer, pad / col_w, 0.82, 0.96, 0.98)
	_footer.add_theme_constant_override("separation", UiLayout.margin_px(4, self))
	var declare: Label = _footer.get_node_or_null("Declare") as Label
	if declare:
		UiAssets.apply_label_font(declare, false, UiLayout.font_size(12, self))
		declare.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		declare.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		declare.add_theme_constant_override("outline_size", UiLayout.margin_px(2, self))
	var ver: Label = _footer.get_node_or_null("VersionLabel") as Label
	if ver:
		ver.text = "游戏版本:%s" % DataStore.content_version
		UiAssets.apply_label_font(ver, false, UiLayout.font_size(13, self))
		ver.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
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

func _size_menu_buttons(n: Node, bw: float, bh: float, bfs: int) -> void:
	if n is Button:
		var b: Button = n as Button
		var is_primary: bool = false
		for k: Variant in _primary_btns.keys():
			if _primary_btns[k] == b:
				is_primary = true
				break
		if is_primary:
			b.custom_minimum_size = Vector2(bw, bh)
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		else:
			b.custom_minimum_size = Vector2(bw, bh)
		UiAssets.apply_button_font(b, bfs)
	for c: Node in n.get_children():
		_size_menu_buttons(c, bw, bh, bfs)

func _menu_btn(text: String, cb: Callable) -> Button:
	var b: Button = _ParaBtn.new() as Button
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_fps_slider.value = (PlayerSettings.instance() as PlayerSettings).target_fps
	_fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_slider.value_changed.connect(_on_fps_changed)
	row.add_child(_fps_slider)
	_fps_lbl = Label.new()
	_fps_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_fps_lbl.text = str(int((PlayerSettings.instance() as PlayerSettings).target_fps))
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
	nomodel.button_pressed = (PlayerSettings.instance() as PlayerSettings).no_model_perf_mode
	UiAssets.apply_button_font(nomodel, UiLayout.font_size(16, self))
	nomodel.toggled.connect(_on_no_model_toggled)
	nomodel_row.add_child(nomodel)
	box.add_child(nomodel_row)

	var fx_simple_row: HBoxContainer = HBoxContainer.new()
	fx_simple_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var fx_simple: CheckBox = CheckBox.new()
	fx_simple.text = "装备与武器特效简化"
	fx_simple.tooltip_text = "关闭=正常特效（与预览同套）；开启=色块束/单球加农/直线导弹"
	fx_simple.button_pressed = (PlayerSettings.instance() as PlayerSettings).weapon_fx_simplified
	UiAssets.apply_button_font(fx_simple, UiLayout.font_size(16, self))
	fx_simple.toggled.connect(_on_weapon_fx_simplified_toggled)
	fx_simple_row.add_child(fx_simple)
	box.add_child(fx_simple_row)

	var breathe_row: HBoxContainer = HBoxContainer.new()
	breathe_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var breathe: CheckBox = CheckBox.new()
	breathe.text = "镜头呼吸浮动"
	breathe.button_pressed = (PlayerSettings.instance() as PlayerSettings).camera_breathe_enabled
	UiAssets.apply_button_font(breathe, UiLayout.font_size(16, self))
	breathe.toggled.connect(_on_camera_breathe_toggled)
	breathe_row.add_child(breathe)
	box.add_child(breathe_row)

	var hp_vis_row: HBoxContainer = HBoxContainer.new()
	var hp_vis: CheckBox = CheckBox.new()
	hp_vis.text = "显示血条"
	hp_vis.tooltip_text = "关闭后隐藏盾/甲/结构/电量几何；吨位章与装备格仍显示"
	hp_vis.button_pressed = (PlayerSettings.instance() as PlayerSettings).health_bar_visible
	UiAssets.apply_button_font(hp_vis, UiLayout.font_size(16, self))
	hp_vis.toggled.connect(_on_health_bar_visible_toggled)
	hp_vis_row.add_child(hp_vis)
	box.add_child(hp_vis_row)

	var hp_row: HBoxContainer = HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var hp_cap: Label = Label.new()
	hp_cap.text = "血量展示"
	UiAssets.apply_label_font(hp_cap, false, UiLayout.font_size(16, self))
	hp_row.add_child(hp_cap)
	var hp_opt: OptionButton = OptionButton.new()
	hp_opt.add_item("环形血量展示", 0)
	hp_opt.add_item("四条血量展示", 1)
	var bars_on: bool = PlayerSettings.get_or_null() != null and PlayerSettings.get_or_null().health_bar_style == "bars"
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

	var ps_audio: PlayerSettings = PlayerSettings.get_or_null()
	var sfx_on_row: HBoxContainer = HBoxContainer.new()
	sfx_on_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	_sfx_check = CheckBox.new()
	_sfx_check.text = "音效"
	_sfx_check.button_pressed = ps_audio.sfx_enabled if ps_audio else true
	UiAssets.apply_button_font(_sfx_check, UiLayout.font_size(16, self))
	_sfx_check.toggled.connect(_on_sfx_toggled)
	sfx_on_row.add_child(_sfx_check)
	box.add_child(sfx_on_row)

	var sfx_vol_row: HBoxContainer = HBoxContainer.new()
	sfx_vol_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var sfx_cap: Label = Label.new()
	sfx_cap.text = "音效音量"
	UiAssets.apply_label_font(sfx_cap, false, UiLayout.font_size(16, self))
	sfx_vol_row.add_child(sfx_cap)
	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0
	_sfx_slider.max_value = 100
	_sfx_slider.step = 1
	_sfx_slider.value = ps_audio.sfx_volume_pct if ps_audio else 80.0
	_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_vol_row.add_child(_sfx_slider)
	_sfx_lbl = Label.new()
	_sfx_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_sfx_lbl.text = str(int(_sfx_slider.value))
	UiAssets.apply_label_font(_sfx_lbl, false, UiLayout.font_size(16, self))
	sfx_vol_row.add_child(_sfx_lbl)
	box.add_child(sfx_vol_row)

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
	_dev_master_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_master_check, UiLayout.font_size(16, self))
	_dev_master_check.toggled.connect(_on_dev_master_toggled)
	box.add_child(_dev_master_check)

	_dev_soften_check = CheckBox.new()
	_dev_soften_check.text = "我方扣血软化（失败惩罚减为 1）"
	_dev_soften_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).player_citadel_soften
	_dev_soften_check.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_soften_check, UiLayout.font_size(16, self))
	_dev_soften_check.toggled.connect(_on_dev_soften_toggled)
	box.add_child(_dev_soften_check)

	_dev_economy_check = CheckBox.new()
	_dev_economy_check.text = "人机双倍经济（我方战斗收入×同人机）"
	_dev_economy_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).player_ai_double_economy
	_dev_economy_check.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_economy_check, UiLayout.font_size(16, self))
	_dev_economy_check.toggled.connect(_on_dev_economy_toggled)
	box.add_child(_dev_economy_check)

	_dev_enemy_layout_check = CheckBox.new()
	_dev_enemy_layout_check.text = "敌方布局调整许可（暂停时可拖敌方单位）"
	_dev_enemy_layout_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).enemy_layout_adjust
	_dev_enemy_layout_check.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_enemy_layout_check, UiLayout.font_size(16, self))
	_dev_enemy_layout_check.toggled.connect(_on_dev_enemy_layout_toggled)
	box.add_child(_dev_enemy_layout_check)

	_dev_ship_data_btn = Button.new()
	_dev_ship_data_btn.text = "全舰船装备数据调整"
	_dev_ship_data_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	_dev_ship_data_btn.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
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

	var about_ver: Label = Label.new()
	about_ver.text = "游戏版本:%s" % DataStore.content_version
	UiAssets.apply_label_font(about_ver, false, UiLayout.font_size(13, self))
	box.add_child(about_ver)

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
		(PlayerSettings.instance() as PlayerSettings).set_target_fps(int(v))
	else:
		(PlayerSettings.instance() as PlayerSettings).target_fps = int(v)
		Engine.max_fps = (PlayerSettings.instance() as PlayerSettings).target_fps
		(PlayerSettings.instance() as PlayerSettings).save_settings()
	if _fps_lbl:
		_fps_lbl.text = str((PlayerSettings.instance() as PlayerSettings).target_fps)

func _on_no_model_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_no_model_perf_mode(on)

func _on_weapon_fx_simplified_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_weapon_fx_simplified(on)

func _on_camera_breathe_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_camera_breathe_enabled(on)

func _on_health_bar_visible_toggled(on: bool) -> void:
	if GameSession.has_method("set_health_bar_visible"):
		(PlayerSettings.instance() as PlayerSettings).set_health_bar_visible(on)
	else:
		GameSession.set("health_bar_visible", on)
		if GameSession.has_method("save_settings"):
			(PlayerSettings.instance() as PlayerSettings).save_settings()
		get_tree().call_group("match_root", "refresh_all_ship_health_bars")

func _on_health_bar_style_selected(idx: int) -> void:
	var style: String = "bars" if idx == 1 else "ring"
	if GameSession.has_method("set_health_bar_style"):
		(PlayerSettings.instance() as PlayerSettings).set_health_bar_style(style)
	else:
		GameSession.set("health_bar_style", style)
		if GameSession.has_method("save_settings"):
			(PlayerSettings.instance() as PlayerSettings).save_settings()
	get_tree().call_group("match_root", "rebuild_all_ship_health_bars")

func _on_nullsec_open() -> void:
	await _ensure_play_mode_open(BRANCH_ONLINE)

func _ensure_play_mode_open(mode_id: String) -> void:
	if _branch_open != BRANCH_PLAY:
		await _toggle_branch(BRANCH_PLAY)
	if _play_mode_open != mode_id:
		await _toggle_play_mode(mode_id)

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
			if str(r) == "kicked":
				_on_nullsec_kicked()
				return
			if _nullsec_lobby:
				_nullsec_lobby.set_status(r)
		)
		_nullsec_net.ships_mismatch.connect(func(_h: String) -> void:
			if _nullsec_lobby:
				_nullsec_lobby.set_status("全舰船数据与房主不一致 · 进入对局后将临时使用房主舰船数据（不覆盖本地）")
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
	_collapse_all_secondaries()
	_branch_open = ""
	_play_mode_open = ""
	_set_main_menu_chrome_for_nullsec_room(true)


func _set_main_menu_chrome_for_nullsec_room(in_room: bool) -> void:
	## UI_AND_SHELL / MATCH_FLOW: room covers accordion; keep bottom-right announce on top.
	if _col:
		_col.visible = not in_room
	if _announce:
		if in_room:
			_announce.z_index = 90
			_announce.z_as_relative = false
		else:
			_announce.z_index = 8


func _on_nullsec_leave() -> void:
	MatchLoadOverlay.hide_overlay()
	GameSession.pending_nullsec = {}
	GameSession.pending_mode = ""
	if _nullsec_net:
		_nullsec_net.clear_rejoin_ticket()
		_nullsec_net.close()
	if _nullsec_room:
		_nullsec_room.queue_free()
		_nullsec_room = null
	_set_main_menu_chrome_for_nullsec_room(false)


func _on_nullsec_kicked() -> void:
	## MULTIPLAYER_MATCH_FLOW §2.1a — ejected peer returns to main menu.
	MatchLoadOverlay.hide_overlay()
	if _nullsec_net:
		_nullsec_net.close()
	if _nullsec_room:
		_nullsec_room.queue_free()
		_nullsec_room = null
	_set_main_menu_chrome_for_nullsec_room(false)
	if _nullsec_lobby and is_instance_valid(_nullsec_lobby):
		_nullsec_lobby.set_status("你已被踢出房间")
		await _ensure_play_mode_open(BRANCH_ONLINE)

func _on_nullsec_start_match(assignments: Dictionary) -> void:
	var net: NullsecNetSession = _ensure_nullsec_net()
	SessionDiagnostics.begin_critical_window("mp_host_match" if net.is_host else "mp_guest_match")
	SessionDiagnostics.log_critical(
		"net.scene_change_match",
		"seat=%d host=%s ships=%d %s" % [
			net.local_seat,
			net.is_host,
			net.opening_host_ships.size(),
			SessionDiagnostics.mem_detail(),
		]
	)
	## Guest: keep「从房主拉取…」visible until ships material is present (SEMI_ASYNC §3.7).
	if net.is_host or not net.opening_host_ships.is_empty():
		MatchLoadOverlay.set_phase("正在进入对局场景", 0.28)
	else:
		MatchLoadOverlay.set_phase("正在从房主拉取全舰船与全游戏数据", 0.16)
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
	LanJoinDebug.log_locals("match_public")
	## -1 → platform default (emulator waits longer for shared-net peers).
	var rooms: Array = await LanBeacon.discover(self, -1.0)
	SessionDiagnostics.log("net.discover", "rooms=%d rules=%s" % [rooms.size(), rules])
	var room_log_n: int = 0
	var saw_same_lan: bool = false
	for rv: Variant in rooms:
		if typeof(rv) != TYPE_DICTIONARY:
			continue
		var rd: Dictionary = TypedVariant.as_dict(rv)
		if room_log_n < 12:
			LanJoinDebug.log_room(rd, room_log_n)
			SessionDiagnostics.log(
				"net.discover.room",
				"ip=%s port=%s code=%s rules=%s occ=%s/%s in_match=%s packet_ip=%s payload_ip=%s aff=%s" % [
					str(rd.get("ip", "")),
					str(rd.get("port", 0)),
					str(rd.get("code", 0)),
					str(rd.get("rules", "")),
					str(rd.get("occupied", 0)),
					str(rd.get("cap", 0)),
					str(rd.get("in_match", false)),
					str(rd.get("packet_ip", "")),
					str(rd.get("payload_ip", "")),
					LanAffinity.affinity(str(rd.get("ip", ""))),
				]
			)
		if LanAffinity.is_same_lan(str(rd.get("ip", ""))):
			saw_same_lan = true
		room_log_n += 1
	var mismatch_n: int = PublicRoomEnumerator.count_rules_mismatch(rooms, rules)
	var started_n: int = PublicRoomEnumerator.count_in_match(rooms, rules)
	var full_n: int = PublicRoomEnumerator.count_full(rooms, rules)
	var candidates: Array = PublicRoomEnumerator.list_join_candidates(rooms, rules, ignore_started)
	## Prefer same-/24 endpoints first (multi-NIC hosts often advertise VPN last).
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aa: int = 1 if LanAffinity.affinity(str(a.get("ip", ""))) == "same_24" else 0
		var ba: int = 1 if LanAffinity.affinity(str(b.get("ip", ""))) == "same_24" else 0
		if aa != ba:
			return aa > ba
		var ca: int = TypedVariant.as_int(a.get("code", 0), 0)
		var cb: int = TypedVariant.as_int(b.get("code", 0), 0)
		if ca != cb:
			return ca < cb
		return TypedVariant.as_int(a.get("occupied", 0), 0) < TypedVariant.as_int(b.get("occupied", 0), 0)
	)
	SessionDiagnostics.log(
		"net.discover",
		"cand=%d mismatch=%d started=%d full=%d ignore_started=%s same_lan_seen=%s" % [
			candidates.size(), mismatch_n, started_n, full_n,
			"1" if ignore_started else "0", "1" if saw_same_lan else "0"
		]
	)
	var private_n: int = 0
	var tried_same_lan: bool = false
	var net: NullsecNetSession = _ensure_nullsec_net()
	## Same room_code may map to multiple endpoints — try each; one reject does not skip siblings.
	for pick: Variant in candidates:
		if typeof(pick) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = TypedVariant.as_dict(pick)
		var code: int = TypedVariant.as_int(d.get("code", 0), 0)
		var ip: String = str(d.get("ip", "")).strip_edges()
		var port: int = TypedVariant.as_int(d.get("port", NullsecNetSession.port_for_code(code)), NullsecNetSession.port_for_code(code))
		var in_match_ad: bool = TypedVariant.as_bool(d.get("in_match", false), false)
		if ip == "" or ip.begins_with("127.") or ip == "0.0.0.0":
			LanJoinDebug.log_fail(ip, port, code, "bad_ip", "match")
			continue
		if LanAffinity.is_same_lan(ip):
			tried_same_lan = true
		net.close()
		var host_plat_ad: String = str(d.get("host_platform", "")).strip_edges()
		if host_plat_ad != "":
			net.opening_host_platform = host_plat_ad
		_nullsec_lobby.set_status("正在试加入房间…")
		LanJoinDebug.log_try(ip, port, code, "match")
		if NullsecNetSession.detect_local_platform() == "mobile":
			SessionDiagnostics.log(
				"net.lan.join_pc_host",
				"menu try ep=%s:%d host_plat=%s code=%04d aff=%s" % [
					ip, port, host_plat_ad if host_plat_ad != "" else "unknown", code, LanAffinity.affinity(ip)
				]
			)
		var err: Error = net.join(ip, port, nick, rules, "")
		if err != OK:
			LanJoinDebug.log_fail(ip, port, code, "enet:%d" % err, "match")
			_nullsec_lobby.set_status("ENet 连接失败(%d) · %s:%d" % [err, ip, port])
			continue
		## SEMI_ASYNC §7.5 — wait ≥5s (align with rejoin); mobile Wi‑Fi handshake is slow.
		var join_res: Dictionary = await _await_nullsec_join_ex(net, 5.0)
		if not TypedVariant.as_bool(join_res.get("ok", false), false):
			var reason: String = str(join_res.get("reason", ""))
			if reason == "":
				reason = "timeout"
			LanJoinDebug.log_fail(ip, port, code, reason, "match")
			if NullsecNetSession.detect_local_platform() == "mobile":
				SessionDiagnostics.log(
					"net.lan.join_pc_host",
					"fail reason=%s ep=%s:%d host_plat=%s" % [reason, ip, port, net.opening_host_platform]
				)
			net.close()
			if reason == "need_password" or reason.find("需要房间密码") >= 0:
				private_n += 1
				continue
			if reason.find("已满") >= 0 or reason == "room full":
				full_n += 1
				continue
			if reason == "timeout" or reason == "enet":
				var tip: String = "同网段信标见但连不上 · 试下一终点…" if LanAffinity.is_same_lan(ip) else "信标见但连不上 · 试下一终点…"
				_nullsec_lobby.set_status("%s · %s" % [tip, reason])
			else:
				_nullsec_lobby.set_status(reason)
			continue
		PublicRoomEnumerator.advance_past(code)
		LanJoinDebug.log_ok(ip, port, code, "match")
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
	var parts: PackedStringArray = []
	if rooms.size() > 0 and candidates.size() > 0:
		if tried_same_lan or saw_same_lan:
			parts.append("同网段信标见但连不上（已试 %d 终点·查防火墙/AP隔离）" % candidates.size())
		else:
			parts.append("信标见但连不上（已试 %d 终点）" % candidates.size())
	elif rooms.size() > 0:
		parts.append("信标见 %d · 无可试加入" % rooms.size())
	else:
		parts.append("未发现可加入房间")
	if ignore_started and started_n > 0:
		parts.append("已略过 %d 间已开局" % started_n)
	if full_n > 0:
		parts.append("已满 %d 间" % full_n)
	if private_n > 0:
		parts.append("私密房 %d 间" % private_n)
	if mismatch_n > 0:
		parts.append("版本不符 %d 间（本机 %s）" % [mismatch_n, rules])
	parts.append("可点「主持房间」开一间")
	LanJoinDebug.log_summary("match_fail " + " · ".join(parts))
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
	GameSession.pending_nullsec = {}
	GameSession.pending_mode = ""
	_nullsec_lobby.set_status("正在选定空闲房间…")
	## Host path: strictly avoid LAN-announced codes; bind fail → retry next code.
	## -1 → longer wait on Android emulator (shared-net peers).
	var rooms: Array = await LanBeacon.discover(self, -1.0)
	var taken: Dictionary = {}
	for r: Variant in rooms:
		if typeof(r) == TYPE_DICTIONARY:
			var rd: Dictionary = TypedVariant.as_dict(r)
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
		net.clear_rejoin_ticket()
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
		LanJoinDebug.log_summary("share_rules_mismatch host=%s local=%s" % [host_rules, local_rules])
		return
	LanJoinDebug.log_locals("join_share")
	## Build try order: LAN same room (all ips) → blob ipv4 → ipv6 → reflexive → TURN.
	var endpoints: Array = []
	if room_code >= 1 and room_code <= 9999:
		_nullsec_lobby.set_status("正在扫描局域网…")
		var rooms: Array = await LanBeacon.discover(self, -1.0)
		var lan_i: int = 0
		for r: Variant in rooms:
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = TypedVariant.as_dict(r)
			if TypedVariant.as_int(d.get("code", 0), 0) != room_code:
				continue
			LanJoinDebug.log_room(d, lan_i)
			lan_i += 1
			var port_lan: int = TypedVariant.as_int(d.get("port", NullsecNetSession.port_for_code(room_code)), NullsecNetSession.port_for_code(room_code))
			var lan_ips: Array = []
			var primary: String = str(d.get("ip", "")).strip_edges()
			if primary != "":
				lan_ips.append(primary)
			for key: String in ["alt_ips", "ips"]:
				var arr_v: Variant = d.get(key, [])
				if arr_v is Array:
					for a_v: Variant in arr_v:
						var a: String = str(a_v).strip_edges()
						if a != "" and not lan_ips.has(a):
							lan_ips.append(a)
			for lip_v: Variant in lan_ips:
				endpoints.append({
					"ip": str(lip_v),
					"port": port_lan,
					"via": "lan_beacon",
				})
	## Prefer blob IPv4 before IPv6 on home Wi‑Fi (global v6 often blackholes).
	var blob_eps: Array = InviteBlobHelper.join_endpoints(decoded)
	blob_eps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ai: String = str(a.get("ip", ""))
		var bi: String = str(b.get("ip", ""))
		var av4: int = 0 if ai.find(":") >= 0 else 1
		var bv4: int = 0 if bi.find(":") >= 0 else 1
		return av4 > bv4
	)
	for e: Dictionary in blob_eps:
		var be: Dictionary = e.duplicate(true)
		if str(be.get("via", "")) == "":
			be["via"] = "room_blob"
		endpoints.append(be)
	## SEMI_ASYNC §7.5 step ⑤ — local turn_urls as extra ENet targets (relay / port-map).
	for te: Variant in NetConnectivity.turn_join_endpoints():
		if typeof(te) == TYPE_DICTIONARY:
			endpoints.append(te)
	## Dedup; same_24 first.
	var seen: Dictionary = {}
	var uniq: Array = []
	for e: Variant in endpoints:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ep: Dictionary = TypedVariant.as_dict(e)
		var key: String = "%s:%d" % [str(ep.get("ip", "")), TypedVariant.as_int(ep.get("port", 0), 0)]
		if key == ":0" or seen.has(key):
			continue
		seen[key] = true
		uniq.append(ep)
	uniq.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aa: int = 2 if LanAffinity.affinity(str(a.get("ip", ""))) == "same_24" else (1 if LanAffinity.is_same_lan(str(a.get("ip", ""))) else 0)
		var ba: int = 2 if LanAffinity.affinity(str(b.get("ip", ""))) == "same_24" else (1 if LanAffinity.is_same_lan(str(b.get("ip", ""))) else 0)
		return aa > ba
	)
	if uniq.is_empty():
		var addr: Dictionary = InviteBlobHelper.join_address(decoded)
		var room: String = str(addr.get("room", decoded.get("room", "")))
		var resolved: Dictionary = ShortcodeSignaling.resolve_join_sync("public", room, host_rules)
		if TypedVariant.as_bool(resolved.get("ok", false), false):
			uniq.append({"ip": str(resolved.get("ip", "")), "port": TypedVariant.as_int(resolved.get("port", 0), 0), "via": "signaling"})
	if uniq.is_empty():
		_nullsec_lobby.set_status("房间码无有效地址（可配 signaling_url / turn_urls）")
		LanJoinDebug.log_summary("share_no_endpoints code=%04d" % room_code)
		return
	var net: NullsecNetSession = _ensure_nullsec_net()
	var last_err: String = ""
	var tried_same_lan: bool = false
	for e: Variant in uniq:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ep: Dictionary = TypedVariant.as_dict(e)
		var ip: String = str(ep.get("ip", ""))
		var port: int = TypedVariant.as_int(ep.get("port", 0), 0)
		if ip == "" or port <= 0 or ip.begins_with("127."):
			continue
		if LanAffinity.is_same_lan(ip):
			tried_same_lan = true
		net.close()
		var via: String = str(ep.get("via", ""))
		if via == "turn":
			_nullsec_lobby.set_status("正在经 TURN/中继试连 %s:%d…" % [ip, port])
		elif LanAffinity.is_same_lan(ip):
			_nullsec_lobby.set_status("正在同网段试连 %s:%d…" % [ip, port])
		else:
			_nullsec_lobby.set_status("正在试连 %s:%d… · 房间主持 %s" % [ip, port, host_rules])
		LanJoinDebug.log_try(ip, port, room_code, via if via != "" else "share")
		var err: Error = net.join(ip, port, nick, local_rules, password)
		if err != OK:
			last_err = error_string(err)
			LanJoinDebug.log_fail(ip, port, room_code, "enet:%s" % last_err, via)
			continue
		## Same 5s gate as public match — 1.5s was too short on phone↔PC Wi‑Fi.
		var wait_s: float = 5.0 if LanAffinity.is_same_lan(ip) or via == "lan_beacon" else 2.5
		var join_share: Dictionary = await _await_nullsec_join_ex(net, wait_s)
		if TypedVariant.as_bool(join_share.get("ok", false), false):
			LanJoinDebug.log_ok(ip, port, room_code, via if via != "" else "share")
			_nullsec_lobby.set_status("已通过房间码加入 · 房间主持 %s" % host_rules)
			_show_nullsec_room()
			return
		last_err = str(join_share.get("reason", "超时"))
		LanJoinDebug.log_fail(ip, port, room_code, last_err, via)
		net.close()
	var turn_n: int = NetConnectivity.turn_join_endpoints().size()
	var tip: String = LanJoinDebug.fail_status_hint(tried_same_lan, last_err, turn_n)
	LanJoinDebug.log_summary("share_fail tried_same_lan=%s last=%s tip=%s" % [
		"1" if tried_same_lan else "0", last_err, tip
	])
	_nullsec_lobby.set_status(tip)


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
	## Tertiary under 联机二级 — chrome list, hover highlight, click → detail (UI_AND_SHELL §1.0).
	if _btn_history == null or _history_tertiary_host == null:
		return
	if _history_tertiary_open:
		_collapse_history_tertiary()
		return
	var entries: Array = NullsecSettlement.load_all()
	if entries.is_empty():
		if _nullsec_lobby:
			_nullsec_lobby.set_status("尚无历史战绩")
		return
	_collapse_tertiary_load()
	_refresh_history_list(entries)
	_history_tertiary_open = true
	_history_tertiary_host.visible = true
	_history_tertiary_host.mouse_filter = Control.MOUSE_FILTER_STOP
	## Keep 历史钮 above tertiary plate if slide edges kiss the frame.
	_btn_history.z_index = 12
	_layout_history_tertiary()
	await get_tree().process_frame
	_layout_history_tertiary()
	_history_reveal.call("play", get_tree(), _btn_history, _history_tertiary_host, _SECONDARY_BG)

func _refresh_history_list(entries: Array) -> void:
	if _history_list == null:
		return
	for c: Node in _history_list.get_children():
		c.queue_free()
	var title: Label = Label.new()
	title.text = "多人联机历史战绩"
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 2)
	UiAssets.apply_label_font(title, true, _menu_font_px(16 if UiLayout.is_mobile() else 18))
	_history_list.add_child(title)
	var row_h: float = _menu_px(48.0 if UiLayout.is_mobile() else 52.0)
	var name_fs: int = _menu_font_px(14 if UiLayout.is_mobile() else 15)
	var pad_x: float = _menu_px(14.0)
	for i: int in range(entries.size() - 1, -1, -1):
		var e_v: Variant = entries[i]
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = TypedVariant.as_dict(e_v)
		var mid: String = str(e.get("match_id", e.get("at", "#%d" % i)))
		var summary: Dictionary = TypedVariant.as_dict(e.get("summary", {}))
		if summary.is_empty():
			var rows: Array = TypedVariant.as_array(e.get("rows", []))
			if not rows.is_empty() and typeof(rows[0]) == TYPE_DICTIONARY:
				summary = rows[0]
		var gold: int = TypedVariant.as_int(summary.get("gold_earned", 0), 0)
		var res: String = str(summary.get("result", "?"))
		var nick: String = NickCodec.display_short(str(summary.get("nick", summary.get("nick_full", "?"))))
		var at: String = str(e.get("at", ""))
		var line: String = "%s · %s · 黄%d · %s" % [mid.substr(0, mini(16, mid.length())), nick, gold, res]
		if at != "":
			line = "%s\n%s" % [line, at]
		## No action buttons — whole row is hoverable / clickable (UI_AND_SHELL §1.0).
		var row: PanelContainer = PanelContainer.new()
		row.custom_minimum_size = Vector2(0, row_h)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var sb_n: StyleBoxFlat = StyleBoxFlat.new()
		sb_n.bg_color = Color(0.08, 0.09, 0.12, 0.35)
		sb_n.set_corner_radius_all(4)
		sb_n.content_margin_left = pad_x
		sb_n.content_margin_right = pad_x
		sb_n.content_margin_top = 6
		sb_n.content_margin_bottom = 6
		var sb_h: StyleBoxFlat = sb_n.duplicate() as StyleBoxFlat
		sb_h.bg_color = Color(0.18, 0.28, 0.42, 0.72)
		sb_h.border_color = Color(0.85, 0.9, 1.0, 0.45)
		sb_h.set_border_width_all(1)
		row.add_theme_stylebox_override("panel", sb_n)
		row.mouse_entered.connect(func() -> void:
			if is_instance_valid(row):
				row.add_theme_stylebox_override("panel", sb_h)
		)
		row.mouse_exited.connect(func() -> void:
			if is_instance_valid(row):
				row.add_theme_stylebox_override("panel", sb_n)
		)
		var captured: Dictionary = e
		var mid_cap: String = mid
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					_open_history_detail(captured, mid_cap)
					row.accept_event()
			elif ev is InputEventScreenTouch:
				var st: InputEventScreenTouch = ev
				if st.pressed:
					_open_history_detail(captured, mid_cap)
					row.accept_event()
		)
		var lab: Label = Label.new()
		lab.text = line
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 2)
		UiAssets.apply_label_font(lab, false, name_fs)
		row.add_child(lab)
		_history_list.add_child(row)

func _open_history_detail(entry: Dictionary, mid: String) -> void:
	var panel: NullsecSettlementPanel = NullsecSettlementPanel.new()
	add_child(panel)
	panel.title = "战绩详情 · %s" % mid.substr(0, mini(20, mid.length()))
	var detail_rows: Array = TypedVariant.as_array(entry.get("players", entry.get("rows", [])))
	panel.show_rows(detail_rows, false)

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
	## Solo secondary only — local last_match (MATCH_FLOW §5.0b).
	_continue_local_last_match()

func _on_restore_room() -> void:
	## Online secondary — nullsec rejoin ticket.
	if not NullsecRejoinTicket.exists():
		if _nullsec_lobby:
			_nullsec_lobby.set_status("没有可恢复的房间连接")
		return
	await _continue_nullsec_rejoin()


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
		var d: Dictionary = TypedVariant.as_dict(r)
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
		var cand: Dictionary = TypedVariant.as_dict(c)
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
	## SEMI_ASYNC §3.7 — rejoin within 1h may reuse cached host table until host rebroadcasts.
	if not net.opening_host_ships.is_empty():
		DataStore.apply_host_ships_override(net.opening_host_ships)
	else:
		DataStore.reapply_host_ships_match_material()
	get_tree().change_scene_to_file("res://scenes/match.tscn")

func _on_load_open() -> void:
	## Tertiary accordion under 单机二级 (UI_AND_SHELL §1.0) — not the old center modal list.
	if _btn_load == null or _load_tertiary_host == null:
		return
	if _load_tertiary_open:
		_collapse_tertiary_load()
		return
	_collapse_history_tertiary()
	_refresh_load_list()
	_load_tertiary_open = true
	_load_tertiary_host.visible = true
	_layout_load_tertiary()
	await get_tree().process_frame
	_layout_load_tertiary()
	_tertiary_reveal.call("play", get_tree(), _btn_load, _load_tertiary_host, _SECONDARY_BG)

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
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		UiAssets.apply_label_font(empty, false, UiLayout.font_size(16, self))
		_load_list.add_child(empty)
		var eof0: Label = Label.new()
		eof0.text = "到头了"
		eof0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eof0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eof0.mouse_filter = Control.MOUSE_FILTER_IGNORE
		eof0.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.75))
		UiAssets.apply_label_font(eof0, false, _menu_font_px(11 if UiLayout.is_mobile() else 12))
		_load_list.add_child(eof0)
		return
	var title: Label = Label.new()
	title.text = "存档列表"
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	UiAssets.apply_label_font(title, true, _menu_font_px(18))
	_load_list.add_child(title)
	var row_h: float = _menu_px(48.0 if UiLayout.is_mobile() else 52.0)
	var op_h: float = _menu_px(34.0 if UiLayout.is_mobile() else 36.0)
	var name_fs: int = _menu_font_px(15 if UiLayout.is_mobile() else 17)
	var time_fs: int = _menu_font_px(11 if UiLayout.is_mobile() else 12)
	var op_fs: int = _menu_font_px(12 if UiLayout.is_mobile() else 13)
	var op_w: float = _menu_px(64.0 if UiLayout.is_mobile() else 72.0)
	var pad_x: float = _menu_px(18.0)
	for s: Variant in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = TypedVariant.as_dict(s)
		var sid: String = str(entry.get("id", ""))
		var slot_name: String = str(entry.get("name", sid))
		var updated: String = str(entry.get("updated_at", ""))
		## One long parallelogram bar wraps name + time + smaller rename/delete.
		var row: Control = Control.new()
		row.custom_minimum_size = Vector2(0, row_h)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bar: Button = _ParaBtn.new() as Button
		bar.text = "" ## Labels draw name; bar is the long plate + load hit.
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.pressed.connect(_on_load_slot.bind(sid))
		UiAssets.apply_button_font(bar, name_fs)
		row.add_child(bar)
		var overlay: HBoxContainer = HBoxContainer.new()
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.offset_left = pad_x
		overlay.offset_right = -pad_x
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_theme_constant_override("separation", maxi(4, roundi(_menu_px(10.0))))
		overlay.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(overlay)
		var name_lbl: Label = Label.new()
		name_lbl.text = slot_name
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		name_lbl.add_theme_constant_override("outline_size", 2)
		UiAssets.apply_label_font(name_lbl, true, name_fs)
		overlay.add_child(name_lbl)
		var time_lbl: Label = Label.new()
		time_lbl.text = updated if updated != "" else "—"
		time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		time_lbl.custom_minimum_size = Vector2(_menu_px(120.0 if UiLayout.is_mobile() else 150.0), 0)
		time_lbl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94, 0.95))
		UiAssets.apply_label_font(time_lbl, false, time_fs)
		overlay.add_child(time_lbl)
		var rename_btn: Button = _ParaBtn.new() as Button
		rename_btn.text = "重命名"
		rename_btn.custom_minimum_size = Vector2(op_w, op_h)
		rename_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiAssets.apply_button_font(rename_btn, op_fs)
		rename_btn.pressed.connect(_on_rename_open.bind(sid, slot_name))
		var del_btn: Button = _ParaBtn.new() as Button
		del_btn.text = "删除"
		del_btn.custom_minimum_size = Vector2(_menu_px(56.0 if UiLayout.is_mobile() else 64.0), op_h)
		del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiAssets.apply_button_font(del_btn, op_fs)
		del_btn.pressed.connect(_on_delete_slot.bind(sid, slot_name))
		## Visual face gap = L1 row sep (not tertiary 100px / overlay container gap).
		## Same-skew paras: AABB sep = face_gap − skew_dx so faces read as row spacing; keep ≥2px AABB so hits don't stack.
		var face_gap: float = _menu_px(_menu_design_l1_sep())
		var skew_dx: float = op_h / maxf(tan(deg_to_rad(60.0)), 0.01)
		var ops_sep: int = maxi(2, roundi(face_gap - skew_dx))
		var ops: HBoxContainer = HBoxContainer.new()
		ops.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ops.add_theme_constant_override("separation", ops_sep)
		ops.add_child(rename_btn)
		ops.add_child(del_btn)
		overlay.add_child(ops)
		_load_list.add_child(row)
	## End marker — centered small type (UI_AND_SHELL §1.0).
	var eof: Label = Label.new()
	eof.text = "到头了"
	eof.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eof.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eof.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eof.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.75))
	eof.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	eof.add_theme_constant_override("outline_size", 1)
	UiAssets.apply_label_font(eof, false, _menu_font_px(11 if UiLayout.is_mobile() else 12))
	_load_list.add_child(eof)


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
	if _btn_continue:
		_btn_continue.disabled = true


func _refresh_continue_btn() -> void:
	if _btn_continue:
		_btn_continue.disabled = not _usable_local_last_match_exists()
	if _nullsec_lobby and _nullsec_lobby.has_method("refresh_restore_enabled"):
		_nullsec_lobby.call("refresh_restore_enabled")
	if _btn_load:
		_btn_load.disabled = MatchSave.list_slots().is_empty() and not MatchSave.exists()


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


func _on_sfx_toggled(on: bool) -> void:
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps:
		ps.set_sfx_enabled(on)


func _on_sfx_volume_changed(v: float) -> void:
	if _sfx_lbl:
		_sfx_lbl.text = str(int(v))
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps:
		ps.set_sfx_volume_pct(v)

func _on_options_open() -> void:
	_dismiss_branch_for_modal()
	if _options:
		_apply_adaptive_layout()
		_options.visible = true
		if _fps_slider:
			_fps_slider.value = (PlayerSettings.instance() as PlayerSettings).target_fps
		var bgm: BgMusic = _bgm()
		if bgm:
			if _bgm_check:
				_bgm_check.set_pressed_no_signal(bgm.enabled)
			if _bgm_slider:
				_bgm_slider.set_value_no_signal(bgm.volume_pct)
			if _bgm_lbl:
				_bgm_lbl.text = str(int(bgm.volume_pct))
		var ps: PlayerSettings = PlayerSettings.get_or_null()
		if ps:
			if _sfx_check:
				_sfx_check.set_pressed_no_signal(ps.sfx_enabled)
			if _sfx_slider:
				_sfx_slider.set_value_no_signal(ps.sfx_volume_pct)
			if _sfx_lbl:
				_sfx_lbl.text = str(int(ps.sfx_volume_pct))


func _on_dev_debug_open() -> void:
	_dismiss_branch_for_modal()
	if _options:
		_options.visible = false
	_sync_dev_debug_widgets()
	if _dev_panel:
		_apply_adaptive_layout()
		_dev_panel.visible = true


func _sync_dev_debug_widgets() -> void:
	if _dev_master_check:
		_dev_master_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).developer_debug_enabled)
	var master_on: bool = (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	if _dev_soften_check:
		_dev_soften_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).player_citadel_soften)
		_dev_soften_check.disabled = not master_on
	if _dev_economy_check:
		_dev_economy_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).player_ai_double_economy)
		_dev_economy_check.disabled = not master_on
	if _dev_enemy_layout_check:
		_dev_enemy_layout_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).enemy_layout_adjust)
		_dev_enemy_layout_check.disabled = not master_on
	if _dev_ship_data_btn:
		_dev_ship_data_btn.disabled = not master_on


func _on_dev_master_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_developer_debug_enabled(on)
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
	if not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled:
		return
	if _ship_data_editor == null or not is_instance_valid(_ship_data_editor):
		_ship_data_editor = ShipDataEditor.new()
		_ship_data_editor.closed.connect(_on_ship_data_editor_closed)
		add_child(_ship_data_editor)
	_ship_data_editor.z_index = 80
	_ship_data_editor.z_as_relative = false
	_ship_data_editor.mouse_filter = Control.MOUSE_FILTER_STOP
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
	(PlayerSettings.instance() as PlayerSettings).set_player_citadel_soften(on)


func _on_dev_economy_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_player_ai_double_economy(on)


func _on_dev_enemy_layout_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_enemy_layout_adjust(on)


func _on_about_open() -> void:
	_dismiss_branch_for_modal()
	if _about:
		_apply_adaptive_layout()
		_about.visible = true
