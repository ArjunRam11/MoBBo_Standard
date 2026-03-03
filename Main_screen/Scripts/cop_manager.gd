extends Node

const BOARD_DATA_PORT_BASE := 8000
const MAX_BOARDS := 6

const DATA_HEADER_SIZE := 11 * 4

var board_ips: Array = []
var board_layout: String = ""
var board_count: int = 0

var udp_sockets: Array = []
var is_listening: bool = false

var combined_cop: Vector3 = Vector3.ZERO
var combined_weight: float = 0.0
var local_cops: Array = []

var cop_x_min: float = 0.30
var cop_x_max: float = -0.30
var cop_y_min: float = -0.225
var cop_y_max: float = 0.675

var scaled_position: Vector2 = Vector2.ZERO
var scaled_position3D: Vector2 = Vector2.ZERO
var raw_position: Vector3 = Vector3.ZERO

signal data_updated(cop: Vector3, weight: float)

func _ready() -> void:
	_load_saved_config()

func _load_saved_config() -> void:
	if FileAccess.file_exists("user://board_config.json"):
		var file = FileAccess.open("user://board_config.json", FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		var data = JSON.parse_string(content)
		if data and typeof(data) == TYPE_DICTIONARY:
			_apply_config(data)
			print("✅ CoPManager loaded saved config")

func _apply_config(cfg: Dictionary) -> void:
	board_layout = cfg.get("layout", "")
	board_count = cfg.get("boards", 0)
	
	var assignments = cfg.get("assignments", [])
	board_ips.clear()
	for a in assignments:
		board_ips.append(a.get("ip", ""))
	
	_start_listening()

func set_board_config(layout: String, assignments: Array) -> void:
	board_layout = layout
	board_count = assignments.size()
	
	board_ips.clear()
	for a in assignments:
		board_ips.append(a.get("ip", ""))
	
	_save_config(layout, assignments)
	_start_listening()

func _save_config(layout: String, assignments: Array) -> void:
	var cfg = {
		"layout": layout,
		"boards": assignments.size(),
		"assignments": assignments
	}
	var file = FileAccess.open("user://board_config.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(cfg))
	file.close()
	print("✅ CoPManager config saved")

func _start_listening() -> void:
	if is_listening:
		_stop_listening()
	
	if board_ips.is_empty():
		print("⚠️ No board IPs configured")
		return
	
	for i in range(MAX_BOARDS):
		var socket = PacketPeerUDP.new()
		udp_sockets.append(socket)
	
	for i in range(board_ips.size()):
		if board_ips[i] != "":
			var port = BOARD_DATA_PORT_BASE + i
			if udp_sockets[i].bind(port, "0.0.0.0") == OK:
				print("✅ CoPManager bound to port %d for board %d" % [port, i])
			else:
				print("❌ Failed to bind port %d" % port)
	
	is_listening = true

func _stop_listening() -> void:
	for socket in udp_sockets:
		if socket:
			socket.close()
	udp_sockets.clear()
	is_listening = false

func _process(_delta: float) -> void:
	if not is_listening:
		return
	
	combined_cop = Vector3.ZERO
	combined_weight = 0.0
	local_cops.clear()
	
	var valid_boards = 0
	
	for i in range(udp_sockets.size()):
		var socket = udp_sockets[i]
		if socket and socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			
			if packet.size() < DATA_HEADER_SIZE:
				continue
			
			var cop_data = _parse_binary_packet(packet)
			if cop_data.size() == 0:
				continue
			
			var cop_x = cop_data[0]
			var cop_y = cop_data[1]
			var weight = cop_data[2]
			
			if weight > 0:
				combined_cop += Vector3(cop_x, cop_y, 0.0) * weight
				combined_weight += weight
				valid_boards += 1
				
				local_cops.append({
					"x": cop_x,
					"y": cop_y,
					"z": 0.0,
					"weight": weight,
					"board": i
				})
	
	if combined_weight > 0:
		combined_cop = combined_cop / combined_weight
		raw_position = combined_cop
		
		_normalize_and_scale()
		data_updated.emit(combined_cop, combined_weight)

func _parse_binary_packet(packet: PackedByteArray) -> Array:
	if packet.size() < DATA_HEADER_SIZE:
		return []
	
	var data_bytes = packet.slice(4)
	var floats = data_bytes.decode_float32(0)
	
	if floats.size() < 7:
		return []
	
	var f1 = floats[0]
	var f2 = floats[1]
	var f3 = floats[2]
	var f4 = floats[3]
	var cop_x = floats[4]
	var cop_y = floats[5]
	var w_sync = floats[6]
	
	var weight = f1 + f2 + f3 + f4
	
	return [cop_x, cop_y, weight, w_sync]

func _normalize_and_scale() -> void:
	var norm_x = (combined_cop.x - cop_x_min) / (cop_x_max - cop_x_min) if cop_x_max != cop_x_min else 0.5
	var norm_y = (combined_cop.y - cop_y_min) / (cop_y_max - cop_y_min) if cop_y_max != cop_y_min else 0.5
	
	norm_x = clampf(norm_x, 0.0, 1.0)
	norm_y = clampf(norm_y, 0.0, 1.0)
	
	var screen_size = DisplayServer.screen_get_size()
	var screen_width = screen_size.x
	var screen_height = screen_size.y
	
	scaled_position = Vector2(
		norm_x * screen_width,
		norm_y * screen_height
	)
	
	scaled_position3D = Vector2(
		norm_x * screen_width,
		(1.0 - norm_y) * screen_height
	)

func get_combined_cop() -> Vector3:
	return combined_cop

func get_scaled_position_2d() -> Vector2:
	return scaled_position

func get_scaled_position_3d() -> Vector2:
	return scaled_position3D

func is_configured() -> bool:
	return not board_ips.is_empty() and is_listening

func get_board_count() -> int:
	return board_count

func shutdown() -> void:
	_stop_listening()
