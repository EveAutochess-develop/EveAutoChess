extends RefCounted
class_name HostSimOrchestrator
## Semi-async host authority — queues BattleJobs, resolves with MatchRng seeds, broadcasts reports.

signal battle_job_finished(serial: int, report: Dictionary)
signal round_finished(round_reports: Array)

var match_rng: MatchRng
var _serial: int = 0
var _pending: Array = []
var _finished: Array = []
var _sim_budget: int = 4


func setup(rng: MatchRng) -> void:
	match_rng = rng


func pending_count() -> int:
	return _pending.size()


func enqueue_pvp(seat_a: int, seat_b: int, home_seat: int) -> int:
	_serial += 1
	var seeds: Dictionary = match_rng.begin_battle(_serial) if match_rng else {}
	var deputy: int = pick_deputy_seat(
		int(match_rng.match_seed) if match_rng else 0,
		_serial,
		seat_a,
		seat_b,
		false,
		false
	)
	_pending.append({
		"serial": _serial,
		"kind": "pvp",
		"seat_a": seat_a,
		"seat_b": seat_b,
		"home_seat": home_seat,
		"deputy_seat": deputy,
		"seeds": seeds,
	})
	NetSessionDebug.log_event(
		"net.deputy.pick",
		"serial=%d a=%d b=%d deputy=%d" % [_serial, seat_a, seat_b, deputy]
	)
	return _serial


## SEMI_ASYNC §3.2 — deterministic deputy from the two combatant seats.
static func pick_deputy_seat(
	match_seed: int,
	round_or_serial: int,
	seat_a: int,
	seat_b: int,
	a_is_ai: bool = false,
	b_is_ai: bool = false
) -> int:
	if a_is_ai and not b_is_ai:
		return seat_b
	if b_is_ai and not a_is_ai:
		return seat_a
	if a_is_ai and b_is_ai:
		return -1 ## Room host must simulate.
	var lo: int = mini(seat_a, seat_b)
	var hi: int = maxi(seat_a, seat_b)
	var key: String = "%d|deputy|%d|%d|%d" % [match_seed, round_or_serial, lo, hi]
	var h: int = hash(key)
	if h < 0:
		h = -h
	return lo if (h % 2) == 0 else hi


func enqueue_pve(seat: int, task: String) -> int:
	_serial += 1
	var seeds: Dictionary = match_rng.begin_battle(_serial) if match_rng else {}
	_pending.append({
		"serial": _serial,
		"kind": "pve",
		"seat": seat,
		"task": task,
		"seeds": seeds,
	})
	return _serial


func tick_authority(_logic_dt: float) -> void:
	## Resolve up to budget jobs per authority tick (deterministic report from MatchRng).
	var n: int = 0
	while not _pending.is_empty() and n < _sim_budget:
		var job: Dictionary = _pending.pop_front()
		var report: Dictionary = _simulate_job(job)
		_finished.append(report)
		battle_job_finished.emit(TypedVariant.as_int(job.get("serial", 0), 0), report)
		n += 1


func _simulate_job(job: Dictionary) -> Dictionary:
	var serial: int = TypedVariant.as_int(job.get("serial", 0), 0)
	var kind: String = str(job.get("kind", ""))
	## Lightweight authority outcome from battle seeds (full board sim shares CombatResolver on host client).
	var roll_a: float = 0.5
	var roll_b: float = 0.5
	if match_rng:
		roll_a = match_rng.roll(serial, "turret_hit")
		roll_b = match_rng.roll(serial, "retarget_tiebreak")
	var result: String = "draw"
	if kind == "pvp":
		if roll_a > roll_b + 0.05:
			result = "seat_a"
		elif roll_b > roll_a + 0.05:
			result = "seat_b"
		else:
			result = "draw"
	else:
		result = "success" if roll_a >= 0.35 else "fail"
	return {
		"serial": serial,
		"kind": kind,
		"result": result,
		"job": job,
		"deputy_seat": TypedVariant.as_int(job.get("deputy_seat", -1), -1),
		"state_hash": "%08x" % hash("%s:%s:%.4f:%.4f" % [kind, result, roll_a, roll_b]),
		"spot_sample": [{"kind": kind, "a": roll_a, "b": roll_b}],
	}


## Opponent / host short check before ingesting deputy report (no silent cheat).
static func rival_spot_check(report: Dictionary, local_hash: String, local_result: String) -> Dictionary:
	var rh: String = str(report.get("state_hash", ""))
	var rr: String = str(report.get("result", ""))
	var gap: bool = false
	if local_hash != "" and rh != "" and local_hash != rh:
		gap = true
	if local_result != "" and rr != "" and local_result != rr:
		gap = true
	return {"gap": gap, "report_hash": rh, "local_hash": local_hash}


func flush_round() -> Array:
	var out: Array = _finished.duplicate(true)
	_finished.clear()
	round_finished.emit(out)
	return out
