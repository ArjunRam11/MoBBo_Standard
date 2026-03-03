# BoardIPSetup.gd
# Pure Godot — no Python involved.
#
# ══════════════════════════════════════════════════════════════
# HOW TO CREATE THE SCENE (do this once in the Godot editor):
# ══════════════════════════════════════════════════════════════
# 1. Scene > New Scene
# 2. Root node: Control  → rename to "BoardIPSetup"
#    - Anchor Preset: Full Rect
# 3. Add child: HBoxContainer → rename "Body"
#    - Layout > Full Rect, then set Top anchor to leave room for header/status/footer
#    - Or use a VBoxContainer as the true root and nest Body inside it
#
# Simplest approach — use a VBoxContainer root:
#
#  BoardIPSetup (Control, Full Rect)
#  └─ VBox (VBoxContainer, Full Rect)
#      ├─ Header (HBoxContainer, size_flags_vertical = SHRINK_BEGIN)
#      │   └─ TitleLabel (Label)  text = "MOBBO Board Setup"
#      ├─ Body (HBoxContainer, size_flags_vertical = EXPAND+FILL)
#      │   ├─ GridWrap (VBoxContainer, size_flags_horizontal = EXPAND+FILL)
#      │   │   ├─ GridLabel (Label)  text = "Board Layout"
#      │   │   └─ BoardGrid (Control, size_flags_vertical = EXPAND+FILL)
#      │   │       mouse_filter = STOP  ← IMPORTANT
#      │   └─ RightPanel (VBoxContainer, custom_minimum_size.x = 280)
#      │       ├─ LayoutSelect (OptionButton)
#      │       ├─ ControlsRow (HBoxContainer)
#      │       │   ├─ ScanBtn  (Button)  text = "🔍 Scan"
#      │       │   └─ ClearBtn (Button)  text = "✕ Reset"
#      │       ├─ ScrollContainer (size_flags_vertical = EXPAND+FILL)
#      │       │   └─ IPList (VBoxContainer)
#      │       └─ Summary (VBoxContainer)
#      ├─ StatusBar (HBoxContainer, size_flags_vertical = SHRINK_END)
#      │   ├─ Dot (ColorRect)  custom_minimum_size = (10,10)
#      │   └─ StatusText (Label)
#      └─ Footer (HBoxContainer, size_flags_vertical = SHRINK_END)
#          ├─ FooterHint (Label, size_flags_horizontal = EXPAND+FILL)
#          ├─ GamesBtn  (Button)  text = "🎮 Games →"
#          └─ ConfirmBtn (Button) text = "✅ Confirm"
#
# 4. Attach THIS script to the BoardIPSetup (root Control) node.
# 5. Save as res://Scenes/BoardIPSetup.tscn
# ══════════════════════════════════════════════════════════════

extends Control

# ─── UDP ─────────────────────────────────────────────────────
const BOARD_PORT    := 23000
const LISTEN_PORT   := 23001
const DISCOVERY_MSG := "Hey!mobbos"
const LED_ON_BYTE   := 0x10
const LED_OFF_BYTE  := 0x20
const SCAN_SECS     := 3.0

var udp_send := PacketPeerUDP.new()
var udp_recv := PacketPeerUDP.new()

