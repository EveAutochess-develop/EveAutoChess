extends RefCounted
class_name ShipDeathFx
## All ships: titan-same Echoes explosion+sfx, scaled; no wreck. Titans keep wreck path elsewhere.

const FX_SCRIPT: String = "res://scripts/vfx/echoes_ship_death_fx.gd"
const EXPLODE_DURATION_S: float = 2.4

static func scale_for_ship(ship_id: int) -> float:
	var ship: Dictionary = DataStore.get_ship(ship_id)
	var group: String = str(ship.get("ship_group", "frigate"))
	match group:
		"frigate":
			return 0.12
		"destroyer":
			return 0.18
		"cruiser", "battlecruiser":
			return 0.28
		"battleship":
			return 0.45
		"dreadnought", "carrier", "force_auxiliary", "capital_industrial":
			return 0.7
		"titan":
			return 1.0
		"freighter":
			return 0.85
		_:
			var tags_v: Variant = ship.get("tags", [])
			if tags_v is Array:
				var tags: Array = tags_v
				for t: Variant in tags:
					if str(t) == "sleeper" or str(t) == "pve_creep":
						return 0.25
			return 0.2

static func should_spawn_wreck(ship_id: int) -> bool:
	var ship: Dictionary = DataStore.get_ship(ship_id)
	if str(ship.get("ship_group", "")) == "titan":
		return true
	var tags_v: Variant = ship.get("tags", [])
	if tags_v is Array:
		var tags: Array = tags_v
		for t: Variant in tags:
			if str(t) == "titan":
				return true
	return false

## Spawns one-shot explode (no wreck) at world position. Returns the FX node.
static func spawn_explode(parent: Node, world_pos: Vector3, ship_id: int) -> Node3D:
	if parent == null:
		return null
	var loaded: Variant = load(FX_SCRIPT)
	if not (loaded is Script):
		return null
	var script: Script = loaded
	var fx: Node3D = Node3D.new()
	fx.set_script(script)
	fx.name = "ShipDeathFx_%d" % ship_id
	parent.add_child(fx)
	fx.global_position = world_pos
	var sc: float = scale_for_ship(ship_id)
	fx.scale = Vector3.ONE * sc
	## Drive explode over EXPLODE_DURATION_S then free (no wreck for non-titans).
	var runner: _DeathFxRunner = _DeathFxRunner.new()
	parent.add_child(runner)
	runner.begin(fx, not should_spawn_wreck(ship_id))
	return fx


class _DeathFxRunner extends Node:
	var _fx: Node3D
	var _t: float = 0.0
	var _no_wreck: bool = true

	func begin(fx: Node3D, no_wreck: bool) -> void:
		_fx = fx
		_no_wreck = no_wreck
		_t = 0.0
		set_process(true)

	func _process(delta: float) -> void:
		if _fx == null or not is_instance_valid(_fx):
			queue_free()
			return
		_t += delta
		var amt: float = clampf(_t / EXPLODE_DURATION_S, 0.0, 1.0)
		if _fx.has_method("apply_phase"):
			_fx.call("apply_phase", "explode", amt, true)
		if amt >= 1.0:
			if _no_wreck and is_instance_valid(_fx):
				_fx.queue_free()
			queue_free()
