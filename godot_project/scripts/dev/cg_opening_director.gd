extends Node3D
## Opening CG draft — aligns to cg-director-studio/projects/eveautochess-opening/OPENING_CG_DIRECTOR.md
## Timeline ~72s · slides → race flypast (orbit cam + aligned bows + trails) → cross standoff.
## Hotkeys: Space / 暂停按钮 play/pause · R restart · [ ] scrub ±1s · 1–9 jump beat · Alt+WASD QE RF TG free cam · F5 capture

## Titan ids are the content defs (201–204): they carry `model_auto_orient`, which the
## TQ length-on-X hulls need. Injecting private ids would drop that flag → titan flies sideways.
## 大航 = 超级航母（supercarrier），不是执政官级那种航母（carrier）。
## 俗称：万古=永恒/Aeon · 飞龙=Wyvern · 夜神=尼克斯/Nyx · 冥府=地狱/Hel。
const RACES: Array[Dictionary] = [
	{"id": 201, "race": "A", "race_id": "amarr", "model_key": "tq_titan_a", "sc_key": "tq_supercarrier_a", "sc_id": 971, "sc_name": "永恒级", "sc_alias": "万古", "sc_name_en": "Aeon", "name": "圣像级", "name_en": "Avatar", "color": Color(1.0, 0.82, 0.28), "sky_jpeg": "res://assets/skyboxes/races/ah1.jpg"},
	{"id": 202, "race": "C", "race_id": "caldari", "model_key": "tq_titan_c", "sc_key": "tq_supercarrier_c", "sc_id": 972, "sc_name": "飞龙级", "sc_alias": "飞龙", "sc_name_en": "Wyvern", "name": "利维坦级", "name_en": "Leviathan", "color": Color(0.35, 0.72, 1.0), "sky_jpeg": "res://assets/skyboxes/races/ch1.jpg"},
	{"id": 203, "race": "G", "race_id": "gallente", "model_key": "tq_titan_g", "sc_key": "tq_supercarrier_g", "sc_id": 973, "sc_name": "尼克斯级", "sc_alias": "夜神", "sc_name_en": "Nyx", "name": "厄勒布洛斯级", "name_en": "Erebus", "color": Color(0.35, 1.0, 0.55), "sky_jpeg": "res://assets/skyboxes/races/gh1.jpg"},
	{"id": 204, "race": "M", "race_id": "minmatar", "model_key": "tq_titan_m", "sc_key": "tq_supercarrier_m", "sc_id": 974, "sc_name": "地狱级", "sc_alias": "冥府", "sc_name_en": "Hel", "name": "诸神黄昏级", "name_en": "Ragnarok", "color": Color(1.0, 0.42, 0.12), "sky_jpeg": "res://assets/skyboxes/races/mh1.jpg"},
]

## Beat grid measured from the mix, 86.54 bpm · first beat 0.680s · period 0.6933s.
## Source of truth: cg-director-studio/projects/eveautochess-opening/_review/opening_audio/beat_grid.json
## (regenerate with tools/analyze_beats.py). Every cut below is a grid index — never a hand-picked second.
const BEAT_T0: float = 0.680
const BEAT_PERIOD: float = 0.6933

## Cut points, all on-grid (comment = beat index).
const T_SLIDE0_END: float = 2.07 ## 2
const T_SLIDE1_END: float = 4.84 ## 6
const T_SLIDE2_END: float = 6.92 ## 9
## VO clause windows (mix wall-clock). Full sentences still own these spans;
## on-screen Chinese is further split at every comma for shorter lines.
const T_VO_S1_END: float = 13.3
const T_VO_S2_END: float = 19.3
const T_VO_S3_END: float = 34.0
const T_VO_NAIL: float = 19.76 ## S3 start / titan-only nail picture
const T_VO_NAIL_END: float = 23.66
const T_TITAN_DEPART_END: float = 23.56 ## 33 — first race cut on beat; nail picture may overlap 0.1s
## Four races × two camera rounds. The former three-round duration is redistributed across
## eight shots; every boundary remains on the measured beat grid.
const T_SHOWCASE_CUTS: Array[float] = [
	23.56, 28.41, 33.27, 37.42, 42.28,
	47.13, 51.98, 56.14, 61.00,
] ## beat indices 33,40,47,53,60,67,74,80,87
const T_SHOWCASE_END: float = 61.00
const T_ASSEMBLE_END: float = 63.08 ## 90
const T_FINALE_LOCK: float = 65.16 ## 93
const T_FINALE_HOLD_END: float = 68.63 ## 98
const T_FADE_END: float = 71.40 ## 102

const TITAN_DISPLAY: float = 14.0 ## legacy label only — live size comes from long-axis curve
const CAPITAL_DISPLAY: float = 5.5
const LIGHT_DISPLAY: float = 2.2
## Titans were only 12.6 wu against 10.73-wu supercarriers, so they read as the same
## tonnage. Keep the nonlinear curve, but give the titan dogma axis and clamp enough
## headroom to land near 20 wu. 大航 (supercarrier) dogmas are raised separately so they
## stay clearly between titan and freighter/carrier rather than vanishing into the midfleet.
const CG_SCALE_MAX_MUL: float = 7.5
const CG_TITAN_LONG_AXIS: float = 5000.0
const CG_SC_LONG_AXIS: float = 3200.0
## User pass: expand the current 1.14 cloud by another 1.5×.
const CG_FLEET_SPREAD_MUL: float = 1.71
## Hulls per ship type in a race fleet (大航 included). Kept at 1 so a missing
## class is countable on screen; raise for a denser parade once the roster is verified.
const HULLS_PER_TYPE: int = 1
## Bow parsing (why titans used to fly sideways):
##   ShipUnit._apply_model_orientation lays the hull length onto local Z. visual.json keeps
##   `ship_model_auto_orient: false` because Echoes hulls are already length-on-Z; TQ hulls
##   (tq_titan_* / tq_supercarrier_*) are length-on-X and only get re-laid when their def sets
##   `model_auto_orient: true`. After that pass an Echoes hull's bow is local -Z (unit yaw 0),
##   while a TQ hull comes out back-to-front and needs yaw PI — same convention as TitanBerth.
## _orient_bow_forward() re-measures the world AABB afterwards and adds 90° if a hull is still
## length-on-X, so a missing content flag can never put a hull broadside to its heading again.
const BOW_YAW_ECHOES: float = 0.0
const BOW_YAW_TQ: float = PI
## Each race cluster spans roughly 20 wu, so 18 wu arms let the four fleets interpenetrate.
const CROSS_RADIUS: float = 51.0
## Capitals sit in a wider cloud so height layers read from side / high / low cameras.
const FLEET_RING_MIN: float = 8.0
const FLEET_RING_MAX: float = 18.0
const FLEET_Y_CAPITAL: Vector2 = Vector2(-7.0, 9.0)
## Guaranteed review seats. 大航 (supercarrier) gets the most readable slot — abeam the
## titan, elevated, clear of freighter/carrier. These are final positions:
## `_spread_fleets_after_titan_scale` leaves them untouched.
const CAPITAL_REVIEW_POS: Dictionary = {
	"supercarrier": Vector3(28.0, 5.0, 0.0),
	"freighter": Vector3(-26.0, -5.0, -8.0),
	"carrier": Vector3(-24.0, 4.0, 14.0),
	"force_auxiliary": Vector3(24.0, -4.0, 14.0),
	"dreadnought": Vector3(0.0, -9.0, 22.0),
}
const PARADE_DIRECTION: Vector3 = Vector3(0.0, 0.0, -1.0)
const PARADE_SPEED: float = 4.2
## Titan-only 目送: enter from below-diagonal off-screen, recede along −Z.
const TITAN_DEPART_SPEED: float = 3.6
## Lane half-gap must exceed display titan size or the four hulls visually collide.
const TITAN_LANE_X: Array[float] = [-30.0, -10.0, 10.0, 30.0]
const TITAN_LANE_Y: Array[float] = [-0.6, 0.8, -0.4, 1.0]
## Depart path: start past/below the locked camera so hulls rise into frame then shrink away.
const TITAN_DEPART_START: Vector3 = Vector3(4.0, -16.0, 58.0)
const TITAN_DEPART_CAM_POS: Vector3 = Vector3(10.0, 16.0, 40.0)
## Ribbon trails are cheap; rebuild ~20 Hz so the head stays glued without SurfaceTool cost.
const TRAIL_REBUILD_S: float = 0.05
const TRAIL_REBUILD_WARM_S: float = 0.08
## Frigate/destroyer: tight on titan envelope sphere; revised speed = previous ×0.5.
const LIGHT_ORBIT_MARGIN: float = 0.55
const LIGHT_ORBIT_Z_FRAC: float = 0.22
const LIGHT_SPEED_MULT_MAX: float = 0.5
const LIGHT_ORBIT_RADIUS_MUL: float = 1.5
## Keep the same composition after the user-requested 1.5× spatial expansion.
const FINALE_ENTRY_RADIUS: float = 123.0
## Vertical framing must clear CROSS_RADIUS plus one cluster radius at fov 48°.
const FINALE_TOP_HEIGHT: float = 183.0
const RACE_ORBIT_RAD_PER_S: float = 0.22
const RACE_ORBIT_RADIUS: float = 26.0
const RACE_ORBIT_HEIGHT: float = 3.0
## Showcase only — four-titan 目送 keeps its tighter locked cam.
const SHOWCASE_CAM_DISTANCE: float = 57.0
## Distance floor only; the live distance also has to fit the measured cluster sphere.
const SHOWCASE_FRAME_MARGIN: float = 1.12
const FINALE_ORBIT_RAD_PER_S: float = 0.055
const FINALE_ORBIT_RADIUS: float = 46.0
const FINALE_ORBIT_HEIGHT: float = 24.0

