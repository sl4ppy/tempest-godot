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
const VSLOPB := 0x10  # Set loop counter from game state
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

# Game state tags for VSLOPB
const TAG_WTTFRA := 0x01  # Top flip rate
const TAG_PUCHDE := 0x02  # Pulsar chase delay

# Jump interpolation constants
const JUMP_FRAMES := 8  # Frames to complete a lane-change flip

# --- CAM Script Bytecode ---
# Each script is a PackedByteArray. Branch targets are absolute offsets.

# NOJUMP — Straight up, no lane changes. Tankers, early flippers.
static var NOJUMP := PackedByteArray([
	0x0C,        # 0: VSMOVE
	0x00,        # 1: VEXIT
	0x06, 0x00,  # 2: VSETPC → 0
])

# MOVJMP — Move 8 frames then jump. Square, Triangle wells.
static var MOVJMP := PackedByteArray([
	0x02, 0x08,  # 0: VSLOOP 8
	0x0C,        # 2: VSMOVE (MJLOP1)
	0x00,        # 3: VEXIT
	0x08, 0x02,  # 4: VELOOP → 2
	0x12,        # 6: VJUMPS
	0x00,        # 7: VEXIT (MJLOP5)
	0x14,        # 8: VJUMPM
	0x04,        # 9: VSKIP0
	0x06, 0x07,  # 10: VSETPC → 7 (not done)
	0x06, 0x00,  # 12: VSETPC → 0 (done, restart)
])

# SPIRAL — Smooth upward spiral. Cross, V-shape, Heart wells.
static var SPIRAL := PackedByteArray([
	0x0C,        # 0: VSMOVE
	0x00,        # 1: VEXIT
	0x12,        # 2: VJUMPS
	0x00,        # 3: VEXIT (SPILOP)
	0x14,        # 4: VJUMPM
	0x0C,        # 5: VSMOVE
	0x04,        # 6: VSKIP0
	0x06, 0x03,  # 7: VSETPC → 3
	0x06, 0x00,  # 9: VSETPC → 0
])

# SPIRCH — Spiral with direction changes. Peanut, Clover, Flat, 8-shape.
static var SPIRCH := PackedByteArray([
	0x0C,        # 0: VSMOVE
	0x00,        # 1: VEXIT
	0x02, 0x02,  # 2: VSLOOP 2
	0x12,        # 4: VJUMPS (SPRLP1)
	0x00,        # 5: VEXIT (SPRLP2)
	0x14,        # 6: VJUMPM
	0x0C,        # 7: VSMOVE
	0x04,        # 8: VSKIP0
	0x06, 0x05,  # 9: VSETPC → 5
	0x00,        # 11: VEXIT
	0x08, 0x04,  # 12: VELOOP → 4
	0x16,        # 14: VCHROT
	0x02, 0x03,  # 15: VSLOOP 3
	0x12,        # 17: VJUMPS (SPRLP3)
	0x00,        # 18: VEXIT (SPRLP4)
	0x14,        # 19: VJUMPM
	0x0C,        # 20: VSMOVE
	0x04,        # 21: VSKIP0
	0x06, 0x12,  # 22: VSETPC → 18
	0x00,        # 24: VEXIT
	0x08, 0x11,  # 25: VELOOP → 17
	0x16,        # 27: VCHROT
	0x06, 0x00,  # 28: VSETPC → 0
])

# COWJMP — Flip only on open lines. Key, Stairs, Star wells.
# Entry at offset 1 (COWJMP); offset 0 is COWJM2 (yield point).
static var COWJMP := PackedByteArray([
	0x00,        # 0: VEXIT (COWJM2)
	0x0C,        # 1: VSMOVE (COWJMP entry)
	0x1C,        # 2: VELTST
	0x1A, 0x00,  # 3: VBR0PC → 0 (on enemy line, stay)
	0x12,        # 5: VJUMPS
	0x00,        # 6: VEXIT
	0x0C,        # 7: VSMOVE
	0x14,        # 8: VJUMPM (COWJM3)
	0x1A, 0x00,  # 9: VBR0PC → 0 (jump done)
	0x00,        # 11: VEXIT
	0x06, 0x08,  # 12: VSETPC → 8
])

# TOPPER — Chase player around rim. Used by any enemy reaching the top.
static var TOPPER := PackedByteArray([
	0x02, 0x04,  # 0: VSLOOP 4
	0x18,        # 2: VKITST (KICHEK)
	0x00,        # 3: VEXIT
	0x08, 0x02,  # 4: VELOOP → 2
	0x12,        # 6: VJUMPS
	0x00,        # 7: VEXIT (KJULP1)
	0x10, 0x01,  # 8: VSLOPB TAG_WTTFRA
	0x14,        # 10: VJUMPM (KJULP2)
	0x1A, 0x00,  # 11: VBR0PC → 0 (done, restart)
	0x08, 0x0A,  # 13: VELOOP → 10
	0x06, 0x07,  # 15: VSETPC → 7
])

