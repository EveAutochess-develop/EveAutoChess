extends RefCounted
class_name ShipWeaponDerive
## Manned hull attack = attack slots × representative weapon module (ammo baked in).
## Unmanned units keep stars[] attack. See SHIP_STATS_V2 §2.2.

const DEFAULT_KIT_METERS_PER_CELL := 500.0

## weapon_fx → size_key → module_type_id  (4×4 = 16)
const WEAPON_KIT := {
	"laser": {"frigate": 453, "destroyer": 453, "cruiser": 456, "large": 462, "capital": 11002810000},
	"rail": {"frigate": 561, "destroyer": 561, "cruiser": 570, "large": 574, "capital": 11000320000},
	"cannon": {"frigate": 485, "destroyer": 485, "cruiser": 491, "large": 498, "capital": 11004810000},
	"missile": {"frigate": 499, "destroyer": 499, "cruiser": 501, "large": 13320, "capital": 11023000000},
}

## race → [frigate, cruiser, large] remote repair module type ids
const REPAIR_KIT := {
	"amarr": [11355, 11357, 11359],
	"caldari": [3586, 3596, 3606],
	"gallente": [27932, 27930, 27904],
	"minmatar": [11355, 11357, 11359],
}


static func uses_baked_star_attack(ship: Dictionary) -> bool:
	return bool(ship.get("is_unmanned", false))


static func _guns_muted(ship: Dictionary) -> bool:
	var fx := str(ship.get("weapon_fx", ""))
	var role := str(ship.get("capital_role", ""))
	return role == "carrier" or fx == "mining" or bool(ship.get("is_mining_ship", false))


static func should_derive(ship: Dictionary) -> bool:
	## True when attack/repair must come from equipment+slots (not stars[]).
	if uses_baked_star_attack(ship):
		return false
	if DataStore == null:
		return false
	if _guns_muted(ship):
		return true
	var fx := str(ship.get("weapon_fx", ""))
	var logistic := bool(ship.get("is_logistic", false)) or fx == "heal"
	if logistic:
		var rid := resolve_repair_module_id(ship)
		if rid > 0 and not DataStore.get_module(rid).is_empty():
			return true
	var explicit := int(ship.get("source_module_type_id", 0))
	if explicit > 0:
		## Echoes capital modules not yet in equipment table → keep stars[].
		return not DataStore.get_module(explicit).is_empty()
	var mid := resolve_module_id(ship)
	if mid <= 0:
		## No kit (titan/freighter placeholders with 0 slots) → derive zeros.
		return true
	return not DataStore.get_module(mid).is_empty()


static func attack_slot_count(ship: Dictionary) -> int:
	var n := int(ship.get("attack_weapon_slots", 0))
	if n <= 0:
		n = int(ship.get("hi_slots", 0))
	return maxi(n, 0)


static func kit_meters_per_cell() -> float:
	if DataStore == null:
		return DEFAULT_KIT_METERS_PER_CELL
	var cd: Dictionary = DataStore.combat
	var v := float(cd.get("weapon_kit_meters_per_cell", 0.0))
	if v > 0.0:
		return v
	v = float(cd.get("speed_meters_per_cell", 0.0))
	return v if v > 0.0 else DEFAULT_KIT_METERS_PER_CELL


static func meters_to_cells(meters: float) -> float:
	return snappedf(float(meters) / kit_meters_per_cell(), 0.001)


static func size_key(ship: Dictionary) -> String:
	var tier := str(ship.get("weapon_tier", ""))
	if tier == "small":
		return "frigate"
	if tier == "large":
		return "large"
	if tier == "medium":
		return "cruiser"
	if tier == "capital":
		return "capital"
	var group := str(ship.get("ship_group", ""))
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
	var mod_id := int(ship.get("source_module_type_id", 0))
	if mod_id > 0:
		return mod_id
	var fx := str(ship.get("weapon_fx", ""))
	if fx == "heal":
		var race := str(ship.get("race", "amarr")).to_lower()
		fx = {"amarr": "laser", "caldari": "rail", "minmatar": "cannon", "gallente": "rail"}.get(race, "laser")
	var kit_by_fx: Variant = WEAPON_KIT.get(fx, {})
	if typeof(kit_by_fx) != TYPE_DICTIONARY:
		return 0
	return int((kit_by_fx as Dictionary).get(size_key(ship), 0))


static func resolve_repair_module_id(ship: Dictionary) -> int:
	var rid := int(ship.get("source_repair_module_type_id", 0))
	if rid > 0:
		return rid
	var race := str(ship.get("race", "amarr")).to_lower()
	var kit: Variant = REPAIR_KIT.get(race, REPAIR_KIT["amarr"])
	if typeof(kit) != TYPE_ARRAY or (kit as Array).size() < 3:
		return 0
	var arr: Array = kit
	var key := size_key(ship)
	if key == "large" or key == "capital":
		return int(arr[2])
	if key == "cruiser":
		return int(arr[1])
	return int(arr[0])


static func _zero_damage() -> Dictionary:
	return {"emp": 0.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0}


static func _scale_damage(d: Dictionary, mul: float) -> Dictionary:
	return {
		"emp": snappedf(float(d.get("emp", 0.0)) * mul, 0.01),
		"thermal": snappedf(float(d.get("thermal", 0.0)) * mul, 0.01),
		"kinetic": snappedf(float(d.get("kinetic", 0.0)) * mul, 0.01),
		"explosive": snappedf(float(d.get("explosive", 0.0)) * mul, 0.01),
	}


