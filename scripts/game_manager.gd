extends Control
## Master game state machine. See GAME_STATE_FLOW.md for all 19 states.

# Game states matching original ALEXEC.MAC state constants
enum State {
	CNEWGA,   # New Game
	CNEWLI,   # New Life
	CPLAY,    # Active Gameplay
	CENDLI,   # Life Lost
	CENDGA,   # Game Over
	CPAUSE,   # Generic Pause
	CNEWAV,   # New Wave Init
	CENDWAV,  # End Wave
	CHISCHK,  # High Score Check
	CGETINI,  # Get Initials
	CDLADR,   # Display Ladder
	CREQRAT,  # Request Rating
	CNEWV2,   # Wave Transition (warp)
	CLOGO,    # Logo
	CINIRAT,  # Init Rating
	CNWLF2,   # New Life Part 2
	CDROP,    # Inter-Level Drop
	CSYSTM,   # System Test
	CBOOM,    # Superzapper
}

const SECOND: int = 20  # Game logic frames per second
const TICK_RATE: float = 1.0 / SECOND
const INITIAL_LIVES: int = 3

var state: State = State.CLOGO
var attract_mode: bool = true
var current_wave: int = 1
var score: int = 0
var lives: int = INITIAL_LIVES
var _tick_accumulator: float = 0.0
var qframe: int = 0  # Global frame counter (wraps at 256)

# Collision constants
var ensize: Array[float] = [0, 0, 0, 0, 0]  # Per-type collision range
var chacha: float = 0.0  # Shot-vs-shot collision distance

# CPAUSE — generic timed pause utility. See GAME_STATE_FLOW.md § CPAUSE.
var pause_timer: int = 0
var pause_next_state: State = State.CPLAY

# Death animation. See ENTITIES.md § Player Death (SPLAT).
const DEATH_FRAMES: int = 15  # Total frames of death explosion
var death_timer: int = 0
var death_lane: int = 0  # Lane where player died
var death_frac: float = 0.0  # Rim fraction at death

# Warp transition (CNEWV2). See PLAYFIELD.md § 5.3.
const WARP_SPEED: float = 24.0  # EYL += $18 per frame
var warp_timer: int = 0
var warp_phase: int = 0  # 0=zoom out, 1=zoom in
var warp_eye_start: float = 0.0
var warp_zadj_start: float = 0.0

# Bonus life system. See GAME_STATE_FLOW.md scoring.
const BONUS_THRESHOLDS: Array[int] = [20000, 60000]
var next_bonus_idx: int = 0
var bonus_flash_timer: int = 0

# Game over
var game_over_timer: int = 0

# Inter-level drop (CDROP). See ENTITIES.md § Inter-Level Drop.
var drop_velocity: float = 0.0  # 16-bit velocity: accumulates with acceleration
var drop_y: float = 0x10  # Player depth during drop (starts at rim)

# Wave bonus table (BONPTM). Points awarded at end of each wave.
# Index = starting skill level (0-8). All waves above 8 use index 8.
const WAVE_BONUS: Array[int] = [0, 60, 160, 320, 540, 740, 940, 1140, 1340]

# Node references
@onready var well: Node2D = $GameViewport/SubViewport/Well
@onready var player: Node2D = $GameViewport/SubViewport/Entities/Player
@onready var projectiles: Node2D = $GameViewport/SubViewport/Entities/Projectiles
@onready var enemy_mgr: Node2D = $GameViewport/SubViewport/Entities/InvaderManager
@onready var enemy_shots: Node2D = $GameViewport/SubViewport/Entities/EnemyShots
@onready var hud: Node2D = $GameViewport/SubViewport/HUD

# Input state
var _spinner_delta: int = 0
var _mouse_delta: float = 0.0  # Accumulated mouse X movement
var _fire_pressed: bool = false
var _zap_pressed: bool = false

# Mouse spinner settings
const MOUSE_SENSITIVITY: float = 0.4  # Mouse pixels per spinner unit

