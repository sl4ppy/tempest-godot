extends Node2D
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


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	# Fixed-tick game logic at 20 Hz, render every frame
	_tick_accumulator += delta
	while _tick_accumulator >= TICK_RATE:
		_tick_accumulator -= TICK_RATE
		_game_tick()


func _game_tick() -> void:
	qframe = (qframe + 1) % 256

	# State dispatch - mirrors EXSTAT in ALEXEC.MAC
	match state:
		State.CLOGO:
			_state_logo()
		State.CPLAY:
			_state_play()
		State.CNEWV2:
			_state_warp()
		State.CBOOM:
			_state_boom()
		State.CDROP:
			_state_drop()
		_:
			pass  # TODO: implement remaining states


func set_state(new_state: State) -> void:
	state = new_state


# --- State handlers (stubs) ---

func _state_logo() -> void:
	pass


func _state_play() -> void:
	# Main gameplay frame: GETCUR → MOVCUR → SLAUNC → MOVCHA → ...
	pass


func _state_warp() -> void:
	# NEWAV2 wave transition. See PLAYFIELD.md § 5.3
	pass


func _state_boom() -> void:
	# Superzapper particle explosion. See ENTITIES.md § Superzapper
	pass


func _state_drop() -> void:
	# Inter-level drop physics. See ENTITIES.md § Inter-Level Drop
	pass
