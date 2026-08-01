extends Node3D
class_name ShipUnit

const TEAM_PLAYER := 0
const TEAM_AI := 1

var ship_id: int = 0
var star: int = 1
var team_id: int = 0
var slot_type: String = "hangar"  # hangar | field
var grid_x: int = 0
var grid_z: int = 0
var is_destroyed: bool = false
var is_logistic: bool = false
var is_mining_ship: bool = false
## Protected neutral (pve_salvage freighter): nobody targets it, it never counts as a field
## combatant (FREIGHTER_AND_TITAN §1.2.1).
var is_protect_target: bool = false
var is_unmanned: bool = false
var unmanned_kind: String = ""
var drone_bandwidth: float = 0.0
var drone_bay_slots: int = 0  # 发射管 / active drone quota
var _plugin_modules: Array = []
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
var cyno_channel_ends_at: float = -1.0
var cyno_completed: bool = false
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
var tracking: float = 0.0
var optimal_cells: float = 0.0
var falloff_cells: float = 0.0
var optimal_sig_radius: float = 40.0
var explosion_radius: float = 0.0
var explosion_velocity: float = 0.0
var missile_drf: float = 0.0
var missile_drs: float = 1.0
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
var _visual_follow_on: bool = false
var _model_rest_local: Vector3 = Vector3.ZERO
var retreat_until_time: float = -1.0
var no_target_acc: float = 0.0
var _stat_modifiers: Array = []

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _model_root: Node3D
var _health_bar: Node3D  # ShipHealthBar (avoid class_name cycle with ShipUnit)
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
## Combat aim (Variant so null clear is valid).
var combat_target = null
## Combat-entry hull glow remaining (sim seconds); <0 = off.
var _combat_glow_left_s: float = -1.0

const _HEALTH_BAR_SCRIPT := preload("res://scripts/ship/ship_health_bar.gd")
const _ECHOES_SURFACE_SHADER := preload("res://shaders/echoes_spaceobject.gdshader")
const _UNITY_SHIP_SHADER := preload("res://shaders/unity_standard_ship.gdshader")
## Combat entry glow duration in **sim** seconds (scales with 倍速; not FPS / time_scale).
const COMBAT_GLOW_S := 10.0
const _HULL_MORPH_FX := preload("res://scripts/combat/hull_morph_fx.gd")

func setup(p_ship_id: int, p_star: int, p_team: int) -> void:
	ship_id = p_ship_id
	star = p_star
	team_id = p_team
	## Race must be known before mesh tint (otherwise all hulls look Amarr gold).
	var ship_data := DataStore.get_ship(ship_id)
	race = str(ship_data.get("race", "amarr")).to_lower()
	var fs: Dictionary = ship_data.get("function_slots", {})
	_plugin_modules = []
	if typeof(fs) == TYPE_DICTIONARY:
		for m in fs.get("slots", []):
			if typeof(m) == TYPE_DICTIONARY:
				_plugin_modules.append((m as Dictionary).duplicate(true))
	## Stats first so is_unmanned / drone flags are known before mesh/bar.
	reload_stats()
	var sd := DataStore.get_ship(ship_id)
	requires_cyno_entry = bool(sd.get("requires_cyno_entry", false))
	deploy_enemy_half_only = bool(sd.get("deploy_enemy_half_only", false))
	allow_enemy_cell_overlap = bool(sd.get("allow_enemy_cell_overlap", false))
	immobile_in_combat = bool(sd.get("immobile_in_combat", false))
	unlimited_weapon_range = bool(sd.get("unlimited_weapon_range", false))
	capital_role = str(sd.get("capital_role", ""))
	hull_morph = str(sd.get("hull_morph", ""))
	hull_morph_duration_s = float(sd.get("hull_morph_duration_s", 10.0))
	hull_morph_requires_fetter = str(sd.get("hull_morph_requires_fetter", ""))
	hull_morph_playing = false
	hull_morphed = false
	hull_morph_unstacking = false
	if field_side_team < 0:
		field_side_team = team_id
	_ensure_mesh()
	_ensure_health_bar()
	var yaw := float(DataStore.visual.get("player_yaw_deg" if team_id == TEAM_PLAYER else "ai_yaw_deg", 0.0))
	rotation_degrees = Vector3(0, yaw, 0)
	## Soft-follow runs only while Battle has armed it (COMBAT §3.2).
	set_process(false)

## Yaw so local −Z faces flat XZ direction (Godot forward).
func face_dir_xz(dir: Vector3) -> void:
	if (immobile_in_combat and not hull_morph_unstacking) or has_cyno_module():
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	rotation.y = atan2(-flat.x, -flat.z)


func model_root() -> Node3D:
	return _model_root


## Ship-local hardpoints were baked while the mesh sat at `_model_rest_local`.
## Map them through the *current* mesh pose so FX / trails stay glued when soft-follow lags.
func visual_to_global(ship_local: Vector3) -> Vector3:
	if _model_root == null:
		return to_global(ship_local)
	var rest_xf := Transform3D(_model_root.transform.basis, _model_rest_local)
	var model_local := rest_xf.affine_inverse() * ship_local
	return _model_root.to_global(model_local)


func visual_origin_world() -> Vector3:
	return visual_to_global(Vector3.ZERO)


func arm_visual_follow() -> void:
	## Battle only: mesh soft-chases the logic root; prepare / drag stay glued.
	if _model_root != null:
		_model_rest_local = _model_root.position
	_visual_world = global_position
	_visual_follow_on = true
	set_process(true)


func disarm_visual_follow() -> void:
	_visual_follow_on = false
	set_process(false)
	_snap_visual_to_logic()


func _snap_visual_to_logic() -> void:
	_visual_world = global_position
	if _model_root != null:
		_model_root.position = _model_rest_local


func _process(delta: float) -> void:
	if not _visual_follow_on or _model_root == null:
		return
	## Outside combat someone may teleport the root (cyno land / board move): re-glue
	## instead of dragging the mesh across the map.
	var err := global_position - _visual_world
	var snap_wu := 6.0
	if DataStore != null and DataStore.visual:
		snap_wu = float(DataStore.visual.get("hull_visual_snap_wu", 6.0))
	if err.length_squared() > snap_wu * snap_wu:
		_snap_visual_to_logic()
		return
	var rate := 10.0
	if DataStore != null and DataStore.visual:
		rate = float(DataStore.visual.get("hull_visual_follow_rate", 10.0))
	rate = maxf(0.5, rate)
	var a := 1.0 - exp(-rate * delta)
	_visual_world = _visual_world.lerp(global_position, a)
	## Keep rest local offset (centering); only the world translation soft-follows.
	_model_root.global_position = _visual_world + (global_transform.basis * _model_rest_local)


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
	var dur := hull_morph_duration_s
	if DataStore != null and DataStore.combat:
		dur = float(DataStore.combat.get("hull_morph_duration_s", dur))
		if hull_morph_duration_s > 0.0:
			dur = hull_morph_duration_s
	var world: Node = get_parent()
	if world == null:
		world = self
	var fx = _HULL_MORPH_FX.new()
	fx.name = "HullMorphFx_%d" % get_instance_id()
	world.add_child(fx)
	fx.play(self, hull_morph, dur)


