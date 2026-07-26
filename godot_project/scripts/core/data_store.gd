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
	ships.clear()
	fetters.clear()
	_load_dir_ships("res://data/ships")
	_load_dir_fetters("res://data/fetters")

func ship_mesh_path(ship_id: int) -> String:
	var m: Dictionary = visual_meshes.get("ships", {})
	return str(m.get(str(ship_id), ""))

func ship_diffuse_path(ship_id: int) -> String:
	var m: Dictionary = ship_textures.get("ships", {})
	return str(m.get(str(ship_id), ""))

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
	var ids: Array = ships.keys()
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
