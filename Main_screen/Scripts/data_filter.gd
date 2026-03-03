extends Node
"""
Data Filter Classes for GDScript
Provides EMA smoothing and outlier detection for Vector3 and coordinate data
Matches Python filters for dual-layer filtering
"""
class_name DataFilter


# ============================================================
# Exponential Moving Average Filter for Vector3
# ============================================================
class EMAFilter:
	"""Exponential Moving Average filter for smoothing Vector3 data"""
	var alpha: float = 0.3
	var value: Vector3 = Vector3.ZERO
	var initialized: bool = false

	func _init(smoothing_alpha: float = 0.3):
		alpha = smoothing_alpha
		initialized = false

	func update(new_value: Vector3) -> Vector3:
		"""Update filter and return smoothed value"""
		if not initialized:
			value = new_value
			initialized = true
			return value

		# EMA formula: smoothed = alpha * new + (1 - alpha) * previous
		value = alpha * new_value + (1.0 - alpha) * value
		return value

	func reset():
		"""Reset filter state"""
		initialized = false
		value = Vector3.ZERO

	func _to_string() -> String:
		return "EMA(alpha=%.2f, value=%s)" % [alpha, value]


# ============================================================
# Outlier Detection Filter for Vector3
# ============================================================
class OutlierFilter:
	"""Detects and rejects outlier values using z-score"""
	var history: Array = []
	var max_history: int = 10
	var threshold: float = 2.0
	var rejected_count: int = 0

	func _init(history_size: int = 10, outlier_threshold: float = 2.0):
		max_history = history_size
		threshold = outlier_threshold
		history.clear()
		rejected_count = 0

	func is_outlier(new_value: Vector3) -> bool:
		"""Check if value is outlier using z-score"""
		if history.size() < 3:
			# Need at least 3 samples for statistics
			return false

		# Calculate mean
		var mean = Vector3.ZERO
		for h in history:
			mean += h
		mean /= history.size()

		# Calculate standard deviation
		var variance = 0.0
		for h in history:
			variance += (h - mean).length_squared()
		variance /= history.size()

		var std_dev = sqrt(variance)
		if std_dev < 0.001:
			# All values are same, no outliers
			return false

		# Calculate z-score
		var distance = (new_value - mean).length()
		var z_score = distance / std_dev

		return z_score > threshold

	func update(new_value: Vector3) -> Vector3:
		"""Update filter, reject outliers"""
		if not is_outlier(new_value):
			history.append(new_value)
			if history.size() > max_history:
				history.pop_front()
			return new_value
		else:
			# Outlier detected, return last valid value
			rejected_count += 1
			return history[-1] if history.size() > 0 else new_value

	func get_rejected_count() -> int:
		"""Get number of rejected outliers"""
		return rejected_count

	func reset():
		"""Reset filter"""
		history.clear()
		rejected_count = 0

	func _to_string() -> String:
		return "OutlierFilter(threshold=%.1f, history=%d, rejected=%d)" % [threshold, history.size(), rejected_count]


# ============================================================
# Combined Coordinate Filter (Outlier + EMA)
# ============================================================
class CoordinateFilter:
	"""
	Combined filter for Vector3 coordinates
	Stage 1: Outlier rejection (removes spikes)
	Stage 2: EMA smoothing (reduces jitter)
	"""
	var ema: EMAFilter
	var outlier: OutlierFilter
	var update_count: int = 0

	func _init(alpha: float = 0.3, outlier_threshold: float = 2.0):
		ema = EMAFilter.new(alpha)
		outlier = OutlierFilter.new(10, outlier_threshold)
		update_count = 0

	func update(pos: Vector3) -> Vector3:
		"""
		Filter 3D coordinate
		Returns smoothed position
		"""
		update_count += 1

		# Stage 1: Remove outliers
		var clean = outlier.update(pos)

		# Stage 2: Apply smoothing
		var smooth = ema.update(clean)

		return smooth

	func reset():
		"""Reset all filters"""
		ema.reset()
		outlier.reset()
		update_count = 0

	func get_stats() -> Dictionary:
		"""Get filter statistics"""
		return {
			"updates": update_count,
			"outliers_rejected": outlier.get_rejected_count()
		}

	func _to_string() -> String:
		var stats = get_stats()
		return "CoordinateFilter(updates=%d, outliers=%d)" % [stats["updates"], stats["outliers_rejected"]]


