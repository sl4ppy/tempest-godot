extends Node
## Autoloaded singleton. Contains all level/wave data from LEVEL_DATA.md.
## Access as: LevelData.get_wave_params(wave_number)

# Well shape sequence (WELSEQ) — maps wave mod 16 to shape index
# See PLAYFIELD.md Appendix A
const WELL_SEQUENCE: Array[int] = [
	0, 1, 2, 3, 4, 5, 6, 7, 0xD, 9, 8, 0xC, 0xE, 0xF, 0xA, 0xB
]

# Shape names for reference
const SHAPE_NAMES: Array[String] = [
	"Circle", "Square", "Cross", "Peanut", "Key", "Triangle",
	"Clover", "V", "Stairs", "U", "Flat", "Heart",
	"Star", "Waves", "Jagged", "8-shape"
]

# All 16 well shapes — LINEX/LINEZ vertex tables from PLAYFIELD.md Appendix A
# Values are unsigned bytes, 0x80 = center origin
const WELL_SHAPES: Array[Dictionary] = [
	# 0: Circle
	{
		"linex": [0xF0, 0xE7, 0xCF, 0xAA, 0x80, 0x56, 0x31, 0x19, 0x10, 0x19, 0x31, 0x56, 0x80, 0xAA, 0xCF, 0xE7],
		"linez": [0x80, 0xAA, 0xCF, 0xE7, 0xF0, 0xE7, 0xCF, 0xAA, 0x80, 0x56, 0x31, 0x19, 0x10, 0x19, 0x31, 0x56],
		"holeyl": 0x18, "holezl": 0x50, "holzad": 0x40, "planar": false,
	},
	# 1: Square
	{
		"linex": [0xF0, 0xF0, 0xF0, 0xB8, 0x80, 0x48, 0x10, 0x10, 0x10, 0x10, 0x10, 0x48, 0x80, 0xB8, 0xF0, 0xF0],
		"linez": [0x80, 0xB8, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xB8, 0x80, 0x48, 0x10, 0x10, 0x10, 0x10, 0x10, 0x48],
		"holeyl": 0x1C, "holezl": 0x50, "holzad": 0x20, "planar": false,
	},
	# 2: Cross
	{
		"linex": [0xF0, 0xF0, 0xB8, 0xB8, 0x80, 0x48, 0x48, 0x10, 0x10, 0x48, 0x48, 0x80, 0xB8, 0xB8, 0xF0, 0xF0],
		"linez": [0x80, 0xB8, 0xB8, 0xF0, 0xF0, 0xF0, 0xB8, 0xB8, 0x80, 0x48, 0x48, 0x10, 0x10, 0x48, 0x48, 0x80],
		"holeyl": 0x18, "holezl": 0x50, "holzad": 0x40, "planar": false,
	},
	# 3: Peanut
	{
		"linex": [0xEC, 0xD5, 0xB1, 0x90, 0x70, 0x4F, 0x2B, 0x14, 0x14, 0x2B, 0x4F, 0x90, 0xB1, 0xD5, 0xEC, 0xEC],
		"linez": [0x94, 0xB0, 0xB8, 0xA7, 0xA7, 0xB8, 0xB0, 0x94, 0x6C, 0x50, 0x48, 0x59, 0x59, 0x48, 0x50, 0x6C],
		"holeyl": 0x0F, "holezl": 0x68, "holzad": 0x80, "planar": false,
	},
	# 4: Key
	{
		"linex": [0xF0, 0xC0, 0xA0, 0x94, 0x6C, 0x60, 0x40, 0x10, 0x10, 0x40, 0x60, 0x6C, 0x94, 0xA0, 0xC0, 0xF0],
		"linez": [0x96, 0xA3, 0xC5, 0xF0, 0xF0, 0xC5, 0xA3, 0x96, 0x6A, 0x5D, 0x3B, 0x10, 0x10, 0x3B, 0x5D, 0x6A],
		"holeyl": 0x18, "holezl": 0x50, "holzad": 0x40, "planar": false,
	},
	# 5: Triangle
	{
		"linex": [0xD9, 0xC2, 0xAC, 0x97, 0x80, 0x69, 0x52, 0x3C, 0x27, 0x10, 0x35, 0x5A, 0x80, 0xA6, 0xCA, 0xF0],
		"linez": [0x3D, 0x6A, 0x97, 0xC4, 0xF0, 0xC4, 0x97, 0x6A, 0x3D, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10],
		"holeyl": 0x18, "holezl": 0x50, "holzad": 0x40, "planar": false,
	},
	# 6: Clover
	{
		"linex": [0xEA, 0xE0, 0x9C, 0x80, 0x64, 0x20, 0x16, 0x50, 0x16, 0x20, 0x64, 0x80, 0x9C, 0xE0, 0xEA, 0xB0],
		"linez": [0xA0, 0xE0, 0xEA, 0xB0, 0xEA, 0xE0, 0xA0, 0x80, 0x60, 0x20, 0x16, 0x50, 0x16, 0x20, 0x60, 0x80],
		"holeyl": 0x18, "holezl": 0x68, "holzad": 0x70, "planar": false,
	},
	# 7: V (planar)
	{
		"linex": [0x10, 0x1E, 0x2C, 0x3A, 0x48, 0x56, 0x64, 0x70, 0x90, 0x9E, 0xAC, 0xBA, 0xC8, 0xD6, 0xE4, 0xF0],
		"linez": [0xF0, 0xD0, 0xB0, 0x90, 0x70, 0x50, 0x30, 0x10, 0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0],
		"holeyl": 0x18, "holezl": 0xB0, "holzad": 0x60, "planar": true,
	},
	# 8: Stairs (planar)
	{
		"linex": [0x10, 0x10, 0x30, 0x30, 0x50, 0x50, 0x70, 0x70, 0x90, 0x90, 0xB0, 0xB0, 0xD0, 0xD0, 0xF0, 0xF0],
		"linez": [0x90, 0x70, 0x70, 0x50, 0x50, 0x30, 0x30, 0x10, 0x10, 0x30, 0x30, 0x50, 0x50, 0x70, 0x70, 0x90],
		"holeyl": 0x0A, "holezl": 0xA0, "holzad": 0x00, "planar": true,
	},
	# 9: U (planar)
	{
		"linex": [0x10, 0x10, 0x10, 0x10, 0x16, 0x29, 0x46, 0x69, 0x97, 0xBA, 0xD7, 0xEA, 0xF0, 0xF0, 0xF0, 0xF0],
		"linez": [0xF0, 0xCB, 0xA6, 0x80, 0x5C, 0x39, 0x20, 0x12, 0x12, 0x20, 0x39, 0x5C, 0x80, 0xA6, 0xCB, 0xF0],
		"holeyl": 0x18, "holezl": 0x50, "holzad": 0x20, "planar": true,
	},
	# 10: Flat (planar)
	{
		"linex": [0x10, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69, 0x78, 0x87, 0x96, 0xA5, 0xB4, 0xC3, 0xD2, 0xE1, 0xF0],
		"linez": [0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40],
		"holeyl": 0x10, "holezl": 0x90, "holzad": 0x40, "planar": true,
	},
	# 11: Heart
	{
		"linex": [0xDA, 0xA4, 0x87, 0x80, 0x79, 0x5C, 0x26, 0x10, 0x10, 0x20, 0x48, 0x80, 0xB8, 0xE0, 0xF0, 0xF0],
		"linez": [0xE4, 0xE8, 0xB7, 0x80, 0xB7, 0xE8, 0xE4, 0xB2, 0x7A, 0x47, 0x20, 0x10, 0x20, 0x47, 0x7A, 0xB2],
		"holeyl": 0x0F, "holezl": 0x80, "holzad": 0x00, "planar": false,
	},
	# 12: Star
	{
		"linex": [0xB0, 0x80, 0x50, 0x47, 0x18, 0x30, 0x18, 0x47, 0x50, 0x80, 0xB0, 0xB9, 0xE8, 0xD4, 0xE8, 0xB9],
		"linez": [0xE6, 0xD0, 0xE6, 0xB9, 0xAE, 0x80, 0x52, 0x47, 0x14, 0x30, 0x14, 0x47, 0x52, 0x80, 0xAE, 0xB9],
		"holeyl": 0x18, "holezl": 0x20, "holzad": 0xA0, "planar": false,
	},
	# 13: Waves (planar)
	{
		"linex": [0x10, 0x1E, 0x21, 0x28, 0x3C, 0x55, 0x66, 0x73, 0x8D, 0x9A, 0xAB, 0xC4, 0xD8, 0xDF, 0xE2, 0xF0],
		"linez": [0x7E, 0x6A, 0x51, 0x3A, 0x2C, 0x2C, 0x38, 0x4E, 0x4E, 0x38, 0x2C, 0x2C, 0x3A, 0x51, 0x6A, 0x7E],
		"holeyl": 0x0C, "holezl": 0xB0, "holzad": 0x40, "planar": true,
	},
	# 14: Jagged
	{
		"linex": [0x10, 0x24, 0x30, 0x36, 0x3E, 0x49, 0x5A, 0x75, 0x94, 0xA4, 0xAC, 0xBA, 0xDA, 0xE2, 0xEA, 0xF0],
		"linez": [0xC0, 0xA6, 0x8A, 0x6A, 0x4A, 0x2F, 0x14, 0x24, 0x20, 0x39, 0x59, 0x75, 0x72, 0x90, 0xB0, 0xD0],
		"holeyl": 0x14, "holezl": 0x60, "holzad": 0x40, "planar": false,
	},
	# 15: 8-shape (planar)
	{
		"linex": [0x80, 0x70, 0x48, 0x20, 0x10, 0x20, 0x48, 0x70, 0x80, 0x90, 0xB8, 0xE0, 0xF0, 0xE0, 0xB8, 0x90],
		"linez": [0x80, 0x57, 0x48, 0x57, 0x80, 0xA9, 0xBA, 0xA9, 0x80, 0x57, 0x48, 0x57, 0x80, 0xA9, 0xBA, 0xA9],
		"holeyl": 0x0A, "holezl": 0xA0, "holzad": 0x00, "planar": true,
	},
]

