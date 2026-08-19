extends RefCounted
class_name OnnxBundleIo
## Import/export farm CPU six-net zip for 游戏设置 (AI_PLAYER_HANDBOOK §0.2).

const NET_NAMES: PackedStringArray = ["titan", "match_global", "ops", "shop", "fit", "place"]
const USER_BUNDLE: String = "user://eveac_ai/model_bundle"
const RES_BUNDLE: String = "res://data/ai/model_bundle"
const USER_AI: String = "user://eveac_ai"
const EXPORT_NAME: String = "eveac_opponent_pack.zip"
const FILTERS: PackedStringArray = ["*.zip ; 人机对手包"]


static func status_text(res: Dictionary) -> String:
	if TypedVariant.as_bool(res.get("ok", false), false):
		if str(res.get("op", "")) == "import":
			var h: String = str(res.get("hash", ""))
			if h != "":
				return "已导入人机对手包（hash %s…）" % h.substr(0, mini(12, h.length()))
			return "已导入人机对手包"
		return "已导出并复制路径: %s" % str(res.get("path", ""))
	var reason: String = str(res.get("reason", ""))
	if reason == "missing_bundle":
		return "没有可导出的人机对手包"
	if reason == "schema_ver":
		return "导入失败：对手包版本不匹配"
	if reason == "content_rev":
		return "导入失败：舰装内容版本不匹配"
	if reason == "not_found" or reason == "zip_open":
		return "导入失败：找不到文件"
	if reason.begins_with("missing_"):
		return "导入失败：缺少 %s" % reason.trim_prefix("missing_")
	return "人机对手包失败（%s）" % reason


static func prompt_export(host: Node, done: Callable) -> void:
	var suggested: String = _default_export_path()
	var native_ok: bool = _native_file_ok()
	if native_ok:
		var show_err: Error = DisplayServer.file_dialog_show(
			"导出人机对手包",
			suggested.get_base_dir(),
			EXPORT_NAME,
			false,
			DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
			PackedStringArray(FILTERS),
			func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
				if not ok or paths.is_empty():
					return
				done.call(export_to_path(str(paths[0])))
		)
		if show_err == OK:
			return
	_spawn_dialog(host, FileDialog.FILE_MODE_SAVE_FILE, suggested, func(path: String) -> void:
		done.call(export_to_path(path))
	)


static func prompt_import(host: Node, done: Callable) -> void:
	var start_dir: String = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var native_ok: bool = _native_file_ok()
	if native_ok:
		var show_err: Error = DisplayServer.file_dialog_show(
			"导入人机对手包",
			start_dir,
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray(FILTERS),
			func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
				if not ok or paths.is_empty():
					return
				done.call(import_from_path(str(paths[0])))
		)
		if show_err == OK:
			return
	_spawn_dialog(host, FileDialog.FILE_MODE_OPEN_FILE, start_dir.path_join(EXPORT_NAME), func(path: String) -> void:
		done.call(import_from_path(path))
	)


static func export_to_path(raw_path: String) -> Dictionary:
	var dest: String = raw_path.strip_edges()
	if dest.is_empty():
		return {"ok": false, "reason": "no_path"}
	if not dest.get_file().to_lower().ends_with(".zip"):
		dest += ".zip"
	var files: Dictionary = _collect_export_files()
	if not TypedVariant.as_bool(files.get("_ok", false), false):
		return {"ok": false, "reason": str(files.get("reason", "missing_bundle"))}
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var zip: ZIPPacker = ZIPPacker.new()
	var err: int = zip.open(dest, ZIPPacker.APPEND_CREATE)
	if err != OK:
		var fb: String = "user://debug/exports".path_join(EXPORT_NAME)
		DirAccess.make_dir_recursive_absolute("user://debug/exports")
		dest = ProjectSettings.globalize_path(fb)
		err = zip.open(dest, ZIPPacker.APPEND_CREATE)
		if err != OK:
			return {"ok": false, "reason": "write_fail"}
	for k: Variant in files.keys():
		var name: String = str(k)
		if name.begins_with("_"):
			continue
		var bytes_v: Variant = files[k]
		if not (bytes_v is PackedByteArray):
			continue
		var bytes: PackedByteArray = TypedVariant.as_packed_bytes(bytes_v)
		zip.start_file(name)
		zip.write_file(bytes)
		zip.close_file()
	zip.close()
	var shown: String = ProjectSettings.globalize_path(dest) if dest.begins_with("user://") else dest
	DisplayServer.clipboard_set(shown)
	return {"ok": true, "path": shown, "reason": "", "op": "export"}


