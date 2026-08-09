extends Node
## Attack VFX: Unity FiringEffectController laser stretch + EVEmu kind taxonomy
## (effects.Laser / hybrid / projectileFired / missileLaunching).
## Spawns from ShipUnit.get_muzzle_global() (turret hardpoints; cycles multi-gun).
## Beam/projectile endpoints re-sample firer muzzle + live target each tick.
## If the target dies mid-clip, aim stays on the last pre-death world point until FX ends.

var _world: Node3D
var _active: Array[Dictionary] = []
var _sfx: WeaponFireSfx
## Per-firer near/far parity for turret kinds (COMBAT §8): false → next near, true → next far.
var _range_parity: Dictionary = {}
## Preview gallery forces full FX regardless of GameSession.weapon_fx_simplified.
var force_full_fx: bool = false

func setup(world_root: Node3D) -> void:
	_world = world_root
	_ensure_sfx()


func _use_simplified_fx() -> bool:
	if force_full_fx:
		return false
	if GameSession == null:
		return false
	return bool(GameSession.weapon_fx_simplified)


func _strip_shot_textures(shot_def: Dictionary) -> void:
	shot_def["tex_beam"] = ""
	shot_def["tex_near"] = ""
	shot_def["tex_far"] = ""
	shot_def["tex_shared"] = ""
	shot_def["tex_noise"] = ""
	shot_def["tex_grid"] = ""
	shot_def["tex_flare"] = ""
	shot_def["tex_target"] = ""
	shot_def["strobe_layers"] = []
	shot_def["strobe_layers_near"] = []
	shot_def["strobe_layers_far"] = []
	shot_def["strobe_hz"] = 0.0
	shot_def["path_offset_noise_scale_m"] = 0.0
	shot_def["path_offset_noise_speed"] = 0.0
	shot_def["eject_duration_s"] = 0.0
	shot_def["eject_speed_m_s"] = 0.0

func _ensure_sfx() -> void:
	if _sfx != null and is_instance_valid(_sfx):
		return
	_sfx = WeaponFireSfx.new()
	_sfx.name = "WeaponFireSfx"
	add_child(_sfx)
	_sfx.setup()

func play(firer: ShipUnit, target: ShipUnit, kind: String, duration: float, projectile_travel_s: float = -1.0, projectile_speed_cells: float = -1.0) -> void:
	if firer == null or target == null or _world == null:
		return
	## COMBAT §8.1 — SFX stays on in no_model_perf; only skip VFX (death boom already ignores this flag).
	_ensure_sfx()
	if _sfx:
		_sfx.play_for(firer, kind)
	if GameSession and bool(GameSession.no_model_perf_mode):
		return
	_play_kind(firer, target, null, kind, duration, projectile_travel_s, projectile_speed_cells)


## Visual-only mining beam toward a MiningAnchor (no damage).
func play_to_anchor(firer: ShipUnit, anchor: Node3D, kind: String = "mining", duration: float = 0.85) -> void:
	if firer == null or anchor == null or not is_instance_valid(anchor) or _world == null:
		return
	_ensure_sfx()
	if _sfx:
		_sfx.play_for(firer, kind)
	if GameSession and bool(GameSession.no_model_perf_mode):
		return
	_play_kind(firer, null, anchor, kind, duration, -1.0, -1.0)


## Function-bucket ship-to-ship FX (COMBAT §8.2) — nos/neut/damp/painter/…
func play_function(firer: ShipUnit, target: ShipUnit, kind: String, duration: float = 1.0) -> void:
	if firer == null or target == null or _world == null:
		return
	var k: String = str(kind).strip_edges()
	if k == "":
		return
	var dur: float = maxf(0.2, duration)
	_ensure_sfx()
	if _sfx:
		_sfx.play_for(firer, k)
	if GameSession and bool(GameSession.no_model_perf_mode):
		return
	## Refresh existing link for the same firer/target/kind so the beam stays for the full active window.
	for e: Dictionary in _active:
		if str(e.get("style", "")) != "beam":
			continue
		if str(e.get("fx_role", "")) != "function":
			continue
		if str(e.get("kind", "")) != k:
			continue
		if e.get("firer") != firer or e.get("target") != target:
			continue
		e["t_left"] = maxf(TypedVariant.as_float(e.get("t_left", 0.0), 0.0), dur)
		return
	var before: int = _active.size()
	_play_kind(firer, target, null, k, dur, -1.0, -1.0)
	if _active.size() > before:
		var entry: Dictionary = _active[_active.size() - 1]
		entry["fx_role"] = "function"
		entry["kind"] = k