# ─── Layout definitions ───────────────────────────────────────
# Each layout: { id, label, cols, rows, slots[] }
var LAYOUTS : Array = [
  { "id":"1x2","label":"1 × 2  (Left / Right)",  "cols":2,"rows":1,"boards":2,
	"slots":["LEFT","RIGHT"] },
  { "id":"2x1","label":"2 × 1  (Top / Bottom)",  "cols":1,"rows":2,"boards":2,
	"slots":["TOP","BOTTOM"] },
  { "id":"1x3","label":"1 × 3  (3 columns)",     "cols":3,"rows":1,"boards":3,
	"slots":["LEFT","CENTER","RIGHT"] },
  { "id":"3x1","label":"3 × 1  (3 rows)",        "cols":1,"rows":3,"boards":3,
	"slots":["TOP","MIDDLE","BOTTOM"] },
  { "id":"2x2","label":"2 × 2  (Grid)",          "cols":2,"rows":2,"boards":4,
	"slots":["TOP-LEFT","TOP-RIGHT","BOT-LEFT","BOT-RIGHT"] },
  { "id":"1x4","label":"1 × 4  (4 columns)",     "cols":4,"rows":1,"boards":4,
	"slots":["1","2","3","4"] },
  { "id":"4x1","label":"4 × 1  (4 rows)",        "cols":1,"rows":4,"boards":4,
	"slots":["1","2","3","4"] },
  { "id":"1x5","label":"1 × 5  (5 columns)",     "cols":5,"rows":1,"boards":5,
	"slots":["1","2","3","4","5"] },
  { "id":"5x1","label":"5 × 1  (5 rows)",        "cols":1,"rows":5,"boards":5,
	"slots":["1","2","3","4","5"] },
  { "id":"2x3","label":"2 × 3  (2 rows × 3 cols)","cols":3,"rows":2,"boards":6,
	"slots":["R1C1","R1C2","R1C3","R2C1","R2C2","R2C3"] },
  { "id":"3x2","label":"3 × 2  (3 rows × 2 cols)","cols":2,"rows":3,"boards":6,
	"slots":["R1C1","R1C2","R2C1","R2C2","R3C1","R3C2"] },
  { "id":"1x6","label":"1 × 6  (6 columns)",     "cols":6,"rows":1,"boards":6,
	"slots":["1","2","3","4","5","6"] },
  { "id":"6x1","label":"6 × 1  (6 rows)",        "cols":1,"rows":6,"boards":6,
	"slots":["1","2","3","4","5","6"] },
]

# ─── State ───────────────────────────────────────────────────
var layout         : Dictionary = {}   # current LAYOUTS entry
var discovered     : Array      = []   # [{serial:int, ip:String}]
var slot_assigned  : Array      = []   # per-slot: serial (1-based) or 0
var flashing_serial: int        = 0
var pending_serial : int        = 0
var scanning       : bool       = false
var confirmed      : bool       = false

# Hit areas for mouse detection (in BoardGrid local coords)
var slot_rects : Array = []   # Array of Rect2

# ─── Colors ──────────────────────────────────────────────────
const C_EMPTY    := Color(0.08, 0.10, 0.16)
const C_HOVER    := Color(0.12, 0.16, 0.28)
const C_ASSIGNED := Color(0.04, 0.18, 0.10)
const C_FLASH    := Color(0.18, 0.16, 0.05)
const C_AUTO     := Color(0.06, 0.10, 0.20)
const C_BDR_DEF  := Color(0.16, 0.20, 0.36)
const C_BDR_ASGN := Color(0.0,  0.86, 0.44)
const C_BDR_FLSH := Color(1.0,  0.84, 0.25)
const C_BDR_AUTO := Color(0.24, 0.55, 1.0)

# ─── Node refs ────────────────────────────────────────────────
@onready var layout_select: OptionButton  = $Body/RightPanel/LayoutSelect
@onready var scan_btn     : Button        = $Body/RightPanel/ControlsRow/ScanBtn
@onready var clear_btn    : Button        = $Body/RightPanel/ControlsRow/ClearBtn
@onready var board_grid   : Control       = $Body/GridWrap/BoardGrid
@onready var ip_list      : VBoxContainer = $Body/RightPanel/ScrollContainer/IPList
@onready var summary      : VBoxContainer = $Body/RightPanel/Summary
@onready var status_dot   : ColorRect     = $StatusBar/Dot
@onready var status_text  : Label         = $StatusBar/StatusText
@onready var footer_hint  : Label         = $Footer/FooterHint
@onready var confirm_btn  : Button        = $Footer/ConfirmBtn
@onready var games_btn    : Button        = $Footer/GamesBtn

# ═════════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("board_setup_scene")

	# Bind UDP
	if udp_recv.bind(LISTEN_PORT, "0.0.0.0") != OK:
		set_status("⚠ Could not bind port %d" % LISTEN_PORT, "err")

	# Populate layout dropdown
	for l in LAYOUTS:
		layout_select.add_item(l["label"])
	layout_select.selected = 0
	layout_select.item_selected.connect(_on_layout_selected)

	scan_btn.pressed.connect(_on_scan_pressed)
	clear_btn.pressed.connect(_on_clear_pressed)
	confirm_btn.pressed.connect(_on_confirm_pressed)
	games_btn.pressed.connect(_on_games_pressed)
	games_btn.hide()
	confirm_btn.disabled = true

	board_grid.draw.connect(_draw_grid)
	board_grid.gui_input.connect(_on_grid_input)

	_apply_layout(0)
	set_status("Select a layout and press SCAN to find boards.", "")

