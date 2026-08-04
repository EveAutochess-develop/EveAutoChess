extends Node
class_name FloatTextPool
## Pooled Label3D damage / heal popups.

var _pool: Array[Label3D] = []
var _active: Array = []  # {label, age, ttl}

func spawn(world_pos: Vector3, text: String, color: Color) -> void:
	var lab: Label3D = _acquire()
	lab.text = text
	lab.modulate = color
	lab.global_position = world_pos + Vector3(0, 1.2, 0)
	lab.visible = true
	_active.append({"label": lab, "age": 0.0, "ttl": 0.85, "start_y": lab.global_position.y})

func _acquire() -> Label3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var lab: Label3D = Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font_size = 48
	lab.outline_size = 8
	lab.outline_modulate = Color(0, 0, 0, 0.8)
	lab.no_depth_test = true
	lab.pixel_size = 0.012
	add_child(lab)
	return lab

func _process(delta: float) -> void:
	var i: int = 0
	while i < _active.size():
		var e: Dictionary = TypedVariant.as_dict(_active[i])
		e["age"] = TypedVariant.as_float(e.get("age", 0.0)) + delta
		var lab_v: Variant = e.get("label")
		if not (lab_v is Label3D):
			_active.remove_at(i)
			continue
		@warning_ignore("unsafe_cast")
		var lab: Label3D = lab_v as Label3D
		var t: float = TypedVariant.as_float(e.get("age", 0.0)) / maxf(TypedVariant.as_float(e.get("ttl", 0.85), 0.85), 0.0001)
		lab.global_position.y = TypedVariant.as_float(e.get("start_y", lab.global_position.y)) + t * 1.2
		lab.modulate.a = 1.0 - t
		if TypedVariant.as_float(e.get("age", 0.0)) >= TypedVariant.as_float(e.get("ttl", 0.85), 0.85):
			lab.visible = false
			_pool.append(lab)
			_active.remove_at(i)
		else:
			i += 1
