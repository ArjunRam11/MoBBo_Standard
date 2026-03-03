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
# Boardsetupscene.gd  (BoardIPSetup)
# Pure Godot — no Python involved.
#
# DISCOVERY: send "Hey!mobbos" broadcast → 192.168.0.255:23000
#            collect sender IPs on same socket (mirrors Python recvfrom).
#
# FIXES IN THIS VERSION:
#  1. Board grid now fills available space properly (GridWrap expands).
#  2. Slot cells keep a reasonable aspect ratio — not thin slivers.
#  3. Mouse clicks work via _input() with global→local conversion,
#     bypassing the gui_input filter issue.
# ══════════════════════════════════════════════════════════════

# Boardsetupscene.gd
# Attaches to the root Control node of Boardsetup_IP.tscn
# Builds the ENTIRE UI in code — no @onready node-path dependencies.
# This means it works even if the .tscn only has the bare root Control.
#
# DISCOVERY: broadcast "Hey!mobbos" → 192.168.0.255:23000
#             collect sender IPs on the same socket (mirrors Python logic).
# ══════════════════════════════════════════════════════════════════════════

extends Control

# ─── Network ─────────────────────────────────────────────────────────────────
const BOARD_PORT    := 23000
const DISCOVERY_MSG := "Hey!mobbos"
const LED_ON_BYTE   := 0x21
const LED_OFF_BYTE  := 0x20
const SCAN_SECS     := 4.0
const BROADCAST_IP  := "192.168.0.255"
const LOCAL_IP      := "192.168.0.105"

var udp_sock  : PacketPeerUDP = PacketPeerUDP.new()
var _scanning : bool = false

# ─── Layout definitions ───────────────────────────────────────────────────────
var LAYOUTS : Array = [
  { "id":"1x2","label":"1 × 2  (Left / Right)",   "cols":2,"rows":1,"boards":2,
	"slots":["LEFT","RIGHT"] },
  { "id":"2x1","label":"2 × 1  (Top / Bottom)",   "cols":1,"rows":2,"boards":2,
	"slots":["TOP","BOTTOM"] },
  { "id":"1x3","label":"1 × 3  (3 columns)",      "cols":3,"rows":1,"boards":3,
	"slots":["LEFT","CENTER","RIGHT"] },
  { "id":"3x1","label":"3 × 1  (3 rows)",         "cols":1,"rows":3,"boards":3,
	"slots":["TOP","MIDDLE","BOTTOM"] },
  { "id":"2x2","label":"2 × 2  (Grid)",           "cols":2,"rows":2,"boards":4,
	"slots":["TOP-LEFT","TOP-RIGHT","BOT-LEFT","BOT-RIGHT"] },
  { "id":"1x4","label":"1 × 4  (4 columns)",      "cols":4,"rows":1,"boards":4,
	"slots":["1","2","3","4"] },
  { "id":"4x1","label":"4 × 1  (4 rows)",         "cols":1,"rows":4,"boards":4,
	"slots":["1","2","3","4"] },
  { "id":"1x5","label":"1 × 5  (5 columns)",      "cols":5,"rows":1,"boards":5,
	"slots":["1","2","3","4","5"] },
  { "id":"5x1","label":"5 × 1  (5 rows)",         "cols":1,"rows":5,"boards":5,
	"slots":["1","2","3","4","5"] },
  { "id":"2x3","label":"2 × 3  (2r × 3c)",        "cols":3,"rows":2,"boards":6,
	"slots":["R1C1","R1C2","R1C3","R2C1","R2C2","R2C3"] },
  { "id":"3x2","label":"3 × 2  (3r × 2c)",        "cols":2,"rows":3,"boards":6,
	"slots":["R1C1","R1C2","R2C1","R2C2","R3C1","R3C2"] },
  { "id":"1x6","label":"1 × 6  (6 columns)",      "cols":6,"rows":1,"boards":6,
	"slots":["1","2","3","4","5","6"] },
  { "id":"6x1","label":"6 × 1  (6 rows)",         "cols":1,"rows":6,"boards":6,
	"slots":["1","2","3","4","5","6"] },
]

