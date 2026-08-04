extends Node3D
## Flip through the nullsec region skies (NEW_EDEN_REGIONS §2): left/right or tap
## to step, so a staged panorama can be eyeballed without hosting a match.

var _ids: Array = []
var _idx: int = 0
var _label: Label = null
var _yaw: float = 0.0

func _ready() -> void:
	for r_v: Variant in SkyboxCatalog.nullsec_regions():
		if not (r_v is Dictionary):
			continue
		var r: Dictionary = r_v
		_ids.append(str(r.get("region_id", "")))
	_ids.sort()
	var cam: Camera3D = Camera3D.new()
	cam.name = "Cam"
	cam.current = true
	add_child(cam)
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.86
	we.environment = env
	add_child(we)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(_label)
	_apply()

func _process(delta: float) -> void:
	_yaw += delta * 0.12
	var cam: Camera3D = get_node_or_null("Cam") as Camera3D
	if cam:
		cam.rotation = Vector3(0.0, _yaw, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	var step: int = 0
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k: Key = (event as InputEventKey).keycode
		if k == KEY_RIGHT or k == KEY_SPACE:
			step = 1
		elif k == KEY_LEFT:
			step = -1
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		step = 1
	if step != 0 and not _ids.is_empty():
		_idx = (_idx + step + _ids.size()) % _ids.size()
		_apply()

func _apply() -> void:
	if _ids.is_empty():
		_label.text = "可分配星域池为空：先跑 tools/stage_region_skyboxes.py"
		return
	var rid: String = str(_ids[_idx])
	var tex: Texture2D = SkyboxCatalog.load_sky_texture(rid)
	var we: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and tex:
		var sky: Sky = Sky.new()
		var mat: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
		mat.panorama = tex
		sky.sky_material = mat
		we.environment.sky = sky
	_label.text = "%d/%d  %s  (%s)  own_sky=%s" % [
		_idx + 1, _ids.size(), SkyboxCatalog.display_name(rid), rid,
		str(SkyboxCatalog.has_own_sky(rid)),
	]
