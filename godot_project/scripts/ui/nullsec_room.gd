extends Control
class_name NullsecRoomUI
## Seat | kick | seat | kick × 10 rows; short kick gutters keep seat bars equal width.

signal leave_room
signal start_match(assignments: Dictionary)

const TITAN_CGMA := [
	{"race": "caldari", "label": "利维坦 · 加达里", "icon": "caldari"},
	{"race": "gallente", "label": "厄勒布洛斯 · 盖伦特", "icon": "gallente"},
	{"race": "minmatar", "label": "诸神黄昏 · 米玛塔尔", "icon": "minmatar"},
	{"race": "amarr", "label": "圣像 · 艾玛", "icon": "amarr"},
]
const KICK_COL_W := 48.0

var session: NullsecNetSession
var _grid: GridContainer
var _cells: Array = [] ## seat_id -> PanelContainer
var _kick_btns: Array = [] ## seat_id -> Kick button (short gutter columns)
var _ready_btn: Button
var _ai_btn: Button
var _sec_opt: OptionButton
var _wait_lbl: Label
var _code_lbl: Label
var _copy_key_btn: Button
var _ships_lbl: Label
var _mobile_cap: int = 20

func setup(net: NullsecNetSession) -> void:
	session = net
	session.seat_sync.connect(_on_seats)
	session.match_start.connect(_on_match_start)
	session.ships_mismatch.connect(_on_ships_mismatch)
	if not session.security_mode_changed.is_connected(_on_security_mode):
		session.security_mode_changed.connect(_on_security_mode)
	_mobile_cap = 5 if (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()) else 20
	_build()
	_on_seats(session.seats)
	_on_security_mode(session.security_mode)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 1 ## Main-menu announcement is z=8 and remains visible.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
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
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	root.add_child(code_row)
	_code_lbl = Label.new()
	_code_lbl.text = _code_text()
	_code_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_lbl)
	_copy_key_btn = Button.new()
	_copy_key_btn.text = "复制秘钥"
	_copy_key_btn.visible = false
	_copy_key_btn.custom_minimum_size = Vector2(96, 30)
	_copy_key_btn.pressed.connect(_copy_private_key)
	code_row.add_child(_copy_key_btn)
	_ships_lbl = Label.new()
	_ships_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ships_lbl.modulate = Color(1.0, 0.82, 0.35)
	_ships_lbl.visible = false
	root.add_child(_ships_lbl)
	if session and not session.is_host and session.host_ships_hash != "" \
			and session.host_ships_hash != DataStore.ships_table_hash():
		_on_ships_mismatch(session.host_ships_hash)
	var sec_row := HBoxContainer.new()
	sec_row.add_theme_constant_override("separation", 8)
	root.add_child(sec_row)
	var sec_lbl := Label.new()
	sec_lbl.text = "安等"
	sec_row.add_child(sec_lbl)
	_sec_opt = OptionButton.new()
	_sec_opt.custom_minimum_size = Vector2(160, 30)
	_sec_opt.add_item("负安局") ## 0
	_sec_opt.add_item("低安局 · 1v1") ## 1
	_sec_opt.item_selected.connect(_on_sec_selected)
	sec_row.add_child(_sec_opt)
	var sec_tip := Label.new()
	sec_tip.name = "SecTip"
	sec_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_tip.modulate = Color(0.7, 0.78, 0.88, 1.0)
	sec_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec_row.add_child(sec_tip)
	_grid = GridContainer.new()
	## Left seat | short kick | right seat | short kick — gutters hold 踢出 so seat bars match.
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
	for row in range(10):
		var left_i := row * 2
		var right_i := left_i + 1
		var left_cell := _make_seat_cell(left_i)
		_grid.add_child(left_cell)
		_cells[left_i] = left_cell
		var left_kick := _make_kick_slot(left_i)
		_grid.add_child(left_kick)
		_kick_btns[left_i] = left_kick.get_node("Kick") as Button
		var right_cell := _make_seat_cell(right_i)
		_grid.add_child(right_cell)
		_cells[right_i] = right_cell
		var right_kick := _make_kick_slot(right_i)
		_grid.add_child(right_kick)
		_kick_btns[right_i] = right_kick.get_node("Kick") as Button
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_ai_btn = Button.new()
	_ai_btn.text = "加人机"
	_ai_btn.pressed.connect(func():
		if session:
			session.add_ai_player()
	)
	bar.add_child(_ai_btn)
	_ready_btn = Button.new()
	_ready_btn.text = "准备好了"
	_ready_btn.pressed.connect(_toggle_ready)
	bar.add_child(_ready_btn)
	_wait_lbl = Label.new()
	_wait_lbl.name = "ReadyWait"
	_wait_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wait_lbl.modulate = Color(0.75, 0.82, 0.9, 1.0)
	bar.add_child(_wait_lbl)
	var leave := Button.new()
	leave.text = "离开房间"
	leave.pressed.connect(func(): leave_room.emit())
	bar.add_child(leave)

