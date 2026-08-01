extends AcceptDialog
class_name NullsecLobbyPopup
## Main-menu multipath lobby: nick + public/private/history.

signal request_match_public
signal request_host_public
signal request_host_private
signal request_join_private(code: String)
signal request_history

const NICK_CFG := "user://player_settings.cfg"
const NICK_SECTION := "nullsec"
const NICK_KEY := "nick"
const ENUM_CURSOR_KEY := "public_enum_cursor"
const ENUM_DIR_KEY := "public_enum_dir"
const IGNORE_IN_MATCH_KEY := "ignore_in_match"

var _nick: LineEdit
var _join_code: LineEdit
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
	_add_btn(right, "匹配公开房间", func():
		if _gate_nick():
			request_match_public.emit()
	)
	_ignore_in_match = CheckBox.new()
	_ignore_in_match.text = "忽视已开局房间"
	_ignore_in_match.button_pressed = _load_ignore_in_match()
	_ignore_in_match.toggled.connect(func(on: bool): _save_ignore_in_match(on))
	right.add_child(_ignore_in_match)
	_add_btn(right, "主持公开房间", func():
		if _gate_nick():
			request_host_public.emit()
	)
	_add_btn(right, "主持私密房间", func():
		if _gate_nick():
			request_host_private.emit()
	)
	var join_row := HBoxContainer.new()
	right.add_child(join_row)
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "私密码"
	_join_code.custom_minimum_size = Vector2(120, 0)
	join_row.add_child(_join_code)
	var join_btn := Button.new()
	join_btn.text = "加入私密房间"
	join_btn.pressed.connect(func():
		if _gate_nick():
			request_join_private.emit(_join_code.text.strip_edges())
	)
	join_row.add_child(join_btn)
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
