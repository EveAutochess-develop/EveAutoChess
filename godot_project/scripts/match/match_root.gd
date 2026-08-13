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
## Guards _sync_required_speed_seats against speed_changed → apply → sync recursion.
var _speed_seat_sync_guard: bool = false
var _speed_dropdown: SpeedDropdownMenu
var _nullsec_pve: NullsecPveDirector
var _nullsec_rng: MatchRng
var _doomsday_resolver: TitanDoomsdayResolver
var _settlement_panel: NullsecSettlementPanel
## Prepare fleet net sync: suppress board_changed echo + debounce identical snapshots.
var _applying_rival_fleet: bool = false
var _rival_fleet_queue: Array = []
var _rival_fleet_spawned: int = 0
var _rival_fleet_before: int = 0
var _pending_combat_eval_finalize: Dictionary = {}
var _fleet_push_sig: String = ""
var _fleet_apply_sig: String = ""
## True after rival Prepare fleet snapshot applied this prepare (empty roster counts).
var _rival_fleet_synced: bool = false
## Barrier released but rival fleet not yet synced — defer commit_prepare_complete.
var _pending_enter_battle: bool = false
var _fleet_push_last_msec: int = 0
var _fleet_push_pending: Array = []
var _fleet_push_debounce_tok: int = 0
const _FLEET_PUSH_MIN_MSEC: int = 200

var _info_ship: ShipUnit = null
## Last board/berth unit the player touched — DETAIL must restore this (UI_AND_SHELL §2.6).
var _last_touched_ship: ShipUnit = null
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
var _collapse_left_syn: bool = false
var _collapse_left_equip: bool = false
var _collapse_right: bool = false
var _collapse_bottom: bool = false
## Live shop-card side after on-screen clamp (UI_AND_SHELL §3.1).
var _hud_shop_card_side: float = 0.0
var _hud_shop_card_size: Vector2 = Vector2.ZERO
## LevelExp column width: probe-locked (15级 / 999 / 999); never follows live text or segs.
var _hud_level_exp_fixed_w: float = 0.0
enum RightPaneMode { DETAIL, LOG, RANK }
var _right_pane_mode: int = RightPaneMode.DETAIL
var _rank_sort_key: String = "dealt"
var _rank_refresh_accum: float = 0.0
## UI_AND_SHELL: HUD refresh ≤½ Engine FPS; 0=none 1=light 2=full.
var _hud_refresh_since_s: float = 999.0
var _hud_refresh_pending: int = 0
## Last time the player touched shop/side-panel chrome — auto collapse/expand
## backs off for a short grace window so it doesn't yank a panel out from under a tap.
var _hud_interact_ms: int = 0
## Whole-match HUD auto fold: collapse once on first Battle; expand once on GAME_END.
var _hud_auto_collapsed_once: bool = false
var _hud_auto_expanded_once: bool = false
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
var _sfx_check: CheckBox
var _sfx_slider: HSlider
var _sfx_lbl: Label
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
var _match_eval: MatchEvalTracker = null
var _match_eval_gold_at_round: int = 0
## 第五人格: room with 5 humans — consecutive round wins vs distinct rivals.
var _fifth_opponents: Array = [] ## rival seat ids
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
## This PVP round fights as guest (rival skybox). Decided at prepare; hop at prepare start (§4.1).
var _nullsec_pvp_guest: bool = false
var _nullsec_guest_hop_done: bool = false
## One-shot nullsec open intro (head-down + slide-in).
var _titan_intro_done: bool = false
var _titan_intro_t: float = -1.0
var _titan_intro_start: Vector3 = Vector3.ZERO
var _titan_intro_end: Vector3 = Vector3.ZERO
var _titan_intro_pitch0: float = 0.0
var _titan_intro_pitch_start: float = 0.0
## Rival berth slide — lowsec only (MULTIPLAYER_PVP §2.5).
var _rival_titan_intro_done: bool = false
var _rival_intro_active: bool = false
var _rival_intro_start: Vector3 = Vector3.ZERO
var _rival_intro_end: Vector3 = Vector3.ZERO
const _TITAN_INTRO_SLIDE_DUR_S: float = 2.7
const _TITAN_INTRO_CAM_DUR_S: float = 1.35
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
const _BOTTOM_CLUSTER: String = "Shop/ShopCol/ShopContent/BottomCluster"
const _BOTTOM_GOLD_POP: String = "Shop/ShopCol/ShopContent/BottomCluster/GoldPop"
## UI_AND_SHELL §2.1 — framed ShopBarPanel (never collapses) + fetter fade (collapsible).
const _SHOP_BAR_PANEL: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel"
const _SHOP_BAR: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar"
const _SHOP_BUY_COL: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel"
## UI_AND_SHELL §3.2 吸靠：ShopBar 绝对宿主；无互抢 stretch 的 ShopBody 链。
const _SHOP_BODY: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar"
const _SHOP_INNER: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ShipCol"
const _SHOP_OFFER_HOST: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ShipCol/ShipOfferHost"
const _SHOP_SLOTS: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ShipCol/ShipOfferHost/ShopSlots"
const _SHOP_SELL: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ShipCol/ShipOfferHost/SellZone"
const _SHOP_META_COL: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/MetaCol"
const _SHOP_META_MID: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/MetaCol/MetaMid"
const _SHOP_EQUIP_SLOTS: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/MetaCol/MetaMid/EquipmentSlots"
const _SHOP_BTNS: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ShopBtns"
const _SHOP_SCANNER_HOST: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ScannerHost"
const _SHOP_SCANNER: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ScannerHost/ScannerFrame/ScannerInner/ScannerBtn"
const _SHOP_LEVEL_HOST: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/MetaCol/MetaMid/LevelExpHost"
const _SHOP_LEVEL: String = "LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/MetaCol/MetaMid/LevelExpHost/LevelExp"
const _RESERVE_GRID_PATH: String = "Shop/ShopCol/ShopContent/BottomCluster/ReserveGrid"
const _EQUIP_INV_CORNER_PX: int = 3
## UI_AND_SHELL §3.4 — collapse-arrow frame pulse (first Prepare only).
const _ARROW_FRAME_PULSE_S: float = 1.4
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
## 0 idle · 1 create MapEnv · 2 step asteroids · 3 start_match · 4 nullsec runtime (stepwise)
var _boot_phase: int = 0
var _boot_env: MapEnv = null
var _boot_mode: String = ""
var _boot_resume_data: Dictionary = {}
## Sub-steps inside boot phase 4 (`_tick_nullsec_runtime_setup`). Mobile hosts ANR if
## start_match + full nullsec wire run in one frame after MapEnv.
var _nullsec_rt_step: int = 0

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
	match_ctrl.hud_refresh.connect(_on_hud_refresh_full)
	match_ctrl.hud_tick.connect(_on_hud_tick)
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
	var is_nullsec: bool = str(GameSession.pending_mode) == "nullsec"
	var net_host: int = 0
	if net_sess:
		net_host = 1 if net_sess.is_host else 0
	if is_nullsec:
		SessionDiagnostics.begin_critical_window("mp_match_boot")
	SessionDiagnostics.log_critical(
		"match.enter",
		"mode=%s host=%d %s" % [str(GameSession.pending_mode), net_host, SessionDiagnostics.mem_detail()]
	)
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
	## Sync drain (tests / rare callers). Match boot uses `_tick_nullsec_runtime_setup` stepwise.
	_nullsec_rt_step = 0
	while _nullsec_rt_step >= 0:
		_tick_nullsec_runtime_setup()


## One chunk per boot frame. Returns true when finished (or failed soft).
## Hot-update stamp: 202608.8.65 — speed-seat sync recursion fix + round titles.
func _tick_nullsec_runtime_setup() -> bool:
	var payload: Dictionary = GameSession.pending_nullsec
	var sec: String = str(payload.get("security_mode", "nullsec"))
	match _nullsec_rt_step:
		0:
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt0_core sec=%s %s" % [sec, SessionDiagnostics.mem_detail()]
			)
			_nullsec_rng = MatchRng.new()
			_nullsec_rng.configure(
				TypedVariant.as_int(payload.get("match_seed", Time.get_unix_time_from_system()), int(Time.get_unix_time_from_system())),
				MatchRng.compute_rules_hash()
			)
			ShopController.bind_match_rng(_nullsec_rng, "shop")
			_nullsec_speed = RoundSpeedController.new()
			_nullsec_speed.speed_changed.connect(_on_nullsec_speed_changed)
			_nullsec_speed.force_draw_remaining.connect(_on_nullsec_force_draw)
			_nullsec_pve = NullsecPveDirector.new()
			_nullsec_pve.always_pvp = NullsecNetSession.is_lowsec(sec)
			_nullsec_pve.setup(_nullsec_rng, 1)
			_nullsec_pve.pick_task(1)
			if not GameSession.pending_nullsec.has("last_rival_by_seat"):
				GameSession.pending_nullsec["last_rival_by_seat"] = {}
			## Seat economy for the AI players starts with the humans' opening, then banks
			## gold/exp every round so a later PVP rival is not a level-1 fleet.
			if ai and ai.has_method("init_economy"):
				ai.init_economy()
			## Titan buff rides the fetter rail (MULTIPLAYER_PVP §2.3): always on from setup.
			board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())
			## Lowsec (always_pvp): no R1 creeps / salvage freighter — seat PVP from round 1.
			## PVE creeps lock+spawn at Prepare→Battle with current gold (§5.1.2).
			_nullsec_rt_step = 1
			return false
		1:
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt1_titan %s" % SessionDiagnostics.mem_detail()
			)
			_doomsday_resolver = TitanDoomsdayResolver.new()
			## Lowsec / always_pvp: titan pipe damage × lowsec_pvp_loss_mul (titan_pvp.json).
			var lowsec_mul: float = 0.25
			if DataStore != null and typeof(DataStore.get("titan_pvp")) == TYPE_DICTIONARY:
				lowsec_mul = TypedVariant.as_float(
					TypedVariant.as_dict(DataStore.titan_pvp).get("lowsec_pvp_loss_mul", 0.25),
					0.25
				)
			_doomsday_resolver.pvp_loss_mul = lowsec_mul if _nullsec_pve.always_pvp else 1.0
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
			_nullsec_rt_step = 2
			return false
		2:
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt2_ui %s" % SessionDiagnostics.mem_detail()
			)
			_speed_dropdown = SpeedDropdownMenu.new()
			_speed_dropdown.controller = _nullsec_speed
			_speed_dropdown.local_nick = "本地"
			hud.add_child(_speed_dropdown)
			_speed_dropdown.vote_changed.connect(func(spd: float) -> void:
				var net_spd: NullsecNetSession = _nullsec_net_session()
				if net_spd and net_spd.needs_stage_barrier():
					## SEMI_ASYNC §4.5: propose only — apply after rpc_speed_vote_apply on all peers.
					_sync_required_speed_seats()
					net_spd.push_speed_vote(spd)
					show_notice("已投票 %s · 等待其他人同档" % SpeedDropdownMenu._label(spd))
				else:
					var ls: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
					if _nullsec_speed:
						_nullsec_speed.set_vote(ls, spd)
					show_notice("有人发起对局速度调整 → %s" % SpeedDropdownMenu._label(spd))
					_apply_resolved_speed()
			)
			_nullsec_rt_step = 3
			return false
		3:
			## Split settle: signals → next-frame speed sync (never recurse into apply).
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt2b_settle_begin %s" % SessionDiagnostics.mem_detail()
			)
			var net_wire: NullsecNetSession = _nullsec_net_session()
			if net_wire:
				if not net_wire.speed_vote_received.is_connected(_on_speed_vote_received):
					net_wire.speed_vote_received.connect(_on_speed_vote_received)
				if not net_wire.doomsday_play_received.is_connected(_on_doomsday_play_received):
					net_wire.doomsday_play_received.connect(_on_doomsday_play_received)
				SessionDiagnostics.log_critical(
					"match.boot_phase",
					"phase=4_ns_rt2b_signals_ok %s" % SessionDiagnostics.mem_detail()
				)
			_nullsec_rt_step = 31
			return false
		31:
			## Was inlined after signals — recursion ANR'd mobile hosts before speed_sync_ok.
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt2b_speed_sync_begin %s" % SessionDiagnostics.mem_detail()
			)
			var net_spd: NullsecNetSession = _nullsec_net_session()
			if net_spd and _nullsec_speed and net_spd.needs_stage_barrier():
				_nullsec_speed.strict_seat_list = true
			_sync_required_speed_seats()
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt2b_speed_sync_ok %s" % SessionDiagnostics.mem_detail()
			)
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt2b_settle_done lazy_panel=1 %s" % SessionDiagnostics.mem_detail()
			)
			_nullsec_rt_step = 4
			return false
		4:
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt3_scout %s" % SessionDiagnostics.mem_detail()
			)
			_wire_nullsec_scout()
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt3_scout_ok %s" % SessionDiagnostics.mem_detail()
			)
			_nullsec_rt_step = 5
			return false
		5:
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt3_prep %s" % SessionDiagnostics.mem_detail()
			)
			_wire_nullsec_prepare_sync()
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt3_prep_ok %s" % SessionDiagnostics.mem_detail()
			)
			_nullsec_rt_step = 6
			return false
		6:
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt3_battle %s" % SessionDiagnostics.mem_detail()
			)
			_setup_net_battle_session()
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt3_battle_ok %s" % SessionDiagnostics.mem_detail()
			)
			_nullsec_rt_step = 7
			return false
		7:
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=4_ns_rt4_enter %s" % SessionDiagnostics.mem_detail()
			)
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
				_nullsec_rebuild_matchups()
				## Lowsec R1: PVP prepare (rival army), never creep slide-in.
				if _nullsec_pve.always_pvp or not _nullsec_local_is_pve():
					call_deferred("_nullsec_prepare_pvp_round")
				else:
					call_deferred("_nullsec_on_prepare_begin")
				call_deferred("_play_titan_berth_intro")
			_nullsec_rt_step = -1
			return true
		_:
			_nullsec_rt_step = -1
			return true

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
			## Keep host IGNORE so fetter fade never eats board picks; ShopBarPanel stays STOP.
			left.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		## Nominal leave: provisional report then mark ghost / menu (MULTIPLAYER_PVP §7.0b).
		_save_provisional_nullsec_report()
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
		match_ctrl.before_battle_callback = Callable(self, "_nullsec_relock_creeps_before_battle")
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
	SessionDiagnostics.log_critical(
		"mp.wire_prep_sync",
		"net=%s armed=%s barrier=%s %s" % [
			"1" if net != null else "0", armed_s, barrier_s, SessionDiagnostics.mem_detail()
		]
	)
	if net == null:
		_apply_nullsec_prepare_stage_gates()
		return
	if not net.prepare_clock_armed_changed.is_connected(_on_prepare_clock_armed_changed):
		net.prepare_clock_armed_changed.connect(_on_prepare_clock_armed_changed)
	if not net.urge_prepare_received.is_connected(_on_urge_prepare_received):
		net.urge_prepare_received.connect(_on_urge_prepare_received)
	if not net.enter_battle_released.is_connected(_on_enter_battle_released):
		net.enter_battle_released.connect(_on_enter_battle_released)
	if not net.seat_battle_finished.is_connected(_on_seat_battle_finished_speed):
		net.seat_battle_finished.connect(_on_seat_battle_finished_speed)
	if not net.battle_done_all_ready.is_connected(_on_battle_done_all_ready_clear_speed):
		net.battle_done_all_ready.connect(_on_battle_done_all_ready_clear_speed)
	if not net.round_matchups_received.is_connected(_on_net_round_matchups):
		net.round_matchups_received.connect(_on_net_round_matchups)
	if not net.round_standings_received.is_connected(_on_net_round_standings):
		net.round_standings_received.connect(_on_net_round_standings)
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
	_rival_fleet_synced = false
	_fleet_push_pending = []
	_pending_enter_battle = false
	## Legitimate empty boards (synced empty or local undeployed) still report battle_done.
	## Only HOLD enter_battle until rival fleet RPC arrives — do not skip the barrier.
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
	## Synced empty rival (or AI) → empty-open settle may skip the 12s phantom hold.
	if match_ctrl.has_method("mark_empty_open_fleet_trusted"):
		match_ctrl.mark_empty_open_fleet_trusted(_rival_fleet_synced or _seat_is_ai(
			_nullsec_rival_seat(TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0))
		))
	match_ctrl.commit_prepare_complete()


## True when we may open Battle vs a human rival (AI seat / PVE / solo always ready).
func _nullsec_human_rival_fleet_ready() -> bool:
	if GameSession.pending_mode != "nullsec" or board == null or match_ctrl == null:
		return true
	if _nullsec_local_is_pve():
		return true
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	if rival < 0 or _seat_is_ai(rival):
		return true
	## Empty roster is valid (rival undeployed) — only wait until the snapshot arrives.
	return _rival_fleet_synced


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
	if match_ctrl.has_method("mark_empty_open_fleet_trusted"):
		match_ctrl.mark_empty_open_fleet_trusted(_rival_fleet_synced)
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
	## PVE Prepare: clear leftover AI/creeps; roster locks at Prepare→Battle with current gold.
	_nullsec_clear_creep_field()
	_nullsec_after_slide_done()


func _nullsec_clear_creep_field() -> void:
	if board == null:
		return
	for s: ShipUnit in board.all_ships().duplicate():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if TypedVariant.as_int(s.team_id, 0) == ShipUnit.TEAM_AI or s.is_protect_target:
			board.remove_ship_node(s)
	board.set_titan_fetter_race(ShipUnit.TEAM_AI, "")
	board.set_titan_fetter_race(ShipUnit.TEAM_PLAYER, _local_titan_race_for_ui())


## Prepare→Battle: lock creeps with floor(gold/2)+field cost, then spawn (§5.1.2).
func _nullsec_relock_creeps_before_battle() -> void:
	if GameSession.pending_mode != "nullsec" or _nullsec_pve == null or match_ctrl == null or board == null:
		return
	if _nullsec_pve.always_pvp or not _nullsec_local_is_pve():
		return
	var pop: int = match_ctrl.population_limit()
	var field_v: int = match_ctrl.field_ships_cost_sum(ShipUnit.TEAM_PLAYER)
	_nullsec_pve.lock_creeps(match_ctrl.player_gold, match_ctrl.player_level, pop, field_v)
	SessionDiagnostics.log(
		"mp.creep_budget",
		"gold=%d field_v=%d budget=%d cap_pop=%d" % [
			match_ctrl.player_gold,
			field_v,
			maxi(0, floori(float(match_ctrl.player_gold) * 0.5)) + maxi(0, field_v),
			pop,
		]
	)
	if _nullsec_pve.current_task == NullsecPveDirector.TASK_SALVAGE:
		_nullsec_pve.pick_freighter_id(_local_titan_race_for_ui())
	_spawn_nullsec_creeps_for_battle()


func _spawn_nullsec_creeps_for_battle() -> void:
	## Place at final cells before combat opens (no await — avoids empty-side wipe).
	_nullsec_clear_creep_field()
	var roster: Array = _nullsec_pve.creep_ai.locked_roster
	var fh: int = TypedVariant.as_int(DataStore.board.get("field_height", 6), 0)
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
		board.spawn_ship(sid, 1, ShipUnit.TEAM_AI, "field", x, z)
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
		var fr: ShipUnit = board.spawn_ship(fid, 1, ShipUnit.TEAM_AI, "field", cx, cz)
		if fr:
			fr.team_id = ShipUnit.TEAM_PLAYER
			fr.field_side_team = ShipUnit.TEAM_AI
	_nullsec_pve.slide_done = true
	show_notice("人机编队就位")


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
	_net_battle.manned_count_fn = Callable(self, "_net_manned_field_count_for_seat")
	## SEMI_ASYNC §3.1a — watch peers skip CombatResolver; keep normal sync cadence.
	## Do NOT densify snaps (≤5): full apply_authority each snap stutters guests.
	if not net.authority_snapshot_bin_received.is_connected(_on_net_authority_snapshot):
		net.authority_snapshot_bin_received.connect(_on_net_authority_snapshot)
	if not net.authority_light_bin_received.is_connected(_on_net_authority_light):
		net.authority_light_bin_received.connect(_on_net_authority_light)
	if not net.battle_report_received.is_connected(_on_net_battle_report):
		net.battle_report_received.connect(_on_net_battle_report)
	if not _net_battle.battle_report.is_connected(_on_net_battle_report):
		_net_battle.battle_report.connect(_on_net_battle_report)
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


func _on_net_authority_snapshot(data: PackedByteArray) -> void:
	if _net_battle:
		_net_battle.apply_full_bin(data, board, firing_fx, _net_float_text())


func _on_net_authority_light(data: PackedByteArray) -> void:
	if _net_battle:
		_net_battle.apply_light_bin(data, board, firing_fx, _net_float_text())


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
	if str(report.get("kind", "")) == "pvp_ai_instant" and str(report.get("result", "")) == "dual_win":
		_apply_ai_vs_ai_instant_settle(report)
	elif str(report.get("kind", "")) == "pve_ai_instant" and str(report.get("result", "")) == "win":
		_apply_ai_pve_instant_settle(report)


func _net_manned_field_count_for_seat(seat_id: int) -> int:
	## AI seats: prefer live TEAM_AI field when this seat is the current rival; else field_cap estimate.
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null:
		var cached_n: int = net.manned_field_count_cached(seat_id)
		if cached_n > 0:
			return cached_n
	if not _seat_is_ai(seat_id):
		return 0
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	if rival == seat_id and board != null:
		var live: int = 0
		for s: ShipUnit in board.all_ships():
			if s == null or not is_instance_valid(s) or s.is_unmanned:
				continue
			if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_AI:
				continue
			if s.slot_type != "field":
				continue
			live += 1
		if live > 0:
			return live
	if ai != null and ai.has_method("field_cap"):
		return maxi(0, TypedVariant.as_int(ai.field_cap(), 0))
	return 0


func _apply_ai_vs_ai_instant_settle(report: Dictionary) -> void:
	## MATCH_FLOW §5.0 — dual win, kill gold, no titan (local human tables unaffected).
	var seat_a: int = TypedVariant.as_int(report.get("seat_a", -1), -1)
	var seat_b: int = TypedVariant.as_int(report.get("seat_b", -1), -1)
	var gold_a: int = TypedVariant.as_int(report.get("gold_a", 0), 0)
	var gold_b: int = TypedVariant.as_int(report.get("gold_b", 0), 0)
	_record_seat_win_only(seat_a)
	_record_seat_win_only(seat_b)
	## Shared local AI bank: grant both seat awards so handbook economy stays hot.
	if ai != null and ai.has_method("add_gold"):
		var grant: int = gold_a + gold_b
		if grant > 0:
			ai.add_gold(grant)
		if ai.has_method("update_streaks"):
			ai.update_streaks(true)
	_append_battle_log("人机↔人机略过 · 席%02d/+%d · 席%02d/+%d · 双胜无扣血" % [
		seat_a + 1, gold_a, seat_b + 1, gold_b
	])


func _apply_ai_pve_instant_settle(report: Dictionary) -> void:
	## MATCH_FLOW §5.0 — AI PVE instant win + kill gold; no titan / creeps.
	var seat: int = TypedVariant.as_int(report.get("seat", -1), -1)
	var gold: int = TypedVariant.as_int(report.get("gold", 0), 0)
	_record_seat_win_only(seat)
	if ai != null and ai.has_method("add_gold") and gold > 0:
		ai.add_gold(gold)
		if ai.has_method("update_streaks"):
			ai.update_streaks(true)
	_append_battle_log("人机PVE略过 · 席%02d/+%d · 直接胜" % [seat + 1, gold])


func _record_seat_win_only(seat: int) -> void:
	if seat < 0:
		return
	var cur: Dictionary = _wld_tuple(seat)
	cur["w"] = TypedVariant.as_int(cur.get("w", 0), 0) + 1
	_wld_by_seat[seat] = cur
	_eval_human_streak[seat] = TypedVariant.as_int(_eval_human_streak.get(seat, 0), 0) + 1


## SEMI_ASYNC §3.1a — PVP watch peers only. PVE is per-seat local (§3.2): ignore.
func _on_net_battle_ended(host_result: String, host_seat: int, reason: String) -> void:
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		return
	## One seat finishing creeps must not force-end another seat's local PVE.
	if _nullsec_local_is_pve():
		print("[mp.diag] battle_ended_rpc IGNORED pve_local reason=%s" % reason)
		SessionDiagnostics.log("mp.battle_ended_rpc", "ignored_pve_local reason=%s" % reason)
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
		_net_battle.apply_authority(snap)


func _on_net_round_jobs_complete(_reports: Array) -> void:
	_net_jobs_ready_for_titan = true
	## Resume settle path that was held for HostSim jobs — never leave finalize stashed forever.
	if _nullsec_prepare_pending and not _doomsday_busy and not _titan_kill_busy \
			and GameSession.pending_mode == "nullsec":
		SessionDiagnostics.log("eval.resume", "reason=jobs_complete")
		_nullsec_prepare_pending = false
		_nullsec_after_battle_into_prepare()


func _tick_net_battle_enrich() -> void:
	if _net_battle == null or board == null:
		return
	if not _net_battle.is_host:
		return
	## PVE creep fights are per-seat local — do not broadcast host board over guests.
	if _nullsec_pve != null and _nullsec_pve.is_pve_task():
		return
	if _net_battle.should_enrich_this_tick():
		var gold: int = TypedVariant.as_int(match_ctrl.player_gold_earned, 0) if match_ctrl else 0
		_net_battle.enrich_and_broadcast(board, gold)
		return
	if _net_battle.should_light_now():
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
	## Open shop; camera follows HUD default (UI_AND_SHELL §2.3).
	_collapse_bottom = false
	_apply_adaptive_hud_layout()
	_sync_default_camera_to_hud()
	show_notice("人机编队就位 · 商店已开")

func _nullsec_pick_next_task() -> void:
	## Pick next round task only — creep roster locks at Prepare→Battle with current gold.
	if _nullsec_pve == null or match_ctrl == null:
		return
	var round_r: int = maxi(1, match_ctrl.battle_game_stage_count + 1)
	_nullsec_pve.setup(_nullsec_rng, round_r)
	_nullsec_pve.pick_task(round_r)
	_nullsec_pve.creep_ai.locked_roster.clear()
	_nullsec_pve.creep_ai.locked = false
	_nullsec_rebuild_matchups()
	if _nullsec_pve.always_pvp or not _nullsec_local_is_pve():
		return
	## Salvage freighter id chosen at battle lock (current gold path).


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
		## Solo: no parallel tables — never arm conditional wall-clock draw.
		_nullsec_speed.mark_seat_finished(cur, false)
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
		## Prefer after_battle so pending combat_eval finalize still runs.
		if not _pending_combat_eval_finalize.is_empty() or _combat_eval_active:
			_nullsec_after_battle_into_prepare()
		else:
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
		## Match over: do not open spectate — settle (MULTIPLAYER_MATCH_FLOW §3.3).
		if _try_nullsec_end_if_alive_gate():
			return
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
		if not _pending_combat_eval_finalize.is_empty() or _combat_eval_active:
			_nullsec_after_battle_into_prepare()
		else:
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

## Opposing seat for this PVP round, or -1 when bye / no matchup / no contender.
## Prefers pending_nullsec.round_matchups (MATCH_FLOW §5.2). Never falls back to local_seat.
func _nullsec_rival_seat(local_seat: int) -> int:
	var mu: Dictionary = TypedVariant.as_dict(GameSession.pending_nullsec.get("round_matchups", {}))
	if not mu.is_empty():
		var from_mu: int = NullsecRoundPairing.rival_from_matchups(mu, local_seat)
		if from_mu >= 0:
			if _seat_titan_alive(from_mu):
				return from_mu
			return -1
		if TypedVariant.as_int(mu.get("bye_seat", -1), -1) == local_seat:
			return -1
		if TypedVariant.as_dict(mu.get("rival_of", {})).has(local_seat) \
			or not TypedVariant.as_array(mu.get("pairs", [])).is_empty():
			return -1
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
		if not NullsecNetSession.is_player_race(str(d.get("titan_race", ""))):
			continue
		if not _seat_titan_alive(sid):
			continue
		return sid
	return -1


## This client plays sleeper PVE this round (global PVE schedule or odd-player bye).
func _nullsec_local_is_pve() -> bool:
	if _nullsec_pve == null:
		return false
	if _nullsec_pve.is_pve_task():
		return true
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var bye: int = TypedVariant.as_int(
		TypedVariant.as_dict(GameSession.pending_nullsec.get("round_matchups", {})).get("bye_seat", -1),
		-1
	)
	return bye >= 0 and bye == local_seat


func _nullsec_collect_contenders() -> Array:
	var out: Array = []
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	var asg: Dictionary = TypedVariant.as_dict(GameSession.pending_nullsec.get("assignments", {}))
	for s_v: Variant in seats:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		var race: String = str(s.get("titan_race", ""))
		if not NullsecNetSession.is_player_race(race):
			continue
		var sid: int = TypedVariant.as_int(s.get("seat_id", -1), -1)
		if sid < 0 or not _seat_titan_alive(sid):
			continue
		var region: String = str(s.get("region_id", ""))
		if region == "" and asg.has(sid):
			region = str(asg.get(sid, ""))
		elif region == "" and asg.has(str(sid)):
			region = str(asg.get(str(sid), ""))
		out.append({
			"seat_id": sid,
			"is_ai": TypedVariant.as_bool(s.get("is_ai", false), false),
			"region_id": region,
		})
	return out


func _nullsec_rebuild_matchups() -> void:
	if _nullsec_pve == null:
		return
	var round_r: int = maxi(1, match_ctrl.battle_game_stage_count + 1) if match_ctrl else 1
	GameSession.pending_nullsec["round_r"] = round_r
	var last_map: Dictionary = TypedVariant.as_dict(GameSession.pending_nullsec.get("last_rival_by_seat", {}))
	## Global sleeper round: no PVP pairs; clear matchups.
	if _nullsec_pve.is_pve_task() and not _nullsec_pve.always_pvp:
		var empty_mu: Dictionary = {"pairs": [], "bye_seat": -1, "rival_of": {}, "degraded": false}
		GameSession.pending_nullsec["round_matchups"] = empty_mu
		var net_e: NullsecNetSession = _nullsec_net_session()
		if net_e != null and net_e.is_host:
			net_e.publish_round_matchups(empty_mu, last_map, round_r)
		return
	## All peers rebuild with MatchRng + last_rival (MATCH_FLOW §5.2); host re-broadcasts.
	var contenders: Array = _nullsec_collect_contenders()
	var mu: Dictionary = NullsecRoundPairing.build_matchups(
		contenders, last_map, _nullsec_rng, round_r
	)
	GameSession.pending_nullsec["round_matchups"] = mu
	if TypedVariant.as_bool(mu.get("degraded", false), false):
		SessionDiagnostics.log("mp.pair_degrade", "round=%d bye=%d pairs=%d" % [
			round_r,
			TypedVariant.as_int(mu.get("bye_seat", -1), -1),
			TypedVariant.as_array(mu.get("pairs", [])).size(),
		])
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and net.is_host:
		net.publish_round_matchups(mu, last_map, round_r)
	_nullsec_apply_bye_pve_task(round_r)


func _nullsec_apply_bye_pve_task(round_r: int) -> void:
	## Odd bye on a PVP schedule round: force local sleeper task (eliminate/salvage).
	if _nullsec_pve == null or _nullsec_pve.always_pvp:
		return
	if _nullsec_pve.is_pve_task():
		return
	if not _nullsec_local_is_pve():
		return
	_nullsec_pve.current_task = NullsecPveDirector.roll_pve_task(_nullsec_rng, round_r, round_r)
	SessionDiagnostics.log("mp.bye_pve", "seat=%d task=%s" % [
		TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0),
		_nullsec_pve.current_task,
	])


func _on_net_round_matchups(matchups: Dictionary, last_rival_by_seat: Dictionary, round_r: int) -> void:
	GameSession.pending_nullsec["round_matchups"] = TypedVariant.as_dict(matchups).duplicate(true)
	GameSession.pending_nullsec["last_rival_by_seat"] = TypedVariant.as_dict(last_rival_by_seat).duplicate(true)
	GameSession.pending_nullsec["round_r"] = round_r
	_nullsec_apply_bye_pve_task(round_r)


func _nullsec_advance_last_rivals_after_round() -> void:
	if _nullsec_pve == null:
		return
	var contenders: Array = _nullsec_collect_contenders()
	var seats_ids: Array = []
	for c_v: Variant in contenders:
		seats_ids.append(TypedVariant.as_int(TypedVariant.as_dict(c_v).get("seat_id", -1), -1))
	## Also include bye/pair seats from the round that just finished (may now be dead).
	var mu: Dictionary = TypedVariant.as_dict(GameSession.pending_nullsec.get("round_matchups", {}))
	for p_v: Variant in TypedVariant.as_array(mu.get("pairs", [])):
		var p: Array = TypedVariant.as_array(p_v)
		for x_v: Variant in p:
			var x: int = TypedVariant.as_int(x_v, -1)
			if x >= 0 and not seats_ids.has(x):
				seats_ids.append(x)
	var bye: int = TypedVariant.as_int(mu.get("bye_seat", -1), -1)
	if bye >= 0 and not seats_ids.has(bye):
		seats_ids.append(bye)
	var finished_r: int = maxi(1, match_ctrl.battle_game_stage_count) if match_ctrl else 1
	var global_pve: bool = (
		_nullsec_pve != null
		and not _nullsec_pve.always_pvp
		and not NullsecPveDirector.is_pvp_round(finished_r)
	)
	var prev: Dictionary = TypedVariant.as_dict(GameSession.pending_nullsec.get("last_rival_by_seat", {}))
	var nxt: Dictionary = NullsecRoundPairing.advance_last_rivals(prev, mu, seats_ids, global_pve)
	GameSession.pending_nullsec["last_rival_by_seat"] = nxt


## Contestant seats (player-race, incl. AI players; not creeps/spectators) with titan still alive.
func _count_nullsec_alive_contestants() -> int:
	var n: int = 0
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
		var sid: int = TypedVariant.as_int(s.get("seat_id", -1), -1)
		if sid < 0:
			continue
		if _seat_titan_alive(sid):
			n += 1
	return n


## After doomsday/kill FX: if ≤1 contestant titan remains, settle instead of next Prepare.
func _try_nullsec_end_if_alive_gate() -> bool:
	if str(GameSession.pending_mode) != "nullsec":
		return false
	var n: int = _count_nullsec_alive_contestants()
	if n > 1:
		return false
	SessionDiagnostics.log_critical("match.nullsec_end", "alive=%d" % n)
	_show_nullsec_settlement("负安终局 · 存活%d" % n)
	return true

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
	## Re-resolve roster every vote so late joiners / stale pending_nullsec cannot unlock 1-seat "unanimous".
	_sync_required_speed_seats()
	_nullsec_speed.set_vote(seat, speed)
	var seats_ui: Array = _speed_vote_seats_snapshot()
	if _speed_dropdown:
		_speed_dropdown.refresh_list(seats_ui)
	var wait_n: int = _nullsec_speed.waiting_count()
	if wait_n > 0:
		show_notice("等待 %d 人同档 → %s" % [wait_n, SpeedDropdownMenu._label(speed)])
	else:
		show_notice("对局倍速 %s" % SpeedDropdownMenu._label(speed))
	_apply_resolved_speed()


func _speed_vote_seats_snapshot() -> Array:
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and net.seats.size() > 0:
		return net.seats.duplicate(true)
	@warning_ignore("unsafe_cast")
	return GameSession.pending_nullsec.get("seats", []) as Array