func _code_text() -> String:
	if session == null:
		return "房间"
	var sec := "低安" if NullsecNetSession.is_lowsec(session.security_mode) else "负安"
	if session.is_private:
		return "私密房 · %s · %s · 版本 %s" % [session.private_code, sec, session.rules_hash]
	return "公开房 · %04d · %s · 版本 %s" % [session.room_code, sec, session.rules_hash]


func _on_sec_selected(idx: int) -> void:
	if session == null or not session.is_host:
		return
	session.set_security_mode(NullsecNetSession.SECURITY_LOWSEC if idx == 1 else NullsecNetSession.SECURITY_NULLSEC)


func _on_security_mode(mode: String) -> void:
	if _sec_opt == null:
		return
	var low := NullsecNetSession.is_lowsec(mode)
	_sec_opt.set_block_signals(true)
	_sec_opt.select(1 if low else 0)
	_sec_opt.set_block_signals(false)
	_sec_opt.disabled = session == null or not session.is_host or session.match_started
	var tip := get_node_or_null("RoomContent/HBoxContainer/SecTip") as Label
	## SecTip lives under the sec_row which has no stable name — find by sibling.
	if tip == null and _sec_opt:
		var row := _sec_opt.get_parent()
		if row:
			tip = row.get_node_or_null("SecTip") as Label
	if tip:
		tip.text = "低安：开战须恰好 2 人选泰坦 · 多于 2 人则禁准备并清回 · 扣血 −75%" if low else "负安：PVE/PVP 交错 · 星域主场"


func _copy_private_key() -> void:
	if session == null or not session.is_private:
		return
	var key := str(session.private_code).strip_edges()
	if key == "":
		return
	DisplayServer.clipboard_set(key)
	if _wait_lbl:
		_wait_lbl.text = "已复制秘钥 %s" % key


func _make_kick_slot(seat_idx: int) -> Control:
	## Narrow gutter — keeps seat bars free of the kick button so host/guest rows align.
	var wrap := CenterContainer.new()
	wrap.name = "KickSlot_%02d" % seat_idx
	wrap.custom_minimum_size = Vector2(KICK_COL_W, 34)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var kick := Button.new()
	kick.name = "Kick"
	kick.text = "踢"
	kick.visible = false
	kick.custom_minimum_size = Vector2(KICK_COL_W, 30)
	kick.pressed.connect(func():
		if session:
			session.kick_seat(seat_idx)
	)
	wrap.add_child(kick)
	return wrap