func _play_kind(
	firer: ShipUnit,
	target: ShipUnit,
	anchor: Node3D,
	kind: String,
	duration: float,
	projectile_travel_s: float,
	projectile_speed_cells: float
) -> void:
	## SFX already fired from play* entrypoints; VFX-only path here.
	var cfg: Dictionary = DataStore.weapon_fx
	var kinds: Dictionary = TypedVariant.as_dict(cfg.get("kinds", {}))
	var kdef: Dictionary = TypedVariant.as_dict(kinds.get(kind, kinds.get("laser", {})))
	if kdef.is_empty():
		return
	var style: String = str(kdef.get("style", "beam"))
	var col_a: Array = TypedVariant.as_array(kdef.get("color", [1, 1, 0.3, 1]))
	var color: Color = Color(
		TypedVariant.as_float(col_a[0], 1.0),
		TypedVariant.as_float(col_a[1], 1.0),
		TypedVariant.as_float(col_a[2], 0.3),
		TypedVariant.as_float(col_a[3], 1.0) if col_a.size() > 3 else 1.0
	)
	var look: String = str(kdef.get("look", "solid")).strip_edges().to_lower()
	if look == "":
		look = "solid"
	## TQ turret near/far alternate (pulse↔beam, blast↔rail, auto↔artil).
	var band: String = _consume_range_band(firer, kdef)
	var shot_def: Dictionary = kdef.duplicate(true)
	_apply_range_band(shot_def, band)
	var simplified: bool = _use_simplified_fx()
	if simplified:
		_strip_shot_textures(shot_def)
		## Cannon: single sphere projectile (not tracer cones). Missile: no eject/noise.
		if style == "tracer" or look == "cannon_cone":
			style = "projectile"
			look = "projectile"
			shot_def["style"] = "projectile"
			shot_def["look"] = "projectile"
			shot_def["trail"] = TypedVariant.as_bool(shot_def.get("trail_far", false), false) and band == "far"
		if kind == "missile" or look == "missile":
			shot_def["path_offset_noise_scale_m"] = 0.0
			shot_def["eject_duration_s"] = 0.0
			shot_def["eject_speed_m_s"] = 0.0
		## Function looks stay geometric; drop texture-driven paint disc if any.
		if look == "paint":
			look = "solid"
			shot_def["look"] = "solid"
	var width: float = TypedVariant.as_float(shot_def.get("width", kdef.get("width", 0.06)), 0.06)
	var dur_scale: float = TypedVariant.as_float(shot_def.get("duration_scale", 1.0), 1.0)
	var dur: float = maxf(0.08, duration * dur_scale)
	var rand_r: float = TypedVariant.as_float(cfg.get("rand_pos_range", 0.25), 0.25)
	## Function / heal / mining stay pinned; attack beams keep light muzzle jitter.
	var jitter_a: Vector3 = Vector3.ZERO
	var jitter_b: Vector3 = Vector3.ZERO
	if look == "solid" or look == "projectile" or look == "missile" or look == "cannon_cone":
		jitter_a = Vector3(randf_range(-rand_r, rand_r), randf_range(0.0, rand_r), randf_range(-rand_r, rand_r))
		jitter_b = Vector3(randf_range(-rand_r, rand_r), randf_range(0.0, rand_r), randf_range(-rand_r, rand_r))
	if style == "tracer" and target != null and not simplified:
		_spawn_cannon_tracers(firer, target, color, width, jitter_a, jitter_b, shot_def)
	elif (style == "projectile" or (simplified and style == "tracer")) and target != null:
		var spd_cells: float = projectile_speed_cells
		if spd_cells <= 0.0 and kind == "missile":
			spd_cells = CombatFormulas.missile_speed_cells_per_s(firer)
		var use_trail: bool = TypedVariant.as_bool(shot_def.get("trail", false), false)
		_spawn_projectile(
			firer,
			target,
			color,
			width,
			TypedVariant.as_float(shot_def.get("speed", 30.0), 30.0),
			use_trail,
			jitter_a,
			jitter_b,
			projectile_travel_s,
			TypedVariant.as_float(shot_def.get("trail_lag", 0.08), 0.08),
			TypedVariant.as_float(shot_def.get("trail_length", 0.6), 0.6),
			spd_cells,
			"" if simplified else str(shot_def.get("tex_beam", "")),
			shot_def
		)
	else:
		if simplified:
			## Force untextured beam mats (stretch shader skipped when tex empty).
			look = "solid" if look in ["cannon_cone", "paint"] else look
		_spawn_beam(firer, target, color, width, dur, jitter_a, jitter_b, anchor, look, shot_def)


func _consume_range_band(firer: ShipUnit, kdef: Dictionary) -> String:
	if not TypedVariant.as_bool(kdef.get("alternate_near_far", false), false):
		return "near"
	if firer == null or not is_instance_valid(firer):
		return "near"
	var id: int = firer.get_instance_id()
	var use_far: bool = TypedVariant.as_bool(_range_parity.get(id, false), false)
	_range_parity[id] = not use_far
	return "far" if use_far else "near"


func _apply_range_band(shot_def: Dictionary, band: String) -> void:
	var is_far: bool = band == "far"
	var tex_key: String = "tex_far" if is_far else "tex_near"
	var tex: String = str(shot_def.get(tex_key, ""))
	if tex == "":
		tex = str(shot_def.get("tex_beam", ""))
	if tex != "":
		shot_def["tex_beam"] = tex
	## Secondary / grid: prefer shared laser/blast fill when present.
	var shared: String = str(shot_def.get("tex_shared", ""))
	if shared != "" and str(shot_def.get("tex_grid", "")) == "":
		shot_def["tex_grid"] = shared
	var noise: String = str(shot_def.get("tex_noise", ""))
	if noise != "" and str(shot_def.get("tex_grid", "")) == shared:
		## Pair primary FX with noise as scroll secondary when available.
		shot_def["tex_grid"] = noise
	var layers_key: String = "strobe_layers_far" if is_far else "strobe_layers_near"
	var layers_v: Variant = shot_def.get(layers_key, [])
	if typeof(layers_v) == TYPE_ARRAY and not TypedVariant.as_array(layers_v).is_empty():
		shot_def["strobe_layers"] = TypedVariant.as_array(layers_v).duplicate()
	else:
		## Fallback: primary + shared + noise from TQ black trio.
		var layers: Array = []
		if tex != "":
			layers.append(tex)
		if shared != "" and shared != tex:
			layers.append(shared)
		if noise != "" and noise != tex and noise != shared:
			layers.append(noise)
		shot_def["strobe_layers"] = layers
	var scale_key: String = "duration_scale_far" if is_far else "duration_scale_near"
	if shot_def.has(scale_key):
		shot_def["duration_scale"] = TypedVariant.as_float(shot_def.get(scale_key), 1.0)
	var width_key: String = "width_far" if is_far else "width_near"
	if shot_def.has(width_key):
		shot_def["width"] = TypedVariant.as_float(shot_def.get(width_key), TypedVariant.as_float(shot_def.get("width", 0.06), 0.06))
	var speed_key: String = "speed_far" if is_far else "speed_near"
	if shot_def.has(speed_key):
		shot_def["speed"] = TypedVariant.as_float(shot_def.get(speed_key), 30.0)
	if is_far and TypedVariant.as_bool(shot_def.get("trail_far", false), false):
		shot_def["trail"] = true
	shot_def["range_band"] = band
	shot_def["range_role"] = str(shot_def.get("role_far" if is_far else "role_near", band))

const STRETCH_SHADER: String = "res://shaders/module_fx_stretch.gdshader"
static var _stretch_shader: Shader

func _ensure_stretch_shader() -> Shader:
	if _stretch_shader != null:
		return _stretch_shader
	if ResourceLoader.exists(STRETCH_SHADER):
		var sh_v: Variant = load(STRETCH_SHADER)
		if sh_v is Shader:
			_stretch_shader = sh_v
	return _stretch_shader


func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var v: Variant = load(path)
	return v if v is Texture2D else null


