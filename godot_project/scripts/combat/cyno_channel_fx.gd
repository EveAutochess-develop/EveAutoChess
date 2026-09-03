extends Node3D
class_name CynoChannelFx
## Covert cyno activation VFX (EVE cyno glow textures). Follows a ship in world space.

const SOFT: String = "res://assets/vfx/cyno/cynojammerglow_g.png"
const CONE: String = "res://assets/vfx/cyno/cynoconegradient_01.png"
const ICON: String = "res://assets/vfx/cyno/effectcyno.png"
const FALLBACK_SOFT: String = "res://assets/vfx/cyno/cyno_soft.png"
const FALLBACK_CONE: String = "res://assets/vfx/cyno/cyno_cone.png"

var follow: Node3D = null
var _spin: float = 0.0
var _haze: HeatHazeFx = null


func setup(follow_ship: Node3D) -> void:
	follow = follow_ship
	top_level = true
	_build()
	_sync_pos()


func _process(delta: float) -> void:
	_spin += delta * 1.2
	_sync_pos()
	var ring: Node3D = get_node_or_null("CynoRingQuad") as Node3D
	if ring:
		ring.rotation.y = _spin


func _sync_pos() -> void:
	if follow == null or not is_instance_valid(follow):
		queue_free()
		return
	global_position = follow.global_position + Vector3(0, 0.15, 0)


func _build() -> void:
	var soft: Texture2D = _tex(SOFT, FALLBACK_SOFT)
	var cone: Texture2D = _tex(CONE, FALLBACK_CONE)
	var icon: Texture2D = _tex(ICON, FALLBACK_SOFT)

	var light: OmniLight3D = OmniLight3D.new()
	light.name = "CynoLight"
	light.light_color = Color(0.4, 0.85, 1.0)
	light.light_energy = 4.0
	light.omni_range = 8.0
	light.shadow_enabled = false
	add_child(light)

	## Vertical beam — always visible even if particles fail.
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.name = "CynoBeam"
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.85
	cyl.height = 5.5
	beam.mesh = cyl
	beam.position = Vector3(0, 2.75, 0)
	beam.material_override = _add_mat(Color(0.35, 0.8, 1.0, 0.45), cone if cone else soft, 2.0)
	add_child(beam)

	## Ground glow disc.
	var disc: MeshInstance3D = MeshInstance3D.new()
	disc.name = "CynoDisc"
	var plane: QuadMesh = QuadMesh.new()
	plane.size = Vector2(3.2, 3.2)
	disc.mesh = plane
	disc.rotation_degrees = Vector3(-90, 0, 0)
	disc.position = Vector3(0, 0.08, 0)
	disc.material_override = _add_mat(
		Color(0.5, 0.9, 1.0, 0.7), cone if cone else icon if icon else soft, 2.4
	)
	add_child(disc)

	## Spinning ring billboard (XZ).
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "CynoRingQuad"
	var rq: QuadMesh = QuadMesh.new()
	rq.size = Vector2(2.4, 2.4)
	ring.mesh = rq
	ring.rotation_degrees = Vector3(-90, 0, 0)
	ring.position = Vector3(0, 0.2, 0)
	ring.material_override = _add_mat(Color(0.7, 0.95, 1.0, 0.85), icon if icon else soft, 2.8)
	add_child(ring)

	## Rising sparks.
	var column: CPUParticles3D = CPUParticles3D.new()
	column.name = "CynoColumn"
	column.amount = 36
	column.lifetime = 1.4
	column.preprocess = 0.5
	column.emitting = true
	column.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	column.emission_sphere_radius = 0.45
	column.direction = Vector3(0, 1, 0)
	column.spread = 12.0
	column.initial_velocity_min = 1.5
	column.initial_velocity_max = 3.2
	column.gravity = Vector3(0, 0.6, 0)
	column.scale_amount_min = 0.4
	column.scale_amount_max = 1.0
	column.material_override = _add_mat(Color(0.6, 0.95, 1.0, 0.9), soft, 2.0, true)
	add_child(column)

	if HeatHazeFx.fx_allowed():
		_haze = HeatHazeFx.new()
		_haze.name = "CynoHeatHaze"
		add_child(_haze)
		## Point-center; radius tracks ground disc (~3.2).
		_haze.configure_point(1.7, 0.0065, 1.0, 0.12)


func _add_mat(color: Color, tex: Texture2D, emission_e: float, billboard: bool = false) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_texture = tex
		mat.emission_energy_multiplier = emission_e
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = emission_e
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return mat


func _tex(primary: String, fallback: String) -> Texture2D:
	if ResourceLoader.exists(primary):
		var t: Variant = load(primary)
		if t is Texture2D:
			return t
	if ResourceLoader.exists(fallback):
		var t2: Variant = load(fallback)
		if t2 is Texture2D:
			return t2
	return null
