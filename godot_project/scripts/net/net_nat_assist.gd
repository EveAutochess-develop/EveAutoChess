extends RefCounted
class_name NetNatAssist
## SEMI_ASYNC §7.2 — UPnP/NAT-PMP port map for host listen_port.

static func try_upnp_map(listen_port: int, timeout_msec: int = 2000) -> Dictionary:
	## {} or { "ip": String, "port": int, "via": "upnp" }
	if listen_port <= 0:
		return {}
	var upnp: UPNP = UPNP.new()
	var disc: int = upnp.discover(maxi(200, timeout_msec), 2, "InternetGatewayDevice")
	if disc != UPNP.UPNP_RESULT_SUCCESS:
		disc = upnp.discover(maxi(200, timeout_msec), 2)
	if disc != UPNP.UPNP_RESULT_SUCCESS:
		return {}
	if upnp.get_gateway() == null:
		return {}
	var ext: String = str(upnp.query_external_address()).strip_edges()
	if ext == "" or ext.begins_with("0."):
		return {}
	var map_err: int = upnp.add_port_mapping(
		listen_port, listen_port, "EveAutochess", "UDP", 0
	)
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		## Some gateways already have the mapping — still publish external IP + listen port.
		pass
	return {"ip": ext, "port": listen_port, "via": "upnp"}


static func remove_upnp_map(listen_port: int) -> void:
	if listen_port <= 0:
		return
	var upnp: UPNP = UPNP.new()
	if upnp.discover(800, 2) != UPNP.UPNP_RESULT_SUCCESS:
		return
	if upnp.get_gateway() == null:
		return
	upnp.delete_port_mapping(listen_port, "UDP")
