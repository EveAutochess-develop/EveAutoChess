extends Node3D
## Echoes generic ship-death FX for the titan kill preview.
##
## Cutout atlases (explosion_005 / fire_01_yd) are played as 2D sequences on
## planes that cross the hull volume at different angles and depths, never
## camera-facing billboards. Volume, ring wave and debris come from the real
## Echoes meshes under mesh/. Every layer advances a single monotonic timeline
## and is retired at the end of its window: nothing replays inside one kill.
##
## Audio is TQ Wwise material decoded to PCM16; clips play once at their
## natural length and are never pitched or looped to fit the animation.

const TEX_DIR := "res://assets/vfx/ship_death_echoes/tex/"
const MESH_DIR := "res://assets/vfx/ship_death_echoes/mesh/"
const AUDIO_DIR := "res://assets/vfx/ship_death_echoes/audio/pcm/"

## Explode-phase boom: 2.14s clip against the 2.4s window, so no stretching.
const AUDIO_BOOM := "456431810_shipSFX1.wav"
const AUDIO_WRECK := "953482009_fire_wreck.wav"
const AUDIO_SPARK := [
	"229896555_wreck_spark1.wav",
	"908083863_wreck_spark2.wav",
	"740572395_wreck_spark3.wav",
]

## Cutout sheets: stem, quad size, local position, euler rotation, window, peak alpha.
const SHEETS := [
	{
		"stem": "explosion_005",
		"size": 15.0,
		"pos": Vector3(0.0, 0.35, 0.0),
		"rot": Vector3(16.0, 34.0, -9.0),
		"from": 0.0,
		"to": 0.52,
		"alpha": 1.0,
	},
	{
		"stem": "fire_01_yd",
		"size": 7.0,
		"pos": Vector3(-2.6, -0.35, 1.1),
		"rot": Vector3(-22.0, -48.0, 12.0),
		"from": 0.16,
		"to": 0.74,
		"alpha": 0.42,
	},
	{
		"stem": "fire_01_yd",
		"size": 5.6,
		"pos": Vector3(2.9, 0.55, -1.4),
		"rot": Vector3(27.0, 61.0, -17.0),
		"from": 0.3,
		"to": 0.9,
		"alpha": 0.3,
	},
]

## Echoes meshes: file, tint, rotation, window, scale range, peak alpha.
const VOLUMES := [
	{
		"glb": "fx_kuosanhuan_04.glb",
		"tex": "caustic_13.png",
		"color": Color(1.0, 0.34, 0.06),
		"rot": Vector3(62.0, 21.0, -14.0),
		"from": 0.04,
		"to": 0.66,
		"scale_from": 0.002,
		"scale_to": 0.03,
		"alpha": 0.8,
		"spin": 26.0,
	},
	{
		"glb": "fx_huoyan_09.glb",
		"tex": "noise_01_m2_pmwo.png",
		"color": Color(1.0, 0.52, 0.16),
		"rot": Vector3(8.0, 128.0, 23.0),
		"from": 0.06,
		"to": 0.82,
		"scale_from": 0.012,
		"scale_to": 0.062,
		"alpha": 0.62,
		"spin": -9.0,
	},
	{
		"glb": "fx_lizi_01.glb",
		"tex": "crystaldebris_01_d.png",
		"color": Color(1.0, 0.72, 0.42),
		"rot": Vector3(-14.0, 44.0, 8.0),
		"from": 0.08,
		"to": 0.95,
		"scale_from": 0.001,
		"scale_to": 0.0085,
		"alpha": 0.5,
		"spin": 5.0,
	},
]

## Wreck ambience uses a fire volume, not a replayed explosion sequence.
const WRECK_EMBER := {
	"glb": "fx_huoyan_08.glb",
	"tex": "noise_01_m2_pmwo.png",
	"color": Color(1.0, 0.4, 0.12),
	"rot": Vector3(4.0, 37.0, 11.0),
	"scale": 0.016,
}

var _sheets: Array = []
var _volumes: Array = []
var _ember: Dictionary = {}
var _sfx_boom: AudioStreamPlayer
var _sfx_wreck: AudioStreamPlayer
var _sfx_spark: AudioStreamPlayer
var _phase := ""
var _spark_cd := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for spec in SHEETS:
		var layer := _make_cutout_sheet(spec)
		if not layer.is_empty():
			_sheets.append(layer)
	for spec in VOLUMES:
		var vol := _make_volume(spec)
		if not vol.is_empty():
			_volumes.append(vol)
	_ember = _make_volume(WRECK_EMBER)
	_sfx_boom = _add_player(-5.0)
	_sfx_wreck = _add_player(-11.0)
	_sfx_spark = _add_player(-13.0)
	_hide_all()


