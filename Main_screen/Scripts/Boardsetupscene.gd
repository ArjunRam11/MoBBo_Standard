# Boardsetupscene.gd
# ══════════════════════════════════════════════════════════════════════════════
# FLOW:
#   1. SCAN  — broadcast "Hey!mobbos" on port 23000, collect reply IPs
#   2. STREAM — boards stream CoP data back to port 23000 (same socket)
#              live CoP printed per board in UI
#   3. ASSIGN — flash LED → click slot on grid
#   4. CONFIRM — hand layout + assignments to CoPManager, go to Games
#
# Buttons:  🔍 Scan | ⏹ Stop | 🔌 Disconnect | ✅ Confirm | 🎮 Games
# ══════════════════════════════════════════════════════════════════════════════

extends Control

# ── Network constants ─────────────────────────────────────────────────────────
const BOARD_PORT    : int    = 23000
const BROADCAST_IP  : String = "192.168.0.255"
const DISCOVERY_MSG : String = "Hey!mobbos"
const LED_ON_BYTE   : int    = 0x21
const LED_OFF_BYTE  : int    = 0x20
const STREAM_ON     : int    = 0x31   # firmware: start streaming
const STREAM_OFF    : int    = 0x30   # firmware: stop streaming
const SCAN_SECS     : float  = 4.0

# Packet: 4 header bytes + 7 floats × 4 = 32 bytes
const PACKET_SIZE  : int = 32
const HEADER_BYTES : int = 4
const FLOAT_COUNT  : int = 7

# ── UDP ───────────────────────────────────────────────────────────────────────
var udp       : PacketPeerUDP = PacketPeerUDP.new()
var _bound    : bool = false
var _scanning : bool = false
var _streaming: bool = false
var _handed_off : bool = false

# ── Layout definitions ────────────────────────────────────────────────────────
var LAYOUTS : Array = [
  { "id":"1x2","label":"1 × 2  (Left / Right)",  "cols":2,"rows":1,"boards":2, "slots":["LEFT","RIGHT"] },
  { "id":"2x1","label":"2 × 1  (Top / Bottom)",  "cols":1,"rows":2,"boards":2, "slots":["TOP","BOTTOM"] },
  { "id":"1x3","label":"1 × 3  (3 columns)",     "cols":3,"rows":1,"boards":3, "slots":["LEFT","CENTER","RIGHT"] },
  { "id":"3x1","label":"3 × 1  (3 rows)",        "cols":1,"rows":3,"boards":3, "slots":["TOP","MIDDLE","BOTTOM"] },
  { "id":"2x2","label":"2 × 2  (Grid)",          "cols":2,"rows":2,"boards":4, "slots":["TOP-LEFT","TOP-RIGHT","BOT-LEFT","BOT-RIGHT"] },
  { "id":"1x4","label":"1 × 4  (4 columns)",     "cols":4,"rows":1,"boards":4, "slots":["1","2","3","4"] },
  { "id":"4x1","label":"4 × 1  (4 rows)",        "cols":1,"rows":4,"boards":4, "slots":["1","2","3","4"] },
  { "id":"1x5","label":"1 × 5  (5 columns)",     "cols":5,"rows":1,"boards":5, "slots":["1","2","3","4","5"] },
  { "id":"5x1","label":"5 × 1  (5 rows)",        "cols":1,"rows":5,"boards":5, "slots":["1","2","3","4","5"] },
  { "id":"2x3","label":"2 × 3  (2r × 3c)",       "cols":3,"rows":2,"boards":6, "slots":["R1C1","R1C2","R1C3","R2C1","R2C2","R2C3"] },
  { "id":"3x2","label":"3 × 2  (3r × 2c)",       "cols":2,"rows":3,"boards":6, "slots":["R1C1","R1C2","R2C1","R2C2","R3C1","R3C2"] },
  { "id":"1x6","label":"1 × 6  (6 columns)",     "cols":6,"rows":1,"boards":6, "slots":["1","2","3","4","5","6"] },
  { "id":"6x1","label":"6 × 1  (6 rows)",        "cols":1,"rows":6,"boards":6, "slots":["1","2","3","4","5","6"] },
]

