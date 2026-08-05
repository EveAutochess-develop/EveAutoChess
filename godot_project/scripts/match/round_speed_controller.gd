extends RefCounted
class_name RoundSpeedController
## Priority: unanimous non-1x > finished→max(4x,场上) > disagree/1x. Wall-clock 2min draw.
## Auto finish floor must not persist as preferred (SEMI_ASYNC §4.5).
## Unanimous requires EVERY occupied human seat to have voted the same speed.

signal speed_changed(speed: float)
signal force_draw_remaining

var human_votes: Dictionary = {} ## peer/seat -> speed
## Seats that must agree before a non-1× vote takes effect. Empty = legacy (any voters).
var required_human_seats: PackedInt32Array = PackedInt32Array()
var any_finished: bool = false
var first_finish_wall_ms: int = 0
var manual_override_active: bool = false
## Floor while any_finished: max(4×, battlefield speed at first finish).
var _finish_floor: float = 4.0
const WALL_DRAW_MS: int = 120_000
const AUTO_FINISH_MIN: float = 4.0

func set_vote(seat_id: int, speed: float) -> void:
	human_votes[seat_id] = speed
	manual_override_active = true
	_recompute()

func set_required_human_seats(seats: PackedInt32Array) -> void:
	required_human_seats = seats.duplicate()
	_recompute()

## How many required human seats still need to vote (or disagree). 0 = unanimous ready.
func waiting_count() -> int:
	if required_human_seats.is_empty():
		return 0 if not human_votes.is_empty() else 1
	var unanimous: float = _unanimous_human()
	if unanimous > 0.0:
		return 0
	var missing: int = 0
	var first: float = -1.0
	for seat: int in required_human_seats:
		if not human_votes.has(seat):
			missing += 1
			continue
		var v: float = TypedVariant.as_float(human_votes[seat], 0.0)
		if first < 0.0:
			first = v
		elif not is_equal_approx(first, v):
			## Disagree counts as still waiting consensus.
			return required_human_seats.size()
	return missing

func mark_seat_finished(battlefield_speed: float = 1.0) -> void:
	if not any_finished:
		any_finished = true
		first_finish_wall_ms = Time.get_ticks_msec()
		_finish_floor = maxf(AUTO_FINISH_MIN, maxf(0.05, battlefield_speed))
	_recompute()

func tick_wall_clock() -> void:
	if any_finished and first_finish_wall_ms > 0:
		if Time.get_ticks_msec() - first_finish_wall_ms >= WALL_DRAW_MS:
			force_draw_remaining.emit()
			first_finish_wall_ms = 0

func reset_round() -> void:
	any_finished = false
	first_finish_wall_ms = 0
	_finish_floor = AUTO_FINISH_MIN
	## Keep votes across round or clear — clear each round for fairness
	human_votes.clear()
	manual_override_active = false
	_recompute()

func ai_follow_majority() -> float:
	return _majority_human()

func current_speed() -> float:
	return _resolve()

## True when resolved speed comes from player votes (may write preferred).
## False for automatic finish floor — must not stick into next round.
func should_persist_preferred() -> bool:
	if not any_finished:
		return true
	var unanimous: float = _unanimous_human()
	if unanimous > 0.0 and not is_equal_approx(unanimous, 1.0):
		return true
	return false

func _recompute() -> void:
	speed_changed.emit(_resolve())

func _resolve() -> float:
	var unanimous: float = _unanimous_human()
	if unanimous > 0.0 and not is_equal_approx(unanimous, 1.0):
		return unanimous
	if any_finished:
		return _finish_floor
	return 1.0

func _unanimous_human() -> float:
	if required_human_seats.is_empty():
		## Solo / unset: any voters that agree.
		if human_votes.is_empty():
			return -1.0
		var first: float = -1.0
		for k_v: Variant in human_votes.keys():
			var v: float = TypedVariant.as_float(human_votes[k_v], 0.0)
			if first < 0.0:
				first = v
			elif not is_equal_approx(first, v):
				return -1.0
		return first
	## Every required human seat must have voted the same value.
	var first_req: float = -1.0
	for seat: int in required_human_seats:
		if not human_votes.has(seat):
			return -1.0
		var v2: float = TypedVariant.as_float(human_votes[seat], 0.0)
		if first_req < 0.0:
			first_req = v2
		elif not is_equal_approx(first_req, v2):
			return -1.0
	return first_req

func _majority_human() -> float:
	if human_votes.is_empty():
		return 1.0
	var counts: Dictionary = {}
	for k_v: Variant in human_votes.keys():
		var v: float = TypedVariant.as_float(human_votes[k_v], 0.0)
		counts[v] = TypedVariant.as_int(counts.get(v, 0), 0) + 1
	var best_v: float = 1.0
	var best_n: int = -1
	for v_v: Variant in counts.keys():
		var n: int = TypedVariant.as_int(counts[v_v], 0)
		var v_f: float = TypedVariant.as_float(v_v, 0.0)
		if n > best_n or (n == best_n and v_f < best_v):
			best_n = n
			best_v = v_f
	return best_v
