extends RefCounted
class_name FunctionFit
## Function bucket (副装备) runtime — EQUIPMENT.md · function_modules.json effects.

const MAX_SLOTS: int = 3

const _RESIST_KEYS: Array[String] = ["emp", "thermal", "kinetic", "explosive"]

## Size tiers allowed by hull group (EQUIPMENT §2).
static func allowed_sizes_for_ship(ship_data: Dictionary) -> PackedStringArray:
	var group: String = str(ship_data.get("ship_group", "")).to_lower()
	var role: String = str(ship_data.get("capital_role", "")).to_lower()
	if role != "" or group in [
		"dreadnought", "carrier", "force_auxiliary", "supercarrier", "titan",
		"freighter", "industrial", "capital", "capital_industrial",
	]:
		return PackedStringArray(["S", "M", "L", "XL"])
	match group:
		"battleship":
			return PackedStringArray(["S", "M", "L"])
		"cruiser", "battlecruiser":
			return PackedStringArray(["S", "M"])
		_:
			return PackedStringArray(["S"])

static func size_allowed_for_ship(ship_data: Dictionary, module_def: Dictionary) -> bool:
	var size: String = str(module_def.get("size", "S"))
	var allowed: PackedStringArray = allowed_sizes_for_ship(ship_data)
	if size not in allowed:
		return false
	var allowed_on: Variant = module_def.get("allowed_on", [])
	if typeof(allowed_on) == TYPE_ARRAY:
		return size in allowed_on
	return true

static func weapon_gate_matches(ship: ShipUnit, module_def: Dictionary) -> bool:
	var gate: Variant = module_def.get("weapon_gate", null)
	if gate == null or str(gate).is_empty():
		return true
	var ship_gate: String = str(ship.resolve_weapon_fx_kind()).to_lower()
	var want: String = str(gate).to_lower()
	if want == "heal":
		return ship.is_logistic or ship_gate == "heal"
	if want == "drone":
		return ship_gate == "drone" or TypedVariant.as_int(DataStore.get_ship(ship.ship_id).get("drone_bay_slots", 0)) > 0
	return ship_gate == want

static func module_active(ship: ShipUnit, module_def: Dictionary) -> bool:
	if module_def.is_empty():
		return false
	return weapon_gate_matches(ship, module_def)

static func _apply_implant_passive(ship: ShipUnit, fx: Dictionary) -> void:
	match str(fx.get("op", "")):
		"implant_auto_def":
			var pct: float = TypedVariant.as_float(fx.get("pct", 40.0)) / 100.0
			ship.tracking *= 1.0 + pct
			ship.explosion_velocity *= 1.0 + pct
		"implant_bombing":
			## Passive drone speed only; ×2 damage / release window applied in combat hooks.
			var spd_pct: float = TypedVariant.as_float(fx.get("spd_pct", 20.0)) / 100.0
			ship._drone_buff_stats["speed"] = TypedVariant.as_float(ship._drone_buff_stats.get("speed", 0.0)) + spd_pct

static func shop_pool_ids() -> Array:
	if DataStore.has_method("function_module_shop_pool_ids"):
		return DataStore.function_module_shop_pool_ids()
	var ids: Array = []
	for k: Variant in DataStore.function_modules.keys():
		var d: Dictionary = DataStore.function_modules[k]
		if not TypedVariant.as_bool(d.get("shop_pool", true)):
			continue
		ids.append(str(k))
	ids.sort()
	return ids

static func shop_pool_roll(rng: Callable) -> String:
	var pool: Array = shop_pool_ids()
	if pool.is_empty():
		return ""
	var idx: int = TypedVariant.as_int(rng.call("shop_fn", 0, pool.size() - 1))
	return str(pool[clampi(idx, 0, pool.size() - 1)])

static func is_cyno_def(module_def: Dictionary) -> bool:
	return str(module_def.get("kind", "")) == "cyno"


## Covert cyno hulls have no function-bucket strip / cannot fit shop modules (EQUIPMENT.md).
static func is_cyno_hull(ship_data: Dictionary) -> bool:
	if str(ship_data.get("capital_role", "")).to_lower() == "covert_cyno":
		return true
	var fs: Variant = ship_data.get("function_slots", {})
	if typeof(fs) != TYPE_DICTIONARY:
		return false
	@warning_ignore("unsafe_cast")
	var _fs_d: Dictionary = fs as Dictionary
	var slots: Array = TypedVariant.as_array(_fs_d.get("slots", []))
	for m: Variant in slots:
		if typeof(m) == TYPE_DICTIONARY and is_cyno_def(TypedVariant.as_dict(m)):
			return true
	return false


static func ship_allows_function_fit(ship_data: Dictionary) -> bool:
	return not is_cyno_hull(ship_data)


static func targeting_kind(module_def: Dictionary) -> String:
	return str(module_def.get("targeting", "none"))

static func is_hostile_targeting(module_def: Dictionary) -> bool:
	return targeting_kind(module_def) == "enemy"

static func is_ally_targeting(module_def: Dictionary) -> bool:
	var t: String = targeting_kind(module_def)
	return t == "ally" or t == "ally_cap"

