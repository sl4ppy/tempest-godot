extends Node
## POKEY synthesis engine for Tempest sound effects.
## Implements the data-driven 4-byte sequence format from ALSOUN.MAC.
## Each sound consists of frequency + control channel sequences that modulate
## virtual POKEY registers. Audio is synthesized in real-time via AudioStreamGenerator.

const MIX_RATE: int = 44100
const FRAME_HZ: float = 60.0  # POKEY sequence update rate
const POKEY_DIV: float = 63920.5  # 1789773 Hz / 28

# Sound IDs matching ALSOUN.MAC constants
const SID_LO: int = 0   # Cursor move (SBOING)
const SID_EX: int = 1   # Enemy explosion (EXSNON)
const SID_LA: int = 2   # Player fire (SLAUNC)
const SID_PU: int = 3   # Pulsation ON (PULSTR)
const SID_WP: int = 4   # Bonus score (SAUSON)
const SID_DI: int = 5   # Player dies (CPEXPL)
const SID_T2: int = 6   # Thrust in tube (SOUTS2)
const SID_T3: int = 7   # Thrust in space (SOUTS3)
const SID_ES: int = 8   # Enemy shot (ESLSON)
const SID_EL: int = 9   # Enemy line destroyed (SELICO)
const SID_SL: int = 10  # Slam (SSLAMS)
const SID_S3: int = 11  # 3-second warning (S3SWAR)
const SID_PO: int = 12  # Pulsation OFF (PULSTO)

# Voice pair assignments (verified from OFFSET macro + label numbers in ALSOUN.MAC)
# Label 1→voice 0, 2→voice 1, 3→voice 2, 4→voice 3, 5→voice 4, 6→voice 5, 7→voice 6, 8→voice 7
const VOICE_MAP: Dictionary = {
	0: 4,   # LO (label 5) → voice 4 (P2-ch1)
	1: 1,   # EX (label 2) → voice 1 (P1-ch2)
	2: 2,   # LA (label 3) → voice 2 (P1-ch3)
	3: 5,   # PU (label 6) → voice 5 (P2-ch2)
	4: 3,   # WP (label 4) → voice 3 (P1-ch4)
	5: 0,   # DI (label 1) → voice 0 (P1-ch1)
	6: 5,   # T2 (label 6) → voice 5 (P2-ch2)
	7: 5,   # T3 (label 6) → voice 5 (P2-ch2)
	8: 7,   # ES (label 8) → voice 7 (P2-ch4)
	9: 6,   # EL (label 7) → voice 6 (P2-ch3)
	10: 0,  # SL (label 1) → voice 0 (P1-ch1)
	11: 0,  # S3 (label 1) → voice 0 (P1-ch1)
	12: 5,  # PO (label 6) → voice 5 (P2-ch2)
}

# ========================================================================
# SOUND DATA — verified against ALSOUN.MAC source (hex values)
# Format: Array of [start_value, frame_count, change, step_count]
# ========================================================================

