extends Node3D
class_name MatchRoot
## Wires bricks; group name match_root for callbacks.

@onready var world: Node3D = $World
@onready var camera: Camera3D = $Camera3D
@onready var hud: CanvasLayer = $HUD

var match_ctrl: MatchController
var board: BoardController
var shop: ShopController
var combat: CombatResolver
var firing_fx = null
var ai: AiController
var pointer: PointerInput
var _nullsec_speed: RoundSpeedController
var _speed_dropdown: SpeedDropdownMenu
var _nullsec_pve: NullsecPveDirector
var _nullsec_rng: MatchRng
var _doomsday_resolver: TitanDoomsdayResolver
var _settlement_panel: NullsecSettlementPanel

var _info_ship: ShipUnit = null
var _suppress_headup_for_preview: bool = false
## UI_AND_SHELL §2.5: tap / drag-release pins the detail panel for INFO_HOLD_S.
var _info_hold_until_ms: int = 0
var _drag_info_ship: ShipUnit = null
var _ship_data_editor: ShipDataEditor = null
var _long_press_t: float = 0.0
var _long_press_slot: int = -1
var _shop_drag_idx: int = -1
var _shop_drag_active: bool = false
var _shop_press_screen: Vector2 = Vector2.ZERO
var _shop_long_previewed: bool = false
var _shop_ghost: Control = null
const _SHOP_DRAG_THRESHOLD_PX := 28.0
const _SHOP_BUY_TIP := "拖动到备战席来完成购买"
var _dragging_sell_ui: bool = false
var _cam_base_pos: Vector3 = Vector3.ZERO
var _cam_default_pitch_deg: float = -55.0
var _cam_base_pitch_deg: float = -55.0
var _cam_base_yaw_deg: float = 0.0
var _cam_frame_offset: Vector3 = Vector3.ZERO
var _cam_frame_target: Vector3 = Vector3.ZERO
var _cam_headup_offset_deg: float = 0.0
var _cam_headup_phase: int = 0
var _cam_headup_t: float = 0.0
## Smooth blend toward a default view (shop / stage); false = settled.
var _cam_view_blend_active: bool = false
var _cam_view_blend_pos: Vector3 = Vector3.ZERO
var _cam_view_blend_pitch_deg: float = 0.0
var _cam_view_blend_yaw_deg: float = 0.0
var _cam_view_blend_fov: float = 50.0
## Camera mode: false = default (framing/breathe/headup); true = free view.
var _camera_free: bool = false
## Third camera state: orbit a selected world unit (UI_AND_SHELL §2.3.1). Mutually exclusive with free.
var _camera_observe: bool = false
var _observe_ship: ShipUnit = null
var _observe_dist: float = 14.0
var _observe_yaw: float = 0.0 ## world radians around +Y
var _observe_elev: float = 0.35 ## world elevation from XZ plane (radians)
var _observe_dist_min: float = 2.0
var _observe_dist_max: float = 80.0
var _observe_btn: Button = null
## Observe pinch (two-finger zoom); FOV never changes.
var _observe_pinch_ids: Array[int] = []
var _observe_pinch_last_dist: float = 0.0
var _observe_touch_pos: Dictionary = {} ## index -> Vector2
var _cam_look_dragging: bool = false
## Pose snapshot taken when expanding shop; restored when collapsing.
var _cam_pose_before_shop: Dictionary = {}
var _cam_pose_before_shop_valid: bool = false
## Mobile free-view orbit drag.
var _cam_orbit_touch_index: int = -1
var _cam_orbit_dragging: bool = false
## Default cam: hide board slot markers only after settling on first default view.
var _pending_hide_slot_markers: bool = false
var _collapse_left: bool = false
var _collapse_right: bool = false
var _collapse_bottom: bool = false
## In-match Esc/菜单 overlay (versus + endless).
var _game_menu: Control
var _game_menu_settings: Control
var _game_menu_save: Control
var _game_menu_dev: Control
var _save_name_edit: LineEdit
var _menu_opened_pause: bool = false
var _fps_slider: HSlider
var _fps_lbl: Label
var _bgm_check: CheckBox
var _bgm_slider: HSlider
var _bgm_lbl: Label
var _dev_master_check: CheckBox
var _dev_soften_check: CheckBox
var _dev_economy_check: CheckBox
var _dev_enemy_layout_check: CheckBox
var _last_match_stage: int = MatchController.Stage.PREPARE
var _battle_log_lines: Array = []
const _BATTLE_LOG_MAX := 40
var _citadel_hp_bar: Node3D = null
const _CITADEL_BAR_SCRIPT := preload("res://scripts/ship/citadel_health_bar.gd")
## Nullsec: seat titan berth replaces the citadel (MULTIPLAYER_PVP §2.4a).
var _titan_berth: TitanBerth = null
var _rival_titan_berth: TitanBerth = null
var _titan_hp_bar: Node3D = null
const _TITAN_BAR_SCRIPT := preload("res://scripts/ship/titan_hp_bar.gd")
const _TitanKillSequence := preload("res://scripts/match/titan_kill_sequence.gd")
## Fetter that marks a hull as an exploration ship (data/fetters/exploration.json).
const EXPLORE_FETTER_ID := "exploration"
const SCOUT_GATE_HINT := "刺探需备战席/场上有探索护卫（富豪级·苍鹭级·探索级·伊米卡斯级）"
## Titan kill shake: wall-clock end (ms). 0 = inactive.
var _titan_shake_until_ms: int = 0
## True while §2.6 kill sequence blocks settlement / next prepare.
var _titan_kill_busy: bool = false
## Concurrent kill sequences (both titans can pop on a mutual doomsday).
var _titan_kill_active: int = 0
## True while the doomsday beam still plays; gates the round flip like the kill does.
var _doomsday_busy: bool = false
## Live DoomsdayFx nodes still running (draw can spawn two).
var _doomsday_fx_left: int = 0
## Wall-clock earliest release for the doomsday gate (ms).
var _doomsday_hold_until_ms: int = 0
## Next-round entry deferred by a running kill sequence / doomsday beam.
var _nullsec_prepare_pending: bool = false
## Prepare HUD/camera held back until doomsday / kill finish.
var _nullsec_prepare_ui_pending: bool = false
## This PVP round fights as guest (rival skybox). Decided at prepare; teleport at battle.
var _nullsec_pvp_guest: bool = false
## One-shot nullsec open intro (head-down + slide-in).
var _titan_intro_done: bool = false
var _titan_intro_t: float = -1.0
var _titan_intro_start: Vector3 = Vector3.ZERO
var _titan_intro_end: Vector3 = Vector3.ZERO
var _titan_intro_pitch0: float = 0.0
## Shared read-only spectate (seat_spectate / mid_join / eliminated).
var _nullsec_spectating: bool = false
var _nullsec_spectate_reason: String = ""
var _nullsec_watch_seat: int = -1
var _spectate_leave_btn: Button = null
const _BgMusic := preload("res://scripts/audio/bg_music.gd")
const _CapitalJumpFx := preload("res://scripts/combat/capital_jump_fx.gd")
const _CAM_MOVE_SPEED := 8.0
var _exp_hold_active: bool = false
var _exp_hold_t: float = 0.0
var _exp_hold_repeat_t: float = 0.0
var _exp_hold_repeating: bool = false
## ECONOMY_AND_SHOP §3 / UI_AND_SHELL §2.5 — hold delay then interval buys.
const _EXP_HOLD_DELAY_S := 0.5
const _EXP_HOLD_INTERVAL_S := 0.05
const _CAM_PITCH_SPEED := 35.0
const _CAM_YAW_SPEED := 45.0
const _SHOP_META := "Shop/ShopCol/ShopContent/MetaRow"
const _SHOP_LEFT := "Shop/ShopCol/ShopContent/MetaRow/LeftCtrl"
const _SHOP_MID := "Shop/ShopCol/ShopContent/MetaRow/MetaMid"
const _SHOP_INNER := "Shop/ShopCol/ShopContent/ShopInner"
const _SHOP_SLOTS := "Shop/ShopCol/ShopContent/ShopInner/ShopSlots"
const _INFO_PANEL := "RightCol/RightInner/RightContent/InfoPanel"
const _BONUS := "LeftCol/LeftInner/LeftContent/BonusContainer"
const _ROUND := "RoundBar/RoundInner"
## Detail panel stays up this long after a tap / drag release (UI_AND_SHELL §2.5).
const INFO_HOLD_S := 10.0

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	add_to_group("match_root")
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Pick up balance/visual JSON edits without restarting the editor.
	DataStore.reload_all()
	_BgMusic.instance()
	match_ctrl = MatchController.new()
	board = BoardController.new()
	shop = ShopController.new()
	combat = CombatResolver.new()
	firing_fx = preload("res://scripts/combat/firing_fx.gd").new()
	ai = AiController.new()
	pointer = PointerInput.new()
	add_child(match_ctrl)
	add_child(board)
	add_child(shop)
	add_child(combat)
	add_child(firing_fx)
	add_child(ai)
	add_child(pointer)
	match_ctrl.process_mode = Node.PROCESS_MODE_PAUSABLE
	board.process_mode = Node.PROCESS_MODE_ALWAYS
	shop.process_mode = Node.PROCESS_MODE_PAUSABLE
	combat.process_mode = Node.PROCESS_MODE_PAUSABLE
	firing_fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	ai.process_mode = Node.PROCESS_MODE_PAUSABLE
	pointer.process_mode = Node.PROCESS_MODE_ALWAYS
	## Esc / 菜单 while tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	board.setup(world)
	_ensure_ground()
	shop.bind(match_ctrl, board)
	firing_fx.setup(world)
	combat.bind(board, firing_fx)
	ai.bind(match_ctrl, board)
	match_ctrl.bind(board, shop, combat, ai)
	_setup_camera()
	_build_hud()
	pointer.setup(self, camera, board)
	pointer.drag_begin.connect(_on_drag_begin)
	pointer.drag_move.connect(_on_drag_move)
	pointer.drag_end.connect(_on_drag_end)
	pointer.tap_ship.connect(_on_tap_ship)
	pointer.hover_ship.connect(_on_hover_ship)
	match_ctrl.hud_refresh.connect(_refresh_hud)
	match_ctrl.notice.connect(show_notice)
	match_ctrl.match_over.connect(_on_match_over)
	match_ctrl.stage_changed.connect(_on_stage_changed_ui)
	shop.shop_changed.connect(_refresh_shop_ui)
	var net_sess := _nullsec_net_session()
	if net_sess and not net_sess.ships_override_applied.is_connected(_on_host_ships_applied):
		net_sess.ships_override_applied.connect(_on_host_ships_applied)
	var diag := SessionDiagnostics.instance()
	if diag and diag.has_method("bind_match"):
		diag.bind_match(self)
	var mode := GameSession.pending_mode
	_spawn_map_env(mode)
	var resume_data: Dictionary = {}
	if GameSession.resume_save:
		## One-shot payload from 读取存档→旗舰测试 inject only.
		if not GameSession.resume_payload.is_empty():
			resume_data = GameSession.resume_payload
		else:
			var slot_id := str(GameSession.resume_slot_id)
			if slot_id != "":
				resume_data = MatchSave.load_slot_dict(slot_id)
			if resume_data.is_empty():
				resume_data = MatchSave.load_dict()
		GameSession.resume_payload = {}
	match_ctrl.start_match(mode)
	if mode == "nullsec":
		_setup_nullsec_runtime()
	if not resume_data.is_empty():
		_apply_match_save_dict(resume_data)
		GameSession.resume_save = false
		GameSession.resume_slot_id = ""
		MatchSave.save_from_match(match_ctrl, board, ai)
	_refresh_hud()
	_refresh_shop_ui()

func _setup_nullsec_runtime() -> void:
	var payload: Dictionary = GameSession.pending_nullsec
	_nullsec_rng = MatchRng.new()
	_nullsec_rng.configure(int(payload.get("match_seed", Time.get_unix_time_from_system())), MatchRng.compute_rules_hash())
	_nullsec_speed = RoundSpeedController.new()
	_nullsec_speed.speed_changed.connect(_on_nullsec_speed_changed)
	_nullsec_speed.force_draw_remaining.connect(_on_nullsec_force_draw)
	_nullsec_pve = NullsecPveDirector.new()
	_nullsec_pve.setup(_nullsec_rng, 1)
	_nullsec_pve.pick_task(1)
	## Lock R1 creeps from starting gold/level.
	var gold := int(match_ctrl.player_gold) if match_ctrl else 0
	var level := int(match_ctrl.player_level) if match_ctrl else 1
	var pop := 0
	if match_ctrl and match_ctrl.has_method("population_limit"):
		pop = int(match_ctrl.population_limit())
	else:
		pop = level + 1
	_nullsec_pve.lock_creeps(gold, level, maxi(1, pop))
	## Seat economy for the AI players starts with the humans' opening, then banks
	## gold/exp every round so a later PVP rival is not a level-1 fleet.
	if ai and ai.has_method("init_economy"):
		ai.init_economy()
	## Titan buff rides the fetter rail (MULTIPLAYER_PVP §2.3): always on from setup.
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())
	if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
		_nullsec_pve.pick_freighter_id(_local_titan_race_for_ui())
	_doomsday_resolver = TitanDoomsdayResolver.new()
	if not _doomsday_resolver.return_home_due.is_connected(_on_titan_return_home):
		_doomsday_resolver.return_home_due.connect(_on_titan_return_home)
	var seats: Array = payload.get("seats", []) as Array
	for s in seats:
		var race := str(s.get("titan_race", "caldari"))
		if not NullsecNetSession.is_player_race(race):
			continue
		_doomsday_resolver.ensure_seat(int(s.get("seat_id", 0)), race)
	_refresh_titan_hp_bar()
	_TitanKillSequence.ensure_wreck_ship_defs()
	_speed_dropdown = SpeedDropdownMenu.new()
	_speed_dropdown.controller = _nullsec_speed
	_speed_dropdown.local_nick = "本地"
	hud.add_child(_speed_dropdown)
	_speed_dropdown.vote_changed.connect(func(spd: float):
		show_notice("有人发起对局速度调整 → %s" % SpeedDropdownMenu._label(spd))
		_apply_resolved_speed()
	)
	_settlement_panel = NullsecSettlementPanel.new()
	hud.add_child(_settlement_panel)
	_wire_nullsec_scout()
	var want_spec := bool(payload.get("spectator", false))
	if want_spec:
		enter_nullsec_spectate(str(payload.get("spectate_reason", "seat_spectate")))
	else:
		show_notice("负安局 · %s · 星域已分配" % _nullsec_pve.current_task)
		call_deferred("_nullsec_on_prepare_begin")
		call_deferred("_play_titan_berth_intro")

func enter_nullsec_spectate(reason: String = "seat_spectate") -> void:
	## Shared path: lobby「仅观战」/ mid-join / titan eliminated early-out.
	_nullsec_spectating = true
	_nullsec_spectate_reason = reason
	_titan_intro_done = true
	_nullsec_prepare_pending = false
	_nullsec_prepare_ui_pending = false
	_apply_nullsec_spectate_hud()
	_wire_nullsec_scout()
	var first := _first_player_seat_id()
	if first >= 0:
		_switch_watch_seat(first)
	var label := "观战"
	if reason == "eliminated":
		label = "已淘汰 · 观战"
	elif reason == "mid_join":
		label = "中途观战"
	show_notice("%s · 可自由切换视角" % label)

func _first_player_seat_id() -> int:
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s in seats:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if not bool(s.get("occupied", false)):
			continue
		if NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			return int(s.get("seat_id", 0))
	return -1

func _apply_nullsec_spectate_hud() -> void:
	var root := hud.get_node_or_null("Root") as Control
	if root:
		var shop_panel := root.get_node_or_null("Shop") as Control
		if shop_panel:
			shop_panel.visible = false
		var right := root.get_node_or_null("RightCol") as Control
		if right:
			right.modulate.a = 0.35
			right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _speed_dropdown:
		_speed_dropdown.visible = true
	_ensure_spectate_leave_btn()
	var scout := hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if scout:
		scout.visible = true
		scout.text = "切换视角"

func _ensure_spectate_leave_btn() -> void:
	var top_r := hud.get_node_or_null("Root/TopRight") as Control
	if top_r == null:
		return
	if _spectate_leave_btn and is_instance_valid(_spectate_leave_btn):
		_spectate_leave_btn.visible = true
		return
	_spectate_leave_btn = Button.new()
	_spectate_leave_btn.name = "SpectateLeaveBtn"
	_spectate_leave_btn.text = "离开观战"
	_spectate_leave_btn.pressed.connect(_on_spectate_leave)
	top_r.add_child(_spectate_leave_btn)

func _on_spectate_leave() -> void:
	if _nullsec_spectate_reason == "eliminated":
		## Nominal leave: mark ghost then return to menu.
		var net := GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession
		if net:
			net.request_mark_local_ghost()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	## Pure spectator seat: disconnect and leave.
	var net2 := GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession
	if net2:
		net2.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

## Single view switch for both spectate (§4.4) and scout (§4.2.1) — no second camera path.
func _switch_watch_seat(seat_id: int, notice: String = "") -> void:
	_nullsec_watch_seat = seat_id
	var region := _seat_region(seat_id)
	if region != "":
		apply_region_skybox(region)
	_refresh_region_label()
	show_notice(notice if notice != "" else "视角 → 席位 %d" % (seat_id + 1))

func _seat_region(seat_id: int) -> String:
	var asg: Dictionary = GameSession.pending_nullsec.get("assignments", {})
	return str(asg.get(str(seat_id), asg.get(seat_id, "")))

## Title bar carries the region being watched, so a scout hop is readable even
## when both seats sit under a similar nebula (MULTIPLAYER_PVP §4.2.1).
func _refresh_region_label() -> void:
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	var lbl := root.get_node_or_null("%s/Region" % _ROUND) as Label
	if lbl == null:
		return
	if GameSession.pending_mode != "nullsec":
		lbl.visible = false
		return
	lbl.visible = true
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", -1))
	var seat := _nullsec_watch_seat if _nullsec_watch_seat >= 0 else local_seat
	var region := _seat_region(seat)
	if region == "":
		lbl.text = "星域 —"
		return
	var region_name := SkyboxCatalog.display_name(region)
	if seat == local_seat and not _nullsec_spectating:
		lbl.text = region_name
	else:
		lbl.text = "%s · 席位 %d" % [region_name, seat + 1]

func _wire_nullsec_scout() -> void:
	var btn := hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if btn == null:
		_ensure_scout_intel_btn()
		btn = hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if btn == null:
		return
	btn.visible = GameSession.pending_mode == "nullsec"
	if _nullsec_spectating:
		btn.text = "切换视角"
	if not btn.observe_requested.is_connected(_on_scout_observe):
		btn.observe_requested.connect(_on_scout_observe)
	## Rows + gate hint are rebuilt on every open: hangar contents change all match long.
	if not btn.menu_opening.is_connected(_refresh_scout_menu):
		btn.menu_opening.connect(_refresh_scout_menu)
	_refresh_scout_menu()

func _refresh_scout_menu() -> void:
	var btn := hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if btn == null:
		return
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", -1))
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	var targets: Array = []
	for s in seats:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if not bool(s.get("occupied", false)):
			continue
		if not NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			continue
		var sid := int(s.get("seat_id", 0))
		targets.append({
			"seat_id": sid,
			"nick": str(s.get("nick", "?")),
			"finished": false,
			"self": not _nullsec_spectating and sid == local_seat,
		})
	btn.set_targets(targets)
	btn.set_hint("" if _nullsec_spectating else _scout_gate_reason())

func _on_scout_observe(seat_id: int) -> void:
	if _nullsec_spectating:
		_switch_watch_seat(seat_id)
		return
	## Returning to one's own board is never gated — only leaving to watch others is (§4.2.1).
	if seat_id == int(GameSession.pending_nullsec.get("local_seat", -1)):
		_switch_watch_seat(seat_id, "视角返回本席主场")
		return
	## Require an explore-tagged ship on the local hangar/field (MULTIPLAYER_PVP §4.2).
	var reason := _scout_gate_reason()
	if reason != "":
		show_notice(reason)
		## One line per rejected click (not per frame): the gate keeps reading false in play
		## while the hulls carry the tag on disk, so the roster it actually saw has to be logged.
		print("[Scout] blocked | %s | 本席舰 %s" % [reason, _local_roster_debug()])
		return
	## Scene switch only: keep free-cam angles if already free.
	_switch_watch_seat(seat_id, "刺探情报 → 席位 %d（观察不停本场）" % (seat_id + 1))

## "" = scouting allowed. Otherwise the text says what is missing (§4.2.1 门控范围).
func _scout_gate_reason() -> String:
	if board == null:
		return SCOUT_GATE_HINT
	## Hangar (备战席) counts as well as the field — either slot satisfies §4.2.
	var hangar := 0
	var field := 0
	var wrecked := 0
	for s in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if int(s.team_id) != ShipUnit.TEAM_PLAYER or s.is_protect_target:
			continue
		if s.slot_type != "hangar" and s.slot_type != "field":
			continue
		if not _is_explore_ship(s.ship_id):
			if s.slot_type == "hangar":
				hangar += 1
			else:
				field += 1
			continue
		if not s.is_destroyed:
			return ""
		wrecked += 1
	if wrecked > 0:
		return "%s：本席探索护卫已被击毁 %d 艘，本回合无法刺探" % [SCOUT_GATE_HINT, wrecked]
	return "%s：当前备战席 %d 舰 / 场上 %d 舰，无一带探索标签" % [SCOUT_GATE_HINT, hangar, field]

## Every hull the board hands back, with what the gate reads off it.
func _local_roster_debug() -> String:
	if board == null:
		return "board=null"
	var parts: PackedStringArray = []
	for s in board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		parts.append("#%d/%s/team%d/dead=%s/unmanned=%s/tags=%s" % [
			s.ship_id,
			s.slot_type,
			int(s.team_id),
			str(s.is_destroyed),
			str(s.is_unmanned),
			str(DataStore.get_ship(s.ship_id).get("fetter_ids", [])),
		])
	return "[%s]" % ", ".join(parts)

## Scout gate canon: only the four racial exploration frigates count, and they are
## identified by the `exploration` fetter — no other hull carries it (MULTIPLAYER_PVP §4.2).
func _is_explore_ship(ship_id: int) -> bool:
	var data: Dictionary = DataStore.get_ship(ship_id)
	if data.is_empty():
		return false
	for f in (data.get("fetter_ids", []) as Array):
		if str(f).to_lower() == EXPLORE_FETTER_ID:
			return true
	for t in (data.get("tags", []) as Array):
		if str(t).to_lower() == EXPLORE_FETTER_ID:
			return true
	return false

func _nullsec_on_prepare_begin() -> void:
	if GameSession.pending_mode != "nullsec" or _nullsec_pve == null or board == null:
		return
	if _nullsec_spectating:
		return
	_spawn_nullsec_creeps_with_slide()

