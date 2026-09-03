extends RefCounted
class_name BoardPolarGrid

## Polar circle board geometry (BOARD_AND_INPUT §2 · D=39 · 62 Field + 18 Hangar).

const LAYOUT_POLAR: String = "polar_circle"
const RING_COUNT: int = 6
const SECTORS_RING6_FULL: int = 22
const SECTORS_RING6_FIELD: int = 16
const SHOULDER_SKIP_PER_SIDE: int = 3
## Re-balance ring6: un-skip inner wing sectors, skip bottom-center instead (wings 4 vs 3).
## Per-corner local (lx,lz); skips (2,2) inner cell closest to play disk.
const HANGAR_LOCAL_MAX_LX: int = 2
const HANGAR_LOCAL_MAX_LZ: int = 2
const HANGAR_CORNER_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	Vector2i(0, 2), Vector2i(1, 2),
]
const MARKER_PICK_SCALE: float = sqrt(2.0 / 3.0)

static var _ring6_skip_sectors: PackedInt32Array = PackedInt32Array()
static var _ring6_skip_sig: String = ""


static func is_polar() -> bool:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	return str(b.get("layout", LAYOUT_POLAR)) == LAYOUT_POLAR


static func play_diameter() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	return TypedVariant.as_float(b.get("play_diameter", 39.0), 39.0)


static func play_radius() -> float:
	return play_diameter() * 0.5


static func isolation_half_width() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var frac: float = TypedVariant.as_float(b.get("isolation_frac", 1.0 / 9.0), 1.0 / 9.0)
	return play_diameter() * frac * 0.5


static func semi_radius() -> float:
	return play_diameter() * 4.0 / 9.0


static func ring_delta_r() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var rings: int = maxi(1, TypedVariant.as_int(b.get("field_rings", RING_COUNT), RING_COUNT))
	return semi_radius() / float(rings)


static func cell_step_wu() -> float:
	return ring_delta_r()


static func semi_center_z(team: int) -> float:
	var sign_z: float = 1.0 if team == ShipUnit.TEAM_PLAYER else -1.0
	return sign_z * isolation_half_width()


static func board_outer_span_z() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	if b.has("board_outer_span_z"):
		return TypedVariant.as_float(b.get("board_outer_span_z", 20.286), 20.286)
	## Legacy hex half-depth: hangar row outer edge from field_origin + hangar offset.
	var fh: int = TypedVariant.as_int(b.get("field_height", 6), 6)
	var hoz: float = absf(TypedVariant.as_float(b.get("hex_offset_z", -2.5), -2.5))
	var gap: float = TypedVariant.as_float(b.get("center_gap_z", 4.0), 4.0)
	var fw: int = TypedVariant.as_int(b.get("field_width", 12), 12)
	var extra: int = TypedVariant.as_int(b.get("field_odd_row_extra", 1), 1)
	var hox: float = absf(TypedVariant.as_float(b.get("hex_offset_x", -3.0), -3.0))
	var widest: int = fw + maxi(0, extra)
	var span_x: float = float(widest - 1) * hox
	var legacy_hw: int = maxi(2, TypedVariant.as_int(b.get("hangar_width", 15), 15))
	var legacy_hangar_step: float = span_x / float(legacy_hw - 1)
	var fo_z: float = float(fh - 1) * hoz + gap
	var hangar_z: float = fo_z + hoz
	return hangar_z + legacy_hangar_step * 0.5


static func hangar_cell_step_mul() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	return TypedVariant.as_float(b.get("hangar_cell_step_mul", 0.72), 0.72)


## Outward span scale for hangar 3×3 corners; inner row/col (board-facing) stays fixed.
static func hangar_span_scale() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	return maxf(0.5, TypedVariant.as_float(b.get("hangar_span_scale", 1.0), 1.0))


static func hangar_step_base() -> float:
	return ring_delta_r() * hangar_cell_step_mul()


static func hangar_step() -> float:
	return hangar_step_base() * hangar_span_scale()


static func hangar_inset_wu() -> float:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	var steps: float = TypedVariant.as_float(b.get("hangar_inset_steps", 0.5), 0.5)
	return hangar_step_base() * steps


static func hangar_width() -> int:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	return maxi(1, TypedVariant.as_int(b.get("hangar_width", 16), 16))


static func hangar_per_corner() -> int:
	var b: Dictionary = TypedVariant.as_dict(DataStore.board)
	return maxi(1, TypedVariant.as_int(b.get("hangar_per_corner", 8), 8))


static func sectors_in_ring(ring: int) -> int:
	if ring < 1 or ring > RING_COUNT:
		return 0
	if ring == RING_COUNT:
		return SECTORS_RING6_FIELD
	return 2 * (2 * ring - 1)


