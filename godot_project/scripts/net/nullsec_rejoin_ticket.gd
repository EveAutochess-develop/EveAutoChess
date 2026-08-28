extends RefCounted
class_name NullsecRejoinTicket
## MATCH_FLOW §5.0b / SEMI_ASYNC §5.3a — local rejoin ticket (not a combat save).

const PATH: String = "user://save/nullsec_rejoin.json"
const VERSION: int = 1


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


static func load_dict() -> Dictionary:
	if not exists():
		return {}
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


static func save_dict(d: Dictionary) -> bool:
	if d.is_empty():
		clear()
		return false
	DirAccess.make_dir_recursive_absolute("user://save")
	var out: Dictionary = d.duplicate(true)
	out["version"] = VERSION
	out["written_unix"] = int(Time.get_unix_time_from_system())
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(out))
	return true


static func from_session(net: Node) -> Dictionary:
	## Accept NullsecNetSession without a typed dep (avoids class_name cycle).
	if net == null or not TypedVariant.as_bool(net.get("match_started"), false) or TypedVariant.as_int(net.get("local_seat"), -1) < 0:
		return {}
	var host_ip: String = str(net.get("last_known_host_ip"))
	var host_port: int = TypedVariant.as_int(net.call("listen_port"), 0) if net.has_method("listen_port") else 0
	if host_ip == "" or host_ip == "0.0.0.0":
		host_ip = "127.0.0.1"
	var room_pw: String = str(net.get("room_password"))
	var room_hint: String = "%04d" % TypedVariant.as_int(net.get("room_code"), 0)
	var blob: String = ""
	if net.has_method("make_invite_blob"):
		blob = str(net.call("make_invite_blob"))
	var payload: Dictionary = {}
	var payload_v: Variant = net.get("last_match_payload")
	if typeof(payload_v) == TYPE_DICTIONARY:
		payload = payload_v
	return {
		"match_id": str(net.get("match_id")),
		"session_secret": str(net.get("session_secret")),
		"seat_id": TypedVariant.as_int(net.get("local_seat"), -1),
		"nick": str(net.get("local_nick")),
		"rules_hash": str(net.get("rules_hash")),
		"security_mode": str(net.get("security_mode")),
		"room_code": TypedVariant.as_int(net.get("room_code"), 0),
		"room_password": room_pw,
		"room_hint": room_hint,
		"room_blob": blob,
		"opening_host_platform": str(net.get("opening_host_platform")),
		"opening_host_ships_hash": str(net.get("opening_host_ships_hash")),
		"host_ip": host_ip,
		"host_port": host_port,
		"host_migrate_generation": TypedVariant.as_int(net.get("host_migrate_generation"), 0),
		"match_seed": TypedVariant.as_int(payload.get("match_seed", 0), 0),
		"enabled_mods_ordered": (
			(ModManager.get_or_null().enabled_mods_ordered() if ModManager.get_or_null() != null else [])
		),
	}


static func write_from_session(net: Node) -> bool:
	var d: Dictionary = from_session(net)
	if d.is_empty():
		return false
	return save_dict(d)
