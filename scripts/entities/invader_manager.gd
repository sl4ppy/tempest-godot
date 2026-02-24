extends Node2D
## Manages all invaders (6-slot pool) and nymphs (pre-spawn particles).
## See ENTITIES.md for entity specs and SYSTEMS.md for execution order.

const VS = preload("res://scripts/vector_shapes.gd")

# Entity type constants matching original INVABI values
const ZABFLI: int = 0  # Flipper
const ZABPUL: int = 1  # Pulsar
const ZABTAN: int = 2  # Tanker
const ZABTRA: int = 3  # Trailer (Spiker)
const ZABFUS: int = 4  # Fuseball

const MAX_INVADERS: int = 6
const MAX_NYMPHS: int = 32

# Enemy colors
const TYPE_COLORS: Array[int] = [
	Colors.RED,     # Flipper
	Colors.TURQOI,  # Pulsar
	Colors.PURPLE,  # Tanker
	Colors.GREEN,   # Spiker
	Colors.GREEN,   # Fuseball
]

# Invader pool (array of dictionaries)
var invaders: Array[Dictionary] = []
var nymphs: Array[Dictionary] = []

# CAM interpreter instance
var cam: CAMInterpreter = CAMInterpreter.new()

# Wave state
var wave_params: Dictionary = {}
var spikes: Array[int] = []  # Per-lane spike Y positions (0xF0 = no spike)
var invader_count: int = 0  # Active invaders in well
var chaser_count: int = 0  # Enemies on rim chasing player
var pulson: int = 0  # Global pulsar pulse timer
var pulson_dir: int = 1  # Pulse timer direction

# Per-type speeds computed via TIMES8 at wave start. See LEVEL_DATA.md.
# Each is a float: the signed per-frame Y-delta (negative = toward player).
var type_speed: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var fuse_speed: float = 0.0  # Fuseball = 2x Flipper. Dedicated WFUSIL/WFUSIH.
var charge_speed: float = 0.0  # Enemy shot speed (WCHARIN:WCHARL)

# Enemy type quotas for current wave
var type_remaining: Array[int] = [0, 0, 0, 0, 0]
var type_spawned: Array[int] = [0, 0, 0, 0, 0]

# References
var well: Node2D
var game_state: Dictionary = {}  # Shared state for CAM interpreter


func _ready() -> void:
	for i in MAX_INVADERS:
		invaders.append(_make_invader())
	for i in MAX_NYMPHS:
		nymphs.append({"active": false, "y": 0.0, "lane": 0, "type": 0})
	spikes.resize(16)


## Compute per-type speeds via TIMES8. See LEVEL_DATA.md and ALWELG.MAC.
## TIMES8 takes an 8-bit seed and produces a 16-bit velocity: seed * 8.
## The result as a float in Y-units/frame = seed * 8 / 256.0.
func _compute_speeds(params: Dictionary) -> void:
	var base_seed: int = params.invader_speed  # Signed 8-bit, e.g. -44 for wave 1

	# Flipper/Tanker: TIMES8(base_seed)
	var flip_speed: float = float(base_seed) * 8.0 / 256.0
	type_speed[ZABFLI] = flip_speed
	type_speed[ZABTAN] = flip_speed

	# Pulsar: hardcoded $FE:$A0 = -2 + 160/256 = -1.375 for ALL waves
	type_speed[ZABPUL] = -1.375

	# Spiker: TIMES8(base_seed + TSPIIN_delta)
	var spiker_delta: int = LevelData.get_spiker_speed_delta(params.wave)
	var spiker_seed: int = base_seed + spiker_delta
	type_speed[ZABTRA] = float(spiker_seed) * 8.0 / 256.0

	# Fuseball speed slot (not used via WINVIN — uses dedicated WFUSIL/WFUSIH)
	type_speed[ZABFUS] = flip_speed  # placeholder, actual fuse uses fuse_speed
	# Fuseball = exactly 2x Flipper (16-bit left shift in original)
	fuse_speed = flip_speed * 2.0

	# Enemy shot speed: TIMES8(base_seed + (-64))
	var charge_seed: int = base_seed + (-64)
	charge_speed = float(charge_seed) * 8.0 / 256.0


