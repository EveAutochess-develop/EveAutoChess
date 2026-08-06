extends Control
class_name NullsecRoomUI
## Seat | 功能 | seat | 功能 × 10 rows; short function gutters keep seat bars equal width.

signal leave_room
signal start_match(assignments: Dictionary)

const TITAN_CGMA: Array = [
	{"race": "caldari", "label": "利维坦 · 加达里", "icon": "caldari"},
	{"race": "gallente", "label": "厄勒布洛斯 · 盖伦特", "icon": "gallente"},
	{"race": "minmatar", "label": "诸神黄昏 · 米玛塔尔", "icon": "minmatar"},
	{"race": "amarr", "label": "圣像 · 艾玛", "icon": "amarr"},
]
const KICK_COL_W: float = 56.0

var session: NullsecNetSession
var _grid: GridContainer
var _cells: Array = [] ## seat_id -> PanelContainer
var _kick_btns: Array = [] ## seat_id -> 功能 button (short gutter columns)
var _func_menus: Array = [] ## seat_id -> PopupMenu
var _ready_btn: Button
var _ai_btn: Button
var _sec_opt: OptionButton
var _wait_lbl: Label
var _code_lbl: Label
var _copy_key_btn: Button
var _copy_share_btn: Button
var _ships_lbl: Label
var _mobile_cap: int = 20
var _urge_count: int = 0
var _urge_until_ms: int = 0
var _urge_holding: bool = false

func setup(net: NullsecNetSession) -> void:
	session = net
	session.seat_sync.connect(_on_seats)
	session.match_start.connect(_on_match_start)
	session.ships_mismatch.connect(_on_ships_mismatch)
	if not session.match_loading.is_connected(_on_match_loading):
		session.match_loading.connect(_on_match_loading)
	if not session.security_mode_changed.is_connected(_on_security_mode):
		session.security_mode_changed.connect(_on_security_mode)
	if not session.lobby_notice.is_connected(_on_lobby_notice):
		session.lobby_notice.connect(_on_lobby_notice)
	if not session.urge_prepare_received.is_connected(_on_urge_prepare):
		session.urge_prepare_received.connect(_on_urge_prepare)
	_mobile_cap = 5 if (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()) else 20
	_build()
	_on_seats(session.seats)
	_on_security_mode(session.security_mode)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 1 ## Main-menu announcement is z=8 and remains visible.
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "RoomContent"
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 0.66 if not UiLayout.is_mobile() else 0.96
	root.anchor_bottom = 1.0
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var code_row: HBoxContainer = HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	root.add_child(code_row)
	_code_lbl = Label.new()
	_code_lbl.text = _code_text()
	_code_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_lbl)
	_copy_share_btn = Button.new()
	_copy_share_btn.text = "复制房间码"
	_copy_share_btn.visible = false
	_copy_share_btn.custom_minimum_size = Vector2(108, 30)
	_copy_share_btn.pressed.connect(_copy_room_share)
	code_row.add_child(_copy_share_btn)
	_copy_key_btn = Button.new()
	_copy_key_btn.text = "复制密码"
	_copy_key_btn.visible = false
	_copy_key_btn.custom_minimum_size = Vector2(96, 30)
	_copy_key_btn.pressed.connect(_copy_room_password)
	code_row.add_child(_copy_key_btn)
	_ships_lbl = Label.new()
	_ships_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ships_lbl.modulate = Color(1.0, 0.82, 0.35)
	_ships_lbl.visible = false
	root.add_child(_ships_lbl)
	if session and not session.is_host and session.host_ships_hash != "" \
			and session.host_ships_hash != DataStore.ships_table_hash():
		_on_ships_mismatch(session.host_ships_hash)
	var sec_row: HBoxContainer = HBoxContainer.new()
	sec_row.add_theme_constant_override("separation", 8)
	root.add_child(sec_row)
	var sec_lbl: Label = Label.new()
	sec_lbl.text = "安等"
	sec_row.add_child(sec_lbl)
	_sec_opt = OptionButton.new()
	_sec_opt.custom_minimum_size = Vector2(160, 30)
	_sec_opt.add_item("负安局") ## 0
	_sec_opt.add_item("低安局 · 1v1") ## 1
	_sec_opt.item_selected.connect(_on_sec_selected)
	sec_row.add_child(_sec_opt)
	var sec_tip: Label = Label.new()
	sec_tip.name = "SecTip"
	sec_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_tip.modulate = Color(0.7, 0.78, 0.88, 1.0)
	sec_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec_row.add_child(sec_tip)
	_grid = GridContainer.new()
	## Left seat | 功能 | right seat | 功能 — gutters hold host actions so seat bars match.
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 3)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_grid)
	_cells.clear()
	_cells.resize(20)
	_kick_btns.clear()
	_kick_btns.resize(20)
	_func_menus.clear()
	_func_menus.resize(20)
	for row: int in range(10):
		var left_i: int = row * 2
		var right_i: int = left_i + 1
		var left_cell: PanelContainer = _make_seat_cell(left_i)
		_grid.add_child(left_cell)
		_cells[left_i] = left_cell
		var left_kick: Control = _make_kick_slot(left_i)
		_grid.add_child(left_kick)
		var left_kick_node: Node = left_kick.get_node("Func")
		if left_kick_node is Button:
			_kick_btns[left_i] = left_kick_node
		var left_menu: Node = left_kick.get_node_or_null("FuncMenu")
		if left_menu is PopupMenu:
			_func_menus[left_i] = left_menu
		var right_cell: PanelContainer = _make_seat_cell(right_i)
		_grid.add_child(right_cell)
		_cells[right_i] = right_cell
		var right_kick: Control = _make_kick_slot(right_i)
		_grid.add_child(right_kick)
		var right_kick_node: Node = right_kick.get_node("Func")
		if right_kick_node is Button:
			_kick_btns[right_i] = right_kick_node
		var right_menu: Node = right_kick.get_node_or_null("FuncMenu")
		if right_menu is PopupMenu:
			_func_menus[right_i] = right_menu
	var bar: HBoxContainer = HBoxContainer.new()
	root.add_child(bar)
	_ai_btn = Button.new()
	_ai_btn.text = "加人机"
	_ai_btn.pressed.connect(func() -> void:
		if session:
			session.add_ai_player()
	)
	bar.add_child(_ai_btn)
	_ready_btn = Button.new()
	_ready_btn.text = "准备好了"
	_ready_btn.pressed.connect(_toggle_ready)
	bar.add_child(_ready_btn)
	var leave: Button = Button.new()
	leave.text = "离开房间"
	leave.pressed.connect(func() -> void: leave_room.emit())
	bar.add_child(leave)
	_wait_lbl = Label.new()
	_wait_lbl.name = "ReadyWait"
	_wait_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wait_lbl.modulate = Color(0.75, 0.82, 0.9, 1.0)
	bar.add_child(_wait_lbl)
	set_process(true)

