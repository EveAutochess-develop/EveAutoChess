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
var firing_fx: Node = null
var ai: AiController
var pointer: PointerInput
var _nullsec_speed: RoundSpeedController
var _speed_dropdown: SpeedDropdownMenu
var _nullsec_pve: NullsecPveDirector
var _nullsec_rng: MatchRng
var _doomsday_resolver: TitanDoomsdayResolver
var _settlement_panel: NullsecSettlementPanel
## Prepare fleet net sync: suppress board_changed echo + debounce identical snapshots.
var _applying_rival_fleet: bool = false
var _fleet_push_sig: String = ""
var _fleet_apply_sig: String = ""
## Barrier released but rival fleet not yet synced — defer commit_prepare_complete.
var _pending_enter_battle: bool = false
var _fleet_push_last_msec: int = 0
var _fleet_push_pending: Array = []
var _fleet_push_debounce_tok: int = 0
const _FLEET_PUSH_MIN_MSEC: int = 200

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
var _shop_bought_ship: ShipUnit = null
var _equip_detail_panel: PanelContainer = null
## PC hover tooltips: hide when pointer leaves source/panel (HUD rebuild must not stick).
var _equip_detail_from_hover: bool = false
var _equip_detail_fit_ship: ShipUnit = null
var _equip_detail_fit_slot: int = -1
var _equip_inv_ui_sig: String = ""
var _equip_drag_source: String = ""
var _equip_drag_shop_idx: int = -1
var _equip_drag_inv_idx: int = -1
var _equip_drag_ship: ShipUnit = null
var _equip_drag_fit_slot: int = -1
var _equip_drag_item_id: String = ""
var _equip_drag_active: bool = false
var _equip_press_screen: Vector2 = Vector2.ZERO
var _equip_ghost: Control = null
const _SHOP_DRAG_THRESHOLD_PX: float = 40.0
const _SHOP_BUY_TIP: String = "拖离商店即购买，松手落到备战席或棋盘"
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
## After exit observe: wait then smooth-blend to default (UI_AND_SHELL §2.3.1).
var _observe_return_delay_left: float = 0.0
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
## Last time the player touched shop/side-panel chrome — Battle-enter auto-collapse
## backs off for a short grace window so it doesn't yank a panel out from under a tap.
var _hud_interact_ms: int = 0
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
const _BATTLE_LOG_MAX: int = 40
var _citadel_hp_bar: Node3D = null
const _CITADEL_BAR_SCRIPT: Script = preload("res://scripts/ship/citadel_health_bar.gd")
## Nullsec: seat titan berth replaces the citadel (MULTIPLAYER_PVP §2.4a).
var _titan_berth: TitanBerth = null
var _rival_titan_berth: TitanBerth = null
var _titan_hp_bar: Node3D = null
var _rival_titan_hp_bar: Node3D = null
const _TITAN_BAR_SCRIPT: Script = preload("res://scripts/ship/titan_hp_bar.gd")
const _TitanKillSequence: Script = preload("res://scripts/match/titan_kill_sequence.gd")
## Fetter that marks a hull as an exploration ship (data/fetters/exploration.json).
const EXPLORE_FETTER_ID: String = "exploration"
const SCOUT_GATE_HINT: String = "刺探需备战席/场上有探索护卫（富豪级·苍鹭级·探索级·伊米卡斯级）"
const SCOUT_TARGET_CD_MS: int = 10000
const SCOUT_DEPART_SPEED: float = 36.0
const SCOUT_DEPART_MAX_S: float = 8.0
## Titan kill shake: wall-clock end (ms). 0 = inactive.
var _titan_shake_until_ms: int = 0
## seat_id -> Time.get_ticks_msec() until which that seat cannot be scouted again.
var _scout_cd_until_ms: Dictionary = {}
## Departing explore frigates: [{ship, vel: Vector3, age: float}]
var _scout_departs: Array = []
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
## Presentation hold (doomsday/kill) — distinct from prepare-stuck deadlock freeze.
var _presentation_hold: bool = false
## Deferred settlement summary while doomsday/kill still playing.
var _settlement_pending_summary: String = ""
## seat -> {w,l,d} match-scoped win/loss/draw tallies.
var _wld_by_seat: Dictionary = {}
## seat -> lifetime kills this match.
var _kills_by_seat: Dictionary = {}
## Ignore remote doomsday play if we already fired locally this resolve.
var _doomsday_rpc_suppress: bool = false
## SEMI_ASYNC §6.2 — guest local W/L prediction vs host doomsday shots.
var _wl_pred_local: String = ""
var _wl_auth_shots: Array = []
var _wl_gap_notified: bool = false
## battle_done armed while doomsday still playing — apply after gate releases.
var _defer_prepare_clock_arm: bool = false
## MULTIPLAYER_PVP §7.1 — human↔human PVP round title tracker (best-effort).
var _combat_eval: CombatEvalTracker = null
var _combat_eval_active: bool = false
## seat_id -> Array of title-name Strings accrued across this table's PVP rounds.
var _match_titles: Dictionary = {}
## Match-scoped eval meta (羊望未来 / streak / scout / rejoin / 神之一手).
var _eval_first_purchase_iid: int = 0
var _eval_sold_first_this_prepare: bool = false
var _eval_bought_capital_this_prepare: bool = false
var _eval_scout_vs_rival: int = 0
var _eval_human_streak: Dictionary = {} ## seat -> int
var _eval_human_losses: Dictionary = {} ## seat -> int
var _eval_rejoined: Dictionary = {} ## seat -> bool
var _eval_wins_since_rejoin: Dictionary = {} ## seat -> int
var _eval_prev_layout: Dictionary = {} ## seat -> {fp, lost}
var _eval_prepare_rival_seat: int = -1
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
## Rival berth slide — lowsec only (MULTIPLAYER_PVP §2.5).
var _rival_titan_intro_done: bool = false
var _rival_intro_active: bool = false
var _rival_intro_start: Vector3 = Vector3.ZERO
var _rival_intro_end: Vector3 = Vector3.ZERO
const _TITAN_INTRO_DUR_S: float = 1.35
const _TITAN_INTRO_SLIDE_Z: float = 28.0
## Shared read-only spectate (seat_spectate / mid_join / eliminated).
var _nullsec_spectating: bool = false
var _nullsec_spectate_reason: String = ""
var _nullsec_watch_seat: int = -1
## SEMI_ASYNC §3.0a — prepare freeze / barrier desync pulse escape.
var _prep_pulse_acc_s: float = 0.0
var _prep_freeze_wall_ms: int = 0
const PREP_PULSE_S: float = 3.0
const PREP_FORCE_ARM_MS: int = 20000
var _spectate_leave_btn: Button = null
## SEMI_ASYNC NetBattleSession (host authority / guest repredict).
var _net_battle: NetBattleSession = null
var _net_jobs_ready_for_titan: bool = true
const _BgMusic: Script = preload("res://scripts/audio/bg_music.gd")
const _CapitalJumpFx: Script = preload("res://scripts/combat/capital_jump_fx.gd")
const _CAM_MOVE_SPEED: float = 8.0
var _exp_hold_active: bool = false
var _exp_hold_t: float = 0.0
var _exp_hold_repeat_t: float = 0.0
var _exp_hold_repeating: bool = false
## ECONOMY_AND_SHOP §3 / UI_AND_SHELL §2.5 — hold delay then interval buys.
const _EXP_HOLD_DELAY_S: float = 0.5
const _EXP_HOLD_INTERVAL_S: float = 0.05
const _CAM_PITCH_SPEED: float = 35.0
const _CAM_YAW_SPEED: float = 45.0
const _SHOP_META: String = "Shop/ShopCol/ShopContent/MetaRow"
const _SHOP_LEFT: String = "Shop/ShopCol/ShopContent/MetaRow/LeftCtrl"
const _SHOP_MID: String = "Shop/ShopCol/ShopContent/MetaRow/MetaMid"
const _SHOP_INNER: String = "Shop/ShopCol/ShopContent/ShopInner"
const _SHOP_SLOTS: String = "Shop/ShopCol/ShopContent/ShopInner/ShopSlots"
const _SHOP_EQUIP_SLOTS: String = "Shop/ShopCol/ShopContent/MetaRow/LeftCtrl/LeftBtns/EquipmentSlots"
const _RESERVE_GRID_PATH: String = "LeftCol/LeftInner/LeftContent/ReserveGrid"
const _BONUS: String = "LeftCol/LeftInner/LeftContent/BonusScroll/BonusContainer"
const _BONUS_FALLBACK: String = "LeftCol/LeftInner/LeftContent/BonusContainer"
const _EQUIP_INVENTORY_SIZE: int = 16
const _EQUIP_ICON_VIEW: Script = preload("res://scripts/ui/equipment_icon_view.gd")
const _EQUIP_DRAG_THRESHOLD_PX: float = 24.0
const _INFO_PANEL: String = "RightCol/RightInner/RightContent/InfoPanel"
const _BONUS_SCROLL: String = "LeftCol/LeftInner/LeftContent/BonusScroll"
const _INFO_SCROLL: String = "InfoScroll"
const _ROUND: String = "RoundBar/RoundInner"
## Detail panel stays up this long after a tap / drag release (UI_AND_SHELL §2.5).
const INFO_HOLD_S: float = 10.0
## Match enter boot (no await — call_deferred+await can stall forever on Godot).
## 0 idle · 1 create MapEnv · 2 step asteroids · 3 start_match
var _boot_phase: int = 0
var _boot_env: MapEnv = null
var _boot_mode: String = ""
var _boot_resume_data: Dictionary = {}

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	add_to_group("match_root")
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Overlay first so lobby text "正在进入对局场景" advances even if reload is slow.
	MatchLoadOverlay.set_phase("正在加载对局配置", 0.28)
	## Pick up balance/visual JSON edits without restarting the editor.
	DataStore.reload_all()
	MatchLoadOverlay.set_phase("正在准备对局控制器", 0.32)
	@warning_ignore("unsafe_method_access")
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
	@warning_ignore("unsafe_method_access")
	firing_fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	ai.process_mode = Node.PROCESS_MODE_PAUSABLE
	pointer.process_mode = Node.PROCESS_MODE_ALWAYS
	## Esc / 菜单 while tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	board.setup(world)
	_ensure_ground()
	shop.bind(match_ctrl, board)
	## Solo / until nullsec payload: match_seed stream for shop (SEMI_ASYNC §2).
	var solo_rng: MatchRng = MatchRng.new()
	solo_rng.configure(
		int(Time.get_unix_time_from_system()) ^ int(hash("eveac_solo")),
		MatchRng.compute_rules_hash()
	)
	ShopController.bind_match_rng(solo_rng, "shop")
	@warning_ignore("unsafe_method_access")
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
	if not AdminBus.after_handoff.is_connected(_on_admin_after_for_combat_eval):
		AdminBus.after_handoff.connect(_on_admin_after_for_combat_eval)
	var net_sess: NullsecNetSession = _nullsec_net_session()
	if net_sess and not net_sess.ships_override_applied.is_connected(_on_host_ships_applied):
		net_sess.ships_override_applied.connect(_on_host_ships_applied)
	if net_sess and not net_sess.match_terminated_host_lost.is_connected(_on_match_terminated_host_lost):
		net_sess.match_terminated_host_lost.connect(_on_match_terminated_host_lost)
	if net_sess and not net_sess.host_migrated.is_connected(_on_nullsec_host_migrated):
		net_sess.host_migrated.connect(_on_nullsec_host_migrated)
	var diag: SessionDiagnostics = SessionDiagnostics.instance()
	if diag:
		diag.bind_match(self)
	SessionDiagnostics.log("match.enter", "mode=%s" % str(GameSession.pending_mode))
	_boot_mode = str(GameSession.pending_mode)
	_boot_resume_data = {}
	if GameSession.resume_save:
		if not GameSession.resume_payload.is_empty():
			_boot_resume_data = GameSession.resume_payload
		else:
			var slot_id: String = str(GameSession.resume_slot_id)
			if slot_id != "":
				_boot_resume_data = MatchSave.load_slot_dict(slot_id)
			if _boot_resume_data.is_empty():
				_boot_resume_data = MatchSave.load_dict()
		GameSession.resume_payload = {}
		## Save mode is authoritative for continue / named load (MATCH_FLOW §5.0b).
		## Must lock before MapEnv stepwise so versus keeps the AI citadel.
		## Wrong pending_mode here used to rebuild as endless then overwrite last_match.
		var resume_mode: String = MatchSave.normalize_solo_mode(_boot_resume_data.get("mode", _boot_mode))
		if resume_mode == "" and str(_boot_resume_data.get("mode", "")) != "nullsec":
			resume_mode = MatchSave.normalize_solo_mode(_boot_mode)
			if resume_mode == "":
				resume_mode = "versus"
		if resume_mode != "":
			_boot_mode = resume_mode
			GameSession.pending_mode = resume_mode
	## Drive map load + start_match from _process (await from call_deferred can hang).
	_boot_phase = 1
	MatchLoadOverlay.set_phase("正在布置战场环境", 0.34)

func _setup_nullsec_runtime() -> void:
	var payload: Dictionary = GameSession.pending_nullsec
	_nullsec_rng = MatchRng.new()
	_nullsec_rng.configure(TypedVariant.as_int(payload.get("match_seed", Time.get_unix_time_from_system()), int(Time.get_unix_time_from_system())), MatchRng.compute_rules_hash())
	ShopController.bind_match_rng(_nullsec_rng, "shop")
	_nullsec_speed = RoundSpeedController.new()
	_nullsec_speed.speed_changed.connect(_on_nullsec_speed_changed)
	_nullsec_speed.force_draw_remaining.connect(_on_nullsec_force_draw)
	_nullsec_pve = NullsecPveDirector.new()
	_nullsec_pve.always_pvp = NullsecNetSession.is_lowsec(str(payload.get("security_mode", "nullsec")))
	_nullsec_pve.setup(_nullsec_rng, 1)
	_nullsec_pve.pick_task(1)
	## Seat economy for the AI players starts with the humans' opening, then banks
	## gold/exp every round so a later PVP rival is not a level-1 fleet.
	if ai and ai.has_method("init_economy"):
		ai.init_economy()
	## Titan buff rides the fetter rail (MULTIPLAYER_PVP §2.3): always on from setup.
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())
	## Lowsec (always_pvp): no R1 creeps / salvage freighter — seat PVP from round 1.
	if not _nullsec_pve.always_pvp:
		var gold: int = TypedVariant.as_int(match_ctrl.player_gold, 0) if match_ctrl else 0
		var level: int = TypedVariant.as_int(match_ctrl.player_level, 1) if match_ctrl else 1
		var pop: int = 0
		if match_ctrl and match_ctrl.has_method("population_limit"):
			pop = TypedVariant.as_int(match_ctrl.population_limit(), 0)
		else:
			pop = level + 1
		_nullsec_pve.lock_creeps(gold, level, maxi(1, pop))
		if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
			_nullsec_pve.pick_freighter_id(_local_titan_race_for_ui())
	_doomsday_resolver = TitanDoomsdayResolver.new()
	## Lowsec: fail/draw titan pipe damage ×0.25 (MULTIPLAYER_PVP §2.4).
	_doomsday_resolver.pvp_loss_mul = 0.25 if _nullsec_pve.always_pvp else 1.0
	if not _doomsday_resolver.return_home_due.is_connected(_on_titan_return_home):
		_doomsday_resolver.return_home_due.connect(_on_titan_return_home)
	@warning_ignore("unsafe_cast")
	var seats: Array = payload.get("seats", []) as Array
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		var race: String = str(s.get("titan_race", "caldari"))
		if not NullsecNetSession.is_player_race(race):
			continue
		_doomsday_resolver.ensure_seat(TypedVariant.as_int(s.get("seat_id", 0), 0), race)
	_refresh_titan_hp_bar()
	@warning_ignore("unsafe_method_access")
	_TitanKillSequence.ensure_wreck_ship_defs()
	var net_ticket: NullsecNetSession = _nullsec_net_session()
	if net_ticket:
		net_ticket.write_rejoin_ticket()
		if not net_ticket.rejected.is_connected(_on_nullsec_rejected):
			net_ticket.rejected.connect(_on_nullsec_rejected)
	_speed_dropdown = SpeedDropdownMenu.new()
	_speed_dropdown.controller = _nullsec_speed
	_speed_dropdown.local_nick = "本地"
	hud.add_child(_speed_dropdown)
	_speed_dropdown.vote_changed.connect(func(spd: float) -> void:
		var net_spd: NullsecNetSession = _nullsec_net_session()
		if net_spd and net_spd.needs_stage_barrier():
			net_spd.push_speed_vote(spd)
		else:
			var ls: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
			if _nullsec_speed:
				_nullsec_speed.set_vote(ls, spd)
			show_notice("有人发起对局速度调整 → %s" % SpeedDropdownMenu._label(spd))
			_apply_resolved_speed()
	)
	var net_wire: NullsecNetSession = _nullsec_net_session()
	if net_wire:
		if not net_wire.speed_vote_received.is_connected(_on_speed_vote_received):
			net_wire.speed_vote_received.connect(_on_speed_vote_received)
		if not net_wire.doomsday_play_received.is_connected(_on_doomsday_play_received):
			net_wire.doomsday_play_received.connect(_on_doomsday_play_received)
		_sync_required_speed_seats()
	_settlement_panel = NullsecSettlementPanel.new()
	hud.add_child(_settlement_panel)
	_wire_nullsec_scout()
	_wire_nullsec_prepare_sync()
	_setup_net_battle_session()
	## 王者归来：本 match 以重连票入局则标记本席已重连。
	if TypedVariant.as_bool(payload.get("rejoin", false), false):
		var rs: int = TypedVariant.as_int(payload.get("local_seat", 0), 0)
		_eval_rejoined[rs] = true
		_eval_wins_since_rejoin[rs] = 0
	var want_spec: bool = TypedVariant.as_bool(payload.get("spectator", false), false)
	if want_spec:
		enter_nullsec_spectate(str(payload.get("spectate_reason", "seat_spectate")))
	else:
		var mode_lbl: String = "低安局" if _nullsec_pve.always_pvp else "负安局"
		show_notice("%s · %s · 主场已分配" % [mode_lbl, _nullsec_pve.current_task])
		## Lowsec R1: PVP prepare (rival army), never creep slide-in.
		if _nullsec_pve.always_pvp:
			call_deferred("_nullsec_prepare_pvp_round")
		else:
			call_deferred("_nullsec_on_prepare_begin")
		call_deferred("_play_titan_berth_intro")

func enter_nullsec_spectate(reason: String = "seat_spectate") -> void:
	## Shared path: lobby「仅观战」/ mid-join / titan eliminated early-out.
	_nullsec_spectating = true
	_nullsec_spectate_reason = reason
	_titan_intro_done = true
	_rival_titan_intro_done = true
	_nullsec_prepare_pending = false
	_nullsec_prepare_ui_pending = false
	_apply_nullsec_spectate_hud()
	_wire_nullsec_scout()
	var first: int = _first_player_seat_id()
	if first >= 0:
		_switch_watch_seat(first)
	var label: String = "观战"
	if reason == "eliminated":
		label = "已淘汰 · 观战"
	elif reason == "mid_join":
		label = "中途观战"
	show_notice("%s · 可自由切换视角" % label)

## Host eject mid-match (MULTIPLAYER_MATCH_FLOW §2.1a) — no host-migration / ghost path,
## just tear the socket down and boot to the menu.
func _on_nullsec_rejected(reason: String) -> void:
	if str(reason) != "kicked":
		return
	show_notice("已被房主移出房间")
	var net: NullsecNetSession = _nullsec_net_session()
	if net:
		net.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _first_player_seat_id() -> int:
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			return TypedVariant.as_int(s.get("seat_id", 0), 0)
	return -1

func _apply_nullsec_spectate_hud() -> void:
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root:
		@warning_ignore("unsafe_cast")
		var shop_panel: Control = root.get_node_or_null("Shop") as Control
		if shop_panel:
			## Spectate keeps the Shop panel on screen but overlays a seat roster
			## (§4.4) on top of it — no buy/sell affordance for a read-only watcher.
			## `_apply_adaptive_hud_layout()` re-shows ShopContent every refresh based on
			## the collapse toggle, so we don't fight that: the roster is opaque and sits
			## in front (later PanelContainer child = drawn + hit-tested first).
			shop_panel.visible = true
			_build_spectate_roster(shop_panel)
		## Left (fetters/equipment) and right (detail) columns stay visible and
		## interactable so the watcher can still read the current seat's board state.
		@warning_ignore("unsafe_cast")
		var right: Control = root.get_node_or_null("RightCol") as Control
		if right:
			right.modulate.a = 1.0
			right.mouse_filter = Control.MOUSE_FILTER_STOP
		@warning_ignore("unsafe_cast")
		var left: Control = root.get_node_or_null("LeftCol") as Control
		if left:
			left.modulate.a = 1.0
			left.mouse_filter = Control.MOUSE_FILTER_STOP
	if _speed_dropdown:
		_speed_dropdown.visible = true
	_ensure_spectate_leave_btn()
	var scout: ScoutIntelButton = hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if scout:
		scout.visible = true
		scout.text = "切换视角"
	_refresh_spectate_watch_panels()

## Shop panel while spectating: seat roster instead of buy slots (§4.4 观战 HUD).
func _build_spectate_roster(shop_panel: Control) -> void:
	if shop_panel == null or not is_instance_valid(shop_panel):
		return
	@warning_ignore("unsafe_cast")
	var overlay: PanelContainer = shop_panel.get_node_or_null("SpectateRosterOverlay") as PanelContainer
	if overlay == null:
		overlay = PanelContainer.new()
		overlay.name = "SpectateRosterOverlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.09, 0.96)
		overlay.add_theme_stylebox_override("panel", sb)
		shop_panel.add_child(overlay)
	@warning_ignore("unsafe_cast")
	var roster: VBoxContainer = overlay.get_node_or_null("SpectateRoster") as VBoxContainer
	if roster == null:
		roster = VBoxContainer.new()
		roster.name = "SpectateRoster"
		roster.add_theme_constant_override("separation", 6)
		roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
		overlay.add_child(roster)
	overlay.visible = true
	for c: Node in roster.get_children():
		c.queue_free()
	var title: Label = Label.new()
	title.text = "观战席位 · 点选切换视角"
	UiAssets.apply_label_font(title, true, UiLayout.font_size(16, roster))
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	roster.add_child(title)
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if not NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			continue
		var seat_id: int = TypedVariant.as_int(s.get("seat_id", 0), 0)
		var nick: String = str(s.get("nick", ""))
		if nick == "":
			nick = "席位 %d" % (seat_id + 1)
		var btn: Button = Button.new()
		btn.text = "%s（席位 %d）" % [nick, seat_id + 1]
		btn.toggle_mode = true
		btn.button_pressed = seat_id == _nullsec_watch_seat
		btn.pressed.connect(_switch_watch_seat.bind(seat_id, ""))
		roster.add_child(btn)

## Best-effort read-only refresh for the seat currently being watched. There is no
## per-seat board snapshot API yet, so this re-applies the existing (local-board)
## fetter/equipment widgets and highlights the active roster button.
func _refresh_spectate_watch_panels() -> void:
	if not _nullsec_spectating:
		return
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	@warning_ignore("unsafe_cast")
	var shop_panel: Control = root.get_node_or_null("Shop") as Control
	if shop_panel and shop_panel.get_node_or_null("SpectateRosterOverlay") != null:
		## Rebuild rather than toggle-in-place, so the highlighted button always tracks
		## the live `_nullsec_watch_seat` (roster order can shift as seats join/leave).
		_build_spectate_roster(shop_panel)
	_refresh_fetter_ui(root)
	_refresh_equipment_inventory_ui()

func _ensure_spectate_leave_btn() -> void:
	@warning_ignore("unsafe_cast")
	var top_r: Control = hud.get_node_or_null("Root/TopRight") as Control
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
		var net: NullsecNetSession = GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession
		if net:
			net.request_mark_local_ghost()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	## Pure spectator seat: disconnect and leave.
	var net2: NullsecNetSession = GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession
	if net2:
		net2.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

## Single view switch for both spectate (§4.4) and scout (§4.2.1) — no second camera path.
func _switch_watch_seat(seat_id: int, notice: String = "") -> void:
	_nullsec_watch_seat = seat_id
	var region: String = _seat_region(seat_id)
	if region != "":
		apply_region_skybox(region)
	_refresh_region_label()
	show_notice(notice if notice != "" else "视角 → 席位 %d" % (seat_id + 1))
	_refresh_spectate_watch_panels()

func _seat_region(seat_id: int) -> String:
	var asg: Dictionary = GameSession.pending_nullsec.get("assignments", {})
	return str(asg.get(str(seat_id), asg.get(seat_id, "")))

## 顶栏星域 = 当前主场主人（开局一人一名；谁主场显示谁的）。
func _active_home_field_seat() -> int:
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	if _nullsec_spectating:
		return _nullsec_watch_seat if _nullsec_watch_seat >= 0 else local_seat
	var net: NullsecNetSession = _nullsec_net_session()
	var mode: String = net.security_mode if net != null else str(GameSession.pending_nullsec.get("security_mode", "nullsec"))
	if NullsecNetSession.is_lowsec(mode):
		return TypedVariant.as_int(GameSession.pending_nullsec.get("host_seat", 0), 0)
	if _nullsec_watch_seat >= 0:
		return _nullsec_watch_seat
	return local_seat

## Title bar carries the home-field owner's region (MULTIPLAYER_PVP §4.1 / NEW_EDEN_REGIONS).
func _refresh_region_label() -> void:
	var root: Control = hud.get_node_or_null("Root")
	if root == null:
		return
	@warning_ignore("unsafe_cast")
	var lbl: Label = root.get_node_or_null("%s/Region" % _ROUND) as Label
	if lbl == null:
		return
	if GameSession.pending_mode != "nullsec":
		lbl.visible = false
		return
	lbl.visible = true
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	var seat: int = _active_home_field_seat()
	var region: String = _seat_region(seat)
	if region == "":
		lbl.text = "星域 —"
		return
	var region_name: String = SkyboxCatalog.display_name(region)
	if seat == local_seat and not _nullsec_spectating:
		lbl.text = region_name
	else:
		lbl.text = "%s · 席位 %d" % [region_name, seat + 1]

func _wire_nullsec_scout() -> void:
	var btn: ScoutIntelButton = hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if btn == null:
		_ensure_scout_intel_btn()
		btn = hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if btn == null:
		return
	btn.visible = GameSession.pending_mode == "nullsec"
	if _nullsec_spectating:
		btn.text = "切换视角"
	else:
		btn.text = "刺探情报"
	if not btn.observe_requested.is_connected(_on_scout_observe):
		btn.observe_requested.connect(_on_scout_observe)
	if not btn.menu_opening.is_connected(_refresh_scout_menu):
		btn.menu_opening.connect(_refresh_scout_menu)
	var net: NullsecNetSession = _nullsec_net_session()
	if net:
		if not net.scout_intel_asked.is_connected(_on_scout_intel_asked):
			net.scout_intel_asked.connect(_on_scout_intel_asked)
		if not net.scout_intel_received.is_connected(_on_scout_intel_received):
			net.scout_intel_received.connect(_on_scout_intel_received)
	_refresh_scout_menu()


func _wire_nullsec_prepare_sync() -> void:
	## Prepare fleet mirror + R1 spend-gate + §3.0a stage barriers.
	_wire_prepare_fleet_sync()
	if match_ctrl != null and not match_ctrl.prepare_spend_occurred.is_connected(_on_prepare_spend_occurred):
		match_ctrl.prepare_spend_occurred.connect(_on_prepare_spend_occurred)
	if match_ctrl != null:
		match_ctrl.prepare_hold_callback = Callable(self, "_on_prepare_awaiting_peers")
		if not match_ctrl.prepare_awaiting_peers.is_connected(_on_prepare_awaiting_peers):
			match_ctrl.prepare_awaiting_peers.connect(_on_prepare_awaiting_peers)
	var net: NullsecNetSession = _nullsec_net_session()
	var armed_s: String = "?"
	if match_ctrl != null:
		armed_s = "1" if match_ctrl.prepare_clock_armed else "0"
	var barrier_s: String = "0"
	if net != null and net.needs_stage_barrier():
		barrier_s = "1"
	print("[mp.diag] wire_prep_sync net=%s ctrl_armed=%s barrier=%s" % [
		"1" if net != null else "0", armed_s, barrier_s
	])
	SessionDiagnostics.log(
		"mp.wire_prep_sync",
		"net=%s armed=%s" % ["1" if net != null else "0", armed_s]
	)
	if net != null:
		if not net.prepare_clock_armed_changed.is_connected(_on_prepare_clock_armed_changed):
			net.prepare_clock_armed_changed.connect(_on_prepare_clock_armed_changed)
		if not net.urge_prepare_received.is_connected(_on_urge_prepare_received):
			net.urge_prepare_received.connect(_on_urge_prepare_received)
	if not net.enter_battle_released.is_connected(_on_enter_battle_released):
		net.enter_battle_released.connect(_on_enter_battle_released)
	if not net.seat_battle_finished.is_connected(_on_seat_battle_finished_speed):
		net.seat_battle_finished.connect(_on_seat_battle_finished_speed)
	_apply_nullsec_prepare_stage_gates()


func _apply_nullsec_prepare_stage_gates() -> void:
	## SEMI_ASYNC §3.0 / §3.0a — freeze + spend (R1) or battle-done (R2+) clock gates.
	if GameSession.pending_mode != "nullsec" or match_ctrl == null:
		return
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null or not net.needs_stage_barrier():
		match_ctrl.hold_prepare_to_battle = false
		## Solo / no peer: R2+ already armed in _enter_prepare; R1 spend only if frozen.
		if match_ctrl.battle_game_stage_count == 0 and not match_ctrl.prepare_clock_armed and net != null:
			net.begin_prepare_spend_gate()
			if net.prepare_clock_armed:
				match_ctrl.arm_prepare_clock()
		return
	match_ctrl.hold_prepare_to_battle = true
	match_ctrl.disarm_prepare_clock()
	_fleet_push_sig = ""
	_fleet_apply_sig = ""
	_fleet_push_pending = []
	_pending_enter_battle = false
	## Empty-open fake wipe must NOT join battle_done / 开钟 — peer may still be fighting.
	if TypedVariant.as_bool(match_ctrl.last_round_empty_open, false):
		print("[mp.diag] prepare_gates SKIP battle_done (empty_open)")
		SessionDiagnostics.log("mp.prep_gate_skip", "empty_open")
		## Stay frozen until we can re-sync fleet and re-enter; arm locally only if solo.
		if not net.needs_stage_barrier():
			match_ctrl.arm_prepare_clock()
		else:
			## Re-open prepare sync: request fleet and wait for next enter_battle from host barrier.
			_push_local_prepare_fleet()
			var rival_skip: int = _nullsec_rival_seat(TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0))
			if rival_skip >= 0 and not _seat_is_ai(rival_skip):
				net.request_prepare_fleet_snapshot(rival_skip)
			## Do not report battle_done — avoid pulling cohort into 开钟 on a phantom round.
			if match_ctrl.battle_game_stage_count == 0:
				net.begin_prepare_spend_gate()
			## R2+: leave clock frozen; host will re-arm when real battles complete.
			## If we were the only one who empty-wiped, urge a fresh prepare barrier via fleet.
		return
	if match_ctrl.battle_game_stage_count == 0:
		net.begin_prepare_spend_gate()
		## Only arm if host already satisfied the gate (e.g. AI-only contestants).
		## Guests must wait for rpc_prepare_clock_armed — never arm from stale net=true.
		if net.is_host and net.prepare_clock_armed:
			match_ctrl.arm_prepare_clock()
	else:
		net.begin_battle_done_clock_gate()
		net.report_local_battle_done()


func _on_prepare_awaiting_peers() -> void:
	if GameSession.pending_mode != "nullsec":
		return
	var net: NullsecNetSession = _nullsec_net_session()
	print("[mp.diag] prepare_awaiting_peers handler net=%s" % (net != null))
	if net == null:
		if match_ctrl:
			match_ctrl.commit_prepare_complete()
		return
	net.report_local_prepare_done()


func _on_enter_battle_released() -> void:
	if match_ctrl == null:
		return
	if match_ctrl.stage != MatchController.Stage.PREPARE:
		print("[mp.diag] enter_battle_released IGNORE stage=%s" % match_ctrl.stage)
		return
	## Doomsday / kill presentation must finish before flipping into the next Battle.
	if _doomsday_busy or _presentation_hold or _titan_kill_busy or _titan_kill_active > 0:
		_pending_enter_battle = true
		print("[mp.diag] enter_battle HOLD presentation")
		SessionDiagnostics.log("mp.enter_hold", "presentation")
		return
	## Human PVP: never open Battle with an empty rival half — that instant-wipes into
	## battle_done 开钟 freeze while the peer is still fighting.
	if not _nullsec_human_rival_fleet_ready():
		_pending_enter_battle = true
		_push_local_prepare_fleet()
		var rival: int = _nullsec_rival_seat(TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0))
		var net: NullsecNetSession = _nullsec_net_session()
		if net != null and rival >= 0:
			net.request_prepare_fleet_snapshot(rival)
		show_notice("等待对手舰队同步…")
		print("[mp.diag] enter_battle HOLD waiting rival fleet")
		SessionDiagnostics.log("mp.enter_hold", "waiting_rival_fleet")
		return
	_pending_enter_battle = false
	match_ctrl.commit_prepare_complete()


## True when we may open Battle vs a human rival (AI seat / PVE / solo always ready).
func _nullsec_human_rival_fleet_ready() -> bool:
	if GameSession.pending_mode != "nullsec" or board == null or match_ctrl == null:
		return true
	if _nullsec_pve != null and _nullsec_pve.is_pve_task():
		return true
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	if rival < 0 or _seat_is_ai(rival):
		return true
	## Need at least one manned rival ship on field or hangar after sync.
	var n: int = 0
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_unmanned or s.is_protect_target:
			continue
		if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_AI:
			continue
		n += 1
	return n > 0


func _try_flush_pending_enter_battle() -> void:
	if not _pending_enter_battle or match_ctrl == null:
		return
	if match_ctrl.stage != MatchController.Stage.PREPARE:
		_pending_enter_battle = false
		return
	if not _nullsec_human_rival_fleet_ready():
		return
	_pending_enter_battle = false
	print("[mp.diag] enter_battle FLUSH after fleet ready")
	SessionDiagnostics.log("mp.enter_flush", "fleet_ready")
	match_ctrl.commit_prepare_complete()


func _on_prepare_spend_occurred() -> void:
	if GameSession.pending_mode != "nullsec":
		return
	if match_ctrl == null or match_ctrl.prepare_clock_armed:
		return
	## MATCH_FLOW: spend-gate is R1 only (`battle_game_stage_count==0`).
	if match_ctrl.battle_game_stage_count != 0:
		return
	var net: NullsecNetSession = _nullsec_net_session()
	if net:
		net.report_local_prepare_spend()
	else:
		match_ctrl.arm_prepare_clock()


func _on_prepare_clock_armed_changed(armed: bool) -> void:
	if match_ctrl == null:
		return
	if not armed:
		_defer_prepare_clock_arm = false
		match_ctrl.disarm_prepare_clock()
		_refresh_hud()
		return
	## MULTIPLAYER_PVP §6 — do not start Prepare timer under doomsday / kill FX.
	if _doomsday_busy or _presentation_hold or _titan_kill_busy or _titan_kill_active > 0:
		_defer_prepare_clock_arm = true
		match_ctrl.disarm_prepare_clock()
		print("[mp.diag] prepare_clock DEFER (presentation)")
		SessionDiagnostics.log("mp.clock_defer", "presentation")
		return
	_defer_prepare_clock_arm = false
	match_ctrl.arm_prepare_clock()
	_refresh_hud()


func _on_urge_prepare_received() -> void:
	show_notice("房主催促准备")


func _refresh_scout_menu() -> void:
	var btn: ScoutIntelButton = hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if btn == null:
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	var seats: Array = []
	var net: NullsecNetSession = _nullsec_net_session()
	if net and not net.seats.is_empty():
		seats = net.seats
	else:
		@warning_ignore("unsafe_cast")
		seats = GameSession.pending_nullsec.get("seats", []) as Array
	var targets: Array = []
	for s_v: Variant in seats:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if not NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			continue
		var sid: int = TypedVariant.as_int(s.get("seat_id", 0), 0)
		## Spectate: include self as return; scout: other seats only.
		if not _nullsec_spectating and sid == local_seat:
			continue
		targets.append({
			"seat_id": sid,
			"nick": str(s.get("nick", "?")),
			"finished": false,
			"self": _nullsec_spectating and sid == local_seat,
		})
	btn.set_targets(targets)
	if _nullsec_spectating:
		btn.set_hint("")
	else:
		btn.set_hint("" if _scout_gate_reason() == "" else _scout_gate_reason())


func _on_scout_observe(seat_id: int) -> void:
	if _nullsec_spectating:
		_switch_watch_seat(seat_id)
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	if seat_id == local_seat:
		show_notice("不能刺探本席")
		return
	var reason: String = _scout_gate_reason()
	if reason != "":
		show_notice(reason)
		return
	var now: int = Time.get_ticks_msec()
	var cd_until: int = TypedVariant.as_int(_scout_cd_until_ms.get(seat_id, 0), 0)
	if now < cd_until:
		var left: float = float(cd_until - now) / 1000.0
		show_notice("对该玩家刺探冷却中（%.1fs）" % left)
		return
	var ship: ShipUnit = _pick_random_explore_ship()
	if ship == null:
		show_notice(SCOUT_GATE_HINT)
		return
	var ship_name: String = str(DataStore.get_ship(ship.ship_id).get("name", "探索护卫"))
	_strip_ship_equipment_to_bag_or_sell(ship)
	_begin_scout_depart(ship)
	_scout_cd_until_ms[seat_id] = now + SCOUT_TARGET_CD_MS
	var nick: String = _seat_nick(seat_id)
	var from_nick: String = _local_nick()
	## 有备而来：本 Prepare 对本桌对手刺探计数。
	if seat_id == _nullsec_rival_seat(local_seat) or seat_id == _eval_prepare_rival_seat:
		_eval_scout_vs_rival += 1
	show_notice("刺探 %s · %s 离场" % [nick, ship_name])
	_request_scout_intel(seat_id, local_seat, from_nick, ship_name)
	_refresh_scout_menu()
	_refresh_hud()


## "" = scouting allowed.
func _scout_gate_reason() -> String:
	if board == null:
		return SCOUT_GATE_HINT
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if s.slot_type != "hangar" and s.slot_type != "field":
			continue
		if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_PLAYER:
			continue
		if s.is_destroyed:
			continue
		if _is_explore_ship(s.ship_id):
			return ""
	return SCOUT_GATE_HINT


func _is_explore_ship(ship_id: int) -> bool:
	var data: Dictionary = DataStore.get_ship(ship_id)
	if data.is_empty():
		return false
	for f: Variant in TypedVariant.as_array(data.get("fetter_ids", [])):
		if str(f).to_lower() == EXPLORE_FETTER_ID:
			return true
	for tag: Variant in TypedVariant.as_array(data.get("tags", [])):
		if str(tag).to_lower() == EXPLORE_FETTER_ID:
			return true
	return false


func _pick_random_explore_ship() -> ShipUnit:
	var cand: Array = []
	if board == null:
		return null
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_unmanned or s.is_destroyed:
			continue
		if s.slot_type != "hangar" and s.slot_type != "field":
			continue
		if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_PLAYER:
			continue
		if _is_explore_ship(s.ship_id):
			cand.append(s)
	if cand.is_empty():
		return null
	@warning_ignore("unsafe_cast")
	return cand[randi() % cand.size()] as ShipUnit


