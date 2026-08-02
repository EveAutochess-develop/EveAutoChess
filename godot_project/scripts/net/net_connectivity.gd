extends RefCounted
class_name NetConnectivity
## SEMI_ASYNC §7 / RELEASE §0.1 — STUN / TURN / signaling from user:// (secrets not in git).

const CFG_PATH := "user://net_connectivity.cfg"
const SECTION := "net"

## Public STUN defaults (D-EAC-42 ON). Overridable via cfg.
const DEFAULT_STUN := [
	"stun:stun.l.google.com:19302",
	"stun:stun1.l.google.com:19302",
]


static func load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	return cfg


static func public_stun_enabled() -> bool:
	var cfg := load_cfg()
	## Default ON when key missing (D-EAC-42 closed).
	if not cfg.has_section_key(SECTION, "public_stun_enabled"):
		return true
	return bool(cfg.get_value(SECTION, "public_stun_enabled", true))


static func stun_urls() -> PackedStringArray:
	var cfg := load_cfg()
	var raw: Variant = cfg.get_value(SECTION, "stun_urls", "")
	var out := PackedStringArray()
	if typeof(raw) == TYPE_STRING and str(raw).strip_edges() != "":
		for part in str(raw).split(",", false):
			var u := part.strip_edges()
			if u != "":
				out.append(u)
	if out.is_empty() and public_stun_enabled():
		for u in DEFAULT_STUN:
			out.append(u)
	return out


static func turn_urls() -> PackedStringArray:
	var cfg := load_cfg()
	var raw := str(cfg.get_value(SECTION, "turn_urls", "")).strip_edges()
	var out := PackedStringArray()
	if raw == "":
		return out
	for part in raw.split(",", false):
		var u := part.strip_edges()
		if u != "":
			out.append(u)
	return out


static func turn_user() -> String:
	return str(load_cfg().get_value(SECTION, "turn_user", ""))


static func turn_pass() -> String:
	return str(load_cfg().get_value(SECTION, "turn_pass", ""))


static func signaling_url() -> String:
	return str(load_cfg().get_value(SECTION, "signaling_url", "")).strip_edges()


static func invite_blob_enabled() -> bool:
	var cfg := load_cfg()
	if not cfg.has_section_key(SECTION, "invite_blob_enabled"):
		return true
	return bool(cfg.get_value(SECTION, "invite_blob_enabled", true))


static func logic_hz() -> int:
	return int(load_cfg().get_value(SECTION, "combat_logic_hz", 30))


static func sync_interval_ticks() -> int:
	return int(load_cfg().get_value(SECTION, "sync_interval_logic_ticks", 15))


static func anticheat_gap_streak() -> int:
	return int(load_cfg().get_value(SECTION, "anticheat_gap_streak_to_investigate", 3))


static func anticheat_gap_hp_rel() -> float:
	return float(load_cfg().get_value(SECTION, "anticheat_gap_hp_rel", 0.05))


static func ice_servers_dict() -> Dictionary:
	## Shape usable by WebRTC / future hole-punch glue.
	return {
		"stun": stun_urls(),
		"turn": turn_urls(),
		"turn_user": turn_user(),
		"turn_pass": turn_pass(),
		"stun_enabled": public_stun_enabled(),
	}
