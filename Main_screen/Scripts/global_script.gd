extends Node

# Constants for screen bounds and scaling
var session_id: int = 1
var current_date: String = ""
var trial_counts: Dictionary = {}
var board_pose_data: Dictionary = {}

# DISABLED: FBP (Full Body Pose) - Individual FBP points disabled
# var fbp_point_0: Dictionary = {}        # Head
# var fbp_point_1: Dictionary = {}        # Neck
# var fbp_point_2: Dictionary = {}        # Right Shoulder
# var fbp_point_3: Dictionary = {}        # Left Shoulder
# var fbp_point_4: Dictionary = {}        # Right Elbow
# var fbp_point_5: Dictionary = {}        # Left Elbow
# var fbp_point_6: Dictionary = {}        # Right Hand
# var fbp_point_7: Dictionary = {}        # Left Hand
# var fbp_point_8: Dictionary = {}        # Right Hip
# var fbp_point_9: Dictionary = {}        # Left Hip
# var fbp_point_10: Dictionary = {}       # Right Knee
# var fbp_point_11: Dictionary = {}       # Left Knee
# var fbp_point_12: Dictionary = {}       # Right Foot
# var fbp_point_13: Dictionary = {}       # Left Foot
# var fbp_point_14: Dictionary = {}       # Left Heel
# var fbp_point_15: Dictionary = {}       # Right Heel
# var fbp_point_16: Dictionary = {}       # Left Foot Index
# var fbp_point_17: Dictionary = {}       # Right Foot Index

# BoS points (keep as arrays, no iteration)
var bos_left_points: Array = []         # Array of [x, y, z] points for left foot
var bos_right_points: Array = []        # Array of [x, y, z] points for right foot

# Legacy attributes (deprecated - for backward compatibility)
var bos_data: Dictionary = {}
var fbp_data: Dictionary = {}
var fbp_points: Array = []              # Legacy - no longer used

# 2D offsets
var X_SCREEN_OFFSET: int
var Y_SCREEN_OFFSET: int

#3D offsets
var Y_SCREEN_OFFSET3D: int

var current_score: int = 0
var json = JSON.new()
var path = "res://debug.json"

# 2D Game positions
@export var PLAYER_POS_SCALER_X: int = 20 * 100
@export var PLAYER_POS_SCALER_Z: int = 20 * 100

# 3D Game positions
@export var PLAYER3D_POS_SCALER_X: int = 20 * 100
@export var PLAYER3D_POS_SCALER_Y: int = 30 * 100

var screen_size = DisplayServer.screen_get_size()
var MIN_X: int = 5
#var MAX_X: int = int((screen_size.x-screen_size))
var MAX_X: int = int((screen_size.x - screen_size.x * .364))
var MIN_Y: int = 5
var MAX_Y: int = int(screen_size.y - screen_size.y * .15)

var clamp_vector_x = Vector2(MIN_X, MIN_Y)
var clamp_vector_y = Vector2(MAX_X, MAX_Y)

# UDP and threading - SINGLE UDP PORT (8000 only)
@onready var udp: PacketPeerUDP = PacketPeerUDP.new()  # Port 8000: CoP + Board Pose (LOCAL CoP, GCoP, Board Pose)
# DISABLED: udp_camera removed - only using port 8000 for CoP and Board Pose data
# @onready var udp_camera: PacketPeerUDP = PacketPeerUDP.new()  # Port 8001: FBP + BoS (DISABLED)
@onready var thread_network = Thread.new()
# DISABLED: thread_network_camera removed - no FBP/BoS processing
# @onready var thread_network_camera = Thread.new()
@onready var thread_python = Thread.new()
@onready var thread_path_check = Thread.new()

@onready var connected: bool = false
@onready var disconnected: bool = false
@onready var reset_position: bool = false

# Paths and platform-specific variables
@onready var interpreter_path: String
@onready var pyscript_path: String
@onready var pypath_checker_path : String
@export var endgame:bool = false

# ============================================================
# ENHANCED CoP VARIABLES - Now supports both local and global
# ============================================================
# Global CoP (combined)
var net_x: float = 0.0
var net_y: float = 0.0
var net_z: float = 0.0
var net_a: float = 0.0
var raw_x: float = 0.0
var raw_y: float = 0.0
var raw_z: float = 0.0

