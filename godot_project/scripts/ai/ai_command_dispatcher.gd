extends RefCounted
class_name AiCommandDispatcher
## Maps protocol actions onto AdminBus / MatchController. Same path for HUD, ONNX, LLM.


static func _action_type(action: Dictionary) -> String:
	return str(action.get("action_type", ""))


func dispatch(action: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var at: String = _action_type(action)
	if at == "":
		return {"accepted": false, "reason_key": "missing_action_type"}
	match at:
		"shop_refresh", "shop_buy_ship", "shop_buy_equip", "buy_exp":
			var ai_v: Variant = ctx.get("ai", null)
			if ai_v != null and ai_v is Object:
				var ai_obj: Object = ai_v
				if ai_obj.has_method("apply_protocol_economy"):
					return TypedVariant.as_dict(ai_obj.call("apply_protocol_economy", action))
			if at == "shop_refresh":
				var free: bool = TypedVariant.as_bool(action.get("free", false), false)
				return AdminBus.request(&"shop.refresh", {"free": free, "persist": true, "via": "ai_dispatcher"})
			if at == "shop_buy_ship":
				if not action.has("slot_index"):
					return {"accepted": false, "reason_key": "missing_shop_fields"}
				var sid: int = TypedVariant.as_int(action.get("ship_id", 0), 0)
				var cost: int = TypedVariant.as_int(action.get("cost", 0), 0)
				if sid <= 0:
					return {"accepted": false, "reason_key": "missing_shop_fields"}
				return AdminBus.request(&"shop.purchase", {
					"slot_index": TypedVariant.as_int(action.get("slot_index", -1), -1),
					"ship_id": sid,
					"cost": cost,
					"team": TypedVariant.as_int(action.get("team", ShipUnit.TEAM_PLAYER), ShipUnit.TEAM_PLAYER),
					"via": "ai_dispatcher",
				})
			if at == "shop_buy_equip":
				if not action.has("slot_index") or str(action.get("item_id", "")) == "":
					return {"accepted": false, "reason_key": "missing_equip_fields"}
				return AdminBus.request(&"shop.equipment_purchase", {
					"slot_index": TypedVariant.as_int(action.get("slot_index", -1), -1),
					"item_id": str(action.get("item_id", "")),
					"cost": TypedVariant.as_int(action.get("cost", 0), 0),
					"team": TypedVariant.as_int(action.get("team", ShipUnit.TEAM_PLAYER), ShipUnit.TEAM_PLAYER),
				})
			var m_v: Variant = ctx.get("match_ctrl", null)
			if m_v != null and m_v is Object:
				var m: Object = m_v
				if m.has_method("buy_exp"):
					m.call("buy_exp")
					return {"accepted": true}
			return {"accepted": false, "reason_key": "missing_match_ctrl"}
		"deploy":
			return AdminBus.request(&"board.deploy", {
				"ship_id": TypedVariant.as_int(action.get("ship_id", 0), 0),
				"star": TypedVariant.as_int(action.get("star", 1), 1),
				"team": TypedVariant.as_int(action.get("team", ShipUnit.TEAM_PLAYER), ShipUnit.TEAM_PLAYER),
				"slot_type": str(action.get("slot_type", "field")),
				"x": TypedVariant.as_int(action.get("x", 0), 0),
				"z": TypedVariant.as_int(action.get("z", 0), 0),
				"skip_upgrade": TypedVariant.as_bool(action.get("skip_upgrade", false), false),
			})
		"move_or_swap":
			return AdminBus.request(&"board.move", action)
		"sell":
			return AdminBus.request(&"board.sell", action)
		"prepare_commit":
			var m2_v: Variant = ctx.get("match_ctrl", null)
			if m2_v != null and m2_v is Object:
				var m2: Object = m2_v
				if m2.has_method("commit_prepare_complete"):
					m2.call("commit_prepare_complete")
					return {"accepted": true}
			return {"accepted": false, "reason_key": "missing_match_ctrl"}
		"titan_pick":
			return {"accepted": true, "reason_key": "titan_pick_deferred"}
		_:
			return {"accepted": false, "reason_key": "unknown_action_type"}


