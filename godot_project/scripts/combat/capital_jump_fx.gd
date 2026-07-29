extends Node3D
class_name CapitalJumpFx
## Capital cyno warp-in: jump-tunnel flash → red light descent onto the field.

const JUMP_GLOW := "res://assets/vfx/cyno/jumptunnelglow_02a.png"
const JUMP_DIFF := "res://assets/vfx/cyno/jumptunneldiffuse.png"
const FALLBACK := "res://assets/vfx/cyno/cyno_soft.png"

var _ship: ShipUnit = null
var _land: Vector3 = Vector3.ZERO
var _elapsed := 0.0
var _duration := 0.85
var _portal: MeshInstance3D = null
var _light: OmniLight3D = null
var _start_y := 0.0
var _done := false
var _on_done: Callable = Callable()


func play(ship: ShipUnit, land_pos: Vector3, duration: float = 0.85, on_done: Callable = Callable()) -> void:
	_ship = ship
	_land = land_pos
	_duration = maxf(0.35, duration)
	_on_done = on_done
	top_level = true
	global_position = land_pos
	_start_y = land_pos.y + 11.0
	_build()
	if _ship != null and is_instance_valid(_ship):
		_ship.visible = true
		_ship.global_position = Vector3(land_pos.x, _start_y, land_pos.z)
		## Red descent is the portal/light VFX only — never tint HealthBar / hull materials
		## (that made tonnage plate opaque and HP bars stuck red).
	set_process(true)


func _process(delta: float) -> void:
	if _done:
		return
	## Respect match speed if present.
	var mul := 1.0
	var root := get_tree().get_first_node_in_group("match_root")
	if root and root.get("match_ctrl"):
		mul = float(root.match_ctrl.speed_multiplier)
	_elapsed += delta * mul
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	## Ease-in for “落”
	var ease_t := t * t
	if _ship != null and is_instance_valid(_ship):
		var y := lerpf(_start_y, _land.y, ease_t)
		_ship.global_position = Vector3(_land.x, y, _land.z)
	if _portal:
		_portal.rotation.y += delta * mul * 4.0
		var s := lerpf(0.4, 1.6, minf(t * 2.0, 1.0)) * (1.0 if t < 0.7 else lerpf(1.0, 0.2, (t - 0.7) / 0.3))
		_portal.scale = Vector3(s, s, s)
	if _light:
		_light.light_energy = lerpf(6.0, 1.2, ease_t)
	if t >= 1.0:
		_finish()


func _finish() -> void:
	_done = true
	set_process(false)
	if _ship != null and is_instance_valid(_ship):
		_ship.global_position = _land
		_ship.set_combat_tint(true)
		## Heal overlays if an older jump tint already mutated bar/plate materials.
		if _ship.has_method("rebuild_health_bar"):
			_ship.rebuild_health_bar()
	if _on_done.is_valid():
		_on_done.call()
	queue_free()


func _build() -> void:
	var glow := _tex(JUMP_GLOW, FALLBACK)
	var diff := _tex(JUMP_DIFF, FALLBACK)

	_light = OmniLight3D.new()
	_light.name = "JumpLight"
	_light.light_color = Color(1.0, 0.25, 0.15)
	_light.light_energy = 6.0
	_light.omni_range = 10.0
	_light.shadow_enabled = false
	add_child(_light)

	_portal = MeshInstance3D.new()
	_portal.name = "JumpPortal"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.55
	tor.outer_radius = 1.35
	tor.rings = 16
	tor.ring_segments = 24
	_portal.mesh = tor
	_portal.position = Vector3(0, 0.4, 0)
	_portal.material_override = _mat(Color(1.0, 0.35, 0.2, 0.85), glow, 3.5)
	add_child(_portal)

	var disc := MeshInstance3D.new()
	disc.name = "JumpDisc"
	var q := QuadMesh.new()
	q.size = Vector2(3.6, 3.6)
	disc.mesh = q
	disc.rotation_degrees = Vector3(-90, 0, 0)
	disc.position = Vector3(0, 0.05, 0)
	disc.material_override = _mat(Color(1.0, 0.2, 0.12, 0.75), diff if diff else glow, 2.8)
	add_child(disc)

	var sparks := CPUParticles3D.new()
	sparks.name = "JumpSparks"
	sparks.amount = 40
	sparks.lifetime = 0.7
	sparks.emitting = true
	sparks.one_shot = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.8
	sparks.direction = Vector3(0, 1, 0)
	sparks.spread = 40.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 3.5
	sparks.gravity = Vector3(0, -2.0, 0)
	sparks.scale_amount_min = 0.25
	sparks.scale_amount_max = 0.7
	sparks.material_override = _mat(Color(1.0, 0.4, 0.2, 0.95), glow, 2.5, true)
	add_child(sparks)


func _mat(color: Color, tex: Texture2D, emission_e: float, billboard: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	if tex:
		mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = emission_e
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return mat


func _tex(primary: String, fallback: String) -> Texture2D:
	if ResourceLoader.exists(primary):
		var t := load(primary)
		if t is Texture2D:
			return t
	if ResourceLoader.exists(fallback):
		var t2 := load(fallback)
		if t2 is Texture2D:
			return t2
	return null
