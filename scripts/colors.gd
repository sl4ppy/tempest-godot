extends Node
## Color palette matching original Atari vector monitor colors.
## See DATA_ASSETS.md for palette definitions.

# 16-color palette indexed 0-15
const PALETTE: Array[Color] = [
	Color(1.0, 1.0, 1.0),    # 0  WHITE
	Color(1.0, 1.0, 0.0),    # 1  YELLOW  — player ship (PCHCOL)
	Color(0.7, 0.0, 1.0),    # 2  PURPLE
	Color(1.0, 0.0, 0.0),    # 3  RED
	Color(0.0, 1.0, 0.8),    # 4  TURQOI  — pulsar idle
	Color(0.0, 1.0, 0.0),    # 5  GREEN
	Color(0.0, 0.4, 1.0),    # 6  BLUE
	Color(0.0, 0.0, 1.0),    # 7  BLULET  — UI text (pure blue, shader adds glow)
	Color(0.0, 1.0, 1.0),    # 8  PSHCTR  — player shot center
	Color(1.0, 1.0, 1.0),    # 9  PDIWHI  — death explosion white
	Color(1.0, 1.0, 0.0),    # 10 PDIYEL  — death explosion yellow
	Color(1.0, 0.0, 0.0),    # 11 PDIRED  — death explosion red
	Color(0.0, 0.8, 0.4),    # 12 NYMCOL  — spiker nymph
	Color(0.5, 0.5, 0.5),    # 13 (reserved)
	Color(0.5, 0.5, 0.5),    # 14 (reserved)
	Color(1.0, 1.0, 1.0),    # 15 FLASH   — cycling
]

# Named constants for readability
const WHITE: int = 0
const YELLOW: int = 1
const PURPLE: int = 2
const RED: int = 3
const TURQOI: int = 4
const GREEN: int = 5
const BLUE: int = 6
const BLULET: int = 7
const PSHCTR: int = 8
const PDIWHI: int = 9
const PDIYEL: int = 10
const PDIRED: int = 11
const NYMCOL: int = 12

# Well colors per wave group — approximate from original color RAM cycling
# See ENTITIES.md § Color System
const WELL_COLORS: Array[int] = [
	6, 3, 5, 2, 4, 6, 3, 5, 2, 4, 6, 3, 5, 2, 4, 6,
]


func get_color(index: int) -> Color:
	return PALETTE[index % 16]


func get_well_color(wave: int) -> Color:
	return PALETTE[WELL_COLORS[(wave - 1) % 16]]
