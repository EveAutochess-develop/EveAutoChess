extends RefCounted
class_name CombatFormulas
## EVE-like turret / missile / lock formulas — see eveautochess-design/docs/COMBAT.md

static func world_units_per_cell() -> float:
	return float(DataStore.combat.get("world_units_per_cell", absf(float(DataStore.board.get("hex_offset_x", 3.0)))))

static func grid_distance_cells(a: Node3D, b: Node3D) -> float:
	var wu := world_units_per_cell()
	if wu <= 0.0001:
		return 0.0
	var flat_a := Vector3(a.global_position.x, 0.0, a.global_position.z)
	var flat_b := Vector3(b.global_position.x, 0.0, b.global_position.z)
	return flat_a.distance_to(flat_b) / wu

static func distance_meters(cells: float) -> float:
	return cells * float(DataStore.combat.get("meters_per_cell", 500.0))

static func tracking_distance_meters(cells: float) -> float:
	## Turret angular-velocity path only: 1 cell = 2 km (2000 m) by design.
	return cells * float(DataStore.combat.get("tracking_meters_per_cell", 2000.0))

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
	var d_track := tracking_distance_meters(distance_cells)
	var d_m := distance_meters(distance_cells)
	var v := maxf(target_speed, 0.0)
	var omega := v / maxf(d_track, 1.0)
	var sig_res := maxf(attacker_optimal_sig, 1.0)
	var sig_tgt := maxf(target_signature, 1.0)
	var tracking_term := (omega / attacker_tracking) * (sig_res / sig_tgt)
	var r_opt := cells_to_meters(attacker_optimal_cells)
	var r_fo := maxf(cells_to_meters(attacker_falloff_cells), 1.0)
	var range_term := maxf(0.0, d_m - r_opt) / r_fo
	var exponent := tracking_term * tracking_term + range_term * range_term
	var p := pow(0.5, exponent)
	var lo := float(DataStore.combat.get("hit_chance_min", 0.01))
	var hi := float(DataStore.combat.get("hit_chance_max", 0.99))
	return clampf(p, lo, hi)

static func missile_damage_factor(
	target_signature: float,
	target_speed: float,
	explosion_radius: float,
	explosion_velocity: float,
	drf: float,
	drs: float
) -> float:
	var er := maxf(explosion_radius, 1.0)
	var ev := maxf(explosion_velocity, 1.0)
	var sig := maxf(target_signature, 1.0)
	var vt := maxf(target_speed, 0.0)
	var sig_term := pow(sig / er, drf)
	var vel_term := pow(ev / (ev + vt), drf * drs)
	return minf(1.0, sig_term * vel_term)

static func lock_time_s(scan_resolution: float, target_signature: float) -> float:
	var scan := maxf(scan_resolution, 1.0)
	var sig := maxf(target_signature, 1.0)
	var k := float(DataStore.combat.get("lock_time_constant", 40000.0))
	return k / (scan * sig)

static func missile_impact_delay_s(distance_cells: float) -> float:
	var per_cell := float(DataStore.combat.get("missile_delay_per_cell_s", 1.5))
	return ceilf(maxf(distance_cells, 0.0)) * per_cell