# ═════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	# Poll incoming board discovery replies
	while udp_recv.get_available_packet_count() > 0:
		var _pkt = udp_recv.get_packet()
		var addr = udp_recv.get_packet_ip()
		if addr == "":
			continue
		if discovered.any(func(d): return d["ip"] == addr):
			continue
		discovered.append({ "serial": discovered.size() + 1, "ip": addr })
		_refresh_ui()
		set_status("Found %d board(s). Flash LED to assign." % discovered.size(), "ok")

# ─────────────────────────────────────────────────────────────
#  LAYOUT
# ─────────────────────────────────────────────────────────────
func _on_layout_selected(idx: int) -> void:
	_apply_layout(idx)
	set_status("Layout: %s. Press SCAN." % layout["label"], "info")

func _apply_layout(idx: int) -> void:
	layout        = LAYOUTS[idx]
	slot_assigned = Array()
	slot_assigned.resize(layout["slots"].size())
	slot_assigned.fill(0)
	flashing_serial = 0
	pending_serial  = 0
	confirmed       = false
	_build_slot_rects()
	_refresh_ui()

# ─────────────────────────────────────────────────────────────
#  SLOT GEOMETRY
# ─────────────────────────────────────────────────────────────
func _build_slot_rects() -> void:
	slot_rects.clear()
	var W    : float = board_grid.size.x
	var H    : float = board_grid.size.y
	var PAD  : float = 14.0
	var GAP  : float = 10.0
	var cols : int = layout["cols"]
	var rows : int = layout["rows"]
	var sw   : float = (W - PAD * 2 - GAP * (cols - 1)) / cols
	var sh   : float = (H - PAD * 2 - GAP * (rows - 1)) / rows

	for i in layout["slots"].size():
		var col : int   = i % cols
		var row : int   = i / cols
		var x   : float = PAD + col * (sw + GAP)
		var y   : float = PAD + row * (sh + GAP)
		slot_rects.append(Rect2(x, y, sw, sh))

# ─────────────────────────────────────────────────────────────
#  DRAWING
# ─────────────────────────────────────────────────────────────
func _draw_grid() -> void:
	if slot_rects.is_empty():
		_build_slot_rects()

	var font      : Font = ThemeDB.fallback_font
	var auto      : Dictionary = _check_auto_assign()

	for i in slot_rects.size():
		var r      : Rect2 = slot_rects[i]
		var serial : int   = slot_assigned[i]
		var is_assigned    : bool = serial > 0
		var is_auto        : bool = auto.size() > 0 and int(auto["slot"]) == i and pending_serial == 0
		var is_flashing    : bool = pending_serial > 0 and not is_assigned

		# Background
		var bg_col := C_EMPTY
		if is_assigned: bg_col = C_ASSIGNED
		elif is_flashing: bg_col = C_FLASH
		elif is_auto: bg_col = C_AUTO
		board_grid.draw_rect(r, bg_col, true)

		# Border
		var bdr_col := C_BDR_DEF
		if is_assigned: bdr_col = C_BDR_ASGN
		elif is_flashing: bdr_col = C_BDR_FLSH
		elif is_auto: bdr_col = C_BDR_AUTO
		board_grid.draw_rect(r, bdr_col, false, 2.0)

		var cx := r.position.x + r.size.x * 0.5
		var cy := r.position.y + r.size.y * 0.5

		# Big serial number
		if is_assigned:
			var sn_str := str(serial)
			var sn_sz  := int(clamp(r.size.y * 0.35, 20, 48))
			var sn_ts  := font.get_string_size(sn_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sn_sz)
			board_grid.draw_string(font,
				Vector2(cx - sn_ts.x * 0.5, cy - 10),
				sn_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sn_sz,
				Color(0.0, 0.86, 0.44, 0.9))

		# Position label
		var lbl    : String = layout["slots"][i] as String
		var lbl_sz := int(clamp(r.size.y * 0.18, 11, 20))
		var lbl_col := Color(1, 1, 1, 0.25)
		if is_assigned: lbl_col = Color(0.7, 1.0, 0.8, 0.8)
		elif is_flashing: lbl_col = Color(1.0, 0.84, 0.25, 0.9)
		elif is_auto: lbl_col = Color(0.24, 0.55, 1.0, 0.8)
		var lbl_ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_sz)
		board_grid.draw_string(font,
			Vector2(cx - lbl_ts.x * 0.5, cy + (14 if is_assigned else 4)),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_sz, lbl_col)

		# IP text
		if is_assigned:
			var ip_str := _ip_for_serial(serial)
			var ip_sz  := int(clamp(r.size.y * 0.12, 9, 13))
			var ip_ts  := font.get_string_size(ip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, ip_sz)
			board_grid.draw_string(font,
				Vector2(cx - ip_ts.x * 0.5, cy + 30),
				ip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, ip_sz,
				Color(0.5, 1.0, 0.7, 0.6))

		# Hint text
		if not is_assigned:
			var hint := ""
			if is_auto and pending_serial == 0:
				hint = "tap to auto-assign"
			elif is_flashing:
				hint = "← click here"
			if hint != "":
				var h_sz := int(clamp(r.size.y * 0.11, 9, 12))
				var h_ts := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, h_sz)
				board_grid.draw_string(font,
					Vector2(cx - h_ts.x * 0.5, r.position.y + r.size.y - 12),
					hint, HORIZONTAL_ALIGNMENT_LEFT, -1, h_sz,
					Color(0.24, 0.55, 1.0, 0.7))