func _strip_ship_equipment_to_bag_or_sell(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var fit: Array = ship.get_function_fit()
	for i: int in range(fit.size() - 1, -1, -1):
		var mid: String = ship.unequip_function_at(i)
		if mid.strip_edges() == "":
			continue
		_stash_or_auto_sell_star_merge_equipment(mid, ShipUnit.TEAM_PLAYER)
	_refresh_equipment_inventory_ui()


func _begin_scout_depart(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	## Free the grid cell first while slot_type is still hangar/field.
	if board and board.has_method("release_ship_occupancy"):
		board.release_ship_occupancy(ship)
	ship.slot_type = "departing"
	## Keep mesh visible while flying; combat already ignores non-field / destroyed.
	ship.set_meta("scout_departing", true)
	var dir: Vector3 = Vector3(randf() * 2.0 - 1.0, randf() * 0.85 + 0.15, randf() * 2.0 - 1.0)
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	dir = dir.normalized()
	_scout_departs.append({"ship": ship, "vel": dir * SCOUT_DEPART_SPEED, "age": 0.0})


func _tick_scout_departs(delta: float) -> void:
	if _scout_departs.is_empty():
		return
	var kept: Array = []
	for entry_v: Variant in _scout_departs:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = TypedVariant.as_dict(entry_v)
		@warning_ignore("unsafe_cast")
		var ship: ShipUnit = e.get("ship") as ShipUnit
		if ship == null or not is_instance_valid(ship):
			continue
		var vel: Vector3 = Vector3.FORWARD * SCOUT_DEPART_SPEED
		var vel_v: Variant = e.get("vel")
		if typeof(vel_v) == TYPE_VECTOR3:
			@warning_ignore("unsafe_cast")
			vel = vel_v as Vector3
		var age: float = TypedVariant.as_float(e.get("age", 0.0), 0.0) + delta
		ship.global_position = ship.global_position + vel * delta
		var off: bool = _is_world_off_camera(ship.global_position) or age >= SCOUT_DEPART_MAX_S
		if off:
			if board:
				board.remove_ship_node(ship)
			elif is_instance_valid(ship):
				ship.queue_free()
			continue
		e["age"] = age
		e["vel"] = vel
		e["ship"] = ship
		kept.append(e)
	_scout_departs = kept


func _is_world_off_camera(world_pos: Vector3) -> bool:
	if camera == null:
		return true
	if camera.is_position_behind(world_pos):
		return true
	var sp: Vector2 = camera.unproject_position(world_pos)
	var vr: Rect2 = get_viewport().get_visible_rect()
	var margin: float = 48.0
	return sp.x < -margin or sp.y < -margin or sp.x > vr.size.x + margin or sp.y > vr.size.y + margin


func _local_nick() -> String:
	var net: NullsecNetSession = _nullsec_net_session()
	if net and str(net.local_nick).strip_edges() != "":
		return str(net.local_nick)
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	return _seat_nick(local_seat)


func _seat_nick(seat_id: int) -> String:
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) == seat_id:
			return str(s.get("nick", "?"))
	return "?"


func _request_scout_intel(target_seat: int, from_seat: int, from_nick: String, scout_ship_name: String) -> void:
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null:
		## Offline / no session: answer from local AI economy when possible.
		var summary: Dictionary = _build_ai_scout_summary() if _seat_is_ai(target_seat) else {}
		_on_scout_intel_received(target_seat, _seat_nick(target_seat), summary)
		return
	net.request_scout_intel(target_seat, from_seat, from_nick, scout_ship_name)


func _seat_is_ai(seat_id: int) -> bool:
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) == seat_id:
			return TypedVariant.as_bool(s.get("is_ai", false), false)
	return false


func _on_scout_intel_asked(_from_seat: int, from_nick: String, scout_ship_name: String, reply_peer: int, target_seat: int) -> void:
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	var for_ai: bool = _seat_is_ai(target_seat)
	if not for_ai and target_seat != local_seat:
		return
	## Peek notice on the victim (humans only).
	if not for_ai:
		var peek: String = "%s派了%s偷看了你一眼" % [from_nick if from_nick != "" else "?", scout_ship_name if scout_ship_name != "" else "探索护卫"]
		_append_battle_log(peek)
	var summary: Dictionary = _build_ai_scout_summary() if for_ai else _build_local_scout_summary()
	var target_nick: String = _seat_nick(target_seat)
	var net: NullsecNetSession = _nullsec_net_session()
	if net:
		net.reply_scout_intel(reply_peer, target_seat, target_nick, summary)
	else:
		_on_scout_intel_received(target_seat, target_nick, summary)


func _on_scout_intel_received(target_seat: int, target_nick: String, summary: Dictionary) -> void:
	var nick: String = target_nick if target_nick != "" else _seat_nick(target_seat)
	if summary.is_empty():
		_append_battle_log("刺探 %s：情报未回传" % nick)
		return
	_append_battle_log(_format_scout_intel_line(nick, summary))


func _build_local_scout_summary() -> Dictionary:
	var gold: int = TypedVariant.as_int(match_ctrl.player_gold, 0) if match_ctrl else 0
	var sizes: Array = []
	var groups: Array = []
	if match_ctrl:
		match_ctrl.ensure_equipment_inventory_size()
		for mid_v: Variant in match_ctrl.equipment_inventory:
			var mid: String = str(mid_v).strip_edges()
			if mid == "":
				continue
			var mod: Dictionary = DataStore.get_function_module(mid)
			sizes.append(str(mod.get("size", "?")).to_upper())
	if board:
		for s: ShipUnit in board.all_ships():
			if s == null or not is_instance_valid(s) or s.is_unmanned:
				continue
			if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_PLAYER:
				continue
			if s.slot_type != "hangar" and s.slot_type != "field":
				continue
			if str(s.slot_type) == "departing":
				continue
			var sd: Dictionary = DataStore.get_ship(s.ship_id)
			groups.append(str(sd.get("ship_group", "frigate")))
			for entry_v: Variant in s.get_function_fit():
				var entry: Dictionary = TypedVariant.as_dict(entry_v)
				var def: Dictionary = TypedVariant.as_dict(entry.get("def", {}))
				if def.is_empty():
					def = DataStore.get_function_module(str(entry.get("id", "")))
				var sz: String = str(def.get("size", "?")).to_upper()
				if sz != "":
					sizes.append(sz)
	return {"gold": gold, "equipment_sizes": sizes, "ship_groups": groups}


func _build_ai_scout_summary() -> Dictionary:
	var gold: int = TypedVariant.as_int(ai.ai_gold, 0) if ai else 0
	var sizes: Array = []
	var groups: Array = []
	if ai:
		for mid_v: Variant in TypedVariant.as_array(ai.equipment_inventory):
			var mid: String = str(mid_v).strip_edges()
			if mid == "":
				continue
			var mod: Dictionary = DataStore.get_function_module(mid)
			sizes.append(str(mod.get("size", "?")).to_upper())
	if board:
		for s: ShipUnit in board.all_ships():
			if s == null or not is_instance_valid(s) or s.is_unmanned:
				continue
			if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_AI:
				continue
			if s.slot_type != "hangar" and s.slot_type != "field":
				continue
			var sd: Dictionary = DataStore.get_ship(s.ship_id)
			groups.append(str(sd.get("ship_group", "frigate")))
			for entry_v: Variant in s.get_function_fit():
				var entry: Dictionary = TypedVariant.as_dict(entry_v)
				var def: Dictionary = TypedVariant.as_dict(entry.get("def", {}))
				if def.is_empty():
					def = DataStore.get_function_module(str(entry.get("id", "")))
				var sz: String = str(def.get("size", "?")).to_upper()
				if sz != "":
					sizes.append(sz)
	return {"gold": gold, "equipment_sizes": sizes, "ship_groups": groups}


func _format_scout_intel_line(nick: String, summary: Dictionary) -> String:
	var gold: int = TypedVariant.as_int(summary.get("gold", 0), 0)
	var sizes: Array = TypedVariant.as_array(summary.get("equipment_sizes", []))
	var groups: Array = TypedVariant.as_array(summary.get("ship_groups", []))
	var size_txt: String = "无"
	if not sizes.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for s_v: Variant in sizes:
			parts.append(str(s_v))
		size_txt = ",".join(parts)
	var ton_txt: String = "无"
	if not groups.is_empty():
		var tparts: PackedStringArray = PackedStringArray()
		for g_v: Variant in groups:
			tparts.append(_ship_group_zh(str(g_v)))
		ton_txt = ",".join(tparts)
	return "刺探 %s：持有 %d 黄；装备 %d 件（%s）；舰船 %d 艘（%s）" % [
		nick, gold, sizes.size(), size_txt, groups.size(), ton_txt
	]


static func _ship_group_zh(group: String) -> String:
	match group:
		"frigate":
			return "护"
		"destroyer":
			return "驱"
		"cruiser":
			return "巡"
		"battlecruiser":
			return "战巡"
		"battleship":
			return "战"
		"carrier":
			return "航"
		"dreadnought":
			return "无畏"
		"force_auxiliary":
			return "后勤"
		"fighter":
			return "舰载"
		"freighter":
			return "货"
		"titan":
			return "泰坦"
		_:
			return group if group != "" else "?"


func _nullsec_on_prepare_begin() -> void:
	if GameSession.pending_mode != "nullsec" or _nullsec_pve == null or board == null:
		return
	if _nullsec_spectating:
		return
	## Lowsec: never creep slide — PVP prepare path only.
	if _nullsec_pve.always_pvp:
		_nullsec_prepare_pvp_round()
		return
	_spawn_nullsec_creeps_with_slide()


func _setup_net_battle_session() -> void:
	if combat and _nullsec_rng:
		combat.bind_match_rng(_nullsec_rng, 1)
	if match_ctrl and _nullsec_rng and match_ctrl.has_method("bind_cyno_rng"):
		match_ctrl.bind_cyno_rng(_nullsec_rng, 1)
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null:
		return
	if _net_battle and is_instance_valid(_net_battle):
		_net_battle.queue_free()
	_net_battle = NetBattleSession.new()
	_net_battle.name = "NetBattleSession"
	add_child(_net_battle)
	var payload: Dictionary = GameSession.pending_nullsec.duplicate(true)
	if not payload.has("host_seat"):
		payload["host_seat"] = TypedVariant.as_int(payload.get("host_seat", 0), 0)
	_net_battle.setup(_nullsec_rng, net, payload)
	## SEMI_ASYNC §3.1a — watch peers skip CombatResolver; keep normal sync cadence.
	## Do NOT densify snaps (≤5): full apply_authority each snap stutters guests.
	if not net.authority_snapshot_received.is_connected(_on_net_authority_snapshot):
		net.authority_snapshot_received.connect(_on_net_authority_snapshot)
	if not net.authority_light_received.is_connected(_on_net_authority_light):
		net.authority_light_received.connect(_on_net_authority_light)
	if not net.battle_report_received.is_connected(_on_net_battle_report):
		net.battle_report_received.connect(_on_net_battle_report)
	if not net.battle_ended_received.is_connected(_on_net_battle_ended):
		net.battle_ended_received.connect(_on_net_battle_ended)
	if not net.anticheat_notice_received.is_connected(_on_net_anticheat_notice):
		net.anticheat_notice_received.connect(_on_net_anticheat_notice)
	if not _net_battle.round_jobs_complete.is_connected(_on_net_round_jobs_complete):
		_net_battle.round_jobs_complete.connect(_on_net_round_jobs_complete)
	if not _net_battle.anticheat_notify.is_connected(_on_net_anticheat_notice):
		_net_battle.anticheat_notify.connect(_on_net_anticheat_notice)
	if not _net_battle.spectate_stream.is_connected(_on_net_spectate_stream):
		_net_battle.spectate_stream.connect(_on_net_spectate_stream)
	_net_jobs_ready_for_titan = true


func _on_net_authority_snapshot(snap: Dictionary) -> void:
	if _net_battle:
		_net_battle.apply_authority(snap, board, firing_fx, _net_float_text())


func _on_net_authority_light(pkt: Dictionary) -> void:
	if _net_battle:
		_net_battle.apply_light(pkt, board, firing_fx, _net_float_text())


func _net_float_text() -> Object:
	if combat == null:
		return null
	return combat.get_node_or_null("FloatTextPool")


func _on_net_battle_report(report: Dictionary) -> void:
	var line: String = "权威战报 · #%d %s → %s" % [
		TypedVariant.as_int(report.get("serial", 0), 0),
		str(report.get("kind", "")),
		str(report.get("result", "")),
	]
	_append_battle_log(line)


## SEMI_ASYNC §3.1a — map host-seat W/L into local seat, then force Prepare.
func _on_net_battle_ended(host_result: String, host_seat: int, reason: String) -> void:
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var mapped: String = _map_host_result_to_local(str(host_result), host_seat, local_seat)
	print("[mp.diag] battle_ended_rpc host=%s seat=%d -> local=%s reason=%s" % [
		host_result, host_seat, mapped, reason
	])
	SessionDiagnostics.log("mp.battle_ended_rpc", "host=%s→%s" % [host_result, mapped])
	match_ctrl.force_authority_combat_complete(mapped, str(reason))


func _map_host_result_to_local(host_result: String, host_seat: int, local_seat: int) -> String:
	if host_result == "draw" or host_result == "":
		return "draw"
	if local_seat == host_seat:
		return host_result
	## Opposite seat: flip win/lose.
	if host_result == "win":
		return "lose"
	if host_result == "lose":
		return "win"
	return "draw"


func _on_net_anticheat_notice(message: String) -> void:
	show_notice(str(message))
	_append_battle_log(str(message))


func _on_net_spectate_stream(snap: Dictionary) -> void:
	if _nullsec_spectating and _net_battle:
		_net_battle.apply_authority(snap, board, firing_fx, _net_float_text())


func _on_net_round_jobs_complete(_reports: Array) -> void:
	_net_jobs_ready_for_titan = true


func _tick_net_battle_enrich() -> void:
	if _net_battle == null or board == null:
		return
	if not _net_battle.is_host:
		return
	if _net_battle.should_enrich_this_tick():
		var gold: int = TypedVariant.as_int(match_ctrl.player_gold_earned, 0) if match_ctrl else 0
		_net_battle.enrich_and_broadcast(board, gold)
		return
	if _net_battle.should_light_this_tick():
		_net_battle.enrich_and_broadcast_light(board)

func _spawn_nullsec_creeps_with_slide() -> void:
	## Clear AI field ships from prior versus AI army when first entering nullsec PVE.
	## Last round's salvage freighter goes with them: it is player-owned but creep-spawned.
	for s: ShipUnit in board.all_ships().duplicate():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if TypedVariant.as_int(s.team_id, 0) == ShipUnit.TEAM_AI or s.is_protect_target:
			board.remove_ship_node(s)
	## Sleepers hold no titan: the creep side never carries a titan fetter (MATCH_FLOW §5.1).
	board.set_titan_fetter_race(ShipUnit.TEAM_AI, "")
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())
	var roster: Array = _nullsec_pve.creep_ai.locked_roster
	var fh: int = TypedVariant.as_int(DataStore.board.get("field_height", 6), 0)
	var sliding: Array = []
	for entry_v: Variant in roster:
		var entry: Dictionary = TypedVariant.as_dict(entry_v)
		var sid: int = TypedVariant.as_int(entry.get("ship_id", 0), 0)
		var cell: int = TypedVariant.as_int(entry.get("cell", 0), 0)
		var z: float = clampi(int(cell / 8.0), 0, fh - 1)
		var cols: int = BoardController.field_cols_at(z)
		var x: int = clampi(cell % 8, 0, maxi(0, cols - 1))
		if not board.is_field_cell_free_for(ShipUnit.TEAM_AI, x, z):
			var found: bool = false
			for zz: int in range(fh):
				var cc: int = BoardController.field_cols_at(zz)
				for xx: int in range(cc):
					if board.is_field_cell_free_for(ShipUnit.TEAM_AI, xx, zz):
						x = xx
						z = zz
						found = true
						break
				if found:
					break
			if not found:
				continue
		var ship: ShipUnit = board.spawn_ship(sid, 1, ShipUnit.TEAM_AI, "field", x, z)
		if ship == null:
			continue
		var dest: Vector3 = ship.global_position
		var start: Vector3 = dest + _nullsec_pve.slide_start_offset()
		ship.global_position = start
		sliding.append({"ship": ship, "from": start, "to": dest})
	if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
		var center: Vector2i = _nullsec_pve.salvage_center_cell(
			BoardController.field_cols_at(0),
			TypedVariant.as_int(DataStore.board.get("field_height", 6), 0)
		)
		var cx: int = clampi(center.x, 0, BoardController.field_cols_at(center.y) - 1)
		var cz: int = clampi(center.y, 0, fh - 1)
		if not board.is_field_cell_free_for(ShipUnit.TEAM_AI, cx, cz):
			for zz: int in range(fh):
				var cc2: int = BoardController.field_cols_at(zz)
				for xx: int in range(cc2):
					if board.is_field_cell_free_for(ShipUnit.TEAM_AI, xx, zz):
						cx = xx
						cz = zz
						break
		var fid: int = _nullsec_pve.freighter_ship_id
		if fid <= 0:
			fid = _nullsec_pve.pick_freighter_id(_local_titan_race_for_ui())
		## Spawned on the AI half (occupancy + world pose) but owned by the player: normal
		## targeting then has creeps shoot it and player logistics repair it, no special case.
		var fr: ShipUnit = board.spawn_ship(fid, 1, ShipUnit.TEAM_AI, "field", cx, cz)
		if fr:
			fr.team_id = ShipUnit.TEAM_PLAYER
			fr.field_side_team = ShipUnit.TEAM_AI
			var dest2: Vector3 = fr.global_position
			var start2: Vector3 = dest2 + _nullsec_pve.slide_start_offset()
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
	var duration: float = 1.2
	var t: float = 0.0
	while t < duration:
		t += get_process_delta_time()
		var a: float = clampf(t / duration, 0.0, 1.0)
		for e_v: Variant in sliding:
			var e: Dictionary = TypedVariant.as_dict(e_v)
			@warning_ignore("unsafe_cast")
			var ship: ShipUnit = e.get("ship") as ShipUnit
			if ship == null or not is_instance_valid(ship):
				continue
			@warning_ignore("unsafe_cast")
			var from_p: Vector3 = e.get("from") as Vector3
			@warning_ignore("unsafe_cast")
			var to_p: Vector3 = e.get("to") as Vector3
			ship.global_position = from_p.lerp(to_p, a)
		await get_tree().process_frame
	for e_v: Variant in sliding:
		var e: Dictionary = TypedVariant.as_dict(e_v)
		var ship2: ShipUnit = e.get("ship")
		if ship2 and is_instance_valid(ship2):
			@warning_ignore("unsafe_cast")
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
	var round_r: int = maxi(1, match_ctrl.battle_game_stage_count + 1)
	_nullsec_pve.setup(_nullsec_rng, round_r)
	_nullsec_pve.pick_task(round_r)
	if _nullsec_pve.always_pvp or not _nullsec_pve.is_pve_task():
		## Lowsec / PVP: opponent is a seat army, never a creep roster.
		_nullsec_pve.creep_ai.locked_roster.clear()
		return
	var pop: int = match_ctrl.population_limit()
	_nullsec_pve.lock_creeps(match_ctrl.player_gold, match_ctrl.player_level, pop)
	if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
		_nullsec_pve.pick_freighter_id(_local_titan_race_for_ui())

## PVP round-after titan fire (MULTIPLAYER_PVP §6): winner fires, draw = both fire.
## Every shot uses the doomsday presentation; losers take the fixed 20 pipe hit.
func _nullsec_resolve_pvp_doomsday(result: String) -> void:
	if _doomsday_resolver == null:
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival_seat: int = _nullsec_rival_seat(local_seat)
	if rival_seat < 0 or rival_seat == local_seat:
		## No contender this round — nobody's titan fires, least of all at itself.
		show_notice("本回合无对手席位 · 泰坦不开火")
		return
	## Guests follow host rpc_doomsday_play for the beam; hold prepare until then.
	var net_dd: NullsecNetSession = _nullsec_net_session()
	var guest_follow: bool = net_dd != null and net_dd.needs_stage_barrier() and not net_dd.is_host
	if guest_follow:
		_doomsday_busy = true
		_presentation_hold = true
		_nullsec_prepare_pending = true
		## Hold until host rpc arrives (then _hold_for_doomsday_presentation resets the clock).
		_doomsday_hold_until_ms = Time.get_ticks_msec() + 60000
		_doomsday_fx_left = 1 ## sentinel so gate doesn't release before RPC
		_wl_pred_local = str(result)
		_wl_auth_shots.clear()
		_wl_gap_notified = false
		if match_ctrl:
			match_ctrl.disarm_prepare_clock()
		return
	_doomsday_resolver.begin_resolve_burst()
	var local_pos: Vector3 = _titan_fire_point(true)
	var rival_pos: Vector3 = _titan_fire_point(false)
	var belt: Node3D = _nullsec_belt_root()
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
	_doomsday_resolver.end_resolve_burst()
	_hold_for_doomsday_presentation()
	_doomsday_resolver.schedule_return_home(get_tree(), local_seat, DoomsdayFx.FIRE_S)
	_refresh_titan_hp_bar()
	_refresh_hud()
	## Speed mark is via net.seat_battle_finished (battle_done); keep local fallback for solo.
	if _nullsec_speed and (_nullsec_net_session() == null or not _nullsec_net_session().needs_stage_barrier()):
		var cur: float = TypedVariant.as_float(match_ctrl.speed_multiplier, 1.0) if match_ctrl else 1.0
		_nullsec_speed.mark_seat_finished(cur)
		_apply_resolved_speed()
	var scout: ScoutIntelButton = hud.get_node_or_null("Root/TopRight/ScoutIntelBtn") as ScoutIntelButton
	if scout:
		scout.set_local_finished(true)
	for home_side: int in kill_seats:
		_begin_titan_kill(bool(home_side))

## Doomsday beam must finish before the round flips (MULTIPLAYER_PVP §6).
## Wall-clock gate — never couple to 倍速 / SceneTreeTimer.
func _hold_for_doomsday_presentation() -> void:
	var hold: float = TypedVariant.as_float(DataStore.visual.get("titan_doomsday_hold_s", 0.8), 0.0)
	_doomsday_busy = true
	_presentation_hold = true
	_doomsday_hold_until_ms = Time.get_ticks_msec() + int((DoomsdayFx.FIRE_S + maxf(hold, 0.0)) * 1000.0)
	## Prepare already re-armed itself on stage_changed(PREPARE) before the beam fired —
	## freeze it again so the timer does not run out under the doomsday performance.
	if match_ctrl:
		if match_ctrl.prepare_clock_armed:
			_defer_prepare_clock_arm = true
		match_ctrl.disarm_prepare_clock()
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and net.prepare_clock_armed:
		_defer_prepare_clock_arm = true

## Flip the Prepare clock back on once the doomsday beam (and any overlapping hull kill)
## has finished. Multiplayer: apply deferred battle_done arm, or re-arm if net already armed.
func _reengage_prepare_clock_after_doomsday() -> void:
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.PREPARE or match_ctrl.prepare_clock_armed:
		return
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and net.needs_stage_barrier():
		if _defer_prepare_clock_arm or net.prepare_clock_armed:
			_defer_prepare_clock_arm = false
			match_ctrl.arm_prepare_clock()
			_refresh_hud()
		return
	match_ctrl.arm_prepare_clock()
	_refresh_hud()

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
	_presentation_hold = false
	_reengage_prepare_clock_after_doomsday()
	_flush_pending_settlement_if_ready()
	if _nullsec_prepare_pending:
		_nullsec_prepare_pending = false
		_nullsec_enter_next_round()

func _seat_titan_alive(seat_id: int) -> bool:
	if _doomsday_resolver == null:
		return true
	@warning_ignore("unsafe_cast")
	var pipes: TitanHpPipes = _doomsday_resolver.pipes_by_seat.get(seat_id) as TitanHpPipes
	if pipes == null:
		return true
	return pipes.alive()

func _begin_titan_kill(home_side: bool) -> void:
	var berth: TitanBerth = _titan_berth if home_side else _rival_titan_berth
	if berth == null or not is_instance_valid(berth):
		return
	_titan_kill_busy = true
	_titan_kill_active += 1
	begin_titan_kill_shake()
	@warning_ignore("unsafe_method_access")
	_TitanKillSequence.play(berth, world, func() -> void: _on_titan_kill_done())

func _on_titan_kill_done() -> void:
	_titan_kill_active = maxi(0, _titan_kill_active - 1)
	if _titan_kill_active > 0:
		return
	_titan_kill_busy = false
	if not _seat_titan_alive(TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)):
		_nullsec_prepare_pending = false
		_presentation_hold = false
		_flush_pending_settlement_if_ready()
		## Early-out → same spectate runtime as「仅观战」.
		if not _nullsec_spectating:
			enter_nullsec_spectate("eliminated")
		return
	if _doomsday_busy:
		return
	_presentation_hold = false
	_flush_pending_settlement_if_ready()
	_reengage_prepare_clock_after_doomsday()
	## Prepare was held back while the hull was exploding — run it now.
	if _nullsec_prepare_pending:
		_nullsec_prepare_pending = false
		_nullsec_enter_next_round()

func begin_titan_kill_shake() -> void:
	## Free / observe camera: do not overlay scripted shake (UI_AND_SHELL / plan).
	if _camera_manual_pose():
		return
	var s: float = TypedVariant.as_float(DataStore.visual.get("titan_kill_shake_s", 2.6), 0.0)
	_titan_shake_until_ms = Time.get_ticks_msec() + int(s * 1000.0)

func _on_titan_return_home(seat_id: int) -> void:
	## After doomsday VFX +5s: guest returns to own home field (skybox + notice).
	## Lowsec: already host-home — no hop / return sky switch (MULTIPLAYER_PVP §1).
	if _nullsec_pve and _nullsec_pve.always_pvp:
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	if seat_id != local_seat:
		return
	var asg: Dictionary = GameSession.pending_nullsec.get("assignments", {})
	var region: String = str(asg.get(str(local_seat), asg.get(local_seat, "")))
	if region != "":
		apply_region_skybox(region)
	show_notice("投送返回主场")

func _doomsday_fx_root() -> Node3D:
	if world == null:
		return null
	var root: Node3D = world.get_node_or_null("FxRoot") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "FxRoot"
		root.process_mode = Node.PROCESS_MODE_ALWAYS
		world.add_child(root)
	return root


func _fire_doomsday(attacker_seat: int, loser_seat: int, from: Vector3, to: Vector3, belt: Node3D, from_rpc: bool = false) -> void:
	if attacker_seat == loser_seat or attacker_seat < 0 or loser_seat < 0:
		push_warning("[Nullsec] doomsday skipped: attacker=%d loser=%d" % [attacker_seat, loser_seat])
		SessionDiagnostics.log("dd.skip", "bad_seats a=%d l=%d" % [attacker_seat, loser_seat])
		return
	var race: String = _seat_titan_race(attacker_seat)
	if race == "":
		race = "caldari"
	var parent: Node3D = _doomsday_fx_root()
	if parent == null:
		parent = world
	var fx: DoomsdayFx = DoomsdayFx.play(parent, race, from, to)
	if fx != null and is_instance_valid(fx):
		_doomsday_fx_left += 1
		fx.finished.connect(_on_one_doomsday_fx_finished)
	else:
		push_warning("[Nullsec] DoomsdayFx failed to spawn")
		SessionDiagnostics.log("dd.skip", "fx_null race=%s" % race)
	if _doomsday_resolver:
		_doomsday_resolver.resolve_loss(attacker_seat, loser_seat, from, to, belt)
	if not from_rpc:
		var net: NullsecNetSession = _nullsec_net_session()
		if net and net.is_host and net.needs_stage_barrier():
			_doomsday_rpc_suppress = true
			var tick: int = _net_battle.logic_tick() if _net_battle else 0
			net.broadcast_doomsday_play(attacker_seat, loser_seat, tick)

func _nullsec_belt_root() -> Node3D:
	var env: Node = world.get_node_or_null("MapEnv")
	if env:
		@warning_ignore("unsafe_cast")
		var belt: Node3D = env.get_node_or_null("AsteroidBelt") as Node3D
		if belt:
			return belt
	@warning_ignore("unsafe_cast")
	return world.get_node_or_null("AsteroidBelt") as Node3D

## Opposing seat for this PVP round, or -1 when the room holds no other contender.
## Never falls back to `local_seat`: that made a won round fire our own doomsday at
## ourselves, so winning cost 20 pipe HP (MULTIPLAYER_PVP §6).
func _nullsec_rival_seat(local_seat: int) -> int:
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		var d: Dictionary = s
		if not TypedVariant.as_bool(d.get("occupied", false), false):
			continue
		var sid: int = TypedVariant.as_int(d.get("seat_id", -1), 0)
		if sid == local_seat or sid < 0:
			continue
		## Spectators and seats that never picked a titan are not contenders.
		if not NullsecNetSession.is_player_race(str(d.get("titan_race", ""))):
			continue
		return sid
	return -1

func _seat_titan_race(seat_id: int) -> String:
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) == seat_id:
			return str(s.get("titan_race", ""))
	return ""

func _titan_fire_point(local_side: bool) -> Vector3:
	if local_side:
		if _titan_berth and is_instance_valid(_titan_berth):
			return _titan_berth.fire_point()
		return Vector3(0, 1.5, 14.0)
	if _rival_titan_berth and is_instance_valid(_rival_titan_berth):
		return _rival_titan_berth.fire_point()
	## Fallback mirror if rival berth missing.
	var p: Vector3 = Vector3(0, 1.5, 14.0)
	if _titan_berth and is_instance_valid(_titan_berth):
		p = _titan_berth.fire_point()
	return Vector3(p.x, p.y, -p.z)

func _on_speed_vote_received(seat: int, speed: float) -> void:
	if _nullsec_speed == null:
		return
	_nullsec_speed.set_vote(seat, speed)
	if _speed_dropdown:
		@warning_ignore("unsafe_cast")
		_speed_dropdown.refresh_list(GameSession.pending_nullsec.get("seats", []) as Array)
	var wait_n: int = _nullsec_speed.waiting_count()
	if wait_n > 0:
		show_notice("等待 %d 人同档 → %s" % [wait_n, SpeedDropdownMenu._label(speed)])
	else:
		show_notice("对局倍速 %s" % SpeedDropdownMenu._label(speed))
	_apply_resolved_speed()


func _sync_required_speed_seats() -> void:
	if _nullsec_speed == null:
		return
	var req: PackedInt32Array = PackedInt32Array()
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if TypedVariant.as_bool(s.get("is_ai", false), false):
			continue
		if NullsecNetSession.is_spectate_race(str(s.get("titan_race", ""))):
			continue
		if not NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			continue
		req.append(TypedVariant.as_int(s.get("seat_id", -1), -1))
	_nullsec_speed.set_required_human_seats(req)


func _on_doomsday_play_received(attacker_seat: int, loser_seat: int, _logic_tick: int) -> void:
	if _doomsday_rpc_suppress:
		_doomsday_rpc_suppress = false
		return
	## Clear guest wait sentinel before spawning real FX.
	if _doomsday_fx_left == 1 and _doomsday_hold_until_ms > Time.get_ticks_msec() + 30000:
		_doomsday_fx_left = 0
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	_record_auth_doomsday_shot(attacker_seat, loser_seat, local_seat)
	var atk_is_local: bool = attacker_seat == local_seat
	var hit_is_local: bool = loser_seat == local_seat
	var from_pos: Vector3 = _titan_fire_point(atk_is_local)
	var to_pos: Vector3 = _titan_fire_point(hit_is_local)
	## Mirror: if neither is local, treat attacker as rival side.
	if not atk_is_local and not hit_is_local:
		from_pos = _titan_fire_point(false)
		to_pos = _titan_fire_point(true)
	if _doomsday_resolver:
		_doomsday_resolver.begin_resolve_burst()
	_fire_doomsday(attacker_seat, loser_seat, from_pos, to_pos, _nullsec_belt_root(), true)
	if _doomsday_resolver:
		_doomsday_resolver.end_resolve_burst()
	_hold_for_doomsday_presentation()
	_refresh_titan_hp_bar()
	_refresh_hud()
	if not _seat_titan_alive(loser_seat):
		_begin_titan_kill(loser_seat == local_seat)


## SEMI_ASYNC §6.2 — notify only when local W/L prediction disagrees with host shots.
func _record_auth_doomsday_shot(attacker_seat: int, loser_seat: int, local_seat: int) -> void:
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null or net.is_host or not net.needs_stage_barrier():
		return
	if _wl_pred_local == "":
		_wl_pred_local = str(match_ctrl.last_round_result) if match_ctrl else ""
	_wl_auth_shots.append({"a": attacker_seat, "l": loser_seat})
	_maybe_notify_wl_prediction_gap(local_seat)


func _auth_result_from_dd_shots(local_seat: int) -> String:
	var rival: int = _nullsec_rival_seat(local_seat)
	if rival < 0:
		return ""
	var hit_rival: bool = false
	var hit_local: bool = false
	for s_v: Variant in _wl_auth_shots:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		var a: int = TypedVariant.as_int(s.get("a", -1), -1)
		var l: int = TypedVariant.as_int(s.get("l", -1), -1)
		if a == local_seat and l == rival:
			hit_rival = true
		elif a == rival and l == local_seat:
			hit_local = true
	if hit_rival and hit_local:
		return "draw"
	if hit_rival:
		return "win"
	if hit_local:
		return "lose"
	return ""


func _maybe_notify_wl_prediction_gap(local_seat: int) -> void:
	if _wl_gap_notified or _wl_pred_local == "":
		return
	var auth: String = _auth_result_from_dd_shots(local_seat)
	var pred: String = _wl_pred_local
	if pred == "draw":
		if _wl_auth_shots.size() < 2:
			return
	elif _wl_auth_shots.size() >= 2:
		## Host fired both ways → draw; local predicted a decisive result.
		auth = "draw"
	elif auth == "":
		return
	if auth == pred:
		return
	_wl_gap_notified = true
	var msg: String = "本地预测与房主有偏差"
	show_notice(msg)
	_append_battle_log(msg)
	SessionDiagnostics.log("net.anticheat_wl", "pred=%s auth=%s" % [pred, auth])
	var net: NullsecNetSession = _nullsec_net_session()
	if net and net.multiplayer and net.multiplayer.has_multiplayer_peer():
		net.broadcast_anticheat_notice(msg)


func _on_nullsec_speed_changed(speed: float) -> void:
	_apply_resolved_speed()
	show_notice("对局倍速 %s" % SpeedDropdownMenu._label(speed))

func _apply_resolved_speed() -> void:
	if _nullsec_speed == null or match_ctrl == null:
		return
	var spd: float = _nullsec_speed.current_speed()
	var persist: bool = _nullsec_speed.should_persist_preferred()
	if match_ctrl.has_method("set_battle_speed"):
		match_ctrl.set_battle_speed(spd, persist)
	_refresh_hud()

func _on_nullsec_force_draw() -> void:
	show_notice("墙钟 2 分钟到 · 剩余对局判平局")
	if match_ctrl and match_ctrl.has_method("force_draw_battle"):
		match_ctrl.force_draw_battle()


func _on_seat_battle_finished_speed(_seat: int) -> void:
	## SEMI_ASYNC §4.5 — any finished → max(4×, 场上); auto floor must not stick next round.
	if _nullsec_speed == null:
		return
	var cur: float = TypedVariant.as_float(match_ctrl.speed_multiplier, 1.0) if match_ctrl else 1.0
	_nullsec_speed.mark_seat_finished(cur)
	_apply_resolved_speed()

func _ensure_ground() -> void:
	var g: MeshInstance3D = get_node_or_null("Ground") as MeshInstance3D
	if g == null:
		return
	# Invisible hit plane only — original Endless has no visible floor pad
	if g.mesh == null:
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(48, 48)
		g.mesh = plane
	g.visible = false
	g.position = Vector3(0, -0.05, 0)

func _boot_match_after_ready() -> void:
	## Legacy entry; boot is driven by _process + _boot_phase.
	_boot_phase = 1


func _tick_match_boot() -> void:
	if _boot_phase <= 0:
		return
	if _boot_phase == 1:
		## Advance first so a throw/hang in begin_stepwise cannot re-enter and spawn duplicates.
		_boot_phase = 2
		MatchLoadOverlay.set_phase("正在布置战场环境", 0.34)
		_boot_env = MapEnv.new()
		_boot_env.name = "MapEnv"
		world.add_child(_boot_env)
		## Structures (titans/citadels) sync here; asteroids step below / next frames.
		_boot_env.begin_stepwise(_boot_mode)
		_apply_env_load_overlay(_boot_env)
		return
	if _boot_phase == 2:
		if _boot_env == null or not is_instance_valid(_boot_env):
			push_warning("MatchRoot boot: MapEnv missing; finishing without belt step")
			_boot_phase = 3
			return
		var done: bool = _boot_env.tick_stepwise()
		_apply_env_load_overlay(_boot_env)
		if done:
			_bind_map_env(_boot_env, _boot_mode)
			_boot_env = null
			_boot_phase = 3
		return
	if _boot_phase == 3:
		MatchLoadOverlay.set_phase("正在初始化对局", 0.93)
		## Prevent re-entry if start_match yields / takes multiple frames.
		_boot_phase = 4
		match_ctrl.start_match(_boot_mode)
		if _boot_mode == "nullsec":
			_setup_nullsec_runtime()
		if not _boot_resume_data.is_empty():
			_apply_match_save_dict(_boot_resume_data)
			GameSession.resume_save = false
			GameSession.resume_slot_id = ""
			MatchSave.save_from_match(match_ctrl, board, ai)
			_boot_resume_data = {}
		_refresh_hud()
		_refresh_shop_ui()
		MatchLoadOverlay.hide_overlay()
		_boot_phase = 0
		SessionDiagnostics.log("match.boot_done", "mode=%s" % _boot_mode)


func _spawn_map_env(mode: String) -> void:
	## Sync path kept for callers that cannot await (drains stepwise in one go).
	var env: MapEnv = MapEnv.new()
	env.name = "MapEnv"
	world.add_child(env)
	env.build(mode)
	_bind_map_env(env, mode)


func _apply_env_load_overlay(env: MapEnv) -> void:
	if env == null:
		return
	var ld: Dictionary = env.last_load
	var phase: String = str(ld.get("phase", "正在加载尘埃带陨石"))
	var prog: float = TypedVariant.as_float(ld.get("progress", 0.3), 0.0)
	MatchLoadOverlay.set_phase(phase, clampf(prog, 0.0, 1.0))


func _bind_map_env(env: MapEnv, mode: String) -> void:
	if mode == "nullsec":
		_titan_berth = env.titan_berth
		_rival_titan_berth = env.rival_titan_berth
		_attach_titan_hp_bar()
	else:
		_attach_citadel_hp_bar(env)
	_ensure_sky()

func _attach_titan_hp_bar() -> void:
	## Both berths carry stern three-pipes (MULTIPLAYER_PVP §2.4a / §10).
	_titan_hp_bar = _spawn_titan_hp_bar_on(_titan_berth)
	_rival_titan_hp_bar = _spawn_titan_hp_bar_on(_rival_titan_berth)
	_refresh_titan_hp_bar()

