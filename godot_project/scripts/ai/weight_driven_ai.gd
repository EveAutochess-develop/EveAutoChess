extends RefCounted
class_name WeightDrivenAi
## Load farm artifacts (behavior.genome + T0–Tn table). No farm code in-engine.
## Spec: EVEautochessAI-design/docs/AI_SELFPLAY.md · handbook §0.2.

const SCHEMA_VER: String = "1"
const TITAN_IDS: PackedStringArray = ["amarr", "caldari", "gallente", "minmatar", "angel"]
const STANCE_IDS: PackedStringArray = ["economy", "offense", "logistics", "speed_control", "formation"]
const STANCE_FLOOR: float = 0.05

var genome: Dictionary = {}
var ranking: Dictionary = {}
var _ship_tier: Dictionary = {} ## ship_id string -> tier index (0 = T0 strongest)


func is_ready() -> bool:
	return not genome.is_empty() and not ranking.is_empty()


func try_autoload() -> bool:
	## user:// overlay, then optional res:// baseline. Missing files → not ready (AiController §2).
	var g_user: String = "user://eveac_ai/behavior.genome.json"
	var t_user: String = "user://eveac_ai/weights_table.json"
	if FileAccess.file_exists(g_user) and FileAccess.file_exists(t_user):
		return load_behavior(g_user) and load_ranking_table(t_user)
	var g_res: String = "res://data/ai/behavior.genome.json"
	var t_res: String = "res://data/ai/weights_table.json"
	if FileAccess.file_exists(g_res) and FileAccess.file_exists(t_res):
		return load_behavior(g_res) and load_ranking_table(t_res)
	return false


func load_behavior(path: String) -> bool:
	var data: Dictionary = _read_json_dict(path)
	if data.is_empty():
		push_warning("WeightDrivenAi: genome missing or invalid: %s" % path)
		genome = {}
		return false
	if str(data.get("schema_ver", "")) != SCHEMA_VER:
		push_warning("WeightDrivenAi: genome schema_ver mismatch (%s)" % str(data.get("schema_ver", "")))
		genome = {}
		return false
	if not ranking.is_empty() and str(ranking.get("content_rev", "")) != str(data.get("content_rev", "")):
		push_warning("WeightDrivenAi: genome content_rev != ranking table")
		genome = {}
		return false
	genome = data
	return true


func apply_genome_delta(delta: Dictionary) -> void:
	if delta.is_empty() or genome.is_empty():
		if not delta.is_empty() and genome.is_empty():
			genome = delta.duplicate(true)
		return
	var stance: Dictionary = TypedVariant.as_dict(delta.get("stance", {}))
	if not stance.is_empty():
		genome["stance"] = stance.duplicate(true)
	var pick: Dictionary = TypedVariant.as_dict(delta.get("titan_pick", {}))
	if not pick.is_empty():
		genome["titan_pick"] = pick.duplicate(true)
	var d_slices: Dictionary = TypedVariant.as_dict(delta.get("titan_slices", {}))
	if d_slices.is_empty():
		return
	var slices: Dictionary = TypedVariant.as_dict(genome.get("titan_slices", {})).duplicate(true)
	for k_v: Variant in d_slices.keys():
		var k: String = str(k_v)
		var overlay: Dictionary = TypedVariant.as_dict(d_slices[k_v])
		var cur: Dictionary = TypedVariant.as_dict(slices.get(k, {})).duplicate(true)
		var ships: Dictionary = TypedVariant.as_dict(cur.get("ship", {})).duplicate(true)
		var equips: Dictionary = TypedVariant.as_dict(cur.get("equip", {})).duplicate(true)
		var o_ships: Dictionary = TypedVariant.as_dict(overlay.get("ship", {}))
		var o_eq: Dictionary = TypedVariant.as_dict(overlay.get("equip", {}))
		for sk: Variant in o_ships.keys():
			ships[sk] = o_ships[sk]
		for ek: Variant in o_eq.keys():
			equips[ek] = o_eq[ek]
		cur["ship"] = ships
		cur["equip"] = equips
		slices[k] = cur
	genome["titan_slices"] = slices


