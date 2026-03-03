extends Area2D

# ── Constants ─────────────────────────────────────────────────────────────────
const LERP_SPEED_NORMAL: float = 0.25   # normal smoothing
const LERP_SPEED_FAST:   float = 0.55   # faster when far from target (>200 px gap)
const FAST_THRESHOLD_PX: float = 200.0  # distance at which fast mode kicks in

# ── Screen boundaries (auto-detected from GlobalScript) ───────────────────────
var MIN_X_VALUE: float
var MAX_X_VALUE: float

# ── Weight state ──────────────────────────────────────────────────────────────
var left_weight:  float = 0.0
var right_weight: float = 0.0

# ── Settings ──────────────────────────────────────────────────────────────────
@onready var adapt_toggle: bool = false
@onready var debug_mode         = DebugSettings.debug_mode
@onready var game: Node2D       = $".."


# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	print("Paddle:: _ready")
	_setup_boundaries()
	print("Paddle:: MIN_X=%.1f  MAX_X=%.1f  width=%.1f" % [
		MIN_X_VALUE, MAX_X_VALUE, MAX_X_VALUE - MIN_X_VALUE
	])


func _setup_boundaries() -> void:
	var paddle_half: float = 50.0
	if has_node("CollisionShape2D") and $CollisionShape2D.shape:
		var shape = $CollisionShape2D.shape
		if shape is RectangleShape2D:
			paddle_half = shape.size.x / 2.0
		elif shape is CapsuleShape2D:
			paddle_half = shape.radius
		elif shape is CircleShape2D:
			paddle_half = shape.radius

	MIN_X_VALUE = float(GlobalScript.MIN_X) + paddle_half
	MAX_X_VALUE = float(GlobalScript.MAX_X) - paddle_half


# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if debug_mode:
		position.x = clampf(get_global_mouse_position().x, MIN_X_VALUE, MAX_X_VALUE)
		position.y = 615.0
		return

	if _read_board_weights():
		_update_paddle_from_weight()

	position.x = clampf(position.x, MIN_X_VALUE, MAX_X_VALUE)
	position.y = 615.0


# ── Safe snapshot read ────────────────────────────────────────────────────────
func _read_board_weights() -> bool:
	var cops: Array = GlobalScript.local_cops.duplicate()

	if cops.size() < 2:
		return false

	var cop_a = cops[1]
	var cop_b = cops[0]

	if typeof(cop_a) != TYPE_DICTIONARY or typeof(cop_b) != TYPE_DICTIONARY:
		return false

	var ax: float = cop_a.get("x", 0.0)
	var bx: float = cop_b.get("x", 0.0)

	if ax <= bx:
		left_weight  = cop_a.get("weight", 0.0)
		right_weight = cop_b.get("weight", 0.0)
	else:
		left_weight  = cop_b.get("weight", 0.0)
		right_weight = cop_a.get("weight", 0.0)

	return true


# ── Weight → paddle X ─────────────────────────────────────────────────────────
func _update_paddle_from_weight() -> void:
	var total: float = left_weight + right_weight
	if total <= 0.0:
		return

	# Clamp individual weights so noise (e.g. -0.1N) doesn't distort percentage
	var lw: float = maxf(left_weight,  0.0)
	var rw: float = maxf(right_weight, 0.0)
	var t:  float = lw + rw
	if t <= 0.0:
		return

	var left_pct: float = lw / t   # 0.0 = all right, 1.0 = all left

	# Direct linear map — no threshold gate, runs every physics frame
	# left_pct=1.0 → MIN_X_VALUE (left edge)
	# left_pct=0.0 → MAX_X_VALUE (right edge)
	var target_x: float = lerp(MIN_X_VALUE, MAX_X_VALUE, left_pct)

	# Adaptive lerp: snap faster when the paddle is far behind the target
	var gap: float  = abs(target_x - position.x)
	var spd: float  = LERP_SPEED_FAST if gap > FAST_THRESHOLD_PX else LERP_SPEED_NORMAL
	position.x      = lerp(position.x, target_x, spd)

	# Throttled debug (~1 s at 30 fps)
	if Engine.get_process_frames() % 30 == 0:
		print("🏏 L=%.1fN(%.1f%%)  R=%.1fN(%.1f%%)  Total=%.1fN  target_x=%.1f  pos.x=%.1f  gap=%.0f  spd=%.2f  [MIN=%.0f MAX=%.0f]" % [
			lw, left_pct * 100.0,
			rw, (1.0 - left_pct) * 100.0,
			t, target_x, position.x,
			gap, spd,
			MIN_X_VALUE, MAX_X_VALUE
		])


# ── Adapt-PROM toggle ─────────────────────────────────────────────────────────
func _on_adapt_prom_toggled(toggled_on: bool) -> void:
	if toggled_on and not GlobalSignals.assessment_done:
		game.pause_game()
		game.button_nodes.adapt_prom.button_pressed = false
		game.button_nodes.warning_window.visible = true
		return
	adapt_toggle = toggled_on