## mining_command: Field Porpoise active → other mining sources receive +20% (MINING §3).
func _hull_morph_fetter_satisfied() -> bool:
	var need := hull_morph_requires_fetter
	if need.is_empty():
		return true
	if need != "mining_command":
		return false
	## Beneficiaries only — Porpoise itself does not "eat" the bonus.
	var self_data: Dictionary = DataStore.get_ship(ship_id) if DataStore else {}
	var self_fids = self_data.get("fetter_ids", [])
	if int(ship_id) == 136 or ("mining_command" in self_fids):
		return false
	var board: BoardController = _find_board_controller() as BoardController
	if board == null:
		return false
	for s in board.field_ships(team_id):
		if s == null or s.is_destroyed or s.is_unmanned:
			continue
		var sd: Dictionary = DataStore.get_ship(s.ship_id)
		if int(s.ship_id) == 136 or ("mining_command" in sd.get("fetter_ids", [])):
			return true
	return false


func _find_board_controller() -> Node:
	var tree := get_tree()
	if tree:
		var root := tree.get_first_node_in_group("match_root")
		if root != null and root.get("board") != null:
			return root.board as Node
		var by_group := tree.get_first_node_in_group("board_controller")
		if by_group != null:
			return by_group
	var n: Node = get_parent()
	while n:
		if n.has_method("field_ships") and n.has_method("recalculate_fetters"):
			return n
		n = n.get_parent()
	return null


func apply_hull_morph_emission(strength: float, kind: String = "siege") -> void:
	if _model_root == null:
		return
	var tint := Color(1.0, 0.55, 0.25) if kind != "industrial" else Color(0.4, 1.0, 0.55)
	for mi in _find_meshes(_model_root):
		_set_mesh_emission(mi, strength, tint, true)


## After morph FX ends: restore combat-entry glow if still active, else clear white film.
func restore_emission_after_hull_morph() -> void:
	_apply_combat_tint_visual(_combat_glow_left_s > 0.0)


func _set_mesh_emission(mi: MeshInstance3D, strength: float, tint: Color, morph_tint: bool) -> void:
	var mats: Array = []
	if mi.material_override != null:
		mats.append(mi.material_override)
	if mi.mesh:
		for si in range(mi.mesh.get_surface_count()):
			var sov := mi.get_surface_override_material(si)
			if sov != null and mats.find(sov) < 0:
				mats.append(sov)
	for mat in mats:
		if mat is ShaderMaterial:
			var smat := mat as ShaderMaterial
			smat.set_shader_parameter("combat_emission_strength", strength)
		elif mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			std.emission_enabled = strength > 0.001
			std.emission = tint if morph_tint else Color.WHITE
			std.emission_energy_multiplier = strength

func restore_team_yaw() -> void:
	var yaw := float(DataStore.visual.get("player_yaw_deg" if team_id == TEAM_PLAYER else "ai_yaw_deg", 0.0))
	rotation_degrees = Vector3(0, yaw, 0)

func _ensure_mesh() -> void:
	if _model_root or _mesh:
		return
	## Performance mode: skip GLB load; keep empty node for transforms / health bar.
	if GameSession and bool(GameSession.get("no_model_perf_mode")):
		_model_root = Node3D.new()
		_model_root.name = "NoModelPlaceholder"
		add_child(_model_root)
		return
	var path := _mesh_path_safe()
	if path != "" and ResourceLoader.exists(path):
		var packed := load(path)
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
	## Missing model: leave empty (no placeholder box). Drop-in §0 bundle restores mesh.
	_muzzle_local = Vector3(0.0, 0.3, -0.9)


func _cache_model_rest_pose() -> void:
	if _model_root == null:
		return
	_model_root.set_meta("rest_rotation", _model_root.rotation)
	_model_root.set_meta("rest_scale", _model_root.scale)


func restore_model_rest_pose() -> void:
	if _model_root == null:
		return
	if _model_root.has_meta("rest_rotation"):
		_model_root.rotation = _model_root.get_meta("rest_rotation") as Vector3
	if _model_root.has_meta("rest_scale"):
		_model_root.scale = _model_root.get_meta("rest_scale") as Vector3
	var addon := _model_root.get_node_or_null("SiegeAddon") as Node3D
	if addon:
		addon.visible = false


func _attach_siege_addon_if_any() -> void:
	## Optional static/anim siege flap pack: assets/models/ships/<key>/siege_addon.glb
	if _model_root == null or DataStore == null:
		return
	if _model_root.get_node_or_null("SiegeAddon") != null:
		return
	var key := str(DataStore.get_ship(ship_id).get("model_key", ""))
	if key.is_empty():
		return
	var path := "res://assets/models/ships/%s/siege_addon.glb" % key
	if not ResourceLoader.exists(path):
		return
	var packed := load(path)
	if not (packed is PackedScene):
		return
	var addon := (packed as PackedScene).instantiate() as Node3D
	if addon == null:
		return
	addon.name = "SiegeAddon"
	addon.visible = false
	_model_root.add_child(addon)

func _mesh_path_safe() -> String:
	if DataStore != null and DataStore.has_method("ship_mesh_path_resolved"):
		return str(DataStore.ship_mesh_path_resolved(ship_id))
	if DataStore != null and DataStore.has_method("ship_mesh_path"):
		var path := str(DataStore.ship_mesh_path(ship_id))
		if path != "" and ResourceLoader.exists(path):
			return path
	var key := str(DataStore.get_ship(ship_id).get("model_key", "")) if DataStore else ""
	if key != "":
		var bundle_mesh := "res://assets/models/ships/%s/model.glb" % key
		if ResourceLoader.exists(bundle_mesh):
			return bundle_mesh
	return ""

func _ensure_health_bar() -> void:
	if _health_bar != null:
		return
	## Drones: trail-only; skip overlay to avoid floating-bar clutter.
	if is_unmanned:
		return
	_health_bar = _HEALTH_BAR_SCRIPT.new() as Node3D
	_health_bar.name = "HealthBar"
	add_child(_health_bar)
	_health_bar.call("setup", self)

func clear_health_bar() -> void:
	if _health_bar != null and is_instance_valid(_health_bar):
		_health_bar.queue_free()
	_health_bar = null
	var hb := get_node_or_null("HealthBar")
	if hb:
		hb.queue_free()

func rebuild_health_bar() -> void:
	## Recreate badge/bars after external FX accidentally mutated overlay materials.
	clear_health_bar()
	_ensure_health_bar()
	if _health_bar and _health_bar.has_method("refresh"):
		_health_bar.call("refresh")

func _apply_model_orientation(root: Node3D) -> void:
	## Lay hull flat: longest axis → length (local Z), up stays Y when possible.
	var pitch := float(DataStore.visual.get("ship_model_pitch_deg", 0.0))
	var model_yaw := float(DataStore.visual.get("ship_model_yaw_deg", 180.0))
	var model_roll := float(DataStore.visual.get("ship_model_roll_deg", 0.0))
	## Nozzles face astern, so a baked `bow_fit` yaw is ground truth and outranks
	## both the global default and the extent guess below (CONTENT_FORMAT §喷口).
	var fit := _bow_fit()
	if fit.has("model_yaw_deg"):
		root.rotation_degrees = Vector3(pitch, float(fit["model_yaw_deg"]), model_roll)
		if bool(DataStore.visual.get("ship_model_level_keel", true)):
			_level_model_keel(root)
		return
	## Echoes hulls are authored length-on-Z, so content keeps auto-orient off globally.
	## TQ hulls (titans) are length-on-X and must opt back in per ship def.
	var auto_orient := bool(DataStore.visual.get("ship_model_auto_orient", true))
	var def_flag: Variant = DataStore.get_ship(ship_id).get("model_auto_orient", null)
	if def_flag != null:
		auto_orient = bool(def_flag)
	if auto_orient:
		var aabb := _aabb_mesh_local(root)
		var sx := aabb.size.x
		var sy := aabb.size.y
		var sz := aabb.size.z
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
	if bool(DataStore.visual.get("ship_model_level_keel", true)):
		_level_model_keel(root)

