extends Node3D
## Dev preview: focus ship-shield ellipsoid under cycling turret fire (COMBAT §8.3).
## Ellipsoid from mesh vertex axis extremes on model_root; attacks stop via play_to_anchor.

const FiringFxScript = preload("res://scripts/combat/firing_fx.gd")

const _CAM_MOVE_SPEED: float = 28.0
const _LOOK_SENS: float = 0.22
const _WHEEL_STEP: float = 3.2
const _MANIFEST: String = "res://assets/vfx/defense_stance/manifest.json"
const _SHADER: String = "res://shaders/defense_stance_fx.gdshader"
const _SHIP_ID: int = 12
const _UNIT_SPHERE_R: float = 0.5
const _ELLIPSOID_PAD: float = 1.12
const _SHIELD_IDLE_VIS: float = 0.03
const _SHIELD_HARDEN_VIS: float = 0.12
const _HIT_FLASH_S: float = 0.425
const _SHIELD_MAX: float = 100.0
const _SHIELD_DAMAGE: float = 25.0
const _SHIELD_REGEN_DELAY_S: float = 2.2
const _ATTACK_GAP_S: float = 1.2
const _BEAM_DUR_S: float = 0.95
const _ATTACK_RING: float = 11.5
const _EDGE: float = 20.0

const ATTACKERS: Array = [
	{"kind": "laser", "ship_id": 1, "yaw_deg": 0.0},
	{"kind": "rail", "ship_id": 11, "yaw_deg": 90.0},
	{"kind": "cannon", "ship_id": 21, "yaw_deg": 180.0},
	{"kind": "missile", "ship_id": 16, "yaw_deg": 270.0},
]

const EDGE_STANCE: Array = [
	{"kind": "shield_sphere", "label": "护盾立场", "pos": [-_EDGE, 0.0, -_EDGE], "scale": 1.8},
	{"kind": "armor_sphere", "label": "装甲连接立场", "pos": [_EDGE, 0.0, -_EDGE], "scale": 1.8},
]

var _cam: Camera3D
var _hud: Label
var _edit_bright: LineEdit
var _edit_alpha: LineEdit
var _world: Node3D
var _firing_fx: FiringFxScript
var _cam_base_pos: Vector3 = Vector3(0, 14, 26)
var _cam_base_pitch_deg: float = -22.0
var _cam_base_yaw_deg: float = 0.0
var _look_dragging: bool = false
var _paused: bool = false
var _roles: Dictionary = {}

var _target: ShipUnit
var _shield_mi: MeshInstance3D
var _shield_mat: ShaderMaterial
var _shield_center_local: Vector3 = Vector3.ZERO
var _shield_radii: Vector3 = Vector3.ONE
var _ship_shield_harden: bool = false ## optional weak idle boost (H)
var _shield_hp: float = _SHIELD_MAX
var _shield_regen_t: float = 0.0
var _hp_label: Label3D
var _last_hit_dir_obj: Vector3 = Vector3(0.0, 1.0, 0.0)

var _attackers: Array[ShipUnit] = []
var _attack_kinds: Array[String] = []
var _attack_i: int = 0
var _attack_t: float = 0.0
var _hit_anchor: Marker3D
## Typed numeric tune (LineEdit).
var _hit_brightness: float = 8.0
var _hit_peak_alpha: float = 0.36


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	if DataStore != null and DataStore.has_method("reload_all"):
		DataStore.reload_all()
	_load_manifest()
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_build_env()
	_build_board()
	_firing_fx = FiringFxScript.new()
	_firing_fx.name = "FiringFx"
	add_child(_firing_fx)
	_firing_fx.force_full_fx = true
	_firing_fx.setup(_world)
	_build_center_shield()
	_build_edge_stances()
	_build_attackers()
	_build_hud()
	_apply_ship_shield_idle()
	_refresh_hud()
	print("[DefenseStanceFxPreview] type numbers for bright/alpha · shield glow owned by FiringFx")


