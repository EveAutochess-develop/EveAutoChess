extends RefCounted
class_name EquipmentIconView
## Shared icon + size badge + detail text for function-bucket equipment (EQUIPMENT.md).

static func make_icon_cell(icon_size: Vector2, mod: Dictionary, from: Node, fill_cell: bool = false) -> Control:
	var root: Control = Control.new()
	root.custom_minimum_size = icon_size
	root.clip_contents = true
	## Detail rows sit in HBox: never EXPAND_FILL or long blurbs stretch icons unevenly.
	if fill_cell:
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		root.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var art: Control
	if MixedLanceIcon.is_mixed_lance(mod):
		art = MixedLanceIcon.make_anim_rect()
	else:
		var tex: Texture2D = UiAssets.function_module_icon(mod)
		if tex:
			var tex_rect: TextureRect = TextureRect.new()
			tex_rect.texture = tex
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art = tex_rect
		else:
			var ph: ColorRect = ColorRect.new()
			ph.color = Color(0.14, 0.18, 0.26, 1.0)
			ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art = ph
	root.add_child(art)
	## Implants: no size badge anywhere (EQUIPMENT.md §5 / §7).
	if TypedVariant.as_bool(mod.get("implant", false), false):
		return root
	var badge_tex: Texture2D = UiAssets.equipment_size_badge(str(mod.get("size", "")))
	if badge_tex:
		var badge: TextureRect = TextureRect.new()
		badge.texture = badge_tex
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bs: float = maxf(UiLayout.px(10.0, from), icon_size.x * 0.38)
		badge.custom_minimum_size = Vector2(bs, bs)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -bs - 1.0
		badge.offset_top = 1.0
		badge.offset_right = -1.0
		badge.offset_bottom = bs + 1.0
		root.add_child(badge)
	elif str(mod.get("size", "")) != "":
		var badge_l: PanelContainer = _size_text_badge(str(mod.get("size", "")), from)
		badge_l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge_l.offset_left = -UiLayout.px(16.0, from)
		badge_l.offset_top = 1.0
		badge_l.offset_right = -1.0
		badge_l.offset_bottom = UiLayout.px(14.0, from)
		root.add_child(badge_l)
	return root


static func _size_text_badge(size_key: String, from: Node) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	sb.border_color = Color(0.55, 0.75, 0.9, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(UiLayout.margin_px(2, from))
	badge.add_theme_stylebox_override("panel", sb)
	var lab: Label = Label.new()
	lab.text = size_key.strip_edges().to_upper()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiAssets.apply_label_font(lab, false, UiLayout.font_size(10, from))
	lab.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	badge.add_child(lab)
	return badge


static func format_blurb(mod: Dictionary) -> String:
	var blurb: String = str(mod.get("blurb", ""))
	if blurb == "":
		return ""
	var holes: Variant = mod.get("blurb_holes", {})
	if typeof(holes) != TYPE_DICTIONARY:
		return blurb
	var holes_d: Dictionary = holes
	for k_v: Variant in holes_d.keys():
		blurb = blurb.replace("{%s}" % str(k_v), str(holes_d[k_v]))
	return blurb


static func format_synth_line(mod: Dictionary) -> String:
	var lines: PackedStringArray = format_synth_lines(mod)
	if lines.is_empty():
		return "无可合成"
	return "\n".join(lines)


## Each line: 本装备拖到{partner}（尺寸）上后，合成出{product}（尺寸）
static func format_synth_lines(mod: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if mod.is_empty():
		return lines
	var self_id: String = str(mod.get("id", "")).strip_edges()
	if self_id == "":
		return lines
	## Same-line size up: two of this id → synth_next.
	var nxt: Variant = mod.get("synth_next", null)
	if nxt != null and str(nxt).strip_edges() != "":
		var next_id: String = str(nxt).strip_edges()
		var next_mod: Dictionary = DataStore.get_function_module(next_id)
		if next_mod.is_empty():
			next_mod = {"id": next_id, "name": next_id}
		lines.append("本装备拖到%s上后，合成出%s" % [_equip_label_with_size(mod), _equip_label_with_size(next_mod)])
	## Cross recipes: any module listing this id in synth_from (order-free).
	for fid_v: Variant in DataStore.function_module_ids():
		var fid: String = str(fid_v)
		var other: Dictionary = DataStore.get_function_module(fid)
		if other.is_empty():
			continue
		var mats: Variant = other.get("synth_from", null)
		if typeof(mats) != TYPE_ARRAY:
			continue
		var mats_a: Array = mats
		if mats_a.size() != 2:
			continue
		var m0: String = str(mats_a[0]).strip_edges()
		var m1: String = str(mats_a[1]).strip_edges()
		var partner_id: String = ""
		if m0 == self_id:
			partner_id = m1
		elif m1 == self_id:
			partner_id = m0
		else:
			continue
		var partner: Dictionary = DataStore.get_function_module(partner_id)
		if partner.is_empty():
			partner = {"id": partner_id, "name": partner_id}
		lines.append("本装备拖到%s上后，合成出%s" % [_equip_label_with_size(partner), _equip_label_with_size(other)])
	return lines


static func _equip_label_with_size(mod: Dictionary) -> String:
	var nm: String = str(mod.get("name", mod.get("id", "?")))
	var size_s: String = str(mod.get("size", "")).strip_edges().to_upper()
	if size_s == "":
		return nm
	return "%s（%s）" % [nm, size_s]


static func detail_lines(mod: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if mod.is_empty():
		return lines
	lines.append(str(mod.get("name", mod.get("id", "?"))))
	var size_s: String = str(mod.get("size", "")).strip_edges()
	if size_s != "":
		lines.append("尺寸：%s" % size_s.to_upper())
	var item_id: String = str(mod.get("id", "")).strip_edges()
	if TypedVariant.as_bool(mod.get("implant", false), false):
		var synth_total: int = 0
		if DataStore:
			synth_total = DataStore.function_module_purchase_value(item_id)
		else:
			synth_total = TypedVariant.as_int(mod.get("cost", 0), 0)
		lines.append("合成总价：%d" % synth_total)
	else:
		lines.append("价格：%d" % TypedVariant.as_int(mod.get("cost", 10), 10))
	var blurb: String = format_blurb(mod)
	if blurb != "":
		lines.append(blurb)
	var synth_lines: PackedStringArray = format_synth_lines(mod)
	if synth_lines.is_empty():
		lines.append("无可合成")
	else:
		for s_v: Variant in synth_lines:
			lines.append(str(s_v))
	return lines