static func ring6_full_sectors() -> int:
	return SECTORS_RING6_FULL


static func ring6_skip_sectors() -> PackedInt32Array:
	_ensure_ring6_skip_cache()
	return _ring6_skip_sectors


static func is_ring6_field_sector(sector: int) -> bool:
	_ensure_ring6_skip_cache()
	return not _ring6_skip_sectors.has(sector)


static func field_cell_count() -> int:
	var n: int = 0
	for ring: int in range(1, RING_COUNT + 1):
		var n_sectors: int = sectors_in_ring(ring) if ring < RING_COUNT else SECTORS_RING6_FULL
		for sector: int in range(n_sectors):
			if is_valid_field_cell(ring, sector):
				n += 1
	return n


static func is_center_skipped_field_cell(ring: int, _sector: int) -> bool:
	## Only innermost ring (2 sectors) removed toward isolation; ring 2 keeps center cells.
	return ring == 1


static func ring_inner_radius(ring: int) -> float:
	return maxf(float(ring - 1), 0.0) * ring_delta_r()


static func ring_outer_radius(ring: int) -> float:
	return float(ring) * ring_delta_r()


## Field marker visual band (must match BoardSectorIndicator).
static func field_marker_visual_r_sem(ring: int, outer: bool = true) -> float:
	var dr: float = ring_delta_r()
	var r_center: float = (float(ring) - 0.5) * dr
	var radial_half: float = dr * 0.36 * MARKER_PICK_SCALE
	if outer:
		return minf(
			r_center + radial_half,
			ring_outer_radius(ring) - dr * 0.03
		)
	return maxf(r_center - radial_half, dr * 0.05)


## Board-origin arc radius for field marker outer/inner edge (same formula as sector indicator).
static func field_marker_board_arc_radius(team: int, ring: int, phi: float, outer: bool = true) -> float:
	var r_sem: float = field_marker_visual_r_sem(ring, outer)
	var xz: Vector2 = semipolar_to_world_xz(team, r_sem, phi)
	return maxf(xz.length(), 0.05)


## Board-origin concentric radius for ring k (constant for all sectors; arcs centered at (0,0)).
static func field_marker_board_ring_radius(team: int, ring: int, outer: bool = true) -> float:
	return field_marker_board_arc_radius(team, ring, 0.0, outer)


static func field_cell_to_world(team: int, ring: int, sector: int) -> Vector3:
	var dr: float = ring_delta_r()
	var r: float = (float(ring) - 0.5) * dr
	var cz: float = semi_center_z(team)
	var phi: float = sector_center_phi(ring, sector)
	var x: float = r * sin(phi)
	var toward: float = r * cos(phi)
	var z: float = cz + toward if team == ShipUnit.TEAM_PLAYER else cz - toward
	return Vector3(x, 0.05, z)


static func hangar_local_offset(_corner: int, local_idx: int) -> Vector2i:
	if local_idx < 0 or local_idx >= HANGAR_CORNER_OFFSETS.size():
		return Vector2i(-1, -1)
	return HANGAR_CORNER_OFFSETS[local_idx]


static func hangar_cell_to_world(team: int, hangar_x: int, _hangar_z: int = 0) -> Vector3:
	var step_s: float = hangar_step()
	var step0: float = hangar_step_base()
	var inset: float = hangar_inset_wu()
	var outer_x: float = play_radius()
	var outer_z: float = board_outer_span_z()
	var per_corner: int = hangar_per_corner()
	var corner: int = hangar_x / per_corner
	var local: int = hangar_x % per_corner
	var off: Vector2i = hangar_local_offset(corner, local)
	if off.x < 0:
		return Vector3.ZERO
	var lx: int = off.x
	var lz: int = off.y
	var max_lx: int = HANGAR_LOCAL_MAX_LX
	var max_lz: int = HANGAR_LOCAL_MAX_LZ
	var inner_off_x: float = step0 * (float(max_lx) + 0.5)
	var inner_off_z: float = step0 * (float(max_lz) + 0.5)
	var lx_off: float = inner_off_x - step_s * float(max_lx - lx)
	var lz_off: float = inner_off_z - step_s * float(max_lz - lz)
	var sign_z: float = 1.0 if team == ShipUnit.TEAM_PLAYER else -1.0
	var x: float = 0.0
	if corner == 0:
		x = -outer_x + inset + lx_off
	else:
		x = outer_x - inset - lx_off
	var z: float = sign_z * (outer_z - inset - lz_off)
	return Vector3(x, 0.0, z)


