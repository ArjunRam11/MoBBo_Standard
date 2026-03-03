# cop_visualiser.gd
# ══════════════════════════════════════════════════════════════════════════════
# CoP Visualiser Scene
#
# Layout:
#   LEFT PANEL (300px)  — weight bar graphs per board (real-time)
#   CENTER PANEL        — board layout grid with local + global CoP dots
#   RIGHT PANEL (260px) — timer controls (input, start/stop recording), back btn
#
# Recording:
#   Saves timestamped CSV to user://cop_recording_<datetime>.csv
#   Columns: time_s, global_cop_x, global_cop_y, total_weight,
#            [per board: board_N_local_x, board_N_local_y, board_N_weight]
#
# To add to select_game scene:
#   var cop_vis_scene = preload("res://Main_screen/Scenes/cop_visualiser.tscn")
#   func _on_assessment_pressed(): get_tree().change_scene_to_packed(cop_vis_scene)
# ══════════════════════════════════════════════════════════════════════════════

extends Control

# ── Physical board dimensions (must match CoPManager) ────────────────────────
const BOARD_W : float = 60.0
const BOARD_H : float = 45.0
const HALF_W  : float = 30.0
const HALF_H  : float = 22.5

# ── Drawing constants ─────────────────────────────────────────────────────────
const DOT_GLOBAL  : float = 14.0   # global CoP dot radius
const DOT_LOCAL   : float =  8.0   # local CoP dot radius
const TRAIL_LEN   : int   = 80     # frames of CoP trail
const BAR_MAX_KG  : float = 150.0  # full-scale for weight bars

# ── Colors ────────────────────────────────────────────────────────────────────
const C_BG          := Color(0.07, 0.09, 0.14)
const C_PANEL       := Color(0.10, 0.13, 0.20)
const C_BOARD_BG    := Color(0.10, 0.14, 0.22)
const C_BOARD_BDR   := Color(0.22, 0.30, 0.50)
const C_GLOBAL_DOT  := Color(0.0,  0.95, 0.55)
const C_LOCAL_DOT   := Color(1.0,  0.75, 0.10)
const C_TRAIL_G     := Color(0.0,  0.95, 0.55, 0.18)
const C_TRAIL_L     := Color(1.0,  0.75, 0.10, 0.12)
const C_BAR_LOW     := Color(0.18, 0.55, 1.0)
const C_BAR_MID     := Color(0.10, 0.90, 0.45)
const C_BAR_HIGH    := Color(1.0,  0.40, 0.20)
const C_GRID_LINE   := Color(1.0,  1.0,  1.0,  0.06)
const C_AXIS        := Color(1.0,  1.0,  1.0,  0.15)
const C_TEXT        := Color(0.85, 0.92, 1.0)
const C_TEXT_DIM    := Color(0.55, 0.65, 0.80)
const C_REC_ON      := Color(1.0,  0.20, 0.20)
const C_REC_OFF     := Color(0.25, 0.75, 0.40)

# ── UI references ─────────────────────────────────────────────────────────────
var _bar_panel   : Control       = null
var _viz_canvas  : Control       = null
var _timer_input : LineEdit      = null
var _start_btn   : Button        = null
var _stop_btn    : Button        = null
var _back_btn    : Button        = null
var _rec_label   : Label         = null
var _elapsed_lbl : Label         = null
var _info_label  : Label         = null
var _cop_label   : Label         = null

# ── State ─────────────────────────────────────────────────────────────────────
var _global_trail : Array = []   # Array of Vector2 (cm)
var _local_trails : Dictionary = {}   # board_idx → Array of Vector2 (cm, local frame)

# ── Recording state ───────────────────────────────────────────────────────────
var _recording       : bool      = false
var _rec_file        : FileAccess = null
var _rec_elapsed     : float     = 0.0
var _rec_duration    : float     = 0.0   # 0 = unlimited
var _rec_timer       : Timer     = null
var _rec_start_time  : float     = 0.0