static func import_from_path(raw_path: String) -> Dictionary:
	var src: String = raw_path.strip_edges()
	if src.is_empty() or not FileAccess.file_exists(src):
		if src.is_empty() or not DirAccess.dir_exists_absolute(src):
			return {"ok": false, "reason": "not_found"}
	var packed: Dictionary = {}
	if src.to_lower().ends_with(".zip"):
		packed = _read_zip(src)
	elif src.get_file().to_lower() == "manifest.json":
		packed = _read_dir(src.get_base_dir())
	elif DirAccess.dir_exists_absolute(src):
		packed = _read_dir(src)
	else:
		return {"ok": false, "reason": "bad_type"}
	if not TypedVariant.as_bool(packed.get("_ok", false), false):
		return {"ok": false, "reason": str(packed.get("reason", "invalid"))}
	DirAccess.make_dir_recursive_absolute(USER_BUNDLE)
	DirAccess.make_dir_recursive_absolute(USER_AI)
	for k: Variant in packed.keys():
		var name: String = str(k)
		if name.begins_with("_"):
			continue
		var bytes_v: Variant = packed[k]
		if not (bytes_v is PackedByteArray):
			continue
		var dest: String = USER_BUNDLE.path_join(name)
		if name == "behavior.genome.json" or name == "weights_table.json":
			dest = USER_AI.path_join(name)
		if name.begins_with("learn_delta/"):
			continue
		var f: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			return {"ok": false, "reason": "write_fail"}
		var bytes: PackedByteArray = TypedVariant.as_packed_bytes(bytes_v)
		f.store_buffer(bytes)
		f.close()
	var has_delta: bool = false
	for pk: Variant in packed.keys():
		if str(pk).begins_with("learn_delta/"):
			has_delta = true
			break
	InMatchSlowLearn.import_delta_bytes(packed, has_delta)
	_invalidate_sessions()
	return {"ok": true, "path": src, "reason": "", "op": "import", "hash": str(packed.get("_hash", ""))}


static func _native_file_ok() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)


static func _default_export_path() -> String:
	var dl: String = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dl != "" and DirAccess.dir_exists_absolute(dl):
		return dl.path_join(EXPORT_NAME)
	DirAccess.make_dir_recursive_absolute("user://debug/exports")
	return ProjectSettings.globalize_path("user://debug/exports".path_join(EXPORT_NAME))


static func _spawn_dialog(host: Node, mode: FileDialog.FileMode, current: String, picked: Callable) -> void:
	if host == null:
		return
	var dlg: FileDialog = FileDialog.new()
	dlg.file_mode = mode
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.add_filter("*.zip", "人机对手包")
	dlg.current_dir = current.get_base_dir()
	dlg.current_file = current.get_file()
	dlg.exclusive = true
	host.add_child(dlg)
	dlg.file_selected.connect(func(path: String) -> void:
		picked.call(path)
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered_ratio(0.6)


static func _collect_export_files() -> Dictionary:
	var dir: String = _best_bundle_dir()
	if dir == "":
		return {"_ok": false, "reason": "missing_bundle"}
	var out: Dictionary = {"_ok": true}
	var man_bytes: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join("manifest.json"))
	if man_bytes.is_empty():
		return {"_ok": false, "reason": "missing_manifest"}
	out["manifest.json"] = man_bytes
	for n: String in NET_NAMES:
		var p: String = dir.path_join("%s.json" % n)
		var b: PackedByteArray = FileAccess.get_file_as_bytes(p)
		if b.is_empty():
			return {"_ok": false, "reason": "missing_%s" % n}
		out["%s.json" % n] = b
	_maybe_add_sidecar(out, "behavior.genome.json")
	if not out.has("behavior.genome.json"):
		out["behavior.genome.json"] = _default_genome_bytes(man_bytes)
	_maybe_add_sidecar(out, "weights_table.json")
	var delta_files: Dictionary = InMatchSlowLearn.collect_export_bytes()
	for dk: Variant in delta_files.keys():
		out[str(dk)] = delta_files[dk]
	return out


static func _best_bundle_dir() -> String:
	if _dir_has_bundle(USER_BUNDLE):
		return USER_BUNDLE
	if _dir_has_bundle(RES_BUNDLE):
		return RES_BUNDLE
	return ""


static func _dir_has_bundle(dir: String) -> bool:
	if not FileAccess.file_exists(dir.path_join("manifest.json")):
		return false
	for n: String in NET_NAMES:
		if not FileAccess.file_exists(dir.path_join("%s.json" % n)):
			return false
	return true


static func _maybe_add_sidecar(out: Dictionary, fname: String) -> void:
	var user_p: String = USER_AI.path_join(fname)
	var res_p: String = "res://data/ai".path_join(fname)
	var p: String = user_p if FileAccess.file_exists(user_p) else (res_p if FileAccess.file_exists(res_p) else "")
	if p == "":
		return
	var b: PackedByteArray = FileAccess.get_file_as_bytes(p)
	if not b.is_empty():
		out[fname] = b


static func _default_genome_bytes(man_bytes: PackedByteArray) -> PackedByteArray:
	var rev: String = ""
	var parsed: Variant = JSON.parse_string(man_bytes.get_string_from_utf8())
	rev = str(TypedVariant.as_dict(parsed).get("content_rev", ""))
	var stance: Dictionary = {}
	var pick: Dictionary = {}
	for id: String in WeightDrivenAi.STANCE_IDS:
		stance[id] = 0.2
	for t: String in WeightDrivenAi.TITAN_IDS:
		pick[t] = 0.2
	var g: Dictionary = {
		"schema_ver": "1",
		"content_rev": rev,
		"stance": stance,
		"titan_pick": pick,
		"titan_slices": {},
	}
	return JSON.stringify(g).to_utf8_buffer()


