extends RefCounted
class_name ModInteractionFxResolve
## Merge mod interaction_fx_override onto stock interaction_fx.json kinds.
## Authority: COMBAT §8.4 · MOD_PROTOCOL §1.2.x · MODS §3.3

const FX_PROTOCOL_SUPPORTED: int = 2

const SAFE_SCALAR_KEYS: Array[String] = [
	"color", "scale", "duration_scale", "emit_boost", "anchor",
]
const TEX_KEYS: Array[String] = ["tex_ring", "tex_sprite"]
const FORBIDDEN_OVERRIDE_KEYS: Array[String] = [
	"style", "look", "weapon_fx_kind", "max_layers", "max_particles_per_layer",
	"blend_mode", "space",
]


static func merge_override(override: Dictionary, kinds: Dictionary) -> Dictionary:
	var base_name: String = str(override.get("base", "")).strip_edges()
	if base_name == "" or kinds.is_empty() or not kinds.has(base_name):
		return {}
	var out: Dictionary = TypedVariant.as_dict(kinds[base_name]).duplicate(true)
	for k_any: Variant in override.keys():
		var k: String = str(k_any)
		if k == "base" or k == "recipe":
			continue
		if FORBIDDEN_OVERRIDE_KEYS.has(k):
			continue
		if SAFE_SCALAR_KEYS.has(k) or TEX_KEYS.has(k):
			out[k] = override[k]
	if override.has("recipe"):
		out["recipe"] = str(override.get("recipe", "")).strip_edges()
	return out


static func normalize_override_paths(override: Dictionary, unit_dir: String) -> Dictionary:
	var out: Dictionary = override.duplicate(true)
	for k: String in TEX_KEYS:
		if not out.has(k):
			continue
		var p: String = str(out.get(k, "")).strip_edges()
		if p == "":
			continue
		out[k] = ModFxResolve.resolve_tex_path(unit_dir, p)
	if out.has("recipe"):
		var rp: String = str(out.get("recipe", "")).strip_edges().replace("\\", "/")
		if rp != "" and not rp.begins_with("/") and rp.find(":") < 0:
			var candidates: PackedStringArray = PackedStringArray([
				unit_dir.path_join(rp),
				unit_dir.path_join("fx").path_join(rp.get_file()),
			])
			for c: String in candidates:
				if FileAccess.file_exists(c):
					out["recipe_abs"] = c
					break
			if not out.has("recipe_abs"):
				out["recipe_abs"] = unit_dir.path_join(rp)
	return out


static func lint_override(override: Dictionary, label: String, kinds: Dictionary = {}) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	if override.is_empty():
		return w
	var base_name: String = str(override.get("base", "")).strip_edges()
	if base_name == "":
		w.append("%s: interaction_fx_override missing base" % label)
	elif not kinds.is_empty() and not kinds.has(base_name):
		w.append("%s: interaction_fx_override.base unknown kind '%s'" % [label, base_name])
	for k_any: Variant in override.keys():
		var k: String = str(k_any)
		if k == "base" or k == "recipe" or k == "recipe_abs":
			continue
		if FORBIDDEN_OVERRIDE_KEYS.has(k):
			w.append("%s: interaction_fx_override forbids key '%s' (ignored)" % [label, k])
			continue
		if SAFE_SCALAR_KEYS.has(k) or TEX_KEYS.has(k):
			continue
		w.append("%s: interaction_fx_override unknown key '%s' (ignored)" % [label, k])
	var recipe_rel: String = str(override.get("recipe", "")).strip_edges()
	if recipe_rel != "" and not recipe_rel.ends_with(".json"):
		w.append("%s: interaction_fx_override.recipe should be .json" % label)
	return w


static func lint_recipe(recipe: Dictionary, label: String, max_layers: int = 4, max_particles: int = 128) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	if recipe.is_empty():
		w.append("%s: empty interaction recipe" % label)
		return w
	var schema: int = TypedVariant.as_int(recipe.get("schema", 0), 0)
	if schema != 1:
		w.append("%s: interaction recipe schema %s != 1" % [label, schema])
	var layers: Array = TypedVariant.as_array(recipe.get("layers", []))
	if layers.size() > max_layers:
		w.append("%s: recipe layers %d > max %d (clamped at runtime)" % [label, layers.size(), max_layers])
	for i: int in range(layers.size()):
		if typeof(layers[i]) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = TypedVariant.as_dict(layers[i])
		var mp: int = TypedVariant.as_int(layer.get("max_particles", 0), 0)
		if mp > max_particles:
			w.append("%s: layer %d max_particles %d > %d" % [label, i, mp, max_particles])
	return w


static func load_recipe_file(abs_path: String) -> Dictionary:
	if abs_path.strip_edges() == "" or not FileAccess.file_exists(abs_path):
		return {}
	var txt: String = FileAccess.get_file_as_string(abs_path)
	if txt.strip_edges() == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return TypedVariant.as_dict(parsed)
