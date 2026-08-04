extends Node3D
class_name DoomsdayFx
## Titan doomsday beam (MULTIPLAYER_PVP §6): every titan shot uses this one
## presentation. Racial textures/style match the doomsday preview pipeline.

signal finished

const FIRE_S: float = 1.55

const RACE_FX: Dictionary = {
	"amarr": {
		"color": Color(1.0, 0.82, 0.28, 1.0),
		"style": "beam_lightning",
		"beam": "res://assets/vfx/doomsday/a/beam8.png",
		"detail": "res://assets/vfx/doomsday/a/fx_electro_03b.png",
		"flare": "res://assets/vfx/doomsday/a/whitesharp2_gradient.png",
		## Amarr flare texture renders as a broken gold square — beam only.
		"hit_flare": false,
	},
	"caldari": {
		"color": Color(0.35, 0.72, 1.0, 1.0),
		"style": "particle_smoke",
		"beam": "res://assets/vfx/doomsday/c/thick_streaks.png",
		"detail": "res://assets/vfx/doomsday/c/smoke_atlas_01.png",
		"flare": "res://assets/vfx/doomsday/c/outburst12.png",
		"hit_flare": true,
	},
	"gallente": {
		"color": Color(0.35, 1.0, 0.55, 1.0),
		"style": "beam_aurora",
		"beam": "res://assets/vfx/doomsday/g/laser.png",
		"detail": "res://assets/vfx/doomsday/g/lightning5x_h_01.png",
		"flare": "res://assets/vfx/doomsday/g/sun2.png",
		"hit_flare": true,
	},
	"minmatar": {
		"color": Color(1.0, 0.42, 0.12, 1.0),
		"style": "explosion_smoke",
		"beam": "res://assets/vfx/doomsday/m/whitesharphifi.png",
		"detail": "res://assets/vfx/doomsday/m/smoke_atlas_02.png",
		"flare": "res://assets/vfx/doomsday/m/outburst12.png",
		"hit_flare": true,
	},
}

var from_world: Vector3 = Vector3.ZERO
var to_world: Vector3 = Vector3.ZERO

var _def: Dictionary = {}
var _beams: Array[MeshInstance3D] = []
var _flare: MeshInstance3D
var _particles: GPUParticles3D
var _t: float = 0.0
var _start_ms: int = 0


## Fire-and-forget: adds itself under `parent` and frees when the beam ends.
static func play(parent: Node, race: String, from: Vector3, to: Vector3) -> DoomsdayFx:
	if parent == null:
		return null
	var fx: DoomsdayFx = DoomsdayFx.new()
	fx.name = "DoomsdayFx"
	fx.from_world = from
	fx.to_world = to
	var def_v: Variant = RACE_FX.get(race.to_lower(), RACE_FX["caldari"])
	if def_v is Dictionary:
		fx._def = def_v
	else:
		fx._def = RACE_FX["caldari"]
	parent.add_child(fx)
	return fx


func _ready() -> void:
	## Wall-clock presentation — never couple to 倍速 / pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_ms = Time.get_ticks_msec()
	var color: Color = _def_color()
	var outer: MeshInstance3D = _make_beam(str(_def.get("beam", "")), color, 1.15, 0.55)
	var inner: MeshInstance3D = _make_beam(str(_def.get("detail", "")), Color.WHITE.lerp(color, 0.35), 0.4, 0.85)
	_beams = [outer, inner]
	_flare = _make_flare(color)
	var style: String = str(_def.get("style", ""))
	if style == "particle_smoke" or style == "explosion_smoke":
		_particles = _make_particles(color, style == "particle_smoke")


func _def_color() -> Color:
	var c_v: Variant = _def.get("color", Color.WHITE)
	if c_v is Color:
		return c_v
	return Color.WHITE


func _process(_delta: float) -> void:
	_t = float(Time.get_ticks_msec() - _start_ms) * 0.001
	if _t >= FIRE_S:
		finished.emit()
		queue_free()
		return
	_tick(_envelope(_t), _delta)


func _envelope(t: float) -> float:
	if t < 0.0 or t >= FIRE_S:
		return 0.0
	if t < 0.35:
		return t / 0.35 * 0.35
	var amt: float = 0.35 + 0.65 * clampf((t - 0.35) / 0.25, 0.0, 1.0)
	if t > FIRE_S - 0.4:
		amt *= clampf((FIRE_S - t) / 0.4, 0.0, 1.0)
	return amt


