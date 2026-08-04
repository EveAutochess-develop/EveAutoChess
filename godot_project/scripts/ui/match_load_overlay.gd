extends CanvasLayer
class_name MatchLoadOverlay
## Full-screen black veil + bottom progress while entering a match
## (SEMI_ASYNC §3.7 · UI_AND_SHELL §1.2). Parent under /root to survive scene change.

static var _instance: MatchLoadOverlay

var _root_ctrl: Control
var _veil: ColorRect
var _panel: PanelContainer
var _bar: ProgressBar
var _label: Label
var _visible_wanted: bool = false


static func ensure() -> MatchLoadOverlay:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var loop_v: Variant = Engine.get_main_loop()
	if not (loop_v is SceneTree):
		return null
	var tree: SceneTree = loop_v
	if tree.root == null:
		return null
	var existing_n: Node = tree.root.get_node_or_null("MatchLoadOverlay")
	if existing_n is MatchLoadOverlay:
		_instance = existing_n
		return _instance
	var o: MatchLoadOverlay = MatchLoadOverlay.new()
	o.name = "MatchLoadOverlay"
	tree.root.add_child(o)
	_instance = o
	return _instance


static func set_phase(phase: String, progress: float) -> void:
	var o: MatchLoadOverlay = ensure()
	if o:
		o.apply(phase, progress)


static func hide_overlay() -> void:
	if _instance != null and is_instance_valid(_instance):
		_instance.hide_bar()
	var loop_v: Variant = Engine.get_main_loop()
	if loop_v is SceneTree:
		var tree: SceneTree = loop_v
		if tree.root:
			var existing_n: Node = tree.root.get_node_or_null("MatchLoadOverlay")
			if existing_n is MatchLoadOverlay:
				var existing: MatchLoadOverlay = existing_n
				existing.hide_bar()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = _visible_wanted


func _build() -> void:
	if _veil != null:
		return
	_root_ctrl = Control.new()
	_root_ctrl.name = "PassRoot"
	_root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Block clicks into half-loaded match / menu under the veil.
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root_ctrl)
	_veil = ColorRect.new()
	_veil.name = "BlackVeil"
	_veil.color = Color(0, 0, 0, 1)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_ctrl.add_child(_veil)
	_panel = PanelContainer.new()
	_panel.name = "BarPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 24.0
	_panel.offset_right = -24.0
	_panel.offset_top = -96.0
	_panel.offset_bottom = -24.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	sb.border_color = Color(0.35, 0.42, 0.52, 0.9)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_root_ctrl.add_child(_panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	_label = Label.new()
	_label.name = "PhaseLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = ""
	_label.modulate = Color(0.88, 0.92, 1.0, 1.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_label)
	_bar = ProgressBar.new()
	_bar.name = "Progress"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_bar)
	UiAssets.apply_label_font(_label, false, 18)


func apply(phase: String, progress: float) -> void:
	if _veil == null or _label == null or _bar == null:
		_build()
	_visible_wanted = true
	visible = true
	if _root_ctrl:
		_root_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	if _veil:
		_veil.visible = true
	if _label and phase != "":
		_label.text = phase
	if _bar:
		_bar.value = clampf(progress, 0.0, 1.0)


func hide_bar() -> void:
	_visible_wanted = false
	visible = false
	if _root_ctrl:
		_root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _veil:
		_veil.visible = false
	if _label:
		_label.text = ""
	if _bar:
		_bar.value = 0.0