var board_layout: String = "2x1"  # Default layout

# CoP scaling ranges based on board layout
var cop_x_min: float = 0.30
var cop_x_max: float = -0.30
var cop_y_min: float = -0.225
var cop_y_max: float = 0.675

# Local CoPs (individual sensors)
var local_cops: Array = []  # Array of dictionaries with {x, y, z, weight}
var num_local_cops: int = 0

#2D Game network position
var network_position: Vector2 = Vector2.ZERO

#3D Game network position
var network_position3D: Vector2 = Vector2.ZERO

#Workspace network position
var workspace: Vector2 = Vector2.ZERO

# scaled position
var scaled_x: float = 0.0
var scaled_y: float = 0.0
var scaled_z: float = 0.0

# 2D Game scaled
var scaled_network_position: Vector2 = Vector2.ZERO

#3D Game scaled
var scaled_network_position3D: Vector2 = Vector2.ZERO

var quit_request:bool = false
@export var delay_time = 0.1
@onready var message_timer:Timer = Timer.new()
var _outgoing_message = "CONNECTED"
var _incoming_message: float = 0.0

@onready var debug:bool
var _last_udp_packet_ms: int = 0
var _last_cop_packet_ms: int = 0
var _last_trace_heartbeat_ms: int = 0
var reset_trace_active: bool = false
var last_reset_button_press_ms: int = 0
var reset_trace_packet_count: int = 0
var reset_trace_cop_count: int = 0
var reset_trace_board_pose_count: int = 0
var reset_trace_error_count: int = 0


func _ready():
	debug = JSON.parse_string(FileAccess.get_file_as_string(path))['debug']
	current_date = get_date_string()
	load_session_info()

	# Bind to port 8000 to RECEIVE CoP + Board Pose from MOBBO
	var bind_result = udp.bind(8000, "127.0.0.1")
	if bind_result == OK:
		print("✅ UDP socket bound to port 8000 - ready to receive LOCAL CoP, GCoP, and Board Pose")
	else:
		print("❌ Failed to bind UDP socket to port 8000 - Error code: %d" % bind_result)

	# DISABLED: Port 8001 removed - only using port 8000 for all CoP and Board Pose data
	# # Bind to port 8001 to RECEIVE FBP + BoS from MOBBO
	# var bind_result_camera = udp_camera.bind(8001, "127.0.0.1")
	# if bind_result_camera == OK:
	# 	pass # print("✅ UDP socket bound to port 8001 - ready to receive FBP + BoS")
	# else:
	# 	pass # print("❌ Failed to bind UDP socket to port 8001 - Error code: %d" % bind_result_camera)

	#thread_python.start(python_thread, Thread.PRIORITY_HIGH)
	thread_network.start(network_thread)
	# DISABLED: Port 8001 thread removed - FBP/BoS disabled
	# thread_network_camera.start(network_thread_camera)

	# print(MAX_X, " " + str(MAX_Y))
	
	# 2D Game offsets  
	X_SCREEN_OFFSET = int(screen_size.x/4)
	Y_SCREEN_OFFSET = int(screen_size.y/4)
	
	# 3D Game offsets
	Y_SCREEN_OFFSET3D = int(screen_size.y/1.75)
	
	message_timer.autostart = true
	message_timer.wait_time = delay_time
	message_timer.one_shot = false
	add_child(message_timer)
	GlobalSignals.SignalBus.connect(handle_quit_request)
	get_tree().set_auto_accept_quit(false)
	
	if OS.get_name() == "Windows":
		pyscript_path = "E:\\Godot_interface\\MOBBO_3D_GAMES\\MOBBO_3D_GAMES\\main_4pt.py"
		pypath_checker_path = "E:\\CMC\\pyprojects\\programs_rpi\\rpi_python\\file_integrity.py"
		interpreter_path = "C:\\Users\\Asus\\miniconda3\\envs\\mb\\python.exe"
	else:
		pass
		#pyscript_path = "/home/sujith/Documents/rpi_python/stream_optimize.py"
		#pypath_checker_path = "/home/sujith/Documents/rpi_python/file_integrity.py"
		#interpreter_path = "/home/sujith/Documents/rpi_python/venv/bin/python"

	_last_udp_packet_ms = Time.get_ticks_msec()
	_last_cop_packet_ms = Time.get_ticks_msec()
	_last_trace_heartbeat_ms = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not thread_python.is_alive() and not endgame and not debug:
		thread_python = Thread.new()
		thread_python.start(python_thread, Thread.PRIORITY_HIGH)
		
	match _incoming_message:
		-99.0:
			disconnected = true
			endgame = true
			thread_network.wait_to_finish()
			thread_python.wait_to_finish()
			get_tree().quit()
		2.0:
			connected = true
		5.0:
			reset_position = true

	_process_reset_trace()