# ── State ─────────────────────────────────────────────────────────────────────
var layout          : Dictionary = {}
var discovered      : Array      = []   # [{serial, ip}]
var slot_assigned   : Array      = []   # slot_idx → serial (0 = empty)
var flashing_serial : int        = 0
var pending_serial  : int        = 0
var confirmed       : bool       = false
var slot_rects      : Array      = []

# Live CoP data per discovered board: ip → {cop_x, cop_y, weight, f1..f4}
var _board_data     : Dictionary = {}

# ── UI references ─────────────────────────────────────────────────────────────
var layout_select : OptionButton  = null
var scan_btn      : Button        = null
var stop_btn      : Button        = null
var disc_btn      : Button        = null
var clear_btn     : Button        = null
var board_grid    : Control       = null
var ip_list       : VBoxContainer = null
var data_panel    : VBoxContainer = null   # live CoP readout
var summary_box   : VBoxContainer = null
var status_dot    : ColorRect     = null
var status_lbl    : Label         = null
var footer_hint   : Label         = null
var confirm_btn   : Button        = null
var games_btn     : Button        = null

# ── Colors ────────────────────────────────────────────────────────────────────
const C_EMPTY    := Color(0.08, 0.10, 0.16)
const C_ASSIGNED := Color(0.04, 0.20, 0.10)
const C_FLASH    := Color(0.20, 0.16, 0.04)
const C_AUTO     := Color(0.06, 0.10, 0.22)
const C_BDR_DEF  := Color(0.20, 0.25, 0.40)
const C_BDR_ASGN := Color(0.0,  0.86, 0.44)
const C_BDR_FLSH := Color(1.0,  0.84, 0.25)
const C_BDR_AUTO := Color(0.24, 0.55, 1.0)

# ══════════════════════════════════════════════════════════════════════════════
#  READY
# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("board_setup_scene")
	_build_ui()
	_apply_layout(0)
	_bind_socket()
	set_status("Select a layout and press SCAN.", "")

func _bind_socket() -> void:
	udp.close()
	if udp.bind(BOARD_PORT, "0.0.0.0") == OK:
		_bound = true
		print("✅ BoardSetup socket bound on 0.0.0.0:%d" % BOARD_PORT)
	else:
		_bound = false
		set_status("❌ Could not bind port %d — already in use?" % BOARD_PORT, "err")

func _exit_tree() -> void:
	if not _handed_off:
		_stop_streaming()
		udp.close()
		_bound = false

# ══════════════════════════════════════════════════════════════════════════════
#  PROCESS — drains UDP every frame
# ══════════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	if not _bound: return

	while udp.get_available_packet_count() > 0:
		var pkt : PackedByteArray = udp.get_packet()
		var ip  : String          = udp.get_packet_ip()
		if ip == "": continue

		if _scanning:
			# Collect new IPs during discovery window
			if not discovered.any(func(d): return d["ip"] == ip):
				discovered.append({ "serial": discovered.size() + 1, "ip": ip })
				_refresh_ui()
				set_status("Found %d board(s). Still scanning…" % discovered.size(), "ok")
			# Also parse CoP if it's a full packet (boards may already stream)
			if pkt.size() >= PACKET_SIZE:
				_parse_cop(pkt, ip)

		elif _streaming:
			# Normal streaming phase
			if pkt.size() >= PACKET_SIZE:
				_parse_cop(pkt, ip)

	if _streaming and Engine.get_process_frames() % 30 == 0:
		_refresh_data_panel()

