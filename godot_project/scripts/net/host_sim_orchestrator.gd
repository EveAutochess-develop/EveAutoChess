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


func enqueue_pvp(seat_a: int, seat_b: int, home_seat: int, a_owner_seat: int = -1, b_owner_seat: int = -1) -> int:
	_serial += 1
	var seeds: Dictionary = match_rng.begin_battle(_serial) if match_rng else {}
	var oa: int = a_owner_seat if a_owner_seat >= 0 else seat_a
	var ob: int = b_owner_seat if b_owner_seat >= 0 else seat_b
	var deputy: int = pick_deputy_seat(
		int(match_rng.match_seed) if match_rng else 0,
		_serial,
		seat_a,
		seat_b,
		oa,
		ob
	)
	_pending.append({
		"serial": _serial,
		"kind": "pvp",
		"seat_a": seat_a,
		"seat_b": seat_b,
		"home_seat": home_seat,
		"deputy_seat": deputy,
		"a_owner_seat": oa,
		"b_owner_seat": ob,
		"seeds": seeds,
	})
	NetSessionDebug.log_event(
		"net.deputy.pick",
		"serial=%d a=%d b=%d deputy=%d oa=%d ob=%d" % [_serial, seat_a, seat_b, deputy, oa, ob]
	)
	return _serial


## SEMI_ASYNC §3.2 — deputy is owner_seat for proxy (onnx/llm/legacy) seats.
static func pick_deputy_seat(
	match_seed: int,
	round_or_serial: int,
	seat_a: int,
	seat_b: int,
	a_owner_seat: int = -1,
	b_owner_seat: int = -1
) -> int:
	var oa: int = a_owner_seat if a_owner_seat >= 0 else seat_a
	var ob: int = b_owner_seat if b_owner_seat >= 0 else seat_b
	var a_proxy: bool = oa != seat_a
	var b_proxy: bool = ob != seat_b
	if a_proxy and b_proxy:
		if oa == ob:
			return oa
		var lo_o: int = mini(oa, ob)
		var hi_o: int = maxi(oa, ob)
		var key_o: String = "%d|deputy|%d|%d|%d" % [match_seed, round_or_serial, lo_o, hi_o]
		var ho: int = hash(key_o)
		if ho < 0:
			ho = -ho
		return lo_o if (ho % 2) == 0 else hi_o
	if a_proxy:
		return oa
	if b_proxy:
		return ob
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
