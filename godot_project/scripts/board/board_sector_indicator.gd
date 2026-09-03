extends RefCounted
class_name BoardSectorIndicator

## Arcs on board-origin circles; radial sides on semipolar rays.
## Corners = ray∩circle intersections; each corner chamfered at 1/4 edge length.

const _SCALE: float = BoardPolarGrid.MARKER_PICK_SCALE
const _FRAME_THIN: float = 0.9
## Border thickness scale (uniform on arcs + radials).
const _FRAME_THICKNESS_RATIO: float = 4.0 / 5.0
## Corner chamfer: connect 1/4 along each adjacent edge (切角).
const _CHAMFER_FRAC: float = 0.25


static func make_field_marker(team: int, ring: int, sector: int) -> MeshInstance3D:
	var dr: float = BoardPolarGrid.ring_delta_r()
	var n_full: int = (
		BoardPolarGrid.sectors_in_ring(ring)
		if ring < BoardPolarGrid.RING_COUNT
		else BoardPolarGrid.ring6_full_sectors()
	)
	var phi_center: float = BoardPolarGrid.sector_center_phi(ring, sector)
	var arc_scale: float = 0.68 if ring == 2 else 0.82
	var arc: float = (PI / float(n_full)) * arc_scale * _SCALE
	var phi_start: float = phi_center - arc * 0.5
	var phi_end: float = phi_center + arc * 0.5
	var r_vis_in: float = BoardPolarGrid.field_marker_visual_r_sem(ring, false)
	var r_vis_out: float = BoardPolarGrid.field_marker_visual_r_sem(ring, true)
	var frame_t: float = maxf(dr * 0.07, 0.045) * _FRAME_THIN * _FRAME_THICKNESS_RATIO
	var mesh_origin: Vector3 = _frame_visual_origin(
		team, ring, phi_start, phi_end, r_vis_in, r_vis_out
	)
	var cell_center: Vector3 = BoardPolarGrid.field_cell_to_world(team, ring, sector)
	var mesh: ArrayMesh = _build_hollow_sector_frame(
		team, ring, r_vis_in, r_vis_out, phi_start, phi_end, frame_t, mesh_origin
	)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(cell_center.x, 0.06, cell_center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.95, 0.85, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_ambient_light = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 0.65)
	mat.emission_energy_multiplier = 0.82
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 0
	mi.material_override = mat
	return mi


static func make_hangar_marker() -> MeshInstance3D:
	var step: float = BoardPolarGrid.hangar_step()
	var outer: float = step * 0.95 * _SCALE
	var frame_t: float = maxf(step * 0.075, 0.04) * _FRAME_THIN
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _square_frame_mesh(outer, frame_t, 0.03)
	mi.position.y = 0.06
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.65, 1.0, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_ambient_light = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.45, 0.85)
	mat.emission_energy_multiplier = 1.0
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 2
	mi.material_override = mat
	return mi


static func _lerp_from_corner(corner: Vector3, along: Vector3, frac: float) -> Vector3:
	return corner.lerp(along, clampf(frac, 0.0, 0.49))


static func _theta_from_corner_toward(th_corner: float, th_target: float, frac: float) -> float:
	var delta: float = wrapf(th_target - th_corner, -PI, PI)
	if absf(delta) < 1e-6:
		return th_corner
	return th_corner + delta * clampf(frac, 0.0, 0.49)


## Semipolar ray (constant phi) ∩ board-origin circle; pick root nearest target semipolar r.
static func _corner_on_board_circle(
		team: int, phi: float, board_r: float, target_sem_r: float
) -> Vector3:
	var s: float = _semipolar_ray_circle_s(team, phi, board_r, target_sem_r)
	s = clampf(s, 0.01, BoardPolarGrid.play_radius() * 1.5)
	var xz: Vector2 = BoardPolarGrid.semipolar_to_world_xz(team, s, phi)
	return Vector3(xz.x, 0.0, xz.y)