func _spawn_nullsec_creeps_with_slide() -> void:
	## Clear AI field ships from prior versus AI army when first entering nullsec PVE.
	## Last round's salvage freighter goes with them: it is player-owned but creep-spawned.
	for s in board.all_ships().duplicate():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if int(s.team_id) == ShipUnit.TEAM_AI or s.is_protect_target:
			board.remove_ship_node(s)
	## Sleepers hold no titan: the creep side never carries a titan fetter (MATCH_FLOW §5.1).
	board.set_titan_fetter_race(ShipUnit.TEAM_AI, "")
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())
	var roster: Array = _nullsec_pve.creep_ai.locked_roster
	var fh := int(DataStore.board.get("field_height", 6))
	var sliding: Array = []
	for entry in roster:
		var sid := int(entry.get("ship_id", 0))
		var cell := int(entry.get("cell", 0))
		var z := clampi(int(cell / 8.0), 0, fh - 1)
		var cols := BoardController.field_cols_at(z)
		var x := clampi(cell % 8, 0, maxi(0, cols - 1))
		if not board.is_field_cell_free_for(ShipUnit.TEAM_AI, x, z):
			var found := false
			for zz in range(fh):
				var cc := BoardController.field_cols_at(zz)
				for xx in range(cc):
					if board.is_field_cell_free_for(ShipUnit.TEAM_AI, xx, zz):
						x = xx
						z = zz
						found = true
						break
				if found:
					break
			if not found:
				continue
		var ship := board.spawn_ship(sid, 1, ShipUnit.TEAM_AI, "field", x, z)
		if ship == null:
			continue
		var dest := ship.global_position
		var start := dest + _nullsec_pve.slide_start_offset()
		ship.global_position = start
		sliding.append({"ship": ship, "from": start, "to": dest})
	if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
		var center := _nullsec_pve.salvage_center_cell(
			BoardController.field_cols_at(0),
			int(DataStore.board.get("field_height", 6))
		)
		var cx := clampi(center.x, 0, BoardController.field_cols_at(center.y) - 1)
		var cz := clampi(center.y, 0, fh - 1)
		if not board.is_field_cell_free_for(ShipUnit.TEAM_AI, cx, cz):
			for zz in range(fh):
				var cc2 := BoardController.field_cols_at(zz)
				for xx in range(cc2):
					if board.is_field_cell_free_for(ShipUnit.TEAM_AI, xx, zz):
						cx = xx
						cz = zz
						break
		var fid := _nullsec_pve.freighter_ship_id
		if fid <= 0:
			fid = _nullsec_pve.pick_freighter_id(_local_titan_race_for_ui())
		## Spawned on the AI half (occupancy + world pose) but owned by the player: normal
		## targeting then has creeps shoot it and player logistics repair it, no special case.
		var fr := board.spawn_ship(fid, 1, ShipUnit.TEAM_AI, "field", cx, cz)
		if fr:
			fr.team_id = ShipUnit.TEAM_PLAYER
			fr.field_side_team = ShipUnit.TEAM_AI
			var dest2 := fr.global_position
			var start2 := dest2 + _nullsec_pve.slide_start_offset()
			fr.global_position = start2
			sliding.append({"ship": fr, "from": start2, "to": dest2})
	_run_nullsec_creep_slide(sliding)

func _run_nullsec_creep_slide(sliding: Array) -> void:
	if sliding.is_empty():
		_nullsec_after_slide_done()
		return
	## Pitch-only lookat while sliding (skip if free/observe cam).
	if not _camera_manual_pose() and camera:
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg - 8.0, -89.0, -20.0)
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
	var duration := 1.2
	var t := 0.0
	while t < duration:
		t += get_process_delta_time()
		var a := clampf(t / duration, 0.0, 1.0)
		for e in sliding:
			var ship: ShipUnit = e.get("ship")
			if ship == null or not is_instance_valid(ship):
				continue
			ship.global_position = (e.get("from") as Vector3).lerp(e.get("to") as Vector3, a)
		await get_tree().process_frame
	for e in sliding:
		var ship2: ShipUnit = e.get("ship")
		if ship2 and is_instance_valid(ship2):
			ship2.global_position = e.get("to") as Vector3
	_nullsec_pve.slide_done = true
	_nullsec_after_slide_done()

func _nullsec_after_slide_done() -> void:
	## Open shop + secondary default view (free/observe cam: shop only).
	_collapse_bottom = false
	_apply_adaptive_hud_layout()
	if not _camera_manual_pose():
		_apply_camera_view_dict(_camera_secondary_view())
	show_notice("人机编队就位 · 商店已开")

func _nullsec_lock_next_creeps() -> void:
	if _nullsec_pve == null or match_ctrl == null:
		return
	var round_r := maxi(1, match_ctrl.battle_game_stage_count + 1)
	_nullsec_pve.setup(_nullsec_rng, round_r)
	_nullsec_pve.pick_task(round_r)
	if not _nullsec_pve.is_pve_task():
		## PVP round: opponent is a seat army, never a creep roster.
		_nullsec_pve.creep_ai.locked_roster.clear()
		return
	var pop := match_ctrl.population_limit()
	_nullsec_pve.lock_creeps(match_ctrl.player_gold, match_ctrl.player_level, pop)
	if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
		_nullsec_pve.pick_freighter_id(_local_titan_race_for_ui())

## PVP round-after titan fire (MULTIPLAYER_PVP §6): winner fires, draw = both fire.
## Every shot uses the doomsday presentation; losers take the fixed 20 pipe hit.
func _nullsec_resolve_pvp_doomsday(result: String) -> void:
	if _doomsday_resolver == null:
		return
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", 0))
	var rival_seat := _nullsec_rival_seat(local_seat)
	if rival_seat < 0 or rival_seat == local_seat:
		## No contender this round — nobody's titan fires, least of all at itself.
		show_notice("本回合无对手席位 · 泰坦不开火")
		return
	var local_pos := _titan_fire_point(true)
	var rival_pos := _titan_fire_point(false)
	var belt := _nullsec_belt_root()
	var kill_seats: Array = []
	match result:
		"win":
			_fire_doomsday(local_seat, rival_seat, local_pos, rival_pos, belt)
			show_notice("胜 · 末日武器命中对手泰坦")
			if not _seat_titan_alive(rival_seat):
				kill_seats.append(false)
		"lose":
			_fire_doomsday(rival_seat, local_seat, rival_pos, local_pos, belt)
			show_notice("负 · 对手末日命中本方泰坦")
			if not _seat_titan_alive(local_seat):
				kill_seats.append(true)
		_:
			_fire_doomsday(local_seat, rival_seat, local_pos, rival_pos, belt)
			_fire_doomsday(rival_seat, local_seat, rival_pos, local_pos, belt)
			show_notice("平局 · 双方各发一次末日")
			if not _seat_titan_alive(local_seat):
				kill_seats.append(true)
			if not _seat_titan_alive(rival_seat):
				kill_seats.append(false)
	_hold_for_doomsday_presentation()
	_doomsday_resolver.schedule_return_home(get_tree(), local_seat, DoomsdayFx.FIRE_S)
	_refresh_titan_hp_bar()
	_refresh_hud()
	if _nullsec_speed:
		_nullsec_speed.mark_seat_finished()
	var scout := hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if scout:
		scout.set_local_finished(true)
	for home_side in kill_seats:
		_begin_titan_kill(bool(home_side))

## Doomsday beam must finish before the round flips (MULTIPLAYER_PVP §6).
## Wall-clock gate — never couple to 倍速 / SceneTreeTimer.
func _hold_for_doomsday_presentation() -> void:
	var hold := float(DataStore.visual.get("titan_doomsday_hold_s", 0.8))
	_doomsday_busy = true
	_doomsday_hold_until_ms = Time.get_ticks_msec() + int((DoomsdayFx.FIRE_S + maxf(hold, 0.0)) * 1000.0)

func _on_one_doomsday_fx_finished() -> void:
	_doomsday_fx_left = maxi(0, _doomsday_fx_left - 1)
	_try_release_doomsday_gate()

func _try_release_doomsday_gate() -> void:
	if not _doomsday_busy:
		return
	if _doomsday_fx_left > 0:
		return
	if Time.get_ticks_msec() < _doomsday_hold_until_ms:
		return
	_on_doomsday_presentation_done()

func _on_doomsday_presentation_done() -> void:
	if not _doomsday_busy:
		return
	_doomsday_busy = false
	_doomsday_hold_until_ms = 0
	## A hull kill overlaps the beam; its own callback resumes the round.
	if _titan_kill_active > 0:
		return
	if _nullsec_prepare_pending:
		_nullsec_prepare_pending = false
		_nullsec_enter_next_round()

func _seat_titan_alive(seat_id: int) -> bool:
	if _doomsday_resolver == null:
		return true
	var pipes: TitanHpPipes = _doomsday_resolver.pipes_by_seat.get(seat_id) as TitanHpPipes
	if pipes == null:
		return true
	return pipes.alive()

func _begin_titan_kill(home_side: bool) -> void:
	var berth := _titan_berth if home_side else _rival_titan_berth
	if berth == null or not is_instance_valid(berth):
		return
	_titan_kill_busy = true
	_titan_kill_active += 1
	begin_titan_kill_shake()
	_TitanKillSequence.play(berth, world, func(): _on_titan_kill_done())

func _on_titan_kill_done() -> void:
	_titan_kill_active = maxi(0, _titan_kill_active - 1)
	if _titan_kill_active > 0:
		return
	_titan_kill_busy = false
	if not _seat_titan_alive(int(GameSession.pending_nullsec.get("local_seat", 0))):
		_nullsec_prepare_pending = false
		## Early-out → same spectate runtime as「仅观战」.
		if not _nullsec_spectating:
			enter_nullsec_spectate("eliminated")
		return
	if _doomsday_busy:
		return
	## Prepare was held back while the hull was exploding — run it now.
	if _nullsec_prepare_pending:
		_nullsec_prepare_pending = false
		_nullsec_enter_next_round()

func begin_titan_kill_shake() -> void:
	## Free / observe camera: do not overlay scripted shake (UI_AND_SHELL / plan).
	if _camera_manual_pose():
		return
	var s := float(DataStore.visual.get("titan_kill_shake_s", 2.6))
	_titan_shake_until_ms = Time.get_ticks_msec() + int(s * 1000.0)

func _on_titan_return_home(seat_id: int) -> void:
	## After doomsday VFX +5s: guest returns to own home field (skybox + notice).
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", -1))
	if seat_id != local_seat:
		return
	var asg: Dictionary = GameSession.pending_nullsec.get("assignments", {})
	var region := str(asg.get(str(local_seat), asg.get(local_seat, "")))
	if region != "":
		apply_region_skybox(region)
	show_notice("投送返回主场")

func _fire_doomsday(attacker_seat: int, loser_seat: int, from: Vector3, to: Vector3, belt: Node3D) -> void:
	if attacker_seat == loser_seat or attacker_seat < 0 or loser_seat < 0:
		push_warning("[Nullsec] doomsday skipped: attacker=%d loser=%d" % [attacker_seat, loser_seat])
		return
	var race := _seat_titan_race(attacker_seat)
	if race == "":
		race = "caldari"
	var fx := DoomsdayFx.play(world, race, from, to)
	if fx != null and is_instance_valid(fx):
		_doomsday_fx_left += 1
		fx.finished.connect(_on_one_doomsday_fx_finished)
	_doomsday_resolver.resolve_loss(attacker_seat, loser_seat, from, to, belt)

func _nullsec_belt_root() -> Node3D:
	var env := world.get_node_or_null("MapEnv")
	if env:
		var belt := env.get_node_or_null("AsteroidBelt") as Node3D
		if belt:
			return belt
	return world.get_node_or_null("AsteroidBelt") as Node3D

## Opposing seat for this PVP round, or -1 when the room holds no other contender.
## Never falls back to `local_seat`: that made a won round fire our own doomsday at
## ourselves, so winning cost 20 pipe HP (MULTIPLAYER_PVP §6).
func _nullsec_rival_seat(local_seat: int) -> int:
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s in seats:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		if not bool(d.get("occupied", false)):
			continue
		var sid := int(d.get("seat_id", -1))
		if sid == local_seat or sid < 0:
			continue
		## Spectators and seats that never picked a titan are not contenders.
		if not NullsecNetSession.is_player_race(str(d.get("titan_race", ""))):
			continue
		return sid
	return -1

func _seat_titan_race(seat_id: int) -> String:
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s in seats:
		if typeof(s) == TYPE_DICTIONARY and int((s as Dictionary).get("seat_id", -1)) == seat_id:
			return str((s as Dictionary).get("titan_race", ""))
	return ""

func _titan_fire_point(local_side: bool) -> Vector3:
	if local_side:
		if _titan_berth and is_instance_valid(_titan_berth):
			return _titan_berth.fire_point()
		return Vector3(0, 1.5, 14.0)
	if _rival_titan_berth and is_instance_valid(_rival_titan_berth):
		return _rival_titan_berth.fire_point()
	## Fallback mirror if rival berth missing.
	var p := Vector3(0, 1.5, 14.0)
	if _titan_berth and is_instance_valid(_titan_berth):
		p = _titan_berth.fire_point()
	return Vector3(p.x, p.y, -p.z)

func _on_nullsec_speed_changed(speed: float) -> void:
	_apply_resolved_speed()
	show_notice("对局倍速 %s" % SpeedDropdownMenu._label(speed))

func _apply_resolved_speed() -> void:
	if _nullsec_speed == null or match_ctrl == null:
		return
	var spd := _nullsec_speed.current_speed()
	if match_ctrl.has_method("set_battle_speed"):
		match_ctrl.set_battle_speed(spd)
	elif "battle_speed" in match_ctrl:
		match_ctrl.battle_speed = spd
	_refresh_hud()

func _on_nullsec_force_draw() -> void:
	show_notice("墙钟 2 分钟到 · 剩余对局判平局")
	if match_ctrl and match_ctrl.has_method("force_draw_battle"):
		match_ctrl.force_draw_battle()

func _ensure_ground() -> void:
	var g := get_node_or_null("Ground") as MeshInstance3D
	if g == null:
		return
	# Invisible hit plane only — original Endless has no visible floor pad
	if g.mesh == null:
		var plane := PlaneMesh.new()
		plane.size = Vector2(48, 48)
		g.mesh = plane
	g.visible = false
	g.position = Vector3(0, -0.05, 0)

func _spawn_map_env(mode: String) -> void:
	var env := MapEnv.new()
	env.name = "MapEnv"
	world.add_child(env)
	env.build(mode)
	if mode == "nullsec":
		_titan_berth = env.titan_berth
		_rival_titan_berth = env.rival_titan_berth
		_attach_titan_hp_bar()
	else:
		_attach_citadel_hp_bar(env)
	_ensure_sky()

func _attach_titan_hp_bar() -> void:
	if _titan_berth == null or not is_instance_valid(_titan_berth):
		return
	_titan_hp_bar = _TITAN_BAR_SCRIPT.new() as Node3D
	_titan_hp_bar.name = "TitanHpBar"
	_titan_berth.add_child(_titan_hp_bar)
	## Bar rides the stern anchor, so the offset is only clearance above the hull.
	_titan_hp_bar.call("setup", float(DataStore.visual.get("titan_hp_bar_stern_margin", 2.0)))
	_refresh_titan_hp_bar()

func _refresh_titan_hp_bar() -> void:
	if _titan_hp_bar == null or not is_instance_valid(_titan_hp_bar):
		return
	var pipes := _local_titan_pipes()
	if pipes:
		_titan_hp_bar.call("refresh", pipes)

func _local_titan_pipes() -> TitanHpPipes:
	if _doomsday_resolver == null:
		return null
	var seat := int(GameSession.pending_nullsec.get("local_seat", -1))
	return _doomsday_resolver.pipes_by_seat.get(seat) as TitanHpPipes

func _attach_citadel_hp_bar(env: MapEnv) -> void:
	if env == null or env.player_citadel == null:
		return
	_citadel_hp_bar = _CITADEL_BAR_SCRIPT.new() as Node3D
	_citadel_hp_bar.name = "CitadelHealthBar"
	env.player_citadel.add_child(_citadel_hp_bar)
	_citadel_hp_bar.call("setup", float(DataStore.visual.get("citadel_health_bar_y", 9.5)))
	_refresh_citadel_bar()

func _refresh_citadel_bar() -> void:
	## Nullsec scores lives on the titan pipes, not the citadel formula.
	if GameSession.pending_mode == "nullsec":
		_refresh_titan_hp_bar()
		return
	if _citadel_hp_bar == null or not is_instance_valid(_citadel_hp_bar):
		return
	_citadel_hp_bar.call("refresh", float(match_ctrl.player_hp), float(match_ctrl.player_max_hp))

func _ensure_sky() -> void:
	if get_node_or_null("WorldEnvironment"):
		return
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.1, 0.14)
	var region_id := ""
	if GameSession.pending_mode == "nullsec" and not GameSession.pending_nullsec.is_empty():
		var asg: Dictionary = GameSession.pending_nullsec.get("assignments", {})
		## Own home sky at kickoff — any other seat's is a scout hop away.
		region_id = _seat_region(int(GameSession.pending_nullsec.get("local_seat", -1)))
		if region_id == "" and not asg.is_empty():
			region_id = str(asg.values()[0])
	var sky_tex: Texture2D = null
	if region_id != "":
		sky_tex = SkyboxCatalog.load_sky_texture(region_id)
	if sky_tex == null:
		sky_tex = UiAssets.tex("res://assets/skyboxes/amarr.jpeg")
	if sky_tex == null:
		sky_tex = UiAssets.tex("res://assets/skyboxes/gallente.jpeg")
	if sky_tex:
		environment.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = sky_tex
		mat.energy_multiplier = 1.0
		sky.sky_material = mat
		environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.74, 0.76, 0.80)
	environment.ambient_light_energy = 0.70
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.86
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.97
	environment.adjustment_contrast = 1.03
	environment.adjustment_saturation = 1.0
	environment.glow_enabled = false
	environment.ssao_enabled = false
	ShipLook.apply_match_environment(environment)
	we.environment = environment
	add_child(we)
	_ensure_board_lights()

func apply_region_skybox(region_id: String) -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var sky_tex := SkyboxCatalog.load_sky_texture(region_id)
	if sky_tex == null:
		return
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = sky_tex
	sky.sky_material = mat
	we.environment.background_mode = Environment.BG_SKY
	we.environment.sky = sky

func _ensure_board_lights() -> void:
	## Off-frustum lights — driven by visual.json ship_look (unity-standard default).
	if get_node_or_null("KeyLightOffscreen") == null:
		var key := DirectionalLight3D.new()
		key.name = "KeyLightOffscreen"
		key.light_energy = 1.0
		key.light_color = Color(1.0, 1.0, 1.0)
		key.shadow_enabled = true
		key.shadow_opacity = 0.55
		key.rotation_degrees = Vector3(-57.3, 107.7, 0.0)
		add_child(key)
	if get_node_or_null("RimLightOffscreen") == null:
		var rim := DirectionalLight3D.new()
		rim.name = "RimLightOffscreen"
		rim.light_energy = 0.0
		rim.light_color = Color(0.65, 0.8, 1.0)
		rim.shadow_enabled = false
		rim.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
		add_child(rim)
	if get_node_or_null("FillLight") == null:
		var fill := OmniLight3D.new()
		fill.name = "FillLight"
		fill.light_energy = 0.0
		fill.omni_range = 85.0
		fill.position = Vector3(0, 32, 10)
		add_child(fill)
	if get_node_or_null("FillLightAI") == null:
		var fill_ai := OmniLight3D.new()
		fill_ai.name = "FillLightAI"
		fill_ai.light_energy = 0.0
		fill_ai.light_color = Color(0.88, 0.92, 1.0)
		fill_ai.omni_range = 60.0
		fill_ai.position = Vector3(-16.0, 24.0, -18.0)
		add_child(fill_ai)
	if get_node_or_null("FillLightPlayer") == null:
		var fill_p := OmniLight3D.new()
		fill_p.name = "FillLightPlayer"
		fill_p.light_energy = 0.0
		fill_p.light_color = Color(1.0, 0.96, 0.9)
		fill_p.omni_range = 60.0
		fill_p.position = Vector3(16.0, 24.0, 18.0)
		add_child(fill_p)
	var scene_key := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if scene_key:
		scene_key.light_energy = 0.0
		scene_key.shadow_opacity = 0.4
	ShipLook.apply_match_lights(self)

func _setup_camera() -> void:
	## Two default camera views:
	## - primary: battle / shop collapsed baseline
	## - secondary: prepare + shop expanded
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var start := _camera_secondary_view() if not _collapse_bottom else _camera_primary_view()
	_cam_base_pos = start.get("pos", Vector3(-2.0, 21.464, 18.067))
	_cam_base_pitch_deg = float(start.get("pitch_deg", -57.0))
	_cam_default_pitch_deg = float(_camera_primary_view().get("pitch_deg", _cam_base_pitch_deg))
	_cam_base_yaw_deg = float(start.get("yaw_deg", 0.0))
	camera.fov = float(start.get("fov", 47.0))
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _camera_primary_view() -> Dictionary:
	var v: Dictionary = DataStore.visual
	return {
		"pos": Vector3(
			float(v.get("camera_x", 2.00856733322144)),
			float(v.get("camera_height", 35.0967063903809)),
			float(v.get("camera_distance", 28.4933738708496))
		),
		"pitch_deg": -float(v.get("camera_angle_deg", 55.6669960021973)),
		"yaw_deg": float(v.get("camera_yaw_deg", 180.0)) - 180.0,
		"fov": float(v.get("camera_fov", 50.0))
	}

func _camera_secondary_view() -> Dictionary:
	var v: Dictionary = DataStore.visual
	return {
		"pos": Vector3(
			float(v.get("camera_second_x", 1.82857227325439)),
			float(v.get("camera_second_height", 27.0970573425293)),
			float(v.get("camera_second_distance", 33.6982917785645))
		),
		"pitch_deg": -float(v.get("camera_second_angle_deg", 55.6669960021973)),
		"yaw_deg": float(v.get("camera_second_yaw_deg", float(v.get("camera_yaw_deg", 180.0)))) - 180.0,
		"fov": float(v.get("camera_second_fov", float(v.get("camera_fov", 50.0))))
	}

func _camera_active_view() -> Dictionary:
	if match_ctrl and match_ctrl.stage == MatchController.Stage.BATTLE:
		return _camera_primary_view()
	return _camera_primary_view() if _collapse_bottom else _camera_secondary_view()

func _camera_manual_pose() -> bool:
	## Free + observe both own the camera pose (no framing / default snaps).
	return _camera_free or _camera_observe

func _process(delta: float) -> void:
	if _nullsec_speed:
		_nullsec_speed.tick_wall_clock()
	_try_release_doomsday_gate()
	if _camera_observe:
		_update_camera_observe(delta)
	elif _camera_free:
		_update_camera_free(delta)
	else:
		_update_camera_headup(delta)
		_update_camera_view_blend(delta)
		_update_camera_framing(delta)
	_try_hide_slot_markers_when_view1_settled()
	## Breathe applies in both default and free view (options toggle only).
	_update_camera_breathe()
	_tick_exp_hold(delta)
	_tick_titan_intro(delta)
	_tick_info_hold()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not _gui_wants_text_input():
			_toggle_game_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_V and not _gui_wants_text_input() and not UiLayout.is_mobile():
			if _game_menu_open():
				return
			_toggle_camera_mode()
			get_viewport().set_input_as_handled()
			return
	if not _camera_manual_pose():
		return
	if _game_menu_open():
		return
	if _camera_observe:
		_handle_observe_orbit_input(event)
		return
	if UiLayout.is_mobile():
		_handle_mobile_orbit_input(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_look_dragging = mb.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _cam_look_dragging:
		var mm := event as InputEventMouseMotion
		var sens := float(DataStore.visual.get("camera_free_look_sens", 0.18))
		_cam_base_yaw_deg -= mm.relative.x * sens
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg - mm.relative.y * sens, -89.0, 89.0)
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		get_viewport().set_input_as_handled()

func _handle_observe_orbit_input(event: InputEvent) -> void:
	## PC: middle-drag orbit + wheel zoom. Mobile: 1-finger orbit + 2-finger pinch zoom.
	## Zoom changes distance only — never FOV (UI_AND_SHELL §2.3.1).
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		## factor > 1 = fingers apart = zoom in (closer).
		if mg.factor > 0.001:
			_observe_zoom_by(1.0 / mg.factor)
		get_viewport().set_input_as_handled()
		return
	if UiLayout.is_mobile():
		_handle_observe_mobile_input(event)
		return
	if event is InputEventMouseButton:
		var mb2 := event as InputEventMouseButton
		if mb2.button_index == MOUSE_BUTTON_WHEEL_UP and mb2.pressed:
			_observe_zoom_by(0.9)
			get_viewport().set_input_as_handled()
			return
		if mb2.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb2.pressed:
			_observe_zoom_by(1.1)
			get_viewport().set_input_as_handled()
			return
		if mb2.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_look_dragging = mb2.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _cam_look_dragging:
		var mm2 := event as InputEventMouseMotion
		var sens := float(DataStore.visual.get("camera_free_look_sens", 0.18))
		_orbit_camera_around_observe(-mm2.relative.x * sens, -mm2.relative.y * sens)
		get_viewport().set_input_as_handled()

