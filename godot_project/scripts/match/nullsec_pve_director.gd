extends RefCounted
class_name NullsecPveDirector
## Full pve_eliminate + pve_salvage orchestration helpers.

const TASK_ELIMINATE := "pve_eliminate"
const TASK_SALVAGE := "pve_salvage"
const TASK_PVP := "pvp"

var creep_ai: PveCreepAi = PveCreepAi.new()
var match_rng: MatchRng
var battle_serial: int = 0
var current_task: String = TASK_ELIMINATE
var freighter_ship_id: int = 0
var freighter_alive: bool = true
var slide_done: bool = false
## Lowsec room (D-EAC-47): every round is PVP — skip nullsec stage table.
var always_pvp: bool = false

func setup(rng: MatchRng, serial: int) -> void:
	match_rng = rng
	battle_serial = serial
	creep_ai.setup(rng, serial)

func pick_task(round_r: int) -> String:
	## MULTIPLAYER_MATCH_FLOW §5: stage one R1 PVE · R2 PVE · R3 PVP · R4 PVE;
	## from R5 on odd rounds are PVE and even rounds are PVP.
	## Lowsec exception: always PVP (MATCH_FLOW §3 lead-in).
	if always_pvp or is_pvp_round(round_r):
		current_task = TASK_PVP
		return current_task
	if round_r % 2 == 0:
		current_task = TASK_SALVAGE
	else:
		current_task = TASK_ELIMINATE
	return current_task

static func is_pvp_round(round_r: int) -> bool:
	if round_r <= 4:
		return round_r == 3
	return round_r % 2 == 0

func is_pve_task() -> bool:
	return current_task == TASK_ELIMINATE or current_task == TASK_SALVAGE

func lock_creeps(gold: int, level: int, pop_limit: int) -> Array:
	return creep_ai.lock_from_player_state(gold, level, pop_limit)

## `exclude_race`: local seat titan race — salvage freighter must not share it
## (FREIGHTER_AND_TITAN §1.2 异族硬门). Empty = no filter (tests / fallback).
func pick_freighter_id(exclude_race: String = "") -> int:
	var pool: Array = []
	var exclude := exclude_race.strip_edges().to_lower()
	for sid in DataStore.ship_ids():
		var ship: Dictionary = DataStore.get_ship(int(sid))
		var tags: Array = ship.get("tags", []) as Array
		var ok := false
		for t in tags:
			if str(t) == "freighter" or str(t) == "pve_salvage":
				ok = true
				break
		if not (ok or str(ship.get("ship_group", "")) == "freighter"):
			continue
		if exclude != "" and _ship_race_key(ship) == exclude:
			continue
		pool.append(int(sid))
	## Data hole: prefer a wrong-race freighter over spawning nothing.
	if pool.is_empty() and exclude != "":
		return pick_freighter_id("")
	if pool.is_empty():
		freighter_ship_id = 211
		freighter_alive = true
		return freighter_ship_id
	var idx := 0
	if match_rng:
		idx = match_rng.pick_index(battle_serial, "creep_buy", pool.size())
	freighter_ship_id = int(pool[idx])
	freighter_alive = true
	return freighter_ship_id


static func _ship_race_key(ship: Dictionary) -> String:
	var race := str(ship.get("race", "")).strip_edges().to_lower()
	if race != "":
		return race
	for t in (ship.get("fetter_ids", []) as Array):
		var k := str(t).to_lower()
		if k in ["amarr", "caldari", "gallente", "minmatar"]:
			return k
	for t in (ship.get("tags", []) as Array):
		var k2 := str(t).to_lower()
		if k2 in ["amarr", "caldari", "gallente", "minmatar"]:
			return k2
	return ""

## Enemy half-field center cell heuristic (board-dependent; caller maps cell→world).
func salvage_center_cell(cols: int = 8, rows: int = 8) -> Vector2i:
	return Vector2i(int(cols / 2.0), int(rows * 0.25))

func evaluate_battle_end(enemy_ships_alive: int) -> Dictionary:
	## Returns {success:bool, task:String, reason:String}
	if current_task == TASK_SALVAGE:
		var ok := freighter_alive
		return {
			"success": ok,
			"task": current_task,
			"reason": "freighter_survived" if ok else "freighter_destroyed",
			"deduct_titan": false,
		}
	var ok2 := enemy_ships_alive <= 0
	return {
		"success": ok2,
		"task": current_task,
		"reason": "cleared" if ok2 else "enemies_remain",
		"deduct_titan": false,
	}

## Slide-in: start positions off-board; caller tweens to cell world pos.
func slide_start_offset() -> Vector3:
	return Vector3(0, 0, -18.0)