func _make_stretch_mat(color: Color, kdef: Dictionary, grid_mix_override: float = -1.0) -> Material:
	var sh: Shader = _ensure_stretch_shader()
	var tex_beam: Texture2D = _load_tex(str(kdef.get("tex_beam", "")))
	var tex_grid: Texture2D = _load_tex(str(kdef.get("tex_grid", "")))
	if sh != null and (tex_beam != null or tex_grid != null):
		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = sh
		if tex_beam != null:
			sm.set_shader_parameter("tex_beam", tex_beam)
		if tex_grid != null:
			sm.set_shader_parameter("tex_grid", tex_grid)
		sm.set_shader_parameter("tint", color)
		var gmix: float = grid_mix_override if grid_mix_override >= 0.0 else TypedVariant.as_float(kdef.get("grid_mix", 0.55), 0.55)
		sm.set_shader_parameter("grid_mix", gmix)
		sm.set_shader_parameter("scroll_speed", TypedVariant.as_float(kdef.get("scroll_speed", 1.8), 1.8))
		sm.set_shader_parameter(
			"emission_boost",
			TypedVariant.as_float(kdef.get("emission_boost", 2.6), 2.6)
		)
		## Default mild tile; cannon needs higher Y so 128 CloudMap grain isn't smeared across board span.
		var uv_a: Array = TypedVariant.as_array(kdef.get("uv_scale", [1.0, 3.2]))
		var uv_x: float = TypedVariant.as_float(uv_a[0], 1.0) if uv_a.size() > 0 else 1.0
		var uv_y: float = TypedVariant.as_float(uv_a[1], 3.2) if uv_a.size() > 1 else 3.2
		sm.set_shader_parameter("uv_scale", Vector2(uv_x, uv_y))
		sm.set_shader_parameter("pulse", 1.0)
		return sm
	return _beam_mat(color, 2.2, 1.0)


func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var mul: float = 1.0
	var root: Node = get_tree().get_first_node_in_group("match_root")
	if root:
		var mc_v: Variant = root.get("match_ctrl")
		if mc_v is Node:
			var mc: Node = mc_v
			mul = TypedVariant.as_float(mc.get("speed_multiplier"), 1.0)
	var scaled: float = delta * mul
	var i: int = 0
	while i < _active.size():
		var e: Dictionary = _active[i]
		var alive: bool = true
		var st: String = str(e.get("style", ""))
		if st == "beam":
			alive = _tick_beam(e, scaled)
		elif st == "tracer":
			alive = _tick_cannon_tracers(e, scaled)
		else:
			alive = _tick_projectile(e, scaled)
		if alive:
			i += 1
		else:
			_free_entry(e)
			_active.remove_at(i)
	SessionDiagnostics.add_usec(&"fx", Time.get_ticks_usec() - t0)

func _beam_mat(color: Color, energy: float = 2.2, alpha_mul: float = 1.0) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var a: float = clampf(color.a * alpha_mul, 0.05, 1.0)
	mat.albedo_color = Color(color.r, color.g, color.b, a)
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b) * 1.4
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _make_trumpet_mesh() -> CylinderMesh:
	## After look_at(to) + rotate_local X=-90°: mesh +Y maps toward target (−Z).
	## So top_radius = target (flare), bottom_radius = firer (tip). Was swapped before.
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 0.22
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 4
	return cyl


func _make_target_disc(color: Color, tex_path: String) -> MeshInstance3D:
	var disc: MeshInstance3D = MeshInstance3D.new()
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	disc.mesh = q
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var tex: Texture2D = _load_tex(tex_path)
	if tex != null:
		mat.albedo_texture = tex
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 2.8
	disc.material_override = mat
	return disc


func _spawn_beam(
	firer: ShipUnit,
	target: ShipUnit,
	color: Color,
	width: float,
	duration: float,
	ja: Vector3,
	jb: Vector3,
	anchor: Node3D = null,
	look: String = "solid",
	kdef: Dictionary = {}
) -> void:
	## Small hulls (frigate/destroyer): keep beams readable; floors track ~50% of prior thicken.
	var w: float = maxf(width, 0.03)
	if firer != null and is_instance_valid(firer):
		var sg: String = str(DataStore.get_ship(firer.ship_id).get("ship_group", "")).to_lower()
		if sg in ["frigate", "destroyer", "drone_light", "drone_medium"]:
			w = maxf(w, 0.055)
	if look == "paint":
		w = maxf(w * 0.55, 0.04)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var secondary: MeshInstance3D = null
	var target_disc: MeshInstance3D = null
	var helix: Array = []
	var stretch_mat: Material = _make_stretch_mat(color, kdef)
	match look:
		"trumpet", "cone_grid", "cone":
			mi.mesh = _make_trumpet_mesh()
			var gmix: float = 0.85 if look == "cone_grid" else TypedVariant.as_float(kdef.get("grid_mix", 0.6), 0.6)
			mi.material_override = _make_stretch_mat(color, kdef, gmix)
			## Outer sheath trumpet (softer, wider) — TQ rail often doubles stretch.
			secondary = MeshInstance3D.new()
			secondary.mesh = _make_trumpet_mesh()
			var sheath_col: Color = Color(color.r, color.g, color.b, color.a * 0.55)
			secondary.material_override = _make_stretch_mat(sheath_col, kdef, maxf(gmix * 0.7, 0.35))
			_world.add_child(secondary)
		"helix":
			mi.mesh = _make_trumpet_mesh()
			mi.material_override = stretch_mat
			for _i: int in range(3):
				var hmi: MeshInstance3D = MeshInstance3D.new()
				var hbox: BoxMesh = BoxMesh.new()
				hbox.size = Vector3.ONE
				hmi.mesh = hbox
				hmi.material_override = _make_stretch_mat(color, kdef, 0.75)
				_world.add_child(hmi)
				helix.append(hmi)
		"paint":
			var box_p: BoxMesh = BoxMesh.new()
			box_p.size = Vector3.ONE
			mi.mesh = box_p
			mi.material_override = stretch_mat
			target_disc = _make_target_disc(color, str(kdef.get("tex_target", kdef.get("tex_flare", ""))))
			_world.add_child(target_disc)
		"core_sheath":
			var core: BoxMesh = BoxMesh.new()
			core.size = Vector3.ONE
			mi.mesh = core
			mi.material_override = stretch_mat if str(kdef.get("tex_beam", "")) != "" else _beam_mat(
				Color(minf(color.r + 0.25, 1.0), minf(color.g + 0.15, 1.0), minf(color.b + 0.25, 1.0), 1.0), 3.2, 1.0
			)
			secondary = MeshInstance3D.new()
			var sheath: BoxMesh = BoxMesh.new()
			sheath.size = Vector3.ONE
			secondary.mesh = sheath
			secondary.material_override = _beam_mat(color, 1.6, 0.45)
			_world.add_child(secondary)
		_:
			var box2: BoxMesh = BoxMesh.new()
			box2.size = Vector3.ONE
			mi.mesh = box2
			if str(kdef.get("tex_beam", "")) != "":
				mi.material_override = stretch_mat
			else:
				mi.material_override = _beam_mat(color, 3.4 if look == "paint" else 2.2, 1.0)
	_world.add_child(mi)
	var from0: Vector3 = _muzzle_point(firer) + ja
	var to0: Vector3 = from0 + Vector3(0, 0, 1)
	if anchor != null and is_instance_valid(anchor):
		to0 = anchor.global_position + jb
	else:
		to0 = _sample_aim_world(target, jb, to0)
	var entry: Dictionary = {
		"style": "beam",
		"look": look,
		"node": mi,
		"secondary": secondary,
		"target_disc": target_disc,
		"helix": helix,
		"helix_phase": randf() * TAU,
		"disc_spin": 0.0,
		"firer": firer,
		"target": target,
		"anchor": anchor,
		"t_left": duration,
		"ja": ja,
		"jb": jb,
		"to": to0,
		"width": w,
		"strobe_layers": TypedVariant.as_array(kdef.get("strobe_layers", [])).duplicate(),
		"strobe_hz": TypedVariant.as_float(kdef.get("strobe_hz", 0.0), 0.0),
		"strobe_i": 0,
		"strobe_t": 0.0,
	}
	_active.append(entry)
	## Layout immediately — otherwise first frame sits at world origin (looks like FX missing).
	_tick_beam(entry, 0.0)

