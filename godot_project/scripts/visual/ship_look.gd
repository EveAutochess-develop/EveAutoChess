extends RefCounted
class_name ShipLook
## Match ship look from visual.json ship_look.
## Default mode unity_standard: port of Unity Custom/StandardShipShader + VSMode lighting.

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


static func mode() -> String:
	var look := cfg()
	var m := str(look.get("mode", "")).strip_edges().to_lower()
	if m != "":
		return m
	var n := str(look.get("name", "unity-standard")).strip_edges().to_lower()
	if n == "high-contrast" or n == "high_contrast":
		return "high_contrast"
	return "unity_standard"


static func is_unity_standard() -> bool:
	return mode() == "unity_standard"


static func f(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


static func color3(prefix: String, fallback: Color) -> Color:
	var look := cfg()
	var rk := "%s_r" % prefix
	if not look.has(rk):
		return fallback
	return Color(
		float(look.get(rk, fallback.r)),
		float(look.get("%s_g" % prefix, fallback.g)),
		float(look.get("%s_b" % prefix, fallback.b)),
		1.0
	)


static func apply_to_unity_shader_material(smat: ShaderMaterial) -> void:
	if smat == null or not enabled():
		return
	var look := cfg()
	smat.set_shader_parameter("color1", color3("color1", Color(0, 0, 0)))
	smat.set_shader_parameter("color2", color3("color2", Color(1, 1, 1)))
	smat.set_shader_parameter("color3", color3("color3", Color(0.1981132, 0.1981132, 0.1981132)))
	smat.set_shader_parameter("color4", color3("color4", Color(1.0, 0.84931314, 0.0)))
	smat.set_shader_parameter("color_light", color3("color_light", Color(0.0, 0.9270375, 1.0)))
	smat.set_shader_parameter("threshold1", float(look.get("threshold1", -0.1)))
	smat.set_shader_parameter("threshold2", float(look.get("threshold2", 0.35)))
	smat.set_shader_parameter("threshold3", float(look.get("threshold3", 0.68)))
	smat.set_shader_parameter("metallic_threshold", float(look.get("metallic_threshold", 0.75)))
	smat.set_shader_parameter("normal_scale", float(look.get("normal_scale", 1.0)))
	smat.set_shader_parameter("glow_mul", float(look.get("glow_mul", 1.0)))
	smat.set_shader_parameter("intensity_floor", float(look.get("intensity_floor", 0.14)))
	smat.set_shader_parameter("combat_emission_strength", 0.0)


static func apply_to_shader_material(smat: ShaderMaterial, ship_id: int, diffuse: Texture2D, diffuse_path: String) -> void:
	if smat == null or not enabled():
		return
	if is_unity_standard():
		# Legacy echoes shader path: force neutral (no race/team), mild PBR from look.
		smat.set_shader_parameter("hull_tint", Color.WHITE)
		smat.set_shader_parameter("team_tint", Color.WHITE)
		smat.set_shader_parameter("team_mix", 0.0)
		smat.set_shader_parameter("normal_scale", float(cfg().get("normal_scale", 1.0)))
		smat.set_shader_parameter("pmwo_metallic", 1.0)
		smat.set_shader_parameter("pmwo_roughness", 0.85)
		if diffuse:
			smat.set_shader_parameter("albedo_tex", diffuse)
		return
	# high_contrast legacy
	smat.set_shader_parameter("hull_tint", Color.WHITE)
	smat.set_shader_parameter("team_tint", Color.WHITE)
	smat.set_shader_parameter("team_mix", 0.0)
	smat.set_shader_parameter("normal_scale", float(cfg().get("normal_scale", 1.05)))
	smat.set_shader_parameter("pmwo_metallic", float(cfg().get("metallic", 0.55)))
	smat.set_shader_parameter("pmwo_roughness", float(cfg().get("roughness", 0.30)))
	if diffuse:
		smat.set_shader_parameter("albedo_tex", remapped_albedo(ship_id, diffuse, diffuse_path))


static func apply_to_standard_material(mat: StandardMaterial3D, ship_id: int, diffuse: Texture2D, diffuse_path: String) -> void:
	if mat == null or not enabled():
		return
	var look := cfg()
	if is_unity_standard():
		if diffuse:
			mat.albedo_texture = unity_remapped_albedo(diffuse, diffuse_path)
			mat.albedo_color = Color.WHITE
		mat.metallic = 0.35
		mat.metallic_specular = 0.5
		mat.roughness = 0.45
		if mat.normal_enabled:
			mat.normal_scale = float(look.get("normal_scale", 1.0))
		var glow := color3("color_light", Color(0.0, 0.9270375, 1.0))
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = float(look.get("emission", 0.08))
		return
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


static func unity_remapped_albedo(diffuse: Texture2D, diffuse_path: String) -> Texture2D:
	## CPU fallback when only albedo is available: intensity × 4-band by albedo.r as mat_id.
	if diffuse == null or not enabled():
		return diffuse
	var look := cfg()
	var cache_key := "unity|%s|%.3f|%.3f|%.3f" % [
		diffuse_path if diffuse_path != "" else str(diffuse.get_rid()),
		float(look.get("threshold2", 0.35)),
		float(look.get("threshold3", 0.68)),
		float(look.get("albedo_mul", 1.0)),
	]
	if _remap_cache.has(cache_key):
		return _remap_cache[cache_key] as Texture2D
	var img := diffuse.get_image()
	if img == null or img.is_empty():
		return diffuse
	img.decompress()
	var c1 := color3("color1", Color(0, 0, 0))
	var c2 := color3("color2", Color(1, 1, 1))
	var c3 := color3("color3", Color(0.1981132, 0.1981132, 0.1981132))
	var c4 := color3("color4", Color(1.0, 0.84931314, 0.0))
	var t1 := float(look.get("threshold1", -0.1))
	var t2 := float(look.get("threshold2", 0.35))
	var t3 := float(look.get("threshold3", 0.68))
	var mul := float(look.get("albedo_mul", 1.0))
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var intensity := c.r
			var mat_id := intensity
			var band: Color
			if mat_id < t1:
				band = c1
			elif mat_id <= t2:
				band = c2
			elif mat_id <= t3:
				band = c3
			else:
				band = c4
			out.set_pixel(x, y, Color(
				clampf(intensity * band.r * mul, 0.0, 1.0),
				clampf(intensity * band.g * mul, 0.0, 1.0),
				clampf(intensity * band.b * mul, 0.0, 1.0),
				1.0
			))
	var tex := ImageTexture.create_from_image(out)
	_remap_cache[cache_key] = tex
	return tex


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
	if is_unity_standard():
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = color3("ambient", Color(0.212, 0.227, 0.259))
		env.ambient_light_energy = float(look.get("ambient_energy", 1.15))
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = float(look.get("exposure", 0.9))
		env.tonemap_white = 1.0
		env.adjustment_enabled = true
		env.adjustment_brightness = float(look.get("brightness", 1.0))
		env.adjustment_contrast = float(look.get("contrast", 1.0))
		env.adjustment_saturation = float(look.get("saturation", 1.0))
		var glow_on := bool(look.get("glow_enabled", true))
		env.glow_enabled = glow_on
		if glow_on:
			env.glow_intensity = float(look.get("glow_intensity", 0.55))
			env.glow_strength = float(look.get("glow_strength", 0.9))
			env.glow_bloom = float(look.get("glow_bloom", 0.35))
			# Godot 4 property is glow_hdr_threshold (not glow_threshold).
			env.glow_hdr_threshold = float(look.get("glow_hdr_threshold", look.get("glow_threshold", 0.45)))
		env.ssao_enabled = bool(look.get("ssao_enabled", false))
		return
	env.ambient_light_energy = float(look.get("ambient_energy", 0.30))
	env.tonemap_exposure = float(look.get("exposure", 1.00))
	env.adjustment_enabled = true
	env.adjustment_brightness = float(look.get("brightness", 1.00))
	env.adjustment_contrast = float(look.get("contrast", 1.03))


static func apply_match_lights(root: Node) -> void:
	if root == null or not enabled():
		return
	var look := cfg()
	var unity := is_unity_standard()
	var key := root.get_node_or_null("KeyLightOffscreen") as DirectionalLight3D
	if key:
		var key_default := 1.0 if unity else 1.20
		key.light_energy = float(look.get("key_energy", key_default))
		key.light_color = color3("key_color", Color(1, 1, 1))
		if unity:
			# VSModeGameScene Directional Light euler hint ≈ (57.3, 107.7, 3)
			key.rotation_degrees = Vector3(
				float(look.get("key_pitch_deg", -57.3)),
				float(look.get("key_yaw_deg", 107.7)),
				float(look.get("key_roll_deg", 0.0))
			)
			key.shadow_enabled = true
			key.shadow_opacity = float(look.get("key_shadow_opacity", 0.55))
	var rim := root.get_node_or_null("RimLightOffscreen") as DirectionalLight3D
	if rim:
		var rim_default := 0.0 if unity else 0.52
		rim.light_energy = float(look.get("rim_energy", rim_default))
	var fill_default := 0.0 if unity else 0.05
	var fill_e := float(look.get("fill_energy", fill_default))
	for fill_name in ["FillLight", "FillLightAI", "FillLightPlayer"]:
		var fill := root.get_node_or_null(fill_name) as OmniLight3D
		if fill:
			fill.light_energy = fill_e
	var scene_key := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if scene_key:
		var scene_default := 0.0 if unity else 0.80
		scene_key.light_energy = float(look.get("scene_key_energy", scene_default))


static func clear_caches() -> void:
	_remap_cache.clear()
	_palette_cache.clear()