# ── Parse CoP packet from firmware ───────────────────────────────────────────
func _parse_cop(pkt: PackedByteArray, ip: String) -> void:
	# Header: 4 bytes (id, status1, status2, status3)
	# Floats[0]=t  [1]=f1  [2]=f2  [3]=f3  [4]=f4  [5]=cop_x  [6]=cop_y
	var floats : Array = []
	for i in range(FLOAT_COUNT):
		floats.append(pkt.decode_float(HEADER_BYTES + i * 4))

	var f1    : float = floats[1]
	var f2    : float = floats[2]
	var f3    : float = floats[3]
	var f4    : float = floats[4]
	var cop_x : float = floats[5]
	var cop_y : float = floats[6]
	var weight: float = f1 + f2 + f3 + f4

	if not (is_finite(cop_x) and is_finite(cop_y) and is_finite(weight)):
		return

	_board_data[ip] = {
		"cop_x": cop_x, "cop_y": cop_y,
		"weight": weight,
		"f1": f1, "f2": f2, "f3": f3, "f4": f4
	}

	# Feed directly to CoPManager for computation
	CoPManager.feed_board_data(ip, cop_x, cop_y, weight)

# ══════════════════════════════════════════════════════════════════════════════
#  SCAN
# ══════════════════════════════════════════════════════════════════════════════
func _on_scan_pressed() -> void:
	if _scanning: return
	if not _bound:
		_bind_socket()
		if not _bound: return

	_stop_streaming()
	discovered.clear()
	_board_data.clear()
	_reset_assignments()
	_scanning = true
	scan_btn.text = "Scanning…"
	scan_btn.disabled = true
	stop_btn.disabled = false
	set_status("📡 Broadcasting… listening for boards.", "warn")

	# Send Hey!mobbos FROM port 23000 — boards reply back to port 23000
	udp.set_broadcast_enabled(true)
	udp.set_dest_address(BROADCAST_IP, BOARD_PORT)
	udp.put_packet(DISCOVERY_MSG.to_utf8_buffer())
	udp.set_broadcast_enabled(false)
	print("📡 Sent '%s' → %s:%d" % [DISCOVERY_MSG, BROADCAST_IP, BOARD_PORT])

	await get_tree().create_timer(SCAN_SECS).timeout

	_scanning = false
	scan_btn.text = "🔍 Scan"
	scan_btn.disabled = false

	if discovered.is_empty():
		set_status("❌ No boards found. Check network / power.", "err")
		stop_btn.disabled = true
	else:
		# Start streaming from all discovered boards
		_start_streaming()
		set_status("✅ Found %d board(s). Streaming live data. Flash 💡 → assign slot." % discovered.size(), "ok")
	_refresh_ui()

# ══════════════════════════════════════════════════════════════════════════════
#  STREAM CONTROL
# ══════════════════════════════════════════════════════════════════════════════
func _start_streaming() -> void:
	if _streaming: return
	_streaming = true
	stop_btn.disabled = false
	# Send STREAM_ON to all discovered boards
	for d in discovered:
		_send_cmd(d["ip"], STREAM_ON)
	print("▶ Streaming started for %d board(s)" % discovered.size())

func _stop_streaming() -> void:
	if not _streaming: return
	_streaming = false
	# Send STREAM_OFF to all boards
	for d in discovered:
		_send_cmd(d["ip"], STREAM_OFF)
	_board_data.clear()
	CoPManager.clear_data()
	if stop_btn: stop_btn.disabled = true
	print("⏹ Streaming stopped")

func _on_stop_pressed() -> void:
	_handed_off = false   # stop button reclaims ownership
	_stop_streaming()
	set_status("⏹ Streaming stopped. Press SCAN to restart.", "warn")
	_refresh_data_panel()

# ══════════════════════════════════════════════════════════════════════════════
#  DISCONNECT
# ══════════════════════════════════════════════════════════════════════════════
func _on_disconnect_pressed() -> void:
	_handed_off = false
	_stop_streaming()
	for d in discovered:
		_send_led_ip(d["ip"], false)
	discovered.clear()
	_board_data.clear()
	_reset_assignments()
	CoPManager.clear_data()
	confirmed = false
	if games_btn: games_btn.hide()
	set_status("🔌 Disconnected. Press SCAN to find boards.", "")
	_refresh_ui()
	_refresh_data_panel()

