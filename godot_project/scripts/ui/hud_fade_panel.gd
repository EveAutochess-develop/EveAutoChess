extends Control
class_name HudFadePanel
## HUD fade fill + cyan rounded hairline (UI_AND_SHELL §3.3).
## fade_axis: 0 = opaque left → fade right; 1 = opaque bottom → fade up;
##            2 = diagonal TL opaque → BR fully transparent.

const AXIS_LEFT_RIGHT: int = 0
const AXIS_BOTTOM_UP: int = 1
const AXIS_DIAGONAL_TL_BR: int = 2

var fill_color: Color = Color(0.07, 0.09, 0.11, 0.88)
var border_color: Color = Color(0.35, 0.72, 0.85, 0.55)
var border_px: float = 1.0
var corner_radius: float = 4.0
var fade_axis: int = AXIS_BOTTOM_UP
var fade_start: float = 0.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func configure(p_axis: int, p_start: float, p_border: float, p_corner: float = 4.0) -> void:
	fade_axis = p_axis
	fade_start = clampf(p_start, 0.0, 1.0)
	border_px = maxf(1.0, p_border)
	corner_radius = maxf(0.0, p_corner)
	queue_redraw()


func _alpha_at_uv(u: float, v: float) -> float:
	if fade_axis == AXIS_DIAGONAL_TL_BR:
		## Fully transparent on/ past the TR–BL diagonal (u+v >= 1); BR triangle clear.
		return clampf(1.0 - (clampf(u, 0.0, 1.0) + clampf(v, 0.0, 1.0)), 0.0, 1.0)
	if fade_axis == AXIS_LEFT_RIGHT:
		if u <= fade_start:
			return 1.0
		return clampf(1.0 - (u - fade_start) / maxf(1.0 - fade_start, 0.0001), 0.0, 1.0)
	## AXIS_BOTTOM_UP: v=1 bottom opaque, v=0 top fade.
	if v >= fade_start:
		return 1.0
	return clampf(v / maxf(fade_start, 0.0001), 0.0, 1.0)


func _rounded_sdf(px: float, py: float, sz: Vector2, cr: float) -> float:
	var hx: float = sz.x * 0.5
	var hy: float = sz.y * 0.5
	var dx: float = absf(px - hx) - (hx - cr)
	var dy: float = absf(py - hy) - (hy - cr)
	var ox: float = maxf(dx, 0.0)
	var oy: float = maxf(dy, 0.0)
	return minf(maxf(dx, dy), 0.0) + sqrt(ox * ox + oy * oy) - cr


func _draw() -> void:
	var sz: Vector2 = size
	if sz.x < 2.0 or sz.y < 2.0:
		return
	var cr: float = minf(corner_radius, minf(sz.x, sz.y) * 0.45)
	var bw: float = minf(border_px, minf(sz.x, sz.y) * 0.25)
	var nx: int = clampi(int(ceili(sz.x / 6.0)), 24, 56)
	var ny: int = clampi(int(ceili(sz.y / 6.0)), 24, 72)
	var cw: float = sz.x / float(nx)
	var ch: float = sz.y / float(ny)
	for iy: int in range(ny):
		for ix: int in range(nx):
			var cx: float = (float(ix) + 0.5) * cw
			var cy: float = (float(iy) + 0.5) * ch
			if _rounded_sdf(cx, cy, sz, cr) > 0.0:
				continue
			var a: float = _alpha_at_uv(cx / sz.x, cy / sz.y)
			if a <= 0.002:
				continue
			var fc: Color = fill_color
			fc.a *= a
			draw_rect(Rect2(float(ix) * cw, float(iy) * ch, cw + 0.5, ch + 0.5), fc)
	_draw_rounded_border(sz, cr, bw)


func _draw_rounded_border(sz: Vector2, cr: float, bw: float) -> void:
	if bw < 0.5:
		return
	var step: float = maxf(1.5, bw)
	## Top edge (left → right), skip BR-adjacent fade via alpha.
	var x: float = cr
	while x <= sz.x - cr + 0.01:
		_stroke_border_seg(Rect2(x, 0.0, step, bw), (x + step * 0.5) / sz.x, 0.0)
		x += step
	## Bottom edge.
	x = cr
	while x <= sz.x - cr + 0.01:
		_stroke_border_seg(Rect2(x, sz.y - bw, step, bw), (x + step * 0.5) / sz.x, 1.0)
		x += step
	## Left edge.
	var y: float = cr
	while y <= sz.y - cr + 0.01:
		_stroke_border_seg(Rect2(0.0, y, bw, step), 0.0, (y + step * 0.5) / sz.y)
		y += step
	## Right edge.
	y = cr
	while y <= sz.y - cr + 0.01:
		_stroke_border_seg(Rect2(sz.x - bw, y, bw, step), 1.0, (y + step * 0.5) / sz.y)
		y += step
	_draw_corner_arc(Vector2(cr, cr), cr, bw, 180.0, 270.0, sz)
	_draw_corner_arc(Vector2(sz.x - cr, cr), cr, bw, 270.0, 360.0, sz)
	_draw_corner_arc(Vector2(cr, sz.y - cr), cr, bw, 90.0, 180.0, sz)
	_draw_corner_arc(Vector2(sz.x - cr, sz.y - cr), cr, bw, 0.0, 90.0, sz)


func _stroke_border_seg(r: Rect2, u: float, v: float) -> void:
	var a: float = _alpha_at_uv(u, v)
	if a <= 0.02:
		return
	var bc: Color = border_color
	bc.a *= a
	draw_rect(r, bc)


func _draw_corner_arc(center: Vector2, cr: float, bw: float, deg0: float, deg1: float, sz: Vector2) -> void:
	if cr < 1.0:
		return
	var n: int = maxi(6, int(ceili(cr * 0.7)))
	for i: int in range(n):
		var t: float = (float(i) + 0.5) / float(n)
		var deg: float = lerpf(deg0, deg1, t)
		var rad: float = deg_to_rad(deg)
		var p: Vector2 = center + Vector2(cos(rad), -sin(rad)) * (cr - bw * 0.5)
		var u: float = clampf(p.x / maxf(sz.x, 1.0), 0.0, 1.0)
		var v: float = clampf(p.y / maxf(sz.y, 1.0), 0.0, 1.0)
		var a: float = _alpha_at_uv(u, v)
		if a <= 0.02:
			continue
		var bc: Color = border_color
		bc.a *= a
		draw_rect(Rect2(p.x - bw * 0.5, p.y - bw * 0.5, bw, bw), bc)
