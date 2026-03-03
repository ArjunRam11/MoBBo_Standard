extends Node

# ══════════════════════════════════════════════════════════════════════════════
#  GlobalScript — autoload singleton
#  CoP data comes exclusively from CoPManager.
#  All games read:  network_position / network_position3D / net_x / net_y
# ══════════════════════════════════════════════════════════════════════════════

# ── Session ───────────────────────────────────────────────────────────────────
var session_id    : int        = 1
var current_date  : String     = ""
var trial_counts  : Dictionary = {}
var board_pose_data : Dictionary = {}

# ── BoS (Base of Support) ─────────────────────────────────────────────────────
var bos_left_points  : Array = []
var bos_right_points : Array = []
var bos_data         : Dictionary = {}   # legacy compat

# ── Screen / position scalers ─────────────────────────────────────────────────
var X_SCREEN_OFFSET  : int
var Y_SCREEN_OFFSET  : int
var Y_SCREEN_OFFSET3D: int

var current_score : int = 0
var path : String = "res://debug.json"

@export var PLAYER_POS_SCALER_X  : int = 20 * 100
@export var PLAYER_POS_SCALER_Z  : int = 20 * 100
@export var PLAYER3D_POS_SCALER_X: int = 20 * 100
@export var PLAYER3D_POS_SCALER_Y: int = 30 * 100

var screen_size = DisplayServer.screen_get_size()
var MIN_X : int = 5
var MAX_X : int = int(screen_size.x - screen_size.x * 0.364)
var MIN_Y : int = 5
var MAX_Y : int = int(screen_size.y - screen_size.y * 0.15)

var clamp_vector_x : Vector2 = Vector2(MIN_X, MIN_Y)
var clamp_vector_y : Vector2 = Vector2(MAX_X, MAX_Y)

# ── Game position outputs (read by every game) ────────────────────────────────
var net_x : float = 0.0
var net_y : float = 0.0
var net_z : float = 0.0
var net_a : float = 0.0
var raw_x : float = 0.0
var raw_y : float = 0.0
var raw_z : float = 0.0

var network_position    : Vector2 = Vector2.ZERO   # 2-D games
var network_position3D  : Vector2 = Vector2.ZERO   # 3-D games
var workspace           : Vector2 = Vector2.ZERO

var scaled_network_position   : Vector2 = Vector2.ZERO
var scaled_network_position3D : Vector2 = Vector2.ZERO
var scaled_x : float = 0.0
var scaled_y : float = 0.0
var scaled_z : float = 0.0

# ── Local CoPs (per-board, read by FruitCatcher weight%) ─────────────────────
var local_cops     : Array = []
var num_local_cops : int   = 0

# ── Connection state ──────────────────────────────────────────────────────────
@onready var connected    : bool = false
@onready var disconnected : bool = false
@onready var reset_position : bool = false
@export   var endgame     : bool = false
var quit_request : bool = false

# ── Misc ──────────────────────────────────────────────────────────────────────
@export var delay_time : float = 0.1
@onready var message_timer : Timer = Timer.new()
var _incoming_message : float = 0.0
@onready var debug : bool

# ── Reset-trace diagnostics ───────────────────────────────────────────────────
var reset_trace_active         : bool = false
var last_reset_button_press_ms : int  = 0
var reset_trace_packet_count   : int  = 0
var reset_trace_cop_count      : int  = 0
var reset_trace_board_pose_count : int = 0
var reset_trace_error_count    : int  = 0
var _last_trace_heartbeat_ms   : int  = 0
var _last_udp_packet_ms        : int  = 0
var _last_cop_packet_ms        : int  = 0

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	debug = JSON.parse_string(FileAccess.get_file_as_string(path))["debug"]
	current_date = get_date_string()
	load_session_info()

	X_SCREEN_OFFSET  = int(screen_size.x / 4)
	Y_SCREEN_OFFSET  = int(screen_size.y / 4)
	Y_SCREEN_OFFSET3D = int(screen_size.y / 1.75)

	message_timer.autostart  = true
	message_timer.wait_time  = delay_time
	message_timer.one_shot   = false
	add_child(message_timer)

	GlobalSignals.SignalBus.connect(handle_quit_request)
	get_tree().set_auto_accept_quit(false)

	_last_udp_packet_ms  = Time.get_ticks_msec()
	_last_cop_packet_ms  = Time.get_ticks_msec()
	_last_trace_heartbeat_ms = Time.get_ticks_msec()