func _path_checker():
	var output = []
	OS.execute(interpreter_path, [pypath_checker_path], output)
	print(output)


func start_reset_trace(reset_press_ms: int) -> void:
	"""Initialize reset trace counters from main thread."""
	last_reset_button_press_ms = reset_press_ms
	reset_trace_active = true
	reset_trace_packet_count = 0
	reset_trace_cop_count = 0
	reset_trace_board_pose_count = 0
	reset_trace_error_count = 0
	_last_trace_heartbeat_ms = Time.get_ticks_msec()


func network_thread():
	"""Thread for PRIMARY UDP port (8000) - CoP + Board Pose"""
	while true:
		if udp.get_available_packet_count() > 0:
			handle_udp_packet()
		if disconnected:
			break

# DISABLED: network_thread_camera removed - Port 8001 and FBP/BoS disabled
# func network_thread_camera():
# 	"""Thread for SECONDARY UDP port (8001) - FBP + BoS (DISABLED)"""
# 	while true:
# 		if udp_camera.get_available_packet_count() > 0:
# 			handle_udp_packet_camera()
# 		if disconnected:
# 			break

func handle_quit_request():
	_outgoing_message = "STOP"

	# Send shutdown to Python COMMAND port (9000), not data port	
	var command_socket = PacketPeerUDP.new()
	var quit_command = {
		"type": "app_control",
		"action": "shutdown",
		"timestamp": Time.get_ticks_msec()
	}
	var json_str = JSON.stringify(quit_command)
	if command_socket.set_dest_address("127.0.0.1", 9000) == OK:
		command_socket.put_packet(json_str.to_utf8_buffer())
		print("✅ Shutdown sent to Python port 9000")

	# Also handle the quit_request flag path (existing code)
	if not quit_request:
		return


func handle_udp_packet():
	"""Safely parse UDP packets from PRIMARY port (8000) - CoP + Board Pose"""
	var packet = udp.get_packet()
	_last_udp_packet_ms = Time.get_ticks_msec()

	# Convert packet to string
	var packet_string = packet.get_string_from_utf8()

	# Validate string before parsing
	if packet_string == null or packet_string.is_empty():
		return

	# Parse JSON with error handling
	var json_result = JSON.parse_string(packet_string)
	#print('the packet is '+str(json_result))

	# Check if parsing succeeded
	if json_result == null:
		return

	# Verify it's a dictionary
	if typeof(json_result) != TYPE_DICTIONARY:
		return

	var json_data = json_result

	# Process CoP data
	if json_data.has("cop"):
		if not handle_cop_data_safe(json_data["cop"]):
			pass

	# Process Board Pose data
	if json_data.has("board_pose"):
		var result = handle_board_pose_data_safe(json_data["board_pose"])

	# Reset-trace packet log (throttled)
	if reset_trace_active:
		reset_trace_packet_count += 1
		var elapsed = Time.get_ticks_msec() - last_reset_button_press_ms
		if reset_trace_packet_count <= 10 or reset_trace_packet_count % 50 == 0:
			print("🧭 RESET TRACE: UDP#%d t=%dms has_cop=%s has_board_pose=%s" % [
				reset_trace_packet_count, elapsed, str(json_data.has("cop")), str(json_data.has("board_pose"))
			])