# Superzapper state. See ENTITIES.md § Superzapper.
const CSUSTA: int = 3   # Frames before first kill
const CSUINT: int = 1   # Kill interval = CSUINT + 1 = 2 frames
var suzcnt: int = 0     # Uses this wave (0, 1, or 2)
var suztim: int = 0     # Active timer (counts down)
var suz_elapsed: int = 0  # Frames since activation (counts up)
var _saved_well_color: Color  # Restore after zap ends


func _ready() -> void:
	# Capture mouse for spinner input
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Start in attract/logo state — load wave 1 visuals but don't play
	_load_wave_visuals(1)
	state = State.CLOGO
	attract_mode = true
	hud.set_message("PRESS START")


## Load well visuals only (for attract mode, warp transitions).
func _load_wave_visuals(wave: int) -> void:
	var shape_data: Dictionary = LevelData.get_well_data(wave)
	well.load_shape(shape_data)
	well.well_color = Colors.get_well_color(wave)
	hud.update_display(score, lives, wave)


## Full wave init — load shape, reset all entities, begin gameplay.
func _start_wave(wave: int) -> void:
	current_wave = wave
	var shape_data: Dictionary = LevelData.get_well_data(wave)
	var wave_params: Dictionary = LevelData.get_wave_params(wave)

	well.load_shape(shape_data)
	well.well_color = Colors.get_well_color(wave)
	player.init_for_wave(well, shape_data.planar)
	projectiles.init_for_wave(well)
	enemy_mgr.init_for_wave(well, wave_params)
	enemy_shots.init_for_wave(well, enemy_mgr.get_charge_speed())
	hud.update_display(score, lives, wave)

	_calc_collision_distances(wave_params)

	# Reset superzapper uses for new wave
	suzcnt = 0
	suztim = 0

	state = State.CPLAY


## Start a new game from attract mode.
func _start_new_game(start_wave: int = 1) -> void:
	attract_mode = false
	attract_pause = SECOND * 3
	score = 0
	lives = INITIAL_LIVES
	next_bonus_idx = 0
	current_wave = start_wave
	hud.set_message("")
	_start_wave(current_wave)


## Calculate ENSIZE per type and CHACHA using integer math matching original.
## See ENTITIES.md § ENSIZE: speed_hi = (seed * 8) >> 8, ENSIZE = (abs(speed_hi) + 13) / 2
func _calc_collision_distances(params: Dictionary) -> void:
	var base_seed: int = absi(params.invader_speed)
	# Flipper/Tanker ENSIZE
	@warning_ignore("integer_division")
	var speed_hi: int = (base_seed * 8) >> 8  # Integer high byte of TIMES8 result
	@warning_ignore("integer_division")
	var base_ensize: int = (speed_hi + 13) / 2
	ensize[0] = float(base_ensize)  # Flipper
	ensize[1] = float(base_ensize)  # Pulsar (same base)
	ensize[2] = float(base_ensize)  # Tanker
	# Spiker has its own speed
	var spiker_seed: int = absi(params.invader_speed + LevelData.get_spiker_speed_delta(params.wave))
	@warning_ignore("integer_division")
	var spiker_hi: int = (spiker_seed * 8) >> 8
	@warning_ignore("integer_division")
	ensize[3] = float((spiker_hi + 13) / 2)
	# Fuseball: fixed ENSIZE = (PCVELO + 3) / 2 = (9 + 3) / 2 = 6
	ensize[4] = 6.0
	# CHACHA: enemy shot speed uses seed + (-64)
	var charge_seed: int = absi(params.invader_speed + (-64))
	@warning_ignore("integer_division")
	var charge_hi: int = (charge_seed * 8) >> 8
	@warning_ignore("integer_division")
	chacha = float((charge_hi + 13) / 2)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		_fire_pressed = true
	if event.is_action_pressed("superzapper"):
		_zap_pressed = true
	if event.is_action_pressed("start"):
		if attract_mode:
			_start_new_game(1)

	# Mouse left-click fires too (since mouse is captured for spinner)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_fire_pressed = true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_zap_pressed = true

	# Mouse spinner — accumulate horizontal mouse motion
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative.x * MOUSE_SENSITIVITY

	# Escape releases mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# Read spinner input — combine keyboard + mouse
	_spinner_delta = 0
	if Input.is_action_pressed("rotate_cw"):
		_spinner_delta += 8
	if Input.is_action_pressed("rotate_ccw"):
		_spinner_delta -= 8

	# Add mouse delta as analog spinner input (unclamped — allows fast spinning!)
	if absf(_mouse_delta) >= 1.0:
		_spinner_delta += int(_mouse_delta)
		_mouse_delta = 0.0

	# Fixed-tick game logic at 20 Hz, render every frame
	_tick_accumulator += delta
	while _tick_accumulator >= TICK_RATE:
		_tick_accumulator -= TICK_RATE
		_game_tick()


