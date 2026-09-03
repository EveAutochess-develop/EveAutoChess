extends Node3D
class_name BoardPrepareRadar

## Prepare-phase planar radar sweep (BOARD_AND_INPUT · 20s / 720°).
## Ring ticks = board-origin arc strips (same family as field marker arcs).

const RING_TRAIL_ARC_DEG: float = 5.0
const SWEEP_ARC_DEG: float = 5.0

var _sweep_pivot: Node3D = null
var _arm: MeshInstance3D = null
var _ring_trails: Array[MeshInstance3D] = []
var _sweep_deg: float = 0.0
var _active: bool = false
var _was_active: bool = false
var _board: BoardController = null
var _ships_in_beam: Dictionary = {}
var _arm_arc_rad: float = -1.0


func setup(board: BoardController) -> void:
	_board = board
	_rebuild_radar_meshes()
	if _active:
		set_process(true)


func set_active(v: bool) -> void:
	if v and not _was_active:
		_sweep_deg = randf() * 360.0
		_apply_sweep_rotation()
	_was_active = v
	_active = v
	visible = v
	if _sweep_pivot:
		_sweep_pivot.visible = v
	if _arm:
		_arm.visible = v
	for trail_mi: MeshInstance3D in _ring_trails:
		if trail_mi != null and is_instance_valid(trail_mi):
			trail_mi.visible = v
	set_process(v)
	if not v:
		_clear_all_flashes()


func _apply_sweep_rotation() -> void:
	if _sweep_pivot != null:
		_sweep_pivot.rotation.y = deg_to_rad(_sweep_deg)


func _rebuild_radar_meshes() -> void:
	for child: Node in get_children():
		child.queue_free()
	_sweep_pivot = null
	_arm = null
	_ring_trails.clear()
	_arm_arc_rad = -1.0
	_sweep_pivot = Node3D.new()
	_sweep_pivot.name = "SweepPivot"
	_sweep_pivot.position = Vector3(0.0, _deck_y(), 0.0)
	add_child(_sweep_pivot)
	_ensure_arm()
	_ensure_ring_trails()


func _sweep_arc_deg() -> float:
	return TypedVariant.as_float(
		DataStore.visual.get("prepare_radar_arc_deg", SWEEP_ARC_DEG), SWEEP_ARC_DEG
	)


func _sweep_arc_rad() -> float:
	return deg_to_rad(maxf(_sweep_arc_deg(), 0.5))


func _ring_trail_arc_rad() -> float:
	var arc_deg: float = TypedVariant.as_float(
		DataStore.visual.get("prepare_radar_ring_trail_arc_deg", RING_TRAIL_ARC_DEG), RING_TRAIL_ARC_DEG
	)
	return deg_to_rad(maxf(arc_deg, 0.5))


func _deck_y() -> float:
	return BoardController.DECK_Y + 0.1


func _beam_alpha_outer() -> float:
	return minf(
		TypedVariant.as_float(DataStore.visual.get("prepare_radar_beam_alpha_outer", 0.28), 0.28),
		0.29
	)


## Radial: a=0 at hub and outer rim; bell peak mid-disk (radar PPI).
func _radial_radar_mask(r: float, r_max: float) -> float:
	if r_max <= 0.001:
		return 0.0
	var t: float = clampf(r / r_max, 0.0, 1.0)
	return sin(PI * t)


## x = angular distance behind sweep leading edge (rad). Factor ∝ 1/x (normalized: 1 at leading).
func _leading_edge_eps(arc_rad: float) -> float:
	return maxf(arc_rad * 0.02, deg_to_rad(0.05))


func _distance_behind_leading(ang: float, half_arc: float, arc_rad: float) -> float:
	return maxf(half_arc - ang, _leading_edge_eps(arc_rad))


func _inverse_leading_factor(x_behind: float, arc_rad: float) -> float:
	var x_eps: float = _leading_edge_eps(arc_rad)
	var x: float = maxf(x_behind, x_eps)
	return x_eps / x


func _sweep_vertex_mask(r: float, r_max: float, ang: float, half_arc: float, arc_rad: float) -> float:
	var x_behind: float = _distance_behind_leading(ang, half_arc, arc_rad)
	return _radial_radar_mask(r, r_max) * _inverse_leading_factor(x_behind, arc_rad)


func _radar_tint_alpha(mask: float) -> Color:
	var peak: float = _beam_alpha_outer()
	return Color(1.0, 1.0, 1.0, mask * peak)


func _beam_emission_color() -> Color:
	return Color(0.12, 0.78, 0.55)