## Build fit entries `{id, def}` from ship JSON slots + runtime ids.
static func entries_from_slot_list(slots: Array) -> Array:
	var out: Array = []
	for m: Variant in slots:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = TypedVariant.as_dict(m).duplicate(true)
		if is_cyno_def(md):
			out.append({"id": str(md.get("id", "cyno")), "def": md})
			continue
		var fid: String = str(md.get("id", md.get("module_id", "")))
		if fid.is_empty():
			continue
		var def: Dictionary = DataStore.get_function_module(fid)
		if def.is_empty():
			continue
		out.append({"id": fid, "def": def})
		if out.size() >= MAX_SLOTS:
			break
	return out

## Passive stat application after reload_stats baseline (linear stack, no penalty).
static func apply_passives_to_ship(ship: ShipUnit) -> void:
	ship._function_damage_mul = 1.0
	ship._drone_buff_stats.clear()
	ship._fit_passive_resist_add.clear()
	var fit: Array = ship.get_function_fit()
	for entry: Variant in fit:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if def.is_empty() or is_cyno_def(def):
			continue
		if not module_active(ship, def):
			continue
		if not TypedVariant.as_bool(def.get("passive", false)):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			_apply_passive_effect(ship, fxd, def)

	_apply_passive_resists(ship)
	_recompute_passive_derived(ship)

static func _apply_passive_effect(ship: ShipUnit, fx: Dictionary, module_def: Dictionary) -> void:
	match str(fx.get("op", "")):
		"add_resist":
			_queue_resist_add(ship, str(fx.get("layer", "armor")), TypedVariant.as_float(fx.get("amount", 0.0)))
		"mul_stat":
			_mul_ship_stat(ship, str(fx.get("stat", "")), TypedVariant.as_float(fx.get("mul", 1.0)))
		"add_stat":
			_add_ship_stat(ship, str(fx.get("stat", "")), TypedVariant.as_float(fx.get("amount", 0.0)))
		"mul_damage_gate":
			if module_active(ship, module_def):
				ship._function_damage_mul *= TypedVariant.as_float(fx.get("mul", 1.0))
		"buff_drones":
			var stats: Dictionary = TypedVariant.as_dict(fx.get("stats", {}))
			for sk: Variant in stats.keys():
				var key: String = str(sk)
				var cur: float = TypedVariant.as_float(ship._drone_buff_stats.get(key, 1.0 if key == "damage" else 0.0))
				if key == "damage":
					ship._drone_buff_stats[key] = cur * TypedVariant.as_float(stats[sk])
				else:
					ship._drone_buff_stats[key] = cur + TypedVariant.as_float(stats[sk])
		_:
			if str(fx.get("op", "")).begins_with("implant_"):
				_apply_implant_passive(ship, fx)

static func _queue_resist_add(ship: ShipUnit, layer: String, amount_pct: float) -> void:
	var add: float = amount_pct / 100.0
	if not ship._fit_passive_resist_add.has(layer):
		ship._fit_passive_resist_add[layer] = {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}
	var bucket: Dictionary = ship._fit_passive_resist_add[layer]
	for k: String in _RESIST_KEYS:
		bucket[k] = TypedVariant.as_float(bucket.get(k, 0.0)) + add

static func _apply_passive_resists(ship: ShipUnit) -> void:
	for layer: Variant in ship._fit_passive_resist_add.keys():
		var layer_s: String = str(layer)
		var adds: Dictionary = ship._fit_passive_resist_add[layer_s]
		var dst: Dictionary
		var base: Dictionary
		match str(layer):
			"shield":
				dst = ship._shield_resist
				base = ship._base_shield_resist
			"armor":
				dst = ship._armor_resist
				base = ship._base_armor_resist
			"structure":
				dst = ship._structure_resist
				base = ship._base_structure_resist
			_:
				continue
		for k: String in _RESIST_KEYS:
			dst[k] = clampf(TypedVariant.as_float(base.get(k, 0.0)) + TypedVariant.as_float(adds.get(k, 0.0)), 0.0, 0.95)
	ship.shield_resist_emp = TypedVariant.as_float(ship._shield_resist.get("emp", 0.0))
	ship.armor_resist_emp = TypedVariant.as_float(ship._armor_resist.get("emp", 0.0))
	ship.structure_resist_emp = TypedVariant.as_float(ship._structure_resist.get("emp", 0.0))

static func _mul_ship_stat(ship: ShipUnit, stat: String, mul: float) -> void:
	match stat:
		"structure_hp", "shield_hp", "armor_hp":
			_mul_max_hp(ship, stat, mul)
		"speed":
			ship.base_speed *= mul
		"tracking":
			ship.tracking *= mul
		"optimal":
			ship.optimal_cells *= mul
		"falloff":
			ship.falloff_cells *= mul
		"attack_cycle_s":
			ship.attack_duration *= mul
			ship.base_attack_duration *= mul
		"capacitor_capacity":
			ship.cap_capacity *= mul
		"scan_resolution":
			ship.scan_resolution *= mul
		"signature_radius":
			ship.signature_radius *= mul
		"explosion_radius":
			ship.explosion_radius *= mul
		"explosion_velocity":
			ship.explosion_velocity *= mul
		"missile_drf", "drf":
			ship.missile_drf *= mul

static func _add_ship_stat(ship: ShipUnit, stat: String, amount: float) -> void:
	match stat:
		"structure_hp", "shield_hp", "armor_hp":
			_add_max_hp(ship, stat, amount)
		"capacitor_capacity":
			ship.cap_capacity += amount
		"scan_resolution":
			ship.scan_resolution += amount

