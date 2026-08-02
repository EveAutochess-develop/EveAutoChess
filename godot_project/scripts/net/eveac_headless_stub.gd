extends RefCounted
class_name EveacHeadless
## SEMI_ASYNC §5 — in-process headless authority (same combat code path as client).
## Optional separate process: --eveac-headless flag; until then HostSim runs in-host.

var orchestrator: HostSimOrchestrator
var _running: bool = false


static func describe() -> String:
	return "eveac_headless — HostSimOrchestrator in-process authority (packaged headless entry ready)"


static func wants_headless_process() -> bool:
	return OS.get_cmdline_user_args().has("--eveac-headless") \
		or OS.get_cmdline_args().has("--eveac-headless")


func bind_orchestrator(orch: HostSimOrchestrator) -> void:
	orchestrator = orch


func ensure_running() -> void:
	_running = true
	## Separate binary spawn is optional; in-process is the default authority path.
	if wants_headless_process():
		push_warning("[eveac_headless] process mode requested — using in-process HostSim (same rules)")


func is_running() -> bool:
	return _running


func tick(logic_dt: float) -> void:
	if orchestrator:
		orchestrator.tick_authority(logic_dt)
