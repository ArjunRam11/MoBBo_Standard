extends Node3D

# Reference to board nodes
@onready var platform = $Platform
@onready var boards = {
	1: $Platform/board_1,
	2: $Platform/board_2,
	3: $Platform/board_3,
	4: $Platform/board_4,
	5: $Platform/board_5,
	6: $Platform/board_6
}

# Mapping from real hardware board IDs to scene board IDs
var board_id_mapping = {
	68: 1,  # Hardware board 68 -> Scene board_1
	11: 2,  # Hardware board 11 -> Scene board_2
}

# Visual indicators
@onready var gcop_indicator: MeshInstance3D
@onready var local_cop_indicators: Array = []  # Array of MeshInstance3D
@onready var fbp_skeleton: Node3D  # Container for body pose
var fbp_joint_indicators: Array = []  # Array of joint indicators (keypoints only)

# MediaPipe keypoint indices (18 keypoints)
var KP = {
	"head": 0,
	"neck": 1,
	"right_shoulder": 2,
	"left_shoulder": 3,
	"right_elbow": 4,
	"left_elbow": 5,
	"right_hand": 6,
	"left_hand": 7,
	"right_hip": 8,
	"left_hip": 9,
	"right_knee": 10,
	"left_knee": 11,
	"right_foot": 12,
	"left_foot": 13,
	"left_heel": 14,
	"right_heel": 15,
	"left_foot_index": 16,
	"right_foot_index": 17
}

@onready var bos_container: Node3D  # Container for BoS points
var bos_point_indicators_left: Array = []  # Array of left foot point indicators
var bos_point_indicators_right: Array = []  # Array of right foot point indicators

# Tracking data changes
var previous_board_data_hash: int = 0
var board_layout_data: Dictionary = {}  # Board layout info (rows, cols, spacing, etc.) - NEW

# Scaling factors
const POSITION_SCALE: float = 1.0
const BOARD_SIZE: Vector3 = Vector3(0.6, 0.02, 0.45)

# Active boards tracking
var active_boards: Array = []
var reference_board_id: int = -1

# Colors
const GCOP_COLOR = Color(1.0, 0.0, 0.0, 1.0)  # Red
const LOCAL_COP_COLOR = Color(1.0, 0.954, 0.944, 1.0)  # White
const REFERENCE_BOARD_COLOR = Color(1.0, 0.5, 0.0, 1.0)  # Orange
const GCOP_RADIUS = 0.025  # 2.5cm
const FBP_JOINT_COLOR = Color(0.0, 0.868, 0.85, 0.9)  # Cyan
const BOS_LEFT_COLOR = Color(0.08, 0.016, 0.003, 0.902)  # Brown
const BOS_RIGHT_COLOR = Color(0.041, 0.011, 0.0, 0.902)  # Dark brown

# ============ UI CONTROL VARIABLES ============
var canvas_layer: CanvasLayer = null
var ui_panel: Panel = null
var recording_buttons: Dictionary = {}  # IP address -> Button
var recording_states: Dictionary = {}  # IP address -> bool (recording state)
var detected_boards: Array = []  # List of board IP addresses detected


func _ready():
	# Verify GlobalScript exists
	if not has_node("/root/GlobalScript"):
		print("❌ GlobalScript not found!")
		return

	create_gcop_indicator()
	# DISABLED: FBP skeleton - Full Body Pose disabled
	# create_fbp_skeleton()
	# create_bos_container()  # DISABLED - BoS plotting disabled

	# DISABLED: FBP joint indicators - Full Body Pose disabled
	# # Create all joint indicators upfront (18 keypoints for MediaPipe)
	# fbp_joint_indicators = []
	# for i in range(18):
	# 	var joint = create_fbp_joint_indicator(i)
	# 	fbp_joint_indicators.append(joint if joint else null)

	hide_all_boards()

	# Create UI controls with reset button
	create_ui_controls()


