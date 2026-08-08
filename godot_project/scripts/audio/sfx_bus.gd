extends RefCounted
class_name SfxBus
## All one-shot / combat SFX route here. Concurrent voices share loudness budget
## (no additive peak stack). BGM stays on its own bus.

const BUS_NAME: StringName = &"SFX"
const _COMP_THRESHOLD_DB: float = -18.0
const _COMP_RATIO: float = 12.0
const _COMP_ATTACK_US: float = 50.0
const _COMP_RELEASE_MS: float = 80.0
const _LIMIT_CEILING_DB: float = -1.5
const _LIMIT_THRESHOLD_DB: float = -6.0

## instance_id -> base_volume_db for currently playing routed players
static var _active: Dictionary = {}


static func ensure() -> void:
	var idx: int = AudioServer.get_bus_index(String(BUS_NAME))
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, String(BUS_NAME))
		AudioServer.set_bus_send(idx, "Master")
	_ensure_compressor(idx)
	_ensure_limiter(idx)


static func _ensure_compressor(bus_idx: int) -> void:
	var fx: AudioEffect = _effect_at(bus_idx, 0, "AudioEffectCompressor")
	if fx is AudioEffectCompressor:
		var c: AudioEffectCompressor = fx
		c.threshold = _COMP_THRESHOLD_DB
		c.ratio = _COMP_RATIO
		c.attack_us = _COMP_ATTACK_US
		c.release_ms = _COMP_RELEASE_MS
		c.gain = 0.0
		c.mix = 1.0


static func _ensure_limiter(bus_idx: int) -> void:
	var fx: AudioEffect = _effect_at(bus_idx, 1, "AudioEffectLimiter")
	if fx is AudioEffectLimiter:
		var lim: AudioEffectLimiter = fx
		lim.ceiling_db = _LIMIT_CEILING_DB
		lim.threshold_db = _LIMIT_THRESHOLD_DB
		lim.soft_clip_db = 2.0
		lim.soft_clip_ratio = 10.0


static func _instantiate_effect(class_nm: String) -> AudioEffect:
	var created_v: Variant = ClassDB.instantiate(class_nm)
	if created_v is AudioEffect:
		return created_v
	return null


static func _effect_at(bus_idx: int, slot: int, class_nm: String) -> AudioEffect:
	while AudioServer.get_bus_effect_count(bus_idx) <= slot:
		var created: AudioEffect = _instantiate_effect(class_nm)
		if created == null:
			return null
		AudioServer.add_bus_effect(bus_idx, created)
	var fx_v: Variant = AudioServer.get_bus_effect(bus_idx, slot)
	var fx: AudioEffect = null
	if fx_v is AudioEffect:
		fx = fx_v
	if fx == null or fx.get_class() != class_nm:
		if fx != null:
			AudioServer.remove_bus_effect(bus_idx, slot)
		var created2: AudioEffect = _instantiate_effect(class_nm)
		if created2 == null:
			return null
		AudioServer.add_bus_effect(bus_idx, created2, slot)
		return created2
	return fx


static func route(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	ensure()
	player.bus = String(BUS_NAME)


## Call immediately before `player.play()`. Tracks concurrent voices and applies
## equal-power gain so N overlapping SFX stay near one-voice loudness.
static func begin_play(player: AudioStreamPlayer, base_volume_db: float = 0.0) -> void:
	if player == null or not is_instance_valid(player):
		return
	route(player)
	var id: int = player.get_instance_id()
	## Re-entry (stolen voice): drop old slot first.
	if _active.has(id):
		_active.erase(id)
	_active[id] = base_volume_db
	player.set_meta("_sfx_bus_active", true)
	_ensure_finished_hook(player)
	_rebalance()


static func end_play(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	if is_instance_valid(player):
		player.set_meta("_sfx_bus_active", false)
	var id: int = player.get_instance_id()
	if _active.has(id):
		_active.erase(id)
		_rebalance()


static func _ensure_finished_hook(player: AudioStreamPlayer) -> void:
	if TypedVariant.as_bool(player.get_meta("_sfx_bus_fin_hook", false), false):
		return
	player.set_meta("_sfx_bus_fin_hook", true)
	player.finished.connect(Callable(SfxBus, "_on_player_finished_node").bind(player))


static func _on_player_finished_node(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not TypedVariant.as_bool(player.get_meta("_sfx_bus_active", false), false):
		return
	end_play(player)


static func _rebalance() -> void:
	## Only drop freed players. Do NOT prune `not playing` here: callers
	## register via begin_play() then call play(), so the voice is briefly idle.
	var dead: Array[int] = []
	for id_v: Variant in _active.keys():
		var id: int = TypedVariant.as_int(id_v, 0)
		var n: Object = instance_from_id(id)
		if n == null or not is_instance_valid(n) or not (n is AudioStreamPlayer):
			dead.append(id)
	for d: int in dead:
		_active.erase(d)
	var n_voices: int = _active.size()
	if n_voices <= 0:
		return
	## Equal-power: N incoherent sources ≈ +10·log10(N) → compensate per voice.
	var share_db: float = -10.0 * log(float(n_voices)) / log(10.0)
	for id_v2: Variant in _active.keys():
		var id2: int = TypedVariant.as_int(id_v2, 0)
		var obj: Object = instance_from_id(id2)
		if obj == null or not (obj is AudioStreamPlayer):
			continue
		var pl: AudioStreamPlayer = obj
		var base_db: float = TypedVariant.as_float(_active[id2], 0.0)
		pl.volume_db = base_db + share_db
