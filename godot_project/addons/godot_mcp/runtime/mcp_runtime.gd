extends Node
## MCPRuntime — autoload that lives inside the user's running game and exposes
## a small set of "runtime" tools to the MCP server (take_screenshot,
## send_input, query_runtime_node, get_runtime_log, list_signal_connections).
##
## Connects to the same MCP WebSocket server as the editor plugin, but
## identifies itself with role="runtime" in its hello message so the server
## can route runtime tool calls to it.
##
## Auto-registered as an autoload by the godot_mcp editor plugin on
## _enable_plugin(); removed on _disable_plugin().

const SERVER_URL: String = "ws://127.0.0.1:6505"
const CACHE_SCREENSHOT_DIR: String = "res://addons/godot_mcp/cache/screenshots/"
const LOG_RING_CAPACITY: int = 500

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected: bool = false
var _reconnect_at_msec: int = 0
var _project_path: String = ""
var _ai_mcp_runtime: AiMcpRuntime = null

# Circular buffer of recent runtime log lines. We grow it via push_runtime_log()
# (called by user scripts that opt in) and via captured push_error/push_warning
# through Engine.print_error_messages — but most prints come from the engine
# via the editor's debugger, so get_runtime_log mirrors what the editor
# already sees with a runtime-focused timestamp.
var _log_ring: Array = []
var _started_at_msec: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_project_path = ProjectSettings.globalize_path("res://")
	_started_at_msec = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ai_mcp_runtime = AiMcpRuntime.new()
	push_runtime_log("info", "MCPRuntime starting (project=%s)" % _project_path)
	print("[MCPRuntime] starting project=%s url=%s" % [_project_path, SERVER_URL])
	_attempt_connect()


func _exit_tree() -> void:
	# Drop the runtime WebSocket so the MCP server can bind the next Play instance.
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	_connected = false


func _process(_delta: float) -> void:
	_socket.poll()
	var st: WebSocketPeer.State = _socket.get_ready_state()

	if st == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			_send({
				"type": "godot_ready",
				"role": "runtime",
				"project_path": _project_path,
				"started_at": _started_at_msec,
			})
			push_runtime_log("info", "MCPRuntime connected to MCP server.")
			print("[MCPRuntime] connected to MCP server")

		while _socket.get_available_packet_count() > 0:
			var raw: String = _socket.get_packet().get_string_from_utf8()
			_handle_message(raw)

	elif st == WebSocketPeer.STATE_CONNECTING:
		# Don't hang forever if handshake never completes.
		if Time.get_ticks_msec() >= _reconnect_at_msec:
			push_runtime_log("warn", "MCPRuntime CONNECTING timeout; closing and retry")
			print("[MCPRuntime] CONNECTING timeout; retry")
			_socket.close()
			_connected = false
			_attempt_connect()

	elif st == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			push_runtime_log("warn", "MCPRuntime disconnected; will retry.")
			print("[MCPRuntime] disconnected; will retry")
		var now_ms: int = Time.get_ticks_msec()
		if now_ms >= _reconnect_at_msec:
			_attempt_connect()


func _attempt_connect() -> void:
	_socket = WebSocketPeer.new()
	_socket.outbound_buffer_size = 8 * 1024 * 1024  # screenshots can be big
	_socket.inbound_buffer_size = 256 * 1024
	var err: Error = _socket.connect_to_url(SERVER_URL)
	_reconnect_at_msec = Time.get_ticks_msec() + 2000
	if err != OK:
		push_runtime_log("warn", "MCPRuntime connect_to_url failed: %d (%s)" % [err, error_string(err)])
		print("[MCPRuntime] connect_to_url failed: %d (%s)" % [err, error_string(err)])
	else:
		print("[MCPRuntime] connect_to_url OK → %s" % SERVER_URL)


func _handle_message(json_string: String) -> void:
	var parsed: Variant = JSON.parse_string(json_string)
	if parsed == null or not (parsed is Dictionary):
		return
	var msg: Dictionary = parsed
	var msg_type: String = str(msg.get("type", ""))
	match msg_type:
		"ping":
			_send({"type": "pong"})
		"tool_invoke":
			var rid: String = str(msg.get("id", ""))
			var tool_name: String = str(msg.get("tool", ""))
			var args_v: Variant = msg.get("args", {})
			var args: Dictionary = args_v if args_v is Dictionary else {}
			var result: Dictionary = _dispatch(tool_name, args)
			var success: bool = TypedVariant.as_bool(result.get("ok", false), false)
			result.erase("ok")
			var payload: Variant = null
			if success:
				payload = result
			var err_text: String = ""
			if not success:
				err_text = str(result.get("error", ""))
			_send({
				"type": "tool_result",
				"id": rid,
				"success": success,
				"result": payload,
				"error": err_text,
			})
		_:
			pass


