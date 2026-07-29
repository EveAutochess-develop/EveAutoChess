extends Node
class_name SessionDiagnostics
## Non-blocking session breadcrumb + 1Hz heartbeat → user://debug/eveac_session.log

const NODE_NAME := &"SessionDiagnostics"
const LOG_PATH := "user://debug/eveac_session.log"
const _SELF := "res://scripts/debug/session_diagnostics.gd"

var enabled: bool = true
var _queue: PackedStringArray = PackedStringArray()
var _heartbeat_accum: float = 0.0
var _flush_accum: float = 0.0
var _match: Node = null

static var _pending: Node = null

static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var existing := tree.root.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing:
		return existing
	if _pending != null and is_instance_valid(_pending):
		return _pending
	var scr := load(_SELF) as GDScript
	if scr == null:
		return null
	var n: Node = scr.new()
	n.name = String(NODE_NAME)
	_pending = n
	tree.root.add_child.call_deferred(n)
	return n

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pending = null
	DirAccess.make_dir_recursive_absolute("user://debug")
	if DataStore and DataStore.match_flow is Dictionary:
		enabled = bool(DataStore.match_flow.get("diagnostics_enabled", true))

func bind_match(m: Node) -> void:
	_match = m

func log_event(tag: String, detail: String = "") -> void:
	if not enabled:
		return
	var line := "%.3f\t%s\t%s" % [Time.get_unix_time_from_system(), tag, detail]
	_queue.append(line)
	if _queue.size() > 4000:
		_queue = _queue.slice(_queue.size() - 2000)

func _process(delta: float) -> void:
	if not enabled:
		return
	_heartbeat_accum += delta
	_flush_accum += delta
	if _heartbeat_accum >= 1.0:
		_heartbeat_accum = 0.0
		_emit_heartbeat()
	if _flush_accum >= 2.0:
		_flush_accum = 0.0
		_flush_async()

func _emit_heartbeat() -> void:
	var fps := Engine.get_frames_per_second()
	var mem := OS.get_static_memory_usage()
	var stage := -1
	var round_n := 0
	var speed := 1.0
	if _match and _match.get("match_ctrl"):
		var mc = _match.match_ctrl
		if mc:
			stage = int(mc.stage)
			round_n = int(mc.battle_game_stage_count)
			speed = float(mc.speed_multiplier)
	log_event("heartbeat", "fps=%s mem=%s stage=%s round=%s speed=%s" % [fps, mem, stage, round_n, speed])

func _flush_async() -> void:
	if _queue.is_empty():
		return
	var batch: PackedStringArray = _queue.duplicate()
	_queue.clear()
	# Defer disk write off the current frame's hot path.
	call_deferred("_write_batch", batch)

func _write_batch(batch: PackedStringArray) -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for line in batch:
		f.store_line(line)
	f.close()

func _exit_tree() -> void:
	if not _queue.is_empty():
		_write_batch(_queue)
		_queue.clear()
