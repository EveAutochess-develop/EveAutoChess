extends Node3D
class_name ShipUnit

const TEAM_PLAYER: int = 0
const TEAM_AI: int = 1
var ship_id: int = 0
var star: int = 1
var team_id: int = 0
var slot_type: String = "hangar"  # hangar | field
var grid_x: int = 0
var grid_z: int = 0
## Cross-peer stable id for authority snapshots (SEMI_ASYNC §3.2a). Empty until assigned.
var net_uid: String = ""
var is_destroyed: bool = false
var is_logistic: bool = false
var is_mining_ship: bool = false
## Salvage freighter: player-team objective. It never locks/moves/fires.
## Sleepers target it by normal enemy rules; it is not a field combatant count
## (FREIGHTER_AND_TITAN §1.2.1). Do not skip it in everyone else's lock search.
var is_protect_target: bool = false
var is_unmanned: bool = false
var unmanned_kind: String = ""
var drone_bandwidth: float = 0.0
var drone_bay_slots: int = 0  # 发射管 / active drone quota
var _plugin_modules: Array = []
## Function bucket fit — max 3 incl. cyno: `{id, def}` (EQUIPMENT §2).
var _function_fit: Array = []
## Parallel to fit slots — from hull `function_slots.slots[].locked` (MOD_PROTOCOL P1).
var _function_slot_locked: Array = []
## Temp combat fetters from grant_fetter (MOD_PROTOCOL P8).
var _runtime_fetter_ids: Array = []
var _runtime_fetter_until: Dictionary = {}
## Blink burst (MOD_PROTOCOL P7) — multiplies combat_move_speed until sim time.
var _blink_speed_mul: float = 1.0
var _blink_until_time: float = -1.0
## Mixed lance channel — suppresses normal weapons while Prep/Fire/End.
var lance_suppress_weapons: bool = false
var _heal_received_mul: float = 1.0
var _heal_received_mul_until: float = -1.0


func set_lance_suppress(v: bool) -> void:
	lance_suppress_weapons = v


func stamp_hangar_home() -> void:
	if slot_type != "hangar":
		return
	hangar_home_x = grid_x
	hangar_home_z = grid_z


func is_lance_suppressing() -> bool:
	## Prefer fit+phase gate (CAPITAL §4.1); flag is diagnostic mirror only.
	return MixedLance.weapons_suppressed(self)


@warning_ignore("unused_private_class_variable")
var _function_target: Variant = null
@warning_ignore("unused_private_class_variable")
var _function_runtime: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _implant_state: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _function_damage_mul: float = 1.0
var _combat_sim_time: float = 0.0
@warning_ignore("unused_private_class_variable")
var _drone_buff_stats: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _fit_passive_resist_add: Dictionary = {}
var mother_ship_id: int = 0  # instance id of carrier when combat_drone
## Fighter squadron id under a carrier (−1 = none).
var fighter_squadron_id: int = -1
## Carrier: remaining squadrons that can still be launched this battle (−1 = uninit).
var fighter_squadron_pool_left: int = -1
var fighter_next_squadron_id: int = 0
## Capital / cyno runtime flags (from ship JSON).
var requires_cyno_entry: bool = false
var deploy_enemy_half_only: bool = false
var allow_enemy_cell_overlap: bool = false
var immobile_in_combat: bool = false
var unlimited_weapon_range: bool = false
var field_side_team: int = -1  ## which half's world coords; -1 = team_id
## Hangar cell to restore after cyno warp (CAPITAL §6.1 / BOARD 原格). -1 = unset.
var hangar_home_x: int = -1
var hangar_home_z: int = 0
var cyno_channel_ends_at: float = -1.0
var cyno_completed: bool = false
## True while CapitalJumpFx is descending the hull onto the field.
var capital_jumping: bool = false
var capital_role: String = ""
## Visual-only TQ siege / industrial morph (`siege` | `industrial`); empty = none.
var hull_morph: String = ""
var hull_morph_duration_s: float = 10.0
## If set (e.g. `mining_command`), morph only when that team fetter is active and this hull is a beneficiary.
var hull_morph_requires_fetter: String = ""
var hull_morph_playing: bool = false
var hull_morphed: bool = false
## True while capital is micro-sliding apart before siege/industrial unfold.
var hull_morph_unstacking: bool = false

var shield_hp: float = 0.0
var armor_hp: float = 0.0
var structure_hp: float = 0.0
var max_shield: float = 0.0
var max_armor: float = 0.0
var max_structure: float = 0.0
## Baseline max HP from star JSON — fetter %/flat bonuses reapply from these (never stack).
var base_max_shield: float = 0.0
var base_max_armor: float = 0.0
var base_max_structure: float = 0.0
## Pristine base caps at last reload_stats (capital max-loss UI black segment; CAPITAL_AND_CYNO §3.1).
var pristine_base_max_shield: float = 0.0
var pristine_base_max_armor: float = 0.0
var pristine_base_max_structure: float = 0.0
var attack_range: float = 1.0
var damage_emp: float = 0.0
var damage_thermal: float = 0.0
var damage_kinetic: float = 0.0
var damage_explosive: float = 0.0
var repair_shield: float = 0.0
var repair_armor: float = 0.0
var repair_structure: float = 0.0
var shield_resist_emp: float = 0.0
var armor_resist_emp: float = 0.0
var structure_resist_emp: float = 0.0
var attack_duration: float = 1.0
## Baseline cycle after JSON+cap; fetter AttackSpeed reapplies from this (never stack-divide).
var base_attack_duration: float = 1.0
var last_attack_time: float = -999.0
var damage_pct_bonus: float = 0.0
## Invisible star DPH multiplier buff (SHIP_STATS_V2 §2.5). ★k → k for kit-derived hulls;
## stays 1.0 when stars[] already baked star damage (unmanned / unresolved capital kits).
var star_dph_mul: float = 1.0
var fetter_repair_mul: float = 1.0
var fetter_speed_mul: float = 1.0
## Cap warfare / ewar function-module effect muls (FETTERS blood · titan EwarCapWarfare).
var fetter_cap_warfare_mul: float = 1.0
var fetter_ewar_mul: float = 1.0
## Baseline scan for SensorStrength SelfFetter reapply (SoE).
var base_scan_resolution: float = 400.0
var _base_shield_resist_emp: float = 0.0
var _base_armor_resist_emp: float = 0.0
var _base_structure_resist_emp: float = 0.0
var _shield_resist: Dictionary = {}
var _armor_resist: Dictionary = {}
var _structure_resist: Dictionary = {}
## Unmodified star resists — fetter ShieldResist/ArmorResist reapply from these (never stack).
var _base_shield_resist: Dictionary = {}
var _base_armor_resist: Dictionary = {}
var _base_structure_resist: Dictionary = {}

# V2 base stats (ship JSON + star scaling where noted)
var race: String = "amarr"
var signature_radius: float = 40.0
var scan_resolution: float = 400.0
var base_speed: float = 300.0
## EVE inertia: τ = agility × mass / 1e6 (COMBAT §3.1). `agility` = inertia modifier.
var base_mass: float = 1000000.0
var base_agility: float = 1.0
## Current combat velocity (world units / s, XZ). Accelerates toward desired with τ.
var move_velocity_wu: Vector3 = Vector3.ZERO
var tracking: float = 0.0
var optimal_cells: float = 0.0
var falloff_cells: float = 0.0
var optimal_sig_radius: float = 40.0
var explosion_radius: float = 0.0
var explosion_velocity: float = 0.0
var missile_drf: float = 0.0
var missile_drs: float = 5.5
var cap_capacity: float = 0.0
var cap_current: float = 0.0
var cap_recharge_s: float = 1.0
var cap_cost_per_cycle: float = -1.0

# Combat runtime
var lock_target_id: int = 0
var lock_timer: float = 0.0
var lock_duration_s: float = 0.0
## Lead lock: the runner-up target is tracked alongside the one being shot, so a
## retarget that its lead lock already finished switches fire instantly (COMBAT §13.1).
var pre_lock_target_id: int = 0
var pre_lock_timer: float = 0.0
var pre_lock_duration_s: float = 0.0

## Visual soft-follow: logic `global_position` may jump on fixed ticks; the mesh eases
## toward it and is allowed to lag (COMBAT §3.2). Combat / targeting always use the node root.
var _visual_world: Vector3 = Vector3.ZERO
var _visual_yaw: float = 0.0
var _visual_follow_on: bool = false
var _model_rest_local: Vector3 = Vector3.ZERO
var retreat_until_time: float = -1.0
var no_target_acc: float = 0.0
var _stat_modifiers: Array = []

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _model_root: Node3D
## Mesh-local triangle soup for pick (AABB is only broadphase).
var _pick_tri_mi: Array[MeshInstance3D] = []
var _pick_tri_local: Array[PackedVector3Array] = []
var _health_bar: Node3D  # ShipHealthBar (avoid class_name cycle with ShipUnit)
var _tactical_stem: Node3D
## Bow muzzle in ShipUnit local space (after model normalize). Forward = −Z.
var _muzzle_local: Vector3 = Vector3(0.0, 0.4, -0.9)
## All turret hardpoints in ShipUnit local; `get_muzzle_global` cycles them.
var _muzzle_locals: Array[Vector3] = []
var _muzzle_fire_i: int = 0
## Primary engine nozzle in ShipUnit local (trail emit). Aft = +Z when bow = −Z.
var _engine_local: Vector3 = Vector3(0.0, 0.12, 0.55)
## Optional multi-nozzle locals (same space); empty → use `_engine_local` only.
var _engine_locals: Array[Vector3] = []
## Per-nozzle outline in ship-local from engine_boosters.json (SOF radius → circle).
var _engine_outlines: Array = []
## Normalized display longest edge (world units) after scale curve — for load precision.
var _model_display_size: float = -1.0
var _applied_size_compensate: float = -1.0
## Combat aim (Variant so null clear is valid).
var combat_target: Variant = null
## Combat-entry hull glow remaining (sim seconds); <0 = off.
var _combat_glow_left_s: float = -1.0
var _prepare_radar_flash_tween: Tween = null

const _HEALTH_BAR_SCRIPT: GDScript = preload("res://scripts/ship/ship_health_bar.gd")
const _ECHOES_SURFACE_SHADER: Shader = preload("res://shaders/echoes_spaceobject.gdshader")
const _UNITY_SHIP_SHADER: Shader = preload("res://shaders/unity_standard_ship.gdshader")
## Combat entry glow duration in **sim** seconds (scales with 倍速; not FPS / time_scale).
const COMBAT_GLOW_S: float = 10.0
const _HULL_MORPH_FX: GDScript = preload("res://scripts/combat/hull_morph_fx.gd")
func setup(p_ship_id: int, p_star: int, p_team: int) -> void:
	ship_id = p_ship_id
	star = p_star
	team_id = p_team
	## Race must be known before mesh tint (otherwise all hulls look Amarr gold).
	var ship_data: Dictionary = DataStore.get_ship(ship_id)
	race = str(ship_data.get("race", "amarr")).to_lower()
	var fs: Dictionary = TypedVariant.as_dict(ship_data.get("function_slots", {}))
	_load_function_fit_from_slots(fs)
	## Stats first so is_unmanned / drone flags are known before mesh/bar.
	reload_stats()
	var sd: Dictionary = DataStore.get_ship(ship_id)
	requires_cyno_entry = TypedVariant.as_bool(sd.get("requires_cyno_entry", false))
	deploy_enemy_half_only = TypedVariant.as_bool(sd.get("deploy_enemy_half_only", false))
	allow_enemy_cell_overlap = TypedVariant.as_bool(sd.get("allow_enemy_cell_overlap", false))
	immobile_in_combat = TypedVariant.as_bool(sd.get("immobile_in_combat", false))
	unlimited_weapon_range = TypedVariant.as_bool(sd.get("unlimited_weapon_range", false))
	capital_role = str(sd.get("capital_role", ""))
	hull_morph = str(sd.get("hull_morph", ""))
	hull_morph_duration_s = TypedVariant.as_float(sd.get("hull_morph_duration_s", 10.0))
	hull_morph_requires_fetter = str(sd.get("hull_morph_requires_fetter", ""))
	hull_morph_playing = false
	hull_morphed = false
	hull_morph_unstacking = false
	if field_side_team < 0:
		field_side_team = team_id
	_ensure_mesh()
	_ensure_health_bar()
	sync_tactical_stem()
	add_to_group("ship_units")
	var yaw: float = TypedVariant.as_float(DataStore.visual.get("player_yaw_deg" if team_id == TEAM_PLAYER else "ai_yaw_deg", 0.0))
	rotation_degrees = Vector3(0, yaw, 0)
	## Soft-follow runs only while Battle has armed it (COMBAT §3.2).
	set_process(false)

## Yaw so local −Z faces flat XZ direction (Godot forward).
func face_dir_xz(dir: Vector3) -> void:
	if (immobile_in_combat and not hull_morph_unstacking) or has_cyno_module():
		return
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	rotation.y = atan2(-flat.x, -flat.z)


## Y-unlocked / unmanned: full 3D facing; near-vertical falls back to yaw-only.
func face_dir_3d(dir: Vector3) -> void:
	if (immobile_in_combat and not hull_morph_unstacking) or has_cyno_module():
		return
	if not y_axis_unlocked():
		face_dir_xz(dir)
		return
	if dir.length_squared() < 0.0001:
		return
	var n: Vector3 = dir.normalized()
	if absf(n.dot(Vector3.UP)) > 0.98:
		face_dir_xz(dir)
		return
	look_at(global_position + n, Vector3.UP)


func y_axis_unlocked() -> bool:
	if is_unmanned:
		return true
	var ship_doc: Dictionary = DataStore.get_ship(ship_id)
	var sg: String = str(ship_doc.get("ship_group", "")).to_lower()
	return sg == "frigate" or sg == "destroyer"


func off_deck_plane() -> bool:
	## Deck plane matches BoardController.DECK_Y (0.2); local const avoids class cycle.
	return absf(global_position.y - 0.2) > 0.05


## AABB aft-center nozzle (COMBAT §14D single-strand drones).
func rear_center_engine_local() -> Vector3:
	if _model_root == null or not is_instance_valid(_model_root):
		return _engine_local
	var aabb: AABB = _aabb_in_ship_space(_model_root)
	if aabb.size.length_squared() < 1e-8:
		return _engine_local
	var mid_y: float = maxf(aabb.get_center().y, aabb.size.y * 0.25)
	var z_aft: float = aabb.position.z + aabb.size.z
	return Vector3(0.0, mid_y, z_aft)


func model_root() -> Node3D:
	return _model_root


## World-space center of the visible hull (AABB), else logic origin. Used by tactical stem.
func model_center_world() -> Vector3:
	if _model_root != null and is_instance_valid(_model_root):
		var aabb: AABB = _aabb_in_ship_space(_model_root)
		if aabb.size.length_squared() > 1e-8:
			return visual_to_global(aabb.get_center())
	return global_position


## Tactical foot disc center on board XZ (UI_AND_SHELL §2.7).
func tactical_foot_world_xz() -> Vector2:
	var c: Vector3 = model_center_world()
	return Vector2(c.x, c.z)


## Move hull so the foot disc center sits on target XZ while lifted for drag preview.
func align_root_to_tactical_foot_xz(target_xz: Vector2, lift_y: float) -> void:
	var foot: Vector2 = tactical_foot_world_xz()
	global_position.x += target_xz.x - foot.x
	global_position.z += target_xz.y - foot.y
	global_position.y = lift_y
	sync_tactical_stem()


## Ship-local hardpoints were baked while the mesh sat at `_model_rest_local`.
## Map them through the *current* mesh pose so FX / trails stay glued when soft-follow lags.
func visual_to_global(ship_local: Vector3) -> Vector3:
	if _model_root == null:
		return to_global(ship_local)
	var rest_xf: Transform3D = Transform3D(_model_root.transform.basis, _model_rest_local)
	var model_local: Vector3 = rest_xf.affine_inverse() * ship_local
	return _model_root.to_global(model_local)


func visual_origin_world() -> Vector3:
	return visual_to_global(Vector3.ZERO)


func arm_visual_follow() -> void:
	## Battle only: mesh soft-chases the logic root; prepare / drag stay glued.
	if _model_root != null:
		_model_rest_local = _model_root.position
	_visual_world = global_position
	_visual_yaw = rotation.y
	_visual_follow_on = true
	set_process(true)


func disarm_visual_follow() -> void:
	_visual_follow_on = false
	set_process(false)
	_snap_visual_to_logic()


func _snap_visual_to_logic() -> void:
	_visual_world = global_position
	_visual_yaw = rotation.y
	if _model_root != null:
		_model_root.position = _model_rest_local
		_apply_visual_yaw_to_model()


func _model_rest_yaw() -> float:
	if _model_root != null and _model_root.has_meta("rest_rotation"):
		var rr: Variant = _model_root.get_meta("rest_rotation")
		if rr is Vector3:
			@warning_ignore("unsafe_cast")
			return (rr as Vector3).y
	return 0.0


func _apply_visual_yaw_to_model() -> void:
	if _model_root == null:
		return
	## Parent logic yaw is instant; child local yaw keeps world visual yaw lagging.
	_model_root.rotation.y = _model_rest_yaw() + (_visual_yaw - rotation.y)


