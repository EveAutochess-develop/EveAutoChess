extends RefCounted
class_name ShipWeaponDerive
## Manned hull attack = attack slots × representative weapon module (ammo baked in).
## Unmanned units keep stars[] attack. See SHIP_STATS_V2 §2.2.

const DEFAULT_KIT_METERS_PER_CELL: float = 500.0

## weapon_fx → size_key → module_type_id  (4×4 = 16)
const WEAPON_KIT: Dictionary = {
	"laser": {"frigate": 453, "destroyer": 453, "cruiser": 456, "large": 462, "capital": 11002810000},
	"rail": {"frigate": 561, "destroyer": 561, "cruiser": 570, "large": 574, "capital": 11000320000},
	"cannon": {"frigate": 485, "destroyer": 485, "cruiser": 491, "large": 498, "capital": 11004810000},
	"missile": {"frigate": 499, "destroyer": 499, "cruiser": 501, "large": 13320, "capital": 11023000000},
}

## race → [frigate, cruiser, large] remote repair module type ids
const REPAIR_KIT: Dictionary = {
	"amarr": [11355, 11357, 11359],
	"caldari": [3586, 3596, 3606],
	"gallente": [27932, 27930, 27904],
	"minmatar": [11355, 11357, 11359],
}


static func uses_baked_star_attack(ship: Dictionary) -> bool:
	return TypedVariant.as_bool(ship.get("is_unmanned", false))


static func _guns_muted(ship: Dictionary) -> bool:
	var fx: String = str(ship.get("weapon_fx", ""))
	var role: String = str(ship.get("capital_role", ""))
	return role == "carrier" or fx == "mining" or TypedVariant.as_bool(ship.get("is_mining_ship", false))


static func should_derive(ship: Dictionary) -> bool:
	## True when attack/repair must come from equipment+slots (not stars[]).
	if uses_baked_star_attack(ship):
		return false
	if DataStore == null:
		return false
	if _guns_muted(ship):
		return true
	var fx: String = str(ship.get("weapon_fx", ""))
	var logistic: bool = TypedVariant.as_bool(ship.get("is_logistic", false)) or fx == "heal"
	if logistic:
		var rid: int = resolve_repair_module_id(ship)
		if rid > 0 and not DataStore.get_module(rid).is_empty():
			return true
	var explicit: int = TypedVariant.as_int(ship.get("source_module_type_id", 0))
	if explicit > 0:
		## Echoes capital modules not yet in equipment table → keep stars[].
		return not DataStore.get_module(explicit).is_empty()
	var mid: int = resolve_module_id(ship)
	if mid <= 0:
		## No kit (titan/freighter placeholders with 0 slots) → derive zeros.
		return true
	return not DataStore.get_module(mid).is_empty()


static func attack_slot_count(ship: Dictionary) -> int:
	var n: int = TypedVariant.as_int(ship.get("attack_weapon_slots", 0))
	if n <= 0:
		n = TypedVariant.as_int(ship.get("hi_slots", 0))
	return maxi(n, 0)


static func kit_meters_per_cell() -> float:
	if DataStore == null:
		return DEFAULT_KIT_METERS_PER_CELL
	var cd: Dictionary = DataStore.combat
	var v: float = TypedVariant.as_float(cd.get("weapon_kit_meters_per_cell", 0.0))
	if v > 0.0:
		return v
	v = TypedVariant.as_float(cd.get("speed_meters_per_cell", 0.0))
	return v if v > 0.0 else DEFAULT_KIT_METERS_PER_CELL


static func meters_to_cells(meters: float) -> float:
	return snappedf(float(meters) / kit_meters_per_cell(), 0.001)


static func size_key(ship: Dictionary) -> String:
	var tier: String = str(ship.get("weapon_tier", ""))
	if tier == "small":
		return "frigate"
	if tier == "large":
		return "large"
	if tier == "medium":
		return "cruiser"
	if tier == "capital":
		return "capital"
	var group: String = str(ship.get("ship_group", ""))
	if group in ["frigate", "destroyer"]:
		return "frigate"
	if group in ["dreadnought", "carrier", "force_auxiliary", "titan"]:
		return "capital"
	if group == "battleship":
		return "large"
	if group in ["cruiser", "battlecruiser"]:
		return "cruiser"
	return "frigate"


