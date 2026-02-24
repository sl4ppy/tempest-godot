extends Node2D
## HUD overlay — score, lives, high score, wave number, messages.
## Supports multiple display modes for different game states.
## Uses VectorFont autoload for authentic Tempest arcade vector beam text.

# Display modes
enum Mode {
	GAMEPLAY,     # Normal score/lives/wave
	WAVE_SELECT,  # "Rate Yourself" wave picker
	HIGH_SCORES,  # High score ladder display
	INITIALS,     # Initials entry after game over
}

var mode: Mode = Mode.GAMEPLAY

# Gameplay state
var score: int = 0
var high_score: int = 0
var lives: int = 4
var wave: int = 1
var message: String = ""

# Wave select state
var select_waves: Array[int] = []  # Available waves to choose from
var select_cursor: int = 0  # Currently highlighted wave index
var select_timer: int = 0  # Countdown in seconds

# High score state
var score_table: Array[Dictionary] = []  # {score: int, initials: String}
var highlight_idx: int = -1  # Row to highlight (-1 = none)

# Initials entry state
var entry_initials: String = "   "  # Current 3-char initials
var entry_slot: int = 0  # Active slot (0, 1, 2)
var entry_score: int = 0  # Score being entered
var entry_char: int = 0  # Current character index (0=A, 25=Z, 26=space)

# Scale constants
const TEXT_SCALE: float = 0.85
const MSG_SCALE: float = 1.2
const TITLE_SCALE: float = 1.5
const TABLE_SCALE: float = 0.75
const LINE_WIDTH: float = 1.5
const MSG_LINE_WIDTH: float = 2.0

# Character cycling for initials entry
const INITIAL_CHARS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ "


func _draw() -> void:
	match mode:
		Mode.GAMEPLAY:
			_draw_gameplay()
		Mode.WAVE_SELECT:
			_draw_wave_select()
		Mode.HIGH_SCORES:
			_draw_high_scores()
		Mode.INITIALS:
			_draw_initials_entry()


func _draw_gameplay() -> void:
	var color: Color = Colors.get_color(Colors.BLULET)

	# Score — top left
	VectorFont.draw_text(self, str(score), Vector2(20, 30), color, TEXT_SCALE, LINE_WIDTH)

	# High score — top center
	VectorFont.draw_text_centered(self, str(high_score), Vector2(512, 30), color, TEXT_SCALE, LINE_WIDTH)

	# Lives — top right
	VectorFont.draw_text_right(self, str(lives), Vector2(1000, 30), color, TEXT_SCALE, LINE_WIDTH)

	# Wave — bottom center
	VectorFont.draw_text_centered(self, "WAVE " + str(wave), Vector2(512, 1000), color, TEXT_SCALE, LINE_WIDTH)

	# Center message (GAME OVER, PRESS START, bonus, etc.)
	if message != "":
		var msg_color: Color = Colors.get_color(Colors.WHITE)
		VectorFont.draw_text_centered(self, message, Vector2(512, 520), msg_color, MSG_SCALE, MSG_LINE_WIDTH)


func _draw_wave_select() -> void:
	var title_color: Color = Colors.get_color(Colors.RED)
	var text_color: Color = Colors.get_color(Colors.BLULET)
	var highlight_color: Color = Colors.get_color(Colors.YELLOW)
	var white: Color = Colors.get_color(Colors.WHITE)

	# Title
	VectorFont.draw_text_centered(self, "RATE YOURSELF", Vector2(512, 120), title_color, TITLE_SCALE, 2.5)

	# Instructions
	VectorFont.draw_text_centered(self, "SPIN KNOB TO CHANGE", Vector2(512, 200), text_color, TEXT_SCALE, LINE_WIDTH)
	VectorFont.draw_text_centered(self, "PRESS FIRE TO SELECT", Vector2(512, 240), text_color, TEXT_SCALE, LINE_WIDTH)

	# Wave grid — 2 rows of 8
	var start_x: float = 180.0
	var spacing: float = 100.0
	var y_row1: float = 400.0
	var y_row2: float = 480.0

	for i in select_waves.size():
		var col: int = i % 8
		@warning_ignore("integer_division")
		var row: int = i / 8
		var x: float = start_x + float(col) * spacing
		var y: float = y_row1 if row == 0 else y_row2
		var is_selected: bool = (i == select_cursor)
		var c: Color = highlight_color if is_selected else white
		var w: float = 2.0 if is_selected else LINE_WIDTH
		var s: float = 1.0 if is_selected else TEXT_SCALE
		VectorFont.draw_text_centered(self, str(select_waves[i]), Vector2(x, y), c, s, w)

		# Draw bracket cursor around selected wave
		if is_selected:
			var tw: float = VectorFont.measure_text(str(select_waves[i]), s)
			var lx: float = x - tw * 0.5 - 8.0
			var rx: float = x + tw * 0.5 + 8.0
			var ty: float = y - 24.0 * s
			var by: float = y + 4.0
			draw_line(Vector2(lx, ty), Vector2(lx, by), highlight_color, 1.5)
			draw_line(Vector2(rx, ty), Vector2(rx, by), highlight_color, 1.5)

	# Timer countdown
	if select_timer > 0:
		VectorFont.draw_text_centered(self, str(select_timer), Vector2(512, 600), text_color, MSG_SCALE, MSG_LINE_WIDTH)

	# Score display at top
	VectorFont.draw_text(self, str(score), Vector2(20, 30), text_color, TEXT_SCALE, LINE_WIDTH)
	VectorFont.draw_text_centered(self, str(high_score), Vector2(512, 30), text_color, TEXT_SCALE, LINE_WIDTH)


