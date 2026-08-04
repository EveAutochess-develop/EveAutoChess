extends AcceptDialog
class_name NullsecLobbyPopup
## Main-menu multipath lobby: nick + host/match/history.
## Join path: single room-share field (SEMI_ASYNC §7.2). Verbal 公开/私密 = password empty/set.
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

signal request_match_public
signal request_host_room(password: String)
signal request_join_share(share: String)
signal request_history

const NICK_CFG := "user://player_settings.cfg"
const NICK_SECTION := "nullsec"
const NICK_KEY := "nick"
const ENUM_CURSOR_KEY := "public_enum_cursor"
const ENUM_DIR_KEY := "public_enum_dir"
const IGNORE_IN_MATCH_KEY := "ignore_in_match"

var _nick: LineEdit
var _password_edit: LineEdit
var _share_edit: LineEdit
var _status: Label
var _ignore_in_match: CheckBox

func _ready() -> void:
	title = "多人联机对战"
	dialog_hide_on_ok = false
	ok_button_text = "关闭"
	confirmed.connect(hide)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	root.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var nick_lbl := Label.new()
	nick_lbl.text = "昵称（仅中英文字符，无标点）"
	left.add_child(nick_lbl)
	_nick = LineEdit.new()
	_nick.placeholder_text = "输入昵称"
	_nick.text = _load_nick()
	left.add_child(_nick)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	_add_btn(right, "匹配房间", func():
		if _gate_nick():
			request_match_public.emit()
	)
	_ignore_in_match = CheckBox.new()
	_ignore_in_match.text = "忽视已开局房间"
	_ignore_in_match.button_pressed = _load_ignore_in_match()
	_ignore_in_match.toggled.connect(func(on: bool): _save_ignore_in_match(on))
	right.add_child(_ignore_in_match)
	var pw_lbl := Label.new()
	pw_lbl.text = "房间密码（空=口头公开 · 有=口头私密）"
	right.add_child(pw_lbl)
	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "可选 4～8 位"
	_password_edit.secret = true
	_password_edit.max_length = 8
	right.add_child(_password_edit)
	_add_btn(right, "主持公开房间", func():
		if _gate_nick():
			request_host_room.emit("")
	)
	_add_btn(right, "主持私密房间", func():
		if _gate_nick():
			var pw := _password_edit.text.strip_edges()
			if pw.is_empty():
				pw = NullsecNetSession.random_room_password(6)
				_password_edit.text = pw
			request_host_room.emit(pw)
	)
	var share_row := HBoxContainer.new()
	right.add_child(share_row)
	_share_edit = LineEdit.new()
	_share_edit.placeholder_text = "粘贴房间码（EAC…）"
	_share_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_row.add_child(_share_edit)
	var join_btn := Button.new()
	join_btn.text = "加入"
	join_btn.pressed.connect(func():
		if _gate_nick():
			request_join_share.emit(_share_edit.text.strip_edges())
	)
	share_row.add_child(join_btn)
	_add_btn(right, "多人联机历史战绩", func(): request_history.emit())

func _add_btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)

func _gate_nick() -> bool:
	var n := sanitized_nick()
	if n == "":
		_status.text = "请输入仅含中英文字符的昵称"
		return false
	_save_nick(n)
	return true

func sanitized_nick() -> String:
	var raw := _nick.text.strip_edges()
	var out := ""
	for i in range(raw.length()):
		var ch := raw.substr(i, 1)
		var code := ch.unicode_at(0)
		var ok := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
			or (code >= 0x4E00 and code <= 0x9FFF)
		if ok:
			out += ch
	return out

func set_status(msg: String) -> void:
	_status.text = msg

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

static func _save_nick(n: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(NICK_CFG)
	cfg.set_value(NICK_SECTION, NICK_KEY, n)
	cfg.save(NICK_CFG)

static func load_enum_cursor() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(NICK_CFG)
	return {
		"cursor": int(cfg.get_value(NICK_SECTION, ENUM_CURSOR_KEY, 1)),
		"dir": int(cfg.get_value(NICK_SECTION, ENUM_DIR_KEY, 1)),
	}

static func save_enum_cursor(cursor: int, dir: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(NICK_CFG)
	cfg.set_value(NICK_SECTION, ENUM_CURSOR_KEY, clampi(cursor, 1, 9999))
	cfg.set_value(NICK_SECTION, ENUM_DIR_KEY, 1 if dir >= 0 else -1)
	cfg.save(NICK_CFG)
