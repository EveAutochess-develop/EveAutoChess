extends RefCounted
class_name ModTitanResolve
## Lobby titan picks + race→ship/fetter mapping (MULTIPLAYER_PVP §2 · FETTERS §4.2).
## Authority: MODS.md §3.4 · MOD_PROTOCOL §1.1 / §1.4

const OFFICIAL_TITAN_PICKS: Array[Dictionary] = [
	{"race": "caldari", "label": "勒维亚坦 · 加达里", "icon": "caldari", "ship_id": 202, "fetter_id": "titan_caldari"},
	{"race": "gallente", "label": "俄洛巴斯 · 盖伦特", "icon": "gallente", "ship_id": 203, "fetter_id": "titan_gallente"},
	{"race": "minmatar", "label": "拉格纳洛克 · 米玛塔尔", "icon": "minmatar", "ship_id": 204, "fetter_id": "titan_minmatar"},
	{"race": "amarr", "label": "神使 · 艾玛", "icon": "amarr", "ship_id": 201, "fetter_id": "titan_amarr"},
	{"race": "angel", "label": "征服者 · 天使", "icon": "angel", "ship_id": 205, "fetter_id": "titan_angel"},
]

const FORBIDDEN_RACES: Array[String] = ["spectate", ""]


static func official_registry() -> Dictionary:
	var out: Dictionary = {}
	for raw: Dictionary in OFFICIAL_TITAN_PICKS:
		var race: String = str(raw.get("race", "")).strip_edges().to_lower()
		if race == "":
			continue
		out[race] = raw.duplicate(true)
	return out


static func pick_list_from_registry(reg: Dictionary) -> Array:
	var order: PackedStringArray = PackedStringArray()
	for raw: Dictionary in OFFICIAL_TITAN_PICKS:
		var race: String = str(raw.get("race", "")).strip_edges().to_lower()
		if reg.has(race):
			order.append(race)
	for race_any: Variant in reg.keys():
		var race_k: String = str(race_any).strip_edges().to_lower()
		if race_k != "" and not order.has(race_k):
			order.append(race_k)
	var out: Array = []
	for race: String in order:
		out.append(TypedVariant.as_dict(reg[race]).duplicate(true))
	return out


static func race_keys_from_registry(reg: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in pick_list_from_registry(reg):
		var race: String = str(e.get("race", "")).strip_edges().to_lower()
		if race != "":
			out.append(race)
	return out


static func lint_pick(entry: Dictionary, label: String) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	var race: String = str(entry.get("race", "")).strip_edges().to_lower()
	if race == "":
		w.append("%s: titan_picks missing race" % label)
	elif FORBIDDEN_RACES.has(race):
		w.append("%s: titan_picks race '%s' reserved" % [label, race])
	elif race != str(entry.get("race", "")).strip_edges():
		w.append("%s: titan_picks race should be lowercase" % label)
	if str(entry.get("label", "")).strip_edges() == "":
		w.append("%s: titan_picks missing label" % label)
	var ship_lid: int = TypedVariant.as_int(entry.get("ship_local_id", -1), -1)
	if ship_lid < 0:
		w.append("%s: titan_picks missing ship_local_id" % label)
	elif ship_lid > 9999:
		w.append("%s: titan_picks ship_local_id must be XXXX (0–9999)" % label)
	var fid: String = str(entry.get("fetter_id", "")).strip_edges()
	if fid != "" and not fid.begins_with("titan_"):
		w.append("%s: titan_picks fetter_id should start with titan_" % label)
	return w


static func normalize_pick(
	entry: Dictionary,
	package_name: String,
	xx: int,
	_runtime_ships: Dictionary,
	_runtime_fetters: Dictionary
) -> Dictionary:
	var race: String = str(entry.get("race", "")).strip_edges().to_lower()
	var lid: int = TypedVariant.as_int(entry.get("ship_local_id", -1), -1)
	var rid: int = xx * 10000 + lid if lid >= 0 else 0
	var fetter_id: String = str(entry.get("fetter_id", "")).strip_edges()
	if fetter_id == "":
		fetter_id = "titan_%s" % race
	return {
		"race": race,
		"label": str(entry.get("label", "")).strip_edges(),
		"icon": str(entry.get("icon", race)).strip_edges().to_lower(),
		"ship_id": rid,
		"fetter_id": fetter_id,
		"package": package_name,
		"ship_local_id": lid,
	}


static func validate_normalized_pick(norm: Dictionary, label: String, runtime_ships: Dictionary, runtime_fetters: Dictionary) -> PackedStringArray:
	var w: PackedStringArray = PackedStringArray()
	var rid: int = TypedVariant.as_int(norm.get("ship_id", 0), 0)
	if rid <= 0 or not runtime_ships.has(rid):
		w.append("%s: titan ship local_id %s not registered in this package" % [label, norm.get("ship_local_id")])
	else:
		var ship: Dictionary = TypedVariant.as_dict(runtime_ships[rid])
		if str(ship.get("ship_group", "")) != "titan":
			w.append("%s: titan_picks ship must have ship_group titan" % label)
	var fid: String = str(norm.get("fetter_id", ""))
	if fid != "" and not runtime_fetters.has(fid):
		w.append("%s: titan fetter '%s' missing — add fetters/%s.json" % [label, fid, fid])
	return w