func _spawn_titan_hp_bar_on(berth: TitanBerth) -> Node3D:
	if berth == null or not is_instance_valid(berth):
		return null
	var old: Node = berth.get_node_or_null("TitanHpBar")
	if old:
		old.name = "TitanHpBar_dying"
		berth.remove_child(old)
		old.free()
	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	var bar: Node3D = _TITAN_BAR_SCRIPT.new() as Node3D
	bar.name = "TitanHpBar"
	berth.add_child(bar)
	## Board hangar outside + middle-5 width (MULTIPLAYER_PVP §2.4).
	var team: int = ShipUnit.TEAM_PLAYER if berth.home_side else ShipUnit.TEAM_AI
	bar.call("setup", team, 0.0)
	return bar

func _refresh_titan_hp_bar() -> void:
	## Rebuild if berth lost the bar node (visibility / free races).
	if _titan_berth != null and is_instance_valid(_titan_berth):
		if _titan_hp_bar == null or not is_instance_valid(_titan_hp_bar):
			_titan_hp_bar = _spawn_titan_hp_bar_on(_titan_berth)
	if _rival_titan_berth != null and is_instance_valid(_rival_titan_berth):
		if _rival_titan_hp_bar == null or not is_instance_valid(_rival_titan_hp_bar):
			_rival_titan_hp_bar = _spawn_titan_hp_bar_on(_rival_titan_berth)
	_ensure_titan_pipes_for_bars()
	_apply_pipes_to_titan_bar(_titan_hp_bar, _local_titan_pipes())
	_apply_pipes_to_titan_bar(_rival_titan_hp_bar, _rival_titan_pipes())
	## Sync bar visibility with berth.
	if _titan_hp_bar != null and is_instance_valid(_titan_hp_bar) and _titan_berth != null:
		_titan_hp_bar.visible = _titan_berth.visible
	if _rival_titan_hp_bar != null and is_instance_valid(_rival_titan_hp_bar) and _rival_titan_berth != null:
		_rival_titan_hp_bar.visible = _rival_titan_berth.visible
	_refresh_berth_info_if_open()

func _ensure_titan_pipes_for_bars() -> void:
	if _doomsday_resolver == null:
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	var local_race: String = _local_titan_race_for_ui()
	if local_race != "":
		_doomsday_resolver.ensure_seat(local_seat, local_race)
	var rival_seat: int = _nullsec_rival_seat(local_seat)
	if rival_seat >= 0:
		var rival_race: String = _seat_titan_race(rival_seat)
		if rival_race != "":
			_doomsday_resolver.ensure_seat(rival_seat, rival_race)

func _apply_pipes_to_titan_bar(bar: Node3D, pipes: TitanHpPipes) -> void:
	if bar == null or not is_instance_valid(bar) or pipes == null:
		return
	bar.call("refresh", pipes)

func _local_titan_pipes() -> TitanHpPipes:
	if _doomsday_resolver == null:
		return null
	var seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	@warning_ignore("unsafe_cast")
	return _doomsday_resolver.pipes_by_seat.get(seat) as TitanHpPipes

func _rival_titan_pipes() -> TitanHpPipes:
	if _doomsday_resolver == null:
		return null
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	var rival_seat: int = _nullsec_rival_seat(local_seat)
	if rival_seat < 0:
		return null
	@warning_ignore("unsafe_cast")
	return _doomsday_resolver.pipes_by_seat.get(rival_seat) as TitanHpPipes

func _pipes_for_berth_unit(ship: ShipUnit) -> TitanHpPipes:
	## Decorative berth hulls must show scoring pipes, not COMBAT hull tables (§10).
	if ship == null or _doomsday_resolver == null:
		return null
	if _titan_berth and is_instance_valid(_titan_berth) and ship == _titan_berth.unit:
		return _local_titan_pipes()
	if _rival_titan_berth and is_instance_valid(_rival_titan_berth) and ship == _rival_titan_berth.unit:
		return _rival_titan_pipes()
	return null

func _refresh_berth_info_if_open() -> void:
	if _info_ship == null or not is_instance_valid(_info_ship):
		return
	if _pipes_for_berth_unit(_info_ship) == null:
		return
	_show_ship_info(_info_ship)

func _attach_citadel_hp_bar(env: MapEnv) -> void:
	if env == null or env.player_citadel == null:
		return
	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	_citadel_hp_bar = _CITADEL_BAR_SCRIPT.new() as Node3D
	_citadel_hp_bar.name = "CitadelHealthBar"
	env.player_citadel.add_child(_citadel_hp_bar)
	_citadel_hp_bar.call("setup", TypedVariant.as_float(DataStore.visual.get("citadel_health_bar_y", 9.5), 0.0))
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
	## NEW_EDEN_REGIONS §2 deferred: old-version construction (amarr/gallente/wormhole.jpeg).
	if get_node_or_null("WorldEnvironment"):
		return
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.1, 0.14)
	var sky_tex: Texture2D = SkyboxCatalog.load_legacy_panorama()
	if sky_tex == null:
		sky_tex = UiAssets.tex("res://assets/skyboxes/amarr.jpeg")
	if sky_tex == null:
		sky_tex = UiAssets.tex("res://assets/skyboxes/gallente.jpeg")
	if sky_tex:
		environment.background_mode = Environment.BG_SKY
		var sky: Sky = Sky.new()
		var mat: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
		mat.panorama = sky_tex
		mat.energy_multiplier = SkyboxCatalog.RACE_SKY_ENERGY
		sky.sky_material = mat
		environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.74, 0.78)
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
	if environment.sky and environment.sky.sky_material is PanoramaSkyMaterial:
		(environment.sky.sky_material as PanoramaSkyMaterial).energy_multiplier = SkyboxCatalog.RACE_SKY_ENERGY
	we.environment = environment
	add_child(we)
	_ensure_board_lights()

func apply_region_skybox(_region_id: String) -> void:
	## Deferred: do not swap panorama per region / race stem (NEW_EDEN_REGIONS §2).
	return

func _ensure_board_lights() -> void:
	## Off-frustum lights — driven by visual.json ship_look (unity-standard default).
	if get_node_or_null("KeyLightOffscreen") == null:
		var key: DirectionalLight3D = DirectionalLight3D.new()
		key.name = "KeyLightOffscreen"
		key.light_energy = 1.0
		key.light_color = Color(1.0, 1.0, 1.0)
		key.shadow_enabled = true
		key.shadow_opacity = 0.55
		key.rotation_degrees = Vector3(-57.3, 107.7, 0.0)
		add_child(key)
	if get_node_or_null("RimLightOffscreen") == null:
		var rim: DirectionalLight3D = DirectionalLight3D.new()
		rim.name = "RimLightOffscreen"
		rim.light_energy = 0.0
		rim.light_color = Color(0.65, 0.8, 1.0)
		rim.shadow_enabled = false
		rim.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
		add_child(rim)
	if get_node_or_null("FillLight") == null:
		var fill: OmniLight3D = OmniLight3D.new()
		fill.name = "FillLight"
		fill.light_energy = 0.0
		fill.omni_range = 85.0
		fill.position = Vector3(0, 32, 10)
		add_child(fill)
	if get_node_or_null("FillLightAI") == null:
		var fill_ai: OmniLight3D = OmniLight3D.new()
		fill_ai.name = "FillLightAI"
		fill_ai.light_energy = 0.0
		fill_ai.light_color = Color(0.88, 0.92, 1.0)
		fill_ai.omni_range = 60.0
		fill_ai.position = Vector3(-16.0, 24.0, -18.0)
		add_child(fill_ai)
	if get_node_or_null("FillLightPlayer") == null:
		var fill_p: OmniLight3D = OmniLight3D.new()
		fill_p.name = "FillLightPlayer"
		fill_p.light_energy = 0.0
		fill_p.light_color = Color(1.0, 0.96, 0.9)
		fill_p.omni_range = 60.0
		fill_p.position = Vector3(16.0, 24.0, 18.0)
		add_child(fill_p)
	var scene_key: DirectionalLight3D = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if scene_key:
		scene_key.light_energy = 0.0
		scene_key.shadow_opacity = 0.4
	ShipLook.apply_match_lights(self)

func _setup_camera() -> void:
	## Two default camera views:
	## - primary: battle / shop collapsed baseline
	## - secondary: prepare + shop expanded
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var start: Dictionary = _camera_secondary_view() if not _collapse_bottom else _camera_primary_view()
	_cam_base_pos = TypedVariant.as_vector3(start.get("pos", Vector3(-2.0, 21.464, 18.067)), Vector3(-2.0, 21.464, 18.067))
	_cam_base_pitch_deg = TypedVariant.as_float(start.get("pitch_deg", -57.0), 0.0)
	_cam_default_pitch_deg = TypedVariant.as_float(_camera_primary_view().get("pitch_deg", _cam_base_pitch_deg), 0.0)
	_cam_base_yaw_deg = TypedVariant.as_float(start.get("yaw_deg", 0.0), 0.0)
	camera.fov = TypedVariant.as_float(start.get("fov", 47.0), 0.0)
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _camera_primary_view() -> Dictionary:
	var v: Dictionary = DataStore.visual
	return {
		"pos": Vector3(
			TypedVariant.as_float(v.get("camera_x", 2.00856733322144), 0.0),
			TypedVariant.as_float(v.get("camera_height", 35.0967063903809), 0.0),
			TypedVariant.as_float(v.get("camera_distance", 28.4933738708496), 0.0)
		),
		"pitch_deg": -TypedVariant.as_float(v.get("camera_angle_deg", 55.6669960021973), 0.0),
		"yaw_deg": TypedVariant.as_float(v.get("camera_yaw_deg", 180.0), 0.0) - 180.0,
		"fov": TypedVariant.as_float(v.get("camera_fov", 50.0), 0.0)
	}

func _camera_secondary_view() -> Dictionary:
	var v: Dictionary = DataStore.visual
	return {
		"pos": Vector3(
			TypedVariant.as_float(v.get("camera_second_x", 1.82857227325439), 0.0),
			TypedVariant.as_float(v.get("camera_second_height", 27.0970573425293), 0.0),
			TypedVariant.as_float(v.get("camera_second_distance", 33.6982917785645), 0.0)
		),
		"pitch_deg": -TypedVariant.as_float(v.get("camera_second_angle_deg", 55.6669960021973), 0.0),
		"yaw_deg": TypedVariant.as_float(v.get("camera_second_yaw_deg", TypedVariant.as_float(v.get("camera_yaw_deg", 180.0), 180.0)), TypedVariant.as_float(v.get("camera_yaw_deg", 180.0), 180.0)) - 180.0,
		"fov": TypedVariant.as_float(v.get("camera_second_fov", TypedVariant.as_float(v.get("camera_fov", 50.0), 50.0)), TypedVariant.as_float(v.get("camera_fov", 50.0), 50.0)),
	}

func _camera_active_view() -> Dictionary:
	if match_ctrl and match_ctrl.stage == MatchController.Stage.BATTLE:
		return _camera_primary_view()
	return _camera_primary_view() if _collapse_bottom else _camera_secondary_view()

func _camera_manual_pose() -> bool:
	## Free + observe + post-observe return delay: framing / stage must not steal the lens.
	return _camera_free or _camera_observe or _observe_return_delay_left > 0.0

func _process(delta: float) -> void:
	if _boot_phase > 0:
		_tick_match_boot()
		return
	if _nullsec_speed:
		_nullsec_speed.tick_wall_clock()
	_try_release_doomsday_gate()
	var t_cam: int = Time.get_ticks_usec()
	if _camera_observe:
		_update_camera_observe(delta)
	elif _camera_free:
		_update_camera_free(delta)
	else:
		_tick_observe_return_delay(delta)
		_update_camera_headup(delta)
		_update_camera_view_blend(delta)
		_update_camera_framing(delta)
	_try_hide_slot_markers_when_view1_settled()
	## Breathe applies in both default and free view (options toggle only).
	_update_camera_breathe()
	SessionDiagnostics.add_usec(&"cam", Time.get_ticks_usec() - t_cam)
	_tick_exp_hold(delta)
	_tick_titan_intro(delta)
	_tick_info_hold()
	_tick_equipment_detail_hover()
	_tick_scout_departs(delta)
	if _combat_eval_active and _combat_eval != null and match_ctrl \
			and match_ctrl.stage == MatchController.Stage.BATTLE \
			and not match_ctrl.remote_watch_only:
		_combat_eval.tick(board)
	if GameSession.pending_mode == "nullsec" and match_ctrl \
			and match_ctrl.stage == MatchController.Stage.BATTLE:
		_tick_net_battle_enrich()
		if _net_battle and _net_battle.is_host:
			_net_jobs_ready_for_titan = _net_battle.host_sim == null \
				or _net_battle.host_sim.pending_count() == 0
	_tick_prepare_stuck_pulse(delta)


## SEMI_ASYNC §3.0a — escape prepare freeze when net/local arm desync or barrier hangs.
func _tick_prepare_stuck_pulse(delta: float) -> void:
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.PREPARE:
		_prep_freeze_wall_ms = 0
		_prep_pulse_acc_s = 0.0
		return
	if GameSession.pending_mode != "nullsec":
		return
	## Presentation freeze ≠ deadlock — never force-arm during doomsday/kill.
	if _doomsday_busy or _titan_kill_active > 0 or _nullsec_prepare_pending or _presentation_hold:
		_prep_freeze_wall_ms = 0
		_prep_pulse_acc_s = 0.0
		return
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null or not net.needs_stage_barrier():
		_prep_freeze_wall_ms = 0
		_prep_pulse_acc_s = 0.0
		return
	## R1 spend gate: freeze is intentional until every contestant spends — no pulse force-arm.
	if match_ctrl.battle_game_stage_count == 0 and net.is_prepare_spend_gate_pending():
		_prep_freeze_wall_ms = 0
		_prep_pulse_acc_s = 0.0
		return
	var local_frozen: bool = not match_ctrl.prepare_clock_armed
	var peer_hold: bool = match_ctrl.is_prepare_peer_hold()
	var gate: bool = net.is_battle_done_gate_open() or net.is_prepare_done_gate_open()
	var arm_desync: bool = net.prepare_clock_armed != match_ctrl.prepare_clock_armed
	if not local_frozen and not peer_hold and not gate and not arm_desync:
		_prep_freeze_wall_ms = 0
		_prep_pulse_acc_s = 0.0
		return
	var now: int = Time.get_ticks_msec()
	if _prep_freeze_wall_ms <= 0:
		_prep_freeze_wall_ms = now
	_prep_pulse_acc_s += delta
	if _prep_pulse_acc_s < PREP_PULSE_S:
		return
	_prep_pulse_acc_s = 0.0
	## Heal: net already armed but MatchController still frozen (1v1 deadlock root).
	if net.prepare_clock_armed and not match_ctrl.prepare_clock_armed:
		print("[mp.diag] prep_pulse_escape heal_arm_desync")
		SessionDiagnostics.log("mp.prep_pulse_escape", "heal_arm_desync")
		match_ctrl.arm_prepare_clock()
		_refresh_hud()
		show_notice("联机时钟已对齐")
	var acts: String = net.pulse_prepare_escape()
	if acts != "":
		print("[mp.diag] prep_pulse_escape net=%s" % acts)
		SessionDiagnostics.log("mp.prep_pulse_escape", "net=%s" % acts)
	var elapsed: int = now - _prep_freeze_wall_ms
	if elapsed >= PREP_FORCE_ARM_MS and not match_ctrl.prepare_clock_armed:
		## Spend gate still pending → never force (belt-and-suspenders).
		if net.is_prepare_spend_gate_pending():
			print("[mp.diag] prep_pulse_escape force_local_arm SKIP spend_gate")
			SessionDiagnostics.log("mp.prep_pulse_escape", "force_local_arm_skip_spend")
			_prep_freeze_wall_ms = now
			return
		print("[mp.diag] prep_pulse_escape force_local_arm elapsed=%d" % elapsed)
		SessionDiagnostics.log("mp.prep_pulse_escape", "force_local_arm ms=%d" % elapsed)
		if net.is_host:
			net.force_arm_prepare_clock_escape()
		if net.prepare_clock_armed:
			match_ctrl.arm_prepare_clock()
			show_notice("联机同步超时 · 已强制开钟")
			_refresh_hud()
		_prep_freeze_wall_ms = now
	elif elapsed >= PREP_FORCE_ARM_MS and peer_hold and net.is_host:
		print("[mp.diag] prep_pulse_escape force_peer_hold elapsed=%d" % elapsed)
		SessionDiagnostics.log("mp.prep_pulse_escape", "force_peer_hold ms=%d" % elapsed)
		net.force_barrier_escape()
		_prep_freeze_wall_ms = now


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		@warning_ignore("unsafe_cast")
		var _ke: InputEventKey = event as InputEventKey
		if _ke.pressed and not _ke.echo:
			if _ke.keycode == KEY_ESCAPE and not _gui_wants_text_input():
				_toggle_game_menu()
				get_viewport().set_input_as_handled()
				return
			if _ke.keycode == KEY_V and not _gui_wants_text_input() and not UiLayout.is_mobile():
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
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_look_dragging = mb.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _cam_look_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var sens: float = TypedVariant.as_float(DataStore.visual.get("camera_free_look_sens", 0.18), 0.0)
		_cam_base_yaw_deg -= mm.relative.x * sens
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg - mm.relative.y * sens, -89.0, 89.0)
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		get_viewport().set_input_as_handled()

func _handle_observe_orbit_input(event: InputEvent) -> void:
	## PC: middle-drag orbit + wheel zoom. Mobile: 1-finger orbit + 2-finger pinch zoom.
	## Zoom changes distance only — never FOV (UI_AND_SHELL §2.3.1).
	if event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		## factor > 1 = fingers apart = zoom in (closer).
		if mg.factor > 0.001:
			_observe_zoom_by(1.0 / mg.factor)
		get_viewport().set_input_as_handled()
		return
	if UiLayout.is_mobile():
		_handle_observe_mobile_input(event)
		return
	if event is InputEventMouseButton:
		var mb2: InputEventMouseButton = event as InputEventMouseButton
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
		var mm2: InputEventMouseMotion = event as InputEventMouseMotion
		var sens: float = TypedVariant.as_float(DataStore.visual.get("camera_free_look_sens", 0.18), 0.0)
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
		var st: InputEventScreenTouch = event as InputEventScreenTouch
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
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		_observe_touch_pos[sd.index] = sd.position
		if _observe_pinch_ids.size() >= 2:
			var span: float = _observe_pinch_span()
			if _observe_pinch_last_dist > 1.0 and span > 1.0:
				## Fingers apart → span grows → zoom in (closer).
				_observe_zoom_by(_observe_pinch_last_dist / span)
			_observe_pinch_last_dist = span
			get_viewport().set_input_as_handled()
			return
		if not _cam_orbit_dragging or sd.index != _cam_orbit_touch_index:
			return
		var sens_m: float = TypedVariant.as_float(DataStore.visual.get("camera_free_look_sens", 0.18), 0.0)
		_orbit_camera_around_observe(-sd.relative.x * sens_m, -sd.relative.y * sens_m)
		get_viewport().set_input_as_handled()

func _observe_pinch_span() -> float:
	if _observe_pinch_ids.size() < 2:
		return 0.0
	var a: int = _observe_pinch_ids[0]
	var b: int = _observe_pinch_ids[1]
	if not _observe_touch_pos.has(a) or not _observe_touch_pos.has(b):
		return _observe_pinch_last_dist
	@warning_ignore("unsafe_cast")
	return (_observe_touch_pos[a] as Vector2).distance_to(_observe_touch_pos[b] as Vector2)

func _handle_mobile_orbit_input(event: InputEvent) -> void:
	## Single-finger drag orbits around board center; ignore 2nd finger / ship drags.
	if pointer != null and pointer.has_method("is_pointer_dragging") and pointer.is_pointer_dragging():
		_cam_orbit_dragging = false
		_cam_orbit_touch_index = -1
		return
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
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
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if not _cam_orbit_dragging or sd.index != _cam_orbit_touch_index:
			return
		var sens: float = TypedVariant.as_float(DataStore.visual.get("camera_free_look_sens", 0.18), 0.0)
		## Flip yaw vs prior inverted touch orbit (UI_AND_SHELL mobile free-cam).
		_orbit_camera_around_board(sd.relative.x * sens, -sd.relative.y * sens)
		get_viewport().set_input_as_handled()

func _ui_blocks_camera_touch(screen: Vector2) -> bool:
	if pointer != null and pointer.has_method("ui_blocks_screen"):
		return bool(pointer.ui_blocks_screen(screen))
	var hover: Control = get_viewport().gui_get_hovered_control() if get_viewport() else null
	return hover != null

func _screen_hits_ship(screen: Vector2) -> bool:
	if board == null or camera == null:
		return false
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
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
	var pivot: Vector3 = _observe_pivot()
	var cp: float = cos(_observe_elev)
	_cam_base_pos = pivot + Vector3(sin(_observe_yaw) * cp, sin(_observe_elev), cos(_observe_yaw) * cp) * _observe_dist
	camera.position = _cam_base_pos
	if camera.global_position.distance_squared_to(pivot) > 0.0001:
		camera.look_at(pivot, Vector3.UP)
	_cam_base_pitch_deg = camera.rotation_degrees.x
	_cam_base_yaw_deg = camera.rotation_degrees.y

func _observe_fit_distance(ship: ShipUnit) -> float:
	var radius: float = 1.0
	if ship != null and is_instance_valid(ship):
		radius = maxf(ship.visual_radius_world(), 0.5)
	var half_v: float = deg_to_rad(maxf(camera.fov, 1.0) * 0.5)
	var vp: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(16, 9)
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	var half_h: float = atan(tan(half_v) * aspect)
	var half: float = minf(half_v, half_h)
	var mul: float = TypedVariant.as_float(DataStore.visual.get("camera_observe_fit_mul", 1.15), 0.0)
	return maxf((radius * mul) / maxf(tan(half), 0.01), 2.0)

func _observe_front_left_above_dir(ship: ShipUnit) -> Vector3:
	## Bow = local −Z; left = local −X; mix with world-up for「左前上方」.
	## Capture once at enter — later ship yaw must not rewrite this world angle.
	var ship_basis: Basis = ship.global_transform.basis
	var forward: Vector3 = -ship_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0, 0, -1)
	else:
		forward = forward.normalized()
	var left: Vector3 = -ship_basis.x
	left.y = 0.0
	if left.length_squared() < 0.0001:
		left = Vector3(-1, 0, 0)
	else:
		left = left.normalized()
	var elev_w: float = TypedVariant.as_float(DataStore.visual.get("camera_observe_elev_weight", 0.85), 0.0)
	var dir: Vector3 = (forward + left + Vector3.UP * elev_w)
	if dir.length_squared() < 0.0001:
		return Vector3(-0.5, 0.7, -0.5).normalized()
	return dir.normalized()

func _orbit_camera_around_pivot(pivot: Vector3, yaw_delta_deg: float, pitch_delta_deg: float, pitch_limit_deg: float) -> void:
	var offset: Vector3 = _cam_base_pos - pivot
	var dist: float = maxf(offset.length(), 2.0)
	var yaw: int = atan2(offset.x, offset.z) + deg_to_rad(yaw_delta_deg)
	var pitch: float = asin(clampf(offset.y / dist, -0.999, 0.999)) + deg_to_rad(pitch_delta_deg)
	## Keep a hair inside ±90 so look_at never flips through the pole.
	var lim: float = minf(absf(pitch_limit_deg), 90.0)
	pitch = clampf(pitch, deg_to_rad(-lim + 0.05), deg_to_rad(lim - 0.05))
	var cp: float = cos(pitch)
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
	var focus: Control = get_viewport().gui_get_focus_owner() if get_viewport() else null
	return focus is LineEdit or focus is TextEdit

func _on_camera_mode_pressed() -> void:
	_toggle_camera_mode()

func _toggle_camera_mode() -> void:
	## Observe: top bar / V = exit observe → default (not free). Else default ↔ free.
	if _camera_observe:
		_exit_observe_unit(true)
		show_notice("默认视角")
		return
	_set_camera_free(not _camera_free)

func _set_camera_free(enabled: bool) -> void:
	if enabled:
		_observe_return_delay_left = 0.0
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
	_observe_return_delay_left = 0.0
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
	var dir: Vector3 = _observe_front_left_above_dir(ship)
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
		## Active cancel / 退出观察: hold pose, then smooth-blend to default.
		var delay: float = 0.4
		if DataStore and DataStore.visual is Dictionary:
			delay = TypedVariant.as_float(DataStore.visual.get("camera_observe_return_delay_s", 0.4), 0.0)
		_observe_return_delay_left = maxf(0.0, delay)
		if _observe_return_delay_left <= 0.0:
			_snap_camera_to_active_default()
	else:
		_observe_return_delay_left = 0.0
	_refresh_camera_mode_btn()
	_refresh_observe_btn()


## Passive end of observe (hide info / ship gone): keep lens — become free at current pose.
func _exit_observe_keep_view() -> void:
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
	_observe_return_delay_left = 0.0
	_cam_view_blend_active = false
	## Last _apply_observe_pose already wrote _cam_base_* / camera.
	_camera_free = true
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	_refresh_camera_mode_btn()
	_refresh_observe_btn()

func _tick_observe_return_delay(delta: float) -> void:
	if _observe_return_delay_left <= 0.0:
		return
	_observe_return_delay_left = maxf(0.0, _observe_return_delay_left - delta)
	if _observe_return_delay_left > 0.0:
		return
	_snap_camera_to_active_default()

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
		_exit_observe_keep_view()
		return
	## Pivot follows translation only; world yaw/elev stay fixed unless user orbits.
	_apply_observe_pose()

func _ensure_observe_btn() -> void:
	## InfoPanel is a PanelContainer, so a direct child would stretch over the whole
	## panel as a grey slab. InfoTop is no host either: portrait + weapon column
	## already fill the right column's width, and the button gets squeezed out of
	## view there. Own row in the body, right under the title block.
	@warning_ignore("unsafe_cast")
	var panel: PanelContainer = hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if panel == null:
		return
	var body: VBoxContainer = _info_body(panel)
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
	var top: Node = body.get_node_or_null("InfoTop")
	if top == null or _observe_btn == null or not is_instance_valid(_observe_btn):
		return
	body.move_child(_observe_btn, mini(top.get_index() + 1, body.get_child_count() - 1))

func _refresh_observe_btn() -> void:
	_ensure_observe_btn()
	if _observe_btn == null or not is_instance_valid(_observe_btn):
		return
	var can: bool = _info_ship != null and is_instance_valid(_info_ship)
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
	_cam_default_pitch_deg = TypedVariant.as_float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg), 0.0)
	_cam_headup_phase = 0
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0
	var pos: Vector3 = TypedVariant.as_vector3(view.get("pos", _cam_base_pos), _cam_base_pos)
	var pitch: float = TypedVariant.as_float(view.get("pitch_deg", _cam_base_pitch_deg), 0.0)
	var yaw: float = TypedVariant.as_float(view.get("yaw_deg", _cam_base_yaw_deg), 0.0)
	var fov: float = TypedVariant.as_float(view.get("fov", camera.fov), 0.0)
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
	_cam_base_pos = TypedVariant.as_vector3(pose.get("pos", _cam_base_pos), _cam_base_pos)
	_cam_base_pitch_deg = TypedVariant.as_float(pose.get("pitch_deg", _cam_base_pitch_deg), 0.0)
	_cam_base_yaw_deg = TypedVariant.as_float(pose.get("yaw_deg", _cam_base_yaw_deg), 0.0)
	camera.fov = TypedVariant.as_float(pose.get("fov", camera.fov), 0.0)
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
	@warning_ignore("unsafe_cast")
	var btn: Button = hud.get_node_or_null("Root/TopRight/CamModeBtn") as Button
	if btn == null:
		return
	if _camera_observe:
		btn.text = "退出观察"
		btn.tooltip_text = "当前：观察单位 · 点此退出并回默认视角"
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
	var speed: float = TypedVariant.as_float(v.get("camera_free_move_speed", _CAM_MOVE_SPEED), 0.0)
	var cam_basis: Basis = camera.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x
	var up: Vector3 = Vector3.UP
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
		move -= up
	if Input.is_physical_key_pressed(KEY_E):
		move += up
	if move != Vector3.ZERO:
		_cam_base_pos += move.normalized() * speed * delta
	var pitch_delta: float = 0.0
	if Input.is_physical_key_pressed(KEY_R):
		pitch_delta += _CAM_PITCH_SPEED * delta
	if Input.is_physical_key_pressed(KEY_F):
		pitch_delta -= _CAM_PITCH_SPEED * delta
	if pitch_delta != 0.0:
		_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + pitch_delta, -89.0, 89.0)
	var yaw_delta: float = 0.0
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
	var rise_s: float = maxf(0.01, TypedVariant.as_float(v.get("camera_headup_time_s", 0.18), 0.0))
	var recover_s: float = maxf(0.01, TypedVariant.as_float(v.get("camera_headup_recover_s", 0.32), 0.0))
	var target_deg: float = maxf(0.0, TypedVariant.as_float(v.get("camera_headup_pitch_deg", 6.0), 0.0))
	_cam_headup_t += delta
	if _cam_headup_phase == 1:
		var up_k: float = clampf(_cam_headup_t / rise_s, 0.0, 1.0)
		_cam_headup_offset_deg = lerpf(0.0, target_deg, ease(up_k, -2.0))
		if up_k >= 1.0:
			_cam_base_pitch_deg = clampf(_cam_base_pitch_deg + target_deg, -89.0, -5.0)
			_cam_headup_phase = 0
			_cam_headup_t = 0.0
			_cam_headup_offset_deg = 0.0
	else:
		var down_k: float = clampf(_cam_headup_t / recover_s, 0.0, 1.0)
		_cam_headup_offset_deg = lerpf(target_deg, 0.0, ease(down_k, 2.0))
		if down_k >= 1.0:
			_cam_headup_phase = 0
			_cam_headup_t = 0.0
			_cam_headup_offset_deg = 0.0

func _trigger_camera_headup(reason: String) -> void:
	if _camera_manual_pose():
		return
	var v: Dictionary = DataStore.visual
	if not TypedVariant.as_bool(v.get("camera_headup_enabled", false), false):
		return
	if _suppress_headup_for_preview:
		return
	var trigger: String = str(v.get("camera_headup_trigger", "stage_change"))
	if trigger != "all" and trigger != reason:
		return
	_cam_headup_phase = 1
	_cam_headup_t = 0.0
	_cam_headup_offset_deg = 0.0

func _update_camera_view_blend(delta: float) -> void:
	if not _cam_view_blend_active or _camera_manual_pose():
		return
	## Allow one-shot blends (shop / exit-observe return) even in Battle; framing resumes after.
	var framing: Dictionary = DataStore.visual.get("camera_framing", {})
	var spd: float = TypedVariant.as_float(framing.get("lerp_speed", 4.0), 0.0)
	var k: float = clampf(spd * delta, 0.0, 1.0)
	_cam_base_pos = _cam_base_pos.lerp(_cam_view_blend_pos, k)
	_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, _cam_view_blend_pitch_deg, k)
	_cam_base_yaw_deg = lerpf(_cam_base_yaw_deg, _cam_view_blend_yaw_deg, k)
	camera.fov = lerpf(camera.fov, _cam_view_blend_fov, k)
	var pos_done: bool = _cam_base_pos.distance_to(_cam_view_blend_pos) < 0.03
	var ang_done: bool = absf(_cam_base_pitch_deg - _cam_view_blend_pitch_deg) < 0.08 \
		and absf(_cam_base_yaw_deg - _cam_view_blend_yaw_deg) < 0.08
	var fov_done: bool = absf(camera.fov - _cam_view_blend_fov) < 0.05
	if pos_done and ang_done and fov_done:
		_cam_base_pos = _cam_view_blend_pos
		_cam_base_pitch_deg = _cam_view_blend_pitch_deg
		_cam_base_yaw_deg = _cam_view_blend_yaw_deg
		camera.fov = _cam_view_blend_fov
		_cam_view_blend_active = false

func _update_camera_framing(delta: float) -> void:
	if _camera_manual_pose():
		return
	## While a one-shot view blend runs (exit observe / shop), let it own the pose.
	if _cam_view_blend_active:
		return
	## Prepare: shop open/close events own the pose. Only Battle continuously locks view 1.
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		return
	var framing: Dictionary = DataStore.visual.get("camera_framing", {})
	var spd: float = TypedVariant.as_float(framing.get("lerp_speed", 4.0), 0.0)
	var view: Dictionary = _camera_primary_view()
	var k: float = clampf(spd * delta, 0.0, 1.0)
	var target_pos: Vector3 = TypedVariant.as_vector3(view.get("pos", _cam_base_pos), _cam_base_pos)
	_cam_base_pos = _cam_base_pos.lerp(target_pos, k)
	_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, TypedVariant.as_float(view.get("pitch_deg", _cam_base_pitch_deg), 0.0), k)
	_cam_base_yaw_deg = lerpf(_cam_base_yaw_deg, TypedVariant.as_float(view.get("yaw_deg", _cam_base_yaw_deg), 0.0), k)
	camera.fov = lerpf(camera.fov, TypedVariant.as_float(view.get("fov", camera.fov), 0.0), k)
	_cam_default_pitch_deg = TypedVariant.as_float(view.get("pitch_deg", _cam_default_pitch_deg), 0.0)
	_cam_frame_target = Vector3.ZERO
	_cam_frame_offset = Vector3.ZERO
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _camera_near_primary_view() -> bool:
	var view: Dictionary = _camera_primary_view()
	var pos: Vector3 = TypedVariant.as_vector3(view.get("pos", _cam_base_pos), _cam_base_pos)
	if _cam_base_pos.distance_to(pos) > 0.08:
		return false
	if absf(_cam_base_pitch_deg - TypedVariant.as_float(view.get("pitch_deg", _cam_base_pitch_deg), 0.0)) > 0.15:
		return false
	if absf(_cam_base_yaw_deg - TypedVariant.as_float(view.get("yaw_deg", _cam_base_yaw_deg), 0.0)) > 0.15:
		return false
	if absf(camera.fov - TypedVariant.as_float(view.get("fov", camera.fov), 0.0)) > 0.1:
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
	var base: Vector3 = _cam_base_pos if _camera_manual_pose() else (_cam_base_pos + _cam_frame_offset)
	var amp: float = TypedVariant.as_float(v.get("camera_breathe_amp", 0.35), 0.0)
	var period: float = maxf(0.5, TypedVariant.as_float(v.get("camera_breathe_period_s", 12.0), 0.0))
	## Titan kill shake: super-accelerated breathe (wall clock); never on free/observe cam.
	var shaking: int = (not _camera_manual_pose()) and _titan_shake_until_ms > 0 and Time.get_ticks_msec() < _titan_shake_until_ms
	if shaking:
		amp = TypedVariant.as_float(v.get("titan_kill_shake_amp", 4.5), 0.0)
		period = maxf(0.05, TypedVariant.as_float(v.get("titan_kill_shake_period_s", 0.22), 0.0))
	elif _titan_shake_until_ms > 0 and Time.get_ticks_msec() >= _titan_shake_until_ms:
		_titan_shake_until_ms = 0
	## Player setting overrides content; options menu is the only off switch.
	## Shake still runs even if breathe preference is off (kill cue).
	var breathe_on: bool = true
	if not shaking:
		if GameSession != null:
			breathe_on = GameSession.camera_breathe_enabled
		elif not TypedVariant.as_bool(v.get("camera_breathe_enabled", true), false):
			breathe_on = false
	if not breathe_on and not shaking:
		camera.position = base
		if _camera_observe:
			var piv0: Vector3 = _observe_pivot()
			if camera.global_position.distance_squared_to(piv0) > 0.0001:
				camera.look_at(piv0, Vector3.UP)
		else:
			camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)
		return
	var th: float = Time.get_ticks_msec() * 0.001 * TAU / period
	var s: float = sin(th)
	var c: float = cos(th)
	# Diagonal figure-8 on XZ only (no Y) so pitch feel stays stable.
	var local: Vector3 = Vector3(s, 0.0, s * c) * amp
	var half: float = 0.70710678
	var offset: Vector3 = Vector3(
		local.x * half - local.z * half,
		0.0,
		local.x * half + local.z * half
	)
	camera.position = base + offset
	if _camera_observe:
		var piv1: Vector3 = _observe_pivot()
		if camera.global_position.distance_squared_to(piv1) > 0.0001:
			camera.look_at(piv1, Vector3.UP)
	else:
		camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _build_hud() -> void:
	_ensure_side_panel_scrolls()
	_ensure_reserve_grid()
	_ensure_observe_btn()
	_apply_adaptive_hud_layout()
	_style_hud_chrome()
	_wire_shop_chrome()
	_apply_shop_interactable()
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root and not root.resized.is_connected(_on_hud_resized):
		root.resized.connect(_on_hud_resized)
	@warning_ignore("unsafe_cast")
	var pause: Button = hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if pause:
		## Versus / Endless keep PauseBtn; nullsec has no pause (UI_AND_SHELL §2.2A).
		var allow_pause: bool = GameSession == null or str(GameSession.pending_mode) != "nullsec"
		pause.visible = allow_pause
		pause.process_mode = Node.PROCESS_MODE_ALWAYS if allow_pause else Node.PROCESS_MODE_DISABLED
		if allow_pause:
			pause.text = "继续" if get_tree().paused else "暂停"
	@warning_ignore("unsafe_cast")
	var exit_btn: Button = hud.get_node_or_null("Root/TopRight/ExitBtn") as Button
	if exit_btn:
		exit_btn.text = "菜单"
		exit_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_scout_intel_btn()
	@warning_ignore("unsafe_cast")
	var cam_btn: Button = hud.get_node_or_null("Root/TopRight/CamModeBtn") as Button
	if cam_btn:
		cam_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_build_game_menu()
	_refresh_camera_mode_btn()

func _ensure_scout_intel_btn() -> void:
	@warning_ignore("unsafe_cast")
	var top_r: Control = hud.get_node_or_null("Root/TopRight") as Control
	if top_r == null:
		return
	if top_r.get_node_or_null("ScoutIntelBtn") != null:
		_reorder_top_right_children(top_r as HBoxContainer)
		return
	var btn: ScoutIntelButton = ScoutIntelButton.new()
	btn.name = "ScoutIntelBtn"
	btn.visible = GameSession.pending_mode == "nullsec"
	top_r.add_child(btn)
	_reorder_top_right_children(top_r as HBoxContainer)

func _reorder_top_right_children(top_r: HBoxContainer) -> void:
	## L→R tree order; HBox ALIGNMENT_END packs 菜单 at the right edge (右→左可读序).
	if top_r == null:
		return
	top_r.alignment = BoxContainer.ALIGNMENT_END
	var order: Array = ["Version", "ScoutIntelBtn", "CamModeBtn", "SpeedBtn", "PauseBtn", "ExitBtn"]
	var i: int = 0
	for n: String in order:
		@warning_ignore("unsafe_cast")
		var c: Node = top_r.get_node_or_null(n) as Node
		if c:
			top_r.move_child(c, i)
			i += 1

func _chrome_content_min_size(c: Control) -> Vector2:
	if c == null:
		return Vector2.ZERO
	var ms: Vector2 = c.get_combined_minimum_size()
	## Fall back if not yet sized (first frame).
	if ms.x < 8.0 and ms.y < 8.0:
		ms = c.size
	return ms

func _on_hud_resized() -> void:
	_ensure_side_panel_scrolls()
	_apply_adaptive_hud_layout()
	_style_hud_chrome()
	_wire_shop_chrome()
	_apply_shop_interactable()
	var grid: GridContainer = hud.get_node_or_null("Root/%s" % _RESERVE_GRID_PATH) as GridContainer
	if grid:
		_layout_reserve_grid_cells(grid)
	_refresh_equipment_inventory_ui()

