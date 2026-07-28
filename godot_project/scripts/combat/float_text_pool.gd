extends Node
class_name FloatTextPool
## Pooled Label3D damage / heal popups.

var _pool: Array[Label3D] = []
var _active: Array = []  # {label, age, ttl}

func spawn(world_pos: Vector3, text: String, color: Color) -> void:
	var lab := _acquire()
	lab.text = text
	lab.modulate = color
	lab.global_position = world_pos + Vector3(0, 1.2, 0)
	lab.visible = true
	_active.append({"label": lab, "age": 0.0, "ttl": 0.85, "start_y": lab.global_position.y})

func _acquire() -> Label3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font_size = 48
	lab.outline_size = 8
	lab.outline_modulate = Color(0, 0, 0, 0.8)
	lab.no_depth_test = true
	lab.pixel_size = 0.012
	add_child(lab)
	return lab

func _process(delta: float) -> void:
	var i := 0
	while i < _active.size():
		var e: Dictionary = _active[i]
		e["age"] = float(e["age"]) + delta
		var lab: Label3D = e["label"]
		var t := float(e["age"]) / float(e["ttl"])
		lab.global_position.y = float(e["start_y"]) + t * 1.2
		lab.modulate.a = 1.0 - t
		if float(e["age"]) >= float(e["ttl"]):
			lab.visible = false
			_pool.append(lab)
			_active.remove_at(i)
		else:
			i += 1