func _process(_delta: float) -> void:
	# Get global script directly
	var global_script = get_node("/root/GlobalScript")
	if not global_script:
		return

	# Always update board pose
	update_boards_from_network(global_script)

	# Always update CoP (local and global)
	update_cop_from_network(global_script)

	# DISABLED: FBP update - Full Body Pose disabled
	# # Update FBP (ULTRA-SAFE)
	# update_fbp_from_network(global_script)

	# Update BoS (ULTRA-SAFE) - DISABLED
	# update_bos_from_network(global_script)


func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_H:
				hide_all_visualizations()


# ============ BOARD SETUP ============

func hide_all_boards():
	for board_id in boards:
		if boards[board_id]:
			boards[board_id].visible = false


func update_boards_from_network(global_script: Node) -> void:
	if not global_script or not is_instance_valid(global_script):
		return

	if not "board_pose_data" in global_script:
		return

	var board_data = global_script.board_pose_data

	if board_data == null or typeof(board_data) != TYPE_DICTIONARY:
		return

	if board_data.is_empty():
		return

	# Make defensive copy
	board_data = board_data.duplicate()

	if not board_data.has("boards") or not board_data.has("reference_id"):
		return

	# NEW FIX: Also retrieve board layout data from GlobalScript
	if "board_layout_data" in global_script:
		var layout_data = global_script.board_layout_data
		if layout_data and typeof(layout_data) == TYPE_DICTIONARY and not layout_data.is_empty():
			board_layout_data = layout_data
			#print("📐 Board Layout cached in BoardSetup: %s" % layout_data.get("layout", "unknown"))

	var new_hash = board_data.hash()

	if new_hash == previous_board_data_hash:
		return

	previous_board_data_hash = new_hash
	print("🎬 Board data changed - rendering %d boards (ref: %s)" % [board_data.get("boards", {}).size(), board_data.get("reference_id", "?")])
	plot_boards(board_data)


func plot_boards(board_data: Dictionary):
	if not board_data.has("reference_id") or not board_data.has("boards"):
		return

	var real_reference_id = int(board_data.get("reference_id", -1))

	if real_reference_id == -1:
		return

	var boards_data = board_data.get("boards", {})

	if typeof(boards_data) != TYPE_DICTIONARY or boards_data.is_empty():
		return

	if not board_id_mapping.has(real_reference_id):
		print("⚠️ Reference board %d not in mapping" % real_reference_id)
		return

	reference_board_id = board_id_mapping[real_reference_id]
	active_boards.clear()
	hide_all_boards()
	print("📦 Rendering boards: hiding all, then showing active ones...")

	for board_id_str in boards_data.keys():
		var real_board_id = int(board_id_str)

		if not board_id_mapping.has(real_board_id):
			continue

		var scene_board_id = board_id_mapping[real_board_id]

		if not boards.has(scene_board_id):
			continue

		active_boards.append(scene_board_id)
		var board_node = boards[scene_board_id]
		var board_info = boards_data[board_id_str]

		if typeof(board_info) != TYPE_DICTIONARY:
			continue

		var rel_translation = board_info.get("relative_translation", [0.0, 0.0, 0.0])
		var rel_rotation_matrix = board_info.get("relative_rotation_matrix", null)

		board_node.visible = true
		print("  ✅ Board %d now visible at scene position %d" % [real_board_id, scene_board_id])
		apply_board_color(board_node, real_board_id == real_reference_id)

		if real_board_id == real_reference_id:
			board_node.position = Vector3.ZERO
			board_node.rotation = Vector3.ZERO
			board_node.basis = Basis()
		else:
			var position_ = convert_translation_to_godot(rel_translation)

			if is_position_valid(position_):
				board_node.position = position_

			if rel_rotation_matrix and typeof(rel_rotation_matrix) == TYPE_ARRAY and rel_rotation_matrix.size() == 9:
				var basis_ = create_basis_from_matrix(rel_rotation_matrix)
				if basis_ != Basis():
					board_node.basis = basis_


func apply_board_color(board_node: Node3D, is_reference: bool):
	for child in board_node.get_children():
		if child is MeshInstance3D:
			if "LED" in child.name or "led" in child.name:
				continue

			if is_reference:
				var material = StandardMaterial3D.new()
				material.albedo_color = REFERENCE_BOARD_COLOR
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color.a = 0.7
				child.material_override = material
			else:
				child.material_override = null

		if child.get_child_count() > 0:
			apply_board_color(child, is_reference)