func _load_manifest() -> void:
	_roles.clear()
	if not FileAccess.file_exists(_MANIFEST):
		push_warning("[DefenseStanceFxPreview] missing %s" % _MANIFEST)
		return
	var f: FileAccess = FileAccess.open(_MANIFEST, FileAccess.READ)
	if f == null:
		return
	_roles = TypedVariant.as_dict(JSON.parse_string(f.get_as_text()))
	f.close()


func _build_center_shield() -> void:
	_target = ShipUnit.new()
	_target.name = "ShieldHost"
	_world.add_child(_target)
	_target.setup(_SHIP_ID, 1, ShipUnit.TEAM_PLAYER)
	_target.global_position = Vector3.ZERO
	## Flush transforms so ship-space hull match visual_center (model_root Y seat included).
	_target.force_update_transform()
	if _target.has_method("model_root"):
		var mr0: Node3D = _target.model_root()
		if mr0 != null and is_instance_valid(mr0):
			mr0.force_update_transform()

	## Parent to ShipUnit (not model_root alone) so Y matches visual_center_world.
	var fx_root: Node3D = Node3D.new()
	fx_root.name = "ShipShieldFx"
	_target.add_child(fx_root)

	_shield_mi = MeshInstance3D.new()
	_shield_mi.set_meta("defense_fx", true)
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = _UNIT_SPHERE_R
	sph.height = _UNIT_SPHERE_R * 2.0
	sph.radial_segments = 48
	sph.rings = 24
	_shield_mi.mesh = sph
	_refit_shield_ellipsoid()
	_shield_mat = _make_shell_mat("ship_shield")
	_shield_mi.material_override = _shield_mat
	fx_root.add_child(_shield_mi)

	_hit_anchor = Marker3D.new()
	_hit_anchor.name = "ShieldHitAnchor"
	_world.add_child(_hit_anchor)

	_hp_label = Label3D.new()
	_hp_label.text = "舰船护盾"
	_hp_label.font_size = 32
	_hp_label.outline_size = 8
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_target.add_child(_hp_label)
	_place_hp_label()
	_shield_hp = _SHIELD_MAX
	_update_hp_label()
	## One-frame late refit after MobileModelLoad / yaw settle.
	call_deferred("_refit_shield_ellipsoid")


func _refit_shield_ellipsoid() -> void:
	if _target == null or not is_instance_valid(_target) or _shield_mi == null:
		return
	_target.force_update_transform()
	if _target.has_method("model_root"):
		var mr: Node3D = _target.model_root()
		if mr != null and is_instance_valid(mr):
			mr.force_update_transform()
	## Ship-local vertex extremes (same space as visual_center_world).
	var aabb: AABB = _hull_vertex_extremes_in(_target, _target)
	if aabb.size.length_squared() < 1e-6:
		aabb = _hull_aabb_in(_target, _target)
	if aabb.size.length_squared() < 1e-6:
		aabb = AABB(Vector3(-1.2, -0.5, -1.6), Vector3(2.4, 1.0, 3.2))
	var padded: Vector3 = aabb.size * _ELLIPSOID_PAD
	padded.x = maxf(padded.x, 0.35)
	padded.y = maxf(padded.y, 0.25)
	padded.z = maxf(padded.z, 0.35)
	_shield_center_local = aabb.get_center()
	_shield_mi.position = _shield_center_local
	_shield_mi.scale = padded
	_shield_radii = padded * _UNIT_SPHERE_R
	_place_hp_label()


func _place_hp_label() -> void:
	if _hp_label == null:
		return
	_hp_label.position = Vector3(
		_shield_center_local.x,
		_shield_center_local.y + _shield_radii.y + 0.55,
		_shield_center_local.z
	)