func _make_seat_cell(idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 34)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	var seat_no := Label.new()
	seat_no.name = "SeatNo"
	seat_no.text = "%02d" % (idx + 1)
	seat_no.custom_minimum_size = Vector2(24, 0)
	row.add_child(seat_no)
	var nick := Label.new()
	nick.name = "Nick"
	nick.text = "空席"
	nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nick.custom_minimum_size = Vector2(72, 0)
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nick)
	var opt := OptionButton.new()
	opt.name = "Titan"
	opt.custom_minimum_size = Vector2(132, 30)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.fit_to_longest_item = false
	opt.add_theme_constant_override("icon_max_width", 20)
	## PopupMenu has its own theme context; cap its otherwise full-size option icons.
	opt.get_popup().add_theme_constant_override("icon_max_width", 20)
	opt.add_item("选择泰坦或观战") ## index 0 = unset
	for t in TITAN_CGMA:
		var race := str(t["race"])
		## Prefer race icon; tips skybox is the option-row / button panel decoration (§2.2.1).
		var icon_path := "res://assets/ui/race_icons/%s.png" % t["icon"]
		var tex: Texture2D = null
		if ResourceLoader.exists(icon_path):
			tex = load(icon_path) as Texture2D
		if tex == null:
			tex = UiAssets.race_tips_skybox(race)
		if tex:
			opt.add_icon_item(tex, str(t["label"]))
		else:
			opt.add_item(str(t["label"]))
	opt.add_item("仅观战") ## last index
	opt.select(0)
	_apply_titan_opt_tips(opt, "")
	opt.item_selected.connect(func(i: int):
		if session == null:
			return
		var race := _race_from_opt_index(i)
		_apply_titan_opt_tips(opt, race if NullsecNetSession.is_player_race(race) else "")
		if session.local_seat == idx:
			session.set_local_titan(race)
		elif session.is_host:
			session.set_seat_titan(idx, race)
	)
	row.add_child(opt)
	var slash := ColorRect.new()
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
		return str(TITAN_CGMA[i - 1]["race"])
	return NullsecNetSession.TITAN_RACE_SPECTATE

func _opt_index_from_race(race: String) -> int:
	if NullsecNetSession.is_spectate_race(race):
		return TITAN_CGMA.size() + 1
	for ti in range(TITAN_CGMA.size()):
		if str(TITAN_CGMA[ti]["race"]) == race:
			return ti + 1
	return 0

func _on_seats(seats: Array) -> void:
	_code_lbl.text = _code_text()
	if _copy_key_btn:
		_copy_key_btn.visible = session != null and session.is_private and str(session.private_code) != ""
	_ai_btn.visible = session != null and session.is_host and not session.match_started
	_on_security_mode(session.security_mode if session else NullsecNetSession.SECURITY_NULLSEC)
	var local_race := ""
	var local_ready := false
	if session != null and session.local_seat >= 0 and session.local_seat < seats.size():
		local_race = str(seats[session.local_seat].get("titan_race", ""))
		local_ready = bool(seats[session.local_seat].get("ready", false))
	var local_is_player := NullsecNetSession.is_player_race(local_race)
	var local_is_spec := NullsecNetSession.is_spectate_race(local_race)
	var ready_blocked := session != null and session.lowsec_ready_blocked()
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
	for i in range(mini(20, seats.size())):
		var s: Dictionary = seats[i]
		var panel: PanelContainer = _cells[i]
		var row := panel.get_node("Row") as HBoxContainer
		var nick := row.get_node("Nick") as Label
		var opt := row.get_node("Titan") as OptionButton
		var slash: ColorRect = panel.get_node("Slash") as ColorRect
		slash.visible = false
		var occupied := bool(s.get("occupied", false))
		var is_ai := bool(s.get("is_ai", false))
		## Own seat, or host editing an AI seat.
		var can_edit_titan := occupied and (
			session.local_seat == i or (session.is_host and is_ai)
		) and not session.match_started
		opt.disabled = not can_edit_titan
		var can_kick := session != null and session.is_host and occupied \
				and i != session.local_seat and not bool(s.get("ghost", false))
		if i < _kick_btns.size() and _kick_btns[i] != null:
			(_kick_btns[i] as Button).visible = can_kick
		if not occupied:
			nick.text = "空席"
			opt.set_block_signals(true)
			opt.select(0)
			opt.set_block_signals(false)
			## Kick / leave must drop tips_skybox panel fill (otherwise starfield lingers).
			_apply_titan_opt_tips(opt, "")
			continue
		var race := str(s.get("titan_race", ""))
		var mark := "✓" if bool(s.get("ready", false)) else "…"
		if NullsecNetSession.is_spectate_race(race):
			mark = "观"
		var ai := " [人机]" if is_ai else ""
		var ghost := "（分身）" if bool(s.get("ghost", false)) else ""
		nick.text = "%s%s%s %s" % [str(s.get("nick", "")), ai, ghost, mark]
		var sel := _opt_index_from_race(race)
		opt.set_block_signals(true)
		opt.select(sel)
		opt.set_block_signals(false)
		_apply_titan_opt_tips(opt, race if NullsecNetSession.is_player_race(race) else "")