# ─────────────────────────────────────────────────────────────
#  MOUSE INPUT ON GRID
# ─────────────────────────────────────────────────────────────
func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
	   and event.button_index == MOUSE_BUTTON_LEFT:
		var slot := _slot_at(event.position)
		if slot == -1:
			return
		if slot_assigned[slot] > 0:
			return  # already assigned, ignore
		_click_slot(slot)

func _slot_at(pos: Vector2) -> int:
	for i in slot_rects.size():
		if slot_rects[i].has_point(pos):
			return i
	return -1

# ─────────────────────────────────────────────────────────────
#  SCAN
# ─────────────────────────────────────────────────────────────
func _on_scan_pressed() -> void:
	if scanning: return
	scanning = true
	discovered.clear()
	_reset_assignments()
	set_status("🔍 Broadcasting on 255.255.255.255:%d …" % BOARD_PORT, "warn")
	scan_btn.text = "Scanning…"

	udp_send.set_broadcast_enabled(true)
	udp_send.set_dest_address("255.255.255.255", BOARD_PORT)
	udp_send.put_packet(DISCOVERY_MSG.to_utf8_buffer())

	await get_tree().create_timer(SCAN_SECS).timeout
	udp_send.set_broadcast_enabled(false)
	scanning = false
	scan_btn.text = "🔍 Scan"

	if discovered.is_empty():
		set_status("❌ No boards found. Check network & power.", "err")
	else:
		set_status("✅ Found %d board(s). Flash each LED to assign." % discovered.size(), "ok")
	_refresh_ui()

func _on_clear_pressed() -> void:
	discovered.clear()
	_reset_assignments()
	set_status("Reset. Press SCAN to discover boards.", "")

func _reset_assignments() -> void:
	slot_assigned.fill(0)
	flashing_serial = 0
	pending_serial  = 0
	confirmed       = false
	games_btn.hide()
	confirm_btn.text = "✅ Confirm"
	confirm_btn.disabled = true
	_refresh_ui()

# ─────────────────────────────────────────────────────────────
#  LED
# ─────────────────────────────────────────────────────────────
func _flash_led(serial: int) -> void:
	if flashing_serial != 0 and flashing_serial != serial:
		_send_led(flashing_serial, false)
	flashing_serial = serial
	pending_serial  = serial
	_send_led(serial, true)
	_refresh_ui()
	set_status("💡 LED ON → Board #%d (%s)  |  Click its slot." \
		% [serial, _ip_for_serial(serial)], "warn")