func _level_model_keel(root: Node3D) -> void:
	## Cancel baked bow/stern pitch so the keel sits level (fixes “nose into floor” look).
	var pts: Array[Vector3] = []
	for mi in _find_meshes(root):
		if mi.mesh == null:
			continue
		var xf := _xform_to_ancestor(root, mi)
		for s in range(mi.mesh.get_surface_count()):
			var arr: Array = mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var step := maxi(1, int(verts.size() / 400.0))
			var i := 0
			while i < verts.size():
				pts.append(xf * verts[i])
				i += step
	if pts.size() < 16:
		return
	var min_z := INF
	var max_z := -INF
	for p in pts:
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var span := max_z - min_z
	if span < 0.001:
		return
	var front_y := 0.0
	var back_y := 0.0
	var fn := 0
	var bn := 0
	var thr := span * 0.12
	for p in pts:
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
	var corr := -rad_to_deg(atan2(front_y - back_y, span))
	corr = clampf(corr, -35.0, 35.0)
	root.rotation_degrees.x += corr

static func _is_sleeper_hull(ship: Dictionary) -> bool:
	if str(ship.get("race", "")).to_lower() == "sleeper":
		return true
	for t in (ship.get("tags", []) as Array):
		var ts := str(t).to_lower()
		if ts == "sleeper" or ts == "pve_creep":
			return true
	return false


## Shop combat hulls of the four empires in `group` — mean `model_long_axis`.
## Sleepers must render at this size (MULTIPLAYER_MATCH_FLOW §5.1).
static func _racial_tonnage_mean_long_axis(group: String) -> float:
	if group == "" or DataStore == null:
		return 0.0
	var sum := 0.0
	var n := 0
	for sid in DataStore.ship_ids():
		var s: Dictionary = DataStore.get_ship(int(sid))
		if str(s.get("ship_group", "")) != group:
			continue
		var race := str(s.get("race", "")).to_lower()
		if race not in ["amarr", "caldari", "gallente", "minmatar"]:
			continue
		if bool(s.get("is_logistic", false)):
			continue
		if s.has("shop_eligible") and not bool(s.get("shop_eligible", true)):
			continue
		if _is_sleeper_hull(s):
			continue
		var ax := float(s.get("model_long_axis", 0.0))
		if ax <= 0.0:
			continue
		sum += ax
		n += 1
	return sum / float(n) if n > 0 else 0.0


func _normalize_model_scale(root: Node3D) -> void:
	## Curve-map Echoes dogma long axis (type attr radius / 105) → display size;
	## mesh AABB longest only scales the GLB to that display size (fallback axis source).
	var target := float(DataStore.visual.get("ship_target_size", 2.4))
	var ref_l := float(DataStore.visual.get("ship_scale_ref_longest", 95.0))
	var power := float(DataStore.visual.get("ship_scale_curve_power", 0.5))
	var min_mul := float(DataStore.visual.get("ship_scale_min_mul", 0.5))
	var max_mul := float(DataStore.visual.get("ship_scale_max_mul", 2.0))
	var aabb := _aabb_mesh_local(root)
	var mesh_longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if mesh_longest < 0.0001:
		return
	var ship_data: Dictionary = DataStore.get_ship(ship_id)
	var axis := float(ship_data.get("model_long_axis", 0.0))
	## Sleepers share the racial same-tonnage mean long axis (MATCH_FLOW §5.1).
	if _is_sleeper_hull(ship_data):
		var mean_axis := _racial_tonnage_mean_long_axis(str(ship_data.get("ship_group", "")))
		if mean_axis > 0.0:
			axis = mean_axis
	if axis <= 0.0:
		axis = mesh_longest
	ref_l = maxf(ref_l, 1.0)
	power = clampf(power, 0.05, 1.0)
	var ratio := axis / ref_l
	var display := target * pow(ratio, power)
	display = clampf(display, target * min_mul, target * max_mul)
	_model_display_size = display
	var sc := display / mesh_longest
	sc *= float(DataStore.visual.get("ship_visual_scale", 1.0))
	if is_unmanned:
		## Fighters = frigate size. Drones are fractions of frigate (heavy 1/2, medium 1/3, light 1/4).
		if unmanned_kind == "fighter":
			sc *= float(DataStore.visual.get("fighter_visual_scale_mul", 1.0))
		else:
			var sg := str(DataStore.get_ship(ship_id).get("ship_group", ""))
			if sg == "drone_heavy" or unmanned_kind == "heavy_repair_drone":
				sc *= float(DataStore.visual.get("drone_heavy_visual_scale_mul", 0.5))
			elif sg == "drone_medium":
				sc *= float(DataStore.visual.get("drone_medium_visual_scale_mul", 1.0 / 3.0))
			elif sg == "drone_light" or unmanned_kind.find("repair") >= 0:
				sc *= float(DataStore.visual.get("drone_light_visual_scale_mul", 0.25))
			else:
				sc *= float(DataStore.visual.get("unmanned_visual_scale_mul", 0.25))
	root.scale = Vector3.ONE * sc
	aabb = _aabb_in_ship_space(root)
	var center := aabb.get_center()
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

func _aabb_mesh_local(root: Node3D) -> AABB:
	## Mesh AABB in root's local space via local transforms (safe before/after scale; ignores root.scale).
	var result := AABB()
	var first := true
	for mi in _find_meshes(root):
		var xf := _xform_to_ancestor(root, mi)
		var local_aabb: AABB = mi.get_aabb()
		for i in range(8):
			var p: Vector3 = xf * local_aabb.get_endpoint(i)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	return result

func _aabb_in_ship_space(root: Node3D) -> AABB:
	## Mesh AABB in ShipUnit local space (includes root.position/scale/rotation).
	var result := AABB()
	var first := true
	for mi in _find_meshes(root):
		var xf: Transform3D
		if is_inside_tree():
			xf = global_transform.affine_inverse() * mi.global_transform
		else:
			xf = root.transform * _xform_to_ancestor(root, mi)
		var local_aabb: AABB = mi.get_aabb()
		for i in range(8):
			var p: Vector3 = xf * local_aabb.get_endpoint(i)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	return result

func visual_center_world() -> Vector3:
	if _model_root != null:
		var aabb := _aabb_in_ship_space(_model_root)
		## AABB is already in current ship-local (includes soft-follow offset); map via root.
		return global_transform * aabb.get_center()
	return visual_origin_world()

func visual_radius_world() -> float:
	if _model_root != null:
		var aabb := _aabb_in_ship_space(_model_root)
		return maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
	return 1.0

func _xform_to_ancestor(ancestor: Node3D, leaf: Node) -> Transform3D:
	## Local transform from ancestor to leaf (does not include ancestor.transform).
	var chain: Array[Node3D] = []
	var walk: Node = leaf
	while walk != null and walk != ancestor:
		if walk is Node3D:
			chain.push_front(walk as Node3D)
		walk = walk.get_parent()
	var xf := Transform3D.IDENTITY
	for n in chain:
		xf = xf * n.transform
	return xf

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out