const SOUNDS: Dictionary = {
	0: {  # LO - Cursor Move (LO5F/LO5A)
		"freq": [[0x0F, 4, 0, 1]],
		"ctrl": [[0xA2, 4, 0x40, 1]],
	},
	1: {  # EX - Enemy Explosion (EX2F/EX2A)
		"freq": [[0x01, 8, 2, 0x10]],
		"ctrl": [[0x86, 0x20, 0, 4]],
	},
	2: {  # LA - Player Fire (LA3F/LA3A)
		"freq": [[0x10, 1, 7, 0x20]],
		"ctrl": [[0xA2, 1, 0xF8, 0x20]],
	},
	3: {  # PU - Pulsation ON (PU6F/PU6A)
		"freq": [[0xB0, 2, 0, 0xFF]],
		"ctrl": [[0xC8, 1, 2, 0xFF], [0xC8, 1, 2, 0xFF]],
	},
	4: {  # WP - Bonus Score (WP4F/WP4A)
		"freq": [
			[0x40, 1, 0, 1], [0x40, 1, 0xFF, 0x40], [0x30, 1, 0xFF, 0x30],
			[0x20, 1, 0xFF, 0x20], [0x18, 1, 0xFF, 0x18], [0x14, 1, 0xFF, 0x14],
			[0x12, 1, 0xFF, 0x12], [0x10, 1, 0xFF, 0x10],
		],
		"ctrl": [[0xA8, 0x93, 0, 2]],
	},
	5: {  # DI - Player Dies (DI1F/DI1A)
		"freq": [[8, 4, 0x20, 0x0A], [8, 4, 1, 9], [0x10, 0x0D, 4, 0x0C]],
		"ctrl": [[8, 4, 0, 0x0A], [0x68, 4, 0, 9], [0x68, 0x12, 0xFF, 9]],
	},
	6: {  # T2 - Thrust in Tube (T26F/T26A)
		"freq": [[0xC0, 2, 0xFF, 0xFF]],
		"ctrl": [[0x28, 2, 0, 0xF0]],
	},
	7: {  # T3 - Thrust in Space (T36F/T36A)
		"freq": [[0x10, 0x0B, 1, 0x40]],
		"ctrl": [[0x86, 0x40, 0, 0x0B]],
	},
	8: {  # ES - Enemy Shot (ES8F/ES8A)
		"freq": [[0, 3, 2, 9]],
		"ctrl": [[8, 3, 0xFF, 9]],
	},
	9: {  # EL - Enemy Line Destroyed (EL7F/EL7A)
		"freq": [[0x80, 1, 0xE8, 5]],
		"ctrl": [[0xA1, 1, 1, 5]],
	},
	10: {  # SL - Slam (SL1F/SL1A)
		"freq": [[0x18, 4, 0, 0xFF]],
		"ctrl": [[0xAF, 4, 0, 0xFF]],
	},
	11: {  # S3 - 3-Second Warning (S31F/S31A)
		"freq": [[0x20, 0x80, 0, 3]],
		"ctrl": [[0xA8, 0x40, 0xF8, 6]],
	},
	12: {  # PO - Pulsation OFF (PO6F/PO6A — both point to same silence data)
		"freq": [[0xC0, 1, 0, 1]],
		"ctrl": [[0xC0, 1, 0, 1]],
	},
}

# ========================================================================
# CHANNEL STATE — sequence interpreter per logical channel
# ========================================================================

var _ch_active: Array[bool] = []    # Channel active flag
var _ch_seqs: Array[Array] = []     # Sequence data for this channel
var _ch_idx: Array[int] = []        # Current segment index
var _ch_current: Array[int] = []    # Current register value (0-255)
var _ch_frames: Array[int] = []     # Frame counter until next step
var _ch_count: Array[int] = []      # Steps remaining in current segment
var _ch_change: Array[int] = []     # Change delta per step
var _ch_frcnt: Array[int] = []      # Frame count per step (saved from segment)
var _ch_is_ctrl: Array[bool] = []   # True = AUDC channel (amplitude-only change fix)

# ========================================================================
# VOICE STATE — audio oscillator per POKEY channel pair
# ========================================================================

const NUM_VOICES: int = 8
var _voice_phase: Array[float] = []
var _voice_poly4: Array[int] = []   # 4-bit LFSR (period 15) — metallic noise
var _voice_poly5: Array[int] = []   # 5-bit LFSR (period 31) — noise filter
var _voice_lfsr: Array[int] = []    # 17-bit LFSR (period 131071) — white noise

# Audio
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _frame_accum: float = 0.0  # Accumulator for 60 Hz sequence updates
var _muted: bool = false  # Attract mode mute


