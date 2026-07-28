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
var is_unmanned: bool = false
var unmanned_kind: String = ""
var drone_bandwidth: float = 0.0
var drone_bay_slots: int = 0  # 发射管 / active drone quota
var _plugin_modules: Array = []
var mother_ship_id: int = 0  # instance id of carrier when combat_drone

var shield_hp: float = 0.0
var armor_hp: float = 0.0
var structure_hp: float = 0.0
var max_shield: float = 0.0
var max_armor: float = 0.0
var max_structure: float = 0.0
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
var fetter_repair_mul: float = 1.0
var fetter_speed_mul: float = 1.0
var _base_shield_resist_emp: float = 0.0
var _base_armor_resist_emp: float = 0.0
var _base_structure_resist_emp: float = 0.0
var _shield_resist: Dictionary = {}
var _armor_resist: Dictionary = {}
var _structure_resist: Dictionary = {}

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
var retreat_until_time: float = -1.0
var no_target_acc: float = 0.0
var _stat_modifiers: Array = []

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _model_root: Node3D
var _health_bar: Node3D  # ShipHealthBar (avoid class_name cycle with ShipUnit)
## Bow muzzle in ShipUnit local space (after model normalize). Forward = −Z.
var _muzzle_local: Vector3 = Vector3(0.0, 0.4, -0.9)
## Normalized display longest edge (world units) after scale curve — for load precision.
var _model_display_size: float = -1.0
## Combat aim (Variant so null clear is valid).
var combat_target = null

const _HEALTH_BAR_SCRIPT := preload("res://scripts/ship/ship_health_bar.gd")
const _ECHOES_SURFACE_SHADER := preload("res://shaders/echoes_spaceobject.gdshader")

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
	_ensure_mesh()
	_ensure_health_bar()
	var yaw := float(DataStore.visual.get("player_yaw_deg" if team_id == TEAM_PLAYER else "ai_yaw_deg", 0.0))
	rotation_degrees = Vector3(0, yaw, 0)

