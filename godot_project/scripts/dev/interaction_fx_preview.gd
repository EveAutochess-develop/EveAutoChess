extends Node3D
## Dev gallery: replay interaction_fx recipe JSON via InteractionFxPlayer (COMBAT §8.4).

const InteractionFxPlayerScript = preload("res://scripts/combat/interaction_fx_player.gd")
const _REFIRE_S: float = 1.4
const _SAMPLE_RECIPES: Array[Dictionary] = [
	{
		"title": "dev hit_burst (no PNG)",
		"recipe_abs": "res://data/dev/interaction_fx_sample_recipe.json",
		"def": {
			"base": "burst_sprite",
			"style": "particle_billboard",
			"scale": 1.1,
			"color": [0.35, 0.85, 1.0, 1.0]
		}
	}
]

var _cam: Camera3D
var _anchor: Node3D
var _hud: Label
var _player: Node
var _selected: int = 0
var _refire_t: float = 0.0


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if DataStore != null and DataStore.has_method("reload_all"):
		DataStore.reload_all()
	_build_scene()
	_play_selected()


func _build_scene() -> void:
	var env_light: DirectionalLight3D = DirectionalLight3D.new()
	env_light.rotation_degrees = Vector3(-42, 35, 0)
	add_child(env_light)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -120, 0)
	fill.light_energy = 0.35
	add_child(fill)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(24, 24)
	ground.mesh = plane
	ground.position = Vector3(0, -0.05, 0)
	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.albedo_color = Color(0.08, 0.1, 0.14)
	ground.material_override = gmat
	add_child(ground)
	_anchor = Node3D.new()
	_anchor.name = "FxAnchor"
	_anchor.position = Vector3(0, 1.0, 0)
	add_child(_anchor)
	_player = InteractionFxPlayerScript.new()
	_player.name = "InteractionFxPlayer"
	add_child(_player)
	if _player.has_method("setup"):
		_player.call("setup", self)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 5.5, 9)
	_cam.look_at(_anchor.global_position, Vector3.UP)
	add_child(_cam)
	_hud = Label.new()
	_hud.name = "Hud"
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_bottom = 72
	_hud.add_theme_font_size_override("font_size", 14)
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.name = "UiLayer"
	add_child(ui_layer)
	ui_layer.add_child(_hud)
	_refresh_hud()


func _process(delta: float) -> void:
	_refire_t -= delta
	if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_F):
		_play_selected()
	if Input.is_action_just_pressed("ui_left"):
		_selected = (_selected - 1 + _SAMPLE_RECIPES.size()) % _SAMPLE_RECIPES.size()
		_refresh_hud()
		_play_selected()
	if Input.is_action_just_pressed("ui_right"):
		_selected = (_selected + 1) % _SAMPLE_RECIPES.size()
		_refresh_hud()
		_play_selected()
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
	if _refire_t <= 0.0:
		_refire_t = _REFIRE_S
		_play_selected()


func _refresh_hud() -> void:
	var item: Dictionary = _SAMPLE_RECIPES[_selected]
	_hud.text = "Interaction FX Preview · %s (%d/%d) · ←→ 切换 · Enter/F 重播 · Esc 退出" % [
		str(item.get("title", "?")),
		_selected + 1,
		_SAMPLE_RECIPES.size(),
	]


func _play_selected() -> void:
	var item: Dictionary = _SAMPLE_RECIPES[_selected]
	var def: Dictionary = TypedVariant.as_dict(item.get("def", {})).duplicate(true)
	def["recipe_abs"] = ProjectSettings.globalize_path(str(item.get("recipe_abs", "")))
	_player.call("play_burst", "weapon_hit", null, _anchor, def, -1.0)