func _ready() -> void:
	# Initialize 16 channels (8 voice pairs × 2 channels each)
	for i in 16:
		_ch_active.append(false)
		_ch_seqs.append([])
		_ch_idx.append(0)
		_ch_current.append(0)
		_ch_frames.append(0)
		_ch_count.append(0)
		_ch_change.append(0)
		_ch_frcnt.append(0)
		_ch_is_ctrl.append(i % 2 == 1)  # Odd channels are AUDC

	for i in NUM_VOICES:
		_voice_phase.append(0.0)
		_voice_poly4.append(0x0F)   # 4-bit LFSR initial state (all 1s)
		_voice_poly5.append(0x1F)   # 5-bit LFSR initial state (all 1s)
		_voice_lfsr.append(0x1FFFF) # 17-bit LFSR initial state (all 1s)

	# Create AudioStreamPlayer with generator
	_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.05  # 50ms buffer
	_player.stream = stream
	_player.bus = "Master"
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return

	# Fill audio buffer
	var frames_available: int = _playback.get_frames_available()
	if frames_available <= 0:
		return

	var samples_per_tick: float = MIX_RATE / FRAME_HZ  # ~735 samples per 60Hz tick

	for _s in frames_available:
		# Advance sequence interpreter at 60 Hz
		_frame_accum += 1.0
		if _frame_accum >= samples_per_tick:
			_frame_accum -= samples_per_tick
			_tick_sequences()

		# Synthesize and mix all active voices
		var mix: float = 0.0
		for v in NUM_VOICES:
			var freq_ch: int = v * 2
			var ctrl_ch: int = v * 2 + 1
			if not _ch_active[freq_ch] and not _ch_active[ctrl_ch]:
				continue

			var audf: int = _ch_current[freq_ch]
			var audc: int = _ch_current[ctrl_ch]
			var volume: float = float(audc & 0x0F) / 15.0
			if volume < 0.001:
				continue

			var freq: float = POKEY_DIV / (2.0 * float(audf + 1))

			# Advance oscillator phase
			_voice_phase[v] += freq / float(MIX_RATE)
			if _voice_phase[v] >= 1.0:
				_voice_phase[v] -= floorf(_voice_phase[v])
				# Clock all polynomial counters on phase wrap
				_clock_polys(v)

			# Generate waveform based on POKEY distortion mode (AUDC bits 7-5)
			# Bit 5 (0x20): Pure tone — square wave output
			# Bit 7 (0x80): Use 4-bit poly instead of 17-bit for noise
			# Bit 6 (0x40): Bypass 5-bit poly filter
			var sample: float
			if audc & 0x20:
				# Pure tone (D5=1): square wave
				sample = 1.0 if _voice_phase[v] < 0.5 else -1.0
			else:
				# Noise mode (D5=0): poly counter output
				var noise_bit: int
				if audc & 0x80:
					# D7=1: use 4-bit poly (metallic, period 15)
					noise_bit = _voice_poly4[v] & 1
				else:
					# D7=0: use 17-bit poly (white noise, period 131071)
					noise_bit = _voice_lfsr[v] & 1
				if not (audc & 0x40):
					# D6=0: AND with 5-bit poly filter (muffled/tonal noise)
					noise_bit = noise_bit & (_voice_poly5[v] & 1)
				sample = 1.0 if noise_bit != 0 else -1.0

			mix += sample * volume

		# Scale mix to prevent clipping (up to 8 voices at full volume)
		mix *= 0.15
		_playback.push_frame(Vector2(mix, mix))


## Start a sound effect. Overwrites any sound on the same voice channels.
func play_sound(sound_id: int) -> void:
	if _muted:
		return
	if not SOUNDS.has(sound_id):
		return

	var voice: int = VOICE_MAP[sound_id]
	var data: Dictionary = SOUNDS[sound_id]
	var freq_ch: int = voice * 2
	var ctrl_ch: int = voice * 2 + 1

	# Load frequency channel
	if data.has("freq"):
		_load_channel(freq_ch, data.freq)

	# Load control channel
	if data.has("ctrl"):
		_load_channel(ctrl_ch, data.ctrl)


## Stop a sound by voice (deactivates both channels).
func stop_voice(voice: int) -> void:
	var freq_ch: int = voice * 2
	var ctrl_ch: int = voice * 2 + 1
	_ch_active[freq_ch] = false
	_ch_active[ctrl_ch] = false
	_ch_current[freq_ch] = 0
	_ch_current[ctrl_ch] = 0