@export var auto_play: bool = true
## Content clock vs wall clock. 1.0 = realtime. Keep at 1.0 unless debugging hitch budgets.
@export var preview_speed: float = 1.0
## Full Chinese subtitle authority (user 2026-08-01). Display splits at every comma.
@export var vo_s1: String = "在我的利诱下，新伊甸无人远征舰队，以及各族的泰坦，会在今天到达并且掀起内斗，在冬眠者控制区深处"
@export var vo_s2: String = "我采取这次措施是为了协助冬眠者组织，为了冬眠者重建家园"
@export var vo_s3: String = "没人能如此轻易地命令新伊甸和其四族前往一个危险的地方，但在经过无法拒绝的现成利益，在耗尽所有族的耐心后，这使得他们的到来成为必然"
@export var audio_path: String = "res://assets/audio/cg/opening_mix.mp3"

enum Beat {
	SLIDE_GODOT, SLIDE_JOINT, SLIDE_FAN, TITAN_DEPART,
	RACE_A, RACE_C, RACE_G, RACE_M,
	ASSEMBLE, FINALE_LOCK, FINALE_HOLD, FADE, DONE
}

var _t: float = 0.0
var _playing: bool = true
var _cam: Camera3D = null
var _cam_base_pos: Vector3 = Vector3(0, 10.0, 36.0)
var _cam_base_pitch_deg: float = -14.0
var _cam_base_yaw_deg: float = 0.0
var _world: Node3D = null
var _env_node: WorldEnvironment = null
var _env: Environment = null
var _hud: Label = null
var _pause_btn: Button = null
var _subtitle: Label = null
var _slide_layer: CanvasLayer = null
var _slide_root: Control = null
var _audio: AudioStreamPlayer = null
var _race_roots: Array[Dictionary] = [] ## per-race Node3D holding titan+fleet
var _tumblers: Array[Dictionary] = [] ## {node, axis, speed}
var _orbiters: Array[Dictionary] = [] ## frigate/destroyer holders on bow-vertical rings
var _trail_units: Array[Dictionary] = [] ## {unit, race_i, group, trail}
var _cross_placed: bool = false
var _last_beat: int = -1
var _last_active_race: int = -1
var _cam_orbit_yaw: float = 0.0
var _free_cam: bool = false
var _ready_to_play: bool = false
var _prepared_showcase_slot: int = -1
var _titan_orbit_radius: Array[float] = [8.0, 8.0, 8.0, 8.0]
var _race_cluster_radius: Array[float] = []
## Offline movie pass (`-- --cg-render` / CG_RENDER=1): content 1×, hide HUD, quit at end.
var _offline_render: bool = false
var _render_quit_armed: bool = false


func _ready() -> void:
	_playing = false
	_detect_offline_render()
	_apply_draft_render_profile()
	_apply_cg_scale_profile()
	_force_full_model_precision()
	_inject_capital_defs()
	_world = Node3D.new()
	_world.name = "CgWorld"
	add_child(_world)
	_build_env()
	_build_slides()
	## Cover initialization/prerender from the very first drawable frame. The opaque slide
	## still lets Godot rasterize the 3D pass underneath, so shader warm-up keeps working.
	_show_slide(Beat.SLIDE_GODOT)
	_build_hud()
	_build_audio()
	for i: int in RACES.size():
		_race_roots.append(_spawn_race_vignette(RACES[i], i))
	await _normalize_all()
	_align_trail_nozzles()
	## Capitals+titans emit while hidden so cuts inherit a wake; lights wait until visible
	## (their dense orbit motion makes GDScript tube rebuilds the main hitch).
	_set_trails_emitting_policy(-1, -1, true)
	await _prerender_all()
	_t = 0.0
	_apply_timeline(0.0)
	await get_tree().process_frame
	_ready_to_play = true
	_playing = auto_play
	if _playing and _audio and _audio.stream:
		_audio.play(0.0)
	if _offline_render:
		print("[CgOpeningDirector] OFFLINE RENDER ready — content 1× · quit at t=%.1f" % total_duration())
	else:
		print("[CgOpeningDirector] draft ready — Space/R/[ ]/1-9 · Alt free cam · F5 capture")


func _detect_offline_render() -> void:
	## User args after `--`: `Godot … scene.tscn -- --cg-render`
	for a: String in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s == "--cg-render" or s.begins_with("--cg-render="):
			_offline_render = true
	if OS.get_environment("CG_RENDER") == "1":
		_offline_render = true
	if not _offline_render:
		return
	preview_speed = 1.0
	auto_play = true


func _apply_cg_scale_profile() -> void:
	## Keep ShipUnit's long-axis pow curve; only lift the game clamp so titans aren't crushed
	## to the same 5.6 wu cap as a battleship. Must run BEFORE any ShipUnit.setup().
	if DataStore == null:
		return
	DataStore.visual["ship_scale_max_mul"] = CG_SCALE_MAX_MUL
	DataStore.visual["ship_scale_curve_power"] = TypedVariant.as_float(DataStore.visual.get("ship_scale_curve_power", 0.5), 0.5)
	print("[CgOpeningDirector] scale profile max_mul=%.1f power=%.2f (nonlinear long-axis)" % [
		CG_SCALE_MAX_MUL, TypedVariant.as_float(DataStore.visual.get("ship_scale_curve_power", 0.5), 0.5)
	])


func _force_full_model_precision() -> void:
	## Film / preview both need full meshes: no MobileModelLoad decimation, no half-float
	## attribute recompress. Must run before any ShipUnit.setup() / apply_tree().
	if DataStore == null:
		return
	DataStore.visual["model_load_precision_enabled"] = false
	DataStore.visual["model_load_precision_base"] = 1.0
	DataStore.visual["model_load_precision_scale_extra_max"] = 0.0
	DataStore.visual["model_half_precision_compress_enabled"] = false
	DataStore.visual["mobile_half_precision_models"] = false
	DataStore.visual["model_half_precision_all_platforms"] = false
	print("[CgOpeningDirector] model precision FULL (keep=1.0, half-float compress off)")


func _prerender_all() -> void:
	## Every hull is drawn before playback starts, so a cut never pays for first-time shader
	## compilation and mesh upload — that hitch is what threw the engine wake off its path.
	## Culled objects compile nothing, so the parade pose (all four fleets on one spot) is
	## staged in front of a temporary wide vantage and every hull really is rasterised.
	_apply_motion_at(T_SHOWCASE_CUTS[0])
	for i: int in _race_roots.size():
		var entry: Dictionary = _race_roots[i]
		_set_entry_contents(entry, true, true, true, true)
	var cam_pose: Transform3D = _cam.global_transform
	var cluster: Vector3 = Vector3.ZERO
	if _race_roots.size() > 0:
		var entry0: Dictionary = _race_roots[0]
		var root0_v: Variant = entry0.get("root")
		if root0_v is Node3D:
			cluster = root0_v.global_position
	_cam.global_position = cluster + Vector3(0.0, 26.0, 62.0)
	_cam.look_at(cluster, Vector3.UP)
	for _i: int in range(6):
		await get_tree().process_frame
	for i: int in _race_roots.size():
		var entry: Dictionary = _race_roots[i]
		_set_entry_contents(entry, false, false, false, false)
	_cam.global_transform = cam_pose
	## Park on the depart start so slide-warm stamps grow on the same path the cut will show.
	## Clearing here is fine — invisible titan trails re-warm under the opaque slides.
	_apply_motion_at(0.0)
	_clear_wakes()
	await get_tree().process_frame


func _report_wake_readiness(label: String) -> void:
	## A cut that opens on stubby plumes is the "拖尾被重置" bug — surface it in the log
	## instead of waiting to spot it in a render.
	var grown: int = 0
	var empty: int = 0
	for item: Dictionary in _trail_units:
		var trail_v: Variant = item.get("trail")
		var trail: EngineBoosterTrail = null
		if trail_v is EngineBoosterTrail:
			trail = trail_v
		if trail == null or not is_instance_valid(trail):
			continue
		if trail.wake_sample_count() >= 3:
			grown += 1
		else:
			empty += 1
	print("[CgOpeningDirector] %s cut-in wakes: %d grown / %d short" % [label, grown, empty])


func _clear_wakes() -> void:
	for item: Dictionary in _trail_units:
		var trail_v: Variant = item.get("trail")
		var trail: EngineBoosterTrail = null
		if trail_v is EngineBoosterTrail:
			trail = trail_v
		if trail != null and is_instance_valid(trail):
			trail.clear_wake()


func _apply_draft_render_profile() -> void:
	## GameSession forces 3× 3D supersample for the game; at 60 hulls that starves the
	## frame budget and the picture lags the audio clock. The draft renders 1:1, no MSAA.
	var root: Window = get_tree().root
	if root == null:
		return
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	Engine.max_fps = 60


func total_duration() -> float:
	return T_FADE_END


func _showcase_slot_at(t: float) -> int:
	for i: int in range(T_SHOWCASE_CUTS.size() - 1):
		if t < T_SHOWCASE_CUTS[i + 1]:
			return i
	return T_SHOWCASE_CUTS.size() - 2


func beat_at(t: float) -> int:
	if t < T_SLIDE0_END:
		return Beat.SLIDE_GODOT
	if t < T_SLIDE1_END:
		return Beat.SLIDE_JOINT
	if t < T_SLIDE2_END:
		return Beat.SLIDE_FAN
	if t < T_TITAN_DEPART_END:
		return Beat.TITAN_DEPART
	if t < T_SHOWCASE_END:
		return Beat.RACE_A + (_showcase_slot_at(t) % RACES.size())
	if t < T_ASSEMBLE_END:
		return Beat.ASSEMBLE
	if t < T_FINALE_LOCK:
		return Beat.FINALE_LOCK
	if t < T_FINALE_HOLD_END:
		return Beat.FINALE_HOLD
	if t < T_FADE_END:
		return Beat.FADE
	return Beat.DONE


