extends RefCounted
class_name MixedLance
## Mixed lance (混合长枪) — CAPITAL_AND_CYNO §4.1 · EQUIPMENT §6.4b.

const MODULE_ID: String = "mixed_lance"
const PHASE_IDLE: int = 0
const PHASE_PREP: int = 1
const PHASE_FIRE: int = 2
const PHASE_END: int = 3
const SOFT_REF: float = 2.5
const CORE_REF: float = 1.2
const PREP_D_REF: float = 3.6
const TIP_FRAC: float = 42.84 / 48.84
const FLOW_REF: float = 3.0
const PREP_ALPHA_REF: float = 0.0
## SEMI_ASYNC: quantize aim angles as rad × ANG_SCALE → i16.
const ANG_SCALE: float = 10000.0
const SFX_PREP: String = "res://assets/audio/weapon_sfx/laser/unk/113964752_indicator_beam_activation.wav"
const SFX_START: String = "res://assets/audio/weapon_sfx/laser/unk/200040170_damage_beam_start.wav"
const SFX_LOOP: String = "res://assets/audio/weapon_sfx/laser/unk/1030500503_black-laser.wav"
const SFX_END: String = "res://assets/audio/weapon_sfx/laser/unk/182843022_damage_beam_end.wav"

static func is_lance_def(def: Dictionary) -> bool:
	return str(def.get("id", "")) == MODULE_ID or str(def.get("activate", "")) == "mixed_lance"


static func capital_role_allowed(ship_data: Dictionary, def: Dictionary) -> bool:
	var want_v: Variant = def.get("require_capital_roles", [])
	if typeof(want_v) != TYPE_ARRAY:
		return true
	var want: Array = TypedVariant.as_array(want_v)
	if want.is_empty():
		return true
	var role: String = str(ship_data.get("capital_role", "")).to_lower()
	var group: String = str(ship_data.get("ship_group", "")).to_lower()
	for w: Variant in want:
		var key: String = str(w).to_lower()
		if key != "" and (role == key or group == key):
			return true
	return false


static func ship_has_lance_line(ship: ShipUnit, exclude_id: String = "") -> bool:
	for entry: Variant in ship.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		var fid: String = str(e.get("id", "")).strip_edges()
		if exclude_id != "" and fid == exclude_id:
			continue
		var d: Dictionary = TypedVariant.as_dict(e.get("def", DataStore.get_function_module(fid)))
		if is_lance_def(d) or str(d.get("line", "")) == "mixed_lance":
			return true
	return false


static func board_diagonal_wu() -> float:
	var bb: Vector4 = BoardController.combat_play_bounds_xz(0.0)
	var sx: float = bb.y - bb.x
	var sz: float = bb.w - bb.z
	return maxf(1.0, sqrt(sx * sx + sz * sz))


static func tick(
	ship: ShipUnit,
	board: BoardController,
	fid: String,
	def: Dictionary,
	sim_dt: float,
	_sim_time: float,
) -> void:
	if ship == null or not is_instance_valid(ship) or board == null:
		return
	var rt: Dictionary = FunctionFit._runtime(ship, fid)
	var phase: int = TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE)
	if phase == PHASE_IDLE:
		## Idle: wait for flush_salvo (board-wide 齐射). Do not start here.
		return
	ship.set("lance_suppress_weapons", true)
	rt["lance_phase_t"] = TypedVariant.as_float(rt.get("lance_phase_t", 0.0)) + sim_dt
	var phase_t: float = TypedVariant.as_float(rt.get("lance_phase_t", 0.0))
	match phase:
		PHASE_PREP:
			_update_fx(ship, rt, 0.0, true)
			_tick_sfx(ship, rt, "prep")
			if phase_t >= TypedVariant.as_float(def.get("prep_sec", 10.0)):
				_enter_fire(ship, fid, rt)
		PHASE_FIRE:
			_update_fx(ship, rt, 0.0, false)
			_tick_sfx(ship, rt, "fire")
			_tick_damage(ship, board, def, rt, sim_dt, 1.0)
			if phase_t >= TypedVariant.as_float(def.get("fire_sec", 10.0)):
				_enter_end(ship, fid, rt)
		PHASE_END:
			var end_sec: float = maxf(0.05, TypedVariant.as_float(def.get("end_sec", 2.1)))
			var shrink: float = clampf(1.0 - phase_t / end_sec, 0.0, 1.0)
			_update_fx(ship, rt, 1.0 - shrink, false)
			_tick_sfx(ship, rt, "end")
			if shrink > 0.02:
				_tick_damage(ship, board, def, rt, sim_dt, shrink)
			if phase_t >= end_sec:
				_consume(ship, fid, rt)
				return
	ship._function_runtime[fid] = rt