func _ensure_side_panel_scrolls() -> void:
	## Fetters scroll above a pinned equipment bag; InfoPanel body scrolls (UI_AND_SHELL).
	@warning_ignore("unsafe_cast")
	var left_content: VBoxContainer = hud.get_node_or_null("Root/LeftCol/LeftInner/LeftContent") as VBoxContainer
	if left_content:
		@warning_ignore("unsafe_cast")
		var bonus: VBoxContainer = left_content.get_node_or_null("BonusContainer") as VBoxContainer
		@warning_ignore("unsafe_cast")
		var scroll: ScrollContainer = left_content.get_node_or_null("BonusScroll") as ScrollContainer
		if scroll == null and bonus != null:
			scroll = ScrollContainer.new()
			scroll.name = "BonusScroll"
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.mouse_filter = Control.MOUSE_FILTER_STOP
			var idx: int = bonus.get_index()
			left_content.remove_child(bonus)
			left_content.add_child(scroll)
			left_content.move_child(scroll, idx)
			scroll.add_child(bonus)
		elif scroll != null and bonus == null:
			@warning_ignore("unsafe_cast")
			bonus = scroll.get_node_or_null("BonusContainer") as VBoxContainer
		if scroll:
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll.mouse_filter = Control.MOUSE_FILTER_STOP
			scroll.scroll_deadzone = 8 if UiLayout.is_mobile() else 0
		if bonus:
			bonus.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			bonus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var grid: GridContainer = left_content.get_node_or_null("ReserveGrid") as GridContainer
		if grid:
			## Width fills left column; height follows 4× square cells (not stretch).
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.size_flags_vertical = Control.SIZE_SHRINK_END
			if grid.get_parent() == left_content:
				left_content.move_child(grid, left_content.get_child_count() - 1)
	@warning_ignore("unsafe_cast")
	var info: PanelContainer = hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if info:
		@warning_ignore("unsafe_cast")
		var body: VBoxContainer = info.get_node_or_null("InfoBody") as VBoxContainer
		@warning_ignore("unsafe_cast")
		var iscroll: ScrollContainer = info.get_node_or_null(_INFO_SCROLL) as ScrollContainer
		if iscroll == null and body != null and body.get_parent() == info:
			iscroll = ScrollContainer.new()
			iscroll.name = _INFO_SCROLL
			iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			iscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			iscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			iscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			iscroll.mouse_filter = Control.MOUSE_FILTER_STOP
			info.remove_child(body)
			info.add_child(iscroll)
			iscroll.add_child(body)
		if iscroll:
			iscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			iscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			iscroll.mouse_filter = Control.MOUSE_FILTER_STOP
			iscroll.scroll_deadzone = 8 if UiLayout.is_mobile() else 0
		body = _info_body(info)
		if body:
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _info_body(panel: Control = null) -> VBoxContainer:
	if panel == null:
		@warning_ignore("unsafe_cast")
		panel = hud.get_node_or_null("Root/%s" % _INFO_PANEL) as Control
	if panel == null:
		return null
	@warning_ignore("unsafe_cast")
	var nested: VBoxContainer = panel.get_node_or_null("%s/InfoBody" % _INFO_SCROLL) as VBoxContainer
	if nested:
		return nested
	@warning_ignore("unsafe_cast")
	return panel.get_node_or_null("InfoBody") as VBoxContainer


func _info_child(rel: String, panel: Control = null) -> Node:
	var body: VBoxContainer = _info_body(panel)
	if body == null:
		return null
	return body.get_node_or_null(rel)


func _ensure_reserve_grid() -> void:
	var grid: GridContainer = hud.get_node_or_null("Root/%s" % _RESERVE_GRID_PATH) as GridContainer
	if grid == null:
		return
	grid.columns = 4
	while grid.get_child_count() < _EQUIP_INVENTORY_SIZE:
		var cell: PanelContainer = PanelContainer.new()
		cell.name = "Cell%d" % grid.get_child_count()
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.15, 0.45, 0.22, 0.55)
		sb.set_corner_radius_all(2)
		cell.add_theme_stylebox_override("panel", sb)
		grid.add_child(cell)
	while grid.get_child_count() > _EQUIP_INVENTORY_SIZE:
		var tail: Node = grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(tail)
		tail.queue_free()
	_layout_reserve_grid_cells(grid)

func _apply_adaptive_hud_layout() -> void:
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp: Vector2 = UiLayout.viewport_size(root)
	var top_r: HBoxContainer = root.get_node_or_null("TopRight") as HBoxContainer
	if top_r:
		_reorder_top_right_children(top_r)
		@warning_ignore("unsafe_cast")
		var ver: Label = top_r.get_node_or_null("Version") as Label
		if ver:
			ver.size_flags_horizontal = Control.SIZE_SHRINK_END
			ver.clip_text = true
			ver.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			## Cap so version never steals the right-edge buttons.
			var vmax: float = UiLayout.px(96.0 if UiLayout.is_mobile() else 168.0, root)
			ver.custom_minimum_size = Vector2(0, 0)
			ver.size_flags_horizontal = Control.SIZE_SHRINK_END
			if ver.get_minimum_size().x > vmax:
				ver.custom_minimum_size.x = vmax
	## Measure chrome before placing; height grows with RoundBar text, width follows content.
	@warning_ignore("unsafe_cast")
	var round_bar: Control = root.get_node_or_null("RoundBar") as Control
	@warning_ignore("unsafe_cast")
	var round_inner: Control = root.get_node_or_null("RoundBar/RoundInner") as Control
	var rb_ms: Vector2 = _chrome_content_min_size(round_inner if round_inner else round_bar)
	## Panel style margins (styled ~6px design).
	rb_ms += Vector2(float(UiLayout.margin_px(12, root)), float(UiLayout.margin_px(12, root)))
	var tr_ms: Vector2 = _chrome_content_min_size(top_r) if top_r else Vector2(200, 40)
	var pad_x: float = float(UiLayout.margin_px(10, root))
	var pad_y: float = float(UiLayout.margin_px(8, root))
	var top_h: float = clampf(
		maxf(
			UiLayout.top_bar_height_frac(),
			maxf((rb_ms.y + pad_y) / maxf(vp.y, 1.0), (tr_ms.y + pad_y) / maxf(vp.y, 1.0))
		),
		0.05,
		0.12
	)
	var margin_r: float = 0.008
	var tr_w: float = clampf((tr_ms.x + pad_x) / maxf(vp.x, 1.0), 0.14, 0.48)
	var tr_left: float = 1.0 - margin_r - tr_w
	if top_r:
		UiLayout.set_rect_frac(top_r, tr_left, 0.008, 1.0 - margin_r, top_h)
	var rb_w: float = clampf((rb_ms.x + pad_x * 2.0) / maxf(vp.x, 1.0), 0.16, 0.58)
	var gap: float = 0.01
	var max_rb_right: float = tr_left - gap
	var rb_left: float = 0.5 - rb_w * 0.5
	var rb_right: float = rb_left + rb_w
	if rb_right > max_rb_right:
		rb_right = max_rb_right
		rb_left = maxf(0.01, rb_right - rb_w)
	if rb_left < 0.01:
		rb_left = 0.01
		rb_right = minf(max_rb_right, rb_left + rb_w)
	if round_bar:
		UiLayout.set_rect_frac(round_bar, rb_left, 0.008, rb_right, top_h)
	var left_w: float = UiLayout.collapse_strip_frac() if _collapse_left else UiLayout.left_col_width_frac()
	var right_w: float = UiLayout.collapse_strip_frac() if _collapse_right else UiLayout.right_col_width_frac()
	var bottom_h: float = UiLayout.collapse_strip_frac() if _collapse_bottom else UiLayout.bottom_shop_height_frac()
	@warning_ignore("unsafe_cast")
	var left_col: Control = root.get_node_or_null("LeftCol") as Control
	if left_col:
		UiLayout.set_rect_frac(left_col, 0.006, top_h + 0.01, 0.006 + left_w, 1.0 - bottom_h - 0.02)
	@warning_ignore("unsafe_cast")
	var right_col: Control = root.get_node_or_null("RightCol") as Control
	if right_col:
		UiLayout.set_rect_frac(right_col, 1.0 - 0.006 - right_w, top_h + 0.01, 0.994, 1.0 - bottom_h - 0.02)
	@warning_ignore("unsafe_cast")
	var shop_panel: Control = root.get_node_or_null("Shop") as Control
	if shop_panel:
		UiLayout.set_bottom_strip(shop_panel, bottom_h, 0.01, 0.01, 0.008)
	@warning_ignore("unsafe_cast")
	var left_content: Control = root.get_node_or_null("LeftCol/LeftInner/LeftContent") as Control
	if left_content:
		left_content.visible = not _collapse_left
	@warning_ignore("unsafe_cast")
	var right_content: Control = root.get_node_or_null("RightCol/RightInner/RightContent") as Control
	if right_content:
		right_content.visible = not _collapse_right
	@warning_ignore("unsafe_cast")
	var shop_content: Control = root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	if shop_content:
		shop_content.visible = not _collapse_bottom
	@warning_ignore("unsafe_cast")
	var cl: Button = root.get_node_or_null("LeftCol/LeftInner/CollapseLeftBtn") as Button
	if cl:
		cl.text = "▶" if _collapse_left else "◀"
	@warning_ignore("unsafe_cast")
	var cr: Button = root.get_node_or_null("RightCol/RightInner/CollapseRightBtn") as Button
	if cr:
		cr.text = "◀" if _collapse_right else "▶"
	@warning_ignore("unsafe_cast")
	var cb: Button = root.get_node_or_null("Shop/ShopCol/CollapseBottomBtn") as Button
	if cb:
		cb.text = "▲" if _collapse_bottom else "▼"
	@warning_ignore("unsafe_cast")
	var notice: Control = root.get_node_or_null("Notice") as Control
	if notice:
		UiLayout.set_rect_frac(notice, 0.28, 0.4, 0.72, 0.5)
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_info_panel_adaptive_layout(root)


func _apply_info_panel_adaptive_layout(root: Control) -> void:
	## Right column: scale portrait / weapon squares; mobile stacks weapon under title.
	_ensure_side_panel_scrolls()
	@warning_ignore("unsafe_cast")
	var info: PanelContainer = root.get_node_or_null(_INFO_PANEL) as PanelContainer
	@warning_ignore("unsafe_cast")
	var blog: PanelContainer = root.get_node_or_null("RightCol/RightInner/RightContent/BattleLog") as PanelContainer
	var mobile: bool = UiLayout.is_mobile()
	if info:
		info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		info.size_flags_stretch_ratio = 2.6 if mobile else 2.0
		@warning_ignore("unsafe_cast")
		var icon: TextureRect = _info_child("InfoTop/InfoIcon", info) as TextureRect
		if icon:
			var isz: int = UiLayout.px(56 if mobile else 72, root)
			icon.custom_minimum_size = Vector2(isz, isz)
		var info_top: HBoxContainer = _info_child("InfoTop", info) as HBoxContainer
		var body: VBoxContainer = _info_body(info)
		@warning_ignore("unsafe_cast")
		var weapon_col: VBoxContainer = _info_child("InfoTop/InfoWeaponColumn", info) as VBoxContainer
		if weapon_col == null and body:
			@warning_ignore("unsafe_cast")
			weapon_col = body.get_node_or_null("InfoWeaponColumn") as VBoxContainer
		if mobile and info_top and body and weapon_col != null and weapon_col.get_parent() == info_top:
			## Stack: [icon|title] then weapon/drone column full width — avoids HBox overflow.
			info_top.remove_child(weapon_col)
			var insert_at: int = info_top.get_index() + 1
			body.add_child(weapon_col)
			body.move_child(weapon_col, insert_at)
		elif (not mobile) and body and info_top:
			@warning_ignore("unsafe_cast")
			var under_body: VBoxContainer = body.get_node_or_null("InfoWeaponColumn") as VBoxContainer
			if under_body != null and under_body.get_parent() == body:
				body.remove_child(under_body)
				info_top.add_child(under_body)
		var w_parent: Control = null
		if weapon_col:
			w_parent = weapon_col
		elif info_top:
			w_parent = info_top
		if w_parent:
			var w_sq: Vector2 = Vector2(
				UiLayout.px(168 if mobile else 228, root),
				UiLayout.px(120 if mobile else 176, root)
			)
			var d_sq: Vector2 = Vector2(
				UiLayout.px(168 if mobile else 228, root),
				UiLayout.px(96 if mobile else 120, root)
			)
			var icon_sz: int = UiLayout.px(44 if mobile else 56, root)
			var lbl_w: int = UiLayout.px(110 if mobile else 150, root)
			var lbl_h: int = UiLayout.px(56 if mobile else 72, root)
			_resize_info_stat_square(w_parent, "InfoWeaponSquare", w_sq, icon_sz, lbl_w, lbl_h)
			_resize_info_stat_square(w_parent, "InfoDroneSquare", d_sq, icon_sz, lbl_w, lbl_h)
	if blog:
		blog.size_flags_vertical = Control.SIZE_EXPAND_FILL
		blog.size_flags_stretch_ratio = 1.0
		@warning_ignore("unsafe_cast")
		var scroll: ScrollContainer = blog.get_node_or_null("BattleLogInner/BattleLogScroll") as ScrollContainer
		if scroll:
			scroll.custom_minimum_size = Vector2(0, UiLayout.px(56 if mobile else 80, root))
	@warning_ignore("unsafe_cast")
	var cr: Button = root.get_node_or_null("RightCol/RightInner/CollapseRightBtn") as Button
	if cr:
		cr.custom_minimum_size = Vector2(0, UiLayout.px(28, root))


func _resize_info_stat_square(parent: Control, square_name: String, min_size: Vector2, icon_sz: float, lbl_w: float, lbl_h: float) -> void:
	@warning_ignore("unsafe_cast")
	var square: PanelContainer = parent.get_node_or_null(square_name) as PanelContainer
	if square == null:
		return
	square.custom_minimum_size = min_size
	var row: HBoxContainer = square.get_node_or_null("%sRow" % square_name) as HBoxContainer
	if row == null:
		return
	@warning_ignore("unsafe_cast")
	var icon: TextureRect = row.get_node_or_null("%sIcon" % square_name) as TextureRect
	if icon:
		icon.custom_minimum_size = Vector2(icon_sz, icon_sz)
	@warning_ignore("unsafe_cast")
	var lbl: Label = row.get_node_or_null("%sText" % square_name) as Label
	if lbl:
		lbl.custom_minimum_size = Vector2(lbl_w, lbl_h)


func _style_hud_chrome() -> void:
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	for lbl_path: String in [
			"%s/Hp" % _ROUND, "%s/Phase" % _ROUND, "%s/Region" % _ROUND,
			"%s/Placement/TimerCol/Timer" % _ROUND, "%s/Placement/TimerCol/StageHint" % _ROUND,
			"Notice",
			"%s/LevelExp/LEInner/LELabels/Level" % _SHOP_LEFT,
			"%s/LevelExp/LEInner/LELabels/Exp" % _SHOP_LEFT,
			"%s/StatsRow/PopBox/Pop" % _SHOP_MID, "%s/StatsRow/GoldBox/Gold" % _SHOP_MID,
			"TopRight/Version",
			"RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogTitle"]:
		@warning_ignore("unsafe_cast")
		var l: Label = root.get_node_or_null(lbl_path) as Label
		if l:
			var design: int = 22 if "Timer" in lbl_path else (
				32 if "Gold" in lbl_path else (
				26 if "Pop" in lbl_path else (
				22 if "Level" in lbl_path else 15)))
			UiAssets.apply_label_font(l, "Gold" in lbl_path or "Level" in lbl_path, UiLayout.font_size(design, root))
			l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2) if "Gold" in lbl_path else Color(0.95, 0.95, 0.9))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", UiLayout.margin_px(3, root))
	for panel_path: String in ["RoundBar", "LeftCol", "RightCol", "Shop"]:
		@warning_ignore("unsafe_cast")
		var panel: PanelContainer = root.get_node_or_null(panel_path) as PanelContainer
		if panel:
			var sb: StyleBoxFlat = StyleBoxFlat.new()
			sb.bg_color = Color(0.07, 0.09, 0.11, 0.88)
			sb.border_color = Color(0.35, 0.72, 0.85, 0.55)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			sb.set_content_margin_all(UiLayout.margin_px(6, root))
			panel.add_theme_stylebox_override("panel", sb)
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
	@warning_ignore("unsafe_cast")
	var info: PanelContainer = root.get_node_or_null(_INFO_PANEL) as PanelContainer
	if info:
		var sb2: StyleBoxFlat = StyleBoxFlat.new()
		sb2.bg_color = Color(0.10, 0.12, 0.15, 0.0)
		sb2.border_color = Color(0.35, 0.72, 0.85, 0.38)
		sb2.set_border_width_all(1)
		sb2.set_corner_radius_all(6)
		sb2.set_content_margin_all(UiLayout.margin_px(8, root))
		info.add_theme_stylebox_override("panel", sb2)
	@warning_ignore("unsafe_cast")
	var blog: PanelContainer = root.get_node_or_null("RightCol/RightInner/RightContent/BattleLog") as PanelContainer
	if blog:
		var sb3: StyleBoxFlat = StyleBoxFlat.new()
		sb3.bg_color = Color(0.08, 0.12, 0.16, 0.9)
		sb3.set_corner_radius_all(4)
		sb3.set_content_margin_all(UiLayout.margin_px(6, root))
		blog.add_theme_stylebox_override("panel", sb3)
	@warning_ignore("unsafe_cast")
	var skip: Button = root.get_node_or_null("%s/Placement/SkipBtn" % _ROUND) as Button
	if skip:
		UiAssets.apply_button_font(skip, UiLayout.font_size(14, root))
		skip.custom_minimum_size = Vector2(UiLayout.px(72, root), UiLayout.px(36, root))
	for btn_name: String in ["TopRight/PauseBtn", "TopRight/ExitBtn", "TopRight/SpeedBtn",
			"TopRight/CamModeBtn", "TopRight/ScoutIntelBtn",
			"LeftCol/LeftInner/CollapseLeftBtn", "RightCol/RightInner/CollapseRightBtn",
			"Shop/ShopCol/CollapseBottomBtn"]:
		@warning_ignore("unsafe_cast")
		var b: Button = root.get_node_or_null(btn_name) as Button
		if b:
			UiAssets.apply_button_font(b, UiLayout.font_size(13, root))
			var bw: float = 88.0 if ("CamMode" in btn_name or "ScoutIntel" in btn_name) else 56.0
			b.custom_minimum_size = Vector2(UiLayout.px(bw, root), UiLayout.px(28, root))
	_ensure_speed_button(root)
	## Re-fit top chrome after button mins / fonts change.
	_apply_adaptive_hud_layout()

func _ensure_speed_button(root: Node) -> void:
	var top_r: HBoxContainer = root.get_node_or_null("TopRight") as HBoxContainer
	if top_r == null:
		return
	@warning_ignore("unsafe_cast")
	var btn: Button = top_r.get_node_or_null("SpeedBtn") as Button
	if btn == null:
		btn = Button.new()
		btn.name = "SpeedBtn"
		top_r.add_child(btn)
		btn.pressed.connect(_on_speed_pressed)
	_reorder_top_right_children(top_r)
	btn.visible = match_ctrl.stage == MatchController.Stage.BATTLE
	btn.text = match_ctrl.speed_label()
	if GameSession.pending_mode == "nullsec":
		btn.tooltip_text = "战斗倍速（下拉投票）"
	else:
		btn.tooltip_text = "战斗倍速（点按循环）"

func _wire_shop_chrome() -> void:
	var root: Control = hud.get_node_or_null("Root")
	if root == null:
		return
	_ensure_equipment_shop_slots()
	# 按钮素材为横图（约 198×69）；宽度保持原设计，高度按比例，禁止再塞进正方形造成下方空白
	var btn_w: int = UiLayout.px(144 if UiLayout.is_mobile() else 162, root)
	_style_image_button(root.get_node_or_null("%s/LeftBtns/ExpBtn" % _SHOP_LEFT) as Button,
			UiAssets.shop_exp_path(), "购买经验", TypedVariant.as_int(DataStore.economy.get("buy_exp_gold_cost", 4), 0), btn_w)
	_wire_exp_hold(root.get_node_or_null("%s/LeftBtns/ExpBtn" % _SHOP_LEFT) as Button)
	_style_image_button(root.get_node_or_null("%s/LeftBtns/RefreshBtn" % _SHOP_LEFT) as Button,
			UiAssets.shop_refresh_path(), "刷新商店", TypedVariant.as_int(DataStore.economy.get("refresh_cost", 2), 0), btn_w)
	@warning_ignore("unsafe_cast")
	var lock: Button = root.get_node_or_null("%s/StatsRow/LockBtn" % _SHOP_MID) as Button
	if lock:
		var t: Texture2D = UiAssets.tex(UiAssets.ICON_LOCK)
		if t:
			lock.icon = t
			lock.expand_icon = true
		lock.text = ""
		UiAssets.apply_button_font(lock, UiLayout.font_size(14, root))
		lock.custom_minimum_size = Vector2(UiLayout.px(52, root), UiLayout.px(44, root))
	_ensure_meta_icon(root.get_node_or_null("%s/StatsRow/GoldBox" % _SHOP_MID) as HBoxContainer, "Gold", UiAssets.ICON_MONEY, 36)
	_ensure_meta_icon(root.get_node_or_null("%s/StatsRow/PopBox" % _SHOP_MID) as HBoxContainer, "Pop", UiAssets.ICON_POP, 36)
	var btn_h: float = btn_w * (69.0 / 198.0)  # 与素材比例一致
	@warning_ignore("unsafe_cast")
	var le: PanelContainer = root.get_node_or_null("%s/LevelExp" % _SHOP_LEFT) as PanelContainer
	if le:
		# 等级框贴合内容，高度不超过按钮行
		var le_h: float = minf(UiLayout.px(64 if UiLayout.is_mobile() else 68, root), ceilf(btn_h) + float(UiLayout.margin_px(8, root)))
		le.custom_minimum_size = Vector2(UiLayout.px(208, root), le_h)
		le.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		@warning_ignore("unsafe_cast")
		var le_inner: VBoxContainer = le.get_node_or_null("LEInner") as VBoxContainer
		if le_inner:
			le_inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			le_inner.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		var le_sb: StyleBoxFlat = StyleBoxFlat.new()
		le_sb.bg_color = Color(0.05, 0.08, 0.1, 0.75)
		le_sb.border_color = Color(0.25, 0.55, 0.7, 0.55)
		le_sb.set_border_width_all(1)
		le_sb.set_corner_radius_all(4)
		le_sb.content_margin_left = UiLayout.margin_px(8, root)
		le_sb.content_margin_right = UiLayout.margin_px(8, root)
		le_sb.content_margin_top = UiLayout.margin_px(4, root)
		le_sb.content_margin_bottom = UiLayout.margin_px(4, root)
		le.add_theme_stylebox_override("panel", le_sb)
	@warning_ignore("unsafe_cast")
	var left_ctrl: Control = root.get_node_or_null(_SHOP_LEFT) as Control
	if left_ctrl:
		# 宽度保留；高度跟内容走，禁止再锁 162 把 MetaRow 撑出空白带
		left_ctrl.custom_minimum_size = Vector2(UiLayout.px(560, root), 0)
		left_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if left_ctrl is BoxContainer:
			(left_ctrl as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	@warning_ignore("unsafe_cast")
	var left_btns: Control = root.get_node_or_null("%s/LeftBtns" % _SHOP_LEFT) as Control
	if left_btns:
		left_btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var seg_row: HBoxContainer = root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as HBoxContainer
	if seg_row:
		seg_row.custom_minimum_size = Vector2(0, UiLayout.px(18, root))
		seg_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var meta_row: HBoxContainer = root.get_node_or_null(_SHOP_META) as HBoxContainer
	if meta_row:
		meta_row.alignment = BoxContainer.ALIGNMENT_CENTER
		meta_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		meta_row.add_theme_constant_override("separation", UiLayout.margin_px(10, root))
	@warning_ignore("unsafe_cast")
	var shop_content: VBoxContainer = root.get_node_or_null("Shop/ShopCol/ShopContent") as VBoxContainer
	if shop_content:
		shop_content.add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	var stats: HBoxContainer = root.get_node_or_null("%s/StatsRow" % _SHOP_MID) as HBoxContainer
	if stats:
		stats.alignment = BoxContainer.ALIGNMENT_CENTER
		stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	@warning_ignore("unsafe_cast")
	var sell: PanelContainer = root.get_node_or_null("%s/SellZone" % _SHOP_INNER) as PanelContainer
	if sell:
		sell.custom_minimum_size = Vector2(UiLayout.px(120, root), 0)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.22, 0.25, 0.92)
		sb.border_color = Color(0.4, 0.75, 0.9, 0.7)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sell.add_theme_stylebox_override("panel", sb)

func _ensure_meta_icon(box: HBoxContainer, for_name: String, tex_path: String, design_px: int = 20) -> void:
	if box == null:
		return
	for c: Node in box.get_children():
		if c is TextureRect and c.has_meta("meta_icon_for") and str(c.get_meta("meta_icon_for")) == for_name:
			var existing_icon_sz: float = UiLayout.px(float(design_px), box)
			(c as TextureRect).custom_minimum_size = Vector2(existing_icon_sz, existing_icon_sz)
			return
	var icon: TextureRect = TextureRect.new()
	icon.set_meta("meta_icon_for", for_name)
	var new_icon_sz: float = UiLayout.px(float(design_px), box)
	icon.custom_minimum_size = Vector2(new_icon_sz, new_icon_sz)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t: Texture2D = UiAssets.tex(tex_path)
	if t:
		icon.texture = t
	box.add_child(icon)
	box.move_child(icon, 0)

func _refresh_exp_segments(root: Node) -> void:
	var row: HBoxContainer = root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as HBoxContainer
	if row == null:
		return
	for c: Node in row.get_children():
		row.remove_child(c)
		c.free()
	var demand: int = maxi(1, match_ctrl.up_level_demand)
	var exp_now: int = clampi(match_ctrl.player_exp, 0, demand)
	var seg_h: float = UiLayout.px(18, row)
	## Cap visual segments so high-level demands (e.g. 124 at Lv16) stay readable.
	var slots: int = demand if demand <= 16 else 16
	var filled: int = exp_now if demand <= 16 else roundi(float(exp_now) / float(demand) * float(slots))
	row.add_theme_constant_override("separation", UiLayout.margin_px(4, row))
	row.custom_minimum_size = Vector2(0, seg_h)
	for i: int in range(slots):
		var cell: PanelContainer = PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.custom_minimum_size = Vector2(UiLayout.px(10, row), seg_h)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
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
	var legacy: ProgressBar = root.get_node_or_null("%s/LevelExp/LEInner/ExpBar" % _SHOP_LEFT) as ProgressBar
	if legacy:
		legacy.visible = false

func _style_image_button(btn: Button, tex_path: String, title: String, cost: int, width_px: float = -1.0) -> void:
	if btn == null:
		return
	# Image-only: art fills the control; cost stays in tooltip / accessibility.
	btn.text = ""
	btn.tooltip_text = "%s  %d" % [title, cost]
	var w: float = width_px if width_px > 0.0 else UiLayout.px(72 if UiLayout.is_mobile() else 88, btn)
	var h: float = w
	var t: Texture2D = UiAssets.tex(tex_path)
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
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("disabled", empty)

func show_notice(text: String) -> void:
	AdminBus.request(&"ui.notice", {"text": text})
	_append_battle_log(text)
	@warning_ignore("unsafe_cast")
	var lbl: Label = hud.get_node_or_null("Root/Notice") as Label
	if lbl:
		lbl.text = text
		lbl.visible = true
		get_tree().create_timer(2.0).timeout.connect(func() -> void: if lbl: lbl.visible = false)

func append_battle_log(text: String) -> void:
	## Battle-log only (no floating notice) — used by AI sell / combat breadcrumbs.
	_append_battle_log(text)

func on_ship_sold(gold: int) -> void:
	match_ctrl.add_gold(gold)
	show_notice("出售获得 %d PLEX" % gold)
	board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	_refresh_hud()

## CAPITAL_AND_CYNO §6.1: cyno hull could not return to hangar → auto-sold.
func on_capital_hangar_full_autosell(gold: int, team: int) -> void:
	if team == ShipUnit.TEAM_PLAYER:
		match_ctrl.add_gold(gold)
		show_notice("因为无法回归旗舰被自动售卖，你获得了%d黄" % gold)
		board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
		_refresh_hud()
		return
	if team == ShipUnit.TEAM_AI and ai != null and ai.has_method("add_gold"):
		ai.add_gold(gold)
		board.recalculate_fetters(ShipUnit.TEAM_AI)

func rebuild_all_ship_health_bars() -> void:
	if board == null:
		return
	for s: ShipUnit in board.all_ships():
		if s != null and is_instance_valid(s) and s.has_method("rebuild_health_bar"):
			s.rebuild_health_bar()

func _refresh_hud() -> void:
	var root: Control = hud.get_node_or_null("Root")
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
	@warning_ignore("unsafe_cast")
	var lock: Button = root.get_node_or_null("%s/StatsRow/LockBtn" % _SHOP_MID) as Button
	if lock:
		lock.set_pressed_no_signal(match_ctrl.shop_locked)
	var stage_name: String = "准备" if match_ctrl.stage == MatchController.Stage.PREPARE else ("战斗" if match_ctrl.stage == MatchController.Stage.BATTLE else "结束")
	var ttext: String = "倒计时"
	if match_ctrl.stage == MatchController.Stage.PREPARE:
		var net_hud: NullsecNetSession = _nullsec_net_session()
		if not match_ctrl.prepare_clock_armed:
			## MATCH_FLOW: spend-gate copy only on R1; later rounds wait battle-sync then countdown.
			if match_ctrl.battle_game_stage_count == 0:
				ttext = "等待首次花费"
				stage_name = "准备·待开钟"
			else:
				ttext = "等待其他席结束战斗"
				stage_name = "准备"
				if net_hud != null and net_hud.needs_stage_barrier():
					ttext = net_hud.barrier_wait_hud_text("battle_done")
		elif match_ctrl.is_prepare_peer_hold():
			ttext = "等待其他玩家"
			stage_name = "准备"
			if net_hud != null and net_hud.needs_stage_barrier():
				ttext = net_hud.barrier_wait_hud_text("prep_done")
		else:
			ttext = "%.0f" % match_ctrl.prepare_remaining()
	elif match_ctrl.stage == MatchController.Stage.BATTLE:
		ttext = "%.0f" % match_ctrl.battle_remaining()
	_set_label(root, "%s/Placement/TimerCol/Timer" % _ROUND, ttext)
	_set_label(root, "%s/Placement/TimerCol/StageHint" % _ROUND, stage_name)
	@warning_ignore("unsafe_cast")
	var speed_btn: Button = root.get_node_or_null("TopRight/SpeedBtn") as Button
	if speed_btn:
		speed_btn.visible = match_ctrl.stage == MatchController.Stage.BATTLE
		speed_btn.text = match_ctrl.speed_label()
	@warning_ignore("unsafe_cast")
	var skip: Button = root.get_node_or_null("%s/Placement/SkipBtn" % _ROUND) as Button
	if skip:
		## Nullsec multiplayer: never show skip (MATCH_FLOW §2.1).
		var show_skip: bool = match_ctrl.stage == MatchController.Stage.PREPARE \
				and GameSession.pending_mode != "nullsec"
		skip.visible = show_skip
		skip.disabled = not show_skip
	_apply_shop_interactable()
	_refresh_fetter_ui(root)
	_refresh_equipment_inventory_ui()
	@warning_ignore("unsafe_cast")
	var ver: Label = root.get_node_or_null("TopRight/Version") as Label
	if ver:
		ver.text = "壳 %s | 热更 %s" % [str(ProjectSettings.get_setting("application/config/version", "dev")), DataStore.content_version]
	## RoundBar / TopRight widths track live label lengths (HP / phase / timer / ver).
	_apply_adaptive_hud_layout()
	_refresh_open_ship_info()

func _refresh_open_ship_info() -> void:
	## Keep InfoPanel in sync after star merge / equip / HUD refresh (UI_AND_SHELL §2.5).
	## is_instance_valid first — avoid null-compare / typed assign on freed ShipUnit.
	if not is_instance_valid(_info_ship):
		_hide_ship_info()
		return
	if _info_ship.is_destroyed:
		_hide_ship_info()
		return
	_show_ship_info(_info_ship)

func _apply_shop_interactable() -> void:
	## Shop stays interactive in Prepare and Battle (no grey-lock).
	var root: Control = hud.get_node_or_null("Root")
	if root == null:
		return
	for path: String in [
			"%s/LeftBtns/ExpBtn" % _SHOP_LEFT,
			"%s/LeftBtns/RefreshBtn" % _SHOP_LEFT,
			"%s/StatsRow/LockBtn" % _SHOP_MID]:
		@warning_ignore("unsafe_cast")
		var b: Button = root.get_node_or_null(path) as Button
		if b:
			b.disabled = false
			b.modulate = Color(1, 1, 1, 1)
	@warning_ignore("unsafe_cast")
	var slots: Control = root.get_node_or_null(_SHOP_SLOTS) as Control
	if slots:
		slots.modulate = Color(1, 1, 1, 1)
		for c: Node in slots.get_children():
			_set_shop_card_interactable(c, true)

func _set_shop_card_interactable(card: Node, enabled: bool) -> void:
	if card == null:
		return
	for child: Node in card.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not enabled
			(child as BaseButton).mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		_set_shop_card_interactable(child, enabled)
func _refresh_fetter_ui(root: Node) -> void:
	_ensure_side_panel_scrolls()
	@warning_ignore("unsafe_cast")
	var side: VBoxContainer = root.get_node_or_null(_BONUS) as VBoxContainer
	if side == null:
		@warning_ignore("unsafe_cast")
		side = root.get_node_or_null(_BONUS_FALLBACK) as VBoxContainer
	if side == null:
		return
	@warning_ignore("unsafe_cast")
	var list: VBoxContainer = side.get_node_or_null("FetterList") as VBoxContainer
	if list == null:
		@warning_ignore("unsafe_cast")
		var old: Label = side.get_node_or_null("Fetters") as Label
		if old:
			old.visible = false
		list = VBoxContainer.new()
		list.name = "FetterList"
		list.add_theme_constant_override("separation", 6)
		side.add_child(list)
	for c: Node in list.get_children():
		c.queue_free()
	var fetters: Array = board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	for a_v: Variant in fetters:
		var a: Dictionary = TypedVariant.as_dict(a_v)
		var fid: String = str(a.get("fetter_id", ""))
		var fdata: Dictionary = DataStore.fetters.get(fid, {})
		var fname: String = str(fdata.get("name", fid))
		var count: int = TypedVariant.as_int(a.get("count", 0), 0)
		var eff: Dictionary = a.get("effect", {})
		var need: int = TypedVariant.as_int(eff.get("champion_count", 0), 0)
		var is_meta: bool = TypedVariant.as_bool(a.get("meta", false), false)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(UiLayout.px(26, list), UiLayout.px(26, list))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex: Texture2D = UiAssets.fetter_icon(fid, fname)
		if tex:
			icon.texture = tex
		row.add_child(icon)
		var col: VBoxContainer = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		var lab: Label = Label.new()
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
			for e: Variant in TypedVariant.as_array(fdata.get("effects", [])):
				if typeof(e) == TYPE_DICTIONARY:
					effect_lines.append(e)
		else:
			effect_lines.append(eff)
		for e: Variant in effect_lines:
			var eff_txt: String = UiAssets.fetter_effect_text(TypedVariant.as_dict(e))
			if eff_txt == "":
				continue
			var elab: Label = Label.new()
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
	@warning_ignore("unsafe_cast")
	var l: Label = root.get_node_or_null(path) as Label
	if l:
		l.text = text

func _refresh_shop_ui() -> void:
	var box: HBoxContainer = hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as HBoxContainer
	if box == null:
		return
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c: Node in box.get_children():
		c.queue_free()
	var slot_count: int = maxi(1, shop.slots.size())
	var card_size: Vector2 = _shop_card_size(slot_count, box)
	for i: int in range(shop.slots.size()):
		var slot: Dictionary = shop.slots[i]
		var sid: int = TypedVariant.as_int(slot.get("ship_id", 0), 0)
		var ship: Dictionary = DataStore.get_ship(sid)
		var purchased: bool = TypedVariant.as_bool(slot.get("purchased", false), false)
		var ship_name: String = str(ship.get("name", "?"))
		var cost: int = TypedVariant.as_int(ship.get("cost", 0), 0)
		var card: Control = _make_shop_card(ship_name, ship, purchased, cost, i, card_size)
		box.add_child(card)
	if not _dragging_sell_ui:
		_set_sell_mode(false)
	_apply_shop_interactable()
	_refresh_equipment_shop_ui()
	_refresh_equipment_inventory_ui()

func _layout_reserve_grid_cells(grid: GridContainer) -> void:
	if grid == null:
		return
	var host: Control = grid.get_parent_control()
	var avail_w: float = grid.size.x
	if avail_w < 8.0 and host:
		avail_w = host.size.x
	if avail_w < 8.0:
		avail_w = UiLayout.px(160.0, grid)
	var h_sep: float = float(grid.get_theme_constant(&"h_separation"))
	var v_sep: float = float(grid.get_theme_constant(&"v_separation"))
	if h_sep <= 0.0:
		h_sep = 4.0
	if v_sep <= 0.0:
		v_sep = 4.0
	## Square cells from full left-column width (UI_AND_SHELL 左下预留).
	var cell: float = (avail_w - h_sep * 3.0) / 4.0
	cell = clampf(cell, UiLayout.px(20.0, grid), UiLayout.px(160.0, grid))
	var grid_h: float = cell * 4.0 + v_sep * 3.0
	grid.custom_minimum_size = Vector2(avail_w, grid_h)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Do not EXPAND cells — stretch would break the square aspect.
	for c: Node in grid.get_children():
		if c is Control:
			var cell_ctrl: Control = c as Control
			cell_ctrl.custom_minimum_size = Vector2(cell, cell)
			cell_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cell_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ensure_equipment_shop_slots() -> void:
	var root: Control = hud.get_node_or_null("Root")
	if root == null:
		return
	var left_btns: HBoxContainer = root.get_node_or_null("%s/LeftBtns" % _SHOP_LEFT) as HBoxContainer
	if left_btns == null:
		return
	var box: HBoxContainer = left_btns.get_node_or_null("EquipmentSlots") as HBoxContainer
	if box == null:
		box = HBoxContainer.new()
		box.name = "EquipmentSlots"
		box.add_theme_constant_override("separation", UiLayout.margin_px(4, left_btns))
		left_btns.add_child(box)
		left_btns.move_child(box, left_btns.get_child_count())


func _refresh_equipment_shop_ui() -> void:
	_ensure_equipment_shop_slots()
	var root: Control = hud.get_node_or_null("Root")
	if root == null or shop == null:
		return
	var box: HBoxContainer = root.get_node_or_null(_SHOP_EQUIP_SLOTS) as HBoxContainer
	if box == null:
		return
	for c: Node in box.get_children():
		c.queue_free()
	if shop.equipment_slots.is_empty() and shop.has_method("ensure_equipment_slots"):
		shop.ensure_equipment_slots()
	var slot_sz: Vector2 = Vector2(
		UiLayout.px(44 if UiLayout.is_mobile() else 48, box),
		UiLayout.px(44 if UiLayout.is_mobile() else 48, box)
	)
	for i: int in range(shop.equipment_slots.size()):
		var slot: Dictionary = shop.equipment_slots[i]
		var item_id: String = str(slot.get("id", ""))
		var purchased: bool = TypedVariant.as_bool(slot.get("purchased", false), false)
		var mod: Dictionary = DataStore.get_function_module(item_id) if item_id != "" else {}
		box.add_child(_make_equipment_shop_card(i, mod, purchased, slot_sz))