static func _read_zip(path: String) -> Dictionary:
	var zr: ZIPReader = ZIPReader.new()
	if zr.open(path) != OK:
		return {"_ok": false, "reason": "zip_open"}
	var names: PackedStringArray = zr.get_files()
	var raw: Dictionary = {}
	for fn: String in names:
		if fn.begins_with("__MACOSX") or fn.ends_with("/"):
			continue
		var base: String = fn.get_file()
		if base.is_empty() or base.begins_with("."):
			continue
		var key: String = fn
		if not fn.begins_with("learn_delta/"):
			key = base
		raw[key] = zr.read_file(fn)
	zr.close()
	return _validate_pack(raw)


static func _read_dir(dir: String) -> Dictionary:
	var raw: Dictionary = {}
	var man: String = dir.path_join("manifest.json")
	if not FileAccess.file_exists(man):
		return {"_ok": false, "reason": "missing_manifest"}
	raw["manifest.json"] = FileAccess.get_file_as_bytes(man)
	for n: String in NET_NAMES:
		var p: String = dir.path_join("%s.json" % n)
		if FileAccess.file_exists(p):
			raw["%s.json" % n] = FileAccess.get_file_as_bytes(p)
	for extra: String in ["behavior.genome.json", "weights_table.json"]:
		var ep: String = dir.path_join(extra)
		if FileAccess.file_exists(ep):
			raw[extra] = FileAccess.get_file_as_bytes(ep)
		else:
			var up: String = dir.get_base_dir().path_join(extra)
			if FileAccess.file_exists(up):
				raw[extra] = FileAccess.get_file_as_bytes(up)
	var delta_dir: String = dir.path_join("learn_delta")
	if not DirAccess.dir_exists_absolute(delta_dir):
		delta_dir = dir.get_base_dir().path_join("learn_delta")
	if DirAccess.dir_exists_absolute(delta_dir):
		var da: DirAccess = DirAccess.open(delta_dir)
		if da != null:
			da.list_dir_begin()
			var fn: String = da.get_next()
			while fn != "":
				if not da.current_is_dir():
					raw["learn_delta/%s" % fn] = FileAccess.get_file_as_bytes(delta_dir.path_join(fn))
				fn = da.get_next()
			da.list_dir_end()
	return _validate_pack(raw)


static func _validate_pack(raw: Dictionary) -> Dictionary:
	if not raw.has("manifest.json"):
		return {"_ok": false, "reason": "missing_manifest"}
	var man_bytes: PackedByteArray = raw["manifest.json"]
	var parsed: Variant = JSON.parse_string(man_bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"_ok": false, "reason": "bad_manifest"}
	var man: Dictionary = TypedVariant.as_dict(parsed)
	if str(man.get("schema_ver", "")) != OnnxCpuPolicy.SCHEMA_VER:
		return {"_ok": false, "reason": "schema_ver"}
	var local_rev: String = _local_content_rev()
	var pack_rev: String = str(man.get("content_rev", ""))
	if local_rev != "" and pack_rev != "" and pack_rev != local_rev:
		return {"_ok": false, "reason": "content_rev"}
	for n: String in NET_NAMES:
		var key: String = "%s.json" % n
		if not raw.has(key):
			return {"_ok": false, "reason": "missing_%s" % n}
		var nb: PackedByteArray = raw[key]
		var nv: Variant = JSON.parse_string(nb.get_string_from_utf8())
		if not (nv is Dictionary):
			return {"_ok": false, "reason": "bad_%s" % n}
	if not raw.has("behavior.genome.json"):
		return {"_ok": false, "reason": "missing_behavior.genome.json"}
	var gb: PackedByteArray = raw["behavior.genome.json"]
	var gv: Variant = JSON.parse_string(gb.get_string_from_utf8())
	if not (gv is Dictionary):
		return {"_ok": false, "reason": "bad_behavior.genome.json"}
	var out: Dictionary = raw.duplicate()
	out["_ok"] = true
	out["_hash"] = str(man.get("model_bundle_hash", ""))
	return out


static func _local_content_rev() -> String:
	for dir: String in [USER_BUNDLE, RES_BUNDLE]:
		var p: String = dir.path_join("manifest.json")
		if not FileAccess.file_exists(p):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		var rev: String = str(TypedVariant.as_dict(parsed).get("content_rev", ""))
		if rev != "":
			return rev
	return ""


static func _invalidate_sessions() -> void:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	@warning_ignore("unsafe_cast")
	var tree: SceneTree = loop as SceneTree
	var n: Node = tree.root.find_child("NullsecNetSession", true, false)
	if n != null and n.has_method("invalidate_onnx_bundle_cache"):
		n.call("invalidate_onnx_bundle_cache")