# Max active invaders (constant for all waves)
const MAX_INVADERS: int = 6


## Get the well shape index for a given wave number.
func get_well_shape(wave: int) -> int:
	return WELL_SEQUENCE[(wave - 1) % 16]


## Get the well shape data dictionary for a given wave.
func get_well_data(wave: int) -> Dictionary:
	return WELL_SHAPES[get_well_shape(wave)]


## Get invader fire delay in frames for a given wave. See TCHARFR.
func get_fire_delay(wave: int) -> int:
	if wave <= 20:
		return clampi(80 - 3 * (wave - 1), 23, 80)
	elif wave <= 64:
		return 20
	else:
		return 10


## Get max enemy shots (add 1 to get actual max). See TCHAMX.
func get_max_shots(wave: int) -> int:
	if wave <= 9:
		return [1, 1, 1, 2, 3, 2, 2, 3, 3][wave - 1]
	elif wave <= 64:
		return 2
	else:
		return 3


## Get flipper count range [min, max]. See WFLIMI/WFLIMX.
func get_flipper_count(wave: int) -> Vector2i:
	var min_f: int = 1 if wave <= 4 else 0
	var max_f: int
	if wave <= 4:
		max_f = 4
	elif wave <= 16:
		max_f = 5
	elif wave <= 19:
		max_f = 3
	elif wave <= 25:
		max_f = 4
	else:
		max_f = 5
	return Vector2i(min_f, max_f)


