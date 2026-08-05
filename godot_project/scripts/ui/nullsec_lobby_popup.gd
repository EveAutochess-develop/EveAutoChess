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
	nick_lbl.text = "昵称（可含数字与符号，最多 50 字）"
	left.add_child(nick_lbl)
	_nick = LineEdit.new()
	_nick.placeholder_text = "克隆人棋手…"
	_nick.max_length = NickCodec.MAX_LEN
	_nick.text = _ensure_default_nick()
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
	pw_lbl.text = "房间密码（不设密码则为公开房间，路人可匹进来）"
	right.add_child(pw_lbl)
	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "可选 4～8 位"
	_password_edit.secret = true
	_password_edit.max_length = 8
	right.add_child(_password_edit)
	_add_btn(right, "主持房间", func():
		if _gate_nick():
			request_host_room.emit(_password_edit.text.strip_edges())
	)
	var share_row := HBoxContainer.new()
	right.add_child(share_row)
	_share_edit = LineEdit.new()
	_share_edit.placeholder_text = "粘贴房间码 EAC…"
	_share_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_edit.text_changed.connect(_on_share_text_changed)
	share_row.add_child(_share_edit)
	var join_btn := Button.new()
	join_btn.text = "加入"
	join_btn.pressed.connect(func():
		if _gate_nick():
			request_join_share.emit(InviteBlobHelper.sanitize_paste(_share_edit.text))
	)
	share_row.add_child(join_btn)
	_add_btn(right, "多人联机历史战绩", func(): request_history.emit())

func _add_btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


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
		_status.text = "请输入昵称（最多 50 字，可含数字与符号）"
		return false
	_save_nick(n)
	return true

func sanitized_nick() -> String:
	return NickCodec.sanitize(_nick.text)

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

## MULTIPLAYER_MATCH_FLOW §2.1 — 克隆人棋手 + 7 digits when unset.
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
