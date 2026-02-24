class_name VectorShapes
## Original vector shape data from ALVROM.MAC and ALDISP.MAC.
## SCAPIC shapes: centered/normalized for lane-relative drawing.
## ONELIN shapes: drawn between lane edge endpoints using VEC multipliers.

# Color indices matching Colors autoload palette
const C_WHITE: int = 0
const C_YELLOW: int = 1
const C_PURPLE: int = 2
const C_RED: int = 3
const C_TURQOI: int = 4
const C_GREEN: int = 5
const C_BLUE: int = 6
const C_PSHCTR: int = 8

# ========================================================================
# ONELIN SHAPES — drawn between two lane edge endpoints (ALDISP.MAC)
# VEC format: [delta_unit, delta_perp, draw_flag]
# Unit axis: 8 units = full lane width (left edge → right edge)
# Perp axis: positive = away from well center
# ========================================================================

# Flipper: CINVA1 (INVA1S) — single non-animating shape.
# FLITAB: .BYTE CINVA1,CINVA1,CINVA1,CINVA1 — all 4 slots identical.
static var FLIPPER: Array = [
	[4, 1, true], [4, -1, true],
	[-2, 1, true], [1, 1, true],
	[-3, -1, true], [-3, 1, true],
	[1, -1, true], [-2, -1, true],
]

# Pulsar: PULS0S-PULS4S — 5 animation frames driven by PULSON timer.
# PULTAB: CPULS0, CPULS1, CPULS2, CPULS3, CPULS4, CPULS4
static var PULSAR: Array = [
	# PULS0 (flat line, resting)
	[[1, 0, false], [6, 0, true]],
	# PULS1 (gentle V)
	[[1, 0, false], [2, -1, true], [2, 2, true], [2, -1, true]],
	# PULS2 (small zigzag)
	[[1, 0, false], [1, -1, true], [1, 2, true], [1, -2, true], [1, 2, true], [1, -2, true], [1, 1, true]],
	# PULS3 (medium zigzag)
	[[1, 0, false], [1, -2, true], [1, 4, true], [1, -4, true], [1, 4, true], [1, -4, true], [1, 2, true]],
	# PULS4 (full sawtooth)
	[[2, -3, true], [1, 6, true], [1, -6, true], [1, 6, true], [1, -6, true], [2, 3, true]],
]


## Draw a shape using the ONELIN rendering system (ALDISP.MAC §ONELIN/ONELN2).
## Shape is drawn as a polyline starting from the left lane edge.
## Unit direction: left→right lane edge (8 units = full lane width).
## Perp direction: 90° to unit, positive = away from well center.
static func draw_onelin(ci: CanvasItem, vecs: Array, left: Vector2, right: Vector2,
		well_center: Vector2, color: Color, line_width: float = 2.0) -> void:
	var lane_vec: Vector2 = right - left
	var unit: Vector2 = lane_vec / 8.0
	# Perpendicular: 90° rotation, oriented away from well center
	var perp: Vector2 = Vector2(-unit.y, unit.x)
	var center: Vector2 = (left + right) * 0.5
	if perp.dot(well_center - center) > 0:
		perp = -perp  # Flip to point AWAY from well center

	var pos: Vector2 = left
	for vec in vecs:
		var new_pos: Vector2 = pos + unit * float(vec[0]) + perp * float(vec[1])
		if vec[2]:
			ci.draw_line(pos, new_pos, color, line_width)
		pos = new_pos


# Cached processed shapes: name -> {"segs": Array, "cols": Array}
static var _cache: Dictionary = {}


## Draw a vector shape on a CanvasItem.
## Shape local X → tangent (along lane edge), local Y → -normal (away from well center).
## Normal is negated because VG Y-up = screen up, but our normal points toward center.
## sz = size multiplier (typically lane_width for depth-dependent scaling).
static func draw_shape(ci: CanvasItem, shape_name: String, center: Vector2,
		tangent: Vector2, normal: Vector2, sz: float,
		default_color: Color, line_width: float = 2.0) -> void:
	_ensure_built()
	var shape: Dictionary = _cache.get(shape_name, {})
	if shape.is_empty():
		return
	var segs: Array = shape.segs
	var cols: Array = shape.cols
	for i in segs.size():
		var s: Array = segs[i]
		var p1: Vector2 = center + (tangent * s[0] - normal * s[1]) * sz
		var p2: Vector2 = center + (tangent * s[2] - normal * s[3]) * sz
		var c: Color
		if cols[i] < 0:
			c = default_color
		else:
			c = Colors.get_color(cols[i])
		ci.draw_line(p1, p2, c, line_width)