## Get tanker count range [min, max]. See WTANMI/WTANMX.
func get_tanker_count(wave: int) -> Vector2i:
	var min_t: int
	var max_t: int
	if wave <= 4:
		min_t = [0, 0, 1, 0][wave - 1]
		max_t = [0, 0, 1, 0, 1][mini(wave - 1, 4)]
	elif wave <= 16:
		min_t = 1; max_t = 2
	elif wave <= 26:
		min_t = 1; max_t = 1
	elif wave <= 32:
		min_t = 1; max_t = 1
	elif wave <= 44:
		min_t = 1; max_t = 2
	else:
		min_t = 1; max_t = 3
	return Vector2i(min_t, max_t)


## Get total enemy count (nymphs) for a wave. See TNYMMX.
func get_nymph_count(wave: int) -> int:
	if wave <= 16:
		return [10, 12, 15, 17, 20, 22, 20, 24, 27, 29, 27, 24, 26, 28, 30, 27][wave - 1]
	elif wave <= 26:
		return 20 + (wave - 17)
	elif wave <= 39:
		return 27
	elif wave <= 48:
		return 29 + (wave - 40)
	elif wave <= 64:
		return 31 + (wave - 49)
	elif wave <= 80:
		return 35 + (wave - 65)
	else:
		return 43 + (wave - 81)


