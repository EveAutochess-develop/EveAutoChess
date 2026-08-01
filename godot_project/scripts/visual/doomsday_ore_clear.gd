extends RefCounted
class_name DoomsdayOreClear
## Remove asteroid belt rocks intersecting doomsday path volume.

static func clear_along_segment(belt_root: Node3D, from: Vector3, to: Vector3, radius: float = 2.5) -> int:
	if belt_root == null:
		return 0
	var removed := 0
	var kids := belt_root.get_children()
	for c in kids:
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if _dist_point_to_segment(n.global_position, from, to) <= radius:
			n.queue_free()
			removed += 1
	return removed

static func _dist_point_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := 0.0
	var denom := ab.length_squared()
	if denom > 0.0001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	var closest := a + ab * t
	return closest.distance_to(p)
