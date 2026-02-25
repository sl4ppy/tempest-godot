extends Node2D
## Renders the well (playfield) using 3D-to-2D perspective projection.
## See PLAYFIELD.md for geometry data and DISPLAY_COMPILER.md for rendering pipeline.

const NUM_LINES: int = 16

# Screen space configuration
var screen_center := Vector2(384, 540)
var screen_scale: float = 88.0

# Camera / eye position (set per well shape from HOLEYL/HOLEZL tables)
var eye := Vector3(0x80, 0x10, 0x80)  # EXL, EYL, EZL
var z_adjust: float = 0.0  # ZADJL vanishing point offset

# Well geometry: 16 vertices for near ring (rim) and far ring
var near_x: Array[float] = []
var near_z: Array[float] = []
var far_x: Array[float] = []
var far_z: Array[float] = []
var is_closed: bool = true  # Closed tube vs open/planar

# Cached projected points for use by entities
var near_screen: Array[Vector2] = []
var far_screen: Array[Vector2] = []

# Colors
var well_color := Color(0.0, 0.0, 1.0)  # Blue (default WELCOL)
var cursor_color := Color(1.0, 1.0, 0.0)  # Yellow
var player_line: int = 14  # Which lane the player is on

# Spike data: per-lane Y-depth of spike tip (0xF0 = no spike). Set by game_manager.
var spike_depths: Array[int] = []


func _draw() -> void:
	if near_x.is_empty():
		return

	near_screen.clear()
	far_screen.clear()

	# Project all vertices
	for i in NUM_LINES:
		near_screen.append(project(Vector3(near_x[i], 0x10, near_z[i])))
		far_screen.append(project(Vector3(far_x[i], 0xF0, far_z[i])))

	var line_count: int = NUM_LINES if is_closed else NUM_LINES - 1

	# Draw far ring segments
	for i in line_count:
		var next := (i + 1) % NUM_LINES
		draw_line(far_screen[i], far_screen[next], well_color * 0.5, 1.0)

	# Draw spokes (radial lines from near to far)
	for i in NUM_LINES:
		var color := cursor_color if (i == player_line or i == (player_line + 1) % NUM_LINES) else well_color
		draw_line(near_screen[i], far_screen[i], color, 1.5)

	# Draw near ring segments (rim) — "flashlight" highlights player's lane
	for i in line_count:
		var next := (i + 1) % NUM_LINES
		var color := cursor_color if (i == player_line) else well_color
		draw_line(near_screen[i], near_screen[next], color, 2.0)

	# Draw spikes — green lines along lane centers where LINEY < 0xF0.
	# See ENTITIES.md § Spiker spike system.
	if spike_depths.size() >= NUM_LINES:
		var spike_color: Color = Colors.get_color(Colors.GREEN)
		for i in line_count:
			if spike_depths[i] >= 0xF0:
				continue
			var spike_frac: float = depth_to_frac(float(spike_depths[i]))
			var tip_left: Vector2 = near_screen[i].lerp(far_screen[i], spike_frac)
			var tip_right: Vector2 = near_screen[(i + 1) % NUM_LINES].lerp(far_screen[(i + 1) % NUM_LINES], spike_frac)
			var tip: Vector2 = (tip_left + tip_right) * 0.5
			var base: Vector2 = (far_screen[i] + far_screen[(i + 1) % NUM_LINES]) * 0.5
			draw_line(tip, base, spike_color, 1.5)


## WORSCR perspective projection. See HARDWARE_REGISTERS.md § WORSCR Protocol.
func project(world: Vector3) -> Vector2:
	var dy: float = world.y - eye.y
	if absf(dy) < 0.001:
		dy = 0.001
	var inv: float = 1.0 / dy
	var sx: float = (world.x - eye.x) * inv
	var sz: float = (world.z - eye.z) * inv + z_adjust
	return Vector2(sx, -sz) * screen_scale + screen_center


## Convert a Y-depth value to a perspective-correct depth fraction (0=near, 1=far).
## Linear Y produces non-linear screen motion due to 1/y projection.
## This maps through inverse-depth so lerp in screen space matches perspective.
func depth_to_frac(y_depth: float) -> float:
	var near_y: float = 0x10
	var far_y: float = 0xF0
	var ey: float = eye.y  # Negative (e.g., -24 for Circle)
	var inv_near: float = 1.0 / (near_y - ey)
	var inv_far: float = 1.0 / (far_y - ey)
	var inv_y: float = 1.0 / (clampf(y_depth, near_y, far_y) - ey)
	var denom: float = inv_near - inv_far
	if absf(denom) < 0.0001:
		return clampf((y_depth - near_y) / (far_y - near_y), 0.0, 1.0)
	return clampf((inv_near - inv_y) / denom, 0.0, 1.0)


## Interpolate a screen position along a spoke at a given depth fraction (0=near, 1=far).
func get_spoke_position(lane: int, depth_frac: float) -> Vector2:
	if near_screen.is_empty():
		return screen_center
	var idx: int = lane % NUM_LINES
	return near_screen[idx].lerp(far_screen[idx], depth_frac)


## Get the center of a lane (between two adjacent spokes) at a given depth.
func get_lane_center(lane: int, depth_frac: float) -> Vector2:
	if near_screen.is_empty():
		return screen_center
	var idx: int = lane % NUM_LINES
	var next: int = (lane + 1) % NUM_LINES
	var p1: Vector2 = near_screen[idx].lerp(far_screen[idx], depth_frac)
	var p2: Vector2 = near_screen[next].lerp(far_screen[next], depth_frac)
	return (p1 + p2) * 0.5


## Get both spoke positions bounding a lane at a given depth.
## Returns [left_spoke, right_spoke] in screen coordinates.
func get_lane_edges(lane: int, depth_frac: float) -> Array[Vector2]:
	if near_screen.is_empty():
		return [screen_center, screen_center]
	var idx: int = lane % NUM_LINES
	var next: int = (lane + 1) % NUM_LINES
	var left: Vector2 = near_screen[idx].lerp(far_screen[idx], depth_frac)
	var right: Vector2 = near_screen[next].lerp(far_screen[next], depth_frac)
	return [left, right]


## Get the rim position between two adjacent spoke endpoints for the player cursor.
func get_rim_position(lane: int, frac: float) -> Vector2:
	if near_screen.is_empty():
		return screen_center
	var idx: int = lane % NUM_LINES
	var next: int = (lane + 1) % NUM_LINES
	return near_screen[idx].lerp(near_screen[next], frac)


## Load a well shape by index (0-15). Data from PLAYFIELD.md Appendix A.
func load_shape(shape_data: Dictionary) -> void:
	near_x.clear()
	near_z.clear()
	for v in shape_data.linex:
		near_x.append(float(v))
	for v in shape_data.linez:
		near_z.append(float(v))
	is_closed = not shape_data.planar

	# Far ring = inner ring, lerp toward center (0x80)
	far_x.resize(NUM_LINES)
	far_z.resize(NUM_LINES)
	for i in NUM_LINES:
		far_x[i] = lerpf(0x80, near_x[i], 0.5)
		far_z[i] = lerpf(0x80, near_z[i], 0.5)

	# Camera parameters from per-shape tables
	eye.y = -float(shape_data.holeyl)
	z_adjust = float(shape_data.holzad) / 256.0

	queue_redraw()
