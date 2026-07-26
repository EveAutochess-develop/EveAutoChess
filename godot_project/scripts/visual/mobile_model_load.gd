extends RefCounted
class_name MobileModelLoad
## On mobile, recompress Mesh surfaces with ARRAY_FLAG_COMPRESS_ATTRIBUTES
## (half-float / packed vertex attrs) and optionally half-res albedo/normal textures.
## Desktop / editor: no-op.

static func enabled() -> bool:
	if not UiLayout.is_mobile():
		return false
	if DataStore and DataStore.visual is Dictionary:
		return bool(DataStore.visual.get("mobile_half_precision_models", true))
	return true


static func apply_tree(root: Node) -> void:
	if root == null or not enabled():
		return
	for mi in _find_meshes(root):
		_compress_mesh_instance(mi)
		_half_material_textures(mi)


static func _compress_mesh_instance(mi: MeshInstance3D) -> void:
	var src := mi.mesh
	if src == null or src.get_surface_count() <= 0:
		return
	# Skip if every surface already reports compressed attributes.
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
		# COMPRESS_ATTRIBUTES requires normals+tangents together, or vertices only.
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
		elif not has_n:
			# Vertices-only path is valid for COMPRESS_ATTRIBUTES.
			pass
		var flags := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		out.add_surface_from_arrays(prim, arrays, [], {}, flags)
		var mat := src.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	if out.get_surface_count() > 0:
		mi.mesh = out


static func _half_material_textures(mi: MeshInstance3D) -> void:
	var max_edge := 1024
	if DataStore and DataStore.visual is Dictionary:
		max_edge = int(DataStore.visual.get("mobile_half_texture_max", 1024))
	max_edge = maxi(64, max_edge)
	_half_one_material(mi.material_override, max_edge)
	_half_one_material(mi.material_overlay, max_edge)
	if mi.mesh == null:
		return
	for s in range(mi.mesh.get_surface_count()):
		_half_one_material(mi.get_active_material(s), max_edge)


static func _half_one_material(mat: Material, max_edge: int) -> void:
	if mat == null or not (mat is BaseMaterial3D):
		return
	var bm := mat as BaseMaterial3D
	bm.albedo_texture = _downscale_tex(bm.albedo_texture, max_edge)
	bm.normal_texture = _downscale_tex(bm.normal_texture, max_edge)
	bm.ao_texture = _downscale_tex(bm.ao_texture, max_edge)
	# Mobile: drop normals — big win vs 2K normal maps on GLES.
	var drop_n := true
	if DataStore and DataStore.visual is Dictionary:
		drop_n = bool(DataStore.visual.get("mobile_disable_model_normals", true))
	if drop_n:
		bm.normal_enabled = false
		bm.normal_texture = null


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
