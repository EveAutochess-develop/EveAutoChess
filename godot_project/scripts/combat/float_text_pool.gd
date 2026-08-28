extends Node
class_name FloatTextPool
## Pooled Label3D popups. Damage / heal / cap each accumulate per target (COMBAT.md).

const CHANNEL_DAMAGE: String = "damage"
const CHANNEL_HEAL: String = "heal"
const CHANNEL_CAP: String = "cap"

const COLOR_DAMAGE: Color = Color(1.0, 0.45, 0.35)
const COLOR_HEAL: Color = Color(0.35, 0.95, 0.55)
const COLOR_CAP: Color = Color(0.4, 0.7, 1.0)

const GAP_RESET_S: float = 1.0
const BASE_FONT: int = 48
const BASE_PIXEL: float = 0.012
const DIGIT_SCALE: float = 1.1
const TTL_S: float = 0.95

var _pool: Array[Label3D] = []
var _active: Array = [] ## {label, age, ttl, start_y, track_key, channel}
## track_key -> {sum, last_s, label}
var _tracks: Dictionary = {}


func spawn(world_pos: Vector3, text: String, color: Color) -> void:
	## Untacked one-shot (legacy / misc). Prefer add_* for combat.
	_spawn_raw(world_pos, text, color, 1.0, "", "", 1.2)


func add_damage(world_pos: Vector3, amount: float, track_id: int) -> void:
	_add_tracked(world_pos, absf(amount), track_id, CHANNEL_DAMAGE)


func add_heal(world_pos: Vector3, amount: float, track_id: int) -> void:
	_add_tracked(world_pos, absf(amount), track_id, CHANNEL_HEAL)


## Signed capacitor delta: +gain / −drain. Blue channel, own track per ship.
func add_cap(world_pos: Vector3, signed_delta: float, track_id: int) -> void:
	_add_tracked(world_pos, signed_delta, track_id, CHANNEL_CAP)


func _add_tracked(world_pos: Vector3, amount: float, track_id: int, channel: String) -> void:
	if track_id == 0:
		return
	## Damage allows exact 0 (turret miss → float "0"). Heal/cap still ignore near-zero.
	if channel == CHANNEL_DAMAGE:
		if amount < 0.0:
			return
	elif channel == CHANNEL_CAP:
		if absf(amount) < 0.5:
			return
	elif amount < 0.5:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var key: String = "%d:%s" % [track_id, channel]
	var track: Dictionary = TypedVariant.as_dict(_tracks.get(key, {}))
	var last_s: float = TypedVariant.as_float(track.get("last_s", -9999.0), -9999.0)
	var sum: float = TypedVariant.as_float(track.get("sum", 0.0), 0.0)
	if now - last_s > GAP_RESET_S:
		sum = amount
		track["label"] = null
	else:
		sum += amount
	track["sum"] = sum
	track["last_s"] = now
	var shown: int = roundi(absf(sum))
	## Miss-only or sub-1 heal/cap noise: damage may show literal 0.
	if channel != CHANNEL_DAMAGE and shown < 1:
		_tracks[key] = track
		return
	var text: String = _format_text(channel, sum)
	var color: Color = _channel_color(channel)
	var scale_mul: float = _digit_scale(maxi(1, shown))
	var y_off: float = _channel_y(channel)
	var lab_v: Variant = track.get("label", null)
	if lab_v is Label3D and is_instance_valid(lab_v):
		@warning_ignore("unsafe_cast")
		var lab: Label3D = lab_v as Label3D
		if _entry_for_label(lab) >= 0:
			lab.text = text
			lab.modulate = color
			lab.modulate.a = 1.0
			_apply_scale(lab, scale_mul)
			lab.global_position = world_pos + Vector3(0.0, y_off, 0.0)
			_refresh_entry(lab)
			_tracks[key] = track
			return
	var lab2: Label3D = _spawn_raw(world_pos, text, color, scale_mul, key, channel, y_off)
	track["label"] = lab2
	_tracks[key] = track