# ══════════════════════════════════════════════════════════════════════════════
#  SEND HELPERS
# ══════════════════════════════════════════════════════════════════════════════
func _send_cmd(ip: String, cmd: int) -> void:
	if not _bound: return
	udp.set_dest_address(ip, BOARD_PORT)
	udp.put_packet(PackedByteArray([cmd]))

func _send_led_ip(ip: String, on: bool) -> void:
	_send_cmd(ip, LED_ON_BYTE if on else LED_OFF_BYTE)

func _send_led(serial: int, on: bool) -> void:
	var ip := _ip_for_serial(serial)
	if ip != "": _send_led_ip(ip, on)

# ══════════════════════════════════════════════════════════════════════════════
#  DATA PANEL — live CoP readout per board
# ══════════════════════════════════════════════════════════════════════════════
func _refresh_data_panel() -> void:
	if data_panel == null: return
	for c in data_panel.get_children(): c.queue_free()

	if _board_data.is_empty():
		var lbl := Label.new()
		lbl.text = "No data yet."
		lbl.modulate = Color(1,1,1,0.4)
		data_panel.add_child(lbl)
		return

	for d in discovered:
		var ip : String = d["ip"]
		if not _board_data.has(ip): continue
		var bd : Dictionary = _board_data[ip]

		var row := HBoxContainer.new()
		data_panel.add_child(row)

		var lbl := Label.new()
		lbl.text = "#%d %s  CoP=(%.1f, %.1f)cm  W=%.1f" \
			% [d["serial"], ip, bd["cop_x"], bd["cop_y"], bd["weight"]]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.modulate = Color(0.4, 1.0, 0.7)
		row.add_child(lbl)

# ══════════════════════════════════════════════════════════════════════════════
#  LED
# ══════════════════════════════════════════════════════════════════════════════
func _flash_led(serial: int) -> void:
	if flashing_serial != 0 and flashing_serial != serial:
		_send_led(flashing_serial, false)
	flashing_serial = serial
	pending_serial  = serial
	_send_led(serial, true)
	_refresh_ui()
	set_status("💡 LED ON → Board #%d (%s)  |  Click its slot on the grid." \
		% [serial, _ip_for_serial(serial)], "warn")

func _led_off(serial: int) -> void:
	_send_led(serial, false)
	if flashing_serial == serial:
		flashing_serial = 0
		pending_serial  = 0
	_refresh_ui()

# ══════════════════════════════════════════════════════════════════════════════
#  CONFIRM
# ══════════════════════════════════════════════════════════════════════════════
func _on_confirm_pressed() -> void:
	confirmed = true
	if confirm_btn:
		confirm_btn.text     = "✅ Confirmed"
		confirm_btn.disabled = true
	if games_btn: games_btn.show()

	var assignments_arr : Array = []
	for i in slot_assigned.size():
		assignments_arr.append({
			"slot":   layout["slots"][i],
			"serial": slot_assigned[i],
			"ip":     _ip_for_serial(slot_assigned[i])
		})

	# Hand socket + config to CoPManager — streaming continues into games
	_handed_off = true
	CoPManager.set_board_config(layout["id"], assignments_arr, udp)
	set_status("✅ Config saved! Press 🎮 Games to continue.", "ok")
	print("✅ Confirmed: layout=%s  %s" % [layout["id"], str(assignments_arr)])

func _on_games_pressed() -> void:
	get_tree().change_scene_to_file("res://Main_screen/Scenes/mode.tscn")

func _on_clear_pressed() -> void:
	_stop_streaming()
	discovered.clear()
	_board_data.clear()
	_reset_assignments()
	CoPManager.clear_data()
	set_status("Reset. Press SCAN to discover boards.", "")
	_refresh_ui()
	_refresh_data_panel()