func handle_cop_data_safe(cop_data) -> bool:
	"""
	Safely process CoP data with validation
	Now handles both local_cops array and gcop dictionary
	AND updates raw_x, raw_y, raw_z for BoardSetup compatibility
	"""
	# Validate input type
	if typeof(cop_data) != TYPE_DICTIONARY:
		print("⚠️ CoP data is not a dictionary")
		return false
	
	var has_valid_data = false

	# ============================================================
	# PROCESS LOCAL CoPs (individual sensors)
	# ============================================================
	if cop_data.has("local_cops"):
		var local_cops_array = cop_data["local_cops"]

		if typeof(local_cops_array) == TYPE_ARRAY:
			local_cops.clear()

			for local_cop in local_cops_array:
				if typeof(local_cop) != TYPE_DICTIONARY:
					continue
				
				# Extract and validate each local CoP
				var lc_x = local_cop.get("x", null)
				var lc_y = local_cop.get("y", null)
				var lc_z = local_cop.get("z", null)
				var lc_weight = local_cop.get("weight", null)
				
				# Skip if any value is null or invalid
				if lc_x == null or lc_y == null or lc_z == null or lc_weight == null:
					continue
				
				# Convert to float and validate
				var lc_x_float = float(lc_x)
				var lc_y_float = float(lc_y)
				var lc_z_float = float(lc_z)
				var lc_weight_float = float(lc_weight)
				
				if not is_finite(lc_x_float) or not is_finite(lc_y_float) or \
				   not is_finite(lc_z_float) or not is_finite(lc_weight_float):
					continue
				
				# Store valid local CoP
				local_cops.append({
					"x": lc_x_float,
					"y": lc_y_float,
					"z": lc_z_float,
					"weight": lc_weight_float
				})
			
			num_local_cops = local_cops.size()
			has_valid_data = true
	
	# ============================================================
	# PROCESS GLOBAL CoP (combined) AND UPDATE raw_x/y/z
	# ============================================================
	if cop_data.has("gcop"):
		var gcop = cop_data["gcop"]
		
		if typeof(gcop) == TYPE_DICTIONARY:
			# Extract values with null checks
			var gc_x = gcop.get("x", null)
			var gc_y = gcop.get("y", null)
			var gc_z = gcop.get("z", null)
			var gc_weight = gcop.get("weight", null)
			
			# Only process if all values are present and valid
			if gc_x != null and gc_y != null and gc_z != null and gc_weight != null:
				# ============================================================
				# CRITICAL FIX: Update raw_x, raw_y, raw_z FIRST
				# ============================================================
				raw_x = float(gc_x)
				raw_y = float(gc_y)
				raw_z = float(gc_z)
				var weight = float(gc_weight)
				
				# Validate values are finite (not NaN or Inf)
