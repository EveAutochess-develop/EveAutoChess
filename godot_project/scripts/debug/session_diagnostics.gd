extends Node
class_name SessionDiagnostics
## Non-blocking session breadcrumb + 1Hz heartbeat/perf → user://debug/eveac_session.log
## Support gate: only for sessions that can reach main menu → settings → export.
## Hot-path: add_usec integers only; flush deferred (DIAGNOSTICS.md).

const NODE_NAME: StringName = &"SessionDiagnostics"
const LOG_PATH: String = "user://debug/eveac_session.log"
const EXPORT_DIR_USER: String = "user://debug/exports"
const _SELF: String = "res://scripts/debug/session_diagnostics.gd"
const SPIKE_MS_DEFAULT: float = 33.0

var enabled: bool = true
var _queue: PackedStringArray = PackedStringArray()
var _heartbeat_accum: float = 0.0
var _flush_accum: float = 0.0
var _match: Node = null
var _error_hook_installed: bool = false
## key(StringName) -> {sum:int, max:int, frames:int, frame:int, spike_cd:float}
var _perf: Dictionary = {}
var _perf_steps_sum: int = 0
var _perf_steps_n: int = 0
var _spike_ms: float = SPIKE_MS_DEFAULT

static var _pending: Node = null

static func instance() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	@warning_ignore("unsafe_cast")
	var tree: SceneTree = loop as SceneTree
	var existing: Node = tree.root.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing:
		return existing
	if _pending != null and is_instance_valid(_pending):
		return _pending
	var loaded: Variant = load(_SELF)
	if not (loaded is GDScript):
		return null
	@warning_ignore("unsafe_cast")
	var scr: GDScript = loaded as GDScript
	var created: Variant = scr.new()
	if not (created is Node):
		return null
	@warning_ignore("unsafe_cast")
	var n: Node = created as Node
	n.name = String(NODE_NAME)
	_pending = n
	tree.root.add_child.call_deferred(n)
	return n


## One-liner from call sites (menu-reachable gameplay only).
static func log(tag: String, detail: String = "") -> void:
	var d: Node = instance()
	if d != null and d.has_method("log_event"):
		d.call("log_event", tag, detail)


## Hot path: integer usec only — no string alloc when disabled.
static func add_usec(key: StringName, usec: int) -> void:
	if usec <= 0:
		return
	var d: Node = instance()
	if d == null or not TypedVariant.as_bool(d.get("enabled"), false):
		return
	if d.has_method("add_usec_inner"):
		d.call("add_usec_inner", key, usec)


static func note_sim_steps(steps: int) -> void:
	var d: Node = instance()
	if d != null and d.has_method("note_sim_steps_inner"):
		d.call("note_sim_steps_inner", steps)