static func _per_slot_weapon(mod_id: int) -> Dictionary:
	## Damage fields on the module are already per-slot final (ammo baked in).
	var out := {
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
		"emp": float(mod.get("emDamage", 0.0)),
		"thermal": float(mod.get("thermalDamage", 0.0)),
		"kinetic": float(mod.get("kineticDamage", 0.0)),
		"explosive": float(mod.get("explosiveDamage", 0.0)),
	}
	out["tracking"] = float(mod.get("trackingSpeed", 0.0))
	out["optimal"] = meters_to_cells(float(mod.get("maxRange", 0.0)))
	out["falloff"] = meters_to_cells(float(mod.get("falloff", 0.0)))
	out["optimal_sig_radius"] = float(mod.get("signatureResolution", 40.0))
	var rof_ms := float(mod.get("rateOfFire", 1000.0))
	out["rate_of_fire_s"] = snappedf(rof_ms / 1000.0, 0.001)
	out["explosion_radius"] = float(mod.get("explosionRadius", 0.0))
	out["explosion_velocity"] = float(mod.get("explosionVelocity", 0.0))
	out["drf"] = float(mod.get("aoeDamageReductionFactor", 0.0))
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
			var half := amount / 2.0
			return {"shield": float(ceili(half)), "armor": float(floor(half)), "structure": 0.0}


static func derive_attack(ship: Dictionary, _star: int = 1) -> Dictionary:
	## Returns attack-side fields for a manned hull. Empty if caller should use stars[].
	## Damage is always ★1 kit baseline; star DPH is ShipUnit.star_dph_mul (SHIP_STATS_V2 §2.5).
	if not should_derive(ship):
		return {}
	var fx := str(ship.get("weapon_fx", ""))
	var slots := attack_slot_count(ship)
	var zero := {
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
	var mute_guns := _guns_muted(ship)
	var mid := resolve_module_id(ship)
	var wpn: Dictionary
	if mute_guns or mid <= 0:
		wpn = {
			"damage": _zero_damage(),
			"tracking": 0.0,
			"optimal": 0.0,
			"falloff": 0.0,
			"optimal_sig_radius": 40.0,
			"rate_of_fire_s": float(ship.get("attack_cycle_s", 1.0)),
			"explosion_radius": 0.0,
			"explosion_velocity": 0.0,
			"drf": 0.0,
		}
	else:
		wpn = _per_slot_weapon(mid)
	var slot_dmg: Dictionary = wpn["damage"]
	var total_1 := {
		"emp": float(slot_dmg.get("emp", 0.0)) * float(slots),
		"thermal": float(slot_dmg.get("thermal", 0.0)) * float(slots),
		"kinetic": float(slot_dmg.get("kinetic", 0.0)) * float(slots),
		"explosive": float(slot_dmg.get("explosive", 0.0)) * float(slots),
	}
	zero["damage"] = _scale_damage(total_1, 1.0)
	zero["tracking"] = float(wpn.get("tracking", 0.0))
	zero["optimal"] = float(wpn.get("optimal", 0.0))
	zero["falloff"] = float(wpn.get("falloff", 0.0))
	zero["optimal_sig_radius"] = float(wpn.get("optimal_sig_radius", 40.0))
	zero["explosion_radius"] = float(wpn.get("explosion_radius", 0.0))
	zero["explosion_velocity"] = float(wpn.get("explosion_velocity", 0.0))
	zero["drf"] = float(wpn.get("drf", 0.0))
	zero["attack_cycle_s"] = float(wpn.get("rate_of_fire_s", -1.0))

	var logistic := bool(ship.get("is_logistic", false)) or fx == "heal"
	if logistic:
		var rid := resolve_repair_module_id(ship)
		var amount := 0.0
		var cycle_s := float(wpn.get("rate_of_fire_s", 0.0))
		var opt := float(wpn.get("optimal", 0.0))
		if rid > 0 and DataStore != null:
			var rmod: Dictionary = DataStore.get_module(rid)
			if not rmod.is_empty():
				amount = float(
					rmod.get("structureDamageAmount",
						rmod.get("armorDamageAmount",
							rmod.get("shieldBonus", 0.0)))
				)
				var dur_ms := float(rmod.get("duration", rmod.get("rateOfFire", 3000.0)))
				cycle_s = snappedf(dur_ms / 1000.0, 0.001)
				opt = meters_to_cells(float(rmod.get("maxRange", 0.0)))
		var hi := int(ship.get("hi_slots", slots))
		var total_rep := amount * float(maxi(hi, 0))
		zero["repair"] = _racial_repair(total_rep, str(ship.get("race", "amarr")).to_lower())
		if opt > 0.0:
			zero["optimal"] = opt
		if cycle_s > 0.0:
			zero["attack_cycle_s"] = cycle_s
	return zero


static func merge_into_star(ship: Dictionary, star_row: Dictionary, star: int) -> Dictionary:
	## Duplicate star row and overlay derived attack when equipment is resolvable.
	var out: Dictionary = star_row.duplicate(true)
	if star_row.is_empty() or not should_derive(ship):
		return out
	var derived := derive_attack(ship, star)
	if derived.is_empty():
		return out
	out["damage"] = derived["damage"]
	out["tracking"] = derived["tracking"]
	out["optimal"] = derived["optimal"]
	out["falloff"] = derived["falloff"]
	out["optimal_sig_radius"] = derived["optimal_sig_radius"]
	out["repair"] = derived["repair"]
	if float(derived.get("explosion_radius", 0.0)) > 0.0 or str(ship.get("weapon_fx", "")) == "missile":
		out["explosion_radius"] = derived["explosion_radius"]
		out["explosion_velocity"] = derived["explosion_velocity"]
		out["drf"] = derived["drf"]
	out["_attack_cycle_s"] = derived["attack_cycle_s"]
	return out