func _make_equipment_shop_card(idx: int, mod: Dictionary, purchased: bool, slot_sz: Vector2) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = slot_sz
	var outer: StyleBoxFlat = StyleBoxFlat.new()
	outer.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	outer.border_color = Color(0.35, 0.62, 0.78, 0.9)
	outer.set_border_width_all(1)
	outer.set_corner_radius_all(4)
	outer.set_content_margin_all(UiLayout.margin_px(2, card))
	card.add_theme_stylebox_override("panel", outer)
	if purchased or mod.is_empty():
		var ph: Label = Label.new()
		ph.text = "已购" if purchased else ""
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		UiAssets.apply_label_font(ph, false, UiLayout.font_size(11, card))
		card.add_child(ph)
		return card
	@warning_ignore("unsafe_method_access")
	var inner: Control = _EQUIP_ICON_VIEW.make_icon_cell(
		Vector2(slot_sz.x - UiLayout.margin_px(4, card), slot_sz.y - UiLayout.margin_px(4, card)),
		mod,
		card
	)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(inner)
	var cost: int = TypedVariant.as_int(mod.get("cost", 10), 0)
	if not TypedVariant.as_bool(mod.get("implant", false), false):
		var cost_l: Label = Label.new()
		cost_l.text = str(cost)
		cost_l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		cost_l.offset_top = -UiLayout.px(14, card)
		cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiAssets.apply_label_font(cost_l, false, UiLayout.font_size(11, card))
		cost_l.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
		card.add_child(cost_l)
	var hit: Button = Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var item_id: String = str(mod.get("id", ""))
	if UiLayout.is_mobile():
		hit.gui_input.connect(func(ev: InputEvent) -> void: _equipment_shop_gui_input(ev, idx, item_id, hit))
	else:
		hit.pressed.connect(func() -> void:
			shop.try_buy_equipment(idx)
			_refresh_shop_ui()
			_refresh_hud()
		)
		hit.set_meta("equip_detail_hover", true)
		hit.mouse_entered.connect(func() -> void: _show_equipment_detail(item_id, true))
		hit.mouse_exited.connect(func() -> void: _schedule_hide_equipment_detail())
		hit.tree_exiting.connect(func() -> void: _schedule_hide_equipment_detail())
	card.add_child(hit)
	return card


func _refresh_equipment_inventory_ui() -> void:
	_ensure_reserve_grid()
	var grid: GridContainer = hud.get_node_or_null("Root/%s" % _RESERVE_GRID_PATH) as GridContainer
	if grid == null or match_ctrl == null:
		return
	_layout_reserve_grid_cells(grid)
	match_ctrl.ensure_equipment_inventory_size()
	var parts: Array = []
	for i: int in range(_EQUIP_INVENTORY_SIZE):
		parts.append(str(match_ctrl.equipment_inventory[i]).strip_edges())
	var sz: Vector2 = Vector2.ZERO
	if grid.get_child_count() > 0:
		@warning_ignore("unsafe_cast")
		var cell0: Control = grid.get_child(0) as Control
		if cell0:
			sz = cell0.custom_minimum_size
	var sig: String = "%s@%.1f,%.1f" % ["|".join(parts), sz.x, sz.y]
	## Skip rebuild when unchanged — freeing hovered EquipHit skips mouse_exited and sticks the tooltip.
	if sig == _equip_inv_ui_sig and grid.get_child_count() >= _EQUIP_INVENTORY_SIZE:
		return
	_equip_inv_ui_sig = sig
	for i: int in range(_EQUIP_INVENTORY_SIZE):
		@warning_ignore("unsafe_cast")
		var cell: PanelContainer = grid.get_child(i) as PanelContainer
		if cell == null:
			continue
		for c: Node in cell.get_children():
			c.queue_free()
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var item_id: String = str(match_ctrl.equipment_inventory[i]).strip_edges()
		if item_id == "":
			cell.tooltip_text = ""
			continue
		var mod: Dictionary = DataStore.get_function_module(item_id)
		if mod.is_empty():
			continue
		var inner_sz: Vector2 = cell.custom_minimum_size - Vector2(4, 4)
		if inner_sz.x < 8.0 or inner_sz.y < 8.0:
			inner_sz = Vector2(UiLayout.px(28, cell), UiLayout.px(28, cell))
		@warning_ignore("unsafe_method_access")
		var icon: Control = _EQUIP_ICON_VIEW.make_icon_cell(inner_sz, mod, cell)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 2
		icon.offset_top = 2
		icon.offset_right = -2
		icon.offset_bottom = -2
		cell.add_child(icon)
		var hit: Control = Control.new()
		hit.name = "EquipHit"
		hit.set_meta("equip_detail_hover", true)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.gui_input.connect(func(ev: InputEvent) -> void: _equipment_inventory_gui_input(ev, i, item_id, hit))
		hit.mouse_entered.connect(func() -> void: _show_equipment_detail(item_id, true))
		hit.mouse_exited.connect(func() -> void: _schedule_hide_equipment_detail())
		hit.tree_exiting.connect(func() -> void: _schedule_hide_equipment_detail())
		cell.add_child(hit)


var _equip_detail_hide_gen: int = 0

func _schedule_hide_equipment_detail() -> void:
	_equip_detail_hide_gen += 1
	var gen: int = _equip_detail_hide_gen
	get_tree().create_timer(0.08).timeout.connect(func() -> void:
		if gen != _equip_detail_hide_gen:
			return
		if _equip_detail_from_hover and _pointer_over_equipment_detail_context():
			return
		_hide_equipment_detail()
	)


func _tick_equipment_detail_hover() -> void:
	if _equip_detail_panel == null or not is_instance_valid(_equip_detail_panel):
		return
	if not _equip_detail_panel.visible or not _equip_detail_from_hover:
		return
	if UiLayout.is_mobile():
		return
	## Keep open while pressing/dragging an equipment icon.
	if _equip_drag_source != "":
		return
	if _pointer_over_equipment_detail_context():
		return
	_hide_equipment_detail()


func _pointer_over_equipment_detail_context() -> bool:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	if _equip_detail_panel and is_instance_valid(_equip_detail_panel) and _equip_detail_panel.visible:
		if _equip_detail_panel.get_global_rect().grow(4.0).has_point(mouse):
			return true
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var c: Control = hovered
	while c != null:
		if c.has_meta("equip_detail_hover"):
			return true
		@warning_ignore("unsafe_cast")
		c = c.get_parent() as Control
	if _equip_detail_fit_ship != null and is_instance_valid(_equip_detail_fit_ship) and _equip_detail_fit_slot >= 0 \
			and camera != null:
		var hb: Node = _equip_detail_fit_ship.get_health_bar()
		if hb != null and hb.has_method("fit_slot_screen_distance"):
			var d: float = TypedVariant.as_float(hb.call("fit_slot_screen_distance", camera, mouse, _equip_detail_fit_slot), 999.0)
			if d < float(UiLayout.px(36, self)):
				return true
	return false


func _ensure_equipment_detail_panel() -> PanelContainer:
	if _equip_detail_panel and is_instance_valid(_equip_detail_panel):
		return _equip_detail_panel
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return null
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "EquipmentDetail"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 90
	## Float near cursor — never fill HUD Root.
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.96)
	sb.border_color = Color(0.45, 0.72, 0.88, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(UiLayout.margin_px(10, root))
	panel.add_theme_stylebox_override("panel", sb)
	var body: VBoxContainer = VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	panel.add_child(body)
	root.add_child(panel)
	_equip_detail_panel = panel
	return panel


func _show_equipment_detail(item_id: String, from_hover: bool = true) -> void:
	if item_id.strip_edges() == "":
		return
	_equip_detail_hide_gen += 1
	_equip_detail_from_hover = from_hover
	if from_hover:
		_equip_detail_fit_ship = null
		_equip_detail_fit_slot = -1
	var mod: Dictionary = DataStore.get_function_module(item_id)
	if mod.is_empty():
		return
	var panel: Control = _ensure_equipment_detail_panel()
	if panel == null:
		return
	@warning_ignore("unsafe_cast")
	var body: VBoxContainer = panel.get_node_or_null("Body") as VBoxContainer
	if body == null:
		return
	while body.get_child_count() > 0:
		var old: Node = body.get_child(0)
		body.remove_child(old)
		old.free()
	var w: float = float(UiLayout.px(300, panel))
	var pad: float = float(UiLayout.margin_px(20, panel))
	var text_w: float = maxf(80.0, w - pad)
	@warning_ignore("unsafe_method_access")
	for line_v: Variant in _EQUIP_ICON_VIEW.detail_lines(mod):
		var lab: Label = Label.new()
		lab.text = str(line_v).strip_edges()
		if lab.text == "":
			continue
		## Autowrap without an X min-size expands to the full HUD → fullscreen empty panel.
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(text_w, 0)
		lab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiAssets.apply_label_font(lab, false, UiLayout.font_size(13, panel))
		lab.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
		body.add_child(lab)
	panel.visible = true
	panel.custom_minimum_size = Vector2(w, 0)
	panel.reset_size()
	var min_sz: Vector2 = panel.get_combined_minimum_size()
	var h: float = maxf(min_sz.y, float(UiLayout.px(48, panel)))
	panel.size = Vector2(maxf(w, min_sz.x), h)
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var x: float = clampf(mouse.x + float(UiLayout.px(16, panel)), 8.0, maxf(8.0, vp.x - panel.size.x - 8.0))
	var y: float = clampf(mouse.y + float(UiLayout.px(12, panel)), 8.0, maxf(8.0, vp.y - panel.size.y - 8.0))
	panel.position = Vector2(x, y)


func _hide_equipment_detail() -> void:
	_equip_detail_from_hover = false
	_equip_detail_fit_ship = null
	_equip_detail_fit_slot = -1
	if _equip_detail_panel and is_instance_valid(_equip_detail_panel):
		_equip_detail_panel.visible = false


func _show_equipment_detail_for_fit(item_id: String, ship: ShipUnit, fit_slot: int, from_hover: bool = true) -> void:
	_show_equipment_detail(item_id, from_hover)
	_equip_detail_fit_ship = ship
	_equip_detail_fit_slot = fit_slot
	_equip_detail_from_hover = from_hover


func _equipment_shop_gui_input(ev: InputEvent, idx: int, item_id: String, from: Control) -> void:
	if not UiLayout.is_mobile():
		return
	var screen: Vector2 = _shop_event_screen(ev, from)
	if ev is InputEventScreenTouch:
		var st: InputEventScreenTouch = ev as InputEventScreenTouch
		if st.pressed:
			_begin_equipment_shop_drag(idx, item_id, screen)
			from.accept_event()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.pressed:
			_begin_equipment_shop_drag(idx, item_id, screen)
			from.accept_event()


func _equipment_inventory_gui_input(ev: InputEvent, inv_idx: int, item_id: String, from: Control) -> void:
	var screen: Vector2 = _shop_event_screen(ev, from)
	if ev is InputEventScreenTouch:
		var st: InputEventScreenTouch = ev as InputEventScreenTouch
		if st.pressed:
			_begin_equipment_inventory_drag(inv_idx, item_id, screen)
			from.accept_event()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.pressed:
			_begin_equipment_inventory_drag(inv_idx, item_id, screen)
			from.accept_event()


func _begin_equipment_shop_drag(idx: int, item_id: String, screen: Vector2) -> void:
	_equip_drag_source = "shop"
	_equip_drag_shop_idx = idx
	_equip_drag_inv_idx = -1
	_equip_drag_ship = null
	_equip_drag_fit_slot = -1
	_equip_drag_item_id = item_id
	_equip_drag_active = false
	_equip_press_screen = screen
	_show_equipment_detail(item_id)


func _begin_equipment_inventory_drag(inv_idx: int, item_id: String, screen: Vector2) -> void:
	## Bag drag allowed in Prepare and Battle (bag synth / rearrange). Ship fit stays Prepare-gated on drop.
	_equip_drag_source = "inventory"
	_equip_drag_inv_idx = inv_idx
	_equip_drag_shop_idx = -1
	_equip_drag_ship = null
	_equip_drag_fit_slot = -1
	_equip_drag_item_id = item_id
	_equip_drag_active = false
	_equip_press_screen = screen
	_show_equipment_detail(item_id)


## Prepare: press on a filled health-bar fit slot → drag unequip (EQUIPMENT.md).
func try_begin_fit_unequip_at_screen(screen: Vector2) -> bool:
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.PREPARE:
		return false
	if camera == null or board == null:
		return false
	var best_ship: ShipUnit = null
	var best_slot: int = -1
	var best_d: float = 1.0e9
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		if s.team_id != ShipUnit.TEAM_PLAYER or s.is_protect_target:
			continue
		if not board.is_board_piece(s):
			continue
		var hb: Node = s.get_health_bar()
		if hb == null or not hb.has_method("pick_fit_slot_at_screen"):
			continue
		var slot_i: int = TypedVariant.as_int(hb.call("pick_fit_slot_at_screen", camera, screen), -1)
		if slot_i < 0:
			continue
		## Prefer nearer screen hit if multiple overlap.
		var d: float = 0.0
		if hb.has_method("fit_slot_screen_distance"):
			d = TypedVariant.as_float(hb.call("fit_slot_screen_distance", camera, screen, slot_i), 999.0)
		if d < best_d:
			best_d = d
			best_ship = s
			best_slot = slot_i
	if best_ship == null or best_slot < 0:
		return false
	var fit: Array = best_ship.get_function_fit()
	if best_slot >= fit.size():
		return false
	var entry: Dictionary = fit[best_slot]
	var item_id: String = str(entry.get("id", "")).strip_edges()
	if item_id == "":
		return false
	## Press only arms unequip; module leaves the ship once drag crosses threshold.
	_equip_drag_source = "fit"
	_equip_drag_ship = best_ship
	_equip_drag_fit_slot = best_slot
	_equip_drag_item_id = item_id
	_equip_drag_shop_idx = -1
	_equip_drag_inv_idx = -1
	_equip_drag_active = false
	_equip_press_screen = screen
	_show_equipment_detail_for_fit(item_id, best_ship, best_slot, true)
	return true


func _update_equipment_drag(screen: Vector2) -> void:
	if _equip_drag_source == "":
		return
	if not _equip_drag_active and screen.distance_to(_equip_press_screen) >= _EQUIP_DRAG_THRESHOLD_PX:
		if _equip_drag_source == "fit":
			if not _commit_fit_unequip_for_drag():
				_clear_equipment_drag()
				return
		_equip_drag_active = true
		_ensure_equipment_ghost(_current_equip_drag_item_id())
		## Inventory / fitted gear: show SellZone like ship drag (EQUIPMENT §1).
		if _equip_drag_source == "inventory" or _equip_drag_source == "fit":
			_dragging_sell_ui = true
			_set_sell_mode(true, DataStore.function_module_sell_price(_current_equip_drag_item_id()))
	if _equip_drag_active:
		_move_equipment_ghost(screen)


func _commit_fit_unequip_for_drag() -> bool:
	if _equip_drag_ship == null or not is_instance_valid(_equip_drag_ship):
		return false
	var slot_i: int = _equip_drag_fit_slot
	var expect: String = _equip_drag_item_id
	var fit: Array = _equip_drag_ship.get_function_fit()
	if slot_i < 0 or slot_i >= fit.size():
		## Slot may have shifted — find by id.
		slot_i = -1
		for i: int in range(fit.size()):
			if str(TypedVariant.as_dict(fit[i]).get("id", "")) == expect:
				slot_i = i
				break
	if slot_i < 0:
		return false
	var removed: String = _equip_drag_ship.unequip_function_at(slot_i)
	if removed == "":
		return false
	_equip_drag_item_id = removed
	_equip_drag_fit_slot = slot_i
	if _info_ship == _equip_drag_ship:
		_show_ship_info(_equip_drag_ship)
	return true


func _end_equipment_drag(screen: Vector2) -> void:
	if _equip_drag_source == "":
		return
	var was_drag: bool = _equip_drag_active
	var source: String = _equip_drag_source
	var shop_idx: int = _equip_drag_shop_idx
	var inv_idx: int = _equip_drag_inv_idx
	var fit_item: String = _equip_drag_item_id
	var fit_ship: ShipUnit = _equip_drag_ship
	var fit_slot: int = _equip_drag_fit_slot
	var fit_was_active: bool = _equip_drag_active
	var sell_drop: bool = was_drag and (source == "inventory" or source == "fit") and _equip_screen_in_sell_zone(screen)
	_clear_equipment_drag()
	if source == "fit":
		if not fit_was_active:
			## Short click on fitted module — detail only (already shown on press).
			if fit_item != "":
				_show_equipment_detail_for_fit(fit_item, fit_ship, fit_slot, true)
			return
		if sell_drop:
			_credit_equipment_sell(fit_item)
			return
		_finish_fit_unequip_drop(screen, fit_item, fit_ship)
		return
	if not was_drag:
		if source == "shop" and shop_idx >= 0:
			var sid: String = str(TypedVariant.as_dict(shop.equipment_slots[shop_idx]).get("id", "")) if shop_idx < shop.equipment_slots.size() else ""
			if sid != "":
				_show_equipment_detail(sid)
		return
	if source == "shop" and shop_idx >= 0:
		if _pick_reserve_cell_at_screen(screen) >= 0:
			shop.try_buy_equipment(shop_idx)
			_refresh_shop_ui()
			_refresh_hud()
		elif _try_drop_equipment_on_ship(screen, "", true, shop_idx):
			pass
		else:
			show_notice("拖到左侧背包或舰船来购买")
	elif source == "inventory" and inv_idx >= 0:
		if sell_drop:
			match_ctrl.ensure_equipment_inventory_size()
			if inv_idx < match_ctrl.equipment_inventory.size():
				var mid: String = str(match_ctrl.equipment_inventory[inv_idx]).strip_edges()
				if mid != "":
					match_ctrl.equipment_inventory[inv_idx] = ""
					_credit_equipment_sell(mid)
					_refresh_equipment_inventory_ui()
			return
		var to_cell: int = _pick_reserve_cell_at_screen(screen)
		if to_cell >= 0 and to_cell != inv_idx:
			if _try_synth_inventory_stack(inv_idx, to_cell):
				pass
			else:
				match_ctrl.move_equipment_inventory(inv_idx, to_cell)
				_refresh_equipment_inventory_ui()
		elif not _try_drop_equipment_on_ship(screen, str(match_ctrl.equipment_inventory[inv_idx]), false, inv_idx):
			if match_ctrl.stage == MatchController.Stage.PREPARE:
				show_notice("拖到舰船来装配")


func _finish_fit_unequip_drop(screen: Vector2, item_id: String, from_ship: ShipUnit) -> void:
	var mid: String = item_id.strip_edges()
	if mid == "":
		return
	## Drop onto another / same ship → re-fit there.
	if _try_drop_equipment_on_ship(screen, mid, false, -1):
		return
	var to_cell: int = _pick_reserve_cell_at_screen(screen)
	if to_cell >= 0:
		match_ctrl.ensure_equipment_inventory_size()
		if str(match_ctrl.equipment_inventory[to_cell]).strip_edges() == "":
			match_ctrl.equipment_inventory[to_cell] = mid
			_refresh_equipment_inventory_ui()
			if match_ctrl.has_method("request_autosave"):
				match_ctrl.request_autosave()
			return
		## Occupied cell: try synth then swap into empty / fail restore.
		var other: String = str(match_ctrl.equipment_inventory[to_cell]).strip_edges()
		var synth: Dictionary = FunctionFit.try_synth(mid, other)
		if TypedVariant.as_bool(synth.get("ok", false), false):
			match_ctrl.equipment_inventory[to_cell] = str(synth.get("result_id", ""))
			_refresh_equipment_inventory_ui()
			show_notice("合成：%s" % str(DataStore.get_function_module(str(synth.get("result_id", ""))).get("name", "")))
			if match_ctrl.has_method("request_autosave"):
				match_ctrl.request_autosave()
			return
	if match_ctrl.add_equipment_to_inventory(mid):
		_refresh_equipment_inventory_ui()
		if match_ctrl.has_method("request_autosave"):
			match_ctrl.request_autosave()
		return
	## Bag full — put back on original ship if possible.
	if from_ship != null and is_instance_valid(from_ship) and from_ship.has_method("try_fit_function_module"):
		var back: Dictionary = from_ship.try_fit_function_module(mid)
		if TypedVariant.as_bool(back.get("ok", false), false):
			show_notice("背包已满 · 装备装回原舰")
			if _info_ship == from_ship:
				_show_ship_info(from_ship)
			return
	show_notice("背包已满 · 无法卸下")


func _try_synth_inventory_stack(from_idx: int, to_idx: int) -> bool:
	match_ctrl.ensure_equipment_inventory_size()
	if from_idx < 0 or to_idx < 0:
		return false
	if from_idx >= match_ctrl.equipment_inventory.size() or to_idx >= match_ctrl.equipment_inventory.size():
		return false
	var a: String = str(match_ctrl.equipment_inventory[from_idx]).strip_edges()
	var b: String = str(match_ctrl.equipment_inventory[to_idx]).strip_edges()
	if a == "" or b == "":
		return false
	var res: Dictionary = FunctionFit.try_synth(a, b)
	if not TypedVariant.as_bool(res.get("ok", false), false):
		return false
	var out_id: String = str(res.get("result_id", ""))
	if out_id == "":
		return false
	match_ctrl.equipment_inventory[from_idx] = ""
	match_ctrl.equipment_inventory[to_idx] = out_id
	_refresh_equipment_inventory_ui()
	var out_mod: Dictionary = DataStore.get_function_module(out_id)
	show_notice("合成：%s" % str(out_mod.get("name", out_id)))
	if match_ctrl.has_method("request_autosave"):
		match_ctrl.request_autosave()
	return true


func _current_equip_drag_item_id() -> String:
	if _equip_drag_item_id.strip_edges() != "":
		return _equip_drag_item_id
	if _equip_drag_source == "shop" and _equip_drag_shop_idx >= 0 and _equip_drag_shop_idx < shop.equipment_slots.size():
		return str(TypedVariant.as_dict(shop.equipment_slots[_equip_drag_shop_idx]).get("id", ""))
	if _equip_drag_source == "inventory" and _equip_drag_inv_idx >= 0:
		match_ctrl.ensure_equipment_inventory_size()
		if _equip_drag_inv_idx < match_ctrl.equipment_inventory.size():
			return str(match_ctrl.equipment_inventory[_equip_drag_inv_idx])
	return ""


func _ensure_equipment_ghost(item_id: String) -> void:
	if _equip_ghost and is_instance_valid(_equip_ghost):
		return
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	var mod: Dictionary = DataStore.get_function_module(item_id)
	var ghost: PanelContainer = PanelContainer.new()
	ghost.name = "EquipDragGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 85
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.2, 0.9)
	sb.border_color = Color(0.5, 0.85, 1.0, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(4)
	ghost.add_theme_stylebox_override("panel", sb)
	var sz: Vector2 = Vector2(UiLayout.px(40, root), UiLayout.px(40, root))
	ghost.custom_minimum_size = sz
	if not mod.is_empty():
		@warning_ignore("unsafe_method_access")
		var ghost_icon: Control = _EQUIP_ICON_VIEW.make_icon_cell(sz - Vector2(8, 8), mod, ghost)
		ghost.add_child(ghost_icon)
	root.add_child(ghost)
	_equip_ghost = ghost


func _move_equipment_ghost(screen: Vector2) -> void:
	if _equip_ghost == null or not is_instance_valid(_equip_ghost):
		return
	_equip_ghost.global_position = screen - _equip_ghost.size * 0.5


func _clear_equipment_drag() -> void:
	_equip_drag_source = ""
	_equip_drag_shop_idx = -1
	_equip_drag_inv_idx = -1
	_equip_drag_ship = null
	_equip_drag_fit_slot = -1
	_equip_drag_item_id = ""
	_equip_drag_active = false
	if _equip_ghost and is_instance_valid(_equip_ghost):
		_equip_ghost.queue_free()
	_equip_ghost = null
	if _dragging_sell_ui:
		_dragging_sell_ui = false
		_set_sell_mode(false)


func _equip_screen_in_sell_zone(screen: Vector2) -> bool:
	## Align with PointerInput._in_sell_zone: SellZone when visible, else shop strip.
	@warning_ignore("unsafe_cast")
	var sell: Control = hud.get_node_or_null("Root/%s/SellZone" % _SHOP_INNER) as Control
	if sell != null and sell.visible:
		return sell.get_global_rect().has_point(screen)
	@warning_ignore("unsafe_cast")
	var shop_root: Control = hud.get_node_or_null("Root/Shop") as Control
	if shop_root == null or not shop_root.visible:
		return false
	@warning_ignore("unsafe_cast")
	var content: Control = hud.get_node_or_null("Root/Shop/ShopCol/ShopContent") as Control
	if content and not content.visible:
		return false
	return shop_root.get_global_rect().has_point(screen)


func _credit_equipment_sell(item_id: String) -> void:
	var mid: String = item_id.strip_edges()
	if mid == "" or match_ctrl == null:
		return
	var gold: int = DataStore.function_module_sell_price(mid)
	match_ctrl.add_gold(gold)
	SessionDiagnostics.log("shop.equipment_sell", "ok item=%s gold=%d" % [mid, gold])
	show_notice("出售获得 %d PLEX" % gold)
	_refresh_hud()
	if match_ctrl.has_method("request_autosave"):
		match_ctrl.request_autosave()


## Star merge (3→1): board already stripped fits; stash ids into bag or auto-sell (EQUIPMENT §2).
## Args are primitives only — never pass ShipUnit across queue_free.
func on_star_merge_stash_equipment(team: int, item_ids: Array) -> void:
	## Materials may have been the open info / equip target — drop freed typed refs before HUD.
	if not is_instance_valid(_info_ship):
		_info_ship = null
	if not is_instance_valid(_drag_info_ship):
		_drag_info_ship = null
	if not is_instance_valid(_equip_detail_fit_ship):
		_equip_detail_fit_ship = null
	if not is_instance_valid(_equip_drag_ship):
		_equip_drag_ship = null
	var bagged: int = 0
	var sold: int = 0
	var sold_gold: int = 0
	for id_any: Variant in TypedVariant.as_array(item_ids):
		var mid: String = str(id_any).strip_edges()
		if mid == "":
			continue
		var outcome: Dictionary = _stash_or_auto_sell_star_merge_equipment(mid, team)
		if TypedVariant.as_int(outcome.get("sold", 0), 0) > 0:
			sold += 1
			sold_gold += TypedVariant.as_int(outcome.get("gold", 0), 0)
		elif TypedVariant.as_bool(outcome.get("bagged", false), false):
			bagged += 1
	if team == ShipUnit.TEAM_PLAYER:
		_refresh_equipment_inventory_ui()
		_refresh_hud()
		if sold > 0:
			show_notice("升星背包已满，已自动出售 %d 件（+%d）" % [sold, sold_gold])
		if match_ctrl != null and match_ctrl.has_method("request_autosave"):
			match_ctrl.request_autosave()
	elif sold > 0 or bagged > 0:
		SessionDiagnostics.log(
			"equip.star_merge_summary",
			"team=ai bagged=%d sold=%d gold=%d" % [bagged, sold, sold_gold]
		)


func _stash_or_auto_sell_star_merge_equipment(item_id: String, team: int) -> Dictionary:
	var mid: String = item_id.strip_edges()
	if mid == "":
		return {}
	var team_tag: String = "player" if team == ShipUnit.TEAM_PLAYER else "ai"
	if team == ShipUnit.TEAM_PLAYER:
		if match_ctrl != null and match_ctrl.add_equipment_to_inventory(mid):
			SessionDiagnostics.log("equip.star_merge_return", "ok team=%s item=%s" % [team_tag, mid])
			return {"bagged": true}
		var gold: int = DataStore.function_module_sell_price(mid)
		if match_ctrl != null:
			match_ctrl.add_gold(gold)
		SessionDiagnostics.log(
			"equip.star_merge_sell",
			"bag_full team=%s item=%s gold=%d" % [team_tag, mid, gold]
		)
		return {"sold": 1, "gold": gold}
	if ai != null and ai.has_method("add_equipment_to_inventory") and ai.add_equipment_to_inventory(mid):
		SessionDiagnostics.log("equip.star_merge_return", "ok team=%s item=%s" % [team_tag, mid])
		return {"bagged": true}
	var gold_ai: int = DataStore.function_module_sell_price(mid)
	if ai != null and ai.has_method("add_gold"):
		ai.add_gold(gold_ai)
	SessionDiagnostics.log(
		"equip.star_merge_sell",
		"bag_full team=%s item=%s gold=%d" % [team_tag, mid, gold_ai]
	)
	return {"sold": 1, "gold": gold_ai}


func _pick_reserve_cell_at_screen(screen: Vector2) -> int:
	var grid: GridContainer = hud.get_node_or_null("Root/%s" % _RESERVE_GRID_PATH) as GridContainer
	if grid == null:
		return -1
	for i: int in range(grid.get_child_count()):
		@warning_ignore("unsafe_cast")
		var cell: Control = grid.get_child(i) as Control
		if cell and cell.get_global_rect().has_point(screen):
			return i
	return -1


func _pick_ship_at_screen(screen: Vector2) -> ShipUnit:
	if pointer == null:
		return null
	if pointer.has_method("pick_ship_at_screen"):
		return pointer.pick_ship_at_screen(screen)
	if camera == null or board == null:
		return null
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	var best: ShipUnit = null
	var best_d: float = INF
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_PLAYER:
			continue
		var to: Vector3 = s.global_position - origin
		var t: float = to.dot(dir)
		if t < 0.0:
			continue
		var closest: Vector3 = origin + dir * t
		var dist: float = closest.distance_to(s.global_position)
		if dist < 2.5 and t < best_d:
			best_d = t
			best = s
	return best


func _try_drop_equipment_on_ship(screen: Vector2, item_id: String, from_shop: bool, source_idx: int) -> bool:
	var ship: ShipUnit = _pick_ship_at_screen(screen)
	if ship == null:
		return false
	if match_ctrl.stage != MatchController.Stage.PREPARE:
		show_notice("仅准备阶段可装配")
		return false
	if from_shop:
		var bought_id: String = item_id
		if source_idx >= 0 and source_idx < shop.equipment_slots.size():
			bought_id = str(TypedVariant.as_dict(shop.equipment_slots[source_idx]).get("id", bought_id))
		shop.try_buy_equipment(source_idx)
		item_id = bought_id
		_refresh_shop_ui()
		var inv_idx: int = -1
		match_ctrl.ensure_equipment_inventory_size()
		for i: int in range(match_ctrl.equipment_inventory.size()):
			if str(match_ctrl.equipment_inventory[i]) == item_id:
				inv_idx = i
				break
		if inv_idx < 0:
			return true
		return _try_fit_equipment_to_ship(ship, item_id, inv_idx)
	if item_id.strip_edges() == "":
		return false
	return _try_fit_equipment_to_ship(ship, item_id, source_idx)


func _try_fit_equipment_to_ship(ship: ShipUnit, item_id: String, inv_idx: int) -> bool:
	if ship == null or item_id.strip_edges() == "":
		return false
	if not ship.has_method("try_fit_function_module"):
		show_notice("舰船装配尚未就绪")
		return false
	var mid: String = item_id.strip_edges()
	var res: Dictionary = ship.try_fit_function_module(mid)
	if TypedVariant.as_bool(res.get("ok", false), false):
		_consume_inv_equipment_slot(inv_idx)
		_show_ship_info(ship)
		return true
	match str(res.get("reason", "")):
		"full":
			return _try_fit_full_ship_synth_or_swap(ship, mid, inv_idx)
		"implant_taken":
			show_notice("每舰只能装一件植入体")
		"size":
			show_notice("装备尺寸不合适")
		"cyno_hull":
			show_notice("诱导舰不能安装副装备")
		_:
			show_notice("无法装配该装备")
	return false


## Full 3-slot hull (EQUIPMENT §2): slot-order synth, else swap slot 0.
func _try_fit_full_ship_synth_or_swap(ship: ShipUnit, item_id: String, inv_idx: int) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var mid: String = item_id.strip_edges()
	if mid == "":
		return false
	var fit: Array = ship.get_function_fit()
	for slot_i: int in range(fit.size()):
		var entry: Dictionary = TypedVariant.as_dict(fit[slot_i])
		var other: String = str(entry.get("id", "")).strip_edges()
		if other == "":
			continue
		var synth: Dictionary = FunctionFit.try_synth(mid, other)
		if not TypedVariant.as_bool(synth.get("ok", false), false):
			continue
		var result_id: String = str(synth.get("result_id", "")).strip_edges()
		if result_id == "":
			continue
		var removed: String = ship.unequip_function_at(slot_i)
		if removed != other:
			## Restore if unequip missed (should not happen).
			if removed != "":
				ship.try_fit_function_module(removed)
			continue
		_consume_inv_equipment_slot(inv_idx)
		var fitted: Dictionary = ship.try_fit_function_module(result_id)
		if TypedVariant.as_bool(fitted.get("ok", false), false):
			show_notice("合成并装配：%s" % str(DataStore.get_function_module(result_id).get("name", result_id)))
			_show_ship_info(ship)
			if match_ctrl.has_method("request_autosave"):
				match_ctrl.request_autosave()
			return true
		## Product cannot install → bag (EQUIPMENT §2).
		if not _stash_equipment_id(result_id):
			_credit_equipment_sell(result_id)
			show_notice("合成：%s · 无法安装且背包满已出售" % str(DataStore.get_function_module(result_id).get("name", result_id)))
			_show_ship_info(ship)
			if match_ctrl.has_method("request_autosave"):
				match_ctrl.request_autosave()
			return true
		show_notice("合成：%s · 无法安装已回背包" % str(DataStore.get_function_module(result_id).get("name", result_id)))
		_show_ship_info(ship)
		if match_ctrl.has_method("request_autosave"):
			match_ctrl.request_autosave()
		return true
	## No recipe — swap first fitted module with dragged item.
	if fit.is_empty():
		show_notice("功能桶已满（最多3件）· 装备退回背包")
		return false
	var first_id: String = ship.unequip_function_at(0)
	if first_id == "":
		show_notice("功能桶已满（最多3件）· 装备退回背包")
		return false
	var put: Dictionary = ship.try_fit_function_module(mid)
	if not TypedVariant.as_bool(put.get("ok", false), false):
		ship.try_fit_function_module(first_id)
		match str(put.get("reason", "")):
			"size":
				show_notice("装备尺寸不合适")
			"implant_taken":
				show_notice("每舰只能装一件植入体")
			_:
				show_notice("无法装配该装备")
		return false
	if inv_idx >= 0:
		match_ctrl.ensure_equipment_inventory_size()
		if inv_idx < match_ctrl.equipment_inventory.size():
			match_ctrl.equipment_inventory[inv_idx] = first_id
			_refresh_equipment_inventory_ui()
		elif not _stash_equipment_id(first_id):
			## Dragged item is on ship; first has nowhere to go — sell.
			_credit_equipment_sell(first_id)
			show_notice("已替换 · 卸下件背包满已出售")
			_show_ship_info(ship)
			if match_ctrl.has_method("request_autosave"):
				match_ctrl.request_autosave()
			return true
	elif not _stash_equipment_id(first_id):
		_credit_equipment_sell(first_id)
		show_notice("已替换 · 卸下件背包满已出售")
		_show_ship_info(ship)
		if match_ctrl.has_method("request_autosave"):
			match_ctrl.request_autosave()
		return true
	show_notice("已替换第 1 件装备")
	_show_ship_info(ship)
	if match_ctrl.has_method("request_autosave"):
		match_ctrl.request_autosave()
	return true


func _consume_inv_equipment_slot(inv_idx: int) -> void:
	if inv_idx < 0 or match_ctrl == null:
		return
	match_ctrl.remove_equipment_from_inventory(inv_idx)
	_refresh_equipment_inventory_ui()


func _stash_equipment_id(item_id: String) -> bool:
	var mid: String = item_id.strip_edges()
	if mid == "" or match_ctrl == null:
		return false
	if match_ctrl.add_equipment_to_inventory(mid):
		_refresh_equipment_inventory_ui()
		return true
	return false


func _begin_equipment_inventory_drag_from_local(inv_idx: int, item_id: String, local: Vector2, from: Control) -> void:
	var screen: Vector2 = local
	if from:
		screen = from.get_global_transform_with_canvas() * local
	_begin_equipment_inventory_drag(inv_idx, item_id, screen)


func _local_titan_race_for_ui() -> String:
	## Industrial tips_ore variant may follow the local nullsec titan race.
	if GameSession == null or GameSession.pending_mode != "nullsec":
		return ""
	var race: String = str(GameSession.pending_nullsec.get("local_titan_race", ""))
	if race != "":
		return race
	if typeof(GameSession.pending_nullsec.get("seats", null)) != TYPE_ARRAY:
		return ""
	var seats: Array = GameSession.pending_nullsec.get("seats", [])
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	for s_v: Variant in seats:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) == local_seat:
			return str(s.get("titan_race", ""))
	return ""

func _shop_card_size(slot_count: int, box: Control) -> Vector2:
	var avail_w: float = box.size.x
	var avail_h: float = box.size.y
	if avail_w < 8.0 or avail_h < 8.0:
		@warning_ignore("unsafe_cast")
		var shop_panel: Control = hud.get_node_or_null("Root/Shop") as Control
		if shop_panel:
			avail_w = shop_panel.size.x * 0.88
			avail_h = shop_panel.size.y * 0.62
	if avail_w < 8.0:
		avail_w = UiLayout.px(1100.0, box)
	if avail_h < 8.0:
		avail_h = UiLayout.px(160.0, box)
	var sep: float = float(UiLayout.margin_px(6, box))
	var total_sep: float = sep * float(maxi(0, slot_count - 1))
	var w: float = (avail_w - total_sep) / float(slot_count)
	var min_w: float = UiLayout.px(88.0 if UiLayout.is_mobile() else 100.0, box)
	var max_w: float = UiLayout.px(180.0 if UiLayout.is_mobile() else 210.0, box)
	var min_h: float = UiLayout.px(120.0 if UiLayout.is_mobile() else 140.0, box)
	var max_h: float = UiLayout.px(180.0 if UiLayout.is_mobile() else 210.0, box)
	return Vector2(clampf(w, min_w, max_w), clampf(avail_h, min_h, max_h))