## Yaw so local −Z faces flat XZ direction (Godot forward).
func face_dir_xz(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	rotation.y = atan2(-flat.x, -flat.z)

func restore_team_yaw() -> void:
	var yaw := float(DataStore.visual.get("player_yaw_deg" if team_id == TEAM_PLAYER else "ai_yaw_deg", 0.0))
	rotation_degrees = Vector3(0, yaw, 0)

func _ensure_mesh() -> void:
	if _model_root or _mesh:
		return
	var path := DataStore.ship_mesh_path_resolved(ship_id)
	if path != "" and ResourceLoader.exists(path):
		var packed := load(path)
		if packed is PackedScene:
			_model_root = (packed as PackedScene).instantiate() as Node3D
			add_child(_model_root)
			_apply_model_orientation(_model_root)
			_normalize_model_scale(_model_root)
			_tint_model(_model_root)
			MobileModelLoad.apply_tree(_model_root, _model_display_size)
			return
	## Missing model: leave empty (no placeholder box). Drop-in §0 bundle restores mesh.
	_muzzle_local = Vector3(0.0, 0.3, -0.9)

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

func _apply_model_orientation(root: Node3D) -> void:
	## Lay hull flat: longest axis → length (local Z), up stays Y when possible.
	var pitch := float(DataStore.visual.get("ship_model_pitch_deg", 0.0))
	var model_yaw := float(DataStore.visual.get("ship_model_yaw_deg", 180.0))
	var model_roll := float(DataStore.visual.get("ship_model_roll_deg", 0.0))
	if bool(DataStore.visual.get("ship_model_auto_orient", true)):
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
	var axis := float(DataStore.get_ship(ship_id).get("model_long_axis", 0.0))
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
		sc *= float(DataStore.visual.get("unmanned_visual_scale_mul", 0.125))
	root.scale = Vector3.ONE * sc
	aabb = _aabb_in_ship_space(root)
	var center := aabb.get_center()
	root.position.x -= center.x
	root.position.z -= center.z
	aabb = _aabb_in_ship_space(root)
	root.position.y -= aabb.position.y
	# Bow muzzle in ShipUnit local (forward −Z tip).
	aabb = _aabb_in_ship_space(root)
	var mid_y := maxf(aabb.get_center().y, aabb.size.y * 0.35)
	_muzzle_local = Vector3(0.0, mid_y, aabb.position.z)

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
		return global_transform * aabb.get_center()
	return global_position

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
	var diffuse_path := DataStore.ship_diffuse_path(ship_id)
	var key := str(DataStore.get_ship(ship_id).get("model_key", ""))
	var bundle := DataStore.resolve_model_bundle(key)
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
	for mi in _find_meshes(root):
		var mat: Material
		if diffuse and normal and pmwo and rg_tex and reduction:
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
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			if diffuse:
				std.albedo_texture = diffuse
				std.albedo_color = Color.WHITE
				std.ao_enabled = false
			else:
				## No albedo — fall back to a neutral hull tone, not race/team tint.
				std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				std.albedo_color = neutral
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
			mat = std
		mi.material_override = mat
		mi.material_overlay = null
		if mi.mesh:
			for si in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(si, mat)

func _texture_file_ok(path: String) -> bool:
	if path == "":
		return false
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
		return
	if _mat:
		var neutral := Color(0.82, 0.84, 0.88, 1.0)
		_mat.albedo_color = neutral.lightened(0.06) if in_combat else neutral
	elif _model_root:
		var neutral := Color(0.82, 0.84, 0.88, 1.0)
		for mi in _find_meshes(_model_root):
			if mi.material_override is ShaderMaterial:
				var smat := mi.material_override as ShaderMaterial
				smat.set_shader_parameter("team_tint", Color.WHITE)
				smat.set_shader_parameter("team_mix", 0.0)
				smat.set_shader_parameter("combat_emission_strength", 0.08 if in_combat else 0.0)
			elif mi.material_override is StandardMaterial3D:
				var mat := mi.material_override as StandardMaterial3D
				if mat.albedo_texture:
					mat.emission_enabled = true
					mat.emission = Color.WHITE
					mat.emission_energy_multiplier = 0.18 if in_combat else 0.0
				else:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.albedo_color = neutral.lightened(0.06) if in_combat else neutral
					mat.emission_enabled = false

func reload_stats() -> void:
	var st: Dictionary = DataStore.get_star(ship_id, star)
	if st.is_empty():
		return
	var ship := DataStore.get_ship(ship_id)
	is_logistic = bool(ship.get("is_logistic", false)) or bool(st.get("is_logistic", false))
	race = str(ship.get("race", "amarr")).to_lower()
	attack_range = float(st.get("attack_range", 1))
	var dmg: Dictionary = st.get("damage", {})
	damage_emp = float(dmg.get("emp", 0))
	damage_thermal = float(dmg.get("thermal", 0))
	damage_kinetic = float(dmg.get("kinetic", 0))
	damage_explosive = float(dmg.get("explosive", 0))
	var rep: Dictionary = st.get("repair", {})
	repair_shield = float(rep.get("shield", 0))
	repair_armor = float(rep.get("armor", 0))
	repair_structure = float(rep.get("structure", 0))
	max_shield = float(st.get("shield_hp", 0))
	max_armor = float(st.get("armor_hp", 0))
	if st.has("structure_hp"):
		max_structure = float(st.get("structure_hp", 0))
	else:
		max_structure = maxf(50.0, roundf(max_armor * 0.5))
	shield_hp = max_shield
	armor_hp = max_armor
	structure_hp = max_structure
	var sr: Dictionary = st.get("shield_resist", {})
	var ar: Dictionary = st.get("armor_resist", {})
	var str_res: Dictionary = st.get("structure_resist", ar if typeof(ar) == TYPE_DICTIONARY else {})
	_shield_resist = sr.duplicate()
	_armor_resist = ar.duplicate()
	_structure_resist = str_res.duplicate()
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
	if cycle <= 0.0:
		cycle = float(cd.get("logistic_attack_duration_s" if is_logistic else "attack_duration_s", 1.0))
	var cap_s := float(cd.get("attack_cycle_cap_s", 6.0))
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
	retreat_until_time = -1.0
	no_target_acc = 0.0
	combat_target = null
	last_attack_time = -999.0
	_stat_modifiers.clear()

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
	var m_per_cell := float(DataStore.combat.get("meters_per_cell", 500.0))
	var spd := get_stat("speed", base_speed)
	var mapped := spd / m_per_cell * wu * move_scale * fetter_speed_mul
	var speed := maxf(mapped, 0.5)
	if absf(global_position.z) < float(DataStore.combat.get("isolation_half_width_wu", 2.5)):
		speed *= float(DataStore.combat.get("isolation_speed_mul", 0.7))
	return speed

func cap_fraction() -> float:
	if cap_capacity <= 0.0:
		return 1.0
	return cap_current / cap_capacity

func attacks_enabled() -> bool:
	var frac_need := float(DataStore.combat.get("cap_disable_attack_function_pct", 0.10))
	return cap_fraction() >= frac_need

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
	if cap_capacity <= 0.0:
		cap_current = 0.0
		return
	var rate := cap_capacity / cap_recharge_s
	cap_current = minf(cap_capacity, cap_current + rate * sim_dt)

func consume_cap_for_cycle() -> void:
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
		lock_timer = 0.0
		lock_duration_s = CombatFormulas.lock_time_s(scan_resolution, target.signature_radius)

func advance_lock(sim_dt: float) -> void:
	if lock_target_id == 0:
		return
	lock_timer += sim_dt

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
	var mul := 1.0 + damage_pct_bonus / 100.0
	return {
		"emp": damage_emp * mul,
		"thermal": damage_thermal * mul,
		"kinetic": damage_kinetic * mul,
		"explosive": damage_explosive * mul,
	}

func sum_damage_amount(dmg: Dictionary) -> float:
	return float(dmg.get("emp", 0.0)) + float(dmg.get("thermal", 0.0)) + float(dmg.get("kinetic", 0.0)) + float(dmg.get("explosive", 0.0))

func heal_dict_scaled() -> Dictionary:
	var mul := float(DataStore.combat.get("logistic_heal_multiplier", 2.0)) * fetter_repair_mul
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

func world_range_cells() -> float:
	return attack_range

func world_range_wu() -> float:
	return world_range()

func apply_fetter_mods(shield_mul: float, armor_mul: float, repair_mul: float, speed_mul: float) -> void:
	fetter_repair_mul = repair_mul
	fetter_speed_mul = speed_mul
	shield_resist_emp = minf(0.90, _base_shield_resist_emp * shield_mul)
	armor_resist_emp = minf(0.90, _base_armor_resist_emp * armor_mul)
	structure_resist_emp = minf(0.90, _base_structure_resist_emp * armor_mul)

func upgrade_level() -> void:
	if star < 3:
		star += 1
		reload_stats()

func get_cost() -> int:
	return int(DataStore.get_ship(ship_id).get("cost", 0))

func world_range() -> float:
	return attack_range * float(DataStore.combat.get("weapon_range_scale", 3.0))

## World-space muzzle ≈ turret: cached ShipUnit-local bow (3DS meshes have no hardpoints).
func get_muzzle_global() -> Vector3:
	return to_global(_muzzle_local)

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
	## Returns {destroyed:bool, dealt:float}. Layers: shield → armor → structure; overflow discarded between layers.
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
	if shield_hp > 0.0:
		shield_hp = maxf(0.0, shield_hp - dealt)
	elif armor_hp > 0.0:
		armor_hp = maxf(0.0, armor_hp - dealt)
	else:
		structure_hp -= dealt
	if shield_hp <= 0.0 and armor_hp <= 0.0 and structure_hp <= 0.0:
		is_destroyed = true
		visible = false
		if _health_bar:
			_health_bar.visible = false
		return {"destroyed": true, "dealt": dealt}
	if _health_bar:
		_health_bar.call("refresh")
	return {"destroyed": false, "dealt": dealt}

func apply_heal(amount: float) -> bool:
	## Legacy flat heal — prefer apply_heal_racial.
	return apply_heal_racial("minmatar", {"shield": amount * 0.5, "armor": amount * 0.5, "structure": 0.0})

func apply_heal_racial(source_race: String, amounts: Dictionary) -> bool:
	if is_destroyed:
		return true
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
	if shield_amt > 0.0 and shield_hp < max_shield:
		var room := max_shield - shield_hp
		shield_hp += minf(room, shield_amt)
	if armor_amt > 0.0 and armor_hp < max_armor:
		var room_a := max_armor - armor_hp
		armor_hp += minf(room_a, armor_amt)
	if structure_amt > 0.0 and structure_hp < max_structure:
		var room_s := max_structure - structure_hp
		structure_hp += minf(room_s, structure_amt)
	if _health_bar:
		_health_bar.call("refresh")
	return is_heal_full_for_race(race_key)