## Initialize for a new wave. All nymphs are created at once (ININYM).
## See ALWELG.MAC INIENE: NYMPY = (index * 16) | random_lane.
func init_for_wave(well_renderer: Node2D, params: Dictionary) -> void:
	well = well_renderer
	wave_params = params

	for inv in invaders:
		inv.active = false
	for nym in nymphs:
		nym.active = false

	for i in 16:
		spikes[i] = 0xF0

	invader_count = 0
	chaser_count = 0
	pulson = 0
	pulson_dir = 1
	type_spawned = [0, 0, 0, 0, 0]

	_compute_speeds(params)
	_calculate_type_quotas(params)

	# ININYM — spawn all nymphs at wave start with staggered Y positions.
	# NYMPY = (index * 16) | random_lane. Converts to invader when NYMPY reaches 0.
	var num_lanes: int = 15 if LevelData.get_well_data(params.wave).planar else 16
	var nymph_count: int = mini(params.nymph_count, MAX_NYMPHS)
	for i in nymph_count:
		nymphs[i].active = true
		nymphs[i].lane = randi() % num_lanes
		nymphs[i].type = _pick_type_for_nymph()
		# Staggered Y: (index * 16) | lane. Ensures nymphs are spread through well.
		var nympy: int = (i * 16) | (nymphs[i].lane & 0x0F)
		if nympy == 0:
			nympy = 0x0F  # Original: avoid 0 at init
		nymphs[i].y = float(nympy)

	_update_game_state()
	queue_redraw()


## Called each game tick from game_manager.
func tick(player_lane: int, player_y: float, qframe: int = 0) -> void:
	game_state["player_lane"] = player_lane
	game_state["player_y"] = player_y
	game_state["player_killed"] = false
	game_state["pulson"] = pulson
	game_state["qframe"] = qframe

	var occupied: Array[int] = []
	for inv in invaders:
		if inv.active:
			occupied.append(inv.l1)
	game_state["occupied_lanes"] = occupied

	_move_nymphs()
	_run_invaders()
	_update_pulsar_timer()
	queue_redraw()


func is_player_killed() -> bool:
	return game_state.get("player_killed", false)


func is_wave_clear() -> bool:
	for nym in nymphs:
		if nym.active:
			return false
	for inv in invaders:
		if inv.active:
			return false
	return true


## Kill an invader at the given index. Returns score points.
func kill_invader(idx: int) -> int:
	if idx < 0 or idx >= MAX_INVADERS or not invaders[idx].active:
		return 0
	var inv: Dictionary = invaders[idx]
	var points: int = _get_score(inv.type, inv.is_chaser)

	if inv.type == ZABTAN:
		_split_tanker(inv)

	inv.active = false
	if inv.is_chaser:
		chaser_count -= 1
	else:
		invader_count -= 1
	return points


## Get invader data for collision checks.
## Only fuseballs are invulnerable during flips. See ENTITIES.md § Collision.
func get_active_invaders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in MAX_INVADERS:
		if not invaders[i].active:
			continue
		# Fuseballs are invulnerable while flipping
		if invaders[i].type == ZABFUS and invaders[i].is_jumping:
			continue
		result.append({"idx": i, "y": invaders[i].y, "l1": invaders[i].l1,
			"type": invaders[i].type, "is_jumping": invaders[i].is_jumping})
	return result


## Check if a given invader can fire. See ENTITIES.md § FIREIC.
func can_invader_fire(inv: Dictionary) -> bool:
	if not inv.active or inv.is_jumping:
		return false
	if inv.fire_timer > 0:
		return false
	# Spikers and fuseballs NEVER fire projectiles
	if inv.type == ZABTRA or inv.type == ZABFUS:
		return false
	# Pulsars can only fire on waves >= 60 (WPULFI flag)
	if inv.type == ZABPUL and not wave_params.pulsar_params.can_fire:
		return false
	return true


## Get the enemy shot speed for this wave.
func get_charge_speed() -> float:
	return charge_speed


# --- Internal ---

func _make_invader() -> Dictionary:
	return {
		"active": false,
		"type": 0,
		"y": 0xF0,
		"l1": 0,
		"l2": 0,
		"cam_pc": 0,
		"cam_script": PackedByteArray([]),
		"cam_status": 0,
		"loop_counter": 0,
		"jump_direction": 1,
		"fire_timer": 0,
		"can_fire": true,
		"moving_up": true,
		"is_jumping": false,
		"jump_progress": 0.0,
		"jump_src_lane": 0,
		"jump_dst_lane": 0,
		"cargo": 0,
		"is_chaser": false,
		"reached_rim": false,
		"convert_to_tanker": false,
		"anim_frame": 0,
	}