func _sync_required_speed_seats() -> void:
	if _nullsec_speed == null:
		return
	if _speed_seat_sync_guard:
		return
	_speed_seat_sync_guard = true
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and net.needs_stage_barrier():
		_nullsec_speed.strict_seat_list = true
	var req: PackedInt32Array = PackedInt32Array()
	var seats: Array = _speed_vote_seats_snapshot()
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
		var sid: int = TypedVariant.as_int(s.get("seat_id", -1), -1)
		if sid < 0:
			continue
		req.append(sid)
	_nullsec_speed.set_required_human_seats(req)
	_speed_seat_sync_guard = false


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
	## Do NOT call _sync_required_speed_seats here — set_required_human_seats → _recompute →
	## speed_changed → this function → infinite recursion (mobile host ANR after 4_ns_rt2b_signals_ok).
	var spd: float = _nullsec_speed.current_speed()
	var persist: bool = _nullsec_speed.should_persist_preferred()
	if match_ctrl.has_method("set_battle_speed"):
		match_ctrl.set_battle_speed(spd, persist)
	SessionDiagnostics.log(
		"mp.speed",
		"resolved=%.2f persist=%s votes=%d req=%d strict=%s" % [
			spd,
			persist,
			_nullsec_speed.human_votes.size(),
			_nullsec_speed.required_human_seats.size(),
			_nullsec_speed.strict_seat_list,
		]
	)
	_refresh_hud()

func _on_nullsec_force_draw() -> void:
	show_notice("墙钟 2 分钟到 · 剩余对局判平局")
	if match_ctrl and match_ctrl.has_method("force_draw_battle"):
		match_ctrl.force_draw_battle()


func _nullsec_should_arm_wall_draw() -> bool:
	## SEMI_ASYNC §4.5 — conditional: someone finished AND ≥1 contestant still fighting.
	if match_ctrl != null and match_ctrl.stage == MatchController.Stage.BATTLE:
		return true
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null or not net.needs_stage_barrier():
		return false
	return net.has_battle_done_missing_humans()


func _on_seat_battle_finished_speed(seat: int) -> void:
	## SEMI_ASYNC §4.5 — manned finish → max(4×, 场上); AI seats never arm.
	if _nullsec_speed == null:
		return
	if _seat_is_ai(seat):
		SessionDiagnostics.log("mp.wall_draw", "ignore_ai_seat=%d" % seat)
		return
	var cur: float = TypedVariant.as_float(match_ctrl.speed_multiplier, 1.0) if match_ctrl else 1.0
	var arm_wall: bool = _nullsec_should_arm_wall_draw()
	_nullsec_speed.mark_seat_finished(cur, arm_wall)
	_apply_resolved_speed()
	SessionDiagnostics.log("mp.wall_draw", "arm=%s seat=%d" % [arm_wall, seat])


func _on_battle_done_all_ready_clear_speed() -> void:
	## All tables finished this round — drop conditional wall draw + auto 4× before next Battle.
	if _nullsec_speed == null:
		return
	_nullsec_speed.clear_finish_state()
	_apply_resolved_speed()
	SessionDiagnostics.log("mp.wall_draw", "cleared_all_ready")

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
		SessionDiagnostics.log_critical(
			"match.boot_phase",
			"phase=1_mapenv mode=%s %s" % [_boot_mode, SessionDiagnostics.mem_detail()]
		)
		MatchLoadOverlay.set_phase("正在布置战场环境", 0.34)
		_boot_env = MapEnv.new()
		_boot_env.name = "MapEnv"
		world.add_child(_boot_env)
		## Structures (titans/citadels) sync here; asteroids step below / next frames.
		_boot_env.begin_stepwise(_boot_mode)
		_apply_env_load_overlay(_boot_env)
		SessionDiagnostics.log_critical(
			"match.boot_phase",
			"phase=1_mapenv_begun mode=%s %s" % [_boot_mode, SessionDiagnostics.mem_detail()]
		)
		return
	if _boot_phase == 2:
		if _boot_env == null or not is_instance_valid(_boot_env):
			push_warning("MatchRoot boot: MapEnv missing; finishing without belt step")
			_boot_phase = 3
			SessionDiagnostics.log_critical("match.boot_phase", "phase=2_env_missing %s" % SessionDiagnostics.mem_detail())
			return
		var done: bool = _boot_env.tick_stepwise()
		_apply_env_load_overlay(_boot_env)
		if done:
			_bind_map_env(_boot_env, _boot_mode)
			_boot_env = null
			_boot_phase = 3
			SessionDiagnostics.log_critical(
				"match.boot_phase",
				"phase=2_env_done mode=%s %s" % [_boot_mode, SessionDiagnostics.mem_detail()]
			)
		return
	if _boot_phase == 3:
		MatchLoadOverlay.set_phase("正在初始化对局", 0.93)
		## Prevent re-entry if start_match yields / takes multiple frames.
		_boot_phase = 4
		SessionDiagnostics.log_critical(
			"match.boot_phase",
			"phase=3_start_match mode=%s %s" % [_boot_mode, SessionDiagnostics.mem_detail()]
		)
		match_ctrl.start_match(_boot_mode)
		SessionDiagnostics.log_critical(
			"match.boot_phase",
			"phase=3_start_match_returned mode=%s %s" % [_boot_mode, SessionDiagnostics.mem_detail()]
		)
		if _boot_mode == "nullsec":
			## Spread nullsec wire across frames — same-frame after MapEnv ANRs mobile hosts.
			_nullsec_rt_step = 0
			_boot_phase = 5
			MatchLoadOverlay.set_phase("正在装配联机运行时", 0.95)
			return
		_finish_match_boot()
		return
	if _boot_phase == 5:
		## Nullsec runtime chunks (DIAGNOSTICS §2.2 · phase=4_ns_rt*).
		if not _tick_nullsec_runtime_setup():
			return
		SessionDiagnostics.log_critical(
			"match.boot_phase",
			"phase=4_nullsec_runtime_done %s" % SessionDiagnostics.mem_detail()
		)
		_finish_match_boot()


func _finish_match_boot() -> void:
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
	_nullsec_rt_step = -1
	SessionDiagnostics.log_critical("match.boot_done", "mode=%s %s" % [_boot_mode, SessionDiagnostics.mem_detail()])
	SessionDiagnostics.end_critical_window()


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
	## HUD default camera (UI_AND_SHELL §2.3) — first default synced from match.tscn Camera3D.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var start: Dictionary = _camera_hud_default_view()
	_cam_base_pos = TypedVariant.as_vector3(start.get("pos", Vector3(-0.7521, 35.3927, 29.2707)), Vector3(-0.7521, 35.3927, 29.2707))
	_cam_base_pitch_deg = TypedVariant.as_float(start.get("pitch_deg", -57.0), 0.0)
	_cam_default_pitch_deg = _cam_base_pitch_deg
	_cam_base_yaw_deg = TypedVariant.as_float(start.get("yaw_deg", 0.0), 0.0)
	camera.fov = TypedVariant.as_float(start.get("fov", 47.0), 0.0)
	camera.position = _cam_base_pos
	camera.rotation_degrees = Vector3(_camera_pitch_now(), _cam_base_yaw_deg, 0)

func _camera_view_from_prefix(prefix: String, fb: Dictionary) -> Dictionary:
	var v: Dictionary = DataStore.visual
	var fb_pos: Vector3 = TypedVariant.as_vector3(fb.get("pos", Vector3(-0.7521, 35.3927, 29.2707)), Vector3(-0.7521, 35.3927, 29.2707))
	var fb_pitch: float = TypedVariant.as_float(fb.get("pitch_deg", -57.0), 0.0)
	var fb_yaw: float = TypedVariant.as_float(fb.get("yaw_deg", 0.0), 0.0)
	var fb_fov: float = TypedVariant.as_float(fb.get("fov", 47.0), 0.0)
	return {
		"pos": Vector3(
			TypedVariant.as_float(v.get(prefix + "_x", fb_pos.x), 0.0),
			TypedVariant.as_float(v.get(prefix + "_height", fb_pos.y), 0.0),
			TypedVariant.as_float(v.get(prefix + "_distance", fb_pos.z), 0.0)
		),
		"pitch_deg": -TypedVariant.as_float(v.get(prefix + "_angle_deg", -fb_pitch), 0.0),
		"yaw_deg": TypedVariant.as_float(v.get(prefix + "_yaw_deg", fb_yaw + 180.0), 0.0) - 180.0,
		"fov": TypedVariant.as_float(v.get(prefix + "_fov", fb_fov), 0.0)
	}

func _camera_primary_view() -> Dictionary:
	## Bottom bar expanded (right column ignored).
	return _camera_view_from_prefix("camera", {
		"pos": Vector3(-0.7521, 35.3927, 29.2707),
		"pitch_deg": -57.0,
		"yaw_deg": 0.0,
		"fov": 47.0
	})

func _camera_hud_default_view() -> Dictionary:
	## UI_AND_SHELL §2.3 — default pose from bottom + right collapse only.
	if not _collapse_bottom:
		return _camera_primary_view()
	var primary: Dictionary = _camera_primary_view()
	if _collapse_right:
		return _camera_view_from_prefix("camera_collapsed_bottom_right", primary)
	return _camera_view_from_prefix("camera_collapsed_bottom", primary)

func _camera_secondary_view() -> Dictionary:
	## Legacy alias — dual default views removed; always same as first default.
	return _camera_primary_view()

func _camera_active_view() -> Dictionary:
	return _camera_hud_default_view()

func _sync_default_camera_to_hud(smooth: bool = true) -> void:
	if _camera_manual_pose():
		return
	_apply_camera_view_dict(_camera_hud_default_view(), smooth)


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
	_hud_refresh_since_s += delta
	_try_flush_hud_refresh()
	_tick_collapse_arrow_frame_pulse()
	if _applying_rival_fleet and not _rival_fleet_queue.is_empty():
		_process_rival_fleet_queue()
	_tick_titan_intro(delta)
	_tick_info_hold()
	_tick_equipment_detail_hover()
	_tick_scout_departs(delta)
	_rank_refresh_accum += delta
	if _rank_refresh_accum >= 1.0:
		_rank_refresh_accum = 0.0
		if _right_pane_mode == RightPaneMode.RANK:
			_refresh_rank_panel()
	## Every frame: stem stays world-vertical while hull rotates / soft-follows.
	_sync_all_tactical_stems()
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
		elif _net_battle:
			## SEMI_ASYNC §3.1a — guests coast on inertia between packets.
			_net_battle.guest_present_tick(
				delta, firing_fx, _net_float_text(),
				match_ctrl.speed_multiplier if match_ctrl else 1.0
			)
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
				_log_camera_pose()
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
			show_notice("自由视角 · WASD世界轴移动 QE升降 · 中键环视 · 顶栏切回 · V记镜头")
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
	_sync_default_camera_to_hud(true)

func _apply_camera_view_dict(view: Dictionary, smooth: bool = true) -> void:
	## Free / observe own their pose; stage / shop / framing must not rewrite it.
	if _camera_manual_pose():
		return
	_cam_default_pitch_deg = TypedVariant.as_float(view.get("pitch_deg", _cam_default_pitch_deg), 0.0)
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
	## Bottom-bar expand: blend to HUD default (UI_AND_SHELL §2.3).
	_sync_default_camera_to_hud()


func _on_shop_collapsed_camera() -> void:
	_cam_pose_before_shop_valid = false
	_cam_pose_before_shop.clear()
	_sync_default_camera_to_hud()


func _log_camera_pose() -> void:
	if camera == null:
		return
	## Logical pose only: `_cam_base_*` excludes breathe figure-8, framing pull, headup, titan shake.
	var mode: String = "observe" if _camera_observe else ("free" if _camera_free else "default")
	var pos: Vector3 = _cam_base_pos
	var pitch: float = _cam_base_pitch_deg
	var yaw: float = _cam_base_yaw_deg
	var fov: float = camera.fov
	var line: String = (
		"mode=%s pos=%.4f,%.4f,%.4f pitch=%.4f yaw=%.4f fov=%.4f"
		% [mode, pos.x, pos.y, pos.z, pitch, yaw, fov]
	)
	print("cam.pose ", line)
	SessionDiagnostics.log("cam.pose", line)


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
		btn.tooltip_text = "点此回默认 · V 记镜头" if not UiLayout.is_mobile() else "当前：自由（触控绕心）"
	else:
		btn.text = "自由视角"
		btn.tooltip_text = "点此进自由 · V 记镜头" if not UiLayout.is_mobile() else "当前：默认"

func _update_camera_free(delta: float) -> void:
	if UiLayout.is_mobile():
		## Mobile free view is touch-orbit only; keep pose stable here.
		camera.position = _cam_base_pos
		camera.rotation_degrees = Vector3(_cam_base_pitch_deg, _cam_base_yaw_deg, 0.0)
		return
	## PC free fly: WASD on world XZ (not camera-relative); QE world up; no framing pull-back.
	var v: Dictionary = DataStore.visual
	var speed: float = TypedVariant.as_float(v.get("camera_free_move_speed", _CAM_MOVE_SPEED), 0.0)
	var move: Vector3 = Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move += Vector3(0.0, 0.0, -1.0)
	if Input.is_physical_key_pressed(KEY_S):
		move += Vector3(0.0, 0.0, 1.0)
	if Input.is_physical_key_pressed(KEY_A):
		move += Vector3(-1.0, 0.0, 0.0)
	if Input.is_physical_key_pressed(KEY_D):
		move += Vector3(1.0, 0.0, 0.0)
	if Input.is_physical_key_pressed(KEY_Q):
		move += Vector3(0.0, -1.0, 0.0)
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3(0.0, 1.0, 0.0)
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
	## Prepare: collapse events own the pose. Battle continuously locks the HUD default.
	if match_ctrl == null or match_ctrl.stage != MatchController.Stage.BATTLE:
		return
	var framing: Dictionary = DataStore.visual.get("camera_framing", {})
	var spd: float = TypedVariant.as_float(framing.get("lerp_speed", 4.0), 0.0)
	var view: Dictionary = _camera_hud_default_view()
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
	var view: Dictionary = _camera_hud_default_view()
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
			breathe_on = (PlayerSettings.instance() as PlayerSettings).camera_breathe_enabled
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
	_ensure_left_shop_layout()
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
		_ensure_concede_round_btn(top_r)
		_reorder_top_right_children(top_r as HBoxContainer)
		return
	var btn: ScoutIntelButton = ScoutIntelButton.new()
	btn.name = "ScoutIntelBtn"
	btn.visible = GameSession.pending_mode == "nullsec"
	top_r.add_child(btn)
	_ensure_concede_round_btn(top_r)
	_reorder_top_right_children(top_r as HBoxContainer)

func _ensure_concede_round_btn(top_r: Control) -> void:
	if top_r == null:
		return
	var existing: Button = top_r.get_node_or_null("ConcedeRoundBtn") as Button
	if existing != null:
		existing.visible = true
		return
	var btn: Button = Button.new()
	btn.name = "ConcedeRoundBtn"
	btn.text = "本回合认负"
	btn.tooltip_text = "本回合按被全灭结算（可续下一回合）"
	btn.pressed.connect(_on_concede_round_pressed)
	top_r.add_child(btn)

func _on_concede_round_pressed() -> void:
	if match_ctrl == null:
		return
	if match_ctrl.stage != MatchController.Stage.PREPARE and match_ctrl.stage != MatchController.Stage.BATTLE:
		return
	if _nullsec_spectating:
		show_notice("观战中无法认负")
		return
	match_ctrl.concede_current_round()
	show_notice("本回合认负")

func _reorder_top_right_children(top_r: HBoxContainer) -> void:
	## L→R tree order; HBox ALIGNMENT_END packs 菜单 at the right edge (右→左可读序).
	if top_r == null:
		return
	top_r.alignment = BoxContainer.ALIGNMENT_END
	var order: Array = ["Version", "ScoutIntelBtn", "ConcedeRoundBtn", "CamModeBtn", "SpeedBtn", "PauseBtn", "ExitBtn"]
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
	## LeftCol = ShopBuyCol | BonusScroll (plan J); InfoPanel body scrolls.
	_ensure_left_shop_layout()
	@warning_ignore("unsafe_cast")
	var left_content: Control = hud.get_node_or_null("Root/LeftCol/LeftInner/LeftContent") as Control
	if left_content:
		@warning_ignore("unsafe_cast")
		var fade_host: Control = left_content.get_node_or_null("BonusFadeHost") as Control
		@warning_ignore("unsafe_cast")
		var bonus: VBoxContainer = left_content.get_node_or_null("BonusContainer") as VBoxContainer
		@warning_ignore("unsafe_cast")
		var scroll: ScrollContainer = left_content.get_node_or_null("BonusScroll") as ScrollContainer
		if scroll == null and fade_host != null:
			scroll = fade_host.get_node_or_null("BonusScroll") as ScrollContainer
		if bonus == null and scroll != null:
			bonus = scroll.get_node_or_null("BonusContainer") as VBoxContainer
		if scroll == null and bonus != null:
			scroll = ScrollContainer.new()
			scroll.name = "BonusScroll"
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.size_flags_stretch_ratio = 0.42
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			## Fade strip is display-only; IGNORE so board ships stay clickable (UI_AND_SHELL §3.3).
			scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
			scroll.scroll_deadzone = 8 if UiLayout.is_mobile() else 0
			_apply_bonus_hfade(scroll)
		if bonus:
			bonus.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			bonus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bonus.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _apply_bonus_hfade(scroll: Control) -> void:
	## Fetter strip only: diagonal TL→BR fade + rounded cyan hairline (UI_AND_SHELL §2.1 / §3.3).
	if scroll == null:
		return
	var host: Control = scroll
	var parent: Node = scroll.get_parent()
	if parent != null and str(parent.name) == "BonusFadeHost":
		host = parent as Control
	elif parent != null and parent.get_node_or_null("BonusFadeHost") == null:
		var fade_host: Control = Control.new()
		fade_host.name = "BonusFadeHost"
		fade_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fade_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		fade_host.size_flags_stretch_ratio = 0.42
		fade_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var idx: int = scroll.get_index()
		parent.remove_child(scroll)
		parent.add_child(fade_host)
		parent.move_child(fade_host, idx)
		fade_host.add_child(scroll)
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host = fade_host
	elif parent != null:
		var existing: Control = parent.get_node_or_null("BonusFadeHost") as Control
		if existing != null:
			host = existing
			if scroll.get_parent() != host:
				_reparent_keep_signals(scroll, host)
				scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var old_overlay: Node = host.get_node_or_null("FetterFadeOverlay")
	if old_overlay:
		old_overlay.name = "FetterFadeOverlay_old"
		host.remove_child(old_overlay)
		old_overlay.free()
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## UI_AND_SHELL §2.1: fetter icons+text inset from cyan left border (not flush).
	var fade_root: Control = null
	if hud != null:
		@warning_ignore("unsafe_cast")
		fade_root = hud.get_node_or_null("Root") as Control
	var inset_l: float = float(UiLayout.margin_px(10, fade_root if fade_root else host))
	scroll.offset_left = inset_l
	var bg: HudFadePanel = _ensure_fade_panel(host, "FetterFadeBg")
	if bg:
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.move_child(bg, 0)
	_configure_fade_panel(bg, HudFadePanel.AXIS_DIAGONAL_TL_BR, 0.0, fade_root)


func _ensure_fade_panel(host: Control, node_name: String) -> HudFadePanel:
	if host == null:
		return null
	var old: Node = host.get_node_or_null(node_name)
	if old is HudFadePanel:
		return old as HudFadePanel
	if old != null:
		old.name = "%s_old" % node_name
		host.remove_child(old)
		old.free()
	var bg: HudFadePanel = HudFadePanel.new()
	bg.name = node_name
	host.add_child(bg)
	host.move_child(bg, 0)
	return bg


func _configure_fade_panel(bg: HudFadePanel, fade_axis: int, fade_start: float, root: Control) -> void:
	if bg == null:
		return
	var bw: float = 1.0
	var cr: float = 4.0
	if root != null:
		bw = float(maxi(1, UiLayout.margin_px(1, root)))
		cr = float(UiLayout.margin_px(4, root))
	bg.configure(fade_axis, fade_start, bw, cr)


func _apply_left_col_shell(root: Control) -> void:
	## LeftCol is a transparent layout host; shop frame lives on ShopBarPanel (UI_AND_SHELL §3.3).
	## Hard-bound: clip so children cannot paint outside the viewport strip.
	## Hosts IGNORE so fetter fade voids click-through to the board; ShopBarPanel stays STOP.
	if root == null:
		return
	var left_col: Control = root.get_node_or_null("LeftCol") as Control
	if left_col == null:
		return
	left_col.clip_contents = true
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left_inner: Control = left_col.get_node_or_null("LeftInner") as Control
	if left_inner:
		left_inner.clip_contents = true
		left_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_content: Control = left_col.get_node_or_null("LeftInner/LeftContent") as Control
	if left_content:
		left_content.clip_contents = true
		left_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar_panel: Control = root.get_node_or_null(_SHOP_BAR_PANEL) as Control
	if bar_panel:
		bar_panel.clip_contents = true
		bar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		bar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var shop_bar: Control = root.get_node_or_null(_SHOP_BAR) as Control
	if shop_bar:
		shop_bar.clip_contents = true
		shop_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if left_col is PanelContainer:
		var left_sb: StyleBoxFlat = StyleBoxFlat.new()
		left_sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		left_sb.border_color = Color(0.0, 0.0, 0.0, 0.0)
		left_sb.set_border_width_all(0)
		left_sb.set_content_margin_all(0)
		(left_col as PanelContainer).add_theme_stylebox_override("panel", left_sb)
		left_col.set_meta("_left_fade_sb", true)
	var old_bg: Node = left_col.get_node_or_null("LeftFadeBg")
	if old_bg != null:
		left_col.remove_child(old_bg)
		old_bg.free()
	var bonus_scroll: Control = _bonus_scroll_of(root)
	if bonus_scroll:
		_apply_bonus_hfade(bonus_scroll)


func _apply_bottom_vfade(bar: Control) -> void:
	## UI_AND_SHELL §2.1 / §3.3: original panel fill+border, opaque lower half, fade up.
	if bar == null:
		return
	if bar is PanelContainer:
		var shop_sb: StyleBoxFlat = StyleBoxFlat.new()
		shop_sb.bg_color = Color(0.07, 0.09, 0.11, 0.0)
		shop_sb.border_color = Color(0.35, 0.72, 0.85, 0.0)
		shop_sb.set_border_width_all(0)
		shop_sb.set_corner_radius_all(0)
		var side_m: int = UiLayout.margin_px(6, bar)
		var bot_m: int = maxi(1, side_m / 2)
		shop_sb.content_margin_left = side_m
		shop_sb.content_margin_right = side_m
		shop_sb.content_margin_top = side_m
		shop_sb.content_margin_bottom = bot_m
		(bar as PanelContainer).add_theme_stylebox_override("panel", shop_sb)
		bar.set_meta("_bottom_vfade_sb", true)
	var bg: HudFadePanel = _ensure_fade_panel(bar, "BottomFadeBg")
	if bg:
		bar.move_child(bg, 0)
	_configure_fade_panel(bg, HudFadePanel.AXIS_BOTTOM_UP, 0.5, bar)


func _bonus_scroll_of(root: Control) -> Control:
	if root == null:
		return null
	var s: Control = root.get_node_or_null(_BONUS_SCROLL) as Control
	if s:
		return s
	return root.get_node_or_null("LeftCol/LeftInner/LeftContent/BonusFadeHost/BonusScroll") as Control


func _bonus_container_of(root: Control) -> VBoxContainer:
	if root == null:
		return null
	var b: VBoxContainer = root.get_node_or_null(_BONUS) as VBoxContainer
	if b:
		return b
	b = root.get_node_or_null("LeftCol/LeftInner/LeftContent/BonusFadeHost/BonusScroll/BonusContainer") as VBoxContainer
	if b:
		return b
	return root.get_node_or_null(_BONUS_FALLBACK) as VBoxContainer


## Keep children/signals; swap HBox↔VBox (UI_AND_SHELL §3.2: rotate strip 90°).
func _rebox_as_axis(old: Control, vertical: bool) -> BoxContainer:
	if old == null:
		return null
	if vertical and old is VBoxContainer:
		return old as VBoxContainer
	if (not vertical) and old is HBoxContainer:
		return old as HBoxContainer
	var nb: BoxContainer
	if vertical:
		nb = VBoxContainer.new()
	else:
		nb = HBoxContainer.new()
	nb.name = old.name
	nb.size_flags_horizontal = old.size_flags_horizontal
	nb.size_flags_vertical = old.size_flags_vertical
	nb.size_flags_stretch_ratio = old.size_flags_stretch_ratio
	if old is BoxContainer:
		nb.add_theme_constant_override("separation", (old as BoxContainer).get_theme_constant("separation"))
	var kids: Array[Node] = []
	for c: Node in old.get_children():
		kids.append(c)
	for c2: Node in kids:
		old.remove_child(c2)
	var p: Node = old.get_parent()
	if p == null:
		for c3: Node in kids:
			nb.add_child(c3)
		old.queue_free()
		return nb
	var idx: int = old.get_index()
	p.remove_child(old)
	old.queue_free()
	p.add_child(nb)
	p.move_child(nb, idx)
	for c4: Node in kids:
		nb.add_child(c4)
	return nb


