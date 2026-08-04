extends SceneTree
## Headless smoke: parse key scripts, seed/scan ships+equipment JSON, load entry scenes.
## Usage:
##   Godot --headless --path godot_project -s res://tools/smoke_early_errors.gd
## Exit 0 = ok; non-zero = fail early (not Unity-complete, but catches parse/entry/bad JSON).

const ENTRY_SCENES: PackedStringArray = [
	"res://scenes/main_menu.tscn",
]
const PARSE_GLOBS: PackedStringArray = [
	"res://scripts/core",
	"res://scripts/ui",
	"res://scripts/boot",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: PackedStringArray = []
	print("[smoke] start")
	_parse_script_trees(errors)
	_check_data_json(errors)
	_load_entries(errors)
	if errors.is_empty():
		print("[smoke] OK")
		quit(0)
		return
	for e in errors:
		push_error("[smoke] %s" % e)
		print("[smoke] FAIL: %s" % e)
	quit(1)


func _parse_script_trees(errors: PackedStringArray) -> void:
	for root in PARSE_GLOBS:
		_parse_dir(root, errors)


func _parse_dir(dir_path: String, errors: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		var full := dir_path.path_join(fn)
		if dir.current_is_dir():
			if fn != "." and fn != "..":
				_parse_dir(full, errors)
		elif fn.ends_with(".gd"):
			var scr: Resource = ResourceLoader.load(full, "", ResourceLoader.CACHE_MODE_IGNORE)
			if scr == null:
				errors.append("cannot load script %s" % full)
			elif scr is GDScript:
				var gds := scr as GDScript
				if not gds.can_instantiate() and gds.get_instance_base_type() != "":
					## Abstract / tool-only still counts as parsed if load succeeded.
					pass
				var src := gds.source_code
				if src.is_empty() and FileAccess.file_exists(full):
					errors.append("empty GDScript %s" % full)
		fn = dir.get_next()
	dir.list_dir_end()


func _check_data_json(errors: PackedStringArray) -> void:
	for sub in ["ships", "equipment"]:
		var dpath := "res://data".path_join(sub)
		var dir := DirAccess.open(dpath)
		if dir == null:
			errors.append("missing data dir %s" % dpath)
			continue
		var count := 0
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.ends_with(".json"):
				count += 1
				var full := dpath.path_join(fn)
				var text := FileAccess.get_file_as_string(full)
				var parsed = JSON.parse_string(text)
				if parsed == null:
					errors.append("bad JSON %s" % full)
			fn = dir.get_next()
		dir.list_dir_end()
		if count < 1:
			errors.append("no JSON in %s" % dpath)


func _load_entries(errors: PackedStringArray) -> void:
	for path in ENTRY_SCENES:
		if not ResourceLoader.exists(path):
			errors.append("missing entry %s" % path)
			continue
		var packed = ResourceLoader.load(path)
		if packed == null:
			errors.append("cannot load entry %s" % path)
