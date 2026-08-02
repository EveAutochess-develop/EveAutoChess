extends RefCounted
class_name NullsecRejoinTicket
## MATCH_FLOW §5.0b / SEMI_ASYNC §5.3a — local rejoin ticket (not a combat save).

const PATH := "user://save/nullsec_rejoin.json"
const VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


static func load_dict() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func save_dict(d: Dictionary) -> bool:
	if d.is_empty():
		clear()
		return false
	DirAccess.make_dir_recursive_absolute("user://save")
	var out: Dictionary = d.duplicate(true)
	out["version"] = VERSION
	out["written_unix"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(out))
	return true


static func from_session(net: Node) -> Dictionary:
	## Accept NullsecNetSession without a typed dep (avoids class_name cycle).
	if net == null or not bool(net.get("match_started")) or int(net.get("local_seat")) < 0:
		return {}
	var host_ip := str(net.get("last_known_host_ip"))
	var host_port := int(net.call("listen_port")) if net.has_method("listen_port") else 0
	if host_ip == "" or host_ip == "0.0.0.0":
		host_ip = "127.0.0.1"
	var is_priv := bool(net.get("is_private"))
	var room_hint := str(net.get("private_code")) if is_priv else "%04d" % int(net.get("room_code"))
	var blob := ""
	if net.has_method("make_invite_blob"):
		blob = str(net.call("make_invite_blob"))
	var payload: Dictionary = net.get("last_match_payload") as Dictionary if typeof(net.get("last_match_payload")) == TYPE_DICTIONARY else {}
	return {
		"match_id": str(net.get("match_id")),
		"session_secret": str(net.get("session_secret")),
		"seat_id": int(net.get("local_seat")),
		"nick": str(net.get("local_nick")),
		"rules_hash": str(net.get("rules_hash")),
		"security_mode": str(net.get("security_mode")),
		"room_code": int(net.get("room_code")),
		"is_private": is_priv,
		"private_code": str(net.get("private_code")),
		"room_hint": room_hint,
		"room_blob": blob,
		"opening_host_platform": str(net.get("opening_host_platform")),
		"opening_host_ships_hash": str(net.get("opening_host_ships_hash")),
		"host_ip": host_ip,
		"host_port": host_port,
		"host_migrate_generation": int(net.get("host_migrate_generation")),
		"match_seed": int(payload.get("match_seed", 0)),
	}


static func write_from_session(net: Node) -> bool:
	var d := from_session(net)
	if d.is_empty():
		return false
	return save_dict(d)