func _apply_titan_opt_tips(opt: OptionButton, race: String) -> void:
	## MULTIPLAYER_PVP §2.2.1: selected titan option shows that race's tips_*01 as panel fill.
	if opt == null:
		return
	var tips := UiAssets.race_tips_skybox(race) if race != "" else null
	if tips == null:
		opt.remove_theme_stylebox_override("normal")
		opt.remove_theme_stylebox_override("hover")
		opt.remove_theme_stylebox_override("pressed")
		opt.remove_theme_stylebox_override("disabled")
		return
	var sb := StyleBoxTexture.new()
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
	var players := 0
	var ready_n := 0
	var specs := 0
	var blocking: PackedStringArray = []
	for s in seats:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		if not bool(d.get("occupied", false)):
			continue
		var nick := str(d.get("nick", "?"))
		var race := str(d.get("titan_race", ""))
		if NullsecNetSession.is_spectate_race(race):
			specs += 1
			continue
		players += 1
		var is_ready := bool(d.get("ready", false))
		if NullsecNetSession.is_player_race(race) and is_ready:
			ready_n += 1
		elif not NullsecNetSession.is_player_race(race):
			blocking.append("%s未选" % nick)
		else:
			blocking.append("%s未准备" % nick)
	var cap := session.effective_player_cap() if session else 20
	var low := session != null and NullsecNetSession.is_lowsec(session.security_mode)
	if players <= 0:
		_wait_lbl.text = "等待参赛玩家选泰坦" if specs > 0 else ""
		return
	if low and players > 2:
		_wait_lbl.text = "低安仅 1v1 · 已有 %d 人选泰坦 · 准备已锁定，请多余席改观战" % players
		return
	if ready_n >= players and players >= 2 and (not low or players == 2):
		_wait_lbl.text = "参赛已准备 %d/%d · 即将开局" % [ready_n, players]
		return
	var tip := "、".join(blocking)
	if tip.length() > 48:
		tip = tip.substr(0, 46) + "…"
	var extra := " · 观战 %d" % specs if specs > 0 else ""
	var cap_tip := " · 上限 %d" % cap
	_wait_lbl.text = "已准备 %d/%d%s%s · %s" % [ready_n, players, cap_tip, extra, tip]


## SEMI_ASYNC_NETPLAY §3.7 — warn only; the host table arrives when the match starts.
func _on_ships_mismatch(host_hash: String) -> void:
	if _ships_lbl == null:
		return
	_ships_lbl.text = "全舰船数据与房主不一致（房主 %s）· 进入对局后将临时应用房主舰船数据" % host_hash.substr(0, 8)
	_ships_lbl.visible = true


func _toggle_ready() -> void:
	if session == null or session.local_seat < 0:
		return
	if not NullsecNetSession.is_player_race(str(session.seats[session.local_seat].get("titan_race", ""))):
		return
	if session.lowsec_ready_blocked():
		return
	var cur := bool(session.seats[session.local_seat].get("ready", false))
	session.set_local_ready(not cur)

func _on_match_start(payload: Dictionary) -> void:
	var rng := MatchRng.new()
	rng.configure(int(payload.get("match_seed", 1)), str(payload.get("rules_hash", "")))
	var dir := NullsecMatchDirector.new()
	dir.setup(rng)
	dir.set_seats(payload.get("seats", []) as Array)
	var sec := str(payload.get("security_mode", session.security_mode if session else "nullsec"))
	var asg := dir.assign_regions(sec)
	if session:
		session.store_match_assignments(asg)
	start_match.emit(asg)
