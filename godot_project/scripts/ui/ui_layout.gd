extends RefCounted
class_name UiLayout
## Screen-relative UI metrics. Prefer anchors + fractions over fixed 1080p pixels.
## Design reference: 1920×1080; mobile uses denser chrome so HUD is not oversized.

const DESIGN: Vector2 = Vector2(1920.0, 1080.0)
const DESIGN_ASPECT: float = 16.0 / 9.0

static func viewport_size(from: Node = null) -> Vector2:
	## HUD canvas size (= window client / stretch visible rect). Frac 1.0 bottom = window bottom.
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

## Edge HUD icons: former on-screen ×4, now ×4×⅔ = ×(8/3). Collapse + mode share one side.
const HUD_EDGE_ICON_MUL: float = 8.0 / 3.0
## Outer margin shared by side panels + edge chrome (expand/collapse use same formula).
const HUD_EDGE_MARGIN_FRAC: float = 0.006

static func hud_edge_icon_px(from: Node = null) -> float:
	## Unified collapse / mode / chrome hit size (UI_ICONS §9 · UI_AND_SHELL §3.4).
	return px(28.0 * HUD_EDGE_ICON_MUL, from)

static func hud_edge_margin_frac() -> float:
	return HUD_EDGE_MARGIN_FRAC

static func font_size(design: int, from: Node = null) -> int:
	var scaled: float = float(design) * scale(from)
	return maxi(10, roundi(scaled))

static func margin_px(design: float, from: Node = null) -> int:
	var scaled: float = px(design, from)
	return maxi(4, roundi(scaled))


static func shop_polite_gap_px(from: Node = null) -> int:
	## UI_AND_SHELL §3.2: 5 design-px between left-shop controls (not 6 ship slots).
	return maxi(5, roundi(px(5.0, from)))

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
	## Allow content+collapse (panel) up to ~0.48 on ultrawide; content alone still ~0.40.
	var hi: float = 0.50 if is_ultrawide(c) else 0.38
	height_frac = clampf(height_frac, 0.08, hi)
	set_rect_frac(c, left_frac, 1.0 - bottom_margin - height_frac, 1.0 - right_frac, 1.0 - bottom_margin)

static func set_center_panel_frac(c: Control, width_frac: float, height_frac: float) -> void:
	width_frac = clampf(width_frac, 0.35, 0.92)
	height_frac = clampf(height_frac, 0.35, 0.92)
	var l: float = 0.5 - width_frac * 0.5
	var t: float = 0.5 - height_frac * 0.5
	set_rect_frac(c, l, t, l + width_frac, t + height_frac)

static func hud_layout() -> Dictionary:
	## CONTENT_FORMAT §3.6b — preview snap fracs. Empty if file missing.
	return ContentRuntimeData.load_json_prefer_runtime("ui/hud_layout.json")


static func hud_panel(id_s: String) -> Dictionary:
	var root_d: Dictionary = hud_layout()
	var panels_v: Variant = root_d.get("panels", {})
	if typeof(panels_v) != TYPE_DICTIONARY:
		return {}
	var panels: Dictionary = panels_v
	var fv: Variant = panels.get(id_s, {})
	if typeof(fv) != TYPE_DICTIONARY:
		return {}
	var rec: Dictionary = fv
	return rec


static func hud_frac(id_s: String, key: String, fallback: float) -> float:
	var p: Dictionary = hud_panel(id_s)
	if p.is_empty() or not p.has(key):
		return fallback
	return TypedVariant.as_float(p.get(key, fallback), fallback)


static func hud_width(id_s: String, fallback: float) -> float:
	var p: Dictionary = hud_panel(id_s)
	if p.is_empty():
		return fallback
	return maxf(0.0, TypedVariant.as_float(p.get("r", 0.0), 0.0) - TypedVariant.as_float(p.get("l", 0.0), 0.0))


static func hud_height(id_s: String, fallback: float) -> float:
	var p: Dictionary = hud_panel(id_s)
	if p.is_empty():
		return fallback
	return maxf(0.0, TypedVariant.as_float(p.get("b", 0.0), 0.0) - TypedVariant.as_float(p.get("t", 0.0), 0.0))


static func top_bar_height_frac() -> float:
	var h: float = hud_height("RoundBar", -1.0)
	if h > 0.02:
		return h
	return 0.050 if is_mobile() else 0.055

static func left_col_width_frac() -> float:
	## Expanded left = Fetter.r (shop + gap + fetter). UI_AND_SHELL §3.1.
	var fr: float = hud_frac("Fetter", "r", -1.0)
	if fr > 0.08:
		return fr
	return 0.24 if is_mobile() else 0.281

static func left_shop_width_frac() -> float:
	var w: float = hud_width("LeftShop", -1.0)
	if w > 0.08:
		return w
	return hud_frac("LeftShop", "r", 0.161)


static func is_wider_than_design(from: Node = null) -> bool:
	var s: Vector2 = viewport_size(from)
	return s.y > 1.0 and (s.x / s.y) > DESIGN_ASPECT + 0.01