func _handle_observe_mobile_input(event: InputEvent) -> void:
	if pointer != null and pointer.has_method("is_pointer_dragging") and pointer.is_pointer_dragging():
		_cam_orbit_dragging = false
		_cam_orbit_touch_index = -1
		_observe_pinch_ids.clear()
		_observe_touch_pos.clear()
		_observe_pinch_last_dist = 0.0
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _ui_blocks_camera_touch(st.position) and _observe_pinch_ids.is_empty():
				return
			_observe_touch_pos[st.index] = st.position
			if not _observe_pinch_ids.has(st.index):
				_observe_pinch_ids.append(st.index)
			if _observe_pinch_ids.size() >= 2:
				_cam_orbit_dragging = false
				_cam_orbit_touch_index = -1
				_observe_pinch_last_dist = _observe_pinch_span()
			elif _observe_pinch_ids.size() == 1:
				_cam_orbit_touch_index = st.index
				_cam_orbit_dragging = true
			get_viewport().set_input_as_handled()
		else:
			_observe_touch_pos.erase(st.index)
			_observe_pinch_ids.erase(st.index)
			if st.index == _cam_orbit_touch_index:
				_cam_orbit_dragging = false
				_cam_orbit_touch_index = -1
			if _observe_pinch_ids.size() < 2:
				_observe_pinch_last_dist = 0.0
			elif _observe_pinch_ids.size() == 1:
				_cam_orbit_touch_index = _observe_pinch_ids[0]
				_cam_orbit_dragging = true
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_observe_touch_pos[sd.index] = sd.position
		if _observe_pinch_ids.size() >= 2:
			var span := _observe_pinch_span()
			if _observe_pinch_last_dist > 1.0 and span > 1.0:
				## Fingers apart → span grows → zoom in (closer).
				_observe_zoom_by(_observe_pinch_last_dist / span)
			_observe_pinch_last_dist = span
			get_viewport().set_input_as_handled()
			return
		if not _cam_orbit_dragging or sd.index != _cam_orbit_touch_index:
			return
		var sens_m := float(DataStore.visual.get("camera_free_look_sens", 0.18))
		_orbit_camera_around_observe(-sd.relative.x * sens_m, -sd.relative.y * sens_m)
		get_viewport().set_input_as_handled()

func _observe_pinch_span() -> float:
	if _observe_pinch_ids.size() < 2:
		return 0.0
	var a: int = _observe_pinch_ids[0]
	var b: int = _observe_pinch_ids[1]
	if not _observe_touch_pos.has(a) or not _observe_touch_pos.has(b):
		return _observe_pinch_last_dist
	return (_observe_touch_pos[a] as Vector2).distance_to(_observe_touch_pos[b] as Vector2)

func _handle_mobile_orbit_input(event: InputEvent) -> void:
	## Single-finger drag orbits around board center; ignore 2nd finger / ship drags.
	if pointer != null and pointer.has_method("is_pointer_dragging") and pointer.is_pointer_dragging():
		_cam_orbit_dragging = false
		_cam_orbit_touch_index = -1
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.index > 0:
			return
		if st.pressed:
			if _ui_blocks_camera_touch(st.position):
				return
			if _screen_hits_ship(st.position):
				return
			_cam_orbit_touch_index = st.index
			_cam_orbit_dragging = true
			get_viewport().set_input_as_handled()
		elif st.index == _cam_orbit_touch_index:
			_cam_orbit_dragging = false
			_cam_orbit_touch_index = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _cam_orbit_dragging or sd.index != _cam_orbit_touch_index:
			return
		var sens := float(DataStore.visual.get("camera_free_look_sens", 0.18))
		_orbit_camera_around_board(-sd.relative.x * sens, -sd.relative.y * sens)
		get_viewport().set_input_as_handled()

func _ui_blocks_camera_touch(screen: Vector2) -> bool:
	if pointer != null and pointer.has_method("ui_blocks_screen"):
		return bool(pointer.ui_blocks_screen(screen))
	var hover := get_viewport().gui_get_hovered_control() if get_viewport() else null
	return hover != null

func _screen_hits_ship(screen: Vector2) -> bool:
	if board == null or camera == null:
		return false
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	return board.pick_ship_at(origin, dir) != null

func _orbit_camera_around_board(yaw_delta_deg: float, pitch_delta_deg: float) -> void:
	_orbit_camera_around_pivot(Vector3.ZERO, yaw_delta_deg, pitch_delta_deg, 85.0)

func _orbit_camera_around_observe(yaw_delta_deg: float, pitch_delta_deg: float) -> void:
	_observe_yaw += deg_to_rad(yaw_delta_deg)
	_observe_elev = clampf(_observe_elev + deg_to_rad(pitch_delta_deg), deg_to_rad(-89.95), deg_to_rad(89.95))
	_apply_observe_pose()

func _observe_zoom_by(factor: float) -> void:
	if factor <= 0.001:
		return
	_observe_dist = clampf(_observe_dist * factor, _observe_dist_min, _observe_dist_max)
	_apply_observe_pose()

func _apply_observe_pose() -> void:
	if camera == null:
		return
	var pivot := _observe_pivot()
	var cp := cos(_observe_elev)
	_cam_base_pos = pivot + Vector3(sin(_observe_yaw) * cp, sin(_observe_elev), cos(_observe_yaw) * cp) * _observe_dist
	camera.position = _cam_base_pos
	if camera.global_position.distance_squared_to(pivot) > 0.0001:
		camera.look_at(pivot, Vector3.UP)
	_cam_base_pitch_deg = camera.rotation_degrees.x
	_cam_base_yaw_deg = camera.rotation_degrees.y

func _observe_fit_distance(ship: ShipUnit) -> float:
	var radius := 1.0
	if ship != null and is_instance_valid(ship):
		radius = maxf(ship.visual_radius_world(), 0.5)
	var half_v := deg_to_rad(maxf(camera.fov, 1.0) * 0.5)
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(16, 9)
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_h := atan(tan(half_v) * aspect)
	var half := minf(half_v, half_h)
	var mul := float(DataStore.visual.get("camera_observe_fit_mul", 1.15))
	return maxf((radius * mul) / maxf(tan(half), 0.01), 2.0)

func _observe_front_left_above_dir(ship: ShipUnit) -> Vector3:
	## Bow = local −Z; left = local −X; mix with world-up for「左前上方」.
	## Capture once at enter — later ship yaw must not rewrite this world angle.
	var ship_basis := ship.global_transform.basis
	var forward := -ship_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0, 0, -1)
	else:
		forward = forward.normalized()
	var left := -ship_basis.x
	left.y = 0.0
	if left.length_squared() < 0.0001:
		left = Vector3(-1, 0, 0)
	else:
		left = left.normalized()
	var elev_w := float(DataStore.visual.get("camera_observe_elev_weight", 0.85))
	var dir := (forward + left + Vector3.UP * elev_w)
	if dir.length_squared() < 0.0001:
		return Vector3(-0.5, 0.7, -0.5).normalized()
	return dir.normalized()

func _orbit_camera_around_pivot(pivot: Vector3, yaw_delta_deg: float, pitch_delta_deg: float, pitch_limit_deg: float) -> void:
	var offset := _cam_base_pos - pivot
	var dist := maxf(offset.length(), 2.0)
	var yaw := atan2(offset.x, offset.z) + deg_to_rad(yaw_delta_deg)
	var pitch := asin(clampf(offset.y / dist, -0.999, 0.999)) + deg_to_rad(pitch_delta_deg)
	## Keep a hair inside ±90 so look_at never flips through the pole.
	var lim := minf(absf(pitch_limit_deg), 90.0)
	pitch = clampf(pitch, deg_to_rad(-lim + 0.05), deg_to_rad(lim - 0.05))
	var cp := cos(pitch)
	_cam_base_pos = pivot + Vector3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp) * dist
	camera.position = _cam_base_pos
	if camera.global_position.distance_squared_to(pivot) > 0.0001:
		camera.look_at(pivot, Vector3.UP)
	_cam_base_pitch_deg = camera.rotation_degrees.x
	_cam_base_yaw_deg = camera.rotation_degrees.y

func _observe_pivot() -> Vector3:
	if _observe_ship != null and is_instance_valid(_observe_ship):
		return _observe_ship.visual_center_world()
	return Vector3.ZERO

func _gui_wants_text_input() -> bool:
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	return focus is LineEdit or focus is TextEdit

func _on_camera_mode_pressed() -> void:
	_toggle_camera_mode()

func _toggle_camera_mode() -> void:
	## Top bar / V only toggles default ↔ free (never enters observe).
	if _camera_observe:
		_exit_observe_unit(false)
	_set_camera_free(not _camera_free)

func _set_camera_free(enabled: bool) -> void:
	if enabled:
		_exit_observe_unit(false)
	_camera_free = enabled
	_cam_look_dragging = false
	_cam_orbit_dragging = false
	_cam_orbit_touch_index = -1
	_cam_view_blend_active = false
	if _camera_free:
		## Adopt current rendered pose as free-view base (drop breathe offset).
		_cam_base_pos = camera.position
		_cam_base_pitch_deg = camera.rotation_degrees.x
		_cam_base_yaw_deg = camera.rotation_degrees.y
		_cam_headup_phase = 0
		_cam_headup_t = 0.0
		_cam_headup_offset_deg = 0.0
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		## Free view: do not delay marker hide for camera settle.
		if _pending_hide_slot_markers:
			_hide_slot_markers_now()
		if UiLayout.is_mobile():
			show_notice("自由视角 · 拖动屏幕绕棋盘旋转 · 点按钮切回")
		else:
			show_notice("自由视角 · WASD移动 QE升降 · 中键环视 · V切回")
	else:
		_snap_camera_to_active_default()
		show_notice("默认视角")
	_refresh_camera_mode_btn()
	_refresh_observe_btn()

func _enter_observe_unit(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	_camera_free = false
	_camera_observe = true
	_observe_ship = ship
	_cam_look_dragging = false
	_cam_orbit_dragging = false
	_cam_orbit_touch_index = -1
	_observe_pinch_ids.clear()
	_observe_touch_pos.clear()
	_observe_pinch_last_dist = 0.0
	_cam_view_blend_active = false
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	## World-space front-left-above from ship facing at enter only — later hull yaw ignored.
	var dir := _observe_front_left_above_dir(ship)
	_observe_yaw = atan2(dir.x, dir.z)
	_observe_elev = asin(clampf(dir.y, -0.999, 0.999))
	_observe_elev = clampf(_observe_elev, deg_to_rad(-89.95), deg_to_rad(89.95))
	_observe_dist = _observe_fit_distance(ship)
	_observe_dist_min = maxf(_observe_dist * 0.35, 1.0)
	_observe_dist_max = maxf(_observe_dist * 4.0, _observe_dist_min + 1.0)
	_apply_observe_pose()
	if _pending_hide_slot_markers:
		_hide_slot_markers_now()
	show_notice("观察单位 · 中键环绕 · 滚轮/捏合拉距")
	_refresh_camera_mode_btn()
	_refresh_observe_btn()

func _exit_observe_unit(snap_default: bool = true) -> void:
	if not _camera_observe:
		_observe_ship = null
		_refresh_observe_btn()
		return
	_camera_observe = false
	_observe_ship = null
	_cam_look_dragging = false
	_cam_orbit_dragging = false
	_cam_orbit_touch_index = -1
	_observe_pinch_ids.clear()
	_observe_touch_pos.clear()
	_observe_pinch_last_dist = 0.0
	if snap_default and not _camera_free:
		_snap_camera_to_active_default()
	_refresh_camera_mode_btn()
	_refresh_observe_btn()

func _toggle_observe_unit() -> void:
	if _info_ship == null or not is_instance_valid(_info_ship):
		show_notice("无可观察单位")
		return
	if _camera_observe and _observe_ship == _info_ship:
		_exit_observe_unit(true)
		show_notice("默认视角")
		return
	_enter_observe_unit(_info_ship)

func _update_camera_observe(_delta: float) -> void:
	if _observe_ship == null or not is_instance_valid(_observe_ship) or _observe_ship.is_destroyed:
		_exit_observe_unit(true)
		return
	## Pivot follows translation only; world yaw/elev stay fixed unless user orbits.
	_apply_observe_pose()

func _ensure_observe_btn() -> void:
	## InfoPanel is a PanelContainer, so a direct child would stretch over the whole
	## panel as a grey slab. InfoTop is no host either: portrait + weapon column
	## already fill the right column's width, and the button gets squeezed out of
	## view there. Own row in the body, right under the title block.
	var panel := hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if panel == null:
		return
	var body := panel.get_node_or_null("InfoBody") as VBoxContainer
	if body == null:
		return
	if _observe_btn != null and is_instance_valid(_observe_btn):
		if _observe_btn.get_parent() != body:
			_observe_btn.reparent(body, false)
			_place_observe_btn(body)
		return
	_observe_btn = Button.new()
	_observe_btn.name = "ObserveUnitBtn"
	_observe_btn.text = "观察单位"
	_observe_btn.focus_mode = Control.FOCUS_NONE
	_observe_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_observe_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_observe_btn.custom_minimum_size = Vector2(UiLayout.px(96, self), UiLayout.px(26, self))
	body.add_child(_observe_btn)
	_place_observe_btn(body)
	UiAssets.apply_button_font(_observe_btn, UiLayout.font_size(13, self))
	_observe_btn.pressed.connect(_toggle_observe_unit)
	_refresh_observe_btn()

func _place_observe_btn(body: VBoxContainer) -> void:
	var top := body.get_node_or_null("InfoTop")
	if top == null or _observe_btn == null or not is_instance_valid(_observe_btn):
		return
	body.move_child(_observe_btn, mini(top.get_index() + 1, body.get_child_count() - 1))

func _refresh_observe_btn() -> void:
	_ensure_observe_btn()
	if _observe_btn == null or not is_instance_valid(_observe_btn):
		return
	var can := _info_ship != null and is_instance_valid(_info_ship)
	_observe_btn.visible = can
	if can and _camera_observe and _observe_ship == _info_ship:
		_observe_btn.text = "取消观察"
	else:
		_observe_btn.text = "观察单位"

func _snap_camera_to_active_default() -> void:
	var view: Dictionary
	if match_ctrl and match_ctrl.stage == MatchController.Stage.BATTLE:
		view = _camera_primary_view()
	elif _collapse_bottom:
		view = _camera_primary_view()
	else:
		view = _camera_secondary_view()
	_apply_camera_view_dict(view, true)

func _apply_camera_view_dict(view: Dictionary, smooth: bool = true) -> void:
	## Free / observe own their pose; stage / shop / framing must not rewrite it.
	if _camera_manual_pose():
		return
	_cam_default_pitch_deg = float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg))
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	var pos: Vector3 = view.get("pos", _cam_base_pos)
	var pitch := float(view.get("pitch_deg", _cam_base_pitch_deg))
	var yaw := float(view.get("yaw_deg", _cam_base_yaw_deg))
	var fov := float(view.get("fov", camera.fov))
	if not smooth:
		_cam_view_blend_active = false
		_cam_base_pos = pos
		_cam_base_pitch_deg = pitch
		_cam_base_yaw_deg = yaw
		camera.fov = fov
		camera.position = _cam_base_pos
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		return
	_cam_view_blend_active = true
	_cam_view_blend_pos = pos
	_cam_view_blend_pitch_deg = pitch
	_cam_view_blend_yaw_deg = yaw
	_cam_view_blend_fov = fov

func _capture_cam_pose() -> Dictionary:
	return {
		"pos": _cam_base_pos,
		"pitch_deg": _cam_base_pitch_deg,
		"yaw_deg": _cam_base_yaw_deg,
		"fov": camera.fov,
		"free": _camera_free,
	}

func _restore_cam_pose(pose: Dictionary) -> void:
	_cam_view_blend_active = false
	_cam_base_pos = pose.get("pos", _cam_base_pos)
	_cam_base_pitch_deg = float(pose.get("pitch_deg", _cam_base_pitch_deg))
	_cam_base_yaw_deg = float(pose.get("yaw_deg", _cam_base_yaw_deg))
	camera.fov = float(pose.get("fov", camera.fov))
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)

func _on_shop_expanded_camera() -> void:
	if _camera_manual_pose():
		return
	_cam_pose_before_shop = _capture_cam_pose()
	_cam_pose_before_shop_valid = true
	_apply_camera_view_dict(_camera_secondary_view())

func _on_shop_collapsed_camera() -> void:
	if _camera_manual_pose():
		_cam_pose_before_shop_valid = false
		_cam_pose_before_shop.clear()
		return
	_cam_pose_before_shop_valid = false
	_cam_pose_before_shop.clear()
	_apply_camera_view_dict(_camera_primary_view())

func _refresh_camera_mode_btn() -> void:
	var btn := hud.get_node_or_null("Root/TopRight/CamModeBtn") as Button
	if btn == null:
		return
	if _camera_observe:
		btn.text = "自由视角"
		btn.tooltip_text = "当前：观察单位 · 点此进自由视角"
	elif _camera_free:
		btn.text = "默认视角"
		btn.tooltip_text = "快捷键 V · 当前：自由" if not UiLayout.is_mobile() else "当前：自由（触控绕心）"
	else:
		btn.text = "自由视角"
		btn.tooltip_text = "快捷键 V · 当前：默认" if not UiLayout.is_mobile() else "当前：默认"

func _update_camera_free(delta: float) -> void:
	if UiLayout.is_mobile():
		## Mobile free view is touch-orbit only; keep pose stable here.
		camera.position = _cam_base_pos
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		return
	## PC free fly: move relative to look; no framing pull-back.
	var v: Dictionary = DataStore.visual
	var speed := float(v.get("camera_free_move_speed", _CAM_MOVE_SPEED))
	var basis := camera.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	var up := Vector3.UP
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move += forward
	if Input.is_physical_key_pressed(KEY_S):
		move -= forward
	if Input.is_physical_key_pressed(KEY_A):
		move -= right
	if Input.is_physical_key_pressed(KEY_D):
		move += right
	if Input.is_physical_key_pressed(KEY_Q):
		move -= up
	if Input.is_physical_key_pressed(KEY_E):
		move += up
	if move != Vector3.ZERO:
		_cam_base_pos += move.normalized() * speed * delta
	var pitch_delta := 0.0
	if Input.is_physical_key_pressed(KEY_R):
		pitch_delta += _CAM_PITCH_SPEED * delta
	if Input.is_physical_key_pressed(KEY_F):
		pitch_delta -= _CAM_PITCH_SPEED * delta
	if pitch_delta != 0.0:
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + pitch_delta, -89.0, 89.0)
	var yaw_delta := 0.0
	if Input.is_physical_key_pressed(KEY_T):
		yaw_delta -= _CAM_YAW_SPEED * delta
	if Input.is_physical_key_pressed(KEY_G):
		yaw_delta += _CAM_YAW_SPEED * delta
	if yaw_delta != 0.0:
		_cam_base_yaw_deg += yaw_delta
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)

func _camera_pitch_now() -> float:
	return _cam_base_pitch_deg + _cam_headup_offset_deg

func _update_camera_headup(delta: float) -> void:
	if _camera_manual_pose():
		_cam_headup_offset_deg = 0.0
		return
	if _cam_headup_phase == 0:
		_cam_headup_offset_deg = 0.0
		return
	var v: Dictionary = DataStore.visual
	var rise_s := maxf(0.01, float(v.get("camera_headup_time_s", 0.18)))
	var recover_s := maxf(0.01, float(v.get("camera_headup_recover_s", 0.32)))
	var target_deg := maxf(0.0, float(v.get("camera_headup_pitch_deg", 6.0)))
	_cam_headup_t += delta
	if _cam_headup_phase == 1:
		var up_k := clampf(_cam_headup_t / rise_s, 0.0, 1.0)
		_cam_headup_offset_deg = lerpf(0.0, target_deg, ease(up_k, -2.0))
		if up_k >= 1.0:
			_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + target_deg, -89.0, -5.0)
			_cam_headup_phase = 0
			_cam_headup_t = 0.0
			_cam_headup_offset_deg = 0.0
	else:
		var down_k := clampf(_cam_headup_t / recover_s, 0.0, 1.0)
		_cam_headup_offset_deg = lerpf(target_deg, 0.0, ease(down_k, 2.0))
		if down_k >= 1.0:
			_cam_headup_phase = 0
			_cam_headup_t = 0.0
			_cam_headup_offset_deg = 0.0

func _trigger_camera_headup(reason: String) -> void:
	if _camera_manual_pose():
		return
	var v: Dictionary = DataStore.visual
	if not bool(v.get("camera_headup_enabled", false)):
		return
	if _suppress_headup_for_preview:
		return
	var trigger := str(v.get("camera_headup_trigger", "stage_change"))
	if trigger != "all" and trigger != reason:
		return
	_cam_headup_phase = 1
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0

func _update_camera_view_blend(delta: float) -> void:
	if not _cam_view_blend_active or _camera_manual_pose():
		return
	## Battle framing owns continuous lock; drop event blend.
	if match_ctrl != null and match_ctrl.stage == MatchController.Stage.BATTLE:
		_cam_view_blend_active = false
		return
	var framing: Dictionary = DataStore.visual.get("camera_framing", {})
	var spd := float(framing.get("lerp_speed", 4.0))
	var k := clampf(spd * delta, 0.0, 1.0)
	_cam_base_pos = _cam_base_pos.lerp(_cam_view_blend_pos, k)
	_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, _cam_view_blend_pitch_deg, k)
	_cam_base_yaw_deg = lerpf(_cam_base_yaw_deg, _cam_view_blend_yaw_deg, k)
	camera.fov = lerpf(camera.fov, _cam_view_blend_fov, k)
	var pos_done := _cam_base_pos.distance_to(_cam_view_blend_pos) < 0.03
	var ang_done := absf(_cam_base_pitch_deg - _cam_view_blend_pitch_deg) < 0.08 \
		and absf(_cam_base_yaw_deg - _cam_view_blend_yaw_deg) < 0.08
	var fov_done := absf(camera.fov - _cam_view_blend_fov) < 0.05
	if pos_done and ang_done and fov_done:
		_cam_base_pos = _cam_view_blend_pos
		_cam_base_pitch_deg = _cam_view_blend_pitch_deg
		_cam_base_yaw_deg = _cam_view_blend_yaw_deg
		camera.fov = _cam_view_blend_fov
		_cam_view_blend_active = false

func _update_camera_framing(delta: float) -> void:
	if _camera_manual_pose():
		return
	## Prepare: shop open/close events own the pose. Only Battle continuously locks view 1.
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		return
	_cam_view_blend_active = false
	var framing: Dictionary = DataStore.visual.get("camera_framing", {})
	var spd := float(framing.get("lerp_speed", 4.0))
	var view := _camera_primary_view()
	var k := clampf(spd * delta, 0.0, 1.0)
	_cam_base_pos = _cam_base_pos.lerp(view.get("pos", _cam_base_pos), k)
	_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, float(view.get("pitch_deg", _cam_base_pitch_deg)), k)
	_cam_base_yaw_deg = lerpf(_cam_base_yaw_deg, float(view.get("yaw_deg", _cam_base_yaw_deg)), k)
	camera.fov = lerpf(camera.fov, float(view.get("fov", camera.fov)), k)
	_cam_default_pitch_deg = float(view.get("pitch_deg", _cam_default_pitch_deg))
	_cam_frame_target = Vector3.ZERO
	_cam_frame_offset = Vector3.ZERO
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _camera_near_primary_view() -> bool:
	var view := _camera_primary_view()
	var pos: Vector3 = view.get("pos", _cam_base_pos)
	if _cam_base_pos.distance_to(pos) > 0.08:
		return false
	if absf(_cam_base_pitch_deg - float(view.get("pitch_deg", _cam_base_pitch_deg))) > 0.15:
		return false
	if absf(_cam_base_yaw_deg - float(view.get("yaw_deg", _cam_base_yaw_deg))) > 0.15:
		return false
	if absf(camera.fov - float(view.get("fov", camera.fov))) > 0.1:
		return false
	return true

