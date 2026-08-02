extends RefCounted
class_name SkyboxCatalog
## NEW_EDEN_REGIONS — region pool + display names.
## Sky *rendering* uses legacy panoramas only (§2 deferred: no race/region switch).

## Old-version construction (f88cac7 / early match_root): root JPEGs, not races/*h1.
const LEGACY_PANO_ROOT := "res://assets/skyboxes"
const LEGACY_DEFAULT := "res://assets/skyboxes/amarr.jpeg"
const LEGACY_FALLBACKS := [
	"res://assets/skyboxes/gallente.jpeg",
	"res://assets/skyboxes/wormhole.jpeg",
]
const FALLBACK_JPEG := LEGACY_DEFAULT
## Exposure for legacy panoramas (old _ensure_sky used 1.25).
const RACE_SKY_ENERGY := 1.25

## Kept for lowsec UI labels / tools; not used to pick panorama files.
const RACE_STEM_LIST := ["ah1", "ch1", "gh1", "mh1"]
const RACE_STEMS := {
	"a": "ah1",
	"c": "ch1",
	"g": "gh1",
	"m": "mh1",
}

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
	if region_id in RACE_STEM_LIST:
		return region_id
	var mapped := str(_skybox_map.get(region_id, ""))
	if mapped in RACE_STEM_LIST:
		return mapped
	if mapped != "":
		var letter := mapped.substr(0, 1).to_lower()
		if RACE_STEMS.has(letter):
			return str(RACE_STEMS[letter])
	return "ah1"


static func race_stem_list() -> Array:
	return RACE_STEM_LIST.duplicate()


static func pick_random_race_stem(rng: RandomNumberGenerator = null) -> String:
	## Label/tool helper only — does not select the rendered panorama (§2 deferred).
	var i := 0
	if rng != null:
		i = rng.randi_range(0, RACE_STEM_LIST.size() - 1)
	else:
		i = randi() % RACE_STEM_LIST.size()
	return str(RACE_STEM_LIST[i])


static func load_race_texture(_stem: String) -> Texture2D:
	return load_legacy_panorama()


static func load_legacy_panorama() -> Texture2D:
	var tex := UiAssets.tex(LEGACY_DEFAULT)
	if tex != null:
		return tex
	for path in LEGACY_FALLBACKS:
		tex = UiAssets.tex(str(path))
		if tex != null:
			return tex
	return null


static func nullsec_regions() -> Array:
	ensure_loaded()
	## Pool is assignable regardless of race JPG presence (sky deferred).
	var out: Array = []
	for r in _nullsec_pool:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var rid := str((r as Dictionary).get("region_id", ""))
		if rid == "":
			continue
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

static func display_name(region_id: String) -> String:
	match region_id:
		"ah1":
			return "艾玛星空"
		"ch1":
			return "加达里星空"
		"gh1":
			return "盖伦特星空"
		"mh1":
			return "米玛塔尔星空"
	ensure_loaded()
	for r in _nullsec_pool:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if str((r as Dictionary).get("region_id", "")) != region_id:
			continue
		var zh := str((r as Dictionary).get("name_zh", ""))
		return zh if zh != "" else str((r as Dictionary).get("name_en", region_id))
	return region_id

## True when the region can be assigned (pool row). Sky assets are not required.
static func has_own_sky(region_id: String) -> bool:
	if region_id == "":
		return false
	if region_id in RACE_STEM_LIST:
		return true
	ensure_loaded()
	for r in _nullsec_pool:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if str((r as Dictionary).get("region_id", "")) == region_id:
			return true
	return _skybox_map.has(region_id)

static func panorama_path(_region_id: String) -> String:
	return LEGACY_DEFAULT

static func load_sky_texture(_region_id: String) -> Texture2D:
	## Region id ignored for rendering while §2 is deferred.
	return load_legacy_panorama()