func _ensure_left_shop_layout(root: Control = null) -> void:
	## UI_AND_SHELL §2.1: framed ShopBar (6 squares + meta + exp/refresh) never collapses;
	## fetter fade to the right can fully collapse.
	if root == null and hud != null:
		@warning_ignore("unsafe_cast")
		root = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	var left_inner: Control = root.get_node_or_null("LeftCol/LeftInner") as Control
	if left_inner == null:
		return
	## Do not inherit old left-strip collapse chrome (top btn + vertical padding).
	left_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if left_inner is BoxContainer:
		(left_inner as BoxContainer).add_theme_constant_override("separation", 0)
	var leftover_cl: Control = left_inner.get_node_or_null("CollapseLeftBtn") as Control
	if leftover_cl != null and leftover_cl.get_parent() == left_inner:
		var chrome_cl: Node = root.get_node_or_null("LeftEdgeChrome/CollapseLeftBtn")
		if chrome_cl != null and chrome_cl != leftover_cl:
			left_inner.remove_child(leftover_cl)
			leftover_cl.queue_free()
			leftover_cl = null
		elif leftover_cl != null:
			leftover_cl.visible = false
			leftover_cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			leftover_cl.custom_minimum_size = Vector2.ZERO
	var left_content: Control = left_inner.get_node_or_null("LeftContent") as Control
	if left_content != null and left_content is VBoxContainer and not (left_content is HBoxContainer):
		left_content = _rebox_as_axis(left_content, false)
	elif left_content == null:
		left_content = HBoxContainer.new()
		left_content.name = "LeftContent"
		left_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_inner.add_child(left_content)
	left_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if left_content is HBoxContainer:
		(left_content as HBoxContainer).add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	var shop_bar_raw: Control = null
	var wrap_existing: Control = left_content.get_node_or_null("ShopBarPanel") as Control
	if wrap_existing != null:
		shop_bar_raw = wrap_existing.get_node_or_null("ShopBar") as Control
	if shop_bar_raw == null:
		shop_bar_raw = left_content.get_node_or_null("ShopBar") as Control
	if shop_bar_raw == null:
		shop_bar_raw = left_content.get_node_or_null("ShopBuyCol") as Control
		if shop_bar_raw != null:
			shop_bar_raw.name = "ShopBar"
	if shop_bar_raw == null:
		shop_bar_raw = VBoxContainer.new()
		shop_bar_raw.name = "ShopBar"
		left_content.add_child(shop_bar_raw)
		left_content.move_child(shop_bar_raw, 0)
	## Absolute snap host (UI_AND_SHELL §3.2) — not a VBox stretch fight.
	var shop_bar: Control = _ensure_shop_bar_abs_host(shop_bar_raw, left_content, root)
	shop_bar = _ensure_shop_bar_frame(left_content, shop_bar, root)
	var panel_now: Node = shop_bar.get_parent()
	if panel_now != null and panel_now.get_parent() == left_content:
		left_content.move_child(panel_now, 0)
	shop_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_bar.clip_contents = true
	## Flatten legacy ShopBody children onto ShopBar.
	var legacy_body: Control = shop_bar.get_node_or_null("ShopBody") as Control
	if legacy_body != null:
		for ch: Node in legacy_body.get_children():
			_reparent_keep_signals(ch, shop_bar)
		legacy_body.queue_free()
	## 1) Bottom buttons first (geometry applied in snap pass).
	var btns_raw: Control = shop_bar.get_node_or_null("ShopBtns") as Control
	if btns_raw == null:
		btns_raw = HBoxContainer.new()
		btns_raw.name = "ShopBtns"
		shop_bar.add_child(btns_raw)
	var shop_btns: BoxContainer = _rebox_as_axis(btns_raw, false)
	shop_btns.clip_contents = true
	shop_btns.add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	var btn_strip_h: float = UiLayout.hud_height("ExpBtn", 0.078) * UiLayout.viewport_size(root).y
	btn_strip_h = clampf(btn_strip_h, float(UiLayout.px(40, root)), float(UiLayout.px(72, root)))
	shop_btns.custom_minimum_size = Vector2(0.0, btn_strip_h)
	var exp_btn: Button = root.get_node_or_null("%s/LeftBtns/ExpBtn" % _SHOP_LEFT) as Button
	if exp_btn == null:
		exp_btn = shop_btns.get_node_or_null("ExpBtn") as Button
	if exp_btn:
		_reparent_keep_signals(exp_btn, shop_btns)
		shop_btns.move_child(exp_btn, 0)
		exp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exp_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var refresh_btn: Button = root.get_node_or_null("%s/LeftBtns/RefreshBtn" % _SHOP_LEFT) as Button
	if refresh_btn == null:
		refresh_btn = shop_btns.get_node_or_null("RefreshBtn") as Button
	if refresh_btn:
		_reparent_keep_signals(refresh_btn, shop_btns)
		shop_btns.move_child(refresh_btn, mini(1, shop_btns.get_child_count() - 1))
		refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		refresh_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_shop_action_buttons(root, shop_bar, shop_btns, exp_btn, refresh_btn)
	## 2) Left ship column (6 squares).
	var ship_raw: Control = shop_bar.get_node_or_null("ShipCol") as Control
	if ship_raw == null:
		ship_raw = shop_bar.get_node_or_null("ShopInner") as Control
	if ship_raw == null:
		ship_raw = root.get_node_or_null("Shop/ShopCol/ShopContent/ShopInner") as Control
		if ship_raw != null:
			_reparent_keep_signals(ship_raw, shop_bar)
	if ship_raw == null:
		ship_raw = VBoxContainer.new()
		ship_raw.name = "ShipCol"
		shop_bar.add_child(ship_raw)
	else:
		ship_raw.name = "ShipCol"
	var ship_col: BoxContainer = _rebox_as_axis(ship_raw, true)
	ship_col.clip_contents = true
	ship_col.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
	_ensure_ship_offer_host(ship_col, root)
	## 3) Advanced refresh square — direct ShopBar child for right/bottom snaps.
	var scan_w: int = UiLayout.px(56, root)
	if _hud_shop_card_side >= 8.0:
		scan_w = clampi(int(_hud_shop_card_side * 0.9), UiLayout.px(48, root), UiLayout.px(120, root))
	_ensure_ship_scanner_btn(root, scan_w, shop_bar)
	## 4) Meta rectangle above scanner: LevelExp | 5 equip (equip bottom-snaps to scanner).
	var meta_raw: Control = shop_bar.get_node_or_null("MetaCol") as Control
	if meta_raw == null:
		meta_raw = Control.new()
		meta_raw.name = "MetaCol"
		shop_bar.add_child(meta_raw)
	meta_raw = _ensure_plain_layout_host(meta_raw, "MetaCol", shop_bar)
	meta_raw.clip_contents = true
	var meta_mid: Control = _ensure_meta_mid(meta_raw, root)
	_ensure_rotated_level_exp(meta_mid, root)
	_ensure_equipment_slots_grid(meta_mid, shop_bar, root)
	## Drop legacy EquipScanCol — scanner is on ShopBar; equip stays in MetaMid.
	var legacy_esc: Control = null
	if meta_mid:
		legacy_esc = meta_mid.get_node_or_null("EquipScanCol") as Control
	if legacy_esc != null:
		var esc_equip: Control = legacy_esc.get_node_or_null("EquipmentSlots") as Control
		if esc_equip != null:
			_reparent_keep_signals(esc_equip, meta_mid)
		var esc_scan: Control = legacy_esc.get_node_or_null("ScannerHost") as Control
		if esc_scan != null:
			_reparent_keep_signals(esc_scan, shop_bar)
		legacy_esc.queue_free()
	if meta_mid:
		var le_host: Control = meta_mid.get_node_or_null("LevelExpHost") as Control
		if le_host:
			meta_mid.move_child(le_host, 0)
			le_host.size_flags_horizontal = 0
			le_host.size_flags_vertical = 0
		var equip_slots: Control = meta_mid.get_node_or_null("EquipmentSlots") as Control
		if equip_slots:
			meta_mid.move_child(equip_slots, mini(1, meta_mid.get_child_count() - 1))
			equip_slots.size_flags_horizontal = 0
			equip_slots.size_flags_vertical = 0
			if equip_slots is VBoxContainer:
				(equip_slots as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
	_apply_left_shop_snap_layout(root)
	call_deferred("_deferred_apply_left_shop_snap")
	## Fetter fade to the right of shop (collapsible).
	var bonus_scroll: Control = left_content.get_node_or_null("BonusScroll") as Control
	if bonus_scroll == null:
		var fh: Control = left_content.get_node_or_null("BonusFadeHost") as Control
		if fh != null:
			bonus_scroll = fh.get_node_or_null("BonusScroll") as Control
			left_content.move_child(fh, left_content.get_child_count() - 1)
	if bonus_scroll != null:
		if bonus_scroll.get_parent() == left_content:
			left_content.move_child(bonus_scroll, left_content.get_child_count() - 1)
		_apply_bonus_hfade(bonus_scroll)
	_ensure_bottom_gold_pop(root)
	_ensure_bottom_cluster(root)
	var shop_content: Control = root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	var meta_row: Control = root.get_node_or_null(_SHOP_META) as Control
	var cluster: Control = root.get_node_or_null(_BOTTOM_CLUSTER) as Control
	if cluster == null:
		cluster = shop_content
	if cluster != null:
		var grid: GridContainer = cluster.get_node_or_null("ReserveGrid") as GridContainer
		if grid == null and shop_content != null:
			grid = shop_content.get_node_or_null("ReserveGrid") as GridContainer
		if grid == null and meta_row != null:
			grid = meta_row.get_node_or_null("ReserveGrid") as GridContainer
		if grid == null:
			grid = root.get_node_or_null("EquipCol/EquipInner/ReserveGrid") as GridContainer
			if grid == null:
				grid = left_content.get_node_or_null("ReserveGrid") as GridContainer
		if grid == null:
			grid = GridContainer.new()
			grid.name = "ReserveGrid"
			cluster.add_child(grid)
		elif grid.get_parent() != cluster:
			_reparent_keep_signals(grid, cluster)
		grid.columns = 16
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.size_flags_vertical = Control.SIZE_SHRINK_END
		grid.set_anchors_preset(Control.PRESET_TOP_LEFT)
		grid.anchor_right = 0.0
		grid.anchor_bottom = 0.0
		if cluster is VBoxContainer:
			(cluster as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
			cluster.move_child(grid, cluster.get_child_count() - 1)
	if meta_row != null:
		meta_row.visible = false
	if shop_content != null:
		var leftover_inner: Control = shop_content.get_node_or_null("ShopInner") as Control
		if leftover_inner:
			leftover_inner.visible = false
			leftover_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left_ctrl: Control = root.get_node_or_null(_SHOP_LEFT) as Control
	if left_ctrl:
		left_ctrl.visible = false
	var shop_mid: Control = root.get_node_or_null(_SHOP_MID) as Control
	if shop_mid:
		shop_mid.visible = false
	var equip_col: Control = root.get_node_or_null("EquipCol") as Control
	if equip_col:
		equip_col.visible = false
		equip_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var equip_chrome: Control = root.get_node_or_null("EquipEdgeChrome") as Control
	if equip_chrome:
		equip_chrome.visible = false
		equip_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collapse_left_syn = _collapse_left
	_collapse_left_equip = _collapse_left


func _ensure_shop_bar_frame(left_content: Control, shop_bar: Control, _root: Control) -> Control:
	## Complete original side-panel StyleBox on ShopBarPanel (UI_AND_SHELL §2.1 / §3.3).
	if left_content == null or shop_bar == null:
		return shop_bar
	var bar_panel: PanelContainer = null
	var parent_n: Node = shop_bar.get_parent()
	if parent_n is PanelContainer and str(parent_n.name) == "ShopBarPanel":
		@warning_ignore("unsafe_cast")
		bar_panel = parent_n as PanelContainer
	else:
		bar_panel = PanelContainer.new()
		bar_panel.name = "ShopBarPanel"
		if parent_n != null:
			var idx: int = shop_bar.get_index()
			parent_n.remove_child(shop_bar)
			parent_n.add_child(bar_panel)
			parent_n.move_child(bar_panel, idx)
		else:
			left_content.add_child(bar_panel)
			left_content.move_child(bar_panel, 0)
		bar_panel.add_child(shop_bar)
	bar_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	bar_panel.clip_contents = true
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.11, 0.88)
	sb.border_color = Color(0.35, 0.72, 0.85, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	## No inner black pad — content flush to cyan hairline (UI_AND_SHELL §3.2 / §3.3).
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	bar_panel.add_theme_stylebox_override("panel", sb)
	shop_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return shop_bar


func _ensure_shop_bar_abs_host(shop_bar_raw: Control, left_content: Control, _root: Control) -> Control:
	## Convert legacy VBox ShopBar into plain Control absolute host.
	if shop_bar_raw == null:
		var created: Control = Control.new()
		created.name = "ShopBar"
		left_content.add_child(created)
		left_content.move_child(created, 0)
		return created
	if not (shop_bar_raw is BoxContainer):
		return shop_bar_raw
	return _ensure_plain_layout_host(shop_bar_raw, "ShopBar", shop_bar_raw.get_parent())


func _ensure_plain_layout_host(node: Control, host_name: String, parent: Node) -> Control:
	## Replace BoxContainer with Control keeping children (absolute snap parent).
	if node == null:
		return null
	if not (node is BoxContainer):
		node.name = host_name
		return node
	var host: Control = Control.new()
	host.name = host_name
	var idx: int = node.get_index()
	var kids: Array[Node] = []
	for c: Node in node.get_children():
		kids.append(c)
	for c2: Node in kids:
		node.remove_child(c2)
	var p: Node = parent if parent != null else node.get_parent()
	if p != null:
		p.remove_child(node)
		p.add_child(host)
		p.move_child(host, idx)
	node.queue_free()
	for c3: Node in kids:
		host.add_child(c3)
	return host


func _snap_control_rect(c: Control, x: float, y: float, w: float, h: float) -> void:
	## Absolute place. Do NOT zero custom_minimum_size — wiping LevelExpHost min made the
	## next snap fall back to ~36px and let EquipmentSlots eat the exp column (pause/HUD).
	if c == null:
		return
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.position = Vector2(x, y)
	c.size = Vector2(maxf(0.0, w), maxf(0.0, h))


func _deferred_apply_left_shop_snap() -> void:
	if hud == null:
		return
	var root: Control = hud.get_node_or_null("Root") as Control
	if root != null:
		_apply_left_shop_snap_layout(root)


func _shop_bar_frame_gutter(_root: Control) -> float:
	## ShopBarPanel has no inner content_margin (no fixed black pad). Keep 1px so
	## Meta/equip card borders sit just inside the cyan hairline, not on it.
	return 1.0


func _apply_left_shop_snap_layout(root: Control) -> void:
	## UI_AND_SHELL §3.2 吸靠：底钮 → 左 6 舰方 → 高级刷新方 → Meta 长方形(经验|5装).
	if root == null:
		return
	var bar: Control = root.get_node_or_null(_SHOP_BAR) as Control
	if bar == null or bar.size.x < 8.0 or bar.size.y < 8.0:
		return
	var gap: float = float(UiLayout.margin_px(4, root))
	var sep: float = float(UiLayout.margin_px(2, root))
	var gutter: float = _shop_bar_frame_gutter(root)
	var btns: Control = root.get_node_or_null(_SHOP_BTNS) as Control
	var btn_h: float = UiLayout.hud_height("ExpBtn", 0.078) * UiLayout.viewport_size(root).y
	btn_h = clampf(btn_h, float(UiLayout.px(40, root)), float(UiLayout.px(72, root)))
	if btns != null and btns.custom_minimum_size.y >= 8.0:
		btn_h = btns.custom_minimum_size.y
	var W: float = bar.size.x
	var H: float = bar.size.y
	## Shared right edge for Meta / equip / scanner — inset so card borders never sit on cyan frame.
	var inner_right: float = maxf(8.0, W - gutter)
	btn_h = minf(btn_h, maxf(8.0, H * 0.22))
	## 1) Bottom buttons full width of content (still under panel margins).
	if btns != null:
		_snap_control_rect(btns, 0.0, H - btn_h, W, btn_h)
		btns.size_flags_horizontal = 0
		btns.size_flags_vertical = 0
	var body_h: float = maxf(8.0, H - btn_h)
	var nslots: int = 6
	if shop != null and shop.slots.size() > 0:
		nslots = maxi(1, shop.slots.size())
	## 2) Left ship squares: side = body_h / n.
	var side: float = (body_h - sep * float(maxi(0, nslots - 1))) / float(nslots)
	side = clampf(side, float(UiLayout.px(28, root)), float(UiLayout.px(160, root)))
	side = minf(side, inner_right * 0.72)
	_hud_shop_card_side = side
	_hud_shop_card_size = Vector2(side, side)
	var ship_col: Control = root.get_node_or_null(_SHOP_INNER) as Control
	if ship_col != null:
		_snap_control_rect(ship_col, 0.0, 0.0, side, body_h)
		ship_col.size_flags_horizontal = 0
		ship_col.size_flags_vertical = 0
		var offer: Control = root.get_node_or_null(_SHOP_OFFER_HOST) as Control
		if offer != null:
			offer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			offer.custom_minimum_size = Vector2(side, 0.0)
		var slots: Control = root.get_node_or_null(_SHOP_SLOTS) as Control
		if slots != null:
			slots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			slots.custom_minimum_size = Vector2(side, 0.0)
			if slots is VBoxContainer:
				(slots as VBoxContainer).add_theme_constant_override("separation", int(sep))
	## 3) Scanner square: left→ship, bottom→btns, right→inner_right (not raw W).
	var rem_w: float = maxf(8.0, inner_right - side - gap)
	var scan_side: float = minf(rem_w, body_h)
	var scan_x: float = inner_right - scan_side
	if rem_w <= body_h + 0.5:
		scan_side = rem_w
		scan_x = side + gap
	var scan_y: float = body_h - scan_side
	var scanner: Control = root.get_node_or_null(_SHOP_SCANNER_HOST) as Control
	if scanner != null:
		_snap_control_rect(scanner, scan_x, scan_y, scan_side, scan_side)
		scanner.size_flags_horizontal = 0
		scanner.size_flags_vertical = 0
		scanner.custom_minimum_size = Vector2(scan_side, scan_side)
		var frame: Control = scanner.get_node_or_null("ScannerFrame") as Control
		if frame != null:
			frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			frame.custom_minimum_size = Vector2.ZERO
	## 4) Meta: left→ship, top→bar top, bottom→scanner, right→inner_right.
	var meta: Control = root.get_node_or_null(_SHOP_META_COL) as Control
	var meta_h: float = maxf(8.0, scan_y)
	var meta_x: float = side + gap
	var meta_w: float = maxf(8.0, inner_right - meta_x)
	if meta != null:
		meta.custom_minimum_size = Vector2.ZERO
		_snap_control_rect(meta, meta_x, 0.0, meta_w, meta_h)
		meta.size_flags_horizontal = 0
		meta.size_flags_vertical = 0
		meta.clip_contents = true
	var meta_mid_raw: Control = root.get_node_or_null(_SHOP_META_MID) as Control
	if meta_mid_raw != null and meta != null:
		if meta_mid_raw is BoxContainer:
			meta_mid_raw = _ensure_plain_layout_host(meta_mid_raw, "MetaMid", meta)
		## Absolute only — never FULL_RECT (that re-expands past snapped Meta).
		_clear_control_abs_layout(meta_mid_raw)
		meta_mid_raw.custom_minimum_size = Vector2.ZERO
		_snap_control_rect(meta_mid_raw, 0.0, 0.0, meta_w, meta_h)
		meta_mid_raw.size_flags_horizontal = 0
		meta_mid_raw.size_flags_vertical = 0
		meta_mid_raw.clip_contents = true
		meta_mid_raw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var le_host: Control = root.get_node_or_null(_SHOP_LEVEL_HOST) as Control
	var equip: Control = root.get_node_or_null(_SHOP_EQUIP_SLOTS) as Control
	## Probe-locked width only — never le_host.size.x (that ratcheted wider with live text/segs).
	var le_w: float = _level_exp_fixed_width(root)
	var mid_gap: float = float(UiLayout.margin_px(4, root))
	## Keep LevelExp from eating the whole Meta.
	le_w = minf(le_w, maxf(8.0, meta_w - mid_gap - float(UiLayout.px(24, root))))
	if le_host != null and meta_mid_raw != null:
		le_host.size_flags_horizontal = 0
		le_host.size_flags_vertical = 0
		_snap_control_rect(le_host, 0.0, 0.0, le_w, meta_h)
		le_host.custom_minimum_size = Vector2(le_w, maxf(le_host.custom_minimum_size.y, float(UiLayout.px(96, root))))
		le_host.clip_contents = true
	if equip != null and meta_mid_raw != null:
		var eq_x: float = le_w + mid_gap
		var eq_w: float = maxf(8.0, meta_w - eq_x)
		equip.size_flags_horizontal = 0
		equip.size_flags_vertical = 0
		equip.clip_contents = true
		equip.custom_minimum_size = Vector2.ZERO
		_snap_control_rect(equip, eq_x, 0.0, eq_w, meta_h)
		if equip is VBoxContainer:
			(equip as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
		_sync_equipment_shop_card_widths(equip)
	if meta_mid_raw != null:
		meta_mid_raw.clip_contents = true
	## Restyle scanner art to the snapped square — do NOT re-run ensure with a
	## different side (that used to set min-size > snapped rect and spill past cyan).
	if scanner != null:
		_restyle_scanner_host_to_side(scanner, scan_side, root)
		_refresh_scanner_cost_caption(root)


func _clear_control_abs_layout(c: Control) -> void:
	## Force BoxContainer-friendly layout: no leftover anchors/offsets that overlap siblings.
	if c == null:
		return
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.position = Vector2.ZERO
	c.rotation = 0.0
	c.scale = Vector2.ONE


func _ensure_ship_offer_host(ship_col: Node, root: Control) -> void:
	## UI_AND_SHELL §3.2: host fills ShopBody height (clipped by LeftCol); cards sized to fit.
	## Never set min-height = 6×side — that overflows the viewport when + ShopBtns + margins.
	if ship_col == null or root == null:
		return
	var host: Control = ship_col.get_node_or_null("ShipOfferHost") as Control
	if host == null:
		host = Control.new()
		host.name = "ShipOfferHost"
		ship_col.add_child(host)
		ship_col.move_child(host, 0)
	_clear_control_abs_layout(host)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = true
	host.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sep: float = float(UiLayout.margin_px(2, root))
	var side: float = _hud_shop_card_side if _hud_shop_card_side >= 8.0 else float(UiLayout.px(48, root))
	## Width only — height comes from ShopBody EXPAND inside clipped LeftCol.
	host.custom_minimum_size = Vector2(side, 0.0)
	var slots_raw: Control = host.get_node_or_null("ShopSlots") as Control
	if slots_raw == null:
		slots_raw = ship_col.get_node_or_null("ShopSlots") as Control
		if slots_raw != null:
			_reparent_keep_signals(slots_raw, host)
	if slots_raw == null:
		slots_raw = VBoxContainer.new()
		slots_raw.name = "ShopSlots"
		host.add_child(slots_raw)
	var slots: BoxContainer = _rebox_as_axis(slots_raw, true)
	_clear_control_abs_layout(slots)
	slots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slots.custom_minimum_size = Vector2(side, 0.0)
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots.add_theme_constant_override("separation", int(sep))
	slots.mouse_filter = Control.MOUSE_FILTER_PASS
	slots.z_index = 0
	var sell: PanelContainer = host.get_node_or_null("SellZone") as PanelContainer
	if sell == null:
		sell = ship_col.get_node_or_null("SellZone") as PanelContainer
		if sell != null:
			_reparent_keep_signals(sell, host)
	if sell == null:
		sell = root.get_node_or_null("Shop/ShopCol/ShopContent/ShopInner/SellZone") as PanelContainer
		if sell != null:
			_reparent_keep_signals(sell, host)
	if sell == null:
		sell = PanelContainer.new()
		sell.name = "SellZone"
		host.add_child(sell)
		var lab: Label = Label.new()
		lab.name = "SellLabel"
		lab.text = "售价"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sell.add_child(lab)
	_clear_control_abs_layout(sell)
	sell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sell.custom_minimum_size = Vector2.ZERO
	sell.z_index = 2
	if not _dragging_sell_ui:
		sell.visible = false
		sell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		sell.visible = true
		sell.mouse_filter = Control.MOUSE_FILTER_STOP
	host.move_child(slots, 0)
	host.move_child(sell, host.get_child_count() - 1)
	if ship_col is Control:
		var sc: Control = ship_col as Control
		sc.custom_minimum_size = Vector2(side, 0.0)
		sc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.clip_contents = true


func _resolve_sell_zone() -> PanelContainer:
	if hud == null:
		return null
	var sell: PanelContainer = hud.get_node_or_null("Root/%s" % _SHOP_SELL) as PanelContainer
	if sell == null:
		sell = hud.get_node_or_null("Root/%s/SellZone" % _SHOP_INNER) as PanelContainer
	if sell == null:
		sell = hud.get_node_or_null("Root/%s/ShipOfferHost/SellZone" % _SHOP_INNER) as PanelContainer
	return sell


func _ensure_meta_mid(meta_col: Control, _root: Control) -> Control:
	## Absolute host for LevelExp (left) + EquipmentSlots (fill to Meta right).
	## Size comes only from _apply_left_shop_snap_layout — never FULL_RECT.
	if meta_col == null:
		return null
	var mid_raw: Control = meta_col.get_node_or_null("MetaMid") as Control
	if mid_raw == null:
		mid_raw = Control.new()
		mid_raw.name = "MetaMid"
		meta_col.add_child(mid_raw)
	elif mid_raw is BoxContainer:
		mid_raw = _ensure_plain_layout_host(mid_raw, "MetaMid", meta_col)
	_clear_control_abs_layout(mid_raw)
	mid_raw.custom_minimum_size = Vector2.ZERO
	mid_raw.size_flags_horizontal = 0
	mid_raw.size_flags_vertical = 0
	mid_raw.clip_contents = true
	mid_raw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_col.move_child(mid_raw, 0)
	return mid_raw


func _ensure_equip_scan_col(meta_mid: Control, root: Control) -> VBoxContainer:
	## Right of LevelExp: equipment shop (top) → ship scanner (under cards). Both top-stick.
	if meta_mid == null:
		return null
	var col: VBoxContainer = meta_mid.get_node_or_null("EquipScanCol") as VBoxContainer
	if col == null:
		col = VBoxContainer.new()
		col.name = "EquipScanCol"
		meta_mid.add_child(col)
	_clear_control_abs_layout(col)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.0
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.clip_contents = true
	## Migrate legacy direct children of MetaMid / MetaCol.
	var meta_col: Node = meta_mid.get_parent()
	for nm: String in ["EquipmentSlots", "ScannerHost"]:
		var n: Node = meta_mid.get_node_or_null(nm)
		if n == null and meta_col != null:
			n = meta_col.get_node_or_null(nm)
		if n != null and n.get_parent() != col:
			_reparent_keep_signals(n, col)
	meta_mid.move_child(col, mini(1, meta_mid.get_child_count() - 1))
	return col


func _ensure_rotated_level_exp(meta_mid: Node, root: Control) -> void:
	## UI_AND_SHELL §3.2: vertical stack n级 → segs → n/n inside MetaMid (left of equip).
	## Host width = probe-locked fixed (_level_exp_fixed_width); height expands in MetaMid.
	if meta_mid == null or root == null:
		return
	var host: Control = meta_mid.get_node_or_null("LevelExpHost") as Control
	if host == null:
		## Migrate from old MetaCol direct child.
		var meta_col: Node = meta_mid.get_parent()
		if meta_col:
			host = meta_col.get_node_or_null("LevelExpHost") as Control
			if host != null:
				_reparent_keep_signals(host, meta_mid)
	if host == null:
		host = Control.new()
		host.name = "LevelExpHost"
		meta_mid.add_child(host)
	_clear_control_abs_layout(host)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = true
	host.visible = true
	host.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.size_flags_stretch_ratio = 0.0
	## Floor only — width later locked by _level_exp_fixed_width (pause/HUD).
	var le_floor_x: float = float(UiLayout.px(36, root))
	var le_floor_y: float = float(UiLayout.px(96, root))
	if host.custom_minimum_size.x < le_floor_x:
		host.custom_minimum_size.x = le_floor_x
	if host.custom_minimum_size.y < le_floor_y:
		host.custom_minimum_size.y = le_floor_y
	meta_mid.move_child(host, 0)
	var le: Control = host.get_node_or_null("LevelExp") as Control
	if le == null:
		le = meta_mid.get_node_or_null("LevelExp") as Control
		if le != null:
			_reparent_keep_signals(le, host)
	if le == null:
		var meta_parent: Node = meta_mid.get_parent()
		if meta_parent:
			le = meta_parent.get_node_or_null("LevelExp") as Control
			if le != null:
				_reparent_keep_signals(le, host)
	if le == null:
		le = root.get_node_or_null("%s/LevelExp" % _SHOP_LEFT) as Control
		if le != null:
			_reparent_keep_signals(le, host)
	if le == null:
		le = PanelContainer.new()
		le.name = "LevelExp"
		host.add_child(le)
	_clear_control_abs_layout(le)
	le.visible = true
	le.rotation = 0.0
	le.pivot_offset = Vector2.ZERO
	le.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.size_flags_vertical = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size = Vector2.ZERO
	le.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Tear down old HBox/LETextCol layout — rebuild as single VBox.
	var inner_raw: Control = le.get_node_or_null("LEInner") as Control
	var level_lbl: Label = null
	var exp_lbl: Label = null
	var seg: Control = null
	if inner_raw != null:
		level_lbl = inner_raw.find_child("Level", true, false) as Label
		exp_lbl = inner_raw.find_child("Exp", true, false) as Label
		seg = inner_raw.find_child("ExpSegRow", true, false) as Control
		if not (inner_raw is VBoxContainer) or inner_raw.get_node_or_null("LETextCol") != null:
			var keep_nodes: Array[Node] = []
			if level_lbl:
				keep_nodes.append(level_lbl)
			if exp_lbl:
				keep_nodes.append(exp_lbl)
			if seg:
				keep_nodes.append(seg)
			for kn: Node in keep_nodes:
				if kn.get_parent() != null:
					kn.get_parent().remove_child(kn)
			le.remove_child(inner_raw)
			inner_raw.queue_free()
			inner_raw = null
			var nv: VBoxContainer = VBoxContainer.new()
			nv.name = "LEInner"
			le.add_child(nv)
			for kn2: Node in keep_nodes:
				nv.add_child(kn2)
			inner_raw = nv
	if inner_raw == null:
		inner_raw = VBoxContainer.new()
		inner_raw.name = "LEInner"
		le.add_child(inner_raw)
	var inner: VBoxContainer = inner_raw as VBoxContainer
	_clear_control_abs_layout(inner)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.custom_minimum_size = Vector2.ZERO
	inner.alignment = BoxContainer.ALIGNMENT_BEGIN
	inner.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Drop obsolete text-col / labels box if still present.
	var text_col: Node = inner.get_node_or_null("LETextCol")
	if text_col != null:
		if level_lbl == null:
			level_lbl = text_col.get_node_or_null("Level") as Label
		if exp_lbl == null:
			exp_lbl = text_col.get_node_or_null("Exp") as Label
		if level_lbl and level_lbl.get_parent() == text_col:
			_reparent_keep_signals(level_lbl, inner)
		if exp_lbl and exp_lbl.get_parent() == text_col:
			_reparent_keep_signals(exp_lbl, inner)
		inner.remove_child(text_col)
		text_col.queue_free()
	var labs: Control = inner.get_node_or_null("LELabels") as Control
	if labs != null:
		if level_lbl == null:
			level_lbl = labs.get_node_or_null("Level") as Label
		if exp_lbl == null:
			exp_lbl = labs.get_node_or_null("Exp") as Label
		if level_lbl and level_lbl.get_parent() == labs:
			_reparent_keep_signals(level_lbl, inner)
		if exp_lbl and exp_lbl.get_parent() == labs:
			_reparent_keep_signals(exp_lbl, inner)
		inner.remove_child(labs)
		labs.queue_free()
	if level_lbl == null:
		level_lbl = inner.get_node_or_null("Level") as Label
	if exp_lbl == null:
		exp_lbl = inner.get_node_or_null("Exp") as Label
	if level_lbl == null:
		level_lbl = Label.new()
		level_lbl.name = "Level"
		inner.add_child(level_lbl)
	elif level_lbl.get_parent() != inner:
		_reparent_keep_signals(level_lbl, inner)
	if exp_lbl == null:
		exp_lbl = Label.new()
		exp_lbl.name = "Exp"
		inner.add_child(exp_lbl)
	elif exp_lbl.get_parent() != inner:
		_reparent_keep_signals(exp_lbl, inner)
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	level_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Head/tail keep glyph height — segs absorb squeeze (UI_AND_SHELL §3.2).
	level_lbl.custom_minimum_size = Vector2(0.0, _label_line_height(level_lbl, "15级"))
	level_lbl.clip_text = true
	level_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	exp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	exp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	exp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exp_lbl.custom_minimum_size = Vector2(0.0, _label_line_height(exp_lbl, "999 / 999"))
	exp_lbl.clip_text = true
	exp_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if seg == null:
		seg = inner.get_node_or_null("ExpSegRow") as Control
	if seg is HBoxContainer:
		seg = _rebox_as_axis(seg, true)
	elif seg == null:
		seg = VBoxContainer.new()
		seg.name = "ExpSegRow"
		inner.add_child(seg)
	if seg.get_parent() != inner:
		_reparent_keep_signals(seg, inner)
	_clear_control_abs_layout(seg)
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	## Seg min height 0 so VBox never pushes head/tail out of LevelExp frame.
	## Min width 0 — cells are capped inside fixed LevelExp; do not widen host.
	seg.custom_minimum_size = Vector2(0.0, 0.0)
	seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seg.clip_contents = true
	if seg is BoxContainer:
		(seg as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	le.clip_contents = true
	inner.clip_contents = true
	## Order: Level → segs → Exp (same column).
	inner.move_child(level_lbl, 0)
	inner.move_child(seg, 1)
	inner.move_child(exp_lbl, inner.get_child_count() - 1)
	var bar: ProgressBar = inner.get_node_or_null("ExpBar") as ProgressBar
	if bar:
		bar.visible = false


func _label_line_height(lbl: Label, probe: String = "字") -> float:
	if lbl == null:
		return float(UiLayout.px(12))
	var font: Font = lbl.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var fs: int = lbl.get_theme_font_size("font_size")
	if fs <= 0:
		fs = UiLayout.font_size(12, lbl)
	return maxf(float(UiLayout.px(10, lbl)), font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).y)


func _label_content_width(lbl: Label) -> float:
	if lbl == null or lbl.text.is_empty():
		return 0.0
	var font: Font = lbl.get_theme_font("font")
	var fs: int = lbl.get_theme_font_size("font_size")
	if font == null:
		return lbl.get_minimum_size().x
	return font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _level_exp_fixed_width(root: Control) -> float:
	## Authority: max("15级", "999 / 999") + LevelExp panel L/R margins.
	## Never live level/exp strings, never segment cell width (UI_AND_SHELL §3.2).
	if root == null:
		return float(UiLayout.px(36))
	var level_lbl: Label = root.get_node_or_null("%s/LEInner/Level" % _SHOP_LEVEL) as Label
	var exp_lbl: Label = root.get_node_or_null("%s/LEInner/Exp" % _SHOP_LEVEL) as Label
	var le: Control = root.get_node_or_null(_SHOP_LEVEL) as Control
	var need: float = float(UiLayout.px(28, root))
	var fs_lv: int = UiLayout.font_size(12, root)
	var font_lv: Font = ThemeDB.fallback_font
	if level_lbl != null:
		fs_lv = level_lbl.get_theme_font_size("font_size")
		var lf: Font = level_lbl.get_theme_font("font")
		if lf != null:
			font_lv = lf
	need = maxf(need, font_lv.get_string_size("15级", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_lv).x)
	var fs_ex: int = UiLayout.font_size(12, root)
	var font_ex: Font = ThemeDB.fallback_font
	if exp_lbl != null:
		fs_ex = exp_lbl.get_theme_font_size("font_size")
		var ef: Font = exp_lbl.get_theme_font("font")
		if ef != null:
			font_ex = ef
	need = maxf(need, font_ex.get_string_size("999 / 999", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_ex).x)
	var pad: float = float(UiLayout.margin_px(3, root)) * 2.0
	if le is PanelContainer:
		var sb: StyleBox = (le as PanelContainer).get_theme_stylebox("panel")
		if sb != null:
			pad = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	## +1px border each side drawn inside panel rect.
	need += pad
	need = maxf(need, float(UiLayout.px(36, root)))
	_hud_level_exp_fixed_w = need
	return need


func _fit_level_exp_width(root: Control) -> void:
	## Fixed LevelExp width — probe strings only; live text / segs never change column width.
	if root == null:
		return
	var host: Control = root.get_node_or_null(_SHOP_LEVEL_HOST) as Control
	var le: Control = root.get_node_or_null(_SHOP_LEVEL) as Control
	if host == null:
		return
	host.visible = true
	host.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.size_flags_stretch_ratio = 0.0
	if host.custom_minimum_size.y < float(UiLayout.px(72, root)):
		host.custom_minimum_size.y = float(UiLayout.px(96, root))
	var need: float = _level_exp_fixed_width(root)
	host.custom_minimum_size = Vector2(need, maxf(host.custom_minimum_size.y, float(UiLayout.px(96, root))))
	var equip: Control = root.get_node_or_null(_SHOP_EQUIP_SLOTS) as Control
	var meta_mid: Control = root.get_node_or_null(_SHOP_META_MID) as Control
	if le:
		le.visible = true
		le.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.size_flags_vertical = Control.SIZE_EXPAND_FILL
		## Host owns width. Panel min-x must stay 0 or Panel chrome double-counts past host.
		le.custom_minimum_size = Vector2(0.0, 0.0)
		le.clip_contents = true
	var level_lbl: Label = root.get_node_or_null("%s/LEInner/Level" % _SHOP_LEVEL) as Label
	var exp_lbl: Label = root.get_node_or_null("%s/LEInner/Exp" % _SHOP_LEVEL) as Label
	if level_lbl:
		level_lbl.clip_text = true
		level_lbl.custom_minimum_size.x = 0.0
	if exp_lbl:
		exp_lbl.clip_text = true
		exp_lbl.custom_minimum_size.x = 0.0
	var mw: float = 0.0
	var mh: float = 0.0
	if meta_mid != null:
		mw = meta_mid.size.x
		mh = meta_mid.size.y
		if mw < 8.0 or mh < 8.0:
			var meta_col: Control = root.get_node_or_null(_SHOP_META_COL) as Control
			if meta_col != null:
				mw = maxf(mw, meta_col.size.x)
				mh = maxf(mh, meta_col.size.y)
	if meta_mid != null and mw >= 8.0 and mh >= 8.0:
		var mid_gap: float = float(UiLayout.margin_px(4, root))
		_snap_control_rect(host, 0.0, 0.0, need, mh)
		host.custom_minimum_size = Vector2(need, maxf(host.custom_minimum_size.y, float(UiLayout.px(96, root))))
		host.clip_contents = true
		if equip != null:
			var eq_x: float = need + mid_gap
			_snap_control_rect(equip, eq_x, 0.0, maxf(8.0, mw - eq_x), mh)
			equip.clip_contents = true
			equip.custom_minimum_size = Vector2.ZERO
			if equip is VBoxContainer:
				(equip as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
			_sync_equipment_shop_card_widths(equip)
		_adapt_level_exp_vertical(root)


func _adapt_level_exp_vertical(root: Control) -> void:
	## Reserve Level (head) + Exp (tail) inside LevelExp frame; segs take leftover only.
	if root == null:
		return
	var host: Control = root.get_node_or_null(_SHOP_LEVEL_HOST) as Control
	var le: Control = root.get_node_or_null(_SHOP_LEVEL) as Control
	var level_lbl: Label = root.get_node_or_null("%s/LEInner/Level" % _SHOP_LEVEL) as Label
	var exp_lbl: Label = root.get_node_or_null("%s/LEInner/Exp" % _SHOP_LEVEL) as Label
	var row: Control = root.get_node_or_null("%s/LEInner/ExpSegRow" % _SHOP_LEVEL) as Control
	var inner: Control = root.get_node_or_null("%s/LEInner" % _SHOP_LEVEL) as Control
	if host == null or le == null or level_lbl == null or exp_lbl == null or row == null:
		return
	le.clip_contents = true
	if inner:
		inner.clip_contents = true
	row.clip_contents = true
	var head_h: float = _label_line_height(level_lbl, "15级")
	var tail_h: float = _label_line_height(exp_lbl, "999 / 999")
	level_lbl.custom_minimum_size = Vector2(0.0, head_h)
	exp_lbl.custom_minimum_size = Vector2(0.0, tail_h)
	level_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	exp_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 0.0
	var pad_y: float = float(UiLayout.margin_px(6, root))
	if le is PanelContainer:
		var sb: StyleBox = (le as PanelContainer).get_theme_stylebox("panel")
		if sb:
			pad_y = sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)
	var sep: float = float(UiLayout.margin_px(2, root))
	if inner is BoxContainer:
		sep = float((inner as BoxContainer).get_theme_constant("separation"))
	var host_h: float = host.size.y if host.size.y >= 8.0 else host.custom_minimum_size.y
	var reserved: float = head_h + tail_h + pad_y + sep * 2.0
	var seg_budget: float = maxf(0.0, host_h - reserved)
	## Rebuild / resize segment cells into leftover only (never steal head/tail).
	_layout_exp_segment_cells(root, row, seg_budget)


func _ensure_bottom_gold_pop(root: Control) -> void:
	## New bottom bar: Gold + field-limit row above 1×16 reserve (UI_AND_SHELL §2.1).
	if root == null:
		return
	var content: Control = root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	if content == null:
		return
	var cluster: Control = content.get_node_or_null("BottomCluster") as Control
	var gold_pop: HBoxContainer = null
	if cluster:
		gold_pop = cluster.get_node_or_null("GoldPop") as HBoxContainer
	if gold_pop == null:
		gold_pop = content.get_node_or_null("GoldPop") as HBoxContainer
	if gold_pop == null:
		gold_pop = root.get_node_or_null("%s/GoldPop" % _SHOP_META) as HBoxContainer
		if gold_pop != null:
			_reparent_keep_signals(gold_pop, content)
		else:
			gold_pop = HBoxContainer.new()
			gold_pop.name = "GoldPop"
			content.add_child(gold_pop)
	gold_pop.visible = true
	gold_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	gold_pop.add_theme_constant_override("separation", UiLayout.margin_px(16, root))
	gold_pop.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_pop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_pop.custom_minimum_size = Vector2(0, UiLayout.px(22, root))
	var gold_box: Control = gold_pop.get_node_or_null("GoldBox") as Control
	if gold_box == null:
		gold_box = root.get_node_or_null("%s/StatsRow/GoldBox" % _SHOP_MID) as Control
		if gold_box != null:
			_reparent_keep_signals(gold_box, gold_pop)
	var pop_box: Control = gold_pop.get_node_or_null("PopBox") as Control
	if pop_box == null:
		pop_box = root.get_node_or_null("%s/StatsRow/PopBox" % _SHOP_MID) as Control
		if pop_box != null:
			_reparent_keep_signals(pop_box, gold_pop)
	if gold_box:
		gold_pop.move_child(gold_box, 0)
		gold_box.visible = true
		gold_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		gold_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if gold_box is HBoxContainer:
			(gold_box as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	if pop_box:
		gold_pop.move_child(pop_box, mini(1, gold_pop.get_child_count() - 1))
		pop_box.visible = true
		pop_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pop_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if pop_box is HBoxContainer:
			(pop_box as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	var meta_mid: Control = root.get_node_or_null(_SHOP_MID) as Control
	if meta_mid:
		meta_mid.visible = false
	var left_ctrl: Control = root.get_node_or_null(_SHOP_LEFT) as Control
	if left_ctrl:
		left_ctrl.visible = false


func _ensure_bottom_cluster(root: Control) -> void:
	## Gold+pop and 16-equip share one centered cluster (UI_AND_SHELL §2.1).
	if root == null:
		return
	var content: Control = root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	if content == null:
		return
	if content is VBoxContainer:
		(content as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
		content.add_theme_constant_override("separation", 0)
	var cluster: VBoxContainer = content.get_node_or_null("BottomCluster") as VBoxContainer
	if cluster == null:
		cluster = VBoxContainer.new()
		cluster.name = "BottomCluster"
		content.add_child(cluster)
	cluster.alignment = BoxContainer.ALIGNMENT_CENTER
	cluster.add_theme_constant_override("separation", UiLayout.margin_px(4, root))
	cluster.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cluster.size_flags_vertical = Control.SIZE_SHRINK_END
	cluster.mouse_filter = Control.MOUSE_FILTER_STOP
	var gold_pop: Control = content.get_node_or_null("GoldPop") as Control
	if gold_pop == null:
		gold_pop = cluster.get_node_or_null("GoldPop") as Control
	if gold_pop != null and gold_pop.get_parent() != cluster:
		_reparent_keep_signals(gold_pop, cluster)
	if gold_pop:
		cluster.move_child(gold_pop, 0)
		gold_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_pop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var grid: Control = content.get_node_or_null("ReserveGrid") as Control
	if grid == null:
		grid = cluster.get_node_or_null("ReserveGrid") as Control
	if grid != null and grid.get_parent() != cluster:
		_reparent_keep_signals(grid, cluster)
	if grid:
		cluster.move_child(grid, cluster.get_child_count() - 1)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.size_flags_vertical = Control.SIZE_SHRINK_END
	content.move_child(cluster, content.get_child_count() - 1)


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
	_ensure_left_shop_layout()
	var grid: GridContainer = hud.get_node_or_null("Root/%s" % _RESERVE_GRID_PATH) as GridContainer
	if grid == null:
		grid = hud.get_node_or_null("Root/Shop/ShopCol/ShopContent/MetaRow/ReserveGrid") as GridContainer
	if grid == null:
		return
	grid.columns = 16
	while grid.get_child_count() < _EQUIP_INVENTORY_SIZE:
		var cell: PanelContainer = PanelContainer.new()
		cell.name = "Cell%d" % grid.get_child_count()
		grid.add_child(cell)
	while grid.get_child_count() > _EQUIP_INVENTORY_SIZE:
		var tail: Node = grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(tail)
		tail.queue_free()
	for c: Node in grid.get_children():
		if not (c is PanelContainer):
			continue
		var cell_pc: PanelContainer = c as PanelContainer
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.15, 0.45, 0.22, 0.55)
		sb.set_corner_radius_all(_EQUIP_INV_CORNER_PX)
		cell_pc.add_theme_stylebox_override("panel", sb)
	_layout_reserve_grid_cells(grid)

func _apply_hud_layout_inner_sizes(root: Control, vp_now: Vector2, shop_w_frac: float, _meta_w_px: float) -> void:
	## Drive shop/fetter/meta/bottom widgets from data/ui/hud_layout.json (UI_AND_SHELL §3.1.1).
	if root == null or vp_now.x < 8.0:
		return
	var bar_panel: Control = root.get_node_or_null(_SHOP_BAR_PANEL) as Control
	if bar_panel:
		bar_panel.custom_minimum_size = Vector2(shop_w_frac * vp_now.x, 0.0)
		bar_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ship_col: Control = root.get_node_or_null(_SHOP_INNER) as Control
	if ship_col:
		ship_col.custom_minimum_size = Vector2(_hud_shop_card_size.x, 0.0)
		ship_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var meta_col: Control = root.get_node_or_null(_SHOP_META_COL) as Control
	if meta_col:
		## Width owned by absolute snap (inner_right), not hud MetaCol frac min.
		meta_col.custom_minimum_size = Vector2.ZERO
		meta_col.size_flags_horizontal = 0
	var shop_btns: Control = root.get_node_or_null(_SHOP_BTNS) as Control
	if shop_btns:
		var btn_h: float = UiLayout.hud_height("ExpBtn", 0.078) * vp_now.y
		btn_h = clampf(btn_h, float(UiLayout.px(40, root)), float(UiLayout.px(72, root)))
		shop_btns.custom_minimum_size = Vector2(0.0, btn_h)
		shop_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_btns.size_flags_vertical = Control.SIZE_SHRINK_END
		shop_btns.clip_contents = true
	var le_host: Control = root.get_node_or_null(_SHOP_LEVEL_HOST) as Control
	if le_host:
		le_host.custom_minimum_size.y = float(UiLayout.px(96, root))
		if le_host.custom_minimum_size.x < float(UiLayout.px(32, root)):
			le_host.custom_minimum_size.x = float(UiLayout.px(32, root))
		le_host.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		le_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		le_host.size_flags_stretch_ratio = 0.0
		le_host.visible = true
	var scanner_host: Control = root.get_node_or_null(_SHOP_SCANNER_HOST) as Control
	if scanner_host == null:
		scanner_host = root.get_node_or_null(_SHOP_SCANNER) as Control
	if scanner_host:
		scanner_host.size_flags_horizontal = 0
		scanner_host.size_flags_vertical = 0
		scanner_host.custom_minimum_size.y = 0.0
	var equip_slots: Control = root.get_node_or_null(_SHOP_EQUIP_SLOTS) as Control
	if equip_slots:
		## Geometry from MetaMid absolute snap — not HBox stretch.
		equip_slots.size_flags_horizontal = 0
		equip_slots.size_flags_vertical = 0
		equip_slots.custom_minimum_size.y = 0.0
		if equip_slots is VBoxContainer:
			(equip_slots as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
	var meta_mid: Control = root.get_node_or_null(_SHOP_META_MID) as Control
	if meta_mid:
		meta_mid.size_flags_horizontal = 0
		meta_mid.size_flags_vertical = 0
	var meta_col2: Control = root.get_node_or_null(_SHOP_META_COL) as Control
	if meta_col2:
		meta_col2.size_flags_horizontal = 0
		meta_col2.size_flags_vertical = 0
		meta_col2.custom_minimum_size.y = 0.0
		meta_col2.clip_contents = true
	## Absolute snap overrides Box stretch leftovers.
	_apply_left_shop_snap_layout(root)
	_fit_level_exp_width(root)
	var ship_col_v: Control = root.get_node_or_null(_SHOP_INNER) as Control
	if ship_col_v:
		ship_col_v.clip_contents = true
	var offer_v: Control = root.get_node_or_null(_SHOP_OFFER_HOST) as Control
	if offer_v:
		offer_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		offer_v.clip_contents = true
	var fade_host: Control = root.get_node_or_null("LeftCol/LeftInner/LeftContent/BonusFadeHost") as Control
	## Always reserve fetter strip width so ShopBarPanel never reflows on collapse.
	## Keep host visible (HBox drops invisible children); only hide scroll content.
	if fade_host:
		var fetter_host_w: float = maxf(8.0, (UiLayout.left_col_width_frac() - shop_w_frac) * vp_now.x)
		fade_host.custom_minimum_size = Vector2(fetter_host_w, 0.0)
		fade_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fade_host.size_flags_stretch_ratio = 0.55
		fade_host.visible = true
		fade_host.modulate = Color(1, 1, 1, 0.0) if _collapse_left else Color(1, 1, 1, 1.0)
		fade_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold_pop: Control = root.get_node_or_null(_BOTTOM_GOLD_POP) as Control
	if gold_pop:
		gold_pop.custom_minimum_size.y = UiLayout.hud_height("GoldPop", 0.04) * vp_now.y
	var reserve: Control = root.get_node_or_null(_RESERVE_GRID_PATH) as Control
	if reserve:
		reserve.custom_minimum_size.y = UiLayout.hud_height("ReserveGrid", 0.06) * vp_now.y


func _shop_layout_metrics(root: Control, vp: Vector2, body_h: float, nslots: int) -> Dictionary:
	## Prefer height fill so bottom ship kisses ShopBtns; hard-clamp so 6×side + btns ≤ viewport.
	var shop_w_frac: float = UiLayout.left_shop_width_frac()
	var shop_w_px: float = shop_w_frac * vp.x
	var meta_w_px: float = UiLayout.hud_width("MetaCol", 0.062) * vp.x
	if meta_w_px < 8.0:
		meta_w_px = maxf(float(UiLayout.px(40, root)), float(UiLayout.px(56, root)))
	var gap_px: float = float(UiLayout.margin_px(4, root))
	var sep_px: float = float(UiLayout.margin_px(2, root))
	var btn_h: float = UiLayout.hud_height("ExpBtn", 0.078) * vp.y
	btn_h = clampf(btn_h, float(UiLayout.px(40, root)), float(UiLayout.px(72, root)))
	var panel_pad: float = float(UiLayout.margin_px(2, root)) * 2.0 + 4.0
	## Total budget = LeftCol height (viewport strip). Body = total − btns − pad − bar sep.
	var total_h: float = vp.y
	var left_col: Control = root.get_node_or_null("LeftCol") as Control
	if left_col != null and left_col.size.y >= 32.0:
		total_h = left_col.size.y
	var bar_panel: Control = root.get_node_or_null(_SHOP_BAR_PANEL) as Control
	if bar_panel != null and bar_panel.size.y >= 32.0:
		total_h = minf(total_h, bar_panel.size.y)
	var max_body: float = maxf(8.0, total_h - btn_h - sep_px - panel_pad)
	if body_h < 8.0 or body_h > max_body:
		body_h = max_body
	else:
		body_h = minf(body_h, max_body)
	var side: float = (body_h - sep_px * float(maxi(0, nslots - 1))) / float(maxi(1, nslots))
	side = clampf(side, UiLayout.px(28.0, root), UiLayout.px(160.0, root))
	## Prefer height-kiss: keep side from body_h; shrink MetaCol only down to LevelExp+equip floor.
	var meta_floor: float = float(UiLayout.px(72, root))
	var le_host_m: Control = root.get_node_or_null(_SHOP_LEVEL_HOST) as Control
	var equip_m: Control = root.get_node_or_null(_SHOP_EQUIP_SLOTS) as Control
	if le_host_m != null:
		meta_floor = maxf(meta_floor, le_host_m.custom_minimum_size.x)
	if equip_m != null:
		meta_floor += gap_px + maxf(float(UiLayout.px(36, root)), equip_m.custom_minimum_size.x)
	else:
		meta_floor += gap_px + float(UiLayout.px(40, root))
	if side + meta_w_px + gap_px > shop_w_px + 0.5:
		meta_w_px = maxf(meta_floor, shop_w_px - side - gap_px)
	if side + meta_w_px + gap_px > shop_w_px + 0.5:
		## Only then shrink side — cards still EXPAND_FILL vertically to kiss ShopBtns.
		side = maxf(float(UiLayout.px(28, root)), shop_w_px - meta_w_px - gap_px)
		## If still impossible, keep meta_floor and accept narrower ship cards.
		if side + meta_w_px + gap_px > shop_w_px + 0.5:
			meta_w_px = maxf(meta_floor, float(UiLayout.px(72, root)))
			side = maxf(float(UiLayout.px(28, root)), shop_w_px - meta_w_px - gap_px)
	## Re-clamp so 6 squares still fit max_body after width shrink.
	var host_h: float = side * float(maxi(1, nslots)) + sep_px * float(maxi(0, nslots - 1))
	if host_h > max_body + 0.5:
		side = (max_body - sep_px * float(maxi(0, nslots - 1))) / float(maxi(1, nslots))
		side = clampf(side, UiLayout.px(28.0, root), UiLayout.px(160.0, root))
		host_h = side * float(maxi(1, nslots)) + sep_px * float(maxi(0, nslots - 1))
	return {
		"side": side,
		"meta_w": meta_w_px,
		"shop_w_frac": shop_w_frac,
		"shop_w_px": shop_w_px,
		"host_h": host_h,
		"btn_h": btn_h,
		"body_h": body_h,
	}


func _deferred_refine_shop_fill() -> void:
	## After first layout pass: square side from real ShopBody height. Width mins only — never min-y = 6×side.
	if hud == null:
		return
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	var bar: Control = root.get_node_or_null(_SHOP_BAR) as Control
	var btns: Control = root.get_node_or_null(_SHOP_BTNS) as Control
	var body: Control = root.get_node_or_null(_SHOP_BODY) as Control
	if bar == null or bar.size.y < 32.0:
		return
	var sep: float = float(UiLayout.margin_px(2, root))
	var btn_h: float = btns.size.y if btns != null and btns.size.y >= 8.0 else UiLayout.hud_height("ExpBtn", 0.078) * UiLayout.viewport_size(root).y
	btn_h = clampf(btn_h, float(UiLayout.px(40, root)), float(UiLayout.px(72, root)))
	if btns != null:
		btns.custom_minimum_size.y = btn_h
	var n: int = 6
	if shop != null and shop.slots.size() > 0:
		n = maxi(1, shop.slots.size())
	var body_h: float = body.size.y if body != null and body.size.y >= 8.0 else maxf(8.0, bar.size.y - btn_h - sep)
	var metrics: Dictionary = _shop_layout_metrics(root, UiLayout.viewport_size(root), body_h, n)
	var side: float = TypedVariant.as_float(metrics.get("side", _hud_shop_card_side), _hud_shop_card_side)
	## Prefer laid-out host/body height so cards kiss ShopBtns without forcing parent taller.
	var host: Control = root.get_node_or_null(_SHOP_OFFER_HOST) as Control
	if host != null and host.size.y >= 8.0:
		var sep_h: float = float(UiLayout.margin_px(2, root))
		var side_from_host: float = (host.size.y - sep_h * float(maxi(0, n - 1))) / float(maxi(1, n))
		side = clampf(side_from_host, UiLayout.px(28.0, root), UiLayout.px(160.0, root))
	var meta_col: Control = root.get_node_or_null(_SHOP_META_COL) as Control
	var need_apply: bool = absf(side - _hud_shop_card_side) >= 1.0
	if not need_apply:
		return
	_hud_shop_card_size = Vector2(side, side)
	_hud_shop_card_side = side
	var ship_col: Control = root.get_node_or_null(_SHOP_INNER) as Control
	if ship_col:
		ship_col.custom_minimum_size = Vector2(side, 0.0)
		ship_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ship_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ship_col.clip_contents = true
	if host:
		host.custom_minimum_size = Vector2(side, 0.0)
		host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.clip_contents = true
	if meta_col:
		meta_col.custom_minimum_size = Vector2.ZERO
		meta_col.size_flags_horizontal = 0
		meta_col.size_flags_vertical = 0
	_ensure_ship_offer_host(ship_col, root)
	_refresh_shop_ui()
	_refresh_equipment_shop_ui()
	_style_shop_action_buttons(
		root,
		bar,
		btns,
		root.get_node_or_null("%s/ExpBtn" % _SHOP_BTNS) as Button,
		root.get_node_or_null("%s/RefreshBtn" % _SHOP_BTNS) as Button
	)
	## Snap owns scanner/Meta geometry; only restyle + LevelExp lock.
	_apply_left_shop_snap_layout(root)
	_fit_level_exp_width(root)
	_apply_left_shop_snap_layout(root)
	_refresh_exp_segments(root)
	_refresh_scanner_cost_caption(root)


func _apply_adaptive_hud_layout(skip_left_shop: bool = false) -> void:
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
	## Fetter collapse only; shop bar always visible (UI_AND_SHELL §2.1 / §3.4).
	_collapse_left_syn = _collapse_left
	_collapse_left_equip = _collapse_left
	## Do NOT rebuild left shop tree every HUD tick — that hitch is the refresh/exp stutter.
	## Geometry refresh only (snap) after chrome fractions are set.
	_ensure_hud_edge_chrome(root)
	var right_w: float = 0.0 if _collapse_right else UiLayout.right_col_width_frac()
	## Bottom bar = Meta + 1×16 equip; collapse btn lives in BottomEdgeChrome above it.
	var bottom_content_h: float = 0.0 if _collapse_bottom else UiLayout.bottom_shop_height_frac(root)
	## Chrome strip = unified edge icon side (flush to panel frame).
	var edge_icon_px: float = UiLayout.hud_edge_icon_px(root)
	var edge_btn_h: float = clampf(edge_icon_px / maxf(vp.y, 1.0), 0.04, 0.12)
	## Always reserve chrome strip above the shop (expanded or collapsed).
	var bottom_h: float = bottom_content_h + edge_btn_h
	var band_top: float = top_h + 0.01
	var band_bot: float = 1.0 - bottom_h - 0.02
	var edge_m: float = UiLayout.hud_edge_margin_frac()
	var vp_now: Vector2 = UiLayout.viewport_size(root)
	var shop_w_frac: float = UiLayout.left_shop_width_frac()
	## UI_AND_SHELL §3.4: LeftCol always full (shop+fetter) width — collapsing fetters only hides
	## BonusFadeHost; shop bar geometry and mid playfield must not jump.
	var left_w: float = UiLayout.left_col_width_frac()
	var min_mid_frac: float = 0.18
	var max_left_frac: float = clampf(1.0 - edge_m - right_w - min_mid_frac, 0.16, 0.40)
	if left_w > max_left_frac:
		left_w = max_left_frac
	var ship_w_px: float = UiLayout.hud_width("Ship0", 0.083) * vp_now.x
	var ship_h_px: float = UiLayout.hud_height("Ship0", 0.144) * vp_now.y
	## Fill: square side from ShopBody height / n, clamped to hud_layout ShipCol width + LeftShop budget.
	var nslots_fill: int = 6
	if shop != null and shop.slots.size() > 0:
		nslots_fill = maxi(1, shop.slots.size())
	var btn_h_fill: float = UiLayout.hud_height("ExpBtn", 0.078) * vp_now.y
	var sep_fill: float = float(UiLayout.margin_px(2, root))
	var panel_pad_fill: float = float(UiLayout.margin_px(8, root))
	var body_h_fill: float = maxf(8.0, vp_now.y - btn_h_fill - sep_fill - panel_pad_fill)
	var layout_m: Dictionary = _shop_layout_metrics(root, vp_now, body_h_fill, nslots_fill)
	var side_fill: float = TypedVariant.as_float(layout_m.get("side", ship_w_px), ship_w_px)
	var meta_w_px: float = TypedVariant.as_float(layout_m.get("meta_w", 0.0), 0.0)
	if meta_w_px < 8.0:
		meta_w_px = UiLayout.hud_width("MetaCol", 0.062) * vp_now.x
	## Bottom collapse must not rewrite ship side — that shifts Meta/LevelExp on X
	## (UI_AND_SHELL §3.1).
	if not skip_left_shop:
		ship_w_px = side_fill
		ship_h_px = side_fill
		_hud_shop_card_size = Vector2(ship_w_px, ship_h_px)
		_hud_shop_card_side = side_fill
	var left_top: float = 0.0
	var left_bot: float = 1.0
	@warning_ignore("unsafe_cast")
	var left_col: Control = root.get_node_or_null("LeftCol") as Control
	if left_col and not skip_left_shop:
		left_col.visible = true
		UiLayout.set_rect_frac(left_col, 0.0, left_top, left_w, left_bot)
	@warning_ignore("unsafe_cast")
	var equip_col: Control = root.get_node_or_null("EquipCol") as Control
	if equip_col:
		## Legacy dual-left bag panel — hidden under plan J (inventory is bottom 1×16).
		equip_col.visible = false
		equip_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("unsafe_cast")
	var right_col: Control = root.get_node_or_null("RightCol") as Control
	if right_col:
		## Keep RightCol in tree when collapsed (0-width at right edge) so chrome can
		## pin to its live left edge on every width/visibility change.
		right_col.visible = true
		right_col.clip_contents = false
		@warning_ignore("unsafe_cast")
		var right_inner: Control = right_col.get_node_or_null("RightInner") as Control
		if _collapse_right:
			if right_inner:
				right_inner.visible = false
			right_col.custom_minimum_size = Vector2.ZERO
			right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			right_col.modulate = Color(1, 1, 1, 0)
			UiLayout.set_rect_frac(right_col, 1.0 - edge_m, band_top, 1.0 - edge_m, band_bot)
		else:
			if right_inner:
				right_inner.visible = true
			right_col.mouse_filter = Control.MOUSE_FILTER_STOP
			right_col.modulate = Color(1, 1, 1, 1)
			UiLayout.set_rect_frac(
				right_col,
				UiLayout.hud_frac("RightCol", "l", 1.0 - edge_m - right_w),
				UiLayout.hud_frac("RightCol", "t", band_top),
				UiLayout.hud_frac("RightCol", "r", 1.0 - edge_m),
				UiLayout.hud_frac("RightCol", "b", band_bot)
			)
		if not right_col.resized.is_connected(_on_right_col_resized_for_chrome):
			right_col.resized.connect(_on_right_col_resized_for_chrome)
	@warning_ignore("unsafe_cast")
	var shop_panel: Control = root.get_node_or_null("Shop") as Control
	## Viewport-centered bottom bar (UI_AND_SHELL §3.1 · hud_layout.json).
	var shop_w: float = UiLayout.bottom_shop_width_frac()
	var shop_l: float = UiLayout.hud_frac("BottomBar", "l", (1.0 - shop_w) * 0.5)
	var shop_r: float = UiLayout.hud_frac("BottomBar", "r", shop_l + shop_w)
	if not skip_left_shop:
		_apply_hud_layout_inner_sizes(root, vp_now, shop_w_frac, meta_w_px)
		_apply_left_col_shell(root)
		call_deferred("_deferred_refine_shop_fill")
	if shop_panel:
		shop_panel.visible = not _collapse_bottom
		if not _collapse_bottom:
			var shop_top: float = UiLayout.hud_frac("BottomBar", "t", 1.0 - bottom_content_h)
			UiLayout.set_rect_frac(shop_panel, shop_l, shop_top, shop_r, 1.0)
			_apply_bottom_vfade(shop_panel)
	@warning_ignore("unsafe_cast")
	var shop_col: Control = root.get_node_or_null("Shop/ShopCol") as Control
	if shop_col:
		shop_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_col.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		## CollapseBottomBtn lives in BottomEdgeChrome; never hide chrome-owned arrow.
	@warning_ignore("unsafe_cast")
	var left_content: Control = root.get_node_or_null("LeftCol/LeftInner/LeftContent") as Control
	if left_content:
		left_content.visible = true
	@warning_ignore("unsafe_cast")
	var bonus_scroll: Control = _bonus_scroll_of(root)
	if bonus_scroll:
		## Collapse hides scroll only — BonusFadeHost stays laid out (§3.4).
		bonus_scroll.visible = not _collapse_left
		bonus_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		bonus_scroll.size_flags_stretch_ratio = 0.55
	var fade_host: Control = root.get_node_or_null("LeftCol/LeftInner/LeftContent/BonusFadeHost") as Control
	if fade_host:
		fade_host.visible = true
		fade_host.size_flags_stretch_ratio = 0.55
		fade_host.modulate = Color(1, 1, 1, 0.0) if _collapse_left else Color(1, 1, 1, 1.0)
		fade_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("unsafe_cast")
	var buy_col: Control = root.get_node_or_null(_SHOP_BUY_COL) as Control
	if buy_col:
		buy_col.visible = true
		## Shop frame width locked — never EXPAND into fetter strip on collapse.
		buy_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	@warning_ignore("unsafe_cast")
	var reserve_grid: Control = root.get_node_or_null(_RESERVE_GRID_PATH) as Control
	if reserve_grid == null:
		reserve_grid = root.get_node_or_null("EquipCol/EquipInner/ReserveGrid") as Control
	if reserve_grid:
		reserve_grid.visible = not _collapse_bottom
		reserve_grid.size_flags_stretch_ratio = 1.0
	@warning_ignore("unsafe_cast")
	var right_content: Control = root.get_node_or_null("RightCol/RightInner/RightContent") as Control
	if right_content:
		right_content.visible = not _collapse_right
	@warning_ignore("unsafe_cast")
	var shop_content: Control = root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	if shop_content:
		shop_content.visible = not _collapse_bottom
		shop_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_content.add_theme_constant_override("separation", 0)
		if shop_content is VBoxContainer:
			(shop_content as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
		_ensure_bottom_cluster(root)
	## Single left chrome — pin to screen top, outside left-column right edge.
	var chrome_w: float = clampf(edge_icon_px / maxf(vp.x, 1.0), 0.03, 0.08)
	var chrome_h: float = clampf(edge_icon_px / maxf(vp.y, 1.0), 0.04, 0.12)
	## Collapse arrow: shop right when fetters hidden; full LeftCol right when shown (§3.4).
	## Vertical: pin to screen top (no longer vertically centered).
	var left_panel_r: float = shop_w_frac if _collapse_left else left_w
	@warning_ignore("unsafe_cast")
	var left_chrome: Control = root.get_node_or_null("LeftEdgeChrome") as Control
	if left_chrome:
		UiLayout.set_rect_frac(
			left_chrome,
			left_panel_r,
			0.0,
			left_panel_r + chrome_w,
			chrome_h
		)
	@warning_ignore("unsafe_cast")
	var equip_chrome: Control = root.get_node_or_null("EquipEdgeChrome") as Control
	if equip_chrome:
		equip_chrome.visible = false
		equip_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Right chrome: flush to RightCol left edge; deferred snap after layout flush.
	_place_right_edge_chrome(root, chrome_w, chrome_h, band_top, band_bot, edge_m)
	call_deferred("_deferred_snap_right_edge_chrome")
	@warning_ignore("unsafe_cast")
	var bottom_chrome: Control = root.get_node_or_null("BottomEdgeChrome") as Control
	if bottom_chrome:
		bottom_chrome.visible = true
		bottom_chrome.z_index = 40
		var shop_top2: float = 1.0 - bottom_content_h
		var bc_l: float = shop_l
		var bc_r: float = shop_r
		if _collapse_bottom:
			bc_l = 0.5 - shop_w * 0.25
			bc_r = 0.5 + shop_w * 0.25
			shop_top2 = 1.0
		UiLayout.set_rect_frac(bottom_chrome, bc_l, shop_top2 - edge_btn_h, bc_r, shop_top2)
	@warning_ignore("unsafe_cast")
	var notice: Control = root.get_node_or_null("Notice") as Control
	if notice:
		UiLayout.set_rect_frac(notice, 0.28, 0.4, 0.72, 0.5)
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_info_panel_adaptive_layout(root)
	## After strip sizes land, re-scale Meta (¼) vs ship row (¾).
	## Bottom-only collapse must not re-snap left shop (LevelExp X).
	if not skip_left_shop:
		_wire_shop_chrome()
	_ensure_rank_panel(root)
	_style_collapse_arrow_buttons(root)
	_apply_right_pane_mode(root)


func _place_right_edge_chrome(
	root: Control,
	chrome_w: float,
	chrome_h: float,
	band_top: float,
	band_bot: float,
	edge_m: float
) -> void:
	@warning_ignore("unsafe_cast")
	var right_chrome: Control = root.get_node_or_null("RightEdgeChrome") as Control
	if right_chrome == null:
		return
	@warning_ignore("unsafe_cast")
	var right_col: Control = root.get_node_or_null("RightCol") as Control
	if right_col == null:
		## Fallback if RightCol missing.
		UiLayout.set_rect_frac(
			right_chrome,
			1.0 - edge_m - chrome_w,
			band_top,
			1.0 - edge_m,
			band_bot if not _collapse_right else (band_top + band_bot) * 0.5 + chrome_h * 0.5
		)
		return
	## Pixel-pin to live RightCol left edge (tracks width expand/collapse).
	_snap_right_edge_chrome_to_col(root)


func _on_right_col_resized_for_chrome() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root != null:
		_snap_right_edge_chrome_to_col(root)


func _deferred_snap_right_edge_chrome() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	@warning_ignore("unsafe_cast")
	var root: Control = hud.get_node_or_null("Root") as Control
	if root != null:
		_snap_right_edge_chrome_to_col(root)


func _snap_right_edge_chrome_to_col(root: Control) -> void:
	## Pin chrome's right edge to RightCol's left edge in Root-local pixels.
	@warning_ignore("unsafe_cast")
	var right_chrome: Control = root.get_node_or_null("RightEdgeChrome") as Control
	@warning_ignore("unsafe_cast")
	var right_col: Control = root.get_node_or_null("RightCol") as Control
	if right_chrome == null or right_col == null:
		return
	var chrome_px: float = UiLayout.hud_edge_icon_px(root)
	var col_r: Rect2 = right_col.get_rect()
	var panel_left_px: float = col_r.position.x
	var top_px: float = col_r.position.y
	var h_px: float = maxf(col_r.size.y, chrome_px)
	if _collapse_right:
		top_px = col_r.position.y + (h_px - chrome_px) * 0.5
		h_px = chrome_px
	right_chrome.set_anchors_preset(Control.PRESET_TOP_LEFT)
	right_chrome.anchor_left = 0.0
	right_chrome.anchor_top = 0.0
	right_chrome.anchor_right = 0.0
	right_chrome.anchor_bottom = 0.0
	right_chrome.position = Vector2(panel_left_px - chrome_px, top_px)
	right_chrome.size = Vector2(chrome_px, h_px)
	right_chrome.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_chrome.grow_vertical = Control.GROW_DIRECTION_BOTH


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
		info.size_flags_stretch_ratio = 1.0
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
		## Always stack weapon/drone under title (UI_AND_SHELL §2.5 vertical list).
		if info_top and body and weapon_col != null and weapon_col.get_parent() == info_top:
			info_top.remove_child(weapon_col)
			var insert_at: int = info_top.get_index() + 1
			body.add_child(weapon_col)
			body.move_child(weapon_col, insert_at)
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
		cr.custom_minimum_size = Vector2(0, UiLayout.px(28, root) * 0.90)


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
			"%s/LevelExp/LEInner/Level" % _SHOP_LEFT,
			"%s/LevelExp/LEInner/Exp" % _SHOP_LEFT,
			"%s/LEInner/LETextCol/Level" % _SHOP_LEVEL,
			"%s/LEInner/LETextCol/Exp" % _SHOP_LEVEL,
			"%s/LEInner/Level" % _SHOP_LEVEL,
			"%s/LEInner/Exp" % _SHOP_LEVEL,
			"%s/LevelExp/LEInner/LELabels/Level" % _SHOP_LEFT,
			"%s/LevelExp/LEInner/LELabels/Exp" % _SHOP_LEFT,
			"%s/LEInner/LELabels/Level" % _SHOP_LEVEL,
			"%s/LEInner/LELabels/Exp" % _SHOP_LEVEL,
			"%s/PopBox/Pop" % _BOTTOM_GOLD_POP, "%s/GoldBox/Gold" % _BOTTOM_GOLD_POP,
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
	for panel_path: String in ["RoundBar", "EquipCol", "RightCol"]:
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
	_apply_left_col_shell(root)
	@warning_ignore("unsafe_cast")
	var shop_fade: Control = root.get_node_or_null("Shop") as Control
	if shop_fade:
		_apply_bottom_vfade(shop_fade)
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
			"TopRight/CamModeBtn", "TopRight/ScoutIntelBtn", "TopRight/ConcedeRoundBtn"]:
		@warning_ignore("unsafe_cast")
		var b: BaseButton = root.get_node_or_null(btn_name) as BaseButton
		if b is Button:
			var bb: Button = b as Button
			UiAssets.apply_button_font(bb, UiLayout.font_size(13, root))
			var bw: float = 88.0 if ("CamMode" in btn_name or "ScoutIntel" in btn_name) else 56.0
			if "ConcedeRound" in btn_name:
				bw = 108.0
			bb.custom_minimum_size = Vector2(UiLayout.px(bw, root), UiLayout.px(28, root))
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
	## Layout tree is built once via `_ensure_left_shop_layout` on enter/resize.
	## Per-HUD ticks only re-snap + restyle — full ensure was the refresh/exp hitch.
	var bar: Control = root.get_node_or_null(_SHOP_BAR) as Control
	if bar == null or bar.get_node_or_null("ShipCol") == null:
		_ensure_left_shop_layout(root)
	else:
		_apply_left_shop_snap_layout(root)
	_ensure_equipment_shop_slots()
	## Plan J: bottom Shop = Meta + 1×16 equip; buy zones sized from LeftCol.
	var content_h: float = 0.0
	@warning_ignore("unsafe_cast")
	var shop_content_probe: Control = root.get_node_or_null("Shop/ShopCol/ShopContent") as Control
	if shop_content_probe and shop_content_probe.size.y >= 8.0:
		content_h = shop_content_probe.size.y
	else:
		content_h = UiLayout.bottom_shop_height_frac(root) * maxf(UiLayout.viewport_size(root).y, 1.0)
	var meta_band: float = content_h * 0.72
	var meta_h: int = clampi(int(meta_band * 0.82), UiLayout.px(28, root), UiLayout.px(52, root))
	var btn_w: int = clampi(int(float(meta_h) * 2.2), UiLayout.px(72, root), UiLayout.px(120, root))
	var btn_h: float = float(meta_h)
	var shop_bar_w: Control = root.get_node_or_null(_SHOP_BAR) as Control
	var shop_btns_w: Control = root.get_node_or_null(_SHOP_BTNS) as Control
	_style_shop_action_buttons(
		root,
		shop_bar_w,
		shop_btns_w,
		root.get_node_or_null("%s/ExpBtn" % _SHOP_BTNS) as Button,
		root.get_node_or_null("%s/RefreshBtn" % _SHOP_BTNS) as Button
	)
	## After ShopBtns gets real size, fill again so icons match the reserved strip.
	call_deferred("_deferred_style_shop_action_buttons")
	var scan_w: int = UiLayout.px(56, root)
	if _hud_shop_card_side >= 8.0:
		scan_w = clampi(int(_hud_shop_card_side * 0.85), UiLayout.px(48, root), UiLayout.px(120, root))
	_ensure_ship_scanner_btn(root, scan_w)
	@warning_ignore("unsafe_cast")
	var lock: Button = root.get_node_or_null("%s/StatsRow/LockBtn" % _SHOP_MID) as Button
	if lock:
		lock.visible = false
		lock.disabled = true
	_ensure_meta_icon(root.get_node_or_null("%s/GoldBox" % _BOTTOM_GOLD_POP) as HBoxContainer, "Gold", UiAssets.ICON_MONEY, mini(28, meta_h))
	_ensure_meta_icon(root.get_node_or_null("%s/PopBox" % _BOTTOM_GOLD_POP) as HBoxContainer, "Pop", UiAssets.ICON_POP, mini(28, meta_h))
	@warning_ignore("unsafe_cast")
	var le: PanelContainer = root.get_node_or_null(_SHOP_LEVEL) as PanelContainer
	if le == null:
		le = root.get_node_or_null("%s/LevelExp" % _SHOP_LEFT) as PanelContainer
	if le:
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.size_flags_vertical = Control.SIZE_EXPAND_FILL
		le.visible = true
		@warning_ignore("unsafe_cast")
		var le_inner: Control = le.get_node_or_null("LEInner") as Control
		if le_inner:
			le_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			le_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
			le_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var le_sb: StyleBoxFlat = StyleBoxFlat.new()
		le_sb.bg_color = Color(0.07, 0.09, 0.11, 0.88)
		le_sb.border_color = Color(0.35, 0.72, 0.85, 0.55)
		le_sb.set_border_width_all(1)
		le_sb.set_corner_radius_all(4)
		## Tight pad — frame hugs text/segs (UI_AND_SHELL §3.2).
		le_sb.content_margin_left = UiLayout.margin_px(3, root)
		le_sb.content_margin_right = UiLayout.margin_px(3, root)
		le_sb.content_margin_top = UiLayout.margin_px(3, root)
		le_sb.content_margin_bottom = UiLayout.margin_px(3, root)
		le.add_theme_stylebox_override("panel", le_sb)
		var meta_mid_le: Node = root.get_node_or_null(_SHOP_META_MID)
		if meta_mid_le == null:
			var meta_col_le: Control = root.get_node_or_null(_SHOP_META_COL) as Control
			if meta_col_le:
				meta_mid_le = _ensure_meta_mid(meta_col_le, root)
		if meta_mid_le:
			_ensure_rotated_level_exp(meta_mid_le, root)
		_refresh_exp_segments(root)
		_fit_level_exp_width(root)
	@warning_ignore("unsafe_cast")
	var left_ctrl: Control = root.get_node_or_null(_SHOP_LEFT) as Control
	if left_ctrl:
		## Meta controls only — equip buy moved to LeftCol; keep compact.
		left_ctrl.custom_minimum_size = Vector2(UiLayout.px(360, root), 0)
		left_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if left_ctrl is BoxContainer:
			(left_ctrl as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	@warning_ignore("unsafe_cast")
	var left_btns: Control = root.get_node_or_null("%s/LeftBtns" % _SHOP_LEFT) as Control
	if left_btns:
		left_btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for c: Node in left_btns.get_children():
			if c is Button:
				(c as Button).custom_minimum_size = Vector2(btn_w, btn_h)
	var seg_row: Control = root.get_node_or_null("%s/LEInner/ExpSegRow" % _SHOP_LEVEL) as Control
	if seg_row == null:
		seg_row = root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as Control
	if seg_row is HBoxContainer:
		seg_row = _rebox_as_axis(seg_row, true)
	if seg_row:
		seg_row.custom_minimum_size = Vector2(0, 0)
		seg_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		seg_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if seg_row is BoxContainer:
			(seg_row as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	var meta_row: HBoxContainer = root.get_node_or_null(_SHOP_META) as HBoxContainer
	if meta_row:
		meta_row.alignment = BoxContainer.ALIGNMENT_CENTER
		meta_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		meta_row.size_flags_stretch_ratio = 1.0
		meta_row.add_theme_constant_override("separation", UiLayout.margin_px(8, root))
		## Soft ceiling so Meta cannot steal ship-row space via child mins.
		meta_row.custom_minimum_size = Vector2(0, 0)
	## ShipCol (was legacy ShopInner path): keep json-driven min width — never zero it.
	@warning_ignore("unsafe_cast")
	var ship_col_lane: Control = root.get_node_or_null(_SHOP_INNER) as Control
	if ship_col_lane:
		ship_col_lane.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ship_col_lane.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ship_col_lane.custom_minimum_size.y = 0.0
		ship_col_lane.clip_contents = true
		if _hud_shop_card_side >= 8.0:
			ship_col_lane.custom_minimum_size.x = _hud_shop_card_side
		var offer_host: Control = root.get_node_or_null(_SHOP_OFFER_HOST) as Control
		if offer_host:
			offer_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
			offer_host.custom_minimum_size.y = 0.0
			offer_host.clip_contents = true
			if _hud_shop_card_side >= 8.0:
				offer_host.custom_minimum_size.x = _hud_shop_card_side
	@warning_ignore("unsafe_cast")
	var shop_slots: Control = root.get_node_or_null(_SHOP_SLOTS) as Control
	if shop_slots:
		shop_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_slots.custom_minimum_size.y = 0.0
	@warning_ignore("unsafe_cast")
	var shop_content: VBoxContainer = root.get_node_or_null("Shop/ShopCol/ShopContent") as VBoxContainer
	if shop_content:
		shop_content.add_theme_constant_override("separation", 0)
		shop_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_content.alignment = BoxContainer.ALIGNMENT_END
		_ensure_bottom_cluster(root)
	## Equip shop cards: vertical name + horizontal price (EQUIPMENT §1).
	@warning_ignore("unsafe_cast")
	var shop_col: Control = root.get_node_or_null("Shop/ShopCol") as Control
	if shop_col and shop_col is VBoxContainer:
		(shop_col as VBoxContainer).add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		shop_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shop_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	@warning_ignore("unsafe_cast")
	var gold_pop_row: HBoxContainer = root.get_node_or_null(_BOTTOM_GOLD_POP) as HBoxContainer
	if gold_pop_row:
		gold_pop_row.alignment = BoxContainer.ALIGNMENT_CENTER
		gold_pop_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gold_pop_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	@warning_ignore("unsafe_cast")
	var gold_lbl: Label = root.get_node_or_null("%s/GoldBox/Gold" % _BOTTOM_GOLD_POP) as Label
	if gold_lbl:
		UiAssets.apply_label_font(gold_lbl, true, UiLayout.font_size(22, root))
	@warning_ignore("unsafe_cast")
	var pop_lbl: Label = root.get_node_or_null("%s/PopBox/Pop" % _BOTTOM_GOLD_POP) as Label
	if pop_lbl:
		UiAssets.apply_label_font(pop_lbl, true, UiLayout.font_size(18, root))
	@warning_ignore("unsafe_cast")
	var leftover_inner: Control = root.get_node_or_null("Shop/ShopCol/ShopContent/ShopInner") as Control
	if leftover_inner:
		leftover_inner.visible = false
		leftover_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("unsafe_cast")
	var sell: PanelContainer = _resolve_sell_zone()
	if sell:
		## Overlay fills ShipOfferHost (= 6 ship slots); never take Box layout space.
		sell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sell.custom_minimum_size = Vector2.ZERO
		sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sell.z_index = 2
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.22, 0.25, 0.92)
		sb.border_color = Color(0.4, 0.75, 0.9, 0.7)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sell.add_theme_stylebox_override("panel", sb)
		@warning_ignore("unsafe_cast")
		var lab: Label = sell.get_node_or_null("SellLabel") as Label
		if lab:
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ensure_meta_icon(box: HBoxContainer, for_name: String, tex_path: String, design_px: int = 20) -> void:
	if box == null:
		return
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for lab_n: Node in box.get_children():
		if lab_n is Label:
			(lab_n as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	## One segment = one buy-exp press toward next level (ECONOMY_AND_SHOP / UI_AND_SHELL).
	## slots = ceil(demand / buy_exp_amount); filled = floor(exp / buy_exp_amount).
	var row_c: Control = root.get_node_or_null("%s/LEInner/ExpSegRow" % _SHOP_LEVEL) as Control
	if row_c == null:
		row_c = root.get_node_or_null("%s/LevelExp/LEInner/ExpSegRow" % _SHOP_LEFT) as Control
	if row_c == null:
		return
	if row_c is HBoxContainer:
		row_c = _rebox_as_axis(row_c, true)
	var row: BoxContainer = row_c as BoxContainer
	if row == null:
		return
	var demand: int = maxi(1, match_ctrl.up_level_demand)
	var exp_now: int = clampi(match_ctrl.player_exp, 0, demand)
	var buy_amt: int = TypedVariant.as_int(DataStore.economy.get("buy_exp_amount", 4), 4)
	buy_amt = maxi(1, buy_amt)
	var slots: int = maxi(1, (demand + buy_amt - 1) / buy_amt)
	var filled: int = clampi(exp_now / buy_amt, 0, slots)
	## Hold path: only recolor when count matches.
	if row.get_child_count() == slots:
		_recolor_exp_segment_cells(row, filled)
		var legacy0: ProgressBar = root.get_node_or_null("%s/LEInner/ExpBar" % _SHOP_LEVEL) as ProgressBar
		if legacy0 == null:
			legacy0 = root.get_node_or_null("%s/LevelExp/LEInner/ExpBar" % _SHOP_LEFT) as ProgressBar
		if legacy0:
			legacy0.visible = false
		return
	## Full rebuild — height budget from LevelExp leftover (head/tail reserved).
	var le_host: Control = root.get_node_or_null(_SHOP_LEVEL_HOST) as Control
	var level_lbl: Label = root.get_node_or_null("%s/LEInner/Level" % _SHOP_LEVEL) as Label
	var exp_lbl: Label = root.get_node_or_null("%s/LEInner/Exp" % _SHOP_LEVEL) as Label
	var head_h: float = _label_line_height(level_lbl, "15级") if level_lbl else float(UiLayout.px(14, row))
	var tail_h: float = _label_line_height(exp_lbl, "999 / 999") if exp_lbl else float(UiLayout.px(14, row))
	var pad_y: float = float(UiLayout.margin_px(6, row))
	var le_panel: Control = root.get_node_or_null(_SHOP_LEVEL) as Control
	if le_panel is PanelContainer:
		var sb: StyleBox = (le_panel as PanelContainer).get_theme_stylebox("panel")
		if sb:
			pad_y = sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)
	var host_h: float = float(UiLayout.px(96, row))
	if le_host != null and le_host.size.y >= 40.0:
		host_h = le_host.size.y
	elif le_host != null and le_host.custom_minimum_size.y >= 8.0:
		host_h = le_host.custom_minimum_size.y
	elif le_panel != null and le_panel.size.y >= 8.0:
		host_h = le_panel.size.y
	var sep_inner: float = float(UiLayout.margin_px(2, row))
	var seg_budget: float = maxf(0.0, host_h - head_h - tail_h - pad_y - sep_inner * 2.0)
	_layout_exp_segment_cells(root, row, seg_budget, slots, filled)
	var legacy: ProgressBar = root.get_node_or_null("%s/LEInner/ExpBar" % _SHOP_LEVEL) as ProgressBar
	if legacy == null:
		legacy = root.get_node_or_null("%s/LevelExp/LEInner/ExpBar" % _SHOP_LEFT) as ProgressBar
	if legacy:
		legacy.visible = false


func _recolor_exp_segment_cells(row: BoxContainer, filled: int) -> void:
	if row == null:
		return
	for i: int in range(row.get_child_count()):
		var cell0: PanelContainer = row.get_child(i) as PanelContainer
		if cell0 == null:
			continue
		var sb0: StyleBoxFlat = StyleBoxFlat.new()
		sb0.set_border_width_all(1)
		sb0.set_corner_radius_all(2)
		sb0.set_content_margin_all(0)
		if i < filled:
			sb0.bg_color = Color(0.0, 0.78, 1.0, 1.0)
			sb0.border_color = Color(0.55, 0.92, 1.0, 0.95)
		else:
			sb0.bg_color = Color(0.04, 0.16, 0.24, 0.92)
			sb0.border_color = Color(0.22, 0.48, 0.62, 0.9)
		cell0.add_theme_stylebox_override("panel", sb0)


func _layout_exp_segment_cells(
	root: Node,
	row: Control,
	seg_budget: float,
	slots_override: int = -1,
	filled_override: int = -1
) -> void:
	## Fill ExpSegRow into seg_budget only — never inflate past leftover under head/tail.
	if root == null or row == null:
		return
	if row is HBoxContainer:
		row = _rebox_as_axis(row, true)
	var box: BoxContainer = row as BoxContainer
	if box == null:
		return
	var demand: int = maxi(1, match_ctrl.up_level_demand)
	var exp_now: int = clampi(match_ctrl.player_exp, 0, demand)
	var buy_amt: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("buy_exp_amount", 4), 4))
	var slots: int = slots_override if slots_override > 0 else maxi(1, (demand + buy_amt - 1) / buy_amt)
	var filled: int = filled_override if filled_override >= 0 else clampi(exp_now / buy_amt, 0, slots)
	var sep: float = float(UiLayout.margin_px(2, box))
	box.add_theme_constant_override("separation", int(sep))
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.clip_contents = true
	box.custom_minimum_size.y = 0.0
	if box is VBoxContainer:
		(box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	## Rebuild if count mismatch.
	if box.get_child_count() != slots:
		for c: Node in box.get_children():
			box.remove_child(c)
			c.free()
	## Cap to LevelExp inner width — segs fill the locked column (not square-from-height,
	## which shifted the stack on X when leftover height changed).
	var le_w: float = _level_exp_fixed_width(root as Control) if root is Control else float(UiLayout.px(36, box))
	var pad_x: float = float(UiLayout.margin_px(3, box)) * 2.0
	var le_panel: Control = root.get_node_or_null(_SHOP_LEVEL) as Control
	if le_panel is PanelContainer:
		var sb_le: StyleBox = (le_panel as PanelContainer).get_theme_stylebox("panel")
		if sb_le != null:
			pad_x = sb_le.get_margin(SIDE_LEFT) + sb_le.get_margin(SIDE_RIGHT)
	var inner_cap: float = maxf(float(UiLayout.px(8, box)), le_w - pad_x)
	var cell_h: float = 0.0
	if slots > 0 and seg_budget > 0.5:
		cell_h = maxf(0.0, (seg_budget - sep * float(maxi(0, slots - 1))) / float(slots))
	box.custom_minimum_size.x = 0.0
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	while box.get_child_count() < slots:
		var cell: PanelContainer = PanelContainer.new()
		box.add_child(cell)
	while box.get_child_count() > slots:
		var last: Node = box.get_child(box.get_child_count() - 1)
		box.remove_child(last)
		last.free()
	for i: int in range(slots):
		var cell2: PanelContainer = box.get_child(i) as PanelContainer
		if cell2 == null:
			continue
		cell2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		## Width = LevelExp inner (no square-from-height). Height from leftover budget.
		cell2.custom_minimum_size = Vector2(inner_cap, cell_h)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		if i < filled:
			sb.bg_color = Color(0.0, 0.78, 1.0, 1.0)
			sb.border_color = Color(0.55, 0.92, 1.0, 0.95)
		else:
			sb.bg_color = Color(0.04, 0.16, 0.24, 0.92)
			sb.border_color = Color(0.22, 0.48, 0.62, 0.9)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		sb.set_content_margin_all(0)
		cell2.add_theme_stylebox_override("panel", sb)


func _deferred_style_shop_action_buttons() -> void:
	if hud == null:
		return
	var root: Control = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	_style_shop_action_buttons(
		root,
		root.get_node_or_null(_SHOP_BAR) as Control,
		root.get_node_or_null(_SHOP_BTNS) as Control,
		root.get_node_or_null("%s/ExpBtn" % _SHOP_BTNS) as Button,
		root.get_node_or_null("%s/RefreshBtn" % _SHOP_BTNS) as Button
	)


func _style_shop_action_buttons(root: Control, shop_bar: Control, shop_btns: Control, exp_btn: Button, refresh_btn: Button) -> void:
	if root == null:
		return
	## Fill reserved ShopBtns strip only — never use square-of-width as min height (overflows LeftCol).
	var strip_h: float = UiLayout.hud_height("ExpBtn", 0.078) * UiLayout.viewport_size(root).y
	strip_h = clampf(strip_h, float(UiLayout.px(40, root)), float(UiLayout.px(72, root)))
	if shop_btns != null:
		shop_btns.custom_minimum_size.y = strip_h
		if shop_btns.size.y >= 8.0:
			strip_h = clampf(shop_btns.size.y, float(UiLayout.px(40, root)), float(UiLayout.px(72, root)))
	var art_w: float = float(UiLayout.px(64, root))
	var art_h: float = strip_h
	if shop_btns != null and shop_btns.size.x >= 16.0:
		var sep: float = float(UiLayout.margin_px(4, root))
		art_w = maxf(8.0, (shop_btns.size.x - sep) * 0.5)
	elif shop_bar != null and shop_bar.size.x >= 16.0:
		art_w = clampf(shop_bar.size.x * 0.46, float(UiLayout.px(48, root)), float(UiLayout.px(200, root)))
	elif _hud_shop_card_side >= 8.0:
		art_w = clampf(_hud_shop_card_side + float(UiLayout.px(40, root)), float(UiLayout.px(48, root)), float(UiLayout.px(200, root)))
	## Cap icon box to strip height so button mins cannot push ShopBtns past budget.
	art_h = strip_h
	art_w = minf(art_w, maxf(strip_h * 2.5, float(UiLayout.px(48, root))))
	if exp_btn:
		_style_image_button_fill(
			exp_btn,
			UiAssets.shop_exp_path(),
			"购买经验",
			TypedVariant.as_int(DataStore.economy.get("buy_exp_gold_cost", 4), 0),
			art_w,
			art_h
		)
		exp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exp_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_wire_exp_hold(exp_btn)
	if refresh_btn:
		_style_image_button_fill(
			refresh_btn,
			UiAssets.shop_refresh_path(),
			"刷新商店",
			TypedVariant.as_int(DataStore.economy.get("refresh_cost", 2), 0),
			art_w,
			art_h
		)
		refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		refresh_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _style_image_button_fill(
	btn: Button,
	tex_path: String,
	title: String,
	cost: int,
	width_px: float,
	height_px: float
) -> void:
	if btn == null:
		return
	btn.text = ""
	btn.tooltip_text = "%s  %d" % [title, cost]
	var w: float = maxf(8.0, width_px)
	var h: float = maxf(8.0, height_px)
	var t: Texture2D = UiAssets.tex(tex_path)
	## Min height must stay ≤ ShopBtns strip; width hint only — EXPAND fills strip.
	btn.custom_minimum_size = Vector2(0.0, minf(h, float(UiLayout.px(72, btn))))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if t:
		btn.icon = t
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", int(maxf(w, h)))
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("disabled", empty)


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


func refresh_all_ship_health_bars() -> void:
	if board == null:
		return
	for s: ShipUnit in board.all_ships():
		if s != null and is_instance_valid(s) and s.has_method("refresh_health_bar"):
			s.refresh_health_bar()

func _on_hud_refresh_full() -> void:
	_request_hud_refresh(true)


func _on_hud_tick() -> void:
	_request_hud_refresh(false)


func _hud_refresh_min_interval_s() -> float:
	## Hard cap: refresh Hz ≤ half of Engine FPS → period ≥ 2/fps.
	var fps: float = maxf(Engine.get_frames_per_second(), 1.0)
	return 2.0 / fps


func _request_hud_refresh(full: bool) -> void:
	_hud_refresh_pending = maxi(_hud_refresh_pending, 2 if full else 1)
	_try_flush_hud_refresh()


func _try_flush_hud_refresh() -> void:
	if _hud_refresh_pending <= 0:
		return
	if _hud_refresh_since_s < _hud_refresh_min_interval_s():
		return
	_hud_refresh_since_s = 0.0
	var full: bool = _hud_refresh_pending >= 2
	_hud_refresh_pending = 0
	var t0: int = Time.get_ticks_usec()
	## Hold-upgrade always stays light (UI_AND_SHELL §2.5).
	if _exp_hold_active or not full:
		_refresh_hud_core(false)
	else:
		_refresh_hud_core(true)
	SessionDiagnostics.add_usec(&"hud", Time.get_ticks_usec() - t0)


func _refresh_hud() -> void:
	## Hold-upgrade: `_grant_exp` emits hud_refresh every 0.05s — must stay light.
	if _exp_hold_active:
		_request_hud_refresh(false)
		return
	_request_hud_refresh(true)


func _refresh_hud_economy_only() -> void:
	## Buy-exp hold / cheap gold updates — skip fetter rebuild, adaptive layout, inventory.
	_request_hud_refresh(false)


func _refresh_hud_core(full: bool) -> void:
	var root: Control = hud.get_node_or_null("Root")
	if root == null:
		return
	_set_label(root, "%s/Hp" % _ROUND, _player_hp_label_text())
	_refresh_citadel_bar()
	_set_label(root, "%s/Phase" % _ROUND, "阶段 %d-%d" % [match_ctrl.battle_phase_value, match_ctrl.round_phase_value])
	_refresh_region_label()
	_set_label(root, "%s/GoldBox/Gold" % _BOTTOM_GOLD_POP, "%d" % match_ctrl.player_gold)
	_set_label(root, "%s/PopBox/Pop" % _BOTTOM_GOLD_POP, "%d/%d" % [board.count_field(ShipUnit.TEAM_PLAYER), match_ctrl.population_limit()])
	_set_label(root, "%s/LEInner/Level" % _SHOP_LEVEL, "%d级" % match_ctrl.player_level)
	_set_label(root, "%s/LEInner/Exp" % _SHOP_LEVEL, "%d / %d" % [match_ctrl.player_exp, match_ctrl.up_level_demand])
	_set_label(root, "%s/LEInner/LETextCol/Level" % _SHOP_LEVEL, "%d级" % match_ctrl.player_level)
	_set_label(root, "%s/LEInner/LETextCol/Exp" % _SHOP_LEVEL, "%d / %d" % [match_ctrl.player_exp, match_ctrl.up_level_demand])
	_set_label(root, "%s/LEInner/LELabels/Level" % _SHOP_LEVEL, "%d级" % match_ctrl.player_level)
	_set_label(root, "%s/LEInner/LELabels/Exp" % _SHOP_LEVEL, "%d / %d" % [match_ctrl.player_exp, match_ctrl.up_level_demand])
	_refresh_exp_segments(root)
	## Fixed LevelExp width — never re-snap Meta on hold ticks.
	if full:
		_fit_level_exp_width(root)
		_refresh_scanner_cost_caption(root)
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
	if full:
		_apply_shop_interactable()
		_refresh_fetter_ui(root)
		_refresh_equipment_inventory_ui()
		@warning_ignore("unsafe_cast")
		var ver: Label = root.get_node_or_null("TopRight/Version") as Label
		if ver:
			## UI_AND_SHELL §2：局内版本 = 内容热更版（禁止壳号）。
			ver.text = "游戏版本:%s" % DataStore.content_version
		## RoundBar / TopRight widths track live label lengths (HP / phase / timer / ver).
		_apply_adaptive_hud_layout()
		_refresh_open_ship_info()

func _refresh_open_ship_info() -> void:
	## Keep InfoPanel in sync after star merge / equip / HUD refresh (UI_AND_SHELL §2.5).
	## Prefer live `_info_ship`; else DETAIL restores `_last_touched_ship`.
	if is_instance_valid(_info_ship) and not _info_ship.is_destroyed:
		_show_ship_info(_info_ship)
		return
	_info_ship = null
	if _right_pane_mode == RightPaneMode.DETAIL and not _collapse_right:
		_restore_detail_ship_panel()
		return
	if is_instance_valid(_last_touched_ship) and _last_touched_ship.is_destroyed:
		_last_touched_ship = null

func _apply_shop_interactable() -> void:
	## Shop stays interactive in Prepare and Battle (no grey-lock).
	var root: Control = hud.get_node_or_null("Root")
	if root == null:
		return
	for path: String in [
			"%s/ExpBtn" % _SHOP_BTNS,
			"%s/RefreshBtn" % _SHOP_BTNS,
			_SHOP_SCANNER,
			"%s/ScannerFrame/ScannerBtn" % _SHOP_SCANNER_HOST,
			"%s/ScannerBtn" % _SHOP_SCANNER_HOST]:
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
	var side: VBoxContainer = _bonus_container_of(root as Control)
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
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side.add_child(list)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in list.get_children():
		c.queue_free()
	var fetters: Array = board.recalculate_fetters(ShipUnit.TEAM_PLAYER)
	## Meta titans append one active row per effect for combat muls — collapse to one UI card.
	var shown_meta: Dictionary = {}
	for a_v: Variant in fetters:
		var a: Dictionary = TypedVariant.as_dict(a_v)
		var fid: String = str(a.get("fetter_id", ""))
		var is_meta: bool = TypedVariant.as_bool(a.get("meta", false), false)
		if is_meta:
			if TypedVariant.as_bool(shown_meta.get(fid, false), false):
				continue
			shown_meta[fid] = true
		var fdata: Dictionary = DataStore.fetters.get(fid, {})
		var fname: String = str(fdata.get("name", fid))
		var count: int = TypedVariant.as_int(a.get("count", 0), 0)
		var eff: Dictionary = a.get("effect", {})
		var need: int = TypedVariant.as_int(eff.get("champion_count", 0), 0)
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var icon: TextureRect = TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(UiLayout.px(26, list), UiLayout.px(26, list))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex: Texture2D = UiAssets.fetter_icon(fid, fname)
		if tex:
			icon.texture = tex
		row.add_child(icon)
		var col: VBoxContainer = VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		var lab: Label = Label.new()
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		## Meta titans list every effect once under a single card (combat + shop + ewar).
		var effect_lines: Array = []
		if is_meta:
			for e: Variant in TypedVariant.as_array(fdata.get("effects", [])):
				if typeof(e) == TYPE_DICTIONARY:
					effect_lines.append(e)
		else:
			effect_lines.append(eff)
		for e: Variant in effect_lines:
			var ed: Dictionary = TypedVariant.as_dict(e)
			var eff_txt: String = UiAssets.fetter_effect_text(ed)
			if eff_txt == "":
				continue
			var step_n: int = TypedVariant.as_int(a.get("step_ships", ed.get("step_ships", 0)), 0)
			if step_n > 0 and not is_meta:
				eff_txt = "%s（步进+%d）" % [eff_txt, step_n]
			var elab: Label = Label.new()
			elab.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var box: Control = hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as Control
	if box == null:
		box = hud.get_node_or_null("Root/%s/ShopSlots" % _SHOP_INNER) as Control
	if box == null:
		return
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 0.0
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
	var shop_content: Control = null
	if hud:
		shop_content = hud.get_node_or_null("Root/Shop/ShopCol/ShopContent") as Control
	var h_sep: float = float(grid.get_theme_constant(&"h_separation"))
	var v_sep: float = float(grid.get_theme_constant(&"v_separation"))
	if h_sep <= 0.0:
		h_sep = 4.0
	if v_sep <= 0.0:
		v_sep = 4.0
	## Square cells; 1 row × 16 columns; GoldPop shares the same width (UI_AND_SHELL §2.1).
	var cols: int = maxi(1, grid.columns)
	var gold_pop: Control = null
	if host:
		gold_pop = host.get_node_or_null("GoldPop") as Control
	if gold_pop == null and hud:
		gold_pop = hud.get_node_or_null("Root/%s" % _BOTTOM_GOLD_POP) as Control
	var avail_h: float = 0.0
	if host and host.size.y >= 8.0:
		avail_h = host.size.y
	elif shop_content and shop_content.size.y >= 8.0:
		avail_h = shop_content.size.y
	else:
		avail_h = grid.size.y
	if gold_pop:
		var gh: float = gold_pop.size.y
		if gh < 1.0:
			gh = gold_pop.custom_minimum_size.y
		if gh > 1.0:
			avail_h = maxf(8.0, avail_h - gh - v_sep)
	if avail_h < 8.0:
		avail_h = grid.size.y if grid.size.y >= 8.0 else UiLayout.px(48.0, grid)
	var avail_w: float = 0.0
	if shop_content and shop_content.size.x >= 8.0:
		avail_w = shop_content.size.x
	elif host and host.size.x >= 8.0:
		avail_w = host.size.x
	if avail_w < 8.0:
		avail_w = grid.size.x
	if avail_w < 8.0:
		avail_w = UiLayout.px(160.0, grid)
	var cell_w: float = (avail_w - h_sep * float(maxi(0, cols - 1))) / float(cols)
	cell_w = minf(cell_w, avail_h)
	cell_w = clampf(cell_w, UiLayout.px(14.0, grid), UiLayout.px(64.0, grid))
	var cell_h: float = cell_w
	var grid_w: float = cell_w * float(cols) + h_sep * float(maxi(0, cols - 1))
	grid.custom_minimum_size = Vector2(grid_w, cell_h)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_END
	if gold_pop:
		gold_pop.custom_minimum_size.x = grid_w
		gold_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_pop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if host and str(host.name) == "BottomCluster":
		host.custom_minimum_size.x = grid_w
		host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for c: Node in grid.get_children():
		if c is Control:
			var cell_ctrl: Control = c as Control
			cell_ctrl.custom_minimum_size = Vector2(cell_w, cell_h)
			cell_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cell_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ensure_equipment_slots_grid(meta_mid: Control, shop_bar: Control, root: Control) -> Control:
	## UI_AND_SHELL §3.2 — single column of 5 in MetaMid; bottom-snaps to advanced refresh via snap pass.
	if meta_mid == null:
		return null
	var meta_col: Control = meta_mid.get_parent() as Control
	var equip_raw: Control = meta_mid.get_node_or_null("EquipmentSlots") as Control
	if equip_raw == null and meta_col != null:
		equip_raw = meta_col.get_node_or_null("EquipmentSlots") as Control
	if equip_raw == null and shop_bar != null:
		equip_raw = shop_bar.get_node_or_null("EquipmentSlots") as Control
	if equip_raw == null and root != null:
		equip_raw = root.get_node_or_null(
			"Shop/ShopCol/ShopContent/MetaRow/LeftCtrl/LeftBtns/EquipmentSlots"
		) as Control
	if equip_raw is VBoxContainer and not (equip_raw is HBoxContainer):
		var existing: VBoxContainer = equip_raw as VBoxContainer
		if existing.get_parent() != meta_mid:
			_reparent_keep_signals(existing, meta_mid)
		existing.size_flags_horizontal = 0
		existing.size_flags_vertical = 0
		existing.size_flags_stretch_ratio = 0.0
		existing.alignment = BoxContainer.ALIGNMENT_END
		existing.add_theme_constant_override("separation", UiLayout.margin_px(3, root))
		meta_mid.move_child(existing, mini(1, meta_mid.get_child_count() - 1))
		return existing
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "EquipmentSlots"
	box.size_flags_horizontal = 0
	box.size_flags_vertical = 0
	box.size_flags_stretch_ratio = 0.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", UiLayout.margin_px(3, root))
	if equip_raw != null:
		var old_parent: Node = equip_raw.get_parent()
		if old_parent != null:
			old_parent.remove_child(equip_raw)
		equip_raw.queue_free()
	meta_mid.add_child(box)
	meta_mid.move_child(box, mini(1, meta_mid.get_child_count() - 1))
	return box


func _ensure_equipment_shop_slots() -> void:
	var root: Control = hud.get_node_or_null("Root")
	if root == null:
		return
	var meta_mid: Control = root.get_node_or_null(_SHOP_META_MID) as Control
	if meta_mid == null:
		_ensure_left_shop_layout(root)
		meta_mid = root.get_node_or_null(_SHOP_META_MID) as Control
	if meta_mid == null:
		var meta_col: Control = root.get_node_or_null(_SHOP_META_COL) as Control
		if meta_col == null:
			return
		meta_mid = _ensure_meta_mid(meta_col, root)
	_ensure_equipment_slots_grid(meta_mid, null, root)


func _equip_shop_card_chrome_x(pad: float) -> float:
	## PanelContainer min width adds StyleBox border (1+1) + content margins (pad*2).
	return pad * 2.0 + 2.0


func _refresh_equipment_shop_ui() -> void:
	_ensure_equipment_shop_slots()
	var root: Control = hud.get_node_or_null("Root")
	if root == null or shop == null:
		return
	var box: Control = root.get_node_or_null(_SHOP_EQUIP_SLOTS) as Control
	if box == null:
		return
	## Lock LevelExp width + column snaps BEFORE measuring card target width.
	_apply_left_shop_snap_layout(root)
	_fit_level_exp_width(root)
	_apply_left_shop_snap_layout(root)
	var width_ready: bool = box.size.x >= 8.0
	for c: Node in box.get_children():
		c.queue_free()
	if shop.equipment_slots.is_empty() and shop.has_method("ensure_equipment_slots"):
		shop.ensure_equipment_slots()
	## ① fit width inside column chrome → ② bottom-kiss advanced refresh → ③ top may stay empty.
	var icon_side: float = float(UiLayout.px(28, box))
	var n_cards: int = maxi(1, shop.equipment_slots.size())
	var sep_e: float = float(UiLayout.margin_px(3, box))
	if box is VBoxContainer:
		(box as VBoxContainer).add_theme_constant_override("separation", int(sep_e))
		sep_e = float((box as VBoxContainer).get_theme_constant("separation"))
	var mid: Control = root.get_node_or_null(_SHOP_META_MID) as Control
	var budget_h: float = 0.0
	if box.size.y >= 40.0:
		budget_h = box.size.y
	elif mid != null and mid.size.y >= 40.0:
		budget_h = mid.size.y
	var col_w: float = box.size.x
	if col_w < 8.0 and mid != null:
		var mid_gap: float = float(UiLayout.margin_px(4, root))
		var le_w: float = _level_exp_fixed_width(root)
		col_w = maxf(8.0, mid.size.x - le_w - mid_gap)
	if col_w < 8.0:
		col_w = float(UiLayout.px(40, root))
	col_w = minf(col_w, maxf(8.0, box.size.x)) if box.size.x >= 8.0 else col_w
	var base_pad: float = float(UiLayout.margin_px(2, box))
	## Scale against inner content budget so Panel border+margins never push past col_w.
	var inner_budget: float = maxf(8.0, col_w - _equip_shop_card_chrome_x(base_pad))
	var natural_inner: float = icon_side
	var width_scale: float = inner_budget / maxf(1.0, natural_inner)
	var stack_natural: float = sep_e * float(maxi(0, n_cards - 1))
	for i_slot: int in range(shop.equipment_slots.size()):
		var slot_d: Dictionary = TypedVariant.as_dict(shop.equipment_slots[i_slot])
		var iid: String = str(slot_d.get("id", ""))
		var mod0: Dictionary = DataStore.get_function_module(iid) if iid != "" else {}
		var nm: String = str(mod0.get("name", mod0.get("id", "")))
		var lines: int = maxi(1, nm.length()) if not mod0.is_empty() else 1
		stack_natural += _equip_shop_card_natural_height(icon_side, base_pad, lines)
	var scale_mul: float = clampf(width_scale, 0.55, 3.5)
	if budget_h >= 40.0 and stack_natural > 1.0 and stack_natural * scale_mul > budget_h:
		scale_mul = clampf(budget_h / stack_natural, 0.55, scale_mul)
	## Re-cap after height shrink: scaled pad grows chrome.
	var pad_s: float = base_pad * scale_mul
	var inner_after: float = maxf(8.0, col_w - _equip_shop_card_chrome_x(pad_s))
	if icon_side * scale_mul > inner_after + 0.5:
		scale_mul = clampf(inner_after / maxf(1.0, icon_side), 0.55, scale_mul)
	var cards: Array[Control] = []
	for i: int in range(shop.equipment_slots.size()):
		var slot: Dictionary = TypedVariant.as_dict(shop.equipment_slots[i])
		var item_id: String = str(slot.get("id", ""))
		var purchased: bool = TypedVariant.as_bool(slot.get("purchased", false), false)
		var mod: Dictionary = DataStore.get_function_module(item_id) if item_id != "" else {}
		## target_w = column; card expands inside it (min-x stays 0 — see _make_equipment_shop_card).
		var card: Control = _make_equipment_shop_card(i, mod, purchased, icon_side, 0.0, col_w, scale_mul)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_SHRINK_END
		cards.append(card)
	for i: int in range(cards.size() - 1, -1, -1):
		box.add_child(cards[i])
	box.size_flags_horizontal = 0
	box.size_flags_vertical = 0
	box.size_flags_stretch_ratio = 0.0
	box.clip_contents = true
	if box is VBoxContainer:
		(box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
	_apply_left_shop_snap_layout(root)
	_fit_level_exp_width(root)
	_sync_equipment_shop_card_widths(box)
	if not width_ready and box.size.x >= 8.0 and not TypedVariant.as_bool(get_meta("_equip_shop_width_retry", false), false):
		set_meta("_equip_shop_width_retry", true)
		call_deferred("_deferred_refresh_equipment_shop_width")


func _sync_equipment_shop_card_widths(box: Control) -> void:
	## Column owns width. Cards EXPAND inside; never min-x = col_w (Panel chrome overflows).
	if box == null:
		return
	var w: float = box.size.x
	if w < 8.0:
		return
	box.clip_contents = true
	box.custom_minimum_size = Vector2.ZERO
	for c: Node in box.get_children():
		if c is Control:
			var card: Control = c as Control
			var h: float = card.custom_minimum_size.y
			card.custom_minimum_size = Vector2(0.0, h)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.clip_contents = true
			## Force into column — VBox can briefly assign min > parent.
			if card.size.x > w + 0.01 or card.size.x < 1.0:
				card.size = Vector2(w, maxf(card.size.y, h))


func _deferred_refresh_equipment_shop_width() -> void:
	set_meta("_equip_shop_width_retry", false)
	_refresh_equipment_shop_ui()


func _equip_shop_card_natural_height(icon_side: float, pad: float, name_lines: int) -> float:
	## Unscaled content height estimate (icon + vertical name + cost + chrome).
	## Bottom content_margin = 0 (price flush to card bottom).
	var gap: float = float(UiLayout.margin_px(1))
	var name_fs: int = UiLayout.font_size(10)
	var font: Font = ThemeDB.fallback_font
	var glyph_h: float = font.get_string_size("字", HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).y
	var cost_fs: int = UiLayout.font_size(10)
	var cost_h: float = font.get_string_size("99", HORIZONTAL_ALIGNMENT_LEFT, -1, cost_fs).y
	return pad + icon_side + gap + glyph_h * float(maxi(1, name_lines)) + gap + cost_h


func _vertical_cjk_label(s: String) -> String:
	var t: String = s.strip_edges()
	if t.is_empty():
		return ""
	var chars: PackedStringArray = PackedStringArray()
	for i: int in range(t.length()):
		chars.append(t.substr(i, 1))
	return "\n".join(chars)


func _make_equipment_shop_card(
	idx: int,
	mod: Dictionary,
	purchased: bool,
	icon_side: float,
	max_h: float = 0.0,
	target_w: float = 0.0,
	scale_mul: float = 1.0
) -> Control:
	## Card expands to column width via SIZE_EXPAND_FILL. Do NOT set min-x = target_w:
	## PanelContainer min = border + content_margin + child → would overflow the cyan frame.
	var card: PanelContainer = PanelContainer.new()
	var s: float = maxf(0.55, scale_mul)
	var pad: float = float(UiLayout.margin_px(2, card)) * s
	var pad_bot: float = 0.0  ## Price sits on card bottom — no bottom blank (EQUIPMENT §1).
	var gap: float = float(UiLayout.margin_px(1, card)) * s
	var outer: StyleBoxFlat = StyleBoxFlat.new()
	outer.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	outer.border_color = Color(0.35, 0.62, 0.78, 0.9)
	outer.set_border_width_all(1)
	outer.set_corner_radius_all(4)
	var pad_i: int = maxi(1, roundi(pad))
	outer.content_margin_left = pad_i
	outer.content_margin_right = pad_i
	outer.content_margin_top = pad_i
	outer.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", outer)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.clip_contents = true
	var name_fs: int = maxi(7, roundi(float(UiLayout.font_size(10, card)) * s))
	var font: Font = ThemeDB.fallback_font
	var glyph_w: float = font.get_string_size("字", HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x
	var glyph_h: float = font.get_string_size("字", HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).y
	var icon_fit: float = icon_side * s
	## Inner content must fit: col - borders - margins.
	if target_w >= 8.0:
		var max_inner: float = maxf(4.0, target_w - _equip_shop_card_chrome_x(pad))
		icon_fit = minf(icon_fit, max_inner)
		glyph_w = minf(glyph_w, max_inner)
	if purchased or mod.is_empty():
		var ph: Label = Label.new()
		ph.text = "已购" if purchased else ""
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiAssets.apply_label_font(ph, false, maxi(7, roundi(float(UiLayout.font_size(11, card)) * s)))
		card.add_child(ph)
		var ph_h: float = maxf(icon_fit + pad + pad_bot, glyph_h + pad + pad_bot)
		if max_h > 8.0:
			ph_h = minf(ph_h, max_h)
		## min-x 0 → parent column assigns width; height content-fit.
		card.custom_minimum_size = Vector2(0.0, ph_h)
		return card
	var name_s: String = str(mod.get("name", mod.get("id", "")))
	var name_lines: int = maxi(1, name_s.length())
	var cost: int = TypedVariant.as_int(mod.get("cost", 10), 0)
	var show_cost: bool = not TypedVariant.as_bool(mod.get("implant", false), false)
	var cost_fs: int = maxi(7, roundi(float(UiLayout.font_size(10, card)) * s))
	var cost_h: float = 0.0
	if show_cost:
		cost_h = font.get_string_size(str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, cost_fs).y
	var chrome: float = pad + pad_bot + gap + (gap if show_cost else 0.0)
	var text_block: float = glyph_h * float(name_lines) + cost_h
	if max_h > 8.0:
		var room_icon: float = max_h - chrome - text_block
		if room_icon < icon_fit:
			icon_fit = clampf(room_icon, float(UiLayout.px(12, card)), icon_side * s)
		if chrome + text_block > max_h:
			var shrink: float = max_h / maxf(1.0, chrome + text_block)
			name_fs = maxi(7, roundi(float(name_fs) * shrink))
			cost_fs = maxi(7, roundi(float(cost_fs) * shrink))
			glyph_h = font.get_string_size("字", HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).y
			if show_cost:
				cost_h = font.get_string_size(str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, cost_fs).y
			text_block = glyph_h * float(name_lines) + cost_h
			icon_fit = clampf(max_h - chrome - text_block, float(UiLayout.px(12, card)), icon_side * s)
	if target_w >= 8.0:
		var max_inner2: float = maxf(4.0, target_w - _equip_shop_card_chrome_x(pad))
		icon_fit = minf(icon_fit, max_inner2)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", maxi(0, roundi(gap)))
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.clip_contents = true
	card.add_child(col)
	@warning_ignore("unsafe_method_access")
	var icon: Control = _EQUIP_ICON_VIEW.make_icon_cell(Vector2(icon_fit, icon_fit), mod, card)
	icon.custom_minimum_size = Vector2(icon_fit, icon_fit)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	var name_l: Label = Label.new()
	name_l.text = _vertical_cjk_label(name_s)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAssets.apply_label_font(name_l, false, name_fs)
	name_l.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_child(name_l)
	if show_cost:
		var cost_l: Label = Label.new()
		cost_l.text = str(cost)
		cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cost_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiAssets.apply_label_font(cost_l, false, cost_fs)
		cost_l.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
		cost_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost_l.size_flags_vertical = Control.SIZE_SHRINK_END
		cost_l.clip_text = true
		## Exact glyph height — Label default line box was leaving a blank under the price.
		cost_l.custom_minimum_size = Vector2(0.0, cost_h)
		cost_l.add_theme_constant_override("line_spacing", 0)
		col.add_child(cost_l)
	var want_h: float = chrome + icon_fit + text_block
	if max_h > 8.0:
		card.custom_minimum_size = Vector2(0.0, minf(want_h, max_h))
	else:
		card.custom_minimum_size = Vector2(0.0, 0.0)
		## Height from content; width from column EXPAND.
		if want_h > 1.0:
			card.custom_minimum_size.y = want_h
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		var inner_sz: Vector2 = Vector2(
			maxi(8.0, cell.custom_minimum_size.x - 4.0),
			maxi(8.0, cell.custom_minimum_size.y - 4.0)
		)
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


func _can_equip_ship_now(ship: ShipUnit) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if match_ctrl == null:
		return false
	if match_ctrl.stage == MatchController.Stage.PREPARE:
		return true
	## Battle: hangar ships only (EQUIPMENT.md / BOARD_AND_INPUT §4).
	if match_ctrl.stage == MatchController.Stage.BATTLE and ship.slot_type == "hangar":
		return true
	## Nestor battle_equip_aura: Field Nestor alive → allow equipping any own ship (EQUIPMENT §0.1).
	if match_ctrl.stage == MatchController.Stage.BATTLE and board != null:
		var team: int = ship.team_id
		if _team_has_battle_equip_aura(team):
			return true
	return false


func _team_has_battle_equip_aura(team: int) -> bool:
	if board == null:
		return false
	for s: ShipUnit in board.field_ships(team):
		if s == null or not is_instance_valid(s) or s.is_destroyed:
			continue
		if TypedVariant.as_bool(DataStore.get_ship(s.ship_id).get("battle_equip_aura", false), false):
			return true
	return false


func try_begin_fit_unequip_at_screen(screen: Vector2) -> bool:
	if match_ctrl == null:
		return false
	if match_ctrl.stage != MatchController.Stage.PREPARE and match_ctrl.stage != MatchController.Stage.BATTLE:
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
		if not _can_equip_ship_now(s):
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
		## Inventory / fitted gear: show SellZone only when shop is expanded.
		if (_equip_drag_source == "inventory" or _equip_drag_source == "fit") and is_shop_sell_enabled():
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
			if match_ctrl.stage == MatchController.Stage.PREPARE or match_ctrl.stage == MatchController.Stage.BATTLE:
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
	## Align with PointerInput._in_sell_zone; left shop must be expanded.
	if not is_shop_sell_enabled():
		return false
	@warning_ignore("unsafe_cast")
	var sell: Control = _resolve_sell_zone()
	if sell != null and sell.visible:
		@warning_ignore("unsafe_cast")
		var left_vis: Control = hud.get_node_or_null("Root/LeftCol") as Control
		if left_vis == null or not left_vis.visible:
			return false
		return sell.get_global_rect().has_point(screen)
	@warning_ignore("unsafe_cast")
	var buy: Control = hud.get_node_or_null("Root/%s" % _SHOP_BUY_COL) as Control
	if buy == null or not buy.visible:
		return false
	return buy.get_global_rect().has_point(screen)


func is_shop_sell_enabled() -> bool:
	## ShopBar never collapses; fetter collapse does not disable sell (UI_AND_SHELL §2.1).
	return true


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
	if not is_instance_valid(_last_touched_ship):
		_last_touched_ship = null
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
	## EQUIPMENT.md: equip drop only counts when the camera ray hits hull mesh AABB.
	if camera == null or board == null:
		return null
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	var best: ShipUnit = null
	var best_t: float = INF
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s) or s.is_destroyed or s.is_unmanned:
			continue
		if TypedVariant.as_int(s.team_id, 0) != ShipUnit.TEAM_PLAYER:
			continue
		var t: float = s.ray_hit_model_distance(origin, dir)
		if t < 0.0:
			continue
		if t < best_t:
			best_t = t
			best = s
	return best


func _try_drop_equipment_on_ship(screen: Vector2, item_id: String, from_shop: bool, source_idx: int) -> bool:
	var ship: ShipUnit = _pick_ship_at_screen(screen)
	if ship == null:
		return false
	if not _can_equip_ship_now(ship):
		if match_ctrl.stage == MatchController.Stage.BATTLE:
			show_notice("战斗中仅可装配候席舰")
		else:
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
		"lance_taken":
			show_notice("每舰只能装一把长枪")
		"capital_role":
			show_notice("混合长枪仅无畏可装")
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
			"lance_taken":
				show_notice("每舰只能装一把长枪")
			"capital_role":
				show_notice("混合长枪仅无畏可装")
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

## UI_AND_SHELL §2.1.1 — COVERED scale, top-aligned (bright nebula stays in frame; Amarr fix).
func _shop_tips_top_align(tips: TextureRect, host: Control) -> void:
	## Left shop card: previous +90° then +180° → Godot −90° (UI_AND_SHELL §2.1.1).
	if tips == null or host == null or tips.texture == null:
		return
	var hw: float = host.size.x
	var hh: float = host.size.y
	if hw < 1.0 or hh < 1.0:
		return
	var tw: float = float(tips.texture.get_width())
	var th: float = float(tips.texture.get_height())
	if tw < 1.0 or th < 1.0:
		return
	## After ±90°, visual size is (th*s, tw*s); cover the card.
	var s: float = maxf(hw / th, hh / tw)
	var dw: float = tw * s
	var dh: float = th * s
	tips.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tips.anchor_right = 0.0
	tips.anchor_bottom = 0.0
	tips.pivot_offset = Vector2(dw * 0.5, dh * 0.5)
	tips.rotation = -PI / 2.0
	tips.position = Vector2((hw - dw) * 0.5, (hh - dh) * 0.5)
	tips.size = Vector2(dw, dh)


func _shop_card_size(slot_count: int, box: Control) -> Vector2:
	if _hud_shop_card_size.x >= 8.0 and _hud_shop_card_size.y >= 8.0:
		## Fill path always stores squares.
		var s0: float = minf(_hud_shop_card_size.x, _hud_shop_card_size.y)
		return Vector2(s0, s0)
	var avail_h: float = box.size.y
	if avail_h < 8.0:
		@warning_ignore("unsafe_cast")
		var ship_col: Control = hud.get_node_or_null("Root/%s" % _SHOP_INNER) as Control
		if ship_col and ship_col.size.y >= 8.0:
			avail_h = ship_col.size.y
	if avail_h < 8.0:
		@warning_ignore("unsafe_cast")
		var bar: Control = hud.get_node_or_null("Root/%s" % _SHOP_BAR) as Control
		var btns: Control = hud.get_node_or_null("Root/%s" % _SHOP_BTNS) as Control
		if bar and bar.size.y >= 8.0:
			var bh: float = btns.size.y if btns and btns.size.y >= 8.0 else 0.0
			avail_h = maxf(8.0, bar.size.y - bh - float(UiLayout.margin_px(2, box)))
	if avail_h < 8.0:
		avail_h = UiLayout.px(560.0, box)
	var n: int = maxi(1, slot_count)
	var sep: float = float(UiLayout.margin_px(2, box))
	var side: float = (avail_h - sep * float(n - 1)) / float(n)
	var max_w: float = box.size.x
	if max_w < 8.0:
		@warning_ignore("unsafe_cast")
		var ship_col_w: Control = hud.get_node_or_null("Root/%s" % _SHOP_INNER) as Control
		if ship_col_w and ship_col_w.size.x >= 8.0:
			max_w = ship_col_w.size.x
	if max_w >= 8.0:
		side = minf(side, max_w)
	side = clampf(side, UiLayout.px(28.0, box), UiLayout.px(200.0, box))
	return Vector2(side, side)

func _make_shop_card(ship_name: String, ship: Dictionary, purchased: bool, cost: int, idx: int, card_size: Vector2 = Vector2.ZERO) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var sz: Vector2 = card_size if card_size.x > 0.0 else Vector2(UiLayout.px(140, card), UiLayout.px(170, card))
	card.custom_minimum_size = sz
	## Always expand equally so N cards fill ShopBody and kiss ShopBtns (no bottom dead gap).
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titan_race: String = _local_titan_race_for_ui()
	var tips_tex: Texture2D = null if purchased else UiAssets.shop_card_tips_skybox(ship, titan_race)
	var outer: StyleBoxFlat = StyleBoxFlat.new()
	## Fill only; cyan hairline is drawn on top of skybox (UI_AND_SHELL §2.1.1).
	if tips_tex != null:
		outer.bg_color = Color(0.08, 0.09, 0.12, 0.28)
	else:
		outer.bg_color = Color(0.14, 0.16, 0.18, 0.98)
	outer.border_color = Color(0, 0, 0, 0)
	outer.set_border_width_all(0)
	outer.set_corner_radius_all(4)
	outer.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", outer)
	card.clip_contents = true
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
		_add_shop_card_frame_overlay(stack)
		return card
	## UI_AND_SHELL §2.1.1: tips skybox under ISIS portrait — +90° fade toward screen center.
	if tips_tex:
		var tips: TextureRect = TextureRect.new()
		tips.name = "TipsSkybox"
		tips.texture = tips_tex
		tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tips.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tips.stretch_mode = TextureRect.STRETCH_SCALE
		stack.clip_contents = true
		stack.add_child(tips)
		var realign: Callable = func() -> void: _shop_tips_top_align(tips, stack)
		if not stack.resized.is_connected(realign):
			stack.resized.connect(realign)
		call_deferred("_shop_tips_top_align", tips, stack)
	## Transparent placeholder column: top pad → art frame (expand) → fetters → name.
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "CardLayout"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiLayout.margin_px(2, card))
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UiLayout.px(4, card)
	col.offset_right = -UiLayout.px(4, card)
	col.offset_top = UiLayout.px(4, card)
	col.offset_bottom = -UiLayout.px(4, card)
	stack.add_child(col)
	var top_pad: Control = Control.new()
	top_pad.name = "TopPad"
	top_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_pad.custom_minimum_size = Vector2(0, UiLayout.px(22, card))
	top_pad.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_child(top_pad)
	## Art station: transparent frame fills leftover height; portrait contain-centered inside.
	var art_frame: Control = Control.new()
	art_frame.name = "ArtFrame"
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_frame.custom_minimum_size = Vector2(0, UiLayout.px(56, card))
	col.add_child(art_frame)
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
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 立绘 = ArtFrame 的 70%（居中 contain），留出星空点缀边。
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.anchor_left = 0.15
	art.anchor_top = 0.15
	art.anchor_right = 0.85
	art.anchor_bottom = 0.85
	art.offset_left = 0.0
	art.offset_top = 0.0
	art.offset_right = 0.0
	art.offset_bottom = 0.0
	art_frame.add_child(art)
	# 本舰可达成羁绊 · 立绘下方简展
	var fids: Array = ship.get("fetter_ids", [])
	var badge_icon: int = UiLayout.px(18 if UiLayout.is_mobile() else 22, card)
	var fetter_box: HBoxContainer = HBoxContainer.new()
	fetter_box.add_theme_constant_override("separation", UiLayout.margin_px(3, card))
	fetter_box.alignment = BoxContainer.ALIGNMENT_CENTER
	fetter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fetter_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fetter_box.custom_minimum_size = Vector2(0, badge_icon + 2.0)
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
	col.add_child(fetter_box)
	# Name under fetter strip
	var name_l: Label = Label.new()
	name_l.text = ship_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_END
	name_l.custom_minimum_size = Vector2(0, UiLayout.px(22, card))
	UiAssets.apply_label_font(name_l, false, UiLayout.font_size(14, card))
	name_l.add_theme_color_override("font_color", Color(1, 1, 1))
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_l.add_theme_constant_override("outline_size", 3)
	col.add_child(name_l)
	# ★ 角标 · 左上（叠在透明站位之上）
	var star_badge: PanelContainer = _make_corner_badge("★1", Color(0.12, 0.1, 0.05, 0.92), Color(1.0, 0.88, 0.35), card)
	star_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	star_badge.offset_left = UiLayout.px(4, card)
	star_badge.offset_top = UiLayout.px(4, card)
	star_badge.offset_right = star_badge.offset_left + UiLayout.px(42, card)
	star_badge.offset_bottom = star_badge.offset_top + UiLayout.px(24, card)
	stack.add_child(star_badge)
	# 价格角标 · 右上（与星级左上对称）
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
	cost_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cost_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cost_badge.grow_vertical = Control.GROW_DIRECTION_END
	cost_badge.offset_right = -UiLayout.px(4, card)
	cost_badge.offset_top = UiLayout.px(4, card)
	cost_badge.offset_left = cost_badge.offset_right - UiLayout.px(56, card)
	cost_badge.offset_bottom = cost_badge.offset_top + UiLayout.px(26, card)
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
		hit.mouse_entered.connect(func() -> void: _show_ship_info_id(TypedVariant.as_int(ship.get("id", 0), 0), false))
	stack.add_child(hit)
	_add_shop_card_frame_overlay(stack)
	return card


func _add_shop_card_frame_overlay(stack: Control) -> void:
	## Cyan rounded hairline on top of skybox (UI_AND_SHELL §2.1.1 / right-col style).
	if stack == null:
		return
	var overlay: Panel = stack.get_node_or_null("CardFrameOverlay") as Panel
	if overlay == null:
		overlay = Panel.new()
		overlay.name = "CardFrameOverlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(overlay)
	overlay.z_index = 12
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0.0
	overlay.offset_top = 0.0
	overlay.offset_right = 0.0
	overlay.offset_bottom = 0.0
	var fr: StyleBoxFlat = StyleBoxFlat.new()
	fr.bg_color = Color(0, 0, 0, 0)
	fr.border_color = Color(0.35, 0.72, 0.85, 0.9)
	fr.set_border_width_all(1)
	fr.set_corner_radius_all(4)
	fr.set_content_margin_all(0)
	overlay.add_theme_stylebox_override("panel", fr)


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
			_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0), true)
	elif _long_press_slot == idx and not _shop_long_previewed:
		var held: float = Time.get_ticks_msec() / 1000.0 - _long_press_t
		if held >= 0.35:
			_shop_long_previewed = true
			if idx >= 0 and idx < shop.slots.size():
				_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0), true)


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
		## Released still inside shop (or buy failed earlier): detail only (pin 10s).
		if idx >= 0 and idx < shop.slots.size():
			_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0), true)
		return
	## Tap without leaving shop = inspect (INPUT_PC_TOUCH_MAP §3/§4): open + pin InfoPanel.
	## Must not leave only the buy tip — hover-null must not wipe an unpinned panel.
	if idx >= 0 and idx < shop.slots.size():
		_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0), true)
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
	## Hangar or field under finger — drop after drag-buy (UI_AND_SHELL §2.3 · BOARD §4 solid ray).
	if camera == null or board == null:
		return {}
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	var slot: Dictionary = board.pick_slot_by_ray(origin, dir, ShipUnit.TEAM_PLAYER)
	var st: String = str(slot.get("slot_type", ""))
	if st == "hangar" or st == "field":
		return slot
	return _shop_pick_hangar_at_screen(screen)


