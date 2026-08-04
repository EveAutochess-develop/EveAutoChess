extends RefCounted
class_name ShipLook
## Match ship look from visual.json ship_look.
## Default mode unity_standard: port of Unity Custom/StandardShipShader + VSMode lighting.

static var _remap_cache: Dictionary = {} # cache_key -> Texture2D
static var _palette_cache: Dictionary = {} # ship_id -> {shadow,mid,high,tint}


static func texture_or(v: Variant, fallback: Texture2D) -> Texture2D:
	if v is Texture2D:
		return v
	return fallback


static func color_or(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	return fallback


static func vector3_or(v: Variant, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	return fallback


static func data_store() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	@warning_ignore("unsafe_cast")
	var tree: SceneTree = main_loop as SceneTree
	return tree.root.get_node_or_null("DataStore")


static func ui_assets() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	@warning_ignore("unsafe_cast")
	var tree: SceneTree = main_loop as SceneTree
	return tree.root.get_node_or_null("UiAssets")


static func cfg() -> Dictionary:
	var store: Node = data_store()
	if store:
		var visual: Dictionary = TypedVariant.as_dict(store.get("visual"))
		return TypedVariant.as_dict(visual.get("ship_look", {}))
	return {}


static func enabled() -> bool:
	return TypedVariant.as_bool(cfg().get("enabled", true), true)


static func mode() -> String:
	var look: Dictionary = cfg()
	var m: String = str(look.get("mode", "")).strip_edges().to_lower()
	if m != "":
		return m
	var n: String = str(look.get("name", "unity-standard")).strip_edges().to_lower()
	if n == "high-contrast" or n == "high_contrast":
		return "high_contrast"
	return "unity_standard"


static func is_unity_standard() -> bool:
	return mode() == "unity_standard"


static func f(key: String, fallback: float) -> float:
	return TypedVariant.as_float(cfg().get(key, fallback), fallback)


static func color3(prefix: String, fallback: Color) -> Color:
	var look: Dictionary = cfg()
	var rk: String = "%s_r" % prefix
	if not look.has(rk):
		return fallback
	return Color(
		TypedVariant.as_float(look.get(rk, fallback.r), fallback.r),
		TypedVariant.as_float(look.get("%s_g" % prefix, fallback.g), fallback.g),
		TypedVariant.as_float(look.get("%s_b" % prefix, fallback.b), fallback.b),
		1.0
	)


static func apply_to_unity_shader_material(smat: ShaderMaterial) -> void:
	if smat == null or not enabled():
		return
	var look: Dictionary = cfg()
	smat.set_shader_parameter("color1", color3("color1", Color(0, 0, 0)))
	smat.set_shader_parameter("color2", color3("color2", Color(1, 1, 1)))
	smat.set_shader_parameter("color3", color3("color3", Color(0.1981132, 0.1981132, 0.1981132)))
	smat.set_shader_parameter("color4", color3("color4", Color(1.0, 0.84931314, 0.0)))
	smat.set_shader_parameter("color_light", color3("color_light", Color(0.0, 0.9270375, 1.0)))
	smat.set_shader_parameter("threshold1", TypedVariant.as_float(look.get("threshold1", -0.1), -0.1))
	smat.set_shader_parameter("threshold2", TypedVariant.as_float(look.get("threshold2", 0.35), 0.35))
	smat.set_shader_parameter("threshold3", TypedVariant.as_float(look.get("threshold3", 0.68), 0.68))
	smat.set_shader_parameter("metallic_threshold", TypedVariant.as_float(look.get("metallic_threshold", 0.75), 0.75))
	smat.set_shader_parameter("normal_scale", TypedVariant.as_float(look.get("normal_scale", 1.0), 1.0))
	smat.set_shader_parameter("glow_mul", TypedVariant.as_float(look.get("glow_mul", 1.0), 1.0))
	smat.set_shader_parameter("intensity_floor", TypedVariant.as_float(look.get("intensity_floor", 0.14), 0.14))
	smat.set_shader_parameter("combat_emission_strength", 0.0)


static func apply_to_shader_material(smat: ShaderMaterial, ship_id: int, diffuse: Texture2D, diffuse_path: String) -> void:
	if smat == null or not enabled():
		return
	if is_unity_standard():
		# Legacy echoes shader path: force neutral (no race/team), mild PBR from look.
		smat.set_shader_parameter("hull_tint", Color.WHITE)
		smat.set_shader_parameter("team_tint", Color.WHITE)
		smat.set_shader_parameter("team_mix", 0.0)
		smat.set_shader_parameter("normal_scale", TypedVariant.as_float(cfg().get("normal_scale", 1.0), 1.0))
		smat.set_shader_parameter("pmwo_metallic", 1.0)
		smat.set_shader_parameter("pmwo_roughness", 0.85)
		if diffuse:
			smat.set_shader_parameter("albedo_tex", diffuse)
		return
	# high_contrast legacy
	smat.set_shader_parameter("hull_tint", Color.WHITE)
	smat.set_shader_parameter("team_tint", Color.WHITE)
	smat.set_shader_parameter("team_mix", 0.0)
	smat.set_shader_parameter("normal_scale", TypedVariant.as_float(cfg().get("normal_scale", 1.05), 1.05))
	smat.set_shader_parameter("pmwo_metallic", TypedVariant.as_float(cfg().get("metallic", 0.55), 0.55))
	smat.set_shader_parameter("pmwo_roughness", TypedVariant.as_float(cfg().get("roughness", 0.30), 0.30))
	if diffuse:
		smat.set_shader_parameter("albedo_tex", remapped_albedo(ship_id, diffuse, diffuse_path))


static func apply_to_standard_material(mat: StandardMaterial3D, ship_id: int, diffuse: Texture2D, diffuse_path: String) -> void:
	if mat == null or not enabled():
		return
	var look: Dictionary = cfg()
	## Flat placeholder albedo (e.g. old fighter tint PNG): never unity-band-remap — that
	## turns the whole hull into a solid silhouette. Keep shaded form via lighting.
	if diffuse != null and is_flat_albedo(diffuse):
		mat.albedo_texture = diffuse
		mat.albedo_color = Color.WHITE
		mat.metallic = 0.25
		mat.metallic_specular = 0.35
		mat.roughness = 0.55
		mat.emission_enabled = false
		return
	if is_unity_standard():
		if diffuse:
			mat.albedo_texture = unity_remapped_albedo(diffuse, diffuse_path)
			mat.albedo_color = Color.WHITE
		mat.metallic = 0.35
		mat.metallic_specular = 0.5
		mat.roughness = 0.45
		if mat.normal_enabled:
			mat.normal_scale = TypedVariant.as_float(look.get("normal_scale", 1.0), 1.0)
		var glow: Color = color3("color_light", Color(0.0, 0.9270375, 1.0))
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = TypedVariant.as_float(look.get("emission", 0.08), 0.08)
		return
	mat.metallic = TypedVariant.as_float(look.get("metallic", 0.55), 0.55)
	mat.metallic_specular = 0.03
	mat.roughness = TypedVariant.as_float(look.get("roughness", 0.30), 0.30)
	if mat.normal_enabled:
		mat.normal_scale = TypedVariant.as_float(look.get("normal_scale", 1.05), 1.05)
	if diffuse:
		mat.albedo_texture = remapped_albedo(ship_id, diffuse, diffuse_path)
		mat.albedo_color = Color.WHITE
		var emission: float = TypedVariant.as_float(look.get("emission", 0.01), 0.01)
		mat.emission_enabled = emission > 0.0
		if emission > 0.0:
			mat.emission = Color(1, 1, 1)
			mat.emission_energy_multiplier = emission


## True when albedo is a near-constant tint (import placeholder), not a real bake.
static func is_flat_albedo(tex: Texture2D) -> bool:
	if tex == null:
		return true
	var w: int = tex.get_width()
	var h: int = tex.get_height()
	if w * h <= 0:
		return true
	## Tiny PNG from Image.new solid fill is typically ≤4KB on disk; also catch runtime constants.
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return w <= 4 and h <= 4
	img.decompress()
	var step_x: int = maxi(1, img.get_width() / 16)
	var step_y: int = maxi(1, img.get_height() / 16)
	var first: Color = img.get_pixel(0, 0)
	var y: int = 0
	while y < img.get_height():
		var x: int = 0
		while x < img.get_width():
			var c: Color = img.get_pixel(x, y)
			if absf(c.r - first.r) > 0.04 or absf(c.g - first.g) > 0.04 or absf(c.b - first.b) > 0.04:
				return false
			x += step_x
		y += step_y
	return true


static func unity_remapped_albedo(diffuse: Texture2D, diffuse_path: String) -> Texture2D:
	## CPU fallback when only albedo is available: intensity × 4-band by albedo.r as mat_id.
	if diffuse == null or not enabled():
		return diffuse
	var look: Dictionary = cfg()
	var cache_key: String = "unity|%s|%.3f|%.3f|%.3f" % [
		diffuse_path if diffuse_path != "" else str(diffuse.get_rid()),
		TypedVariant.as_float(look.get("threshold2", 0.35), 0.35),
		TypedVariant.as_float(look.get("threshold3", 0.68), 0.68),
		TypedVariant.as_float(look.get("albedo_mul", 1.0), 1.0),
	]
	if _remap_cache.has(cache_key):
		return texture_or(_remap_cache[cache_key], diffuse)
	var img: Image = diffuse.get_image()
	if img == null or img.is_empty():
		return diffuse
	img.decompress()
	var c1: Color = color3("color1", Color(0, 0, 0))
	var c2: Color = color3("color2", Color(1, 1, 1))
	var c3: Color = color3("color3", Color(0.1981132, 0.1981132, 0.1981132))
	var c4: Color = color3("color4", Color(1.0, 0.84931314, 0.0))
	var t1: float = TypedVariant.as_float(look.get("threshold1", -0.1), -0.1)
	var t2: float = TypedVariant.as_float(look.get("threshold2", 0.35), 0.35)
	var t3: float = TypedVariant.as_float(look.get("threshold3", 0.68), 0.68)
	var mul: float = TypedVariant.as_float(look.get("albedo_mul", 1.0), 1.0)
	var out: Image = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var intensity: float = c.r
			var mat_id: float = intensity
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
	var tex: ImageTexture = ImageTexture.create_from_image(out)
	_remap_cache[cache_key] = tex
	return tex


static func remapped_albedo(ship_id: int, diffuse: Texture2D, diffuse_path: String) -> Texture2D:
	if diffuse == null or not enabled():
		return diffuse
	var look: Dictionary = cfg()
	var cache_key: String = "%s|%s|%.3f|%.3f|%.3f" % [
		diffuse_path if diffuse_path != "" else str(diffuse.get_rid()),
		str(ship_id),
		TypedVariant.as_float(look.get("albedo_mul", 1.04), 1.04),
		TypedVariant.as_float(look.get("hull_contrast", 1.24), 1.24),
		TypedVariant.as_float(look.get("portrait_tint_strength", 0.92), 0.92),
	]
	if _remap_cache.has(cache_key):
		return texture_or(_remap_cache[cache_key], diffuse)
	var palette: Dictionary = portrait_palette(ship_id)
	var palette_shadow: Color = color_or(palette["shadow"], Color(0.12, 0.09, 0.05, 1.0))
	var palette_mid: Color = color_or(palette["mid"], Color(0.52, 0.44, 0.30, 1.0))
	var palette_high: Color = color_or(palette["high"], Color(0.88, 0.82, 0.67, 1.0))
	var palette_tint: Color = color_or(palette["tint"], Color(0.82, 0.88, 0.92, 1.0))
	var shadow_col: Color = look_color("shadow", Color(0.06, 0.05, 0.04)).lerp(palette_shadow, 0.55)
	var mid_col: Color = look_color("mid", Color(0.58, 0.43, 0.28)).lerp(palette_mid, 0.55)
	var high_col: Color = look_color("high", Color(0.98, 0.96, 0.90)).lerp(palette_high, 0.55)
	var manual_tint: Color = Color(
		TypedVariant.as_float(look.get("tint_r", 1.0), 1.0),
		TypedVariant.as_float(look.get("tint_g", 1.0), 1.0),
		TypedVariant.as_float(look.get("tint_b", 1.0), 1.0),
		1.0
	)
	var tint: Color = manual_tint.lerp(palette_tint, TypedVariant.as_float(look.get("portrait_tint_strength", 0.92), 0.92))
	var out: Texture2D = remap_texture_tones(
		diffuse,
		shadow_col,
		mid_col,
		high_col,
		tint,
		TypedVariant.as_float(look.get("albedo_mul", 1.04), 1.04),
		TypedVariant.as_float(look.get("hull_contrast", 1.24), 1.24)
	)
	_remap_cache[cache_key] = out
	return out


static func look_color(band: String, fallback: Color) -> Color:
	var look: Dictionary = cfg()
	var r_key: String = "%s_r" % band
	var g_key: String = "%s_g" % band
	var b_key: String = "%s_b" % band
	if not look.has(r_key):
		return fallback
	return Color(TypedVariant.as_float(look.get(r_key, fallback.r), fallback.r), TypedVariant.as_float(look.get(g_key, fallback.g), fallback.g), TypedVariant.as_float(look.get(b_key, fallback.b), fallback.b), 1.0)


static func portrait_palette(ship_id: int) -> Dictionary:
	if _palette_cache.has(ship_id):
		return TypedVariant.as_dict(_palette_cache[ship_id])
	var fallback: Dictionary = {
		"shadow": Color(0.12, 0.09, 0.05, 1.0),
		"mid": Color(0.52, 0.44, 0.30, 1.0),
		"high": Color(0.88, 0.82, 0.67, 1.0),
		"tint": Color(0.82, 0.88, 0.92, 1.0),
	}
	var store: Node = data_store()
	var ship: Dictionary = TypedVariant.as_dict(store.call("get_ship", ship_id)) if store else {}
	var ship_name: String = str(ship.get("name", ""))
	var assets: Node = ui_assets()
	var tex: Texture2D = texture_or(assets.call("champion_icon", ship_name, ship_id), null) if assets else null
	if tex == null:
		_palette_cache[ship_id] = fallback
		return fallback
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		_palette_cache[ship_id] = fallback
		return fallback
	img.decompress()
	var tint_acc: Vector3 = Vector3.ZERO
	var tint_w: float = 0.0
	var buckets: Dictionary = {
		"shadow": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.0, "hi": 0.18},
		"mid": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.18, "hi": 0.65},
		"high": {"acc": Vector3.ZERO, "w": 0.0, "lo": 0.65, "hi": 1.01},
	}
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			if c.s >= 0.18 and c.v >= 0.14 and c.v <= 0.92:
				var tw: float = c.s * (1.0 - absf(c.v - 0.55))
				tint_acc += Vector3(c.r, c.g, c.b) * tw
				tint_w += tw
			if c.a < 0.2:
				continue
			var lum: float = (c.r + c.g + c.b) / 3.0
			var sat: float = maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			for key: String in buckets.keys():
				var b: Dictionary = TypedVariant.as_dict(buckets[key])
				if lum >= TypedVariant.as_float(b.get("lo", 0.0), 0.0) and lum < TypedVariant.as_float(b.get("hi", 1.0), 1.0):
					var w: float = maxf(sat, 0.03)
					b["acc"] = vector3_or(b["acc"], Vector3.ZERO) + Vector3(c.r, c.g, c.b) * w
					b["w"] = TypedVariant.as_float(b.get("w", 0.0), 0.0) + w
					buckets[key] = b
					break
	var out: Dictionary = {}
	for key: String in ["shadow", "mid", "high"]:
		var b2: Dictionary = TypedVariant.as_dict(buckets[key])
		if TypedVariant.as_float(b2.get("w", 0.0), 0.0) <= 0.0001:
			out[key] = fallback[key]
		else:
			var rgb: Vector3 = vector3_or(b2["acc"], Vector3.ZERO) / TypedVariant.as_float(b2.get("w", 0.0), 0.0)
			out[key] = Color(rgb.x, rgb.y, rgb.z, 1.0)
	if tint_w <= 0.0001:
		out["tint"] = fallback["tint"]
	else:
		var trgb: Vector3 = tint_acc / tint_w
		var mx: float = maxf(trgb.x, maxf(trgb.y, trgb.z))
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
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return tex
	img.decompress()
	var out: Image = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var lum: float = (c.r + c.g + c.b) / 3.0
			var mapped: Color
			if lum < 0.22:
				var t0: float = clampf(lum / 0.22, 0.0, 1.0)
				mapped = shadow_col.lerp(mid_col, t0)
			elif lum < 0.72:
				var t1: float = clampf((lum - 0.22) / 0.50, 0.0, 1.0)
				mapped = mid_col.lerp(high_col, t1 * 0.25)
			else:
				var t2: float = clampf((lum - 0.72) / 0.28, 0.0, 1.0)
				mapped = mid_col.lerp(high_col, 0.25 + t2 * 0.75)
			var detail_boost: float = 0.42 + lum * 0.92
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
	var look: Dictionary = cfg()
	if is_unity_standard():
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = color3("ambient", Color(0.212, 0.227, 0.259))
		env.ambient_light_energy = TypedVariant.as_float(look.get("ambient_energy", 1.15), 1.15)
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = TypedVariant.as_float(look.get("exposure", 0.9), 0.9)
		env.tonemap_white = 1.0
		env.adjustment_enabled = true
		env.adjustment_brightness = TypedVariant.as_float(look.get("brightness", 1.0), 1.0)
		env.adjustment_contrast = TypedVariant.as_float(look.get("contrast", 1.0), 1.0)
		env.adjustment_saturation = TypedVariant.as_float(look.get("saturation", 1.0), 1.0)
		var glow_on: bool = TypedVariant.as_bool(look.get("glow_enabled", true), true)
		env.glow_enabled = glow_on
		if glow_on:
			env.glow_intensity = TypedVariant.as_float(look.get("glow_intensity", 0.55), 0.55)
			env.glow_strength = TypedVariant.as_float(look.get("glow_strength", 0.9), 0.9)
			env.glow_bloom = TypedVariant.as_float(look.get("glow_bloom", 0.35), 0.35)
			# Godot 4 property is glow_hdr_threshold (not glow_threshold).
			env.glow_hdr_threshold = TypedVariant.as_float(look.get("glow_hdr_threshold", look.get("glow_threshold", 0.45)), 0.45)
		env.ssao_enabled = TypedVariant.as_bool(look.get("ssao_enabled", false), false)
		return
	env.ambient_light_energy = TypedVariant.as_float(look.get("ambient_energy", 0.30), 0.30)
	env.tonemap_exposure = TypedVariant.as_float(look.get("exposure", 1.00), 1.00)
	env.adjustment_enabled = true
	env.adjustment_brightness = TypedVariant.as_float(look.get("brightness", 1.00), 1.00)
	env.adjustment_contrast = TypedVariant.as_float(look.get("contrast", 1.03), 1.03)


