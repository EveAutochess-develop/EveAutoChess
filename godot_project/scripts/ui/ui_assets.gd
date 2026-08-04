extends RefCounted
class_name UiAssets
## Resolve original Unity UI art by ship/fetter name (UTF-8 filenames).

const FONT_DISPLAY: String = "res://assets/fonts/SanJiLuoLiHei-2.ttf"
const FONT_BODY: String = "res://assets/fonts/msyh.ttc"
const MAIN_BG: String = "res://assets/ui/main_menu/MainMenuBG.jpg"
const ANNOUNCE_DIR: String = "res://assets/ui/main_menu/Announcements"
## Explicit list — DirAccess on exported PCK often yields .ctex / empty, so scan-by-extension fails on mobile.
const ANNOUNCE_FILES: PackedStringArray = [
	"afdian.png",
	"bug_feedback.png",
	"github_open_source.png",
	"sponsor.png",
	"survey.png",
	"update.png",
]
const CHAMPION_ICON_DIR: String = "res://assets/ui/sprites/ChampionIcons"
const CHAMPION_ICON_ASCII_MAP: String = "res://data/champion_icons.json"
const FETTER_ICON_DIR: String = "res://assets/ui/sprites/FetterIcons"
const SHOP_DIR: String = "res://assets/ui/ingame/Shop"
const SHOP_REFRESH_ASCII: String = "res://assets/ui/ingame/Shop/shop_refresh.png"
const SHOP_EXP_ASCII: String = "res://assets/ui/ingame/Shop/shop_exp.png"
const ICON_MONEY: String = "res://assets/ui/sprites/Money.png"
const ICON_POP: String = "res://assets/ui/sprites/Population.png"
const ICON_LOCK: String = "res://assets/ui/sprites/Lock.png"
const ICON_COIN: String = "res://assets/ui/sprites/coin 64.png"
const TERRAIN_DIFFUSE: String = "res://assets/textures/terrain diffuse.png"
const ENTITY_ICON_DIR: String = "E:/game_dev/icon_for_entity"
const ECHOES_ITEM_ICON_DIR: String = "H:/eve手游/history/asset_library/items/icons"
const TONNAGE_ICON_MAP: Dictionary = {
	"frigate": "frigate_32.png",
	"destroyer": "destroyer_32.png",
	"cruiser": "cruiser_32.png",
	"battlecruiser": "battleCruiser_32.png",
	"battleship": "battleship_32.png",
	"carrier": "carrier_32.png",
	"dreadnought": "dreadnought_32.png",
	"force_auxiliary": "force_auxiliary_32.png",
	"drone_light": "droneAttack_16.png",
	"drone_medium": "droneAttack_16.png",
	"drone_heavy": "droneAttack_16.png",
	"fighter": "fighterSquad_16.png",
	"mining_drone": "droneMining_M_16.png",
	"heavy_repair_drone": "droneAttack_16.png",
	"repair_drone": "droneAttack_16.png",
	"mining_barge": "industrial_32.png",
	"industrial_command": "industrialCommand_32.png",
	"capital_industrial": "freighter_32.png",
	"freighter": "freighter_32.png",
	"titan": "titan_32.png",
}
const SHIPGROUP_ICON_DIR: String = "res://assets/ui/icons/ShipGroup"
const TONNAGE_DIR: String = "res://assets/ui/sprites/tonnage"
const TONNAGE_OVERLAY_DIR: String = "res://assets/ui/sprites/tonnage_overlays"
const EQUIPMENT_SIZE_BADGE_DIR: String = "res://assets/ui/sprites/equipment_size_badges"
## In-match tonnage overlays (UI_ICONS §6.1): one bg + one badge per unit, picked by viewer-side allegiance.
const TONNAGE_OVERLAY_FILES: Dictionary = {
	"red_minus_badge": "01_red_minus_badge.png",
	"red_bg": "02_red_bg.png",
	"fleet_member": "03_fleet_member.png",
	"fleet_member_bg": "04_fleet_member_bg.png",
	"blue_bg": "05_blue_bg.png",
	"friendly_badge": "06_friendly_badge.png",
}
## key = allegiance set from the local client's point of view.
const TONNAGE_OVERLAY_SETS: Dictionary = {
	"fleet": {"bg": "fleet_member_bg", "badge": "fleet_member"},
	"enemy": {"bg": "red_bg", "badge": "red_minus_badge"},
	"friendly": {"bg": "blue_bg", "badge": "friendly_badge"},
}
const TIPS_SKYBOX_DIR: String = "res://assets/ui/tips_skybox"
const INDUSTRIAL_SHIP_GROUPS: Array = [
	"mining_barge",
	"industrial_command",
	"capital_industrial",
]
const RACE_TIPS_FILES: Dictionary = {
	"amarr": "tips_a01_pic.png",
	"a": "tips_a01_pic.png",
	"caldari": "tips_c01_pic.png",
	"c": "tips_c01_pic.png",
	"gallente": "tips_g01_pic.png",
	"g": "tips_g01_pic.png",
	"minmatar": "tips_m01_pic.png",
	"m": "tips_m01_pic.png",
}
const ORE_TIPS_FILES: Dictionary = {
	"amarr": "tips_ore_a01_pic.png",
	"a": "tips_ore_a01_pic.png",
	"caldari": "tips_ore_c01_pic.png",
	"c": "tips_ore_c01_pic.png",
	"gallente": "tips_ore_g01_pic.png",
	"g": "tips_ore_g01_pic.png",
	"minmatar": "tips_ore_m01.png",
	"m": "tips_ore_m01.png",
}