func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	_free_cam = (not _offline_render) and Input.is_physical_key_pressed(KEY_ALT)
	if _free_cam:
		_update_camera_free(delta)
	_apply_preview_speed()
	if _playing:
		if _offline_render:
			## --fixed-fps / --write-movie: delta is exactly one content frame.
			_t = minf(_t + delta, total_duration())
		elif _audio and _audio.stream and _audio.playing:
			## get_playback_position is still content-seconds; pitch_scale slows how fast it advances.
			var audio_clock: float = _audio.get_playback_position()
			audio_clock += AudioServer.get_time_since_last_mix()
			audio_clock -= AudioServer.get_output_latency()
			_t = clampf(audio_clock, 0.0, total_duration())
		else:
			_t = minf(_t + delta * maxf(preview_speed, 0.05), total_duration())
	_apply_timeline(_t)
	if not _free_cam:
		_apply_motion_at(_t)
		_apply_light_orbits(_t)
		_apply_camera_at(_t)
	_spin_tumblers(delta)
	if _offline_render and _playing and _t >= total_duration() - 0.0001 and not _render_quit_armed:
		_render_quit_armed = true
		_playing = false
		print("[CgOpeningDirector] offline render complete t=%.2f — quitting" % _t)
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if not key_ev.pressed or key_ev.echo:
			return
		var k: Key = key_ev.keycode
		if k == KEY_SPACE:
			_toggle_play_pause()
			get_viewport().set_input_as_handled()
		elif k == KEY_R:
			_t = 0.0
			_cross_placed = false
			_prepared_showcase_slot = -1
			_last_active_race = -1
			_cam_orbit_yaw = 0.0
			_last_beat = -1
			_playing = true
			if _audio:
				_audio.play(0.0)
			get_viewport().set_input_as_handled()
		elif k == KEY_BRACKETLEFT:
			_t = maxf(0.0, _t - 1.0)
			_sync_audio()
			get_viewport().set_input_as_handled()
		elif k == KEY_BRACKETRIGHT:
			_t = minf(total_duration(), _t + 1.0)
			_sync_audio()
			get_viewport().set_input_as_handled()
		elif k == KEY_F5:
			_capture()
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k <= KEY_9:
			var jumps: Array[float] = [
				0.0, T_SLIDE0_END, T_SLIDE1_END, T_SLIDE2_END,
				T_TITAN_DEPART_END, T_SHOWCASE_CUTS[4],
				T_SHOWCASE_CUTS[6], T_SHOWCASE_END, T_FINALE_LOCK,
			]
			var idx: int = int(k - KEY_1)
			if idx < jumps.size():
				_t = jumps[idx]
				_sync_audio()
			get_viewport().set_input_as_handled()


func _toggle_play_pause() -> void:
	_playing = not _playing
	if _audio:
		if _playing:
			_audio.play(_t)
		else:
			_audio.stop()
	_refresh_pause_btn()


func _refresh_pause_btn() -> void:
	if _pause_btn == null:
		return
	_pause_btn.text = "继续" if not _playing else "暂停"


func _sync_audio() -> void:
	if _audio and _audio.stream:
		if _playing:
			_audio.play(_t)
		else:
			_audio.stop()


func _apply_timeline(t: float) -> void:
	var beat: int = beat_at(t)
	_show_slide(beat)
	if beat != _last_beat:
		_on_beat_enter(beat, t)
		_last_beat = beat
		print("[CgOpeningDirector] beat=", Beat.keys()[beat], " t=", snapped(t, 0.1))
	_update_world_for_beat(beat, t)
	_update_subtitle(beat, t)
	if _hud:
		_hud.visible = not _offline_render
		if not _offline_render:
			var drift: float = t - (_audio.get_playback_position() if _audio and _audio.playing else t)
			_hud.text = "CG draft  t=%.1f/%.1f  ×%.2f  beat=%s  %d fps  a/v %+.2fs | Space R [] 1-9 F5 | Alt+WASD" % [
				t, total_duration(), preview_speed, Beat.keys()[beat], Engine.get_frames_per_second(), drift
			]
	if _pause_btn:
		_pause_btn.visible = not _offline_render
		_refresh_pause_btn()


func _show_slide(beat: int) -> void:
	if _slide_root == null:
		return
	var show_ui: bool = beat == Beat.SLIDE_GODOT or beat == Beat.SLIDE_JOINT or beat == Beat.SLIDE_FAN
	_slide_root.visible = show_ui
	for c: Node in _slide_root.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
	match beat:
		Beat.SLIDE_GODOT:
			var slide_godot_v: Node = _slide_root.get_node("SlideGodot")
			if slide_godot_v is CanvasItem:
				(slide_godot_v as CanvasItem).visible = true
		Beat.SLIDE_JOINT:
			var slide_joint_v: Node = _slide_root.get_node("SlideJoint")
			if slide_joint_v is CanvasItem:
				(slide_joint_v as CanvasItem).visible = true
		Beat.SLIDE_FAN:
			var slide_fan_v: Node = _slide_root.get_node("SlideFan")
			if slide_fan_v is CanvasItem:
				(slide_fan_v as CanvasItem).visible = true


func _update_subtitle(_beat: int, t: float) -> void:
	if _subtitle == null:
		return
	## One on-screen clause per comma; timing stays inside the original S1/S2/S3 windows
	## and is weighted by character count so short clauses do not linger.
	var line: String = _subtitle_clause_at(t)
	_subtitle.visible = line != ""
	if _subtitle.visible:
		_subtitle.text = line


func _subtitle_clause_at(t: float) -> String:
	if t < 0.0 or t >= T_VO_S3_END:
		return ""
	var text: String = ""
	var t0: float = 0.0
	var t1: float = T_VO_S1_END
	if t < T_VO_S1_END:
		text = vo_s1
	elif t < T_VO_S2_END:
		text = vo_s2
		t0 = T_VO_S1_END
		t1 = T_VO_S2_END
	else:
		text = vo_s3
		t0 = T_VO_S2_END
		t1 = T_VO_S3_END
	var clauses: PackedStringArray = _split_subtitle_clauses(text)
	if clauses.is_empty():
		return ""
	var weights: Array[float] = []
	var total_w: float = 0.0
	for c: String in clauses:
		var w: float = float(maxi(str(c).length(), 1))
		weights.append(w)
		total_w += w
	var u: float = clampf((t - t0) / maxf(0.01, t1 - t0), 0.0, 0.9999)
	var acc: float = 0.0
	for i: int in clauses.size():
		acc += weights[i] / total_w
		if u < acc:
			return str(clauses[i])
	return str(clauses[clauses.size() - 1])


func _split_subtitle_clauses(text: String) -> PackedStringArray:
	## Strict comma split: each "，" / "," ends one on-screen line.
	var raw: PackedStringArray = text.replace(",", "，").split("，", false)
	var out: PackedStringArray = PackedStringArray()
	for part: String in raw:
		var s: String = str(part).strip_edges()
		if s != "":
			out.append(s)
	return out


func _on_beat_enter(beat: int, _t_enter: float) -> void:
	_cross_placed = false if beat < Beat.ASSEMBLE else _cross_placed
	match beat:
		Beat.TITAN_DEPART:
			_set_sky_neutral()
			## All four titans are on screen for 目送 — every hull must already be plumed,
			## lights included, or the cut shows escorts igniting on camera.
			_set_trails_emitting_policy(-1, -1, true, true)
			_report_wake_readiness("目送")
		Beat.RACE_A:
			## No clear_wake here — capital wakes already warmed on the continuous parade path.
			_set_sky_race(RACES[0])
		Beat.RACE_C, Beat.RACE_G, Beat.RACE_M:
			var ri: int = beat - Beat.RACE_A
			_set_sky_race(RACES[ri])
		Beat.ASSEMBLE:
			_ensure_cross_layout()
			## Only teleport of the film: the parade wake would smear across the map, so it
			## is dropped here and immediately regrown on the slow cross approach.
			_clear_wakes()
			_set_sky_neutral()
			_last_active_race = -1
			_set_trails_emitting_policy(-1, -1, true, true)
		Beat.FINALE_LOCK, Beat.FINALE_HOLD:
			_ensure_cross_layout()
			_set_sky_neutral()
			_set_trails_emitting_policy(-1, -1, true, true)
		Beat.FADE, Beat.DONE:
			_ensure_cross_layout()
			_set_sky_neutral()
			_set_trails_emitting(false)
		_:
			pass