static func _mul_max_hp(ship: ShipUnit, stat: String, mul: float) -> void:
	match stat:
		"shield_hp":
			ship.base_max_shield *= mul
			ship.max_shield = ship.base_max_shield
			ship.shield_hp = ship.max_shield
		"armor_hp":
			ship.base_max_armor *= mul
			ship.max_armor = ship.base_max_armor
			ship.armor_hp = ship.max_armor
		"structure_hp":
			ship.base_max_structure *= mul
			ship.max_structure = ship.base_max_structure
			ship.structure_hp = ship.max_structure

static func _add_max_hp(ship: ShipUnit, stat: String, amount: float) -> void:
	match stat:
		"shield_hp":
			ship.base_max_shield += amount
			ship.max_shield = ship.base_max_shield
			ship.shield_hp = ship.max_shield
		"armor_hp":
			ship.base_max_armor += amount
			ship.max_armor = ship.base_max_armor
			ship.armor_hp = ship.max_armor
		"structure_hp":
			ship.base_max_structure += amount
			ship.max_structure = ship.base_max_structure
			ship.structure_hp = ship.max_structure

static func _recompute_passive_derived(ship: ShipUnit) -> void:
	if ship.cap_capacity > 0.0 and ship.cap_current > ship.cap_capacity:
		ship.cap_current = ship.cap_capacity

## ---- Combat targeting (separate from main weapon bucket) ----

static func update_function_target(ship: ShipUnit, board: BoardController, weapon_target: ShipUnit) -> void:
	if ship.is_destroyed or ship.slot_type != "field":
		ship._function_target = null
		return
	var needs_hostile: bool = false
	var needs_ally: bool = false
	for entry: Variant in ship.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if def.is_empty() or is_cyno_def(def) or not module_active(ship, def):
			continue
		if TypedVariant.as_bool(def.get("passive", false)):
			continue
		if is_hostile_targeting(def):
			needs_hostile = true
		elif is_ally_targeting(def):
			needs_ally = true
	if not needs_hostile and not needs_ally:
		ship._function_target = null
		return
	if needs_hostile:
		if ship.is_logistic:
			var ally_needs: ShipUnit = _best_heal_ally(ship, board)
			if ally_needs != null:
				ship._function_target = null
				return
		var tgt: ShipUnit = weapon_target
		if tgt != null and is_instance_valid(tgt) and not tgt.is_destroyed and tgt.team_id != ship.team_id:
			ship._function_target = tgt
			return
		ship._function_target = _pick_enemy(ship, board)
		return
	if needs_ally:
		ship._function_target = _pick_ally_cap(ship, board)

static func _pick_enemy(ship: ShipUnit, board: BoardController) -> ShipUnit:
	var enemy_team: int = ShipUnit.TEAM_AI if ship.team_id == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
	var best: ShipUnit = null
	var best_d: float = 99999.0
	for o: ShipUnit in board.field_ships(enemy_team):
		if o.is_destroyed:
			continue
		var d: float = ship.grid_dist_to(o)
		if d < best_d:
			best_d = d
			best = o
	return best

static func _pick_ally_cap(ship: ShipUnit, board: BoardController) -> ShipUnit:
	var best: ShipUnit = null
	var best_frac: float = 2.0
	var best_d: float = 99999.0
	for o: ShipUnit in board.field_ships(ship.team_id):
		if o == ship or o.is_destroyed or o.is_unmanned:
			continue
		if o.cap_capacity <= 0.0:
			continue
		var frac: float = o.cap_current / o.cap_capacity
		var d: float = ship.grid_dist_to(o)
		if frac < best_frac - 0.001 or (absf(frac - best_frac) <= 0.001 and d < best_d):
			best_frac = frac
			best_d = d
			best = o
	return best

static func _best_heal_ally(ship: ShipUnit, board: BoardController) -> ShipUnit:
	## Mirror CombatResolver: FAX heavy repair prefers mother (CAPITAL §6).
	if str(ship.unmanned_kind) == "heavy_repair_drone" and ship.mother_ship_id != 0:
		var mother: ShipUnit = instance_from_id(ship.mother_ship_id) as ShipUnit
		if (
			mother != null
			and is_instance_valid(mother)
			and not mother.is_destroyed
			and mother.team_id == ship.team_id
			and mother.slot_type == "field"
			and not mother.is_unmanned
			and mother.needs_heal_for_race(ship.race)
		):
			return mother
	var best: ShipUnit = null
	var best_d: float = 99999.0
	for o: ShipUnit in board.field_ships(ship.team_id):
		if o == ship or o.is_destroyed or o.is_unmanned:
			continue
		if not o.needs_heal_for_race(ship.race):
			continue
		var d: float = ship.grid_dist_to(o)
		if d < best_d:
			best_d = d
			best = o
	return best

## ---- Active module tick ----

