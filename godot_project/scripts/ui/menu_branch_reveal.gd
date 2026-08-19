extends RefCounted
## Two-phase reveal: (1) solid accelerating slide 0.15s; (2) mind-map link + wipe secondary (0.3–0.5s by width).
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

## UI_AND_SHELL §1.0a. Slide must finish before secondary / link appear.
const SLIDE_DUR_S: float = 0.15
const WIPE_DUR_MIN_S: float = 0.3
const WIPE_DUR_MAX_S: float = 0.5
## px/s so typical L2 (~360) ≈ 0.3s and wide L2/L3 (~600+) clamp at 0.5s.
const WIPE_PX_PER_S: float = 1200.0
const LINK_DRAW_S: float = 0.12
const SLIDE_FRAC: float = 0.25
const LINE_W: float = 3.0
const TRAIL_W: float = 28.0
const LINK_W: float = 2.0

var _tween: Tween
var _clip: Control
var _trail: ColorRect
var _line: ColorRect
var _link: Control
var _host: Control
var _primary: Control
var _content: Control
var _tree: SceneTree
var _primary_base_x: float = 0.0
var _host_w: float = 1.0
var _host_h: float = 1.0
var _running: bool = false
## Optional: e.g. tertiary slides 「读取存档」→ lengthen solo→btn mindmap line.
var on_slide_step: Callable = Callable()
## Optional: after wipe finishes (content restored).
var on_finished: Callable = Callable()

func is_running() -> bool:
	return _running

func abort() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	_running = false
	_restore_content()
	_clear_fx()
	_clear_link()
	if _primary != null and is_instance_valid(_primary):
		_primary.modulate = Color.WHITE
		if _primary.has_method("set_slide_offset_px"):
			_primary.call("set_slide_offset_px", 0.0)
		if _primary.has_method("set_reveal_progress"):
			_primary.call("set_reveal_progress", 1.0)
		_primary.position.x = _primary_base_x
	_tree = null

func _restore_content() -> void:
	if _content != null and is_instance_valid(_content) and _host != null and is_instance_valid(_host):
		if _content.get_parent() != _host:
			var keep: Control = _content
			keep.get_parent().remove_child(keep)
			_host.add_child(keep)
			_host.move_child(keep, 0)
		_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_content.position = Vector2.ZERO
		_content.size = Vector2(_host_w, _host_h)
	_content = null

func _clear_fx() -> void:
	if _clip != null and is_instance_valid(_clip):
		_clip.queue_free()
	if _trail != null and is_instance_valid(_trail):
		_trail.queue_free()
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_clip = null
	_trail = null
	_line = null

func _clear_link() -> void:
	if _link != null and is_instance_valid(_link):
		_link.queue_free()
	_link = null

func play(tree: SceneTree, primary: Control, host: Control, _mask_color: Color = Color(0, 0, 0, 0)) -> void:
	abort()
	if tree == null or primary == null or host == null:
		return
	_tree = tree
	_primary = primary
	_host = host
	_primary_base_x = primary.position.x
	_running = true
	## Solid slide — no fade (UI_AND_SHELL §1.0a).
	primary.modulate = Color.WHITE
	if primary.has_method("set_reveal_progress"):
		primary.call("set_reveal_progress", 1.0)
	if primary.has_method("set_slide_offset_px"):
		primary.call("set_slide_offset_px", 0.0)
	## Secondary stays hidden until slide completes.
	host.visible = false
	_host_w = maxf(host.size.x, 1.0)
	_host_h = maxf(host.size.y, 1.0)
	var slide: float = primary.size.x * SLIDE_FRAC

	_tween = tree.create_tween()
	## Phase 1: accelerating slide — no secondary / link yet.
	if primary.has_method("set_slide_offset_px"):
		_tween.tween_method(_on_slide_offset, 0.0, slide, SLIDE_DUR_S) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		_tween.tween_property(primary, "position:x", _primary_base_x + slide, SLIDE_DUR_S) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_begin_secondary_wipe)