func _hide_slot_markers_now() -> void:
	_pending_hide_slot_markers = false
	## Battle: hide Field hexes only; Hangar blue frames stay.
	if board and board.has_method("set_field_markers_visible"):
		board.set_field_markers_visible(false)
	elif board and board.has_method("set_slot_markers_visible"):
		board.set_slot_markers_visible(false)

func _show_slot_markers_now() -> void:
	_pending_hide_slot_markers = false
	if board and board.has_method("set_field_markers_visible"):
		board.set_field_markers_visible(true)
		if board.has_method("set_hangar_markers_visible"):
			board.set_hangar_markers_visible(true)
	elif board and board.has_method("set_slot_markers_visible"):
		board.set_slot_markers_visible(true)

func _try_hide_slot_markers_when_view1_settled() -> void:
	if not _pending_hide_slot_markers:
		return
	if _camera_manual_pose():
		_hide_slot_markers_now()
		return
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		_pending_hide_slot_markers = false
		return
	if _camera_near_primary_view():
		_hide_slot_markers_now()

func _update_camera_breathe() -> void:
	var v: Dictionary = DataStore.visual
	## Free / observe: offset from pilot base only (no framing). Default: base + frame.
	var base := _cam_base_pos if _camera_manual_pose() else (_cam_base_pos + _cam_frame_offset)
	var amp := float(v.get("camera_breathe_amp", 0.35))
	var period := maxf(0.5, float(v.get("camera_breathe_period_s", 12.0)))
	## Titan kill shake: super-accelerated breathe (wall clock); never on free/observe cam.
	var shaking := (not _camera_manual_pose()) and _titan_shake_until_ms > 0 and Time.get_ticks_msec() < _titan_shake_until_ms
	if shaking:
		amp = float(v.get("titan_kill_shake_amp", 4.5))
		period = maxf(0.05, float(v.get("titan_kill_shake_period_s", 0.22)))
	elif _titan_shake_until_ms > 0 and Time.get_ticks_msec() >= _titan_shake_until_ms:
		_titan_shake_until_ms = 0
	## Player setting overrides content; options menu is the only off switch.
	## Shake still runs even if breathe preference is off (kill cue).
	var breathe_on := true
	if not shaking:
		if GameSession != null:
			breathe_on = GameSession.camera_breathe_enabled
		elif not bool(v.get("camera_breathe_enabled", true)):
			breathe_on = false
	if not breathe_on and not shaking:
		camera.position = base
		if _camera_observe:
			var piv0 := _observe_pivot()
			if camera.global_position.distance_squared_to(piv0) > 0.0001:
				camera.look_at(piv0, Vector3.UP)
		else:
			camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)
		return
	var th := Time.get_ticks_msec() * 0.001 * TAU / period
	var s := sin(th)
	var c := cos(th)
	# Diagonal figure-8 on XZ only (no Y) so pitch feel stays stable.
	var local := Vector3(s, 0.0, s * c) * amp
	var half := 0.70710678
	var offset := Vector3(
		local.x * half - local.z * half,
		0.0,
		local.x * half + local.z * half
	)
	camera.position = base + offset
	if _camera_observe:
		var piv1 := _observe_pivot()
		if camera.global_position.distance_squared_to(piv1) > 0.0001:
			camera.look_at(piv1, Vector3.UP)
	else:
		camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _build_hud() -> void:
	_ensure_reserve_grid()
	_ensure_observe_btn()
	_apply_adaptive_hud_layout()
	_style_hud_chrome()
	_wire_shop_chrome()
	_apply_shop_interactable()
	var root := hud.get_node_or_null("Root") as Control
	if root and not root.resized.is_connected(_on_hud_resized):
		root.resized.connect(_on_hud_resized)
	var pause := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if pause:
		## Versus / Endless keep PauseBtn; nullsec has no pause (UI_AND_SHELL §2.2A).
		var allow_pause := GameSession == null or str(GameSession.pending_mode) != "nullsec"
		pause.visible = allow_pause
		pause.process_mode = Node.PROCESS_MODE_ALWAYS if allow_pause else Node.PROCESS_MODE_DISABLED
		if allow_pause:
			pause.text = "继续" if get_tree().paused else "暂停"
	var exit_btn := hud.get_node_or_null("Root/TopRight/ExitBtn") as Button
	if exit_btn:
		exit_btn.text = "菜单"
		exit_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_scout_intel_btn()
	var cam_btn := hud.get_node_or_null("Root/TopRight/CamModeBtn") as Button
	if cam_btn:
		cam_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_build_game_menu()
	_refresh_camera_mode_btn()

func _ensure_scout_intel_btn() -> void:
	var top_r := hud.get_node_or_null("Root/TopRight") as Control
	if top_r == null:
		return
	if top_r.get_node_or_null("ScoutIntelBtn") != null:
		return
	var btn := ScoutIntelButton.new()
	btn.name = "ScoutIntelBtn"
	btn.visible = GameSession.pending_mode == "nullsec"
	top_r.add_child(btn)
	top_r.move_child(btn, 0)

func _on_hud_resized() -> void:
	_apply_adaptive_hud_layout()
	_style_hud_chrome()
	_wire_shop_chrome()
	_apply_shop_interactable()

func _ensure_reserve_grid() -> void:
	var grid := hud.get_node_or_null("Root/LeftCol/LeftInner/LeftContent/ReserveGrid") as GridContainer
	if grid == null or grid.get_child_count() > 0:
		return
	for i in range(8):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(18, 18)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.15, 0.45, 0.22, 0.55)
		sb.set_corner_radius_all(2)
		cell.add_theme_stylebox_override("panel", sb)
		grid.add_child(cell)

func _apply_adaptive_hud_layout() -> void:
	var root := hud.get_node_or_null("Root") as Control
	if root == null:
		return
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_h := UiLayout.top_bar_height_frac()
	var left_w: float = UiLayout.collapse_strip_frac() if _collapse_left else UiLayout.left_col_width_frac()
	var right_w: float = UiLayout.collapse_strip_frac() if _collapse_right else UiLayout.right_col_width_frac()
	var bottom_h: float = UiLayout.collapse_strip_frac() if _collapse_bottom else UiLayout.bottom_shop_height_frac()
	var round_bar := root.get_node_or_null("RoundBar") as Control
	if round_bar:
		UiLayout.set_rect_frac(round_bar, 0.22, 0.008, 0.78, top_h)
	var top_r := root.get_node_or_null("TopRight") as Control
	if top_r:
		UiLayout.set_rect_frac(top_r, 0.78, 0.008, 0.992, top_h)
	var left_col := root.get_node_or_null("LeftCol") as Control
	if left_col:
		UiLayout.set_rect_frac(left_col, 0.006, top_h + 0.01, 0.006 + left_w, 1.0 - bottom_h - 0.02)
	var right_col := root.get_node_or_null("RightCol") as Control
	if right_col:
		UiLayout.set_rect_frac(right_col, 1.0 - 0.006 - right_w, top_h + 0.01, 0.994, 1.0 - bottom_h - 0.02)
	var shop_panel := root.get_node_or_null("Shop") as Control
	if shop_panel:
		UiLayout.set_bottom_strip(shop_panel, bottom_h, 0.01, 0.01, 0.008)
	var left_content := root.get_node_or_null("LeftCol/LeftInner/LeftContent") as Control
	if left_content:
		left_content.visible = not _collapse_left
	var right_content := root.get_node_or_null("RightCol/RightInner/RightContent") as Control
	if right_content:
		right_content.visible = not _collapse_right
	var shop_content := root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	if shop_content:
		shop_content.visible = not _collapse_bottom
	var cl := root.get_node_or_null("LeftCol/LeftInner/CollapseLeftBtn") as Button
	if cl:
		cl.text = "▶" if _collapse_left else "◀"
	var cr := root.get_node_or_null("RightCol/RightInner/CollapseRightBtn") as Button
	if cr:
		cr.text = "◀" if _collapse_right else "▶"
	var cb := root.get_node_or_null("Shop/ShopCol/CollapseBottomBtn") as Button
	if cb:
		cb.text = "▲" if _collapse_bottom else "▼"
	var notice := root.get_node_or_null("Notice") as Control
	if notice:
		UiLayout.set_rect_frac(notice, 0.28, 0.4, 0.72, 0.5)
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_info_panel_adaptive_layout(root)


func _apply_info_panel_adaptive_layout(root: Control) -> void:
	## Right column: scale portrait / weapon squares; mobile stacks weapon under title.
	var info := root.get_node_or_null(_INFO_PANEL) as PanelContainer
	var blog := root.get_node_or_null("RightCol/RightInner/RightContent/BattleLog") as PanelContainer
	var mobile := UiLayout.is_mobile()
	if info:
		info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		info.size_flags_stretch_ratio = 2.6 if mobile else 2.0
		var icon := info.get_node_or_null("InfoBody/InfoTop/InfoIcon") as TextureRect
		if icon:
			var isz := UiLayout.px(56 if mobile else 72, root)
			icon.custom_minimum_size = Vector2(isz, isz)
		var info_top := info.get_node_or_null("InfoBody/InfoTop") as HBoxContainer
		var body := info.get_node_or_null("InfoBody") as VBoxContainer
		var weapon_col := info.get_node_or_null("InfoBody/InfoTop/InfoWeaponColumn") as VBoxContainer
		if weapon_col == null and body:
			weapon_col = body.get_node_or_null("InfoWeaponColumn") as VBoxContainer
		if mobile and info_top and body and weapon_col != null and weapon_col.get_parent() == info_top:
			## Stack: [icon|title] then weapon/drone column full width — avoids HBox overflow.
			info_top.remove_child(weapon_col)
			var insert_at := info_top.get_index() + 1
			body.add_child(weapon_col)
			body.move_child(weapon_col, insert_at)
		elif (not mobile) and body and info_top:
			var under_body := body.get_node_or_null("InfoWeaponColumn") as VBoxContainer
			if under_body != null and under_body.get_parent() == body:
				body.remove_child(under_body)
				info_top.add_child(under_body)
		var w_parent: Control = null
		if weapon_col:
			w_parent = weapon_col
		elif info_top:
			w_parent = info_top
		if w_parent:
			var w_sq := Vector2(
				UiLayout.px(168 if mobile else 228, root),
				UiLayout.px(120 if mobile else 176, root)
			)
			var d_sq := Vector2(
				UiLayout.px(168 if mobile else 228, root),
				UiLayout.px(96 if mobile else 120, root)
			)
			var icon_sz := UiLayout.px(44 if mobile else 56, root)
			var lbl_w := UiLayout.px(110 if mobile else 150, root)
			var lbl_h := UiLayout.px(56 if mobile else 72, root)
			_resize_info_stat_square(w_parent, "InfoWeaponSquare", w_sq, icon_sz, lbl_w, lbl_h)
			_resize_info_stat_square(w_parent, "InfoDroneSquare", d_sq, icon_sz, lbl_w, lbl_h)
	if blog:
		blog.size_flags_vertical = Control.SIZE_EXPAND_FILL
		blog.size_flags_stretch_ratio = 1.0
		var scroll := blog.get_node_or_null("BattleLogInner/BattleLogScroll") as ScrollContainer
		if scroll:
			scroll.custom_minimum_size = Vector2(0, UiLayout.px(56 if mobile else 80, root))
	var cr := root.get_node_or_null("RightCol/RightInner/CollapseRightBtn") as Button
	if cr:
		cr.custom_minimum_size = Vector2(0, UiLayout.px(28, root))


func _resize_info_stat_square(
		parent: Control, square_name: String, min_size: Vector2, icon_sz: float, lbl_w: float, lbl_h: float
) -> void:
	var square := parent.get_node_or_null(square_name) as PanelContainer
	if square == null:
		return
	square.custom_minimum_size = min_size
	var row := square.get_node_or_null("%sRow" % square_name) as HBoxContainer
	if row == null:
		return
	var icon := row.get_node_or_null("%sIcon" % square_name) as TextureRect
	if icon:
		icon.custom_minimum_size = Vector2(icon_sz, icon_sz)
	var lbl := row.get_node_or_null("%sText" % square_name) as Label
	if lbl:
		lbl.custom_minimum_size = Vector2(lbl_w, lbl_h)


func _style_hud_chrome() -> void:
	var root := hud.get_node_or_null("Root") as Control
	if root == null:
		return
	for lbl_path in [
			"%s/Hp" % _ROUND, "%s/Phase" % _ROUND, "%s/Region" % _ROUND,
			"%s/Placement/TimerCol/Timer" % _ROUND, "%s/Placement/TimerCol/StageHint" % _ROUND,
			"Notice",
			"%s/LevelExp/LEInner/LELabels/Level" % _SHOP_LEFT,
			"%s/LevelExp/LEInner/LELabels/Exp" % _SHOP_LEFT,
			"%s/StatsRow/PopBox/Pop" % _SHOP_MID, "%s/StatsRow/GoldBox/Gold" % _SHOP_MID,
			"TopRight/Version",
			"RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogTitle"]:
		var l := root.get_node_or_null(lbl_path) as Label
		if l:
			var design := 22 if "Timer" in lbl_path else (
				32 if "Gold" in lbl_path else (
				26 if "Pop" in lbl_path else (
				22 if "Level" in lbl_path else 15)))
			UiAssets.apply_label_font(l, "Gold" in lbl_path or "Level" in lbl_path, UiLayout.font_size(design, root))
			l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2) if "Gold" in lbl_path else Color(0.95, 0.95, 0.9))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", UiLayout.margin_px(3, root))
	for panel_path in ["RoundBar", "LeftCol", "RightCol", "Shop"]:
		var panel := root.get_node_or_null(panel_path) as PanelContainer
		if panel:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.07, 0.09, 0.11, 0.88)
			sb.border_color = Color(0.35, 0.72, 0.85, 0.55)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			sb.set_content_margin_all(UiLayout.margin_px(6, root))
			panel.add_theme_stylebox_override("panel", sb)
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var info := root.get_node_or_null(_INFO_PANEL) as PanelContainer
	if info:
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(0.10, 0.12, 0.15, 0.0)
		sb2.border_color = Color(0.35, 0.72, 0.85, 0.38)
		sb2.set_border_width_all(1)
		sb2.set_corner_radius_all(6)
		sb2.set_content_margin_all(UiLayout.margin_px(8, root))
		info.add_theme_stylebox_override("panel", sb2)
	var blog := root.get_node_or_null("RightCol/RightInner/RightContent/BattleLog") as PanelContainer
	if blog:
		var sb3 := StyleBoxFlat.new()
		sb3.bg_color = Color(0.08, 0.12, 0.16, 0.9)
		sb3.set_corner_radius_all(4)
		sb3.set_content_margin_all(UiLayout.margin_px(6, root))
		blog.add_theme_stylebox_override("panel", sb3)
	var skip := root.get_node_or_null("%s/Placement/SkipBtn" % _ROUND) as Button
	if skip:
		UiAssets.apply_button_font(skip, UiLayout.font_size(14, root))
		skip.custom_minimum_size = Vector2(UiLayout.px(72, root), UiLayout.px(36, root))
	for btn_name in ["TopRight/PauseBtn", "TopRight/ExitBtn", "TopRight/SpeedBtn",
			"LeftCol/LeftInner/CollapseLeftBtn", "RightCol/RightInner/CollapseRightBtn",
			"Shop/ShopCol/CollapseBottomBtn"]:
		var b := root.get_node_or_null(btn_name) as Button
		if b:
			UiAssets.apply_button_font(b, UiLayout.font_size(13, root))
			b.custom_minimum_size = Vector2(UiLayout.px(56, root), UiLayout.px(28, root))
	_ensure_speed_button(root)

func _ensure_speed_button(root: Node) -> void:
	var top_r := root.get_node_or_null("TopRight") as HBoxContainer
	if top_r == null:
		return
	var btn := top_r.get_node_or_null("SpeedBtn") as Button
	if btn == null:
		btn = Button.new()
		btn.name = "SpeedBtn"
		var pause := top_r.get_node_or_null("PauseBtn")
		if pause:
			top_r.add_child(btn)
			top_r.move_child(btn, pause.get_index())
		else:
			top_r.add_child(btn)
		btn.pressed.connect(_on_speed_pressed)
	btn.visible = match_ctrl.stage == MatchController.Stage.BATTLE
	btn.text = match_ctrl.speed_label()
	if GameSession.pending_mode == "nullsec":
		btn.tooltip_text = "战斗倍速（下拉投票）"
	else:
		btn.tooltip_text = "战斗倍速（点按循环）"

