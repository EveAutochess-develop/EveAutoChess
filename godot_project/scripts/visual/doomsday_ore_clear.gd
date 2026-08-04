extends RefCounted
class_name DoomsdayOreClear
## Remove asteroid belt rocks intersecting doomsday path volume.

static func clear_along_segment(belt_root: Node3D, from: Vector3, to: Vector3, radius: float = 2.5) -> int:
	if belt_root == null:
		return 0
	var removed: int = 0
	var kids: Array = belt_root.get_children()
	for c: Node in kids:
		if not (c is Node3D):
			continue
		var n: Node3D = c
		if _dist_point_to_segment(n.global_position, from, to) <= radius:
			n.queue_free()
			removed += 1
	return removed

static func _dist_point_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var t: float = 0.0
	var denom: float = ab.length_squared()
	if denom > 0.0001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	var closest: Vector3 = a + ab * t
	return closest.distance_to(p)
