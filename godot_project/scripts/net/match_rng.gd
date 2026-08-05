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
	_streams.clear()


## Named whole-match streams (shop / shop_ai / mm) — salt from match_seed.
var _streams: Dictionary = {}


func _rng_for(stream: String) -> RandomNumberGenerator:
	var key: String = stream if stream != "" else "match"
	if key == "match":
		return _match_rng
	if _streams.has(key):
		@warning_ignore("unsafe_cast")
		return _streams[key] as RandomNumberGenerator
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = int(hash(str(match_seed) + ":" + key))
	if r.seed == 0:
		r.seed = 1
	_streams[key] = r
	return r


func stream_randf(stream: String = "match") -> float:
	## Whole-match streams (shop / mm) — not battle seeds[10].
	return _rng_for(stream).randf()


func stream_randi_range(stream: String, from_v: int, to_v: int) -> int:
	return _rng_for(stream).randi_range(from_v, to_v)


static func compute_rules_hash() -> String:
	## Content+shell version string; callers may override.
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	return ver


func has_battle(battle_serial: int) -> bool:
	return _battles.has(battle_serial)


func begin_battle(battle_serial: int, master_entropy: int = 0) -> Dictionary:
	var master: int = master_entropy
	if master == 0:
		master = int(hash(str(match_seed) + ":" + str(battle_serial)))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = master if master != 0 else 1
	var seeds: PackedInt64Array = PackedInt64Array()
	seeds.resize(10)
	var seen: Dictionary = {}
	for i: int in range(10):
		var s: int = int(rng.randi())
		while seen.has(s):
			s = int(rng.randi())
		seen[s] = true
		seeds[i] = s
	## SEMI_ASYNC §2.3 event kinds → slot indices (A = battle seeds[10]).
	var apply_table: Dictionary = {
		"turret_hit": 0,
		"retarget_tiebreak": 1,
		"orbit_dir": 2,
		"deploy_cell": 3,
		"cyno_cell": 4,
		"cyno_anchor": 4,
		"creep_buy": 5,
		"creep_cell": 6,
		"pvp_home": 7,
		"mining_pick": 8,
		"mining_wander": 8,
		"isolation_debris": 9,
		"isolation_debris_dmg": 9,
	}
	var keys: Array = apply_table.keys()
	for i: int in range(keys.size()):
		## Keep declared slots; only remap unassigned collisions via master entropy.
		if TypedVariant.as_int(apply_table[keys[i]]) < 0 or TypedVariant.as_int(apply_table[keys[i]]) > 9:
			apply_table[keys[i]] = i % 10
	var job: Dictionary = {"seeds": seeds, "apply_table": apply_table, "slots": []}
	var slots: Array = []
	for i: int in range(10):
		var slot_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		slot_rng.seed = seeds[i]
		slots.append(slot_rng)
	job["slots"] = slots
	_battles[battle_serial] = job
	return {"seeds": seeds, "apply_table": apply_table}

func roll(battle_serial: int, event_kind: String) -> float:
	if not _battles.has(battle_serial):
		begin_battle(battle_serial)
	var job: Dictionary = TypedVariant.as_dict(_battles[battle_serial])
	var table: Dictionary = TypedVariant.as_dict(job.get("apply_table", {}))
	var slot_i: int = TypedVariant.as_int(table.get(event_kind, 0))
	var slots: Array = TypedVariant.as_array(job.get("slots", []))
	if slot_i < 0 or slot_i >= slots.size():
		slot_i = 0
	var slot_v: Variant = slots[slot_i]
	if not (slot_v is RandomNumberGenerator):
		return 0.0
	@warning_ignore("unsafe_cast")
	var slot: RandomNumberGenerator = slot_v as RandomNumberGenerator
	return slot.randf()

func roll_int(battle_serial: int, event_kind: String, from_v: int, to_v: int) -> int:
	if not _battles.has(battle_serial):
		begin_battle(battle_serial)
	var job: Dictionary = TypedVariant.as_dict(_battles[battle_serial])
	var table: Dictionary = TypedVariant.as_dict(job.get("apply_table", {}))
	var slot_i: int = TypedVariant.as_int(table.get(event_kind, 0))
	var slots: Array = TypedVariant.as_array(job.get("slots", []))
	if slot_i < 0 or slot_i >= slots.size():
		slot_i = 0
	var slot_v: Variant = slots[slot_i]
	if not (slot_v is RandomNumberGenerator):
		return from_v
	@warning_ignore("unsafe_cast")
	var slot: RandomNumberGenerator = slot_v as RandomNumberGenerator
	return slot.randi_range(from_v, to_v)

func pick_index(battle_serial: int, event_kind: String, count: int) -> int:
	if count <= 0:
		return 0
	return roll_int(battle_serial, event_kind, 0, count - 1)