# ── Layout cache (from CoPManager) ───────────────────────────────────────────
var _n_cols    : int   = 1
var _n_rows    : int   = 1
var _x_min     : float = -HALF_W
var _x_max     : float =  HALF_W
var _y_min     : float = -HALF_H
var _y_max     : float =  HALF_H
var _board_count : int = 0

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_read_layout_from_cop_manager()
	_build_ui()
	_setup_rec_timer()

func _read_layout_from_cop_manager() -> void:
	_board_count = CoPManager.get_board_count()
	var lid : String = CoPManager.board_layout
	var parts := lid.split("x")
	if parts.size() == 2:
		_n_cols = int(parts[1])
		_n_rows = int(parts[0])
	else:
		_n_cols = max(1, _board_count)
		_n_rows = 1
	var rx : Vector2 = CoPManager.get_layout_range_x()
	var ry : Vector2 = CoPManager.get_layout_range_y()
	_x_min = rx.x; _x_max = rx.y
	_y_min = ry.x; _y_max = ry.y

# ── Recording timer ───────────────────────────────────────────────────────────
func _setup_rec_timer() -> void:
	_rec_timer = Timer.new()
	_rec_timer.wait_time = 1.0
	_rec_timer.timeout.connect(_on_rec_tick)
	add_child(_rec_timer)

# ══════════════════════════════════════════════════════════════════════════════
#  PROCESS
# ══════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	_update_trails()
	if _viz_canvas:  _viz_canvas.queue_redraw()
	if _bar_panel:   _bar_panel.queue_redraw()
	if _recording:   _write_rec_row(delta)
	_update_info_labels()

func _update_trails() -> void:
	var gcop : Vector2 = CoPManager.global_cop_cm
	if gcop != Vector2.ZERO:
		_global_trail.append(gcop)
		if _global_trail.size() > TRAIL_LEN:
			_global_trail.pop_front()

	for lc in CoPManager.get_local_cops():
		var idx : int = lc.get("board_idx", 0)
		var lpt : Vector2 = Vector2(lc.get("cop_x_local", 0.0), lc.get("cop_y_local", 0.0))
		if not _local_trails.has(idx):
			_local_trails[idx] = []
		_local_trails[idx].append(lpt)
		if _local_trails[idx].size() > TRAIL_LEN:
			_local_trails[idx].pop_front()

func _update_info_labels() -> void:
	var gcop : Vector2 = CoPManager.global_cop_cm
	var w    : float   = CoPManager.combined_weight
	if _cop_label:
		_cop_label.text = "Global CoP: (%.1f, %.1f) cm   Total: %.1f kg" % [gcop.x, gcop.y, w]
	if _recording and _rec_elapsed_lbl():
		pass   # handled in _on_rec_tick

func _rec_elapsed_lbl() -> bool:
	return _elapsed_lbl != null

