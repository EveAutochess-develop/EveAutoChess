extends RefCounted
class_name AiMcpRuntime
## In-game MCP tools for LLM seats. Attach then submit legal actions only.

var _attached_seats: Dictionary = {}
var _loaded_model_bundle_hash: String = ""
var _loaded_model_bundle_ok: bool = false


func _get_tree() -> SceneTree:
	var ml: MainLoop = Engine.get_main_loop()
	if not (ml is SceneTree):
		return null
	@warning_ignore("unsafe_cast")
	return ml as SceneTree


func _match_root() -> Node:
	var tree: SceneTree = _get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("match_root")


func _get_seats() -> Array:
	if GameSession == null:
		return []
	var pn: Dictionary = GameSession.pending_nullsec
	var seats_v: Variant = pn.get("seats", [])
	return TypedVariant.as_array(seats_v)


func _seat_controller(s: Dictionary) -> String:
	var c: String = str(s.get("controller", ""))
	if c != "":
		return c
	if TypedVariant.as_bool(s.get("is_ai", false), false):
		return "legacy_ai"
	return "human"


func list_seats() -> Dictionary:
	var out: Array = []
	for s_v: Variant in _get_seats():
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		var seat_id: int = TypedVariant.as_int(s.get("seat_id", -1), -1)
		if seat_id < 0:
			continue
		out.append({
			"seat_id": seat_id,
			"nick": str(s.get("nick", "")),
			"occupied": TypedVariant.as_bool(s.get("occupied", false), false),
			"is_ai": TypedVariant.as_bool(s.get("is_ai", false), false),
			"controller": _seat_controller(s),
			"owner_nick": str(s.get("owner_nick", "")),
		})
	return {"ok": true, "seats": out}


func attach_seat(seat_id: int) -> Dictionary:
	if seat_id < 0:
		return {"ok": false, "accepted": false, "reason_key": "invalid_seat_id"}
	var st: Dictionary = get_seat_state(seat_id)
	if not TypedVariant.as_bool(st.get("ok", false), false):
		return {"ok": false, "accepted": false, "reason_key": "seat_not_found"}
	if not TypedVariant.as_bool(st.get("occupied", false), false):
		return {"ok": false, "accepted": false, "reason_key": "seat_not_occupied"}
	if _seat_controller(st) != "llm":
		return {"ok": false, "accepted": false, "reason_key": "not_llm_slot"}
	_attached_seats[seat_id] = true
	return {"ok": true, "accepted": true}


func detach_seat(seat_id: int) -> Dictionary:
	_attached_seats.erase(seat_id)
	return {"ok": true, "accepted": true}


func get_seat_state(seat_id: int) -> Dictionary:
	for s_v: Variant in _get_seats():
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) != seat_id:
			continue
		var out: Dictionary = s.duplicate(true)
		out["ok"] = true
		out["controller"] = _seat_controller(s)
		return out
	return {"ok": false, "error": "seat_not_found"}


func list_legal_actions(seat_id: int, phase: String) -> Dictionary:
	var seat_state: Dictionary = get_seat_state(seat_id)
	if not TypedVariant.as_bool(seat_state.get("ok", false), false):
		return {"ok": false, "accepted": false, "reason_key": "seat_not_found"}
	var las: Array = LegalActions.list_legal_actions(phase, seat_state)
	return {"ok": true, "accepted": true, "legal_actions": las}


func submit_action(seat_id: int, action: Dictionary) -> Dictionary:
	if not _attached_seats.has(seat_id):
		return {"ok": false, "accepted": false, "reason_key": "seat_not_attached"}
	if _seat_controller(get_seat_state(seat_id)) != "llm":
		return {"ok": false, "accepted": false, "reason_key": "not_llm_slot"}
	var phase: String = str(action.get("phase", "prepare"))
	var legal: Dictionary = list_legal_actions(seat_id, phase)
	var las: Array = TypedVariant.as_array(legal.get("legal_actions", []))
	var chk: Dictionary = LegalActions.validate_action_against_list(action, las)
	if not TypedVariant.as_bool(chk.get("accepted", false), false):
		chk["ok"] = false
		return chk
	var root: Node = _match_root()
	var ctx: Dictionary = {"seat": seat_id}
	if root != null:
		ctx["match_ctrl"] = root.get("match_ctrl")
		ctx["board"] = root.get("board")
		ctx["shop"] = root.get("shop")
		ctx["ai"] = root.get("ai")
	var disp: AiCommandDispatcher = AiCommandDispatcher.new()
	var res: Dictionary = disp.dispatch(action, ctx)
	res["ok"] = TypedVariant.as_bool(res.get("accepted", false), false)
	return res


func load_model_bundle(bundle: Dictionary) -> Dictionary:
	_loaded_model_bundle_hash = ""
	_loaded_model_bundle_ok = false
	var manifest_json: String = str(bundle.get("manifest_json", ""))
	if manifest_json.is_empty():
		return {"ok": true, "accepted": true, "model_bundle_hash": "", "bundle_ok": false}
	var parsed: Variant = JSON.parse_string(manifest_json)
	if parsed is Dictionary:
		var d: Dictionary = TypedVariant.as_dict(parsed)
		_loaded_model_bundle_hash = str(d.get("model_bundle_hash", ""))
		_loaded_model_bundle_ok = not _loaded_model_bundle_hash.is_empty()
	return {
		"ok": true,
		"accepted": true,
		"model_bundle_hash": _loaded_model_bundle_hash,
		"bundle_ok": _loaded_model_bundle_ok,
	}


func validate_model_bundle(bundle: Dictionary) -> Dictionary:
	var manifest_json: String = str(bundle.get("manifest_json", ""))
	if manifest_json.is_empty():
		return {"ok": true, "accepted": true}
	var parsed: Variant = JSON.parse_string(manifest_json)
	if parsed is Dictionary:
		var d: Dictionary = TypedVariant.as_dict(parsed)
		var schema_ver: String = str(d.get("schema_ver", ""))
		if schema_ver.is_empty():
			return {"ok": false, "accepted": false, "reason_key": "manifest_schema_missing"}
		var hash_v: String = str(d.get("model_bundle_hash", ""))
		if hash_v.is_empty():
			return {"ok": false, "accepted": false, "reason_key": "manifest_hash_missing"}
		return {"ok": true, "accepted": true, "model_bundle_hash": hash_v, "bundle_ok": true}
	return {"ok": false, "accepted": false, "reason_key": "manifest_invalid"}
