extends RefCounted
class_name CombatFormulas
## EVE-like turret / missile / lock formulas — see eveautochess-design/docs/COMBAT.md

static func world_units_per_cell() -> float:
	return TypedVariant.as_float(
		DataStore.combat.get("world_units_per_cell", absf(TypedVariant.as_float(DataStore.board.get("hex_offset_x", 3.0), 3.0))),
		absf(TypedVariant.as_float(DataStore.board.get("hex_offset_x", 3.0), 3.0))
	)

static func grid_distance_cells(a: Node3D, b: Node3D) -> float:
	var wu: float = world_units_per_cell()
	if wu <= 0.0001:
		return 0.0
	## Off-deck either side → true 3D (COMBAT §11 / §14.2). Both on deck → flatten XZ.
	var off: bool = false
	if a != null:
		@warning_ignore("unsafe_method_access")
		if a.has_method("off_deck_plane"):
			@warning_ignore("unsafe_method_access")
			off = TypedVariant.as_bool(a.call("off_deck_plane"), false)
	if not off and b != null:
		@warning_ignore("unsafe_method_access")
		if b.has_method("off_deck_plane"):
			@warning_ignore("unsafe_method_access")
			off = TypedVariant.as_bool(b.call("off_deck_plane"), false)
	if off:
		return a.global_position.distance_to(b.global_position) / wu
	var flat_a: Vector3 = Vector3(a.global_position.x, 0.0, a.global_position.z)
	var flat_b: Vector3 = Vector3(b.global_position.x, 0.0, b.global_position.z)
	return flat_a.distance_to(flat_b) / wu

static func distance_meters(cells: float) -> float:
	## Range path: 1 cell = 2 km, same as tracking (COMBAT §3.1 格距语义).
	return cells * TypedVariant.as_float(DataStore.combat.get("meters_per_cell", 2000.0), 2000.0)

static func tracking_distance_meters(cells: float) -> float:
	## Turret angular-velocity path only: 1 cell = 2 km (2000 m) by design.
	return cells * TypedVariant.as_float(DataStore.combat.get("tracking_meters_per_cell", 2000.0), 2000.0)

static func optimal_meters(km_value: float) -> float:
	## Legacy helper if raw EVE km ever passed in.
	return km_value * 1000.0


static func cells_to_meters(cells: float) -> float:
	return distance_meters(cells)


static func turret_hit_chance(
	attacker_tracking: float,
	attacker_optimal_cells: float,
	attacker_falloff_cells: float,
	attacker_optimal_sig: float,
	target_speed: float,
	target_signature: float,
	distance_cells: float
) -> float:
	## `optimal` / `falloff` on ship stars are already in board cells (gen_content_data).
	if attacker_tracking <= 0.0:
		return 0.0
	## Tracking ω uses 1 cell = 2 km; range_term still uses meters_per_cell.
	var d_track: float = tracking_distance_meters(distance_cells)
	var d_m: float = distance_meters(distance_cells)
	var v: float = maxf(target_speed, 0.0)
	var omega: float = v / maxf(d_track, 1.0)
	var sig_res: float = maxf(attacker_optimal_sig, 1.0)
	var sig_tgt: float = maxf(target_signature, 1.0)
	var tracking_term: float = (omega / attacker_tracking) * (sig_res / sig_tgt)
	var r_opt: float = cells_to_meters(attacker_optimal_cells)
	var r_fo: float = maxf(cells_to_meters(attacker_falloff_cells), 1.0)
	var range_term: float = maxf(0.0, d_m - r_opt) / r_fo
	var exponent: float = tracking_term * tracking_term + range_term * range_term
	var p: float = pow(0.5, exponent)
	var lo: float = TypedVariant.as_float(DataStore.combat.get("hit_chance_min", 0.01), 0.01)
	var hi: float = TypedVariant.as_float(DataStore.combat.get("hit_chance_max", 0.99), 0.99)
	return clampf(p, lo, hi)


## COMBAT §11.1 — same X as turret_hit: 0 = miss, else damage quality mul.
static func turret_hit_quality(x: float, p_hit: float) -> float:
	if x > p_hit:
		return 0.0
	if x < 0.01:
		return 3.0
	return x + 0.5


## COMBAT §12 — TQ / EVE Uni missile DR (not EVEMU product form).
static func missile_damage_factor(
	target_signature: float,
	target_speed: float,
	explosion_radius: float,
	explosion_velocity: float,
	drf: float,
	drs: float
) -> float:
	var er: float = maxf(explosion_radius, 1.0)
	var ev: float = maxf(explosion_velocity, 1.0)
	var sig: float = maxf(target_signature, 1.0)
	var vt: float = maxf(target_speed, 0.0)
	var sig_ratio: float = sig / er
	if drf <= 0.0:
		return minf(1.0, sig_ratio)
	## Dogma may store raw DRF (>1 → ln/ln) or already-baked exponent (≤1, e.g. 0.604).
	var drf_exp: float = drf
	if drf > 1.0:
		var drs_eff: float = drs
		if drs_eff <= 1.0:
			drs_eff = TypedVariant.as_float(DataStore.combat.get("missile_drs_default", 5.5), 5.5)
			if drs_eff <= 1.0:
				drs_eff = 5.5
		drf_exp = log(drf) / log(drs_eff)
	var vt_eff: float = maxf(vt, 0.0001)
	var speed_term: float = pow(sig_ratio * (ev / vt_eff), drf_exp)
	return minf(1.0, minf(sig_ratio, speed_term))

static func lock_time_s(scan_resolution: float, target_signature: float) -> float:
	var scan: float = maxf(scan_resolution, 1.0)
	var sig: float = maxf(target_signature, 1.0)
	var k: float = TypedVariant.as_float(DataStore.combat.get("lock_time_constant", 40000.0), 40000.0)
	return k / (scan * sig)

static func missile_speed_cells_per_s(firer: Node = null) -> float:
	## After launch missiles chase at constant cells/s (independent of target motion).
	if firer != null and is_instance_valid(firer):
		if TypedVariant.as_bool(firer.get("is_unmanned")) and str(firer.get("unmanned_kind")) == "fighter":
			return TypedVariant.as_float(DataStore.combat.get("fighter_missile_speed_cells_per_s", 999.0), 999.0)
	return TypedVariant.as_float(DataStore.combat.get("missile_speed_cells_per_s", 1.5), 1.5)


static func missile_impact_delay_s(distance_cells: float) -> float:
	## Legacy estimate only (FX/docs); live missiles use missile_speed_cells_per_s chase.
	var spd: float = maxf(TypedVariant.as_float(DataStore.combat.get("missile_speed_cells_per_s", 1.5), 1.5), 0.001)
	return ceilf(maxf(distance_cells, 0.0)) / spd