static func abort_combat_end(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	for entry: Variant in ship.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		var fid: String = str(e.get("id", "")).strip_edges()
		var def: Dictionary = TypedVariant.as_dict(e.get("def", {}))
		if not is_lance_def(def):
			continue
		var rt: Dictionary = FunctionFit._runtime(ship, fid)
		var phase: int = TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE)
		if phase != PHASE_IDLE:
			_consume(ship, fid, rt)
		return


static func _try_start(
	ship: ShipUnit,
	board: BoardController,
	fid: String,
	def: Dictionary,
	rt: Dictionary,
	_sim_time: float,
) -> void:
	_commit_start(ship, board, fid, def, rt)


## CAPITAL §4.1 / SEMI_ASYNC：未消耗长枪等齐停稳后同一 tick 齐射落锁。
static func flush_salvo(board: BoardController) -> void:
	if board == null:
		return
	var blockers: int = 0
	var eligible: Array = []
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.slot_type != "field":
			continue
		for entry: Variant in s.get_function_fit():
			var e: Dictionary = TypedVariant.as_dict(entry)
			var fid: String = str(e.get("id", "")).strip_edges()
			var def: Dictionary = TypedVariant.as_dict(e.get("def", {}))
			if not is_lance_def(def):
				continue
			var rt: Dictionary = FunctionFit._runtime(s, fid)
			if TypedVariant.as_bool(rt.get("lance_spent", false), false):
				continue
			var phase: int = TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE)
			if phase != PHASE_IDLE:
				continue
			if not _ship_ready_to_aim(s):
				blockers += 1
				break
			var tgt: ShipUnit = _pick_target(s, board)
			if tgt == null:
				## Settled but no enemy — not a blocker; cannot join this salvo.
				break
			eligible.append({"ship": s, "fid": fid, "def": def, "rt": rt})
			break
	if blockers > 0 or eligible.is_empty():
		return
	for row_v: Variant in eligible:
		var row: Dictionary = TypedVariant.as_dict(row_v)
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = row.get("ship") as ShipUnit
		if ship == null or not is_instance_valid(ship):
			continue
		_commit_start(
			ship,
			board,
			str(row.get("fid", "")),
			TypedVariant.as_dict(row.get("def", {})),
			TypedVariant.as_dict(row.get("rt", {})),
		)
	## One force-full so the trailer carries every angle group together.
	_request_net_full_on_lock()


static func _commit_start(
	ship: ShipUnit,
	board: BoardController,
	fid: String,
	def: Dictionary,
	rt: Dictionary,
) -> void:
	if TypedVariant.as_bool(rt.get("lance_spent", false), false):
		return
	if TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE) != PHASE_IDLE:
		return
	## CAPITAL §4.1: aim only after full land + move settled.
	if not _ship_ready_to_aim(ship):
		ship.set("lance_suppress_weapons", false)
		return
	var tgt: ShipUnit = _pick_target(ship, board)
	if tgt == null:
		ship.set("lance_suppress_weapons", false)
		return
	var origin: Vector3 = ship.global_position
	if ship.has_method("get_muzzle_global"):
		var mz: Variant = ship.call("get_muzzle_global")
		if typeof(mz) == TYPE_VECTOR3:
			origin = mz
	var tip_dir: Vector3 = tgt.global_position - origin
	if tip_dir.length_squared() < 0.0001:
		tip_dir = -ship.global_transform.basis.z
	tip_dir = tip_dir.normalized()
	var beam_h: float = board_diagonal_wu()
	var soft: float = TypedVariant.as_float(def.get("attack_diameter", SOFT_REF))
	var soft_ref: float = TypedVariant.as_float(def.get("soft_d_ref", SOFT_REF))
	var d_scale: float = soft / maxf(soft_ref, 0.001)
	rt["lance_phase"] = PHASE_PREP
	rt["lance_phase_t"] = 0.0
	rt["lance_tick_acc"] = 0.0
	rt["lance_origin"] = origin
	rt["lance_dir"] = tip_dir
	rt["lance_az_xz"] = dir_to_az_xz(tip_dir)
	rt["lance_el_xy"] = dir_to_el_xy(tip_dir)
	rt["lance_beam_h"] = beam_h
	rt["lance_soft"] = soft
	rt["lance_core"] = TypedVariant.as_float(def.get("core_d_ref", CORE_REF)) * d_scale
	rt["lance_prep_d"] = TypedVariant.as_float(def.get("prepare_d_ref", PREP_D_REF)) * d_scale
	rt["lance_tip_frac"] = TIP_FRAC
	rt["lance_flow"] = TypedVariant.as_float(def.get("flow_speed", FLOW_REF))
	rt["lance_prep_alpha"] = TypedVariant.as_float(def.get("prepare_alpha", PREP_ALPHA_REF))
	rt["lance_guest"] = false
	ship.set("lance_suppress_weapons", true)
	_ensure_fx(ship, rt, true)
	_start_sfx(ship, rt, "prep")
	ship._function_runtime[fid] = rt
	SessionDiagnostics.log("lance.prep", "ship=%d tgt=%d beam_h=%.1f soft=%.2f az=%.3f el=%.3f" % [
		ship.ship_id, tgt.ship_id, beam_h, soft,
		TypedVariant.as_float(rt.get("lance_az_xz", 0.0)),
		TypedVariant.as_float(rt.get("lance_el_xy", 0.0)),
	])


