extends Node

"""
Timer Controller - Displays elapsed time in HH:MM:SS format
with Start/Stop button functionality

Usage:
1. Add this script to a Node in your scene
2. Attach UI elements for display and button
3. Call start_timer() and stop_timer() to control
"""

# UI References
@onready var timer_label: Label = Label.new()
@onready var timer_button: Button = Button.new()
@onready var timer_node: Timer = Timer.new()

# Timer state
var elapsed_time: float = 0.0
var is_running: bool = false
var timer_visible: bool = true

# Style constants
var TIMER_COLOR: Color = Color.WHITE
var TIMER_FONT_SIZE: int = 48
var BUTTON_COLOR: Color = Color(0.2, 0.6, 1.0, 1.0)  # Blue
var BUTTON_TEXT_COLOR: Color = Color.WHITE

func _ready():
	"""Initialize timer UI and setup"""
	setup_ui()
	connect_signals()

	# Add timer node to scene tree
	add_child(timer_node)

	# Update display
	update_timer_display()

func setup_ui():
	"""Setup timer label and button UI elements"""

	# Setup Timer Label
	timer_label.name = "TimerLabel"
	timer_label.anchor_left = 0.5
	timer_label.anchor_top = 0.1
	timer_label.anchor_right = 0.5
	timer_label.anchor_bottom = 0.15
	timer_label.offset_left = -100
	timer_label.offset_top = 10
	timer_label.offset_right = 100
	timer_label.offset_bottom = 80

	# Style the label
	var label_font = preload("res://assets/fonts/default_font.tres") if ResourceLoader.exists("res://assets/fonts/default_font.tres") else null
	if label_font == null:
		# Create default font
		var font_file = FontFile.new()
		timer_label.add_theme_font_override("font", font_file)

	timer_label.add_theme_font_size_override("font_size", TIMER_FONT_SIZE)
	timer_label.add_theme_color_override("font_color", TIMER_COLOR)
	timer_label.text = "00:00:00"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Setup Control node as container for UI (2D overlay on 3D scene)
	var ui_layer = CanvasLayer.new()
	ui_layer.name = "TimerUILayer"
	ui_layer.layer = 100  # On top of everything
	add_child(ui_layer)

	ui_layer.add_child(timer_label)

	# Setup Timer Button
	timer_button.name = "TimerButton"
	timer_button.anchor_left = 0.5
	timer_button.anchor_top = 0.2
	timer_button.anchor_right = 0.5
	timer_button.anchor_bottom = 0.25
	timer_button.offset_left = -75
	timer_button.offset_top = 100
	timer_button.offset_right = 75
	timer_button.offset_bottom = 150
	timer_button.text = "Start"

	# Style the button
	var button_theme = Theme.new()
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = BUTTON_COLOR
	button_style.corner_radius_bottom_left = 5
	button_style.corner_radius_bottom_right = 5
	button_style.corner_radius_top_left = 5
	button_style.corner_radius_top_right = 5
	button_theme.set_stylebox("normal", "Button", button_style)
	button_theme.set_color("font_color", "Button", BUTTON_TEXT_COLOR)
	button_theme.set_font_size("font_size", "Button", 24)

	timer_button.theme = button_theme

	ui_layer.add_child(timer_button)

func connect_signals():
	"""Connect signals for button and timer"""
	timer_button.pressed.connect(_on_timer_button_pressed)
	timer_node.timeout.connect(_on_timer_timeout)

func _process(_delta):
	"""Update timer display every frame"""
	if not is_running:
		return

	# Update label
	update_timer_display()

func _on_timer_button_pressed():
	"""Handle button press - toggle timer start/stop"""
	if is_running:
		stop_timer()
	else:
		start_timer()

func _on_timer_timeout():
	"""Called by internal Timer node every tick"""
	elapsed_time += timer_node.wait_time

func start_timer():
	"""Start the timer"""
	if is_running:
		return

	is_running = true
	timer_node.start()
	timer_button.text = "Stop"
	timer_button.modulate = Color(1.0, 0.4, 0.4)  # Red-ish when running
	print("⏱️ Timer started")

func stop_timer():
	"""Stop the timer"""
	if not is_running:
		return

	is_running = false
	timer_node.stop()
	timer_button.text = "Start"
	timer_button.modulate = Color.WHITE
	print("⏱️ Timer stopped - Elapsed: %s" % format_time(elapsed_time))

func reset_timer():
	"""Reset timer to 00:00:00"""
	elapsed_time = 0.0
	is_running = false
	timer_node.stop()
	timer_button.text = "Start"
	timer_button.modulate = Color.WHITE
	update_timer_display()
	print("⏱️ Timer reset")

func update_timer_display():
	"""Update the label with current elapsed time in HH:MM:SS format"""
	timer_label.text = format_time(elapsed_time)

func format_time(seconds: float) -> String:
	"""Convert seconds to HH:MM:SS format"""
	var hours = int(seconds) / 3600
	var minutes = (int(seconds) % 3600) / 60
	var secs = int(seconds) % 60

	return "%02d:%02d:%02d" % [hours, minutes, secs]

func get_elapsed_time() -> float:
	"""Get current elapsed time in seconds"""
	return elapsed_time

func set_timer_visible(visible: bool):
	"""Show/hide the timer UI"""
	timer_visible = visible
	timer_label.visible = visible
	timer_button.visible = visible

func get_timer_string() -> String:
	"""Get formatted timer string"""
	return format_time(elapsed_time)