# ══════════════════════════════════════════════════════════════════════════════
#  BUILD UI
# ══════════════════════════════════════════════════════════════════════════════
func _build_ui() -> void:
	for c in get_children(): c.queue_free()

	# Dark background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# ── LEFT: weight bars ──────────────────────────────────────────────────
	var left_bg := PanelContainer.new()
	left_bg.custom_minimum_size = Vector2(290, 0)
	_style_panel(left_bg, C_PANEL)
	root.add_child(left_bg)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	var lm := MarginContainer.new()
	_set_margins(lm, 12)
	lm.add_child(left_vbox)
	left_bg.add_child(lm)

	var bar_title := _make_label("Weight Distribution", 14, true)
	bar_title.modulate = C_TEXT
	left_vbox.add_child(bar_title)

	_bar_panel = Control.new()
	_bar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar_panel.draw.connect(_draw_bars)
	left_vbox.add_child(_bar_panel)

	var legend_h := HBoxContainer.new()
	legend_h.add_theme_constant_override("separation", 10)
	left_vbox.add_child(legend_h)
	_add_legend_item(legend_h, C_LOCAL_DOT, "Local CoP")
	_add_legend_item(legend_h, C_GLOBAL_DOT, "Global CoP")

	# ── CENTER: viz canvas ─────────────────────────────────────────────────
	var center_vbox := VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	center_vbox.add_theme_constant_override("separation", 4)
	root.add_child(center_vbox)

	var title_row := HBoxContainer.new()
	title_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var cm := MarginContainer.new(); _set_margins(cm, 8, 8, 4, 4)
	cm.add_child(title_row); center_vbox.add_child(cm)

	var title_lbl := _make_label("CoP Visualiser — " + CoPManager.board_layout, 18, true)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.modulate = C_TEXT
	title_row.add_child(title_lbl)

	_cop_label = _make_label("Global CoP: -- cm   Total: -- kg", 12)
	_cop_label.modulate = C_GLOBAL_DOT
	title_row.add_child(_cop_label)

	_viz_canvas = Control.new()
	_viz_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viz_canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_viz_canvas.draw.connect(_draw_viz)
	center_vbox.add_child(_viz_canvas)

	# Legend row under canvas
	var leg_row := HBoxContainer.new()
	leg_row.size_flags_vertical = Control.SIZE_SHRINK_END
	var lm2 := MarginContainer.new(); _set_margins(lm2, 8, 8, 4, 4)
	lm2.add_child(leg_row); center_vbox.add_child(lm2)
	_add_legend_item(leg_row, C_LOCAL_DOT, "Local CoP  (board frame)")
	leg_row.add_child(_make_spacer(20))
	_add_legend_item(leg_row, C_GLOBAL_DOT, "Global CoP  (layout frame)")

	# ── RIGHT: controls ────────────────────────────────────────────────────
	var right_bg := PanelContainer.new()
	right_bg.custom_minimum_size = Vector2(250, 0)
	_style_panel(right_bg, C_PANEL)
	root.add_child(right_bg)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 14)
	var rm := MarginContainer.new(); _set_margins(rm, 14)
	rm.add_child(right_vbox); right_bg.add_child(rm)

	# Title
	var r_title := _make_label("Recording", 16, true)
	r_title.modulate = C_TEXT
	right_vbox.add_child(r_title)

	var sep1 := HSeparator.new(); right_vbox.add_child(sep1)

	# Duration input
	var dur_lbl := _make_label("Duration (seconds)", 11)
	dur_lbl.modulate = C_TEXT_DIM
	right_vbox.add_child(dur_lbl)

	_timer_input = LineEdit.new()
	_timer_input.placeholder_text = "e.g. 30  (blank = unlimited)"
	_timer_input.custom_minimum_size = Vector2(0, 36)
	right_vbox.add_child(_timer_input)

	# Start / Stop buttons
	_start_btn = Button.new()
	_start_btn.text = "▶  Start Recording"
	_start_btn.custom_minimum_size = Vector2(0, 44)
	_style_btn(_start_btn, C_REC_OFF)
	_start_btn.pressed.connect(_on_start_pressed)
	right_vbox.add_child(_start_btn)

	_stop_btn = Button.new()
	_stop_btn.text = "⏹  Stop Recording"
	_stop_btn.custom_minimum_size = Vector2(0, 44)
	_stop_btn.disabled = true
	_style_btn(_stop_btn, C_REC_ON)
	_stop_btn.pressed.connect(_on_stop_pressed)
	right_vbox.add_child(_stop_btn)

	var sep2 := HSeparator.new(); right_vbox.add_child(sep2)

	# Status / elapsed
	_rec_label = _make_label("● Idle", 13)
	_rec_label.modulate = C_TEXT_DIM
	right_vbox.add_child(_rec_label)

	_elapsed_lbl = _make_label("", 12)
	_elapsed_lbl.modulate = C_TEXT_DIM
	right_vbox.add_child(_elapsed_lbl)

	# Board info
	var sep3 := HSeparator.new(); right_vbox.add_child(sep3)
	var boards_lbl := _make_label("Boards  (%d detected)" % _board_count, 12)
	boards_lbl.modulate = C_TEXT_DIM
	right_vbox.add_child(boards_lbl)

	for lc in CoPManager.get_local_cops():
		var s : String = lc.get("slot", str(lc.get("board_idx",0)+1))
		var ip : String = lc.get("ip", "?")
		var bl := _make_label("  %s → %s" % [s, ip], 11)
		bl.modulate = C_TEXT_DIM
		right_vbox.add_child(bl)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(spacer)

	# Back button
	_back_btn = Button.new()
	_back_btn.text = "← Back to Games"
	_back_btn.custom_minimum_size = Vector2(0, 44)
	_style_btn(_back_btn, Color(0.20, 0.28, 0.50))
	_back_btn.pressed.connect(_on_back_pressed)
	right_vbox.add_child(_back_btn)

