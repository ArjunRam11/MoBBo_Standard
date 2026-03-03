extends Camera3D

# Camera speeds
var rotation_speed = 0.3
var zoom_speed = 0.5
var pan_speed = 0.05

# Mouse button states
var right_mouse_pressed = false
var middle_mouse_pressed = false

# Store initial camera position and rotation from scene
var original_position = Vector3.ZERO
var original_rotation = Vector3.ZERO

# View mode tracking
enum ViewMode { CUSTOM, TOP, FRONT, ISOMETRIC }
var current_view_mode = ViewMode.CUSTOM

# Target point to look at (center of the platform/scene)
var look_at_target = Vector3(0, 0, 0)

# Standard view distances
var view_distance = 3.0  # Distance from target in meters


func _ready():
	# Store the initial position and rotation set in the editor
	original_position = position
	original_rotation = rotation_degrees
	
	print("📷 Camera Controls:")
	print("  1 - Top View")
	print("  2 - Front View")
	print("  3 - Isometric View")
	print("  ESC - Reset to Original View")
	print("  Right Mouse - Rotate")
	print("  Middle Mouse - Pan")
	print("  Mouse Wheel - Zoom")


func _input(event):
	# Handle mouse button press/release
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			right_mouse_pressed = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_mouse_pressed = event.pressed
		
		# Zoom with mouse wheel
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			translate(Vector3(0, 0, -zoom_speed))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			translate(Vector3(0, 0, zoom_speed))
	
	# Handle mouse motion
	if event is InputEventMouseMotion:
		# Right mouse: Rotate camera
		if right_mouse_pressed:
			rotate_y(-event.relative.x * rotation_speed * 0.01)
			rotate_object_local(Vector3(1, 0, 0), -event.relative.y * rotation_speed * 0.01)
			current_view_mode = ViewMode.CUSTOM
		
		# Middle mouse: Pan/translate camera
		elif middle_mouse_pressed:
			var right_direction = global_transform.basis.x
			var up_direction = global_transform.basis.y
			
			translate(-right_direction * event.relative.x * pan_speed)
			translate(up_direction * event.relative.y * pan_speed)
			current_view_mode = ViewMode.CUSTOM


func _process(delta):
	# View mode hotkeys
	if Input.is_action_just_pressed("ui_cancel"):  # ESC key
		reset_camera()
	
	# Number keys for view modes
	if Input.is_key_pressed(KEY_1):
		set_top_view()
	elif Input.is_key_pressed(KEY_2):
		set_front_view()
	elif Input.is_key_pressed(KEY_3):
		set_isometric_view()


func reset_camera():
	"""Reset camera to original editor position"""
	position = original_position
	rotation_degrees = original_rotation
	current_view_mode = ViewMode.CUSTOM
	print("📷 Camera reset to original view")


func set_top_view():
	"""Set camera to top-down view (looking down Y-axis)"""
	if current_view_mode == ViewMode.TOP:
		return
	
	current_view_mode = ViewMode.TOP
	
	# Position camera directly above the target
	position = look_at_target + Vector3(0, view_distance, 0)
	
	# Look straight down
	rotation_degrees = Vector3(-90, 0, 0)
	
	print("📷 Top View activated")


func set_front_view():
	"""Set camera to front view (looking along Z-axis)"""
	if current_view_mode == ViewMode.FRONT:
		return
	
	current_view_mode = ViewMode.FRONT
	
	# Position camera in front of the target (along -Z axis in Godot)
	position = look_at_target + Vector3(0, 0, view_distance)
	
	# Look at target (facing -Z direction)
	look_at(look_at_target, Vector3.UP)
	
	print("📷 Front View activated")


func set_isometric_view():
	"""Set camera to isometric view (45° angle, useful for 3D visualization)"""
	if current_view_mode == ViewMode.ISOMETRIC:
		return
	
	current_view_mode = ViewMode.ISOMETRIC
	
	# Classic isometric angle: 45° horizontal, 35.264° vertical
	# Position camera at an angle
	var angle_h = deg_to_rad(45)  # Horizontal angle
	var angle_v = deg_to_rad(35.264)  # Vertical angle (arctan(1/sqrt(2)))
	
	# Calculate position using spherical coordinates
	var distance = view_distance
	var x = distance * cos(angle_v) * cos(angle_h)
	var y = distance * sin(angle_v)
	var z = distance * cos(angle_v) * sin(angle_h)
	
	position = look_at_target + Vector3(x, y, z)
	
	# Look at the target
	look_at(look_at_target, Vector3.UP)
	
	print("📷 Isometric View activated")


func set_look_at_target(target: Vector3):
	"""Update the target point that camera views look at"""
	look_at_target = target


func set_view_distance(distance: float):
	"""Update the distance from target for standard views"""
	view_distance = distance


func get_current_view_mode_name() -> String:
	"""Get the name of the current view mode"""
	match current_view_mode:
		ViewMode.TOP:
			return "Top View"
		ViewMode.FRONT:
			return "Front View"
		ViewMode.ISOMETRIC:
			return "Isometric View"
		ViewMode.CUSTOM:
			return "Custom View"
		_:
			return "Unknown"
