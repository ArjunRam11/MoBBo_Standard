# cop_manager.gd  — Autoload singleton
# ══════════════════════════════════════════════════════════════════════════════
#
# PHYSICAL MODEL
# ──────────────
# Each balance board measures CoP in its own local frame:
#   X : -30 cm  ..  +30 cm  (left–right on the board)
#   Y : -22.5 cm .. +22.5 cm (front–back on the board)
#
# Board dimensions:  WIDTH = 60 cm,  HEIGHT = 45 cm
# Reference: top-left board (row 0, col 0) is the global origin.
#
# Layout string "ColsxRows" e.g. "1x2" = 1 col, 2 rows (LEFT / RIGHT side-by-side)
#   • Column offset per board = col_index × BOARD_WIDTH_CM
#   • Row    offset per board = row_index × BOARD_HEIGHT_CM
#
# Combined CoP formula (weighted average with physical offsets):
#
#   global_x = Σ( w_i × (cop_x_i + col_i × WIDTH)  ) / Σ w_i
#   global_y = Σ( w_i × (cop_y_i + row_i × HEIGHT) ) / Σ w_i
#
# The result is in cm, in the global frame whose origin is the
# centre of the top-left board.
#
# Normalisation maps [global_x_min .. global_x_max] → [0..1]
# and feeds scaled_position (2D) and scaled_position3D (3D games).
#
# ══════════════════════════════════════════════════════════════════════════════

extends Node

# ── Physical constants (cm) ───────────────────────────────────────────────────
const BOARD_W  : float = 60.0    # board width  in cm  (X axis)
const BOARD_H  : float = 45.0    # board height in cm  (Y axis)
const HALF_W   : float = BOARD_W / 2.0   # 30 cm
const HALF_H   : float = BOARD_H / 2.0   # 22.5 cm

# ── Network ───────────────────────────────────────────────────────────────────
const BOARD_DATA_PORT : int = 8000   # all boards stream to this port
const BOARD_CMD_PORT  : int = 23000  # LED / command port on the board side

# Packet layout:  4 header bytes  +  7 × float32  = 32 bytes
# Floats: t, f1, f2, f3, f4, cop_x, cop_y
const PACKET_SIZE   : int = 32
const HEADER_BYTES  : int = 4
const FLOAT_COUNT   : int = 7

# ── Public state (read by GlobalScript / games every frame) ───────────────────
var combined_cop    : Vector3 = Vector3.ZERO   # cm, global frame
var combined_weight : float   = 0.0
var local_cops      : Array   = []             # per-board local CoP dicts
var global_cop_cm   : Vector2 = Vector2.ZERO   # convenient 2-D alias (cm)

var scaled_position   : Vector2 = Vector2.ZERO  # 2-D games  (pixels)
var scaled_position3D : Vector2 = Vector2.ZERO  # 3-D games  (pixels, Y flipped)
var raw_position      : Vector3 = Vector3.ZERO  # same as combined_cop

# ── Board configuration ───────────────────────────────────────────────────────
var board_layout  : String = ""
var board_count   : int    = 0
var board_ips     : Array  = []   # ordered list: index → IP string
var assignments   : Array  = []   # [{slot, serial, ip}]

# Layout grid dimensions (parsed from layout id string e.g. "2x3")
var _n_cols : int = 1
var _n_rows : int = 1

# CoP global range (cm) — computed from layout
var _x_min : float = -HALF_W
var _x_max : float =  HALF_W
var _y_min : float = -HALF_H
var _y_max : float =  HALF_H

# ── Internal ──────────────────────────────────────────────────────────────────
var _udp      : PacketPeerUDP = PacketPeerUDP.new()
var _udp_cmd  : PacketPeerUDP = PacketPeerUDP.new()
var is_listening : bool = false

# Per-board cache: ip → {cop_x, cop_y, weight}  (last received packet)
var _cache : Dictionary = {}

