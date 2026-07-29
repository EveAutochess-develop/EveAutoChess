extends Node
## Loads all data/*.json — single source for bricks (no magic numbers in gameplay).

var match_flow: Dictionary = {}
var economy: Dictionary = {}
var board: Dictionary = {}
var combat: Dictionary = {}
var ai: Dictionary = {}
var visual: Dictionary = {}
var weapon_fx: Dictionary = {}
var visual_meshes: Dictionary = {}  # ships: { "1": "res://..." }
var ship_textures: Dictionary = {}  # ships: { "1": "res://..._d.dds" }
var ship_portraits: Dictionary = {}  # ships: { "1": "res://.../portraits/{key}.png" }
var ships: Dictionary = {}  # id(int) -> dict
var fetters: Dictionary = {}  # id(str) -> dict
var content_version: String = "local"

func _ready() -> void:
	reload_all()

func reload_all() -> void:
	match_flow = _load_json("res://data/balance/match_flow.json")
	economy = _load_json("res://data/balance/economy.json")
	board = _load_json("res://data/balance/board.json")
	combat = _load_json("res://data/balance/combat.json")
	ai = _load_json("res://data/balance/ai.json")
	visual = _load_json("res://data/balance/visual.json")
	weapon_fx = _load_json("res://data/balance/weapon_fx.json")
	visual_meshes = _load_json("res://data/visual_meshes.json")
	ship_textures = _load_json("res://data/ship_textures.json")
	ship_portraits = _load_json("res://data/ship_portraits.json")
	ships.clear()
	fetters.clear()
	_load_dir_ships("res://data/ships")
	_load_dir_ships("res://data/unmanned_units")
	_load_dir_fetters("res://data/fetters")
	ShipLook.clear_caches()

func ship_mesh_path(ship_id: int) -> String:
	var m: Dictionary = visual_meshes.get("ships", {})
	return str(m.get(str(ship_id), ""))

func ship_diffuse_path(ship_id: int) -> String:
	var m: Dictionary = ship_textures.get("ships", {})
	return str(m.get(str(ship_id), ""))

func ship_portrait_path(ship_id: int) -> String:
	var m: Dictionary = ship_portraits.get("ships", {})
	var mapped := str(m.get(str(ship_id), ""))
	if mapped != "":
		return mapped
	var s := get_ship(ship_id)
	return str(s.get("portrait", ""))

func _res_file_ok(path: String) -> bool:
	if path == "":
		return false
	if ResourceLoader.exists(path):
		return true
	var abs_path := ProjectSettings.globalize_path(path)
	return abs_path != "" and FileAccess.file_exists(abs_path)

func resolve_model_bundle(model_key: String) -> Dictionary:
	## §0 drop-in pack: assets/models/ships/{model_key}/{model.glb,albedo.png,normal.png,pmwo.png,rg.png,reduction.png}
	var out := {"mesh": "", "albedo": "", "normal": "", "pmwo": "", "rg": "", "reduction": ""}
	if model_key == "":
		return out
	var root := "res://assets/models/ships/%s" % model_key
	var mesh := root.path_join("model.glb")
	if _res_file_ok(mesh):
		out["mesh"] = mesh
	for albedo_name in ["albedo.png", "diffuse.png", "albedo.jpg"]:
		var ap := root.path_join(albedo_name)
		if _res_file_ok(ap):
			out["albedo"] = ap
			break
	for normal_name in ["normal.png", "nrm.png"]:
		var np := root.path_join(normal_name)
		if _res_file_ok(np):
			out["normal"] = np
			break
	for extra_name in ["pmwo.png", "rg.png", "reduction.png"]:
		var ep := root.path_join(extra_name)
		if _res_file_ok(ep):
			out[extra_name.get_basename()] = ep
	return out

func ship_mesh_path_resolved(ship_id: int) -> String:
	var path := ship_mesh_path(ship_id)
	if path != "" and _res_file_ok(path):
		return path
	var ship := get_ship(ship_id)
	var key := str(ship.get("model_key", ""))
	var bundle := resolve_model_bundle(key)
	return str(bundle.get("mesh", ""))

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("DataStore missing: " + path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _load_dir_ships(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			var d := _load_json(dir_path.path_join(fn))
			if d.has("id"):
				ships[int(d["id"])] = d
		fn = dir.get_next()

func _load_dir_fetters(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			var d := _load_json(dir_path.path_join(fn))
			if d.has("id"):
				fetters[str(d["id"])] = d
		fn = dir.get_next()

func ship_ids() -> Array:
	## Playable shop/AI pool — exclude unmanned templates.
	var ids: Array = []
	for k in ships.keys():
		var sid := int(k)
		var s: Dictionary = ships[k]
		if bool(s.get("is_unmanned", false)):
			continue
		ids.append(sid)
	ids.sort()
	return ids

func get_ship(id: int) -> Dictionary:
	return ships.get(id, {})

func get_star(ship_id: int, star: int) -> Dictionary:
	var s := get_ship(ship_id)
	var stars = s.get("stars", [])
	if star < 1 or star > stars.size():
		return {}
	return stars[star - 1]

func ship_has_group(ship_id: int, tag: String) -> bool:
	var s := get_ship(ship_id)
	var groups = s.get("ship_groups", [])
	return tag in groups
