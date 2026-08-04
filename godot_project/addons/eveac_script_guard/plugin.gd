@tool
extends EditorPlugin
## Project → Tools → 校验全部 GDScript（强制全量）.
## Idle / 默认：增量 — 只查相对 .godot/eveac_script_guard_cache.json 有变的脚本；无缓存则全量.
## Output is one block per file (DIAGNOSTICS §7).

const MENU_FULL := "校验全部 GDScript（全量）"
const MENU_INCR := "校验改动 GDScript（增量）"
const SCRIPTS_ROOT := "res://scripts"
const CACHE_PATH := "res://.godot/eveac_script_guard_cache.json"


func _enter_tree() -> void:
	add_tool_menu_item(MENU_INCR, _on_validate_incremental)
	add_tool_menu_item(MENU_FULL, _on_validate_full)
	call_deferred("_schedule_idle_validate")


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_INCR)
	remove_tool_menu_item(MENU_FULL)


func _schedule_idle_validate() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(1.5).timeout
	if not is_instance_valid(self):
		return
	_run_validate(false, false)


func _on_validate_incremental() -> void:
	_run_validate(true, false)


func _on_validate_full() -> void:
	_run_validate(true, true)


func _run_validate(from_menu: bool, force_full: bool) -> void:
	var all_paths: PackedStringArray = _collect_script_paths(SCRIPTS_ROOT)
	var cache: Dictionary = _load_cache()
	var warn_fp: String = _warn_policy_fingerprint()
	var do_full: bool = force_full or cache.is_empty() or str(cache.get("warnPolicyFp", "")) != warn_fp
	var ok_map: Dictionary = {}
	if cache.has("files") and typeof(cache["files"]) == TYPE_DICTIONARY:
		ok_map = (cache["files"] as Dictionary).duplicate()

	var to_check: PackedStringArray = PackedStringArray()
	var skipped := 0
	for path in all_paths:
		var rel := _res_to_rel(str(path))
		var stamp := _file_stamp(str(path))
		var need := do_full
		if not need:
			if not ok_map.has(rel):
				need = true
			else:
				var prev: Variant = ok_map[rel]
				if typeof(prev) != TYPE_DICTIONARY:
					need = true
				elif int(prev.get("mtimeUtc", -1)) != int(stamp.get("mtimeUtc", -2)) \
						or int(prev.get("length", -1)) != int(stamp.get("length", -2)):
					need = true
		if need:
			to_check.append(path)
		else:
			skipped += 1

	# Prune deleted.
	var live: Dictionary = {}
	for path in all_paths:
		live[_res_to_rel(str(path))] = true
	for key in ok_map.keys():
		if not live.has(key):
			ok_map.erase(key)

	var mode := "full" if do_full else "incremental"
	print("=== eveac_script_guard: mode=%s check=%d skip_ok=%d (from_menu=%s) ===" % [
		mode, to_check.size(), skipped, from_menu
	])

	var failed: PackedStringArray = PackedStringArray()
	var ok_n := 0
	for path in to_check:
		var rel := _res_to_rel(str(path))
		var block: Dictionary = _check_one(str(path))
		if bool(block.get("ok", false)):
			ok_n += 1
			ok_map[rel] = _file_stamp(str(path))
			continue
		failed.append(path)
		ok_map.erase(rel)
		print("=== FAIL %s ===" % path)
		for line in block.get("lines", []):
			push_error(str(line))
			print(str(line))
		print("=== END %s ===" % path)

	_save_cache({"version": 1, "warnPolicyFp": warn_fp, "files": ok_map})
	var summary := "eveac_script_guard: mode=%s ok=%d failed=%d skipped_ok=%d" % [
		mode, ok_n, failed.size(), skipped
	]
	if failed.is_empty():
		print(summary)
	else:
		push_warning(summary)
		print(summary)
		print("Failed paths:")
		for p in failed:
			print("  - %s" % p)


func _res_to_rel(path: String) -> String:
	if path.begins_with("res://"):
		return path.substr(6)
	return path


func _file_stamp(path: String) -> Dictionary:
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return {"mtimeUtc": 0, "length": 0}
	var length := 0
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f != null:
		length = int(f.get_length())
		f.close()
	return {
		"mtimeUtc": int(FileAccess.get_modified_time(abs_path)),
		"length": length,
	}


func _warn_policy_fingerprint() -> String:
	var abs_pg := ProjectSettings.globalize_path("res://project.godot")
	if not FileAccess.file_exists(abs_pg):
		return "missing"
	var text := FileAccess.get_file_as_string(abs_pg)
	var buf := PackedStringArray()
	var in_debug := false
	for line in text.split("\n"):
		var s := str(line)
		if s.begins_with("[debug]"):
			in_debug = true
			continue
		if s.begins_with("["):
			in_debug = false
			continue
		if in_debug and s.contains("gdscript/warnings/"):
			buf.append(s.strip_edges())
	return str(hash("\n".join(buf)))


func _load_cache() -> Dictionary:
	if not FileAccess.file_exists(CACHE_PATH):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


func _save_cache(data: Dictionary) -> void:
	var abs_dir := ProjectSettings.globalize_path("res://.godot")
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("eveac_script_guard: cannot write %s" % CACHE_PATH)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _collect_script_paths(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_walk_dir(root, out)
	out.sort()
	return out


func _walk_dir(dir_path: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var child: String = dir_path.path_join(name)
		if d.current_is_dir():
			if name != "addons":
				_walk_dir(child, out)
		elif name.ends_with(".gd"):
			out.append(child)
		name = d.get_next()
	d.list_dir_end()


func _check_one(path: String) -> Dictionary:
	var lines: PackedStringArray = PackedStringArray()
	if not ResourceLoader.exists(path):
		lines.append("missing resource %s" % path)
		return {"ok": false, "lines": lines}
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		lines.append("load returned null %s" % path)
		return {"ok": false, "lines": lines}
	var gds := res as GDScript
	if gds == null:
		lines.append("not a GDScript %s (%s)" % [path, res.get_class()])
		return {"ok": false, "lines": lines}
	var err: Error = gds.reload()
	if err != OK:
		lines.append("GDScript.reload failed path=%s error=%s" % [path, error_string(err)])
		return {"ok": false, "lines": lines}
	if gds.source_code.strip_edges().is_empty():
		lines.append("empty source %s" % path)
		return {"ok": false, "lines": lines}
	return {"ok": true, "lines": lines}