func _shop_pick_hangar_at_screen(screen: Vector2) -> Dictionary:
	if camera == null or board == null:
		return {}
	var origin: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	var slot: Dictionary = board.pick_slot_by_ray(origin, dir, ShipUnit.TEAM_PLAYER)
	if str(slot.get("slot_type", "")) == "hangar":
		return slot
	return {}


func _set_sell_mode(active: bool, price: int = 0) -> void:
	## Overlay only — keep ShopSlots in layout so MetaCol / ShopBtns do not jump.
	@warning_ignore("unsafe_cast")
	var slots: Control = hud.get_node_or_null("Root/%s" % _SHOP_SLOTS) as Control
	if slots == null:
		slots = hud.get_node_or_null("Root/%s/ShopSlots" % _SHOP_INNER) as Control
	@warning_ignore("unsafe_cast")
	var sell: PanelContainer = _resolve_sell_zone()
	if slots:
		## Stay visible for layout footprint; ignore picks while sell overlay is up.
		slots.visible = true
		slots.mouse_filter = Control.MOUSE_FILTER_IGNORE if active else Control.MOUSE_FILTER_PASS
	if sell:
		sell.visible = active
		sell.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
		sell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sell.custom_minimum_size = Vector2.ZERO
		@warning_ignore("unsafe_cast")
		var lab: Label = sell.get_node_or_null("SellLabel") as Label
		if lab:
			lab.text = "售价  %d" % price if active else "售价"
			UiAssets.apply_label_font(lab, false, 22)