func _code_text() -> String:
	if session == null:
		return "房间"
	var sec: String = "低安" if NullsecNetSession.is_lowsec(session.security_mode) else "负安"
	var verbal: String = "私密房" if (not session.room_password.is_empty() or session.room_has_password) else "公开房"
	## SEMI_ASYNC §7.5 — do not show room_code (internal / may differ after claim).
	return "%s · %s · 版本 %s" % [verbal, sec, session.rules_hash]


func _on_sec_selected(idx: int) -> void:
	if session == null or not session.is_host:
		return
	session.set_security_mode(NullsecNetSession.SECURITY_LOWSEC if idx == 1 else NullsecNetSession.SECURITY_NULLSEC)


func _on_security_mode(mode: String) -> void:
	if _sec_opt == null:
		return
	var low: bool = NullsecNetSession.is_lowsec(mode)
	_sec_opt.set_block_signals(true)
	_sec_opt.select(1 if low else 0)
	_sec_opt.set_block_signals(false)
	_sec_opt.disabled = session == null or not session.is_host or session.match_started
	var tip: Label = null
	var tip_node: Node = get_node_or_null("RoomContent/HBoxContainer/SecTip")
	if tip_node is Label:
		tip = tip_node
	## SecTip lives under the sec_row which has no stable name — find by sibling.
	if tip == null and _sec_opt:
		var row_node: Node = _sec_opt.get_parent()
		if row_node != null:
			var sibling: Node = row_node.get_node_or_null("SecTip")
			if sibling is Label:
				tip = sibling
	if tip:
		tip.text = "低安：开战须恰好 2 人选泰坦 · 多于 2 人则禁准备并清回 · 扣血 −75%" if low else "负安：PVE/PVP 交错 · 星域主场"