static var _champ_cache: Dictionary = {}
static var _champ_path_map: Dictionary = {}
static var _fetter_cache: Dictionary = {}
static var _tonnage_cache: Dictionary = {}
static var _item_icon_cache: Dictionary = {}
static var _tips_cache: Dictionary = {}
static var _font_display: Font
static var _font_body: Font
static var _shop_refresh: String = ""
static var _shop_exp: String = ""

static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH

static func top_left_box(c: Control, left: float, top: float, width: float, height: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = left
	c.offset_top = top
	c.offset_right = left + width
	c.offset_bottom = top + height

static func bottom_right_box(c: Control, right_margin: float, bottom_margin: float, width: float, height: float) -> void:
	c.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	c.anchor_left = 1.0
	c.anchor_top = 1.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -right_margin - width
	c.offset_top = -bottom_margin - height
	c.offset_right = -right_margin
	c.offset_bottom = -bottom_margin

static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		# REPLACE so rebaked PNGs are not stuck on a stale import/cache.
		var res: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res is Texture2D:
			@warning_ignore("unsafe_cast")
			return res as Texture2D
	# Fallback: Chinese / broken .import → load pixels via absolute path
	return _tex_from_image_file(path)

## Prefer ResourceLoader (works inside exported PCK). Raw Image.load is editor-only refresh aid.
static func tex_ship_bake(path: String) -> Texture2D:
	if path == "":
		return null
	var t: Texture2D = tex(path)
	if t != null:
		return t
	if OS.has_feature("editor"):
		return _tex_from_image_file(path)
	return null

static func _tex_from_image_file(path: String) -> Texture2D:
	var abs_path: String = path
	# res:// is NOT a real filesystem path; globalize it so FileAccess + Image.load work
	# even when PNGs were just written and .import is not settled yet.
	if path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	# Windows absolute path: C:\xxx or C:/xxx
	elif path.length() >= 3 and path[1] == ":" and (path[2] == "\\" or path[2] == "/"):
		abs_path = path
	elif not (path.contains(":/") or path.begins_with("/") or path.begins_with("\\") ):
		abs_path = ProjectSettings.globalize_path(path)
	if abs_path == "" or not FileAccess.file_exists(abs_path):
		return null
	var img: Image = Image.new()
	if img.load(abs_path) != OK:
		return null
	return ImageTexture.create_from_image(img)

static func body_font() -> Font:
	# Prefer TTF; many Godot builds mishandle .ttc collections → blank glyphs / gray UI.
	if _font_body == null:
		if ResourceLoader.exists(FONT_DISPLAY):
			var loaded: Variant = load(FONT_DISPLAY)
			if loaded is Font:
				@warning_ignore("unsafe_cast")
				_font_body = loaded as Font
		elif ResourceLoader.exists(FONT_BODY):
			var loaded: Variant = load(FONT_BODY)
			if loaded is Font:
				@warning_ignore("unsafe_cast")
				_font_body = loaded as Font
	return _font_body

static func display_font() -> Font:
	if _font_display == null:
		if ResourceLoader.exists(FONT_DISPLAY):
			var loaded: Variant = load(FONT_DISPLAY)
			if loaded is Font:
				@warning_ignore("unsafe_cast")
				_font_display = loaded as Font
		elif ResourceLoader.exists(FONT_BODY):
			var loaded: Variant = load(FONT_BODY)
			if loaded is Font:
				@warning_ignore("unsafe_cast")
				_font_display = loaded as Font
	return _font_display

static func apply_label_font(l: Label, display: bool = false, size: int = 18) -> void:
	var f: Font = display_font() if display else body_font()
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)