# Throttle debug prints
var _print_counter : int = 0
const PRINT_EVERY  : int = 60   # frames

signal data_updated(cop: Vector3, weight: float)

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_load_saved_config()

# ══════════════════════════════════════════════════════════════════════════════
#  CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

func set_board_config(layout_id: String, assign_array: Array) -> void:
	"""Called by BoardSetup after the user confirms assignments."""
	board_layout = layout_id
	assignments  = assign_array.duplicate(true)
	board_count  = assignments.size()
	board_ips.clear()
	for a in assignments:
		board_ips.append(a.get("ip", ""))

	_parse_layout(layout_id)
	_compute_ranges()
	_save_config()
	_start_listening()

	print("✅ CoPManager configured — layout=%s  cols=%d  rows=%d  boards=%d" \
		% [layout_id, _n_cols, _n_rows, board_count])
	print("   X range: %.1f .. %.1f cm   Y range: %.1f .. %.1f cm" \
		% [_x_min, _x_max, _y_min, _y_max])

func _parse_layout(layout_id: String) -> void:
	# Layout id format: "ColsxRows"  e.g. "1x2", "2x3", "6x1"
	var parts := layout_id.split("x")
	if parts.size() == 2:
		_n_cols = int(parts[1])
		_n_rows = int(parts[0])
	else:
		_n_cols = 1
		_n_rows = 1

func _compute_ranges() -> void:
	# Global CoP can span from the left/top edge of board[0,0]
	# to the right/bottom edge of board[n_cols-1, n_rows-1].
	# Board origin = board centre, so:
	#   min_x = -HALF_W  (left edge of col 0)
	#   max_x = (n_cols-1)*BOARD_W + HALF_W  (right edge of last col)
	_x_min = -HALF_W
	_x_max =  (_n_cols - 1) * BOARD_W + HALF_W
	_y_min = -HALF_H
	_y_max =  (_n_rows - 1) * BOARD_H + HALF_H

func _apply_config(cfg: Dictionary) -> void:
	board_layout = cfg.get("layout", "")
	board_count  = cfg.get("boards", 0)
	assignments  = cfg.get("assignments", []).duplicate(true)
	board_ips.clear()
	for a in assignments:
		board_ips.append(a.get("ip", ""))
	_parse_layout(board_layout)
	_compute_ranges()
	_start_listening()

func _load_saved_config() -> void:
	if FileAccess.file_exists("user://board_config.json"):
		var file : FileAccess = FileAccess.open("user://board_config.json", FileAccess.READ)
		var data  : Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if data and typeof(data) == TYPE_DICTIONARY:
			_apply_config(data)
			print("✅ CoPManager: loaded saved config  layout=%s  boards=%d" \
				% [board_layout, board_count])