# ─── State ────────────────────────────────────────────────────────────────────
var layout          : Dictionary = {}
var discovered      : Array      = []
var slot_assigned   : Array      = []
var flashing_serial : int        = 0
var pending_serial  : int        = 0
var scanning        : bool       = false
var confirmed       : bool       = false
var slot_rects      : Array      = []

# ─── UI node references (created in _build_ui) ───────────────────────────────
var layout_select : OptionButton  = null
var scan_btn      : Button        = null
var clear_btn     : Button        = null
var board_grid    : Control       = null
var ip_list       : VBoxContainer = null
var summary_box   : VBoxContainer = null
var status_dot    : ColorRect     = null
var status_lbl    : Label         = null
var footer_hint   : Label         = null
var confirm_btn   : Button        = null
var games_btn     : Button        = null

# ─── Colors ───────────────────────────────────────────────────────────────────
const C_EMPTY    := Color(0.08, 0.10, 0.16)
const C_ASSIGNED := Color(0.04, 0.20, 0.10)
const C_FLASH    := Color(0.20, 0.16, 0.04)
const C_AUTO     := Color(0.06, 0.10, 0.22)
const C_BDR_DEF  := Color(0.20, 0.25, 0.40)
const C_BDR_ASGN := Color(0.0,  0.86, 0.44)
const C_BDR_FLSH := Color(1.0,  0.84, 0.25)
const C_BDR_AUTO := Color(0.24, 0.55, 1.0)

# ══════════════════════════════════════════════════════════════════════════════
#  _ready  — build UI then initialise
# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("board_setup_scene")
	_build_ui()
	_apply_layout(0)
	set_status("Select a layout and press SCAN to find boards.", "")

# ══════════════════════════════════════════════════════════════════════════════
#  BUILD ENTIRE UI PROGRAMMATICALLY
# ══════════════════════════════════════════════════════════════════════════════
func _build_ui() -> void:
	# Clear any existing children from the tscn
	for c in get_children():
		c.queue_free()

	# ── Root VBox ────────────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# ── Header ───────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(header)

	var title := Label.new()
	title.text = "MoBBo Device Setup"
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)

	# ── Body (grid | right panel) ─────────────────────────────────────────────
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	vbox.add_child(body)

	# Grid side
	var grid_wrap := VBoxContainer.new()
	grid_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(grid_wrap)

	var grid_lbl := Label.new()
	grid_lbl.text = "Board Layout"
	grid_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid_wrap.add_child(grid_lbl)

	board_grid = Control.new()
	board_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_grid.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	board_grid.mouse_filter          = Control.MOUSE_FILTER_STOP
	board_grid.draw.connect(_draw_grid)
	grid_wrap.add_child(board_grid)

	# Right panel
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	layout_select = OptionButton.new()
	for l in LAYOUTS:
		layout_select.add_item(l["label"])
	layout_select.selected = 0
	layout_select.item_selected.connect(_on_layout_selected)
	right.add_child(layout_select)

	var ctrl_row := HBoxContainer.new()
	right.add_child(ctrl_row)

	scan_btn = Button.new()
	scan_btn.text = "🔍 Scan"
	scan_btn.pressed.connect(_on_scan_pressed)
	ctrl_row.add_child(scan_btn)

	clear_btn = Button.new()
	clear_btn.text = "✕ Reset"
	clear_btn.pressed.connect(_on_clear_pressed)
	ctrl_row.add_child(clear_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	ip_list = VBoxContainer.new()
	ip_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ip_list)

	summary_box = VBoxContainer.new()
	summary_box.size_flags_vertical = Control.SIZE_SHRINK_END
	right.add_child(summary_box)

	# ── Status bar ────────────────────────────────────────────────────────────
	var status_bar := HBoxContainer.new()
	status_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(status_bar)

	status_dot = ColorRect.new()
	status_dot.custom_minimum_size = Vector2(14, 14)
	status_bar.add_child(status_dot)

	status_lbl = Label.new()
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(status_lbl)

	# ── Footer ────────────────────────────────────────────────────────────────
	var footer := HBoxContainer.new()
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(footer)

	footer_hint = Label.new()
	footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_hint)

	games_btn = Button.new()
	games_btn.text = "🎮 Games →"
	games_btn.pressed.connect(_on_games_pressed)
	games_btn.hide()
	footer.add_child(games_btn)

	confirm_btn = Button.new()
	confirm_btn.text = "✅ Confirm"
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(_on_confirm_pressed)
	footer.add_child(confirm_btn)