func _led_off(serial: int) -> void:
	_send_led(serial, false)
	if flashing_serial == serial:
		flashing_serial = 0
		pending_serial  = 0
	_refresh_ui()

func _send_led(ip_or_serial: Variant, on: bool) -> void:
	var ip : String = ""
	if typeof(ip_or_serial) == TYPE_INT:
		ip = _ip_for_serial(int(ip_or_serial))
	else:
		ip = str(ip_or_serial)
	if ip == "": return
	udp_send.set_dest_address(ip, BOARD_PORT)
	udp_send.put_packet(PackedByteArray([LED_ON_BYTE if on else LED_OFF_BYTE]))

# ─────────────────────────────────────────────────────────────
#  AUTO-ASSIGN (last unassigned IP + last empty slot)
# ─────────────────────────────────────────────────────────────
func _check_auto_assign() -> Dictionary:
	var used     := {}
	for s in slot_assigned:
		if s > 0: used[s] = true
	var unassigned := discovered.filter(func(d): return not used.has(d["serial"]))
	var empty_slots := []
	for i in slot_assigned.size():
		if slot_assigned[i] == 0:
			empty_slots.append(i)
	if unassigned.size() == 1 and empty_slots.size() == 1:
		return { "serial": unassigned[0]["serial"], "slot": empty_slots[0] }
	return {}

# ─────────────────────────────────────────────────────────────
#  SLOT CLICK / ASSIGN
# ─────────────────────────────────────────────────────────────
func _click_slot(slot_idx: int) -> void:
	var aa : Dictionary = _check_auto_assign()
	if aa.size() > 0 and int(aa["slot"]) == slot_idx and pending_serial == 0:
		_assign_slot(slot_idx, int(aa["serial"]))
		return
	if pending_serial == 0:
		set_status("⚡ Flash a board LED first, then click its slot.", "warn")
		return
	_assign_slot(slot_idx, pending_serial)

func _assign_slot(slot_idx: int, serial: int) -> void:
	# Remove serial from any other slot
	for i in slot_assigned.size():
		if slot_assigned[i] == serial:
			slot_assigned[i] = 0
	slot_assigned[slot_idx] = serial
	if flashing_serial == serial:
		_send_led(serial, false)
		flashing_serial = 0
		pending_serial  = 0
	pending_serial = 0
	_refresh_ui()
	var label := layout["slots"][slot_idx] as String
	set_status("✅ Board #%d (%s) → %s" % [serial, _ip_for_serial(serial), label], "ok")
	_check_confirm()

# ─────────────────────────────────────────────────────────────
#  IP HELPERS
# ─────────────────────────────────────────────────────────────
func _ip_for_serial(serial: int) -> String:
	for d in discovered:
		if d["serial"] == serial:
			return d["ip"]
	return ""

# ─────────────────────────────────────────────────────────────
#  UI REFRESH
# ─────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	_build_slot_rects()
	board_grid.queue_redraw()
	_rebuild_ip_list()
	_rebuild_summary()
	_check_confirm()

func _rebuild_ip_list() -> void:
	for c in ip_list.get_children():
		c.queue_free()
	if discovered.is_empty():
		var lbl := Label.new()
		lbl.text = "No boards discovered yet."
		ip_list.add_child(lbl)
		return

	# Build reverse map: serial → slot label
	var assigned_map := {}
	for i in slot_assigned.size():
		if slot_assigned[i] > 0:
			assigned_map[slot_assigned[i]] = layout["slots"][i]

	for d in discovered:
		var serial : int    = d["serial"]
		var ip     : String = d["ip"]
		var row := HBoxContainer.new()
		ip_list.add_child(row)

		# Serial badge
		var badge := Label.new()
		badge.text = str(serial)
		badge.custom_minimum_size = Vector2(24, 24)
		row.add_child(badge)

		# IP
		var addr := Label.new()
		addr.text = ip
		addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(addr)

		# Assigned tag
		if assigned_map.has(serial):
			var tag := Label.new()
			tag.text = "[%s]" % assigned_map[serial]
			row.add_child(tag)

		# Flash button
		if not assigned_map.has(serial) or flashing_serial == serial:
			var fb := Button.new()
			fb.text = "💡 ON" if flashing_serial == serial else "💡"
			fb.pressed.connect(
				func(): if flashing_serial == serial: _led_off(serial) else: _flash_led(serial)
			)
			row.add_child(fb)

