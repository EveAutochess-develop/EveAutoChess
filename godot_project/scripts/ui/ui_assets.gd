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

static var _champ_cache: Dictionary = {}
static var _champ_path_map: Dictionary = {}
static var _fetter_cache: Dictionary = {}
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

## Prefer raw ImageTexture for hull bakes on desktop (avoids mid-reimport CompressedTexture2D blanks).
## On mobile, res:// cannot be Image.load()'d via globalize_path — use ResourceLoader only.
static func tex_ship_bake(path: String) -> Texture2D:
	if path == "":
		return null
	var mobile := OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"
	if mobile:
		return tex(path)
	var img_tex := _tex_from_image_file(path)
	if img_tex:
		return img_tex
	return tex(path)

static func _tex_from_image_file(path: String) -> Texture2D:
	var abs_path := ProjectSettings.globalize_path(path)
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

static func champion_icon(ship_name: String) -> Texture2D:
	if _champ_cache.has(ship_name):
		return _champ_cache[ship_name]
	_ensure_champ_map()
	var t: Texture2D = null
	# Prefer ASCII copies — Chinese path .import often stays valid=false on Windows
	if _champ_path_map.has(ship_name):
		t = tex(str(_champ_path_map[ship_name]))
	if t == null:
		t = _find_named_tex(CHAMPION_ICON_DIR, ship_name)
	_champ_cache[ship_name] = t
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

static func fetter_icon(fetter_name: String) -> Texture2D:
	if _fetter_cache.has(fetter_name):
		return _fetter_cache[fetter_name]
	var t := _find_named_tex(FETTER_ICON_DIR, fetter_name)
	_fetter_cache[fetter_name] = t
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
	var dir := DirAccess.open("res://assets/ui/main_menu")
	if dir == null:
		return null
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.get_extension().to_lower() == "png" and ("二维码" in fn or "qq" in fn.to_lower() or fn.length() > 20):
			var t := tex("res://assets/ui/main_menu".path_join(fn))
			if t:
				return t
		fn = dir.get_next()
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