# AVOIDR — Flip away from player. U-shape, Jagged wells.
static var AVOIDR := PackedByteArray([
	0x24,        # 0: VCHPLA
	0x16,        # 1: VCHROT
	0x12,        # 2: VJUMPS
	0x00,        # 3: VEXIT (AVOID1)
	0x0C,        # 4: VSMOVE
	0x14,        # 5: VJUMPM
	0x04,        # 6: VSKIP0
	0x06, 0x03,  # 7: VSETPC → 3
	0x02, 0x04,  # 9: VSLOOP 4
	0x00,        # 11: VEXIT (AVOID2)
	0x0C,        # 12: VSMOVE
	0x08, 0x0B,  # 13: VELOOP → 11
	0x06, 0x00,  # 15: VSETPC → 0
])

# TRALUP — Trailer/Spiker movement.
static var TRALUP := PackedByteArray([
	0x0C,        # 0: VSMOVE
	0x0E,        # 1: VSTRAI
	0x00,        # 2: VEXIT
	0x06, 0x00,  # 3: VSETPC → 0
])

# FUSE — Combined Fuseball vertical (FUSEUP) + lateral (FUSELR).
# FUSEUP starts at offset 0, FUSELR at offset 5.
static var FUSE := PackedByteArray([
	# FUSEUP (offset 0)
	0x1E,        # 0: VSFUSE
	0x20,        # 1: VFUSKI
	0x00,        # 2: VEXIT
	0x06, 0x00,  # 3: VSETPC → 0
	# FUSELR (offset 5)
	0x00,        # 5: VEXIT
	0x02, 0x03,  # 6: VSLOOP 3
	0x20,        # 8: VFUSKI (FUSLOP)
	0x00,        # 9: VEXIT
	0x08, 0x08,  # 10: VELOOP → 8
	0x14,        # 12: VJUMPM
	0x1A, 0x00,  # 13: VBR0PC → 0 (done, back to FUSEUP)
	0x06, 0x05,  # 15: VSETPC → 5
])

# PULSAR — Combined pulsar chaser script.
static var PULSAR := PackedByteArray([
	# PULSCP (offset 0)
	0x10, 0x02,  # 0: VSLOPB TAG_PUCHDE
	0x22,        # 2: VSPUMO (PULSC1)
	0x00,        # 3: VEXIT
	0x08, 0x02,  # 4: VELOOP → 2
	# PULSC2 (offset 6)
	0x26,        # 6: VCHKPU
	0x1A, 0x0D,  # 7: VBR0PC → 13 (not pulsing, go flip)
	0x22,        # 9: VSPUMO
	0x00,        # 10: VEXIT
	0x06, 0x06,  # 11: VSETPC → 6
	# PULSC3 (offset 13)
	0x24,        # 13: VCHPLA
	0x12,        # 14: VJUMPS
	0x00,        # 15: VEXIT (PULSCJ)
	0x14,        # 16: VJUMPM
	0x1A, 0x00,  # 17: VBR0PC → 0 (done, restart)
	0x06, 0x0F,  # 19: VSETPC → 15
])

# Script lookup table
static var SCRIPTS: Dictionary = {
	"NOJUMP": NOJUMP,
	"MOVJMP": MOVJMP,
	"SPIRAL": SPIRAL,
	"SPIRCH": SPIRCH,
	"COWJMP": COWJMP,
	"TOPPER": TOPPER,
	"AVOIDR": AVOIDR,
	"TRALUP": TRALUP,
	"FUSE": FUSE,
	"PULSAR": PULSAR,
}

# Default CAM by enemy type (TNEWCAM)
# 0=Flipper, 1=Pulsar, 2=Tanker, 3=Spiker, 4=Fuseball
static var DEFAULT_CAM: Array[String] = [
	"NOJUMP",  # Flipper (overridden per wave)
	"PULSAR",  # Pulsar
	"NOJUMP",  # Tanker (always straight)
	"TRALUP",  # Spiker
	"FUSE",    # Fuseball
]


## Execute one frame of CAM for an invader. Returns when VEXIT is hit.
func execute_frame(invader: Dictionary, game_state: Dictionary) -> void:
	var safety: int = 100  # Prevent infinite loops
	while safety > 0:
		safety -= 1
		if invader.cam_pc >= invader.cam_script.size():
			break
		var opcode: int = _read_byte(invader)
		match opcode:
			VEXIT:
				return
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
				var tag: int = _read_byte(invader)
				match tag:
					TAG_WTTFRA:
						invader.loop_counter = game_state.get("top_flip_rate", 2)
					TAG_PUCHDE:
						invader.loop_counter = game_state.get("puchde", 20)
					_:
						invader.loop_counter = 1
			_:
				push_warning("Unknown CAM opcode: 0x%02X at PC=%d" % [opcode, invader.cam_pc - 1])
				return


