extends RefCounted
class_name InMatchSlowLearn
## In-match slow learn: high-LR GDScript CE + genome overlay. No farm opt.step.
## Handbook §0.2 · AI_SELFPLAY §6. Memory first, disk async.

const DIR: String = "user://eveac_ai/learn_delta"
const SCHEMA_VER: String = "1"
const NET_NAMES: PackedStringArray = ["titan", "match_global", "ops", "shop", "fit", "place"]
const STANCE_IDS: PackedStringArray = ["economy", "offense", "logistics", "speed_control", "formation"]
const TITAN_IDS: PackedStringArray = ["amarr", "caldari", "gallente", "minmatar", "angel"]
const ETA: float = 0.012
const CE_STEPS: int = 4
const STANCE_ALPHA: float = 0.5
const SHIP_BUMP: float = 0.45
const SHIP_DECAY: float = 0.92
const HUMAN_CE_W: float = 2.5
const AI_CE_W: float = 0.6

static var _stats: CombatLearnStats = CombatLearnStats.new()
static var _genome_delta: Dictionary = {}
static var _net_delta: Dictionary = {} ## net -> {W0: PackedFloat32Array, b0: ..., ...}
static var _revealed: Array = []
static var _shop_samples: Array = []
static var _place_samples: Array = []
static var _task_ids: Array[int] = []
static var _quitting: bool = false
static var _disk_loaded: bool = false
static var _queued: Dictionary = {}
static var _ce_task_id: int = -1
static var _ce_busy: bool = false
static var _ce_out: Dictionary = {}
static var _slice_t0: int = 0
const SLICE_PREPARE_MS: int = 6
const SLICE_BATTLE_MS: int = 1
const W_CLIP: float = 8.0


static func is_enabled() -> bool:
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps == null:
		return true
	return ps.in_match_slow_learn


static func ensure_loaded() -> void:
	if _disk_loaded:
		return
	_disk_loaded = true
	_load_delta_dir()


static func cancel_pending() -> void:
	_quitting = true
	_queued.clear()
	for id: int in _task_ids:
		if not WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
	_task_ids.clear()
	_ce_task_id = -1
	_ce_busy = false
	_ce_out.clear()
	_quitting = false


static func begin_battle(board: BoardController) -> void:
	ensure_loaded()
	_stats.begin_battle(board)


static func note_revealed(cmd: Dictionary) -> void:
	if cmd.is_empty():
		return
	if _revealed.size() > 48:
		_revealed.pop_front()
	_revealed.append(cmd.duplicate(true))


static func note_shop_sample(obs: PackedFloat32Array, act: int, human: bool) -> void:
	if obs.is_empty() or act < 0:
		return
	if _shop_samples.size() > 64:
		_shop_samples.pop_front()
	_shop_samples.append({"obs": obs, "act": act, "human": human})


static func note_place_sample(obs: PackedFloat32Array, act: int, human: bool) -> void:
	if obs.is_empty() or act < 0:
		return
	if _place_samples.size() > 32:
		_place_samples.pop_front()
	_place_samples.append({"obs": obs, "act": act, "human": human})


static func has_queued() -> bool:
	return not _queued.is_empty()


static func has_slice_work() -> bool:
	return _ce_busy or not _queued.is_empty()


static func queue_round(match_ctrl: MatchController, board: BoardController) -> void:
	ensure_loaded()
	if not is_enabled() or match_ctrl == null or match_ctrl.remote_watch_only:
		_revealed.clear()
		_shop_samples.clear()
		_place_samples.clear()
		_queued.clear()
		return
	var ships: Array = _stats.snapshot_end(
		board,
		match_ctrl.kills_this_round_player,
		match_ctrl.kills_this_round_ai
	)
	_queued = {
		"ships": ships,
		"shop": _shop_samples.duplicate(true),
		"place": _place_samples.duplicate(true),
		"revealed": _revealed.duplicate(true),
	}
	_revealed.clear()
	_shop_samples.clear()
	_place_samples.clear()


