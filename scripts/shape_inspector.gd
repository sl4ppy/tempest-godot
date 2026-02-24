extends Control
## Visual debug tool for inspecting and verifying vector shape data.
## Step-through mode shows how the VG beam traces each shape.

const VS = preload("res://scripts/vector_shapes.gd")

const SHAPE_LIST: Array[String] = [
	"player",
	"flipper_0", "flipper_1", "flipper_2", "flipper_3",
	"tanker_plain", "tanker_pulsar", "tanker_fuse",
	"spiker_0", "spiker_1", "spiker_2", "spiker_3",
	"fuseball_0", "fuseball_1", "fuseball_2", "fuseball_3",
	"pulsar_0", "pulsar_1", "pulsar_2", "pulsar_3",
	"eshot_0", "eshot_1", "eshot_2", "eshot_3",
	"pshot",
]

var current_idx: int = 0
var draw_scale: float = 300.0
var show_vertices: bool = true
var show_axes: bool = true
var show_numbers: bool = true
var step_mode: bool = false
var step_count: int = 999  # How many commands to show (all by default)
var show_raw: bool = false  # Show un-normalized path


func _ready() -> void:
	VS._ensure_built()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_RIGHT, KEY_D:
				current_idx = (current_idx + 1) % SHAPE_LIST.size()
				step_count = 999
				queue_redraw()
			KEY_LEFT, KEY_A:
				current_idx = (current_idx - 1 + SHAPE_LIST.size()) % SHAPE_LIST.size()
				step_count = 999
				queue_redraw()
			KEY_UP:
				draw_scale *= 1.25
				queue_redraw()
			KEY_DOWN:
				draw_scale /= 1.25
				queue_redraw()
			KEY_V:
				show_vertices = not show_vertices
				queue_redraw()
			KEY_X:
				show_axes = not show_axes
				queue_redraw()
			KEY_N:
				show_numbers = not show_numbers
				queue_redraw()
			KEY_S:
				step_mode = not step_mode
				if step_mode:
					step_count = 1
				else:
					step_count = 999
				queue_redraw()
			KEY_R:
				show_raw = not show_raw
				queue_redraw()
			KEY_SPACE:
				if step_mode:
					step_count += 1
					queue_redraw()
			KEY_BACKSPACE:
				if step_mode and step_count > 0:
					step_count -= 1
					queue_redraw()
			KEY_ESCAPE:
				get_tree().quit()


func _draw() -> void:
	var shape_name: String = SHAPE_LIST[current_idx]
	var center: Vector2 = size * 0.5

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.1))

	# Title
	draw_string(ThemeDB.fallback_font, Vector2(20, 30),
		"Shape: %s  [%d/%d]" % [shape_name, current_idx + 1, SHAPE_LIST.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(20, 55),
		"Left/Right: shapes  Up/Down: zoom  S: step mode  R: raw  N: numbers  V: vertices",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))
	if step_mode:
		draw_string(ThemeDB.fallback_font, Vector2(20, 70),
			"STEP MODE: Space=next  Backspace=prev  Step: %d" % step_count,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 1.0, 0.3))

	# Axes
	if show_axes:
		draw_line(center + Vector2(-400, 0), center + Vector2(400, 0),
			Color(0.3, 0.0, 0.0), 1.0)
		draw_line(center + Vector2(0, -400), center + Vector2(0, 400),
			Color(0.0, 0.3, 0.0), 1.0)

	if show_raw:
		_draw_raw(shape_name, center)
	else:
		_draw_processed(shape_name, center)