# Validate values are finite (not NaN or Inf)
				if is_finite(raw_x) and is_finite(raw_y) and is_finite(raw_z) and is_finite(weight):
					_last_cop_packet_ms = Time.get_ticks_msec()
					if reset_trace_active:
						reset_trace_cop_count += 1
						var elapsed = Time.get_ticks_msec() - last_reset_button_press_ms
						if reset_trace_cop_count <= 10 or reset_trace_cop_count % 50 == 0:
							print("🧭 RESET TRACE: CoP#%d t=%dms raw=(%.4f, %.4f, %.4f) w=%.2f" % [
								reset_trace_cop_count, elapsed, raw_x, raw_y, raw_z, weight
							])
					# Set connection status
					if weight > 0:
						_incoming_message = 2.0  # Connected
						connected = true
						
					# ============================================================
					# CRITICAL FIX: Scale raw CoP using board layout ranges
					# ============================================================

					# Determine actual min/max (accounts for reversed X in 2x1)
					var actual_x_min = min(cop_x_min, cop_x_max)
					var actual_x_max = max(cop_x_min, cop_x_max)
					var actual_y_min = min(cop_y_min, cop_y_max)
					var actual_y_max = max(cop_y_min, cop_y_max)
				

					# Normalize CoP values to 0.0-1.0 range based on board layout
					# This maps the physical board space to normalized screen space
					var normalized_x = (raw_x - actual_x_max) / (actual_x_min - actual_x_max)
					var normalized_y = (raw_y - actual_y_min) / (actual_y_max - actual_y_min)
					

					# Clamp to valid 0.0-1.0 range
					normalized_x = clampf(normalized_x, 0.0, 1.0)
					normalized_y = clampf(normalized_y, 0.0, 1.0)

					# Handle reversed X axis for 2x1 layout
					# In 2x1 layout, cop_x_min (0.30) > cop_x_max (-0.30), meaning X is reversed
					if board_layout == "2x1" and cop_x_min > cop_x_max:
						normalized_x = 1.0 - normalized_x  # Invert: right→left becomes left→right in screen coords

					# Map normalized coordinates to screen coordinates
					var screen_width = float(MAX_X - MIN_X)
					var screen_height = float(MAX_Y - MIN_Y)
				

					net_x = MIN_X + (normalized_x * screen_width)
					net_y = MIN_Y + (normalized_y * screen_height)
					
					net_z = net_y  # For 2D games that use Z as vertical
					if Engine.get_process_frames() % 50 == 0 and weight > 2:
						print("🌐 GLOBAL CoP: x=%.4f, y=%.4f, z=%.4f, weight=%.2f" % [raw_x, raw_y, raw_z, weight])
						print('The max is '+ str(MAX_X)+ 'and '+str(MAX_Y)+'and the screen size X and Y is :'+str(screen_size.x)+ ' and '+str(screen_size.y))
						print('The min screen X is: ' +str(MIN_X)+'the screen width is:'+str(screen_width)+ 'and the net_X is: ' +str(net_x)+"for the GCOP_X: "+ str(raw_x)+"norm_value: "+str(normalized_x)+"weight: "+str(weight))
						print('The min screen Y is: ' +str(MIN_Y)+'the screen height is:'+str(screen_height)+ 'and the net_y is: ' +str(net_y)+"for the GCOP_y: "+ str(raw_y)+"norm_value: "+str(normalized_y)+"weight: "+str(weight))

					# Update all output positions
					net_a = net_y  # Alternative vertical position

					# Store in both 2D and 3D formats
					network_position = Vector2(net_x, net_z)
					network_position3D = Vector2(net_x, net_y)


	return has_valid_data

func set_scaling_for_layout(layout: String) -> void:
	"""
	Update CoP scaling ranges based on board layout (DYNAMIC).
	Layout format: "NxM" where N=columns (horizontal), M=rows (vertical)
	Each board is 0.60m wide x 0.45m tall

	Examples:
	- "1x2" = 1 wide, 2 tall (user facing left-right)
	- "2x1" = 2 wide, 1 tall (user facing front-back)
	- "3x2" = 3 wide, 2 tall (6 boards total)

	Args:
		layout: Board layout string (e.g., "1x2", "2x1", "3x2", etc.)
	"""
	board_layout = layout

	# Parse layout string to extract columns (N) and rows (M)
	var parts = layout.split("x")
	if parts.size() != 2:
		print("⚠️ INVALID LAYOUT FORMAT: %s, using default 2x1" % layout)
		cop_x_min = 0.30
		cop_x_max = -0.30
		cop_y_min = -0.225
		cop_y_max = 0.675
		
		return

	var num_rows = int(parts[0])  # N: boards wide (horizontal)
	var num_columns = int(parts[1])      # M: boards tall (vertical)

	# Each board is 0.60m wide and 0.45m tall
	const BOARD_WIDTH = 0.60
	const BOARD_HEIGHT = 0.45

	# ============================================================
	# LAYOUT 1xN (N board wide, 1 boards tall)
	# User stands facing LEFT-RIGHT axis
	# ============================================================
	if num_rows == 1:
		cop_x_min = -0.30 - (num_columns - 1) * BOARD_WIDTH  # Expands left with more rows
		cop_x_max = 0.30  # Fixed on right
		cop_y_min = -0.225
		cop_y_max = 0.225
		print("📐 SCALING CONFIGURED: %s Layout (1 wide, %d tall)" % [layout, num_rows])
		print("   X Range: %.2f to %.2f (LEFT to RIGHT)" % [cop_x_min, cop_x_max])
		print("   Y Range: %.2f to %.2f (BACK to FRONT)" % [cop_y_min, cop_y_max])

	# ============================================================
	# LAYOUT Nx1 (1 boards wide, N board tall)
	# User stands facing FORWARD-BACKWARD axis
	# NOTE: X range is FIXED (does NOT expand with more columns)
	# ============================================================
	elif num_columns == 1:
		cop_x_min = -0.30  # Always fixed
		cop_x_max = 0.30   # Always fixed
		cop_y_min = -0.225
		cop_y_max = 0.225 + (num_rows - 1) * BOARD_HEIGHT  # Expands forward with more columns
		print("📐 SCALING CONFIGURED: %s Layout (%d tall, 1 wide)" % [layout, num_columns])
		print("   X Range: %.2f to %.2f (FIXED - left to right)" % [cop_x_min, cop_x_max])
		print("   Y Range: %.2f to %.2f (BACK to FRONT)" % [cop_y_min, cop_y_max])

	# ============================================================
	# LAYOUT NxM (N wide, M tall) - MIXED/RECTANGULAR
	# This is a more complex case (e.g., 2x2, 3x2, etc.)
	# User orientation depends on which dimension is larger
	# ============================================================
	else:
		print("📐 SCALING CONFIGURED: %s Layout (%d wide, %d tall) - MIXED LAYOUT" % [layout, num_columns, num_rows])

		if num_columns > 1 and num_rows> 1:
			# More boards horizontally - treat like 1xN
			cop_x_min = -0.30
			cop_x_max = 0.30 + (num_columns-1) * BOARD_WIDTH
			cop_y_min = -0.225
			cop_y_max = 0.225 + (num_rows - 1) * BOARD_HEIGHT
			print("   NOT A 1xN or NX1 arrangement.")
			
			
		print("  X Range: %.2f to %.2f" % [cop_x_min, cop_x_max])
		print("  Y Range: %.2f to %.2f" % [cop_y_min, cop_y_max])



