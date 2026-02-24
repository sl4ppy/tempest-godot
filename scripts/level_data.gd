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

# Max active invaders (constant for all waves)
const MAX_INVADERS: int = 6


## Get the well shape index for a given wave number.
func get_well_shape(wave: int) -> int:
	return WELL_SEQUENCE[(wave - 1) % 16]


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