static func tick_active_modules(
	ship: ShipUnit,
	board: BoardController,
	sim_dt: float,
	sim_time: float,
	auth_rng: Callable,
) -> void:
	if ship.is_destroyed or ship.slot_type != "field" or not ship.functions_enabled():
		return
	_tick_implant_passives(ship, sim_dt, sim_time)
	for entry: Variant in ship.get_function_fit():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var fid: String = str(TypedVariant.as_dict(entry).get("id", ""))
		var def: Dictionary = TypedVariant.as_dict(TypedVariant.as_dict(entry).get("def", {}))
		if def.is_empty() or is_cyno_def(def) or not module_active(ship, def):
			continue
		if TypedVariant.as_bool(def.get("passive", false)):
			continue
		if str(def.get("activate", "periodic")) != "periodic":
			if str(def.get("activate", "")) == "on_need":
				if ship.max_shield <= 0.0 or ship.shield_hp >= ship.max_shield * 0.9:
					continue
			else:
				continue
		if ship.is_logistic and is_hostile_targeting(def):
			if _best_heal_ally(ship, board) != null:
				continue
		_try_fire_module(ship, board, fid, def, sim_dt, sim_time, auth_rng)

static func _runtime(ship: ShipUnit, fid: String) -> Dictionary:
	if not ship._function_runtime.has(fid):
		ship._function_runtime[fid] = {"cd": 0.0, "active_until": 0.0}
	return ship._function_runtime[fid]

static func _try_fire_module(
	ship: ShipUnit,
	board: BoardController,
	fid: String,
	def: Dictionary,
	sim_dt: float,
	sim_time: float,
	auth_rng: Callable,
) -> void:
	var rt: Dictionary = _runtime(ship, fid)
	rt["cd"] = maxf(0.0, TypedVariant.as_float(rt.get("cd", 0.0)) - sim_dt)
	if TypedVariant.as_float(rt.get("cd", 0.0)) > 0.0:
		return
	var cycle: float = TypedVariant.as_float(def.get("duration_s", 1.0))
	if cycle <= 0.0:
		cycle = 1.0
	var cap_need: float = TypedVariant.as_float(def.get("capacitor_need", 0.0))
	if cap_need > 0.0 and ship.cap_current < cap_need:
		return
	var tgt: ShipUnit = _resolve_module_target(ship, board, def)
	var range_cells: float = TypedVariant.as_float(def.get("range_cells", 0.0))
	if targeting_kind(def) != "none" and range_cells > 0.0:
		if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
			return
		if ship.grid_dist_to(tgt) > range_cells + 0.001:
			return
	if cap_need > 0.0:
		ship.cap_current = maxf(0.0, ship.cap_current - cap_need)
	_fire_module_effects(ship, tgt, def, sim_time, auth_rng)
	_play_function_fx(ship, tgt, def)
	rt["cd"] = cycle
	ship._function_runtime[fid] = rt


static func resolve_function_fx_kind(def: Dictionary) -> String:
	var line: String = str(def.get("line", "")).strip_edges().to_lower()
	var id: String = str(def.get("id", "")).strip_edges().to_lower()
	if line == "nos" or id.begins_with("nos_"):
		return "nos"
	if line == "neut" or id.begins_with("neut_"):
		return "neut"
	if line == "remote_cap" or id.begins_with("remote_cap"):
		return "remote_cap"
	match id:
		"sensor_dampener":
			return "sensor_damp"
		"tracking_disruptor":
			return "tracking_disrupt"
		"guidance_disruptor":
			return "guidance_disrupt"
		"target_painter":
			return "target_painter"
	return ""


static func _play_function_fx(ship: ShipUnit, tgt: ShipUnit, def: Dictionary) -> void:
	var kind: String = resolve_function_fx_kind(def)
	if kind == "":
		return
	if targeting_kind(def) != "none":
		if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
			return
	elif tgt == null:
		tgt = ship
	if ship == null or not is_instance_valid(ship) or not ship.is_inside_tree():
		return
	var root: Node = ship.get_tree().get_first_node_in_group("match_root")
	if root == null or not root.get("firing_fx"):
		return
	var fx: Variant = root.get("firing_fx")
	if fx == null or not (fx is Object):
		return
	@warning_ignore("unsafe_cast")
	var fx_obj: Object = fx as Object
	if not fx_obj.has_method("play_function"):
		return
	var dur: float = TypedVariant.as_float(def.get("duration_s", 1.0))
	## Match module active / cycle window (COMBAT §8.2) — do not clip to a short flash.
	@warning_ignore("unsafe_cast")
	fx_obj.call("play_function", ship, tgt, kind, maxf(0.35, dur))

static func _resolve_module_target(ship: ShipUnit, board: BoardController, def: Dictionary) -> ShipUnit:
	match targeting_kind(def):
		"enemy":
			var ft: Variant = ship._function_target
			if ft != null and is_instance_valid(ft) and ft is ShipUnit:
				@warning_ignore("unsafe_cast")
				var enemy: ShipUnit = ft as ShipUnit
				if not enemy.is_destroyed:
					return enemy
			ship._function_target = null
			return _pick_enemy(ship, board)
		"ally_cap":
			var ft2: Variant = ship._function_target
			if ft2 != null and is_instance_valid(ft2) and ft2 is ShipUnit:
				@warning_ignore("unsafe_cast")
				var ally: ShipUnit = ft2 as ShipUnit
				if not ally.is_destroyed:
					return ally
			ship._function_target = null
			return _pick_ally_cap(ship, board)
		_:
			return ship