static func cell_to_world(slot_type: String, team: int, x: int, z: int) -> Vector3:
	if slot_type == "hangar":
		return hangar_cell_to_world(team, x, z)
	return field_cell_to_world(team, x, z)


static func is_valid_field_cell(ring: int, sector: int) -> bool:
	if ring < 1 or ring > RING_COUNT or sector < 0:
		return false
	if is_center_skipped_field_cell(ring, sector):
		return false
	if ring < RING_COUNT:
		return sector < sectors_in_ring(ring)
	return is_ring6_field_sector(sector)


static func is_valid_hangar_cell(hangar_x: int, hangar_z: int = 0) -> bool:
	return hangar_z == 0 and hangar_x >= 0 and hangar_x < hangar_width()


static func is_in_isolation_band(world_xz: Vector2) -> bool:
	return absf(world_xz.y) < isolation_half_width()


static func is_inside_play_disk(world_xz: Vector2, margin: float = 0.0) -> bool:
	var r_lim: float = play_radius() - margin
	return world_xz.length_squared() <= r_lim * r_lim


static func clamp_to_play_disk(pos: Vector3, margin: float = 0.0) -> Vector3:
	var xz: Vector2 = Vector2(pos.x, pos.z)
	var r_lim: float = maxf(play_radius() - margin, 0.01)
	var dist: float = xz.length()
	if dist > r_lim and dist > 1e-6:
		xz = xz * (r_lim / dist)
	pos.x = xz.x
	pos.z = xz.y
	return pos


static func pick_field_sector(world_xz: Vector2, team: int) -> Vector2i:
	var pol: Vector2 = _semipolar_from_world_xz(world_xz, team)
	var r: float = pol.x
	var phi: float = pol.y
	var dr: float = ring_delta_r()
	if dr <= 1e-6:
		return Vector2i(-1, -1)
	var ring: int = clampi(ceili(r / dr - 0.5), 1, RING_COUNT)
	var sector: int = _phi_to_sector(ring, phi)
	if not is_valid_field_cell(ring, sector):
		return Vector2i(-1, -1)
	var center: Vector3 = field_cell_to_world(team, ring, sector)
	if not _point_in_sector_wedge(world_xz, Vector2(center.x, center.z), ring, sector, team):
		return Vector2i(-1, -1)
	return Vector2i(ring, sector)


static func point_in_field_sector_xz(world: Vector3, team: int, ring: int, sector: int) -> bool:
	if not is_valid_field_cell(ring, sector):
		return false
	var center: Vector3 = field_cell_to_world(team, ring, sector)
	return _point_in_sector_wedge(Vector2(world.x, world.z), Vector2(center.x, center.z), ring, sector, team)


static func point_in_hangar_square_xz(world: Vector3, cell_center: Vector3) -> bool:
	var half: float = hangar_step() * 0.5 * MARKER_PICK_SCALE
	if half <= 1e-6:
		half = 0.6
	return absf(world.x - cell_center.x) <= half and absf(world.z - cell_center.z) <= half


static func disc_overlaps_hangar_square_xz(foot_xz: Vector2, cell_center: Vector3, disc_r: float) -> bool:
	var half: float = hangar_step() * 0.5 * MARKER_PICK_SCALE
	if half <= 1e-6:
		half = 0.6
	var closest_x: float = clampf(foot_xz.x, cell_center.x - half, cell_center.x + half)
	var closest_z: float = clampf(foot_xz.y, cell_center.z - half, cell_center.z + half)
	var dx: float = foot_xz.x - closest_x
	var dz: float = foot_xz.y - closest_z
	return dx * dx + dz * dz <= disc_r * disc_r


static func disc_overlaps_field_sector_xz(
		foot_xz: Vector2, team: int, ring: int, sector: int, disc_r: float
) -> bool:
	if point_in_field_sector_xz(Vector3(foot_xz.x, 0.0, foot_xz.y), team, ring, sector):
		return true
	for i: int in range(8):
		var ang: float = float(i) * TAU / 8.0
		var rim: Vector2 = foot_xz + Vector2(cos(ang), sin(ang)) * disc_r
		if point_in_field_sector_xz(Vector3(rim.x, 0.0, rim.y), team, ring, sector):
			return true
	return false


static func enumerate_field_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ring: int in range(1, RING_COUNT + 1):
		var n: int = sectors_in_ring(ring) if ring < RING_COUNT else SECTORS_RING6_FULL
		for sector: int in range(n):
			if is_valid_field_cell(ring, sector):
				out.append(Vector2i(ring, sector))
	return out


static func enumerate_hangar_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var hw: int = hangar_width()
	for x: int in range(hw):
		out.append(Vector2i(x, 0))
	return out