func _on_drag_begin(ship: ShipUnit) -> void:
	board.begin_drag(ship)
	_drag_info_ship = ship
	## Sell overlay only when bottom shop is expanded.
	if is_shop_sell_enabled():
		_dragging_sell_ui = true
		var price: int = 0
		if ship:
			price = ship.get_sell_price()
		_set_sell_mode(true, price)
	else:
		_dragging_sell_ui = false
		_set_sell_mode(false)

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
	_titan_intro_pitch_start = _cam_base_pitch_deg
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
	var u_slide: float = clampf(_titan_intro_t / _TITAN_INTRO_SLIDE_DUR_S, 0.0, 1.0)
	var u_cam: float = clampf(_titan_intro_t / _TITAN_INTRO_CAM_DUR_S, 0.0, 1.0)
	## Smoothstep.
	u_slide = u_slide * u_slide * (3.0 - 2.0 * u_slide)
	u_cam = u_cam * u_cam * (3.0 - 2.0 * u_cam)
	if home_sliding:
		_titan_berth.position = _titan_intro_start.lerp(_titan_intro_end, u_slide)
		_cam_base_pitch_deg = lerpf(_titan_intro_pitch_start, _titan_intro_pitch0, u_cam)
	if _rival_intro_active and _rival_titan_berth != null and is_instance_valid(_rival_titan_berth):
		_rival_titan_berth.position = _rival_intro_start.lerp(_rival_intro_end, u_slide)
	if u_slide < 1.0:
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
		_show_ship_info_id(TypedVariant.as_int(TypedVariant.as_dict(shop.slots[idx]).get("ship_id", 0), 0), true)

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
	if group == "industrial_command":
		return "heavy"
	if group == "mining_barge" or group == "battlecruiser" or group == "cruiser":
		return "medium"
	if group == "battleship":
		return "heavy"
	return "light"