static func resolve_module_id(ship: Dictionary) -> int:
	var mod_id: int = TypedVariant.as_int(ship.get("source_module_type_id", 0))
	if mod_id > 0:
		return mod_id
	var fx: String = str(ship.get("weapon_fx", ""))
	if fx == "heal":
		var race: String = str(ship.get("race", "amarr")).to_lower()
		fx = str({"amarr": "laser", "caldari": "rail", "minmatar": "cannon", "gallente": "rail"}.get(race, "laser"))
	var kit_by_fx: Dictionary = TypedVariant.as_dict(WEAPON_KIT.get(fx, {}))
	if kit_by_fx.is_empty():
		return 0
	return TypedVariant.as_int(kit_by_fx.get(size_key(ship), 0))


static func resolve_repair_module_id(ship: Dictionary) -> int:
	var rid: int = TypedVariant.as_int(ship.get("source_repair_module_type_id", 0))
	if rid > 0:
		return rid
	var race: String = str(ship.get("race", "amarr")).to_lower()
	var kit: Variant = REPAIR_KIT.get(race, REPAIR_KIT["amarr"])
	var arr: Array = TypedVariant.as_array(kit)
	if arr.size() < 3:
		return 0
	var key: String = size_key(ship)
	if key == "large" or key == "capital":
		return TypedVariant.as_int(arr[2])
	if key == "cruiser":
		return TypedVariant.as_int(arr[1])
	return TypedVariant.as_int(arr[0])


static func _zero_damage() -> Dictionary:
	return {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}


static func _scale_damage(d: Dictionary, mul: float) -> Dictionary:
	return {
		"emp": snappedf(TypedVariant.as_float(d.get("emp", 0.0)) * mul, 0.01),
		"thermal": snappedf(TypedVariant.as_float(d.get("thermal", 0.0)) * mul, 0.01),
		"kinetic": snappedf(TypedVariant.as_float(d.get("kinetic", 0.0)) * mul, 0.01),
		"explosive": snappedf(TypedVariant.as_float(d.get("explosive", 0.0)) * mul, 0.01),
	}


static func _per_slot_weapon(mod_id: int) -> Dictionary:
	## Damage fields on the module are already per-slot final (ammo baked in).
	var out: Dictionary = {
		"damage": _zero_damage(),
		"tracking": 0.0,
		"optimal": 0.0,
		"falloff": 0.0,
		"optimal_sig_radius": 40.0,
		"rate_of_fire_s": 1.0,
		"explosion_radius": 0.0,
		"explosion_velocity": 0.0,
		"drf": 0.0,
	}
	if mod_id <= 0 or DataStore == null:
		return out
	var mod: Dictionary = DataStore.get_module(mod_id)
	if mod.is_empty():
		return out
	out["damage"] = {
		"emp": TypedVariant.as_float(mod.get("emDamage", 0.0)),
		"thermal": TypedVariant.as_float(mod.get("thermalDamage", 0.0)),
		"kinetic": TypedVariant.as_float(mod.get("kineticDamage", 0.0)),
		"explosive": TypedVariant.as_float(mod.get("explosiveDamage", 0.0)),
	}
	out["tracking"] = TypedVariant.as_float(mod.get("trackingSpeed", 0.0))
	out["optimal"] = meters_to_cells(TypedVariant.as_float(mod.get("maxRange", 0.0)))
	out["falloff"] = meters_to_cells(TypedVariant.as_float(mod.get("falloff", 0.0)))
	out["optimal_sig_radius"] = TypedVariant.as_float(mod.get("signatureResolution", 40.0))
	var rof_ms: float = TypedVariant.as_float(mod.get("rateOfFire", 1000.0))
	out["rate_of_fire_s"] = snappedf(rof_ms / 1000.0, 0.001)
	out["explosion_radius"] = TypedVariant.as_float(mod.get("explosionRadius", 0.0))
	out["explosion_velocity"] = TypedVariant.as_float(mod.get("explosionVelocity", 0.0))
	out["drf"] = TypedVariant.as_float(mod.get("aoeDamageReductionFactor", 0.0))
	return out