func _game_tick() -> void:
	qframe = (qframe + 1) % 256

	# State dispatch — mirrors EXSTAT in ALEXEC.MAC
	match state:
		State.CLOGO:
			_state_logo()
		State.CPLAY:
			_state_play()
		State.CENDLI:
			_state_endlife()
		State.CNEWLI:
			_state_newlife()
		State.CNWLF2:
			_state_newlife2()
		State.CENDWAV:
			_state_endwave()
		State.CNEWV2:
			_state_warp()
		State.CBOOM:
			_state_boom()
		State.CDROP:
			_state_drop()
		State.CENDGA:
			_state_gameover()
		State.CPAUSE:
			_state_pause()
		_:
			pass


func set_state(new_state: State) -> void:
	state = new_state


# --- State handlers ---

## CPAUSE — generic timed delay. Decrements timer, transitions to next state.
func _set_pause(frames: int, next: State) -> void:
	pause_timer = frames
	pause_next_state = next
	state = State.CPAUSE


func _state_pause() -> void:
	pause_timer -= 1
	if pause_timer <= 0:
		state = pause_next_state


## CLOGO — Attract mode. Show well + "PRESS START" message.
## After a brief pause, starts a demo game with AI control. See GAME_STATE_FLOW.md.
var attract_pause: int = SECOND * 3  # 3 seconds before demo starts

func _state_logo() -> void:
	# Rotate the well cursor slowly for visual interest
	@warning_ignore("integer_division")
	well.player_line = (qframe / 4) % 16
	well.queue_redraw()

	attract_pause -= 1
	if attract_pause <= 0:
		# Start demo game: random wave 1-8, single life
		attract_mode = true
		lives = 1
		score = 0
		next_bonus_idx = 0
		current_wave = (randi() % 8) + 1
		hud.set_message("")
		_start_wave(current_wave)  # Sets state to CPLAY


func _state_play() -> void:
	# Main gameplay frame: GETCUR -> MOVCUR -> FIREPC -> MOVCHA -> MOVINV -> COLLID
	# See SYSTEMS.md § Execution Order

	# 1. GETCUR + MOVCUR — read input, move player
	# In attract mode, AUTOCU replaces human input
	var move_delta: int = _spinner_delta
	if attract_mode:
		move_delta = _autocu()
		_fire_pressed = true  # Auto-fire during attract
	player.move(move_delta)

	# 2. Update well flashlight to follow player
	well.player_line = player.cursl1
	well.queue_redraw()

	# 3. FIREPC — fire if button pressed
	if _fire_pressed:
		projectiles.fire(player.cursl1, player.cursl2)
		_fire_pressed = false

	# 4. MOVCHA — advance all shots (player and enemy)
	projectiles.move_all(enemy_mgr.spikes)
	enemy_shots.move_all()
	enemy_shots.advance_anim()

	# 5. MOVINV / MOVNYM / MOVSPK — advance all enemies
	enemy_mgr.tick(player.cursl1, player.cursy, qframe)

	# 5b. PROEXP — tick explosion animations
	enemy_mgr.tick_explosions()

	# Update spike rendering data from invader_manager → well_renderer
	well.spike_depths = enemy_mgr.spikes

	# 6. Enemy firing — check if any invader should fire
	_enemy_fire()

	# 7. COLLID — collision detection
	_collide()

	# 8. Check for player death from CAM kill checks
	if enemy_mgr.is_player_killed():
		_player_die()

	# 9. Check enemy shot hitting player
	if enemy_shots.check_player_hit(player.cursl1, player.cursy):
		_player_die()

	# 10. PROSUZ — superzapper activation
	if _zap_pressed and suzcnt < 2:
		_zap_pressed = false
		_activate_superzapper()
	else:
		_zap_pressed = false

	# 11. Check wave clear
	if enemy_mgr.is_wave_clear():
		state = State.CENDWAV

	# Clear timed HUD messages
	if bonus_flash_timer > 0:
		bonus_flash_timer -= 1
		if bonus_flash_timer <= 0:
			hud.set_message("")

	# Update HUD
	hud.update_display(score, lives, current_wave)