func _draw_high_scores() -> void:
	var title_color: Color = Colors.get_color(Colors.RED)
	var text_color: Color = Colors.get_color(Colors.BLULET)
	var highlight_color: Color = Colors.get_color(Colors.YELLOW)

	# Title
	VectorFont.draw_text_centered(self, "HIGH SCORES", Vector2(512, 100), title_color, TITLE_SCALE, 2.5)

	# Table
	var y: float = 220.0
	var row_height: float = 55.0
	for i in score_table.size():
		var entry: Dictionary = score_table[i]
		var c: Color = highlight_color if (i == highlight_idx) else text_color
		var rank: String = str(i + 1) + "."
		var sc: String = str(entry.score).pad_zeros(6) if entry.score > 0 else "000000"
		var ini: String = entry.initials if entry.initials != "" else "---"

		VectorFont.draw_text(self, rank, Vector2(250, y), c, TABLE_SCALE, LINE_WIDTH)
		VectorFont.draw_text(self, sc, Vector2(340, y), c, TABLE_SCALE, LINE_WIDTH)
		VectorFont.draw_text(self, ini, Vector2(640, y), c, TABLE_SCALE, LINE_WIDTH)
		y += row_height

	# Message at bottom
	if message != "":
		var white: Color = Colors.get_color(Colors.WHITE)
		VectorFont.draw_text_centered(self, message, Vector2(512, 900), white, MSG_SCALE, MSG_LINE_WIDTH)


func _draw_initials_entry() -> void:
	var title_color: Color = Colors.get_color(Colors.RED)
	var text_color: Color = Colors.get_color(Colors.BLULET)
	var highlight_color: Color = Colors.get_color(Colors.YELLOW)
	var white: Color = Colors.get_color(Colors.WHITE)

	# Title
	VectorFont.draw_text_centered(self, "ENTER YOUR INITIALS", Vector2(512, 120), title_color, TITLE_SCALE, 2.5)

	# Instructions
	VectorFont.draw_text_centered(self, "SPIN KNOB TO CHANGE", Vector2(512, 200), text_color, TEXT_SCALE, LINE_WIDTH)
	VectorFont.draw_text_centered(self, "PRESS FIRE TO SELECT", Vector2(512, 240), text_color, TEXT_SCALE, LINE_WIDTH)

	# Score
	VectorFont.draw_text_centered(self, "SCORE " + str(entry_score), Vector2(512, 340), white, MSG_SCALE, MSG_LINE_WIDTH)

	# Initials display — 3 large characters with active slot highlighted
	var init_x: float = 430.0
	var init_spacing: float = 60.0
	for i in 3:
		var ch: String = entry_initials[i] if i < entry_initials.length() else " "
		var is_active: bool = (i == entry_slot)
		var c: Color = highlight_color if is_active else white
		var s: float = 1.8 if is_active else 1.5
		VectorFont.draw_text(self, ch, Vector2(init_x + float(i) * init_spacing, 480), c, s, 2.5)

		# Underline each slot
		var ux: float = init_x + float(i) * init_spacing
		var uw: float = 24.0 * s
		draw_line(Vector2(ux, 490), Vector2(ux + uw, 490), c, 2.0)

	# High score table below
	var y: float = 580.0
	var row_height: float = 45.0
	for i in mini(score_table.size(), 8):
		var entry: Dictionary = score_table[i]
		var c: Color = highlight_color if (i == highlight_idx) else text_color
		var rank: String = str(i + 1) + "."
		var sc: String = str(entry.score).pad_zeros(6) if entry.score > 0 else "000000"
		var ini: String = entry.initials if entry.initials != "" else "---"

		VectorFont.draw_text(self, rank, Vector2(280, y), c, TABLE_SCALE * 0.8, LINE_WIDTH)
		VectorFont.draw_text(self, sc, Vector2(350, y), c, TABLE_SCALE * 0.8, LINE_WIDTH)
		VectorFont.draw_text(self, ini, Vector2(600, y), c, TABLE_SCALE * 0.8, LINE_WIDTH)
		y += row_height


# --- Public API ---

func update_display(new_score: int, new_lives: int, new_wave: int) -> void:
	score = new_score
	lives = new_lives
	wave = new_wave
	if score > high_score:
		high_score = score
	queue_redraw()


func set_message(msg: String) -> void:
	message = msg
	queue_redraw()


func show_gameplay() -> void:
	mode = Mode.GAMEPLAY
	queue_redraw()


func show_wave_select(waves: Array[int], cursor: int, timer: int) -> void:
	mode = Mode.WAVE_SELECT
	select_waves = waves
	select_cursor = cursor
	select_timer = timer
	queue_redraw()


func show_high_scores(table: Array[Dictionary], highlight: int = -1, msg: String = "") -> void:
	mode = Mode.HIGH_SCORES
	score_table = table
	highlight_idx = highlight
	message = msg
	queue_redraw()


func show_initials_entry(table: Array[Dictionary], initials: String, slot: int,
		sc: int, highlight: int, char_idx: int) -> void:
	mode = Mode.INITIALS
	score_table = table
	entry_initials = initials
	entry_slot = slot
	entry_score = sc
	highlight_idx = highlight
	entry_char = char_idx
	queue_redraw()
