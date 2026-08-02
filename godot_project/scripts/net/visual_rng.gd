extends RefCounted
class_name VisualRng
## SEMI_ASYNC_NETPLAY §2.2 — local presentation RNG; never feeds state_hash / win-loss.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_v: int = 0) -> void:
	if seed_v != 0:
		_rng.seed = seed_v
	else:
		_rng.randomize()


func reseed(seed_v: int = 0) -> void:
	if seed_v != 0:
		_rng.seed = seed_v
	else:
		_rng.randomize()


func randf() -> float:
	return _rng.randf()


func randf_range(from_v: float, to_v: float) -> float:
	return _rng.randf_range(from_v, to_v)


func randi() -> int:
	return int(_rng.randi())


func randi_range(from_v: int, to_v: int) -> int:
	return _rng.randi_range(from_v, to_v)