func _copy_room_share() -> void:
	if session == null or not session.is_host:
		return
	var blob: String = session.make_invite_blob()
	if blob == "":
		if _wait_lbl:
			_wait_lbl.text = "房间码生成失败"
		return
	DisplayServer.clipboard_set(InviteBlobHelper.format_for_clipboard(blob))
	if _wait_lbl:
		var tip: String = "房间码已复制（EAC+Base62）"
		if NetConnectivity.turn_urls().size() > 0:
			tip += " · 直连失败可回落 TURN"
		elif NetConnectivity.public_stun_enabled():
			tip += " · 已附公共 STUN"
		_wait_lbl.text = tip


func _copy_room_password() -> void:
	if session == null or session.room_password.is_empty():
		return
	var key: String = str(session.room_password).strip_edges()
	if key == "":
		return
	DisplayServer.clipboard_set(key)
	if _wait_lbl:
		_wait_lbl.text = "已复制房间密码"


func _make_kick_slot(seat_idx: int) -> Control:
	## Narrow gutter — host「功能」menu (转移房主 / 踢出 / 催促准备).
	var kick_wrap: CenterContainer = CenterContainer.new()
	kick_wrap.name = "FuncSlot_%02d" % seat_idx
	kick_wrap.custom_minimum_size = Vector2(KICK_COL_W, 34)
	kick_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var kick: Button = Button.new()
	kick.name = "Func"
	kick.text = "功能"
	kick.visible = false
	kick.custom_minimum_size = Vector2(KICK_COL_W, 30)
	var menu: PopupMenu = PopupMenu.new()
	menu.name = "FuncMenu"
	menu.add_item("转移房主", 0)
	menu.add_item("踢出", 1)
	menu.add_item("催促准备", 2)
	kick_wrap.add_child(menu)
	kick.pressed.connect(func() -> void:
		_popup_func_menu(seat_idx, kick, menu)
	)
	menu.id_pressed.connect(func(id: int) -> void:
		_on_func_menu_id(seat_idx, id)
	)
	kick_wrap.add_child(kick)
	return kick_wrap


func _popup_func_menu(seat_idx: int, btn: Button, menu: PopupMenu) -> void:
	if session == null or menu == null or btn == null:
		return
	var row: Dictionary = {}
	if seat_idx >= 0 and seat_idx < session.seats.size():
		row = TypedVariant.as_dict(session.seats[seat_idx])
	var is_ai: bool = TypedVariant.as_bool(row.get("is_ai", false), false)
	var is_ready: bool = TypedVariant.as_bool(row.get("ready", false), false)
	var spectate: bool = NullsecNetSession.is_spectate_race(str(row.get("titan_race", "")))
	## 0 转移房主 — humans only; 1 踢出 — always; 2 催促 — unready contestants.
	menu.set_item_disabled(0, is_ai or session.match_started)
	menu.set_item_disabled(1, false)
	menu.set_item_disabled(2, is_ready or spectate or session.match_started)
	var gp: Vector2 = btn.get_global_rect().position + Vector2(0, btn.size.y)
	menu.position = Vector2i(int(gp.x), int(gp.y))
	menu.popup()


func _on_func_menu_id(seat_idx: int, id: int) -> void:
	if session == null:
		return
	match id:
		0:
			session.transfer_host_to_seat(seat_idx)
		1:
			session.kick_seat(seat_idx)
		2:
			session.urge_prepare(seat_idx)


func _on_lobby_notice(message: String) -> void:
	if _wait_lbl and str(message) != "":
		_wait_lbl.text = str(message)


func _on_urge_prepare() -> void:
	if _wait_lbl == null:
		return
	var now: int = Time.get_ticks_msec()
	if _urge_holding and now < _urge_until_ms:
		_urge_count += 1
	else:
		_urge_count = 1
	_urge_holding = true
	_urge_until_ms = now + 3000
	if _urge_count <= 1:
		_wait_lbl.text = "房主催促准备"
	else:
		_wait_lbl.text = "房主催促准备*%d" % _urge_count


func _process(_delta: float) -> void:
	if not _urge_holding:
		return
	if Time.get_ticks_msec() < _urge_until_ms:
		return
	_urge_holding = false
	_urge_count = 0
	_urge_until_ms = 0
	if session != null:
		_refresh_wait_label(session.seats)


