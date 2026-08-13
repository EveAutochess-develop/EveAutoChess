extends Control
## Inline multipath lobby for main-menu 联机二级 (no AcceptDialog, no scroll).
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

const _ParaBtn: Script = preload("res://scripts/ui/menu_parallelogram_button.gd")

signal request_match_public
signal request_host_room(password: String)
signal request_join_share(share: String)
signal request_restore_room

const NICK_CFG := "user://player_settings.cfg"
const NICK_SECTION := "nullsec"
const NICK_KEY := "nick"
const ENUM_CURSOR_KEY := "public_enum_cursor"
const ENUM_DIR_KEY := "public_enum_dir"
const IGNORE_IN_MATCH_KEY := "ignore_in_match"

var _nick: LineEdit
var _password_edit: LineEdit
var _share_edit: LineEdit
var _status_a: Label
var _status_b: Label
var _ignore_in_match: CheckBox
var _restore_btn: Button
var _box: VBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	## One-shot layout — no ScrollContainer (UI_AND_SHELL §1.0a).
	_box = VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Pass empty band through; action buttons / edits own the hits.
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Default; main_menu.apply_layout_metrics overrides to L1 separation.
	_box.add_theme_constant_override("separation", 20)
	add_child(_box)

	var nick_lbl := Label.new()
	nick_lbl.text = "昵称（可含数字与符号，最多 50 字）"
	nick_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	nick_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	nick_lbl.add_theme_constant_override("outline_size", 2)
	_box.add_child(nick_lbl)
	_nick = LineEdit.new()
	_nick.placeholder_text = "克隆人棋手…"
	_nick.max_length = NickCodec.MAX_LEN
	_nick.text = _ensure_default_nick()
	_box.add_child(_nick)

	_add_action_btn("匹配房间", func():
		if _gate_nick():
			request_match_public.emit()
	)
	var ignore_row := HBoxContainer.new()
	ignore_row.name = "IgnoreRow"
	ignore_row.alignment = BoxContainer.ALIGNMENT_END
	ignore_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(ignore_row)
	var ignore_pad := Control.new()
	ignore_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ignore_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ignore_row.add_child(ignore_pad)
	_ignore_in_match = CheckBox.new()
	_ignore_in_match.text = "忽视已开局房间"
	_ignore_in_match.button_pressed = _load_ignore_in_match()
	_ignore_in_match.toggled.connect(func(on: bool): _save_ignore_in_match(on))
	_ignore_in_match.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiAssets.apply_button_font(_ignore_in_match, 14)
	_ignore_in_match.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_ignore_in_match.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	_ignore_in_match.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.75, 1))
	_style_ignore_checkbox(_ignore_in_match)
	ignore_row.add_child(_ignore_in_match)

	var pw_lbl := Label.new()
	pw_lbl.text = "房间密码（不设密码则为公开房间，路人可匹进来）"
	pw_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pw_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	pw_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	pw_lbl.add_theme_constant_override("outline_size", 2)
	_box.add_child(pw_lbl)
	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "可选 4～8 位"
	_password_edit.secret = true
	_password_edit.max_length = 8
	_box.add_child(_password_edit)

	_add_action_btn("主持房间", func():
		if _gate_nick():
			request_host_room.emit(_password_edit.text.strip_edges())
	)

	var share_row := HBoxContainer.new()
	share_row.name = "ShareRow"
	share_row.add_theme_constant_override("separation", 6)
	_box.add_child(share_row)
	_share_edit = LineEdit.new()
	_share_edit.placeholder_text = "粘贴房间码 EAC…"
	_share_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_edit.text_changed.connect(_on_share_text_changed)
	share_row.add_child(_share_edit)
	var join_btn: Button = _make_para_btn("加入")
	join_btn.pressed.connect(func():
		if _gate_nick():
			request_join_share.emit(InviteBlobHelper.sanitize_paste(_share_edit.text))
	)
	share_row.add_child(join_btn)

	_restore_btn = _add_action_btn("快捷恢复房间连接", func(): request_restore_room.emit())
	## 「多人联机历史战绩」在联机底框外（main_menu OnlineSecondaryRoot），不在此列。
	_refresh_restore_enabled()

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(status_row)
	_status_a = Label.new()
	_status_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_a.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0, 1))
	_status_a.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_status_a.add_theme_constant_override("outline_size", 2)
	status_row.add_child(_status_a)
	_status_b = Label.new()
	_status_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_b.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0, 1))
	_status_b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_status_b.add_theme_constant_override("outline_size", 2)
	status_row.add_child(_status_b)
	set_status("")