func _read_byte(invader: Dictionary) -> int:
	var script: PackedByteArray = invader.cam_script
	if invader.cam_pc >= script.size():
		return VEXIT
	var val: int = script[invader.cam_pc]
	invader.cam_pc += 1
	return val


# --- Opcode implementations ---

## VSMOVE — Move invader up/down one frame using per-type speed.
## Original: 16-bit add INVAYL:INVAY += WINVIL[type]:WINVIN[type]. See ALWELG.MAC JSMOVE.
func _move_invader(invader: Dictionary, game_state: Dictionary) -> void:
	var speeds: Array = game_state.get("type_speed", [0.0, 0.0, 0.0, 0.0, 0.0])
	var speed: float = absf(speeds[invader.type])

	if invader.moving_up:
		invader.y -= speed
		# Check if reached rim (CURSY = $10)
		if invader.y <= 0x10:
			invader.y = 0x10
			invader.reached_rim = true
	else:
		invader.y += speed
		# Clamp at bottom ($F2)
		if invader.y >= 0xF2:
			invader.y = 0xF2


## VJUMPS — Start a lane-change jump sequence.
func _start_jump(invader: Dictionary, game_state: Dictionary) -> void:
	invader.is_jumping = true
	invader.jump_progress = 0.0
	invader.jump_src_lane = invader.l1

	var num_lanes: int = game_state.get("num_lanes", 16)
	var is_planar: bool = game_state.get("is_planar", false)

	var dst: int = invader.l1 + invader.jump_direction
	if is_planar:
		dst = clampi(dst, 0, num_lanes - 2)
	else:
		dst = dst % 16
		if dst < 0:
			dst += 16
	invader.jump_dst_lane = dst

	invader.cam_status = 1  # Jump in progress


## VJUMPM — Continue jump motion. Sets cam_status=0 when done.
## Original uses JUMPX/JUMPZ 8-entry lookup tables = 8 frames per flip.
func _continue_jump(invader: Dictionary, _game_state: Dictionary) -> void:
	if not invader.is_jumping:
		invader.cam_status = 0
		return

	invader.jump_progress += 1.0 / JUMP_FRAMES
	if invader.jump_progress >= 1.0:
		invader.jump_progress = 0.0
		invader.is_jumping = false
		invader.l1 = invader.jump_dst_lane
		invader.l2 = (invader.l1 + 1) % 16
		invader.cam_status = 0
	else:
		invader.cam_status = 1


## VCHPLA — Set jump direction toward player's current lane.
func _set_direction_toward_player(invader: Dictionary, game_state: Dictionary) -> void:
	var player_lane: int = game_state.get("player_lane", 0)
	var num_lanes: int = game_state.get("num_lanes", 16)
	var is_planar: bool = game_state.get("is_planar", false)

	if is_planar:
		invader.jump_direction = 1 if player_lane > invader.l1 else -1
	else:
		var diff: int = player_lane - invader.l1
		@warning_ignore("integer_division")
		var half: int = num_lanes / 2
		if diff > half:
			diff -= num_lanes
		elif diff < -half:
			diff += num_lanes
		invader.jump_direction = 1 if diff > 0 else -1


## VKITST — Test if invader is on same lane as player cursor (rim kill check).
func _test_cursor_kill(invader: Dictionary, game_state: Dictionary) -> void:
	var player_lane: int = game_state.get("player_lane", 0)
	if invader.l1 == player_lane and invader.y <= 0x10:
		game_state["player_killed"] = true


## VELTST — Test if invader is on an "enemy line". Sets cam_status.
## cam_status=0 means ON enemy line (deep enough), cam_status=1 means NOT on enemy line.
func _test_enemy_line(invader: Dictionary, game_state: Dictionary) -> void:
	var height: int = game_state.get("enemy_line_height", 0)
	if height == 0:
		invader.cam_status = 1  # No enemy line for this shape
	elif invader.y >= height:
		invader.cam_status = 0  # On enemy line
	else:
		invader.cam_status = 1  # Not on enemy line


