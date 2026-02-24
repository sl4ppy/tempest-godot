extends Node2D
## Player cursor (blaster). See ENTITIES.md § Player Cursor.
## Position tracked as CURSPO (0-255), lane = CURSPO / 16.

const VS = preload("res://scripts/vector_shapes.gd")

# Movement constants
const SPINNER_CLAMP: int = 31  # Max ±31 per frame
const INITIAL_LANE1: int = 14  # CURSL1 start
const INITIAL_LANE2: int = 15  # CURSL2 start

# Position state
var curspo: int = INITIAL_LANE1 * 16 + 8  # Fractional position (0-255)
var cursl1: int = INITIAL_LANE1  # Primary lane
var cursl2: int = INITIAL_LANE2  # Secondary lane (cursl1 + 1)
var cursy: float = 0x10  # Y-depth (near rim = 0x10)

# State flags
var alive: bool = true
var is_planar: bool = false
var num_lanes: int = 16  # 16 for closed, 15 for planar

# References
var well: Node2D  # WellRenderer


func init_for_wave(well_renderer: Node2D, planar: bool) -> void:
	well = well_renderer
	is_planar = planar
	num_lanes = 15 if is_planar else 16
	curspo = INITIAL_LANE1 * 16 + 8
	cursl1 = INITIAL_LANE1
	cursl2 = INITIAL_LANE2
	cursy = 0x10
	alive = true
	queue_redraw()


## GETCUR + MOVCUR — read input and update position. Called each game tick.
func move(input_delta: int) -> void:
	if not alive:
		return

	# Clamp spinner input
	var clamped: int = clampi(input_delta, -SPINNER_CLAMP, SPINNER_CLAMP)

	# Update fractional position
	curspo += clamped

	# Wrap or clamp depending on well type
	if is_planar:
		curspo = clampi(curspo, 0, num_lanes * 16 - 1)
	else:
		curspo = curspo % 256
		if curspo < 0:
			curspo += 256

	# Derive lane from fractional position
	@warning_ignore("integer_division")
	cursl1 = curspo / 16
	if is_planar:
		cursl1 = mini(cursl1, num_lanes - 1)
	cursl2 = (cursl1 + 1) % 16
	if is_planar:
		cursl2 = mini(cursl2, 15)

	queue_redraw()


func _draw() -> void:
	if well == null or not alive or well.near_screen.size() < 16:
		return

	# Get screen position on the rim
	var frac: float = float(curspo % 16) / 16.0
	var pos: Vector2 = well.get_rim_position(cursl1, frac)

	# Orientation: tangent along rim, normal pointing outward from center
	var p1: Vector2 = well.near_screen[cursl1]
	var p2: Vector2 = well.near_screen[cursl2]

	var tangent: Vector2 = (p2 - p1).normalized()
	# Normal points toward center of well (shape Y-up = into the well)
	var normal: Vector2 = Vector2(-tangent.y, tangent.x)
	if normal.dot(well.screen_center - pos) < 0:
		normal = -normal

	# Scale based on lane segment length
	var seg_len: float = p1.distance_to(p2)
	var sz: float = maxf(seg_len, 30.0)
	var color: Color = Colors.get_color(Colors.YELLOW)

	# Draw original LIFE1 vector shape
	VS.draw_shape(self, "player", pos, tangent, normal, sz, color, 2.5)