static func prepare_play_bounds_xz(team: int, margin_wu: float = 0.0) -> Vector4:
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for cell: Vector2i in enumerate_field_cells():
		var p: Vector3 = field_cell_to_world(team, cell.x, cell.y)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	for cell: Vector2i in enumerate_hangar_cells():
		var p2: Vector3 = hangar_cell_to_world(team, cell.x, cell.y)
		min_x = minf(min_x, p2.x)
		max_x = maxf(max_x, p2.x)
		min_z = minf(min_z, p2.z)
		max_z = maxf(max_z, p2.z)
	return Vector4(min_x - margin_wu, max_x + margin_wu, min_z - margin_wu, max_z + margin_wu)


static func combat_play_bounds_xz(margin_wu: float = 0.75) -> Vector4:
	var r: float = play_radius()
	return Vector4(-r - margin_wu, r + margin_wu, -r - margin_wu, r + margin_wu)


static func field_span_x() -> float:
	return play_diameter()


static func _ensure_ring6_skip_cache() -> void:
	var sig: String = "%.4f|%.4f|center8" % [play_radius(), board_outer_span_z()]
	if sig == _ring6_skip_sig and _ring6_skip_sectors.size() > 0:
		return
	_ring6_skip_sig = sig
	## Wing 4 + hangar gap 3 + center 8 + hangar gap 3 + wing 4 = 22 sectors / 16 field.
	_ring6_skip_sectors = PackedInt32Array([4, 5, 6, 15, 16, 17])


static func sector_center_phi(ring: int, sector: int) -> float:
	return _sector_center_phi(ring, sector)


static func semipolar_to_world_xz(team: int, r: float, phi: float) -> Vector2:
	var cz: float = semi_center_z(team)
	var x: float = r * sin(phi)
	var toward: float = r * cos(phi)
	var z: float = cz + toward if team == ShipUnit.TEAM_PLAYER else cz - toward
	return Vector2(x, z)


static func semipolar_phi_from_world_xz(world_xz: Vector2, team: int) -> float:
	return _semipolar_from_world_xz(world_xz, team).y


static func _semipolar_from_world_xz(world_xz: Vector2, team: int) -> Vector2:
	var cz: float = semi_center_z(team)
	var dx: float = world_xz.x
	var dz: float = world_xz.y - cz
	if team != ShipUnit.TEAM_PLAYER:
		dz = -dz
	var r: float = sqrt(dx * dx + dz * dz)
	var phi: float = atan2(dx, dz)
	return Vector2(r, phi)


static func _nearest_ring6_sector(phi: float) -> int:
	var best_i: int = 0
	var best_d: float = INF
	for i: int in range(SECTORS_RING6_FULL):
		var dphi: float = absf(wrapf(phi - _sector_center_phi(RING_COUNT, i), -PI, PI))
		if dphi < best_d:
			best_d = dphi
			best_i = i
	return best_i


static func _sector_center_phi(ring: int, sector: int) -> float:
	var arc: float = PI
	var n_full: int = sectors_in_ring(ring) if ring < RING_COUNT else SECTORS_RING6_FULL
	var half_w: float = (arc / float(n_full)) * 0.5
	var start: float = -PI * 0.5 + half_w
	return start + float(sector) * (arc / float(n_full))


static func _phi_to_sector(ring: int, phi: float) -> int:
	var arc: float = PI
	var n_full: int = sectors_in_ring(ring) if ring < RING_COUNT else SECTORS_RING6_FULL
	var half_w: float = (arc / float(n_full)) * 0.5
	var rel: float = phi - (-PI * 0.5 + half_w)
	var idx: int = roundi(rel / (arc / float(n_full)))
	return clampi(idx, 0, n_full - 1)


static func _point_in_sector_wedge(
		world_xz: Vector2, _center_xz: Vector2, ring: int, sector: int, team: int
) -> bool:
	var pol: Vector2 = _semipolar_from_world_xz(world_xz, team)
	var r: float = pol.x
	var phi: float = pol.y
	var dr: float = ring_delta_r()
	var r_inner: float = float(ring - 1) * dr
	var r_outer: float = float(ring) * dr
	if r < r_inner - 0.02 or r > r_outer + 0.02:
		return false
	var n_full: int = sectors_in_ring(ring) if ring < RING_COUNT else SECTORS_RING6_FULL
	var arc: float = PI / float(n_full)
	var shrink: float = 0.92 * MARKER_PICK_SCALE
	var half_w: float = arc * shrink * 0.5
	var center_phi: float = _sector_center_phi(ring, sector)
	var dphi: float = absf(wrapf(phi - center_phi, -PI, PI))
	return dphi <= half_w