func handle_board_pose_data_safe(board_data) -> bool:
	"""Safely process Board Pose data with validation"""
	# Validate input type
	if typeof(board_data) != TYPE_DICTIONARY:
		print("⚠️ Board data is not a dictionary")
		return false

	# FIXED: Handle both wrapped (with "data" key) and unwrapped formats
	var data_content
	if board_data.has("data"):
		data_content = board_data["data"]
	else:
		# Data is directly in the dictionary (new format from Python)
		data_content = board_data
	
	# Validate data content
	if typeof(data_content) != TYPE_DICTIONARY:
		print("⚠️ Board data content is not a dictionary")
		return false
	
	# Safely extract reference_id with null check
	var ref_id = data_content.get("reference_id", null)
	if ref_id == null:
		print("⚠️ Board data missing reference_id")
		return false
	
	if typeof(ref_id) != TYPE_FLOAT and typeof(ref_id) != TYPE_INT:
		print("⚠️ Invalid reference_id type: %d" % typeof(ref_id))
		return false
	
	# Safely extract boards with null check
	var boards_dict = data_content.get("boards", null)
	if boards_dict == null:
		print("⚠️ Board data missing boards")
		return false
	
	if typeof(boards_dict) != TYPE_DICTIONARY:
		print("⚠️ Boards is not a dictionary")
		return false
	
	# Validate each board's data
	for board_id in boards_dict.keys():
		var board_info = boards_dict[board_id]
		
		if typeof(board_info) != TYPE_DICTIONARY:
			print("⚠️ Board %s info is not a dictionary" % board_id)
			continue
		
		# Check for required fields
		if not board_info.has("id") or \
		   not board_info.has("relative_rotation_matrix") or \
		   not board_info.has("relative_translation"):
			print("⚠️ Board %s missing required fields" % board_id)
			continue
		
		# Validate rotation matrix
		var rot_matrix = board_info["relative_rotation_matrix"]
		if typeof(rot_matrix) != TYPE_ARRAY or rot_matrix.size() != 9:
			print("⚠️ Board %s rotation matrix invalid" % board_id)
			continue
		
		# Validate translation
		var translation = board_info["relative_translation"]
		if typeof(translation) != TYPE_ARRAY or translation.size() != 3:
			print("⚠️ Board %s translation invalid" % board_id)
			continue
			# Extract and store board layout if included
		
		
		
	
	# Store validated data
	board_pose_data = data_content
	if reset_trace_active:
		reset_trace_board_pose_count += 1
		var elapsed = Time.get_ticks_msec() - last_reset_button_press_ms
		print("🧭 RESET TRACE: board_pose#%d t=%dms ref_id=%s boards=%d" % [
			reset_trace_board_pose_count, elapsed, str(ref_id), boards_dict.size()
		])

	# Print each board's data
	for board_id in boards_dict.keys():
		var board_info = boards_dict[board_id]
		if typeof(board_info) == TYPE_DICTIONARY:
			if board_info.has("relative_translation"):
				@warning_ignore("unused_variable")
				var trans = board_info.get("relative_translation")
			if board_info.has("relative_rotation_matrix"):
				var rot = board_info.get("relative_rotation_matrix")
				if typeof(rot) == TYPE_ARRAY:
					pass
			
	if data_content.has("layout"):
			var layout_container = data_content["layout"]
			if typeof(layout_container) == TYPE_DICTIONARY:
				var layout_str = layout_container.get("Board_Layout", "2x1")
				print("📐 Board Layout: %s" % str(layout_container))
				# CRITICAL: Update scaling for the detected layout
				set_scaling_for_layout(layout_str)


	return true