const MUZZLE_FALLBACK_DIST: float = 6.0

func _muzzle_point(firer: ShipUnit) -> Vector3:
	if firer == null or not is_instance_valid(firer):
		return Vector3(0.0, 0.4, 0.0)
	var from: Vector3 = firer.get_muzzle_global()
	var ship_pos: Vector3 = firer.visual_origin_world() if firer.has_method("visual_origin_world") else firer.global_position
	if from.distance_to(ship_pos) > MUZZLE_FALLBACK_DIST:
		return ship_pos + Vector3(0.0, 0.4, 0.0)
	return from

func _target_point(target: ShipUnit, jb: Vector3, fallback: Vector3) -> Vector3:
	if target != null and is_instance_valid(target) and not target.is_destroyed:
		## Aim at the drawn hull so beams/missiles meet the soft-followed mesh.
		return _sample_aim_world(target, jb, fallback)
	return fallback


## Logic pose remains after kill (`visible=false`); use once to seed FX when hit already destroyed the unit.
func _sample_aim_world(target: ShipUnit, jb: Vector3, fallback: Vector3) -> Vector3:
	if target != null and is_instance_valid(target):
		var center: Vector3 = target.visual_center_world() if target.has_method("visual_center_world") else target.global_position
		return center + Vector3(0, 0.4, 0) + jb
	return fallback


## Live aim, else hold last `e["to"]` (COMBAT §8 kill-freeze). Never invent a near-muzzle placeholder.
func _aim_to(e: Dictionary, jb: Vector3, fallback: Vector3) -> Vector3:
	var target: ShipUnit = _alive_ship_ref(e, "target")
	var held: Vector3 = _dict_vec3(e.get("to", fallback), fallback)
	if target != null:
		held = _sample_aim_world(target, jb, held)
	e["to"] = held
	return held


## TQ pathOffsetNoise: dual-sine in the plane perpendicular to flight direction.
func _missile_path_offset(e: Dictionary, dir: Vector3) -> Vector3:
	var scale_wu: float = TypedVariant.as_float(e.get("noise_scale_wu", 0.0), 0.0)
	if scale_wu <= 0.0001:
		return Vector3.ZERO
	var nspd: float = TypedVariant.as_float(e.get("noise_speed", 0.0), 0.0)
	var ft: float = TypedVariant.as_float(e.get("flight_t", 0.0), 0.0)
	var ph: float = TypedVariant.as_float(e.get("noise_phase", 0.0), 0.0)
	var ph2: float = TypedVariant.as_float(e.get("noise_phase2", 0.0), 0.0)
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(up)) > 0.92:
		up = Vector3.RIGHT
	var side: Vector3 = dir.cross(up).normalized()
	var binorm: Vector3 = dir.cross(side).normalized()
	var u: float = ft * nspd * TAU + ph
	var v: float = ft * nspd * 1.73 * TAU + ph2
	## Two frequencies approximate NoiseMap scroll without a texture sample.
	var ox: float = sin(u) * 0.65 + sin(u * 2.17 + 1.1) * 0.35
	var oy: float = cos(v) * 0.65 + cos(v * 1.91 + 0.7) * 0.35
	return side * (ox * scale_wu) + binorm * (oy * scale_wu)

