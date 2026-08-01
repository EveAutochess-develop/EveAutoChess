extends Node
class_name WeaponFireSfx
## Play TQ turret SFX on each FiringFx shot. Pools by family×size; voice-limited.

const ROOT := "res://assets/audio/weapon_sfx/"
const MAX_VOICES := 10
const BASE_VOLUME_DB := -8.0

var _players: Array[AudioStreamPlayer] = []
## "family/size" -> PackedStringArray of res paths
var _pools: Dictionary = {}
var _rr: Dictionary = {}
var _stream_cache: Dictionary = {}

func setup() -> void:
	_build_pools()
	for i in range(MAX_VOICES):
		var p := AudioStreamPlayer.new()
		p.name = "WeaponSfx_%d" % i
		p.bus = "Master"
		p.volume_db = BASE_VOLUME_DB
		add_child(p)
		_players.append(p)

func play_for(firer: ShipUnit, kind: String) -> void:
	var k := str(kind).to_lower()
	if k == "mining" or k == "":
		return
	var family := _family_for_kind(k)
	if family == "":
		return
	var size := _size_bucket(firer, family)
	var path := _pick_path(family, size)
	if path == "":
		return
	var stream := _load_stream(path)
	if stream == null:
		return
	var player := _acquire_player()
	if player == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	player.stream = stream
	player.pitch_scale = 1.0
	player.volume_db = BASE_VOLUME_DB
	player.play()

func _family_for_kind(kind: String) -> String:
	match kind:
		"laser", "heal":
			return "laser"
		"rail":
			return "hybrid"
		"cannon":
			return "projectile"
		"missile":
			return "missile"
		_:
			return ""

func _size_bucket(firer: ShipUnit, family: String) -> String:
	var group := "frigate"
	if firer != null and is_instance_valid(firer):
		group = str(DataStore.get_ship(firer.ship_id).get("ship_group", "frigate")).to_lower()
	match group:
		"frigate", "destroyer", "drone_light", "drone_medium", "drone_heavy":
			return "small"
		"cruiser", "battlecruiser":
			return "medium"
		"battleship":
			return "large"
		"dreadnought", "carrier", "force_auxiliary", "capital_industrial", "titan", "freighter":
			if family == "missile":
				return "capital"
			if family == "laser":
				return "xlarge"
			return "large"
		_:
			return "medium"

func _pick_path(family: String, size: String) -> String:
	var order: Array[String] = [size]
	if size != "medium":
		order.append("medium")
	if size != "small":
		order.append("small")
	if size == "capital" or size == "xlarge":
		order.append("large")
	order.append("unk")
	for sz in order:
		var key := "%s/%s" % [family, sz]
		var paths: Array = _pools.get(key, []) as Array
		if paths.is_empty():
			continue
		var preferred: Array = []
		var fallback: Array = []
		for p in paths:
			var fname := str(p).get_file().to_lower()
			var is_impact := "impact" in fname and "outburst" not in fname and "fire" not in fname and "shot" not in fname
			if is_impact:
				fallback.append(p)
			elif "first_shot" in fname or "fire_" in fname or "_fire_" in fname or "outburst" in fname or "shot" in fname:
				preferred.append(p)
			else:
				fallback.append(p)
		var pool: Array = preferred if not preferred.is_empty() else fallback
		if pool.is_empty():
			continue
		var idx := int(_rr.get(key, 0))
		_rr[key] = (idx + 1) % pool.size()
		return str(pool[idx % pool.size()])
	## Last resort: any file in family
	for k in _pools.keys():
		if str(k).begins_with(family + "/"):
			var arr: Array = _pools[k] as Array
			if not arr.is_empty():
				return str(arr[0])
	return ""

func _acquire_player() -> AudioStreamPlayer:
	for p in _players:
		if p != null and not p.playing:
			return p
	## Steal oldest-finished-ish: first player
	if _players.is_empty():
		return null
	var steal := _players[0]
	steal.stop()
	return steal

func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is AudioStream:
			stream = res as AudioStream
	if stream == null:
		stream = _load_pcm16_wav(path)
	if stream != null:
		_stream_cache[path] = stream
	return stream

func _load_pcm16_wav(path: String) -> AudioStreamWAV:
	## Same fallback as death FX for WAVs Godot has not imported yet.
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data := f.get_buffer(f.get_length())
	if data.size() < 44 or data.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var i := 12
	var channels := 1
	var rate := 44100
	var pcm := PackedByteArray()
	while i + 8 <= data.size():
		var cid := data.slice(i, i + 4).get_string_from_ascii()
		var sz := data.decode_u32(i + 4)
		var body := i + 8
		if cid == "fmt " and sz >= 16:
			if data.decode_u16(body) != 1 or data.decode_u16(body + 14) != 16:
				return null
			channels = data.decode_u16(body + 2)
			rate = data.decode_u32(body + 4)
		elif cid == "data":
			pcm = data.slice(body, body + sz)
			break
		i = body + sz + (sz & 1)
	if pcm.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = channels >= 2
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm
	return wav

func _build_pools() -> void:
	_pools.clear()
	var root_dir := DirAccess.open(ROOT)
	if root_dir == null:
		push_warning("WeaponFireSfx: missing %s" % ROOT)
		return
	root_dir.list_dir_begin()
	var fam := root_dir.get_next()
	while fam != "":
		if root_dir.current_is_dir() and not fam.begins_with("."):
			_scan_family(fam)
		fam = root_dir.get_next()
	root_dir.list_dir_end()

func _scan_family(family: String) -> void:
	var fam_path := ROOT.path_join(family)
	var d := DirAccess.open(fam_path)
	if d == null:
		return
	d.list_dir_begin()
	var size_name := d.get_next()
	while size_name != "":
		if d.current_is_dir() and not size_name.begins_with("."):
			var key := "%s/%s" % [family, size_name]
			var files: Array = []
			var sd := DirAccess.open(fam_path.path_join(size_name))
			if sd:
				sd.list_dir_begin()
				var fn := sd.get_next()
				while fn != "":
					if not sd.current_is_dir() and fn.to_lower().ends_with(".wav"):
						files.append(fam_path.path_join(size_name).path_join(fn))
					fn = sd.get_next()
				sd.list_dir_end()
			files.sort()
			_pools[key] = files
		size_name = d.get_next()
	d.list_dir_end()