static func _fire_module_effects(
	ship: ShipUnit,
	tgt: ShipUnit,
	def: Dictionary,
	_sim_time: float,
	_auth_rng: Callable,
) -> void:
	var dur: float = TypedVariant.as_float(def.get("duration_s", 0.0))
	for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
		if typeof(fx) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		var fxd: Dictionary = fx as Dictionary
		match str(fxd.get("op", "")):
			"repair":
				_apply_repair(ship, fxd)
			"nos":
				_apply_nos(ship, tgt, TypedVariant.as_float(fxd.get("amount", 0.0)))
			"neut":
				_apply_neut(ship, tgt, TypedVariant.as_float(fxd.get("amount", 0.0)))
			"remote_cap":
				_apply_remote_cap(ship, tgt, TypedVariant.as_float(fxd.get("amount", 0.0)))
			"add_resist_active":
				_apply_resist_buff(ship, fxd, dur, str(def.get("id", "fn")))
			"mul_stat_active":
				_apply_self_mul_buff(ship, fxd, dur, str(def.get("id", "fn")))
			"debuff_mul":
				if tgt != null and is_instance_valid(tgt):
					_apply_debuff_mul(tgt, fxd, dur, str(def.get("id", "fn")))

static func _apply_repair(ship: ShipUnit, fx: Dictionary) -> void:
	var layer: String = str(fx.get("layer", "armor"))
	var amount: float = TypedVariant.as_float(fx.get("amount", 0.0))
	var before: float = 0.0
	var after: float = 0.0
	match layer:
		"shield":
			before = ship.shield_hp
			ship.shield_hp = minf(ship.max_shield, ship.shield_hp + amount)
			after = ship.shield_hp
		"armor":
			before = ship.armor_hp
			ship.armor_hp = minf(ship.max_armor, ship.armor_hp + amount)
			after = ship.armor_hp
		"structure":
			before = ship.structure_hp
			ship.structure_hp = minf(ship.max_structure, ship.structure_hp + amount)
			after = ship.structure_hp
	var gained: float = after - before
	if gained > 0.5 and ship.has_method("_notify_health_bar_gain"):
		ship.call("_notify_health_bar_gain", layer, gained)
	if ship._health_bar:
		ship._health_bar.call("refresh")
	_spawn_equip_float(ship, gained, true, Color(0.35, 0.95, 0.55))

static func _apply_nos(ship: ShipUnit, tgt: ShipUnit, amount: float) -> void:
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		return
	if not TypedVariant.as_bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		return
	var drain: float = minf(amount, tgt.cap_current)
	tgt.cap_current = maxf(0.0, tgt.cap_current - drain)
	var before_self: float = ship.cap_current
	ship.cap_current = minf(ship.cap_capacity, ship.cap_current + drain)
	var gained: float = ship.cap_current - before_self
	if gained > 0.5 and ship.has_method("_notify_health_bar_gain"):
		ship.call("_notify_health_bar_gain", "cap", gained)
	_spawn_equip_float(tgt, -drain, false, Color(1.0, 0.4, 0.55))
	_spawn_equip_float(ship, gained, true, Color(0.95, 0.85, 0.35))

static func _apply_neut(_ship: ShipUnit, tgt: ShipUnit, amount: float) -> void:
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		return
	if not TypedVariant.as_bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		return
	var before: float = tgt.cap_current
	tgt.cap_current = maxf(0.0, tgt.cap_current - amount)
	_spawn_equip_float(tgt, tgt.cap_current - before, false, Color(1.0, 0.4, 0.55))

static func _apply_remote_cap(_ship: ShipUnit, tgt: ShipUnit, amount: float) -> void:
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed or tgt.is_unmanned:
		return
	if not TypedVariant.as_bool(DataStore.combat.get("capacitor_combat_enabled", false)):
		return
	var before: float = tgt.cap_current
	tgt.cap_current = minf(tgt.cap_capacity, tgt.cap_current + amount)
	var gained: float = tgt.cap_current - before
	if gained > 0.5 and tgt.has_method("_notify_health_bar_gain"):
		tgt.call("_notify_health_bar_gain", "cap", gained)
	_spawn_equip_float(tgt, gained, true, Color(0.95, 0.85, 0.35))


## Shared FloatTextPool on CombatResolver — presentation only; still runs in no-model.
static func _spawn_equip_float(ship: ShipUnit, delta_val: float, positive: bool, color: Color) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var applied: float = absf(delta_val)
	if applied < 1.0:
		return
	var pool: Node = _float_text_pool(ship)
	if pool == null or not pool.has_method("spawn"):
		return
	var text: String = ("+%d" if positive else "-%d") % roundi(applied)
	pool.call("spawn", ship.global_position, text, color)


static func _float_text_pool(ship: ShipUnit) -> Node:
	if ship == null or not ship.is_inside_tree():
		return null
	var root: Node = ship.get_tree().get_first_node_in_group("match_root")
	if root == null or root.get("combat") == null:
		return null
	var combat: Variant = root.get("combat")
	if combat == null or not (combat is Node):
		return null
	@warning_ignore("unsafe_cast")
	return (combat as Node).get_node_or_null("FloatTextPool")

