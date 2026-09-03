extends RefCounted
class_name ModPrepareRadarResolve
## Merge mod prepare_radar_override onto global visual flash colors.
## Authority: MODS.md · MOD_PROTOCOL · BOARD §Prepare radar

const SET_KEYS: Array[String] = ["fleet", "enemy", "friendly", "relation_friendly"]

const SAFE_KEYS: Array[String] = ["color", "flash_colors"]

const FORBIDDEN_OVERRIDE_KEYS: Array[String] = [
	"shader", "script", "style", "look", "period_s", "arc_deg",
]


static func merge_flash_colors(base_visual: Dictionary, override: Dictionary) -> Dictionary:
	var out: Dictionary = TypedVariant.as_dict(base_visual.get("prepare_radar_flash_colors", {})).duplicate(true)
	if override.is_empty():
		return out
	var colors_ov: Dictionary = TypedVariant.as_dict(override.get("flash_colors", {}))
	for k: String in SET_KEYS:
		if colors_ov.has(k):
			var c: Color = _parse_color(colors_ov.get(k, null))
			if c.a > 0.001:
				out[k] = [c.r, c.g, c.b]
	return out


static func lint_override(override: Dictionary, label: String) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	if override.is_empty():
		return w
	for k_any: Variant in override.keys():
		var k: String = str(k_any)
		if FORBIDDEN_OVERRIDE_KEYS.has(k):
			w.append("%s: prepare_radar_override forbids key '%s'" % [label, k])
			continue
		if k == "color":
			if _parse_color(override.get(k, null)).a <= 0.001:
				w.append("%s: prepare_radar_override.color invalid" % label)
			continue
		if k == "flash_colors":
			var colors: Dictionary = TypedVariant.as_dict(override.get(k, {}))
			for sk: String in colors.keys():
				if not SET_KEYS.has(str(sk)):
					w.append("%s: prepare_radar_override.flash_colors unknown set '%s'" % [label, sk])
			continue
		w.append("%s: prepare_radar_override unknown key '%s' (ignored)" % [label, k])
	return w


static func pick_from_unit_data(data: Dictionary) -> Dictionary:
	return TypedVariant.as_dict(data.get("prepare_radar_override", {}))


static func ship_flash_color(override: Dictionary, set_key: String, fallback: Color) -> Color:
	if override.has("color"):
		var c: Color = _parse_color(override.get("color", null))
		if c.a > 0.001:
			return c
	if set_key != "" and override.has("flash_colors"):
		var colors: Dictionary = TypedVariant.as_dict(override.get("flash_colors", {}))
		if colors.has(set_key):
			var c2: Color = _parse_color(colors.get(set_key, null))
			if c2.a > 0.001:
				return c2
	return fallback


static func color_from_visual_set(visual: Dictionary, set_key: String, fallback: Color) -> Color:
	var table: Dictionary = TypedVariant.as_dict(visual.get("prepare_radar_flash_colors", {}))
	if not table.has(set_key):
		return fallback
	var v: Variant = table.get(set_key)
	if v is Color:
		return v
	if v is Array:
		var arr: Array = v
		if arr.size() >= 3:
			return Color(
				TypedVariant.as_float(arr[0], fallback.r),
				TypedVariant.as_float(arr[1], fallback.g),
				TypedVariant.as_float(arr[2], fallback.b),
				1.0
			)
	return _parse_color(v, fallback)


static func _parse_color(v: Variant, fb: Color = Color(0.0, 0.0, 0.0, 0.0)) -> Color:
	if v == null:
		return fb
	if v is Color:
		return v
	if v is Array:
		var arr: Array = v
		if arr.size() >= 3:
			return Color(
				TypedVariant.as_float(arr[0], 0.0),
				TypedVariant.as_float(arr[1], 0.0),
				TypedVariant.as_float(arr[2], 0.0),
				1.0
			)
	var s: String = str(v).strip_edges()
	if s == "":
		return fb
	if s.begins_with("#"):
		return Color.html(s)
	return fb
