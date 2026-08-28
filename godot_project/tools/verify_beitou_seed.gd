extends SceneTree
## Headless smoke: mod_samples JSON + FunctionFit gates (no ModManager boot).
## Usage: godot --path godot_project --headless --script res://tools/verify_beitou_seed.gd

func _init() -> void:
	print("VERIFY start beitou-float-turret")
	var ok: bool = true
	var pn: String = "beitou-float-turret"
	var beitou: Dictionary = {
		"ship_group": "frigate",
		"function_allowed_sizes": ["S", "M", "L", "XL"],
		"_mod_package": pn,
		"local_id": 5438,
	}
	var vanilla: Dictionary = {"ship_group": "frigate", "id": 23}
	var sizes: PackedStringArray = FunctionFit.allowed_sizes_for_ship(beitou)
	if sizes.size() != 4:
		push_error("VERIFY FAIL: beitou sizes=%s" % str(sizes))
		ok = false
	var frigate_sizes: PackedStringArray = FunctionFit.allowed_sizes_for_ship(vanilla)
	if frigate_sizes.size() != 1 or frigate_sizes[0] != "S":
		push_error("VERIFY FAIL: vanilla frigate sizes=%s" % str(frigate_sizes))
		ok = false
	var mod_eq: Dictionary = {
		"size": "S",
		"allowed_on": ["S", "M", "L", "XL"],
		"allowed_ships": [{"package": pn, "local_id": 5438}],
	}
	var mod_eq_l: Dictionary = {
		"size": "L",
		"allowed_on": ["S", "M", "L", "XL"],
		"allowed_ships": [{"package": pn, "local_id": 5438}],
	}
	if not FunctionFit.size_allowed_for_ship(beitou, mod_eq_l):
		push_error("VERIFY FAIL: L should fit beitou")
		ok = false
	if FunctionFit.size_allowed_for_ship(vanilla, mod_eq):
		push_error("VERIFY FAIL: exclusive equip must reject vanilla")
		ok = false
	var su: ShipUnit = ShipUnit.new()
	su.add_stat_modifier("t", "resist_armor_emp", "set", 1.0, 20.0, "t_armor")
	var r: float = su.layer_resist("armor", "emp", 0.6)
	if absf(r - 1.0) > 0.0001:
		push_error("VERIFY FAIL: set resist got %s want 1.0" % r)
		ok = false
	su.add_stat_modifier("a", "resist_shield_emp", "add", 0.5, 10.0, "a_shield")
	var r2: float = su.layer_resist("shield", "emp", 0.5)
	if absf(r2 - 0.95) > 0.0001:
		push_error("VERIFY FAIL: add resist cap got %s want 0.95" % r2)
		ok = false
	su.free()
	var ship_uj: Dictionary = TypedVariant.as_dict(JSON.parse_string(
		FileAccess.get_file_as_string("res://mod_samples/beitou-float-turret/units/ships/beitou_float_turret/unit.json")
	))
	var eq_uj: Dictionary = TypedVariant.as_dict(JSON.parse_string(
		FileAccess.get_file_as_string("res://mod_samples/beitou-float-turret/units/equipment/beitou_block_membrane/unit.json")
	))
	var mj: Dictionary = TypedVariant.as_dict(JSON.parse_string(
		FileAccess.get_file_as_string("res://mod_samples/beitou-float-turret/mod.json")
	))
	var want_dn: String = "狈头级浮游炮台与专属格挡器（不包含美术素材用于测试逻辑是否正确样例mod）"
	if str(mj.get("display_name", "")) != want_dn:
		push_error("VERIFY FAIL: display_name")
		ok = false
	if TypedVariant.as_int(ship_uj.get("local_id", 0)) != 5438:
		push_error("VERIFY FAIL: ship local_id")
		ok = false
	if TypedVariant.as_int(eq_uj.get("local_id", 0)) != 9438:
		push_error("VERIFY FAIL: eq local_id")
		ok = false
	if TypedVariant.as_float(eq_uj.get("capacitor_need", 0.0)) != 160.0:
		push_error("VERIFY FAIL: capacitor_need")
		ok = false
	if TypedVariant.as_float(eq_uj.get("duration_s", 0.0)) != 20.0:
		push_error("VERIFY FAIL: duration_s")
		ok = false
	var fx_list: Array = TypedVariant.as_array(eq_uj.get("effects", []))
	var fx0: Dictionary = {}
	if fx_list.size() > 0:
		fx0 = TypedVariant.as_dict(fx_list[0])
	if str(fx0.get("op", "")) != "set_resist_active":
		push_error("VERIFY FAIL: effect op")
		ok = false
	if str(eq_uj.get("fx_kind", "")) != "remote_cap":
		push_error("VERIFY FAIL: fx_kind expected remote_cap")
		ok = false
	if FileAccess.file_exists("res://mod_samples/beitou-float-turret/units/ships/beitou_float_turret/portrait/portrait.png"):
		push_error("VERIFY FAIL: should have no portrait")
		ok = false
	if FileAccess.file_exists("res://mod_samples/beitou-float-turret/units/ships/beitou_float_turret/model/model.glb"):
		push_error("VERIFY FAIL: should have no model")
		ok = false
	for star_any: Variant in TypedVariant.as_array(ship_uj.get("stars", [])):
		var star: Dictionary = TypedVariant.as_dict(star_any)
		for hk: String in ["shield_hp", "armor_hp", "structure_hp"]:
			if TypedVariant.as_float(star.get(hk, -1.0)) != 10.0:
				push_error("VERIFY FAIL: star %s" % hk)
				ok = false
	if str(ship_uj.get("weapon_fx", "")) != "rail" or str(ship_uj.get("weapon_tier", "")) != "capital":
		push_error("VERIFY FAIL: weapon_fx/tier")
		ok = false
	if ship_uj.has("interaction_fx") or ship_uj.has("interaction_fx_override"):
		push_error("VERIFY FAIL: ship must not have interaction_fx fields")
		ok = false
	if eq_uj.has("interaction_fx") or eq_uj.has("interaction_fx_override"):
		push_error("VERIFY FAIL: equip must not have interaction_fx fields")
		ok = false
	if TypedVariant.as_int(mj.get("fx_protocol", 1), 1) >= 2:
		push_error("VERIFY FAIL: mod.json must not set fx_protocol >= 2")
		ok = false
	if ok:
		print("VERIFY OK beitou-float-turret sample + gates")
		quit(0)
	else:
		print("VERIFY FAIL")
		quit(1)