func _wire_shop_chrome() -> void:
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	# 按钮素材为横图（约 198×69）；宽度保持原设计，高度按比例，禁止再塞进正方形造成下方空白
	var btn_w := UiLayout.px(144 if UiLayout.is_mobile() else 162, root)
	_style_image_button(root.get_node_or_null("%s/LeftBtns/ExpBtn" % _SHOP_LEFT) as Button,
			UiAssets.shop_exp_path(), "购买经验", int(DataStore.economy.get("buy_exp_gold_cost", 4)), btn_w)
	_wire_exp_hold(root.get_node_or_null("%s/LeftBtns/ExpBtn" % _SHOP_LEFT) as Button)
	_style_image_button(root.get_node_or_null("%s/LeftBtns/RefreshBtn" % _SHOP_LEFT) as Button,
			UiAssets.shop_refresh_path(), "刷新商店", int(DataStore.economy.get("refresh_cost", 2)), btn_w)
	var lock := root.get_node_or_null("%s/StatsRow/LockBtn" % _SHOP_MID) as Button
	if lock:
		var t := UiAssets.tex(UiAssets.ICON_LOCK)
		if t:
			lock.icon = t
			lock.expand_icon = true
		lock.text = ""
		UiAssets.apply_button_font(lock, UiLayout.font_size(14, root))
		lock.custom_minimum_size = Vector2(UiLayout.px(52, root), UiLayout.px(44, root))
	_ensure_meta_icon(root.get_node_or_null("%s/StatsRow/GoldBox" % _SHOP_MID) as HBoxContainer, "Gold", UiAssets.ICON_MONEY, 36)
	_ensure_meta_icon(root.get_node_or_null("%s/StatsRow/PopBox" % _SHOP_MID) as HBoxContainer, "Pop", UiAssets.ICON_POP, 36)
	var btn_h := btn_w * (69.0 / 198.0)  # 与素材比例一致
	var le := root.get_node_or_null("%s/LevelExp" % _SHOP_LEFT) as PanelContainer
	if le:
		# 等级框贴合内容，高度不超过按钮行
		var le_h := minf(UiLayout.px(64 if UiLayout.is_mobile() else 68, root), ceilf(btn_h) + float(UiLayout.margin_px(8, root)))
		le.custom_minimum_size = Vector2(UiLayout.px(208, root), le_h)
		le.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var le_inner := le.get_node_or_null("LEInner") as VBoxContainer
		if le_inner:
			le_inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			le_inner.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		var le_sb := StyleBoxFlat.new()
		le_sb.bg_color = Color(0.05, 0.08, 0.1, 0.75)
		le_sb.border_color = Color(0.25, 0.55, 0.7, 0.55)
		le_sb.set_border_width_all(1)
		le_sb.set_corner_radius_all(4)
		le_sb.content_margin_left = UiLayout.margin_px(8, root)
		le_sb.content_margin_right = UiLayout.margin_px(8, root)
		le_sb.content_margin_top = UiLayout.margin_px(4, root)
		le_sb.content_margin_bottom = UiLayout.margin_px(4, root)
		le.add_theme_stylebox_override("panel", le_sb)
	var left_ctrl := root.get_node_or_null(_SHOP_LEFT) as Control
	if left_ctrl:
		# 宽度保留；高度跟内容走，禁止再锁 162 把 MetaRow 撑出空白带
		left_ctrl.custom_minimum_size = Vector2(UiLayout.px(560, root), 0)
		left_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if left_ctrl is BoxContainer:
			(left_ctrl as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	var left_btns := root.get_node_or_null("%s/LeftBtns" % _SHOP_LEFT) as Control
	if left_btns:
		left_btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var seg_row := root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as HBoxContainer
	if seg_row:
		seg_row.custom_minimum_size = Vector2(0, UiLayout.px(18, root))
		seg_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var meta_row := root.get_node_or_null(_SHOP_META) as HBoxContainer
	if meta_row:
		meta_row.alignment = BoxContainer.ALIGNMENT_CENTER
		meta_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		meta_row.add_theme_constant_override("separation", UiLayout.margin_px(10, root))
	var shop_content := root.get_node_or_null("Shop/ShopCol/ShopContent") as VBoxContainer
	if shop_content:
		shop_content.add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	var stats := root.get_node_or_null("%s/StatsRow" % _SHOP_MID) as HBoxContainer
	if stats:
		stats.alignment = BoxContainer.ALIGNMENT_CENTER
		stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sell := root.get_node_or_null("%s/SellZone" % _SHOP_INNER) as PanelContainer
	if sell:
		sell.custom_minimum_size = Vector2(UiLayout.px(120, root), 0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.22, 0.25, 0.92)
		sb.border_color = Color(0.4, 0.75, 0.9, 0.7)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sell.add_theme_stylebox_override("panel", sb)

func _ensure_meta_icon(box: HBoxContainer, for_name: String, tex_path: String, design_px: int = 20) -> void:
	if box == null:
		return
	for c in box.get_children():
		if c is TextureRect and c.has_meta("meta_icon_for") and str(c.get_meta("meta_icon_for")) == for_name:
			var existing_icon_sz := UiLayout.px(float(design_px), box)
			(c as TextureRect).custom_minimum_size = Vector2(existing_icon_sz, existing_icon_sz)
			return
	var icon := TextureRect.new()
	icon.set_meta("meta_icon_for", for_name)
	var new_icon_sz := UiLayout.px(float(design_px), box)
	icon.custom_minimum_size = Vector2(new_icon_sz, new_icon_sz)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t := UiAssets.tex(tex_path)
	if t:
		icon.texture = t
	box.add_child(icon)
	box.move_child(icon, 0)

func _refresh_exp_segments(root: Node) -> void:
	var row := root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as HBoxContainer
	if row == null:
		return
	for c in row.get_children():
		row.remove_child(c)
		c.free()
	var demand := maxi(1, match_ctrl.up_level_demand)
	var exp_now := clampi(match_ctrl.player_exp, 0, demand)
	var seg_h := UiLayout.px(18, row)
	## Cap visual segments so high-level demands (e.g. 124 at Lv16) stay readable.
	var slots := demand if demand <= 16 else 16
	var filled := exp_now if demand <= 16 else int(round(float(exp_now) / float(demand) * float(slots)))
	row.add_theme_constant_override("separation", UiLayout.margin_px(4, row))
	row.custom_minimum_size = Vector2(0, seg_h)
	for i in range(slots):
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.custom_minimum_size = Vector2(UiLayout.px(10, row), seg_h)
		var sb := StyleBoxFlat.new()
		if i < filled:
			sb.bg_color = Color(0.0, 0.78, 1.0, 1.0)
			sb.border_color = Color(0.55, 0.92, 1.0, 0.95)
		else:
			sb.bg_color = Color(0.04, 0.16, 0.24, 0.92)
			sb.border_color = Color(0.22, 0.48, 0.62, 0.9)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(0)
		cell.add_theme_stylebox_override("panel", sb)
		row.add_child(cell)
	var legacy := root.get_node_or_null("%s/LevelExp/LEInner/ExpBar" % _SHOP_LEFT) as ProgressBar
	if legacy:
		legacy.visible = false

func _style_image_button(btn: Button, tex_path: String, title: String, cost: int, width_px: float = -1.0) -> void:
	if btn == null:
		return
	# Image-only: art fills the control; cost stays in tooltip / accessibility.
	btn.text = ""
	btn.tooltip_text = "%s  %d" % [title, cost]
	var w := width_px if width_px > 0.0 else UiLayout.px(72 if UiLayout.is_mobile() else 88, btn)
	var h := w
	var t := UiAssets.tex(tex_path)
	if t and t.get_width() > 0 and t.get_height() > 0:
		# 横图按比例定高，避免正方形 min_size 在图标下方留出大块空白
		h = w * (float(t.get_height()) / float(t.get_width()))
	btn.custom_minimum_size = Vector2(w, h)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if t:
		btn.icon = t
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	# Allow large icons to fill the button face.
	btn.add_theme_constant_override("icon_max_width", int(w))
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("disabled", empty)

func show_notice(text: String) -> void:
	AdminBus.request(&"ui.notice", {"text": text})
	_append_battle_log(text)
	var lbl := hud.get_node_or_null("Root/Notice") as Label
	if lbl:
		lbl.text = text
		lbl.visible = true
		get_tree().create_timer(2.0).timeout.connect(func(): if lbl: lbl.visible = false)

func append_battle_log(text: String) -> void:
	## Battle-log only (no floating notice) — used by AI sell / combat breadcrumbs.
	_append_battle_log(text)

func on_ship_sold(gold: int) -> void:
	match_ctrl.add_gold(gold)
	show_notice("出售获得 %d PLEX" % gold)
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_refresh_hud()

func _refresh_hud() -> void:
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	_set_label(root, "%s/Hp" % _ROUND, _player_hp_label_text())
	_refresh_citadel_bar()
	_set_label(root, "%s/Phase" % _ROUND, "阶段 %d-%d" % [match_ctrl.battle_phase_value, match_ctrl.round_phase_value])
	_refresh_region_label()
	_set_label(root, "%s/StatsRow/GoldBox/Gold" % _SHOP_MID, "%d" % match_ctrl.player_gold)
	_set_label(root, "%s/StatsRow/PopBox/Pop" % _SHOP_MID, "%d/%d" % [board.count_field(ShipUnit.TEAM_PLAYER), match_ctrl.population_limit()])
	_set_label(root, "%s/LevelExp/LEInner/LELabels/Level" % _SHOP_LEFT, "%d级" % match_ctrl.player_level)
	_set_label(root, "%s/LevelExp/LEInner/LELabels/Exp" % _SHOP_LEFT, "%d / %d" % [match_ctrl.player_exp, match_ctrl.up_level_demand])
	_refresh_exp_segments(root)
	var lock := root.get_node_or_null("%s/StatsRow/LockBtn" % _SHOP_MID) as Button
	if lock:
		lock.set_pressed_no_signal(match_ctrl.shop_locked)
	var stage_name := "准备" if match_ctrl.stage == MatchController.Stage.PREPARE else ("战斗" if match_ctrl.stage == MatchController.Stage.BATTLE else "结束")
	var ttext := "倒计时"
	if match_ctrl.stage == MatchController.Stage.PREPARE:
		ttext = "%.0f" % match_ctrl.prepare_remaining()
	elif match_ctrl.stage == MatchController.Stage.BATTLE:
		ttext = "%.0f" % match_ctrl.battle_remaining()
	_set_label(root, "%s/Placement/TimerCol/Timer" % _ROUND, ttext)
	_set_label(root, "%s/Placement/TimerCol/StageHint" % _ROUND, stage_name)
	var speed_btn := root.get_node_or_null("TopRight/SpeedBtn") as Button
	if speed_btn:
		speed_btn.visible = match_ctrl.stage == MatchController.Stage.BATTLE
		speed_btn.text = match_ctrl.speed_label()
	var skip := root.get_node_or_null("%s/Placement/SkipBtn" % _ROUND) as Button
	if skip:
		skip.visible = match_ctrl.stage == MatchController.Stage.PREPARE
		skip.disabled = match_ctrl.stage != MatchController.Stage.PREPARE
	_apply_shop_interactable()
	_refresh_fetter_ui(root)
	var ver := root.get_node_or_null("TopRight/Version") as Label
	if ver:
		ver.text = "壳 %s | 热更 %s" % [str(ProjectSettings.get_setting("application/config/version", "dev")), DataStore.content_version]

func _apply_shop_interactable() -> void:
	## Shop stays interactive in Prepare and Battle (no grey-lock).
	var root := hud.get_node_or_null("Root")
	if root == null:
		return
	for path in [
			"%s/LeftBtns/ExpBtn" % _SHOP_LEFT,
			"%s/LeftBtns/RefreshBtn" % _SHOP_LEFT,
			"%s/StatsRow/LockBtn" % _SHOP_MID]:
		var b := root.get_node_or_null(path) as Button
		if b:
			b.disabled = false
			b.modulate = Color(1, 1, 1, 1)
	var slots := root.get_node_or_null(_SHOP_SLOTS) as Control
	if slots:
		slots.modulate = Color(1, 1, 1, 1)
		for c in slots.get_children():
			_set_shop_card_interactable(c, true)

func _set_shop_card_interactable(card: Node, enabled: bool) -> void:
	if card == null:
		return
	for child in card.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not enabled
			(child as BaseButton).mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		_set_shop_card_interactable(child, enabled)
func _refresh_fetter_ui(root: Node) -> void:
	var side := root.get_node_or_null(_BONUS) as VBoxContainer
	if side == null:
		return
	var list := side.get_node_or_null("FetterList") as VBoxContainer
	if list == null:
		var old := side.get_node_or_null("Fetters") as Label
		if old:
			old.visible = false
		list = VBoxContainer.new()
		list.name = "FetterList"
		list.add_theme_constant_override("separation", 6)
		side.add_child(list)
	for c in list.get_children():
		c.queue_free()
	var fetters: Array = board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	for a in fetters:
		var fid := str(a.get("fetter_id", ""))
		var fdata: Dictionary = DataStore.fetters.get(fid, {})
		var fname := str(fdata.get("name", fid))
		var count := int(a.get("count", 0))
		var eff: Dictionary = a.get("effect", {})
		var need := int(eff.get("champion_count", 0))
		var is_meta := bool(a.get("meta", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(UiLayout.px(26, list), UiLayout.px(26, list))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex := UiAssets.fetter_icon(fid, fname)
		if tex:
			icon.texture = tex
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		var lab := Label.new()
		## Titan fetter is always on and has no Field count to show (MULTIPLAYER_PVP §2.3).
		if is_meta:
			lab.text = fname
		else:
			lab.text = "%s %d/%d" % [fname, count, need] if need > 0 else "%s %d" % [fname, count]
		UiAssets.apply_label_font(lab, false, UiLayout.font_size(15, list))
		lab.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 3)
		col.add_child(lab)
		## Meta titans list every effect (combat +10% shop race); field fetters keep one tier.
		var effect_lines: Array = []
		if is_meta:
			for e in (fdata.get("effects", []) as Array):
				if typeof(e) == TYPE_DICTIONARY:
					effect_lines.append(e)
		else:
			effect_lines.append(eff)
		for e in effect_lines:
			var eff_txt := UiAssets.fetter_effect_text(e as Dictionary)
			if eff_txt == "":
				continue
			var elab := Label.new()
			elab.text = eff_txt
			elab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UiAssets.apply_label_font(elab, false, UiLayout.font_size(12, list))
			elab.add_theme_color_override("font_color", Color(0.55, 0.92, 0.72))
			elab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			elab.add_theme_constant_override("outline_size", 2)
			col.add_child(elab)
		row.add_child(col)
		list.add_child(row)

func _set_label(root: Node, path: String, text: String) -> void:
	var l := root.get_node_or_null(path) as Label
	if l:
		l.text = text

func _refresh_shop_ui() -> void:
	var box := hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as HBoxContainer
	if box == null:
		return
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c in box.get_children():
		c.queue_free()
	var slot_count := maxi(1, shop.slots.size())
	var card_size := _shop_card_size(slot_count, box)
	for i in range(shop.slots.size()):
		var slot: Dictionary = shop.slots[i]
		var sid := int(slot.get("ship_id", 0))
		var ship: Dictionary = DataStore.get_ship(sid)
		var purchased := bool(slot.get("purchased", false))
		var ship_name := str(ship.get("name", "?"))
		var cost := int(ship.get("cost", 0))
		var card := _make_shop_card(ship_name, ship, purchased, cost, i, card_size)
		box.add_child(card)
	if not _dragging_sell_ui:
		_set_sell_mode(false)
	_apply_shop_interactable()

func _local_titan_race_for_ui() -> String:
	## Industrial tips_ore variant may follow the local nullsec titan race.
	if GameSession == null or GameSession.pending_mode != "nullsec":
		return ""
	var race := str(GameSession.pending_nullsec.get("local_titan_race", ""))
	if race != "":
		return race
	if typeof(GameSession.pending_nullsec.get("seats", null)) != TYPE_ARRAY:
		return ""
	var seats: Array = GameSession.pending_nullsec.get("seats", [])
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", 0))
	for s in seats:
		if typeof(s) == TYPE_DICTIONARY and int((s as Dictionary).get("seat_id", -1)) == local_seat:
			return str((s as Dictionary).get("titan_race", ""))
	return ""

func _shop_card_size(slot_count: int, box: Control) -> Vector2:
	var avail_w := box.size.x
	var avail_h := box.size.y
	if avail_w < 8.0 or avail_h < 8.0:
		var shop_panel := hud.get_node_or_null("Root/Shop") as Control
		if shop_panel:
			avail_w = shop_panel.size.x * 0.88
			avail_h = shop_panel.size.y * 0.62
	if avail_w < 8.0:
		avail_w = UiLayout.px(1100.0, box)
	if avail_h < 8.0:
		avail_h = UiLayout.px(160.0, box)
	var sep := float(UiLayout.margin_px(6, box))
	var total_sep := sep * float(maxi(0, slot_count - 1))
	var w := (avail_w - total_sep) / float(slot_count)
	var min_w := UiLayout.px(88.0 if UiLayout.is_mobile() else 100.0, box)
	var max_w := UiLayout.px(180.0 if UiLayout.is_mobile() else 210.0, box)
	var min_h := UiLayout.px(120.0 if UiLayout.is_mobile() else 140.0, box)
	var max_h := UiLayout.px(180.0 if UiLayout.is_mobile() else 210.0, box)
	return Vector2(clampf(w, min_w, max_w), clampf(avail_h, min_h, max_h))

func _make_shop_card(ship_name: String, ship: Dictionary, purchased: bool, cost: int, idx: int, card_size: Vector2 = Vector2.ZERO) -> Control:
	var card := PanelContainer.new()
	var sz := card_size if card_size.x > 0.0 else Vector2(UiLayout.px(140, card), UiLayout.px(170, card))
	card.custom_minimum_size = sz
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titan_race := _local_titan_race_for_ui()
	var tips_tex: Texture2D = null if purchased else UiAssets.shop_card_tips_skybox(ship, titan_race)
	var outer := StyleBoxFlat.new()
	## When tips fill the card, keep only a thin border — don't paint an opaque plate over the nebula.
	if tips_tex != null:
		outer.bg_color = Color(0.08, 0.09, 0.12, 0.35)
	else:
		outer.bg_color = Color(0.14, 0.16, 0.18, 0.98)
	outer.border_color = Color(0.4, 0.65, 0.78, 0.95)
	outer.set_border_width_all(2)
	outer.set_corner_radius_all(5)
	outer.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", outer)
	var stack := Control.new()
	stack.custom_minimum_size = sz
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(stack)
	if purchased:
		var done := Label.new()
		done.text = "已购"
		done.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiAssets.apply_label_font(done, false, UiLayout.font_size(20, card))
		done.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
		stack.add_child(done)
		return card
	## UI_AND_SHELL §2.1.1: tips skybox under ISIS portrait (keep source alpha fade).
	if tips_tex:
		var tips := TextureRect.new()
		tips.name = "TipsSkybox"
		tips.texture = tips_tex
		tips.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tips.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(tips)
	# Large centered portrait (leave room below for fetter strip + name)
	var psz := minf(sz.x * 0.88, sz.y * 0.58)
	psz = maxf(psz, UiLayout.px(72 if UiLayout.is_mobile() else 90, card))
	var tex := UiAssets.champion_icon(ship_name, int(ship.get("id", 0)))
	var art: Control
	if tex:
		var art_rect := TextureRect.new()
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_rect.texture = tex
		art = art_rect
	else:
		var ph := ColorRect.new()
		ph.color = Color(0.12, 0.16, 0.24, 1.0)
		art = ph
	art.custom_minimum_size = Vector2(psz, psz)
	art.set_anchors_preset(Control.PRESET_CENTER_TOP)
	art.anchor_left = 0.5
	art.anchor_right = 0.5
	art.offset_left = -psz * 0.5
	art.offset_right = psz * 0.5
	art.offset_top = UiLayout.px(28, card)
	art.offset_bottom = art.offset_top + psz
	stack.add_child(art)
	# 本舰可达成羁绊 · 立绘下方简展
	var fids: Array = ship.get("fetter_ids", [])
	var badge_icon := UiLayout.px(18 if UiLayout.is_mobile() else 22, card)
	var fetter_box := HBoxContainer.new()
	fetter_box.add_theme_constant_override("separation", UiLayout.margin_px(3, card))
	fetter_box.alignment = BoxContainer.ALIGNMENT_CENTER
	fetter_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	fetter_box.anchor_left = 0.0
	fetter_box.anchor_right = 1.0
	fetter_box.offset_left = UiLayout.px(4, card)
	fetter_box.offset_right = -UiLayout.px(4, card)
	fetter_box.offset_top = art.offset_bottom + UiLayout.px(2, card)
	fetter_box.offset_bottom = fetter_box.offset_top + badge_icon + 2.0
	for fid in fids:
		var fdata: Dictionary = DataStore.fetters.get(str(fid), {})
		var fname := str(fdata.get("name", fid))
		var fic := TextureRect.new()
		fic.custom_minimum_size = Vector2(badge_icon, badge_icon)
		fic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fic.tooltip_text = fname
		var ft := UiAssets.fetter_icon(str(fid), fname)
		if ft:
			fic.texture = ft
		else:
			# 无图时用色块占位，避免空白缺口
			var ph2 := ColorRect.new()
			ph2.custom_minimum_size = Vector2(badge_icon, badge_icon)
			ph2.color = Color(0.35, 0.4, 0.48, 0.9)
			ph2.tooltip_text = fname
			fetter_box.add_child(ph2)
			continue
		fetter_box.add_child(fic)
	stack.add_child(fetter_box)
	# Name under fetter strip
	var name_l := Label.new()
	name_l.text = ship_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -UiLayout.px(28, card)
	name_l.offset_bottom = -UiLayout.px(4, card)
	name_l.offset_left = UiLayout.px(4, card)
	name_l.offset_right = -UiLayout.px(4, card)
	UiAssets.apply_label_font(name_l, false, UiLayout.font_size(14, card))
	name_l.add_theme_color_override("font_color", Color(1, 1, 1))
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_l.add_theme_constant_override("outline_size", 3)
	stack.add_child(name_l)
	# ★ 角标 · 左上
	var star_badge := _make_corner_badge("★1", Color(0.12, 0.1, 0.05, 0.92), Color(1.0, 0.88, 0.35), card)
	star_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	star_badge.offset_left = UiLayout.px(4, card)
	star_badge.offset_top = UiLayout.px(4, card)
	star_badge.offset_right = star_badge.offset_left + UiLayout.px(42, card)
	star_badge.offset_bottom = star_badge.offset_top + UiLayout.px(24, card)
	stack.add_child(star_badge)
	# 价格角标 · 右下
	var cost_badge := PanelContainer.new()
	var cost_sb := StyleBoxFlat.new()
	cost_sb.bg_color = Color(0.05, 0.08, 0.1, 0.92)
	cost_sb.border_color = Color(0.85, 0.7, 0.25, 0.9)
	cost_sb.set_border_width_all(1)
	cost_sb.set_corner_radius_all(4)
	cost_sb.set_content_margin_all(UiLayout.margin_px(4, card))
	cost_badge.add_theme_stylebox_override("panel", cost_sb)
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", UiLayout.margin_px(3, card))
	cost_badge.add_child(cost_row)
	var money := TextureRect.new()
	money.custom_minimum_size = Vector2(UiLayout.px(16, card), UiLayout.px(16, card))
	money.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	money.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mt := UiAssets.tex(UiAssets.ICON_MONEY)
	if mt:
		money.texture = mt
	cost_row.add_child(money)
	var cost_l := Label.new()
	cost_l.text = str(cost)
	UiAssets.apply_label_font(cost_l, false, UiLayout.font_size(15, card))
	cost_l.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	cost_row.add_child(cost_l)
	cost_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cost_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cost_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cost_badge.offset_right = -UiLayout.px(4, card)
	cost_badge.offset_bottom = -UiLayout.px(30, card)
	cost_badge.offset_left = cost_badge.offset_right - UiLayout.px(56, card)
	cost_badge.offset_top = cost_badge.offset_bottom - UiLayout.px(26, card)
	stack.add_child(cost_badge)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if UiLayout.is_mobile():
		## Mobile: tap = ship info + drag-to-hangar tip; drag onto hangar = buy; long-press = preview.
		hit.gui_input.connect(func(ev): _shop_gui_input(ev, idx, hit))
	else:
		hit.pressed.connect(func():
			shop.try_buy(idx)
			_refresh_shop_ui()
			_refresh_hud()
		)
		hit.mouse_entered.connect(func(): _show_ship_info_id(int(ship.get("id", 0))))
	stack.add_child(hit)
	return card

func _make_corner_badge(text: String, bg: Color, fg: Color, from: Node) -> PanelContainer:
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(UiLayout.margin_px(4, from))
	badge.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiAssets.apply_label_font(lab, false, UiLayout.font_size(13, from))
	lab.add_theme_color_override("font_color", fg)
	badge.add_child(lab)
	return badge

func _shop_card_height(slot_count: int, box: Control) -> float:
	return _shop_card_size(slot_count, box).y

func _shop_gui_input(ev: InputEvent, idx: int, from: Control = null) -> void:
	if not UiLayout.is_mobile():
		return
	## Press starts here; drag/release continue in `_input` so finger can leave the card.
	var screen := _shop_event_screen(ev, from)
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_shop_begin_press(idx, screen)
			if from:
				from.accept_event()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			_shop_begin_press(idx, screen)
			if from:
				from.accept_event()


func _input(event: InputEvent) -> void:
	if _shop_drag_idx < 0 or not UiLayout.is_mobile():
		return
	if event is InputEventScreenDrag:
		_shop_update_drag(_shop_drag_idx, (event as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			_shop_end_press(_shop_drag_idx, st.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_shop_update_drag(_shop_drag_idx, (event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			_shop_end_press(_shop_drag_idx, mb.position)
			get_viewport().set_input_as_handled()


func _shop_event_screen(ev: InputEvent, from: Control) -> Vector2:
	var local := Vector2.ZERO
	if ev is InputEventScreenTouch:
		local = (ev as InputEventScreenTouch).position
	elif ev is InputEventScreenDrag:
		local = (ev as InputEventScreenDrag).position
	elif ev is InputEventMouseButton:
		local = (ev as InputEventMouseButton).position
	elif ev is InputEventMouseMotion:
		local = (ev as InputEventMouseMotion).position
	if from:
		return from.get_global_transform_with_canvas() * local
	return local


func _shop_begin_press(idx: int, screen: Vector2) -> void:
	_shop_drag_idx = idx
	_shop_drag_active = false
	_shop_long_previewed = false
	_shop_press_screen = screen
	_long_press_slot = idx
	_long_press_t = Time.get_ticks_msec() / 1000.0


func _shop_update_drag(idx: int, screen: Vector2) -> void:
	if _shop_drag_idx != idx:
		return
	var dist := screen.distance_to(_shop_press_screen)
	if not _shop_drag_active and dist >= _SHOP_DRAG_THRESHOLD_PX:
		_shop_drag_active = true
		_long_press_slot = -1  # cancel long-press preview once dragging
		_ensure_shop_ghost(idx)
	if _shop_drag_active:
		_move_shop_ghost(screen)
	elif _long_press_slot == idx and not _shop_long_previewed:
		var held := Time.get_ticks_msec() / 1000.0 - _long_press_t
		if held >= 0.35:
			_shop_long_previewed = true
			if idx >= 0 and idx < shop.slots.size():
				_show_ship_info_id(int(shop.slots[idx].get("ship_id", 0)))


func _shop_end_press(idx: int, screen: Vector2) -> void:
	if _shop_drag_idx != idx:
		_shop_clear_drag()
		return
	var was_drag := _shop_drag_active
	var previewed := _shop_long_previewed
	_shop_clear_drag()
	if was_drag:
		var slot := _shop_pick_hangar_at_screen(screen)
		if not slot.is_empty() and str(slot.get("slot_type", "")) == "hangar":
			shop.try_buy(idx)
			_refresh_shop_ui()
			_refresh_hud()
		else:
			show_notice(_SHOP_BUY_TIP)
		return
	if previewed:
		return
	## Plain tap: open ship info (mobile primary detail path) + buy tip. No purchase.
	if idx >= 0 and idx < shop.slots.size():
		_show_ship_info_id(int(shop.slots[idx].get("ship_id", 0)))
	show_notice(_SHOP_BUY_TIP)


func _shop_clear_drag() -> void:
	_shop_drag_idx = -1
	_shop_drag_active = false
	_long_press_slot = -1
	_shop_long_previewed = false
	if _shop_ghost and is_instance_valid(_shop_ghost):
		_shop_ghost.queue_free()
	_shop_ghost = null


func _ensure_shop_ghost(idx: int) -> void:
	if _shop_ghost and is_instance_valid(_shop_ghost):
		return
	var root := hud.get_node_or_null("Root") as Control
	if root == null:
		return
	var ghost := PanelContainer.new()
	ghost.name = "ShopDragGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 80
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.16, 0.22, 0.88)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	ghost.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ship_id := 0
	if idx >= 0 and idx < shop.slots.size():
		ship_id = int(shop.slots[idx].get("ship_id", 0))
	var ship: Dictionary = DataStore.get_ship(ship_id) if ship_id > 0 else {}
	lab.text = str(ship.get("name", "舰船"))
	UiAssets.apply_label_font(lab, false, UiLayout.font_size(16, root))
	lab.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	ghost.add_child(lab)
	ghost.custom_minimum_size = Vector2(UiLayout.px(120, root), UiLayout.px(48, root))
	root.add_child(ghost)
	_shop_ghost = ghost


func _move_shop_ghost(screen: Vector2) -> void:
	if _shop_ghost == null or not is_instance_valid(_shop_ghost):
		return
	var half := _shop_ghost.custom_minimum_size * 0.5
	_shop_ghost.global_position = screen - half


func _shop_pick_hangar_at_screen(screen: Vector2) -> Dictionary:
	if camera == null or board == null:
		return {}
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return {}
	var t := -origin.y / dir.y
	var world := origin + dir * t
	var slot := board.pick_slot_at(world, ShipUnit.TEAM_PLAYER)
	if str(slot.get("slot_type", "")) == "hangar":
		return slot
	## Slightly looser: nearest hangar cell within 3.5 wu.
	var best := {}
	var best_d := 3.5
	var hw := int(DataStore.board.get("hangar_width", 15))
	for x in range(hw):
		var p := board.cell_to_world("hangar", ShipUnit.TEAM_PLAYER, x, 0)
		var d := Vector2(world.x - p.x, world.z - p.z).length()
		if d < best_d:
			best_d = d
			best = {"slot_type": "hangar", "x": x, "z": 0, "team": ShipUnit.TEAM_PLAYER}
	return best


func _set_sell_mode(active: bool, price: int = 0) -> void:
	var slots := hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as Control
	var sell := hud.get_node_or_null("Root/%s/SellZone" % _SHOP_INNER) as PanelContainer
	if slots:
		slots.visible = not active
	if sell:
		sell.visible = active
		var lab := sell.get_node_or_null("SellLabel") as Label
		if lab:
			lab.text = "售价  %d" % price if active else "售价"
			UiAssets.apply_label_font(lab, false, 22)

func _on_drag_begin(ship: ShipUnit) -> void:
	board.begin_drag(ship)
	_drag_info_ship = ship
	_dragging_sell_ui = true
	var price := 0
	if ship:
		price = ship.get_sell_price()
	_set_sell_mode(true, price)

func _on_drag_move(world_pos: Vector3) -> void:
	board.update_drag(world_pos)

func _on_drag_end(sell: bool, slot: Dictionary) -> void:
	board.end_drag(sell, slot)
	var team := int(slot.get("team", ShipUnit.TEAM_PLAYER))
	board.recalculate_fetters(team)
	_dragging_sell_ui = false
	_set_sell_mode(false)
	_refresh_shop_ui()
	if match_ctrl and match_ctrl.has_method("request_autosave"):
		match_ctrl.request_autosave()
	_refresh_hud()
	## Drag release counts as "selected this unit" — pin its detail (UI_AND_SHELL §2.5).
	if not sell and _drag_info_ship != null and is_instance_valid(_drag_info_ship):
		_show_ship_info(_drag_info_ship)
		_pin_ship_info()
	_drag_info_ship = null

func _on_tap_ship(ship: ShipUnit) -> void:
	_show_ship_info(ship)
	if ship:
		_pin_ship_info()

func _on_hover_ship(ship: ShipUnit) -> void:
	if ship:
		## Hovering a new unit ends the hold and hands the panel back to hover rules.
		_info_hold_until_ms = 0
		_show_ship_info(ship)
		return
	## Fallback: nullsec berth titans are not board-registered.
	var berth_unit := _pick_berth_unit_under_cursor()
	if berth_unit:
		_info_hold_until_ms = 0
		_show_ship_info(berth_unit)
		return
	if _info_hold_active():
		return
	_hide_ship_info()

func _pin_ship_info() -> void:
	_info_hold_until_ms = Time.get_ticks_msec() + int(INFO_HOLD_S * 1000.0)

func _info_hold_active() -> bool:
	return _info_hold_until_ms > 0 and Time.get_ticks_msec() < _info_hold_until_ms

func _tick_info_hold() -> void:
	if _info_hold_until_ms <= 0 or Time.get_ticks_msec() < _info_hold_until_ms:
		return
	_info_hold_until_ms = 0
	var hovered: ShipUnit = pointer.hovered_ship() if pointer else null
	if hovered != null and is_instance_valid(hovered):
		_show_ship_info(hovered)
		return
	_hide_ship_info()

func _pick_berth_unit_under_cursor() -> ShipUnit:
	if camera == null:
		return null
	var screen := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	for berth in [_titan_berth, _rival_titan_berth]:
		if berth == null or not is_instance_valid(berth):
			continue
		if berth.pick_hits_ray(origin, dir) and berth.unit and is_instance_valid(berth.unit):
			return berth.unit
	return null

func _play_titan_berth_intro() -> void:
	## §2.5: head-down camera + slide berth in from offscreen once.
	if _nullsec_spectating:
		_titan_intro_done = true
		return
	if _titan_intro_done or GameSession.pending_mode != "nullsec":
		return
	if _titan_berth == null or not is_instance_valid(_titan_berth):
		_titan_intro_done = true
		return
	if _camera_manual_pose():
		_titan_intro_done = true
		return
	_titan_intro_end = _titan_berth.position
	_titan_intro_start = _titan_intro_end + Vector3(0, 0, 28.0)
	_titan_berth.position = _titan_intro_start
	_titan_berth.set_engine_trail_emitting(true)
	_titan_intro_pitch0 = _cam_base_pitch_deg
	## Head down (more negative pitch).
	_cam_base_pitch_deg = minf(_cam_base_pitch_deg, _cam_base_pitch_deg - 12.0)
	_titan_intro_t = 0.0

func _tick_titan_intro(delta: float) -> void:
	if _titan_intro_t < 0.0 or _titan_berth == null or not is_instance_valid(_titan_berth):
		return
	if _camera_manual_pose():
		_titan_berth.position = _titan_intro_end
		_titan_berth.set_engine_trail_emitting(false)
		_titan_intro_t = -1.0
		_titan_intro_done = true
		return
	var dur := 1.35
	_titan_intro_t += delta
	var u := clampf(_titan_intro_t / dur, 0.0, 1.0)
	## Smoothstep.
	u = u * u * (3.0 - 2.0 * u)
	_titan_berth.position = _titan_intro_start.lerp(_titan_intro_end, u)
	_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, _titan_intro_pitch0, u)
	if u >= 1.0:
		_titan_berth.position = _titan_intro_end
		_titan_berth.set_engine_trail_emitting(false)
		_cam_base_pitch_deg = _titan_intro_pitch0
		_titan_intro_t = -1.0
		_titan_intro_done = true
		if _titan_berth.has_method("place_tonnage_badge"):
			_titan_berth.place_tonnage_badge()

func _on_long_press_shop(idx: int) -> void:
	if idx >= 0 and idx < shop.slots.size():
		_show_ship_info_id(int(shop.slots[idx].get("ship_id", 0)))

func _weapon_kind_label(kind: String) -> String:
	match kind:
		"rail":
			return "磁轨"
		"cannon":
			return "火炮"
		"missile":
			return "导弹"
		"heal":
			return "维修"
		_:
			return "激光"

func _weapon_size_label(ship_data: Dictionary) -> String:
	var tier := str(ship_data.get("weapon_tier", ""))
	if tier == "large":
		return "大"
	if tier == "small":
		return "小"
	if tier == "medium":
		return "中"
	var ship_group := str(ship_data.get("ship_group", ""))
	match ship_group:
		"frigate", "destroyer":
			return "小"
		"cruiser", "battlecruiser":
			return "中"
		"battleship":
			return "大"
		_:
			return ""

func _weapon_module_type_id(ship_data: Dictionary) -> int:
	var fx: String = str(ship_data.get("weapon_fx", "laser"))
	var source_weapon := int(ship_data.get("source_module_type_id", 0))
	if fx == "heal":
		## Medium/large remote repair reuse small-tier icons (art parity).
		return _repair_icon_type_id(int(ship_data.get("source_repair_module_type_id", 0)))
	var group := str(ship_data.get("ship_group", "frigate"))
	var tier := str(ship_data.get("weapon_tier", ""))
	var large := tier == "large" or group == "battleship"
	var medium := tier == "medium" or (tier == "" and (group == "cruiser" or group == "battlecruiser"))
	## Prefer Echoes-tier icons: medium missile must not share large missile art.
	if fx == "missile" and medium and (source_weapon == 501 or source_weapon == 499 or source_weapon == 0):
		return 120300101
	if source_weapon > 0:
		return source_weapon
	match fx:
		"laser":
			if large:
				return 462
			if medium:
				return 456
			return 453
		"rail":
			if large:
				return 574
			if medium:
				return 570
			return 561
		"cannon":
			if large:
				return 498
			if medium:
				return 491
			return 485
		"missile":
			if large:
				return 501
			if medium:
				return 120300101
			return 499
		_:
			return int(ship_data.get("source_module_type_id", 0))

func _repair_icon_type_id(repair_module_id: int) -> int:
	## Armor RR / shield RB / hull RR: always show small-tier icon art.
	match repair_module_id:
		11355, 11357, 11359:
			return 11355
		3586, 3596, 3606:
			return 3586
		27932, 27930, 27904:
			return 11355  ## no dedicated hull icon pack — reuse armor RR small
		_:
			return repair_module_id if repair_module_id > 0 else 11355

func _weapon_damage_text(dmg: Dictionary) -> String:
	var emp := float(dmg.get("emp", 0.0))
	var thermal := float(dmg.get("thermal", 0.0))
	var kinetic := float(dmg.get("kinetic", 0.0))
	var explosive := float(dmg.get("explosive", 0.0))
	var total := emp + thermal + kinetic + explosive
	## Hide per-channel breakdown (capital/cyno UI lock).
	return "总伤 %d" % int(round(total))

func _weapon_or_repair_text(ship_data: Dictionary, star_data: Dictionary, dmg: Dictionary) -> String:
	if str(ship_data.get("weapon_fx", "")) != "heal":
		return _weapon_damage_text(dmg)
	var repair: Dictionary = star_data.get("repair", {})
	var lines: Array[String] = []
	var shield := float(repair.get("shield", 0.0))
	var armor := float(repair.get("armor", 0.0))
	var structure := float(repair.get("structure", 0.0))
	if shield > 0.0:
		lines.append("护盾修理 %d" % int(round(shield)))
	if armor > 0.0:
		lines.append("装甲修理 %d" % int(round(armor)))
	if structure > 0.0:
		lines.append("结构修理 %d" % int(round(structure)))
	if lines.is_empty():
		lines.append("修理 0")
	return "\n".join(lines)

const _RACE_DRONE_LIGHT := {"amarr": 1001, "caldari": 1002, "gallente": 1003, "minmatar": 1004}
const _RACE_DRONE_MEDIUM := {"amarr": 1005, "caldari": 1006, "gallente": 1007, "minmatar": 1008}
const _RACE_DRONE_HEAVY := {"amarr": 1011, "caldari": 1012, "gallente": 1013, "minmatar": 1014}
const _DRONE_COUNT_EXCEPTIONS := {42: 5, 44: 4, 55: 4, 56: 5}

func _drone_tier_for_carrier(ship_data: Dictionary) -> String:
	var group := str(ship_data.get("ship_group", "frigate"))
	if group == "battlecruiser":
		return "medium"
	if group == "battleship":
		return "heavy"
	if group == "cruiser":
		return "medium"
	return "light"

func _race_drone_id(ship_data: Dictionary) -> int:
	var race := str(ship_data.get("race", "amarr")).to_lower()
	match _drone_tier_for_carrier(ship_data):
		"heavy":
			return int(_RACE_DRONE_HEAVY.get(race, 1011))
		"medium":
			return int(_RACE_DRONE_MEDIUM.get(race, 1005))
		_:
			return int(_RACE_DRONE_LIGHT.get(race, 1001))

func _ship_drone_bay_slots(ship_data: Dictionary) -> int:
	var sid := int(ship_data.get("id", 0))
	if _DRONE_COUNT_EXCEPTIONS.has(sid):
		return int(_DRONE_COUNT_EXCEPTIONS[sid])
	var group := str(ship_data.get("ship_group", ""))
	if group == "battleship":
		return 2
	if group == "battlecruiser":
		return 1
	var slots := int(ship_data.get("drone_bay_slots", ship_data.get("drone_count_cap", 0)))
	if slots <= 0:
		var bw := float(ship_data.get("drone_bandwidth", 0.0))
		if bw > 0.0:
			slots = int(floor(bw / 5.0))
	return slots

func _attack_cycle_s(ship_data: Dictionary, runtime_cycle: float = -1.0) -> float:
	## Same source as ShipUnit.setup: JSON cycle (or combat fallback), then attack_cycle_cap_s.
	var cap_s := float(DataStore.combat.get("attack_cycle_cap_s", 6.0))
	var role := str(ship_data.get("capital_role", ""))
	var skip_cap := role != "" or bool(ship_data.get("requires_cyno_entry", false))
	if runtime_cycle > 0.0:
		return runtime_cycle if skip_cap else minf(runtime_cycle, cap_s)
	var cycle := float(ship_data.get("attack_cycle_s", 0.0))
	if cycle <= 0.0:
		var logistic := str(ship_data.get("weapon_fx", "")) == "heal" or bool(ship_data.get("is_logistic", false))
		cycle = float(DataStore.combat.get("logistic_attack_duration_s" if logistic else "attack_duration_s", 1.0))
	return cycle if skip_cap else minf(cycle, cap_s)

func _weapon_stats_text(ship_data: Dictionary, star_data: Dictionary, atk_range, runtime_cycle: float = -1.0) -> String:
	var shown_range := float(atk_range)
	var tracking := float(star_data.get("tracking", 0.0))
	var cycle := _attack_cycle_s(ship_data, runtime_cycle)
	return "射程 %s\n跟踪 %.2f\nCD %.2fs" % [str(int(round(shown_range))), tracking, cycle]

func _drone_stats_text(drone_data: Dictionary, drone_star: Dictionary) -> String:
	var cycle := _attack_cycle_s(drone_data)
	var speed := float(drone_data.get("speed", 0.0))
	if bool(drone_data.get("is_logistic", false)) or str(drone_data.get("weapon_fx", "")) == "heal":
		var repair: Dictionary = drone_star.get("repair", {})
		var parts: Array[String] = []
		for k in ["shield", "armor", "structure"]:
			var v := float(repair.get(k, 0.0))
			if v > 0.0:
				var label := "盾" if k == "shield" else ("甲" if k == "armor" else "结")
				parts.append("%s%d" % [label, int(round(v))])
		var heal_txt := " ".join(parts) if not parts.is_empty() else "修 0"
		return "%s\nCD %.2fs\n速度 %s" % [heal_txt, cycle, str(int(round(speed)))]
	var dmg: Dictionary = drone_star.get("damage", {})
	return "%s\nCD %.2fs\n速度 %s" % [_weapon_damage_text(dmg), cycle, str(int(round(speed)))]

func _ensure_info_stat_square(parent: Control, square_name: String, min_size: Vector2) -> Dictionary:
	var square := parent.get_node_or_null(square_name) as PanelContainer
	var mobile := UiLayout.is_mobile()
	var icon_sz := UiLayout.px(44 if mobile else 56, self)
	var lbl_w := UiLayout.px(110 if mobile else 150, self)
	var lbl_h := UiLayout.px(56 if mobile else 72, self)
	if square == null:
		square = PanelContainer.new()
		square.name = square_name
		square.custom_minimum_size = min_size
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_content_margin_all(0)
		square.add_theme_stylebox_override("panel", sb)
		parent.add_child(square)
	else:
		square.custom_minimum_size = min_size
	var row := square.get_node_or_null("%sRow" % square_name) as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "%sRow" % square_name
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override("separation", UiLayout.margin_px(8 if mobile else 10, self))
		UiAssets.full_rect(row)
		square.add_child(row)
	var icon := row.get_node_or_null("%sIcon" % square_name) as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "%sIcon" % square_name
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	icon.custom_minimum_size = Vector2(icon_sz, icon_sz)
	var lbl := row.get_node_or_null("%sText" % square_name) as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "%sText" % square_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
	lbl.custom_minimum_size = Vector2(lbl_w, lbl_h)
	return {"square": square, "icon": icon, "label": lbl}

func _ensure_info_weapon_column(info_top: HBoxContainer) -> Dictionary:
	var mobile := UiLayout.is_mobile()
	var body := info_top.get_parent() as VBoxContainer
	var col_parent: Control = body if (mobile and body != null) else info_top
	var col := col_parent.get_node_or_null("InfoWeaponColumn") as VBoxContainer
	if col == null:
		## Also look under the other parent (desktop↔mobile layout switch).
		var other: Control = info_top if col_parent == body else body
		if other:
			col = other.get_node_or_null("InfoWeaponColumn") as VBoxContainer
			if col and col.get_parent() != col_parent:
				col.get_parent().remove_child(col)
				col_parent.add_child(col)
	if col == null:
		col = VBoxContainer.new()
		col.name = "InfoWeaponColumn"
		col.add_theme_constant_override("separation", UiLayout.margin_px(6, self))
		col_parent.add_child(col)
	# Migrate legacy weapon square if it was parented directly under InfoTop.
	var legacy := info_top.get_node_or_null("InfoWeaponSquare") as PanelContainer
	if legacy and legacy.get_parent() == info_top:
		info_top.remove_child(legacy)
		legacy.queue_free()
	var w_sz := Vector2(UiLayout.px(168 if mobile else 228, self), UiLayout.px(120 if mobile else 176, self))
	var d_sz := Vector2(UiLayout.px(168 if mobile else 228, self), UiLayout.px(96 if mobile else 120, self))
	var weapon := _ensure_info_stat_square(col, "InfoWeaponSquare", w_sz)
	var drone := _ensure_info_stat_square(col, "InfoDroneSquare", d_sz)
	return {"weapon": weapon, "drone": drone}

func _style_info_stat_label(lbl: Label) -> void:
	UiAssets.apply_label_font(lbl, true, 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)

func _ensure_info_weapon_square(info_top: HBoxContainer) -> Dictionary:
	return _ensure_info_weapon_column(info_top).get("weapon", {})

func _ensure_info_extra(body: VBoxContainer) -> Label:
	var lbl := body.get_node_or_null("InfoExtra") as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "InfoExtra"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(lbl)
	return lbl

func _resist_pct(value) -> int:
	return int(round(float(value) * 100.0))

func _resist_text(resist: Dictionary) -> String:
	return "电%s%% 热%s%% 动%s%% 爆%s%%" % [
		_resist_pct(resist.get("emp", 0.0)),
		_resist_pct(resist.get("thermal", 0.0)),
		_resist_pct(resist.get("kinetic", 0.0)),
		_resist_pct(resist.get("explosive", 0.0))
	]

func _hp_line(layer_name: String, hp_text: String, _resist: Dictionary) -> String:
	## Resists hidden in ship detail panel (capital update lock).
	return "%s  %s" % [layer_name, hp_text]

func _base_stats_text(ship_data: Dictionary) -> String:
	var long_axis := float(ship_data.get("model_long_axis", 0.0))
	var long_axis_txt := "%.0f" % long_axis if long_axis > 0.0 else "—"
	return "信源半径 %s   速度 %s   长轴 %s\n感应强度 %s   电容量 %s   电容回复 %ss" % [
		str(ship_data.get("signature_radius", 0)),
		str(ship_data.get("speed", 0)),
		long_axis_txt,
		str(ship_data.get("sensor_strength", 0)),
		str(ship_data.get("capacitor_capacity", 0)),
		str(ship_data.get("capacitor_recharge_s", 0))
	]

func _fill_info_panel(ship_name: String, star: int, shield_txt: String, armor_txt: String, structure_txt: String, dmg: Dictionary, atk_range, fetter_ids: Array, ship_data: Dictionary, star_data: Dictionary, ship_id: int = 0, runtime_cycle: float = -1.0) -> void:
	var p := hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if p == null:
		return
	var icon := p.get_node_or_null("InfoBody/InfoTop/InfoIcon") as TextureRect
	var title := p.get_node_or_null("InfoBody/InfoTop/InfoTitleCol/InfoTitle") as Label
	var title_col := p.get_node_or_null("InfoBody/InfoTop/InfoTitleCol") as VBoxContainer
	var info_top := p.get_node_or_null("InfoBody/InfoTop") as HBoxContainer
	var weapon_col: Dictionary = {}
	if info_top:
		weapon_col = _ensure_info_weapon_column(info_top)
	var weapon_square: Dictionary = weapon_col.get("weapon", {})
	var drone_square: Dictionary = weapon_col.get("drone", {})
	if title_col:
		var old_badge := title_col.get_node_or_null("InfoWeaponRow")
		if old_badge:
			old_badge.queue_free()
	var fetter_box := p.get_node_or_null("InfoBody/InfoFetters") as VBoxContainer
	var sh := p.get_node_or_null("InfoBody/InfoShield") as Label
	var ar := p.get_node_or_null("InfoBody/InfoArmor") as Label
	var st := p.get_node_or_null("InfoBody/InfoStructure") as Label
	var dm := p.get_node_or_null("InfoBody/InfoDmg") as Label
	var rg := p.get_node_or_null("InfoBody/InfoRange") as Label
	var body := p.get_node_or_null("InfoBody") as VBoxContainer
	var extra: Label = null
	if body:
		extra = _ensure_info_extra(body)
	if icon:
		icon.texture = UiAssets.champion_icon(ship_name, ship_id)
		var isz := UiLayout.px(56 if UiLayout.is_mobile() else 72, self)
		icon.custom_minimum_size = Vector2(isz, isz)
	if title:
		title.text = "%s  ★%d" % [ship_name, star]
		UiAssets.apply_label_font(title, true, UiLayout.font_size(18 if UiLayout.is_mobile() else 22, self))
	var is_titan_info := str(ship_data.get("ship_group", "")) == "titan"
	if not is_titan_info:
		var tags_chk: Array = ship_data.get("tags", []) as Array
		for t in tags_chk:
			if str(t) == "titan":
				is_titan_info = true
				break
	if not weapon_square.is_empty():
		var weapon_icon := weapon_square.get("icon") as TextureRect
		var weapon_label := weapon_square.get("label") as Label
		var weapon_panel := weapon_square.get("square") as PanelContainer
		var fs: Dictionary = ship_data.get("function_slots", {}) if typeof(ship_data.get("function_slots", {})) == TYPE_DICTIONARY else {}
		var fslots: Array = fs.get("slots", []) if typeof(fs) == TYPE_DICTIONARY else []
		var cyno_mod: Dictionary = {}
		for m in fslots:
			if typeof(m) == TYPE_DICTIONARY and str((m as Dictionary).get("kind", "")) == "cyno":
				cyno_mod = m
				break
		var dmg_total := float(dmg.get("emp", 0)) + float(dmg.get("thermal", 0)) + float(dmg.get("kinetic", 0)) + float(dmg.get("explosive", 0))
		var show_cyno := not cyno_mod.is_empty() or str(ship_data.get("capital_role", "")) == "covert_cyno"
		var is_mining := bool(ship_data.get("is_mining_ship", false))
		var mining_gold_base := int(ship_data.get("mining_gold_per_round", 0))
		var mining_gold := mining_gold_base * maxi(star, 1)
		var is_heal := str(ship_data.get("weapon_fx", "")) == "heal" or bool(ship_data.get("is_logistic", false))
		if is_titan_info:
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				weapon_icon.texture = null
			if weapon_label:
				weapon_label.text = ""
		elif is_mining:
			## All mining hulls (incl. Rorqual body): strip miner art + hull gold / round × star.
			## Rorqual excavators still show in the drone square below.
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				var strip_id := int(ship_data.get("source_module_type_id", 11008100000))
				if strip_id <= 0:
					strip_id = 11008100000
				weapon_icon.texture = UiAssets.item_icon(strip_id)
			if weapon_label:
				weapon_label.text = "露天采矿器\n采矿 +%d 黄币/回合（★%d）" % [mining_gold, maxi(star, 1)]
				_style_info_stat_label(weapon_label)
		elif is_heal and not show_cyno:
			## Logistics / FAX hull: remote repairer portrait + repair lines (even if DPH=0).
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				weapon_icon.texture = UiAssets.item_icon(_weapon_module_type_id(ship_data))
			if weapon_label:
				weapon_label.text = "%s\n%s" % [
					_weapon_or_repair_text(ship_data, star_data, dmg),
					_weapon_stats_text(ship_data, star_data, atk_range, runtime_cycle)
				]
				_style_info_stat_label(weapon_label)
		elif (not show_cyno) and dmg_total <= 0.001:
			# No primary weapon damage: hide weapon slot (carriers/FAX etc. keep drone/fighter slot only).
			if weapon_panel:
				weapon_panel.visible = false
			if weapon_icon:
				weapon_icon.texture = null
			if weapon_label:
				weapon_label.text = ""
		elif show_cyno and dmg_total <= 0.001:
			## Empty weapon → equip (cyno) fills weapon square (上移盖空武器框).
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				var cyno_icon_id := int(cyno_mod.get("icon_item_id", ship_data.get("source_module_type_id", 11114010000)))
				weapon_icon.texture = UiAssets.item_icon(cyno_icon_id)
			if weapon_label:
				var dur := float(cyno_mod.get("duration_s", 90.0))
				weapon_label.text = "%s\n读条 %.0fs" % [str(cyno_mod.get("name", "诱导")), dur]
				_style_info_stat_label(weapon_label)
		else:
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				weapon_icon.texture = UiAssets.item_icon(_weapon_module_type_id(ship_data))
			if weapon_label:
				weapon_label.text = "%s\n%s" % [
					_weapon_or_repair_text(ship_data, star_data, dmg),
					_weapon_stats_text(ship_data, star_data, atk_range, runtime_cycle)
				]
				_style_info_stat_label(weapon_label)
	if not drone_square.is_empty():
		var drone_panel := drone_square.get("square") as PanelContainer
		var drone_icon := drone_square.get("icon") as TextureRect
		var drone_label := drone_square.get("label") as Label
		if is_titan_info:
			if drone_panel:
				drone_panel.visible = false
			if drone_icon:
				drone_icon.texture = null
			if drone_label:
				drone_label.text = ""
		else:
			var fighter_id := int(ship_data.get("fighter_unit_id", 0))
			var repair_id := int(ship_data.get("heavy_repair_drone_id", 0))
			var mining_drone_id2 := int(ship_data.get("mining_drone_id", 0))
			var bay_slots := _ship_drone_bay_slots(ship_data)
			if mining_drone_id2 > 0:
				var n_mine := int(ship_data.get("mining_drone_count", bay_slots if bay_slots > 0 else 4))
				var mine_data: Dictionary = DataStore.get_ship(mining_drone_id2)
				var per_base := int(mine_data.get("mining_gold_per_round", 25))
				var per := per_base * maxi(star, 1)
				var full := per * n_mine
				if drone_panel:
					drone_panel.visible = true
				if drone_icon:
					drone_icon.texture = UiAssets.drone_portrait(mining_drone_id2)
					if drone_icon.texture == null:
						drone_icon.texture = UiAssets.champion_icon(str(mine_data.get("name", "")), mining_drone_id2)
				if drone_label:
					drone_label.text = "%s ×%d\n每架 +%d 黄币/回合（满额 %d · ★%d）" % [
						str(mine_data.get("name", "挖矿无人机")),
						n_mine,
						per,
						full,
						maxi(star, 1)
					]
					_style_info_stat_label(drone_label)
			elif bool(ship_data.get("is_mining_ship", false)):
				if drone_panel:
					drone_panel.visible = false
				if drone_icon:
					drone_icon.texture = null
				if drone_label:
					drone_label.text = ""
			elif fighter_id > 0:
				var squads := int(ship_data.get("fighter_squadrons", 3))
				var tubes := int(ship_data.get("fighter_tubes_per_squadron", 3))
				var n_fighters := squads * tubes
				var fighter_data: Dictionary = DataStore.get_ship(fighter_id)
				var fighter_star: Dictionary = DataStore.get_star(fighter_id, 1)
				if drone_panel:
					drone_panel.visible = true
				if drone_icon:
					drone_icon.texture = UiAssets.champion_icon(str(fighter_data.get("name", "")), fighter_id)
				if drone_label:
					drone_label.text = "%s ×%d\n%s" % [
						str(fighter_data.get("name", "舰载机")),
						n_fighters,
						_drone_stats_text(fighter_data, fighter_star)
					]
					_style_info_stat_label(drone_label)
			elif repair_id > 0:
				var n_rep := int(ship_data.get("heavy_repair_drone_count", 4))
				var rep_data: Dictionary = DataStore.get_ship(repair_id)
				var rep_star: Dictionary = DataStore.get_star(repair_id, 1)
				if drone_panel:
					drone_panel.visible = true
				if drone_icon:
					drone_icon.texture = UiAssets.drone_portrait(repair_id)
					if drone_icon.texture == null:
						var rep_path := str(rep_data.get("portrait", ""))
						if rep_path != "":
							drone_icon.texture = UiAssets.tex(rep_path)
				if drone_label:
					drone_label.text = "%s ×%d\n%s" % [
						str(rep_data.get("name", "维修无人机")),
						n_rep,
						_drone_stats_text(rep_data, rep_star)
					]
					_style_info_stat_label(drone_label)
			else:
				if drone_panel:
					drone_panel.visible = bay_slots > 0
				if bay_slots > 0:
					var drone_id := _race_drone_id(ship_data)
					var drone_data: Dictionary = DataStore.get_ship(drone_id)
					var drone_star: Dictionary = DataStore.get_star(drone_id, 1)
					if drone_icon:
						drone_icon.texture = UiAssets.drone_portrait(drone_id)
					if drone_label:
						var drone_name := str(drone_data.get("name", "无人机"))
						drone_label.text = "%s ×%d\n%s" % [
							drone_name,
							bay_slots,
							_drone_stats_text(drone_data, drone_star)
						]
						_style_info_stat_label(drone_label)
	if fetter_box:
		for c in fetter_box.get_children():
			c.queue_free()
		for fid in fetter_ids:
			var fdata: Dictionary = DataStore.fetters.get(str(fid), {})
			var fname := str(fdata.get("name", fid))
			var row := HBoxContainer.new()
			var fic := TextureRect.new()
			fic.custom_minimum_size = Vector2(UiLayout.px(18 if UiLayout.is_mobile() else 22, self), UiLayout.px(18 if UiLayout.is_mobile() else 22, self))
			fic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var ft := UiAssets.fetter_icon(str(fid), fname)
			if ft:
				fic.texture = ft
			row.add_child(fic)
			var fl := Label.new()
			fl.text = fname
			UiAssets.apply_label_font(fl, false, 15)
			row.add_child(fl)
			fetter_box.add_child(row)
	if sh:
		sh.text = _hp_line("护盾", shield_txt, star_data.get("shield_resist", {}))
		UiAssets.apply_label_font(sh, false, 16)
	if ar:
		ar.text = _hp_line("装甲", armor_txt, star_data.get("armor_resist", {}))
		UiAssets.apply_label_font(ar, false, 16)
	if st:
		st.text = _hp_line("结构", structure_txt, star_data.get("structure_resist", {}))
		UiAssets.apply_label_font(st, false, 16)
	if dm:
		dm.visible = false
	if rg:
		rg.visible = false
	if extra:
		extra.text = _base_stats_text(ship_data)
		UiAssets.apply_label_font(extra, false, 15)
	p.visible = true
	var root := hud.get_node_or_null("Root") as Control
	if root:
		_apply_info_panel_adaptive_layout(root)
	# Expand right column when showing ship info.
	if _collapse_right:
		_collapse_right = false
		_apply_adaptive_hud_layout()

func _show_ship_info(ship: ShipUnit) -> void:
	_info_ship = ship
	_suppress_headup_for_preview = ship == null or ship.slot_type != "field"
	if ship == null:
		_refresh_observe_btn()
		return
	var data: Dictionary = DataStore.get_ship(ship.ship_id)
	var st: Dictionary = DataStore.get_star_resolved(ship.ship_id, ship.star)
	_fill_info_panel(
		str(data.get("name", "?")),
		ship.star,
		"%.0f/%.0f" % [ship.shield_hp, ship.max_shield],
		"%.0f/%.0f" % [ship.armor_hp, ship.max_armor],
		"%.0f/%.0f" % [ship.structure_hp, ship.max_structure],
		ship.damage_dict_scaled(),
		ship.attack_range,
		data.get("fetter_ids", []),
		data,
		st,
		ship.ship_id,
		ship.attack_duration
	)
	_refresh_observe_btn()

func _show_ship_info_id(ship_id: int) -> void:
	_info_ship = null
	_info_hold_until_ms = 0
	_suppress_headup_for_preview = true
	if _camera_observe:
		_exit_observe_unit(true)
	var st: Dictionary = DataStore.get_star_resolved(ship_id, 1)
	var data: Dictionary = DataStore.get_ship(ship_id)
	var dmg: Dictionary = st.get("damage", {})
	var armor := float(st.get("armor_hp", 0))
	var structure := float(st.get("structure_hp", maxf(50.0, roundf(armor * 0.5))))
	_fill_info_panel(
		str(data.get("name", "?")),
		1,
		str(st.get("shield_hp", 0)),
		str(st.get("armor_hp", 0)),
		str(int(structure)),
		dmg,
		st.get("attack_range", 0),
		data.get("fetter_ids", []),
		data,
		st,
		ship_id
	)
	_refresh_observe_btn()

func _hide_ship_info() -> void:
	_info_ship = null
	_info_hold_until_ms = 0
	_suppress_headup_for_preview = false
	if _camera_observe:
		_exit_observe_unit(true)
	var p := hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if p:
		p.visible = false
	_refresh_observe_btn()

func _on_match_over(summary: String) -> void:
	show_notice(summary)
	_append_battle_log(summary)
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	_cam_base_pitch_deg = _cam_default_pitch_deg
	if GameSession.pending_mode == "nullsec":
		_show_nullsec_settlement(summary)
		return
	var delay := float(DataStore.match_flow.get("death_return_delay_s", 3))
	await get_tree().create_timer(delay).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _show_nullsec_settlement(summary: String) -> void:
	_nullsec_prepare_pending = false
	_nullsec_prepare_ui_pending = false
	_doomsday_busy = false
	var ships: Array = []
	if board:
		for s in board.all_ships():
			if s == null or not is_instance_valid(s) or s.is_unmanned:
				continue
			if int(s.team_id) != ShipUnit.TEAM_PLAYER:
				continue
			ships.append({"ship_id": int(s.ship_id), "star": int(s.star)})
	var result := "平"
	if match_ctrl:
		if match_ctrl.player_hp <= 0:
			result = "负"
		elif match_ctrl.mode != "endless" and match_ctrl.ai_hp <= 0:
			result = "胜"
	var nick := "本地"
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s in seats:
		if bool(s.get("occupied", false)) and not bool(s.get("is_ai", false)):
			nick = str(s.get("nick", nick))
			break
	var gold_earned := int(match_ctrl.player_gold_earned) if match_ctrl else 0
	var row := NullsecSettlement.make_row(
		nick,
		int(match_ctrl.player_level) if match_ctrl else 1,
		gold_earned,
		result,
		ships
	)
	if _settlement_panel == null:
		_settlement_panel = NullsecSettlementPanel.new()
		hud.add_child(_settlement_panel)
	_settlement_panel.confirmed.connect(func():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	, CONNECT_ONE_SHOT)
	_settlement_panel.show_rows([row])
	show_notice(summary)

func _on_refresh_pressed() -> void:
	shop.manual_refresh()
	_refresh_shop_ui()
	_refresh_hud()

func _on_lock_pressed() -> void:
	match_ctrl.shop_locked = not match_ctrl.shop_locked
	show_notice("商店锁定" if match_ctrl.shop_locked else "商店解锁")

func _on_lock_toggled(pressed: bool) -> void:
	match_ctrl.shop_locked = pressed
	show_notice("商店锁定" if pressed else "商店解锁")

func _on_exp_pressed() -> void:
	## Scene may still fire pressed; prefer button_down/up hold path.
	pass

func _wire_exp_hold(btn: Button) -> void:
	if btn == null:
		return
	if btn.pressed.is_connected(_on_exp_pressed):
		btn.pressed.disconnect(_on_exp_pressed)
	if not btn.button_down.is_connected(_on_exp_button_down):
		btn.button_down.connect(_on_exp_button_down)
	if not btn.button_up.is_connected(_on_exp_button_up):
		btn.button_up.connect(_on_exp_button_up)

func _on_exp_button_down() -> void:
	_exp_hold_active = true
	_exp_hold_t = 0.0
	_exp_hold_repeat_t = 0.0
	_exp_hold_repeating = false

func _on_exp_button_up() -> void:
	## Short tap: release before the hold delay → one buy. Once repeating, buys already ran.
	if _exp_hold_active and not _exp_hold_repeating:
		_try_buy_exp_once()
	_exp_hold_active = false
	_exp_hold_t = 0.0
	_exp_hold_repeat_t = 0.0
	_exp_hold_repeating = false

func _tick_exp_hold(delta: float) -> void:
	if not _exp_hold_active:
		return
	_exp_hold_t += delta
	if not _exp_hold_repeating:
		if _exp_hold_t < _EXP_HOLD_DELAY_S:
			return
		_exp_hold_repeating = true
		_exp_hold_repeat_t = 0.0
		if not _try_buy_exp_once():
			_exp_hold_active = false
		return
	_exp_hold_repeat_t += delta
	while _exp_hold_repeat_t >= _EXP_HOLD_INTERVAL_S:
		_exp_hold_repeat_t -= _EXP_HOLD_INTERVAL_S
		if not _try_buy_exp_once():
			_exp_hold_active = false
			break

func _try_buy_exp_once() -> bool:
	var cost := int(DataStore.economy.get("buy_exp_gold_cost", 4))
	if match_ctrl == null or match_ctrl.player_gold < cost:
		return false
	var before := match_ctrl.player_gold
	match_ctrl.buy_exp()
	_refresh_hud()
	return match_ctrl.player_gold < before

func _player_hp_label_text() -> String:
	## Nullsec lives = titan three pipes, not the citadel formula (MULTIPLAYER_PVP §2.4).
	if GameSession.pending_mode == "nullsec":
		var pipes := _local_titan_pipes()
		if pipes == null:
			return ""
		return "泰坦 盾%d · 甲%d · 结构%d" % [pipes.shield, pipes.armor, pipes.structure]
	return "我 %d  ·  敌 %d" % [match_ctrl.player_hp, match_ctrl.ai_hp]

func _apply_match_save() -> void:
	_apply_match_save_dict(MatchSave.load_dict())

func _apply_match_save_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	var p: Dictionary = d.get("player", {})
	match_ctrl.player_gold = int(p.get("gold", match_ctrl.player_gold))
	match_ctrl.player_hp = int(p.get("hp", match_ctrl.player_hp))
	match_ctrl.player_max_hp = int(p.get("max_hp", match_ctrl.player_max_hp))
	match_ctrl.player_level = maxi(1, int(p.get("level", match_ctrl.player_level)))
	match_ctrl.player_exp = maxi(0, int(p.get("exp", match_ctrl.player_exp)))
	## Heal inconsistent / legacy saves: demand must match level curve.
	var expected_demand := MatchController.exp_demand_for_level(match_ctrl.player_level)
	var saved_demand := int(p.get("up_level_demand", 0))
	match_ctrl.up_level_demand = expected_demand if saved_demand != expected_demand else saved_demand
	## Apply any overflow XP that was saved against a wrong demand.
	var inc := int(DataStore.economy.get("level_exp_demand_increment", 8))
	while match_ctrl.player_exp >= match_ctrl.up_level_demand and match_ctrl.up_level_demand > 0:
		match_ctrl.player_exp -= match_ctrl.up_level_demand
		match_ctrl.player_level += 1
		match_ctrl.up_level_demand += inc
	match_ctrl.win_streak = int(p.get("win_streak", 0))
	match_ctrl.loss_streak = int(p.get("loss_streak", 0))
	match_ctrl.shop_locked = bool(p.get("shop_locked", false))
	match_ctrl.battle_game_stage_count = int(d.get("battle_game_stage_count", 0))
	match_ctrl.round_phase_value = int(d.get("round_phase_value", 1))
	match_ctrl.battle_phase_value = int(d.get("battle_phase_value", 0))
	if shop and p.has("shop_slots"):
		var restored := _normalize_shop_slots(p.get("shop_slots", []))
		## Empty shop_slots in legacy/bad saves must not wipe a freshly rolled shop.
		if restored.is_empty():
			shop.refresh_shop(true, false)
		else:
			shop.slots = restored
			shop.shop_changed.emit()
	elif shop and (shop.slots.is_empty()):
		shop.refresh_shop(true, false)
	var a: Dictionary = d.get("ai", {})
	match_ctrl.ai_hp = int(a.get("hp", match_ctrl.ai_hp))
	match_ctrl.ai_max_hp = int(a.get("max_hp", match_ctrl.ai_max_hp))
	if ai:
		ai.ai_gold = int(a.get("gold", ai.ai_gold))
		ai.ai_level = maxi(1, int(a.get("level", ai.ai_level)))
		ai.ai_exp = maxi(0, int(a.get("exp", ai.ai_exp)))
		var ai_expected := MatchController.exp_demand_for_level(ai.ai_level)
		var ai_saved := int(a.get("up_level_demand", 0))
		ai.up_level_demand = ai_expected if ai_saved != ai_expected else ai_saved
		var ai_inc := int(DataStore.economy.get("level_exp_demand_increment", 8))
		while ai.ai_exp >= ai.up_level_demand and ai.up_level_demand > 0:
			ai.ai_exp -= ai.up_level_demand
			ai.ai_level += 1
			ai.up_level_demand += ai_inc
		ai.win_streak = int(a.get("win_streak", 0))
		ai.loss_streak = int(a.get("loss_streak", 0))
		ai.shop_slots = _normalize_shop_slots(a.get("shop_slots", ai.shop_slots))
	board.reset_match()
	_redeploy_saved_ships(d.get("ships", []))
	## start_match already ran AI economy on an empty board; after redeploy, fill field again.
	if ai and ai.has_method("sync_field_for_prepare"):
		ai.sync_field_for_prepare()
	_refresh_citadel_bar()
	_refresh_hud()
	show_notice("已继续上次对局（空堡 HP 我%d/敌%d）" % [match_ctrl.player_hp, match_ctrl.ai_hp])


func _normalize_shop_slots(raw) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for e in raw:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = e
		out.append({
			"ship_id": int(slot.get("ship_id", 0)),
			"purchased": bool(slot.get("purchased", false)),
		})
	return out

func _redeploy_saved_ships(ships: Array) -> void:
	for entry in ships:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid := int(entry.get("ship_id", 0))
		if sid <= 0:
			continue
		if DataStore.get_ship(sid).is_empty():
			continue
		AdminBus.request(&"board.deploy", {
			"ship_id": sid,
			"star": int(entry.get("star", 1)),
			"team": int(entry.get("team", ShipUnit.TEAM_PLAYER)),
			"slot_type": str(entry.get("slot_type", "hangar")),
			"x": int(entry.get("x", 0)),
			"z": int(entry.get("z", 0)),
			## Preserve exact save roster — do not merge 3×same into upgrades mid-redeploy.
			"skip_upgrade": true,
		})
		var deployed := false
		for s2 in board.all_ships():
			if s2.ship_id == sid and s2.grid_x == int(entry.get("x", 0)) and s2.grid_z == int(entry.get("z", 0)) and s2.slot_type == str(entry.get("slot_type", "hangar")) and s2.team_id == int(entry.get("team", ShipUnit.TEAM_PLAYER)):
				if int(entry.get("field_side_team", -1)) >= 0:
					s2.field_side_team = int(entry.get("field_side_team"))
					if s2.slot_type == "field":
						s2.global_position = BoardController.cell_to_world("field", s2.field_side_team, s2.grid_x, s2.grid_z)
				deployed = true
				break
		if not deployed:
			## Legacy saves may still list cyno hulls on field — park them in hangar.
			var sd: Dictionary = DataStore.get_ship(sid)
			if bool(sd.get("requires_cyno_entry", false)) and str(entry.get("slot_type", "")) == "field":
				var hang: Vector2i = board.find_empty_hangar(int(entry.get("team", ShipUnit.TEAM_PLAYER)))
				if hang.x >= 0:
					var r2 := AdminBus.request(&"board.deploy", {
						"ship_id": sid,
						"star": int(entry.get("star", 1)),
						"team": int(entry.get("team", ShipUnit.TEAM_PLAYER)),
						"slot_type": "hangar",
						"x": hang.x,
						"z": hang.y,
						"skip_upgrade": true,
					})
					if r2.get("accepted", true):
						deployed = true
			if not deployed:
				push_warning("MatchSave redeploy failed ship_id=%s slot=%s(%s,%s) team=%s" % [
					sid, entry.get("slot_type"), entry.get("x"), entry.get("z"), entry.get("team"),
				])
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	board.recalculate_fetters(ShipUnit.TEAM_AI)
	_refresh_hud()
	_refresh_shop_ui()

func _on_skip_pressed() -> void:
	match_ctrl.skip_prepare()
	_refresh_hud()

func _on_speed_pressed() -> void:
	if GameSession.pending_mode == "nullsec" and _speed_dropdown != null:
		var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
		_speed_dropdown.refresh_list(seats)
		var btn := hud.get_node_or_null("Root/TopRight/SpeedBtn") as Button
		if btn:
			_speed_dropdown.position = btn.global_position + Vector2(0, btn.size.y)
		_speed_dropdown.popup()
		return
	match_ctrl.cycle_speed()
	_refresh_hud()
	show_notice("倍速 %s" % match_ctrl.speed_label())

func _on_menu_pressed() -> void:
	_toggle_game_menu()


func _game_menu_open() -> bool:
	return _game_menu != null and _game_menu.visible


func _toggle_game_menu() -> void:
	if _game_menu_open():
		_close_game_menu()
	else:
		_open_game_menu()


func _open_game_menu() -> void:
	if _game_menu == null:
		_build_game_menu()
	_menu_opened_pause = get_tree().paused
	## Nullsec: menu never pauses the match. Versus/Endless: open → pause.
	var allow_pause := GameSession == null or str(GameSession.pending_mode) != "nullsec"
	if allow_pause and not get_tree().paused:
		get_tree().paused = true
		var pause_btn := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
		if pause_btn:
			pause_btn.text = "继续"
	if _game_menu_settings:
		_game_menu_settings.visible = false
	if _game_menu_dev:
		_game_menu_dev.visible = false
	if _game_menu_save:
		_game_menu_save.visible = false
	_game_menu.visible = true
	_sync_game_menu_settings_widgets()


func _close_game_menu() -> void:
	if _game_menu:
		_game_menu.visible = false
	if _game_menu_settings:
		_game_menu_settings.visible = false
	if _game_menu_dev:
		_game_menu_dev.visible = false
	if _game_menu_save:
		_game_menu_save.visible = false
	if not _menu_opened_pause:
		get_tree().paused = false
		var pause_btn := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
		if pause_btn:
			pause_btn.text = "暂停"
	_menu_opened_pause = false


func _build_game_menu() -> void:
	if hud == null:
		return
	if _game_menu and is_instance_valid(_game_menu):
		return
	_game_menu = _make_modal_panel("GameMenuPanel")
	_game_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(_game_menu)
	var box := _game_menu.get_node("Margin/VBox") as VBoxContainer
	var title := Label.new()
	title.text = "菜单"
	UiAssets.apply_label_font(title, true, UiLayout.font_size(26, self))
	box.add_child(title)
	box.add_child(_menu_action_btn("继续游戏", _close_game_menu))
	## Nullsec rounds cannot be resumed offline, so they are never archived
	## (MATCH_FLOW §5.0b) — the entry is absent rather than dead.
	if GameSession.pending_mode != "nullsec":
		box.add_child(_menu_action_btn("保存当前局为存档", _open_save_panel))
	box.add_child(_menu_action_btn("设置", _open_settings_panel))
	box.add_child(_menu_action_btn("返回主菜单", _return_to_main_menu))
	_layout_center_panel(_game_menu, 0.42, 0.52)

	_game_menu_settings = _build_match_settings_panel()
	hud.add_child(_game_menu_settings)
	_layout_center_panel(_game_menu_settings, 0.55, 0.68)

	_game_menu_dev = _build_match_developer_panel()
	hud.add_child(_game_menu_dev)
	_layout_center_panel(_game_menu_dev, 0.52, 0.48)

	_game_menu_save = _build_save_panel()
	hud.add_child(_game_menu_save)
	_layout_center_panel(_game_menu_save, 0.5, 0.42)


func _menu_action_btn(label: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, UiLayout.px(44, self))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_button_font(btn, UiLayout.font_size(18, self))
	btn.pressed.connect(cb)
	return btn


func _make_modal_panel(p_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = p_name
	panel.visible = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	sb.border_color = Color(0.35, 0.72, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	var m := UiLayout.margin_px(16, self)
	margin.add_theme_constant_override("margin_left", m)
	margin.add_theme_constant_override("margin_right", m)
	margin.add_theme_constant_override("margin_top", m)
	margin.add_theme_constant_override("margin_bottom", m)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	margin.add_child(vbox)
	return panel


func _layout_center_panel(panel: Control, w_frac: float, h_frac: float) -> void:
	if panel == null:
		return
	UiLayout.set_center_panel_frac(panel, w_frac, h_frac)


func _build_match_settings_panel() -> Control:
	var panel := _make_modal_panel("MatchSettingsPanel")
	var box := panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "设置"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back := Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func():
		panel.visible = false
		if _game_menu:
			_game_menu.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var fps_cap := Label.new()
	fps_cap.text = "FPS限制"
	UiAssets.apply_label_font(fps_cap, false, UiLayout.font_size(16, self))
	row.add_child(fps_cap)
	_fps_slider = HSlider.new()
	_fps_slider.min_value = 30
	_fps_slider.max_value = 240
	_fps_slider.step = 1
	_fps_slider.value = GameSession.target_fps
	_fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_slider.value_changed.connect(_on_match_fps_changed)
	row.add_child(_fps_slider)
	_fps_lbl = Label.new()
	_fps_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_fps_lbl.text = str(int(GameSession.target_fps))
	UiAssets.apply_label_font(_fps_lbl, false, UiLayout.font_size(16, self))
	row.add_child(_fps_lbl)
	box.add_child(row)

	var bgm := _BgMusic.instance()
	var bgm_on_row := HBoxContainer.new()
	_bgm_check = CheckBox.new()
	_bgm_check.text = "背景音乐"
	_bgm_check.button_pressed = bgm.enabled if bgm else false
	UiAssets.apply_button_font(_bgm_check, UiLayout.font_size(16, self))
	_bgm_check.toggled.connect(_on_match_bgm_toggled)
	bgm_on_row.add_child(_bgm_check)
	box.add_child(bgm_on_row)

	var nomodel := CheckBox.new()
	nomodel.text = "无模型性能模式"
	nomodel.button_pressed = GameSession.no_model_perf_mode
	UiAssets.apply_button_font(nomodel, UiLayout.font_size(16, self))
	nomodel.toggled.connect(func(on: bool): GameSession.set_no_model_perf_mode(on))
	box.add_child(nomodel)

	var breathe := CheckBox.new()
	breathe.text = "镜头呼吸浮动"
	breathe.button_pressed = GameSession.camera_breathe_enabled
	UiAssets.apply_button_font(breathe, UiLayout.font_size(16, self))
	breathe.toggled.connect(func(on: bool): GameSession.set_camera_breathe_enabled(on))
	box.add_child(breathe)

	var bgm_vol_row := HBoxContainer.new()
	bgm_vol_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var bgm_cap := Label.new()
	bgm_cap.text = "背景音乐音量"
	UiAssets.apply_label_font(bgm_cap, false, UiLayout.font_size(16, self))
	bgm_vol_row.add_child(bgm_cap)
	_bgm_slider = HSlider.new()
	_bgm_slider.min_value = 0
	_bgm_slider.max_value = 100
	_bgm_slider.step = 1
	_bgm_slider.value = bgm.volume_pct if bgm else 60.0
	_bgm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bgm_slider.value_changed.connect(_on_match_bgm_volume_changed)
	bgm_vol_row.add_child(_bgm_slider)
	_bgm_lbl = Label.new()
	_bgm_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_bgm_lbl.text = str(int(_bgm_slider.value))
	UiAssets.apply_label_font(_bgm_lbl, false, UiLayout.font_size(16, self))
	bgm_vol_row.add_child(_bgm_lbl)
	box.add_child(bgm_vol_row)

	var dev_btn := Button.new()
	dev_btn.text = "开发者调试"
	dev_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(dev_btn, UiLayout.font_size(16, self))
	dev_btn.pressed.connect(_open_developer_panel)
	box.add_child(dev_btn)
	return panel


func _build_match_developer_panel() -> Control:
	var panel := _make_modal_panel("MatchDeveloperPanel")
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var box := panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "开发者调试"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back := Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func():
		panel.visible = false
		if _game_menu_settings:
			_game_menu_settings.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)

	var hint := Label.new()
	hint.text = "默认关闭。写入本地设置文件，与对局存档无关。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(hint, false, UiLayout.font_size(13, self))
	box.add_child(hint)

	_dev_master_check = CheckBox.new()
	_dev_master_check.text = "启用开发者调试"
	_dev_master_check.button_pressed = GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_master_check, UiLayout.font_size(16, self))
	_dev_master_check.toggled.connect(_on_match_dev_master_toggled)
	box.add_child(_dev_master_check)

	_dev_soften_check = CheckBox.new()
	_dev_soften_check.text = "我方扣血软化（失败惩罚减为 1）"
	_dev_soften_check.button_pressed = GameSession.player_citadel_soften
	_dev_soften_check.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_soften_check, UiLayout.font_size(16, self))
	_dev_soften_check.toggled.connect(_on_match_dev_soften_toggled)
	box.add_child(_dev_soften_check)

	_dev_economy_check = CheckBox.new()
	_dev_economy_check.text = "人机双倍经济（我方战斗收入×同人机）"
	_dev_economy_check.button_pressed = GameSession.player_ai_double_economy
	_dev_economy_check.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_economy_check, UiLayout.font_size(16, self))
	_dev_economy_check.toggled.connect(_on_match_dev_economy_toggled)
	box.add_child(_dev_economy_check)

	_dev_enemy_layout_check = CheckBox.new()
	_dev_enemy_layout_check.text = "敌方布局调整许可（暂停时可拖敌方单位）"
	_dev_enemy_layout_check.button_pressed = GameSession.enemy_layout_adjust
	_dev_enemy_layout_check.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(_dev_enemy_layout_check, UiLayout.font_size(16, self))
	_dev_enemy_layout_check.toggled.connect(_on_match_dev_enemy_layout_toggled)
	box.add_child(_dev_enemy_layout_check)

	var swap_btn := Button.new()
	swap_btn.text = "换边（双方棋子中心对称交换）"
	swap_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	swap_btn.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(swap_btn, UiLayout.font_size(16, self))
	swap_btn.pressed.connect(_on_match_dev_swap_sides)
	swap_btn.name = "DevSwapSidesBtn"
	box.add_child(swap_btn)

	var ship_data_btn := Button.new()
	ship_data_btn.text = "全舰船装备数据调整（暂停对局）"
	ship_data_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	ship_data_btn.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(ship_data_btn, UiLayout.font_size(16, self))
	ship_data_btn.pressed.connect(_on_match_dev_ship_data)
	ship_data_btn.name = "DevShipDataBtn"
	box.add_child(ship_data_btn)
	return panel


func _build_save_panel() -> Control:
	var panel := _make_modal_panel("MatchSavePanel")
	var box := panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row := HBoxContainer.new()
	var cap := Label.new()
	cap.text = "保存当前局为存档"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back := Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func():
		panel.visible = false
		if _game_menu:
			_game_menu.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)
	var hint := Label.new()
	hint.text = "写入命名槽，可在主菜单「读取存档」加载；不覆盖旗舰测试。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(hint, false, UiLayout.font_size(14, self))
	box.add_child(hint)
	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "存档名称"
	_save_name_edit.add_theme_font_size_override("font_size", UiLayout.font_size(16, self))
	box.add_child(_save_name_edit)
	var confirm := _menu_action_btn("确认保存", _confirm_save_named_slot)
	box.add_child(confirm)
	return panel


func _open_settings_panel() -> void:
	if _game_menu:
		_game_menu.visible = false
	if _game_menu_dev:
		_game_menu_dev.visible = false
	_sync_game_menu_settings_widgets()
	if _game_menu_settings:
		_game_menu_settings.visible = true


func _open_developer_panel() -> void:
	if _game_menu_settings:
		_game_menu_settings.visible = false
	_sync_dev_debug_widgets()
	if _game_menu_dev:
		_game_menu_dev.visible = true


func _sync_dev_debug_widgets() -> void:
	if _dev_master_check:
		_dev_master_check.set_pressed_no_signal(GameSession.developer_debug_enabled)
	var master_on := GameSession.developer_debug_enabled
	if _dev_soften_check:
		_dev_soften_check.set_pressed_no_signal(GameSession.player_citadel_soften)
		_dev_soften_check.disabled = not master_on
	if _dev_economy_check:
		_dev_economy_check.set_pressed_no_signal(GameSession.player_ai_double_economy)
		_dev_economy_check.disabled = not master_on
	if _dev_enemy_layout_check:
		_dev_enemy_layout_check.set_pressed_no_signal(GameSession.enemy_layout_adjust)
		_dev_enemy_layout_check.disabled = not master_on
	if _game_menu_dev:
		var swap_btn := _game_menu_dev.find_child("DevSwapSidesBtn", true, false) as Button
		if swap_btn:
			swap_btn.disabled = not master_on
		var ship_btn := _game_menu_dev.find_child("DevShipDataBtn", true, false) as Button
		if ship_btn:
			ship_btn.disabled = not master_on


func _on_match_dev_master_toggled(on: bool) -> void:
	GameSession.set_developer_debug_enabled(on)
	if _dev_soften_check:
		_dev_soften_check.disabled = not on
	if _dev_economy_check:
		_dev_economy_check.disabled = not on
	if _dev_enemy_layout_check:
		_dev_enemy_layout_check.disabled = not on
	if _game_menu_dev:
		var swap_btn := _game_menu_dev.find_child("DevSwapSidesBtn", true, false) as Button
		if swap_btn:
			swap_btn.disabled = not on
		var ship_btn := _game_menu_dev.find_child("DevShipDataBtn", true, false) as Button
		if ship_btn:
			ship_btn.disabled = not on


func _on_match_dev_soften_toggled(on: bool) -> void:
	GameSession.set_player_citadel_soften(on)


func _on_match_dev_economy_toggled(on: bool) -> void:
	GameSession.set_player_ai_double_economy(on)


func _on_match_dev_enemy_layout_toggled(on: bool) -> void:
	GameSession.set_enemy_layout_adjust(on)


func _on_match_dev_swap_sides() -> void:
	if not GameSession.developer_debug_enabled:
		return
	if board == null:
		return
	var r: Dictionary = board.swap_sides_center_symmetric()
	if bool(r.get("ok", false)):
		show_notice("已换边（%d 艘）" % int(r.get("count", 0)))
		_refresh_hud()
	else:
		show_notice("换边仅备战阶段可用" if str(r.get("reason", "")) == "prepare_only" else "换边失败")


## UI_AND_SHELL §2.5.1 — pauses the match; guests in a net match may not edit (host authority).
func _on_match_dev_ship_data() -> void:
	if not GameSession.developer_debug_enabled:
		return
	var net := _nullsec_net_session()
	if GameSession.pending_mode == "nullsec" and net != null and not net.is_host:
		show_notice("联机对局以房主舰船数据为准，本机改动不生效")
		return
	if _ship_data_editor == null or not is_instance_valid(_ship_data_editor):
		_ship_data_editor = ShipDataEditor.new()
		_ship_data_editor.closed.connect(_on_ship_data_editor_closed)
		hud.add_child(_ship_data_editor)
	if _game_menu_dev:
		_game_menu_dev.visible = false
	_ship_data_editor.open(true)


func _on_ship_data_editor_closed(changed_ids: Array, equipment_changed: bool = false) -> void:
	if changed_ids.is_empty() and not equipment_changed:
		if _game_menu_dev:
			_game_menu_dev.visible = true
		return
	var what := "已保存 %d 艘舰船数据" % changed_ids.size() if not changed_ids.is_empty() else "已保存装备数据"
	if not changed_ids.is_empty() and equipment_changed:
		what = "已保存 %d 艘舰船与装备数据" % changed_ids.size()
	show_notice(what)
	## Host edits are authoritative mid-match — push the table to guests at once (§3.7).
	## Equipment counts: manned DPH derives from it (SHIP_STATS_V2 §2.2).
	var net := _nullsec_net_session()
	if net != null and net.is_host and net.match_started:
		net.broadcast_ships_table()
		show_notice("%s并同步给房客" % what)
	if _game_menu_dev:
		_game_menu_dev.visible = true


## Guest side of SEMI_ASYNC_NETPLAY §3.7 — host table landed (join or mid-match edit).
func _on_host_ships_applied(mid_match: bool) -> void:
	show_notice("房主已更新舰船数据 · 已临时应用" if mid_match else "已临时应用房主舰船数据")
	_refresh_hud()


func _nullsec_net_session() -> NullsecNetSession:
	if GameSession == null:
		return null
	return GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession


func _open_save_panel() -> void:
	if _game_menu:
		_game_menu.visible = false
	if _save_name_edit:
		var mode_l := "对战" if str(GameSession.pending_mode) == "versus" else "无尽"
		_save_name_edit.text = "%s · 第%d回合 · Lv%d" % [
			mode_l,
			maxi(1, match_ctrl.battle_game_stage_count if match_ctrl else 1),
			match_ctrl.player_level if match_ctrl else 1,
		]
	if _game_menu_save:
		_game_menu_save.visible = true


func _confirm_save_named_slot() -> void:
	var name := _save_name_edit.text if _save_name_edit else ""
	var r := MatchSave.save_as_named_slot(name, match_ctrl, board, ai)
	if bool(r.get("ok", false)):
		show_notice("已保存：%s" % str(r.get("name", "")))
		if _game_menu_save:
			_game_menu_save.visible = false
		if _game_menu:
			_game_menu.visible = true
	elif str(r.get("reason", "")) == "nullsec":
		show_notice("多人联机局不入存档（战绩见主菜单历史战绩）")
	else:
		show_notice("保存失败")


func _return_to_main_menu() -> void:
	if match_ctrl and match_ctrl.has_method("force_autosave"):
		match_ctrl.force_autosave()
	_close_game_menu()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _sync_game_menu_settings_widgets() -> void:
	if _fps_slider:
		_fps_slider.value = GameSession.target_fps
	if _fps_lbl:
		_fps_lbl.text = str(int(GameSession.target_fps))
	var bgm := _BgMusic.instance()
	if _bgm_check and bgm:
		_bgm_check.button_pressed = bgm.enabled
	if _bgm_slider and bgm:
		_bgm_slider.value = bgm.volume_pct
	if _bgm_lbl and bgm:
		_bgm_lbl.text = str(int(bgm.volume_pct))


func _on_match_fps_changed(v: float) -> void:
	GameSession.target_fps = int(v)
	Engine.max_fps = GameSession.target_fps
	GameSession.save_settings()
	if _fps_lbl:
		_fps_lbl.text = str(GameSession.target_fps)


func _on_match_bgm_toggled(on: bool) -> void:
	var bgm := _BgMusic.instance()
	if bgm:
		bgm.set_enabled(on)


func _on_match_bgm_volume_changed(v: float) -> void:
	if _bgm_lbl:
		_bgm_lbl.text = str(int(v))
	var bgm := _BgMusic.instance()
	if bgm:
		bgm.set_volume_pct(v)


func _on_pause_pressed() -> void:
	## Nullsec has no pause (UI_AND_SHELL §2.2A).
	if GameSession != null and str(GameSession.pending_mode) == "nullsec":
		return
	if _game_menu_open():
		return
	get_tree().paused = not get_tree().paused
	var btn := hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if btn:
		btn.text = "继续" if get_tree().paused else "暂停"
	show_notice("已暂停" if get_tree().paused else "继续")

func _on_collapse_left() -> void:
	_collapse_left = not _collapse_left
	_apply_adaptive_hud_layout()

func _on_collapse_right() -> void:
	_collapse_right = not _collapse_right
	_apply_adaptive_hud_layout()

func _on_collapse_bottom() -> void:
	var was_collapsed := _collapse_bottom
	_collapse_bottom = not _collapse_bottom
	_apply_adaptive_hud_layout()
	## Free / observe view: HUD only — never move the camera for shop or stage chrome.
	if _camera_manual_pose():
		return
	## Shop expand → view 2. Shop collapse → first default (default mode).
	## Battle: bottom toggle does not move the camera.
	if match_ctrl != null and match_ctrl.stage == MatchController.Stage.BATTLE:
		return
	if was_collapsed and not _collapse_bottom:
		_on_shop_expanded_camera()
	elif not was_collapsed and _collapse_bottom:
		_on_shop_collapsed_camera()

func _on_stage_changed_ui(stage: int) -> void:
	var stage_label := "准备" if stage == MatchController.Stage.PREPARE else ("战斗" if stage == MatchController.Stage.BATTLE else "结束")
	_append_battle_log("进入%s阶段" % stage_label)
	## Battle start: auto-collapse side chrome + shop once; toggles remain available.
	## Right = battle log (auto-collapse once on enter Battle).
	if stage == MatchController.Stage.BATTLE:
		_collapse_left = true
		_collapse_right = true
		_collapse_bottom = true
		_cam_pose_before_shop_valid = false
		_cam_pose_before_shop.clear()
		_apply_adaptive_hud_layout()
		## PVP: prepare stayed home — teleport (if guest) then fight starts immediately (§4.1).
		if GameSession.pending_mode == "nullsec" and _nullsec_pve and not _nullsec_pve.is_pve_task():
			_nullsec_pvp_battle_teleport()
		## Free / observe view keeps current pose across combat enter.
		if not _camera_manual_pose():
			_apply_camera_view_dict(_camera_primary_view())
			## Keep slot grid until camera settles on first default view.
			_show_slot_markers_now()
			_pending_hide_slot_markers = true
		else:
			_hide_slot_markers_now()
	# 回合结束：战斗 -> 准备；展开左栏+右栏+底栏一次；default 切视角 2；free/observe 不动镜头。
	# 负安局若要播末日/击毁，先把 HUD/镜头转场压住，等演出结束再走 prepare 展示。
	if _last_match_stage == MatchController.Stage.BATTLE and stage == MatchController.Stage.PREPARE:
		if GameSession.pending_mode == "nullsec":
			_nullsec_prepare_ui_pending = true
			_nullsec_after_battle_into_prepare()
			if not _doomsday_busy and not _titan_kill_busy:
				_apply_nullsec_prepare_presentation()
		else:
			_collapse_left = false
			_collapse_right = false
			_collapse_bottom = false
			_apply_adaptive_hud_layout()
			_show_slot_markers_now()
			if not _camera_manual_pose():
				_cam_headup_phase = 0
				_cam_headup_t = 0.0
				_cam_headup_offset_deg = 0.0
				_cam_default_pitch_deg = float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg))
				_cam_pose_before_shop = _capture_cam_pose()
				_cam_pose_before_shop_valid = true
				_apply_camera_view_dict(_camera_secondary_view())
	elif not _camera_manual_pose():
		_trigger_camera_headup("stage_change")
	_last_match_stage = stage
	_refresh_hud()
	var diag := SessionDiagnostics.instance()
	if diag and diag.has_method("log_event"):
		diag.log_event("stage", stage_label)

