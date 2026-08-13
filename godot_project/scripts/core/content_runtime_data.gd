extends RefCounted
class_name ContentRuntimeData
## D-EAC-34 / CONTENT_FORMAT §1.1 / RELEASE_AND_HOTUPDATE §2.2
## Semi-expose playable JSON under user://content_runtime/data/; DataStore prefers disk.

const RUNTIME_DATA_ROOT: String = "user://content_runtime/data"
const RES_DATA_ROOT: String = "res://data"
## Subtrees that may be hand-edited after install.
const EXPOSE_SUBDIRS: PackedStringArray = [
	"ships",
	"balance",
	"fetters",
	"unmanned_units",
	"equipment",
	"admin",
	"locale",
	"ui",
]
## Flat JSON files at data/ root (portrait/mesh maps stay PCK-only; not seeded).
const EXPOSE_ROOT_FILES: PackedStringArray = []
## Baseline files seeded last run. A file listed here but gone from res://data was
## deleted upstream (removed ship etc.), so its stale runtime copy must go too —
## otherwise deleted content keeps loading from user://. Hand-added files are never
## listed, so pruning leaves them alone.
const SEED_MANIFEST: String = "user://content_runtime/data/_seed_manifest.json"


static func runtime_path(rel: String) -> String:
	return RUNTIME_DATA_ROOT.path_join(rel.replace("\\", "/").lstrip("/"))


static func res_path(rel: String) -> String:
	return RES_DATA_ROOT.path_join(rel.replace("\\", "/").lstrip("/"))


## First-run / empty tree: copy baseline from res://data into user://.
## Player builds never overwrite an existing file (hand edits are sticky until deleted).
## In the editor `res://data` IS the authoring source, so it always wins — otherwise a
## stale seeded copy would shadow the JSON we just edited in the repo.
static func ensure_seeded() -> Dictionary:
	var force: bool = OS.has_feature("editor")
	var wrote: int = 0
	var skipped: int = 0
	var root_abs: String = ProjectSettings.globalize_path(RUNTIME_DATA_ROOT)
	DirAccess.make_dir_recursive_absolute(root_abs)
	var baseline: Array[String] = []
	for sub: String in EXPOSE_SUBDIRS:
		var r: Dictionary = _seed_dir(sub, force)
		wrote += TypedVariant.as_int(r.get("wrote", 0), 0)
		skipped += TypedVariant.as_int(r.get("skipped", 0), 0)
		for rel: Variant in TypedVariant.as_array(r.get("baseline", [])):
			baseline.append(str(rel))
	for fn: String in EXPOSE_ROOT_FILES:
		if _seed_file(fn, force):
			wrote += 1
		else:
			skipped += 1
		baseline.append(fn)
	var pruned: int = _prune_removed_baseline(baseline, force)
	_write_seed_manifest(baseline)
	return {"ok": true, "wrote": wrote, "skipped": skipped, "pruned": pruned, "forced": force}


## Editor / force-pull: overwrite ships + equipment (+ unmanned) from res:// baseline.
static func force_reseed_ships_equipment_unmanned() -> Dictionary:
	var wrote: int = 0
	var skipped: int = 0
	var root_abs: String = ProjectSettings.globalize_path(RUNTIME_DATA_ROOT)
	DirAccess.make_dir_recursive_absolute(root_abs)
	var baseline: Array[String] = []
	for sub: String in ["ships", "equipment", "unmanned_units"]:
		var r: Dictionary = _seed_dir(sub, true)
		wrote += TypedVariant.as_int(r.get("wrote", 0), 0)
		skipped += TypedVariant.as_int(r.get("skipped", 0), 0)
		for rel: Variant in TypedVariant.as_array(r.get("baseline", [])):
			baseline.append(str(rel))
	## Refresh full seed manifest from all expose dirs so prune stays consistent.
	var full_baseline: Array[String] = []
	for sub: String in EXPOSE_SUBDIRS:
		var r2: Dictionary = _seed_dir(sub, false)
		for rel: Variant in TypedVariant.as_array(r2.get("baseline", [])):
			full_baseline.append(str(rel))
	var pruned: int = _prune_removed_baseline(full_baseline, false)
	_write_seed_manifest(full_baseline)
	print("[ContentRuntimeData] force_reseed ships/equipment/unmanned wrote=%s pruned=%s" % [wrote, pruned])
	return {"ok": true, "wrote": wrote, "skipped": skipped, "pruned": pruned, "forced": true}


## Delete runtime copies of baseline files that no longer exist in res://data.
## Editor runs also sweep untracked orphans, since there res://data IS the authoring source.
static func _prune_removed_baseline(baseline: Array[String], force: bool) -> int:
	var current: Dictionary = {}
	for rel: String in baseline:
		current[rel] = true
	var stale: Dictionary = {}
	for rel: String in _read_seed_manifest():
		if not current.has(rel):
			stale[rel] = true
	if force:
		for sub: String in EXPOSE_SUBDIRS:
			for rel: String in _list_runtime_json(sub):
				if not current.has(rel):
					stale[rel] = true
	var n: int = 0
	for rel_key: Variant in stale.keys():
		var rel: String = str(rel_key)
		var abs_path: String = ProjectSettings.globalize_path(runtime_path(rel))
		if not FileAccess.file_exists(abs_path):
			continue
		if DirAccess.remove_absolute(abs_path) == OK:
			n += 1
			print("[ContentRuntimeData] pruned stale runtime %s" % rel)
		else:
			push_warning("[ContentRuntimeData] cannot prune %s" % abs_path)
	return n