func _update_world_for_beat(beat: int, t: float) -> void:
	## Visibility + process gating. Motion and camera are absolute functions of audio time.
	var showcase: bool = t >= T_SHOWCASE_CUTS[0] and t < T_SHOWCASE_END
	var slot: int = _showcase_slot_at(t) if showcase else -1
	var active_race: int = slot % RACES.size() if showcase else -1
	var next_slot: int = slot + 1
	var _next_race: int = next_slot % RACES.size() if showcase and next_slot < T_SHOWCASE_CUTS.size() - 1 else -1
	_last_active_race = active_race
	if showcase:
		_prepared_showcase_slot = next_slot
	## Wakes are never cleared or gated mid-film: every hull of every race keeps stamping,
	## on-screen or not, so a cut always inherits a grown plume. A race that returns for the
	## second round therefore looks identical to the one that never left.
	if beat != Beat.FADE and beat != Beat.DONE:
		_set_trails_emitting_policy(-1, -1, true, true)
	for i: int in _race_roots.size():
		var entry_v: Variant = _race_roots[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if not entry.has("root"):
			continue
		match beat:
			Beat.SLIDE_GODOT, Beat.SLIDE_JOINT, Beat.SLIDE_FAN, Beat.TITAN_DEPART:
				## Hidden fleets still run so their wakes exist at the first race cut.
				var titan_only: bool = beat == Beat.TITAN_DEPART
				_set_entry_contents(entry, titan_only, titan_only, false, true)
			Beat.RACE_A, Beat.RACE_C, Beat.RACE_G, Beat.RACE_M:
				var active: bool = i == active_race
				_set_entry_contents(entry, active, active, active, true)
			Beat.ASSEMBLE, Beat.FINALE_LOCK, Beat.FINALE_HOLD, Beat.FADE, Beat.DONE:
				_set_entry_contents(entry, true, true, true, false)
			_:
				_set_entry_contents(entry, false, false, false, true)
	if beat == Beat.FADE or beat == Beat.DONE:
		if _env:
			var fade_u: float = clampf((t - T_FINALE_HOLD_END) / maxf(0.01, T_FADE_END - T_FINALE_HOLD_END), 0.0, 1.0)
			_env.adjustment_enabled = true
			_env.adjustment_brightness = lerpf(1.0, 0.05, fade_u)


func _set_entry_contents(entry: Dictionary, root_visible: bool, titan_visible: bool, fleet_visible: bool, warming: bool) -> void:
	var root_v: Variant = entry.get("root")
	if root_v is Node3D:
		var root: Node3D = root_v
		_set_node_active(root, root_visible, root_visible or warming)
	var titan_holder_v: Variant = entry.get("titan_holder")
	if titan_holder_v is Node3D:
		var titan_holder: Node3D = titan_holder_v
		_set_node_active(titan_holder, titan_visible, titan_visible or warming)
	var fleet_v: Variant = entry.get("fleet")
	if fleet_v is Array:
		for f_v: Variant in fleet_v:
			if f_v is Dictionary:
				var f: Dictionary = f_v
				var holder_v: Variant = f.get("holder")
				if holder_v is Node3D:
					var escort_holder: Node3D = holder_v
					_set_node_active(escort_holder, fleet_visible, fleet_visible or warming)


func _set_node_active(node: Node3D, vis: bool, run: bool) -> void:
	## Disabled subtrees skip ShipUnit and trail _process — the only way 60 hulls hold 60 fps.
	node.visible = vis
	var mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT if run else Node.PROCESS_MODE_DISABLED
	if node.process_mode != mode:
		node.process_mode = mode


func _show_all_races(vis: bool) -> void:
	for entry: Dictionary in _race_roots:
		if not entry.has("root"):
			continue
		var root_v: Variant = entry.get("root")
		if root_v is Node3D:
			root_v.visible = vis


func _apply_motion_at(t: float) -> void:
	## Parade path also runs under the slides so invisible titan wakes already exist at cut-in.
	if t < T_SHOWCASE_END:
		## Each race keeps its own permanent lane offset — never collapse holders to the
		## origin (that read as titans slamming into an invisible wall). Roots also never
		## teleport between depart and showcase, so titan wakes stay continuous.
		var base: Vector3 = _continuous_parade_pos(t)
		for i: int in _race_roots.size():
			var entry: Dictionary = _race_roots[i]
			var root_v: Variant = entry.get("root")
			if root_v is Node3D:
				var root: Node3D = root_v
				root.position = base + Vector3(TITAN_LANE_X[i], TITAN_LANE_Y[i], 0.0)
				root.rotation = Vector3.ZERO
			var titan_holder_v: Variant = entry.get("titan_holder")
			if titan_holder_v is Node3D:
				titan_holder_v.position = Vector3.ZERO
	else:
		_apply_finale_entry_at(t)


func _continuous_parade_pos(t: float) -> Vector3:
	## Constant −Z velocity, running from t=0 so the hulls are already travelling while the
	## slides cover them. A standing start at the 目送 cut gave the first shot a wake that
	## visibly grew from zero; the pre-roll means it is already full length at cut-in.
	var depart_t: float = clampf(t, 0.0, T_SHOWCASE_CUTS[0])
	var pos: Vector3 = _parade_origin() + PARADE_DIRECTION * TITAN_DEPART_SPEED * depart_t
	if t > T_SHOWCASE_CUTS[0]:
		pos += PARADE_DIRECTION * PARADE_SPEED * (t - T_SHOWCASE_CUTS[0])
	return pos


func _parade_origin() -> Vector3:
	## Back-dated so the hull still sits exactly on TITAN_DEPART_START when the slides end —
	## the pre-roll changes nothing about the depart composition.
	return TITAN_DEPART_START - PARADE_DIRECTION * TITAN_DEPART_SPEED * T_SLIDE2_END


func _apply_light_orbits(t: float) -> void:
	## Orbit plane ⊥ bow (−Z) ⇒ local XY. Radius hugs the measured titan envelope sphere;
	## tangential speed is capped at LIGHT_SPEED_MULT_MAX × PARADE_SPEED.
	if t >= T_SHOWCASE_END:
		return
	var clock: float = maxf(0.0, t - T_SLIDE2_END)
	for item: Dictionary in _orbiters:
		var holder_v: Variant = item.get("holder")
		var holder: Node3D = holder_v if holder_v is Node3D else null
		if holder == null or not is_instance_valid(holder):
			continue
		var race_i: int = TypedVariant.as_int(item.get("race_i", 0), 0)
		var base_r: float = _titan_orbit_radius[race_i] if race_i < _titan_orbit_radius.size() else 8.0
		var r: float = base_r * LIGHT_ORBIT_RADIUS_MUL + TypedVariant.as_float(item.get("r_extra", 0.0), 0.0) * LIGHT_ORBIT_RADIUS_MUL
		var v_cap: float = PARADE_SPEED * LIGHT_SPEED_MULT_MAX
		var omega: float = minf(TypedVariant.as_float(item.get("omega_want", 0.0), 0.0), v_cap / maxf(r, 0.5))
		var ang: float = TypedVariant.as_float(item.get("phase0", 0.0), 0.0) + omega * clock
		holder.position = Vector3(cos(ang) * r, sin(ang) * r, TypedVariant.as_float(item.get("z", 0.0), 0.0))
		## Bow follows the real path: ring tangent plus the fleet's own −Z parade drift.
		## Race roots are unrotated, so local and world axes coincide here.
		var parade_v: float = TITAN_DEPART_SPEED if t < T_SHOWCASE_CUTS[0] else PARADE_SPEED
		var vel: Vector3 = Vector3(-sin(ang), cos(ang), 0.0) * (r * omega) + PARADE_DIRECTION * parade_v
		_aim_bow_along(holder, vel)


func _aim_bow_along(holder: Node3D, vel: Vector3) -> void:
	## Hull bow is holder −Z (same convention as the titans), which is what look_at aims.
	if vel.length_squared() < 0.0001:
		return
	var dir: Vector3 = vel.normalized()
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.FORWARD
	holder.look_at(holder.global_position + dir, up)


func _apply_camera_at(t: float) -> void:
	if _cam == null:
		return
	if t >= T_SHOWCASE_END:
		_apply_finale_top_down_cam()
		return
	var beat: int = beat_at(t)
	match beat:
		Beat.TITAN_DEPART:
			## Locked vantage above-right; titans climb out of the lower-diagonal off-screen
			## and recede along −Z — classic 目送, camera does not chase.
			var look: Vector3 = _continuous_parade_pos(t) + Vector3(0.0, 2.0, 0.0)
			_cam.position = TITAN_DEPART_CAM_POS
			_cam.look_at(look, Vector3.UP)
			_cam_base_pos = _cam.position
			_cam_base_pitch_deg = _cam.rotation_degrees.x
			_cam_base_yaw_deg = _cam.rotation_degrees.y
		Beat.RACE_A, Beat.RACE_C, Beat.RACE_G, Beat.RACE_M:
			var phase_t: float = maxf(0.0, t - T_SHOWCASE_CUTS[0])
			_cam_orbit_yaw = 0.35 + phase_t * RACE_ORBIT_RAD_PER_S
			var slot: int = _showcase_slot_at(t)
			var active_i: int = slot % RACES.size()
			var round_i: int = floori(float(slot) / float(RACES.size()))
			var e: Dictionary = _race_roots[active_i]
			var center: Vector3 = Vector3.ZERO
			var race_root_v: Variant = e.get("root")
			if race_root_v is Node3D:
				center = race_root_v.global_position + Vector3(0, 1.5, 0)
			if round_i == 0:
				## First round genuinely descends on a sphere: high俯视 +58° → below-target
				## 仰视 −18°, while yaw keeps orbiting continuously across race cuts.
				var round_u: float = clampf(
					(t - T_SHOWCASE_CUTS[0])
					/ maxf(0.01, TypedVariant.as_float(T_SHOWCASE_CUTS[4], 0.0) - T_SHOWCASE_CUTS[0]),
					0.0, 1.0
				)
				round_u = smoothstep(0.0, 1.0, round_u)
				var elevation: float = lerpf(deg_to_rad(58.0), deg_to_rad(-18.0), round_u)
				_apply_spherical_orbit_cam(center, _showcase_cam_distance(active_i), elevation)
			else:
				## One continuous spherical move, not three discrete angle presets:
				## elevation −22° is physically below the target (仰视), crosses the
				## target plane/斜上方, and ends at +68° (high 俯视).
				var round_u: float = clampf(
					(t - TypedVariant.as_float(T_SHOWCASE_CUTS[4], 0.0))
					/ maxf(0.01, T_SHOWCASE_END - TypedVariant.as_float(T_SHOWCASE_CUTS[4], 0.0)),
					0.0, 1.0
				)
				round_u = smoothstep(0.0, 1.0, round_u)
				var elevation: float = lerpf(deg_to_rad(-22.0), deg_to_rad(68.0), round_u)
				_apply_spherical_orbit_cam(center, _showcase_cam_distance(active_i), elevation)
		_:
			pass


func _apply_orbit_cam(center: Vector3, radius: float, height: float) -> void:
	if _cam == null:
		return
	var yaw: float = _cam_orbit_yaw
	var pos: Vector3 = center + Vector3(sin(yaw) * radius, height, cos(yaw) * radius)
	_cam.position = pos
	_cam.look_at(center, Vector3.UP)
	_cam_base_pos = pos
	_cam_base_pitch_deg = _cam.rotation_degrees.x
	_cam_base_yaw_deg = _cam.rotation_degrees.y


func _apply_spherical_orbit_cam(center: Vector3, distance: float, elevation: float) -> void:
	var horizontal: float = cos(elevation) * distance
	var pos: Vector3 = center + Vector3(
		sin(_cam_orbit_yaw) * horizontal,
		sin(elevation) * distance,
		cos(_cam_orbit_yaw) * horizontal
	)
	_cam.position = pos
	_cam.look_at(center, Vector3.UP)
	_cam_base_pos = pos
	_cam_base_pitch_deg = _cam.rotation_degrees.x
	_cam_base_yaw_deg = _cam.rotation_degrees.y


func _apply_finale_top_down_cam() -> void:
	## Exact vertical top-down. Vector3.FORWARD is the screen-up reference because
	## Vector3.UP is collinear with the viewing direction and invalid for look_at().
	_cam.position = Vector3(0.0, FINALE_TOP_HEIGHT, 0.0)
	_cam.look_at(Vector3.ZERO, Vector3.FORWARD)
	_cam_base_pos = _cam.position
	_cam_base_pitch_deg = _cam.rotation_degrees.x
	_cam_base_yaw_deg = _cam.rotation_degrees.y


func _finale_slots() -> Array[Dictionary]:
	return [
		{"i": 3, "pos": Vector3(0, 0, -CROSS_RADIUS)},
		{"i": 1, "pos": Vector3(CROSS_RADIUS, 0, 0)},
		{"i": 2, "pos": Vector3(0, 0, CROSS_RADIUS)},
		{"i": 0, "pos": Vector3(-CROSS_RADIUS, 0, 0)},
	]


func _apply_finale_entry_at(t: float) -> void:
	var u: float = clampf(
		(t - T_SHOWCASE_END) / maxf(0.01, T_FINALE_LOCK - T_SHOWCASE_END),
		0.0, 1.0
	)
	## Ease-out bias: more of the travel happens early so the last third reads as a slow settle.
	u = 1.0 - pow(1.0 - smoothstep(0.0, 1.0, u), 1.65)
	for s: Dictionary in _finale_slots():
		var slot_i: int = TypedVariant.as_int(s.get("i", 0), 0)
		var entry_finale: Dictionary = _race_roots[slot_i]
		var root_v: Variant = entry_finale.get("root")
		if not root_v is Node3D:
			continue
		var root: Node3D = root_v
		var target_v: Variant = s.get("pos", Vector3.ZERO)
		var target: Vector3 = target_v if target_v is Vector3 else Vector3.ZERO
		var start: Vector3 = target.normalized() * FINALE_ENTRY_RADIUS
		root.position = start.lerp(target, u)
		root.look_at(Vector3.ZERO, Vector3.UP)


func _ensure_cross_layout() -> void:
	if _cross_placed:
		return
	_cross_placed = true
	## The top-down cut begins with all four centers outside frame. _apply_finale_entry_at()
	## eases them into these same N/E/S/W targets and stops exactly there.
	for s: Dictionary in _finale_slots():
		var slot_i: int = TypedVariant.as_int(s.get("i", 0), 0)
		var entry: Dictionary = _race_roots[slot_i]
		var root_v: Variant = entry.get("root")
		if not root_v is Node3D:
			continue
		var root: Node3D = root_v
		var target_v: Variant = s.get("pos", Vector3.ZERO)
		var target: Vector3 = target_v if target_v is Vector3 else Vector3.ZERO
		root.position = target.normalized() * FINALE_ENTRY_RADIUS
		root.look_at(Vector3.ZERO, Vector3.UP)
	## Escort bows tracked their orbit tangent during the parade; the tableau is a formation
	## hold, so drop that heading and let every hull share the race root's facing.
	for item: Dictionary in _orbiters:
		var holder_v: Variant = item.get("holder")
		var holder: Node3D = holder_v if holder_v is Node3D else null
		if holder != null and is_instance_valid(holder):
			holder.rotation = Vector3.ZERO


func _set_sky_race(def: Dictionary) -> void:
	var path: String = str(def.get("sky_jpeg", "res://assets/skyboxes/races/ah1.jpg"))
	_apply_panorama(path)


func _set_sky_neutral() -> void:
	_apply_panorama("res://assets/skyboxes/races/gh1.jpg")


func _apply_panorama(path: String) -> void:
	if _env == null:
		return
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and DataStore:
		tex = UiAssets.tex(path)
	if tex == null:
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color(0.02, 0.03, 0.06)
		return
	var mat: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
	mat.panorama = tex
	var sky: Sky = Sky.new()
	sky.sky_material = mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky


func _build_env() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.light_energy = 1.45
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-42, 35, 0)
	add_child(light)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.light_energy = 1.05
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.rotation_degrees = Vector3(-18, -140, 0)
	add_child(rim)
	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 48.0
	_apply_cam()
	add_child(_cam)
	_env_node = WorldEnvironment.new()
	_env = Environment.new()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.22, 0.24, 0.28)
	_env.ambient_light_energy = 1.7
	_env.glow_enabled = false
	_env.glow_intensity = 0.0
	_env_node.environment = _env
	add_child(_env_node)
	_set_sky_neutral()


