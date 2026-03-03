# cop_manager.gd — Autoload singleton
# Computation only during setup. After confirm, also owns the UDP socket
# and polls it every frame to keep feeding data to games.
# ══════════════════════════════════════════════════════════════════════════════

extends Node

const BOARD_W : float = 60.0
const BOARD_H : float = 45.0
const HALF_W  : float = BOARD_W / 2.0
const HALF_H  : float = BOARD_H / 2.0

# Packet layout: 4 header bytes + 7 floats × 4 = 32 bytes
const PACKET_SIZE  : int = 32
const HEADER_BYTES : int = 4
const FLOAT_COUNT  : int = 7

# ── Public state ──────────────────────────────────────────────────────────────
var combined_cop    : Vector3 = Vector3.ZERO
var combined_weight : float   = 0.0
var local_cops      : Array   = []
var global_cop_cm   : Vector2 = Vector2.ZERO
var scaled_position   : Vector2 = Vector2.ZERO
var scaled_position3D : Vector2 = Vector2.ZERO
var raw_position      : Vector3 = Vector3.ZERO

# ── Board configuration ───────────────────────────────────────────────────────
var board_layout : String = ""
var board_count  : int    = 0
var board_ips    : Array  = []
var assignments  : Array  = []
var _n_cols      : int    = 1
var _n_rows      : int    = 1
var _x_min : float = -HALF_W;  var _x_max : float = HALF_W
var _y_min : float = -HALF_H;  var _y_max : float = HALF_H

# ── UDP socket (handed over from BoardSetupScene after confirm) ───────────────
var _udp         : PacketPeerUDP = null
var _owns_socket : bool          = false

# ── Cache: ip → {cop_x, cop_y, weight} ───────────────────────────────────────
var _cache             : Dictionary = {}
var is_configured_flag : bool       = false

var _print_counter : int = 0
const PRINT_EVERY  : int = 200

signal data_updated(cop: Vector3, weight: float)

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_load_saved_config()

# ══════════════════════════════════════════════════════════════════════════════
#  PROCESS — poll socket (when we own it) + recompute
# ══════════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	if not is_configured_flag: return

	# Poll UDP if we own the socket (during gameplay, after handoff)
	if _owns_socket and _udp != null:
		while _udp.get_available_packet_count() > 0:
			var pkt : PackedByteArray = _udp.get_packet()
			var ip  : String          = _udp.get_packet_ip()
			if ip in board_ips and pkt.size() >= PACKET_SIZE:
				_parse_packet(pkt, ip)

	_recompute_combined()

# ── Parse a CoP packet ────────────────────────────────────────────────────────
func _parse_packet(pkt: PackedByteArray, ip: String) -> void:
	var floats : Array = []
	for i in range(FLOAT_COUNT):
		floats.append(pkt.decode_float(HEADER_BYTES + i * 4))
	var f1    : float = floats[1]; var f2 : float = floats[2]
	var f3    : float = floats[3]; var f4 : float = floats[4]
	var cop_x : float = floats[5]; var cop_y : float = floats[6]
	var weight: float = f1 + f2 + f3 + f4
	if not (is_finite(cop_x) and is_finite(cop_y) and is_finite(weight)): return
	_cache[ip] = { "cop_x": cop_x, "cop_y": cop_y, "weight": weight }

# ══════════════════════════════════════════════════════════════════════════════
#  FEED — called by BoardSetupScene during setup phase
# ══════════════════════════════════════════════════════════════════════════════
func feed_board_data(ip: String, cop_x: float, cop_y: float, weight: float) -> void:
	if ip not in board_ips: return
	_cache[ip] = { "cop_x": cop_x, "cop_y": cop_y, "weight": weight }

func clear_data() -> void:
	_cache.clear()
	combined_cop    = Vector3.ZERO
	combined_weight = 0.0
	global_cop_cm   = Vector2.ZERO
	local_cops.clear()
	_release_socket()

# ══════════════════════════════════════════════════════════════════════════════
#  CONFIGURATION — called with socket handoff on confirm
# ══════════════════════════════════════════════════════════════════════════════
func set_board_config(layout_id: String, assign_array: Array, udp_socket: PacketPeerUDP = null) -> void:
	board_layout = layout_id
	assignments  = assign_array.duplicate(true)
	board_count  = assignments.size()
	board_ips.clear()
	for a in assignments: board_ips.append(a.get("ip", ""))
	_parse_layout(layout_id)
	_compute_ranges()
	_cache.clear()
	is_configured_flag = true

	# Take ownership of the socket so we keep polling during gameplay
	if udp_socket != null:
		_udp        = udp_socket
		_owns_socket = true
		print("✅ CoPManager: socket handed over, will poll during gameplay")

	_save_config()
	print("✅ CoPManager configured — layout=%s  boards=%d" % [layout_id, board_count])
	for ip in board_ips: print("   board ip: %s" % ip)

func _release_socket() -> void:
	if _owns_socket and _udp != null:
		_udp.close()
	_udp         = null
	_owns_socket = false

func _apply_config(cfg: Dictionary) -> void:
	board_layout = cfg.get("layout", "")
	board_count  = cfg.get("boards", 0)
	assignments  = cfg.get("assignments", []).duplicate(true)
	board_ips.clear()
	for a in assignments: board_ips.append(a.get("ip", ""))
	_parse_layout(board_layout)
	_compute_ranges()
	if not board_ips.is_empty(): is_configured_flag = true

