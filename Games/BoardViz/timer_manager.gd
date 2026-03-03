extends Node

"""
Simple Timer Manager - Tracks elapsed time in HH:MM:SS format
Place this on a Node and reference UI elements (Label for display, Button for control)

Usage:
1. Create a Node with this script
2. Create a Label child node named "TimerLabel" for display
3. Create a Button child node named "TimerButton" for start/stop
4. Optional: Create a Timer child node named "InternalTimer" (auto-created if not found)
"""

# References to child nodes
var timer_label: Label
var control_button: Button
var back_button: Button
var internal_timer: Timer

# Timer state
var elapsed_time: float = 0.0
var is_active: bool = false

# UDP for sending recording commands to Python
var udp_socket: PacketPeerUDP = PacketPeerUDP.new()
var python_command_port: int = 9000
var python_ip: String = "127.0.0.1"

func _ready():
	"""Initialize and find child nodes"""
	print("⏱️ Timer Manager initialized")

	# Find or create label
	timer_label = find_child("TimerLabel", true, false)
	if timer_label == null:
		print("⚠️ TimerLabel not found, creating one...")
		create_default_label()
	else:
		print("✅ Found TimerLabel")

	# Find or create control button (combined Start/Stop and Record)
	control_button = find_child("ControlButton", true, false)
	if control_button == null:
		# Try to find TimerButton as fallback for compatibility
		control_button = find_child("TimerButton", true, false)
		if control_button == null:
			print("⚠️ ControlButton not found, creating one...")
			create_default_button()
		else:
			print("✅ Found TimerButton (using as ControlButton)")
			control_button.pressed.connect(_on_control_button_pressed)
	else:
		print("✅ Found ControlButton")
		control_button.pressed.connect(_on_control_button_pressed)

	# Find or create internal timer
	internal_timer = find_child("InternalTimer", true, false)
	if internal_timer == null:
		print("⚠️ InternalTimer not found, creating one...")
		internal_timer = Timer.new()
		internal_timer.name = "InternalTimer"
		internal_timer.wait_time = 0.1  # Update every 100ms
		add_child(internal_timer)
	else:
		print("✅ Found InternalTimer")

	internal_timer.timeout.connect(_on_timer_tick)

	# Find back button
	back_button = find_child("BackButton", true, false)
	if back_button == null:
		print("⚠️ BackButton not found")
	else:
		print("✅ Found BackButton")
		back_button.pressed.connect(_on_back_button_pressed)

	# Update display
	update_display()

func create_default_label():
	"""Create a default label if not found"""
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)

	timer_label = Label.new()
	timer_label.name = "TimerLabel"
	timer_label.text = "00:00:00"
	timer_label.anchor_left = 0.2
	timer_label.anchor_top = 0.05
	timer_label.offset_left = -100
	timer_label.offset_top = 10
	timer_label.offset_right = 100
	timer_label.offset_bottom = 70
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Add theme
	var theme = Theme.new()
	timer_label.add_theme_font_size_override("font_size", 100)
	timer_label.add_theme_color_override("font_color", Color.LAWN_GREEN)

	canvas_layer.add_child(timer_label)

func create_default_button():
	"""Create a default control button if not found"""
	var canvas_layer = get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		canvas_layer = CanvasLayer.new()
		add_child(canvas_layer)

	control_button = Button.new()
	control_button.name = "ControlButton"
	control_button.text = "Start"
	control_button.anchor_left = 0.0
	control_button.anchor_top = 0.0
	control_button.anchor_right = 0.0
	control_button.anchor_bottom = 0.0
	control_button.offset_left = 20      # 20px from left edge
	control_button.offset_top = 30       # 30px from top edge
	control_button.offset_right = 140    # Width: 120px (right - left)
	control_button.offset_bottom = 80    # Height: 50px (bottom - top)
	

	# Add theme
	var theme = Theme.new()
	control_button.add_theme_font_size_override("font_size", 50)

	canvas_layer.add_child(control_button)
	control_button.pressed.connect(_on_control_button_pressed)

func _on_timer_tick():
	"""Called every timer tick"""
	elapsed_time += internal_timer.wait_time
	update_display()

func _on_control_button_pressed():
	"""Handle control button press - combined Start/Stop and Record"""
	if is_active:
		stop_session()
	else:
		start_session()