static func left_shop_width_frac_live(from: Node = null) -> float:
	## UI_AND_SHELL §3.1.2: mobile wider-than-16:9 → 16:9 left share, height-fill.
	## Pixel width = design_frac * (vh * 16/9); do not stretch shop with vp.x.
	var base: float = left_shop_width_frac()
	if not is_mobile():
		return base
	var s: Vector2 = viewport_size(from)
	if s.x <= 1.0 or not is_wider_than_design(from):
		return base
	var ref_w: float = s.y * DESIGN_ASPECT
	return clampf((base * ref_w) / s.x, 0.06, base)


static func left_col_width_frac_live(from: Node = null) -> float:
	## Shop may shrink on mobile ultrawide; fetter/gap keep screen-adaptive fracs.
	var shop_b: float = left_shop_width_frac()
	var col_b: float = left_col_width_frac()
	var shop_l: float = left_shop_width_frac_live(from)
	if absf(shop_l - shop_b) < 0.0005:
		return col_b
	var fetter: float = fetter_col_width_frac()
	var gap: float = maxf(0.0, col_b - shop_b - fetter)
	return shop_l + gap + fetter

static func fit_ship_offer_1x6(avail_w: float, avail_h: float, nslots: int = 6) -> Vector2:
	## UI_AND_SHELL §3.2: 6-offer container is 底:高 = 1:6. Returns (width, height).
	var n: float = float(maxi(1, nslots))
	var aw: float = maxf(1.0, avail_w)
	var ah: float = maxf(1.0, avail_h)
	var unit: float = minf(aw, ah / n)
	return Vector2(unit, unit * n)


static func fetter_col_width_frac() -> float:
	var w: float = hud_width("Fetter", -1.0)
	if w > 0.02:
		return w
	return 0.090 if is_mobile() else 0.106

static func right_col_width_frac() -> float:
	var w: float = hud_width("RightCol", -1.0)
	if w > 0.08:
		return w
	return 0.145 if is_mobile() else 0.13

static func is_ultrawide(from: Node = null) -> bool:
	## D-EAC-49：视口宽:高 ≥ 2:1
	var s: Vector2 = viewport_size(from)
	return s.y > 1.0 and (s.x / s.y) >= 2.0

static func bottom_shop_height_frac(from: Node = null) -> float:
	## UI_AND_SHELL §2.1 — Meta + 1×16 equip row only (buy zones live in LeftCol).
	var h: float = hud_height("BottomBar", -1.0)
	if h > 0.04:
		return h
	var base: float = 0.11 if is_mobile() else 0.12
	if is_ultrawide(from):
		return maxf(base, 0.12 if is_mobile() else 0.13)
	return base

## Bottom shop strip width as fraction of the full viewport (UI_AND_SHELL §3.1).
static func bottom_shop_width_frac() -> float:
	var w: float = hud_width("BottomBar", -1.0)
	if w > 0.2:
		return w
	return 0.60

## Collapse button strip thickness as viewport fraction (not part of bottom-bar height).
static func bottom_collapse_btn_frac(from: Node = null) -> float:
	var s: Vector2 = viewport_size(from)
	var btn_px: float = 28.0 if is_mobile() else 26.0
	if s.y <= 1.0:
		return collapse_strip_frac()
	return clampf(btn_px / s.y, 0.018, 0.045)

## Expanded Shop panel = bottom-bar content + collapse button on top.
static func bottom_shop_panel_frac(from: Node = null) -> float:
	## Content height + edge collapse strip above the shop (UI_AND_SHELL §3.4).
	return bottom_shop_height_frac(from) + bottom_collapse_btn_frac(from)

## Collapsed strip thickness (fraction of viewport).
static func collapse_strip_frac() -> float:
	return 0.028 if is_mobile() else 0.024

## Left band always reserves full shop+fetter width (UI_AND_SHELL §3.4).
## Left collapse_* args kept for call-site compat; fetter hide must not shift mid.
static func playfield_safe_rect(
	_collapse_left: bool,
	collapse_right: bool,
	collapse_bottom: bool,
	from: Node = null,
	_collapse_left_syn: bool = true,
	_collapse_left_equip: bool = true
) -> Rect2:
	var top: float = top_bar_height_frac() + 0.01
	var arrow_pad: float = 0.045
	var left: float = left_col_width_frac_live(from) + 0.012
	var right: float = (1.0 - arrow_pad) if collapse_right else (1.0 - right_col_width_frac() - 0.01)
	var bottom_band: float = arrow_pad if collapse_bottom else bottom_shop_panel_frac(from)
	var bottom: float = 1.0 - bottom_band - 0.012
	return Rect2(left, top, maxf(0.2, right - left), maxf(0.2, bottom - top))

## Deprecated name kept for callers; prefer left_col_width_frac.
static func shop_width_frac() -> float:
	return left_col_width_frac()
