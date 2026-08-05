extends AcceptDialog
class_name NullsecSettlementPanel
## End-of-match list: nick / level / gold earned / WLD / ship icons+stars.

func show_rows(rows: Array, persist: bool = true) -> void:
	title = "对局结算"
	dialog_hide_on_ok = true
	ok_button_text = "确定"
	for c: Node in get_children():
		if c is ScrollContainer or c is VBoxContainer:
			c.queue_free()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 360)
	add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	scroll.add_child(box)
	for r_v: Variant in rows:
		if not (r_v is Dictionary):
			continue
		var r: Dictionary = r_v
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		box.add_child(col)
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		col.add_child(line)
		var rank: int = TypedVariant.as_int(r.get("rank", 0), 0)
		var w: int = TypedVariant.as_int(r.get("wins", 0), 0)
		var l: int = TypedVariant.as_int(r.get("losses", 0), 0)
		var d: int = TypedVariant.as_int(r.get("draws", 0), 0)
		var tags: PackedStringArray = PackedStringArray()
		if TypedVariant.as_bool(r.get("is_ai", false), false):
			tags.append("人机")
		if TypedVariant.as_bool(r.get("absent", false), false):
			tags.append("缺席")
		if TypedVariant.as_bool(r.get("ghost", false), false):
			tags.append("掉线")
		var tag_s: String = (" · " + " ".join(tags)) if tags.size() > 0 else ""
		var main: Label = Label.new()
		var rank_s: String = ("#%d  " % rank) if rank > 0 else ""
		main.text = "%s%s  Lv%d  黄币+%d  %d胜%d负%d平  %s%s" % [
			rank_s,
			str(r.get("nick", "?")),
			TypedVariant.as_int(r.get("level", 1), 1),
			TypedVariant.as_int(r.get("gold_earned", 0), 0),
			w, l, d,
			str(r.get("result", "")),
			tag_s,
		]
		if TypedVariant.as_bool(r.get("absent", false), false) or TypedVariant.as_bool(r.get("ghost", false), false):
			main.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		line.add_child(main)
		var ships: Array = TypedVariant.as_array(r.get("ships", []))
		for sh_v: Variant in ships:
			var sid: int = 0
			var star: int = 1
			if sh_v is Dictionary:
				var sh: Dictionary = sh_v
				sid = TypedVariant.as_int(sh.get("ship_id", 0), 0)
				star = TypedVariant.as_int(sh.get("star", 1), 1)
			else:
				sid = TypedVariant.as_int(sh_v, 0)
			var data: Dictionary = DataStore.get_ship(sid)
			var ic: TextureRect = TextureRect.new()
			ic.custom_minimum_size = Vector2(36, 36)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture = UiAssets.champion_icon(str(data.get("name", "")), sid)
			ic.tooltip_text = "%s ★%d" % [str(data.get("name", sid)), star]
			line.add_child(ic)
			var st: Label = Label.new()
			st.text = "★%d" % star
			line.add_child(st)
		## MULTIPLAYER_PVP §7.1 — second line: "称号 ，称号*n" (n≥2 only).
		var titles_line: String = NullsecSettlement.format_titles_line(TypedVariant.as_array(r.get("titles", [])))
		if titles_line != "":
			var tlabel: Label = Label.new()
			tlabel.text = titles_line
			tlabel.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
			col.add_child(tlabel)
	if persist:
		NullsecSettlement.save_history(rows)
	popup_centered()

## Prefer this over `show_rows` when a full match_report dict is available (host-collected
## §7 report with every contestant's summary) — merge by seat_id into existing rows when
## the panel already shows placeholders; persists via `save_match_report`.
func show_report(report: Dictionary, persist: bool = true) -> void:
	var players: Array = TypedVariant.as_array(report.get("players", TypedVariant.as_array(report.get("rows", []))))
	show_rows(players, false)
	if persist:
		NullsecSettlement.save_match_report(report)
