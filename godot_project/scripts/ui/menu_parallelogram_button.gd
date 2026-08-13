extends Button
## 60° parallelogram; corners fillet from slant_len/3; self-drawn label.
## Gold theme: mid gold · platinum highlight · dark-gold shade (UI_AND_SHELL §1.0a).
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

const SKEW_DEG: float = 60.0
## Fillet starts at 1/3 of each slanted edge from the vertex (UI_AND_SHELL §1.0a).
const SLANT_CORNER_FRAC: float = 1.0 / 3.0
const ARC_SEGS: int = 10

## Mid gold face (was near-black slate).
var base_color: Color = Color(0.58, 0.44, 0.16, 0.94)
## Platinum highlight / dark-gold shade — same relative strength as old white/black bands.
const HI_PLATINUM: Color = Color(0.96, 0.94, 0.88, 1.0)
const SHADE_DARK_GOLD: Color = Color(0.22, 0.14, 0.04, 1.0)
const OUTLINE_GOLD: Color = Color(0.92, 0.86, 0.65, 1.0)

var reveal_progress: float = 1.0
var slide_offset_px: float = 0.0

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	## Theme colors unused for face text (we draw_string); kept for any leftover chrome.
	add_theme_color_override("font_color", Color(1, 1, 1, 1))
	add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.85, 1))
	add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.55, 1))
	add_theme_color_override("font_disabled_color", Color(0.88, 0.88, 0.9, 1))
	## Transparent flat — StyleBoxEmpty can shrink the effective click rect to a hairline.
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(0)
	sb.draw_center = true
	add_theme_stylebox_override("normal", sb)
	add_theme_stylebox_override("hover", sb)
	add_theme_stylebox_override("pressed", sb)
	add_theme_stylebox_override("disabled", sb)
	add_theme_stylebox_override("focus", sb)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func set_reveal_progress(p: float) -> void:
	reveal_progress = clampf(p, 0.0, 1.0)
	queue_redraw()

func set_slide_offset_px(px: float) -> void:
	slide_offset_px = px
	position.x = px
	queue_redraw()

func _skew_dx() -> float:
	var h: float = maxf(size.y, 1.0)
	return h / tan(deg_to_rad(SKEW_DEG))

## Visual attach (parallelogram face), not Control AABB corners.
func get_visual_attach_right_global() -> Vector2:
	var dx: float = _skew_dx()
	var local: Vector2 = Vector2(size.x - dx * 0.5, size.y * 0.5)
	return get_global_transform_with_canvas() * local

func get_visual_attach_left_global() -> Vector2:
	var dx: float = _skew_dx()
	var local: Vector2 = Vector2(dx * 0.5, size.y * 0.5)
	return get_global_transform_with_canvas() * local

func get_visual_attach_bottom_right_global() -> Vector2:
	## Bottom edge of the face (c2), not AABB (w,h) which sits outside the skew.
	var dx: float = _skew_dx()
	return get_global_transform_with_canvas() * Vector2(size.x - dx, size.y)

func get_visual_attach_bottom_left_global() -> Vector2:
	return get_global_transform_with_canvas() * Vector2(0.0, size.y)

func _slant_len() -> float:
	var dx: float = _skew_dx()
	var h: float = maxf(size.y, 1.0)
	return sqrt(dx * dx + h * h)

func _corner_inset() -> float:
	var slant: float = _slant_len()
	var d: float = slant * SLANT_CORNER_FRAC
	var w: float = size.x
	var h: float = size.y
	var dx: float = _skew_dx()
	var top_len: float = maxf(w - dx, 1.0)
	## Keep fillets from eating past mid-edge on short sides.
	return minf(d, minf(slant * 0.49, minf(top_len * 0.49, h * 0.49)))

func _line_intersect(p: Vector2, dir_p: Vector2, q: Vector2, dir_q: Vector2) -> Vector2:
	var det: float = dir_p.x * dir_q.y - dir_p.y * dir_q.x
	if absf(det) < 0.0001:
		return (p + q) * 0.5
	var t: float = ((q.x - p.x) * dir_q.y - (q.y - p.y) * dir_q.x) / det
	return p + dir_p * t

func _append_fillet(out: PackedVector2Array, prev: Vector2, curr: Vector2, next: Vector2, inset: float) -> void:
	var u_in: Vector2 = (curr - prev).normalized()
	var u_out: Vector2 = (next - curr).normalized()
	var p_enter: Vector2 = curr - u_in * inset
	var p_exit: Vector2 = curr + u_out * inset
	## Inward normals for CCW winding (rotate edge dir 90° CCW).
	var n_in: Vector2 = Vector2(-u_in.y, u_in.x)
	var n_out: Vector2 = Vector2(-u_out.y, u_out.x)
	var center: Vector2 = _line_intersect(p_enter, n_in, p_exit, n_out)
	var r: float = center.distance_to(p_enter)
	if r < 0.5:
		out.append(p_enter)
		out.append(p_exit)
		return
	var a0: float = (p_enter - center).angle()
	var a1: float = (p_exit - center).angle()
	## Sweep the shorter arc that stays near the corner (CCW polygon → usually CCW sweep).
	var delta: float = wrapf(a1 - a0, -PI, PI)
	var steps: int = maxi(2, ARC_SEGS)
	for i: int in range(steps + 1):
		var t: float = float(i) / float(steps)
		var ang: float = a0 + delta * t
		out.append(center + Vector2(cos(ang), sin(ang)) * r)