static func apply_button_font(b: Button, size: int = 22) -> void:
	var f: Font = display_font()
	if f == null:
		f = body_font()
	if f:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", size)

static func drone_portrait(drone_id: int) -> Texture2D:
	var cache_key: String = "drone#%d" % drone_id
	if _champ_cache.has(cache_key) and _champ_cache[cache_key] != null:
		return _champ_cache[cache_key]
	var t: Texture2D = null
	var data: Dictionary = DataStore.get_ship(drone_id) if DataStore else {}
	## Prefer explicit portrait (heavy repair / fighter icons live outside ship_portraits fallbacks).
	var portrait: String = str(data.get("portrait", ""))
	if portrait != "":
		t = tex(portrait)
		if t == null and OS.has_feature("editor"):
			t = _tex_from_image_file(portrait)
	if t == null:
		t = champion_icon(str(data.get("name", "")), drone_id)
	if t == null:
		var key: String = str(data.get("model_key", ""))
		if key != "":
			t = tex("res://assets/ui/portraits/%s.png" % key)
	if t == null:
		var kind: String = str(data.get("unmanned_kind", ""))
		if kind == "heavy_repair_drone":
			t = tex("res://assets/ui/heavy_repair_drone_icons/%s.png" % str(data.get("model_key", "heavy_repair_amarr")))
		elif kind.find("heavy") >= 0:
			t = tonnage_icon("drone_heavy")
		else:
			t = tonnage_icon("drone_light")
	if t != null:
		_champ_cache[cache_key] = t
	else:
		_champ_cache.erase(cache_key)
	return t

## Shell Autoload DataStore may lag content; never hard-crash on missing APIs.
static func _ship_portrait_path_safe(ship_id: int) -> String:
	if DataStore != null and DataStore.has_method("ship_portrait_path"):
		return str(DataStore.ship_portrait_path(ship_id))
	if DataStore != null:
		var portraits: Variant = DataStore.get("ship_portraits")
		if typeof(portraits) == TYPE_DICTIONARY:
			var portraits_dict: Dictionary = TypedVariant.as_dict(portraits)
			var m: Dictionary = TypedVariant.as_dict(portraits_dict.get("ships", {}))
			return str(m.get(str(ship_id), ""))
	# Last resort: read map from mounted content JSON.
	var path: String = "res://data/ship_portraits.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			var root: Dictionary = TypedVariant.as_dict(parsed)
			var ships_map: Dictionary = TypedVariant.as_dict(root.get("ships", {}))
			return str(ships_map.get(str(ship_id), ""))
	return ""

static func champion_icon(ship_name: String, ship_id: int = 0) -> Texture2D:
	## Portraits only — Echoes ship_portraits; never ChampionIcons fallback.
	var cache_key: String = "%s#%d" % [ship_name, ship_id]
	if _champ_cache.has(cache_key) and _champ_cache[cache_key] != null:
		return _champ_cache[cache_key]
	var t: Texture2D = null
	if ship_id > 0:
		var ppath: String = _ship_portrait_path_safe(ship_id)
		if ppath != "":
			# Exported PCK: ResourceLoader first. Raw Image.load only helps editor reimports.
			t = tex(ppath)
			if t == null and OS.has_feature("editor"):
				t = _tex_from_image_file(ppath)
	if t != null:
		_champ_cache[cache_key] = t
	else:
		_champ_cache.erase(cache_key)
	return t