# ============================================================
# Scalar Filter (for float/int values)
# ============================================================
class ScalarFilter:
	"""Filter for scalar (single value) data"""
	var ema: EMAFilter

	func _init(alpha: float = 0.3):
		ema = EMAFilter.new(alpha)

	func update(value: float) -> float:
		"""Filter scalar value"""
		var vec_in = Vector3(value, 0, 0)
		var vec_out = ema.update(vec_in)
		return vec_out.x

	func reset():
		"""Reset filter"""
		ema.reset()

	func _to_string() -> String:
		return "ScalarFilter(alpha=%.2f)" % ema.alpha


# ============================================================
# Array/Vector Filter
# ============================================================
class ArrayFilter:
	"""Filter for array-like data (e.g., keypoint positions)"""
	var previous_value: PackedVector3Array = []
	var ema_filters: Array = []
	var alpha: float = 0.3

	func _init(size: int = 18, smoothing_alpha: float = 0.3):
		alpha = smoothing_alpha
		# Create one EMA filter per array element
		for i in range(size):
			ema_filters.append(EMAFilter.new(alpha))

	func update(values: PackedVector3Array) -> PackedVector3Array:
		"""Filter array of Vector3 values"""
		if values.size() != ema_filters.size():
			push_warning("ArrayFilter: input size %d doesn't match filter size %d" % [values.size(), ema_filters.size()])
			return values

		var smoothed = PackedVector3Array()
		for i in range(values.size()):
			if i < ema_filters.size():
				var filtered = ema_filters[i].update(values[i])
				smoothed.append(filtered)

		return smoothed

	func reset():
		"""Reset all filters"""
		for filter in ema_filters:
			filter.reset()
		previous_value.clear()

	func _to_string() -> String:
		return "ArrayFilter(size=%d, alpha=%.2f)" % [ema_filters.size(), alpha]


# ============================================================
# Helper Functions
# ============================================================

static func create_coordinate_filter(alpha: float = 0.3, threshold: float = 2.0) -> CoordinateFilter:
	"""Factory function to create coordinate filter"""
	return CoordinateFilter.new(alpha, threshold)


static func create_ema_filter(alpha: float = 0.3) -> EMAFilter:
	"""Factory function to create EMA filter"""
	return EMAFilter.new(alpha)


static func create_outlier_filter(window_size: int = 10, threshold: float = 2.0) -> OutlierFilter:
	"""Factory function to create outlier filter"""
	return OutlierFilter.new(window_size, threshold)


static func create_array_filter(size: int = 18, alpha: float = 0.3) -> ArrayFilter:
	"""Factory function to create array filter"""
	return ArrayFilter.new(size, alpha)


# ============================================================
# Testing
# ============================================================
static func test_filters():
	"""Test filters with synthetic data"""
	print("\n=== Testing DataFilter Classes ===\n")

	# Test CoordinateFilter
	print("1. Testing CoordinateFilter:")
	var coord_filter = CoordinateFilter.new(0.3, 2.0)

	for i in range(10):
		var angle = i * 0.628  # ~2*pi/10
		var x = cos(angle) * 0.5
		var y = sin(angle) * 0.5
		var z = 0.3

		# Add noise
		x += randf_range(-0.05, 0.05)
		y += randf_range(-0.05, 0.05)

		var pos = Vector3(x, y, z)
		var smoothed = coord_filter.update(pos)

		if i % 3 == 0:
			print("  Step %d: Raw=(%.3f, %.3f, %.3f) -> Smooth=(%.3f, %.3f, %.3f)" % [
				i, pos.x, pos.y, pos.z,
				smoothed.x, smoothed.y, smoothed.z
			])

	var stats = coord_filter.get_stats()
	print("  Stats: %s" % coord_filter)
	print()

	# Test ArrayFilter
	print("2. Testing ArrayFilter (for FBP keypoints):")
	var array_filter = ArrayFilter.new(5, 0.4)

	for i in range(8):
		var keypoints = PackedVector3Array()
		for k in range(5):
			var x = cos(i * 0.314) * (k + 1) * 0.1
			var y = sin(i * 0.314) * (k + 1) * 0.1
			var z = k * 0.2
			keypoints.append(Vector3(x, y, z))

		var smoothed = array_filter.update(keypoints)

		if i % 2 == 0:
			print("  Step %d: Smoothed[0]=(%.3f, %.3f, %.3f)" % [i, smoothed[0].x, smoothed[0].y, smoothed[0].z])

	print()
	print("=== Tests Complete ===\n")


# Auto-test on script load (comment out for production)
#static func _static_init():
#	if OS.is_debug_build():
#		test_filters()