static func dir_to_az_xz(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


static func dir_to_el_xy(dir: Vector3) -> float:
	var horiz: float = sqrt(dir.x * dir.x + dir.z * dir.z)
	var el: float = atan2(dir.y, maxf(horiz, 0.0001))
	const EL_LIMIT: float = PI / 6.0 ## ±30°
	return clampf(el, -EL_LIMIT, EL_LIMIT)


static func angles_to_dir(az_xz: float, el_xy: float) -> Vector3:
	var c: float = cos(el_xy)
	var d: Vector3 = Vector3(sin(az_xz) * c, sin(el_xy), cos(az_xz) * c)
	if d.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return d.normalized()


static func quant_angle(rad: float) -> int:
	return clampi(roundi(rad * ANG_SCALE), -32768, 32767)


static func dequant_angle(q: int) -> float:
	return float(q) / ANG_SCALE


static func _request_net_full_on_lock() -> void:
	## SEMI_ASYNC §3.3.1 A — force full so guests get az/el immediately.
	var live: NetBattleSession = NetBattleSession.live_session()
	if live != null and live.is_host:
		live.request_force_full_sync()


## True if any ship is in Prep/Fire/End (no roster index needed).
static func has_any_active(board: BoardController) -> bool:
	if board == null:
		return false
	for s_v: Variant in board.all_ships():
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if not _active_aim_on_ship(s).is_empty():
			return true
	return false


## Active Prep/Fire/End aims for the full-packet trailer (host).
static func collect_active_aim_rows(ships: Array, idx_of_iid: Callable) -> Array:
	var rows: Array = []
	for s_v: Variant in ships:
		if not (s_v is ShipUnit):
			continue
		var s: ShipUnit = s_v
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		var aim: Dictionary = _active_aim_on_ship(s)
		if aim.is_empty():
			continue
		var idx: int = TypedVariant.as_int(idx_of_iid.call(s.get_instance_id()), -1)
		if idx < 0 or idx == NetWireCodec.NO_IDX:
			continue
		rows.append({
			"idx": idx,
			"az_xz": TypedVariant.as_float(aim.get("az_xz", 0.0)),
			"el_xy": TypedVariant.as_float(aim.get("el_xy", 0.0)),
		})
	return rows


static func _active_aim_on_ship(ship: ShipUnit) -> Dictionary:
	for entry: Variant in ship.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		var fid: String = str(e.get("id", "")).strip_edges()
		var def: Dictionary = TypedVariant.as_dict(e.get("def", {}))
		if not is_lance_def(def):
			continue
		var rt: Dictionary = FunctionFit._runtime(ship, fid)
		var phase: int = TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE)
		if phase == PHASE_IDLE:
			continue
		var dir: Vector3 = TypedVariant.as_vector3(rt.get("lance_dir", Vector3.ZERO))
		var az: float
		var el: float
		if rt.has("lance_az_xz") and rt.has("lance_el_xy"):
			az = TypedVariant.as_float(rt.get("lance_az_xz", 0.0))
			el = TypedVariant.as_float(rt.get("lance_el_xy", 0.0))
		else:
			if dir.length_squared() < 0.0001:
				continue
			az = dir_to_az_xz(dir)
			el = dir_to_el_xy(dir)
		return {"az_xz": az, "el_xy": el, "fid": fid}
	return {}