func _get_minimum_size() -> Vector2:
	if _box != null and is_instance_valid(_box):
		return _box.get_combined_minimum_size()
	return Vector2(240, 320)

func content_min_size() -> Vector2:
	return _get_minimum_size()

func history_button() -> Button:
	## Deprecated — history is outside chrome; main_menu owns the button.
	return null

func _style_ignore_checkbox(cb: CheckBox) -> void:
	## Rounded deep-black check plate (UI_AND_SHELL §1.0).
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	cb.add_theme_stylebox_override("normal", empty)
	cb.add_theme_stylebox_override("pressed", empty)
	cb.add_theme_stylebox_override("hover", empty)
	cb.add_theme_stylebox_override("hover_pressed", empty)
	cb.add_theme_stylebox_override("disabled", empty)
	cb.add_theme_stylebox_override("focus", empty)
	var px: int = 20
	cb.add_theme_icon_override("unchecked", _rounded_check_icon(false, px))
	cb.add_theme_icon_override("checked", _rounded_check_icon(true, px))
	cb.add_theme_icon_override("unchecked_disabled", _rounded_check_icon(false, px))
	cb.add_theme_icon_override("checked_disabled", _rounded_check_icon(true, px))
	cb.add_theme_constant_override("h_separation", 8)

func _rounded_check_icon(checked: bool, px: int) -> ImageTexture:
	var img: Image = Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var radius: int = 4
	var dark: Color = Color(0.04, 0.04, 0.05, 1.0)
	var edge: Color = Color(0.14, 0.14, 0.16, 1.0)
	for y: int in range(px):
		for x: int in range(px):
			if not _point_in_rounded_square(x, y, px, radius):
				continue
			var border: bool = not _point_in_rounded_square(x - 1, y, px, radius) \
				or not _point_in_rounded_square(x + 1, y, px, radius) \
				or not _point_in_rounded_square(x, y - 1, px, radius) \
				or not _point_in_rounded_square(x, y + 1, px, radius)
			img.set_pixel(x, y, edge if border else dark)
	if checked:
		var tick: Color = Color(0.92, 0.94, 0.98, 1.0)
		var pts: Array[Vector2i] = [
			Vector2i(4, 10), Vector2i(5, 11), Vector2i(6, 12), Vector2i(7, 13),
			Vector2i(8, 12), Vector2i(9, 11), Vector2i(10, 10), Vector2i(11, 9),
			Vector2i(12, 8), Vector2i(13, 7), Vector2i(14, 6),
			Vector2i(5, 10), Vector2i(6, 11), Vector2i(7, 12),
			Vector2i(8, 11), Vector2i(9, 10), Vector2i(10, 9), Vector2i(11, 8),
			Vector2i(12, 7), Vector2i(13, 6),
		]
		for p: Vector2i in pts:
			if p.x >= 0 and p.y >= 0 and p.x < px and p.y < px:
				img.set_pixel(p.x, p.y, tick)
	return ImageTexture.create_from_image(img)

func _point_in_rounded_square(x: int, y: int, side: int, radius: int) -> bool:
	if side <= 0 or x < 0 or y < 0 or x >= side or y >= side:
		return false
	var r: int = mini(radius, side / 2)
	if x >= r and x < side - r:
		return true
	if y >= r and y < side - r:
		return true
	var cx: int = r if x < r else side - 1 - r
	var cy: int = r if y < r else side - 1 - r
	var dx: int = x - cx
	var dy: int = y - cy
	return dx * dx + dy * dy <= r * r

