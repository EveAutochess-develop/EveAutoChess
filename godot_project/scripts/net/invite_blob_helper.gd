extends RefCounted
class_name InviteBlobHelper
## SEMI_ASYNC §7.2 — invite string encode/decode stub (辅助异地).

static func encode(host_ip: String, port: int, room_hint: String, rules_hash: String) -> String:
	var payload := {
		"v": 1,
		"ip": host_ip,
		"port": port,
		"room": room_hint,
		"rules": rules_hash,
	}
	return Marshalls.utf8_to_base64(JSON.stringify(payload))

static func decode(blob: String) -> Dictionary:
	var json_txt := Marshalls.base64_to_utf8(blob.strip_edges())
	var parsed: Variant = JSON.parse_string(json_txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
