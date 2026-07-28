extends RefCounted
class_name ShipLook
## Shared high-contrast ship look: albedo tone remap + PBR + match lighting.
## Source of truth: DataStore.visual["ship_look"] (synced from ship_color_viewer high-contrast).

static var _remap_cache: Dictionary = {} # cache_key -> Texture2D
static var _palette_cache: Dictionary = {} # ship_id -> {shadow,mid,high,tint}


static func cfg() -> Dictionary:
	if DataStore and DataStore.visual is Dictionary:
		var sl: Variant = DataStore.visual.get("ship_look", {})
		if sl is Dictionary:
			return sl as Dictionary
	return {}


static func enabled() -> bool:
	return bool(cfg().get("enabled", true))


static func f(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


static func apply_to_shader_material(smat: ShaderMaterial, ship_id: int, diffuse: Texture2D, diffuse_path: String) -> void:
	if smat == null or not enabled():
		return
	var look := cfg()
	smat.set_shader_parameter("hull_tint", Color.WHITE)
	smat.set_shader_parameter("team_tint", Color.WHITE)
	smat.set_shader_parameter("team_mix", 0.0)
	smat.set_shader_parameter("normal_scale", float(look.get("normal_scale", 1.05)))
	smat.set_shader_parameter("pmwo_metallic", float(look.get("metallic", 0.55)))
	smat.set_shader_parameter("pmwo_roughness", float(look.get("roughness", 0.30)))
	if diffuse:
		smat.set_shader_parameter("albedo_tex", remapped_albedo(ship_id, diffuse, diffuse_path))


static func apply_to_standard_material(mat: StandardMaterial3D, ship_id: int, diffuse: Texture2D, diffuse_path: String) -> void:
	if mat == null or not enabled():
		return
	var look := cfg()
	mat.metallic = float(look.get("metallic", 0.55))
	mat.metallic_specular = 0.03
	mat.roughness = float(look.get("roughness", 0.30))
	if mat.normal_enabled:
		mat.normal_scale = float(look.get("normal_scale", 1.05))
	if diffuse:
		mat.albedo_texture = remapped_albedo(ship_id, diffuse, diffuse_path)
		mat.albedo_color = Color.WHITE
		var emission := float(look.get("emission", 0.01))
		mat.emission_enabled = emission > 0.0
		if emission > 0.0:
			mat.emission = Color(1, 1, 1)
			mat.emission_energy_multiplier = emission


static func remapped_albedo(ship_id: int, diffuse: Texture2D, diffuse_path: String) -> Texture2D:
	if diffuse == null or not enabled():
		return diffuse
	var look := cfg()
	var cache_key := "%s|%s|%.3f|%.3f|%.3f" % [
		diffuse_path if diffuse_path != "" else str(diffuse.get_rid()),
		str(ship_id),
		float(look.get("albedo_mul", 1.04)),
		float(look.get("hull_contrast", 1.24)),
		float(look.get("portrait_tint_strength", 0.92)),
	]
	if _remap_cache.has(cache_key):
		return _remap_cache[cache_key] as Texture2D
	var palette := portrait_palette(ship_id)
	var shadow_col: Color = look_color("shadow", Color(0.06, 0.05, 0.04)).lerp(palette["shadow"], 0.55)
	var mid_col: Color = look_color("mid", Color(0.58, 0.43, 0.28)).lerp(palette["mid"], 0.55)
	var high_col: Color = look_color("high", Color(0.98, 0.96, 0.90)).lerp(palette["high"], 0.55)
	var manual_tint := Color(
		float(look.get("tint_r", 1.0)),
		float(look.get("tint_g", 1.0)),
		float(look.get("tint_b", 1.0)),
		1.0
	)
	var tint: Color = manual_tint.lerp(palette["tint"], float(look.get("portrait_tint_strength", 0.92)))
	var out := remap_texture_tones(
		diffuse,
		shadow_col,
		mid_col,
		high_col,
		tint,
		float(look.get("albedo_mul", 1.04)),
		float(look.get("hull_contrast", 1.24))
	)
	_remap_cache[cache_key] = out
	return out


static func look_color(band: String, fallback: Color) -> Color:
	var look := cfg()
	var r_key := "%s_r" % band
	var g_key := "%s_g" % band
	var b_key := "%s_b" % band
	if not look.has(r_key):
		return fallback
	return Color(float(look.get(r_key, fallback.r)), float(look.get(g_key, fallback.g)), float(look.get(b_key, fallback.b)), 1.0)


static func portrait_palette(ship_id: int) -> Dictionary:
	if _palette_cache.has(ship_id):
		return _palette_cache[ship_id] as Dictionary
	var fallback := {
		"shadow": Color(0.12, 0.09, 0.05, 1.0),
		"mid": Color(0.52, 0.44, 0.30, 1.0),
		"high": Color(0.88, 0.82, 0.67, 1.0),
		"tint": Color(0.82, 0.88, 0.92, 1.0),
	}
	var ship := DataStore.get_ship(ship_id) if DataStore else {}
	var ship_name := str(ship.get("name", ""))
	var tex: Texture2D = UiAssets.champion_icon(ship_name, ship_id)
	if tex == null:
		_palette_cache[ship_id] = fallback
		return fallback
	var img := tex.get_image()
	if img == null or img.is_empty():
		_palette_cache[ship_id] = fallback
		return fallback
	img.decompress()
	var tint_acc := Vector3.ZERO
	var tint_w := 0.0
	var buckets := {
		"shadow": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.0, "hi": 0.18},
		"mid": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.18, "hi": 0.65},
		"high": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.65, "hi": 1.01},
	}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			if c.s >= 0.18 and c.v >= 0.14 and c.v <= 0.92:
				var tw := c.s * (1.0 - absf(c.v - 0.55))
				tint_acc += Vector3(c.r, c.g, c.b) * tw
				tint_w += tw
			if c.a < 0.2:
				continue
			var lum := (c.r + c.g + c.b) / 3.0
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			for key in buckets.keys():
				var b: Dictionary = buckets[key]
				if lum >= float(b["lo"]) and lum < float(b["hi"]):
					var w := maxf(sat, 0.03)
					b["acc"] = (b["acc"] as Vector3) + Vector3(c.r, c.g, c.b) * w
					b["w"] = float(b["w"]) + w
					buckets[key] = b
					break
	var out := {}
	for key in ["shadow", "mid", "high"]:
		var b2: Dictionary = buckets[key]
		if float(b2["w"]) <= 0.0001:
			out[key] = fallback[key]
		else:
			var rgb := (b2["acc"] as Vector3) / float(b2["w"])
			out[key] = Color(rgb.x, rgb.y, rgb.z, 1.0)
	if tint_w <= 0.0001:
		out["tint"] = fallback["tint"]
	else:
		var trgb := tint_acc / tint_w
		var mx := maxf(trgb.x, maxf(trgb.y, trgb.z))
		if mx > 0.0001:
			trgb /= mx
		out["tint"] = Color(clampf(trgb.x, 0.0, 1.0), clampf(trgb.y, 0.0, 1.0), clampf(trgb.z, 0.0, 1.0), 1.0)
	_palette_cache[ship_id] = out
	return out