## Base invader speed (signed, negative = toward player). See TINVIN.
func get_invader_speed(wave: int) -> int:
	if wave <= 8:
		return [-44, -49, -54, -59, -64, -69, -74, -79][wave - 1]
	elif wave <= 16:
		return [-81, -84, -84, -84, -88, -92, -96, -96][wave - 9]
	elif wave <= 25:
		return -81 - 3 * (wave - 17)
	elif wave <= 32:
		return -99 - 3 * (wave - 26)
	elif wave <= 39:
		return -108 - 3 * (wave - 33)
	elif wave <= 48:
		return -110 - (wave - 40)
	elif wave <= 64:
		return -120 - (wave - 49)
	elif wave % 2 == 1:
		return -160
	else:
		return -191


## Spiker count range [min, max]. See WSPIMI/WSPIMX.
func get_spiker_count(wave: int) -> Vector2i:
	if wave <= 3:
		return Vector2i(0, 0)
	elif wave <= 5:
		return Vector2i(1, 3) if wave == 5 else Vector2i(1, 2)
	elif wave <= 10:
		return Vector2i(2, 4)
	elif wave <= 16:
		return Vector2i(2, 3)
	elif wave <= 19:
		return Vector2i(0, 0)
	elif wave <= 25:
		return Vector2i(1, 2)
	elif wave <= 26:
		return Vector2i(1, 1)
	elif wave <= 32:
		return Vector2i(1, 2)
	else:
		return Vector2i(1, 1)


## Pulsar count range [min, max]. See WPULMI/WPULMX.
func get_pulsar_count(wave: int) -> Vector2i:
	if wave <= 16:
		return Vector2i(0, 0)
	elif wave == 17:
		return Vector2i(2, 5)
	elif wave == 18:
		return Vector2i(2, 3)
	elif wave <= 32:
		return Vector2i(2, 2)
	else:
		return Vector2i(1, 3)


## Fuseball count range [min, max]. See WFUSMI/WFUSMX.
func get_fuseball_count(wave: int) -> Vector2i:
	if wave <= 10:
		return Vector2i(0, 0)
	elif wave <= 16:
		return Vector2i(1, 1)
	elif wave <= 21:
		return Vector2i(0, 0)
	elif wave <= 25:
		return Vector2i(1, 1)
	elif wave == 26:
		return Vector2i(0, 0)
	elif wave <= 32:
		return Vector2i(1, 1)
	elif wave <= 39:
		return Vector2i(1, 4)
	else:
		return Vector2i(1, 3)


# CAM script assignment per well shape (wave mod 16). See CAMWAV / TZANDF.
const CAM_BY_SHAPE: Array[String] = [
	"NOJUMP",  # 0  Circle
	"MOVJMP",  # 1  Square
	"SPIRAL",  # 2  Cross
	"SPIRCH",  # 3  Peanut
	"COWJMP",  # 4  Key
	"MOVJMP",  # 5  Triangle
	"SPIRCH",  # 6  Clover
	"SPIRAL",  # 7  V
	"COWJMP",  # 8  Stairs
	"AVOIDR",  # 9  U
	"SPIRCH",  # 10 Flat
	"SPIRAL",  # 11 Heart
	"COWJMP",  # 12 Star
	"NOJUMP",  # 13 Waves
	"AVOIDR",  # 14 Jagged
	"SPIRCH",  # 15 8-shape
]