func _apply_cam() -> void:
	if _cam == null:
		return
	_cam.position = _cam_base_pos
	_cam.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)


func _build_slides() -> void:
	_slide_layer = CanvasLayer.new()
	_slide_layer.layer = 20
	add_child(_slide_layer)
	_slide_root = Control.new()
	_slide_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slide_layer.add_child(_slide_root)

	## 01 Made with Godot
	var g: ColorRect = _make_slide_panel("SlideGodot")
	var gtitle: Label = Label.new()
	gtitle.text = "MADE WITH GODOT"
	gtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	gtitle.add_theme_font_size_override("font_size", 64)
	gtitle.add_theme_color_override("font_color", Color(0.478, 0.698, 0.941))
	g.add_child(gtitle)

	## 02 Joint producers
	var j: ColorRect = _make_slide_panel("SlideJoint")
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 36)
	j.add_child(row)
	row.add_child(_make_logo_tex("res://assets/ui/cg_slides/xingshi_huanyu.jpg", 220))
	var times: Label = Label.new()
	times.text = "×"
	times.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	times.add_theme_font_size_override("font_size", 96)
	times.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	row.add_child(times)
	row.add_child(_make_logo_tex("res://assets/ui/cg_slides/jiuxing_duxing_team.png", 220))
	var joint: Label = Label.new()
	joint.text = "联合出品"
	joint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## CENTER_BOTTOM has zero width, so horizontal_alignment cannot center the glyphs.
	## BOTTOM_WIDE supplies a real full-width box centered on the viewport.
	joint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	joint.offset_left = 0
	joint.offset_right = 0
	joint.offset_top = -140
	joint.offset_bottom = -90
	joint.add_theme_font_size_override("font_size", 36)
	joint.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	j.add_child(joint)

	## 03 Fan disclaimer
	var f: ColorRect = _make_slide_panel("SlideFan")
	var fbody: Label = Label.new()
	fbody.text = "EVE非商业同人"
	fbody.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fbody.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fbody.set_anchors_preset(Control.PRESET_FULL_RECT)
	fbody.add_theme_font_size_override("font_size", 36)
	fbody.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	f.add_child(fbody)


func _make_slide_panel(node_name: String) -> ColorRect:
	var p: ColorRect = ColorRect.new()
	p.name = node_name
	p.color = Color(0, 0, 0, 1)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	_slide_root.add_child(p)
	return p


func _make_logo_tex(path: String, side: int) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(path):
		rect.texture = load(path) as Texture2D
	return rect


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_left = 12
	_hud.offset_top = 8
	_hud.offset_bottom = 40
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.85))
	layer.add_child(_hud)
	_pause_btn = Button.new()
	_pause_btn.text = "暂停"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.anchor_left = 1.0
	_pause_btn.anchor_right = 1.0
	_pause_btn.offset_left = -132
	_pause_btn.offset_right = -16
	_pause_btn.offset_top = 10
	_pause_btn.offset_bottom = 52
	_pause_btn.add_theme_font_size_override("font_size", 20)
	_pause_btn.pressed.connect(_toggle_play_pause)
	layer.add_child(_pause_btn)
	_subtitle = Label.new()
	## BOTTOM_WIDE, not CENTER_BOTTOM: the centred preset anchors both edges at 0.5, so the
	## side margins subtract into a negative width and every glyph wraps onto its own line.
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.offset_left = 160
	_subtitle.offset_right = -160
	_subtitle.offset_top = -150
	_subtitle.offset_bottom = -48
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_subtitle.add_theme_constant_override("outline_size", 6)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.visible = false
	layer.add_child(_subtitle)


func _build_audio() -> void:
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_apply_preview_speed()
	var candidates: Array[String] = [
		audio_path,
		"res://assets/audio/cg/opening_mix.mp3",
	]
	## Also try external精校 path via user copy note — skip if missing
	for p: String in candidates:
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			var stream: AudioStream = load(p) as AudioStream
			if stream:
				_audio.stream = stream
				print("[CgOpeningDirector] audio %s · preview_speed=%.2f (wall)" % [p, preview_speed])
				return
	print("[CgOpeningDirector] no opening_mix yet — drop mp3 at res://assets/audio/cg/opening_mix.mp3")


func _apply_preview_speed() -> void:
	## pitch_scale drives both rate and pitch; content clock stays the audio position.
	if _audio == null:
		return
	var s: float = maxf(preview_speed, 0.05)
	if not is_equal_approx(_audio.pitch_scale, s):
		_audio.pitch_scale = s


func _inject_capital_defs() -> void:
	if DataStore == null:
		push_error("CgOpeningDirector: DataStore missing")
		return
	for def: Dictionary in RACES:
		## Content titans (201–204) often omit model_long_axis → ShipUnit falls back to raw
		## mesh AABB and then the game clamp flattens them. Patch the dogma axis first.
		_patch_titan_long_axis(TypedVariant.as_int(def.get("id", 0), 0))
		## 大航 = supercarrier. Name the def with CCP 中文 + colloquial alias for roll-call logs.
		_ensure_ship_def(
			TypedVariant.as_int(def.get("sc_id", 0), 0),
			"%s（%s）" % [str(def["sc_name"]), str(def["sc_alias"])],
			str(def["sc_name_en"]),
			str(def["sc_key"]),
			str(def["race_id"]),
			"supercarrier",
			CG_SC_LONG_AXIS
		)