func apply_phase(phase: String, explode_amt: float, active: bool) -> void:
	if not active:
		if _phase != "":
			_hide_all()
			_stop_audio()
			_phase = ""
		return
	match phase:
		"intact":
			if _phase != "intact":
				_hide_all()
				_stop_audio()
			_phase = "intact"
		"explode":
			if _phase != "explode":
				_hide_all()
				_stop_audio()
				_play_once(_sfx_boom, AUDIO_BOOM)
			_phase = "explode"
			_drive_explode(clampf(explode_amt, 0.0, 1.0))
		"wreck":
			if _phase != "wreck":
				_hide_all()
				_play_once(_sfx_wreck, AUDIO_WRECK)
				_spark_cd = 0.8
			_phase = "wreck"
			_drive_wreck()
		_:
			if _phase != phase:
				_hide_all()
				_stop_audio()
			_phase = phase


func _process(delta: float) -> void:
	if _phase != "wreck":
		return
	_spark_cd -= delta
	if _spark_cd <= 0.0 and _sfx_spark and not _sfx_spark.playing:
		_play_once(_sfx_spark, AUDIO_SPARK[_rng.randi_range(0, AUDIO_SPARK.size() - 1)])
		_spark_cd = _rng.randf_range(1.3, 2.2)


func _drive_explode(amt: float) -> void:
	for layer in _sheets:
		var u := _window_u(layer, amt)
		var mi: MeshInstance3D = layer["mi"]
		if u < 0.0:
			mi.visible = false
			continue
		mi.visible = true
		_set_sheet_frame(layer, u)
		_set_sheet_alpha(layer, float(layer["alpha"]) * _envelope(u))
		var grow: float = 0.72 + 0.5 * ease(u, 0.45)
		mi.scale = Vector3.ONE * grow

	for vol in _volumes:
		var vu := _window_u(vol, amt)
		var node: Node3D = vol["node"]
		if vu < 0.0:
			node.visible = false
			continue
		node.visible = true
		var s: float = lerpf(float(vol["scale_from"]), float(vol["scale_to"]), ease(vu, 0.5))
		node.scale = Vector3.ONE * s
		var base_rot: Vector3 = vol["rot"]
		node.rotation_degrees = base_rot + Vector3(0.0, float(vol["spin"]) * vu, 0.0)
		_set_volume_alpha(vol, float(vol["alpha"]) * _envelope(vu), vu)

	if not _ember.is_empty():
		(_ember["node"] as Node3D).visible = false


func _drive_wreck() -> void:
	for layer in _sheets:
		(layer["mi"] as MeshInstance3D).visible = false
	for vol in _volumes:
		(vol["node"] as Node3D).visible = false
	if _ember.is_empty():
		return
	var node: Node3D = _ember["node"]
	node.visible = true
	var t := float(Time.get_ticks_msec()) * 0.001
	node.scale = Vector3.ONE * float(WRECK_EMBER["scale"]) * (0.94 + 0.06 * sin(t * 2.1))
	var ember_rot: Vector3 = WRECK_EMBER["rot"]
	node.rotation_degrees = ember_rot + Vector3(0.0, t * 4.0, 0.0)
	_set_volume_alpha(_ember, 0.34 + 0.1 * sin(t * 3.3), fmod(t * 0.16, 1.0))


func _window_u(spec: Dictionary, amt: float) -> float:
	var t0 := float(spec["from"])
	var t1 := float(spec["to"])
	if amt < t0 or amt > t1 or t1 <= t0:
		return -1.0
	return (amt - t0) / (t1 - t0)


func _envelope(u: float) -> float:
	## Fade in fast, hold, fade out; keeps a layer from popping when retired.
	return clampf(minf(u / 0.12, (1.0 - u) / 0.22), 0.0, 1.0)