func _dispatch(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"take_screenshot":
			return _take_screenshot(args)
		"send_input":
			return _send_input(args)
		"query_runtime_node":
			return _query_runtime_node(args)
		"get_runtime_log":
			return _get_runtime_log(args)
		"list_signal_connections":
			return _list_signal_connections(args)
		"list_seats", "attach_seat", "detach_seat", "get_seat_state", "list_legal_actions", "submit_action", "load_model_bundle", "validate_model_bundle":
			if _ai_mcp_runtime == null:
				return {"ok": false, "error": "ai mcp not ready"}
			match tool_name:
				"list_seats":
					return _ai_mcp_runtime.list_seats()
				"attach_seat":
					return _ai_mcp_runtime.attach_seat(TypedVariant.as_int(args.get("seat_id", -1), -1))
				"detach_seat":
					return _ai_mcp_runtime.detach_seat(TypedVariant.as_int(args.get("seat_id", -1), -1))
				"get_seat_state":
					return _ai_mcp_runtime.get_seat_state(TypedVariant.as_int(args.get("seat_id", -1), -1))
				"list_legal_actions":
					return _ai_mcp_runtime.list_legal_actions(
						TypedVariant.as_int(args.get("seat_id", -1), -1),
						str(args.get("phase", ""))
					)
				"submit_action":
					var action_v: Variant = args.get("action", {})
					var action: Dictionary = action_v if action_v is Dictionary else {}
					return _ai_mcp_runtime.submit_action(TypedVariant.as_int(args.get("seat_id", -1), -1), action)
				"load_model_bundle":
					var bundle_v: Variant = args.get("bundle", {})
					var bundle: Dictionary = bundle_v if bundle_v is Dictionary else {}
					return _ai_mcp_runtime.load_model_bundle(bundle)
				"validate_model_bundle":
					var bundle2_v: Variant = args.get("bundle", {})
					var bundle2: Dictionary = bundle2_v if bundle2_v is Dictionary else {}
					return _ai_mcp_runtime.validate_model_bundle(bundle2)
				_:
					return {"ok": false, "error": "Unknown runtime tool: %s" % tool_name}
		_:
			return {"ok": false, "error": "Unknown runtime tool: %s" % tool_name}


# =============================================================================
# take_screenshot
# =============================================================================
func _take_screenshot(args: Dictionary) -> Dictionary:
	var save_to: String = str(args.get("save_to", "")).strip_edges()
	var return_base64: bool = TypedVariant.as_bool(args.get("return_base64", false), false)

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return {"ok": false, "error": "No viewport available"}
	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "Viewport returned no image"}

	var resource_path: String = ""
	if save_to.is_empty():
		_ensure_cache_dir()
		resource_path = "%sscreenshot_%d.png" % [CACHE_SCREENSHOT_DIR, Time.get_ticks_msec()]
	else:
		if not save_to.begins_with("res://") and not save_to.begins_with("user://"):
			save_to = "res://" + save_to
		resource_path = save_to

	var abs_path: String = ProjectSettings.globalize_path(resource_path)
	var dir: String = abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err: Error = img.save_png(abs_path)
	if err != OK:
		return {"ok": false, "error": "save_png failed: %d (%s) at %s" % [err, error_string(err), abs_path]}

	var out: Dictionary = {
		"ok": true,
		"resource_path": resource_path,
		"absolute_path": abs_path,
		"width": img.get_width(),
		"height": img.get_height(),
	}
	if return_base64:
		out["base64_png"] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(abs_path))
	return out


# =============================================================================
# send_input
# =============================================================================
func _send_input(args: Dictionary) -> Dictionary:
	var event_desc: Dictionary = TypedVariant.as_dict(args.get("event", {}))
	if event_desc.is_empty():
		return {"ok": false, "error": "Missing 'event' dictionary"}
	var event: InputEvent = _build_input_event(event_desc)
	if event == null:
		return {"ok": false, "error": "Could not construct InputEvent from: %s" % str(event_desc)}
	Input.parse_input_event(event)
	return {
		"ok": true,
		"dispatched": event.get_class(),
		"event": event_desc,
	}