func _tint_model(root: Node) -> void:
	## Prefer Echoes §0 bundle with auxiliary control maps (pmwo/rg/reduction),
	## else fall back to simpler albedo+normal tint.
	var diffuse_path := DataStore.ship_diffuse_path(ship_id) if DataStore and DataStore.has_method("ship_diffuse_path") else ""
	var key := str(DataStore.get_ship(ship_id).get("model_key", ""))
	var bundle: Dictionary = {}
	if DataStore != null and DataStore.has_method("resolve_model_bundle"):
		bundle = DataStore.resolve_model_bundle(key)
	else:
		var root_dir := "res://assets/models/ships/%s" % key
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
	var diffuse := UiAssets.tex_ship_bake(diffuse_path) if diffuse_path != "" else null
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
			var npath := diffuse_path.replace("albedo.png", "normal.png")
			if _texture_file_ok(npath):
				normal = UiAssets.tex_ship_bake(npath)
	var pmwo_path := str(bundle.get("pmwo", ""))
	var rg_path := str(bundle.get("rg", ""))
	var reduction_path := str(bundle.get("reduction", ""))
	if _texture_file_ok(pmwo_path):
		pmwo = UiAssets.tex_ship_bake(pmwo_path)
	if _texture_file_ok(rg_path):
		rg_tex = UiAssets.tex_ship_bake(rg_path)
	if _texture_file_ok(reduction_path):
		reduction = UiAssets.tex_ship_bake(reduction_path)
	if diffuse == null and diffuse_path != "":
		push_warning("ShipUnit missing diffuse ship_id=%s path=%s" % [ship_id, diffuse_path])
	var neutral := Color(0.82, 0.84, 0.88, 1.0)
	var use_unity := ShipLook.is_unity_standard()
	for mi in _find_meshes(root):
		var mat: Material
		if use_unity and diffuse and normal and (pmwo != null) and (rg_tex != null):
			## Unity StandardShipShader port — needs albedo/normal/pmwo/rg (reduction optional).
			var smat := ShaderMaterial.new()
			smat.shader = _UNITY_SHIP_SHADER
			smat.set_shader_parameter("albedo_tex", diffuse)
			smat.set_shader_parameter("normal_tex", normal)
			smat.set_shader_parameter("pmwo_tex", pmwo)
			smat.set_shader_parameter("rg_tex", rg_tex)
			ShipLook.apply_to_unity_shader_material(smat)
			mat = smat
		elif diffuse and normal and pmwo and rg_tex and reduction and not use_unity:
			var smat := ShaderMaterial.new()
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
			var std := StandardMaterial3D.new()
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
			for si in range(mi.mesh.get_surface_count()):
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
	var abs_path := ProjectSettings.globalize_path(path)
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
		_combat_glow_left_s = float(DataStore.visual.get("combat_glow_s", COMBAT_GLOW_S)) if DataStore else COMBAT_GLOW_S
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
	var unity_strength := 0.06 if in_combat else 0.0
	var echoes_strength := 0.08 if in_combat else 0.0
	var std_strength := 0.18 if in_combat else 0.0
	if _mat:
		var neutral := Color(0.82, 0.84, 0.88, 1.0)
		_mat.albedo_color = neutral.lightened(0.06) if in_combat else neutral
		_mat.emission_enabled = in_combat
		_mat.emission = Color.WHITE
		_mat.emission_energy_multiplier = std_strength
		return
	if _model_root == null:
		return
	var neutral2 := Color(0.82, 0.84, 0.88, 1.0)
	for mi in _find_meshes(_model_root):
		if mi.material_override is ShaderMaterial:
			var smat := mi.material_override as ShaderMaterial
			var strength := unity_strength if smat.shader == _UNITY_SHIP_SHADER else echoes_strength
			_set_mesh_emission(mi, strength, Color.WHITE, false)
			if smat.shader != _UNITY_SHIP_SHADER and not in_combat:
				smat.set_shader_parameter("team_tint", Color.WHITE)
				smat.set_shader_parameter("team_mix", 0.0)
		elif mi.material_override is StandardMaterial3D:
			var mat := mi.material_override as StandardMaterial3D
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
	for t in (ship.get("tags", []) as Array):
		if str(t) == "pve_salvage":
			return true
	return false

func reload_stats() -> void:
	var ship := DataStore.get_ship(ship_id)
	var st: Dictionary = DataStore.get_star_resolved(ship_id, star)
	if st.is_empty():
		return
	is_logistic = bool(ship.get("is_logistic", false)) or bool(st.get("is_logistic", false))
	is_mining_ship = bool(ship.get("is_mining_ship", false))
	is_protect_target = _resolve_protect_target(ship)
	race = str(ship.get("race", "amarr")).to_lower()
	attack_range = float(st.get("attack_range", 1))
	var dmg: Dictionary = st.get("damage", {})
	## Kit-derived hulls keep ★1 base DPH here; star raise is star_dph_mul (invisible buff).
	## Baked stars[] (unmanned / unresolved capital) already include star × on damage.
	damage_emp = float(dmg.get("emp", 0))
	damage_thermal = float(dmg.get("thermal", 0))
	damage_kinetic = float(dmg.get("kinetic", 0))
	damage_explosive = float(dmg.get("explosive", 0))
	star_dph_mul = float(maxi(star, 1)) if ShipWeaponDerive.should_derive(ship) else 1.0
	var rep_src: Dictionary = st
	if is_logistic or str(ship.get("unmanned_kind", "")).find("repair") >= 0:
		var st1: Dictionary = DataStore.get_star_resolved(ship_id, 1)
		if not st1.is_empty():
			rep_src = st1
	var rep: Dictionary = rep_src.get("repair", {})
	repair_shield = float(rep.get("shield", 0))
	repair_armor = float(rep.get("armor", 0))
	repair_structure = float(rep.get("structure", 0))
	max_shield = float(st.get("shield_hp", 0))
	max_armor = float(st.get("armor_hp", 0))
	if st.has("structure_hp"):
		max_structure = float(st.get("structure_hp", 0))
	else:
		max_structure = maxf(50.0, roundf(max_armor * 0.5))
	base_max_shield = max_shield
	base_max_armor = max_armor
	base_max_structure = max_structure
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
	shield_resist_emp = float(sr.get("emp", 0))
	armor_resist_emp = float(ar.get("emp", 0))
	structure_resist_emp = float(str_res.get("emp", armor_resist_emp))
	_base_shield_resist_emp = shield_resist_emp
	_base_armor_resist_emp = armor_resist_emp
	_base_structure_resist_emp = structure_resist_emp
	signature_radius = float(ship.get("signature_radius", 40.0))
	scan_resolution = float(ship.get("scan_resolution", 400.0))
	base_speed = float(ship.get("speed", 300.0))
	tracking = float(st.get("tracking", 0.0))
	optimal_cells = float(st.get("optimal", 0.0))
	falloff_cells = float(st.get("falloff", 0.0))
	optimal_sig_radius = float(st.get("optimal_sig_radius", 40.0))
	explosion_radius = float(st.get("explosion_radius", 0.0))
	explosion_velocity = float(st.get("explosion_velocity", 0.0))
	missile_drf = float(st.get("drf", 0.0))
	missile_drs = float(st.get("drs", DataStore.combat.get("missile_drs_default", 1.0)))
	cap_capacity = float(ship.get("capacitor_capacity", 0.0))
	cap_recharge_s = maxf(float(ship.get("capacitor_recharge_s", 1.0)), 0.001)
	cap_cost_per_cycle = float(st.get("cap_cost", ship.get("cap_cost", -1.0)))
	fetter_repair_mul = 1.0
	fetter_speed_mul = 1.0
	var cd := DataStore.combat
	var cycle := float(ship.get("attack_cycle_s", -1.0))
	var derived_cycle := float(st.get("_attack_cycle_s", -1.0))
	if derived_cycle > 0.0 and ShipWeaponDerive.should_derive(ship):
		cycle = derived_cycle
	if cycle <= 0.0:
		cycle = float(cd.get("logistic_attack_duration_s" if is_logistic else "attack_duration_s", 1.0))
	var cap_s := float(cd.get("attack_cycle_cap_s", 6.0))
	## Capitals / cyno / explicit long cycles keep JSON cycle (siege & 90s channel).
	var role := str(ship.get("capital_role", ""))
	if role != "" or bool(ship.get("requires_cyno_entry", false)):
		attack_duration = cycle
	else:
		attack_duration = minf(cycle, cap_s)
	base_attack_duration = attack_duration
	is_destroyed = false
	is_unmanned = bool(ship.get("is_unmanned", false))
	unmanned_kind = str(ship.get("unmanned_kind", ""))
	drone_bandwidth = float(ship.get("drone_bandwidth", 0.0))
	drone_bay_slots = int(ship.get("drone_bay_slots", ship.get("drone_count_cap", 0)))
	if drone_bay_slots <= 0 and drone_bandwidth > 0.0:
		drone_bay_slots = int(floor(drone_bandwidth / 5.0))
	visible = true
	reset_combat_runtime()
	if _health_bar:
		_health_bar.visible = true
		_health_bar.call("refresh")

