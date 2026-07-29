extends RefCounted
class_name UiAssets
## Resolve original Unity UI art by ship/fetter name (UTF-8 filenames).

const FONT_DISPLAY := "res://assets/fonts/SanJiLuoLiHei-2.ttf"
const FONT_BODY := "res://assets/fonts/msyh.ttc"
const MAIN_BG := "res://assets/ui/main_menu/MainMenuBG.jpg"
const ANNOUNCE_DIR := "res://assets/ui/main_menu/Announcements"
const CHAMPION_ICON_DIR := "res://assets/ui/sprites/ChampionIcons"
const CHAMPION_ICON_ASCII_MAP := "res://data/champion_icons.json"
const FETTER_ICON_DIR := "res://assets/ui/sprites/FetterIcons"
const SHOP_DIR := "res://assets/ui/ingame/Shop"
const SHOP_REFRESH_ASCII := "res://assets/ui/ingame/Shop/shop_refresh.png"
const SHOP_EXP_ASCII := "res://assets/ui/ingame/Shop/shop_exp.png"
const ICON_MONEY := "res://assets/ui/sprites/Money.png"
const ICON_POP := "res://assets/ui/sprites/Population.png"
const ICON_LOCK := "res://assets/ui/sprites/Lock.png"
const ICON_COIN := "res://assets/ui/sprites/coin 64.png"
const TERRAIN_DIFFUSE := "res://assets/textures/terrain diffuse.png"
const ENTITY_ICON_DIR := "E:/game_dev/icon_for_entity"
const ECHOES_ITEM_ICON_DIR := "H:/eve手游/history/asset_library/items/icons"
const TONNAGE_ICON_MAP := {
	"frigate": "frigate_32.png",
	"destroyer": "destroyer_32.png",
	"cruiser": "cruiser_32.png",
	"battlecruiser": "battleCruiser_32.png",
	"battleship": "battleship_32.png",
	"carrier": "carrier_32.png",
	"dreadnought": "dreadnought_32.png",
	"force_auxiliary": "force_auxiliary_32.png",
	"drone_light": "droneLightScout_16.png",
	"drone_medium": "droneMediumScout_16.png",
	"drone_heavy": "droneHeavyAttack_16.png",
	"fighter": "fighter.png",
	"heavy_repair_drone": "droneHeavyAttack_16.png",
	"repair_drone": "droneHeavyAttack_16.png",
}
const SHIPGROUP_ICON_DIR := "res://assets/ui/icons/ShipGroup"
const TONNAGE_DIR := "res://assets/ui/sprites/tonnage"

static var _champ_cache: Dictionary = {}
static var _champ_path_map: Dictionary = {}
static var _fetter_cache: Dictionary = {}
static var _tonnage_cache: Dictionary = {}
static var _item_icon_cache: Dictionary = {}
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
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res is Texture2D:
			return res as Texture2D
	# Fallback: Chinese / broken .import → load pixels via absolute path
	return _tex_from_image_file(path)

## Prefer ResourceLoader (works inside exported PCK). Raw Image.load is editor-only refresh aid.
static func tex_ship_bake(path: String) -> Texture2D:
	if path == "":
		return null
	var t := tex(path)
	if t != null:
		return t
	if OS.has_feature("editor"):
		return _tex_from_image_file(path)
	return null

static func _tex_from_image_file(path: String) -> Texture2D:
	var abs_path := path
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
	var img := Image.new()
	if img.load(abs_path) != OK:
		return null
	return ImageTexture.create_from_image(img)

static func body_font() -> Font:
	# Prefer TTF; many Godot builds mishandle .ttc collections → blank glyphs / gray UI.
	if _font_body == null:
		if ResourceLoader.exists(FONT_DISPLAY):
			_font_body = load(FONT_DISPLAY) as Font
		elif ResourceLoader.exists(FONT_BODY):
			_font_body = load(FONT_BODY) as Font
	return _font_body

static func display_font() -> Font:
	if _font_display == null:
		if ResourceLoader.exists(FONT_DISPLAY):
			_font_display = load(FONT_DISPLAY) as Font
		elif ResourceLoader.exists(FONT_BODY):
			_font_display = load(FONT_BODY) as Font
	return _font_display

static func apply_label_font(l: Label, display: bool = false, size: int = 18) -> void:
	var f := display_font() if display else body_font()
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)

static func apply_button_font(b: Button, size: int = 22) -> void:
	var f := display_font()
	if f == null:
		f = body_font()
	if f:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", size)

static func drone_portrait(drone_id: int) -> Texture2D:
	var cache_key := "drone#%d" % drone_id
	if _champ_cache.has(cache_key) and _champ_cache[cache_key] != null:
		return _champ_cache[cache_key]
	var t: Texture2D = null
	var data: Dictionary = DataStore.get_ship(drone_id) if DataStore else {}
	## Prefer explicit portrait (heavy repair / fighter icons live outside ship_portraits fallbacks).
	var portrait := str(data.get("portrait", ""))
	if portrait != "":
		t = tex(portrait)
		if t == null and OS.has_feature("editor"):
			t = _tex_from_image_file(portrait)
	if t == null:
		t = champion_icon(str(data.get("name", "")), drone_id)
	if t == null:
		var key := str(data.get("model_key", ""))
		if key != "":
			t = tex("res://assets/ui/portraits/%s.png" % key)
	if t == null:
		var kind := str(data.get("unmanned_kind", ""))
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
			var m: Dictionary = (portraits as Dictionary).get("ships", {})
			return str(m.get(str(ship_id), ""))
	# Last resort: read map from mounted content JSON.
	var path := "res://data/ship_portraits.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			var ships_map: Dictionary = (parsed as Dictionary).get("ships", {})
			return str(ships_map.get(str(ship_id), ""))
	return ""