func _apply_nullsec_prepare_presentation() -> void:
	if not _nullsec_prepare_ui_pending:
		return
	_nullsec_prepare_ui_pending = false
	_collapse_left = false
	_collapse_right = false
	_collapse_bottom = false
	_apply_adaptive_hud_layout()
	_show_slot_markers_now()
	if not _camera_manual_pose():
		_cam_headup_phase = 0
		_cam_headup_t = 0.0
		_cam_headup_offset_deg = 0.0
		_cam_default_pitch_deg = float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg))
		_cam_pose_before_shop = _capture_cam_pose()
		_cam_pose_before_shop_valid = true
		_apply_camera_view_dict(_camera_secondary_view())

func _nullsec_after_battle_into_prepare() -> void:
	## Lock next creep roster immediately at previous round end.
	if _titan_kill_busy or _doomsday_busy:
		_nullsec_prepare_pending = true
		return
	if _nullsec_pve and match_ctrl:
		## Read the outcome frozen at combat end: by now every field hull has been
		## reloaded, so counting the board here would score every round as a draw.
		var result := str(match_ctrl.last_round_result)
		var player_lost := result == "lose"
		## Salvage: the escorted freighter must still have been alive at the last tick.
		if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
			_nullsec_pve.freighter_alive = bool(match_ctrl.last_round_freighter_alive)
		## PVE failures do not deduct titan HP — evaluate BEFORE locking next task.
		var was_pve := _nullsec_pve.is_pve_task()
		if not was_pve:
			_nullsec_resolve_pvp_doomsday(result)
			if _doomsday_busy or _titan_kill_busy:
				## Hold the next round until the beam (and any hull kill) has played out.
				_nullsec_prepare_pending = true
				return
		elif player_lost:
			show_notice("PVE 失败 · 不扣泰坦血")
	_nullsec_enter_next_round()

