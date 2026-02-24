extends Node2D
## Player shot pool. See ENTITIES.md § Player Charges.
## 8-slot pool, shots travel down spokes at PCVELO speed.

const VS = preload("res://scripts/vector_shapes.gd")

const NPCHARG: int = 8     # Max simultaneous player shots
const PCVELO: float = 9.0  # Speed in Y-depth units per tick
const DEACTIVATE_Y: float = 0xF0  # Shot dies at far end
const MAX_SPIKE_HITS: int = 2  # CHARCO threshold — shot dies after 2 spike hits

# Per-shot state arrays
var active: Array[bool] = []
var shot_y: Array[float] = []    # Y-depth (0x10=near, 0xF0=far)
var shot_l1: Array[int] = []     # Lane (spoke index)
var shot_l2: Array[int] = []     # Adjacent lane
var spike_hits: Array[int] = []  # CHARCO — spike hit counter per shot

# References
var well: Node2D  # WellRenderer


func _ready() -> void:
	active.resize(NPCHARG)
	shot_y.resize(NPCHARG)
	shot_l1.resize(NPCHARG)
	shot_l2.resize(NPCHARG)
	spike_hits.resize(NPCHARG)
	clear_all()


func clear_all() -> void:
	for i in NPCHARG:
		active[i] = false
		shot_y[i] = 0.0
		shot_l1[i] = 0
		shot_l2[i] = 0
		spike_hits[i] = 0


func init_for_wave(well_renderer: Node2D) -> void:
	well = well_renderer
	clear_all()


## FIREPC — try to fire a shot from the player's current position.
func fire(lane1: int, lane2: int) -> bool:
	for i in NPCHARG:
		if not active[i]:
			active[i] = true
			shot_y[i] = 0x10  # Start at near rim
			shot_l1[i] = lane1
			shot_l2[i] = lane2
			spike_hits[i] = 0
			queue_redraw()
			return true
	return false  # All slots full


## MOVCHA — advance all active shots. Called each game tick.
## Also performs LIFECT spike collision: erases spike and counts hits.
func move_all(spikes: Array[int] = []) -> void:
	var any_changed := false
	for i in NPCHARG:
		if not active[i]:
			continue
		shot_y[i] += PCVELO
		if shot_y[i] >= DEACTIVATE_Y:
			active[i] = false
			any_changed = true
			continue

		# LIFECT — check spike collision on this lane.
		# If shot Y >= spike Y, shot has reached the spike.
		# Erase spike down to shot position; increment CHARCO.
		if spikes.size() > shot_l1[i]:
			var spike_y: int = spikes[shot_l1[i]]
			if spike_y < 0xF0 and shot_y[i] >= spike_y:
				# Damage spike: push it down to shot's position
				spikes[shot_l1[i]] = int(shot_y[i])
				if spikes[shot_l1[i]] >= 0xF0:
					spikes[shot_l1[i]] = 0xF0  # Fully erased
				spike_hits[i] += 1
				if spike_hits[i] >= MAX_SPIKE_HITS:
					active[i] = false
		any_changed = true

	if any_changed:
		queue_redraw()


func get_active_count() -> int:
	var count: int = 0
	for i in NPCHARG:
		if active[i]:
			count += 1
	return count


func _draw() -> void:
	if well == null:
		return

	var color: Color = Colors.get_color(Colors.PSHCTR)
	for i in NPCHARG:
		if not active[i]:
			continue

		# Depth fraction: 0x10=near(0.0), 0xF0=far(1.0)
		var depth_frac: float = well.depth_to_frac(shot_y[i])
		depth_frac = clampf(depth_frac, 0.0, 1.0)

		# Use lane edges for proper sizing
		var edges: Array[Vector2] = well.get_lane_edges(shot_l1[i], depth_frac)
		var center: Vector2 = (edges[0] + edges[1]) * 0.5
		var lane_width: float = edges[0].distance_to(edges[1])
		var tangent: Vector2 = (edges[1] - edges[0]).normalized()
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		if normal.dot(well.screen_center - center) < 0:
			normal = -normal

		# Draw original DIARA2 dot pattern (two concentric rings of dots)
		var dot_scale: float = lane_width * 0.4
		var dot_size: float = maxf(lerpf(2.5, 1.0, depth_frac), 1.0)
		VS.draw_dots(self, "pshot", center, tangent, normal,
			dot_scale, color, dot_size)