func _make_seat_cell(idx: int) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 34)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	var seat_no: Label = Label.new()
	seat_no.name = "SeatNo"
	seat_no.text = "%02d" % (idx + 1)
	seat_no.custom_minimum_size = Vector2(24, 0)
	row.add_child(seat_no)
	var nick: Label = Label.new()
	nick.name = "Nick"
	nick.text = "空席"
	nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nick.custom_minimum_size = Vector2(72, 0)
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nick)
	var opt: OptionButton = OptionButton.new()
	opt.name = "Titan"
	opt.custom_minimum_size = Vector2(132, 30)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.fit_to_longest_item = false
	opt.add_theme_constant_override("icon_max_width", 20)
	## PopupMenu has its own theme context; cap its otherwise full-size option icons.
	opt.get_popup().add_theme_constant_override("icon_max_width", 20)
	opt.add_item("选择泰坦或观战") ## index 0 = unset
	for t_v: Variant in TITAN_CGMA:
		if not (t_v is Dictionary):
			continue
		var t: Dictionary = t_v
		var race: String = str(t.get("race", ""))
		## Prefer race icon; tips skybox is the option-row / button panel decoration (§2.2.1).
		var icon_path: String = "res://assets/ui/race_icons/%s.png" % str(t.get("icon", ""))
		var tex: Texture2D = null
		if ResourceLoader.exists(icon_path):
			var loaded: Variant = load(icon_path)
			if loaded is Texture2D:
				tex = loaded
		if tex == null:
			tex = UiAssets.race_tips_skybox(race)
		if tex:
			opt.add_icon_item(tex, str(t.get("label", "")))
		else:
			opt.add_item(str(t.get("label", "")))
	opt.add_item("仅观战") ## last index
	opt.select(0)
	_apply_titan_opt_tips(opt, "")
	opt.item_selected.connect(func(i: int) -> void:
		if session == null:
			return
		var pick_race: String = _race_from_opt_index(i)
		_apply_titan_opt_tips(opt, pick_race if NullsecNetSession.is_player_race(pick_race) else "")
		if session.local_seat == idx:
			session.set_local_titan(pick_race)
		elif session.is_host:
			session.set_seat_titan(idx, pick_race)
	)
	row.add_child(opt)
	var slash: ColorRect = ColorRect.new()
	slash.name = "Slash"
	slash.color = Color(0.8, 0.2, 0.2, 0.55)
	slash.visible = false ## All 20 seats joinable; player_cap gates titan pick, not seat occupancy.
	slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(slash)
	return panel

func _race_from_opt_index(i: int) -> String:
	if i <= 0:
		return ""
	if i >= 1 and i <= TITAN_CGMA.size():
		var entry_v: Variant = TITAN_CGMA[i - 1]
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			return str(entry.get("race", ""))
		return ""
	return NullsecNetSession.TITAN_RACE_SPECTATE

func _opt_index_from_race(race: String) -> int:
	if NullsecNetSession.is_spectate_race(race):
		return TITAN_CGMA.size() + 1
	for ti: int in range(TITAN_CGMA.size()):
		var entry_v: Variant = TITAN_CGMA[ti]
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			if str(entry.get("race", "")) == race:
				return ti + 1
	return 0