func _build_input_event(desc: Dictionary) -> InputEvent:
	var t: String = str(desc.get("type", ""))
	match t:
		"key":
			var k: InputEventKey = InputEventKey.new()
			k.pressed = TypedVariant.as_bool(desc.get("pressed", true), true)
			if desc.has("keycode"):
				k.keycode = TypedVariant.as_int(desc["keycode"], 0) as Key
			if desc.has("physical_keycode"):
				k.physical_keycode = TypedVariant.as_int(desc["physical_keycode"], 0) as Key
			if desc.has("key"):
				var keystr: String = str(desc["key"]).to_upper()
				k.physical_keycode = OS.find_keycode_from_string(keystr)
			if desc.has("shift"):
				k.shift_pressed = TypedVariant.as_bool(desc["shift"], false)
			if desc.has("ctrl"):
				k.ctrl_pressed = TypedVariant.as_bool(desc["ctrl"], false)
			if desc.has("alt"):
				k.alt_pressed = TypedVariant.as_bool(desc["alt"], false)
			if desc.has("meta"):
				k.meta_pressed = TypedVariant.as_bool(desc["meta"], false)
			return k
		"mouse_button":
			var mb: InputEventMouseButton = InputEventMouseButton.new()
			mb.pressed = TypedVariant.as_bool(desc.get("pressed", true), true)
			mb.button_index = TypedVariant.as_int(desc.get("button_index", MOUSE_BUTTON_LEFT), MOUSE_BUTTON_LEFT) as MouseButton
			if desc.has("position"):
				mb.position = _to_vec2(desc["position"])
				mb.global_position = mb.position
			if desc.has("double_click"):
				mb.double_click = TypedVariant.as_bool(desc["double_click"], false)
			return mb
		"mouse_motion":
			var mm: InputEventMouseMotion = InputEventMouseMotion.new()
			if desc.has("position"):
				mm.position = _to_vec2(desc["position"])
				mm.global_position = mm.position
			if desc.has("relative"):
				mm.relative = _to_vec2(desc["relative"])
			return mm
		"action":
			var act: InputEventAction = InputEventAction.new()
			act.action = str(desc.get("action", ""))
			act.pressed = TypedVariant.as_bool(desc.get("pressed", true), true)
			var strength_default: float = 1.0 if act.pressed else 0.0
			act.strength = TypedVariant.as_float(desc.get("strength", strength_default), strength_default)
			return act
		_:
			return null


func _to_vec2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Dictionary:
		var d: Dictionary = v
		return Vector2(TypedVariant.as_float(d.get("x", 0), 0.0), TypedVariant.as_float(d.get("y", 0), 0.0))
	if v is Array:
		var arr: Array = v
		if arr.size() >= 2:
			return Vector2(TypedVariant.as_float(arr[0], 0.0), TypedVariant.as_float(arr[1], 0.0))
	return Vector2.ZERO


