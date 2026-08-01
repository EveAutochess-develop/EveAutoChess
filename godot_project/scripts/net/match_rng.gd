extends RefCounted
class_name MatchRng
## SEMI_ASYNC_NETPLAY §2 — match_seed + per-battle seeds[10] API skeleton.

var match_seed: int = 0
var rules_hash: String = ""
var _match_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## battle_serial -> { seeds: PackedInt64Array(10), apply_table: Dictionary }
var _battles: Dictionary = {}

func configure(p_match_seed: int, p_rules_hash: String = "") -> void:
	match_seed = p_match_seed
	rules_hash = p_rules_hash
	_match_rng.seed = match_seed if match_seed != 0 else 1

static func compute_rules_hash() -> String:
	## Content+shell version string; callers may override.
	var ver := str(ProjectSettings.get_setting("application/config/version", "dev"))
	return ver

func stream_randf(stream: String = "match") -> float:
	## Whole-match streams (shop / mm) — not battle seeds[10].
	if stream == "match":
		return _match_rng.randf()
	return _match_rng.randf()

func stream_randi_range(stream: String, from_v: int, to_v: int) -> int:
	if stream == "match":
		return _match_rng.randi_range(from_v, to_v)
	return _match_rng.randi_range(from_v, to_v)

func begin_battle(battle_serial: int, master_entropy: int = 0) -> Dictionary:
	var master := master_entropy
	if master == 0:
		master = int(hash(str(match_seed) + ":" + str(battle_serial)))
	var rng := RandomNumberGenerator.new()
	rng.seed = master if master != 0 else 1
	var seeds := PackedInt64Array()
	seeds.resize(10)
	var seen: Dictionary = {}
	for i in range(10):
		var s: int = int(rng.randi())
		while seen.has(s):
			s = int(rng.randi())
		seen[s] = true
		seeds[i] = s
	## Minimal apply table — expand with event kinds later.
	var apply_table := {
		"turret_hit": 0,
		"retarget_tiebreak": 1,
		"orbit_dir": 2,
		"deploy_cell": 3,
		"cyno_cell": 4,
		"creep_buy": 5,
		"creep_cell": 6,
		"pvp_home": 7,
	}
	## Shuffle table values across 0..9 using remaining entropy.
	var keys: Array = apply_table.keys()
	for i in range(keys.size()):
		apply_table[keys[i]] = i % 10
	var job := {"seeds": seeds, "apply_table": apply_table, "slots": []}
	var slots: Array = []
	for i in range(10):
		var slot_rng := RandomNumberGenerator.new()
		slot_rng.seed = seeds[i]
		slots.append(slot_rng)
	job["slots"] = slots
	_battles[battle_serial] = job
	return {"seeds": seeds, "apply_table": apply_table}

func roll(battle_serial: int, event_kind: String) -> float:
	if not _battles.has(battle_serial):
		begin_battle(battle_serial)
	var job: Dictionary = _battles[battle_serial]
	var table: Dictionary = job.get("apply_table", {})
	var slot_i := int(table.get(event_kind, 0))
	var slots: Array = job.get("slots", [])
	if slot_i < 0 or slot_i >= slots.size():
		slot_i = 0
	var slot: RandomNumberGenerator = slots[slot_i]
	return slot.randf()

func roll_int(battle_serial: int, event_kind: String, from_v: int, to_v: int) -> int:
	if not _battles.has(battle_serial):
		begin_battle(battle_serial)
	var job: Dictionary = _battles[battle_serial]
	var table: Dictionary = job.get("apply_table", {})
	var slot_i := int(table.get(event_kind, 0))
	var slots: Array = job.get("slots", [])
	if slot_i < 0 or slot_i >= slots.size():
		slot_i = 0
	var slot: RandomNumberGenerator = slots[slot_i]
	return slot.randi_range(from_v, to_v)

func pick_index(battle_serial: int, event_kind: String, count: int) -> int:
	if count <= 0:
		return 0
	return roll_int(battle_serial, event_kind, 0, count - 1)