func _enemy_fire() -> void:
	# Check each invader for firing opportunity. See ENTITIES.md § FIREIC.
	var max_shots: int = LevelData.get_max_shots(current_wave) + 1
	if enemy_shots.get_active_count() >= max_shots:
		return

	for inv in enemy_mgr.invaders:
		# Use invader_manager's type-aware fire check
		# (spikers/fuseballs never fire, pulsars only wave 60+)
		if not enemy_mgr.can_invader_fire(inv):
			continue
		# CHANCE table throttle — reduces probability with more active shots
		var active_shots: int = enemy_shots.get_active_count()
		var chance: int = 16 + active_shots * 8  # Higher = less likely
		if randi() % chance != 0:
			continue

		# Fire!
		enemy_shots.fire(inv.l1, inv.y)
		inv.fire_timer = LevelData.get_fire_delay(current_wave)

		if enemy_shots.get_active_count() >= max_shots:
			return


func _collide() -> void:
	# For each active player shot, check against enemies and enemy shots.
	# See ENTITIES.md § Collision Detection System.
	var active_invaders: Array[Dictionary] = enemy_mgr.get_active_invaders()
	var active_enemy_shots: Array[Dictionary] = enemy_shots.get_active_shots()

	for i in projectiles.NPCHARG:
		if not projectiles.active[i]:
			continue

		var py: float = projectiles.shot_y[i]
		var pl: int = projectiles.shot_l1[i]

		# Check vs enemy shots
		for es in active_enemy_shots:
			if es.l1 == pl and absf(py - es.y) < chacha:
				# Both destroyed
				projectiles.active[i] = false
				enemy_shots.deactivate(es.idx)
				_add_score(50)
				break

		if not projectiles.active[i]:
			continue  # Shot was destroyed

		# Check vs invaders
		for inv_data in active_invaders:
			if inv_data.l1 == pl and absf(py - inv_data.y) < ensize[inv_data.type]:
				# Hit! Kill invader
				projectiles.active[i] = false
				_add_score(enemy_mgr.kill_invader(inv_data.idx))
				break

	projectiles.queue_redraw()


func _player_die() -> void:
	if state != State.CPLAY and state != State.CBOOM:
		return
	player.start_death(DEATH_FRAMES)
	# Clear active shots
	projectiles.clear_all()
	enemy_shots.clear_all()
	state = State.CENDLI


## CENDLI — death explosion animation, then transition to respawn or game over.
func _state_endlife() -> void:
	# Tick player death animation and any active enemy explosions
	enemy_mgr.tick_explosions()
	var done: bool = player.tick_death()

	# Well color strobe during death
	var hue: float = fmod(float(qframe) * 0.2, 1.0)
	well.well_color = Color.from_hsv(hue, 1.0, 1.0)
	well.queue_redraw()

	if done:
		# Restore well color
		well.well_color = Colors.get_well_color(current_wave)
		well.queue_redraw()
		lives -= 1
		if lives <= 0:
			if attract_mode:
				# Attract demo over — return to logo quickly
				game_over_timer = SECOND
				hud.set_message("PRESS START")
			else:
				game_over_timer = SECOND * 3  # 3 seconds
				hud.set_message("GAME OVER")
			state = State.CENDGA
		else:
			hud.update_display(score, lives, current_wave)
			_set_pause(SECOND, State.CNEWLI)  # 1 second before respawn


## CNEWLI — reinitialize wave for new life.
func _state_newlife() -> void:
	_start_wave(current_wave)