## Draw the processed (centered, normalized) shape from cache.
func _draw_processed(shape_name: String, center: Vector2) -> void:
	var shape: Dictionary = VS._cache.get(shape_name, {})
	if shape.is_empty():
		draw_string(ThemeDB.fallback_font, center,
			"[No shape data]", HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color.RED)
		return

	var segs: Array = shape.segs
	var cols: Array = shape.cols

	if shape_name == "pshot":
		_draw_dots(center, segs, cols)
		return

	var seg_limit: int = mini(segs.size(), step_count) if step_mode else segs.size()

	for i in seg_limit:
		var s: Array = segs[i]
		var p1: Vector2 = center + Vector2(s[0], -s[1]) * draw_scale
		var p2: Vector2 = center + Vector2(s[2], -s[3]) * draw_scale

		var color: Color
		if cols[i] < 0:
			color = Color(1.0, 0.3, 0.3)
		else:
			color = Colors.get_color(cols[i])

		# Highlight the latest segment in step mode
		var lw: float = 2.0
		if step_mode and i == seg_limit - 1:
			color = Color.WHITE
			lw = 3.0

		draw_line(p1, p2, color, lw)

		# Direction arrow at midpoint
		if show_numbers:
			var mid: Vector2 = (p1 + p2) * 0.5
			var dir: Vector2 = (p2 - p1).normalized()
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			draw_line(p2, p2 - dir * 6 + perp * 3, color * 0.7, 1.0)
			draw_line(p2, p2 - dir * 6 - perp * 3, color * 0.7, 1.0)
			draw_string(ThemeDB.fallback_font, mid + Vector2(4, -4),
				"%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.6, 0.6))

		if show_vertices:
			draw_circle(p1, 3.0, Color(1, 1, 0, 0.6))
			draw_circle(p2, 3.0, Color(1, 1, 0, 0.6))

	# Info panel
	_draw_info(segs, seg_limit)


## Draw the raw (un-normalized) path by re-tracing commands.
func _draw_raw(shape_name: String, center: Vector2) -> void:
	var cmds: Array = _get_raw_cmds(shape_name)
	if cmds.is_empty():
		draw_string(ThemeDB.fallback_font, center,
			"[No raw data for %s]" % shape_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.RED)
		return

	# Trace the commands to get vertices
	var cmd_limit: int = mini(cmds.size(), step_count) if step_mode else cmds.size()
	var cx: float = 0.0
	var cy: float = 0.0

	# Compute bounding box first (full shape) for auto-scaling
	# Values are ABSOLUTE positions (not cumulative deltas)
	var all_verts: Array[Vector2] = [Vector2.ZERO]
	for cmd in cmds:
		all_verts.append(Vector2(float(cmd[0]), float(cmd[1])))

	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for v in all_verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)

	var extent: float = maxf(max_x - min_x, max_y - min_y)
	if extent < 1.0:
		extent = 1.0
	var raw_scale: float = 400.0 / extent  # Fit in ~800px
	var raw_center_x: float = (min_x + max_x) * 0.5
	var raw_center_y: float = (min_y + max_y) * 0.5

	# Draw the traced path (values are absolute positions)
	for i in cmd_limit:
		var cmd: Array = cmds[i]
		var nx: float = float(cmd[0])
		var ny: float = float(cmd[1])
		var draw_flag: int = cmd[2]
		var color_idx: int = cmd[3] if cmd.size() > 3 else -1

		var p1: Vector2 = center + Vector2((cx - raw_center_x), -(cy - raw_center_y)) * raw_scale
		var p2: Vector2 = center + Vector2((nx - raw_center_x), -(ny - raw_center_y)) * raw_scale

		var color: Color
		if draw_flag == 0:
			color = Color(0.2, 0.2, 0.4, 0.4)  # Dim for moves
		elif color_idx >= 0:
			color = Colors.get_color(color_idx)
		else:
			color = Color(1.0, 0.3, 0.3)

		# Highlight latest in step mode
		var lw: float = 1.5 if draw_flag == 0 else 2.5
		if step_mode and i == cmd_limit - 1:
			color = Color.WHITE
			lw = 3.5

		if draw_flag == 2:
			# Dot: draw small cross
			draw_line(p2 + Vector2(-4, 0), p2 + Vector2(4, 0), color, 2.0)
			draw_line(p2 + Vector2(0, -4), p2 + Vector2(0, 4), color, 2.0)
		else:
			draw_line(p1, p2, color, lw)

		# Direction arrow
		if show_numbers:
			var dir: Vector2 = (p2 - p1)
			if dir.length() > 5:
				dir = dir.normalized()
				var perp: Vector2 = Vector2(-dir.y, dir.x)
				draw_line(p2, p2 - dir * 5 + perp * 2.5, color * 0.7, 1.0)
				draw_line(p2, p2 - dir * 5 - perp * 2.5, color * 0.7, 1.0)

		# Vertex labels
		if show_vertices:
			var label_color := Color(0.4, 0.4, 0.7) if draw_flag == 0 else Color(1.0, 1.0, 0.3)
			draw_circle(p2, 3.0, label_color)
			if show_numbers:
				var flag_str: String = "M" if draw_flag == 0 else ("D" if draw_flag == 2 else "L")
				draw_string(ThemeDB.fallback_font, p2 + Vector2(5, -3),
					"%d %s (%d,%d)" % [i, flag_str, int(nx), int(ny)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, label_color)

		cx = nx
		cy = ny

	# Info: show current command details
	var info_y: float = 80.0
	draw_string(ThemeDB.fallback_font, Vector2(20, info_y),
		"RAW MODE — Commands: %d  Showing: %d" % [cmds.size(), cmd_limit],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.3))
	info_y += 18

	if step_mode and cmd_limit > 0 and cmd_limit <= cmds.size():
		var cmd: Array = cmds[cmd_limit - 1]
		var flag_name: String = "MOVE" if cmd[2] == 0 else ("DOT" if cmd[2] == 2 else "DRAW")
		var col_name: String = ""
		if cmd.size() > 3:
			col_name = " col=%d" % cmd[3]
		draw_string(ThemeDB.fallback_font, Vector2(20, info_y),
			"Cmd %d: [%d, %d, %s%s]" % [cmd_limit - 1, cmd[0], cmd[1], flag_name, col_name],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		info_y += 18

	draw_string(ThemeDB.fallback_font, Vector2(20, info_y),
		"Bounds: X[%d, %d] Y[%d, %d]  Extent: %d" % [
			int(min_x), int(max_x), int(min_y), int(max_y), int(extent)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))


func _draw_info(segs: Array, seg_limit: int) -> void:
	var info_y: float = 80.0
	draw_string(ThemeDB.fallback_font, Vector2(20, info_y),
		"Segments: %d  Showing: %d  Scale: %.0f" % [segs.size(), seg_limit, draw_scale],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
	info_y += 18

	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for i in mini(segs.size(), seg_limit):
		var s: Array = segs[i]
		min_x = minf(min_x, minf(s[0], s[2]))
		max_x = maxf(max_x, maxf(s[0], s[2]))
		min_y = minf(min_y, minf(s[1], s[3]))
		max_y = maxf(max_y, maxf(s[1], s[3]))

	if min_x < INF:
		draw_string(ThemeDB.fallback_font, Vector2(20, info_y),
			"Bounds: X[%.3f, %.3f] Y[%.3f, %.3f]" % [min_x, max_x, min_y, max_y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))


func _draw_dots(center: Vector2, dots: Array, cols: Array) -> void:
	for i in dots.size():
		var d: Array = dots[i]
		var pos: Vector2 = center + Vector2(d[0], -d[1]) * draw_scale
		var color: Color = Colors.get_color(cols[i])
		draw_circle(pos, 4.0, color)
		if show_vertices:
			draw_string(ThemeDB.fallback_font, pos + Vector2(6, -2),
				"%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))


## Get raw command array for a shape.
func _get_raw_cmds(shape_name: String) -> Array:
	return VS.get_raw_cmds(shape_name)
