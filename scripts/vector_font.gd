extends Node
## Vector beam font matching original Tempest arcade (ANVGAN.MAC).
## See DATA_ASSETS.md § Character Generator.
##
## Each character is an array of [dx, dy, draw] tuples in VG units.
## Original coordinate system: Y-up, 24x24 unit cell, 16 units drawable + 8 advance.
## When drawing, Y is negated for Godot's Y-down screen space.

# Character cell dimensions in VG units
const CELL_WIDTH: int = 24
const CELL_HEIGHT: int = 24

# Character data: [dx, dy, draw_flag] per stroke segment.
# dx/dy are relative moves in VG units. draw_flag true = beam on (draw line).
# Each character returns to baseline (dy sums to 0) and advances 24 units (dx sums to 24).
# Y-up coordinate system (negated at draw time for Godot).

var CHARS: Dictionary = {}


func _ready() -> void:
	_build_chars()


func _build_chars() -> void:
	# Letters A-Z
	CHARS["A"] = [
		[0, 16, true], [8, 8, true], [8, -8, true], [0, -16, true],
		[-16, 8, false], [16, 0, true], [8, -8, false],
	]
	CHARS["B"] = [
		[0, 24, true], [12, 0, true], [4, -4, true], [0, -4, true],
		[-4, -4, true], [-12, 0, true], [12, 0, false], [4, -4, true],
		[0, -4, true], [-4, -4, true], [-12, 0, true], [24, 0, false],
	]
	CHARS["C"] = [
		[0, 24, true], [16, 0, true], [-16, -24, false], [16, 0, true],
		[8, 0, false],
	]
	CHARS["D"] = [
		[0, 24, true], [8, 0, true], [8, -8, true], [0, -8, true],
		[-8, -8, true], [-8, 0, true], [24, 0, false],
	]
	CHARS["E"] = [
		[0, 24, true], [16, 0, true], [-4, -12, false], [-12, 0, true],
		[0, -12, false], [16, 0, true], [8, 0, false],
	]
	CHARS["F"] = [
		[0, 24, true], [16, 0, true], [-4, -12, false], [-12, 0, true],
		[0, -12, false], [24, 0, false],
	]
	CHARS["G"] = [
		[0, 24, true], [16, 0, true], [0, -8, true], [-8, -8, false],
		[8, 0, true], [0, -8, true], [-16, 0, true], [24, 0, false],
	]
	CHARS["H"] = [
		[0, 24, true], [0, -12, false], [16, 0, true], [0, 12, false],
		[0, -24, true], [8, 0, false],
	]
	CHARS["I"] = [
		[16, 0, true], [-8, 0, false], [0, 24, true], [8, 0, false],
		[-16, 0, true], [24, -24, false],
	]
	CHARS["J"] = [
		[0, 8, false], [8, -8, true], [8, 0, true], [0, 24, true],
		[8, -24, false],
	]
	CHARS["K"] = [
		[0, 24, true], [12, 0, false], [-12, -12, true], [12, -12, true],
		[12, 0, false],
	]
	CHARS["L"] = [
		[0, 24, false], [0, -24, true], [16, 0, true], [8, 0, false],
	]
	CHARS["M"] = [
		[0, 24, true], [8, -8, true], [8, 8, true], [0, -24, true],
		[8, 0, false],
	]
	CHARS["N"] = [
		[0, 24, true], [16, -24, true], [0, 24, true], [8, -24, false],
	]
	CHARS["O"] = [
		[0, 24, true], [16, 0, true], [0, -24, true], [-16, 0, true],
		[24, 0, false],
	]
	CHARS["P"] = [
		[0, 24, true], [16, 0, true], [0, -12, true], [-16, 0, true],
		[12, -12, false], [12, 0, false],
	]
	CHARS["Q"] = [
		[0, 24, true], [16, 0, true], [0, -16, true], [-8, -8, true],
		[-8, 0, true], [8, 8, false], [8, -8, true], [8, 0, false],
	]
	CHARS["R"] = [
		[0, 24, true], [16, 0, true], [0, -12, true], [-16, 0, true],
		[4, 0, false], [12, -12, true], [8, 0, false],
	]
	CHARS["S"] = [
		[16, 0, true], [0, 12, true], [-16, 0, true], [0, 12, true],
		[16, 0, true], [8, -24, false],
	]
	CHARS["T"] = [
		[8, 0, false], [0, 24, true], [-8, 0, false], [16, 0, true],
		[8, -24, false],
	]
	CHARS["U"] = [
		[0, 24, false], [0, -24, true], [16, 0, true], [0, 24, true],
		[8, -24, false],
	]
	CHARS["V"] = [
		[0, 24, false], [8, -24, true], [8, 24, true], [8, -24, false],
	]
	CHARS["W"] = [
		[0, 24, false], [0, -24, true], [8, 8, true], [8, -8, true],
		[0, 24, true], [8, -24, false],
	]
	CHARS["X"] = [
		[16, 24, true], [-16, 0, false], [16, -24, true], [8, 0, false],
	]
	CHARS["Y"] = [
		[8, 0, false], [0, 16, true], [-8, 8, true], [16, 0, false],
		[-8, -8, true], [16, -16, false],
	]
	CHARS["Z"] = [
		[0, 24, false], [16, 0, true], [-16, -24, true], [16, 0, true],
		[8, 0, false],
	]

	# Digits 0-9
	CHARS["0"] = CHARS["O"]  # Same shape as O in original
	CHARS["1"] = [
		[8, 0, false], [0, 24, true], [16, -24, false],
	]
	CHARS["2"] = [
		[0, 24, false], [16, 0, true], [0, -12, true], [-16, 0, true],
		[0, -12, true], [16, 0, true], [8, 0, false],
	]
	CHARS["3"] = [
		[16, 0, true], [0, 24, true], [-16, 0, true], [0, -12, false],
		[16, 0, true], [8, -12, false],
	]
	CHARS["4"] = [
		[0, 24, false], [0, -12, true], [16, 0, true], [0, 12, false],
		[0, -24, true], [8, 0, false],
	]
	CHARS["5"] = CHARS["S"]  # Same shape as S in original
	CHARS["6"] = [
		[0, 12, false], [16, 0, true], [0, -12, true], [-16, 0, true],
		[0, 24, true], [24, -24, false],
	]
	CHARS["7"] = [
		[0, 24, false], [16, 0, true], [0, -24, true], [8, 0, false],
	]
	CHARS["8"] = [
		[16, 0, true], [0, 24, true], [-16, 0, true], [0, -24, true],
		[0, 12, false], [16, 0, true], [8, -12, false],
	]
	CHARS["9"] = [
		[16, 0, false], [0, 24, true], [-16, 0, true], [0, -12, true],
		[16, 0, true], [8, -12, false],
	]

	# Special characters
	CHARS[" "] = [
		[24, 0, false],
	]
	CHARS["-"] = [
		[0, 12, false], [16, 0, true], [8, -12, false],
	]
	CHARS["."] = [
		[4, 0, false], [4, 0, true], [0, 4, true], [-4, 0, true], [0, -4, true], [20, 0, false],
	]
	CHARS["("] = [
		[8, 0, false], [-4, 8, true], [0, 8, true], [4, 8, true], [16, -24, false],
	]
	CHARS[")"] = [
		[8, 0, false], [4, 8, true], [0, 8, true], [-4, 8, true], [16, -24, false],
	]
	# Ampersand — not in original ANVGAN.MAC, designed to match vector font style
	CHARS["&"] = [
		[16, 4, false],         # move to bottom-right start
		[-12, 8, true],         # diagonal up-left to middle crossing
		[0, 8, true],           # up left side
		[4, 4, true],           # up-right curve to top
		[4, 0, true],           # top horizontal
		[0, -4, true],          # down from top
		[-8, -8, true],         # diagonal cross back to center
		[-4, -8, true],         # continue down-left
		[4, -4, true],          # curve to bottom
		[12, 4, true],          # sweep right and up
		[8, -4, false],         # advance
	]
	# Copyright symbol © — circle with C inside, matching original VG shape
	CHARS["©"] = [
		# Octagonal circle (radius ~10, centered at 12,12)
		[8, 4, false],          # move to bottom-center
		[6, 1, true],           # bottom-right arc
		[2, 7, true],           # right side
		[-2, 7, true],          # top-right arc
		[-6, 1, true],          # top-center
		[-6, -1, true],         # top-left arc
		[-2, -7, true],         # left side
		[2, -7, true],          # bottom-left arc
		[6, -1, true],          # close circle
		# C letter inside
		[3, 3, false],          # move to bottom-right of C
		[-6, 0, true],          # bottom horizontal
		[0, 10, true],          # left vertical
		[6, 0, true],           # top horizontal
		[13, -17, false],       # advance to next character
	]