## btn_h: match LineEdit to action-button height; row_sep: same as main-menu L1 Buttons.
func apply_layout_metrics(btn_h: float, row_sep: int) -> void:
	if _box:
		_box.add_theme_constant_override("separation", row_sep)
	var h: float = maxf(btn_h, 1.0)
	for edit: LineEdit in [_nick, _password_edit, _share_edit]:
		if edit == null:
			continue
		edit.custom_minimum_size = Vector2(0, h)
	var share_row: HBoxContainer = null
	if _box:
		share_row = _box.get_node_or_null("ShareRow") as HBoxContainer
	if share_row:
		share_row.custom_minimum_size = Vector2(0, h)
		for ch: Node in share_row.get_children():
			if ch is Control:
				var c: Control = ch as Control
				c.custom_minimum_size = Vector2(c.custom_minimum_size.x, h)
				if ch is Button:
					c.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _make_para_btn(text: String) -> Button:
	var b: Button = _ParaBtn.new() as Button
	b.text = text
	b.custom_minimum_size = Vector2(120, 40)
	UiAssets.apply_button_font(b, 16)
	return b

func _add_action_btn(text: String, cb: Callable) -> Button:
	var b: Button = _make_para_btn(text)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	_box.add_child(b)
	return b

func _on_share_text_changed(new_text: String) -> void:
	var cleaned := InviteBlobHelper.sanitize_paste(new_text)
	if cleaned == new_text:
		return
	var caret := _share_edit.caret_column
	_share_edit.set_block_signals(true)
	_share_edit.text = cleaned
	_share_edit.caret_column = mini(caret, cleaned.length())
	_share_edit.set_block_signals(false)

func _gate_nick() -> bool:
	var n := sanitized_nick()
	if n == "":
		n = _ensure_default_nick()
		_nick.text = n
	if n == "":
		set_status("请输入昵称（最多 50 字，可含数字与符号）")
		return false
	_save_nick(n)
	return true

func sanitized_nick() -> String:
	return NickCodec.sanitize(_nick.text)

func set_status(msg: String) -> void:
	if _status_a:
		_status_a.text = msg
	if _status_b and msg == "":
		_status_b.text = ""

func set_status_pair(left: String, right: String = "") -> void:
	if _status_a:
		_status_a.text = left
	if _status_b:
		_status_b.text = right

func current_nick() -> String:
	return sanitized_nick()

func current_password() -> String:
	if _password_edit:
		return _password_edit.text.strip_edges()
	return ""

func ignore_in_match_rooms() -> bool:
	if _ignore_in_match:
		return _ignore_in_match.button_pressed
	return _load_ignore_in_match()

func refresh_restore_enabled() -> void:
	_refresh_restore_enabled()

func _refresh_restore_enabled() -> void:
	if _restore_btn:
		_restore_btn.disabled = not NullsecRejoinTicket.exists()

static func _load_ignore_in_match() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(NICK_CFG) != OK:
		return false
	return bool(cfg.get_value(NICK_SECTION, IGNORE_IN_MATCH_KEY, false))

static func _save_ignore_in_match(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(NICK_CFG)
	cfg.set_value(NICK_SECTION, IGNORE_IN_MATCH_KEY, on)
	cfg.save(NICK_CFG)

static func _load_nick() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(NICK_CFG) != OK:
		return ""
	return str(cfg.get_value(NICK_SECTION, NICK_KEY, ""))

static func make_default_clone_nick() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var digits := ""
	for _i in range(7):
		digits += str(rng.randi_range(0, 9))
	return "克隆人棋手" + digits

static func _ensure_default_nick() -> String:
	var existing := NickCodec.sanitize(_load_nick())
	if existing != "":
		return existing
	var gen := NickCodec.sanitize(make_default_clone_nick())
	if gen != "":
		_save_nick(gen)
	return gen

static func _save_nick(nick: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(NICK_CFG)
	cfg.set_value(NICK_SECTION, NICK_KEY, nick)
	cfg.save(NICK_CFG)

static func load_enum_cursor() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(NICK_CFG) != OK:
		return {"cursor": 1, "dir": 1}
	return {
		"cursor": int(cfg.get_value(NICK_SECTION, ENUM_CURSOR_KEY, 1)),
		"dir": int(cfg.get_value(NICK_SECTION, ENUM_DIR_KEY, 1)),
	}

static func save_enum_cursor(cursor: int, dir: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(NICK_CFG)
	cfg.set_value(NICK_SECTION, ENUM_CURSOR_KEY, cursor)
	cfg.set_value(NICK_SECTION, ENUM_DIR_KEY, dir)
	cfg.save(NICK_CFG)
