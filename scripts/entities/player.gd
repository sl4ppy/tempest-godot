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
var in_drop: bool = false  # True during CDROP — use direct projection for rendering

# Death explosion. See ENTITIES.md § Player Death (SPLAT).
const SPLAT_SPOKES: int = 16
const DEATH_COLORS: Array[int] = [Colors.WHITE, Colors.YELLOW, Colors.RED]
var death_timer: int = 0
var death_max: int = 15

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
	in_drop = false
	queue_redraw()


## GETCUR + MOVCUR — read input and update position. Called each game tick.
## Start death explosion animation at current position.
func start_death(duration: int = 15) -> void:
	alive = false
	death_timer = duration
	death_max = duration
	queue_redraw()


## Advance death animation by one tick. Returns true when finished.
func tick_death() -> bool:
	if death_timer > 0:
		death_timer -= 1
		queue_redraw()
	return death_timer <= 0


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
	if well == null or well.near_screen.size() < 16:
		return

	if not alive:
		_draw_death_explosion()
		return

	var frac: float = float(curspo % 16) / 16.0
	var p1: Vector2
	var p2: Vector2

	if in_drop:
		# CDROP: camera is tracking the player through the well. The cached
		# near_screen/far_screen are unreliable (near rim may be behind camera).
		# Project the player's world position directly — since the camera tracks
		# at constant distance, this gives a stable screen position.
		var t: float = clampf((cursy - 0x10) / (0xF0 - 0x10), 0.0, 1.0)
		var x1: float = lerpf(well.near_x[cursl1], well.far_x[cursl1], t)
		var z1: float = lerpf(well.near_z[cursl1], well.far_z[cursl1], t)
		var x2: float = lerpf(well.near_x[cursl2], well.far_x[cursl2], t)
		var z2: float = lerpf(well.near_z[cursl2], well.far_z[cursl2], t)
		p1 = well.project(Vector3(x1, cursy, z1))
		p2 = well.project(Vector3(x2, cursy, z2))
	elif cursy > 0x10 + 0.5:
		# Below rim (not in drop) — interpolate along spokes at current depth
		var depth_frac: float = well.depth_to_frac(cursy)
		var edges: Array[Vector2] = well.get_lane_edges(cursl1, depth_frac)
		p1 = edges[0]
		p2 = edges[1]
	else:
		# At rim — use near screen positions
		p1 = well.near_screen[cursl1]
		p2 = well.near_screen[cursl2]

	var pos: Vector2 = p1.lerp(p2, frac)

	# Orientation: tangent along lane edge, normal pointing outward from center
	var tangent: Vector2 = (p2 - p1).normalized()
	var normal: Vector2 = Vector2(-tangent.y, tangent.x)
	if normal.dot(well.screen_center - pos) < 0:
		normal = -normal

	# Scale based on lane segment length
	var seg_len: float = p1.distance_to(p2)
	var sz: float = maxf(seg_len, 10.0)
	var color: Color = Colors.get_color(Colors.YELLOW)
	var lw: float = 2.5

	VS.draw_shape(self, "player", pos, tangent, normal, sz, color, lw)


## Draw SPLAT death explosion — expanding 16-spoke starburst with cycling colors.
## See ENTITIES.md § Player Death, DATA_ASSETS.md § SPLAT shapes.
func _draw_death_explosion() -> void:
	if death_timer <= 0:
		return

	var frac: float = float(curspo % 16) / 16.0
	var pos: Vector2
	if in_drop and cursy > 0x10 + 0.5:
		# During CDROP: use direct projection (camera is tracking player)
		var t: float = clampf((cursy - 0x10) / (0xF0 - 0x10), 0.0, 1.0)
		var x1: float = lerpf(well.near_x[cursl1], well.far_x[cursl1], t)
		var z1: float = lerpf(well.near_z[cursl1], well.far_z[cursl1], t)
		var x2: float = lerpf(well.near_x[cursl2], well.far_x[cursl2], t)
		var z2: float = lerpf(well.near_z[cursl2], well.far_z[cursl2], t)
		var pp1: Vector2 = well.project(Vector3(x1, cursy, z1))
		var pp2: Vector2 = well.project(Vector3(x2, cursy, z2))
		pos = pp1.lerp(pp2, frac)
	else:
		pos = well.get_rim_position(cursl1, frac)

	# Progress: 0.0 (just died) → 1.0 (fully expanded)
	var progress: float = 1.0 - (float(death_timer) / float(death_max))

	# Scale expands progressively (CM=1,2,4,8 across 4 frames → exponential)
	var radius: float = 20.0 + progress * progress * 120.0

	# Color cycles through white → yellow → red
	var color_idx: int = (death_max - death_timer) % DEATH_COLORS.size()
	var color: Color = Colors.get_color(DEATH_COLORS[color_idx])

	# Draw 16-spoke starburst (SPOK16 pattern)
	for i in SPLAT_SPOKES:
		var angle: float = float(i) * TAU / float(SPLAT_SPOKES)
		# Add slight random jitter per spoke for organic feel
		var spoke_len: float = radius * (0.7 + 0.3 * absf(sin(angle * 3.0 + progress * 5.0)))
		var end: Vector2 = pos + Vector2.from_angle(angle) * spoke_len
		draw_line(pos, end, color, maxf(2.5 - progress * 1.5, 1.0))