# ══════════════════════════════════════════════════════════════════════════════
#  _process — forward CoPManager data to every game variable
# ══════════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:

	if CoPManager.is_configured() and CoPManager.combined_weight > 0.0:

		# 1. Raw CoP (cm, physical frame)
		var cop : Vector3 = CoPManager.get_combined_cop()
		raw_x = cop.x
		raw_y = cop.y
		raw_z = 0.0

		# 2. Normalise cm → 0..1 using layout physical range
		var rx : Vector2 = CoPManager.get_layout_range_x()
		var ry : Vector2 = CoPManager.get_layout_range_y()
		var x_range : float = rx.y - rx.x
		var y_range : float = ry.y - ry.x
		var norm_x : float = 0.5 if x_range == 0.0 else (raw_x - rx.x) / x_range
		var norm_y : float = 0.5 if y_range == 0.0 else (raw_y - ry.x) / y_range
		norm_x = clampf(norm_x, 0.0, 1.0)
		norm_y = clampf(norm_y, 0.0, 1.0)

		# 3. Map to screen pixel bounds
		var sw : float = float(MAX_X - MIN_X)
		var sh : float = float(MAX_Y - MIN_Y)
		net_x = MIN_X + norm_x * sw
		net_y = MIN_Y + norm_y * sh
		net_z = net_y
		net_a = net_y
		var net_y_3d : float = MIN_Y + (1.0 - norm_y) * sh

		# 4. Populate all game-facing position variables
		network_position   = Vector2(net_x, net_y_3d)
		network_position3D = Vector2(net_x, net_y_3d)
		scaled_network_position   = network_position
		scaled_network_position3D = network_position3D

		# 5. Per-board local CoPs (FruitCatcher weight% etc.)
		local_cops     = CoPManager.get_local_cops().duplicate(true)
		num_local_cops = local_cops.size()

		# 6. Connection status
		connected = true
		_incoming_message = 2.0
		_last_cop_packet_ms = Time.get_ticks_msec()

		# 7. Throttled debug print
		if Engine.get_process_frames() % 60 == 0:
			print("── GlobalScript CoP ──  raw=(%.2f, %.2f) cm  norm=(%.3f, %.3f)  2D=(%.0f, %.0f)px  w=%.2f" \
				% [raw_x, raw_y, norm_x, norm_y, net_x, net_y, CoPManager.combined_weight])
			for lc in local_cops:
				print("  board[%d] %-8s  local=(%.2f,%.2f)  global=(%.2f,%.2f)  w=%.1f" \
					% [lc.get("board_idx",0), lc.get("slot","?"),
					   lc.get("cop_x_local",0.0),  lc.get("cop_y_local",0.0),
					   lc.get("cop_x_global",0.0), lc.get("cop_y_global",0.0),
					   lc.get("weight",0.0)])

	# Handle incoming signals
	match _incoming_message:
		-99.0:
			disconnected = true
			endgame = true
			handle_quit_request()
			get_tree().quit()
		2.0:
			connected = true
		5.0:
			reset_position = true

	_process_reset_trace()

# ══════════════════════════════════════════════════════════════════════════════
#  QUIT / RESET
# ══════════════════════════════════════════════════════════════════════════════
func handle_quit_request() -> void:
	CoPManager.shutdown()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_request = true
		endgame = true
		handle_quit_request()
		get_tree().quit()

