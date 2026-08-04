extends Node
class_name BgMusic
## Content-side BGM host under /root/BgMusic (PCK cannot register Autoloads).
## Track: res://assets/audio/bgm/neo.ogg — loop; options: enable + 0..100 volume.

const NODE_NAME: StringName = &"BgMusic"
const STREAM_PATH: String = "res://assets/audio/bgm/neo.ogg"
const SETTINGS_PATH: String = "user://player_settings.cfg"
const BUS_NAME: StringName = &"BGM"
const _SELF: String = "res://scripts/audio/bg_music.gd"

var enabled: bool = false
var volume_pct: float = 60.0

var _player: AudioStreamPlayer


static func instance() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	@warning_ignore("unsafe_cast")
	var tree: SceneTree = loop as SceneTree
	var existing: Node = tree.root.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing:
		return existing
	# Avoid class_name .new() — global class cache may miss after load_resource_pack.
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
	tree.root.add_child.call_deferred(n)
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	_load_settings()
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.bus = String(BUS_NAME)
	add_child(_player)
	if ResourceLoader.exists(STREAM_PATH):
		var stream_v: Variant = load(STREAM_PATH)
		if stream_v is AudioStream:
			@warning_ignore("unsafe_cast")
			var stream: AudioStream = stream_v as AudioStream
			if stream is AudioStreamOggVorbis:
				@warning_ignore("unsafe_cast")
				(stream as AudioStreamOggVorbis).loop = true
			elif stream.has_method("set_loop"):
				stream.call("set_loop", true)
			_player.stream = stream
	_apply()


func set_enabled(on: bool) -> void:
	enabled = on
	_apply()
	_save_settings()


func set_volume_pct(v: float) -> void:
	volume_pct = clampf(v, 0.0, 100.0)
	_apply()
	_save_settings()


func _apply() -> void:
	_ensure_bus()
	var idx: int = AudioServer.get_bus_index(String(BUS_NAME))
	if idx < 0:
		return
	var linear: float = clampf(volume_pct / 100.0, 0.0, 1.0)
	if not enabled or linear <= 0.0001:
		AudioServer.set_bus_mute(idx, true)
		AudioServer.set_bus_volume_db(idx, -80.0)
		if _player and _player.playing:
			_player.stop()
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	if _player and _player.stream and not _player.playing:
		_player.play()


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(String(BUS_NAME)) >= 0:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, String(BUS_NAME))
	AudioServer.set_bus_send(idx, "Master")


func _load_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	enabled = TypedVariant.as_bool(cf.get_value("audio", "bgm_enabled", false), false)
	volume_pct = TypedVariant.as_float(cf.get_value("audio", "bgm_volume", 60.0), 60.0)
	volume_pct = clampf(volume_pct, 0.0, 100.0)


func _save_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	cf.load(SETTINGS_PATH)  # keep other sections if any
	cf.set_value("audio", "bgm_enabled", enabled)
	cf.set_value("audio", "bgm_volume", volume_pct)
	cf.save(SETTINGS_PATH)