func reset_combat_runtime() -> void:
	cap_current = cap_capacity
	lock_target_id = 0
	lock_timer = 0.0
	lock_duration_s = 0.0
	clear_pre_lock()
	retreat_until_time = -1.0
	no_target_acc = 0.0
	combat_target = null
	last_attack_time = -999.0
	_stat_modifiers.clear()
	## Carrier pool re-inits on next ensure; do not wipe living fighters' squadron id.
	fighter_squadron_pool_left = -1
	fighter_next_squadron_id = 0
	if not is_unmanned:
		fighter_squadron_id = -1
	hull_morph_playing = false
	hull_morphed = false
	hull_morph_unstacking = false
	restore_model_rest_pose()
	## Drop leftover morph FX from prior round if still parented.
	var old_fx := get_parent().get_node_or_null("HullMorphFx_%d" % get_instance_id()) if get_parent() else null
	if old_fx != null and is_instance_valid(old_fx):
		old_fx.queue_free()

func get_stat(stat_name: String, base_value: float) -> float:
	var add := 0.0
	var mul := 1.0
	for m in _stat_modifiers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("stat", "")) != stat_name:
			continue
		match str(m.get("op", "add")):
			"add":
				add += float(m.get("value", 0.0))
			"mul":
				mul *= float(m.get("value", 1.0))
	return (base_value + add) * mul

func add_stat_modifier(source: String, stat_name: String, op: String, value: float, duration: float = -1.0, stack_id: String = "") -> void:
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
	for m in _stat_modifiers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var dur := float(m.get("duration", -1.0))
		if dur < 0.0:
			kept.append(m)
			continue
		m["age"] = float(m.get("age", 0.0)) + sim_dt
		if float(m["age"]) < dur:
			kept.append(m)
	_stat_modifiers = kept

func combat_move_speed() -> float:
	var wu := CombatFormulas.world_units_per_cell()
	var move_scale := float(DataStore.combat.get("move_speed_scale", 1.65))
	## Movement runs on its own metric — 1 cell = 500 m, never the 2 km range metric.
	var m_per_cell := float(DataStore.combat.get("speed_meters_per_cell", 500.0))
	var spd := get_stat("speed", base_speed)
	var mapped := spd / m_per_cell * wu * move_scale * fetter_speed_mul
	var speed := maxf(mapped, 0.5)
	if absf(global_position.z) < float(DataStore.combat.get("isolation_half_width_wu", 2.5)):
		speed *= float(DataStore.combat.get("isolation_speed_mul", 0.7))
	## Excavators wander the belt slowly (MINING §2.1): 1/5 mapped move speed.
	if is_unmanned and str(unmanned_kind) == "mining_excavator":
		speed *= float(DataStore.combat.get("mining_excavator_move_mul", 0.2))
	return speed

func cap_fraction() -> float:
	if cap_capacity <= 0.0:
		return 1.0
	return cap_current / cap_capacity

func attacks_enabled() -> bool:
	if has_cyno_module():
		return false
	## Cap gate only after capacitor-warfare modules ship (COMBAT §7).
	if not bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		return true
	var frac_need := float(DataStore.combat.get("cap_disable_attack_function_pct", 0.10))
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
	for i in range(_plugin_modules.size()):
		var m: Dictionary = _plugin_modules[i]
		if m.get("id", null) == module_id:
			_plugin_modules.remove_at(i)
			_recompute_stats_from_modules()
			return true
	return false

func _recompute_stats_from_modules() -> void:
	## Infinite plugin-slot hook — no numeric effects this round.
	pass

func total_hp_fraction() -> float:
	var mx := max_shield + max_armor + max_structure
	if mx <= 0.0:
		return 1.0
	return clampf((shield_hp + armor_hp + structure_hp) / mx, 0.0, 1.0)

func tick_capacitor(sim_dt: float) -> void:
	if not bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		## Keep display/full for UI; no combat drain/gate until cap warfare exists.
		cap_current = cap_capacity
		return
	if cap_capacity <= 0.0:
		cap_current = 0.0
		return
	var rate := cap_capacity / cap_recharge_s
	cap_current = minf(cap_capacity, cap_current + rate * sim_dt)

func consume_cap_for_cycle() -> void:
	if not bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		return
	if cap_capacity <= 0.0:
		return
	var cost := cap_cost_per_cycle
	if cost < 0.0:
		cost = cap_capacity * float(DataStore.combat.get("cap_drain_fraction_per_cycle", 0.02))
	cap_current = maxf(0.0, cap_current - cost)

func sync_lock(target: ShipUnit, _sim_time: float) -> void:
	if target == null or target.is_destroyed:
		lock_target_id = 0
		lock_timer = 0.0
		lock_duration_s = 0.0
		return
	var tid := target.get_instance_id()
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
	var tid := target.get_instance_id()
	if pre_lock_target_id != tid:
		pre_lock_target_id = tid
		pre_lock_timer = 0.0
		pre_lock_duration_s = CombatFormulas.lock_time_s(scan_resolution, target.signature_radius)

func advance_pre_lock(sim_dt: float) -> void:
	if pre_lock_target_id == 0:
		return
	var t := instance_from_id(pre_lock_target_id) as ShipUnit
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
		tracking,
		optimal_cells,
		falloff_cells,
		optimal_sig_radius,
		target.get_stat("speed", target.base_speed),
		target.signature_radius,
		distance_cells
	)

func missile_damage_factor_vs(target: ShipUnit) -> float:
	return CombatFormulas.missile_damage_factor(
		target.signature_radius,
		target.get_stat("speed", target.base_speed),
		explosion_radius,
		explosion_velocity,
		missile_drf,
		missile_drs
	)

func damage_dict_scaled() -> Dictionary:
	var mul := star_dph_mul * (1.0 + damage_pct_bonus / 100.0)
	return {
		"emp": damage_emp * mul,
		"thermal": damage_thermal * mul,
		"kinetic": damage_kinetic * mul,
		"explosive": damage_explosive * mul,
	}

func sum_damage_amount(dmg: Dictionary) -> float:
	return float(dmg.get("emp", 0.0)) + float(dmg.get("thermal", 0.0)) + float(dmg.get("kinetic", 0.0)) + float(dmg.get("explosive", 0.0))

func heal_dict_scaled() -> Dictionary:
	# FAX heavy repair drones use fixed per-cycle values from content (no global x2 logistic multiplier).
	var mul := fetter_repair_mul
	if str(unmanned_kind) != "heavy_repair_drone":
		mul *= float(DataStore.combat.get("logistic_heal_multiplier", 1.0))
	return {
		"shield": repair_shield * mul,
		"armor": repair_armor * mul,
		"structure": repair_structure * mul,
	}

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
		var min_s := float(DataStore.combat.get("retreat_mode_min_s", 60.0))
		retreat_until_time = maxf(retreat_until_time, sim_time + min_s)