static func begin_pending(match_ctrl: MatchController, ai: AiController, _board: BoardController) -> void:
	if _queued.is_empty() or _ce_busy:
		return
	var pack: Dictionary = _queued
	_queued = {}
	var t0: int = Time.get_ticks_msec()
	ensure_loaded()
	if not is_enabled() or match_ctrl == null or match_ctrl.remote_watch_only:
		return
	if ai == null or ai.weight_policy == null:
		return
	var live_shop: Array = _shop_samples
	var live_place: Array = _place_samples
	var live_rev: Array = _revealed
	_shop_samples = TypedVariant.as_array(pack.get("shop", []))
	_place_samples = TypedVariant.as_array(pack.get("place", []))
	_revealed = TypedVariant.as_array(pack.get("revealed", []))
	var ships: Array = TypedVariant.as_array(pack.get("ships", []))
	var g: float = _signed_g(match_ctrl, ships)
	_apply_genome(ai, g)
	if ai.weight_policy.fallback != null:
		ai.weight_policy.fallback.apply_genome_delta(_genome_delta)
	var jobs: Array = _build_ce_jobs(ai.weight_policy, g)
	ai.weight_policy.set_net_delta(_net_delta)
	SessionDiagnostics.log("ai.slow_learn", "begin G=%.3f jobs=%d cmds=%d" % [g, jobs.size(), _revealed.size()])
	_shop_samples = live_shop
	_place_samples = live_place
	_revealed = live_rev
	if jobs.is_empty():
		_schedule_flush()
		return
	var specs: Dictionary = {}
	var bag: Dictionary = {}
	for n: String in ["shop", "place"]:
		if not _net_delta.has(n):
			continue
		specs[n] = ai.weight_policy.net_spec(n).duplicate(true)
		bag[n] = TypedVariant.as_dict(_net_delta[n]).duplicate(true)
	_slice_t0 = t0
	_ce_out = {}
	_ce_busy = true
	_ce_task_id = WorkerThreadPool.add_task(_ce_worker.bind({
		"jobs": jobs, "specs": specs, "delta": bag,
	}))
	_task_ids.append(_ce_task_id)


static func tick_pending(ai: AiController, _budget_ms: int = 0) -> void:
	if not _ce_busy or _ce_task_id < 0:
		return
	if not WorkerThreadPool.is_task_completed(_ce_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_ce_task_id)
	_ce_task_id = -1
	_ce_busy = false
	for k_v: Variant in _ce_out.keys():
		_net_delta[str(k_v)] = _ce_out[k_v]
	_ce_out = {}
	if ai != null and ai.weight_policy != null:
		ai.weight_policy.set_net_delta(_net_delta)
	_schedule_flush()


static func apply_pending(match_ctrl: MatchController, ai: AiController, board: BoardController) -> void:
	begin_pending(match_ctrl, ai, board)
	if _ce_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_ce_task_id)
	tick_pending(ai, 0)


static func apply_round_now(match_ctrl: MatchController, ai: AiController, board: BoardController) -> void:
	queue_round(match_ctrl, board)
	apply_pending(match_ctrl, ai, board)


static func genome_delta() -> Dictionary:
	ensure_loaded()
	return _genome_delta


static func net_delta() -> Dictionary:
	ensure_loaded()
	return _net_delta


static func has_delta() -> bool:
	ensure_loaded()
	if not _genome_delta.is_empty():
		return true
	for n: String in NET_NAMES:
		if _net_delta.has(n):
			return true
	return false


static func clear_delta_files() -> void:
	_genome_delta.clear()
	_net_delta.clear()
	_disk_loaded = true
	if not DirAccess.dir_exists_absolute(DIR):
		return
	var da: DirAccess = DirAccess.open(DIR)
	if da == null:
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if not da.current_is_dir():
			da.remove(fn)
		fn = da.get_next()
	da.list_dir_end()