func _rebuild_summary() -> void:
	for c in summary.get_children():
		c.queue_free()
	var use_pos : bool = int(layout["boards"]) <= 2
	for i in slot_assigned.size():
		var serial : int    = int(slot_assigned[i])
		var label  : String = layout["slots"][i]
		var pos_label : String = label if use_pos else ("Board %d" % (i+1))
		var row := HBoxContainer.new()
		summary.add_child(row)

		var pos_lbl := Label.new()
		pos_lbl.text = pos_label + " : "
		row.add_child(pos_lbl)

		var val_lbl := Label.new()
		val_lbl.text = ("#%d  %s" % [serial, _ip_for_serial(serial)]) if serial > 0 else "—"
		row.add_child(val_lbl)

func _check_confirm() -> void:
	var all_filled : bool = slot_assigned.all(func(v): return v > 0)
	confirm_btn.disabled = not all_filled
	var filled : int = 0
	for v in slot_assigned:
		if int(v) > 0:
			filled += 1
	footer_hint.text = "All assigned — ready!" if all_filled \
		else "%d / %d slots filled." % [filled, slot_assigned.size()]

# ─────────────────────────────────────────────────────────────
#  CONFIRM / GAMES
# ─────────────────────────────────────────────────────────────
func _on_confirm_pressed() -> void:
	confirmed = true
	confirm_btn.text = "✅ Confirmed"
	confirm_btn.disabled = true
	games_btn.show()

	# Build and push to GlobalScript
	GlobalScript.board_layout = layout["id"]
	if int(layout["boards"]) <= 2:
		var labels : Array = layout["slots"]
		for i in slot_assigned.size():
			var serial : int   = int(slot_assigned[i])
			var lbl    : String = (labels[i] as String).to_lower()
			match lbl:
				"left":   GlobalScript.board_ip_left   = _ip_for_serial(serial)
				"right":  GlobalScript.board_ip_right  = _ip_for_serial(serial)
				"top":    GlobalScript.board_ip_top    = _ip_for_serial(serial)
				"bottom": GlobalScript.board_ip_bottom = _ip_for_serial(serial)
	else:
		# For 3-6 boards: board1..board6
		if not GlobalScript.get("multi_board_ips"):
			pass  # add var multi_board_ips: Array = [] to GlobalScript
		var arr := []
		for i in slot_assigned.size():
			arr.append({
				"board": i + 1,
				"position": layout["slots"][i],
				"ip": _ip_for_serial(slot_assigned[i])
			})
		GlobalScript.multi_board_ips = arr

	# Persist
	var cfg := {
		"layout":      layout["id"],
		"boards":      layout["boards"],
		"assignments": []
	}
	for i in slot_assigned.size():
		cfg["assignments"].append({
			"slot":     layout["slots"][i],
			"serial":   slot_assigned[i],
			"ip":       _ip_for_serial(slot_assigned[i])
		})
	var f := FileAccess.open("user://board_config.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(cfg))
	f.close()
	print("✅ Board config saved: ", cfg)
	set_status("✅ Config saved! Press 🎮 Games to continue.", "ok")

func _on_games_pressed() -> void:
	get_tree().change_scene_to_file("res://Games/MainMenu.tscn")  # ← your path

# ─────────────────────────────────────────────────────────────
#  STATUS BAR
# ─────────────────────────────────────────────────────────────
func set_status(msg: String, type: String) -> void:
	status_text.text = msg
	match type:
		"ok":   status_dot.color = Color(0.0, 0.86, 0.44)
		"warn": status_dot.color = Color(1.0, 0.84, 0.25)
		"err":  status_dot.color = Color(1.0, 0.32, 0.32)
		"info": status_dot.color = Color(0.24, 0.55, 1.0)
		_:      status_dot.color = Color(0.3, 0.33, 0.47)

# ─────────────────────────────────────────────────────────────
#  RESIZE
# ─────────────────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_build_slot_rects()
		board_grid.queue_redraw()