## Cannon: cone tracers ride a fixed muzzle→aim line (COMBAT §8).
## auto=3 head-to-tail along the line; artil=1 fat cone. Brightness from DataStore only.
func _spawn_cannon_tracers(
	firer: ShipUnit,
	target: ShipUnit,
	color: Color,
	width: float,
	ja: Vector3,
	jb: Vector3,
	shot_def: Dictionary
) -> void:
	var from: Vector3 = _muzzle_point(firer) + ja
	var to: Vector3 = _sample_aim_world(target, jb, from + Vector3(0, 0, 1))
	var band: String = str(shot_def.get("range_band", "near"))
	var is_far: bool = band == "far"
	var count: int = maxi(
		1,
		TypedVariant.as_int(
			shot_def.get("tracer_count_far" if is_far else "tracer_count_near", 1 if is_far else 3),
			1 if is_far else 3
		)
	)
	var cone_len: float = TypedVariant.as_float(
		shot_def.get("cone_length_far" if is_far else "cone_length_near", 0.7),
		0.7
	)
	var tip_r: float = maxf(width * 0.12, 0.006)
	var mouth_r: float = maxf(width, tip_r * 2.0)
	var tex: Texture2D = _load_tex(str(shot_def.get("tex_beam", "")))
	## Prefer live DataStore (preview tune); never hard-reset from JSON defaults here.
	var emit: float = TypedVariant.as_float(shot_def.get("emission_boost", 5.0), 5.0)
	if DataStore != null:
		var live: Dictionary = TypedVariant.as_dict(
			TypedVariant.as_dict(DataStore.weapon_fx.get("kinds", {})).get("cannon", {})
		)
		if live.has("emission_boost"):
			emit = TypedVariant.as_float(live.get("emission_boost", emit), emit)
	var dir: Vector3 = to - from
	var dist: float = maxf(0.05, dir.length())
	dir /= dist
	## Progress gap so cone centers are cone_len apart → tip of rear meets mouth of front.
	var chain_dt: float = cone_len / dist if count > 1 else 0.0
	var nodes: Array = []
	var staggers: Array = []
	for i: int in range(count):
		var mi: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		## Tip aft (bottom), slight flare forward (top).
		cyl.top_radius = mouth_r
		cyl.bottom_radius = tip_r
		cyl.height = cone_len
		cyl.radial_segments = 12
		cyl.rings = 2
		mi.mesh = cyl
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = emit
		if tex != null:
			mat.albedo_texture = tex
			mat.emission_texture = tex
		mi.material_override = mat
		_world.add_child(mi)
		mi.global_position = from
		nodes.append(mi)
		## i=0 = leading (toward target); i>0 trail behind, head-to-tail.
		staggers.append(-chain_dt * float(i))
	_active.append({
		"style": "tracer",
		"nodes": nodes,
		"staggers": staggers,
		"from": from,
		"to": to,
		"dir": dir,
		"dist": dist,
		"progress": 0.0,
		"speed": TypedVariant.as_float(shot_def.get("speed", 70.0), 70.0),
		"cone_length": cone_len,
		"node": null,
		"trail": null,
		"target": null,
		"firer": null,
	})
	_tick_cannon_tracers(_active[_active.size() - 1], 0.0)