## Flush queue then copy session log for user export (UI click only — not Tick).
static func export_session_log() -> Dictionary:
	var d: Node = instance()
	if d == null or not d.has_method("export_log_now"):
		return {"ok": false, "reason": "no_diag"}
	return TypedVariant.as_dict(d.call("export_log_now"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pending = null
	DirAccess.make_dir_recursive_absolute("user://debug")
	if DataStore != null and DataStore.match_flow is Dictionary:
		enabled = TypedVariant.as_bool(DataStore.match_flow.get("diagnostics_enabled", true), true)
		_spike_ms = TypedVariant.as_float(
			DataStore.match_flow.get("diagnostics_perf_spike_ms", SPIKE_MS_DEFAULT),
			SPIKE_MS_DEFAULT
		)
	_install_error_hook()


func bind_match(m: Node) -> void:
	_match = m


func log_event(tag: String, detail: String = "") -> void:
	if not enabled:
		return
	var line: String = "%.3f\t%s\t%s" % [Time.get_unix_time_from_system(), tag, detail]
	_queue.append(line)
	if _queue.size() > 4000:
		_queue = _queue.slice(_queue.size() - 2000)


func add_usec_inner(key: StringName, usec: int) -> void:
	if not enabled:
		return
	var bucket: Dictionary
	if _perf.has(key):
		bucket = TypedVariant.as_dict(_perf[key])
	else:
		bucket = {"sum": 0, "max": 0, "frames": 0, "frame": 0, "spike_cd": 0.0}
		_perf[key] = bucket
	bucket["sum"] = TypedVariant.as_int(bucket.get("sum", 0)) + usec
	var fr: int = TypedVariant.as_int(bucket.get("frame", 0)) + usec
	bucket["frame"] = fr
	if fr > TypedVariant.as_int(bucket.get("max", 0)):
		bucket["max"] = fr


func note_sim_steps_inner(steps: int) -> void:
	if not enabled or steps <= 0:
		return
	_perf_steps_sum += steps
	_perf_steps_n += 1


func flush_now() -> void:
	if _queue.is_empty():
		return
	var batch: PackedStringArray = _queue.duplicate()
	_queue.clear()
	_write_batch(batch)


## Returns {ok, path, reason}. Must run on UI thread after user click.
func export_log_now() -> Dictionary:
	flush_now()
	if not FileAccess.file_exists(LOG_PATH):
		return {"ok": false, "reason": "no_log"}
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "")
	var fname: String = "eveac_session_%s.log" % stamp
	var dest: String = _pick_export_path(fname)
	if dest.is_empty():
		return {"ok": false, "reason": "no_dest"}
	var src: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
	if src == null:
		return {"ok": false, "reason": "read_fail"}
	var text: String = src.get_as_text()
	src.close()
	var abs_parent: String = dest.get_base_dir()
	DirAccess.make_dir_recursive_absolute(abs_parent)
	var out: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
	if out == null:
		var fb: String = EXPORT_DIR_USER.path_join(fname)
		DirAccess.make_dir_recursive_absolute(EXPORT_DIR_USER)
		out = FileAccess.open(fb, FileAccess.WRITE)
		if out == null:
			return {"ok": false, "reason": "write_fail"}
		dest = fb
	out.store_string(text)
	out.close()
	var shown: String = ProjectSettings.globalize_path(dest) if dest.begins_with("user://") else dest
	DisplayServer.clipboard_set(shown)
	return {"ok": true, "path": shown, "reason": "", "clipboard": true}


func _pick_export_path(fname: String) -> String:
	var dl: String = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dl != "" and DirAccess.dir_exists_absolute(dl):
		return dl.path_join(fname)
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR_USER)
	return EXPORT_DIR_USER.path_join(fname)


func _process(delta: float) -> void:
	if not enabled:
		return
	## End-of-frame: count frames that had samples; reset per-frame accumulators.
	for k: Variant in _perf.keys():
		var b: Dictionary = TypedVariant.as_dict(_perf[k])
		var fr: int = TypedVariant.as_int(b.get("frame", 0))
		if fr > 0:
			b["frames"] = TypedVariant.as_int(b.get("frames", 0)) + 1
			var spike_cd: float = TypedVariant.as_float(b.get("spike_cd", 0.0))
			if spike_cd > 0.0:
				b["spike_cd"] = maxf(0.0, spike_cd - delta)
			elif float(fr) * 0.001 > _spike_ms:
				log_event("perf.spike", "%s_ms=%.1f" % [str(k), float(fr) * 0.001])
				b["spike_cd"] = 1.0
		b["frame"] = 0
	_heartbeat_accum += delta
	_flush_accum += delta
	if _heartbeat_accum >= 1.0:
		_heartbeat_accum = 0.0
		_emit_heartbeat()
		_emit_perf()
	if _flush_accum >= 2.0:
		_flush_accum = 0.0
		_flush_async()