func _patch_titan_long_axis(sid: int) -> void:
	if DataStore == null or not DataStore.ships.has(sid):
		return
	var s: Dictionary = DataStore.ships[sid]
	if TypedVariant.as_float(s.get("model_long_axis", 0.0), 0.0) <= 0.0:
		s["model_long_axis"] = CG_TITAN_LONG_AXIS
		print("[CgOpeningDirector] patched %s model_long_axis=%.0f" % [str(s.get("name", sid)), CG_TITAN_LONG_AXIS])


func _ensure_ship_def(sid: int, ship_name: String, name_en: String, model_key: String, race_id: String, group: String, long_axis: float) -> void:
	## Always refresh axis / orient flags — a stale inject from an earlier CG run must not
	## keep the old 1400 dogma that made 大航 look like a battleship.
	if DataStore.ships.has(sid):
		var existing: Dictionary = DataStore.ships[sid]
		existing["name"] = ship_name
		existing["name_en"] = name_en
		existing["model_key"] = model_key
		existing["model_long_axis"] = long_axis
		existing["model_auto_orient"] = model_key.begins_with("tq_")
		existing["ship_group"] = group
		existing["race"] = race_id
		return
	DataStore.ships[sid] = {
		"id": sid,
		"name": ship_name,
		"name_en": name_en,
		"model_key": model_key,
		"model_long_axis": long_axis,
		## TQ hulls are authored length-on-X and must opt back into auto-orient.
		"model_auto_orient": model_key.begins_with("tq_"),
		"race": race_id,
		"ship_group": group,
		"cost": 0,
		"fetter_ids": [],
		"tags": [race_id, group],
		"is_logistic": false,
		"weapon_fx": "",
		"function_slots": {"slots": []},
		"stars": [{
			"attack_range": 8,
			"damage": {"emp": 1.0, "thermal": 0.0, "kinetic": 0.0, "explosive": 0.0},
			"repair": {"shield": 0.0, "armor": 0.0, "structure": 0.0},
			"shield": 100.0, "armor": 100.0, "structure": 100.0,
			"shield_resist": {}, "armor_resist": {}, "structure_resist": {},
			"attack_duration": 1.0,
		}],
	}


func _spawn_race_vignette(def: Dictionary, race_i: int) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.name = "Race_%s" % str(def["race"])
	root.visible = false
	_world.add_child(root)

	var titan_holder: Node3D = Node3D.new()
	titan_holder.name = "Titan"
	root.add_child(titan_holder)
	var titan: ShipUnit = ShipUnit.new()
	titan_holder.add_child(titan)
	titan.setup(TypedVariant.as_int(def.get("id", 0), 0), 1, ShipUnit.TEAM_PLAYER)
	if titan.has_method("clear_health_bar"):
		titan.clear_health_bar()
	titan.slot_type = ""
	titan.rotation.y = _bow_yaw_for(titan, str(def["model_key"]))
	_attach_trail(titan, "titan", race_i, str(def["model_key"]))

	var fleet_nodes: Array[Dictionary] = []
	var ei: int = 0
	## 大航 (supercarrier) ships even when it is not in the playable roster.
	if ResourceLoader.exists("res://assets/models/ships/%s/model.glb" % str(def["sc_key"])):
		var sc_def: Dictionary = {
			"id": TypedVariant.as_int(def.get("sc_id", 0), 0),
			"model_key": str(def["sc_key"]),
			"ship_group": "supercarrier",
			"name": "%s（%s）" % [str(def["sc_name"]), str(def["sc_alias"])],
		}
		for _i: int in HULLS_PER_TYPE:
			fleet_nodes.append(_spawn_escort(root, sc_def, race_i, ei))
			ei += 1
		print("[CgOpeningDirector] 大航上场 %s/%s key=%s" % [
			str(def["sc_name"]), str(def["sc_alias"]), str(def["sc_key"])
		])
	else:
		## Textures alone ship in some bundles; without model.glb the hull silently vanishes
		## from the parade, which reads as "this race is missing 大航".
		push_warning("CgOpeningDirector: %s has no model.glb — 大航 absent from %s fleet" % [
			str(def["sc_key"]), str(def["name"])
		])
		print("[CgOpeningDirector] MISSING MODEL %s — %s（%s）大航不会出场" % [
			str(def["sc_key"]), str(def["sc_name"]), str(def["sc_alias"])
		])

	## Every modeled non-titan hull, no type budget — capitals used to vanish when the
	## DataStore file-order list was capped at 14.
	var escorts: Array[Dictionary] = _list_race_ships(str(def["race_id"]))
	for ship: Dictionary in escorts:
		for _i: int in HULLS_PER_TYPE:
			fleet_nodes.append(_spawn_escort(root, ship, race_i, ei))
			ei += 1

	print("[CgOpeningDirector] race %s fleet=%d hulls (titan + %d escorts, %d types×%d)" % [
		str(def["name"]), fleet_nodes.size() + 1, fleet_nodes.size(), escorts.size() + 1, HULLS_PER_TYPE
	])
	return {"root": root, "titan_holder": titan_holder, "titan": titan, "fleet": fleet_nodes, "def": def, "parade_z": 0.0}


## Stable parade order only — does not cull. Capitals first so they sit near the titan.
const FLEET_CLASS_ORDER: Array[String] = [
	"freighter", "carrier", "force_auxiliary", "dreadnought", "battleship",
	"battlecruiser", "cruiser", "destroyer", "frigate",
]


func _list_race_ships(race_id: String) -> Array[Dictionary]:
	var by_group: Dictionary = {}
	var discovered: Array[String] = []
	if DataStore == null:
		return []
	for sid: Variant in DataStore.ships.keys():
		var s: Variant = DataStore.ships[sid]
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		if str(d.get("race", "")) != race_id:
			continue
		var group: String = str(d.get("ship_group", ""))
		## Titans / supercarriers are injected separately; wrecks and unmanned craft
		## (fighters, light/heavy drones, repair drones) stay out of the parade.
		if group in ["titan", "supercarrier", "wreck"]:
			continue
		if TypedVariant.as_bool(d.get("is_unmanned", false), false):
			continue
		if group.begins_with("drone") or group in ["fighter", "repair_drone"]:
			continue
		var mk: String = str(d.get("model_key", ""))
		if mk == "" or not ResourceLoader.exists("res://assets/models/ships/%s/model.glb" % mk):
			continue
		if not by_group.has(group):
			by_group[group] = []
			discovered.append(group)
		(TypedVariant.as_array(by_group.get(group, [])) as Array).append(d)

	var groups: Array[String] = []
	for g: String in FLEET_CLASS_ORDER:
		if by_group.has(g):
			groups.append(g)
	for g: String in discovered:
		if not groups.has(g):
			groups.append(g)

	var out: Array[Dictionary] = []
	for g: String in groups:
		var pool: Array[Dictionary] = by_group[g]
		var names: Array[String] = []
		for d: Dictionary in pool:
			out.append(d)
			names.append(str(d.get("name", "?")))
		## Roll-call so "this race lost a ship" can be checked against the screen by name.
		print("[CgOpeningDirector]   %s %-16s ×%d: %s" % [race_id, g, pool.size(), ", ".join(names)])
	print("[CgOpeningDirector] %s types=%d" % [race_id, out.size()])
	return out


func _spawn_escort(parent: Node3D, ship: Dictionary, race_i: int, slot_i: int) -> Dictionary:
	var sid: int = TypedVariant.as_int(ship.get("id", 0), 0)
	var model_key: String = str(ship.get("model_key", ""))
	var group: String = str(ship.get("ship_group", ""))
	var holder: Node3D = Node3D.new()
	holder.name = "Escort_%s_%d" % [model_key, slot_i]
	parent.add_child(holder)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%s_%d_%d" % [model_key, race_i, slot_i])
	var capital: bool = group in [
		"battleship", "battlecruiser", "cruiser", "carrier", "force_auxiliary", "fax",
		"supercarrier", "freighter", "industrial", "dreadnought",
	]
	var review_capital: bool = CAPITAL_REVIEW_POS.has(group)
	var light_orbit: bool = group in ["frigate", "destroyer"]
	## Escorts fly bow-first along their own path (orbit tangent + parade), never tumble.
	var tumble: bool = false
	if light_orbit:
		## Radius filled in after titan AABB measure; until then use a safe stand-in.
		var orb: Dictionary = {
			"holder": holder,
			"race_i": race_i,
			"phase0": rng.randf() * TAU,
			## Desired rad/s before the 2×-parade tangential cap is applied each frame.
			"omega_want": rng.randf_range(0.1375, 0.2375),
			"r_extra": rng.randf_range(0.15, LIGHT_ORBIT_MARGIN),
			"z": rng.randf_range(-1.0, 1.0), ## rewritten once titan length is known
		}
		_orbiters.append(orb)
		holder.position = Vector3(8.0, 0.0, 0.0)
	elif review_capital:
		## One unmistakable seat per capital class. Race-dependent sign changes prevent
		## four finale fleets from becoming identical stamps while preserving separation.
		var seat_v: Variant = CAPITAL_REVIEW_POS.get(group, Vector3.ZERO)
		var seat: Vector3 = seat_v if seat_v is Vector3 else Vector3.ZERO
		if race_i % 2 == 1:
			seat.x *= -1.0
		holder.position = seat
	else:
		## Deterministic golden-angle scatter + wide height so capitals don't pancake.
		var ang: float = float(slot_i) * 2.399963 + rng.randf_range(-0.35, 0.35)
		var rad: float = lerpf(FLEET_RING_MIN, FLEET_RING_MAX, rng.randf())
		var y: float = rng.randf_range(FLEET_Y_CAPITAL.x, FLEET_Y_CAPITAL.y)
		holder.position = Vector3(cos(ang) * rad, y, sin(ang) * rad)
	## All bows share parade heading (parent +Z after unit BOW_YAW)
	holder.rotation = Vector3.ZERO

	var tumble_node: Node3D = Node3D.new()
	tumble_node.name = "Tumble"
	holder.add_child(tumble_node)

	var unit: ShipUnit = ShipUnit.new()
	tumble_node.add_child(unit)
	unit.setup(sid, 1, ShipUnit.TEAM_PLAYER)
	if unit.has_method("clear_health_bar"):
		unit.clear_health_bar()
	unit.slot_type = ""
	unit.rotation.y = _bow_yaw_for(unit, model_key)
	_attach_trail(unit, group, race_i, model_key)

	if tumble:
		## Roll/pitch about forward (+Z) so bow queue stays neat while the ring carries them.
		_tumblers.append({
			"node": tumble_node,
			"axis": Vector3(rng.randf_range(0.15, 0.45), 0.0, 1.0).normalized(),
			"speed": rng.randf_range(0.45, 0.85),
		})

	return {
		"holder": holder, "unit": unit, "model_key": model_key,
		"group": group, "label": str(ship.get("name", model_key)),
		"capital": capital, "review_capital": review_capital,
		"tumble": tumble, "light_orbit": light_orbit,
	}