# ══════════════════════════════════════════════════════════════════════════════
#  LAYOUT
# ══════════════════════════════════════════════════════════════════════════════
func _on_layout_selected(idx: int) -> void:
	_apply_layout(idx)
	set_status("Layout: %s.  Press SCAN." % layout["label"], "")

func _apply_layout(idx: int) -> void:
	layout        = LAYOUTS[idx]
	slot_assigned = []
	slot_assigned.resize(layout["slots"].size())
	slot_assigned.fill(0)
	flashing_serial = 0
	pending_serial  = 0
	confirmed       = false
	_build_slot_rects()
	_refresh_ui()

# ══════════════════════════════════════════════════════════════════════════════
#  SLOT GEOMETRY + DRAWING  (unchanged from original)
# ══════════════════════════════════════════════════════════════════════════════
func _build_slot_rects() -> void:
	slot_rects.clear()
	if board_grid == null: return
	var cols : int   = layout["cols"]
	var rows : int   = layout["rows"]
	var GW   : float = board_grid.size.x if board_grid.size.x > 10 else 600.0
	var GH   : float = board_grid.size.y if board_grid.size.y > 10 else 400.0
	const PAD : float = 16.0
	const GAP : float = 10.0
	var aw : float = GW - PAD * 2.0 - GAP * (cols - 1)
	var ah : float = GH - PAD * 2.0 - GAP * (rows - 1)
	var raw_cw : float = aw / cols
	var raw_ch : float = ah / rows
	const MAX_RATIO : float = 2.5
	if raw_cw / maxf(raw_ch, 1.0) > MAX_RATIO: raw_cw = raw_ch * MAX_RATIO
	elif raw_ch / maxf(raw_cw, 1.0) > MAX_RATIO: raw_ch = raw_cw * MAX_RATIO
	var total_w : float = raw_cw * cols + GAP * (cols - 1)
	var total_h : float = raw_ch * rows + GAP * (rows - 1)
	var ox : float = PAD + (aw - total_w) * 0.5
	var oy : float = PAD + (ah - total_h) * 0.5
	for i in layout["slots"].size():
		var col : int = i % cols
		var row : int = i / cols
		slot_rects.append(Rect2(ox + col*(raw_cw+GAP), oy + row*(raw_ch+GAP), raw_cw, raw_ch))