static func champion_icon(ship_name: String, ship_id: int = 0) -> Texture2D:
	## Portraits only — Echoes ship_portraits; never ChampionIcons fallback.
	var cache_key := "%s#%d" % [ship_name, ship_id]
	if _champ_cache.has(cache_key) and _champ_cache[cache_key] != null:
		return _champ_cache[cache_key]
	var t: Texture2D = null
	if ship_id > 0:
		var ppath := _ship_portrait_path_safe(ship_id)
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
	var map_abs := ProjectSettings.globalize_path(CHAMPION_ICON_ASCII_MAP)
	if FileAccess.file_exists(map_abs):
		var f := FileAccess.open(map_abs, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_champ_path_map = parsed

## Resolve by fetter id ASCII `{id}.png` only (no Chinese filename fallback).
## Battlecruiser/battleship may fall back to tonnage icons.
static func fetter_icon(fetter_key: String, _display_name: String = "") -> Texture2D:
	var cache_key := fetter_key
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
	if t != null:
		_fetter_cache[cache_key] = t
	else:
		_fetter_cache.erase(cache_key)
	return t

## Short Chinese line for an active fetter effect dict (from JSON / recalculate_fetters).
static func fetter_effect_text(eff: Dictionary) -> String:
	if eff.is_empty():
		return ""
	var et := str(eff.get("effect_type", ""))
	var vt := str(eff.get("effect_value_type", ""))
	var val := float(eff.get("value", 0.0))
	var target := str(eff.get("effect_target", ""))
	var scope := ""
	match target:
		"SelfFetter":
			scope = "本羁绊"
		"SelfAll":
			scope = "全队"
		"SelfOne":
			scope = "单体"
		_:
			scope = ""
	var what := et
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
			what = "装甲回复"
		"ShieldResist":
			what = "盾抗"
		"ArmorResist":
			what = "甲抗"
	var amount := ""
	var signed := ("+" if val > 0.0 else "") + str(int(round(val)))
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
	var file_name := str(TONNAGE_ICON_MAP.get(ship_group, ""))
	if file_name == "":
		return null
	var t: Texture2D = null
	## Capitals use the same hollow outline sprites under tonnage/ (not solid ShipGroup art).
	if ship_group == "fighter":
		t = tex(FETTER_ICON_DIR.path_join(file_name))
		if t == null:
			t = _tex_from_image_file(FETTER_ICON_DIR.path_join(file_name))
	else:
		t = tex(TONNAGE_DIR.path_join(file_name))
		if t == null:
			t = _tex_from_image_file(TONNAGE_DIR.path_join(file_name))
		## Legacy ShipGroup fallback only if tonnage sprite missing.
		if t == null and ship_group in ["carrier", "dreadnought", "force_auxiliary"]:
			t = tex(SHIPGROUP_ICON_DIR.path_join(file_name))
			if t == null:
				t = _tex_from_image_file(SHIPGROUP_ICON_DIR.path_join(file_name))
	if t != null:
		_tonnage_cache[ship_group] = t
	return t

static func item_icon(type_id: int) -> Texture2D:
	if type_id <= 0:
		return null
	## Medium/large remote repair → small-tier art (same PNG family).
	var resolved := type_id
	match type_id:
		11357, 11359:
			resolved = 11355
		3596, 3606:
			resolved = 3586
		27930, 27904, 27932:
			resolved = 11355
	if _item_icon_cache.has(resolved) and _item_icon_cache[resolved] != null:
		return _item_icon_cache[resolved]
	var stem := str(resolved)
	var res_path := "res://assets/ui/item_icons".path_join(stem + ".png")
	## Prefer ResourceLoader (works in exported PCK); raw Image only as editor refresh aid.
	var t := tex(res_path)
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
	var dir := DirAccess.open(SHOP_DIR)
	if dir == null:
		return
	var files: PackedStringArray = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.get_extension().to_lower() == "png":
			files.append(fn)
		fn = dir.get_next()
	files.sort()
	if files.size() >= 1 and _shop_refresh == "":
		_shop_refresh = SHOP_DIR.path_join(files[0])
	if files.size() >= 2 and _shop_exp == "":
		_shop_exp = SHOP_DIR.path_join(files[1])
	for f in files:
		var stem := f.get_basename()
		if "刷新" in stem or "refresh" in stem.to_lower():
			_shop_refresh = SHOP_DIR.path_join(f)
		if "升" in stem or "級" in stem or "级" in stem or "exp" in stem.to_lower():
			_shop_exp = SHOP_DIR.path_join(f)

static func announcement_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var dir := DirAccess.open(ANNOUNCE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.get_extension().to_lower() in ["png", "jpg", "jpeg"]:
			var t := tex(ANNOUNCE_DIR.path_join(fn))
			if t:
				out.append(t)
		fn = dir.get_next()
	return out

static func qq_qr_texture() -> Texture2D:
	var ascii := "res://assets/ui/main_menu/dev_qq_group_qr.png"
	var t := tex(ascii)
	if t:
		return t
	t = _tex_from_image_file(ascii)
	if t:
		return t
	return null

static func _find_named_tex(dir_path: String, stem: String) -> Texture2D:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return null
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			var base := fn.get_basename()
			if base == stem:
				return tex(dir_path.path_join(fn))
		fn = dir.get_next()
	return null