func _calculate_type_quotas(params: Dictionary) -> void:
	var total: int = params.nymph_count
	var flip_range: Vector2i = params.flipper_count
	var tank_range: Vector2i = params.tanker_count
	var spik_range: Vector2i = params.spiker_count
	var puls_range: Vector2i = params.pulsar_count
	var fuse_range: Vector2i = params.fuseball_count

	type_remaining[ZABFLI] = flip_range.x
	type_remaining[ZABPUL] = puls_range.x
	type_remaining[ZABTAN] = tank_range.x
	type_remaining[ZABTRA] = spik_range.x
	type_remaining[ZABFUS] = fuse_range.x

	var assigned: int = type_remaining[ZABFLI] + type_remaining[ZABPUL] + \
		type_remaining[ZABTAN] + type_remaining[ZABTRA] + type_remaining[ZABFUS]

	var remaining: int = total - assigned
	var attempts: int = 0
	while remaining > 0 and attempts < 200:
		attempts += 1
		var t: int = randi() % 5
		var max_count: int
		match t:
			ZABFLI: max_count = flip_range.y
			ZABPUL: max_count = puls_range.y
			ZABTAN: max_count = tank_range.y
			ZABTRA: max_count = spik_range.y
			ZABFUS: max_count = fuse_range.y
			_: max_count = 0
		if type_remaining[t] < max_count:
			type_remaining[t] += 1
			remaining -= 1

	type_remaining[ZABFLI] += remaining


func _count_active_nymphs() -> int:
	var count: int = 0
	for nym in nymphs:
		if nym.active:
			count += 1
	return count


func _update_game_state() -> void:
	var shape_data: Dictionary = LevelData.get_well_data(wave_params.wave)
	game_state = {
		# Per-type speeds for CAM interpreter
		"type_speed": type_speed,
		"fuse_speed": fuse_speed,
		"num_lanes": 15 if shape_data.planar else 16,
		"is_planar": shape_data.planar,
		"enemy_line_height": wave_params.enemy_line_height,
		"top_flip_rate": wave_params.top_flip_rate,
		"puchde": wave_params.pulsar_params.puchde,
		"pulpot": wave_params.pulsar_params.pulpot,
		"fuse_freq": LevelData.get_fuse_freq(wave_params.wave),
		"fuse_chase": LevelData.get_fuse_chase(wave_params.wave),
		"spikes": spikes,
		"player_lane": 0,
		"player_y": 0x10,
		"player_killed": false,
		"nymph_remaining": _count_active_nymphs(),
		"pulson": pulson,
		"occupied_lanes": [],
	}


## Pick a type for a nymph from remaining quotas. Called during init.
func _pick_type_for_nymph() -> int:
	var available: Array[int] = []
	for t in 5:
		if type_remaining[t] > 0:
			available.append(t)
	if available.is_empty():
		return ZABFLI  # Fallback to flipper
	var t: int = available[randi() % available.size()]
	type_remaining[t] -= 1
	return t


## MOVNYM — Move all nymphs. Decrement NYMPY by 1 per frame.
## When Y >= 0x40, nymph rotates around well every other frame.
## When NYMPY reaches 0, convert to invader. See ALWELG.MAC MOVNYM.
func _move_nymphs() -> void:
	var num_lanes: int = game_state.get("num_lanes", 16)
	for nym in nymphs:
		if not nym.active:
			continue

		# Rotation in far zone: when Y >= 0x40, rotate lane every other frame
		var qf: int = game_state.get("qframe", 0)
		if int(nym.y) >= 0x40 and qf % 2 == 0:
			nym.lane = (nym.lane + 1) % num_lanes

		nym.y -= 1.0  # Decrement by 1 per game tick (20 Hz)
		if nym.y <= 0.0:
			_activate_invader(nym)
			nym.active = false