func convert_translation_to_godot(translation: Array) -> Vector3:
	if typeof(translation) != TYPE_ARRAY or translation.size() < 3:
		return Vector3.ZERO

	var fx = float(translation[0])
	var fy = float(translation[1])
	var fz = float(translation[2])

	if not is_finite(fx) or not is_finite(fy) or not is_finite(fz):
		return Vector3.ZERO

	return Vector3(fx * POSITION_SCALE, 0, -fy * POSITION_SCALE)


func create_basis_from_matrix(matrix: Array) -> Basis:
	if typeof(matrix) != TYPE_ARRAY or matrix.size() != 9:
		return Basis()

	for i in range(9):
		var val = matrix[i]
		if typeof(val) != TYPE_FLOAT and typeof(val) != TYPE_INT:
			return Basis()
		if not is_finite(float(val)):
			return Basis()

	var row0 = Vector3(float(matrix[0]), float(matrix[1]), float(matrix[2]))
	var angle_z = atan2(-row0.y, row0.x)
	var basis_1 = Basis(Vector3.UP, angle_z)

	return basis_1


# ============ COP VISUALIZATION ============

func create_gcop_indicator():
	gcop_indicator = MeshInstance3D.new()
	gcop_indicator.name = "GCoP_Indicator"

	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = GCOP_RADIUS
	sphere_mesh.height = GCOP_RADIUS * 2

	gcop_indicator.mesh = sphere_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = GCOP_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 0.0)
	material.emission_energy = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	gcop_indicator.material_override = material
	platform.add_child(gcop_indicator)
	gcop_indicator.position = Vector3(0, 0.05, 0)
	gcop_indicator.visible = false


func create_local_cop_indicator(index: int) -> MeshInstance3D:
	var indicator = MeshInstance3D.new()
	indicator.name = "LocalCoP_%d" % index

	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	sphere_mesh.height = 0.02

	indicator.mesh = sphere_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = LOCAL_COP_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	indicator.material_override = material
	platform.add_child(indicator)
	indicator.visible = false

	return indicator


func update_cop_from_network(global_script: Node) -> void:
	if not global_script or not is_instance_valid(global_script):
		hide_local_cops()
		if gcop_indicator and is_instance_valid(gcop_indicator):
			gcop_indicator.visible = false
		return

	# Check for local CoPs
	if not "local_cops" in global_script:
		hide_local_cops()
	else:
		var local_cops = global_script.local_cops
		if local_cops != null:
			plot_local_cops(local_cops)
		else:
			hide_local_cops()

	# Check for global CoP
	if not "raw_x" in global_script or not "raw_y" in global_script or not "raw_z" in global_script:
		if gcop_indicator and is_instance_valid(gcop_indicator):
			gcop_indicator.visible = false
		return

	var raw_x = global_script.raw_x
	var raw_y = global_script.raw_y
	var raw_z = global_script.raw_z

	if raw_x != null and raw_y != null and raw_z != null:
		var has_gcop = abs(float(raw_x)) + abs(float(raw_y)) + abs(float(raw_z)) > 0.0001
		if has_gcop:
			var gcop_pos = Vector3(float(raw_x), float(raw_y), float(raw_z))
			plot_gcop(gcop_pos)
		else:
			if gcop_indicator and is_instance_valid(gcop_indicator):
				gcop_indicator.visible = false
	else:
		if gcop_indicator and is_instance_valid(gcop_indicator):
			gcop_indicator.visible = false


