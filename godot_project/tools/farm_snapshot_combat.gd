extends Node
## Headless: load a farm compare snapshot and run CombatResolver.
## Godot --headless --path godot_project res://tools/farm_snapshot_combat.tscn -- --snapshot= --out=


func _ready() -> void:
	print("[farm_snapshot] ready")
	call_deferred("_run")


func _run() -> void:
	var snap_path: String = _arg("snapshot")
	var out_path: String = _arg("out")
	if snap_path.is_empty() or out_path.is_empty():
		var jf: FileAccess = FileAccess.open("res://tools/_farm_snapshot_job.json", FileAccess.READ)
		if jf:
			var jv: Variant = JSON.parse_string(jf.get_as_text())
			if typeof(jv) == TYPE_DICTIONARY:
				var jd: Dictionary = jv
				if snap_path.is_empty():
					snap_path = str(jd.get("snapshot", ""))
				if out_path.is_empty():
					out_path = str(jd.get("out", ""))
	if snap_path.is_empty() or out_path.is_empty():
		push_error("need --snapshot= and --out= (or tools/_farm_snapshot_job.json)")
		get_tree().quit(2)
		return
	var f: FileAccess = FileAccess.open(snap_path, FileAccess.READ)
	if f == null:
		push_error("cannot read snapshot")
		get_tree().quit(3)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		get_tree().quit(4)
		return
	var blob: Dictionary = parsed
	var job: Dictionary = blob.get("job", {})
	await get_tree().process_frame
	var world: Node3D = Node3D.new()
	world.name = "World"
	add_child(world)
	var board: BoardController = BoardController.new()
	board.name = "Board"
	add_child(board)
	board.setup(world)
	board.set_prepare_mode(false)
	var combat: CombatResolver = CombatResolver.new()
	combat.name = "Combat"
	add_child(combat)
	combat.bind(board, null)
	var seed_i: int = int(float(str(job.get("seed", 1))))
	if seed_i == 0:
		seed_i = 1
	var mrng: MatchRng = MatchRng.new()
	mrng.configure(seed_i, "farm_compare")
	mrng.begin_battle(maxi(1, int(float(str(job.get("round_i", 0)))) + 1))
	combat.bind_match_rng(mrng, maxi(1, int(float(str(job.get("round_i", 0)))) + 1))
	var titan_a: String = str(job.get("titan_a", "amarr"))
	var titan_b: String = str(job.get("titan_b", "caldari"))
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, titan_a)
	board.set_titan_fetter_race(ShipUnit.TEAM_AI, titan_b)
	_place_side(board, job.get("pos_a", []), ShipUnit.TEAM_PLAYER)
	_place_side(board, job.get("pos_b", []), ShipUnit.TEAM_AI)
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	board.recalculate_fetters(ShipUnit.TEAM_AI)
	print("[farm_snapshot] placed ships, starting combat")
	combat.start_combat()
	var dt: float = 0.05
	var min_b: float = 1.25
	var max_s: float = 900.0
	if DataStore != null and DataStore.match_flow:
		var mf: Dictionary = DataStore.match_flow
		dt = maxf(0.001, float(str(mf.get("sim_fixed_step_s", 0.05))))
		min_b = float(str(mf.get("min_battle_duration_s", 1.25)))
		max_s = float(str(mf.get("battle_duration_s", 900.0)))
	var t: float = 0.0
	var reason: String = "timeout"
	while t < max_s:
		combat.tick(dt)
		t += dt
		if t >= min_b and board.is_one_side_cleared():
			reason = "wipe"
			break
		if t >= min_b and board.both_sides_no_offense():
			reason = "draw_no_offense"
			break
	combat.stop_combat()
	var live_a: int = board.count_alive_field(ShipUnit.TEAM_PLAYER)
	var live_b: int = board.count_alive_field(ShipUnit.TEAM_AI)
	var winner: String = "draw"
	if live_a > 0 and live_b <= 0:
		winner = "a"
	elif live_b > 0 and live_a <= 0:
		winner = "b"
	var out: Dictionary = {
		"ok": true,
		"winner": winner,
		"reason": reason,
		"sim_s": snappedf(t, 0.01),
		"live_a": live_a,
		"live_b": live_b,
	}
	var wf: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(out))
	print("[farm_snapshot] winner=%s reason=%s t=%.1f a=%d b=%d" % [winner, reason, t, live_a, live_b])
	get_tree().quit(0)


func _place_side(board: BoardController, rows: Variant, team: int) -> void:
	if typeof(rows) != TYPE_ARRAY:
		return
	for rv: Variant in rows:
		if typeof(rv) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = rv
		var sid: int = int(float(str(row.get("ship_id", "0"))))
		if sid <= 0:
			continue
		var star: int = maxi(1, int(float(str(row.get("star", 1)))))
		var x: int = int(float(str(row.get("x", 0))))
		var z: int = int(float(str(row.get("z", 0))))
		var ship: ShipUnit = board.spawn_ship(sid, star, team, "field", x, z)
		if ship == null:
			continue
		var eqs: Array = row.get("equips", [])
		if typeof(eqs) == TYPE_ARRAY and not eqs.is_empty():
			var fit: Array = []
			for e: Variant in eqs:
				fit.append({"id": str(e).split(":")[0]})
			ship.set_function_fit(fit)


func _arg(key: String) -> String:
	var prefix: String = "--%s=" % key
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	for a: String in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""
