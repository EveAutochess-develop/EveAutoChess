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

const TEX_DIR: String = "res://assets/vfx/ship_death_echoes/tex/"
const MESH_DIR: String = "res://assets/vfx/ship_death_echoes/mesh/"
const AUDIO_DIR: String = "res://assets/vfx/ship_death_echoes/audio/pcm/"

## Explode-phase boom: 2.14s clip against the 2.4s window, so no stretching.
const AUDIO_BOOM: String = "456431810_shipSFX1.wav"
const AUDIO_WRECK: String = "953482009_fire_wreck.wav"
const AUDIO_SPARK: Array[String] = [
	"229896555_wreck_spark1.wav",
	"908083863_wreck_spark2.wav",
	"740572395_wreck_spark3.wav",
]

## Cutout sheets: stem, quad size, local position, euler rotation, window, peak alpha.
const SHEETS: Array[Dictionary] = [
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
const VOLUMES: Array[Dictionary] = [
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
const WRECK_EMBER: Dictionary = {
	"glb": "fx_huoyan_08.glb",
	"tex": "noise_01_m2_pmwo.png",
	"color": Color(1.0, 0.4, 0.12),
	"rot": Vector3(4.0, 37.0, 11.0),
	"scale": 0.016,
}

var _sheets: Array[Dictionary] = []
var _volumes: Array[Dictionary] = []
var _ember: Dictionary = {}
var _sfx_boom: AudioStreamPlayer
var _sfx_wreck: AudioStreamPlayer
var _sfx_spark: AudioStreamPlayer
var _phase: String = ""
var _spark_cd: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for spec: Dictionary in SHEETS:
		var layer: Dictionary = _make_cutout_sheet(spec)
		if not layer.is_empty():
			_sheets.append(layer)
	for spec: Dictionary in VOLUMES:
		var vol: Dictionary = _make_volume(spec)
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
	for layer: Dictionary in _sheets:
		var u: float = _window_u(layer, amt)
		var mi_v: Variant = layer.get("mi")
		if not (mi_v is MeshInstance3D):
			continue
		var mi: MeshInstance3D = mi_v
		if u < 0.0:
			mi.visible = false
			continue
		mi.visible = true
		_set_sheet_frame(layer, u)
		_set_sheet_alpha(layer, TypedVariant.as_float(layer.get("alpha", 0.0)) * _envelope(u))
		var grow: float = 0.72 + 0.5 * ease(u, 0.45)
		mi.scale = Vector3.ONE * grow

	for vol: Dictionary in _volumes:
		var vu: float = _window_u(vol, amt)
		var node_v: Variant = vol.get("node")
		if not (node_v is Node3D):
			continue
		var node: Node3D = node_v
		if vu < 0.0:
			node.visible = false
			continue
		node.visible = true
		var s: float = lerpf(
			TypedVariant.as_float(vol.get("scale_from", 0.0)),
			TypedVariant.as_float(vol.get("scale_to", 0.0)),
			ease(vu, 0.5),
		)
		node.scale = Vector3.ONE * s
		var base_rot_v: Variant = vol.get("rot")
		var base_rot: Vector3 = base_rot_v if base_rot_v is Vector3 else Vector3.ZERO
		node.rotation_degrees = base_rot + Vector3(0.0, TypedVariant.as_float(vol.get("spin", 0.0)) * vu, 0.0)
		_set_volume_alpha(vol, TypedVariant.as_float(vol.get("alpha", 0.0)) * _envelope(vu), vu)

	if not _ember.is_empty():
		var ember_node_v: Variant = _ember.get("node")
		if ember_node_v is Node3D:
			var ember_node: Node3D = ember_node_v
			ember_node.visible = false


func _drive_wreck() -> void:
	for layer: Dictionary in _sheets:
		var mi_v: Variant = layer.get("mi")
		if mi_v is MeshInstance3D:
			var mi: MeshInstance3D = mi_v
			mi.visible = false
	for vol: Dictionary in _volumes:
		var node_v: Variant = vol.get("node")
		if node_v is Node3D:
			var node: Node3D = node_v
			node.visible = false
	if _ember.is_empty():
		return
	var ember_node_v: Variant = _ember.get("node")
	if not (ember_node_v is Node3D):
		return
	var node: Node3D = ember_node_v
	node.visible = true
	var t: float = float(Time.get_ticks_msec()) * 0.001
	node.scale = Vector3.ONE * TypedVariant.as_float(WRECK_EMBER.get("scale", 0.0)) * (0.94 + 0.06 * sin(t * 2.1))
	var ember_rot_v: Variant = WRECK_EMBER.get("rot")
	var ember_rot: Vector3 = ember_rot_v if ember_rot_v is Vector3 else Vector3.ZERO
	node.rotation_degrees = ember_rot + Vector3(0.0, t * 4.0, 0.0)
	_set_volume_alpha(_ember, 0.34 + 0.1 * sin(t * 3.3), fmod(t * 0.16, 1.0))


func _window_u(spec: Dictionary, amt: float) -> float:
	var t0: float = TypedVariant.as_float(spec.get("from", 0.0))
	var t1: float = TypedVariant.as_float(spec.get("to", 0.0))
	if amt < t0 or amt > t1 or t1 <= t0:
		return -1.0
	return (amt - t0) / (t1 - t0)


func _envelope(u: float) -> float:
	## Fade in fast, hold, fade out; keeps a layer from popping when retired.
	return clampf(minf(u / 0.12, (1.0 - u) / 0.22), 0.0, 1.0)


func _make_cutout_sheet(spec: Dictionary) -> Dictionary:
	var stem: String = str(spec.get("stem", ""))
	var png_path: String = TEX_DIR + stem + ".png"
	var json_path: String = TEX_DIR + stem + ".spr.json"
	if not ResourceLoader.exists(png_path) or not FileAccess.file_exists(json_path):
		push_warning("EchoesShipDeathFx: missing atlas %s" % stem)
		return {}
	var tex_v: Variant = load(png_path)
	if not (tex_v is Texture2D):
		push_warning("EchoesShipDeathFx: bad atlas data %s" % stem)
		return {}
	var tex: Texture2D = tex_v
	var raw_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (raw_v is Dictionary):
		push_warning("EchoesShipDeathFx: bad atlas data %s" % stem)
		return {}
	var raw: Dictionary = raw_v
	var rects: Array[Rect2] = []
	for fr_v: Variant in TypedVariant.as_array(raw.get("frames", [])):
		if not (fr_v is Dictionary):
			continue
		var fr: Dictionary = fr_v
		var x0: float = TypedVariant.as_float(fr.get("x0", 0))
		var y0: float = TypedVariant.as_float(fr.get("y0", 0))
		var x1: float = TypedVariant.as_float(fr.get("x1", 0))
		var y1: float = TypedVariant.as_float(fr.get("y1", 0))
		rects.append(Rect2(x0, y0, maxf(1.0, x1 - x0), maxf(1.0, y1 - y0)))
	if rects.is_empty():
		return {}

	var quad: QuadMesh = QuadMesh.new()
	var size: float = TypedVariant.as_float(spec.get("size", 0.0))
	quad.size = Vector2(size, size)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Cutout_%s" % stem
	mi.mesh = quad
	var pos_v: Variant = spec.get("pos")
	if pos_v is Vector3:
		mi.position = pos_v
	var rot_v: Variant = spec.get("rot")
	if rot_v is Vector3:
		mi.rotation_degrees = rot_v
	mi.visible = false

	var mat: StandardMaterial3D = StandardMaterial3D.new()
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

	var layer: Dictionary = {
		"mi": mi,
		"mat": mat,
		"frames": rects,
		"texture_size": Vector2(tex.get_width(), tex.get_height()),
		"alpha": TypedVariant.as_float(spec.get("alpha", 0.0)),
		"from": TypedVariant.as_float(spec.get("from", 0.0)),
		"to": TypedVariant.as_float(spec.get("to", 0.0)),
	}
	_set_sheet_frame(layer, 0.0)
	return layer


func _set_sheet_frame(layer: Dictionary, u01: float) -> void:
	var frames_v: Variant = layer.get("frames")
	if not (frames_v is Array):
		return
	var frames: Array = frames_v
	var n: int = frames.size()
	if n == 0:
		return
	var idx: int = clampi(floori(clampf(u01, 0.0, 0.9999) * float(n)), 0, n - 1)
	var rect_v: Variant = frames[idx]
	if not (rect_v is Rect2):
		return
	var rect: Rect2 = rect_v
	var tex_size_v: Variant = layer.get("texture_size")
	if not (tex_size_v is Vector2):
		return
	var tex_size: Vector2 = tex_size_v
	## Half-pixel inset stops neighbouring atlas cells bleeding into the frame.
	var inset: Vector2 = Vector2(0.5, 0.5)
	var uv_pos: Vector2 = (rect.position + inset) / tex_size
	var uv_size: Vector2 = (rect.size - inset * 2.0).max(Vector2.ONE) / tex_size
	var mat_v: Variant = layer.get("mat")
	if not (mat_v is StandardMaterial3D):
		return
	var mat: StandardMaterial3D = mat_v
	mat.uv1_scale = Vector3(uv_size.x, uv_size.y, 1.0)
	mat.uv1_offset = Vector3(uv_pos.x, uv_pos.y, 0.0)


func _set_sheet_alpha(layer: Dictionary, a: float) -> void:
	var aa: float = clampf(a, 0.0, 1.0)
	var mat_v: Variant = layer.get("mat")
	if not (mat_v is StandardMaterial3D):
		return
	var mat: StandardMaterial3D = mat_v
	mat.albedo_color = Color(1, 1, 1, aa)
	mat.emission_energy_multiplier = 0.35 + 1.9 * aa


func _make_volume(spec: Dictionary) -> Dictionary:
	var path: String = MESH_DIR + str(spec.get("glb", ""))
	if not ResourceLoader.exists(path):
		push_warning("EchoesShipDeathFx: missing mesh %s" % spec.get("glb", ""))
		return {}
	var packed_v: Variant = load(path)
	if not (packed_v is PackedScene):
		return {}
	var packed: PackedScene = packed_v
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		return {}
	var node: Node3D = inst
	node.name = "Vol_%s" % str(spec.get("glb", "")).get_basename()
	var spec_rot_v: Variant = spec.get("rot")
	if spec_rot_v is Vector3:
		node.rotation_degrees = spec_rot_v
	node.visible = false

	var color_v: Variant = spec.get("color")
	var color: Color = color_v if color_v is Color else Color.WHITE
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mat.emission_enabled = true
	mat.emission = color
	var tex_path: String = TEX_DIR + str(spec.get("tex", ""))
	if ResourceLoader.exists(tex_path):
		var tex_v: Variant = load(tex_path)
		if tex_v is Texture2D:
			mat.albedo_texture = tex_v
	_override_materials(node, mat)
	add_child(node)
	var vol: Dictionary = {"node": node, "mat": mat}
	for key: String in ["from", "to", "scale_from", "scale_to", "alpha", "spin", "rot"]:
		if spec.has(key):
			vol[key] = spec[key]
	return vol


func _override_materials(root: Node, mat: Material) -> void:
	if root is MeshInstance3D:
		var mesh_i: MeshInstance3D = root
		mesh_i.material_override = mat
	for child: Node in root.get_children():
		_override_materials(child, mat)


func _set_volume_alpha(vol: Dictionary, a: float, scroll_u: float) -> void:
	var mat_v: Variant = vol.get("mat")
	if not (mat_v is StandardMaterial3D):
		return
	var mat: StandardMaterial3D = mat_v
	var aa: float = clampf(a, 0.0, 1.0)
	mat.albedo_color.a = aa
	mat.emission_energy_multiplier = 0.6 + 2.6 * aa
	mat.uv1_offset = Vector3(scroll_u * 0.24, -scroll_u * 0.15, 0.0)


func _hide_all() -> void:
	for layer: Dictionary in _sheets:
		var mi_v: Variant = layer.get("mi")
		if mi_v is MeshInstance3D:
			var mi: MeshInstance3D = mi_v
			mi.visible = false
			_set_sheet_alpha(layer, 0.0)
	for vol: Dictionary in _volumes:
		var node_v: Variant = vol.get("node")
		if node_v is Node3D:
			var node: Node3D = node_v
			node.visible = false
	if not _ember.is_empty():
		var ember_node_v: Variant = _ember.get("node")
		if ember_node_v is Node3D:
			var ember_node: Node3D = ember_node_v
			ember_node.visible = false


func _add_player(volume_db: float) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	SfxBus.route(p)
	p.set_meta("sfx_base_db", volume_db)
	p.volume_db = volume_db
	add_child(p)
	return p


func _play_once(player: AudioStreamPlayer, file: String) -> void:
	if player == null:
		return
	var stream: AudioStream = _load_audio(AUDIO_DIR + file)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		## Play at recorded length: no looping, no pitch fitting.
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	player.stream = stream
	player.pitch_scale = 1.0
	var base_db: float = TypedVariant.as_float(player.get_meta("sfx_base_db", 0.0), 0.0)
	SfxBus.begin_play(player, base_db)
	player.play()


func _load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is AudioStream:
			var audio: AudioStream = res
			return audio
	return _load_pcm16_wav(path)


func _load_pcm16_wav(path: String) -> AudioStreamWAV:
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


func _stop_audio() -> void:
	for p: AudioStreamPlayer in [_sfx_boom, _sfx_wreck, _sfx_spark]:
		if p:
			SfxBus.end_play(p)
			p.stop()