static func _semipolar_ray_circle_s(
		team: int, phi: float, board_r: float, target_sem_r: float
) -> float:
	var cz: float = BoardPolarGrid.semi_center_z(team)
	var fwd: float = 1.0 if team == ShipUnit.TEAM_PLAYER else -1.0
	var cp: float = cos(phi)
	var b_coef: float = 2.0 * cz * fwd * cp
	var c_coef: float = cz * cz - board_r * board_r
	var disc: float = b_coef * b_coef - 4.0 * c_coef
	if disc < 0.0:
		return target_sem_r
	var sd: float = sqrt(disc)
	var s_a: float = (-b_coef + sd) * 0.5
	var s_b: float = (-b_coef - sd) * 0.5
	var best: float = target_sem_r
	var best_d: float = INF
	for s_cand: float in [s_a, s_b]:
		if s_cand <= 0.01:
			continue
		var d: float = absf(s_cand - target_sem_r)
		if d < best_d:
			best_d = d
			best = s_cand
	return best


static func _board_origin_vertex(radius: float, theta: float, origin: Vector3 = Vector3.ZERO) -> Vector3:
	return Vector3(radius * sin(theta), 0.0, radius * cos(theta)) - origin


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


static func _xz_dir(from: Vector3, to: Vector3) -> Vector3:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var dir_len: float = sqrt(dx * dx + dz * dz)
	if dir_len < 1e-6:
		return Vector3.ZERO
	return Vector3(dx / dir_len, 0.0, dz / dir_len)


static func _add_line_segment_capped(
		st: SurfaceTool, p_lo: Vector3, p_hi: Vector3, half_w: float, y_hi: float
) -> void:
	_add_line_segment_asymmetric(
		st, p_lo, p_hi, Vector3(-(p_hi.z - p_lo.z), 0.0, p_hi.x - p_lo.x).normalized(),
		half_w, half_w, y_hi
	)


static func _add_line_segment_asymmetric(
		st: SurfaceTool,
		p_lo: Vector3,
		p_hi: Vector3,
		n_inner: Vector3,
		half_w_in: float,
		half_w_out: float,
		y_hi: float
) -> void:
	var dx: float = p_hi.x - p_lo.x
	var dz: float = p_hi.z - p_lo.z
	var seg_len: float = sqrt(dx * dx + dz * dz)
	if seg_len < 1e-5:
		return
	var n_unit: Vector3 = n_inner
	if n_unit.length_squared() < 1e-8:
		n_unit = Vector3(-dz / seg_len, 0.0, dx / seg_len)
	else:
		n_unit = n_unit.normalized()
	var n_in: Vector3 = n_unit * half_w_in
	var n_out: Vector3 = -n_unit * half_w_out
	var a: Vector3 = p_lo + n_in
	var b: Vector3 = p_lo + n_out
	var c: Vector3 = p_hi + n_out
	var d: Vector3 = p_hi + n_in
	_add_quad(st, a, b, c, d)
	var ah: Vector3 = a + Vector3(0.0, y_hi, 0.0)
	var bh: Vector3 = b + Vector3(0.0, y_hi, 0.0)
	var ch: Vector3 = c + Vector3(0.0, y_hi, 0.0)
	var dh: Vector3 = d + Vector3(0.0, y_hi, 0.0)
	_add_quad(st, ah, ch, bh, dh)


static func _add_bevel_join(
		st: SurfaceTool,
		pivot: Vector3,
		p_prev: Vector3,
		p_next: Vector3,
		half_w: float,
		y_hi: float
) -> void:
	var dir_a: Vector3 = _xz_dir(pivot, p_prev)
	var dir_b: Vector3 = _xz_dir(pivot, p_next)
	if dir_a.length_squared() < 1e-8 or dir_b.length_squared() < 1e-8:
		return
	var n_a: Vector3 = Vector3(-dir_a.z, 0.0, dir_a.x) * half_w
	var n_b: Vector3 = Vector3(-dir_b.z, 0.0, dir_b.x) * half_w
	var v0: Vector3 = pivot + n_a
	var v1: Vector3 = pivot + n_b
	var v2: Vector3 = pivot - n_b
	var v3: Vector3 = pivot - n_a
	_add_quad(st, v0, v1, v2, v3)
	var v0h: Vector3 = v0 + Vector3(0.0, y_hi, 0.0)
	var v1h: Vector3 = v1 + Vector3(0.0, y_hi, 0.0)
	var v2h: Vector3 = v2 + Vector3(0.0, y_hi, 0.0)
	var v3h: Vector3 = v3 + Vector3(0.0, y_hi, 0.0)
	_add_quad(st, v0h, v1h, v2h, v3h)


