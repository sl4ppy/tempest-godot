extends Node2D
## Enemy shot pool. See ENTITIES.md § Invader Charges.
## 4-slot pool, shots travel from enemy toward player (decreasing Y).

const VS = preload("res://scripts/vector_shapes.gd")

const NICHARG: int = 4     # Max simultaneous enemy shots
const DEACTIVATE_Y: float = 0x10  # Shot reaches player rim

# Per-shot state arrays
var active: Array[bool] = []
var shot_y: Array[float] = []    # Y-depth
var shot_l1: Array[int] = []     # Lane
var shot_speed: float = 1.0      # Per-tick movement (toward player)

# References
var well: Node2D


func _ready() -> void:
	active.resize(NICHARG)
	shot_y.resize(NICHARG)
	shot_l1.resize(NICHARG)
	clear_all()


func clear_all() -> void:
	for i in NICHARG:
		active[i] = false
		shot_y[i] = 0.0
		shot_l1[i] = 0


func init_for_wave(well_renderer: Node2D, charge_spd: float) -> void:
	well = well_renderer
	# Speed is already computed via TIMES8 in invader_manager
	shot_speed = absf(charge_spd)
	clear_all()


## Try to fire an enemy shot from a given position.
func fire(lane: int, y_pos: float) -> bool:
	for i in NICHARG:
		if not active[i]:
			active[i] = true
			shot_y[i] = y_pos
			shot_l1[i] = lane
			queue_redraw()
			return true
	return false


## Advance all active enemy shots toward player. Called each game tick.
func move_all() -> void:
	var any_changed := false
	for i in NICHARG:
		if not active[i]:
			continue
		shot_y[i] -= shot_speed
		if shot_y[i] <= DEACTIVATE_Y:
			active[i] = false
		any_changed = true

	if any_changed:
		queue_redraw()


## Check if any enemy shot hit the player. Returns true if hit.
func check_player_hit(player_lane: int, player_y: float) -> bool:
	for i in NICHARG:
		if not active[i]:
			continue
		if shot_l1[i] == player_lane and shot_y[i] <= player_y + 4.0:
			active[i] = false
			queue_redraw()
			return true
	return false


## Get active shots for collision detection against player shots.
func get_active_shots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in NICHARG:
		if active[i]:
			result.append({"idx": i, "y": shot_y[i], "l1": shot_l1[i]})
	return result


## Deactivate a shot by index (hit by player shot).
func deactivate(idx: int) -> void:
	if idx >= 0 and idx < NICHARG:
		active[idx] = false
		queue_redraw()


func get_active_count() -> int:
	var count: int = 0
	for i in NICHARG:
		if active[i]:
			count += 1
	return count


var _anim_frame: int = 0


func advance_anim() -> void:
	_anim_frame = (_anim_frame + 1) % 4


func _draw() -> void:
	if well == null:
		return

	var color: Color = Colors.get_color(Colors.WHITE)
	for i in NICHARG:
		if not active[i]:
			continue

		var depth_frac: float = well.depth_to_frac(shot_y[i])
		var edges: Array[Vector2] = well.get_lane_edges(shot_l1[i], depth_frac)
		var center: Vector2 = (edges[0] + edges[1]) * 0.5
		var lane_width: float = edges[0].distance_to(edges[1])
		var tangent: Vector2 = (edges[1] - edges[0]).normalized()
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		if normal.dot(well.screen_center - center) < 0:
			normal = -normal

		var shape_name: String = "eshot_%d" % _anim_frame
		var sz: float = lane_width * 0.5
		VS.draw_shape(self, shape_name, center, tangent, normal,
			sz, color, 1.5)