func _on_seats(seats: Array) -> void:
	_code_lbl.text = _code_text()
	if _copy_share_btn:
		_copy_share_btn.visible = session != null and session.is_host
	if _copy_key_btn:
		_copy_key_btn.visible = session != null and session.is_host and not session.room_password.is_empty()
	_ai_btn.visible = session != null and session.is_host and not session.match_started
	_on_security_mode(session.security_mode if session else NullsecNetSession.SECURITY_NULLSEC)
	var local_race: String = ""
	var local_ready: bool = false
	if session != null and session.local_seat >= 0 and session.local_seat < seats.size():
		var local_v: Variant = seats[session.local_seat]
		if local_v is Dictionary:
			var local_d: Dictionary = local_v
			local_race = str(local_d.get("titan_race", ""))
			local_ready = TypedVariant.as_bool(local_d.get("ready", false), false)
	var local_is_player: bool = NullsecNetSession.is_player_race(local_race)
	var local_is_spec: bool = NullsecNetSession.is_spectate_race(local_race)
	var ready_blocked: bool = session != null and session.lowsec_ready_blocked()
	## Ready only for players who picked a titan; spectators are auto-ready.
	## Lowsec with >2 titan picks: button disabled; session already cleared ready.
	_ready_btn.visible = not local_is_spec
	_ready_btn.disabled = session == null or session.local_seat < 0 or not local_is_player or ready_blocked
	_ready_btn.text = "取消准备" if local_ready and not ready_blocked else "准备好了"
	if ready_blocked:
		_ready_btn.tooltip_text = "低安局仅 1v1：请多余席改为仅观战后再准备"
	elif local_is_player:
		_ready_btn.tooltip_text = ""
	else:
		_ready_btn.tooltip_text = "请先选择泰坦"
	_refresh_wait_label(seats)
	for i: int in range(mini(20, seats.size())):
		var s_v: Variant = seats[i]
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v
		var panel_v: Variant = _cells[i]
		if not (panel_v is PanelContainer):
			continue
		var panel: PanelContainer = panel_v
		var row_node: Node = panel.get_node("Row")
		if not (row_node is HBoxContainer):
			continue
		var row: HBoxContainer = row_node
		var nick_node: Node = row.get_node("Nick")
		if not (nick_node is Label):
			continue
		var nick: Label = nick_node
		var opt_node: Node = row.get_node("Titan")
		if not (opt_node is OptionButton):
			continue
		var opt: OptionButton = opt_node
		var slash_node: Node = panel.get_node("Slash")
		if not (slash_node is ColorRect):
			continue
		var slash: ColorRect = slash_node
		slash.visible = false
		var occupied: bool = TypedVariant.as_bool(s.get("occupied", false), false)
		var is_ai: bool = TypedVariant.as_bool(s.get("is_ai", false), false)
		## Own seat, or host editing an AI seat.
		var can_edit_titan: bool = occupied and (
			session.local_seat == i or (session.is_host and is_ai)
		) and not session.match_started
		opt.disabled = not can_edit_titan
		var can_kick: bool = session != null and session.is_host and occupied \
				and i != session.local_seat and not TypedVariant.as_bool(s.get("ghost", false), false)
		if i < _kick_btns.size() and _kick_btns[i] != null:
			var kb_v: Variant = _kick_btns[i]
			if kb_v is Button:
				var kb: Button = kb_v
				kb.visible = can_kick
		if not occupied:
			nick.text = "空席"
			opt.set_block_signals(true)
			opt.select(0)
			opt.set_block_signals(false)
			## Kick / leave must drop tips_skybox panel fill (otherwise starfield lingers).
			_apply_titan_opt_tips(opt, "")
			continue
		var race: String = str(s.get("titan_race", ""))
		var mark: String = "✓" if TypedVariant.as_bool(s.get("ready", false), false) else "…"
		if NullsecNetSession.is_spectate_race(race):
			mark = "观"
		var ai: String = " [人机]" if is_ai else ""
		var ghost: String = "（分身）" if TypedVariant.as_bool(s.get("ghost", false), false) else ""
		var raw_nick: String = str(s.get("nick", ""))
		var shown: String = NickCodec.display_short(raw_nick)
		var rtt: int = TypedVariant.as_int(s.get("rtt_ms", -1), -1)
		var rtt_s: String = ""
		if not is_ai:
			rtt_s = " —" if rtt < 0 else (" %dms" % rtt)
		nick.text = "%s%s%s%s %s" % [shown, rtt_s, ai, ghost, mark]
		nick.tooltip_text = NickCodec.tooltip_full(raw_nick)
		var sel: int = _opt_index_from_race(race)
		opt.set_block_signals(true)
		opt.select(sel)
		opt.set_block_signals(false)
		_apply_titan_opt_tips(opt, race if NullsecNetSession.is_player_race(race) else "")

func _apply_titan_opt_tips(opt: OptionButton, race: String) -> void:
	## MULTIPLAYER_PVP §2.2.1: selected titan option shows that race's tips_*01 as panel fill.
	if opt == null:
		return
	var tips: Texture2D = UiAssets.race_tips_skybox(race) if race != "" else null
	if tips == null:
		opt.remove_theme_stylebox_override("normal")
		opt.remove_theme_stylebox_override("hover")
		opt.remove_theme_stylebox_override("pressed")
		opt.remove_theme_stylebox_override("disabled")
		return
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = tips
	sb.set_content_margin_all(4)
	## Keep source alpha fade — no opaque tint plate behind tips.
	sb.modulate_color = Color(1, 1, 1, 1)
	opt.add_theme_stylebox_override("normal", sb)
	opt.add_theme_stylebox_override("hover", sb)
	opt.add_theme_stylebox_override("pressed", sb)
	opt.add_theme_stylebox_override("disabled", sb)