## Guest: apply authority aim angles and start local FX-only timeline.
static func apply_guest_aim(ship: ShipUnit, az_xz: float, el_xy: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	const EL_LIMIT: float = PI / 6.0
	el_xy = clampf(el_xy, -EL_LIMIT, EL_LIMIT)
	var fid: String = ""
	var def: Dictionary = {}
	for entry: Variant in ship.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		var d: Dictionary = TypedVariant.as_dict(e.get("def", {}))
		if is_lance_def(d):
			fid = str(e.get("id", "")).strip_edges()
			def = d
			break
	if fid == "" or def.is_empty():
		## Fit may lag; still stash angles on a synthetic runtime key.
		fid = MODULE_ID
		def = DataStore.get_function_module(MODULE_ID)
	var rt: Dictionary = FunctionFit._runtime(ship, fid)
	var phase: int = TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE)
	var dir: Vector3 = angles_to_dir(az_xz, el_xy)
	var same: bool = (
		phase != PHASE_IDLE
		and absf(TypedVariant.as_float(rt.get("lance_az_xz", 0.0)) - az_xz) < 0.001
		and absf(TypedVariant.as_float(rt.get("lance_el_xy", 0.0)) - el_xy) < 0.001
	)
	if same:
		rt["lance_dir"] = dir
		ship._function_runtime[fid] = rt
		return
	var origin: Vector3 = ship.global_position
	if ship.has_method("get_muzzle_global"):
		var mz: Variant = ship.call("get_muzzle_global")
		if typeof(mz) == TYPE_VECTOR3:
			origin = mz
	var soft: float = TypedVariant.as_float(def.get("attack_diameter", SOFT_REF))
	var soft_ref: float = TypedVariant.as_float(def.get("soft_d_ref", SOFT_REF))
	var d_scale: float = soft / maxf(soft_ref, 0.001)
	rt["lance_phase"] = PHASE_PREP if phase == PHASE_IDLE else phase
	if phase == PHASE_IDLE:
		rt["lance_phase_t"] = 0.0
	rt["lance_guest"] = true
	rt["lance_az_xz"] = az_xz
	rt["lance_el_xy"] = el_xy
	rt["lance_dir"] = dir
	rt["lance_origin"] = origin
	rt["lance_beam_h"] = board_diagonal_wu()
	rt["lance_soft"] = soft
	rt["lance_core"] = TypedVariant.as_float(def.get("core_d_ref", CORE_REF)) * d_scale
	rt["lance_prep_d"] = TypedVariant.as_float(def.get("prepare_d_ref", PREP_D_REF)) * d_scale
	rt["lance_tip_frac"] = TIP_FRAC
	rt["lance_flow"] = TypedVariant.as_float(def.get("flow_speed", FLOW_REF))
	rt["lance_prep_alpha"] = TypedVariant.as_float(def.get("prepare_alpha", PREP_ALPHA_REF))
	ship.set("lance_suppress_weapons", true)
	_ensure_fx(ship, rt, TypedVariant.as_int(rt.get("lance_phase", PHASE_PREP)) == PHASE_PREP)
	if phase == PHASE_IDLE:
		_start_sfx(ship, rt, "prep")
	ship._function_runtime[fid] = rt


static func clear_guest_aim(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var ids: Array = []
	for entry: Variant in ship.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		var fid: String = str(e.get("id", "")).strip_edges()
		var def: Dictionary = TypedVariant.as_dict(e.get("def", {}))
		if is_lance_def(def) or fid == MODULE_ID:
			ids.append(fid)
	if not ids.has(MODULE_ID) and ship._function_runtime.has(MODULE_ID):
		ids.append(MODULE_ID)
	for fid_v: Variant in ids:
		var fid2: String = str(fid_v)
		var rt: Dictionary = FunctionFit._runtime(ship, fid2)
		if not TypedVariant.as_bool(rt.get("lance_guest", false), false):
			continue
		if TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE) == PHASE_IDLE:
			continue
		_cleanup_fx(rt)
		_stop_all_sfx(rt)
		ship.set("lance_suppress_weapons", false)
		rt["lance_phase"] = PHASE_IDLE
		rt["lance_guest"] = false
		ship._function_runtime[fid2] = rt


