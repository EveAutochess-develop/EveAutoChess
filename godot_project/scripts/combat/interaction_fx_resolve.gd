extends RefCounted
class_name InteractionFxResolve
## Pick merged interaction FX defs for combat triggers (COMBAT §8.4).

static func from_unit_data(unit: Dictionary) -> Dictionary:
	return _from_unit_dict(unit)


static func resolve_for_weapon_hit(firer: ShipUnit, target: ShipUnit) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {}
	## Priority: target ship → firer main module → firer ship.
	var tgt_def: Dictionary = _from_unit_dict(DataStore.get_ship(target.ship_id))
	if not tgt_def.is_empty():
		return tgt_def
	var main_def: Dictionary = _from_main_module(firer)
	if not main_def.is_empty():
		return main_def
	if firer != null and is_instance_valid(firer):
		return _from_unit_dict(DataStore.get_ship(firer.ship_id))
	return {}


static func resolve_for_module(firer: ShipUnit, module_def: Dictionary) -> Dictionary:
	var from_mod: Dictionary = _from_unit_dict(module_def)
	if not from_mod.is_empty():
		return from_mod
	if firer != null and is_instance_valid(firer):
		return _from_unit_dict(DataStore.get_ship(firer.ship_id))
	return {}


static func resolve_for_superweapon(firer: ShipUnit, module_def: Dictionary) -> Dictionary:
	return resolve_for_module(firer, module_def)


static func _from_main_module(ship: ShipUnit) -> Dictionary:
	if ship == null or not is_instance_valid(ship):
		return {}
	var mod_id: int = TypedVariant.as_int(DataStore.get_ship(ship.ship_id).get("source_module_type_id", 0), 0)
	if mod_id <= 0:
		return {}
	var mod_def: Dictionary = DataStore.get_module(mod_id)
	return _from_unit_dict(mod_def)


static func _from_unit_dict(unit: Dictionary) -> Dictionary:
	if unit.is_empty():
		return {}
	var kinds: Dictionary = TypedVariant.as_dict(DataStore.interaction_fx.get("kinds", {}))
	var ov: Dictionary = TypedVariant.as_dict(unit.get("interaction_fx_override", {}))
	if not ov.is_empty():
		var merged: Dictionary = ModInteractionFxResolve.merge_override(ov, kinds)
		if not merged.is_empty():
			return merged
	var kind: String = str(unit.get("interaction_fx", "")).strip_edges()
	if kind == "":
		return {}
	if kinds.has(kind):
		return TypedVariant.as_dict(kinds[kind]).duplicate(true)
	return {}