## Draw dot-based shapes (player shot).
static func draw_dots(ci: CanvasItem, shape_name: String, center: Vector2,
		tangent: Vector2, normal: Vector2, sz: float,
		default_color: Color, dot_size: float = 2.0) -> void:
	_ensure_built()
	var shape: Dictionary = _cache.get(shape_name, {})
	if shape.is_empty():
		return
	var dots: Array = shape.segs
	var cols: Array = shape.cols
	for i in dots.size():
		var d: Array = dots[i]
		var pos: Vector2 = center + (tangent * d[0] - normal * d[1]) * sz
		var c: Color
		if cols[i] < 0:
			c = default_color
		else:
			c = Colors.get_color(cols[i])
		ci.draw_line(pos + Vector2(-dot_size, 0), pos + Vector2(dot_size, 0), c, 1.5)
		ci.draw_line(pos + Vector2(0, -dot_size), pos + Vector2(0, dot_size), c, 1.5)


static func _ensure_built() -> void:
	if not _cache.is_empty():
		return
	_build_all()


# ========================================================================
# RAW SHAPE COMMAND DATA
# Format: [dx, dy, draw_flag] or [dx, dy, draw_flag, color_index]
# draw_flag: 0 = move, 1 = draw
# color_index omitted or -1 = use default_color
# ========================================================================

# --- Player Ship (LIFE1) ---
# CM=6, CD=1. Raw SCVEC deltas (unnormalized — CM doesn't matter due to normalization).
static var _PLAYER: Array = [
	[4, -2, 1],
	[1, -3, 1],
	[3, -2, 1],
	[0, -1, 1],
	[-3, -2, 1],
	[-1, -3, 1],
	[-4, -2, 1],
	[0, 0, 1],  # SCVEC 0,0,CB — close shape back to origin
]

# (Flipper shapes moved to ONELIN system — see FLIPPER array above)

# --- Tanker Plain (TANKR + GENTNK, all purple) ---
# Hex values converted to decimal: 0x20=32, 0x0C=12
static var _TANK_PLAIN: Array = [
	[32, 0, 0],  # move to body start
	[0, 32, 1], [0, 12, 1], [32, 0, 1], [12, 0, 1],
	[0, 12, 1], [-12, 0, 1], [0, 32, 1], [-32, 0, 1],
	[-12, 0, 1], [0, -12, 1], [-32, 0, 1], [0, -32, 1],
	[0, -12, 1], [12, 0, 1], [0, -32, 1], [32, 0, 1],
	[12, 0, 1],
]

# --- Tanker Pulsar (TANKP core + GENTNK) ---
static var _TANK_PULSAR: Array = [
	[-5, -2, 0],  # move to core start
	[-3, 6, 1, C_TURQOI], [0, -6, 1, C_TURQOI],
	[3, 6, 1, C_TURQOI], [5, -2, 1, C_TURQOI],
	[32, 0, 0],  # move to body start
	[0, 32, 1, C_PURPLE], [0, 12, 1, C_PURPLE], [32, 0, 1, C_PURPLE],
	[12, 0, 1, C_PURPLE], [0, 12, 1, C_PURPLE], [-12, 0, 1, C_PURPLE],
	[0, 32, 1, C_PURPLE], [-32, 0, 1, C_PURPLE], [-12, 0, 1, C_PURPLE],
	[0, -12, 1, C_PURPLE], [-32, 0, 1, C_PURPLE], [0, -32, 1, C_PURPLE],
	[0, -12, 1, C_PURPLE], [12, 0, 1, C_PURPLE], [0, -32, 1, C_PURPLE],
	[32, 0, 1, C_PURPLE], [12, 0, 1, C_PURPLE],
]