func _process(delta: float) -> void:
	if not _visual_follow_on or _model_root == null:
		return
	var t0: int = Time.get_ticks_usec()
	## Outside combat someone may teleport the root (cyno land / board move): re-glue
	## instead of dragging the mesh across the map.
	var err: Vector3 = global_position - _visual_world
	var snap_wu: float = 6.0
	var yaw_snap_deg: float = 120.0
	var rate: float = 10.0
	var max_wu_s: float = 12.0
	var yaw_rate_deg: float = 180.0
	if DataStore != null and DataStore.visual:
		snap_wu = TypedVariant.as_float(DataStore.visual.get("hull_visual_snap_wu", 6.0))
		yaw_snap_deg = TypedVariant.as_float(DataStore.visual.get("hull_visual_yaw_snap_deg", 120.0))
		rate = TypedVariant.as_float(DataStore.visual.get("hull_visual_follow_rate", 10.0))
		max_wu_s = TypedVariant.as_float(DataStore.visual.get("hull_visual_follow_max_wu_s", 12.0))
		yaw_rate_deg = TypedVariant.as_float(DataStore.visual.get("hull_visual_yaw_rate_deg", 180.0))
	var yaw_err: float = angle_difference(_visual_yaw, rotation.y)
	if err.length_squared() > snap_wu * snap_wu or absf(yaw_err) > deg_to_rad(yaw_snap_deg):
		_snap_visual_to_logic()
		sync_tactical_stem()
		SessionDiagnostics.add_usec(&"ship", Time.get_ticks_usec() - t0)
		return
	rate = maxf(0.5, rate)
	var a: float = 1.0 - exp(-rate * delta)
	var desired: Vector3 = _visual_world.lerp(global_position, a)
	var step: Vector3 = desired - _visual_world
	if max_wu_s > 0.0:
		var max_step: float = max_wu_s * delta
		if step.length() > max_step:
			step = step.normalized() * max_step
		_visual_world += step
	else:
		_visual_world = desired
	## Keep rest local offset (centering); only the world translation soft-follows.
	_model_root.global_position = _visual_world + (global_transform.basis * _model_rest_local)
	var max_yaw: float = deg_to_rad(maxf(1.0, yaw_rate_deg)) * delta
	_visual_yaw += clampf(yaw_err, -max_yaw, max_yaw)
	_apply_visual_yaw_to_model()
	## Stem uses model center; refresh after soft-follow pose this frame.
	sync_tactical_stem()
	SessionDiagnostics.add_usec(&"ship", Time.get_ticks_usec() - t0)


## Pure VFX: TQ StartSiege / Normal2Siege — real AnimationPlayer if present, else proxy.
func can_begin_hull_morph() -> bool:
	if hull_morph.is_empty() or hull_morphed or hull_morph_playing:
		return false
	if slot_type != "field" or is_destroyed:
		return false
	if not hull_morph_requires_fetter.is_empty() and not _hull_morph_fetter_satisfied():
		return false
	return true


func begin_hull_morph_if_needed() -> void:
	if not can_begin_hull_morph():
		return
	var dur: float = hull_morph_duration_s
	if DataStore != null and DataStore.combat:
		dur = TypedVariant.as_float(DataStore.combat.get("hull_morph_duration_s", dur))
		if hull_morph_duration_s > 0.0:
			dur = hull_morph_duration_s
	var world: Node = get_parent()
	if world == null:
		world = self
	var fx_v: Variant = _HULL_MORPH_FX.new()
	if not (fx_v is Node):
		return
	@warning_ignore("unsafe_cast")
	var fx: Node = fx_v as Node
	fx.name = "HullMorphFx_%d" % get_instance_id()
	world.add_child(fx)
	fx.call("play", self, hull_morph, dur)


## mining_command: Field Porpoise active → other mining sources receive +20% (MINING §3).
func _hull_morph_fetter_satisfied() -> bool:
	var need: String = hull_morph_requires_fetter
	if need.is_empty():
		return true
	if need != "mining_command":
		return false
	## Beneficiaries only — Porpoise itself does not "eat" the bonus.
	var self_data: Dictionary = DataStore.get_ship(ship_id) if DataStore else {}
	var self_fids: Array = TypedVariant.as_array(self_data.get("fetter_ids", []))
	if ship_id == 136 or ("mining_command" in self_fids):
		return false
	var board_v: Variant = _find_board_controller()
	if not (board_v is BoardController):
		return false
	@warning_ignore("unsafe_cast")
	var board: BoardController = board_v as BoardController
	for s: Variant in board.field_ships(team_id):
		if s == null or not (s is ShipUnit):
			continue
		@warning_ignore("unsafe_cast")
		var su: ShipUnit = s as ShipUnit
		if su.is_destroyed or su.is_unmanned:
			continue
		var sd: Dictionary = DataStore.get_ship(su.ship_id)
		if su.ship_id == 136 or ("mining_command" in TypedVariant.as_array(sd.get("fetter_ids", []))):
			return true
	return false


func _find_board_controller() -> Node:
	var tree: SceneTree = get_tree()
	if tree:
		var root: Node = tree.get_first_node_in_group("match_root")
		if root != null and root.get("board") != null:
			var bv: Variant = root.get("board")
			if bv is Node:
				@warning_ignore("unsafe_cast")
				return bv as Node
		var by_group: Node = tree.get_first_node_in_group("board_controller")
		if by_group != null:
			return by_group
	var n: Node = get_parent()
	while n:
		if n.has_method("field_ships") and n.has_method("recalculate_fetters"):
			return n
		n = n.get_parent()
	return null


func apply_prepare_radar_flash(
		sweep_mask: float = 1.0,
		beam_sample: Color = Color(1.0, 1.0, 1.0, 1.0),
		beam_emission: Color = Color(0.12, 0.78, 0.55),
		beam_peak_alpha: float = 0.28
) -> void:
	if _model_root == null or _model_root.has_meta("no_model_pick_sphere"):
		return
	if sweep_mask <= 0.001:
		clear_prepare_radar_flash()
		return
	var ship_tint: Color = _prepare_radar_overlay_color()
	## Match sweep fan: emission × vertex albedo; blend ship set color toward beam by sample.
	var line_strength: float = sweep_mask
	if beam_peak_alpha > 1e-5:
		line_strength = clampf(beam_sample.a / beam_peak_alpha, 0.0, 1.0)
	var beam_visible: Color = beam_emission.lightened(0.42)
	var tint: Color = ship_tint.lerp(beam_visible, line_strength * 0.62)
	if _prepare_radar_flash_tween != null and is_instance_valid(_prepare_radar_flash_tween):
		_prepare_radar_flash_tween.kill()
		_prepare_radar_flash_tween = null
	_apply_prepare_radar_emission(line_strength, tint)


func clear_prepare_radar_flash() -> void:
	if _prepare_radar_flash_tween != null and is_instance_valid(_prepare_radar_flash_tween):
		_prepare_radar_flash_tween.kill()
		_prepare_radar_flash_tween = null
	_apply_prepare_radar_emission(0.0, Color.WHITE)
	_reset_shader_combat_emission_color()
	restore_emission_after_hull_morph()


func _reset_shader_combat_emission_color() -> void:
	if _model_root == null:
		return
	for mi: MeshInstance3D in _find_meshes(_model_root):
		if _is_pick_proxy_mesh(mi):
			continue
		if mi.material_override is ShaderMaterial:
			var smat: ShaderMaterial = mi.material_override as ShaderMaterial
			smat.set_shader_parameter("combat_emission_color", Vector3.ONE)


func _prepare_radar_overlay_set_key() -> String:
	if is_unmanned:
		return ""
	var sd: Dictionary = DataStore.get_ship(ship_id)
	if sd.is_empty():
		return ""
	var vis: Dictionary = TypedVariant.as_dict(sd.get("_visual", {}))
	var profile: String = str(vis.get("tonnage_overlay_profile", "")).strip_edges()
	var sg: String = str(sd.get("ship_group", "")).to_lower()
	if profile == "relation":
		if is_protect_target or sg == "freighter":
			return "relation_friendly"
		return "fleet" if team_id == TEAM_PLAYER else "enemy"
	if is_protect_target or sg == "freighter":
		return "friendly"
	return "fleet" if team_id == TEAM_PLAYER else "enemy"


func _prepare_radar_overlay_color() -> Color:
	var key: String = _prepare_radar_overlay_set_key()
	var fb: Color = Color(0.35, 0.55, 0.95) if team_id == TEAM_PLAYER else Color(0.92, 0.28, 0.22)
	var ship: Dictionary = DataStore.get_ship(ship_id)
	var ov: Dictionary = TypedVariant.as_dict(ship.get("prepare_radar_override", {}))
	if ov.has("color"):
		return ModPrepareRadarResolve.ship_flash_color(ov, "", fb)
	if key != "":
		var bg: Texture2D = UiAssets.tonnage_overlay_set(key).get("bg")
		if bg != null:
			var tex_c: Color = _average_texture_color(bg)
			if tex_c.a > 0.05 and tex_c != Color.WHITE:
				return ModPrepareRadarResolve.ship_flash_color(ov, key, tex_c)
	var visual: Dictionary = DataStore.visual.duplicate(true)
	var mm: ModManager = ModManager.get_or_null()
	if mm != null and not mm.merged_prepare_radar_override.is_empty():
		visual["prepare_radar_flash_colors"] = ModPrepareRadarResolve.merge_flash_colors(
			visual, mm.merged_prepare_radar_override
		)
	var table_c: Color = ModPrepareRadarResolve.color_from_visual_set(visual, key, fb)
	return ModPrepareRadarResolve.ship_flash_color(ov, key, table_c)


func _average_texture_color(tex: Texture2D) -> Color:
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return Color.WHITE
	var r_sum: float = 0.0
	var g_sum: float = 0.0
	var b_sum: float = 0.0
	var n: int = 0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.05:
				continue
			r_sum += c.r
			g_sum += c.g
			b_sum += c.b
			n += 1
	if n <= 0:
		return Color.WHITE
	return Color(r_sum / float(n), g_sum / float(n), b_sum / float(n), 1.0)


func _apply_prepare_radar_emission(strength: float, tint: Color) -> void:
	if _model_root == null:
		return
	for mi: MeshInstance3D in _find_meshes(_model_root):
		if _is_pick_proxy_mesh(mi):
			continue
		_set_mesh_emission(mi, strength * 0.85, tint, true)


func apply_hull_morph_emission(strength: float, kind: String = "siege") -> void:
	if _model_root == null:
		return
	## Pick-proxy only: never paint emission onto the invisible sphere.
	if _model_root.has_meta("no_model_pick_sphere"):
		return
	var tint: Color = Color(1.0, 0.55, 0.25) if kind != "industrial" else Color(0.4, 1.0, 0.55)
	for mi: MeshInstance3D in _find_meshes(_model_root):
		if _is_pick_proxy_mesh(mi):
			continue
		_set_mesh_emission(mi, strength, tint, true)


## After morph FX ends: restore combat-entry glow if still active, else clear white film.
func restore_emission_after_hull_morph() -> void:
	_apply_combat_tint_visual(_combat_glow_left_s > 0.0)


func _is_pick_proxy_mesh(mi: MeshInstance3D) -> bool:
	return mi != null and mi.has_meta("no_model_pick_sphere")


func _set_mesh_emission(mi: MeshInstance3D, strength: float, tint: Color, morph_tint: bool) -> void:
	if _is_pick_proxy_mesh(mi):
		return
	var mats: Array = []
	if mi.material_override != null:
		mats.append(mi.material_override)
	if mi.mesh:
		for si: int in range(mi.mesh.get_surface_count()):
			var sov: Material = mi.get_surface_override_material(si)
			if sov != null and mats.find(sov) < 0:
				mats.append(sov)
	for mat: Variant in mats:
		if mat is ShaderMaterial:
			@warning_ignore("unsafe_cast")
			var smat: ShaderMaterial = mat as ShaderMaterial
			smat.set_shader_parameter("combat_emission_strength", strength)
			if morph_tint:
				smat.set_shader_parameter(
					"combat_emission_color", Vector3(tint.r, tint.g, tint.b)
				)
		elif mat is StandardMaterial3D:
			@warning_ignore("unsafe_cast")
			var std: StandardMaterial3D = mat as StandardMaterial3D
			std.emission_enabled = strength > 0.001
			std.emission = tint if morph_tint else Color.WHITE
			std.emission_energy_multiplier = strength

func restore_team_yaw() -> void:
	var yaw: float = TypedVariant.as_float(DataStore.visual.get("player_yaw_deg" if team_id == TEAM_PLAYER else "ai_yaw_deg", 0.0))
	rotation_degrees = Vector3(0, yaw, 0)

func _ensure_mesh() -> void:
	if _model_root or _mesh:
		return
	## Berth titans keep GLB even in no-model (UI_AND_SHELL: 泰坦停泊仍加载).
	var berth_decor: bool = get_parent() is TitanBerth
	## Performance mode: skip GLB; transparent pick sphere so BOARD raycast still works.
	if (not berth_decor) and PlayerSettings.get_or_null() != null and PlayerSettings.get_or_null().no_model_perf_mode:
		_attach_no_model_pick_proxy()
		return
	var path: String = _mesh_path_safe()
	if path != "" and path.ends_with(".obj") and FileAccess.file_exists(path):
		var obj_mesh: ArrayMesh = ModObjLoader.load_obj(path)
		if obj_mesh != null:
			_model_root = Node3D.new()
			_model_root.name = "ModObjHull"
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = obj_mesh
			_model_root.add_child(mi)
			add_child(_model_root)
			_apply_model_orientation(_model_root)
			_normalize_model_scale(_model_root)
			MobileModelLoad.apply_tree(_model_root, _model_display_size)
			_tint_model(_model_root)
			_attach_siege_addon_if_any()
			_cache_model_rest_pose()
			return
	if path != "" and ResourceLoader.exists(path):
		var packed: Resource = load(path)
		if packed is PackedScene:
			_model_root = (packed as PackedScene).instantiate() as Node3D
			add_child(_model_root)
			_apply_model_orientation(_model_root)
			_normalize_model_scale(_model_root)
			## Mesh mutation (decimate/compress) before tint — never rebuild after materials applied.
			MobileModelLoad.apply_tree(_model_root, _model_display_size)
			_tint_model(_model_root)
			_attach_siege_addon_if_any()
			_cache_model_rest_pose()
			return
	## Missing model: transparent pick sphere (BOARD_AND_INPUT §4 · MOD_PROTOCOL).
	_attach_no_model_pick_proxy()
	_muzzle_local = Vector3(0.0, 0.3, -0.9)
	var ship: Dictionary = DataStore.get_ship(ship_id) if DataStore else {}
	if str(ship.get("_mod_package", "")).strip_edges() != "":
		var label: String = str(ship.get("name", ""))
		if label.strip_edges() == "":
			label = str(ship_id)
		SessionDiagnostics.log("ship.model_missing", "%s 模型美术素材加载失败" % label)