func _load_saved_config() -> void:
	if FileAccess.file_exists("user://board_config.json"):
		var file := FileAccess.open("user://board_config.json", FileAccess.READ)
		var data : Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if data and typeof(data) == TYPE_DICTIONARY:
			_apply_config(data)
			print("✅ CoPManager: loaded saved config  layout=%s  boards=%d" % [board_layout, board_count])

func _save_config() -> void:
	var cfg := { "layout": board_layout, "boards": board_count, "assignments": assignments }
	var file := FileAccess.open("user://board_config.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(cfg))
	file.close()

func _parse_layout(layout_id: String) -> void:
	var parts := layout_id.split("x")
	if parts.size() == 2: _n_cols = int(parts[1]); _n_rows = int(parts[0])
	else: _n_cols = 1; _n_rows = 1

func _compute_ranges() -> void:
	_x_min = -HALF_W;  _x_max = (_n_cols - 1) * BOARD_W + HALF_W
	_y_min = -HALF_H;  _y_max = (_n_rows - 1) * BOARD_H + HALF_H

# ══════════════════════════════════════════════════════════════════════════════
#  COMBINED CoP
# ══════════════════════════════════════════════════════════════════════════════
func _recompute_combined() -> void:
	var sum_wx : float = 0.0; var sum_wy : float = 0.0; var total_w : float = 0.0
	local_cops.clear()
	for i in range(board_ips.size()):
		var ip : String = board_ips[i]
		if ip == "" or not _cache.has(ip): continue
		var entry    : Dictionary = _cache[ip]
		var lx       : float = float(entry["cop_x"])
		var ly       : float = float(entry["cop_y"])
		var w        : float = float(entry["weight"])
		var col      : int   = i % _n_cols
		var row      : int   = i / _n_cols
		var offset_x : float = col * BOARD_W
		var offset_y : float = row * BOARD_H
		sum_wx  += w * (lx + offset_x)
		sum_wy  += w * (ly + offset_y)
		total_w += w
		local_cops.append({
			"ip": ip, "board_idx": i, "col": col, "row": row,
			"slot": assignments[i].get("slot", str(i+1)) if i < assignments.size() else str(i+1),
			"cop_x_local":  lx,             "cop_y_local":  ly,
			"cop_x_global": lx + offset_x,  "cop_y_global": ly + offset_y,
			"weight": w, "offset_x": offset_x, "offset_y": offset_y
		})
	if total_w > 0.0:
		var gx : float = sum_wx / total_w
		var gy : float = sum_wy / total_w
		combined_cop    = Vector3(gx, gy, 0.0)
		combined_weight = total_w
		global_cop_cm   = Vector2(gx, gy)
		raw_position    = combined_cop
		_normalize_and_scale()
		data_updated.emit(combined_cop, combined_weight)
		_print_counter += 1
		if _print_counter >= PRINT_EVERY:
			_print_counter = 0
			print("CoPManager combined=(%.2f,%.2f)cm  w=%.2f  2D=(%.0f,%.0f)px" \
				% [gx, gy, total_w, scaled_position.x, scaled_position.y])
	else:
		combined_cop    = Vector3.ZERO
		combined_weight = 0.0
		global_cop_cm   = Vector2.ZERO

func _normalize_and_scale() -> void:
	var x_range : float = _x_max - _x_min
	var y_range : float = _y_max - _y_min
	var norm_x := 0.5 if x_range == 0.0 else (combined_cop.x - _x_min) / x_range
	var norm_y := 0.5 if y_range == 0.0 else (combined_cop.y - _y_min) / y_range
	norm_x = clampf(norm_x, 0.0, 1.0)
	norm_y = clampf(norm_y, 0.0, 1.0)
	var ss : Vector2i = DisplayServer.screen_get_size()
	scaled_position   = Vector2(norm_x * ss.x, norm_y * ss.y)
	scaled_position3D = Vector2(norm_x * ss.x, (1.0 - norm_y) * ss.y)

# ══════════════════════════════════════════════════════════════════════════════
#  PUBLIC GETTERS  (GlobalScript + all games read these)
# ══════════════════════════════════════════════════════════════════════════════
func get_combined_cop() -> Vector3:       return combined_cop
func get_global_cop_cm() -> Vector2:      return global_cop_cm
func get_scaled_position_2d() -> Vector2: return scaled_position
func get_scaled_position_3d() -> Vector2: return scaled_position3D
func get_local_cops() -> Array:           return local_cops
func get_board_count() -> int:            return board_count
func get_layout_range_x() -> Vector2:     return Vector2(_x_min, _x_max)
func get_layout_range_y() -> Vector2:     return Vector2(_y_min, _y_max)
func get_local_cop(board_idx: int) -> Dictionary:
	return local_cops[board_idx] if board_idx < local_cops.size() else {}
func is_configured() -> bool:
	return is_configured_flag and not board_ips.is_empty()

# ══════════════════════════════════════════════════════════════════════════════
#  SHUTDOWN
# ══════════════════════════════════════════════════════════════════════════════
func shutdown() -> void:
	clear_data()
	is_configured_flag = false