# --- Tanker Fuseball (TANKF core + GENTNK) ---
static var _TANK_FUSE: Array = [
	[-12, 0, 1, C_BLUE],  # left arm
	[0, 12, 0],  # move up
	[0, -12, 1, C_GREEN],  # down arm
	[12, 0, 1, C_YELLOW],  # right arm
	[32, 0, 0],  # move to body start
	[0, 32, 1, C_PURPLE], [0, 12, 1, C_PURPLE], [32, 0, 1, C_PURPLE],
	[12, 0, 1, C_PURPLE], [0, 12, 1, C_PURPLE], [-12, 0, 1, C_PURPLE],
	[0, 32, 1, C_PURPLE], [-32, 0, 1, C_PURPLE], [-12, 0, 1, C_PURPLE],
	[0, -12, 1, C_PURPLE], [-32, 0, 1, C_PURPLE], [0, -32, 1, C_PURPLE],
	[0, -12, 1, C_PURPLE], [12, 0, 1, C_PURPLE], [0, -32, 1, C_PURPLE],
	[32, 0, 1, C_PURPLE], [12, 0, 1, C_PURPLE],
]

# --- Spiker Frames (SPIRA1-4) ---
# Hex values converted: 0A=10, 0B=11, 0C=12, 0E=14, 0F=15, 10=16, 12=18, 14=20
static var _SPIK0: Array = [
	[1, -1, 1], [0, -2, 1], [-2, -2, 1], [-4, 0, 1],
	[-4, 4, 1], [0, 6, 1], [5, 5, 1], [8, 0, 1],
	[7, -7, 1], [0, -10, 1], [-8, -8, 1], [-12, 0, 1],
	[-9, 9, 1], [0, 14, 1], [11, 11, 1], [16, 0, 1],
	[12, -12, 1], [0, -18, 1], [-14, -14, 1], [-20, 0, 1],
	[-15, 15, 1],
]

static var _SPIK1: Array = [
	[1, 1, 1], [2, 0, 1], [2, -2, 1], [0, -4, 1],
	[-4, -4, 1], [-6, 0, 1], [-5, 5, 1], [0, 8, 1],
	[7, 7, 1], [10, 0, 1], [8, -8, 1], [0, -12, 1],
	[-9, -9, 1], [-14, 0, 1], [-11, 11, 1], [0, 16, 1],
	[12, 12, 1], [18, 0, 1], [14, -14, 1], [0, -20, 1],
	[-15, -15, 1],
]

static var _SPIK2: Array = [
	[-1, 1, 1], [0, 2, 1], [2, 2, 1], [4, 0, 1],
	[4, -4, 1], [0, -6, 1], [-5, -5, 1], [-8, 0, 1],
	[-7, 7, 1], [0, 10, 1], [8, 8, 1], [12, 0, 1],
	[9, -9, 1], [0, -14, 1], [-11, -11, 1], [-16, 0, 1],
	[-12, 12, 1], [0, 18, 1], [14, 14, 1], [20, 0, 1],
	[15, -15, 1],
]

static var _SPIK3: Array = [
	[-1, -1, 1], [-2, 0, 1], [-2, 2, 1], [0, 4, 1],
	[4, 4, 1], [6, 0, 1], [5, -5, 1], [0, -8, 1],
	[-7, -7, 1], [-10, 0, 1], [-8, 8, 1], [0, 12, 1],
	[9, 9, 1], [14, 0, 1], [11, -11, 1], [0, -16, 1],
	[-12, -12, 1], [-18, 0, 1], [-14, 14, 1], [0, 20, 1],
	[15, 15, 1],
]

# --- Fuseball Frames (FUSE0-3) ---
# Multi-color: RED → YELLOW → GREEN → PURPLE → TURQUOISE
# Hex converted: 0A=10, 0B=11, 0C=12, 0D=13, 0E=14, 0F=15, 10=16,
#   11=17, 12=18, 13=19, 14=20, 15=21, 16=22, 17=23, 18=24, 1A=26, 1C=28

static var _FUSE0: Array = [
	# RED
	[-4, 6, 1, C_RED], [1, 12, 1, C_RED], [-5, 14, 1, C_RED],
	[1, 18, 1, C_RED], [-1, 24, 1, C_RED],
	# YELLOW
	[8, 23, 0],  # move
	[10, 20, 1, C_YELLOW], [12, 16, 1, C_YELLOW], [6, 12, 1, C_YELLOW],
	[8, 8, 1, C_YELLOW],
	# GREEN
	[10, 2, 1, C_GREEN], [8, -6, 1, C_GREEN], [14, -6, 1, C_GREEN],
	[8, -12, 1, C_GREEN], [12, -19, 1, C_GREEN], [16, -19, 1, C_GREEN],
	# PURPLE
	[-4, -26, 0],  # move
	[-4, -20, 1, C_PURPLE], [-10, -20, 1, C_PURPLE], [-7, -13, 1, C_PURPLE],
	[-9, -6, 1, C_PURPLE], [-3, -8, 1, C_PURPLE],
	# TURQUOISE
	[-8, -2, 1, C_TURQOI], [-10, 3, 1, C_TURQOI], [-14, -1, 1, C_TURQOI],
	[-16, 4, 1, C_TURQOI], [-28, -4, 1, C_TURQOI],
]