func _tick(amt: float, delta: float) -> void:
	var mid: Vector3 = (from_world + to_world) * 0.5
	var length: float = from_world.distance_to(to_world)
	if length < 0.001:
		return
	var dir: Vector3 = (to_world - from_world).normalized()
	for mesh_i: MeshInstance3D in _beams:
		var w: float = TypedVariant.as_float(mesh_i.get_meta("beam_width", 0.6), 0.6)
		var a: float = TypedVariant.as_float(mesh_i.get_meta("beam_alpha", 0.7), 0.7)
		mesh_i.visible = amt > 0.02
		if not mesh_i.visible:
			continue
		var right: Vector3 = dir.cross(Vector3.UP)
		if right.length_squared() < 1e-6:
			right = dir.cross(Vector3.RIGHT)
		right = right.normalized()
		var fwd: Vector3 = right.cross(dir).normalized()
		mesh_i.global_transform = Transform3D(Basis(right, dir, fwd), mid)
		mesh_i.scale = Vector3(w * (0.55 + amt), length, w * (0.55 + amt))
		var mat: StandardMaterial3D = mesh_i.material_override as StandardMaterial3D
		if mat == null:
			continue
		var col: Color = mat.albedo_color
		col.a = a * amt
		mat.albedo_color = col
		mat.emission_energy_multiplier = 1.2 + amt * 2.4
		mat.uv1_offset.y = fmod(mat.uv1_offset.y - delta * (1.8 + amt * 2.5), 1.0)
	var use_flare: bool = TypedVariant.as_bool(_def.get("hit_flare", true), true)
	_flare.visible = use_flare and amt > 0.02
	_flare.global_position = to_world
	var fmat: StandardMaterial3D = _flare.material_override as StandardMaterial3D
	if fmat != null:
		var fc: Color = fmat.albedo_color
		fc.a = amt * amt * 0.95 if use_flare else 0.0
		fmat.albedo_color = fc
	_flare.scale = Vector3.ONE * (1.2 + amt * 3.2)
	if _particles:
		_particles.emitting = amt > 0.4
		_particles.global_transform = Transform3D(
			Basis.looking_at(dir, Vector3.UP), from_world.lerp(to_world, 0.12)
		)


func _make_beam(tex_path: String, color: Color, width: float, alpha: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	mi.mesh = box
	mi.top_level = true
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	if ResourceLoader.exists(tex_path):
		var tex_v: Variant = load(tex_path)
		if tex_v is Texture2D:
			mat.albedo_texture = tex_v
		mat.uv1_scale = Vector3(1, 4, 1)
	mi.material_override = mat
	mi.set_meta("beam_width", width)
	mi.set_meta("beam_alpha", alpha)
	mi.visible = false
	add_child(mi)
	return mi


func _make_flare(color: Color) -> MeshInstance3D:
	var flare: MeshInstance3D = MeshInstance3D.new()
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(2.8, 2.8)
	flare.mesh = q
	flare.top_level = true
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var flare_path: String = str(_def.get("flare", ""))
	if ResourceLoader.exists(flare_path):
		var tex_v: Variant = load(flare_path)
		if tex_v is Texture2D:
			fmat.albedo_texture = tex_v
	fmat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	fmat.emission_enabled = true
	fmat.emission = color
	fmat.emission_energy_multiplier = 2.2
	flare.material_override = fmat
	flare.visible = false
	add_child(flare)
	return flare


func _make_particles(color: Color, is_caldari: bool) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.amount = 48 if is_caldari else 64
	particles.lifetime = 0.9
	particles.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	particles.local_coords = true
	particles.top_level = true
	var pmat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 0, -1)
	pmat.spread = 2.5 if is_caldari else 4.0
	pmat.initial_velocity_min = 8.0
	pmat.initial_velocity_max = 22.0
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.35
	pmat.scale_max = 1.2
	pmat.color = Color(color.r, color.g, color.b, 0.85)
	particles.process_material = pmat
	var draw: QuadMesh = QuadMesh.new()
	draw.size = Vector2(0.65, 0.65)
	var dmat: StandardMaterial3D = StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var detail: String = str(_def.get("detail", ""))
	if ResourceLoader.exists(detail):
		var tex_v: Variant = load(detail)
		if tex_v is Texture2D:
			dmat.albedo_texture = tex_v
	dmat.albedo_color = Color(color.r, color.g, color.b, 0.7)
	draw.material = dmat
	particles.draw_pass_1 = draw
	particles.emitting = false
	add_child(particles)
	return particles