func plot_local_cops(local_cops_array):
	if local_cops_array == null or typeof(local_cops_array) != TYPE_ARRAY or local_cops_array.is_empty():
		hide_local_cops()
		return

	var cops_snapshot: Array = local_cops_array.duplicate(false)
	var num_cops: int = cops_snapshot.size()

	while local_cop_indicators.size() < num_cops:
		var new_indicator = create_local_cop_indicator(local_cop_indicators.size())
		local_cop_indicators.append(new_indicator)

	for i in range(num_cops):
		if i >= local_cop_indicators.size():
			break

		var cop_data = cops_snapshot[i]

		if typeof(cop_data) != TYPE_DICTIONARY:
			local_cop_indicators[i].visible = false
			continue

		var x = cop_data.get("x", null)
		var y = cop_data.get("y", null)
		var z = cop_data.get("z", null)
		var weight = cop_data.get("weight", null)

		if x == null or y == null or z == null or weight == null:
			local_cop_indicators[i].visible = false
			continue

		var fx: float = float(x)
		var fy: float = float(y)
		var fz: float = float(z)
		var fw: float = float(weight)

		if not is_finite(fx) or not is_finite(fy) or not is_finite(fz) or not is_finite(fw):
			local_cop_indicators[i].visible = false
			continue

		var cop_pos: Vector3 = Vector3(fx * POSITION_SCALE, fz * POSITION_SCALE, -fy * POSITION_SCALE)

		if not is_position_valid(cop_pos):
			local_cop_indicators[i].visible = false
			continue

		cop_pos.y = 0.03

		local_cop_indicators[i].position = cop_pos
		local_cop_indicators[i].visible = true

		var scale_ = clamp(0.8 + (fw * 0.005), 0.6, 1.4)
		local_cop_indicators[i].scale = Vector3.ONE * scale_

	for i in range(num_cops, local_cop_indicators.size()):
		local_cop_indicators[i].visible = false


func plot_gcop(gcop_raw: Vector3):
	if not gcop_indicator:
		return

	if not is_finite(gcop_raw.x) or not is_finite(gcop_raw.y) or not is_finite(gcop_raw.z):
		gcop_indicator.visible = false
		return

	var gcop_pos = Vector3(gcop_raw.x * POSITION_SCALE, gcop_raw.z * POSITION_SCALE, -gcop_raw.y * POSITION_SCALE)

	if not is_position_valid(gcop_pos):
		gcop_indicator.visible = false
		return

	gcop_pos.y = 0.06

	gcop_indicator.visible = true
	gcop_indicator.position = gcop_pos
	gcop_indicator.scale = Vector3.ONE


func hide_local_cops():
	for indicator in local_cop_indicators:
		if indicator:
			indicator.visible = false


# ============ FULL BODY POSE VISUALIZATION (ULTRA-SAFE) ============

func create_fbp_skeleton():
	fbp_skeleton = Node3D.new()
	fbp_skeleton.name = "FBP_Skeleton"
	platform.add_child(fbp_skeleton)


func create_fbp_joint_indicator(index: int) -> MeshInstance3D:
	if not fbp_skeleton or not is_instance_valid(fbp_skeleton):
		return null

	var indicator = MeshInstance3D.new()
	indicator.name = "FBP_Joint_%d" % index

	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.025
	sphere_mesh.height = 0.055

	indicator.mesh = sphere_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = FBP_JOINT_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.0, 0.598, 0.72, 1.0)
	material.emission_energy = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	indicator.material_override = material
	fbp_skeleton.add_child(indicator)
	indicator.visible = false

	return indicator


# DISABLED: FBP update function - Full Body Pose disabled
# func update_fbp_from_network(global_script: Node) -> void:
# 	"""FBP update with individual point variables (like GCOP - NO RACE CONDITION!)"""
# 	if not global_script or not is_instance_valid(global_script):
# 		hide_fbp()
# 		return
# 	plot_fbp_points(global_script)
#
# DISABLED: FBP plot function - Full Body Pose disabled
# func plot_fbp_points(global_script: Node):
# 	"""Render FBP skeleton from individual point variables (NO ITERATION = NO RACE CONDITION!)"""
# 	# ... function disabled ...



func hide_fbp():
	if not fbp_joint_indicators:
		return

	for joint in fbp_joint_indicators:
		if joint and is_instance_valid(joint):
			joint.visible = false


# ============ BoS (BASE OF SUPPORT) FUNCTIONS (ULTRA-SAFE) ============

func create_bos_container():
	bos_container = Node3D.new()
	bos_container.name = "BoS_Container"
	platform.add_child(bos_container)


