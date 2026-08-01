extends PopupPanel
class_name SpeedDropdownMenu
## Top: speed options. Bottom: player×speed list. Votes feed RoundSpeedController.

signal vote_changed(speed: float)
signal opened_by(nick: String)

const STEPS := [0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]

var controller: RoundSpeedController
var local_seat: int = 0
var local_nick: String = ""
var _opt_box: VBoxContainer
var _list_box: VBoxContainer

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var title_lbl := Label.new()
	title_lbl.text = "倍速"
	UiAssets.apply_label_font(title_lbl, false, UiLayout.font_size(16, self))
	root.add_child(title_lbl)
	var hint := Label.new()
	hint.text = "所有玩家同倍速时才加速"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.75, 0.78, 0.85, 0.9)
	UiAssets.apply_label_font(hint, false, UiLayout.font_size(12, self))
	root.add_child(hint)
	_opt_box = VBoxContainer.new()
	root.add_child(_opt_box)
	for s in STEPS:
		var b := Button.new()
		b.text = _label(float(s))
		var speed := float(s)
		b.pressed.connect(func():
			opened_by.emit(local_nick)
			if controller:
				controller.set_vote(local_seat, speed)
			vote_changed.emit(speed)
			hide()
		)
		_opt_box.add_child(b)
	var sep := HSeparator.new()
	root.add_child(sep)
	var list_title := Label.new()
	list_title.text = "玩家倍速"
	root.add_child(list_title)
	_list_box = VBoxContainer.new()
	root.add_child(_list_box)

func refresh_list(seats: Array) -> void:
	for c in _list_box.get_children():
		c.queue_free()
	for s in seats:
		## Room ships 20 seat slots; only seated players belong in the vote list.
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if not bool((s as Dictionary).get("occupied", false)):
			continue
		var row := Label.new()
		var nick := str(s.get("nick", "?"))
		var seat_id := int(s.get("seat_id", 0))
		var spd := 1.0
		if controller and controller.human_votes.has(seat_id):
			spd = float(controller.human_votes[seat_id])
		elif bool(s.get("is_ai", false)) and controller:
			spd = controller.ai_follow_majority()
		row.text = "%s  %s" % [nick, _label(spd)]
		_list_box.add_child(row)

static func _label(s: float) -> String:
	if s < 1.0:
		return "%.1fx" % s
	if is_equal_approx(s, float(int(s))):
		return "%dx" % int(s)
	return "%.1fx" % s
