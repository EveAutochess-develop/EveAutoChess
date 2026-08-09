extends Node
class_name WeaponFireSfx
## Play TQ turret SFX on each FiringFx shot. Pools by family×size; voice-limited.

const ROOT: String = "res://assets/audio/weapon_sfx/"
const MAX_VOICES: int = 10
const BASE_VOLUME_DB: float = -2.0

var _players: Array[AudioStreamPlayer] = []
## "family/size" -> PackedStringArray of res paths
var _pools: Dictionary = {}
var _rr: Dictionary = {}
var _stream_cache: Dictionary = {}
var _logged_empty: bool = false
var _load_fail_logs: int = 0
var _last_load_fail_ms: int = 0

func setup() -> void:
	_build_pools()
	_probe_and_heal_pools()
	SfxBus.ensure()
	for i: int in range(MAX_VOICES):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "WeaponSfx_%d" % i
		SfxBus.route(p)
		p.volume_db = BASE_VOLUME_DB
		add_child(p)
		_players.append(p)

func play_for(firer: Node, kind: String) -> void:
	## Keep SFX even when no_model_perf suppresses beam VFX (COMBAT §8.1).
	var k: String = str(kind).to_lower()
	## mining + function-bucket beams: silent (COMBAT §8.1 / §8.2)
	if k == "mining" or k == "" or k in [
			"nos", "neut", "remote_cap", "sensor_damp",
			"tracking_disrupt", "guidance_disrupt", "target_painter"]:
		return
	var family: String = _family_for_kind(k)
	if family == "":
		return
	if _pools.is_empty():
		_build_pools()
		_probe_and_heal_pools()
	if _pools.is_empty() and not _logged_empty:
		_logged_empty = true
		push_warning("WeaponFireSfx: empty pools — catalog/DirAccess failed")
		if SessionDiagnostics != null:
			SessionDiagnostics.log("sfx.weapon", "empty_pools kind=%s" % k)
	var size: String = _size_bucket(firer, family)
	var path: String = _pick_path(family, size)
	if path == "":
		if SessionDiagnostics != null:
			SessionDiagnostics.log("sfx.weapon", "no_path family=%s size=%s kind=%s" % [family, size, k])
		return
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		_log_load_fail(path)
		return
	var player: AudioStreamPlayer = _acquire_player()
	if player == null:
		return
	if stream is AudioStreamWAV:
		@warning_ignore("unsafe_cast")
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	player.stream = stream
	player.pitch_scale = 1.0
	SfxBus.begin_play(player, BASE_VOLUME_DB)
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

func _size_bucket(firer: Node, family: String) -> String:
	var group: String = "frigate"
	if firer != null and is_instance_valid(firer):
		var ship_id: int = TypedVariant.as_int(firer.get("ship_id"), 0)
		group = str(DataStore.get_ship(ship_id).get("ship_group", "frigate")).to_lower()
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
	for sz: String in order:
		var key: String = "%s/%s" % [family, sz]
		var paths: Array = TypedVariant.as_array(_pools.get(key, []))
		if paths.is_empty():
			continue
		var preferred: Array = []
		var fallback: Array = []
		for p: Variant in paths:
			var fname: String = str(p).get_file().to_lower()
			var is_impact: bool = "impact" in fname and "outburst" not in fname and "fire" not in fname and "shot" not in fname
			if is_impact:
				fallback.append(p)
			elif "first_shot" in fname or "fire_" in fname or "_fire_" in fname or "outburst" in fname or "shot" in fname:
				preferred.append(p)
			else:
				fallback.append(p)
		var pool: Array = preferred if not preferred.is_empty() else fallback
		if pool.is_empty():
			continue
		var idx: int = TypedVariant.as_int(_rr.get(key, 0))
		_rr[key] = (idx + 1) % pool.size()
		return str(pool[idx % pool.size()])
	## Last resort: any file in family
	for k: Variant in _pools.keys():
		if str(k).begins_with(family + "/"):
			var arr: Array = TypedVariant.as_array(_pools[k])
			if not arr.is_empty():
				return str(arr[0])
	return ""

func _acquire_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _players:
		if p != null and not p.playing:
			return p
	## Steal oldest-finished-ish: first player
	if _players.is_empty():
		return null
	var steal: AudioStreamPlayer = _players[0]
	SfxBus.end_play(steal)
	steal.stop()
	return steal

func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		var cached: Variant = _stream_cache[path]
		if cached is AudioStream:
			@warning_ignore("unsafe_cast")
			return cached as AudioStream
		return null
	var stream: AudioStream = null
	## Prefer ResourceLoader even when exists() is false (exported remap edge cases).
	var res: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is AudioStream:
		@warning_ignore("unsafe_cast")
		stream = res as AudioStream
	if stream == null and ResourceLoader.exists(path):
		var res2: Variant = load(path)
		if res2 is AudioStream:
			@warning_ignore("unsafe_cast")
			stream = res2 as AudioStream
	if stream == null:
		stream = _load_pcm16_wav(path)
	if stream != null:
		_stream_cache[path] = stream
	else:
		## Cache miss as null sentinel so we don't spam load each shot.
		_stream_cache[path] = null
	return stream

func _load_pcm16_wav(path: String) -> AudioStreamWAV:
	## Same fallback as death FX for WAVs Godot has not imported yet.
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data: PackedByteArray = f.get_buffer(f.get_length())
	if data.size() < 44 or data.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var i: int = 12
	var channels: int = 1
	var rate: int = 44100
	var pcm: PackedByteArray = PackedByteArray()
	while i + 8 <= data.size():
		var cid: String = data.slice(i, i + 4).get_string_from_ascii()
		var sz: int = data.decode_u32(i + 4)
		var body: int = i + 8
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
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = channels >= 2
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm
	return wav

