extends RefCounted
class_name ShortcodeSignaling
## SEMI_ASYNC §7.5 — public 4-digit / private 6×0-9a-v claim via optional signaling URL.
## Without signaling_url: falls back to LAN claim (PublicRoomEnumerator + local bind).

signal claim_result(ok: bool, detail: Dictionary)

const PRIVATE_ALPHABET := "0123456789abcdefghijklmnopqrstuv"
const CLAIM_TIMEOUT_MS := 4000


static func is_valid_private(code: String) -> bool:
	var c := code.strip_edges().to_lower()
	if c.length() != 6:
		return false
	for i in range(c.length()):
		if PRIVATE_ALPHABET.find(c.substr(i, 1)) < 0:
			return false
	return true


static func random_private() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in range(6):
		out += PRIVATE_ALPHABET[rng.randi_range(0, PRIVATE_ALPHABET.length() - 1)]
	return out


## Atomic claim: HTTP POST {action:claim, kind, code, rules_hash, host_hint}.
## Returns {ok, code, reason, endpoints?} — never silently defers.
static func claim_public_sync(preferred: int, rules_hash: String, host_hint: Dictionary = {}) -> Dictionary:
	var base := NetConnectivity.signaling_url()
	if base == "":
		return {"ok": true, "code": preferred, "via": "lan_local", "reason": ""}
	return _http_claim(base, {
		"action": "claim",
		"kind": "public",
		"code": preferred,
		"rules_hash": rules_hash,
		"host": host_hint,
	})


static func claim_private_sync(code: String, rules_hash: String, host_hint: Dictionary = {}) -> Dictionary:
	var c := code.strip_edges().to_lower()
	if not is_valid_private(c):
		return {"ok": false, "code": c, "via": "validate", "reason": "invalid_private_format"}
	var base := NetConnectivity.signaling_url()
	if base == "":
		return {"ok": true, "code": c, "via": "lan_local", "reason": ""}
	return _http_claim(base, {
		"action": "claim",
		"kind": "private",
		"code": c,
		"rules_hash": rules_hash,
		"host": host_hint,
	})


static func resolve_join_sync(kind: String, code: String, rules_hash: String) -> Dictionary:
	var base := NetConnectivity.signaling_url()
	if base == "":
		return {"ok": false, "reason": "no_signaling", "via": "none"}
	return _http_claim(base, {
		"action": "resolve",
		"kind": kind,
		"code": code,
		"rules_hash": rules_hash,
	})


static func _http_claim(base: String, body: Dictionary) -> Dictionary:
	var http := HTTPClient.new()
	var url := base
	var tls := url.begins_with("https://")
	var host := url
	var path := "/"
	if url.find("://") >= 0:
		host = url.get_slice("://", 1)
	var slash := host.find("/")
	if slash >= 0:
		path = host.substr(slash)
		host = host.substr(0, slash)
	var port := 443 if tls else 80
	if host.find(":") >= 0:
		var parts := host.split(":")
		host = parts[0]
		port = int(parts[1])
	var tls_opts: TLSOptions = TLSOptions.client() if tls else null
	var err := http.connect_to_host(host, port, tls_opts)
	if err != OK:
		return {"ok": false, "reason": "connect_fail:%s" % error_string(err), "via": "signaling"}
	var deadline := Time.get_ticks_msec() + CLAIM_TIMEOUT_MS
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "reason": "connect_timeout", "via": "signaling"}
		OS.delay_msec(10)
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "reason": "not_connected", "via": "signaling"}
	var payload := JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json"])
	err = http.request(HTTPClient.METHOD_POST, path if path != "" else "/", headers, payload)
	if err != OK:
		return {"ok": false, "reason": "request_fail", "via": "signaling"}
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "reason": "request_timeout", "via": "signaling"}
		OS.delay_msec(10)
	if http.get_status() != HTTPClient.STATUS_BODY and http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "reason": "bad_status", "via": "signaling"}
	var rb := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			rb.append_array(chunk)
		else:
			OS.delay_msec(5)
		if Time.get_ticks_msec() > deadline:
			break
	var txt := rb.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		## Full pool / reject without JSON body.
		var code_i := http.get_response_code()
		if code_i == 409 or code_i == 503:
			return {"ok": false, "reason": "pool_full_or_taken", "via": "signaling", "http": code_i}
		return {"ok": false, "reason": "bad_json", "via": "signaling", "http": code_i}
	var d: Dictionary = parsed
	d["via"] = "signaling"
	if not d.has("ok"):
		d["ok"] = bool(d.get("claimed", false)) or str(d.get("status", "")) == "ok"
	return d
