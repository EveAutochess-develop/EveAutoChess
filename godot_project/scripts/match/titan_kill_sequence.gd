extends RefCounted
class_name TitanKillSequence
## MULTIPLAYER_PVP §2.6: explode → wreck 5s (wall clock) → then allow next step.

const _ShipDeathFx := preload("res://scripts/visual/ship_death_fx.gd")
const EXPLODE_S := 2.4
const WRECK_HOLD_S := 5.0
const WRECK_KEY := {
	"amarr": "tq_titan_wreck_a",
	"caldari": "tq_titan_wreck_c",
	"gallente": "tq_titan_wreck_g",
	"minmatar": "tq_titan_wreck_m",
}
const WRECK_SHIP_ID := {
	"amarr": 921,
	"caldari": 922,
	"gallente": 923,
	"minmatar": 924,
}


static func ensure_wreck_ship_defs() -> void:
	if DataStore == null:
		return
	for race in WRECK_KEY.keys():
		var wid: int = int(WRECK_SHIP_ID[race])
		if DataStore.ships.has(wid):
			continue
		DataStore.ships[wid] = {
			"id": wid,
			"name": "泰坦残骸",
			"name_en": "TitanWreck",
				"race": race,
				"ship_group": "titan",
				"model_auto_orient": true,
				"model_key": WRECK_KEY[race],
			"shop_eligible": false,
			"tags": ["titan", "wreck", "shop_ineligible"],
			"model_long_axis": 2200.0,
		}


## Runs explode + wreck hold on berth; calls on_done when §2.6 finishes.
static func play(berth: TitanBerth, parent: Node, on_done: Callable = Callable()) -> void:
	if berth == null or not is_instance_valid(berth) or parent == null:
		if on_done.is_valid():
			on_done.call()
		return
	ensure_wreck_ship_defs()
	var runner := _Runner.new()
	parent.add_child(runner)
	runner.begin(berth, on_done)


class _Runner extends Node:
	var _berth: TitanBerth
	var _on_done: Callable
	var _phase := 0
	var _start_ms: int = 0
	var _wreck: ShipUnit = null

	func begin(berth: TitanBerth, on_done: Callable) -> void:
		_berth = berth
		_on_done = on_done
		_phase = 0
		_start_ms = Time.get_ticks_msec()
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(true)
		var pos := berth.fire_point()
		_ShipDeathFx.spawn_explode(get_parent(), pos, berth.ship_id)
		berth.set_engine_trail_emitting(false)
		if berth.unit and is_instance_valid(berth.unit):
			berth.unit.visible = false

	func _process(_delta: float) -> void:
		var elapsed := float(Time.get_ticks_msec() - _start_ms) * 0.001
		if _phase == 0:
			if elapsed >= EXPLODE_S:
				_show_wreck()
				_phase = 1
				_start_ms = Time.get_ticks_msec()
		elif _phase == 1:
			if elapsed >= WRECK_HOLD_S:
				_finish()

	func _show_wreck() -> void:
		if _berth == null or not is_instance_valid(_berth):
			return
		var race := _berth.race
		var wid := int(WRECK_SHIP_ID.get(race, 921))
		_wreck = ShipUnit.new()
		_wreck.name = "TitanWreck"
		_berth.add_child(_wreck)
		_wreck.setup(wid, 1, ShipUnit.TEAM_PLAYER if _berth.home_side else ShipUnit.TEAM_AI)
		_wreck.clear_health_bar()
		_wreck.slot_type = ""
		_wreck.face_dir_xz(Vector3(0, 0, -1.0 if _berth.home_side else 1.0))
		if _berth.unit and is_instance_valid(_berth.unit):
			## Wreck meshes share the intact hull's authored axis — copy the solved yaw
			## instead of re-deriving it, or the debris parks reversed / sideways.
			_wreck.rotation.y = _berth.unit.rotation.y
			_wreck.scale = _berth.unit.scale
			_wreck.position = _berth.unit.position

	func _finish() -> void:
		set_process(false)
		if _on_done.is_valid():
			_on_done.call()
		queue_free()