func _save_config() -> void:
	var cfg := { "layout": board_layout, "boards": board_count, "assignments": assignments }
	var file : FileAccess = FileAccess.open("user://board_config.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(cfg))
	file.close()

# ══════════════════════════════════════════════════════════════════════════════
#  UDP LISTEN
# ══════════════════════════════════════════════════════════════════════════════

func _start_listening() -> void:
	_stop_listening()
	if board_ips.is_empty():
		print("⚠️ CoPManager: no board IPs — not listening")
		return
	if _udp.bind(BOARD_DATA_PORT, "0.0.0.0") == OK:
		is_listening = true
		print("✅ CoPManager listening on 0.0.0.0:%d" % BOARD_DATA_PORT)
	else:
		print("❌ CoPManager failed to bind port %d" % BOARD_DATA_PORT)

func _stop_listening() -> void:
	if is_listening:
		_udp.close()
		is_listening = false
	_cache.clear()

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN LOOP
# ══════════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	if not is_listening:
		return

	# Drain all waiting packets
	while _udp.get_available_packet_count() > 0:
		var pkt       : PackedByteArray = _udp.get_packet()
		var sender_ip : String          = _udp.get_packet_ip()
		_handle_packet(pkt, sender_ip)

	# Recompute global CoP from per-board cache every frame
	_recompute_combined()

# ── Packet parsing ────────────────────────────────────────────────────────────

func _handle_packet(pkt: PackedByteArray, sender_ip: String) -> void:
	if sender_ip not in board_ips:
		return
	if pkt.size() < PACKET_SIZE:
		return

	# Decode 7 floats after the 4-byte header
	var floats : Array = []
	for i in range(FLOAT_COUNT):
		floats.append(pkt.decode_float(HEADER_BYTES + i * 4))

	# t=floats[0]  (timestamp, unused here)
	var f1    : float = floats[1]
	var f2    : float = floats[2]
	var f3    : float = floats[3]
	var f4    : float = floats[4]
	var cop_x : float = floats[5]   # cm, board local frame
	var cop_y : float = floats[6]   # cm, board local frame
	var weight: float = f1 + f2 + f3 + f4

	if not (is_finite(cop_x) and is_finite(cop_y) and is_finite(weight)):
		return

	_cache[sender_ip] = { "cop_x": cop_x, "cop_y": cop_y, "weight": weight }

# ══════════════════════════════════════════════════════════════════════════════
#  COMBINED CoP  —  PHYSICS-CORRECT FORMULA
# ══════════════════════════════════════════════════════════════════════════════
#
#  Boards are arranged in a grid.  The assignment list is ordered:
#    index 0 = col 0, row 0  (top-left / reference origin)
#    index 1 = col 1, row 0  (next column in same row)
#    ...
#    index n_cols = col 0, row 1
#
#  For board at (col, row):
#    offset_x = col × BOARD_W   (cm from reference centre)
#    offset_y = row × BOARD_H   (cm from reference centre)
#
#  Combined CoP:
#    sum_wx = Σ  w_i × (cop_x_i + offset_x_i)
#    sum_wy = Σ  w_i × (cop_y_i + offset_y_i)
#    W      = Σ  w_i
#    global_cop_x = sum_wx / W
#    global_cop_y = sum_wy / W
#
# ══════════════════════════════════════════════════════════════════════════════

func _recompute_combined() -> void:
	var sum_wx     : float = 0.0
	var sum_wy     : float = 0.0
	var total_w    : float = 0.0
	local_cops.clear()

	for i in range(board_ips.size()):
		var ip : String = board_ips[i]
		if ip == "" or not _cache.has(ip):
			continue

		var entry  : Dictionary = _cache[ip]
		var lx     : float = float(entry["cop_x"])   # local CoP X (cm)
		var ly     : float = float(entry["cop_y"])   # local CoP Y (cm)
		var w      : float = float(entry["weight"])

		# Grid position of this board
		var col : int = i % _n_cols
		var row : int = i / _n_cols

		# Physical offset of this board's centre from the reference board
		var offset_x : float = col * BOARD_W   # cm
		var offset_y : float = row * BOARD_H   # cm

		# Accumulate weighted global coords
		sum_wx  += w * (lx + offset_x)
		sum_wy  += w * (ly + offset_y)
		total_w += w

		# Store local CoP info (games can read this per-board)
		local_cops.append({
			"ip":       ip,
			"board_idx": i,
			"col":      col,
			"row":      row,
			"slot":     assignments[i].get("slot", str(i + 1)) if i < assignments.size() else str(i + 1),
			"cop_x_local":  lx,    # cm, board frame
			"cop_y_local":  ly,    # cm, board frame
			"cop_x_global": lx + offset_x,  # cm, global frame
			"cop_y_global": ly + offset_y,  # cm, global frame
			"weight":   w,
			"offset_x": offset_x,
			"offset_y": offset_y
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

		# ── Debug print (throttled) ───────────────────────────────
		_print_counter += 1
		if _print_counter >= PRINT_EVERY:
			_print_counter = 0
			_debug_print()
	else:
		combined_cop    = Vector3.ZERO
		combined_weight = 0.0
		global_cop_cm   = Vector2.ZERO

# ── Debug print ───────────────────────────────────────────────────────────────

func _debug_print() -> void:
	print("─── CoPManager ─── layout=%s  cols=%d  rows=%d ───" \
		% [board_layout, _n_cols, _n_rows])
	for lc in local_cops:
		print("  Board[%d] slot=%-10s  col=%d row=%d  offset=(%.1f, %.1f) cm" \
			% [lc["board_idx"], lc["slot"], lc["col"], lc["row"],
			   lc["offset_x"], lc["offset_y"]])
		print("         local  CoP: (%.3f, %.3f) cm   weight=%.2f" \
			% [lc["cop_x_local"], lc["cop_y_local"], lc["weight"]])
		print("         global CoP: (%.3f, %.3f) cm" \
			% [lc["cop_x_global"], lc["cop_y_global"]])
	print("  ► COMBINED global CoP: (%.3f, %.3f) cm   total_weight=%.2f" \
		% [combined_cop.x, combined_cop.y, combined_weight])
	print("  ► scaled 2D: (%.1f, %.1f) px   3D: (%.1f, %.1f) px" \
		% [scaled_position.x, scaled_position.y,
		   scaled_position3D.x, scaled_position3D.y])

# ══════════════════════════════════════════════════════════════════════════════
#  NORMALISE + SCALE  →  SCREEN PIXELS
# ══════════════════════════════════════════════════════════════════════════════

func _normalize_and_scale() -> void:
	var x_range : float = _x_max - _x_min
	var y_range : float = _y_max - _y_min

	var norm_x := 0.5 if x_range == 0.0 else (combined_cop.x - _x_min) / x_range
	var norm_y := 0.5 if y_range == 0.0 else (combined_cop.y - _y_min) / y_range

	norm_x = clampf(norm_x, 0.0, 1.0)
	norm_y = clampf(norm_y, 0.0, 1.0)

	var ss : Vector2i = DisplayServer.screen_get_size()

	# 2-D games: Y increases downward (top = low CoP Y)
	scaled_position = Vector2(norm_x * ss.x, norm_y * ss.y)

	# 3-D games: Y flipped (higher CoP Y = higher on screen)
	scaled_position3D = Vector2(norm_x * ss.x, (1.0 - norm_y) * ss.y)

# ══════════════════════════════════════════════════════════════════════════════
#  PUBLIC GETTERS  (used by GlobalScript + every game)
# ══════════════════════════════════════════════════════════════════════════════

func get_combined_cop() -> Vector3:
	return combined_cop            # cm, global frame

func get_global_cop_cm() -> Vector2:
	return global_cop_cm           # convenience 2-D (cm)

func get_scaled_position_2d() -> Vector2:
	return scaled_position         # pixels

func get_scaled_position_3d() -> Vector2:
	return scaled_position3D       # pixels

func get_local_cop(board_idx: int) -> Dictionary:
	if board_idx < local_cops.size():
		return local_cops[board_idx]
	return {}

func get_local_cops() -> Array:
	return local_cops

func is_configured() -> bool:
	return not board_ips.is_empty() and is_listening

func get_board_count() -> int:
	return board_count

func get_layout_range_x() -> Vector2:
	return Vector2(_x_min, _x_max)   # cm

func get_layout_range_y() -> Vector2:
	return Vector2(_y_min, _y_max)   # cm

# ══════════════════════════════════════════════════════════════════════════════
#  LED  (unicast to board's command port)
# ══════════════════════════════════════════════════════════════════════════════

func send_led(ip: String, on: bool) -> void:
	_udp_cmd.set_dest_address(ip, BOARD_CMD_PORT)
	_udp_cmd.put_packet(PackedByteArray([0x10 if on else 0x20]))

# ══════════════════════════════════════════════════════════════════════════════
#  SHUTDOWN
# ══════════════════════════════════════════════════════════════════════════════

func shutdown() -> void:
	_stop_listening()