func _make_cutout_sheet(spec: Dictionary) -> Dictionary:
	var stem := str(spec["stem"])
	var png_path := TEX_DIR + stem + ".png"
	var json_path := TEX_DIR + stem + ".spr.json"
	if not ResourceLoader.exists(png_path) or not FileAccess.file_exists(json_path):
		push_warning("EchoesShipDeathFx: missing atlas %s" % stem)
		return {}
	var tex := load(png_path) as Texture2D
	var raw_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if tex == null or not (raw_v is Dictionary):
		push_warning("EchoesShipDeathFx: bad atlas data %s" % stem)
		return {}
	var raw: Dictionary = raw_v
	var rects: Array[Rect2] = []
	for fr in raw.get("frames", []):
		if not (fr is Dictionary):
			continue
		var x0 := float(fr.get("x0", 0))
		var y0 := float(fr.get("y0", 0))
		var x1 := float(fr.get("x1", 0))
		var y1 := float(fr.get("y1", 0))
		rects.append(Rect2(x0, y0, maxf(1.0, x1 - x0), maxf(1.0, y1 - y0)))
	if rects.is_empty():
		return {}

	var quad := QuadMesh.new()
	var size := float(spec["size"])
	quad.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = "Cutout_%s" % stem
	mi.mesh = quad
	mi.position = spec["pos"]
	mi.rotation_degrees = spec["rot"]
	mi.visible = false

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.albedo_texture = tex
	mat.texture_repeat = false
	mat.albedo_color = Color(1, 1, 1, 0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.2)
	mi.material_override = mat
	add_child(mi)

	var layer := {
		"mi": mi,
		"mat": mat,
		"frames": rects,
		"texture_size": Vector2(tex.get_width(), tex.get_height()),
		"alpha": float(spec["alpha"]),
		"from": float(spec["from"]),
		"to": float(spec["to"]),
	}
	_set_sheet_frame(layer, 0.0)
	return layer


func _set_sheet_frame(layer: Dictionary, u01: float) -> void:
	var frames: Array = layer["frames"]
	var n := frames.size()
	if n == 0:
		return
	var idx := clampi(int(floor(clampf(u01, 0.0, 0.9999) * float(n))), 0, n - 1)
	var rect: Rect2 = frames[idx]
	var tex_size: Vector2 = layer["texture_size"]
	## Half-pixel inset stops neighbouring atlas cells bleeding into the frame.
	var inset := Vector2(0.5, 0.5)
	var uv_pos := (rect.position + inset) / tex_size
	var uv_size := (rect.size - inset * 2.0).max(Vector2.ONE) / tex_size
	var mat: StandardMaterial3D = layer["mat"]
	mat.uv1_scale = Vector3(uv_size.x, uv_size.y, 1.0)
	mat.uv1_offset = Vector3(uv_pos.x, uv_pos.y, 0.0)


func _set_sheet_alpha(layer: Dictionary, a: float) -> void:
	var aa := clampf(a, 0.0, 1.0)
	var mat: StandardMaterial3D = layer["mat"]
	mat.albedo_color = Color(1, 1, 1, aa)
	mat.emission_energy_multiplier = 0.35 + 1.9 * aa


func _make_volume(spec: Dictionary) -> Dictionary:
	var path := MESH_DIR + str(spec["glb"])
	if not ResourceLoader.exists(path):
		push_warning("EchoesShipDeathFx: missing mesh %s" % spec["glb"])
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var node := packed.instantiate() as Node3D
	if node == null:
		return {}
	node.name = "Vol_%s" % str(spec["glb"]).get_basename()
	node.rotation_degrees = spec["rot"]
	node.visible = false

	var color: Color = spec["color"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mat.emission_enabled = true
	mat.emission = color
	var tex_path := TEX_DIR + str(spec.get("tex", ""))
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path) as Texture2D
	_override_materials(node, mat)
	add_child(node)
	var vol := {"node": node, "mat": mat}
	for key in ["from", "to", "scale_from", "scale_to", "alpha", "spin", "rot"]:
		if spec.has(key):
			vol[key] = spec[key]
	return vol


func _override_materials(root: Node, mat: Material) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = mat
	for child in root.get_children():
		_override_materials(child, mat)


func _set_volume_alpha(vol: Dictionary, a: float, scroll_u: float) -> void:
	var mat: StandardMaterial3D = vol["mat"]
	var aa := clampf(a, 0.0, 1.0)
	mat.albedo_color.a = aa
	mat.emission_energy_multiplier = 0.6 + 2.6 * aa
	mat.uv1_offset = Vector3(scroll_u * 0.24, -scroll_u * 0.15, 0.0)


func _hide_all() -> void:
	for layer in _sheets:
		var mi: MeshInstance3D = layer["mi"]
		mi.visible = false
		_set_sheet_alpha(layer, 0.0)
	for vol in _volumes:
		(vol["node"] as Node3D).visible = false
	if not _ember.is_empty():
		(_ember["node"] as Node3D).visible = false


func _add_player(volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.volume_db = volume_db
	add_child(p)
	return p


func _play_once(player: AudioStreamPlayer, file: String) -> void:
	if player == null:
		return
	var stream := _load_audio(AUDIO_DIR + file)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		## Play at recorded length: no looping, no pitch fitting.
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	player.stream = stream
	player.pitch_scale = 1.0
	player.play()


func _load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is AudioStream:
			return res as AudioStream
	return _load_pcm16_wav(path)


func _load_pcm16_wav(path: String) -> AudioStreamWAV:
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


func _stop_audio() -> void:
	for p in [_sfx_boom, _sfx_wreck, _sfx_spark]:
		if p:
			p.stop()
