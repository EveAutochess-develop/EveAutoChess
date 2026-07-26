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
	var path := "res://data/admin/policies.json"
	if not FileAccess.file_exists(path):
		return
	var raw := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return
	admin_enabled = bool(data.get("admin_enabled", true))
	var arr = data.get("policies", [])
	if typeof(arr) == TYPE_ARRAY:
		_policies = arr

func register_handler(channel: StringName, handler: Callable) -> void:
	_handlers[channel] = handler

func request(channel: StringName, payload: Dictionary) -> Dictionary:
	var p := payload.duplicate(true)
	p["channel"] = String(channel)
	if admin_enabled:
		p = _apply_before(channel, p)
		if p.get("_drop", false):
			return {"accepted": false, "reason_key": "admin_drop", "mutated": true}
	var handler: Callable = _handlers.get(channel, Callable())
	var result: Dictionary
	if handler.is_valid():
		result = handler.call(p)
		if typeof(result) != TYPE_DICTIONARY:
			result = {"accepted": true}
	else:
		result = {"accepted": true}
	result["channel"] = String(channel)
	result["payload"] = p
	if not result.has("mutated"):
		result["mutated"] = bool(p.get("mutated", false))
	after_handoff.emit(channel, p, result)
	return result

func _apply_before(channel: StringName, payload: Dictionary) -> Dictionary:
	var ch := String(channel)
	for pol in _policies:
		if typeof(pol) != TYPE_DICTIONARY:
			continue
		if not bool(pol.get("enabled", false)):
			continue
		if str(pol.get("channel", "")) != ch:
			continue
		var actions = pol.get("actions", [])
		if typeof(actions) != TYPE_ARRAY:
			continue
		for act in actions:
			if typeof(act) != TYPE_DICTIONARY:
				continue
			payload = _apply_action(payload, act)
			payload["mutated"] = true
	return payload

func _apply_action(payload: Dictionary, act: Dictionary) -> Dictionary:
	var op := str(act.get("op", ""))
	match op:
		"drop":
			payload["_drop"] = true
		"set_field":
			payload[str(act.get("field", ""))] = act.get("value")
		"mul_field":
			var f := str(act.get("field", ""))
			if payload.has(f) and typeof(payload[f]) in [TYPE_INT, TYPE_FLOAT]:
				payload[f] = float(payload[f]) * float(act.get("factor", 1.0))
		"add_field":
			var f2 := str(act.get("field", ""))
			if payload.has(f2) and typeof(payload[f2]) in [TYPE_INT, TYPE_FLOAT]:
				payload[f2] = float(payload[f2]) + float(act.get("amount", 0.0))
		_:
			pass
	return payload