func _begin_secondary_wipe() -> void:
	if not _running or _tree == null or _host == null or not is_instance_valid(_host):
		return
	_host.visible = true
	_host.modulate = Color.WHITE
	_ensure_mouse_pass(_host)
	_host_w = maxf(_host.size.x, _host_w)
	_host_h = maxf(_host.size.y, _host_h)

	_spawn_mindmap_link()

	_clip = Control.new()
	_clip.name = "BranchRevealClip"
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	_clip.z_index = 5
	_clip.position = Vector2.ZERO
	_clip.size = Vector2(0.0, _host_h)
	_host.add_child(_clip)

	for ch: Node in _host.get_children():
		if ch == _clip:
			continue
		if ch is Control and not str(ch.name).begins_with("BranchReveal"):
			_content = ch as Control
			break
	if _content != null:
		_host.remove_child(_content)
		_clip.add_child(_content)
		_content.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_content.anchor_right = 0.0
		_content.anchor_bottom = 0.0
		_content.position = Vector2.ZERO
		_content.size = Vector2(_host_w, _host_h)

	_trail = ColorRect.new()
	_trail.name = "BranchRevealTrail"
	_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trail.z_index = 21
	_trail.color = Color(1, 1, 1, 0.35)
	_trail.size = Vector2(TRAIL_W, _host_h)
	_trail.position = Vector2(-TRAIL_W, 0)
	_host.add_child(_trail)

	_line = ColorRect.new()
	_line.name = "BranchRevealLine"
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.z_index = 22
	_line.color = Color(1, 1, 1, 0.95)
	_line.size = Vector2(LINE_W, _host_h)
	_line.position = Vector2.ZERO
	_host.add_child(_line)

	var wipe_s: float = clampf(_host_w / WIPE_PX_PER_S, WIPE_DUR_MIN_S, WIPE_DUR_MAX_S)
	_tween = _tree.create_tween()
	_tween.set_parallel(true)
	if _link != null and is_instance_valid(_link):
		_tween.tween_method(_on_link_progress, 0.0, 1.0, LINK_DRAW_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_clip, "size:x", _host_w, wipe_s).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(_line, "position:x", _host_w, wipe_s).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(_trail, "position:x", _host_w - TRAIL_W, wipe_s).set_trans(Tween.TRANS_LINEAR)
	_tween.chain().tween_callback(_on_reveal_finished)

func _spawn_mindmap_link() -> void:
	_clear_link()
	if _primary == null or _host == null or not is_instance_valid(_primary) or not is_instance_valid(_host):
		return
	var parent: Control = _host.get_parent() as Control
	if parent == null:
		return
	var paths: Array = _mindmap_paths(parent, _primary, _host)
	if paths.is_empty():
		return
	var link: Control = Control.new()
	link.name = "BranchMindmapLink"
	link.mouse_filter = Control.MOUSE_FILTER_IGNORE
	link.clip_contents = false
	link.z_index = 5
	_apply_paths_to_link(link, parent, paths)
	link.set_meta("progress", 0.0)
	link.set_meta("line_w", LINK_W)
	link.draw.connect(_on_link_draw.bind(link))
	parent.add_child(link)
	parent.move_child(link, _host.get_index())
	_link = link
	link.queue_redraw()