# ══════════════════════════════════════════════════════════════════════════════
#  DRAW — BAR GRAPH
# ══════════════════════════════════════════════════════════════════════════════
func _draw_bars() -> void:
	if _bar_panel == null: return
	var W : float = _bar_panel.size.x
	var H : float = _bar_panel.size.y
	if W < 10 or H < 10: return

	var cops : Array = CoPManager.get_local_cops()
	var n    : int   = max(1, cops.size())
	var slot_h : float = H / n
	var font   : Font  = ThemeDB.fallback_font
	const PAD : float = 10.0
	const BAR_H : float = 22.0

	for i in range(cops.size()):
		var lc     : Dictionary = cops[i]
		var w      : float      = lc.get("weight", 0.0)
		var slot   : String     = lc.get("slot", str(i+1))
		var cy     : float      = i * slot_h + slot_h * 0.5

		# Background track
		var track_y : float = cy - BAR_H * 0.5
		_bar_panel.draw_rect(Rect2(PAD, track_y, W - PAD*2, BAR_H),
			Color(0.12, 0.16, 0.26), true)
		_bar_panel.draw_rect(Rect2(PAD, track_y, W - PAD*2, BAR_H),
			Color(0.20, 0.28, 0.45, 0.5), false, 1.0)

		# Filled bar
		var fill_frac : float = clampf(w / BAR_MAX_KG, 0.0, 1.0)
		var fill_w    : float = fill_frac * (W - PAD*2)
		var bar_col   : Color
		if fill_frac < 0.4:
			bar_col = C_BAR_LOW.lerp(C_BAR_MID, fill_frac / 0.4)
		else:
			bar_col = C_BAR_MID.lerp(C_BAR_HIGH, (fill_frac - 0.4) / 0.6)

		if fill_w > 1.0:
			_bar_panel.draw_rect(Rect2(PAD, track_y, fill_w, BAR_H), bar_col, true)

		# Label
		var txt  : String = "%s   %.1f kg" % [slot, w]
		var t_sz : int    = 11
		_bar_panel.draw_string(font, Vector2(PAD + 4, cy + t_sz * 0.4),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, t_sz, C_TEXT)

		# Percentage label on right
		var total_w : float = CoPManager.combined_weight
		var pct_str : String = "%.0f%%" % (w / total_w * 100.0) if total_w > 0.0 else "0%"
		var pt_sz   : int    = 11
		var pt_ts   : Vector2 = font.get_string_size(pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1, pt_sz)
		_bar_panel.draw_string(font, Vector2(W - PAD - pt_ts.x - 2, cy + pt_sz * 0.4),
			pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1, pt_sz, bar_col)