static func remap_texture_tones(
	tex: Texture2D,
	shadow_col: Color,
	mid_col: Color,
	high_col: Color,
	tint: Color,
	mul: float,
	hull_contrast: float = 1.0
) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	img.decompress()
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			var mapped: Color
			if lum < 0.22:
				var t0 := clampf(lum / 0.22, 0.0, 1.0)
				mapped = shadow_col.lerp(mid_col, t0)
			elif lum < 0.72:
				var t1 := clampf((lum - 0.22) / 0.50, 0.0, 1.0)
				mapped = mid_col.lerp(high_col, t1 * 0.25)
			else:
				var t2 := clampf((lum - 0.72) / 0.28, 0.0, 1.0)
				mapped = mid_col.lerp(high_col, 0.25 + t2 * 0.75)
			var detail_boost := 0.42 + lum * 0.92
			mapped = Color(
				mapped.r * tint.r * mul * detail_boost,
				mapped.g * tint.g * mul * detail_boost,
				mapped.b * tint.b * mul * detail_boost,
				1.0
			)
			mapped.r = clampf(0.5 + (mapped.r - 0.5) * hull_contrast, 0.0, 1.0)
			mapped.g = clampf(0.5 + (mapped.g - 0.5) * hull_contrast, 0.0, 1.0)
			mapped.b = clampf(0.5 + (mapped.b - 0.5) * hull_contrast, 0.0, 1.0)
			out.set_pixel(x, y, mapped)
	return ImageTexture.create_from_image(out)


static func apply_match_environment(env: Environment) -> void:
	if env == null or not enabled():
		return
	var look := cfg()
	env.ambient_light_energy = float(look.get("ambient_energy", 0.30))
	env.tonemap_exposure = float(look.get("exposure", 1.00))
	env.adjustment_enabled = true
	env.adjustment_brightness = float(look.get("brightness", 1.00))
	env.adjustment_contrast = float(look.get("contrast", 1.03))


static func apply_match_lights(root: Node) -> void:
	if root == null or not enabled():
		return
	var look := cfg()
	var key := root.get_node_or_null("KeyLightOffscreen") as DirectionalLight3D
	if key:
		key.light_energy = float(look.get("key_energy", 1.20))
	var rim := root.get_node_or_null("RimLightOffscreen") as DirectionalLight3D
	if rim:
		rim.light_energy = float(look.get("rim_energy", 0.52))
	var fill_e := float(look.get("fill_energy", 0.05))
	for fill_name in ["FillLight", "FillLightAI", "FillLightPlayer"]:
		var fill := root.get_node_or_null(fill_name) as OmniLight3D
		if fill:
			fill.light_energy = fill_e
	var scene_key := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if scene_key:
		scene_key.light_energy = float(look.get("scene_key_energy", 0.80))


static func clear_caches() -> void:
	_remap_cache.clear()
	_palette_cache.clear()