func create_bos_point_indicator(is_left: bool, index: int) -> MeshInstance3D:
	if not bos_container or not is_instance_valid(bos_container):
		return null

	var indicator = MeshInstance3D.new()
	var foot_name = "Left" if is_left else "Right"
	indicator.name = "BoS_%s_Point_%d" % [foot_name, index]

	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	sphere_mesh.height = 0.04

	indicator.mesh = sphere_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = BOS_LEFT_COLOR if is_left else BOS_RIGHT_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = BOS_LEFT_COLOR if is_left else BOS_RIGHT_COLOR
	material.emission_energy = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	indicator.material_override = material
	bos_container.add_child(indicator)
	indicator.visible = false

	return indicator


func update_bos_from_network(global_script: Node) -> void:
	"""ULTRA-SAFE BoS update - Simplified with flat arrays (Option A - no race condition!)"""
	if not global_script or not is_instance_valid(global_script):
		hide_bos()
		return

	# Check for flat points arrays
	if not "bos_left_points" in global_script or not "bos_right_points" in global_script:
		hide_bos()
		return

	# Pass global_script itself (not the arrays) to always get fresh references
	plot_bos_points(global_script)


func plot_bos_points(global_script: Node):
	"""Plot BoS foot points - CRITICAL FIX: Snapshot arrays to avoid race condition"""
	if not global_script or not is_instance_valid(global_script):
		hide_bos()
		return

	# CRITICAL FIX: Snapshot arrays BEFORE iteration to avoid race condition
	# This decouples the arrays Godot reads from the ones Python writes to
	var left_foot_points = []
	if "bos_left_points" in global_script:
		var src = global_script.bos_left_points
		if src != null and typeof(src) == TYPE_ARRAY:
			left_foot_points = src.duplicate(false)

	var right_foot_points = []
	if "bos_right_points" in global_script:
		var src = global_script.bos_right_points
		if src != null and typeof(src) == TYPE_ARRAY:
			right_foot_points = src.duplicate(false)

	# LEFT FOOT
	if not left_foot_points.is_empty():
		var num_left = left_foot_points.size()
		while bos_point_indicators_left.size() < num_left:
			var new_indicator = create_bos_point_indicator(true, bos_point_indicators_left.size())
			bos_point_indicators_left.append(new_indicator)

		for i in range(num_left):
			if i >= bos_point_indicators_left.size():
				break
			var indicator = bos_point_indicators_left[i]
			if indicator == null or not is_instance_valid(indicator):
				continue

			var point = null
			var x = null
			var y = null
			var z = null

			# Safe access to snapshot (not being mutated)
			if i < left_foot_points.size():
				point = left_foot_points[i]
				if point != null and typeof(point) == TYPE_ARRAY and point.size() >= 3:
					x = point[0]
					y = point[1]
					z = point[2]

			if point == null or x == null or y == null or z == null:
				indicator.visible = false
				continue

			var fx = float(x)
			var fy = float(y)
			var fz = float(z)
			if not is_finite(fx) or not is_finite(fy) or not is_finite(fz):
				indicator.visible = false
				continue

			var point_pos = Vector3(fx * POSITION_SCALE, fz * POSITION_SCALE, -fy * POSITION_SCALE)
			if not is_position_valid(point_pos):
				indicator.visible = false
				continue

			point_pos.y += 0.01
			indicator.position = point_pos
			indicator.visible = true

		# Hide extras
		for i in range(num_left, bos_point_indicators_left.size()):
			if bos_point_indicators_left[i] and is_instance_valid(bos_point_indicators_left[i]):
				bos_point_indicators_left[i].visible = false
	else:
		for indicator in bos_point_indicators_left:
			if indicator and is_instance_valid(indicator):
				indicator.visible = false

	# RIGHT FOOT (repeat same pattern with snapshot)
	if not right_foot_points.is_empty():
		var num_right = right_foot_points.size()
		while bos_point_indicators_right.size() < num_right:
			var new_indicator = create_bos_point_indicator(false, bos_point_indicators_right.size())
			bos_point_indicators_right.append(new_indicator)

		for i in range(num_right):
			if i >= bos_point_indicators_right.size():
				break
			var indicator = bos_point_indicators_right[i]
			if indicator == null or not is_instance_valid(indicator):
				continue

			var point = null
			var x = null
			var y = null
			var z = null

			# Safe access to snapshot (not being mutated)
			if i < right_foot_points.size():
				point = right_foot_points[i]
				if point != null and typeof(point) == TYPE_ARRAY and point.size() >= 3:
					x = point[0]
					y = point[1]
					z = point[2]

			if point == null or x == null or y == null or z == null:
				indicator.visible = false
				continue

			var fx = float(x)
			var fy = float(y)
			var fz = float(z)
			if not is_finite(fx) or not is_finite(fy) or not is_finite(fz):
				indicator.visible = false
				continue

			var point_pos = Vector3(fx * POSITION_SCALE, fz * POSITION_SCALE, -fy * POSITION_SCALE)
			if not is_position_valid(point_pos):
				indicator.visible = false
				continue

			point_pos.y += 0.01
			indicator.position = point_pos
			indicator.visible = true

		for i in range(num_right, bos_point_indicators_right.size()):
			if bos_point_indicators_right[i] and is_instance_valid(bos_point_indicators_right[i]):
				bos_point_indicators_right[i].visible = false
	else:
		for indicator in bos_point_indicators_right:
			if indicator and is_instance_valid(indicator):
				indicator.visible = false

	# Debug print
	if Engine.get_process_frames() % 100 == 0:
		var left_visible = 0
		var right_visible = 0
		for indicator in bos_point_indicators_left:
			if indicator and is_instance_valid(indicator) and indicator.visible:
				left_visible += 1
		for indicator in bos_point_indicators_right:
			if indicator and is_instance_valid(indicator) and indicator.visible:
				right_visible += 1
		if left_visible > 0 or right_visible > 0:
			print("  🦶 BoS: Left=%d points, Right=%d points" % [left_visible, right_visible])