static func _ensure_champ_map() -> void:
	if not _champ_path_map.is_empty():
		return
	var map_abs: String = ProjectSettings.globalize_path(CHAMPION_ICON_ASCII_MAP)
	if FileAccess.file_exists(map_abs):
		var f: FileAccess = FileAccess.open(map_abs, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_champ_path_map = TypedVariant.as_dict(parsed)

## UI_AND_SHELL §2.1.1 / UI_ICONS §8 — four-empire tips skybox (battle ships / titan options).
static func race_tips_skybox(race_key: String) -> Texture2D:
	var k: String = _normalize_race_key(race_key)
	if k == "":
		return null
	var cache_key: String = "race:%s" % k
	if _tips_cache.has(cache_key):
		return _tips_cache[cache_key]
	var file_name: String = str(RACE_TIPS_FILES.get(k, ""))
	var t: Texture2D = null
	if file_name != "":
		t = tex(TIPS_SKYBOX_DIR.path_join(file_name))
		if t == null:
			t = _tex_from_image_file(TIPS_SKYBOX_DIR.path_join(file_name))
	_tips_cache[cache_key] = t
	return t

## Industrial / mining shop cards — tips_ore_* (never silent-fallback to empire tips).
static func ore_tips_skybox(variant_key: String) -> Texture2D:
	var k: String = _normalize_race_key(variant_key)
	if k == "":
		k = "m"
	var cache_key: String = "ore:%s" % k
	if _tips_cache.has(cache_key):
		return _tips_cache[cache_key]
	var file_name: String = str(ORE_TIPS_FILES.get(k, ORE_TIPS_FILES["m"]))
	var t: Texture2D = null
	if file_name != "":
		t = tex(TIPS_SKYBOX_DIR.path_join(file_name))
		if t == null:
			t = _tex_from_image_file(TIPS_SKYBOX_DIR.path_join(file_name))
	_tips_cache[cache_key] = t
	return t

## Pick the correct tips texture for a shop ship card (or null = keep plain card).
static func shop_card_tips_skybox(ship: Dictionary, titan_race: String = "") -> Texture2D:
	if ship == null or ship.is_empty():
		return null
	var group: String = str(ship.get("ship_group", ""))
	var groups: Array = TypedVariant.as_array(ship.get("ship_groups", []))
	var is_industrial: bool = group in INDUSTRIAL_SHIP_GROUPS
	if not is_industrial:
		for g: Variant in groups:
			if str(g) in INDUSTRIAL_SHIP_GROUPS:
				is_industrial = true
				break
	if is_industrial:
		var ore_key: String = _normalize_race_key(str(ship.get("race", "")))
		if ore_key == "":
			ore_key = _normalize_race_key(titan_race)
		if ore_key == "":
			ore_key = "m"
		return ore_tips_skybox(ore_key)
	var race: String = _normalize_race_key(str(ship.get("race", "")))
	if race == "":
		return null
	return race_tips_skybox(race)

static func _normalize_race_key(raw: String) -> String:
	var k: String = raw.strip_edges().to_lower()
	match k:
		"amarr", "a", "am":
			return "amarr"
		"caldari", "c", "cald", "jdl":
			return "caldari"
		"gallente", "g", "gal", "glt":
			return "gallente"
		"minmatar", "m", "min", "mmte":
			return "minmatar"
		_:
			return ""

## Resolve by fetter id ASCII `{id}.png` only (no Chinese filename fallback).
## Battlecruiser/battleship may fall back to tonnage icons.
static func fetter_icon(fetter_key: String, _display_name: String = "") -> Texture2D:
	var cache_key: String = fetter_key
	if _fetter_cache.has(cache_key) and _fetter_cache[cache_key] != null:
		return _fetter_cache[cache_key]
	var t: Texture2D = null
	if fetter_key != "":
		t = tex(FETTER_ICON_DIR.path_join(fetter_key + ".png"))
		if t == null:
			t = _find_named_tex(FETTER_ICON_DIR, fetter_key)
		if t == null and fetter_key in ["battlecruiser", "battleship"]:
			t = tonnage_icon(fetter_key)
		if t == null and fetter_key == "fighter":
			t = tex(FETTER_ICON_DIR.path_join("fighter.png"))
		## Titan meta fetter borrows the race icon (UI_ICONS §8.5).
		if t == null and fetter_key.begins_with("titan_"):
			t = tex("res://assets/ui/race_icons/%s.png" % fetter_key.substr(6))
	if t != null:
		_fetter_cache[cache_key] = t
	else:
		_fetter_cache.erase(cache_key)
	return t

## Short Chinese line for an active fetter effect dict (from JSON / recalculate_fetters).
static func fetter_effect_text(eff: Dictionary) -> String:
	if eff.is_empty():
		return ""
	var et: String = str(eff.get("effect_type", ""))
	var vt: String = str(eff.get("effect_value_type", ""))
	var val: float = TypedVariant.as_float(eff.get("value", 0.0), 0.0)
	var target: String = str(eff.get("effect_target", ""))
	var scope: String = ""
	match target:
		"SelfFetter":
			scope = "本羁绊"
		"SelfAll":
			scope = "全队"
		"SelfOne":
			scope = "单体"
		_:
			scope = ""
	var signed: String = ("+" if val > 0.0 else "") + str(roundi(val))
	var what: String = et
	match et:
		"Damage":
			what = "伤害"
		"ArmorHP":
			what = "装甲"
		"ShieldHP":
			what = "护盾"
		"FlatHP":
			what = "HP"
		"AttackSpeed":
			what = "攻速"
		"Speed":
			what = "移速"
		"ArmorHeal", "RemoteRepair", "Repair":
			## Logistic heal amount (fetter_repair_mul) — not passive armor regen.
			what = "后勤维修量"
		"ShieldResist":
			what = "盾抗"
		"ArmorResist":
			what = "甲抗"
		"ShopRaceWeight":
			## Titan meta only — not a combat mul; sidebar copy (FETTERS §4.2).
			return "本族商店刷新%s%%" % signed
	var amount: String = ""
	if vt == "Percentage":
		amount = signed + "%"
	elif vt == "Multiplier":
		amount = "×%.2f" % val
	else:
		amount = signed
	if scope != "":
		return "%s%s%s" % [scope, what, amount]
	return "%s%s" % [what, amount]

static func tonnage_icon(ship_group: String) -> Texture2D:
	if _tonnage_cache.has(ship_group):
		return _tonnage_cache[ship_group]
	var file_name: String = str(TONNAGE_ICON_MAP.get(ship_group, ""))
	if file_name == "":
		return null
	var t: Texture2D = null
	## Capitals / drones / fighter use hollow outline sprites under tonnage/.
	t = tex(TONNAGE_DIR.path_join(file_name))
	if t == null:
		t = _tex_from_image_file(TONNAGE_DIR.path_join(file_name))
	## Fighter legacy: FetterIcons/fighter.png if tonnage sprite missing.
	if t == null and ship_group == "fighter":
		t = tex(FETTER_ICON_DIR.path_join("fighter.png"))
		if t == null:
			t = _tex_from_image_file(FETTER_ICON_DIR.path_join("fighter.png"))
	## Legacy ShipGroup fallback only if tonnage sprite missing.
	if t == null and ship_group in ["carrier", "dreadnought", "force_auxiliary", "titan"]:
		var sg_name: String = file_name
		if ship_group == "titan":
			sg_name = "Titan.png"
		t = tex(SHIPGROUP_ICON_DIR.path_join(sg_name))
		if t == null:
			t = _tex_from_image_file(SHIPGROUP_ICON_DIR.path_join(sg_name))
		if t == null and ship_group == "titan":
			t = tex(SHIPGROUP_ICON_DIR.path_join("Titan.png"))
			if t == null:
				t = _tex_from_image_file(SHIPGROUP_ICON_DIR.path_join("Titan.png"))
	if t != null:
		_tonnage_cache[ship_group] = t
	return t

## Overlay art for the in-match tonnage icon. `key` = TONNAGE_OVERLAY_FILES key.
static func tonnage_overlay(key: String) -> Texture2D:
	if key == "":
		return null
	var cache_key: String = "ovl:%s" % key
	if _tonnage_cache.has(cache_key):
		return _tonnage_cache[cache_key]
	var file_name: String = str(TONNAGE_OVERLAY_FILES.get(key, ""))
	if file_name == "":
		return null
	var t: Texture2D = tex(TONNAGE_OVERLAY_DIR.path_join(file_name))
	if t == null:
		t = _tex_from_image_file(TONNAGE_OVERLAY_DIR.path_join(file_name))
	if t != null:
		_tonnage_cache[cache_key] = t
	return t

## Both layers of one allegiance set → {"bg": Texture2D|null, "badge": Texture2D|null}.
static func tonnage_overlay_set(set_key: String) -> Dictionary:
	var conf: Dictionary = TypedVariant.as_dict(TONNAGE_OVERLAY_SETS.get(set_key, {}))
	if conf.is_empty():
		return {"bg": null, "badge": null}
	return {
		"bg": tonnage_overlay(str(conf.get("bg", ""))),
		"badge": tonnage_overlay(str(conf.get("badge", ""))),
	}

static func item_icon(type_id: int) -> Texture2D:
	if type_id <= 0:
		return null
	## Medium/large remote repair → small-tier art (same PNG family).
	var resolved: int = type_id
	match type_id:
		11357, 11359:
			resolved = 11355
		3596, 3606:
			resolved = 3586
		27930, 27904, 27932:
			resolved = 11355
	if _item_icon_cache.has(resolved) and _item_icon_cache[resolved] != null:
		return _item_icon_cache[resolved]
	var stem: String = str(resolved)
	var res_path: String = "res://assets/ui/item_icons".path_join(stem + ".png")
	## Prefer ResourceLoader (works in exported PCK); raw Image only as editor refresh aid.
	var t: Texture2D = tex(res_path)
	if t == null:
		t = _tex_from_image_file(res_path)
	# Dev-only Echoes unpack fallback — never required for shipped builds.
	if t == null and OS.has_feature("editor"):
		t = _tex_from_image_file(ECHOES_ITEM_ICON_DIR.path_join(stem + ".ktx"))
		if t == null:
			t = _tex_from_image_file(ECHOES_ITEM_ICON_DIR.path_join(stem + ".png"))
	if t != null:
		_item_icon_cache[resolved] = t
		_item_icon_cache[type_id] = t
	else:
		_item_icon_cache.erase(resolved)
		_item_icon_cache.erase(type_id)
	return t

static func equipment_size_badge(size_key: String) -> Texture2D:
	var key: String = size_key.strip_edges().to_lower()
	match key:
		"small", "s":
			key = "s"
		"medium", "m":
			key = "m"
		"large", "l":
			key = "l"
		"capital", "xl", "x-large", "x_large":
			key = "xl"
		_:
			if key == "":
				return null
	var path: String = EQUIPMENT_SIZE_BADGE_DIR.path_join("size_%s.png" % key)
	return tex(path)


static func function_module_icon(mod: Dictionary) -> Texture2D:
	if mod.is_empty():
		return null
	var icon_path: String = str(mod.get("icon", ""))
	if icon_path != "":
		var from_path: Texture2D = tex(icon_path)
		if from_path:
			return from_path
	return item_icon(TypedVariant.as_int(mod.get("typeID", 0), 0))

static func shop_refresh_path() -> String:
	_ensure_shop_paths()
	return _shop_refresh

static func shop_exp_path() -> String:
	_ensure_shop_paths()
	return _shop_exp

static func _ensure_shop_paths() -> void:
	if _shop_refresh != "":
		return
	# Prefer ASCII paths — Chinese filenames often break on Android PCK / DirAccess.
	if ResourceLoader.exists(SHOP_REFRESH_ASCII):
		_shop_refresh = SHOP_REFRESH_ASCII
	if ResourceLoader.exists(SHOP_EXP_ASCII):
		_shop_exp = SHOP_EXP_ASCII
	if _shop_refresh != "" and _shop_exp != "":
		return
	var dir: DirAccess = DirAccess.open(SHOP_DIR)
	if dir == null:
		return
	var files: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.get_extension().to_lower() == "png":
			files.append(fn)
		fn = dir.get_next()
	files.sort()
	if files.size() >= 1 and _shop_refresh == "":
		_shop_refresh = SHOP_DIR.path_join(files[0])
	if files.size() >= 2 and _shop_exp == "":
		_shop_exp = SHOP_DIR.path_join(files[1])
	for f: String in files:
		var stem: String = f.get_basename()
		if "刷新" in stem or "refresh" in stem.to_lower():
			_shop_refresh = SHOP_DIR.path_join(f)
		if "升" in stem or "級" in stem or "级" in stem or "exp" in stem.to_lower():
			_shop_exp = SHOP_DIR.path_join(f)

static func announcement_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for fn: String in ANNOUNCE_FILES:
		var t: Texture2D = tex(ANNOUNCE_DIR.path_join(fn))
		if t == null:
			t = _tex_from_image_file(ANNOUNCE_DIR.path_join(fn))
		if t:
			out.append(t)
	if out.is_empty():
		## Editor-only fallback if new files were added without updating ANNOUNCE_FILES.
		var dir: DirAccess = DirAccess.open(ANNOUNCE_DIR)
		if dir != null:
			dir.list_dir_begin()
			var scan: String = dir.get_next()
			while scan != "":
				if not dir.current_is_dir() and scan.get_extension().to_lower() in ["png", "jpg", "jpeg"]:
					var t2: Texture2D = tex(ANNOUNCE_DIR.path_join(scan))
					if t2:
						out.append(t2)
				scan = dir.get_next()
	return out

static func qq_qr_texture() -> Texture2D:
	var ascii: String = "res://assets/ui/main_menu/dev_qq_group_qr.png"
	var t: Texture2D = tex(ascii)
	if t:
		return t
	t = _tex_from_image_file(ascii)
	if t:
		return t
	return null

static func _find_named_tex(dir_path: String, stem: String) -> Texture2D:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return null
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			var base: String = fn.get_basename()
			if base == stem:
				return tex(dir_path.path_join(fn))
		fn = dir.get_next()
	return null