static func _apply_resist_buff(ship: ShipUnit, fx: Dictionary, dur: float, source: String) -> void:
	var layer: String = str(fx.get("layer", "shield"))
	var add: float = TypedVariant.as_float(fx.get("amount", 0.0)) / 100.0
	var layers: Array = []
	if layer == "all":
		layers = ["shield", "armor", "structure"]
	else:
		layers = [layer]
	for ln: Variant in layers:
		for k: String in _RESIST_KEYS:
			ship.add_stat_modifier(source, "resist_%s_%s" % [ln, k], "add", add, dur, "%s_%s" % [source, ln])

static func _apply_self_mul_buff(ship: ShipUnit, fx: Dictionary, dur: float, source: String) -> void:
	var stat: String = str(fx.get("stat", ""))
	var mul: float = TypedVariant.as_float(fx.get("mul", 1.0))
	if stat.is_empty():
		return
	ship.add_stat_modifier(source, stat, "mul", mul, dur, source)

static func _apply_debuff_mul(tgt: ShipUnit, fx: Dictionary, dur: float, source: String) -> void:
	var stat: String = str(fx.get("stat", ""))
	var mul: float = TypedVariant.as_float(fx.get("mul", 1.0))
	if stat.is_empty():
		return
	tgt.add_stat_modifier(source, stat, "mul", mul, dur, "%s_%s" % [source, stat])

static func on_first_damage(ship: ShipUnit, sim_time: float) -> void:
	for entry: Variant in ship.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if def.is_empty() or not module_active(ship, def):
			continue
		if str(def.get("activate", "")) != "first_damage":
			continue
		var fid: String = str(TypedVariant.as_dict(entry).get("id", ""))
		var rt: Dictionary = _runtime(ship, fid)
		if TypedVariant.as_bool(rt.get("spent", false)):
			continue
		var cd_left: float = TypedVariant.as_float(rt.get("cooldown", 0.0)) - sim_time
		if cd_left > 0.0:
			continue
		rt["spent"] = true
		var dur: float = TypedVariant.as_float(def.get("duration_s", 0.0))
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			if str(fxd.get("op", "")) == "add_resist_active":
				_apply_resist_buff(ship, fxd, dur, fid)
		rt["cooldown"] = sim_time + TypedVariant.as_float(def.get("cooldown_s", 240.0))
		ship._function_runtime[fid] = rt

