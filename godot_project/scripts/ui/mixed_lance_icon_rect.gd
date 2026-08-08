extends ColorRect
## Drives MixedLanceIcon 2D shader sweep (CAPITAL §4.1).

const _SWEEP_RATE: float = 0.28

func _process(_delta: float) -> void:
	var mat_v: Variant = material
	if typeof(mat_v) != TYPE_OBJECT:
		return
	if not (mat_v is ShaderMaterial):
		return
	var sm: ShaderMaterial = mat_v
	sm.set_shader_parameter("sweep_rad", Time.get_ticks_msec() * 0.001 * _SWEEP_RATE)