func _make_shop_card(ship_name: String, ship: Dictionary, purchased: bool, cost: int, idx: int, card_size: Vector2 = Vector2.ZERO) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var sz: Vector2 = card_size if card_size.x > 0.0 else Vector2(UiLayout.px(140, card), UiLayout.px(170, card))
	card.custom_minimum_size = sz
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titan_race: String = _local_titan_race_for_ui()
	var tips_tex: Texture2D = null if purchased else UiAssets.shop_card_tips_skybox(ship, titan_race)
	var outer: StyleBoxFlat = StyleBoxFlat.new()
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
	var stack: Control = Control.new()
	stack.custom_minimum_size = sz
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(stack)
	if purchased:
		var done: Label = Label.new()
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
		var tips: TextureRect = TextureRect.new()
		tips.name = "TipsSkybox"
		tips.texture = tips_tex
		tips.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tips.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(tips)
	# Large centered portrait (leave room below for fetter strip + name)
	var psz: float = minf(sz.x * 0.88, sz.y * 0.58)
	psz = maxf(psz, UiLayout.px(72 if UiLayout.is_mobile() else 90, card))
	var tex: Texture2D = UiAssets.champion_icon(ship_name, TypedVariant.as_int(ship.get("id", 0), 0))
	var art: Control
	if tex:
		var art_rect: TextureRect = TextureRect.new()
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_rect.texture = tex
		art = art_rect
	else:
		var ph: ColorRect = ColorRect.new()
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
	var badge_icon: int = UiLayout.px(18 if UiLayout.is_mobile() else 22, card)
	var fetter_box: HBoxContainer = HBoxContainer.new()
	fetter_box.add_theme_constant_override("separation", UiLayout.margin_px(3, card))
	fetter_box.alignment = BoxContainer.ALIGNMENT_CENTER
	fetter_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	fetter_box.anchor_left = 0.0
	fetter_box.anchor_right = 1.0
	fetter_box.offset_left = UiLayout.px(4, card)
	fetter_box.offset_right = -UiLayout.px(4, card)
	fetter_box.offset_top = art.offset_bottom + UiLayout.px(2, card)
	fetter_box.offset_bottom = fetter_box.offset_top + badge_icon + 2.0
	for fid: Variant in fids:
		var fdata: Dictionary = DataStore.fetters.get(str(fid), {})
		var fname: String = str(fdata.get("name", fid))
		var fic: TextureRect = TextureRect.new()
		fic.custom_minimum_size = Vector2(badge_icon, badge_icon)
		fic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fic.tooltip_text = fname
		var ft: Texture2D = UiAssets.fetter_icon(str(fid), fname)
		if ft:
			fic.texture = ft
		else:
			# 无图时用色块占位，避免空白缺口
			var ph2: ColorRect = ColorRect.new()
			ph2.custom_minimum_size = Vector2(badge_icon, badge_icon)
			ph2.color = Color(0.35, 0.4, 0.48, 0.9)
			ph2.tooltip_text = fname
			fetter_box.add_child(ph2)
			continue
		fetter_box.add_child(fic)
	stack.add_child(fetter_box)
	# Name under fetter strip
	var name_l: Label = Label.new()
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
	var star_badge: PanelContainer = _make_corner_badge("★1", Color(0.12, 0.1, 0.05, 0.92), Color(1.0, 0.88, 0.35), card)
	star_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	star_badge.offset_left = UiLayout.px(4, card)
	star_badge.offset_top = UiLayout.px(4, card)
	star_badge.offset_right = star_badge.offset_left + UiLayout.px(42, card)
	star_badge.offset_bottom = star_badge.offset_top + UiLayout.px(24, card)
	stack.add_child(star_badge)
	# 价格角标 · 右下
	var cost_badge: PanelContainer = PanelContainer.new()
	var cost_sb: StyleBoxFlat = StyleBoxFlat.new()
	cost_sb.bg_color = Color(0.05, 0.08, 0.1, 0.92)
	cost_sb.border_color = Color(0.85, 0.7, 0.25, 0.9)
	cost_sb.set_border_width_all(1)
	cost_sb.set_corner_radius_all(4)
	cost_sb.set_content_margin_all(UiLayout.margin_px(4, card))
	cost_badge.add_theme_stylebox_override("panel", cost_sb)
	var cost_row: HBoxContainer = HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", UiLayout.margin_px(3, card))
	cost_badge.add_child(cost_row)
	var money: TextureRect = TextureRect.new()
	money.custom_minimum_size = Vector2(UiLayout.px(16, card), UiLayout.px(16, card))
	money.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	money.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mt: Texture2D = UiAssets.tex(UiAssets.ICON_MONEY)
	if mt:
		money.texture = mt
	cost_row.add_child(money)
	var cost_l: Label = Label.new()
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
	var hit: Button = Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if UiLayout.is_mobile():
		## Mobile: tap = ship info + drag-to-hangar tip; drag onto hangar = buy; long-press = preview.
		hit.gui_input.connect(func(ev: InputEvent) -> void: _shop_gui_input(ev, idx, hit))
	else:
		hit.pressed.connect(func() -> void:
			var bought_pc: Dictionary = shop.try_buy(idx)
			_note_shop_purchase(bought_pc)
			_refresh_shop_ui()
			_refresh_hud()
		)
		hit.mouse_entered.connect(func() -> void: _show_ship_info_id(TypedVariant.as_int(ship.get("id", 0), 0)))
	stack.add_child(hit)
	return card

func _make_corner_badge(text: String, bg: Color, fg: Color, from: Node) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(UiLayout.margin_px(4, from))
	badge.add_theme_stylebox_override("panel", sb)
	var lab: Label = Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiAssets.apply_label_font(lab, false, UiLayout.font_size(13, from))
	lab.add_theme_color_override("font_color", fg)
	badge.add_child(lab)
	return badge

func _shop_card_height(slot_count: int, box: Control) -> float:
	return _shop_card_size(slot_count, box).y

func _shop_gui_input(ev: InputEvent, idx: int, from: Control = null) -> void:
	_hud_interact_ms = Time.get_ticks_msec()
	if not UiLayout.is_mobile():
		return
	## Press starts here; drag/release continue in `_input` so finger can leave the card.
	var screen: Vector2 = _shop_event_screen(ev, from)
	if ev is InputEventScreenTouch:
		var st: InputEventScreenTouch = ev as InputEventScreenTouch
		if st.pressed:
			_shop_begin_press(idx, screen)
			if from:
				from.accept_event()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.pressed:
			_shop_begin_press(idx, screen)
			if from:
				from.accept_event()


func _input(event: InputEvent) -> void:
	if _equip_drag_source != "":
		if event is InputEventScreenDrag:
			_update_equipment_drag((event as InputEventScreenDrag).position)
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch:
			var st: InputEventScreenTouch = event as InputEventScreenTouch
			if not st.pressed:
				_end_equipment_drag(st.position)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_equipment_drag((event as InputEventMouseMotion).position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if not mb.pressed:
				_end_equipment_drag(mb.position)
				get_viewport().set_input_as_handled()
		return
	if _shop_drag_idx < 0 or not UiLayout.is_mobile():
		return
	if event is InputEventScreenDrag:
		_shop_update_drag(_shop_drag_idx, (event as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if not st.pressed:
			_shop_end_press(_shop_drag_idx, st.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_shop_update_drag(_shop_drag_idx, (event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			_shop_end_press(_shop_drag_idx, mb.position)
			get_viewport().set_input_as_handled()


func _shop_event_screen(ev: InputEvent, from: Control) -> Vector2:
	var local: Vector2 = Vector2.ZERO
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
	var dist: float = screen.distance_to(_shop_press_screen)
	if not _shop_drag_active and dist >= _SHOP_DRAG_THRESHOLD_PX:
		_shop_drag_active = true
		_long_press_slot = -1
		## Ghost follows finger inside shop; purchase only after leaving shop rect (UI_AND_SHELL §2.1).
		var preview_ship_id: int = 0
		if idx >= 0 and idx < shop.slots.size():
			preview_ship_id = TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0)
		_ensure_shop_ghost_for_ship_id(preview_ship_id)
	## Leave shop area → buy onto hangar and stick to finger.
	if _shop_drag_active and _shop_bought_ship == null and not _shop_screen_in_shop(screen):
		var preview_ship_id2: int = 0
		if idx >= 0 and idx < shop.slots.size():
			preview_ship_id2 = TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0)
		var bought: Dictionary = shop.try_buy(idx)
		_refresh_shop_ui()
		_refresh_hud()
		if not TypedVariant.as_bool(bought.get("accepted", false), false):
			_shop_clear_drag()
			return
		_note_shop_purchase(bought, preview_ship_id2)
		var hx: int = TypedVariant.as_int(bought.get("hangar_x", -1), -1)
		var hz: int = TypedVariant.as_int(bought.get("hangar_z", 0), 0)
		var ship: ShipUnit = board._occupant_at("hangar", ShipUnit.TEAM_PLAYER, hx, hz) if board else null
		if ship == null or not is_instance_valid(ship):
			_shop_clear_drag()
			return
		_shop_bought_ship = ship
		board.begin_drag(ship)
		_ensure_shop_ghost_for_ship_id(preview_ship_id2)
	if _shop_bought_ship != null and is_instance_valid(_shop_bought_ship) and board != null and camera != null:
		var origin: Vector3 = camera.project_ray_origin(screen)
		var dir: Vector3 = camera.project_ray_normal(screen)
		if absf(dir.y) > 0.0001:
			var t: float = -origin.y / dir.y
			board.update_drag(origin + dir * t)
		_move_shop_ghost(screen)
	elif _shop_drag_active:
		_move_shop_ghost(screen)
		## Still inside shop: surface detail (drag = inspect, not buy).
		if _shop_screen_in_shop(screen) and idx >= 0 and idx < shop.slots.size() and not _shop_long_previewed:
			_shop_long_previewed = true
			_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0))
	elif _long_press_slot == idx and not _shop_long_previewed:
		var held: float = Time.get_ticks_msec() / 1000.0 - _long_press_t
		if held >= 0.35:
			_shop_long_previewed = true
			if idx >= 0 and idx < shop.slots.size():
				_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0))


func _shop_screen_in_shop(screen: Vector2) -> bool:
	@warning_ignore("unsafe_cast")
	var shop_root: Control = hud.get_node_or_null("Root/Shop") as Control
	if shop_root == null or not shop_root.visible:
		return false
	return shop_root.get_global_rect().has_point(screen)


func _shop_end_press(idx: int, screen: Vector2) -> void:
	if _shop_drag_idx != idx:
		_shop_clear_drag()
		return
	var was_drag: bool = _shop_drag_active
	var previewed: bool = _shop_long_previewed
	var bought: ShipUnit = _shop_bought_ship
	_shop_bought_ship = null
	_shop_clear_drag()
	if was_drag and bought != null and is_instance_valid(bought) and board != null:
		## Ensure board still dragging this ship (begin_drag may have been cleared).
		if board._drag_ship != bought:
			board.begin_drag(bought)
		var slot: Dictionary = _shop_pick_board_slot_at_screen(screen)
		board.end_drag(false, slot)
		_refresh_hud()
		return
	if was_drag:
		## Released still inside shop (or buy failed earlier): detail only.
		if idx >= 0 and idx < shop.slots.size():
			_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0))
		return
	## Not a drag: always surface the ship detail panel on tap (mobile tap-to-inspect),
	## even if a long-press already previewed it — the release is still a deliberate tap.
	if idx >= 0 and idx < shop.slots.size():
		_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0))
	if previewed:
		return
	show_notice(_SHOP_BUY_TIP)


func _shop_clear_drag() -> void:
	_shop_drag_idx = -1
	_shop_drag_active = false
	_long_press_slot = -1
	_shop_long_previewed = false
	if _shop_bought_ship != null and board != null and board._drag_ship == _shop_bought_ship:
		board._cancel_drag()
	_shop_bought_ship = null
	if _shop_ghost and is_instance_valid(_shop_ghost):
		_shop_ghost.queue_free()
	_shop_ghost = null


func _ensure_shop_ghost(idx: int) -> void:
	var ship_id: int = 0
	if idx >= 0 and idx < shop.slots.size():
		ship_id = TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0)
	_ensure_shop_ghost_for_ship_id(ship_id)


func _ensure_shop_ghost_for_ship_id(ship_id: int) -> void:
	if _shop_ghost and is_instance_valid(_shop_ghost):
		return
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	var ghost: PanelContainer = PanelContainer.new()
	ghost.name = "ShopDragGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 80
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.16, 0.22, 0.88)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	ghost.add_theme_stylebox_override("panel", sb)
	var lab: Label = Label.new()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var half: Vector2 = _shop_ghost.custom_minimum_size * 0.5
	_shop_ghost.global_position = screen - half


func _shop_pick_board_slot_at_screen(screen: Vector2) -> Dictionary:
	## Hangar or field under finger — drop after drag-buy (UI_AND_SHELL §2.3).
	if camera == null or board == null:
		return {}
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return {}
	var t: float = -origin.y / dir.y
	var hit_world: Vector3 = origin + dir * t
	var slot: Dictionary = board.pick_slot_at(hit_world, ShipUnit.TEAM_PLAYER)
	var st: String = str(slot.get("slot_type", ""))
	if st == "hangar" or st == "field":
		return slot
	return _shop_pick_hangar_at_screen(screen)


func _shop_pick_hangar_at_screen(screen: Vector2) -> Dictionary:
	if camera == null or board == null:
		return {}
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return {}
	var t: float = -origin.y / dir.y
	var hit_world: Vector3 = origin + dir * t
	var slot: Dictionary = board.pick_slot_at(hit_world, ShipUnit.TEAM_PLAYER)
	if str(slot.get("slot_type", "")) == "hangar":
		return slot
	## Slightly looser: nearest hangar cell within 3.5 wu.
	var best: Dictionary = {}
	var best_d: float = 3.5
	var hw: int = TypedVariant.as_int(DataStore.board.get("hangar_width", 15), 0)
	for x: int in range(hw):
		var p: Vector3 = board.cell_to_world("hangar", ShipUnit.TEAM_PLAYER, x, 0)
		var d: float = Vector2(hit_world.x - p.x, hit_world.z - p.z).length()
		if d < best_d:
			best_d = d
			best = {"slot_type": "hangar", "x": x, "z": 0, "team": ShipUnit.TEAM_PLAYER}
	return best


func _set_sell_mode(active: bool, price: int = 0) -> void:
	@warning_ignore("unsafe_cast")
	var slots: Control = hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as Control
	@warning_ignore("unsafe_cast")
	var sell: PanelContainer = hud.get_node_or_null("Root/%s/SellZone" % _SHOP_INNER) as PanelContainer
	if slots:
		slots.visible = not active
	if sell:
		sell.visible = active
		@warning_ignore("unsafe_cast")
		var lab: Label = sell.get_node_or_null("SellLabel") as Label
		if lab:
			lab.text = "售价  %d" % price if active else "售价"
			UiAssets.apply_label_font(lab, false, 22)

func _on_drag_begin(ship: ShipUnit) -> void:
	board.begin_drag(ship)
	_drag_info_ship = ship
	_dragging_sell_ui = true
	var price: int = 0
	if ship:
		price = ship.get_sell_price()
	_set_sell_mode(true, price)

func _on_drag_move(world_pos: Vector3) -> void:
	board.update_drag(world_pos)

func _on_drag_end(sell: bool, slot: Dictionary) -> void:
	board.end_drag(sell, slot)
	var team: int = TypedVariant.as_int(slot.get("team", ShipUnit.TEAM_PLAYER), 0)
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
		## Same unit while detail is pinned — keep the 10s hold (PC click dwell).
		if _info_hold_active() and _info_ship == ship:
			_show_ship_info(ship)
			return
		## Hovering a different unit ends the hold and hands the panel back to hover rules.
		_info_hold_until_ms = 0
		_show_ship_info(ship)
		return
	## Fallback: nullsec berth titans are not board-registered.
	var berth_unit: ShipUnit = _pick_berth_unit_under_cursor()
	if berth_unit:
		if _info_hold_active() and _info_ship == berth_unit:
			_show_ship_info(berth_unit)
			return
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
	var screen: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	for berth: TitanBerth in [_titan_berth, _rival_titan_berth]:
		if berth == null or not is_instance_valid(berth):
			continue
		if berth.pick_hits_ray(origin, dir) and berth.unit and is_instance_valid(berth.unit):
			return berth.unit
	return null

func _play_titan_berth_intro() -> void:
	## §2.5: head-down camera + slide berth in from offscreen once.
	if _nullsec_spectating:
		_titan_intro_done = true
		_rival_titan_intro_done = true
		return
	if _titan_intro_done or GameSession.pending_mode != "nullsec":
		return
	if _titan_berth == null or not is_instance_valid(_titan_berth):
		_titan_intro_done = true
		## Lowsec may still need rival-only slide if home berth missing.
		if _rival_titan_berth and is_instance_valid(_rival_titan_berth) and _rival_titan_berth.visible:
			_begin_rival_titan_slide()
		return
	if _camera_manual_pose():
		_titan_intro_done = true
		if _rival_titan_berth and is_instance_valid(_rival_titan_berth) and _rival_titan_berth.visible:
			_begin_rival_titan_slide()
		return
	_titan_intro_end = _titan_berth.position
	_titan_intro_start = _titan_intro_end + Vector3(0, 0, _TITAN_INTRO_SLIDE_Z)
	_titan_berth.position = _titan_intro_start
	_titan_berth.set_engine_trail_emitting(true)
	_titan_intro_pitch0 = _cam_base_pitch_deg
	## Head down (more negative pitch).
	_cam_base_pitch_deg = minf(_cam_base_pitch_deg, _cam_base_pitch_deg - 12.0)
	_titan_intro_t = 0.0
	## Lowsec R1 already shows rival — slide both together (§2.5).
	if _rival_titan_berth and is_instance_valid(_rival_titan_berth) and _rival_titan_berth.visible:
		_begin_rival_titan_slide()


func _begin_rival_titan_slide() -> void:
	## Lowsec only — opponent berth from −Z offscreen (MULTIPLAYER_PVP §2.5).
	## Nullsec rival berth stays pop-in on PVP reveal (no slide).
	if _nullsec_pve == null or not _nullsec_pve.always_pvp:
		return
	if _rival_titan_intro_done or _rival_intro_active:
		return
	if _rival_titan_berth == null or not is_instance_valid(_rival_titan_berth):
		_rival_titan_intro_done = true
		return
	_rival_intro_end = _rival_titan_berth.position
	_rival_intro_start = _rival_intro_end + Vector3(0, 0, -_TITAN_INTRO_SLIDE_Z)
	_rival_titan_berth.visible = true
	_rival_titan_berth.position = _rival_intro_start
	_rival_titan_berth.set_engine_trail_emitting(true)
	_rival_intro_active = true
	## Rival-only path unused on nullsec; keep clock hook for lowsec edge cases.
	if _titan_intro_t < 0.0:
		_titan_intro_t = 0.0


func _finish_rival_titan_slide() -> void:
	if _rival_titan_berth and is_instance_valid(_rival_titan_berth):
		_rival_titan_berth.position = _rival_intro_end
		_rival_titan_berth.set_engine_trail_emitting(false)
		if _rival_titan_berth.has_method("place_tonnage_badge"):
			_rival_titan_berth.place_tonnage_badge()
	_rival_intro_active = false
	_rival_titan_intro_done = true
	_refresh_titan_hp_bar()


func _tick_titan_intro(delta: float) -> void:
	if _titan_intro_t < 0.0:
		return
	var home_sliding: bool = (
		not _titan_intro_done
		and _titan_berth != null
		and is_instance_valid(_titan_berth)
		and _titan_intro_start != _titan_intro_end
	)
	if _camera_manual_pose():
		if home_sliding:
			_titan_berth.position = _titan_intro_end
			_titan_berth.set_engine_trail_emitting(false)
			_cam_base_pitch_deg = _titan_intro_pitch0
		_titan_intro_done = true
		if _rival_intro_active:
			_finish_rival_titan_slide()
		_titan_intro_t = -1.0
		return
	_titan_intro_t += delta
	var u: float = clampf(_titan_intro_t / _TITAN_INTRO_DUR_S, 0.0, 1.0)
	## Smoothstep.
	u = u * u * (3.0 - 2.0 * u)
	if home_sliding:
		_titan_berth.position = _titan_intro_start.lerp(_titan_intro_end, u)
		_cam_base_pitch_deg = lerpf(_cam_base_pitch_deg, _titan_intro_pitch0, u)
	if _rival_intro_active and _rival_titan_berth != null and is_instance_valid(_rival_titan_berth):
		_rival_titan_berth.position = _rival_intro_start.lerp(_rival_intro_end, u)
	if u < 1.0:
		return
	if home_sliding:
		_titan_berth.position = _titan_intro_end
		_titan_berth.set_engine_trail_emitting(false)
		_cam_base_pitch_deg = _titan_intro_pitch0
		if _titan_berth.has_method("place_tonnage_badge"):
			_titan_berth.place_tonnage_badge()
	_titan_intro_done = true
	if _rival_intro_active:
		_finish_rival_titan_slide()
	_titan_intro_t = -1.0

func _on_long_press_shop(idx: int) -> void:
	if idx >= 0 and idx < shop.slots.size():
		_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0))

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
	var tier: String = str(ship_data.get("weapon_tier", ""))
	if tier == "large":
		return "大"
	if tier == "small":
		return "小"
	if tier == "medium":
		return "中"
	var ship_group: String = str(ship_data.get("ship_group", ""))
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
	var source_weapon: int = TypedVariant.as_int(ship_data.get("source_module_type_id", 0), 0)
	if fx == "heal":
		## Medium/large remote repair reuse small-tier icons (art parity).
		return _repair_icon_type_id(TypedVariant.as_int(ship_data.get("source_repair_module_type_id", 0), 0))
	var group: String = str(ship_data.get("ship_group", "frigate"))
	var tier: String = str(ship_data.get("weapon_tier", ""))
	var large: bool = tier == "large" or group == "battleship"
	var medium: bool = tier == "medium" or (tier == "" and (group == "cruiser" or group == "battlecruiser"))
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
			return TypedVariant.as_int(ship_data.get("source_module_type_id", 0), 0)

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

func _weapon_damage_text(dmg: Dictionary, live: ShipUnit = null) -> String:
	var emp: float = TypedVariant.as_float(dmg.get("emp", 0.0), 0.0)
	var thermal: float = TypedVariant.as_float(dmg.get("thermal", 0.0), 0.0)
	var kinetic: float = TypedVariant.as_float(dmg.get("kinetic", 0.0), 0.0)
	var explosive: float = TypedVariant.as_float(dmg.get("explosive", 0.0), 0.0)
	var total: float = emp + thermal + kinetic + explosive
	## Hide per-channel breakdown (capital/cyno UI lock).
	var line: String = "总伤 %d" % roundi(total)
	if live != null and is_instance_valid(live) and absf(float(live.damage_pct_bonus)) > 0.01:
		line += "（羁绊+%.0f%%）" % float(live.damage_pct_bonus)
	return line

func _weapon_or_repair_text(ship_data: Dictionary, star_data: Dictionary, dmg: Dictionary, live: ShipUnit = null) -> String:
	if str(ship_data.get("weapon_fx", "")) != "heal" and not TypedVariant.as_bool(ship_data.get("is_logistic", false), false):
		return _weapon_damage_text(dmg, live)
	var shield: float = 0.0
	var armor: float = 0.0
	var structure: float = 0.0
	## Runtime repair includes fetter_repair_mul (FETTERS §3.1 / UI_AND_SHELL §2.5).
	if live != null and is_instance_valid(live):
		var healed: Dictionary = live.heal_dict_scaled()
		shield = TypedVariant.as_float(healed.get("shield", 0.0), 0.0)
		armor = TypedVariant.as_float(healed.get("armor", 0.0), 0.0)
		structure = TypedVariant.as_float(healed.get("structure", 0.0), 0.0)
	else:
		var repair: Dictionary = star_data.get("repair", {})
		shield = TypedVariant.as_float(repair.get("shield", 0.0), 0.0)
		armor = TypedVariant.as_float(repair.get("armor", 0.0), 0.0)
		structure = TypedVariant.as_float(repair.get("structure", 0.0), 0.0)
	var lines: Array[String] = []
	if shield > 0.0:
		lines.append("护盾修理 %d" % roundi(shield))
	if armor > 0.0:
		lines.append("装甲修理 %d" % roundi(armor))
	if structure > 0.0:
		lines.append("结构修理 %d" % roundi(structure))
	if lines.is_empty():
		lines.append("修理 0")
	return "\n".join(lines)

const _RACE_DRONE_LIGHT: Dictionary = {"amarr": 1001, "caldari": 1002, "gallente": 1003, "minmatar": 1004}
const _RACE_DRONE_MEDIUM: Dictionary = {"amarr": 1005, "caldari": 1006, "gallente": 1007, "minmatar": 1008}
const _RACE_DRONE_HEAVY: Dictionary = {"amarr": 1011, "caldari": 1012, "gallente": 1013, "minmatar": 1014}
const _DRONE_COUNT_EXCEPTIONS: Dictionary = {42: 5, 44: 4, 55: 4, 56: 5}

func _drone_tier_for_carrier(ship_data: Dictionary) -> String:
	var group: String = str(ship_data.get("ship_group", "frigate"))
	if group == "battlecruiser":
		return "medium"
	if group == "battleship":
		return "heavy"
	if group == "cruiser":
		return "medium"
	return "light"

func _race_drone_id(ship_data: Dictionary) -> int:
	var race: String = str(ship_data.get("race", "amarr")).to_lower()
	match _drone_tier_for_carrier(ship_data):
		"heavy":
			return TypedVariant.as_int(_RACE_DRONE_HEAVY.get(race, 1011), 0)
		"medium":
			return TypedVariant.as_int(_RACE_DRONE_MEDIUM.get(race, 1005), 0)
		_:
			return TypedVariant.as_int(_RACE_DRONE_LIGHT.get(race, 1001), 0)

func _ship_drone_bay_slots(ship_data: Dictionary) -> int:
	var sid: int = TypedVariant.as_int(ship_data.get("id", 0), 0)
	if _DRONE_COUNT_EXCEPTIONS.has(sid):
		return TypedVariant.as_int(_DRONE_COUNT_EXCEPTIONS[sid], 0)
	var group: String = str(ship_data.get("ship_group", ""))
	if group == "battleship":
		return 2
	if group == "battlecruiser":
		return 1
	var slots: int = TypedVariant.as_int(ship_data.get("drone_bay_slots", ship_data.get("drone_count_cap", 0)), 0)
	if slots <= 0:
		var bw: float = TypedVariant.as_float(ship_data.get("drone_bandwidth", 0.0), 0.0)
		if bw > 0.0:
			slots = floori(bw / 5.0)
	return slots

func _attack_cycle_s(ship_data: Dictionary, runtime_cycle: float = -1.0) -> float:
	## Same source as ShipUnit.setup: JSON cycle (or combat fallback), then attack_cycle_cap_s.
	var cap_s: float = TypedVariant.as_float(DataStore.combat.get("attack_cycle_cap_s", 6.0), 0.0)
	var role: String = str(ship_data.get("capital_role", ""))
	var skip_cap: bool = role != "" or TypedVariant.as_bool(ship_data.get("requires_cyno_entry", false), false)
	if runtime_cycle > 0.0:
		return runtime_cycle if skip_cap else minf(runtime_cycle, cap_s)
	var cycle: float = TypedVariant.as_float(ship_data.get("attack_cycle_s", 0.0), 0.0)
	if cycle <= 0.0:
		var logistic: bool = str(ship_data.get("weapon_fx", "")) == "heal" or TypedVariant.as_bool(ship_data.get("is_logistic", false), false)
		cycle = TypedVariant.as_float(DataStore.combat.get("logistic_attack_duration_s" if logistic else "attack_duration_s", 1.0), 0.0)
	return cycle if skip_cap else minf(cycle, cap_s)

func _weapon_stats_text(ship_data: Dictionary, star_data: Dictionary, atk_range: float, runtime_cycle: float = -1.0, live: ShipUnit = null) -> String:
	var shown_range: float = float(atk_range)
	var tracking: float = TypedVariant.as_float(star_data.get("tracking", 0.0), 0.0)
	if live != null and is_instance_valid(live):
		tracking = float(live.tracking)
	var cycle: float = _attack_cycle_s(ship_data, runtime_cycle)
	var cd_note: String = ""
	if live != null and is_instance_valid(live) and live.base_attack_duration > 0.05 \
			and absf(float(live.attack_duration) - float(live.base_attack_duration)) > 0.01:
		cd_note = "（羁绊）"
	return "射程 %s\n跟踪 %.2f\nCD %.2fs%s" % [str(roundi(shown_range)), tracking, cycle, cd_note]

func _drone_stats_text(drone_data: Dictionary, drone_star: Dictionary) -> String:
	var cycle: float = _attack_cycle_s(drone_data)
	var speed: float = TypedVariant.as_float(drone_data.get("speed", 0.0), 0.0)
	if TypedVariant.as_bool(drone_data.get("is_logistic", false), false) or str(drone_data.get("weapon_fx", "")) == "heal":
		var repair: Dictionary = drone_star.get("repair", {})
		var parts: Array[String] = []
		for k: String in ["shield", "armor", "structure"]:
			var v: float = TypedVariant.as_float(repair.get(k, 0.0), 0.0)
			if v > 0.0:
				var label: String = "盾" if k == "shield" else ("甲" if k == "armor" else "结")
				parts.append("%s%d" % [label, roundi(v)])
		var heal_txt: String = " ".join(parts) if not parts.is_empty() else "修 0"
		return "%s\nCD %.2fs\n速度 %s" % [heal_txt, cycle, str(roundi(speed))]
	var dmg: Dictionary = drone_star.get("damage", {})
	return "%s\nCD %.2fs\n速度 %s" % [_weapon_damage_text(dmg), cycle, str(roundi(speed))]

func _ensure_info_stat_square(parent: Control, square_name: String, min_size: Vector2) -> Dictionary:
	@warning_ignore("unsafe_cast")
	var square: PanelContainer = parent.get_node_or_null(square_name) as PanelContainer
	var mobile: bool = UiLayout.is_mobile()
	var icon_sz: int = UiLayout.px(44 if mobile else 56, self)
	var lbl_w: int = UiLayout.px(110 if mobile else 150, self)
	var lbl_h: int = UiLayout.px(56 if mobile else 72, self)
	if square == null:
		square = PanelContainer.new()
		square.name = square_name
		square.custom_minimum_size = min_size
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_content_margin_all(0)
		square.add_theme_stylebox_override("panel", sb)
		parent.add_child(square)
	else:
		square.custom_minimum_size = min_size
	var row: HBoxContainer = square.get_node_or_null("%sRow" % square_name) as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "%sRow" % square_name
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override("separation", UiLayout.margin_px(8 if mobile else 10, self))
		UiAssets.full_rect(row)
		square.add_child(row)
	@warning_ignore("unsafe_cast")
	var icon: TextureRect = row.get_node_or_null("%sIcon" % square_name) as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "%sIcon" % square_name
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	icon.custom_minimum_size = Vector2(icon_sz, icon_sz)
	@warning_ignore("unsafe_cast")
	var lbl: Label = row.get_node_or_null("%sText" % square_name) as Label
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
	var mobile: bool = UiLayout.is_mobile()
	@warning_ignore("unsafe_cast")
	var body: VBoxContainer = info_top.get_parent() as VBoxContainer
	var col_parent: Control
	if mobile and body != null:
		col_parent = body
	else:
		col_parent = info_top
	@warning_ignore("unsafe_cast")
	var col: VBoxContainer = col_parent.get_node_or_null("InfoWeaponColumn") as VBoxContainer
	if col == null:
		## Also look under the other parent (desktop↔mobile layout switch).
		var other: Control
		if col_parent == body:
			other = info_top
		else:
			other = body
		if other:
			@warning_ignore("unsafe_cast")
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
	@warning_ignore("unsafe_cast")
	var legacy: PanelContainer = info_top.get_node_or_null("InfoWeaponSquare") as PanelContainer
	if legacy and legacy.get_parent() == info_top:
		info_top.remove_child(legacy)
		legacy.queue_free()
	var w_sz: Vector2 = Vector2(UiLayout.px(168 if mobile else 228, self), UiLayout.px(120 if mobile else 176, self))
	var d_sz: Vector2 = Vector2(UiLayout.px(168 if mobile else 228, self), UiLayout.px(96 if mobile else 120, self))
	var weapon: Dictionary = _ensure_info_stat_square(col, "InfoWeaponSquare", w_sz)
	var drone: Dictionary = _ensure_info_stat_square(col, "InfoDroneSquare", d_sz)
	@warning_ignore("unsafe_cast")
	var fn_list: VBoxContainer = col.get_node_or_null("InfoFunctionList") as VBoxContainer
	if fn_list == null:
		fn_list = VBoxContainer.new()
		fn_list.name = "InfoFunctionList"
		fn_list.add_theme_constant_override("separation", UiLayout.margin_px(4, self))
		col.add_child(fn_list)
	return {"weapon": weapon, "drone": drone, "function_list": fn_list}

func _style_info_stat_label(lbl: Label) -> void:
	UiAssets.apply_label_font(lbl, true, 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)

func _ensure_info_weapon_square(info_top: HBoxContainer) -> Dictionary:
	return _ensure_info_weapon_column(info_top).get("weapon", {})

func _ensure_info_extra(body: VBoxContainer) -> Label:
	@warning_ignore("unsafe_cast")
	var lbl: Label = body.get_node_or_null("InfoExtra") as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "InfoExtra"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(lbl)
	return lbl

func _resist_pct(value: Variant) -> int:
	return roundi(TypedVariant.as_float(value, 0.0) * 100.0)

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

func _base_stats_text(ship_data: Dictionary, live: ShipUnit = null) -> String:
	var long_axis: float = TypedVariant.as_float(ship_data.get("model_long_axis", 0.0), 0.0)
	var long_axis_txt: String = "%.0f" % long_axis if long_axis > 0.0 else "—"
	var sig: float
	var spd: float
	var sensor: float
	var cap: float
	var recharge: float
	var is_titan: bool = str(ship_data.get("ship_group", "")) == "titan"
	var spd_note: String = ""
	if live != null and is_instance_valid(live):
		## Runtime after function-fit passives + fetters (EQUIPMENT §5 / FETTERS §3.1 / UI_AND_SHELL §2.5).
		sig = float(live.signature_radius)
		spd = float(live.base_speed) * maxf(0.01, float(live.fetter_speed_mul))
		if absf(float(live.fetter_speed_mul) - 1.0) > 0.001:
			spd_note = "（羁绊×%.2f）" % float(live.fetter_speed_mul)
		## Label is 感应强度 (JSON); fit passives touch scan_resolution — show that when changed.
		sensor = TypedVariant.as_float(ship_data.get("sensor_strength", 0), 0.0)
		if absf(float(live.scan_resolution) - TypedVariant.as_float(ship_data.get("scan_resolution", live.scan_resolution), 0.0)) > 0.01:
			sensor = float(live.scan_resolution)
		cap = float(live.cap_capacity)
		recharge = float(live.cap_recharge_s)
	else:
		sig = TypedVariant.as_float(ship_data.get("signature_radius", 0), 0.0)
		spd = TypedVariant.as_float(ship_data.get("speed", 0), 0.0)
		sensor = TypedVariant.as_float(ship_data.get("sensor_strength", ship_data.get("scan_resolution", 0)), 0.0)
		cap = TypedVariant.as_float(ship_data.get("capacitor_capacity", 0), 0.0)
		recharge = TypedVariant.as_float(ship_data.get("capacitor_recharge_s", 0), 0.0)
	## Titans do not enter the field — no capacitor stats (MULTIPLAYER_PVP §2.4).
	if is_titan:
		return "信源半径 %s   速度 %s%s   长轴 %s\n感应强度 %s" % [
			str(roundi(sig)),
			str(roundi(spd)),
			spd_note,
			long_axis_txt,
			str(roundi(sensor)),
		]
	return "信源半径 %s   速度 %s%s   长轴 %s\n感应强度 %s   电容量 %s   电容回复 %ss" % [
		str(roundi(sig)),
		str(roundi(spd)),
		spd_note,
		long_axis_txt,
		str(roundi(sensor)),
		str(roundi(cap)),
		str(roundi(recharge)) if recharge == roundf(recharge) else str(snappedf(recharge, 0.1))
	]

func _fill_info_function_modules(fn_list: Variant, ship_data: Dictionary, is_titan_info: bool) -> void:
	@warning_ignore("unsafe_cast")
	var box: VBoxContainer = fn_list as VBoxContainer
	if box == null:
		return
	for c: Node in box.get_children():
		c.queue_free()
	if is_titan_info:
		return
	if FunctionFit.is_cyno_hull(ship_data):
		return
	var fit: Array = []
	if _info_ship != null and is_instance_valid(_info_ship):
		fit = _info_ship.get_function_fit()
	else:
		var fs: Dictionary = ship_data.get("function_slots", {}) if typeof(ship_data.get("function_slots", {})) == TYPE_DICTIONARY else {}
		fit = FunctionFit.entries_from_slot_list(TypedVariant.as_array(fs.get("slots", [])))
	var shown: int = mini(fit.size(), FunctionFit.MAX_SLOTS)
	for i: int in range(shown):
		if typeof(fit[i]) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = fit[i]
		var mod: Dictionary = entry.get("def", {})
		if mod.is_empty():
			mod = DataStore.get_function_module(str(entry.get("id", "")))
		if mod.is_empty():
			continue
		var item_id: String = str(entry.get("id", "")).strip_edges()
		var row: PanelContainer = PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var sb: StyleBoxEmpty = StyleBoxEmpty.new()
		row.add_theme_stylebox_override("panel", sb)
		var inner: HBoxContainer = HBoxContainer.new()
		inner.add_theme_constant_override("separation", UiLayout.margin_px(6, self))
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_sz: Vector2 = Vector2(UiLayout.px(32, self), UiLayout.px(32, self))
		@warning_ignore("unsafe_method_access")
		var icon_cell: Control = _EQUIP_ICON_VIEW.make_icon_cell(icon_sz, mod, box, false)
		icon_cell.custom_minimum_size = icon_sz
		icon_cell.size = icon_sz
		icon_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon_cell)
		var col: VBoxContainer = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_l: Label = Label.new()
		name_l.text = str(mod.get("name", entry.get("id", "?")))
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiAssets.apply_label_font(name_l, true, UiLayout.font_size(12, self))
		col.add_child(name_l)
		@warning_ignore("unsafe_method_access")
		var blurb: String = _EQUIP_ICON_VIEW.format_blurb(mod)
		if blurb != "":
			var bl: Label = Label.new()
			bl.text = blurb.strip_edges()
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			## Cap wrap width to info column so it cannot inflate the side panel.
			bl.custom_minimum_size = Vector2(UiLayout.px(140, self), 0)
			bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UiAssets.apply_label_font(bl, false, UiLayout.font_size(11, self))
			bl.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
			col.add_child(bl)
		inner.add_child(col)
		row.add_child(inner)
		row.gui_input.connect(func(ev: InputEvent) -> void: _info_fit_gui_input(ev, i, item_id, row))
		row.set_meta("equip_detail_hover", true)
		row.mouse_entered.connect(func() -> void: _show_equipment_detail(item_id, true))
		row.mouse_exited.connect(func() -> void: _schedule_hide_equipment_detail())
		row.tree_exiting.connect(func() -> void: _schedule_hide_equipment_detail())
		box.add_child(row)


func _info_fit_gui_input(ev: InputEvent, fit_slot: int, item_id: String, from: Control) -> void:
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.PREPARE:
		return
	if _info_ship == null or not is_instance_valid(_info_ship):
		return
	var screen: Vector2 = _shop_event_screen(ev, from)
	var pressed: bool = false
	if ev is InputEventScreenTouch:
		pressed = (ev as InputEventScreenTouch).pressed
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed = (ev as InputEventMouseButton).pressed
	if not pressed:
		return
	_begin_info_fit_unequip_drag(_info_ship, fit_slot, item_id, screen)
	from.accept_event()


func _begin_info_fit_unequip_drag(ship: ShipUnit, fit_slot: int, item_id: String, screen: Vector2) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if item_id.strip_edges() == "":
		return
	_equip_drag_source = "fit"
	_equip_drag_ship = ship
	_equip_drag_fit_slot = fit_slot
	_equip_drag_item_id = item_id
	_equip_drag_shop_idx = -1
	_equip_drag_inv_idx = -1
	_equip_drag_active = false
	_equip_press_screen = screen
	_show_equipment_detail(item_id)


