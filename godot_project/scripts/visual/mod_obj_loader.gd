class_name ModObjLoader
extends RefCounted
## Minimal Wavefront OBJ → ArrayMesh for mod unit folders (model/model.obj).


static func load_obj(abs_path: String) -> ArrayMesh:
	if not FileAccess.file_exists(abs_path):
		return null
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return null
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var out_pos: PackedVector3Array = PackedVector3Array()
	var out_nrm: PackedVector3Array = PackedVector3Array()
	var out_uv: PackedVector2Array = PackedVector2Array()

	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts: PackedStringArray = line.split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"v":
				if parts.size() >= 4:
					positions.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
			"vn":
				if parts.size() >= 4:
					normals.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
			"vt":
				if parts.size() >= 3:
					uvs.append(Vector2(parts[1].to_float(), 1.0 - parts[2].to_float()))
			"f":
				var idxs: Array[Dictionary] = []
				for i: int in range(1, parts.size()):
					idxs.append(_parse_face_vert(parts[i]))
				if idxs.size() < 3:
					continue
				for t: int in range(1, idxs.size() - 1):
					_emit_tri(positions, uvs, out_pos, out_nrm, out_uv, idxs[0], idxs[t + 1], idxs[t])

	if out_pos.is_empty():
		return null
	out_nrm = _generate_normals(out_pos)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_pos
	arrays[Mesh.ARRAY_NORMAL] = out_nrm
	var uv_attached: bool = false
	if out_uv.size() == out_pos.size() and not out_uv.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = out_uv
		uv_attached = true
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if uv_attached and mesh.get_surface_count() > 0:
		var st: SurfaceTool = SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_tangents()
		var committed: ArrayMesh = st.commit()
		if committed != null and committed.get_surface_count() > 0:
			mesh = committed
	return mesh


static func _parse_face_vert(token: String) -> Dictionary:
	var bits: PackedStringArray = token.split("/")
	var vi: int = bits[0].to_int()
	var ti: int = 0
	var ni: int = 0
	if bits.size() >= 2 and bits[1] != "":
		ti = bits[1].to_int()
	if bits.size() >= 3 and bits[2] != "":
		ni = bits[2].to_int()
	return {"v": vi, "t": ti, "n": ni}


static func _resolve_index(i: int, count: int) -> int:
	if i < 0:
		return count + i
	return i - 1


static func _emit_tri(
	positions: PackedVector3Array,
	uvs: PackedVector2Array,
	out_pos: PackedVector3Array,
	out_nrm: PackedVector3Array,
	out_uv: PackedVector2Array,
	a: Dictionary,
	b: Dictionary,
	c: Dictionary
) -> bool:
	var had_uv: bool = false
	for corner: Dictionary in [a, b, c]:
		var vi: int = _resolve_index(TypedVariant.as_int(corner.get("v", 0), 0), positions.size())
		if vi < 0 or vi >= positions.size():
			return false
		out_pos.append(positions[vi])
		out_nrm.append(Vector3.UP)
		var ti: int = TypedVariant.as_int(corner.get("t", 0), 0)
		if ti != 0 and uvs.size() > 0:
			var tidx: int = _resolve_index(ti, uvs.size())
			if tidx >= 0 and tidx < uvs.size():
				out_uv.append(uvs[tidx])
				had_uv = true
				continue
		out_uv.append(Vector2.ZERO)
	return had_uv


static func _generate_normals(pos: PackedVector3Array) -> PackedVector3Array:
	var nrm: PackedVector3Array = PackedVector3Array()
	nrm.resize(pos.size())
	var i: int = 0
	while i + 2 < pos.size():
		var p0: Vector3 = pos[i]
		var p1: Vector3 = pos[i + 1]
		var p2: Vector3 = pos[i + 2]
		var n: Vector3 = (p1 - p0).cross(p2 - p0).normalized()
		nrm[i] = n
		nrm[i + 1] = n
		nrm[i + 2] = n
		i += 3
	return nrm