func _tick_cannon_tracers(e: Dictionary, delta: float) -> bool:
	var from: Vector3 = _dict_vec3(e.get("from", Vector3.ZERO))
	var to: Vector3 = _dict_vec3(e.get("to", Vector3.ZERO))
	var dist: float = maxf(0.05, TypedVariant.as_float(e.get("dist", from.distance_to(to)), from.distance_to(to)))
	var speed: float = TypedVariant.as_float(e.get("speed", 70.0), 70.0)
	e["progress"] = TypedVariant.as_float(e.get("progress", 0.0), 0.0) + (speed * delta) / dist
	var base_t: float = TypedVariant.as_float(e.get("progress", 0.0), 0.0)
	var dir: Vector3 = _dict_vec3(e.get("dir", to - from), to - from)
	if dir.length_squared() < 0.0001:
		dir = Vector3(0, 0, 1)
	else:
		dir = dir.normalized()
	var nodes_v: Variant = e.get("nodes", [])
	var stags_v: Variant = e.get("staggers", [])
	if not nodes_v is Array:
		return false
	var nodes: Array = nodes_v
	var stags: Array = stags_v if stags_v is Array else []
	var any_alive: bool = false
	var tail_need: float = 1.0
	if not stags.is_empty():
		## Keep volley alive until the rearmost cone finishes.
		var min_stag: float = 0.0
		for s_any: Variant in stags:
			min_stag = minf(min_stag, TypedVariant.as_float(s_any, 0.0))
		tail_need = 1.0 - min_stag
	for i: int in range(nodes.size()):
		var n_any: Variant = nodes[i]
		if n_any == null or not is_instance_valid(n_any) or not n_any is MeshInstance3D:
			continue
		@warning_ignore("unsafe_cast")
		var mi: MeshInstance3D = n_any as MeshInstance3D
		var stag: float = TypedVariant.as_float(stags[i], 0.0) if i < stags.size() else 0.0
		var t: float = base_t + stag
		if t < 0.0:
			mi.visible = false
			any_alive = true
			continue
		if t >= 1.0:
			mi.visible = false
			continue
		mi.visible = true
		any_alive = true
		var pos: Vector3 = from.lerp(to, t)
		mi.global_position = pos
		var ahead: Vector3 = pos + dir
		mi.look_at(ahead, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	return any_alive or base_t < tail_need


func _spawn_projectile(
	firer: ShipUnit,
	target: ShipUnit,
	color: Color,
	width: float,
	speed: float,
	trail: bool,
	ja: Vector3,
	jb: Vector3,
	projectile_travel_s: float = -1.0,
	trail_lag: float = 0.08,
	trail_length: float = 0.6,
	speed_cells_per_s: float = -1.0,
	tex_path: String = "",
	shot_def: Dictionary = {}
) -> void:
	var from: Vector3 = _muzzle_point(firer) + ja
	## Seed even if kill already flipped is_destroyed before play().
	var to: Vector3 = _sample_aim_world(target, jb, from + Vector3(0, 0, 1))
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = width * 0.5
	sphere.height = width
	mi.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	var emit_boost: float = TypedVariant.as_float(shot_def.get("emission_boost", 2.5), 2.5)
	mat.emission_energy_multiplier = emit_boost
	var ptex: Texture2D = _load_tex(tex_path)
	if ptex != null:
		mat.albedo_texture = ptex
	mi.material_override = mat
	_world.add_child(mi)
	mi.global_position = from
	var trail_mi: MeshInstance3D = null
	if trail:
		trail_mi = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = width * 0.15
		cyl.bottom_radius = width * 0.35
		cyl.height = maxf(0.2, trail_length)
		trail_mi.mesh = cyl
		var tmat: StandardMaterial3D = StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tmat.emission_enabled = true
		tmat.emission = Color(color.r, color.g, color.b)
		tmat.emission_energy_multiplier = emit_boost * 0.55
		if ptex != null:
			tmat.albedo_texture = ptex
		trail_mi.material_override = tmat
		_world.add_child(trail_mi)
	var chase: bool = speed_cells_per_s > 0.0
	var strobe_layers: Array = TypedVariant.as_array(shot_def.get("strobe_layers", []))
	## TQ EveMissileWarhead eject + pathOffsetNoise → board WU (COMBAT §12). FX-only.
	var m_per_cell: float = TypedVariant.as_float(DataStore.combat.get("meters_per_cell", 2000.0), 2000.0)
	var wu_cell: float = CombatFormulas.world_units_per_cell()
	var noise_scale_m: float = TypedVariant.as_float(shot_def.get("path_offset_noise_scale_m", 0.0), 0.0)
	var noise_speed: float = TypedVariant.as_float(shot_def.get("path_offset_noise_speed", 0.0), 0.0)
	var noise_scale_wu: float = 0.0
	if chase and noise_scale_m > 0.0 and m_per_cell > 0.0001:
		noise_scale_wu = noise_scale_m / m_per_cell * wu_cell
	var eject_dur: float = 0.0
	var eject_speed_wu: float = 0.0
	var eject_dir: Vector3 = Vector3.UP
	if chase:
		eject_dur = maxf(0.0, TypedVariant.as_float(shot_def.get("eject_duration_s", 0.0), 0.0))
		var eject_spd_m: float = TypedVariant.as_float(shot_def.get("eject_speed_m_s", 0.0), 0.0)
		if eject_spd_m > 0.0 and m_per_cell > 0.0001:
			eject_speed_wu = eject_spd_m / m_per_cell * wu_cell
		## Vertical leave-ship, slight outward from hull (TQ eject phase).
		var hull: Vector3 = from
		if firer != null and is_instance_valid(firer):
			hull = firer.visual_center_world() if firer.has_method("visual_center_world") else firer.global_position
		var away: Vector3 = from - hull
		if away.length_squared() < 0.0001:
			away = Vector3.UP
		else:
			away = away.normalized()
		eject_dir = (Vector3.UP * 0.85 + away * 0.15).normalized()
	_active.append({
		"style": "projectile",
		"node": mi,
		"trail": trail_mi,
		## Detached chase missiles do not re-tether to firer muzzle.
		"firer": null if chase else firer,
		"target": target,
		"ja": ja,
		"jb": jb,
		"from": from,
		"to": to,
		"pos": from,
		"speed": speed,
		"speed_cells_per_s": speed_cells_per_s,
		"travel_s": -1.0 if chase else projectile_travel_s,
		"trail_lag": trail_lag,
		"progress": 0.0,
		"dist": maxf(0.01, from.distance_to(to)),
		"strobe_layers": strobe_layers,
		"strobe_hz": TypedVariant.as_float(shot_def.get("strobe_hz", 0.0), 0.0),
		"strobe_i": 0,
		"strobe_t": 0.0,
		"noise_scale_wu": noise_scale_wu,
		"noise_speed": noise_speed,
		"noise_phase": randf() * TAU,
		"noise_phase2": randf() * TAU,
		"flight_t": 0.0,
		"draw_pos": from,
		"phase": "eject" if chase and eject_dur > 0.0 and eject_speed_wu > 0.0 else "cruise",
		"eject_t": 0.0,
		"eject_duration_s": eject_dur,
		"eject_speed_wu": eject_speed_wu,
		"eject_dir": eject_dir,
	})

func _dict_vec3(v: Variant, default_val: Vector3 = Vector3.ZERO) -> Vector3:
	if v is Vector3:
		return v
	return default_val

func _orient_beam_node(mi: MeshInstance3D, from: Vector3, to: Vector3, look: String, sx: float, sy: float, length: float) -> void:
	var mid: Vector3 = from + (to - from) * 0.5
	mi.global_position = mid
	if look == "cone" or look == "cone_grid" or look == "trumpet" or look == "helix":
		## CylinderMesh Y-up: tip at firer (top_radius), flare at target (bottom).
		mi.look_at(to, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		mi.scale = Vector3(sx, length, sy)
	else:
		mi.look_at(to, Vector3.UP)
		mi.scale = Vector3(sx, sy, length)


func _set_mat_pulse(mat: Material, pulse: float) -> void:
	if mat is ShaderMaterial:
		@warning_ignore("unsafe_cast")
		(mat as ShaderMaterial).set_shader_parameter("pulse", pulse)
	elif mat is StandardMaterial3D:
		@warning_ignore("unsafe_cast")
		var sm: StandardMaterial3D = mat as StandardMaterial3D
		sm.albedo_color.a = pulse


func _set_mat_tex_beam(mat: Material, tex: Texture2D) -> void:
	if tex == null:
		return
	if mat is ShaderMaterial:
		@warning_ignore("unsafe_cast")
		(mat as ShaderMaterial).set_shader_parameter("tex_beam", tex)
	elif mat is StandardMaterial3D:
		@warning_ignore("unsafe_cast")
		(mat as StandardMaterial3D).albedo_texture = tex


func _tick_strobe(e: Dictionary, delta: float) -> void:
	var hz: float = TypedVariant.as_float(e.get("strobe_hz", 0.0), 0.0)
	var layers_v: Variant = e.get("strobe_layers", [])
	if hz <= 0.01 or typeof(layers_v) != TYPE_ARRAY:
		return
	var layers: Array = TypedVariant.as_array(layers_v)
	if layers.size() <= 1:
		return
	e["strobe_t"] = TypedVariant.as_float(e.get("strobe_t", 0.0), 0.0) + delta
	var step: float = 1.0 / hz
	if TypedVariant.as_float(e.get("strobe_t", 0.0), 0.0) < step:
		return
	e["strobe_t"] = 0.0
	var i: int = (TypedVariant.as_int(e.get("strobe_i", 0), 0) + 1) % layers.size()
	e["strobe_i"] = i
	var path: String = str(layers[i])
	var tex: Texture2D = _load_tex(path)
	if tex == null:
		return
	var mi_v: Variant = e.get("node")
	if mi_v != null and is_instance_valid(mi_v) and mi_v is MeshInstance3D:
		@warning_ignore("unsafe_cast")
		_set_mat_tex_beam((mi_v as MeshInstance3D).material_override, tex)
	var trail_v: Variant = e.get("trail")
	if trail_v != null and is_instance_valid(trail_v) and trail_v is MeshInstance3D:
		@warning_ignore("unsafe_cast")
		_set_mat_tex_beam((trail_v as MeshInstance3D).material_override, tex)
	## Alternate grid channel with previous layer for richer flicker.
	var prev: int = (i + layers.size() - 1) % layers.size()
	var grid_tex: Texture2D = _load_tex(str(layers[prev]))
	if grid_tex != null and mi_v != null and is_instance_valid(mi_v) and mi_v is MeshInstance3D:
		@warning_ignore("unsafe_cast")
		var mat_g: Material = (mi_v as MeshInstance3D).material_override
		if mat_g is ShaderMaterial:
			@warning_ignore("unsafe_cast")
			(mat_g as ShaderMaterial).set_shader_parameter("tex_grid", grid_tex)


func _tick_beam(e: Dictionary, delta: float) -> bool:
	e["t_left"] = TypedVariant.as_float(e.get("t_left", 0.0), 0.0) - delta
	var mi_v: Variant = e.get("node")
	if mi_v == null or not is_instance_valid(mi_v):
		return false
	if not mi_v is MeshInstance3D:
		return false
	var mi: MeshInstance3D = mi_v
	var firer: ShipUnit = _alive_ship_ref(e, "firer")
	if firer == null:
		return false
	var ja: Vector3 = _dict_vec3(e.get("ja", Vector3.ZERO))
	var jb: Vector3 = _dict_vec3(e.get("jb", Vector3.ZERO))
	var from: Vector3 = _muzzle_point(firer) + ja
	var to: Vector3
	var anchor_v: Variant = e.get("anchor")
	if anchor_v != null and is_instance_valid(anchor_v) and anchor_v is Node3D:
		var anchor: Node3D = anchor_v
		to = anchor.global_position + jb
		e["to"] = to
	else:
		## Prefer last aimed point; spawn path seeds `to` before first tick.
		var aim_seed: Vector3 = _dict_vec3(e.get("to", from + Vector3(0, 0, 1)), from + Vector3(0, 0, 1))
		to = _aim_to(e, jb, aim_seed)
	var diff: Vector3 = to - from
	var length: float = diff.length()
	if length < 0.05:
		return TypedVariant.as_float(e.get("t_left", 0.0), 0.0) > 0.0
	var look: String = str(e.get("look", "solid"))
	var w: float = TypedVariant.as_float(e.get("width", 0.06), 0.06)
	var dir: Vector3 = diff / length
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(up)) > 0.92:
		up = Vector3.RIGHT
	var side: Vector3 = dir.cross(up).normalized()
	var binorm: Vector3 = dir.cross(side).normalized()
	match look:
		"trumpet", "cone_grid", "cone":
			var tip: float = w * (0.9 if look == "trumpet" else 0.7)
			var mouth: float = w * (2.4 if look == "trumpet" else 2.8)
			## Cylinder scale XZ = radius multipliers vs mesh unit radii.
			_orient_beam_node(mi, from, to, look, tip, tip, length)
			var sec_t: Variant = e.get("secondary")
			if sec_t != null and is_instance_valid(sec_t) and sec_t is MeshInstance3D:
				@warning_ignore("unsafe_cast")
				var sec_trumpet: MeshInstance3D = sec_t as MeshInstance3D
				_orient_beam_node(sec_trumpet, from, to, look, mouth, mouth, length)
		"core_sheath":
			_orient_beam_node(mi, from, to, look, w * 0.55, w * 0.55, length)
			var sec_v: Variant = e.get("secondary")
			if sec_v != null and is_instance_valid(sec_v) and sec_v is MeshInstance3D:
				@warning_ignore("unsafe_cast")
				var sec_mi: MeshInstance3D = sec_v as MeshInstance3D
				_orient_beam_node(sec_mi, from, to, "solid", w * 1.55, w * 1.55, length)
		"helix":
			_orient_beam_node(mi, from, to, "trumpet", w * 0.85, w * 0.85, length)
			e["helix_phase"] = TypedVariant.as_float(e.get("helix_phase", 0.0), 0.0) + delta * 7.2
			var phase: float = TypedVariant.as_float(e.get("helix_phase", 0.0), 0.0)
			var helix_v: Variant = e.get("helix")
			if helix_v is Array:
				var arr: Array = helix_v
				for hi: int in range(arr.size()):
					var h_any: Variant = arr[hi]
					if h_any == null or not is_instance_valid(h_any) or not h_any is MeshInstance3D:
						continue
					@warning_ignore("unsafe_cast")
					var hmi: MeshInstance3D = h_any as MeshInstance3D
					var ang: float = phase + float(hi) * (TAU / 3.0)
					var rad: float = w * 2.2
					var offset: Vector3 = side * cos(ang) * rad + binorm * sin(ang) * rad
					_orient_beam_node(hmi, from + offset, to + offset, "solid", w * 0.4, w * 0.4, length)
		"paint":
			_orient_beam_node(mi, from, to, look, w, w, length)
			var disc_v: Variant = e.get("target_disc")
			if disc_v != null and is_instance_valid(disc_v) and disc_v is MeshInstance3D:
				@warning_ignore("unsafe_cast")
				var disc: MeshInstance3D = disc_v as MeshInstance3D
				e["disc_spin"] = TypedVariant.as_float(e.get("disc_spin", 0.0), 0.0) + delta * 2.8
				disc.global_position = to
				disc.scale = Vector3.ONE * (1.15 + 0.15 * sin(TypedVariant.as_float(e.get("disc_spin", 0.0), 0.0) * 2.0))
				disc.rotate_object_local(Vector3.FORWARD, delta * 2.8)
		_:
			_orient_beam_node(mi, from, to, look, w, w, length)
	_tick_strobe(e, delta)
	## Laser 连闪: fast alpha + texture strobe (TQ laser+fx+noise trio).
	var strobe_on: bool = TypedVariant.as_float(e.get("strobe_hz", 0.0), 0.0) > 0.01
	var pulse: float = 0.65 + 0.35 * absf(sin(Time.get_ticks_msec() * (0.085 if strobe_on else 0.02)))
	if look == "paint":
		pulse = 0.8 + 0.2 * absf(sin(Time.get_ticks_msec() * 0.035))
	elif look == "trumpet" or look == "helix" or look == "cone_grid":
		pulse = 0.7 + 0.3 * absf(sin(Time.get_ticks_msec() * 0.028))
	elif strobe_on:
		pulse = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.12))
	_set_mat_pulse(mi.material_override, pulse)
	var sec_pulse_v: Variant = e.get("secondary")
	if sec_pulse_v != null and is_instance_valid(sec_pulse_v) and sec_pulse_v is MeshInstance3D:
		@warning_ignore("unsafe_cast")
		_set_mat_pulse((sec_pulse_v as MeshInstance3D).material_override, pulse * 0.75)
	return TypedVariant.as_float(e.get("t_left", 0.0), 0.0) > 0.0

