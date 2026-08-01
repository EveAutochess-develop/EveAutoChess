extends AcceptDialog
class_name NullsecSettlementPanel
## End-of-match list: nick / level / gold earned / WLD / ship icons+stars.

func show_rows(rows: Array, persist: bool = true) -> void:
	title = "对局结算"
	dialog_hide_on_ok = true
	ok_button_text = "确定"
	for c in get_children():
		if c is ScrollContainer or c is VBoxContainer:
			c.queue_free()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 360)
	add_child(scroll)
	var box := VBoxContainer.new()
	scroll.add_child(box)
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		box.add_child(line)
		var main := Label.new()
		main.text = "%s  Lv%d  黄币+%d  %s" % [
			str(r.get("nick", "?")),
			int(r.get("level", 1)),
			int(r.get("gold_earned", 0)),
			str(r.get("result", "")),
		]
		line.add_child(main)
		var ships: Array = r.get("ships", []) as Array
		for sh in ships:
			var sid := int(sh.get("ship_id", 0)) if typeof(sh) == TYPE_DICTIONARY else int(sh)
			var star := int(sh.get("star", 1)) if typeof(sh) == TYPE_DICTIONARY else 1
			var data: Dictionary = DataStore.get_ship(sid)
			var ic := TextureRect.new()
			ic.custom_minimum_size = Vector2(36, 36)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture = UiAssets.champion_icon(str(data.get("name", "")), sid)
			ic.tooltip_text = "%s ★%d" % [str(data.get("name", sid)), star]
			line.add_child(ic)
			var st := Label.new()
			st.text = "★%d" % star
			line.add_child(st)
	if persist:
		NullsecSettlement.save_history(rows)
	popup_centered()