## Guest FX-only timeline (no damage / no consume unequip).
static func guest_tick_visual(ship: ShipUnit, delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or delta <= 0.0:
		return
	for entry: Variant in ship.get_function_fit():
		var e: Dictionary = TypedVariant.as_dict(entry)
		var fid: String = str(e.get("id", "")).strip_edges()
		var def: Dictionary = TypedVariant.as_dict(e.get("def", DataStore.get_function_module(fid)))
		if not is_lance_def(def):
			continue
		var rt: Dictionary = FunctionFit._runtime(ship, fid)
		if TypedVariant.as_bool(rt.get("lance_guest", false), false):
			_guest_advance_visual(ship, fid, def, delta)
			return
	if ship._function_runtime.has(MODULE_ID):
		var rt2: Dictionary = FunctionFit._runtime(ship, MODULE_ID)
		if TypedVariant.as_bool(rt2.get("lance_guest", false), false):
			_guest_advance_visual(ship, MODULE_ID, DataStore.get_function_module(MODULE_ID), delta)


static func _guest_advance_visual(ship: ShipUnit, fid: String, def: Dictionary, delta: float) -> void:
	var rt: Dictionary = FunctionFit._runtime(ship, fid)
	var phase: int = TypedVariant.as_int(rt.get("lance_phase", PHASE_IDLE), PHASE_IDLE)
	if phase == PHASE_IDLE:
		return
	rt["lance_phase_t"] = TypedVariant.as_float(rt.get("lance_phase_t", 0.0)) + delta
	var phase_t: float = TypedVariant.as_float(rt.get("lance_phase_t", 0.0))
	match phase:
		PHASE_PREP:
			_update_fx(ship, rt, 0.0, true)
			_tick_sfx(ship, rt, "prep")
			if phase_t >= TypedVariant.as_float(def.get("prep_sec", 10.0)):
				rt["lance_phase"] = PHASE_FIRE
				rt["lance_phase_t"] = 0.0
				_ensure_fx(ship, rt, false)
				_stop_sfx(rt, "prep")
				_start_sfx(ship, rt, "fire")
				## Presentation path — same title hook as sim `_enter_fire`.
				var b: BoardController = null
				if ship.get_tree() != null and ship.get_tree().current_scene != null:
					var scn: Node = ship.get_tree().current_scene
					var bv: Variant = scn.get("board")
					if bv is BoardController:
						@warning_ignore("unsafe_cast")
						b = bv as BoardController
				_notify_match_lance_fire(ship, b, rt)
		PHASE_FIRE:
			_update_fx(ship, rt, 0.0, false)
			_tick_sfx(ship, rt, "fire")
			if phase_t >= TypedVariant.as_float(def.get("fire_sec", 10.0)):
				rt["lance_phase"] = PHASE_END
				rt["lance_phase_t"] = 0.0
				_stop_sfx(rt, "fire")
				_start_sfx(ship, rt, "end")
		PHASE_END:
			var end_sec: float = maxf(0.05, TypedVariant.as_float(def.get("end_sec", 2.1)))
			var shrink: float = clampf(1.0 - phase_t / end_sec, 0.0, 1.0)
			_update_fx(ship, rt, 1.0 - shrink, false)
			_tick_sfx(ship, rt, "end")
			if phase_t >= end_sec:
				_cleanup_fx(rt)
				_stop_all_sfx(rt)
				ship.set("lance_suppress_weapons", false)
				rt["lance_phase"] = PHASE_IDLE
				rt["lance_guest"] = false
	ship._function_runtime[fid] = rt


static func _ship_ready_to_aim(ship: ShipUnit) -> bool:
	if ship == null or not is_instance_valid(ship) or ship.is_destroyed:
		return false
	if str(ship.slot_type) != "field":
		return false
	if TypedVariant.as_bool(ship.get("capital_jumping"), false):
		return false
	if TypedVariant.as_bool(ship.get("hull_morph_unstacking"), false):
		return false
	## Settled: no meaningful horizontal slide left.
	var spd: float = 0.0
	if ship.has_method("combat_speed_now"):
		spd = TypedVariant.as_float(ship.call("combat_speed_now"), 0.0)
	return spd < 0.08


## Aim target must already be landed — mid-jump / unstack locks shoot empty air.
static func _target_lockable(o: ShipUnit) -> bool:
	if o == null or not is_instance_valid(o) or o.is_destroyed:
		return false
	if str(o.slot_type) != "field":
		return false
	if TypedVariant.as_bool(o.get("capital_jumping"), false):
		return false
	if TypedVariant.as_bool(o.get("hull_morph_unstacking"), false):
		return false
	return true


static func _enter_fire(ship: ShipUnit, fid: String, rt: Dictionary) -> void:
	rt["lance_phase"] = PHASE_FIRE
	rt["lance_phase_t"] = 0.0
	rt["lance_tick_acc"] = 0.0
	_ensure_fx(ship, rt, false)
	_stop_sfx(rt, "prep")
	_start_sfx(ship, rt, "fire")
	ship._function_runtime[fid] = rt
	var board: BoardController = null
	if ship.get_tree() != null and ship.get_tree().current_scene != null:
		var sc: Node = ship.get_tree().current_scene
		var bv: Variant = sc.get("board")
		if bv is BoardController:
			@warning_ignore("unsafe_cast")
			board = bv as BoardController
	_notify_match_lance_fire(ship, board, rt)


static func _notify_match_lance_fire(ship: ShipUnit, board: BoardController, rt: Dictionary = {}) -> void:
	if not rt.is_empty() and TypedVariant.as_bool(rt.get("lance_fire_noted", false), false):
		return
	if not rt.is_empty():
		rt["lance_fire_noted"] = true
	var sc: Node = _match_scene(ship)
	if sc != null and sc.has_method("note_match_lance_fire"):
		sc.call("note_match_lance_fire", ship, board)


static func _notify_match_lance_hit(src: ShipUnit, tgt: ShipUnit, dealt: float, destroyed: bool) -> void:
	var sc: Node = _match_scene(src)
	if sc != null and sc.has_method("note_match_lance_hit"):
		sc.call("note_match_lance_hit", src, tgt, dealt, destroyed)


static func _match_scene(ship: ShipUnit) -> Node:
	if ship == null or not is_instance_valid(ship) or ship.get_tree() == null:
		return null
	return ship.get_tree().current_scene


static func _enter_end(ship: ShipUnit, fid: String, rt: Dictionary) -> void:
	rt["lance_phase"] = PHASE_END
	rt["lance_phase_t"] = 0.0
	_stop_sfx(rt, "fire")
	_start_sfx(ship, rt, "end")
	ship._function_runtime[fid] = rt


static func _consume(ship: ShipUnit, fid: String, rt: Dictionary) -> void:
	_cleanup_fx(rt)
	_stop_all_sfx(rt)
	ship.set("lance_suppress_weapons", false)
	rt["lance_phase"] = PHASE_IDLE
	rt["lance_spent"] = true
	ship._function_runtime[fid] = rt
	var fit: Array = ship.get_function_fit()
	for i: int in range(fit.size()):
		if str(TypedVariant.as_dict(fit[i]).get("id", "")) == fid:
			ship.unequip_function_at(i)
			SessionDiagnostics.log("lance.consumed", "ship=%d slot=%d" % [ship.ship_id, i])
			break


static func _pick_target(ship: ShipUnit, board: BoardController) -> ShipUnit:
	var best_dread: ShipUnit = null
	var best_dread_d: float = INF
	var best_any: ShipUnit = null
	var best_any_d: float = INF
	for o: ShipUnit in board.all_ships():
		if o == null or not is_instance_valid(o):
			continue
		if o.team_id == ship.team_id:
			continue
		if not _target_lockable(o):
			continue
		var d: float = ship.global_position.distance_to(o.global_position)
		var sd: Dictionary = DataStore.get_ship(o.ship_id)
		var role: String = str(sd.get("capital_role", "")).to_lower()
		var group: String = str(sd.get("ship_group", "")).to_lower()
		var is_dread: bool = role == "dreadnought" or group == "dreadnought"
		if is_dread and d < best_dread_d:
			best_dread_d = d
			best_dread = o
		if d < best_any_d:
			best_any_d = d
			best_any = o
	if best_dread != null:
		return best_dread
	return best_any


static func _tick_damage(
	ship: ShipUnit,
	board: BoardController,
	def: Dictionary,
	rt: Dictionary,
	sim_dt: float,
	shrink: float,
) -> void:
	var tick_sec: float = maxf(0.05, TypedVariant.as_float(def.get("tick_sec", 0.5)))
	rt["lance_tick_acc"] = TypedVariant.as_float(rt.get("lance_tick_acc", 0.0)) + sim_dt
	while TypedVariant.as_float(rt.get("lance_tick_acc", 0.0)) >= tick_sec:
		rt["lance_tick_acc"] = TypedVariant.as_float(rt.get("lance_tick_acc", 0.0)) - tick_sec
		_apply_column_hit(ship, board, def, rt, shrink)


static func _apply_column_hit(
	ship: ShipUnit,
	board: BoardController,
	def: Dictionary,
	rt: Dictionary,
	shrink: float,
) -> void:
	var origin: Vector3 = TypedVariant.as_vector3(rt.get("lance_origin", Vector3.ZERO))
	var dir: Vector3 = TypedVariant.as_vector3(rt.get("lance_dir", Vector3.FORWARD)).normalized()
	if dir.length_squared() < 0.0001:
		return
	var beam_h: float = TypedVariant.as_float(rt.get("lance_beam_h", board_diagonal_wu())) * shrink
	var radius: float = TypedVariant.as_float(rt.get("lance_soft", SOFT_REF)) * 0.5 * shrink
	if beam_h < 0.05 or radius < 0.01:
		return
	## Per tick (default 0.5s): raw = max(floor, maxHP×pct); NOT once for whole Fire.
	var pct: float = TypedVariant.as_float(def.get("damage_hp_pct", 0.05))
	var floor_v: float = TypedVariant.as_float(def.get("damage_floor", 1000.0))
	var heal_mul: float = TypedVariant.as_float(def.get("heal_received_mul", 0.2))
	var heal_dur: float = TypedVariant.as_float(def.get("heal_debuff_sec", 60.0))
	## −90% move speed → remaining ×0.1; refresh each tick (CAPITAL §4.1).
	var speed_mul: float = TypedVariant.as_float(def.get("speed_mul", 0.1))
	var speed_dur: float = TypedVariant.as_float(def.get("speed_debuff_sec", heal_dur))
	var hit_n: int = 0
	var raw_sample: float = 0.0
	var dealt_sum: float = 0.0
	for o: ShipUnit in board.all_ships():
		if o == null or not is_instance_valid(o) or o.is_destroyed or o.slot_type != "field":
			continue
		if not _point_in_cylinder(o.global_position, origin, dir, beam_h, radius):
			continue
		var max_hp: float = o.max_shield + o.max_armor + o.max_structure
		var raw: float = maxf(floor_v, max_hp * pct)
		var quarter: float = raw * 0.25
		var dmg: Dictionary = {
			"emp": quarter,
			"thermal": quarter,
			"kinetic": quarter,
			"explosive": quarter,
		}
		## Via combat.hit → resists in apply_hit_dict + float text / eval / net.
		var res: Dictionary = AdminBus.request(&"combat.hit", {
			"source_id": ship.get_instance_id(),
			"target_id": o.get_instance_id(),
			"damage": dmg,
			"via": "mixed_lance",
		})
		var dealt: float = TypedVariant.as_float(res.get("dealt", 0.0), 0.0)
		if dealt <= 0.0:
			## Fallback if AdminBus not wired (editor / early boot).
			res = o.apply_hit_dict(dmg, true)
			dealt = TypedVariant.as_float(res.get("dealt", 0.0), 0.0)
		hit_n += 1
		raw_sample = raw
		dealt_sum += dealt
		_notify_match_lance_hit(ship, o, dealt, TypedVariant.as_bool(res.get("destroyed", false), false))
		if o.has_method("apply_heal_received_mul"):
			o.call("apply_heal_received_mul", heal_mul, heal_dur)
		if o.has_method("add_stat_modifier"):
			o.add_stat_modifier(
				"mixed_lance", "speed", "mul", speed_mul, speed_dur, "mixed_lance_speed"
			)
	if hit_n > 0:
		SessionDiagnostics.log(
			"lance.hit",
			"src=%d n=%d raw=%.0f dealt_sum=%.0f r=%.2f h=%.1f" % [
				ship.ship_id, hit_n, raw_sample, dealt_sum, radius, beam_h,
			]
		)


static func _point_in_cylinder(p: Vector3, origin: Vector3, dir: Vector3, height: float, radius: float) -> bool:
	var rel: Vector3 = p - origin
	var along: float = rel.dot(dir)
	if along < -0.25 or along > height + 0.25:
		return false
	var radial: Vector3 = rel - dir * along
	return radial.length() <= radius + 0.35


static func _ensure_fx(ship: ShipUnit, rt: Dictionary, prepare: bool) -> void:
	var fx_id: int = TypedVariant.as_int(rt.get("lance_fx_id", 0), 0)
	var fx: Node = instance_from_id(fx_id) if fx_id != 0 else null
	if fx == null or not is_instance_valid(fx):
		var script: Script = load("res://scripts/combat/mixed_lance_fx.gd") as Script
		if script == null:
			return
		fx = Node3D.new()
		fx.set_script(script)
		var host: Node = ship
		if ship.get_tree() != null and ship.get_tree().current_scene != null:
			host = ship.get_tree().current_scene
		host.add_child(fx)
		rt["lance_fx_id"] = fx.get_instance_id()
	if fx.has_method("configure"):
		fx.call(
			"configure",
			TypedVariant.as_float(rt.get("lance_beam_h", board_diagonal_wu())),
			TypedVariant.as_float(rt.get("lance_soft", SOFT_REF)),
			TypedVariant.as_float(rt.get("lance_core", CORE_REF)),
			TypedVariant.as_float(rt.get("lance_prep_d", PREP_D_REF)),
			TypedVariant.as_float(rt.get("lance_tip_frac", TIP_FRAC)),
			prepare,
			TypedVariant.as_float(rt.get("lance_prep_alpha", PREP_ALPHA_REF)),
			TypedVariant.as_float(rt.get("lance_flow", FLOW_REF)),
		)
	_update_fx(ship, rt, 0.0, prepare)


static func _update_fx(ship: ShipUnit, rt: Dictionary, shrink_amount: float, prepare: bool) -> void:
	var fx_id: int = TypedVariant.as_int(rt.get("lance_fx_id", 0), 0)
	if fx_id == 0:
		return
	var fx: Node = instance_from_id(fx_id)
	if fx == null or not is_instance_valid(fx) or not fx.has_method("set_pose"):
		return
	var origin: Vector3 = TypedVariant.as_vector3(rt.get("lance_origin", ship.global_position))
	var dir: Vector3 = TypedVariant.as_vector3(rt.get("lance_dir", Vector3.FORWARD))
	if dir.length_squared() < 0.0001:
		return
	var scale_mul: float = clampf(1.0 - shrink_amount, 0.0, 1.0)
	fx.call("set_pose", origin, dir, scale_mul, prepare)


static func _cleanup_fx(rt: Dictionary) -> void:
	var fx_id: int = TypedVariant.as_int(rt.get("lance_fx_id", 0), 0)
	rt["lance_fx_id"] = 0
	if fx_id == 0:
		return
	var fx: Node = instance_from_id(fx_id)
	if fx != null and is_instance_valid(fx):
		fx.queue_free()


static func _start_sfx(ship: ShipUnit, rt: Dictionary, kind: String) -> void:
	var path: String = ""
	var loop: bool = false
	match kind:
		"prep":
			path = SFX_PREP
			loop = true
		"fire":
			_play_oneshot(ship, SFX_START)
			path = SFX_LOOP
			loop = true
		"end":
			path = SFX_END
			loop = false
		_:
			return
	var player: AudioStreamPlayer = _ensure_player(ship, rt, kind)
	if player == null:
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamWAV:
		stream = (stream as AudioStreamWAV).duplicate()
		(stream as AudioStreamWAV).loop_mode = (
			AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		)
	player.stream = stream
	SfxBus.begin_play(player, 0.0)
	player.play()


static func _tick_sfx(ship: ShipUnit, rt: Dictionary, kind: String) -> void:
	var player: AudioStreamPlayer = _ensure_player(ship, rt, kind)
	if player == null or kind == "end":
		return
	if not player.playing and player.stream != null:
		SfxBus.begin_play(player, 0.0)
		player.play()


static func _stop_sfx(rt: Dictionary, kind: String) -> void:
	var key: String = "lance_sfx_%s" % kind
	var pid: int = TypedVariant.as_int(rt.get(key, 0), 0)
	if pid == 0:
		return
	var n: Node = instance_from_id(pid)
	if n is AudioStreamPlayer and is_instance_valid(n):
		var p: AudioStreamPlayer = n as AudioStreamPlayer
		SfxBus.end_play(p)
		p.stop()


static func _stop_all_sfx(rt: Dictionary) -> void:
	for kind: String in ["prep", "fire", "end"]:
		_stop_sfx(rt, kind)


static func _ensure_player(ship: ShipUnit, rt: Dictionary, kind: String) -> AudioStreamPlayer:
	var key: String = "lance_sfx_%s" % kind
	var pid: int = TypedVariant.as_int(rt.get(key, 0), 0)
	if pid != 0:
		var existing: Node = instance_from_id(pid)
		if existing is AudioStreamPlayer and is_instance_valid(existing):
			return existing as AudioStreamPlayer
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = "LanceSfx_%s" % kind
	SfxBus.route(p)
	ship.add_child(p)
	rt[key] = p.get_instance_id()
	return p


static func _play_oneshot(ship: ShipUnit, path: String) -> void:
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	SfxBus.route(p)
	ship.add_child(p)
	p.stream = stream
	p.finished.connect(func() -> void:
		SfxBus.end_play(p)
		p.queue_free()
	)
	SfxBus.begin_play(p, 0.0)
	p.play()