static func collect_export_bytes() -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	if not _genome_delta.is_empty():
		out["learn_delta/genome_delta.json"] = JSON.stringify(_genome_delta).to_utf8_buffer()
	for n: String in NET_NAMES:
		if not _net_delta.has(n):
			continue
		var spec: Dictionary = _delta_to_json(TypedVariant.as_dict(_net_delta[n]))
		if spec.is_empty():
			continue
		out["learn_delta/%s.json" % n] = JSON.stringify(spec).to_utf8_buffer()
	return out


static func import_delta_bytes(files: Dictionary, present: bool) -> void:
	if not present:
		clear_delta_files()
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	_genome_delta.clear()
	_net_delta.clear()
	for k_v: Variant in files.keys():
		var key: String = str(k_v)
		if not key.begins_with("learn_delta/"):
			continue
		var bytes_v: Variant = files[k_v]
		if not (bytes_v is PackedByteArray):
			continue
		var bytes: PackedByteArray = TypedVariant.as_packed_bytes(bytes_v)
		var dest: String = DIR.path_join(key.trim_prefix("learn_delta/"))
		var f: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer(bytes)
		f.close()
	_disk_loaded = false
	_load_delta_dir()


static func _signed_g(match_ctrl: MatchController, ships: Array) -> float:
	## AI view: player win ⇒ AI loss. No title-count reward.
	var result: String = str(match_ctrl.last_round_result)
	var ai_sign: float = 0.0
	if result == "lose":
		ai_sign = 1.0
	elif result == "win":
		ai_sign = -1.0
	var ai_cost: float = 0.0
	var p_cost: float = 0.0
	var ai_live: int = 0
	var p_live: int = 0
	for row_v: Variant in ships:
		var row: Dictionary = TypedVariant.as_dict(row_v)
		var cost: float = TypedVariant.as_float(row.get("cost", 0), 0.0)
		var team: int = TypedVariant.as_int(row.get("team", 0), 0)
		var survived: bool = TypedVariant.as_bool(row.get("survived", false), false)
		if team == ShipUnit.TEAM_AI:
			if survived:
				ai_cost += cost
				ai_live += 1
		else:
			if survived:
				p_cost += cost
				p_live += 1
	var wipe: float = 0.0
	if ai_sign > 0.0 and p_live <= 0:
		wipe = 1.0
	elif ai_sign < 0.0 and ai_live <= 0:
		wipe = 1.0
	var diff: float = (ai_cost - p_cost) / 20.0
	return tanh(ai_sign * 1.15 + 0.35 * diff + 0.55 * wipe)