func hide_bos():
	for indicator in bos_point_indicators_left:
		if indicator and is_instance_valid(indicator):
			indicator.visible = false

	for indicator in bos_point_indicators_right:
		if indicator and is_instance_valid(indicator):
			indicator.visible = false


# ============ UTILITY FUNCTIONS ============

func is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


func is_position_valid(pos: Vector3) -> bool:
	if not is_finite(pos.x) or not is_finite(pos.y) or not is_finite(pos.z):
		return false

	if abs(pos.x) > 5.0 or abs(pos.y) > 5.0 or abs(pos.z) > 5.0:
		return false

	return true


func hide_all_visualizations():
	if gcop_indicator:
		gcop_indicator.visible = false
	hide_local_cops()
	hide_bos()
	# DISABLED: FBP hide - Full Body Pose disabled
	# hide_fbp()
	hide_all_boards()
	previous_board_data_hash = 0
	print("🙈 All visualizations hidden")


func show_all_visualizations():
	"""Re-enable visualization updates after reset"""
	# Note: We don't show indicators here - they show themselves when data arrives
	# This just ensures the update loop will process them
	print("👁️ Visualization updates resumed")


# ============ UI CONTROL FUNCTIONS ============

func create_ui_controls():
	"""Create UI with Reset Board button and recording controls"""
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 1
	add_child(canvas_layer)

	ui_panel = Panel.new()
	ui_panel.anchor_left = 0.75
	ui_panel.anchor_top = 0.0
	ui_panel.anchor_right = 1.0
	ui_panel.anchor_bottom = 1.0
	ui_panel.offset_left = -5
	ui_panel.offset_top = 15
	ui_panel.offset_right = -15
	ui_panel.offset_bottom = -15
	canvas_layer.add_child(ui_panel)

	var panel_bg = StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.15, 0.15, 0.18, 0.95)
	panel_bg.border_color = Color(0.4, 0.6, 0.8, 0.9)
	panel_bg.set_border_width_all(2)
	panel_bg.set_corner_radius_all(8)
	ui_panel.add_theme_stylebox_override("panel", panel_bg)

	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 15
	vbox.offset_top = 15
	vbox.offset_right = -15
	vbox.offset_bottom = -15
	vbox.add_theme_constant_override("separation", 12)
	ui_panel.add_child(vbox)

	var title = Label.new()
	title.text = "MOBBO Controls"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	vbox.add_child(title)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	var vis_label = Label.new()
	vis_label.text = "Visualization"
	vis_label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	vis_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(vis_label)

	var reset_btn = Button.new()
	reset_btn.text = "Reset Board"
	reset_btn.pressed.connect(_on_reset_board_pressed)
	reset_btn.toggle_mode = false
	reset_btn.custom_minimum_size = Vector2(0, 40)

	var btn_stylebox = StyleBoxFlat.new()
	btn_stylebox.bg_color = Color(0.2, 0.4, 0.6, 0.8)
	btn_stylebox.border_color = Color(0.4, 0.7, 1.0)
	btn_stylebox.set_border_width_all(2)
	btn_stylebox.set_corner_radius_all(4)
	reset_btn.add_theme_stylebox_override("normal", btn_stylebox)

	var btn_focused = StyleBoxFlat.new()
	btn_focused.bg_color = Color(0.703, 0.0, 0.392, 0.9)
	btn_focused.border_color = Color(0.6, 0.9, 1.0)
	btn_focused.set_border_width_all(2)
	btn_focused.set_corner_radius_all(4)
	reset_btn.add_theme_stylebox_override("focus", btn_focused)
	reset_btn.add_theme_stylebox_override("pressed", btn_stylebox)

	reset_btn.add_theme_font_size_override("font_size", 12)
	reset_btn.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(reset_btn)

	if not has_meta("reset_btn"):
		set_meta("reset_btn", reset_btn)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var record_label = Label.new()
	record_label.text = "CoP Recording"
	record_label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	record_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(record_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(150, 250)
	vbox.add_child(spacer)


func add_recording_button(ip_address: String):
	"""Dynamically add recording button for board IP"""
	if ip_address in recording_buttons:
		return

	var vbox = ui_panel.get_child(0)

	var btn = Button.new()
	btn.text = "Rec: %s [OFF]" % ip_address
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 32)
	btn.pressed.connect(_on_recording_button_toggled.bind(ip_address))

	var rec_btn_stylebox = StyleBoxFlat.new()
	rec_btn_stylebox.bg_color = Color(0.3, 0.25, 0.2, 0.7)
	rec_btn_stylebox.border_color = Color(0.8, 0.5, 0.3)
	rec_btn_stylebox.set_border_width_all(2)
	rec_btn_stylebox.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", rec_btn_stylebox)
	btn.add_theme_stylebox_override("hover", rec_btn_stylebox)

	var rec_btn_pressed = StyleBoxFlat.new()
	rec_btn_pressed.bg_color = Color(0.6, 0.2, 0.2, 0.8)
	rec_btn_pressed.border_color = Color(1.0, 0.3, 0.3)
	rec_btn_pressed.set_border_width_all(2)
	rec_btn_pressed.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("pressed", rec_btn_pressed)

	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color.WHITE)

	recording_buttons[ip_address] = btn
	recording_states[ip_address] = false

	vbox.add_child(btn)
	vbox.move_child(btn, vbox.get_child_count() - 2)

	print("📍 Added recording button for: %s" % ip_address)


