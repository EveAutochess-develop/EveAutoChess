extends RefCounted
class_name LegalActions
## Enumerate protocol actions for a seat. No side effects.
## HUD / ONNX / LLM all consume this list; CommandDispatcher executes it.


static func action_type_of(action: Dictionary) -> String:
	return str(action.get("action_type", ""))


static func list_legal_actions(phase: String, seat_state: Dictionary) -> Array:
	## If the seat snapshot already carries an explicit list, pass it through.
	var preset_v: Variant = seat_state.get("legal_actions", [])
	if preset_v is Array:
		var preset: Array = preset_v
		if not preset.is_empty():
			return preset
	var out: Array = []
	var gold: int = TypedVariant.as_int(seat_state.get("gold", 0), 0)
	var hangar_free: bool = TypedVariant.as_bool(seat_state.get("hangar_free", true), true)
	var field_free: bool = TypedVariant.as_bool(seat_state.get("field_free", true), true)
	var bag_free: bool = TypedVariant.as_bool(seat_state.get("bag_free", true), true)
	var seat: int = TypedVariant.as_int(seat_state.get("seat_id", -1), -1)
	if phase == "titan_pick" or phase == "lobby":
		out.append({"action_type": "titan_pick", "seat": seat})
		return out
	if phase != "prepare" and phase != "":
		if TypedVariant.as_bool(seat_state.get("can_prepare_commit", false), false):
			out.append({"action_type": "prepare_commit", "seat": seat})
		return out
	var shop_v: Variant = seat_state.get("shop_slots", [])
	var shop: Array = shop_v if shop_v is Array else []
	for i: int in range(shop.size()):
		var slot: Dictionary = TypedVariant.as_dict(shop[i])
		if TypedVariant.as_bool(slot.get("purchased", false), false):
			continue
		var sid: int = TypedVariant.as_int(slot.get("ship_id", 0), 0)
		var cost: int = TypedVariant.as_int(slot.get("cost", 0), 0)
		if cost <= 0:
			var sd: Dictionary = DataStore.get_ship(sid) if DataStore != null else {}
			cost = TypedVariant.as_int(sd.get("cost", 0), 0)
		if gold < cost:
			continue
		var cyno: bool = TypedVariant.as_bool(slot.get("requires_cyno_entry", false), false)
		if hangar_free:
			out.append({
				"action_type": "shop_buy_ship",
				"seat": seat,
				"slot_index": i,
				"ship_id": sid,
				"cost": cost,
			})
		elif field_free and not cyno:
			out.append({
				"action_type": "shop_buy_ship",
				"seat": seat,
				"slot_index": i,
				"ship_id": sid,
				"cost": cost,
			})
	var eq_v: Variant = seat_state.get("equipment_slots", [])
	var eqs: Array = eq_v if eq_v is Array else []
	for i: int in range(eqs.size()):
		var es: Dictionary = TypedVariant.as_dict(eqs[i])
		if TypedVariant.as_bool(es.get("purchased", false), false):
			continue
		var item_id: String = str(es.get("id", ""))
		var ecost: int = TypedVariant.as_int(es.get("cost", 0), 0)
		if gold < ecost or not bag_free or item_id == "":
			continue
		out.append({
			"action_type": "shop_buy_equip",
			"seat": seat,
			"slot_index": i,
			"item_id": item_id,
			"cost": ecost,
		})
	var refresh_cost: int = TypedVariant.as_int(seat_state.get("refresh_cost", 2), 2)
	if gold >= refresh_cost:
		out.append({"action_type": "shop_refresh", "seat": seat, "free": false})
	var exp_cost: int = TypedVariant.as_int(seat_state.get("buy_exp_cost", 4), 4)
	if gold >= exp_cost and not TypedVariant.as_bool(seat_state.get("level_capped", false), false):
		out.append({"action_type": "buy_exp", "seat": seat})
	var sellable_v: Variant = seat_state.get("sellable_instance_ids", [])
	var sellable: Array = sellable_v if sellable_v is Array else []
	for sid_v: Variant in sellable:
		out.append({
			"action_type": "sell",
			"seat": seat,
			"ship_instance_id": TypedVariant.as_int(sid_v, 0),
		})
	if TypedVariant.as_bool(seat_state.get("can_prepare_commit", true), true):
		out.append({"action_type": "prepare_commit", "seat": seat})
	return out


static func action_key(action: Dictionary) -> String:
	var at: String = action_type_of(action)
	var seat: int = TypedVariant.as_int(action.get("seat", -1), -1)
	return "%s|seat=%d|%s" % [at, seat, JSON.stringify(action)]


static func validate_action_against_list(action: Dictionary, legal_actions: Array) -> Dictionary:
	var at: String = action_type_of(action)
	if at == "":
		return {"accepted": false, "reason_key": "missing_action_type"}
	if legal_actions.is_empty():
		return {"accepted": true}
	var want: String = JSON.stringify(action)
	for la_v: Variant in legal_actions:
		var la: Dictionary = TypedVariant.as_dict(la_v)
		if at != action_type_of(la):
			continue
		if JSON.stringify(la) == want:
			return {"accepted": true}
		## Slot-level match: ignore extra keys the dispatcher injects (team, star).
		if at == "shop_buy_ship" and TypedVariant.as_int(la.get("slot_index", -2), -2) == TypedVariant.as_int(action.get("slot_index", -3), -3):
			return {"accepted": true}
		if at == "shop_buy_equip" and TypedVariant.as_int(la.get("slot_index", -2), -2) == TypedVariant.as_int(action.get("slot_index", -3), -3):
			return {"accepted": true}
		if at == "shop_refresh" or at == "buy_exp" or at == "prepare_commit" or at == "titan_pick":
			return {"accepted": true}
	return {"accepted": false, "reason_key": "not_in_legal_actions"}
