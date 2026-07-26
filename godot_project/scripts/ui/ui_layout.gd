extends RefCounted
class_name UiLayout
## Screen-relative UI metrics. Prefer anchors + fractions over fixed 1080p pixels.
## Design reference: 1920×1080; mobile uses denser chrome so HUD is not oversized.

const DESIGN := Vector2(1920.0, 1080.0)

static func viewport_size(from: Node = null) -> Vector2:
	if from != null and is_instance_valid(from) and from.is_inside_tree():
		var vp := from.get_viewport()
		if vp:
			var r := vp.get_visible_rect().size
			if r.x > 1.0 and r.y > 1.0:
				return r
	var w := DisplayServer.window_get_size()
	if w.x > 1 and w.y > 1:
		return Vector2(w)
	return DESIGN

static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"

static func scale(from: Node = null) -> float:
	var s := viewport_size(from)
	var base := minf(s.x / DESIGN.x, s.y / DESIGN.y)
	# Stretch often already maps UI space ≈ design; treat near-1 as identity.
	if base > 0.88 and base < 1.12:
		base = 1.0
	if is_mobile():
		# Denser on phones / emulators so left shop + menu don't dominate.
		return clampf(base * 0.78, 0.55, 0.92)
	return clampf(base, 0.7, 1.2)

static func px(design_px: float, from: Node = null) -> float:
	return design_px * scale(from)

static func font_size(design: int, from: Node = null) -> int:
	return maxi(10, int(round(float(design) * scale(from))))

static func margin_px(design: float, from: Node = null) -> int:
	return maxi(4, int(round(px(design, from))))

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
	width_frac = clampf(width_frac, 0.12, 0.28)
	set_rect_frac(c, left_frac, top_frac, left_frac + width_frac, 1.0 - bottom_frac)

static func set_center_panel_frac(c: Control, width_frac: float, height_frac: float) -> void:
	width_frac = clampf(width_frac, 0.35, 0.92)
	height_frac = clampf(height_frac, 0.35, 0.92)
	var l := 0.5 - width_frac * 0.5
	var t := 0.5 - height_frac * 0.5
	set_rect_frac(c, l, t, l + width_frac, t + height_frac)

static func shop_width_frac() -> float:
	return 0.16 if is_mobile() else 0.185
