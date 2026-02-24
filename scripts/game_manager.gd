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

var state: State = State.CLOGO
var attract_mode: bool = true
var current_wave: int = 1
var score: int = 0
var lives: int = 4
var _tick_accumulator: float = 0.0
var qframe: int = 0  # Global frame counter (wraps at 256)

# Collision constants
var ensize: Array[float] = [0, 0, 0, 0, 0]  # Per-type collision range
var chacha: float = 0.0  # Shot-vs-shot collision distance

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
	_start_wave(current_wave)


func _start_wave(wave: int) -> void:
	current_wave = wave
	var shape_data: Dictionary = LevelData.get_well_data(wave)
	var wave_params: Dictionary = LevelData.get_wave_params(wave)

	well.load_shape(shape_data)
	well.well_color = Colors.get_well_color(wave)
	player.init_for_wave(well, shape_data.planar)
	projectiles.init_for_wave(well)
	enemy_mgr.init_for_wave(well, wave_params)
	# Enemy shot speed computed by invader_manager via TIMES8(base_seed - 64)
	enemy_shots.init_for_wave(well, enemy_mgr.get_charge_speed())
	hud.update_display(score, lives, wave)

	# Calculate collision distances. See ENTITIES.md § ENSIZE.
	_calc_collision_distances(wave_params)

	# Reset superzapper uses for new wave
	suzcnt = 0
	suztim = 0

	state = State.CPLAY


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
	if event.is_action_pressed("start") and state == State.CLOGO:
		_start_wave(1)

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
		State.CENDWAV:
			_state_endwave()
		State.CNEWV2:
			_state_warp()
		State.CBOOM:
			_state_boom()
		State.CDROP:
			_state_drop()
		_:
			pass


func set_state(new_state: State) -> void:
	state = new_state


# --- State handlers ---

func _state_logo() -> void:
	pass


func _state_play() -> void:
	# Main gameplay frame: GETCUR -> MOVCUR -> FIREPC -> MOVCHA -> MOVINV -> COLLID
	# See SYSTEMS.md § Execution Order

	# 1. GETCUR + MOVCUR — read input, move player
	player.move(_spinner_delta)

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
				score += 50
				break

		if not projectiles.active[i]:
			continue  # Shot was destroyed

		# Check vs invaders
		for inv_data in active_invaders:
			if inv_data.l1 == pl and absf(py - inv_data.y) < ensize[inv_data.type]:
				# Hit! Kill invader
				projectiles.active[i] = false
				score += enemy_mgr.kill_invader(inv_data.idx)
				break

	projectiles.queue_redraw()


func _player_die() -> void:
	if state != State.CPLAY:
		return
	lives -= 1
	if lives <= 0:
		state = State.CENDGA
	else:
		state = State.CENDLI


func _state_endlife() -> void:
	# Brief pause then restart wave
	# TODO: death explosion animation
	_start_wave(current_wave)


func _state_endwave() -> void:
	# Advance to next wave
	current_wave += 1
	_start_wave(current_wave)


func _state_warp() -> void:
	pass


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
				score += enemy_mgr.kill_invader(i)
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


func _state_drop() -> void:
	pass