func _emit_heartbeat() -> void:
	var fps: float = Engine.get_frames_per_second()
	var mem: int = OS.get_static_memory_usage()
	var stage: int = -1
	var round_n: int = 0
	var speed: float = 1.0
	var units: int = -1
	var mobile_n: int = -1
	if _match != null:
		var mc_v: Variant = _match.get("match_ctrl")
		if mc_v is Object:
			@warning_ignore("unsafe_cast")
			var mc: Object = mc_v as Object
			stage = TypedVariant.as_int(mc.get("stage"), -1)
			round_n = TypedVariant.as_int(mc.get("battle_game_stage_count"), 0)
			speed = TypedVariant.as_float(mc.get("speed_multiplier"), 1.0)
		var board_v: Variant = _match.get("board")
		if board_v is Node:
			@warning_ignore("unsafe_cast")
			var board: Node = board_v as Node
			if board.has_method("all_ships"):
				var ships_v: Variant = board.call("all_ships")
				if ships_v is Array:
					@warning_ignore("unsafe_cast")
					var ships: Array = ships_v as Array
					var manned: int = 0
					var unman: int = 0
					for s_v: Variant in ships:
						if s_v == null or not (s_v is Object):
							continue
						@warning_ignore("unsafe_cast")
						var s: Object = s_v as Object
						if not is_instance_valid(s):
							continue
						if TypedVariant.as_bool(s.get("is_destroyed")):
							continue
						if TypedVariant.as_bool(s.get("is_unmanned")):
							unman += 1
						else:
							manned += 1
					units = manned
					mobile_n = unman
	var nomodel: int = 0
	var fps_cap: int = 0
	if GameSession != null:
		nomodel = 1 if GameSession.no_model_perf_mode else 0
		fps_cap = GameSession.target_fps
	var detail: String = "fps=%s mem=%s stage=%s round=%s speed=%s nomodel=%d fps_cap=%d" % [
		fps, mem, stage, round_n, speed, nomodel, fps_cap
	]
	if units >= 0:
		detail += " units=%d" % units
	if mobile_n >= 0:
		detail += " mobile=%d" % mobile_n
	log_event("heartbeat", detail)


func _emit_perf() -> void:
	if _perf.is_empty() and _perf_steps_n <= 0:
		return
	var parts: PackedStringArray = PackedStringArray()
	var keys: Array = _perf.keys()
	keys.sort()
	for k: Variant in keys:
		var b: Dictionary = TypedVariant.as_dict(_perf[k])
		var sum_u: int = TypedVariant.as_int(b.get("sum", 0))
		if sum_u <= 0:
			continue
		var max_u: int = TypedVariant.as_int(b.get("max", 0))
		var frames: int = TypedVariant.as_int(b.get("frames", 0))
		var ks: String = str(k)
		parts.append("%s_ms=%.1f" % [ks, float(sum_u) * 0.001])
		parts.append("%s_max=%.1f" % [ks, float(max_u) * 0.001])
		if frames > 0:
			parts.append("%s_frames=%d" % [ks, frames])
		b["sum"] = 0
		b["max"] = 0
		b["frames"] = 0
	if _perf_steps_n > 0:
		var avg_steps: float = float(_perf_steps_sum) / float(_perf_steps_n)
		parts.append("steps=%.1f" % avg_steps)
		_perf_steps_sum = 0
		_perf_steps_n = 0
	parts.append("frames=%d" % maxi(1, int(Engine.get_frames_per_second())))
	if parts.is_empty():
		return
	log_event("perf", " ".join(parts))


func _flush_async() -> void:
	if _queue.is_empty():
		return
	var batch: PackedStringArray = _queue.duplicate()
	_queue.clear()
	call_deferred("_write_batch", batch)


func _write_batch(batch: PackedStringArray) -> void:
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for line: String in batch:
		f.store_line(line)
	f.close()


func _install_error_hook() -> void:
	if _error_hook_installed:
		return
	_error_hook_installed = true


func _exit_tree() -> void:
	if not _queue.is_empty():
		_write_batch(_queue)
		_queue.clear()