func load_ranking_table(path: String) -> bool:
	var data: Dictionary = _read_json_dict(path)
	if data.is_empty():
		push_warning("WeightDrivenAi: ranking table missing or invalid: %s" % path)
		ranking = {}
		_ship_tier.clear()
		return false
	if str(data.get("schema_ver", "")) != SCHEMA_VER:
		push_warning("WeightDrivenAi: ranking schema_ver mismatch (%s)" % str(data.get("schema_ver", "")))
		ranking = {}
		_ship_tier.clear()
		return false
	if not genome.is_empty() and str(genome.get("content_rev", "")) != str(data.get("content_rev", "")):
		push_warning("WeightDrivenAi: ranking content_rev != genome")
		ranking = {}
		_ship_tier.clear()
		return false
	ranking = data
	_index_ship_tiers()
	return true


func current_titan_slice(titan_id: String) -> Dictionary:
	if genome.is_empty():
		return {}
	var slices: Dictionary = TypedVariant.as_dict(genome.get("titan_slices", {}))
	var key: String = titan_id if TITAN_IDS.has(titan_id) and slices.has(titan_id) else "caldari"
	return TypedVariant.as_dict(slices.get(key, {}))


func stance_mix() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(STANCE_IDS.size())
	var raw: Dictionary = TypedVariant.as_dict(genome.get("stance", {}))
	var acc: float = 0.0
	var n: int = STANCE_IDS.size()
	var prior: float = 1.0 / float(n)
	for i: int in range(n):
		var v: float = maxf(STANCE_FLOOR, TypedVariant.as_float(raw.get(STANCE_IDS[i], prior), prior))
		out[i] = v
		acc += v
	if acc <= 0.0:
		for i: int in range(n):
			out[i] = prior
		return out
	for i: int in range(n):
		out[i] = out[i] / acc
	return out


func titan_pick_vec() -> PackedFloat32Array:
	## Same order as farm TITAN_IDS / TitanNet out.
	var out: PackedFloat32Array = PackedFloat32Array()
	var n: int = TITAN_IDS.size()
	out.resize(n)
	var raw: Dictionary = TypedVariant.as_dict(genome.get("titan_pick", {}))
	var acc: float = 0.0
	var prior: float = 1.0 / float(n)
	for i: int in range(n):
		var v: float = maxf(1e-6, TypedVariant.as_float(raw.get(TITAN_IDS[i], prior), prior))
		out[i] = v
		acc += v
	if acc <= 0.0:
		for i: int in range(n):
			out[i] = prior
		return out
	for i: int in range(n):
		out[i] = out[i] / acc
	return out


func ship_tier(ship_id: int) -> int:
	## 0 = T0 (strongest). Missing id → last tier (neutral prior).
	if _ship_tier.is_empty():
		return 99
	var key: String = str(ship_id)
	if _ship_tier.has(key):
		return TypedVariant.as_int(_ship_tier[key], 99)
	return 99


func pick_unpurchased_shop_index(shop_slots: Array, titan_id: String) -> int:
	## Lower T-index preferred; same tier broken by current titan-slice weight.
	var slice_ships: Dictionary = TypedVariant.as_dict(current_titan_slice(titan_id).get("ship", {}))
	var best_i: int = -1
	var best_tier: int = 1000000
	var best_w: float = -1.0
	for i: int in range(shop_slots.size()):
		var slot: Dictionary = TypedVariant.as_dict(shop_slots[i])
		if TypedVariant.as_bool(slot.get("purchased", false), false):
			continue
		var sid: int = TypedVariant.as_int(slot.get("ship_id", 0), 0)
		var t: int = ship_tier(sid)
		var w: float = TypedVariant.as_float(slice_ships.get(str(sid), 0.5), 0.5)
		if best_i < 0 or t < best_tier or (t == best_tier and w > best_w):
			best_i = i
			best_tier = t
			best_w = w
	return best_i


func _index_ship_tiers() -> void:
	_ship_tier.clear()
	var tiers: Dictionary = TypedVariant.as_dict(ranking.get("tiers", {}))
	var order: Array = TypedVariant.as_array(ranking.get("tier_order", []))
	if order.is_empty():
		var keys: Array = tiers.keys()
		keys.sort()
		order = keys
	for ti: int in range(order.size()):
		var tname: String = str(order[ti])
		var bucket: Dictionary = TypedVariant.as_dict(tiers.get(tname, {}))
		var ships: Array = TypedVariant.as_array(bucket.get("ships", []))
		for sid_v: Variant in ships:
			_ship_tier[str(sid_v)] = ti


func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	return TypedVariant.as_dict(JSON.parse_string(txt))