static func _add_polyline_strip_beveled(st: SurfaceTool, points: PackedVector3Array, half_w: float) -> void:
	var n: int = points.size()
	if n < 2:
		return
	var y_hi: float = 0.03
	for i: int in range(n - 1):
		_add_line_segment_capped(st, points[i], points[i + 1], half_w, y_hi)
	for i: int in range(1, n - 1):
		_add_bevel_join(st, points[i], points[i - 1], points[i + 1], half_w, y_hi)


static func _add_arc_endpoint_join(
		st: SurfaceTool,
		r_inner: float,
		r_outer: float,
		theta: float,
		arc_mid: Vector3,
		line_neighbor: Vector3,
		half_w: float,
		mesh_origin: Vector3 = Vector3.ZERO
) -> void:
	var arc_in: Vector3 = _board_origin_vertex(r_inner, theta, mesh_origin)
	var arc_out: Vector3 = _board_origin_vertex(r_outer, theta, mesh_origin)
	var line_dir: Vector3 = _xz_dir(line_neighbor, arc_mid)
	if line_dir.length_squared() < 1e-8:
		return
	var n_line: Vector3 = Vector3(-line_dir.z, 0.0, line_dir.x) * half_w
	var line_lo: Vector3 = arc_mid - n_line
	var line_hi: Vector3 = arc_mid + n_line
	var use_out: bool = line_hi.distance_squared_to(arc_out) < line_lo.distance_squared_to(arc_out)
	var arc_near: Vector3 = arc_out if use_out else arc_in
	var arc_far: Vector3 = arc_in if use_out else arc_out
	var line_near: Vector3 = line_hi if use_out else line_lo
	var line_far: Vector3 = line_lo if use_out else line_hi
	_add_quad(st, arc_near, line_near, line_far, arc_far)
	var y_hi: float = 0.03
	_add_quad(
		st,
		arc_near + Vector3(0.0, y_hi, 0.0),
		line_near + Vector3(0.0, y_hi, 0.0),
		line_far + Vector3(0.0, y_hi, 0.0),
		arc_far + Vector3(0.0, y_hi, 0.0)
	)


static func _add_board_origin_arc_strip(
		st: SurfaceTool,
		r_inner: float,
		r_outer: float,
		theta_a: float,
		theta_b: float,
		mesh_origin: Vector3 = Vector3.ZERO
) -> void:
	if r_outer <= r_inner + 1e-5:
		return
	var ta: float = theta_a
	var tb: float = theta_b
	if absf(wrapf(tb - ta, -PI, PI)) > PI * 0.95:
		return
	if tb < ta:
		var swap: float = ta
		ta = tb
		tb = swap
	if tb <= ta + 1e-6:
		return
	var segments: int = maxi(3, ceili((tb - ta) / (PI / 36.0)))
	for i: int in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var ang_lo: float = lerpf(ta, tb, t0)
		var ang_hi: float = lerpf(ta, tb, t1)
		var p00: Vector3 = _board_origin_vertex(r_inner, ang_lo, mesh_origin)
		var p01: Vector3 = _board_origin_vertex(r_outer, ang_lo, mesh_origin)
		var p10: Vector3 = _board_origin_vertex(r_inner, ang_hi, mesh_origin)
		var p11: Vector3 = _board_origin_vertex(r_outer, ang_hi, mesh_origin)
		st.add_vertex(p00)
		st.add_vertex(p01)
		st.add_vertex(p11)
		st.add_vertex(p00)
		st.add_vertex(p11)
		st.add_vertex(p10)


