extends RefCounted
class_name NickCodec
## MULTIPLAYER_MATCH_FLOW §2.1 — nick charset / encode / display truncate.

const MAX_LEN: int = 50
const DISPLAY_LEN: int = 10


static func sanitize(raw: String) -> String:
	## Allow CJK, letters, digits, common symbols; strip controls; cap length.
	var s: String = raw.strip_edges()
	var out: String = ""
	for i: int in range(s.length()):
		var ch: String = s.substr(i, 1)
		var code: int = ch.unicode_at(0)
		if code < 32 or code == 127:
			continue
		## Reject path separators and NUL.
		if ch == "/" or ch == "\\" or code == 0:
			continue
		out += ch
		if out.length() >= MAX_LEN:
			break
	return out


static func is_valid(raw: String) -> bool:
	var n: String = sanitize(raw)
	return n != "" and n.length() <= MAX_LEN


static func encode_for_wire(nick: String) -> String:
	## Percent-encode UTF-8 so wire cannot smuggle raw control / path bytes.
	var clean: String = sanitize(nick)
	return clean.uri_encode()


static func decode_from_wire(encoded: String) -> String:
	var decoded: String = str(encoded).uri_decode()
	return sanitize(decoded)


static func display_short(nick: String) -> String:
	var n: String = sanitize(nick)
	if n.length() <= DISPLAY_LEN:
		return n
	return n.substr(0, DISPLAY_LEN) + "…"


static func tooltip_full(nick: String) -> String:
	return sanitize(nick)