func _on_reset_board_pressed():
	"""Handle Reset Board button - triggers Python reinitialization"""
	var reset_press_ms = Time.get_ticks_msec()
	print("🔄 Resetting board visualization...")
	print("🧭 RESET TRACE: button pressed at t=%d ms frame=%d" % [reset_press_ms, Engine.get_process_frames()])

	var global_script = get_node("/root/GlobalScript")
	if global_script:
		if global_script.has_method("start_reset_trace"):
			global_script.start_reset_trace(reset_press_ms)
			print("🧭 RESET TRACE: counters reset on GlobalScript")
		else:
			print("🧭 RESET TRACE: start_reset_trace() missing on GlobalScript")

	# Hide all visualizations
	if gcop_indicator and is_instance_valid(gcop_indicator):
		gcop_indicator.visible = false
	hide_local_cops()
	# DISABLED: FBP hide - Full Body Pose disabled
	# hide_fbp()
	hide_bos()
	hide_all_boards()

	# CRITICAL FIX: Clear hash to force board re-rendering on next update
	# Without this, identical board positions won't trigger re-render after reset
	previous_board_data_hash = 0
	print("  🧹 Cleared board data hash cache (force next render)")

	for ip in recording_states:
		recording_states[ip] = false
		if ip in recording_buttons:
			recording_buttons[ip].button_pressed = false
			recording_buttons[ip].text = "Rec: %s [OFF]" % ip

	_send_reset_command_to_python()
	print("🧭 RESET TRACE: reset command dispatched to Python")

	# CRITICAL: Wait briefly for Python reset to complete
	# This gives time for new threads to start and board detection to complete
	await get_tree().create_timer(1.0).timeout

	print("✅ Board reset initiated - waiting for fresh data from Python")
	if global_script:
		print("🧭 RESET TRACE: +1s status raw_x=%.4f raw_y=%.4f connected=%s" % [
			float(global_script.raw_x),
			float(global_script.raw_y),
			str(global_script.connected)
		])

	if has_meta("reset_btn"):
		var reset_btn = get_meta("reset_btn")
		if reset_btn and is_instance_valid(reset_btn):
			reset_btn.button_pressed = false
			