static func _apply_genome(ai: AiController, _g: float) -> void:
	var baseline: Dictionary = {}
	if ai.weight_policy != null and ai.weight_policy.fallback != null:
		baseline = ai.weight_policy.fallback.genome.duplicate(true)
	if baseline.is_empty():
		baseline = _read_json("user://eveac_ai/behavior.genome.json")
	if baseline.is_empty():
		baseline = _read_json("res://data/ai/behavior.genome.json")
	if baseline.is_empty():
		baseline = {"schema_ver": SCHEMA_VER, "stance": {}, "titan_pick": {}, "titan_slices": {}}
	var stance: Dictionary = TypedVariant.as_dict(baseline.get("stance", {})).duplicate(true)
	var target: Dictionary = _human_stance_target()
	var prior: float = 1.0 / float(STANCE_IDS.size())
	for id: String in STANCE_IDS:
		var a: float = TypedVariant.as_float(stance.get(id, prior), prior)
		var b: float = TypedVariant.as_float(target.get(id, prior), prior)
		stance[id] = a * (1.0 - STANCE_ALPHA) + b * STANCE_ALPHA
	var pick: Dictionary = TypedVariant.as_dict(baseline.get("titan_pick", {})).duplicate(true)
	var slices: Dictionary = TypedVariant.as_dict(baseline.get("titan_slices", {})).duplicate(true)
	var titan: String = ai._ai_titan_id()
	if not TITAN_IDS.has(titan):
		titan = "caldari"
	if not slices.has(titan):
		slices[titan] = {"ship": {}, "equip": {}}
	var slice: Dictionary = TypedVariant.as_dict(slices[titan]).duplicate(true)
	var ships: Dictionary = TypedVariant.as_dict(slice.get("ship", {})).duplicate(true)
	var equips: Dictionary = TypedVariant.as_dict(slice.get("equip", {})).duplicate(true)
	for k_v: Variant in ships.keys():
		ships[k_v] = TypedVariant.as_float(ships[k_v], 0.5) * SHIP_DECAY
	for k2: Variant in equips.keys():
		equips[k2] = TypedVariant.as_float(equips[k2], 0.5) * SHIP_DECAY
	for cmd_v: Variant in _revealed:
		var cmd: Dictionary = TypedVariant.as_dict(cmd_v)
		var kind: String = str(cmd.get("kind", ""))
		if kind == "buy_ship":
			var sid: String = str(cmd.get("ship_id", ""))
			if sid != "" and sid != "0":
				ships[sid] = TypedVariant.as_float(ships.get(sid, 0.5), 0.5) + SHIP_BUMP
			var race: String = str(cmd.get("race", ""))
			if TITAN_IDS.has(race):
				pick[race] = TypedVariant.as_float(pick.get(race, 0.2), 0.2) + 0.25
		elif kind == "buy_equip":
			var eid: String = str(cmd.get("item_id", ""))
			if eid != "":
				equips[eid] = TypedVariant.as_float(equips.get(eid, 0.5), 0.5) + SHIP_BUMP
	slice["ship"] = ships
	slice["equip"] = equips
	slices[titan] = slice
	_genome_delta = {
		"schema_ver": SCHEMA_VER,
		"content_rev": str(baseline.get("content_rev", "")),
		"stance": stance,
		"titan_pick": pick,
		"titan_slices": slices,
	}


static func _human_stance_target() -> Dictionary:
	var acc: Dictionary = {}
	for id: String in STANCE_IDS:
		acc[id] = 0.08
	var n: int = 0
	for cmd_v: Variant in _revealed:
		var cmd: Dictionary = TypedVariant.as_dict(cmd_v)
		var kind: String = str(cmd.get("kind", ""))
		if kind == "buy_ship":
			n += 1
			var cost: int = TypedVariant.as_int(cmd.get("cost", 0), 0)
			if TypedVariant.as_bool(cmd.get("is_logistic", false), false):
				acc["logistics"] = TypedVariant.as_float(acc["logistics"], 0.0) + 1.2
			elif TypedVariant.as_bool(cmd.get("is_cyno", false), false):
				acc["formation"] = TypedVariant.as_float(acc["formation"], 0.0) + 1.0
			elif cost <= 2:
				acc["economy"] = TypedVariant.as_float(acc["economy"], 0.0) + 1.0
			elif cost >= 5:
				acc["offense"] = TypedVariant.as_float(acc["offense"], 0.0) + 1.1
			else:
				acc["offense"] = TypedVariant.as_float(acc["offense"], 0.0) + 0.7
			if TypedVariant.as_float(cmd.get("speed", 0.0), 0.0) >= 280.0:
				acc["speed_control"] = TypedVariant.as_float(acc["speed_control"], 0.0) + 0.45
		elif kind == "buy_exp" or kind == "refresh":
			acc["economy"] = TypedVariant.as_float(acc["economy"], 0.0) + 0.55
			n += 1
		elif kind == "buy_equip":
			acc["offense"] = TypedVariant.as_float(acc["offense"], 0.0) + 0.35
			n += 1
		elif kind == "place":
			acc["formation"] = TypedVariant.as_float(acc["formation"], 0.0) + 0.5
			n += 1
	if n <= 0:
		var even: Dictionary = {}
		for id2: String in STANCE_IDS:
			even[id2] = 0.2
		return even
	var sum: float = 0.0
	for id3: String in STANCE_IDS:
		sum += TypedVariant.as_float(acc[id3], 0.0)
	if sum <= 0.0:
		sum = 1.0
	for id4: String in STANCE_IDS:
		acc[id4] = TypedVariant.as_float(acc[id4], 0.0) / sum
	return acc