func _build_edge_stances() -> void:
	for row_v: Variant in EDGE_STANCE:
		var row: Dictionary = TypedVariant.as_dict(row_v)
		var kind: String = str(row.get("kind", ""))
		var pos_a: Array = TypedVariant.as_array(row.get("pos", [-_EDGE, 0.0, -_EDGE]))
		var pos: Vector3 = Vector3(
			TypedVariant.as_float(pos_a[0] if pos_a.size() > 0 else -_EDGE, -_EDGE),
			TypedVariant.as_float(pos_a[1] if pos_a.size() > 1 else 0.0, 0.0),
			TypedVariant.as_float(pos_a[2] if pos_a.size() > 2 else -_EDGE, -_EDGE)
		)
		var ship: ShipUnit = ShipUnit.new()
		ship.name = "Edge_%s" % kind
		_world.add_child(ship)
		ship.setup(_SHIP_ID, 1, ShipUnit.TEAM_AI)
		ship.global_position = pos
		var fx: Node3D = Node3D.new()
		ship.add_child(fx)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.set_meta("defense_fx", true)
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = _UNIT_SPHERE_R
		sph.height = _UNIT_SPHERE_R * 2.0
		sph.radial_segments = 32
		sph.rings = 16
		mi.mesh = sph
		var radius: float = _shell_radius(ship, TypedVariant.as_float(row.get("scale", 1.8), 1.8))
		mi.scale = Vector3.ONE * (radius / _UNIT_SPHERE_R)
		mi.material_override = _make_shell_mat(kind)
		fx.add_child(mi)
		var lab: Label3D = Label3D.new()
		lab.text = str(row.get("label", kind))
		lab.font_size = 22
		lab.outline_size = 5
		lab.position = Vector3(0.0, radius + 0.8, 0.0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ship.add_child(lab)


func _build_attackers() -> void:
	_attackers.clear()
	_attack_kinds.clear()
	for row_v: Variant in ATTACKERS:
		var row: Dictionary = TypedVariant.as_dict(row_v)
		var kind: String = str(row.get("kind", "laser"))
		var yaw: float = TypedVariant.as_float(row.get("yaw_deg", 0.0), 0.0)
		var rad: float = deg_to_rad(yaw)
		var pos: Vector3 = Vector3(sin(rad) * _ATTACK_RING, 0.0, -cos(rad) * _ATTACK_RING)
		var ship: ShipUnit = ShipUnit.new()
		ship.name = "Atk_%s" % kind
		_world.add_child(ship)
		ship.setup(TypedVariant.as_int(row.get("ship_id", 1), 1), 1, ShipUnit.TEAM_AI)
		ship.global_position = pos
		## Face the center shield host.
		ship.look_at(Vector3(0.0, ship.global_position.y, 0.0), Vector3.UP)
		_attackers.append(ship)
		_attack_kinds.append(kind)
		var lab: Label3D = Label3D.new()
		lab.text = kind
		lab.font_size = 24
		lab.outline_size = 6
		lab.position = Vector3(0.0, 2.2, 0.0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ship.add_child(lab)


func _make_shell_mat(kind: String) -> ShaderMaterial:
	var sh: Shader = load(_SHADER) as Shader
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = sh
	var role: Dictionary = TypedVariant.as_dict(_roles.get(kind, {}))
	var tint_a: Array = TypedVariant.as_array(role.get("tint", [0.5, 0.8, 1.0, 0.65]))
	var tint: Color = Color(0.5, 0.8, 1.0, 0.65)
	if tint_a.size() >= 4:
		tint = Color(
			TypedVariant.as_float(tint_a[0], 0.5),
			TypedVariant.as_float(tint_a[1], 0.8),
			TypedVariant.as_float(tint_a[2], 1.0),
			TypedVariant.as_float(tint_a[3], 0.65)
		)
	mat.set_shader_parameter("tint", tint)
	var shell_tex: Texture2D = _load_tex(str(role.get("tex_shell", "")))
	var flow_tex: Texture2D = _load_tex(str(role.get("tex_flow", role.get("tex_shell", ""))))
	if shell_tex != null:
		mat.set_shader_parameter("tex_shell", shell_tex)
	if flow_tex != null:
		mat.set_shader_parameter("tex_flow", flow_tex)
	var is_ship: bool = kind == "ship_shield"
	mat.set_shader_parameter("scroll_speed", 0.85 if is_ship else 0.45)
	mat.set_shader_parameter("flow_mix", 0.55 if is_ship else 0.4)
	mat.set_shader_parameter("emission_boost", 2.6 if is_ship else 1.8)
	mat.set_shader_parameter("uv_scale", Vector2(1.4, 1.4) if is_ship else Vector2(2.0, 2.0))
	mat.set_shader_parameter("rim_power", 1.55 if is_ship else 2.1)
	mat.set_shader_parameter("pulse", 1.0)
	mat.set_shader_parameter("visibility", _SHIELD_IDLE_VIS if is_ship else 0.75)
	mat.set_shader_parameter("hit_glow", 0.0)
	mat.set_shader_parameter("hit_peak_alpha", _hit_peak_alpha)
	mat.set_shader_parameter("hit_emit_boost", _hit_brightness)
	mat.set_shader_parameter("hit_dir_obj", Vector3(0.0, 1.0, 0.0))
	return mat


func _load_tex(res_path: String) -> Texture2D:
	if res_path.is_empty():
		return null
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img: Image = Image.new()
		if img.load(abs_path) == OK:
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(res_path):
		return load(res_path) as Texture2D
	return null


## Axis extremes from real mesh vertices in `space` local (凸起点), excluding FX shells.
func _hull_vertex_extremes_in(space: Node3D, ship: ShipUnit) -> AABB:
	var first: bool = true
	var result: AABB = AABB()
	var inv: Transform3D = space.global_transform.affine_inverse()
	for mi: MeshInstance3D in _collect_hull_meshes(ship):
		if mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		for s: int in range(mi.mesh.get_surface_count()):
			var arr: Array = mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var step: int = maxi(1, int(verts.size() / 1200.0))
			var i: int = 0
			while i < verts.size():
				var p: Vector3 = xf * verts[i]
				if first:
					result = AABB(p, Vector3.ZERO)
					first = false
				else:
					result = result.expand(p)
				i += step
	return result


func _hull_aabb_in(space: Node3D, ship: ShipUnit) -> AABB:
	var first: bool = true
	var result: AABB = AABB()
	var inv: Transform3D = space.global_transform.affine_inverse()
	for mi: MeshInstance3D in _collect_hull_meshes(ship):
		var local_aabb: AABB = mi.get_aabb()
		if local_aabb.size.length_squared() < 1e-12:
			continue
		var xf: Transform3D = inv * mi.global_transform
		for ei: int in range(8):
			var p: Vector3 = xf * local_aabb.get_endpoint(ei)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	return result


func _collect_hull_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_hull_meshes_rec(n, out)
	return out


func _collect_hull_meshes_rec(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		if not TypedVariant.as_bool(mi.get_meta("defense_fx", false), false):
			out.append(mi)
	for c: Node in n.get_children():
		_collect_hull_meshes_rec(c, out)


func _shell_radius(ship: ShipUnit, scale_mul: float) -> float:
	var base: float = 1.6
	if ship != null and ship.has_method("get_model_display_size"):
		base = maxf(0.6, TypedVariant.as_float(ship.call("get_model_display_size"), 1.6) * 0.55)
	return base * scale_mul


func _shield_center_world() -> Vector3:
	if _shield_mi != null and is_instance_valid(_shield_mi):
		return _shield_mi.global_position
	if _target == null or not is_instance_valid(_target):
		return Vector3.ZERO
	return _target.to_global(_shield_center_local)


func _shield_radii_world() -> Vector3:
	## Live half-extents from scaled unit sphere (follows model_root transform).
	if _shield_mi != null and is_instance_valid(_shield_mi):
		var b: Basis = _shield_mi.global_transform.basis
		return Vector3(
			maxf(b.x.length() * _UNIT_SPHERE_R, 0.05),
			maxf(b.y.length() * _UNIT_SPHERE_R, 0.05),
			maxf(b.z.length() * _UNIT_SPHERE_R, 0.05)
		)
	var r: Vector3 = _shield_radii
	r.x = maxf(r.x, 0.05)
	r.y = maxf(r.y, 0.05)
	r.z = maxf(r.z, 0.05)
	return r


## Ray along from → aim (model center), clipped to shield surface.
func _ray_hit_shield_toward(from_w: Vector3, aim_w: Vector3) -> Vector3:
	var center: Vector3 = _shield_center_world()
	var radii: Vector3 = _shield_radii_world()
	var dir: Vector3 = aim_w - from_w
	if dir.length_squared() < 1e-8:
		dir = center - from_w
	if dir.length_squared() < 1e-8:
		return center + Vector3(0, radii.y, 0)
	dir = dir.normalized()
	var o: Vector3 = Vector3(
		(from_w.x - center.x) / radii.x,
		(from_w.y - center.y) / radii.y,
		(from_w.z - center.z) / radii.z
	)
	var d: Vector3 = Vector3(dir.x / radii.x, dir.y / radii.y, dir.z / radii.z)
	var a: float = d.dot(d)
	var b: float = 2.0 * o.dot(d)
	var c: float = o.dot(o) - 1.0
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0 or a < 1e-12:
		## Miss ellipsoid: still land on shell toward aim.
		var outward: Vector3 = (aim_w - center)
		if outward.length_squared() < 1e-8:
			outward = from_w - center
		outward = outward.normalized()
		return center + Vector3(outward.x * radii.x, outward.y * radii.y, outward.z * radii.z)
	var sqrt_d: float = sqrt(disc)
	var t0: float = (-b - sqrt_d) / (2.0 * a)
	var t1: float = (-b + sqrt_d) / (2.0 * a)
	## Near intersection along aim ray (clip before piercing to model center).
	var t: float = t0 if t0 > 0.001 else t1
	if t < 0.001:
		t = maxf(t0, t1)
	var local_u: Vector3 = o + d * t
	return center + Vector3(local_u.x * radii.x, local_u.y * radii.y, local_u.z * radii.z)


func _has_shield() -> bool:
	return _shield_hp > 0.001


func _model_center_world() -> Vector3:
	if _target != null and is_instance_valid(_target) and _target.has_method("visual_center_world"):
		return _target.visual_center_world()
	return _shield_center_world()


func _hit_dir_mesh_local(hit_w: Vector3) -> Vector3:
	if _shield_mi == null or not is_instance_valid(_shield_mi):
		return Vector3(0.0, 1.0, 0.0)
	var local: Vector3 = _shield_mi.to_local(hit_w)
	if local.length_squared() < 1e-8:
		return Vector3(0.0, 1.0, 0.0)
	return local.normalized()


func _update_hp_label() -> void:
	if _hp_label == null:
		return
	if _has_shield():
		_hp_label.text = "舰船护盾  %.0f / %.0f" % [_shield_hp, _SHIELD_MAX]
	else:
		_hp_label.text = "破盾 · 落点=舰心  (%.1fs回满)" % maxf(0.0, _shield_regen_t)


func _apply_damage_to_shield() -> void:
	if not _has_shield():
		return
	_shield_hp = maxf(0.0, _shield_hp - _SHIELD_DAMAGE)
	if _shield_hp <= 0.001:
		_shield_hp = 0.0
		_shield_regen_t = _SHIELD_REGEN_DELAY_S
	_update_hp_label()


func _fire_next_attacker() -> void:
	if _attackers.is_empty() or _firing_fx == null:
		return
	var i: int = _attack_i % _attackers.size()
	_attack_i = (_attack_i + 1) % _attackers.size()
	var firer: ShipUnit = _attackers[i]
	var kind: String = _attack_kinds[i]
	if firer == null or not is_instance_valid(firer):
		return
	_read_tune_fields()
	var muzzle: Vector3 = firer.get_muzzle_global() if firer.has_method("get_muzzle_global") else firer.global_position
	## Ballistics always aim at model center; with shield, stop/clip on shell along that ray.
	var aim: Vector3 = _model_center_world()
	var hit: Vector3 = aim
	var shielded: bool = _has_shield()
	var shield_hit: Dictionary = {}
	if shielded:
		hit = _ray_hit_shield_toward(muzzle, aim)
		_last_hit_dir_obj = _hit_dir_mesh_local(hit)
		_apply_damage_to_shield()
		## Shield glow is owned by FiringFx (same tick as attack shot).
		shield_hit = {
			"mat": _shield_mat,
			"hit_dir": _last_hit_dir_obj,
			"peak_alpha": _hit_peak_alpha,
			"emit_boost": _hit_brightness,
			"base_vis": _SHIELD_HARDEN_VIS if _ship_shield_harden else _SHIELD_IDLE_VIS,
			"flash_s": _HIT_FLASH_S,
		}
		_apply_ship_shield_idle()
	_hit_anchor.global_position = hit
	_firing_fx.play_to_anchor(firer, _hit_anchor, kind, _BEAM_DUR_S, shield_hit)
	if firer.has_method("advance_muzzle"):
		firer.advance_muzzle()
	if not shielded:
		_apply_ship_shield_idle()


func _apply_ship_shield_idle() -> void:
	if _shield_mat == null or _shield_mi == null:
		return
	var up: bool = _has_shield()
	_shield_mi.visible = up
	if not up:
		_shield_mat.set_shader_parameter("hit_glow", 0.0)
		_shield_mat.set_shader_parameter("visibility", 0.0)
		return
	var base_vis: float = _SHIELD_HARDEN_VIS if _ship_shield_harden else _SHIELD_IDLE_VIS
	_shield_mat.set_shader_parameter("visibility", base_vis)
	_shield_mat.set_shader_parameter("hit_peak_alpha", _hit_peak_alpha)
	_shield_mat.set_shader_parameter("hit_emit_boost", _hit_brightness)
	## hit_glow driven exclusively by FiringFx while a shot is alive.


func _process(delta: float) -> void:
	_drive_camera(delta)
	## Broken shield → wait → refill (full↔empty cycle).
	if not _has_shield() and _shield_regen_t > 0.0:
		_shield_regen_t = maxf(0.0, _shield_regen_t - delta)
		if _shield_regen_t <= 0.0:
			_shield_hp = _SHIELD_MAX
			_apply_ship_shield_idle()
		_update_hp_label()
	if not _paused:
		_attack_t += delta
		if _attack_t >= _ATTACK_GAP_S:
			_attack_t = 0.0
			_fire_next_attacker()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			## Typing in LineEdit — don't steal digit/Enter for fire.
			var focus: Control = get_viewport().gui_get_focus_owner()
			if focus is LineEdit:
				if k.keycode == KEY_ESCAPE:
					focus.release_focus()
				return
			match k.keycode:
				KEY_ESCAPE:
					get_tree().quit()
				KEY_SPACE:
					_paused = not _paused
				KEY_H:
					_ship_shield_harden = not _ship_shield_harden
					_apply_ship_shield_idle()
				KEY_F:
					_fire_next_attacker()
				KEY_ENTER:
					_fire_next_attacker()
				KEY_R:
					_attack_i = 0
					_shield_hp = _SHIELD_MAX
					_shield_regen_t = 0.0
					_update_hp_label()
					_apply_ship_shield_idle()
					_fire_next_attacker()
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_look_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_base_pos += _cam_forward() * -_WHEEL_STEP
			_apply_cam()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_base_pos += _cam_forward() * _WHEEL_STEP
			_apply_cam()
	if event is InputEventMouseMotion and _look_dragging:
		var mm: InputEventMouseMotion = event
		_cam_base_yaw_deg -= mm.relative.x * _LOOK_SENS
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg - mm.relative.y * _LOOK_SENS, -80.0, 80.0)
		_apply_cam()


func _build_env() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.light_energy = 1.35
	add_child(light)
	var amb: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.2, 0.24)
	env.ambient_light_energy = 0.45
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.26
	amb.environment = env
	add_child(amb)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_apply_cam()


func _build_board() -> void:
	var pad: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(48.0, 0.06, 48.0)
	pad.mesh = box
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.1, 0.12, 0.16, 0.85)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad.material_override = pm
	pad.position = Vector3(0, -0.03, 0)
	_world.add_child(pad)
	var note: Label3D = Label3D.new()
	note.text = "满盾↔破盾 · 敲数字调亮/透 · 护盾亮=攻击特效同拍 · WASD移镜"
	note.font_size = 28
	note.outline_size = 7
	note.position = Vector3(0, 0.25, 14.0)
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_world.add_child(note)


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	layer.add_child(_hud)

	var row: HBoxContainer = HBoxContainer.new()
	row.position = Vector2(16, 78)
	row.add_theme_constant_override("separation", 10)
	layer.add_child(row)

	var lb1: Label = Label.new()
	lb1.text = "中心亮度"
	row.add_child(lb1)
	_edit_bright = LineEdit.new()
	_edit_bright.custom_minimum_size = Vector2(100, 28)
	_edit_bright.text = str(_hit_brightness)
	_edit_bright.placeholder_text = "brightness"
	_edit_bright.text_submitted.connect(_on_bright_submitted)
	_edit_bright.focus_exited.connect(_read_tune_fields)
	row.add_child(_edit_bright)

	var lb2: Label = Label.new()
	lb2.text = "峰透明度(0-1)"
	row.add_child(lb2)
	_edit_alpha = LineEdit.new()
	_edit_alpha.custom_minimum_size = Vector2(100, 28)
	_edit_alpha.text = str(_hit_peak_alpha)
	_edit_alpha.placeholder_text = "0..1"
	_edit_alpha.text_submitted.connect(_on_alpha_submitted)
	_edit_alpha.focus_exited.connect(_read_tune_fields)
	row.add_child(_edit_alpha)

	var apply_btn: Button = Button.new()
	apply_btn.text = "应用"
	apply_btn.pressed.connect(_read_tune_fields)
	row.add_child(apply_btn)