## Get flipper CAM script name for a wave. See CAMWAV.
func get_flipper_cam(wave: int) -> String:
	return CAM_BY_SHAPE[get_well_shape(wave)]


## Enemy line height per shape. See TELIHI.
func get_enemy_line_height(wave: int) -> int:
	var shape: int = get_well_shape(wave)
	const ELIHI: Array[int] = [
		0x00, 0x00, 0x00, 0xE0, 0xD8, 0xD4, 0xD0, 0xC8,
		0xC0, 0xB8, 0xB0, 0xA8, 0xA0, 0xA0, 0xA0, 0xA8,
	]
	return ELIHI[shape]


## Pulsar timing/behavior params. See TPULTI/TPUCHD/TPULPO.
func get_pulsar_params(wave: int) -> Dictionary:
	var pultim: int = 4 if wave <= 48 else (6 if wave <= 64 else 8)
	var pulpot: int = 0xA0 if wave <= 64 else 0xC0
	var puchde: int
	if wave <= 17:
		puchde = 40
	elif wave == 18:
		puchde = 20
	elif wave <= 32:
		puchde = 20 if (wave % 2 == 1) else 40
	elif wave <= 39:
		puchde = 20 - (wave - 33)
	else:
		puchde = 20 if (wave % 2 == 0) else 10
	var can_fire: bool = wave >= 60
	return {"pultim": pultim, "pulpot": pulpot, "puchde": puchde, "can_fire": can_fire}


## Top flip rate for chasers. See TWTTFRA.
func get_top_flip_rate(wave: int) -> int:
	return 2 if wave <= 32 else 3


## Tanker cargo type. See WTACAR.
func get_tanker_cargo(wave: int) -> int:
	if wave <= 16:
		return 1  # Flippers
	elif wave <= 32:
		return 1  # Still flippers
	elif wave <= 48:
		return 2  # Pulsars
	else:
		return 3  # Fuseballs


## Spiker speed delta (added to base seed before TIMES8). See TSPIIN.
func get_spiker_speed_delta(wave: int) -> int:
	if wave <= 20:
		return 0
	elif wave <= 32:
		return -48
	elif wave <= 48:
		return -40
	else:
		return -48


## Fuseball flip frequency. See TFUFRQ. Higher = less frequent flips.
func get_fuse_freq(wave: int) -> int:
	if wave <= 16:
		return 220
	elif wave <= 39:
		return 192
	elif wave <= 64:
		return 192 + (wave - 40)
	else:
		return 230


## Fuseball chase mode flag. See TWFUSC. True = chase player, false = random.
func get_fuse_chase(wave: int) -> bool:
	if wave <= 16:
		return false
	elif wave <= 32:
		# Alternates: even waves = 0 (no chase), odd = 40 (chase)
		return (wave % 2 == 0)
	elif wave <= 48:
		# Alternates: even = 40 (chase), odd = $C0 (chase)
		return true
	else:
		return true  # $C0 = always chase


## Consolidated wave parameters dictionary.
func get_wave_params(wave: int) -> Dictionary:
	return {
		"wave": wave,
		"shape": get_well_shape(wave),
		"nymph_count": get_nymph_count(wave),
		"invader_speed": get_invader_speed(wave),
		"flipper_cam": get_flipper_cam(wave),
		"flipper_count": get_flipper_count(wave),
		"tanker_count": get_tanker_count(wave),
		"spiker_count": get_spiker_count(wave),
		"pulsar_count": get_pulsar_count(wave),
		"fuseball_count": get_fuseball_count(wave),
		"fire_delay": get_fire_delay(wave),
		"max_shots": get_max_shots(wave),
		"enemy_line_height": get_enemy_line_height(wave),
		"pulsar_params": get_pulsar_params(wave),
		"top_flip_rate": get_top_flip_rate(wave),
		"tanker_cargo": get_tanker_cargo(wave),
		"charge_speed": get_invader_speed(wave),  # Base seed; actual charge speed computed via TIMES8 in invader_manager
	}
