extends RefCounted
class_name MobileModelLoad
## Model load precision: baseline mesh/texture keep ratio + scale-driven extra reduction.
## Mobile additionally recompresses with ARRAY_FLAG_COMPRESS_ATTRIBUTES (half-float attrs).

static func precision_enabled() -> bool:
	if DataStore and DataStore.visual is Dictionary:
		return bool(DataStore.visual.get("model_load_precision_enabled", true))
	return true


static func mobile_compress_enabled() -> bool:
	if DataStore and DataStore.visual is Dictionary:
		if bool(DataStore.visual.get("model_half_precision_all_platforms", false)):
			return true
	if not UiLayout.is_mobile():
		return false
	if DataStore and DataStore.visual is Dictionary:
		return bool(DataStore.visual.get("mobile_half_precision_models", true))
	return true


## display_size < 0 → baseline only (no scale extra). Returns vertex/texture keep ratio ∈ (0, 1].
static func compute_precision_keep(display_size: float = -1.0) -> float:
	if not precision_enabled():
		return 1.0
	var base := float(DataStore.visual.get("model_load_precision_base", 0.8))
	var extra_max := float(DataStore.visual.get("model_load_precision_scale_extra_max", 0.5))
	if display_size <= 0.0:
		return clampf(base, 0.05, 1.0)
	var target := float(DataStore.visual.get("ship_target_size", 2.8))
	var min_mul := float(DataStore.visual.get("ship_scale_min_mul", 0.5))
	var max_mul := float(DataStore.visual.get("ship_scale_max_mul", 2.0))
	var min_d := target * min_mul
	var max_d := target * max_mul
	var t := 0.0
	if max_d > min_d + 0.001:
		t = clampf((display_size - min_d) / (max_d - min_d), 0.0, 1.0)
	var extra := t * extra_max
	return clampf(base - extra, 0.05, 1.0)


static func apply_tree(root: Node, display_size: float = -1.0) -> void:
	if root == null:
		return
	var keep := compute_precision_keep(display_size)
	for mi in _find_meshes(root):
		if keep < 0.999:
			_decimate_mesh_instance(mi, keep)
		_apply_texture_budget(mi, keep)
	if not mobile_compress_enabled():
		return
	for mi in _find_meshes(root):
		_compress_mesh_instance(mi)


static func _decimate_mesh_instance(mi: MeshInstance3D, keep_ratio: float) -> void:
	var src := mi.mesh
	if src == null or src.get_surface_count() <= 0:
		return
	if keep_ratio >= 0.999:
		return
	var out := ArrayMesh.new()
	for s in range(src.get_surface_count()):
		var prim := Mesh.PRIMITIVE_TRIANGLES
		if src is ArrayMesh:
			prim = (src as ArrayMesh).surface_get_primitive_type(s)
		var arrays: Array = src.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		arrays = _decimate_surface_arrays(arrays, keep_ratio)
		if arrays.is_empty():
			continue
		out.add_surface_from_arrays(prim, arrays)
		var mat := src.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	if out.get_surface_count() > 0:
		mi.mesh = out


static func _decimate_surface_arrays(arrays: Array, keep_ratio: float) -> Array:
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() >= 3:
		var indices: PackedInt32Array = idx
		var tri_count := int(floor(float(indices.size()) / 3.0))
		var keep_tris := maxi(1, int(floor(float(tri_count) * keep_ratio)))
		if keep_tris >= tri_count:
			return arrays
		var new_idx := PackedInt32Array()
		new_idx.resize(keep_tris * 3)
		var stride := float(tri_count) / float(keep_tris)
		var w := 0
		var f := 0.0
		while w < keep_tris * 3:
			var base_i := int(f) * 3
			if base_i + 2 < indices.size():
				new_idx[w] = indices[base_i]
				new_idx[w + 1] = indices[base_i + 1]
				new_idx[w + 2] = indices[base_i + 2]
				w += 3
			f += stride
		arrays[Mesh.ARRAY_INDEX] = new_idx
		return arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tri_count_v := int(floor(float(verts.size()) / 3.0))
	var keep_tris_v := maxi(1, int(floor(float(tri_count_v) * keep_ratio)))
	if keep_tris_v >= tri_count_v:
		return arrays
	var out_arrays: Array = arrays.duplicate(true)
	for channel in range(arrays.size()):
		var data: Variant = arrays[channel]
		if data == null:
			continue
		if data is PackedVector3Array:
			var src_v: PackedVector3Array = data
			if src_v.size() < tri_count_v * 3:
				continue
			var dst := PackedVector3Array()
			dst.resize(keep_tris_v * 3)
			var stride_v := float(tri_count_v) / float(keep_tris_v)
			var wv := 0
			var fv := 0.0
			while wv < keep_tris_v * 3:
				var base_v := int(fv) * 3
				dst[wv] = src_v[base_v]
				dst[wv + 1] = src_v[base_v + 1]
				dst[wv + 2] = src_v[base_v + 2]
				wv += 3
				fv += stride_v
			out_arrays[channel] = dst
		elif data is PackedVector2Array:
			var src_uv: PackedVector2Array = data
			if src_uv.size() < tri_count_v * 3:
				continue
			var dst_uv := PackedVector2Array()
			dst_uv.resize(keep_tris_v * 3)
			var stride_uv := float(tri_count_v) / float(keep_tris_v)
			var wu := 0
			var fu := 0.0
			while wu < keep_tris_v * 3:
				var base_u := int(fu) * 3
				dst_uv[wu] = src_uv[base_u]
				dst_uv[wu + 1] = src_uv[base_u + 1]
				dst_uv[wu + 2] = src_uv[base_u + 2]
				wu += 3
				fu += stride_uv
			out_arrays[channel] = dst_uv
	return out_arrays


