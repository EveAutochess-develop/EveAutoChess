extends RefCounted
class_name SkyboxCatalog
## NEW_EDEN_REGIONS — region_id → tq_universe stem; load cube/panorama for match.

const TQ_ROOT := "res://assets/skyboxes/tq_universe"
## Equirect panorama per region, unwrapped from that region's TQ cube by
## `tools/stage_region_skyboxes.py` (NEW_EDEN_REGIONS §2 天空盒 1:1).
const PANO_ROOT := "res://assets/skyboxes/regions"
const FALLBACK_JPEG := "res://assets/skyboxes/amarr.jpeg"

static var _skybox_map: Dictionary = {}
static var _nullsec_pool: Array = []
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var map_path := "res://data/regions/skybox_map.json"
	if FileAccess.file_exists(map_path):
		var txt := FileAccess.get_file_as_string(map_path)
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			_skybox_map = parsed
	var pool_path := "res://data/regions/nullsec_pool.json"
	if FileAccess.file_exists(pool_path):
		var txt2 := FileAccess.get_file_as_string(pool_path)
		var parsed2: Variant = JSON.parse_string(txt2)
		if typeof(parsed2) == TYPE_DICTIONARY:
			_nullsec_pool = parsed2.get("regions", []) as Array

static func stem_for_region(region_id: String) -> String:
	ensure_loaded()
	return str(_skybox_map.get(region_id, ""))

static func nullsec_regions() -> Array:
	ensure_loaded()
	## Only regions whose own sky actually shipped are assignable (§2 缺资源).
	var out: Array = []
	for r in _nullsec_pool:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if has_own_sky(str((r as Dictionary).get("region_id", ""))):
			out.append((r as Dictionary).duplicate(true))
	return out

static func must_include_region_ids() -> Array:
	ensure_loaded()
	var pool_path := "res://data/regions/nullsec_pool.json"
	if FileAccess.file_exists(pool_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pool_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed.get("must_include", ["period_basis"]) as Array
	return ["period_basis"]

static func cube_texture_path(stem: String) -> String:
	## Prefer Godot-importable faces; DDS cube may need importer — try panorama jpeg fallbacks first.
	var candidates := [
		"%s/%s/%s_cube.dds" % [TQ_ROOT, stem, stem],
		"%s/%s/%s_cube_lowdetail.dds" % [TQ_ROOT, stem, stem],
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			return p
	return ""

static func display_name(region_id: String) -> String:
	ensure_loaded()
	for r in _nullsec_pool:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if str((r as Dictionary).get("region_id", "")) != region_id:
			continue
		var zh := str((r as Dictionary).get("name_zh", ""))
		return zh if zh != "" else str((r as Dictionary).get("name_en", region_id))
	return region_id

## True when this region owns a sky of its own — a region that would only get the
## generic backdrop must stay out of the pool (NEW_EDEN_REGIONS §2 缺资源).
static func has_own_sky(region_id: String) -> bool:
	return region_id != "" and ResourceLoader.exists(panorama_path(region_id))

static func panorama_path(region_id: String) -> String:
	return "%s/%s.jpg" % [PANO_ROOT, region_id]

static func load_sky_texture(region_id: String) -> Texture2D:
	ensure_loaded()
	## Panorama first: PanoramaSkyMaterial wants equirect, and the cube DDS suite
	## is 1.9 GB, so only the unwrapped copies ship.
	var pano := panorama_path(region_id)
	if ResourceLoader.exists(pano):
		var pano_tex: Resource = load(pano)
		if pano_tex is Texture2D:
			return pano_tex as Texture2D
	var stem := stem_for_region(region_id)
	if stem != "":
		var cube := cube_texture_path(stem)
		if cube != "":
			var tex: Resource = load(cube)
			if tex is Texture2D:
				return tex as Texture2D
	## Fallback race JPEGs
	var jpeg := UiAssets.tex(FALLBACK_JPEG)
	if jpeg == null:
		jpeg = UiAssets.tex("res://assets/skyboxes/gallente.jpeg")
	return jpeg