static var _FUSE1: Array = [
	# RED
	[-1, 8, 1, C_RED], [-5, 8, 1, C_RED], [-5, 10, 1, C_RED],
	[-10, 9, 1, C_RED], [-7, 16, 1, C_RED], [-12, 16, 1, C_RED],
	[-14, 12, 1, C_RED],
	# YELLOW
	[20, 16, 0],
	[14, 18, 1, C_YELLOW], [9, 13, 1, C_YELLOW], [10, 7, 1, C_YELLOW],
	[6, 8, 1, C_YELLOW],
	# GREEN
	[1, -1, 1, C_GREEN], [9, 0, 1, C_GREEN], [11, -5, 1, C_GREEN],
	[16, -6, 1, C_GREEN], [14, -10, 1, C_GREEN], [20, -11, 1, C_GREEN],
	# PURPLE
	[-8, -22, 0],
	[-8, -18, 1, C_PURPLE], [-4, -12, 1, C_PURPLE], [-8, -12, 1, C_PURPLE],
	[-6, -6, 1, C_PURPLE],
	# TURQUOISE
	[-8, 0, 1, C_TURQOI], [-12, -4, 1, C_TURQOI], [-16, -2, 1, C_TURQOI],
	[-24, -6, 1, C_TURQOI],
]

static var _FUSE2: Array = [
	# RED
	[0, 7, 1, C_RED], [3, 9, 1, C_RED], [1, 13, 1, C_RED],
	[6, 16, 1, C_RED], [4, 20, 1, C_RED], [8, 28, 1, C_RED],
	# YELLOW
	[24, 14, 0],
	[18, 14, 1, C_YELLOW], [16, 6, 1, C_YELLOW], [10, 2, 1, C_YELLOW],
	[8, 6, 1, C_YELLOW],
	# GREEN
	[4, -4, 1, C_GREEN], [8, -4, 1, C_GREEN], [9, -8, 1, C_GREEN],
	[16, -9, 1, C_GREEN], [17, -16, 1, C_GREEN], [24, -16, 1, C_GREEN],
	# PURPLE
	[-12, -24, 0],
	[-8, -20, 1, C_PURPLE], [-12, -12, 1, C_PURPLE], [-5, -10, 1, C_PURPLE],
	# TURQUOISE
	[-4, 2, 1, C_TURQOI], [-8, 0, 1, C_TURQOI], [-10, 2, 1, C_TURQOI],
	[-18, 0, 1, C_TURQOI], [-22, -6, 1, C_TURQOI],
]

static var _FUSE3: Array = [
	# RED
	[-4, 4, 1, C_RED], [-3, 10, 1, C_RED], [-6, 14, 1, C_RED],
	[-12, 14, 1, C_RED], [-12, 18, 1, C_RED],
	# YELLOW
	[16, 16, 0],
	[10, 14, 1, C_YELLOW], [13, 11, 1, C_YELLOW], [8, 8, 1, C_YELLOW],
	[10, 4, 1, C_YELLOW],
	# GREEN
	[8, -3, 1, C_GREEN], [9, -7, 1, C_GREEN], [14, -4, 1, C_GREEN],
	[18, -4, 1, C_GREEN], [20, -14, 1, C_GREEN],
	# PURPLE
	[0, -24, 0],
	[-4, -20, 1, C_PURPLE], [0, -16, 1, C_PURPLE], [-4, -12, 1, C_PURPLE],
	[2, -8, 1, C_PURPLE],
	# TURQUOISE
	[-9, -4, 1, C_TURQOI], [-10, -1, 1, C_TURQOI], [-14, -1, 1, C_TURQOI],
	[-15, -7, 1, C_TURQOI], [-21, -9, 1, C_TURQOI],
]

# (Pulsar shapes moved to ONELIN system — see PULSAR array above)