func _apply_paths_to_link(link: Control, _parent: Control, paths: Array) -> void:
	## Fit control to path bounds (parent-local) so 1→N below L1 row is not clipped; store link-local pts.
	var min_p: Vector2 = Vector2(INF, INF)
	var max_p: Vector2 = Vector2(-INF, -INF)
	var any: bool = false
	for path_v: Variant in paths:
		if typeof(path_v) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		for p: Vector2 in path_v as PackedVector2Array:
			min_p.x = minf(min_p.x, p.x)
			min_p.y = minf(min_p.y, p.y)
			max_p.x = maxf(max_p.x, p.x)
			max_p.y = maxf(max_p.y, p.y)
			any = true
	if not any:
		return
	var pad: float = 8.0
	min_p -= Vector2(pad, pad)
	max_p += Vector2(pad, pad)
	link.set_anchors_preset(Control.PRESET_TOP_LEFT)
	link.anchor_right = 0.0
	link.anchor_bottom = 0.0
	link.position = min_p
	link.size = Vector2(maxf(max_p.x - min_p.x, 4.0), maxf(max_p.y - min_p.y, 4.0))
	var shifted: Array = []
	for path_v2: Variant in paths:
		if typeof(path_v2) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		var dst: PackedVector2Array = PackedVector2Array()
		for q: Vector2 in path_v2 as PackedVector2Array:
			dst.append(q - min_p)
		shifted.append(dst)
	link.set_meta("paths", shifted)

func _host_has_outer_frame(host: Control) -> bool:
	## Own chrome only — ignore nested mode Branch_* under 开始游戏 (UI_AND_SHELL §1.0a).
	return _find_own_secondary_chrome(host) != null

func _find_own_secondary_chrome(host: Control) -> Node:
	## Chrome for THIS secondary plate. Do not descend into nested Branch_solo / Branch_online.
	if host == null:
		return null
	for ch: Node in host.get_children():
		var nm: String = str(ch.name)
		if nm.begins_with("BranchReveal") or nm.begins_with("BranchMindmap"):
			continue
		if nm.begins_with("Branch_"):
			## Nested 单机/联机 rows — their plates are not this host's frame.
			continue
		var hit: Node = _find_chrome_excluding_names(ch, ["LoadTertiary", "HistoryTertiary", "DrillTertiary"])
		if hit != null:
			return hit
	return null

func _find_chrome_excluding_names(n: Node, skip_names: Array) -> Node:
	var nm: String = str(n.name)
	if nm in skip_names:
		return null
	if nm.begins_with("Branch_"):
		return null
	if nm == "SecondaryChrome" or nm == "RectBackdrop":
		return n
	for ch: Node in n.get_children():
		var hit: Node = _find_chrome_excluding_names(ch, skip_names)
		if hit != null:
			return hit
	return null

func _collect_secondary_buttons(host: Control) -> Array[Control]:
	var out: Array[Control] = []
	## Start at children so the revealed host named Secondary_* is not self-skipped.
	if host == null:
		return out
	for ch: Node in host.get_children():
		_collect_secondary_buttons_rec(ch, out)
	return out

func _collect_secondary_buttons_rec(n: Node, out: Array[Control]) -> void:
	var nm: String = str(n.name)
	if nm.begins_with("BranchReveal") or nm.begins_with("BranchMindmap") \
			or nm == "LoadTertiary" or nm == "HistoryTertiary" or nm == "DrillTertiary":
		return
	if n is Control and not (n as Control).visible:
		## Hidden mode columns under 开始游戏 must not steal 1→N targets.
		return
	## Nested mode content hosts under 开始游戏 — only want Branch_* primary btns.
	if nm.begins_with("Secondary_") and nm != "SecondaryChrome":
		return
	if n is BaseButton:
		out.append(n as Control)
		return
	for ch: Node in n.get_children():
		_collect_secondary_buttons_rec(ch, out)

func _visual_right_global(c: Control) -> Vector2:
	## Parallelogram face mid-right — not Control AABB.
	if c != null and c.has_method("get_visual_attach_right_global"):
		return c.call("get_visual_attach_right_global") as Vector2
	return c.global_position + Vector2(c.size.x, c.size.y * 0.5)

func _visual_left_global(c: Control) -> Vector2:
	if c != null and c.has_method("get_visual_attach_left_global"):
		return c.call("get_visual_attach_left_global") as Vector2
	return c.global_position + Vector2(0.0, c.size.y * 0.5)

