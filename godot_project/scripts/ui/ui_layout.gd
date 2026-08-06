extends RefCounted
class_name UiLayout
## Screen-relative UI metrics. Prefer anchors + fractions over fixed 1080p pixels.
## Design reference: 1920×1080; mobile uses denser chrome so HUD is not oversized.

const DESIGN: Vector2 = Vector2(1920.0, 1080.0)

static func viewport_size(from: Node = null) -> Vector2:
	if from != null and is_instance_valid(from) and from.is_inside_tree():
		var vp: Viewport = from.get_viewport()
		if vp:
			var r: Vector2 = vp.get_visible_rect().size
			if r.x > 1.0 and r.y > 1.0:
				return r
	var w: Vector2i = DisplayServer.window_get_size()
	if w.x > 1 and w.y > 1:
		return Vector2(w)
	return DESIGN

static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"

static func scale(from: Node = null) -> float:
	var s: Vector2 = viewport_size(from)
	var base: float = minf(s.x / DESIGN.x, s.y / DESIGN.y)
	# Stretch often already maps UI space ≈ design; treat near-1 as identity.
	if base > 0.88 and base < 1.12:
		base = 1.0
	if is_mobile():
		return clampf(base * 0.78, 0.55, 0.92)
	return clampf(base, 0.7, 1.2)

static func px(design_px: float, from: Node = null) -> float:
	return design_px * scale(from)

static func font_size(design: int, from: Node = null) -> int:
	var scaled: float = float(design) * scale(from)
	return maxi(10, roundi(scaled))

static func margin_px(design: float, from: Node = null) -> int:
	var scaled: float = px(design, from)
	return maxi(4, roundi(scaled))

## Fraction of viewport (0..1). Keeps offsets zero so resize stays correct.
static func set_rect_frac(c: Control, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.anchor_left = clampf(left, 0.0, 1.0)
	c.anchor_top = clampf(top, 0.0, 1.0)
	c.anchor_right = clampf(right, 0.0, 1.0)
	c.anchor_bottom = clampf(bottom, 0.0, 1.0)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH

static func set_left_strip(c: Control, width_frac: float, top_frac: float = 0.055, bottom_frac: float = 0.012, left_frac: float = 0.006) -> void:
	width_frac = clampf(width_frac, 0.08, 0.28)
	set_rect_frac(c, left_frac, top_frac, left_frac + width_frac, 1.0 - bottom_frac)

static func set_right_strip(c: Control, width_frac: float, top_frac: float = 0.07, bottom_frac: float = 0.18, right_margin: float = 0.008) -> void:
	width_frac = clampf(width_frac, 0.12, 0.3)
	set_rect_frac(c, 1.0 - right_margin - width_frac, top_frac, 1.0 - right_margin, 1.0 - bottom_frac)

static func set_bottom_strip(c: Control, height_frac: float, left_frac: float = 0.01, right_frac: float = 0.01, bottom_margin: float = 0.01) -> void:
	var hi: float = 0.44 if is_ultrawide(c) else 0.32
	height_frac = clampf(height_frac, 0.08, hi)
	set_rect_frac(c, left_frac, 1.0 - bottom_margin - height_frac, 1.0 - right_frac, 1.0 - bottom_margin)

static func set_center_panel_frac(c: Control, width_frac: float, height_frac: float) -> void:
	width_frac = clampf(width_frac, 0.35, 0.92)
	height_frac = clampf(height_frac, 0.35, 0.92)
	var l: float = 0.5 - width_frac * 0.5
	var t: float = 0.5 - height_frac * 0.5
	set_rect_frac(c, l, t, l + width_frac, t + height_frac)

static func top_bar_height_frac() -> float:
	return 0.055 if is_mobile() else 0.06

static func left_col_width_frac() -> float:
	return 0.12 if is_mobile() else 0.13

static func right_col_width_frac() -> float:
	## Mobile needs a bit more width so InfoPanel weapon squares / portrait fit.
	return 0.22 if is_mobile() else 0.2

static func is_ultrawide(from: Node = null) -> bool:
	## D-EAC-49：视口宽:高 ≥ 2:1
	var s: Vector2 = viewport_size(from)
	return s.y > 1.0 and (s.x / s.y) >= 2.0

static func bottom_shop_height_frac(from: Node = null) -> float:
	var base: float = 0.22 if is_mobile() else 0.26
	if is_ultrawide(from):
		## Raise floor so Meta / refresh / lock stay in the safe area on ultrawide.
		return maxf(base, 0.36 if is_mobile() else 0.40)
	return base

## Collapsed strip thickness (fraction of viewport).
static func collapse_strip_frac() -> float:
	return 0.028 if is_mobile() else 0.024

## Playfield open window as viewport fractions: left, top, right, bottom edges.
static func playfield_safe_rect(collapse_left: bool, collapse_right: bool, collapse_bottom: bool, from: Node = null) -> Rect2:
	var top: float = top_bar_height_frac() + 0.01
	var left: float = collapse_strip_frac() if collapse_left else (left_col_width_frac() + 0.012)
	var right: float = (1.0 - collapse_strip_frac()) if collapse_right else (1.0 - right_col_width_frac() - 0.01)
	var bottom: float = (1.0 - collapse_strip_frac()) if collapse_bottom else (1.0 - bottom_shop_height_frac(from) - 0.012)
	return Rect2(left, top, maxf(0.2, right - left), maxf(0.2, bottom - top))

## Deprecated name kept for callers; prefer left_col_width_frac.
static func shop_width_frac() -> float:
	return left_col_width_frac()