static func _apply_texture_budget(mi: MeshInstance3D, keep_ratio: float) -> void:
	var max_edge := int(DataStore.visual.get("model_load_texture_max", 2048))
	if mobile_compress_enabled():
		max_edge = mini(max_edge, int(DataStore.visual.get("mobile_half_texture_max", 1024)))
	if precision_enabled():
		max_edge = maxi(64, int(round(float(max_edge) * keep_ratio)))
	_scale_material_textures(mi, max_edge, mobile_compress_enabled())


static func _scale_material_textures(mi: MeshInstance3D, max_edge: int, drop_normals_on_mobile: bool) -> void:
	_scale_one_material(mi.material_override, max_edge, drop_normals_on_mobile)
	_scale_one_material(mi.material_overlay, max_edge, drop_normals_on_mobile)
	if mi.mesh == null:
		return
	for s in range(mi.mesh.get_surface_count()):
		_scale_one_material(mi.get_active_material(s), max_edge, drop_normals_on_mobile)


static func _scale_one_material(mat: Material, max_edge: int, drop_normals_on_mobile: bool) -> void:
	if mat == null or not (mat is BaseMaterial3D):
		return
	var bm := mat as BaseMaterial3D
	bm.albedo_texture = _downscale_tex(bm.albedo_texture, max_edge)
	bm.normal_texture = _downscale_tex(bm.normal_texture, max_edge)
	bm.ao_texture = _downscale_tex(bm.ao_texture, max_edge)
	if drop_normals_on_mobile and bool(DataStore.visual.get("mobile_disable_model_normals", true)):
		bm.normal_enabled = false
		bm.normal_texture = null


static func _compress_mesh_instance(mi: MeshInstance3D) -> void:
	var src := mi.mesh
	if src == null or src.get_surface_count() <= 0:
		return
	var all_compressed := true
	for s in range(src.get_surface_count()):
		var fmt: int = src.surface_get_format(s)
		if (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0:
			all_compressed = false
			break
	if all_compressed:
		return
	var out := ArrayMesh.new()
	for s in range(src.get_surface_count()):
		var prim := Mesh.PRIMITIVE_TRIANGLES
		if src is ArrayMesh:
			prim = (src as ArrayMesh).surface_get_primitive_type(s)
		var arrays: Array = src.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var has_n: bool = arrays[Mesh.ARRAY_NORMAL] != null
		var has_t: bool = arrays.size() > Mesh.ARRAY_TANGENT and arrays[Mesh.ARRAY_TANGENT] != null
		if has_n and not has_t:
			var st := SurfaceTool.new()
			st.create_from(src, s)
			st.generate_tangents()
			var tmp_mesh: ArrayMesh = st.commit()
			if tmp_mesh == null or tmp_mesh.get_surface_count() < 1:
				continue
			arrays = tmp_mesh.surface_get_arrays(0)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
		var flags := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		out.add_surface_from_arrays(prim, arrays, [], {}, flags)
		var mat := src.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	if out.get_surface_count() > 0:
		mi.mesh = out


static func _downscale_tex(tex: Texture2D, max_edge: int) -> Texture2D:
	if tex == null:
		return null
	var w := tex.get_width()
	var h := tex.get_height()
	if w <= max_edge and h <= max_edge:
		return tex
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	var scale := minf(float(max_edge) / float(maxi(w, 1)), float(max_edge) / float(maxi(h, 1)))
	var nw := maxi(1, int(round(float(w) * scale)))
	var nh := maxi(1, int(round(float(h) * scale)))
	img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out
