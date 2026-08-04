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
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		box.add_child(line)
		var main: Label = Label.new()
		main.text = "%s  Lv%d  黄币+%d  %s" % [
			str(r.get("nick", "?")),
			TypedVariant.as_int(r.get("level", 1), 1),
			TypedVariant.as_int(r.get("gold_earned", 0), 0),
			str(r.get("result", "")),
		]
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
	if persist:
		NullsecSettlement.save_history(rows)
	popup_centered()
