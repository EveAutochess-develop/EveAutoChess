extends RefCounted
class_name HostSimOrchestrator
## Semi-async host authority ring skeleton — queues BattleJobs, broadcasts results.

signal battle_job_finished(serial: int, report: Dictionary)
signal round_finished(round_reports: Array)

var match_rng: MatchRng
var _serial: int = 0
var _pending: Array = []
var _finished: Array = []

func setup(rng: MatchRng) -> void:
	match_rng = rng

func enqueue_pvp(seat_a: int, seat_b: int, home_seat: int) -> int:
	_serial += 1
	var seeds := match_rng.begin_battle(_serial) if match_rng else {}
	_pending.append({
		"serial": _serial,
		"kind": "pvp",
		"seat_a": seat_a,
		"seat_b": seat_b,
		"home_seat": home_seat,
		"seeds": seeds,
	})
	return _serial

func enqueue_pve(seat: int, task: String) -> int:
	_serial += 1
	var seeds := match_rng.begin_battle(_serial) if match_rng else {}
	_pending.append({
		"serial": _serial,
		"kind": "pve",
		"seat": seat,
		"task": task,
		"seeds": seeds,
	})
	return _serial

func tick_authority(_logic_dt: float) -> void:
	## Placeholder: mark first pending complete for smoke tests.
	if _pending.is_empty():
		return
	var job: Dictionary = _pending.pop_front()
	var report := {
		"serial": int(job.get("serial", 0)),
		"kind": str(job.get("kind", "")),
		"result": "pending_sim",
		"job": job,
	}
	_finished.append(report)
	battle_job_finished.emit(int(job.get("serial", 0)), report)

func flush_round() -> Array:
	var out := _finished.duplicate(true)
	_finished.clear()
	round_finished.emit(out)
	return out