func _tick_projectile(e: Dictionary, delta: float) -> bool:
	var mi_v: Variant = e.get("node")
	if mi_v == null or not is_instance_valid(mi_v):
		return false
	if not mi_v is MeshInstance3D:
		return false
	var mi: MeshInstance3D = mi_v
	_tick_strobe(e, delta)
	var jb: Vector3 = _dict_vec3(e.get("jb", Vector3.ZERO))
	var speed_cells: float = TypedVariant.as_float(e.get("speed_cells_per_s", -1.0), -1.0)
	## Independent chase: eject vertically off hull, then straight guide + TQ path noise.
	if speed_cells > 0.0:
		var pos: Vector3 = _dict_vec3(e.get("pos", mi.global_position), mi.global_position)
		var to: Vector3 = _aim_to(e, jb, _dict_vec3(e.get("to", pos), pos))
		var wu: float = CombatFormulas.world_units_per_cell()
		var hit_r: float = TypedVariant.as_float(DataStore.combat.get("missile_hit_radius_wu", 0.45), 0.45)
		e["flight_t"] = TypedVariant.as_float(e.get("flight_t", 0.0), 0.0) + delta
		var phase: String = str(e.get("phase", "cruise"))
		var nxt: Vector3 = pos
		var dir: Vector3 = Vector3.UP
		var apply_noise: bool = false
		if phase == "eject":
			e["eject_t"] = TypedVariant.as_float(e.get("eject_t", 0.0), 0.0) + delta
			var eject_spd: float = TypedVariant.as_float(e.get("eject_speed_wu", 0.0), 0.0)
			dir = _dict_vec3(e.get("eject_dir", Vector3.UP), Vector3.UP)
			if dir.length_squared() < 0.0001:
				dir = Vector3.UP
			else:
				dir = dir.normalized()
			nxt = pos + dir * (eject_spd * delta)
			e["pos"] = nxt
			if TypedVariant.as_float(e.get("eject_t", 0.0), 0.0) >= TypedVariant.as_float(e.get("eject_duration_s", 0.0), 0.0):
				e["phase"] = "cruise"
		else:
			var delta_p: Vector3 = to - pos
			var dist: float = delta_p.length()
			var step: float = speed_cells * wu * delta
			if dist <= maxf(hit_r, step) or dist < 0.001:
				mi.global_position = to
				e["pos"] = to
				e["draw_pos"] = to
				return false
			dir = delta_p / dist
			nxt = pos + dir * step
			e["pos"] = nxt
			apply_noise = true
		var draw: Vector3 = nxt
		if apply_noise:
			draw = nxt + _missile_path_offset(e, dir)
		var prev_draw: Vector3 = _dict_vec3(e.get("draw_pos", pos), pos)
		e["draw_pos"] = draw
		mi.global_position = draw
		var trail_v: Variant = e.get("trail")
		if trail_v != null and is_instance_valid(trail_v) and trail_v is Node3D:
			var trail: Node3D = trail_v
			trail.global_position = (draw + prev_draw) * 0.5
			if draw.distance_to(prev_draw) > 0.01:
				trail.look_at(draw, Vector3.UP)
				trail.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		return true
	var firer: ShipUnit = _alive_ship_ref(e, "firer")
	var ja: Vector3 = _dict_vec3(e.get("ja", Vector3.ZERO))
	var from: Vector3 = _dict_vec3(e.get("from", Vector3.ZERO))
	var to2: Vector3 = _dict_vec3(e.get("to", Vector3.ZERO))
	if firer != null:
		from = _muzzle_point(firer) + ja
	to2 = _aim_to(e, jb, to2)
	e["from"] = from
	e["to"] = to2
	var dist2: float = maxf(0.01, from.distance_to(to2))
	e["dist"] = dist2
	var travel_s: float = TypedVariant.as_float(e.get("travel_s", -1.0), -1.0)
	if travel_s > 0.0:
		e["progress"] = TypedVariant.as_float(e.get("progress", 0.0), 0.0) + delta / travel_s
	else:
		var speed: float = TypedVariant.as_float(e.get("speed", 0.0), 0.0)
		e["progress"] = TypedVariant.as_float(e.get("progress", 0.0), 0.0) + (speed * delta) / dist2
	var t: float = clampf(TypedVariant.as_float(e.get("progress", 0.0), 0.0), 0.0, 1.0)
	mi.global_position = from.lerp(to2, t)
	var trail2_v: Variant = e.get("trail")
	if trail2_v != null and is_instance_valid(trail2_v) and trail2_v is Node3D:
		var trail2: Node3D = trail2_v
		var lag2: float = clampf(TypedVariant.as_float(e.get("trail_lag", 0.08), 0.08), 0.02, 0.35)
		var back2: Vector3 = from.lerp(to2, maxf(0.0, t - lag2))
		trail2.global_position = (mi.global_position + back2) * 0.5
		if mi.global_position.distance_to(back2) > 0.01:
			trail2.look_at(mi.global_position, Vector3.UP)
			trail2.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return t < 1.0