# --- Enemy Shot Frames (ESHOT1-4) ---
# 4 white line segments + 4 red dots per frame
# draw_flag: 0=move, 1=draw line, 2=dot (small cross)
static var _ESHOT0: Array = [
	[-11, 11, 0], [-17, 17, 1, C_WHITE],
	[-17, -11, 0], [-11, -17, 1, C_WHITE],
	[17, -17, 0], [11, -11, 1, C_WHITE],
	[11, 17, 0], [17, 11, 1, C_WHITE],
	# RED dots
	[6, 6, 2, C_RED], [-6, 6, 2, C_RED],
	[-6, -6, 2, C_RED], [6, -6, 2, C_RED],
]

static var _ESHOT1: Array = [
	[-18, 12, 0], [-18, 4, 1, C_WHITE],
	[-8, -14, 0], [-8, -22, 1, C_WHITE],
	[18, -12, 0], [18, -4, 1, C_WHITE],
	[8, 14, 0], [8, 22, 1, C_WHITE],
	# RED dots
	[-3, 7, 2, C_RED], [-7, 3, 2, C_RED],
	[3, -7, 2, C_RED], [7, 3, 2, C_RED],
]

static var _ESHOT2: Array = [
	[-17, 3, 0], [-23, -3, 1, C_WHITE],
	[-3, -23, 0], [3, -17, 1, C_WHITE],
	[17, -3, 0], [23, 3, 1, C_WHITE],
	[3, 23, 0], [-3, 17, 1, C_WHITE],
	# RED dots
	[0, 8, 2, C_RED], [-8, 0, 2, C_RED],
	[0, -8, 2, C_RED], [8, 0, 2, C_RED],
]

static var _ESHOT3: Array = [
	[-22, -8, 0], [-14, -8, 1, C_WHITE],
	[4, -18, 0], [12, -18, 1, C_WHITE],
	[14, 8, 0], [22, 8, 1, C_WHITE],
	[-4, 18, 0], [-12, 18, 1, C_WHITE],
	# RED dots
	[-7, 3, 2, C_RED], [-3, -7, 2, C_RED],
	[7, 3, 2, C_RED], [3, 7, 2, C_RED],
]

# --- Player Shot dots (DIARA2) ---
# Cumulative SCDOT positions traced to absolute coords
# Inner ring (PSHCTR) + Outer ring (YELLOW)
# Stored as absolute positions after tracing: [[x, y, color], ...]
static var _PSHOT_DOTS: Array = [
	# Inner ring (PSHCTR=8)
	[0.0, 0.0, C_PSHCTR],
	[7.0, 0.0, C_PSHCTR],
	[12.0, 5.0, C_PSHCTR],
	[12.0, 12.0, C_PSHCTR],
	[7.0, 17.0, C_PSHCTR],
	[0.0, 17.0, C_PSHCTR],
	[-5.0, 12.0, C_PSHCTR],
	[-5.0, 5.0, C_PSHCTR],
	[0.0, 0.0, C_PSHCTR],
	# Outer ring (YELLOW=1)
	[15.0, 0.0, C_YELLOW],
	[26.0, 11.0, C_YELLOW],
	[26.0, 26.0, C_YELLOW],
	[15.0, 37.0, C_YELLOW],
	[4.0, 37.0, C_YELLOW],
	[-7.0, 26.0, C_YELLOW],
	[-7.0, 15.0, C_YELLOW],
	[4.0, 4.0, C_YELLOW],
]


# ========================================================================
# RAW DATA LOOKUP (for shape inspector)
# ========================================================================

static var _RAW_MAP: Dictionary = {}


static func get_raw_cmds(shape_name: String) -> Array:
	if _RAW_MAP.is_empty():
		_RAW_MAP = {
			"player": _PLAYER,
			# Flipper + Pulsar use ONELIN (not in _RAW_MAP)
			"tanker_plain": _TANK_PLAIN, "tanker_pulsar": _TANK_PULSAR,
			"tanker_fuse": _TANK_FUSE,
			"spiker_0": _SPIK0, "spiker_1": _SPIK1,
			"spiker_2": _SPIK2, "spiker_3": _SPIK3,
			"fuseball_0": _FUSE0, "fuseball_1": _FUSE1,
			"fuseball_2": _FUSE2, "fuseball_3": _FUSE3,
			"eshot_0": _ESHOT0, "eshot_1": _ESHOT1,
			"eshot_2": _ESHOT2, "eshot_3": _ESHOT3,
		}
	return _RAW_MAP.get(shape_name, [])


# ========================================================================
# BUILD / PROCESS
# ========================================================================