## Near-clear sphere under `_model_root` for pick / soft-follow when hull mesh is absent.
func _attach_no_model_pick_proxy() -> void:
	_model_root = Node3D.new()
	_model_root.name = "NoModelPlaceholder"
	_model_root.set_meta("no_model_pick_sphere", true)
	add_child(_model_root)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "PickSphere"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mi.mesh = sphere
	mi.set_meta("no_model_pick_sphere", true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	## Fully invisible; triangles remain for BOARD ray pick (BOARD_AND_INPUT §4).
	## Combat tint / morph must never overwrite this (set_combat_tint skips meta).
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.emission_enabled = false
	mi.material_override = mat
	_model_root.add_child(mi)
	_normalize_model_scale(_model_root)
	_cache_model_rest_pose()


## UI_AND_SHELL no-model toggle: drop or rebuild hull mesh on an already-spawned unit.
func refresh_visual_for_no_model_mode() -> void:
	## Titan berth decor never strips/rebuilds for no-model (keeps TitanHpBar stern anchor).
	if get_parent() is TitanBerth:
		return
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.queue_free()
	_model_root = null
	_mesh = null
	_pick_tri_mi.clear()
	_pick_tri_local.clear()
	_ensure_mesh()
	rebuild_health_bar()
	sync_tactical_stem()


func _cache_model_rest_pose() -> void:
	if _model_root == null:
		return
	_model_root.set_meta("rest_rotation", _model_root.rotation)
	_model_root.set_meta("rest_scale", _model_root.scale)
	sync_tactical_stem()


func restore_model_rest_pose() -> void:
	if _model_root == null:
		return
	if _model_root.has_meta("rest_rotation"):
		var rr: Variant = _model_root.get_meta("rest_rotation")
		if rr is Vector3:
			@warning_ignore("unsafe_cast")
			_model_root.rotation = rr as Vector3
	if _model_root.has_meta("rest_scale"):
		var rs: Variant = _model_root.get_meta("rest_scale")
		if rs is Vector3:
			@warning_ignore("unsafe_cast")
			_model_root.scale = rs as Vector3
	var addon_v: Variant = _model_root.get_node_or_null("SiegeAddon")
	var addon: Node3D = null
	if addon_v is Node3D:
		@warning_ignore("unsafe_cast")
		addon = addon_v as Node3D
	if addon:
		addon.visible = false


func _attach_siege_addon_if_any() -> void:
	## Optional static/anim siege flap pack: assets/models/ships/<key>/siege_addon.glb
	if _model_root == null or DataStore == null:
		return
	if _model_root.get_node_or_null("SiegeAddon") != null:
		return
	var key: String = str(DataStore.get_ship(ship_id).get("model_key", ""))
	if key.is_empty():
		return
	var path: String = "res://assets/models/ships/%s/siege_addon.glb" % key
	if not ResourceLoader.exists(path):
		return
	var packed: Resource = load(path)
	if not (packed is PackedScene):
		return
	var addon: Node3D = (packed as PackedScene).instantiate() as Node3D
	if addon == null:
		return
	addon.name = "SiegeAddon"
	addon.visible = false
	_model_root.add_child(addon)

func _mesh_path_safe() -> String:
	if DataStore != null and DataStore.has_method("ship_mesh_path_resolved"):
		return str(DataStore.ship_mesh_path_resolved(ship_id))
	if DataStore != null and DataStore.has_method("ship_mesh_path"):
		var path: String = str(DataStore.ship_mesh_path(ship_id))
		if path != "" and ResourceLoader.exists(path):
			return path
	var ship: Dictionary = DataStore.get_ship(ship_id) if DataStore else {}
	var mod_glb: String = str(ship.get("_mod_model_glb", ""))
	if mod_glb != "" and FileAccess.file_exists(mod_glb):
		return mod_glb
	var key: String = str(ship.get("model_key", ""))
	if key != "":
		var bundle_mesh: String = "res://assets/models/ships/%s/model.glb" % key
		if ResourceLoader.exists(bundle_mesh):
			return bundle_mesh
	return ""

func refresh_health_bar() -> void:
	if _health_bar:
		_health_bar.call("refresh")


func _ensure_health_bar() -> void:
	if _health_bar != null:
		return
	## Drones: trail-only; skip overlay to avoid floating-bar clutter.
	if is_unmanned:
		return
	## Titans / berth decor: life is TitanHpBar only (MULTIPLAYER_PVP §2.4) — never ShipHealthBar.
	if _suppress_ship_float_health_bar():
		clear_health_bar()
		return
	var hb_v: Variant = _HEALTH_BAR_SCRIPT.new()
	if not (hb_v is Node3D):
		return
	@warning_ignore("unsafe_cast")
	_health_bar = hb_v as Node3D
	_health_bar.name = "HealthBar"
	add_child(_health_bar)
	_health_bar.call("setup", self)


func _suppress_ship_float_health_bar() -> bool:
	## Titans / berth decor: life is TitanHpBar only (MULTIPLAYER_PVP §2.4).
	if DataStore:
		if str(DataStore.get_ship(ship_id).get("ship_group", "")) == "titan":
			return true
	var p: Node = get_parent()
	if p is TitanBerth:
		return true
	return false


func clear_health_bar() -> void:
	if _health_bar != null and is_instance_valid(_health_bar):
		_health_bar.queue_free()
	_health_bar = null
	var hb: Node = get_node_or_null("HealthBar")
	if hb:
		hb.queue_free()


func get_health_bar() -> Node3D:
	return _health_bar if _health_bar != null and is_instance_valid(_health_bar) else null


func flash_tonnage_lock(duration_s: float = 0.45) -> void:
	_ensure_health_bar()
	if _health_bar != null and _health_bar.has_method("flash_lock_brackets"):
		_health_bar.call("flash_lock_brackets", duration_s)


func _exit_tree() -> void:
	_clear_tactical_stem()


func _tactical_stem_world_host() -> Node3D:
	## Sibling under board WorldRoot — avoids parent-scale / visibility quirks on the hull node.
	var p: Node = get_parent()
	if p is Node3D:
		return p as Node3D
	return null


func _ensure_tactical_stem() -> void:
	if _tactical_stem != null and is_instance_valid(_tactical_stem):
		return
	var stem_n: ShipTacticalStem = ShipTacticalStem.new()
	_tactical_stem = stem_n
	_tactical_stem.name = "TacticalStem"
	var host: Node3D = _tactical_stem_world_host()
	if host != null:
		host.add_child(_tactical_stem)
	else:
		add_child(_tactical_stem)
	if _tactical_stem.has_method("setup"):
		_tactical_stem.call("setup", BoardController.DECK_Y)


func _clear_tactical_stem() -> void:
	if _tactical_stem != null and is_instance_valid(_tactical_stem):
		_tactical_stem.queue_free()
	_tactical_stem = null


func sync_tactical_stem() -> void:
	if is_unmanned or is_destroyed:
		_clear_tactical_stem()
		return
	if not is_inside_tree():
		call_deferred("sync_tactical_stem")
		return
	_ensure_tactical_stem()
	if _tactical_stem != null and is_instance_valid(_tactical_stem):
		_tactical_stem.visible = true
		if _tactical_stem.has_method("sync_to_ship"):
			_tactical_stem.call("sync_to_ship", self)


func on_board_slot_changed() -> void:
	rebuild_health_bar()
	sync_tactical_stem()


func rebuild_health_bar() -> void:
	## Recreate badge/bars after external FX accidentally mutated overlay materials.
	clear_health_bar()
	if _suppress_ship_float_health_bar():
		return
	_ensure_health_bar()
	if _health_bar and _health_bar.has_method("refresh"):
		_health_bar.call("refresh")

func _apply_model_orientation(root: Node3D) -> void:
	## Lay hull flat: longest axis → length (local Z), up stays Y when possible.
	var pitch: float = TypedVariant.as_float(DataStore.visual.get("ship_model_pitch_deg", 0.0))
	var model_yaw: float = TypedVariant.as_float(DataStore.visual.get("ship_model_yaw_deg", 180.0))
	var model_roll: float = TypedVariant.as_float(DataStore.visual.get("ship_model_roll_deg", 0.0))
	## Nozzles face astern, so a baked `bow_fit` yaw is ground truth and outranks
	## both the global default and the extent guess below (CONTENT_FORMAT §喷口).
	var fit: Dictionary = _bow_fit()
	if fit.has("model_yaw_deg"):
		var fit_pitch: float = TypedVariant.as_float(fit.get("model_pitch_deg", pitch), pitch)
		var fit_roll: float = TypedVariant.as_float(fit.get("model_roll_deg", model_roll), model_roll)
		root.rotation_degrees = Vector3(
			fit_pitch,
			TypedVariant.as_float(fit["model_yaw_deg"]),
			fit_roll
		)
		if TypedVariant.as_bool(DataStore.visual.get("ship_model_level_keel", true)):
			_level_model_keel(root)
		return
	## Echoes hulls are authored length-on-Z, so content keeps auto-orient off globally.
	## TQ hulls (titans) are length-on-X and must opt back in per ship def.
	var auto_orient: bool = TypedVariant.as_bool(DataStore.visual.get("ship_model_auto_orient", true))
	var def_flag: Variant = DataStore.get_ship(ship_id).get("model_auto_orient", null)
	if def_flag != null:
		auto_orient = TypedVariant.as_bool(def_flag)
	if auto_orient:
		var aabb: AABB = _aabb_mesh_local(root)
		var sx: float = aabb.size.x
		var sy: float = aabb.size.y
		var sz: float = aabb.size.z
		if sy >= sx and sy >= sz:
			## Length along Y (legacy Unity tip) → +90° X lays length onto Z.
			pitch = 90.0
		elif sx >= sy and sx >= sz:
			## Length along X → +90° yaw maps X onto Z; keep configured bow flip.
			pitch = 0.0
			model_yaw = model_yaw + 90.0
		else:
			## Length already on Z (typical Echoes).
			pitch = 0.0
	root.rotation_degrees = Vector3(pitch, model_yaw, model_roll)
	if TypedVariant.as_bool(DataStore.visual.get("ship_model_level_keel", true)):
		_level_model_keel(root)

func _level_model_keel(root: Node3D) -> void:
	## Cancel baked bow/stern pitch so the keel sits level (fixes “nose into floor” look).
	var pts: Array[Vector3] = []
	for mi: MeshInstance3D in _find_meshes(root):
		if mi.mesh == null:
			continue
		var xf: Transform3D = _xform_to_ancestor(root, mi)
		for s: int in range(mi.mesh.get_surface_count()):
			var arr: Array = mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var step: int = maxi(1, int(verts.size() / 400.0))
			var i: int = 0
			while i < verts.size():
				pts.append(xf * verts[i])
				i += step
	if pts.size() < 16:
		return
	var min_z: float = INF
	var max_z: float = -INF
	for p: Vector3 in pts:
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var span: float = max_z - min_z
	if span < 0.001:
		return
	var front_y: float = 0.0
	var back_y: float = 0.0
	var fn: int = 0
	var bn: int = 0
	var thr: float = span * 0.12
	for p: Variant in pts:
		if p.z > max_z - thr:
			front_y += p.y
			fn += 1
		elif p.z < min_z + thr:
			back_y += p.y
			bn += 1
	if fn < 1 or bn < 1:
		return
	front_y /= float(fn)
	back_y /= float(bn)
	## Positive atan ⇒ bow higher than stern; apply opposite pitch about X.
	var corr: float = -rad_to_deg(atan2(front_y - back_y, span))
	corr = clampf(corr, -35.0, 35.0)
	root.rotation_degrees.x += corr

static func _is_sleeper_hull(ship: Dictionary) -> bool:
	if str(ship.get("race", "")).to_lower() == "sleeper":
		return true
	for t: Variant in TypedVariant.as_array(ship.get("tags", [])):
		var ts: String = str(t).to_lower()
		if ts == "sleeper" or ts == "pve_creep":
			return true
	return false


## Shop combat hulls of the four empires in `group` — mean `model_long_axis`.
## Sleepers must render at this size (MULTIPLAYER_MATCH_FLOW §5.1).
static func _racial_tonnage_mean_long_axis(group: String) -> float:
	if group == "" or DataStore == null:
		return 0.0
	var sum: float = 0.0
	var n: int = 0
	for sid: Variant in DataStore.ship_ids():
		var s: Dictionary = DataStore.get_ship(TypedVariant.as_int(sid))
		if str(s.get("ship_group", "")) != group:
			continue
		var race_name: String = str(s.get("race", "")).to_lower()
		if race_name not in ["amarr", "caldari", "gallente", "minmatar"]:
			continue
		if TypedVariant.as_bool(s.get("is_logistic", false)):
			continue
		if s.has("shop_eligible") and not TypedVariant.as_bool(s.get("shop_eligible", true)):
			continue
		if _is_sleeper_hull(s):
			continue
		var ax: float = TypedVariant.as_float(s.get("model_long_axis", 0.0))
		if ax <= 0.0:
			continue
		sum += ax
		n += 1
	return sum / float(n) if n > 0 else 0.0


func _normalize_model_scale(root: Node3D) -> void:
	## Curve-map Echoes dogma long axis (type attr radius / 105) → display size;
	## mesh AABB longest only scales the GLB to that display size (fallback axis source).
	var target: float = TypedVariant.as_float(DataStore.visual.get("ship_target_size", 2.4))
	var ref_l: float = TypedVariant.as_float(DataStore.visual.get("ship_scale_ref_longest", 95.0))
	var power: float = TypedVariant.as_float(DataStore.visual.get("ship_scale_curve_power", 0.5))
	var min_mul: float = TypedVariant.as_float(DataStore.visual.get("ship_scale_min_mul", 0.5))
	var max_mul: float = TypedVariant.as_float(DataStore.visual.get("ship_scale_max_mul", 2.0))
	var aabb: AABB = _aabb_mesh_local(root)
	var mesh_longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if mesh_longest < 0.0001:
		return
	var ship_data: Dictionary = DataStore.get_ship(ship_id)
	var axis: float = TypedVariant.as_float(ship_data.get("model_long_axis", 0.0))
	## Sleepers share the racial same-tonnage mean long axis (MATCH_FLOW §5.1).
	if _is_sleeper_hull(ship_data):
		var mean_axis: float = _racial_tonnage_mean_long_axis(str(ship_data.get("ship_group", "")))
		if mean_axis > 0.0:
			axis = mean_axis
	if axis <= 0.0:
		axis = mesh_longest
	ref_l = maxf(ref_l, 1.0)
	power = clampf(power, 0.05, 1.0)
	var ratio: float = axis / ref_l
	var display: float = target * pow(ratio, power)
	display = clampf(display, target * min_mul, target * max_mul)
	var compensate: float = clampf(
		TypedVariant.as_float(ship_data.get("model_size_compensate", 1.0), 1.0), 0.15, 4.0
	)
	_model_display_size = display * compensate
	var sc: float = display / mesh_longest
	sc *= TypedVariant.as_float(DataStore.visual.get("ship_visual_scale", 1.0))
	if is_unmanned:
		## Fighters = frigate size. Drones are fractions of frigate (heavy 1/2, medium 1/3, light 1/4).
		if unmanned_kind == "fighter":
			sc *= TypedVariant.as_float(DataStore.visual.get("fighter_visual_scale_mul", 1.0))
		else:
			var sg: String = str(DataStore.get_ship(ship_id).get("ship_group", ""))
			if sg == "drone_heavy" or unmanned_kind == "heavy_repair_drone":
				sc *= TypedVariant.as_float(DataStore.visual.get("drone_heavy_visual_scale_mul", 0.5))
			elif sg == "drone_medium":
				sc *= TypedVariant.as_float(DataStore.visual.get("drone_medium_visual_scale_mul", 1.0 / 3.0))
			elif sg == "drone_light" or unmanned_kind.find("repair") >= 0:
				sc *= TypedVariant.as_float(DataStore.visual.get("drone_light_visual_scale_mul", 0.25))
			else:
				sc *= TypedVariant.as_float(DataStore.visual.get("unmanned_visual_scale_mul", 0.25))
	sc *= compensate
	_applied_size_compensate = compensate
	root.scale = Vector3.ONE * sc
	aabb = _aabb_in_ship_space(root)
	var center: Vector3 = aabb.get_center()
	root.position.x -= center.x
	root.position.z -= center.z
	aabb = _aabb_in_ship_space(root)
	root.position.y -= aabb.position.y
	# Turret hardpoints + engine nozzles (ShipUnit local).
	aabb = _aabb_in_ship_space(root)
	_resolve_turret_locals(root, aabb)
	_resolve_engine_local(root, aabb)
	## Soft-follow / visual_to_global treat this as the glued mesh seat.
	_model_rest_local = root.position


## Re-run display scale from current DataStore (model_size_compensate live preview).
## Pick tris stay mesh-local; world AABB / triangle tests use updated global_transform.
func apply_model_size_from_data() -> void:
	if _model_root == null or not is_instance_valid(_model_root):
		return
	var ship_data: Dictionary = DataStore.get_ship(ship_id) if DataStore else {}
	var compensate: float = clampf(
		TypedVariant.as_float(ship_data.get("model_size_compensate", 1.0), 1.0), 0.15, 4.0
	)
	if _applied_size_compensate >= 0.0 and is_equal_approx(compensate, _applied_size_compensate):
		return
	_normalize_model_scale(_model_root)
	_cache_model_rest_pose()
	if _health_bar != null and is_instance_valid(_health_bar) and _health_bar.has_method("refresh"):
		_health_bar.call("refresh")

func _aabb_mesh_local(root: Node3D) -> AABB:
	## Mesh AABB in root's local space via local transforms (safe before/after scale; ignores root.scale).
	var result: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _find_meshes(root):
		var xf: Transform3D = _xform_to_ancestor(root, mi)
		var local_aabb: AABB = mi.get_aabb()
		for i: int in range(8):
			var p: Vector3 = xf * local_aabb.get_endpoint(i)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	return result

func _aabb_in_ship_space(root: Node3D) -> AABB:
	## Mesh AABB in ShipUnit local space (includes root.position/scale/rotation).
	var result: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _find_meshes(root):
		var xf: Transform3D
		if is_inside_tree():
			xf = global_transform.affine_inverse() * mi.global_transform
		else:
			xf = root.transform * _xform_to_ancestor(root, mi)
		var local_aabb: AABB = mi.get_aabb()
		for i: int in range(8):
			var p: Vector3 = xf * local_aabb.get_endpoint(i)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	return result

func visual_center_world() -> Vector3:
	if _model_root != null:
		var aabb: AABB = _aabb_in_ship_space(_model_root)
		## AABB is already in current ship-local (includes soft-follow offset); map via root.
		return global_transform * aabb.get_center()
	return visual_origin_world()

func visual_radius_world() -> float:
	if _model_root != null:
		var aabb: AABB = _aabb_in_ship_space(_model_root)
		return maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
	return 1.0

## Camera ray vs visible hull (BOARD_AND_INPUT §4 · EQUIPMENT.md).
## AABB broadphase, then triangle soup — empty AABB air does not block ships behind.
## Returns distance along dir to the nearest triangle, or -1 if miss.
func ray_hit_model_distance(origin: Vector3, dir: Vector3) -> float:
	if _model_root == null or not is_instance_valid(_model_root):
		return -1.0
	var nd: Vector3 = dir.normalized()
	if nd.length_squared() < 1e-12:
		return -1.0
	if _ray_hit_model_aabb_distance(origin, nd) < 0.0:
		return -1.0
	_ensure_pick_tris()
	var best_t: float = -1.0
	var n_sets: int = _pick_tri_mi.size()
	for si: int in range(n_sets):
		var mi: MeshInstance3D = _pick_tri_mi[si]
		if mi == null or not is_instance_valid(mi) or not mi.is_visible_in_tree():
			continue
		var xf: Transform3D = mi.global_transform
		var inv: Transform3D = xf.affine_inverse()
		var o_l: Vector3 = inv * origin
		var d_l: Vector3 = inv.basis * nd
		if d_l.length_squared() < 1e-20:
			continue
		var tris: PackedVector3Array = _pick_tri_local[si]
		var ti: int = 0
		var tn: int = tris.size()
		while ti + 2 < tn:
			var hit_v: Variant = Geometry3D.ray_intersects_triangle(
				o_l, d_l, tris[ti], tris[ti + 1], tris[ti + 2]
			)
			ti += 3
			if typeof(hit_v) != TYPE_VECTOR3:
				continue
			@warning_ignore("unsafe_cast")
			var hit_w: Vector3 = xf * (hit_v as Vector3)
			var t: float = (hit_w - origin).dot(nd)
			if t < 0.0:
				continue
			if best_t < 0.0 or t < best_t:
				best_t = t
	return best_t


func _ray_hit_model_aabb_distance(origin: Vector3, nd: Vector3) -> float:
	var best_t: float = -1.0
	for mi: MeshInstance3D in _find_meshes(_model_root):
		if mi == null or not is_instance_valid(mi) or not mi.is_visible_in_tree():
			continue
		var local_aabb: AABB = mi.get_aabb()
		if local_aabb.size.length_squared() < 1e-12:
			continue
		var world_box: AABB = _aabb_from_transformed(mi.global_transform, local_aabb)
		var t: float = _ray_aabb_enter_t(origin, nd, world_box)
		if t < 0.0:
			continue
		if best_t < 0.0 or t < best_t:
			best_t = t
	return best_t


func _ensure_pick_tris() -> void:
	if not _pick_tri_local.is_empty():
		return
	if _model_root == null or not is_instance_valid(_model_root):
		return
	for mi: MeshInstance3D in _find_meshes(_model_root):
		if mi == null or mi.mesh == null:
			continue
		var packed: PackedVector3Array = PackedVector3Array()
		var mesh: Mesh = mi.mesh
		for s: int in range(mesh.get_surface_count()):
			if mesh is ArrayMesh:
				@warning_ignore("unsafe_cast")
				if (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
			var arr: Array = mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var indices: Variant = arr[Mesh.ARRAY_INDEX]
			if indices is PackedInt32Array:
				@warning_ignore("unsafe_cast")
				var i32: PackedInt32Array = indices as PackedInt32Array
				var k: int = 0
				var nidx: int = i32.size()
				while k + 2 < nidx:
					packed.append(verts[i32[k]])
					packed.append(verts[i32[k + 1]])
					packed.append(verts[i32[k + 2]])
					k += 3
			else:
				var nvert: int = verts.size()
				var j: int = 0
				while j + 2 < nvert:
					packed.append(verts[j])
					packed.append(verts[j + 1])
					packed.append(verts[j + 2])
					j += 3
		if packed.size() >= 3:
			_pick_tri_mi.append(mi)
			_pick_tri_local.append(packed)


## Slab AABB ray enter distance; -1 on miss. Avoids Variant cast from AABB.intersects_ray.
func _ray_aabb_enter_t(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var inv_x: float = 1.0 / dir.x if absf(dir.x) > 1e-12 else 1e12
	var inv_y: float = 1.0 / dir.y if absf(dir.y) > 1e-12 else 1e12
	var inv_z: float = 1.0 / dir.z if absf(dir.z) > 1e-12 else 1e12
	var min_b: Vector3 = box.position
	var max_b: Vector3 = box.position + box.size
	var tx0: float = (min_b.x - origin.x) * inv_x
	var tx1: float = (max_b.x - origin.x) * inv_x
	var ty0: float = (min_b.y - origin.y) * inv_y
	var ty1: float = (max_b.y - origin.y) * inv_y
	var tz0: float = (min_b.z - origin.z) * inv_z
	var tz1: float = (max_b.z - origin.z) * inv_z
	var tmin: float = maxf(maxf(minf(tx0, tx1), minf(ty0, ty1)), minf(tz0, tz1))
	var tmax: float = minf(minf(maxf(tx0, tx1), maxf(ty0, ty1)), maxf(tz0, tz1))
	if tmax < 0.0 or tmin > tmax:
		return -1.0
	if tmin >= 0.0:
		return tmin
	if tmax >= 0.0:
		return tmax
	return -1.0

func _aabb_from_transformed(xf: Transform3D, local: AABB) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for i: int in range(8):
		var p: Vector3 = xf * local.get_endpoint(i)
		if first:
			result = AABB(p, Vector3.ZERO)
			first = false
		else:
			result = result.expand(p)
	return result

func _xform_to_ancestor(ancestor: Node3D, leaf: Node) -> Transform3D:
	## Local transform from ancestor to leaf (does not include ancestor.transform).
	var chain: Array[Node3D] = []
	var walk: Node = leaf
	while walk != null and walk != ancestor:
		if walk is Node3D:
			chain.push_front(walk as Node3D)
		walk = walk.get_parent()
	var xf: Transform3D = Transform3D.IDENTITY
	for n: Node3D in chain:
		xf = xf * n.transform
	return xf

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_find_meshes(c))
	return out

func _tint_model(root: Node) -> void:
	## Prefer Echoes §0 bundle with auxiliary control maps (pmwo/rg/reduction),
	## else fall back to simpler albedo+normal tint.
	var diffuse_path: String = DataStore.ship_diffuse_path(ship_id) if DataStore and DataStore.has_method("ship_diffuse_path") else ""
	var key: String = str(DataStore.get_ship(ship_id).get("model_key", ""))
	var bundle: Dictionary = {}
	if DataStore != null and DataStore.has_method("resolve_model_bundle"):
		bundle = DataStore.resolve_model_bundle(key)
	else:
		var root_dir: String = "res://assets/models/ships/%s" % key
		bundle = {
			"mesh": root_dir.path_join("model.glb"),
			"albedo": root_dir.path_join("albedo.png"),
			"normal": root_dir.path_join("normal.png"),
			"pmwo": root_dir.path_join("pmwo.png"),
			"rg": root_dir.path_join("rg.png"),
			"reduction": root_dir.path_join("reduction.png"),
		}
	if not _texture_file_ok(diffuse_path):
		diffuse_path = str(bundle.get("albedo", ""))
	var diffuse: Texture2D = UiAssets.tex_ship_bake(diffuse_path) if diffuse_path != "" else null
	var normal: Texture2D = null
	var pmwo: Texture2D = null
	var rg_tex: Texture2D = null
	var reduction: Texture2D = null
	if diffuse_path != "":
		if diffuse_path.ends_with("_d.png"):
			normal = UiAssets.tex_ship_bake(diffuse_path.replace("_d.png", "_n.png"))
		elif diffuse_path.ends_with("_ad.png"):
			normal = UiAssets.tex_ship_bake(diffuse_path.replace("_ad.png", "_n.png"))
		elif diffuse_path.ends_with("albedo.png"):
			var npath: String = diffuse_path.replace("albedo.png", "normal.png")
			if _texture_file_ok(npath):
				normal = UiAssets.tex_ship_bake(npath)
	var pmwo_path: String = str(bundle.get("pmwo", ""))
	var rg_path: String = str(bundle.get("rg", ""))
	var reduction_path: String = str(bundle.get("reduction", ""))
	if _texture_file_ok(pmwo_path):
		pmwo = UiAssets.tex_ship_bake(pmwo_path)
	if _texture_file_ok(rg_path):
		rg_tex = UiAssets.tex_ship_bake(rg_path)
	if _texture_file_ok(reduction_path):
		reduction = UiAssets.tex_ship_bake(reduction_path)
	if diffuse == null and diffuse_path != "":
		push_warning("ShipUnit missing diffuse ship_id=%s path=%s" % [ship_id, diffuse_path])
	var neutral: Color = Color(0.82, 0.84, 0.88, 1.0)
	var use_unity: bool = ShipLook.is_unity_standard()
	for mi: MeshInstance3D in _find_meshes(root):
		var mat: Material
		if use_unity and diffuse and normal and (pmwo != null) and (rg_tex != null):
			## Unity StandardShipShader port — needs albedo/normal/pmwo/rg (reduction optional).
			var smat: ShaderMaterial = ShaderMaterial.new()
			smat.shader = _UNITY_SHIP_SHADER
			smat.set_shader_parameter("albedo_tex", diffuse)
			smat.set_shader_parameter("normal_tex", normal)
			smat.set_shader_parameter("pmwo_tex", pmwo)
			smat.set_shader_parameter("rg_tex", rg_tex)
			ShipLook.apply_to_unity_shader_material(smat)
			## Stratios-style glass: albedo alpha marks atlas padding / membrane UVs.
			var glass_flag: String = "res://assets/models/ships/%s/glass_cutout.on" % key
			if _texture_file_ok(glass_flag):
				smat.set_shader_parameter("alpha_cutoff", 0.5)
			mat = smat
		elif diffuse and normal and pmwo and rg_tex and reduction and not use_unity:
			var smat: ShaderMaterial = ShaderMaterial.new()
			smat.shader = _ECHOES_SURFACE_SHADER
			smat.set_shader_parameter("albedo_tex", diffuse)
			smat.set_shader_parameter("normal_tex", normal)
			smat.set_shader_parameter("pmwo_tex", pmwo)
			smat.set_shader_parameter("rg_tex", rg_tex)
			smat.set_shader_parameter("reduction_tex", reduction)
			smat.set_shader_parameter("combat_emission_strength", 0.0)
			ShipLook.apply_to_shader_material(smat, ship_id, diffuse, diffuse_path)
			mat = smat
		else:
			var std: StandardMaterial3D = StandardMaterial3D.new()
			std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			std.texture_repeat = true
			# Solid hull: alpha/cull from GLB materials looks like “镂空”.
			std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			if diffuse:
				std.albedo_texture = diffuse
				std.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				std.ao_enabled = false
			else:
				## No albedo — fall back to a neutral hull tone, not race/team tint.
				std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				std.albedo_color = Color(neutral.r, neutral.g, neutral.b, 1.0)
				std.emission_enabled = false
			if normal:
				std.normal_enabled = true
				std.normal_texture = normal
				std.normal_scale = 0.92
			std.metallic = 0.10
			std.metallic_specular = 0.03
			std.roughness = 0.70
			if diffuse:
				ShipLook.apply_to_standard_material(std, ship_id, diffuse, diffuse_path)
				std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				std.albedo_color.a = 1.0
			mat = std
		mi.material_override = mat
		mi.material_overlay = null
		# Drop GLB surface mats that may still carry alpha cutout under override edge cases.
		if mi.mesh:
			for si: int in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(si, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _texture_file_ok(path: String) -> bool:
	if path == "":
		return false
	# PCK / Android: globalize_path often misses packed res:// — use ResourceLoader first.
	if ResourceLoader.exists(path):
		return true
	if FileAccess.file_exists(path):
		return true
	var abs_path: String = ProjectSettings.globalize_path(path)
	return abs_path != "" and FileAccess.file_exists(abs_path)

func _race_hull_color(race_id: String) -> Color:
	match race_id:
		"caldari":
			return Color(0.38, 0.58, 0.82)
		"gallente":
			return Color(0.40, 0.78, 0.52)
		"minmatar":
			return Color(0.90, 0.48, 0.32)
		_:
			return Color(0.95, 0.78, 0.40)

func set_combat_tint(in_combat: bool) -> void:
	if is_destroyed:
		_combat_glow_left_s = -1.0
		return
	if in_combat:
		## Fresh window each arm (battle start / cyno jump-in); duration is sim-seconds.
		_combat_glow_left_s = TypedVariant.as_float(DataStore.visual.get("combat_glow_s", COMBAT_GLOW_S)) if DataStore else COMBAT_GLOW_S
		_apply_combat_tint_visual(true)
	else:
		_combat_glow_left_s = -1.0
		_apply_combat_tint_visual(false)


## Called from CombatResolver each sim step (scaled by 倍速; independent of render FPS).
func tick_combat_glow(sim_delta: float) -> void:
	if _combat_glow_left_s < 0.0:
		return
	_combat_glow_left_s -= sim_delta
	if _combat_glow_left_s > 0.0:
		return
	_combat_glow_left_s = -1.0
	## Morph owns emission while playing; clear white film when morph is done.
	if not hull_morph_playing:
		_apply_combat_tint_visual(false)


func _apply_combat_tint_visual(in_combat: bool) -> void:
	## Invisible pick sphere must stay a=0; combat glow used to paint it opaque white.
	if _model_root != null and _model_root.has_meta("no_model_pick_sphere"):
		return
	var unity_strength: float = 0.06 if in_combat else 0.0
	var echoes_strength: float = 0.08 if in_combat else 0.0
	var std_strength: float = 0.18 if in_combat else 0.0
	if _mat:
		var neutral: Color = Color(0.82, 0.84, 0.88, 1.0)
		_mat.albedo_color = neutral.lightened(0.06) if in_combat else neutral
		_mat.emission_enabled = in_combat
		_mat.emission = Color.WHITE
		_mat.emission_energy_multiplier = std_strength
		return
	if _model_root == null:
		return
	var neutral2: Color = Color(0.82, 0.84, 0.88, 1.0)
	for mi: MeshInstance3D in _find_meshes(_model_root):
		if _is_pick_proxy_mesh(mi):
			continue
		if mi.material_override is ShaderMaterial:
			var smat: ShaderMaterial = mi.material_override as ShaderMaterial
			var strength: float = unity_strength if smat.shader == _UNITY_SHIP_SHADER else echoes_strength
			_set_mesh_emission(mi, strength, Color.WHITE, false)
			if smat.shader != _UNITY_SHIP_SHADER and not in_combat:
				smat.set_shader_parameter("team_tint", Color.WHITE)
				smat.set_shader_parameter("team_mix", 0.0)
		elif mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
			if mat.albedo_texture:
				_set_mesh_emission(mi, std_strength, Color.WHITE, false)
			else:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = neutral2.lightened(0.06) if in_combat else neutral2
				mat.emission_enabled = false
		else:
			_set_mesh_emission(mi, unity_strength, Color.WHITE, false)

## Salvage freighters are protected neutrals no matter which half they were spawned on
## (FREIGHTER_AND_TITAN §1.2.1) — data-driven so a new hull only needs the group/tag.
static func _resolve_protect_target(ship: Dictionary) -> bool:
	if str(ship.get("ship_group", "")) == "freighter":
		return true
	for t: Variant in TypedVariant.as_array(ship.get("tags", [])):
		if str(t) == "pve_salvage":
			return true
	return false

func reload_stats() -> void:
	var ship: Dictionary = DataStore.get_ship(ship_id)
	var st: Dictionary = DataStore.get_star_resolved(ship_id, star)
	if st.is_empty() and star != 1:
		st = DataStore.get_star_resolved(ship_id, 1)
	if st.is_empty():
		return
	is_logistic = TypedVariant.as_bool(ship.get("is_logistic", false)) or TypedVariant.as_bool(st.get("is_logistic", false))
	is_mining_ship = TypedVariant.as_bool(ship.get("is_mining_ship", false))
	is_protect_target = _resolve_protect_target(ship)
	race = str(ship.get("race", "amarr")).to_lower()
	attack_range = TypedVariant.as_float(st.get("attack_range", 1))
	var dmg: Dictionary = st.get("damage", {})
	## Kit-derived hulls keep ★1 base DPH here; star raise is star_dph_mul (invisible buff).
	## Baked stars[] (unmanned / unresolved capital) already include star × on damage.
	damage_emp = TypedVariant.as_float(dmg.get("emp", 0))
	damage_thermal = TypedVariant.as_float(dmg.get("thermal", 0))
	damage_kinetic = TypedVariant.as_float(dmg.get("kinetic", 0))
	damage_explosive = TypedVariant.as_float(dmg.get("explosive", 0))
	star_dph_mul = float(maxi(star, 1)) if ShipWeaponDerive.should_derive(ship) else 1.0
	var rep_src: Dictionary = st
	if is_logistic or str(ship.get("unmanned_kind", "")).find("repair") >= 0:
		var st1: Dictionary = DataStore.get_star_resolved(ship_id, 1)
		if not st1.is_empty():
			rep_src = st1
	var rep: Dictionary = rep_src.get("repair", {})
	repair_shield = TypedVariant.as_float(rep.get("shield", 0))
	repair_armor = TypedVariant.as_float(rep.get("armor", 0))
	repair_structure = TypedVariant.as_float(rep.get("structure", 0))
	max_shield = TypedVariant.as_float(st.get("shield_hp", 0))
	max_armor = TypedVariant.as_float(st.get("armor_hp", 0))
	if st.has("structure_hp"):
		max_structure = TypedVariant.as_float(st.get("structure_hp", 0))
	else:
		max_structure = maxf(50.0, roundf(max_armor * 0.5))
	base_max_shield = max_shield
	base_max_armor = max_armor
	base_max_structure = max_structure
	pristine_base_max_shield = base_max_shield
	pristine_base_max_armor = base_max_armor
	pristine_base_max_structure = base_max_structure
	shield_hp = max_shield
	armor_hp = max_armor
	structure_hp = max_structure
	var sr: Dictionary = st.get("shield_resist", {})
	var ar: Dictionary = st.get("armor_resist", {})
	var str_res: Dictionary = st.get("structure_resist", ar if typeof(ar) == TYPE_DICTIONARY else {})
	_shield_resist = sr.duplicate()
	_armor_resist = ar.duplicate()
	_structure_resist = str_res.duplicate()
	_base_shield_resist = _shield_resist.duplicate()
	_base_armor_resist = _armor_resist.duplicate()
	_base_structure_resist = _structure_resist.duplicate()
	shield_resist_emp = TypedVariant.as_float(sr.get("emp", 0))
	armor_resist_emp = TypedVariant.as_float(ar.get("emp", 0))
	structure_resist_emp = TypedVariant.as_float(str_res.get("emp", armor_resist_emp))
	_base_shield_resist_emp = shield_resist_emp
	_base_armor_resist_emp = armor_resist_emp
	_base_structure_resist_emp = structure_resist_emp
	signature_radius = TypedVariant.as_float(ship.get("signature_radius", 40.0))
	scan_resolution = TypedVariant.as_float(ship.get("scan_resolution", 400.0))
	base_scan_resolution = scan_resolution
	fetter_cap_warfare_mul = 1.0
	fetter_ewar_mul = 1.0
	base_speed = TypedVariant.as_float(ship.get("speed", 300.0))
	base_mass = maxf(TypedVariant.as_float(ship.get("mass", 1000000.0)), 1.0)
	base_agility = maxf(TypedVariant.as_float(ship.get("agility", 1.0)), 0.001)
	tracking = TypedVariant.as_float(st.get("tracking", 0.0))
	optimal_cells = TypedVariant.as_float(st.get("optimal", 0.0))
	falloff_cells = TypedVariant.as_float(st.get("falloff", 0.0))
	optimal_sig_radius = TypedVariant.as_float(st.get("optimal_sig_radius", 40.0))
	explosion_radius = TypedVariant.as_float(st.get("explosion_radius", 0.0))
	explosion_velocity = TypedVariant.as_float(st.get("explosion_velocity", 0.0))
	missile_drf = TypedVariant.as_float(st.get("drf", 0.0))
	missile_drs = TypedVariant.as_float(st.get("drs", DataStore.combat.get("missile_drs_default", 5.5)))
	cap_capacity = TypedVariant.as_float(ship.get("capacitor_capacity", 0.0))
	## Covert cyno: show cap ring at 1/1 (UI cue) — 0 max reads as missing bar.
	if cap_capacity <= 0.0 and FunctionFit.is_cyno_hull(ship):
		cap_capacity = 1.0
	cap_recharge_s = maxf(TypedVariant.as_float(ship.get("capacitor_recharge_s", 1.0)), 0.001)
	cap_cost_per_cycle = TypedVariant.as_float(st.get("cap_cost", ship.get("cap_cost", -1.0)))
	fetter_repair_mul = 1.0
	fetter_speed_mul = 1.0
	var cd: Dictionary = DataStore.combat
	var cycle: float = TypedVariant.as_float(ship.get("attack_cycle_s", -1.0))
	var derived_cycle: float = TypedVariant.as_float(st.get("_attack_cycle_s", -1.0))
	if derived_cycle > 0.0 and ShipWeaponDerive.should_derive(ship):
		cycle = derived_cycle
	if cycle <= 0.0:
		cycle = TypedVariant.as_float(cd.get("logistic_attack_duration_s" if is_logistic else "attack_duration_s", 1.0))
	var cap_s: float = TypedVariant.as_float(cd.get("attack_cycle_cap_s", 6.0))
	## Capitals / cyno / explicit long cycles keep JSON cycle (siege & 90s channel).
	var role: String = str(ship.get("capital_role", ""))
	if role != "" or TypedVariant.as_bool(ship.get("requires_cyno_entry", false)):
		attack_duration = cycle
	else:
		attack_duration = minf(cycle, cap_s)
	base_attack_duration = attack_duration
	is_destroyed = false
	is_unmanned = TypedVariant.as_bool(ship.get("is_unmanned", false))
	unmanned_kind = str(ship.get("unmanned_kind", ""))
	drone_bandwidth = TypedVariant.as_float(ship.get("drone_bandwidth", 0.0))
	## Explicit drone_bay_slots=0 must win (faction frigates). Bandwidth invent only if key omitted.
	if ship.has("drone_bay_slots"):
		drone_bay_slots = TypedVariant.as_int(ship.get("drone_bay_slots"), 0)
	else:
		drone_bay_slots = TypedVariant.as_int(ship.get("drone_count_cap", 0))
		if drone_bay_slots <= 0 and drone_bandwidth > 0.0:
			drone_bay_slots = int(floorf(drone_bandwidth / 5.0))
	visible = true
	reset_combat_runtime()
	if _health_bar:
		_health_bar.visible = true
		_health_bar.call("refresh")
	sync_tactical_stem()
	FunctionFit.apply_passives_to_ship(self)

func _load_function_fit_from_slots(fs: Dictionary) -> void:
	_function_fit.clear()
	_plugin_modules.clear()
	_refresh_function_slot_locked(fs)
	if typeof(fs) != TYPE_DICTIONARY:
		return
	var slots: Array = TypedVariant.as_array(fs.get("slots", []))
	var ship_data: Dictionary = DataStore.get_ship(ship_id)
	## Cyno hulls: induction module stays in plugins only — no shop function-bucket strip.
	if FunctionFit.is_cyno_hull(ship_data) or capital_role == "covert_cyno":
		for m: Variant in slots:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var md: Dictionary = TypedVariant.as_dict(m).duplicate(true)
			if FunctionFit.is_cyno_def(md):
				_plugin_modules.append(md)
		return
	_function_fit = FunctionFit.entries_from_slot_list(slots)
	for entry: Variant in _function_fit:
		var def: Dictionary = TypedVariant.as_dict(TypedVariant.as_dict(entry).get("def", {}))
		if FunctionFit.is_cyno_def(def):
			_plugin_modules.append(def.duplicate(true))

func get_function_fit() -> Array:
	return _function_fit.duplicate(true)


func _refresh_function_slot_locked(fs: Dictionary = {}) -> void:
	_function_slot_locked.clear()
	for _i: int in range(FunctionFit.MAX_SLOTS):
		_function_slot_locked.append(false)
	var use_fs: Dictionary = fs
	if use_fs.is_empty():
		use_fs = TypedVariant.as_dict(DataStore.get_ship(ship_id).get("function_slots", {}))
	var slots: Array = TypedVariant.as_array(use_fs.get("slots", []))
	for i: int in range(mini(slots.size(), FunctionFit.MAX_SLOTS)):
		var md: Dictionary = TypedVariant.as_dict(slots[i])
		_function_slot_locked[i] = TypedVariant.as_bool(md.get("locked", false), false)


func function_slot_locked(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _function_slot_locked.size():
		return false
	return TypedVariant.as_bool(_function_slot_locked[slot_index], false)


func add_runtime_fetter(fetter_id: String, until_sim_time: float) -> void:
	var fid: String = fetter_id.strip_edges()
	if fid == "":
		return
	if not _runtime_fetter_ids.has(fid):
		_runtime_fetter_ids.append(fid)
	_runtime_fetter_until[fid] = until_sim_time


func get_active_runtime_fetters(sim_time: float) -> Array:
	var out: Array = []
	for fid_v: Variant in _runtime_fetter_ids:
		var fid: String = str(fid_v)
		var until: float = TypedVariant.as_float(_runtime_fetter_until.get(fid, -1.0), -1.0)
		if until < 0.0 or sim_time <= until:
			out.append(fid)
	return out


func prune_runtime_fetters(sim_time: float) -> void:
	var kept: Array = []
	for fid_v: Variant in _runtime_fetter_ids:
		var fid: String = str(fid_v)
		var until: float = TypedVariant.as_float(_runtime_fetter_until.get(fid, -1.0), -1.0)
		if until < 0.0 or sim_time <= until:
			kept.append(fid)
		else:
			_runtime_fetter_until.erase(fid)
	_runtime_fetter_ids = kept


## Prepare-phase fit from inventory. Returns {ok, reason} — reason: size | full | unknown | cyno_hull | …
func try_fit_function_module(module_id: String, slot_index: int = -1) -> Dictionary:
	var mid: String = module_id.strip_edges()
	if mid == "":
		return {"ok": false, "reason": "empty"}
	var def: Dictionary = DataStore.get_function_module(mid)
	if def.is_empty():
		return {"ok": false, "reason": "unknown"}
	var ship_data: Dictionary = DataStore.get_ship(ship_id)
	if not FunctionFit.ship_allows_function_fit(ship_data):
		return {"ok": false, "reason": "cyno_hull"}
	if not FunctionFit.size_allowed_for_ship(ship_data, def):
		var roles_v: Variant = def.get("require_capital_roles", [])
		if typeof(roles_v) == TYPE_ARRAY and not TypedVariant.as_array(roles_v).is_empty():
			return {"ok": false, "reason": "capital_role"}
		return {"ok": false, "reason": "size"}
	if TypedVariant.as_bool(def.get("implant", false), false) and _function_fit_has_implant():
		return {"ok": false, "reason": "implant_taken"}
	if TypedVariant.as_bool(def.get("unique_per_ship", false), false) and _function_fit_has_unique_line(str(def.get("line", mid))):
		return {"ok": false, "reason": "lance_taken"}
	if _function_fit.size() >= FunctionFit.MAX_SLOTS:
		return {"ok": false, "reason": "full"}
	var target: int = slot_index
	if target < 0:
		target = _function_fit.size()
	else:
		target = clampi(target, 0, FunctionFit.MAX_SLOTS - 1)
	if function_slot_locked(target):
		return {"ok": false, "reason": "slot_locked"}
	if target < _function_fit.size():
		return {"ok": false, "reason": "slot_taken"}
	if target > _function_fit.size():
		return {"ok": false, "reason": "slot_order"}
	_function_fit.append({"id": mid, "def": def.duplicate(true)})
	if FunctionFit.is_cyno_def(def):
		_plugin_modules.append(def.duplicate(true))
	reload_stats()
	return {"ok": true, "reason": ""}


func _function_fit_has_implant() -> bool:
	for entry: Variant in _function_fit:
		var e: Dictionary = TypedVariant.as_dict(entry)
		var d: Dictionary = TypedVariant.as_dict(e.get("def", {}))
		if TypedVariant.as_bool(d.get("implant", false), false):
			return true
		var fid: String = str(e.get("id", "")).strip_edges()
		if fid != "" and TypedVariant.as_bool(DataStore.get_function_module(fid).get("implant", false), false):
			return true
	return false


func _function_fit_has_unique_line(line: String) -> bool:
	var want: String = line.strip_edges()
	if want == "":
		return false
	for entry: Variant in _function_fit:
		var e: Dictionary = TypedVariant.as_dict(entry)
		var d: Dictionary = TypedVariant.as_dict(e.get("def", {}))
		var lid: String = str(d.get("line", e.get("id", ""))).strip_edges()
		if lid == want and TypedVariant.as_bool(d.get("unique_per_ship", false), false):
			return true
	return false


## Prepare unequip. Returns removed module id (empty if miss).
func unequip_function_at(slot_index: int) -> String:
	if function_slot_locked(slot_index):
		return ""
	if slot_index < 0 or slot_index >= _function_fit.size():
		return ""
	var entry: Dictionary = _function_fit[slot_index]
	var mid: String = str(entry.get("id", "")).strip_edges()
	var def: Dictionary = TypedVariant.as_dict(entry.get("def", {}))
	_function_fit.remove_at(slot_index)
	if FunctionFit.is_cyno_def(def):
		for i: int in range(_plugin_modules.size() - 1, -1, -1):
			if FunctionFit.is_cyno_def(TypedVariant.as_dict(_plugin_modules[i])):
				_plugin_modules.remove_at(i)
				break
	reload_stats()
	return mid

func set_function_fit(entries: Array) -> void:
	_function_fit.clear()
	_plugin_modules.clear()
	var saw_implant: bool = false
	var saw_lance: bool = false
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _function_fit.size() >= FunctionFit.MAX_SLOTS:
			break
		var e: Dictionary = TypedVariant.as_dict(entry).duplicate(true)
		var fid: String = str(e.get("id", ""))
		var def: Dictionary = TypedVariant.as_dict(e.get("def", DataStore.get_function_module(fid)))
		if def.is_empty():
			continue
		if not FunctionFit.size_allowed_for_ship(DataStore.get_ship(ship_id), def):
			continue
		var is_implant: bool = TypedVariant.as_bool(def.get("implant", false), false)
		if is_implant and saw_implant:
			SessionDiagnostics.log("equip.implant_clamp", "drop extra implant=%s ship=%d" % [fid, ship_id])
			continue
		if is_implant:
			saw_implant = true
		if TypedVariant.as_bool(def.get("unique_per_ship", false), false) and saw_lance:
			SessionDiagnostics.log("equip.lance_clamp", "drop extra lance=%s ship=%d" % [fid, ship_id])
			continue
		if TypedVariant.as_bool(def.get("unique_per_ship", false), false):
			saw_lance = true
		_function_fit.append({"id": fid, "def": def.duplicate(true)})
		if FunctionFit.is_cyno_def(def):
			_plugin_modules.append(def.duplicate(true))
	reload_stats()

func reset_combat_runtime() -> void:
	hull_morph_playing = false
	hull_morphed = false
	hull_morph_unstacking = false
	capital_jumping = false

	cap_current = cap_capacity
	lock_target_id = 0
	lock_timer = 0.0
	lock_duration_s = 0.0
	clear_pre_lock()
	retreat_until_time = -1.0
	no_target_acc = 0.0
	combat_target = null
	_function_target = null
	last_attack_time = -999.0
	lance_suppress_weapons = false
	_heal_received_mul = 1.0
	_heal_received_mul_until = -1.0
	FunctionFit.abort_mixed_lances(self)
	_stat_modifiers.clear()
	FunctionFit.reset_combat_state(self)
	_runtime_fetter_ids.clear()
	_runtime_fetter_until.clear()
	_blink_speed_mul = 1.0
	_blink_until_time = -1.0
	## Carrier pool re-inits on next ensure; do not wipe living fighters' squadron id.
	fighter_squadron_pool_left = -1
	fighter_next_squadron_id = 0
	if not is_unmanned:
		fighter_squadron_id = -1
	hull_morph_playing = false
	hull_morphed = false
	hull_morph_unstacking = false
	clear_move_velocity()
	restore_model_rest_pose()
	## Drop leftover morph FX from prior round if still parented.
	var old_fx: Node = get_parent().get_node_or_null("HullMorphFx_%d" % get_instance_id()) if get_parent() else null
	if old_fx != null and is_instance_valid(old_fx):
		old_fx.queue_free()

func get_stat(stat_name: String, base_value: float) -> float:
	var add: float = 0.0
	var mul: float = 1.0
	for m: Variant in _stat_modifiers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = TypedVariant.as_dict(m)
		if str(md.get("stat", "")) != stat_name:
			continue
		match str(md.get("op", "add")):
			"add":
				add += TypedVariant.as_float(md.get("value", 0.0))
			"mul":
				mul *= TypedVariant.as_float(md.get("value", 1.0))
	return (base_value + add) * mul

func layer_resist(layer: String, dtype: String, base: float) -> float:
	var add: float = 0.0
	var mul: float = 1.0
	var has_set: bool = false
	var set_v: float = 0.0
	for m: Variant in _stat_modifiers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = TypedVariant.as_dict(m)
		var stat_name: String = str(md.get("stat", ""))
		if stat_name != "resist_%s_%s" % [layer, dtype]:
			continue
		match str(md.get("op", "add")):
			"set":
				has_set = true
				set_v = TypedVariant.as_float(md.get("value", 0.0))
			"add":
				add += TypedVariant.as_float(md.get("value", 0.0))
			"mul":
				mul *= TypedVariant.as_float(md.get("value", 1.0))
	## Absolute set (set_resist_active) may reach 1.0; normal add path stays capped at 0.95.
	if has_set:
		return clampf(set_v, 0.0, 1.0)
	return clampf((base + add) * mul, 0.0, 0.95)

func add_stat_modifier(source: String, stat_name: String, op: String, value: float, duration: float = -1.0, stack_id: String = "") -> void:
	## Non-empty stack_id replaces prior entry (refresh debuffs without stacking).
	if stack_id != "":
		var kept: Array = []
		for m: Variant in _stat_modifiers:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var md: Dictionary = TypedVariant.as_dict(m)
			if str(md.get("stack_id", "")) == stack_id:
				continue
			kept.append(md)
		_stat_modifiers = kept
	_stat_modifiers.append({
		"source": source,
		"stat": stat_name,
		"op": op,
		"value": value,
		"duration": duration,
		"stack_id": stack_id,
		"age": 0.0,
	})

func tick_stat_modifiers(sim_dt: float) -> void:
	var kept: Array = []
	for m: Variant in _stat_modifiers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = TypedVariant.as_dict(m)
		var dur: float = TypedVariant.as_float(md.get("duration", -1.0))
		if dur < 0.0:
			kept.append(md)
			continue
		md["age"] = TypedVariant.as_float(md.get("age", 0.0)) + sim_dt
		if TypedVariant.as_float(md.get("age", 0.0)) < dur:
			kept.append(md)
	_stat_modifiers = kept

func combat_move_speed() -> float:
	var wu: float = CombatFormulas.world_units_per_cell()
	var move_scale: float = TypedVariant.as_float(DataStore.combat.get("move_speed_scale", 1.65))
	## Movement runs on its own metric — 1 cell = 750 m, never the 2 km range metric.
	var m_per_cell: float = TypedVariant.as_float(DataStore.combat.get("speed_meters_per_cell", 750.0))
	var spd: float = get_stat("speed", base_speed)
	var mapped: float = spd / m_per_cell * wu * move_scale * fetter_speed_mul
	var speed: float = maxf(mapped, 0.5)
	if absf(global_position.z) < (
		BoardPolarGrid.isolation_half_width()
		if BoardPolarGrid.is_polar()
		else TypedVariant.as_float(DataStore.combat.get("isolation_half_width_wu", 2.5), 2.5)
	):
		speed *= TypedVariant.as_float(DataStore.combat.get("isolation_speed_mul", 0.7))
	## Excavators wander the belt slowly (MINING §2.1): 1/5 mapped move speed.
	if is_unmanned and str(unmanned_kind) == "mining_excavator":
		speed *= TypedVariant.as_float(DataStore.combat.get("mining_excavator_move_mul", 0.2))
	if _blink_until_time > _combat_sim_time and _blink_speed_mul > 1.0:
		speed *= _blink_speed_mul
	return speed


## EVE Uni: τ = I×M/10⁶. Field `agility` is the inertia modifier.
func combat_inertia_tau_s() -> float:
	var mass: float = maxf(get_stat("mass", base_mass), 1.0)
	var inertia: float = maxf(get_stat("agility", base_agility), 0.001)
	var tau: float = inertia * mass * 1.0e-6
	var tau_min: float = TypedVariant.as_float(DataStore.combat.get("move_inertia_tau_min_s", 0.05))
	return maxf(tau, tau_min)


func clear_move_velocity() -> void:
	move_velocity_wu = Vector3.ZERO


func combat_speed_now() -> float:
	if y_axis_unlocked():
		return move_velocity_wu.length()
	return Vector3(move_velocity_wu.x, 0.0, move_velocity_wu.z).length()


## Accelerate / decelerate toward desired velocity (COMBAT §3.1). Returns this-step displacement.
func tick_combat_velocity(desired_vel: Vector3, delta: float) -> Vector3:
	var unlock_y: bool = y_axis_unlocked()
	if not unlock_y:
		desired_vel.y = 0.0
		move_velocity_wu.y = 0.0
	var dt: float = maxf(delta, 0.0)
	if dt <= 0.0:
		return Vector3.ZERO
	var tau: float = combat_inertia_tau_s()
	var a: float = 1.0 - exp(-dt / tau)
	move_velocity_wu = move_velocity_wu.lerp(desired_vel, a)
	if not unlock_y:
		move_velocity_wu.y = 0.0
	return move_velocity_wu * dt

func cap_fraction() -> float:
	if cap_capacity <= 0.0:
		return 1.0
	return cap_current / cap_capacity

func attacks_enabled() -> bool:
	if has_cyno_module():
		return false
	## Cap gate only after capacitor-warfare modules ship (COMBAT §7).
	if not TypedVariant.as_bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		return true
	var frac_need: float = TypedVariant.as_float(DataStore.combat.get("cap_disable_attack_function_pct", 0.10))
	return cap_fraction() >= frac_need

func has_offensive_damage() -> bool:
	return (damage_emp + damage_thermal + damage_kinetic + damage_explosive) > 0.001

func functions_enabled() -> bool:
	return attacks_enabled()

func get_plugin_modules() -> Array:
	return _plugin_modules.duplicate(true)

func add_plugin_module(module_data: Dictionary) -> void:
	_plugin_modules.append(module_data.duplicate(true))
	_recompute_stats_from_modules()

func remove_plugin_module(module_id: Variant) -> bool:
	for i: int in range(_plugin_modules.size()):
		var m: Dictionary = _plugin_modules[i]
		if m.get("id", null) == module_id:
			_plugin_modules.remove_at(i)
			_recompute_stats_from_modules()
			return true
	return false

func _recompute_stats_from_modules() -> void:
	reload_stats()

func total_hp_fraction() -> float:
	var mx: float = max_shield + max_armor + max_structure
	if mx <= 0.0:
		return 1.0
	return clampf((shield_hp + armor_hp + structure_hp) / mx, 0.0, 1.0)

func tick_capacitor(sim_dt: float) -> void:
	if not TypedVariant.as_bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		## Keep display/full for UI; no combat drain/gate until cap warfare exists.
		cap_current = cap_capacity
		return
	if cap_capacity <= 0.0:
		cap_current = 0.0
		return
	var rate: float = cap_capacity / cap_recharge_s
	cap_current = minf(cap_capacity, cap_current + rate * sim_dt)

func consume_cap_for_cycle() -> void:
	if not TypedVariant.as_bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		return
	if cap_capacity <= 0.0:
		return
	var cost: float = cap_cost_per_cycle
	if cost < 0.0:
		cost = cap_capacity * TypedVariant.as_float(DataStore.combat.get("cap_drain_fraction_per_cycle", 0.02))
	cap_current = maxf(0.0, cap_current - cost)

func sync_lock(target: ShipUnit, _sim_time: float) -> void:
	if target == null or target.is_destroyed:
		lock_target_id = 0
		lock_timer = 0.0
		lock_duration_s = 0.0
		return
	var tid: int = target.get_instance_id()
	if lock_target_id != tid:
		lock_target_id = tid
		lock_duration_s = CombatFormulas.lock_time_s(scan_resolution, target.signature_radius)
		## Lead lock already spent on this hull carries over: a finished one fires at once.
		lock_timer = minf(pre_lock_timer, pre_lock_duration_s) if pre_lock_target_id == tid else 0.0
		clear_pre_lock()

func advance_lock(sim_dt: float) -> void:
	if lock_target_id == 0:
		return
	lock_timer += sim_dt

func sync_pre_lock(target: ShipUnit) -> void:
	if target == null or target.is_destroyed or target.get_instance_id() == lock_target_id:
		clear_pre_lock()
		return
	var tid: int = target.get_instance_id()
	if pre_lock_target_id != tid:
		pre_lock_target_id = tid
		pre_lock_timer = 0.0
		pre_lock_duration_s = CombatFormulas.lock_time_s(scan_resolution, target.signature_radius)

func advance_pre_lock(sim_dt: float) -> void:
	if pre_lock_target_id == 0:
		return
	var t: ShipUnit = instance_from_id(pre_lock_target_id) as ShipUnit
	if t == null or not is_instance_valid(t) or t.is_destroyed:
		clear_pre_lock()
		return
	pre_lock_timer += sim_dt

func clear_pre_lock() -> void:
	pre_lock_target_id = 0
	pre_lock_timer = 0.0
	pre_lock_duration_s = 0.0

func is_target_locked() -> bool:
	if lock_target_id == 0:
		return false
	return lock_timer >= lock_duration_s

func grid_dist_to(other: Node3D) -> float:
	return CombatFormulas.grid_distance_cells(self, other)

func is_missile_weapon() -> bool:
	return resolve_weapon_fx_kind() == "missile"

func turret_hit_chance_vs(target: ShipUnit, distance_cells: float) -> float:
	return CombatFormulas.turret_hit_chance(
		get_stat("tracking", tracking),
		get_stat("optimal", optimal_cells),
		get_stat("falloff", falloff_cells),
		optimal_sig_radius,
		target.get_stat("speed", target.base_speed),
		target.get_stat("signature_radius", target.signature_radius),
		distance_cells
	)

func missile_damage_factor_vs(target: ShipUnit) -> float:
	return CombatFormulas.missile_damage_factor(
		target.get_stat("signature_radius", target.signature_radius),
		target.get_stat("speed", target.base_speed),
		get_stat("explosion_radius", explosion_radius),
		get_stat("explosion_velocity", explosion_velocity),
		missile_drf,
		missile_drs
	)

func damage_dict_scaled() -> Dictionary:
	var mul: float = star_dph_mul * (1.0 + damage_pct_bonus / 100.0) * _function_damage_mul
	var raw: Dictionary = {
		"emp": damage_emp * mul,
		"thermal": damage_thermal * mul,
		"kinetic": damage_kinetic * mul,
		"explosive": damage_explosive * mul,
	}
	return FunctionFit.modify_outgoing_damage(self, raw, 0.0)

func sum_damage_amount(dmg: Dictionary) -> float:
	return TypedVariant.as_float(dmg.get("emp", 0.0)) + TypedVariant.as_float(dmg.get("thermal", 0.0)) + TypedVariant.as_float(dmg.get("kinetic", 0.0)) + TypedVariant.as_float(dmg.get("explosive", 0.0))

func heal_dict_scaled() -> Dictionary:
	# FAX heavy repair drones use fixed per-cycle values from content (no global x2 logistic multiplier).
	var mul: float = fetter_repair_mul
	if str(unmanned_kind) != "heavy_repair_drone":
		mul *= TypedVariant.as_float(DataStore.combat.get("logistic_heal_multiplier", 1.0))
	var amounts: Dictionary = {
		"shield": repair_shield * mul,
		"armor": repair_armor * mul,
		"structure": repair_structure * mul,
	}
	return FunctionFit.scale_heal_amounts(self, amounts)

func needs_heal_for_race(logi_race: String) -> bool:
	match logi_race.to_lower():
		"amarr":
			return armor_hp < max_armor
		"caldari":
			return shield_hp < max_shield
		"gallente":
			return structure_hp < max_structure
		"minmatar":
			return shield_hp < max_shield or armor_hp < max_armor
		_:
			return shield_hp < max_shield or armor_hp < max_armor or structure_hp < max_structure

func needs_heal_for_logistic() -> bool:
	return needs_heal_for_race(race)

func is_heal_full_for_race(source_race: String) -> bool:
	return not needs_heal_for_race(source_race)

func update_retreat(sim_time: float) -> void:
	## Only logistics may enter armor-retreat mode.
	if not is_logistic:
		return
	if max_armor <= 0.0:
		return
	if armor_hp <= max_armor / 3.0:
		var min_s: float = TypedVariant.as_float(DataStore.combat.get("retreat_mode_min_s", 60.0))
		retreat_until_time = maxf(retreat_until_time, sim_time + min_s)

func in_retreat(sim_time: float) -> bool:
	return retreat_until_time > sim_time

func world_range() -> float:
	if unlimited_weapon_range:
		return 9999.0
	return attack_range * TypedVariant.as_float(DataStore.combat.get("weapon_range_scale", 3.0))

func world_range_cells() -> float:
	if unlimited_weapon_range:
		return 9999.0
	return attack_range

func has_cyno_module() -> bool:
	for entry: Variant in _function_fit:
		var def: Dictionary = TypedVariant.as_dict(TypedVariant.as_dict(entry).get("def", {}))
		if FunctionFit.is_cyno_def(def):
			return true
	for m: Variant in _plugin_modules:
		if str(TypedVariant.as_dict(m).get("kind", "")) == "cyno":
			return true
	return capital_role == "covert_cyno"

func cyno_duration_s() -> float:
	for m: Variant in _plugin_modules:
		var md: Dictionary = TypedVariant.as_dict(m)
		if str(md.get("kind", "")) == "cyno":
			return TypedVariant.as_float(md.get("duration_s", 90.0))
	return 90.0

func world_range_wu() -> float:
	return world_range()

func apply_fetter_mods(shield_mul: float, armor_mul: float, repair_mul: float, speed_mul: float) -> void:
	## Combat reads `_shield_resist` / `_armor_resist` / `_structure_resist` in apply_hit_dict —
	## the EMP-only scalars are display leftovers and must stay in sync.
	fetter_repair_mul = repair_mul
	fetter_speed_mul = speed_mul
	_apply_resist_mul(_shield_resist, _base_shield_resist, shield_mul)
	_apply_resist_mul(_armor_resist, _base_armor_resist, armor_mul)
	_apply_resist_mul(_structure_resist, _base_structure_resist, armor_mul)
	shield_resist_emp = TypedVariant.as_float(_shield_resist.get("emp", 0.0))
	armor_resist_emp = TypedVariant.as_float(_armor_resist.get("emp", 0.0))
	structure_resist_emp = TypedVariant.as_float(_structure_resist.get("emp", 0.0))


func _apply_resist_mul(dst: Dictionary, base: Dictionary, mul: float) -> void:
	dst.clear()
	for key: Variant in ["emp", "thermal", "kinetic", "explosive"]:
		dst[key] = minf(0.90, TypedVariant.as_float(base.get(key, 0.0)) * mul)

func upgrade_level() -> void:
	if star < 3:
		star += 1
		reload_stats()

func get_cost() -> int:
	return TypedVariant.as_int(DataStore.get_ship(ship_id).get("cost", 0))

func get_sell_price() -> int:
	## Sell = purchase cost − discount, floor min (economy.json).
	var eco: Dictionary = DataStore.economy if DataStore else {}
	var discount: int = TypedVariant.as_int(eco.get("sell_price_discount", 3))
	var floor_p: int = TypedVariant.as_int(eco.get("sell_price_min", 1))
	return maxi(floor_p, get_cost() - discount)

## World-space muzzle from current turret hardpoint (stable across FX retarget ticks).
## Bound to the drawn mesh, not the logic root (COMBAT §3.2).
func get_muzzle_global() -> Vector3:
	if _muzzle_locals.is_empty():
		return visual_to_global(_muzzle_local)
	return visual_to_global(_muzzle_locals[_muzzle_fire_i % _muzzle_locals.size()])

## Advance to next turret after a shot (multi-gun volley).
func advance_muzzle() -> void:
	if _muzzle_locals.size() <= 1:
		return
	_muzzle_fire_i = (_muzzle_fire_i + 1) % _muzzle_locals.size()

func get_muzzle_locals() -> Array[Vector3]:
	if _muzzle_locals.is_empty():
		return [_muzzle_local] as Array[Vector3]
	return _muzzle_locals

func _turret_slot_count() -> int:
	var sd: Dictionary = DataStore.get_ship(ship_id) if DataStore else {}
	var slots: int = TypedVariant.as_int(sd.get("attack_weapon_slots", 0))
	if slots <= 0:
		slots = TypedVariant.as_int(sd.get("hi_slots", 0))
	if slots <= 0:
		slots = 2
	return clampi(slots, 1, 8)

## turret_anchors.json per model_key (SOF locatorTurrets full copy).
static var _turret_docs: Dictionary = {}

static func _turret_doc_for(key: String) -> Dictionary:
	if key == "":
		return {}
	if _turret_docs.has(key):
		return _turret_docs[key]
	var doc: Dictionary = {}
	## Open directly: mounted PCK JSON is readable even where file_exists() can miss it.
	var file: FileAccess = FileAccess.open("res://assets/models/ships/%s/turret_anchors.json" % key, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			doc = parsed
	_turret_docs[key] = doc
	return doc

func _resolve_turret_locals(root: Node3D, aabb: AABB) -> void:
	_muzzle_locals.clear()
	_muzzle_fire_i = 0
	var key: String = str(DataStore.get_ship(ship_id).get("model_key", "")) if DataStore else ""
	if key != "":
		var doc: Dictionary = _turret_doc_for(key)
		if not doc.is_empty():
			## Formal: SOF-native items + hull_aabb (same Z-flip map as engine_boosters).
			var mapped: Array = _map_sof_turret_items_named(doc, aabb)
			_muzzle_locals = _select_firing_muzzle_locals(mapped)
			## Legacy baked mesh-local list (pre-SOF sidecar).
			if _muzzle_locals.is_empty():
				var arr: Variant = doc.get("anchors_mesh_local", [])
				if typeof(arr) == TYPE_ARRAY:
					for item: Variant in TypedVariant.as_array(arr):
						if typeof(item) != TYPE_ARRAY and typeof(item) != TYPE_PACKED_FLOAT32_ARRAY and typeof(item) != TYPE_PACKED_FLOAT64_ARRAY:
							continue
						var a: Array = TypedVariant.as_array(item)
						if a.size() < 3:
							continue
						_muzzle_locals.append(root.transform * Vector3(TypedVariant.as_float(a[0]), TypedVariant.as_float(a[1]), TypedVariant.as_float(a[2])))
	if _muzzle_locals.is_empty():
		_muzzle_locals = _sample_turret_locals_from_mesh(root, aabb, _turret_slot_count())
	if _muzzle_locals.is_empty():
		var mid_y: float = maxf(aabb.get_center().y, aabb.size.y * 0.35)
		_muzzle_locals.append(Vector3(0.0, mid_y, aabb.position.z))
	_muzzle_local = _muzzle_locals[0]

## Map turret_anchors.json SOF pos → named ShipUnit-local rows.
func _map_sof_turret_items_named(doc: Dictionary, mesh_aabb: AABB) -> Array:
	var out: Array = []
	var items: Variant = doc.get("items", [])
	if typeof(items) != TYPE_ARRAY or TypedVariant.as_array(items).is_empty():
		return out
	if mesh_aabb.size.x < 1e-4 or mesh_aabb.size.y < 1e-4 or mesh_aabb.size.z < 1e-4:
		return out
	var sof_aabb: AABB = _sof_hull_aabb(doc)
	if sof_aabb.size.x < 1e-4 or sof_aabb.size.y < 1e-4 or sof_aabb.size.z < 1e-4:
		return out
	for item: Variant in TypedVariant.as_array(items):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = TypedVariant.as_dict(item)
		var pos_v: Variant = d.get("pos", null)
		if typeof(pos_v) != TYPE_ARRAY and typeof(pos_v) != TYPE_PACKED_FLOAT32_ARRAY and typeof(pos_v) != TYPE_PACKED_FLOAT64_ARRAY:
			continue
		var a: Array = TypedVariant.as_array(pos_v)
		if a.size() < 3:
			continue
		var sof_p: Vector3 = Vector3(TypedVariant.as_float(a[0]), TypedVariant.as_float(a[1]), TypedVariant.as_float(a[2]))
		var nx: float = clampf((sof_p.x - sof_aabb.position.x) / sof_aabb.size.x, -0.05, 1.05)
		var ny: float = clampf((sof_p.y - sof_aabb.position.y) / sof_aabb.size.y, -0.05, 1.05)
		var nz: float = clampf((sof_p.z - sof_aabb.position.z) / sof_aabb.size.z, -0.05, 1.05)
		## Flip length: SOF min-Z aft → Godot max-Z aft (same as engine nozzles).
		var local_p: Vector3 = Vector3(
			mesh_aabb.position.x + nx * mesh_aabb.size.x,
			mesh_aabb.position.y + ny * mesh_aabb.size.y,
			mesh_aabb.position.z + (1.0 - nz) * mesh_aabb.size.z
		)
		out.append({"name": str(d.get("name", "")), "pos": local_p})
	return out


## COMBAT §8: pick real gun/launcher hardpoints for fire FX (not every SOF locator).
func _select_firing_muzzle_locals(mapped: Array) -> Array[Vector3]:
	var empty: Array[Vector3] = []
	if mapped.is_empty():
		return empty
	var fx: String = resolve_weapon_fx_kind().to_lower()
	var prefs: Array[String] = []
	if fx == "missile":
		prefs = ["locator_launcher", "locator_xl", "locator_turretm", "locator_turret"]
	else:
		## Laser / rail / cannon / heal: dorsal turret mounts; avoid belly *b and XL unless needed.
		prefs = ["locator_turret", "locator_turretm", "locator_launcher", "locator_xl"]
	var pool: Array = []
	for prefix: String in prefs:
		pool.clear()
		for row_v: Variant in mapped:
			var row: Dictionary = TypedVariant.as_dict(row_v)
			var n: String = str(row.get("name", "")).to_lower()
			if n.find(prefix) >= 0:
				pool.append(row)
		if not pool.is_empty():
			break
	if pool.is_empty():
		pool = mapped.duplicate()
	## Same-slot pairs are `…1a` / `…1b`; prefer dorsal `*a` when any exist.
	var dorsal: Array = []
	for row_v2: Variant in pool:
		var row2: Dictionary = TypedVariant.as_dict(row_v2)
		var n2: String = str(row2.get("name", "")).to_lower()
		if n2.ends_with("a"):
			dorsal.append(row2)
	if not dorsal.is_empty():
		pool = dorsal
	## Bow-most first (min Z), then higher deck (max Y).
	pool.sort_custom(func(a: Variant, b: Variant) -> bool:
		var pa: Vector3 = TypedVariant.as_vector3(TypedVariant.as_dict(a).get("pos", Vector3.ZERO))
		var pb: Vector3 = TypedVariant.as_vector3(TypedVariant.as_dict(b).get("pos", Vector3.ZERO))
		if absf(pa.z - pb.z) > 0.001:
			return pa.z < pb.z
		return pa.y > pb.y
	)
	var want: int = _turret_slot_count()
	var out: Array[Vector3] = []
	for i: int in range(mini(want, pool.size())):
		out.append(TypedVariant.as_vector3(TypedVariant.as_dict(pool[i]).get("pos", Vector3.ZERO)))
	return out


## Legacy helper — full SOF map without fire selection (unused by resolve path).
func _map_sof_turret_items(doc: Dictionary, mesh_aabb: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for row_v: Variant in _map_sof_turret_items_named(doc, mesh_aabb):
		out.append(TypedVariant.as_vector3(TypedVariant.as_dict(row_v).get("pos", Vector3.ZERO)))
	return out

func _sample_turret_locals_from_mesh(root: Node3D, aabb: AABB, want: int) -> Array[Vector3]:
	## Prefer authored hardpoints JSON; else sample upper-forward hull verts as turret decks.
	var pts: Array[Vector3] = []
	for mi: MeshInstance3D in _find_meshes(root):
		if mi.mesh == null:
			continue
		var xf: Transform3D
		if is_inside_tree():
			xf = global_transform.affine_inverse() * mi.global_transform
		else:
			xf = root.transform * _xform_to_ancestor(root, mi)
		for s: int in range(mi.mesh.get_surface_count()):
			var arr: Array = mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var step: int = maxi(1, int(verts.size() / 500.0))
			var i: int = 0
			while i < verts.size():
				pts.append(xf * verts[i])
				i += step
	var mid_y: float = maxf(aabb.get_center().y, aabb.size.y * 0.35)
	var bow_z: float = aabb.position.z
	var z_cut: float = bow_z + aabb.size.z * 0.55  # forward 55% (bow = min Z)
	var y_cut: float = aabb.position.y + aabb.size.y * 0.45
	var deck: Array[Vector3] = []
	for p: Variant in pts:
		if p.z <= z_cut and p.y >= y_cut:
			deck.append(p)
	if deck.size() < 8:
		## Soften filters if mesh is sparse / flat.
		for p: Variant in pts:
			if p.z <= bow_z + aabb.size.z * 0.7:
				deck.append(p)
	var out: Array[Vector3] = []
	if deck.size() < 4:
		## Symmetric gunwales along forward length.
		var n: int = maxi(1, want)
		for i: int in range(n):
			var t: float = (float(i) + 0.5) / float(n)
			var z: float = bow_z + aabb.size.z * 0.08 + aabb.size.z * 0.42 * t
			var x_off: float = aabb.size.x * 0.32
			if n == 1:
				out.append(Vector3(0.0, mid_y, z))
			elif i % 2 == 0:
				out.append(Vector3(-x_off, mid_y, z))
			else:
				out.append(Vector3(x_off, mid_y, z))
		return out
	## Cluster deck verts by X then Z into `want` hardpoints.
	deck.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	var groups: Array = []
	var per: int = maxi(1, int(ceili(float(deck.size()) / float(maxi(want, 1)))))
	var g: Array[Vector3] = []
	for p: Variant in deck:
		g.append(p)
		if g.size() >= per and groups.size() + 1 < want:
			groups.append(g.duplicate())
			g.clear()
	if not g.is_empty():
		groups.append(g)
	while groups.size() > want:
		groups.pop_back()
	for grp: Variant in groups:
		var sx: float = 0.0
		var sy: float = 0.0
		var sz: float = 0.0
		var cn: Array = grp
		for p2: Variant in cn:
			var v: Vector3 = p2
			sx += v.x
			sy += v.y
			sz += v.z
		var n2: float = maxf(1.0, float(cn.size()))
		out.append(Vector3(sx / n2, maxf(sy / n2, mid_y * 0.85), sz / n2))
	if out.is_empty():
		out.append(Vector3(0.0, mid_y, bow_z))
	## Prefer bow-most first so opening shot reads as forward battery.
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	return out

## Engine nozzles: formal path engine_boosters.json (SOF); single AABB stern fallback.
## World sample is mesh-bound (same as muzzle) so trails stick under soft-follow.
func get_engine_global() -> Vector3:
	return visual_to_global(_engine_local)

func get_engine_local() -> Vector3:
	return _engine_local

func get_engine_locals() -> Array[Vector3]:
	if _engine_locals.is_empty():
		return [_engine_local] as Array[Vector3]
	return _engine_locals

func get_engine_outlines() -> Array:
	return _engine_outlines

func get_model_display_size() -> float:
	if _model_display_size > 0.0:
		return _model_display_size
	return TypedVariant.as_float(DataStore.visual.get("ship_target_size", 2.4)) if DataStore else 2.4


## Soft collision sphere radius in world units (scales with on-field display size).
func collision_radius_wu() -> float:
	var frac: float = 0.26
	var rmin: float = 0.32
	var rmax: float = 0.95
	var umul: float = 0.5
	var fallback: float = 0.5
	if DataStore != null and DataStore.combat:
		frac = TypedVariant.as_float(DataStore.combat.get("collision_radius_display_frac", frac))
		rmin = TypedVariant.as_float(DataStore.combat.get("collision_radius_min_wu", rmin))
		rmax = TypedVariant.as_float(DataStore.combat.get("collision_radius_max_wu", rmax))
		umul = TypedVariant.as_float(DataStore.combat.get("collision_unmanned_mul", umul))
		fallback = TypedVariant.as_float(DataStore.combat.get("agent_radius", fallback))
	var disp: float = get_model_display_size()
	if disp <= 0.05:
		return fallback
	var r: float = disp * frac
	if is_unmanned:
		r *= umul
	return clampf(r, rmin, rmax)

func _resolve_engine_local(root: Node3D, aabb: AABB) -> void:
	## Formal: engine_boosters.json mapped SOF→mesh AABB. Fallback: one stern point.
	_engine_locals.clear()
	_engine_outlines.clear()
	_load_engine_boosters(root, aabb)
	if _engine_locals.is_empty():
		var mid_y: float = maxf(aabb.get_center().y, aabb.size.y * 0.25)
		var z_aft: float = aabb.position.z + aabb.size.z
		var p: Vector3 = Vector3(0.0, mid_y, z_aft)
		_engine_locals.append(p)
		_engine_outlines.append(_circle_outline(p, maxf(aabb.size.x * 0.06, 0.05)))
	_engine_local = _engine_locals[0]

## engine_boosters.json per model_key, parsed once per run.
static var _booster_docs: Dictionary = {}

static func _booster_doc_for(key: String) -> Dictionary:
	if key == "":
		return {}
	if _booster_docs.has(key):
		return _booster_docs[key]
	var doc: Dictionary = {}
	## Open directly: mounted PCK JSON is readable even where file_exists() can miss it.
	var file: FileAccess = FileAccess.open("res://assets/models/ships/%s/engine_boosters.json" % key, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			doc = parsed
	_booster_docs[key] = doc
	return doc

## Offline nozzle→bow solve (`tools/fit_bow_yaw_from_nozzles.py`); empty when the
## pack still relies on the global yaw + SOF AABB mapping.
func _bow_fit() -> Dictionary:
	var key: String = str(DataStore.get_ship(ship_id).get("model_key", "")) if DataStore else ""
	var fit_v: Variant = _booster_doc_for(key).get("bow_fit", null)
	return TypedVariant.as_dict(fit_v) if typeof(fit_v) == TYPE_DICTIONARY else {}

## True when the pack carries the offline nozzle→bow solve, i.e. heading and nozzles are
## measured per hull. Callers must not add their own bow flip or nozzle mirror on top.
func has_baked_bow_fit() -> bool:
	return not _bow_fit().is_empty()

func _load_engine_boosters(_root: Node3D, mesh_aabb: AABB) -> void:
	## Map SOF-native nozzle pos into live mesh AABB (Echoes GLB ≠ TQ mesh space).
	## SOF aft ≈ min Z; Godot ship aft ≈ max Z → flip normalized Z.
	var key: String = str(DataStore.get_ship(ship_id).get("model_key", "")) if DataStore else ""
	if key == "":
		return
	var doc: Dictionary = _booster_doc_for(key)
	if doc.is_empty():
		return
	var items: Variant = doc.get("items", [])
	if typeof(items) != TYPE_ARRAY or TypedVariant.as_array(items).is_empty():
		return
	if mesh_aabb.size.x < 1e-4 or mesh_aabb.size.y < 1e-4 or mesh_aabb.size.z < 1e-4:
		return
	## TQ-converted GLBs swap axes, so their nozzles are pre-solved against the
	## real mesh and only need the live post-yaw AABB.
	if _load_baked_nozzles(mesh_aabb):
		_sort_nozzles_aft_first()
		return
	var sof_aabb: AABB = _sof_hull_aabb(doc)
	if sof_aabb.size.x < 1e-4 or sof_aabb.size.y < 1e-4 or sof_aabb.size.z < 1e-4:
		return
	var scale_r: float = (
		mesh_aabb.size.x / sof_aabb.size.x
		+ mesh_aabb.size.y / sof_aabb.size.y
		+ mesh_aabb.size.z / sof_aabb.size.z
	) / 3.0
	## Prefer SOF `has_trail` nozzles. TQ drones often flag all boosters `has_trail:false`
	## (always_on glow only) — still pin game trails to those real nozzle transforms.
	var preferred: Array = []
	var all_valid: Array = []
	for item: Variant in TypedVariant.as_array(items):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = TypedVariant.as_dict(item)
		var pos_v: Variant = d.get("pos", null)
		if typeof(pos_v) != TYPE_ARRAY and typeof(pos_v) != TYPE_PACKED_FLOAT32_ARRAY and typeof(pos_v) != TYPE_PACKED_FLOAT64_ARRAY:
			continue
		var a0: Array = TypedVariant.as_array(pos_v)
		if a0.size() < 3:
			continue
		all_valid.append(d)
		if d.get("has_trail", true) != false:
			preferred.append(d)
	var use_items: Array = preferred if not preferred.is_empty() else all_valid
	for d_any: Variant in use_items:
		var d: Dictionary = TypedVariant.as_dict(d_any)
		var a: Array = TypedVariant.as_array(d.get("pos"))
		var sof_p: Vector3 = Vector3(TypedVariant.as_float(a[0]), TypedVariant.as_float(a[1]), TypedVariant.as_float(a[2]))
		var nx: float = (sof_p.x - sof_aabb.position.x) / sof_aabb.size.x
		var ny: float = (sof_p.y - sof_aabb.position.y) / sof_aabb.size.y
		var nz: float = (sof_p.z - sof_aabb.position.z) / sof_aabb.size.z
		nx = clampf(nx, -0.05, 1.05)
		ny = clampf(ny, -0.05, 1.05)
		nz = clampf(nz, -0.05, 1.05)
		## Flip length: SOF min-Z aft → Godot max-Z aft.
		var ship_p: Vector3 = Vector3(
			mesh_aabb.position.x + nx * mesh_aabb.size.x,
			mesh_aabb.position.y + ny * mesh_aabb.size.y,
			mesh_aabb.position.z + (1.0 - nz) * mesh_aabb.size.z
		)
		var rad: float = TypedVariant.as_float(d.get("radius", 0.08)) * scale_r
		_engine_locals.append(ship_p)
		_engine_outlines.append(_circle_outline(ship_p, maxf(rad, mesh_aabb.size.x * 0.02)))
	_sort_nozzles_aft_first()

## Nozzle positions solved offline against the GLB itself, stored 0..1 inside the
## post-yaw mesh AABB — the live AABB already carries scale and recentre.
func _load_baked_nozzles(mesh_aabb: AABB) -> bool:
	var fit: Dictionary = _bow_fit()
	var norms_v: Variant = fit.get("nozzles_ship_norm", null)
	if typeof(norms_v) != TYPE_ARRAY or TypedVariant.as_array(norms_v).is_empty():
		return false
	var norms: Array = TypedVariant.as_array(norms_v)
	var radii: Array = TypedVariant.as_array(fit.get("nozzle_radius_norm", []))
	var longest: float = maxf(mesh_aabb.size.x, maxf(mesh_aabb.size.y, mesh_aabb.size.z))
	for i: int in range(norms.size()):
		if typeof(norms[i]) != TYPE_ARRAY or TypedVariant.as_array(norms[i]).size() < 3:
			continue
		var n: Array = TypedVariant.as_array(norms[i])
		var p: Vector3 = Vector3(
			mesh_aabb.position.x + clampf(TypedVariant.as_float(n[0]), -0.05, 1.05) * mesh_aabb.size.x,
			mesh_aabb.position.y + clampf(TypedVariant.as_float(n[1]), -0.05, 1.05) * mesh_aabb.size.y,
			mesh_aabb.position.z + clampf(TypedVariant.as_float(n[2]), -0.05, 1.05) * mesh_aabb.size.z
		)
		var rad: float = (TypedVariant.as_float(radii[i]) * longest) if i < radii.size() else 0.0
		_engine_locals.append(p)
		_engine_outlines.append(_circle_outline(p, maxf(rad, mesh_aabb.size.x * 0.02)))
	return not _engine_locals.is_empty()

func _sort_nozzles_aft_first() -> void:
	if _engine_locals.is_empty():
		return
	var order: Array[int] = []
	for i: int in range(_engine_locals.size()):
		order.append(i)
	order.sort_custom(func(ia: int, ib: int) -> bool: return _engine_locals[ia].z > _engine_locals[ib].z)
	var locs: Array[Vector3] = []
	var outs: Array = []
	for i: int in order:
		locs.append(_engine_locals[i])
		outs.append(_engine_outlines[i])
	_engine_locals = locs
	_engine_outlines = outs
	_engine_local = _engine_locals[0]


## TitanBerth `BOW_FLIP` (MULTIPLAYER_PVP §2.4a): unit yaw π swaps which length end
## faces the enemy, but SOF nozzles stay at ship-local +Z (“aft”). After the flip that
## +Z end is the visual bow — remirror on Z so trails stick to the stern (same end as
## tonnage badge / stern_top_point). Skip when pack has baked bow_fit (already coherent).
func compensate_bow_flip_for_engines() -> void:
	if has_baked_bow_fit():
		return
	if _engine_locals.is_empty():
		return
	if _model_root == null or not is_instance_valid(_model_root):
		return
	var aabb: AABB = _aabb_in_ship_space(_model_root)
	if aabb.size.z < 1e-4:
		return
	var cz: float = aabb.get_center().z
	for i: int in range(_engine_locals.size()):
		var p: Vector3 = _engine_locals[i]
		p.z = 2.0 * cz - p.z
		_engine_locals[i] = p
	for i: int in range(_engine_outlines.size()):
		var outline_v: Variant = _engine_outlines[i]
		if typeof(outline_v) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		@warning_ignore("unsafe_cast")
		var outline: PackedVector3Array = outline_v as PackedVector3Array
		var flipped: PackedVector3Array = PackedVector3Array()
		for q: Vector3 in outline:
			flipped.append(Vector3(q.x, q.y, 2.0 * cz - q.z))
		_engine_outlines[i] = flipped
	## After remirror, visual stern is at local −Z; sort so primary emit is stern-most.
	var order: Array[int] = []
	for i: int in range(_engine_locals.size()):
		order.append(i)
	order.sort_custom(func(ia: int, ib: int) -> bool: return _engine_locals[ia].z < _engine_locals[ib].z)
	var locs: Array[Vector3] = []
	var outs: Array = []
	for i: int in order:
		locs.append(_engine_locals[i])
		outs.append(_engine_outlines[i])
	_engine_locals = locs
	_engine_outlines = outs
	_engine_local = _engine_locals[0]

func _sof_hull_aabb(doc: Dictionary) -> AABB:
	var hb: Variant = doc.get("hull_aabb", null)
	if typeof(hb) == TYPE_DICTIONARY:
		var hbd: Dictionary = TypedVariant.as_dict(hb)
		var pos_v: Variant = hbd.get("position", null)
		var size_v: Variant = hbd.get("size", null)
		if typeof(pos_v) == TYPE_ARRAY and typeof(size_v) == TYPE_ARRAY:
			var pa: Array = TypedVariant.as_array(pos_v)
			var sa: Array = TypedVariant.as_array(size_v)
			if pa.size() >= 3 and sa.size() >= 3:
				return AABB(
					Vector3(TypedVariant.as_float(pa[0]), TypedVariant.as_float(pa[1]), TypedVariant.as_float(pa[2])),
					Vector3(TypedVariant.as_float(sa[0]), TypedVariant.as_float(sa[1]), TypedVariant.as_float(sa[2]))
				)
	## Derive from item positions if hull_aabb missing.
	var items: Variant = doc.get("items", [])
	if typeof(items) != TYPE_ARRAY or TypedVariant.as_array(items).is_empty():
		return AABB()
	var first: bool = true
	var mn: Vector3 = Vector3.ZERO
	var mx: Vector3 = Vector3.ZERO
	for item: Variant in TypedVariant.as_array(items):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var pos_v2: Variant = TypedVariant.as_dict(item).get("pos", null)
		if typeof(pos_v2) != TYPE_ARRAY:
			continue
		var a2: Array = TypedVariant.as_array(pos_v2)
		if a2.size() < 3:
			continue
		var p: Vector3 = Vector3(TypedVariant.as_float(a2[0]), TypedVariant.as_float(a2[1]), TypedVariant.as_float(a2[2]))
		if first:
			mn = p
			mx = p
			first = false
		else:
			mn = mn.min(p)
			mx = mx.max(p)
	if first:
		return AABB()
	var size: Vector3 = mx - mn
	## Pad stern cluster toward bow (SOF +Z).
	var pad: float = maxf(size.x, maxf(size.y, 1.0)) * 0.5
	mn.x -= pad
	mx.x += pad
	mn.y -= pad
	mx.y += pad
	mx.z += maxf(size.z * 2.5, pad * 2.0)
	return AABB(mn, mx - mn)

func _circle_outline(center: Vector3, radius: float, sides: int = 10) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var r: float = maxf(radius, 0.01)
	for k: int in range(sides):
		var ang: float = TAU * float(k) / float(sides)
		out.append(center + Vector3(cos(ang) * r, sin(ang) * r, 0.0))
	return out

func resolve_weapon_fx_kind() -> String:
	## Prefer ships/<id>.json weapon_fx. Do NOT infer from hull ship_groups (EVEmu stores
	## weapon family on modules, not hull). Logistics → heal; else default_kind.
	var cfg: Dictionary = DataStore.weapon_fx
	var ship: Dictionary = DataStore.get_ship(ship_id)
	var explicit: String = str(ship.get("weapon_fx", "")).strip_edges()
	if explicit != "":
		return explicit
	## Override without weapon_fx: use base kind for SFX / kind string.
	var ov: Dictionary = TypedVariant.as_dict(ship.get("weapon_fx_override", {}))
	var ov_base: String = str(ov.get("base", "")).strip_edges()
	if ov_base != "":
		return ov_base
	if is_logistic:
		return "heal"
	return str(cfg.get("default_kind", "laser"))


## Full interaction FX def (stock + optional interaction_fx_override). COMBAT §8.4.
func resolve_interaction_fx_def() -> Dictionary:
	return InteractionFxResolve.from_unit_data(DataStore.get_ship(ship_id))


## Ship/unmanned engine trail appearance override (MOD_PROTOCOL §1.2.0c). Empty = global visual.json.
func resolve_trail_override() -> Dictionary:
	return TypedVariant.as_dict(DataStore.get_ship(ship_id).get("trail_override", {}))


## Full kind def for FiringFx (stock + optional weapon_fx_override). COMBAT §8.2a.
func resolve_weapon_fx_def() -> Dictionary:
	var ship: Dictionary = DataStore.get_ship(ship_id)
	var kinds: Dictionary = TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {}))
	var ov: Dictionary = TypedVariant.as_dict(ship.get("weapon_fx_override", {}))
	if not ov.is_empty():
		var merged: Dictionary = ModFxResolve.merge_override(ov, kinds)
		if not merged.is_empty():
			return merged
	var kind: String = resolve_weapon_fx_kind()
	return TypedVariant.as_dict(kinds.get(kind, kinds.get("laser", {}))).duplicate(true)

func apply_hit(raw_emp: float, raw_thermal: float = 0.0, raw_kinetic: float = 0.0, raw_explosive: float = 0.0) -> Dictionary:
	## Returns {destroyed:bool, dealt:float}. Layer overflow pierces shield→armor→structure when combat flag is on.
	var dmg: Dictionary = {
		"emp": raw_emp,
		"thermal": raw_thermal,
		"kinetic": raw_kinetic,
		"explosive": raw_explosive,
	}
	return apply_hit_dict(dmg)

## `lethal` off = SEMI_ASYNC §3.1a guest estimate: paint the bar, never kill and
## never touch authority-owned bookkeeping (first-damage hooks, capital HP drain).
func apply_hit_dict(dmg: Dictionary, lethal: bool = true) -> Dictionary:
	## COMBAT §6: per-layer resists, pierce recalculates with next-layer resists; no min_damage_pct floor.
	if is_destroyed:
		return {"destroyed": is_destroyed, "dealt": 0.0}
	var total_raw: float = sum_damage_amount(dmg)
	if total_raw <= 0.0:
		return {"destroyed": is_destroyed, "dealt": 0.0}
	if lethal:
		FunctionFit.on_first_damage(self, _combat_sim_time)
	var remaining: Dictionary = {
		"emp": TypedVariant.as_float(dmg.get("emp", 0.0)),
		"thermal": TypedVariant.as_float(dmg.get("thermal", 0.0)),
		"kinetic": TypedVariant.as_float(dmg.get("kinetic", 0.0)),
		"explosive": TypedVariant.as_float(dmg.get("explosive", 0.0)),
	}
	var applied: float = 0.0
	var applied_by_layer: Dictionary = {"shield": 0.0, "armor": 0.0, "structure": 0.0}
	var pierce: bool = TypedVariant.as_bool(DataStore.combat.get("shield_overflow_pierces_armor", true))
	var layers: Array = [
		{"name": "shield", "resist": _shield_resist},
		{"name": "armor", "resist": _armor_resist},
		{"name": "structure", "resist": _structure_resist},
	]
	for layer_info: Variant in layers:
		if sum_damage_amount(remaining) <= 0.0:
			break
		var lname: String = layer_info["name"]
		var layer_hp: float = 0.0
		if lname == "shield":
			layer_hp = shield_hp
		elif lname == "armor":
			layer_hp = armor_hp
		else:
			layer_hp = structure_hp
		if layer_hp <= 0.0:
			continue
		var resist_map: Dictionary = layer_info["resist"]
		var dealt: float = 0.0
		for key: Variant in ["emp", "thermal", "kinetic", "explosive"]:
			var raw_i: float = TypedVariant.as_float(remaining.get(key, 0.0))
			if raw_i <= 0.0:
				continue
			var base_resist: float = clampf(TypedVariant.as_float(resist_map.get(key, 0.0)), 0.0, 0.95)
			var resist: float = layer_resist(lname, str(key), base_resist)
			dealt += raw_i * (1.0 - resist)
		if dealt <= 0.0:
			break
		if dealt <= layer_hp:
			if lname == "shield":
				shield_hp -= dealt
			elif lname == "armor":
				armor_hp -= dealt
			else:
				structure_hp -= dealt
			applied += dealt
			applied_by_layer[lname] = TypedVariant.as_float(applied_by_layer.get(lname, 0.0)) + dealt
			remaining = {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}
			break
		## Layer breaks: absorb full HP, scale remaining raw by unabsorbed fraction.
		var frac_absorbed: float = layer_hp / dealt
		if lname == "shield":
			shield_hp = 0.0
		elif lname == "armor":
			armor_hp = 0.0
		else:
			## Overkill structure: subtract full dealt so HP goes ≤0 (destroy check).
			structure_hp -= dealt
		applied += layer_hp
		applied_by_layer[lname] = TypedVariant.as_float(applied_by_layer.get(lname, 0.0)) + layer_hp
		if lname == "structure" or not pierce:
			remaining = {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}
			break
		var keep: float = 1.0 - frac_absorbed
		for key2: Variant in ["emp", "thermal", "kinetic", "explosive"]:
			remaining[key2] = TypedVariant.as_float(remaining.get(key2, 0.0)) * keep
	if lethal and is_capital_flagship() and applied > 0.0:
		var loss_pct: float = TypedVariant.as_float(DataStore.combat.get("capital_max_hp_loss_from_damage_pct", 0.10))
		if loss_pct > 0.0:
			_apply_capital_max_hp_loss_by_layer(applied_by_layer, loss_pct)
	if shield_hp <= 0.0 and armor_hp <= 0.0 and structure_hp <= 0.0:
		if not lethal:
			## Hold one sliver of structure until authority confirms the kill.
			shield_hp = 0.0
			armor_hp = 0.0
			structure_hp = 1.0
			refresh_health_bar()
			return {"destroyed": false, "dealt": applied}
		is_destroyed = true
		## Titan-same explode FX scaled; no wreck for non-titans.
		var parent_n: Node = get_parent()
		if parent_n:
			ShipDeathFx.spawn_explode(parent_n, global_position, ship_id)
		visible = false
		if _health_bar:
			_health_bar.visible = false
		return {"destroyed": true, "dealt": applied}
	if _health_bar:
		_health_bar.call("refresh")
	return {"destroyed": false, "dealt": applied}

## dreadnought / carrier / force_auxiliary only (CAPITAL_AND_CYNO §3.1).
func is_capital_flagship() -> bool:
	if capital_role in ["dreadnought", "carrier", "force_auxiliary"]:
		return true
	var sg: String = str(DataStore.get_ship(ship_id).get("ship_group", "")) if DataStore else ""
	return sg in ["dreadnought", "carrier", "force_auxiliary"]

## Fraction of pristine base already lost to capital max-HP drain (0..1). UI black segment.
func capital_black_frac(layer: String) -> float:
	if not is_capital_flagship():
		return 0.0
	var pristine: float = 0.0
	var now: float = 0.0
	match layer:
		"shield":
			pristine = pristine_base_max_shield
			now = base_max_shield
		"armor":
			pristine = pristine_base_max_armor
			now = base_max_armor
		"structure":
			pristine = pristine_base_max_structure
			now = base_max_structure
		_:
			return 0.0
	if pristine <= 1e-6:
		return 0.0
	return clampf(1.0 - now / pristine, 0.0, 1.0)

## Permanently cut each layer's base_max by (that layer's applied damage × pct).
func _apply_capital_max_hp_loss_by_layer(applied_by_layer: Dictionary, loss_pct: float) -> void:
	if loss_pct <= 0.0:
		return
	var cut_s: float = TypedVariant.as_float(applied_by_layer.get("shield", 0.0)) * loss_pct
	var cut_a: float = TypedVariant.as_float(applied_by_layer.get("armor", 0.0)) * loss_pct
	var cut_st: float = TypedVariant.as_float(applied_by_layer.get("structure", 0.0)) * loss_pct
	if cut_s <= 0.0 and cut_a <= 0.0 and cut_st <= 0.0:
		return
	var mul_s: float = max_shield / base_max_shield if base_max_shield > 1e-6 else 1.0
	var mul_a: float = max_armor / base_max_armor if base_max_armor > 1e-6 else 1.0
	var flat_st: float = max_structure - base_max_structure
	base_max_shield = maxf(0.0, base_max_shield - cut_s)
	base_max_armor = maxf(0.0, base_max_armor - cut_a)
	base_max_structure = maxf(0.0, base_max_structure - cut_st)
	max_shield = base_max_shield * mul_s
	max_armor = base_max_armor * mul_a
	max_structure = maxf(0.0, base_max_structure + flat_st)
	shield_hp = minf(shield_hp, max_shield)
	armor_hp = minf(armor_hp, max_armor)
	structure_hp = minf(structure_hp, max_structure)

func apply_heal(amount: float) -> bool:
	## Legacy flat heal — prefer apply_heal_racial.
	var res: Dictionary = apply_heal_racial("minmatar", {"shield": amount * 0.5, "armor": amount * 0.5, "structure": 0.0})
	return TypedVariant.as_bool(res.get("full", false))

## Returns {applied: float, full: bool}. `applied` is HP that actually entered the
## bars — a layer already at max discards its share (COMBAT §9: 溢出丢弃、不跨层),
## so callers must never report the requested amount as healing.
func apply_heal_received_mul(mul: float, duration_s: float) -> void:
	_heal_received_mul = clampf(mul, 0.0, 1.0)
	_heal_received_mul_until = _combat_sim_time + maxf(0.0, duration_s)


func current_heal_received_mul() -> float:
	if _heal_received_mul_until < 0.0:
		return 1.0
	if _combat_sim_time > _heal_received_mul_until:
		_heal_received_mul = 1.0
		_heal_received_mul_until = -1.0
		return 1.0
	return _heal_received_mul


func apply_heal_racial(source_race: String, amounts: Dictionary) -> Dictionary:
	if is_destroyed:
		return {"applied": 0.0, "full": true}
	var recv: float = current_heal_received_mul()
	var scaled_amounts: Dictionary = amounts.duplicate()
	if recv < 0.999:
		for k: Variant in scaled_amounts.keys():
			scaled_amounts[k] = TypedVariant.as_float(scaled_amounts[k], 0.0) * recv
	var race_key: String = source_race.to_lower()
	var shield_amt: float = 0.0
	var armor_amt: float = 0.0
	var structure_amt: float = 0.0
	match race_key:
		"amarr":
			armor_amt = TypedVariant.as_float(scaled_amounts.get("armor", 0.0))
			if armor_amt <= 0.0:
				armor_amt = TypedVariant.as_float(scaled_amounts.get("shield", 0.0)) + TypedVariant.as_float(scaled_amounts.get("structure", 0.0))
		"caldari":
			shield_amt = TypedVariant.as_float(scaled_amounts.get("shield", 0.0))
			if shield_amt <= 0.0:
				shield_amt = TypedVariant.as_float(scaled_amounts.get("armor", 0.0)) + TypedVariant.as_float(scaled_amounts.get("structure", 0.0))
		"gallente":
			structure_amt = TypedVariant.as_float(scaled_amounts.get("structure", 0.0))
			if structure_amt <= 0.0:
				structure_amt = TypedVariant.as_float(scaled_amounts.get("shield", 0.0)) + TypedVariant.as_float(scaled_amounts.get("armor", 0.0))
		"minmatar":
			var total: float = TypedVariant.as_float(scaled_amounts.get("shield", 0.0)) + TypedVariant.as_float(scaled_amounts.get("armor", 0.0)) + TypedVariant.as_float(scaled_amounts.get("structure", 0.0))
			var hi: int = int(floorf(total))
			var lo: int = int(hi / 2)
			shield_amt = float(lo + hi % 2)
			armor_amt = float(lo)
		_:
			shield_amt = TypedVariant.as_float(scaled_amounts.get("shield", 0.0))
			armor_amt = TypedVariant.as_float(scaled_amounts.get("armor", 0.0))
			structure_amt = TypedVariant.as_float(scaled_amounts.get("structure", 0.0))
	var applied: float = 0.0
	if shield_amt > 0.0 and shield_hp < max_shield:
		var add: float = minf(max_shield - shield_hp, shield_amt)
		shield_hp += add
		applied += add
		_notify_health_bar_gain("shield", add)
	if armor_amt > 0.0 and armor_hp < max_armor:
		var add_a: float = minf(max_armor - armor_hp, armor_amt)
		armor_hp += add_a
		applied += add_a
		_notify_health_bar_gain("armor", add_a)
	if structure_amt > 0.0 and structure_hp < max_structure:
		var add_s: float = minf(max_structure - structure_hp, structure_amt)
		structure_hp += add_s
		applied += add_s
		_notify_health_bar_gain("structure", add_s)
	if _health_bar:
		_health_bar.call("refresh")
	return {"applied": applied, "full": is_heal_full_for_race(race_key)}


func _notify_health_bar_gain(layer: String, amount: float) -> void:
	## Only actual restored HP/cap deltas — callers must pass after-before gain, never cur/max.
	if amount <= 0.5 or _health_bar == null or not is_instance_valid(_health_bar):
		return
	var key: String = str(layer).strip_edges().to_lower()
	if key != "shield" and key != "armor" and key != "structure" and key != "cap" \
			and key != "capacitor" and key != "cap_current" and key != "hull":
		return
	if _health_bar.has_method("notify_layer_gain"):
		_health_bar.call("notify_layer_gain", key, amount)
