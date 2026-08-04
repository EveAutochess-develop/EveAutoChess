extends Control
## Eternal thin shell: version.json → manifest → download → load_resource_pack → main menu.

const DEFAULT_RESOLVE: String = "https://huggingface.co/buckets/liketocode789/eveautochess/resolve/"
const CACHE_DIR: String = "user://hotupdate/"

@onready var status_label: Label = $Margin/VBox/Status
@onready var progress: ProgressBar = $Margin/VBox/Progress
@onready var play_btn: Button = $Margin/VBox/PlayBtn
@onready var skip_btn: Button = $Margin/VBox/SkipBtn

var _base_url: String = DEFAULT_RESOLVE
var _entry: String = "res://scenes/main_menu.tscn"
var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.timeout = 8.0
	_style_boot()
	play_btn.disabled = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	# Editor / F5 preview: skip HF round-trip (often 2–10s+ and blocks Play).
	if OS.has_feature("editor") or FileAccess.file_exists("res://boot/skip_hotupdate"):
		_set_status("编辑器预览 · 内置内容（已跳过热更）")
		DataStore.content_version = "local-embedded"
		play_btn.disabled = false
		# Auto-jump so F5 lands on menu without an extra click.
		await get_tree().process_frame
		_on_skip()
		return
	_set_status("检查热更…")
	_start_update()

func _style_boot() -> void:
	var bg: ColorRect = get_node_or_null("ColorRect") as ColorRect
	# Keep an opaque fill so we never show the default gray clear color
	if bg:
		UiAssets.full_rect(bg)
		bg.color = Color(0.06, 0.08, 0.12, 1.0)
	var tex: Texture2D = UiAssets.tex(UiAssets.MAIN_BG)
	if tex:
		var bg_tex: TextureRect = TextureRect.new()
		bg_tex.name = "BG"
		UiAssets.full_rect(bg_tex)
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
		bg_tex.texture = tex
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_tex)
		move_child(bg_tex, 0)
		# Soft dim on top of photo, still opaque enough
		if bg:
			bg.color = Color(0.02, 0.03, 0.06, 0.55)
	var title: Label = get_node_or_null("Margin/VBox/Title") as Label
	if title:
		title.text = "星视寰宇EVE自走棋"
		UiAssets.apply_label_font(title, true, 32)
		title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.75))
	if status_label:
		UiAssets.apply_label_font(status_label, false, 16)
		status_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	if play_btn:
		UiAssets.apply_button_font(play_btn, 20)
	if skip_btn:
		UiAssets.apply_button_font(skip_btn, 16)

func _set_status(t: String) -> void:
	if status_label:
		status_label.text = t

func _start_update() -> void:
	var local_pointer: String = "res://boot/resolve_url.txt"
	if FileAccess.file_exists(local_pointer):
		_base_url = FileAccess.get_file_as_string(local_pointer).strip_edges()
		if not _base_url.ends_with("/"):
			_base_url += "/"
	var err: Error = _http.request(_base_url + "version.json")
	if err != OK:
		_set_status("无法请求 version.json，可跳过使用内置内容")
		play_btn.disabled = false
		return
	var result: Variant = await _http.request_completed
	if result is Array:
		var arr: Array = result
		_on_version(arr)

func _on_version(result: Array) -> void:
	var response_code: int = TypedVariant.as_int(result[1], 0)
	var body: PackedByteArray = result[3]
	if response_code != 200:
		_set_status("热更不可用 (%d)，使用内置内容" % response_code)
		play_btn.disabled = false
		return
	var data_v: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data_v) != TYPE_DICTIONARY:
		_set_status("version.json 无效")
		play_btn.disabled = false
		return
	var data: Dictionary = data_v
	if data.has("baseUrl"):
		_base_url = str(data["baseUrl"])
		if not _base_url.ends_with("/"):
			_base_url += "/"
	if data.has("entry"):
		_entry = str(data["entry"])
	# Prefer local scenes path if entry points to old path
	if _entry == "res://game/main.tscn":
		_entry = "res://scenes/main_menu.tscn"
	DataStore.content_version = str(data.get("version", "unknown"))
	GameSession.shell_version = str(ProjectSettings.get_setting("application/config/version", "1.0.0-shell"))
	_set_status("拉取 manifest %s…" % DataStore.content_version)
	_http.request(_base_url + "manifest.json")
	var man_v: Variant = await _http.request_completed
	if man_v is Array:
		var man: Array = man_v
		_on_manifest(man)

func _on_manifest(result: Array) -> void:
	var response_code: int = TypedVariant.as_int(result[1], 0)
	var body: PackedByteArray = result[3]
	if response_code != 200:
		_set_status("manifest 失败，使用内置")
		play_btn.disabled = false
		return
	var data_v: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data_v) != TYPE_DICTIONARY:
		play_btn.disabled = false
		return
	var data: Dictionary = data_v
	var files_v: Variant = data.get("files", [])
	if typeof(files_v) != TYPE_ARRAY:
		_set_status("manifest 空，使用内置内容")
		play_btn.disabled = false
		return
	var files: Array = files_v
	if files.is_empty():
		_set_status("manifest 空，使用内置内容")
		play_btn.disabled = false
		return
	var i: int = 0
	for f_v: Variant in files:
		if typeof(f_v) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_v
		var path: String = str(f.get("path", ""))
		if path.is_empty():
			continue
		i += 1
		progress.value = float(i) / float(files.size()) * 100.0
		_set_status("下载 %s" % path)
		var ok: bool = await _download_file(path, str(f.get("sha256", "")))
		if not ok:
			_set_status("下载失败: %s（可跳过）" % path)
			play_btn.disabled = false
			return
		if path.ends_with(".pck"):
			var local: String = CACHE_DIR + path.get_file()
			var abs_path: String = ProjectSettings.globalize_path(local)
			if FileAccess.file_exists(local):
				var mounted: bool = ProjectSettings.load_resource_pack(abs_path)
				_set_status("挂载 %s → %s" % [path, str(mounted)])
	DataStore.reload_all()
	_set_status("热更完成 · %s" % DataStore.content_version)
	play_btn.disabled = false

func _download_file(rel: String, expect_sha: String) -> bool:
	var url: String = _base_url + rel
	var local: String = CACHE_DIR + rel.get_file()
	_http.request(url)
	var result_v: Variant = await _http.request_completed
	if not (result_v is Array):
		return false
	var result: Array = result_v
	var code: int = TypedVariant.as_int(result[1], 0)
	var body: PackedByteArray = result[3]
	if code != 200:
		return false
	if expect_sha != "":
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(body)
		var digest: PackedByteArray = ctx.finish()
		var h: String = digest.hex_encode()
		if h != expect_sha:
			push_warning("sha mismatch %s got %s expect %s" % [rel, h, expect_sha])
	var f: FileAccess = FileAccess.open(local, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(body)
	f.close()
	return true

func _on_play() -> void:
	get_tree().change_scene_to_file(_entry)

func _on_skip() -> void:
	DataStore.content_version = "local-embedded"
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
