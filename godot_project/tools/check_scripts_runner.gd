extends SceneTree
## Project-aware GDScript gate: Autoloads are live, then reload listed scripts.
## Env:
##   EVEAC_CHECK_SCRIPTS = semicolon-separated res:// paths (empty = all under res://scripts)
## Prints per-file blocks; exit 1 if any attributed failure.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw: String = OS.get_environment("EVEAC_CHECK_SCRIPTS").strip_edges()
	var paths: PackedStringArray = PackedStringArray()
	if raw.is_empty():
		paths = _collect_scripts("res://scripts")
	else:
		for part: String in raw.split(";"):
			var s: String = part.strip_edges()
			if not s.is_empty():
				paths.append(s)
	var failed: int = 0
	var checked: int = 0
	print("=== eveac_check_runner: scripts=%d ===" % paths.size())
	for path: String in paths:
		checked += 1
		if not _check_one(path):
			failed += 1
	print("=== eveac_check_runner RESULT checked=%d failed=%d ===" % [checked, failed])
	quit(1 if failed > 0 else 0)


func _check_one(path: String) -> bool:
	if not FileAccess.file_exists(path):
		print("=== FAIL %s ===" % path)
		print("missing resource")
		print("=== END %s ===" % path)
		return false
	## Ensure common class_name helpers are in the global class DB before isolated compile.
	_ensure_global_helpers()
	## Never GDScript.reload() the live Autoload resource — instances block reload.
	## Fresh script + source_code compiles against the project class DB (Autoloads already loaded).
	var src: String = FileAccess.get_file_as_string(path)
	if src.is_empty() and FileAccess.get_size(path) > 0:
		print("=== FAIL %s ===" % path)
		print("read failed")
		print("=== END %s ===" % path)
		return false
	var gds: GDScript = GDScript.new()
	gds.resource_path = path
	gds.source_code = src
	var err: Error = gds.reload()
	if err != OK:
		print("=== FAIL %s ===" % path)
		print("GDScript.reload error=%s" % error_string(err))
		print("=== END %s ===" % path)
		return false
	return true


func _ensure_global_helpers() -> void:
	## class_name scripts used widely; isolated source_code compile can miss them if not touched yet.
	var helpers: PackedStringArray = PackedStringArray([
		"res://scripts/core/typed_variant.gd",
		"res://scripts/ship/ship_weapon_derive.gd",
		"res://scripts/visual/ship_look.gd",
		"res://scripts/combat/combat_formulas.gd",
		"res://scripts/combat/float_text_pool.gd",
		"res://scripts/debug/session_diagnostics.gd",
	])
	for hp: String in helpers:
		if FileAccess.file_exists(hp):
			ResourceLoader.load(hp, "", ResourceLoader.CACHE_MODE_REUSE)


func _collect_scripts(scripts_root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_walk(scripts_root, out)
	out.sort()
	return out


func _walk(dir_path: String, out: PackedStringArray) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var child: String = dir_path.path_join(name)
		if d.current_is_dir():
			if name != "addons":
				_walk(child, out)
		elif name.ends_with(".gd"):
			out.append(child)
		name = d.get_next()
	d.list_dir_end()