static func apply_match_lights(root: Node) -> void:
	if root == null or not enabled():
		return
	var look: Dictionary = cfg()
	var unity: bool = is_unity_standard()
	var key: DirectionalLight3D = root.get_node_or_null("KeyLightOffscreen") as DirectionalLight3D
	if key:
		var key_default: float = 1.0 if unity else 1.20
		key.light_energy = TypedVariant.as_float(look.get("key_energy", key_default), key_default)
		key.light_color = color3("key_color", Color(1, 1, 1))
		if unity:
			# VSModeGameScene Directional Light euler hint ≈ (57.3, 107.7, 3)
			key.rotation_degrees = Vector3(
				TypedVariant.as_float(look.get("key_pitch_deg", -57.3), -57.3),
				TypedVariant.as_float(look.get("key_yaw_deg", 107.7), 107.7),
				TypedVariant.as_float(look.get("key_roll_deg", 0.0), 0.0)
			)
			key.shadow_enabled = true
			key.shadow_opacity = TypedVariant.as_float(look.get("key_shadow_opacity", 0.55), 0.55)
	var rim: DirectionalLight3D = root.get_node_or_null("RimLightOffscreen") as DirectionalLight3D
	if rim:
		var rim_default: float = 0.0 if unity else 0.52
		rim.light_energy = TypedVariant.as_float(look.get("rim_energy", rim_default), rim_default)
	var fill_default: float = 0.0 if unity else 0.05
	var fill_e: float = TypedVariant.as_float(look.get("fill_energy", fill_default), fill_default)
	for fill_name: String in ["FillLight", "FillLightAI", "FillLightPlayer"]:
		var fill: OmniLight3D = root.get_node_or_null(fill_name) as OmniLight3D
		if fill:
			fill.light_energy = fill_e
	var scene_key: DirectionalLight3D = root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if scene_key:
		var scene_default: float = 0.0 if unity else 0.80
		scene_key.light_energy = TypedVariant.as_float(look.get("scene_key_energy", scene_default), scene_default)


static func clear_caches() -> void:
	_remap_cache.clear()
	_palette_cache.clear()