func in_retreat(sim_time: float) -> bool:
	return retreat_until_time > sim_time

func world_range() -> float:
	if unlimited_weapon_range:
		return 9999.0
	return attack_range * float(DataStore.combat.get("weapon_range_scale", 3.0))

func world_range_cells() -> float:
	if unlimited_weapon_range:
		return 9999.0
	return attack_range

func has_cyno_module() -> bool:
	for m in _plugin_modules:
		if str((m as Dictionary).get("kind", "")) == "cyno":
			return true
	return capital_role == "covert_cyno"

func cyno_duration_s() -> float:
	for m in _plugin_modules:
		var md: Dictionary = m
		if str(md.get("kind", "")) == "cyno":
			return float(md.get("duration_s", 90.0))
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
	shield_resist_emp = float(_shield_resist.get("emp", 0.0))
	armor_resist_emp = float(_armor_resist.get("emp", 0.0))
	structure_resist_emp = float(_structure_resist.get("emp", 0.0))


func _apply_resist_mul(dst: Dictionary, base: Dictionary, mul: float) -> void:
	dst.clear()
	for key in ["emp", "thermal", "kinetic", "explosive"]:
		dst[key] = minf(0.90, float(base.get(key, 0.0)) * mul)

func upgrade_level() -> void:
	if star < 3:
		star += 1
		reload_stats()

func get_cost() -> int:
	return int(DataStore.get_ship(ship_id).get("cost", 0))

func get_sell_price() -> int:
	## Sell = purchase cost − discount, floor min (economy.json).
	var eco: Dictionary = DataStore.economy if DataStore else {}
	var discount := int(eco.get("sell_price_discount", 3))
	var floor_p := int(eco.get("sell_price_min", 1))
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
	var sd := DataStore.get_ship(ship_id) if DataStore else {}
	var slots := int(sd.get("attack_weapon_slots", 0))
	if slots <= 0:
		slots = int(sd.get("hi_slots", 0))
	if slots <= 0:
		slots = 2
	return clampi(slots, 1, 8)

func _resolve_turret_locals(root: Node3D, aabb: AABB) -> void:
	_muzzle_locals.clear()
	_muzzle_fire_i = 0
	var key := str(DataStore.get_ship(ship_id).get("model_key", "")) if DataStore else ""
	var path := "res://assets/models/ships/%s/turret_anchors.json" % key
	if key != "" and FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			var arr: Variant = (parsed as Dictionary).get("anchors_mesh_local", [])
			if typeof(arr) == TYPE_ARRAY:
				for item in arr:
					if typeof(item) != TYPE_ARRAY and typeof(item) != TYPE_PACKED_FLOAT32_ARRAY and typeof(item) != TYPE_PACKED_FLOAT64_ARRAY:
						continue
					var a: Array = item as Array
					if a.size() < 3:
						continue
					_muzzle_locals.append(root.transform * Vector3(float(a[0]), float(a[1]), float(a[2])))
	if _muzzle_locals.is_empty():
		_muzzle_locals = _sample_turret_locals_from_mesh(root, aabb, _turret_slot_count())
	if _muzzle_locals.is_empty():
		var mid_y := maxf(aabb.get_center().y, aabb.size.y * 0.35)
		_muzzle_locals.append(Vector3(0.0, mid_y, aabb.position.z))
	_muzzle_local = _muzzle_locals[0]

func _sample_turret_locals_from_mesh(root: Node3D, aabb: AABB, want: int) -> Array[Vector3]:
	## Prefer authored hardpoints JSON; else sample upper-forward hull verts as turret decks.
	var pts: Array[Vector3] = []
	for mi in _find_meshes(root):
		if mi.mesh == null:
			continue
		var xf: Transform3D
		if is_inside_tree():
			xf = global_transform.affine_inverse() * mi.global_transform
		else:
			xf = root.transform * _xform_to_ancestor(root, mi)
		for s in range(mi.mesh.get_surface_count()):
			var arr: Array = mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var step := maxi(1, int(verts.size() / 500.0))
			var i := 0
			while i < verts.size():
				pts.append(xf * verts[i])
				i += step
	var mid_y := maxf(aabb.get_center().y, aabb.size.y * 0.35)
	var bow_z := aabb.position.z
	var z_cut := bow_z + aabb.size.z * 0.55  # forward 55% (bow = min Z)
	var y_cut := aabb.position.y + aabb.size.y * 0.45
	var deck: Array[Vector3] = []
	for p in pts:
		if p.z <= z_cut and p.y >= y_cut:
			deck.append(p)
	if deck.size() < 8:
		## Soften filters if mesh is sparse / flat.
		for p in pts:
			if p.z <= bow_z + aabb.size.z * 0.7:
				deck.append(p)
	var out: Array[Vector3] = []
	if deck.size() < 4:
		## Symmetric gunwales along forward length.
		var n := maxi(1, want)
		for i in range(n):
			var t := (float(i) + 0.5) / float(n)
			var z := bow_z + aabb.size.z * 0.08 + aabb.size.z * 0.42 * t
			var x_off := aabb.size.x * 0.32
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
	var per := maxi(1, int(ceil(float(deck.size()) / float(maxi(want, 1)))))
	var g: Array[Vector3] = []
	for p in deck:
		g.append(p)
		if g.size() >= per and groups.size() + 1 < want:
			groups.append(g.duplicate())
			g.clear()
	if not g.is_empty():
		groups.append(g)
	while groups.size() > want:
		groups.pop_back()
	for grp in groups:
		var sx := 0.0
		var sy := 0.0
		var sz := 0.0
		var cn: Array = grp
		for p2 in cn:
			var v: Vector3 = p2
			sx += v.x
			sy += v.y
			sz += v.z
		var n2 := maxf(1.0, float(cn.size()))
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
	return float(DataStore.visual.get("ship_target_size", 2.4)) if DataStore else 2.4


## Soft collision sphere radius in world units (scales with on-field display size).
func collision_radius_wu() -> float:
	var frac := 0.26
	var rmin := 0.32
	var rmax := 0.95
	var umul := 0.5
	var fallback := 0.5
	if DataStore != null and DataStore.combat:
		frac = float(DataStore.combat.get("collision_radius_display_frac", frac))
		rmin = float(DataStore.combat.get("collision_radius_min_wu", rmin))
		rmax = float(DataStore.combat.get("collision_radius_max_wu", rmax))
		umul = float(DataStore.combat.get("collision_unmanned_mul", umul))
		fallback = float(DataStore.combat.get("agent_radius", fallback))
	var disp := get_model_display_size()
	if disp <= 0.05:
		return fallback
	var r := disp * frac
	if is_unmanned:
		r *= umul
	return clampf(r, rmin, rmax)