func _draw_grid() -> void:
	_build_slot_rects()
	var font : Font       = ThemeDB.fallback_font
	var auto : Dictionary = _check_auto_assign()
	for i in slot_rects.size():
		var r      : Rect2 = slot_rects[i]
		var serial : int   = slot_assigned[i]
		var is_assigned  := serial > 0
		var is_auto      := auto.size() > 0 and int(auto["slot"]) == i and pending_serial == 0
		var is_flashing  := pending_serial > 0 and not is_assigned
		var bg  := C_ASSIGNED if is_assigned else (C_FLASH if is_flashing else (C_AUTO if is_auto else C_EMPTY))
		var bdr := C_BDR_ASGN if is_assigned else (C_BDR_FLSH if is_flashing else (C_BDR_AUTO if is_auto else C_BDR_DEF))
		board_grid.draw_rect(r, bg, true)
		board_grid.draw_rect(r, bdr, false, 2.5)
		var cx := r.position.x + r.size.x * 0.5
		var cy := r.position.y + r.size.y * 0.5
		if is_assigned:
			var sn    := str(serial)
			var sn_sz := int(clamp(minf(r.size.x, r.size.y) * 0.32, 18, 52))
			var sn_ts := font.get_string_size(sn, HORIZONTAL_ALIGNMENT_LEFT, -1, sn_sz)
			board_grid.draw_string(font, Vector2(cx - sn_ts.x*0.5, cy - 4),
				sn, HORIZONTAL_ALIGNMENT_LEFT, -1, sn_sz, Color(0.0, 0.86, 0.44, 0.95))
		var lbl    := layout["slots"][i] as String
		var lbl_sz := int(clamp(minf(r.size.x*0.2, r.size.y*0.22), 10, 22))
		var lbl_col := Color(0.6,1.0,0.75,0.85) if is_assigned else (Color(1.0,0.84,0.25,0.95) if is_flashing else (Color(0.24,0.55,1.0,0.85) if is_auto else Color(1,1,1,0.28)))
		var lbl_ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_sz)
		board_grid.draw_string(font, Vector2(cx - lbl_ts.x*0.5, cy + (22 if is_assigned else 6)),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_sz, lbl_col)
		if is_assigned:
			var ip_str := _ip_for_serial(serial)
			var ip_sz  := int(clamp(minf(r.size.x*0.13, r.size.y*0.14), 8, 13))
			var ip_ts  := font.get_string_size(ip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, ip_sz)
			board_grid.draw_string(font, Vector2(cx - ip_ts.x*0.5, cy + 38),
				ip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, ip_sz, Color(0.5,1.0,0.7,0.6))
			# Show live CoP in grid cell
			if _board_data.has(ip_str):
				var bd : Dictionary = _board_data[ip_str]
				var cop_str := "(%.1f, %.1f) W=%.0f" % [bd["cop_x"], bd["cop_y"], bd["weight"]]
				var cs_sz := int(clamp(minf(r.size.x*0.10, r.size.y*0.12), 7, 11))
				var cs_ts := font.get_string_size(cop_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cs_sz)
				board_grid.draw_string(font, Vector2(cx - cs_ts.x*0.5, cy + 52),
					cop_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cs_sz, Color(1.0,0.9,0.4,0.8))
		if not is_assigned:
			var hint := "tap to auto-assign" if (is_auto and pending_serial==0) else ("← click here" if is_flashing else "")
			if hint != "":
				var h_sz := int(clamp(minf(r.size.x*0.10, r.size.y*0.13), 8, 12))
				var h_ts := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, h_sz)
				board_grid.draw_string(font, Vector2(cx - h_ts.x*0.5, r.position.y + r.size.y - 10),
					hint, HORIZONTAL_ALIGNMENT_LEFT, -1, h_sz, Color(0.24,0.55,1.0,0.7))

func _slot_at(local_pos: Vector2) -> int:
	for i in slot_rects.size():
		if slot_rects[i].has_point(local_pos): return i
	return -1

# ══════════════════════════════════════════════════════════════════════════════
#  INPUT
# ══════════════════════════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	if not event.pressed: return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	if board_grid == null: return
	var local_pos : Vector2 = board_grid.get_global_transform().affine_inverse() * event.position
	if not Rect2(Vector2.ZERO, board_grid.size).has_point(local_pos): return
	var slot := _slot_at(local_pos)
	if slot == -1 or slot_assigned[slot] > 0: return
	_click_slot(slot)

# ══════════════════════════════════════════════════════════════════════════════
#  SLOT ASSIGN
# ══════════════════════════════════════════════════════════════════════════════
func _check_auto_assign() -> Dictionary:
	var used := {}
	for s in slot_assigned:
		if s > 0: used[s] = true
	var unassigned := discovered.filter(func(d): return not used.has(d["serial"]))
	var empty_slots : Array = []
	for i in slot_assigned.size():
		if slot_assigned[i] == 0: empty_slots.append(i)
	if unassigned.size() == 1 and empty_slots.size() == 1:
		return { "serial": unassigned[0]["serial"], "slot": empty_slots[0] }
	return {}

func _click_slot(slot_idx: int) -> void:
	var aa := _check_auto_assign()
	if aa.size() > 0 and int(aa["slot"]) == slot_idx and pending_serial == 0:
		_assign_slot(slot_idx, int(aa["serial"]))
		return
	if pending_serial == 0:
		set_status("⚡ Flash a board LED first, then click its slot.", "warn")
		return
	_assign_slot(slot_idx, pending_serial)