func _activate_invader(nym: Dictionary) -> void:
	for inv in invaders:
		if not inv.active:
			inv.active = true
			inv.type = nym.type
			inv.y = 0xF0  # ILINDDY — start at far end
			inv.l1 = nym.lane
			inv.l2 = (nym.lane + 1) % 16
			inv.is_jumping = false
			inv.jump_progress = 0.0
			inv.jump_direction = [-1, 1][randi() % 2]
			inv.moving_up = true
			inv.is_chaser = false
			inv.reached_rim = false
			inv.convert_to_tanker = false
			inv.fire_timer = wave_params.fire_delay
			inv.can_fire = true
			inv.cam_status = 0
			inv.loop_counter = 0
			inv.cargo = wave_params.tanker_cargo if nym.type == ZABTAN else 0

			var cam_name: String
			if nym.type == ZABFLI:
				cam_name = wave_params.flipper_cam
			else:
				cam_name = CAMInterpreter.DEFAULT_CAM[nym.type]

			inv.cam_script = CAMInterpreter.SCRIPTS.get(cam_name, CAMInterpreter.NOJUMP)
			inv.cam_pc = 1 if cam_name == "COWJMP" else 0

			invader_count += 1
			return


func _run_invaders() -> void:
	for inv in invaders:
		if not inv.active:
			continue

		cam.execute_frame(inv, game_state)

		# Handle post-CAM state changes
		if inv.reached_rim and not inv.is_chaser:
			if inv.type == ZABPUL:
				# Pulsars do NOT become chasers — they reverse direction
				# See ENTITIES.md: "unlike a Flipper, it does not become a permanent Chaser"
				inv.moving_up = false
				inv.reached_rim = false
			else:
				# Flippers/Tankers become chasers (TOPPER script)
				inv.is_chaser = true
				inv.cam_script = CAMInterpreter.TOPPER
				inv.cam_pc = 0
				inv.y = 0x10
				invader_count -= 1
				chaser_count += 1
				inv.reached_rim = false

		if inv.convert_to_tanker:
			inv.type = ZABTAN
			inv.cam_script = CAMInterpreter.NOJUMP
			inv.cam_pc = 0
			inv.moving_up = true
			inv.convert_to_tanker = false
			inv.cargo = wave_params.tanker_cargo

		if inv.fire_timer > 0:
			inv.fire_timer -= 1

		inv.anim_frame = (inv.anim_frame + 1) % 4


func _update_pulsar_timer() -> void:
	var pultim: int = wave_params.pulsar_params.pultim
	pulson += pulson_dir * pultim
	if pulson > 64:
		pulson_dir = -1
	elif pulson <= 0:
		pulson = 0
		pulson_dir = 1


func _split_tanker(tanker: Dictionary) -> void:
	var cargo: int = tanker.cargo
	var child_type: int
	match cargo:
		2: child_type = ZABPUL
		3: child_type = ZABFUS
		_: child_type = ZABFLI

	var spawned: int = 0
	for inv in invaders:
		if not inv.active and spawned < 2:
			inv.active = true
			inv.type = child_type
			inv.y = tanker.y
			inv.l1 = tanker.l1
			inv.l2 = (tanker.l1 + 1) % 16
			inv.moving_up = true
			inv.is_jumping = false
			inv.jump_progress = 0.0
			inv.is_chaser = false
			inv.reached_rim = false
			inv.convert_to_tanker = false
			inv.cam_status = 0
			inv.loop_counter = 0
			inv.fire_timer = wave_params.fire_delay
			inv.jump_direction = 1 if spawned == 0 else -1

			var cam_name: String
			if child_type == ZABFLI:
				cam_name = wave_params.flipper_cam
			else:
				cam_name = CAMInterpreter.DEFAULT_CAM[child_type]
			inv.cam_script = CAMInterpreter.SCRIPTS.get(cam_name, CAMInterpreter.NOJUMP)
			inv.cam_pc = 1 if cam_name == "COWJMP" else 0

			invader_count += 1
			spawned += 1


func _get_score(etype: int, is_chaser: bool) -> int:
	# See original score tables. Flipper on rim = 200, in well = 150.
	match etype:
		ZABFLI: return 200 if is_chaser else 150
		ZABTAN: return 100
		ZABTRA: return 50
		ZABFUS: return 750
		ZABPUL: return 200
		_: return 100


# --- Rendering ---

func _draw() -> void:
	if well == null:
		return
	_draw_invaders()


func _draw_nymphs() -> void:
	var color: Color = Colors.get_color(Colors.NYMCOL)
	for nym in nymphs:
		if not nym.active:
			continue
		# Map NYMPY to depth fraction. Higher Y = further from player.
		# NYMPY ranges from ~0 to ~0xFF. Map to well depth (0=near, 1=far).
		var depth_frac: float = well.depth_to_frac(nym.y)
		var edges: Array[Vector2] = well.get_lane_edges(nym.lane, depth_frac)
		var center: Vector2 = (edges[0] + edges[1]) * 0.5
		var s: float = edges[0].distance_to(edges[1]) * 0.15
		s = maxf(s, 1.5)
		draw_line(center + Vector2(0, -s), center + Vector2(s, 0), color, 1.5)
		draw_line(center + Vector2(s, 0), center + Vector2(0, s), color, 1.5)
		draw_line(center + Vector2(0, s), center + Vector2(-s, 0), color, 1.5)
		draw_line(center + Vector2(-s, 0), center + Vector2(0, -s), color, 1.5)