func _nullsec_enter_next_round() -> void:
	_apply_nullsec_prepare_presentation()
	if _nullsec_pve and match_ctrl:
		_nullsec_lock_next_creeps()
	## Only slide-in creeps on PVE prepares.
	if _nullsec_pve and _nullsec_pve.is_pve_task():
		_nullsec_pvp_guest = false
		_set_rival_berth_visible(false)
		_restore_local_home_skybox()
		_nullsec_on_prepare_begin()
	elif _nullsec_pve:
		## PVP prepare stays on the local home field; battle does the guest hop (§4.1).
		_nullsec_prepare_pvp_round()
	if _nullsec_speed:
		_nullsec_speed.reset_round()


## Own region skybox — Prepare always, and after a guest PVP battle.
func _restore_local_home_skybox() -> void:
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", -1))
	var region := _seat_region(local_seat)
	if region != "":
		apply_region_skybox(region)
	_nullsec_watch_seat = local_seat
	_refresh_region_label()


func _nullsec_prepare_pvp_round() -> void:
	## Prepare: clear creeps, rebuild rival army, stay on own skybox (MULTIPLAYER_PVP §4.1).
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", 0))
	var rival := _nullsec_rival_seat(local_seat)
	_set_rival_berth_visible(true)
	_restore_local_home_skybox()
	_nullsec_pvp_guest = false
	if rival < 0:
		## Nobody to travel to — the round runs at home against whatever the AI seat fields.
		show_notice("PVP 准备 · 本房无对手席位 · 本场主场进行")
	else:
		if _nullsec_rng:
			_nullsec_pvp_guest = _nullsec_rng.roll_int(
				maxi(1, int(match_ctrl.round_phase_value) if match_ctrl else 1), "pvp_home", 0, 1
			) == 0
		else:
			_nullsec_pvp_guest = (Time.get_ticks_msec() % 2) == 0
		if _nullsec_pvp_guest:
			show_notice("PVP 准备 · 对手席位 %02d · 交战进客场" % (rival + 1))
		else:
			show_notice("PVP 准备 · 对手席位 %02d · 本场主场开战" % (rival + 1))
	for s in board.all_ships().duplicate():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		## PVP round: drop the creep army and any leftover salvage freighter with it.
		if int(s.team_id) == ShipUnit.TEAM_AI or s.is_protect_target:
			board.remove_ship_node(s)
	if ai and ai.has_method("rebuild_round_army"):
		ai.rebuild_round_army()
	if ai and ai.has_method("finalize_prepare"):
		ai.finalize_prepare()
	## Rival seat is a titan holder too — its buff rides the same fetter rail.
	board.set_titan_fetter_race(ShipUnit.TEAM_AI, _seat_titan_race(rival))
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())