static func _racial_repair(amount: float, race: String) -> Dictionary:
	if amount <= 0.0:
		return {"shield": 0.0, "armor": 0.0, "structure": 0.0}
	match race:
		"amarr":
			return {"shield": 0.0, "armor": amount, "structure": 0.0}
		"caldari":
			return {"shield": amount, "armor": 0.0, "structure": 0.0}
		"gallente":
			return {"shield": 0.0, "armor": 0.0, "structure": amount}
		_:
			var half: float = amount / 2.0
			return {"shield": float(ceili(half)), "armor": floorf(half), "structure": 0.0}


static func derive_attack(ship: Dictionary, _star: int = 1) -> Dictionary:
	## Returns attack-side fields for a manned hull. Empty if caller should use stars[].
	## Damage is always ★1 kit baseline; star DPH is ShipUnit.star_dph_mul (SHIP_STATS_V2 §2.5).
	if not should_derive(ship):
		return {}
	var fx: String = str(ship.get("weapon_fx", ""))
	var slots: int = attack_slot_count(ship)
	var zero: Dictionary = {
		"damage": _zero_damage(),
		"tracking": 0.0,
		"optimal": 0.0,
		"falloff": 0.0,
		"optimal_sig_radius": 40.0,
		"explosion_radius": 0.0,
		"explosion_velocity": 0.0,
		"drf": 0.0,
		"repair": {"shield": 0.0, "armor": 0.0, "structure": 0.0},
		"attack_cycle_s": -1.0,
	}
	var mute_guns: bool = _guns_muted(ship)
	var mid: int = resolve_module_id(ship)
	var wpn: Dictionary
	if mute_guns or mid <= 0:
		wpn = {
			"damage": _zero_damage(),
			"tracking": 0.0,
			"optimal": 0.0,
			"falloff": 0.0,
			"optimal_sig_radius": 40.0,
			"rate_of_fire_s": TypedVariant.as_float(ship.get("attack_cycle_s", 1.0)),
			"explosion_radius": 0.0,
			"explosion_velocity": 0.0,
			"drf": 0.0,
		}
	else:
		wpn = _per_slot_weapon(mid)
	var slot_dmg: Dictionary = TypedVariant.as_dict(wpn.get("damage", {}))
	var total_1: Dictionary = {
		"emp": TypedVariant.as_float(slot_dmg.get("emp", 0.0)) * float(slots),
		"thermal": TypedVariant.as_float(slot_dmg.get("thermal", 0.0)) * float(slots),
		"kinetic": TypedVariant.as_float(slot_dmg.get("kinetic", 0.0)) * float(slots),
		"explosive": TypedVariant.as_float(slot_dmg.get("explosive", 0.0)) * float(slots),
	}
	zero["damage"] = _scale_damage(total_1, 1.0)
	zero["tracking"] = TypedVariant.as_float(wpn.get("tracking", 0.0))
	zero["optimal"] = TypedVariant.as_float(wpn.get("optimal", 0.0))
	zero["falloff"] = TypedVariant.as_float(wpn.get("falloff", 0.0))
	zero["optimal_sig_radius"] = TypedVariant.as_float(wpn.get("optimal_sig_radius", 40.0))
	zero["explosion_radius"] = TypedVariant.as_float(wpn.get("explosion_radius", 0.0))
	zero["explosion_velocity"] = TypedVariant.as_float(wpn.get("explosion_velocity", 0.0))
	zero["drf"] = TypedVariant.as_float(wpn.get("drf", 0.0))
	zero["attack_cycle_s"] = TypedVariant.as_float(wpn.get("rate_of_fire_s", -1.0))

	var logistic: bool = TypedVariant.as_bool(ship.get("is_logistic", false)) or fx == "heal"
	if logistic:
		var rid: int = resolve_repair_module_id(ship)
		var amount: float = 0.0
		var cycle_s: float = TypedVariant.as_float(wpn.get("rate_of_fire_s", 0.0))
		var opt: float = TypedVariant.as_float(wpn.get("optimal", 0.0))
		if rid > 0 and DataStore != null:
			var rmod: Dictionary = DataStore.get_module(rid)
			if not rmod.is_empty():
				amount = TypedVariant.as_float(
					rmod.get("structureDamageAmount",
						rmod.get("armorDamageAmount",
							rmod.get("shieldBonus", 0.0)))
				)
				var dur_ms: float = TypedVariant.as_float(rmod.get("duration", rmod.get("rateOfFire", 3000.0)))
				cycle_s = snappedf(dur_ms / 1000.0, 0.001)
				opt = meters_to_cells(TypedVariant.as_float(rmod.get("maxRange", 0.0)))
		var hi: int = TypedVariant.as_int(ship.get("hi_slots", slots))
		var total_rep: float = amount * float(maxi(hi, 0))
		zero["repair"] = _racial_repair(total_rep, str(ship.get("race", "amarr")).to_lower())
		if opt > 0.0:
			zero["optimal"] = opt
		if cycle_s > 0.0:
			zero["attack_cycle_s"] = cycle_s
	return zero