func _draw_invaders() -> void:
	for inv in invaders:
		if not inv.active:
			continue

		var depth_frac: float = well.depth_to_frac(inv.y)

		var left: Vector2
		var right: Vector2
		var center: Vector2

		if inv.is_jumping:
			# Flipper rotates around the shared spoke (pivot) between src and dst lanes.
			# See ENTITIES.md § Flipper lane-change.
			var src: int = inv.jump_src_lane
			var dst: int = inv.jump_dst_lane
			var t: float = inv.jump_progress
			var num_lanes: int = well.near_screen.size()

			var pivot_spoke: int
			var src_free_spoke: int
			var dst_free_spoke: int

			if inv.jump_direction > 0:  # Flipping right: pivot is right edge of src
				pivot_spoke = (src + 1) % num_lanes
				src_free_spoke = src
				dst_free_spoke = (dst + 1) % num_lanes
			else:  # Flipping left: pivot is left edge of src
				pivot_spoke = src
				src_free_spoke = (src + 1) % num_lanes
				dst_free_spoke = dst

			var pivot: Vector2 = well.get_spoke_position(pivot_spoke, depth_frac)
			var src_free: Vector2 = well.get_spoke_position(src_free_spoke, depth_frac)
			var dst_free: Vector2 = well.get_spoke_position(dst_free_spoke, depth_frac)

			# Angular interpolation of free end around pivot
			var src_off: Vector2 = src_free - pivot
			var dst_off: Vector2 = dst_free - pivot
			var cur_angle: float = lerp_angle(src_off.angle(), dst_off.angle(), t)
			var cur_dist: float = lerpf(src_off.length(), dst_off.length(), t)
			var free: Vector2 = pivot + Vector2.from_angle(cur_angle) * cur_dist

			left = free if inv.jump_direction > 0 else pivot
			right = pivot if inv.jump_direction > 0 else free
			center = (pivot + free) * 0.5
		else:
			var edges: Array[Vector2] = well.get_lane_edges(inv.l1, depth_frac)
			left = edges[0]
			right = edges[1]
			center = (left + right) * 0.5

		var color_idx: int = TYPE_COLORS[inv.type]
		if inv.type == ZABPUL and pulson > 0:
			color_idx = Colors.WHITE
		var color: Color = Colors.get_color(color_idx)

		var tangent: Vector2 = (right - left).normalized()
		var lane_width: float = left.distance_to(right)
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		if normal.dot(well.screen_center - center) < 0:
			normal = -normal

		# Flipper + Pulsar use ONELIN (drawn between lane edges).
		# Tanker/Spiker/Fuseball use SCAPIC (centered at lane midpoint).
		match inv.type:
			ZABFLI:
				# Single non-animating shape. See ALDISP.MAC: FLITAB all CINVA1.
				VS.draw_onelin(self, VS.FLIPPER, left, right,
					well.screen_center, color, 2.0)
			ZABPUL:
				# Pulsar frame from PULSON timer: 0-64 → frame 0-4
				@warning_ignore("integer_division")
				var pulse_frame: int = clampi(pulson / 13, 0, 4)
				VS.draw_onelin(self, VS.PULSAR[pulse_frame], left, right,
					well.screen_center, color, 2.0)
			ZABTAN:
				var shape_name: String
				match inv.cargo:
					2: shape_name = "tanker_pulsar"
					3: shape_name = "tanker_fuse"
					_: shape_name = "tanker_plain"
				VS.draw_shape(self, shape_name, center, tangent, normal,
					lane_width, color, 2.0)
			ZABTRA:
				var shape_name: String = "spiker_%d" % inv.anim_frame
				VS.draw_shape(self, shape_name, center, tangent, normal,
					lane_width, color, 2.0)
			ZABFUS:
				var shape_name: String = "fuseball_%d" % inv.anim_frame
				VS.draw_shape(self, shape_name, center, tangent, normal,
					lane_width, color, 2.0)
			_:
				continue