func _attach_trail(unit: Node3D, group: String, race_i: int, model_key: String) -> void:
	if unit == null:
		return
	var trail: EngineBoosterTrail = EngineBoosterTrail.ensure_on(unit, true)
	if trail == null:
		return
	## Ribbon is the match/CG default (`booster_trail_mesh_style`); keep explicit for CG fleets.
	trail.set_mesh_style(EngineBoosterTrail.STYLE_RIBBON)
	var profile: Dictionary = _trail_profile(group)
	trail.configure_profile(
		TypedVariant.as_float(profile.get("lifetime", 0.0), 0.0), TypedVariant.as_int(profile.get("segments", 0), 0), TypedVariant.as_float(profile.get("idle", 0.0), 0.0), TypedVariant.as_float(profile.get("stamp", 0.0), 0.0)
	)
	EngineBoosterTrail.set_emitting_on(unit, false)
	_trail_units.append({
		"unit": unit, "race_i": race_i, "group": group, "trail": trail, "model_key": model_key,
	})


func _align_trail_nozzles() -> void:
	## Nozzle positions stay what ShipUnit resolved from engine_boosters.json (SOF).
	## TQ hulls are modelled back-to-front, so their booster cloud maps onto the bow and
	## has to be Z-mirrored. Ribbon style only needs centers + SOF radii from the outlines.
	for item: Dictionary in _trail_units:
		var unit_v: Variant = item.get("unit")
		var unit: Node3D = null
		if unit_v is Node3D:
			unit = unit_v
		var trail_v: Variant = item.get("trail")
		var trail: EngineBoosterTrail = null
		if trail_v is EngineBoosterTrail:
			trail = trail_v
		if unit == null or not is_instance_valid(unit) or trail == null:
			continue
		trail.set_rebuild_interval(TRAIL_REBUILD_S)
		if not unit.has_method("get_engine_locals"):
			continue
		var locals: Array[Vector3] = unit.call("get_engine_locals")
		var outlines: Array = unit.call("get_engine_outlines")
		if locals.is_empty() or outlines.size() < locals.size():
			continue
		var hull: AABB = _approx_aabb(unit)
		if hull.size.z < 0.05:
			continue
		var hull_center_local: Vector3 = unit.to_local(hull.get_center())
		var mean_world: Vector3 = Vector3.ZERO
		for p: Vector3 in locals:
			mean_world += unit.to_global(p)
		mean_world /= float(locals.size())
		## Baked packs solved their nozzles against the mesh itself, so the cloud is already
		## astern; the world-space test below would still flip them, because it reads the
		## unyawed hulls the other way round. Trust the measurement.
		var baked: bool = unit.has_method("has_baked_bow_fit") and unit.call("has_baked_bow_fit")
		if not baked and mean_world.z < hull.get_center().z:
			locals = _mirror_z(locals, hull_center_local.z)
			var flipped: Array = []
			for ring_v: Variant in outlines:
				if ring_v is PackedVector3Array:
					var ring: PackedVector3Array = ring_v
					flipped.append(_mirror_z_ring(ring, hull_center_local.z))
			outlines = flipped
		var astern_local: Vector3 = unit.global_transform.basis.inverse() * Vector3(0, 0, 1)
		trail.configure_nozzles(locals, outlines, astern_local)
		if str(item["group"]) in ["titan", "freighter", "supercarrier"]:
			print("[CgOpeningDirector] trail %s nozzles=%d style=ribbon baked=%s mirrored=%s" % [
				str(item["model_key"]), locals.size(), str(baked),
				str(not baked and mean_world.z < hull.get_center().z)
			])