## VSFUSE — Fuseball up/down motion. May initiate lateral flip.
## Uses dedicated fuse_speed (2x Flipper). See ALWELG.MAC JFUSUD.
func _fuse_move(invader: Dictionary, game_state: Dictionary) -> void:
	var speed: float = absf(game_state.get("fuse_speed", 2.0))
	if invader.moving_up:
		invader.y -= speed
		if invader.y <= 0x10:
			invader.y = 0x10
			invader.moving_up = false
	else:
		invader.y += speed
		if invader.y >= 0x80:
			invader.y = 0x80
			invader.moving_up = true

	# Periodically decide to flip laterally. See ENTITIES.md § Fuseball.
	var freq: int = game_state.get("fuse_freq", 220)
	if randi() % 256 < (256 - freq):
		# Check WFUSCH flag: chase mode vs random mode
		var chase: bool = game_state.get("fuse_chase", false)
		if chase:
			_set_direction_toward_player(invader, game_state)
		else:
			# LEFRIT: random direction
			invader.jump_direction = [-1, 1][randi() % 2]
		_start_jump(invader, game_state)
		invader.cam_pc = 5  # Jump to FUSELR section


## VFUSKI — Fuseball cursor-kill check (same lane + same depth).
func _fuse_kill_check(invader: Dictionary, game_state: Dictionary) -> void:
	if invader.is_jumping:
		return  # Invulnerable during flip
	var player_lane: int = game_state.get("player_lane", 0)
	var player_y: float = game_state.get("player_y", 0x10)
	if invader.l1 == player_lane and absf(invader.y - player_y) < 8.0:
		game_state["player_killed"] = true


## VSPUMO — Pulsar movement. Uses hardcoded speed ($FE:$A0 = -1.375/frame).
## When outside PULPOT zone, uses Flipper speed (faster) instead.
## While PULSON > 0, performs lethal collision check (JPULMO). See ALWELG.MAC.
func _pulsar_move(invader: Dictionary, game_state: Dictionary) -> void:
	var pulpot: int = game_state.get("pulpot", 0xA0)
	var speed: float
	if invader.y < pulpot:
		# Inside power zone: use hardcoded pulsar speed
		speed = 1.375  # abs($FE:$A0)
	else:
		# Outside power zone: use Flipper speed (faster)
		var speeds: Array = game_state.get("type_speed", [0.0, 0.0, 0.0, 0.0, 0.0])
		speed = absf(speeds[0])  # ZABFLI speed

	if invader.moving_up:
		invader.y -= speed
		if invader.y <= 0x10:
			invader.y = 0x10
			invader.reached_rim = true
	else:
		invader.y += speed
		if invader.y >= pulpot:
			invader.y = float(pulpot)
			invader.moving_up = true

	# JPULMO lethal check: while pulsing, kill player if on same lane within power zone.
	# See ENTITIES.md § Pulsar Lethality.
	var pulson_val: int = game_state.get("pulson", 0)
	if pulson_val > 0 and invader.y <= pulpot:
		var player_lane: int = game_state.get("player_lane", 0)
		if invader.l1 == player_lane:
			game_state["player_killed"] = true


## VCHKPU — Check if pulsar is currently pulsing. Sets cam_status.
func _check_pulsing(_invader: Dictionary, game_state: Dictionary) -> void:
	var pulson_val: int = game_state.get("pulson", 0)
	if pulson_val > 0:
		_invader.cam_status = 1  # Pulsing — delay the flip
	else:
		_invader.cam_status = 0  # Not pulsing — OK to flip


## VSTRAI — Process trailer/spiker special logic. See ALWELG.MAC JSTRAI.
func _process_trailer(invader: Dictionary, game_state: Dictionary) -> void:
	# Reverse direction at bounds
	if invader.moving_up:
		if invader.y <= 0x20:
			invader.moving_up = false
	else:
		if invader.y >= 0xF2:
			invader.moving_up = true
			_find_empty_lane(invader, game_state)
			# Check nymph exhaustion — convert to Tanker ONLY at bottom reversal
			var nymph_count: int = game_state.get("nymph_remaining", 0)
			if nymph_count <= 0:
				invader.convert_to_tanker = true

	# Record spike: LINEY[INVAL1] = INVAY (unconditional write, tracks current position)
	var spike_arr: Array = game_state.get("spikes", [])
	if invader.l1 < spike_arr.size():
		spike_arr[invader.l1] = int(invader.y)


## Find an empty lane for spiker. See ASTRAL in ALWELG.MAC.
func _find_empty_lane(invader: Dictionary, game_state: Dictionary) -> void:
	var num_lanes: int = game_state.get("num_lanes", 16)
	var occupied: Array = game_state.get("occupied_lanes", [])
	# Scan all lanes starting from a random offset
	var start: int = randi() % num_lanes
	for i in num_lanes:
		var lane: int = (start + i) % num_lanes
		if lane not in occupied:
			invader.l1 = lane
			invader.l2 = (lane + 1) % 16
			return