static func _build_all() -> void:
	# Player (LIFE1 already traces a complete U-shape, no mirroring needed)
	_build("player", _PLAYER)

	# Flipper + Pulsar use ONELIN system (draw_onelin), not SCAPIC — no build needed.

	# Tanker variants
	_build("tanker_plain", _TANK_PLAIN)
	_build("tanker_pulsar", _TANK_PULSAR)
	_build("tanker_fuse", _TANK_FUSE)

	# Spiker 4 frames
	_build("spiker_0", _SPIK0)
	_build("spiker_1", _SPIK1)
	_build("spiker_2", _SPIK2)
	_build("spiker_3", _SPIK3)

	# Fuseball 4 frames
	_build("fuseball_0", _FUSE0)
	_build("fuseball_1", _FUSE1)
	_build("fuseball_2", _FUSE2)
	_build("fuseball_3", _FUSE3)

	# Enemy shots 4 frames
	_build("eshot_0", _ESHOT0)
	_build("eshot_1", _ESHOT1)
	_build("eshot_2", _ESHOT2)
	_build("eshot_3", _ESHOT3)

	# Player shot (dots)
	_build_dots("pshot", _PSHOT_DOTS)


## Process command array into centered, normalized line segments.
## Values are ABSOLUTE positions (matching SCVEC/CALVEC operands), not deltas.
static func _build(shape_name: String, cmds: Array) -> void:
	var cx: float = 0.0
	var cy: float = 0.0
	var segs: Array = []
	var cols: Array = []

	for cmd in cmds:
		var nx: float = float(cmd[0])
		var ny: float = float(cmd[1])
		var draw: int = cmd[2]
		var color_idx: int = cmd[3] if cmd.size() > 3 else -1

		if draw == 1:
			if absf(nx - cx) < 0.01 and absf(ny - cy) < 0.01:
				pass  # Zero-length: skip
			else:
				segs.append([cx, cy, nx, ny])
				cols.append(color_idx)
		elif draw == 2:
			# Dot: generate small cross at the absolute position
			var r: float = 1.5
			segs.append([nx - r, ny, nx + r, ny])
			cols.append(color_idx)
			segs.append([nx, ny - r, nx, ny + r])
			cols.append(color_idx)

		cx = nx
		cy = ny

	_center_and_normalize(shape_name, segs, cols)


## Build dot-based shape (player shot). Stores normalized dot positions.
static func _build_dots(shape_name: String, dot_data: Array) -> void:
	var dots: Array = []
	var cols: Array = []

	for d in dot_data:
		dots.append([d[0], d[1]])
		cols.append(int(d[2]))

	# Center and normalize
	if dots.is_empty():
		_cache[shape_name] = {"segs": [], "cols": []}
		return

	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for d in dots:
		min_x = minf(min_x, d[0])
		max_x = maxf(max_x, d[0])
		min_y = minf(min_y, d[1])
		max_y = maxf(max_y, d[1])

	var cx: float = (min_x + max_x) * 0.5
	var cy: float = (min_y + max_y) * 0.5
	var extent: float = maxf(max_x - min_x, max_y - min_y)
	if extent < 0.01:
		extent = 1.0

	for d in dots:
		d[0] = (d[0] - cx) / extent
		d[1] = (d[1] - cy) / extent

	_cache[shape_name] = {"segs": dots, "cols": cols}


## Center segments on (0,0) and normalize to max extent = 1.0.
static func _center_and_normalize(shape_name: String, segs: Array, cols: Array) -> void:
	if segs.is_empty():
		_cache[shape_name] = {"segs": [], "cols": []}
		return

	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for s in segs:
		min_x = minf(min_x, minf(s[0], s[2]))
		max_x = maxf(max_x, maxf(s[0], s[2]))
		min_y = minf(min_y, minf(s[1], s[3]))
		max_y = maxf(max_y, maxf(s[1], s[3]))

	var cx: float = (min_x + max_x) * 0.5
	var cy: float = (min_y + max_y) * 0.5
	var extent: float = maxf(max_x - min_x, max_y - min_y)
	if extent < 0.01:
		extent = 1.0

	for s in segs:
		s[0] = (s[0] - cx) / extent
		s[1] = (s[1] - cy) / extent
		s[2] = (s[2] - cx) / extent
		s[3] = (s[3] - cy) / extent

	_cache[shape_name] = {"segs": segs, "cols": cols}