func _fill_info_panel(ship_name: String, star: int, shield_txt: String, armor_txt: String, structure_txt: String, dmg: Dictionary, atk_range: float, fetter_ids: Array, ship_data: Dictionary, star_data: Dictionary, ship_id: int = 0, runtime_cycle: float = -1.0) -> void:
	@warning_ignore("unsafe_cast")
	var p: PanelContainer = hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if p == null:
		return
	var live: ShipUnit = null
	if _info_ship != null and is_instance_valid(_info_ship) and TypedVariant.as_int(_info_ship.ship_id, 0) == TypedVariant.as_int(ship_id, 0):
		live = _info_ship
	_ensure_side_panel_scrolls()
	@warning_ignore("unsafe_cast")
	var icon: TextureRect = _info_child("InfoTop/InfoIcon", p) as TextureRect
	@warning_ignore("unsafe_cast")
	var title: Label = _info_child("InfoTop/InfoTitleCol/InfoTitle", p) as Label
	@warning_ignore("unsafe_cast")
	var title_col: VBoxContainer = _info_child("InfoTop/InfoTitleCol", p) as VBoxContainer
	var info_top: HBoxContainer = _info_child("InfoTop", p) as HBoxContainer
	var weapon_col: Dictionary = {}
	if info_top:
		weapon_col = _ensure_info_weapon_column(info_top)
	var weapon_square: Dictionary = weapon_col.get("weapon", {})
	var drone_square: Dictionary = weapon_col.get("drone", {})
	if title_col:
		var old_badge: Node = title_col.get_node_or_null("InfoWeaponRow")
		if old_badge:
			old_badge.queue_free()
	@warning_ignore("unsafe_cast")
	var fetter_box: VBoxContainer = _info_child("InfoFetters", p) as VBoxContainer
	@warning_ignore("unsafe_cast")
	var sh: Label = _info_child("InfoShield", p) as Label
	@warning_ignore("unsafe_cast")
	var ar: Label = _info_child("InfoArmor", p) as Label
	@warning_ignore("unsafe_cast")
	var st: Label = _info_child("InfoStructure", p) as Label
	@warning_ignore("unsafe_cast")
	var dm: Label = _info_child("InfoDmg", p) as Label
	@warning_ignore("unsafe_cast")
	var rg: Label = _info_child("InfoRange", p) as Label
	var body: VBoxContainer = _info_body(p)
	var extra: Label = null
	if body:
		extra = _ensure_info_extra(body)
	if icon:
		icon.texture = UiAssets.champion_icon(ship_name, ship_id)
		var isz: int = UiLayout.px(56 if UiLayout.is_mobile() else 72, self)
		icon.custom_minimum_size = Vector2(isz, isz)
	if title:
		title.text = "%s  ★%d" % [ship_name, star]
		UiAssets.apply_label_font(title, true, UiLayout.font_size(18 if UiLayout.is_mobile() else 22, self))
	var is_titan_info: bool = str(ship_data.get("ship_group", "")) == "titan"
	if not is_titan_info:
		@warning_ignore("unsafe_cast")
		var tags_chk: Array = ship_data.get("tags", []) as Array
		for t_v: Variant in tags_chk:
			if str(t_v) == "titan":
				is_titan_info = true
				break
	if not weapon_square.is_empty():
		@warning_ignore("unsafe_cast")
		var weapon_icon: TextureRect = weapon_square.get("icon") as TextureRect
		@warning_ignore("unsafe_cast")
		var weapon_label: Label = weapon_square.get("label") as Label
		@warning_ignore("unsafe_cast")
		var weapon_panel: PanelContainer = weapon_square.get("square") as PanelContainer
		var fs: Dictionary = ship_data.get("function_slots", {}) if typeof(ship_data.get("function_slots", {})) == TYPE_DICTIONARY else {}
		var fslots: Array = fs.get("slots", []) if typeof(fs) == TYPE_DICTIONARY else []
		var cyno_mod: Dictionary = {}
		for m_v: Variant in fslots:
			var m: Dictionary = TypedVariant.as_dict(m_v)
			if str(m.get("kind", "")) == "cyno":
				cyno_mod = m
				break
		var dmg_total: float = TypedVariant.as_float(dmg.get("emp", 0), 0.0) + TypedVariant.as_float(dmg.get("thermal", 0), 0.0) + TypedVariant.as_float(dmg.get("kinetic", 0), 0.0) + TypedVariant.as_float(dmg.get("explosive", 0), 0.0)
		var show_cyno: bool = not cyno_mod.is_empty() or str(ship_data.get("capital_role", "")) == "covert_cyno"
		var is_mining: bool = TypedVariant.as_bool(ship_data.get("is_mining_ship", false), false)
		var mining_gold_base: int = TypedVariant.as_int(ship_data.get("mining_gold_per_round", 0), 0)
		var mining_gold: int = mining_gold_base * maxi(star, 1)
		var is_heal: bool = str(ship_data.get("weapon_fx", "")) == "heal" or TypedVariant.as_bool(ship_data.get("is_logistic", false), false)
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
				var strip_id: int = TypedVariant.as_int(ship_data.get("source_module_type_id", 11008100000), 0)
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
					_weapon_or_repair_text(ship_data, star_data, dmg, live),
					_weapon_stats_text(ship_data, star_data, atk_range, runtime_cycle, live)
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
				var cyno_icon_id: int = TypedVariant.as_int(cyno_mod.get("icon_item_id", ship_data.get("source_module_type_id", 11114010000)), TypedVariant.as_int(ship_data.get("source_module_type_id", 11114010000), 11114010000))
				weapon_icon.texture = UiAssets.item_icon(cyno_icon_id)
			if weapon_label:
				var dur: float = TypedVariant.as_float(cyno_mod.get("duration_s", 90.0), 0.0)
				weapon_label.text = "%s\n读条 %.0fs" % [str(cyno_mod.get("name", "诱导")), dur]
				_style_info_stat_label(weapon_label)
		else:
			if weapon_panel:
				weapon_panel.visible = true
			if weapon_icon:
				weapon_icon.texture = UiAssets.item_icon(_weapon_module_type_id(ship_data))
			if weapon_label:
				weapon_label.text = "%s\n%s" % [
					_weapon_or_repair_text(ship_data, star_data, dmg, live),
					_weapon_stats_text(ship_data, star_data, atk_range, runtime_cycle, live)
				]
				_style_info_stat_label(weapon_label)
	if not drone_square.is_empty():
		@warning_ignore("unsafe_cast")
		var drone_panel: PanelContainer = drone_square.get("square") as PanelContainer
		@warning_ignore("unsafe_cast")
		var drone_icon: TextureRect = drone_square.get("icon") as TextureRect
		@warning_ignore("unsafe_cast")
		var drone_label: Label = drone_square.get("label") as Label
		if is_titan_info:
			if drone_panel:
				drone_panel.visible = false
			if drone_icon:
				drone_icon.texture = null
			if drone_label:
				drone_label.text = ""
		else:
			var fighter_id: int = TypedVariant.as_int(ship_data.get("fighter_unit_id", 0), 0)
			var repair_id: int = TypedVariant.as_int(ship_data.get("heavy_repair_drone_id", 0), 0)
			var mining_drone_id2: int = TypedVariant.as_int(ship_data.get("mining_drone_id", 0), 0)
			var bay_slots: int = _ship_drone_bay_slots(ship_data)
			if mining_drone_id2 > 0:
				var n_mine: int = TypedVariant.as_int(ship_data.get("mining_drone_count", bay_slots if bay_slots > 0 else 4), 0)
				var mine_data: Dictionary = DataStore.get_ship(mining_drone_id2)
				var per_base: int = TypedVariant.as_int(mine_data.get("mining_gold_per_round", 25), 0)
				var per: int = per_base * maxi(star, 1)
				var full: float = per * n_mine
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
			elif TypedVariant.as_bool(ship_data.get("is_mining_ship", false), false):
				if drone_panel:
					drone_panel.visible = false
				if drone_icon:
					drone_icon.texture = null
				if drone_label:
					drone_label.text = ""
			elif fighter_id > 0:
				var squads: int = TypedVariant.as_int(ship_data.get("fighter_squadrons", 3), 0)
				var tubes: int = TypedVariant.as_int(ship_data.get("fighter_tubes_per_squadron", 3), 0)
				var n_fighters: int = squads * tubes
				var fighter_data: Dictionary = DataStore.get_ship(fighter_id)
				var fighter_star: Dictionary = DataStore.get_star(fighter_id, maxi(star, 1))
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
				var n_rep: int = TypedVariant.as_int(ship_data.get("heavy_repair_drone_count", 4), 0)
				var rep_data: Dictionary = DataStore.get_ship(repair_id)
				var rep_star: Dictionary = DataStore.get_star(repair_id, maxi(star, 1))
				if drone_panel:
					drone_panel.visible = true
				if drone_icon:
					drone_icon.texture = UiAssets.drone_portrait(repair_id)
					if drone_icon.texture == null:
						var rep_path: String = str(rep_data.get("portrait", ""))
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
					var drone_id: int = _race_drone_id(ship_data)
					var drone_data: Dictionary = DataStore.get_ship(drone_id)
					var drone_star: Dictionary = DataStore.get_star(drone_id, maxi(star, 1))
					if drone_icon:
						drone_icon.texture = UiAssets.drone_portrait(drone_id)
					if drone_label:
						var drone_name: String = str(drone_data.get("name", "无人机"))
						drone_label.text = "%s ×%d\n%s" % [
							drone_name,
							bay_slots,
							_drone_stats_text(drone_data, drone_star)
						]
						_style_info_stat_label(drone_label)
	_fill_info_function_modules(weapon_col.get("function_list"), ship_data, is_titan_info)
	if fetter_box:
		for c: Node in fetter_box.get_children():
			c.queue_free()
		for fid: Variant in fetter_ids:
			var fdata: Dictionary = DataStore.fetters.get(str(fid), {})
			var fname: String = str(fdata.get("name", fid))
			var row: HBoxContainer = HBoxContainer.new()
			var fic: TextureRect = TextureRect.new()
			fic.custom_minimum_size = Vector2(UiLayout.px(18 if UiLayout.is_mobile() else 22, self), UiLayout.px(18 if UiLayout.is_mobile() else 22, self))
			fic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var ft: Texture2D = UiAssets.fetter_icon(str(fid), fname)
			if ft:
				fic.texture = ft
			row.add_child(fic)
			var fl: Label = Label.new()
			fl.text = fname
			UiAssets.apply_label_font(fl, false, 15)
			row.add_child(fl)
			fetter_box.add_child(row)
	if sh:
		sh.text = _hp_line("护盾", shield_txt, TypedVariant.as_dict(star_data.get("shield_resist", {})))
		UiAssets.apply_label_font(sh, false, 16)
	if ar:
		ar.text = _hp_line("装甲", armor_txt, TypedVariant.as_dict(star_data.get("armor_resist", {})))
		UiAssets.apply_label_font(ar, false, 16)
	if st:
		st.text = _hp_line("结构", structure_txt, TypedVariant.as_dict(star_data.get("structure_resist", {})))
		UiAssets.apply_label_font(st, false, 16)
	if dm:
		dm.visible = false
	if rg:
		rg.visible = false
	if extra:
		extra.text = _base_stats_text(ship_data, live)
		UiAssets.apply_label_font(extra, false, 15)
	p.visible = true
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
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
	## Refresh fetter multipliers before reading runtime stats into InfoPanel.
	if board != null and ship.slot_type == "field":
		board.recalculate_fetters(TypedVariant.as_int(ship.team_id, 0))
	var data: Dictionary = DataStore.get_ship(ship.ship_id)
	var st: Dictionary = DataStore.get_star_resolved(ship.ship_id, ship.star)
	var shield_txt: String = "%.0f/%.0f" % [ship.shield_hp, ship.max_shield]
	var armor_txt: String = "%.0f/%.0f" % [ship.armor_hp, ship.max_armor]
	var structure_txt: String = "%.0f/%.0f" % [ship.structure_hp, ship.max_structure]
	var pipes: TitanHpPipes = _pipes_for_berth_unit(ship)
	if pipes:
		shield_txt = "%d/%d" % [pipes.shield, pipes.shield_max]
		armor_txt = "%d/%d" % [pipes.armor, pipes.armor_max]
		structure_txt = "%d/%d" % [pipes.structure, pipes.structure_max]
	_fill_info_panel(
		str(data.get("name", "?")),
		ship.star,
		shield_txt,
		armor_txt,
		structure_txt,
		ship.damage_dict_scaled(),
		ship.attack_range,
		TypedVariant.as_array(data.get("fetter_ids", [])),
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
		_exit_observe_keep_view()
	var st: Dictionary = DataStore.get_star_resolved(ship_id, 1)
	var data: Dictionary = DataStore.get_ship(ship_id)
	var dmg: Dictionary = st.get("damage", {})
	var armor: float = TypedVariant.as_float(st.get("armor_hp", 0), 0.0)
	var structure: float = TypedVariant.as_float(st.get("structure_hp", maxf(50.0, roundf(armor * 0.5))), maxf(50.0, roundf(armor * 0.5)))
	_fill_info_panel(
		str(data.get("name", "?")),
		1,
		str(st.get("shield_hp", 0)),
		str(st.get("armor_hp", 0)),
		str(int(structure)),
		dmg,
		TypedVariant.as_float(st.get("attack_range", 0), 0.0),
		TypedVariant.as_array(data.get("fetter_ids", [])),
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
		_exit_observe_keep_view()
	@warning_ignore("unsafe_cast")
	var p: PanelContainer = hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
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
	var delay: float = TypedVariant.as_float(DataStore.match_flow.get("death_return_delay_s", 3), 0.0)
	await get_tree().create_timer(delay).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _show_nullsec_settlement(summary: String) -> void:
	_nullsec_prepare_pending = false
	_nullsec_prepare_ui_pending = false
	## Do not clear _doomsday_busy — wait for beam/kill, then flush.
	if _doomsday_busy or _titan_kill_busy or _titan_kill_active > 0:
		_settlement_pending_summary = summary
		return
	_present_nullsec_settlement(summary)


func _flush_pending_settlement_if_ready() -> void:
	if _settlement_pending_summary == "":
		return
	if _doomsday_busy or _titan_kill_busy or _titan_kill_active > 0:
		return
	var s: String = _settlement_pending_summary
	_settlement_pending_summary = ""
	_present_nullsec_settlement(s)


func _wld_tuple(seat: int) -> Dictionary:
	var d: Dictionary = TypedVariant.as_dict(_wld_by_seat.get(seat, {}))
	return {
		"w": TypedVariant.as_int(d.get("w", 0), 0),
		"l": TypedVariant.as_int(d.get("l", 0), 0),
		"d": TypedVariant.as_int(d.get("d", 0), 0),
	}


func _present_nullsec_settlement(summary: String) -> void:
	var ships: Array = []
	if board:
		for s: ShipUnit in board.all_ships():
			if s == null or not is_instance_valid(s) or s.is_unmanned:
				continue
			if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_PLAYER:
				continue
			ships.append({"ship_id": TypedVariant.as_int(s.ship_id, 0), "star": TypedVariant.as_int(s.star, 1)})
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), -1)
	var nick: String = "本地"
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) == local_seat:
			nick = str(s.get("nick", nick))
			break
	var gold_earned: int = TypedVariant.as_int(match_ctrl.player_gold_earned, 0) if match_ctrl else 0
	var my_titles: Array = TypedVariant.as_array(_match_titles.get(local_seat, []))
	var wld: Dictionary = _wld_tuple(local_seat)
	var elim: int = 0
	if _doomsday_resolver:
		elim = TypedVariant.as_int(_doomsday_resolver.elimination_order.get(local_seat, 0), 0)
	var result: String = "淘汰" if elim > 0 else "存活"
	if not _seat_titan_alive(local_seat):
		result = "淘汰"
	var kills: int = TypedVariant.as_int(_kills_by_seat.get(local_seat, 0), 0)
	var row: Dictionary = NullsecSettlement.make_row(
		nick,
		TypedVariant.as_int(match_ctrl.player_level, 1) if match_ctrl else 1,
		gold_earned,
		result,
		ships,
		my_titles,
		local_seat,
		TypedVariant.as_int(wld.get("w", 0), 0),
		TypedVariant.as_int(wld.get("l", 0), 0),
		TypedVariant.as_int(wld.get("d", 0), 0),
		0,
		kills,
		false,
		false
	)
	row["elimination_order"] = elim
	if _settlement_panel == null:
		_settlement_panel = NullsecSettlementPanel.new()
		hud.add_child(_settlement_panel)
	_settlement_panel.confirmed.connect(func() -> void:
		NullsecRejoinTicket.clear()
		var net_close: NullsecNetSession = _nullsec_net_session()
		if net_close and net_close.has_method("clear_ghosts_after_settlement"):
			net_close.clear_ghosts_after_settlement()
		if net_close:
			net_close.close()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	, CONNECT_ONE_SHOT)
	var rows: Array = []
	var seen_seats: Dictionary = {}
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if NullsecNetSession.is_spectate_race(str(s.get("titan_race", ""))):
			continue
		if not NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			continue
		var seat_id: int = TypedVariant.as_int(s.get("seat_id", -1), -1)
		if seat_id < 0 or TypedVariant.as_bool(seen_seats.get(seat_id, false), false):
			continue
		seen_seats[seat_id] = true
		if seat_id == local_seat:
			rows.append(row)
			continue
		var snick: String = str(s.get("nick", "席位%d" % seat_id))
		var owld: Dictionary = _wld_tuple(seat_id)
		var oelim: int = 0
		if _doomsday_resolver:
			oelim = TypedVariant.as_int(_doomsday_resolver.elimination_order.get(seat_id, 0), 0)
		var orow: Dictionary = NullsecSettlement.make_row(
			snick,
			1,
			0,
			"淘汰" if oelim > 0 else "—",
			[],
			TypedVariant.as_array(_match_titles.get(seat_id, [])),
			seat_id,
			TypedVariant.as_int(owld.get("w", 0), 0),
			TypedVariant.as_int(owld.get("l", 0), 0),
			TypedVariant.as_int(owld.get("d", 0), 0),
			0,
			TypedVariant.as_int(_kills_by_seat.get(seat_id, 0), 0),
			TypedVariant.as_bool(s.get("is_ai", false), false),
			true
		)
		orow["elimination_order"] = oelim
		orow["ghost"] = TypedVariant.as_bool(s.get("ghost", false), false)
		rows.append(orow)
	if not TypedVariant.as_bool(seen_seats.get(local_seat, false), false):
		rows.insert(0, row)
	rows = NullsecSettlement.assign_ranks(rows, _nullsec_rng)
	var net: NullsecNetSession = _nullsec_net_session()
	if net:
		if not net.match_report_received.is_connected(_on_nullsec_match_report_received):
			net.match_report_received.connect(_on_nullsec_match_report_received, CONNECT_ONE_SHOT)
		## Refresh local row after rank assign.
		for r_v: Variant in rows:
			var r: Dictionary = TypedVariant.as_dict(r_v)
			if TypedVariant.as_int(r.get("seat_id", -1), -1) == local_seat:
				net.submit_local_match_summary(r)
				break
	_settlement_panel.show_rows(rows)
	show_notice(summary)

func _on_nullsec_match_report_received(report: Dictionary) -> void:
	## Host-collected §7 report (every contestant's own titles/summary) supersedes the
	## local-only fallback rows shown the instant combat ended.
	if _settlement_panel and is_instance_valid(_settlement_panel):
		_settlement_panel.show_report(report)

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
	var cost: int = TypedVariant.as_int(DataStore.economy.get("buy_exp_gold_cost", 4), 0)
	if match_ctrl == null or match_ctrl.player_gold < cost:
		return false
	var before: int = match_ctrl.player_gold
	match_ctrl.buy_exp()
	_refresh_hud()
	return match_ctrl.player_gold < before

func _player_hp_label_text() -> String:
	## Nullsec lives = titan three pipes, not the citadel formula (MULTIPLAYER_PVP §2.4).
	if GameSession.pending_mode == "nullsec":
		var pipes: TitanHpPipes = _local_titan_pipes()
		if pipes == null:
			return ""
		return "泰坦 盾%d · 甲%d · 结构%d" % [pipes.shield, pipes.armor, pipes.structure]
	return "我 %d  ·  敌 %d" % [match_ctrl.player_hp, match_ctrl.ai_hp]

func _apply_match_save() -> void:
	_apply_match_save_dict(MatchSave.load_dict())

func _apply_match_save_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	## Keep MatchController / GameSession / AI endless flag aligned with the snapshot.
	var solo_mode: String = MatchSave.normalize_solo_mode(d.get("mode", ""))
	if solo_mode != "":
		match_ctrl.mode = solo_mode
		GameSession.pending_mode = solo_mode
		if ai:
			ai.endless = solo_mode == "endless"
	var p: Dictionary = d.get("player", {})
	match_ctrl.player_gold = TypedVariant.as_int(p.get("gold", match_ctrl.player_gold), 0)
	match_ctrl.player_hp = TypedVariant.as_int(p.get("hp", match_ctrl.player_hp), 0)
	match_ctrl.player_max_hp = TypedVariant.as_int(p.get("max_hp", match_ctrl.player_max_hp), 0)
	match_ctrl.player_level = maxi(1, TypedVariant.as_int(p.get("level", match_ctrl.player_level), 0))
	match_ctrl.player_exp = maxi(0, TypedVariant.as_int(p.get("exp", match_ctrl.player_exp), 0))
	## Heal inconsistent / legacy saves: demand must match level curve.
	var expected_demand: int = MatchController.exp_demand_for_level(match_ctrl.player_level)
	var saved_demand: int = TypedVariant.as_int(p.get("up_level_demand", 0), 0)
	match_ctrl.up_level_demand = expected_demand if saved_demand != expected_demand else saved_demand
	## Apply any overflow XP that was saved against a wrong demand.
	var inc: int = TypedVariant.as_int(DataStore.economy.get("level_exp_demand_increment", 8), 0)
	while match_ctrl.player_exp >= match_ctrl.up_level_demand and match_ctrl.up_level_demand > 0:
		match_ctrl.player_exp -= match_ctrl.up_level_demand
		match_ctrl.player_level += 1
		match_ctrl.up_level_demand += inc
	match_ctrl.win_streak = TypedVariant.as_int(p.get("win_streak", 0), 0)
	match_ctrl.loss_streak = TypedVariant.as_int(p.get("loss_streak", 0), 0)
	match_ctrl.shop_locked = TypedVariant.as_bool(p.get("shop_locked", false), false)
	match_ctrl.battle_game_stage_count = TypedVariant.as_int(d.get("battle_game_stage_count", 0), 0)
	match_ctrl.round_phase_value = TypedVariant.as_int(d.get("round_phase_value", 1), 0)
	match_ctrl.battle_phase_value = TypedVariant.as_int(d.get("battle_phase_value", 0), 0)
	if shop and p.has("shop_slots"):
		var restored: Array = _normalize_shop_slots(p.get("shop_slots", []))
		## Empty shop_slots in legacy/bad saves must not wipe a freshly rolled shop.
		if restored.is_empty():
			shop.refresh_shop(true, false)
		else:
			shop.slots = restored
			shop.shop_changed.emit()
	elif shop and (shop.slots.is_empty()):
		shop.refresh_shop(true, false)
	if shop:
		if p.has("equipment_shop_slots"):
			shop.equipment_slots = _normalize_equipment_shop_slots(p.get("equipment_shop_slots", []))
		if shop.equipment_slots.is_empty() and shop.has_method("ensure_equipment_slots"):
			shop.ensure_equipment_slots()
	if p.has("equipment_inventory"):
		match_ctrl.equipment_inventory = _normalize_equipment_inventory(p.get("equipment_inventory", []))
		match_ctrl.ensure_equipment_inventory_size()
	elif match_ctrl.has_method("ensure_equipment_inventory_size"):
		match_ctrl.ensure_equipment_inventory_size()
	var a: Dictionary = d.get("ai", {})
	match_ctrl.ai_hp = TypedVariant.as_int(a.get("hp", match_ctrl.ai_hp), 0)
	match_ctrl.ai_max_hp = TypedVariant.as_int(a.get("max_hp", match_ctrl.ai_max_hp), 0)
	if ai:
		ai.ai_gold = TypedVariant.as_int(a.get("gold", ai.ai_gold), 0)
		ai.ai_level = maxi(1, TypedVariant.as_int(a.get("level", ai.ai_level), 0))
		ai.ai_exp = maxi(0, TypedVariant.as_int(a.get("exp", ai.ai_exp), 0))
		var ai_expected: int = MatchController.exp_demand_for_level(ai.ai_level)
		var ai_saved: int = TypedVariant.as_int(a.get("up_level_demand", 0), 0)
		ai.up_level_demand = ai_expected if ai_saved != ai_expected else ai_saved
		var ai_inc: int = TypedVariant.as_int(DataStore.economy.get("level_exp_demand_increment", 8), 0)
		while ai.ai_exp >= ai.up_level_demand and ai.up_level_demand > 0:
			ai.ai_exp -= ai.up_level_demand
			ai.ai_level += 1
			ai.up_level_demand += ai_inc
		ai.win_streak = TypedVariant.as_int(a.get("win_streak", 0), 0)
		ai.loss_streak = TypedVariant.as_int(a.get("loss_streak", 0), 0)
		ai.shop_slots = _normalize_shop_slots(a.get("shop_slots", ai.shop_slots))
	board.reset_match()
	_redeploy_saved_ships(TypedVariant.as_array(d.get("ships", [])))
	## start_match already ran AI economy on an empty board; after redeploy, fill field again.
	if ai and ai.has_method("sync_field_for_prepare"):
		ai.sync_field_for_prepare()
	_refresh_citadel_bar()
	_refresh_hud()
	show_notice("已继续上次对局（空堡 HP 我%d/敌%d）" % [match_ctrl.player_hp, match_ctrl.ai_hp])