func _assign_slot(slot_idx: int, serial: int) -> void:
	for i in slot_assigned.size():
		if slot_assigned[i] == serial: slot_assigned[i] = 0
	slot_assigned[slot_idx] = serial
	if flashing_serial == serial:
		_send_led(serial, false)
		flashing_serial = 0
		pending_serial  = 0
	pending_serial = 0
	_refresh_ui()
	set_status("✅ Board #%d (%s) → slot [%s]" \
		% [serial, _ip_for_serial(serial), layout["slots"][slot_idx]], "ok")
	_check_confirm()

func _reset_assignments() -> void:
	slot_assigned.fill(0)
	flashing_serial = 0
	pending_serial  = 0
	confirmed       = false
	if games_btn:   games_btn.hide()
	if confirm_btn:
		confirm_btn.text     = "✅ Confirm"
		confirm_btn.disabled = true

func _ip_for_serial(serial: int) -> String:
	for d in discovered:
		if d["serial"] == serial: return d["ip"]
	return ""

# ══════════════════════════════════════════════════════════════════════════════
#  UI REFRESH
# ══════════════════════════════════════════════════════════════════════════════
func _refresh_ui() -> void:
	if board_grid: board_grid.queue_redraw()
	_rebuild_ip_list()
	_rebuild_summary()
	_check_confirm()

