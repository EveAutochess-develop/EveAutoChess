extends Button
class_name ScoutIntelButton
## Top-right scout: pick observe target; highlight unfinished after local done.
## The menu must never open empty/silent (MULTIPLAYER_PVP §4.2.1) — it always carries either
## seat rows or a disabled reason row.

signal observe_requested(seat_id: int)
## Fired right before the popup opens so the owner can refresh rows + gate hint.
signal menu_opening

const HINT_ID := -1

var _menu: PopupMenu
var _seat_labels: Array = [] ## [{seat_id, nick, finished, self}]
var _local_finished: bool = false
## Non-empty = why scouting cannot fire right now (shown as a disabled first row).
var _hint: String = ""

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
	for i in range(_seat_labels.size()):
		if int(_seat_labels[i].get("seat_id", -1)) == seat_id:
			_seat_labels[i]["finished"] = true
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
	for s in _seat_labels:
		var sid := int(s.get("seat_id", 0))
		var nick := str(s.get("nick", "?"))
		var fin := bool(s.get("finished", false))
		var label := nick
		if bool(s.get("self", false)):
			label = "%s（本席 · 返回）" % nick
		elif _local_finished and not fin:
			label = "★ %s（未完成）" % nick
		elif fin:
			label = "%s（已完成）" % nick
		_menu.add_item(label, sid)
	if _menu.item_count == 0:
		_menu.add_item("暂无可观察的参赛席位", HINT_ID)
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
