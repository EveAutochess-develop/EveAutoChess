extends Node
class_name AiController

var _board: BoardController
var _match: MatchController
var endless: bool = false

func bind(match_ctrl: MatchController, board: BoardController) -> void:
	_match = match_ctrl
	_board = board
	AdminBus.register_handler(&"ai.deploy_ship", _on_deploy)
	# Endless: absorb citadel damage to AI
	AdminBus.after_handoff.connect(_on_after)

func init_army() -> void:
	endless = _match.mode == "endless"
	_deploy_up_to_quota()

func after_round() -> void:
	## Keep survivors; add at most deploys_per_round if under hard cap vs player pop.
	_deploy_up_to_quota()

## Hard cap from player deployable pop (level/gold→exp→level). AI ≤ floor(pop × 2.5).
func field_cap() -> int:
	var pop := maxi(1, _match.population_limit())
	var mult := float(DataStore.ai.get("field_cap_vs_player_pop", 2.5))
	return maxi(1, int(floor(float(pop) * mult)))

func _deploy_up_to_quota() -> void:
	var per := maxi(0, int(DataStore.ai.get("deploys_per_round", 1)))
	var placed := 0
	while placed < per:
		if not _try_deploy_one():
			break
		placed += 1
	_board.recalculate_fetters(ShipUnit.TEAM_AI)

func _try_deploy_one() -> bool:
	var cap := field_cap()
	if _board.count_field(ShipUnit.TEAM_AI) >= cap:
		return false
	var tries := int(DataStore.ai.get("deploy_try_limit", 28))
	var tag := str(DataStore.ai.get("cruiser_ship_group_tag", "cruiser"))
	var block_until := int(DataStore.ai.get("cruiser_block_battle_stages", 3))
	var ids: Array = DataStore.ship_ids()
	if ids.is_empty():
		return false
	for _i in range(tries):
		if _board.count_field(ShipUnit.TEAM_AI) >= cap:
			return false
		var cell := _board.find_empty_field(ShipUnit.TEAM_AI)
		if cell.x < 0:
			return false
		var sid: int = ids[randi() % ids.size()]
		if _match.battle_game_stage_count <= block_until and DataStore.ship_has_group(sid, tag):
			continue
		AdminBus.request(&"ai.deploy_ship", {
			"ship_id": sid,
			"star": 1,
			"team": ShipUnit.TEAM_AI,
			"x": cell.x,
			"z": cell.y,
		})
		_board.try_upgrades_all()
		return true
	return false

func _on_deploy(payload: Dictionary) -> Dictionary:
	var ship_id := int(payload.get("ship_id", 0))
	var x := int(payload.get("x", 0))
	var z := int(payload.get("z", 0))
	var star := int(payload.get("star", 1))
	# Enforce hard cap even if deploy comes from elsewhere.
	if _board.count_field(ShipUnit.TEAM_AI) >= field_cap():
		return {"accepted": false, "reason_key": "ai_field_cap"}
	AdminBus.request(&"board.deploy", {
		"ship_id": ship_id,
		"star": star,
		"team": ShipUnit.TEAM_AI,
		"slot_type": "field",
		"x": x,
		"z": z,
	})
	return {"accepted": true}

func _on_after(channel: StringName, _payload: Dictionary, _result: Dictionary) -> void:
	if endless and String(channel) == "citadel.damage":
		# Swallow damage targeting AI by marking — Match already skips applying AI HP
		pass