func _rounded_poly() -> PackedVector2Array:
	var w: float = size.x
	var h: float = size.y
	var dx: float = _skew_dx()
	var c0: Vector2 = Vector2(dx, 0.0)
	var c1: Vector2 = Vector2(w, 0.0)
	var c2: Vector2 = Vector2(w - dx, h)
	var c3: Vector2 = Vector2(0.0, h)
	var inset: float = _corner_inset()
	var out: PackedVector2Array = PackedVector2Array()
	_append_fillet(out, c3, c0, c1, inset)
	_append_fillet(out, c0, c1, c2, inset)
	_append_fillet(out, c1, c2, c3, inset)
	_append_fillet(out, c2, c3, c0, inset)
	return out

func _label_color() -> Color:
	if disabled:
		return Color(0.9, 0.9, 0.93, 1.0)
	if button_pressed:
		return Color(1.0, 0.94, 0.7, 1.0)
	if is_hovered():
		return Color(1.0, 0.98, 0.9, 1.0)
	return Color(1.0, 1.0, 1.0, 1.0)

func _draw_label() -> void:
	## Overriding `_draw` suppresses Button's theme text — must paint ourselves.
	if text.is_empty() or reveal_progress <= 0.01:
		return
	var f: Font = get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	var fs: int = get_theme_font_size("font_size")
	if fs <= 0:
		fs = 22
	var sz: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var baseline: float = size.y * 0.5 + f.get_ascent(fs) * 0.5 - f.get_descent(fs) * 0.5
	var pos: Vector2 = Vector2(size.x * 0.5 - sz.x * 0.5, baseline)
	var col: Color = _label_color()
	col.a *= clampf(reveal_progress, 0.0, 1.0)
	var outline: Color = Color(0.0, 0.0, 0.0, 0.95 * col.a)
	draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, outline)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 2.0 or h < 2.0:
		return
	if reveal_progress <= 0.01:
		## Hit target only — no face / no label.
		return
	var pts: PackedVector2Array = _rounded_poly()
	if pts.size() < 3:
		return
	var vis_col: Color = base_color
	if disabled:
		vis_col = Color(base_color.r, base_color.g, base_color.b, base_color.a * 0.55)
	elif button_pressed:
		vis_col = base_color.darkened(0.18)
	elif is_hovered():
		vis_col = base_color.lightened(0.12)
	vis_col.a *= clampf(reveal_progress, 0.0, 1.0)
	draw_colored_polygon(pts, vis_col)
	var dx: float = _skew_dx()
	## Platinum highlight — same band geometry / alpha as former white.
	var hi: Color = Color(HI_PLATINUM.r, HI_PLATINUM.g, HI_PLATINUM.b, 0.16 if not disabled else 0.07)
	hi.a *= vis_col.a
	draw_colored_polygon(PackedVector2Array([
		Vector2(dx, 0.0),
		Vector2(w * 0.55, 0.0),
		Vector2(w * 0.42, h * 0.45),
		Vector2(dx * 0.55, h * 0.35),
	]), hi)
	## Dark-gold shade — same band geometry / alpha as former black.
	var sh: Color = Color(SHADE_DARK_GOLD.r, SHADE_DARK_GOLD.g, SHADE_DARK_GOLD.b, 0.24 if not disabled else 0.12)
	sh.a *= vis_col.a
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.45, h * 0.55),
		Vector2(w, h * 0.35),
		Vector2(w - dx, h),
		Vector2(w * 0.25, h),
	]), sh)
	var outline: Color = Color(OUTLINE_GOLD.r, OUTLINE_GOLD.g, OUTLINE_GOLD.b, 0.45 * vis_col.a)
	var ring: PackedVector2Array = pts.duplicate()
	if ring.size() > 0:
		ring.append(ring[0])
	draw_polyline(ring, outline, 1.5, true)
	_draw_label()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()

func _has_point(point: Vector2) -> bool:
	var w: float = size.x
	var h: float = size.y
	if w < 1.0 or h < 1.0:
		return false
	if point.y < 0.0 or point.y > h:
		return false
	var dx: float = _skew_dx()
	var t: float = point.y / h
	var left: float = lerpf(dx, 0.0, t)
	var right: float = lerpf(w, w - dx, t)
	return point.x >= left and point.x <= right