# ══════════════════════════════════════════════════════════════════════════════
#  INPUT — global handler for board-grid clicks
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
#  PROCESS — poll UDP during scan + CoP debug print
# ══════════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	# Discovery: collect sender IPs while scanning
	if _scanning:
		while udp_sock.get_available_packet_count() > 0:
			udp_sock.get_packet()
			var addr : String = udp_sock.get_packet_ip()
			if addr == "" or addr == LOCAL_IP: continue
			if discovered.any(func(d): return d["ip"] == addr): continue
			discovered.append({ "serial": discovered.size() + 1, "ip": addr })
			_refresh_ui()
			set_status("Found %d board(s). Still scanning…" % discovered.size(), "ok")

	# CoP debug print (throttled to every 60 frames)
	if CoPManager.is_configured() and Engine.get_process_frames() % 60 == 0:
		_print_cop_debug()

# ─── CoP debug print ──────────────────────────────────────────────────────────
func _print_cop_debug() -> void:
	var local_cops : Array = CoPManager.get_local_cops()
	if local_cops.is_empty(): return

	print("─── CoP Debug ─── layout=%s ───" % CoPManager.board_layout)
	for lc in local_cops:
		print("  [Board %d | slot=%-8s | col=%d row=%d]  local=(%.3f, %.3f) cm  global=(%.3f, %.3f) cm  w=%.2f" \
			% [ lc["board_idx"], lc["slot"], lc["col"], lc["row"],
				lc["cop_x_local"], lc["cop_y_local"],
				lc["cop_x_global"], lc["cop_y_global"],
				lc["weight"] ])

	var gcop : Vector3 = CoPManager.get_combined_cop()
	var sw   : Vector2 = CoPManager.get_scaled_position_2d()
	print("  ► COMBINED  global CoP = (%.3f, %.3f) cm   total_weight=%.2f" \
		% [gcop.x, gcop.y, CoPManager.combined_weight])
	print("  ► scaled 2D = (%.1f, %.1f) px" % [sw.x, sw.y])

# ─────────────────────────────────────────────────────────────────────────────
#  LAYOUT
# ─────────────────────────────────────────────────────────────────────────────
func _on_layout_selected(idx: int) -> void:
	_apply_layout(idx)
	set_status("Layout: %s.  Press SCAN." % layout["label"], "info")

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

# ─────────────────────────────────────────────────────────────────────────────
#  SLOT GEOMETRY
# ─────────────────────────────────────────────────────────────────────────────
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
	if raw_cw / maxf(raw_ch, 1.0) > MAX_RATIO:
		raw_cw = raw_ch * MAX_RATIO
	elif raw_ch / maxf(raw_cw, 1.0) > MAX_RATIO:
		raw_ch = raw_cw * MAX_RATIO

	var total_w : float = raw_cw * cols + GAP * (cols - 1)
	var total_h : float = raw_ch * rows + GAP * (rows - 1)
	var ox      : float = PAD + (aw - total_w) * 0.5
	var oy      : float = PAD + (ah - total_h) * 0.5

	for i in layout["slots"].size():
		var col : int = i % cols
		var row : int = i / cols
		slot_rects.append(Rect2(
			ox + col * (raw_cw + GAP),
			oy + row * (raw_ch + GAP),
			raw_cw, raw_ch))