static func _build_ce_jobs(policy: OnnxCpuPolicy, g: float) -> Array:
	var jobs: Array = []
	if policy == null or not policy.nets_ready():
		return jobs
	_ensure_net_delta(policy, "shop")
	for _step: int in range(CE_STEPS):
		for samp_v: Variant in _shop_samples:
			var samp: Dictionary = TypedVariant.as_dict(samp_v)
			var obs: PackedFloat32Array = TypedVariant.as_packed_f32(samp.get("obs", PackedFloat32Array()))
			var act: int = TypedVariant.as_int(samp.get("act", -1), -1)
			if obs.is_empty() or act < 0:
				continue
			var w: float = HUMAN_CE_W if TypedVariant.as_bool(samp.get("human", false), false) else (AI_CE_W * g)
			jobs.append({"net": "shop", "obs": obs, "act": act, "w": w})
	if not _place_samples.is_empty():
		_ensure_net_delta(policy, "place")
		for _step2: int in range(CE_STEPS):
			for samp2_v: Variant in _place_samples:
				var samp2: Dictionary = TypedVariant.as_dict(samp2_v)
				var obs2: PackedFloat32Array = TypedVariant.as_packed_f32(samp2.get("obs", PackedFloat32Array()))
				var act2: int = TypedVariant.as_int(samp2.get("act", -1), -1)
				if obs2.is_empty() or act2 < 0:
					continue
				var w2: float = HUMAN_CE_W if TypedVariant.as_bool(samp2.get("human", false), false) else (AI_CE_W * g)
				jobs.append({"net": "place", "obs": obs2, "act": act2, "w": w2})
	var leftover: PackedFloat32Array = PackedFloat32Array()
	for samp3_v: Variant in _shop_samples:
		var s3: Dictionary = TypedVariant.as_dict(samp3_v)
		if TypedVariant.as_bool(s3.get("human", false), false):
			leftover = TypedVariant.as_packed_f32(s3.get("obs", PackedFloat32Array()))
			break
	if leftover.is_empty() and not _revealed.is_empty():
		leftover.resize(PolicyObs.shop_in_dim())
	if leftover.size() >= 8:
		for cmd_v: Variant in _revealed:
			var cmd: Dictionary = TypedVariant.as_dict(cmd_v)
			var act_h: int = _cmd_to_shop_act(cmd)
			if act_h < 0:
				continue
			for _s: int in range(CE_STEPS):
				jobs.append({"net": "shop", "obs": leftover, "act": act_h, "w": HUMAN_CE_W})
	return jobs


static func _ce_worker(payload: Dictionary) -> void:
	if _quitting:
		_ce_busy = false
		return
	var jobs: Array = TypedVariant.as_array(payload.get("jobs", []))
	var specs: Dictionary = TypedVariant.as_dict(payload.get("specs", {}))
	var bag: Dictionary = TypedVariant.as_dict(payload.get("delta", {}))
	for job_v: Variant in jobs:
		if _quitting:
			_ce_busy = false
			return
		var job: Dictionary = TypedVariant.as_dict(job_v)
		var net: String = str(job.get("net", ""))
		var spec: Dictionary = TypedVariant.as_dict(specs.get(net, {}))
		var dlt: Dictionary = TypedVariant.as_dict(bag.get(net, {}))
		_ce_step_spec(
			spec,
			dlt,
			TypedVariant.as_packed_f32(job.get("obs", PackedFloat32Array())),
			TypedVariant.as_int(job.get("act", -1), -1),
			TypedVariant.as_float(job.get("w", 0.0), 0.0)
		)
		bag[net] = dlt
	_ce_out = bag