func _race_drone_id(ship_data: Dictionary) -> int:
	## Ore mining hulls default to Gallente combat drones (MINING §2).
	var group: String = str(ship_data.get("ship_group", "")).to_lower()
	if group == "mining_barge":
		return 1007
	if group == "industrial_command":
		return 1013
	var race: String = str(ship_data.get("race", "amarr")).to_lower()
	match _drone_tier_for_carrier(ship_data):
		"heavy":
			return TypedVariant.as_int(_RACE_DRONE_HEAVY.get(race, 1011), 0)
		"medium":
			return TypedVariant.as_int(_RACE_DRONE_MEDIUM.get(race, 1005), 0)
		_:
			return TypedVariant.as_int(_RACE_DRONE_LIGHT.get(race, 1001), 0)

func _ship_drone_unit_ids(ship_data: Dictionary) -> Array:
	## Explicit multi-id list wins (Nestor 1421–1424, Guristas doubles).
	@warning_ignore("unsafe_cast")
	var raw: Array = ship_data.get("drone_unit_ids", []) as Array
	var out: Array = []
	for u: Variant in raw:
		var uid: int = TypedVariant.as_int(u, 0)
		if uid > 0:
			out.append(uid)
	return out


func _ship_fighter_unit_ids(ship_data: Dictionary) -> Array:
	## Multi-type carriers (Delirium): fighter_unit_ids[]; else single fighter_unit_id.
	@warning_ignore("unsafe_cast")
	var raw: Array = ship_data.get("fighter_unit_ids", []) as Array
	var out: Array = []
	for u: Variant in raw:
		var uid: int = TypedVariant.as_int(u, 0)
		if uid > 0:
			out.append(uid)
	if out.is_empty():
		var one: int = TypedVariant.as_int(ship_data.get("fighter_unit_id", 0), 0)
		if one > 0:
			out.append(one)
	return out


func _ship_drone_bay_slots(ship_data: Dictionary) -> int:
	var explicit: Array = _ship_drone_unit_ids(ship_data)
	if not explicit.is_empty():
		return explicit.size()
	var sid: int = TypedVariant.as_int(ship_data.get("id", 0), 0)
	var group: String = str(ship_data.get("ship_group", ""))
	## COMBAT §14C: logistic cruiser / BC show empty drone bay.
	if TypedVariant.as_bool(ship_data.get("is_logistic", false), false) and group in ["cruiser", "battlecruiser"]:
		return 0
	## Logistic battleship without drone_unit_ids: no combat heavies (Nestor must set the array).
	if TypedVariant.as_bool(ship_data.get("is_logistic", false), false) and group == "battleship":
		return 0
	if _DRONE_COUNT_EXCEPTIONS.has(sid):
		return TypedVariant.as_int(_DRONE_COUNT_EXCEPTIONS[sid], 0)
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
	if match_ctrl == null:
		return
	if not _can_equip_ship_now(_info_ship):
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
		var hi_slots: int = TypedVariant.as_int(ship_data.get("hi_slots", 0), 0)
		## hi_slots=0 (Nestor / Delirium): hide high-slot / primary weapon block — no zero-damage fake.
		if hi_slots <= 0 and not show_cyno and not is_mining and not is_titan_info:
			if weapon_panel:
				weapon_panel.visible = false
			if weapon_icon:
				weapon_icon.texture = null
			if weapon_label:
				weapon_label.text = ""
		elif is_titan_info:
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
			var fighter_ids: Array = _ship_fighter_unit_ids(ship_data)
			var drone_ids: Array = _ship_drone_unit_ids(ship_data)
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
			elif not fighter_ids.is_empty():
				## Carrier / Delirium: list each fighter type (1 squadron each when multi-id).
				var squads: int = TypedVariant.as_int(ship_data.get("fighter_squadrons", fighter_ids.size()), 0)
				var tubes: int = TypedVariant.as_int(ship_data.get("fighter_tubes_per_squadron", 3), 0)
				var names: PackedStringArray = PackedStringArray()
				var first_fid: int = TypedVariant.as_int(fighter_ids[0], 0)
				for fi: Variant in fighter_ids:
					var fid: int = TypedVariant.as_int(fi, 0)
					var fd: Dictionary = DataStore.get_ship(fid)
					names.append(str(fd.get("name", "舰载机")))
				var per_squad: int = tubes
				var multi: bool = fighter_ids.size() > 1
				var head: String = "、".join(names) if multi else str(names[0] if names.size() > 0 else "舰载机")
				var count_txt: String = "%d组×%d" % [fighter_ids.size(), per_squad] if multi else "×%d" % (squads * tubes)
				var stats_src: Dictionary = DataStore.get_ship(first_fid)
				var stats_star: Dictionary = DataStore.get_star(first_fid, maxi(star, 1))
				if drone_panel:
					drone_panel.visible = true
				if drone_icon:
					drone_icon.texture = UiAssets.champion_icon(str(stats_src.get("name", "")), first_fid)
					var fp: String = str(stats_src.get("portrait", ""))
					if fp != "" and drone_icon.texture == null:
						drone_icon.texture = UiAssets.tex(fp)
				if drone_label:
					drone_label.text = "%s %s\n%s" % [
						head,
						count_txt,
						_drone_stats_text(stats_src, stats_star)
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
			elif not drone_ids.is_empty():
				## Explicit list (Nestor 四族后勤): never fall back to race combat drones.
				var dnames: PackedStringArray = PackedStringArray()
				var first_did: int = TypedVariant.as_int(drone_ids[0], 0)
				for di: Variant in drone_ids:
					var did: int = TypedVariant.as_int(di, 0)
					var dd: Dictionary = DataStore.get_ship(did)
					dnames.append(str(dd.get("name", "无人机")))
				var d0: Dictionary = DataStore.get_ship(first_did)
				var d0_star: Dictionary = DataStore.get_star(first_did, maxi(star, 1))
				if drone_panel:
					drone_panel.visible = true
				if drone_icon:
					drone_icon.texture = UiAssets.drone_portrait(first_did)
					if drone_icon.texture == null:
						drone_icon.texture = UiAssets.champion_icon(str(d0.get("name", "")), first_did)
				if drone_label:
					drone_label.text = "%s\n各1 · 共%d\n%s" % [
						"、".join(dnames),
						drone_ids.size(),
						_drone_stats_text(d0, d0_star)
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
	## Do not auto-expand right column here — collapsed stays collapsed until user toggles (UI_AND_SHELL §2.5).

func _show_ship_info(ship: ShipUnit) -> void:
	_info_ship = ship
	if ship != null and is_instance_valid(ship):
		_last_touched_ship = ship
	_suppress_headup_for_preview = ship == null or ship.slot_type != "field"
	if ship == null:
		_refresh_observe_btn()
		return
	## Right collapsed: remember unit only — no panel / no auto-expand.
	if _collapse_right:
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

func _show_ship_info_id(ship_id: int, pin: bool = false) -> void:
	## `pin=true`: mobile shop tap / long-press — dwell INFO_HOLD_S so release→hover-null
	## cannot instantly hide the panel (INPUT_PC_TOUCH_MAP §4). PC shop hover keeps pin=false.
	## Do not wipe `_last_touched_ship` — shop preview is temporary.
	_info_ship = null
	_info_hold_until_ms = 0
	_suppress_headup_for_preview = true
	if _camera_observe:
		_exit_observe_keep_view()
	## Right collapsed: skip shop preview expand as well.
	if _collapse_right:
		_refresh_observe_btn()
		return
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
	if pin:
		_pin_ship_info()
	_refresh_observe_btn()

func _hide_ship_info() -> void:
	_info_hold_until_ms = 0
	_suppress_headup_for_preview = false
	if _camera_observe:
		_exit_observe_keep_view()
	## DETAIL mode must not become an empty shell — restore last touched unit.
	if _right_pane_mode == RightPaneMode.DETAIL and not _collapse_right:
		if _restore_detail_ship_panel():
			return
	_info_ship = null
	@warning_ignore("unsafe_cast")
	var p: PanelContainer = hud.get_node_or_null("Root/%s" % _INFO_PANEL) as PanelContainer
	if p:
		p.visible = false
	_refresh_observe_btn()

func _on_match_over(summary: String) -> void:
	SessionDiagnostics.log(
		"match.leave",
		"reason=match_over mode=%s summary=%s" % [str(GameSession.pending_mode), summary]
	)
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


func _nullsec_match_id() -> String:
	var net: NullsecNetSession = _nullsec_net_session()
	if net != null and str(net.match_id).strip_edges() != "":
		return str(net.match_id).strip_edges()
	return str(GameSession.pending_nullsec.get("match_id", "")).strip_edges()


## Unranked contestant rows for §7 report / provisional leave save.
func _collect_nullsec_settlement_player_rows() -> Array:
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
	if local_seat >= 0 and not _seat_titan_alive(local_seat):
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
			"淘汰" if oelim > 0 or not _seat_titan_alive(seat_id) else "—",
			[],
			TypedVariant.as_array(_match_titles.get(seat_id, [])),
			seat_id,
			TypedVariant.as_int(owld.get("w", 0), 0),
			TypedVariant.as_int(owld.get("l", 0), 0),
			TypedVariant.as_int(owld.get("d", 0), 0),
			0,
			TypedVariant.as_int(_kills_by_seat.get(seat_id, 0), 0),
			TypedVariant.as_bool(s.get("is_ai", false), false),
			false
		)
		orow["elimination_order"] = oelim
		orow["ghost"] = TypedVariant.as_bool(s.get("ghost", false), false)
		rows.append(orow)
	if local_seat >= 0 and not TypedVariant.as_bool(seen_seats.get(local_seat, false), false):
		rows.insert(0, row)
	return rows


func _make_local_nullsec_match_report(provisional: bool = false) -> Dictionary:
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), -1)
	var report: Dictionary = NullsecSettlement.make_match_report(
		_nullsec_match_id(), local_seat, _collect_nullsec_settlement_player_rows(), _nullsec_rng
	)
	if provisional:
		report["provisional"] = true
	return report


func _should_save_provisional_nullsec_report() -> bool:
	if str(GameSession.pending_mode) != "nullsec":
		return false
	if _nullsec_spectate_reason == "eliminated":
		return true
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), -1)
	return local_seat >= 0 and not _seat_titan_alive(local_seat)


func _save_provisional_nullsec_report() -> void:
	if not _should_save_provisional_nullsec_report():
		return
	NullsecSettlement.save_match_report(_make_local_nullsec_match_report(true))


func _present_nullsec_settlement(summary: String) -> void:
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), -1)
	var report: Dictionary = _make_local_nullsec_match_report(false)
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
	var net: NullsecNetSession = _nullsec_net_session()
	if net:
		if not net.match_report_received.is_connected(_on_nullsec_match_report_received):
			net.match_report_received.connect(_on_nullsec_match_report_received, CONNECT_ONE_SHOT)
		## Submit local ranked row for host stitch / broadcast.
		for r_v: Variant in TypedVariant.as_array(report.get("players", [])):
			var r: Dictionary = TypedVariant.as_dict(r_v)
			if TypedVariant.as_int(r.get("seat_id", -1), -1) == local_seat:
				net.submit_local_match_summary(r)
				break
	## Persist via upsert (match_id); authoritative broadcast later replaces provisional.
	_settlement_panel.show_report(report)
	show_notice(summary)

func _submit_seat_round_summary_if_net(result: String) -> void:
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null or GameSession.pending_mode != "nullsec":
		return
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	var titles: Array = []
	if _match_titles.has(local_seat):
		titles = TypedVariant.as_array(_match_titles.get(local_seat)).duplicate()
	var wld: Dictionary = TypedVariant.as_dict(_wld_by_seat.get(local_seat, {}))
	var round_id: int = TypedVariant.as_int(match_ctrl.battle_game_stage_count, 0) if match_ctrl else 0
	var summary: Dictionary = {
		"seat": local_seat,
		"seat_id": local_seat,
		"rival": rival,
		"result": result,
		"titles": titles,
		"w": TypedVariant.as_int(wld.get("w", 0), 0),
		"l": TypedVariant.as_int(wld.get("l", 0), 0),
		"d": TypedVariant.as_int(wld.get("d", 0), 0),
		"round": round_id,
		"is_ai": false,
	}
	## Host fills AI desks before local human ingest so stitch does not race empty AI rows.
	if net.is_host:
		_host_inject_ai_round_summaries(round_id)
	if net.has_method("submit_seat_round_summary"):
		net.call("submit_seat_round_summary", summary)
	SessionDiagnostics.log("net.round_summary", "seat=%d result=%s titles=%d" % [local_seat, result, titles.size()])


func _host_inject_ai_round_summaries(round_id: int) -> void:
	var net: NullsecNetSession = _nullsec_net_session()
	if net == null or not net.is_host or not net.has_method("host_inject_round_summary"):
		return
	@warning_ignore("unsafe_cast")
	var seats: Array = GameSession.pending_nullsec.get("seats", []) as Array
	var mu: Dictionary = TypedVariant.as_dict(GameSession.pending_nullsec.get("round_matchups", {}))
	for s_v: Variant in seats:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if not TypedVariant.as_bool(s.get("is_ai", false), false):
			continue
		if NullsecNetSession.is_spectate_race(str(s.get("titan_race", ""))):
			continue
		if not NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			continue
		var seat_id: int = TypedVariant.as_int(s.get("seat_id", -1), -1)
		if seat_id < 0:
			continue
		var rival: int = NullsecRoundPairing.rival_from_matchups(mu, seat_id)
		var result: String = _ai_round_result_for_seat(seat_id, rival)
		var wld: Dictionary = _wld_tuple(seat_id)
		var titles: Array = TypedVariant.as_array(_match_titles.get(seat_id, [])).duplicate()
		net.call("host_inject_round_summary", {
			"seat": seat_id,
			"seat_id": seat_id,
			"rival": rival,
			"result": result,
			"titles": titles,
			"w": TypedVariant.as_int(wld.get("w", 0), 0),
			"l": TypedVariant.as_int(wld.get("l", 0), 0),
			"d": TypedVariant.as_int(wld.get("d", 0), 0),
			"round": round_id,
			"is_ai": true,
			"nick": str(s.get("nick", "席位%d" % seat_id)),
		})