# ─────────────────────────────────────────────────────────────────────────────
#  DRAWING
# ─────────────────────────────────────────────────────────────────────────────
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

		var bg := C_EMPTY
		if is_assigned:   bg = C_ASSIGNED
		elif is_flashing: bg = C_FLASH
		elif is_auto:     bg = C_AUTO
		board_grid.draw_rect(r, bg, true)

		var bdr := C_BDR_DEF
		if is_assigned:   bdr = C_BDR_ASGN
		elif is_flashing: bdr = C_BDR_FLSH
		elif is_auto:     bdr = C_BDR_AUTO
		board_grid.draw_rect(r, bdr, false, 2.5)

		var cx := r.position.x + r.size.x * 0.5
		var cy := r.position.y + r.size.y * 0.5

		if is_assigned:
			var sn    := str(serial)
			var sn_sz := int(clamp(minf(r.size.x, r.size.y) * 0.32, 18, 52))
			var sn_ts := font.get_string_size(sn, HORIZONTAL_ALIGNMENT_LEFT, -1, sn_sz)
			board_grid.draw_string(font, Vector2(cx - sn_ts.x * 0.5, cy - 4),
				sn, HORIZONTAL_ALIGNMENT_LEFT, -1, sn_sz, Color(0.0, 0.86, 0.44, 0.95))

		var lbl    := layout["slots"][i] as String
		var lbl_sz := int(clamp(minf(r.size.x * 0.2, r.size.y * 0.22), 10, 22))
		var lbl_col := Color(1, 1, 1, 0.28)
		if is_assigned:   lbl_col = Color(0.6, 1.0, 0.75, 0.85)
		elif is_flashing: lbl_col = Color(1.0, 0.84, 0.25, 0.95)
		elif is_auto:     lbl_col = Color(0.24, 0.55, 1.0, 0.85)
		var lbl_ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_sz)
		board_grid.draw_string(font,
			Vector2(cx - lbl_ts.x * 0.5, cy + (22 if is_assigned else 6)),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_sz, lbl_col)

		if is_assigned:
			var ip_str := _ip_for_serial(serial)
			var ip_sz  := int(clamp(minf(r.size.x * 0.13, r.size.y * 0.14), 8, 13))
			var ip_ts  := font.get_string_size(ip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, ip_sz)
			board_grid.draw_string(font, Vector2(cx - ip_ts.x * 0.5, cy + 38),
				ip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, ip_sz, Color(0.5, 1.0, 0.7, 0.6))

		if not is_assigned:
			var hint := ""
			if is_auto and pending_serial == 0: hint = "tap to auto-assign"
			elif is_flashing:                   hint = "← click here"
			if hint != "":
				var h_sz := int(clamp(minf(r.size.x * 0.10, r.size.y * 0.13), 8, 12))
				var h_ts := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, h_sz)
				board_grid.draw_string(font,
					Vector2(cx - h_ts.x * 0.5, r.position.y + r.size.y - 10),
					hint, HORIZONTAL_ALIGNMENT_LEFT, -1, h_sz, Color(0.24, 0.55, 1.0, 0.7))

func _slot_at(local_pos: Vector2) -> int:
	for i in slot_rects.size():
		if slot_rects[i].has_point(local_pos): return i
	return -1