static func _list_runtime_json(rel_dir: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(runtime_path(rel_dir))
	if dir == null:
		return out
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			out.append(rel_dir.path_join(fn))
		fn = dir.get_next()
	return out


static func _read_seed_manifest() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(SEED_MANIFEST):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEED_MANIFEST))
	if not (data is Dictionary):
		return out
	var data_dict: Dictionary = data
	for rel: Variant in TypedVariant.as_array(data_dict.get("files", [])):
		out.append(str(rel))
	return out


static func _write_seed_manifest(baseline: Array[String]) -> void:
	var f: FileAccess = FileAccess.open(SEED_MANIFEST, FileAccess.WRITE)
	if f == null:
		push_warning("[ContentRuntimeData] cannot write %s" % SEED_MANIFEST)
		return
	var sorted: Array[String] = baseline.duplicate()
	sorted.sort()
	f.store_string(JSON.stringify({"files": sorted}, "  "))
	f.close()


static func _seed_dir(rel_dir: String, force: bool = false) -> Dictionary:
	var wrote: int = 0
	var skipped: int = 0
	var baseline: Array[String] = []
	var src_dir: String = res_path(rel_dir)
	var dir: DirAccess = DirAccess.open(src_dir)
	if dir == null:
		return {"wrote": 0, "skipped": 0, "baseline": baseline}
	var dst_abs: String = ProjectSettings.globalize_path(runtime_path(rel_dir))
	DirAccess.make_dir_recursive_absolute(dst_abs)
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			var rel: String = rel_dir.path_join(fn)
			baseline.append(rel)
			if _seed_file(rel, force):
				wrote += 1
			else:
				skipped += 1
		fn = dir.get_next()
	return {"wrote": wrote, "skipped": skipped, "baseline": baseline}


static func _seed_file(rel: String, force: bool = false) -> bool:
	## Returns true if a file was written.
	var dst: String = runtime_path(rel)
	if not force and FileAccess.file_exists(dst):
		return false
	var src: String = res_path(rel)
	if not ResourceLoader.exists(src) and not FileAccess.file_exists(src):
		return false
	var text: String = FileAccess.get_file_as_string(src)
	if text.is_empty():
		var f: FileAccess = FileAccess.open(src, FileAccess.READ)
		if f == null:
			return false
		text = f.get_as_text()
		f.close()
	var parent: String = ProjectSettings.globalize_path(dst.get_base_dir())
	DirAccess.make_dir_recursive_absolute(parent)
	var out: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if out == null:
		push_warning("[ContentRuntimeData] cannot write %s" % dst)
		return false
	out.store_string(text)
	out.close()
	return true


## Prefer runtime disk; fall back to res:// (PCK). Bad JSON → warning + PCK fallback.
static func load_json_prefer_runtime(rel: String) -> Dictionary:
	var runtime: String = runtime_path(rel)
	if FileAccess.file_exists(runtime):
		var parsed: Dictionary = _parse_json_file(runtime)
		if not parsed.is_empty() or _file_is_empty_object(runtime):
			return parsed
		push_warning("[ContentRuntimeData] bad JSON %s — falling back to PCK" % runtime)
	return _parse_json_file(res_path(rel))


static func _file_is_empty_object(path: String) -> bool:
	## Distinguish "{}" from parse failure.
	var text: String = FileAccess.get_file_as_string(path).strip_edges()
	return text == "{}" or text == "[]"


static func _parse_json_file(path: String) -> Dictionary:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f:
			text = f.get_as_text()
			f.close()
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		push_warning("[ContentRuntimeData] JSON not object: %s" % path)
		return {}
	var data_dict: Dictionary = data
	return data_dict


## Merge dir: load all res:// files, then overlay any runtime files (same id wins).
static func load_dir_overlay(rel_dir: String, on_item: Callable) -> void:
	var seen: Dictionary = {}
	_for_each_json(res_path(rel_dir), func(path: String, d: Dictionary) -> void:
		seen[path.get_file()] = true
		if on_item.is_valid():
			on_item.call(d, path, false)
	)
	_for_each_json(runtime_path(rel_dir), func(path: String, d: Dictionary) -> void:
		seen[path.get_file()] = true
		if on_item.is_valid():
			on_item.call(d, path, true)
	)


static func _for_each_json(dir_path: String, on_item: Callable) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			var full: String = dir_path.path_join(fn)
			var d: Dictionary = _parse_json_file(full)
			if d.is_empty() and not _file_is_empty_object(full):
				## Try PCK twin when runtime file is corrupt.
				if dir_path.begins_with(RUNTIME_DATA_ROOT):
					var rel: String = full.trim_prefix(RUNTIME_DATA_ROOT).lstrip("/")
					d = _parse_json_file(res_path(rel))
					push_warning("[ContentRuntimeData] bad runtime %s — used PCK" % full)
			if not d.is_empty() and on_item.is_valid():
				on_item.call(d, full)
		fn = dir.get_next()