func _rebuild_ip_list() -> void:
	if ip_list == null: return
	for c in ip_list.get_children(): c.queue_free()
	if discovered.is_empty():
		var lbl := Label.new(); lbl.text = "No boards discovered yet."
		ip_list.add_child(lbl); return
	var assigned_map := {}
	for i in slot_assigned.size():
		if slot_assigned[i] > 0: assigned_map[slot_assigned[i]] = layout["slots"][i]
	for d in discovered:
		var serial : int    = d["serial"]
		var ip     : String = d["ip"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		ip_list.add_child(row)
		var badge := Label.new(); badge.text = "#%d" % serial
		badge.custom_minimum_size = Vector2(32, 0); row.add_child(badge)
		var addr_lbl := Label.new(); addr_lbl.text = ip
		addr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(addr_lbl)
		if assigned_map.has(serial):
			var tag := Label.new(); tag.text = "[%s]" % assigned_map[serial]
			tag.modulate = Color(0.4, 1.0, 0.6); row.add_child(tag)
		if not assigned_map.has(serial) or flashing_serial == serial:
			var fb := Button.new()
			fb.text = "💡 ON" if flashing_serial == serial else "💡"
			var cap := serial
			fb.pressed.connect(func(): if flashing_serial == cap: _led_off(cap) else: _flash_led(cap))
			row.add_child(fb)

func _rebuild_summary() -> void:
	if summary_box == null: return
	for c in summary_box.get_children(): c.queue_free()
	var use_pos : bool = int(layout["boards"]) <= 2
	for i in slot_assigned.size():
		var serial    : int    = int(slot_assigned[i])
		var pos_label : String = layout["slots"][i] if use_pos else ("Board %d" % (i + 1))
		var row := HBoxContainer.new(); summary_box.add_child(row)
		var pl  := Label.new(); pl.text = pos_label + " : "; row.add_child(pl)
		var vl  := Label.new()
		vl.text = ("#%d  %s" % [serial, _ip_for_serial(serial)]) if serial > 0 else "—"
		vl.modulate = Color(0.4, 1.0, 0.6) if serial > 0 else Color(1, 1, 1, 0.4)
		row.add_child(vl)

func _check_confirm() -> void:
	if confirm_btn == null: return
	var all_filled : bool = slot_assigned.all(func(v): return v > 0)
	confirm_btn.disabled = not all_filled
	var filled := 0
	for v in slot_assigned:
		if int(v) > 0: filled += 1
	if footer_hint:
		footer_hint.text = "All assigned — ready to confirm!" if all_filled \
			else "%d / %d slots filled." % [filled, slot_assigned.size()]

func set_status(msg: String, level: String) -> void:
	if status_lbl: status_lbl.text = msg
	if status_dot:
		match level:
			"ok":   status_dot.color = Color(0.0, 0.86, 0.44)
			"warn": status_dot.color = Color(1.0, 0.84, 0.25)
			"err":  status_dot.color = Color(1.0, 0.20, 0.18)
			_:      status_dot.color = Color(0.4, 0.4, 0.4)

# ══════════════════════════════════════════════════════════════════════════════
#  BUILD UI
# ══════════════════════════════════════════════════════════════════════════════
func _build_ui() -> void:
	for c in get_children(): c.queue_free()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(header)
	var title := Label.new(); title.text = "MoBBo Device Setup"
	title.add_theme_font_size_override("font_size", 20); header.add_child(title)

	# Body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	vbox.add_child(body)

	# Left: grid
	var grid_wrap := VBoxContainer.new()
	grid_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(grid_wrap)
	var grid_lbl := Label.new(); grid_lbl.text = "Board Layout"
	grid_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN; grid_wrap.add_child(grid_lbl)
	board_grid = Control.new()
	board_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_grid.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	board_grid.mouse_filter          = Control.MOUSE_FILTER_STOP
	board_grid.draw.connect(_draw_grid)
	grid_wrap.add_child(board_grid)

	# Live data panel below grid
	var data_lbl := Label.new(); data_lbl.text = "Live Board Data"
	data_lbl.add_theme_font_size_override("font_size", 11)
	data_lbl.modulate = Color(1,1,1,0.5)
	grid_wrap.add_child(data_lbl)
	data_panel = VBoxContainer.new()
	data_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	grid_wrap.add_child(data_panel)

	# Right panel
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	layout_select = OptionButton.new()
	for l in LAYOUTS: layout_select.add_item(l["label"])
	layout_select.selected = 0
	layout_select.item_selected.connect(_on_layout_selected)
	right.add_child(layout_select)

	# Control buttons row
	var ctrl_row := HBoxContainer.new()
	right.add_child(ctrl_row)
	scan_btn = Button.new(); scan_btn.text = "🔍 Scan"
	scan_btn.pressed.connect(_on_scan_pressed); ctrl_row.add_child(scan_btn)
	stop_btn = Button.new(); stop_btn.text = "⏹ Stop"
	stop_btn.pressed.connect(_on_stop_pressed); stop_btn.disabled = true
	ctrl_row.add_child(stop_btn)

	var ctrl_row2 := HBoxContainer.new()
	right.add_child(ctrl_row2)
	disc_btn = Button.new(); disc_btn.text = "🔌 Disconnect"
	disc_btn.pressed.connect(_on_disconnect_pressed); ctrl_row2.add_child(disc_btn)
	clear_btn = Button.new(); clear_btn.text = "✕ Reset"
	clear_btn.pressed.connect(_on_clear_pressed); ctrl_row2.add_child(clear_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; right.add_child(scroll)
	ip_list = VBoxContainer.new()
	ip_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(ip_list)

	summary_box = VBoxContainer.new()
	summary_box.size_flags_vertical = Control.SIZE_SHRINK_END; right.add_child(summary_box)

	# Status bar
	var status_bar := HBoxContainer.new()
	status_bar.size_flags_vertical = Control.SIZE_SHRINK_END; vbox.add_child(status_bar)
	status_dot = ColorRect.new(); status_dot.custom_minimum_size = Vector2(14,14)
	status_bar.add_child(status_dot)
	status_lbl = Label.new(); status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(status_lbl)

	# Footer
	var footer := HBoxContainer.new()
	footer.size_flags_vertical = Control.SIZE_SHRINK_END; vbox.add_child(footer)
	footer_hint = Label.new(); footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_hint)
	games_btn = Button.new(); games_btn.text = "🎮 Games →"
	games_btn.pressed.connect(_on_games_pressed); games_btn.hide(); footer.add_child(games_btn)
	confirm_btn = Button.new(); confirm_btn.text = "✅ Confirm"
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(_on_confirm_pressed); footer.add_child(confirm_btn)