static func _cmd_to_shop_act(cmd: Dictionary) -> int:
	var kind: String = str(cmd.get("kind", ""))
	if kind == "buy_ship":
		return clampi(TypedVariant.as_int(cmd.get("slot_index", 0), 0), 0, 5)
	if kind == "buy_equip":
		return 6 + clampi(TypedVariant.as_int(cmd.get("slot_index", 0), 0), 0, 3)
	if kind == "refresh":
		return 10
	if kind == "buy_exp":
		return 12
	return -1


static func _ce_step(policy: OnnxCpuPolicy, net_name: String, x: PackedFloat32Array, target: int, weight: float) -> void:
	if policy == null:
		return
	var spec: Dictionary = policy.net_spec(net_name)
	var dlt: Dictionary = TypedVariant.as_dict(_net_delta.get(net_name, {}))
	_ce_step_spec(spec, dlt, x, target, weight)
	_net_delta[net_name] = dlt


static func _ce_step_spec(spec: Dictionary, dlt: Dictionary, x: PackedFloat32Array, target: int, weight: float) -> void:
	if absf(weight) < 1e-6:
		return
	if spec.is_empty():
		return
	var cache: Dictionary = _forward_cache_spec(spec, dlt, x)
	var logits: PackedFloat32Array = TypedVariant.as_packed_f32(cache.get("logits", PackedFloat32Array()))
	if logits.is_empty() or target < 0 or target >= logits.size():
		return
	var dlogits: PackedFloat32Array = _softmax(logits)
	dlogits[target] -= 1.0
	for i: int in range(dlogits.size()):
		dlogits[i] *= weight
	_backward_update(spec, dlt, cache, x, dlogits)


static func _forward_cache_spec(spec: Dictionary, dlt: Dictionary, x: PackedFloat32Array) -> Dictionary:
	var h1: PackedFloat32Array = _linear_spec(spec, "0", x, dlt)
	var a1: PackedFloat32Array = h1.duplicate()
	_silu_inplace(a1)
	var h2: PackedFloat32Array = _linear_spec(spec, "2", a1, dlt)
	var a2: PackedFloat32Array = h2.duplicate()
	_silu_inplace(a2)
	var logits: PackedFloat32Array = _linear_spec(spec, "4", a2, dlt)
	return {"h1": h1, "a1": a1, "h2": h2, "a2": a2, "logits": logits}


static func _linear_spec(spec: Dictionary, layer: String, x: PackedFloat32Array, dlt: Dictionary) -> PackedFloat32Array:
	var rows: int = TypedVariant.as_int(spec.get("out%s" % layer, 0), 0)
	var cols: int = TypedVariant.as_int(spec.get("in%s" % layer, 0), 0)
	if rows <= 0 or cols <= 0:
		return PackedFloat32Array()
	var w: Array = TypedVariant.as_array(spec.get("W%s" % layer, []))
	var b: Array = TypedVariant.as_array(spec.get("b%s" % layer, []))
	var dw: PackedFloat32Array = PackedFloat32Array()
	var db: PackedFloat32Array = PackedFloat32Array()
	if not dlt.is_empty():
		dw = TypedVariant.as_packed_f32(dlt.get("W%s" % layer, PackedFloat32Array()))
		db = TypedVariant.as_packed_f32(dlt.get("b%s" % layer, PackedFloat32Array()))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(rows)
	for r: int in range(rows):
		var bias_v: Variant = 0.0
		if r < b.size():
			bias_v = b[r]
		var acc: float = TypedVariant.as_float(bias_v, 0.0)
		if r < db.size():
			acc += db[r]
		acc = clampf(acc, -W_CLIP, W_CLIP)
		var base: int = r * cols
		var n: int = mini(cols, x.size())
		for c: int in range(n):
			var wv_el: Variant = 0.0
			var wi: int = base + c
			if wi < w.size():
				wv_el = w[wi]
			var wsum: float = TypedVariant.as_float(wv_el, 0.0)
			if wi < dw.size():
				wsum += dw[wi]
			acc += clampf(wsum, -W_CLIP, W_CLIP) * x[c]
		out[r] = acc
	return out