func _notify_boardsetup_reset_done() -> void:
	var nodes := get_tree().get_nodes_in_group("board_setup_scene")
	for node in nodes:
		if node.has_method("_restore_reset_button"):
			node._restore_reset_button()
			return
	var board_setup = get_tree().root.find_child("BoardSetup", true, false)
	if board_setup and board_setup.has_method("_restore_reset_button"):
		board_setup._restore_reset_button()

# ══════════════════════════════════════════════════════════════════════════════
#  RESET TRACE (diagnostics)
# ══════════════════════════════════════════════════════════════════════════════
func start_reset_trace(reset_press_ms: int) -> void:
	last_reset_button_press_ms  = reset_press_ms
	reset_trace_active          = true
	reset_trace_packet_count    = 0
	reset_trace_cop_count       = 0
	reset_trace_board_pose_count = 0
	reset_trace_error_count     = 0
	_last_trace_heartbeat_ms    = Time.get_ticks_msec()

func _process_reset_trace() -> void:
	if not reset_trace_active: return
	if last_reset_button_press_ms <= 0: return
	var now_ms  : int = Time.get_ticks_msec()
	var elapsed : int = now_ms - last_reset_button_press_ms
	if now_ms - _last_trace_heartbeat_ms >= 1000:
		_last_trace_heartbeat_ms = now_ms
		print("🧭 RESET TRACE t=%dms cop=%d since_cop=%dms connected=%s" \
			% [elapsed, reset_trace_cop_count,
			   now_ms - _last_cop_packet_ms, str(connected)])
	if elapsed >= 15000:
		reset_trace_active = false
		print("🧭 RESET TRACE: finished at t=%dms" % elapsed)

# ══════════════════════════════════════════════════════════════════════════════
#  SESSION / TRIAL
# ══════════════════════════════════════════════════════════════════════════════
func get_date_string() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [t.year, t.month, t.day]

func start_new_session_if_needed() -> void:
	var today := get_date_string()
	if today != current_date:
		current_date = today
		session_id = 1
		trial_counts.clear()
	else:
		session_id += 1
		trial_counts.clear()
	save_session_info()

func get_next_trial_id(game_name: String) -> int:
	if not trial_counts.has(game_name):
		trial_counts[game_name] = 1
	else:
		trial_counts[game_name] += 1
	save_session_info()
	return trial_counts[game_name]

func load_session_info() -> void:
	if FileAccess.file_exists("user://session.json"):
		var file := FileAccess.open("user://session.json", FileAccess.READ)
		var data : Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			current_date = data.get("current_date", get_date_string())
			session_id   = data.get("session_id", 1)
			trial_counts = data.get("trial_counts", {})

func save_session_info() -> void:
	var data := { "current_date": current_date, "session_id": session_id, "trial_counts": trial_counts }
	var file := FileAccess.open("user://session.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# ══════════════════════════════════════════════════════════════════════════════
#  SCORE UTILITY
# ══════════════════════════════════════════════════════════════════════════════
func get_top_score_for_game(game_name: String, p_id: String) -> int:
	var top_score := 0
	var folder_path := GlobalSignals.data_path + "/" + p_id + "/GameData"
	if not DirAccess.dir_exists_absolute(folder_path):
		return top_score
	var dir := DirAccess.open(folder_path)
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".csv") and file_name.begins_with(game_name):
			var file := FileAccess.open(folder_path + "/" + file_name, FileAccess.READ)
			if file:
				var first := true
				while not file.eof_reached():
					var line := file.get_line()
					if first: first = false; continue
					var fields := line.split(",")
					if fields.size() > 0:
						var s := fields[0].strip_edges()
						if s.is_valid_int() and int(s) > top_score:
							top_score = int(s)
				file.close()
		file_name = dir.get_next()
	return top_score

# ══════════════════════════════════════════════════════════════════════════════
#  is_finite helper (Godot 4 has built-in but keeping for compat)
# ══════════════════════════════════════════════════════════════════════════════
func is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

func change_patient() -> void:
	PatientDB.current_patient_id = PatientDB.current_patient_id  # triggers any listeners
