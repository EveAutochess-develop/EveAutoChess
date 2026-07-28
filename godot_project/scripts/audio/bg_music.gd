extends Node
class_name BgMusic
## Content-side BGM host under /root/BgMusic (PCK cannot register Autoloads).
## Track: res://assets/audio/bgm/neo.ogg — loop; options: enable + 0..100 volume.

const NODE_NAME := &"BgMusic"
const STREAM_PATH := "res://assets/audio/bgm/neo.ogg"
const SETTINGS_PATH := "user://player_settings.cfg"
const BUS_NAME := &"BGM"
const _SELF := "res://scripts/audio/bg_music.gd"

var enabled: bool = false
var volume_pct: float = 60.0

var _player: AudioStreamPlayer


static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var existing := tree.root.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing:
		return existing
	# Avoid class_name .new() — global class cache may miss after load_resource_pack.
	var scr := load(_SELF) as GDScript
	if scr == null:
		return null
	var n: Node = scr.new()
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
		var stream := load(STREAM_PATH)
		if stream is AudioStream:
			if stream is AudioStreamOggVorbis:
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
	var idx := AudioServer.get_bus_index(String(BUS_NAME))
	if idx < 0:
		return
	var linear := clampf(volume_pct / 100.0, 0.0, 1.0)
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
	var master := AudioServer.get_bus_index("Master")
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, String(BUS_NAME))
	AudioServer.set_bus_send(idx, "Master" if master >= 0 else "Master")


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	enabled = bool(cf.get_value("audio", "bgm_enabled", false))
	volume_pct = float(cf.get_value("audio", "bgm_volume", 60.0))
	volume_pct = clampf(volume_pct, 0.0, 100.0)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)  # keep other sections if any
	cf.set_value("audio", "bgm_enabled", enabled)
	cf.set_value("audio", "bgm_volume", volume_pct)
	cf.save(SETTINGS_PATH)
