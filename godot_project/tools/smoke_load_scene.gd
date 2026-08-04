extends SceneTree
## Headless smoke: load one scene resource. Path from EVEAC_SMOKE_SCENE or default main_menu.
## Prints [eveac_smoke] OK / FAIL with the path so CLI blocks stay attributable.


func _init() -> void:
	var path: String = OS.get_environment("EVEAC_SMOKE_SCENE").strip_edges()
	if path.is_empty():
		path = "res://scenes/main_menu.tscn"
	print("[eveac_smoke] loading %s" % path)
	if not ResourceLoader.exists(path):
		push_error("[eveac_smoke] FAIL missing %s" % path)
		quit(1)
		return
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		push_error("[eveac_smoke] FAIL load returned null %s" % path)
		quit(1)
		return
	print("[eveac_smoke] OK %s type=%s" % [path, res.get_class()])
	quit(0)