## CNWLF2 — placeholder for new life part 2.
func _state_newlife2() -> void:
	state = State.CPLAY


## CENDWAV — wave cleared. Award bonus, begin inter-level drop.
func _state_endwave() -> void:
	# Award end-of-wave bonus
	var bonus_idx: int = mini(current_wave - 1, WAVE_BONUS.size() - 1)
	var bonus: int = WAVE_BONUS[bonus_idx]
	if bonus > 0:
		_add_score(bonus)
		hud.set_message("BONUS %d" % bonus)
	else:
		hud.set_message("")

	# Begin inter-level drop: player descends through well to destroy remaining spikes.
	drop_velocity = 0.0
	drop_y = player.cursy
	state = State.CDROP


## CNEWV2 — warp transition between waves. Camera dives INTO the well.
## See PLAYFIELD.md § 5.3: EYL += $18 per frame (eye moves forward through tube).
## Camera must NOT cross world.y = 0x10 (near rim) or projection inverts.
func _state_warp() -> void:
	warp_timer += 1

	# Phase 0: dive in (accelerating toward near rim) — 30 frames
	# Phase 1: new well, zoom in from far away — 30 frames
	const WARP_HALF: int = 30
	const NEAR_Y: float = 0x10  # Near rim world Y — camera must stay below this

	if warp_phase == 0:
		# Quadratic ease-in: accelerates toward near rim, stops at 95%
		var t: float = float(warp_timer) / float(WARP_HALF)
		var max_forward: float = (NEAR_Y - warp_eye_start) * 0.95
		well.eye.y = warp_eye_start + max_forward * t * t
		well.queue_redraw()

		if warp_timer >= WARP_HALF:
			# Midpoint: load new well shape
			_load_wave_visuals(current_wave)
			var shape_data: Dictionary = LevelData.get_well_data(current_wave)
			warp_eye_start = -float(shape_data.holeyl)
			warp_zadj_start = float(shape_data.holzad) / 256.0
			# Start camera far behind the new well (very small on screen)
			well.eye.y = warp_eye_start - 300.0
			warp_phase = 1
			warp_timer = 0
	else:
		# Quadratic ease-out: decelerates as it approaches final position
		var t: float = float(warp_timer) / float(WARP_HALF)
		var far_start: float = warp_eye_start - 300.0
		well.eye.y = lerpf(far_start, warp_eye_start, 1.0 - (1.0 - t) * (1.0 - t))
		well.z_adjust = warp_zadj_start
		well.queue_redraw()

		if warp_timer >= WARP_HALF:
			# Warp complete — start new wave
			hud.set_message("SUPERZAPPER RECHARGE")
			_start_wave(current_wave)
			bonus_flash_timer = SECOND * 2


## PROSUZ — Activate superzapper. See ENTITIES.md § Superzapper.
func _activate_superzapper() -> void:
	suzcnt += 1
	# Duration: CSUSTA + (multiplier * (CSUINT+1))
	# 1st use: 3 + 8*2 = 19 frames. 2nd use: 3 + 1*2 = 5 frames.
	var multiplier: int = 8 if suzcnt == 1 else 1
	suztim = CSUSTA + multiplier * (CSUINT + 1)
	suz_elapsed = 0
	_saved_well_color = well.well_color
	state = State.CBOOM


func _state_boom() -> void:
	# Superzapper active: cycle well colors, sequentially kill enemies.
	# See ENTITIES.md § Superzapper, KILENE routine.

	# Tick explosions from previous kills
	enemy_mgr.tick_explosions()

	# Player can still move during CBOOM
	player.move(_spinner_delta)
	well.player_line = player.cursl1

	# Well color cycling (strobe effect based on QFRAME)
	var hue: float = fmod(float(qframe) * 0.15, 1.0)
	well.well_color = Color.from_hsv(hue, 1.0, 1.0)
	well.queue_redraw()

	# Kill one enemy every CSUINT+1 (2) frames, starting after CSUSTA (3) frames
	if suz_elapsed >= CSUSTA and (suz_elapsed - CSUSTA) % (CSUINT + 1) == 0:
		# Kill first active enemy found
		for i in enemy_mgr.MAX_INVADERS:
			if enemy_mgr.invaders[i].active:
				_add_score(enemy_mgr.kill_invader(i))
				break

	# Also clear enemy shots during superzapper
	enemy_shots.clear_all()

	suz_elapsed += 1
	suztim -= 1
	if suztim <= 0:
		# Restore well color and return to gameplay
		well.well_color = _saved_well_color
		well.queue_redraw()
		state = State.CPLAY


