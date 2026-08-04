extends Node
## Cross-brick AdminBus — bricks must hand off side effects via request().
## Policies from data/admin/policies.json; default pass-through.

signal after_handoff(channel: StringName, payload: Dictionary, result: Dictionary)

var admin_enabled: bool = true
var _policies: Array = []
var _handlers: Dictionary = {}  # channel -> Callable

func _ready() -> void:
	reload_policies()

func reload_policies() -> void:
	_policies.clear()
	var path: String = "res://data/admin/policies.json"
	if not FileAccess.file_exists(path):
		return
	var raw: String = FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		return
	var data_dict: Dictionary = data
	admin_enabled = _variant_to_bool(data_dict.get("admin_enabled", true), true)
	var arr: Variant = data_dict.get("policies", [])
	if arr is Array:
		_policies = arr

func register_handler(channel: StringName, handler: Callable) -> void:
	_handlers[channel] = handler

func request(channel: StringName, payload: Dictionary) -> Dictionary:
	var p: Dictionary = payload.duplicate(true)
	p["channel"] = String(channel)
	if admin_enabled:
		p = _apply_before(channel, p)
		if _variant_to_bool(p.get("_drop", false), false):
			return {"accepted": false, "reason_key": "admin_drop", "mutated": true}
	var handler: Callable = _handlers.get(channel, Callable())
	var result: Dictionary
	if handler.is_valid():
		var call_ret: Variant = handler.call(p)
		if call_ret is Dictionary:
			result = call_ret
		else:
			result = {"accepted": true}
	else:
		result = {"accepted": true}
	result["channel"] = String(channel)
	result["payload"] = p
	if not result.has("mutated"):
		result["mutated"] = _variant_to_bool(p.get("mutated", false), false)
	after_handoff.emit(channel, p, result)
	return result

func _apply_before(channel: StringName, payload: Dictionary) -> Dictionary:
	var ch: String = String(channel)
	for pol: Variant in _policies:
		if not (pol is Dictionary):
			continue
		var pol_dict: Dictionary = pol
		if not _variant_to_bool(pol_dict.get("enabled", false), false):
			continue
		if str(pol_dict.get("channel", "")) != ch:
			continue
		var actions: Variant = pol_dict.get("actions", [])
		if not (actions is Array):
			continue
		for act: Variant in actions:
			if not (act is Dictionary):
				continue
			var act_dict: Dictionary = act
			payload = _apply_action(payload, act_dict)
			payload["mutated"] = true
	return payload

func _apply_action(payload: Dictionary, act: Dictionary) -> Dictionary:
	var op: String = str(act.get("op", ""))
	match op:
		"drop":
			payload["_drop"] = true
		"set_field":
			payload[str(act.get("field", ""))] = act.get("value")
		"mul_field":
			var f: String = str(act.get("field", ""))
			if payload.has(f) and typeof(payload[f]) in [TYPE_INT, TYPE_FLOAT]:
				payload[f] = _variant_to_float(payload[f], 0.0) * _variant_to_float(act.get("factor", 1.0), 1.0)
		"add_field":
			var f2: String = str(act.get("field", ""))
			if payload.has(f2) and typeof(payload[f2]) in [TYPE_INT, TYPE_FLOAT]:
				payload[f2] = _variant_to_float(payload[f2], 0.0) + _variant_to_float(act.get("amount", 0.0), 0.0)
		_:
			pass
	return payload

## JSON / policy Variant boundary — narrow after typeof without changing semantics.
func _variant_to_bool(v: Variant, default_val: bool) -> bool:
	match typeof(v):
		TYPE_BOOL:
			@warning_ignore("unsafe_cast")
			return v as bool
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return (v as int) != 0
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return (v as float) != 0.0
		TYPE_STRING:
			var s: String = str(v)
			return s == "true" or s == "1"
		_:
			return default_val

func _variant_to_float(v: Variant, default_val: float) -> float:
	match typeof(v):
		TYPE_FLOAT:
			@warning_ignore("unsafe_cast")
			return v as float
		TYPE_INT:
			@warning_ignore("unsafe_cast")
			return float(v as int)
		TYPE_BOOL:
			@warning_ignore("unsafe_cast")
			return 1.0 if (v as bool) else 0.0
		TYPE_STRING:
			return str(v).to_float()
		_:
			return default_val