func _log_load_fail(path: String) -> void:
	var now: int = Time.get_ticks_msec()
	if _load_fail_logs >= 8 and now - _last_load_fail_ms < 5000:
		return
	_load_fail_logs += 1
	_last_load_fail_ms = now
	if SessionDiagnostics != null:
		SessionDiagnostics.log(
			"sfx.weapon",
			"load_fail path=%s exists=%d fa=%d" % [
				path.get_file(),
				1 if ResourceLoader.exists(path) else 0,
				1 if FileAccess.file_exists(path) else 0,
			]
		)

func _probe_and_heal_pools() -> void:
	var n: int = 0
	for k: Variant in _pools.keys():
		n += TypedVariant.as_array(_pools[k]).size()
	var sample: String = ""
	var sample_ok: int = 0
	if n > 0:
		for k2: Variant in _pools.keys():
			var arr: Array = TypedVariant.as_array(_pools[k2])
			if arr.is_empty():
				continue
			sample = str(arr[0])
			break
		if sample != "":
			var probe: AudioStream = _load_stream(sample)
			sample_ok = 1 if probe != null else 0
			if probe == null:
				## Catalog paths present but unloadable (audio.pck missing) — try DirAccess.
				_pools.clear()
				_stream_cache.clear()
				_scan_dir_pools()
				n = 0
				for k3: Variant in _pools.keys():
					n += TypedVariant.as_array(_pools[k3]).size()
				if n > 0:
					sample = ""
					for k4: Variant in _pools.keys():
						var arr2: Array = TypedVariant.as_array(_pools[k4])
						if arr2.is_empty():
							continue
						sample = str(arr2[0])
						break
					if sample != "":
						sample_ok = 1 if _load_stream(sample) != null else 0
	var root_open: int = 1 if DirAccess.open(ROOT) != null else 0
	if SessionDiagnostics != null:
		SessionDiagnostics.log(
			"sfx.weapon",
			"pools_n=%d sample_ok=%d root_dir=%d sample=%s" % [
				n, sample_ok, root_open, sample.get_file() if sample != "" else "-"
			]
		)
	if n == 0 or sample_ok == 0:
		push_warning(
			"WeaponFireSfx: audio mount/load weak pools_n=%d sample_ok=%d (need packs/audio.pck)" % [n, sample_ok]
		)

func _build_pools() -> void:
	_pools.clear()
	if _load_catalog():
		return
	_scan_dir_pools()

func _load_catalog() -> bool:
	## COMBAT §8.1 — baked paths survive exported PCK. Prefer Array values (PSA broke pools_n=0 on install).
	var d: Dictionary = WeaponSfxCatalog.pools()
	if d.is_empty():
		return false
	var n: int = 0
	for k: Variant in d.keys():
		var files: Array = _string_paths_from_pool(d[k])
		if files.is_empty():
			continue
		files.sort()
		_pools[str(k)] = files
		n += files.size()
	return n > 0


func _string_paths_from_pool(v: Variant) -> Array:
	var out: Array = []
	if v is PackedStringArray:
		var psa: PackedStringArray = v
		for i: int in range(psa.size()):
			_append_sfx_path(out, str(psa[i]))
		return out
	var arr: Array = TypedVariant.as_array(v)
	for p: Variant in arr:
		_append_sfx_path(out, str(p))
	return out


func _append_sfx_path(out: Array, path: String) -> void:
	var p: String = path.strip_edges()
	if p.is_empty():
		return
	var low: String = p.to_lower()
	if low.ends_with(".ogg") or low.ends_with(".wav"):
		out.append(p)


func _scan_dir_pools() -> void:
	var root_dir: DirAccess = DirAccess.open(ROOT)
	if root_dir == null:
		push_warning("WeaponFireSfx: missing %s" % ROOT)
		return
	root_dir.list_dir_begin()
	var fam: String = root_dir.get_next()
	while fam != "":
		if root_dir.current_is_dir() and not fam.begins_with("."):
			_scan_family(fam)
		fam = root_dir.get_next()
	root_dir.list_dir_end()

func _scan_family(family: String) -> void:
	var fam_path: String = ROOT.path_join(family)
	var d: DirAccess = DirAccess.open(fam_path)
	if d == null:
		return
	d.list_dir_begin()
	var size_name: String = d.get_next()
	while size_name != "":
		if d.current_is_dir() and not size_name.begins_with("."):
			var key: String = "%s/%s" % [family, size_name]
			var files: Array = []
			var sd: DirAccess = DirAccess.open(fam_path.path_join(size_name))
			if sd:
				sd.list_dir_begin()
				var fn: String = sd.get_next()
				while fn != "":
					if not sd.current_is_dir():
						var asset: String = _strip_godot_sidecar(fn)
						var low: String = asset.to_lower()
						if low.ends_with(".ogg") or low.ends_with(".wav"):
							files.append(fam_path.path_join(size_name).path_join(asset))
					fn = sd.get_next()
				sd.list_dir_end()
			## Do not insert empty keys — they make _pools non-empty while play still no_path.
			if not files.is_empty():
				files.sort()
				_pools[key] = files
		size_name = d.get_next()
	d.list_dir_end()

func _strip_godot_sidecar(fn: String) -> String:
	## Exported PCK DirAccess often yields `foo.ogg.remap` instead of `foo.ogg`.
	var n: String = fn
	if n.ends_with(".remap"):
		n = n.substr(0, n.length() - 6)
	if n.ends_with(".import"):
		return ""
	return n