## Same mask as sweep fan vertices (radial bell × 1/x trail). 0 = outside arc or disk.
func _sample_sweep_mask_at_xz(px: float, pz: float) -> float:
	var r_lim: float = BoardPolarGrid.play_radius()
	var dist: float = sqrt(px * px + pz * pz)
	if dist > r_lim or dist < 0.01:
		return 0.0
	var world_ang: float = atan2(px, pz)
	var arm_rad: float = deg_to_rad(_sweep_deg)
	var arc_rad: float = _sweep_arc_rad()
	var half: float = arc_rad * 0.5
	var fan_ang: float = wrapf(world_ang - arm_rad, -PI, PI)
	if fan_ang < -half - 1e-5 or fan_ang > half + 1e-5:
		return 0.0
	return _sweep_vertex_mask(dist, r_lim, fan_ang, half, arc_rad)


## Vertex albedo sample on the sweep fan at board XZ (real-time leading-edge sample).
func _sample_sweep_tint_at_xz(px: float, pz: float) -> Color:
	return _radar_tint_alpha(_sample_sweep_mask_at_xz(px, pz))


func _build_sweep_fan_mesh(radius: float, arc_rad: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = arc_rad * 0.5
	var ang_segs: int = maxi(12, ceili(arc_rad / deg_to_rad(0.25)))
	var rad_segs: int = maxi(16, ceili(radius / 1.2))
	var y_lo: float = 0.0
	var y_hi: float = 0.05
	for ri: int in range(rad_segs):
		var r0: float = radius * float(ri) / float(rad_segs)
		var r1: float = radius * float(ri + 1) / float(rad_segs)
		for ai: int in range(ang_segs):
			var t0: float = float(ai) / float(ang_segs)
			var t1: float = float(ai + 1) / float(ang_segs)
			var ang_lo: float = -half + arc_rad * t0
			var ang_hi: float = -half + arc_rad * t1
			var m00: float = _sweep_vertex_mask(r0, radius, ang_lo, half, arc_rad)
			var m01: float = _sweep_vertex_mask(r0, radius, ang_hi, half, arc_rad)
			var m10: float = _sweep_vertex_mask(r1, radius, ang_lo, half, arc_rad)
			var m11: float = _sweep_vertex_mask(r1, radius, ang_hi, half, arc_rad)
			var p00: Vector3 = Vector3(r0 * sin(ang_lo), y_lo, r0 * cos(ang_lo))
			var p01: Vector3 = Vector3(r0 * sin(ang_hi), y_lo, r0 * cos(ang_hi))
			var p10: Vector3 = Vector3(r1 * sin(ang_lo), y_lo, r1 * cos(ang_lo))
			var p11: Vector3 = Vector3(r1 * sin(ang_hi), y_lo, r1 * cos(ang_hi))
			var p00h: Vector3 = Vector3(r0 * sin(ang_lo), y_hi, r0 * cos(ang_lo))
			var p01h: Vector3 = Vector3(r0 * sin(ang_hi), y_hi, r0 * cos(ang_hi))
			var p10h: Vector3 = Vector3(r1 * sin(ang_lo), y_hi, r1 * cos(ang_lo))
			var p11h: Vector3 = Vector3(r1 * sin(ang_hi), y_hi, r1 * cos(ang_hi))
			st.set_color(_radar_tint_alpha(m00))
			st.add_vertex(p00)
			st.set_color(_radar_tint_alpha(m01))
			st.add_vertex(p01)
			st.set_color(_radar_tint_alpha(m11))
			st.add_vertex(p11)
			st.set_color(_radar_tint_alpha(m00))
			st.add_vertex(p00)
			st.set_color(_radar_tint_alpha(m11))
			st.add_vertex(p11)
			st.set_color(_radar_tint_alpha(m10))
			st.add_vertex(p10)
			st.set_color(_radar_tint_alpha(m00))
			st.add_vertex(p00h)
			st.set_color(_radar_tint_alpha(m01))
			st.add_vertex(p01h)
			st.set_color(_radar_tint_alpha(m11))
			st.add_vertex(p11h)
			st.set_color(_radar_tint_alpha(m00))
			st.add_vertex(p00h)
			st.set_color(_radar_tint_alpha(m11))
			st.add_vertex(p11h)
			st.set_color(_radar_tint_alpha(m10))
			st.add_vertex(p10h)
	st.generate_normals()
	return st.commit()


func _build_board_arc_tick_mesh(
		r_board: float,
		r_lim: float,
		tick_arc_rad: float,
		sweep_arc_rad: float,
		thickness: float
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = tick_arc_rad * 0.5
	var sweep_half: float = sweep_arc_rad * 0.5
	var segments: int = maxi(3, ceili(tick_arc_rad / deg_to_rad(0.5)))
	var r_in: float = maxf(r_board - thickness * 0.5, 0.05)
	var r_out: float = r_board + thickness * 0.5
	var y_lo: float = 0.0
	var y_hi: float = 0.035
	var radial_peak: float = _radial_radar_mask(r_board, r_lim)
	for i: int in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var ang_lo: float = -half + tick_arc_rad * t0
		var ang_hi: float = -half + tick_arc_rad * t1
		var x_lo: float = _distance_behind_leading(ang_lo, sweep_half, sweep_arc_rad)
		var x_hi: float = _distance_behind_leading(ang_hi, sweep_half, sweep_arc_rad)
		var mask_lo: float = radial_peak * _inverse_leading_factor(x_lo, sweep_arc_rad)
		var mask_hi: float = radial_peak * _inverse_leading_factor(x_hi, sweep_arc_rad)
		var va0: Vector3 = Vector3(r_in * sin(ang_lo), y_lo, r_in * cos(ang_lo))
		var va1: Vector3 = Vector3(r_out * sin(ang_lo), y_lo, r_out * cos(ang_lo))
		var vb0: Vector3 = Vector3(r_in * sin(ang_hi), y_lo, r_in * cos(ang_hi))
		var vb1: Vector3 = Vector3(r_out * sin(ang_hi), y_lo, r_out * cos(ang_hi))
		var va0h: Vector3 = Vector3(r_in * sin(ang_lo), y_hi, r_in * cos(ang_lo))
		var va1h: Vector3 = Vector3(r_out * sin(ang_lo), y_hi, r_out * cos(ang_lo))
		var vb0h: Vector3 = Vector3(r_in * sin(ang_hi), y_hi, r_in * cos(ang_hi))
		var vb1h: Vector3 = Vector3(r_out * sin(ang_hi), y_hi, r_out * cos(ang_hi))
		st.set_color(_radar_tint_alpha(mask_lo))
		st.add_vertex(va0)
		st.set_color(_radar_tint_alpha(mask_lo))
		st.add_vertex(va1)
		st.set_color(_radar_tint_alpha(mask_hi))
		st.add_vertex(vb1)
		st.add_vertex(va0)
		st.add_vertex(vb1)
		st.add_vertex(vb0)
		st.set_color(_radar_tint_alpha(mask_lo))
		st.add_vertex(va0h)
		st.set_color(_radar_tint_alpha(mask_lo))
		st.add_vertex(va1h)
		st.set_color(_radar_tint_alpha(mask_hi))
		st.add_vertex(vb1h)
		st.add_vertex(va0h)
		st.add_vertex(vb1h)
		st.add_vertex(vb0h)
	st.generate_normals()
	return st.commit()


func _ensure_arm() -> void:
	if _sweep_pivot == null:
		return
	if _arm != null and is_instance_valid(_arm):
		return
	_arm = MeshInstance3D.new()
	_arm.name = "RadarArm"
	_sweep_pivot.add_child(_arm)
	_arm.position = Vector3.ZERO
	_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arm.material_override = _make_arm_material()
	_arm.sorting_offset = 6.0
	_refresh_arm_mesh()


func _refresh_arm_mesh() -> void:
	if _arm == null or not is_instance_valid(_arm):
		return
	var arc_rad: float = _sweep_arc_rad()
	if is_equal_approx(_arm_arc_rad, arc_rad) and _arm.mesh != null:
		return
	_arm_arc_rad = arc_rad
	var r: float = BoardPolarGrid.play_radius()
	_arm.mesh = _build_sweep_fan_mesh(r, arc_rad)


func _ring_tick_board_radius(ring: int, sweep_rad: float) -> float:
	var team: int = ShipUnit.TEAM_PLAYER if cos(sweep_rad) >= 0.0 else ShipUnit.TEAM_AI
	return BoardPolarGrid.field_marker_board_ring_radius(team, ring, true)


func _ensure_ring_trails() -> void:
	if _sweep_pivot == null:
		return
	var dr: float = BoardPolarGrid.ring_delta_r()
	var tick_t: float = maxf(dr * 0.07, 0.045) * 0.9
	var arc_rad: float = _ring_trail_arc_rad()
	for ring: int in range(1, BoardPolarGrid.RING_COUNT + 1):
		var r_board: float = _ring_tick_board_radius(ring, 0.0)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "RingTrail%d" % ring
		mi.mesh = _build_board_arc_tick_mesh(
			r_board, BoardPolarGrid.play_radius(), arc_rad, _sweep_arc_rad(), tick_t
		)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _make_tick_material()
		mi.sorting_offset = 2.0
		mi.set_meta(&"ring", ring)
		_sweep_pivot.add_child(mi)
		_ring_trails.append(mi)


func _make_arm_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.95, 0.7, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_ambient_light = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.render_priority = 8
	mat.emission_enabled = true
	mat.emission = _beam_emission_color()
	mat.emission_energy_multiplier = _beam_alpha_outer() * 1.1
	return mat


func _make_tick_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.95, 0.7, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_ambient_light = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.render_priority = 7
	mat.emission_enabled = true
	mat.emission = _beam_emission_color()
	mat.emission_energy_multiplier = _beam_alpha_outer()
	return mat


func _fade_arc_deg() -> float:
	return TypedVariant.as_float(
		DataStore.visual.get("prepare_radar_fade_arc_deg", 2.0), 2.0
	)


func _sync_beam_materials() -> void:
	var outer_a: float = _beam_alpha_outer()
	var r_lim: float = maxf(BoardPolarGrid.play_radius(), 0.01)
	var sweep_rad: float = deg_to_rad(_sweep_deg)
	if _arm != null and (_arm.material_override is StandardMaterial3D):
		var sm: StandardMaterial3D = _arm.material_override as StandardMaterial3D
		sm.emission_energy_multiplier = outer_a * 1.1
	for trail_mi: MeshInstance3D in _ring_trails:
		if trail_mi == null or not is_instance_valid(trail_mi):
			continue
		var ring: int = TypedVariant.as_int(trail_mi.get_meta(&"ring", 1), 1)
		var r_board: float = _ring_tick_board_radius(ring, sweep_rad)
		_rebuild_ring_tick_mesh(trail_mi, r_board, r_lim)
		if trail_mi.material_override is StandardMaterial3D:
			var tsm: StandardMaterial3D = trail_mi.material_override as StandardMaterial3D
			tsm.emission_energy_multiplier = outer_a


func _rebuild_ring_tick_mesh(mi: MeshInstance3D, r_board: float, r_lim: float) -> void:
	var dr: float = BoardPolarGrid.ring_delta_r()
	var tick_t: float = maxf(dr * 0.07, 0.045) * 0.9
	var arc_rad: float = _ring_trail_arc_rad()
	var sig: float = r_board
	if mi.has_meta(&"r_sig") and is_equal_approx(TypedVariant.as_float(mi.get_meta(&"r_sig"), 0.0), sig):
		return
	mi.set_meta(&"r_sig", sig)
	mi.mesh = _build_board_arc_tick_mesh(r_board, r_lim, arc_rad, _sweep_arc_rad(), tick_t)


func _process(delta: float) -> void:
	if not _active:
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		return
	var period: float = TypedVariant.as_float(DataStore.visual.get("prepare_radar_period_s", 20.0), 20.0)
	if period <= 0.01:
		period = 20.0
	var deg_per_s: float = 720.0 / period
	_sweep_deg = fmod(_sweep_deg + deg_per_s * delta, 360.0)
	_apply_sweep_rotation()
	_sync_beam_materials()
	_update_ship_flashes()


func _hit_angle_rad() -> float:
	var hit_deg: float = TypedVariant.as_float(
		DataStore.visual.get("prepare_radar_hit_angle_deg", -1.0), -1.0
	)
	if hit_deg < 0.0:
		hit_deg = _sweep_arc_deg() * 0.5
	return deg_to_rad(maxf(hit_deg, 0.05))


func _update_ship_flashes() -> void:
	if _board == null:
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		return
	var peak_a: float = _beam_alpha_outer()
	var beam_em: Color = _beam_emission_color()
	var in_beam: Dictionary = {}
	for s: ShipUnit in _board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if s.slot_type != "field":
			continue
		if not _board.is_board_piece(s):
			continue
		var cell: Vector3 = BoardPolarGrid.field_cell_to_world(s.team_id, s.grid_x, s.grid_z)
		var mask: float = _sample_sweep_mask_at_xz(cell.x, cell.z)
		if mask <= 0.001:
			continue
		var beam_sample: Color = _radar_tint_alpha(mask)
		var sid: int = s.get_instance_id()
		in_beam[sid] = true
		if s.has_method("apply_prepare_radar_flash"):
			s.apply_prepare_radar_flash(mask, beam_sample, beam_em, peak_a)
	for sid_v: Variant in _ships_in_beam.keys():
		var sid: int = TypedVariant.as_int(sid_v, 0)
		if in_beam.has(sid):
			continue
		for s2: ShipUnit in _board.all_ships():
			if s2 != null and is_instance_valid(s2) and s2.get_instance_id() == sid:
				if s2.has_method("clear_prepare_radar_flash"):
					s2.clear_prepare_radar_flash()
				break
	_ships_in_beam = in_beam


func _clear_all_flashes() -> void:
	if _board == null:
		return
	for s: ShipUnit in _board.all_ships():
		if s != null and is_instance_valid(s) and s.has_method("clear_prepare_radar_flash"):
			s.clear_prepare_radar_flash()
	_ships_in_beam.clear()