# ══════════════════════════════════════════════════════════════════════════════
#  DRAW — BOARD GRID + CoP DOTS
# ══════════════════════════════════════════════════════════════════════════════
func _draw_viz() -> void:
	if _viz_canvas == null: return
	var CW : float = _viz_canvas.size.x
	var CH : float = _viz_canvas.size.y
	if CW < 10 or CH < 10: return

	const PAD  : float = 30.0
	const GAP  : float = 8.0
	var avail_w : float = CW - PAD * 2.0 - GAP * (_n_cols - 1)
	var avail_h : float = CH - PAD * 2.0 - GAP * (_n_rows - 1)
	var cell_w  : float = avail_w / _n_cols
	var cell_h  : float = avail_h / _n_rows

	# Clamp aspect ratio
	const MAX_RATIO : float = 2.5
	if cell_w / max(cell_h, 1.0) > MAX_RATIO: cell_w = cell_h * MAX_RATIO
	elif cell_h / max(cell_w, 1.0) > MAX_RATIO: cell_h = cell_w * MAX_RATIO

	var total_w2 : float = cell_w * _n_cols + GAP * (_n_cols - 1)
	var total_h2 : float = cell_h * _n_rows + GAP * (_n_rows - 1)
	var ox : float = PAD + (avail_w - total_w2) * 0.5
	var oy : float = PAD + (avail_h - total_h2) * 0.5

	# Build board rects
	var board_rects : Array = []
	var cops : Array = CoPManager.get_local_cops()
	var assignments : Array = CoPManager.assignments

	for i in range(_n_cols * _n_rows):
		var col : int   = i % _n_cols
		var row : int   = i / _n_cols
		var rx  : float = ox + col * (cell_w + GAP)
		var ry  : float = oy + row * (cell_h + GAP)
		board_rects.append(Rect2(rx, ry, cell_w, cell_h))

	# Draw each board cell
	var font : Font = ThemeDB.fallback_font
	for i in range(board_rects.size()):
		var r : Rect2 = board_rects[i]
		_viz_canvas.draw_rect(r, C_BOARD_BG, true)
		_viz_canvas.draw_rect(r, C_BOARD_BDR, false, 1.5)

		# Grid lines inside board
		for gx_line in range(1, 3):
			var lx : float = r.position.x + r.size.x * gx_line / 3.0
			_viz_canvas.draw_line(Vector2(lx, r.position.y), Vector2(lx, r.end.y), C_GRID_LINE, 1.0)
		for gy_line in range(1, 3):
			var ly : float = r.position.y + r.size.y * gy_line / 3.0
			_viz_canvas.draw_line(Vector2(r.position.x, ly), Vector2(r.end.x, ly), C_GRID_LINE, 1.0)

		# Center crosshair
		var cx : float = r.position.x + r.size.x * 0.5
		var cy_c: float = r.position.y + r.size.y * 0.5
		_viz_canvas.draw_line(Vector2(cx, r.position.y + 4), Vector2(cx, r.end.y - 4), C_AXIS, 1.0)
		_viz_canvas.draw_line(Vector2(r.position.x + 4, cy_c), Vector2(r.end.x - 4, cy_c), C_AXIS, 1.0)

		# Slot label
		var slot_name : String = ""
		if i < assignments.size():
			slot_name = assignments[i].get("slot", str(i+1))
		else:
			slot_name = str(i+1)
		var sl_sz : int = int(clamp(min(r.size.x * 0.12, r.size.y * 0.13), 9, 18))
		var sl_ts : Vector2 = font.get_string_size(slot_name, HORIZONTAL_ALIGNMENT_LEFT, -1, sl_sz)
		_viz_canvas.draw_string(font, Vector2(r.position.x + 6, r.position.y + sl_sz + 4),
			slot_name, HORIZONTAL_ALIGNMENT_LEFT, -1, sl_sz, Color(1,1,1,0.35))

	# ── Helper: local CoP cm → pixel in board rect ──────────────────────────
	# local frame: X in [-30,30], Y in [-22.5,22.5]
	# pixel: x maps L→R, y maps top→bottom (board front = screen top)

	# Draw LOCAL trails + dots
	for lc in cops:
		var idx : int = lc.get("board_idx", 0)
		if idx >= board_rects.size(): continue
		var r   : Rect2 = board_rects[idx]

		# Trail
		if _local_trails.has(idx):
			var trail : Array = _local_trails[idx]
			for t in range(trail.size()):
				var alpha : float = float(t) / trail.size() * 0.6
				var lpt   : Vector2 = trail[t]
				var px    : float   = r.position.x + (lpt.x + HALF_W) / BOARD_W * r.size.x
				var py    : float   = r.position.y + (lpt.y + HALF_H) / BOARD_H * r.size.y
				_viz_canvas.draw_circle(Vector2(px, py), 3.0, Color(C_TRAIL_L, alpha))

		# Live dot
		var lx  : float = lc.get("cop_x_local", 0.0)
		var ly  : float = lc.get("cop_y_local", 0.0)
		var dpx : float = r.position.x + (lx + HALF_W) / BOARD_W * r.size.x
		var dpy : float = r.position.y + (ly + HALF_H) / BOARD_H * r.size.y
		_viz_canvas.draw_circle(Vector2(dpx, dpy), DOT_LOCAL, C_LOCAL_DOT)
		_viz_canvas.draw_circle(Vector2(dpx, dpy), DOT_LOCAL, Color(1,1,1,0.7), false, 1.5)

		# Local CoP text
		var cop_txt : String = "(%.1f, %.1f)" % [lx, ly]
		var ct_sz   : int    = 9
		var ct_ts   : Vector2 = font.get_string_size(cop_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ct_sz)
		_viz_canvas.draw_string(font,
			Vector2(dpx - ct_ts.x * 0.5, dpy - DOT_LOCAL - 3),
			cop_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ct_sz, C_LOCAL_DOT)

	# ── Draw GLOBAL CoP trail + dot (mapped across entire layout) ───────────
	var layout_px_x : float = ox
	var layout_px_y : float = oy
	var layout_pw   : float = total_w2
	var layout_ph   : float = total_h2
	var gl_range_x  : float = _x_max - _x_min
	var gl_range_y  : float = _y_max - _y_min

	# Trail
	for t in range(_global_trail.size()):
		var alpha : float = float(t) / _global_trail.size() * 0.5
		var gpt   : Vector2 = _global_trail[t]
		var gpx   : float   = layout_px_x + (gpt.x - _x_min) / max(gl_range_x, 0.001) * layout_pw
		var gpy   : float   = layout_px_y + (gpt.y - _y_min) / max(gl_range_y, 0.001) * layout_ph
		_viz_canvas.draw_circle(Vector2(gpx, gpy), 4.0, Color(C_TRAIL_G, alpha))

	# Live global dot
	var gcop : Vector2 = CoPManager.global_cop_cm
	if CoPManager.combined_weight > 0.0:
		var gpx : float = layout_px_x + (gcop.x - _x_min) / max(gl_range_x, 0.001) * layout_pw
		var gpy : float = layout_px_y + (gcop.y - _y_min) / max(gl_range_y, 0.001) * layout_ph
		# Outer ring
		_viz_canvas.draw_circle(Vector2(gpx, gpy), DOT_GLOBAL + 4, Color(C_GLOBAL_DOT, 0.25), true)
		_viz_canvas.draw_circle(Vector2(gpx, gpy), DOT_GLOBAL, C_GLOBAL_DOT, true)
		_viz_canvas.draw_circle(Vector2(gpx, gpy), DOT_GLOBAL, Color(1,1,1,0.9), false, 2.0)

		var gc_txt : String = "(%.1f, %.1f) cm" % [gcop.x, gcop.y]
		var gc_sz  : int    = 10
		var gc_ts  : Vector2 = font.get_string_size(gc_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, gc_sz)
		_viz_canvas.draw_string(font,
			Vector2(gpx - gc_ts.x * 0.5, gpy + DOT_GLOBAL + gc_sz + 2),
			gc_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, gc_sz, C_GLOBAL_DOT)