func _ai_round_result_for_seat(seat_id: int, rival: int) -> String:
	## Prefer inverting a human rival's known local result; else AI↔AI dual_win / PVE win.
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	if rival == local_seat and match_ctrl and not _seat_is_ai(rival):
		var hr: String = str(match_ctrl.last_round_result)
		if hr == "win":
			return "lose"
		if hr == "lose":
			return "win"
		return "draw"
	## AI vs human on another table: WLD already bumped by host instant/report paths when known.
	if rival >= 0 and not _seat_is_ai(rival):
		## No local POV — leave as win if host already counted a win this round via instant settle.
		var wld: Dictionary = _wld_tuple(seat_id)
		if TypedVariant.as_int(wld.get("w", 0), 0) > 0:
			return "win"
		return "—"
	## AI vs AI / AI PVE instant: recorded as wins on host.
	return "win"


func _on_net_round_standings(standings: Dictionary) -> void:
	var summaries: Array = TypedVariant.as_array(standings.get("summaries", []))
	SessionDiagnostics.log(
		"net.round_standings",
		"apply n=%d round=%d" % [
			summaries.size(),
			TypedVariant.as_int(standings.get("round", -1), -1),
		]
	)
	for s_v: Variant in summaries:
		var s: Dictionary = TypedVariant.as_dict(s_v)
		var seat: int = TypedVariant.as_int(s.get("seat", s.get("seat_id", -1)), -1)
		if seat < 0:
			continue
		_wld_by_seat[seat] = {
			"w": TypedVariant.as_int(s.get("w", 0), 0),
			"l": TypedVariant.as_int(s.get("l", 0), 0),
			"d": TypedVariant.as_int(s.get("d", 0), 0),
		}
		var titles: Array = TypedVariant.as_array(s.get("titles", []))
		if not titles.is_empty():
			_match_titles[seat] = titles.duplicate()
		## Append battle-log lines for remote seats' new titles this round when result known.
		var result: String = str(s.get("result", ""))
		var rival: int = TypedVariant.as_int(s.get("rival", -1), -1)
		var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
		if seat != local_seat and result != "" and result != "—":
			var nick: String = NickCodec.display_short(str(_seat_row_nick(seat)))
			var rival_nick: String = NickCodec.display_short(str(_seat_row_nick(rival))) if rival >= 0 else "?"
			_append_battle_log("%s本回合对%s · %s" % [nick, rival_nick, result])
	if _right_pane_mode == RightPaneMode.RANK:
		_refresh_rank_panel()


func _on_nullsec_match_report_received(report: Dictionary) -> void:
	var n: int = TypedVariant.as_array(report.get("players", [])).size()
	SessionDiagnostics.log(
		"net.match_report",
		"apply players=%d provisional=%d" % [
			n,
			1 if TypedVariant.as_bool(report.get("provisional", false), false) else 0,
		]
	)
	## Host-collected §7 report (every contestant's own titles/summary) supersedes the
	## local-only fallback rows shown the instant combat ended.
	if _settlement_panel and is_instance_valid(_settlement_panel):
		_settlement_panel.show_report(report)
	else:
		## Guest may receive report before panel exists — persist + show.
		NullsecSettlement.save_match_report(report)
		if _settlement_panel == null:
			_settlement_panel = NullsecSettlementPanel.new()
			hud.add_child(_settlement_panel)
		_settlement_panel.show_report(report)


func on_gold_income_float(amount: int, mining_part: int = 0) -> void:
	if amount <= 0:
		return
	var root: Control = hud.get_node_or_null("Root") if hud else null
	if root == null:
		return
	var gold_box: Control = root.get_node_or_null("%s/GoldBox" % _BOTTOM_GOLD_POP) as Control
	if gold_box == null:
		gold_box = root.get_node_or_null("%s/StatsRow/GoldBox" % _SHOP_MID) as Control
	if gold_box:
		var floater: Label = Label.new()
		floater.text = "+%d" % amount
		floater.modulate = Color(1.0, 0.92, 0.35, 1.0)
		floater.z_index = 40
		floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gold_box.add_child(floater)
		floater.position = Vector2(0, -8)
		var tw: Tween = create_tween()
		tw.tween_property(floater, "position:y", -48.0, 0.85).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(floater, "modulate:a", 0.0, 0.85)
		tw.tween_callback(floater.queue_free)
	if mining_part > 0 and board != null:
		_log_mining_ship_incomes()


func _log_mining_ship_incomes() -> void:
	if board == null:
		return
	for s: ShipUnit in board.field_ships(ShipUnit.TEAM_PLAYER):
		if s == null or s.is_destroyed or s.is_unmanned:
			continue
		var sd: Dictionary = DataStore.get_ship(s.ship_id)
		var base_g: int = TypedVariant.as_int(sd.get("mining_gold_per_round", 0), 0)
		if base_g <= 0:
			continue
		var amt: int = base_g * maxi(1, s.star)
		var nm: String = str(sd.get("name", s.ship_id))
		_append_battle_log("矿船 %s +%d" % [nm, amt])

func _on_refresh_pressed() -> void:
	shop.manual_refresh()
	_refresh_shop_ui()
	_refresh_hud_economy_only()


func _restyle_scanner_host_to_side(host: Control, side: float, root: Control) -> void:
	## Keep snapped host rect; only refresh frame/art/caption to match `side`.
	if host == null or root == null or side < 8.0:
		return
	host.custom_minimum_size = Vector2(side, side)
	host.clip_contents = true
	var frame: PanelContainer = host.get_node_or_null("ScannerFrame") as PanelContainer
	if frame == null:
		return
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.custom_minimum_size = Vector2.ZERO
	var cost: int = TypedVariant.as_int(DataStore.economy.get("ship_scanner_cost", 50), 50)
	var inner: VBoxContainer = frame.get_node_or_null("ScannerInner") as VBoxContainer
	if inner == null:
		return
	var btn: Button = inner.get_node_or_null("ScannerBtn") as Button
	if btn != null:
		var cap_h: float = float(UiLayout.px(16, root))
		var art_side: float = maxf(8.0, side - float(UiLayout.margin_px(8, root)) - cap_h)
		_style_image_button_fill(btn, UiAssets.shop_scanner_path(), "高级刷新", cost, art_side, art_side)
		btn.custom_minimum_size = Vector2(0.0, art_side * 0.55)
	var cap: Label = inner.get_node_or_null("ScannerCaption") as Label
	if cap != null:
		cap.text = "高级刷新 %d" % cost


func _ensure_ship_scanner_btn(root: Control, btn_w: int, parent_col: Node = null) -> void:
	if root == null:
		return
	if parent_col == null:
		parent_col = root.get_node_or_null(_SHOP_BAR)
	if parent_col == null:
		parent_col = root.get_node_or_null(_SHOP_META_COL)
	if parent_col == null:
		return
	## Prefer plain Control host (absolute snap square); migrate legacy VBox.
	var host: Control = parent_col.get_node_or_null("ScannerHost") as Control
	if host == null:
		var meta_mid: Node = root.get_node_or_null(_SHOP_META_MID)
		if meta_mid != null:
			host = meta_mid.get_node_or_null("ScannerHost") as Control
			if host == null:
				var esc: Node = meta_mid.get_node_or_null("EquipScanCol")
				if esc != null:
					host = esc.get_node_or_null("ScannerHost") as Control
		if host != null and host.get_parent() != parent_col:
			_reparent_keep_signals(host, parent_col)
	if host == null:
		host = Control.new()
		host.name = "ScannerHost"
		parent_col.add_child(host)
	elif host is VBoxContainer or host is HBoxContainer:
		## Box host fights FULL_RECT frame; flatten to plain Control.
		var flat: Control = Control.new()
		flat.name = "ScannerHost"
		var hp: Node = host.get_parent()
		var hi: int = host.get_index()
		var migrate: Array[Node] = []
		for ch: Node in host.get_children():
			migrate.append(ch)
		for ch2: Node in migrate:
			_reparent_keep_signals(ch2, flat)
		host.name = "ScannerHost_Legacy"
		host.queue_free()
		hp.add_child(flat)
		hp.move_child(flat, hi)
		host = flat
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = true
	host.size_flags_horizontal = 0
	host.size_flags_vertical = 0
	var side: float = float(maxi(btn_w, UiLayout.px(56, root)))
	if _hud_shop_card_side >= 8.0:
		side = clampf(_hud_shop_card_side * 0.85, float(UiLayout.px(48, root)), float(UiLayout.px(100, root)))
	side = clampf(side, float(UiLayout.px(48, root)), float(UiLayout.px(110, root)))
	host.custom_minimum_size = Vector2(side, side)
	var frame: PanelContainer = host.get_node_or_null("ScannerFrame") as PanelContainer
	if frame == null:
		frame = PanelContainer.new()
		frame.name = "ScannerFrame"
		host.add_child(frame)
	_clear_control_abs_layout(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.custom_minimum_size = Vector2.ZERO
	var outer: StyleBoxFlat = StyleBoxFlat.new()
	outer.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	outer.border_color = Color(0.35, 0.62, 0.78, 0.9)
	outer.set_border_width_all(1)
	outer.set_corner_radius_all(4)
	outer.set_content_margin_all(UiLayout.margin_px(2, root))
	frame.add_theme_stylebox_override("panel", outer)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	## Title+price inside frame (not host-external Caption).
	var inner: VBoxContainer = frame.get_node_or_null("ScannerInner") as VBoxContainer
	if inner == null:
		inner = VBoxContainer.new()
		inner.name = "ScannerInner"
		frame.add_child(inner)
	inner.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost: int = TypedVariant.as_int(DataStore.economy.get("ship_scanner_cost", 50), 50)
	var btn: Button = inner.get_node_or_null("ScannerBtn") as Button
	if btn == null:
		btn = frame.get_node_or_null("ScannerBtn") as Button
	if btn == null:
		btn = host.get_node_or_null("ScannerBtn") as Button
	if btn == null:
		btn = parent_col.get_node_or_null("ScannerBtn") as Button
		if btn == null:
			btn = root.get_node_or_null("%s/LeftBtns/ScannerBtn" % _SHOP_LEFT) as Button
	if btn != null and btn.get_parent() != inner:
		_reparent_keep_signals(btn, inner)
	if btn == null:
		btn = Button.new()
		btn.name = "ScannerBtn"
		inner.add_child(btn)
	_clear_control_abs_layout(btn)
	var cap_h: float = float(UiLayout.px(16, root))
	var art_side: float = maxf(8.0, side - float(UiLayout.margin_px(8, root)) - cap_h)
	_style_image_button_fill(btn, UiAssets.shop_scanner_path(), "高级刷新", cost, art_side, art_side)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0.0, art_side * 0.55)
	if not btn.pressed.is_connected(_on_scanner_pressed):
		btn.pressed.connect(_on_scanner_pressed)
	var cap: Label = inner.get_node_or_null("ScannerCaption") as Label
	if cap == null:
		cap = frame.get_node_or_null("ScannerCaption") as Label
	if cap == null:
		cap = host.get_node_or_null("ScannerCaption") as Label
	if cap != null and cap.get_parent() != inner:
		_reparent_keep_signals(cap, inner)
	if cap == null:
		cap = Label.new()
		cap.name = "ScannerCaption"
		inner.add_child(cap)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.text = "高级刷新 %d" % cost
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_END
	UiAssets.apply_label_font(cap, false, UiLayout.font_size(11, root))
	cap.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cap.add_theme_constant_override("outline_size", UiLayout.margin_px(2, root))
	## Drop stray host-level captions left from older layout.
	for ch: Node in host.get_children():
		if ch != frame and str(ch.name).begins_with("ScannerCaption"):
			ch.queue_free()
	inner.move_child(btn, 0)
	inner.move_child(cap, inner.get_child_count() - 1)


func _refresh_scanner_cost_caption(root: Control = null) -> void:
	## Keep 「高级刷新 N」 in sync with economy.json / 全舰船数据调整.
	if root == null and hud != null:
		root = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	var cost: int = TypedVariant.as_int(DataStore.economy.get("ship_scanner_cost", 50), 50)
	var cap: Label = root.get_node_or_null(
		"%s/ScannerFrame/ScannerInner/ScannerCaption" % _SHOP_SCANNER_HOST
	) as Label
	if cap == null:
		cap = root.get_node_or_null("%s/ScannerFrame/ScannerCaption" % _SHOP_SCANNER_HOST) as Label
	if cap == null:
		cap = root.get_node_or_null("%s/ScannerCaption" % _SHOP_SCANNER_HOST) as Label
	if cap:
		cap.text = "高级刷新 %d" % cost
	var btn: Button = root.get_node_or_null(_SHOP_SCANNER) as Button
	if btn == null:
		btn = root.get_node_or_null(
			"LeftCol/LeftInner/LeftContent/ShopBarPanel/ShopBar/ScannerHost/ScannerFrame/ScannerBtn"
		) as Button
	if btn:
		btn.tooltip_text = "高级刷新  %d" % cost


func _on_scanner_pressed() -> void:
	if shop == null or not shop.has_method("try_ship_scanner"):
		return
	if shop.try_ship_scanner():
		_refresh_shop_ui()
		_refresh_hud()


func _on_lock_pressed() -> void:
	## Lock shop removed (ECONOMY_AND_SHOP §3).
	pass

func _on_lock_toggled(_pressed: bool) -> void:
	## Lock shop removed (ECONOMY_AND_SHOP §3).
	pass

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
	## `_grant_exp` emits hud_refresh; while hold-active `_refresh_hud` stays economy-only.
	match_ctrl.buy_exp()
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
	## Old saves may still carry 5 slots — clamp to live economy count (EQUIPMENT.md).
	var cap: int = maxi(1, TypedVariant.as_int(DataStore.economy.get("equipment_shop_slot_count", 4), 4))
	if out.size() > cap:
		out.resize(cap)
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
	_fps_slider.value = (PlayerSettings.instance() as PlayerSettings).target_fps
	_fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_slider.value_changed.connect(_on_match_fps_changed)
	row.add_child(_fps_slider)
	_fps_lbl = Label.new()
	_fps_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_fps_lbl.text = str(int((PlayerSettings.instance() as PlayerSettings).target_fps))
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
	nomodel.button_pressed = (PlayerSettings.instance() as PlayerSettings).no_model_perf_mode
	UiAssets.apply_button_font(nomodel, UiLayout.font_size(16, self))
	nomodel.toggled.connect(func(on: bool) -> void: (PlayerSettings.instance() as PlayerSettings).set_no_model_perf_mode(on))
	box.add_child(nomodel)

	var fx_simple: CheckBox = CheckBox.new()
	fx_simple.text = "装备与武器特效简化"
	fx_simple.tooltip_text = "关闭=正常特效（与预览同套）；开启=色块束/单球加农/直线导弹"
	fx_simple.button_pressed = (PlayerSettings.instance() as PlayerSettings).weapon_fx_simplified
	UiAssets.apply_button_font(fx_simple, UiLayout.font_size(16, self))
	fx_simple.toggled.connect(func(on: bool) -> void: (PlayerSettings.instance() as PlayerSettings).set_weapon_fx_simplified(on))
	box.add_child(fx_simple)

	var breathe: CheckBox = CheckBox.new()
	breathe.text = "镜头呼吸浮动"
	breathe.button_pressed = (PlayerSettings.instance() as PlayerSettings).camera_breathe_enabled
	UiAssets.apply_button_font(breathe, UiLayout.font_size(16, self))
	breathe.toggled.connect(func(on: bool) -> void: (PlayerSettings.instance() as PlayerSettings).set_camera_breathe_enabled(on))
	box.add_child(breathe)

	var hp_vis: CheckBox = CheckBox.new()
	hp_vis.text = "显示血条"
	hp_vis.tooltip_text = "关闭后隐藏盾/甲/结构/电量几何；吨位章与装备格仍显示"
	hp_vis.button_pressed = (PlayerSettings.instance() as PlayerSettings).health_bar_visible
	UiAssets.apply_button_font(hp_vis, UiLayout.font_size(16, self))
	hp_vis.toggled.connect(func(on: bool) -> void: (PlayerSettings.instance() as PlayerSettings).set_health_bar_visible(on))
	box.add_child(hp_vis)

	var hp_row: HBoxContainer = HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var hp_cap: Label = Label.new()
	hp_cap.text = "血量展示"
	UiAssets.apply_label_font(hp_cap, false, UiLayout.font_size(16, self))
	hp_row.add_child(hp_cap)
	var hp_opt: OptionButton = OptionButton.new()
	hp_opt.add_item("环形血量展示", 0)
	hp_opt.add_item("四条血量展示", 1)
	hp_opt.select(1 if PlayerSettings.get_or_null() != null and PlayerSettings.get_or_null().health_bar_style == "bars" else 0)
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

	var ps_audio: PlayerSettings = PlayerSettings.get_or_null()
	var sfx_on_row: HBoxContainer = HBoxContainer.new()
	_sfx_check = CheckBox.new()
	_sfx_check.text = "音效"
	_sfx_check.button_pressed = ps_audio.sfx_enabled if ps_audio else true
	UiAssets.apply_button_font(_sfx_check, UiLayout.font_size(16, self))
	_sfx_check.toggled.connect(_on_match_sfx_toggled)
	sfx_on_row.add_child(_sfx_check)
	box.add_child(sfx_on_row)

	var sfx_vol_row: HBoxContainer = HBoxContainer.new()
	sfx_vol_row.add_theme_constant_override("separation", UiLayout.margin_px(10, self))
	var sfx_cap: Label = Label.new()
	sfx_cap.text = "音效音量"
	UiAssets.apply_label_font(sfx_cap, false, UiLayout.font_size(16, self))
	sfx_vol_row.add_child(sfx_cap)
	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0
	_sfx_slider.max_value = 100
	_sfx_slider.step = 1
	_sfx_slider.value = ps_audio.sfx_volume_pct if ps_audio else 80.0
	_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_slider.value_changed.connect(_on_match_sfx_volume_changed)
	sfx_vol_row.add_child(_sfx_slider)
	_sfx_lbl = Label.new()
	_sfx_lbl.custom_minimum_size = Vector2(UiLayout.px(40, self), 0)
	_sfx_lbl.text = str(int(_sfx_slider.value))
	UiAssets.apply_label_font(_sfx_lbl, false, UiLayout.font_size(16, self))
	sfx_vol_row.add_child(_sfx_lbl)
	box.add_child(sfx_vol_row)

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
	_dev_master_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_master_check, UiLayout.font_size(16, self))
	_dev_master_check.toggled.connect(_on_match_dev_master_toggled)
	box.add_child(_dev_master_check)

	_dev_soften_check = CheckBox.new()
	_dev_soften_check.text = "我方扣血软化（失败惩罚减为 1）"
	_dev_soften_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).player_citadel_soften
	_dev_soften_check.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_soften_check, UiLayout.font_size(16, self))
	_dev_soften_check.toggled.connect(_on_match_dev_soften_toggled)
	box.add_child(_dev_soften_check)

	_dev_economy_check = CheckBox.new()
	_dev_economy_check.text = "人机双倍经济（我方战斗收入×同人机）"
	_dev_economy_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).player_ai_double_economy
	_dev_economy_check.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_economy_check, UiLayout.font_size(16, self))
	_dev_economy_check.toggled.connect(_on_match_dev_economy_toggled)
	box.add_child(_dev_economy_check)

	_dev_enemy_layout_check = CheckBox.new()
	_dev_enemy_layout_check.text = "敌方布局调整许可（暂停时可拖敌方单位）"
	_dev_enemy_layout_check.button_pressed = (PlayerSettings.instance() as PlayerSettings).enemy_layout_adjust
	_dev_enemy_layout_check.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(_dev_enemy_layout_check, UiLayout.font_size(16, self))
	_dev_enemy_layout_check.toggled.connect(_on_match_dev_enemy_layout_toggled)
	box.add_child(_dev_enemy_layout_check)

	var swap_btn: Button = Button.new()
	swap_btn.text = "换边（双方棋子中心对称交换）"
	swap_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	swap_btn.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	UiAssets.apply_button_font(swap_btn, UiLayout.font_size(16, self))
	swap_btn.pressed.connect(_on_match_dev_swap_sides)
	swap_btn.name = "DevSwapSidesBtn"
	box.add_child(swap_btn)

	var ship_data_btn: Button = Button.new()
	ship_data_btn.text = "全舰船装备数据调整（暂停对局）"
	ship_data_btn.custom_minimum_size = Vector2(0, UiLayout.px(40, self))
	ship_data_btn.disabled = not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
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
		_dev_master_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).developer_debug_enabled)
	var master_on: bool = (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled
	if _dev_soften_check:
		_dev_soften_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).player_citadel_soften)
		_dev_soften_check.disabled = not master_on
	if _dev_economy_check:
		_dev_economy_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).player_ai_double_economy)
		_dev_economy_check.disabled = not master_on
	if _dev_enemy_layout_check:
		_dev_enemy_layout_check.set_pressed_no_signal((PlayerSettings.instance() as PlayerSettings).enemy_layout_adjust)
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
	(PlayerSettings.instance() as PlayerSettings).set_developer_debug_enabled(on)
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
	(PlayerSettings.instance() as PlayerSettings).set_player_citadel_soften(on)


func _on_match_dev_economy_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_player_ai_double_economy(on)


func _on_match_dev_enemy_layout_toggled(on: bool) -> void:
	(PlayerSettings.instance() as PlayerSettings).set_enemy_layout_adjust(on)


func _on_match_dev_swap_sides() -> void:
	if not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled:
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
	if not (PlayerSettings.instance() as PlayerSettings).developer_debug_enabled:
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
	## economy.ship_scanner_cost may have changed — refresh 「高级刷新 N」.
	_refresh_hud()
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
	## SEMI_ASYNC §5.3a — flip watch↔authority so the new host resumes CombatResolver tick
	## (stuck units / frozen sim was caused by leaving remote_watch_only ON after promote).
	_apply_remote_watch_only_for_battle()
	if match_ctrl != null and match_ctrl.stage == MatchController.Stage.BATTLE \
			and not match_ctrl.remote_watch_only and _net_battle != null and _net_battle.is_host:
		## Mid-battle promote: board already has units; force a full snap so peers resync.
		## Do NOT re-call on_local_battle_begin — that would duplicate HostSim jobs.
		if _net_battle.has_method("request_force_full_sync"):
			_net_battle.request_force_full_sync()
		_net_jobs_ready_for_titan = true
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", -1), 0)
	if new_host_seat == local_seat:
		show_notice("你已成为新房主 · 继续主持对局（迁移 #%d）" % generation)
		SessionDiagnostics.log("mp.watch_only", "OFF after host_migrate gen=%d" % generation)
		print("[mp.diag] remote_watch_only OFF (promoted host)")
	else:
		show_notice("房主已迁移 · 席位 %d 接手（#%d）" % [new_host_seat + 1, generation])
		if match_ctrl != null and match_ctrl.remote_watch_only:
			print("[mp.diag] remote_watch_only ON (following new host)")


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
		## Eliminated early exit → provisional match_report (MULTIPLAYER_PVP §7.0b).
		_save_provisional_nullsec_report()
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
		_fps_slider.value = (PlayerSettings.instance() as PlayerSettings).target_fps
	if _fps_lbl:
		_fps_lbl.text = str(int((PlayerSettings.instance() as PlayerSettings).target_fps))
	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	var bgm: BgMusic = _BgMusic.instance() as BgMusic
	if _bgm_check and bgm:
		_bgm_check.button_pressed = bgm.enabled
	if _bgm_slider and bgm:
		_bgm_slider.value = bgm.volume_pct
	if _bgm_lbl and bgm:
		_bgm_lbl.text = str(int(bgm.volume_pct))
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if _sfx_check and ps:
		_sfx_check.button_pressed = ps.sfx_enabled
	if _sfx_slider and ps:
		_sfx_slider.value = ps.sfx_volume_pct
	if _sfx_lbl and ps:
		_sfx_lbl.text = str(int(ps.sfx_volume_pct))


func _on_match_fps_changed(v: float) -> void:
	if GameSession.has_method("set_target_fps"):
		(PlayerSettings.instance() as PlayerSettings).set_target_fps(int(v))
	else:
		(PlayerSettings.instance() as PlayerSettings).target_fps = int(v)
		Engine.max_fps = (PlayerSettings.instance() as PlayerSettings).target_fps
		(PlayerSettings.instance() as PlayerSettings).save_settings()
	if _fps_lbl:
		_fps_lbl.text = str((PlayerSettings.instance() as PlayerSettings).target_fps)


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
	if not (PlayerSettings.instance() as PlayerSettings).no_model_perf_mode:
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
		(PlayerSettings.instance() as PlayerSettings).set_health_bar_style(style)
	else:
		GameSession.set("health_bar_style", style)
		if GameSession.has_method("save_settings"):
			(PlayerSettings.instance() as PlayerSettings).save_settings()
	rebuild_all_ship_health_bars()


func _on_match_bgm_volume_changed(v: float) -> void:
	if _bgm_lbl:
		_bgm_lbl.text = str(int(v))
	@warning_ignore("unsafe_method_access")
	@warning_ignore("unsafe_cast")
	var bgm: BgMusic = _BgMusic.instance() as BgMusic
	if bgm:
		bgm.set_volume_pct(v)


func _on_match_sfx_toggled(on: bool) -> void:
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps:
		ps.set_sfx_enabled(on)


func _on_match_sfx_volume_changed(v: float) -> void:
	if _sfx_lbl:
		_sfx_lbl.text = str(int(v))
	var ps: PlayerSettings = PlayerSettings.get_or_null()
	if ps:
		ps.set_sfx_volume_pct(v)


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
	_collapse_left_syn = _collapse_left
	_collapse_left_equip = _collapse_left
	_apply_adaptive_hud_layout()

func _on_collapse_left_equip() -> void:
	## Legacy equip-only toggle — now folds the whole left column (plan J).
	_on_collapse_left()

func _on_collapse_right() -> void:
	_hud_interact_ms = Time.get_ticks_msec()
	_collapse_right = not _collapse_right
	_apply_adaptive_hud_layout()
	_sync_default_camera_to_hud()
	## Remembered unit survives collapse; restore detail body when expanding on DETAIL.
	if not _collapse_right and _right_pane_mode == RightPaneMode.DETAIL:
		_restore_detail_ship_panel()


func _restore_detail_ship_panel() -> bool:
	## UI_AND_SHELL §2.6 — restore last touched unit into DETAIL; empty only if never touched.
	var ship: ShipUnit = null
	if is_instance_valid(_info_ship) and not _info_ship.is_destroyed:
		ship = _info_ship
	elif is_instance_valid(_last_touched_ship) and not _last_touched_ship.is_destroyed:
		ship = _last_touched_ship
	else:
		_info_ship = null
		if not is_instance_valid(_last_touched_ship):
			_last_touched_ship = null
		return false
	_show_ship_info(ship)
	return true

func _on_collapse_bottom() -> void:
	_hud_interact_ms = Time.get_ticks_msec()
	var was_collapsed: bool = _collapse_bottom
	_collapse_bottom = not _collapse_bottom
	## Hide/show bottom strip only — do not re-snap left shop / LevelExp (UI_AND_SHELL §3.1).
	_apply_adaptive_hud_layout(true)
	if was_collapsed and not _collapse_bottom:
		_on_shop_expanded_camera()
	elif not was_collapsed and _collapse_bottom:
		_on_shop_collapsed_camera()
	else:
		_sync_default_camera_to_hud()

func _try_auto_collapse_hud_once() -> void:
	## UI_AND_SHELL §2.5 — whole match: first Battle only.
	if _hud_auto_collapsed_once:
		return
	_hud_auto_collapsed_once = true
	if Time.get_ticks_msec() - _hud_interact_ms < 2000:
		return
	_collapse_left_syn = true
	_collapse_left_equip = true
	_collapse_left = true
	_collapse_right = true
	_collapse_bottom = true
	_cam_pose_before_shop_valid = false
	_cam_pose_before_shop.clear()
	_apply_adaptive_hud_layout()
	_sync_default_camera_to_hud()


func _try_auto_expand_hud_once() -> void:
	## UI_AND_SHELL §2.5 — whole match: GAME_END only.
	if _hud_auto_expanded_once:
		return
	_hud_auto_expanded_once = true
	if Time.get_ticks_msec() - _hud_interact_ms < 2000:
		return
	_collapse_left_syn = false
	_collapse_left_equip = false
	_collapse_left = false
	_collapse_right = false
	_collapse_bottom = false
	_apply_adaptive_hud_layout()
	_sync_default_camera_to_hud()


func _on_stage_changed_ui(stage: int) -> void:
	_apply_collapse_arrow_frames()
	var stage_label: String = "准备" if stage == MatchController.Stage.PREPARE else ("战斗" if stage == MatchController.Stage.BATTLE else "结束")
	_append_battle_log("进入%s阶段" % stage_label)
	if stage == MatchController.Stage.BATTLE:
		## SEMI_ASYNC §4.5 — never carry conditional wall draw / auto 4× into a new Battle.
		if _nullsec_speed:
			_nullsec_speed.reset_round()
			_apply_resolved_speed()
		_try_auto_collapse_hud_once()
		_flash_enemy_locks_on_battle_start()
		## Force full Prepare fleet snapshot once before HostSim battle.
		if GameSession.pending_mode == "nullsec" and _nullsec_pve and not _nullsec_local_is_pve():
			_push_local_prepare_fleet()
			var rival_pre: int = _nullsec_rival_seat(TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0))
			var net_pre: NullsecNetSession = _nullsec_net_session()
			if net_pre != null and rival_pre >= 0 and not _seat_is_ai(rival_pre):
				net_pre.request_prepare_fleet_snapshot(rival_pre)
		## PVP: guest hop already at Prepare (§4.1). Battle only starts combat.
		if GameSession.pending_mode == "nullsec" and _nullsec_pve and not _nullsec_local_is_pve():
			_apply_remote_watch_only_for_battle()
			if _net_battle:
				_net_jobs_ready_for_titan = false
				_net_battle.on_local_battle_begin()
			_begin_combat_eval_if_human_pvp()
		elif GameSession.pending_mode == "nullsec" and _nullsec_pve and _nullsec_local_is_pve():
			## SEMI_ASYNC §3.2 — defending seat sims PVE locally (creeps). Never host-watch.
			_apply_remote_watch_only_for_battle()
			if _net_battle:
				## Only enqueue lightweight reports for ai_player seats (no local client).
				_net_jobs_ready_for_titan = false
				_net_battle.on_local_battle_begin()
			_combat_eval_active = false
			SessionDiagnostics.log("mp.pve_local", "creep battle local sim")
		else:
			if match_ctrl:
				match_ctrl.remote_watch_only = false
			_begin_combat_eval_if_human_pvp()
		## PVE local also tracks rank stats.
		if GameSession.pending_mode == "nullsec" and _nullsec_pve and _nullsec_local_is_pve():
			if _combat_eval == null:
				_combat_eval = CombatEvalTracker.new()
			_combat_eval.begin_round(board)
			_combat_eval_active = true
		if not _camera_manual_pose():
			_sync_default_camera_to_hud()
			## Keep slot grid until camera settles on HUD default view.
			_show_slot_markers_now()
			_pending_hide_slot_markers = true
		else:
			_hide_slot_markers_now()
	# 回合结束：战斗 -> 准备；HUD 不在此处自动展开（整局仅 GAME_END 展开一次）。
	# 镜头锁当前 HUD 默认（底栏/右栏收展组合）。
	# 负安局若要播末日/击毁，先把 HUD/镜头转场压住，等演出结束再走 prepare 展示。
	if _last_match_stage == MatchController.Stage.BATTLE and stage == MatchController.Stage.PREPARE:
		## SEMI_ASYNC §3.1a — PVP watch peers only. PVE stays local (§3.2); sync via battle_done.
		var net_end: NullsecNetSession = _nullsec_net_session()
		var pve_local_end: bool = _nullsec_pve != null and _nullsec_pve.is_pve_task()
		if (
			not pve_local_end
			and net_end != null
			and net_end.is_host
			and net_end.needs_stage_barrier()
			and match_ctrl
		):
			var hs: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
			net_end.broadcast_battle_ended(str(match_ctrl.last_round_result), hs, "host_complete")
		elif pve_local_end and net_end != null and net_end.is_host:
			SessionDiagnostics.log("mp.battle_ended_skip", "pve_local_no_broadcast")
		if GameSession.pending_mode == "nullsec":
			_apply_nullsec_prepare_stage_gates()
			_nullsec_prepare_ui_pending = true
			_nullsec_after_battle_into_prepare()
			if not _doomsday_busy and not _titan_kill_busy:
				_apply_nullsec_prepare_presentation()
		else:
			_show_slot_markers_now()
			if not _camera_manual_pose():
				_cam_headup_phase = 0
				_cam_headup_t = 0.0
				_cam_headup_offset_deg = 0.0
				_sync_default_camera_to_hud()
	elif stage == MatchController.Stage.GAME_END:
		_try_auto_expand_hud_once()
	elif not _camera_manual_pose():
		_trigger_camera_headup("stage_change")
	_last_match_stage = stage
	_refresh_hud()
	SessionDiagnostics.log("stage", stage_label)

func _apply_nullsec_prepare_presentation() -> void:
	if not _nullsec_prepare_ui_pending:
		return
	_nullsec_prepare_ui_pending = false
	## Do not auto-expand HUD here — only GAME_END may try expand once.
	_show_slot_markers_now()
	if not _camera_manual_pose():
		_cam_headup_phase = 0
		_cam_headup_t = 0.0
		_cam_headup_offset_deg = 0.0
		_sync_default_camera_to_hud()


## SEMI_ASYNC §3.1a — non-host peers on **PVP** barrier tables only watch authority snaps.
## PVE (creep / sleeper) rounds are always local on the defending seat (§3.2) — never watch-only.
func _apply_remote_watch_only_for_battle() -> void:
	if match_ctrl == null:
		return
	var net: NullsecNetSession = _nullsec_net_session()
	var pve_local: bool = _nullsec_pve != null and _nullsec_pve.is_pve_task()
	match_ctrl.remote_watch_only = (
		not pve_local and net != null and net.needs_stage_barrier() and not net.is_host
	)
	if match_ctrl.remote_watch_only:
		## Watch peers do not bookkeep titles — host eval is authoritative enough for UI.
		_combat_eval_active = false
		if _net_battle != null:
			_net_battle.watch_only_apply = true
		if combat != null:
			combat.authority_only = true
		SessionDiagnostics.log("mp.watch_only", "guest")
		print("[mp.diag] remote_watch_only ON")
	else:
		if _net_battle != null:
			_net_battle.watch_only_apply = false
		if combat != null:
			combat.authority_only = false
		if pve_local:
			SessionDiagnostics.log("mp.watch_only", "OFF pve_local")
			print("[mp.diag] remote_watch_only OFF (PVE local)")


## MULTIPLAYER_PVP §7.1 — only real human↔human PVP tables earn titles; PVE / AI-rival
## rounds never start the tracker (kept inert to avoid wasted per-hit bookkeeping).
func notify_cyno_success(team_id: int) -> void:
	if _combat_eval_active and _combat_eval != null:
		_combat_eval.on_cyno_success(team_id)


func note_cap_war_stat(source_id: int, amount: float) -> void:
	if not _combat_eval_active or _combat_eval == null:
		return
	if _combat_eval.has_method("on_cap_war"):
		_combat_eval.on_cap_war(source_id, amount)