static func _frame_visual_origin(
		team: int,
		ring: int,
		phi_start: float,
		phi_end: float,
		r_in: float,
		r_out: float
) -> Vector3:
	var r_arc_out: float = maxf(
		BoardPolarGrid.field_marker_board_ring_radius(team, ring, true), 0.2
	)
	var r_arc_in: float = maxf(
		BoardPolarGrid.field_marker_board_ring_radius(team, ring, false), 0.05
	)
	var os: Vector3 = _corner_on_board_circle(team, phi_start, r_arc_out, r_out)
	var oe: Vector3 = _corner_on_board_circle(team, phi_end, r_arc_out, r_out)
	var is_pt: Vector3 = _corner_on_board_circle(team, phi_start, r_arc_in, r_in)
	var ie: Vector3 = _corner_on_board_circle(team, phi_end, r_arc_in, r_in)
	return (os + oe + is_pt + ie) * 0.25


static func _local_point(p: Vector3, origin: Vector3) -> Vector3:
	return p - origin


static func _build_hollow_sector_frame(
		team: int,
		ring: int,
		r_in: float,
		r_out: float,
		phi_start: float,
		phi_end: float,
		frame_t: float,
		mesh_origin: Vector3 = Vector3.ZERO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Same ring → same board-center concentric radii (φ=0 reference on each half).
	var r_arc_out: float = maxf(
		BoardPolarGrid.field_marker_board_ring_radius(team, ring, true), 0.2
	)
	var r_arc_in: float = maxf(
		BoardPolarGrid.field_marker_board_ring_radius(team, ring, false), 0.05
	)
	var os_w: Vector3 = _corner_on_board_circle(team, phi_start, r_arc_out, r_out)
	var oe_w: Vector3 = _corner_on_board_circle(team, phi_end, r_arc_out, r_out)
	var is_w: Vector3 = _corner_on_board_circle(team, phi_start, r_arc_in, r_in)
	var ie_w: Vector3 = _corner_on_board_circle(team, phi_end, r_arc_in, r_in)
	var th_os: float = atan2(os_w.x, os_w.z)
	var th_oe: float = atan2(oe_w.x, oe_w.z)
	var th_is: float = atan2(is_w.x, is_w.z)
	var th_ie: float = atan2(ie_w.x, ie_w.z)
	var os: Vector3 = _local_point(os_w, mesh_origin)
	var oe: Vector3 = _local_point(oe_w, mesh_origin)
	var is_pt: Vector3 = _local_point(is_w, mesh_origin)
	var ie: Vector3 = _local_point(ie_w, mesh_origin)
	var half_w: float = frame_t * 0.5
	var r_mid_out: float = r_arc_out - half_w
	var r_mid_in: float = r_arc_in + half_w
	## Outer / inner arc (trimmed at chamfer angles).
	var th_out_a: float = _theta_from_corner_toward(th_os, th_oe, _CHAMFER_FRAC)
	var th_out_b: float = _theta_from_corner_toward(th_oe, th_os, _CHAMFER_FRAC)
	var th_in_a: float = _theta_from_corner_toward(th_is, th_ie, _CHAMFER_FRAC)
	var th_in_b: float = _theta_from_corner_toward(th_ie, th_is, _CHAMFER_FRAC)
	_add_board_origin_arc_strip(
		st, r_arc_out - frame_t, r_arc_out, th_out_a, th_out_b, mesh_origin
	)
	if r_arc_in > 1e-4:
		_add_board_origin_arc_strip(
			st, r_arc_in, r_arc_in + frame_t, th_in_a, th_in_b, mesh_origin
		)
	## Chamfer anchor points on frame midlines (consistent with arc strips).
	var is_rad_a: Vector3 = _lerp_from_corner(is_pt, os, _CHAMFER_FRAC)
	var os_rad_b: Vector3 = _lerp_from_corner(os, is_pt, _CHAMFER_FRAC)
	var ie_rad_a: Vector3 = _lerp_from_corner(ie, oe, _CHAMFER_FRAC)
	var oe_rad_b: Vector3 = _lerp_from_corner(oe, ie, _CHAMFER_FRAC)
	var arc_os_ch: Vector3 = _board_origin_vertex(r_mid_out, th_out_a, mesh_origin)
	var arc_oe_ch: Vector3 = _board_origin_vertex(r_mid_out, th_out_b, mesh_origin)
	var arc_is_ch: Vector3 = _board_origin_vertex(r_mid_in, th_in_a, mesh_origin)
	var arc_ie_ch: Vector3 = _board_origin_vertex(r_mid_in, th_in_b, mesh_origin)
	## Straight runs: bevel joins (no miter spikes at chamfer corners).
	_add_polyline_strip_beveled(
		st, PackedVector3Array([is_rad_a, os_rad_b, arc_os_ch]), half_w
	)
	_add_polyline_strip_beveled(
		st, PackedVector3Array([arc_oe_ch, oe_rad_b, ie_rad_a]), half_w
	)
	_add_line_segment_capped(st, arc_is_ch, is_rad_a, half_w, 0.03)
	_add_line_segment_capped(st, ie_rad_a, arc_ie_ch, half_w, 0.03)
	_add_bevel_join(st, is_rad_a, arc_is_ch, os_rad_b, half_w, 0.03)
	_add_bevel_join(st, ie_rad_a, oe_rad_b, arc_ie_ch, half_w, 0.03)
	## Arc-line end caps: square patches, no overlapping extrusion.
	_add_arc_endpoint_join(
		st, r_arc_out - frame_t, r_arc_out, th_out_a, arc_os_ch, os_rad_b, half_w, mesh_origin
	)
	_add_arc_endpoint_join(
		st, r_arc_out - frame_t, r_arc_out, th_out_b, arc_oe_ch, oe_rad_b, half_w, mesh_origin
	)
	if r_arc_in > 1e-4:
		_add_arc_endpoint_join(
			st, r_arc_in, r_arc_in + frame_t, th_in_a, arc_is_ch, is_rad_a, half_w, mesh_origin
		)
		_add_arc_endpoint_join(
			st, r_arc_in, r_arc_in + frame_t, th_in_b, arc_ie_ch, ie_rad_a, half_w, mesh_origin
		)
	st.generate_normals()
	return st.commit()


static func _add_line_strip(st: SurfaceTool, p_lo: Vector3, p_hi: Vector3, half_w: float) -> void:
	_add_line_segment_capped(st, p_lo, p_hi, half_w, 0.03)


static func _square_frame_mesh(outer: float, thickness: float, height: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hout: float = outer * 0.5
	var tin: float = hout - thickness
	var segs: Array = [
		[Vector3(-hout, 0, -hout), Vector3(hout, 0, -hout), Vector3(hout, 0, -tin), Vector3(-hout, 0, -tin)],
		[Vector3(-hout, 0, tin), Vector3(hout, 0, tin), Vector3(hout, 0, hout), Vector3(-hout, 0, hout)],
		[Vector3(-hout, 0, -tin), Vector3(-tin, 0, -tin), Vector3(-tin, 0, tin), Vector3(-hout, 0, tin)],
		[Vector3(tin, 0, -tin), Vector3(hout, 0, -tin), Vector3(hout, 0, tin), Vector3(tin, 0, tin)],
	]
	for quad: Array in segs:
		var a: Vector3 = quad[0]
		var b: Vector3 = quad[1]
		var c: Vector3 = quad[2]
		var d: Vector3 = quad[3]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
		var a2: Vector3 = a + Vector3(0, height, 0)
		var b2: Vector3 = b + Vector3(0, height, 0)
		var c2: Vector3 = c + Vector3(0, height, 0)
		var d2: Vector3 = d + Vector3(0, height, 0)
		st.add_vertex(a2); st.add_vertex(c2); st.add_vertex(b2)
		st.add_vertex(a2); st.add_vertex(d2); st.add_vertex(c2)
	st.generate_normals()
	return st.commit()
