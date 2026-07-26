extends Node
class_name ShopController

signal shop_changed()

var slots: Array = []  # Array of {ship_id:int, purchased:bool} size from economy
var _match: MatchController
var _board: BoardController

func bind(match_ctrl: MatchController, board: BoardController) -> void:
	_match = match_ctrl
	_board = board
	AdminBus.register_handler(&"shop.purchase", _on_purchase)
	AdminBus.register_handler(&"shop.refresh", _on_refresh)

func refresh_shop(free: bool) -> void:
	var payload := {"free": free, "team": ShipUnit.TEAM_PLAYER}
	AdminBus.request(&"shop.refresh", payload)

func _on_refresh(payload: Dictionary) -> Dictionary:
	var free := bool(payload.get("free", false))
	var cost := int(DataStore.economy.get("refresh_cost", 2))
	if not free:
		if _match.player_gold < cost:
			return {"accepted": false, "reason_key": "no_gold"}
		_match.try_spend(cost)
	var n := int(DataStore.economy.get("shop_slot_count", 5))
	slots.clear()
	for i in range(n):
		var sid := _roll_ship_id()
		slots.append({"ship_id": sid, "purchased": false})
	shop_changed.emit()
	return {"accepted": true}

func _roll_ship_id() -> int:
	var ids: Array = DataStore.ship_ids()
	var tag := str(DataStore.ai.get("cruiser_ship_group_tag", "cruiser"))
	var block_until := int(DataStore.ai.get("cruiser_block_battle_stages", 3))
	for _attempt in range(40):
		var sid: int = ids[randi() % ids.size()]
		if _match.battle_game_stage_count <= block_until and DataStore.ship_has_group(sid, tag):
			continue
		return sid
	return int(ids[0])

func try_buy(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot: Dictionary = slots[slot_index]
	if slot.get("purchased", false):
		return
	var ship_id := int(slot.get("ship_id", 0))
	var cost := int(DataStore.get_ship(ship_id).get("cost", 0))
	AdminBus.request(&"shop.purchase", {
		"slot_index": slot_index,
		"ship_id": ship_id,
		"cost": cost,
		"team": ShipUnit.TEAM_PLAYER,
	})

func _on_purchase(payload: Dictionary) -> Dictionary:
	var idx := int(payload.get("slot_index", -1))
	var ship_id := int(payload.get("ship_id", 0))
	var cost := int(payload.get("cost", 0))
	if idx < 0 or idx >= slots.size():
		return {"accepted": false}
	if slots[idx].get("purchased", false):
		return {"accepted": false}
	var hangar := _board.find_empty_hangar(ShipUnit.TEAM_PLAYER)
	if hangar.x < 0:
		get_tree().call_group("match_root", "show_notice", "备战席已满")
		return {"accepted": false, "reason_key": "hangar_full"}
	if not _match.try_spend(cost):
		get_tree().call_group("match_root", "show_notice", "PLEX不足")
		return {"accepted": false, "reason_key": "no_gold"}
	slots[idx]["purchased"] = true
	AdminBus.request(&"board.deploy", {
		"ship_id": ship_id,
		"star": 1,
		"team": ShipUnit.TEAM_PLAYER,
		"slot_type": "hangar",
		"x": hangar.x,
		"z": hangar.y,
	})
	_board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	shop_changed.emit()
	return {"accepted": true}

func manual_refresh() -> void:
	refresh_shop(false)