func _process_reset_trace() -> void:
	"""Periodic heartbeat logs for reset diagnostics (auto-stops after 15s)."""
	if not reset_trace_active:
		return

	var start_ms = last_reset_button_press_ms
	if start_ms <= 0:
		return

	var now_ms = Time.get_ticks_msec()
	var elapsed = now_ms - start_ms

	if now_ms - _last_trace_heartbeat_ms >= 1000:
		_last_trace_heartbeat_ms = now_ms
		var since_udp = now_ms - _last_udp_packet_ms
		var since_cop = now_ms - _last_cop_packet_ms
		print("🧭 RESET TRACE HEARTBEAT t=%dms packets=%d cop=%d board_pose=%d since_udp=%dms since_cop=%dms connected=%s" % [
			elapsed, reset_trace_packet_count, reset_trace_cop_count, reset_trace_board_pose_count, since_udp, since_cop, str(connected)
		])

	if elapsed >= 15000:
		reset_trace_active = false
		print("🧭 RESET TRACE: finished at t=%dms" % elapsed)


func handle_bos_data_safe(bos_dict) -> bool:
	"""Safely process Base of Support data with validation"""
	# Validate input type
	if typeof(bos_dict) != TYPE_DICTIONARY:
		print("⚠️ BoS data is not a dictionary")
		return false

	# FIXED: Handle both wrapped (with "data" key) and unwrapped formats
	var data_content
	if bos_dict.has("data"):
		data_content = bos_dict["data"]
	else:
		# Data is directly in the dictionary (new format from Python)
		data_content = bos_dict
	
	# Validate data content
	if typeof(data_content) != TYPE_DICTIONARY:
		print("⚠️ BoS data content is not a dictionary")
		return false
	
	# Validate left foot data if present
	if data_content.has("left_foot") and data_content["left_foot"] != null:
		@warning_ignore("confusable_local_declaration")
		var left_foot = data_content["left_foot"]
		if typeof(left_foot) != TYPE_ARRAY:
			print("⚠️ Left foot is not an array")
			return false
		
		# Validate each point
		for point in left_foot:
			if typeof(point) != TYPE_ARRAY or point.size() < 3:
				print("⚠️ Left foot point invalid")
				return false
			
			# Check for null/invalid values
			for coord in point:
				if coord == null or (typeof(coord) == TYPE_FLOAT and not is_finite(coord)):
					print("⚠️ Left foot coordinate invalid")
					return false
	
	# Validate right foot data if present
	if data_content.has("right_foot") and data_content["right_foot"] != null:
		@warning_ignore("confusable_local_declaration")
		var right_foot = data_content["right_foot"]
		if typeof(right_foot) != TYPE_ARRAY:
			print("⚠️ Right foot is not an array")
			return false
		
		# Validate each point
		for point in right_foot:
			if typeof(point) != TYPE_ARRAY or point.size() < 3:
				print("⚠️ Right foot point invalid")
				return false
			
			# Check for null/invalid values
			for coord in point:
				if coord == null or (typeof(coord) == TYPE_FLOAT and not is_finite(coord)):
					print("⚠️ Right foot coordinate invalid")
					return false
	
	# FIXED: Update flat BoS points arrays (Option A - atomic, no race condition!)
	var left_foot = data_content.get("left_foot", null)
	var right_foot = data_content.get("right_foot", null)

	bos_left_points = left_foot if left_foot != null else []
	bos_right_points = right_foot if right_foot != null else []

	# Store as before for backward compatibility
	bos_data = data_content

	# Debug logf
	if Engine.get_process_frames() % 50 == 0:
		var has_left = left_foot != null and left_foot.size() > 0
		var has_right = right_foot != null and right_foot.size() > 0
		if has_left or has_right:
			pass

	return true