static func merge_into_star(ship: Dictionary, star_row: Dictionary, star: int) -> Dictionary:
	## Duplicate star row and overlay derived attack when equipment is resolvable.
	var out: Dictionary = star_row.duplicate(true)
	## Board engagement range: ship -1 inherits module; 0–999 overrides (COMBAT §3.1).
	out["attack_range"] = resolve_attack_range(ship, star_row)
	if star_row.is_empty() or not should_derive(ship):
		return out
	var derived: Dictionary = derive_attack(ship, star)
	if derived.is_empty():
		return out
	out["damage"] = derived["damage"]
	out["tracking"] = derived["tracking"]
	out["optimal"] = derived["optimal"]
	out["falloff"] = derived["falloff"]
	out["optimal_sig_radius"] = derived["optimal_sig_radius"]
	out["repair"] = derived["repair"]
	if TypedVariant.as_float(derived.get("explosion_radius", 0.0)) > 0.0 or str(ship.get("weapon_fx", "")) == "missile":
		out["explosion_radius"] = derived["explosion_radius"]
		out["explosion_velocity"] = derived["explosion_velocity"]
		out["drf"] = derived["drf"]
	out["_attack_cycle_s"] = derived["attack_cycle_s"]
	return out


## Board cells. Ship star `attack_range`: -1 → module; 0–999 → override; else clamp.
static func resolve_attack_range(ship: Dictionary, star_row: Dictionary) -> float:
	var has_field: bool = star_row.has("attack_range")
	var raw: float = TypedVariant.as_float(star_row.get("attack_range", -1.0), -1.0)
	## Missing or exact -1 → inherit equipment (COMBAT §3.1).
	var inherit: bool = (not has_field) or is_equal_approx(raw, -1.0)
	if not inherit:
		return clampf(raw, 0.0, 999.0)
	if uses_baked_star_attack(ship):
		## Unmanned with inherit sentinel and no kit → safe 1 cell.
		return 1.0
	var fx: String = str(ship.get("weapon_fx", ""))
	var logistic: bool = TypedVariant.as_bool(ship.get("is_logistic", false)) or fx == "heal"
	var mid: int = resolve_repair_module_id(ship) if logistic else resolve_module_id(ship)
	if mid > 0 and DataStore != null:
		var mod: Dictionary = DataStore.get_module(mid)
		if not mod.is_empty() and mod.has("attack_range"):
			return clampf(TypedVariant.as_float(mod.get("attack_range", 1.0)), 0.0, 999.0)
	return clampf(default_attack_range_cells(ship), 0.0, 999.0)


## Fallback when module lacks `attack_range` (COMBAT §3.1 table).
static func default_attack_range_cells(ship: Dictionary) -> float:
	var fx: String = str(ship.get("weapon_fx", "")).to_lower()
	if TypedVariant.as_bool(ship.get("is_logistic", false)) or fx == "heal":
		match size_key(ship):
			"large", "capital":
				return 12.0
			"cruiser":
				return 8.0
			_:
				return 4.0
	if fx == "missile" or size_key(ship) == "capital":
		return 999.0
	var sk: String = size_key(ship)
	match fx:
		"rail":
			match sk:
				"large":
					return 10.0
				"cruiser":
					return 4.0
				_:
					return 2.0
		"laser":
			match sk:
				"large":
					return 13.0
				"cruiser":
					return 6.0
				_:
					return 3.0
		"cannon":
			match sk:
				"large":
					return 16.0
				"cruiser":
					return 8.0
				_:
					return 4.0
		_:
			return 1.0