func _visual_left_global_at_rest(c: Control) -> Vector2:
	## Ignore slide_offset so parent mindmap vertical stubs stay put while the btn slides.
	var p: Vector2 = _visual_left_global(c)
	if c != null and c.get("slide_offset_px") != null:
		p.x -= float(c.get("slide_offset_px"))
	return p

func _mindmap_paths(parent: Control, primary: Control, host: Control) -> Array:
	var origin: Vector2 = _to_parent_local(parent, _visual_right_global(primary))
	var paths: Array = []
	if _host_has_outer_frame(host):
		## Straight horizontal onto frame left at visual attach Y (not frame mid).
		var frame_x: float = host.global_position.x
		var chrome: Node = _find_own_secondary_chrome(host)
		if chrome is Control:
			frame_x = (chrome as Control).global_position.x
		var end: Vector2 = _to_parent_local(
			parent, Vector2(frame_x, _visual_right_global(primary).y)
		)
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(origin)
		pts.append(end)
		paths.append(pts)
		## Box-外二级钮（历史战绩）：竖段 X 用未滑左缘；末点用当前左缘（右滑拉长贴钮）。
		var extras: Array[Control] = _collect_buttons_outside_chrome(host)
		if not extras.is_empty():
			var min_left_rest: float = INF
			var branches_data: Array = []
			for b: Control in extras:
				if not is_instance_valid(b):
					continue
				var rest: Vector2 = _to_parent_local(parent, _visual_left_global_at_rest(b))
				var cur: Vector2 = _to_parent_local(parent, _visual_left_global(b))
				min_left_rest = minf(min_left_rest, rest.x)
				branches_data.append({"rest": rest, "cur": cur})
			var spine_x: float = (origin.x + min_left_rest) * 0.5
			for item: Variant in branches_data:
				var rest_t: Vector2 = (item as Dictionary)["rest"] as Vector2
				var cur_t: Vector2 = (item as Dictionary)["cur"] as Vector2
				var branch: PackedVector2Array = PackedVector2Array()
				branch.append(origin)
				if absf(rest_t.y - origin.y) < 1.5 and absf(cur_t.x - rest_t.x) < 1.5:
					branch.append(cur_t)
				else:
					branch.append(Vector2(spine_x, origin.y))
					branch.append(Vector2(spine_x, rest_t.y))
					## Horizontal stub tracks the sliding face.
					branch.append(Vector2(cur_t.x, rest_t.y))
				paths.append(branch)
		return paths
	var btns: Array[Control] = _collect_secondary_buttons(host)
	if btns.is_empty():
		var end2: Vector2 = _to_parent_local(
			parent, Vector2(host.global_position.x, _visual_right_global(primary).y)
		)
		var pts2: PackedVector2Array = PackedVector2Array()
		pts2.append(origin)
		pts2.append(end2)
		paths.append(pts2)
		return paths
	var min_left2: float = INF
	var targets2: Array[Vector2] = []
	for b2: Control in btns:
		if not is_instance_valid(b2):
			continue
		var t2: Vector2 = _to_parent_local(parent, _visual_left_global(b2))
		targets2.append(t2)
		min_left2 = minf(min_left2, t2.x)
	var spine_x2: float = (origin.x + min_left2) * 0.5
	for target2: Vector2 in targets2:
		var branch2: PackedVector2Array = PackedVector2Array()
		branch2.append(origin)
		if absf(target2.y - origin.y) < 1.5:
			branch2.append(target2)
		else:
			branch2.append(Vector2(spine_x2, origin.y))
			branch2.append(Vector2(spine_x2, target2.y))
			branch2.append(target2)
		paths.append(branch2)
	return paths

func _collect_buttons_outside_chrome(host: Control) -> Array[Control]:
	var out: Array[Control] = []
	_collect_buttons_outside_chrome_rec(host, out)
	return out

