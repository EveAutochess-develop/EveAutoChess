extends RefCounted
class_name ModTrailResolve
## Merge ship/unmanned trail_override onto global DataStore.visual trail keys.
## Authority: MODS.md §3.3 · MOD_PROTOCOL §1.2.0c · COMBAT §14D
## Do NOT reference DataStore here (avoids class_name cycle with ModManager).

## Author-facing keys → visual.json booster_* keys (tint deliberately omitted).
const KEY_MAP: Dictionary = {
	"mesh_style": "booster_trail_mesh_style",
	"brightness": "booster_trail_brightness",
	"fade_power": "booster_trail_fade_power",
	"lifetime_s": "booster_trail_lifetime_s",
	"stamp_interval_s": "booster_trail_stamp_interval_s",
	"unmanned_stamp_interval_s": "booster_trail_unmanned_stamp_interval_s",
	"min_stamp_wu": "booster_trail_min_stamp_wu",
	"max_segments": "booster_trail_max_segments",
	"width_mul": "unmanned_single_strand_width_mul",
	"single_strand": "unmanned_single_strand_trail",
}

const SAFE_KEYS: Array[String] = [
	"mesh_style", "brightness", "fade_power", "lifetime_s",
	"stamp_interval_s", "unmanned_stamp_interval_s", "min_stamp_wu",
	"max_segments", "width_mul", "single_strand",
]

const FORBIDDEN_OVERRIDE_KEYS: Array[String] = [
	"tint_player", "tint_enemy", "booster_tint_player", "booster_tint_enemy",
	"tint", "color", "nozzles", "engine_boosters", "pos", "outline",
	"style", "look", "shader", "script",
]


## Clone global visual and overlay allowlisted trail_override fields. Empty override → copy of base.
static func merge_onto_visual(base_visual: Dictionary, override: Dictionary) -> Dictionary:
	var out: Dictionary = base_visual.duplicate(true)
	if override.is_empty():
		return out
	for k_any: Variant in override.keys():
		var k: String = str(k_any)
		if not SAFE_KEYS.has(k):
			continue
		if FORBIDDEN_OVERRIDE_KEYS.has(k):
			continue
		var mapped: String = str(KEY_MAP.get(k, ""))
		if mapped == "":
			continue
		if k == "mesh_style":
			var style: String = str(override.get(k, "")).strip_edges().to_lower()
			if style == "tube" or style == "ribbon":
				out[mapped] = style
			continue
		out[mapped] = override[k]
	return out


static func lint_override(override: Dictionary, label: String) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	if override.is_empty():
		return w
	for k_any: Variant in override.keys():
		var k: String = str(k_any)
		if FORBIDDEN_OVERRIDE_KEYS.has(k) or k.begins_with("booster_tint") or k.begins_with("tint_"):
			w.append("%s: trail_override forbids key '%s' (ignored; team tint / nozzles stay global)" % [label, k])
			continue
		if SAFE_KEYS.has(k):
			if k == "mesh_style":
				var style: String = str(override.get(k, "")).strip_edges().to_lower()
				if style != "ribbon" and style != "tube":
					w.append("%s: trail_override.mesh_style must be ribbon|tube (got '%s')" % [label, style])
			continue
		w.append("%s: trail_override unknown key '%s' (ignored)" % [label, k])
	return w


## Prefer unit.json trail_override; else lift from visual.json stash.
static func pick_from_unit_data(data: Dictionary) -> Dictionary:
	var ov: Dictionary = TypedVariant.as_dict(data.get("trail_override", {}))
	if not ov.is_empty():
		return ov
	var vis: Dictionary = TypedVariant.as_dict(data.get("_visual", {}))
	return TypedVariant.as_dict(vis.get("trail_override", {}))