func _nullsec_pvp_battle_teleport() -> void:
	## Prepare→Battle only: guest hops to rival skybox + cyno flash, then combat is already on.
	var local_seat := int(GameSession.pending_nullsec.get("local_seat", 0))
	var rival := _nullsec_rival_seat(local_seat)
	var land_team := ShipUnit.TEAM_PLAYER if _nullsec_pvp_guest else ShipUnit.TEAM_AI
	if _nullsec_pvp_guest and rival >= 0:
		var region := _seat_region(rival)
		if region != "":
			apply_region_skybox(region)
		_nullsec_watch_seat = rival
		_refresh_region_label()
		show_notice("客场作战 · 诱导落位 · 开战")
	else:
		show_notice("主场迎战 · 对手诱导落位 · 开战")
	## CapitalJumpFx flash-land, no travel path — guest = our hulls; home = rival hulls.
	for s in board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		if int(s.team_id) != land_team or s.is_unmanned:
			continue
		if str(s.slot_type) != "field":
			continue
		var land := s.global_position
		var fx = _CapitalJumpFx.new()
		world.add_child(fx)
		fx.play(s, land, 0.85)


func _set_rival_berth_visible(v: bool) -> void:
	## Opposing titan is only on field for player-vs-player rounds (§2.4a).
	if _rival_titan_berth and is_instance_valid(_rival_titan_berth):
		_rival_titan_berth.visible = v


func _append_battle_log(text: String) -> void:
	var line := str(text).strip_edges()
	if line.is_empty():
		return
	_battle_log_lines.append(line)
	while _battle_log_lines.size() > _BATTLE_LOG_MAX:
		_battle_log_lines.pop_front()
	_refresh_battle_log_list()

func _refresh_battle_log_list() -> void:
	var list := hud.get_node_or_null("Root/RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogScroll/BattleLogList") as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	for entry in _battle_log_lines:
		var lab := Label.new()
		lab.text = str(entry)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiAssets.apply_label_font(lab, false, UiLayout.font_size(11, list))
		lab.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		list.add_child(lab)
	call_deferred("_scroll_battle_log_to_end")

func _scroll_battle_log_to_end() -> void:
	var scroll := hud.get_node_or_null("Root/RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogScroll") as ScrollContainer
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	if bar:
		scroll.scroll_vertical = int(bar.max_value)