## CENDGA — Game Over. Show message, then return to attract mode.
func _state_gameover() -> void:
	game_over_timer -= 1
	if game_over_timer <= 0:
		# Return to attract mode
		attract_mode = true
		attract_pause = SECOND * 3
		hud.set_message("PRESS START")
		_load_wave_visuals(1)
		state = State.CLOGO


## CDROP — Inter-level drop. Player descends through well, can hit spikes.
## Acceleration = 20 + min(wave, 30) per frame. See ENTITIES.md § Inter-Level Drop.
func _state_drop() -> void:
	# Player can still move and fire during drop
	player.move(_spinner_delta)
	well.player_line = player.cursl1
	well.queue_redraw()

	if _fire_pressed:
		projectiles.fire(player.cursl1, player.cursl2)
		_fire_pressed = false
	_zap_pressed = false  # Superzapper disabled during drop

	projectiles.move_all(enemy_mgr.spikes)

	# Accelerating descent: velocity increases each frame
	var accel: float = (20.0 + float(mini(current_wave, 30))) / 256.0
	drop_velocity += accel
	drop_y += drop_velocity
	player.cursy = drop_y

	# Check spike collision during drop — spike kills player
	var player_lane: int = player.cursl1
	if enemy_mgr.spikes.size() > player_lane:
		if enemy_mgr.spikes[player_lane] < 0xF0 and drop_y >= float(enemy_mgr.spikes[player_lane]):
			_player_die()
			return

	# Update spike rendering
	well.spike_depths = enemy_mgr.spikes

	# Check if player reached bottom of well
	if drop_y >= 0xF0:
		# Advance wave (cap at 99) and start warp
		current_wave = mini(current_wave + 1, 99)
		warp_timer = 0
		warp_phase = 0
		warp_eye_start = well.eye.y
		warp_zadj_start = well.z_adjust
		state = State.CNEWV2

	hud.update_display(score, lives, current_wave)


## AUTOCU — Attract mode AI. Greedy nearest-enemy targeting.
## Scans all invaders, finds closest to player (smallest Y), moves toward it.
## Returns simulated spinner delta (±9). See GAME_STATE_FLOW.md § Attract Mode.
func _autocu() -> int:
	var best_y: float = 0xFF
	var best_lane: int = -1

	# Find nearest enemy
	for inv in enemy_mgr.invaders:
		if inv.active and inv.y < best_y:
			best_y = inv.y
			best_lane = inv.l1

	if best_lane < 0:
		return 0  # No enemies, no movement

	# POLDEL — shortest polar distance on 16-lane ring
	var num_lanes: int = player.num_lanes
	var delta: int = best_lane - player.cursl1
	@warning_ignore("integer_division")
	var half_lanes: int = num_lanes / 2
	if not player.is_planar:
		# Wrap around for closed wells
		if delta > half_lanes:
			delta -= num_lanes
		elif delta < -half_lanes:
			delta += num_lanes

	if delta == 0:
		return 0  # Already aligned
	elif delta > 0:
		return 9  # Move clockwise toward target
	else:
		return -9  # Move counter-clockwise toward target


## Add points and check bonus life thresholds.
func _add_score(points: int) -> void:
	var old_score: int = score
	score += points
	# Check bonus life thresholds (20K, 60K)
	if next_bonus_idx < BONUS_THRESHOLDS.size():
		if old_score < BONUS_THRESHOLDS[next_bonus_idx] and score >= BONUS_THRESHOLDS[next_bonus_idx]:
			lives += 1
			bonus_flash_timer = SECOND  # Flash for 1 second
			next_bonus_idx += 1
	hud.update_display(score, lives, current_wave)