func _resolve_engine_local(root: Node3D, aabb: AABB) -> void:
	## Formal: engine_boosters.json mapped SOF→mesh AABB. Fallback: one stern point.
	_engine_locals.clear()
	_engine_outlines.clear()
	_load_engine_boosters(root, aabb)
	if _engine_locals.is_empty():
		var mid_y := maxf(aabb.get_center().y, aabb.size.y * 0.25)
		var z_aft := aabb.position.z + aabb.size.z
		var p := Vector3(0.0, mid_y, z_aft)
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
	var file := FileAccess.open("res://assets/models/ships/%s/engine_boosters.json" % key, FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			doc = parsed
	_booster_docs[key] = doc
	return doc

## Offline nozzle→bow solve (`tools/fit_bow_yaw_from_nozzles.py`); empty when the
## pack still relies on the global yaw + SOF AABB mapping.
func _bow_fit() -> Dictionary:
	var key := str(DataStore.get_ship(ship_id).get("model_key", "")) if DataStore else ""
	var fit_v: Variant = _booster_doc_for(key).get("bow_fit", null)
	return fit_v as Dictionary if typeof(fit_v) == TYPE_DICTIONARY else {}

## True when the pack carries the offline nozzle→bow solve, i.e. heading and nozzles are
## measured per hull. Callers must not add their own bow flip or nozzle mirror on top.
func has_baked_bow_fit() -> bool:
	return not _bow_fit().is_empty()

func _load_engine_boosters(_root: Node3D, mesh_aabb: AABB) -> void:
	## Map SOF-native nozzle pos into live mesh AABB (Echoes GLB ≠ TQ mesh space).
	## SOF aft ≈ min Z; Godot ship aft ≈ max Z → flip normalized Z.
	var key := str(DataStore.get_ship(ship_id).get("model_key", "")) if DataStore else ""
	if key == "":
		return
	var doc := _booster_doc_for(key)
	if doc.is_empty():
		return
	var items: Variant = doc.get("items", [])
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		return
	if mesh_aabb.size.x < 1e-4 or mesh_aabb.size.y < 1e-4 or mesh_aabb.size.z < 1e-4:
		return
	## TQ-converted GLBs swap axes, so their nozzles are pre-solved against the
	## real mesh and only need the live post-yaw AABB.
	if _load_baked_nozzles(mesh_aabb):
		_sort_nozzles_aft_first()
		return
	var sof_aabb := _sof_hull_aabb(doc)
	if sof_aabb.size.x < 1e-4 or sof_aabb.size.y < 1e-4 or sof_aabb.size.z < 1e-4:
		return
	var scale_r := (
		mesh_aabb.size.x / sof_aabb.size.x
		+ mesh_aabb.size.y / sof_aabb.size.y
		+ mesh_aabb.size.z / sof_aabb.size.z
	) / 3.0
	## Prefer SOF `has_trail` nozzles. TQ drones often flag all boosters `has_trail:false`
	## (always_on glow only) — still pin game trails to those real nozzle transforms.
	var preferred: Array = []
	var all_valid: Array = []
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var pos_v: Variant = d.get("pos", null)
		if typeof(pos_v) != TYPE_ARRAY and typeof(pos_v) != TYPE_PACKED_FLOAT32_ARRAY and typeof(pos_v) != TYPE_PACKED_FLOAT64_ARRAY:
			continue
		var a0: Array = pos_v as Array
		if a0.size() < 3:
			continue
		all_valid.append(d)
		if d.get("has_trail", true) != false:
			preferred.append(d)
	var use_items: Array = preferred if not preferred.is_empty() else all_valid
	for d_any in use_items:
		var d: Dictionary = d_any
		var a: Array = d.get("pos") as Array
		var sof_p := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var nx := (sof_p.x - sof_aabb.position.x) / sof_aabb.size.x
		var ny := (sof_p.y - sof_aabb.position.y) / sof_aabb.size.y
		var nz := (sof_p.z - sof_aabb.position.z) / sof_aabb.size.z
		nx = clampf(nx, -0.05, 1.05)
		ny = clampf(ny, -0.05, 1.05)
		nz = clampf(nz, -0.05, 1.05)
		## Flip length: SOF min-Z aft → Godot max-Z aft.
		var ship_p := Vector3(
			mesh_aabb.position.x + nx * mesh_aabb.size.x,
			mesh_aabb.position.y + ny * mesh_aabb.size.y,
			mesh_aabb.position.z + (1.0 - nz) * mesh_aabb.size.z
		)
		var rad := float(d.get("radius", 0.08)) * scale_r
		_engine_locals.append(ship_p)
		_engine_outlines.append(_circle_outline(ship_p, maxf(rad, mesh_aabb.size.x * 0.02)))
	_sort_nozzles_aft_first()

## Nozzle positions solved offline against the GLB itself, stored 0..1 inside the
## post-yaw mesh AABB — the live AABB already carries scale and recentre.
func _load_baked_nozzles(mesh_aabb: AABB) -> bool:
	var fit := _bow_fit()
	var norms_v: Variant = fit.get("nozzles_ship_norm", null)
	if typeof(norms_v) != TYPE_ARRAY or (norms_v as Array).is_empty():
		return false
	var norms: Array = norms_v
	var radii: Array = fit.get("nozzle_radius_norm", []) as Array
	var longest := maxf(mesh_aabb.size.x, maxf(mesh_aabb.size.y, mesh_aabb.size.z))
	for i in range(norms.size()):
		if typeof(norms[i]) != TYPE_ARRAY or (norms[i] as Array).size() < 3:
			continue
		var n: Array = norms[i]
		var p := Vector3(
			mesh_aabb.position.x + clampf(float(n[0]), -0.05, 1.05) * mesh_aabb.size.x,
			mesh_aabb.position.y + clampf(float(n[1]), -0.05, 1.05) * mesh_aabb.size.y,
			mesh_aabb.position.z + clampf(float(n[2]), -0.05, 1.05) * mesh_aabb.size.z
		)
		var rad := (float(radii[i]) * longest) if i < radii.size() else 0.0
		_engine_locals.append(p)
		_engine_outlines.append(_circle_outline(p, maxf(rad, mesh_aabb.size.x * 0.02)))
	return not _engine_locals.is_empty()

func _sort_nozzles_aft_first() -> void:
	if _engine_locals.is_empty():
		return
	var order: Array[int] = []
	for i in range(_engine_locals.size()):
		order.append(i)
	order.sort_custom(func(ia: int, ib: int) -> bool: return _engine_locals[ia].z > _engine_locals[ib].z)
	var locs: Array[Vector3] = []
	var outs: Array = []
	for i in order:
		locs.append(_engine_locals[i])
		outs.append(_engine_outlines[i])
	_engine_locals = locs
	_engine_outlines = outs

func _sof_hull_aabb(doc: Dictionary) -> AABB:
	var hb: Variant = doc.get("hull_aabb", null)
	if typeof(hb) == TYPE_DICTIONARY:
		var pos_v: Variant = (hb as Dictionary).get("position", null)
		var size_v: Variant = (hb as Dictionary).get("size", null)
		if typeof(pos_v) == TYPE_ARRAY and typeof(size_v) == TYPE_ARRAY:
			var pa: Array = pos_v
			var sa: Array = size_v
			if pa.size() >= 3 and sa.size() >= 3:
				return AABB(
					Vector3(float(pa[0]), float(pa[1]), float(pa[2])),
					Vector3(float(sa[0]), float(sa[1]), float(sa[2]))
				)
	## Derive from item positions if hull_aabb missing.
	var items: Variant = doc.get("items", [])
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		return AABB()
	var first := true
	var mn := Vector3.ZERO
	var mx := Vector3.ZERO
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var pos_v2: Variant = (item as Dictionary).get("pos", null)
		if typeof(pos_v2) != TYPE_ARRAY:
			continue
		var a2: Array = pos_v2
		if a2.size() < 3:
			continue
		var p := Vector3(float(a2[0]), float(a2[1]), float(a2[2]))
		if first:
			mn = p
			mx = p
			first = false
		else:
			mn = mn.min(p)
			mx = mx.max(p)
	if first:
		return AABB()
	var size := mx - mn
	## Pad stern cluster toward bow (SOF +Z).
	var pad := maxf(size.x, maxf(size.y, 1.0)) * 0.5
	mn.x -= pad
	mx.x += pad
	mn.y -= pad
	mx.y += pad
	mx.z += maxf(size.z * 2.5, pad * 2.0)
	return AABB(mn, mx - mn)

func _circle_outline(center: Vector3, radius: float, sides: int = 10) -> PackedVector3Array:
	var out := PackedVector3Array()
	var r := maxf(radius, 0.01)
	for k in range(sides):
		var ang := TAU * float(k) / float(sides)
		out.append(center + Vector3(cos(ang) * r, sin(ang) * r, 0.0))
	return out

func resolve_weapon_fx_kind() -> String:
	## Prefer ships/<id>.json weapon_fx. Do NOT infer from hull ship_groups (EVEmu stores
	## weapon family on modules, not hull). Logistics → heal; else default_kind.
	var cfg: Dictionary = DataStore.weapon_fx
	var ship := DataStore.get_ship(ship_id)
	var explicit := str(ship.get("weapon_fx", "")).strip_edges()
	if explicit != "":
		return explicit
	if is_logistic:
		return "heal"
	return str(cfg.get("default_kind", "laser"))

func apply_hit(raw_emp: float, raw_thermal: float = 0.0, raw_kinetic: float = 0.0, raw_explosive: float = 0.0) -> Dictionary:
	## Returns {destroyed:bool, dealt:float}. Layer overflow pierces shield→armor→structure when combat flag is on.
	var dmg := {
		"emp": raw_emp,
		"thermal": raw_thermal,
		"kinetic": raw_kinetic,
		"explosive": raw_explosive,
	}
	return apply_hit_dict(dmg)

func apply_hit_dict(dmg: Dictionary) -> Dictionary:
	if is_destroyed:
		return {"destroyed": is_destroyed, "dealt": 0.0}
	var total_raw := sum_damage_amount(dmg)
	if total_raw <= 0.0:
		return {"destroyed": is_destroyed, "dealt": 0.0}
	var min_pct := float(DataStore.combat.get("min_damage_pct", 0.25))
	var layer := "shield"
	if shield_hp <= 0.0:
		layer = "armor" if armor_hp > 0.0 else "structure"
	var resist_map: Dictionary = _shield_resist if layer == "shield" else (_armor_resist if layer == "armor" else _structure_resist)
	var dealt := 0.0
	for key in ["emp", "thermal", "kinetic", "explosive"]:
		var raw := float(dmg.get(key, 0.0))
		if raw <= 0.0:
			continue
		var resist := clampf(float(resist_map.get(key, 0.0)), 0.0, 0.95)
		dealt += maxf(raw * min_pct, raw * (1.0 - resist))
	dealt = maxf(dealt, total_raw * min_pct)
	var remaining := dealt
	var applied := 0.0
	var pierce := bool(DataStore.combat.get("shield_overflow_pierces_armor", true))
	if shield_hp > 0.0 and remaining > 0.0:
		var absorbed := minf(shield_hp, remaining)
		shield_hp -= absorbed
		remaining -= absorbed
		applied += absorbed
		if not pierce:
			remaining = 0.0
	if armor_hp > 0.0 and remaining > 0.0:
		var absorbed_a := minf(armor_hp, remaining)
		armor_hp -= absorbed_a
		remaining -= absorbed_a
		applied += absorbed_a
		if not pierce:
			remaining = 0.0
	if remaining > 0.0:
		var absorbed_s := minf(maxf(structure_hp, 0.0), remaining)
		structure_hp -= remaining
		applied += absorbed_s
	if is_capital_flagship() and applied > 0.0:
		var loss_pct := float(DataStore.combat.get("capital_max_hp_loss_from_damage_pct", 0.10))
		if loss_pct > 0.0:
			_apply_capital_max_hp_loss(applied * loss_pct)
	if shield_hp <= 0.0 and armor_hp <= 0.0 and structure_hp <= 0.0:
		is_destroyed = true
		## Titan-same explode FX scaled; no wreck for non-titans.
		var parent_n := get_parent()
		if parent_n:
			ShipDeathFx.spawn_explode(parent_n, global_position, ship_id)
		visible = false
		if _health_bar:
			_health_bar.visible = false
		return {"destroyed": true, "dealt": dealt}
	if _health_bar:
		_health_bar.call("refresh")
	return {"destroyed": false, "dealt": dealt}

## dreadnought / carrier / force_auxiliary only (CAPITAL_AND_CYNO §3.1).
func is_capital_flagship() -> bool:
	if capital_role in ["dreadnought", "carrier", "force_auxiliary"]:
		return true
	var sg := str(DataStore.get_ship(ship_id).get("ship_group", "")) if DataStore else ""
	return sg in ["dreadnought", "carrier", "force_auxiliary"]

## Permanently cut base_max_* (and live max_*) proportional to current base caps.
func _apply_capital_max_hp_loss(loss: float) -> void:
	if loss <= 0.0:
		return
	var total := base_max_shield + base_max_armor + base_max_structure
	if total <= 1e-6:
		return
	loss = minf(loss, total)
	var mul_s := max_shield / base_max_shield if base_max_shield > 1e-6 else 1.0
	var mul_a := max_armor / base_max_armor if base_max_armor > 1e-6 else 1.0
	var flat_st := max_structure - base_max_structure
	var cut_s := loss * (base_max_shield / total)
	var cut_a := loss * (base_max_armor / total)
	var cut_st := loss - cut_s - cut_a
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
	var res := apply_heal_racial("minmatar", {"shield": amount * 0.5, "armor": amount * 0.5, "structure": 0.0})
	return bool(res.get("full", false))

## Returns {applied: float, full: bool}. `applied` is HP that actually entered the
## bars — a layer already at max discards its share (COMBAT §9: 溢出丢弃、不跨层),
## so callers must never report the requested amount as healing.
func apply_heal_racial(source_race: String, amounts: Dictionary) -> Dictionary:
	if is_destroyed:
		return {"applied": 0.0, "full": true}
	var race_key := source_race.to_lower()
	var shield_amt := 0.0
	var armor_amt := 0.0
	var structure_amt := 0.0
	match race_key:
		"amarr":
			armor_amt = float(amounts.get("armor", 0.0))
			if armor_amt <= 0.0:
				armor_amt = float(amounts.get("shield", 0.0)) + float(amounts.get("structure", 0.0))
		"caldari":
			shield_amt = float(amounts.get("shield", 0.0))
			if shield_amt <= 0.0:
				shield_amt = float(amounts.get("armor", 0.0)) + float(amounts.get("structure", 0.0))
		"gallente":
			structure_amt = float(amounts.get("structure", 0.0))
			if structure_amt <= 0.0:
				structure_amt = float(amounts.get("shield", 0.0)) + float(amounts.get("armor", 0.0))
		"minmatar":
			var total := float(amounts.get("shield", 0.0)) + float(amounts.get("armor", 0.0)) + float(amounts.get("structure", 0.0))
			var hi := int(floor(total))
			var lo := int(hi / 2.0)
			shield_amt = float(lo + hi % 2)
			armor_amt = float(lo)
		_:
			shield_amt = float(amounts.get("shield", 0.0))
			armor_amt = float(amounts.get("armor", 0.0))
			structure_amt = float(amounts.get("structure", 0.0))
	var applied := 0.0
	if shield_amt > 0.0 and shield_hp < max_shield:
		var add := minf(max_shield - shield_hp, shield_amt)
		shield_hp += add
		applied += add
	if armor_amt > 0.0 and armor_hp < max_armor:
		var add_a := minf(max_armor - armor_hp, armor_amt)
		armor_hp += add_a
		applied += add_a
	if structure_amt > 0.0 and structure_hp < max_structure:
		var add_s := minf(max_structure - structure_hp, structure_amt)
		structure_hp += add_s
		applied += add_s
	if _health_bar:
		_health_bar.call("refresh")
	return {"applied": applied, "full": is_heal_full_for_race(race_key)}