static func _silu_inplace(v: PackedFloat32Array) -> void:
	for i: int in range(v.size()):
		var x: float = v[i]
		v[i] = x / (1.0 + exp(-x))


static func _softmax(logits: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(logits.size())
	var m: float = logits[0]
	for i: int in range(1, logits.size()):
		if logits[i] > m:
			m = logits[i]
	var s: float = 0.0
	for i2: int in range(logits.size()):
		var e: float = exp(logits[i2] - m)
		out[i2] = e
		s += e
	if s <= 1e-12:
		s = 1.0
	for i3: int in range(out.size()):
		out[i3] = out[i3] / s
	return out


static func _silu_grad(z: float) -> float:
	var sig: float = 1.0 / (1.0 + exp(-z))
	return sig + z * sig * (1.0 - sig)


static func _backward_update(spec: Dictionary, dlt: Dictionary, cache: Dictionary, x: PackedFloat32Array, dlogits: PackedFloat32Array) -> void:
	var a2: PackedFloat32Array = TypedVariant.as_packed_f32(cache.get("a2", PackedFloat32Array()))
	var h2: PackedFloat32Array = TypedVariant.as_packed_f32(cache.get("h2", PackedFloat32Array()))
	var a1: PackedFloat32Array = TypedVariant.as_packed_f32(cache.get("a1", PackedFloat32Array()))
	var h1: PackedFloat32Array = TypedVariant.as_packed_f32(cache.get("h1", PackedFloat32Array()))
	var da2: PackedFloat32Array = _linear_bwd(spec, dlt, "4", a2, dlogits)
	var dh2: PackedFloat32Array = PackedFloat32Array()
	dh2.resize(h2.size())
	for i: int in range(h2.size()):
		dh2[i] = da2[i] * _silu_grad(h2[i]) if i < da2.size() else 0.0
	var da1: PackedFloat32Array = _linear_bwd(spec, dlt, "2", a1, dh2)
	var dh1: PackedFloat32Array = PackedFloat32Array()
	dh1.resize(h1.size())
	for j: int in range(h1.size()):
		dh1[j] = da1[j] * _silu_grad(h1[j]) if j < da1.size() else 0.0
	_linear_bwd(spec, dlt, "0", x, dh1)


static func _linear_bwd(spec: Dictionary, dlt: Dictionary, layer: String, xin: PackedFloat32Array, dout: PackedFloat32Array) -> PackedFloat32Array:
	var rows: int = TypedVariant.as_int(spec.get("out%s" % layer, 0), 0)
	var cols: int = TypedVariant.as_int(spec.get("in%s" % layer, 0), 0)
	var dx: PackedFloat32Array = PackedFloat32Array()
	dx.resize(cols)
	if rows <= 0 or cols <= 0:
		return dx
	var wk: String = "W%s" % layer
	var bk: String = "b%s" % layer
	var w_base: Array = []
	var w_raw: Variant = spec.get(wk, [])
	if w_raw is Array:
		w_base = TypedVariant.as_array(w_raw)
	var dw: PackedFloat32Array = TypedVariant.as_packed_f32(dlt.get(wk, PackedFloat32Array()))
	var db: PackedFloat32Array = TypedVariant.as_packed_f32(dlt.get(bk, PackedFloat32Array()))
	if dw.size() < rows * cols:
		dw.resize(rows * cols)
	if db.size() < rows:
		db.resize(rows)
	for r: int in range(mini(rows, dout.size())):
		var g: float = dout[r]
		db[r] -= ETA * g
		var base: int = r * cols
		var n: int = mini(cols, xin.size())
		for c: int in range(n):
			dw[base + c] -= ETA * g * xin[c]
			var wv: float = 0.0
			if base + c < w_base.size():
				wv = TypedVariant.as_float(w_base[base + c], 0.0)
			wv += dw[base + c]
			dx[c] += g * wv
	dlt[wk] = dw
	dlt[bk] = db
	return dx


static func _ensure_net_delta(policy: OnnxCpuPolicy, net_name: String) -> void:
	if _net_delta.has(net_name):
		return
	var spec: Dictionary = policy.net_spec(net_name)
	var d: Dictionary = {}
	for layer: String in ["0", "2", "4"]:
		var rows: int = TypedVariant.as_int(spec.get("out%s" % layer, 0), 0)
		var cols: int = TypedVariant.as_int(spec.get("in%s" % layer, 0), 0)
		var w: PackedFloat32Array = PackedFloat32Array()
		w.resize(maxi(0, rows * cols))
		var b: PackedFloat32Array = PackedFloat32Array()
		b.resize(maxi(0, rows))
		d["W%s" % layer] = w
		d["b%s" % layer] = b
		d["out%s" % layer] = rows
		d["in%s" % layer] = cols
	_net_delta[net_name] = d


static func _schedule_flush() -> void:
	if _quitting:
		return
	var nets_raw: Dictionary = {}
	for n_v: Variant in _net_delta.keys():
		nets_raw[n_v] = TypedVariant.as_dict(_net_delta[n_v]).duplicate(true)
	var snap: Dictionary = {
		"genome": _genome_delta.duplicate(true),
		"nets_raw": nets_raw,
	}
	var id: int = WorkerThreadPool.add_task(InMatchSlowLearn._flush_task.bind(snap))
	_task_ids.append(id)


static func _flush_task(snap: Dictionary) -> void:
	if _quitting:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Dictionary = TypedVariant.as_dict(snap.get("genome", {}))
	if not g.is_empty():
		_write_text(DIR.path_join("genome_delta.json"), JSON.stringify(g))
	var nets_raw: Dictionary = TypedVariant.as_dict(snap.get("nets_raw", {}))
	for n_v: Variant in nets_raw.keys():
		var spec: Dictionary = _delta_to_json(TypedVariant.as_dict(nets_raw[n_v]))
		_write_text(DIR.path_join("%s.json" % str(n_v)), JSON.stringify(spec))


static func _load_delta_dir() -> void:
	_genome_delta = _read_json(DIR.path_join("genome_delta.json"))
	_net_delta.clear()
	for n: String in NET_NAMES:
		var spec: Dictionary = _read_json(DIR.path_join("%s.json" % n))
		if spec.is_empty():
			continue
		_net_delta[n] = _json_to_delta(spec)


static func _delta_to_json(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k_v: Variant in d.keys():
		var k: String = str(k_v)
		var v: Variant = d[k_v]
		if v is PackedFloat32Array:
			var arr: Array = []
			var pf: PackedFloat32Array = TypedVariant.as_packed_f32(v)
			for x: float in pf:
				arr.append(x)
			out[k] = arr
		else:
			out[k] = v
	return out


static func _json_to_delta(spec: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	for k_v: Variant in spec.keys():
		var k: String = str(k_v)
		var v: Variant = spec[k_v]
		if v is Array and (k.begins_with("W") or k.begins_with("b")):
			var pf: PackedFloat32Array = PackedFloat32Array()
			var arr: Array = TypedVariant.as_array(v)
			pf.resize(arr.size())
			for i: int in range(arr.size()):
				pf[i] = TypedVariant.as_float(arr[i], 0.0)
			d[k] = pf
		else:
			d[k] = v
	return d


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	return TypedVariant.as_dict(JSON.parse_string(txt))


static func _write_text(path: String, txt: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()