# ─────────────────────────────────────────────────────────────────────────────
#  SCAN
# ─────────────────────────────────────────────────────────────────────────────
func _on_scan_pressed() -> void:
	if scanning: return
	scanning = true
	discovered.clear()
	_reset_assignments()

	udp_sock.close()
	if udp_sock.bind(0, "0.0.0.0") != OK:
		set_status("❌ UDP socket error. Try again.", "err")
		scanning = false
		return

	udp_sock.set_broadcast_enabled(true)
	udp_sock.set_dest_address(BROADCAST_IP, BOARD_PORT)
	udp_sock.put_packet(DISCOVERY_MSG.to_utf8_buffer())
	print("📡 Sent '%s' → %s:%d" % [DISCOVERY_MSG, BROADCAST_IP, BOARD_PORT])

	_scanning     = true
	scan_btn.text = "Scanning…"
	set_status("📡 Broadcast sent → %s  listening for replies…" % BROADCAST_IP, "warn")

	await get_tree().create_timer(SCAN_SECS).timeout

	_scanning     = false
	scanning      = false
	udp_sock.set_broadcast_enabled(false)
	scan_btn.text = "🔍 Scan"

	if discovered.is_empty():
		set_status("❌ No boards replied. Check network / power.", "err")
	else:
		set_status("✅ Found %d board(s). Flash 💡 → click its slot." % discovered.size(), "ok")
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
	if games_btn:  games_btn.hide()
	if confirm_btn:
		confirm_btn.text     = "✅ Confirm"
		confirm_btn.disabled = true
	_refresh_ui()

# ─────────────────────────────────────────────────────────────────────────────
#  LED
# ─────────────────────────────────────────────────────────────────────────────
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

func _send_led(serial: int, on: bool) -> void:
	var ip := _ip_for_serial(serial)
	if ip == "": return
	udp_sock.set_broadcast_enabled(false)
	udp_sock.set_dest_address(ip, BOARD_PORT)
	udp_sock.put_packet(PackedByteArray([LED_ON_BYTE if on else LED_OFF_BYTE]))

# ─────────────────────────────────────────────────────────────────────────────
#  AUTO-ASSIGN
# ─────────────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────────────
#  SLOT ASSIGN
# ─────────────────────────────────────────────────────────────────────────────
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

func _ip_for_serial(serial: int) -> String:
	for d in discovered:
		if d["serial"] == serial: return d["ip"]
	return ""

# ─────────────────────────────────────────────────────────────────────────────
#  UI REFRESH
# ─────────────────────────────────────────────────────────────────────────────
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

		var badge := Label.new()
		badge.text = "#%d" % serial
		badge.custom_minimum_size = Vector2(32, 0)
		row.add_child(badge)

		var addr_lbl := Label.new()
		addr_lbl.text = ip
		addr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(addr_lbl)

		if assigned_map.has(serial):
			var tag := Label.new()
			tag.text = "[%s]" % assigned_map[serial]
			tag.modulate = Color(0.4, 1.0, 0.6)
			row.add_child(tag)

		if not assigned_map.has(serial) or flashing_serial == serial:
			var fb := Button.new()
			fb.text = "💡 ON" if flashing_serial == serial else "💡"
			var cap_serial := serial
			fb.pressed.connect(
				func(): if flashing_serial == cap_serial: _led_off(cap_serial) else: _flash_led(cap_serial))
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

# ─────────────────────────────────────────────────────────────────────────────
#  STATUS
# ─────────────────────────────────────────────────────────────────────────────
func set_status(msg: String, level: String) -> void:
	if status_lbl:  status_lbl.text = msg
	if status_dot:
		match level:
			"ok":   status_dot.color = Color(0.0, 0.86, 0.44)
			"warn": status_dot.color = Color(1.0, 0.84, 0.25)
			"err":  status_dot.color = Color(1.0, 0.20, 0.18)
			_:      status_dot.color = Color(0.4, 0.4, 0.4)

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIRM + NAVIGATE
# ─────────────────────────────────────────────────────────────────────────────
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

	CoPManager.set_board_config(layout["id"], assignments_arr)
	set_status("✅ Config saved! Press 🎮 Games to continue.", "ok")
	print("✅ Confirmed: layout=%s  %s" % [layout["id"], str(assignments_arr)])

func _on_games_pressed() -> void:
	get_tree().change_scene_to_file("res://Main_screen/Scenes/mode.tscn")