func _on_recording_button_toggled(pressed: bool, ip_address: String):
	"""Handle recording toggle"""
	recording_states[ip_address] = pressed
	var btn = recording_buttons[ip_address]

	if pressed:
		btn.text = "Rec: %s [ON]" % ip_address
		btn.add_theme_color_override("font_color", Color.RED)
		print("🔴 Recording started for: %s" % ip_address)
		_send_recording_command(ip_address, true)
	else:
		btn.text = "Rec: %s [OFF]" % ip_address
		btn.remove_theme_color_override("font_color")
		print("⚪ Recording stopped for: %s" % ip_address)
		_send_recording_command(ip_address, false)


func _send_recording_command(ip_address: String, start_recording: bool):
	"""Send recording command to Python"""
	var global_script = get_node("/root/GlobalScript")
	if not global_script:
		return

	var command = {
		"type": "recording_control",
		"ip_address": ip_address,
		"action": "start" if start_recording else "stop"
	}

	if not global_script.get_meta("recording_command", null):
		global_script.set_meta("recording_command", {})

	var rec_cmd = global_script.get_meta("recording_command")
	rec_cmd[ip_address] = command
	global_script.set_meta("recording_command", rec_cmd)


func _send_reset_command_to_python():
	"""Send reset command to Python via UDP port 9000"""
	var reset_command = {
		"type": "reset_board",
		"action": "stop_all_threads",
		"timestamp": Time.get_ticks_msec()
	}

	var command_socket = PacketPeerUDP.new()
	var json_str = JSON.stringify(reset_command)
	print("🧭 RESET TRACE: reset payload = %s" % json_str)

	if command_socket.set_dest_address("127.0.0.1", 9000) == OK:
		var error = command_socket.put_packet(json_str.to_utf8_buffer())
		if error == OK:
			print("✅ Reset command sent to Python")
			print("🧭 RESET TRACE: UDP send OK (bytes=%d)" % json_str.to_utf8_buffer().size())
		else:
			print("❌ Failed to send reset command")
			print("🧭 RESET TRACE: UDP send error code = %d" % error)
	else:
		print("❌ Failed to set destination address")
		print("🧭 RESET TRACE: set_dest_address failed")


func update_detected_boards(board_ips: Array):
	"""Update UI with detected boards"""
	for ip in board_ips:
		if ip not in detected_boards:
			detected_boards.append(ip)
			add_recording_button(ip)


func _exit_tree():
	if gcop_indicator and is_instance_valid(gcop_indicator):
		gcop_indicator.queue_free()

	for indicator in local_cop_indicators:
		if indicator and is_instance_valid(indicator):
			indicator.queue_free()

	for joint in fbp_joint_indicators:
		if joint and is_instance_valid(joint):
			joint.queue_free()

	if bos_container and is_instance_valid(bos_container):
		bos_container.queue_free()

	local_cop_indicators.clear()
	fbp_joint_indicators.clear()