func _normalize_shop_slots(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for e_v: Variant in raw:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = TypedVariant.as_dict(e_v)
		var slot: Dictionary = e
		out.append({
			"ship_id": TypedVariant.as_int(slot.get("ship_id", 0), 0),
			"purchased": TypedVariant.as_bool(slot.get("purchased", false), false),
		})
	return out


func _normalize_equipment_shop_slots(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for e_v: Variant in raw:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = TypedVariant.as_dict(e_v)
		var slot: Dictionary = e
		out.append({
			"id": str(slot.get("id", "")),
			"purchased": TypedVariant.as_bool(slot.get("purchased", false), false),
		})
	return out


func _normalize_equipment_inventory(raw: Variant) -> Array[String]:
	## Must return typed Array[String] — Godot rejects assigning plain Array onto MatchController.equipment_inventory.
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		while out.size() < MatchController.EQUIPMENT_INVENTORY_SIZE:
			out.append("")
		return out
	for e: Variant in raw:
		out.append(str(e))
	while out.size() < MatchController.EQUIPMENT_INVENTORY_SIZE:
		out.append("")
	if out.size() > MatchController.EQUIPMENT_INVENTORY_SIZE:
		out.resize(MatchController.EQUIPMENT_INVENTORY_SIZE)
	return out

func _redeploy_saved_ships(ships: Array) -> void:
	for entry_v: Variant in ships:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = TypedVariant.as_dict(entry_v)
		var sid: int = TypedVariant.as_int(entry.get("ship_id", 0), 0)
		if sid <= 0:
			continue
		if DataStore.get_ship(sid).is_empty():
			continue
		AdminBus.request(&"board.deploy", {
			"ship_id": sid,
			"star": TypedVariant.as_int(entry.get("star", 1), 0),
			"team": TypedVariant.as_int(entry.get("team", ShipUnit.TEAM_PLAYER), 0),
			"slot_type": str(entry.get("slot_type", "hangar")),
			"x": TypedVariant.as_int(entry.get("x", 0), 0),
			"z": TypedVariant.as_int(entry.get("z", 0), 0),
			## Preserve exact save roster — do not merge 3×same into upgrades mid-redeploy.
			"skip_upgrade": true,
		})
		var deployed: bool = false
		for s2: ShipUnit in board.all_ships():
			if s2.ship_id == sid and s2.grid_x == TypedVariant.as_int(entry.get("x", 0), 0) and s2.grid_z == TypedVariant.as_int(entry.get("z", 0), 0) and s2.slot_type == str(entry.get("slot_type", "hangar")) and s2.team_id == TypedVariant.as_int(entry.get("team", ShipUnit.TEAM_PLAYER), 0):
				if TypedVariant.as_int(entry.get("field_side_team", -1), 0) >= 0:
					s2.field_side_team = TypedVariant.as_int(entry.get("field_side_team"), 0)
					if s2.slot_type == "field":
						s2.global_position = BoardController.cell_to_world("field", s2.field_side_team, s2.grid_x, s2.grid_z)
				deployed = true
				break
		if not deployed:
			## Legacy saves may still list cyno hulls on field — park them in hangar.
			var sd: Dictionary = DataStore.get_ship(sid)
			if TypedVariant.as_bool(sd.get("requires_cyno_entry", false), false) and str(entry.get("slot_type", "")) == "field":
				var hang: Vector2i = board.find_empty_hangar(TypedVariant.as_int(entry.get("team", ShipUnit.TEAM_PLAYER), 0))
				if hang.x >= 0:
					var r2: Dictionary = AdminBus.request(&"board.deploy", {
						"ship_id": sid,
						"star": TypedVariant.as_int(entry.get("star", 1), 0),
						"team": TypedVariant.as_int(entry.get("team", ShipUnit.TEAM_PLAYER), 0),
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
		@warning_ignore("unsafe_cast")
		var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
		_speed_dropdown.refresh_list(seats)
		@warning_ignore("unsafe_cast")
		var btn: Button = hud.get_node_or_null("Root/TopRight/SpeedBtn") as Button
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
	var allow_pause: bool = GameSession == null or str(GameSession.pending_mode) != "nullsec"
	if allow_pause and not get_tree().paused:
		get_tree().paused = true
		@warning_ignore("unsafe_cast")
		var pause_btn: Button = hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
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
		@warning_ignore("unsafe_cast")
		var pause_btn: Button = hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
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
	@warning_ignore("unsafe_cast")
	var box: VBoxContainer = _game_menu.get_node("Margin/VBox") as VBoxContainer
	var title: Label = Label.new()
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
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, UiLayout.px(44, self))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_button_font(btn, UiLayout.font_size(18, self))
	btn.pressed.connect(cb)
	return btn


func _make_modal_panel(p_name: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = p_name
	panel.visible = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	sb.border_color = Color(0.35, 0.72, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	var m: int = UiLayout.margin_px(16, self)
	margin.add_theme_constant_override("margin_left", m)
	margin.add_theme_constant_override("margin_right", m)
	margin.add_theme_constant_override("margin_top", m)
	margin.add_theme_constant_override("margin_bottom", m)
	panel.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
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
	var panel: Control = _make_modal_panel("MatchSettingsPanel")
	@warning_ignore("unsafe_cast")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "设置"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back: Button = Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func() -> void:
		panel.visible = false
		if _game_menu:
			_game_menu.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var fps_cap: Label = Label.new()
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

	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	var bgm: BgMusic = _BgMusic.instance() as BgMusic
	var bgm_on_row: HBoxContainer = HBoxContainer.new()
	_bgm_check = CheckBox.new()
	_bgm_check.text = "背景音乐"
	_bgm_check.button_pressed = bgm.enabled if bgm else false
	UiAssets.apply_button_font(_bgm_check, UiLayout.font_size(16, self))
	_bgm_check.toggled.connect(_on_match_bgm_toggled)
	bgm_on_row.add_child(_bgm_check)
	box.add_child(bgm_on_row)

	var nomodel: CheckBox = CheckBox.new()
	nomodel.text = "无模型性能模式（亦关血条特效）"
	nomodel.button_pressed = GameSession.no_model_perf_mode
	UiAssets.apply_button_font(nomodel, UiLayout.font_size(16, self))
	nomodel.toggled.connect(func(on: bool) -> void: GameSession.set_no_model_perf_mode(on))
	box.add_child(nomodel)

	var breathe: CheckBox = CheckBox.new()
	breathe.text = "镜头呼吸浮动"
	breathe.button_pressed = GameSession.camera_breathe_enabled
	UiAssets.apply_button_font(breathe, UiLayout.font_size(16, self))
	breathe.toggled.connect(func(on: bool) -> void: GameSession.set_camera_breathe_enabled(on))
	box.add_child(breathe)

	var hp_row: HBoxContainer = HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var hp_cap: Label = Label.new()
	hp_cap.text = "血量展示"
	UiAssets.apply_label_font(hp_cap, false, UiLayout.font_size(16, self))
	hp_row.add_child(hp_cap)
	var hp_opt: OptionButton = OptionButton.new()
	hp_opt.add_item("环形血量展示", 0)
	hp_opt.add_item("四条血量展示", 1)
	hp_opt.select(1 if str(GameSession.get("health_bar_style")) == "bars" else 0)
	UiAssets.apply_button_font(hp_opt, UiLayout.font_size(16, self))
	hp_opt.item_selected.connect(_on_match_health_bar_style_selected)
	hp_row.add_child(hp_opt)
	box.add_child(hp_row)

	var bgm_vol_row: HBoxContainer = HBoxContainer.new()
	bgm_vol_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var bgm_cap: Label = Label.new()
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

	var export_btn: Button = Button.new()
	export_btn.text = "导出 debug 日志"
	export_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(export_btn, UiLayout.font_size(16, self))
	export_btn.pressed.connect(_export_debug_log_clicked)
	box.add_child(export_btn)

	var verify_btn: Button = Button.new()
	verify_btn.text = "核实版本是否最新"
	verify_btn.tooltip_text = "主动检查远端是否有新内容；将离开对局回到 Boot 验版"
	verify_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(verify_btn, UiLayout.font_size(16, self))
	verify_btn.pressed.connect(_on_verify_content_version)
	box.add_child(verify_btn)

	var dev_btn: Button = Button.new()
	dev_btn.text = "开发者调试"
	dev_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	UiAssets.apply_button_font(dev_btn, UiLayout.font_size(16, self))
	dev_btn.pressed.connect(_open_developer_panel)
	box.add_child(dev_btn)
	return panel


func _build_match_developer_panel() -> Control:
	var panel: Control = _make_modal_panel("MatchDeveloperPanel")
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	@warning_ignore("unsafe_cast")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "开发者调试"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back: Button = Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func() -> void:
		panel.visible = false
		if _game_menu_settings:
			_game_menu_settings.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)

	var hint: Label = Label.new()
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

	var swap_btn: Button = Button.new()
	swap_btn.text = "换边（双方棋子中心对称交换）"
	swap_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	swap_btn.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(swap_btn, UiLayout.font_size(16, self))
	swap_btn.pressed.connect(_on_match_dev_swap_sides)
	swap_btn.name = "DevSwapSidesBtn"
	box.add_child(swap_btn)

	var ship_data_btn: Button = Button.new()
	ship_data_btn.text = "全舰船装备数据调整（暂停对局）"
	ship_data_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	ship_data_btn.disabled = not GameSession.developer_debug_enabled
	UiAssets.apply_button_font(ship_data_btn, UiLayout.font_size(16, self))
	ship_data_btn.pressed.connect(_on_match_dev_ship_data)
	ship_data_btn.name = "DevShipDataBtn"
	box.add_child(ship_data_btn)
	return panel


func _export_debug_log_clicked() -> void:
	var res: Dictionary = SessionDiagnostics.export_session_log()
	if TypedVariant.as_bool(res.get("ok", false), false):
		show_notice("已导出并复制路径: %s" % str(res.get("path", "")))
	else:
		var reason: String = str(res.get("reason", ""))
		if reason == "no_log":
			show_notice("尚无会话日志")
		else:
			show_notice("导出失败（%s）" % reason)


func _on_verify_content_version() -> void:
	if GameSession and GameSession.has_method("request_verify_content_version"):
		GameSession.request_verify_content_version()
	else:
		show_notice("当前壳不支持主动验版（需 202608.4.3+）")


func _build_save_panel() -> Control:
	var panel: Control = _make_modal_panel("MatchSavePanel")
	@warning_ignore("unsafe_cast")
	var box: VBoxContainer = panel.get_node("Margin/VBox") as VBoxContainer
	var cap_row: HBoxContainer = HBoxContainer.new()
	var cap: Label = Label.new()
	cap.text = "保存当前局为存档"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_label_font(cap, true, UiLayout.font_size(22, self))
	cap_row.add_child(cap)
	var back: Button = Button.new()
	back.text = "返回"
	UiAssets.apply_button_font(back, UiLayout.font_size(16, self))
	back.pressed.connect(func() -> void:
		panel.visible = false
		if _game_menu:
			_game_menu.visible = true
	)
	cap_row.add_child(back)
	box.add_child(cap_row)
	var hint: Label = Label.new()
	hint.text = "写入命名槽，可在主菜单「读取存档」加载；不覆盖旗舰测试。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_label_font(hint, false, UiLayout.font_size(14, self))
	box.add_child(hint)
	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "存档名称"
	_save_name_edit.add_theme_font_size_override("font_size", UiLayout.font_size(16, self))
	box.add_child(_save_name_edit)
	var confirm: Button = _menu_action_btn("确认保存", _confirm_save_named_slot)
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
	var master_on: bool = GameSession.developer_debug_enabled
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
		@warning_ignore("unsafe_cast")
		var swap_btn: Button = _game_menu_dev.find_child("DevSwapSidesBtn", true, false) as Button
		if swap_btn:
			swap_btn.disabled = not master_on
		@warning_ignore("unsafe_cast")
		var ship_btn: Button = _game_menu_dev.find_child("DevShipDataBtn", true, false) as Button
		if ship_btn:
			ship_btn.disabled = not master_on


func _on_match_dev_master_toggled(on: bool) -> void:
	GameSession.set_developer_debug_enabled(on)
	SessionDiagnostics.log("dev.debug", "on=%s" % on)
	if _dev_soften_check:
		_dev_soften_check.disabled = not on
	if _dev_economy_check:
		_dev_economy_check.disabled = not on
	if _dev_enemy_layout_check:
		_dev_enemy_layout_check.disabled = not on
	if _game_menu_dev:
		@warning_ignore("unsafe_cast")
		var swap_btn: Button = _game_menu_dev.find_child("DevSwapSidesBtn", true, false) as Button
		if swap_btn:
			swap_btn.disabled = not on
		@warning_ignore("unsafe_cast")
		var ship_btn: Button = _game_menu_dev.find_child("DevShipDataBtn", true, false) as Button
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
	if TypedVariant.as_bool(r.get("ok", false), false):
		show_notice("已换边（%d 艘）" % TypedVariant.as_int(r.get("count", 0), 0))
		_refresh_hud()
	else:
		show_notice("换边仅备战阶段可用" if str(r.get("reason", "")) == "prepare_only" else "换边失败")


## UI_AND_SHELL §2.5.1 — pauses the match; guests in a net match may not edit (host authority).
func _on_match_dev_ship_data() -> void:
	if not GameSession.developer_debug_enabled:
		return
	var net: NullsecNetSession = _nullsec_net_session()
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
	SessionDiagnostics.log("editor.open", "match")


func _on_ship_data_editor_closed(changed_ids: Array, equipment_changed: bool = false) -> void:
	SessionDiagnostics.log("editor.close", "changed=%d eq=%s" % [changed_ids.size(), equipment_changed])
	if changed_ids.is_empty() and not equipment_changed:
		if _game_menu_dev:
			_game_menu_dev.visible = true
		return
	var what: String = "已保存 %d 艘舰船数据" % changed_ids.size() if not changed_ids.is_empty() else "已保存装备数据"
	if not changed_ids.is_empty() and equipment_changed:
		what = "已保存 %d 艘舰船与装备数据" % changed_ids.size()
	show_notice(what)
	## Host edits are authoritative mid-match — push the table to guests at once (§3.7).
	## Equipment counts: manned DPH derives from it (SHIP_STATS_V2 §2.2).
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and net.is_host and net.match_started:
		net.broadcast_ships_table()
		show_notice("%s并同步给房客" % what)
	if _game_menu_dev:
		_game_menu_dev.visible = true


## Guest side of SEMI_ASYNC_NETPLAY §3.7 — host table landed (join or mid-match edit).
func _on_host_ships_applied(mid_match: bool) -> void:
	show_notice("房主已更新舰船数据 · 已作对局临时材料" if mid_match else "已使用房主舰船数据作对局临时材料（不覆盖本地）")
	_refresh_hud()


func _on_match_terminated_host_lost(reason: String) -> void:
	SessionDiagnostics.log("net.terminate", str(reason))
	NullsecRejoinTicket.clear()
	show_notice(reason if reason != "" else "房主掉线，对局终止")
	get_tree().paused = false
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_nullsec_host_migrated(generation: int, new_host_seat: int) -> void:
	SessionDiagnostics.log("net.host_migrate", "gen=%d seat=%d" % [generation, new_host_seat])
	GameSession.pending_nullsec["host_seat"] = new_host_seat
	var net: NullsecNetSession = _nullsec_net_session()
	if net:
		net.write_rejoin_ticket()
		if _net_battle and _net_battle.has_method("refresh_host_role"):
			_net_battle.refresh_host_role()
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	if new_host_seat == local_seat:
		show_notice("你已成为新房主 · 继续主持对局（迁移 #%d）" % generation)
	else:
		show_notice("房主已迁移 · 席位 %d 接手（#%d）" % [new_host_seat + 1, generation])


func _nullsec_net_session() -> NullsecNetSession:
	if GameSession == null:
		return null
	return GameSession.get_node_or_null("NullsecNetSession") as NullsecNetSession


func _open_save_panel() -> void:
	if _game_menu:
		_game_menu.visible = false
	if _save_name_edit:
		var mode_key: String = str(match_ctrl.mode) if match_ctrl else str(GameSession.pending_mode)
		var mode_l: String = "对战" if mode_key == "versus" else ("无尽" if mode_key == "endless" else mode_key)
		_save_name_edit.text = "%s · 第%d回合 · Lv%d" % [
			mode_l,
			maxi(1, match_ctrl.battle_game_stage_count if match_ctrl else 1),
			match_ctrl.player_level if match_ctrl else 1,
		]
	if _game_menu_save:
		_game_menu_save.visible = true


func _confirm_save_named_slot() -> void:
	var slot_name: String = _save_name_edit.text if _save_name_edit else ""
	var r: Dictionary = MatchSave.save_as_named_slot(slot_name, match_ctrl, board, ai)
	if TypedVariant.as_bool(r.get("ok", false), false):
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
	SessionDiagnostics.log("match.leave", "mode=%s" % str(GameSession.pending_mode))
	if match_ctrl and match_ctrl.has_method("force_autosave"):
		match_ctrl.force_autosave()
	if GameSession.pending_mode == "nullsec":
		var net: NullsecNetSession = _nullsec_net_session()
		if net:
			net.request_mark_local_ghost()
			net.write_rejoin_ticket()
			net.close()
	_close_game_menu()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _sync_game_menu_settings_widgets() -> void:
	if _fps_slider:
		_fps_slider.value = GameSession.target_fps
	if _fps_lbl:
		_fps_lbl.text = str(int(GameSession.target_fps))
	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	var bgm: BgMusic = _BgMusic.instance() as BgMusic
	if _bgm_check and bgm:
		_bgm_check.button_pressed = bgm.enabled
	if _bgm_slider and bgm:
		_bgm_slider.value = bgm.volume_pct
	if _bgm_lbl and bgm:
		_bgm_lbl.text = str(int(bgm.volume_pct))


func _on_match_fps_changed(v: float) -> void:
	if GameSession.has_method("set_target_fps"):
		GameSession.set_target_fps(int(v))
	else:
		GameSession.target_fps = int(v)
		Engine.max_fps = GameSession.target_fps
		GameSession.save_settings()
	if _fps_lbl:
		_fps_lbl.text = str(GameSession.target_fps)


## Mid-match no-model toggle: refresh existing ships + asteroid visuals (UI_AND_SHELL).
func apply_no_model_perf_mode_changed() -> void:
	apply_no_model_perf_cleanup()
	if board != null:
		for s: ShipUnit in board.all_ships():
			if s == null or not is_instance_valid(s):
				continue
			s.refresh_visual_for_no_model_mode()
	var belt: AsteroidBelt = _find_match_asteroid_belt()
	if belt != null:
		belt.apply_no_model_visibility()
	rebuild_all_ship_health_bars()
	## Berth titans keep meshes; refresh pipe bars in case of prior no-model damage.
	_refresh_titan_hp_bar()


## Mid-match toggle: drop trails / active weapon FX (settlement + float text stay).
func apply_no_model_perf_cleanup() -> void:
	if not GameSession.no_model_perf_mode:
		return
	if firing_fx != null and firing_fx.has_method("clear_all"):
		@warning_ignore("unsafe_method_access")
		firing_fx.clear_all()
	if board == null:
		return
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		var trail: Node = s.get_node_or_null(EngineBoosterTrail.ROOT_NAME)
		if trail != null:
			trail.queue_free()


func _find_match_asteroid_belt() -> AsteroidBelt:
	var n: Node3D = _nullsec_belt_root()
	if n is AsteroidBelt:
		return n as AsteroidBelt
	return null


func _on_match_bgm_toggled(on: bool) -> void:
	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	var bgm: BgMusic = _BgMusic.instance() as BgMusic
	if bgm:
		bgm.set_enabled(on)

func _on_match_health_bar_style_selected(idx: int) -> void:
	var style: String = "bars" if idx == 1 else "ring"
	if GameSession.has_method("set_health_bar_style"):
		GameSession.set_health_bar_style(style)
	else:
		GameSession.set("health_bar_style", style)
		if GameSession.has_method("save_settings"):
			GameSession.save_settings()
	rebuild_all_ship_health_bars()


func _on_match_bgm_volume_changed(v: float) -> void:
	if _bgm_lbl:
		_bgm_lbl.text = str(int(v))
	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	var bgm: BgMusic = _BgMusic.instance() as BgMusic
	if bgm:
		bgm.set_volume_pct(v)


func _on_pause_pressed() -> void:
	## Nullsec has no pause (UI_AND_SHELL §2.2A).
	if GameSession != null and str(GameSession.pending_mode) == "nullsec":
		return
	if _game_menu_open():
		return
	get_tree().paused = not get_tree().paused
	@warning_ignore("unsafe_cast")
	var btn: Button = hud.get_node_or_null("Root/TopRight/PauseBtn") as Button
	if btn:
		btn.text = "继续" if get_tree().paused else "暂停"
	show_notice("已暂停" if get_tree().paused else "继续")

func _on_collapse_left() -> void:
	_hud_interact_ms = Time.get_ticks_msec()
	_collapse_left = not _collapse_left
	_apply_adaptive_hud_layout()

func _on_collapse_right() -> void:
	_hud_interact_ms = Time.get_ticks_msec()
	_collapse_right = not _collapse_right
	_apply_adaptive_hud_layout()

func _on_collapse_bottom() -> void:
	_hud_interact_ms = Time.get_ticks_msec()
	var was_collapsed: bool = _collapse_bottom
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
	var stage_label: String = "准备" if stage == MatchController.Stage.PREPARE else ("战斗" if stage == MatchController.Stage.BATTLE else "结束")
	_append_battle_log("进入%s阶段" % stage_label)
	## Battle start: auto-collapse side chrome + shop once; toggles remain available.
	## Right = battle log (auto-collapse once on enter Battle).
	if stage == MatchController.Stage.BATTLE:
		## Skip the auto-collapse if the player just touched shop/side chrome — don't yank
		## a panel out from under an in-progress tap/drag (< 2s grace window).
		if Time.get_ticks_msec() - _hud_interact_ms >= 2000:
			_collapse_left = true
			_collapse_right = true
			_collapse_bottom = true
			_cam_pose_before_shop_valid = false
			_cam_pose_before_shop.clear()
			_apply_adaptive_hud_layout()
		## Force full Prepare fleet snapshot once before HostSim battle.
		if GameSession.pending_mode == "nullsec" and _nullsec_pve and not _nullsec_pve.is_pve_task():
			_push_local_prepare_fleet()
			var rival_pre: int = _nullsec_rival_seat(TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0))
			var net_pre: NullsecNetSession = _nullsec_net_session()
			if net_pre != null and rival_pre >= 0 and not _seat_is_ai(rival_pre):
				net_pre.request_prepare_fleet_snapshot(rival_pre)
		## PVP: nullsec guest hop (§4.1). Lowsec stays host-home — no teleport/sky switch.
		if GameSession.pending_mode == "nullsec" and _nullsec_pve and not _nullsec_pve.is_pve_task():
			if not _nullsec_pve.always_pvp:
				_nullsec_pvp_battle_teleport()
			_apply_remote_watch_only_for_battle()
			if _net_battle:
				_net_jobs_ready_for_titan = false
				_net_battle.on_local_battle_begin()
			_begin_combat_eval_if_human_pvp()
		elif GameSession.pending_mode == "nullsec" and _nullsec_pve and _nullsec_pve.is_pve_task():
			_apply_remote_watch_only_for_battle()
			if _net_battle:
				_net_jobs_ready_for_titan = false
				_net_battle.on_local_battle_begin()
			_combat_eval_active = false
		else:
			if match_ctrl:
				match_ctrl.remote_watch_only = false
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
		## SEMI_ASYNC §3.1a — host tells watch peers the round is over.
		var net_end: NullsecNetSession = _nullsec_net_session()
		if net_end != null and net_end.is_host and net_end.needs_stage_barrier() and match_ctrl:
			var hs: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
			net_end.broadcast_battle_ended(str(match_ctrl.last_round_result), hs, "host_complete")
		if GameSession.pending_mode == "nullsec":
			_apply_nullsec_prepare_stage_gates()
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
				_cam_default_pitch_deg = TypedVariant.as_float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg))
				_cam_pose_before_shop = _capture_cam_pose()
				_cam_pose_before_shop_valid = true
				_apply_camera_view_dict(_camera_secondary_view())
	elif not _camera_manual_pose():
		_trigger_camera_headup("stage_change")
	_last_match_stage = stage
	_refresh_hud()
	SessionDiagnostics.log("stage", stage_label)

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
		_cam_default_pitch_deg = TypedVariant.as_float(_camera_primary_view().get("pitch_deg", _cam_default_pitch_deg))
		_cam_pose_before_shop = _capture_cam_pose()
		_cam_pose_before_shop_valid = true
		_apply_camera_view_dict(_camera_secondary_view())


## SEMI_ASYNC §3.1a — non-host peers on barrier tables only watch authority snaps.
func _apply_remote_watch_only_for_battle() -> void:
	if match_ctrl == null:
		return
	var net: NullsecNetSession = _nullsec_net_session()
	match_ctrl.remote_watch_only = (
		net != null and net.needs_stage_barrier() and not net.is_host
	)
	if match_ctrl.remote_watch_only:
		## Watch peers do not bookkeep titles — host eval is authoritative enough for UI.
		_combat_eval_active = false
		if _net_battle != null:
			_net_battle.watch_only_apply = true
		SessionDiagnostics.log("mp.watch_only", "guest")
		print("[mp.diag] remote_watch_only ON")
	elif _net_battle != null:
		_net_battle.watch_only_apply = false


## MULTIPLAYER_PVP §7.1 — only real human↔human PVP tables earn titles; PVE / AI-rival
## rounds never start the tracker (kept inert to avoid wasted per-hit bookkeeping).
func notify_cyno_success(team_id: int) -> void:
	if _combat_eval_active and _combat_eval != null:
		_combat_eval.on_cyno_success(team_id)


func _begin_combat_eval_if_human_pvp() -> void:
	_combat_eval_active = false
	if match_ctrl != null and match_ctrl.remote_watch_only:
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	if rival < 0 or _seat_is_ai(rival):
		return
	if _combat_eval == null:
		_combat_eval = CombatEvalTracker.new()
	_combat_eval.begin_round(board)
	_combat_eval_active = true
	_eval_prepare_rival_seat = rival

func _on_admin_after_for_combat_eval(channel: StringName, payload: Dictionary, result: Dictionary) -> void:
	var ch: String = String(channel)
	## SEMI_ASYNC §3.3B — host queues fire/repair into light packets (independent of titles).
	if _net_battle != null and _net_battle.is_host:
		if ch == "combat.hit":
			var dealt_net: float = TypedVariant.as_float(result.get("dealt", 0.0), 0.0)
			if dealt_net > 0.0:
				@warning_ignore("unsafe_cast")
				var src_n: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("source_id", 0), 0)) as ShipUnit
				@warning_ignore("unsafe_cast")
				var tgt_n: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("target_id", 0), 0)) as ShipUnit
				_net_battle.record_combat_event("damage", src_n, tgt_n, dealt_net)
		elif ch == "combat.heal":
			var healed_net: float = TypedVariant.as_float(result.get("applied", 0.0), 0.0)
			if healed_net > 0.0:
				@warning_ignore("unsafe_cast")
				var src_h: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("source_id", 0), 0)) as ShipUnit
				@warning_ignore("unsafe_cast")
				var tgt_h: ShipUnit = instance_from_id(TypedVariant.as_int(payload.get("target_id", 0), 0)) as ShipUnit
				_net_battle.record_combat_event("repair", src_h, tgt_h, healed_net)
	## Purchase / sell sensors run even outside active battle (Prepare 羊望未来).
	if ch == "shop.purchase":
		_note_shop_purchase_result(result, payload)
		return
	if ch == "board.sell":
		_note_board_sell(payload, result)
		return
	if not _combat_eval_active or _combat_eval == null:
		return
	if ch == "combat.hit":
		var dealt: float = TypedVariant.as_float(result.get("dealt", 0.0), 0.0)
		if dealt <= 0.0:
			return
		var source_id: int = TypedVariant.as_int(payload.get("source_id", 0), 0)
		var target_id: int = TypedVariant.as_int(payload.get("target_id", 0), 0)
		@warning_ignore("unsafe_cast")
		var src: ShipUnit = instance_from_id(source_id) as ShipUnit
		if src == null or not is_instance_valid(src):
			return
		_combat_eval.on_hit(source_id, target_id, src.team_id, dealt)
		if TypedVariant.as_bool(result.get("destroyed", false), false):
			@warning_ignore("unsafe_cast")
			var tgt: ShipUnit = instance_from_id(target_id) as ShipUnit
			_combat_eval.on_ship_lost(tgt, src)
	elif ch == "combat.heal":
		_combat_eval.on_heal(TypedVariant.as_float(result.get("applied", 0.0), 0.0))

func _note_shop_purchase(bought: Dictionary, ship_id_hint: int = 0) -> void:
	if not TypedVariant.as_bool(bought.get("accepted", false), false):
		return
	_note_shop_purchase_result(bought, {"ship_id": ship_id_hint})

func _note_shop_purchase_result(result: Dictionary, _payload: Dictionary = {}) -> void:
	if not TypedVariant.as_bool(result.get("accepted", false), false):
		return
	var hx: int = TypedVariant.as_int(result.get("hangar_x", -1), -1)
	var hz: int = TypedVariant.as_int(result.get("hangar_z", 0), 0)
	var ship: ShipUnit = null
	if board and hx >= 0:
		ship = board._occupant_at("hangar", ShipUnit.TEAM_PLAYER, hx, hz)
	if ship == null or not is_instance_valid(ship):
		return
	if _eval_first_purchase_iid == 0:
		_eval_first_purchase_iid = ship.get_instance_id()
	if CombatEvalTracker._tonnage_rank(ship) >= 5 or ship.requires_cyno_entry:
		_eval_bought_capital_this_prepare = true

func _note_board_sell(payload: Dictionary, result: Dictionary) -> void:
	if not TypedVariant.as_bool(result.get("accepted", false), false):
		return
	var iid: int = TypedVariant.as_int(payload.get("ship_instance_id", 0), 0)
	if iid != 0 and iid == _eval_first_purchase_iid:
		_eval_sold_first_this_prepare = true

## Merge this round's §7.1 titles into the running per-seat tally and log them.
func _finalize_combat_eval(result: String, local_seat: int, rival_seat: int) -> void:
	if not _combat_eval_active or _combat_eval == null:
		return
	_combat_eval_active = false
	## Update streak / loss meta before finalize reads it.
	_update_eval_streak_meta(result, local_seat, rival_seat)
	_combat_eval.meta_scout_vs_rival = _eval_scout_vs_rival
	_combat_eval.meta_sold_first_purchase = _eval_sold_first_this_prepare
	_combat_eval.meta_bought_capital_prepare = _eval_bought_capital_this_prepare
	_combat_eval.meta_streak_by_seat = _eval_human_streak.duplicate()
	_combat_eval.meta_losses_by_seat = _eval_human_losses.duplicate()
	_combat_eval.meta_rejoined_by_seat = _eval_rejoined.duplicate()
	_combat_eval.meta_wins_since_rejoin = _eval_wins_since_rejoin.duplicate()
	_combat_eval.meta_divine_hand_by_seat = _eval_divine_hand_flags(result, local_seat, rival_seat)
	_combat_eval.meta_match_ending = false
	var titles: Array = _combat_eval.finalize(result, local_seat, rival_seat, board)
	## Cache layout for 神之一手 next round.
	_cache_layout_after_round(result, local_seat)
	_eval_scout_vs_rival = 0
	_eval_sold_first_this_prepare = false
	_eval_bought_capital_this_prepare = false
	for t_v: Variant in titles:
		var t: Dictionary = TypedVariant.as_dict(t_v)
		var seat_id: int = TypedVariant.as_int(t.get("seat_id", -1), -1)
		var title: String = str(t.get("title", ""))
		if seat_id < 0 or title == "":
			continue
		if not _match_titles.has(seat_id):
			_match_titles[seat_id] = []
		@warning_ignore("unsafe_cast")
		var arr: Array = _match_titles[seat_id] as Array
		arr.append(title)
		var nick: String = NickCodec.display_short(str(_seat_row_nick(seat_id)))
		var rival_nick: String = NickCodec.display_short(str(_seat_row_nick(rival_seat if seat_id == local_seat else local_seat)))
		_append_battle_log("%s在与%s的对局中获得%s评价" % [nick, rival_nick, title])


func _record_wld(result: String, local_seat: int, rival_seat: int) -> void:
	## result is from local seat's perspective: win|lose|draw
	var pairs: Array = []
	if result == "win":
		pairs = [{"seat": local_seat, "k": "w"}, {"seat": rival_seat, "k": "l"}]
	elif result == "lose":
		pairs = [{"seat": local_seat, "k": "l"}, {"seat": rival_seat, "k": "w"}]
	else:
		pairs = [{"seat": local_seat, "k": "d"}, {"seat": rival_seat, "k": "d"}]
	for p_v: Variant in pairs:
		var p: Dictionary = TypedVariant.as_dict(p_v)
		var seat: int = TypedVariant.as_int(p.get("seat", -1), -1)
		if seat < 0:
			continue
		var cur: Dictionary = _wld_tuple(seat)
		var key: String = str(p.get("k", "d"))
		cur[key] = TypedVariant.as_int(cur.get(key, 0), 0) + 1
		_wld_by_seat[seat] = cur
	if match_ctrl:
		_kills_by_seat[local_seat] = TypedVariant.as_int(_kills_by_seat.get(local_seat, 0), 0) + TypedVariant.as_int(match_ctrl.kills_this_round_player, 0)
		if rival_seat >= 0:
			_kills_by_seat[rival_seat] = TypedVariant.as_int(_kills_by_seat.get(rival_seat, 0), 0) + TypedVariant.as_int(match_ctrl.kills_this_round_ai, 0)


func _update_eval_streak_meta(result: String, local_seat: int, rival_seat: int) -> void:
	_record_wld(result, local_seat, rival_seat)
	for p_v: Variant in [
		{"seat": local_seat, "won": result == "win", "reset": result != "win"},
		{"seat": rival_seat, "won": result == "lose", "reset": result != "lose"},
	]:
		var p: Dictionary = TypedVariant.as_dict(p_v)
		var seat: int = TypedVariant.as_int(p.get("seat", -1), -1)
		if seat < 0:
			continue
		if TypedVariant.as_bool(p.get("reset", false), false):
			_eval_human_streak[seat] = 0
			if (seat == local_seat and result == "lose") or (seat == rival_seat and result == "win"):
				_eval_human_losses[seat] = TypedVariant.as_int(_eval_human_losses.get(seat, 0), 0) + 1
		else:
			_eval_human_streak[seat] = TypedVariant.as_int(_eval_human_streak.get(seat, 0), 0) + 1
			if TypedVariant.as_bool(_eval_rejoined.get(seat, false), false):
				_eval_wins_since_rejoin[seat] = TypedVariant.as_int(_eval_wins_since_rejoin.get(seat, 0), 0) + 1


func _eval_divine_hand_flags(result: String, local_seat: int, _rival_seat: int) -> Dictionary:
	var out: Dictionary = {}
	var cur_fp: String = _combat_eval.get_layout_fingerprint() if _combat_eval else ""
	if result == "win" and local_seat >= 0:
		var prev: Dictionary = TypedVariant.as_dict(_eval_prev_layout.get(local_seat, {}))
		if TypedVariant.as_bool(prev.get("lost", false), false) \
				and CombatEvalTracker.layout_is_plus_one(str(prev.get("fp", "")), cur_fp):
			out[local_seat] = true
	return out


func _cache_layout_after_round(result: String, local_seat: int) -> void:
	if _combat_eval == null or local_seat < 0:
		return
	_eval_prev_layout[local_seat] = {
		"fp": _combat_eval.get_layout_fingerprint(),
		"lost": result == "lose",
	}

func _seat_row_nick(seat_id: int) -> String:
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if TypedVariant.as_int(s.get("seat_id", -1), -1) == seat_id:
			return str(s.get("nick", "席位 %d" % (seat_id + 1)))
	return "席位 %d" % (seat_id + 1)

func _nullsec_after_battle_into_prepare() -> void:
	## Lock next creep roster immediately at previous round end.
	if _titan_kill_busy or _doomsday_busy:
		_nullsec_prepare_pending = true
		return
	if _nullsec_pve and match_ctrl:
		## Read the outcome frozen at combat end: by now every field hull has been
		## reloaded, so counting the board here would score every round as a draw.
		var result: String = str(match_ctrl.last_round_result)
		var player_lost: bool = result == "lose"
		## Salvage: the escorted freighter must still have been alive at the last tick.
		if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
			_nullsec_pve.freighter_alive = bool(match_ctrl.last_round_freighter_alive)
		## PVE failures do not deduct titan HP — evaluate BEFORE locking next task.
		var was_pve: bool = _nullsec_pve.is_pve_task()
		if not was_pve:
			## Nullsec multi-seat: wait until host authority jobs flush before titan settle.
			if _net_battle and _net_battle.is_host and not _net_jobs_ready_for_titan:
				_nullsec_prepare_pending = true
				return
			if _net_battle and _net_battle.is_host:
				_net_battle.take_round_reports()
			if _combat_eval_active:
				var local_seat_eval: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
				_finalize_combat_eval(result, local_seat_eval, _nullsec_rival_seat(local_seat_eval))
			_nullsec_resolve_pvp_doomsday(result)
			if _doomsday_busy or _titan_kill_busy:
				## Hold the next round until the beam (and any hull kill) has played out.
				_nullsec_prepare_pending = true
				return
		elif player_lost:
			show_notice("PVE 失败 · 不扣泰坦血")
	_nullsec_enter_next_round()

func _nullsec_enter_next_round() -> void:
	## Doomsday beam must finish first (MULTIPLAYER_PVP §6 演出闸门) — every caller already
	## checks `_doomsday_busy` before reaching here, but guard directly too so a stray call
	## can never slip the round forward mid-performance.
	if _doomsday_busy or _presentation_hold or _titan_kill_busy or _titan_kill_active > 0:
		_nullsec_prepare_pending = true
		return
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
		## Cancel auto finish floor before next battle prefers preferred/votes (SEMI_ASYNC §4.5).
		_nullsec_speed.reset_round()
		_apply_resolved_speed()


## Own region skybox — Prepare always, and after a guest PVP battle.
func _restore_local_home_skybox() -> void:
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	var region: String = _seat_region(local_seat)
	if region != "":
		apply_region_skybox(region)
	_nullsec_watch_seat = local_seat
	_refresh_region_label()


func _nullsec_prepare_pvp_round() -> void:
	## Fresh Prepare window for 羊望未来 capital/sell flags (first-purchase iid is match-scoped).
	_eval_sold_first_this_prepare = false
	_eval_bought_capital_this_prepare = false
	_eval_scout_vs_rival = 0
	_pending_enter_battle = false
	## Prepare: clear creeps, rebuild rival army, stay on own skybox (MULTIPLAYER_PVP §4.1).
	## Lowsec: always host-home — never roll guest hop (D-EAC-47).
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	_eval_prepare_rival_seat = rival
	_set_rival_berth_visible(true)
	_restore_local_home_skybox()
	_nullsec_pvp_guest = false
	var lowsec: bool = _nullsec_pve != null and _nullsec_pve.always_pvp
	if rival < 0:
		show_notice("PVP 准备 · 本房无对手席位 · 本场主场进行")
	elif lowsec:
		## Host home field for both ends (sky stem = host seat region).
		var host_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("host_seat", 0), 0)
		var host_region: String = _seat_region(host_seat)
		if host_region != "":
			apply_region_skybox(host_region)
		_nullsec_watch_seat = host_seat
		_refresh_region_label()
		show_notice("低安 · 对手席位 %02d · 房主主场开战" % (rival + 1))
	else:
		if _nullsec_rng:
			_nullsec_pvp_guest = _nullsec_rng.roll_int(
				maxi(1, TypedVariant.as_int(match_ctrl.round_phase_value, 1) if match_ctrl else 1), "pvp_home", 0, 1
			) == 0
		else:
			_nullsec_pvp_guest = (Time.get_ticks_msec() % 2) == 0
		if _nullsec_pvp_guest:
			show_notice("PVP 准备 · 对手席位 %02d · 交战进客场" % (rival + 1))
		else:
			show_notice("PVP 准备 · 对手席位 %02d · 本场主场开战" % (rival + 1))
	for s: ShipUnit in board.all_ships().duplicate():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		## PVP round: drop the creep army and any leftover salvage freighter with it.
		if TypedVariant.as_int(s.team_id, 0) == ShipUnit.TEAM_AI or s.is_protect_target:
			board.remove_ship_node(s)
	## Cleared AI side — must re-apply even if rival snapshot signature unchanged.
	_fleet_apply_sig = ""
	## Human rivals: live Prepare fleet sync — never AI handbook. AI seats keep rebuild.
	var rival_ai: bool = rival >= 0 and _seat_is_ai(rival)
	print("[mp.diag] pvp_prepare local=%d rival=%d is_ai=%s lowsec=%s" % [
		local_seat, rival, rival_ai, lowsec
	])
	SessionDiagnostics.log(
		"mp.pvp_prepare",
		"local=%d rival=%d ai=%s" % [local_seat, rival, rival_ai]
	)
	if rival_ai:
		if ai and ai.has_method("rebuild_round_army"):
			ai.rebuild_round_army()
			print("[mp.diag] pvp_prepare AI rebuild_round_army")
		if ai and ai.has_method("finalize_prepare"):
			ai.finalize_prepare()
	else:
		_wire_prepare_fleet_sync()
		_push_local_prepare_fleet()
		var net: NullsecNetSession = _nullsec_net_session()
		if net != null and rival >= 0:
			net.request_prepare_fleet_snapshot(rival)
		else:
			print("[mp.diag] pvp_prepare human path no net/rival")
	## Rival seat is a titan holder too — its buff rides the same fetter rail.
	board.set_titan_fetter_race(ShipUnit.TEAM_AI, _seat_titan_race(rival))
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())
	if combat and _nullsec_rng:
		var serial: int = maxi(1, TypedVariant.as_int(match_ctrl.round_phase_value, 1) if match_ctrl else 1)
		combat.bind_match_rng(_nullsec_rng, serial)
		if match_ctrl.has_method("bind_cyno_rng"):
			match_ctrl.bind_cyno_rng(_nullsec_rng, serial)


func _wire_prepare_fleet_sync() -> void:
	if board != null and not board.board_changed.is_connected(_on_prepare_board_changed_for_net):
		board.board_changed.connect(_on_prepare_board_changed_for_net)
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and not net.prepare_fleet_snapshot_received.is_connected(_on_prepare_fleet_snapshot):
		net.prepare_fleet_snapshot_received.connect(_on_prepare_fleet_snapshot)


func _on_prepare_board_changed_for_net() -> void:
	if _applying_rival_fleet:
		return
	if GameSession.pending_mode != "nullsec":
		return
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.PREPARE:
		return
	if _nullsec_pve != null and _nullsec_pve.is_pve_task():
		return
	_push_local_prepare_fleet()


func _serialize_team_player_fleet() -> Array:
	var out: Array = []
	if board == null:
		return out
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var seq: int = 0
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_PLAYER:
			continue
		var st: String = str(s.slot_type)
		if st != "hangar" and st != "field":
			continue
		var x: int = TypedVariant.as_int(s.grid_x, 0)
		var z: int = TypedVariant.as_int(s.grid_z, 0)
		var side: int = s.field_side_team if s.field_side_team >= 0 else s.team_id
		if str(s.net_uid) == "":
			s.net_uid = "%d|%d|%s|%d|%d|%d" % [local_seat, TypedVariant.as_int(s.ship_id, 0), st, x, z, seq]
		seq += 1
		var fit_ids: Array = []
		for fe_v: Variant in s.get_function_fit():
			var fe: Dictionary = TypedVariant.as_dict(fe_v)
			var fid: String = str(fe.get("id", ""))
			if fid != "":
				fit_ids.append(fid)
		out.append({
			"ship_id": TypedVariant.as_int(s.ship_id, 0),
			"star": TypedVariant.as_int(s.star, 1),
			"slot_type": st,
			"x": x,
			"z": z,
			"side": side,
			"net_uid": str(s.net_uid),
			"fit": fit_ids,
		})
	return out


func _fleet_snapshot_sig(ships: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry_v: Variant in ships:
		var e: Dictionary = TypedVariant.as_dict(entry_v)
		var fit: Array = TypedVariant.as_array(e.get("fit", []))
		parts.append("%d.%d.%s.%d.%d.%d.%s.%s" % [
			TypedVariant.as_int(e.get("ship_id", 0), 0),
			TypedVariant.as_int(e.get("star", 1), 1),
			str(e.get("slot_type", "")),
			TypedVariant.as_int(e.get("x", 0), 0),
			TypedVariant.as_int(e.get("z", 0), 0),
			TypedVariant.as_int(e.get("side", -1), -1),
			str(e.get("net_uid", "")),
			",".join(PackedStringArray(fit)),
		])
	parts.sort()
	return "|".join(parts)


func _push_local_prepare_fleet() -> void:
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null:
		return
	var ships: Array = _serialize_team_player_fleet()
	var sig: String = _fleet_snapshot_sig(ships)
	if sig == _fleet_push_sig:
		return
	var now: int = Time.get_ticks_msec()
	if (now - _fleet_push_last_msec) < _FLEET_PUSH_MIN_MSEC and not _fleet_push_sig.is_empty():
		_fleet_push_pending = ships
		_fleet_push_debounce_tok += 1
		var tok: int = _fleet_push_debounce_tok
		get_tree().create_timer(float(_FLEET_PUSH_MIN_MSEC) / 1000.0).timeout.connect(
			func() -> void: _flush_deferred_fleet_push(tok)
		)
		return
	_commit_fleet_push(ships, sig)


func _flush_deferred_fleet_push(tok: int) -> void:
	if tok != _fleet_push_debounce_tok:
		return
	if _fleet_push_pending.is_empty():
		return
	var ships: Array = _fleet_push_pending
	_fleet_push_pending = []
	var sig: String = _fleet_snapshot_sig(ships)
	if sig == _fleet_push_sig:
		return
	_commit_fleet_push(ships, sig)


func _commit_fleet_push(ships: Array, sig: String) -> void:
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null:
		return
	_fleet_push_sig = sig
	_fleet_push_last_msec = Time.get_ticks_msec()
	net.push_prepare_fleet_snapshot(ships)


func _on_prepare_fleet_snapshot(seat: int, ships: Array) -> void:
	## Prepare-only normally; allow Battle only while recovering from empty-open hold.
	var empty_recover: bool = (
		match_ctrl != null
		and match_ctrl.stage == MatchController.Stage.BATTLE
		and match_ctrl.is_battle_opened_empty()
	)
	if match_ctrl == null or (match_ctrl.stage != MatchController.Stage.PREPARE and not empty_recover):
		print("[mp.diag] fleet_apply SKIP (not prepare stage=%s)" % (
			match_ctrl.stage if match_ctrl else -1
		))
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	print("[mp.diag] fleet_apply_check seat=%d rival=%d n=%d" % [seat, rival, ships.size()])
	if seat != rival:
		print("[mp.diag] fleet_apply SKIP (not rival)")
		return
	var sig: String = _fleet_snapshot_sig(ships)
	var ai_alive: int = board.count_alive_field(ShipUnit.TEAM_AI) if board else 0
	## Same snap after AI wipe must still re-apply (was: silent sig skip → battle_empty ai=0).
	if sig == _fleet_apply_sig and ai_alive > 0 and not empty_recover:
		print("[mp.diag] fleet_apply SKIP (same sig ai=%d)" % ai_alive)
		_try_flush_pending_enter_battle()
		return
	if sig == _fleet_apply_sig and ai_alive <= 0:
		print("[mp.diag] fleet_apply FORCE (same sig but ai empty n=%d)" % ships.size())
	_fleet_apply_sig = sig
	_apply_rival_prepare_fleet(ships)
	if empty_recover and _nullsec_human_rival_fleet_ready():
		match_ctrl.resume_combat_after_empty_fleet()
	else:
		_try_flush_pending_enter_battle()


func _apply_rival_prepare_fleet(ships: Array) -> void:
	if board == null:
		return
	_applying_rival_fleet = true
	var before: int = 0
	for s0: ShipUnit in board.all_ships():
		if s0 != null and is_instance_valid(s0) and TypedVariant.as_int(s0.team_id, 0) == ShipUnit.TEAM_AI:
			before += 1
	for s: ShipUnit in board.all_ships().duplicate():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if TypedVariant.as_int(s.team_id, 0) == ShipUnit.TEAM_AI:
			board.remove_ship_node(s)
	var spawned: int = 0
	for entry_v: Variant in ships:
		var entry: Dictionary = TypedVariant.as_dict(entry_v)
		var sid: int = TypedVariant.as_int(entry.get("ship_id", 0), 0)
		if sid <= 0:
			continue
		var star: int = maxi(1, TypedVariant.as_int(entry.get("star", 1), 1))
		var st: String = str(entry.get("slot_type", "field"))
		if st != "hangar" and st != "field":
			st = "field"
		var x: int = TypedVariant.as_int(entry.get("x", 0), 0)
		var z: int = TypedVariant.as_int(entry.get("z", 0), 0)
		## Sender-perspective side → flip for local AI half.
		var sender_side: int = TypedVariant.as_int(entry.get("side", -1), -1)
		if sender_side < 0:
			var sd: Dictionary = DataStore.get_ship(sid)
			if TypedVariant.as_bool(sd.get("deploy_enemy_half_only", false), false):
				sender_side = ShipUnit.TEAM_AI ## enemy half from sender = their AI
			else:
				sender_side = ShipUnit.TEAM_PLAYER
		var local_side: int = ShipUnit.TEAM_AI if sender_side == ShipUnit.TEAM_PLAYER else ShipUnit.TEAM_PLAYER
		var ship: ShipUnit = board.spawn_ship(sid, star, ShipUnit.TEAM_AI, st, x, z)
		if ship != null and is_instance_valid(ship):
			ship.net_uid = str(entry.get("net_uid", ship.net_uid))
			if st == "field":
				board.move_ship_to_field_side(ship, x, z, local_side)
			var fit_ids: Array = TypedVariant.as_array(entry.get("fit", []))
			if not fit_ids.is_empty():
				var fit_entries: Array = []
				for fid_v: Variant in fit_ids:
					fit_entries.append({"id": str(fid_v)})
				ship.set_function_fit(fit_entries)
		spawned += 1
	board.recalculate_fetters(ShipUnit.TEAM_AI)
	_applying_rival_fleet = false
	print("[mp.diag] fleet_apply done before=%d spawned=%d field_ai=%d" % [
		before, spawned, board.count_alive_field(ShipUnit.TEAM_AI)
	])
	SessionDiagnostics.log(
		"mp.fleet_apply",
		"before=%d spawned=%d" % [before, spawned]
	)
	_refresh_hud()


func _nullsec_pvp_battle_teleport() -> void:
	## Prepare→Battle only: guest hops to rival skybox + cyno flash (nullsec §4.1).
	## Lowsec callers must not reach here.
	if _nullsec_pve and _nullsec_pve.always_pvp:
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	var land_team: int = ShipUnit.TEAM_PLAYER if _nullsec_pvp_guest else ShipUnit.TEAM_AI
	if _nullsec_pvp_guest and rival >= 0:
		var region: String = _seat_region(rival)
		if region != "":
			apply_region_skybox(region)
		_nullsec_watch_seat = rival
		_refresh_region_label()
		show_notice("客场作战 · 诱导落位 · 开战")
	else:
		show_notice("主场迎战 · 对手诱导落位 · 开战")
	## CapitalJumpFx flash-land, no travel path — guest = our hulls; home = rival hulls.
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		if TypedVariant.as_int(s.team_id, 0) != land_team or s.is_unmanned:
			continue
		if str(s.slot_type) != "field":
			continue
		var land: Vector3 = s.global_position
		@warning_ignore("unsafe_method_access")
		var fx: _CapitalJumpFx = _CapitalJumpFx.new()
		world.add_child(fx)
		@warning_ignore("unsafe_method_access")
		fx.play(s, land, 0.85)


func _set_rival_berth_visible(v: bool) -> void:
	## Opposing titan is only on field for player-vs-player rounds (§2.4a).
	## Lowsec first reveal → −Z slide (§2.5); nullsec just toggles visibility.
	if _rival_titan_berth == null or not is_instance_valid(_rival_titan_berth):
		return
	var was: bool = _rival_titan_berth.visible
	_rival_titan_berth.visible = v
	if v and not was and _nullsec_pve != null and _nullsec_pve.always_pvp:
		_begin_rival_titan_slide()
	_refresh_titan_hp_bar()


func _append_battle_log(text: String) -> void:
	var line: String = str(text).strip_edges()
	if line.is_empty():
		return
	_battle_log_lines.append(line)
	while _battle_log_lines.size() > _BATTLE_LOG_MAX:
		_battle_log_lines.pop_front()
	_refresh_battle_log_list()

func _refresh_battle_log_list() -> void:
	@warning_ignore("unsafe_cast")
	var list: VBoxContainer = hud.get_node_or_null("Root/RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogScroll/BattleLogList") as VBoxContainer
	if list == null:
		return
	for c: Node in list.get_children():
		c.queue_free()
	for entry: Variant in _battle_log_lines:
		var lab: Label = Label.new()
		lab.text = str(entry)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiAssets.apply_label_font(lab, false, UiLayout.font_size(11, list))
		lab.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		list.add_child(lab)
	call_deferred("_scroll_battle_log_to_end")

func _scroll_battle_log_to_end() -> void:
	@warning_ignore("unsafe_cast")
	var scroll: ScrollContainer = hud.get_node_or_null("Root/RightCol/RightInner/RightContent/BattleLog/BattleLogInner/BattleLogScroll") as ScrollContainer
	if scroll == null:
		return
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	if bar:
		scroll.scroll_vertical = roundi(bar.max_value)
