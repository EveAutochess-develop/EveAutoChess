extends RefCounted
class_name ModFxResolve
## Merge mod weapon_fx_override onto stock weapon_fx.json kinds.
## Authority: MODS.md §3.3 · MOD_PROTOCOL §1.2.0 · COMBAT §8.2a
## Do NOT reference DataStore here (avoids class_name cycle with ModManager).

const SAFE_SCALAR_KEYS: Array[String] = [
	"color", "width", "duration_scale", "duration_scale_near", "duration_scale_far",
	"strobe_hz", "scroll_speed", "grid_mix", "emission_boost", "flow_to_target",
]
const TEX_KEYS: Array[String] = [
	"tex_near", "tex_far", "tex_shared", "tex_noise", "tex_beam", "tex_grid", "tex_target",
]
const LAYER_KEYS: Array[String] = ["strobe_layers_near", "strobe_layers_far"]
const FORBIDDEN_OVERRIDE_KEYS: Array[String] = [
	"style", "look", "evemu_effect", "evemu_group", "role_near", "role_far",
]


## Clone kinds[base] and apply safe override fields. Empty if base missing.
static func merge_override(override: Dictionary, kinds: Dictionary) -> Dictionary:
	var base_name: String = str(override.get("base", "")).strip_edges()
	if base_name == "" or kinds.is_empty() or not kinds.has(base_name):
		return {}
	var out: Dictionary = TypedVariant.as_dict(kinds[base_name]).duplicate(true)
	for k_any: Variant in override.keys():
		var k: String = str(k_any)
		if k == "base":
			continue
		if FORBIDDEN_OVERRIDE_KEYS.has(k):
			continue
		if SAFE_SCALAR_KEYS.has(k) or TEX_KEYS.has(k) or LAYER_KEYS.has(k):
			out[k] = override[k]
	return out


## Resolve relative texture paths under unit_dir/fx/ (or unit_dir / package-relative).
static func normalize_override_paths(override: Dictionary, unit_dir: String) -> Dictionary:
	var out: Dictionary = override.duplicate(true)
	for k: String in TEX_KEYS:
		if not out.has(k):
			continue
		var p: String = str(out.get(k, "")).strip_edges()
		if p == "":
			continue
		out[k] = resolve_tex_path(unit_dir, p)
	for k: String in LAYER_KEYS:
		if not out.has(k):
			continue
		var arr: Array = TypedVariant.as_array(out.get(k, []))
		var resolved: Array = []
		for item: Variant in arr:
			var p2: String = str(item).strip_edges()
			if p2 == "":
				continue
			resolved.append(resolve_tex_path(unit_dir, p2))
		out[k] = resolved
	return out


static func resolve_tex_path(unit_dir: String, rel_or_abs: String) -> String:
	var p: String = rel_or_abs.strip_edges().replace("\\", "/")
	if p == "":
		return ""
	if p.begins_with("res://") or p.begins_with("user://"):
		return p
	## Windows absolute
	if p.length() >= 3 and p[1] == ":" and (p[2] == "/" or p[2] == "\\"):
		return p
	if p.begins_with("/"):
		return p
	var candidates: PackedStringArray = PackedStringArray([
		unit_dir.path_join("fx").path_join(p),
		unit_dir.path_join(p),
	])
	if p.begins_with("fx/"):
		candidates.append(unit_dir.path_join(p))
	for c: String in candidates:
		if FileAccess.file_exists(c):
			return c
	return unit_dir.path_join("fx").path_join(p.get_file() if p.find("/") < 0 else p)


## Lint notes for one override object (does not mutate). kinds may be empty at import-time.
static func lint_override(override: Dictionary, label: String, kinds: Dictionary = {}) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	if override.is_empty():
		return w
	var base_name: String = str(override.get("base", "")).strip_edges()
	if base_name == "":
		w.append("%s: weapon_fx_override missing base" % label)
	elif not kinds.is_empty() and not kinds.has(base_name):
		w.append("%s: weapon_fx_override.base unknown kind '%s'" % [label, base_name])
	for k_any: Variant in override.keys():
		var k: String = str(k_any)
		if k == "base":
			continue
		if FORBIDDEN_OVERRIDE_KEYS.has(k):
			w.append("%s: weapon_fx_override forbids key '%s' (ignored)" % [label, k])
			continue
		if SAFE_SCALAR_KEYS.has(k) or TEX_KEYS.has(k) or LAYER_KEYS.has(k):
			continue
		w.append("%s: weapon_fx_override unknown key '%s' (ignored)" % [label, k])
	return w
