extends Button
class_name ScoutIntelButton
## Top-right scout / spectate picker (MULTIPLAYER_PVP §4.2 / §4.4).
## Scout: explore-frigate gate + consume; spectate: view switch. Empty list shows a disabled reason row.

signal observe_requested(seat_id: int)
## Fired right before the popup opens so the owner can refresh rows + gate hint.
signal menu_opening

const HINT_ID: int = -1

var _menu: PopupMenu
var _seat_labels: Array = [] ## [{seat_id, nick, finished, self}]
var _local_finished: bool = false
## Non-empty = why scouting cannot fire right now (shown as a disabled first row).
var _hint: String = ""


static func _as_int(v: Variant, default_val: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return v as int
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return int(v as float)
		_:
			return default_val


static func _as_bool(v: Variant, default_val: bool = false) -> bool:
	match typeof(v):
		TYPE_BOOL:
			@warning_ignore("unsafe_cast")
			return v as bool
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return (v as int) != 0
		_:
			return default_val


func _ready() -> void:
	text = "刺探情报"
	_menu = PopupMenu.new()
	add_child(_menu)
	_menu.id_pressed.connect(_on_pick)
	pressed.connect(_on_pressed)


func set_targets(seats: Array) -> void:
	_seat_labels = seats.duplicate(true)
	_rebuild()


func set_hint(hint: String) -> void:
	_hint = hint
	_rebuild()


func set_local_finished(done: bool) -> void:
	_local_finished = done
	_rebuild()


func mark_seat_finished(seat_id: int) -> void:
	for i: int in range(_seat_labels.size()):
		var row_v: Variant = _seat_labels[i]
		if not (row_v is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var row: Dictionary = row_v as Dictionary
		var sid: int = _as_int(row.get("seat_id", -1), -1)
		if sid == seat_id:
			row["finished"] = true
			_seat_labels[i] = row
	_rebuild()


func _rebuild() -> void:
	if _menu == null:
		return
	_menu.clear()
	if _hint != "":
		_menu.add_item(_hint, HINT_ID)
		_menu.set_item_disabled(_menu.item_count - 1, true)
		if not _seat_labels.is_empty():
			_menu.add_separator()
	for s_v: Variant in _seat_labels:
		if not (s_v is Dictionary):
			continue
		@warning_ignore("unsafe_cast")
		var s: Dictionary = s_v as Dictionary
		var sid: int = _as_int(s.get("seat_id", 0), 0)
		var nick: String = str(s.get("nick", "?"))
		var fin: bool = _as_bool(s.get("finished", false), false)
		var is_self: bool = _as_bool(s.get("self", false), false)
		var label: String = nick
		if is_self:
			label = "%s（本席 · 返回）" % nick
		elif _local_finished and not fin:
			label = "★ %s（未完成）" % nick
		elif fin:
			label = "%s（已完成）" % nick
		_menu.add_item(label, sid)
	if _menu.item_count == 0:
		_menu.add_item("暂无可刺探的参赛席位", HINT_ID)
		_menu.set_item_disabled(0, true)


func _on_pressed() -> void:
	menu_opening.emit()
	_rebuild()
	_menu.position = Vector2i(global_position) + Vector2i(0, int(size.y))
	_menu.reset_size()
	_menu.popup()


func _on_pick(id: int) -> void:
	if id == HINT_ID:
		return
	observe_requested.emit(id)