func _refresh_wait_label(seats: Array) -> void:
	if _wait_lbl == null:
		return
	var players: int = 0
	var ready_n: int = 0
	var specs: int = 0
	var blocking: PackedStringArray = PackedStringArray()
	for s_v: Variant in seats:
		if not (s_v is Dictionary):
			continue
		var d: Dictionary = s_v
		if not TypedVariant.as_bool(d.get("occupied", false), false):
			continue
		var nick: String = str(d.get("nick", "?"))
		var race: String = str(d.get("titan_race", ""))
		if NullsecNetSession.is_spectate_race(race):
			specs += 1
			continue
		players += 1
		var is_ready: bool = TypedVariant.as_bool(d.get("ready", false), false)
		if NullsecNetSession.is_player_race(race) and is_ready:
			ready_n += 1
		elif not NullsecNetSession.is_player_race(race):
			blocking.append("%s未选" % nick)
		else:
			blocking.append("%s未准备" % nick)
	var cap: int = session.effective_player_cap() if session else 20
	var low: bool = session != null and NullsecNetSession.is_lowsec(session.security_mode)
	if players <= 0:
		_wait_lbl.text = "等待参赛玩家选泰坦" if specs > 0 else ""
		MatchLoadOverlay.hide_overlay()
		return
	if low and players > 2:
		_wait_lbl.text = "低安仅 1v1 · 已有 %d 人选泰坦 · 准备已锁定，请多余席改观战" % players
		MatchLoadOverlay.hide_overlay()
		return
	if ready_n >= players and players >= 2 and (not low or players == 2):
		_wait_lbl.text = "参赛已准备 %d/%d · 即将开局" % [ready_n, players]
		MatchLoadOverlay.set_phase("即将开局…", 0.02)
		return
	MatchLoadOverlay.hide_overlay()
	var tip: String = "、".join(blocking)
	if tip.length() > 48:
		tip = tip.substr(0, 46) + "…"
	var extra: String = " · 观战 %d" % specs if specs > 0 else ""
	var cap_tip: String = " · 上限 %d" % cap
	_wait_lbl.text = "已准备 %d/%d%s%s · %s" % [ready_n, players, cap_tip, extra, tip]


## SEMI_ASYNC_NETPLAY §3.7 — warn only; the host table arrives when the match starts.
func _on_ships_mismatch(host_hash: String) -> void:
	if _ships_lbl == null:
		return
	_ships_lbl.text = "全舰船数据与房主不一致（房主 %s）· 进入对局后将临时使用（不覆盖本地）" % host_hash.substr(0, 8)
	_ships_lbl.visible = true


func _toggle_ready() -> void:
	if session == null or session.local_seat < 0:
		return
	var seat_v: Variant = session.seats[session.local_seat]
	if not (seat_v is Dictionary):
		return
	var seat_d: Dictionary = seat_v
	if not NullsecNetSession.is_player_race(str(seat_d.get("titan_race", ""))):
		return
	if session.lowsec_ready_blocked():
		return
	var cur: bool = TypedVariant.as_bool(seat_d.get("ready", false), false)
	session.set_local_ready(not cur)

func _on_match_loading(phase: String, progress: float) -> void:
	MatchLoadOverlay.set_phase(phase, progress)


func _on_match_start(payload: Dictionary) -> void:
	## Guest pull copy must stay readable; do not cover with「进入对局场景」before ships land.
	if session != null and not session.is_host and session.opening_host_ships.is_empty():
		MatchLoadOverlay.set_phase("正在从房主拉取全舰船与全游戏数据", 0.16)
	else:
		MatchLoadOverlay.set_phase("正在进入对局场景", 0.25)
	var rng: MatchRng = MatchRng.new()
	rng.configure(TypedVariant.as_int(payload.get("match_seed", 1), 1), str(payload.get("rules_hash", "")))
	var dir: NullsecMatchDirector = NullsecMatchDirector.new()
	dir.setup(rng)
	dir.set_seats(TypedVariant.as_array(payload.get("seats", [])))
	var sec: String = str(payload.get("security_mode", session.security_mode if session else "nullsec"))
	var asg: Dictionary = dir.assign_regions(sec)
	if session:
		session.store_match_assignments(asg)
	start_match.emit(asg)
