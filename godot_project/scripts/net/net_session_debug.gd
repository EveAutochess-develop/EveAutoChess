extends RefCounted
class_name NetSessionDebug
## SEMI_ASYNC §8.5a / DIAGNOSTICS §2.1 — net debug + packet summaries; ≤50MB; ships hash only.

const LOG_PATH: String = "user://logs/net_session.log"
const MAX_TOTAL_BYTES: int = 50 * 1024 * 1024
const FLUSH_EVERY: int = 8

static var _buf: PackedStringArray = PackedStringArray()
static var _bytes_approx: int = -1


static func log_event(tag: String, detail: String = "") -> void:
	var line: String = "%s\t%s\t%s" % [
		Time.get_datetime_string_from_system(true, true),
		tag,
		detail.replace("\n", " ").substr(0, 2000),
	]
	_buf.append(line)
	SessionDiagnostics.log(tag, detail)
	if _buf.size() >= FLUSH_EVERY:
		flush()


static func log_pack(kind: String, meta: Dictionary) -> void:
	## Never include full ships table — hashes only.
	var safe: Dictionary = {}
	for k_v: Variant in meta.keys():
		var k: String = str(k_v)
		if k.contains("ships_table") or k.contains("ships_json") or k == "table" or k == "ships":
			continue
		var v: Variant = meta[k_v]
		if typeof(v) == TYPE_DICTIONARY and str(k).begins_with("ships"):
			continue
		safe[k] = v
	if meta.has("ships_hash"):
		safe["ships_hash"] = str(meta.get("ships_hash", ""))
	if meta.has("pack_hash"):
		safe["pack_hash"] = str(meta.get("pack_hash", ""))
	if meta.has("rules_hash"):
		safe["rules_hash"] = str(meta.get("rules_hash", ""))
	if meta.has("bytes"):
		safe["bytes"] = TypedVariant.as_int(meta.get("bytes", 0), 0)
	log_event("net.pack." + kind, JSON.stringify(safe))


static func flush() -> void:
	if _buf.is_empty():
		return
	var chunk: String = "\n".join(_buf) + "\n"
	_buf.clear()
	_ensure_dir()
	_rotate_if_needed(chunk.length())
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string(chunk)
	## No sync flush — drop on failure.
	if _bytes_approx >= 0:
		_bytes_approx += chunk.length()


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")


static func _rotate_if_needed(incoming: int) -> void:
	if _bytes_approx < 0:
		if FileAccess.file_exists(LOG_PATH):
			var existing: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
			_bytes_approx = existing.get_length() if existing else 0
		else:
			_bytes_approx = 0
	if _bytes_approx + incoming <= MAX_TOTAL_BYTES:
		return
	## Truncate to keep last ~half of cap.
	if not FileAccess.file_exists(LOG_PATH):
		_bytes_approx = 0
		return
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		return
	var all: String = f.get_as_text()
	f = null
	var keep: int = int(MAX_TOTAL_BYTES * 0.5)
	if all.length() > keep:
		all = all.substr(all.length() - keep)
	var w: FileAccess = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if w:
		w.store_string(all)
		_bytes_approx = all.length()
