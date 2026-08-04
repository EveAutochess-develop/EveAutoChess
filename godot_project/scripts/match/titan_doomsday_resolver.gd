extends RefCounted
class_name TitanDoomsdayResolver
## PVP loss → TitanHpPipes damage + doomsday presentation hooks + ore clear + delayed return.

signal doomsday_fired(attacker_seat: int, loser_seat: int, from: Vector3, to: Vector3)
signal return_home_due(seat_id: int)

var pipes_by_seat: Dictionary = {} ## seat -> TitanHpPipes
var pvp_loss_mul: float = 1.0

func ensure_seat(seat_id: int, race: String) -> TitanHpPipes:
	if not pipes_by_seat.has(seat_id):
		var p: TitanHpPipes = TitanHpPipes.new()
		p.setup(race)
		p.pvp_loss_mul = pvp_loss_mul
		pipes_by_seat[seat_id] = p
	else:
		var existing: TitanHpPipes = pipes_by_seat[seat_id]
		existing.pvp_loss_mul = pvp_loss_mul
	return pipes_by_seat[seat_id]

func resolve_loss(winner_seat: int, loser_seat: int, from: Vector3, to: Vector3, belt_root: Node3D) -> Dictionary:
	var loser: TitanHpPipes = pipes_by_seat.get(loser_seat)
	if loser == null:
		return {"applied": 0, "alive": true}
	var applied: int = loser.apply_pvp_loss()
	DoomsdayOreClear.clear_along_segment(belt_root, from, to, 2.5)
	doomsday_fired.emit(winner_seat, loser_seat, from, to)
	return {"applied": applied, "alive": loser.alive(), "pipes": loser.to_dict()}

## Call after VFX length; schedule +5s return.
func schedule_return_home(tree: SceneTree, seat_id: int, vfx_duration_s: float = 3.0) -> void:
	if tree == null:
		return
	var delay: float = vfx_duration_s + 5.0
	## Wall-clock: ignore_time_scale so 倍速 never truncates the off-field return beat.
	tree.create_timer(delay, true, true).timeout.connect(func() -> void: return_home_due.emit(seat_id))