# ══════════════════════════════════════════════════════════════════════════════
#  RECORDING
# ══════════════════════════════════════════════════════════════════════════════
func _on_start_pressed() -> void:
	if _recording: return

	# Parse duration
	var dur_str : String = _timer_input.text.strip_edges()
	_rec_duration = float(dur_str) if dur_str.is_valid_float() else 0.0

	# Open CSV file
	var dt  : Dictionary = Time.get_datetime_dict_from_system()
	var fname : String = "user://cop_recording_%04d%02d%02d_%02d%02d%02d.csv" \
		% [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	_rec_file = FileAccess.open(fname, FileAccess.WRITE)
	if _rec_file == null:
		_rec_label.text = "❌ Could not open file"
		return

	# Write CSV header
	var header : PackedStringArray = PackedStringArray([
		"time_s", "global_cop_x_cm", "global_cop_y_cm", "total_weight_kg"
	])
	for lc in CoPManager.get_local_cops():
		var s : String = lc.get("slot", str(lc.get("board_idx",0)+1))
		header.append("%s_local_cop_x" % s)
		header.append("%s_local_cop_y" % s)
		header.append("%s_weight_kg" % s)
	_rec_file.store_csv_line(header)

	_recording      = true
	_rec_elapsed    = 0.0
	_rec_start_time = Time.get_unix_time_from_system()
	_rec_timer.start()
	_start_btn.disabled = true
	_stop_btn.disabled  = false
	_rec_label.text     = "● Recording…"
	_rec_label.modulate = C_REC_ON
	_elapsed_lbl.text   = "0 s" + ("  / %d s" % int(_rec_duration) if _rec_duration > 0.0 else "")

func _on_stop_pressed() -> void:
	_stop_recording()

func _stop_recording() -> void:
	if not _recording: return
	_recording = false
	_rec_timer.stop()
	if _rec_file:
		_rec_file.flush()
		_rec_file.close()
		_rec_file = null
	_start_btn.disabled = false
	_stop_btn.disabled  = true
	_rec_label.text     = "✅ Saved  (%d s)" % int(_rec_elapsed)
	_rec_label.modulate = C_REC_OFF
	_elapsed_lbl.text   = ""

func _on_rec_tick() -> void:
	_rec_elapsed += 1.0
	var dur_str : String = ("  / %d s" % int(_rec_duration)) if _rec_duration > 0.0 else ""
	_elapsed_lbl.text = "%d s%s" % [int(_rec_elapsed), dur_str]
	if _rec_duration > 0.0 and _rec_elapsed >= _rec_duration:
		_stop_recording()

func _write_rec_row(_delta: float) -> void:
	if _rec_file == null: return
	var t    : float  = Time.get_unix_time_from_system() - _rec_start_time
	var gcop : Vector2 = CoPManager.global_cop_cm
	var tw   : float   = CoPManager.combined_weight
	var row  : PackedStringArray = PackedStringArray([
		"%.4f" % t,
		"%.4f" % gcop.x,
		"%.4f" % gcop.y,
		"%.4f" % tw
	])
	for lc in CoPManager.get_local_cops():
		row.append("%.4f" % lc.get("cop_x_local", 0.0))
		row.append("%.4f" % lc.get("cop_y_local", 0.0))
		row.append("%.4f" % lc.get("weight", 0.0))
	_rec_file.store_csv_line(row)

# ══════════════════════════════════════════════════════════════════════════════
#  BACK
# ══════════════════════════════════════════════════════════════════════════════
func _on_back_pressed() -> void:
	if _recording: _stop_recording()
	get_tree().change_scene_to_file("res://Main_screen/Scenes/select_game.tscn")

# ══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS
# ══════════════════════════════════════════════════════════════════════════════
func _make_label(txt: String, size: int = 12, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	if bold: l.add_theme_color_override("font_color", C_TEXT)
	return l

func _make_spacer(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c

func _add_legend_item(parent: Node, col: Color, txt: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	parent.add_child(h)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.color = col
	h.add_child(dot)
	var l := _make_label(txt, 11)
	l.modulate = C_TEXT_DIM
	h.add_child(l)

func _style_panel(p: PanelContainer, col: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", s)

func _style_btn(b: Button, col: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.15)
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sp)

func _set_margins(m: MarginContainer, all: int, right: int = -1, top: int = -1, bottom: int = -1) -> void:
	m.add_theme_constant_override("margin_left",   all)
	m.add_theme_constant_override("margin_right",  all if right  < 0 else right)
	m.add_theme_constant_override("margin_top",    all if top    < 0 else top)
	m.add_theme_constant_override("margin_bottom", all if bottom < 0 else bottom)

func _exit_tree() -> void:
	if _recording: _stop_recording()