# =============================================================================
# query_runtime_node — inspect a live node in the running scene tree
# =============================================================================
func _query_runtime_node(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return {"ok": false, "error": "Missing 'node_path' (e.g. /root/Main/Player or relative path from current_scene)"}
	var properties: Array = TypedVariant.as_array(args.get("properties", []))
	var include_children: bool = TypedVariant.as_bool(args.get("include_children", false), false)
	var include_groups: bool = TypedVariant.as_bool(args.get("include_groups", true), true)

	var tree: SceneTree = get_tree()
	if tree == null:
		return {"ok": false, "error": "SceneTree unavailable"}

	var node: Node = null
	if node_path.begins_with("/"):
		node = tree.root.get_node_or_null(NodePath(node_path))
	else:
		var current: Node = tree.current_scene
		if current != null:
			node = current.get_node_or_null(NodePath(node_path))
		if node == null:
			node = tree.root.get_node_or_null(NodePath(node_path))

	if node == null:
		return {"ok": false, "error": "Node not found: %s" % node_path}

	var info: Dictionary = {
		"ok": true,
		"name": str(node.name),
		"class": node.get_class(),
		"path": str(node.get_path()),
		"valid": true,
	}
	if include_groups:
		info["groups"] = node.get_groups()

	if properties.is_empty():
		# Default subset that's almost always interesting
		properties = ["position", "global_position", "rotation", "scale", "visible", "modulate"]
	var prop_values: Dictionary = {}
	for pname_v: Variant in properties:
		var pname: String = str(pname_v)
		var v: Variant = node.get(pname)
		if v != null:
			prop_values[pname] = _serialize(v)
	info["properties"] = prop_values

	if include_children:
		var kids: Array = []
		for c: Node in node.get_children():
			kids.append({"name": str(c.name), "class": c.get_class()})
		info["children"] = kids

	return info


func _serialize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return {"type": "Vector2", "x": v2.x, "y": v2.y}
		TYPE_VECTOR3:
			var v3: Vector3 = v
			return {"type": "Vector3", "x": v3.x, "y": v3.y, "z": v3.z}
		TYPE_COLOR:
			var col: Color = v
			return {"type": "Color", "r": col.r, "g": col.g, "b": col.b, "a": col.a}
		TYPE_OBJECT:
			if v == null:
				return null
			var obj: Object = v
			if obj.has_method("get_class"):
				return "<%s>" % obj.get_class()
			return "<Object>"
		_:
			return v


# =============================================================================
# get_runtime_log — recent runtime log lines pushed via push_runtime_log()
# =============================================================================
func _get_runtime_log(args: Dictionary) -> Dictionary:
	var limit: int = clampi(TypedVariant.as_int(args.get("limit", 200), 200), 1, LOG_RING_CAPACITY)
	var since_ms: int = TypedVariant.as_int(args.get("since_ms", 0), 0)
	var filtered: Array = []
	for entry_v: Variant in _log_ring:
		var entry: Dictionary = TypedVariant.as_dict(entry_v)
		if TypedVariant.as_int(entry.get("ts_ms", 0), 0) >= since_ms:
			filtered.append(entry)
	if filtered.size() > limit:
		filtered = filtered.slice(filtered.size() - limit, filtered.size())
	return {
		"ok": true,
		"entries": filtered,
		"count": filtered.size(),
		"started_at_ms": _started_at_msec,
		"now_ms": Time.get_ticks_msec(),
		"hint": "For full engine output (prints from your scripts) the editor's get_console_log already includes the running game's stdout.",
	}


# Public: user scripts can call MCPRuntime.push_runtime_log("info", "msg") to
# surface custom diagnostics in the agent's get_runtime_log results.
func push_runtime_log(level: String, text: String) -> void:
	if _log_ring.size() >= LOG_RING_CAPACITY:
		_log_ring.pop_front()
	_log_ring.append({
		"ts_ms": Time.get_ticks_msec(),
		"level": level,
		"text": text,
	})


# =============================================================================
# list_signal_connections — runtime-side
# =============================================================================
func _list_signal_connections(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return {"ok": false, "error": "Missing 'node_path'"}

	var tree: SceneTree = get_tree()
	if tree == null:
		return {"ok": false, "error": "SceneTree unavailable"}

	var node: Node = null
	if node_path.begins_with("/"):
		node = tree.root.get_node_or_null(NodePath(node_path))
	else:
		var current: Node = tree.current_scene
		if current != null:
			node = current.get_node_or_null(NodePath(node_path))

	if node == null:
		return {"ok": false, "error": "Node not found: %s" % node_path}

	var outgoing: Array = []
	for sig_v: Dictionary in node.get_signal_list():
		var sig_name: String = str(sig_v["name"])
		for conn_v: Dictionary in node.get_signal_connection_list(sig_name):
			var callable: Callable = conn_v["callable"]
			var dst: Object = callable.get_object()
			var to_object: String = "<%s>" % "null"
			if dst != null:
				if dst is Node:
					var dst_node: Node = dst
					to_object = str(dst_node.get_path())
				else:
					to_object = "<%s>" % dst.get_class()
			outgoing.append({
				"signal": sig_name,
				"to_object": to_object,
				"method": callable.get_method(),
				"flags": TypedVariant.as_int(conn_v.get("flags", 0), 0),
			})

	return {
		"ok": true,
		"source": "runtime",
		"node_path": node_path,
		"outgoing": outgoing,
		"outgoing_count": outgoing.size(),
	}


# =============================================================================
func _ensure_cache_dir() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(CACHE_SCREENSHOT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


func _send(msg: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))
