extends RefCounted
class_name LanJoinDebug
## SEMI_ASYNC §7.5 / DIAGNOSTICS — dedicated LAN join scaffold (match + room-code).
## Tags: net.lan.local | net.lan.room | net.lan.try | net.lan.fail | net.lan.ok | net.lan.summary


static func log_locals(context: String = "") -> void:
	var dump: Dictionary = LanAffinity.dump_locals()
	var detail: String = "ctx=%s plat=%s emu=%s addrs=%s" % [
		context,
		str(dump.get("platform", "")),
		"1" if TypedVariant.as_bool(dump.get("emulator", false), false) else "0",
		JSON.stringify(dump.get("addrs", [])),
	]
	_emit("net.lan.local", detail)


static func log_room(d: Dictionary, index: int = 0) -> void:
	var ip: String = str(d.get("ip", "")).strip_edges()
	var aff: String = LanAffinity.affinity(ip)
	_emit(
		"net.lan.room",
		"i=%d code=%s ip=%s port=%s aff=%s packet=%s payload=%s alts=%s ips=%s rules=%s occ=%s/%s" % [
			index,
			str(d.get("code", 0)),
			ip,
			str(d.get("port", 0)),
			aff,
			str(d.get("packet_ip", "")),
			str(d.get("payload_ip", "")),
			JSON.stringify(d.get("alt_ips", [])),
			JSON.stringify(d.get("ips", [])),
			str(d.get("rules", "")),
			str(d.get("occupied", 0)),
			str(d.get("cap", 0)),
		]
	)


static func log_try(ip: String, port: int, code: int, via: String) -> void:
	var aff: String = LanAffinity.affinity(ip)
	_emit(
		"net.lan.try",
		"code=%04d ep=%s:%d via=%s aff=%s same_lan=%s" % [
			code, ip, port, via, aff, "1" if LanAffinity.is_same_lan(ip) else "0"
		]
	)


static func log_fail(ip: String, port: int, code: int, reason: String, via: String = "") -> void:
	_emit(
		"net.lan.fail",
		"code=%04d ep=%s:%d via=%s aff=%s reason=%s" % [
			code, ip, port, via, LanAffinity.affinity(ip), reason
		]
	)


static func log_ok(ip: String, port: int, code: int, via: String = "") -> void:
	_emit(
		"net.lan.ok",
		"code=%04d ep=%s:%d via=%s aff=%s" % [code, ip, port, via, LanAffinity.affinity(ip)]
	)


static func log_summary(detail: String) -> void:
	_emit("net.lan.summary", detail)


static func fail_status_hint(tried_same_lan: bool, last_err: String, turn_n: int) -> String:
	## Avoid telling users "跨网段" when affinity says same LAN.
	var err: String = last_err if last_err != "" else "超时"
	if tried_same_lan:
		return "同网段信标见但连不上: %s（查防火墙/路由器 AP 隔离/两端内容版）" % err
	if turn_n > 0:
		return "双栈+TURN 试连失败: %s（检查中继可达与房主听口）" % err
	return "加入失败: %s（未与本机同 /24；可再扫匹配，或查 UPnP/turn_urls）" % err


static func _emit(tag: String, detail: String) -> void:
	SessionDiagnostics.log(tag, detail)
	NetSessionDebug.log_event(tag, detail)