func _mirror_z(points: Array[Vector3], pivot_z: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in points:
		out.append(Vector3(p.x, p.y, 2.0 * pivot_z - p.z))
	return out


func _mirror_z_ring(ring: PackedVector3Array, pivot_z: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in ring:
		out.append(Vector3(p.x, p.y, 2.0 * pivot_z - p.z))
	return out


func _set_trails_emitting(on: bool) -> void:
	## Legacy helper: every hull that currently processes may plume.
	_set_trails_emitting_policy(-1, -1, on, on)


func _set_trails_emitting_policy(
	active_race: int,
	warming_race: int,
	capitals_default_on: bool = false,
	include_lights: bool = false
) -> void:
	## Lights emit only while on-screen (or when include_lights forces a full tableau).
	## Capitals/titans may pre-warm on the next race.
	## GDScript hollow-tube rebuilds are the showcase hitch — keep warm load to capitals.
	for item: Dictionary in _trail_units:
		var u_v: Variant = item.get("unit")
		var u: Node3D = u_v if u_v is Node3D else null
		var trail_v: Variant = item.get("trail")
		var trail: EngineBoosterTrail = null
		if trail_v is EngineBoosterTrail:
			trail = trail_v
		if u == null or not is_instance_valid(u):
			continue
		var group: String = str(item["group"])
		var light: bool = group in ["frigate", "destroyer"]
		var race_i: int = TypedVariant.as_int(item.get("race_i", 0), 0)
		var on: bool = false
		if light:
			on = include_lights or (race_i == active_race and active_race >= 0)
		else:
			on = capitals_default_on or race_i == active_race or race_i == warming_race
		EngineBoosterTrail.set_emitting_on(u, on)
		if trail != null:
			var rebuild: float = TRAIL_REBUILD_S if race_i == active_race or include_lights else TRAIL_REBUILD_WARM_S
			trail.set_rebuild_interval(rebuild)


func _trail_profile(group: String) -> Dictionary:
	## 2.0 s fade with enough samples to avoid chunky steps, without the 30-seg SurfaceTool
	## rebuild that was hitching the showcase (GDScript tube meshing dominates the frame).
	match group:
		"titan":
			return {"lifetime": 2.0, "segments": 14, "stamp": 0.16, "idle": 6.0}
		"supercarrier", "carrier", "dreadnought", "fax", "freighter":
			return {"lifetime": 2.0, "segments": 12, "stamp": 0.17, "idle": 4.5}
		"battleship", "battlecruiser":
			return {"lifetime": 2.0, "segments": 12, "stamp": 0.17, "idle": 3.5}
		"cruiser", "industrial":
			return {"lifetime": 2.0, "segments": 10, "stamp": 0.18, "idle": 2.8}
		"destroyer":
			return {"lifetime": 2.0, "segments": 8, "stamp": 0.20, "idle": 1.6}
		"frigate":
			return {"lifetime": 2.0, "segments": 8, "stamp": 0.20, "idle": 1.2}
		_:
			return {"lifetime": 2.0, "segments": 10, "stamp": 0.18, "idle": 2.4}


func _bow_yaw_for(unit: Node3D, model_key: String) -> float:
	## A pack with a baked bow_fit already points its bow at local -Z, so any extra flip
	## would sail it stern-first. The `tq_` flip is only a stand-in for the hulls whose
	## heading was never measured, and it is wrong per hull (the four freighters solve to
	## 90/180/270 — see tools/fit_bow_yaw_from_nozzles.py).
	if unit != null and unit.has_method("has_baked_bow_fit") and unit.call("has_baked_bow_fit"):
		return BOW_YAW_ECHOES
	return BOW_YAW_TQ if model_key.begins_with("tq_") else BOW_YAW_ECHOES


func _orient_bow_forward() -> void:
	## Last-resort guard for TQ hulls only: if one still measures clearly longer on X than on
	## Z, auto-orient never laid it onto Z and it would travel broadside — quarter-turn it like
	## TitanBerth does. Echoes hulls are excluded: wide wings legitimately beat hull length.
	for item: Dictionary in _trail_units:
		var unit_v: Variant = item.get("unit")
		var unit: Node3D = null
		if unit_v is Node3D:
			unit = unit_v
		var model_key: String = str(item["model_key"])
		if unit == null or not is_instance_valid(unit) or not model_key.begins_with("tq_"):
			continue
		var box: AABB = _approx_aabb(unit)
		if box.size.x > box.size.z * 1.25:
			unit.rotation.y += PI * 0.5
			push_warning("CgOpeningDirector: %s was length-on-X, forced quarter turn" % model_key)


func _normalize_all() -> void:
	## ShipUnit.setup already applied display = target * (axis/ref)^power with CG max_mul.
	## Do NOT re-bucket to fixed 14/5.5/2.2 — that wiped relative tonnage.
	await get_tree().process_frame
	await get_tree().process_frame
	_orient_bow_forward()
	_enforce_titan_curve_sizes()
	_spread_fleets_after_titan_scale()
	_log_display_sizes()
	_measure_titan_orbit_radii()
	_measure_race_cluster_radii()


func _measure_race_cluster_radii() -> void:
	## Showcase framing has to follow the real fleet extent. After the spread passes the
	## authored constant no longer covers the cloud and the outer hulls fall off frame.
	_race_cluster_radius.clear()
	for i: int in _race_roots.size():
		var entry: Dictionary = _race_roots[i]
		var radius: float = _titan_orbit_radius[i] if i < _titan_orbit_radius.size() else 8.0
		radius = maxf(radius, _light_orbit_reach(i))
		for f_v: Variant in TypedVariant.as_array(entry.get("fleet", [])):
			if not f_v is Dictionary:
				continue
			var f: Dictionary = f_v
			if TypedVariant.as_bool(f.get("light_orbit", false), false):
				continue
			var holder_v: Variant = f.get("holder")
			var holder: Node3D = holder_v if holder_v is Node3D else null
			if holder == null or not is_instance_valid(holder):
				continue
			var unit_v: Variant = f.get("unit")
			var unit: Node3D = null
			if unit_v is Node3D:
				unit = unit_v
			var hull_half: float = 0.0
			if unit != null and is_instance_valid(unit):
				hull_half = _approx_longest_world(unit) * 0.5
			radius = maxf(radius, holder.position.length() + hull_half)
		_race_cluster_radius.append(radius)
		print("[CgOpeningDirector] race %d cluster radius=%.2f → cam distance %.1f (floor %.1f)" % [
			i, radius, _showcase_cam_distance(i), SHOWCASE_CAM_DISTANCE
		])


func _light_orbit_reach(race_i: int) -> float:
	var base_r: float = _titan_orbit_radius[race_i] if race_i < _titan_orbit_radius.size() else 8.0
	var reach: float = 0.0
	for item: Dictionary in _orbiters:
		if TypedVariant.as_int(item.get("race_i", 0), 0) != race_i:
			continue
		reach = maxf(reach, (base_r + TypedVariant.as_float(item.get("r_extra", 0.0), 0.0)) * LIGHT_ORBIT_RADIUS_MUL)
	return reach


func _showcase_cam_distance(race_i: int) -> float:
	## Godot fov is vertical, so the cluster sphere must fit inside tan(fov/2) * distance.
	if _cam == null or race_i < 0 or race_i >= _race_cluster_radius.size():
		return SHOWCASE_CAM_DISTANCE
	var half_fov_tan: float = tan(deg_to_rad(_cam.fov) * 0.5)
	var needed: float = TypedVariant.as_float(_race_cluster_radius[race_i], 0.0) / maxf(half_fov_tan, 0.01) * SHOWCASE_FRAME_MARGIN
	return maxf(SHOWCASE_CAM_DISTANCE, needed)


func _enforce_titan_curve_sizes() -> void:
	## ShipUnit owns the curve calculation. Verify it against the rendered AABB and apply any
	## missing ratio to the complete unit (mesh + nozzles) so a later model transform cannot
	## visually cancel the titan's long-axis scale.
	for entry: Dictionary in _race_roots:
		var titan_v: Variant = entry.get("titan")
		var titan: Node3D = titan_v if titan_v is Node3D else null
		if titan == null or not is_instance_valid(titan) or not titan.has_method("get_model_display_size"):
			continue
		var wanted: float = TypedVariant.as_float(titan.call("get_model_display_size"), 0.0)
		var before: float = _approx_longest_world(titan)
		if wanted <= 0.0 or before <= 0.05:
			continue
		var correction: float = clampf(wanted / before, 0.25, 4.0)
		titan.scale *= correction
		var after: float = _approx_longest_world(titan)
		print("[CgOpeningDirector] titan curve enforced %s axis=%.0f wanted=%.2f actual %.2f→%.2f" % [
			str(TypedVariant.as_dict(entry.get("def", {})).get("model_key", "?")),
			TypedVariant.as_float(
				DataStore.get_ship(TypedVariant.as_int(TypedVariant.as_dict(entry.get("def", {})).get("id", 0), 0)).get("model_long_axis", 0.0),
				0.0
			),
			wanted, before, after
		])


func _spread_fleets_after_titan_scale() -> void:
	## Preserve the authored arrangement, only loosen it enough to clear the enlarged hull.
	for entry: Dictionary in _race_roots:
		for f_v: Variant in TypedVariant.as_array(entry.get("fleet", [])):
			if not f_v is Dictionary:
				continue
			var f: Dictionary = f_v
			if TypedVariant.as_bool(f.get("light_orbit", false), false) or TypedVariant.as_bool(f.get("review_capital", false), false):
				continue
			var holder_v: Variant = f.get("holder")
			var holder: Node3D = holder_v if holder_v is Node3D else null
			if holder == null or not is_instance_valid(holder):
				continue
			holder.position = Vector3(
				holder.position.x * CG_FLEET_SPREAD_MUL,
				holder.position.y * lerpf(1.0, CG_FLEET_SPREAD_MUL, 0.55),
				holder.position.z * CG_FLEET_SPREAD_MUL
			)


func _log_display_sizes() -> void:
	for entry: Dictionary in _race_roots:
		var titan_v: Variant = entry.get("titan")
		var titan: Node3D = null
		if titan_v is Node3D:
			titan = titan_v
		if titan != null and titan.has_method("get_model_display_size"):
			print("[CgOpeningDirector] %s display=%.2f actual=%.2f wu (curve)" % [
				str(TypedVariant.as_dict(entry.get("def", {})).get("model_key", "?")),
				TypedVariant.as_float(titan.call("get_model_display_size"), 0.0),
				_approx_longest_world(titan)
			])
		for f_v: Variant in TypedVariant.as_array(entry.get("fleet", [])):
			if not f_v is Dictionary:
				continue
			var f: Dictionary = f_v
			var u_v: Variant = f.get("unit")
			var u: Node3D = u_v if u_v is Node3D else null
			if (
				u != null
				and u.has_method("get_model_display_size")
				and TypedVariant.as_bool(f.get("review_capital", false), false)
			):
				var holder_v: Variant = f.get("holder")
				var holder: Node3D = holder_v if holder_v is Node3D else null
				var label: String = "大航" if str(f.get("group")) == "supercarrier" else str(f.get("group"))
				print("[CgOpeningDirector] capital %s/%s display=%.2f actual=%.2f pos=%s" % [
					label, str(f.get("model_key")),
					TypedVariant.as_float(u.call("get_model_display_size"), 0.0), _approx_longest_world(u),
					str(holder.position if holder != null else Vector3.ZERO),
				])


func _measure_titan_orbit_radii() -> void:
	## Bounding sphere of the display-scaled titan; light craft hug this shell.
	_titan_orbit_radius.clear()
	for i: int in _race_roots.size():
		var entry: Dictionary = _race_roots[i]
		var titan_holder_v: Variant = entry.get("titan_holder")
		if not titan_holder_v is Node3D:
			continue
		var titan_holder: Node3D = titan_holder_v
		var box: AABB = _approx_aabb(titan_holder)
		var half: Vector3 = box.size * 0.5
		var radius: float = maxf(0.75, half.length())
		_titan_orbit_radius.append(radius)
		var half_z: float = maxf(box.size.z * 0.5 * LIGHT_ORBIT_Z_FRAC, 0.4)
		for item: Dictionary in _orbiters:
			if TypedVariant.as_int(item.get("race_i", 0), 0) != i:
				continue
			## Keep Z near the midship so the ring reads as "around the hull", not a long tube.
			var rng_z: RandomNumberGenerator = RandomNumberGenerator.new()
			rng_z.seed = hash("orbz_%d_%s" % [i, str(item.get("holder"))])
			item["z"] = rng_z.randf_range(-half_z, half_z)
		print("[CgOpeningDirector] race %d titan orbit radius=%.2f" % [i, radius])


func _normalize_node(node: Node3D, display_longest: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var longest: float = _approx_longest_world(node)
	if longest < 0.05:
		return
	var mul: float = clampf(display_longest / longest, 0.02, 6.0)
	node.scale = node.scale * mul


func _spin_tumblers(delta: float) -> void:
	for item: Dictionary in _tumblers:
		var n_v: Variant = item.get("node")
		var n: Node3D = n_v if n_v is Node3D else null
		if n == null or not is_instance_valid(n):
			continue
		if not n.is_visible_in_tree():
			continue
		var axis: Vector3 = item["axis"]
		var speed: float = item["speed"]
		n.rotate_object_local(axis, speed * delta)


func _approx_longest_world(node: Node3D) -> float:
	var box: AABB = _approx_aabb(node)
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


func _approx_aabb(node: Node3D) -> AABB:
	var acc: AABB = AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "VisualInstance3D", true, false):
		if child is VisualInstance3D:
			var vi: VisualInstance3D = child
			var ab: AABB = vi.get_aabb()
			var xf: Transform3D = vi.global_transform
			var corners: Array[Vector3] = [
				xf * ab.position,
				xf * (ab.position + Vector3(ab.size.x, 0, 0)),
				xf * (ab.position + Vector3(0, ab.size.y, 0)),
				xf * (ab.position + Vector3(0, 0, ab.size.z)),
				xf * (ab.position + ab.size),
			]
			for c: Vector3 in corners:
				if first:
					acc = AABB(c, Vector3.ZERO)
					first = false
				else:
					acc = acc.expand(c)
	return acc


func _update_camera_free(delta: float) -> void:
	if _cam == null:
		return
	var speed: float = 28.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 2.5
	var cam_basis: Basis = _cam.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x
	var move: Vector3 = Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move += forward
	if Input.is_physical_key_pressed(KEY_S):
		move -= forward
	if Input.is_physical_key_pressed(KEY_A):
		move -= right
	if Input.is_physical_key_pressed(KEY_D):
		move += right
	if Input.is_physical_key_pressed(KEY_Q):
		move -= Vector3.UP
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if move != Vector3.ZERO:
		_cam_base_pos += move.normalized() * speed * delta
	if Input.is_physical_key_pressed(KEY_R):
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + 48.0 * delta, -89.0, 89.0)
	if Input.is_physical_key_pressed(KEY_F):
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg - 48.0 * delta, -89.0, 89.0)
	if Input.is_physical_key_pressed(KEY_T):
		_cam_base_yaw_deg -= 56.0 * delta
	if Input.is_physical_key_pressed(KEY_G):
		_cam_base_yaw_deg += 56.0 * delta
	_apply_cam()


func _capture() -> void:
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir: String = "user://cg_captures"
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = "%s/cg_%05d_t%.1f.png" % [dir, Time.get_ticks_msec() % 100000, _t]
	img.save_png(path)
	print("[CgOpeningDirector] captured ", path)
