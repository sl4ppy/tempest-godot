class_name CAMInterpreter
## CAM (Computer-Aided Movement) bytecode interpreter for enemy AI.
## See CAM_SCRIPTS.md for the complete instruction set and script definitions.

# CAM Opcodes
const VEXIT  := 0x00  # Yield (end frame execution)
const VSLOOP := 0x02  # Set loop counter from immediate byte
const VSKIP0 := 0x04  # Skip 2 bytes if CAMSTA == 0
const VSETPC := 0x06  # Unconditional branch
const VELOOP := 0x08  # Decrement loop, branch if non-zero
const VNOOP  := 0x0A  # No-op
const VSMOVE := 0x0C  # Move invader up/down one frame
const VSTRAI := 0x0E  # Process trailer (spiker) logic
const VSLOPB := 0x10  # Set loop counter from memory
const VJUMPS := 0x12  # Start lane-change jump
const VJUMPM := 0x14  # Continue jump motion
const VCHROT := 0x16  # Reverse jump direction
const VKITST := 0x18  # Test cursor kill (both legs same lane)
const VBR0PC := 0x1A  # Branch if CAMSTA == 0
const VELTST := 0x1C  # Test if on enemy line
const VSFUSE := 0x1E  # Fuseball up/down motion
const VFUSKI := 0x20  # Fuseball cursor-kill check
const VSPUMO := 0x22  # Pulsar movement
const VCHPLA := 0x24  # Set flip direction toward player
const VCHKPU := 0x26  # Check if pulsing in next 4 frames

# Script data — loaded from CAM_SCRIPTS.md definitions
var scripts: Dictionary = {}  # name -> PackedByteArray


## Execute one frame of CAM for an invader. Returns when VEXIT is hit.
func execute_frame(invader: Dictionary, game_state: Dictionary) -> void:
	var exit_flag := false
	while not exit_flag:
		var opcode: int = _read_byte(invader)
		match opcode:
			VEXIT:
				exit_flag = true
			VSLOOP:
				invader.loop_counter = _read_byte(invader)
			VELOOP:
				var target: int = _read_byte(invader)
				invader.loop_counter -= 1
				if invader.loop_counter > 0:
					invader.cam_pc = target
			VSETPC:
				invader.cam_pc = _read_byte(invader)
			VSKIP0:
				if invader.cam_status == 0:
					invader.cam_pc += 2
			VBR0PC:
				var target: int = _read_byte(invader)
				if invader.cam_status == 0:
					invader.cam_pc = target
			VNOOP:
				pass
			VSMOVE:
				_move_invader(invader, game_state)
			VJUMPS:
				_start_jump(invader, game_state)
			VJUMPM:
				_continue_jump(invader, game_state)
			VCHROT:
				invader.jump_direction *= -1
			VCHPLA:
				_set_direction_toward_player(invader, game_state)
			VKITST:
				_test_cursor_kill(invader, game_state)
			VELTST:
				_test_enemy_line(invader, game_state)
			VSFUSE:
				_fuse_move(invader, game_state)
			VFUSKI:
				_fuse_kill_check(invader, game_state)
			VSPUMO:
				_pulsar_move(invader, game_state)
			VCHKPU:
				_check_pulsing(invader, game_state)
			VSTRAI:
				_process_trailer(invader, game_state)
			VSLOPB:
				var addr: int = _read_byte(invader)
				invader.loop_counter = game_state.get(addr, 1)
			_:
				push_warning("Unknown CAM opcode: 0x%02X" % opcode)
				exit_flag = true


func _read_byte(invader: Dictionary) -> int:
	var script: PackedByteArray = invader.cam_script
	var val: int = script[invader.cam_pc]
	invader.cam_pc += 1
	return val


# --- Opcode implementations (stubs — to be filled in Phase 2) ---

func _move_invader(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _start_jump(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _continue_jump(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _set_direction_toward_player(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _test_cursor_kill(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _test_enemy_line(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _fuse_move(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _fuse_kill_check(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _pulsar_move(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _check_pulsing(_invader: Dictionary, _state: Dictionary) -> void:
	pass

func _process_trailer(_invader: Dictionary, _state: Dictionary) -> void:
	pass