func start_session():
	"""Start timer and recording"""
	if is_active:
		return

	is_active = true

	# Start timer
	internal_timer.start()

	# Start recording - create trial folder and send command
	var trial_path = create_trial_folder()
	send_recording_command(true, trial_path)

	# Update button appearance
	control_button.text = "Stop"
	control_button.modulate = Color(1.0, 0.4, 0.4)

	print("⏱️ Session started - Timer and Recording active")

func stop_session():
	"""Stop timer and recording - then reset timer to 0"""
	if not is_active:
		return

	is_active = false

	# Stop timer
	internal_timer.stop()

	# Stop recording
	send_recording_command(false, "")

	# FIXED: Reset timer to 0 when stopped
	elapsed_time = 0.0
	update_display()

	# Update button appearance
	control_button.text = "Start"
	control_button.modulate = Color(0.2, 0.8, 0.2)

	print("⏱️ Session stopped and reset to %s" % format_time(elapsed_time))

func reset_timer():
	"""Reset timer to 00:00:00"""
	elapsed_time = 0.0
	is_active = false
	if internal_timer:
		internal_timer.stop()
	if control_button:
		control_button.text = "Start"
		control_button.modulate = Color(0.2, 0.8, 0.2)
	update_display()
	print("⏱️ Session reset")

func update_display():
	"""Update label with current time"""
	if timer_label:
		timer_label.text = format_time(elapsed_time)

func format_time(seconds: float) -> String:
	"""Convert seconds to HH:MM:SS"""
	var hours = int(seconds) / 3600
	var minutes = (int(seconds) % 3600) / 60
	var secs = int(seconds) % 60

	return "%02d:%02d:%02d" % [hours, minutes, secs]

func get_elapsed_time() -> float:
	"""Return elapsed time in seconds"""
	return elapsed_time

func get_time_string() -> String:
	"""Return formatted time string"""
	return format_time(elapsed_time)

func is_session_active() -> bool:
	"""Check if session is currently active (timer + recording)"""
	return is_active

func create_trial_folder() -> String:
	"""Generate trial folder name with timestamp - Python will create actual folder"""
	var date_dict = Time.get_datetime_dict_from_system()

	var date_str = "%04d%02d%02d" % [date_dict["year"], date_dict["month"], date_dict["day"]]
	var time_str = "%02d%02d%02d" % [date_dict["hour"], date_dict["minute"], date_dict["second"]]
	var trial_name = "trial_%s_%s" % [date_str, time_str]

	return trial_name

func send_recording_command(state: bool, trial_path: String):
	"""Send recording command to Python backend via UDP"""
	if udp_socket == null:
		print("Error: UDP socket not initialized")
		return

	# Get current patient name from PatientDB
	var patient_name: String = ""
	if PatientDB and PatientDB.current_patient_id != "":
		var patient_data = PatientDB.get_patient(PatientDB.current_patient_id)
		if patient_data and patient_data.has("name"):
			patient_name = patient_data["name"]
			print("📋 Patient name retrieved: %s" % patient_name)
		else:
			print("⚠️ Patient data not found for ID: %s" % PatientDB.current_patient_id)
	else:
		print("⚠️ PatientDB not available or no patient selected")

	# Create command packet with patient name
	var command = {
		"action": "toggle_recording",
		"state": state,
		"trial_path": trial_path,
		"patient_name": patient_name,
		"timestamp": Time.get_ticks_msec()
	}

	# Convert to JSON string
	var json_string = JSON.stringify(command)
	var packet_bytes = json_string.to_utf8_buffer()

	# Send to Python command receiver
	var error = udp_socket.set_dest_address(python_ip, python_command_port)
	if error != OK:
		print("Error setting UDP destination: %s" % error)
		return

	error = udp_socket.put_packet(packet_bytes)
	if error != OK:
		print("Error sending UDP packet: %s" % error)
		return

	print("Recording command sent to Python: %s" % json_string)

func _on_back_button_pressed():
	"""Handle back button press - navigate to mode.tscn"""
	print("🔙 Back button pressed - Returning to mode selection")

	# Stop recording if active
	if is_active:
		stop_session()

	# Load mode.tscn - correct path with Scenes subdirectory
	get_tree().change_scene_to_file("res://Main_screen/Scenes/mode.tscn")