func _begin_combat_eval_if_human_pvp() -> void:
	## Always track per-ship dmg/heal for HUD rank; titles still require human rival.
	_combat_eval_active = false
	if match_ctrl != null and match_ctrl.remote_watch_only:
		return
	if _combat_eval == null:
		_combat_eval = CombatEvalTracker.new()
	_combat_eval.begin_round(board)
	_combat_eval_active = true
	var local_seat: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
	var rival: int = _nullsec_rival_seat(local_seat)
	if rival < 0 or _seat_is_ai(rival):
		return
	if _match_eval == null:
		_match_eval = MatchEvalTracker.new()
	_match_eval.reset(local_seat)
	_match_eval.note_prepare_board(board)
	_match_eval_gold_at_round = TypedVariant.as_int(match_ctrl.player_gold_earned, 0) if match_ctrl else 0
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
			## Non-lance losses for 小兵先行 / 护犊狂魔 (lance path already notes via mixed_lance).
			if _match_eval != null and str(payload.get("via", "")) != "mixed_lance":
				_match_eval.note_ship_lost(tgt, src, false)
	elif ch == "combat.heal":
		var healer_id: int = TypedVariant.as_int(payload.get("source_id", payload.get("healer_id", 0)), 0)
		_combat_eval.on_heal(TypedVariant.as_float(result.get("applied", 0.0), 0.0), healer_id)
	elif ch == "combat.cap" or ch == "combat.energy":
		var cap_amt: float = absf(TypedVariant.as_float(result.get("applied", result.get("amount", 0.0)), 0.0))
		var cap_src: int = TypedVariant.as_int(payload.get("source_id", 0), 0)
		if cap_amt > 0.0 and cap_src != 0 and _combat_eval.has_method("on_cap_war"):
			_combat_eval.on_cap_war(cap_src, cap_amt)

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

func note_match_lance_fire(ship: ShipUnit, board_ref: BoardController) -> void:
	if not _combat_eval_active or _match_eval == null:
		return
	_match_eval.note_lance_fire_start(board_ref if board_ref else board, ship)


func note_match_lance_hit(src: ShipUnit, tgt: ShipUnit, dealt: float, destroyed: bool) -> void:
	if not _combat_eval_active or _match_eval == null:
		return
	_match_eval.note_lance_hit(src, tgt, dealt)
	if destroyed:
		_match_eval.note_ship_lost(tgt, src, true)


## Merge this round's §7.1 titles into the running per-seat tally and log them.
func _finalize_combat_eval(result: String, local_seat: int, rival_seat: int) -> void:
	if not _combat_eval_active or _combat_eval == null:
		SessionDiagnostics.log("eval.skip", "reason=inactive_or_null")
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
	if _match_eval != null:
		var gold_now: int = TypedVariant.as_int(match_ctrl.player_gold_earned, 0) if match_ctrl else 0
		var round_gold: int = maxi(0, gold_now - _match_eval_gold_at_round)
		var extra: Array = _match_eval.finalize_local(round_gold, result == "win")
		for name_v: Variant in extra:
			titles.append({"seat_id": local_seat, "title": str(name_v)})
		if _note_fifth_persona(result, local_seat, rival_seat):
			titles.append({"seat_id": local_seat, "title": "第五人格"})
	## Cache layout for 神之一手 next round.
	_cache_layout_after_round(result, local_seat)
	_eval_scout_vs_rival = 0
	_eval_sold_first_this_prepare = false
	_eval_bought_capital_this_prepare = false
	SessionDiagnostics.log(
		"eval.finalize",
		"result=%s seat=%d rival=%d titles=%d" % [result, local_seat, rival_seat, titles.size()]
	)
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


func _count_human_contestants() -> int:
	var n: int = 0
	for s_v: Variant in _speed_vote_seats_snapshot():
		var s: Dictionary = TypedVariant.as_dict(s_v)
		if not TypedVariant.as_bool(s.get("occupied", false), false):
			continue
		if TypedVariant.as_bool(s.get("is_ai", false), false):
			continue
		if NullsecNetSession.is_spectate_race(str(s.get("titan_race", ""))):
			continue
		if not NullsecNetSession.is_player_race(str(s.get("titan_race", ""))):
			continue
		n += 1
	return n


## Returns true when 第五人格 should be awarded this round (streak clears after award).
func _note_fifth_persona(result: String, _local_seat: int, rival_seat: int) -> bool:
	if _count_human_contestants() != 5:
		_fifth_opponents.clear()
		return false
	if result != "win" or rival_seat < 0:
		_fifth_opponents.clear()
		return false
	if _fifth_opponents.has(rival_seat):
		_fifth_opponents.clear()
		_fifth_opponents.append(rival_seat)
		return false
	_fifth_opponents.append(rival_seat)
	if _fifth_opponents.size() < 4:
		return false
	_fifth_opponents.clear()
	return true


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
	## Enter next Prepare after settle; creep lock waits for Prepare→Battle.
	if _titan_kill_busy or _doomsday_busy:
		_nullsec_prepare_pending = true
		## Doomsday/kill hold must not permanently drop combat_eval finalize.
		if _combat_eval_active and _pending_combat_eval_finalize.is_empty() and match_ctrl:
			var ls_busy: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
			_pending_combat_eval_finalize = {
				"result": str(match_ctrl.last_round_result),
				"local_seat": ls_busy,
				"rival_seat": _nullsec_rival_seat(ls_busy),
			}
			SessionDiagnostics.log("eval.skip", "reason=doomsday_or_kill_busy")
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
				## Stash eval so titan gate cannot permanently skip finalize.
				if _combat_eval_active:
					var ls0: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
					_pending_combat_eval_finalize = {
						"result": result,
						"local_seat": ls0,
						"rival_seat": _nullsec_rival_seat(ls0),
					}
					SessionDiagnostics.log("eval.skip", "reason=titan_jobs_pending")
				return
			if _net_battle and _net_battle.is_host:
				_net_battle.take_round_reports()
			if not _pending_combat_eval_finalize.is_empty():
				var pend: Dictionary = _pending_combat_eval_finalize
				_pending_combat_eval_finalize = {}
				## Re-arm active so finalize runs after a jobs/doomsday hold.
				if not _combat_eval_active and _combat_eval != null:
					_combat_eval_active = true
				_finalize_combat_eval(
					str(pend.get("result", result)),
					TypedVariant.as_int(pend.get("local_seat", 0), 0),
					TypedVariant.as_int(pend.get("rival_seat", -1), -1)
				)
			elif _combat_eval_active:
				var local_seat_eval: int = TypedVariant.as_int(GameSession.pending_nullsec.get("local_seat", 0), 0)
				_finalize_combat_eval(result, local_seat_eval, _nullsec_rival_seat(local_seat_eval))
			_submit_seat_round_summary_if_net(result)
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
	## Alive ≤ 1 after kill/doomsday FX → settlement, never open another Prepare (§3.3).
	if _try_nullsec_end_if_alive_gate():
		return
	_apply_nullsec_prepare_presentation()
	if _nullsec_pve and match_ctrl:
		_nullsec_advance_last_rivals_after_round()
		_nullsec_pick_next_task()
	## PVE prepare: clear field + open shop (creeps spawn at battle lock).
	## Includes odd-player bye on a global PVP round (MATCH_FLOW §5.2).
	if _nullsec_local_is_pve():
		_nullsec_pvp_guest = false
		_set_rival_berth_visible(false)
		_restore_local_home_skybox()
		_nullsec_on_prepare_begin()
	elif _nullsec_pve:
		## PVP prepare: roll guest home; guest hop + CapitalJumpFx at Prepare start (§4.1).
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
	_nullsec_guest_hop_done = false
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
			## Switch sky immediately so Prepare happens on guest field; FX after fleets ready.
			var region: String = _seat_region(rival)
			if region != "":
				apply_region_skybox(region)
			_nullsec_watch_seat = rival
			_refresh_region_label()
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
	_rival_fleet_synced = false
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
	## Induction land flash after fleets are on the board (Prepare start, §4.1).
	if not lowsec and rival >= 0:
		_nullsec_pvp_prepare_guest_hop()


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
	_rival_fleet_synced = true
	_apply_rival_prepare_fleet(ships)
	if empty_recover and _nullsec_human_rival_fleet_ready():
		match_ctrl.resume_combat_after_empty_fleet()
	else:
		_try_flush_pending_enter_battle()


func _apply_rival_prepare_fleet(ships: Array) -> void:
	if board == null:
		return
	_applying_rival_fleet = true
	_rival_fleet_queue.clear()
	for s: ShipUnit in board.all_ships().duplicate():
		if s == null or not is_instance_valid(s) or s.is_unmanned:
			continue
		if TypedVariant.as_int(s.team_id, 0) == ShipUnit.TEAM_AI:
			board.remove_ship_node(s)
	for entry_v: Variant in ships:
		_rival_fleet_queue.append(TypedVariant.as_dict(entry_v))
	_rival_fleet_spawned = 0
	_rival_fleet_before = board.count_alive_field(ShipUnit.TEAM_AI)
	if not is_processing():
		set_process(true)
	## Kick first batch this frame.
	_process_rival_fleet_queue()


func _process_rival_fleet_queue() -> void:
	if board == null:
		_rival_fleet_queue.clear()
		_applying_rival_fleet = false
		return
	const K: int = 3
	var n: int = 0
	while n < K and not _rival_fleet_queue.is_empty():
		var entry: Dictionary = TypedVariant.as_dict(_rival_fleet_queue.pop_front())
		var sid: int = TypedVariant.as_int(entry.get("ship_id", 0), 0)
		if sid <= 0:
			continue
		var star: int = maxi(1, TypedVariant.as_int(entry.get("star", 1), 1))
		var st: String = str(entry.get("slot_type", "field"))
		if st != "hangar" and st != "field":
			st = "field"
		var x: int = TypedVariant.as_int(entry.get("x", 0), 0)
		var z: int = TypedVariant.as_int(entry.get("z", 0), 0)
		var sender_side: int = TypedVariant.as_int(entry.get("side", -1), -1)
		if sender_side < 0:
			var sd: Dictionary = DataStore.get_ship(sid)
			if TypedVariant.as_bool(sd.get("deploy_enemy_half_only", false), false):
				sender_side = ShipUnit.TEAM_AI
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
			## Defer heavy mesh for AI fleet to next frames when supported.
			if ship.has_method("defer_mesh_ensure"):
				ship.call("defer_mesh_ensure")
		_rival_fleet_spawned += 1
		n += 1
	if _rival_fleet_queue.is_empty():
		board.recalculate_fetters(ShipUnit.TEAM_AI)
		_applying_rival_fleet = false
		print("[mp.diag] fleet_apply done before=%d spawned=%d field_ai=%d" % [
			_rival_fleet_before, _rival_fleet_spawned, board.count_alive_field(ShipUnit.TEAM_AI)
		])
		SessionDiagnostics.log(
			"mp.fleet_apply",
			"spawned=%d field_ai=%d" % [_rival_fleet_spawned, board.count_alive_field(ShipUnit.TEAM_AI)]
		)
		_try_flush_pending_enter_battle()
		_refresh_hud()


func _nullsec_pvp_prepare_guest_hop() -> void:
	## Prepare: induction flash after fleets ready. Sky already switched for guest above.
	if _nullsec_guest_hop_done:
		return
	_nullsec_pvp_battle_teleport()
	_nullsec_guest_hop_done = true


func _nullsec_pvp_battle_teleport() -> void:
	## Guest/home induction land flash at Prepare (§4.1). Not mid-match cyno capital entry.
	if _nullsec_pve and _nullsec_pve.always_pvp:
		return
	var land_team: int = ShipUnit.TEAM_PLAYER if _nullsec_pvp_guest else ShipUnit.TEAM_AI
	if _nullsec_pvp_guest:
		show_notice("客场作战 · 诱导落位 · 准备")
	else:
		show_notice("主场迎战 · 对手诱导落位 · 准备")
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
func _style_collapse_texture_btn(btn: BaseButton, collapsed: bool, axis: String) -> void:
	if btn == null:
		return
	var tex: Texture2D = UiAssets.hud_icon(UiAssets.ICON_PANEL_COLLAPSE)
	## UI_ICONS §9 — unified edge icon side (former ×4 × ⅔).
	var side: float = UiLayout.hud_edge_icon_px(btn)
	btn.custom_minimum_size = Vector2(side, side)
	## Left chrome: flush begin (toward panel); right chrome: flush end.
	if axis == "right":
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	elif axis == "left":
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	## Never rotate the button itself (clipping / hit-box issues); rotate ArrowHost.
	btn.rotation_degrees = 0.0
	btn.pivot_offset = Vector2.ZERO
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	if btn is TextureButton:
		@warning_ignore("unsafe_cast")
		var tb: TextureButton = btn as TextureButton
		tb.texture_normal = null
		tb.texture_pressed = null
		tb.texture_hover = null
		tb.ignore_texture_size = true
	elif btn is Button:
		@warning_ignore("unsafe_cast")
		var b: Button = btn as Button
		b.icon = null
		b.text = ""
		b.flat = true
		b.add_theme_stylebox_override("normal", empty)
		b.add_theme_stylebox_override("pressed", empty)
		b.add_theme_stylebox_override("hover", empty)
		b.add_theme_stylebox_override("focus", empty)
		b.add_theme_stylebox_override("disabled", empty)
	@warning_ignore("unsafe_cast")
	var host: Control = btn.get_node_or_null("ArrowHost") as Control
	if host == null:
		host = Control.new()
		host.name = "ArrowHost"
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(host)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.position = Vector2.ZERO
	host.size = Vector2(side, side)
	host.custom_minimum_size = Vector2(side, side)
	host.pivot_offset = Vector2(side * 0.5, side * 0.5)
	## Outer frame around arrow (does not rotate with whole button).
	@warning_ignore("unsafe_cast")
	var frame: Panel = host.get_node_or_null("ArrowFrame") as Panel
	if frame == null:
		frame = Panel.new()
		frame.name = "ArrowFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(frame)
		host.move_child(frame, 0)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.55)
	sb.border_color = Color(0.75, 0.82, 0.9, 0.85)
	sb.set_border_width_all(maxi(1, int(roundf(side * 0.06))))
	sb.set_corner_radius_all(maxi(2, int(roundf(side * 0.12))))
	frame.add_theme_stylebox_override("panel", sb)
	@warning_ignore("unsafe_cast")
	var icon: TextureRect = host.get_node_or_null("ArrowIcon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "ArrowIcon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(icon)
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2.ZERO
	icon.size = Vector2(side, side)
	icon.custom_minimum_size = Vector2(side, side)
	## Icon art points right at 0°. Expanded → collapse direction; collapsed → +180°.
	var rot: float = 0.0
	if axis == "left":
		rot = 0.0 if collapsed else 180.0
	elif axis == "right":
		rot = 180.0 if collapsed else 0.0
	elif axis == "bottom":
		rot = 270.0 if collapsed else 90.0
	host.rotation_degrees = rot
	_apply_collapse_arrow_frame_on(frame)


func _is_first_prepare_arrow_frame() -> bool:
	if match_ctrl == null:
		return false
	return match_ctrl.stage == MatchController.Stage.PREPARE and match_ctrl.battle_game_stage_count == 0


func _collapse_arrow_frame_pulse_alpha() -> float:
	var t: float = float(Time.get_ticks_msec()) * 0.001
	var wave: float = 0.5 + 0.5 * sin(t * TAU / _ARROW_FRAME_PULSE_S)
	return 0.35 + 0.65 * wave


func _apply_collapse_arrow_frame_on(frame: Panel) -> void:
	if frame == null:
		return
	var show_frame: bool = _is_first_prepare_arrow_frame()
	frame.visible = show_frame
	if show_frame:
		var a: float = _collapse_arrow_frame_pulse_alpha()
		frame.modulate = Color(1.0, 1.0, 1.0, a)
	else:
		frame.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _apply_collapse_arrow_frames(root: Control = null) -> void:
	if root == null and hud != null:
		@warning_ignore("unsafe_cast")
		root = hud.get_node_or_null("Root") as Control
	if root == null:
		return
	for path: String in [
			"LeftEdgeChrome/CollapseLeftBtn/ArrowHost/ArrowFrame",
			"RightEdgeChrome/RightEdgeInner/CollapseRightBtn/ArrowHost/ArrowFrame",
			"BottomEdgeChrome/CollapseBottomBtn/ArrowHost/ArrowFrame"]:
		@warning_ignore("unsafe_cast")
		var fr: Panel = root.get_node_or_null(path) as Panel
		_apply_collapse_arrow_frame_on(fr)


func _tick_collapse_arrow_frame_pulse() -> void:
	if not _is_first_prepare_arrow_frame():
		return
	_apply_collapse_arrow_frames()


func _as_base_button(n: Node) -> BaseButton:
	if n == null or not (n is BaseButton):
		return null
	@warning_ignore("unsafe_cast")
	return n as BaseButton


func _as_panel(n: Node) -> PanelContainer:
	if n == null or not (n is PanelContainer):
		return null
	@warning_ignore("unsafe_cast")
	return n as PanelContainer


func _as_vbox(n: Node) -> VBoxContainer:
	if n == null or not (n is VBoxContainer):
		return null
	@warning_ignore("unsafe_cast")
	return n as VBoxContainer


func _as_grid(n: Node) -> GridContainer:
	if n == null or not (n is GridContainer):
		return null
	@warning_ignore("unsafe_cast")
	return n as GridContainer


func _as_tex_btn(n: Node) -> TextureButton:
	if n == null or not (n is TextureButton):
		return null
	@warning_ignore("unsafe_cast")
	return n as TextureButton


func _style_collapse_arrow_buttons(root: Control) -> void:
	if root == null:
		return
	_style_collapse_texture_btn(_as_base_button(root.get_node_or_null("LeftEdgeChrome/CollapseLeftBtn")), _collapse_left, "left")
	## EquipEdgeChrome retired under plan J (single left collapse).
	var cle_style: BaseButton = _as_base_button(root.get_node_or_null("EquipEdgeChrome/CollapseLeftEquipBtn"))
	if cle_style:
		cle_style.visible = false
		cle_style.disabled = true
	_style_collapse_texture_btn(_as_base_button(root.get_node_or_null("RightEdgeChrome/RightEdgeInner/CollapseRightBtn")), _collapse_right, "right")
	_style_collapse_texture_btn(_as_base_button(root.get_node_or_null("BottomEdgeChrome/CollapseBottomBtn")), _collapse_bottom, "bottom")
	_apply_collapse_arrow_frames(root)


func _make_edge_chrome(root: Control, chrome_name: String) -> PanelContainer:
	var chrome: PanelContainer = _as_panel(root.get_node_or_null(chrome_name))
	if chrome != null:
		return chrome
	chrome = PanelContainer.new()
	chrome.name = chrome_name
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	chrome.add_theme_stylebox_override("panel", empty)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chrome)
	return chrome


func _reparent_keep_signals(node: Node, new_parent: Node) -> void:
	if node == null or new_parent == null:
		return
	if node.get_parent() == new_parent:
		return
	var p: Node = node.get_parent()
	if p != null:
		p.remove_child(node)
	new_parent.add_child(node)


func _ensure_equip_col(root: Control = null) -> void:
	## Plan J: inventory lives under Shop MetaRow — keep as alias to left-shop ensure.
	_ensure_left_shop_layout(root)


func _ensure_hud_edge_chrome(root: Control) -> void:
	if root == null:
		return
	_ensure_left_shop_layout(root)
	## Left column collapse — right edge of LeftCol (shop+fetter).
	var left_chrome: PanelContainer = _make_edge_chrome(root, "LeftEdgeChrome")
	left_chrome.z_index = 40
	var cl: BaseButton = _as_base_button(root.get_node_or_null("LeftEdgeChrome/CollapseLeftBtn"))
	var leftover_inner_cl: BaseButton = _as_base_button(root.get_node_or_null("LeftCol/LeftInner/CollapseLeftBtn"))
	if cl == null:
		cl = leftover_inner_cl
		leftover_inner_cl = null
	if cl == null:
		var tb: TextureButton = TextureButton.new()
		tb.name = "CollapseLeftBtn"
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.mouse_filter = Control.MOUSE_FILTER_STOP
		tb.pressed.connect(_on_collapse_left)
		left_chrome.add_child(tb)
		cl = tb
	if cl != null:
		_reparent_keep_signals(cl, left_chrome)
		cl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		cl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cl.tooltip_text = "收起/展开羁绊"
		if not cl.pressed.is_connected(_on_collapse_left):
			cl.pressed.connect(_on_collapse_left)
	if leftover_inner_cl != null and leftover_inner_cl != cl:
		var p_left: Node = leftover_inner_cl.get_parent()
		if p_left:
			p_left.remove_child(leftover_inner_cl)
		leftover_inner_cl.queue_free()
	## Hide legacy equip-only edge chrome (plan J: one left button).
	var equip_chrome: PanelContainer = _make_edge_chrome(root, "EquipEdgeChrome")
	equip_chrome.visible = false
	equip_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cle: BaseButton = _as_base_button(root.get_node_or_null("EquipEdgeChrome/CollapseLeftEquipBtn"))
	if cle != null:
		cle.visible = false
		cle.disabled = true
	## Right: collapse + three mode buttons in one transparent column on left edge.
	var right_chrome: PanelContainer = _make_edge_chrome(root, "RightEdgeChrome")
	var right_box: VBoxContainer = _as_vbox(right_chrome.get_node_or_null("RightEdgeInner"))
	if right_box == null:
		right_box = VBoxContainer.new()
		right_box.name = "RightEdgeInner"
		right_box.alignment = BoxContainer.ALIGNMENT_CENTER
		right_box.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right_chrome.add_child(right_box)
	right_box.alignment = BoxContainer.ALIGNMENT_CENTER
	right_box.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
	right_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cr: BaseButton = _as_base_button(root.get_node_or_null("RightEdgeChrome/RightEdgeInner/CollapseRightBtn"))
	if cr == null:
		cr = _as_base_button(root.get_node_or_null("RightCol/RightInner/CollapseRightBtn"))
	if cr != null:
		_reparent_keep_signals(cr, right_box)
		## Flush to panel (right edge of chrome strip).
		cr.size_flags_horizontal = Control.SIZE_SHRINK_END
	var mode_col: VBoxContainer = _as_vbox(right_box.get_node_or_null("RightModeBtns"))
	if mode_col == null:
		mode_col = VBoxContainer.new()
		mode_col.name = "RightModeBtns"
		mode_col.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		mode_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right_box.add_child(mode_col)
	mode_col.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
	mode_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	var edge_side: float = UiLayout.hud_edge_icon_px(root)
	var specs: Array = [
		["DetailBtn", UiAssets.ICON_SHIP_DETAIL, "舰船详情", RightPaneMode.DETAIL],
		["LogBtn", UiAssets.ICON_BATTLE_LOG, "战斗日志", RightPaneMode.LOG],
		["RankBtn", UiAssets.ICON_COMBAT_RANK, "排行榜", RightPaneMode.RANK],
	]
	for spec: Variant in specs:
		@warning_ignore("unsafe_cast")
		var s: Array = spec as Array
		var nm: String = str(s[0])
		var existing: TextureButton = _as_tex_btn(mode_col.get_node_or_null(nm))
		if existing == null:
			var old_box: Node = root.get_node_or_null("RightCol/RightInner/RightModeBtns")
			if old_box != null:
				existing = _as_tex_btn(old_box.get_node_or_null(nm))
		if existing == null:
			var tb2: TextureButton = TextureButton.new()
			tb2.name = nm
			tb2.texture_normal = UiAssets.hud_icon(str(s[1]))
			tb2.tooltip_text = str(s[2])
			tb2.ignore_texture_size = true
			tb2.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			tb2.custom_minimum_size = Vector2(edge_side, edge_side)
			tb2.size_flags_horizontal = Control.SIZE_SHRINK_END
			var mode: int = TypedVariant.as_int(s[3], RightPaneMode.DETAIL)
			tb2.pressed.connect(func() -> void: _set_right_pane_mode(mode))
			mode_col.add_child(tb2)
		else:
			_reparent_keep_signals(existing, mode_col)
			existing.texture_normal = UiAssets.hud_icon(str(s[1]))
			existing.ignore_texture_size = true
			existing.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			existing.custom_minimum_size = Vector2(edge_side, edge_side)
			existing.size_flags_horizontal = Control.SIZE_SHRINK_END
	## Drop obsolete mode host if emptied.
	var stale_modes: Node = root.get_node_or_null("RightCol/RightInner/RightModeBtns")
	if stale_modes != null and stale_modes.get_child_count() == 0:
		stale_modes.queue_free()
	## Collapsed right: only collapse arrow — hide mode trio (UI_AND_SHELL §3.4).
	mode_col.visible = not _collapse_right
	## Bottom shop collapse — above Shop top edge, centered.
	var bottom_chrome: PanelContainer = _make_edge_chrome(root, "BottomEdgeChrome")
	bottom_chrome.z_index = 40
	var cb: BaseButton = _as_base_button(root.get_node_or_null("BottomEdgeChrome/CollapseBottomBtn"))
	var leftover_shop_cb: BaseButton = _as_base_button(root.get_node_or_null("Shop/ShopCol/CollapseBottomBtn"))
	if cb == null:
		cb = leftover_shop_cb
		leftover_shop_cb = null
	if cb == null:
		var tb_bot: TextureButton = TextureButton.new()
		tb_bot.name = "CollapseBottomBtn"
		tb_bot.ignore_texture_size = true
		tb_bot.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb_bot.mouse_filter = Control.MOUSE_FILTER_STOP
		tb_bot.pressed.connect(_on_collapse_bottom)
		bottom_chrome.add_child(tb_bot)
		cb = tb_bot
	if cb != null:
		_reparent_keep_signals(cb, bottom_chrome)
		cb.visible = true
		cb.mouse_filter = Control.MOUSE_FILTER_STOP
		cb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.tooltip_text = "收起/展开底栏"
		if not cb.pressed.is_connected(_on_collapse_bottom):
			cb.pressed.connect(_on_collapse_bottom)
	if leftover_shop_cb != null and leftover_shop_cb != cb:
		var p_bot: Node = leftover_shop_cb.get_parent()
		if p_bot:
			p_bot.remove_child(leftover_shop_cb)
		leftover_shop_cb.queue_free()


func _ensure_left_equip_collapse_btn(root: Control) -> void:
	## Kept for callers; edge chrome owns the button now.
	_ensure_hud_edge_chrome(root)


func _ensure_hud_mode_buttons(root: Control) -> void:
	## Kept for callers; edge chrome owns mode buttons now.
	_ensure_hud_edge_chrome(root)


func _set_right_pane_mode(mode: int) -> void:
	_hud_interact_ms = Time.get_ticks_msec()
	_right_pane_mode = mode
	if _collapse_right:
		_collapse_right = false
	_apply_adaptive_hud_layout()
	if mode == RightPaneMode.DETAIL:
		_restore_detail_ship_panel()
	elif mode == RightPaneMode.RANK:
		_refresh_rank_panel()


func _apply_right_pane_mode(root: Control) -> void:
	if root == null:
		return
	@warning_ignore("unsafe_cast")
	var info: Control = root.get_node_or_null(_INFO_PANEL) as Control
	@warning_ignore("unsafe_cast")
	var blog: Control = root.get_node_or_null("RightCol/RightInner/RightContent/BattleLog") as Control
	@warning_ignore("unsafe_cast")
	var rank: Control = root.get_node_or_null("RightCol/RightInner/RightContent/RankPanel") as Control
	if info:
		info.visible = (_right_pane_mode == RightPaneMode.DETAIL) and not _collapse_right
		info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if blog:
		blog.visible = (_right_pane_mode == RightPaneMode.LOG) and not _collapse_right
		blog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if rank:
		rank.visible = (_right_pane_mode == RightPaneMode.RANK) and not _collapse_right
		rank.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _right_pane_mode == RightPaneMode.RANK and not _collapse_right:
		_refresh_rank_panel()


func _ensure_rank_panel(root: Control) -> void:
	if root == null:
		return
	var content: Control = root.get_node_or_null("RightCol/RightInner/RightContent") as Control
	if content == null:
		return
	var panel: PanelContainer = content.get_node_or_null("RankPanel") as PanelContainer
	var created: bool = false
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "RankPanel"
		panel.visible = false
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(panel)
		created = true
	var inner: VBoxContainer = panel.get_node_or_null("RankInner") as VBoxContainer
	if inner == null:
		inner = VBoxContainer.new()
		inner.name = "RankInner"
		inner.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		panel.add_child(inner)
	var headers: HBoxContainer = inner.get_node_or_null("RankHeaders") as HBoxContainer
	if headers == null:
		headers = HBoxContainer.new()
		headers.name = "RankHeaders"
		headers.add_theme_constant_override("separation", UiLayout.margin_px(2, root))
		headers.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_child(headers)
		created = true
	## Rebuild headers when missing tonnage icon spacer (older runtime panels).
	if created or headers.get_node_or_null("H_icon") == null:
		while headers.get_child_count() > 0:
			var old_h: Node = headers.get_child(0)
			headers.remove_child(old_h)
			old_h.free()
		var cols: Array = [
			["icon", ""],
			["name", "舰船名"],
			["taken", "抗伤"],
			["dealt", "伤害"],
			["heal", "维修"],
			["cap", "电容战"],
		]
		for c: Variant in cols:
			@warning_ignore("unsafe_cast")
			var pair: Array = c as Array
			var key: String = str(pair[0])
			if key == "icon":
				var spacer: Control = Control.new()
				spacer.name = "H_icon"
				spacer.custom_minimum_size = Vector2(UiLayout.px(22, root), UiLayout.px(18, root))
				spacer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				headers.add_child(spacer)
				continue
			var b: Button = Button.new()
			b.name = "H_%s" % key
			b.text = str(pair[1])
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, UiLayout.px(18, root))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			UiAssets.apply_button_font(b, UiLayout.font_size(11, root))
			b.pressed.connect(func() -> void:
				_rank_sort_key = key
				_refresh_rank_panel()
			)
			headers.add_child(b)
	var scroll: ScrollContainer = inner.get_node_or_null("RankScroll") as ScrollContainer
	if scroll == null:
		scroll = ScrollContainer.new()
		scroll.name = "RankScroll"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner.add_child(scroll)
	var list: VBoxContainer = scroll.get_node_or_null("RankList") as VBoxContainer
	if list == null:
		list = VBoxContainer.new()
		list.name = "RankList"
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", UiLayout.margin_px(1, root))
		scroll.add_child(list)


func _format_rank_stat(v: float) -> String:
	## UI_AND_SHELL §2.6 — ≥1e7 → m, ≥1000 → k.
	var a: float = absf(v)
	if a >= 10000000.0:
		return "%.1fm" % (v / 1000000.0)
	if a >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return "%.0f" % v


func _make_rank_tonnage_badge(ship_group: String, overlay_key: String, host_from: Control) -> Control:
	## Compact HUD copy of in-world tonnage stack: bg → icon → corner badge.
	var icon_side: float = float(UiLayout.px(14, host_from))
	var host_side: float = icon_side * 1.5
	var host: Control = Control.new()
	host.custom_minimum_size = Vector2(host_side, host_side)
	host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ov: Dictionary = {}
	if overlay_key != "":
		ov = UiAssets.tonnage_overlay_set(overlay_key)
	@warning_ignore("unsafe_cast")
	var bg_tex: Texture2D = ov.get("bg") as Texture2D
	if bg_tex != null:
		var bg: TextureRect = TextureRect.new()
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(bg)
	var icon_tex: Texture2D = UiAssets.tonnage_icon(ship_group) if ship_group != "" else null
	if icon_tex != null:
		var icon: TextureRect = TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pad: float = (host_side - icon_side) * 0.5
		icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon.offset_left = pad
		icon.offset_top = pad
		icon.offset_right = pad + icon_side
		icon.offset_bottom = pad + icon_side
		host.add_child(icon)
	@warning_ignore("unsafe_cast")
	var badge_tex: Texture2D = ov.get("badge") as Texture2D
	if badge_tex != null:
		var badge_side: float = maxf(icon_side / 3.0, float(UiLayout.px(5, host_from)))
		var badge: TextureRect = TextureRect.new()
		badge.texture = badge_tex
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
		badge.offset_left = host_side - badge_side
		badge.offset_top = host_side - badge_side
		badge.offset_right = host_side
		badge.offset_bottom = host_side
		host.add_child(badge)
	return host


func _refresh_rank_panel() -> void:
	@warning_ignore("unsafe_cast")
	var list: VBoxContainer = hud.get_node_or_null("Root/RightCol/RightInner/RightContent/RankPanel/RankInner/RankScroll/RankList") as VBoxContainer
	if list == null:
		return
	list.add_theme_constant_override("separation", UiLayout.margin_px(1, list))
	for c: Node in list.get_children():
		c.queue_free()
	var rows: Array = []
	if _combat_eval != null and _combat_eval.has_method("ranking_rows"):
		rows = _combat_eval.ranking_rows(_rank_sort_key, board)
	var fs: int = UiLayout.font_size(11, list)
	var row_h: float = float(UiLayout.px(20, list))
	for row_v: Variant in rows:
		@warning_ignore("unsafe_cast")
		var row: Dictionary = row_v as Dictionary
		var row_btn: Button = Button.new()
		row_btn.flat = true
		row_btn.focus_mode = Control.FOCUS_NONE
		row_btn.custom_minimum_size = Vector2(0, row_h)
		row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var iid: int = TypedVariant.as_int(row.get("iid", 0), 0)
		row_btn.pressed.connect(func() -> void: _on_rank_row_pressed(iid))
		var hb: HBoxContainer = HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", UiLayout.margin_px(2, list))
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row_btn.add_child(hb)
		hb.add_child(
			_make_rank_tonnage_badge(
				str(row.get("ship_group", "")),
				str(row.get("overlay_key", "enemy")),
				list
			)
		)
		var cells: Array = [
			str(row.get("name", "?")),
			_format_rank_stat(TypedVariant.as_float(row.get("taken", 0.0), 0.0)),
			_format_rank_stat(TypedVariant.as_float(row.get("dealt", 0.0), 0.0)),
			_format_rank_stat(TypedVariant.as_float(row.get("heal", 0.0), 0.0)),
			_format_rank_stat(TypedVariant.as_float(row.get("cap", 0.0), 0.0)),
		]
		for i: int in range(cells.size()):
			var lab: Label = Label.new()
			lab.text = str(cells[i])
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			lab.clip_text = true
			lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			UiAssets.apply_label_font(lab, false, fs)
			hb.add_child(lab)
		list.add_child(row_btn)


func _on_rank_row_pressed(iid: int) -> void:
	@warning_ignore("unsafe_cast")
	var ship: ShipUnit = instance_from_id(iid) as ShipUnit
	if ship == null or not is_instance_valid(ship):
		return
	if ship.has_method("flash_tonnage_lock"):
		ship.call("flash_tonnage_lock", 0.55)
	_show_ship_info(ship)
	_pin_ship_info()
	_set_right_pane_mode(RightPaneMode.DETAIL)


func _flash_enemy_locks_on_battle_start() -> void:
	if board == null:
		return
	var delay: float = 0.0
	for s: ShipUnit in board.all_ships():
		if s == null or not is_instance_valid(s):
			continue
		if s.slot_type != "field" or s.is_destroyed:
			continue
		if s.team_id == ShipUnit.TEAM_PLAYER:
			continue
		var ship_ref: ShipUnit = s
		var d: float = delay
		get_tree().create_timer(d).timeout.connect(func() -> void:
			if ship_ref != null and is_instance_valid(ship_ref) and ship_ref.has_method("flash_tonnage_lock"):
				ship_ref.call("flash_tonnage_lock", 0.4)
		)
		delay += 0.04


func _sync_all_tactical_stems() -> void:
	if board == null:
		return
	for s: ShipUnit in board.all_ships():
		if s != null and is_instance_valid(s) and s.has_method("sync_tactical_stem"):
			s.call("sync_tactical_stem")
