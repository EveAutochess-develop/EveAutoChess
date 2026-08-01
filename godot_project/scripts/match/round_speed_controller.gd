extends RefCounted
class_name RoundSpeedController
## Priority: unanimous non-1x > finished→4x > disagree/1x. Wall-clock 2min draw.

signal speed_changed(speed: float)
signal force_draw_remaining

var human_votes: Dictionary = {} ## peer/seat -> speed
var any_finished: bool = false
var first_finish_wall_ms: int = 0
var manual_override_active: bool = false
const WALL_DRAW_MS := 120_000

func set_vote(seat_id: int, speed: float) -> void:
	human_votes[seat_id] = speed
	manual_override_active = true
	_recompute()

func mark_seat_finished() -> void:
	if not any_finished:
		any_finished = true
		first_finish_wall_ms = Time.get_ticks_msec()
	_recompute()

func tick_wall_clock() -> void:
	if any_finished and first_finish_wall_ms > 0:
		if Time.get_ticks_msec() - first_finish_wall_ms >= WALL_DRAW_MS:
			force_draw_remaining.emit()
			first_finish_wall_ms = 0

func reset_round() -> void:
	any_finished = false
	first_finish_wall_ms = 0
	## Keep votes across round or clear — clear each round for fairness
	human_votes.clear()
	manual_override_active = false
	_recompute()

func ai_follow_majority() -> float:
	return _majority_human()

func current_speed() -> float:
	return _resolve()

func _recompute() -> void:
	speed_changed.emit(_resolve())

func _resolve() -> float:
	var unanimous := _unanimous_human()
	if unanimous > 0.0 and not is_equal_approx(unanimous, 1.0):
		return unanimous
	if any_finished:
		return 4.0
	return 1.0

func _unanimous_human() -> float:
	if human_votes.is_empty():
		return -1.0
	var first := -1.0
	for k in human_votes.keys():
		var v := float(human_votes[k])
		if first < 0.0:
			first = v
		elif not is_equal_approx(first, v):
			return -1.0
	return first

func _majority_human() -> float:
	if human_votes.is_empty():
		return 1.0
	var counts: Dictionary = {}
	for k in human_votes.keys():
		var v := float(human_votes[k])
		counts[v] = int(counts.get(v, 0)) + 1
	var best_v := 1.0
	var best_n := -1
	for v in counts.keys():
		var n := int(counts[v])
		if n > best_n or (n == best_n and float(v) < best_v):
			best_n = n
			best_v = float(v)
	return best_v