static func _tick_implant_passives(ship: ShipUnit, sim_dt: float, sim_time: float) -> void:
	var cd_left: float = TypedVariant.as_float(ship._implant_state.get("focus_shield_cd", 0.0))
	if cd_left > 0.0:
		ship._implant_state["focus_shield_cd"] = maxf(0.0, cd_left - sim_dt)
	for entry: Variant in ship.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(ship, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			if str(fxd.get("op", "")) == "implant_pulse_crystal":
				_tick_pulse_crystal(ship, fxd, sim_dt, sim_time)

static func _tick_pulse_crystal(ship: ShipUnit, fx: Dictionary, sim_dt: float, _sim_time: float) -> void:
	if ship.cap_capacity <= 0.0:
		return
	var frac: float = ship.cap_fraction()
	var low: float = TypedVariant.as_float(fx.get("low_pct", 50.0)) / 100.0
	var high: float = TypedVariant.as_float(fx.get("high_pct", 90.0)) / 100.0
	var st: Dictionary = TypedVariant.as_dict(ship._implant_state.get("pulse", {}))
	if frac <= low:
		st["mode"] = "swap"
	elif frac >= high:
		st["mode"] = "dmg"
	st["swap_cd"] = maxf(0.0, TypedVariant.as_float(st.get("swap_cd", 0.0)) - sim_dt)
	if str(st.get("mode", "dmg")) == "swap" and TypedVariant.as_float(st.get("swap_cd", 0.0)) <= 0.0:
		var shield_pct: float = TypedVariant.as_float(fx.get("shield_pct", 10.0)) / 100.0
		var gain_pct: float = TypedVariant.as_float(fx.get("gain_pct", 15.0)) / 100.0
		var xfer: float = ship.max_shield * shield_pct
		if ship.shield_hp >= xfer and xfer > 0.0:
			ship.shield_hp -= xfer
			var before_cap: float = ship.cap_current
			ship.cap_current = minf(ship.cap_capacity, ship.cap_current + ship.cap_capacity * gain_pct)
			var cap_gain: float = ship.cap_current - before_cap
			if cap_gain > 0.5 and ship.has_method("_notify_health_bar_gain"):
				ship.call("_notify_health_bar_gain", "cap", cap_gain)
			st["swap_cd"] = TypedVariant.as_float(fx.get("swap_s", 10.0))
	ship._implant_state["pulse"] = st

## ---- Attack / damage / heal hooks ----

static func modify_outgoing_damage(ship: ShipUnit, raw: Dictionary, _dist_cells: float) -> Dictionary:
	var mul: float = 1.0
	for entry: Variant in ship.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(ship, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			match str(fxd.get("op", "")):
				"implant_focus_crystal":
					var st: Dictionary = TypedVariant.as_dict(ship._implant_state.get("focus", {"stacks": 0}))
					var cap_pct: float = TypedVariant.as_float(fxd.get("cap_pct", 20.0))
					mul *= 1.0 + TypedVariant.as_float(st.get("stacks", 0)) * TypedVariant.as_float(fxd.get("stack_pct", 1.0)) / 100.0
					mul = minf(mul, 1.0 + cap_pct / 100.0)
				"implant_pulse_crystal":
					var pst: Dictionary = TypedVariant.as_dict(ship._implant_state.get("pulse", {}))
					if str(pst.get("mode", "dmg")) == "dmg":
						mul *= 1.0 + TypedVariant.as_float(fxd.get("dmg_pct", 15.0)) / 100.0
				"implant_sniper":
					var sn: Dictionary = TypedVariant.as_dict(ship._implant_state.get("sniper", {"shots": 0}))
					var every: int = TypedVariant.as_int(fxd.get("every", 10))
					sn["shots"] = TypedVariant.as_int(sn.get("shots", 0)) + 1
					ship._implant_state["sniper"] = sn
					if every > 0 and TypedVariant.as_int(sn.get("shots", 0)) % every == 0:
						mul *= TypedVariant.as_float(fxd.get("mul", 10.0))
						sn["force_hit"] = true
						ship._implant_state["sniper"] = sn
					else:
						mul *= 0.0
				"implant_thermal_cycle":
					var tc: Dictionary = TypedVariant.as_dict(ship._implant_state.get("thermal", {"round": 0}))
					tc["round"] = TypedVariant.as_int(tc.get("round", 0)) + 1
					ship._implant_state["thermal"] = tc
					if TypedVariant.as_int(tc.get("round", 0)) % 2 == 1:
						mul *= 1.0 + TypedVariant.as_float(fxd.get("dmg_pct", 15.0)) / 100.0
					else:
						var res_add: float = TypedVariant.as_float(fxd.get("res_pct", 15.0)) / 100.0
						for k: String in _RESIST_KEYS:
							ship.add_stat_modifier("thermal_cycle", "resist_armor_%s" % k, "add", res_add, ship.attack_duration, "thermal_cycle")
	var out: Dictionary = {}
	for k: Variant in raw.keys():
		out[k] = TypedVariant.as_float(raw[k]) * mul
	return out

static func consume_attack_cap_cost(ship: ShipUnit) -> void:
	for entry: Variant in ship.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(ship, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			if str(fxd.get("op", "")) == "implant_pulse_crystal" and ship.cap_capacity > 0.0:
				var pst: Dictionary = TypedVariant.as_dict(ship._implant_state.get("pulse", {}))
				if str(pst.get("mode", "dmg")) == "dmg":
					var cost: float = ship.cap_capacity * TypedVariant.as_float(fxd.get("cap_cost_pct", 5.0)) / 100.0
					ship.cap_current = maxf(0.0, ship.cap_current - cost)

static func attack_force_hit(ship: ShipUnit) -> bool:
	var sn: Dictionary = TypedVariant.as_dict(ship._implant_state.get("sniper", {}))
	return TypedVariant.as_bool(sn.get("force_hit", false))

static func clear_attack_force_hit(ship: ShipUnit) -> void:
	var sn: Dictionary = TypedVariant.as_dict(ship._implant_state.get("sniper", {}))
	sn.erase("force_hit")
	ship._implant_state["sniper"] = sn

static func on_attack_hit(ship: ShipUnit, _tgt: ShipUnit, _dealt: float) -> void:
	for entry: Variant in ship.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(ship, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			if str(fxd.get("op", "")) == "implant_focus_crystal":
				var st: Dictionary = TypedVariant.as_dict(ship._implant_state.get("focus", {"stacks": 0}))
				var cap_pct: float = TypedVariant.as_float(fxd.get("cap_pct", 20.0))
				st["stacks"] = mini(TypedVariant.as_int(st.get("stacks", 0)) + 1, TypedVariant.as_int(cap_pct / maxf(TypedVariant.as_float(fxd.get("stack_pct", 1.0)), 0.001)))
				ship._implant_state["focus"] = st

static func on_attack_miss(ship: ShipUnit) -> void:
	for entry: Variant in ship.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(ship, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			if str(fxd.get("op", "")) == "implant_focus_crystal":
				var st: Dictionary = TypedVariant.as_dict(ship._implant_state.get("focus", {"stacks": 0}))
				var stacks: int = TypedVariant.as_int(st.get("stacks", 0))
				if stacks <= 0:
					continue
				st["stacks"] = 0
				ship._implant_state["focus"] = st
				var cd_key: String = "focus_shield_cd"
				if TypedVariant.as_float(ship._implant_state.get(cd_key, 0.0)) > 0.0:
					continue
				var heal_pct: float = float(stacks) * TypedVariant.as_float(fxd.get("stack_pct", 1.0)) / 100.0
				var before_sh: float = ship.shield_hp
				ship.shield_hp = minf(ship.max_shield, ship.shield_hp + ship.max_shield * heal_pct)
				var sh_gain: float = ship.shield_hp - before_sh
				if sh_gain > 0.5 and ship.has_method("_notify_health_bar_gain"):
					ship.call("_notify_health_bar_gain", "shield", sh_gain)
				ship._implant_state[cd_key] = TypedVariant.as_float(fxd.get("shield_cd", 20.0))

static func transform_damage_dict(source: ShipUnit, target: ShipUnit, dmg: Dictionary) -> Dictionary:
	var out: Dictionary = dmg.duplicate()
	for entry: Variant in source.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(source, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			match str(fxd.get("op", "")):
				"implant_warhead":
					out = _warhead_transform(target, out)
				"implant_he_coil":
					out = _penetration_transform(target, out, TypedVariant.as_float(fxd.get("pen_pct", 15.0)))
					target.add_stat_modifier("he_coil", "speed", "mul", 1.0 - TypedVariant.as_float(fxd.get("spd_pct", 10.0)) / 100.0, 5.0, "he_coil")
	return out

static func _warhead_transform(target: ShipUnit, dmg: Dictionary) -> Dictionary:
	var total: float = 0.0
	for k: String in _RESIST_KEYS:
		total += TypedVariant.as_float(dmg.get(k, 0.0))
	if total <= 0.0:
		return dmg
	if target.shield_hp > 0.0:
		return {"emp": total, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}
	if target.armor_hp > 0.0:
		return {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": total}
	var each: float = total / 4.0
	return {"emp": each, "thermal": each, "kinetic": each, "explosive": each}

static func _penetration_transform(_target: ShipUnit, dmg: Dictionary, pen_pct: float) -> Dictionary:
	## Flat boost — resist applied later; emulate pen by scaling raw up.
	var factor: float = 1.0 + pen_pct / 100.0
	var out: Dictionary = {}
	for k: String in _RESIST_KEYS:
		out[k] = TypedVariant.as_float(dmg.get(k, 0.0)) * factor
	return out

static func on_hit_landed(source: ShipUnit, target: ShipUnit, dealt: float, auth_rng: Callable) -> void:
	if dealt <= 0.0:
		return
	for entry: Variant in source.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(source, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			match str(fxd.get("op", "")):
				"implant_support_proj":
					if TypedVariant.as_float(auth_rng.call("support_strip")) <= TypedVariant.as_float(fxd.get("strip_pct", 5.0)) / 100.0:
						pass  # inventory strip deferred to UI layer
					if target.cap_capacity > 0.0:
						var neut: float = target.cap_capacity * TypedVariant.as_float(fxd.get("neut_pct", 1.0)) / 100.0
						target.cap_current = maxf(0.0, target.cap_current - neut)

static func scale_heal_amounts(source: ShipUnit, amounts: Dictionary) -> Dictionary:
	var out: Dictionary = amounts.duplicate()
	var shield_mul: float = 1.0
	for entry: Variant in source.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(source, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			if str(fxd.get("op", "")) == "implant_shield_support":
				var st: Dictionary = TypedVariant.as_dict(source._implant_state.get("shield_sup", {"n": 0}))
				st["n"] = TypedVariant.as_int(st.get("n", 0)) + 1
				source._implant_state["shield_sup"] = st
				var every: int = TypedVariant.as_int(fxd.get("every", 3))
				if every > 0 and TypedVariant.as_int(st.get("n", 0)) % every == 0:
					shield_mul *= TypedVariant.as_float(fxd.get("mul", 2.0))
	out["shield"] = TypedVariant.as_float(out.get("shield", 0.0)) * shield_mul
	return out

static func apply_armor_support_on_repair(source: ShipUnit, target: ShipUnit) -> void:
	for entry: Variant in source.get_function_fit():
		var _entry_d: Dictionary = TypedVariant.as_dict(entry)
		var def: Dictionary = TypedVariant.as_dict(_entry_d.get("def", {}))
		if not module_active(source, def):
			continue
		for fx: Variant in TypedVariant.as_array(def.get("effects", [])):
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			@warning_ignore("unsafe_cast")
			var fxd: Dictionary = fx as Dictionary
			if str(fxd.get("op", "")) == "implant_armor_support":
				var add: float = TypedVariant.as_float(fxd.get("res_pct", 10.0)) / 100.0
				for k: String in _RESIST_KEYS:
					target.add_stat_modifier("armor_sup", "resist_armor_%s" % k, "add", add, 5.0, "armor_sup")


static func reset_combat_state(ship: ShipUnit) -> void:
	ship._function_target = null
	ship._function_runtime.clear()
	ship._implant_state.clear()


## Same-line size up: two identical ids whose def has synth_next → that next id.
## Cross-type implant: two different materials matching some implant's synth_from (order-free).
## Returns {ok, result_id, reason}.
static func try_synth(id_a: String, id_b: String) -> Dictionary:
	var a: String = id_a.strip_edges()
	var b: String = id_b.strip_edges()
	if a == "" or b == "":
		return {"ok": false, "result_id": "", "reason": "empty"}
	if a == b:
		var def: Dictionary = DataStore.get_function_module(a)
		var nxt: Variant = def.get("synth_next", null)
		if nxt == null or str(nxt).is_empty():
			return {"ok": false, "result_id": "", "reason": "no_upgrade"}
		return {"ok": true, "result_id": str(nxt), "reason": "upgrade"}
	for fid: String in DataStore.function_module_ids():
		var def: Dictionary = DataStore.get_function_module(fid)
		if not TypedVariant.as_bool(def.get("implant", false)):
			continue
		var mats: Variant = def.get("synth_from", null)
		if typeof(mats) != TYPE_ARRAY:
			continue
		@warning_ignore("unsafe_cast")
		var mats_a: Array = mats as Array
		if mats_a.size() != 2:
			continue
		var m0: String = str(mats_a[0])
		var m1: String = str(mats_a[1])
		if (a == m0 and b == m1) or (a == m1 and b == m0):
			return {"ok": true, "result_id": fid, "reason": "implant"}
	return {"ok": false, "result_id": "", "reason": "no_recipe"}