func _format_text(channel: String, sum: float) -> String:
	var n: int = roundi(absf(sum))
	match channel:
		CHANNEL_HEAL:
			return "+%d" % n
		CHANNEL_DAMAGE:
			## Turret miss: show "0" not "-0".
			if n <= 0:
				return "0"
			return "-%d" % n
		CHANNEL_CAP:
			return ("+%d" if sum >= 0.0 else "-%d") % n
		_:
			return "%d" % n


func _channel_color(channel: String) -> Color:
	match channel:
		CHANNEL_HEAL:
			return COLOR_HEAL
		CHANNEL_CAP:
			return COLOR_CAP
		_:
			return COLOR_DAMAGE


func _channel_y(channel: String) -> float:
	match channel:
		CHANNEL_HEAL:
			return 1.65
		CHANNEL_CAP:
			return 2.1
		_:
			return 1.2


func _digit_scale(n: int) -> float:
	var digits: int = str(maxi(1, n)).length()
	return pow(DIGIT_SCALE, float(digits - 1))


func _apply_scale(lab: Label3D, scale_mul: float) -> void:
	var fs: float = float(BASE_FONT) * scale_mul
	lab.font_size = maxi(12, roundi(fs))
	lab.pixel_size = BASE_PIXEL * scale_mul


func _spawn_raw(
	world_pos: Vector3,
	text: String,
	color: Color,
	scale_mul: float,
	track_key: String,
	channel: String,
	y_off: float
) -> Label3D:
	var lab: Label3D = _acquire()
	lab.text = text
	lab.modulate = color
	_apply_scale(lab, scale_mul)
	lab.global_position = world_pos + Vector3(0.0, y_off, 0.0)
	lab.visible = true
	_active.append({
		"label": lab,
		"age": 0.0,
		"ttl": TTL_S,
		"start_y": lab.global_position.y,
		"track_key": track_key,
		"channel": channel,
	})
	return lab


func _refresh_entry(lab: Label3D) -> void:
	var idx: int = _entry_for_label(lab)
	if idx < 0:
		return
	var entry: Dictionary = TypedVariant.as_dict(_active[idx])
	entry["age"] = 0.0
	entry["ttl"] = TTL_S
	entry["start_y"] = lab.global_position.y
	_active[idx] = entry


func _entry_for_label(lab: Label3D) -> int:
	for i: int in range(_active.size()):
		var entry: Dictionary = TypedVariant.as_dict(_active[i])
		if entry.get("label") == lab:
			return i
	return -1


func _acquire() -> Label3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var lab: Label3D = Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font_size = BASE_FONT
	lab.outline_size = 8
	lab.outline_modulate = Color(0, 0, 0, 0.8)
	lab.no_depth_test = true
	lab.pixel_size = BASE_PIXEL
	add_child(lab)
	return lab


func _process(delta: float) -> void:
	var i: int = 0
	while i < _active.size():
		var entry: Dictionary = TypedVariant.as_dict(_active[i])
		entry["age"] = TypedVariant.as_float(entry.get("age", 0.0)) + delta
		var lab_v: Variant = entry.get("label")
		if not (lab_v is Label3D):
			_clear_track_label(str(entry.get("track_key", "")))
			_active.remove_at(i)
			continue
		@warning_ignore("unsafe_cast")
		var lab: Label3D = lab_v as Label3D
		var ttl: float = maxf(TypedVariant.as_float(entry.get("ttl", TTL_S), TTL_S), 0.0001)
		var t: float = TypedVariant.as_float(entry.get("age", 0.0)) / ttl
		lab.global_position.y = TypedVariant.as_float(entry.get("start_y", lab.global_position.y)) + t * 1.2
		lab.modulate.a = 1.0 - t
		_active[i] = entry
		if TypedVariant.as_float(entry.get("age", 0.0)) >= ttl:
			_clear_track_label(str(entry.get("track_key", "")))
			lab.visible = false
			_apply_scale(lab, 1.0)
			_pool.append(lab)
			_active.remove_at(i)
		else:
			i += 1


func _clear_track_label(track_key: String) -> void:
	if track_key == "" or not _tracks.has(track_key):
		return
	var track: Dictionary = TypedVariant.as_dict(_tracks[track_key])
	track["label"] = null
	_tracks[track_key] = track
