extends AcceptDialog
class_name NullsecLobbyPopup
## Deprecated chrome — static helpers for PublicRoomEnumerator.
@warning_ignore_start("untyped_declaration", "inferred_declaration", "unsafe_method_access", "unsafe_call_argument", "inference_on_variant", "unsafe_cast")

const _LobbyPanel: Script = preload("res://scripts/ui/nullsec_lobby_panel.gd")

static func load_enum_cursor() -> Dictionary:
	return _LobbyPanel.call("load_enum_cursor")

static func save_enum_cursor(cursor: int, dir: int) -> void:
	_LobbyPanel.call("save_enum_cursor", cursor, dir)

static func make_default_clone_nick() -> String:
	return str(_LobbyPanel.call("make_default_clone_nick"))