## Draw a string of text using vector beam lines.
## pos = baseline-left position. Y-up is negated for Godot's Y-down.
## Returns the total advance width in pixels for the drawn string.
func draw_text(ci: CanvasItem, text: String, pos: Vector2, color: Color,
		scale: float = 1.0, line_width: float = 2.0) -> float:
	var cursor: Vector2 = pos
	var upper: String = text.to_upper()

	for ch in upper:
		if ch not in CHARS:
			# Unknown character — advance one space
			cursor.x += CELL_WIDTH * scale
			continue

		var strokes: Array = CHARS[ch]
		var beam: Vector2 = cursor

		for s in strokes:
			var dx: float = float(s[0]) * scale
			var dy: float = float(s[1]) * scale
			var new_beam: Vector2 = beam + Vector2(dx, -dy)  # Negate Y for Godot
			if s[2]:
				ci.draw_line(beam, new_beam, color, line_width)
			beam = new_beam

		cursor = beam  # Advance to next character position

	return cursor.x - pos.x


## Measure the pixel width of a string at a given scale without drawing.
func measure_text(text: String, scale: float = 1.0) -> float:
	var width: float = 0.0
	var upper: String = text.to_upper()

	for ch in upper:
		if ch not in CHARS:
			width += CELL_WIDTH * scale
			continue
		var strokes: Array = CHARS[ch]
		var dx_sum: float = 0.0
		for s in strokes:
			dx_sum += float(s[0])
		width += dx_sum * scale

	return width


## Draw text centered horizontally at a given position.
func draw_text_centered(ci: CanvasItem, text: String, center_pos: Vector2,
		color: Color, scale: float = 1.0, line_width: float = 2.0) -> void:
	var w: float = measure_text(text, scale)
	var pos: Vector2 = Vector2(center_pos.x - w * 0.5, center_pos.y)
	draw_text(ci, text, pos, color, scale, line_width)


## Draw text right-aligned at a given position.
func draw_text_right(ci: CanvasItem, text: String, right_pos: Vector2,
		color: Color, scale: float = 1.0, line_width: float = 2.0) -> void:
	var w: float = measure_text(text, scale)
	var pos: Vector2 = Vector2(right_pos.x - w, right_pos.y)
	draw_text(ci, text, pos, color, scale, line_width)