## Avoid typed assign from Dictionary when the Object was freed (crashes GDScript).
func _alive_ship_ref(e: Dictionary, key: String) -> ShipUnit:
	var raw: Variant = e.get(key)
	if raw == null or not is_instance_valid(raw):
		e[key] = null
		return null
	if not raw is ShipUnit:
		e[key] = null
		return null
	var ship: ShipUnit = raw
	if bool(ship.is_destroyed):
		return null
	return ship

func _free_entry(e: Dictionary) -> void:
	var sec_v: Variant = e.get("secondary")
	if sec_v != null and is_instance_valid(sec_v) and sec_v is Node:
		@warning_ignore("unsafe_cast")
		(sec_v as Node).queue_free()
	var disc_free: Variant = e.get("target_disc")
	if disc_free != null and is_instance_valid(disc_free) and disc_free is Node:
		@warning_ignore("unsafe_cast")
		(disc_free as Node).queue_free()
	var helix_v: Variant = e.get("helix")
	if helix_v is Array:
		for h_any: Variant in helix_v:
			if h_any != null and is_instance_valid(h_any) and h_any is Node:
				@warning_ignore("unsafe_cast")
				(h_any as Node).queue_free()
	var tracers_v: Variant = e.get("nodes")
	if tracers_v is Array:
		for t_any: Variant in tracers_v:
			if t_any != null and is_instance_valid(t_any) and t_any is Node:
				@warning_ignore("unsafe_cast")
				(t_any as Node).queue_free()
	var n_v: Variant = e.get("node")
	if n_v != null and is_instance_valid(n_v) and n_v is Node:
		@warning_ignore("unsafe_cast")
		(n_v as Node).queue_free()
	var trail_v: Variant = e.get("trail")
	if trail_v != null and is_instance_valid(trail_v) and trail_v is Node:
		@warning_ignore("unsafe_cast")
		(trail_v as Node).queue_free()

func clear_all() -> void:
	for e: Dictionary in _active:
		_free_entry(e)
	_active.clear()