func _on_bright_submitted(t: String) -> void:
	_hit_brightness = maxf(0.0, t.strip_edges().to_float())
	_edit_bright.text = str(_hit_brightness)
	_apply_ship_shield_idle()


func _on_alpha_submitted(t: String) -> void:
	_hit_peak_alpha = clampf(t.strip_edges().to_float(), 0.0, 1.0)
	_edit_alpha.text = str(_hit_peak_alpha)
	_apply_ship_shield_idle()


func _read_tune_fields() -> void:
	if _edit_bright != null:
		_hit_brightness = maxf(0.0, _edit_bright.text.strip_edges().to_float())
		_edit_bright.text = str(_hit_brightness)
	if _edit_alpha != null:
		_hit_peak_alpha = clampf(_edit_alpha.text.strip_edges().to_float(), 0.0, 1.0)
		_edit_alpha.text = str(_hit_peak_alpha)
	_apply_ship_shield_idle()


func _refresh_hud() -> void:
	if _hud == null:
		return
	var next_kind: String = ""
	if not _attack_kinds.is_empty():
		next_kind = _attack_kinds[_attack_i % _attack_kinds.size()]
	var shield_txt: String = "%.0f/%.0f" % [_shield_hp, _SHIELD_MAX]
	if not _has_shield():
		shield_txt = "破盾(%.1fs)" % _shield_regen_t
	var mode: String = "硬化+" if _ship_shield_harden else "idle近透"
	_hud.text = (
		"舰盾受击  盾=%s  下一枪=%s  %s  暂停=%s\n"
		+ "亮度/透明度：上方输入框敲数字 → Enter或「应用」\n"
		+ "护盾亮随攻击特效同拍 · WASD/QE移镜 · H壳 · F开火 · Esc"
	) % [shield_txt, next_kind, mode, str(_paused)]


func _drive_camera(delta: float) -> void:
	var move: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		move.z += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	## Don't fly the cam while typing numbers.
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return
	if move != Vector3.ZERO:
		var cam_basis: Basis = Basis.from_euler(
			Vector3(deg_to_rad(_cam_base_pitch_deg), deg_to_rad(_cam_base_yaw_deg), 0.0)
		)
		_cam_base_pos += cam_basis * move.normalized() * _CAM_MOVE_SPEED * delta
		_apply_cam()


func _cam_forward() -> Vector3:
	return Basis.from_euler(
		Vector3(deg_to_rad(_cam_base_pitch_deg), deg_to_rad(_cam_base_yaw_deg), 0.0)
	) * Vector3(0, 0, -1)


func _apply_cam() -> void:
	if _cam == null:
		return
	_cam.position = _cam_base_pos
	_cam.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
