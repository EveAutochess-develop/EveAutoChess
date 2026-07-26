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

var shield_hp: float = 0.0
var armor_hp: float = 0.0
var structure_hp: float = 0.0
var max_shield: float = 0.0
var max_armor: float = 0.0
var max_structure: float = 0.0
var attack_range: float = 1.0
var damage_emp: float = 0.0
var shield_resist_emp: float = 0.0
var armor_resist_emp: float = 0.0
var structure_resist_emp: float = 0.0
var attack_duration: float = 1.0
var last_attack_time: float = -999.0
var damage_pct_bonus: float = 0.0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _model_root: Node3D
var _health_bar: Node3D  # ShipHealthBar (avoid class_name cycle with ShipUnit)
## Bow muzzle in ShipUnit local space (after model normalize). Forward = −Z.
var _muzzle_local: Vector3 = Vector3(0.0, 0.4, -0.9)
## Combat aim (Variant so null clear is valid).
var combat_target = null

const _HEALTH_BAR_SCRIPT := preload("res://scripts/ship/ship_health_bar.gd")

func setup(p_ship_id: int, p_star: int, p_team: int) -> void:
	ship_id = p_ship_id
	star = p_star
	team_id = p_team
	_ensure_mesh()
	_ensure_health_bar()
	reload_stats()
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
	var path := DataStore.ship_mesh_path(ship_id)
	if path != "" and ResourceLoader.exists(path):
		var packed := load(path)
		if packed is PackedScene:
			_model_root = (packed as PackedScene).instantiate() as Node3D
			add_child(_model_root)
			# 3DS→glTF root matrix maps ship length onto +Y (stands upright).
			# +90° X lays flat with deck up; −90° would put belly up. Tunable via visual.json.
			var pitch := float(DataStore.visual.get("ship_model_pitch_deg", 90.0))
			var model_yaw := float(DataStore.visual.get("ship_model_yaw_deg", 180.0))
			_model_root.rotation_degrees = Vector3(pitch, model_yaw, 0.0)
			_normalize_model_scale(_model_root)
			_tint_model(_model_root)
			MobileModelLoad.apply_tree(_model_root)
			return
	# Fallback placeholder box
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.6, 1.8)
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.3, 0.55, 1.0) if team_id == TEAM_PLAYER else Color(1.0, 0.35, 0.3)
	_mesh.material_override = _mat
	add_child(_mesh)
	var sc := float(DataStore.visual.get("ship_visual_scale", 0.85))
	scale = Vector3.ONE * sc
	_muzzle_local = Vector3(0.0, 0.3, -0.9)

func _ensure_health_bar() -> void:
	if _health_bar != null:
		return
	_health_bar = _HEALTH_BAR_SCRIPT.new() as Node3D
	_health_bar.name = "HealthBar"
	add_child(_health_bar)
	_health_bar.call("setup", self)

func _normalize_model_scale(root: Node3D) -> void:
	## Fit longest AABB axis to target_size; center XZ on node origin; sit on ground.
	## After setting root.scale, further AABB must be in ShipUnit space (includes scale);
	## child-local AABB ignores root.scale and would lift the mesh by tens of units.
	var target := float(DataStore.visual.get("ship_target_size", 2.2))
	var aabb := _aabb_mesh_local(root)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest < 0.0001:
		return
	var sc := target / longest
	sc *= float(DataStore.visual.get("ship_visual_scale", 1.0))
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
	## ships_png/*_d are grayscale panel bakes (not painted albedo). Multiply by hull tint
	## so panel lines read; lights + normal give shape.
	var diffuse_path := DataStore.ship_diffuse_path(ship_id)
	var diffuse := UiAssets.tex_ship_bake(diffuse_path) if diffuse_path != "" else null
	var normal: Texture2D = null
	if diffuse_path != "" and diffuse_path.ends_with("_d.png"):
		normal = UiAssets.tex_ship_bake(diffuse_path.replace("_d.png", "_n.png"))
	if diffuse == null and diffuse_path != "":
		push_warning("ShipUnit missing diffuse ship_id=%s path=%s" % [ship_id, diffuse_path])
	# Amarr gold hull + team lean (player cooler / AI warmer).
	var hull := Color(0.92, 0.78, 0.48)
	var team := Color(0.45, 0.62, 1.0) if team_id == TEAM_PLAYER else Color(1.0, 0.42, 0.38)
	hull = hull.lerp(team, 0.18)
	for mi in _find_meshes(root):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.texture_repeat = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if diffuse:
			mat.albedo_texture = diffuse
			mat.albedo_color = hull
			mat.ao_enabled = true
			mat.ao_texture = diffuse
			mat.ao_light_affect = 0.4
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		else:
			mat.albedo_color = hull.darkened(0.1)
		if normal:
			mat.normal_enabled = true
			mat.normal_texture = normal
			mat.normal_scale = 1.15
		mat.metallic = 0.22
		mat.metallic_specular = 0.35
		mat.roughness = 0.42
		mi.material_override = mat
		mi.material_overlay = null
		if mi.mesh:
			for si in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(si, mat)