func _notify_boardsetup_reset_done():
	"""Find BoardSetup scene and call its reset-button restore function."""
	# Try to find BoardSetup node by group (recommended approach)
	var nodes = get_tree().get_nodes_in_group("board_setup_scene")
	for node in nodes:
		if node.has_method("_restore_reset_button"):
			node._restore_reset_button()
			return
	
	# Fallback: search by node name
	var board_setup = get_tree().root.find_child("BoardSetup", true, false)
	if board_setup and board_setup.has_method("_restore_reset_button"):
		board_setup._restore_reset_button()

# DISABLED: FBP data processing function - FBP disabled
# func handle_fbp_data_safe(fbp_dict) -> bool:
# 	"""Safely process Full Body Pose data with validation (Individual points like GCOP)"""
# 	# ... function disabled ...


func is_finite(value: float) -> bool:
	"""Check if a float value is finite (not NaN or Inf)"""
	return not is_nan(value) and not is_inf(value)


func change_patient():
	_outgoing_message = 'USER:' + PatientDB.current_patient_id


func send_dummy_packet():
	udp.put_packet(_outgoing_message.to_utf8_buffer())

func python_thread():
	if not debug:
		print("🐍 Python thread started...")

		var launcher_path = "E:\\Godot_interface\\MOBBO_3D_GAMES\\MOBBO_3D_GAMES\\run_main_mb.bat"
		var output: Array = []
		var exit_code = OS.execute("cmd.exe", ["/c", launcher_path], output, true, true)

		if exit_code != 0:
			print("❌ Failed to start MOBBO process via launcher. Exit code: %d" % exit_code)
		else:
			print("✅ MOBBO launcher exited cleanly")

		print("🛑 Python process ended.")
	else:
		print("Debugging...")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_request = true
		endgame = true
		handle_quit_request()
		thread_python.wait_to_finish()
		get_tree().quit()


func get_date_string() -> String:
	var time = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [time.year, time.month, time.day]


func start_new_session_if_needed():
	var today = get_date_string()
	if today != current_date:
		current_date = today
		session_id = 1
		trial_counts.clear()
		save_session_info()
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


func load_session_info():
	if FileAccess.file_exists("user://session.json"):
		var file = FileAccess.open("user://session.json", FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			current_date = data.get("current_date", get_date_string())
			session_id = data.get("session_id", 1)
			trial_counts = data.get("trial_counts", {})


func save_session_info():
	var data = {
		"current_date": current_date,
		"session_id": session_id,
		"trial_counts": trial_counts
	}
	var file = FileAccess.open("user://session.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))


func get_top_score_for_game(game_name: String, p_id: String) -> int:
	var top_score := 0
	var folder_path = GlobalSignals.data_path + "/" + p_id + "/GameData"
	
	if DirAccess.dir_exists_absolute(folder_path):
		var dir = DirAccess.open(folder_path)
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".csv") and file_name.begins_with(game_name):
				var file_path = folder_path + "/" + file_name
				var file = FileAccess.open(file_path, FileAccess.READ)
				
				if file:
					var is_first_line = true
					while not file.eof_reached():
						var line = file.get_line()
						if is_first_line:
							is_first_line = false
							continue
						var fields = line.split(",")
						if fields.size() > 0:
							var score_str = fields[0].strip_edges()
							if score_str.is_valid_int():
								var score = int(score_str)
								if score > top_score:
									top_score = score
					
					file.close()
			file_name = dir.get_next()
	
	return top_score
