extends Node2D
## Renders the well (playfield) using 3D-to-2D perspective projection.
## See PLAYFIELD.md for geometry data and DISPLAY_COMPILER.md for rendering pipeline.

const NUM_LINES: int = 16

# Screen space configuration
var screen_center := Vector2(512, 512)
var screen_scale: float = 4.0

# Camera / eye position (set per well shape from HOLEYL/HOLEZL tables)
var eye := Vector3(0x80, 0x10, 0x80)  # EXL, EYL, EZL
var z_adjust: float = 0.0  # ZADJL vanishing point offset

# Well geometry: 16 vertices for near ring (rim) and far ring
var near_x: Array[float] = []
var near_z: Array[float] = []
var far_x: Array[float] = []
var far_z: Array[float] = []
var is_closed: bool = true  # Closed tube vs open/planar

# Colors
var well_color := Color(0.0, 0.0, 1.0)  # Blue (default WELCOL)
var cursor_color := Color(1.0, 1.0, 0.0)  # Yellow
var player_line: int = 0  # Which line the player is on


func _draw() -> void:
	if near_x.is_empty():
		return

	var near_screen: Array[Vector2] = []
	var far_screen: Array[Vector2] = []

	# Project all vertices
	for i in NUM_LINES:
		near_screen.append(_project(Vector3(near_x[i], 0x10, near_z[i])))
		far_screen.append(_project(Vector3(far_x[i], 0xF0, far_z[i])))

	# Draw spokes (radial lines from near to far)
	for i in NUM_LINES:
		var color := cursor_color if (i == player_line or i == (player_line + 1) % NUM_LINES) else well_color
		draw_line(near_screen[i], far_screen[i], color, 1.5)

	# Draw near ring segments (rim)
	var count := NUM_LINES if is_closed else NUM_LINES - 1
	for i in count:
		var next := (i + 1) % NUM_LINES
		var color := cursor_color if (i == player_line) else well_color
		draw_line(near_screen[i], near_screen[next], color, 1.5)

	# Draw far ring segments
	for i in count:
		var next := (i + 1) % NUM_LINES
		draw_line(far_screen[i], far_screen[next], well_color, 1.0)


## WORSCR perspective projection. See HARDWARE_REGISTERS.md § WORSCR Protocol.
func _project(world: Vector3) -> Vector2:
	var dy: float = world.y - eye.y
	if absf(dy) < 0.001:
		dy = 0.001
	var inv: float = 1.0 / dy
	var sx: float = (world.x - eye.x) * inv
	var sz: float = (world.z - eye.z) * inv + z_adjust
	return Vector2(sx, -sz) * screen_scale + screen_center


## Load a well shape by index (0-15). Data from PLAYFIELD.md Appendix A.
func load_shape(shape_index: int, shape_data: Dictionary) -> void:
	near_x = shape_data.linex.duplicate()
	near_z = shape_data.linez.duplicate()
	is_closed = not shape_data.planar

	# Far ring is the near ring scaled toward center (0x80)
	far_x.resize(NUM_LINES)
	far_z.resize(NUM_LINES)
	for i in NUM_LINES:
		far_x[i] = lerpf(0x80, near_x[i], 0.5)
		far_z[i] = lerpf(0x80, near_z[i], 0.5)

	# Camera parameters from per-shape tables
	eye.y = -float(shape_data.holeyl)
	z_adjust = float(shape_data.holzad) / 256.0

	queue_redraw()