## Stop all sounds (INISOU).
func stop_all() -> void:
	for i in 16:
		_ch_active[i] = false
		_ch_current[i] = 0
	for v in NUM_VOICES:
		_voice_phase[v] = 0.0


## Set attract mode mute (SNDON checks QSTATUS bit 7).
func set_attract_mute(mute: bool) -> void:
	_muted = mute
	if mute:
		stop_all()


# ========================================================================
# SEQUENCE INTERPRETER — implements MODSND from ALSOUN.MAC
# ========================================================================

func _load_channel(ch: int, seqs: Array) -> void:
	_ch_seqs[ch] = seqs
	_ch_idx[ch] = 0
	_ch_active[ch] = true
	# Load first segment immediately (skip the SNDON 1-frame delay)
	if seqs.size() > 0:
		var seg: Array = seqs[0]
		_ch_current[ch] = seg[0]
		_ch_frcnt[ch] = seg[1]
		_ch_frames[ch] = seg[1]
		_ch_change[ch] = seg[2]
		_ch_count[ch] = seg[3]


func _tick_sequences() -> void:
	for ch in 16:
		if not _ch_active[ch]:
			continue

		# Decrement frame counter
		if _ch_frames[ch] > 0:
			_ch_frames[ch] -= 1
			if _ch_frames[ch] > 0:
				continue

		# Frame counter expired — DEC COUNT then check.
		# Original 6502: DEC COUNT; BNE apply_change (branch if not zero).
		# COUNT=N means N-1 change applications; when COUNT reaches 0, advance segment.
		_ch_count[ch] -= 1
		if _ch_count[ch] > 0:
			# Apply change with 8-bit wrapping
			var old_val: int = _ch_current[ch]
			var new_val: int = (old_val + _ch_change[ch]) & 0xFF
			# MODSND amplitude-only fix: for AUDC channels (odd), preserve distortion nibble
			if _ch_is_ctrl[ch]:
				new_val = (old_val & 0xF0) | (new_val & 0x0F)
			_ch_current[ch] = new_val
			_ch_frames[ch] = _ch_frcnt[ch]
		else:
			# Segment exhausted — advance to next segment
			_ch_idx[ch] += 1
			if _ch_idx[ch] >= _ch_seqs[ch].size():
				# No more segments — deactivate channel
				_ch_active[ch] = false
				_ch_current[ch] = 0
			else:
				var seg: Array = _ch_seqs[ch][_ch_idx[ch]]
				_ch_current[ch] = seg[0]
				_ch_frcnt[ch] = seg[1]
				_ch_frames[ch] = seg[1]
				_ch_change[ch] = seg[2]
				_ch_count[ch] = seg[3]


# ========================================================================
# POLYNOMIAL COUNTER NOISE GENERATORS — matches POKEY hardware
# See HARDWARE_REGISTERS.md. POKEY uses three poly counters for noise:
#   4-bit (period 15): taps at bits 0,1 — metallic/rhythmic noise
#   5-bit (period 31): taps at bits 0,2 — used as noise filter
#  17-bit (period 131071): taps at bits 0,5 — white noise
# ========================================================================

func _clock_polys(voice: int) -> void:
	# 4-bit LFSR: feedback = bit0 XOR bit1, shift right, insert at bit 3
	var p4: int = _voice_poly4[voice]
	var b4: int = ((p4 >> 0) ^ (p4 >> 1)) & 1
	_voice_poly4[voice] = (p4 >> 1) | (b4 << 3)

	# 5-bit LFSR: feedback = bit0 XOR bit2, shift right, insert at bit 4
	var p5: int = _voice_poly5[voice]
	var b5: int = ((p5 >> 0) ^ (p5 >> 2)) & 1
	_voice_poly5[voice] = (p5 >> 1) | (b5 << 4)

	# 17-bit LFSR: feedback = bit0 XOR bit5, shift right, insert at bit 16
	var p17: int = _voice_lfsr[voice]
	var b17: int = ((p17 >> 0) ^ (p17 >> 5)) & 1
	_voice_lfsr[voice] = (p17 >> 1) | (b17 << 16)