func _collect_buttons_outside_chrome_rec(n: Node, out: Array[Control]) -> void:
	var nm: String = str(n.name)
	if nm.begins_with("BranchReveal") or nm.begins_with("BranchMindmap") \
			or nm == "LoadTertiary" or nm == "HistoryTertiary" or nm == "DrillTertiary":
		return
	## Do not descend into the plate — only框外钮.
	if nm == "SecondaryChrome" or nm == "RectBackdrop":
		return
	if n is BaseButton:
		out.append(n as Control)
		return
	for ch: Node in n.get_children():
		_collect_buttons_outside_chrome_rec(ch, out)

func _to_parent_local(parent: Control, global_pt: Vector2) -> Vector2:
	return parent.get_global_transform_with_canvas().affine_inverse() * global_pt

func _on_link_progress(p: float) -> void:
	if _link != null and is_instance_valid(_link):
		_link.set_meta("progress", clampf(p, 0.0, 1.0))
		_link.queue_redraw()

func _on_link_draw(link: Control) -> void:
	if link == null or not is_instance_valid(link):
		return
	var paths_v: Variant = link.get_meta("paths", [])
	if typeof(paths_v) != TYPE_ARRAY:
		return
	var progress: float = float(link.get_meta("progress", 1.0))
	var lw: float = float(link.get_meta("line_w", LINK_W))
	var col: Color = Color(1, 1, 1, 0.92)
	for path_v: Variant in paths_v:
		if typeof(path_v) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		_draw_path_progressive(link, path_v as PackedVector2Array, progress, col, lw)

func _draw_path_progressive(link: Control, pts: PackedVector2Array, progress: float, col: Color, lw: float) -> void:
	if pts.size() < 2:
		return
	var total: float = 0.0
	for i: int in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	if total < 0.001:
		return
	var budget: float = total * clampf(progress, 0.0, 1.0)
	var drawn: PackedVector2Array = PackedVector2Array()
	drawn.append(pts[0])
	for i2: int in range(1, pts.size()):
		var a: Vector2 = pts[i2 - 1]
		var b: Vector2 = pts[i2]
		var seg: float = a.distance_to(b)
		if budget >= seg:
			drawn.append(b)
			budget -= seg
		else:
			if seg > 0.001:
				drawn.append(a.lerp(b, budget / seg))
			budget = 0.0
			break
	if drawn.size() < 2:
		return
	link.draw_polyline(drawn, col, lw, true)

func _on_slide_offset(v: float) -> void:
	if _primary != null and is_instance_valid(_primary) and _primary.has_method("set_slide_offset_px"):
		_primary.call("set_slide_offset_px", v)
	## Keep peer mindmap lines attached — just redraw longer to the slid button.
	if on_slide_step.is_valid():
		on_slide_step.call()

func _on_reveal_finished() -> void:
	_restore_content()
	_clear_fx()
	if _link != null and is_instance_valid(_link):
		_link.set_meta("progress", 1.0)
		_relayout_link()
		_link.queue_redraw()
	_running = false
	_tree = null
	if _primary != null and is_instance_valid(_primary):
		_primary.modulate = Color.WHITE
		if _primary.has_method("set_reveal_progress"):
			_primary.call("set_reveal_progress", 1.0)
	if on_slide_step.is_valid():
		on_slide_step.call()
	if on_finished.is_valid():
		on_finished.call()

func relayout_open_link() -> void:
	_relayout_link()

func _relayout_link() -> void:
	if _link == null or not is_instance_valid(_link):
		return
	if _primary == null or _host == null or not is_instance_valid(_primary) or not is_instance_valid(_host):
		return
	var parent: Control = _link.get_parent() as Control
	if parent == null:
		return
	var paths: Array = _mindmap_paths(parent, _primary, _host)
	if paths.is_empty():
		return
	_apply_paths_to_link(_link, parent, paths)
	_link.queue_redraw()

func _ensure_mouse_pass(n: Node) -> void:
	if n is Control:
		var c: Control = n as Control
		if c is ColorRect and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch: Node in n.get_children():
		_ensure_mouse_pass(ch)