func set_combat_tint(in_combat: bool) -> void:
	if is_destroyed:
		return
	if _mat:
		var base := Color(0.3, 0.55, 1.0) if team_id == TEAM_PLAYER else Color(1.0, 0.35, 0.3)
		_mat.albedo_color = base.lightened(0.2) if in_combat else base
	elif _model_root:
		var team := Color(0.55, 0.72, 1.0) if team_id == TEAM_PLAYER else Color(1.0, 0.52, 0.48)
		for mi in _find_meshes(_model_root):
			if mi.material_override is StandardMaterial3D:
				var mat := mi.material_override as StandardMaterial3D
				if mat.albedo_texture:
					mat.emission_enabled = true
					mat.emission = team * (0.2 if in_combat else 0.08)
					mat.emission_energy_multiplier = 0.55 if in_combat else 0.35
				else:
					var c := Color(0.22, 0.24, 0.28).lerp(team, 0.35)
					mat.albedo_color = c.lightened(0.18) if in_combat else c

func reload_stats() -> void:
	var st: Dictionary = DataStore.get_star(ship_id, star)
	if st.is_empty():
		return
	var ship := DataStore.get_ship(ship_id)
	is_logistic = bool(ship.get("is_logistic", false)) or bool(st.get("is_logistic", false))
	attack_range = float(st.get("attack_range", 1))
	var dmg: Dictionary = st.get("damage", {})
	damage_emp = float(dmg.get("emp", 0))
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
	shield_resist_emp = float(sr.get("emp", 0))
	armor_resist_emp = float(ar.get("emp", 0))
	structure_resist_emp = float(str_res.get("emp", armor_resist_emp))
	var cd := DataStore.combat
	attack_duration = float(cd.get("logistic_attack_duration_s" if is_logistic else "attack_duration_s", 1.0))
	is_destroyed = false
	visible = true
	if _health_bar:
		_health_bar.visible = true
		_health_bar.call("refresh")

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

func apply_hit(raw_emp: float) -> Dictionary:
	## Returns {destroyed:bool, dealt:float}. Layers: shield → armor → structure; overflow discarded between layers.
	if is_destroyed or raw_emp <= 0.0:
		return {"destroyed": is_destroyed, "dealt": 0.0}
	var min_pct := float(DataStore.combat.get("min_damage_pct", 0.25))
	var resist := shield_resist_emp
	if shield_hp <= 0.0:
		resist = armor_resist_emp if armor_hp > 0.0 else structure_resist_emp
	var dealt := maxf(raw_emp * min_pct, raw_emp - resist)
	dealt = maxf(dealt, raw_emp * min_pct)
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
	## Returns true if fully topped (armor then shield; structure unchanged).
	if is_destroyed:
		return true
	var need_a := max_armor - armor_hp
	var use := minf(need_a, amount)
	armor_hp += use
	amount -= use
	if amount > 0.0:
		shield_hp = minf(max_shield, shield_hp + amount)
	if _health_bar:
		_health_bar.call("refresh")
	return shield_hp >= max_shield and armor_hp >= max_armor and structure_hp >= max_structure
